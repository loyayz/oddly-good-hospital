extends "res://tests/acceptance/clinical_flow_fixtures.gd"

const IDS: Array[String]=["CLFLOW-19","CLFLOW-20","CLFLOW-21","CLFLOW-22","CLFLOW-23","CLFLOW-24","CLFLOW-25"]

func run(t, database: HospitalContent, selected: Array = []) -> void:
	var wanted: Array=[]
	for id: String in IDS:
		if t.wants(id) and (selected.is_empty() or id in selected): wanted.append(id)
	if wanted.is_empty(): return
	flow_initialize(t,database)
	for id: String in wanted:
		t.begin_case(id)
		_fixture_failures.clear()
		await call("_case_"+id.right(2),t)
	_dispose_simulations()

func _multi(t, second_floor: bool = true, extra_first: bool = false) -> Dictionary:
	var c: Dictionary=flow_context()
	c.world.facts.ledger.opening_balance=1000000
	if second_floor:
		flow_add_floor(c)
		var result: CommandResult=_command(c,"build_facility",{"id":"flow_desk_2","definition_id":"SE01","floor_id":2,"cell":[47,83]})
		c.fixture_ready=c.fixture_ready and result.accepted
		flow_add_worker(c,"flow_nurse_2","nurse",2,[52,92])
	if extra_first:
		var result: CommandResult=_command(c,"build_facility",{"id":"flow_desk_1_extra","definition_id":"SE01","floor_id":1,"cell":[34,66]})
		c.fixture_ready=c.fixture_ready and result.accepted
		flow_add_worker(c,"flow_nurse_1_extra","nurse",1,[61,78])
	var ids: Array=["floor_guidance_desk"]
	if second_floor: ids.append("flow_desk_2")
	if extra_first: ids.append("flow_desk_1_extra")
	c.guidance_ready=await flow_until(t,c,func()->bool:return ids.all(func(id: String)->bool:return c.sim.services.floor_guidance._desk_usable(c.world,id)),1600)
	return c

func _actual_entry(c: Dictionary, service: String = "gp") -> bool:
	var admitted: bool=_arrive(c)
	if not admitted: return false
	c.sim.clinic._queue(c.world,flow_visit(c),service)
	return true

func _case_19(t) -> void:
	var base: Dictionary=await _multi(t,true,true)
	var checks: Dictionary={"three_actual_nursing_posts":base.get("guidance_ready",false)}
	if not checks.three_actual_nursing_posts: flow_check(t,"CLFLOW-19",checks,base);return
	checks.real_entry=_actual_entry(base)
	var input: Dictionary=flow_freeze(base)
	for choice: int in [0,1]:
		var c: Dictionary=flow_restore(input)
		flow_exact_draw(c.world,"registration",choice,2)
		var guide: HospitalFloorGuidance=c.sim.services.floor_guidance
		var ticket: Dictionary=c.world.facts.tickets[flow_visit(c).ticket_id]
		guide.prepare(c.world,flow_visit(c),ticket)
		checks["floor_equal_choice_"+str(choice)]=int(flow_guide(c).get("guide_floor",-1))==choice+1
		checks["entry_body_preserved_"+str(choice)]=c.world.facts.actors[flow_visit(c).actor_id].location.kind=="floor" and int(c.world.facts.actors[flow_visit(c).actor_id].location.floor_id)==1 and flow_visit(c).diagnosis.is_empty()
		if choice==1:
			var moved: bool=await flow_until(t,c,func()->bool:return c.world.facts.actors[flow_visit(c).actor_id].location.kind=="floor" and int(c.world.facts.actors[flow_visit(c).actor_id].location.floor_id)==2,2800)
			checks.cross_floor_actual_entry=moved
	flow_check(t,"CLFLOW-19",checks)

