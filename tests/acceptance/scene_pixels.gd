extends RefCounted

func run(t, _content: HospitalContent) -> void:
	var app: Control = load("res://game/app/main.tscn").instantiate()
	t.root.add_child(app)
	app.set_process(false)
	await t.process_frame
	if app._simulation==null:
		t.check("CORE-43",false,"Actual isolated application did not activate")
		app.queue_free()
		return
	var window: Window = app.get_window()
	var original_size: Vector2i = window.size
	var original_scale_size: Vector2i = window.content_scale_size
	var original_scale_mode: int = window.content_scale_mode
	var original_scale_factor: float = window.content_scale_factor
	var original_embed: bool = window.gui_embed_subwindows
	var before: Dictionary = app._simulation.world.freeze()
	var texture: ViewportTexture = app._world_container.texture
	var viewport_rid: RID = app._viewport.get_viewport_rid()
	var observations: Array = []
	var valid: bool = true
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_size = Vector2i(1440,900)
	window.gui_embed_subwindows = true
	for dimensions: Vector2i in [Vector2i(2560,1440),Vector2i(2880,1920)]:
		window.size = dimensions
		# The headless Window does not apply an OS DPI transform. A real parent
		# canvas transform still exercises the same logical-to-physical handoff.
		app.scale = Vector2.ONE if dimensions.x==2560 else Vector2(1.25,1.25)
		# Exercise a real Window stretch independently of the parent Control.
		window.content_scale_factor = 1.25 if dimensions.x==2560 else 1.0
		for ui: int in [1,2]:
			app._set_ui_scale(ui)
			await t.process_frame
			await t.process_frame
			app._sync_scene_pixels()
			var control: Control = app._world_container
			var transform: Transform2D = window.get_stretch_transform()*window.global_canvas_transform*control.get_canvas_transform()*control.get_global_transform()
			var origin: Vector2 = transform*Vector2.ZERO
			var width: float = origin.distance_to(transform*Vector2(control.size.x,0))
			var height: float = origin.distance_to(transform*Vector2(0,control.size.y))
			var expected: Vector2i = Vector2i(ceili(width),ceili(height))
			valid = valid and app._viewport.size==expected and window.content_scale_mode==Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
			if dimensions.x==2560:
				valid = valid and not is_equal_approx(window.get_stretch_transform().x.length(),1.0)
			for scale: float in [1.0,0.75,0.6667]:
				app._viewport.scaling_3d_scale = scale
				app._view.overview()
				var bounds: AABB = app._view._floor_bounds()
				var safe: bool = true
				for corner: int in 8:
					var projected: Vector2 = app._view.camera.unproject_position(bounds.get_endpoint(corner))
					safe = safe and Rect2(Vector2.ZERO,Vector2(expected)).has_point(projected)
				var cell: Array = [35,67]
				var point: Vector2 = app._view.camera.unproject_position(Vector3((cell[0]+0.5-32)*1.5,0,(cell[1]+0.5-64)*1.5))
				var local: Vector2 = point*control.size/Vector2(expected)
				var recovered: Array = app._view.cell_at_screen(local*Vector2(app._viewport.size)/control.size)
				var pan: InputEventMouseMotion = InputEventMouseMotion.new()
				pan.button_mask = MOUSE_BUTTON_MASK_MIDDLE
				pan.relative = Vector2(12,7)
				var camera: Vector3 = app._view.camera.position
				var meters: float = app._view.camera.size/float(expected.y)
				var actual_pixels: Vector2 = pan.relative*Vector2(expected)/control.size
				var offset: Vector3 = -app._view.camera.basis.x*actual_pixels.x*meters+app._view.camera.basis.y*actual_pixels.y*meters
				offset.y = 0
				app._world_input(pan)
				var pan_ok: bool = app._view.camera.position.is_equal_approx(camera+offset)
				valid = valid and safe and recovered==cell and pan_ok and is_equal_approx(app._viewport.scaling_3d_scale,scale)
				valid = valid and app._world_container.texture==texture and app._viewport.get_viewport_rid()==viewport_rid
				observations.append({"window":dimensions,"parent_canvas_scale":app.scale,"window_stretch":window.get_stretch_transform(),"embedded_subwindows":window.gui_embed_subwindows,"ui":ui,"scene_scale":scale,"control_physical_extent":Vector2(width,height),"viewport":app._viewport.size,"overview_safe":safe,"picked_cell":recovered,"pan":pan_ok})
	window.size = original_size
	window.content_scale_size = original_scale_size
	window.content_scale_mode = original_scale_mode
	window.content_scale_factor = original_scale_factor
	window.gui_embed_subwindows = original_embed
	valid = valid and app._simulation.world.freeze()==before
	if app._snapshots.busy(): app._snapshots.wait_for_idle()
	app._guard.call("release")
	app.queue_free()
	await t.process_frame
	t.check("CORE-43",valid and not is_instance_valid(app),{"conditions":observations,"native_2d_mode":"canvas_items","application_released":not is_instance_valid(app),"scope":"production geometry, control ownership and coordinate handoff; no GPU allocation or OS presentation claim"})
