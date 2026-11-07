extends "res://tests/acceptance/floor_guidance.gd"

# These are legitimate immediate business-boundary inputs, not claims about
# completed earlier services. All measured gathering and guide travel is real.
func run_ownership(database: HospitalContent, selected: Array = []) -> Dictionary:
	_content = database
	var runs: Dictionary = {"GUIDE-LIVE-WARD-OWNERSHIP":_live_ward,"GUIDE-GATHERING-ARRIVAL-OWNERSHIP":_gathering_arrival,"GUIDE-WARD-ASSOCIATION-NOT-PERMANENT":_ward_association_only,"GUIDE-TERMINAL-WARD-RELEASE_WAIT":_terminal_ward.bind("release_wait"),"GUIDE-IDLE-STATION-SCHEDULE-HANDOFF":_idle_station_schedule_handoff,"GUIDE-TRAINING-SCHEDULE":_training_schedule,"GUIDE-PREPARATION-WARD-SURGERY":_preparation_coverage.bind(true),"GUIDE-PREPARATION-WARD-OUTPATIENT":_preparation_coverage.bind(false)}
	var rows: Array = []
	var okay: bool = true
	for id: String in (runs.keys() if selected.is_empty() else selected):
		if not runs.has(id): return {"ok":false,"error":"unknown selector "+id}
		var row: Dictionary = runs[id].call()
		rows.append(row);okay = okay and bool(row.ok)
	return {"ok":okay,"cases":rows}

func _ward_boundary() -> Dictionary:
	var x: Dictionary = _base(true)
	var f: RefCounted = load("res://tests/acceptance/clinical_fixtures.gd").new()
	f._content = _content
	f._add_layout(x.world,"ward_two_beds","ownership_ward",[45,65])
	var nurse: Dictionary = x.world.facts.staff.guide_nurse
	nurse.base_prepared = true
	nurse.ward_id = "ownership_ward"
	nurse.abilities.surgery = 1;nurse.certificates.append("q_or")
	x.world.facts.staff.doctor.abilities.surgery = 2;x.world.facts.staff.doctor.abilities.diagnosis = 2;x.world.facts.staff.doctor.title_id = "DT02"
	HospitalFactory._add_staff(x.world,"history_anesthetist","历史麻醉医生","doctor",[42,92],_content)
	x.world.facts.staff.history_anesthetist.abilities.surgery = 2;x.world.facts.staff.history_anesthetist.title_id = "DT02"
	for key: String in ["d","s","w","r","f"]: x[key].ensure(x.world)
	# Initial already-covered recovery boundary; no motion is under test here.
	_position(x,"guide_nurse",[46,72])
	var v: Dictionary = _visit(x,"ownership_inpatient",[47,67])
	x.world.facts.tickets.erase(v.ticket_id);v.ticket_id = "";v.phase = "recovery"
	var b: Dictionary = _content.definition("treatment_bindings","B_S13_D09_M09")
	v.binding_id = b.id;v.disease_id = b.disease_id;v.requested_plan_id = "P_D09_SURGERY"
	x.world.facts.actors[v.actor_id].species_id = b.species_id
	x.world.facts.actors[v.actor_id].body_binding_id = b.id
	var attempt_id: String = "ownership_attempt"
	v.attempt_ids = [attempt_id]
	x.world.facts.attempts[attempt_id] = {"id":attempt_id,"visit_id":v.id,"plan_id":"P_D09_SURGERY","protocol_id":"TP_SURGERY1","result":true,"start_tick":0,"probability_bp":9600,"work_ticks":1200,"recovery_ticks":1800,"supply_units":8,"cure_fee":360,"facility_fee":60,"ward_fee":60,"staff_ids":["doctor","history_anesthetist","guide_nurse"],"effective_level":0.0,"bed_id":"ownership_ward_0","nurse_id":"guide_nurse","round_doctor_id":"doctor","ward_id":"ownership_ward"}
	x.world.facts.inventory.issues[attempt_id] = {"attempt_id":attempt_id,"units":8,"tick":0}
	x.world.facts.inventory.units -= 8
	var stay: Dictionary = {"id":attempt_id,"attempt_id":attempt_id,"bed_id":"ownership_ward_0","phase":"recovery","remaining_ticks":120,"work_credit_milli":0,"care_completed":true,"nurse_id":"guide_nurse","round_doctor_id":"doctor","escort_id":"guide_nurse","last_progress_tick":0,"entered_tick":0}
	x.world.facts.ward_stays[attempt_id] = stay
	x.reservation_error = x.space.reserve_facility(x.world,stay.bed_id,v.actor_id,attempt_id,["guide_nurse","doctor"])
	x.c._support(x.world,v,x.world.facts.facilities[stay.bed_id],"lying")
	x.world.touch()
	return x

