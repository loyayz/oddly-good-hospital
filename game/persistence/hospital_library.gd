class_name HospitalLibrary
extends RefCounted

const TRASH: String = "user://trash"
const PENDING: String = ".library-pending"
const TRASH_RECORD: String = ".trash.json"
const DEFINITION_IDS: Array[String] = ["definition_id","species_id","disease_id","binding_id","body_binding_id","title_id","personality_id","requested_plan_id","plan_id","course_id","research_id","material_id","handler_id","certificate_id","department_definition_id"]
const INSTANCE_ARRAYS: Array[String] = ["riders","occupants","participants"]
const INSTANCE_KEY_MAPS: Array[String] = ["moves","command_receipts","completed_jobs","use_receipts","issues","reservations","completion_receipts","evidence_by_source","work_receipts"]

var content: HospitalContent
var snapshots: HospitalSnapshots
var _scan_generation: int = 0
var _scan_ids: Array[String] = []
var _scan_query: String = ""
var _scan_recycled: bool = false
var _io_busy: bool = false
var _cancel_io: bool = false

func _init(registry: HospitalContent,store: HospitalSnapshots) -> void:
	content = registry
	snapshots = store

func busy() -> bool:
	return _io_busy or snapshots.busy()

func cancel_scan() -> void:
	_scan_generation += 1
	_scan_ids.clear()

func cancel_io() -> void:
	_cancel_io = true

func scan_page(cursor: Dictionary = {},limit: int = 12,query: String = "",recycled: bool = false) -> Dictionary:
	if not snapshots.guard.call("is_held"):
		return _error("资料库尚未取得独占权限")
	var index: int = int(cursor.get("index",0))
	if cursor.is_empty():
		cancel_scan()
		_scan_query = query
		_scan_recycled = recycled
		var directory: String = TRASH if recycled else HospitalSnapshots.ROOT
		if DirAccess.dir_exists_absolute(directory):
			for id: String in DirAccess.get_directories_at(directory):
				if HospitalSnapshots.valid_uuid(id) and not FileAccess.file_exists(directory.path_join(id).path_join(PENDING)):
					_scan_ids.append(id)
		_scan_ids.sort()
	elif int(cursor.get("generation",-1))!=_scan_generation or query!=_scan_query or recycled!=_scan_recycled:
		return {"ok":false,"cancelled":true,"error":"原医院扫描已取消，请重新浏览"}
	if index<0 or index>_scan_ids.size():
		return _error("医院扫描游标越界，请重新浏览")
	var generation: int = _scan_generation
	var records: Array[Dictionary] = []
	var errors: Dictionary = {}
	var end: int = mini(_scan_ids.size(),index+clampi(limit,1,32))
	while index<end:
		var id: String = _scan_ids[index]
		var record: Dictionary = _trash_manifest(id) if recycled else _latest_manifest(id)
		if not record.ok:
			errors[id] = str(record.error)
		elif query.is_empty() or str(record.manifest.display_summary.display_name).to_lower().contains(query.to_lower()):
			var card: Dictionary = record.manifest.duplicate(true)
			card.world_verified = false
			card.needs_recovery = bool(record.get("needs_recovery",false))
			if recycled:
				card.deleted_utc = record.get("deleted_utc","")
				card.cleanup_due = record.get("cleanup_due",false)
			records.append(card)
		index += 1
	if generation!=_scan_generation:
		return {"ok":false,"cancelled":true,"error":"原医院扫描已取消"}
	return {"ok":true,"records":records,"errors":errors,"cursor":{"generation":generation,"index":index},"done":index>=_scan_ids.size()}

