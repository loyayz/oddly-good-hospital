extends "res://tests/acceptance/clinical_flow_fixtures.gd"

const CASES: Dictionary={
	"CLFLOW-01":"统一规格§14、17；能力1…5精确概率边界及能力0拒绝",
	"CLFLOW-02":"统一规格§14；暂停、换人、升级与保存保持初诊开工判断",
	"CLFLOW-03":"统一规格§14；合法模式等权一次检查，收费/实践唯一",
	"CLFLOW-04":"统一规格§14；同层及跨层真实回原门诊队尾，免费复核",
	"CLFLOW-05":"统一规格§14；医生下班不打断检查，完成后安全离院",
	"CLFLOW-06":"统一规格§14；D+1办理时在班判定，接续或D+2",
	"CLFLOW-07":"统一规格§14；D+2一次投诉终结，保留实收与检查",
	"CLFLOW-08":"统一规格§14；离职医生随机转交，无候选等待",
	"CLFLOW-09":"统一规格§14、18；院外、途中及定向导诊保存恢复",
	"CLFLOW-10":"统一规格§15.1；普通治疗直接或导诊，C舒缓无强制住院",
	"CLFLOW-11":"统一规格§15.1；首败自动重新选择，二次开工前可指定",
	"CLFLOW-12":"统一规格§15.1；两次实际失败安全转诊，准备失败不计次",
	"CLFLOW-13":"统一规格§15.2；先实际住院，缺术台/术组不弃候转诊",
	"CLFLOW-14":"统一规格§15.2；异层无导诊术室真实往返并保留原床",
	"CLFLOW-15":"统一规格§15.3；晚班不开新术，已开术安全返房",
	"CLFLOW-16":"统一规格§15.2；到齐才计准备期限，失败安全返原床",
	"CLFLOW-17":"统一规格§15.3；首术失败恢复护理后在同住院重试",
	"CLFLOW-18":"统一规格§15.3；术前不刷恢复，术后护理与恢复齐全才结算",
	"CLFLOW-19":"统一规格§16.1；新来客真实入院后按楼层等权选择导诊",
	"CLFLOW-20":"统一规格§16.1；无导诊合法等待，恢复后真实移动",
	"CLFLOW-21":"统一规格§16.2；四类缺项随机换层，可重返旧层不预搜",
	"CLFLOW-22":"统一规格§16.2；个体缺项让过，后续继续且不刷工时",
	"CLFLOW-23":"统一规格§16.3；在途冻结目的台，到达后才重选",
	"CLFLOW-24":"统一规格§16.2；普通设施须导诊，住院手术层例外",
	"CLFLOW-25":"统一规格§16.3；保临床票和有效等待，导诊号不跨台",
	"CLFLOW-26":"统一规格§15.3；床故障/护理缺员与缺术组分别处理",
	"CLFLOW-27":"统一规格§18；同住院两术与跨夜恢复保持床/身份/费用",
	"CLFLOW-28":"统一规格§14；投诉终结后只有合法新复诊Visit",
	"FOLLOWUP-01":"统一规格§3；患者复诊名称、20%、两日及独立新Visit"
}

func run(t, database: HospitalContent = null, selected: Array = []) -> void:
	flow_initialize(t,database if database!=null else HospitalContent.new())
	for id: String in CASES:
		if not t.wants(id) or not selected.is_empty() and not id in selected: continue
		if id=="FOLLOWUP-01" or int(id.right(2))>=13: continue
		t.begin_case(id)
		_fixture_failures.clear()
		if not _content.error.is_empty(): t.check(id,false,{"content_error":_content.error});continue
		await call("_case_"+id.right(2),t)
	await preload("res://tests/acceptance/clinical_flow_inpatient.gd").new().run(t,_content,selected)
	await preload("res://tests/acceptance/clinical_flow_guidance.gd").new().run(t,_content,selected)
	await preload("res://tests/acceptance/clinical_flow_followup.gd").new().run(t,_content,selected)
	_dispose_simulations()

func _case_01(t) -> void:
	var base: Dictionary=await flow_boundary(t,"before_gp")
	var checks: Dictionary={"legal_gp_boundary":not base.is_empty()}
	if base.is_empty(): flow_check(t,"CLFLOW-01",checks);return
	var snapshot: Dictionary=flow_freeze(base)
	var doctor: String=base.doctors[0]
	for level: int in range(1,6):
		var threshold: int=[4000,3200,2400,1600,800][level-1]
		for roll: int in [threshold-1,threshold]:
			var c: Dictionary=flow_restore(snapshot)
			c.world.facts.staff[doctor].abilities.diagnosis=level
			flow_exact_draw(c.world,"treatment",roll)
			var started: bool=await flow_until(t,c,func()->bool:return not _session(c,"gp").is_empty(),20)
			var session: Dictionary=_session(c,"gp")
			checks["level_%d_roll_%d"%[level,roll]]=started and int(session.get("insufficient_bp",-1))==threshold and bool(session.get("insufficient",false))==(roll<threshold) and flow_visit(c).diagnosis.state=="working" and not flow_visit(c).diagnosis.has("insufficient")
	var zero: Dictionary=flow_restore(snapshot)
	zero.world.facts.staff[doctor].abilities.diagnosis=0
	var rng: Dictionary=zero.world.facts.rng.treatment.duplicate(true)
	await flow_steps(t,zero,5)
	checks.zero_rejected=_session(zero,"gp").is_empty() and zero.world.facts.rng.treatment==rng
	checks.no_score_data=not _content.balance.has("diagnosis_threshold") and not _content.balance.tests.spectrum.has("confidence") and not _content.catalog.profiles.A.has("gp_confidence") and not flow_visit(base).has("evidence_by_source")
	flow_check(t,"CLFLOW-01",checks)

