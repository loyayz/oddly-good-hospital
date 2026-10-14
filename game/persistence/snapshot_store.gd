class_name HospitalSnapshots
extends RefCounted

const FORMAT: String = "oddly-good-hospital.snapshot"
const ROOT: String = "user://hospitals"
const HEADROOM: int = 67108864

var content: HospitalContent
var guard: RefCounted
var _thread: Thread
var _request: Dictionary = {}
var _dirty_auto_pending: bool = false

func _init(database: HospitalContent, platform_guard: RefCounted) -> void:
	content = database
	guard = platform_guard

static func uuid() -> String:
	var raw: PackedByteArray = Crypto.new().generate_random_bytes(16)
	raw[6] = (raw[6] & 15) | 64
	raw[8] = (raw[8] & 63) | 128
	var hex: String = raw.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0,8),hex.substr(8,4),hex.substr(12,4),hex.substr(16,4),hex.substr(20,12)]

func busy() -> bool:
	return _thread != null

func begin(world: HospitalWorld, session_id: String, kind: String = "manual", slot: String = "1") -> Dictionary:
	var reason: String = world.validate(content)
	if not reason.is_empty() or not valid_uuid(str(world.facts.get("hospital_id",""))):
		return {"ok":false,"error":"医院不能保存："+reason}
	if busy():
		if kind == "auto":
			_dirty_auto_pending = true
		return {"ok":false,"error":"正在保存同一资料库，保留本次未保存进展"}
	if not _budget(estimate(world.facts)):
		return {"ok":false,"error":"快照副本所需内存或磁盘不足"}
	var snapshot_id: String = uuid()
	_request = {"hospital_id":world.facts.hospital_id,"loading_session_id":session_id,"request_id":uuid(),
		"snapshot_id":snapshot_id,"world_revision":world.facts.world_revision,"sim_tick":world.facts.sim_tick,
		"slot_kind":kind,"slot_key":slot}
	var frozen: Dictionary = world.freeze()
	_thread = Thread.new()
	var start_error: Error = _thread.start(_write.bind(frozen,_request.duplicate(true)))
	if start_error != OK:
		_thread = null
		return {"ok":false,"error":"无法启动保存工作：%d" % start_error}
	return {"ok":true,"request":_request.duplicate(true)}

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

func list_commits(hospital_id: String = "") -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(ROOT):
		return records
	var hospitals: PackedStringArray = DirAccess.get_directories_at(ROOT)
	hospitals.sort()
	for id: String in hospitals:
		if not valid_uuid(id):
			continue
		if not hospital_id.is_empty() and id != hospital_id:
			continue
		var commits_dir: String = ROOT.path_join(id).path_join("commits")
		if not DirAccess.dir_exists_absolute(commits_dir):
			continue
		for snapshot_id: String in DirAccess.get_directories_at(commits_dir):
			if not valid_uuid(snapshot_id):
				continue
			var record: Dictionary = _manifest(commits_dir.path_join(snapshot_id),id,snapshot_id)
			if record.ok:
				records.append(record.manifest)
	records.sort_custom(func(a:Dictionary,b:Dictionary) -> bool: return int(a.sequence)>int(b.sequence))
	return records

func load_commit(hospital_id: String, snapshot_id: String) -> Dictionary:
	if not valid_uuid(hospital_id) or not valid_uuid(snapshot_id):
		return {"ok":false,"error":"医院或保存点身份无效"}
	var path: String = ROOT.path_join(hospital_id).path_join("commits").path_join(snapshot_id)
	var metadata: Dictionary = _manifest(path,hospital_id,snapshot_id)
	if not metadata.ok:
		return metadata
	var manifest: Dictionary = metadata.manifest
	if not _budget(int(manifest.world_bytes)):
		return {"ok":false,"error":"目标医院所需资源不足，当前医院保持暂停"}
	var decoder: HospitalJsonStream = HospitalJsonStream.new()
	var decoded: Dictionary = decoder.decode(path.path_join("world.json"),int(manifest.world_bytes),manifest.world_sha256,_budget)
	if not decoded.ok:
		return decoded
	var world: HospitalWorld = HospitalWorld.new(decoded.value)
	var reason: String = world.validate(content)
	if not reason.is_empty():
		return {"ok":false,"error":reason}
	if world.facts.hospital_id != hospital_id or int(world.facts.sim_tick) != int(manifest.sim_tick) or world.facts.display_name != manifest.display_summary.display_name or world.present_actor_count() != int(manifest.display_summary.present_actor_count):
		return {"ok":false,"error":"医院身份或清单摘要与世界不符"}
	return {"ok":true,"world":world,"manifest":manifest}

