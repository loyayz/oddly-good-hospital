extends "res://tests/acceptance/clinical_flow_fixtures.gd"

func run(t, database: HospitalContent, selected: Array = []) -> void:
	var wanted: Array=[]
	for id: String in ["FOLLOWUP-01","CLFLOW-28"]:
		if t.wants(id) and (selected.is_empty() or id in selected): wanted.append(id)
	if wanted.is_empty(): return
	flow_initialize(t,database)
	for id: String in wanted:
		t.begin_case(id)
		_fixture_failures.clear()
		if id=="FOLLOWUP-01": await _followup(t)
		else: await _after_complaint(t)
	_dispose_simulations()

func _remembered_patient(c: Dictionary) -> Dictionary:
	var identity: Dictionary=c.sim.services.arrivals._new_identity(c.world,"S13")
	identity.remembered=true
	c.world.facts.residents[identity.id]=identity
	var result: CommandResult=_command(c,"clinical_arrive",{"arrival_key":"followup-original","binding_id":"B_S13_D09_M09","resident_id":identity.id,"name":identity.name,"personality_id":identity.personality_id,"expression":"clear"})
	if not result.accepted: return {}
	c.visit_id=result.changed_ids[0]
	var actor: Dictionary=c.world.facts.actors[flow_visit(c).actor_id]
	actor.appearance=identity.appearance.duplicate(true)
	identity.current_actor_id=actor.id
	return identity

func _eligible_later(c: Dictionary, tick: int) -> Dictionary:
	var input: Dictionary=flow_freeze(c)
	input.facts.sim_tick=tick
	return flow_restore(input)

func _natural_again(c: Dictionary, resident_id: String) -> Dictionary:
	# Each candidate is an independent legal random INPUT before the one
	# opportunity. No committed arrival in a running world is ever rerolled.
	var input: Dictionary=flow_freeze(c)
	for seed_value: int in range(1,129):
		var next: Dictionary=flow_restore(input)
		var service: HospitalArrivalService=next.sim.services.arrivals
		for disease: Dictionary in _content.catalog.diseases:
			service.execute(next.world,"arrivals_weight",{"disease_id":disease.id,"weight":1 if disease.id=="D09" else 0})
		service.execute(next.world,"arrivals_intake",{"open":true})
		var generator:=RandomNumberGenerator.new()
		generator.seed=seed_value
		next.world.facts.rng.arrival={"algorithm":"godot-pcg32-4.7.2","seed_decimal":str(seed_value),"state_decimal":str(generator.state)}
		var day: int=next.world.sim_tick/WorldState.TICKS_PER_DAY+1
		var one: Dictionary={"n":"1","d":"1"}
		next.world.facts.arrivals.plan={"day_index":day,"preset":"normal","scale_numerator":1,"shift_capacities":[one.duplicate(),one.duplicate(),one.duplicate()],"opportunity_count":1,"shift_opportunity_counts":[1,0,0],"schedule_seed":"1","schedule_algorithm":"arrival-slot-v1","next_slot_index":0,"held_capacity_fraction":one.duplicate(),"held_scale_numerator":1}
		service.arrivals(next.world)
		for visit: Dictionary in next.world.facts.visits.values():
			if not input.facts.visits.has(visit.id) and next.world.facts.actors[visit.actor_id].get("resident_id","")==resident_id:
				next.visit_id=visit.id
				return next
	return {}

func _fresh_checks(next: Dictionary, old_visit: String, resident: Dictionary) -> Dictionary:
	var checks: Dictionary={"natural_new_visit":not next.is_empty()}
	if next.is_empty(): return checks
	var visit: Dictionary=flow_visit(next)
	var actor: Dictionary=next.world.facts.actors[visit.actor_id]
	checks.new_identity_claim=visit.id!=old_visit and actor.resident_id==resident.id and actor.name==resident.name and actor.appearance==resident.appearance and actor.location.kind=="floor" and int(actor.location.floor_id)==int(next.world.facts.entry.floor_id) and actor.location.cell==next.world.facts.entry.cell
	checks.new_clinical_state=visit.diagnosis.is_empty() and visit.attempt_ids.is_empty() and visit.plan_decision.is_empty() and not visit.has("continuation") and not visit.has("continuation_complaint") and visit.final_result==""
	checks.new_patient_state=visit.personality_id==resident.personality_id and float(visit.anger)==float(_content.definition("patient_personalities",resident.personality_id).initial_anger)
	var receipts: int=0
	for entry: Dictionary in next.world.facts.ledger.entries.values():
		if entry.owner_id==visit.id: receipts+=1
	checks.no_old_fee_credit=receipts==0
	return checks