func _case_02(t) -> void:
	var c: Dictionary=await flow_boundary(t,"before_gp")
	var checks: Dictionary={"legal_gp_boundary":not c.is_empty()}
	if c.is_empty(): flow_check(t,"CLFLOW-02",checks);return
	var pending_world: Dictionary=c.world.freeze()
	var rejected: CommandResult=c.sim.clinic.execute(c.world,"clinical_select_plan",{"visit_id":c.visit_id,"plan_id":"P_D09_COMMON"})
	checks.no_plan_before_diagnosis=not rejected.accepted and rejected.code=="diagnosis_pending" and c.world.freeze()==pending_world
	flow_exact_draw(c.world,"treatment",0)
	_tick(c)
	var frozen: Dictionary=_session(c,"gp").duplicate(true)
	checks.started=not frozen.is_empty()
	if frozen.is_empty(): flow_check(t,"CLFLOW-02",checks,c);return
	var rng: Dictionary=c.world.facts.rng.treatment.duplicate(true)
	var before: Dictionary=c.world.freeze()
	var game:=GameSession.new(c.sim,"diagnosis-freeze")
	game.set_speed(1)
	game.pause("acceptance")
	for index: int in 4: game.advance(0.5)
	checks.paused_without_work=c.world.freeze()==before
	checks.hidden_before_completion=not flow_visit(c).diagnosis.has("insufficient")
	var panel:=HospitalPlansPanel.new()
	panel.simulation=c.sim
	panel.session=game
	panel.build_controls()
	panel._visit_id=c.visit_id
	panel._populate_plans()
	var pending_text: String=panel._details()
	checks.no_early_plan_controls=panel._plans.item_count==0 and panel._apply.disabled and panel._auto.disabled and pending_text=="完成初诊及必要的检查复核后，可以比较治疗方案。"
	checks.plan_view_readonly=c.world.freeze()==before
	panel.free()
	c.world.facts.facilities[frozen.facility_id].failed=true
	var remaining: int=int(_session(c,"gp").remaining_ticks)
	await flow_steps(t,c,13)
	checks.equipment_pause_preserves=_session(c,"gp").get("remaining_ticks",-1)==remaining and c.world.facts.rng.treatment==rng
	c.world.facts.facilities[frozen.facility_id].failed=false
	c.sim.clinic.suspend_outpatient(c.world,frozen.facility_id)
	var suspended: Dictionary=c.world.facts.clinical_suspensions.get(frozen.id,{})
	checks.suspension_preserves=suspended.get("insufficient")==frozen.insufficient and int(suspended.get("insufficient_bp",-1))==int(frozen.insufficient_bp) and int(suspended.get("remaining_ticks",-1))==remaining
	var changes: Array=[{"staff_id":frozen.staff_ids[0],"schedule":_schedule("rest")},{"staff_id":c.doctors[1],"schedule":_schedule("outpatient",[c.world.facts.facilities[frozen.facility_id].room_id])}]
	checks.safe_handoff_schedule=c.sim.services.scheduler.execute(c.world,"apply_schedule",{"changes":changes}).accepted
	c.world.facts.staff[c.doctors[1]].abilities.diagnosis=5
	c.world.facts.facilities[frozen.facility_id].grade=2
	checks.saved=_roundtrip(c).get("ok",false)
	checks.real_replacement_arrival=await flow_until(t,c,func()->bool:return not _session(c,"gp").is_empty() and _session(c,"gp").get("staff_ids",[])==[c.doctors[1]],1600)
	var completed: bool=await flow_until(t,c,func()->bool:return flow_visit(c).diagnosis.gp_completed,500)
	checks.frozen=completed and bool(flow_visit(c).diagnosis.insufficient) and int(flow_visit(c).diagnosis.insufficient_bp)==int(frozen.insufficient_bp) and c.world.facts.rng.treatment==rng
	checks.revealed_at_completion=completed and flow_visit(c).diagnosis.state=="insufficient" and flow_visit(c).phase=="wait_examination"
	checks.unique_initial_fee=_income(c,"consultation")==int(frozen.doctor_fee) and _income(c,"gp")==int(frozen.facility_fee)
	flow_check(t,"CLFLOW-02",checks,c,{"original_session":frozen})

