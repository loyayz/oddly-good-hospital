extends "res://tests/acceptance/clinical_fixtures.gd"

const WardContract = preload("res://tests/acceptance/ward_room_guidance_contract.gd")

func run_case(database: HospitalContent, mode: String) -> Dictionary:
	_content = database
	var started: int = Time.get_ticks_msec()
	var result: Dictionary
	match mode:
		"auto_need": result = _auto_need()
		"social_visit": result = _social_visit()
		_: return {"ok":false,"error":"Unknown staff life contract: "+mode}
	result.mode = mode
	result.elapsed_ms = Time.get_ticks_msec()-started
	_dispose_simulations()
	return result

func _auto_need() -> Dictionary:
	var clock: Dictionary = _clock_boundary()
	var gp: Dictionary = _gp_need_cycles()
	var runs: Array = [clock,gp]
	if gp.has("first_return_input"):
		var source: Dictionary = gp.first_return_input
		gp.erase("first_return_input")
		var source_hash: String = _facts_hash(source.facts)
		var failed: Dictionary = _no_water(source,str(gp.staff_id))
		failed.checks.immutable_original_input = _facts_hash(source.facts)==source_hash
		failed.ok = _passed(failed.checks)
		runs.append(failed)
	return {"ok":runs.size()==3 and runs.all(func(row: Dictionary)->bool:return row.ok),"runs":runs}

func _clock_boundary() -> Dictionary:
	# A declared hospital immediately before the first due boundary. No active
	# movement/work is supplied: nurses must really walk to SE06 and work.
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"员工首次需求边界",true,_content)
	world.facts.sim_tick = 1799
	var sim := HospitalSimulation.new(world,_content)
	_simulations.append(sim)
	var c: Dictionary = _context_record(sim,world)
	_command(c,"set_intake_open",{"open":false})
	_command(c,"tutorial_set_enabled",{"enabled":false})
	_command(c,"set_auto_restock",{"enabled":false})
	var nurse_id: String = "starter_nurse"
	var checks: Dictionary = {"hired_zero_first_due_1800":int(world.facts.staff[nurse_id].hired_tick)==0 and world.facts.staff[nurse_id].amenity_clock=={"next_need_tick":1800,"next_purpose":"toilet"},"before_due_no_need":true,"due_entry_exact":false,"base_rejection_atomic":false,"due_stays_pending":true,"actual_base_work":false,"automatic_after_base":false}
	var errors: Array = []
	_step_checked(c,errors,true)
	checks.before_due_no_need = world.sim_tick==1800 and world.facts.staff[nurse_id].life_task.phase=="idle"
	var due_source: Dictionary = _freeze_context(c)
	var doctor_id: String = ""
	for id: String in world.ids("staff"):
		if world.facts.staff[id].role=="doctor": doctor_id=id; break
	var sleep: Dictionary = _clone(due_source)
	# Independent legal mandatory-sleep boundary; no sleep work is supplied.
	sleep.world.facts.staff[doctor_id].awake_ticks = ceili(float(_content.balance.staff_sleep.awake_limit_seconds)/WorldState.TICK_SECONDS)
	_step_checked(sleep,errors,true)
	checks.sleep_priority = sleep.world.facts.staff[doctor_id].life_task.get("kind","")=="sleep" and sleep.world.facts.staff[doctor_id].amenity_clock.next_need_tick==1800
	var leave: Dictionary = _clone(due_source)
	var planned: CommandResult = _command(leave,"plan_leave",{"staff_id":doctor_id,"days":1,"start":"now"})
	_step_checked(leave,errors,true)
	checks.leave_priority = planned.accepted and leave.world.facts.staff[doctor_id].life_task.get("kind","")=="leave" and leave.world.facts.staff[doctor_id].amenity_clock.next_need_tick==1800
	var frozen: Dictionary = world.freeze()
	checks.base_rejection_atomic = not c.sim.services.wellbeing.begin_amenity(world,nurse_id,"toilet") and world.freeze()==frozen and not world.facts.staff[nurse_id].get("base_task",{}).is_empty()
	_step_checked(c,errors,true)
	for staff: Dictionary in world.facts.staff.values():
		if staff.get("life_task",{}).get("kind","")=="amenity" and staff.life_task.get("started_tick",-1)==1800: checks.due_entry_exact = true
	for index: int in 900:
		var staff: Dictionary = world.facts.staff[nurse_id]
		if staff.life_task.get("kind","")=="amenity":
			checks.automatic_after_base = staff.get("base_prepared",false) and staff.base_task.is_empty() and staff.life_task.purpose=="toilet"
			break
		checks.due_stays_pending = checks.due_stays_pending and staff.amenity_clock=={"next_need_tick":1800,"next_purpose":"toilet"}
		if not _step_checked(c,errors): break
	checks.actual_base_work = int(c.nursing_handoff_ticks.get(nurse_id,0))==60 and c.nursing_handoff_not_at_base.is_empty()
	return _result(c,checks,{"name":"first_1800_and_nurse_base","tick":world.sim_tick,"nursing_handoff_ticks":c.nursing_handoff_ticks,"clock":world.facts.staff[nurse_id].amenity_clock.duplicate(true),"errors":errors})