func _case_20(t) -> void:
	var c: Dictionary=await _multi(t,false)
	var checks: Dictionary={"actual_entry":_actual_entry(c)}
	c.world.facts.facilities.floor_guidance_desk.open=false
	var patient: String=str(flow_visit(c).actor_id)
	var entry: Array=c.world.facts.entry.cell.duplicate()
	await flow_steps(t,c,120)
	checks.waiting_without_false_service=flow_visit(c).attempt_ids.is_empty() and c.world.facts.sessions.is_empty() and not flow_visit(c).phase in ["leaving","departed"] and flow_guide(c).get("target_id","")==""
	var actor: Dictionary=c.world.facts.actors[patient]
	var entrance: Dictionary=actor.duplicate(true)
	entrance.location={"kind":"floor","floor_id":1,"cell":entry,"height_m":0.0}
	var body: Rect2=c.sim.space.body_rectangle(actor)
	var entry_body: Rect2=c.sim.space.body_rectangle(entrance)
	checks.body_safely_retained=actor.location.kind=="floor" and not body.intersects(entry_body,false)
	var waiting: Dictionary={"actor":actor.duplicate(true),"move":c.world.facts.moves.get(patient,{}).duplicate(true),"body":[body.position.x,body.position.y,body.size.x,body.size.y],"entry_body":[entry_body.position.x,entry_body.position.y,entry_body.size.x,entry_body.size.y],"reason":str(flow_visit(c).waiting_reason),"safe_wait":c.sim.space.public_areas.safe_wait(c.world,patient,1,actor.location.cell)}
	var ticket: Dictionary=c.world.facts.tickets.get(flow_visit(c).ticket_id,{})
	checks.ordinary_wait_accumulates=int(ticket.get("waited_ticks",0))>=100
	c.world.facts.facilities.floor_guidance_desk.open=true
	checks.recovered_actual_service=await flow_until(t,c,func()->bool:return not _session(c,"gp").is_empty(),2600)
	var absent: Dictionary=await _no_guidance_entity(t)
	for key: String in absent.checks: checks["no_entity_"+key]=absent.checks[key]
	flow_check(t,"CLFLOW-20",checks,c,{"unavailable_guidance_wait":waiting,"no_guidance_entity":absent})

func _no_guidance_entity(t) -> Dictionary:
	var world: WorldState=HospitalFactory.create(HospitalSnapshots.uuid(),"无导诊设施实际到院",true,_content)
	var simulation:=HospitalSimulation.new(world,_content)
	_simulations.append(simulation)
	var c: Dictionary={"world":world,"sim":simulation,"serial":0,"visit_id":"","doctors":[],"started":{},"beats":{},"group_seen":false,"errors":[],"fixture_ready":true,"clinical_scenario":true}
	_command(c,"set_intake_open",{"open":false})
	_command(c,"tutorial_set_enabled",{"enabled":false})
	_command(c,"set_auto_restock",{"enabled":false})
	var checks: Dictionary={"before_first_step":world.sim_tick==0 and world.facts.visits.is_empty() and world.facts.floor_guidance.desks.is_empty()}
	var commands: Array=[]
	for id: String in world.facility_ids("SE01"):
		var stored: CommandResult=_command(c,"build_store",{"target_id":id})
		commands.append(stored.to_record())
		checks["stored_"+id]=stored.accepted and world.sim_tick==0
	checks.no_desk_entity=world.facility_ids("SE01").is_empty() and world.facts.floor_guidance.desks.is_empty()
	checks.actual_entry=_actual_entry(c)
	if not checks.actual_entry: return {"checks":checks,"commands":commands}
	var patient: String=str(flow_visit(c).actor_id)
	var probe: Dictionary=world.facts.actors[patient].duplicate(true)
	probe.location={"kind":"floor","floor_id":int(world.facts.entry.floor_id),"cell":world.facts.entry.cell.duplicate(),"height_m":0.0}
	var entry_body: Rect2=simulation.space.body_rectangle(probe)
	checks.actual_safe_wait=await flow_until(t,c,func()->bool:
		var actor: Dictionary=world.facts.actors[patient]
		return actor.location.kind=="floor" and not world.facts.moves.has(patient) and not simulation.space.body_rectangle(actor).intersects(entry_body,false) and simulation.space.public_areas.safe_wait(world,patient,int(actor.location.floor_id),actor.location.cell),600)
	await flow_steps(t,c,120)
	checks.no_false_service=flow_visit(c).phase=="wait_gp" and flow_visit(c).attempt_ids.is_empty() and world.facts.sessions.is_empty() and flow_guide(c).get("target_id","")=="" and world.facility_ids("SE01").is_empty()
	checks.ordinary_wait=int(world.facts.tickets.get(str(flow_visit(c).ticket_id),{}).get("waited_ticks",0))>=100
	checks.world_valid=world.validate(_content).is_empty()
	return {"checks":checks,"commands":commands,"handoff":flow_guidance_handoff(c),"entry_body":[entry_body.position.x,entry_body.position.y,entry_body.size.x,entry_body.size.y]}