func _case_03(t) -> void:
	var base: Dictionary=await flow_boundary(t,"exam_wait")
	var checks: Dictionary={"examination_boundary":not base.is_empty()}
	var failures: Dictionary={}
	if base.is_empty(): flow_check(t,"CLFLOW-03",checks);return
	checks.real_first_b_admission=base.has("first_b_input") and int(base.world.facts.research_progress.get("first_profile_b_tick",-1))==int(base.first_b_input.get("entry_tick",-2)) and base.first_b_input.get("before_open_targets",[]).is_empty() and not base.first_b_input.get("after_open_targets",[]).is_empty()
	for dual: bool in [false,true]:
		for choice: int in ([0,1] if dual else [0]):
			var c: Dictionary=flow_restore(flow_freeze(base))
			if dual:
				for research_id: String in ["R02","R11"]:
					if not research_id in c.world.facts.research: c.world.facts.research.append(research_id)
			else: c.world.facts.research.erase("R11")
			flow_exact_draw(c.world,"treatment",choice,2 if dual else 1)
			var units: int=_units_used(c)
			var started: bool=await flow_until(t,c,func()->bool:return not flow_exam_session(c).is_empty(),2400)
			var session: Dictionary=flow_exam_session(c).duplicate(true)
			var mode: String="resonance" if dual and choice==1 else "spectrum"
			var prefix: String="dual_%s_choice_%d"%[str(dual),choice]
			checks[prefix+"_legal_mode"]=started and session.get("kind","")==mode
			if not checks[prefix+"_legal_mode"]: failures[prefix]=flow_diagnostic(c)
			if not started: continue
			var rng: Dictionary=c.world.facts.rng.treatment.duplicate(true)
			var done: bool=await flow_until(t,c,func()->bool:return flow_visit(c).diagnosis.exam_completed,500)
			checks[prefix+"_once"]=done and int(c.started.get("spectrum",0))+int(c.started.get("resonance",0))==1 and flow_visit(c).diagnosis.exam_kind==mode and c.world.facts.rng.treatment==rng and _units_used(c)==units
			checks[prefix+"_practice_once"]=done and c.world.facts.staff[session.staff_ids[0]].completed_jobs.has(session.id)
			checks[prefix+"_one_fee"]=done and _income(c,mode)==int(session.get("facility_fee",0))
	flow_check(t,"CLFLOW-03",checks,{}, {"failures":failures,"first_b_input":base.get("first_b_input",{})})

func _case_04(t) -> void:
	var checks: Dictionary={}
	for cross: bool in [false,true]:
		var c: Dictionary=flow_two_floor_clinic() if cross else flow_context(false,true)
		flow_exact_draw(c.world,"treatment",0)
		var admitted: bool=_arrive(c)
		var began: bool=admitted and await flow_until(t,c,func()->bool:return not flow_exam_session(c).is_empty(),4000)
		var prefix: String="cross" if cross else "same"
		checks[prefix+"_actual_exam"]=began
		if not began: continue
		var original: Dictionary=flow_visit(c).diagnosis.duplicate(true)
		var exam: Dictionary=flow_exam_session(c).duplicate(true)
		checks[prefix+"_floors"]=not cross or int(c.world.facts.facilities[exam.facility_id].floor_id)!=int(c.world.facts.facilities[original.facility_id].floor_id)
		checks[prefix+"_exam_done"]=await flow_until(t,c,func()->bool:return flow_visit(c).diagnosis.exam_completed,500)
		var prior: Dictionary=flow_existing_gp_queue(c,str(original.facility_id))
		var original_room: String=str(c.world.facts.facilities[original.facility_id].room_id)
		c.sim.services.floor_guidance.prepare(c.world,flow_visit(c),c.world.facts.tickets[flow_visit(c).ticket_id])
		var order: Array=c.world.facts.floor_guidance.clinic_queues[original_room].visit_ids
		checks[prefix+"_fifo_tail"]=order.has(prior.id) and order.has(c.visit_id) and order.find(prior.id)<order.find(c.visit_id)
		# The previous patient chooses to leave; its body still exits through
		# production movement, without delaying this return's review indefinitely.
		checks[prefix+"_prior_safe_departure"]=c.sim.clinic.depart_visit(c.world,prior.id,"abandoned")
		var ledger: Dictionary=c.world.facts.ledger.entries.duplicate(true)
		var receipts: Array=flow_guide(c).get("receipts",[]).duplicate(true)
		var units: int=_units_used(c)
		var reviewed: bool=await flow_until(t,c,func()->bool:return not _session(c,"consult").is_empty(),2800)
		var review: Dictionary=_session(c,"consult").duplicate(true)
		checks[prefix+"_original_doctor"]=reviewed and review.get("facility_id","")==original.facility_id and review.get("staff_ids",[])==[original.doctor_id] and flow_in_room(c,flow_visit(c).actor_id,original_room)
		checks[prefix+"_free_review"]=reviewed and c.world.facts.ledger.entries==ledger and _units_used(c)==units and int(review.get("total_ticks",0))>=40
		checks[prefix+"_no_guidance"]=flow_guide(c).get("receipts",[])==receipts
		checks[prefix+"_completed"]=reviewed and await flow_until(t,c,func()->bool:return flow_visit(c).diagnosis.get("review_completed",false),180)
	flow_check(t,"CLFLOW-04",checks)

