extends "res://tests/acceptance/floor_guidance.gd"

func run_desk_cases(database: HospitalContent, selected: Array = []) -> Dictionary:
	_content = database
	var runs: Dictionary = {"GUIDE-LIFE-CHANGE-DESK":_life_change_desk,"GUIDE-LIFE-CLOSED-DESK":_life_change_desk.bind(true),"GUIDE-LIFE-CHANGE-DESK-JSON":_life_change_desk.bind(false,true),"GUIDE-DESK-SAVE-OWNERSHIP":_desk_save_ownership,"GUIDE-DESK-STAFF-PAUSE":_desk_staff_pause,"GUIDE-DESK-CLOSE-ACTIVE":_desk_close_active}
	var rows: Array = []
	for id: String in (runs.keys() if selected.is_empty() else selected):
		if not runs.has(id): return {"ok":false,"error":"unknown case "+id}
		rows.append(runs[id].call())
	return {"ok":not rows.any(func(row: Dictionary)->bool:return not row.get("ok",false)),"cases":rows}

func _life_change_desk(close_desk: bool = false, save_return: bool = false) -> Dictionary:
	var x: Dictionary = _base()
	x.world.facts.staff.guide_nurse.on_shift = false
	_facility(x,"water","FUR17",[54,89])
	x.m.ensure(x.world)
	x.world.touch()
	var visit: Dictionary = _visit(x,"returning",[40,88])
	var ticket_id: String = visit.ticket_id
	var input_validation: String = x.world.validate(_content)
	for tick: int in 600:
		_step(x)
		if x.g.state(x.world,visit.id).get("phase","")=="desk_queue": break
	var old: Dictionary = x.g.state(x.world,visit.id).duplicate(true)
	var clock: Dictionary = x.world.facts.waiting_life.clocks[visit.id]
	clock.next_purpose = "water";clock.next_need_tick = x.world.sim_tick
	x.world.touch(false)
	var using_actual: bool = true
	var using_ticks: int = 0
	var changed: bool = false
	var build: BuildService = BuildService.new(_content,x.space)
	var remodel: HospitalRemodel = HospitalRemodel.new(_content,x.space)
	remodel.services = {"building":build}
	var restored: bool = not save_return
	var removal: Dictionary = {}
	var creation: Dictionary = {}
	var other: Dictionary = {}
	var other_seq: int = -1
	var switch_state: Dictionary = {}
	var switch_before_arrival: bool = false
	var old_privilege_cleared: bool = true
	var new_point_local: bool = true
	var no_remote_new_priority: bool = true
	var returned: bool = false
	var evidence: Array = []
	for tick: int in 1200:
		_step(x)
		var need: Dictionary = x.world.facts.waiting_life.needs.get(visit.id,{})
		var current: Dictionary = x.g.state(x.world,visit.id)
		if need.get("phase","")=="using":
			using_ticks += 1
			var layout: Dictionary = x.space.facility_layout(x.world,"water")
			using_actual = using_actual and need.facility_id=="water" and x.space.at(x.world,visit.actor_id,1,layout.patient_cell) and not x.world.facts.moves.has(visit.actor_id)
			if not changed:
				removal = remodel.execute(x.world,"remodel_prepare",{"commands":[{"kind":"build_move","target_id":"guide","cell":[47,81],"floor_id":1}]}).to_record() if close_desk else build.execute(x.world,"build_demolish",{"target_id":"guide"}).to_record()
				creation = build.execute(x.world,"build_facility",{"id":"guide_b","definition_id":"SE01","cell":[55,83],"floor_id":1}).to_record()
				other = _visit(x,"already_at_b",[58,86])
				changed = true
		if not other.is_empty(): other_seq = int(x.g.state(x.world,other.id).get("queue_seq",-1))
		if current.get("desk_id","")=="guide_b":
			if switch_state.is_empty():
				switch_state = current.duplicate(true)
				switch_before_arrival = not x.g.scope.allows(x.world,visit.actor_id,"guide_b",1,x.world.facts.actors[visit.actor_id].location.cell)
				if save_return:
					x = _restore_json(x)
					if x.has("restore_error"): return {"case":"GUIDE-LIFE-CHANGE-DESK-JSON","ok":false,"error":x.restore_error}
					restored = x.restore_ok
					visit = x.world.facts.visits.returning
					other = x.world.facts.visits.already_at_b
					current = x.g.state(x.world,visit.id)
					need = x.world.facts.waiting_life.needs.get(visit.id,{})
			old_privilege_cleared = old_privilege_cleared and int(current.get("queue_seq",-1))!=int(old.get("queue_seq",-2))
			if current.has("queue_cell"): new_point_local = new_point_local and x.g.scope.allows(x.world,visit.actor_id,"guide_b",1,current.queue_cell)
			if current.has("queue_seq"): no_remote_new_priority = no_remote_new_priority and current.has("queue_cell") and x.space.at(x.world,visit.actor_id,1,current.queue_cell) and not x.world.facts.moves.has(visit.actor_id)
		if evidence.is_empty() or evidence.back().need!=need.get("phase","") or evidence.back().desk!=current.get("desk_id",""):
			evidence.append({"tick":x.world.sim_tick,"need":need.get("phase",""),"desk":current.get("desk_id",""),"seq":current.get("queue_seq",-1),"location":x.world.facts.actors[visit.actor_id].location.duplicate(true)})
		if changed and need.is_empty() and current.get("phase","")=="desk_queue" and current.get("desk_id","")=="guide_b" and not x.world.facts.moves.has(visit.actor_id): returned = true;break
	var final: Dictionary = x.g.state(x.world,visit.id).duplicate(true)
	var actual_new_arrival: bool = final.has("queue_cell") and x.space.at(x.world,visit.actor_id,1,final.queue_cell) and x.g.scope.allows(x.world,visit.actor_id,"guide_b",1,final.queue_cell)
	var correct_order: bool = other_seq>int(old.get("queue_seq",-1)) and int(final.get("queue_seq",-1))>other_seq
	var row: Dictionary = {"case":"GUIDE-LIFE-CHANGE-DESK-JSON" if save_return else ("GUIDE-LIFE-CLOSED-DESK" if close_desk else "GUIDE-LIFE-CHANGE-DESK"),"json_new_instance":restored,"ok":restored and input_validation.is_empty() and old.get("phase","")=="desk_queue" and removal.get("accepted",false) and creation.get("accepted",false) and using_actual and using_ticks>=79 and returned and switch_before_arrival and old_privilege_cleared and new_point_local and no_remote_new_priority and actual_new_arrival and correct_order and visit.ticket_id==ticket_id and x.world.validate(_content).is_empty(),"input_validation":input_validation,"old_state":old,"removal":removal,"creation":creation,"actual_water_use":using_actual,"using_ticks":using_ticks,"switch_before_new_desk_arrival":switch_before_arrival,"switch_state":switch_state,"old_privilege_cleared":old_privilege_cleared,"new_point_local":new_point_local,"no_remote_new_priority":no_remote_new_priority,"actual_new_arrival":actual_new_arrival,"other_seq":other_seq,"correct_new_queue_order":correct_order,"returned":returned,"same_clinical_ticket":visit.ticket_id==ticket_id,"final":final,"trace":evidence,"validation":x.world.validate(_content)}
	_dispose(x);return row

