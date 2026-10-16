extends "res://tests/acceptance/clinical_fixtures.gd"

const ClinicalTiming = preload("res://tests/acceptance/clinical_timing.gd")

const CASES: Dictionary = {
	"CLIN-01":"docs/design/12-implementation-plan.md §10.1–10.2；真实接待6秒，Actor/Visit/原票只建一次",
	"CLIN-02":"docs/design/07-clinical-team.md §9、§14、§17；诊断池与治疗池由不同实际医生安全交接，D09首试成功实收235",
	"CLIN-03":"docs/design/01-simulation.md §4；C档证据42→77→102，检查各一次且不领包",
	"CLIN-04":"docs/design/07-clinical-team.md §14；诊断3/奇想台49.2→93，省略共振全部副作用",
	"CLIN-05":"docs/design/07-clinical-team.md §14；初诊按开工职称冻结，重复完成不重收25",
	"CLIN-06":"docs/design/01-simulation.md §4；临床§6、§16；报价只读，常规/舒缓从同一未取整工时分别最终ceil一次",
	"CLIN-07":"docs/design/07-clinical-team.md §5–6；C档能力/住院研究/覆盖不足不能开工",
	"CLIN-08":"docs/design/04-technical.md §6、§10；缺包不消费，补货按原票开工且不另扣采购现金",
	"CLIN-09":"docs/design/07-clinical-team.md §15；首败自动接第二次，重试+15个百分点夹98%，初诊不重收",
	"CLIN-10":"docs/design/07-clinical-team.md §14–15、§17；D09两次失败实收45、领2包、无第三次",
	"CLIN-11":"docs/design/07-clinical-team.md §6、§15；院长指定舒缓在短缺及首败后保留意图",
	"CLIN-12":"docs/design/01-simulation.md §1、§4；暂停与流式恢复保留Attempt、余量、随机流、费用和领包",
	"CLIN-13":"docs/design/07-clinical-team.md §14；D09舒缓治愈费220、D14手术1080，快照不随后改重算",
	"CLIN-14":"docs/design/07-clinical-team.md §5、§8；三位互异术组及另一位病区覆盖护士缺一不可",
	"CLIN-15":"docs/design/07-clinical-team.md §8；准备原子预留8包/床/团队，开术前不领包、不计尝试",
	"CLIN-16":"docs/design/07-clinical-team.md §8；取消/30秒到齐过期释放未承诺资源，保留原票",
	"CLIN-17":"docs/design/04-technical.md §10；两术室争一床，原票序只允许一个完整资源束",
	"CLIN-18":"docs/design/07-clinical-team.md §5、§8；开术冻结结果/120秒/180秒及四段15/45/25/15，恢复不重领",
	"CLIN-19":"docs/design/07-clinical-team.md §8、§14；术毕仍须15秒苏醒，完成才收60且不提前治愈",
	"CLIN-20":"docs/design/07-clinical-team.md §8；手术护士真实陪同转床，同Attempt交接床承诺",
	"CLIN-21":"docs/design/07-clinical-team.md §8；术中待故障安全完成，原结果/工时/领包不变",
	"CLIN-22":"docs/design/07-clinical-team.md §8.1；实际病房覆盖才推进，缺员/故障/暂停为0",
	"CLIN-23":"docs/design/07-clinical-team.md §8.1；同床双护士不加倍，每人不同时做两项主动护理",
	"CLIN-24":"docs/design/07-clinical-team.md §8.1、§14；8秒护理和10秒合格查房全部完成才收床费/治愈费",
	"CLIN-25":"docs/design/07-clinical-team.md §8.1、§10；安全换床保留标准余量/护理，回原床不重复磨损/收费",
	"CLIN-26":"docs/design/07-clinical-team.md §8；床故障无备用120秒安全转诊，只保留已完成术台60",
	"CLIN-27":"docs/design/07-clinical-team.md §8.1；缺员120秒提示/300秒转诊，改派走路不重置无进展",
	"CLIN-28":"docs/design/07-clinical-team.md §10、§14；住院各边界流式恢复保留护理/查房/最终唯一结算",
	"CLIN-29":"docs/design/07-clinical-team.md §5、§8、§14；C舒缓真实180秒恢复和查房后收60+660，领4包",
	"CLIN-30":"docs/design/07-clinical-team.md §8.2；无等候点仅有请求，条件齐备后独立亲友从入口真实到院",
	"CLIN-31":"docs/design/07-clinical-team.md §8.2；每窗口意向一次，换床/恢复不重抽，实际床边才起30秒",
	"CLIN-32":"docs/design/07-clinical-team.md §8.2；拒绝/医疗让位/出院安全退出，原停留不重启且空间不早释放"
}

const PREREQUISITES: Dictionary = {
	"CLIN-05": [
		"gp_started"
	],
	"CLIN-06": [
		"outpatient_queue"
	],
	"CLIN-07": [
		"c_diagnosed"
	],
	"CLIN-08": [
		"outpatient_queue"
	],
	"CLIN-09": [
		"outpatient_queue"
	],
	"CLIN-10": [
		"outpatient_queue"
	],
	"CLIN-11": [
		"outpatient_queue"
	],
	"CLIN-12": [
		"outpatient_started"
	],
	"CLIN-13": [
		"outpatient_queue",
		"c_surgery_queue"
	],
	"CLIN-14": [
		"surgery_queue"
	],
	"CLIN-15": [
		"surgery_queue"
	],
	"CLIN-16": [
		"surgery_prepared"
	],
	"CLIN-17": [
		"surgery_queue"
	],
	"CLIN-18": [
		"surgery_queue"
	],
	"CLIN-19": [
		"surgery_wake"
	],
	"CLIN-20": [
		"surgery_transfer"
	],
	"CLIN-21": [
		"surgery_started"
	],
	"CLIN-22": [
		"ward_after_care"
	],
	"CLIN-23": [
		"ward_after_care"
	],
	"CLIN-24": [
		"ward_care"
	],
	"CLIN-25": [
		"ward_after_care"
	],
	"CLIN-26": [
		"ward_after_care"
	],
	"CLIN-27": [
		"ward_after_care"
	],
	"CLIN-28": [
		"ward_entered",
		"ward_care",
		"ward_round_wait",
		"ward_round",
		"ward_settled"
	],
	"CLIN-29": [
		"c_diagnosed"
	],
	"CLIN-31": [
		"ward_entered"
	],
	"CLIN-32": [
		"visitor_visiting",
		"ward_entered",
		"companion_entered"
	]
}

func run(t) -> void:
	_content = HospitalContent.new()
	_cache = t.checkpoints(_content,"res://tests/acceptance/clinical_fixtures.gd")
	for case_id: String in CASES:
		if not t.wants(case_id): continue
		t.begin_case(case_id)
		if not _content.error.is_empty():
			t.check(case_id,false,{"content_error":_content.error})
			continue
		var started: int = Time.get_ticks_msec()
		var ready: bool = true
		for key: String in PREREQUISITES.get(case_id,[]):
			if not await _ensure_boundary(t,key):
				ready = false
				break
		t.preparation_elapsed(started)
		if ready:
			await call("_case_"+case_id.right(2),t)
		else:
			t.check(case_id,false,{"fixture_prerequisites":_fixture_failures,"required":PREREQUISITES.get(case_id,[])})
	_dispose_simulations()

func _declare_call_ready(c: Dictionary, visit_ids: Array) -> void:
	# Input construction only: retain positions and tickets, remove an earlier
	# service/seat walk that does not belong to the rule being exercised.
	for visit_id: String in visit_ids:
		var actor_id: String = str(c.world.facts.visits[visit_id].actor_id)
		var seat: Dictionary = c.world.facts.waiting_life.seats.get(visit_id,{})
		var chair_id: String = str(seat.get("facility_id",""))
		c.sim.services.waiting._release_seat(c.world,visit_id)
		c.world.facts.moves.erase(actor_id)
		if c.world.facts.adaptations.get(chair_id,{}).get("actor_id","")==actor_id:
			c.world.facts.adaptations.erase(chair_id)

func _validate_rule_input(c: Dictionary, case_id: String, kind: String) -> String:
	c.world.touch()
	c.sim._ensure_services()
	var validation: String = c.world.validate(_content)
	print("CASE_INPUT "+case_id+" "+JSON.stringify({"kind":kind,"tick":c.world.sim_tick,"validation":validation}))
	return validation

func _case_01(t) -> void:
	var c: Dictionary = _context()
	_seed_stream(c.world,"treatment",true,true,9200,9800)
	var arrived: bool = _arrive(c)
	var duplicate: CommandResult = CommandResult.new(false,"not_checked")
	var request: Dictionary = {"arrival_key":_visit(c).get("arrival_key",""),"binding_id":"B_S13_D09_M09","requested_plan_id":"P_D09_COMMON","personality_id":"PP01"}
	duplicate = _command(c,"clinical_arrive",request)
	var reception: bool = arrived and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="reception")
	var reception_session: Dictionary = _session(c,"reception").duplicate(true)
	t.check("CLIN-01",reception and duplicate.accepted and c.world.facts.visits.size()==1 and c.world.facts.arrival_receipts.size()==1 and c.world.facts.actors.size()==c.world.facts.staff.size()+1 and int(reception_session.get("total_ticks",-1))==60 and c.world.facts.attempts.is_empty() and _income(c)==0 and _units_used(c)==0,_state(c))