func _latest_manifest(hospital_id: String) -> Dictionary:
	var imported: Dictionary = snapshots._legacy_import(hospital_id)
	if not imported.ok:
		return imported
	var opened: Dictionary = snapshots._connect(hospital_id)
	if not opened.ok:
		return opened
	var database: RefCounted = opened.database
	var result: Dictionary = snapshots._database_identity(database,hospital_id)
	if result.ok:
		result = database.call("execute","SELECT snapshot_id,sequence,CASE WHEN length(manifest)<=65536 THEN manifest END AS manifest,manifest_sha256 FROM snapshots WHERE sealed=1 ORDER BY sequence DESC LIMIT 256",[])
	var selected: Dictionary = _error("医院没有可读保存清单，可从外部备份恢复")
	if result.ok:
		for row: Dictionary in result.rows:
			var metadata: Dictionary = snapshots._metadata(row,hospital_id)
			if metadata.ok:
				metadata.needs_recovery = row!=result.rows[0]
				selected = metadata
				break
	else:
		selected = result
	database.call("close")
	return selected

func slots(hospital_id: String) -> Dictionary:
	var opened: Dictionary = snapshots._connect(hospital_id)
	if not opened.ok:
		return opened
	var database: RefCounted = opened.database
	var result: Dictionary = snapshots._database_identity(database,hospital_id)
	var records: Array[Dictionary] = []
	var errors: Array[Dictionary] = []
	if result.ok:
		result = database.call("execute","SELECT snapshot_id,sequence,CASE WHEN length(manifest)<=65536 THEN manifest END AS manifest,manifest_sha256 FROM snapshots WHERE sealed=1 ORDER BY sequence DESC LIMIT 256",[])
	if result.ok:
		for row: Dictionary in result.rows:
			var parsed: Dictionary = snapshots._metadata(row,hospital_id)
			if parsed.ok:
				records.append(parsed.manifest)
			else:
				errors.append({"snapshot_id":row.snapshot_id,"error":parsed.error})
	database.call("close")
	return {"ok":result.ok,"records":records,"errors":errors,"error":str(result.get("error",""))}

func create(world: WorldState,session_id: String) -> Dictionary:
	if busy() or world==null or not HospitalSnapshots.valid_uuid(world.hospital_id):
		return _error("当前资料操作尚未完成")
	if DirAccess.dir_exists_absolute(HospitalSnapshots.ROOT.path_join(world.hospital_id)):
		return _error("新医院身份已经存在，不会覆盖原医院")
	cancel_scan()
	return snapshots.begin(world,session_id,"checkpoint","created")

func continue_hospital(hospital_id: String,snapshot_id: String = "") -> Dictionary:
	if _io_busy:
		return _error("资料操作尚未完成，请稍后继续医院")
	return snapshots.recover_latest(hospital_id) if snapshot_id.is_empty() else snapshots.load_commit(hospital_id,snapshot_id)

func export_backup(hospital_id: String,snapshot_id: String,destination: String) -> Dictionary:
	if busy():
		return _error("请等待当前资料写入完成后导出")
	_io_busy = true
	_cancel_io = false
	var candidate: Dictionary = snapshots.load_commit(hospital_id,snapshot_id)
	candidate.erase("world")
	var staging: String = ""
	var result: Dictionary = candidate
	if candidate.ok:
		staging = HospitalSnapshots.uuid()
		result = _prepare_staging(staging)
	if result.ok:
		result = _clone_snapshot(hospital_id,snapshot_id,staging)
	if result.ok:
		var zip: HospitalBackupZip = HospitalBackupZip.new()
		var path: String = HospitalSnapshots.ROOT.path_join(staging).path_join(HospitalSnapshots.DATABASE_NAME)
		var info: Dictionary = zip.file_info(path,snapshots._budget)
		result = info
		if info.ok:
			var manifest: Dictionary = candidate.manifest.duplicate(true)
			manifest.database_bytes = info.bytes
			manifest.database_sha256 = info.sha256
			var raw: PackedByteArray = JSON.stringify(manifest,"",true,true).to_utf8_buffer()
			if raw.size()>65536:
				result = _error("备份清单超过64KiB")
			else:
				var budget: Callable = func(bytes: int) -> bool:
					var target: DirAccess = DirAccess.open(destination.get_base_dir())
					return snapshots._budget(maxi(bytes,int(manifest.world_bytes))) and target!=null and int(target.get_space_left())>=maxi(bytes,int(manifest.world_bytes))*3+HospitalSnapshots.HEADROOM
				result = zip.write(destination,raw,path,info,budget,func() -> bool: return _cancel_io)
	if not staging.is_empty():
		_remove_staging(staging)
	_io_busy = false
	return result