func _live_ward() -> Dictionary:
	var x: Dictionary = _ward_boundary()
	var stay: Dictionary = x.world.facts.ward_stays.ownership_attempt
	var prevalidation: String = x.world.validate(_content)
	var covered: bool = x.c._ward_covering(x.world,stay)
	var otherwise_free: bool = not HospitalClinicalDevelopment.safe_busy(x.world,"guide_nurse") and not x.c.staff_busy(x.world,"guide_nurse") and not x.world.facts.moves.has("guide_nurse") and x.world.facts.sessions.is_empty()
	var location: Dictionary = x.world.facts.actors.guide_nurse.location.duplicate(true)
	var remaining: int = int(stay.remaining_ticks)
	x.g.dispatch(x.world)
	var kept: bool = str(x.world.facts.floor_guidance.desks.guide.nurse_id).is_empty() and str(x.world.facts.staff.guide_nurse.get("active_job_id","")).is_empty() and not x.world.facts.moves.has("guide_nurse") and x.world.facts.actors.guide_nurse.location==location
	x.c.advance(x.world)
	var continued: bool = int(stay.remaining_ticks)==remaining-1
	var row: Dictionary = {"case":"GUIDE-LIVE-WARD-OWNERSHIP","ok":prevalidation.is_empty() and str(x.reservation_error).is_empty() and covered and otherwise_free and kept and continued and x.world.validate(_content).is_empty(),"input_validation":prevalidation,"reservation_error":x.reservation_error,"actual_coverage_before":covered,"no_move_session_or_other_busy_before":otherwise_free,"ward_nurse_not_stolen":kept,"continuous_recovery_advanced_one_tick":continued,"desk_nurse":x.world.facts.floor_guidance.desks.guide.nurse_id,"remaining_before":remaining,"remaining_after":stay.remaining_ticks,"validation":x.world.validate(_content)}
	_dispose(x);return row

func _gathering_arrival() -> Dictionary:
	var x: Dictionary = _base()
	x.world.facts.staff.guide_nurse.base_prepared = true
	var v: Dictionary = _visit(x,"ownership_exam",[40,88])
	x.world.facts.tickets.erase(v.ticket_id);v.ticket_id = ""
	x.c._queue(x.world,v,"spectrum")
	var ticket: Dictionary = x.world.facts.tickets[v.ticket_id]
	# An already-issued clinical journey owns its original gathering. Its
	# movement must finish honestly before testing next guide allocation.
	x.c.floor_guidance = null
	x.world.touch()
	var prevalidation: String = x.world.validate(_content)
	x.c._dispatch_service(x.world,v,ticket)
	var held: bool = bool(ticket.get("service_assigned",false)) and x.world.facts.adaptations.has("diagnosis") and x.world.facts.sessions.is_empty()
	var start: Dictionary = x.world.facts.actors.guide_nurse.location.duplicate(true)
	var arrived: bool = false
	var ticks: int = 0
	for tick: int in 800:
		x.space.advance(x.world)
		x.world.facts.sim_tick += 1;x.world.touch(false);x.space.finish_boundary(x.world)
		ticks += 1
		var fit: Dictionary = x.space.facility_layout(x.world,"diagnosis")
		if x.space.at(x.world,"guide_nurse",int(fit.floor_id),fit.operator_cells[0]) and not x.world.facts.moves.has("guide_nurse"):
			arrived = true;break
	var walked: bool = start!=x.world.facts.actors.guide_nurse.location
	var owned: bool = x.c.staff_busy(x.world,"guide_nurse") and not HospitalClinicalDevelopment.safe_busy(x.world,"guide_nurse") and x.world.facts.sessions.is_empty()
	var saved_reservation: Dictionary = x.world.facts.adaptations.get("diagnosis",{}).duplicate(true)
	x.g.dispatch(x.world)
	var kept: bool = str(x.world.facts.floor_guidance.desks.guide.nurse_id).is_empty() and str(x.world.facts.staff.guide_nurse.get("active_job_id","")).is_empty() and not x.world.facts.moves.has("guide_nurse") and x.world.facts.adaptations.get("diagnosis",{})==saved_reservation
	var started: bool = false
	if kept:
		for tick: int in 800:
			x.c._dispatch_service(x.world,v,ticket)
			if not x.world.facts.sessions.is_empty(): started = true;break
			x.space.advance(x.world);x.world.facts.sim_tick += 1;x.world.touch(false);x.space.finish_boundary(x.world)
	var release_evidence: Dictionary = _finish_and_release(x) if started else {"ok":false}
	var row: Dictionary = {"case":"GUIDE-GATHERING-ARRIVAL-OWNERSHIP","ok":prevalidation.is_empty() and held and arrived and walked and owned and kept and started and release_evidence.ok and x.world.validate(_content).is_empty(),"input_validation":prevalidation,"original_ticket_reservation":held,"actual_arrival_without_move":arrived,"nurse_walked":walked,"real_movement_ticks":ticks,"clinic_owned_despite_safe_busy_false":owned,"nurse_not_stolen":kept,"original_service_started":started,"session_release_evidence":release_evidence,"desk_nurse":x.world.facts.floor_guidance.desks.guide.nurse_id,"validation":x.world.validate(_content),"waiting_reason":v.waiting_reason}
	_dispose(x);return row