func _gp_need_cycles() -> Dictionary:
	var c: Dictionary = _context(false,false,true,[],true)
	var errors: Array = []
	# These are real fixed steps, not a rewritten clock or called reservation.
	while c.world.sim_tick<1480:
		if not _step_checked(c,errors): break
	_seed_stream(c.world,"treatment",true,true,9200,9800)
	var arrived: bool = _arrive(c)
	var doctor_id: String = str(c.doctors[0])
	var checks: Dictionary = {"patient_arrived":arrived,"clock_not_rewritten":int(c.world.facts.staff[doctor_id].hired_tick)==0 and int(c.world.facts.staff[doctor_id].amenity_clock.next_need_tick)==1800,"before_1800_no_need":false,"due_during_called_gp":false,"called_rejection_atomic":false,"called_commitment_retained":true,"original_gp_safe_work":true,"original_gp_complete":false,"pending_clock_not_restarted":true,"toilet_80":false,"water_80":false,"first_cooldown_and_alternation":false,"cooldown_before_boundary":false,"next_boundary_automatic":false,"second_cooldown_and_alternation":false,"all_attempt_clocks_and_purposes":true,"all_failed_attempts_no_use":true,"no_early_attempts":true,"cold_restore":false,"rest_clock_unchanged":true,"one_original_gp_bill":false}
	var observed: Dictionary = {"arrival_tick":c.world.sim_tick,"called_first_tick":-1,"gp_started_tick":-1,"gp_completed_tick":-1,"gp_work_ticks":0,"gp_total_ticks":-1,"due_clock":1800,"needs":{},"successful_toilet":{},"successful_water":{},"restore":{},"gather_at_due":{},"first_return_input":{}}
	var initial_rest: int = int(c.world.facts.staff[doctor_id].last_rest_end_tick)
	for index: int in 9000:
		var tick: int = c.world.sim_tick
		var staff: Dictionary = c.world.facts.staff[doctor_id]
		var gathering: bool = c.sim.services.wellbeing._staff_query(c.world).gathering.has(doctor_id)
		if gathering and int(observed.called_first_tick)<0: observed.called_first_tick = tick
		if tick==1799: checks.before_1800_no_need = staff.life_task.phase=="idle" and staff.amenity_clock.next_need_tick==1800
		if tick==1800:
			var called_ticket: Dictionary = c.world.facts.tickets.get(str(_visit(c).get("ticket_id","")),{})
			checks.due_during_called_gp = gathering and called_ticket.get("kind","")=="gp" and _session(c,"gp").is_empty()
			observed.gather_at_due = {"gathering":gathering,"ticket":called_ticket.duplicate(true),"adaptations":c.world.facts.adaptations.duplicate(true),"doctor_move":c.world.facts.moves.get(doctor_id,{}).duplicate(true)}
			if gathering:
				var before: Dictionary = c.world.freeze()
				checks.called_rejection_atomic = not c.sim.services.wellbeing.begin_amenity(c.world,doctor_id,"toilet") and c.world.freeze()==before
		var before_need: Dictionary = staff.life_task.duplicate(true)
		var before_gp: Dictionary = _session(c,"gp").duplicate(true)
		var held: Dictionary = {}
		if tick>=1800 and gathering and int(observed.gp_started_tick)<0: held = _gathering_owners(c,doctor_id)
		if not observed.successful_toilet.is_empty():
			var first: Dictionary = observed.successful_toilet
			if first.has("clock_at_return") and tick==int(first.clock_at_return.next_need_tick)-1: checks.cooldown_before_boundary = staff.life_task.get("kind","")!="amenity" and staff.amenity_clock==first.clock_at_return
		if not _step_checked(c,errors,not before_gp.is_empty() or before_need.get("phase","")=="using"): break
		staff = c.world.facts.staff[doctor_id]
		var gp: Dictionary = _session(c,"gp")
		if not held.is_empty() and gp.is_empty(): checks.called_commitment_retained = checks.called_commitment_retained and _gathering_owners(c,doctor_id)==held and staff.life_task.phase=="idle" and staff.amenity_clock.next_need_tick==1800
		if not gp.is_empty() and int(observed.gp_started_tick)<0:
			observed.gp_started_tick = int(gp.start_tick)
			observed.gp_total_ticks = int(gp.total_ticks)
			observed.gp_work_ticks += int(gp.total_ticks)-int(gp.remaining_ticks)
		if not before_gp.is_empty():
			observed.gp_work_ticks += int(before_gp.remaining_ticks)-int(gp.get("remaining_ticks",0))
			if gp.is_empty(): observed.gp_completed_tick = tick
		if not gp.is_empty() and staff.life_task.get("kind","")=="amenity":
			var facility: Dictionary = c.sim.space.facility_layout(c.world,gp.facility_id)
			checks.original_gp_safe_work = checks.original_gp_safe_work and staff.life_task.phase=="wait_safe" and staff.on_shift and c.sim.space.at(c.world,doctor_id,int(facility.floor_id),facility.operator_cells[0])
		_measure_need(c,doctor_id,before_need,observed.needs)
		if staff.life_task.get("kind","")=="amenity" and observed.needs.size()==1: checks.pending_clock_not_restarted = checks.pending_clock_not_restarted and staff.amenity_clock=={"next_need_tick":1800,"next_purpose":"toilet"}
		checks.rest_clock_unchanged = checks.rest_clock_unchanged and int(staff.last_rest_end_tick)==initial_rest
		var completed: Array = observed.needs.values().filter(func(row: Dictionary)->bool:return row.has("clock_at_return"))
		for row: Dictionary in completed:
			if observed.successful_toilet.is_empty() and row.purpose=="toilet" and _full_use(row) and row.clock_at_return.next_purpose=="water":
				observed.successful_toilet = row.duplicate(true)
				observed.first_return_input = _freeze_context(c)
			elif not observed.successful_toilet.is_empty() and row.purpose=="water" and _full_use(row) and row.clock_at_return.next_purpose=="toilet": observed.successful_water = row.duplicate(true)
		if observed.restore.is_empty() and staff.life_task.get("phase","")=="using" and int(staff.life_task.remaining_ticks)==40:
			var facts: Dictionary = c.world.freeze()
			observed.restore = _roundtrip(c)
			checks.cold_restore = observed.restore.get("ok",false) and c.world.freeze()==facts
			if not checks.cold_restore: break
		if not observed.successful_water.is_empty(): break
	var needs: Array = observed.needs.values()
	var expected_clock: Dictionary = {"next_need_tick":1800,"next_purpose":"toilet"}
	for row: Dictionary in needs:
		checks.no_early_attempts = checks.no_early_attempts and int(row.requested_tick)>=int(expected_clock.next_need_tick)
		checks.all_attempt_clocks_and_purposes = checks.all_attempt_clocks_and_purposes and row.purpose==expected_clock.next_purpose and row.has("clock_at_return")
		if not row.has("clock_at_return"): continue
		if row.has("completed_tick"):
			var next_purpose: String = "water" if row.purpose=="toilet" else "toilet"
			checks.all_attempt_clocks_and_purposes = checks.all_attempt_clocks_and_purposes and _full_use(row) and row.clock_at_return=={"next_need_tick":int(row.completed_tick)+1800,"next_purpose":next_purpose}
		else:
			checks.all_failed_attempts_no_use = checks.all_failed_attempts_no_use and int(row.work_ticks)==0 and int(row.work_steps)==0 and not row.has("use_started_tick") and row.has("finished_tick")
			checks.all_attempt_clocks_and_purposes = checks.all_attempt_clocks_and_purposes and row.has("finished_tick") and row.clock_at_return=={"next_need_tick":int(row.get("finished_tick",-1))+1800,"next_purpose":str(row.purpose)}
		expected_clock = row.clock_at_return
	if not observed.successful_toilet.is_empty():
		var first: Dictionary = observed.successful_toilet
		checks.toilet_80 = first.has("use_started_tick") and _full_use(first) and int(first.requested_tick)>=int(observed.gp_started_tick) and int(first.use_started_tick)>int(observed.gp_completed_tick)
		checks.first_cooldown_and_alternation = first.has("completed_tick") and first.has("clock_at_return") and first.clock_at_return=={"next_need_tick":int(first.completed_tick)+1800,"next_purpose":"water"}
		for row: Dictionary in needs:
			if row.purpose=="water" and int(row.requested_tick)>=int(first.returned_tick):
				checks.next_boundary_automatic = first.has("clock_at_return") and int(row.requested_tick)>=int(first.clock_at_return.next_need_tick)
				break
	if not observed.successful_water.is_empty():
		var second: Dictionary = observed.successful_water
		checks.water_80 = _full_use(second)
		checks.second_cooldown_and_alternation = second.has("completed_tick") and second.has("clock_at_return") and second.clock_at_return=={"next_need_tick":int(second.completed_tick)+1800,"next_purpose":"toilet"}
	checks.original_gp_complete = int(observed.gp_total_ticks)>0 and int(observed.gp_work_ticks)==int(observed.gp_total_ticks) and int(c.started.get("gp",0))==1
	checks.one_original_gp_bill = _income(c,"consultation")==20 and _income(c,"gp")==5
	var source: Dictionary = observed.first_return_input
	observed.erase("first_return_input")
	var result: Dictionary = _result(c,checks,{"name":"called_gp_and_automatic_cycles","staff_id":doctor_id,"observed":observed,"errors":errors,"final_tick":c.world.sim_tick})
	if not source.is_empty(): result.first_return_input = source
	return result

