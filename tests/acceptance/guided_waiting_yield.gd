extends "res://tests/acceptance/floor_guidance.gd"

func run_cases(database: HospitalContent, selected: Array = []) -> Dictionary:
	_content = database
	var modes: Dictionary = {"GUIDE-VISITOR-YIELD":"auto", "GUIDE-VISITOR-MANUAL":"manual", "GUIDE-VISITOR-FREE-FIRST":"free"}
	var rows: Array = []
	for id: String in (modes.keys() if selected.is_empty() else selected):
		if not modes.has(id): return {"ok":false,"error":"unknown selector "+id}
		var row: Dictionary = _guided_yield(str(modes[id]))
		row["case"] = id
		rows.append(row)
	return {"ok":rows.all(func(row: Dictionary)->bool:return row.ok),"cases":rows}

func _guided_yield(mode: String) -> Dictionary:
	var x: Dictionary = _base()
	_facility(x,"visitor_chair","FUR09",[41,80])
	var patient: Dictionary = _visit(x,"guided_patient",[40,88])
	x.world.touch()
	var admitted: bool = x.c.visitors._admit(x.world,patient,{"purpose":"companion","window":""})
	var initial_valid: String = x.world.validate(_content)
	var ticket_id: String = patient.ticket_id
	var enqueue: int = x.world.facts.tickets[ticket_id].enqueued_tick
	var ready_tick: int = -1
	var visitor_tick: int = -1
	var visitor_arrival: int = -1
	var visitor_arrival_kept: bool = true
	var yielded_tick: int = -1
	var seated_tick: int = -1
	var order: int = -1
	var safe_claim: bool = true
	var courtesy: bool = true
	var no_queue: bool = true
	var cadence: bool = true
	var command_ok: bool = true
	var boundary_checks: Dictionary = {}
	var visitor: Dictionary = {}
	for i: int in 600:
		step(x)
		visitor = x.c.visitors._present(x.world,patient.id)
		var public: Dictionary = visitor.get("public_use",{})
		if int(public.get("arrived_tick",-1))>=0 and visitor_arrival<0: visitor_arrival=int(public.arrived_tick)
		if visitor_arrival>=0: visitor_arrival_kept=visitor_arrival_kept and int(public.arrived_tick)==visitor_arrival
		if not public.is_empty(): no_queue=no_queue and not x.space.public_areas._wait_results.has(str(public.id)) and not x.space.public_areas._wait_dependencies.waiters.has(str(public.id))
		if public.get("phase","")=="seated" and visitor_tick<0:
			visitor_tick=x.world.sim_tick
			command_ok = command_ok and x.space.at(x.world,visitor.actor_id,1,x.space.facility_layout(x.world,"visitor_chair").patient_cell)
		var guide: Dictionary = x.g.state(x.world,patient.id)
		if guide.get("phase","")=="ready" and ready_tick<0:
			ready_tick=x.world.sim_tick
			order=int(guide.arrived_seq)
			if mode=="manual":
				command_ok = command_ok and x.l.execute(x.world,"waiting_select_seat",{"visit_id":patient.id,"facility_id":"visitor_chair"}).accepted
			elif mode=="free":
				command_ok = command_ok and BuildService.new(_content,x.space).execute(x.world,"build_facility",{"id":"free_chair","definition_id":"FUR09","floor_id":1,"cell":[43,80]}).accepted
		var intent: Dictionary = x.world.facts.waiting_life.seats.get(patient.id,{})
		if not intent.is_empty():
			no_queue = no_queue and not x.space.public_areas._wait_results.has(str(intent.id)) and not x.space.public_areas._wait_dependencies.waiters.has(str(intent.id))
		if public.has("yielded_seat") and yielded_tick<0:
			yielded_tick=x.world.sim_tick
			cadence = yielded_tick==ready_tick if mode=="manual" else (yielded_tick-1)%50==0
			boundary_checks = _courtesy_boundaries(x,patient,public)
		if yielded_tick>=0 and not HospitalWaitingLife.is_seated(x.world,patient.id):
			courtesy = courtesy and x.c.visitors._yielded_seat(x.world,public)=="visitor_chair" and public.get("phase","")!="seated"
		var owner: String = x.world.facts.adaptations.get("visitor_chair",{}).get("actor_id","")
		if owner==patient.actor_id:
			safe_claim = safe_claim and HospitalWaitingLife.is_seated(x.world,patient.id) and x.space.at(x.world,patient.actor_id,1,x.space.facility_layout(x.world,"visitor_chair").patient_cell) and not x.space.overlaps_facility(x.world,visitor.actor_id,"visitor_chair")
		if HospitalWaitingLife.is_seated(x.world,patient.id):
			seated_tick=x.world.sim_tick
			break
	var final_valid: String = x.world.validate(_content)
	var target: String = x.world.facts.waiting_life.seats.get(patient.id,{}).get("facility_id","")
	var checks: Dictionary = {"legal_input_and_final":initial_valid.is_empty() and final_valid.is_empty(),"real_visitor_then_guidance_arrival":admitted and visitor_tick>=0 and ready_tick>visitor_tick,"command_ok":command_ok,"real_patient_seating":seated_tick>ready_tick,"no_remote_claim":safe_claim,"no_failed_queue":no_queue,"ticket_and_local_order_preserved":patient.ticket_id==ticket_id and int(x.world.facts.tickets[ticket_id].enqueued_tick)==enqueue and int(x.g.state(x.world,patient.id).arrived_seq)==order,"ordinary_yield_cadence":cadence,"visitor_arrival_preserved":visitor_arrival_kept}
	if mode=="free": checks.free_first = yielded_tick<0 and target=="free_chair" and visitor.public_use.phase=="seated"
	else:
		checks.yield_survives_real_departure = yielded_tick>=0 and courtesy and target=="visitor_chair"
		checks.courtesy_scope_boundaries = not boundary_checks.is_empty() and boundary_checks.values().all(func(v: Variant)->bool:return bool(v))
	var result: Dictionary = {"ok":checks.values().all(func(v: Variant)->bool:return bool(v)),"checks":checks,"courtesy_boundaries":boundary_checks,"visitor_seated_tick":visitor_tick,"ready_tick":ready_tick,"yield_tick":yielded_tick,"patient_seated_tick":seated_tick,"input_validation":initial_valid,"final_validation":final_valid,"tick_seconds":WorldState.TICK_SECONDS}
	_dispose(x)
	return result

