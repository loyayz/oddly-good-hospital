class_name HospitalSnapshots
extends RefCounted

const FORMAT: String = "oddly-good-hospital.snapshot"
const ROOT: String = "user://hospitals"
const HEADROOM: int = 67108864
const DATABASE_NAME: String = "hospital.sqlite3"
const APPLICATION_ID: int = 0x4F474853
const DATABASE_VERSION: int = 1

var content: HospitalContent
var guard: RefCounted
var _thread: Thread
var _request: Dictionary = {}
var _dirty_auto_pending: bool = false

func _init(content_registry: HospitalContent, platform_guard: RefCounted) -> void:
	content = content_registry
	guard = platform_guard

func _connect(hospital_id: String, create: bool = false) -> Dictionary:
	if not valid_uuid(hospital_id) or not guard.call("is_held"):
		return {"ok":false,"error":"医院身份无效或资料库尚未取得独占权限"}
	if not ClassDB.class_exists("PlatformSQLite"):
		return {"ok":false,"error":"SQLite原生桥接不可用"}
	if create and DirAccess.make_dir_recursive_absolute(ROOT.path_join(hospital_id))!=OK:
		return {"ok":false,"error":"无法创建医院数据库目录"}
	var database: RefCounted = ClassDB.instantiate("PlatformSQLite") as RefCounted
	var result: Dictionary = database.call("open",hospital_id,create)
	if result.ok:
		result.database = database
	else:
		result.error = "无法打开医院数据库："+str(result.get("error",""))
	return result

func _empty_database(database: RefCounted) -> bool:
	var result: Dictionary = database.call("execute","SELECT count(*) AS count FROM sqlite_schema",[])
	var identity: Dictionary = database.call("execute","PRAGMA application_id",[])
	var version: Dictionary = database.call("execute","PRAGMA user_version",[])
	return result.ok and identity.ok and version.ok and result.rows[0].count==0 and identity.rows[0].application_id==0 and version.rows[0].user_version==0

func _database_identity(database: RefCounted, hospital_id: String) -> Dictionary:
	var identity: Dictionary = database.call("execute","PRAGMA application_id",[])
	var version: Dictionary = database.call("execute","PRAGMA user_version",[])
	if not identity.ok or not version.ok:
		return {"ok":false,"error":"医院数据库结构无法读取"}
	if identity.rows[0].application_id!=APPLICATION_ID or version.rows[0].user_version!=DATABASE_VERSION:
		return {"ok":false,"error":"医院数据库格式或结构版本不符"}
	var owner: Dictionary = database.call("execute","SELECT hospital_id FROM hospital",[])
	if not owner.ok or owner.rows.size()!=1 or owner.rows[0].hospital_id!=hospital_id:
		return {"ok":false,"error":"医院数据库所属身份不符"}
	var journal: Dictionary = database.call("execute","PRAGMA journal_mode",[])
	if not journal.ok or journal.rows[0].journal_mode!="delete":
		return {"ok":false,"error":"医院数据库回滚日志模式不符"}
	return {"ok":true}

func _initialize_database(database: RefCounted, hospital_id: String) -> Dictionary:
	var statements: Array[String] = [
		"PRAGMA application_id=%d" % APPLICATION_ID,"PRAGMA user_version=1",
		"CREATE TABLE hospital (singleton INTEGER PRIMARY KEY CHECK(singleton=1), hospital_id TEXT NOT NULL UNIQUE CHECK(length(hospital_id)=36)) STRICT",
		"CREATE TABLE snapshots (snapshot_id TEXT PRIMARY KEY NOT NULL CHECK(length(snapshot_id)=36), sequence INTEGER NOT NULL UNIQUE CHECK(sequence>0), manifest BLOB NOT NULL CHECK(length(manifest)<=65536), manifest_sha256 TEXT NOT NULL, sealed INTEGER NOT NULL CHECK(sealed IN (0,1))) STRICT",
		"CREATE TABLE world_chunks (snapshot_id TEXT NOT NULL REFERENCES snapshots(snapshot_id) ON DELETE CASCADE, chunk_index INTEGER NOT NULL CHECK(chunk_index>=0), data BLOB NOT NULL CHECK(length(data)>0 AND length(data)<=32768), PRIMARY KEY(snapshot_id,chunk_index)) STRICT"]
	for statement: String in statements:
		var result: Dictionary = database.call("execute",statement,[])
		if not result.ok:
			return result
	return database.call("execute","INSERT INTO hospital VALUES(1,?)",[hospital_id])

