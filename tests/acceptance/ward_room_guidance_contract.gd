extends "res://tests/acceptance/clinical_fixtures.gd"

# One real production prefix is immutable. Each scenario owns a complete facts
# copy and newly constructed services; neither scenario edits the source input.
static var _ward_source: Dictionary = {}
static var _ward_source_identity: String = ""

func run_case(database: HospitalContent, mode: String) -> Dictionary:
	_content = database
	if not mode in ["room_loss","nurse_need"]: return {"ok":false,"error":"Unknown ward contract: "+mode}
	var started: int = Time.get_ticks_msec()
	var identity: String = database.content_fingerprint+FileAccess.get_sha256("res://tests/acceptance/clinical_fixtures.gd")
	var source_kind: String = "memory"
	if _ward_source.is_empty() or _ward_source_identity!=identity:
		source_kind = "built"
		_ward_source = _produce_ward_input()
		_ward_source_identity = identity
	var setup_ms: int = Time.get_ticks_msec()-started
	if _ward_source.is_empty():
		_dispose_simulations()
		return {"ok":false,"mode":mode,"fixture_errors":_fixture_failures,"setup_ms":setup_ms}
	var source_hash: String = _hash(_ward_source.facts)
	_snapshots.ward_contract = _ward_source.duplicate(true)
	var c: Dictionary = _copy("ward_contract")
	setup_ms = Time.get_ticks_msec()-started
	var input: Dictionary = {"source":source_kind,"key":"actual_surgery_ward_care","sha256":source_hash,"tick":c.world.sim_tick,"setup_ms":setup_ms,"content_fingerprint":database.content_fingerprint,"staff":c.world.facts.staff.size(),"facilities":c.world.facts.facilities.size(),"beds":c.world.facility_ids("EQ05").size(),"real_prefix":_ward_source.prefix.duplicate(true)}
	var body_started: int = Time.get_ticks_msec()
	var result: Dictionary = _run_contract(c,mode)
	result.mode = mode
	result.input = input
	result.setup_ms = setup_ms
	result.body_ms = Time.get_ticks_msec()-body_started
	result.checks.immutable_input = _hash(_ward_source.facts)==source_hash
	result.ok = result.checks.values().all(func(value: Variant)->bool:return value==true)
	if not result.ok: result.failure_world = _failure_world("RESULT-03" if mode=="room_loss" else "RESULT-04",c.world)
	_dispose_simulations()
	return result

func _produce_ward_input() -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var c: Dictionary = _context(true,false,true,[],true)
	_seed_stream(c.world,"treatment",true,true,9600,9800)
	if not _arrive(c,"B_S13_D09_M09","P_D09_SURGERY"):
		_fixture_failures.append({"failure_world":_failure_world("WARD-CONTRACT-PREFIX",c.world)})
		return {}
	var selected: Dictionary = {}
	var phases: Array = []
	var prior_phase: String = ""
	var ready: bool = false
	for index: int in 7000:
		var phase: String = str(_visit(c).phase)
		if phase!=prior_phase:
			phases.append({"tick":c.world.sim_tick,"phase":phase})
			prior_phase = phase
		if selected.is_empty() and phase in ["wait_outpatient","wait_surgery"]:
			if not bool(_ward_nurse_return_state(c).ready):
				_fixture_failures.append({"actual_ward_nurse_not_ready":_ward_nurse_return_state(c)})
				break
			selected = _command(c,"clinical_select_plan",{"visit_id":c.visit_id,"plan_id":"P_D09_SURGERY"}).to_record()
			if not selected.accepted:
				_fixture_failures.append({"surgery_selection":selected})
				break
		var stay: Dictionary = _stay(c)
		if not stay.is_empty() and stay.phase=="recovery" and not _session(c,"care").is_empty() and not c.sim.clinic.staff_busy(c.world,str(stay.escort_id)):
			ready = true
			break
		_tick(c)
	var validation: String = c.world.validate(_content)
	if not ready or not validation.is_empty():
		_fixture_failures.append({"ward_care_missing":not ready,"validation":validation,"actual_tick":c.world.sim_tick,"phase":_visit(c).get("phase",""),"failure_world":_failure_world("WARD-CONTRACT-PREFIX",c.world)})
		return {}
	var state: Dictionary = {"facts":c.world.freeze(),"visit_id":c.visit_id,"serial":int(c.serial),"doctors":c.doctors.duplicate(),"started":c.started.duplicate(),"group_seen":c.group_seen,"beats":c.beats.duplicate(),"capture_events":true,"event_log":c.event_log.duplicate(true),"nursing_handoff_ticks":c.nursing_handoff_ticks.duplicate(true),"nursing_handoff_not_at_base":c.nursing_handoff_not_at_base.duplicate(true)}
	state.prefix = {"elapsed_ms":Time.get_ticks_msec()-started,"actual_steps_from_creation":c.world.sim_tick,"phases":phases,"selection":selected,"validation":validation,"nursing_handoff_ticks":c.nursing_handoff_ticks.duplicate(true),"nursing_handoff_not_at_base":c.nursing_handoff_not_at_base.duplicate(true)}
	_dispose_simulations()
	return state

