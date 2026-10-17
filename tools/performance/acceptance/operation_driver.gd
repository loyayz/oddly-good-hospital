extends RefCounted

# Scenario operations use original owners. Polling never advances simulation,
# completes work, edits actors, or changes a preparation worker's policy.
const ACTIONS: Array[String] = ["view_rebind","navigation_evict","wait_autosave","wait_boundary","seed_hospital","switch","remodel","command","playback","preview_input","cancel_build_preview"]
var app
var observer: Object
var current: Dictionary = {}
var state: Dictionary = {}
var begin_us: int = 0
var next_poll_us: int = 0
var preview_observer: Node
var save_receipts: Dictionary = {}
var completed_auto_receipts: Array[Dictionary] = []

func _init(root_app: Control, sink: Object) -> void:
	app = root_app
	observer = sink
	var script: Script = load(get_script().resource_path.get_base_dir().path_join("preview_input_observer.gd"))
	preview_observer = script.new()
	app.add_child(preview_observer)
	preview_observer.attach(app,observer)

func active() -> bool:
	return not current.is_empty()

func start(operation: Dictionary) -> Dictionary:
	current = operation.duplicate(true)
	state = {"hospital_session":app._session.loading_session_id,"hospital_id":app._simulation.world.hospital_id,"tick":app._simulation.world.sim_tick,"source_revision":app._simulation.world.revision}
	begin_us = Time.get_ticks_usec()
	next_poll_us = 0
	match str(current.action):
		"view_rebind":
			var view = app._view
			var camera_transform: Transform3D = view.camera.global_transform
			var camera_size: float = view.camera.size
			var target: Vector3 = view._camera_target
			var follow: String = view.follow_actor
			var selected: String = view._selected
			state.previous_generation = view.view_generation
			state.before_resources = view.resource_usage()
			view.bind(app._simulation.world,app._observed_floor,app._session.loading_session_id)
			if not view.bind_error.is_empty(): return _failure(view.bind_error)
			view.camera.global_transform = camera_transform
			view.camera.size = camera_size
			view._camera_target = target
			view.follow_actor = follow
			view._selected = selected
			state.generation = view.view_generation
			state.first_observation_after_callback = observer.engine_callbacks+1
			observer._emit("view_rebuild_started", {"operation":current,"old_generation":state.previous_generation,"new_generation":state.generation,"resources":state.before_resources,"fact_revision_before":state.source_revision,"kind_of_reclamation":"original bind/release_tree and current-view reconstruction"})
		"navigation_evict":
			var cache = app._simulation.space._navigation
			state.before_entries = cache._entries.size()
			state.before_charge = cache._charged+cache._query_charged
			cache._trim(0)
			state.after_entries = cache._entries.size()
			state.after_charge = cache._charged+cache._query_charged
			if int(state.after_entries)!=0 or int(state.after_charge)!=0: return _failure("Original navigation trim did not settle its accounting")
			state.minimum_tick = app._simulation.world.sim_tick+int(current.get("minimum_followup_steps",1))
			observer._emit("navigation_evicted", {"operation":current,"before_entries":state.before_entries,"after_entries":state.after_entries,"before_allowance_bytes":state.before_charge,"after_allowance_bytes":state.after_charge,"bytes_kind":"original eviction allowance; not measured allocation/residency","routes_and_reservations":"preserved"})
		"wait_autosave":
			state.after_engine_us = observer.capture_begin_us if bool(current.get("include_previous_in_capture",true)) else begin_us
		"wait_boundary":
			state.pending_seen = false
			state.intent_issued = false
			state.completed = false
			var target: int = int(current.get("target_executed_tick",-1))
			if target>=0 and app._simulation.world.sim_tick>target: return _failure("Named business boundary has already passed before operation start")
		"seed_hospital":
			var loaded: Dictionary = _read_world(str(current.get("input_path","")))
			if not loaded.ok: return _failure(loaded.error)
			if loaded.world.hospital_id==app._simulation.world.hospital_id: return _failure("Seed hospital must have a genuinely distinct original UUID")
			var started: Dictionary = app._library.call("create",loaded.world,HospitalSnapshots.uuid())
			if not started.get("ok",false): return _failure(str(started.get("error","Original library create failed")))
			state.request_id = str(started.request.request_id)
			state.target_hospital_id = loaded.world.hospital_id
			observer._emit("hospital_seed_started", {"operation":current,"request":started.request,"input_sha256":FileAccess.get_sha256(str(current.input_path))})
		"switch":
			if not app._drafts.is_empty(): return _failure("Resolve the original draft confirmation before a measured switch")
			var target: String = str(current.get("hospital_id",""))
			if not HospitalSnapshots.valid_uuid(target) or target==app._simulation.world.hospital_id: return _failure("Switch needs a distinct valid committed hospital UUID")
			app._library_action("continue",{"hospital_id":target,"snapshot_id":str(current.get("snapshot_id",""))})
			if app._leave_operation.is_empty(): return _failure("Original switch did not start")
			state.target_hospital_id = target
		"remodel":
			if not current.get("commands") is Array or current.commands.is_empty(): return _failure("Remodel requires original complete commands")
			if not _real_layout_change(current.commands): return _failure("Remodel must change actual geometry")
			if bool(current.get("require_view_loading",false)) and int(app._view.resource_usage().pending_bindings)==0: return _failure("Requested geometry-during-loading case has no actual pending view bindings")
			var prerequisite: String = _check_work_prerequisite(current.get("required_session",{}))
			if not prerequisite.is_empty(): return _failure(prerequisite)
			state.stage = "prepare"
			_submit("remodel_prepare",{"commands":current.commands,"safe_transfer":bool(current.get("safe_transfer",false))})
		"command":
			if bool(current.get("verify_failure_atomicity",false)):
				if app._session.actual_speed()!=0 or not app._simulation._commands.is_empty() or not app._simulation._command_boundary.is_empty(): return _failure("Whole-fact failure oracle needs an already paused complete empty-command boundary")
				state.facts_before = app._simulation.world.freeze()
			_submit(str(current.get("kind","")),current.get("payload",{}))
		"playback":
			app._set_speed(int(current.get("speed",observer.config.speed)))
			return _success({"requested_speed":app._session.requested_speed,"actual_speed":app._session.actual_speed(),"pause_reasons":app._session.pause_reasons()})
		"preview_input":
			return _begin_preview()
		"cancel_build_preview":
			app._build_panel.cancel_draft()
			return _success({"original_preview_cancelled":true})
		_:
			return _failure("Unsupported operation")
	return {"pending":true}

