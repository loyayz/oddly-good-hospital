extends SceneTree

const PANEL_IDS: Array[String] = ["building","clinical","plans","ward","training","schedule","staff_life","waiting","supplies","environment","maintenance","departments","finance","recruitment","arrivals"]

var _app: Control
var _failures: Array[String] = []
var _results: Dictionary = {}
var _output: String = ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# The native guard and SQLite must use a separate acceptance profile.
	var profile: String = OS.get_user_data_dir()
	if not "stage24" in profile.to_lower().replace(" ",""):
		push_error("Stage24 UI verification requires a dedicated Stage24 user-data profile")
		quit(2)
		return
	_output=profile.get_base_dir().path_join("stage24-ui-evidence")
	DirAccess.make_dir_recursive_absolute(_output)
	_results.user_directory=profile
	_results.engine=Engine.get_version_info()
	_results.display_driver=DisplayServer.get_name()
	var scene_path: String = str(ProjectSettings.get_setting("application/run/main_scene","res://game/app/main.tscn"))
	var scene: PackedScene = load(scene_path) as PackedScene
	_check("real_main_scene_loads",scene!=null)
	if scene==null: _finish(); return
	_app=scene.instantiate() as Control
	root.add_child(_app)
	# _ready invokes the product acquisition path; never replace it with a fixture.
	var deadline: int = Time.get_ticks_msec()+15000
	while _app.get("_simulation")==null and Time.get_ticks_msec()<deadline:
		await process_frame
	_check("acquire_created_real_hospital",_app.get("_simulation")!=null)
	if _app.get("_simulation")==null: _finish(); return
	_app.call("_set_speed",0)
	var simulation: HospitalSimulation = _app.get("_simulation")
	var session: GameSession = _app.get("_session")
	_check("hospital_paused",session.actual_speed()==0)
	_check("initial_world_valid",simulation.world.validate(simulation.content).is_empty())
	var before: String = JSON.stringify(simulation.world.freeze(),"",true,true)
	var panels: Node = _app.get("_management_panels")
	_check("management_container_exists",panels!=null)
	if panels==null: _finish(); return
	var inventory: Dictionary = {}
	for id: String in PANEL_IDS:
		var panel: Control = panels.get_node_or_null(NodePath(id)) as Control
		_check(id+"_registered",panel!=null)
		if panel==null: continue
		_app.call("_show_panel",id)
		# Exercise the same attachment and rebuild used after activating a hospital.
		if id=="building":
			panel.call("attach",simulation,session,int(_app.get("_observed_floor")))
		else:
			panel.call("attach",simulation,session)
		if panel.has_method("rebuild"): panel.call("rebuild")
		await create_timer(0.6).timeout
		var counts: Dictionary = {"labels":0,"buttons":0,"choices":0,"inputs":0,"nonempty_labels":0}
		_count_controls(panel,counts)
		inventory[id]=counts
		_check(id+"_visible",panel.is_visible_in_tree())
		_check(id+"_has_content",int(counts.nonempty_labels)>0)
		_check(id+"_has_actions",int(counts.buttons)>0)
		if id!="building":
			_check(id+"_uses_real_hospital",panel.get("simulation")==simulation and panel.get("session")==session)
		_check(id+"_query_preserves_world",before==JSON.stringify(simulation.world.freeze(),"",true,true))
	_results.panels=inventory
	if "--capture-ui" in OS.get_cmdline_user_args():
		_check("capture_requires_real_renderer",DisplayServer.get_name()!="headless")
		if DisplayServer.get_name()!="headless":
			for scenario: Dictionary in [{"size":Vector2i(1440,900),"scale":1,"name":"1440x900-ui100"},{"size":Vector2i(1280,720),"scale":2,"name":"1280x720-ui200"}]:
				DisplayServer.window_set_size(scenario.size)
				_app.call("_set_ui_scale",scenario.scale)
				for id: String in ["clinical","supplies","finance"]:
					_app.call("_show_panel",id)
					await _capture(str(scenario.name)+"-"+id)
	var snapshot: Dictionary = simulation.world.freeze()
	var restored: WorldState = WorldState.new(snapshot.duplicate(true))
	_check("frozen_world_restores_valid",restored.validate(simulation.content).is_empty())
	_check("restore_preserves_all_facts",JSON.stringify(restored.freeze(),"",true,true)==before)
	_check("ui_refresh_does_not_advance_time",simulation.world.sim_tick==int(snapshot.sim_tick) and session.actual_speed()==0)
	_finish()

func _count_controls(node: Node, counts: Dictionary) -> void:
	if node is Label:
		counts.labels+=1
		if not (node as Label).text.strip_edges().is_empty(): counts.nonempty_labels+=1
	if node is Button: counts.buttons+=1
	if node is OptionButton: counts.choices+=1
	if node is LineEdit or node is TextEdit or node is SpinBox: counts.inputs+=1
	if node is RichTextLabel:
		counts.labels+=1
		if not (node as RichTextLabel).text.strip_edges().is_empty(): counts.nonempty_labels+=1
	for child: Node in node.get_children(): _count_controls(child,counts)

func _capture(name: String) -> void:
	for frame: int in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var saved: Error = image.save_png(_output.path_join(name+".png"))
	_check(name+"_capture",saved==OK and image.get_width()>0 and image.get_height()>0)
	print("STAGE24_UI_CAPTURE="+_output.path_join(name+".png"))

func _check(name: String, passed: bool) -> void:
	_results[name]=passed
	if not passed:
		_failures.append(name)
		push_error("Stage24 UI verification failed: "+name)

func _finish() -> void:
	var simulation: Variant = null
	if is_instance_valid(_app):
		simulation = _app.get("_simulation")
		if simulation!=null and simulation.has_method("dispose"):
			simulation.call("dispose")
		var guard: Variant = _app.get("_guard")
		if guard!=null: guard.call("release")
		root.remove_child(_app)
		_app.queue_free()
		_app=null
	for frame: int in range(3):
		await process_frame
	print("STAGE24_UI_RELEASE_SIMULATION")
	simulation=null
	await process_frame
	_results.failures=_failures
	_results.ok=_failures.is_empty()
	var file: FileAccess = FileAccess.open(_output.path_join("stage24-ui-evidence.json"),FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(_results,"\t",true))
		file.close()
	print("STAGE24_UI_PASS="+str(_results.ok))
	quit(0 if _results.ok else 1)
