extends MeshInstance3D

# Reused from game/view/compatibility_skin_input.gd, without a global class name.
const ENGINE_HASH: String = "ed1daf0bf001b61586d9930840f2f1394092c079"
const INPUT_NAME: StringName = &"__compatibility_identity_skin_input"
const SOURCE_KEY: StringName = &"compatibility_skin_rest_source_v1"

func _ready() -> void:
	if not is_identity_input(mesh):
		return
	if current_backend_supported():
		set_blend_shape_value(0, 1.0)
	else:
		mesh = rest_mesh(mesh)

static func current_backend_supported() -> bool:
	return str(Engine.get_version_info().hash) == ENGINE_HASH and RenderingServer.get_current_rendering_method() == "gl_compatibility" and RenderingServer.get_current_rendering_driver_name() == "opengl3"

static func prepare_mesh(source: ArrayMesh) -> ArrayMesh:
	if str(Engine.get_version_info().hash) != ENGINE_HASH or source.get_blend_shape_count() != 0:
		return source
	var surfaces: Array = source.get("_surfaces")
	if surfaces.is_empty():
		return source
	for surface: Dictionary in surfaces:
		if not surface.has("skin_data") or not surface.has("vertex_data") or (int(surface.format) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0:
			return source
	var adapted := ArrayMesh.new()
	adapted.resource_name = source.resource_name + "_compatibility_skin_input"
	adapted.add_blend_shape(INPUT_NAME)
	adapted.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	var copied: Array = surfaces.duplicate(true)
	for surface: Dictionary in copied:
		surface["blend_shapes"] = surface.vertex_data
	adapted.set("_surfaces", copied)
	adapted.custom_aabb = source.custom_aabb
	adapted.shadow_mesh = source.shadow_mesh
	adapted.set_meta(SOURCE_KEY, source)
	return adapted

static func rest_mesh(source: Mesh) -> Mesh:
	return source.get_meta(SOURCE_KEY) as Mesh if source.has_meta(SOURCE_KEY) else source

static func is_identity_input(source: Mesh) -> bool:
	if not source is ArrayMesh or not source.has_meta(SOURCE_KEY) or source.get_blend_shape_count() != 1 or source.get_blend_shape_name(0) != INPUT_NAME:
		return false
	var adapted: ArrayMesh = source
	var original: ArrayMesh = adapted.get_meta(SOURCE_KEY) as ArrayMesh
	if original == null or original.get_blend_shape_count() != 0 or adapted.blend_shape_mode != Mesh.BLEND_SHAPE_MODE_NORMALIZED:
		return false
	var raw: Array = original.get("_surfaces")
	var current: Array = adapted.get("_surfaces")
	if raw.size() != current.size():
		return false
	for index: int in raw.size():
		for key: Variant in raw[index]:
			if raw[index][key] != current[index].get(key):
				return false
		if current[index].get("blend_shapes") != raw[index].vertex_data:
			return false
	return true

static func input_active(instance: MeshInstance3D) -> bool:
	return current_backend_supported() and is_identity_input(instance.mesh) and instance.get_blend_shape_value(0) == 1.0