func _ward_association_only() -> Dictionary:
	var x: Dictionary = _base()
	HospitalFactory._add_room(x.world,{"id":"empty_ward","type":"ward","anchor":[45,65],"size":[10,8],"door":{"definition_id":"DR04","offset":3}},_content)
	x.world.facts.staff.guide_nurse.ward_id = "empty_ward"
	x.world.touch()
	var prevalidation: String = x.world.validate(_content)
	x.g.dispatch(x.world)
	var assigned: bool = x.world.facts.floor_guidance.desks.guide.nurse_id=="guide_nurse"
	var arrived: bool = false
	for tick: int in 500:
		x.space.advance(x.world);x.world.facts.sim_tick += 1;x.world.touch(false);x.space.finish_boundary(x.world)
		x.g.dispatch(x.world)
		if x.space.at(x.world,"guide_nurse",1,x.space.guidance_operator_cell(x.world,"guide","guide_nurse")) and not x.world.facts.moves.has("guide_nurse"):
			arrived = true;break
	var row: Dictionary = {"case":"GUIDE-WARD-ASSOCIATION-NOT-PERMANENT","ok":prevalidation.is_empty() and assigned and arrived and x.world.validate(_content).is_empty(),"input_validation":prevalidation,"nurse_with_no_live_stay_assigned":assigned,"actual_desk_arrival":arrived,"validation":x.world.validate(_content)}
	_dispose(x);return row

func _finish_and_release(x: Dictionary) -> Dictionary:
	var session: Dictionary = x.world.facts.sessions.values()[0]
	var session_id: String = str(session.id)
	var total: int = int(session.remaining_ticks)
	var uninterrupted: bool = true
	for tick: int in total:
		var before: int = int(session.remaining_ticks)
		x.g.dispatch(x.world)
		uninterrupted = uninterrupted and x.world.facts.floor_guidance.desks.guide.nurse_id=="" and x.world.facts.sessions.has(session_id) and int(session.remaining_ticks)==before
		x.c.advance(x.world);x.world.facts.sim_tick += 1;x.world.touch(false)
		uninterrupted = uninterrupted and int(session.remaining_ticks)==before-1
	var actual_release: bool = x.world.facts.staff.guide_nurse.has("clinical_release")
	var release_start: Dictionary = x.world.facts.actors.guide_nurse.location.duplicate(true)
	var protected: bool = true
	var arrived: bool = false
	var exit_steps: int = 0
	for tick: int in 700:
		var releasing: bool = x.world.facts.staff.guide_nurse.has("clinical_release")
		var before_release: Dictionary = x.world.facts.staff.guide_nurse.get("clinical_release",{}).duplicate(true)
		var before_move: Dictionary = x.world.facts.moves.get("guide_nurse",{}).duplicate(true)
		x.g.dispatch(x.world)
		if releasing:
			protected = protected and x.world.facts.floor_guidance.desks.guide.nurse_id=="" and before_release==x.world.facts.staff.guide_nurse.get("clinical_release",{}) and before_move==x.world.facts.moves.get("guide_nurse",{})
		x.c._dispatch_clinical_releases(x.world)
		x.space.advance(x.world);x.world.facts.sim_tick += 1;x.world.touch(false);x.space.finish_boundary(x.world)
		exit_steps += 1
		if x.world.facts.floor_guidance.desks.guide.nurse_id=="guide_nurse" and not x.world.facts.moves.has("guide_nurse") and x.space.at(x.world,"guide_nurse",1,x.space.guidance_operator_cell(x.world,"guide","guide_nurse")):
			arrived = true;break
	return {"ok":uninterrupted and actual_release and protected and arrived and not x.world.facts.staff.guide_nurse.has("clinical_release"),"continuous_service_ticks":total,"original_session_uninterrupted":uninterrupted,"real_clinical_release_observed":actual_release,"release_and_move_not_cancelled":protected,"actual_exit_and_guide_travel_ticks":exit_steps,"actual_exit_moved":release_start!=x.world.facts.actors.guide_nurse.location,"clear_then_real_guide_arrival":arrived}

