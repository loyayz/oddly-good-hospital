extends SceneTree

const Batch = preload("res://game/view/skinned_pose_batch.gd")
const SkinInput = preload("res://game/view/compatibility_skin_input.gd")
const READBACK: Shader = preload("res://game/view/shaders/skin_readback.gdshader")
const READBACK_ORIGINAL: Shader = preload("res://game/view/shaders/skin_readback_original.gdshader")
const ASSET: String = "res://assets/models/core_s49_body.glb"
const OUTPUT: String = "res://.cache/validation/stage01-render"
const ANCHORS: Array[String] = ["head", "look_target", "hand_l", "hand_r", "treatment_anchor", "emotion_anchor", "carry_anchor"]

var _viewport: SubViewport
var _scene: Node3D
var _meshes: Array[MeshInstance3D] = []
var _skeletons: Array[Skeleton3D] = []
var _players: Array[AnimationPlayer] = []
var _original_points: Array[MeshInstance3D] = []
var _reference_materials: Array[ShaderMaterial] = []
var _palette_points: MultiMeshInstance3D
var _palette_material: ShaderMaterial
var _batch: Node3D
var _vertex_count: int = 0
var _point_count: int = 0
var _rows_per_actor: int = 0
var _point_arrays: Array = []
var _raw_point_mesh: ArrayMesh
var _raw_values: Array = []
var _last_neutral_values: Array = []
var _report: Dictionary = {}
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	_report = {"engine": Engine.get_version_info(), "display": DisplayServer.get_name(), "adapter": RenderingServer.get_video_adapter_name(), "vendor": RenderingServer.get_video_adapter_vendor(), "graphics_api": RenderingServer.get_video_adapter_api_version(), "render_driver": RenderingServer.get_current_rendering_driver_name(), "render_method": RenderingServer.get_current_rendering_method(), "command_arguments": OS.get_cmdline_args(), "cwd": ProjectSettings.globalize_path("res://"), "asset": ASSET, "asset_sha256": _hash(ASSET), "probe_sha256": _hash("res://tools/verify-stage01-render.gd"), "shader_sha256": _hash("res://game/view/shaders/skinned_pose.gdshader"), "include_sha256": _hash("res://game/view/shaders/skinned_pose.gdshaderinc"), "probe_shader_sha256": _hash("res://game/view/shaders/skin_readback.gdshader"), "samples": [], "limits": {"position_m": 0.005, "normal_degrees": 1.0, "tangent_degrees": 1.0, "anchor_m": 0.05}, "method": "GPU original MeshInstance3D + Skin + Skeleton3D transform-feedback output, captured after engine deformation in a point vertex shader; same rest vertices in MultiMesh use the production RGBAF shader include; nine RGB24 sRGB-compensated image readbacks reconstruct every vertex position, normal and tangent. CPU compares readbacks; CPU skin arithmetic is not the reference.", "uncovered": ["other eight rig families", "nonuniform bone scale and blend shapes", "alpha-blend sorting", "multiple surfaces and texture material adapters", "640-person performance and all-world budget", "complete future symptom and support poses"]}
	_report["import_hook_sha256"] = _hash("res://assets/models/import_vertex_colours.gd")
	_report["asset_import_sha256"] = _hash(ASSET + ".import")
	_report["component_sha256"] = _hash("res://game/view/skinned_pose_batch.gd")
	_report["original_input_adapter_sha256"] = _hash("res://game/view/compatibility_skin_input.gd")
	_report["surface_include_sha256"] = _hash("res://game/view/shaders/skinned_pose_surface.gdshaderinc")
	_report["double_sided_shader_sha256"] = _hash("res://game/view/shaders/skinned_pose_double_sided.gdshader")
	_report["original_probe_shader_sha256"] = _hash("res://game/view/shaders/skin_readback_original.gdshader")
	_report["readback_output_sha256"] = _hash("res://game/view/shaders/skin_readback_output.gdshaderinc")
	_report["invocation"] = [OS.get_executable_path(),"--path",ProjectSettings.globalize_path("res://"),"--rendering-method","gl_compatibility","--rendering-driver","opengl3","--script","tools/verify-stage01-render.gd"]
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_driver_name() != "opengl3":
		_failures.append("GPU 验收需要真实 Windows opengl3，不能使用 dummy/headless")
		_finish()
		return
	_make_scene()
	await process_frame
	var production_sources: Array[Dictionary] = []
	for mesh: MeshInstance3D in _meshes:
		var adapted: bool = SkinInput.input_active(mesh)
		var cost: Dictionary = SkinInput.resource_usage(mesh.mesh)
		production_sources.append({"active": adapted,"actual_imported_mesh": mesh.mesh.resource_path,"instance_script": mesh.get_script().resource_path if mesh.get_script()!=null else "","input_weight": mesh.get_blend_shape_value(0) if mesh.mesh.get_blend_shape_count()>0 else null,"payload_identity_exact": SkinInput.is_identity_input(mesh.mesh),"resource_cost": cost})
		if not adapted:
			_failures.append("实际生产导入网格未激活原 Skin 输入适配")
		if cost.is_empty():
			_failures.append("实际生产原管线资源测量缺失")
	_report["actual_production_original_sources"] = production_sources
	for row: int in 2:
		_set_pose(row, "work" if row == 0 else "walk", 0.5 if row == 0 else 1.5)
	await process_frame
	_batch = Batch.new()
	_scene.add_child(_batch)
	var bind_reason: String = _batch.bind_sources(_meshes, _skeletons)
	if not bind_reason.is_empty():
		_failures.append(bind_reason)
		_finish()
		return
	if not _batch.publish(AABB(Vector3(-3, -0.1, -1), Vector3(6, 2.5, 2))):
		_failures.append("合法 S49 姿态发布失败")
		_finish()
		return
	_make_readback_meshes()
	var calibration: Image = await _capture(4, 0, false)
	var calibration_error: int = 0
	for index: int in 256:
		calibration_error = maxi(calibration_error, absi(_code(calibration, index, 0) - index * 65793))
	calibration.save_png(OUTPUT + "/rgb24-calibration.png")
	_report["readback_calibration"] = {"tested_grey_levels": 256, "maximum_integer_code_error": calibration_error, "position_resolution_m": 8.0 / 16777215.0, "direction_component_resolution": 2.0 / 16777215.0, "position_comparison_quantization_bound_m": 0.000007, "direction_comparison_quantization_bound_degrees": 0.0001, "integer_rgb_transport": "each of the 256 byte levels measured exactly; integer packing and normalized GPU float conversion have finite quantization", "vertical_orientation": "Compatibility SubViewport get_image is bottom-up on this Windows backend; grid addresses explicitly invert image Y"}
	if calibration_error > 1:
		_failures.append("RGB24 读回的 256 档校准超过一个编码单位")
	var samples: Array[Dictionary] = [{"name": "independent_work_walk", "poses": [["work", 0.5], ["walk", 1.5]]}, {"name": "low_motion", "poses": [["pause", 0.5], ["low_motion", 0.5]], "equal_pose_allowed": true}, {"name": "recovery_and_symptom", "poses": [["recover", 1.5], ["symptom", 0.5]]}]
	for sample: Dictionary in samples:
		for row: int in 2:
			_set_pose(row, str(sample.poses[row][0]), float(sample.poses[row][1]))
		await process_frame
		if not _batch.publish(AABB(Vector3(-3, -0.1, -1), Vector3(6, 2.5, 2))):
			_failures.append("姿态发布失败: " + str(sample.name))
			continue
		_palette_material.set_shader_parameter("bone_rows", _batch.get_node("Instances").multimesh.mesh.surface_get_material(0).get_shader_parameter("bone_rows"))
		var values: Array = []
		for kind: int in 3:
			var reference: Array[Image] = []
			var candidate: Array[Image] = []
			for axis: int in 3:
				reference.append(await _capture(kind, axis, false))
				candidate.append(await _capture(kind, axis, true))
			values.append([reference, candidate])
		var measured: Dictionary = _compare(sample, values)
		_report.samples.append(measured)
		_raw_values.append(values)
		if float(measured.position_max_m) > 0.005 or float(measured.normal_max_degrees) > 1.0 or float(measured.anchor_max_m) > 0.05 or int(measured.missing_pixels) != 0:
			_failures.append("原生管线位置/法线/锚点或采集完整性失败: " + str(sample.name))
	_report["raw_original_pass"] = true
	for sample: Dictionary in _report.samples:
		_report.raw_original_pass = bool(_report.raw_original_pass) and bool(sample.pass)
	_install_neutral_reference()
	_report["neutral_reference_samples"] = []
	for sample_index: int in samples.size():
		var sample: Dictionary = samples[sample_index]
		for row: int in 2:
			_set_pose(row, str(sample.poses[row][0]), float(sample.poses[row][1]))
		await process_frame
		_batch.publish(AABB(Vector3(-3,-0.1,-1),Vector3(6,2.5,2)))
		_palette_material.set_shader_parameter("bone_rows", _batch.get_node("Instances").multimesh.mesh.surface_get_material(0).get_shader_parameter("bone_rows"))
		var values: Array = []
		for kind: int in 3:
			var reference: Array[Image] = []
			var candidate: Array[Image] = []
			for axis: int in 3:
				reference.append(await _capture(kind, axis, false))
				candidate.append(await _capture(kind, axis, true))
			values.append([reference,candidate])
		var measured: Dictionary = _compare(sample, values)
		var change: Dictionary = _compare_reference_neutral(_raw_values[sample_index],values)
		_last_neutral_values = values
		measured["raw_to_neutral_position_normal_change"] = change
		_report.neutral_reference_samples.append(measured)
		if not bool(measured.pass) or float(change.position_m) > 0.00001 or float(change.normal_degrees) > 0.01:
			_failures.append("中性引擎输入桥接未保持原身体/法线或逐顶点对照失败: " + str(sample.name))
	_report.neutral_reference_bridge["video_bytes_after_actual_render"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	_report.neutral_reference_bridge["process_static_bytes_after_actual_render"] = Performance.get_monitor(Performance.MEMORY_STATIC)
	_report["adapted_original_pass"] = true
	for sample: Dictionary in _report.neutral_reference_samples:
		_report.adapted_original_pass = bool(_report.adapted_original_pass) and bool(sample.pass)
	_report["palette_resources"] = _batch.resource_usage()
	_report["original_material"] = {"vertex_color_use_as_albedo": (_meshes[0].get_active_material(0) as StandardMaterial3D).vertex_color_use_as_albedo, "albedo_color": str((_meshes[0].get_active_material(0) as StandardMaterial3D).albedo_color), "cull_mode": (_meshes[0].get_active_material(0) as StandardMaterial3D).cull_mode, "transparency": (_meshes[0].get_active_material(0) as StandardMaterial3D).transparency, "candidate_instance_colour": "explicit white so per-instance colour does not zero the source vertex colours"}
	_report["raw_original_tangent_issue"] = {"pass": bool(_report.raw_original_pass), "source": "https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/storage/mesh_storage.cpp", "source_sha256": _hash("res://.cache/validation/skin-source/mesh_storage.cpp"), "line": 1552, "finding": "Skeleton-only transform-feedback input mask contains ARRAY_FORMAT_VERTEX twice and omits ARRAY_FORMAT_TANGENT. Its default tangent input decodes near (0.5547,0,-0.83205), producing the preserved raw tangent mismatch. Neutral identity reference enters the real blend+Skin path which binds tangent correctly; it does not fix or hide the raw failure."}
	_report["vertex_count_per_actor"] = _vertex_count
	_report["anchor_count_per_actor"] = ANCHORS.size()
	await _measure_identity_rows()
	await _measure_shadow()
	_measure_fallbacks()
	_report["process_static_bytes"] = Performance.get_monitor(Performance.MEMORY_STATIC)
	_report["video_bytes"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	_report["frames_rendered"] = Engine.get_frames_drawn()
	_finish()

func _make_scene() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(128, 32)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_debanding = false
	_viewport.scaling_3d_scale = 1.0
	_viewport.transparent_bg = true
	root.add_child(_viewport)
	_scene = Node3D.new()
	_viewport.add_child(_scene)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_scene.add_child(environment)
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0, 1, 5)
	_scene.add_child(camera)
	camera.current = true
	for row: int in 2:
		var model: Node3D = load(ASSET).instantiate()
		model.position = Vector3(-1.0 if row == 0 else 1.0, 0, 0)
		_scene.add_child(model)
		_meshes.append(model.find_children("*", "MeshInstance3D", true, false)[0])
		_skeletons.append(model.find_children("*", "Skeleton3D", true, false)[0])
		_players.append(model.find_children("*", "AnimationPlayer", true, false)[0])

func _make_readback_meshes() -> void:
	var source: ArrayMesh = SkinInput.rest_mesh(_meshes[0].mesh)
	var arrays: Array = source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_vertex_count = vertices.size()
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for anchor: String in ANCHORS:
		var bone: int = _skeletons[0].find_bone(anchor)
		var bind_index: int = -1
		for index: int in _meshes[0].skin.get_bind_count():
			if _meshes[0].skin.get_bind_name(index) == StringName(anchor):
				bind_index = index
		vertices.append(_skeletons[0].get_bone_global_rest(bone).origin)
		normals.append(Vector3.UP)
		tangents.append_array(PackedFloat32Array([1, 0, 0, 1]))
		bones.append_array(PackedInt32Array([bind_index, 0, 0, 0]))
		weights.append_array(PackedFloat32Array([1, 0, 0, 0]))
		colors.append(Color.WHITE)
		uv.append(Vector2.ZERO)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = null
	_point_count = vertices.size()
	_rows_per_actor = ceili(float(_point_count) / 128.0)
	_viewport.size = Vector2i(128, _rows_per_actor * 2)
	var temporary: ArrayMesh = ArrayMesh.new()
	temporary.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS,arrays)
	var generated: Dictionary = temporary.get("_surfaces")[0]
	var original: Dictionary = source.get("_surfaces")[0]
	var data: Dictionary = original.duplicate(true)
	var source_vertex_data: PackedByteArray = original.vertex_data
	var generated_vertex_data: PackedByteArray = generated.vertex_data
	var vertex_data: PackedByteArray = source_vertex_data.slice(0,_vertex_count*12)
	vertex_data.append_array(generated_vertex_data.slice(_vertex_count*12,_point_count*12))
	vertex_data.append_array(source_vertex_data.slice(_vertex_count*12))
	vertex_data.append_array(generated_vertex_data.slice(_point_count*12+_vertex_count*8))
	data.vertex_data = vertex_data
	for key: String in ["skin_data","attribute_data"]:
		var raw: PackedByteArray = original[key]
		var appended: PackedByteArray = generated[key]
		var stride: int = raw.size()/_vertex_count
		var joined: PackedByteArray = raw.duplicate()
		joined.append_array(appended.slice(_vertex_count*stride))
		data[key] = joined
	data.vertex_count = _point_count
	data.primitive = Mesh.PRIMITIVE_POINTS
	data.erase("index_data")
	data.erase("index_count")
	data.erase("lods")
	data.format = int(data.format) & ~Mesh.ARRAY_FORMAT_INDEX
	_raw_point_mesh = ArrayMesh.new()
	_raw_point_mesh.set("_surfaces",[data])
	_report["body_readback_source_preservation"] = {"vertex_positions_byte_exact": vertex_data.slice(0,_vertex_count*12)==source_vertex_data.slice(0,_vertex_count*12),"normal_tangent_bytes_exact": vertex_data.slice(_point_count*12,_point_count*12+_vertex_count*8)==source_vertex_data.slice(_vertex_count*12),"skin_bytes_exact": (data.skin_data as PackedByteArray).slice(0,(original.skin_data as PackedByteArray).size())==original.skin_data,"attribute_bytes_exact": (data.attribute_data as PackedByteArray).slice(0,(original.attribute_data as PackedByteArray).size())==original.attribute_data,"method": "same serialized production source payload; only point submission topology and seven appended diagnostic anchor vertices differ"}
	for field: String in ["vertex_positions_byte_exact","normal_tangent_bytes_exact","skin_bytes_exact","attribute_bytes_exact"]:
		if not bool(_report.body_readback_source_preservation[field]):
			_failures.append("原资产测量字节发生变化: "+field)
	_point_arrays = _raw_point_mesh.surface_get_arrays(0)
	for row: int in 2:
		var points: MeshInstance3D = MeshInstance3D.new()
		points.mesh = _raw_point_mesh
		points.skin = _meshes[row].skin
		points.skeleton = NodePath("..")
		points.custom_aabb = AABB(Vector3(-10,-10,-10), Vector3(20,20,20))
		_skeletons[row].add_child(points)
		var material: ShaderMaterial = _readback_material(false, row)
		points.material_override = material
		_original_points.append(points)
		_reference_materials.append(material)
	_palette_points = MultiMeshInstance3D.new()
	_palette_points.multimesh = MultiMesh.new()
	_palette_points.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_palette_points.multimesh.use_custom_data = true
	_palette_points.multimesh.mesh = _raw_point_mesh
	_palette_points.multimesh.instance_count = 2
	_palette_points.custom_aabb = AABB(Vector3(-10,-10,-10), Vector3(20,20,20))
	for row: int in 2:
		_palette_points.multimesh.set_instance_transform(row, Transform3D.IDENTITY)
		_palette_points.multimesh.set_instance_custom_data(row, Color(row,0,0,0))
	_palette_material = _readback_material(true, 0)
	_palette_material.set_shader_parameter("bone_rows", _batch.get_node("Instances").multimesh.mesh.surface_get_material(0).get_shader_parameter("bone_rows"))
	_palette_points.material_override = _palette_material
	_scene.add_child(_palette_points)

