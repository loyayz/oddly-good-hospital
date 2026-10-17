extends Node

# Observation only. The controller sends real OS input to original controls.
# Connect after AppRoot's own preview connection so its overlay is updated first.
var app
var observer: Object
var armed: Dictionary = {}
var input_sequence: int = 0
var inputs: Dictionary = {}
var generation_inputs: Dictionary = {}
var observed_generation: int = -1
var operation_first_input_us: int = 0
var partial_phases: Dictionary = {}
var armed_session: String = ""
var armed_world: int = 0
var completed: Dictionary = {}

func attach(root_app: Control, sink: Object) -> void:
	app = root_app
	observer = sink
	app._build_panel.preview_changed.connect(_preview_changed)

func arm(operation: Dictionary) -> void:
	armed = operation.duplicate(true)
	completed = {}
	inputs.clear()
	generation_inputs.clear()
	partial_phases.clear()
	operation_first_input_us = 0
	armed_session = app._session.loading_session_id
	armed_world = app._simulation.world.get_instance_id()
	observed_generation = app._build_panel._preview.generation
	_log("preview_armed", {"operation":armed,"hospital_session":app._session.loading_session_id,"world_instance":app._simulation.world.get_instance_id(),"initial_generation":observed_generation})

func _input(event: InputEvent) -> void:
	var input_clock: Dictionary = observer._clock() if observer!=null else {}
	var input_engine_us: int = Time.get_ticks_usec()
	if armed.is_empty() or not app._build_panel.is_visible_in_tree(): return
	if not _same_owner():
		_log("preview_cancelled", {"operation":armed,"reason":"hospital/session replaced"})
		armed = {}
		return
	var relevant: bool = false
	if event is InputEventKey:
		var focus: Control = get_viewport().gui_get_focus_owner()
		relevant = event.pressed and not event.echo and focus!=null and app._build_panel.is_ancestor_of(focus)
	elif event is InputEventMouseButton:
		relevant = event.button_index==MOUSE_BUTTON_LEFT and (app._world_container.get_global_rect().has_point(event.position) or app._build_panel.get_global_rect().has_point(event.position))
	elif event is InputEventMouseMotion:
		relevant = bool(event.button_mask&MOUSE_BUTTON_MASK_LEFT) and app._world_container.get_global_rect().has_point(event.position)
	if not relevant: return
	input_sequence += 1
	if operation_first_input_us==0: operation_first_input_us = input_engine_us
	var sequence: int = input_sequence
	inputs[sequence] = {"sequence":sequence,"input_engine_us":input_engine_us,"input_qpc_ticks":input_clock.get("qpc_ticks"),"qpc_frequency":input_clock.get("qpc_frequency"),"qpc_role":"actual input callback entry; external send remains a separate event","event_instance":event.get_instance_id(),"event_class":event.get_class(),"event_text":event.as_text(),"session":app._session.loading_session_id,"world_instance":app._simulation.world.get_instance_id(),"generation_before":app._build_panel._preview.generation}
	_log("preview_input", inputs[sequence], input_engine_us, input_clock)
	call_deferred("_after_input", sequence)

func _after_input(sequence: int) -> void:
	if not inputs.has(sequence) or armed.is_empty(): return
	var request: Dictionary = inputs[sequence]
	if request.session!=app._session.loading_session_id or request.world_instance!=app._simulation.world.get_instance_id():
		_log("preview_input_discarded", {"sequence":sequence,"reason":"hospital changed before request observation"})
		return
	var generation: int = app._build_panel._preview.generation
	if generation!=observed_generation:
		if generation_inputs.has(observed_generation):
			_log("preview_superseded", {"generation":observed_generation,"successor_generation":generation,"inputs":generation_inputs[observed_generation],"elapsed_until_successor_us":Time.get_ticks_usec()-_first_input_us(observed_generation)})
		observed_generation = generation
	if not generation_inputs.has(generation): generation_inputs[generation] = []
	generation_inputs[generation].append(sequence)
	_log("preview_request_observed", {"sequence":sequence,"generation":generation,"draft":app._build_panel._draft,"request_change":generation!=int(request.generation_before),"observation_kind":"after input dispatch; no request start timestamp invented"})
	var job = app._build_panel._preview.job
	if job!=null and job.complete:
		_preview_changed(app._build_panel._draft, app._build_panel._result, "terminal result read after input dispatch; conservative observation endpoint")