func _legacy_import(hospital_id: String) -> Dictionary:
	var database_path: String = ROOT.path_join(hospital_id).path_join(DATABASE_NAME)
	if FileAccess.file_exists(database_path):
		var existing: Dictionary = _connect(hospital_id)
		if not existing.ok:
			return existing
		var identity: Dictionary = _database_identity(existing.database,hospital_id)
		var empty: bool = _empty_database(existing.database) if not identity.ok else false
		existing.database.call("close")
		if identity.ok or not empty:
			return identity
	var commits: String = ROOT.path_join(hospital_id).path_join("commits")
	if not DirAccess.dir_exists_absolute(commits):
		return {"ok":true}
	var records: Array[Dictionary] = []
	for snapshot_id: String in DirAccess.get_directories_at(commits):
		if not valid_uuid(snapshot_id):
			continue
		var path: String = commits.path_join(snapshot_id)
		var record: Dictionary = _legacy_manifest(path,hospital_id,snapshot_id)
		if not record.ok:
			continue
		var decoder: HospitalJsonStream = HospitalJsonStream.new()
		var decoded: Dictionary = decoder.decode(path.path_join("world.json"),int(record.manifest.world_bytes),record.manifest.world_sha256,_budget)
		if decoded.ok and _validate_world(decoded.value,record.manifest).ok:
			records.append({"manifest":record.manifest,"path":path})
	if records.is_empty():
		return {"ok":false,"error":"旧医院没有通过完整校验的保存点，原文件保留"}
	var opened: Dictionary = _connect(hospital_id,true)
	if not opened.ok:
		return opened
	var database: RefCounted = opened.database
	var result: Dictionary = database.call("execute","BEGIN IMMEDIATE",[])
	if result.ok:
		result = _initialize_database(database,hospital_id)
	for record: Dictionary in records:
		if not result.ok:
			break
		var manifest: Dictionary = record.manifest
		var raw: PackedByteArray = FileAccess.get_file_as_bytes(record.path.path_join("manifest.json"))
		result = database.call("execute","INSERT INTO snapshots VALUES(?,?,?,?,0)",[manifest.snapshot_id,manifest.sequence,raw,_sha(raw)])
		var file: FileAccess = FileAccess.open(record.path.path_join("world.json"),FileAccess.READ)
		if file==null:
			result = {"ok":false,"error":"旧世界读取失败"}
		var index: int = 0
		while result.ok and file.get_position()<file.get_length():
			var chunk: PackedByteArray = file.get_buffer(HospitalJsonStream.CHUNK)
			if not _budget(index*HospitalJsonStream.CHUNK+chunk.size()):
				result = {"ok":false,"error":"旧医院导入资源不足"}
			else:
				result = database.call("execute","INSERT INTO world_chunks VALUES(?,?,?)",[manifest.snapshot_id,index,chunk])
			index += 1
		if file!=null:
			file.close()
		if result.ok:
			result = _read_snapshot(database,hospital_id,manifest.snapshot_id,false)
		if result.ok:
			result = database.call("execute","UPDATE snapshots SET sealed=1 WHERE snapshot_id=?",[manifest.snapshot_id])
	if result.ok:
		result = database.call("execute","COMMIT",[])
	database.call("close") # Closing rolls back an unfinished initial/import transaction.
	return {"ok":result.ok,"error":str(result.get("error",""))}