func _readback_material(palette: bool, row: int) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = READBACK if palette else READBACK_ORIGINAL
	if not palette:
		material.set_shader_parameter("reference_row", row)
	material.set_shader_parameter("rows_per_actor", _rows_per_actor)
	material.set_shader_parameter("image_size", Vector2(_viewport.size))
	return material

func _set_pose(row: int, animation: String, time: float) -> void:
	var player: AnimationPlayer = _players[row]
	player.play(animation)
	player.seek(time, true)
	player.pause()
	_skeletons[row].force_update_all_bone_transforms()

func _capture(kind: int, axis: int, palette: bool) -> Image:
	_batch.visible = false
	_palette_points.visible = palette
	for points: MeshInstance3D in _original_points:
		points.visible = not palette
	for material: ShaderMaterial in _reference_materials:
		material.set_shader_parameter("value_kind", kind)
		material.set_shader_parameter("component_axis", axis)
	_palette_material.set_shader_parameter("value_kind", kind)
	_palette_material.set_shader_parameter("component_axis", axis)
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	return _viewport.get_texture().get_image()

func _compare(sample: Dictionary, values: Array) -> Dictionary:
	var position_max: float = 0.0
	var normal_max: float = 0.0
	var tangent_max: float = 0.0
	var anchor_max: float = 0.0
	var different_positions: int = 0
	var missing_pixels: int = 0
	var semantic_anchor_error: float = 0.0
	var worst_tangent: Dictionary = {}
	for row: int in 2:
		for index: int in _point_count:
			for kind: int in 3:
				for axis: int in 3:
					if not _pixel_present(values[kind][0][axis], index, row) or not _pixel_present(values[kind][1][axis], index, row):
						missing_pixels += 1
				var original: Vector3 = _vector(values[kind][0], index, row, kind)
				var candidate: Vector3 = _vector(values[kind][1], index, row, kind)
				if kind == 0:
					if index >= _vertex_count:
						anchor_max = maxf(anchor_max, original.distance_to(candidate))
						var bone: int = _skeletons[row].find_bone(ANCHORS[index-_vertex_count])
						var expected: Vector3 = _skeletons[row].get_bone_global_pose(bone).origin
						semantic_anchor_error = maxf(semantic_anchor_error,original.distance_to(expected))
					else:
						position_max = maxf(position_max, original.distance_to(candidate))
				else:
					var degrees: float = rad_to_deg(original.normalized().angle_to(candidate.normalized()))
					if kind == 1:
						normal_max = maxf(normal_max, degrees)
					else:
						if degrees > tangent_max:
							worst_tangent = {"row": row, "vertex": index, "reference": [original.x, original.y, original.z], "candidate": [candidate.x, candidate.y, candidate.z]}
						tangent_max = maxf(tangent_max, degrees)
	for index: int in _vertex_count:
		if _vector(values[0][1], index, 0, 0).distance_to(_vector(values[0][1], index, 1, 0)) > 0.005:
			different_positions += 1
	var example: Vector3 = _vector(values[0][0], 0, 0, 0)
	return {"name": sample.name, "poses": sample.poses, "compared_vertices": _vertex_count * 2, "compared_anchors": ANCHORS.size() * 2, "position_max_m": position_max, "normal_max_degrees": normal_max, "tangent_max_degrees": tangent_max, "anchor_max_m": anchor_max, "semantic_anchor_max_m": semantic_anchor_error, "missing_pixels": missing_pixels, "different_pose_vertex_count": different_positions, "worst_tangent": worst_tangent, "first_original_vertex": [example.x, example.y, example.z], "pass": position_max <= 0.005 and normal_max <= 1.0 and tangent_max <= 1.0 and anchor_max <= 0.05 and semantic_anchor_error <= 0.05 and (different_positions > 0 or bool(sample.get("equal_pose_allowed",false))) and missing_pixels == 0}