func _clone_snapshot(hospital_id: String,snapshot_id: String,staging_id: String) -> Dictionary:
	var source: Dictionary = snapshots._connect(hospital_id)
	if not source.ok:
		return source
	var opened: Dictionary = snapshots._connect(staging_id,true)
	if not opened.ok:
		source.database.call("close")
		return opened
	var database: RefCounted = opened.database
	var result: Dictionary = source.database.call("execute","BEGIN",[])
	if result.ok:
		result = database.call("execute","BEGIN IMMEDIATE",[])
	if result.ok:
		result = snapshots._initialize_database(database,hospital_id)
	if result.ok:
		result = source.database.call("execute","SELECT snapshot_id,sequence,CASE WHEN length(manifest)<=65536 THEN manifest END AS manifest,manifest_sha256 FROM snapshots WHERE snapshot_id=? AND sealed=1",[snapshot_id])
	if result.ok and result.rows.size()==1:
		var row: Dictionary = result.rows[0]
		result = snapshots._metadata(row,hospital_id)
		if result.ok:
			result = database.call("execute","INSERT INTO snapshots VALUES(?,?,?,?,0)",[snapshot_id,row.sequence,row.manifest,row.manifest_sha256])
	else:
		result = _error("所选完整保存点不再存在")
	var index: int = 0
	while result.ok:
		var chunk: Dictionary = source.database.call("execute","SELECT chunk_index,CASE WHEN length(data)<=32768 THEN data END AS data FROM world_chunks WHERE snapshot_id=? AND chunk_index>=? ORDER BY chunk_index LIMIT 1",[snapshot_id,index])
		if not chunk.ok:
			result = chunk
			break
		if chunk.rows.is_empty():
			break
		if int(chunk.rows[0].chunk_index)!=index or not chunk.rows[0].data is PackedByteArray or chunk.rows[0].data.is_empty():
			result = _error("备份来源世界分段次序、类型或大小无效")
			break
		if _cancel_io or not snapshots._budget((index+1)*HospitalJsonStream.CHUNK):
			result = _error("备份取消或暂存资源不足")
			break
		result = database.call("execute","INSERT INTO world_chunks VALUES(?,?,?)",[snapshot_id,chunk.rows[0].chunk_index,chunk.rows[0].data])
		index += 1
	if result.ok:
		result = snapshots._read_snapshot(database,hospital_id,snapshot_id,false)
	if result.ok:
		result = database.call("execute","UPDATE snapshots SET sealed=1 WHERE snapshot_id=?",[snapshot_id])
	if result.ok:
		result = database.call("execute","COMMIT",[])
	database.call("close")
	source.database.call("close")
	return result

