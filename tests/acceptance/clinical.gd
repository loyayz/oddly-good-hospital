extends "res://tests/acceptance/clinical_fixtures.gd"

const ClinicalTiming = preload("res://tests/acceptance/clinical_timing.gd")

const CASES: Dictionary = {
	"CLIN-01":"docs/design/12-implementation-plan.md §10.1–10.2；入院直接导诊后医生接诊，Actor/Visit只建一次",
	"CLIN-02":"docs/design/07-clinical-team.md §9、§14、§17；诊断池与治疗池由不同实际医生安全交接，D09首试成功实收235",
	"CLIN-05":"docs/design/07-clinical-team.md §14；初诊按开工职称冻结，重复完成不重收25",
	"CLIN-06":"docs/design/01-simulation.md §4；临床§6、§16；报价只读，常规/舒缓从同一未取整工时分别最终ceil一次",
	"CLIN-07":"统一规格§15.1；C档治疗资格仍受限，舒缓不再要求住院研究、床或护理",
	"CLIN-08":"docs/design/04-technical.md §6、§10；缺包不消费，补货按原票开工且不另扣采购现金",
	"CLIN-09":"docs/design/07-clinical-team.md §15；首败自动接第二次，重试+15个百分点夹98%，初诊不重收",
	"CLIN-10":"docs/design/07-clinical-team.md §14–15、§17；D09两次失败实收45、领2包、无第三次",
	"CLIN-11":"统一规格§15.1；手选舒缓在短缺中保留，首败后医生自动选第二方案",
	"CLIN-12":"docs/design/01-simulation.md §1、§4；暂停与流式恢复保留Attempt、余量、随机流、费用和领包",
	"CLIN-13":"docs/design/07-clinical-team.md §14；D09舒缓治愈费220、D14手术1080，快照不随后改重算",
	"CLIN-14":"docs/design/07-clinical-team.md §5、§8；三位互异术组及另一位病区覆盖护士缺一不可",
	"CLIN-15":"统一规格§15.2；已住院原床保留，准备原子预留8包与术组，开术前不领包、不计尝试",
	"CLIN-16":"统一规格§15.2；真实到齐后30秒准备窗口，过期释放术组与材料预约并安全回原床",
	"CLIN-17":"统一规格§15.2；住院原床不能被第二位患者或术室准备重复承诺",
	"CLIN-18":"docs/design/07-clinical-team.md §5、§8；开术冻结结果/120秒/180秒及四段15/45/25/15，恢复不重领",
	"CLIN-19":"docs/design/07-clinical-team.md §8、§14；术毕仍须15秒苏醒，完成才收60且不提前治愈",
	"CLIN-20":"docs/design/07-clinical-team.md §8；手术护士真实陪同转床，同Attempt交接床承诺",
	"CLIN-21":"docs/design/07-clinical-team.md §8；术中待故障安全完成，原结果/工时/领包不变",
	"CLIN-22":"docs/design/07-clinical-team.md §8.1；实际病房覆盖才推进，缺员/故障/暂停为0",
	"CLIN-23":"docs/design/07-clinical-team.md §8.1；同床双护士不加倍，每人不同时做两项主动护理",
	"CLIN-24":"docs/design/07-clinical-team.md §8.1、§14；真实护理与完整恢复后直接收床费/治愈费，无查房等待",
	"CLIN-25":"docs/design/07-clinical-team.md §8.1、§10；安全换床保留标准余量/护理，回原床不重复磨损/收费",
	"CLIN-26":"docs/design/07-clinical-team.md §8；床故障无备用120秒安全转诊，只保留已完成术台60",
	"CLIN-27":"docs/design/07-clinical-team.md §8.1；缺员120秒提示/300秒转诊，改派走路不重置无进展",
	"CLIN-28":"docs/design/07-clinical-team.md §10、§14；真实入床/护理/恢复/结算边界冷恢复并唯一收费",
	"CLIN-33":"docs/design/01-simulation.md §3、07-clinical-team.md §1、§6；接待/初诊到齐预约独占职员，原票接续，床通行权限不冒充工作，路线失败不占资源",
	"CLIN-34":"docs/design/07-clinical-team.md §6；指定医生与无指定均按原序选择首个完整可用报价，失败继续搜索；结构/实际限制及完整事实随机流不变",
	"CLIN-37":"docs/design/07-clinical-team.md §8.1；护理后真实离位保留床边缓冲、占位与原班表，旧目标受阻可安全改选，恢复不提前释放",
	"CLIN-36":"docs/design/01-simulation.md §3、07-clinical-team.md §1、§6；接待/初诊有效预约保持，失效换台不遗留旧票；转诊后真实安全离岗并释放空间",
	"CLIN-35":"docs/design/07-clinical-team.md §6；推荐与短缺查询批次复用保留全部合法方案、顺序与只读事实",
	"CLIN-38":"统一规格§15.2；床位预留仍计门诊，真实入床才扣除，缺术组不触发普通弃候"
}

