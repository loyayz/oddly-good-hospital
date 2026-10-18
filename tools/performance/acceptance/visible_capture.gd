extends Node

const OperationDriver = preload("operation_driver.gd")
const SnapshotWitness = preload("snapshot_witness.gd")

# Engine callbacks are diagnostic samples, never presented frames.
# Notification QPC is sampled natively; original engine step endpoints retain
# their own domain and are joined through explicit QPC/engine/QPC brackets.
var config: Dictionary
var app
var output: String
var stream: FileAccess
var buffer: Array[String] = []
var phase: String = "warmup"
var generation: int = 0
var started_us: int = 0
var capture_begin_us: int = 0
var capture_begin_tick: int = 0
var capture_end_us: int = 0
var capture_end_tick: int = 0
var capture_steps: int = 0
var total_steps: int = 0
var engine_callbacks: int = 0
var last_poll_us: int = 0
var last_flush_us: int = 0
var last_heartbeat_us: int = 0
var warmup_work_seen: bool = false
var warmup_ready: bool = false
var warmup_ready_us: int = 0
var operation_index: int = 0
var waiting_save: String = ""
var operation_begin_us: int = 0
var waiting_operation: Dictionary = {}
var stop_requested: bool = false
var dense_open: bool = false
var dense_index: int = 0
var telemetry_write_us: int = 0
var telemetry_lines: int = 0
var observed_session: WeakRef
var capture_begin_session: String = ""
var pending_step_observation: Dictionary = {}
var last_step_signal_us: int = 0
var clock_api: Script
var clock_method_ready: bool = false
var clock_frequency: int = 0
var last_clock_sample_us: int = 0
var warmup_gate_pending: bool = false
var finishing: bool = false
var quit_requested: bool = false
var root_released: bool = false
var exit_code: int = 0
var tail_ack: Dictionary = {}
var screenshots: Array[Dictionary] = []
var root_readback_pixels: Vector2i = Vector2i.ZERO
var failure_reason: String = ""
var profile_path: String = ""
var operation_driver: RefCounted
var save_requests: Dictionary = {}
var completed_save_operations: Dictionary = {}
var snapshot_sources: Dictionary = {}
var loaded_snapshot_checks: Dictionary = {}
var last_auto_deadline: int = -1
var root: Window
var initial_hospital_id: String = ""

func _ready() -> void:
	root = get_tree().root
	call_deferred("_boot")

func quit(code: int = 0) -> void:
	get_tree().quit(code)