static func uuid() -> String:
	var raw: PackedByteArray = Crypto.new().generate_random_bytes(16)
	raw[6] = (raw[6] & 15) | 64
	raw[8] = (raw[8] & 63) | 128
	var hex: String = raw.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0,8),hex.substr(8,4),hex.substr(12,4),hex.substr(16,4),hex.substr(20,12)]

func busy() -> bool:
	return _thread != null

func begin(source: RefCounted, session_id: String, kind: String = "manual", slot: String = "1") -> Dictionary:
	if busy():
		if kind == "auto":
			_dirty_auto_pending = true
		return {"ok":false,"error":"正在保存同一资料库，保留本次未保存进展"}
	if not guard.call("is_held") or session_id.is_empty():
		return {"ok":false,"error":"保存缺少有效加载会话或资料库所有权"}
	if not kind in ["manual","auto","checkpoint"] or slot.is_empty() or slot.to_utf8_buffer().size()>64:
		return {"ok":false,"error":"保存槽位无效"}
	var world: WorldState
	if source is HospitalSimulation:
		source.drain_commands()
		world = source.world
	elif source is WorldState:
		world = source
	else:
		return {"ok":false,"error":"保存来源不是医院世界或模拟会话"}
	var reason: String = world.validate(content)
	if not reason.is_empty() or not valid_uuid(str(world.facts.get("hospital_id",""))):
		return {"ok":false,"error":"医院不能保存："+reason}
	if not _budget(estimate(world.facts)):
		return {"ok":false,"error":"快照副本所需内存或磁盘不足"}
	var snapshot_id: String = uuid()
	_request = {"hospital_id":world.facts.hospital_id,"loading_session_id":session_id,"request_id":uuid(),
		"snapshot_id":snapshot_id,"world_revision":world.facts.world_revision,"sim_tick":world.facts.sim_tick,
		"slot_kind":kind,"slot_key":slot,"content_packs":_content_identity()}
	var frozen: Dictionary = world.freeze()
	if frozen.is_empty():
		return {"ok":false,"error":"无法冻结医院副本，当前世界保留"}
	_thread = Thread.new()
	var start_error: Error = _thread.start(_write.bind(frozen,_request.duplicate(true)))
	if start_error != OK:
		_thread = null
		return {"ok":false,"error":"无法启动保存工作：%d" % start_error}
	return {"ok":true,"request":_request.duplicate(true)}

func _content_identity() -> Array:
	return content.snapshot_identity().duplicate(true)

func wait_for_idle() -> Dictionary:
	if _thread == null:
		return {}
	var receipt: Dictionary = _thread.wait_to_finish()
	_thread = null
	_request = {}
	return receipt

func recover_latest(hospital_id: String) -> Dictionary:
	var issues: Dictionary = {}
	var rejected: Array[Dictionary] = []
	for record: Dictionary in list_commits(hospital_id,issues):
		var candidate: Dictionary = load_commit(hospital_id,record.snapshot_id)
		if candidate.ok:
			candidate.rejected_candidates = rejected
			return candidate
		rejected.append({"snapshot_id":record.snapshot_id,"error":candidate.error})
	return {"ok":false,"error":str(issues.get(hospital_id,"医院没有完整有效的保存点")),"rejected_candidates":rejected}

func poll() -> Dictionary:
	if _thread == null or _thread.is_alive():
		return {}
	var receipt: Dictionary = _thread.wait_to_finish()
	_thread = null
	_request = {}
	return receipt

func take_pending_auto() -> bool:
	var pending: bool = _dirty_auto_pending
	_dirty_auto_pending = false
	return pending