func _rejects_unchanged(world: WorldState) -> bool:
	var frozen: Dictionary = world.freeze()
	return not world.validate(_content).is_empty() and world.freeze()==frozen

func _desk_save_ownership() -> Dictionary:
	var x: Dictionary = _base()
	HospitalFactory._add_staff(x.world,"replacement","替班护士","nurse",[42,92],_content)
	for key: String in ["d","s","w","r","f","m"]: x[key].ensure(x.world)
	x.world.facts.staff.replacement.on_shift = false
	var first: Dictionary = _visit(x,"owner",[40,88])
	var other: Dictionary = {}
	for tick: int in 600:
		_step(x)
		if x.g.state(x.world,first.id).get("phase","")=="working": break
	other = _visit(x,"other",[58,90])
	var current: Dictionary = x.g.state(x.world,first.id)
	var checks: Dictionary = {"real_working_input":current.get("phase","")=="working" and x.world.validate(_content).is_empty()}
	if not checks.real_working_input:
		var row: Dictionary = {"case":"GUIDE-DESK-SAVE-OWNERSHIP","ok":false,"checks":checks,"validation":x.world.validate(_content)}
		_dispose(x);return row
	for kind: String in ["different_nurse","foreign_ticket","wrong_request","second_active_service","wrong_reservation_patient","wrong_reservation_staff","queue_other_desk"]:
		var candidate: WorldState = WorldState.new(x.world.freeze())
		var row: Dictionary = candidate.facts.floor_guidance.visits.owner
		match kind:
			"different_nurse": row.nurse_id = "replacement"
			"foreign_ticket": row.ticket_id = other.ticket_id;row.request_key = other.ticket_id+":gp"
			"wrong_request": row.request_key = row.ticket_id+":spectrum"
			"second_active_service":
				var second: Dictionary = row.duplicate(true)
				second.visit_id = other.id;second.ticket_id = other.ticket_id;second.request_key = other.ticket_id+":gp";second.erase("queue_seq")
				candidate.facts.floor_guidance.visits[other.id] = second
			"wrong_reservation_patient": candidate.facts.adaptations.guide.actor_id = other.actor_id
			"wrong_reservation_staff": candidate.facts.adaptations.guide.staff_ids = ["replacement"]
			"queue_other_desk": row.queue_desk_id = "foreign_desk"
		checks[kind] = _rejects_unchanged(candidate)
	# Older valid queues had no explicit queue_desk_id. Keep that save format
	# readable; the actual desk/visit/ticket/reservation checks still apply.
	var legacy: WorldState = WorldState.new(x.world.freeze())
	for row: Dictionary in legacy.facts.floor_guidance.visits.values(): row.erase("queue_desk_id")
	checks.legacy_queue_readable = legacy.validate(_content).is_empty()
	var started: int = int(current.started_tick)
	var remaining: int = int(current.remaining_ticks)
	x = _restore_json(x)
	checks.new_instance_exact_restore = not x.has("restore_error") and x.get("restore_ok",false)
	if not checks.new_instance_exact_restore: return {"case":"GUIDE-DESK-SAVE-OWNERSHIP","ok":false,"checks":checks}
	checks.restored_same_desk_progress = x.g.state(x.world,"owner").desk_id=="guide" and int(x.g.state(x.world,"owner").remaining_ticks)==remaining
	for tick: int in 500:
		_step(x)
		if not x.g.state(x.world,"owner").receipts.is_empty(): break
	var receipt: Dictionary = x.g.state(x.world,"owner").receipts[0] if not x.g.state(x.world,"owner").receipts.is_empty() else {}
	checks.same_desk_completes_once = receipt.get("desk_id","")=="guide" and int(receipt.get("completed_tick",-1))-started+1==60 and x.g.state(x.world,"owner").receipts.size()==1
	checks.final_valid = x.world.validate(_content).is_empty()
	var result: Dictionary = {"case":"GUIDE-DESK-SAVE-OWNERSHIP","ok":not checks.values().has(false),"checks":checks,"receipt":receipt,"validation":x.world.validate(_content)}
	_dispose(x);return result