func _case_05(t) -> void:
	var c: Dictionary=await flow_boundary(t,"exam_started")
	var checks: Dictionary={"exam_boundary":not c.is_empty()}
	if c.is_empty(): flow_check(t,"CLFLOW-05",checks);return
	var exam: Dictionary=flow_exam_session(c).duplicate(true)
	# A legal already-started input whose remaining real work finishes just
	# before midnight. Its actual exit journey then crosses into the next day.
	c=flow_clock_boundary(c,17980-int(exam.remaining_ticks))
	checks.offshift_scheduled=flow_schedule(c,str(flow_visit(c).diagnosis.doctor_id),"rest")
	await flow_steps(t,c,10)
	checks.not_interrupted=not flow_exam_session(c).is_empty() and flow_exam_session(c).id==exam.id and int(flow_exam_session(c).remaining_ticks)==int(exam.remaining_ticks)-10 and not flow_visit(c).has("continuation")
	checks.completed_first=await flow_until(t,c,func()->bool:return flow_visit(c).diagnosis.exam_completed,500)
	checks.exit_requested_before_midnight=c.world.sim_tick<18000 and flow_visit(c).get("continuation",{}).get("stage","")=="leaving"
	var history: Dictionary=flow_visit(c).diagnosis.duplicate(true)
	var ledger: Dictionary=c.world.facts.ledger.entries.duplicate(true)
	checks.safe_actual_exit=await flow_until(t,c,func()->bool:return flow_visit(c).phase=="continuation_outside",2800)
	var plan: Dictionary=flow_visit(c).get("continuation",{})
	checks.first_day_is_actual_exit_day=int(plan.get("first_day",-1))==1 and int(plan.get("first_day",-1))==(c.world.sim_tick-1)/18000
	checks.next_day_preselected=plan.get("return_day",-1)==int(plan.get("first_day",-10))+1 and int(plan.get("due_tick",-1))>=int(plan.get("return_day",0))*18000 and int(plan.get("due_tick",-1))<(int(plan.get("return_day",0))+1)*18000
	checks.history_and_fees=flow_visit(c).diagnosis==history and c.world.facts.ledger.entries==ledger and flow_visit(c).attempt_ids.is_empty()
	flow_check(t,"CLFLOW-05",checks,c)

func _case_06(t) -> void:
	var base: Dictionary=await flow_boundary(t,"continuation_outside")
	var checks: Dictionary={"actual_first_exit_boundary":not base.is_empty()}
	var failures: Dictionary={}
	var preparation: Dictionary={}
	if base.is_empty(): flow_check(t,"CLFLOW-06",checks);return
	for at_turn: bool in [true,false]:
		# The saved due remains the original draw. Prepare only the untested
		# outside input clock, leaving three real minutes for schedule handoff.
		var input: Dictionary=flow_freeze(base)
		var due_tick: int=int(input.facts.visits[input.visit_id].continuation.due_tick)
		input.facts.sim_tick=maxi(int(base.world.sim_tick),due_tick-1800)
		var c: Dictionary=flow_restore(input)
		var doctor: String=str(flow_visit(c).diagnosis.doctor_id)
		var room: String=str(c.world.facts.facilities[flow_visit(c).diagnosis.facility_id].room_id)
		var before: Dictionary=flow_return_probe(c)
		var desired_kind: String="rest" if at_turn else "outpatient"
		var prepared: Dictionary={"start_tick":c.world.sim_tick,"due_tick":due_tick,"desired_kind":desired_kind,"desired_on_shift":not at_turn,"before_staff":c.world.facts.staff[doctor].duplicate(true)}
		checks["arrival_schedule_accepted_"+str(at_turn)]=flow_schedule(c,doctor,desired_kind,"" if at_turn else room)
		_tick(c)
		var ready: bool=await flow_until(t,c,func()->bool:return c.world.facts.actors[flow_visit(c).actor_id].location.kind=="outside" and bool(c.world.facts.staff[doctor].get("on_shift",false))!=at_turn and c.world.facts.staff[doctor].get("scheduled_kind","")==desired_kind,maxi(0,due_tick-c.world.sim_tick-1))
		checks["arrival_schedule_effective_outside_"+str(at_turn)]=ready and c.world.sim_tick<due_tick and c.world.facts.actors[flow_visit(c).actor_id].location.kind=="outside"
		prepared.effective_tick=c.world.sim_tick
		prepared.effective_staff=c.world.facts.staff[doctor].duplicate(true)
		prepared.patient_before_entry=c.world.facts.actors[flow_visit(c).actor_id].duplicate(true)
		preparation[str(at_turn)]=prepared
		if not checks["arrival_schedule_effective_outside_"+str(at_turn)]:
			failures["work_at_turn_"+str(at_turn)]=flow_guidance_handoff(c)
			continue
		var real_entry: bool=await flow_until(t,c,func()->bool:return c.world.facts.actors[flow_visit(c).actor_id].location.kind=="floor",maxi(0,due_tick-c.world.sim_tick)+40)
		checks["real_entry_"+str(at_turn)]=real_entry
		if real_entry:
			var conserved: Dictionary=flow_return_checks(c,before)
			for key: String in conserved: checks[key+"_"+str(at_turn)]=conserved[key]
		# The actual entry is already before counter service. A due life need
		# may legitimately take the next 120-second search window first; it
		# does not change the doctor's arrival status or this switch boundary.
		var actor: Dictionary=c.world.facts.actors[flow_visit(c).actor_id]
		var returned_tick: int=int(flow_visit(c).continuation.outside_periods.back().returned_tick)
		var entered: bool=real_entry and actor.location.kind=="floor" and int(actor.location.floor_id)==int(c.world.facts.entry.floor_id) and returned_tick==c.world.sim_tick-1 and returned_tick>=due_tick
		checks["entered_"+str(at_turn)]=entered and flow_visit(c).continuation.return_day==1 and flow_visit(c).continuation.stage=="guidance"
		var entry_move: Dictionary=c.world.facts.moves.get(str(actor.id),{})
		var travelled: Array=entry_move.get("travelled",[])
		checks["entry_origin_"+str(at_turn)]=travelled.is_empty() or travelled[0].get("kind","")=="floor" and int(travelled[0].get("floor_id",-1))==int(c.world.facts.entry.floor_id) and travelled[0].get("cell",[])==c.world.facts.entry.cell
		prepared.returned_tick=returned_tick
		prepared.entry_actor=actor.duplicate(true)
		prepared.entry_move=entry_move.duplicate(true)
		prepared.entry_staff=c.world.facts.staff[doctor].duplicate(true)
		var at_counter: bool=false
		for desk_id: String in c.world.facility_ids("SE01"):
			var post: Dictionary=c.sim.space.guidance_patient_post(c.world,desk_id,str(flow_visit(c).actor_id))
			if not post.is_empty() and c.sim.space.at(c.world,str(flow_visit(c).actor_id),int(c.world.facts.facilities[desk_id].floor_id),post.cell): at_counter=true
		checks["before_counter_service_"+str(at_turn)]=not at_counter and flow_guide(c).get("phase","")!="working" and _session(c,"consult").is_empty() and flow_visit(c).attempt_ids.is_empty()
		checks["arrival_status_"+str(at_turn)]=bool(c.world.facts.staff[doctor].get("on_shift",false))!=at_turn
		if not entered or not checks["before_counter_service_"+str(at_turn)] or not checks["arrival_status_"+str(at_turn)]:
			failures["work_at_turn_"+str(at_turn)]=flow_guidance_handoff(c)
			continue
		checks["changed_before_turn_"+str(at_turn)]=flow_schedule(c,doctor,"outpatient" if at_turn else "rest",room if at_turn else "")
		var decided: bool=await flow_until(t,c,func()->bool:return not _session(c,"consult").is_empty() if at_turn else flow_visit(c).phase=="continuation_outside",3000)
		checks["service_time_decision_"+str(at_turn)]=decided and (flow_visit(c).continuation.stage=="continuing" if at_turn else int(flow_visit(c).continuation.return_day)==2 and int(flow_visit(c).continuation.first_day)==0)
		if not checks["service_time_decision_"+str(at_turn)]: failures["work_at_turn_"+str(at_turn)]=flow_guidance_handoff(c)
	flow_check(t,"CLFLOW-06",checks,{}, {"failures":failures,"schedule_preparation":preparation})