func import_backup(path: String) -> Dictionary:
	if busy() or not snapshots.guard.call("is_held"):
		return _error("请等待当前资料操作完成后导入")
	_io_busy = true
	_cancel_io = false
	var zip: HospitalBackupZip = HospitalBackupZip.new()
	var archive: Dictionary = zip.inspect(path)
	var result: Dictionary = archive
	var manifest: Dictionary = {}
	var staging: String = ""
	if result.ok:
		result = zip.read_manifest(archive,snapshots._budget)
	if result.ok:
		manifest = result.manifest
		if not HospitalSnapshots.valid_uuid(str(manifest.get("hospital_id",""))) or not HospitalSnapshots.valid_uuid(str(manifest.get("snapshot_id",""))):
			result = _error("备份医院或保存点身份无效")
		else:
			result = snapshots._parse_manifest(JSON.stringify(manifest,"",true,true).to_utf8_buffer(),manifest.hospital_id,manifest.snapshot_id)
	if result.ok:
		if not WorldState._natural(manifest.get("database_bytes",-1)) or not manifest.get("database_sha256") is String or not HospitalSnapshots._valid_sha(manifest.database_sha256) or int(manifest.database_bytes)!=int(archive.entries["hospital.sqlite3"].unpacked):
			result = _error("备份数据库实际长度或哈希声明无效")
		elif not snapshots._budget(maxi(int(manifest.world_bytes),int(manifest.database_bytes))):
			result = _error("备份数据库和候选世界所需内存或磁盘不足")
	if result.ok:
		staging = HospitalSnapshots.uuid()
		result = _prepare_staging(staging)
	if result.ok:
		var output: FileAccess = FileAccess.open(HospitalSnapshots.ROOT.path_join(staging).path_join(HospitalSnapshots.DATABASE_NAME),FileAccess.WRITE)
		if output==null:
			result = _error("无法建立备份暂存数据库")
		else:
			var sink: Callable = func(chunk: PackedByteArray) -> Dictionary:
				output.store_buffer(chunk)
				return {"ok":output.get_error()==OK,"error":"备份暂存数据库写入失败"}
			result = zip.extract(archive,"hospital.sqlite3",sink,snapshots._budget,func() -> bool: return _cancel_io)
			output.flush()
			if output.get_error()!=OK:
				result = _error("备份暂存数据库未完整落盘")
			output.close()
			if result.ok and result.sha256!=manifest.database_sha256:
				result = _error("备份数据库SHA-256不符")
	if result.ok:
		result = _read_import(staging,manifest)
	if result.ok:
		result = _publish_import(result.world)
	if not staging.is_empty():
		_remove_staging(staging)
	_io_busy = false
	if result.ok:
		cancel_scan()
	return result

func _read_import(staging_id: String,manifest: Dictionary) -> Dictionary:
	var opened: Dictionary = snapshots._connect(staging_id)
	if not opened.ok:
		return opened
	var database: RefCounted = opened.database
	var result: Dictionary = snapshots._database_identity(database,manifest.hospital_id)
	if result.ok:
		result = database.call("execute","SELECT name,type FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%' ORDER BY name",[])
		if result.ok and result.rows!=[{"name":"hospital","type":"table"},{"name":"snapshots","type":"table"},{"name":"world_chunks","type":"table"}]:
			result = _error("备份数据库包含未知表、视图或触发器")
	if result.ok:
		result = database.call("execute","SELECT count(*) AS count FROM snapshots",[])
		if result.ok and int(result.rows[0].count)!=1:
			result = _error("独立备份必须只含所选完整保存点")
	if result.ok:
		result = database.call("execute","PRAGMA quick_check",[])
		if result.ok and (result.rows.size()!=1 or result.rows[0].get("quick_check","")!="ok"):
			result = _error("备份数据库结构校验失败")
	if result.ok:
		result = database.call("execute","PRAGMA foreign_key_check",[])
		if result.ok and not result.rows.is_empty():
			result = _error("备份数据库包含孤立世界分段")
	if result.ok:
		result = snapshots._read_snapshot(database,manifest.hospital_id,manifest.snapshot_id)
		if result.ok and (result.manifest.world_sha256!=manifest.world_sha256 or int(result.manifest.world_bytes)!=int(manifest.world_bytes) or int(result.manifest.sequence)!=int(manifest.sequence)):
			result = _error("备份外部清单与数据库所选保存点不符")
	database.call("close")
	return result

func _publish_import(source: WorldState) -> Dictionary:
	if _cancel_io:
		return _error("备份导入已取消，原文件保留")
	var new_id: String = HospitalSnapshots.uuid()
	var world: WorldState = WorldState.new(_remap_hospital(source.facts,source.hospital_id,new_id))
	var reason: String = world.validate(content)
	if not reason.is_empty():
		return _error("新医院引用校验失败："+reason)
	var prepared: Dictionary = _prepare_staging(new_id)
	if not prepared.ok:
		return prepared
	var started: Dictionary = snapshots.begin(world,HospitalSnapshots.uuid(),"checkpoint","imported")
	var receipt: Dictionary = snapshots.wait_for_idle() if started.ok else started
	if not receipt.ok:
		_remove_staging(new_id)
		return receipt
	var restored: Dictionary = snapshots.load_commit(new_id,receipt.snapshot_id)
	if not restored.ok:
		_remove_staging(new_id)
		return restored
	if DirAccess.remove_absolute(HospitalSnapshots.ROOT.path_join(new_id).path_join(PENDING))!=OK:
		_remove_staging(new_id)
		return _error("新医院发布失败，原备份和既有医院保留，请检查目录权限")
	restored.hospital_id = new_id
	restored.snapshot_id = receipt.snapshot_id
	return restored