const PREREQUISITES: Dictionary = {
	"CLIN-37": ["ward_after_care"],
	"CLIN-38": ["surgery_queue"],
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
		"surgery_setup"
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
		"ward_after_care",
		"ward_before_settlement",
		"ward_settled"
	],
}

func run(t) -> void:
	_content = HospitalContent.new()
	_cache = t.checkpoints(_content,"res://tests/acceptance/clinical_fixtures.gd",self)
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

func _case_33(t) -> void:
	load("res://tests/acceptance/clinical_gathering.gd").new().run_case(t,_content)

func _case_34(t) -> void:
	load("res://tests/acceptance/clinical_selected_doctor.gd").new().run_case(t,_content)

func _validate_rule_input(c: Dictionary, case_id: String, kind: String) -> String:
	c.world.touch()
	c.sim._ensure_services()
	var validation: String = c.world.validate(_content)
	print("CASE_INPUT "+case_id+" "+JSON.stringify({"kind":kind,"tick":c.world.sim_tick,"validation":validation}))
	return validation

func _case_35(t) -> void:
	preload("res://tests/acceptance/clinical_repeated_work.gd").new().run_case(t,_content)

func _case_01(t) -> void:
	var c: Dictionary = _context()
	_seed_stream(c.world,"treatment",false,true,4000,9200)
	var arrived: bool = _arrive(c)
	var duplicate: CommandResult = CommandResult.new(false,"not_checked")
	var request: Dictionary = {"arrival_key":_visit(c).get("arrival_key",""),"binding_id":"B_S13_D09_M09","requested_plan_id":"P_D09_COMMON","personality_id":"PP01"}
	duplicate = _command(c,"clinical_arrive",request)
	var guided: bool = arrived and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="gp")
	var guidance: Dictionary = c.world.facts.floor_guidance.visits.get(_visit(c).id,{})
	t.check("CLIN-01",guided and duplicate.accepted and c.world.facts.visits.size()==1 and c.world.facts.arrival_receipts.size()==1 and c.world.facts.actors.size()==c.world.facts.staff.size()+1 and guidance.get("receipts",[]).size()==1 and not _visit(c).has("registration_receipt") and c.world.facts.attempts.is_empty() and _income(c)==0 and _units_used(c)==0,_state(c))

func _case_02(t) -> void:
	# This is the ordinary outpatient integration case. Its actual GP and
	# treatment handoff run together; quote/boundary cases use checkpoints.
	var c: Dictionary = _context()
	_seed_stream(c.world,"treatment",false,true,4000,9200)
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

