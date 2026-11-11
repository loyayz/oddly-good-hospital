extends "res://tests/acceptance/clinical_flow_fixtures.gd"

const IDS: Array[String]=["CLFLOW-13","CLFLOW-14","CLFLOW-15","CLFLOW-16","CLFLOW-17","CLFLOW-18","CLFLOW-26","CLFLOW-27","CLFLOW-29"]

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

func _tables(c: Dictionary, open_for_work: bool) -> void:
	for id: String in c.world.facility_ids("EQ01"): c.world.facts.facilities[id].open=open_for_work
	c.world.touch(false)

func _case_13(t) -> void:
	var base: Dictionary=await flow_boundary(t,"inpatient_wait")
	var checks: Dictionary={"actual_admission":not base.is_empty()}
	if base.is_empty(): flow_check(t,"CLFLOW-13",checks);return
	for missing_table: bool in [true,false]:
		var c: Dictionary=flow_restore(flow_freeze(base))
		var stay: Dictionary=flow_stay(c).duplicate(true)
		if missing_table: _tables(c,false)
		else: flow_schedule(c,"clin_surgeon","rest")
		await flow_steps(t,c,3100)
		var ward: Dictionary=flow_stay(c)
		checks["waits_"+str(missing_table)]=not ward.is_empty() and ward.id==stay.id and ward.phase=="waiting_surgery" and ward.bed_id==stay.bed_id and flow_visit(c).attempt_ids.is_empty() and not flow_visit(c).phase in ["leaving","departed","ward_referral"]
		checks["no_recovery_"+str(missing_table)]=int(ward.get("remaining_ticks",-1))==0 and not ward.get("care_completed",true) and _income(c,"ward")==0 and _income(c,"cure")==0 and _units_used(c)==0
		checks["no_guidance_loop_"+str(missing_table)]=flow_guide(c).is_empty() and c.world.facts.actors[flow_visit(c).actor_id].get("support_facility_id","")==stay.bed_id
	var absent: Dictionary=await _admit_without_installed_or(t)
	for key: String in absent.checks: checks["no_installed_or_"+key]=absent.checks[key]
	flow_check(t,"CLFLOW-13",checks,{}, {"no_installed_or":absent})