func _no_water(source: Dictionary, staff_id: String) -> Dictionary:
	var c: Dictionary = _clone(source)
	var checks: Dictionary = {"formal_store":false,"actors_unchanged":true,"stored_before_next_due":false,"no_usage_faked":false,"failed_attempt_cooldown":false,"failed_purpose_not_alternated":false}
	var commands: Array = []
	var before_clock: Dictionary = c.world.facts.staff[staff_id].amenity_clock.duplicate(true)
	var due: int = int(before_clock.next_need_tick)
	var pending: Array = c.world.facility_ids("FUR17")
	var wait_steps: int = 0
	var errors: Array = []
	# Existing users retain the complete use and physical release. Failed store
	# commands do not create an absent-facility input; only actual commits do.
	while not pending.is_empty() and c.world.sim_tick<due:
		for id: String in pending.duplicate():
			var actors: Dictionary = c.world.facts.actors.duplicate(true)
			var tick: int = c.world.sim_tick
			var stored: CommandResult = _command(c,"build_store",{"target_id":id})
			var unchanged: bool = c.world.facts.actors==actors
			commands.append({"tick":tick,"target_id":id,"actors_unchanged":unchanged,"result":stored.to_record()})
			checks.actors_unchanged = checks.actors_unchanged and unchanged
			if stored.accepted: pending.erase(id)
		if pending.is_empty(): break
		if not _step_checked(c,errors): break
		wait_steps += 1
	checks.formal_store = pending.is_empty() and c.world.facility_ids("FUR17").is_empty()
	checks.stored_before_next_due = checks.formal_store and c.world.sim_tick<due and c.world.facts.staff[staff_id].amenity_clock==before_clock
	if not checks.stored_before_next_due: return _result(c,checks,{"name":"no_water_failure","prior_clock":before_clock,"wait_steps":wait_steps,"remaining_water_facilities":pending,"commands":commands,"errors":errors})
	var stored_tick: int = c.world.sim_tick
	var needs: Dictionary = {}
	for index: int in 2800:
		var before: Dictionary = c.world.facts.staff[staff_id].life_task.duplicate(true)
		if not _step_checked(c,errors,before.get("phase","")=="using"): break
		_measure_need(c,staff_id,before,needs)
		if needs.values().any(func(row: Dictionary)->bool:return row.has("clock_at_return")): break
	var rows: Array = needs.values()
	if rows.size()==1:
		var row: Dictionary = rows[0]
		checks.no_usage_faked = row.purpose=="water" and int(row.work_ticks)==0 and not row.has("completed_tick")
		checks.failed_attempt_cooldown = row.has("finished_tick") and row.has("clock_at_return") and int(row.clock_at_return.next_need_tick)==int(row.finished_tick)+1800
		checks.failed_purpose_not_alternated = row.has("clock_at_return") and row.clock_at_return.next_purpose==before_clock.next_purpose
	return _result(c,checks,{"name":"no_water_failure","prior_clock":before_clock,"wait_steps":wait_steps,"stored_tick":stored_tick,"remaining_water_facilities":pending,"needs":needs,"commands":commands,"errors":errors})