func _boot() -> void:
	var config_path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--config="): config_path = argument.trim_prefix("--config=")
	if not config_path.is_absolute_path():
		push_error("Expected an absolute --config=... JSON path")
		quit(2)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not parsed is Dictionary:
		push_error("Expected an absolute --config=... JSON path")
		quit(2)
		return
	config = parsed
	var config_error: String = _validate_config()
	if not config_error.is_empty():
		push_error(config_error)
		quit(2)
		return
	output = str(config.output_dir)
	if FileAccess.file_exists(output.path_join("telemetry.ndjson")):
		push_error("Refusing to replace an existing capture")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output)!=OK:
		push_error("Cannot create capture output")
		quit(2)
		return
	stream = FileAccess.open(output.path_join("telemetry.ndjson"), FileAccess.WRITE)
	if stream == null:
		quit(2)
		return
	started_us = Time.get_ticks_usec()
	var folder: String = get_script().resource_path.get_base_dir()
	clock_api = ResourceLoader.load(folder.path_join("native_clock.gd"))
	clock_method_ready = clock_api!=null and clock_api.available()
	if not clock_method_ready:
		_fail("Release native PlatformArrivalMath.monotonic_clock method unavailable")
		return
	var first_clock: Dictionary = _clock()
	if first_clock.get("qpc_ticks")==null:
		_fail("Release native monotonic clock unavailable: "+str(first_clock))
		return
	clock_frequency = int(first_clock.qpc_frequency)
	if not _clock_bracket("boot"): return
	if not OS.has_feature("template") or not OS.has_feature("release") or OS.has_feature("editor") or OS.has_feature("debug") or DisplayServer.get_name()=="headless":
		_fail("Requires the actual visible exported Release executable")
		return
	# The external startup override isolates the profile before renderer startup.
	var sandbox: String = "OddlyGoodHospital Formal "+str(config.run_id)
	if not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir",false)) or str(ProjectSettings.get_setting("application/config/custom_user_dir_name",""))!=sandbox:
		_fail("Startup override did not establish the run-specific formal profile")
		return
	var directory: String = OS.get_user_data_dir().replace("\\", "/")
	if not directory.ends_with("/"+sandbox) or not ProjectSettings.globalize_path("user://hospitals").replace("\\", "/").begins_with(directory+"/"):
		_fail("Cannot establish an isolated native/user:// profile")
		return
	if DirAccess.dir_exists_absolute(directory.path_join("hospitals")):
		_fail("Formal profile already contains a hospital library")
		return
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:
		_fail("Cannot create isolated profile")
		return
	profile_path = directory
	var content_script: Script = ResourceLoader.load("res://game/content/content_db.gd")
	var world_script: Script = ResourceLoader.load("res://game/sim/world_state.gd")
	if content_script==null or world_script==null:
		_fail("Original PCK content/world script unavailable")
		return
	var content: RefCounted = content_script.new()
	if not str(content.error).is_empty():
		_fail(str(content.error))
		return
	var capture_contract: Dictionary = content.balance.performance_targets.capture
	if int(config.minimum_frame_samples)!=int(capture_contract.minimum_frame_samples) or int(config.minimum_step_samples)!=int(capture_contract.minimum_step_samples):
		_fail("Scenario sample minima differ from the current content contract")
		return
	var source: FileAccess = FileAccess.open(str(config.input_path), FileAccess.READ)
	if source == null:
		_fail("Cannot read the original Fixture input")
		return
	var saved: Variant = source.get_var(false)
	source.close()
	if not saved is Dictionary or not saved.get("facts") is Dictionary or not saved.get("floors") is Array or not saved.get("visitor_ids") is Array or str(saved.get("content_fingerprint", ""))!=str(content.content_fingerprint):
		_fail("Fixture content fingerprint differs from Release content")
		return
	var expected_floors: Array = [1] if str(config.layout)=="wide" else ([1,10,1000,10000] if str(config.layout)=="tall" else [1,2,3,4])
	if saved.floors!=expected_floors or not int(config.floor_id) in expected_floors:
		_fail("Fixture floors differ from declared layout/observed floor")
		return
	var world: RefCounted = world_script.new(saved.facts)
	initial_hospital_id = world.hospital_id
	var reason: String = world.validate(content)
	if not reason.is_empty() or world.present_actor_count()!=int(config.actors):
		_fail("Invalid/incorrect Fixture: "+reason)
		return
	if int(world.facts.get("gameplay_version",0))!=1:
		_fail("Fixture must already contain the original production gameplay version")
		return
	if not int(config.speed) in [1, 3] or not int(config.ui_scale_percent) in [100, 200] or not int(config.scene_scale_bp) in [10000, 7500, 6667]:
		_fail("Scenario settings are outside the existing acceptance options")
		return
	var scene: PackedScene = ResourceLoader.load("res://game/app/main.tscn")
	var root_script: Script = ResourceLoader.load(folder.path_join("formal_root.gd"))
	if scene==null or root_script==null:
		_fail("Original PCK main scene or external AppRoot subclass unavailable")
		return
	app = scene.instantiate()
	app.set_script(root_script)
	app.observer = self
	add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not app.mount_fixture(world, content, int(config.get("floor_id", 1))):
		_fail("Fixture AppRoot composition failed")
		return
	operation_driver = OperationDriver.new(app,self)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(int(config.window_pixels[0]), int(config.window_pixels[1])))
	app._viewport.scaling_3d_scale = float(config.scene_scale_bp)/10000.0
	app._set_ui_scale(1 if int(config.ui_scale_percent)==100 else 2)
	app._show_panel(str(config.get("initial_panel", "details")))
	app._set_speed(int(config.speed))
	DisplayServer.window_move_to_foreground()
	_emit("boot", {"pid":OS.get_process_id(),"exe":OS.get_executable_path(),"engine":Engine.get_version_info(),"input_path":config.input_path,"input_sha256":FileAccess.get_sha256(config.input_path),"content_fingerprint":content.content_fingerprint,"profile":directory,"fixture_floors":saved.floors,"actual_present_actors":world.present_actor_count(),"requested":config,"settings":_settings(),"fixture_validation":"passed","instrumentation":"external main-scene observer; original AppRoot and GameSession","observer_sha256":_observer_hashes(folder),"startup_override_sha256":FileAccess.get_sha256(OS.get_executable_path().get_base_dir().path_join("override.cfg")),"startup_main_scene":ProjectSettings.get_setting("application/run/main_scene"),"not_covered":["product startup/load","complete GPU residency","long stability"]})
	_flush()

func _validate_config() -> String:
	for key: String in ["output_dir","input_path","run_id","actors","layout","floor_id","window_pixels","scene_scale_bp","ui_scale_percent","speed","minimum_frame_samples","minimum_step_samples"]:
		if not config.has(key): return "Scenario missing "+key
	if not str(config.output_dir).is_absolute_path() or not str(config.input_path).is_absolute_path(): return "Input/output paths must be absolute"
	var run_id: String = str(config.run_id)
	if run_id.is_empty() or run_id.length()>80: return "Invalid run_id"
	for character: String in run_id:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_": return "run_id must contain only ASCII letters, numbers, hyphen or underscore"
	if not config.window_pixels is Array or config.window_pixels.size()!=2 or int(config.window_pixels[0])<=0 or int(config.window_pixels[1])<=0: return "window_pixels must contain two positive dimensions"
	if not str(config.layout) in ["four_floors","wide","tall"]: return "Unsupported Fixture layout"
	if int(config.actors)<=0: return "Actual actor count must be positive"
	if str(config.get("workload_kind","reference"))=="reference" and not int(config.actors) in [160,320,640]: return "Unsupported formal reference actor group"
	if not str(config.get("workload_kind","reference")) in ["reference","boundary","history"]: return "Unsupported workload kind"
	if not int(config.speed) in [1,3] or not int(config.ui_scale_percent) in [100,200] or not int(config.scene_scale_bp) in [10000,7500,6667]: return "Unsupported formal display/playback option"
	if float(config.get("maximum_real_seconds",900))<=0 or float(config.get("minimum_capture_real_seconds",0))<0: return "Invalid real duration bounds"
	if not config.get("operations",[]) is Array: return "operations must be an array"
	var ids: Dictionary = {}
	for operation: Variant in config.get("operations",[]):
		if not operation is Dictionary or str(operation.get("id","")).is_empty(): return "Malformed operation"
		if not str(operation.get("action","")) in ["panel","floor","overview","pan","zoom","save"] and not str(operation.get("action","")) in OperationDriver.ACTIONS: return "Unsupported operation"
		if float(operation.get("after_real_seconds",0))<0: return "Operation real deadline cannot be negative"
		if ids.has(str(operation.id)): return "Operation IDs must be unique"
		ids[str(operation.id)] = true
	return ""

