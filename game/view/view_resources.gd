extends RefCounted

# Packed scenes retain shared meshes, materials and clips. Instances retain only
# their own pose. The last visible user releases the cache's strong reference.
const MANIFEST: String = "res://assets/models/stage01-production.json"
var errors: Array[String] = []
var _definitions: Dictionary = {}
var _entries: Dictionary = {}

func _init() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not data is Dictionary or not data.get("assets") is Array:
		errors.append(MANIFEST+": 资源清单结构无效")
		return
	for record: Variant in data.assets:
		if not record is Dictionary or not record.get("asset_path") is String:
			errors.append(MANIFEST+": 资源路径缺失")
			continue
		var path: String = "res://"+str(record.asset_path)
		if _definitions.has(path) or not path.begins_with("res://assets/") or ".." in path:
			errors.append(path+": 资源身份重复或路径无效")
			continue
		if not record.get("surfaces") is Array or not record.get("joint_order") is Array or not record.get("animation_names") is Array or not record.get("anchors_engine_local_m") is Dictionary or not record.get("rest_mesh_bounds_engine_m") is Dictionary:
			errors.append(path+": 材质、骨序、插槽、姿态或包络清单缺失")
			continue
		if int(record.get("surface_count",-1))!=record.surfaces.size() or int(record.get("bone_count",-1))!=record.joint_order.size() or int(record.get("bytes",0))<=0 or str(record.get("asset_sha256","")).length()!=64:
			errors.append(path+": 资源清单数量或内容身份无效")
			continue
		for surface: Dictionary in record.surfaces:
			if surface.get("alpha_mode","") not in ["OPAQUE","MASK","BLEND"] or str(surface.get("material","")).is_empty():
				errors.append(path+": Surface 材质分类无效")
		_definitions[path] = record

func acquire(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	if not _entries.has(path):
		var definition: Dictionary = _definitions.get(path,{})
		if not definition.is_empty() and FileAccess.get_sha256(path)!=definition.asset_sha256:
			_report(path+": 资源哈希与发布清单不一致")
			return null
		var packed: PackedScene = ResourceLoader.load(path) as PackedScene
		if packed==null:
			_report(path+": 无法导入三维场景")
			return null
		var bytes: int = int(definition.bytes) if definition.has("bytes") else FileAccess.get_file_as_bytes(path).size()
		_entries[path] = {"scene":packed,"users":0,"bytes":bytes,"validated":false}
	var node: Node3D = (_entries[path].scene as PackedScene).instantiate() as Node3D
	if node==null:
		_report(path+": 资源根节点必须为 Node3D")
		return null
	if not _entries[path].validated and not _validate_instance(node,_definitions.get(path,{}),path):
		node.free()
		if int(_entries[path].users)==0:
			_entries.erase(path)
		return null
	_entries[path].validated = true
	_entries[path].users += 1
	node.set_meta("shared_resource_path",path)
	return node

func release_tree(node: Node) -> void:
	for child: Node in node.get_children():
		release_tree(child)
	if node.has_meta("shared_resource_path"):
		var path: String = str(node.get_meta("shared_resource_path"))
		if _entries.has(path):
			_entries[path].users -= 1
			if int(_entries[path].users)<=0:
				_entries.erase(path)
		node.remove_meta("shared_resource_path")

func usage() -> Dictionary:
	var bytes: int = 0
	var users: int = 0
	for entry: Dictionary in _entries.values():
		bytes += int(entry.bytes)
		users += int(entry.users)
	return {"shared_scenes":_entries.size(),"instance_users":users,"source_bytes":bytes,"errors":errors.duplicate(),"allocation_measurement":"not_measured"}

func _validate_instance(root: Node3D, definition: Dictionary, path: String) -> bool:
	if definition.is_empty():
		return true
	var meshes: Array[MeshInstance3D] = []
	var skeletons: Array[Skeleton3D] = []
	var players: Array[AnimationPlayer] = []
	_collect(root,meshes,skeletons,players)
	var count: int = 0
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh==null:
			continue
		for surface: int in mesh.mesh.get_surface_count():
			var material: Material = mesh.get_active_material(surface)
			if material==null:
				_report(path+": 导入 Surface 缺少材质")
				return false
			count += 1
	if count!=int(definition.surface_count):
		_report(path+": 导入 Surface 数量与发布清单不一致")
		return false
	if int(definition.bone_count)>0:
		if skeletons.size()!=1 or skeletons[0].get_bone_count()!=int(definition.bone_count):
			_report(path+": 导入骨架与发布清单不一致")
			return false
		for index: int in definition.joint_order.size():
			if str(skeletons[0].get_bone_name(index))!=str(definition.joint_order[index]):
				_report(path+": 导入骨序不一致："+str(index))
				return false
		for slot: String in definition.anchors_engine_local_m:
			if skeletons[0].find_bone(slot)<0:
				_report(path+": 缺少必要插槽："+slot)
				return false
	for requested: String in definition.animation_names:
		var found: bool = false
		for player: AnimationPlayer in players:
			for clip: StringName in player.get_animation_list():
				if str(clip)==requested or str(clip).ends_with("/"+requested):
					found = true
		if not found:
			_report(path+": 缺少清单姿态："+requested)
			return false
	return true

func _collect(node: Node, meshes: Array[MeshInstance3D], skeletons: Array[Skeleton3D], players: Array[AnimationPlayer]) -> void:
	if node is MeshInstance3D:
		meshes.append(node)
	if node is Skeleton3D:
		skeletons.append(node)
	if node is AnimationPlayer:
		players.append(node)
	for child: Node in node.get_children():
		_collect(child,meshes,skeletons,players)

func _report(reason: String) -> void:
	if not reason in errors:
		errors.append(reason)