func _case_05(t) -> void:
	if not _require(t,["CLIN-05"],"gp_started"): return
	var frozen: Dictionary = _copy("gp_started")
	var original: Dictionary = _session(frozen,"gp").duplicate(true)
	var doctor_id: String = str(original.get("staff_ids",[""])[0])
	if frozen.world.facts.staff.has(doctor_id): frozen.world.facts.staff[doctor_id].title_id = "DT04"
	frozen.world.facts.facilities[original.facility_id].grade = 2
	var completed: bool = await _until(t,frozen,func()->bool: return _visit(frozen).get("diagnosis",{}).get("gp_completed",false))
	var paid: int = _income(frozen)
	# Late completion delivery goes through the existing Session identity guard.
	frozen.sim.clinic._complete_service(frozen.world,original)
	HospitalLedger.settle(frozen.world)
	t.check("CLIN-05",completed and int(original.get("doctor_fee",-1))==20 and paid==25 and _income(frozen)==25 and _visit(frozen).diagnosis.gp_completed,{"quoted":original,"income":_income(frozen),"state":_state(frozen)})

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
	var c: Dictionary=_copy("c_diagnosed")
	for staff: Dictionary in c.world.facts.staff.values():
		if staff.role=="doctor": staff.abilities.treatment=1
	c.world.touch()
	var too_low: Dictionary=c.sim.clinic.plan_quote(c.world,c.visit_id,"P_D14_COMMON")
	for staff: Dictionary in c.world.facts.staff.values():
		if staff.role=="doctor": staff.abilities.treatment=3
	c.world.facts.research.erase("R33")
	c.world.touch()
	var gentle: Dictionary=c.sim.clinic.plan_quote(c.world,c.visit_id,"P_D14_GENTLE")
	var required: Array=_content.definition("treatment_plans","P_D14_GENTLE").requires_research
	var other_research_guard: bool=true
	if not required.is_empty():
		var original: Array=c.world.facts.research.duplicate()
		c.world.facts.research.erase(required[0])
		c.world.touch()
		other_research_guard=not c.sim.clinic.plan_quote(c.world,c.visit_id,"P_D14_GENTLE").ok
		c.world.facts.research=original
		c.world.touch()
	var selected: CommandResult=_command(c,"clinical_select_plan",{"visit_id":c.visit_id,"plan_id":"P_D14_GENTLE"})
	t.check("CLIN-07",not too_low.get("ok",true) and gentle.get("ok",false) and int(gentle.get("recovery_ticks",-1))==0 and not gentle.has("bed_id") and selected.accepted and other_research_guard and c.world.facts.ward_stays.is_empty() and c.world.facts.attempts.is_empty() and _units_used(c)==0,{"ability":too_low,"gentle_without_R33_bed_or_nurse":gentle,"other_research_preserved":other_research_guard,"command":selected.to_record()})

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
	# Doctor ownership exercises automatic plan selection after failure.
	_visit(retry).plan_decision.source = "doctor"
	var twice: bool = await _until(t,retry,func()->bool: return _visit(retry).attempt_ids.size()==2,2600)
	var ids: Array = _visit(retry).attempt_ids
	var first: Dictionary = retry.world.facts.attempts.get(ids[0],{}) if ids.size()>0 else {}
	var second: Dictionary = retry.world.facts.attempts.get(ids[1],{}) if ids.size()>1 else {}
	t.check("CLIN-09",twice and not first.get("result",true) and second.get("result",false) and int(second.get("probability_bp",-1))==9800 and _units_used(retry)==2 and _income(retry,"consultation")==20 and _income(retry,"gp")==5 and int(retry.started.get("consult",0))==0,{"first":first,"second":second,"state":_state(retry)})

func _case_10(t) -> void:
	var failed: Dictionary = _copy("outpatient_queue")
	_seed_stream(failed.world,"treatment",false,false,9200,9800)
	var departed: bool = await _until(t,failed,func()->bool: return _visit(failed).get("phase","")=="departed",2600)
	var at_end: Dictionary = failed.world.facts.ledger.entries.duplicate(true)
	await _steps(t,failed,5)
	t.check("CLIN-10",departed and _visit(failed).attempt_ids.size()==2 and _visit(failed).get("final_result","")=="referred" and _income(failed)==45 and _income(failed,"cure")==0 and _units_used(failed)==2 and failed.world.facts.ledger.entries==at_end,{"income":_income(failed),"used":_units_used(failed),"state":_state(failed)})