func _observer_hashes(folder: String) -> Dictionary:
	var result: Dictionary = {}
	for name: String in ["visible_capture.gd","formal_root.gd","native_clock.gd","observed_library.gd","observed_snapshots.gd","snapshot_witness.gd","preview_input_observer.gd","operation_driver.gd","launch.tscn","probe.gd","probe.tscn"]:
		result[name] = FileAccess.get_sha256(folder.path_join(name))
	return result

func observe_session(session: RefCounted) -> void:
	if observed_session!=null and observed_session.get_ref()==session: return
	if not session.has_signal("tick_completed"):
		_fail("Release GameSession lacks the generic tick_completed observation signal")
		return
	observed_session = weakref(session)
	session.connect("tick_completed", _on_tick_completed)
	if session.has_signal("playback_changed"):
		session.connect("playback_changed", _on_playback_changed)
	else:
		_emit("coverage_gap", {"metric":"exact pause/speed segmentation","reason":"playback_changed signal absent; heartbeat is not an exact transition trace"})
	_emit("hospital_session_begin", {"hospital_id":session.simulation.world.hospital_id,"hospital_session":session.loading_session_id,"tick":session.simulation.world.sim_tick,"phase":phase})

func _on_tick_completed(result: RefCounted) -> void:
	var notification_clock: Dictionary = _clock()
	var now: int = Time.get_ticks_usec()
	last_step_signal_us = now
	var session: RefCounted = observed_session.get_ref()
	total_steps += 1
	if phase=="capture": capture_steps += 1
	var events: Array = []
	for event: RefCounted in result.facts:
		if event.kind in ["arrival_day_planned", "command_applied", "command_rejected"]:
			events.append({"kind":event.kind,"sim_tick":event.sim_tick,"details":event.details})
	_emit("step", {"tick":result.sim_tick,"revision":result.revision,"started_engine_us":result.started_engine_us,"completed_engine_us":result.completed_engine_us,"elapsed_us":result.elapsed_us,"main_elapsed_us":result.main_elapsed_us,"between_slices_wall_us":result.elapsed_us-result.main_elapsed_us,"main_time_kind":"sum of original step_nonblocking execution slices; wall time, not OS CPU","completion_engine_us":now,"completion_qpc_ticks":notification_clock.get("qpc_ticks"),"completion_time_kind":"original tick_completed callback entry; later than original completed_engine_us","qpc_role":"completed-step notification observation","hospital_id":session.simulation.world.hospital_id,"hospital_session":session.loading_session_id,"phase":phase,"capture_step":phase=="capture","events":events}, now, notification_clock)
	if operation_driver!=null: operation_driver.on_tick(result)
	var shift_ticks: int = ceili(float(app._content.balance.schedule.shift_seconds)/float(session.simulation.world.TICK_SECONDS))
	if (int(result.sim_tick)-1)%shift_ticks==0:
		var staff_state: Array = []
		for id: String in session.simulation.world.facts.staff:
			var staff: Dictionary = session.simulation.world.facts.staff[id]
			staff_state.append({"id":id,"on_shift":staff.get("on_shift",false),"block_new_work":staff.get("block_new_work",false),"last_schedule_slot":staff.get("last_schedule_slot",-1),"reason":staff.get("schedule_reason",""),"rest_debt_ticks":staff.get("rest_debt_ticks",0)})
		_emit("shift_boundary_complete", {"executed_tick":int(result.sim_tick)-1,"completed_tick":result.sim_tick,"hospital_session":session.loading_session_id,"staff":staff_state}, now)

func _on_playback_changed() -> void:
	var notification_clock: Dictionary = _clock()
	on_session_state("playback_changed", "original session signal", notification_clock)

func on_session_state(action: String, source: String, notification_clock: Dictionary = {}) -> void:
	var kernel: RefCounted = app._simulation
	_emit("session_state", {"action":action,"source":source,"requested_speed":app._session.requested_speed,"actual_speed":app._session.actual_speed(),"pause_reasons":app._session.pause_reasons(),"pending":kernel.pending(),"step_in_progress":kernel.step_in_progress(),"original_step_started_us":kernel._step_context.get("started_us", null),"hospital_session":app._session.loading_session_id,"tick":kernel.world.sim_tick,"phase":phase,"qpc_role":"playback signal observation" if not notification_clock.is_empty() else "telemetry observation","contract":"a previously started preparation wait remains in its prior effective segment until completion"}, -1, notification_clock)