func poll(now: int) -> Dictionary:
	if not active(): return {}
	if float(now-begin_us)/1000000.0>float(current.get("timeout_real_seconds",600)): return _failure("Operation timed out with original work/owners preserved")
	if str(current.action)=="wait_boundary": return _poll_boundary()
	if str(current.action)=="preview_input": return _poll_preview()
	if not observer._business_boundary_ready(): return {"pending":true}
	if str(current.action)!="switch" and str(current.action)!="seed_hospital" and app._session.loading_session_id!=str(state.hospital_session): return _failure("Operation source hospital/session changed")
	match str(current.action):
		"view_rebind":
			var usage: Dictionary = app._view.resource_usage()
			if not usage.errors.is_empty(): return _failure("View resource rebuild failed")
			if app._view.view_generation!=int(state.generation): return _failure("View generation changed during current-view rebuild")
			if observer.engine_callbacks>=int(state.first_observation_after_callback) and int(usage.pending_bindings)==0 and int(usage.retiring_nodes)==0:
				return _success({"previous_generation":state.previous_generation,"generation":state.generation,"resources_before":state.before_resources,"resources_after":usage,"displayed_endpoint":"external first correct frame still required"})
		"navigation_evict":
			if app._simulation.world.sim_tick>=int(state.minimum_tick):
				return _success({"before_entries":state.before_entries,"after_trim_entries":state.after_entries,"followup_entries":app._simulation.space._navigation._entries.size(),"actual_followup_steps":app._simulation.world.sim_tick-int(state.tick),"business_result_evidence":"original routes/work/receipts retained; scenario-specific arrival/charge assertions required"})
		"wait_autosave":
			for item: Dictionary in completed_auto_receipts:
				if int(item.observed_engine_us)>=int(state.after_engine_us): return _success({"autosave":item})
		"seed_hospital":
			if save_receipts.has(state.request_id):
				var receipt: Dictionary = save_receipts[state.request_id]
				if not receipt.get("ok",false): return _failure("Original hospital creation save failed")
				return _success({"receipt":receipt,"hospital_id":state.target_hospital_id})
		"switch":
			if app._simulation.world.hospital_id==str(state.target_hospital_id) and app._session.loading_session_id!=str(state.hospital_session):
				if bool(current.get("expect_failure",false)): return _failure("Expected failed load published a target hospital")
				var usage: Dictionary = app._view.resource_usage()
				if int(usage.pending_bindings)>0: return {"pending":true}
				if not usage.errors.is_empty(): return _failure("Target view resource load failed")
				var paused: bool = app._session.requested_speed==0 and app._session.actual_speed()==0
				if not paused: return _failure("Original switch did not preserve paused playback")
				if current.has("resume_speed"): app._set_speed(int(current.resume_speed))
				return _success({"hospital_id":app._simulation.world.hospital_id,"hospital_session":app._session.loading_session_id,"tick":app._simulation.world.sim_tick,"original_paused_after_load":paused,"resources":usage,"displayed_endpoint":"external first correct target frame still required"})
			if app._leave_operation.is_empty():
				if bool(current.get("expect_failure",false)) and app._session.loading_session_id==str(state.hospital_session) and app._session.requested_speed==0:
					return _success({"expected_failed_load":true,"source_session_preserved":true,"source_hospital_id":state.hospital_id,"error_text":app._status.text})
				return _failure("Original target load failed: "+app._status.text)
		"remodel":
			return _poll_remodel(now)
		"command":
			var receipt: Dictionary = app._simulation.receipt(str(state.command_id))
			if receipt.is_empty(): return {"pending":true}
			if bool(receipt.accepted)!=bool(current.get("expected_accepted",true)): return _failure("Original command outcome differs from scenario: "+JSON.stringify(receipt))
			if state.has("facts_before") and state.facts_before!=app._simulation.world.freeze(): return _failure("Rejected command changed world facts on the paused oracle boundary")
			return _success({"receipt":receipt,"failure_atomicity_checked":state.has("facts_before")})
	return {"pending":true}