func _write(frozen: Dictionary, request: Dictionary) -> Dictionary:
	var receipt: Dictionary = request.duplicate(true)
	receipt.ok = false
	var commits: String = ROOT.path_join(request.hospital_id).path_join("commits")
	var pending: String = commits.path_join(".pending-"+request.snapshot_id)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(pending)
	if directory_error != OK:
		receipt.error = "无法创建保存目录：%d" % directory_error
		return receipt
	var encoder: HospitalJsonStream = HospitalJsonStream.new()
	if not encoder.encode(pending.path_join("world.json"),frozen,_budget):
		receipt.error = encoder.error
		return receipt
	var sequence: int = 1
	for existing: Dictionary in list_commits(request.hospital_id):
		sequence = maxi(sequence,int(existing.sequence)+1)
	var manifest: Dictionary = {"format":FORMAT,"schema_version":1,"game_version":"0.1.0-stage01",
		"hospital_id":request.hospital_id,"snapshot_id":request.snapshot_id,"sequence":sequence,
		"slot_kind":request.slot_kind,"slot_key":request.slot_key,"created_utc":Time.get_datetime_string_from_system(true),
		"sim_tick":request.sim_tick,"content_packs":[{"id":"core","version":str(content.catalog.content_version)}],
		"world_bytes":encoder.bytes,"world_sha256":encoder.digest,
		"display_summary":{"display_name":frozen.display_name,"mode":frozen.mode,"present_actor_count":HospitalWorld.new(frozen).present_actor_count()}}
	var manifest_bytes: PackedByteArray = JSON.stringify(manifest,"",true).to_utf8_buffer()
	if manifest_bytes.size()>65536 or not _store(pending.path_join("manifest.json"),manifest_bytes):
		receipt.error = "保存清单写入失败"
		return receipt
	var decoder: HospitalJsonStream = HospitalJsonStream.new()
	var readback: Dictionary = decoder.decode(pending.path_join("world.json"),encoder.bytes,encoder.digest,_budget)
	if not readback.ok or not HospitalWorld.new(readback.get("value",{})).validate(content).is_empty():
		receipt.error = "保存世界回读校验失败："+str(readback.get("error",""))
		return receipt
	if FileAccess.get_file_as_bytes(pending.path_join("manifest.json")) != manifest_bytes:
		receipt.error = "保存清单回读校验失败"
		return receipt
	var committed: PackedByteArray = _sha(manifest_bytes).to_utf8_buffer()
	if not _store(pending.path_join("COMMITTED"),committed):
		receipt.error = "保存提交标记写入失败"
		return receipt
	var destination: String = commits.path_join(request.snapshot_id)
	if DirAccess.dir_exists_absolute(destination) or DirAccess.rename_absolute(pending,destination)!=OK:
		receipt.error = "保存提交目录更名失败，旧提交保留"
		return receipt
	var final_check: Dictionary = load_commit(request.hospital_id,request.snapshot_id)
	if not final_check.ok:
		receipt.error = "完整提交最终校验失败："+str(final_check.error)
		return receipt
	receipt.ok = true
	receipt.sequence = sequence
	receipt.error = ""
	_cleanup(request.hospital_id)
	return receipt

func _manifest(path: String, hospital_id: String, snapshot_id: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path.path_join("manifest.json"),FileAccess.READ)
	if file == null or file.get_length()>65536:
		return {"ok":false,"error":"保存清单缺失或超限"}
	var raw: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	if FileAccess.get_file_as_string(path.path_join("COMMITTED")) != _sha(raw):
		return {"ok":false,"error":"保存提交标记缺失或不符"}
	var json: JSON = JSON.new()
	if json.parse(raw.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return {"ok":false,"error":"保存清单JSON无效"}
	var data: Dictionary = json.data
	for field: String in ["format","schema_version","game_version","hospital_id","snapshot_id","sequence","slot_kind","slot_key","created_utc","sim_tick","content_packs","world_bytes","world_sha256","display_summary"]:
		if not data.has(field):
			return {"ok":false,"error":"保存清单缺少字段："+field}
	var types: Dictionary = {"format":TYPE_STRING,"schema_version":TYPE_INT,"game_version":TYPE_STRING,"hospital_id":TYPE_STRING,"snapshot_id":TYPE_STRING,"sequence":TYPE_INT,"slot_kind":TYPE_STRING,"slot_key":TYPE_STRING,"created_utc":TYPE_STRING,"sim_tick":TYPE_INT,"content_packs":TYPE_ARRAY,"world_bytes":TYPE_INT,"world_sha256":TYPE_STRING,"display_summary":TYPE_DICTIONARY}
	if not HospitalWorld._fields(data,types).is_empty() or not HospitalWorld._natural(data.sim_tick) or not data.slot_kind in ["manual","auto","checkpoint"] or data.world_sha256.length()!=64:
		return {"ok":false,"error":"保存清单字段类型无效"}
	if data.content_packs != [{"id":"core","version":str(content.catalog.content_version)}]:
		return {"ok":false,"error":"保存点需要不同的核心内容版本"}
	if not HospitalWorld._fields(data.display_summary,{"display_name":TYPE_STRING,"mode":TYPE_STRING,"present_actor_count":TYPE_INT}).is_empty() or not HospitalWorld._natural(data.display_summary.present_actor_count):
		return {"ok":false,"error":"保存清单显示摘要无效"}
	if data.format!=FORMAT or int(data.schema_version)!=1 or data.hospital_id!=hospital_id or data.snapshot_id!=snapshot_id or not HospitalWorld._natural(data.world_bytes) or not HospitalWorld._natural(data.sequence) or int(data.sequence)<1:
		return {"ok":false,"error":"保存清单身份或格式无效"}
	return {"ok":true,"manifest":data}

func _budget(world_bytes: int) -> bool:
	var status: Dictionary = guard.call("get_resource_status")
	if not status.get("ok",false):
		return false
	return world_bytes*4+HEADROOM <= int(status.available_physical_bytes)/2 and world_bytes*3+HEADROOM <= int(status.available_disk_bytes)

func _cleanup(hospital_id: String) -> void:
	var retained: Dictionary = {}
	var slots: Dictionary = {}
	var automatic: int = 0
	var checkpoints: int = 0
	var records: Array[Dictionary] = []
	for record: Dictionary in list_commits(hospital_id):
		if load_commit(hospital_id,record.snapshot_id).ok:
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
	for record: Dictionary in records:
		if retained.has(record.snapshot_id):
			continue
		var path: String = ROOT.path_join(hospital_id).path_join("commits").path_join(record.snapshot_id)
		for name: String in ["world.json","manifest.json","COMMITTED"]:
			DirAccess.remove_absolute(path.path_join(name))
		DirAccess.remove_absolute(path)

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
		if valid_uuid(id):
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
