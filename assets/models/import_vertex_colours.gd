@tool
extends EditorScenePostImport

const SkinInput = preload("res://game/view/compatibility_skin_input.gd")

var _skin_meshes: Dictionary = {}

func _post_import(scene: Node) -> Object:
	_apply(scene)
	return scene

func _apply(node: Node) -> void:
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node
		for surface: int in instance.mesh.get_surface_count():
			var material: Material = instance.get_active_material(surface)
			if material is StandardMaterial3D:
				var colours: Variant = instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
				if colours is PackedColorArray and not colours.is_empty():
					(material as StandardMaterial3D).vertex_color_use_as_albedo = true
		if instance.skin != null and instance.mesh is ArrayMesh and instance.get_script() == null:
			var original: ArrayMesh = instance.mesh
			if not _skin_meshes.has(original):
				_skin_meshes[original] = SkinInput.prepare_mesh(original)
			var adapted: ArrayMesh = _skin_meshes[original]
			if adapted != original:
				instance.mesh = adapted
				instance.set_script(SkinInput)
				instance.set_blend_shape_value(0,1.0)
	for child: Node in node.get_children():
		_apply(child)