func _case_02(t) -> void:
	# This is the ordinary outpatient integration case. Its actual GP and
	# treatment handoff run together; quote/boundary cases use checkpoints.
	var c: Dictionary = _context()
	_seed_stream(c.world,"treatment",true,true,9200,9800)
	var arrived: bool = _arrive(c)
	var gp: bool = arrived and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="gp")
	c.queue_gp_session = _session(c,"gp").duplicate(true)
	var waiting: bool = gp and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="wait_outpatient" and c.world.facts.preparations.has(c.visit_id) and _visit(c).attempt_ids.is_empty())
	var actual_gp: Dictionary = c.queue_gp_session
	var started: bool = waiting and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="outpatient")
	var actual_treatment: Dictionary = _session(c,"outpatient").duplicate(true)
	var departed: bool = started and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="departed")
	var ids: Array = _visit(c).get("attempt_ids",[])
	var gp_id: String = str(actual_gp.get("staff_ids",[""])[0])
	var treatment_id: String = str(actual_treatment.get("staff_ids",[""])[0])
	var actual_handoff: bool = gp_id!=treatment_id and gp_id==str(c.doctors[0]) and treatment_id==str(c.doctors[1])
	if actual_handoff:
		actual_handoff = c.sim.clinic._schedule_allows(c.world,gp_id,"gp",_visit(c),str(actual_gp.facility_id)) and c.sim.clinic._schedule_allows(c.world,treatment_id,"outpatient",_visit(c),str(actual_treatment.facility_id)) and not c.sim.clinic._schedule_allows(c.world,gp_id,"outpatient",_visit(c),str(actual_treatment.facility_id))
	t.check("CLIN-02",departed and actual_handoff and _visit(c).get("final_result","")=="cured" and _income(c)==235 and _income(c,"consultation")==20 and _income(c,"gp")==5 and _income(c,"outpatient")==10 and _income(c,"cure")==200 and ids.size()==1 and _units_used(c)==1 and c.world.facts.sessions.is_empty() and c.world.facts.ward_stays.is_empty(),{"actual_gp_doctor":gp_id,"actual_treatment_doctor":treatment_id,"legal_separate_pool_handoff":actual_handoff,"state":_state(c)})

func _case_03(t) -> void:
	await _diagnosis_chain(t,false)

func _case_04(t) -> void:
	await _diagnosis_chain(t,true)

func _case_05(t) -> void:
	if not _require(t,["CLIN-05"],"gp_started"): return
	var frozen: Dictionary = _copy("gp_started")
	var original: Dictionary = _session(frozen,"gp").duplicate(true)
	var doctor_id: String = str(original.get("staff_ids",[""])[0])
	if frozen.world.facts.staff.has(doctor_id): frozen.world.facts.staff[doctor_id].title_id = "DT04"
	frozen.world.facts.facilities[original.facility_id].grade = 2
	var completed: bool = await _until(t,frozen,func()->bool: return _visit(frozen).get("evidence_by_source",{}).has("gp"))
	var paid: int = _income(frozen)
	# Late completion delivery goes through the existing Session identity guard.
	frozen.sim.clinic._complete_service(frozen.world,original)
	HospitalLedger.settle(frozen.world)
	t.check("CLIN-05",completed and int(original.get("doctor_fee",-1))==20 and paid==25 and _income(frozen)==25 and _visit(frozen).evidence_by_source.size()==1,{"quoted":original,"income":_income(frozen),"state":_state(frozen)})

func _case_06(t) -> void:
	var c: Dictionary = _copy("outpatient_queue")
	var before: Dictionary = c.world.freeze()
	var ordinary: Dictionary = c.sim.clinic.plan_quote(c.world,c.visit_id,"P_D09_COMMON")
	var gentle: Dictionary = c.sim.clinic.plan_quote(c.world,c.visit_id,"P_D09_GENTLE")
	var repeated: Dictionary = c.sim.clinic.plan_quote(c.world,c.visit_id,"P_D09_GENTLE")
	c.sim.clinic.compare_plans(c.world,c.visit_id)
	# Simulation §4: D09 uses 30 standard seconds, no communication or
	# department modifier in this fixture. Each plan rounds only its final ticks.
	var preparation: Dictionary = c.world.facts.preparations.get(c.visit_id,{})
	var operators: Array = preparation.get("staff_ids",[])
	var operator_id: String = str(operators[0]) if not operators.is_empty() else ""
	var operator: Dictionary = c.world.facts.staff.get(operator_id,{})
	var facility: Dictionary = c.world.facts.facilities.get(str(preparation.get("facility_id","")),{})
	var level: int = int(operator.get("abilities",{}).get("treatment",0))
	var grade: int = int(facility.get("grade",-1))
	var fatigue: float = float(operator.get("fatigue",0.0))
	var utilization: Dictionary = {1:0.60,2:0.70,3:0.80,4:0.90,5:1.00}
	var oracle_ready: bool = utilization.has(level) and grade>=0 and grade<=2 and facility.get("definition_id","")=="M09"
	var unrounded_seconds: float = 0.0
	var expected_common_ticks: int = -1
	var expected_gentle_ticks: int = -1
	if oracle_ready:
		var effective: float = float(grade)*float(utilization[level])
		unrounded_seconds = 30.0/(1.0+0.05*(level-1)+0.20*effective)*(1.0+0.003*fatigue)
		expected_common_ticks = ceili(unrounded_seconds*10.0)
		expected_gentle_ticks = ceili(unrounded_seconds*1.8*10.0)
	t.check("CLIN-06",oracle_ready and ordinary.get("ok",false) and gentle.get("ok",false) and int(ordinary.get("probability_bp",-1))==9200 and int(gentle.get("probability_bp",-1))==9700 and int(ordinary.get("supply_units",-1))==1 and int(gentle.get("supply_units",-1))==2 and int(ordinary.get("work_ticks",-1))==expected_common_ticks and int(gentle.get("work_ticks",-1))==expected_gentle_ticks and int(ordinary.get("facility_fee",-1))==10 and int(gentle.get("facility_fee",-1))==10 and int(ordinary.get("cure_fee",-1))==200 and int(gentle.get("cure_fee",-1))==220 and gentle==repeated and c.world.freeze()==before,{"ordinary":ordinary,"gentle":gentle,"oracle_inputs":{"operator_id":operator_id,"treatment_level":level,"equipment_grade":grade,"fatigue":fatigue},"unrounded_standard_seconds":unrounded_seconds,"expected_common_ticks":expected_common_ticks,"expected_gentle_ticks":expected_gentle_ticks,"world_changed":c.world.freeze()!=before})

func _case_07(t) -> void:
	var c: Dictionary = _copy("c_diagnosed")
	for staff: Dictionary in c.world.facts.staff.values():
		if staff.role=="doctor": staff.abilities.treatment = 1
	var too_low: Dictionary = c.sim.clinic.plan_quote(c.world,c.visit_id,"P_D14_COMMON")
	for staff: Dictionary in c.world.facts.staff.values():
		if staff.role=="doctor": staff.abilities.treatment = 3
	c.world.facts.research.erase("R33")
	var missing_research: Dictionary = c.sim.clinic.plan_quote(c.world,c.visit_id,"P_D14_GENTLE")
	c.world.facts.research.append("R33")
	var missing_bed: Dictionary = c.sim.clinic.plan_quote(c.world,c.visit_id,"P_D14_GENTLE")
	var rejected: CommandResult = _command(c,"clinical_select_plan",{"visit_id":c.visit_id,"plan_id":"P_D14_GENTLE"})
	t.check("CLIN-07",not too_low.get("ok",true) and not missing_research.get("ok",true) and not missing_bed.get("ok",true) and not rejected.accepted and c.world.facts.attempts.is_empty() and c.world.facts.preparations.is_empty() and _units_used(c)==0,{"ability":too_low,"research":missing_research,"bed":missing_bed,"command":rejected.to_record()})

func _case_08(t) -> void:
	var short: Dictionary = _copy("outpatient_queue")
	# This shared boundary already owns a reservation. Release it through the
	# existing same-plan command before constructing an unreserved shortage.
	var released: CommandResult = _command(short,"clinical_select_plan",{"visit_id":short.visit_id,"plan_id":"P_D09_COMMON"})
	var unreserved: bool = released.accepted and short.world.facts.preparations.is_empty() and short.sim.services.supplies.reserved(short.world)==0
	_declare_call_ready(short,[short.visit_id])
	if unreserved: short.world.facts.inventory.units = 0
	var original_ticket: String = str(_visit(short).ticket_id)
	var consults: int = int(short.started.get("consult",0))
	if unreserved: await _steps(t,short,50)
	var blocked: bool = unreserved and short.world.facts.attempts.is_empty() and _units_used(short)==0 and _income(short)==25 and str(_visit(short).ticket_id)==original_ticket
	var purchased: CommandResult = _command(short,"purchase_supplies",{"units":1,"unit_price":20,"order_id":"clinical_shortage_purchase"}) if blocked else CommandResult.new(false,"shortage_fixture_not_ready")
	var after_purchase: int = HospitalLedger.balance(short.world)
	var resumed: bool = purchased.accepted and await _until(t,short,func()->bool: return _visit(short).get("phase","")=="outpatient")
	var session: Dictionary = _session(short,"outpatient")
	t.check("CLIN-08",blocked and resumed and int(short.started.get("consult",0))==consults and str(session.get("original_ticket",{}).get("id",""))==original_ticket and _units_used(short)==1 and int(short.world.facts.inventory.units)==0 and HospitalLedger.balance(short.world)==after_purchase,{"released_unstarted_reservation":released.to_record(),"blocked_without_effects":blocked,"purchased":purchased.to_record(),"state":_state(short)})