func list_commits(hospital_id: String = "", errors: Variant = null) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var issues: Dictionary = errors if errors is Dictionary else {}
	issues.clear()
	if not DirAccess.dir_exists_absolute(ROOT):
		return records
	var hospitals: PackedStringArray = DirAccess.get_directories_at(ROOT)
	hospitals.sort()
	for id: String in hospitals:
		if not valid_uuid(id) or FileAccess.file_exists(ROOT.path_join(id).path_join(".library-pending")):
			continue
		if not hospital_id.is_empty() and id != hospital_id:
			continue
		var imported: Dictionary = _legacy_import(id)
		if not imported.ok:
			issues[id] = imported.error
			continue
		var opened: Dictionary = _connect(id)
		if not opened.ok:
			issues[id] = opened.error
			continue
		var database: RefCounted = opened.database
		var before: int = 9223372036854775807
		while true:
			var result: Dictionary = database.call("execute","SELECT snapshot_id,sequence,CASE WHEN length(manifest)<=65536 THEN manifest END AS manifest,manifest_sha256 FROM snapshots WHERE sealed=1 AND sequence<=? ORDER BY sequence DESC LIMIT 256",[before])
			if not result.ok:
				issues[id] = result.error
				break
			if result.rows.is_empty():
				break
			for row: Dictionary in result.rows:
				var record: Dictionary = _metadata(row,id)
				if record.ok:
					records.append(record.manifest)
				else:
					issues[id] = record.error
			before = int(result.rows.back().sequence)-1
		database.call("close")
	records.sort_custom(func(a:Dictionary,b:Dictionary) -> bool: return int(a.sequence)>int(b.sequence))
	return records

func load_commit(hospital_id: String, snapshot_id: String) -> Dictionary:
	if not valid_uuid(hospital_id) or not valid_uuid(snapshot_id):
		return {"ok":false,"error":"医院或保存点身份无效"}
	var imported: Dictionary = _legacy_import(hospital_id)
	if not imported.ok:
		return imported
	var opened: Dictionary = _connect(hospital_id)
	if not opened.ok:
		return opened
	var database: RefCounted = opened.database
	var result: Dictionary = database.call("execute","BEGIN",[])
	if result.ok:
		result = _read_snapshot(database,hospital_id,snapshot_id)
	database.call("close")
	return result

func _metadata(row: Dictionary, hospital_id: String) -> Dictionary:
	if not row.get("manifest") is PackedByteArray or row.manifest.size()>65536 or _sha(row.manifest)!=row.manifest_sha256:
		return {"ok":false,"error":"保存清单缺失、超限或SHA-256不符"}
	var result: Dictionary = _parse_manifest(row.manifest,hospital_id,str(row.snapshot_id))
	if result.ok and int(result.manifest.sequence)!=int(row.sequence):
		return {"ok":false,"error":"保存点sequence与清单不符"}
	return result

func _read_snapshot(database: RefCounted, hospital_id: String, snapshot_id: String, sealed: bool = true) -> Dictionary:
	var result: Dictionary = database.call("execute","SELECT snapshot_id,sequence,CASE WHEN length(manifest)<=65536 THEN manifest END AS manifest,manifest_sha256 FROM snapshots WHERE snapshot_id=? AND sealed=?",[snapshot_id,1 if sealed else 0])
	if not result.ok:
		return result
	if result.rows.size()!=1:
		return {"ok":false,"error":"保存点不存在或事务尚未提交"}
	var metadata: Dictionary = _metadata(result.rows[0],hospital_id)
	if not metadata.ok:
		return metadata
	var manifest: Dictionary = metadata.manifest
	if not _budget(int(manifest.world_bytes)):
		return {"ok":false,"error":"目标医院所需资源不足，当前医院保持暂停"}
	var decoder: HospitalJsonStream = HospitalJsonStream.new()
	var cursor: Dictionary = {"index":0}
	var source: Callable = func() -> Dictionary:
		var chunk: Dictionary = database.call("execute","SELECT chunk_index,CASE WHEN length(data)<=32768 THEN data END AS data FROM world_chunks WHERE snapshot_id=? AND chunk_index>=? ORDER BY chunk_index LIMIT 1",[snapshot_id,cursor.index])
		if not chunk.ok:
			return chunk
		if chunk.rows.is_empty():
			return {"ok":true,"data":PackedByteArray()}
		if int(chunk.rows[0].chunk_index)!=int(cursor.index) or not chunk.rows[0].data is PackedByteArray or chunk.rows[0].data.is_empty():
			return {"ok":false,"error":"世界分段次序、大小或类型无效"}
		cursor.index += 1
		return {"ok":true,"data":chunk.rows[0].data}
	var decoded: Dictionary = decoder.decode_from(int(manifest.world_bytes),manifest.world_sha256,_budget,source)
	if not decoded.ok:
		return decoded
	return _validate_world(decoded.value,manifest)