func _remap_hospital(value: Dictionary,old_id: String,new_id: String) -> Dictionary:
	var ids: Dictionary = {old_id:new_id}
	_collect_instance_ids(value,old_id,new_id,ids)
	var rewritten: Dictionary = _rewrite_ids(value,"",old_id,new_id,ids)
	# Rating deduplication keys concatenate two instance identities.
	var state: Dictionary = value.get("departments",{})
	if state.has("staff_consumed"):
		var consumed: Dictionary = {}
		var staff_ids: Dictionary = value.get("staff",{})
		for key: String in state.staff_consumed:
			var mapped: String = key
			# Try actual delimiter positions from longest to shortest. Staff IDs
			# may themselves contain colons; splitting at the first is incorrect.
			var separator: int = key.rfind(":")
			while separator>=0:
				var staff_id: String = key.left(separator)
				if staff_ids.has(staff_id):
					var source_id: String = key.substr(separator+1)
					var mapped_source: String = new_id+source_id.substr(old_id.length()) if _hospital_prefix(source_id,old_id) else source_id
					mapped = str(ids.get(staff_id,staff_id))+":"+mapped_source
					break
				separator = key.rfind(":",separator-1) if separator>0 else -1
			consumed[mapped] = state.staff_consumed[key]
		rewritten.departments.staff_consumed = consumed
	return rewritten

func _collect_instance_ids(value: Variant,old_id: String,new_id: String,ids: Dictionary,field: String = "",path: Array[String] = []) -> void:
	if value is Dictionary:
		if value.get("id") is String and _hospital_prefix(value.id,old_id):
			ids[value.id] = new_id+str(value.id).substr(old_id.length())
		for key: Variant in value:
			if (field in INSTANCE_KEY_MAPS or _typed_instance_map(path)) and _hospital_prefix(str(key),old_id):
				ids[str(key)] = new_id+str(key).substr(old_id.length())
			var child_path: Array[String] = path.duplicate()
			child_path.append(str(key))
			_collect_instance_ids(value[key],old_id,new_id,ids,str(key),child_path)
	elif value is Array:
		for element: Variant in value:
			_collect_instance_ids(element,old_id,new_id,ids,field,path)
	elif value is String and _instance_field(field) and _hospital_prefix(value,old_id):
		ids[value] = new_id+str(value).substr(old_id.length())

func _rewrite_ids(value: Variant,field: String,old_id: String,new_id: String,ids: Dictionary,path: Array[String] = []) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			var original: String = str(key)
			var rewritten: String = original
			if field in INSTANCE_KEY_MAPS or _typed_instance_map(path) or (value[key] is Dictionary and value[key].get("id")==original):
				rewritten = str(ids.get(original,original))
			if value[key] is Dictionary and value[key].get("owner_id") is String and value[key].get("component") is String and original==str(value[key].owner_id)+":"+str(value[key].component):
				rewritten = str(ids.get(value[key].owner_id,value[key].owner_id))+":"+str(value[key].component)
			var child_path: Array[String] = path.duplicate()
			child_path.append(original)
			result[rewritten] = _rewrite_ids(value[key],original,old_id,new_id,ids,child_path)
		return result
	if value is Array:
		var result: Array = []
		for element: Variant in value:
			result.append(_rewrite_ids(element,field,old_id,new_id,ids,path))
		return result
	if value is String:
		if field=="hospital_id" and value==old_id:
			return new_id
		if _instance_field(field):
			return ids.get(value,value)
	return value