func _case_09(t) -> void:
	var retry: Dictionary = _copy("outpatient_queue")
	_seed_stream(retry.world,"treatment",false,true,9200,9800)
	# Doctor ownership exercises automatic consultation after failure.
	_visit(retry).plan_decision.source = "doctor"
	var twice: bool = await _until(t,retry,func()->bool: return _visit(retry).attempt_ids.size()==2,2600)
	var ids: Array = _visit(retry).attempt_ids
	var first: Dictionary = retry.world.facts.attempts.get(ids[0],{}) if ids.size()>0 else {}
	var second: Dictionary = retry.world.facts.attempts.get(ids[1],{}) if ids.size()>1 else {}
	t.check("CLIN-09",twice and not first.get("result",true) and second.get("result",false) and int(second.get("probability_bp",-1))==9800 and _units_used(retry)==2 and _income(retry,"consultation")==20 and _income(retry,"gp")==5 and int(retry.started.get("consult",0))==2,{"first":first,"second":second,"state":_state(retry)})

func _case_10(t) -> void:
	var failed: Dictionary = _copy("outpatient_queue")
	_seed_stream(failed.world,"treatment",false,false,9200,9800)
	var departed: bool = await _until(t,failed,func()->bool: return _visit(failed).get("phase","")=="departed",2600)
	var at_end: Dictionary = failed.world.facts.ledger.entries.duplicate(true)
	await _steps(t,failed,5)
	t.check("CLIN-10",departed and _visit(failed).attempt_ids.size()==2 and _visit(failed).get("final_result","")=="referred" and _income(failed)==45 and _income(failed,"cure")==0 and _units_used(failed)==2 and failed.world.facts.ledger.entries==at_end,{"income":_income(failed),"used":_units_used(failed),"state":_state(failed)})

func _case_11(t) -> void:
	var manual: Dictionary = _copy("outpatient_queue")
	var selected: CommandResult = _command(manual,"clinical_select_plan",{"visit_id":manual.visit_id,"plan_id":"P_D09_GENTLE"})
	_seed_stream(manual.world,"treatment",false,true,9700,9800)
	manual.world.facts.inventory.units = 0
	var ticket: String = str(_visit(manual).ticket_id)
	var revision: int = int(_visit(manual).plan_decision.get("revision",-1))
	await _steps(t,manual,20)
	var preserved: bool = _visit(manual).plan_decision.get("plan_id","")=="P_D09_GENTLE" and _visit(manual).ticket_id==ticket and int(_visit(manual).plan_decision.get("revision",-2))==revision and manual.world.facts.preparations.is_empty()
	var purchase: CommandResult = _command(manual,"purchase_supplies",{"units":4,"order_id":"clinical_manual_supply"})
	var repeated: bool = purchase.accepted and await _until(t,manual,func()->bool: return _visit(manual).attempt_ids.size()==2,2800)
	var all_gentle: bool = true
	for attempt_id: String in _visit(manual).attempt_ids: all_gentle = all_gentle and manual.world.facts.attempts[attempt_id].plan_id=="P_D09_GENTLE"
	t.check("CLIN-11",selected.accepted and preserved and repeated and all_gentle and _visit(manual).plan_decision.get("source","")=="director" and int(manual.started.get("consult",0))==1 and _units_used(manual)==4,{"preserved_during_shortage":preserved,"state":_state(manual)})

func _case_12(t) -> void:
	var c: Dictionary = _copy("outpatient_started")
	await _steps(t,c,17)
	var before: Dictionary = c.world.freeze()
	var session: GameSession = GameSession.new(c.sim,"clinical-pause")
	session.set_speed(1)
	session.pause("acceptance")
	for index: int in 4: session.advance(0.5)
	var paused: bool = c.world.freeze()==before
	var restored: Dictionary = _roundtrip(c)
	var resumed: bool = restored.ok and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="departed")
	t.check("CLIN-12",paused and resumed and _commitments(c.world.facts.attempts)==_commitments(before.attempts) and _income(c)==235 and _units_used(c)==1 and c.world.facts.inventory.issues==before.inventory.issues,{"paused_without_effects":paused,"restore":restored,"state":_state(c)})

func _case_13(t) -> void:
	var timing: RefCounted = ClinicalTiming.new()
	var clock: int = Time.get_ticks_usec()
	var basic: Dictionary = _copy("outpatient_queue")
	var surgical: Dictionary = _copy("c_surgery_queue")
	timing.finish("input_copy",clock)
	clock = Time.get_ticks_usec()
	var before_basic: Dictionary = basic.world.freeze()
	var before_surgical: Dictionary = surgical.world.freeze()
	var gentle: Dictionary = basic.sim.clinic.plan_quote(basic.world,basic.visit_id,"P_D09_GENTLE")
	var surgery: Dictionary = surgical.sim.clinic.plan_quote(surgical.world,surgical.visit_id,"P_D14_SURGERY")
	var readonly: bool = basic.world.freeze()==before_basic and surgical.world.freeze()==before_surgical
	timing.finish("readonly_quotes",clock)
	clock = Time.get_ticks_usec()
	# Legal input immediately before commitment: selection, reservation and arrival
	# are inputs here. The dispatch below must create the actual Attempt and issue.
	var preparation: Dictionary = basic.world.facts.preparations.get(basic.visit_id,{})
	if preparation.is_empty() or not gentle.get("ok",false):
		t.check("CLIN-13",false,{"missing_commit_input":true,"gentle":gentle,"timing":timing.report()})
		return
	_declare_call_ready(basic,[basic.visit_id])
	_visit(basic).requested_plan_id = "P_D09_GENTLE"
	_visit(basic).plan_decision = {"plan_id":"P_D09_GENTLE","source":"director","doctor_id":preparation.staff_ids[0],"revision":int(_visit(basic).plan_decision.get("revision",0))+1,"probability_bp":9700,"reason":"boundary input"}
	preparation.supply_units = 2
	var layout: Dictionary = basic.sim.space.facility_layout(basic.world,preparation.facility_id)
	var positions: Dictionary = {_visit(basic).actor_id:layout.patient_cell,preparation.staff_ids[0]:layout.operator_cells[0]}
	for actor_id: String in positions:
		basic.world.facts.moves.erase(actor_id)
		basic.world.facts.actors[actor_id].location = {"kind":"floor","floor_id":int(layout.floor_id),"cell":positions[actor_id].duplicate(),"height_m":0.0}
		basic.world.facts.actors[actor_id].posture = "standing"
		basic.world.facts.actors[actor_id].erase("support_facility_id")
	_seed_stream(basic.world,"treatment",true,true,9700,9800)
	var validation: String = _validate_rule_input(basic,"CLIN-13","ready_gentle_commit")
	timing.finish("commit_input",clock)
	if not validation.is_empty():
		t.check("CLIN-13",false,{"input_validation":validation,"timing":timing.report()})
		return
	clock = Time.get_ticks_usec()
	await _steps(t,basic,1)
	var started: bool = _visit(basic).get("phase","")=="outpatient" and basic.world.facts.attempts.size()==1
	timing.finish("real_commit",clock)
	if not started:
		t.check("CLIN-13",false,{"missing_real_commit":true,"state":_state(basic),"timing":timing.report()})
		return
	clock = Time.get_ticks_usec()
	var committed: Dictionary = _commitments(basic.world.facts.attempts)
	var original: Dictionary = basic.world.facts.attempts.values()[0].duplicate(true)
	basic.world.facts.facilities.zombie_machine.grade = 2
	basic.world.touch()
	var changed_quote: Dictionary = basic.sim.clinic.plan_quote(basic.world,basic.visit_id,"P_D09_GENTLE",{"structural_only":true})
	await _steps(t,basic,2)
	timing.finish("changed_conditions",clock)
	t.check("CLIN-13",readonly and gentle.get("ok",false) and surgery.get("ok",false) and int(gentle.get("cure_fee",-1))==220 and int(surgery.get("cure_fee",-1))==1080 and int(original.get("cure_fee",-1))==220 and changed_quote.get("ok",false) and int(changed_quote.get("work_ticks",-1))!=int(original.work_ticks) and _commitments(basic.world.facts.attempts)==committed and _units_used(basic)==2 and _income(basic)==25,{"readonly_quotes":readonly,"gentle":gentle,"surgery":surgery,"changed_quote":changed_quote,"committed":committed,"state":_state(basic),"timing":timing.report()})

func _case_14(t) -> void:
	var qualified: Dictionary = _copy("surgery_queue")
	var complete: Dictionary = qualified.sim.clinic.plan_quote(qualified.world,qualified.visit_id,"P_D09_SURGERY")
	qualified.world.facts.staff.clin_surgeon.abilities.surgery = 4
	var stronger_later_team: Dictionary = qualified.sim.clinic.plan_quote(qualified.world,qualified.visit_id,"P_D09_SURGERY")
	qualified.world.facts.staff.clin_surgeon.abilities.surgery = 2
	qualified.world.facts.floors.overrides["1"].plots.append([0,2])
	_add_layout(qualified.world,"or_standard","clin_unavailable_or",[19,65])
	qualified.world.facts.facilities.clin_unavailable_or_0.grade = 2
	qualified.world.facts.facilities.clin_unavailable_or_0.failed = true
	qualified.world.touch()
	var unavailable_better_table: Dictionary = qualified.sim.clinic.plan_quote(qualified.world,qualified.visit_id,"P_D09_SURGERY")
	var duplicate_team: Dictionary = qualified.sim.clinic._surgery_bundle_quote(qualified.world,_visit(qualified),["clin_surgeon","clin_surgeon","clin_or_nurse"],"clin_or_0",{},{})
	qualified.world.facts.staff.clin_anesthesia.abilities.surgery = 0
	var missing_doctor: Dictionary = qualified.sim.clinic.plan_quote(qualified.world,qualified.visit_id,"P_D09_SURGERY")
	qualified.world.facts.staff.clin_anesthesia.abilities.surgery = 2
	qualified.world.facts.staff.clin_cover.on_shift = false
	var missing_coverage: Dictionary = qualified.sim.clinic.plan_quote(qualified.world,qualified.visit_id,"P_D09_SURGERY")
	t.check("CLIN-14",complete.get("ok",false) and stronger_later_team.get("ok",false) and stronger_later_team.get("staff_ids",[])[0]=="clin_surgeon" and int(stronger_later_team.get("probability_bp",-1))==9800 and unavailable_better_table.get("ok",false) and unavailable_better_table.get("facility_id","")=="clin_or_0" and int(unavailable_better_table.get("probability_bp",-1))==9600 and not duplicate_team.get("ok",true) and not missing_doctor.get("ok",true) and not missing_coverage.get("ok",true) and qualified.world.facts.preparations.is_empty() and qualified.world.facts.attempts.is_empty() and _units_used(qualified)==0,{"complete":complete,"stronger_later_team":stronger_later_team,"unavailable_better_table":unavailable_better_table,"duplicate_team":duplicate_team,"missing_doctor":missing_doctor,"missing_coverage":missing_coverage})