func _social_visit() -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var producer: RefCounted = WardContract.new()
	producer.set("_content",_content)
	var ward: Dictionary = producer.call("_produce_ward_input")
	if ward.is_empty(): return {"ok":false,"error":"Fresh real ward_care prerequisite failed","fixture_errors":producer.get("_fixture_failures")}
	var ward_hash: String = _facts_hash(ward.facts)
	var scan: Dictionary = _clone(ward)
	var doctor_id: String = str(scan.doctors[0])
	var changed: CommandResult = _room_schedule(scan,doctor_id,[])
	var errors: Array = []
	var ready: bool = false
	for index: int in 1500:
		var staff: Dictionary = scan.world.facts.staff[doctor_id]
		if scan.world.sim_tick%600==0 and staff.life_task.phase=="idle" and not scan.world.facts.moves.has(doctor_id) and scan.sim.services.wellbeing.doctor_visits._available(scan.world,doctor_id) and _stay(scan).get("phase","")=="recovery": ready = true; break
		if not _visit(scan).get("final_result","").is_empty(): break
		if not _step_checked(scan,errors): break
	if not ready:
		return _result(scan,{"fresh_ward":true,"released_schedule":changed.accepted,"eligible_scan_boundary":false},{"name":"social_prerequisite","errors":errors,"tick":scan.world.sim_tick,"doctor":scan.world.facts.staff[doctor_id].duplicate(true)})
	var scan_input: Dictionary = _freeze_context(scan)
	var scan_hash: String = _facts_hash(scan_input.facts)
	var setup_ms: int = Time.get_ticks_msec()-started
	var active_source: Dictionary = _near_discharge_scan_input(producer,ward)
	var active_hash: String = _facts_hash(active_source.facts) if not active_source.is_empty() else ""
	var active_case: Dictionary = _visit_during_discharge(active_source) if not active_source.is_empty() else {"name":"active_visit_is_not_discharge_gate","ok":false,"reason":"Could not align a real admission with a scan near actual settlement","fixture_errors":producer.get("_fixture_failures")}
	var runs: Array = [_visit_positive(scan_input,doctor_id),_visit_rejections(scan_input,doctor_id),_visit_priority(scan_input,doctor_id),_discharge_without_visit(ward),active_case]
	var immutable: bool = _facts_hash(ward.facts)==ward_hash and _facts_hash(scan_input.facts)==scan_hash and (active_source.is_empty() or _facts_hash(active_source.facts)==active_hash)
	return {"ok":changed.accepted and immutable and runs.all(func(row: Dictionary)->bool:return row.ok),"setup_ms":setup_ms,"sources":{"ward_care":{"sha256":ward_hash,"freshly_built":true,"prefix":ward.prefix,"staff":ward.facts.staff.size(),"facilities":ward.facts.facilities.size()},"eligible_scan":{"sha256":scan_hash,"tick":scan_input.facts.sim_tick,"doctor_id":doctor_id,"schedule_command":changed.to_record()}},"immutable_sources":immutable,"runs":runs}

