extends "res://tests/acceptance/floor_guidance.gd"

# These are legitimate immediate business-boundary inputs, not claims about
# completed earlier services. All measured gathering and guide travel is real.
func run_ownership(database: HospitalContent, selected: Array = []) -> Dictionary:
	_content = database
	var runs: Dictionary = {"GUIDE-LIVE-WARD-OWNERSHIP":_live_ward,"GUIDE-GATHERING-ARRIVAL-OWNERSHIP":_gathering_arrival,"GUIDE-WARD-ASSOCIATION-NOT-PERMANENT":_ward_association_only,"GUIDE-TERMINAL-WARD-RELEASE_WAIT":_terminal_ward.bind("release_wait"),"GUIDE-IDLE-STATION-SCHEDULE-HANDOFF":_idle_station_schedule_handoff,"GUIDE-TRAINING-SCHEDULE":_training_schedule,"GUIDE-PREPARATION-WARD-SURGERY":_preparation_coverage}
	var rows: Array = []
	var okay: bool = true
	for id: String in (runs.keys() if selected.is_empty() else selected):
		if not runs.has(id): return {"ok":false,"error":"unknown selector "+id}
		var row: Dictionary = runs[id].call()
		rows.append(row);okay = okay and bool(row.ok)
	return {"ok":okay,"cases":rows}

func _ward_boundary() -> Dictionary:
	var x: Dictionary = _base(true)
	# Declared downstream history: admission at 0, operation at 100, recovery
	# from 1500. At 3600 its 1800 standard ticks have 120 left after legal
	# coverage pauses. The tested ownership and subsequent movement start here.
	x.world.facts.sim_tick = 3600
	x.boundary_input = {"kind":"declared_covered_recovery_history","source":"legal_downstream_input","boundary_tick":3600,"admitted_tick":0,"surgery_start_tick":100,"surgery_work_ticks":1200,"wake_ticks":150,"entered_recovery_tick":1500,"recovery_standard_ticks":1800,"remaining_recovery_ticks":120,"prior_history_executed":false}
	for research_id: String in ["R02","R11","R12","R33","R34"]:
		if not research_id in x.world.facts.research: x.world.facts.research.append(research_id)
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
	HospitalFactory._add_staff(x.world,"history_or_nurse","历史手术护士","nurse",[55,92],_content)
	x.world.facts.staff.history_or_nurse.abilities.surgery = 1
	x.world.facts.staff.history_or_nurse.certificates = ["q_or"]
	x.world.facts.staff.history_or_nurse.schedule = [{"kind":"rest","pools":[],"locked":false},{"kind":"rest","pools":[],"locked":false},{"kind":"rest","pools":[],"locked":false}]
	x.world.facts.staff.history_or_nurse.on_shift = false
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
	v.diagnosis=preload("res://tests/acceptance/clinical_input.gd").diagnosed("doctor","diagnosis")
	x.world.facts.attempts[attempt_id] = {"id":attempt_id,"visit_id":v.id,"plan_id":"P_D09_SURGERY","protocol_id":"TP_SURGERY1","result":true,"start_tick":100,"probability_bp":9600,"work_ticks":1200,"recovery_ticks":1800,"supply_units":8,"cure_fee":360,"facility_fee":60,"ward_fee":60,"staff_ids":["doctor","history_anesthetist","history_or_nurse"],"effective_level":0.0,"bed_id":"ownership_ward_0","nurse_id":"guide_nurse","ward_id":"ownership_ward"}
	x.world.facts.inventory.issues[attempt_id] = {"attempt_id":attempt_id,"units":8,"tick":100}
	x.world.facts.inventory.units -= 8
	var stay: Dictionary = {"id":"ownership_stay","visit_id":v.id,"attempt_id":attempt_id,"bed_id":"ownership_ward_0","phase":"recovery","remaining_ticks":120,"work_credit_milli":0,"care_completed":true,"nurse_id":"guide_nurse","escort_id":"guide_nurse","admitted_tick":0,"last_progress_tick":x.world.sim_tick,"entered_tick":1500,"companion_evaluated":true,"companion_qualified":false,"companion_actor_id":"","visitor_day":0,"visitor_intent":false,"visitor_requested":false}
	x.world.facts.ward_stays[stay.id] = stay
	x.reservation_error = x.space.reserve_facility(x.world,stay.bed_id,v.actor_id,stay.id,["guide_nurse"])
	x.c._support(x.world,v,x.space.facility_layout(x.world,stay.bed_id),"lying")
	x.world.touch()
	return x