func _pixel_present(image: Image, index: int, row: int) -> bool:
	return image.get_pixel(index%128,image.get_height()-1-(index/128+row*_rows_per_actor)).a > 0.99

func _install_neutral_reference() -> void:
	var video_before: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	var mesh: ArrayMesh = SkinInput.prepare_mesh(_raw_point_mesh)
	var activated: bool = true
	for row: int in _original_points.size():
		var previous: MeshInstance3D = _original_points[row]
		var points: MeshInstance3D = SkinInput.new()
		points.mesh = mesh
		points.skin = previous.skin
		points.skeleton = previous.skeleton
		points.custom_aabb = previous.custom_aabb
		points.material_override = previous.material_override
		var parent: Node = previous.get_parent()
		parent.remove_child(previous)
		previous.free()
		parent.add_child(points)
		_original_points[row] = points
		activated = activated and SkinInput.input_active(points)
	_report["neutral_reference_bridge"] = {"scope": "production original Skin/Skeleton pipeline adapter, installed by the asset import hook and activated on actual loaded MeshInstance3D; the production batch strips only this verified zero-delta input using the exact retained static source", "vertex_delta_max": 0.0, "normal_delta_max": 0.0, "tangent_delta_max": 0.0, "blend_shape_weight": 1.0, "relative": false, "shared_identity_payload_bytes": (mesh.get("_surfaces")[0].blend_shapes as PackedByteArray).size(), "video_bytes_after_install": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED), "facts": "the full original packed vertex payload is reused byte-for-byte as the sole normalized identity input; every actual delta is zero. Weight one avoids Godot's zero-weight elimination and forces its real blend+Skin GPU pass to bind tangent. Same actual production factory, original Skin and original Skeleton; reference shader contains no skin deformation formula."}
	_report.neutral_reference_bridge["original_source_shader"] = "res://game/view/shaders/skin_readback_original.gdshader"
	_report.neutral_reference_bridge["production_runtime_ready_activation_pass"] = activated
	_report.neutral_reference_bridge["identity_bytes_equal_production_source"] = SkinInput.is_identity_input(mesh)
	if not activated:
		_failures.append("生产运行时原 Skin 输入没有实际激活")
	_report.neutral_reference_bridge["video_bytes_before_install"] = video_before
	_report.neutral_reference_bridge["measured_original_source_shader_sha256"] = _hash("res://game/view/shaders/skin_readback_original.gdshader")
	_report.neutral_reference_bridge["extra_upload_input_bytes"] = _point_count*20
	_report.neutral_reference_bridge["per_instance_blend_intermediate_buffer_bytes"] = _point_count*28*2
	_report.neutral_reference_bridge["original_instances"] = 2
	_report.neutral_reference_bridge["pixel_readback_cpu_bytes_per_image"] = _viewport.size.x*_viewport.size.y*4