func _case_11(t) -> void:
	var manual: Dictionary=_copy("outpatient_queue")
	var selected: CommandResult=_command(manual,"clinical_select_plan",{"visit_id":manual.visit_id,"plan_id":"P_D09_GENTLE"})
	var quote: Dictionary=manual.sim.clinic.plan_quote(manual.world,manual.visit_id,"P_D09_GENTLE")
	_seed_stream(manual.world,"treatment",false,true,int(quote.get("probability_bp",9800)),9800)
	manual.world.facts.inventory.units=0
	var ticket: String=str(_visit(manual).ticket_id)
	var revision: int=int(_visit(manual).plan_decision.get("revision",-1))
	await _steps(t,manual,20)
	var preserved: bool=_visit(manual).plan_decision.get("plan_id","")=="P_D09_GENTLE" and _visit(manual).ticket_id==ticket and int(_visit(manual).plan_decision.get("revision",-2))==revision and manual.world.facts.preparations.is_empty()
	var purchase: CommandResult=_command(manual,"purchase_supplies",{"units":4,"order_id":"clinical_manual_supply"})
	var repeated: bool=purchase.accepted and await _until(t,manual,func()->bool:return _visit(manual).attempt_ids.size()==2,2800)
	var ids: Array=_visit(manual).attempt_ids
	var first: Dictionary=manual.world.facts.attempts.get(str(ids[0]),{}) if ids.size()>0 else {}
	var second: Dictionary=manual.world.facts.attempts.get(str(ids[1]),{}) if ids.size()>1 else {}
	var legal_second: bool=not second.is_empty() and _content.definition("treatment_plans",str(second.plan_id)).disease_id=="D09" and _visit(manual).plan_decision.get("source","")=="doctor"
	t.check("CLIN-11",selected.accepted and preserved and repeated and first.get("plan_id","")=="P_D09_GENTLE" and not first.get("result",true) and legal_second and int(manual.started.get("gp",0))==1 and int(manual.started.get("consult",0))==0 and _units_used(manual)==int(first.get("supply_units",0))+int(second.get("supply_units",0)),{"preserved_during_shortage":preserved,"automatic_second_plan":legal_second,"first":first,"second":second,"state":_state(manual)})

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
	t.check("CLIN-15",supply_boundary and prepared and int(preparation.get("supply_units",-1))==8 and int(preparation.get("setup_remaining_ticks",-1))==80 and int(preparation.get("deadline_tick",0))==-1 and preparation.get("staff_ids",[]).size()==3 and not str(preparation.get("bed_id","")).is_empty() and c.sim.services.supplies.reserved(c.world)==8 and c.world.facts.attempts.is_empty() and _units_used(c)==0 and int(c.world.facts.inventory.units)==60 and _income(c)==25 and int(c.world.facts.staff.clin_or_nurse.practice.surgery)==0,{"supply_boundary":supply_boundary,"short_requests":short_requests,"enough_requests":enough_requests,"preparation":preparation,"state":_state(c),"timing":timing.report()})

