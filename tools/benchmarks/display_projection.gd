extends RefCounted

var view: HospitalView
var viewport: SubViewport
var status: Label
var _start_us: int
var _record: FileAccess

func _init(parent: Node, content: HospitalContent, world: WorldState, window: Vector2i, scale: float, ui: int, output: String) -> void:
	DisplayServer.window_set_size(window)
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(root)
	status = Label.new()
	status.text = "可复现基准 · 实际呈现间隔需外部采集"
	status.add_theme_font_override("font",load("res://assets/fonts/NotoSansCJKsc-Regular.otf"))
	status.add_theme_font_size_override("font_size",18*ui)
	root.add_child(status)
	var container: SubViewportContainer = SubViewportContainer.new()
	container.stretch = true
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(container)
	viewport = SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.scaling_3d_scale = scale
	container.add_child(viewport)
	view = HospitalView.new(content)
	viewport.add_child(view)
	view.bind(world,3)
	_start_us = Time.get_ticks_usec()
	_record = FileAccess.open(output.path_join("render-observations.ndjson"),FileAccess.WRITE)

func update(world: WorldState) -> void:
	var elapsed: float = float(Time.get_ticks_usec()-_start_us)/1000000.0
	var period: int = int(elapsed/10.0)%6
	var floor_id: int = [3,10,1000,10000,3,3][period]
	if view.observed_floor!=floor_id:
		view.bind(world,floor_id)
	view.camera.size = [28.0,90.0,140.0,90.0,55.0,140.0][period]
	view.camera.position.x = 72.0+sin(elapsed*0.15)*12.0
	view.update_facts()
	status.text = "%d身体 · %dF · %s" % [world.present_actor_count(),floor_id,world.clock_text()]
	_record.store_line(JSON.stringify({"real_usec":Time.get_ticks_usec(),"sim_tick":world.sim_tick,"observed_floor":floor_id,
		"window_pixels":[DisplayServer.window_get_size().x,DisplayServer.window_get_size().y],"viewport_pixels":[viewport.size.x,viewport.size.y],
		"scene_scale":viewport.scaling_3d_scale,"engine_frames_drawn":Engine.get_frames_drawn(),
		"draw_calls":_observable(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":_observable(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"render_objects":_observable(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"presented_frame_interval_ms":null,"GPU_ms":null}))

func describe() -> Dictionary:
	return {"display_server":DisplayServer.get_name(),"rendering_method":RenderingServer.get_current_rendering_method(),
		"rendering_driver":RenderingServer.get_current_rendering_driver_name(),"adapter":RenderingServer.get_video_adapter_name(),
		"presented_frame_capture":"missing; engine render observations do not prove display-change intervals",
		"camera_sequence":"pan, zoom, active-floor switch; acceptance-tool cameras include technical full-floor views"}

func _observable(monitor: int) -> Variant:
	var value: float = Performance.get_monitor(monitor)
	return value if value>0.0 else null