func _validate_world(value: Dictionary, manifest: Dictionary) -> Dictionary:
	var world: WorldState = WorldState.new(value)
	var reason: String = world.validate(content)
	if not reason.is_empty():
		return {"ok":false,"error":reason}
	if world.facts.hospital_id != manifest.hospital_id or int(world.facts.sim_tick) != int(manifest.sim_tick) or world.facts.display_name != manifest.display_summary.display_name or world.facts.mode != manifest.display_summary.mode or world.present_actor_count() != int(manifest.display_summary.present_actor_count) or (manifest.has("world_revision") and int(world.facts.world_revision)!=int(manifest.world_revision)):
		return {"ok":false,"error":"医院身份或清单摘要与世界不符"}
	return {"ok":true,"world":world,"manifest":manifest}

func _write(frozen: Dictionary, request: Dictionary) -> Dictionary:
	var receipt: Dictionary = request.duplicate(true)
	receipt.ok = false
	if not request.has("content_packs"):
		request.content_packs = _content_identity()
	if frozen.get("hospital_id")!=request.get("hospital_id") or frozen.get("world_revision")!=request.get("world_revision") or frozen.get("sim_tick")!=request.get("sim_tick"):
		receipt.error = "冻结世界与保存请求身份不符"
		return receipt
	var imported: Dictionary = _legacy_import(request.hospital_id)
	if not imported.ok:
		receipt.error = imported.error
		return receipt
	var opened: Dictionary = _connect(request.hospital_id,true)
	if not opened.ok:
		receipt.error = opened.error
		return receipt
	var database: RefCounted = opened.database
	var empty: bool = _empty_database(database)
	var result: Dictionary = {"ok":true} if empty else _database_identity(database,request.hospital_id)
	if result.ok:
		result = database.call("execute","BEGIN IMMEDIATE",[])
	if result.ok and empty:
		result = _initialize_database(database,request.hospital_id)
	var sequence: int = 1
	if result.ok:
		result = database.call("execute","SELECT coalesce(max(sequence),0)+1 AS next_sequence FROM snapshots",[])
		if result.ok:
			sequence = int(result.rows[0].next_sequence)
			result = database.call("execute","INSERT INTO snapshots VALUES(?,?,?,?,0)",[request.snapshot_id,sequence,PackedByteArray(),""])
	var encoder: HospitalJsonStream = HospitalJsonStream.new()
	var cursor: Dictionary = {"index":0}
	var sink: Callable = func(chunk: PackedByteArray) -> Dictionary:
		var written: Dictionary = database.call("execute","INSERT INTO world_chunks VALUES(?,?,?)",[request.snapshot_id,cursor.index,chunk])
		if written.ok:
			cursor.index += 1
		return written
	if result.ok and not encoder.encode_to(frozen,_budget,sink):
		result = {"ok":false,"error":encoder.error}
	if result.ok:
		var manifest: Dictionary = {"format":FORMAT,"schema_version":1,"game_version":str(ProjectSettings.get_setting("application/config/version")),
			"hospital_id":request.hospital_id,"snapshot_id":request.snapshot_id,"sequence":sequence,
			"slot_kind":request.slot_kind,"slot_key":request.slot_key,"created_utc":Time.get_datetime_string_from_system(true),
			"sim_tick":request.sim_tick,"world_revision":request.world_revision,"content_packs":request.content_packs,
			"world_bytes":encoder.bytes,"world_sha256":encoder.digest,
			"display_summary":{"display_name":frozen.display_name,"mode":frozen.mode,"present_actor_count":WorldState.new(frozen).present_actor_count()}}
		var raw: PackedByteArray = JSON.stringify(manifest,"",true).to_utf8_buffer()
		if raw.size()>65536:
			result = {"ok":false,"error":"保存清单超过64KiB"}
		else:
			result = database.call("execute","UPDATE snapshots SET manifest=?,manifest_sha256=? WHERE snapshot_id=?",[raw,_sha(raw),request.snapshot_id])
	if result.ok:
		result = _read_snapshot(database,request.hospital_id,request.snapshot_id,false)
	if result.ok:
		result = database.call("execute","UPDATE snapshots SET sealed=1 WHERE snapshot_id=?",[request.snapshot_id])
	if result.ok:
		result = database.call("execute","COMMIT",[])
	database.call("close")
	if not result.ok:
		receipt.error = "保存失败，旧保存点保留："+str(result.get("error",""))
		return receipt
	var final_check: Dictionary = load_commit(request.hospital_id,request.snapshot_id)
	if not final_check.ok:
		receipt.error = "完整提交最终校验失败："+str(final_check.error)
		return receipt
	receipt.ok = true
	receipt.sequence = sequence
	receipt.error = ""
	_cleanup(request.hospital_id,request.snapshot_id)
	return receipt