func _live_ward() -> Dictionary:
	var x: Dictionary = _ward_boundary()
	var stay: Dictionary = x.world.facts.ward_stays.ownership_stay
	var prevalidation: String = x.world.validate(_content)
	var covered: bool = x.c._ward_covering(x.world,stay)
	var otherwise_free: bool = not HospitalClinicalDevelopment.safe_busy(x.world,"guide_nurse") and not x.c.staff_busy(x.world,"guide_nurse") and not x.world.facts.moves.has("guide_nurse") and x.world.facts.sessions.is_empty()
	var location: Dictionary = x.world.facts.actors.guide_nurse.location.duplicate(true)
	var remaining: int = int(stay.remaining_ticks)
	x.g.dispatch(x.world)
	var kept: bool = str(x.world.facts.floor_guidance.desks.guide.nurse_id).is_empty() and str(x.world.facts.staff.guide_nurse.get("active_job_id","")).is_empty() and not x.world.facts.moves.has("guide_nurse") and x.world.facts.actors.guide_nurse.location==location
	x.c.advance(x.world)
	var continued: bool = int(stay.remaining_ticks)==remaining-1
	var row: Dictionary = {"case":"GUIDE-LIVE-WARD-OWNERSHIP","ok":prevalidation.is_empty() and str(x.reservation_error).is_empty() and covered and otherwise_free and kept and continued and x.world.validate(_content).is_empty(),"boundary_input":x.boundary_input,"input_validation":prevalidation,"reservation_error":x.reservation_error,"actual_coverage_before":covered,"no_move_session_or_other_busy_before":otherwise_free,"ward_nurse_not_stolen":kept,"continuous_recovery_advanced_one_tick":continued,"desk_nurse":x.world.facts.floor_guidance.desks.guide.nurse_id,"remaining_before":remaining,"remaining_after":stay.remaining_ticks,"validation":x.world.validate(_content)}
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
	var stay: Dictionary = x.world.facts.ward_stays.ownership_stay
	# Legitimate post-recovery boundary. Retained ward assignment and bed access
	# are not active nursing work. No physical exit under test is fabricated.
	stay.phase = phase;stay.remaining_ticks = 0
	x.boundary_input.kind = "declared_terminal_recovery_history"
	x.boundary_input.remaining_recovery_ticks = 0
	x.world.facts.visits.ownership_inpatient.phase = "leaving"
	x.world.facts.visits.ownership_inpatient.final_result = "cured"
	x.world.touch()
	var prevalidation: String = x.world.validate(_content)
	x.g.dispatch(x.world)
	var assigned: bool = x.world.facts.floor_guidance.desks.guide.nurse_id=="guide_nurse"
	var row: Dictionary = {"case":"GUIDE-TERMINAL-WARD-"+phase.to_upper(),"ok":prevalidation.is_empty() and str(x.reservation_error).is_empty() and assigned and x.world.validate(_content).is_empty(),"boundary_input":x.boundary_input,"input_validation":prevalidation,"terminal_stay_kept":x.world.facts.ward_stays.has(stay.id),"ward_assignment_kept":x.world.facts.staff.guide_nurse.ward_id=="ownership_ward","nurse_eligible_after_coverage_ends":assigned,"validation":x.world.validate(_content)}
	_dispose(x);return row


func _ownership_schedule(rest_now: bool) -> Array:
	return [{"kind":"rest" if rest_now else "work","pools":[],"locked":false},{"kind":"work","pools":[],"locked":false},{"kind":"work" if rest_now else "rest","pools":[],"locked":false}]

