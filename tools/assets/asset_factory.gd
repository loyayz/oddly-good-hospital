extends RefCounted

static var _tint_cache: Dictionary = {}
static var _case_definitions: Dictionary = {}
static var _body_definitions: Dictionary = {}
static var _equipment_definitions: Dictionary = {}

## Assemble read-only assets. Callers own identity, service state and progress.
static func find_skeleton(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var result: Skeleton3D = find_skeleton(child)
		if result != null:
			return result
	return null

static func find_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var result: AnimationPlayer = find_player(child)
		if result != null:
			return result
	return null

static func seek(node: Node, requested: String, fraction: float) -> bool:
	var player: AnimationPlayer = find_player(node)
	if player == null:
		return false
	for clip: StringName in player.get_animation_list():
		if str(clip) == requested or str(clip).ends_with("/" + requested):
			var skeleton: Skeleton3D = find_skeleton(node)
			if skeleton != null:
				skeleton.reset_bone_poses()
			player.play(clip)
			player.seek(clampf(fraction, 0.0, 1.0) * player.get_animation(clip).length, true)
			player.pause()
			if skeleton != null and requested.begins_with("job_"):
				for index: int in skeleton.get_bone_count():
					if str(skeleton.get_bone_name(index)).begins_with("eye_"):
						var openness: float = 0.10 if requested.contains("sleep") or requested.contains("rest") else (lerpf(0.1, 1.0, fraction) if requested.contains("wake") else 1.0)
						skeleton.set_bone_pose_scale(index, Vector3(1, openness, 1))
			if skeleton != null and bool(node.get_meta("hide_default_hair", false)):
				var hair: int = skeleton.find_bone("hair")
				if hair >= 0:
					skeleton.set_bone_pose_scale(hair, Vector3.ONE * 0.001)
			return true
	return false

static func instantiate_asset(path: String) -> Node3D:
	var scene: PackedScene = load("res://" + path) as PackedScene
	return scene.instantiate() as Node3D if scene != null else null

static func tint_instance(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		for index: int in mesh_node.mesh.get_surface_count():
			var original: Material = mesh_node.get_active_material(index)
			if original is StandardMaterial3D:
				if tint == Color.WHITE:
					continue
				var key: String = original.resource_path + ":" + str(original.resource_name) + ":" + tint.to_html()
				if not _tint_cache.has(key):
					var tinted: StandardMaterial3D = original.duplicate() as StandardMaterial3D
					tinted.albedo_color *= tint
					_tint_cache[key] = tinted
				var material: StandardMaterial3D = _tint_cache[key]
				mesh_node.set_surface_override_material(index, material)
	for child: Node in node.get_children():
		tint_instance(child, tint)

static func attach(node: Node3D, path: String, slot: String, scale_factor: float = 1.0) -> Node3D:
	var skeleton: Skeleton3D = find_skeleton(node)
	if skeleton == null or skeleton.find_bone(slot) < 0:
		return null
	var prop: Node3D = instantiate_asset(path)
	if prop == null:
		return null
	var mount := BoneAttachment3D.new()
	mount.name = "Accessory_" + str(node.get_child_count())
	mount.bone_name = slot
	skeleton.add_child(mount)
	mount.add_child(prop)
	var rest: Transform3D = skeleton.get_bone_global_rest(skeleton.find_bone(slot))
	prop.basis = rest.basis.inverse().scaled(Vector3.ONE * scale_factor)
	return prop

static func _visual_boxes(node: Node, parent_transform: Transform3D, boxes: Array[AABB]) -> void:
	var transform: Transform3D = parent_transform
	if node is Node3D:
		transform *= (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		boxes.append(transform * (node as MeshInstance3D).get_aabb())
	for child: Node in node.get_children():
		_visual_boxes(child, transform, boxes)

static func fit_accessory(node: Node3D, prop: Node3D, slot: String, dimensions: Dictionary, factor: float, on_head: bool, offset: Vector3 = Vector3.ZERO) -> void:
	if prop == null:
		return
	var skeleton: Skeleton3D = find_skeleton(node)
	var rest: Transform3D = skeleton.get_bone_global_rest(skeleton.find_bone(slot))
	var boxes: Array[AABB] = []
	_visual_boxes(prop, prop.transform.affine_inverse(), boxes)
	if boxes.is_empty():
		return
	var bounds: AABB = boxes[0]
	for box: AABB in boxes:
		bounds = bounds.merge(box)
	var body_box := AABB(Vector3(-float(dimensions.width_m) / 2.0, 0, -float(dimensions.depth_m) / 2.0), Vector3(float(dimensions.width_m), float(dimensions.height_m), float(dimensions.depth_m)))
	if on_head:
		offset.y = float(dimensions.height_m) - rest.origin.y - bounds.end.y * factor
	for _pass_index: int in 2:
		var center: Vector3 = rest.origin + offset
		for axis: int in 3:
			if bounds.end[axis] > 0.00001:
				factor = minf(factor, maxf(0.05, (body_box.end[axis] - center[axis]) / bounds.end[axis]))
			if bounds.position[axis] < -0.00001:
				factor = minf(factor, maxf(0.05, (body_box.position[axis] - center[axis]) / bounds.position[axis]))
		if on_head:
			offset.y = float(dimensions.height_m) - rest.origin.y - bounds.end.y * factor
	prop.basis = rest.basis.inverse().scaled(Vector3.ONE * factor * 0.98)
	prop.position = rest.basis.inverse() * offset

static func body(species_id: String, appearance: int = 1, role: String = "") -> Node3D:
	var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/appearances/core_" + species_id.to_lower() + ".json"))
	var node: Node3D = instantiate_asset(str(definition.body_path))
	if node == null:
		return null
	var look: Dictionary = definition.variants[clampi(appearance, 1, 4) - 1]
	var values: Array = look.tint
	tint_instance(node, Color(float(values[0]), float(values[1]), float(values[2]), float(values[3])))
	var rig: String = str(definition.rig)
	var skeleton: Skeleton3D = find_skeleton(node)
	var head_height: float = skeleton.get_bone_global_rest(skeleton.find_bone("head")).origin.y
	var prop: Node3D = attach(node, str(look.accessory_path), str(look.slot), clampf(head_height * 0.7, 0.4, 2.0))
	fit_accessory(node, prop, str(look.slot), definition.dimensions, clampf(head_height * 0.7, 0.4, 2.0), str(look.slot) == "head")
	if species_id == "S49":
		node.set_meta("hide_default_hair", true)
	if not role.is_empty():
		var uniform: Node3D = attach(node, "assets/accessories/uniforms/" + rig + "_" + role + ".glb", "spine", clampf(head_height * 0.6, 0.4, 2.0))
		fit_accessory(node, uniform, "spine", definition.dimensions, clampf(head_height * 0.6, 0.4, 2.0), false, Vector3(0, 0, float(definition.dimensions.depth_m) * 0.42))
	var player: AnimationPlayer = find_player(node)
	var library_path: String = "res://assets/animations/staff/" + rig + ".tres"
	if player != null and ResourceLoader.exists(library_path):
		player.add_animation_library("staff", load(library_path) as AnimationLibrary)
	seek(node, "idle", 0.0)
	return node

static func case_scene(binding_id: String, phase: String, progress: float, appearance: int = 1, low_motion: bool = false) -> Node3D:
	var group := Node3D.new()
	group.name = "ClinicalPresentation"
	var species: String = binding_id.split("_")[1]
	var patient: Node3D = body(species, appearance)
	var props: Node3D = instantiate_asset("assets/cases/" + binding_id.to_lower() + ".glb")
	if patient == null or props == null:
		group.free()
		return null
	patient.name = "Patient"
	props.name = "ClinicalProps"
	group.add_child(patient)
	group.add_child(props)
	seek_case(group, binding_id, phase, progress, low_motion)
	return group

static func equipment(definition_id: String, completed_level: int = 0, state: String = "idle", phase: String = "process", progress: float = 0.0) -> Node3D:
	if _equipment_definitions.is_empty():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/equipment-states.json"))
		for record: Dictionary in data.definitions:
			_equipment_definitions[str(record.id)] = record
	if not _equipment_definitions.has(definition_id):
		return null
	var definition: Dictionary = _equipment_definitions[definition_id]
	if not state in definition.states:
		return null
	var group := Node3D.new()
	group.name = "EquipmentPresentation"
	var base: Node3D = instantiate_asset(str(definition.base_path))
	group.add_child(base)
	if definition.upgrade_paths.has(str(completed_level)):
		group.add_child(instantiate_asset(str(definition.upgrade_paths[str(completed_level)])))
	if state in ["working", "using", "paused"]:
		seek(base, phase, progress)
	else:
		seek(base, "idle", 0.0)
	if state in ["broken", "repairing", "maintenance", "construction"]:
		var sign: Node3D = instantiate_asset("assets/props/library/key.glb" if state != "construction" else "assets/props/library/label.glb")
		sign.position = Vector3(0.25, 1.2, 0.1)
		group.add_child(sign)
	return group

static func seek_case(group: Node3D, binding_id: String, phase: String, progress: float, low_motion: bool = false) -> void:
	var patient: Node3D = group.get_node("Patient") as Node3D
	var props: Node3D = group.get_node("ClinicalProps") as Node3D
	var actual_phase: String = phase
	if low_motion:
		actual_phase = "low_motion_recovery" if phase in ["recovery", "recovery_hold"] else ("low_motion_work" if phase in ["prepare", "process", "climax", "work"] else "low_motion")
	seek(props, actual_phase, progress)
	var body_action: String = "recovery" if phase in ["recovery", "recovery_hold"] else ("work" if phase in ["prepare", "process", "climax", "work"] else "symptom")
	seek(patient, body_action, 0.5 if low_motion else progress)
	if _case_definitions.is_empty():
		var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cases/index.json"))
		for record: Dictionary in index.cases:
			_case_definitions[str(record.id)] = record
		var bodies: Array = JSON.parse_string(FileAccess.get_file_as_string("res://content/core/species.json"))
		for record: Dictionary in bodies:
			_body_definitions[str(record.id)] = record
	if not _case_definitions.has(binding_id) or phase in ["recovery", "recovery_hold", "low_motion_recovery"]:
		return
	var definition: Dictionary = _case_definitions[binding_id]
	var skeleton: Skeleton3D = find_skeleton(patient)
	var disease: int = str(definition.disease_id).substr(1).to_int()
	var offsets: Dictionary = {}
	if disease == 1 and str(definition.rig) == "longneck":
		offsets = {"neck": Vector3(0, 0, 0.22), "neck_mid": Vector3(0, 0, -0.34), "head": Vector3(0, 0, 0.12)}
	elif disease == 2:
		offsets = {"arm_5": Vector3(0.1, 0, 0.18), "arm_7": Vector3(-0.1, 0, -0.18)}
	elif disease == 3:
		offsets = {"head": Vector3(0.75, 0, 0)}
	elif disease == 9:
		offsets = {"foot_l": Vector3(0, PI, 0), "foot_r": Vector3(0, PI, 0)}
	elif disease == 18:
		offsets = {"head": Vector3(PI, 0, 0)}
	elif disease in [23, 37, 38, 39, 42]:
		offsets = {"head": Vector3(0.08 if disease != 39 else 0.0, 0.10 if disease == 39 else 0.0, 0)}
	for bone: String in offsets:
		var index: int = skeleton.find_bone(bone)
		if index >= 0:
			skeleton.set_bone_pose_rotation(index, Quaternion.from_euler(offsets[bone]))
	if disease in [4, 33]:
		var base: Dictionary = _body_definitions[str(definition.species_id)].body
		var envelope: Dictionary = definition.effective_body
		var index: int = skeleton.find_bone("spine" if disease == 33 else "head")
		skeleton.set_bone_pose_scale(index, Vector3(float(envelope.width_m) / float(base.width_m), float(envelope.height_m) / float(base.height_m), float(envelope.depth_m) / float(base.depth_m)))
	if disease in [23, 38]:
		for index: int in skeleton.get_bone_count():
			if str(skeleton.get_bone_name(index)).begins_with("eye_"):
				skeleton.set_bone_pose_scale(index, Vector3(1, 0.45, 1))