func _compare_reference_neutral(raw: Array, neutral: Array) -> Dictionary:
	var position: float = 0.0
	var normal: float = 0.0
	for row: int in 2:
		for index: int in _point_count:
			position = maxf(position,_vector(raw[0][0],index,row,0).distance_to(_vector(neutral[0][0],index,row,0)))
			normal = maxf(normal,rad_to_deg(_vector(raw[1][0],index,row,1).normalized().angle_to(_vector(neutral[1][0],index,row,1).normalized())))
	return {"position_m": position,"normal_degrees": normal}

func _vector(images: Array, index: int, row: int, kind: int) -> Vector3:
	var value: Vector3 = Vector3(float(_code(images[0], index, row)), float(_code(images[1], index, row)), float(_code(images[2], index, row))) / 16777215.0
	return value * 8.0 - Vector3.ONE * 4.0 if kind == 0 else value * 2.0 - Vector3.ONE

func _code(image: Image, index: int, row: int) -> int:
	var pixel: Color = image.get_pixel(index % 128, image.get_height() - 1 - (index / 128 + row * _rows_per_actor))
	return roundi(pixel.r * 255.0) * 65536 + roundi(pixel.g * 255.0) * 256 + roundi(pixel.b * 255.0)

func _measure_identity_rows() -> void:
	for points: MeshInstance3D in _original_points:
		points.visible = false
	_palette_points.multimesh.instance_count = 64
	_viewport.size = Vector2i(128, _rows_per_actor * 64)
	_palette_material.set_shader_parameter("image_size", Vector2(_viewport.size))
	var current: Texture2D = _palette_material.get_shader_parameter("bone_rows")
	var original_page: Image = current.get_image()
	var page: Image = Image.create_empty(original_page.get_width(),64,false,Image.FORMAT_RGBAF)
	for row: int in 64:
		for column: int in original_page.get_width():
			page.set_pixel(column,row,original_page.get_pixel(column,row%2))
	var texture: ImageTexture = ImageTexture.create_from_image(page)
	_palette_material.set_shader_parameter("bone_rows",texture)
	for row: int in 64:
		_palette_points.multimesh.set_instance_transform(row, Transform3D.IDENTITY)
		_palette_points.multimesh.set_instance_custom_data(row, Color(row,0,0,0))
	var custom: Image = await _capture(3, 0, true)
	var identity: Image = await _capture(5, 0, true)
	var errors: Array[int] = []
	for row: int in 64:
		if roundi(float(_code(custom, 0, row)) / 16777215.0 * 63.0) != row or roundi(float(_code(identity, 0, row)) / 16777215.0 * 63.0) != row:
			errors.append(row)
	_report["local_row_identity"] = {"rows": 64, "custom_channel": "INSTANCE_CUSTOM.x", "instance_channel": "INSTANCE_ID", "failed_rows": errors, "pass": errors.is_empty()}
	var position_images: Array[Image] = []
	for axis: int in 3:
		position_images.append(await _capture(0,axis,true))
	var row_position_error: float = 0.0
	var missing: int = 0
	for row: int in 64:
		for index: int in _point_count:
			var original: Vector3 = _vector(_last_neutral_values[0][0],index,row%2,0)
			var candidate: Vector3 = _vector(position_images,index,row,0)
			row_position_error = maxf(row_position_error,original.distance_to(candidate))
			for image: Image in position_images:
				if not _pixel_present(image,index,row):
					missing += 1
	_report.local_row_identity["rgba_float_64_row_position_max_m"] = row_position_error
	_report.local_row_identity["rgba_float_page_bytes"] = page.get_data().size()
	_report.local_row_identity["missing_position_pixels"] = missing
	_report.local_row_identity["pass"] = errors.is_empty() and row_position_error <= 0.005 and missing == 0
	custom.save_png(OUTPUT + "/custom-row-roundtrip.png")
	identity.save_png(OUTPUT + "/instance-id-roundtrip.png")
	if not bool(_report.local_row_identity.pass):
		_failures.append("局部行号或 INSTANCE_ID 未实际往返")
	_palette_points.visible = false