func _idle_station_schedule_handoff() -> Dictionary:
	var started_us: int = Time.get_ticks_usec()
	var x: Dictionary = _ward_boundary()
	var inspection_source: Dictionary = _open_inspection_from_real_b_arrival(x)
	if not bool(inspection_source.ok) or not x.world.facts.ward_stays.has("ownership_stay"):
		var failed: Dictionary={"case":"GUIDE-IDLE-STATION-SCHEDULE-HANDOFF","ok":false,"prerequisite":"实际B病例到院和离院后保留原护理交接起点","inspection_source":inspection_source,"validation":x.world.validate(_content)}
		_dispose(x);return failed
	var stay: Dictionary = x.world.facts.ward_stays.ownership_stay
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
	var ward_schedule: Array=_ownership_schedule(false)
	for entry: Dictionary in ward_schedule:
		if entry.kind=="work": entry.pools=["ownership_ward"]
	var doctor_schedule: Array=[{"kind":"outpatient","pools":["clinic"],"locked":false},{"kind":"outpatient","pools":["clinic"],"locked":false},{"kind":"rest","pools":[],"locked":false}]
	var initial_schedules: CommandResult=x.s.execute(x.world,"apply_schedule",{"changes":[{"staff_id":"guide_nurse","schedule":ward_schedule},{"staff_id":"ward_cover","schedule":ward_schedule},{"staff_id":"doctor","schedule":doctor_schedule}]})
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
	var guide_excluded: bool = true
	var other_assignments_legal: bool = true
	var first_demand: Dictionary = {}
	var last_demand: Dictionary = {}
	var no_parallel: bool = true
	for tick: int in 60:
		x.s.boundaries(x.world);x.s.dispatch(x.world);x.d.dispatch(x.world);x.g.dispatch(x.world)
		x.c._dispatch_service(x.world,exam,ticket)
		held = held and x.world.facts.staff.guide_nurse.get("active_job_id","")=="floor_desk:guide" and x.world.facts.floor_guidance.desks.guide.nurse_id=="guide_nurse" and x.world.facts.actors.guide_nurse.location==station and not x.world.facts.moves.has("guide_nurse") and x.world.facts.floor_guidance.visits.is_empty()
		last_demand = _idle_competing_work(x,exam,ticket)
		guide_excluded = guide_excluded and bool(last_demand.guide_excluded)
		other_assignments_legal = other_assignments_legal and bool(last_demand.assignments_legal)
		if first_demand.is_empty() and (not last_demand.staff_ids.is_empty() or not last_demand.handoffs.is_empty()): first_demand=last_demand.duplicate(true)
		no_parallel = no_parallel and bool(last_demand.guide_excluded) and x.world.facts.staff.guide_nurse.base_task.is_empty() and stay.nurse_id!="guide_nurse"
		x.space.advance(x.world);x.world.facts.sim_tick += 1;x.world.touch(false);x.space.finish_boundary(x.world)
	var before_rest_validation: String = x.world.validate(_content)
	# Resolve the independent ward shortage by a real schedule change. The
	# coming replacement is then for this desk, not for another department.
	var rest: CommandResult = x.s.execute(x.world,"apply_schedule",{"changes":[{"staff_id":"guide_nurse","schedule":_ownership_schedule(true)},{"staff_id":"ward_cover","schedule":ward_schedule},{"staff_id":"replacement","schedule":_ownership_schedule(false)}]})
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
	var row: Dictionary = {"case":"GUIDE-IDLE-STATION-SCHEDULE-HANDOFF","boundary_input":x.boundary_input,"ok":initial_schedules.accepted and prevalidation.is_empty() and before_rest_validation.is_empty() and actual_arrival and at_idle_desk and original_relief.accepted and otherwise_qualified and held and guide_excluded and other_assignments_legal and no_parallel and rest.accepted and saw_release and release_protected and replacement_arrived and no_overlap and old_clear and x.world.validate(_content).is_empty(),"initial_schedules":initial_schedules.to_record(),"input_validation":prevalidation,"before_rest_validation":before_rest_validation,"preparation_us":preparation_us,"test_us":Time.get_ticks_usec()-started_us-preparation_us,"actual_initial_desk_arrival_ticks":arrival_ticks,"idle_without_guidance_patient":at_idle_desk,"original_ward_nurse_rest_command":original_relief.to_record(),"otherwise_qualified_inspection_operator":otherwise_qualified,"idle_station_held_for_ticks":60,"position_and_desk_owner_unchanged":held,"guide_excluded_from_clinical_and_ward_assignments":guide_excluded,"other_assignments_qualified_and_scheduled":other_assignments_legal,"first_demand":first_demand if not first_demand.is_empty() else last_demand,"no_parallel_clinical_or_base_work":no_parallel,"formal_rest_and_replacement_command":rest.to_record(),"real_release_observed":saw_release,"release_retained_busy_ownership":release_protected,"release_and_replacement_travel_ticks":handoff_ticks,"replacement_really_arrived":replacement_arrived,"old_nurse_really_clear_and_off_shift":old_clear,"nurse_bodies_never_overlapped":no_overlap,"station_location":station,"old_released_location":released_position,"validation":x.world.validate(_content)}
	row.inspection_source = inspection_source
	row.ok = bool(row.ok) and bool(inspection_source.ok)
	_dispose(x);return row

