extends Node

var _output: String = ""

func _stage(name: String) -> void:
	var marker: FileAccess = FileAccess.open(_output.path_join("display-stage.json"),FileAccess.WRITE)
	marker.store_string(JSON.stringify({"stage":name,"ticks_ms":Time.get_ticks_msec(),"pid":OS.get_process_id()}))
	marker.close()

func _ready() -> void:
	call_deferred("_run")

func _process(_delta: float) -> void:
	if not _output.is_empty() and FileAccess.file_exists(_output.path_join("display.abort")):
		get_tree().quit(2)

func _run() -> void:
	var config_path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--config="): config_path = argument.trim_prefix("--config=")
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	var output: String = config.output_dir
	_output = output
	_stage("config_loaded")
	var root_script: Script = load(get_script().resource_path.get_base_dir().path_join("display_root.gd"))
	_stage("root_script_loaded")
	var app: Control = load("res://game/app/main.tscn").instantiate()
	_stage("main_instantiated")
	app.set_script(root_script)
	_stage("root_script_attached")
	add_child(app)
	_stage("app_added")
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var conditions: Array = config.get("conditions",[])
	if conditions.is_empty():
		for window: Array in [[2560,1440],[2880,1920]]:
			for ui: int in [100,200]:
				for scale: int in [10000,7500,6667]:
					conditions.append({"window_pixels":window,"ui_scale_percent":ui,"scene_scale_bp":scale})
	for index: int in conditions.size():
		var condition: Dictionary = conditions[index]
		DisplayServer.window_set_size(Vector2i(condition.window_pixels[0],condition.window_pixels[1]))
		app._set_ui_scale(1 if int(condition.ui_scale_percent)==100 else 2)
		app._viewport.scaling_3d_scale = float(condition.scene_scale_bp)/10000.0
		_stage("settings_applied_%02d" % index)
		for frame: int in 6: await get_tree().process_frame
		app._sync_scene_pixels()
		app._view.overview()
		var started: int = Time.get_ticks_msec()
		while int(app._view.resource_usage().pending_bindings)>0:
			if FileAccess.file_exists(output.path_join("display.abort")) or Time.get_ticks_msec()-started>30000:
				push_error("Display bindings incomplete")
				get_tree().quit(2)
				return
			await get_tree().process_frame
		_stage("bindings_complete_%02d" % index)
		await RenderingServer.frame_post_draw
		_stage("frame_post_draw_%02d" % index)
		var screenshot: String = output.path_join("display-%02d.png" % index)
		var root_image: Image = get_window().get_texture().get_image()
		if root_image.save_png(screenshot)!=OK:
			push_error("Display root PNG could not be saved")
			get_tree().quit(2)
			return
		var screen: Transform2D = app._world_container.get_viewport_transform()*app._world_container.get_global_transform()
		var physical: Vector2 = app._world_container.size*Vector2(screen.x.length(),screen.y.length())
		var record: Dictionary = {"index":index,"condition":condition,"pid":OS.get_process_id(),"exe_sha256":FileAccess.get_sha256(OS.get_executable_path()),"engine":Engine.get_version_info(),"features":{"template":OS.has_feature("template"),"release":OS.has_feature("release"),"debug":OS.has_feature("debug")},"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"window_pixels":[DisplayServer.window_get_size().x,DisplayServer.window_get_size().y],"root_raster_pixels":[get_window().get_texture().get_width(),get_window().get_texture().get_height()],"native_2d_mode":get_window().content_scale_mode,"ui_scale_percent":app._ui_scale*100,"scene_control_physical_extent":[physical.x,physical.y],"scene_output_pixels":[app._viewport.size.x,app._viewport.size.y],"scene_output_gl_handle":RenderingServer.texture_get_native_handle(app._viewport.get_texture().get_rid()),"scene_scale":app._viewport.scaling_3d_scale,"world_unchanged_tick":app._view.world.sim_tick,"scope":"display-only legal preset; no simulation speed, allocation budget or stability conclusion"}
		record.root_viewport_texture_declared_pixels = record.root_raster_pixels
		record.gpu = RenderingServer.get_video_adapter_name()
		record.root_raster_pixels = [root_image.get_width(),root_image.get_height()]
		record.root_png = {"path":screenshot,"sha256":FileAccess.get_sha256(screenshot),"pixels":record.root_raster_pixels}
		var root_logical: Vector2 = app.get_viewport_rect().size
		var root_stretch: Transform2D = get_window().get_stretch_transform()
		var root_physical: Vector2i = Vector2i((root_logical*Vector2(root_stretch.x.length(),root_stretch.y.length())).ceil())
		record.root_canvas_physical_extent = [root_physical.x,root_physical.y]
		record.native_2d_raster_matches_canvas = root_image.get_size()==root_physical
		var ready: String = output.path_join("display-%02d.json" % index)
		var file: FileAccess = FileAccess.open(ready+".next",FileAccess.WRITE)
		file.store_string(JSON.stringify(record))
		file.close()
		if DirAccess.rename_absolute(ready+".next",ready)!=OK:
			push_error("Display metadata could not be published")
			get_tree().quit(2)
			return
		while not FileAccess.file_exists(output.path_join("display-%02d.ack" % index)):
			if FileAccess.file_exists(output.path_join("display.abort")) or Time.get_ticks_msec()-started>120000:
				push_error("Renderer capture did not acknowledge condition")
				get_tree().quit(2)
				return
			await get_tree().process_frame
	app.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