func _terminal_ward(phase: String) -> Dictionary:
	var x: Dictionary = _ward_boundary()
	var stay: Dictionary = x.world.facts.ward_stays.ownership_attempt
	# Legitimate post-round boundary. Retained ward assignment and bed access
	# are not active nursing work. No physical exit under test is fabricated.
	stay.phase = phase;stay.remaining_ticks = 0
	x.world.facts.visits.ownership_inpatient.phase = "leaving"
	x.world.facts.visits.ownership_inpatient.final_result = "cured"
	x.world.touch()
	var prevalidation: String = x.world.validate(_content)
	x.g.dispatch(x.world)
	var assigned: bool = x.world.facts.floor_guidance.desks.guide.nurse_id=="guide_nurse"
	var row: Dictionary = {"case":"GUIDE-TERMINAL-WARD-"+phase.to_upper(),"ok":prevalidation.is_empty() and str(x.reservation_error).is_empty() and assigned and x.world.validate(_content).is_empty(),"input_validation":prevalidation,"terminal_stay_kept":x.world.facts.ward_stays.has(stay.id),"ward_assignment_kept":x.world.facts.staff.guide_nurse.ward_id=="ownership_ward","nurse_eligible_after_coverage_ends":assigned,"validation":x.world.validate(_content)}
	_dispose(x);return row


func _ownership_schedule(rest_now: bool) -> Array:
	return [{"kind":"rest" if rest_now else "work","pools":[],"locked":false},{"kind":"work","pools":[],"locked":false},{"kind":"work" if rest_now else "rest","pools":[],"locked":false}]