func _desk_schedule(rest: bool) -> Array:
	return [{"kind":"rest" if rest else "work","pools":[],"locked":false},{"kind":"work","pools":[],"locked":false},{"kind":"work" if rest else "rest","pools":[],"locked":false}]

func _scheduled_step(x: Dictionary) -> void:
	x.s.boundaries(x.world)
	_step(x)

func _desk_staff_pause() -> Dictionary:
	var x: Dictionary = _base()
	HospitalFactory._add_staff(x.world,"replacement","替班护士","nurse",[42,92],_content)
	for key: String in ["d","s","w","r","f","m"]: x[key].ensure(x.world)
	var setup: CommandResult = x.s.execute(x.world,"apply_schedule",{"changes":[{"staff_id":"replacement","schedule":_desk_schedule(true)}]})
	var visit: Dictionary = _visit(x,"pause",[45,87])
	var input_validation: String = x.world.validate(_content)
	for tick: int in 500:
		_scheduled_step(x)
		if x.g.state(x.world,visit.id).get("phase","")=="to_counter": break
	var before: Dictionary = x.g.state(x.world,visit.id).duplicate(true)
	var before_work: bool = before.get("phase","")=="to_counter" and not before.has("remaining_ticks") and not x.space.at(x.world,"guide_nurse",1,x.space.guidance_operator_cell(x.world,"guide","guide_nurse"))
	var rest: CommandResult = x.s.execute(x.world,"apply_schedule",{"changes":[{"staff_id":"guide_nurse","schedule":_desk_schedule(true)}]})
	var paused: bool = true
	var queue_kept: bool = true
	var saw_release: bool = false
	var valid_boundaries: bool = true
	var validation_errors: Array = []
	for tick: int in 150:
		_scheduled_step(x)
		var state: Dictionary = x.g.state(x.world,visit.id)
		paused = paused and state.receipts.is_empty() and not state.has("remaining_ticks") and x.g.worked_staff().is_empty()
		queue_kept = queue_kept and state.get("desk_id","")=="guide" and state.get("queue_seq",-1)==before.get("queue_seq",-2)
		saw_release = saw_release or x.world.facts.floor_guidance.releases.has("guide_nurse")
		var problem: String = x.world.validate(_content)
		if not problem.is_empty() and not problem in validation_errors: validation_errors.append(problem)
		valid_boundaries = valid_boundaries and problem.is_empty()
	var paused_snapshot: Dictionary = x.g.state(x.world,visit.id).duplicate(true)
	x = _restore_json(x)
	if x.has("restore_error"): return {"case":"GUIDE-DESK-STAFF-PAUSE","ok":false,"error":x.restore_error}
	var saved_pause: bool = x.restore_ok and x.g.state(x.world,"pause")==paused_snapshot
	var replacement: CommandResult = x.s.execute(x.world,"apply_schedule",{"changes":[{"staff_id":"replacement","schedule":_desk_schedule(false)}]})
	var actual_work: bool = true
	var work_ticks: int = 0
	for tick: int in 700:
		_scheduled_step(x)
		var state: Dictionary = x.g.state(x.world,"pause")
		if x.g.worked_staff().has("replacement"):
			work_ticks += 1
			var layout: Dictionary = x.space.facility_layout(x.world,"guide")
			actual_work = actual_work and x.space.at(x.world,"replacement",1,layout.operator_cells[0]) and x.space.at(x.world,x.world.facts.visits.pause.actor_id,1,layout.patient_cell) and state.desk_id=="guide"
		if state.get("phase","")=="ready": break
	var final: Dictionary = x.g.state(x.world,"pause").duplicate(true)
	var receipt: Dictionary = final.receipts[0] if not final.receipts.is_empty() else {}
	var completed: bool = final.get("phase","")=="ready" and receipt.get("desk_id","")=="guide" and receipt.get("nurse_id","")=="replacement" and final.receipts.size()==1
	var row: Dictionary = {"case":"GUIDE-DESK-STAFF-PAUSE","ok":input_validation.is_empty() and setup.accepted and before_work and rest.accepted and paused and queue_kept and saw_release and valid_boundaries and saved_pause and replacement.accepted and actual_work and work_ticks==60 and completed and x.world.validate(_content).is_empty(),"input_validation":input_validation,"counter_approach_before_nurse_arrival":before_work,"rest_command":rest.to_record(),"no_work_while_unstaffed":paused,"same_desk_queue_kept":queue_kept,"actual_nurse_release":saw_release,"all_pause_boundaries_valid":valid_boundaries,"pause_validation_errors":validation_errors,"paused_json_new_instance":saved_pause,"replacement_command":replacement.to_record(),"actual_patient_and_replacement_work":actual_work,"actual_work_ticks":work_ticks,"same_desk_completed_once":completed,"before":before,"paused":paused_snapshot,"final":final,"validation":x.world.validate(_content)}
	_dispose(x);return row