func _case_21(t) -> void:
	var source: Dictionary=await _multi(t,true)
	var checks: Dictionary={"two_guidance_floors":source.get("guidance_ready",false)}
	if not checks.two_guidance_floors: flow_check(t,"CLFLOW-21",checks);return
	for need: String in ["gp","examination","outpatient","surgery"]:
		var c: Dictionary=flow_restore(flow_freeze(source))
		checks[need+"_entry"]=_actual_entry(c)
		if need!="gp":
			flow_visit(c).diagnosis={"state":"insufficient" if need=="examination" else "diagnosed","gp_completed":true,"exam_kind":"","exam_completed":false,"review_completed":false,"doctor_id":c.doctors[0],"facility_id":"gp_station"}
			flow_visit(c).plan_decision={"plan_id":"P_D09_SURGERY" if need=="surgery" else "P_D09_COMMON","source":"doctor","doctor_id":c.doctors[0],"revision":1,"probability_bp":9600,"reason":"合法候诊输入","expected_team":[]}
			c.world.facts.tickets[flow_visit(c).ticket_id].kind=need
			flow_visit(c).phase="wait_"+need
		# Both floors lack this need, while both guidance desks remain usable.
		if need in ["gp","examination"]:
			for id: String in c.world.facility_ids("FUR02"): c.world.facts.facilities[id].open=false
		elif need=="outpatient":
			for id: String in c.world.facility_ids("M09"): c.world.facts.facilities[id].open=false
		flow_exact_draw(c.world,"registration",0,2)
		var seen: Dictionary={"first":false,"back":false,"transit":false,"last":1}
		var roundtrip: bool=await flow_watch(t,c,func()->bool:return seen.back,func()->void:
			var actor: Dictionary=c.world.facts.actors[flow_visit(c).actor_id]
			seen.transit=seen.transit or actor.location.kind=="transit"
			if actor.location.kind=="floor":
				if int(actor.location.floor_id)==2: seen.first=true
				if seen.first and int(actor.location.floor_id)==1: seen.back=true,4600)
		checks[need+"_random_return_allowed"]=roundtrip and seen.transit and flow_visit(c).attempt_ids.is_empty()
		checks[need+"_no_visited_exclusion"]=not flow_guide(c).has("visited_floors") and not flow_guide(c).has("tried_floors")
	flow_check(t,"CLFLOW-21",checks)

