extends SceneTree

const Factory = preload("res://tools/assets/asset_factory.gd")
var failures: Array[String] = []
var checked_models: int = 0
var checked_scenes: int = 0
var checked_clinical_states: int = 0
var checked_appearances: int = 0
var checked_staff_combinations: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _read(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string("res://" + path))

func _materials(node: Node, path: String) -> void:
	if node is MeshInstance3D:
		var mesh: MeshInstance3D = node as MeshInstance3D
		for surface: int in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = mesh.get_active_material(surface) as StandardMaterial3D
			if material == null or not material.vertex_color_use_as_albedo:
				failures.append("Vertex color material missing " + path)
	for child: Node in node.get_children():
		_materials(child, path)

func _save_library(model_path: String, output: String) -> void:
	var node: Node3D = Factory.instantiate_asset(model_path)
	if node == null:
		failures.append("Cannot instantiate " + model_path)
		return
	var player: AnimationPlayer = Factory.find_player(node)
	_materials(node, model_path)
	if player == null:
		failures.append("No animation player " + model_path)
		node.free()
		return
	var library := AnimationLibrary.new()
	for name: StringName in player.get_animation_list():
		if str(name) == "RESET":
			continue
		var animation: Animation = player.get_animation(name).duplicate(true) as Animation
		animation.resource_path = ""
		for track: int in animation.get_track_count():
			if animation.track_get_type(track) in [Animation.TYPE_METHOD, Animation.TYPE_AUDIO]:
				failures.append("Forbidden callback track " + model_path)
		library.add_animation(str(name).get_file(), animation)
	DirAccess.make_dir_recursive_absolute("res://" + output.get_base_dir())
	if ResourceSaver.save(library, "res://" + output) != OK:
		failures.append("Cannot save library " + output)
	node.free()

func _case_states(record: Dictionary) -> void:
	var node: Node3D = Factory.instantiate_asset(str(record.path))
	var skeleton: Skeleton3D = Factory.find_skeleton(node)
	var symptom: int = skeleton.find_bone("symptom")
	var recovered: int = skeleton.find_bone("recovered")
	for phase: String in ["symptom", "prepare", "process", "climax", "safe_finish", "failure", "paused", "awaiting_result", "recovery", "low_motion_work", "low_motion_recovery"]:
		if not Factory.seek(node, phase, 0.47):
			failures.append("Case phase unavailable " + str(record.id) + ":" + phase)
			continue
		var is_cured: bool = phase in ["recovery", "low_motion_recovery"]
		var symptom_scale: Vector3 = skeleton.get_bone_pose_scale(symptom)
		var recovered_scale: Vector3 = skeleton.get_bone_pose_scale(recovered)
		if (is_cured and (symptom_scale.length() > 0.1 or recovered_scale.length() < 1.0)) or (not is_cured and (symptom_scale.length() < 1.0 or recovered_scale.length() > 0.1)):
			failures.append("Premature or missing result visibility " + str(record.id) + ":" + phase)
		checked_clinical_states += 1
	node.free()

func _combinations() -> void:
	var species: Array = _read("content/core/species.json")
	var roles: Array[String] = ["doctor", "nurse", "receptionist", "cleaner", "mechanic", "researcher", "decorator"]
	for definition: Dictionary in species:
		for appearance: int in range(1, 5):
			var node: Node3D = Factory.body(str(definition.id), appearance)
			if node == null:
				failures.append("Appearance cannot assemble " + str(definition.id) + ":" + str(appearance))
			else:
				_materials(node, str(definition.id))
				node.free()
			checked_appearances += 1
		for role: String in roles:
			var node: Node3D = Factory.body(str(definition.id), 1, role)
			if node == null:
				failures.append("Staff combination cannot assemble " + str(definition.id) + ":" + role)
			else:
				Factory.seek(node, "job_operate", 0.47)
				Factory.seek(node, "job_sleep", 0.47)
				node.free()
			checked_staff_combinations += 1