func _measure_shadow() -> void:
	for points: MeshInstance3D in _original_points:
		points.queue_free()
	_palette_points.queue_free()
	_viewport.size = Vector2i(512, 512)
	_viewport.transparent_bg = false
	_viewport.positional_shadow_atlas_size = 2048
	RenderingServer.directional_shadow_atlas_set_size(2048, false)
	var camera: Camera3D = _scene.find_children("*", "Camera3D", true, false)[0]
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.0
	camera.look_at_from_position(Vector3(0,6,4), Vector3(0,0,0))
	var environment: WorldEnvironment = _scene.find_children("*", "WorldEnvironment", true, false)[0]
	environment.environment.background_color = Color(0.6,0.6,0.6)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.15
	var ground: MeshInstance3D = MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(10,10)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ground_material: StandardMaterial3D = StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.7,0.7,0.7)
	ground.material_override = ground_material
	_scene.add_child(ground)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48,-32,0)
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 20
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	light.shadow_bias = 0.01
	camera.far = 30.0
	_scene.add_child(light)
	for row: int in 2:
		_set_pose(row, "work" if row == 0 else "walk", 0.5 if row == 0 else 1.5)
		_meshes[row].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_meshes[row].get_parent().get_parent().get_parent().rotation.y = PI*0.5 if row==0 else PI*1.5
	_batch.visible = true
	_batch.publish(AABB(Vector3(-3,-0.1,-1),Vector3(6,2.5,2)))
	_batch.get_node("Instances").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var candidate: Image = _viewport.get_texture().get_image()
	var candidate_calls: int = _viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	_batch.visible = false
	for mesh: MeshInstance3D in _meshes:
		mesh.visible = true
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var reference: Image = _viewport.get_texture().get_image()
	var original_calls: int = _viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	for mesh: MeshInstance3D in _meshes:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var control: Image = _viewport.get_texture().get_image()
	var shadows: int = 0
	var mismatched: int = 0
	var maximum: float = 0.0
	for y: int in 512:
		for x: int in 512:
			var original: Color = reference.get_pixel(x,y)
			var batched: Color = candidate.get_pixel(x,y)
			var unshadowed: Color = control.get_pixel(x,y)
			var difference: float = maxf(absf(original.r-batched.r), maxf(absf(original.g-batched.g), absf(original.b-batched.b)))
			maximum = maxf(maximum, difference)
			if difference > 2.0/255.0:
				mismatched += 1
			if unshadowed.r - original.r > 0.03:
				shadows += 1
	var passed: bool = shadows > 50 and mismatched == 0
	_report["main_shadow"] = {"camera_size": [512,512], "actors": 2, "distinct_current_poses": true, "root_yaw_degrees": [90,270], "reference_shadow_pixels": shadows, "pixels_different_by_more_than_2_bytes": mismatched, "maximum_colour_difference": maximum, "original_viewport_calls": original_calls, "candidate_viewport_calls": candidate_calls, "pass": passed, "method": "original visible bodies + real directional shadows vs production visible MultiMesh + shadows; control keeps the same original visible bodies and disables shadow casting"}
	reference.save_png(OUTPUT + "/shadow-reference.png")
	candidate.save_png(OUTPUT + "/shadow-palette.png")
	control.save_png(OUTPUT + "/shadow-control.png")
	if not passed:
		_failures.append("主阴影对照未通过")