func after_frame(begin: int, end: int) -> void:
	engine_callbacks += 1
	_emit("engine_callback", {"begin_us":begin,"app_process_us":end-begin,"callback_index":engine_callbacks,"tick":app._simulation.world.sim_tick,"phase":phase,"source":"AppRoot._process; not a displayed frame"}, end)
	_observe_density(end)
	_observe_pending_step(end)
	if float(end-started_us)/1000000.0>float(config.get("maximum_real_seconds", 7200)):
		_fail("Time limit reached before completion; evidence incomplete")
		return
	if not app._simulation.preparing_error().is_empty():
		_fail("Production preparation failed: "+app._simulation.preparing_error())
		return
	if phase=="warmup" and not warmup_work_seen and not app._simulation.pending():
		for session: Dictionary in app._simulation.world.facts.sessions.values():
			if int(session.get("remaining_ticks", 0))<int(session.get("total_ticks", 0)): warmup_work_seen = true
	if end-last_heartbeat_us>=500000:
		last_heartbeat_us = end
		_heartbeat(end)
	if end-last_clock_sample_us>=500000:
		if not _clock_bracket("periodic"): return
	if end-last_poll_us>=100000:
		last_poll_us = end
		_poll_control()
	if phase=="capture": _operations(end)
	if stop_requested and _business_boundary_ready(): _end_capture()
	if finishing and not quit_requested and _business_boundary_ready():
		if not app._drafts.is_empty():
			_fail("Unresolved original drafts prevent normal product quit")
			return
		quit_requested = true
		_emit("normal_quit_requested", {"source":"original AppRoot._request_quit; final checkpoint and worker completion remain real"})
		app._request_quit()
	if end-last_flush_us>=500000: _flush()

func before_frame(now: int) -> void:
	if app._simulation==null or app._snapshots==null: return
	var deadline: int = int(app._auto_deadline_ms)
	if Time.get_ticks_msec()>=deadline and deadline!=last_auto_deadline:
		last_auto_deadline = deadline
		_emit("autosave_deadline", {"deadline_engine_ms":deadline,"pending":app._simulation.pending(),"saving":app._snapshots.busy(),"world_revision":app._simulation.world.revision,"saved_revision":app._saved_revision,"phase":phase},now)

func on_save_started(started: Dictionary, slot_kind: String, slot: String, begin: int, end: int) -> void:
	if not bool(started.get("ok",false)):
		_emit("save_start_deferred_or_failed", {"slot_kind":slot_kind,"slot":slot,"result":started,"phase":phase,"begin_us":begin,"end_us":end},end)
		return
	var request: Dictionary = started.request.duplicate(true)
	save_requests[str(request.request_id)] = {"request":request,"begin_engine_us":begin,"slot_kind":slot_kind,"slot":slot}
	_emit("save_request", {"request":request,"slot_kind":slot_kind,"slot":slot,"begin_us":begin,"end_us":end,"main_start_call_us":end-begin,"scope":"original request, boundary/freeze and writer launch; nested spans are inclusive","phase":phase},end)

func _observe_pending_step(now: int) -> void:
	var kernel = app._simulation
	if kernel.step_in_progress():
		if pending_step_observation.is_empty():
			pending_step_observation = {"hospital_session":app._session.loading_session_id,"tick_before":kernel.world.sim_tick,"original_step_started_us":kernel._step_context.get("started_us",null),"observed_begin_us":now,"step_phase":kernel._step_context.get("phase","")}
			_emit("pending_step_observed_begin", pending_step_observation, now)
	elif not pending_step_observation.is_empty():
		_emit("pending_step_observed_end", {"begin":pending_step_observation,"observed_end_us":now,"last_completed_signal_us":last_step_signal_us,"tick_after":kernel.world.sim_tick,"duration_kind":"observed wait bounds; original full step elapsed remains in TickResult"}, now)
		pending_step_observation = {}

func _heartbeat(now: int) -> void:
	var usage: Dictionary = app._view.resource_usage()
	var work: Dictionary = app._simulation.services.arrivals.preparation_metrics()
	var eligible: int = app._view._actors.size()
	var target: int = int(config.get("dense_target_actors", config.actors))
	var density_bp: Variant = eligible*10000/target if target>0 else null
	_emit("heartbeat", {"phase":phase,"tick":app._simulation.world.sim_tick,"completed_steps":capture_steps,"total_steps":total_steps,"speed":app._session.actual_speed(),"requested_speed":app._session.requested_speed,"pause_reasons":app._session.pause_reasons(),"pending":app._simulation.pending(),"world_actors":app._simulation.world.facts.actors.size(),"visible_bindings":eligible,"dense_target":target,"density_bp":density_bp,"resources":usage,"preparation":work,"settings":_settings()}, now)
	# This is an explicit observable gate, not proof every possible cache is warm.
	var candidate: bool = total_steps>=int(config.get("warmup_minimum_actual_steps", 32)) and warmup_work_seen and int(usage.pending_bindings)==0 and usage.errors.is_empty() and _business_boundary_ready() and app._session.actual_speed()==int(config.speed)
	if phase=="warmup" and candidate and not warmup_ready and not warmup_gate_pending:
		warmup_gate_pending = true
		call_deferred("_prepare_capture", usage.duplicate(true), work.duplicate(true))
	if phase=="capture" and _operations_complete(): _ack("operations_complete")

func _prepare_capture(usage: Dictionary, work: Dictionary) -> void:
	await get_tree().process_frame
	if not await _screenshot("prepared"): return
	if not _verify_settings(): return
	warmup_ready_us = Time.get_ticks_usec()
	warmup_ready = true
	_emit("warmup_complete", {"elapsed_us":warmup_ready_us-started_us,"actual_steps":total_steps,"real_work_observed":warmup_work_seen,"resources":usage,"preparation":work,"settings":_settings(),"gate_kind":"initial bindings, actual work and complete-step gate; background next-day preparation is ordinary capture load, not a warmup completion requirement"}, warmup_ready_us)
	_ack("prepared")