func _case_22(t) -> void:
	var c: Dictionary=await _multi(t,false)
	var checks: Dictionary={"first_entry":_actual_entry(c,"examination")}
	flow_visit(c).diagnosis={"state":"insufficient","gp_completed":true,"exam_kind":"","exam_completed":false,"review_completed":false,"doctor_id":c.doctors[0],"facility_id":"gp_station"}
	# Only the original GP doctor is qualified for initial diagnosis. Neither
	# GP doctor has the level/research required for this examination input.
	for staff: Dictionary in c.world.facts.staff.values():
		if staff.role=="doctor": staff.abilities.diagnosis=1
	c.world.facts.staff.starter_nurse.schedule=_schedule("rest")
	var first: String=str(c.visit_id)
	checks.blocked_individual=await flow_until(t,c,func()->bool:return flow_guide(c).get("phase","")=="blocked_destination",2200)
	var original_sequence: int=int(flow_guide(c).get("queue_seq",-1))
	var receipts: int=flow_guide(c).get("receipts",[]).size()
	checks.blocked_world_valid=c.world.validate(_content).is_empty()
	checks.blocked_save_restore=_roundtrip(c).get("ok",false) and flow_guide(c).get("phase","")=="blocked_destination" and int(flow_guide(c).get("queue_seq",-2))==original_sequence
	await flow_steps(t,c,80)
	checks.no_repeated_counter_work=flow_guide(c).get("receipts",[]).size()==receipts and not flow_guide(c).get("queue_attending",true) and not flow_guide(c).has("nurse_id")
	checks.waiting_world_valid=c.world.validate(_content).is_empty()
	# A second genuine arrival waits for the real entry body to clear.
	var admitted: Dictionary={"ok":false,"id":""}
	for index: int in 300:
		var result: CommandResult=_command(c,"clinical_arrive",{"arrival_key":"flow-second","binding_id":"B_S13_D09_M09","personality_id":"PP01","expression":"clear"})
		if result.accepted: admitted.ok=true;admitted.id=result.changed_ids[0];break
		_tick(c)
	checks.second_entry=admitted.ok
	if admitted.ok:
		var second: String=str(admitted.id)
		checks.later_patient_served=await flow_until(t,c,func()->bool:
			for session: Dictionary in c.world.facts.sessions.values():
				if session.visit_id==second and session.kind=="gp": return true
			return false,2600)
		checks.first_still_waits=c.world.facts.visits[first].phase=="wait_examination" and int(c.sim.services.floor_guidance.state(c.world,first).get("queue_seq",-2))==original_sequence
		if not "R11" in c.world.facts.research: c.world.facts.research.append("R11")
		c.world.facts.staff[c.doctors[0]].abilities.diagnosis=2
		checks.condition_change_resumes=await flow_until(t,c,func()->bool:return not flow_exam_session(c).is_empty(),2800)
	flow_check(t,"CLFLOW-22",checks,c)

func _case_23(t) -> void:
	var c: Dictionary=await _multi(t,true)
	var checks: Dictionary={"actual_entry":_actual_entry(c)}
	flow_exact_draw(c.world,"registration",1,2)
	var guide: HospitalFloorGuidance=c.sim.services.floor_guidance
	guide.prepare(c.world,flow_visit(c),c.world.facts.tickets[flow_visit(c).ticket_id])
	var trip: Dictionary=flow_guide(c).get("floor_trip",{}).duplicate(true)
	checks.chosen_remote_trip=not trip.is_empty() and int(trip.get("floor_id",-1))==2
	c.world.facts.facilities.flow_desk_2.open=false
	var rng: Dictionary=c.world.facts.rng.registration.duplicate(true)
	await flow_steps(t,c,10)
	checks.unchanged_during_trip=flow_guide(c).get("floor_trip",{})==trip and c.world.facts.rng.registration==rng and int(flow_guide(c).get("guide_floor",-1))==2
	var seen: Dictionary={"arrived":false,"transit":false}
	checks.real_arrival_then_reselect=await flow_watch(t,c,func()->bool:return seen.arrived and int(flow_guide(c).get("guide_floor",-1))==1,func()->void:
		var actor: Dictionary=c.world.facts.actors[flow_visit(c).actor_id]
		seen.transit=seen.transit or actor.location.kind=="transit"
		seen.arrived=seen.arrived or actor.location.kind=="floor" and int(actor.location.floor_id)==2,3200)
	checks.real_transport=seen.transit
	var connectors: Array=[]
	for key: Variant in c.world.facts.connectors:
		connectors.append({"key":str(key),"key_type":typeof(key),"value":c.world.facts.connectors[key].duplicate(true)})
	flow_check(t,"CLFLOW-23",checks,c,{"selected_trip":trip,"connectors":connectors})