func _measure_fallbacks() -> void:
	var skeleton: Skeleton3D = _skeletons[0]
	var hips: int = skeleton.find_bone("hips")
	var scale: Vector3 = skeleton.get_bone_pose_scale(hips)
	skeleton.set_bone_pose_scale(hips,Vector3(1,1.1,1))
	skeleton.force_update_all_bone_transforms()
	var rejected: bool = not _batch.publish(AABB(Vector3(-3,-0.1,-1),Vector3(6,2.5,2)))
	var restored: bool = _meshes[0].visible and _meshes[1].visible and not _batch.get_node("Instances").visible
	skeleton.set_bone_pose_scale(hips,scale)
	skeleton.force_update_all_bone_transforms()
	_batch.clear_sources()
	var original_material: Material = _meshes[0].material_override
	var alpha: StandardMaterial3D = _meshes[0].get_active_material(0).duplicate()
	alpha.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_meshes[0].material_override = alpha
	var alpha_reason: String = _batch.bind_sources(_meshes,_skeletons)
	_meshes[0].material_override = original_material
	var morph_mesh: ArrayMesh = ArrayMesh.new()
	morph_mesh.add_blend_shape("actual_morph")
	var mesh_arrays: Array = _meshes[0].mesh.surface_get_arrays(0)
	var shapes: Array = []
	shapes.resize(Mesh.ARRAY_MAX)
	for slot: int in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT]:
		shapes[slot] = mesh_arrays[slot]
	morph_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,mesh_arrays,[shapes])
	var original_mesh: Mesh = _meshes[0].mesh
	_meshes[0].mesh = morph_mesh
	var morph_reason: String = _batch.bind_sources(_meshes,_skeletons)
	_meshes[0].mesh = original_mesh
	_report["fallbacks"] = {"nonuniform_bone_scale_rejected": rejected,"original_visibility_restored": restored,"alpha_blend_reason": alpha_reason,"actual_morph_reason": morph_reason,"pass": rejected and restored and not alpha_reason.is_empty() and not morph_reason.is_empty()}
	if not bool(_report.fallbacks.pass):
		_failures.append("不支持的资产未回退原管线")
	var reason: String = _batch.bind_sources(_meshes,_skeletons)
	if not reason.is_empty():
		_failures.append(reason)
		return
	var before: String = _pose_fingerprint()
	_batch.publish(AABB(Vector3(-3,-0.1,-1),Vector3(6,2.5,2)))
	_batch.publish(AABB(Vector3(-3,-0.1,-1),Vector3(6,2.5,2)))
	var after: String = _pose_fingerprint()
	_report["original_pose_read_only"] = {"before_sha256": before, "after_sha256": after, "pass": before == after, "source": "original Skeleton bone pose positions/rotations/scales; batch publish never calls AnimationPlayer or changes those fields"}
	if before != after:
		_failures.append("绘制发布修改了原姿态事实")
	_batch.clear_sources()
	_report["original_pipeline_after_batch_release"] = {"meshes_visible": _meshes[0].visible and _meshes[1].visible,"input_still_active": SkinInput.input_active(_meshes[0]) and SkinInput.input_active(_meshes[1]),"pass": _meshes[0].visible and _meshes[1].visible and SkinInput.input_active(_meshes[0]) and SkinInput.input_active(_meshes[1])}
	if not bool(_report.original_pipeline_after_batch_release.pass):
		_failures.append("批量释放没有恢复真实适配原管线")