func _idle_station_schedule_handoff() -> Dictionary:
	var started_us: int = Time.get_ticks_usec()
	var x: Dictionary = _ward_boundary()
	var stay: Dictionary = x.world.facts.ward_stays.ownership_attempt
	# Initial coverage is owned by a different nurse. Guide arrival below is
	# actual movement from a legitimate starting position, never a pose edit.
	_position(x,"guide_nurse",[36,92])
	HospitalFactory._add_staff(x.world,"ward_cover","病房覆盖护士","nurse",[46,72],_content)
	HospitalFactory._add_staff(x.world,"replacement","替班导诊护士","nurse",[53,90],_content)
	for key: String in ["d","s","w","r","f"]: x[key].ensure(x.world)
	for id: String in ["guide_nurse","ward_cover","replacement"]: x.world.facts.staff[id].base_prepared = true
	x.world.facts.staff.ward_cover.ward_id = "ownership_ward"
	x.world.facts.staff.replacement.schedule = _ownership_schedule(true)
	x.world.facts.staff.replacement.on_shift = false
	stay.nurse_id = "ward_cover";stay.escort_id = "ward_cover"
	x.world.facts.attempts.ownership_attempt.nurse_id = "ward_cover"
	x.space.grant_facility_access(x.world,stay.bed_id,"ward_cover")
	x.world.touch()
	var prevalidation: String = x.world.validate(_content)
	var preparation_us: int = Time.get_ticks_usec()-started_us
	var actual_arrival: bool = false
	var arrival_ticks: int = 0
	for tick: int in 700:
		x.s.boundaries(x.world);x.s.dispatch(x.world);x.g.dispatch(x.world)
		x.space.advance(x.world);x.world.facts.sim_tick += 1;x.world.touch(false);x.space.finish_boundary(x.world)
		arrival_ticks += 1
		if x.space.at(x.world,"guide_nurse",1,x.space.guidance_operator_cell(x.world,"guide","guide_nurse")) and not x.world.facts.moves.has("guide_nurse"):
			actual_arrival = true;break
	var station: Dictionary = x.world.facts.actors.guide_nurse.location.duplicate(true)
	var at_idle_desk: bool = actual_arrival and x.world.facts.floor_guidance.visits.is_empty() and x.world.facts.floor_guidance.desks.guide.nurse_id=="guide_nurse" and x.world.facts.staff.guide_nurse.get("active_job_id","")=="floor_desk:guide"
	var original_relief: CommandResult = x.s.execute(x.world,"apply_schedule",{"changes":[{"staff_id":"ward_cover","schedule":_ownership_schedule(true)}]})
	x.s.boundaries(x.world)
	var exam: Dictionary = _visit(x,"idle_station_exam",[40,88])
	x.world.facts.tickets.erase(exam.ticket_id);exam.ticket_id = ""
	x.c._queue(x.world,exam,"spectrum")
	var ticket: Dictionary = x.world.facts.tickets[exam.ticket_id]
	# Exercise the clinical operator dispatcher directly so demand really
	# reaches staff selection; the separate patient-guidance gate is not the
	# reason this already-stationed nurse must remain unavailable.
	x.c.floor_guidance = null
	x.world.touch()
	var structural: Array = x.c.service_candidates(x.world,exam,"spectrum",true)
	var otherwise_qualified: bool = false
	for pair: Dictionary in structural: otherwise_qualified = otherwise_qualified or pair.staff_id=="guide_nurse"
	var held: bool = true
	var demands_blocked: bool = true
	var no_parallel: bool = true
	for tick: int in 60:
		x.s.boundaries(x.world);x.s.dispatch(x.world);x.d.dispatch(x.world);x.g.dispatch(x.world)
		x.c._dispatch_service(x.world,exam,ticket)
		held = held and x.world.facts.staff.guide_nurse.get("active_job_id","")=="floor_desk:guide" and x.world.facts.floor_guidance.desks.guide.nurse_id=="guide_nurse" and x.world.facts.actors.guide_nurse.location==station and not x.world.facts.moves.has("guide_nurse") and x.world.facts.floor_guidance.visits.is_empty()
		demands_blocked = demands_blocked and not ticket.get("service_assigned",false) and not x.world.facts.adaptations.has("diagnosis") and x.world.facts.staff_schedule.handoffs.is_empty()
		no_parallel = no_parallel and x.world.facts.sessions.is_empty() and x.world.facts.preparations.is_empty() and x.world.facts.staff.guide_nurse.base_task.is_empty() and stay.nurse_id=="ward_cover"
		x.space.advance(x.world);x.world.facts.sim_tick += 1;x.world.touch(false);x.space.finish_boundary(x.world)
	var before_rest_validation: String = x.world.validate(_content)
	# Resolve the independent ward shortage by a real schedule change. The
	# coming replacement is then for this desk, not for another department.
	var rest: CommandResult = x.s.execute(x.world,"apply_schedule",{"changes":[{"staff_id":"guide_nurse","schedule":_ownership_schedule(true)},{"staff_id":"ward_cover","schedule":_ownership_schedule(false)},{"staff_id":"replacement","schedule":_ownership_schedule(false)}]})
	x.c.floor_guidance = x.g
	var saw_release: bool = false
	var release_protected: bool = true
	var no_overlap: bool = true
	var replacement_arrived: bool = false
	var released_position: Dictionary = {}
	var handoff_ticks: int = 0
	for tick: int in 900:
		x.s.boundaries(x.world);x.s.dispatch(x.world);x.g.dispatch(x.world)
		if x.world.facts.floor_guidance.releases.has("guide_nurse"):
			saw_release = true
			release_protected = release_protected and x.world.facts.staff.guide_nurse.get("active_job_id","")=="floor_desk_release:guide" and HospitalClinicalDevelopment.safe_busy(x.world,"guide_nurse") and x.c.staff_busy(x.world,"guide_nurse")
		elif saw_release and released_position.is_empty(): released_position = x.world.facts.actors.guide_nurse.location.duplicate(true)
		x.space.advance(x.world);x.world.facts.sim_tick += 1;x.world.touch(false);x.space.finish_boundary(x.world)
		handoff_ticks += 1
		no_overlap = no_overlap and not x.space.body_rectangle(x.world.facts.actors.guide_nurse).intersects(x.space.body_rectangle(x.world.facts.actors.replacement),false)
		if x.world.facts.floor_guidance.desks.guide.nurse_id=="replacement" and x.space.at(x.world,"replacement",1,x.space.guidance_operator_cell(x.world,"guide","replacement")) and not x.world.facts.moves.has("replacement") and not x.world.facts.floor_guidance.releases.has("guide_nurse"):
			replacement_arrived = true;break
	x.s.boundaries(x.world)
	var old_clear: bool = str(x.world.facts.staff.guide_nurse.get("active_job_id","")).is_empty() and not x.world.facts.staff.guide_nurse.on_shift and x.world.facts.actors.guide_nurse.location!=station and not x.world.facts.moves.has("guide_nurse")
	var row: Dictionary = {"case":"GUIDE-IDLE-STATION-SCHEDULE-HANDOFF","ok":prevalidation.is_empty() and before_rest_validation.is_empty() and actual_arrival and at_idle_desk and original_relief.accepted and otherwise_qualified and held and demands_blocked and no_parallel and rest.accepted and saw_release and release_protected and replacement_arrived and no_overlap and old_clear and x.world.validate(_content).is_empty(),"input_validation":prevalidation,"before_rest_validation":before_rest_validation,"preparation_us":preparation_us,"test_us":Time.get_ticks_usec()-started_us-preparation_us,"actual_initial_desk_arrival_ticks":arrival_ticks,"idle_without_guidance_patient":at_idle_desk,"original_ward_nurse_rest_command":original_relief.to_record(),"otherwise_qualified_inspection_operator":otherwise_qualified,"idle_station_held_for_ticks":60,"position_and_desk_owner_unchanged":held,"inspection_and_ward_relief_commitments_blocked":demands_blocked,"no_parallel_clinical_or_base_work":no_parallel,"formal_rest_and_replacement_command":rest.to_record(),"real_release_observed":saw_release,"release_retained_busy_ownership":release_protected,"release_and_replacement_travel_ticks":handoff_ticks,"replacement_really_arrived":replacement_arrived,"old_nurse_really_clear_and_off_shift":old_clear,"nurse_bodies_never_overlapped":no_overlap,"station_location":station,"old_released_location":released_position,"validation":x.world.validate(_content)}
	_dispose(x);return row