func _visit_positive(source: Dictionary, doctor_id: String) -> Dictionary:
	var c: Dictionary = _clone(source)
	_seed_communication(c.world,true)
	var checks: Dictionary = {"original_doctor_history":_is_original(c,doctor_id),"probability_and_scan":int(_content.balance.doctor_visits.probability_bp)==2500 and float(_content.balance.doctor_visits.scan_seconds)==60.0,"actual_visit_started":false,"actual_move":false,"cold_restore":false,"actual_six_seconds":false,"safe_bedside":true,"no_clinical_ownership":true,"normal_recovery_rate":true,"same_day_decision_preserved":true,"returned_safely":false,"no_extra_income_or_supplies":false}
	var baseline_income: int = _income(c)
	var baseline_units: int = _units_used(c)
	var work: int = 0
	var started_tick: int = -1
	var restored: Dictionary = {}
	var errors: Array = []
	var initial_day: int = c.world.sim_tick/WorldState.TICKS_PER_DAY
	var target: Dictionary = {}
	for index: int in 900:
		var before: Dictionary = c.world.facts.staff[doctor_id].life_task.duplicate(true)
		var before_stay: Dictionary = _stay(c).duplicate(true)
		if not _step_checked(c,errors,before.get("phase","")=="visiting"): break
		var staff: Dictionary = c.world.facts.staff[doctor_id]
		var task: Dictionary = staff.life_task
		if task.get("kind","")=="doctor_visit": checks.actual_visit_started = true
		if task.get("phase","")=="visit_travel" and c.world.facts.moves.has(doctor_id):
			checks.actual_move = true
			if restored.is_empty():
				var facts: Dictionary = c.world.freeze()
				restored = _roundtrip(c)
				checks.cold_restore = restored.get("ok",false) and c.world.freeze()==facts
				if not checks.cold_restore: break
				staff = c.world.facts.staff[doctor_id]; task = staff.life_task
		var advanced: int = 0
		if before.get("phase","")=="visiting": advanced = int(before.remaining_ticks)-int(task.get("remaining_ticks",0))
		elif task.get("phase","")=="visiting": advanced = 60-int(task.remaining_ticks)
		if advanced>0:
			work += advanced
			if started_tick<0: started_tick = c.world.sim_tick-1
			var position: Dictionary = before if before.get("phase","")=="visiting" else task
			var bed: Dictionary = c.world.facts.facilities[_stay(c).bed_id]
			var distance: float = Vector2(float(position.cell[0]),float(position.cell[1])).distance_to(Vector2(float(bed.patient_cell[0]),float(bed.patient_cell[1])))
			checks.safe_bedside = checks.safe_bedside and advanced==1 and distance<=3.0 and c.sim.space.at(c.world,doctor_id,int(position.floor_id),position.cell) and c.sim.space.public_areas.safe_wait(c.world,doctor_id,int(position.floor_id),position.cell)
		for session: Dictionary in c.world.facts.sessions.values(): checks.no_clinical_ownership = checks.no_clinical_ownership and not doctor_id in session.staff_ids
		for held: Dictionary in c.world.facts.adaptations.values(): checks.no_clinical_ownership = checks.no_clinical_ownership and not doctor_id in held.get("staff_ids",[])
		if not before_stay.is_empty() and not _stay(c).is_empty() and int(before_stay.remaining_ticks)>0: checks.normal_recovery_rate = checks.normal_recovery_rate and int(before_stay.remaining_ticks)-int(_stay(c).remaining_ticks)==1
		if checks.actual_visit_started: checks.same_day_decision_preserved = checks.same_day_decision_preserved and int(staff.social_visit_day)==initial_day
		if task.get("phase","") in ["returning","release"]: target = {"floor_id":task.floor_id,"cell":task.cell.duplicate()}
		if staff.has("last_doctor_visit") and task.phase=="idle" and not c.world.facts.moves.has(doctor_id):
			checks.returned_safely = not target.is_empty() and c.sim.space.at(c.world,doctor_id,int(target.floor_id),target.cell)
			break
		if index==0 and not checks.actual_visit_started: break
	checks.actual_six_seconds = work==60 and c.world.facts.staff[doctor_id].get("last_doctor_visit",{}).get("visit_id","")==c.visit_id and int(c.world.facts.staff[doctor_id].get("last_doctor_visit",{}).get("completed_tick",-1))-started_tick+1==60
	checks.no_extra_income_or_supplies = _income(c)==baseline_income and _units_used(c)==baseline_units
	return _result(c,checks,{"name":"original_doctor_actual_visit","doctor_id":doctor_id,"work_ticks":work,"started_tick":started_tick,"last_visit":c.world.facts.staff[doctor_id].get("last_doctor_visit",{}).duplicate(true),"restore":restored,"errors":errors,"final_tick":c.world.sim_tick})

func _visit_rejections(source: Dictionary, doctor_id: String) -> Dictionary:
	var c: Dictionary = _clone(source)
	var owner: RefCounted = c.sim.services.wellbeing.doctor_visits
	var checks: Dictionary = {"non_original_does_not_decide":false,"assigned_doctor_does_not_decide":false,"failed_probability_one_daily_decision":false,"same_day_no_second_draw":false,"cold_restore_no_second_draw":false}
	var bystander: String = "clin_round"
	var before: Dictionary = c.world.freeze()
	owner.consider(c.world,bystander)
	checks.non_original_does_not_decide = not _is_original(c,bystander) and c.world.freeze()==before and c.world.facts.staff[bystander].social_visit_day<0
	var assigned: CommandResult = _room_schedule(c,doctor_id,["room_gp"])
	before = c.world.freeze()
	owner.consider(c.world,doctor_id)
	checks.assigned_doctor_does_not_decide = assigned.accepted and c.world.freeze()==before and c.world.facts.staff[doctor_id].social_visit_day<0
	_room_schedule(c,doctor_id,[])
	_seed_communication(c.world,false)
	owner.consider(c.world,doctor_id)
	var day: int = c.world.sim_tick/WorldState.TICKS_PER_DAY
	checks.failed_probability_one_daily_decision = c.world.facts.staff[doctor_id].social_visit_day==day and c.world.facts.staff[doctor_id].life_task.phase=="idle"
	before = c.world.freeze()
	owner.consider(c.world,doctor_id)
	checks.same_day_no_second_draw = c.world.freeze()==before
	var restored: Dictionary = _roundtrip(c)
	before = c.world.freeze()
	c.sim.services.wellbeing.doctor_visits.consider(c.world,doctor_id)
	checks.cold_restore_no_second_draw = restored.get("ok",false) and c.world.freeze()==before
	return _result(c,checks,{"name":"relationship_schedule_and_daily_probability","schedule":assigned.to_record(),"restore":restored,"day":day})

