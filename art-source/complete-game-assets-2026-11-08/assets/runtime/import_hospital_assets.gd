@tool
extends EditorScenePostImport

const SkinInput = preload("res://assets/runtime/compatibility_skin_input.gd")
var _skin_meshes: Dictionary = {}

func _post_import(scene: Node) -> Object:
	_apply(scene)
	return scene

func _apply(node: Node) -> void:
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node as MeshInstance3D
		for surface: int in instance.mesh.get_surface_count():
			var material: Material = instance.get_active_material(surface)
			if material is StandardMaterial3D:
				var colors: Variant = instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
				if colors is PackedColorArray and not colors.is_empty():
					var transparent: bool = (material as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
					var shared: StandardMaterial3D = load("res://assets/materials/vertex_alpha.tres" if transparent else "res://assets/materials/vertex_opaque.tres") as StandardMaterial3D
					(instance.mesh as ArrayMesh).surface_set_material(surface, shared)
		if instance.skin != null and instance.mesh is ArrayMesh and instance.get_script() == null:
			var original: ArrayMesh = instance.mesh as ArrayMesh
			if not _skin_meshes.has(original):
				_skin_meshes[original] = SkinInput.prepare_mesh(original)
			var adapted: ArrayMesh = _skin_meshes[original]
			if adapted != original:
				instance.mesh = adapted
				instance.set_script(SkinInput)
				instance.set_blend_shape_value(0, 1.0)
	for child: Node in node.get_children():
		_apply(child)