func _case_07(t) -> void:
	var base: Dictionary=await flow_boundary(t,"continuation_second_outside")
	var checks: Dictionary={"actual_second_exit_boundary":not base.is_empty()}
	if base.is_empty(): flow_check(t,"CLFLOW-07",checks);return
	var c: Dictionary=flow_outside_return_input(base,2)
	checks.offshift=flow_schedule(c,str(flow_visit(c).diagnosis.doctor_id),"rest")
	var ledger: Dictionary=c.world.facts.ledger.entries.duplicate(true)
	var history: Dictionary=flow_visit(c).diagnosis.duplicate(true)
	c.clinical_scenario=false
	var before: Dictionary=flow_return_probe(c)
	checks.real_entry=await flow_until(t,c,func()->bool:return c.world.facts.actors[flow_visit(c).actor_id].location.kind=="floor",40)
	if checks.real_entry: checks.merge(flow_return_checks(c,before))
	checks.terminated=await flow_finish_visit(t,c,3600)
	var experience: Dictionary=c.world.facts.patient_experience.experience.get(c.visit_id,{})
	checks.one_complaint=flow_visit(c).has("continuation_complaint") and experience.get("unhandled",{}).size()==1
	checks.no_d3=flow_visit(c).get("continuation",{}).get("stage","")=="finished" and int(flow_visit(c).continuation.return_day)==2
	checks.history_and_fees=flow_visit(c).diagnosis==history and c.world.facts.ledger.entries==ledger and flow_visit(c).attempt_ids.is_empty()
	var complaints: Dictionary=experience.get("unhandled",{}).duplicate(true)
	await flow_steps(t,c,10)
	checks.idempotent=c.world.facts.patient_experience.experience.get(c.visit_id,{}).get("unhandled",{})==complaints
	flow_check(t,"CLFLOW-07",checks,c,{"unhandled":experience.get("unhandled",{}).duplicate(true),"complaint":flow_visit(c).get("continuation_complaint",{}).duplicate(true)})

