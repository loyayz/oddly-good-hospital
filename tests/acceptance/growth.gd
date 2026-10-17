extends "res://tests/acceptance/growth_fixtures.gd"

const CASES: Dictionary = {
	"GROW-01":"docs/design/11-growth-arrivals-recruitment.md §1.1.1/1.2；零能力零机会且不抽签",
	"GROW-02":"docs/design/11-growth-arrivals-recruitment.md §1.1/1.1.1；完整组合要求互异实际操作者",
	"GROW-03":"docs/design/11-growth-arrivals-recruitment.md §1.1.1；容量投影只读",
	"GROW-04":"docs/design/11-growth-arrivals-recruitment.md §1.1.1；关诊不改变结构能力",
	"GROW-05":"docs/design/11-growth-arrivals-recruitment.md §1.1/1.2；保持客流取min(C,H)",
	"GROW-06":"docs/design/11-growth-arrivals-recruitment.md §1.2；三班固定时刻向量",
	"GROW-07":"docs/design/11-growth-arrivals-recruitment.md §1.2；零能力班无机会",
	"GROW-08":"docs/design/11-growth-arrivals-recruitment.md §1.2；计划恢复及查询不重抽",
	"GROW-09":"docs/design/01-simulation.md §5；明日档位与立即关诊",
	"GROW-10":"docs/design/11-growth-arrivals-recruitment.md §1.2.1；关诊早排除不查病例或抽患者",
	"GROW-11":"docs/design/11-growth-arrivals-recruitment.md §1.1/1.2.1；真实门诊在院数与床承诺",
	"GROW-12":"docs/design/11-growth-arrivals-recruitment.md §1.2.1；同tick逐机会重读额度",
	"GROW-13":"docs/design/11-growth-arrivals-recruitment.md §1.2.1；Readiness失败消费不补发",
	"GROW-14":"docs/design/11-growth-arrivals-recruitment.md §2；弃候概率公式与环境缓冲",
	"GROW-15":"docs/design/11-growth-arrivals-recruitment.md §2/2.1；120秒首签与每30秒唯一签",
	"GROW-16":"docs/design/11-growth-arrivals-recruitment.md §2.1；生活暂离保留有效候诊余量",
	"GROW-17":"docs/design/11-growth-arrivals-recruitment.md §2；安全排除及确定退出先于概率",
	"GROW-18":"docs/design/04-technical.md §6患者耐心的到期索引；恢复不重抽旧门槛",
	"GROW-19":"docs/design/11-growth-arrivals-recruitment.md §1.3；实际离院及两个完整日窗口",
	"GROW-20":"docs/design/11-growth-arrivals-recruitment.md §1.3；20%回访与最久离院身份选择",
	"GROW-21":"docs/design/01-simulation.md §9/9.1；38研究AND可达及真实初诊开放",
	"GROW-22":"docs/design/01-simulation.md §9.1；唯一免费简报不重设期限",
	"GROW-23":"docs/design/01-simulation.md §9.1；简报120模拟秒到期归并",
	"GROW-24":"docs/design/01-simulation.md §9.1；同tick诊断资料优先且唯一",
	"GROW-25":"docs/design/01-simulation.md §9.2；待办只规划有序唯一",
	"GROW-26":"docs/design/01-simulation.md §9.2；重查前置资料并唯一付费任务",
	"GROW-27":"docs/design/04-technical.md §3 ResearchService；缺资源显式允许已付等待",
	"GROW-28":"docs/design/01-simulation.md §9/9.2；社区研究只在不足时零费双倍量",
	"GROW-29":"docs/design/01-simulation.md §9.2；实际到桌当班才推进研究",
	"GROW-30":"docs/design/01-simulation.md §9.2；研究课程共用真实桌位且可分桌并行",
	"GROW-31":"docs/design/01-simulation.md §9.2；暂停释放资源保留付款进度",
	"GROW-32":"docs/design/01-simulation.md §9.2；故障恢复及改派保留冻结进度",
	"GROW-33":"docs/design/01-simulation.md §9.2；取消按未完成比例一次退款",
	"GROW-34":"docs/design/01-simulation.md §9.2；旧任务冻结量付款方式与回报",
	"GROW-35":"docs/design/01-simulation.md §9.2/9.4；实际完成一次解锁并释放",
	"GROW-36":"docs/design/01-simulation.md §9.3；六兴趣路线只筛原依赖图",
	"GROW-37":"docs/design/01-simulation.md §9.4；研究开放选项仍查真实接诊缺项",
	"GROW-38":"docs/design/04-technical.md §4研究进度；资料简报排序与任务恢复",
	"GROW-39":"docs/design/11-growth-arrivals-recruitment.md §1.1；两套术组、两床及独立共享护理覆盖",
	"GROW-40":"docs/design/11-growth-arrivals-recruitment.md §1.1.2；日界与保持命令封闭输入、暂停续接和一次提交",
	"GROW-41":"docs/design/11-growth-arrivals-recruitment.md §1.1.2；待续步骤保存与请求命令水位、冻结计划恢复",
	"GROW-42":"docs/design/11-growth-arrivals-recruitment.md §1.1.1；关闭旧患者病种不清空模型身份或遗漏旧需求",
	"GROW-43":"docs/design/11-growth-arrivals-recruitment.md §1.1.1；苏醒承诺、恢复信用及并行床边工作去重",
	"GROW-44":"docs/design/11-growth-arrivals-recruitment.md §1.1.1；准备中的第二套资源按原身份和准备余量扣减",
	"GROW-45":"docs/design/11-growth-arrivals-recruitment.md §1.1.1；既有护理覆盖排除另一病房与术组主动岗位",
	"GROW-46":"docs/design/11-growth-arrivals-recruitment.md §1.1.1；必要检查保留全部合法资源及证据条件分支",
	"GROW-47":"docs/design/11-growth-arrivals-recruitment.md §1.1.2；运输回执不改变参考依据，已知余量仍使依据变化",
	"GROW-48":"docs/design/11-growth-arrivals-recruitment.md §1.1.1；同床不同护理护士的门诊转床需求保持各自身份",
	"GROW-49":"docs/design/11-growth-arrivals-recruitment.md §1.1.1；两床及八床覆盖贡献逐项切班，不转移到错误班次",
	"GROW-50":"docs/design/11-growth-arrivals-recruitment.md §1.1.2；后台保留业务版本和实际承诺适配，名义资格一致",
	"GROW-51":"docs/design/11-growth-arrivals-recruitment.md §1.1.1；查房授权即时失效，冷热几何与权限一致",
	"GROW-52":"docs/design/11-growth-arrivals-recruitment.md §1.1；K仅依赖首尝试实际结构及接待匹配",
	"GROW-53":"docs/design/11-growth-arrivals-recruitment.md §1.1.2；无关运输变化不递增等价病例版本",
	"GROW-54":"docs/design/11-growth-arrivals-recruitment.md §1.1.2；A到B到A封闭结果保留与原输入重试",
	"GROW-55":"docs/design/11-growth-arrivals-recruitment.md §1.1.2；记录共享保持输入隔离、删除与后继完整性",
	"GROW-56":"docs/design/07-clinical-team.md §10；同身体不同专业的会诊候选与遍历顺序无关",
	"GROW-57":"docs/design/07-clinical-team.md §6；完整方案集上的三种策略与实际选择一致",
	"GROW-58":"docs/design/11-growth-arrivals-recruitment.md §1.1.2；实际交通票序和出口保留，名义模型排除排队",
	"GROW-59":"docs/design/07-clinical-team.md §14；已足够证据不枚举后续检查，入院布尔与解释一致",
	"GROW-60":"docs/design/07-clinical-team.md §5；候选使用已证明的适配站位且不修改实际预约",
	"GROW-61":"docs/design/11-growth-arrivals-recruitment.md §1.1.2；在途组偏移与身体姿态进入名义运输缓存身份"
}

func run(t) -> void:
	_content = HospitalContent.new()
	_cache = t.checkpoints(_content,"res://tests/acceptance/growth_fixtures.gd")
	for case_id: String in CASES:
		if not t.wants(case_id): continue
		t.begin_case(case_id)
		if not _content.error.is_empty():
			t.check(case_id,false,{"content_error":_content.error})
			continue
		if int(case_id.right(2))>=21 and int(case_id.right(2))<=38:
			var started: int = Time.get_ticks_msec()
			_prepare_opened_snapshot()
			t.preparation_elapsed(started)
		await call("_case_"+case_id.right(2),t)
	for simulation: HospitalSimulation in _simulations: simulation.dispose()
	_simulations.clear()


func _case_01(t) -> void:
	var empty: Dictionary = _context(false)
	# This case, unlike the fixed-day fixtures, exercises real plan generation.
	empty.world.facts.arrivals.plan.clear()
	var rng_before: Dictionary = empty.world.facts.rng.duplicate(true)
	empty.arrivals.boundaries(empty.world)
	var zero: Dictionary = empty.world.facts.arrivals.plan
	t.check("GROW-01",not zero.is_empty() and zero.opportunity_count==0 and zero.shift_opportunity_counts==[0,0,0] and zero.schedule_seed==null and zero.shift_capacities==[F.make(),F.make(),F.make()] and empty.world.facts.rng==rng_before,zero)

func _case_02(t) -> void:
	var base: Dictionary = _context()
	_single_case(base)
	var capacity: Dictionary = base.arrivals.capacity(base.world,false)
	var no_team: Dictionary = _context()
	_single_case(no_team)
	for staff_id: String in ["starter_doctor_b","starter_doctor_c"]:
		no_team.world.facts.staff.erase(staff_id)
		no_team.world.facts.actors.erase(staff_id)
	var absent: Dictionary = no_team.arrivals.capacity(no_team.world,false)
	_add_room(no_team.world,"spare_terminal","T01",[42,70],[6,6])
	_add_facility(no_team.world,"unmanned_terminal","M09","spare_terminal",[44,71])
	_fresh_space(no_team)
	var unmanned: Dictionary = no_team.arrivals.capacity(no_team.world,false)
	var flow: bool = _shared_clock_contract()
	t.check("GROW-02",flow and capacity.get("complete",false) and F.compare(capacity.get("capacity",F.make()),F.make())>0 and absent.get("capacity",{})==F.make() and unmanned.get("capacity",{})==F.make() and int(unmanned.get("scale_numerator",-1))==0,{"base":capacity,"missing_team":absent,"unmanned":unmanned,"shared_clocks":flow})

func _shared_clock_contract() -> bool:
	# Two doctors rotate 100-tick diagnostics and 200-tick treatment. A
	# quarter-probability 100-tick retry adds 25 ticks, not another budget.
	# Each complete visit uses 325 doctor-ticks: 12000/325 = 480/13.
	var model: Dictionary = {"probability":F.make(1),"bundles":[
		{"resources":{"doctor_a":F.make(200)},"choices":["diagnosis_a","reception","retry_a"]},
		{"resources":{"doctor_b":F.make(200)},"choices":["diagnosis_b","reception","retry_b"]}],
		"choice_groups":{
			"diagnosis_a":[{"resources":{"doctor_b":F.make(100)}}],
			"diagnosis_b":[{"resources":{"doctor_a":F.make(100)}}],
			"reception":[{"resources":{"receptionist":F.make(25)}}],
			"retry_a":[{"resources":{"doctor_a":F.make(25)},"choices":["retry_round"]}],
			"retry_b":[{"resources":{"doctor_b":F.make(25)},"choices":["retry_round"]}],
			"retry_round":[{"resources":{"round":F.make(10)}}]}}
	var budgets: Dictionary = {"doctor_a":F.make(6000),"doctor_b":F.make(6000),"receptionist":F.make(6000),"round":F.make(6000)}
	var result: Dictionary = ArrivalCapacitySolver.solve([model],budgets)
	if result.get("capacity",{})!=F.make(480,13): return false
	budgets.receptionist = F.make(500)
	result = ArrivalCapacitySolver.solve([model],budgets)
	if result.get("capacity",{})!=F.make(20): return false
	budgets.round = F.make(100)
	result = ArrivalCapacitySolver.solve([model],budgets)
	if result.get("capacity",{})!=F.make(10): return false
	# One third of Visits use six ticks; two thirds use three. Both real
	# resources have 180 ticks, so 360/(6/3+3*2/3) = 90 Visits exactly.
	var mixed: Array = []
	for index: int in 2:
		var ticks: int = 6 if index==0 else 3
		mixed.append({"probability":F.make(index+1,3),"bundles":[{"resources":{},"choices":["operator"]}],"choice_groups":{"operator":[{"resources":{"a":F.make(ticks)}},{"resources":{"b":F.make(ticks)}}]}})
	result = ArrivalCapacitySolver.solve(mixed,{"a":F.make(180),"b":F.make(180)})
	if result.get("capacity",{})!=F.make(90): return false
	var visits: Array = [F.make(),F.make()]
	var used: Dictionary = {"a":F.make(),"b":F.make()}
	for assignment: Dictionary in result.assignments:
		visits[assignment.case_index] = F.add(visits[assignment.case_index],assignment.amount)
		for resource: String in assignment.resources:
			used[resource] = F.add(used[resource],F.mul(assignment.amount,assignment.resources[resource]))
	return visits==[F.make(30),F.make(60)] and used.a==F.make(180) and used.b==F.make(180)

func _case_03(t) -> void:
	var base: Dictionary = _context()
	_single_case(base)
	var capacity: Dictionary = base.arrivals.capacity(base.world,false)
	var frozen: Dictionary = base.world.freeze()
	var repeated: Dictionary = base.arrivals.capacity(base.world,false)
	var unchanged: bool = base.world.freeze()==frozen
	# Actual whereabouts do not remove a scheduled, qualified nominal resource.
	# This calculation input does not execute or skip any actual movement.
	for staff_id: String in base.world.ids("staff"):
		base.world.facts.actors[staff_id].location = {"kind":"outside"}
	var outside_input: Dictionary = base.world.freeze()
	var outside: Dictionary = base.arrivals.capacity(base.world,false)
	var outside_unchanged: bool = base.world.freeze()==outside_input
	base.arrivals.execute(base.world,"arrivals_weight",{"disease_id":"D09","weight":0})
	var no_cases: Dictionary = base.arrivals.capacity(base.world,false)
	base.arrivals.execute(base.world,"arrivals_weight",{"disease_id":"D09","weight":1})
	var restored: Dictionary = base.arrivals.capacity(base.world,false)
	t.check("GROW-03",capacity==repeated and unchanged and outside==capacity and outside_unchanged and no_cases.get("capacity",{})==F.make() and restored==capacity,{"same_projection":capacity==repeated,"world_unchanged":unchanged,"temporary_positions_independent":outside==capacity,"empty_weighted_pool":no_cases.get("capacity",{}),"restored_weights":restored==capacity})