func _idle_competing_work(x: Dictionary, exam: Dictionary, ticket: Dictionary) -> Dictionary:
	var assigned: Dictionary={}
	var excluded: bool=true
	var legal: bool=true
	var reservations: Array=[]
	var sessions: Array=[]
	var hold: Dictionary=x.world.facts.adaptations.get("diagnosis",{})
	if hold.get("actor_id","")==exam.actor_id:
		reservations.append({"facility_id":"diagnosis","owner_id":hold.get("owner_id",""),"staff_ids":hold.get("staff_ids",[]).duplicate()})
		for id: String in hold.get("staff_ids",[]): assigned[id]={"kind":"spectrum","facility_id":"diagnosis"}
	for session: Dictionary in x.world.facts.sessions.values():
		excluded=excluded and not "guide_nurse" in session.staff_ids
		if session.visit_id!=exam.id: continue
		sessions.append({"id":session.id,"kind":session.kind,"staff_ids":session.staff_ids.duplicate()})
		for id: String in session.staff_ids: assigned[id]={"kind":session.kind,"facility_id":session.facility_id}
	for preparation: Dictionary in x.world.facts.preparations.values():
		excluded=excluded and not "guide_nurse" in preparation.staff_ids
		if preparation.visit_id!=exam.id: continue
		for id: String in preparation.staff_ids: assigned[id]={"kind":preparation.kind,"facility_id":preparation.facility_id}
	var operators: Array=[]
	for id: String in assigned:
		var staff: Dictionary=x.world.facts.staff[id]
		var assignment: Dictionary=x.s.assignment(x.world,id,x.s.shift_index(x.world))
		var room: String=str(x.world.facts.facilities[assigned[id].facility_id].get("room_id",""))
		var qualified: bool=x.c._service_qualified(x.world,staff,str(assigned[id].kind))
		var scheduled: bool=staff.on_shift and assignment.kind==("outpatient" if staff.role=="doctor" else "work") and room in assignment.pools
		excluded=excluded and id!="guide_nurse"
		legal=legal and qualified and scheduled
		operators.append({"staff_id":id,"qualified":qualified,"scheduled":scheduled,"assignment":assignment.duplicate(true)})
	var handoffs: Array=[]
	for handoff: Dictionary in x.world.facts.staff_schedule.handoffs.values():
		var id: String=str(handoff.new_id)
		var staff: Dictionary=x.world.facts.staff[id]
		var assignment: Dictionary=x.s.assignment(x.world,id,x.s.shift_index(x.world))
		var qualified: bool=staff.role=="nurse" and "q_ward" in staff.certificates and int(staff.abilities.care)>=1
		var scheduled: bool=staff.on_shift and assignment.kind=="work" and handoff.ward_id in assignment.pools
		excluded=excluded and id!="guide_nurse"
		legal=legal and qualified and scheduled
		handoffs.append({"ward_id":handoff.ward_id,"new_id":id,"qualified":qualified,"scheduled":scheduled,"assignment":assignment.duplicate(true)})
	return {"tick":x.world.sim_tick,"guide_excluded":excluded,"assignments_legal":legal,"ticket_assigned":ticket.get("service_assigned",false),"staff_ids":assigned.keys(),"operators":operators,"reservations":reservations,"sessions":sessions,"handoffs":handoffs}