func _case_24(t) -> void:
	var c: Dictionary=flow_two_floor_clinic()
	var checks: Dictionary={"legal_secondary_clinic":c.get("fixture_ready",false)}
	c.world.facts.facilities.flow_guide_2.open=false
	flow_exact_draw(c.world,"treatment",0)
	checks.actual_entry=_arrive(c)
	var diagnosed: bool=await flow_until(t,c,func()->bool:return flow_visit(c).diagnosis.get("gp_completed",false),2600)
	await flow_steps(t,c,120)
	checks.no_ordinary_assignment_without_desk=diagnosed and int(flow_guide(c).get("guide_floor",-1))==1 and flow_guide(c).get("target_id","")!="flow_exam_table" and flow_exam_session(c).is_empty()
	checks.clear_missing_guidance_prompt=str(flow_visit(c).waiting_reason).contains("导诊")
	var inpatient: Dictionary=await flow_boundary(t,"third_floor_inpatient")
	var preparation_trace: Dictionary={}
	checks.operative_exception_boundary=not inpatient.is_empty()
	if not inpatient.is_empty():
		inpatient.world.facts.ledger.opening_balance=1000000
		var room: CommandResult=_command(inpatient,"build_room",{"id":"flow_unattended_gp_2","room_type_id":"gp","floor_id":2,"origin":[34,66],"size":[10,10],"door":{"definition_id":"DR04","edge":"south","offset":3}})
		var table: CommandResult=_command(inpatient,"build_facility",{"id":"flow_unattended_table_2","definition_id":"FUR02","floor_id":2,"cell":[38,69],"room_id":"flow_unattended_gp_2"})
		checks.ordinary_second_floor_and_third_or=room.accepted and table.accepted and inpatient.world.facility_ids("SE01").all(func(id: String)->bool:return int(inpatient.world.facts.facilities[id].floor_id)==1)
		checks.operative_layer_needs_no_desk=await flow_watch(t,inpatient,func()->bool:return not _session(inpatient,"surgery").is_empty(),func()->void:flow_trace_preparation(inpatient,preparation_trace),4200) and int(inpatient.world.facts.facilities[_session(inpatient,"surgery").get("facility_id","")].floor_id)==3
	flow_check(t,"CLFLOW-24",checks,{}, {"preparation_trace":flow_preparation_trace_result(preparation_trace)})

func _case_25(t) -> void:
	var c: Dictionary=await _multi(t,true)
	var checks: Dictionary={"actual_entry":_actual_entry(c)}
	var visit: Dictionary=flow_visit(c)
	var ticket: String=str(visit.ticket_id)
	c.world.facts.tickets[ticket].waited_ticks=125
	c.world.facts.tickets[ticket].wait_accounted_tick=c.world.sim_tick
	var ledger: Dictionary=c.world.facts.ledger.entries.duplicate(true)
	var diagnosis: Dictionary=visit.diagnosis.duplicate(true)
	flow_exact_draw(c.world,"registration",0,2)
	checks.original_queue=await flow_until(t,c,func()->bool:return flow_guide(c).has("queue_seq"),1400)
	var old_desk: String=str(flow_guide(c).get("desk_id",""))
	var old_queue: int=int(flow_guide(c).get("queue_seq",-1))
	var guide: HospitalFloorGuidance=c.sim.services.floor_guidance
	checks.other_floor_selected=guide._select_floor(c.world,visit,flow_guide(c),true)
	checks.old_queue_not_carried=flow_guide(c).get("desk_id","")!=old_desk and int(flow_guide(c).get("queue_seq",-1))==-1 and not visit.id in guide._desk_queue(c.world,old_desk)
	checks.actual_floor_arrival=await flow_until(t,c,func()->bool:return c.world.facts.actors[visit.actor_id].location.kind=="floor" and int(c.world.facts.actors[visit.actor_id].location.floor_id)==2,2800)
	checks.business_facts_preserved=visit.ticket_id==ticket and int(c.world.facts.tickets.get(ticket,{}).get("waited_ticks",0))>=125 and visit.diagnosis==diagnosis and c.world.facts.ledger.entries==ledger
	checks.save_in_new_queue=_roundtrip(c).get("ok",false)
	checks.original_sequence_not_restored=not flow_guide(c).has("queue_seq") or flow_guide(c).get("desk_id","")!=old_desk or int(flow_guide(c).queue_seq)!=old_queue
	var life: Dictionary=await _seat_and_need(t)
	checks.merge(life.checks)
	flow_check(t,"CLFLOW-25",checks,c,{"life_handoff":life})