static func _typed_instance_map(path: Array[String]) -> bool:
	# These owners index by actor, visit, room, staff or completed training job.
	# Other dictionaries (definitions, dates, cells and anger causes) retain their keys.
	if path.is_empty():
		return false
	var owner: String = path[0]
	var field: String = path.back()
	if path.size()==1:
		return owner in ["wait_departures","adaptations"]
	if owner=="waiting_life" and path.size()==2:
		return field in ["seats","needs","clocks"]
	if owner=="staff_life" and path.size()==2:
		return field in ["personal_beds","reservations"]
	if owner=="departments":
		return (path.size()==2 and field in ["room_focus","routes","guidance","experience","staff_jobs"]) or (path.size()==3 and path[1]=="staff_days") or (path.size()==4 and path[1]=="experience" and field in ["retired_tickets","started_services","completed_services","staff_names"])
	if owner=="inventory" and path.size()==3 and path[1]=="shortage":
		return field=="participants"
	if owner=="staff_schedule" and path.size()==2:
		return field=="handoffs"
	if owner=="staff" and path.size()==3:
		return field=="completed_courses"
	if owner=="visits" and path.size()==3:
		return field=="clinical_participants"
	return owner in ["maintenance","environment"] and field=="contributions"

static func _instance_field(field: String) -> bool:
	return not field in DEFINITION_IDS and (field=="id" or field.ends_with("_id") or field.ends_with("_ids") or field in INSTANCE_ARRAYS)

static func _hospital_prefix(value: String,hospital_id: String) -> bool:
	return value.begins_with(hospital_id+":") or value.begins_with(hospital_id+"_") or value.begins_with(hospital_id+"/")

func trash_hospital(hospital_id: String,active_hospital_id: String = "") -> Dictionary:
	if busy() or not HospitalSnapshots.valid_uuid(hospital_id) or hospital_id==active_hospital_id:
		return _error("当前医院或资料写入中的医院不能移入回收站")
	var source: String = HospitalSnapshots.ROOT.path_join(hospital_id)
	var destination: String = TRASH.path_join(hospital_id)
	if DirAccess.dir_exists_absolute(destination):
		return _error("回收站已有相同身份医院，请先恢复该医院")
	var record: Dictionary = _latest_manifest(hospital_id)
	if not record.ok:
		return record
	if DirAccess.make_dir_recursive_absolute(TRASH)!=OK:
		return _error("无法创建医院回收站")
	var metadata: Dictionary = {"hospital_id":hospital_id,"deleted_utc":Time.get_datetime_string_from_system(true),"deleted_unix":int(Time.get_unix_time_from_system()),"manifest":record.manifest}
	if not HospitalSnapshots._store(source.path_join(TRASH_RECORD),JSON.stringify(metadata,"",true,true).to_utf8_buffer()):
		return _error("无法记录删除时间，原医院保留")
	if DirAccess.rename_absolute(source,destination)!=OK:
		DirAccess.remove_absolute(source.path_join(TRASH_RECORD))
		return _error("医院移入回收站失败，请检查文件占用和权限")
	cancel_scan()
	return {"ok":true,"hospital_id":hospital_id}

func _trash_manifest(hospital_id: String) -> Dictionary:
	var path: String = TRASH.path_join(hospital_id).path_join(TRASH_RECORD)
	var file: FileAccess = FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>69632:
		return _error("回收医院清单缺失或超过限额")
	var parser: JSON = JSON.new()
	if parser.parse(file.get_as_text())!=OK or not parser.data is Dictionary:
		return _error("回收医院清单无效")
	var record: Dictionary = parser.data
	if record.get("hospital_id")!=hospital_id or not record.get("manifest") is Dictionary or not WorldState._natural(record.get("deleted_unix",-1)):
		return _error("回收医院身份无效")
	var manifest: Dictionary = record.manifest
	var validated: Dictionary = snapshots._parse_manifest(JSON.stringify(manifest,"",true,true).to_utf8_buffer(),hospital_id,str(manifest.get("snapshot_id","")))
	if not validated.ok:
		return validated
	validated.deleted_utc = str(record.get("deleted_utc",""))
	validated.cleanup_due = Time.get_unix_time_from_system()-int(record.deleted_unix)>=30*86400
	return validated

