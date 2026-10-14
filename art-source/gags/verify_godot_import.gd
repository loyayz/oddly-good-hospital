extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	for name: String in ["case_d37_tissue", "device_m37_filter", "case_d23_dream"]:
		var path: String = "res://assets/gags/" + name + ".glb"
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			failures.append("Imported PackedScene unavailable: " + path)
			continue
		var scene: Node = packed.instantiate()
		var measured: Dictionary = {"surfaces": 0, "colour_vertices": 0, "non_white_colour_vertices": 0, "palette": [], "vertex_colour_enabled": 0, "skin_meshes": 0, "mesh_scripts": 0, "animations": []}
		inspect(scene, measured)
		if measured.surfaces != measured.vertex_colour_enabled:
			failures.append(name + ": not every actual colour stream is enabled as albedo")
		if measured.non_white_colour_vertices == 0:
			failures.append(name + ": actual imported colours contain no authored palette")
		if measured.skin_meshes != 0 or measured.mesh_scripts != 0:
			failures.append(name + ": display props must retain the ordinary unskinned path")
		for clip: String in ["symptom", "work", "paused", "recovery", "recovery_hold", "low_motion", "short_loop"]:
			if not measured.animations.has(clip):
				failures.append(name + ": actual imported phase is missing: " + clip)
		print("GODOT_GAG_IMPORT=" + name + ";FACTS=" + JSON.stringify(measured))
		scene.free()
	if failures.is_empty():
		print("GODOT_GAG_IMPORT_PASS=3;BACKEND=headless_import_only")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)

func inspect(node: Node, measured: Dictionary) -> void:
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node as MeshInstance3D
		if instance.skin != null:
			measured.skin_meshes += 1
		if instance.get_script() != null:
			measured.mesh_scripts += 1
		for surface: int in instance.mesh.get_surface_count():
			measured.surfaces += 1
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var colours: Variant = arrays[Mesh.ARRAY_COLOR]
			var material: Material = instance.get_active_material(surface)
			if colours is PackedColorArray and not colours.is_empty():
				measured.colour_vertices += colours.size()
				for colour: Color in colours:
					if absf(colour.r - 1.0) > 0.001 or absf(colour.g - 1.0) > 0.001 or absf(colour.b - 1.0) > 0.001:
						measured.non_white_colour_vertices += 1
					var sample: Array[float] = [colour.r, colour.g, colour.b, colour.a]
					if measured.palette.size() < 4 and not measured.palette.has(sample):
						measured.palette.append(sample)
				if material is StandardMaterial3D and (material as StandardMaterial3D).vertex_color_use_as_albedo:
					measured.vertex_colour_enabled += 1
	if node is AnimationPlayer:
		var player: AnimationPlayer = node as AnimationPlayer
		for clip: String in player.get_animation_list():
			measured.animations.append(clip)
	for child: Node in node.get_children():
		inspect(child, measured)