func on_receipt(receipt: Dictionary) -> void:
	save_receipts[str(receipt.get("request_id",""))] = receipt.duplicate(true)
	if str(receipt.get("slot_kind",""))=="auto":
		completed_auto_receipts.append({"receipt":receipt.duplicate(true),"observed_engine_us":Time.get_ticks_usec()})

func on_tick(result: RefCounted) -> void:
	if not active() or str(current.action)!="wait_boundary": return
	var executed: int = int(result.sim_tick)-1
	var hit: bool = executed==int(current.get("target_executed_tick",-1))
	for event: RefCounted in result.facts:
		if str(current.get("boundary","day"))=="day" and event.kind=="arrival_day_planned":
			if not current.has("target_day_index") or int(event.details.get("day_index",-1))==int(current.target_day_index): hit = true
	if str(current.get("boundary","day"))=="shift" and not current.has("target_executed_tick"):
		var ticks: int = ceili(float(app._content.balance.schedule.shift_seconds)/float(app._simulation.world.TICK_SECONDS))
		hit = executed%ticks==0
	if hit:
		state.completed = true
		state.executed_tick = executed
		state.completed_tick = result.sim_tick
		state.original_started_engine_us = result.started_engine_us
		state.original_completed_engine_us = result.completed_engine_us
		state.original_elapsed_us = result.elapsed_us