func _case_15(t) -> void:
	var timing: RefCounted = ClinicalTiming.new()
	var clock: int = Time.get_ticks_usec()
	var c: Dictionary = _copy("surgery_queue")
	_declare_call_ready(c,[c.visit_id])
	var validation: String = _validate_rule_input(c,"CLIN-15","call_ready_before_reservation")
	timing.finish("call_ready_input",clock)
	if not validation.is_empty():
		t.check("CLIN-15",false,{"input_validation":validation,"timing":timing.report()})
		return
	clock = Time.get_ticks_usec()
	c.world.facts.inventory.units = 7
	var before_shortage: Dictionary = c.world.freeze()
	var short_requests: Array = c.sim.clinic.shortage_requests(c.world)
	var shortage_readonly: bool = before_shortage==c.world.freeze()
	c.world.facts.inventory.units = 8
	var enough_requests: Array = c.sim.clinic.shortage_requests(c.world)
	c.world.facts.inventory.units = 60
	var supply_boundary: bool = shortage_readonly and short_requests.size()==1 and int(short_requests[0].get("units",-1))==8 and short_requests[0].visit_id==c.visit_id and enough_requests.is_empty()
	timing.finish("supply_boundary",clock)
	clock = Time.get_ticks_usec()
	await _steps(t,c,1)
	timing.finish("real_reservation",clock)
	var prepared: bool = c.world.facts.preparations.has(c.visit_id)
	var preparation: Dictionary = c.world.facts.preparations.get(c.visit_id,{}).duplicate(true)
	t.check("CLIN-15",supply_boundary and prepared and int(preparation.get("supply_units",-1))==8 and int(preparation.get("setup_remaining_ticks",-1))==80 and int(preparation.get("deadline_tick",-1))-c.world.sim_tick==299 and preparation.get("staff_ids",[]).size()==3 and not str(preparation.get("bed_id","")).is_empty() and c.sim.services.supplies.reserved(c.world)==8 and c.world.facts.attempts.is_empty() and _units_used(c)==0 and int(c.world.facts.inventory.units)==60 and _income(c)==25 and int(c.world.facts.staff.clin_or_nurse.practice.surgery)==0,{"supply_boundary":supply_boundary,"short_requests":short_requests,"enough_requests":enough_requests,"preparation":preparation,"state":_state(c),"timing":timing.report()})

func _case_16(t) -> void:
	var timing: RefCounted = ClinicalTiming.new()
	var clock: int = Time.get_ticks_usec()
	var cancel: Dictionary = _copy("surgery_prepared")
	var expiry: Dictionary = _copy("surgery_prepared")
	var old_ticket: String = str(_visit(cancel).ticket_id)
	var expiry_ticket: String = str(_visit(expiry).ticket_id)
	var deadline: int = int(expiry.world.facts.preparations[expiry.visit_id].deadline_tick)
	# Prior waiting is an input. Dispatch at deadline-1 must retain the bundle;
	# dispatch at deadline must release it. Each real step increments tick at end.
	expiry.world.facts.sim_tick = deadline-1
	var validation: String = _validate_rule_input(expiry,"CLIN-16","one_dispatch_before_deadline")
	timing.finish("boundary_inputs",clock)
	if not validation.is_empty():
		t.check("CLIN-16",false,{"input_validation":validation,"timing":timing.report()})
		return
	clock = Time.get_ticks_usec()
	var result: CommandResult = _command(cancel,"clinical_auto_plan",{"visit_id":cancel.visit_id})
	var cancelled: bool = result.accepted and cancel.world.facts.preparations.is_empty() and cancel.sim.services.supplies.reserved(cancel.world)==0 and _units_used(cancel)==0 and cancel.world.facts.attempts.is_empty() and str(_visit(cancel).ticket_id)==old_ticket and _income(cancel)==25 and cancel.world.validate(_content).is_empty()
	timing.finish("cancel",clock)
	clock = Time.get_ticks_usec()
	var treatment_rng: Variant = expiry.world.facts.rng.get("treatment").duplicate(true)
	await _steps(t,expiry,1)
	var before_deadline: bool = expiry.world.sim_tick==deadline and expiry.world.facts.preparations.has(expiry.visit_id) and expiry.sim.services.supplies.reserved(expiry.world)==8 and expiry.world.facts.attempts.is_empty() and _units_used(expiry)==0 and _income(expiry)==25
	timing.finish("dispatch_before_deadline",clock)
	clock = Time.get_ticks_usec()
	await _steps(t,expiry,1)
	var expired: bool = expiry.world.sim_tick==deadline+1 and expiry.world.facts.preparations.is_empty() and expiry.world.facts.attempts.is_empty() and _visit(expiry).ticket_id==expiry_ticket and _units_used(expiry)==0 and int(expiry.world.facts.inventory.units)==60 and expiry.sim.services.supplies.reserved(expiry.world)==0 and _income(expiry)==25 and expiry.world.facts.rng.get("treatment")==treatment_rng
	timing.finish("dispatch_at_deadline",clock)
	t.check("CLIN-16",cancelled and before_deadline and expired,{"cancelled_without_effects":cancelled,"retained_before_deadline":before_deadline,"expired_at_deadline":expired,"dispatch_ticks":[deadline-1,deadline],"state":_state(expiry),"timing":timing.report()})

func _case_17(t) -> void:
	var timing: RefCounted = ClinicalTiming.new()
	var clock: int = Time.get_ticks_usec()
	var race: Dictionary = _copy("surgery_queue")
	timing.finish("input_copy",clock)
	clock = Time.get_ticks_usec()
	var observation_only: bool = timing.attach(race.sim)
	timing.finish("timing_install",clock)
	if not observation_only:
		t.check("CLIN-17",false,{"timing_changed_facts":true,"timing":timing.report()})
		return
	clock = Time.get_ticks_usec()
	race.world.facts.facilities.erase("clin_ward_1")
	race.world.facts.floors.overrides["1"].plots.append([0,2])
	_add_layout(race.world,"or_standard","clin_second_or",[19,65])
	_add_worker(race.world,"second_surgeon","doctor",[20,75],"surgery",{"diagnosis":1,"treatment":1,"care":0,"surgery":2},"DT02")
	_add_worker(race.world,"second_anesthesia","doctor",[24,75],"surgery",{"diagnosis":1,"treatment":1,"care":0,"surgery":2},"DT02")
	_add_worker(race.world,"second_or_nurse","nurse",[28,75],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":1})
	race.world.facts.staff.second_or_nurse.certificates = ["q_or","q_ward"]
	var second_visit: String = _waiting_case(race,[49,94])
	var first_ticket: String = str(_visit(race).ticket_id)
	var second_ticket: String = str(race.world.facts.visits[second_visit].ticket_id)
	_declare_call_ready(race,[race.visit_id,second_visit])
	timing.finish("competition_input",clock)
	clock = Time.get_ticks_usec()
	var input_validation: String = _validate_rule_input(race,"CLIN-17","two_call_ready_surgical_patients")
	timing.finish("input_validation",clock)
	var call_ready: bool = input_validation.is_empty() and race.world.facts.preparations.is_empty() and first_ticket<second_ticket
	for visit_id: String in [race.visit_id,second_visit]:
		var visit: Dictionary = race.world.facts.visits[visit_id]
		call_ready = call_ready and not race.world.facts.moves.has(visit.actor_id) and not race.world.facts.waiting_life.needs.has(visit_id) and race.world.facts.tickets[visit.ticket_id].get("pause_reasons",{}).is_empty()
	if not call_ready:
		t.check("CLIN-17",false,{"input_validation":input_validation,"call_ready":call_ready,"timing":timing.report()})
		return
	var digest: HashingContext = HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(race.world.freeze()))
	var input_sha256: String = digest.finish().hex_encode()
	clock = Time.get_ticks_usec()
	await _steps(t,race,1)
	timing.finish("formal_dispatch_step",clock)
	var first_prepared: Dictionary = race.world.facts.preparations.get(race.visit_id,{})
	var later: Dictionary = race.world.facts.visits[second_visit]
	clock = Time.get_ticks_usec()
	var later_quote: Dictionary = race.sim.clinic._surgery_quote(race.world,later,["second_surgeon","second_anesthesia","second_or_nurse"],{"facility_id":"clin_second_or_0"})
	timing.finish("loser_quote",clock)
	t.check("CLIN-17",race.world.facts.preparations.size()==1 and not first_prepared.is_empty() and not race.world.facts.preparations.has(second_visit) and str(later.ticket_id)==second_ticket and not later_quote.get("ok",true) and str(later_quote.get("reason","")).contains("床") and race.world.facts.attempts.is_empty() and _units_used(race)==0 and race.sim.services.supplies.reserved(race.world)==8,{"input_sha256":input_sha256,"call_ready_input":call_ready,"first_ticket":first_ticket,"second_ticket":second_ticket,"later_quote":later_quote,"state":_state(race),"timing":timing.report()})