func _case_16(t) -> void:
	var timing: RefCounted = ClinicalTiming.new()
	var clock: int = Time.get_ticks_usec()
	var cancel: Dictionary = _copy("surgery_setup")
	var expiry: Dictionary = _copy("surgery_setup")
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
	var race: Dictionary=_copy("surgery_queue")
	var stay_id: String=str(_stay(race).id)
	var bed_id: String=str(_stay(race).bed_id)
	for id: String in race.world.facility_ids("EQ05").duplicate():
		if id!=bed_id: race.world.facts.facilities.erase(id)
	var second_id: String=_waiting_case(race,[49,94])
	race.world.touch()
	var original: Dictionary=_stay(race).duplicate(true)
	var later: Dictionary=race.world.facts.visits[second_id]
	var original_ticket: Dictionary=race.world.facts.tickets[later.ticket_id].duplicate(true)
	var before: Dictionary=race.world.freeze()
	var quote: Dictionary=race.sim.clinic._compatible_bed(race.world,later,1,[])
	var read_only: bool=not quote.ok and before==race.world.freeze()
	var validation: String=race.world.validate(_content)
	await _steps(t,race,1)
	var stays: Array=[]
	for stay: Dictionary in race.world.facts.ward_stays.values():
		if stay.bed_id==bed_id: stays.append(stay.id)
	t.check("CLIN-17",validation.is_empty() and race.world.validate(_content).is_empty() and read_only and stays==[stay_id] and _stay(race).visit_id==original.visit_id and not HospitalClinic.Flow.ward_stay(race.world,second_id).has("admitted_tick") and later.ticket_id==original_ticket.id and race.world.facts.tickets[later.ticket_id].enqueued_tick==original_ticket.enqueued_tick and _units_used(race)==0 and race.world.facts.attempts.is_empty(),{"checks":{"bed_owner_unchanged":stays==[stay_id],"second_not_admitted":HospitalClinic.Flow.ward_stay(race.world,second_id).is_empty(),"quote_read_only":read_only},"input_validation":validation,"later_bed_quote":quote,"state":_state(race)})

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
	if not _require(t,["CLIN-24"],"ward_care"): return
	var c: Dictionary = _copy("ward_care")
	var care_input: Dictionary = _session(c,"care").duplicate(true)
	var initial_remaining: int = int(_stay(c).remaining_ticks)
	var initial_tick: int = c.world.sim_tick
	# The former round doctor remains a real worker, now on a legal rest
	# schedule. No qualified doctor visit is required for discharge.
	_all_rest(c.world,"doctor",true)
	var observed: Dictionary = {"valid":true,"no_early_charges":true,"no_round":true,"care_completed_with_recovery_left":false,"recovery_work_ticks":0,"previous":initial_remaining,"care_at_bedside":true}
	var finished: bool = await _until(t,c,func()->bool:
		var error: String = c.world.validate(_content)
		if not error.is_empty(): observed.valid = false; c.errors.append({"validation":error}); return true
		var stay: Dictionary = _stay(c)
		if not stay.is_empty():
			var remaining: int = int(stay.remaining_ticks)
			observed.recovery_work_ticks += maxi(0,int(observed.previous)-remaining)
			observed.previous = remaining
			if remaining>0 or not stay.care_completed: observed.no_early_charges = observed.no_early_charges and _income(c,"ward")==0 and _income(c,"cure")==0
			if remaining>0 and stay.care_completed: observed.care_completed_with_recovery_left = true
		var care: Dictionary = _session(c,"care")
		if not care.is_empty():
			var bed: Dictionary = c.sim.space.facility_layout(c.world,care.facility_id)
			observed.care_at_bedside = observed.care_at_bedside and c.sim.space.at(c.world,str(care.staff_ids[0]),int(bed.floor_id),bed.operator_cells[0])
		observed.no_round = observed.no_round and _session(c,"round").is_empty() and int(c.started.get("round",0))==0
		return _visit(c).get("final_result","")=="cured",2500)
	var departed: bool = finished and await _until(t,c,func()->bool:return _visit(c).phase=="departed",900)
	var no_round_doctor: bool = true
	for staff: Dictionary in c.world.facts.staff.values():
		if staff.role=="doctor" and staff.on_shift and int(staff.abilities.diagnosis)>=2 and int(staff.abilities.treatment)>=1: no_round_doctor = false
	var passed: bool = observed.valid and observed.no_early_charges and observed.no_round and observed.care_completed_with_recovery_left and observed.care_at_bedside and int(care_input.get("total_ticks",-1))==80 and int(observed.recovery_work_ticks)==initial_remaining and no_round_doctor and departed and c.world.validate(_content).is_empty() and _income(c,"ward")==60 and _income(c,"cure")==360 and _income(c)==505 and _units_used(c)==8
	t.check("CLIN-24",passed,{"observed":observed,"initial_tick":initial_tick,"final_tick":c.world.sim_tick,"care_session":care_input,"remaining_recovery_at_input":initial_remaining,"recovery_progress_in_real_prefix":1800-initial_remaining,"doctor_visit_not_required":no_round_doctor,"actual_departure":departed,"income":_income(c),"failure_world":_failure_world("CLIN-24",c.world) if not passed else {}})

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
	var projection: Dictionary = {"initial":transfer.sim.space.overlaps_facility(transfer.world,_visit(transfer).actor_id,original_bed),"exit":false,"freed":false}
	var initial_cell: Array = transfer.world.facts.actors[_visit(transfer).actor_id].location.cell.duplicate()
	var arrived: bool = switched.accepted and await _until(t,transfer,func()->bool:
		if not projection.exit and transfer.world.facts.actors[_visit(transfer).actor_id].location.cell!=initial_cell and transfer.sim.space.overlaps_facility(transfer.world,_visit(transfer).actor_id,original_bed):
			projection.exit = transfer.sim.space.overlaps_facility(transfer.world,_visit(transfer).actor_id,original_bed)
		if not projection.freed and _stay(transfer).get("phase","")=="transfer" and not transfer.sim.space.overlaps_facility(transfer.world,_visit(transfer).actor_id,original_bed):
			projection.freed = not transfer.sim.space.overlaps_facility(transfer.world,_visit(transfer).actor_id,original_bed)
		return _stay(transfer).get("phase","")=="recovery",800)
	projection.released = arrived and not _stay(transfer).has("transfer_from_bed_id")
	var no_transfer_work: bool = arrived and int(_stay(transfer).remaining_ticks)>=old_remaining-1
	await _until(t,transfer,func()->bool: return not transfer.sim.clinic.staff_busy(transfer.world,str(_stay(transfer).nurse_id)),200)
	var return_remaining: int = int(_stay(transfer).get("remaining_ticks",-1))
	var returned: CommandResult = _command(transfer,"clinical_transfer_bed",{"visit_id":transfer.visit_id,"bed_id":original_bed})
	var back: bool = returned.accepted and await _until(t,transfer,func()->bool: return _stay(transfer).get("phase","")=="recovery",800)
	t.check("CLIN-25",projection.initial and projection.exit and projection.freed and projection.released and preserved_immediately and no_transfer_work and back and str(_stay(transfer).attempt_id)==original_attempt and bool(_stay(transfer).care_completed) and int(_stay(transfer).remaining_ticks)>=return_remaining-1 and is_equal_approx(float(transfer.world.facts.facilities[original_bed].condition),old_condition) and transfer.world.facts.facilities[original_bed].use_receipts.size()==1 and _units_used(transfer)==8 and _income(transfer,"ward")==0 and _income(transfer,"cure")==0,{"projection":projection,"immediate_preservation":preserved_immediately,"no_work_while_transferring":no_transfer_work,"outward":switched.to_record(),"return":returned.to_record(),"state":_state(transfer)})

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
		t.check("CLIN-27",false,{"missing":"actual_off_shift_after_safe_work_and_movement","initial_progress_tick":initial_progress,"state":_state(shortage),"failure_world":_failure_world("CLIN-27",shortage.world)})
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
	var boundaries: Array = ["ward_entered","ward_care","ward_after_care","ward_before_settlement","ward_settled"]
	var restored_all: bool = true
	var observations: Dictionary = {}
	for boundary: String in boundaries:
		if not _snapshots.has(boundary): restored_all = false; observations[boundary] = "缺少真实生成的边界"; continue
		var c: Dictionary = _copy(boundary)
		var before: Dictionary = c.world.freeze()
		var restored: Dictionary = _roundtrip(c)
		restored_all = restored_all and restored.ok and c.world.freeze()==before
		observations[boundary] = {"restore":restored,"tick":c.world.sim_tick,"stay":_stay(c).duplicate(true),"income":_income(c)}
	var final: Dictionary = _copy("ward_before_settlement")
	var real_completed_care: Dictionary = {}
	for session: Dictionary in _snapshots.ward_care.facts.sessions.values():
		if session.kind=="care": real_completed_care = session.duplicate(true)
	var completed: bool = await _until(t,final,func()->bool:return _visit(final).get("final_result","")=="cured",20)
	var positive_before: Dictionary = _positive_entries(final)
	# A duplicate delivery uses the identity of the care session that actually
	# completed in the shared prefix; the production session guard owns it.
	final.sim.clinic._complete_service(final.world,real_completed_care)
	HospitalLedger.settle(final.world)
	var after_repeated_delivery: bool = _positive_entries(final)==positive_before
	var restored_end: Dictionary = _roundtrip(final)
	var departed: bool = completed and restored_end.ok and await _until(t,final,func()->bool:return _visit(final).phase=="departed",900)
	var passed: bool = restored_all and completed and after_repeated_delivery and restored_end.ok and departed and _positive_entries(final)==positive_before and int(final.started.get("round",0))==0 and _income(final,"ward")==60 and _income(final,"cure")==360 and _income(final)==505 and _units_used(final)==8 and final.world.validate(_content).is_empty()
	t.check("CLIN-28",passed,{"boundaries":observations,"late_real_care_delivery_unchanged":after_repeated_delivery,"final_restore":restored_end,"actual_departure":departed,"positive_entries":positive_before,"final_tick":final.world.sim_tick,"supply_units":_units_used(final),"failure_world":_failure_world("CLIN-28",final.world) if not passed else {}})