func _verify_settings() -> bool:
	var actual: Dictionary = _settings()
	if actual.window_pixels!=config.window_pixels or not is_equal_approx(float(actual.scene_scale),float(config.scene_scale_bp)/10000.0) or int(actual.ui_scale_percent)!=int(config.ui_scale_percent):
		_fail("Actual window/scene/UI settings differ from scenario: "+JSON.stringify(actual))
		return false
	if str(actual.renderer)!=str(config.get("rendering_method","gl_compatibility")):
		_fail("Actual renderer differs from scenario")
		return false
	if config.has("render_driver") and str(actual.render_driver)!=str(config.render_driver):
		_fail("Actual render driver differs from scenario")
		return false
	if not actual.native_2d_output or not actual.scene_output_matches_control:
		_fail("Actual 2D output or nested scene texture differs from physical display region: "+JSON.stringify(actual))
		return false
	return true

func _screenshot(name: String) -> bool:
	await RenderingServer.frame_post_draw
	var sampled: Dictionary = _clock()
	var begin: int = Time.get_ticks_usec()
	var image: Image = root.get_texture().get_image()
	if image==null or image.is_empty():
		_fail("Rendered screenshot unavailable: "+name)
		return false
	root_readback_pixels = image.get_size()
	var path: String = output.path_join(name+".png")
	var status: Error = image.save_png(path)
	if status!=OK:
		_fail("Cannot write screenshot: "+path)
		return false
	var record: Dictionary = {"name":name,"path":path,"sha256":FileAccess.get_sha256(path),"pixels":[image.get_width(),image.get_height()],"readback_and_write_us":Time.get_ticks_usec()-begin,"phase":phase,"kind_of_image":"actual root viewport readback; not proof of OS display or a presented-frame sample"}
	screenshots.append(record)
	_emit("screenshot", record, begin, sampled)
	return true

func _business_boundary_ready() -> bool:
	return app!=null and app._simulation!=null and not app._simulation.pending() and not app._simulation.saving_boundary() and not app._snapshots.busy() and app._library_thread==null and app._leave_operation.is_empty()

func _observe_density(now: int) -> void:
	if phase!="capture": return
	var eligible: int = app._view._actors.size()
	var target: int = int(config.get("dense_target_actors", config.actors))
	if target<=0: return
	var density_bp: int = eligible*10000/maxi(1, target)
	var dense: bool = density_bp>=int(app._content.balance.performance_targets.spatial_samples.minimum_density_bp)
	_emit("density", {"phase":phase,"density_bp":density_bp,"visible_binding_count":eligible,"denominator":target,"qualifies_logically":dense,"count_kind":"frustum-admitted bindings; raster visibility unverified","hospital_session":app._session.loading_session_id,"floor_id":app._observed_floor}, now)
	if dense!=dense_open:
		if dense: dense_index += 1
		_emit("dense_segment_begin" if dense else "dense_segment_end", {"segment":dense_index,"density_bp":density_bp,"visible_binding_count":eligible,"denominator":target,"count_kind":"frustum-admitted logical bindings; final raster visibility requires corroboration","boundary_kind":"AppRoot callback observation"}, now)
		dense_open = dense

func _poll_control() -> void:
	var path: String = output.path_join("control.json")
	if not FileAccess.file_exists(path): return
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary or int(value.get("generation", -1))<generation: return
	var requested: String = str(value.get("phase", ""))
	if not _business_boundary_ready() and requested in ["start", "stop"]: return
	generation = int(value.generation)
	match requested:
		"armed":
			if warmup_ready: _ack("prepared")
		"start":
			if phase!="warmup" or not warmup_ready: return
			if not _clock_bracket("before_capture_start"): return
			capture_begin_us = Time.get_ticks_usec()
			capture_begin_tick = app._simulation.world.sim_tick
			capture_begin_session = app._session.loading_session_id
			capture_steps = 0
			phase = "capture"
			_emit("capture_start", {"tick":capture_begin_tick,"warmup_complete_us":warmup_ready_us,"external_request":value})
			_ack("started")
		"stop":
			if phase!="capture": return
			if float(Time.get_ticks_usec()-capture_begin_us)/1000000.0<float(config.get("minimum_capture_real_seconds", 0)):
				_emit("stop_rejected", {"reason":"minimum scenario wall duration incomplete","minimum_capture_real_seconds":config.minimum_capture_real_seconds})
				return
			var minimum: int = int(app._content.balance.performance_targets.capture.minimum_step_samples)
			if capture_steps<minimum or not _operations_complete():
				_emit("stop_rejected", {"completed_steps":capture_steps,"minimum_steps":minimum,"operations_complete":_operations_complete()})
				return
			stop_requested = true
			_emit("stop_requested", {"external_request":value})
		"tail_ack":
			if phase=="stopped": _finish(value)