func _poll_boundary() -> Dictionary:
	if app._session.loading_session_id!=str(state.hospital_session): return _failure("Boundary source session changed")
	if app._simulation.step_in_progress():
		state.pending_seen = true
		if not bool(state.intent_issued) and str(current.get("pending_intent","")) in ["pause","save"]:
			state.intent_issued = true
			if str(current.pending_intent)=="pause": app._set_speed(0)
			else:
				var started: Dictionary = app._begin_save("manual","boundary-"+str(current.id))
				if not started.get("ok",false): return _failure("Original save intent did not start during preparation wait")
				state.request_id = str(started.request.request_id)
			observer._emit("boundary_wait_intent", {"operation":current,"original_started_engine_us":app._simulation._step_context.get("started_us"),"pending":true,"requested_speed":app._session.requested_speed})
	if not bool(state.completed):
		if current.has("target_executed_tick") and app._simulation.world.sim_tick>int(current.target_executed_tick): return _failure("Named boundary passed without its actual completion observation")
		return {"pending":true}
	if bool(current.get("require_pending",false)) and not bool(state.pending_seen): return _failure("Boundary completed without an actual pending wait; wait case remains uncovered")
	if current.has("pending_intent") and not bool(state.intent_issued): return _failure("Required intent was not issued during the real wait")
	if state.has("request_id") and not save_receipts.has(state.request_id): return {"pending":true}
	if state.has("request_id") and not bool(save_receipts[state.request_id].get("ok",false)): return _failure("Boundary save failed")
	if not observer._business_boundary_ready(): return {"pending":true}
	if str(current.get("pending_intent",""))=="pause" and current.has("resume_speed"): app._set_speed(int(current.resume_speed))
	return _success(state.duplicate(true))

func _poll_remodel(now: int) -> Dictionary:
	var world: WorldState = app._simulation.world
	if str(state.stage)=="prepare":
		var receipt: Dictionary = app._simulation.receipt(str(state.command_id))
		if receipt.is_empty(): return {"pending":true}
		if not receipt.accepted or receipt.changed_ids.is_empty(): return _failure("Original remodel prepare rejected: "+JSON.stringify(receipt))
		state.prepare_receipt = receipt
		state.order_id = str(receipt.changed_ids[0])
		state.stage = "waiting"
	if str(state.stage)=="waiting":
		if now<next_poll_us: return {"pending":true}
		next_poll_us = now+100000
		var order: Dictionary = world.facts.remodels.get(str(state.order_id),{})
		if order.is_empty() or order.state!="preparing": return _failure("Original preparing remodel owner changed")
		var waiting: String = app._simulation.services.remodel._waiting(world,order)
		if str(state.get("waiting_reason",""))!=waiting:
			state.waiting_reason = waiting
			observer._emit("remodel_waiting", {"operation":current,"order_id":state.order_id,"reason":waiting,"tick":world.sim_tick})
		if not waiting.is_empty(): return {"pending":true}
		var plan: Dictionary = app._simulation.services.remodel.preview(world,str(state.order_id))
		if not plan.get("ok",false): return _failure("Current complete remodel preview rejected: "+str(plan.get("reason","")))
		state.quote = {"price":plan.price,"refund":plan.refund,"layout":plan.layout.duplicate(true)}
		observer._emit("remodel_quote", {"operation":current,"order_id":state.order_id,"quote":state.quote,"tick":world.sim_tick,"confirmation":"scenario authorizes this exact freshly observed quote once"})
		state.stage = "apply"
		_submit("remodel_apply",{"order_id":state.order_id,"quote":state.quote})
		return {"pending":true}
	var applied: Dictionary = app._simulation.receipt(str(state.command_id))
	if applied.is_empty(): return {"pending":true}
	if not applied.accepted: return _failure("Original remodel apply rejected; no automatic re-quote/retry: "+JSON.stringify(applied))
	var committed: Dictionary = world.facts.remodels.get(str(state.order_id),{})
	var entry: Dictionary = world.facts.ledger.entries.get(str(state.order_id)+":remodel",{})
	if committed.get("state","")!="applied" or entry.is_empty() or int(entry.amount)!=int(state.quote.refund)-int(state.quote.price): return _failure("Remodel final state/ledger does not match the original exact quote")
	return _success({"prepare_receipt":state.prepare_receipt,"apply_receipt":applied,"order_id":state.order_id,"quote":state.quote,"ledger_entry":entry,"actual_tick":world.sim_tick})