func _visit_priority(source: Dictionary, doctor_id: String) -> Dictionary:
	var c: Dictionary = _clone(source)
	_seed_communication(c.world,true)
	var errors: Array = []
	_step_checked(c,errors)
	var started: bool = c.world.facts.staff[doctor_id].life_task.get("kind","")=="doctor_visit"
	var change: CommandResult = _room_schedule(c,doctor_id,["room_gp"])
	for index: int in 120:
		if not _step_checked(c,errors): break
		if c.world.facts.staff[doctor_id].life_task.phase=="idle": break
	var staff: Dictionary = c.world.facts.staff[doctor_id]
	return _result(c,{"visit_really_started":started,"clinical_schedule_applied":change.accepted,"social_stopped_safely":staff.life_task.phase=="idle" and not staff.has("last_doctor_visit"),"original_daily_decision_retained":staff.social_visit_day==c.world.sim_tick/WorldState.TICKS_PER_DAY,"actual_room_assignment":c.sim.services.scheduler.assignment(c.world,doctor_id,c.sim.services.scheduler.shift_index(c.world)).pools==["room_gp"]},{"name":"clinical_schedule_takes_priority","command":change.to_record(),"errors":errors})

func _discharge_without_visit(source: Dictionary) -> Dictionary:
	var c: Dictionary = _clone(source)
	var errors: Array = []
	var remaining: int = int(_stay(c).remaining_ticks)
	var work: int = 0
	var no_early: bool = true
	for index: int in 2400:
		if _stay(c).get("remaining_ticks",-1)==1 and _stay(c).get("care_completed",false): break
		var before: int = int(_stay(c).get("remaining_ticks",0))
		if not _step_checked(c,errors): break
		work += maxi(0,before-int(_stay(c).get("remaining_ticks",0)))
		no_early = no_early and _income(c,"ward")==0 and _income(c,"cure")==0
	var ready: bool = _stay(c).get("remaining_ticks",-1)==1 and _stay(c).get("care_completed",false)
	var before_tick: int = c.world.sim_tick
	_step_checked(c,errors,true)
	work += 1 if ready else 0
	var never_visited: bool = true
	for staff: Dictionary in c.world.facts.staff.values(): never_visited = never_visited and not staff.has("last_doctor_visit")
	var checks: Dictionary = {"actual_full_remaining_recovery":ready and work==remaining,"necessary_care_complete":_stay(c).get("care_completed",false),"no_early_final_fees":no_early,"no_social_visit_required":never_visited and _visit(c).get("final_result","")=="cured" and c.world.sim_tick==before_tick+1,"unique_original_settlement":_income(c)==505 and _income(c,"ward")==60 and _income(c,"cure")==360 and _units_used(c)==8 and _visit(c).attempt_ids.size()==1}
	return _result(c,checks,{"name":"no_visit_discharge_gate","remaining_at_input":remaining,"real_recovery_work_ticks":work,"settlement_tick":before_tick,"income":_income(c),"supply_units":_units_used(c),"errors":errors})

# Keep the full operation under test: natural admission, real treatment and
# original uninterrupted recovery. Only vary the time the patient enters so
# the actual next-to-last recovery boundary can intersect a scheduled scan.
func _near_discharge_scan_input(producer: RefCounted, ward: Dictionary) -> Dictionary:
	var scan_interval: int = ceili(float(_content.balance.doctor_visits.scan_seconds)/WorldState.TICK_SECONDS)
	var work_ticks: int = ceili(float(_content.balance.doctor_visits.interaction_seconds)/WorldState.TICK_SECONDS)
	var expected: int = _expected_settlement(ward)
	var desired: int = ceili(float(expected)/scan_interval)*scan_interval+work_ticks/2
	var admission: int = int(ward.facts.visits[ward.visit_id].arrived_tick)+desired-expected
	for variant: int in 3:
		var candidate: Dictionary = producer.call("_produce_ward_input",admission)
		if candidate.is_empty(): return {}
		var settlement: int = _expected_settlement(candidate)
		var previous_scan: int = (settlement-1)/scan_interval*scan_interval
		if settlement-previous_scan<work_ticks and int(candidate.facts.sim_tick)<previous_scan-scan_interval+1:
			return candidate
		# Recreate from the start with a corrected entry time if the changed
		# physical routes shifted the real boundary. Do not alter frozen facts.
		admission += desired-settlement
		if admission<=int(ward.facts.visits[ward.visit_id].arrived_tick): return {}
	return {}

func _expected_settlement(source: Dictionary) -> int:
	for stay: Dictionary in source.facts.ward_stays.values():
		if stay.visit_id==source.visit_id:
			return int(stay.entered_tick)+int(source.facts.attempts[stay.attempt_id].recovery_ticks)-1
	return -1