func _operations(now: int) -> void:
	if not waiting_save.is_empty(): return
	if operation_driver.active():
		_complete_operation_driver(operation_driver.poll(now))
		return
	if not _business_boundary_ready(): return
	var operations: Array = config.get("operations", [])
	if operation_index>=operations.size(): return
	var operation: Dictionary = operations[operation_index]
	if float(now-capture_begin_us)/1000000.0<float(operation.get("after_real_seconds", 0)): return
	operation_begin_us = Time.get_ticks_usec()
	_emit("operation_start", {"operation":operation,"source":"programmatic production callback; not OS input latency"}, operation_begin_us)
	match str(operation.action):
		"panel": app._show_panel(str(operation.panel))
		"floor": app._change_floor(int(operation.floor_id))
		"overview": app._view.overview()
		"pan": app._view.pan_camera(Vector2(float(operation.pixels[0]), float(operation.pixels[1])))
		"zoom": app._view.zoom_camera(float(operation.factor))
		"save":
			var prerequisite: String = operation_driver._check_work_prerequisite(operation.get("required_session",{}))
			if not prerequisite.is_empty():
				_fail(prerequisite)
				return
			var started: Dictionary = app._begin_save("manual", "formal-"+str(operation.id))
			if not started.get("ok", false):
				_fail("Save operation could not start")
				return
			waiting_save = str(started.request.request_id)
			waiting_operation = operation
			return
		_:
			waiting_operation = operation
			_complete_operation_driver(operation_driver.start(operation))
			return
	_emit("operation_complete", {"operation":operation,"elapsed_us":Time.get_ticks_usec()-operation_begin_us,"completion_kind":"callback_return; presented endpoint measured externally"})
	operation_index += 1

func _complete_operation_driver(result: Dictionary) -> void:
	if not bool(result.get("complete",false)): return
	if not bool(result.get("ok",false)):
		_emit("operation_failed", {"operation":waiting_operation,"result":result,"elapsed_us":Time.get_ticks_usec()-operation_begin_us})
		_fail(str(result.get("error","Operation failed")))
		return
	_emit("operation_complete", {"operation":waiting_operation,"elapsed_us":Time.get_ticks_usec()-operation_begin_us,"completion_kind":"original owner result and declared operation checks; displayed endpoint is external","details":result.get("details",{})})
	waiting_operation = {}
	operation_index += 1

func on_receipt(receipt: Dictionary) -> void:
	var request_id: String = str(receipt.get("request_id",""))
	var original: Dictionary = save_requests.get(request_id,{})
	_emit("save_receipt", {"receipt":receipt,"phase":phase,"request_observation":original,"elapsed_us":Time.get_ticks_usec()-int(original.begin_engine_us) if not original.is_empty() else null,"duration_kind":"original request entry through matching receipt observation"})
	if operation_driver!=null: operation_driver.on_receipt(receipt)
	if not original.is_empty() and not bool(receipt.get("ok",false)):
		_fail("Original save failed: "+str(receipt.get("error","")))
		return
	save_requests.erase(request_id)
	if str(receipt.get("request_id", ""))!=waiting_save: return
	if not receipt.get("ok", false):
		_fail("Production save failed")
		return
	completed_save_operations[str(waiting_operation.id)] = receipt.duplicate(true)
	_emit("operation_complete", {"operation":waiting_operation,"receipt":receipt,"elapsed_us":Time.get_ticks_usec()-operation_begin_us,"completion_kind":"original asynchronous save receipt"})
	waiting_save = ""
	waiting_operation = {}
	operation_index += 1

func on_snapshot_source(request: Dictionary, world: WorldState) -> void:
	var begin: int = Time.get_ticks_usec()
	var required: Dictionary = config.get("required_session",{}) if world.hospital_id==initial_hospital_id else {}
	var witness: Dictionary = SnapshotWitness.capture(world,required)
	var snapshot_id: String = str(request.snapshot_id)
	var identity: bool = witness.hospital_id==request.hospital_id and witness.sim_tick==request.sim_tick and witness.world_revision==request.world_revision
	snapshot_sources[snapshot_id] = {"witness":witness,"identity_matches_request":identity,"request":request.duplicate(true)}
	_emit("snapshot_source_witness", {"snapshot_id":snapshot_id,"request":request,"identity_matches_request":identity,"witness":witness,"observation_us":Time.get_ticks_usec()-begin,"scope":"identity/RNG plus named clinical owner only; whole canonical payload verified by original loader"})
	if not identity: _fail("Snapshot source witness differs from the original freeze request identity")

func on_snapshot_loaded(result: Dictionary) -> void:
	var begin: int = Time.get_ticks_usec()
	var manifest: Dictionary = result.get("manifest",{})
	var snapshot_id: String = str(manifest.get("snapshot_id",""))
	var source: Dictionary = snapshot_sources.get(snapshot_id,{})
	var check: Dictionary = {"snapshot_id":snapshot_id,"hospital_id":manifest.get("hospital_id",""),"source_witness_present":not source.is_empty(),"original_payload_hash_verified":bool(result.get("ok",false)),"verified":false}
	if not source.is_empty():
		var actual: Dictionary = SnapshotWitness.capture(result.world,source.witness.required_session)
		check.verified = bool(source.identity_matches_request) and actual==source.witness and str(manifest.hospital_id)==str(source.request.hospital_id) and int(manifest.sim_tick)==int(source.request.sim_tick) and int(manifest.world_revision)==int(source.request.world_revision)
		check.source_tick = source.request.sim_tick
		check.loaded_tick = result.world.sim_tick
		check.rng_and_named_clinical_equal = actual==source.witness
	check.observation_us = Time.get_ticks_usec()-begin
	loaded_snapshot_checks[str(check.hospital_id)] = check
	_emit("snapshot_loaded_witness",check)
	if not source.is_empty() and not bool(check.verified): _fail("Original loaded snapshot differs from its captured identity/RNG/clinical witness")

