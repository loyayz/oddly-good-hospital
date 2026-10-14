class_name CompatibilitySkinInput
extends MeshInstance3D

const ENGINE_HASH: String = "ed1daf0bf001b61586d9930840f2f1394092c079"
const INPUT_NAME: StringName = &"__compatibility_identity_skin_input"
const SOURCE_KEY: StringName = &"compatibility_skin_rest_source_v1"

func _ready() -> void:
	if not is_identity_input(mesh):
		return
	if current_backend_supported():
		set_blend_shape_value(0,1.0)
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
	var adapted: ArrayMesh = ArrayMesh.new()
	adapted.resource_name = source.resource_name + "_compatibility_skin_input"
	adapted.add_blend_shape(INPUT_NAME)
	adapted.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	var adapted_surfaces: Array = surfaces.duplicate(true)
	for surface: Dictionary in adapted_surfaces:
		# The engine's serialization payload is copied exactly, including packed
		# normals/tangents, LOD indices, material layout and bone bounds.
		# The normalized input is that same immutable vertex payload: delta zero.
		surface["blend_shapes"] = surface.vertex_data
	adapted.set("_surfaces",adapted_surfaces)
	adapted.custom_aabb = source.custom_aabb
	adapted.shadow_mesh = source.shadow_mesh
	adapted.set_meta(SOURCE_KEY,source)
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
	var raw_surfaces: Array = original.get("_surfaces")
	var current_surfaces: Array = adapted.get("_surfaces")
	if raw_surfaces.size() != current_surfaces.size():
		return false
	for index: int in raw_surfaces.size():
		var raw: Dictionary = raw_surfaces[index]
		var current: Dictionary = current_surfaces[index]
		for key: Variant in raw:
			if raw[key] != current.get(key):
				return false
		if current.get("blend_shapes") != raw.vertex_data:
			return false
	return true

static func input_active(instance: MeshInstance3D) -> bool:
	return current_backend_supported() and is_identity_input(instance.mesh) and instance.get_blend_shape_value(0) == 1.0

static func resource_usage(source: Mesh) -> Dictionary:
	if not is_identity_input(source):
		return {"active_identity_resource": false}
	var original: Mesh = rest_mesh(source)
	var bytes: int = 0
	var base_bytes: int = 0
	var vertices: int = 0
	var surfaces: Array = (original as ArrayMesh).get("_surfaces")
	for surface: Dictionary in surfaces:
		bytes += (surface.vertex_data as PackedByteArray).size()
		vertices += int(surface.vertex_count)
		for key: String in ["vertex_data","attribute_data","skin_data","index_data"]:
			base_bytes += (surface.get(key,PackedByteArray()) as PackedByteArray).size()
		var lods: Array = surface.get("lods",[])
		for index: int in range(1,lods.size(),2):
			base_bytes += (lods[index] as PackedByteArray).size()
	return {"active_identity_resource": true,"surface_count": surfaces.size(),"vertices": vertices,"shared_additional_input_payload_bytes": bytes,"shared_duplicate_base_gpu_payload_bytes": base_bytes,"raw_base_payload_retained_bytes": base_bytes,"per_original_instance_additional_blend_intermediate_bytes": vertices*28*2,"raw_source_retained": true,"body_payload_unchanged": true,"gpu_buffers": "original and adapted base resources are distinct GPU meshes; same-source payload is retained and must not be counted as freed", "driver_temporaries": "not exposed by Godot; observe process/video allocation separately"}