func _followup(t) -> void:
	var c: Dictionary=flow_context()
	var resident: Dictionary=_remembered_patient(c)
	var checks: Dictionary={"actual_original_entry":not resident.is_empty(),"unchanged_config":float(_content.balance.resident_returns.probability)==0.2 and int(_content.balance.resident_returns.minimum_absence_days)==2}
	if resident.is_empty(): flow_check(t,"FOLLOWUP-01",checks,c);return
	flow_exact_draw(c.world,"treatment",9999)
	checks.gp=await flow_until(t,c,func()->bool:return flow_visit(c).diagnosis.get("gp_completed",false),2400)
	flow_exact_draw(c.world,"treatment",0)
	checks.actual_departure=await flow_finish_visit(t,c,3600)
	c.sim.services.arrivals.settle(c.world)
	var old_visit: String=str(c.visit_id)
	var departed: int=int(resident.last_departure_tick)
	checks.real_departure_record=departed>=0 and resident.last_visit_id==old_visit and resident.current_actor_id==""
	var early: Dictionary=_eligible_later(c,departed+36000-1)
	flow_uniform_arrival(early.world,1999)
	var rng: Dictionary=early.world.facts.rng.arrival.duplicate(true)
	checks.before_two_days_rejected=early.sim.services.arrivals._returning_resident(early.world,"S13","B_S13_D09_M09").is_empty() and early.world.facts.rng.arrival==rng
	for roll: int in [1999,2000]:
		var boundary: Dictionary=_eligible_later(c,departed+36000)
		flow_uniform_arrival(boundary.world,roll)
		var selected: Dictionary=boundary.sim.services.arrivals._returning_resident(boundary.world,"S13","B_S13_D09_M09")
		checks["twenty_percent_"+str(roll)]=(not selected.is_empty() and selected.id==resident.id) if roll==1999 else selected.is_empty()
	var incompatible: Dictionary=_eligible_later(c,departed+36000)
	checks.incompatible_rejected=incompatible.sim.services.arrivals._returning_resident(incompatible.world,"S49","B_S49_D37_M37").is_empty()
	var at_day_end: int=((departed+36000)/18000)*18000+17999
	var future: Dictionary=_eligible_later(c,at_day_end)
	var next: Dictionary=_natural_again(future,str(resident.id))
	checks.merge(_fresh_checks(next,old_visit,resident))
	if not next.is_empty():
		flow_uniform_arrival(next.world,1999)
		checks.in_hospital_identity_exclusive=next.sim.services.arrivals._returning_resident(next.world,"S13","B_S13_D09_M09").is_empty()
	flow_check(t,"FOLLOWUP-01",checks,next if not next.is_empty() else c,{"naming_verification":"玩家名称由内容/界面静态检查另行验证"})

func _after_complaint(t) -> void:
	var base: Dictionary=await flow_boundary(t,"continuation_second_outside")
	var checks: Dictionary={"actual_second_exit_boundary":not base.is_empty()}
	if base.is_empty(): flow_check(t,"CLFLOW-28",checks);return
	var c: Dictionary=flow_outside_return_input(base,2)
	var resident: Dictionary=c.sim.services.arrivals._new_identity(c.world,"S13")
	resident.remembered=true
	resident.current_actor_id=""
	c.world.facts.residents[resident.id]=resident
	var actor: Dictionary=c.world.facts.actors[flow_visit(c).actor_id]
	actor.resident_id=resident.id
	actor.name=resident.name
	actor.appearance=resident.appearance.duplicate(true)
	checks.offshift=flow_schedule(c,str(flow_visit(c).diagnosis.doctor_id),"rest")
	c.clinical_scenario=false
	var before: Dictionary=flow_return_probe(c)
	checks.real_entry=await flow_until(t,c,func()->bool:return c.world.facts.actors[flow_visit(c).actor_id].location.kind=="floor",40)
	if checks.real_entry: checks.merge(flow_return_checks(c,before))
	checks.complaint_then_real_exit=await flow_finish_visit(t,c,3600)
	c.sim.services.arrivals.settle(c.world)
	var old: String=str(c.visit_id)
	var old_history: Dictionary=flow_visit(c).diagnosis.duplicate(true)
	var old_complaint: Dictionary=flow_visit(c).get("continuation_complaint",{}).duplicate(true)
	checks.closed_original=flow_visit(c).continuation.stage=="finished" and not old_complaint.is_empty() and resident.last_visit_id==old
	flow_uniform_arrival(c.world,1999)
	checks.no_immediate_revival=c.sim.services.arrivals._returning_resident(c.world,"S13","B_S13_D09_M09").is_empty()
	var tick: int=((int(resident.last_departure_tick)+36000)/18000)*18000+17999
	var next: Dictionary=_natural_again(_eligible_later(c,tick),str(resident.id))
	checks.merge(_fresh_checks(next,old,resident))
	if not next.is_empty(): checks.old_stays_terminal=next.world.facts.visits[old].diagnosis==old_history and next.world.facts.visits[old].continuation_complaint==old_complaint and next.world.facts.visits[old].phase=="departed" and next.world.facts.visits[old].continuation.stage=="finished"
	flow_check(t,"CLFLOW-28",checks,next if not next.is_empty() else c)
