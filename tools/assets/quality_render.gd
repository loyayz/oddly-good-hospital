extends SceneTree

const Factory = preload("res://tools/assets/asset_factory.gd")
var subjects: Array[Node3D] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.91, 0.88, 0.81)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(1.0, 0.97, 0.91)
	environment.environment.ambient_light_energy = 0.6
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.light_energy = 0.75
	light.rotation_degrees = Vector3(-55, -30, 0)
	world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17.0
	world.add_child(camera)
	var right := Vector3(0.8, 0, -0.6)
	var front := Vector3(0.6, 0, 0.8)
	var center: Vector3 = right * 6.75 + front * 7.0 + Vector3(0, 1.6, 0)
	camera.position = center + Vector3(18, 18, 24)
	camera.look_at(center)
	var identities: Array[String] = ["S59", "S01", "S55", "S63", "S49", "S03", "S05", "S02", "S14", "S36", "S26", "S21"]
	for i: int in identities.size():
		var body: Node3D = Factory.body(identities[i], 1 + i % 4)
		world.add_child(body)
		body.position = right * float(i % 4) * 4.5 + front * floorf(float(i) / 4.0) * 7.0
		subjects.append(body)
		Factory.seek(body, "walk", 0.47)
		var label := Label3D.new()
		label.text = identities[i]
		label.font_size = 36
		label.pixel_size = 0.018
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.13, 0.22, 0.29)
		label.outline_modulate = Color(0.96, 0.93, 0.85)
		label.position = body.position + Vector3(0, -0.3, 0)
		world.add_child(label)
	for count: int in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var output: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.get_texture().get_image().save_png(output.path_join("godot-nine-rigs.png"))
	var renderer: Dictionary = {"engine": Engine.get_version_info().string,
		"method": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"visible_subjects": subjects.size(), "image": "godot-nine-rigs.png",
		"scope": "real backend asset preview; not the 640-person hospital acceptance benchmark"}
	var metrics: Dictionary = {}
	for key: String in ClassDB.class_get_integer_constant_list("RenderingServer"):
		if key.begins_with("RENDERING_INFO_"):
			metrics[key] = RenderingServer.get_rendering_info(ClassDB.class_get_integer_constant("RenderingServer", key))
	renderer["rendering_server_metrics"] = metrics
	var file := FileAccess.open(output.path_join("godot-renderer.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(renderer, "\t"))
	file.close()
	print("ASSET_RENDER_RESULT=" + JSON.stringify(renderer))
	quit()
