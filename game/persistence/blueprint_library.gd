class_name HospitalBlueprintLibrary
extends RefCounted

const DIRECTORY: String = "user://blueprints"
var blueprints: HospitalBlueprints

func _init(service: HospitalBlueprints) -> void:
	blueprints = service

func list_page(after: String = "", limit: int = 30) -> Dictionary:
	var directory: DirAccess = DirAccess.open(DIRECTORY)
	if directory==null:
		return {"ok":true,"items":[],"next_cursor":""} if not DirAccess.dir_exists_absolute(DIRECTORY) else BuildGeometry.failure("无法读取蓝图库")
	var ids: Array = []
	for filename: String in directory.get_files():
		if filename.ends_with(".json") and valid_id(filename.trim_suffix(".json")): ids.append(filename.trim_suffix(".json"))
	ids.sort()
	var items: Array = []
	var next: String = ""
	for id: String in ids:
		if id<=after: continue
		if items.size()>=maxi(1,limit):
			next = str(items[-1].id)
			break
		var result: Dictionary = load_blueprint(id)
		items.append(result.blueprint if result.ok else {"id":id,"name":"无法读取的蓝图","error":result.reason})
	return {"ok":true,"items":items,"next_cursor":next}

func load_blueprint(id: String) -> Dictionary:
	if not valid_id(id): return BuildGeometry.failure("蓝图身份无效")
	var file: FileAccess = FileAccess.open(DIRECTORY.path_join(id+".json"),FileAccess.READ)
	if file==null: return BuildGeometry.failure("蓝图文件不可读取")
	var parser: JSON = JSON.new()
	var code: Error = parser.parse(file.get_as_text())
	file.close()
	if code!=OK: return BuildGeometry.failure("蓝图JSON格式无效")
	var data: Variant = parser.data
	if not data is Dictionary or data.get("id","")!=id or not WorldState._natural(data.get("revision")) or int(data.revision)<1: return BuildGeometry.failure("蓝图身份或修订与文件不符")
	var reason: String = blueprints.validate_definition(data)
	if not reason.is_empty():
		if reason.begins_with("缺少"): return {"ok":false,"reason":reason,"editable":true,"blueprint":data}
		return BuildGeometry.failure(reason)
	return {"ok":true,"reason":"","blueprint":data}

func save(blueprint: Dictionary, name: String, description: String, thumbnail: String = "") -> Dictionary:
	var reason: String = blueprints.validate_definition(blueprint)
	if not reason.is_empty(): return BuildGeometry.failure(reason)
	if name.strip_edges().is_empty(): return BuildGeometry.failure("请填写蓝图名称")
	var data: Dictionary = blueprint.duplicate(true)
	var id: String = str(data.get("id",""))
	if not valid_id(id):
		var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
		bytes[6] = (bytes[6]&15)|64
		bytes[8] = (bytes[8]&63)|128
		var hex: String = bytes.hex_encode()
		id = "%s-%s-%s-%s-%s" % [hex.substr(0,8),hex.substr(8,4),hex.substr(12,4),hex.substr(16,4),hex.substr(20)]
		data.revision = 1
	elif FileAccess.file_exists(DIRECTORY.path_join(id+".json")):
		var old: Dictionary = load_blueprint(id)
		if not old.ok: return old
		if int(data.revision)!=int(old.blueprint.revision): return BuildGeometry.failure("蓝图修订已变化，请重新载入")
		data.revision = int(data.revision)+1
	data.id = id
	data.name = name.strip_edges()
	data.description = description
	data.thumbnail = thumbnail
	data.content_dependencies = blueprints.dependencies(data)
	var created: Error = DirAccess.make_dir_recursive_absolute(DIRECTORY)
	if created!=OK: return BuildGeometry.failure("无法创建蓝图库目录")
	var path: String = DIRECTORY.path_join(id+".json")
	var temporary: String = path+".tmp"
	var file: FileAccess = FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: return BuildGeometry.failure("无法写入蓝图临时文件，原蓝图保留")
	file.store_string(JSON.stringify(data,"\t",true,true))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error!=OK or DirAccess.rename_absolute(temporary,path)!=OK: return BuildGeometry.failure("蓝图未完成替换，原蓝图保留")
	return {"ok":true,"reason":"","blueprint":data}

func remove(id: String) -> Dictionary:
	if not valid_id(id): return BuildGeometry.failure("蓝图身份无效")
	var code: Error = DirAccess.remove_absolute(DIRECTORY.path_join(id+".json"))
	return {"ok":true,"reason":""} if code==OK else BuildGeometry.failure("蓝图删除失败")

static func valid_id(id: String) -> bool:
	var regex: RegEx = RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	return regex.search(id)!=null