func _open_inspection_from_real_b_arrival(x: Dictionary) -> Dictionary:
	var started_tick: int=x.world.sim_tick
	var research: HospitalResearch=HospitalResearch.new(_content,x.space)
	research.ensure(x.world)
	x.c.research=research
	# R02 is part of this hospital's declared legal history. Its B-profile D16
	# arrives through the production owner and really leaves before idle work.
	var unlocked: bool=HospitalResearch.disease_unlocked(x.world,_content,"D16")
	var arrival: CommandResult=x.c.execute(x.world,"clinical_arrive",{"arrival_key":"ownership_inspection_opening","binding_id":"B_S26_D16_M16","personality_id":"PP01"})
	var referral: CommandResult=CommandResult.new(false,"arrival_incomplete")
	var departed: bool=false
	if arrival.accepted:
		var visit: Dictionary=x.world.facts.visits[arrival.changed_ids[0]]
		referral=x.c.execute(x.world,"clinical_refer",{"visit_id":visit.id})
		for tick: int in 200:
			if visit.phase=="departed" and x.world.facts.actors[visit.actor_id].location.kind=="outside":
				departed=true
				break
			_step(x,true)
			x.c.release_departed(x.world)
	var first_b_tick: int=int(x.world.facts.research_progress.first_profile_b_tick)
	return {"ok":unlocked and arrival.accepted and referral.accepted and departed and first_b_tick==started_tick,"binding_id":"B_S26_D16_M16","disease_unlocked":unlocked,"arrival":arrival.to_record(),"referral":referral.to_record(),"actual_departure":departed,"first_profile_b_tick":first_b_tick,"started_tick":started_tick,"finished_tick":x.world.sim_tick}


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