func _operations_complete() -> bool:
	return operation_index>=config.get("operations", []).size() and waiting_save.is_empty() and (operation_driver==null or not operation_driver.active())

func _end_capture() -> void:
	var resources: Dictionary = app._view.resource_usage()
	if not resources.errors.is_empty():
		_fail("View resource error before capture end")
		return
	if int(resources.pending_bindings)>0 or int(resources.retiring_nodes)>0: return
	if not _clock_bracket("before_capture_end"): return
	capture_end_us = Time.get_ticks_usec()
	capture_end_tick = app._simulation.world.sim_tick
	if dense_open:
		_emit("dense_segment_end", {"segment":dense_index,"reason":"capture_end"}, capture_end_us)
		dense_open = false
	phase = "stopped"
	stop_requested = false
	_emit("capture_end", {"tick":capture_end_tick,"start_tick":capture_begin_tick,"start_session":capture_begin_session,"end_session":app._session.loading_session_id,"start_engine_us":capture_begin_us,"end_engine_us":capture_end_us,"completed_steps":capture_steps,"tick_delta":capture_end_tick-capture_begin_tick if capture_begin_session==app._session.loading_session_id else null,"real_seconds":float(capture_end_us-capture_begin_us)/1000000.0,"requested_speed":config.speed,"effective_real_time_requires_pause_segment_audit":true,"presented_frames":"external_only","tail_complete":false}, capture_end_us)
	_ack("stopped")

func _finish(tail: Dictionary) -> void:
	if finishing: return
	phase = "finishing"
	tail_ack = tail.duplicate(true)
	_emit("tail_ack", {"external_tail_ack":tail,"capture_end_engine_us":capture_end_us})
	call_deferred("_finish_after_tail")

func _finish_after_tail() -> void:
	if not await _screenshot("after-tail"): return
	finishing = true

func on_root_released(guard_released: bool, quit_checkpoint_complete: bool) -> void:
	root_released = true
	if failure_reason.is_empty() and (not finishing or not quit_requested or not guard_released or not quit_checkpoint_complete):
		failure_reason = "Product root exited before acknowledged tail and normal checkpoint release"
		exit_code = 2
	if exit_code==0:
		_emit("scenario_complete", {"external_tail_ack":tail_ack,"completed_steps":capture_steps,"operations_complete":_operations_complete(),"engine_callbacks":engine_callbacks,"telemetry_lines_before_final":telemetry_lines,"telemetry_write_us":telemetry_write_us,"screenshots":screenshots,"profile":profile_path,"normal_quit_checkpoint_complete":quit_checkpoint_complete,"simulation_dispose_complete":true,"guard_released":guard_released,"performance_pass":null,"reason":"external presented samples, bounded clock join, density, resources and thresholds are evaluated by the report"})
	else:
		_emit("incomplete", {"reason":failure_reason,"phase":phase,"completed_steps":capture_steps,"guard_released":guard_released,"simulation_dispose_complete":true})
	_emit("exit", {"exit_code":exit_code,"capture_end_engine_us":capture_end_us})
	_flush()
	if stream!=null: stream.close()
	quit(exit_code)