func _admit_without_installed_or(t) -> Dictionary:
	var world: WorldState=HospitalFactory.create(HospitalSnapshots.uuid(),"未装术台先住院",true,_content)
	var doctors: Array=[]
	for id: String in world.ids("staff"):
		var staff: Dictionary=world.facts.staff[id]
		if staff.role=="doctor": doctors.append(id)
		if staff.role in ["doctor","nurse"]:
			staff.personality_id="DP05"
			staff.schedule=_schedule("outpatient" if staff.role=="doctor" else "work")
			if staff.role=="nurse": staff.base_prepared=false
	for index: int in doctors.size():
		var doctor: Dictionary=world.facts.staff[doctors[index]]
		doctor.schedule=_schedule("outpatient",["room_gp" if index==0 else "room_physical"]) if index<2 else _schedule("rest")
		if index<2: doctor.abilities.treatment=2
	for definition: Dictionary in _content.catalog.research: world.facts.research.append(definition.id)
	_add_layout(world,"or_standard","clin_or",[33,65])
	_add_layout(world,"ward_two_beds","clin_ward",[45,65])
	_add_worker(world,"clin_surgeon","doctor",[34,75],"rest",{"diagnosis":1,"treatment":1,"care":0,"surgery":2},"DT02")
	_add_worker(world,"clin_anesthesia","doctor",[38,75],"rest",{"diagnosis":1,"treatment":1,"care":0,"surgery":2},"DT02")
	_add_worker(world,"clin_or_nurse","nurse",[42,75],"rest",{"diagnosis":1,"treatment":0,"care":1,"surgery":1})
	world.facts.staff.clin_or_nurse.certificates=["q_or","q_ward"]
	_add_worker(world,"clin_cover","nurse",[46,72],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":0},"DT01","clin_ward")
	_add_worker(world,"clin_round","doctor",[51,72],"outpatient",{"diagnosis":2,"treatment":1,"care":0,"surgery":0})
	var gp_abilities: Dictionary=world.facts.staff[doctors[0]].abilities.duplicate(true)
	var simulation:=HospitalSimulation.new(world,_content)
	_simulations.append(simulation)
	var c: Dictionary={"world":world,"sim":simulation,"serial":0,"visit_id":"","doctors":doctors,"started":{},"beats":{},"group_seen":false,"errors":[],"fixture_ready":true,"clinical_scenario":true}
	_command(c,"set_intake_open",{"open":false})
	_command(c,"tutorial_set_enabled",{"enabled":false})
	_command(c,"set_auto_restock",{"enabled":false})
	var checks: Dictionary={"before_first_step":world.sim_tick==0 and world.facts.visits.is_empty()}
	var stored: Array=[]
	for id: String in world.facility_ids("EQ01"):
		var result: CommandResult=_command(c,"build_store",{"target_id":id})
		stored.append(result.to_record())
		checks["store_"+id]=result.accepted and world.sim_tick==0
	checks.no_actual_or=world.facility_ids("EQ01").is_empty()
	checks.qualified_team_offshift=["clin_surgeon","clin_anesthesia","clin_or_nurse"].all(func(id: String)->bool:return world.facts.staff[id].schedule[0].kind=="rest")
	checks.real_ward_coverage=await flow_until(t,c,func()->bool:return _ward_nurse_return_state(c).ready,1200)
	flow_exact_draw(world,"treatment",9999)
	checks.real_entry=_arrive(c,"B_S13_D09_M09","P_D09_SURGERY")
	if not checks.real_entry: return {"checks":checks,"stored":stored}
	checks.real_gp_diagnosis=await flow_until(t,c,func()->bool:return flow_visit(c).diagnosis.get("state","")=="diagnosed" and str(flow_visit(c).phase).begins_with("wait_"),3000)
	checks.original_gp_abilities=world.facts.staff[doctors[0]].abilities==gp_abilities and int(gp_abilities.diagnosis)==1
	var selected: CommandResult=_command(c,"clinical_select_plan",{"visit_id":c.visit_id,"plan_id":"P_D09_SURGERY"})
	checks.legal_surgery_selected=selected.accepted
	checks.real_admission=selected.accepted and await flow_until(t,c,func()->bool:return flow_stay(c).has("admitted_tick") and flow_stay(c).get("phase","")=="waiting_surgery",2400)
	var admitted: Dictionary=flow_stay(c).duplicate(true)
	if checks.real_admission: await flow_steps(t,c,3100)
	checks.same_waiting_bed=checks.real_admission and flow_stay(c).get("id","")==admitted.get("id","") and flow_stay(c).get("bed_id","")==admitted.get("bed_id","") and flow_stay(c).get("phase","")=="waiting_surgery" and world.facts.actors[flow_visit(c).actor_id].get("support_facility_id","")==admitted.get("bed_id","")
	checks.no_premature_work=flow_visit(c).attempt_ids.is_empty() and _session(c,"surgery").is_empty() and _units_used(c)==0 and _income(c,"ward")==0 and _income(c,"cure")==0 and not flow_visit(c).phase in ["ward_referral","leaving","departed"]
	checks.world_valid=world.validate(_content).is_empty()
	return {"checks":checks,"stored":stored,"selection":selected.to_record(),"initial_gp_abilities":gp_abilities,"admitted":admitted,"final":flow_diagnostic(c)}

func _case_14(t) -> void:
	var c: Dictionary=await flow_boundary(t,"cross_floor_inpatient")
	var checks: Dictionary={"actual_cross_floor_admission":not c.is_empty()}
	if c.is_empty(): flow_check(t,"CLFLOW-14",checks);return
	var original: Dictionary=flow_stay(c).duplicate(true)
	var patient: String=str(flow_visit(c).actor_id)
	var seen: Dictionary={"transit":false,"or_floor":false,"wake":false,"bed_held":true,"escort":false}
	var preparation_trace: Dictionary={}
	flow_exact_draw(c.world,"treatment",0)
	var started: bool=await flow_watch(t,c,func()->bool:return not _session(c,"surgery").is_empty(),func()->void:
		flow_trace_preparation(c,preparation_trace)
		var actor: Dictionary=c.world.facts.actors[patient]
		seen.transit=seen.transit or actor.location.kind=="transit"
		seen.or_floor=seen.or_floor or actor.location.kind=="floor" and int(actor.location.floor_id)==2
		seen.bed_held=seen.bed_held and flow_stay(c).get("bed_id","")==original.bed_id,3600)
	checks.actual_operative_arrival=started and seen.transit and seen.or_floor
	if not started: flow_check(t,"CLFLOW-14",checks,c,{"observed":seen,"preparation_trace":flow_preparation_trace_result(preparation_trace)});return
	checks.or_layer_has_no_guidance=c.world.facility_ids("SE01").all(func(id: String)->bool:return int(c.world.facts.facilities[id].floor_id)!=2)
	var returned: bool=await flow_watch(t,c,func()->bool:return flow_stay(c).get("phase","")=="recovery",func()->void:
		seen.wake=seen.wake or not _session(c,"wake").is_empty()
		seen.bed_held=seen.bed_held and flow_stay(c).get("bed_id","")==original.bed_id
		for move: Dictionary in c.world.facts.moves.values():
			if patient in move.get("members",[]) and move.get("members",[]).size()>1: seen.escort=true,5000)
	checks.real_wake_and_escort=returned and seen.wake and seen.escort
	checks.same_reserved_bed=returned and seen.bed_held and flow_stay(c).id==original.id and c.world.facts.actors[patient].get("support_facility_id","")==original.bed_id and int(c.world.facts.actors[patient].location.floor_id)==1
	flow_check(t,"CLFLOW-14",checks,c,{"observed":seen,"preparation_trace":flow_preparation_trace_result(preparation_trace)})

func _case_15(t) -> void:
	var base: Dictionary=await flow_boundary(t,"before_surgery")
	var checks: Dictionary={"actual_gathered_boundary":not base.is_empty()}
	if base.is_empty(): flow_check(t,"CLFLOW-15",checks);return
	var day: Dictionary=flow_clock_boundary(base,11999)
	flow_exact_draw(day.world,"treatment",0)
	_tick(day)
	checks.day_started=not _session(day,"surgery").is_empty() and flow_visit(day).attempt_ids.size()==1
	var night: Dictionary=flow_clock_boundary(base,12000)
	_tick(night)
	checks.night_not_started=_session(night,"surgery").is_empty() and flow_visit(night).attempt_ids.is_empty() and night.world.facts.preparations.is_empty()
	checks.night_returns_original_bed=await flow_until(t,night,func()->bool:return flow_stay(night).get("phase","")=="waiting_surgery",2200)
	if checks.day_started:
		var attempt: Dictionary=day.world.facts.attempts[flow_visit(day).attempt_ids[0]].duplicate(true)
		var commitment: Dictionary=_commitments({attempt.id:attempt})
		checks.started_finishes_after_night=await flow_until(t,day,func()->bool:return flow_stay(day).get("phase","")=="recovery",4800)
		checks.commitment_preserved=_commitments(day.world.facts.attempts).get(attempt.id,{})==commitment[attempt.id] and flow_stay(day).attempt_id==attempt.id
	flow_check(t,"CLFLOW-15",checks)

func _case_16(t) -> void:
	var c: Dictionary=await flow_boundary(t,"cross_floor_inpatient")
	var checks: Dictionary={"inpatient_boundary":not c.is_empty()}
	if c.is_empty(): flow_check(t,"CLFLOW-16",checks);return
	var original: Dictionary=flow_stay(c).duplicate(true)
	var transit: Dictionary={"seen":false,"no_deadline":true}
	var preparation_trace: Dictionary={}
	checks.gathered=await flow_watch(t,c,func()->bool:return int(c.world.facts.preparations.get(c.visit_id,{}).get("deadline_tick",-1))>=0,func()->void:
		flow_trace_preparation(c,preparation_trace)
		var preparation: Dictionary=c.world.facts.preparations.get(c.visit_id,{})
		if not preparation.is_empty() and c.world.facts.actors[flow_visit(c).actor_id].location.kind=="transit":
			transit.seen=true
			transit.no_deadline=transit.no_deadline and int(preparation.deadline_tick)==-1,3600)
	checks.travel_not_in_prepare_window=transit.seen and transit.no_deadline
	if not checks.gathered: flow_check(t,"CLFLOW-16",checks,c,{"transit":transit,"preparation_trace":flow_preparation_trace_result(preparation_trace)});return
	var preparation: Dictionary=c.world.facts.preparations[c.visit_id]
	checks.thirty_seconds_from_arrival=int(preparation.deadline_tick)-c.world.sim_tick==299
	# Exact expiry boundary of an already real, gathered preparation. No actor
	# or completed work is moved to manufacture the subsequent return.
	preparation.deadline_tick=c.world.sim_tick
	_tick(c)
	flow_trace_preparation(c,preparation_trace)
	checks.uncommitted_released=c.world.facts.preparations.is_empty() and flow_visit(c).attempt_ids.is_empty() and _units_used(c)==0
	checks.safe_return=await flow_until(t,c,func()->bool:return flow_stay(c).get("phase","")=="waiting_surgery",2600)
	checks.same_admission=flow_stay(c).get("id","")==original.id and flow_stay(c).get("bed_id","")==original.bed_id and flow_stay(c).get("admitted_tick",-1)==original.admitted_tick and flow_stay(c).get("companion_qualified") ==original.get("companion_qualified")
	# A real connector outage before departure is a separate route input.
	var blocked: Dictionary=await flow_boundary(t,"cross_floor_inpatient")
	for connection: Dictionary in blocked.world.facts.connectors.values(): connection.failed=true
	await flow_steps(t,blocked,40)
	checks.route_outage_does_not_commit=flow_visit(blocked).attempt_ids.is_empty() and flow_stay(blocked).get("id","")==original.id and _units_used(blocked)==0
	flow_check(t,"CLFLOW-16",checks,c,{"transit":transit,"preparation_trace":flow_preparation_trace_result(preparation_trace)})

func _case_17(t) -> void:
	var base: Dictionary=await flow_boundary(t,"inpatient_wait")
	var checks: Dictionary={"inpatient_boundary":not base.is_empty()}
	var failures: Dictionary={}
	var decisions: Dictionary={}
	if base.is_empty(): flow_check(t,"CLFLOW-17",checks);return
	for repeat_surgery: bool in [true,false]:
		var c: Dictionary=flow_restore(flow_freeze(base))
		var original: Dictionary=flow_stay(c).duplicate(true)
		c.world.facts.staff.clin_surgeon.abilities.treatment=2
		flow_exact_draw(c.world,"treatment",9999)
		var began: bool=await flow_until(t,c,func()->bool:return not _session(c,"surgery").is_empty(),3000)
		checks["first_started_"+str(repeat_surgery)]=began
		if not began:
			failures[str(repeat_surgery)]=flow_diagnostic(c)
			continue
		var first: Dictionary=c.world.facts.attempts[flow_visit(c).attempt_ids[0]]
		checks["first_failed_"+str(repeat_surgery)]=not first.result
		if repeat_surgery:
			for id: String in c.world.facility_ids("M09"): c.world.facts.facilities[id].intake_open=false
		var safety: Dictionary={"returned":false,"care":false,"recovery_done":false,"no_early_retry":true}
		var settled: bool=await flow_watch(t,c,func()->bool:return flow_visit(c).get("result_receipt",{}).get("attempt_id","")==first.id,func()->void:
			var stay: Dictionary=flow_stay(c)
			if stay.get("phase","")=="recovery":
				safety.returned=true
				safety.care=safety.care or stay.get("care_completed",false)
				safety.recovery_done=safety.recovery_done or int(stay.remaining_ticks)==0
			if not safety.care or not safety.recovery_done: safety.no_early_retry=safety.no_early_retry and flow_visit(c).attempt_ids.size()==1,6000)
		checks["safe_before_retry_"+str(repeat_surgery)]=settled and safety.returned and safety.no_early_retry and int(flow_stay(c).get("remaining_ticks",-1))==0 and flow_stay(c).get("care_completed",false)
		decisions[str(repeat_surgery)]={"at_receipt":_decision_evidence(c)}
		flow_exact_draw(c.world,"treatment",0)
		var expected_kind: String="surgery" if repeat_surgery else "outpatient"
		var automatic: Dictionary={"seen":false}
		# Result settlement may leave wait_plan for the next real dispatch.
		# Observe the doctor's actual automatic choice through the same retry
		# window, without requiring it on the receipt's own tick.
		var second: bool=await flow_watch(t,c,func()->bool:return flow_visit(c).attempt_ids.size()==2,func()->void:
			var decision: Dictionary=flow_visit(c).plan_decision
			var protocol: Dictionary=_content.definition("treatment_protocols",_content.definition("treatment_plans",str(decision.get("plan_id",""))).get("protocol_id",""))
			if not automatic.seen and decision.get("source","")=="doctor" and protocol.get("kind","")==expected_kind:
				automatic.seen=true
				automatic.evidence=_decision_evidence(c),3000)
		var second_attempt: Dictionary=c.world.facts.attempts[flow_visit(c).attempt_ids[1]] if second else {}
		var second_kind: String=str(_content.definition("treatment_protocols",_content.definition("treatment_plans",str(second_attempt.get("plan_id",""))).get("protocol_id","")).get("kind",""))
		checks["auto_second_plan_"+str(repeat_surgery)]=automatic.seen and second and second_kind==expected_kind
		checks["second_actual_start_"+str(repeat_surgery)]=second and flow_stay(c).get("id","")==original.id and flow_stay(c).get("bed_id","")==original.bed_id and flow_stay(c).get("admitted_tick",-1)==original.admitted_tick
		decisions[str(repeat_surgery)].automatic=automatic
		decisions[str(repeat_surgery)].at_second_start=_decision_evidence(c)
	flow_check(t,"CLFLOW-17",checks,{}, {"failures":failures,"decisions":decisions})

func _decision_evidence(c: Dictionary) -> Dictionary:
	var visit: Dictionary=flow_visit(c)
	var decision: Dictionary=visit.plan_decision.duplicate(true)
	var plan: Dictionary=_content.definition("treatment_plans",str(decision.get("plan_id","")))
	var protocol: Dictionary=_content.definition("treatment_protocols",str(plan.get("protocol_id","")))
	var doctor_id: String=str(decision.get("doctor_id",visit.diagnosis.get("doctor_id","")))
	var doctor: Dictionary=c.world.facts.staff.get(doctor_id,{})
	var personality: Dictionary=_content.definition("doctor_personalities",str(doctor.get("personality_id","")))
	var ordinary: Dictionary={}
	for id: String in c.world.facility_ids("M09"): ordinary[id]={"open":c.world.facts.facilities[id].get("open",true),"intake_open":c.world.facts.facilities[id].get("intake_open",true),"failed":c.world.facts.facilities[id].failed}
	return {"tick":c.world.sim_tick,"actual_decision":decision,"protocol_kind":protocol.get("kind",""),"visit_phase":visit.phase,"stay":flow_stay(c).duplicate(true),"attempt_ids":visit.attempt_ids.duplicate(),"strategy":c.world.facts.get("plan_strategy","doctor"),"doctor_id":doctor_id,"doctor_abilities":doctor.get("abilities",{}).duplicate(),"personality_id":doctor.get("personality_id",""),"personality_weights":personality.get("weights",{}).duplicate(),"ordinary_equipment":ordinary,"selection_source":{"reconsider":"game/clinic/clinical_flow.gd:reconsider/choose_plan","scoring":"game/clinic/clinical_runtime.gd:_select_plan_in_query","ordering":"game/clinic/clinical_runtime.gd:_choose_plan"}}

func _case_18(t) -> void:
	var c: Dictionary=await flow_boundary(t,"inpatient_wait")
	var checks: Dictionary={"inpatient_boundary":not c.is_empty()}
	if c.is_empty(): flow_check(t,"CLFLOW-18",checks);return
	_tables(c,false)
	await flow_steps(t,c,200)
	checks.no_future_recovery=flow_visit(c).attempt_ids.is_empty() and int(flow_stay(c).remaining_ticks)==0 and not flow_stay(c).care_completed and _income(c,"ward")==0
	_tables(c,true)
	var patient: String=str(flow_visit(c).actor_id)
	var original_actor: Dictionary=c.world.facts.actors[patient].duplicate(true)
	var bed_id: String=str(flow_stay(c).bed_id)
	var original_owner: String=str(c.world.facts.adaptations.get(bed_id,{}).get("owner_id",""))
	var ticket_id: String=str(flow_visit(c).ticket_id)
	var original_ticket: Dictionary=c.world.facts.tickets.get(ticket_id,{}).duplicate(true)
	var original_rng: Dictionary=c.world.facts.rng.duplicate(true)
	var before_quote: Dictionary=c.world.freeze()
	var quote: Dictionary=c.sim.clinic.plan_quote(c.world,c.visit_id,str(flow_visit(c).plan_decision.plan_id))
	var tables: Array=c.world.facility_ids("EQ01")
	var table_id: String=str(quote.get("facility_id",tables[0] if not tables.is_empty() else ""))
	var layout: Dictionary=c.sim.space.facility_layout(c.world,table_id) if not table_id.is_empty() else {}
	var travel: Dictionary=c.sim.space.travel_quote(c.world,patient,int(layout.floor_id),layout.patient_cell) if not layout.is_empty() else {"ok":false,"reason":"缺少真实手术台患者位"}
	var cells_before_cost: int=int(c.sim.space.query_counts.materialized_floor_cells)
	var cost: Dictionary=c.sim.space.route_cost(c.world,patient,int(layout.floor_id),layout.patient_cell) if not layout.is_empty() else {"ok":false,"reason":"缺少真实手术台患者位"}
	var materialized_cost_cells: int=int(c.sim.space.query_counts.materialized_floor_cells)-cells_before_cost
	var route: Dictionary=c.sim.space.route(c.world,patient,int(layout.floor_id),layout.patient_cell) if not layout.is_empty() else {"ok":false,"reason":"缺少真实手术台患者位"}
	var route_fields: Dictionary=route.duplicate(true)
	route_fields.erase("path")
	route_fields.erase("cells")
	checks.supported_plan_quote=quote.get("ok",false)
	checks.supported_route_quote=travel.get("ok",false)
	checks.supported_quote_fields_equal=route_fields==cost and cost==travel
	checks.full_route_starts_with_actual_support_exit=route.get("ok",false) and not route.get("path",[]).is_empty() and route.path[0].get("kind","")=="support_exit" and int(route.path[0].get("floor_id",-1))==int(c.world.facts.facilities[bed_id].floor_id) and route.path[0].get("cell",[])==c.sim.space.facility_layout(c.world,bed_id).patient_cell
	checks.cost_does_not_materialize_path=not cost.has("path") and not cost.has("cells") and materialized_cost_cells==0
	checks.quotes_leave_world_unchanged=c.world.freeze()==before_quote
	checks.quotes_keep_real_lying_actor=c.world.facts.actors[patient]==original_actor and original_actor.get("posture","")=="lying"
	checks.quotes_keep_original_bed_ticket_rng=str(c.world.facts.adaptations.get(bed_id,{}).get("owner_id",""))==original_owner and flow_visit(c).ticket_id==ticket_id and c.world.facts.tickets.get(ticket_id,{})==original_ticket and c.world.facts.rng==original_rng
	var quote_results: Dictionary={"plan_ok":quote.get("ok",false),"plan_reason":quote.get("reason",""),"travel":travel,"route_fields":route_fields,"cost":cost,"materialized_cost_cells":materialized_cost_cells,"first_path_segment":route.get("path",[])[0] if not route.get("path",[]).is_empty() else {},"table_id":table_id,"patient_cell":layout.get("patient_cell",[])}
	flow_exact_draw(c.world,"treatment",0)
	checks.surgery_started=await flow_until(t,c,func()->bool:return not _session(c,"surgery").is_empty(),3000)
	if not checks.surgery_started: flow_check(t,"CLFLOW-18",checks,c,{"failure":flow_diagnostic(c),"quote_results":quote_results});return
	var attempt: Dictionary=c.world.facts.attempts[flow_visit(c).attempt_ids[0]].duplicate(true)
	checks.target_frozen=int(flow_stay(c).remaining_ticks)==int(attempt.recovery_ticks) and not flow_stay(c).care_completed
	checks.real_return=await flow_until(t,c,func()->bool:return flow_stay(c).get("phase","")=="recovery",4500)
	var premature: Dictionary={"none":true,"care_seen":false,"recovery_ticks":0}
	var finished: bool=await flow_watch(t,c,func()->bool:return flow_visit(c).get("result_receipt",{}).get("attempt_id","")==attempt.id,func()->void:
		var stay: Dictionary=flow_stay(c)
		if stay.is_empty(): return
		premature.care_seen=premature.care_seen or not _session(c,"care").is_empty()
		if stay.get("phase","")=="recovery": premature.recovery_ticks+=1
		if int(stay.remaining_ticks)>0 or not stay.care_completed: premature.none=premature.none and _income(c,"ward")==0 and _income(c,"cure")==0,4000)
	checks.required_work_and_billing=finished and premature.none and premature.care_seen and int(premature.recovery_ticks)>0 and _income(c,"ward")==60 and _income(c,"cure")==int(attempt.cure_fee)
	flow_check(t,"CLFLOW-18",checks,c,{"work_observation":premature,"quote_results":quote_results})

func _case_26(t) -> void:
	var base: Dictionary=await flow_boundary(t,"ward_recovery")
	var checks: Dictionary={"recovery_boundary":not base.is_empty()}
	if base.is_empty(): flow_check(t,"CLFLOW-26",checks);return
	var outcomes: Dictionary={}
	for bed_fault: bool in [true,false]:
		var c: Dictionary=flow_restore(flow_freeze(base))
		if bed_fault:
			for id: String in c.world.facility_ids("EQ05"): c.world.facts.facilities[id].failed=true
		else: _all_rest(c.world,"nurse")
		var limit: int=1200 if bed_fault else 3000
		var bed_events: Array=[]
		var observed: Dictionary={"signature":""}
		var work: Dictionary={"billing_waited":true,"care_seen":false}
		var attempt: Dictionary=c.world.facts.attempts.get(str(flow_stay(c).get("attempt_id","")),{}).duplicate(true)
		await flow_watch(t,c,func()->bool:return c.world.sim_tick>=int(base.world.sim_tick)+limit-1,func()->void:_observe_fault_work(c,bed_events,observed,work),limit-1)
		var before_limit: Dictionary=_fault_outcome(c)
		checks["before_limit_"+str(bed_fault)]=not flow_visit(c).phase in ["ward_referral","leaving","departed"]
		if bed_fault:
			var completed: bool=await flow_watch(t,c,func()->bool:return flow_visit(c).get("result_receipt",{}).get("attempt_id","")==attempt.get("id","missing"),func()->void:_observe_fault_work(c,bed_events,observed,work),1800)
			checks.auto_repair_completed_required_work=completed and work.billing_waited and work.care_seen and flow_stay(c).get("care_completed",false) and int(flow_stay(c).get("remaining_ticks",-1))==0 and not c.world.facts.facilities[str(flow_stay(c).bed_id)].failed
			checks.auto_repair_legitimate_fees=completed and flow_visit(c).final_result=="cured" and _income(c,"ward")==60 and _income(c,"cure")==int(attempt.get("cure_fee",-1))
			outcomes.automatic_repair={"expected_completed_income":{"ward":60,"cure":int(attempt.get("cure_fee",-1))},"before_limit":before_limit,"final":_fault_outcome(c),"bed_events":bed_events,"work":work}
		else:
			checks["safe_referral_"+str(bed_fault)]=await flow_watch(t,c,func()->bool:return flow_visit(c).phase in ["ward_referral","leaving","departed"],func()->void:_observe_bed_condition(c,bed_events,observed),1800)
			checks["uncompleted_not_charged_"+str(bed_fault)]=_income(c,"ward")==0 and _income(c,"cure")==0
			outcomes.nurse_shortage={"expected_uncompleted_income":{"ward":0,"cure":0},"before_limit":before_limit,"final":_fault_outcome(c),"bed_events":bed_events}
	var persistent: Dictionary=await _persistent_bed_fault(t,base)
	for key: String in persistent.checks: checks["persistent_"+key]=persistent.checks[key]
	outcomes.persistent_bed_fault=persistent
	var pending: Dictionary=await flow_boundary(t,"inpatient_wait")
	_tables(pending,false)
	await flow_steps(t,pending,3100)
	checks.only_or_shortage_keeps_waiting=flow_stay(pending).get("phase","")=="waiting_surgery" and not flow_visit(pending).phase in ["ward_referral","leaving","departed"]
	flow_check(t,"CLFLOW-26",checks,{}, {"outcomes":outcomes})

func _persistent_bed_fault(t, base: Dictionary) -> Dictionary:
	var c: Dictionary=flow_restore(flow_freeze(base))
	var beds: Array=c.world.facility_ids("EQ05").duplicate()
	for id: String in beds: c.world.facts.facilities[id].failed=true
	var checks: Dictionary={"faulted_beds_present":not beds.is_empty()}
	var commands: Array=[]
	var jobs: Dictionary={}
	var accepted: bool=true
	# Both commands are the normal maintenance surface. Pause the first
	# accepted order for each failed bed before any simulation step can repair
	# it; rejected input remains a failed prerequisite, without replacement.
	for id: String in beds:
		var quote: Dictionary=c.sim.services.maintenance.service_quote(c.world,id)
		var order: CommandResult=_command(c,"maintenance_order",{"facility_id":id,"cost":int(quote.get("cost",-1))})
		commands.append({"kind":"maintenance_order","facility_id":id,"quote":quote,"result":order.to_record()})
		var ordered: bool=order.accepted and not order.changed_ids.is_empty() and c.world.facts.maintenance.jobs.has(str(order.changed_ids[0]))
		checks["ordered_"+id]=ordered
		if not ordered: accepted=false;continue
		var job_id: String=str(order.changed_ids[0])
		jobs[id]=job_id
		var pause: CommandResult=_command(c,"maintenance_pause",{"job_id":job_id})
		commands.append({"kind":"maintenance_pause","job_id":job_id,"result":pause.to_record()})
		checks["paused_"+id]=pause.accepted and c.world.facts.maintenance.jobs[job_id].facility_id==id and c.world.facts.maintenance.jobs[job_id].paused
		accepted=accepted and checks["paused_"+id]
	if not accepted: return {"checks":checks,"commands":commands,"final":_fault_outcome(c)}
	var events: Array=[]
	var observed: Dictionary={"signature":""}
	var persistence: Dictionary={"all_failed":true,"all_jobs_paused":true}
	var last_progress: int=int(flow_stay(c).last_progress_tick)
	var deadline: int=last_progress+1200
	await flow_watch(t,c,func()->bool:return c.world.sim_tick>=deadline,func()->void:_observe_persistent_beds(c,beds,jobs,events,observed,persistence),maxi(0,deadline-c.world.sim_tick))
	checks.no_early_referral=c.world.sim_tick==deadline and not flow_visit(c).phase in ["ward_referral","leaving","departed"] and int(flow_stay(c).last_progress_tick)==last_progress
	var at_boundary: Dictionary=_fault_outcome(c)
	_tick(c)
	_observe_persistent_beds(c,beds,jobs,events,observed,persistence)
	checks.referral_at_120_seconds=flow_visit(c).phase=="ward_referral" and flow_stay(c).get("phase","")=="referral_release"
	checks.actual_safe_exit=await flow_watch(t,c,func()->bool:return flow_visit(c).phase=="departed",func()->void:_observe_persistent_beds(c,beds,jobs,events,observed,persistence),1800)
	checks.actual_safe_exit=checks.actual_safe_exit and c.world.facts.actors[flow_visit(c).actor_id].location.kind=="outside" and not c.world.facts.moves.has(flow_visit(c).actor_id) and flow_visit(c).final_result=="referred"
	checks.failed_throughout=persistence.all_failed and persistence.all_jobs_paused
	checks.uncompleted_not_charged=_income(c,"ward")==0 and _income(c,"cure")==0
	checks.world_valid=c.world.validate(_content).is_empty()
	return {"checks":checks,"commands":commands,"job_ids":jobs,"last_progress_tick":last_progress,"deadline_tick":deadline,"at_boundary":at_boundary,"final":_fault_outcome(c),"bed_events":events,"persistence":persistence}

func _observe_persistent_beds(c: Dictionary, beds: Array, jobs: Dictionary, events: Array, observed: Dictionary, persistence: Dictionary) -> void:
	_observe_bed_condition(c,events,observed)
	for id: String in beds:
		persistence.all_failed=persistence.all_failed and c.world.facts.facilities.get(id,{}).get("failed",false)
		var job: Dictionary=c.world.facts.maintenance.jobs.get(str(jobs.get(id,"")),{})
		persistence.all_jobs_paused=persistence.all_jobs_paused and job.get("paused",false) and job.get("phase","") not in ["completed","cancelled"] and int(job.get("completed_milli",-1))==0

func _observe_fault_work(c: Dictionary, events: Array, observed: Dictionary, work: Dictionary) -> void:
	_observe_bed_condition(c,events,observed)
	var stay: Dictionary=flow_stay(c)
	work.care_seen=work.care_seen or not _session(c,"care").is_empty()
	if stay.is_empty(): return
	if int(stay.get("remaining_ticks",-1))>0 or not stay.get("care_completed",false): work.billing_waited=work.billing_waited and _income(c,"ward")==0 and _income(c,"cure")==0

func _fault_outcome(c: Dictionary) -> Dictionary:
	var beds: Dictionary={}
	for id: String in c.world.facility_ids("EQ05"): beds[id]={"failed":c.world.facts.facilities[id].failed,"condition":c.world.facts.facilities[id].get("condition",-1.0)}
	var entries: Array=[]
	for entry: Dictionary in c.world.facts.ledger.entries.values():
		if entry.component in ["ward","cure"]: entries.append(entry.duplicate(true))
	return {"tick":c.world.sim_tick,"visit":flow_visit(c).duplicate(true),"stay":flow_stay(c).duplicate(true),"sessions":c.world.facts.sessions.duplicate(true),"actual_income":{"ward":_income(c,"ward"),"cure":_income(c,"cure")},"ledger_components":entries,"beds":beds,"maintenance":c.world.facts.get("maintenance",{}).duplicate(true)}

func _observe_bed_condition(c: Dictionary, events: Array, observed: Dictionary) -> void:
	var state: Dictionary={"beds":{},"jobs":{}}
	var details: Dictionary={"tick":c.world.sim_tick,"beds":{},"jobs":{}}
	for id: String in c.world.facility_ids("EQ05"):
		state.beds[id]=c.world.facts.facilities[id].failed
		details.beds[id]={"failed":c.world.facts.facilities[id].failed,"condition":c.world.facts.facilities[id].get("condition",-1.0)}
	for id: String in c.world.facts.get("maintenance",{}).get("jobs",{}):
		var job: Dictionary=c.world.facts.maintenance.jobs[id]
		if not c.world.facts.facilities.get(str(job.get("facility_id","")),{}).get("definition_id","")=="EQ05": continue
		state.jobs[id]=job.get("phase","")
		details.jobs[id]=job.duplicate(true)
	var signature: String=JSON.stringify(state,"",true,true)
	if signature==observed.signature: return
	observed.signature=signature
	events.append(details)

func _case_27(t) -> void:
	var base: Dictionary=await flow_boundary(t,"inpatient_wait")
	var checks: Dictionary={"admission_boundary":not base.is_empty() and base.has("before_admission")}
	if not checks.admission_boundary: flow_check(t,"CLFLOW-27",checks);return
	var c: Dictionary=flow_restore(base.before_admission)
	flow_exact_draw(c.world,"arrival",0)
	_tick(c)
	_tables(c,false)
	_command(c,"clinical_visit_consent",{"visit_id":c.visit_id,"allow":true})
	flow_exact_draw(c.world,"arrival",0)
	var family: bool=await flow_until(t,c,func()->bool:return not c.sim.clinic.visitors._role(c.world,c.visit_id,"companion").is_empty() and not c.sim.clinic.visitors._role(c.world,c.visit_id,"ward_visit").is_empty(),1500)
	checks.two_actual_family_roles=family
	var companion: String=str(flow_stay(c).get("companion_actor_id",""))
	var original_bed: String=str(flow_stay(c).get("bed_id",""))
	var original_stay: String=str(flow_stay(c).get("id",""))
	var visitor: Dictionary=c.sim.clinic.visitors._role(c.world,c.visit_id,"ward_visit")
	var left: int=int(visitor.get("remaining_ticks",-1))
	var rng: Dictionary=c.world.facts.rng.arrival.duplicate(true)
	checks.family_save=_roundtrip(c).get("ok",false)
	checks.progress_preserved=family and int(c.sim.clinic.visitors._role(c.world,c.visit_id,"ward_visit").get("remaining_ticks",-2))==left and flow_stay(c).companion_actor_id==companion and c.world.facts.rng.arrival==rng
	_tables(c,true)
	c.world.facts.staff.clin_surgeon.abilities.treatment=2
	flow_exact_draw(c.world,"treatment",9999)
	checks.first_started=await flow_until(t,c,func()->bool:return flow_visit(c).attempt_ids.size()==1,3000)
	if not checks.first_started: flow_check(t,"CLFLOW-27",checks,c);return
	var first: String=str(flow_visit(c).attempt_ids[0])
	checks.first_recovery=await flow_until(t,c,func()->bool:return flow_visit(c).get("result_receipt",{}).get("attempt_id","")==first,6000)
	checks.same_stay_after_failure=flow_stay(c).get("id","")==original_stay and flow_stay(c).get("bed_id","")==original_bed and flow_stay(c).get("companion_actor_id","")==companion
	checks.second_surgery_selected=_command(c,"clinical_select_plan",{"visit_id":c.visit_id,"plan_id":"P_D09_SURGERY"}).accepted
	flow_exact_draw(c.world,"treatment",0)
	checks.second_started=await flow_until(t,c,func()->bool:return flow_visit(c).attempt_ids.size()==2,3000)
	if checks.second_started:
		# The crossing-night input contains a genuinely started second Attempt.
		c=flow_clock_boundary(c,12000)
		var commitments: Dictionary=_commitments(c.world.facts.attempts)
		checks.cross_night_save=_roundtrip(c).get("ok",false)
		checks.frozen_after_save=_commitments(c.world.facts.attempts)==commitments and flow_stay(c).get("bed_id","")==original_bed and flow_stay(c).get("companion_actor_id","")==companion
		checks.real_second_return=await flow_until(t,c,func()->bool:return flow_stay(c).get("phase","")=="recovery",4800)
		checks.only_two=flow_visit(c).attempt_ids.size()==2 and flow_stay(c).get("id","")==original_stay
	flow_check(t,"CLFLOW-27",checks,c)

func _case_29(t) -> void:
	var prefix_started: int=Time.get_ticks_msec()
	# The input's beds are grade 1 before any employee or patient step. All
	# admission, surgery, care, transfer and recovery below execute normally.
	var c: Dictionary=await _surgery_queue(t,false,false,1,1)
	t.preparation_elapsed(prefix_started)
	var checks: Dictionary={"actual_graded_admission":flow_stay(c).has("admitted_tick") and flow_stay(c).get("phase","")=="waiting_surgery"}
	if not checks.actual_graded_admission: flow_check(t,"CLFLOW-29",checks,c);return
	var stay_id: String=str(flow_stay(c).id)
	var first_bed: String=str(flow_stay(c).bed_id)
	flow_exact_draw(c.world,"treatment",9999)
	checks.first_started=await flow_until(t,c,func()->bool:return not _session(c,"surgery").is_empty(),3000)
	if not checks.first_started: flow_check(t,"CLFLOW-29",checks,c);return
	var first: Dictionary=c.world.facts.attempts[flow_visit(c).attempt_ids[0]].duplicate(true)
	checks.first_failed=not first.result
	checks.first_care_started=await flow_until(t,c,func()->bool:return not _session(c,"care").is_empty(),5000)
	if not checks.first_care_started: flow_check(t,"CLFLOW-29",checks,c);return
	checks.twenty_real_care_ticks=await flow_until(t,c,func()->bool:
		var care: Dictionary=_session(c,"care")
		return not care.is_empty() and int(care.total_ticks)-int(care.remaining_ticks)>=20,160)
	var care: Dictionary=_session(c,"care").duplicate(true)
	checks.original_care_work=int(care.get("total_ticks",0))==80 and int(care.get("remaining_ticks",0))==60
	var other_bed: String=""
	for id: String in c.world.facility_ids("EQ05"):
		if id!=first_bed: other_bed=id;break
	var transfer: CommandResult=_command(c,"clinical_transfer_bed",{"visit_id":c.visit_id,"bed_id":other_bed})
	checks.real_transfer_accepted=transfer.accepted
	checks.current_care_checkpoint=transfer.accepted and flow_stay(c).id==stay_id and flow_stay(c).attempt_id==first.id and int(flow_stay(c).get("care_remaining_ticks",-1))==60 and _session(c,"care").is_empty()
	var transfer_save: Dictionary=_roundtrip(c)
	checks.transfer_saved=transfer_save.get("ok",false)
	if not transfer.accepted: flow_check(t,"CLFLOW-29",checks,c,{"transfer":transfer.to_record(),"transfer_save":transfer_save});return
	checks.real_transfer_and_resume=await flow_until(t,c,func()->bool:return flow_stay(c).get("phase","")=="recovery" and not _session(c,"care").is_empty(),2400)
	var resumed: Dictionary=_session(c,"care").duplicate(true)
	checks.same_attempt_care_continues=checks.real_transfer_and_resume and flow_stay(c).bed_id==other_bed and resumed.get("id","")!=care.get("id","") and int(resumed.get("total_ticks",0))==60 and flow_visit(c).attempt_ids==[first.id]
	checks.first_recovery_completed=await flow_until(t,c,func()->bool:return flow_visit(c).get("result_receipt",{}).get("attempt_id","")==first.id,5000)
	var first_completed: Dictionary=flow_stay(c).duplicate(true)
	checks.fractional_recovery_rate=int(first_completed.get("coverage_segment",{}).get("rate_milli",0))==1090
	checks.no_old_recovery_credit=checks.first_recovery_completed and int(first_completed.get("remaining_ticks",-1))==0 and int(first_completed.get("work_credit_milli",-1))==0
	checks.no_completed_care_checkpoint=not first_completed.has("care_remaining_ticks")
	var retry_save: Dictionary=_roundtrip(c)
	checks.retry_wait_saved=retry_save.get("ok",false)
	checks.first_bill_once=_income(c,"ward")==60 and _income(c,"cure")==0
	var selected: CommandResult=_command(c,"clinical_select_plan",{"visit_id":c.visit_id,"plan_id":"P_D09_SURGERY"})
	checks.second_plan_accepted=selected.accepted
	flow_exact_draw(c.world,"treatment",0)
	checks.second_started=selected.accepted and await flow_until(t,c,func()->bool:return flow_visit(c).attempt_ids.size()==2,3000)
	if not checks.second_started: flow_check(t,"CLFLOW-29",checks,c,{"first_completed":first_completed,"retry_save":retry_save,"selection":selected.to_record()});return
	var second: Dictionary=c.world.facts.attempts[flow_visit(c).attempt_ids[1]].duplicate(true)
	checks.new_attempt_same_stay=second.id!=first.id and second.result and flow_stay(c).id==stay_id and flow_stay(c).bed_id==other_bed and not flow_stay(c).care_completed and not flow_stay(c).has("care_remaining_ticks") and int(flow_stay(c).remaining_ticks)==1800
	checks.second_care_started=await flow_until(t,c,func()->bool:return not _session(c,"care").is_empty(),5000)
	var second_care: Dictionary=_session(c,"care").duplicate(true)
	# Care 1, a neutral nursing talent and eight standard seconds require
	# eighty real work ticks for each operation, regardless of the old pause.
	checks.full_second_care=int(second_care.get("total_ticks",0))==80
	var care_save: Dictionary=_roundtrip(c)
	checks.second_care_saved=care_save.get("ok",false) and _session(c,"care").get("remaining_ticks",-1)==second_care.get("remaining_ticks",-2)
	checks.second_completed=await flow_until(t,c,func()->bool:return flow_visit(c).get("result_receipt",{}).get("attempt_id","")==second.id,5000)
	checks.complete_unique_bill=checks.second_completed and flow_visit(c).attempt_ids.size()==2 and _income(c,"ward")==120 and _income(c,"cure")==int(second.cure_fee) and _units_used(c)==16
	flow_check(t,"CLFLOW-29",checks,c,{"first_care":care,"transfer":transfer.to_record(),"transfer_save":transfer_save,"resumed_care":resumed,"first_completed":first_completed,"retry_save":retry_save,"second_care":second_care,"second_care_save":care_save})