func _case_18(t) -> void:
	# Surgical integration retains real gathering, setup and all four work beats.
	var timing: RefCounted = ClinicalTiming.new()
	var clock: int = Time.get_ticks_usec()
	var c: Dictionary = _copy("surgery_queue")
	var input_validation: String = c.world.validate(_content)
	var observation_only: bool = timing.attach(c.sim)
	var digest: HashingContext = HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(c.world.freeze()))
	var input_sha256: String = digest.finish().hex_encode()
	var initial_tick: int = c.world.sim_tick
	timing.finish("input_and_timing",clock)
	if not input_validation.is_empty() or not observation_only:
		t.check("CLIN-18",false,{"input_validation":input_validation,"timing_changed_facts":not observation_only,"timing":timing.report()})
		return
	clock = Time.get_ticks_usec()
	var begun: bool = await _until(t,c,func()->bool: return _visit(c).get("phase","")=="surgery",600)
	var surgery_tick: int = c.world.sim_tick
	timing.finish("real_gathering_and_setup",clock)
	if not begun:
		t.check("CLIN-18",false,{"missing_real_business_boundary":"surgery_started","state":_state(c),"timing":timing.report()})
		return
	clock = Time.get_ticks_usec()
	var frozen: Dictionary = c
	var before: Dictionary = _commitments(frozen.world.facts.attempts)
	var original: Dictionary = frozen.world.facts.attempts.values()[0].duplicate(true)
	frozen.world.facts.staff[original.staff_ids[0]].abilities.surgery = 5
	frozen.world.facts.facilities[original.facility_id].grade = 2
	var restored: Dictionary = _roundtrip(frozen)
	if restored.ok:
		observation_only = timing.attach(frozen.sim) and observation_only
	timing.finish("commitment_roundtrip",clock)
	clock = Time.get_ticks_usec()
	await _steps(t,frozen,3)
	timing.finish("first_three_work_ticks",clock)
	clock = Time.get_ticks_usec()
	var reached_wake: bool = restored.ok and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="wake",1800)
	timing.finish("remaining_work_to_wake",clock)
	t.check("CLIN-18",observation_only and reached_wake and restored.ok and int(original.get("probability_bp",-1))==9600 and int(original.get("work_ticks",-1))==1200 and int(original.get("recovery_ticks",-1))==1800 and int(original.get("ward_fee",original.get("ward_fee_quote",-1)))==60 and original.get("beat_end_ticks",[])==[180,720,1020,1200] and _commitments(frozen.world.facts.attempts)==before and c.beats.size()==4 and _units_used(frozen)==8 and frozen.world.facts.attempts.size()==1,{"input_sha256":input_sha256,"real_ticks":{"initial":initial_tick,"surgery_started":surgery_tick,"wake":c.world.sim_tick},"attempt":original,"actual_beats":c.beats,"restore":restored,"state":_state(frozen),"timing":timing.report()})

func _case_19(t) -> void:
	var wake: Dictionary = _copy("surgery_wake")
	var wake_session: Dictionary = _session(wake,"wake").duplicate(true)
	var no_early_charge: bool = _income(wake,"surgery")==0 and _income(wake,"cure")==0 and int(wake_session.get("total_ticks",-1))==150
	var held: bool = true
	for staff_id: String in wake_session.get("staff_ids",[]): held = held and wake.sim.clinic.staff_busy(wake.world,staff_id)
	await _steps(t,wake,149)
	var before_end: bool = _visit(wake).phase=="wake" and _income(wake,"surgery")==0 and int(_session(wake,"wake").get("remaining_ticks",-1))==1
	await _steps(t,wake,1)
	t.check("CLIN-19",no_early_charge and held and before_end and _visit(wake).phase=="transfer" and _session(wake,"wake").is_empty() and _income(wake,"surgery")==60 and _income(wake,"ward")==0 and _income(wake,"cure")==0 and not _stay(wake).is_empty(),{"not_charged_before_wake":no_early_charge,"all_staff_held":held,"before_last_tick":before_end,"state":_state(wake)})

func _case_20(t) -> void:
	var c: Dictionary = _copy("surgery_transfer")
	var in_bed: bool = await _until(t,c,func()->bool: return _visit(c).get("phase","")=="recovery",900)
	var stay: Dictionary = _stay(c)
	var attempt: Dictionary = c.world.facts.attempts.get(stay.get("attempt_id",""),{})
	var transferred_id: String = str(stay.get("attempt_id",""))
	var entered_units: int = _units_used(c)
	var escort: String = str(stay.get("escort_id",""))
	var released: bool = in_bed and await _until(t,c,func()->bool: return not c.sim.clinic.staff_busy(c.world,escort),180)
	t.check("CLIN-20",in_bed and released and bool(c.group_seen) and str(_stay(c).get("attempt_id",""))==transferred_id and not attempt.is_empty() and _visit(c).attempt_ids.size()==1 and c.world.facts.actors[_visit(c).actor_id].get("posture","")=="lying" and entered_units==8 and _units_used(c)==8 and _income(c,"surgery")==60 and _income(c,"ward")==0 and _income(c,"cure")==0,{"group_seen":c.group_seen,"escort_released":released,"state":_state(c)})

func _case_21(t) -> void:
	var fault: Dictionary = _copy("surgery_started")
	var before: Dictionary = _commitments(fault.world.facts.attempts)
	fault.world.facts.facilities.clin_or_0.pending_failure = true
	var completed: bool = await _until(t,fault,func()->bool: return _visit(fault).get("phase","")=="transfer",1800)
	var table: Dictionary = fault.world.facts.facilities.clin_or_0
	t.check("CLIN-21",completed and _commitments(fault.world.facts.attempts)==before and fault.world.facts.attempts.size()==1 and _units_used(fault)==8 and _income(fault,"surgery")==60 and _income(fault,"cure")==0 and (table.pending_failure or table.failed or table.get("maintenance_block",false)),_state(fault))

func _case_22(t) -> void:
	if not _require(t,["CLIN-22"],"ward_after_care"): return
	var coverage: Dictionary = _copy("ward_after_care")
	var nurse_id: String = str(_stay(coverage).nurse_id)
	var idle: bool = await _until(t,coverage,func()->bool: return not coverage.sim.clinic.staff_busy(coverage.world,nurse_id) and not coverage.world.facts.moves.has(nurse_id),180)
	var moving: String = coverage.sim.space.request_move(coverage.world,nurse_id,1,[44,75]) if idle else "覆盖护士尚未安全离位"
	var outside_seen: bool = false
	var uncovered_ticks: int = 0
	var uncovered_stops: bool = true
	var returned: bool = false
	if moving.is_empty():
		for index: int in 500:
			var before_inside: bool = _in_stay_ward(coverage,nurse_id)
			var before_remaining: int = int(_stay(coverage).get("remaining_ticks",-1))
			_tick(coverage)
			var after_inside: bool = _in_stay_ward(coverage,nurse_id)
			outside_seen = outside_seen or not after_inside
			if not before_inside and not after_inside:
				uncovered_ticks += 1
				uncovered_stops = uncovered_stops and int(_stay(coverage).get("remaining_ticks",-2))==before_remaining
			if outside_seen and after_inside and not coverage.world.facts.moves.has(nurse_id) and not coverage.sim.clinic.staff_busy(coverage.world,nurse_id):
				returned = true
				break
			if index%100==99: await t.process_frame
	var before_covered: int = int(_stay(coverage).get("remaining_ticks",-1))
	await _steps(t,coverage,3)
	var covered_progress: bool = returned and int(_stay(coverage).get("remaining_ticks",before_covered))==before_covered-3
	var frozen: Dictionary = coverage.world.freeze()
	var session: GameSession = GameSession.new(coverage.sim,"ward-paused")
	session.set_speed(0)
	for index: int in 3: session.advance(0.5)
	t.check("CLIN-22",idle and moving.is_empty() and outside_seen and uncovered_ticks>0 and uncovered_stops and returned and covered_progress and coverage.world.freeze()==frozen,{"outside_ticks_checked":uncovered_ticks,"uncovered_stops":uncovered_stops,"automatic_return_completed":returned,"covered_progress":covered_progress,"move_reason":moving,"state":_state(coverage)})