func _settings() -> Dictionary:
	var window: Vector2i = DisplayServer.window_get_size()
	var scene: Vector2i = app._viewport.size
	var logical: Vector2 = app.get_viewport_rect().size
	var screen: Transform2D = app._world_container.get_viewport_transform()*app._world_container.get_global_transform()
	var physical: Vector2 = app._world_container.size*Vector2(screen.x.length(),screen.y.length())
	var scene_scale: float = app._viewport.scaling_3d_scale
	var expected_internal: Vector2i = Vector2i(roundi(physical.x*scene_scale/2.0)*2,roundi(physical.y*scene_scale/2.0)*2)
	var product: PackedFloat32Array = PackedFloat32Array([float(scene.x)*scene_scale,float(scene.y)*scene_scale])
	var predicted_internal: Vector2i = Vector2i(floori(product[0]),floori(product[1]))
	var output_matches: bool = absf(float(scene.x)-physical.x)<3.001 and absf(float(scene.y)-physical.y)<3.001 and predicted_internal==expected_internal
	# ViewportTexture.get_size multiplies Window's already physical viewport
	# size by stretch again in this engine. Only a real image establishes raster.
	var root_texture_declared: Vector2i = Vector2i(root.get_texture().get_size())
	var root_texture: Vector2i = root_readback_pixels
	var scene_texture: Vector2i = Vector2i(app._viewport.get_texture().get_size())
	var root_stretch: Transform2D = root.get_stretch_transform()
	var root_physical: Vector2i = Vector2i((logical*Vector2(root_stretch.x.length(),root_stretch.y.length())).ceil())
	return {"window_pixels":[window.x,window.y],"root_logical_extent":[logical.x,logical.y],"content_scale_size":[root.content_scale_size.x,root.content_scale_size.y],"content_scale_mode":root.content_scale_mode,"canvas_transform":str(app.get_global_transform_with_canvas()),"root_raster_texture_pixels":[root_texture.x,root_texture.y],"root_viewport_texture_declared_pixels":[root_texture_declared.x,root_texture_declared.y],"root_raster_source":"actual image readback outside formal window; zero until first screenshot","root_canvas_physical_extent":[root_physical.x,root_physical.y],"native_2d_output":root.content_scale_mode==Window.CONTENT_SCALE_MODE_CANVAS_ITEMS and root_texture==root_physical,"scene_control_logical_extent":[app._world_container.size.x,app._world_container.size.y],"scene_control_physical_extent":[physical.x,physical.y],"scene_control_screen_transform":str(screen),"scene_viewport_pixels":[scene.x,scene.y],"scene_output_texture_pixels":[scene_texture.x,scene_texture.y],"scene_output_matches_control":output_matches and scene_texture==scene,"scene_nearest_even_internal_pixels":[expected_internal.x,expected_internal.y],"scene_predicted_float32_internal_pixels":[predicted_internal.x,predicted_internal.y],"scene_output_rounding":"nearby native output extent yields nearest even internal 3D pixels; actual GPU corroboration is separate","scene_scale":app._viewport.scaling_3d_scale,"scene_allocated_pixels":"unavailable_without_actual_backend_corroboration","ui_scale_percent":app._ui_scale*100,"renderer":RenderingServer.get_current_rendering_method(),"render_driver":RenderingServer.get_current_rendering_driver_name(),"gpu":RenderingServer.get_video_adapter_name(),"refresh_hz":DisplayServer.screen_get_refresh_rate(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"observed_floor":app._observed_floor,"camera_size":app._view.camera.size,"camera_transform":str(app._view.camera.global_transform)}

func _ack(state: String) -> void:
	var sampled: Dictionary = _clock()
	var body: Dictionary = {"phase":state,"generation":generation,"engine_us":Time.get_ticks_usec(),"completed_steps":capture_steps,"operations_complete":_operations_complete(),"clock_domain":"windows_qpc","engine_clock_domain":"godot_ticks_usec","qpc_ticks":sampled.get("qpc_ticks"),"qpc_frequency":sampled.get("qpc_frequency"),"qpc_role":"ACK construction observation; engine_us read immediately afterwards","pid":OS.get_process_id()}
	for name: String in ["ready.json", "capture_ready.json"]:
		var file: FileAccess = FileAccess.open(output.path_join(name), FileAccess.WRITE)
		if file!=null:
			file.store_string(JSON.stringify(body))
			file.close()
	_emit("control_ack", body, int(body.engine_us), sampled)
	_flush()

func _clock() -> Dictionary:
	if clock_api==null or not clock_method_ready: return {"qpc_ticks":null,"qpc_frequency":null,"clock_error":"native clock unavailable"}
	return clock_api.read()

func _clock_bracket(reason: String) -> bool:
	var before: Dictionary = _clock()
	var engine: int = Time.get_ticks_usec()
	var after: Dictionary = _clock()
	var valid: bool = before.get("qpc_ticks")!=null and after.get("qpc_ticks")!=null and int(before.get("qpc_frequency", 0))==clock_frequency and int(after.get("qpc_frequency", 0))==clock_frequency and int(before.get("qpc_ticks", -1))<=int(after.get("qpc_ticks", -1))
	_emit("clock_sample", {"reason":reason,"engine_us":engine,"qpc_before_ticks":before.get("qpc_ticks"),"qpc_after_ticks":after.get("qpc_ticks"),"qpc_frequency":clock_frequency,"valid":valid,"qpc_role":"clock bracket end","mapping_contract":"engine sample lies between native raw QPC endpoints; no exact midpoint or drift bound invented"}, engine, after)
	last_clock_sample_us = engine
	if not valid: _fail("Native QPC/engine bracket invalid or frequency changed")
	return valid

func _emit(kind: String, details: Dictionary = {}, at_us: int = -1, supplied_clock: Dictionary = {}) -> void:
	var sampled: Dictionary = _clock() if supplied_clock.is_empty() else supplied_clock
	var observed_engine_us: int = Time.get_ticks_usec()
	var row: Dictionary = {"kind":kind,"engine_us":observed_engine_us if at_us<0 else at_us,"observation_engine_us":observed_engine_us,"qpc_ticks":sampled.get("qpc_ticks"),"qpc_frequency":sampled.get("qpc_frequency"),"clock_domain":"windows_qpc","engine_clock_domain":"godot_ticks_usec","qpc_role":"telemetry observation; not historical engine_us mapping","generation":generation}
	if sampled.has("clock_error"): row.clock_error = sampled.clock_error
	row.merge(details, true)
	buffer.append(JSON.stringify(row))
	telemetry_lines += 1

func _flush() -> void:
	if stream==null or buffer.is_empty(): return
	var begin: int = Time.get_ticks_usec()
	stream.store_string("\n".join(buffer)+"\n")
	stream.flush()
	buffer.clear()
	last_flush_us = Time.get_ticks_usec()
	telemetry_write_us += last_flush_us-begin

func _fail(reason: String) -> void:
	if not failure_reason.is_empty(): return
	failure_reason = reason
	exit_code = 2
	_emit("incomplete", {"reason":reason,"phase":phase,"completed_steps":capture_steps})
	if app==null:
		_emit("exit", {"exit_code":2})
	_flush()
	push_error(reason)
	quit(2)