func _submit(kind: String, payload: Dictionary) -> void:
	var command: Dictionary = payload.duplicate(true)
	state.command_id = HospitalSnapshots.uuid()
	command.command_id = state.command_id
	observer._emit("business_command_submitted", {"operation":current,"command_id":state.command_id,"kind":kind,"payload":command,"hospital_session":app._session.loading_session_id,"expected_revision":app._simulation.world.revision})
	app._submit_business(kind,command)

func _read_world(path: String) -> Dictionary:
	if not path.is_absolute_path(): return {"ok":false,"error":"Hospital seed input path must be absolute"}
	var file: FileAccess = FileAccess.open(path,FileAccess.READ)
	if file==null: return {"ok":false,"error":"Hospital seed input unavailable"}
	var saved: Variant = file.get_var(false)
	file.close()
	if not saved is Dictionary or not saved.get("facts") is Dictionary or str(saved.get("content_fingerprint",""))!=app._content.content_fingerprint: return {"ok":false,"error":"Hospital seed input envelope/content mismatch"}
	var world: WorldState = WorldState.new(saved.facts)
	var reason: String = world.validate(app._content)
	return {"ok":reason.is_empty(),"error":reason,"world":world}

func _real_layout_change(commands: Array) -> bool:
	for command: Variant in commands:
		if not command is Dictionary: return false
		var id: String = str(command.get("target_id",""))
		var original: Dictionary = app._simulation.world.facts.rooms.get(id,app._simulation.world.facts.facilities.get(id,{}))
		if str(command.get("kind",""))=="build_door":
			var found: Dictionary = app._simulation.services.building._door(app._simulation.world,id)
			if found.is_empty(): return false
			var room: Dictionary = app._simulation.world.facts.rooms[found.door.room_id]
			var edge: String = str(command.get("edge","south"))
			var axis: String = "x" if edge in ["north","south"] else "y"
			var offset: int = int(command.get("offset",1))
			var cell: Array = command.get("cell",[int(room.origin[0])+(offset if axis=="x" else int(room.size[0]) if edge=="east" else 0),int(room.origin[1])+(offset if axis=="y" else int(room.size[1]) if edge=="south" else 0)])
			if str(command.get("definition_id","DR01"))!=str(found.door.definition_id) or axis!=str(found.door.axis) or cell!=found.door.cell: return true
			continue
		if original.is_empty(): return false
		if str(command.get("kind",""))=="build_demolish": return true
		if int(command.get("turns",0))%4!=0: return true
		if int(command.get("floor_id",original.floor_id))!=int(original.floor_id): return true
		if command.has("size") and command.size!=original.get("size",original.get("footprint",[])): return true
		if command.get("origin",command.get("cell",original.get("origin",original.get("cell",[]))))!=original.get("origin",original.get("cell",[])): return true
	return false

func _check_work_prerequisite(required: Dictionary) -> String:
	if required.is_empty(): return ""
	var session: Dictionary = app._simulation.world.facts.sessions.get(str(required.get("id","")),{})
	if session.is_empty(): return "Named real clinical session no longer exists"
	if int(session.get("remaining_ticks",0))<=0 or int(session.get("remaining_ticks",0))>=int(session.get("total_ticks",0)): return "Named clinical work is not actually in progress"
	for key: String in ["visit_id","facility_id"]:
		if required.has(key) and session.get(key)!=required[key]: return "Named clinical work owner changed"
	return ""