func _case_08(t) -> void:
	var base: Dictionary=await flow_boundary(t,"review_wait")
	var checks: Dictionary={"review_boundary":not base.is_empty()}
	if base.is_empty(): flow_check(t,"CLFLOW-08",checks);return
	var departures: Array=[]
	for empty: bool in [false,true]:
		var c: Dictionary=flow_restore(flow_freeze(base))
		var old: String=str(flow_visit(c).diagnosis.doctor_id)
		var history: Dictionary=flow_visit(c).diagnosis.duplicate(true)
		var clinical_receipts: Dictionary={}
		for key: String in c.world.facts.ledger.entries:
			if c.world.facts.ledger.entries[key].owner_id==c.visit_id: clinical_receipts[key]=c.world.facts.ledger.entries[key].duplicate(true)
		var paid: CommandResult=c.sim.services.finance.settle_departure(c.world,old)
		checks["original_departure_settled_"+str(empty)]=paid.accepted
		departures.append({"staff_id":old,"no_candidates":empty,"settlement":paid.to_record()})
		c.world.facts.staff[old].schedule=_schedule("rest")
		c.world.facts.staff[old].erase("clinical_release")
		c.world.facts.moves.erase(old)
		c.world.facts.actors[old].location={"kind":"outside"}
		c.sim.space.sync_actor(c.world,old)
		if empty:
			for staff: Dictionary in c.world.facts.staff.values():
				if staff.role=="doctor" and staff.id!=old:
					var result: CommandResult=c.sim.services.finance.settle_departure(c.world,staff.id)
					checks["departure_settled_"+staff.id]=result.accepted
					departures.append({"staff_id":staff.id,"no_candidates":true,"settlement":result.to_record()})
					staff.erase("clinical_release")
					c.world.facts.moves.erase(staff.id)
					c.world.facts.actors[staff.id].location={"kind":"outside"}
					c.sim.space.sync_actor(c.world,staff.id)
		else: checks.replacement_schedule=flow_schedule(c,c.doctors[1],"outpatient",str(c.world.facts.facilities[history.facility_id].room_id))
		checks["departure_finance_valid_"+str(empty)]=c.sim.services.finance.validate(c.world).is_empty()
		for key: String in clinical_receipts:
			checks["clinical_receipt_"+str(empty)+"_"+key]=c.world.facts.ledger.entries.get(key,{})==clinical_receipts[key]
		# The tested operation begins after lawful employment settlement. Its
		# handoff must not alter either clinical receipts or the complete ledger.
		var ledger: Dictionary=c.world.facts.ledger.entries.duplicate(true)
		var selected: bool=Flow.resolve_doctor(c.sim.clinic,c.world,flow_visit(c))
		if empty: checks.no_fabricated_doctor=not selected and flow_visit(c).diagnosis.doctor_id==old and str(flow_visit(c).waiting_reason).contains("等待")
		else:
			var chosen: String=str(flow_visit(c).diagnosis.doctor_id)
			var rng: Dictionary=c.world.facts.rng.treatment.duplicate(true)
			checks.transferred=selected and chosen!=old and not c.world.facts.staff[chosen].get("departed",false)
			for index: int in 5: Flow.resolve_doctor(c.sim.clinic,c.world,flow_visit(c))
			checks.once=c.world.facts.rng.treatment==rng and flow_visit(c).diagnosis.doctor_id==chosen
		checks["preserved_"+str(empty)]=flow_visit(c).diagnosis.exam_completed==history.exam_completed and flow_visit(c).diagnosis.exam_kind==history.exam_kind and c.world.facts.ledger.entries==ledger and flow_visit(c).attempt_ids.is_empty()
		checks["handoff_world_valid_"+str(empty)]=c.world.validate(_content).is_empty()
	flow_check(t,"CLFLOW-08",checks,{}, {"employment_departures":departures})

func _case_09(t) -> void:
	var c: Dictionary=await flow_boundary(t,"review_wait")
	var checks: Dictionary={"review_boundary":not c.is_empty()}
	if c.is_empty(): flow_check(t,"CLFLOW-09",checks);return
	checks.offshift=flow_schedule(c,str(flow_visit(c).diagnosis.doctor_id),"rest")
	checks.actual_exit=await flow_until(t,c,func()->bool:return flow_visit(c).phase=="continuation_outside",2800)
	if not checks.actual_exit: flow_check(t,"CLFLOW-09",checks,c);return
	var plan: Dictionary=flow_visit(c).get("continuation",{}).duplicate(true)
	var rng: Dictionary=c.world.facts.rng.arrival.duplicate(true)
	var ledger: Dictionary=c.world.facts.ledger.entries.duplicate(true)
	checks.outside_saved=_roundtrip(c).get("ok",false)
	var retained: Dictionary=c.world.facts.tickets.get(str(flow_visit(c).ticket_id),{})
	checks.no_ghost=c.world.facts.actors[flow_visit(c).actor_id].location.kind=="outside" and not c.world.facts.moves.has(flow_visit(c).actor_id) and flow_guide(c).is_empty() and not c.world.facts.waiting_life.seats.has(c.visit_id) and not c.world.facts.preparations.has(c.visit_id) and not retained.get("service_assigned",false)
	checks.no_active_session=c.world.facts.sessions.values().all(func(session: Dictionary)->bool:return session.visit_id!=c.visit_id)
	# Explicit pre-entry boundary, without claiming the overnight interval as
	# measured work. The exit above and subsequent real entry are both executed.
	var due: Dictionary=flow_freeze(c)
	due.facts.sim_tick=int(plan.get("due_tick",0))-1
	c=flow_restore(due)
	var before: Dictionary=flow_return_probe(c)
	checks.reentry=await flow_until(t,c,func()->bool:return c.world.facts.actors[flow_visit(c).actor_id].location.kind=="floor",5)
	if checks.reentry: checks.merge(flow_return_checks(c,before))
	checks.entry_saved=_roundtrip(c).get("ok",false)
	# Temporarily unstaffed guidance is a stable legal waiting boundary. An
	# empty staffed queue can decide the original doctor's absence in the same
	# dispatch that admits its head, leaving no queue-wait snapshot to save.
	var schedules: Array=[]
	for staff: Dictionary in c.world.facts.staff.values():
		if staff.role!="nurse": continue
		schedules.append({"staff_id":staff.id,"schedule":staff.schedule.duplicate(true)})
		checks["nurse_pause_"+str(staff.id)]=flow_schedule(c,str(staff.id),"rest")
	checks.guidance_waiting=await flow_until(t,c,func()->bool:return flow_visit(c).continuation.stage=="guidance" and not c.world.facts.moves.has(flow_visit(c).actor_id) and str(flow_visit(c).waiting_reason).contains("导诊"),1800)
	checks.guidance_wait_saved=_roundtrip(c).get("ok",false)
	checks.plan_rng_fees=flow_visit(c).continuation.due_tick==plan.get("due_tick",-1) and flow_visit(c).continuation.first_day==plan.get("first_day",-1) and c.world.facts.rng.arrival==rng and c.world.facts.ledger.entries==ledger
	checks.original_floor=int(flow_guide(c).get("guide_floor",-1))==int(c.world.facts.facilities[flow_visit(c).diagnosis.facility_id].floor_id)
	var saved_guidance: Dictionary=flow_guide(c).duplicate(true)
	checks.nurses_restored=c.sim.services.scheduler.execute(c.world,"apply_schedule",{"changes":schedules}).accepted
	var journey: Dictionary={"observed":false,"saved":false}
	# Observe the real guidance journey throughout the original processing
	# window, after life service and nurse recovery have actually completed.
	checks.restored_real_processing=await flow_watch(t,c,func()->bool:return flow_visit(c).phase=="continuation_outside" and int(flow_visit(c).continuation.return_day)==int(plan.first_day)+2,func()->void:
		if journey.observed: return
		var actor: Dictionary=c.world.facts.actors[flow_visit(c).actor_id]
		var move: Dictionary=c.world.facts.moves.get(str(actor.id),{})
		var guide: Dictionary=flow_guide(c)
		if actor.location.kind!="floor" or not guide.has("queue_trip") or move.get("floor_guidance_key","")!=guide.get("request_key","missing") or c.world.facts.waiting_life.needs.has(c.visit_id): return
		var travelled: Array=move.get("travelled",[])
		if travelled.is_empty() or travelled[0].get("cell",[])==actor.location.cell: return
		journey.observed=true
		journey.state={"tick":c.world.sim_tick,"guide":guide.duplicate(true),"actor":actor.duplicate(true),"move":move.duplicate(true)}
		journey.saved=_roundtrip(c).get("ok",false),3000)
	checks.actual_guidance_journey=journey.observed
	checks.journey_saved=journey.saved
	checks.no_duplicate_initial_fees=c.world.facts.ledger.entries==ledger and flow_visit(c).attempt_ids.is_empty()
	flow_check(t,"CLFLOW-09",checks,c,{"selected_return_plan":plan,"saved_guidance":saved_guidance,"journey":journey,"handoff":flow_guidance_handoff(c)})