func _run_contract(c: Dictionary, mode: String) -> Dictionary:
	var stay_input: Dictionary = _stay(c).duplicate(true)
	var care_input: Dictionary = _session(c,"care").duplicate(true)
	var bed_id: String = str(stay_input.bed_id)
	var nurse_id: String = str(stay_input.nurse_id)
	var ward_id: String = str(c.world.facts.facilities[bed_id].room_id)
	var attempt: Dictionary = c.world.facts.attempts[stay_input.attempt_id].duplicate(true)
	var immutable_attempt: Dictionary = _commitments({attempt.id:attempt})
	var initial_remaining: int = int(stay_input.remaining_ticks)
	var initial_rest_tick: int = int(c.world.facts.staff[nurse_id].last_rest_end_tick)
	var checks: Dictionary = {"legal_real_input":c.world.validate(_content).is_empty() and stay_input.phase=="recovery" and initial_remaining>0 and int(care_input.total_ticks)==80 and int(c.nursing_handoff_ticks.get(nurse_id,0))==60 and c.nursing_handoff_not_at_base.is_empty(),"one_original_attempt":_visit(c).attempt_ids.size()==1,"real_bodies":true,"world_valid":true,"full_recovery":false,"care_at_bedside":true,"exact_work_rate":true,"no_early_fees":true,"original_commitments":true,"original_stay_resources":true,"actual_safe_bed_exit":false,"actual_departure":false,"unique_original_bill":false,"one_original_supply_issue":false,"no_round":true}
	var operation: Dictionary = {}
	if mode=="room_loss":
		var ward: Dictionary = c.world.facts.rooms[ward_id]
		var origin: Array = ward.origin
		var removed: CommandResult = _command(c,"build_remove_wall",{"floor_id":int(ward.floor_id),"edges":[{"axis":"x","line":int(origin[1]),"low":int(origin[0]),"high":int(origin[0])+1}]})
		operation = removed.to_record()
		var old_room: Dictionary = c.world.facts.rooms.get(ward_id,{})
		checks.wall_removed = removed.accepted
		checks.old_use_invalid = old_room.get("kind","")=="" and not old_room.get("structure_valid",true) and not old_room.get("open_intent",true)
		checks.no_new_bed_admission = not c.sim.space.room_use.reason(c.world,ward_id).is_empty() and not c.sim.clinic._compatible_bed(c.world,_visit(c),1,[],true).get("ok",true)
		checks.commitment_retained_at_demolition = _stay(c)==stay_input and _session(c,"care")==care_input and c.world.facts.facilities[bed_id].get("room_id","")==ward_id and c.world.facts.staff[nurse_id].get("ward_id","")==ward_id
		checks.old_schedule_released = c.world.facts.staff[nurse_id].schedule.all(func(entry: Dictionary)->bool:return not ward_id in entry.get("pools",[]))
	else:
		var pending: Dictionary=c.world.facts.staff[nurse_id].life_task
		operation = {"kind":"automatic_amenity","purpose":pending.get("purpose",""),"started_tick":pending.get("started_tick",-1),"tick":c.world.sim_tick}
		checks.automatic_need_preserved = pending.get("kind","")=="amenity" and pending.get("purpose","")=="toilet" and pending.phase=="wait_safe" and int(pending.started_tick)>=1800
		checks.wait_safe_until_coverage_end = true
		checks.same_prepared_work_segment = bool(c.world.facts.staff[nurse_id].get("base_prepared",false))
		checks.rest_clock_unchanged = true
		checks.actual_amenity_use = false
		checks.safe_return = false
	var observed: Dictionary = {"recovery_work_ticks":0,"recovery_advancing_steps":0,"care_work_ticks":int(care_input.total_ticks)-int(care_input.remaining_ticks),"care_advancing_steps":0,"wait_safe_steps":0,"use_work_ticks":0,"use_started_tick":-1,"use_completed_tick":-1,"coverage_released_tick":-1,"first_amenity_travel_tick":-1,"care_completed_with_recovery_left":false,"care_completed_tick":-1,"safe_bed_exit_tick":-1,"departure_tick":-1,"return_tick":-1,"amenity_at_facility":true,"amenity_facility_id":"","return_target":{}}
	var errors: Array = []
	var final_entries: Dictionary = {}
	for index: int in 3600:
		var before_stay: Dictionary = _stay(c).duplicate(true)
		var before_care: Dictionary = _session(c,"care").duplicate(true)
		var before_need: Dictionary = c.world.facts.staff[nurse_id].life_task.duplicate(true)
		_tick(c)
		var validation: String = c.world.validate(_content)
		var overlap: Array = _overlapping_bodies(c)
		checks.world_valid = checks.world_valid and validation.is_empty()
		checks.real_bodies = checks.real_bodies and overlap.is_empty()
		if not validation.is_empty() or not overlap.is_empty():
			errors.append({"tick":c.world.sim_tick,"validation":validation,"overlap":overlap})
			break
		var stay: Dictionary = _stay(c)
		var care: Dictionary = _session(c,"care")
		var nurse: Dictionary = c.world.facts.staff[nurse_id]
		var need: Dictionary = nurse.life_task
		if not before_stay.is_empty():
			var work: int = maxi(0,int(before_stay.remaining_ticks)-int(stay.get("remaining_ticks",0)))
			observed.recovery_work_ticks += work
			if work>0: observed.recovery_advancing_steps += 1
			checks.exact_work_rate = checks.exact_work_rate and work<=1
		if not before_care.is_empty():
			var work: int = maxi(0,int(before_care.remaining_ticks)-int(care.get("remaining_ticks",0)))
			observed.care_work_ticks += work
			if work>0: observed.care_advancing_steps += 1
			checks.exact_work_rate = checks.exact_work_rate and work<=1
		if not care.is_empty():
			var bed: Dictionary = c.sim.space.facility_layout(c.world,bed_id)
			checks.care_at_bedside = checks.care_at_bedside and care.staff_ids==care_input.staff_ids and care.facility_id==bed_id and c.sim.space.at(c.world,nurse_id,int(bed.floor_id),bed.operator_cells[0])
		if not stay.is_empty(): checks.original_stay_resources = checks.original_stay_resources and stay.nurse_id==nurse_id and stay.bed_id==bed_id and stay.attempt_id==attempt.id
		if not stay.is_empty() and stay.get("care_completed",false):
			if int(observed.care_completed_tick)<0: observed.care_completed_tick = c.world.sim_tick
			if int(stay.remaining_ticks)>0: observed.care_completed_with_recovery_left = true
		if not stay.is_empty() and (int(stay.remaining_ticks)>0 or not stay.care_completed): checks.no_early_fees = checks.no_early_fees and _income(c,"ward")==0 and _income(c,"cure")==0
		checks.original_commitments = checks.original_commitments and _commitments(c.world.facts.attempts)==immutable_attempt
		checks.no_round = checks.no_round and _session(c,"round").is_empty() and int(c.started.get("round",0))==0
		if not before_stay.is_empty() and not before_stay.phase in ["release_wait","complete"] and (stay.is_empty() or stay.phase in ["release_wait","complete"]) and int(observed.coverage_released_tick)<0: observed.coverage_released_tick = c.world.sim_tick
		if _visit(c).get("final_result","")=="cured" and not c.sim.space.overlaps_facility(c.world,str(_visit(c).actor_id),bed_id):
			checks.actual_safe_bed_exit = true
			if int(observed.safe_bed_exit_tick)<0: observed.safe_bed_exit_tick = c.world.sim_tick
		if _visit(c).phase=="departed":
			checks.actual_departure = c.world.facts.actors[_visit(c).actor_id].location.kind=="outside"
			if int(observed.departure_tick)<0: observed.departure_tick = c.world.sim_tick
		if mode=="nurse_need":
			checks.same_prepared_work_segment = checks.same_prepared_work_segment and bool(nurse.get("base_prepared",false)) and nurse.get("base_task",{}).is_empty()
			checks.rest_clock_unchanged = checks.rest_clock_unchanged and int(nurse.last_rest_end_tick)==initial_rest_tick
			if not stay.is_empty() and not stay.phase in ["release_wait","complete"]:
				observed.wait_safe_steps += 1
				checks.wait_safe_until_coverage_end = checks.wait_safe_until_coverage_end and need.phase=="wait_safe" and nurse.on_shift and stay.nurse_id==nurse_id and c.sim.clinic._ward_covering(c.world,stay)
			if not need.phase in ["idle","wait_safe"] and int(observed.first_amenity_travel_tick)<0: observed.first_amenity_travel_tick = c.world.sim_tick
			var used: int = 0
			if before_need.phase=="using": used = int(before_need.remaining_ticks)-int(need.get("remaining_ticks",0))
			elif need.phase=="using": used = 80-int(need.remaining_ticks)
			if need.phase=="using" and int(observed.use_started_tick)<0: observed.use_started_tick = int(need.use_started_tick)
			if used>0:
				observed.use_work_ticks += used
				checks.exact_work_rate = checks.exact_work_rate and used==1
				var facility: String = str(need.get("facility_id",before_need.get("facility_id","")))
				observed.amenity_facility_id = facility
				var amenity: Dictionary = c.sim.space.facility_layout(c.world,facility)
				observed.amenity_at_facility = observed.amenity_at_facility and not amenity.is_empty() and c.world.facts.facilities[facility].definition_id=="FUR07" and c.sim.space.at(c.world,nurse_id,int(amenity.floor_id),amenity.patient_cell)
			if before_need.phase=="using" and need.phase!="using": observed.use_completed_tick = c.world.sim_tick
			if need.phase in ["returning","release"]: observed.return_target = {"floor_id":need.floor_id,"cell":need.cell.duplicate()}
			if int(observed.use_work_ticks)>0 and need.phase=="idle" and nurse.on_shift and not c.world.facts.moves.has(nurse_id):
				var target: Dictionary = observed.return_target
				checks.safe_return = not target.is_empty() and c.sim.space.at(c.world,nurse_id,int(target.floor_id),target.cell) and not c.sim.space.overlaps_facility(c.world,nurse_id,str(observed.amenity_facility_id))
				observed.return_tick = c.world.sim_tick
		if checks.actual_departure and (mode=="room_loss" or checks.get("safe_return",false)):
			final_entries = _positive_bill(c)
			break
	checks.full_recovery = int(observed.recovery_work_ticks)==initial_remaining and int(observed.recovery_advancing_steps)==initial_remaining and int(attempt.recovery_ticks)==1800 and observed.care_completed_with_recovery_left
	checks.full_original_care = int(observed.care_work_ticks)==80 and int(observed.care_advancing_steps)==int(care_input.remaining_ticks) and int(c.started.get("care",0))==1
	checks.unique_original_bill = _income(c)==505 and _income(c,"consultation")==20 and _income(c,"gp")==5 and _income(c,"surgery")==60 and _income(c,"ward")==60 and _income(c,"cure")==360 and final_entries.size()==5
	checks.one_original_supply_issue = _units_used(c)==8 and c.world.facts.inventory.issues.size()==1 and _visit(c).attempt_ids.size()==1
	if mode=="nurse_need": checks.actual_amenity_use = int(observed.use_work_ticks)==80 and int(observed.use_completed_tick)-int(observed.use_started_tick)==80 and observed.amenity_at_facility and int(observed.wait_safe_steps)>0 and int(observed.first_amenity_travel_tick)>=int(observed.coverage_released_tick) and int(observed.use_started_tick)>=int(observed.coverage_released_tick)
	if checks.actual_departure:
		for index: int in 5: _tick(c)
		checks.bill_stable_after_departure = _positive_bill(c)==final_entries and _units_used(c)==8
	if mode=="room_loss": checks.old_room_released_after_exit = not c.world.facts.rooms.has(ward_id) and c.world.facts.facilities[bed_id].get("room_id","")!=ward_id
	return {"checks":checks,"operation":operation,"initial_tick":int(_ward_source.facts.sim_tick) if _ward_source.facts.has("sim_tick") else _ward_source.prefix.actual_steps_from_creation,"final_tick":c.world.sim_tick,"remaining_recovery_at_input":initial_remaining,"recovery_work_in_real_prefix":1800-initial_remaining,"care_input":care_input,"attempt":attempt,"observed":observed,"positive_entries":_positive_bill(c),"supply_units":_units_used(c),"initial_rest_tick":initial_rest_tick,"final_rest_tick":c.world.facts.staff[nurse_id].last_rest_end_tick,"event_log":c.event_log,"errors":errors}

func _positive_bill(c: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in c.world.facts.ledger.entries:
		var entry: Dictionary = c.world.facts.ledger.entries[id]
		if int(entry.amount)>0: result[id] = entry.duplicate(true)
	return result

func _hash(value: Dictionary) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func _overlapping_bodies(c: Dictionary) -> Array:
	var bodies: Array = []
	for actor: Dictionary in c.world.facts.actors.values():
		if actor.location.kind=="floor": bodies.append({"id":actor.id,"floor":actor.location.floor_id,"body":c.sim.space.body_rectangle(actor)})
	for index: int in bodies.size():
		for other: int in range(index+1,bodies.size()):
			if bodies[index].floor==bodies[other].floor and bodies[index].body.intersects(bodies[other].body,false): return [bodies[index].id,bodies[other].id]
	return []