func _legacy_manifest(path: String, hospital_id: String, snapshot_id: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path.path_join("manifest.json"),FileAccess.READ)
	if file == null or file.get_length()>65536:
		return {"ok":false,"error":"保存清单缺失或超限"}
	var raw: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	if FileAccess.get_file_as_string(path.path_join("COMMITTED")) != _sha(raw):
		return {"ok":false,"error":"保存提交标记缺失或不符"}
	return _parse_manifest(raw,hospital_id,snapshot_id)

func _parse_manifest(raw: PackedByteArray, hospital_id: String, snapshot_id: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(raw.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return {"ok":false,"error":"保存清单JSON无效"}
	var data: Dictionary = json.data
	for field: String in ["format","schema_version","game_version","hospital_id","snapshot_id","sequence","slot_kind","slot_key","created_utc","sim_tick","content_packs","world_bytes","world_sha256","display_summary"]:
		if not data.has(field):
			return {"ok":false,"error":"保存清单缺少字段："+field}
	var types: Dictionary = {"format":TYPE_STRING,"schema_version":TYPE_INT,"game_version":TYPE_STRING,"hospital_id":TYPE_STRING,"snapshot_id":TYPE_STRING,"sequence":TYPE_INT,"slot_kind":TYPE_STRING,"slot_key":TYPE_STRING,"created_utc":TYPE_STRING,"sim_tick":TYPE_INT,"content_packs":TYPE_ARRAY,"world_bytes":TYPE_INT,"world_sha256":TYPE_STRING,"display_summary":TYPE_DICTIONARY}
	if not WorldState._fields(data,types).is_empty() or not WorldState._natural(data.sim_tick) or not data.slot_kind in ["manual","auto","checkpoint"] or not _valid_sha(data.world_sha256) or data.slot_key.is_empty() or data.slot_key.to_utf8_buffer().size()>64 or (data.has("world_revision") and not WorldState._natural(data.world_revision)):
		return {"ok":false,"error":"保存清单字段类型无效"}
	# Engineering fixtures from the first schema1 implementation have only pack/version.
	if data.content_packs != _content_identity() and data.content_packs != [{"id":"core","version":str(content.catalog.content_version)}]:
		return {"ok":false,"error":"保存点需要不同的核心内容版本"}
	if not WorldState._fields(data.display_summary,{"display_name":TYPE_STRING,"mode":TYPE_STRING,"present_actor_count":TYPE_INT}).is_empty() or not WorldState._natural(data.display_summary.present_actor_count):
		return {"ok":false,"error":"保存清单显示摘要无效"}
	if data.format!=FORMAT or int(data.schema_version)!=1 or data.hospital_id!=hospital_id or data.snapshot_id!=snapshot_id or not WorldState._natural(data.world_bytes) or not WorldState._natural(data.sequence) or int(data.sequence)<1:
		return {"ok":false,"error":"保存清单身份或格式无效"}
	return {"ok":true,"manifest":data}

func _budget(world_bytes: int) -> bool:
	if world_bytes<0 or world_bytes>2305843009196916735:
		return false
	var status: Dictionary = guard.call("get_resource_status")
	if not status.get("ok",false):
		return false
	return world_bytes*4+HEADROOM <= int(status.available_physical_bytes)/2 and world_bytes*3+HEADROOM <= int(status.available_disk_bytes)

static func _valid_sha(value: String) -> bool:
	if value.length()!=64:
		return false
	for character: String in value:
		if not character in "0123456789abcdef":
			return false
	return true

func _cleanup(hospital_id: String, validated_snapshot_id: String) -> void:
	var retained: Dictionary = {}
	var slots: Dictionary = {}
	var automatic: int = 0
	var checkpoints: int = 0
	var records: Array[Dictionary] = []
	for record: Dictionary in list_commits(hospital_id):
		if record.snapshot_id==validated_snapshot_id or load_commit(hospital_id,record.snapshot_id).ok:
			records.append(record)
	for record: Dictionary in records:
		var key: String = str(record.slot_kind)+":"+str(record.slot_key)
		if record.slot_kind=="auto" and automatic<int(content.balance.save.autosave_slots):
			retained[record.snapshot_id] = true
			automatic += 1
		elif record.slot_kind=="checkpoint" and checkpoints<int(content.balance.save.checkpoint_slots):
			retained[record.snapshot_id] = true
			checkpoints += 1
		elif record.slot_kind=="manual" and not slots.has(key) and slots.size()<int(content.balance.save.manual_slots):
			slots[key] = true
			retained[record.snapshot_id] = true
	var extra: int = 0
	for record: Dictionary in records:
		if not retained.has(record.snapshot_id) and extra<2:
			retained[record.snapshot_id] = true
			extra += 1
	var obsolete: Array[Dictionary] = []
	var cleanup_bytes: int = 0
	for record: Dictionary in records:
		if not retained.has(record.snapshot_id):
			obsolete.append(record)
			cleanup_bytes += int(record.world_bytes)
	if obsolete.is_empty() or not _budget(cleanup_bytes):
		return
	var opened: Dictionary = _connect(hospital_id)
	if not opened.ok:
		return
	var database: RefCounted = opened.database
	var result: Dictionary = database.call("execute","BEGIN IMMEDIATE",[])
	for record: Dictionary in obsolete:
		if not result.ok:
			break
		result = database.call("execute","DELETE FROM snapshots WHERE snapshot_id=?",[record.snapshot_id])
	if result.ok:
		database.call("execute","COMMIT",[])
	database.call("close")

static func estimate(value: Variant) -> int:
	if value is Dictionary:
		var size: int = 2
		for key: String in value:
			size += key.to_utf8_buffer().size()*6+4+estimate(value[key])
		return size
	if value is Array:
		var size: int = 2
		for element: Variant in value:
			size += estimate(element)+1
		return size
	return str(value).to_utf8_buffer().size()*6+32

static func valid_uuid(value: String) -> bool:
	if value.length()!=36:
		return false
	for index: int in value.length():
		if index in [8,13,18,23]:
			if value[index]!="-":
				return false
		elif not value[index] in "0123456789abcdef":
			return false
	return true

func hospital_ids() -> Array[String]:
	var ids: Array[String] = []
	if not DirAccess.dir_exists_absolute(ROOT):
		return ids
	for id: String in DirAccess.get_directories_at(ROOT):
		if valid_uuid(id) and not FileAccess.file_exists(ROOT.path_join(id).path_join(".library-pending")):
			ids.append(id)
	ids.sort()
	return ids

static func _store(path: String, bytes_to_write: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes_to_write)
	file.flush()
	var ok: bool = file.get_error()==OK
	file.close()
	return ok

static func _sha(raw: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(raw)
	return context.finish().hex_encode()