func _case_10(t) -> void:
	var checks: Dictionary={}
	var failures: Dictionary={}
	var selections: Dictionary={}
	for gentle: bool in [false,true]:
		var c: Dictionary=flow_context(false,gentle)
		if gentle:
			# C gentle treatment needs level 3 under the unchanged rule. This
			# qualified worker and its prerequisite research are initial input.
			c.world.facts.staff[c.doctors[1]].abilities.treatment=3
			c.world.facts.research=["R02","R11","R07"]
			c.world.touch(false)
			checks.gentle_has_no_ward_research=not "R33" in c.world.facts.research
		flow_exact_draw(c.world,"treatment",9999)
		var admitted: bool=_arrive(c,"B_S22_D14_M14" if gentle else "B_S13_D09_M09","P_D14_COMMON" if gentle else "P_D09_COMMON")
		var diagnosed: bool=admitted and await flow_until(t,c,func()->bool:return flow_visit(c).diagnosis.get("state","")=="diagnosed",2400)
		if gentle and diagnosed:
			var selection: CommandResult=_command(c,"clinical_select_plan",{"visit_id":c.visit_id,"plan_id":"P_D14_GENTLE"})
			selections.gentle=selection.to_record()
			checks.gentle_selected=selection.accepted
		flow_exact_draw(c.world,"treatment",0)
		var done: bool=diagnosed and await flow_finish_visit(t,c,3600)
		checks["gentle" if gentle else "common"]=done and flow_visit(c).final_result=="cured" and c.world.facts.ward_stays.is_empty() and _income(c,"ward")==0 and int(c.started.get("consult",0))==0 and flow_visit(c).attempt_ids.size()==1
		checks["one_initial_fee_"+str(gentle)]=_income(c,"consultation")==20 and _income(c,"gp")==5
		var actual_plan: String=""
		if flow_visit(c).attempt_ids.size()==1: actual_plan=str(c.world.facts.attempts[flow_visit(c).attempt_ids[0]].plan_id)
		checks["actual_plan_"+str(gentle)]=actual_plan==("P_D14_GENTLE" if gentle else "P_D09_COMMON")
		selections["performed_gentle" if gentle else "performed_common"]={"plan_id":actual_plan,"income":_income(c),"ward_income":_income(c,"ward"),"supply_units":_units_used(c),"final_phase":flow_visit(c).phase}
		if not checks["gentle" if gentle else "common"] or not checks["one_initial_fee_"+str(gentle)] or gentle and not checks.get("gentle_selected",false): failures["gentle" if gentle else "common"]=flow_diagnostic(c)
	var direct: Dictionary=flow_context()
	direct.world.facts.ledger.opening_balance=1000000
	var room: CommandResult=_command(direct,"build_room",{"id":"flow_direct_gp","room_type_id":"gp","floor_id":1,"origin":[33,65],"size":[14,10],"door":{"definition_id":"DR04","edge":"south","offset":3}})
	var table: CommandResult=_command(direct,"build_facility",{"id":"flow_direct_table","definition_id":"FUR02","floor_id":1,"cell":[35,67],"room_id":"flow_direct_gp"})
	var machine: CommandResult=_command(direct,"build_facility",{"id":"flow_direct_machine","definition_id":"M09","floor_id":1,"cell":[40,67],"room_id":"flow_direct_gp"})
	var doctor: String=direct.doctors[0]
	checks.direct_room_input=room.accepted and table.accepted and machine.accepted and flow_schedule(direct,doctor,"outpatient","flow_direct_gp")
	flow_exact_draw(direct.world,"treatment",9999)
	var entered: bool=_arrive(direct)
	var diagnosed: bool=entered and await flow_until(t,direct,func()->bool:return flow_visit(direct).diagnosis.get("gp_completed",false),2800)
	var receipts: Array=flow_guide(direct).get("receipts",[]).duplicate(true)
	flow_exact_draw(direct.world,"treatment",0)
	var treated: bool=diagnosed and await flow_until(t,direct,func()->bool:return not _session(direct,"outpatient").is_empty(),1800)
	checks.suitable_gp_direct=treated and _session(direct,"outpatient").get("staff_ids",[])==[doctor] and _session(direct,"outpatient").get("facility_id","")=="flow_direct_machine" and flow_guide(direct).get("receipts",[])==receipts
	if not checks.suitable_gp_direct: failures.direct=flow_diagnostic(direct)
	flow_check(t,"CLFLOW-10",checks,{}, {"failures":failures,"plan_selections":selections})