func _preview_changed(draft: Dictionary, result: Dictionary, endpoint: String = "complete original result plus synchronous AppRoot overlay callback; displayed endpoint requires external trace") -> void:
	var result_clock: Dictionary = observer._clock()
	var now: int = Time.get_ticks_usec()
	if armed.is_empty(): return
	if not _same_owner():
		_log("preview_cancelled", {"operation":armed,"reason":"hospital/session replaced"})
		armed = {}
		return
	if draft.is_empty():
		_log("preview_cancelled", {"operation":armed,"pending_inputs":inputs.keys()}, now)
		armed = {}
		return
	var generation: int = int(result.get("generation", -1))
	if not generation_inputs.has(generation): return
	var binding: Dictionary = result.get("binding", {})
	if str(binding.get("loading_session_id", ""))!=app._session.loading_session_id: return
	if not bool(result.get("draw_on_current_floor",true)):
		_log("preview_cancelled", {"operation":armed,"reason":"completed draft belongs to another observed floor; no displayed endpoint"}, now)
		armed = {}
		return
	var job = app._build_panel._preview.job
	var terminal: bool = bool(result.get("ready", false)) or job!=null and job.complete
	if not terminal:
		var request_phase: String = str(result.get("phase", ""))
		if partial_phases.get(generation)!=request_phase:
			_log("preview_partial_feedback", {"generation":generation,"ready":false,"phase":request_phase,"inputs":generation_inputs[generation]}, now)
			partial_phases[generation] = request_phase
		return
	var first_us: int = _first_input_us(generation)
	var last_us: int = first_us
	for sequence: int in generation_inputs[generation]: last_us = maxi(last_us, int(inputs[sequence].input_engine_us))
	var expected: Dictionary = armed.get("expected_draft", {})
	var matches: bool = true
	for key: String in expected:
		if draft.get(key)!=expected[key]: matches = false
	_log("preview_complete", {"operation":armed,"generation":generation,"draft":draft,"ok":result.get("ok", false),"reason":result.get("reason", ""),"inputs":generation_inputs[generation],"first_input_engine_us":first_us,"last_input_engine_us":last_us,"first_input_to_result_us":now-first_us,"last_input_to_result_us":now-last_us,"expected_draft_matches":matches,"atomic_overruns":result.get("atomic_overruns", 0),"units_checked":result.get("units_checked", 0),"endpoint":endpoint,"qpc_role":"complete preview callback entry after original overlay callback"}, now, result_clock)
	# One completion per request generation; repeated panel emissions do not add samples.
	generation_inputs.erase(generation)
	if matches:
		completed = {"operation_id":armed.get("id", ""),"generation":generation,"first_input_to_result_us":now-first_us,"operation_first_input_us":operation_first_input_us,"operation_input_to_target_result_us":now-operation_first_input_us,"ok":result.get("ok", false),"expected_outcome_matches":bool(result.get("ok", false))==bool(armed.get("expected_ok", true)),"qpc_role":"same complete preview callback entry","completion_qpc_ticks":result_clock.get("qpc_ticks"),"qpc_frequency":result_clock.get("qpc_frequency")}
		_log("preview_target_complete", completed, now, result_clock)
		armed = {}

func _first_input_us(generation: int) -> int:
	var result: int = Time.get_ticks_usec()
	for sequence: int in generation_inputs.get(generation, []): result = mini(result, int(inputs[sequence].input_engine_us))
	return result

func _same_owner() -> bool:
	return app._session.loading_session_id==armed_session and app._simulation.world.get_instance_id()==armed_world

func _log(kind: String, data: Dictionary, now: int = -1, sampled_clock: Dictionary = {}) -> void:
	observer._emit(kind, data, now, sampled_clock)