func _visit_during_discharge(source: Dictionary) -> Dictionary:
	var c: Dictionary = _clone(source)
	var errors: Array = []
	var doctor_id: String = str(c.doctors[0])
	var original_stay: Dictionary = _stay(c).duplicate(true)
	var attempt: Dictionary = c.world.facts.attempts[original_stay.attempt_id]
	var expected_tick: int = int(original_stay.entered_tick)+int(attempt.recovery_ticks)-1
	var scan_interval: int = ceili(float(_content.balance.doctor_visits.scan_seconds)/WorldState.TICK_SECONDS)
	var scan_tick: int = (expected_tick-1)/scan_interval*scan_interval
	var release_tick: int = scan_tick-scan_interval+1
	var initial_remaining: int = int(original_stay.remaining_ticks)
	var advanced: int = 0
	var normal_rate: bool = true
	var no_early_fees: bool = true
	while c.world.sim_tick<release_tick:
		var before: int = int(_stay(c).get("remaining_ticks",0))
		if not _step_checked(c,errors): break
		var work: int = before-int(_stay(c).get("remaining_ticks",0))
		advanced += maxi(0,work); normal_rate = normal_rate and work==1
		no_early_fees = no_early_fees and _income(c,"ward")==0 and _income(c,"cure")==0
	var schedule_tick: int = c.world.sim_tick
	var schedule: CommandResult = _room_schedule(c,doctor_id,[])
	while c.world.sim_tick<scan_tick:
		var before: int = int(_stay(c).get("remaining_ticks",0))
		if not _step_checked(c,errors): break
		var work: int = before-int(_stay(c).get("remaining_ticks",0))
		advanced += maxi(0,work); normal_rate = normal_rate and work==1
		no_early_fees = no_early_fees and _income(c,"ward")==0 and _income(c,"cure")==0
	var eligible: bool = c.world.sim_tick==scan_tick and c.world.facts.staff[doctor_id].life_task.phase=="idle" and not c.world.facts.moves.has(doctor_id) and c.sim.services.wellbeing.doctor_visits._available(c.world,doctor_id) and _stay(c).get("phase","")=="recovery"
	var checks: Dictionary = {"original_doctor":_is_original(c,doctor_id),"real_release_and_scheduled_scan":schedule.accepted and schedule_tick==release_tick and eligible,"actual_social_visit_started":false,"visit_unfinished_at_settlement":false,"normal_recovery_rate":false,"no_early_fees":false,"immediate_original_settlement":false}
	if not eligible: return _result(c,checks,{"name":"active_visit_is_not_discharge_gate","schedule_tick":schedule_tick,"scan_tick":c.world.sim_tick,"doctor":c.world.facts.staff[doctor_id].duplicate(true),"errors":errors})
	_seed_communication(c.world,true)
	var before_settlement: Dictionary = {}
	var actual_settlement: int = -1
	for index: int in 500:
		var tick: int = c.world.sim_tick
		var remaining: int = int(_stay(c).get("remaining_ticks",0))
		var before_task: Dictionary = c.world.facts.staff[doctor_id].life_task.duplicate(true)
		var completed_before: bool = c.world.facts.staff[doctor_id].has("last_doctor_visit")
		if not _step_checked(c,errors,remaining<=3 or before_task.get("phase","")=="visiting"): break
		var task: Dictionary = c.world.facts.staff[doctor_id].life_task
		checks.actual_social_visit_started = checks.actual_social_visit_started or task.get("kind","")=="doctor_visit"
		var work: int = remaining-int(_stay(c).get("remaining_ticks",0))
		advanced += maxi(0,work); normal_rate = normal_rate and work==1
		if _visit(c).get("final_result","")=="cured":
			actual_settlement = tick
			before_settlement = {"task":before_task,"doctor_location":c.world.facts.actors[doctor_id].location.duplicate(true),"completed_before":completed_before,"remaining_before":remaining,"tick_before":tick,"tick_after":c.world.sim_tick}
			checks.visit_unfinished_at_settlement = before_task.get("kind","")=="doctor_visit" and before_task.get("phase","") in ["visit_travel","visiting"] and not completed_before
			break
		no_early_fees = no_early_fees and _income(c,"ward")==0 and _income(c,"cure")==0
	checks.normal_recovery_rate = normal_rate and advanced==initial_remaining
	checks.no_early_fees = no_early_fees
	checks.immediate_original_settlement = actual_settlement==expected_tick and c.world.sim_tick==expected_tick+1 and _visit(c).get("final_result","")=="cured" and _stay(c).get("care_completed",false) and _income(c)==505 and _income(c,"ward")==60 and _income(c,"cure")==360 and _units_used(c)==8 and _visit(c).attempt_ids.size()==1
	return _result(c,checks,{"name":"active_visit_is_not_discharge_gate","schedule_tick":schedule_tick,"schedule":schedule.to_record(),"scan_tick":scan_tick,"expected_settlement_tick":expected_tick,"actual_settlement_tick":actual_settlement,"boundary":before_settlement,"remaining_at_input":initial_remaining,"actual_recovery_work_ticks":advanced,"income":_income(c),"supply_units":_units_used(c),"errors":errors})