func _case_23(t) -> void:
	var two: Dictionary = _copy("ward_after_care")
	_add_worker(two.world,"additional_ward_nurse","nurse",[52,72],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":0})
	two.world.facts.staff.additional_ward_nurse.ward_id = "clin_ward"
	two.world.touch()
	var assigned: String = str(_stay(two).nurse_id)
	var before_two: int = int(_stay(two).remaining_ticks)
	await _steps(t,two,1)
	var counts: Dictionary = {}
	for work: Dictionary in two.world.facts.sessions.values():
		for worker: String in work.staff_ids: counts[worker] = int(counts.get(worker,0))+1
	var unique: bool = true
	for count: int in counts.values(): unique = unique and count<=1
	t.check("CLIN-23",int(_stay(two).remaining_ticks)==before_two-1 and str(_stay(two).nurse_id)==assigned and unique and int(_content.balance.clinical.beds_per_nurse)==8,{"remaining_before":before_two,"remaining_after":_stay(two).remaining_ticks,"active_jobs_by_staff":counts,"assigned_nurse":_stay(two).nurse_id})

func _case_24(t) -> void:
	if not _snapshots.has("ward_care"):
		var partial: WorldState = _simulations.back().world if not _simulations.is_empty() else null
		t.check("CLIN-24",false,{"missing_real_business_boundary":"ward_care","fixture_prerequisites":_fixture_failures,"failure_world":_failure_world("CLIN-24",partial)})
		return
	var rounding: Dictionary = _copy("ward_care")
	# Input: recovery is one tick from its end while the first care visit is
	# still active. Earlier recovery is not the operation under this assertion.
	var care_input: Dictionary = _session(rounding,"care")
	var delta: int = maxi(0,int(_stay(rounding).remaining_ticks)-1)
	rounding.world.facts.sim_tick += delta
	care_input.start_tick += delta
	_stay(rounding).remaining_ticks = 1
	_stay(rounding).last_progress_tick = rounding.world.sim_tick
	if _stay(rounding).has("coverage_segment"): _stay(rounding).coverage_segment.start_tick = rounding.world.sim_tick
	_visit(rounding).last_progress_tick = rounding.world.sim_tick
	_visit(rounding).last_service_tick = rounding.world.sim_tick
	rounding.world.touch()
	print("CASE_INPUT CLIN-24 "+JSON.stringify({"care":"active","recovery_remaining_ticks":1,"prior_recovery":"input"}))
	var input_validation: String = rounding.world.validate(_content)
	if not input_validation.is_empty():
		t.check("CLIN-24",false,{"boundary_input_validation":input_validation})
		return
	_all_rest(rounding.world,"doctor",true)
	await _steps(t,rounding,1)
	var blocked_until_care: bool = int(_stay(rounding).get("remaining_ticks",-1))==0 and not bool(_stay(rounding).get("care_completed",true)) and _stay(rounding).get("phase","")=="recovery" and _income(rounding,"ward")==0 and _income(rounding,"cure")==0
	if not await _until(t,rounding,func()->bool: return bool(_stay(rounding).get("care_completed",false)),350):
		t.check("CLIN-24",false,{"missing_real_business_boundary":"care_completed","state":_state(rounding)})
		return
	_all_rest(rounding.world,"doctor",true)
	var ready: bool = await _until(t,rounding,func()->bool: return _stay(rounding).get("phase","")=="round_wait",2200)
	var held: bool = ready and int(_stay(rounding).get("remaining_ticks",-1))==0 and bool(_stay(rounding).get("care_completed",false)) and _income(rounding,"ward")==0 and _income(rounding,"cure")==0 and _visit(rounding).get("final_result","").is_empty()
	var care_ticks: int = -1
	for source: Dictionary in _snapshots.get("ward_care",{}).get("facts",{}).get("sessions",{}).values():
		if source.kind=="care": care_ticks = int(source.total_ticks)
	var round_input: Dictionary = {}
	var placement: Dictionary = {"qualification_blocked":false,"base_prepared":false,"bedside_reached":false}
	if ready:
		var candidate_doctor: Dictionary = rounding.world.facts.staff.clin_round
		var diagnosis_input: int = int(candidate_doctor.abilities.diagnosis)
		candidate_doctor.abilities.diagnosis = 1
		candidate_doctor.schedule = _schedule("round")
		placement.qualification_blocked = true
		for staff: Dictionary in rounding.world.facts.staff.values():
			if staff.role=="doctor" and staff.on_shift and int(staff.abilities.diagnosis)>=2 and int(staff.abilities.treatment)>=1:
				placement.qualification_blocked = false
		var bed: Dictionary = rounding.sim.space.facility_layout(rounding.world,str(_stay(rounding).bed_id))
		var nurse_id: String = str(_stay(rounding).nurse_id)
		placement.base_prepared = await _until(t,rounding,func()->bool:
			return candidate_doctor.on_shift and bool(candidate_doctor.get("base_prepared",false)) and candidate_doctor.get("base_task",{}).is_empty() and not bool(candidate_doctor.get("block_new_work",false)) and not rounding.world.facts.moves.has("clin_round") and not rounding.sim.clinic.staff_busy(rounding.world,"clin_round") and not rounding.world.facts.moves.has(nurse_id) and not rounding.sim.clinic.staff_busy(rounding.world,nurse_id) and not rounding.sim.space.at(rounding.world,nurse_id,int(bed.floor_id),bed.operator_cells[1]),600)
		placement.move_reason = rounding.sim.space.request_move(rounding.world,"clin_round",int(bed.floor_id),bed.operator_cells[1]) if placement.base_prepared else "医生基地整理或护士安全离位尚未完成"
		placement.bedside_reached = placement.qualification_blocked and placement.move_reason.is_empty() and await _until(t,rounding,func()->bool:
			return rounding.sim.space.at(rounding.world,"clin_round",int(bed.floor_id),bed.operator_cells[1]) and not rounding.world.facts.moves.has("clin_round"),400)
		placement.no_round_before_qualification = _session(rounding,"round").is_empty()
		if placement.bedside_reached and placement.no_round_before_qualification:
			# Qualification remains insufficient throughout the real preparation and walk.
			round_input = {"tick":rounding.world.sim_tick,"doctor_id":"clin_round","fatigue":float(candidate_doctor.fatigue),"treatment_level":int(candidate_doctor.abilities.treatment),"species_id":str(rounding.world.facts.actors.clin_round.species_id),"talent_rate":1.0,"diagnosis_before":int(candidate_doctor.abilities.diagnosis),"diagnosis_input":diagnosis_input}
			candidate_doctor.abilities.diagnosis = diagnosis_input
	var began_round: bool = not round_input.is_empty() and await _until(t,rounding,func()->bool: return not _session(rounding,"round").is_empty(),180)
	var expected_round_ticks: int = -1
	if not round_input.is_empty():
		# Clinical 10 standard seconds; S49 has a course talent, no ward_visit bonus.
		expected_round_ticks = ceili(10.0*10.0*(1.0+0.003*float(round_input.fatigue))/(1.0+0.05*(int(round_input.treatment_level)-1))/float(round_input.talent_rate))
	var round_session: Dictionary = _session(rounding,"round").duplicate(true)
	var doctor: Dictionary = rounding.world.facts.staff.get(str(round_session.get("staff_ids",[""])[0]),{})
	var before_charge: bool = _income(rounding,"ward")==0 and _income(rounding,"cure")==0
	var finished: bool = began_round and await _until(t,rounding,func()->bool: return _visit(rounding).get("final_result","")=="cured",180)
	var departed: bool = finished and await _until(t,rounding,func()->bool: return _visit(rounding).get("phase","")=="departed",900)
	var passed: bool = blocked_until_care and held and care_ticks==80 and began_round and placement.qualification_blocked and placement.base_prepared and placement.bedside_reached and placement.get("no_round_before_qualification",false) and round_input.get("species_id","")=="S49" and int(round_session.get("total_ticks",-1))==expected_round_ticks and int(doctor.get("abilities",{}).get("diagnosis",0))>=2 and int(doctor.get("abilities",{}).get("treatment",0))>=1 and before_charge and finished and departed and _income(rounding,"ward")==60 and _income(rounding,"cure")==360 and _income(rounding)==505
	var failure: Dictionary = _failure_world("CLIN-24",rounding.world) if not passed else {}
	t.check("CLIN-24",passed,{"recovery_alone_did_not_settle":blocked_until_care,"waited_for_qualified_round":held,"care_ticks":care_ticks,"round_placement":placement,"round_start_input":round_input,"expected_round_ticks":expected_round_ticks,"round":round_session,"actual_departure":departed,"failure_world":failure,"state":_state(rounding)})

func _case_25(t) -> void:
	var transfer: Dictionary = _copy("ward_after_care")
	await _until(t,transfer,func()->bool: return not transfer.sim.clinic.staff_busy(transfer.world,str(_stay(transfer).nurse_id)) and not transfer.world.facts.moves.has(str(_stay(transfer).nurse_id)),180)
	var original_attempt: String = str(_stay(transfer).attempt_id)
	var original_bed: String = str(_stay(transfer).bed_id)
	var old_condition: float = float(transfer.world.facts.facilities[original_bed].condition)
	var old_remaining: int = int(_stay(transfer).remaining_ticks)
	var old_progress: int = int(_stay(transfer).last_progress_tick)
	var switched: CommandResult = _command(transfer,"clinical_transfer_bed",{"visit_id":transfer.visit_id,"bed_id":"clin_ward_1"})
	var preserved_immediately: bool = switched.accepted and int(_stay(transfer).remaining_ticks)==old_remaining and int(_stay(transfer).last_progress_tick)==old_progress and bool(_stay(transfer).care_completed)
	var arrived: bool = switched.accepted and await _until(t,transfer,func()->bool: return _stay(transfer).get("phase","")=="recovery",800)
	var no_transfer_work: bool = arrived and int(_stay(transfer).remaining_ticks)>=old_remaining-1
	await _until(t,transfer,func()->bool: return not transfer.sim.clinic.staff_busy(transfer.world,str(_stay(transfer).nurse_id)),200)
	var return_remaining: int = int(_stay(transfer).get("remaining_ticks",-1))
	var returned: CommandResult = _command(transfer,"clinical_transfer_bed",{"visit_id":transfer.visit_id,"bed_id":original_bed})
	var back: bool = returned.accepted and await _until(t,transfer,func()->bool: return _stay(transfer).get("phase","")=="recovery",800)
	t.check("CLIN-25",preserved_immediately and no_transfer_work and back and str(_stay(transfer).attempt_id)==original_attempt and bool(_stay(transfer).care_completed) and int(_stay(transfer).remaining_ticks)>=return_remaining-1 and is_equal_approx(float(transfer.world.facts.facilities[original_bed].condition),old_condition) and transfer.world.facts.facilities[original_bed].use_receipts.size()==1 and _units_used(transfer)==8 and _income(transfer,"ward")==0 and _income(transfer,"cure")==0,{"immediate_preservation":preserved_immediately,"no_work_while_transferring":no_transfer_work,"outward":switched.to_record(),"return":returned.to_record(),"state":_state(transfer)})

func _case_26(t) -> void:
	var fault: Dictionary = _copy("ward_after_care")
	fault.world.facts.facilities.erase("clin_ward_1")
	var bed_id: String = str(_stay(fault).bed_id)
	fault.world.facts.facilities[bed_id].failed = true
	var remaining: int = int(_stay(fault).remaining_ticks)
	var fault_origin: int = int(_stay(fault).last_progress_tick)
	var before_deadline: bool = await _until(t,fault,func()->bool: return fault.world.sim_tick>=fault_origin+1200,1300)
	var retained: bool = before_deadline and not _stay(fault).is_empty() and int(_stay(fault).get("remaining_ticks",-1))==remaining and _visit(fault).get("final_result","").is_empty() and _income(fault,"ward")==0
	var referred: bool = await _until(t,fault,func()->bool: return _visit(fault).get("final_result","")=="referred",700)
	t.check("CLIN-26",retained and referred and _stay(fault).is_empty() and _income(fault)==85 and _income(fault,"surgery")==60 and _income(fault,"ward")==0 and _income(fault,"cure")==0 and _units_used(fault)==8 and _visit(fault).attempt_ids.size()==1,{"held_until_fault_deadline":retained,"state":_state(fault)})

func _case_27(t) -> void:
	if not _require(t,["CLIN-27"],"ward_after_care"): return
	var shortage: Dictionary = _copy("ward_after_care")
	var initial_progress: int = int(_stay(shortage).last_progress_tick)
	_all_rest(shortage.world,"nurse")
	_all_rest(shortage.world,"doctor",true)
	var nurse_id: String = str(_stay(shortage).nurse_id)
	var off_shift: bool = await _until(t,shortage,func()->bool:
		if _stay(shortage).is_empty(): return false
		var nurse: Dictionary = shortage.world.facts.staff[nurse_id]
		if nurse.on_shift or shortage.world.facts.moves.has(nurse_id) or shortage.sim.clinic.staff_busy(shortage.world,nurse_id): return false
		for doctor_id: String in shortage.world.ids("staff"):
			var doctor: Dictionary = shortage.world.facts.staff[doctor_id]
			if doctor.role!="doctor" or int(doctor.abilities.diagnosis)<2 or int(doctor.abilities.treatment)<1: continue
			if doctor.on_shift or shortage.world.facts.moves.has(doctor_id) or shortage.sim.clinic.staff_busy(shortage.world,doctor_id): return false
		return true,600)
	if not off_shift:
		t.check("CLIN-27",false,{"missing":"actual_off_shift_after_safe_work_and_movement","initial_progress_tick":initial_progress,"state":_state(shortage)})
		return
	var shortage_tick: int = shortage.world.sim_tick
	var no_progress: int = int(_stay(shortage).last_progress_tick)
	# This completed boundary has processed 119.9 seconds, before the 120-second dispatch.
	await _until(t,shortage,func()->bool: return shortage.world.sim_tick>=no_progress+1200,1300)
	var early_reason: String = str(_visit(shortage).get("waiting_reason",""))
	var no_early_prompt: bool = _visit(shortage).get("final_result","").is_empty() and not early_reason.contains("排班") and not early_reason.contains("招聘") and int(_stay(shortage).get("last_progress_tick",-1))==no_progress
	await _steps(t,shortage,1)
	var reason: String = str(_visit(shortage).get("waiting_reason",""))
	var prompt: bool = _visit(shortage).get("final_result","").is_empty() and reason.contains("排班") and reason.contains("招聘") and int(_stay(shortage).get("last_progress_tick",-1))==no_progress
	_command(shortage,"clinical_visit_consent",{"visit_id":shortage.visit_id,"allow":true})
	_command(shortage,"clinical_visit_consent",{"visit_id":shortage.visit_id,"allow":false})
	shortage.sim.clinic.compare_plans(shortage.world,shortage.visit_id)
	var did_not_reset: bool = int(_stay(shortage).get("last_progress_tick",-1))==no_progress
	await _until(t,shortage,func()->bool: return shortage.world.sim_tick>no_progress+3000,1900)
	var safe_referral: bool = await _until(t,shortage,func()->bool: return _visit(shortage).get("final_result","")=="referred",700)
	t.check("CLIN-27",no_early_prompt and prompt and did_not_reset and safe_referral and _units_used(shortage)==8 and _visit(shortage).attempt_ids.size()==1 and _income(shortage,"ward")==0 and _income(shortage,"cure")==0,{"initial_progress_tick":initial_progress,"actual_shortage_boundary_tick":shortage_tick,"last_actual_progress_tick":no_progress,"no_prompt_at_119_9_seconds":no_early_prompt,"reason_before_120_seconds":early_reason,"prompt_at_120_seconds":prompt,"prompt_reason":reason,"no_reset_by_controls_or_queries":did_not_reset,"state":_state(shortage)})

func _case_28(t) -> void:
	var boundaries: Array = ["ward_entered","ward_care","ward_round_wait","ward_round","ward_settled"]
	var restored_all: bool = true
	var observations: Dictionary = {}
	for boundary: String in boundaries:
		if not _snapshots.has(boundary):
			restored_all = false
			observations[boundary] = "实际链路未到达此边界"
			continue
		var copy: Dictionary = _copy(boundary)
		var before: Dictionary = copy.world.freeze()
		var roundtrip: Dictionary = _roundtrip(copy)
		restored_all = restored_all and roundtrip.ok and copy.world.freeze()==before
		observations[boundary] = roundtrip
	var round_copy: Dictionary = _copy("ward_round")
	var original_round: Dictionary = _session(round_copy,"round").duplicate(true)
	var completed: bool = await _until(t,round_copy,func()->bool: return _visit(round_copy).get("final_result","")=="cured",180)
	var previous: Dictionary = round_copy.world.facts.ledger.entries.duplicate(true)
	round_copy.sim.clinic._complete_service(round_copy.world,original_round)
	HospitalLedger.settle(round_copy.world)
	var restored_end: Dictionary = _roundtrip(round_copy)
	t.check("CLIN-28",restored_all and completed and restored_end.ok and round_copy.world.facts.ledger.entries==previous and _income(round_copy,"ward")==60 and _income(round_copy,"cure")==360 and _units_used(round_copy)==8,{"boundaries":observations,"final_restore":restored_end,"state":_state(round_copy)})

func _case_29(t) -> void:
	var timing: RefCounted = ClinicalTiming.new()
	var clock: int = Time.get_ticks_usec()
	# Completed C-profile diagnostics are input. This case starts before choosing
	# the gentle plan and still executes its full work, transfer and recovery.
	var c: Dictionary = _copy("c_diagnosed")
	# This gentle-plan hospital needs a ward, not an unrelated operating team.
	# Keep the real completed diagnostic facts and add the legal nearby ward.
	_add_layout(c.world,"ward_two_beds","clin_ward",[42,72])
	_add_worker(c.world,"clin_cover","nurse",[43,79],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":0})
	c.world.facts.staff.clin_cover.ward_id = "clin_ward"
	_add_worker(c.world,"clin_round","doctor",[51,79],"round",{"diagnosis":2,"treatment":1,"care":0,"surgery":0})
	c.world.touch()
	c.sim._ensure_services()
	c.clinical_scenario = true
	_declare_call_ready(c,[c.visit_id])
	var input_validation: String = c.world.validate(_content)
	timing.finish("diagnosed_input",clock)
	if not input_validation.is_empty():
		t.check("CLIN-29",false,{"input_validation":input_validation,"timing":timing.report()})
		return
	clock = Time.get_ticks_usec()
	c.world.facts.staff[c.doctors[1]].abilities.treatment = 3
	_seed_stream(c.world,"treatment",true,true,9700,9800)
	var diagnosed: bool = _visit(c).get("phase","")=="wait_consult" and not _visit(c).evidence_by_source.is_empty()
	var coverage_at_selection: Dictionary = _ward_nurse_return_state(c)
	var coverage_wait: Dictionary = {"ok":bool(coverage_at_selection.ready),"reason":"ready_ward_input"}
	timing.finish("ward_coverage_input",clock)
	clock = Time.get_ticks_usec()
	var selected: CommandResult = _command(c,"clinical_select_plan",{"visit_id":c.visit_id,"plan_id":"P_D14_GENTLE"}) if diagnosed and coverage_wait.ok else CommandResult.new(false,"ward_coverage_missing",str(coverage_wait.reason))
	if not selected.accepted:
		t.check("CLIN-29",false,{"selection":selected.to_record(),"coverage_at_selection":coverage_at_selection,"state":_state(c),"timing":timing.report()})
		return
	var began: bool = selected.accepted and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="outpatient",800)
	var attempt: Dictionary = c.world.facts.attempts.values()[0].duplicate(true) if began else {}
	timing.finish("select_and_start_outpatient",clock)
	clock = Time.get_ticks_usec()
	var operated: bool = began and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="transfer",1300)
	timing.finish("actual_outpatient_work",clock)
	clock = Time.get_ticks_usec()
	var unrevealed: bool = operated and _income(c,"ward")==0 and _income(c,"cure")==0 and _visit(c).get("final_result","").is_empty()
	var recovery: Dictionary = {"previous":1800,"work_ticks":0,"advancing_steps":0}
	var completed: bool = operated and await _until(t,c,func()->bool:
		var stay: Dictionary = _stay(c)
		if not stay.is_empty():
			var remaining: int = int(stay.remaining_ticks)
			var delta: int = int(recovery.previous)-remaining
			if delta>0:
				recovery.work_ticks += delta
				recovery.advancing_steps += 1
			recovery.previous = remaining
		return _visit(c).get("final_result","")=="cured",3000)
	timing.finish("actual_transfer_recovery_and_round",clock)
	t.check("CLIN-29",unrevealed and completed and recovery.work_ticks==1800 and recovery.advancing_steps==1800 and int(attempt.get("recovery_ticks",-1))==1800 and int(attempt.get("supply_units",-1))==4 and int(attempt.get("cure_fee",-1))==660 and int(c.started.get("wake",0))==0 and _income(c,"outpatient")==10 and _income(c,"ward")==60 and _income(c,"cure")==660 and _income(c)==790 and _units_used(c)==4 and _visit(c).attempt_ids.size()==1,{"recovery":recovery,"diagnosed":diagnosed,"selected":selected.to_record(),"coverage_wait":coverage_wait,"coverage_at_selection":coverage_at_selection,"result_hidden_after_operation":unrevealed,"attempt":attempt,"state":_state(c),"timing":timing.report()})