func _case_11(t) -> void:
	var c: Dictionary=await flow_boundary(t,"diagnosed")
	var checks: Dictionary={"diagnosed_boundary":not c.is_empty()}
	if c.is_empty(): flow_check(t,"CLFLOW-11",checks);return
	checks.first_manual=_command(c,"clinical_select_plan",{"visit_id":c.visit_id,"plan_id":"P_D09_GENTLE"}).accepted
	flow_exact_draw(c.world,"treatment",9999)
	checks.first_started=await flow_until(t,c,func()->bool:return not _session(c,"outpatient").is_empty(),2200)
	checks.first_finished=await flow_until(t,c,func()->bool:return flow_visit(c).attempt_ids.size()==1 and _session(c,"outpatient").is_empty() and str(flow_visit(c).phase).begins_with("wait_"),1500)
	checks.auto_reselected=flow_visit(c).plan_decision.get("source","")=="doctor"
	checks.second_manual=_command(c,"clinical_select_plan",{"visit_id":c.visit_id,"plan_id":"P_D09_COMMON"}).accepted
	var history: Dictionary=flow_visit(c).diagnosis.duplicate(true)
	var initial: int=_income(c,"consultation")+_income(c,"gp")
	flow_exact_draw(c.world,"treatment",0)
	checks.second_started=await flow_until(t,c,func()->bool:return flow_visit(c).attempt_ids.size()==2,2400)
	if flow_visit(c).attempt_ids.size()==2: checks.player_override=not c.world.facts.attempts[flow_visit(c).attempt_ids[0]].result and c.world.facts.attempts[flow_visit(c).attempt_ids[1]].plan_id=="P_D09_COMMON"
	checks.no_diagnostic_repeat=flow_visit(c).diagnosis==history and _income(c,"consultation")+_income(c,"gp")==initial and int(c.started.get("gp",0))==1 and int(c.started.get("consult",0))==0
	flow_check(t,"CLFLOW-11",checks,c)

func _case_12(t) -> void:
	var c: Dictionary=await flow_boundary(t,"diagnosed")
	var checks: Dictionary={"diagnosed_boundary":not c.is_empty()}
	if c.is_empty(): flow_check(t,"CLFLOW-12",checks);return
	var units: int=_units_used(c)
	c.world.facts.inventory.units=0
	var rng: Dictionary=c.world.facts.rng.treatment.duplicate(true)
	await flow_steps(t,c,80)
	checks.prestart_atomic=flow_visit(c).attempt_ids.is_empty() and _units_used(c)==units and c.world.facts.rng.treatment==rng
	c.world.facts.inventory.units=20
	flow_exact_draw(c.world,"treatment",9999)
	checks.first_started=await flow_until(t,c,func()->bool:return flow_visit(c).attempt_ids.size()==1,2400)
	checks.first_failure_finished=await flow_until(t,c,func()->bool:return flow_visit(c).attempt_ids.size()==1 and _session(c,"outpatient").is_empty() and str(flow_visit(c).phase).begins_with("wait_"),1600)
	flow_exact_draw(c.world,"treatment",9999)
	checks.second_departed=await flow_finish_visit(t,c,3600)
	var failed: bool=flow_visit(c).attempt_ids.size()==2
	for id: String in flow_visit(c).attempt_ids: failed=failed and not c.world.facts.attempts[id].result
	checks.two_actual_attempts=failed and flow_visit(c).final_result=="referred"
	var attempts: Dictionary=c.world.facts.attempts.duplicate(true)
	var issues: Dictionary=c.world.facts.inventory.issues.duplicate(true)
	await flow_steps(t,c,20)
	checks.no_third=c.world.facts.attempts==attempts and c.world.facts.inventory.issues==issues
	flow_check(t,"CLFLOW-12",checks,c)