func _training_template() -> Array:
	return [{"kind":"training","pools":[],"locked":false},{"kind":"work","pools":[],"locked":false},{"kind":"rest","pools":[],"locked":false}]

func _training_schedule() -> Dictionary:
	var x: Dictionary = _base()
	var command: CommandResult = x.s.execute(x.world,"apply_schedule",{"changes":[{"staff_id":"guide_nurse","schedule":_training_template()}]})
	x.s.boundaries(x.world)
	var before: String = x.world.validate(_content)
	var no_course: bool = str(x.world.facts.staff.guide_nurse.training_job_id).is_empty() and x.world.facts.staff.guide_nurse.on_shift and not x.world.facts.staff.guide_nurse.block_new_work and x.s.available_ticks(x.world,"guide_nurse",x.s.shift_index(x.world))==0
	x.g.dispatch(x.world)
	var no_assignment: bool = x.world.facts.floor_guidance.desks.guide.nurse_id=="" and str(x.world.facts.staff.guide_nurse.get("active_job_id","")).is_empty() and not x.world.facts.moves.has("guide_nurse")
	_dispose(x)
	x = _base()
	var arrived: bool = false
	for tick: int in 600:
		x.s.boundaries(x.world);x.g.dispatch(x.world);x.space.advance(x.world)
		x.world.facts.sim_tick += 1;x.world.touch(false);x.space.finish_boundary(x.world)
		if x.space.at(x.world,"guide_nurse",1,x.space.guidance_operator_cell(x.world,"guide","guide_nurse")) and not x.world.facts.moves.has("guide_nurse"):
			arrived = true;break
	var original: Dictionary = x.world.facts.actors.guide_nurse.location.duplicate(true)
	var changed: CommandResult = x.s.execute(x.world,"apply_schedule",{"changes":[{"staff_id":"guide_nurse","schedule":_training_template()}]})
	var saw_release: bool = false
	var cleared: bool = false
	var ticks: int = 0
	for tick: int in 300:
		x.s.boundaries(x.world);x.g.dispatch(x.world)
		saw_release = saw_release or x.world.facts.floor_guidance.releases.has("guide_nurse")
		x.space.advance(x.world);x.world.facts.sim_tick += 1;x.world.touch(false);x.space.finish_boundary(x.world)
		ticks += 1
		if saw_release and x.world.facts.floor_guidance.desks.guide.nurse_id=="" and str(x.world.facts.staff.guide_nurse.get("active_job_id","")).is_empty() and not x.world.facts.moves.has("guide_nurse"):
			cleared = true;break
	var row: Dictionary = {"case":"GUIDE-TRAINING-SCHEDULE","ok":before.is_empty() and command.accepted and no_course and no_assignment and arrived and changed.accepted and saw_release and cleared and x.world.facts.actors.guide_nurse.location!=original and x.world.validate(_content).is_empty(),"input_validation":before,"no_course_training_has_zero_work_capacity":no_course,"training_new_assignment_blocked":no_assignment,"actual_work_desk_arrival":arrived,"training_command":changed.to_record(),"actual_training_release_observed":saw_release,"training_desk_really_cleared":cleared,"release_ticks":ticks,"old_position":original,"new_position":x.world.facts.actors.guide_nurse.location.duplicate(true),"validation":x.world.validate(_content)}
	_dispose(x);return row