func _begin_preview() -> Dictionary:
	app._show_panel("building")
	var panel = app._build_panel
	if not _select(panel._mode,"build_room"): return _failure("Original build-room mode unavailable")
	panel._populate()
	if not _select(panel._definition,str(current.get("room_type_id",""))) or not _select(panel._door,str(current.get("door_id",""))): return _failure("Original room/door definition unavailable")
	var origin: Array = current.get("origin",[])
	var size: Array = current.get("size",[])
	if origin.size()!=2 or size.size()!=2: return _failure("Preview needs original origin and full size")
	panel._x.value = int(origin[0])
	panel._y.value = int(origin[1])
	panel._width.value = int(size[0])
	panel._height.value = int(size[1])
	var measured: SpinBox = panel._height if str(current.get("field","width"))=="height" else panel._width
	state.field = "height" if measured==panel._height else "width"
	state.value = int(size[1]) if state.field=="height" else int(size[0])
	var initial: int = int(current.get("initial_value",4))
	if initial==int(state.value): return _failure("Measured original input must change the requested dimension")
	measured.value = initial
	panel._request()
	app._management_scroll.ensure_control_visible(measured)
	state.stage = "prepare_input"
	state.ready_after_frame = observer.engine_callbacks+2
	return {"pending":true}

func _poll_preview() -> Dictionary:
	if app._session.loading_session_id!=str(state.hospital_session): return _failure("Preview source hospital/session changed")
	if str(state.stage)=="prepare_input":
		if observer.engine_callbacks<int(state.ready_after_frame): return {"pending":true}
		var measured: SpinBox = app._build_panel._height if state.field=="height" else app._build_panel._width
		var field: LineEdit = measured.get_line_edit()
		var point: Vector2 = field.get_screen_transform()*(field.size*0.5)
		var armed: Dictionary = current.duplicate(true)
		armed.expected_draft = {"kind":"build_room","floor_id":app._observed_floor,"origin":current.origin,"size":current.size,"room_type_id":current.room_type_id}
		preview_observer.arm(armed)
		var request: Dictionary = {"id":str(current.id),"status":"armed","pid":OS.get_process_id(),"hospital_session":app._session.loading_session_id,"fields":[{"name":state.field,"screen_point":[point.x,point.y],"text":str(state.value)}],"coordinate_source":"CanvasItem.get_screen_transform local LineEdit center; external owned-PID/client rectangle verification required","expected_draft":armed.expected_draft}
		if not _write_json("input-request.json",request): return _failure("Cannot publish external real-input request")
		observer._emit("input_request", request)
		state.stage = "wait_input"
	var ack_path: String = observer.output.path_join("input-ack.json")
	if FileAccess.file_exists(ack_path):
		var ack: Variant = JSON.parse_string(FileAccess.get_file_as_string(ack_path))
		if ack is Dictionary and str(ack.get("id",""))==str(current.id):
			if not bool(ack.get("ok",false)): return _failure("External real input failed: "+str(ack.get("error","")))
			state.input_ack = ack
	if preview_observer.completed.is_empty(): return {"pending":true}
	if not state.has("input_ack"): return {"pending":true}
	if not bool(preview_observer.completed.get("expected_outcome_matches",false)): return _failure("Complete original preview outcome differs from scenario")
	var completed: Dictionary = preview_observer.completed.duplicate(true)
	if bool(current.get("cancel_after",true)): app._build_panel.cancel_draft()
	return _success({"preview":completed,"input_ack":state.input_ack,"displayed_endpoint":"external next actual correct frame still required"})

func _select(picker: OptionButton, value: String) -> bool:
	for index: int in picker.item_count:
		if str(picker.get_item_metadata(index))==value:
			picker.select(index)
			return true
	return false

func _write_json(name: String, value: Dictionary) -> bool:
	var path: String = observer.output.path_join(name)
	var temporary: String = path+".tmp"
	var file: FileAccess = FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: return false
	file.store_string(JSON.stringify(value))
	file.close()
	return DirAccess.rename_absolute(temporary,path)==OK

func _success(details: Dictionary) -> Dictionary:
	var result: Dictionary = {"ok":true,"complete":true,"details":details}
	current = {}
	state = {}
	return result

func _failure(reason: String) -> Dictionary:
	var detail: Dictionary = state.duplicate()
	if detail.has("facts_before"):
		detail.erase("facts_before")
		detail.failure_oracle_snapshot_retained = true
	return {"ok":false,"complete":true,"error":reason,"operation":current.duplicate(true),"state":detail}
