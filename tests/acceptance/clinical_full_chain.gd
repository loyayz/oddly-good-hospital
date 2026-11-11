extends "res://tests/acceptance/clinical_fixtures.gd"

# Full production steps from arrival. No completed-travel or partial-work
# checkpoint replaces guidance, examination, preparation, recovery or discharge.
func run_selected(tree: SceneTree, selected: Array) -> Dictionary:
	_content = HospitalContent.new()
	for mode: String in selected:
		if not mode in ["OUTPATIENT","SURGERY","LIVE","RESTORE"]: return {"ok":false,"error":"Unknown selector: "+mode}
	var results: Array = []
	var okay: bool = not selected.is_empty()
	for mode: String in selected:
		var started: int = Time.get_ticks_msec()
		var row: Dictionary = await _chain(tree,mode)
		row.body_ms = Time.get_ticks_msec()-started
		results.append(row)
		okay = okay and row.ok
		_dispose_simulations()
	return {"ok":okay,"cases":results,"fixture_failures":_fixture_failures,
		"scope":"Real arrival, guidance, GP, required examinations, consultation and treatment; C-profile surgery includes full team gathering, instrument check, wake, escorted transfer, recovery, bedside nursing and direct discharge. Experience service stays enabled."}

func _chain(tree: SceneTree, mode: String) -> Dictionary:
	var surgical: bool = mode!="OUTPATIENT"
	var c: Dictionary = _context(surgical,surgical,true,[],true,2 if mode=="RESTORE" else 1)
	if surgical:
		# This declared initial hospital has one diagnostic table in gp. A
		# diagnosis-2 GP doctor can legally perform both checks in that room;
		# no extra table or nurse wildcard is added to the original load.
		c.world.facts.staff[c.doctors[0]].abilities.diagnosis = 2
		c.world.facts.staff[c.doctors[0]].abilities.treatment = 2
		c.world.facts.staff.clin_surgeon.title_id = "DT03"
		c.world.facts.staff.clin_surgeon.abilities.surgery = 3
		c.world.facts.staff.clin_or_nurse.abilities.surgery = 2
	var binding: String = "B_S22_D14_M14" if surgical else "B_S13_D09_M09"
	var plan: String = "P_D14_SURGERY" if surgical else "P_D09_COMMON"
	_seed_stream(c.world,"treatment",true,true,9600 if surgical else 9200,9800)
	var arrived: bool = _arrive(c,binding,plan)
	var initial: Dictionary = {"validation":c.world.validate(_content),"arrived":arrived,"tick":c.world.sim_tick,
		"staff":c.world.facts.staff.size(),"facilities":c.world.facts.facilities.size(),"care_beds":c.world.facility_ids("EQ05").size(),"research":c.world.facts.research.duplicate()}
	if surgical:
		initial.team_locations = {}
		for id: String in ["clin_surgeon","clin_anesthesia","clin_or_nurse"]: initial.team_locations[id] = c.world.facts.actors[id].location.duplicate(true)
	var errors: Array = []
	var phases: Array = []
	var previous_phase: String = ""
	var work: Dictionary = {}
	var starts: Dictionary = {}
	var recovery: int = 0
	var care_at_bedside: bool = true
	var off_ward_covered_ticks: int = 0
	var finished: bool = false
	var restore: Dictionary = {}
	var closure: Dictionary = {}
	var original_commitment: Dictionary = {}
	var expectation: Dictionary = {}
	var handoff_checks: Array = []
	var selection: Dictionary = {}
	var guidance_receipts: Array = []
	var actual_connector_riders: Dictionary = {}
	for index: int in 10000:
		if not arrived or not c.fixture_ready: break
		var before_sessions: Dictionary = c.world.facts.sessions.duplicate(true)
		var before_stay: Dictionary = _stay(c).duplicate(true)
		var before_staff: Dictionary = c.world.facts.staff.duplicate(true)
		var before_move: Dictionary = c.world.facts.moves.get(_visit(c).actor_id,{}).duplicate(true)
		_tick(c)
		var invalid: String = c.world.validate(_content)
		if not invalid.is_empty(): errors.append({"tick":c.world.sim_tick,"validation":invalid,"previous_actual_move":before_move});break
		var overlap: Array = _body_overlap(c)
		if not overlap.is_empty(): errors.append({"tick":c.world.sim_tick,"overlap":overlap});break
		var phase: String = str(_visit(c).phase)
		if mode=="RESTORE":
			for id: String in ["clin_surgeon","clin_anesthesia","clin_or_nurse"]:
				if c.world.facts.actors[id].location.kind=="transit": actual_connector_riders[id] = true
		var current_receipts: Array = c.world.facts.floor_guidance.visits.get(c.visit_id,{}).get("receipts",[])
		if current_receipts.size()>guidance_receipts.size(): guidance_receipts = current_receipts.duplicate(true)
		if phase!=previous_phase:
			phases.append({"tick":c.world.sim_tick,"phase":phase})
			previous_phase = phase
		if surgical and selection.is_empty() and phase in ["wait_outpatient","wait_surgery"] and _visit(c).attempt_ids.is_empty():
			selection = _command(c,"clinical_select_plan",{"visit_id":c.visit_id,"plan_id":plan}).to_record()
			if not selection.accepted: errors.append({"selection_rejected":selection});break
		for session: Dictionary in c.world.facts.sessions.values():
			if session.visit_id!=c.visit_id or starts.has(session.id): continue
			starts[session.id] = {"kind":session.kind,"total_ticks":session.total_ticks,"staff_ids":session.staff_ids.duplicate(),"facility_id":session.facility_id,"tick":c.world.sim_tick-1}
			var first_work: int = int(session.total_ticks)-int(session.remaining_ticks)
			work[session.kind] = int(work.get(session.kind,0))+first_work
			if first_work not in [0,1]: errors.append({"kind":session.kind,"invalid_first_work":first_work})
		for old: Dictionary in before_sessions.values():
			if old.visit_id!=c.visit_id: continue
			var current: Dictionary = c.world.facts.sessions.get(old.id,{})
			var delta: int = int(old.remaining_ticks)-int(current.get("remaining_ticks",0))
			if delta not in [0,1]: errors.append({"kind":old.kind,"unexpected_work_delta":delta,"tick":c.world.sim_tick})
			work[old.kind] = int(work.get(old.kind,0))+maxi(0,delta)
			if old.kind=="care" and delta>0:
				var bed: Dictionary = c.sim.space.facility_layout(c.world,old.facility_id)
				care_at_bedside = care_at_bedside and c.sim.space.at(c.world,str(old.staff_ids[0]),int(bed.floor_id),bed.operator_cells[0])
		var stay: Dictionary = _stay(c)
		var recovery_delta: int = 0
		if not before_stay.is_empty() and not stay.is_empty(): recovery_delta = maxi(0,int(before_stay.remaining_ticks)-int(stay.remaining_ticks))
		elif before_stay.is_empty() and not stay.is_empty(): recovery_delta = 2400-int(stay.remaining_ticks)
		recovery += recovery_delta
		if recovery_delta>0 and not stay.is_empty():
			var nurse: Dictionary = c.world.facts.actors[stay.nurse_id]
			var occupied_cell: Array = [floori(float(nurse.location.cell[0])),floori(float(nurse.location.cell[1]))]
			if not BuildGeometry.contains(c.world.facts.rooms.clin_ward,occupied_cell): off_ward_covered_ticks += 1
		if not _visit(c).attempt_ids.is_empty() and original_commitment.is_empty():
			var attempt: Dictionary = c.world.facts.attempts[_visit(c).attempt_ids[0]]
			original_commitment = _commitments({attempt.id:attempt})
			expectation = _expected_attempt(c,attempt,before_staff)
			handoff_checks.append({"tick":c.world.sim_tick,"attempt":attempt.duplicate(true),"nursing_handoff_ticks":c.nursing_handoff_ticks.duplicate(true)})
		if surgical and closure.is_empty() and phase=="surgery":
			closure = _command(c,"build_room_open",{"target_id":"clin_or","open_intent":false}).to_record()
			closure.tick = c.world.sim_tick
			closure.frozen_unchanged = _commitments(c.world.facts.attempts)==original_commitment
		if surgical and mode=="RESTORE" and restore.is_empty() and phase=="recovery" and not c.world.facts.moves.is_empty():
			restore = _roundtrip(c)
			if not restore.ok: errors.append({"restore":restore});break
		if phase=="departed": finished = true;break
		if not errors.is_empty(): break
		if index%100==99:
			print("FULL_CHAIN_PROGRESS="+JSON.stringify({"case":mode,"tick":c.world.sim_tick,"phase":phase,"reason":_visit(c).get("waiting_reason",""),"work_ticks":work}))
			await tree.process_frame
	var attempt: Dictionary = c.world.facts.attempts.get(str(_visit(c).attempt_ids[0]),{}) if not _visit(c).attempt_ids.is_empty() else {}
	var same_commitment: bool = not original_commitment.is_empty() and _commitments(c.world.facts.attempts)==original_commitment
	var expected_income: int = 1260 if surgical else 235
	var expected_work: int = int(expectation.get("work_ticks",-1))
	var receipt: Dictionary = c.sim.services.experience.receipt(c.world,c.visit_id)
	var charges: Array = receipt.get("charges",[])
	var receipt_total: int = 0
	var charge_ids: Dictionary = {}
	for charge: Dictionary in charges:
		receipt_total += int(charge.amount)
		charge_ids[charge.id] = true
	var ratings: Dictionary = {}
	for staff_id: String in c.world.facts.staff: ratings[staff_id] = c.sim.services.experience.staff_rating(c.world,staff_id)
	var rated_clinical_staff: bool = not attempt.is_empty()
	for staff_id: String in attempt.get("staff_ids",[]): rated_clinical_staff = rated_clinical_staff and int(ratings[staff_id].samples)>0
	var correct_guidance_work: bool = not guidance_receipts.is_empty()
	for receipt_row: Dictionary in guidance_receipts: correct_guidance_work = correct_guidance_work and int(receipt_row.completed_tick)-int(receipt_row.started_tick)+1==60
	var closed_quote: Dictionary = c.sim.clinic.plan_quote(c.world,c.visit_id,plan,{"structural_only":true}) if surgical and finished else {}
	var checks: Dictionary = {"legal_initial_world":arrived and initial.validation.is_empty(),"all_real_steps_valid":errors.is_empty(),
		"actual_departure":finished and _visit(c).get("final_result","")=="cured","one_attempt":_visit(c).attempt_ids.size()==1,
		"real_guidance":correct_guidance_work,
		"one_gp_and_consult":int(c.started.get("gp",0))==1 and int(c.started.get("consult",0))==1,
		"work_and_probability":not attempt.is_empty() and int(attempt.get("work_ticks",-2))==expected_work and int(work.get("surgery" if surgical else "outpatient",0))==expected_work and int(attempt.get("probability_bp",-1))==int(expectation.get("probability_bp",-2)),
		"frozen_attempt":same_commitment,"single_supply_issue":_units_used(c)==(10 if surgical else 1),
		"exact_income":_income(c)==expected_income,"receipt_and_patient_rating":not receipt.is_empty() and receipt_total==expected_income and charge_ids.size()==charges.size() and int(receipt.get("closed_tick",-1))>=0 and receipt.get("rating",{}).get("score")!=null,
		"hospital_case_and_staff_scores":c.world.facts.patient_experience.cases.size()==1 and rated_clinical_staff,
		"no_department_fact":not c.world.facts.has("departments"),"no_compulsory_round":not work.has("round") and not c.started.has("round"),
		"real_nursing_handoffs":c.nursing_handoff_not_at_base.is_empty()}
	if surgical:
		checks.required_checks = int(c.started.get("spectrum",0))==1 and int(c.started.get("resonance",0))==1 and _visit(c).evidence_by_source=={"gp":44.0,"spectrum":37.0,"resonance":27.0}
		checks.full_wake_recovery_care = int(work.get("wake",0))==150 and recovery==2400 and int(work.get("care",0))==80 and care_at_bedside and c.group_seen
		checks.handoff_before_clinical_work = int(c.nursing_handoff_ticks.get("clin_cover",0))>=60 and int(c.nursing_handoff_ticks.get("clin_or_nurse",0))>=60
		checks.closed_or_safe_finish = closure.get("accepted",false) and closure.get("frozen_unchanged",false) and not c.world.facts.rooms.clin_or.open_intent and not closed_quote.get("ok",true)
		checks.cold_restore = mode!="RESTORE" or restore.get("ok",false)
		checks.cross_floor_gathering = mode!="RESTORE" or actual_connector_riders.size()==3
	var okay: bool = true
	for value: bool in checks.values(): okay = okay and value
	var ledger: Array = []
	for entry: Dictionary in c.world.facts.ledger.entries.values():
		if int(entry.amount)>0: ledger.append(entry.duplicate(true))
	return {"case":mode,"ok":okay,"checks":checks,"initial":initial,"selection":selection,"phases":phases,"work_ticks":work,"service_starts":starts,
		"attempt":attempt,"expected_attempt":expectation,"recovery_ticks":recovery,"care_work_at_bedside":care_at_bedside,"covered_recovery_ticks_while_nurse_outside_ward":off_ward_covered_ticks,
		"nursing_handoff_ticks":c.nursing_handoff_ticks,"handoff_checks":handoff_checks,"or_close":closure,"closed_or_new_service_quote":closed_quote,
		"restore":restore,"actual_connector_riders":actual_connector_riders.keys(),"guidance_receipts":guidance_receipts,"receipt":receipt,"hospital_cases":c.world.facts.patient_experience.cases.duplicate(true),"hospital_rating":c.sim.services.experience.aggregate_rating(c.world),"staff_ratings":ratings,
		"positive_ledger":ledger,"inventory_issues":c.world.facts.inventory.issues.duplicate(true),"events":c.event_log,"errors":errors,"final_tick":c.world.sim_tick,
		"failure_state":_state(c) if not okay else {},"failure_world":_failure_world("CLIN-FULL-"+mode,c.world) if not okay else {}}

