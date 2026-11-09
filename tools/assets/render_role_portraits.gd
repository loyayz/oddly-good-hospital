extends SceneTree

const Factory = preload("res://tools/assets/asset_factory.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 320)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(1.0, 0.97, 0.92)
	environment.environment.ambient_light_energy = 0.65
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -25, 0)
	light.light_energy = 0.9
	world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.15
	camera.position = Vector3(2.6, 2.0, 4.0)
	world.add_child(camera)
	camera.look_at(Vector3(0, 0.95, 0))
	for role: String in ["doctor","nurse","receptionist","cleaner","mechanic","researcher","decorator"]:
		var subject: Node3D = Factory.body("S49", 1, role)
		world.add_child(subject)
		Factory.seek(subject, "idle", 0.4)
		for frame: int in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = viewport.get_texture().get_image()
		var error: Error = image.save_png(output.path_join(role + ".png"))
		if error != OK:
			push_error("Role portrait save failed: " + role)
			quit(1)
			return
		subject.free()
	viewport.queue_free()
	await process_frame
	print("ROLE_PORTRAITS_RESULT=7 actual assembled role outfits rendered")
	quit()