func _seat_and_need(t) -> Dictionary:
	var c: Dictionary=flow_context()
	var checks: Dictionary={}
	# A lawful slower explanation is input before the first GP starts. Its
	# real work creates a queue for the second patient; no synthetic lock,
	# extended Session or shortened travel is introduced.
	var admitted: CommandResult=_command(c,"clinical_arrive",{"arrival_key":"flow-slow-gp","binding_id":"B_S49_D37_M37","requested_plan_id":"P_D37_COMMON","personality_id":"PP08","expression":"off_topic"})
	checks.first_real_entry=admitted.accepted
	if not admitted.accepted: return {"checks":checks,"arrival":admitted.to_record()}
	c.visit_id=str(admitted.changed_ids[0])
	checks.first_consent=_command(c,"clinical_visit_consent",{"visit_id":c.visit_id,"allow":false}).accepted
	flow_exact_draw(c.world,"treatment",9999)
	checks.first_real_gp=await flow_until(t,c,func()->bool:return not _session(c,"gp").is_empty(),2400)
	var first: Dictionary={"visit":flow_visit(c).duplicate(true),"session":_session(c,"gp").duplicate(true)}
	if not checks.first_real_gp: return {"checks":checks,"first":first}
	checks.second_real_entry=_arrive(c,"B_S49_D37_M37","P_D37_COMMON")
	if not checks.second_real_entry: return {"checks":checks,"first":first}
	var ticket: String=str(flow_visit(c).ticket_id)
	checks.actual_waiting_seat=await flow_until(t,c,func()->bool:return HospitalWaitingLife.is_seated(c.world,c.visit_id),1800)
	if not checks.actual_waiting_seat: return {"checks":checks,"first":first,"visit":flow_visit(c).duplicate(true)}
	ticket=str(flow_visit(c).ticket_id)
	var target: String=str(flow_guide(c).get("target_id",""))
	var waited: int=int(c.world.facts.tickets.get(ticket,{}).get("waited_ticks",0))
	c.sim.services.waiting._begin_need(c.world,flow_visit(c))
	var work: Dictionary={"using":false,"same_ticket":true}
	var returned: bool=await flow_watch(t,c,func()->bool:return work.using and not c.world.facts.waiting_life.needs.has(c.visit_id),func()->void:
		var need: Dictionary=c.world.facts.waiting_life.needs.get(c.visit_id,{})
		work.using=work.using or need.get("phase","")=="using"
		work.same_ticket=work.same_ticket and flow_visit(c).ticket_id==ticket,2400)
	checks.actual_life_work_and_return=returned and work.using
	checks.life_keeps_business_ticket=returned and work.same_ticket and flow_visit(c).ticket_id==ticket and int(c.world.facts.tickets.get(ticket,{}).get("waited_ticks",0))>=waited
	checks.life_returns_original_room=returned and flow_guide(c).get("target_id","")==target and not target.is_empty() and c.sim.services.floor_guidance.scope.allows(c.world,flow_visit(c).actor_id,target,int(c.world.facts.facilities[target].floor_id),c.world.facts.actors[flow_visit(c).actor_id].location.cell)
	return {"checks":checks,"first":first,"work":work,"ticket":ticket,"waited_before":waited,"visit":flow_visit(c).duplicate(true)}