func _case_30(t) -> void:
	await _companion_entry(t,true)

func _case_31(t) -> void:
	var visiting: Dictionary = await _visitor_bedside(t)
	var bedside: bool = bool(visiting.bedside_ready)
	var medical_priority: bool = true
	for observation: Dictionary in visiting.get("visitor_trace",[]):
		if observation.phase in ["to_bed","visiting"]:
			medical_priority = medical_priority and bool(observation.care_completed)
	var original: Dictionary = _visitor(visiting).duplicate(true)
	var window: String = str(original.get("started_window",""))
	var windows: Dictionary = _visit(visiting).get("visitor_windows",{}).duplicate(true)
	var arrival_rng: Dictionary = visiting.world.facts.rng.arrival.duplicate(true)
	var legal_point: bool = bedside and visiting.sim.space.at(visiting.world,str(original.actor_id),int(original.bedside_floor),original.bedside_cell)
	var real_clock: bool = bedside and int(original.remaining_ticks)+(visiting.world.sim_tick-int(original.started_tick))==300
	var restored: Dictionary = _roundtrip(visiting)
	await _steps(t,visiting,50)
	var once: bool = visiting.world.facts.rng.arrival==arrival_rng and _visit(visiting).get("visitor_windows",{})==windows and visiting.world.facts.visitors.stays.size()==1
	# A clinical transfer must first make the same visitor physically yield.
	var transfer: CommandResult = _command(visiting,"clinical_transfer_bed",{"visit_id":visiting.visit_id,"bed_id":"clin_ward_1"})
	if not transfer.accepted:
		await _until(t,visiting,func()->bool: return _visitor(visiting).get("phase","") in ["waiting","to_waiting","leaving"],350)
		transfer = _command(visiting,"clinical_transfer_bed",{"visit_id":visiting.visit_id,"bed_id":"clin_ward_1"})
	var transferred: bool = transfer.accepted and await _until(t,visiting,func()->bool: return _stay(visiting).get("phase","")=="recovery",800)
	t.check("CLIN-31",bedside and medical_priority and legal_point and real_clock and restored.ok and once and windows.get(window,{}).get("intent",false) and windows.get(window,{}).get("started",false) and transferred and _visit(visiting).get("visitor_windows",{})==windows and visiting.world.facts.rng.arrival==arrival_rng and str(_visit(visiting).get("relative_actor_id",""))==str(original.get("actor_id","")) and _income(visiting,"ward")==0 and _income(visiting,"cure")==0,{"initial_care_before_bedside":medical_priority,"actual_bedside_before_timer":legal_point,"exact_30_second_timer":real_clock,"single_intent_after_restore":once,"transfer":transfer.to_record(),"restore":restored,"visitor_trace":visiting.get("visitor_trace",[]),"failure_world":visiting.get("failure_world",{}),"state":_state(visiting)})

