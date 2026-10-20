class_name SkinnedPoseBatch
extends Node3D

const MAX_ROWS: int = 64
const MAX_BONES: int = 40
const POSE_SHADER: Shader = preload("res://game/view/shaders/skinned_pose.gdshader")
const DOUBLE_SIDED_SHADER: Shader = preload("res://game/view/shaders/skinned_pose_double_sided.gdshader")
const SkinInput = preload("res://game/view/compatibility_skin_input.gd")

var _sources: Array[MeshInstance3D] = []
var _skeletons: Array[Skeleton3D] = []
var _bind_bones: Array[PackedInt32Array] = []
var _source_visibility: Array[bool] = []
var _source_skins: Array[Skin] = []
var _source_mesh: Mesh
var _source_material: Material
var _instances: MultiMeshInstance3D
var _material: ShaderMaterial
var _images: Array[Image] = []
var _textures: Array[ImageTexture] = []
var _current_page: int = 0
var _page_width: int = 0
var _page_height: int = 0
var _bone_count: int = 0
var _uploaded_bytes: int = 0
var _publish_count: int = 0

func bind_sources(meshes: Array[MeshInstance3D], skeletons: Array[Skeleton3D]) -> String:
	clear_sources()
	if meshes.is_empty() or meshes.size() > MAX_ROWS or meshes.size() != skeletons.size():
		return "独立骨矩阵页需要一至六十四个对应的原网格与骨架"
	var first: MeshInstance3D = meshes[0]
	if first.mesh == null or first.skin == null or first.mesh.get_surface_count() != 1:
		return "该适配只覆盖带 Skin 的单 Surface 网格"
	var bone_count: int = first.skin.get_bind_count()
	if bone_count < 1 or bone_count > MAX_BONES or (first.mesh.get_blend_shape_count() > 0 and not SkinInput.input_active(first)):
		return "骨骼容量或形态变形需要原管线"
	var original_material: Material = first.get_active_material(0)
	if not original_material is StandardMaterial3D:
		return "未知材质保持原管线"
	var standard: StandardMaterial3D = original_material
	if standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or standard.cull_mode not in [BaseMaterial3D.CULL_BACK, BaseMaterial3D.CULL_DISABLED]:
		return "透明或特殊剔除材质保持原管线"
	for texture_slot: int in BaseMaterial3D.TEXTURE_MAX:
		if standard.get_texture(texture_slot) != null:
			return "带纹理材料尚未纳入该适配"
	var arrays: Array = SkinInput.rest_mesh(first.mesh).surface_get_arrays(0)
	if arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
		return "网格缺少原骨索引或权重"
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if indices.size() != vertices.size() * 4 or weights.size() != vertices.size() * 4:
		return "超过四权重的资产保持原管线"
	for index: int in indices:
		if index < 0 or index >= bone_count:
			return "骨索引不在实际 Skin 范围"
	var mappings: Array[PackedInt32Array] = []
	var skins: Array[Skin] = []
	for row: int in meshes.size():
		var source: MeshInstance3D = meshes[row]
		var skeleton: Skeleton3D = skeletons[row]
		if source.mesh != first.mesh or source.get_active_material(0) != original_material or source.skin == null:
			return "该页只能使用相同原网格与完整材质布局"
		if source.mesh.get_blend_shape_count() > 0 and not SkinInput.input_active(source):
			return "专用中性输入未激活或实际形态变形需要原管线"
		if source.skin.get_bind_count() != bone_count or skeleton == null:
			return "Skin 或骨架不相容"
		var mapping: PackedInt32Array = PackedInt32Array()
		for bind_index: int in bone_count:
			if source.skin.get_bind_name(bind_index) != first.skin.get_bind_name(bind_index) or not source.skin.get_bind_pose(bind_index).is_equal_approx(first.skin.get_bind_pose(bind_index)):
				return "Skin 绑定空间不相容"
			var bone_name: StringName = source.skin.get_bind_name(bind_index)
			var bone_index: int = skeleton.find_bone(bone_name) if not bone_name.is_empty() else source.skin.get_bind_bone(bind_index)
			if bone_index < 0 or bone_index >= skeleton.get_bone_count():
				return "Skin 引用的骨骼不存在"
			mapping.append(bone_index)
		mappings.append(mapping)
		skins.append(source.skin)
	_bone_count = bone_count
	_bind_bones = mappings
	_source_skins = skins
	_source_mesh = first.mesh
	_source_material = original_material
	_sources = meshes.duplicate()
	_skeletons = skeletons.duplicate()
	for source: MeshInstance3D in _sources:
		_source_visibility.append(source.visible)
	_page_width = nearest_po2(_bone_count * 3)
	_page_height = nearest_po2(_sources.size())
	for page: int in 2:
		var image: Image = Image.create_empty(_page_width, _page_height, false, Image.FORMAT_RGBAF)
		_images.append(image)
		_textures.append(ImageTexture.create_from_image(image))
	_uploaded_bytes = _page_width * _page_height * 16 * 2
	_material = ShaderMaterial.new()
	_material.shader = POSE_SHADER if standard.cull_mode == BaseMaterial3D.CULL_BACK else DOUBLE_SIDED_SHADER
	_material.set_shader_parameter("albedo_color", standard.albedo_color)
	_material.set_shader_parameter("use_vertex_color", standard.vertex_color_use_as_albedo)
	_material.set_shader_parameter("material_roughness", standard.roughness)
	_material.set_shader_parameter("material_metallic", standard.metallic)
	_material.set_shader_parameter("material_specular", standard.metallic_specular)
	var prepared: ArrayMesh = ArrayMesh.new()
	prepared.add_surface_from_arrays(first.mesh.surface_get_primitive_type(0), arrays)
	prepared.surface_set_material(0, _material)
	_instances = MultiMeshInstance3D.new()
	_instances.name = "Instances"
	_instances.visible = false
	_instances.cast_shadow = first.cast_shadow
	_instances.multimesh = MultiMesh.new()
	_instances.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_instances.multimesh.use_colors = true
	_instances.multimesh.use_custom_data = true
	_instances.multimesh.mesh = prepared
	_instances.multimesh.instance_count = _sources.size()
	add_child(_instances)
	return ""