func restore_hospital(hospital_id: String) -> Dictionary:
	if busy() or not snapshots.guard.call("is_held") or not HospitalSnapshots.valid_uuid(hospital_id):
		return _error("当前资料操作尚未完成或医院身份无效")
	var record: Dictionary = _trash_manifest(hospital_id)
	if not record.ok:
		return record
	var source: String = TRASH.path_join(hospital_id)
	var destination: String = HospitalSnapshots.ROOT.path_join(hospital_id)
	if DirAccess.dir_exists_absolute(destination):
		return _error("原医院身份目录已存在，回收医院保留，不能覆盖现有资料")
	if DirAccess.rename_absolute(source,destination)!=OK:
		return _error("医院恢复失败，请检查文件占用和权限")
	DirAccess.remove_absolute(destination.path_join(TRASH_RECORD))
	cancel_scan()
	return {"ok":true,"hospital_id":hospital_id}

func delete_slot(hospital_id: String,snapshot_id: String,_active_hospital_id: String = "") -> Dictionary:
	if busy() or not HospitalSnapshots.valid_uuid(snapshot_id):
		return _error("资料写入中或保存点身份无效")
	var survivor: bool = false
	for record: Dictionary in snapshots.list_commits(hospital_id):
		if record.snapshot_id!=snapshot_id and snapshots.load_commit(hospital_id,record.snapshot_id).ok:
			survivor = true
			break
	if not survivor:
		return _error("不能删除医院最后一个有效保存点")
	var opened: Dictionary = snapshots._connect(hospital_id)
	if not opened.ok:
		return opened
	var result: Dictionary = opened.database.call("execute","BEGIN IMMEDIATE",[])
	if result.ok:
		result = opened.database.call("execute","DELETE FROM snapshots WHERE snapshot_id=?",[snapshot_id])
	if result.ok:
		result = opened.database.call("execute","COMMIT",[])
	opened.database.call("close")
	if result.ok:
		cancel_scan()
	return result

func _prepare_staging(hospital_id: String) -> Dictionary:
	var path: String = HospitalSnapshots.ROOT.path_join(hospital_id)
	if DirAccess.dir_exists_absolute(path) or DirAccess.make_dir_recursive_absolute(path)!=OK:
		return _error("无法创建唯一医院暂存目录")
	if not HospitalSnapshots._store(path.path_join(PENDING),PackedByteArray([1])):
		DirAccess.remove_absolute(path)
		return _error("无法记录医院暂存身份")
	return {"ok":true}

func _remove_staging(hospital_id: String) -> void:
	if not HospitalSnapshots.valid_uuid(hospital_id):
		return
	var path: String = HospitalSnapshots.ROOT.path_join(hospital_id)
	if not FileAccess.file_exists(path.path_join(PENDING)):
		return
	for filename: String in [HospitalSnapshots.DATABASE_NAME+"-journal",HospitalSnapshots.DATABASE_NAME,PENDING]:
		DirAccess.remove_absolute(path.path_join(filename))
	DirAccess.remove_absolute(path)

static func thumbnail_valid(raw: PackedByteArray) -> bool:
	if raw.size()<24 or raw.size()>262144 or raw.slice(0,8)!=PackedByteArray([137,80,78,71,13,10,26,10]) or raw.slice(12,16).get_string_from_ascii()!="IHDR":
		return false
	var width: int = (int(raw[16])<<24)|(int(raw[17])<<16)|(int(raw[18])<<8)|int(raw[19])
	var height: int = (int(raw[20])<<24)|(int(raw[21])<<16)|(int(raw[22])<<8)|int(raw[23])
	if width<1 or height<1 or width>640 or height>360:
		return false
	var image: Image = Image.new()
	return image.load_png_from_buffer(raw)==OK and image.get_width()==width and image.get_height()==height

static func _error(message: String) -> Dictionary:
	return {"ok":false,"error":message}
