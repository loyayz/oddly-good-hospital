extends RefCounted

const ClinicalInput = preload("res://tests/acceptance/clinical_input.gd")

class AdmissionProbe extends HospitalWaitingLife:
	var admission_queries: int = 0
	func _admitted(world: WorldState, visit_id: String) -> bool:
		admission_queries+=1
		return super._admitted(world,visit_id)

func _visit(world: WorldState, id: String, cell: Array, phase: String = "wait_gp") -> Dictionary:
	# Declared input before the clock calculation, not a tested arrival/journey.
	world.facts.actors[id]={"id":id,"name":id,"species_id":"S13","body_binding_id":"B_S13_D09_M09",
		"location":{"kind":"floor","floor_id":1,"cell":cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
	var visit: Dictionary={"id":id,"actor_id":id,"disease_id":"D09","binding_id":"B_S13_D09_M09",
		"requested_plan_id":"P_D09_COMMON" if phase=="wait_gp" else "P_D09_SURGERY",
		"expression":"clear","personality_id":"PP01","anger":0.0,"phase":phase,"diagnosis":{},
		"attempt_ids":[],"plan_decision":{},"complex":false,"final_result":"","waiting_reason":"",
		"ticket_id":"ticket_"+id,"doctor_fee_quote":-1 if phase=="wait_gp" else 20,"arrived_tick":100,"arrival_key":id,
		"last_progress_tick":world.sim_tick,"last_service_tick":world.sim_tick}
	if phase=="wait_surgery":
		var doctor_id: String = ""
		for staff_id: String in world.ids("staff"):
			if world.facts.staff[staff_id].role=="doctor": doctor_id=staff_id;break
		visit.diagnosis=ClinicalInput.diagnosed(doctor_id,str(world.facility_ids("FUR02")[0]))
		visit.plan_decision={"plan_id":"P_D09_SURGERY","source":"director","doctor_id":doctor_id,
			"revision":1,"probability_bp":9600,"expected_team":[]}
	world.facts.visits[id]=visit
	world.facts.arrival_receipts[id]=id
	world.facts.tickets[visit.ticket_id]={"id":visit.ticket_id,"visit_id":id,
		"kind":"gp" if phase=="wait_gp" else "surgery","enqueued_tick":world.sim_tick}
	world.register_visit(id)
	return visit

func _stay(world: WorldState, clinic: HospitalClinic, visit: Dictionary, bed_id: String, admitted: bool) -> String:
	var space: HospitalSpace=clinic.space
	var id: String = "stay_"+str(visit.id)
	var stay: Dictionary={"id":id,"visit_id":visit.id,"attempt_id":"","bed_id":bed_id,
		"phase":"waiting_surgery" if admitted else "admitting","remaining_ticks":0,
		"work_credit_milli":0,"care_completed":false,"nurse_id":"starter_nurse",
		"escort_id":"starter_nurse","last_progress_tick":world.sim_tick}
	var reason: String=space.reserve_facility(world,bed_id,visit.actor_id,id,["starter_nurse"])
	if not reason.is_empty(): return reason
	world.facts.ward_stays[id]=stay
	var bed: Dictionary=space.facility_layout(world,bed_id)
	if admitted:
		# Legal already-in-bed history; no bed arrival or movement is measured.
		stay.admitted_tick=world.sim_tick
		clinic._support(world,visit,bed,"lying")
		clinic._use(world,bed,id)
		clinic.visitors.call("admission",world,visit,stay)
		return ""
	var ticket: Dictionary=world.facts.tickets[visit.ticket_id]
	ticket.called_tick=world.sim_tick
	ticket.service_assigned=true
	return space.request_move(world,visit.actor_id,int(bed.floor_id),bed.patient_cell)

func _clock(tick: int, delay: int) -> Dictionary:
	return {"sequence":0,"next_purpose":"toilet","next_need_tick":tick+delay}

func _containers_same(world: WorldState, state: Dictionary, clocks: Dictionary, entries: Dictionary) -> bool:
	if not is_same(world.facts.waiting_life,state) or not is_same(state.clocks,clocks): return false
	for id: String in entries:
		if not clocks.has(id) or not is_same(clocks[id],entries[id]): return false
	return true

func run_case(content: HospitalContent) -> Dictionary:
	var checks: Dictionary={}
	var validation: Dictionary={}
	var query_counts: Dictionary={}
	var world: WorldState=HospitalFactory.create(HospitalSnapshots.uuid(),"候诊时钟边界",true,content)
	world.facts.sim_tick=900
	var fixture: RefCounted=load("res://tests/acceptance/clinical_fixtures.gd").new()
	fixture._content=content
	fixture._add_layout(world,"ward_two_beds","clock_ward",[45,65])
	var space: HospitalSpace=HospitalSpace.new(content)
	var clinic: HospitalClinic=HospitalClinic.new(content,space)
	clinic.ensure(world)
	var life: AdmissionProbe=AdmissionProbe.new(content,space)
	var ordinary: Dictionary=_visit(world,"clock_outpatient",[39,86])
	ordinary.arrived_tick=world.sim_tick
	var admitting: Dictionary=_visit(world,"clock_admitting",[42,86],"wait_surgery")
	var admitted: Dictionary=_visit(world,"clock_admitted",[55,86],"wait_surgery")
	world.facts.waiting_life={"seats":{},"needs":{},"clocks":{},"toilet_queues":{}}
	var admission_errors: Array=[_stay(world,clinic,admitting,"clock_ward_0",false),_stay(world,clinic,admitted,"clock_ward_1",true)]
	validation.input=world.validate(content)
	checks.legal_calculation_input=validation.input.is_empty() and admission_errors==["",""]
	if not checks.legal_calculation_input: return {"checks":checks,"validation":validation,"admission_errors":admission_errors}
	var active: Array=world.active_visit_ids()
	var before: Dictionary=world.freeze()
	var delay: int=ceili(float(content.balance.amenity_flow.first_need_seconds)/WorldState.TICK_SECONDS)
	life.ensure(world)
	query_counts.missing=life.admission_queries
	var admitting_clock: Dictionary=world.facts.waiting_life.clocks.get(admitting.id,{})
	var unchanged: Dictionary=world.freeze()
	unchanged.waiting_life.clocks=before.waiting_life.clocks.duplicate(true)
	checks.new_arrival_gets_first_need_interval=world.facts.waiting_life.clocks.get(ordinary.id,{})==_clock(900,delay)
	checks.admitting_still_gets_clock=admitting_clock.get("sequence",-1)==0 and admitting_clock.get("next_purpose","")=="toilet" and admitting_clock.has("next_need_tick")
	checks.actual_admission_does_not_create_clock=not world.facts.waiting_life.clocks.has(admitted.id)
	checks.only_missing_eligible_clocks_change=unchanged==before and world.facts.waiting_life.clocks.size()==2
	checks.missing_clock_admission_queries=query_counts.missing==3
	checks.active_set_unchanged=world.active_visit_ids()==active
	validation.initialized=world.validate(content)
	checks.initialized_world_valid=validation.initialized.is_empty()

	var state: Dictionary=world.facts.waiting_life
	var clocks: Dictionary=state.clocks
	clocks[ordinary.id]=_clock(int(ordinary.arrived_tick),delay)
	clocks[admitting.id]=_clock(int(admitting.arrived_tick),delay)
	clocks[admitted.id]=_clock(int(admitted.arrived_tick),delay)
	var entries: Dictionary={ordinary.id:clocks[ordinary.id],admitting.id:clocks[admitting.id],admitted.id:clocks[admitted.id]}
	validation.existing_input=world.validate(content)
	checks.existing_clock_input_valid=validation.existing_input.is_empty()
	before=world.freeze()
	life.admission_queries=0
	for _repeat: int in 5: life.ensure(world)
	query_counts.existing_five_calls=life.admission_queries
	checks.existing_values_and_world_unchanged=world.freeze()==before
	checks.existing_containers_not_replaced=_containers_same(world,state,clocks,entries)
	checks.existing_clocks_do_not_query_admission=query_counts.existing_five_calls==0

	var newcomer: Dictionary=_visit(world,"clock_new",[58,86])
	newcomer.arrived_tick=world.sim_tick
	before=world.freeze()
	life.admission_queries=0
	life.ensure(world)
	query_counts.same_tick_registration=life.admission_queries
	var expected: Dictionary=before.duplicate(true)
	expected.waiting_life.clocks[newcomer.id]=_clock(900,delay)
	checks.same_tick_registered_visit_gets_clock=world.freeze()==expected and newcomer.id in world.active_visit_ids()
	checks.only_new_clock_queries_admission=query_counts.same_tick_registration==1
	checks.registration_keeps_previous_container_identity=_containers_same(world,state,clocks,entries)

	var departed: Dictionary=_visit(world,"clock_departed",[60,86])
	world.facts.tickets.erase(departed.ticket_id)
	departed.ticket_id=""
	departed.phase="departed"
	departed.departure_recorded=true
	world.facts.actors[departed.actor_id].location={"kind":"outside"}
	world.finish_visits()
	var restored: WorldState=WorldState.new(world.freeze())
	var restored_life: AdmissionProbe=AdmissionProbe.new(content,HospitalSpace.new(content))
	before=restored.freeze()
	var restored_state: Dictionary=restored.facts.waiting_life
	var restored_clocks: Dictionary=restored_state.clocks
	var restored_entry: Dictionary=restored_clocks[admitted.id]
	validation.restored_input=restored.validate(content)
	checks.restored_input_valid=validation.restored_input.is_empty()
	restored_life.ensure(restored)
	query_counts.restored_warm=restored_life.admission_queries
	checks.restored_active_index_keeps_full_live_set=restored.active_visit_ids()==["clock_admitted","clock_admitting","clock_new","clock_outpatient"]
	checks.restored_warm_world_unchanged=restored.freeze()==before and restored_life.admission_queries==0
	checks.restored_existing_container_identity=_containers_same(restored,restored_state,restored_clocks,{admitted.id:restored_entry})
	checks.departed_clock_not_created=not restored_clocks.has(departed.id)
	validation.restored=restored.validate(content)
	checks.restored_world_valid=validation.restored.is_empty()

	var missing_facts: Dictionary=restored.freeze()
	missing_facts.waiting_life.clocks.erase(newcomer.id)
	var missing_restored: WorldState=WorldState.new(missing_facts)
	var missing_life: AdmissionProbe=AdmissionProbe.new(content,HospitalSpace.new(content))
	validation.restored_missing_input=missing_restored.validate(content)
	checks.restored_missing_input_valid=validation.restored_missing_input.is_empty()
	before=missing_restored.freeze()
	missing_life.ensure(missing_restored)
	query_counts.restored_missing=missing_life.admission_queries
	expected=before.duplicate(true)
	expected.waiting_life.clocks[newcomer.id]=_clock(900,delay)
	checks.restore_missing_clock_only=missing_restored.freeze()==expected and missing_life.admission_queries==1
	validation.restored_missing=missing_restored.validate(content)
	checks.restored_missing_world_valid=validation.restored_missing.is_empty()

	var empty: WorldState=HospitalFactory.create(HospitalSnapshots.uuid(),"空医院时钟初始化",false,content)
	var empty_life: AdmissionProbe=AdmissionProbe.new(content,HospitalSpace.new(content))
	empty_life.ensure(empty)
	checks.absent_collection_initialized=empty.facts.waiting_life=={"seats":{},"needs":{},"clocks":{},"toilet_queues":{}}
	before=empty.freeze()
	empty_life.ensure(empty)
	checks.empty_repeat_unchanged=empty.freeze()==before and empty_life.admission_queries==0
	validation.empty=empty.validate(content)
	checks.empty_world_valid=validation.empty.is_empty()
	return {"checks":checks,"validation":validation,"admission_queries":query_counts,
		"active_visit_ids":restored.active_visit_ids(),"tick":world.sim_tick,"first_need_ticks":delay,
		"scope":"Clock calculation and restoration boundaries only. Admission queries are counted in an untimed probe. No simulation, arrival, movement or admission flow is claimed."}