func publish(visible_bounds: AABB) -> bool:
	if _instances == null:
		return false
	if visible_bounds.size.x <= 0.0 or visible_bounds.size.y <= 0.0 or visible_bounds.size.z <= 0.0:
		_suspend()
		return false
	var next_page: int = 1 - _current_page
	var image: Image = _images[next_page]
	image.fill(Color(0, 0, 0, 0))
	for row: int in _sources.size():
		if not is_instance_valid(_sources[row]) or not is_instance_valid(_skeletons[row]):
			_suspend()
			return false
		var source: MeshInstance3D = _sources[row]
		var skeleton: Skeleton3D = _skeletons[row]
		if source.mesh != _source_mesh or source.skin != _source_skins[row] or source.get_active_material(0) != _source_material or not source.get_parent().is_visible_in_tree() or not _rigid(source.global_transform.basis):
			_suspend()
			return false
		if source.mesh.get_blend_shape_count() > 0 and source.get_blend_shape_value(0) != 1.0:
			_suspend()
			return false
		var skeleton_to_model: Transform3D = source.global_transform.affine_inverse() * skeleton.global_transform
		for bind_index: int in _bone_count:
			var pose: Transform3D = skeleton_to_model * skeleton.get_bone_global_pose(_bind_bones[row][bind_index]) * source.skin.get_bind_pose(bind_index)
			if not _rigid(pose.basis):
				_suspend()
				return false
			var basis: Basis = pose.basis
			image.set_pixel(bind_index * 3, row, Color(basis.x.x, basis.y.x, basis.z.x, pose.origin.x))
			image.set_pixel(bind_index * 3 + 1, row, Color(basis.x.y, basis.y.y, basis.z.y, pose.origin.y))
			image.set_pixel(bind_index * 3 + 2, row, Color(basis.x.z, basis.y.z, basis.z.z, pose.origin.z))
	_textures[next_page].update(image)
	for row: int in _sources.size():
		_instances.multimesh.set_instance_transform(row, global_transform.affine_inverse() * _sources[row].global_transform)
		_instances.multimesh.set_instance_color(row, Color.WHITE)
		_instances.multimesh.set_instance_custom_data(row, Color(float(row), 0, 0, 0))
	_instances.custom_aabb = visible_bounds
	_material.set_shader_parameter("bone_rows", _textures[next_page])
	_current_page = next_page
	_instances.visible = true
	for source: MeshInstance3D in _sources:
		source.visible = false
	_uploaded_bytes += _page_width * _page_height * 16
	_publish_count += 1
	return true

func clear_sources() -> void:
	_suspend()
	if is_instance_valid(_instances):
		remove_child(_instances)
		_instances.free()
	_instances = null
	_sources.clear()
	_skeletons.clear()
	_bind_bones.clear()
	_source_visibility.clear()
	_source_skins.clear()
	_source_mesh = null
	_source_material = null
	_images.clear()
	_textures.clear()
	_material = null
	_current_page = 0
	_page_width = 0
	_page_height = 0
	_bone_count = 0
	_uploaded_bytes = 0
	_publish_count = 0

func resource_usage() -> Dictionary:
	var bytes: int = _page_width * _page_height * 16
	return {"members": _sources.size(), "bones": _bone_count, "page_width": _page_width, "page_height": _page_height, "format": "RGBAF", "gpu_current_and_staging_bytes": bytes * 2, "cpu_current_and_staging_bytes": bytes * 2, "full_page_uploaded_bytes_including_initialization": _uploaded_bytes, "publish_count": _publish_count, "prepared_surfaces": 1 if _instances != null else 0, "driver_upload_temporaries": "not exposed by Godot; process/video peaks remain separate evidence"}

func _exit_tree() -> void:
	_suspend()

func _suspend() -> void:
	if is_instance_valid(_instances):
		_instances.visible = false
	for index: int in _sources.size():
		if is_instance_valid(_sources[index]):
			_sources[index].visible = _source_visibility[index]

static func _rigid(basis: Basis) -> bool:
	return absf(basis.x.length_squared() - 1.0) < 0.001 and absf(basis.y.length_squared() - 1.0) < 0.001 and absf(basis.z.length_squared() - 1.0) < 0.001 and absf(basis.x.dot(basis.y)) < 0.001 and absf(basis.x.dot(basis.z)) < 0.001 and absf(basis.y.dot(basis.z)) < 0.001