func _staff_libraries() -> void:
	var species: Array = _read("content/core/species.json")
	var adapters: Array = _read("content/core/staff_rig_adapters.json")
	for adapter: Dictionary in adapters:
		var prototype: Dictionary = {}
		for body: Dictionary in species:
			if body.rig == adapter.rig:
				prototype = body
				break
		var node: Node3D = Factory.instantiate_asset("assets/models/core_" + str(prototype.id).to_lower() + "_body.glb")
		var skeleton: Skeleton3D = Factory.find_skeleton(node)
		var player: AnimationPlayer = Factory.find_player(node)
		var base: Node = player.get_node(player.root_node)
		var skeleton_path: String = str(base.get_path_to(skeleton))
		var library := AnimationLibrary.new()
		for action: String in adapter.actions:
			for low_motion: bool in [false, true]:
				var animation := Animation.new()
				animation.length = 2.0
				var bones: Array[String] = ["head", "spine", "hand_l", "hand_r"]
				if str(adapter.rig) == "biped":
					bones.append("hips")
				for bone: String in bones:
					if skeleton.find_bone(bone) < 0:
						continue
					var track: int = animation.add_track(Animation.TYPE_ROTATION_3D)
					animation.track_set_path(track, NodePath(skeleton_path + ":" + bone))
					for step: int in 5:
						var fraction: float = float(step) / 4.0
						var angle: float = 0.035 if low_motion else sin(fraction * TAU) * (0.10 if bone.begins_with("hand") else 0.045)
						if action in ["sleep", "rest"]:
							angle = 1.35 if bone == "hips" else (0.16 if bone == "head" else 0.0)
						elif action == "wake":
							angle = 1.35 * (1.0 - fraction) if bone == "hips" else -0.1 * sin(fraction * PI)
						elif action == "record" and bone.begins_with("hand"):
							angle *= 0.5
						animation.rotation_track_insert_key(track, fraction * 2.0, Quaternion(Vector3.RIGHT, angle))
				library.add_animation("job_" + action + ("_low_motion" if low_motion else ""), animation)
		DirAccess.make_dir_recursive_absolute("res://assets/animations/staff")
		ResourceSaver.save(library, "res://assets/animations/staff/" + str(adapter.rig) + ".tres")
		node.free()

func _routines() -> void:
	var routines: Array = _read("content/core/treatment_routines.json")
	for routine: Dictionary in routines:
		var library := AnimationLibrary.new()
		var phases: Array[String] = ["prepare", "process", "climax", "safe_finish"]
		for index: int in phases.size():
			for gentle: bool in [false, true]:
				var clip := Animation.new()
				clip.length = 1.0
				var track: int = clip.add_track(Animation.TYPE_VALUE)
				clip.track_set_path(track, NodePath("Tool:rotation"))
				clip.track_insert_key(track, 0.0, Vector3.ZERO)
				clip.track_insert_key(track, 0.5, Vector3(0.03 if gentle else 0.07, 0.01 * float(index), 0))
				clip.track_insert_key(track, 1.0, Vector3.ZERO)
				clip.set_meta("source_beat", routine.beats[index])
				library.add_animation(("gentle_" if gentle else "") + phases[index], clip)
		DirAccess.make_dir_recursive_absolute("res://assets/animations/treatments")
		ResourceSaver.save(library, "res://assets/animations/treatments/" + str(routine.id).to_lower() + ".tres")