func _positive_entries(c: Dictionary) -> Dictionary:
	var entries: Dictionary = {}
	for key: String in c.world.facts.ledger.entries:
		var entry: Dictionary = c.world.facts.ledger.entries[key]
		if int(entry.amount)>0: entries[key] = entry.duplicate(true)
	return entries

func _case_36(t) -> void:
	preload("res://tests/acceptance/clinical_handoff.gd").new().run_case(t,_content)

func _case_37(t) -> void:
	await preload("res://tests/acceptance/clinical_ward_release.gd").new().run_case(t,self)

func _case_38(t) -> void:
	var c: Dictionary=_copy("surgery_queue")
	var source: Dictionary=c.get("before_bed_arrival",{})
	var checks: Dictionary={"real_reserved_bed_source":not source.is_empty()}
	if source.is_empty():
		t.check("CLIN-38",false,{"checks":checks,"state":_state(c)})
		return
	# This is the first reservation reached by the real diagnosis/admission
	# prefix. Its actual pending walk resumes in fresh simulation services.
	c.world=WorldState.new(source.facts.duplicate(true))
	c.sim=HospitalSimulation.new(c.world,_content)
	_simulations.append(c.sim)
	var visit: Dictionary=_visit(c)
	var stay: Dictionary=_stay(c)
	var stay_id: String=str(stay.id)
	var bed_id: String=str(stay.bed_id)
	var original_ticket: String=str(visit.ticket_id)
	var initial_location: Dictionary=c.world.facts.actors[visit.actor_id].location.duplicate(true)
	var bed: Dictionary=c.sim.space.facility_layout(c.world,bed_id)
	var arrivals: HospitalArrivalService=c.sim.services.arrivals
	var reserved_count: int=arrivals.outpatient_count(c.world)
	checks.reserved_not_admitted=stay.phase=="admitting" and not stay.has("admitted_tick") and not c.sim.space.at(c.world,visit.actor_id,int(bed.floor_id),bed.patient_cell)
	checks.reserved_still_outpatient=reserved_count==1
	checks.seat_released_for_bed=not c.world.facts.waiting_life.seats.has(visit.id)
	# This legal shift change removes only the future OR team member. It does
	# not remove the bed, coverage nurse, patient, or any admission work.
	c.world.facts.staff.clin_anesthesia.schedule=_schedule("rest")
	c.world.touch()
	var input_validation: String=c.world.validate(_content)
	checks.input_valid=input_validation.is_empty()
	var counted_until_admission: bool=true
	var moved: bool=false
	var admitted: bool=false
	var pre_support_walk: Dictionary={}
	for index: int in 900:
		if c.sim.space.at(c.world,visit.actor_id,int(bed.floor_id),bed.patient_cell) and not c.world.facts.moves.has(visit.actor_id):
			pre_support_walk={"tick":c.world.sim_tick,"location":c.world.facts.actors[visit.actor_id].location.duplicate(true),"target":bed.patient_cell.duplicate(),"move_empty":true}
		_tick(c)
		stay=_stay(c)
		moved=moved or c.world.facts.actors[visit.actor_id].location!=initial_location
		if stay.has("admitted_tick"):
			admitted=true
			break
		counted_until_admission=counted_until_admission and arrivals.outpatient_count(c.world)==1 and visit.ticket_id==original_ticket
		if index%100==99: await t.process_frame
	var supported_actor: Dictionary=c.world.facts.actors[visit.actor_id]
	var post_support_location: Dictionary={"actual":supported_actor.location.duplicate(true),"expected":c.sim.space.support_location(c.world,supported_actor,bed)}
	checks.pre_support_walk=admitted and moved and not pre_support_walk.is_empty()
	checks.post_support_location=admitted and supported_actor.get("posture","")=="lying" and supported_actor.get("support_facility_id","")==bed_id and supported_actor.location==post_support_location.expected and not c.world.facts.moves.has(visit.actor_id)
	checks.actual_walk_to_original_bed=checks.pre_support_walk and checks.post_support_location and stay.get("id","")==stay_id and stay.get("bed_id","")==bed_id
	var admitted_count: int=arrivals.outpatient_count(c.world)
	checks.count_changes_only_at_admission=counted_until_admission and admitted and admitted_count==0
	if admitted:
		var ticket_id: String=str(visit.ticket_id)
		var admitted_tick: int=int(stay.admitted_tick)
		var first_check: int=roundi(float(_content.balance.wait_departure.first_check_seconds)/WorldState.TICK_SECONDS)
		var income: int=_income(c)
		var used_units: int=_units_used(c)
		# A value below even the minimum departure probability would leave an
		# eligible ordinary waiter at its first real 120-second check.
		_seed_stream(c.world,"patience",true,true,100,10000)
		var patience: Dictionary=c.world.facts.rng.patience.duplicate(true)
		var initial_wait_tick: int=c.world.sim_tick
		await _steps(t,c,first_check+1)
		stay=_stay(c)
		checks.real_wait_past_patience_threshold=c.world.sim_tick-initial_wait_tick==first_check+1
		checks.or_member_actually_unavailable=not c.world.facts.staff.clin_anesthesia.on_shift
		checks.waiting_in_original_bed=stay.get("id","")==stay_id and stay.get("bed_id","")==bed_id and int(stay.get("admitted_tick",-1))==admitted_tick and stay.get("phase","")=="waiting_surgery" and visit.phase=="wait_surgery" and visit.ticket_id==ticket_id and visit.final_result.is_empty() and c.world.facts.actors[visit.actor_id].get("support_facility_id","")==bed_id and c.world.facts.adaptations.get(bed_id,{}).get("owner_id","")==stay_id
		checks.no_ordinary_abandonment=c.world.facts.rng.patience==patience and not c.world.facts.wait_departures.get(visit.actor_id,{}).get("selected",false) and int(c.world.facts.tickets.get(ticket_id,{}).get("waited_ticks",-1))==0 and arrivals.outpatient_count(c.world)==0
		checks.no_unstarted_effects=c.world.facts.preparations.is_empty() and visit.attempt_ids.is_empty() and c.world.facts.attempts.is_empty() and _units_used(c)==used_units and _income(c)==income and _income(c,"ward")==0 and _income(c,"surgery")==0 and _income(c,"cure")==0
	checks.final_valid=c.world.validate(_content).is_empty()
	var passed: bool=admitted
	for value: bool in checks.values(): passed=passed and value
	t.check("CLIN-38",passed,{"checks":checks,"pre_support_walk":pre_support_walk,"post_support_location":post_support_location,"input_validation":input_validation,"counts":{"reserved":reserved_count,"admitted":admitted_count,"final":arrivals.outpatient_count(c.world)},"state":_state(c)})