func _case_32(t) -> void:
	var missing: Array = []
	for key: String in ["visitor_visiting","ward_entered","companion_entered"]:
		if not _snapshots.has(key): missing.append(key)
	if not missing.is_empty():
		t.check("CLIN-32",false,{"missing_real_business_boundaries":missing})
		return
	var yielding: Dictionary = _copy("visitor_visiting")
	var before_visitor: Dictionary = _visitor(yielding).duplicate(true)
	var cleared: bool = yielding.sim.clinic.visitors.yield_for_care(yielding.world,yielding.visit_id)
	var began_yielding: bool = not cleared and _visitor(yielding).get("phase","")=="yielding" and yielding.world.facts.moves.has(str(before_visitor.actor_id)) and int(_visitor(yielding).get("remaining_ticks",-1))==int(before_visitor.remaining_ticks)
	await _steps(t,yielding,1)
	var same_timer: bool = int(_visitor(yielding).get("remaining_ticks",-1))<=int(before_visitor.remaining_ticks) and _visitor(yielding).get("started_tick",-1)==before_visitor.started_tick
	var refusing: Dictionary = _copy("visitor_visiting")
	var before_anger: float = float(_visit(refusing).anger)
	var before_income: int = _income(refusing)
	var original_relative: String = str(_visitor(refusing).actor_id)
	var consent: CommandResult = _command(refusing,"clinical_visit_consent",{"visit_id":refusing.visit_id,"allow":false})
	refusing.sim.clinic.visitors.dispatch(refusing.world)
	var retained_until_exit: bool = consent.accepted and not _visitor(refusing).is_empty() and refusing.world.facts.actors[original_relative].location.kind=="floor" and _visitor(refusing).get("phase","")=="leaving" and is_equal_approx(float(_visit(refusing).anger),before_anger) and _income(refusing)==before_income
	var body_observation: Dictionary = {"retained":retained_until_exit,"floor_ticks":0,"body_blocks_space":true}
	var outside_after_walk: bool = await _until(t,refusing,func()->bool:
		var relative: Dictionary = refusing.world.facts.actors.get(original_relative,{})
		if relative.is_empty():
			body_observation.retained = false
			return false
		if relative.location.kind=="floor":
			body_observation.floor_ticks += 1
			body_observation.retained = body_observation.retained and not _visitor(refusing).is_empty()
			# Ignore every other actor to query this visitor's own real body/sweep.
			var ignored: Array = refusing.world.ids("actors")
			ignored.erase(original_relative)
			body_observation.body_blocks_space = body_observation.body_blocks_space and not refusing.sim.space._dynamic_clear(refusing.world,"clinical_visitor_exit_probe",int(relative.location.floor_id),refusing.sim.space.body_rectangle(relative),ignored)
		return relative.location.kind=="outside" and _visitor(refusing).is_empty(),900)
	var pending: Dictionary = _copy("ward_entered")
	_remove_waiting_chairs(pending.world)
	_command(pending,"clinical_visit_consent",{"visit_id":pending.visit_id,"allow":true})
	_seed_stream(pending.world,"arrival",true,false,5000,5000)
	var had_request: bool = await _until(t,pending,func()->bool: return not pending.world.facts.visitors.requests.is_empty(),100)
	_command(pending,"clinical_visit_consent",{"visit_id":pending.visit_id,"allow":false})
	await _steps(t,pending,50)
	var cancelled_request: bool = had_request and pending.world.facts.visitors.requests.is_empty() and pending.world.facts.visitors.stays.is_empty()
	var leaving: Dictionary = _copy("companion_entered")
	var relative_id: String = str(_visitor(leaving).actor_id)
	var safe_boundary: bool = await _until(t,leaving,func()->bool: return str(_visit(leaving).get("phase","")).begins_with("wait_") and leaving.world.facts.sessions.is_empty(),1000)
	var referred: CommandResult = _command(leaving,"clinical_refer",{"visit_id":leaving.visit_id}) if safe_boundary else CommandResult.new(false,"safe_boundary_missing")
	var family_departed: bool = referred.accepted and await _until(t,leaving,func()->bool: return leaving.world.facts.actors[relative_id].location.kind=="outside" and _visitor(leaving).is_empty(),900)
	t.check("CLIN-32",began_yielding and same_timer and retained_until_exit and body_observation.retained and int(body_observation.floor_ticks)>0 and body_observation.body_blocks_space and outside_after_walk and cancelled_request and family_departed,{"responded_to_clinical_yield":began_yielding,"original_timer_preserved":same_timer,"consent_command":consent.to_record(),"body_retained_until_exit":retained_until_exit and body_observation.retained,"exit_body_observation":body_observation,"outside_after_walk":outside_after_walk,"pending_request_cancelled":cancelled_request,"family_left_after_patient_referral":family_departed,"state":_state(yielding)})

func _diagnosis_chain(t, upgraded: bool) -> void:
	var id: String = "CLIN-04" if upgraded else "CLIN-03"
	var c: Dictionary = await _diagnosis_state(t,upgraded)
	var third: bool = c.diagnosis_trace.third
	var gp_evidence: float = c.diagnosis_trace.gp
	var after_spectrum: float = c.diagnosis_trace.after_spectrum
	var total: float = c.diagnosis_trace.total
	if upgraded:
		t.check(id,third and is_equal_approx(gp_evidence,49.2) and is_equal_approx(after_spectrum,93.0) and not _visit(c).evidence_by_source.has("resonance") and int(c.started.get("resonance",0))==0 and _income(c,"resonance")==0 and _income(c)==40 and _units_used(c)==0 and _visit(c).phase=="wait_consult",{"gp":gp_evidence,"after_spectrum":after_spectrum,"income":_income(c),"state":_state(c)})
	else:
		t.check(id,third and is_equal_approx(gp_evidence,42.0) and is_equal_approx(after_spectrum,77.0) and is_equal_approx(total,102.0) and int(c.started.get("spectrum",0))==1 and int(c.started.get("resonance",0))==1 and _units_used(c)==0 and _income(c)==60 and _visit(c).phase=="wait_consult",{"gp":gp_evidence,"after_spectrum":after_spectrum,"total":total,"income":_income(c),"state":_state(c)})