func _run() -> void:
	var manifest: Dictionary = _read("assets/models/complete-production.json")
	for record: Dictionary in manifest.assets:
		var node: Node3D = Factory.instantiate_asset(str(record.asset_path))
		if node == null:
			failures.append("Cannot load " + str(record.asset_path))
			continue
		if FileAccess.get_sha256("res://" + str(record.asset_path)) != str(record.asset_sha256):
			failures.append("Published model identity mismatch " + str(record.asset_path))
		_materials(node, str(record.asset_path))
		var skeleton: Skeleton3D = Factory.find_skeleton(node)
		if skeleton == null or skeleton.get_bone_count() != int(record.bone_count):
			failures.append("Bone count mismatch " + str(record.asset_path))
		else:
			for i: int in record.joint_order.size():
				if str(skeleton.get_bone_name(i)) != str(record.joint_order[i]):
					failures.append("Joint order mismatch " + str(record.asset_path))
		for clip: String in record.animation_names:
			if not Factory.seek(node, clip, 0.47):
				failures.append("Clip missing " + str(record.asset_path) + ":" + clip)
		checked_models += 1
		node.free()
	var cases: Dictionary = _read("assets/cases/index.json")
	for record: Dictionary in cases.cases:
		_save_library(str(record.path), "assets/animations/cases/" + str(record.id).to_lower() + ".tres")
		_case_states(record)
		checked_models += 1
	var surgeries: Dictionary = _read("assets/surgery/index.json")
	for record: Dictionary in surgeries.adapters:
		_save_library(str(record.path), "assets/animations/surgery/" + str(record.id).to_lower() + ".tres")
		checked_models += 1
	_staff_libraries()
	_routines()
	_combinations()
	for index_path: String in ["assets/accessories/index.json", "assets/props/index.json", "assets/props/library/index.json", "assets/upgrades/index.json", "assets/architecture/index.json"]:
		var data: Dictionary = _read(index_path)
		for entries: Variant in data.values():
			if not entries is Array:
				continue
			for record: Dictionary in entries:
				var node: Node3D = Factory.instantiate_asset(str(record.path))
				if node == null:
					failures.append("Cannot instantiate " + str(record.path))
				else:
					_materials(node, str(record.path))
					node.free()
				checked_models += 1
	var presentations: Dictionary = _read("assets/presentation/index.json")
	for record: Dictionary in presentations.scenes:
		var scene: PackedScene = load("res://" + str(record.path)) as PackedScene
		if scene == null:
			failures.append("Scene cannot load " + str(record.path))
		else:
			var instance: Node = scene.instantiate()
			if instance == null:
				failures.append("Scene cannot instantiate " + str(record.path))
			else:
				instance.free()
		checked_scenes += 1
	for routine: Dictionary in _read("content/core/treatment_routines.json"):
		var path: String = "res://assets/presentation/treatments/" + str(routine.id).to_lower() + ".tscn"
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			failures.append("Routine scene cannot load " + path)
		else:
			packed.instantiate().free()
		checked_scenes += 1
	var plan: Dictionary = _read("assets/asset-plan.json")
	for requirement: Dictionary in plan.requirements:
		for path: String in requirement.required_paths:
			if not FileAccess.file_exists("res://" + path):
				failures.append("Missing required file " + path)
	var audio: Dictionary = _read("assets/audio/index.json")
	for clip: Dictionary in audio.clips:
		var stream: AudioStreamOggVorbis = load("res://" + str(clip.path)) as AudioStreamOggVorbis
		if stream == null or absf(stream.get_length() - float(clip.duration_seconds)) > 0.01:
			failures.append("Invalid imported audio " + str(clip.id))
		else:
			stream.loop = bool(clip.loop)
			clip.godot_import_status = "decoded and loop policy verified in Godot " + Engine.get_version_info().string
	var output: Dictionary = {"engine": Engine.get_version_info().string, "models_checked": checked_models,
		"scenes_checked": checked_scenes, "requirements_checked": plan.requirements.size(),
		"audio_checked": audio.clips.size(), "clinical_state_checks": checked_clinical_states,
		"appearance_assemblies": checked_appearances,"staff_assemblies":checked_staff_combinations,
		"model_manifest_sha256":FileAccess.get_sha256("res://assets/models/complete-production.json"),
		"case_index_sha256":FileAccess.get_sha256("res://assets/cases/index.json"),
		"factory_sha256":FileAccess.get_sha256("res://tools/assets/asset_factory.gd"),
		"failures": failures,
		"rendering": "headless import validation; visual and actual backend measurements separate"}
	DirAccess.make_dir_recursive_absolute("res://art-source/production/validation")
	var file := FileAccess.open("res://art-source/production/validation/godot-import.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	var audio_file := FileAccess.open("res://assets/audio/index.json", FileAccess.WRITE)
	audio_file.store_string(JSON.stringify(audio, "\t"))
	audio_file.close()
	var summary: Dictionary = output.duplicate()
	summary.failures = failures.slice(0, 20)
	summary.failure_count = failures.size()
	print("ASSET_IMPORT_RESULT=" + JSON.stringify(summary))
	quit(0 if failures.is_empty() else 1)