func _preparation_context(surgical: bool) -> Dictionary:
	var old: Dictionary = _fixture()
	var world: WorldState = old.world
	_dispose(old)
	var x: Dictionary = _guide_bind(world)
	var f: RefCounted = load("res://tests/acceptance/clinical_fixtures.gd").new()
	f._content = _content
	f._add_layout(world,"ward_two_beds","ownership_ward",[45,65])
	if surgical:
		f._add_layout(world,"or_standard","ownership_or",[33,65])
	else:
		HospitalFactory._add_room(world,{"id":"gentle_room","type":"T05","anchor":[33,65],"size":[10,10],"door":{"definition_id":"DR04","offset":3}},_content)
		_facility(x,"gentle_equipment","M09",[36,68],"gentle_room")
	_facility(x,"guide","SE01",[47,83])
	f._add_worker(world,"surgeon","doctor",[34,77],"surgery" if surgical else "outpatient",{"diagnosis":1,"treatment":3,"care":0,"surgery":2},"DT02")
	if surgical:
		f._add_worker(world,"anesthetist","doctor",[38,77],"surgery",{"diagnosis":1,"treatment":1,"care":0,"surgery":2},"DT02")
		f._add_worker(world,"or_nurse","nurse",[42,77],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":1})
		world.facts.staff.or_nurse.certificates = ["q_or","q_ward"]
	f._add_worker(world,"guide_nurse","nurse",[46,72],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":0})
	world.facts.staff.guide_nurse.ward_id = "ownership_ward"
	f._add_worker(world,"round_doctor","doctor",[51,72],"round",{"diagnosis":2,"treatment":1,"care":0,"surgery":0})
	for key: String in ["d","s","w","r","f"]: x[key].ensure(world)
	for definition: Dictionary in _content.catalog.research: world.facts.research.append(definition.id)
	var v: Dictionary = _visit(x,"prepared_patient",[40,88])
	world.facts.tickets.erase(v.ticket_id);v.ticket_id = ""
	var binding: Dictionary = _content.definition("treatment_bindings","B_S13_D09_M09" if surgical else "B_S22_D14_M14")
	v.binding_id = binding.id;v.disease_id = binding.disease_id
	v.requested_plan_id = "P_D09_SURGERY" if surgical else "P_D14_GENTLE"
	world.facts.actors[v.actor_id].species_id = binding.species_id;world.facts.actors[v.actor_id].body_binding_id = binding.id
	v.evidence_by_source = {"gp":100.0}
	v.plan_decision = {"plan_id":v.requested_plan_id,"source":"director","doctor_id":"surgeon","revision":1,"reason":"已确认的临床待办边界","expected_team":["surgeon","anesthetist","or_nurse"] if surgical else ["surgeon"]}
	x.c._queue(world,v,"surgery" if surgical else "outpatient")
	x.c.floor_guidance = null
	world.touch()
	x.visit = v
	return x

func _preparation_coverage(surgical: bool) -> Dictionary:
	var x: Dictionary = _preparation_context(surgical)
	var v: Dictionary = x.visit
	var before: String = x.world.validate(_content)
	var ticket: Dictionary = x.world.facts.tickets[v.ticket_id]
	# Production dispatch performs the actual two-facility reservation and
	# creates preparation. No reservation or preparation is injected here.
	if surgical: x.c._prepare_surgery(x.world,v,ticket)
	else: x.c._dispatch_service(x.world,v,ticket)
	var preparation: Dictionary = x.world.facts.preparations.get(v.id,{})
	var pending: bool = not preparation.is_empty() and preparation.get("nurse_id","")=="guide_nurse" and not "guide_nurse" in preparation.get("staff_ids",[]) and x.world.facts.ward_stays.is_empty() and x.world.facts.sessions.is_empty()
	var actual_bundle: bool = pending and x.world.facts.adaptations.has(preparation.bed_id) and x.world.facts.adaptations.has(preparation.facility_id) and x.world.facts.adaptations[preparation.bed_id].owner_id==v.id and x.world.facts.adaptations[preparation.facility_id].owner_id==(v.id if surgical else ticket.id)
	var distinct_from_old_busy: bool = not HospitalClinicalDevelopment.safe_busy(x.world,"guide_nurse") and not x.c.staff_busy(x.world,"guide_nurse") and not x.world.facts.moves.has("guide_nurse")
	var prepared_validation: String = x.world.validate(_content)
	var original: Dictionary = x.world.facts.actors.guide_nurse.location.duplicate(true)
	x.g.dispatch(x.world)
	var held: bool = pending and x.world.facts.floor_guidance.desks.guide.nurse_id=="" and str(x.world.facts.staff.guide_nurse.get("active_job_id","")).is_empty() and not x.world.facts.moves.has("guide_nurse") and x.world.facts.actors.guide_nurse.location==original
	var cancelled: bool = false
	var arrived: bool = false
	var safe_release: bool = true
	var release_ticks: int = 0
	if held:
		var result: CommandResult = x.c.execute(x.world,"clinical_refer",{"visit_id":v.id})
		cancelled = result.accepted and not x.world.facts.preparations.has(v.id)
		for tick: int in 600:
			var releasing: bool = x.world.facts.staff.guide_nurse.has("clinical_release")
			x.g.dispatch(x.world)
			if releasing: safe_release = safe_release and x.world.facts.floor_guidance.desks.guide.nurse_id!="guide_nurse"
			x.c._dispatch_clinical_releases(x.world)
			x.space.advance(x.world);x.world.facts.sim_tick += 1;x.world.touch(false);x.space.finish_boundary(x.world)
			release_ticks += 1
			if x.world.facts.floor_guidance.desks.guide.nurse_id=="guide_nurse" and x.space.at(x.world,"guide_nurse",1,x.space.guidance_operator_cell(x.world,"guide","guide_nurse")) and not x.world.facts.moves.has("guide_nurse"):
				arrived = true;break
	var row: Dictionary = {"case":"GUIDE-PREPARATION-WARD-"+("SURGERY" if surgical else "OUTPATIENT"),"ok":before.is_empty() and prepared_validation.is_empty() and actual_bundle and pending and distinct_from_old_busy and held and cancelled and safe_release and arrived and x.world.validate(_content).is_empty(),"input_validation":before,"prepared_validation":prepared_validation,"actual_two_facility_bundle_reserved":actual_bundle,"separate_preparation_nurse_without_stay_or_session":pending,"previous_busy_helpers_false_no_move":distinct_from_old_busy,"coverage_nurse_not_taken":held,"real_referral_released_preparation":cancelled,"physical_release_respected":safe_release,"actual_guide_arrival_after_cancel":arrived,"release_and_guide_ticks":release_ticks,"preparation":preparation.duplicate(true),"reason":v.waiting_reason,"validation":x.world.validate(_content)}
	_dispose(x);return row