func _case_39(t) -> void:
	# A legal calculation input; no patient movement or clinical work is skipped.
	var ctx: Dictionary = _context()
	var builder: RefCounted = load("res://tests/acceptance/clinical_fixtures.gd").new()
	builder._content = _content
	builder._add_layout(ctx.world,"or_standard","parallel_or_a",[33,65])
	builder._add_layout(ctx.world,"or_standard","parallel_or_b",[43,65])
	builder._add_layout(ctx.world,"ward_two_beds","parallel_ward",[53,65])
	_add_room(ctx.world,"parallel_gp","gp",[43,76],[4,4])
	_add_facility(ctx.world,"parallel_gp_desk","FUR02","parallel_gp",[43,77])
	for id: String in ["starter_doctor_a","starter_doctor_b"]:
		ctx.world.facts.staff[id].abilities.treatment = 2
		ctx.world.facts.staff[id].schedule = builder._schedule("outpatient")
		for slot: int in 2: ctx.world.facts.staff[id].schedule[slot].pools = ["diagnosis"]
	ctx.world.facts.staff.starter_doctor_c.schedule = builder._schedule("rest")
	for index: int in 4:
		builder._add_worker(ctx.world,"parallel_surgeon_"+str(index),"doctor",[34+index*4,75],"surgery",{"diagnosis":1,"treatment":1,"care":0,"surgery":2},"DT02")
	for index: int in 2:
		var id: String = "parallel_or_nurse_"+str(index)
		builder._add_worker(ctx.world,id,"nurse",[50+index*2,75],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":1})
		ctx.world.facts.staff[id].certificates = ["q_or","q_ward"]
	builder._add_worker(ctx.world,"parallel_cover","nurse",[54,75],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":0})
	ctx.world.facts.staff.parallel_cover.ward_id = "parallel_ward"
	for index: int in 2:
		builder._add_worker(ctx.world,"parallel_round_"+str(index),"doctor",[58+index*2,75],"round",{"diagnosis":2,"treatment":1,"care":0,"surgery":0})
	for definition: Dictionary in _content.catalog.research:
		if not definition.id in ctx.world.facts.research: ctx.world.facts.research.append(definition.id)
	ctx.simulation._ensure_services()
	ctx.world.touch()
	_fresh_space(ctx)
	var valid: String = ctx.world.validate(_content)
	var frozen: Dictionary = ctx.world.freeze()
	var nominal: WorldState = ctx.arrivals._capacity_reference_world(ctx.world)
	var query: Dictionary = {}
	var binding: Dictionary = _content.definition("treatment_bindings","B_S13_D09_M09")
	var quote: Dictionary = ctx.clinic.reference_demand(nominal,binding.id,false,0,query)
	var variant: Dictionary = ctx.arrivals._reference_variant(nominal,binding,false,0,quote,query)
	variant.probability = F.make(1)
	var tables: Dictionary = {}
	var beds: Dictionary = {}
	for bundle: Dictionary in quote.get("model",{}).get("bundles",[]):
		for resource: String in bundle.resources:
			if not resource.begins_with("facility:"): continue
			var id: String = resource.trim_prefix("facility:")
			if ctx.world.facts.facilities[id].definition_id=="EQ01": tables[id] = true
			elif ctx.world.facts.facilities[id].definition_id=="EQ05": beds[id] = true
	var structure: Dictionary = ctx.arrivals._structural_pairs(nominal,[variant],0)
	var budgets: Dictionary = ctx.arrivals._resource_budgets(nominal,[variant],0)
	var model_key: Array = [JSON.stringify(variant).sha256_text()]
	var capacity: Dictionary = ctx.arrivals._solve_roles(nominal,[variant],budgets,0,model_key)
	# Exhausted care time removes new Visit capacity, while the independent
	# built structural maximum still has both complete teams.
	var coverage_budget: Dictionary = budgets["coverage:parallel_cover:parallel_ward"]
	budgets["coverage:parallel_cover:parallel_ward"] = F.make()
	var exhausted: Dictionary = ctx.arrivals._solve_roles(nominal,[variant],budgets,0,model_key)
	budgets["coverage:parallel_cover:parallel_ward"] = coverage_budget
	var restored: Dictionary = ctx.arrivals._solve_roles(nominal,[variant],budgets,0,model_key)
	if restored.get("capacity",{})!=capacity.get("capacity",{}):
		t.check("GROW-39",false,{"restored":restored,"capacity":capacity})
		return
	# Both independent teams fit. Removing the only independent cover removes
	# every surgery group; the two operating nurses cannot cover their own work.
	nominal.facts.staff = nominal.facts.staff.duplicate(true)
	nominal.facts.staff.parallel_cover.schedule = builder._schedule("rest")
	var uncovered: Dictionary = ctx.arrivals._structural_pairs(nominal,[variant],0)
	t.check("GROW-39",valid.is_empty() and ctx.world.freeze()==frozen and quote.get("ok",false) and tables.size()==2 and beds.size()==2 and int(structure.get("pairs",-1))==2 and int(uncovered.get("pairs",-1))==0 and not capacity.has("error") and F.compare(capacity.get("capacity",F.make()),F.make())>0 and exhausted.get("capacity",{})==F.make() and int(exhausted.get("structural_pairs",-1))==2,{"validation":valid,"tables":tables.keys(),"beds":beds.keys(),"structure":structure,"uncovered":uncovered,"capacity":capacity,"exhausted":exhausted,"reference_reason":quote.get("reason","")})

func _case_42(t) -> void:
	var ctx: Dictionary = _context()
	_single_case(ctx)
	var visit: Dictionary = _patient(ctx,[45,76],"B_S13_D09_M09")
	if visit.is_empty():
		t.check("GROW-42",false,ctx.get("last_admission",{}))
		return
	_single_case(ctx,"D37")
	var before: Dictionary = ctx.world.freeze()
	var query: Dictionary = {}
	ctx.arrivals._reference_classes(ctx.world,0,query)
	var identity: Dictionary = query.duplicate(true)
	var workload: Dictionary = ctx.arrivals._existing_workload(ctx.world,0,query)
	var projection: Dictionary = ctx.arrivals.capacity(ctx.world)
	t.check("GROW-42",query==identity and not workload.is_empty() and projection.get("complete",false) and ctx.world.freeze()==before,{"query_preserved":query==identity,"workload":workload,"projection":projection})

func _commitment_context() -> Dictionary:
	var builder: RefCounted = load("res://tests/acceptance/clinical_fixtures.gd").new()
	builder._content = _content
	var ctx: Dictionary = builder._context(true)
	_simulations.append(ctx.sim)
	ctx.builder = builder
	ctx.ready = builder._arrive(ctx,"B_S13_D09_M09","P_D09_SURGERY")
	if ctx.ready:
		ctx.visit = ctx.world.facts.visits[ctx.visit_id]
		ctx.visit.plan_decision = {"plan_id":"P_D09_SURGERY","source":"director","revision":1}
	return ctx

func _case_43(t) -> void:
	# Calculation inputs start at legal service boundaries; this case does not
	# claim to verify the preceding travel, surgery or bedside execution.
	var ctx: Dictionary = _commitment_context()
	if not ctx.ready:
		t.check("GROW-43",false,ctx.errors)
		return
	var clinic: HospitalClinic = ctx.sim.clinic
	var quote: Dictionary = clinic._surgery_quote(ctx.world,ctx.visit,["clin_surgeon","clin_anesthesia","clin_or_nurse"],{"structural_only":true,"ignore_supplies":true})
	if not quote.ok:
		t.check("GROW-43",false,quote)
		return
	var attempt: Dictionary = clinic._commit_attempt(ctx.world,ctx.visit,quote)
	var stay: Dictionary = {"id":attempt.id,"attempt_id":attempt.id,"bed_id":quote.bed_id,"phase":"reserved","remaining_ticks":109,"work_credit_milli":0,"care_completed":false,"nurse_id":"clin_cover","round_doctor_id":"clin_round","escort_id":"clin_or_nurse","last_progress_tick":ctx.world.sim_tick}
	ctx.world.facts.ward_stays[stay.id] = stay
	ctx.world.facts.facilities[stay.bed_id].grade = 1
	ctx.world.facts.staff.clin_round.fatigue = 0.0
	var session: Dictionary = clinic._start(ctx.world,ctx.visit,"surgery",quote.facility_id,quote.staff_ids,50,{"attempt_id":attempt.id})
	var before: Dictionary = ctx.world.freeze()
	var surgery: Dictionary = clinic.remaining_commitments(ctx.world).resources
	attempt.result = not attempt.result
	var hidden_independent: bool = clinic.remaining_commitments(ctx.world).resources==surgery
	attempt.result = not attempt.result
	var readonly: bool = ctx.world.freeze()==before
	session.kind = "wake"
	var wake: Dictionary = clinic.remaining_commitments(ctx.world).resources
	ctx.world.facts.sessions.clear()
	stay.phase = "recovery"
	clinic._start(ctx.world,ctx.visit,"care",stay.bed_id,[stay.nurse_id],50,{"stay_id":stay.id})
	var care: Dictionary = clinic.remaining_commitments(ctx.world).resources
	ctx.world.facts.sessions.clear()
	stay.phase = "round"
	stay.remaining_ticks = 0
	stay.care_completed = true
	clinic._start(ctx.world,ctx.visit,"round",stay.bed_id,[stay.round_doctor_id],50,{"stay_id":stay.id})
	var round_work: Dictionary = clinic.remaining_commitments(ctx.world).resources
	var bed_key: String = "facility:"+str(stay.bed_id)
	# Grade 1 / care 1 gives rate 1090; 109 standard ticks need 100
	# wall ticks. Care 50 overlaps recovery; a started round has only its 50.
	t.check("GROW-43",readonly and hidden_independent and surgery.get("facility:"+str(quote.facility_id))-wake.get("facility:"+str(quote.facility_id))==150 and surgery.get("staff:clin_surgeon")==200 and surgery.get(bed_key)-wake.get(bed_key)==150 and wake.get(bed_key)>250 and care.get(bed_key)-round_work.get(bed_key)==150 and care.get("staff:clin_cover")==50 and round_work.get(bed_key)>50 and round_work.get("staff:clin_round")==50 and clinic._recovery_ticks(ctx.world,stay.bed_id,stay.nurse_id,12,500)==11,{"surgery":surgery,"wake":wake,"care":care,"round":round_work,"readonly":readonly,"hidden_independent":hidden_independent})

func _case_44(t) -> void:
	var ctx: Dictionary = _commitment_context()
	if not ctx.ready:
		t.check("GROW-44",false,ctx.errors)
		return
	ctx.builder._add_layout(ctx.world,"or_standard","second_committed_or",[55,65])
	for index: int in 3:
		ctx.builder._add_worker(ctx.world,"second_team_"+str(index),"nurse" if index==2 else "doctor",[54+index*3,75],"work" if index==2 else "surgery",{"diagnosis":1,"treatment":1,"care":1,"surgery":2},"DT02")
	ctx.world.facts.staff.second_team_2.certificates = ["q_or","q_ward"]
	var table_id: String = ""
	for facility: Dictionary in ctx.world.facts.facilities.values():
		if facility.get("room_id","")=="second_committed_or" and facility.definition_id=="EQ01": table_id = facility.id
	var clinic: HospitalClinic = ctx.sim.clinic
	var quote: Dictionary = clinic._surgery_quote(ctx.world,ctx.visit,["second_team_0","second_team_1","second_team_2"],{"facility_id":table_id,"structural_only":true,"ignore_supplies":true})
	if not quote.ok:
		t.check("GROW-44",false,quote)
		return
	ctx.world.facts.preparations[ctx.visit.id] = {"id":ctx.visit.id,"visit_id":ctx.visit.id,"kind":"surgery","facility_id":table_id,"staff_ids":quote.staff_ids,"bed_id":quote.bed_id,"nurse_id":quote.nurse_id,"round_doctor_id":quote.round_doctor_id,"ward_id":quote.ward_id,"supply_units":quote.supply_units,"setup_remaining_ticks":7,"deadline_tick":ctx.world.sim_tick+300}
	var before: Dictionary = ctx.world.freeze()
	var projection: Dictionary = clinic.remaining_commitments(ctx.world).resources
	var work: int = int(quote.work_ticks)+150
	var doctor_ticks: int = int(projection.get("staff:second_team_0",0))
	var nurse_ticks: int = int(projection.get("staff:second_team_2",0))
	var readonly: bool = ctx.world.freeze()==before
	ctx.world.facts.preparations[ctx.visit.id].setup_remaining_ticks = 0
	var ready: Dictionary = clinic.remaining_commitments(ctx.world).resources
	t.check("GROW-44",readonly and doctor_ticks>=work+7 and doctor_ticks-int(ready.get("staff:second_team_0",0))==7 and int(projection.get("facility:"+table_id,0))-int(ready.get("facility:"+table_id,0))==7 and nurse_ticks-int(ready.get("staff:second_team_2",0))==7 and nurse_ticks>doctor_ticks and not projection.has("staff:clin_surgeon"),{"projection":projection,"without_setup":ready,"expected_work":work,"original_table":table_id})

func _case_45(t) -> void:
	var ctx: Dictionary = _context()
	var cases: Array = [{"probability":F.make(1),"bundles":[
		{"resources":{"staff:n":F.make(1),"coverage:n:w1":F.make(1)},"coverage_roles":{"n":["w1"]}},
		{"resources":{"staff:n":F.make(1),"coverage:n:w2":F.make(1)},"coverage_roles":{"n":["w2"]}},
		{"resources":{"staff:n":F.make(1),"facility:or":F.make(1)}}]}]
	var budgets: Dictionary = {"staff:n":F.make(100),"coverage:n:w1":F.make(2),"coverage:n:w2":F.make(20),"facility:or":F.make(100)}
	var before: Array = cases.duplicate(true)
	var backend: RefCounted = ClassDB.instantiate("PlatformArrivalCapacity")
	var free: Dictionary = backend.call("prepare",cases,budgets)
	var locked: Dictionary = backend.call("prepare",ctx.arrivals._restrict_roles(cases,{"n":"w1"}),budgets)
	t.check("GROW-45",free.get("capacity",{})==F.make(100) and locked.get("capacity",{})==F.make(2) and before==cases,{"free":free,"locked":locked})

func _case_46(t) -> void:
	var builder: RefCounted = load("res://tests/acceptance/clinical_fixtures.gd").new()
	builder._content = _content
	var ctx: Dictionary = builder._context(false,true)
	_simulations.append(ctx.sim)
	_add_room(ctx.world,"second_diagnostic","gp",[42,65],[6,6])
	_add_facility(ctx.world,"second_exam","FUR02","second_diagnostic",[44,67])
	ctx.world.facts.facilities.second_exam.grade = 5
	builder._add_worker(ctx.world,"strong_exam_nurse","nurse",[48,75],"work",{"diagnosis":5,"treatment":0,"care":1,"surgery":0})
	var nominal: WorldState = ctx.sim.services.arrivals._capacity_reference_world(ctx.world)
	var candidate: Dictionary = ctx.sim.clinic._arrival_candidate(nominal,"B_S22_D14_M14",false)
	var world: WorldState = candidate.world
	var query: Dictionary = {"candidates":{},"diagnostic_stages":{}}
	ctx.sim.space.begin_route_query(world,{"nominal":true})
	var diagnostic: Dictionary = {}
	for pair: Dictionary in ctx.sim.clinic._reference_candidates(world,candidate.visit,"gp",query):
		if int(world.facts.staff[pair.staff_id].abilities.diagnosis)==1:
			diagnostic = pair
			break
	var result: Dictionary = ctx.sim.clinic._build_reference_diagnostic_stages(world,candidate.visit,diagnostic,query) if not diagnostic.is_empty() else {"ok":false}
	ctx.sim.space.end_route_query()
	var machines: Dictionary = {}
	var short_path: bool = false
	var long_path: bool = false
	for stages: Dictionary in result.get("variants",[]):
		if not stages.has("spectrum"): continue
		for id: String in stages.spectrum:
			if id.begins_with("facility:"): machines[id] = true
		short_path = short_path or not stages.has("resonance")
		long_path = long_path or stages.has("resonance")
	t.check("GROW-46",result.ok and machines.has("facility:second_exam") and machines.size()>=2 and short_path and long_path,{"machines":machines,"short_path":short_path,"long_path":long_path,"variants":result.get("variants",[]).size()})

func _case_47(t) -> void:
	var builder: RefCounted = load("res://tests/acceptance/space.gd").new()
	builder.content = _content
	var sim: HospitalSimulation = builder._transit_fixture()
	_simulations.append(sim)
	var id: String = builder._connection(sim)
	builder._add_actor(sim,"projection_rider","S49",[36,76])
	sim.space.request_move(sim.world,"projection_rider",2,[46,80])
	var boarding: bool = builder._wait(sim,func()->bool: return sim.world.facts.connectors[id].phase=="boarding",30)
	var connection: Dictionary = sim.world.facts.connectors[id]
	var first: Dictionary = HospitalTransit.reference_conditions(sim.world).duplicate(true)
	connection.use_receipts = {"completed_trip":sim.world.sim_tick}
	connection.condition = 90.0
	var receipts_ignored: bool = HospitalTransit.reference_conditions(sim.world)==first
	builder._movement_tick(sim)
	t.check("GROW-47",boarding and receipts_ignored and HospitalTransit.reference_conditions(sim.world)!=first,{"boarding":boarding,"receipts_ignored":receipts_ignored,"remainder_retained":HospitalTransit.reference_conditions(sim.world)!=first})

func _case_48(t) -> void:
	# A legal quote input, before treatment starts. Both qualified nurses can
	# cover each bed; their escort work belongs to the selected nurse only.
	var builder: RefCounted = load("res://tests/acceptance/clinical_fixtures.gd").new()
	builder._content = _content
	var ctx: Dictionary = builder._context(false,true)
	_simulations.append(ctx.sim)
	builder._add_layout(ctx.world,"ward_two_beds","clin_ward",[42,72])
	for index: int in 2:
		var id: String = "transfer_nurse_"+str(index)
		builder._add_worker(ctx.world,id,"nurse",[43+index,79],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":0})
		ctx.world.facts.staff[id].ward_id = "clin_ward"
	builder._add_worker(ctx.world,"clin_round","doctor",[51,79],"round",{"diagnosis":2,"treatment":1,"care":0,"surgery":0})
	ctx.world.facts.staff[ctx.doctors[1]].abilities.treatment = 3
	ctx.world.touch()
	var before: Dictionary = ctx.world.freeze()
	var nominal: WorldState = ctx.sim.services.arrivals._capacity_reference_world(ctx.world)
	var candidate: Dictionary = ctx.sim.clinic._arrival_candidate(nominal,"B_S22_D14_M14",false)
	var world: WorldState = candidate.world
	var query: Dictionary = {"candidates":{}}
	ctx.sim.space.begin_route_query(world,{"nominal":true})
	var receptions: Array = ctx.sim.clinic._reference_candidates(world,candidate.visit,"reception",query)
	var diagnostics: Array = ctx.sim.clinic._reference_candidates(world,candidate.visit,"gp",query)
	var terminal: String = str(world.facility_ids("M09")[0])
	var quote: Dictionary = ctx.sim.clinic._outpatient_quote(world,candidate.visit,world.facts.staff[ctx.doctors[1]],world.facts.facilities[terminal],"P_D14_GENTLE",true,true,true)
	var alternatives: Array = ctx.sim.clinic._reference_terminal_beds(world,candidate.visit,quote,{}) if quote.get("ok",false) else []
	var nurses: Dictionary = {}
	var correct: bool = not receptions.is_empty() and not diagnostics.is_empty()
	for alternative: Dictionary in alternatives:
		if not correct: break
		var bundle: Dictionary = ctx.sim.clinic._reference_terminal_bundle(world,candidate.visit,receptions[0],diagnostics[0],alternative,{},query)
		var staff: Array = []
		for id: String in bundle.get("stage_resources",{}).get("transfer",{}):
			if id.begins_with("staff:"): staff.append(id)
		correct = bundle.get("ok",false) and staff==["staff:"+str(alternative.nurse_id)]
		nurses[alternative.nurse_id] = true
	ctx.sim.space.end_route_query()
	t.check("GROW-48",correct and nurses.size()==2 and ctx.world.freeze()==before,{"alternatives":alternatives.size(),"nurses":nurses.keys(),"correct_escort":correct,"quote":quote})

func _case_49(t) -> void:
	# Coverage-slot arithmetic consumes per-bed durations, not serial nurse
	# work. These inputs do not claim an eight-patient clinical flow run.
	var ctx: Dictionary = _context()
	var key: String = "coverage:starter_nurse:ward"
	var examples: Array = [
		{"durations":[4000,4000],"expected":[8000,0,0]},
		{"durations":[4000,4000,4000,4000,4000,4000,4000,4000],"expected":[32000,0,0]},
		{"durations":[1000,7000],"expected":[7000,1000,0]},
		{"durations":[1000,2000,3000,4000,5000,6000,7000,13000],"expected":[33000,7000,1000]}]
	var correct: bool = true
	for example: Dictionary in examples:
		var projected: Dictionary = {"resources":{},"coverage":{key:example.durations},"visits":{}}
		for shift: int in 3:
			var work: Dictionary = ctx.arrivals._existing_workload(ctx.world,shift,{},projected)
			correct = correct and work.get(key,F.make())==F.make(example.expected[shift])
	t.check("GROW-49",correct,{"examples":examples})

func _case_50(t) -> void:
	var ctx: Dictionary = _commitment_context()
	var clinic: HospitalClinic = ctx.sim.clinic
	var quote: Dictionary = clinic._surgery_quote(ctx.world,ctx.visit,["clin_surgeon","clin_anesthesia","clin_or_nurse"],{"structural_only":true,"ignore_supplies":true}) if ctx.ready else {"ok":false}
	if not quote.ok:
		t.check("GROW-50",false,quote)
		return
	var reason: String = clinic._reserve_bundle(ctx.world,ctx.visit,quote,ctx.visit.id)
	if not reason.is_empty():
		t.check("GROW-50",false,{"reservation":reason})
		return
	var preparation: ArrivalPreparation = ArrivalPreparation.new(_content)
	ctx.world.facts.preparations[ctx.visit.id] = {"id":ctx.visit.id,"visit_id":ctx.visit.id,"kind":"surgery","facility_id":quote.facility_id,"staff_ids":quote.staff_ids,"bed_id":quote.bed_id,"nurse_id":quote.nurse_id,"round_doctor_id":quote.round_doctor_id,"ward_id":quote.ward_id,"supply_units":quote.supply_units,"setup_remaining_ticks":7,"deadline_tick":ctx.world.sim_tick+300}
	var before: Dictionary = ctx.world.freeze()
	var input: Dictionary = preparation._capture(ctx.world,true,-1)
	var captured: WorldState = WorldState.new(input.facts)
	var actual: Dictionary = clinic.remaining_commitments(ctx.world)
	var copied: Dictionary = clinic.remaining_commitments(captured)
	var correct: bool = actual==copied and input.facts.gameplay_version==ctx.world.facts.gameplay_version and captured.facts.adaptations==ctx.world.facts.adaptations and not captured.facts.adaptations.is_empty() and before==ctx.world.freeze()
	# Mutating an isolated input cannot alter the original reservation.
	captured.facts.adaptations[quote.bed_id].staff_ids.clear()
	correct = correct and ctx.world.freeze()==before
	ctx.world.facts.preparations.clear()
	for id: String in ctx.world.facility_ids("SE06"): ctx.world.facts.facilities[id].failed = true
	var missing: Dictionary = preparation._capture(ctx.world,false,-1)
	var arrivals: HospitalArrivalService = ctx.sim.services.arrivals
	var direct: Dictionary = clinic._arrival_candidate(arrivals._capacity_reference_world(ctx.world),ctx.visit.binding_id,false)
	var copied_input: Dictionary = clinic._arrival_candidate(arrivals._capacity_reference_world(WorldState.new(missing.facts)),ctx.visit.binding_id,false)
	ctx.sim.space.begin_route_query(direct.world,{"nominal":true})
	var sync: Dictionary = clinic._surgery_quote(direct.world,direct.visit,quote.staff_ids,{"structural_only":true,"ignore_supplies":true})
	ctx.sim.space.end_route_query()
	ctx.sim.space.begin_route_query(copied_input.world,{"nominal":true})
	var background: Dictionary = clinic._surgery_quote(copied_input.world,copied_input.visit,quote.staff_ids,{"structural_only":true,"ignore_supplies":true})
	ctx.sim.space.end_route_query()
	correct = correct and not sync.ok and not background.ok and sync.reason==background.reason
	preparation.dispose()
	t.check("GROW-50",correct,{"commitments_equal":actual==copied,"sync_without_workbench":sync,"background_without_workbench":background})

func _case_51(t) -> void:
	var ctx: Dictionary = _commitment_context()
	var clinic: HospitalClinic = ctx.sim.clinic
	var quote: Dictionary = clinic._surgery_quote(ctx.world,ctx.visit,["clin_surgeon","clin_anesthesia","clin_or_nurse"],{"structural_only":true,"ignore_supplies":true}) if ctx.ready else {"ok":false}
	if not quote.ok or not clinic._reserve_bundle(ctx.world,ctx.visit,quote,ctx.visit.id).is_empty():
		t.check("GROW-51",false,quote)
		return
	ctx.builder._add_worker(ctx.world,"new_round_doctor","doctor",[52,75],"round",{"diagnosis":2,"treatment":1,"care":0,"surgery":0})
	var stay: Dictionary = {"bed_id":quote.bed_id,"round_doctor_id":"new_round_doctor"}
	var bed: Dictionary = ctx.sim.space.facility_layout(ctx.world,quote.bed_id)
	var doctor: Dictionary = ctx.world.facts.actors.new_round_doctor
	var target: Vector2i = Vector2i(int(bed.operator_cells[1][0]),int(bed.operator_cells[1][1]))
	ctx.sim.space.begin_route_query(ctx.world)
	var before: String = ctx.sim.space.static_reason(ctx.world,doctor,int(bed.floor_id),target)
	ctx.sim.space.end_route_query()
	var selected: String = clinic._round_candidate(ctx.world,ctx.visit,stay)
	ctx.sim.space.begin_route_query(ctx.world)
	var hot: String = ctx.sim.space.static_reason(ctx.world,doctor,int(bed.floor_id),target)
	ctx.sim.space.end_route_query()
	var cold: String = HospitalSpace.new(_content).static_reason(ctx.world,doctor,int(bed.floor_id),target)
	var reset: String = ctx.sim.space.reserve_facility(ctx.world,quote.bed_id,ctx.visit.actor_id,ctx.visit.id,[quote.nurse_id,quote.round_doctor_id])
	ctx.sim.space.begin_route_query(ctx.world)
	var withdrawn: String = ctx.sim.space.static_reason(ctx.world,doctor,int(bed.floor_id),target)
	ctx.sim.space.end_route_query()
	t.check("GROW-51",not before.is_empty() and selected==doctor.id and hot.is_empty() and hot==cold and reset.is_empty() and not withdrawn.is_empty(),{"before":before,"selected":selected,"hot":hot,"cold":cold,"withdrawn":withdrawn,"reset":reset})

func _case_52(t) -> void:
	var ctx: Dictionary = _context()
	_single_case(ctx)
	var query: Dictionary = {}
	var classes: Array = ctx.arrivals._reference_classes(ctx.world,0,query)
	var first: Dictionary = ctx.arrivals._structural_pairs(ctx.world,classes,0)
	var retained: Dictionary = ctx.arrivals._structure_cache[0]
	var changed: Array = classes.duplicate(true)
	for case: Dictionary in changed:
		case.probability = F.make(1,7)
		case.choice_groups["unused-retry:9600"] = [{"resources":{"staff:unused":F.make(123)}}]
		case.bundles.append(case.bundles[0].duplicate(true))
	var next: Dictionary = ctx.arrivals._structural_pairs(ctx.world,changed,0)
	var reused: bool = is_same(retained,ctx.arrivals._structure_cache[0])
	# A real structural root must affect the identity even if K's maximum ties.
	changed[0].bundles[0].structural_resources.append("facility:new_terminal")
	ctx.arrivals._structural_pairs(ctx.world,changed,0)
	t.check("GROW-52",first==next and reused and not is_same(retained,ctx.arrivals._structure_cache[0]),{"first":first,"same_K":next,"reused":reused})

func _case_53(t) -> void:
	var builder: RefCounted = load("res://tests/acceptance/space.gd").new()
	builder.content = _content
	var ctx: Dictionary = _context()
	_single_case(ctx)
	var sim: HospitalSimulation = ctx.simulation
	builder._history_height(sim,2)
	var built: CommandResult = builder._command(sim,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[36,72]})
	var extended: CommandResult = builder._command(sim,"connector_extend",{"connection_id":builder._connection(sim),"floor_id":2}) if built.accepted else built
	if not extended.accepted:
		t.check("GROW-53",false,extended.to_record())
		return
	var arrivals: HospitalArrivalService = sim.services.arrivals
	for disease: Dictionary in _content.catalog.diseases: arrivals.execute(sim.world,"arrivals_weight",{"disease_id":disease.id,"weight":1 if disease.id=="D09" else 0})
	var first: Dictionary = {}
	arrivals._reference_classes(sim.world,0,first)
	var connection: Dictionary = sim.world.facts.connectors[builder._connection(sim)]
	connection.use_receipts = {"old":0}
	var receipts: Dictionary = {}
	arrivals._reference_classes(sim.world,0,receipts)
	# This hospital's clinical resources remain on floor 1. Changing this
	# connector's idle stop cannot improve their routes via the same anchor.
	connection.floor_id = 2 if int(connection.floor_id)==1 else 1
	var changed: Dictionary = {}
	arrivals._reference_classes(sim.world,0,changed)
	builder._add_actor(sim,"shared_quote_rider","S49",[36,76])
	sim.space.request_move(sim.world,"shared_quote_rider",2,[46,80])
	var boarding: bool = builder._wait(sim,func()->bool: return connection.phase=="boarding",80)
	var facts: Dictionary = sim.world.freeze()
	facts.moves = HospitalTransit.reference_movements(sim.world)
	var nominal: WorldState = WorldState.new(facts)
	var reference: Dictionary = {"nominal":true}
	sim.space.begin_route_query(nominal,reference)
	var route: Dictionary = sim.space.route(nominal,"starter_doctor_a",1,[47,93],[],{},true)
	sim.space.begin_route_query(nominal)
	var reused: Dictionary = sim.space.route(nominal,"starter_doctor_a",1,[47,93],[],{},true)
	sim.space.end_route_query()
	sim.space.end_route_query()
	t.check("GROW-53",not first.model_key.is_empty() and first.model_key==receipts.model_key and first.model_key==changed.model_key and boarding and not facts.moves.is_empty() and route==reused and reference.journeys.size()==1 and reference.transport_builds==1,{"same_model":first.model_key==changed.model_key,"boarding":boarding,"journeys":reference.journeys.size(),"route":route})

func _case_54(t) -> void:
	var ctx: Dictionary = _context(false)
	var preparation: ArrivalPreparation = ArrivalPreparation.new(_content)
	var input: Dictionary = preparation._capture(ctx.world,false,-1)
	var other: Dictionary = input.duplicate(true)
	other.facts.plan_strategy = "safety_first"
	preparation._completed = {"input":input,"projection":{"complete":true,"marker":"A"}}
	preparation._completed_id = 7
	preparation._sequence = 8
	preparation._active = other
	preparation._active_id = 8
	var gate: Semaphore = Semaphore.new()
	preparation._thread = Thread.new()
	preparation._thread.start(func()->Dictionary:
		gate.wait()
		return {"projection":{"complete":true,"marker":"B"},"elapsed_us":0})
	var first: Dictionary = preparation.sealed_projection(ctx.world,false)
	gate.post()
	while preparation._thread.is_alive(): await t.process_frame
	preparation.poll(false)
	var retained: Dictionary = preparation.sealed_projection(ctx.world,false)
	var correct: bool = first.get("marker")=="A" and retained==first and preparation._completed_id==8
	preparation._sealed_result = {"complete":false,"reason":"controlled_failure"}
	preparation.retry()
	while preparation._thread!=null and preparation._thread.is_alive(): await t.process_frame
	preparation.poll(false)
	correct = correct and preparation._completed.input==input and preparation.sealed_projection(ctx.world,false).get("complete",false)
	preparation.dispose()
	t.check("GROW-54",correct,{"first":first,"retained":retained})

func _case_55(t) -> void:
	var ctx: Dictionary = _context()
	var preparation: ArrivalPreparation = ArrivalPreparation.new(_content)
	var first: Dictionary = preparation._capture(ctx.world,true,-1)
	var copied: int = preparation.metrics().copied_records
	var second: Dictionary = preparation._capture(ctx.world,true,-1)
	var unchanged: bool = first==second and preparation.metrics().copied_records==copied
	var id: String = ctx.world.ids("facilities")[0]
	var old: Dictionary = first.facts.facilities[id].duplicate(true)
	ctx.world.facts.facilities[id].grade = 2
	var changed: Dictionary = preparation._capture(ctx.world,true,-1)
	ctx.world.facts.facilities.erase(id)
	var removed: Dictionary = preparation._capture(ctx.world,true,-1)
	ctx.world.facts.facilities[id] = old.duplicate(true)
	var restored: Dictionary = preparation._capture(ctx.world,true,-1)
	var correct: bool = unchanged and is_same(first.facts.facilities[id],second.facts.facilities[id]) and first.facts.facilities[id]==old and changed.facts.facilities[id].grade==2 and not removed.facts.facilities.has(id) and restored==first
	preparation.dispose()
	t.check("GROW-55",correct,{"unchanged_records_reused":unchanged,"restored":restored==first})

func _case_56(t) -> void:
	var ctx: Dictionary = _context()
	var first_binding: Dictionary = _content.definition("treatment_bindings","B_S49_D37_M37")
	var specialty: String = _content.definition("treatment_routines",first_binding.routine_id).specialty_id
	var second_binding: Dictionary = {}
	for binding: Dictionary in _content.catalog.treatment_bindings:
		if binding.species_id==first_binding.species_id and _content.definition("treatment_routines",binding.routine_id).specialty_id!=specialty:
			second_binding = binding
			break
	var candidate: Dictionary = ctx.clinic._arrival_candidate(ctx.arrivals._capacity_reference_world(ctx.world),first_binding.id,false)
	if not candidate.ok or second_binding.is_empty():
		t.check("GROW-56",false,{"candidate":candidate.get("reason",""),"second":second_binding})
		return
	var world: WorldState = candidate.world
	var a: Dictionary = candidate.visit
	var b: Dictionary = a.duplicate(true)
	b.binding_id = second_binding.id
	b.disease_id = second_binding.disease_id
	for id: String in world.ids("staff"):
		if world.facts.staff[id].role!="doctor": continue
		world.facts.staff[id] = world.facts.staff[id].duplicate(true)
		world.facts.staff[id].schedule = [{"kind":"rest","pools":[],"locked":false},{"kind":"rest","pools":[],"locked":false},{"kind":"rest","pools":[],"locked":false}]
	world.facts.staff.starter_doctor_a.schedule[0] = {"kind":"outpatient","pools":[specialty],"locked":false}
	world.facts.staff.starter_doctor_b.schedule[0] = {"kind":"outpatient","pools":[_content.definition("treatment_routines",second_binding.routine_id).specialty_id],"locked":false}
	var query: Dictionary = {"candidates":{}}
	var ac: Array = ctx.clinic._reference_candidates(world,a,"consult",query)
	var bc: Array = ctx.clinic._reference_candidates(world,b,"consult",query)
	var reverse: Dictionary = {"candidates":{}}
	var br: Array = ctx.clinic._reference_candidates(world,b,"consult",reverse)
	var ar: Array = ctx.clinic._reference_candidates(world,a,"consult",reverse)
	var cold: Array = ctx.clinic._reference_candidates(world,b,"consult",{"candidates":{}})
	t.check("GROW-56",not ac.is_empty() and not bc.is_empty() and ac!=bc and ac==ar and bc==br and bc==cold,{"A":ac,"B":bc,"second":second_binding.id})

func _case_57(t) -> void:
	var ctx: Dictionary = _context()
	var quotes: Array = [{"plan_id":"P_D09_COMMON","score":100.0,"probability_bp":7900,"work_ticks":100},{"plan_id":"P_D09_GENTLE","score":90.0,"probability_bp":8300,"work_ticks":200}]
	var correct: bool = ctx.clinic._choose_plan(quotes,"doctor").plan_id=="P_D09_COMMON" and ctx.clinic._choose_plan(quotes,"safety_first").plan_id=="P_D09_GENTLE" and ctx.clinic._choose_plan(quotes,"outpatient_first").plan_id=="P_D09_GENTLE"
	quotes[0].probability_bp = 8000
	correct = correct and ctx.clinic._choose_plan(quotes,"outpatient_first").plan_id=="P_D09_COMMON"
	var detailed: Array = []
	for strategy: String in ["doctor","safety_first","outpatient_first"]:
		ctx.world.facts.plan_strategy = strategy
		var nominal: WorldState = ctx.arrivals._capacity_reference_world(ctx.world)
		var options: Dictionary = ctx.clinic._reference_options(nominal,"B_S13_D09_M09",false,0,{},{},{"candidates":{}})
		correct = correct and options.ok
		for terminal: Dictionary in options.get("terminals",[]):
			var selected: Dictionary = ctx.clinic._select_plan(options.world,options.visit,terminal.consulting_doctor_id)
			correct = correct and selected.get("plan_id","")==terminal.plan_id
			detailed.append([strategy,terminal.plan_id,selected.get("plan_id","")])
	t.check("GROW-57",correct,detailed)

func _case_58(t) -> void:
	var builder: RefCounted = load("res://tests/acceptance/space.gd").new()
	builder.content = _content
	var sim: HospitalSimulation = builder._transit_fixture()
	_simulations.append(sim)
	var id: String = builder._connection(sim)
	for index: int in 3:
		var actor_id: String = "capture_queue_"+str(index)
		builder._add_actor(sim,actor_id,"S49",[[36,76],[32,76],[45,84]][index])
	sim.space.request_move(sim.world,"capture_queue_0",2,[46,80])
	var boarded: bool = builder._wait(sim,func()->bool: return sim.world.facts.actors.capture_queue_0.location.kind=="transit",30)
	sim.space.request_move(sim.world,"capture_queue_1",2,[42,82])
	var queued: bool = boarded and builder._wait(sim,func()->bool: return sim.world.facts.moves.get("capture_queue_1",{}).has("transit_ticket"),90)
	var preparation: ArrivalPreparation = ArrivalPreparation.new(_content)
	var actual: Dictionary = preparation._capture(sim.world,true,-1)
	var captured: WorldState = WorldState.new(actual.facts)
	var first: Dictionary = HospitalTransit._prefix(sim.space,sim.world,sim.world.facts.connectors[id],"capture_queue_2")
	var copied: Dictionary = HospitalTransit._prefix(HospitalSpace.new(_content),captured,captured.facts.connectors[id],"capture_queue_2")
	var nominal: Dictionary = preparation._capture(sim.world,false,-1)
	var stripped: bool = true
	for movement: Dictionary in nominal.facts.moves.values(): stripped = stripped and not movement.has("transit_ticket")
	var before: Dictionary = sim.world.freeze()
	builder._add_actor(sim,"capture_exit_blocker","S49",[36,76],2)
	var blocked: WorldState = WorldState.new(preparation._capture(sim.world,true,-1).facts)
	var blocked_source: Dictionary = HospitalTransit._prefix(sim.space,sim.world,sim.world.facts.connectors[id],"capture_queue_2")
	var blocked_copy: Dictionary = HospitalTransit._prefix(HospitalSpace.new(_content),blocked,blocked.facts.connectors[id],"capture_queue_2")
	preparation.dispose()
	t.check("GROW-58",queued and first==copied and stripped and blocked_source==blocked_copy and not blocked_source.ok and not before.is_empty(),{"queued":queued,"source":first,"captured":copied,"blocked":blocked_source})

func _case_59(t) -> void:
	var ctx: Dictionary = _context()
	var candidate: Dictionary = ctx.clinic._arrival_candidate(ctx.arrivals._capacity_reference_world(ctx.world),"B_S49_D37_M37",false)
	var query: Dictionary = {"candidates":{}}
	var pairs: Array = ctx.clinic.service_candidates(candidate.world,candidate.visit,"gp",true)
	var result: Dictionary = ctx.clinic._build_reference_diagnostic_stages(candidate.world,candidate.visit,pairs[0],query) if not pairs.is_empty() else {"ok":false}
	var full: Dictionary = ctx.clinic.arrival_readiness(ctx.world,"B_S49_D37_M37",false,true)
	var brief: Dictionary = ctx.clinic.arrival_readiness(ctx.world,"B_S49_D37_M37",false,false)
	t.check("GROW-59",result.ok and query.candidates.is_empty() and full.ok and brief.ok==full.ok,{"diagnostic":result,"candidate_queries":query.candidates.size(),"detailed":full.ok,"brief":brief.ok})

func _case_60(t) -> void:
	var ctx: Dictionary = _context()
	var candidate: Dictionary = ctx.clinic._arrival_candidate(ctx.arrivals._capacity_reference_world(ctx.world),"B_S13_D09_M09",false)
	var world: WorldState = candidate.world
	var before: Dictionary = world.freeze()
	var pairs: Array = ctx.clinic.service_candidates(world,candidate.visit,"gp",true)
	var checked: int = 0
	var correct: bool = not pairs.is_empty()
	for pair: Dictionary in pairs:
		var copy: WorldState = WorldState.new(world.freeze())
		var reason: String = ctx.space.reserve_facility(copy,pair.facility_id,candidate.visit.actor_id,candidate.visit.id,[pair.staff_id])
		var layout: Dictionary = ctx.space.facility_layout(copy,pair.facility_id)
		correct = correct and reason.is_empty() and ctx.space.route(copy,candidate.visit.actor_id,int(layout.floor_id),layout.patient_cell,[],{},true).ok and ctx.space.route(copy,pair.staff_id,int(layout.floor_id),layout.operator_cells[0],[],{},true).ok
		checked += 1
	t.check("GROW-60",correct and checked>0 and world.freeze()==before,{"checked":checked,"readonly":world.freeze()==before})

func _case_61(t) -> void:
	var builder: RefCounted = load("res://tests/acceptance/space.gd").new()
	builder.content = _content
	var ctx: Dictionary = _context()
	_single_case(ctx)
	var sim: HospitalSimulation = ctx.simulation
	builder._history_height(sim,2)
	var built: CommandResult = builder._command(sim,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[36,72]})
	var extended: CommandResult = builder._command(sim,"connector_extend",{"connection_id":builder._connection(sim),"floor_id":2}) if built.accepted else built
	if not extended.accepted:
		t.check("GROW-61",false,extended.to_record())
		return
	builder._add_actor(sim,"prefix_primary","S49",[36,76])
	builder._add_actor(sim,"prefix_companion","S49",[37,76])
	var move: String = sim.space.request_group_move(sim.world,"prefix_primary",["prefix_primary","prefix_companion"],{"prefix_primary":[0,0],"prefix_companion":[1,0]},2,[46,80])
	var boarded: bool = move.is_empty() and builder._wait(sim,func()->bool: return sim.world.facts.actors.prefix_primary.location.kind=="transit",100)
	if not boarded:
		t.check("GROW-61",false,{"move":move,"boarded":boarded})
		return
	var source: Dictionary = sim.world.freeze()
	var original: Dictionary = HospitalTransit.reference_basis(ctx.space,sim.world).duplicate(true)
	var before: Dictionary = {}
	ctx.arrivals._reference_classes(sim.world,0,before)
	var observations: Array = []
	var correct: bool = not before.model_key.is_empty()
	for change: String in ["offset","posture","facing"]:
		# Complete boundary inputs own their records; no in-flight simulation is
		# advanced or moved by the alternative-envelope query.
		var facts: Dictionary = source.duplicate(true)
		if change=="offset": facts.moves.prefix_primary.offsets.prefix_companion = [0,1]
		elif change=="posture": facts.actors.prefix_companion.posture = "lying"
		else: facts.actors.prefix_companion.facing = PI/2
		var changed: WorldState = WorldState.new(facts)
		var hot: Dictionary = {}
		var hot_classes: Array = ctx.arrivals._reference_classes(changed,0,hot)
		# The collection may be retained, but every transport-dependent case
		# must now carry the new complete prefix identity.
		var expected: Dictionary = HospitalTransit.reference_basis(ctx.space,changed)
		var rebound: bool = not ctx.arrivals._reference_cache[0].cases.is_empty()
		for item: Dictionary in ctx.arrivals._reference_cache[0].cases.values(): rebound = rebound and item.transport==expected
		ctx.arrivals._reference_cache.clear()
		var cold: Dictionary = {}
		var cold_classes: Array = ctx.arrivals._reference_classes(changed,0,cold)
		# Local version counters are observation identities, not model values.
		hot.erase("model_key")
		cold.erase("model_key")
		var reference: Dictionary = {"nominal":true}
		var nominal: WorldState = ctx.arrivals._capacity_reference_world(sim.world)
		ctx.space.begin_route_query(nominal,reference)
		ctx.space.route(nominal,"starter_doctor_a",1,[47,93],[],{},true)
		ctx.space.end_route_query()
		var primed: bool = reference.journeys.size()==1
		ctx.space.begin_route_query(ctx.arrivals._capacity_reference_world(changed),reference)
		var invalidated: bool = primed and reference.journeys.is_empty()
		ctx.space.end_route_query()
		correct = correct and expected!=original and rebound and hot_classes==cold_classes and hot==cold and invalidated
		observations.append({"change":change,"rebound":rebound,"cold_equal":hot_classes==cold_classes and hot==cold,"journeys_invalidated":invalidated})
	t.check("GROW-61",correct and sim.world.freeze()==source,{"boarded":boarded,"observations":observations,"readonly":sim.world.freeze()==source})

func _case_40(t) -> void:
	var ctx: Dictionary = _context()
	_single_case(ctx)
	ctx.arrivals.execute(ctx.world,"arrivals_intake",{"open":false})
	ctx.world.facts.arrivals.plan.clear()
	var session: GameSession = GameSession.new(ctx.simulation,"sealed-day")
	# Change a real dependency after preparation starts. The original candidate
	# cannot satisfy the sealed input, irrespective of worker scheduling speed.
	ctx.arrivals.execute(ctx.world,"arrivals_weight",{"disease_id":"D09","weight":2})
	var rng: Dictionary = ctx.world.facts.rng.duplicate(true)
	session.set_speed(1)
	var first: Array[TickResult] = session.advance(0.1)
	var waiting: bool = first.is_empty() and ctx.simulation.pending() and ctx.world.sim_tick==0 and ctx.world.facts.arrivals.plan.is_empty() and ctx.world.facts.rng.arrival==rng.arrival
	var sealed_world: Dictionary = ctx.world.freeze()
	var late: CommandResult = session.submit(GameCommand.new("late-weight",ctx.world.hospital_id,ctx.world.revision,"arrivals_weight",BusinessPayload.new({"disease_id":"D09","weight":0}),"sealed-day"))
	session.set_speed(0)
	var results: Array[TickResult] = []
	var deadline: int = Time.get_ticks_msec()+15000
	while ctx.simulation.pending() and ctx.simulation.preparing_error().is_empty() and Time.get_ticks_msec()<deadline:
		var completed: Array[TickResult] = session.advance(0.4)
		if completed.is_empty(): waiting = waiting and ctx.world.freeze()==sealed_world
		results.append_array(completed)
		await t.process_frame
	var plan: Dictionary = ctx.world.facts.arrivals.plan.duplicate(true)
	var sealed: bool = results.size()==1 and ctx.world.sim_tick==1 and int(plan.get("opportunity_count",0))>0 and not ctx.world.facts.command_receipts.has("late-weight") and int(ctx.world.facts.arrivals.disease_weights.D09)==2
	session.advance(0.4)
	var frozen: bool = ctx.world.facts.arrivals.plan==plan and ctx.world.sim_tick==1 and ctx.world.facts.command_receipts.has("late-weight")
	var held: CommandResult = session.submit(GameCommand.new("hold",ctx.world.hospital_id,ctx.world.revision,"arrivals_scale",BusinessPayload.new({"mode":"hold_capacity"}),"sealed-day"))
	session.submit(GameCommand.new("after-hold",ctx.world.hospital_id,ctx.world.revision,"arrivals_weight",BusinessPayload.new({"disease_id":"D09","weight":1}),"sealed-day"))
	deadline = Time.get_ticks_msec()+15000
	while ctx.simulation.pending() and ctx.simulation.preparing_error().is_empty() and Time.get_ticks_msec()<deadline:
		session.advance(0.4)
		await t.process_frame
	var held_input: bool = ctx.world.facts.command_receipts.has("hold") and ctx.world.facts.arrivals.held_capacity_fraction==F.make() and not ctx.world.facts.command_receipts.has("after-hold")
	session.advance(0.4)
	t.check("GROW-40",waiting and late.code=="queued" and sealed and frozen and held.code=="queued" and held_input and int(ctx.world.facts.arrivals.disease_weights.D09)==1 and ctx.world.sim_tick==1 and ctx.world.facts.arrivals.plan==plan,{"waiting":waiting,"sealed":sealed,"frozen":frozen,"held_input":held_input,"error":ctx.simulation.preparing_error()})

func _case_41(t) -> void:
	var ctx: Dictionary = _context()
	_single_case(ctx)
	ctx.arrivals.execute(ctx.world,"arrivals_intake",{"open":false})
	ctx.world.facts.arrivals.plan.clear()
	var session: GameSession = GameSession.new(ctx.simulation,"save-boundary")
	ctx.arrivals.execute(ctx.world,"arrivals_weight",{"disease_id":"D09","weight":2})
	session.set_speed(1)
	session.advance(0.1)
	var pending: bool = ctx.simulation.pending()
	session.set_speed(0)
	session.submit(GameCommand.new("before-save",ctx.world.hospital_id,ctx.world.revision,"finance_note",BusinessPayload.new({"text":"保存前接收","target_amount":6000}),"save-boundary"))
	var guard: RefCounted = ClassDB.instantiate("PlatformSessionGuard")
	var acquired: Dictionary = guard.call("acquire")
	if not acquired.ok:
		t.check("GROW-41",false,acquired)
		return
	var store: HospitalSnapshots = HospitalSnapshots.new(_content,guard)
	var started: Dictionary = store.begin(ctx.simulation,"save-boundary")
	session.submit(GameCommand.new("after-save",ctx.world.hospital_id,ctx.world.revision,"finance_note",BusinessPayload.new({"text":"保存后接收","target_amount":7000}),"save-boundary"))
	var receipt: Dictionary = {}
	var deadline: int = Time.get_ticks_msec()+15000
	while started.ok and receipt.is_empty() and ctx.simulation.preparing_error().is_empty() and Time.get_ticks_msec()<deadline:
		receipt = store.poll()
		if not receipt.is_empty(): break
		session.advance(0.4)
		await t.process_frame
	var loaded: Dictionary = store.load_commit(ctx.world.hospital_id,receipt.snapshot_id) if receipt.get("ok",false) else {"ok":false}
	var watermark: bool = loaded.ok and loaded.world.sim_tick==1 and loaded.world.facts.command_receipts.has("before-save") and not loaded.world.facts.command_receipts.has("after-save")
	var restored: bool = false
	if loaded.ok:
		var saved: Dictionary = loaded.world.freeze()
		var kernel: HospitalSimulation = HospitalSimulation.new(loaded.world,_content)
		var resumed: GameSession = GameSession.new(kernel,"restored-plan")
		resumed.advance(0.4)
		restored = loaded.world.freeze()==saved
		kernel.dispose()
	guard.call("release")
	t.check("GROW-41",pending and started.ok and started.request.get("pending",false) and watermark and restored,{"pending":pending,"started":started,"receipt":receipt,"watermark":watermark,"restored":restored,"error":ctx.simulation.preparing_error()})

func _case_04(t) -> void:
	var base: Dictionary = _context()
	_single_case(base)
	var capacity: Dictionary = base.arrivals.capacity(base.world,false)
	base.arrivals.execute(base.world,"arrivals_intake",{"open":false})
	var closed_capacity: Dictionary = base.arrivals.capacity(base.world,false)
	t.check("GROW-04",closed_capacity.get("capacity",{})==capacity.get("capacity",{}) and closed_capacity.get("shift_pairs",[])==capacity.get("shift_pairs",[]),closed_capacity)

func _case_05(t) -> void:
	var base: Dictionary = _context()
	_single_case(base)
	var capacity: Dictionary = base.arrivals.capacity(base.world,false)
	base.arrivals.execute(base.world,"arrivals_intake",{"open":false})
	# Today is already frozen; real capacity was calculated above and is still
	# recalculated by hold selection and the later new-day boundaries below.
	base.arrivals.boundaries(base.world)
	var today: Dictionary = base.world.facts.arrivals.plan.duplicate(true)
	var held_result: CommandResult = base.arrivals.execute(base.world,"arrivals_scale",{"mode":"hold_capacity"})
	var held: Dictionary = base.world.facts.arrivals.held_capacity_fraction.duplicate(true)
	_add_room(base.world,"second_terminal_room","T01",[42,70],[6,6])
	_add_facility(base.world,"second_terminal","M09","second_terminal_room",[44,71])
	# One additional treatment operator is sufficient to increase C. Duplicating
	# the whole diagnostic roster adds unrelated interchangeable resource bundles.
	for source_id: String in ["starter_doctor_b"]:
		var extra_id: String = "extra_"+source_id
		base.world.facts.staff[extra_id] = base.world.facts.staff[source_id].duplicate(true)
		base.world.facts.staff[extra_id].id = extra_id
		base.world.facts.actors[extra_id] = base.world.facts.actors[source_id].duplicate(true)
		base.world.facts.actors[extra_id].id = extra_id
		base.world.facts.actors[extra_id].location.cell = [54,65+base.world.facts.staff.size()%5]
	_fresh_space(base)
	var grown: Dictionary = base.arrivals.capacity(base.world,false)
	base.arrivals.boundaries(base.world)
	var unchanged_today: bool = base.world.facts.arrivals.plan==today
	base.world.facts.sim_tick = 18000
	base.arrivals.boundaries(base.world)
	var held_day: Dictionary = base.world.facts.arrivals.plan.duplicate(true)
	var held_total: Dictionary = _sum(held_day.get("shift_capacities",[]))
	base.world.facts.facilities.zombie_machine.failed = true
	base.world.facts.facilities.second_terminal.failed = true
	base.world.facts.sim_tick = 36000
	base.arrivals.boundaries(base.world)
	t.check("GROW-05",held_result.accepted and held==capacity.get("capacity",{}) and F.compare(grown.get("capacity",F.make()),held)>0 and unchanged_today and held_total==held and base.world.facts.arrivals.plan.opportunity_count==0,{"held":held,"grown":grown,"held_day":held_day,"declined":base.world.facts.arrivals.plan})

func _case_06(t) -> void:
	var empty: Dictionary = _context(false)
	var vector_world: WorldState = empty.world
	var allocation: Array = DayPlan.allocate_shifts(1,"321",8,[F.make(1),F.make(1),F.make(1)])
	var vector: Dictionary = _plan(vector_world,8,allocation,[F.make(3),F.make(3),F.make(3)])
	t.check("GROW-06",allocation==[3,2,3] and _slot_ticks(vector)==[1156,2815,5438,8035,11156,12853,15397,16553],{"allocation":allocation,"ticks":_slot_ticks(vector)})

func _case_07(t) -> void:
	var vector_world: WorldState = _context(false).world
	var gap_counts: Array = DayPlan.allocate_shifts(1,"321",8,[F.make(1),F.make(),F.make(1)])
	var gap: Dictionary = _plan(vector_world,8,gap_counts,[F.make(5),F.make(),F.make(5)])
	var no_middle: bool = true
	for tick: int in _slot_ticks(gap):
		no_middle = no_middle and (tick<6000 or tick>=12000)
	t.check("GROW-07",gap_counts==[4,0,4] and no_middle,{"counts":gap_counts,"ticks":_slot_ticks(gap)})

func _case_08(t) -> void:
	var vector: Dictionary = _vector_plan(_context(false).world)
	var restore: Dictionary = _context()
	restore.world.facts.arrivals.plan = vector.duplicate(true)
	var restore_rng: Dictionary = restore.world.facts.rng.duplicate(true)
	var restored: WorldState = WorldState.new(restore.world.freeze())
	restored.facts.arrivals.next_preset = "festival"
	restored.facts.staff.starter_doctor_a.schedule[0].kind = "rest"
	var restored_ticks: Array = _slot_ticks(restored.facts.arrivals.plan)
	var wide: Dictionary = F.make("18446744073709551616","3")
	var exact: bool = F.add(wide,F.make(2,3))==F.make("6148914691236517206")
	exact = exact and F.add(F.make("999999999999999999"),F.make("999999999999999999"))==F.make("1999999999999999998")
	exact = exact and F.make("999999999999999999",7)==F.make("142857142857142857")
	exact = exact and F.floor_value(wide)==6148914691236517205 and F.ceil_value(wide)==6148914691236517206
	t.check("GROW-08",exact and restored_ticks==_slot_ticks(vector) and restored.facts.arrivals.plan==vector and restored.facts.rng==restore_rng and not vector.has("slot_ticks") and DayPlan.validate(vector).is_empty(),{"plan":restored.facts.arrivals.plan,"wide_exact_fractions":exact})

func _case_09(t) -> void:
	var restore: Dictionary = _context()
	restore.world.facts.arrivals.plan = _vector_plan(restore.world)
	var before_settings: Dictionary = restore.world.facts.arrivals.plan.duplicate(true)
	restore.arrivals.execute(restore.world,"arrivals_intake",{"open":true})
	restore.arrivals.execute(restore.world,"arrivals_preset",{"preset":"busy"})
	restore.arrivals.execute(restore.world,"arrivals_intake",{"open":false})
	var immediate: bool = not restore.world.facts.arrivals.intake_open
	restore.arrivals.execute(restore.world,"arrivals_intake",{"open":true})
	t.check("GROW-09",immediate and restore.world.facts.arrivals.intake_open and restore.world.facts.arrivals.preset=="normal" and restore.world.facts.arrivals.next_preset=="busy" and restore.world.facts.arrivals.plan==before_settings,restore.arrivals.daystats(restore.world))

func _case_10(t) -> void:
	var excluded: Dictionary = _context()
	var observed: AdmissionObserver = _observer(excluded)
	excluded.world.facts.arrivals.plan = _plan(excluded.world,1,[1,0,0])
	excluded.world.facts.sim_tick = DayPlan.slot_tick(excluded.world.facts.arrivals.plan,0)
	excluded.arrivals.execute(excluded.world,"arrivals_intake",{"open":false})
	var excluded_before: Dictionary = excluded.world.freeze()
	excluded.arrivals.arrivals(excluded.world)
	t.check("GROW-10",observed.readiness_queries==0 and excluded.world.facts.arrivals.plan.next_slot_index==1 and excluded.world.facts.rng==excluded_before.rng and excluded.world.facts.actors==excluded_before.actors and excluded.world.facts.visits==excluded_before.visits and excluded.world.facts.tickets==excluded_before.tickets and excluded.world.facts.preparations==excluded_before.preparations,excluded.arrivals.daystats(excluded.world))

func _case_11(t) -> void:
	var counting: Dictionary = _context()
	var first: Dictionary = _patient(counting,[34,76],"B_S44_D01_M01")
	var second: Dictionary = _patient(counting,[46,76])
	var count_passed: bool = false
	var count_details: Dictionary = {"fixture_errors":_fixture_errors.duplicate(true)}
	if not first.is_empty() and not second.is_empty():
		second.phase = "leaving"
		var before_bed: int = counting.arrivals.outpatient_count(counting.world)
		for topic: String in ["R02","R11","R12","R33","R34"]:
			counting.world.facts.research.append(topic)
		_add_room(counting.world,"count_or","operating_room",[34,65],[8,8])
		_add_facility(counting.world,"count_table","EQ01","count_or",[36,67])
		counting.world.facts.facilities.count_table.patient_cell = [36,71]
		counting.world.facts.facilities.count_table.operator_cells = [[35,68],[39,67],[39,69]]
		_add_room(counting.world,"count_ward","ward",[50,67],[8,8])
		_add_facility(counting.world,"count_bed","EQ05","count_ward",[51,68])
		_add_facility(counting.world,"count_nurse_base","SE06","count_ward",[51,73])
		HospitalFactory._add_staff(counting.world,"count_care_nurse","护理护士","nurse",[54,73],_content)
		for doctor_id: String in ["starter_doctor_a","starter_doctor_b"]:
			counting.world.facts.staff[doctor_id].title_id = "DT02"
			counting.world.facts.staff[doctor_id].abilities.surgery = 2
			counting.world.facts.staff[doctor_id].schedule[0] = {"kind":"surgery","pools":[],"locked":false}
		counting.world.facts.staff.starter_nurse.abilities.surgery = 1
		counting.world.facts.staff.starter_nurse.certificates.append("q_or")
		counting.world.facts.staff.starter_doctor_c.abilities.diagnosis = 2
		counting.world.facts.staff.starter_doctor_c.schedule[0] = {"kind":"round","pools":[],"locked":false}
		counting.world.facts.staff.starter_doctor_c.on_shift = true
		counting.simulation._ensure_services()
		counting.clinic._retarget_ticket(counting.world,first,"surgery")
		first.plan_decision = {"plan_id":"P_D01_SURGERY","source":"director","revision":1}
		# A frozen, not-yet-started original bed commitment is the admission-count input.
		counting.world.facts.preparations[first.id] = {"id":first.id,"visit_id":first.id,"kind":"surgery","bed_id":"count_bed","facility_id":"count_table","staff_ids":["starter_doctor_a","starter_doctor_b","starter_nurse"],"nurse_id":"count_care_nurse","round_doctor_id":"starter_doctor_c","ward_id":"count_ward","supply_units":8,"deadline_tick":counting.world.sim_tick+300,"setup_remaining_ticks":60}
		var with_bed: int = counting.arrivals.outpatient_count(counting.world)
		counting.world.facts.preparations.erase(first.id)
		var restored_count: int = counting.arrivals.outpatient_count(counting.world)
		count_passed = before_bed==2 and with_bed==1 and restored_count==2 and second.phase=="leaving" and counting.world.facts.staff.size()>0
		count_details = {"before":before_bed,"with_bed":with_bed,"cancelled":restored_count}
	t.check("GROW-11",count_passed,count_details)

func _case_12(t) -> void:
	var batch: Dictionary = _context()
	_single_case(batch,"D37")
	for index: int in 23:
		_patient(batch,[34+(index%10)*2,65+(index/10)*2])
	var batch_observer: AdmissionObserver = _observer(batch)
	# A legitimate frozen high-throughput day may outlive a later resource reduction.
	# At 18,000 opportunities in the first shift, exactly its first three are tick 0.
	batch.world.facts.arrivals.plan = _plan(batch.world,18000,[18000,0,0],[F.make(20000),F.make(),F.make()])
	batch.arrivals.arrivals(batch.world)
	var batch_stats: Dictionary = batch.arrivals.daystats(batch.world)
	t.check("GROW-12",batch.arrivals.outpatient_count(batch.world)==24 and batch.world.facts.arrivals.plan.next_slot_index==3 and batch_stats.days.get("1",{}).get("arrived",0)==1 and batch_stats.days.get("1",{}).get("full",0)==2 and batch_observer.readiness_queries==3,{"stats":batch_stats,"readiness_queries":batch_observer.readiness_queries,"fixture_errors":_fixture_errors})

func _case_13(t) -> void:
	var unready: Dictionary = _context()
	_single_case(unready,"D37")
	unready.world.facts.facilities.cold_machine.failed = true
	unready.world.facts.arrivals.plan = _plan(unready.world,1,[1,0,0])
	unready.world.facts.sim_tick = DayPlan.slot_tick(unready.world.facts.arrivals.plan,0)
	var unready_rng: Dictionary = unready.world.facts.rng.duplicate(true)
	unready.arrivals.arrivals(unready.world)
	unready.arrivals.arrivals(unready.world)
	t.check("GROW-13",unready.world.facts.arrivals.plan.next_slot_index==1 and unready.world.facts.visits.is_empty() and unready.world.facts.rng==unready_rng and unready.arrivals.daystats(unready.world).days.get("1",{}).get("unready",0)==1,unready.arrivals.daystats(unready.world))

func _case_14(t) -> void:
	var probability: Dictionary = _wait_ctx("PP02")
	probability.ticket.waited_ticks = 1200
	probability.visit.anger = 15.0
	var quick: int = probability.arrivals.patience_probability(probability.world,probability.visit,probability.ticket)
	probability.visit.personality_id = "PP09"
	var slow: int = probability.arrivals.patience_probability(probability.world,probability.visit,probability.ticket)
	_add_room(probability.world,"comfort_room","rest",[40,69],[8,8])
	for item: Dictionary in [{"id":"comfort_art","definition":"FUR25","cell":[43,75]},{"id":"comfort_plant","definition":"FUR26","cell":[45,74]},{"id":"comfort_light","definition":"FUR37","cell":[46,75]}]:
		_add_facility(probability.world,item.id,item.definition,"comfort_room",item.cell)
	var surfaces: Dictionary = probability.world.facts.environment.surfaces
	surfaces["1:45:76:floor:"] = {"floor_id":1,"cell":[45,76],"surface":"floor","edge":"","material_id":"MAT04"}
	surfaces["1:45:76:wall:south"] = {"floor_id":1,"cell":[45,76],"surface":"wall","edge":"south","material_id":"MAT08"}
	_fresh_space(probability)
	probability.visit.personality_id = "PP02"
	var buffered: int = probability.arrivals.patience_probability(probability.world,probability.visit,probability.ticket)
	probability.ticket.waited_ticks = 100000
	probability.visit.anger = 100.0
	var capped: int = probability.arrivals.patience_probability(probability.world,probability.visit,probability.ticket)
	t.check("GROW-14",quick==600 and slow==260 and buffered==300 and capped==3500 and mini(quick,mini(slow,buffered))>=100,{"quick":quick,"slow":slow,"buffered":buffered,"capped":capped})

func _case_15(t) -> void:
	var clock: Dictionary = _wait_ctx()
	clock.world.facts.sim_tick = 1199
	clock.ticket.waited_ticks = 1199
	var before: String = clock.world.facts.rng.patience.state_decimal
	clock.arrivals.needs(clock.world)
	var before_threshold: bool = clock.world.facts.rng.patience.state_decimal==before
	clock.world.facts.sim_tick = 1200
	clock.arrivals.advance_wait(clock.world)
	clock.arrivals.needs(clock.world)
	var at_first: String = clock.world.facts.rng.patience.state_decimal
	var first_events: int = _patience_events(clock.arrivals)
	clock.arrivals.advance_wait(clock.world)
	clock.arrivals.needs(clock.world)
	var unique_first: bool = clock.world.facts.rng.patience.state_decimal==at_first and int(clock.ticket.waited_ticks)==1200 and _patience_events(clock.arrivals)==0
	clock.world.facts.sim_tick = 1500
	clock.ticket.waited_ticks = 1500
	clock.arrivals.needs(clock.world)
	t.check("GROW-15",before_threshold and before!=at_first and first_events==1 and unique_first and int(clock.world.facts.wait_departures[clock.visit.actor_id].next_check_wait_ticks)==1800 and _patience_events(clock.arrivals)==1,{"state":clock.world.facts.wait_departures.get(clock.visit.actor_id,{}),"unique_first":unique_first})

func _case_16(t) -> void:
	var paused: Dictionary = _wait_ctx()
	paused.world.facts.sim_tick = 1200
	paused.ticket.waited_ticks = 1200
	paused.arrivals.needs(paused.world)
	paused.world.facts.sim_tick = 1210
	paused.ticket.waited_ticks = 1210
	paused.ticket.pause_reasons = {"life_service":true}
	var pause_rng: String = paused.world.facts.rng.patience.state_decimal
	for index: int in 400:
		paused.world.facts.sim_tick += 1
		paused.arrivals.advance_wait(paused.world)
		paused.arrivals.needs(paused.world)
	var held_wait: bool = paused.ticket.waited_ticks==1210 and paused.world.facts.rng.patience.state_decimal==pause_rng
	paused.ticket.pause_reasons.clear()
	for index: int in 289:
		paused.world.facts.sim_tick += 1
		paused.arrivals.advance_wait(paused.world)
		paused.arrivals.needs(paused.world)
	var not_yet: bool = paused.world.facts.rng.patience.state_decimal==pause_rng
	paused.world.facts.sim_tick += 1
	paused.arrivals.advance_wait(paused.world)
	paused.arrivals.needs(paused.world)
	t.check("GROW-16",held_wait and not_yet and paused.ticket.waited_ticks==1500 and paused.world.sim_tick==1900 and paused.world.facts.rng.patience.state_decimal!=pause_rng and paused.visit.ticket_id==paused.ticket.id,{"held":held_wait,"not_yet":not_yet,"waited_ticks":paused.ticket.waited_ticks,"sim_tick":paused.world.sim_tick})

func _case_17(t) -> void:
	var safe: Dictionary = _wait_ctx()
	safe.world.facts.sim_tick = 1200
	safe.ticket.waited_ticks = 1200
	safe.ticket.service_assigned = true
	safe.ticket.called_tick = 1200
	safe.space.request_move(safe.world,safe.visit.actor_id,1,[46,76])
	safe.space.advance(safe.world)
	var safe_rng: String = safe.world.facts.rng.patience.state_decimal
	safe.arrivals.needs(safe.world)
	var no_walking_draw: bool = safe.world.facts.rng.patience.state_decimal==safe_rng
	safe.world.facts.moves.erase(safe.visit.actor_id)
	safe.ticket.service_assigned = false
	safe.visit.phase = "surgery"
	safe.arrivals.needs(safe.world)
	var no_service_draw: bool = safe.world.facts.rng.patience.state_decimal==safe_rng
	safe.visit.phase = "wait_reception"
	safe.visit.anger = 90.0
	safe.visit.last_service_tick = 600
	safe.arrivals.needs(safe.world)
	var deterministic: bool = safe.world.facts.wait_departures.get(safe.visit.actor_id,{}).get("selected",false) and safe.world.facts.rng.patience.state_decimal==safe_rng
	var stalled: Dictionary = _wait_ctx()
	stalled.world.facts.sim_tick = 6000
	stalled.ticket.waited_ticks = 6000
	stalled.visit.last_service_tick = 0
	stalled.visit.last_progress_tick = 0
	var stalled_rng: String = stalled.world.facts.rng.patience.state_decimal
	stalled.arrivals.needs(stalled.world)
	t.check("GROW-17",no_walking_draw and no_service_draw and deterministic and stalled.world.facts.wait_departures.get(stalled.visit.actor_id,{}).get("selected",false) and stalled.world.facts.rng.patience.state_decimal==stalled_rng,{"walking":no_walking_draw,"service":no_service_draw,"anger_exit":deterministic,"stalled":stalled.world.facts.wait_departures.get(stalled.visit.actor_id,{})})

func _case_18(t) -> void:
	var saved: Dictionary = _wait_ctx()
	saved.world.facts.sim_tick = 1200
	saved.ticket.waited_ticks = 1200
	saved.arrivals.needs(saved.world)
	var saved_facts: Dictionary = saved.world.freeze()
	var reconstructed: WorldState = WorldState.new(saved_facts.duplicate(true))
	var rebuilt: HospitalArrivalService = HospitalArrivalService.new(_content,HospitalSpace.new(_content))
	rebuilt.needs(reconstructed)
	rebuilt.needs(reconstructed)
	var restored_patience_error: String = HospitalArrivalService.validate_snapshot(reconstructed.facts,_content)
	t.check("GROW-18",restored_patience_error.is_empty() and reconstructed.facts.rng==saved_facts.rng and reconstructed.facts.tickets==saved_facts.tickets and reconstructed.facts.wait_departures==saved_facts.wait_departures and _patience_events(rebuilt)==0,{"state":reconstructed.facts.wait_departures,"valid":restored_patience_error})

func _case_19(t) -> void:
	var ctx: Dictionary = _context()
	var person: Dictionary = _resident(ctx,[46,93])
	ctx.clinic.depart_visit(ctx.world,person.visit.id,"referred")
	ctx.arrivals.settle(ctx.world)
	var before_exit: bool = person.resident.last_departure_tick==-1 and ctx.arrivals.outpatient_count(ctx.world)==1
	var exited: bool = _actual_departure(ctx,person.visit)
	var departure: int = int(person.resident.last_departure_tick)
	ctx.world.facts.sim_tick = departure+35999
	var no_return_rng: String = ctx.world.facts.rng.arrival.state_decimal
	var early: Dictionary = ctx.arrivals._returning_resident(ctx.world,"S49","B_S49_D37_M37")
	var no_early_draw: bool = ctx.world.facts.rng.arrival.state_decimal==no_return_rng
	ctx.world.facts.sim_tick += 1
	_return_hit(ctx.world)
	var eligible: Dictionary = ctx.arrivals._returning_resident(ctx.world,"S49","B_S49_D37_M37")
	var restored: WorldState = WorldState.new(ctx.world.freeze())
	t.check("GROW-19",before_exit and exited and departure>=0 and person.visit.get("departure_recorded",false) and early.is_empty() and no_early_draw and eligible.get("id","")==person.resident.id and restored.facts.residents[person.resident.id].last_departure_tick==departure,{"departure":departure,"eligible":eligible.get("id",""),"before_exit":before_exit,"exited":exited})

func _case_20(t) -> void:
	var ctx: Dictionary = _context()
	var person: Dictionary = _resident(ctx,[46,93])
	ctx.clinic.depart_visit(ctx.world,person.visit.id,"referred")
	_actual_departure(ctx,person.visit)
	var another: Dictionary = _resident(ctx,[44,93])
	var second_exited: bool = _actual_departure(ctx,another.visit)
	ctx.world.facts.sim_tick = maxi(int(person.resident.last_departure_tick),int(another.resident.last_departure_tick))+36000
	_return_hit(ctx.world)
	var oldest: Dictionary = ctx.arrivals._returning_resident(ctx.world,"S49","B_S49_D37_M37")
	var tied: WorldState = WorldState.new(ctx.world.freeze())
	var tied_tick: int = mini(int(person.resident.last_departure_tick),int(another.resident.last_departure_tick))
	for resident_id: String in [str(person.resident.id),str(another.resident.id)]:
		var tied_resident: Dictionary = tied.facts.residents[resident_id]
		tied_resident.last_departure_tick = tied_tick
		var tied_visit: Dictionary = tied.facts.visits[tied_resident.last_visit_id]
		tied_visit.departed_tick = tied_tick
		tied_visit.departure_tick = tied_tick
		for memory: Dictionary in tied_resident.memories:
			if memory.visit_id==tied_visit.id:
				memory.departure_tick = tied_tick
	_return_hit(tied)
	var tie_choice: Dictionary = ctx.arrivals._returning_resident(tied,"S49","B_S49_D37_M37")
	var expected_tie: String = mini_string(str(person.resident.id),str(another.resident.id))
	var retained: Dictionary = person.resident.duplicate(true)
	var returned_visit: Dictionary = _patient(ctx,[44,76],"B_S49_D37_M37","PP01",person.resident)
	_return_hit(ctx.world)
	var occupied: Dictionary = ctx.arrivals._returning_resident(ctx.world,"S49","B_S49_D37_M37")
	ctx.arrivals.execute(ctx.world,"resident_forget",{"resident_id":another.resident.id})
	var none_rng: String = ctx.world.facts.rng.arrival.state_decimal
	var none: Dictionary = ctx.arrivals._returning_resident(ctx.world,"S49","B_S49_D37_M37")
	t.check("GROW-20",second_exited and oldest.get("id","")==person.resident.id and tie_choice.get("id","")==expected_tie and occupied.get("id","")==another.resident.id and none.is_empty() and ctx.world.facts.rng.arrival.state_decimal==none_rng and not returned_visit.is_empty() and returned_visit.id!=retained.last_visit_id and returned_visit.evidence_by_source.is_empty() and returned_visit.attempt_ids.is_empty() and returned_visit.personality_id==retained.personality_id and returned_visit.anger==float(_content.definition("patient_personalities",retained.personality_id).initial_anger) and ctx.world.facts.actors[returned_visit.actor_id].appearance==retained.appearance and person.resident.name==retained.name,{"oldest":oldest.get("id",""),"tie":tie_choice.get("id",""),"occupied":occupied.get("id",""),"none":none,"fixture_errors":_fixture_errors})

func _case_21(t) -> void:
	_prepare_opened_snapshot()
	var fresh: Dictionary = _context()
	var initial_materials: Dictionary = fresh.world.facts.research_progress.materials
	var initial_ok: bool = not fresh.research.opened(fresh.world)
	for definition: Dictionary in _content.catalog.research:
		initial_ok = initial_ok and initial_materials.has(definition.id)==definition.disease_ids.is_empty()
	var reachable: Array = []
	for pass_index: int in _content.catalog.research.size():
		for definition: Dictionary in _content.catalog.research:
			if definition.id in reachable:
				continue
			var allowed: bool = true
			for prerequisite: String in definition.requires:
				allowed = allowed and prerequisite in reachable
			if allowed:
				reachable.append(definition.id)
	var actual_gp: bool = false
	for visit: Dictionary in _opened_snapshot.get("visits",{}).values():
		actual_gp = actual_gp or visit.evidence_by_source.has("gp")
	t.check("GROW-21",initial_ok and reachable.size()==38 and _content.catalog.research.size()==38 and actual_gp and int(_opened_snapshot.get("research_progress",{}).get("opened_tick",-1))>=0,{"initial":initial_ok,"reachable":reachable.size(),"actual_gp":actual_gp,"fixture_errors":_fixture_errors})

func _case_22(t) -> void:
	var mail: Dictionary = _research_context(false,false)
	var cash: int = HospitalLedger.balance(mail.world)
	var first_request: CommandResult = mail.research.execute(mail.world,"research_request_mail",{"research_id":"R03"})
	var due: int = int(mail.world.facts.research_progress.mail.get("R03",-1))
	var requested_at: int = mail.world.sim_tick
	mail.world.facts.sim_tick += 1
	mail.research.execute(mail.world,"research_request_mail",{"research_id":"R03"})
	mail.research.execute(mail.world,"research_todo_add",{"research_id":"R03"})
	mail.research.execute(mail.world,"research_todo_remove",{"research_id":"R03"})
	t.check("GROW-22",first_request.accepted and due==requested_at+1200 and mail.world.facts.research_progress.mail.get("R03",-1)==due and HospitalLedger.balance(mail.world)==cash and not "R02" in mail.world.facts.research,{"due":due,"requested_at":requested_at,"cash":HospitalLedger.balance(mail.world)})

func _case_23(t) -> void:
	var mail: Dictionary = _research_context(false,false)
	var cash: int = HospitalLedger.balance(mail.world)
	mail.research.execute(mail.world,"research_request_mail",{"research_id":"R03"})
	var due: int = int(mail.world.facts.research_progress.mail.get("R03",-1))
	mail.world.facts.sim_tick = due-1
	mail.research.boundaries(mail.world)
	mail.research.settle(mail.world)
	var not_early: bool = not mail.world.facts.research_progress.materials.has("R03")
	var paused_facts: Dictionary = mail.world.freeze()
	mail.research.boundaries(mail.world)
	mail.research.settle(mail.world)
	var paused_same: bool = mail.world.freeze()==paused_facts
	mail.world.facts.sim_tick = due
	mail.research.boundaries(mail.world)
	mail.research.settle(mail.world)
	var arrived_materials: Dictionary = mail.world.facts.research_progress.materials.duplicate(true)
	mail.research.boundaries(mail.world)
	mail.research.settle(mail.world)
	t.check("GROW-23",not_early and paused_same and mail.world.facts.research_progress.materials.get("R03",{}).get("kind","")=="mail" and mail.world.facts.research_progress.materials==arrived_materials and not mail.world.facts.research_progress.mail.has("R03") and HospitalLedger.balance(mail.world)==cash,{"not_early":not_early,"paused_same":paused_same,"material":mail.world.facts.research_progress.materials.get("R03",{})})

func _case_24(t) -> void:
	var diagnosis: Dictionary = _research_context()
	# The input hospital has this prior unlock, but no research-progress cache for
	# its next actual diagnosis. This is also a valid migration evidence boundary.
	diagnosis.world.facts.research.append("R19")
	diagnosis.world.touch()
	var initial_readiness: Dictionary = diagnosis.clinic.arrival_readiness(diagnosis.world,"B_S49_D41_M41")
	var opening_handoff: Dictionary = _finish_opening_handoff(diagnosis)
	var diagnosed: Dictionary = {}
	if opening_handoff.cleared:
		diagnosed = _patient(diagnosis,[47,93],"B_S49_D41_M41")
	var evidence_ready: bool = false
	if not diagnosed.is_empty():
		for index: int in 900:
			diagnosis.simulation.step()
			var receipt: Dictionary = diagnosis.world.facts.research_progress.materials.get("R19",{})
			if receipt.get("kind","")=="diagnosis" and receipt.get("visit_id","")==diagnosed.id:
				evidence_ready = true
				break
	diagnosis.world.facts.research_progress.materials.erase("R19")
	diagnosis.research.execute(diagnosis.world,"research_request_mail",{"research_id":"R19"})
	var diagnosis_due: int = int(diagnosis.world.facts.research_progress.mail.get("R19",diagnosis.world.sim_tick))
	diagnosis.world.facts.sim_tick = diagnosis_due
	diagnosis.research.boundaries(diagnosis.world)
	if evidence_ready:
		diagnosis.research.record_diagnostic_work(diagnosis.world,diagnosed,"gp")
	diagnosis.research.settle(diagnosis.world)
	var diagnosis_count: int = diagnosis.world.facts.research_progress.materials.size()
	if evidence_ready:
		diagnosis.research.record_diagnostic_work(diagnosis.world,diagnosed,"gp")
	diagnosis.research.settle(diagnosis.world)
	var diagnosis_details: Dictionary = diagnosis.world.facts.research_progress.materials.get("R19",{}).duplicate(true)
	diagnosis_details.admitted = not diagnosed.is_empty()
	diagnosis_details.evidence_ready = evidence_ready
	diagnosis_details.evidence = diagnosed.get("evidence_by_source",{}).duplicate(true)
	diagnosis_details.initial_readiness = {"ok":initial_readiness.ok,"reason":initial_readiness.reason}
	diagnosis_details.opening_handoff = opening_handoff
	diagnosis_details.admission = diagnosis.get("last_admission",{}).duplicate(true)
	t.check("GROW-24",evidence_ready and diagnosis.world.facts.research_progress.materials.get("R19",{}).get("kind","")=="diagnosis" and diagnosis.world.facts.research_progress.materials.size()==diagnosis_count and not diagnosis.world.facts.research_progress.mail.has("R19"),diagnosis_details)

func _case_25(t) -> void:
	var planning: Dictionary = _research_context()
	var planning_cash: int = HospitalLedger.balance(planning.world)
	for topic: String in ["R03","R12","R12","R14"]:
		planning.research.execute(planning.world,"research_todo_add",{"research_id":topic})
	planning.research.execute(planning.world,"research_todo_move",{"research_id":"R14","index":1})
	planning.research.execute(planning.world,"research_todo_remove",{"research_id":"R14"})
	var after_plan: bool = planning.world.facts.research_progress.todo==["R03","R12"] and planning.world.facts.research_jobs.is_empty() and HospitalLedger.balance(planning.world)==planning_cash and planning.research.preview(planning.world,"R12").ok and not planning.research.preview(planning.world,"R03").ok
	planning.world.facts.research.append("R14")
	var completed_add: CommandResult = planning.research.execute(planning.world,"research_todo_add",{"research_id":"R14"})
	t.check("GROW-25",after_plan and not completed_add.accepted and not "R14" in planning.world.facts.research_progress.todo,{"todo":planning.world.facts.research_progress.todo,"cash":HospitalLedger.balance(planning.world)})

func _case_26(t) -> void:
	var unique: Dictionary = _research_context()
	var unique_cash: int = HospitalLedger.balance(unique.world)
	_material(unique,"R04")
	unique.world.facts.research.append("R02")
	var missing: CommandResult = _start(unique,"R04")
	var no_material: CommandResult = _start(unique,"R01")
	var failed_clean: bool = not missing.accepted and not no_material.accepted and unique.world.facts.research_jobs.is_empty() and HospitalLedger.balance(unique.world)==unique_cash
	var started: CommandResult = _start(unique)
	var twice: CommandResult = _start(unique)
	var unique_job: Dictionary = unique.research.active_job(unique.world,"R12")
	t.check("GROW-26",failed_clean and started.accepted and not twice.accepted and unique.world.facts.research_jobs.size()==1 and HospitalLedger.balance(unique.world)==unique_cash-600 and unique_job.get("cost",-1)==600 and unique_job.get("total_work_milli",0)==1800000,{"first":started.accepted,"second":twice.accepted,"job":unique_job})

func _case_27(t) -> void:
	var waiting: Dictionary = _research_context(false,false)
	var waiting_cash: int = HospitalLedger.balance(waiting.world)
	var default_wait: CommandResult = _start(waiting)
	var default_clean: bool = not default_wait.accepted and waiting.world.facts.research_jobs.is_empty() and HospitalLedger.balance(waiting.world)==waiting_cash
	var allowed_wait: CommandResult = _start(waiting,"R12",{"allow_waiting":true})
	var paid_wait: Dictionary = waiting.research.active_job(waiting.world,"R12")
	var paid_remaining: int = int(paid_wait.get("remaining_work_milli",-1))
	_research_tick(waiting)
	t.check("GROW-27",default_clean and allowed_wait.accepted and HospitalLedger.balance(waiting.world)==waiting_cash-600 and paid_wait.get("state","")=="waiting" and paid_wait.get("remaining_work_milli",-2)==paid_remaining and str(paid_wait.get("worker_id","x")).is_empty(),{"default_clean":default_clean,"job":paid_wait})

func _case_28(t) -> void:
	var community: Dictionary = _research_context()
	var rich_community: CommandResult = _start(community,"R12",{"community":true})
	community.world.facts.ledger.opening_balance -= HospitalLedger.balance(community.world)
	var low_cash: int = HospitalLedger.balance(community.world)
	var community_start: CommandResult = _start(community,"R12",{"community":true})
	var community_job: Dictionary = community.research.active_job(community.world,"R12")
	var doubled: bool = community_job.get("total_work_milli",0)==3600000 and community_job.get("mode","")=="community" and community_job.get("cost",-1)==0
	community.research.execute(community.world,"research_cancel",{"research_id":"R12"})
	t.check("GROW-28",not rich_community.accepted and low_cash==0 and community_start.accepted and doubled and community_job.get("refund",-1)==0 and HospitalLedger.balance(community.world)==0,{"rich_rejected":not rich_community.accepted,"job":community_job})

func _case_29(t) -> void:
	var working: Dictionary = _research_context()
	working.world.facts.actors.research_worker.location.cell = [47,74]
	working.world.touch()
	_start(working)
	var active: Dictionary = working.research.active_job(working.world,"R12")
	var work_before: int = int(active.get("remaining_work_milli",0))
	working.research.dispatch_job(working.world,active)
	working.research.advance(working.world)
	var not_present: bool = active.get("remaining_work_milli",-1)==work_before and active.get("state","")=="travelling"
	for index: int in 150:
		_research_tick(working)
		if active.get("state","")=="working":
			break
	var at_desk: bool = working.space.at(working.world,"research_worker",1,HospitalClinicalDevelopment._operator(working.space.facility_layout(working.world,"research_desk")))
	working.world.facts.staff.research_worker.on_shift = false
	var off_before: int = int(active.get("remaining_work_milli",0))
	working.research.advance(working.world)
	var off_still: bool = active.get("remaining_work_milli",-1)==off_before
	working.world.facts.staff.research_worker.on_shift = true
	working.research.dispatch_job(working.world,active)
	var on_before: int = int(active.get("remaining_work_milli",0))
	working.research.advance(working.world)
	t.check("GROW-29",not_present and at_desk and off_still and int(active.get("remaining_work_milli",on_before))==on_before-1000 and working.research.worked_staff().has("research_worker"),{"not_present":not_present,"at_desk":at_desk,"off_still":off_still,"job":active})

func _case_30(t) -> void:
	var sharing: Dictionary = _research_context()
	sharing.world.facts.research.append("R11")
	var opening_doctor_busy: bool = HospitalClinicalDevelopment.safe_busy(sharing.world,"starter_doctor_a")
	# The first GP's doctor may still own a safe clinical release. The idle third
	# doctor supplies an executable training task, and the desk starts unoccupied.
	sharing.world.facts.staff.starter_doctor_c.schedule[0] = {"kind":"training","pools":[],"locked":false}
	sharing.world.facts.staff.starter_doctor_c.scheduled_kind = "training"
	sharing.world.facts.staff.starter_doctor_c.on_shift = true
	sharing.world.facts.actors.research_worker.location.cell = [47,74]
	sharing.world.touch()
	sharing.space.sync_actor(sharing.world,"research_worker")
	var course: CommandResult = sharing.development.execute(sharing.world,"train_staff",{"staff_id":"starter_doctor_c","track":"diagnosis","desk_id":"research_desk"})
	var shared_start: CommandResult = _start(sharing,"R12",{"allow_waiting":true})
	sharing.development.dispatch(sharing.world)
	var shared_job: Dictionary = sharing.research.active_job(sharing.world,"R12")
	var course_job: Dictionary = sharing.world.facts.training_jobs.get(sharing.world.facts.staff.starter_doctor_c.training_job_id,{})
	var exclusive: bool = course_job.get("desk_id","")=="research_desk" and str(shared_job.get("desk_id","x")).is_empty()
	sharing.research.execute(sharing.world,"research_todo_add",{"research_id":"R12"})
	sharing.research.execute(sharing.world,"research_todo_move",{"research_id":"R12","index":0})
	sharing.development.dispatch(sharing.world)
	var retained_desk: bool = course_job.get("desk_id","")=="research_desk" and str(shared_job.get("desk_id","x")).is_empty()
	var parallel: Dictionary = _research_context()
	_add_facility(parallel.world,"second_research_desk","FUR05","research_room",[43,72])
	HospitalFactory._add_staff(parallel.world,"second_research_worker","研究员二","researcher",[45,72],_content)
	parallel.simulation.services.scheduler.ensure(parallel.world)
	parallel.simulation.services.recruitment.ensure(parallel.world)
	_fresh_space(parallel)
	var one: CommandResult = _start(parallel,"R12",{"desk_id":"research_desk","worker_id":"research_worker"})
	var two: CommandResult = _start(parallel,"R14",{"desk_id":"second_research_desk","worker_id":"second_research_worker"})
	_research_tick(parallel)
	var one_job: Dictionary = parallel.research.active_job(parallel.world,"R12")
	var two_job: Dictionary = parallel.research.active_job(parallel.world,"R14")
	t.check("GROW-30",course.accepted and shared_start.accepted and exclusive and retained_desk and one.accepted and two.accepted and one_job.get("state","")=="working" and two_job.get("state","")=="working" and one_job.get("desk_id","")!=two_job.get("desk_id","") and not _start(parallel,"R12",{"allow_waiting":true}).accepted,{"exclusive":exclusive,"retained":retained_desk,"original_gp_doctor_busy":opening_doctor_busy,"course_accepted":course.accepted,"course_reason":course.reason,"course":course_job,"shared":shared_job,"first":one_job,"second":two_job})

func _case_31(t) -> void:
	var pausing: Dictionary = _research_context()
	_start(pausing)
	_research_tick(pausing)
	var pause_job: Dictionary = pausing.research.active_job(pausing.world,"R12")
	var partial: int = int(pause_job.get("remaining_work_milli",-1))
	var pause_cash: int = HospitalLedger.balance(pausing.world)
	pausing.research.execute(pausing.world,"research_pause",{"research_id":"R12"})
	_research_tick(pausing)
	var released: bool = pause_job.get("state","")=="paused" and str(pause_job.get("desk_id","x")).is_empty() and str(pause_job.get("worker_id","x")).is_empty() and str(pausing.world.facts.staff.research_worker.get("active_job_id","x")).is_empty() and int(pause_job.get("remaining_work_milli",-2))==partial
	pausing.world.facts.staff.research_worker.on_shift = false
	pausing.research.execute(pausing.world,"research_resume",{"research_id":"R12"})
	_research_tick(pausing)
	t.check("GROW-31",partial<1800000 and released and int(pause_job.get("remaining_work_milli",-2))==partial and pause_job.get("state","")=="waiting" and HospitalLedger.balance(pausing.world)==pause_cash,{"released":released,"job":pause_job})

func _case_32(t) -> void:
	var failure: Dictionary = _research_context()
	_start(failure)
	_research_tick(failure)
	var failure_job: Dictionary = failure.research.active_job(failure.world,"R12")
	var failure_remaining: int = int(failure_job.get("remaining_work_milli",-1))
	var failure_cash: int = HospitalLedger.balance(failure.world)
	failure.world.facts.facilities.research_desk.failed = true
	_research_tick(failure)
	var no_failed_work: bool = int(failure_job.get("remaining_work_milli",-2))==failure_remaining and str(failure_job.get("desk_id","x")).is_empty()
	failure.world.facts.facilities.research_desk.failed = false
	var reassigned: CommandResult = failure.research.execute(failure.world,"research_assign",{"research_id":"R12","desk_id":"research_desk","worker_id":"research_worker"})
	_research_tick(failure)
	t.check("GROW-32",no_failed_work and reassigned.accepted and int(failure_job.get("remaining_work_milli",failure_remaining))<failure_remaining and int(failure_job.get("total_work_milli",0))==1800000 and failure_job.get("mode","")=="cash" and HospitalLedger.balance(failure.world)==failure_cash,{"no_failed_work":no_failed_work,"job":failure_job})

func _case_33(t) -> void:
	var cancel: Dictionary = _research_context()
	_start(cancel)
	for index: int in 7:
		_research_tick(cancel)
	var cancelled: Dictionary = cancel.research.active_job(cancel.world,"R12")
	var cancellation_cash: int = HospitalLedger.balance(cancel.world)
	var expected_refund: int = int(cancelled.get("cost",0))*int(cancelled.get("remaining_work_milli",0))/maxi(1,int(cancelled.get("total_work_milli",1)))
	cancel.research.execute(cancel.world,"research_cancel",{"research_id":"R12"})
	var first_refund_cash: int = HospitalLedger.balance(cancel.world)
	cancel.research.execute(cancel.world,"research_cancel",{"research_id":"R12"})
	cancel.research.settle(cancel.world)
	var cancelled_resume: CommandResult = cancel.research.execute(cancel.world,"research_resume",{"research_id":"R12"})
	t.check("GROW-33",cancelled.get("state","")=="cancelled" and int(cancelled.get("refund",-1))==expected_refund and first_refund_cash==cancellation_cash+expected_refund and HospitalLedger.balance(cancel.world)==first_refund_cash and not cancelled_resume.accepted and not "R12" in cancel.world.facts.research and cancel.world.facts.research_progress.materials.has("R12"),{"expected_refund":expected_refund,"job":cancelled})

func _case_34(t) -> void:
	var freezing: Dictionary = _research_context()
	_start(freezing)
	_research_tick(freezing)
	var frozen_job: Dictionary = freezing.research.active_job(freezing.world,"R12")
	var frozen_terms: Dictionary = frozen_job.duplicate(true)
	var changed_data: Dictionary = _content.registry._data.duplicate(true)
	for record: Dictionary in changed_data.collections.research:
		if ContentRegistry.legacy_id(record.id)=="R12":
			record.price = 999
			record.work_seconds = 360
			record.disease_ids = ["core:D37"]
	changed_data.indexes.research["core:R12"].price = 999
	changed_data.indexes.research["core:R12"].work_seconds = 360
	changed_data.indexes.research["core:R12"].disease_ids = ["core:D37"]
	for record: Dictionary in changed_data.catalog.research:
		if ContentRegistry.legacy_id(record.id)=="R12":
			record.price = 999
			record.work_seconds = 360
			record.disease_ids = ["core:D37"]
	var changed_content: HospitalContent = HospitalContent.new()
	changed_content.registry = ContentRegistry.new(changed_data)
	var changed_service: HospitalResearch = HospitalResearch.new(changed_content,HospitalSpace.new(changed_content))
	changed_service.ensure(freezing.world)
	var unchanged_terms: bool = frozen_job.cost==frozen_terms.cost and frozen_job.total_work_milli==frozen_terms.total_work_milli and frozen_job.mode==frozen_terms.mode and frozen_job.rewards==frozen_terms.rewards and frozen_job.remaining_work_milli==frozen_terms.remaining_work_milli
	changed_service.execute(freezing.world,"research_cancel",{"research_id":"R12"})
	var new_preview: Dictionary = changed_service.preview(freezing.world,"R12")
	t.check("GROW-34",unchanged_terms and frozen_job.rewards.disease_ids.is_empty() and new_preview.get("cost",0)==999 and new_preview.get("total_work_milli",0)==3600000 and new_preview.get("basis",{}).get("rewards",{}).get("disease_ids",[])==["D37"] and int(frozen_job.get("refund",-1))==int(frozen_terms.cost)*int(frozen_terms.remaining_work_milli)/int(frozen_terms.total_work_milli),{"old":frozen_terms,"new_quote":new_preview,"cancelled":frozen_job})

func _case_35(t) -> void:
	var completion: Dictionary = _research_context()
	var completion_start: CommandResult = _start(completion)
	var completed_job: Dictionary = completion.research.active_job(completion.world,"R12")
	var finished: bool = _finish_research(completion,"R12")
	var completed_cash: int = HospitalLedger.balance(completion.world)
	var completed_research: Array = completion.world.facts.research.duplicate()
	completion.research.settle(completion.world)
	completion.research.execute(completion.world,"research_cancel",{"research_id":"R12"})
	var restart: CommandResult = _start(completion)
	t.check("GROW-35",completion_start.accepted and finished and completed_job.get("remaining_work_milli",-1)==0 and str(completed_job.get("worker_id","x")).is_empty() and str(completed_job.get("desk_id","x")).is_empty() and "R12" in completed_research and completion.world.facts.research==completed_research and not restart.accepted and HospitalLedger.balance(completion.world)==completed_cash and not completion.world.facts.ledger.entries.has(str(completed_job.get("id",""))+":research_refund"),{"finished":finished,"job":completed_job})

func _case_36(t) -> void:
	var routes: Dictionary = _research_context()
	var route_world: Dictionary = routes.world.freeze()
	var targets: Array = [["R19","R32"],["R01","R21","R15"],["R07","R25"],["R16","R33","R34"],["R09","R31","R38"],["R11","R12","R13","R17"]]
	var route_ok: bool = _content.catalog.research_trails.size()==6
	for index: int in 6:
		var route_id: String = "RT%02d"%(index+1)
		var definition: Dictionary = _content.definition("research_trails",route_id)
		var expanded: Array = routes.research.trail_research(route_id)
		route_ok = route_ok and definition.get("research_ids",[])==targets[index]
		for topic: String in expanded:
			for prerequisite: String in _content.definition("research",topic).requires:
				route_ok = route_ok and prerequisite in expanded and expanded.find(prerequisite)<expanded.find(topic)
		for target: String in targets[index]:
			route_ok = route_ok and target in expanded
		routes.research.trail_research(route_id)
	t.check("GROW-36",route_ok and routes.world.freeze()==route_world,{"valid_routes":route_ok,"world_unchanged":routes.world.freeze()==route_world})

func _case_37(t) -> void:
	var unlocking: Dictionary = _research_context()
	_material(unlocking,"R01")
	var unlock_start: CommandResult = _start(unlocking,"R01")
	var unlock_finished: bool = _finish_research(unlocking,"R01")
	var unlock_rewards: Dictionary = unlocking.research.rewards(unlocking.world,"R01")
	var unbuilt: Array = unlocking.research.reception_readiness(unlocking.world,"R01")
	var missing_real_resources: bool = not unbuilt.is_empty()
	for row: Dictionary in unbuilt:
		missing_real_resources = missing_real_resources and not row.ok and not str(row.reason).is_empty()
	var actual_before: Dictionary = {"actors":unlocking.world.facts.actors.duplicate(true),"facilities":unlocking.world.facts.facilities.duplicate(true),"staff":unlocking.world.facts.staff.duplicate(true),"intake":unlocking.world.facts.arrivals.intake_open}
	unlocking.research.reception_readiness(unlocking.world,"R01")
	var ordinary: Dictionary = _context()
	var ordinary_ready: Dictionary = ordinary.clinic.arrival_readiness(ordinary.world,"B_S49_D37_M37")
	t.check("GROW-37",unlock_start.accepted and unlock_finished and "R01" in unlocking.world.facts.research and unlock_rewards.get("disease_ids",[])==["D03","D04","D25"] and missing_real_resources and unlocking.world.facts.actors==actual_before.actors and unlocking.world.facts.facilities==actual_before.facilities and unlocking.world.facts.staff==actual_before.staff and unlocking.world.facts.arrivals.intake_open==actual_before.intake and ordinary_ready.get("ok",false),{"finished":unlock_finished,"missing":unbuilt,"ordinary_ready":ordinary_ready})

func _case_38(t) -> void:
	var restoring: Dictionary = _research_context()
	_start(restoring)
	for index: int in 7:
		_research_tick(restoring)
	restoring.research.execute(restoring.world,"research_request_mail",{"research_id":"R03"})
	restoring.research.execute(restoring.world,"research_todo_add",{"research_id":"R03"})
	restoring.research.execute(restoring.world,"research_todo_add",{"research_id":"R14"})
	var restore_facts: Dictionary = restoring.world.freeze()
	var restored_world: WorldState = WorldState.new(restore_facts.duplicate(true))
	var restored_sim: HospitalSimulation = HospitalSimulation.new(restored_world,_content)
	_simulations.append(restored_sim)
	var restored_research: HospitalResearch = restored_sim.services.research
	var restored_job: Dictionary = restored_research.active_job(restored_world,"R12")
	var saved_job: Dictionary = restoring.research.active_job(restoring.world,"R12")
	var preserved: bool = restored_world.facts.research_progress==restore_facts.research_progress and restored_job==saved_job and restored_world.facts.research==restore_facts.research
	restored_world.facts.staff.research_worker.on_shift = false
	restored_research.advance(restored_world)
	t.check("GROW-38",preserved and int(restored_job.get("remaining_work_milli",-1))==int(saved_job.get("remaining_work_milli",-2)) and str(restored_job.get("worker_id","x")).is_empty() and str(restored_job.get("desk_id","x")).is_empty() and restored_research.validate(restored_world).is_empty(),{"preserved":preserved,"job":restored_job,"validation":restored_research.validate(restored_world)})