func _courtesy_boundaries(x: Dictionary, patient: Dictionary, public: Dictionary) -> Dictionary:
	# Read-only semantic checks on isolated candidate facts after actual yielding.
	# These inputs do not stand in for movement or guidance-completion evidence.
	var facts: Dictionary = x.world.freeze()
	var candidate: WorldState = WorldState.new(facts)
	var guide: Dictionary = candidate.facts.floor_guidance.visits[patient.id]
	var original: String = str(guide.target_id)
	var checks: Dictionary = {"current_clinic_keeps_courtesy":x.c.visitors._yielded_seat(candidate,public)=="visitor_chair"}
	guide.target_id="guide"
	checks.unrelated_target_rejected=x.c.visitors._yielded_seat(candidate,public).is_empty()
	guide.target_id=original
	guide.phase="destination"
	checks.incomplete_guidance_rejected=x.c.visitors._yielded_seat(candidate,public).is_empty()
	guide.phase="ready"
	var intent: Dictionary = candidate.facts.waiting_life.seats[patient.id]
	intent.mode="manual";intent.manual_facility_id="other_chair"
	checks.changed_manual_target_rejected=x.c.visitors._yielded_seat(candidate,public).is_empty()
	return checks

func step(x: Dictionary) -> void:
	# Production ordering for the affected services, exactly one 0.1s tick.
	x.g.dispatch(x.world)
	x.l.dispatch(x.world)
	x.p.dispatch(x.world)
	x.c.dispatch(x.world)
	x.space.advance(x.world)
	x.c.advance(x.world)
	x.p.advance(x.world)
	x.g.advance(x.world)
	x.l.advance(x.world)
	x.a.advance_wait(x.world)
	x.p.sample(x.world)
	x.a.clinic = x.c
	x.a.environment = x.e
	x.a.needs(x.world)
	x.world.facts.sim_tick += 1
	x.world.touch(false)


func _visit(x: Dictionary, id: String = "visit", cell: Array = [38,76], personality: String = "PP01") -> Dictionary:
	var binding: Dictionary = {}
	for candidate: Dictionary in _content.catalog.treatment_bindings:
		if candidate.species_id=="S49":
			binding = candidate
			break
	var actor_id: String = "patient_"+id
	x.world.facts.actors[actor_id] = {"id":actor_id,"name":"候诊患者","species_id":binding.species_id,"body_binding_id":binding.id,
		"location":{"kind":"floor","floor_id":1,"cell":cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
	var visit: Dictionary = {"id":id,"actor_id":actor_id,"disease_id":binding.disease_id,"binding_id":binding.id,
		"requested_plan_id":"P_"+binding.disease_id+"_COMMON","expression":"clear","personality_id":personality,"anger":50.0,
		"phase":"arrival","diagnosis":{},"attempt_ids":[],"plan_decision":{},"complex":false,"final_result":"",
		"waiting_reason":"","ticket_id":"","doctor_fee_quote":-1,"arrival_tick":0,"arrived_tick":0,
		"last_progress_tick":0,"last_service_tick":0,"arrival_key":"arrival_"+id}
	x.world.facts.visits[id] = visit
	x.c._queue(x.world,visit,"gp")
	var ticket: Dictionary = x.world.facts.tickets[visit.ticket_id]
	ticket.pause_reasons = {}
	ticket.service_assigned = false
	ticket.called_tick = -1
	x.l.ensure(x.world)
	x.p.ensure(x.world)
	return visit