func _desk_close_active() -> Dictionary:
	var x: Dictionary = _base()
	x.m.ensure(x.world)
	var first: Dictionary = _visit(x,"active",[40,88])
	for tick: int in 600:
		_step(x)
		var state: Dictionary = x.g.state(x.world,first.id)
		if state.get("phase","")=="working" and int(state.remaining_ticks)==30: break
	var original: Dictionary = x.g.state(x.world,first.id).duplicate(true)
	var build: BuildService = BuildService.new(_content,x.space)
	var remodel: HospitalRemodel = HospitalRemodel.new(_content,x.space)
	remodel.services = {"building":build}
	var close: CommandResult = remodel.execute(x.world,"remodel_prepare",{"commands":[{"kind":"build_move","target_id":"guide","cell":[47,81],"floor_id":1}]})
	var other: Dictionary = _visit(x,"after_close",[43,90])
	var stable: bool = true
	var real_work: int = 0
	var no_new_work: bool = true
	var valid: bool = true
	for tick: int in 100:
		_step(x)
		var state: Dictionary = x.g.state(x.world,first.id)
		if x.g.worked_staff().has("guide_nurse"):
			real_work += 1
			var layout: Dictionary = x.space.facility_layout(x.world,"guide")
			stable = stable and state.desk_id=="guide" and x.space.at(x.world,first.actor_id,1,layout.patient_cell) and x.space.at(x.world,"guide_nurse",1,layout.operator_cells[0])
		no_new_work = no_new_work and x.g.state(x.world,other.id).receipts.is_empty() and not x.g.state(x.world,other.id).get("phase","") in ["to_counter","working"]
		valid = valid and x.world.validate(_content).is_empty()
	var receipt: Dictionary = x.g.state(x.world,first.id).receipts[0] if not x.g.state(x.world,first.id).receipts.is_empty() else {}
	var completed: bool = receipt.get("desk_id","")=="guide" and int(receipt.get("completed_tick",-1))-int(original.get("started_tick",-1))+1==60 and real_work==30
	var reopen: CommandResult = remodel.execute(x.world,"remodel_cancel",{"order_id":close.changed_ids[0]}) if close.accepted else CommandResult.new(false,"not_closed","",[],x.world.revision)
	for tick: int in 700:
		_step(x)
		if x.g.state(x.world,other.id).get("phase","")=="ready": break
	var next: Dictionary = x.g.state(x.world,other.id)
	var new_service: bool = next.get("phase","")=="ready" and next.receipts.size()==1 and next.receipts[0].desk_id=="guide" and int(next.receipts[0].started_tick)>int(receipt.get("completed_tick",0))
	var row: Dictionary = {"case":"GUIDE-DESK-CLOSE-ACTIVE","ok":original.get("phase","")=="working" and close.accepted and stable and completed and no_new_work and valid and reopen.accepted and new_service and x.world.validate(_content).is_empty(),"close_command":close.to_record(),"original_service_stayed_at_its_desk":stable,"remaining_actual_work_ticks":real_work,"original_sixty_ticks_completed_once":completed,"closed_desk_accepts_no_new_work":no_new_work,"all_closed_boundaries_valid":valid,"reopen_command":reopen.to_record(),"reopened_desk_real_new_service":new_service,"first_receipt":receipt,"second_receipts":next.receipts.duplicate(true),"validation":x.world.validate(_content)}
	_dispose(x);return row