func _pose_fingerprint() -> String:
	var facts: Array = []
	for skeleton: Skeleton3D in _skeletons:
		for bone: int in skeleton.get_bone_count():
			facts.append([skeleton.get_bone_pose_position(bone),skeleton.get_bone_pose_rotation(bone),skeleton.get_bone_pose_scale(bone)])
	var bytes: PackedByteArray = var_to_bytes(facts)
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

func _hash(path: String) -> String:
	return FileAccess.get_sha256(path)

func _finish() -> void:
	_report["failures"] = _failures
	_report["measurement_suite_pass"] = _failures.is_empty()
	_report["pass"] = _failures.is_empty()
	_report["qualification"] = "The actual production original pipeline now uses the exact-byte zero-delta Compatibility Skin input adapter, and the production batch is measured against that actual GPU Skin pipeline. The unadapted native tangent failure remains preserved separately. Genuine morph assets, transparent parts and nonuniform transforms still use the full original pipeline. This is not an all-rig or performance qualification."
	var file: FileAccess = FileAccess.open(OUTPUT + "/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	print("STAGE01_RENDER_RESULT=", ProjectSettings.globalize_path(OUTPUT + "/result.json"))
	print("STAGE01_RENDER_PASS=", _failures.is_empty())
	for failure: String in _failures:
		printerr(failure)
	quit(0 if _failures.is_empty() else 1)