func _expected_attempt(c: Dictionary, attempt: Dictionary, before_staff: Dictionary) -> Dictionary:
	var staff: Dictionary = before_staff[attempt.staff_ids[0]]
	var surgical: bool = attempt.protocol_id=="TP_SURGERY2"
	var level: int = int(staff.abilities.surgery if surgical else staff.abilities.treatment)
	# All equipment starts at grade zero and all workers are ordinary humans;
	# no equipment, comfort, low-energy/maintenance or success talent applies.
	var seconds: float = (150.0/(1.0+0.05*(level-3)) if surgical else 30.0/(1.0+0.05*(level-1)))*(1.0+0.003*float(staff.fatigue))
	return {"work_ticks":ceili(seconds*10.0),"probability_bp":9600 if surgical else 9200,"supply_units":10 if surgical else 1,"cure_fee":1080 if surgical else 200,
		"work_source":"07-clinical-team §5; 01-simulation §4; grade zero, recorded start fatigue and required skill","operator_at_start":staff.duplicate(true),"unrounded_seconds":seconds}

func _body_overlap(c: Dictionary) -> Array:
	var bodies: Array = []
	for id: String in c.world.facts.actors:
		var actor: Dictionary = c.world.facts.actors[id]
		if actor.location.kind=="floor": bodies.append({"id":id,"floor":actor.location.floor_id,"body":c.sim.space.body_rectangle(actor)})
	for index: int in bodies.size():
		for other: int in range(index+1,bodies.size()):
			if bodies[index].floor==bodies[other].floor and bodies[index].body.intersects(bodies[other].body,false): return [bodies[index].id,bodies[other].id]
	return []