func _preparation_context() -> Dictionary:
	var old: Dictionary = _fixture()
	var world: WorldState = old.world
	_dispose(old)
	var x: Dictionary = _guide_bind(world)
	var f: RefCounted = load("res://tests/acceptance/clinical_fixtures.gd").new()
	f._content = _content
	f._add_layout(world,"ward_two_beds","ownership_ward",[45,65])
	f._add_layout(world,"or_standard","ownership_or",[33,65])
	_facility(x,"guide","SE01",[47,83])
	f._add_worker(world,"surgeon","doctor",[34,77],"surgery",{"diagnosis":1,"treatment":3,"care":0,"surgery":2},"DT02","ownership_or")
	f._add_worker(world,"anesthetist","doctor",[38,77],"surgery",{"diagnosis":1,"treatment":1,"care":0,"surgery":2},"DT02","ownership_or")
	f._add_worker(world,"or_nurse","nurse",[42,77],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":1},"DT01","ownership_or")
	world.facts.staff.or_nurse.certificates=["q_or","q_ward"]
	f._add_worker(world,"guide_nurse","nurse",[46,72],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":0},"DT01","ownership_ward")
	world.facts.staff.guide_nurse.ward_id="ownership_ward"
	world.facts.staff.guide_nurse.base_prepared=true
	world.facts.staff.or_nurse.base_prepared=true
	for key: String in ["d","s","w","r","f"]: x[key].ensure(world)
	for definition: Dictionary in _content.catalog.research: world.facts.research.append(definition.id)
	var v: Dictionary = _visit(x,"prepared_patient",[40,88])
	world.facts.tickets.erase(v.ticket_id);v.ticket_id = ""
	var binding: Dictionary = _content.definition("treatment_bindings","B_S13_D09_M09")
	v.binding_id = binding.id;v.disease_id = binding.disease_id
	v.requested_plan_id = "P_D09_SURGERY"
	world.facts.actors[v.actor_id].species_id = binding.species_id;world.facts.actors[v.actor_id].body_binding_id = binding.id
	v.diagnosis = preload("res://tests/acceptance/clinical_input.gd").diagnosed("surgeon","diagnosis")
	v.plan_decision = {"plan_id":v.requested_plan_id,"source":"director","doctor_id":"surgeon","revision":1,"reason":"已确认的临床待办边界","expected_team":["surgeon","anesthetist","or_nurse"]}
	x.c._queue(world,v,"surgery")
	var stay: Dictionary={"id":"prepared_inpatient_stay","visit_id":v.id,"attempt_id":"","bed_id":"ownership_ward_0","nurse_id":"guide_nurse","escort_id":"guide_nurse","phase":"waiting_surgery","admitted_tick":world.sim_tick,"remaining_ticks":0,"work_credit_milli":0,"care_completed":false,"last_progress_tick":world.sim_tick,"companion_evaluated":true,"companion_qualified":false,"companion_actor_id":"","visitor_day":world.sim_tick/WorldState.TICKS_PER_DAY,"visitor_intent":false,"visitor_requested":false}
	world.facts.ward_stays[stay.id]=stay
	var bed_reason: String=x.space.reserve_facility(world,stay.bed_id,v.actor_id,stay.id,[stay.nurse_id])
	x.bed_reservation=bed_reason
	x.c._support(world,v,x.space.facility_layout(world,stay.bed_id),"lying")
	x.c.floor_guidance = null
	world.touch()
	x.visit = v
	return x

func _preparation_coverage() -> Dictionary:
	var x: Dictionary = _preparation_context()
	var v: Dictionary = x.visit
	var before: String = x.world.validate(_content)
	var ticket: Dictionary = x.world.facts.tickets[v.ticket_id]
	# Production dispatch reserves the actual OR/team while retaining the
	# already admitted patient's original bed and its separate coverage nurse.
	x.c._prepare_surgery(x.world,v,ticket)
	var preparation: Dictionary = x.world.facts.preparations.get(v.id,{})
	var pending: bool = not preparation.is_empty() and preparation.get("nurse_id","")=="guide_nurse" and not "guide_nurse" in preparation.get("staff_ids",[]) and x.world.facts.ward_stays.size()==1 and x.world.facts.sessions.is_empty()
	var actual_bundle: bool = pending and x.world.facts.adaptations.has(preparation.bed_id) and x.world.facts.adaptations.has(preparation.facility_id) and x.world.facts.adaptations[preparation.bed_id].owner_id=="prepared_inpatient_stay" and x.world.facts.adaptations[preparation.facility_id].owner_id==v.id
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
		var ward: Dictionary=x.world.facts.ward_stays.prepared_inpatient_stay
		# Cancel this unstarted OR preparation through its production owner.
		# The admitted patient must really return before the ward referral command.
		HospitalClinic.Flow.abort_preparation(x.c,x.world,v,ward,ticket)
		var released_or: bool=not x.world.facts.preparations.has(v.id) and x.world.facts.attempts.is_empty() and x.world.facts.inventory.issues.is_empty()
		var returned: bool=false
		for tick: int in 400:
			if ward.phase=="waiting_surgery": returned=true;break
			_step(x,true)
			x.c.release_departed(x.world)
		var result: CommandResult=x.c.execute(x.world,"clinical_ward_refer",{"visit_id":v.id}) if returned else CommandResult.new(false,"preop_return_incomplete")
		cancelled=released_or and returned and result.accepted and not x.world.facts.preparations.has(v.id)
		for tick: int in 600:
			var releasing: bool=x.world.facts.staff.guide_nurse.has("clinical_release")
			_step(x,true)
			x.c.release_departed(x.world)
			if releasing: safe_release=safe_release and x.world.facts.floor_guidance.desks.guide.nurse_id!="guide_nurse"
			release_ticks+=1
			var handoff: Dictionary=_post_preparation_handoff(x,v,str(preparation.bed_id))
			if handoff.original_cover_available and handoff.actual_desk_owner_arrived and handoff.patient_departed and handoff.bed_released:
				arrived=true;break
	var desk_owner: String=str(x.world.facts.floor_guidance.desks.guide.nurse_id)
	var tracked_staff: Dictionary={}
	for staff_id: String in ["guide_nurse",desk_owner]:
		if staff_id.is_empty() or tracked_staff.has(staff_id): continue
		var staff: Dictionary=x.world.facts.staff[staff_id]
		var movement: Dictionary=x.world.facts.moves.get(staff_id,{})
		var cursor: int=int(movement.get("cursor",0))
		tracked_staff[staff_id]={"location":x.world.facts.actors[staff_id].location.duplicate(true),"on_shift":staff.on_shift,"base_prepared":staff.get("base_prepared",false),"active_job_id":staff.get("active_job_id",""),"clinical_release":staff.get("clinical_release",{}).duplicate(true),"life_phase":staff.get("life_task",{}).get("phase",""),"move":{"target_floor":movement.get("target_floor",-1),"target_cell":movement.get("target_cell",[]),"cursor":cursor,"blocked_since":movement.get("blocked_since",-1),"route_pending":movement.get("route_pending",false),"next":movement.get("path",[]).slice(cursor,cursor+3)}}
	var final_handoff: Dictionary={"tick":x.world.sim_tick,"desk_owner":desk_owner,"visit_phase":v.phase,"visit_ticket":v.ticket_id,"ward_stay":HospitalClinic.Flow.ward_stay(x.world,v.id).duplicate(true),"staff":tracked_staff,"checks":_post_preparation_handoff(x,v,str(preparation.bed_id))}
	var row: Dictionary = {"case":"GUIDE-PREPARATION-WARD-SURGERY","ok":before.is_empty() and prepared_validation.is_empty() and actual_bundle and pending and distinct_from_old_busy and held and cancelled and safe_release and arrived and x.world.validate(_content).is_empty(),"input_validation":before,"prepared_validation":prepared_validation,"actual_two_facility_bundle_reserved":actual_bundle,"separate_ward_nurse_and_unstarted_or_preparation":pending,"previous_busy_helpers_false_no_move":distinct_from_old_busy,"coverage_nurse_not_taken":held,"real_referral_released_preparation":cancelled,"physical_release_respected":safe_release,"original_cover_available_and_actual_desk_owner_arrived":arrived,"release_and_guide_ticks":release_ticks,"preparation":preparation.duplicate(true),"reason":v.waiting_reason,"validation":x.world.validate(_content)}
	row.final_handoff = final_handoff
	_dispose(x);return row

func _post_preparation_handoff(x: Dictionary, visit: Dictionary, bed_id: String) -> Dictionary:
	var owner: String=str(x.world.facts.floor_guidance.desks.guide.nurse_id)
	var desk_ready: bool=not owner.is_empty() and x.g._desk_usable(x.world,"guide")
	var staff: Dictionary=x.world.facts.staff.guide_nurse
	var original_clear: bool=not staff.has("clinical_release") and not x.world.facts.moves.has("guide_nurse") and staff.get("base_task",{}).is_empty()
	var own_ward: bool=false
	for stay: Dictionary in x.world.facts.ward_stays.values():
		own_ward=own_ward or stay.get("nurse_id","")=="guide_nurse" or stay.get("escort_id","")=="guide_nurse"
	var free_for_work: bool=x.g._nurse_ready(x.world,"guide_nurse") and str(staff.get("active_job_id","")).is_empty() and not x.g._clinical_responsibility(x.world,"guide_nurse") and not x.c.staff_busy(x.world,"guide_nurse") and not HospitalClinicalDevelopment.safe_busy(x.world,"guide_nurse")
	var available: bool=original_clear and not own_ward and (free_for_work or owner=="guide_nurse" and desk_ready)
	var actor: Dictionary=x.world.facts.actors[visit.actor_id]
	var departed: bool=visit.phase=="departed" and actor.location.kind=="outside" and not x.world.facts.moves.has(visit.actor_id)
	var released: bool=HospitalClinic.Flow.ward_stay(x.world,visit.id).is_empty() and not x.world.facts.adaptations.has(bed_id) and not actor.has("support_facility_id")
	return {"original_cover_available":available,"original_cover_physically_clear":original_clear,"original_cover_has_ward":own_ward,"actual_desk_owner_arrived":desk_ready,"desk_owner":owner,"patient_departed":departed,"bed_released":released}