func _measure_need(c: Dictionary, staff_id: String, before: Dictionary, rows: Dictionary) -> void:
	var after: Dictionary = c.world.facts.staff[staff_id].life_task
	var source: Dictionary = after if after.get("kind","")=="amenity" else before
	if source.get("kind","")!="amenity": return
	var id: String = str(source.id)
	var row: Dictionary = rows.get_or_add(id,{"purpose":str(source.purpose),"requested_tick":c.world.sim_tick-1,"work_ticks":0,"work_steps":0,"at_facility":true})
	var used: int = 0
	if before.get("phase","")=="using": used = int(before.remaining_ticks)-int(after.get("remaining_ticks",0))
	elif after.get("phase","")=="using": used = 80-int(after.remaining_ticks)
	if after.get("phase","")=="using" and after.has("use_started_tick"): row.use_started_tick = int(after.use_started_tick)
	if used>0:
		row.work_ticks += used; row.work_steps += 1
		var facility_id: String = str(source.get("facility_id",""))
		var facility: Dictionary = c.sim.space.facility_layout(c.world,facility_id)
		row.at_facility = row.at_facility and used==1 and not facility.is_empty() and c.sim.space.at(c.world,staff_id,int(facility.floor_id),facility.patient_cell)
	for key: String in ["completed_tick","finished_tick"]:
		if source.has(key): row[key] = source[key]
	if after.phase=="idle":
		row.returned_tick = c.world.sim_tick
		row.clock_at_return = c.world.facts.staff[staff_id].amenity_clock.duplicate(true)

func _full_use(row: Dictionary) -> bool:
	return row.has("completed_tick") and row.has("use_started_tick") and int(row.work_ticks)==80 and int(row.work_steps)==80 and row.at_facility and int(row.completed_tick)-int(row.use_started_tick)+1==80

func _gathering_owners(c: Dictionary, staff_id: String) -> Dictionary:
	var result: Dictionary = {}
	for id: String in c.world.facts.adaptations:
		var held: Dictionary = c.world.facts.adaptations[id]
		if c.world.facts.tickets.has(str(held.get("owner_id",""))) and staff_id in held.get("staff_ids",[]): result[id] = {"owner_id":held.owner_id,"staff_ids":held.staff_ids.duplicate()}
	return result

func _room_schedule(c: Dictionary, staff_id: String, rooms: Array) -> CommandResult:
	return _command(c,"apply_schedule",{"changes":[{"staff_id":staff_id,"schedule":_schedule("outpatient",rooms)}]})

func _is_original(c: Dictionary, staff_id: String) -> bool:
	var history: Dictionary = c.world.facts.patient_experience.experience[c.visit_id].completed_services
	for record: Dictionary in history.values():
		if record.kind in ["gp","surgery"] and not record.staff_ids.is_empty() and record.staff_ids[0]==staff_id: return true
	return false

func _seed_communication(world: WorldState, success: bool) -> void:
	for seed_value: int in 1000:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value+901
		var initial: Dictionary = {"algorithm":"godot-pcg32-4.7.2","seed_decimal":str(rng.seed),"state_decimal":str(rng.state)}
		if (rng.randi_range(0,9999)<2500)==success:
			world.facts.rng.communication = initial
			return

func _context_record(sim: HospitalSimulation, world: WorldState) -> Dictionary:
	return {"sim":sim,"world":world,"serial":0,"visit_id":"","doctors":[],"started":{},"group_seen":false,"beats":{},"errors":[],"fixture_ready":true,"capture_events":true,"event_log":[],"nursing_handoff_ticks":{},"nursing_handoff_not_at_base":[]}

func _freeze_context(c: Dictionary) -> Dictionary:
	var result: Dictionary = {"facts":c.world.freeze(),"visit_id":c.visit_id,"serial":c.serial,"doctors":c.doctors.duplicate(),"started":c.started.duplicate(),"group_seen":c.group_seen,"beats":c.beats.duplicate(),"capture_events":true,"event_log":c.event_log.duplicate(true),"nursing_handoff_ticks":c.nursing_handoff_ticks.duplicate(true),"nursing_handoff_not_at_base":c.nursing_handoff_not_at_base.duplicate(true)}
	return result

func _clone(source: Dictionary) -> Dictionary:
	var world := WorldState.new(source.facts.duplicate(true))
	var sim := HospitalSimulation.new(world,_content)
	_simulations.append(sim)
	var result: Dictionary = source.duplicate(true)
	result.erase("facts"); result.world = world; result.sim = sim; result.errors = []
	return result

func _step_checked(c: Dictionary, errors: Array, full: bool = false) -> bool:
	_tick(c)
	var overlap: Array = _body_overlap(c)
	var validation: String = c.world.validate(_content) if full or c.world.sim_tick%100==0 else ""
	if not overlap.is_empty() or not validation.is_empty(): errors.append({"tick":c.world.sim_tick,"overlap":overlap,"validation":validation}); return false
	return true

func _result(c: Dictionary, checks: Dictionary, details: Dictionary) -> Dictionary:
	checks.world_valid = c.world.validate(_content).is_empty()
	checks.real_bodies = _body_overlap(c).is_empty()
	checks.no_step_errors = details.get("errors",[]).is_empty()
	details.checks = checks
	details.ok = _passed(checks)
	if not details.ok: details.failure_world = _failure_world("STAFF-ROOM-LIFE",c.world)
	return details

func _passed(checks: Dictionary) -> bool:
	return checks.values().all(func(value: Variant)->bool:return value==true)

func _facts_hash(value: Dictionary) -> String:
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(var_to_bytes(value))
	return hash_context.finish().hex_encode()

func _body_overlap(c: Dictionary) -> Array:
	var bodies: Array = []
	for actor: Dictionary in c.world.facts.actors.values():
		if actor.location.kind=="floor": bodies.append({"id":actor.id,"floor":actor.location.floor_id,"body":c.sim.space.body_rectangle(actor)})
	for index: int in bodies.size():
		for other: int in range(index+1,bodies.size()):
			if bodies[index].floor==bodies[other].floor and bodies[index].body.intersects(bodies[other].body,false): return [bodies[index].id,bodies[other].id]
	return []
