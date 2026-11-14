extends "res://tests/acceptance/growth_fixtures.gd"

const CASES: Dictionary = {
	"GROW-01":"docs/design/11-growth-arrivals-recruitment.md §1.1/1.2；无诊桌零机会且不抽签",
	"GROW-03":"docs/design/11-growth-arrivals-recruitment.md §1.1；诊桌需求查询只读且病症权重不重算兴趣",
	"GROW-04":"docs/design/11-growth-arrivals-recruitment.md §1.1；立即关诊不改变诊桌需求",
	"GROW-06":"docs/design/11-growth-arrivals-recruitment.md §1.2；三班固定时刻向量",
	"GROW-07":"docs/design/11-growth-arrivals-recruitment.md §1.2；零兴趣份额不分配机会",
	"GROW-08":"docs/design/11-growth-arrivals-recruitment.md §1.2；计划恢复及查询不重抽",
	"GROW-09":"docs/design/01-simulation.md §5；明日档位与立即关诊",
	"GROW-10":"docs/design/11-growth-arrivals-recruitment.md §1.2.1；关诊早排除不查病例或抽患者",
	"GROW-11":"docs/design/11-growth-arrivals-recruitment.md §1.1/1.2.1；离院途中仍计门诊，员工不计入门诊额度",
	"GROW-12":"docs/design/11-growth-arrivals-recruitment.md §1.2.1；同tick逐机会重读额度",
	"GROW-13":"docs/design/11-growth-arrivals-recruitment.md §1.2.1；缺治疗设备仍自然入院且机会不补发",
	"GROW-14":"docs/design/11-growth-arrivals-recruitment.md §2；弃候概率公式与环境缓冲",
	"GROW-15":"docs/design/11-growth-arrivals-recruitment.md §2/2.1；120秒首签与每30秒唯一签",
	"GROW-16":"docs/design/11-growth-arrivals-recruitment.md §2.1；生活暂离保留有效候诊余量",
	"GROW-17":"docs/design/11-growth-arrivals-recruitment.md §2；安全排除及确定退出先于概率",
	"GROW-18":"docs/design/04-technical.md §6患者耐心的到期索引；恢复不重抽旧门槛",
	"GROW-19":"docs/design/11-growth-arrivals-recruitment.md §1.3；实际离院及两个完整日窗口",
	"GROW-20":"docs/design/11-growth-arrivals-recruitment.md §1.3；20%患者复诊与最久离院身份选择",
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
	"GROW-37":"docs/design/01-simulation.md §9.4；研究解锁允许入院但实际治疗仍解释缺项",
	"GROW-38":"docs/design/04-technical.md §4研究进度；资料简报排序与任务恢复",
	"GROW-56":"统一规格§14；门诊候选由真实房间班表与诊断资格决定，病例与遍历顺序不改变合法岗位",
	"GROW-57":"docs/design/07-clinical-team.md §6；三种方案策略遵守成功率边界及稳定顺序",
	"GROW-60":"docs/design/07-clinical-team.md §5；候选使用已证明的适配站位且不修改实际预约",
	"GROW-67":"docs/design/07-clinical-team.md；活动病例索引、归档与恢复",
	"GROW-68":"docs/design/07-clinical-team.md §5；只读占用视图边界与实际新预约可见",
	"GROW-72":"docs/design/08-hospital-life.md §4；弃候与常驻环境使用同一本人可用性且报价只读",
	"GROW-75":"docs/design/08-hospital-life.md §4；正向来源交集、按来源覆盖与同次主体观察",
	"GROW-76":"docs/design/07-clinical-team.md §5；候选早排除不装配占用或员工ID，实际接待预约立即对后票生效",
	"GROW-78":"docs/design/04-technical.md §6；参考路线按完整主体与组包络区分且冷热一致",
	"GROW-83":"docs/design/11-growth-arrivals-recruitment.md §1.3；居民保护批次保持在院身份、完整原因与查询边界",
	"GROW-85":"docs/design/01-simulation.md §9.2；研究历史索引复用保留付款、暂停、取消、恢复与原序",
	"GROW-86":"docs/design/11-growth-arrivals-recruitment.md §1.2.1；单次病例选择复用保留权重、解锁变更和病症抽签"
}

func run(t) -> void:
	_content = HospitalContent.new()
	_cache = t.checkpoints(_content,"res://tests/acceptance/growth_fixtures.gd",self)
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


func _case_85(t) -> void:
	await preload("res://tests/acceptance/growth_repeated_work.gd").new().run(t,_content,_cache)

func _case_86(t) -> void:
	preload("res://tests/acceptance/admission_weights.gd").new().run(t,_content,_context())

func _case_01(t) -> void:
	var empty: Dictionary = _context(false)
	# This case, unlike the fixed-day fixtures, exercises real plan generation.
	empty.world.facts.arrivals.plan.clear()
	var rng_before: Dictionary = empty.world.facts.rng.duplicate(true)
	empty.arrivals.boundaries(empty.world)
	var zero: Dictionary = empty.world.facts.arrivals.plan
	t.check("GROW-01",not zero.is_empty() and zero.opportunity_count==0 and zero.shift_opportunity_counts==[0,0,0] and zero.schedule_seed==null and zero.shift_capacities==[F.make(),F.make(),F.make()] and empty.world.facts.rng==rng_before,zero)

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
	t.check("GROW-03",capacity==repeated and unchanged and outside==capacity and outside_unchanged and no_cases==capacity and restored==capacity,{"same_projection":capacity==repeated,"world_unchanged":unchanged,"temporary_positions_independent":outside==capacity,"empty_weighted_pool":no_cases.get("capacity",{}),"restored_weights":restored==capacity})

func _case_83(t) -> void:
	load("res://tests/acceptance/clinical_query_batches.gd").new().run_case(t,_content)

func _case_56(t) -> void:
	var input: Dictionary=_clinical_query_input(_context(),"B_S13_D09_M09")
	if not input.ok:
		t.check("GROW-56",false,{"input":input});return
	var world: WorldState=input.world
	var first: String="starter_doctor_a"
	var second: String="starter_doctor_b"
	for staff: Dictionary in world.facts.staff.values():
		staff.schedule=[{"kind":"rest","pools":[],"locked":false},{"kind":"rest","pools":[],"locked":false},{"kind":"rest","pools":[],"locked":false}]
	for id: String in [first,second]:
		world.facts.staff[id].schedule[0]={"kind":"outpatient","pools":["room_gp"],"locked":false}
		world.facts.staff[id].abilities.diagnosis=1 if id==first else 0
	world.touch()
	var selection: Dictionary={"facility_id":"gp_station"}
	var initial: Array=input.clinic.service_candidates(world,input.visit,"gp",true,true,selection)
	world.facts.staff[second].abilities.diagnosis=1
	world.touch()
	var before: Dictionary=world.freeze()
	var forward: Array=input.clinic.service_candidates(world,input.visit,"gp",true,true,selection)
	var reversed: Dictionary=selection.duplicate();reversed.staff_id=second
	var only_second: Array=input.clinic.service_candidates(world,input.visit,"gp",true,true,reversed)
	var actual: Array=[]
	for pair: Dictionary in forward: actual.append(pair.staff_id)
	t.check("GROW-56",initial==[{"facility_id":"gp_station","staff_id":first}] and actual==[first,second] and only_second==[{"facility_id":"gp_station","staff_id":second}] and world.freeze()==before,{"checks":{"ability_zero_excluded":initial==[{"facility_id":"gp_station","staff_id":first}],"both_qualified_retained":actual==[first,second],"queries_read_only":world.freeze()==before},"pairs":forward,"explicit_second":only_second})

func _case_57(t) -> void:
	var ctx: Dictionary=_context()
	var quotes: Array=[{"plan_id":"P_D09_COMMON","score":100.0,"probability_bp":7900,"work_ticks":100},{"plan_id":"P_D09_GENTLE","score":90.0,"probability_bp":8300,"work_ticks":200}]
	var correct: bool=ctx.clinic._choose_plan(quotes,"doctor").plan_id=="P_D09_COMMON" and ctx.clinic._choose_plan(quotes,"safety_first").plan_id=="P_D09_GENTLE" and ctx.clinic._choose_plan(quotes,"outpatient_first").plan_id=="P_D09_GENTLE"
	quotes[0].probability_bp=8000
	correct=correct and ctx.clinic._choose_plan(quotes,"outpatient_first").plan_id=="P_D09_COMMON"
	var reverse: Array=quotes.duplicate();reverse.reverse()
	for strategy: String in ["doctor","safety_first","outpatient_first"]:
		correct=correct and ctx.clinic._choose_plan(quotes,strategy).plan_id==ctx.clinic._choose_plan(reverse,strategy).plan_id
	t.check("GROW-57",correct,{"outpatient_priority_boundary_bp":8000,"stable_under_reverse_input":correct})

func _case_60(t) -> void:
	var candidate: Dictionary=_clinical_query_input(_context(),"B_S13_D09_M09")
	if not candidate.ok:
		t.check("GROW-60",false,{"input":candidate});return
	var world: WorldState=candidate.world
	var before: Dictionary=world.freeze()
	var pairs: Array=candidate.clinic.service_candidates(world,candidate.visit,"gp",true)
	var checked: int=0
	var correct: bool=not pairs.is_empty()
	for pair: Dictionary in pairs:
		var copy: WorldState=WorldState.new(world.freeze())
		var reason: String=candidate.space.reserve_facility(copy,pair.facility_id,candidate.visit.actor_id,candidate.visit.id,[pair.staff_id])
		var layout: Dictionary=candidate.space.facility_layout(copy,pair.facility_id)
		correct=correct and reason.is_empty() and candidate.space.route(copy,candidate.visit.actor_id,int(layout.floor_id),layout.patient_cell,[],{},true).ok and candidate.space.route(copy,pair.staff_id,int(layout.floor_id),layout.operator_cells[0],[],{},true).ok
		checked+=1
	t.check("GROW-60",correct and checked>0 and world.freeze()==before,{"checked":checked,"readonly":world.freeze()==before})

class CandidateIdCounts extends WorldState:
	var staff_id_reads: int = 0
	func ids(collection: String) -> Array:
		if collection=="staff": staff_id_reads += 1
		return super.ids(collection)

class QuoteCounts extends HospitalClinic:
	var availability_calls: int = 0
	func _build_availability(world: WorldState) -> Dictionary:
		availability_calls += 1
		return super._build_availability(world)

func _case_67(t) -> void:
	var ctx: Dictionary = _context()
	var visit: Dictionary = _patient(ctx,[45,76])
	if visit.is_empty():
		t.check("GROW-67",false,ctx.last_admission)
		return
	var correct: bool = true
	var counts: Array = []
	ctx.world.facts.sim_tick = 1000
	for index: int in 256:
		var id: String = "archived_%04d"%index
		var actor_id: String = id+"_actor"
		var archived: Dictionary = visit.duplicate(true)
		archived.merge({"id":id,"actor_id":actor_id,"arrival_key":id,"phase":"departed","ticket_id":"","final_result":"referred","departed_tick":0,"departure_recorded":true},true)
		var actor: Dictionary = ctx.world.facts.actors[visit.actor_id].duplicate(true)
		actor.merge({"id":actor_id,"location":{"kind":"outside"}},true)
		ctx.world.facts.visits[id] = archived
		ctx.world.facts.actors[actor_id] = actor
		ctx.world.facts.arrival_receipts[id] = id
		if index+1 in [16,64,256]:
			var before: Dictionary = ctx.world.freeze()
			var ids: Array = ctx.world.active_visit_ids()
			var restored: WorldState = WorldState.new(before.duplicate(true))
			correct = correct and ids==[visit.id] and restored.active_visit_ids()==ids and ctx.world.freeze()==before and ctx.world.validate(_content).is_empty()
			counts.append({"history":index+1,"active":ids.size()})
	# A same-sized replacement must invalidate ordered IDs even inside one tick.
	var ids_before: Array = ctx.world.ids("arrival_receipts")
	ctx.world.facts.arrival_receipts.erase("archived_0000")
	ctx.world.facts.arrival_receipts.replacement = "archived_0000"
	ctx.world.facts.visits.archived_0000.arrival_key = "replacement"
	var ids_after: Array = ctx.world.ids("arrival_receipts")
	correct = correct and ids_before!=ids_after and "replacement" in ids_after and not "archived_0000" in ids_after
	ids_after.clear()
	correct = correct and not ctx.world.ids("arrival_receipts").is_empty() and ctx.world.validate(_content).is_empty()
	t.check("GROW-67",correct,{"scales":counts,"validation":ctx.world.validate(_content)})

func _case_68(t) -> void:
	var ctx: Dictionary = _context()
	var visit: Dictionary = _admit_fixture(ctx,"B_S49_D37_M37", "acceptance_occupancy")
	if visit.is_empty():
		t.check("GROW-68",false,ctx.last_admission)
		return
	var observer: QuoteCounts = QuoteCounts.new(_content,ctx.space)
	ctx.space.begin_route_query(ctx.world)
	var first: Dictionary = observer._availability(ctx.world)
	var second: Dictionary = observer._availability(ctx.world)
	ctx.space.end_route_query()
	var shared: bool = observer.availability_calls==1 and is_same(first,second)
	# Registration reserves space first. Walk and start the real service before
	# checking the clinical owners; no preparation exists for an unassigned diagnosis.
	var ticks: int = 0
	while ctx.world.facts.sessions.is_empty() and ticks<1200 and not visit.phase in ["leaving","departed"]:
		ctx.simulation.step()
		ticks += 1
	var next: Dictionary = observer._availability(ctx.world)
	var fresh: Dictionary = observer._build_availability(ctx.world)
	var environment: HospitalEnvironment = ctx.simulation.services.environment
	var builds: int = environment.query_builds
	var before: Dictionary = ctx.world.freeze()
	environment.begin_query(ctx.world)
	environment.begin_query(ctx.world)
	var a: Dictionary = environment.environment_at(ctx.world,1,[45,76],visit.actor_id)
	environment.end_query()
	var b: Dictionary = environment.environment_at(ctx.world,1,[45,76],visit.actor_id)
	environment.end_query()
	var readonly: bool = ctx.world.freeze()==before
	var uses: Dictionary = HospitalClinic.equipment_uses(ctx.world)
	var use_equal: bool = true
	for id: String in ctx.world.facts.facilities:
		use_equal = use_equal and HospitalEquipmentUse.query(ctx.world,id,uses)==HospitalEquipmentUse.query(ctx.world,id)
	t.check("GROW-68",shared and next==fresh and not ctx.world.facts.sessions.is_empty() and next!=first and a==b and environment.query_builds==builds+1 and environment._query.is_empty() and readonly and use_equal,{"shared":shared,"new_sessions":ctx.world.facts.sessions.size(),"ticks":ticks,"new_occupancy_seen":next!=first,"environment_builds":environment.query_builds-builds,"readonly":readonly,"visit_phase":visit.phase,"waiting_reason":visit.waiting_reason,"guidance":ctx.simulation.clinic.floor_guidance.state(ctx.world,visit.id)})

func _case_78(t) -> void:
	load("res://tests/acceptance/reference_route_envelope.gd").new().run_case(t,_content)

func _case_76(t) -> void:
	var ctx: Dictionary = _context()
	var first: Dictionary = _patient(ctx,[45,76])
	var second: Dictionary = _patient(ctx,[44,76])
	if first.is_empty() or second.is_empty():
		t.check("GROW-76",false,{"admission":ctx.get("last_admission",{})})
		return
	# This snapshot is the legal before-dispatch input. The counter delegates
	# every ID query to WorldState and does not replace any production result.
	var world: CandidateIdCounts = CandidateIdCounts.new(ctx.world.freeze())
	ctx.world = world
	ctx.simulation.world = world
	first = world.facts.visits[first.id]
	second = world.facts.visits[second.id]
	for staff_id: String in world.facts.staff:
		if world.facts.staff[staff_id].role=="doctor" and staff_id!="starter_doctor_a": world.facts.staff[staff_id].on_shift = false
	# This candidate/reservation boundary begins after ordinary base preparation.
	world.facts.staff.starter_doctor_a.base_prepared = true
	var validation: String = world.validate(_content)
	world.staff_id_reads = 0
	var observer: QuoteCounts = QuoteCounts.new(_content,ctx.space)
	var before: Dictionary = world.freeze()
	var all: Array = observer.service_candidates(world,first,"gp")
	var first_only: Array = observer.service_candidates(world,second,"gp",false,false,{"first_only":true})
	var independent_builds: int = observer.availability_calls
	var independent_reads: int = world.staff_id_reads
	var independent: bool = all.size()==1 and first_only==all and independent_builds==2 and independent_reads==2 and ctx.space._route_queries.is_empty() and world.freeze()==before
	observer.availability_calls = 0
	world.staff_id_reads = 0
	var structural: Array = observer.service_candidates(world,second,"gp",true,false,{"staff_id":"starter_doctor_a","first_only":true})
	var structural_readonly: bool = structural==all and observer.availability_calls==0 and world.staff_id_reads==0 and ctx.space._route_queries.is_empty() and world.freeze()==before
	var first_ticket: Dictionary = world.facts.tickets[first.ticket_id]
	var second_ticket: Dictionary = world.facts.tickets[second.ticket_id]
	var second_identity: Array = [second_ticket.id,second_ticket.enqueued_tick]
	# The first real dispatcher, rather than an injected busy fact, reserves
	# the sole diagnostic point and requests actual patient/staff movement.
	ctx.clinic._dispatch_service(world,first,first_ticket)
	var held: Dictionary = world.facts.adaptations.get(str(all[0].facility_id) if not all.is_empty() else "",{})
	var reserved: bool = first_ticket.get("service_assigned",false) and held.get("owner_id","")==first_ticket.id and held.get("actor_id","")==first.actor_id and world.facts.moves.has(first.actor_id)
	before = world.freeze()
	observer.availability_calls = 0
	world.staff_id_reads = 0
	var blocked: Array = observer.service_candidates(world,second,"gp",false,false,{"first_only":true})
	var blocked_builds: int = observer.availability_calls
	var blocked_reads: int = world.staff_id_reads
	var early: bool = blocked.is_empty() and blocked_builds==0 and blocked_reads==0 and ctx.space._route_queries.is_empty() and world.freeze()==before
	ctx.clinic._dispatch_service(world,second,second_ticket)
	var original_ticket: bool = [second_ticket.id,second_ticket.enqueued_tick]==second_identity and second.ticket_id==second_ticket.id and not second_ticket.get("service_assigned",false) and world.facts.adaptations==before.adaptations and world.facts.ledger==before.ledger and world.facts.rng==before.rng
	validation += world.validate(_content)
	t.check("GROW-76",independent and structural_readonly and reserved and early and original_ticket and validation.is_empty(),{"independent_queries":independent,"pairs":all,"first_only":first_only,"reason":first.waiting_reason,"structural_readonly":structural_readonly,"actual_reservation":reserved,"blocked_without_views":early,"independent_availability_builds":independent_builds,"independent_staff_id_reads":independent_reads,"blocked_availability_builds":blocked_builds,"blocked_staff_id_reads":blocked_reads,"original_ticket":original_ticket,"validation":validation})

func _case_75(t) -> void:
	var ctx: Dictionary = _context()
	var visit: Dictionary = _patient(ctx,[45,76])
	_add_facility(ctx.world,"environment_plant","FUR25",null,[42,79])
	_add_facility(ctx.world,"environment_light","FUR19",null,[46,80])
	_add_facility(ctx.world,"environment_screen","FUR23",null,[44,82])
	ctx.world.facts.research.append("R15")
	var environment: EnvironmentObserver = EnvironmentObserver.new(_content,ctx.space)
	environment.waiting_life = ctx.simulation.services.waiting
	var correct: bool = true
	var seen_water: Dictionary = {}
	for amenity: Dictionary in _content.catalog.get("amenity_services",[]):
		if amenity.get("purpose","")=="water":
			for field: String in ["ordinary_facility_id","universal_facility_id"]:
				if not str(amenity.get(field,"")).is_empty(): seen_water[str(amenity[field])] = true
	for id: String in ctx.world.facts.facilities:
		var definition_id: String = ctx.world.facts.facilities[id].definition_id
		var original: Dictionary = _content.facility_definition(definition_id)
		var classified: Dictionary = environment._positive_definition(definition_id)
		correct = correct and classified.decoration==original.get("passive_decoration",false) and classified.light==(original.get("environment","")=="light" or original.get("environment_function","")=="light") and classified.has("category")==original.has("decoration_category") and environment._is_water(definition_id)==seen_water.has(definition_id)
	for id: String in seen_water: correct = correct and environment._is_water(id)
	var before: Dictionary = ctx.world.freeze()
	# Explicitly retain the original raw-source reference for scoped sampling.
	var complete: Dictionary = environment._observe_at(ctx.world,1,[44,80],visit.actor_id,true,true)
	var brief: Dictionary = environment._observe_at(ctx.world,1,[44,80],visit.actor_id,false,true)
	var expected_brief: Dictionary = complete.duplicate(true)
	expected_brief.sources = []
	environment.begin_query(ctx.world)
	var edges: Dictionary = environment._coverage_edges(ctx.world,1)
	var positive_ids: Dictionary = {}
	for cells: Dictionary in environment._query.facilities.values():
		for facilities: Array in cells.values():
			for id: String in facilities: positive_ids[id] = true
	var filtered: bool = positive_ids.has("environment_plant") and positive_ids.has("environment_light") and positive_ids.has("water")
	filtered = filtered and not positive_ids.has("bin") and not positive_ids.has("environment_screen") and "environment_screen" in environment._query.screens.get(1,[])
	var sparse_ids: Array = []
	for facility: Dictionary in environment._positive_facilities(ctx.world,1,environment._coverage(ctx.world,1,[44,80],5,false,edges)): sparse_ids.append(facility.id)
	sparse_ids.sort()
	var dense: Array = environment._positive_facilities(ctx.world,1,environment._coverage(ctx.world,1,[42,79],0,false,edges))
	var intersections: bool = sparse_ids==["environment_light","environment_plant"] and dense.size()==1 and dense[0].id=="environment_plant"
	environment.coverage_queries.clear()
	var indexed: Dictionary = environment.environment_at(ctx.world,1,[44,80],visit.actor_id)
	var nearby_before: int = environment.nearby_queries
	var sample: Dictionary = environment.sample_at(ctx.world,1,[44,80],visit.actor_id)
	var expected_sample: Dictionary = expected_brief.duplicate(true)
	expected_sample.erase("nearby_count")
	var sampling: bool = brief==expected_brief and indexed==complete and sample==expected_sample and environment.nearby_queries==nearby_before
	var positive_only: bool = environment.coverage_queries.size()==2
	for query: Dictionary in environment.coverage_queries: positive_only = positive_only and query.radius==5 and not query.noise
	environment.end_query()
	var readonly: bool = ctx.world.freeze()==before
	var empty_sources: bool = _empty_environment_sources()
	environment.calls = 0
	environment.sample_calls = 0
	environment.nearby_queries = 0
	var department: HospitalExperience = ctx.simulation.services.experience
	department.environment = environment
	department.ensure(ctx.world)
	ctx.world.facts.patient_experience.experience[visit.id].next_anger_tick = ctx.world.sim_tick
	department.sample(ctx.world)
	var worker_checks: Dictionary = preload("res://tests/acceptance/worker_sample_checks.gd").new().run(self,_content)
	t.check("GROW-75",worker_checks.ok and correct and filtered and intersections and sampling and positive_only and empty_sources and readonly and environment.calls==1 and environment.sample_calls==1 and environment.nearby_queries==0 and environment._query.is_empty(),{"classification_equal":correct,"filtered_sources":filtered,"intersections":intersections,"sampling_equal":sampling,"positive_coverage_only":positive_only,"empty_sources":empty_sources,"readonly":readonly,"environment_calls":environment.calls,"sample_calls":environment.sample_calls,"nearby_queries":environment.nearby_queries,"scope_balanced":environment._query.is_empty(),"worker_sample_checks":worker_checks})

func _empty_environment_sources() -> bool:
	var ctx: Dictionary = _context(false)
	var environment: EnvironmentObserver = EnvironmentObserver.new(_content,ctx.space)
	var before: Dictionary = ctx.world.freeze()
	environment.begin_query(ctx.world)
	var clean: Dictionary = environment.sample_at(ctx.world,1,[44,80])
	var absent: bool = clean.value==43 and clean.clean and clean.dirt==0 and clean.noise==0 and not clean.water and environment.coverage_queries.is_empty() and environment.edge_queries==0
	environment.end_query()
	absent = absent and ctx.world.freeze()==before
	var patch: String = environment.spawn_dirt(ctx.world,"CL01","environment_spill","environment_spill_once",1,[44,80])
	before = ctx.world.freeze()
	environment.coverage_queries.clear()
	environment.begin_query(ctx.world)
	var dirty: Dictionary = environment.sample_at(ctx.world,1,[44,80])
	var negative_only: bool = not patch.is_empty() and dirty.value==31 and not dirty.clean and dirty.dirt==1 and dirty.noise==0 and environment.coverage_queries.size()==1
	if not environment.coverage_queries.is_empty(): negative_only = negative_only and environment.coverage_queries[0].radius==4 and not environment.coverage_queries[0].noise
	environment.end_query()
	return absent and negative_only and ctx.world.freeze()==before and environment._query.is_empty()

class EnvironmentObserver extends HospitalEnvironment:
	var calls: int = 0
	var sample_calls: int = 0
	var nearby_queries: int = 0
	var edge_queries: int = 0
	var coverage_queries: Array = []
	func environment_at(world: WorldState, floor_id: int, cell: Array, actor_id: String = "", explain: bool = true) -> Dictionary:
		calls += 1
		return super.environment_at(world,floor_id,cell,actor_id,explain)
	func sample_at(world: WorldState, floor_id: int, cell: Array, actor_id: String = "") -> Dictionary:
		calls += 1
		sample_calls += 1
		return super.sample_at(world,floor_id,cell,actor_id)
	func _nearby_actors(world: WorldState, floor_id: int, cell: Array) -> Array:
		nearby_queries += 1
		return super._nearby_actors(world,floor_id,cell)
	func _coverage_edges(world: WorldState, floor_id: int) -> Dictionary:
		edge_queries += 1
		return super._coverage_edges(world,floor_id)
	func _coverage(world: WorldState, floor_id: int, origin: Array, radius: int, noise: bool, edges: Dictionary = {}) -> Dictionary:
		coverage_queries.append({"radius":radius,"noise":noise})
		return super._coverage(world,floor_id,origin,radius,noise,edges)

func _case_72(t) -> void:
	var ctx: Dictionary = _context()
	var visit: Dictionary = _patient(ctx,ctx.world.facts.facilities.water.patient_cell)
	var injected: bool = ctx.arrivals.environment==ctx.simulation.services.environment
	var observation: EnvironmentObserver = EnvironmentObserver.new(_content,ctx.space)
	observation.waiting_life = ctx.simulation.services.waiting
	ctx.arrivals.environment = observation
	var actor: Dictionary = ctx.world.facts.actors[visit.actor_id]
	var before: Dictionary = ctx.world.freeze()
	observation.begin_query(ctx.world)
	var expected: Dictionary = observation.environment_at(ctx.world,int(actor.location.floor_id),actor.location.cell,actor.id)
	var coverage_before: int = observation.coverage_queries.size()
	var sampled: Dictionary = observation.sample_at(ctx.world,int(actor.location.floor_id),actor.location.cell,actor.id)
	var sampled_coverages: int = observation.coverage_queries.size()-coverage_before
	var expected_sample: Dictionary = expected.duplicate(true)
	expected_sample.sources = []
	expected_sample.erase("nearby_count")
	var actual: float = ctx.arrivals._environment_score(ctx.world,visit)
	observation.end_query()
	var standalone: HospitalArrivalService = HospitalArrivalService.new(_content,ctx.space)
	var independent: float = standalone._environment_score(ctx.world,visit)
	t.check("GROW-72",injected and observation.calls==3 and observation.sample_calls==2 and sampled_coverages==1 and sampled==expected_sample and actual==float(expected.value) and independent==actual and ctx.world.freeze()==before,{"injected":injected,"calls":observation.calls,"sample_calls":observation.sample_calls,"sampled_coverages":sampled_coverages,"sampling_equal":sampled==expected_sample,"shared":actual,"standalone":independent,"readonly":ctx.world.freeze()==before})

func _case_04(t) -> void:
	var base: Dictionary = _context()
	_single_case(base)
	var capacity: Dictionary = base.arrivals.capacity(base.world,false)
	base.arrivals.execute(base.world,"arrivals_intake",{"open":false})
	var closed_capacity: Dictionary = base.arrivals.capacity(base.world,false)
	t.check("GROW-04",closed_capacity.get("capacity",{})==capacity.get("capacity",{}) and closed_capacity.get("shift_pairs",[])==capacity.get("shift_pairs",[]),closed_capacity)

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
	var cached: bool = true
	var slot_service: HospitalArrivalService = restore.arrivals
	for probe: Dictionary in [vector.duplicate(true),vector.duplicate(true),_vector_plan(restored)]:
		for index: int in int(probe.opportunity_count):
			cached = cached and slot_service._next_slot_tick(restored,probe,index)==DayPlan.slot_tick(probe,index)
			cached = cached and slot_service._next_slot_tick(restored,probe,index)==DayPlan.slot_tick(probe,index)
		for field: String in ["day_index","schedule_seed","schedule_algorithm","shift_opportunity_counts"]:
			var changed: Dictionary = probe.duplicate(true)
			match field:
				"day_index": changed.day_index += 1
				"schedule_seed": changed.schedule_seed = "987654321"
				"schedule_algorithm": changed.schedule_algorithm = "arrival-slot-v1"
				"shift_opportunity_counts": changed.shift_opportunity_counts = [0,0,int(changed.opportunity_count)]
			cached = cached and slot_service._next_slot_tick(restored,changed,0)==DayPlan.slot_tick(changed,0)
	var wide: Dictionary = F.make("18446744073709551616","3")
	var exact: bool = F.add(wide,F.make(2,3))==F.make("6148914691236517206")
	exact = exact and F.add(F.make("999999999999999999"),F.make("999999999999999999"))==F.make("1999999999999999998")
	exact = exact and F.make("999999999999999999",7)==F.make("142857142857142857")
	exact = exact and F.floor_value(wide)==6148914691236517205 and F.ceil_value(wide)==6148914691236517206
	t.check("GROW-08",cached and exact and restored_ticks==_slot_ticks(vector) and restored.facts.arrivals.plan==vector and restored.facts.rng==restore_rng and not vector.has("slot_ticks") and DayPlan.validate(vector).is_empty(),{"plan":restored.facts.arrivals.plan,"wide_exact_fractions":exact,"same_slot_cache_full_readset":cached})

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
		var before_departure: int = counting.arrivals.outpatient_count(counting.world)
		var selected: bool = counting.clinic.depart_visit(counting.world,second.id,"referred")
		var before_query: Dictionary = counting.world.freeze()
		var leaving_count: int = counting.arrivals.outpatient_count(counting.world)
		var read_only: bool = before_query==counting.world.freeze()
		# Bed reservation versus actual admission is exercised by CLIN-38's
		# real diagnosis, reservation, walk and first-admission prefix.
		count_passed = selected and before_departure==2 and leaving_count==2 and second.phase=="leaving" and counting.world.facts.actors[second.actor_id].location.kind=="floor" and counting.world.facts.staff.size()>0 and counting.world.present_actor_count()>leaving_count and read_only
		count_details = {"before":before_departure,"leaving":leaving_count,"staff_excluded":counting.world.facts.staff.size(),"read_only":read_only}
	t.check("GROW-11",count_passed,count_details)

func _case_12(t) -> void:
	var batch: Dictionary = _context()
	_single_case(batch,"D37")
	for index: int in 15:
		_patient(batch,[34+(index%10)*2,65+(index/10)*2])
	var batch_observer: AdmissionObserver = _observer(batch)
	# A legitimate frozen high-throughput day may outlive a later resource reduction.
	# At 18,000 opportunities in the first shift, exactly its first three are tick 0.
	batch.world.facts.arrivals.plan = _plan(batch.world,18000,[18000,0,0],[F.make(20000),F.make(),F.make()])
	batch.arrivals.arrivals(batch.world)
	var batch_stats: Dictionary = batch.arrivals.daystats(batch.world)
	t.check("GROW-12",batch.arrivals.outpatient_count(batch.world)==16 and batch.world.facts.arrivals.plan.next_slot_index==3 and batch_stats.days.get("1",{}).get("arrived",0)==1 and batch_stats.days.get("1",{}).get("full",0)==2 and batch_observer.readiness_queries==1,{"stats":batch_stats,"readiness_queries":batch_observer.readiness_queries,"fixture_errors":_fixture_errors})

func _case_13(t) -> void:
	var unready: Dictionary = _context()
	_single_case(unready,"D37")
	unready.world.facts.facilities.cold_machine.failed = true
	unready.world.facts.arrivals.plan = _plan(unready.world,1,[1,0,0])
	unready.world.facts.sim_tick = DayPlan.slot_tick(unready.world.facts.arrivals.plan,0)
	var unready_rng: Dictionary = unready.world.facts.rng.duplicate(true)
	unready.arrivals.arrivals(unready.world)
	unready.arrivals.arrivals(unready.world)
	t.check("GROW-13",unready.world.facts.arrivals.plan.next_slot_index==1 and unready.world.facts.visits.size()==1 and unready.world.facts.rng!=unready_rng and unready.arrivals.daystats(unready.world).days.get("1",{}).get("arrived",0)==1,unready.arrivals.daystats(unready.world))

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
	# The guidance desk occupies [46,76]; walking exclusion needs a real,
	# accepted move that remains in transit, not a rejected request.
	var before_cell: Array = safe.world.facts.actors[safe.visit.actor_id].location.cell.duplicate()
	var move_reason: String = safe.space.request_move(safe.world,safe.visit.actor_id,1,[44,80])
	safe.space.advance(safe.world)
	var after_cell: Array = safe.world.facts.actors[safe.visit.actor_id].location.cell.duplicate()
	var walking_setup: bool = move_reason.is_empty() and before_cell!=after_cell and safe.world.facts.moves.has(safe.visit.actor_id) and after_cell!=[44,80]
	var safe_rng: String = safe.world.facts.rng.patience.state_decimal
	safe.arrivals.needs(safe.world)
	var no_walking_draw: bool = walking_setup and safe.world.facts.rng.patience.state_decimal==safe_rng
	safe.world.facts.moves.erase(safe.visit.actor_id)
	safe.ticket.service_assigned = false
	safe.visit.phase = "surgery"
	var service_rng: String = safe.world.facts.rng.patience.state_decimal
	safe.arrivals.needs(safe.world)
	var no_service_draw: bool = safe.world.facts.rng.patience.state_decimal==service_rng
	safe.visit.phase = "wait_gp"
	safe.visit.anger = 90.0
	safe.visit.last_service_tick = 600
	var anger_rng: String = safe.world.facts.rng.patience.state_decimal
	safe.arrivals.needs(safe.world)
	var deterministic: bool = safe.world.facts.wait_departures.get(safe.visit.actor_id,{}).get("selected",false) and safe.world.facts.rng.patience.state_decimal==anger_rng
	var stalled: Dictionary = _wait_ctx()
	stalled.world.facts.sim_tick = 6000
	stalled.ticket.waited_ticks = 6000
	stalled.visit.last_service_tick = 0
	stalled.visit.last_progress_tick = 0
	var stalled_rng: String = stalled.world.facts.rng.patience.state_decimal
	stalled.arrivals.needs(stalled.world)
	t.check("GROW-17",no_walking_draw and no_service_draw and deterministic and stalled.world.facts.wait_departures.get(stalled.visit.actor_id,{}).get("selected",false) and stalled.world.facts.rng.patience.state_decimal==stalled_rng,{"walking_setup":walking_setup,"move_reason":move_reason,"before_cell":before_cell,"after_cell":after_cell,"walking":no_walking_draw,"service":no_service_draw,"anger_exit":deterministic,"stalled":stalled.world.facts.wait_departures.get(stalled.visit.actor_id,{})})

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
	t.check("GROW-20",second_exited and oldest.get("id","")==person.resident.id and tie_choice.get("id","")==expected_tie and occupied.get("id","")==another.resident.id and none.is_empty() and ctx.world.facts.rng.arrival.state_decimal==none_rng and not returned_visit.is_empty() and returned_visit.id!=retained.last_visit_id and returned_visit.get("diagnosis",{}).is_empty() and returned_visit.attempt_ids.is_empty() and returned_visit.personality_id==retained.personality_id and returned_visit.anger==float(_content.definition("patient_personalities",retained.personality_id).initial_anger) and ctx.world.facts.actors[returned_visit.actor_id].appearance==retained.appearance and person.resident.name==retained.name,{"oldest":oldest.get("id",""),"tie":tie_choice.get("id",""),"occupied":occupied.get("id",""),"none":none,"fixture_errors":_fixture_errors})

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
		actual_gp = actual_gp or visit.get("diagnosis",{}).get("gp_completed",false)
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
	# Neither evidence collection nor the free brief requires a research desk
	# or worker. Keep the fully linked simulation's geometry together: the
	# desk-only research fixture installs a private space for isolated ticks.
	var diagnosis: Dictionary = _context(true,true)
	# The input hospital has this prior unlock, but no research-progress cache for
	# its next actual diagnosis. This is also a valid migration evidence boundary.
	diagnosis.world.facts.research.append("R19")
	diagnosis.world.touch()
	var initial_readiness: Dictionary = diagnosis.clinic.arrival_readiness(diagnosis.world,"B_S49_D41_M41")
	var opening_handoff: Dictionary = _finish_opening_handoff(diagnosis)
	var diagnosed: Dictionary = {}
	if opening_handoff.cleared:
		# This case tests diagnosis-material ownership, not a second clinical
		# branch. Choose a legal sufficient-GP random input before actual work.
		for seed_value: int in range(1,1000):
			var generator:=RandomNumberGenerator.new()
			generator.seed=seed_value
			var initial: int=generator.state
			if generator.randi_range(0,9999)>=4000:
				diagnosis.world.facts.rng.treatment={"algorithm":"godot-pcg32-4.7.2","seed_decimal":str(seed_value),"state_decimal":str(initial)}
				break
		diagnosed = _admit_fixture(diagnosis,"B_S49_D41_M41","acceptance_diagnosis_material")
	var diagnosis_ready: bool = false
	if not diagnosed.is_empty():
		for index: int in 1200:
			if diagnosed.phase in ["leaving","departed"]: break
			diagnosis.simulation.step()
			var receipt: Dictionary = diagnosis.world.facts.research_progress.materials.get("R19",{})
			if receipt.get("kind","")=="diagnosis" and receipt.get("visit_id","")==diagnosed.id:
				diagnosis_ready = true
				break
	diagnosis.world.facts.research_progress.materials.erase("R19")
	diagnosis.research.execute(diagnosis.world,"research_request_mail",{"research_id":"R19"})
	var diagnosis_due: int = int(diagnosis.world.facts.research_progress.mail.get("R19",diagnosis.world.sim_tick))
	diagnosis.world.facts.sim_tick = diagnosis_due
	diagnosis.research.boundaries(diagnosis.world)
	if diagnosis_ready:
		diagnosis.research.record_diagnostic_work(diagnosis.world,diagnosed,"gp")
	diagnosis.research.settle(diagnosis.world)
	var diagnosis_count: int = diagnosis.world.facts.research_progress.materials.size()
	if diagnosis_ready:
		diagnosis.research.record_diagnostic_work(diagnosis.world,diagnosed,"gp")
	diagnosis.research.settle(diagnosis.world)
	var diagnosis_details: Dictionary = diagnosis.world.facts.research_progress.materials.get("R19",{}).duplicate(true)
	diagnosis_details.admitted = not diagnosed.is_empty()
	diagnosis_details.diagnosis_ready = diagnosis_ready
	diagnosis_details.diagnosis = diagnosed.get("diagnosis",{}).duplicate(true)
	diagnosis_details.phase = diagnosed.get("phase","")
	diagnosis_details.waiting_reason = diagnosed.get("waiting_reason","")
	diagnosis_details.guidance = diagnosis.simulation.clinic.floor_guidance.state(diagnosis.world,str(diagnosed.get("id","")))
	diagnosis_details.initial_readiness = {"ok":initial_readiness.ok,"reason":initial_readiness.reason}
	diagnosis_details.opening_handoff = opening_handoff
	diagnosis_details.admission = diagnosis.get("last_admission",{}).duplicate(true)
	t.check("GROW-24",diagnosis_ready and diagnosis.world.facts.research_progress.materials.get("R19",{}).get("kind","")=="diagnosis" and diagnosis.world.facts.research_progress.materials.size()==diagnosis_count and not diagnosis.world.facts.research_progress.mail.has("R19"),diagnosis_details)

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
	var started: CommandResult = _start(working)
	if not started.accepted:
		t.check("GROW-29",false,{"research_start":started.to_record(),"prerequisite_failures":_fixture_errors.duplicate(true)})
		return
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
	# The night/rest state of a starter doctor is not an available student.
	# Begin with a fresh, rested learner and a valid current training shift.
	var learner: String = "research_desk_learner"
	sharing.world.facts.actors.research_worker.location.cell = [47,74]
	HospitalFactory._add_staff(sharing.world,learner,"课程医生","doctor",[45,71],_content)
	sharing.world.touch()
	sharing.space.sync_actor(sharing.world,"research_worker")
	var scheduler: HospitalShiftScheduler = sharing.simulation.services.scheduler
	var scheduled: CommandResult = scheduler.execute(sharing.world,"apply_schedule",{"changes":[{"staff_id":learner,"schedule":[{"kind":"training","pools":[],"locked":false},{"kind":"work","pools":[],"locked":false},{"kind":"rest","pools":[],"locked":false}]}]})
	scheduler.boundaries(sharing.world)
	var course: CommandResult = sharing.development.execute(sharing.world,"train_staff",{"staff_id":learner,"track":"diagnosis","desk_id":"research_desk"})
	sharing.development.dispatch(sharing.world)
	var course_job: Dictionary = sharing.world.facts.training_jobs.get(sharing.world.facts.staff[learner].training_job_id,{})
	var prior_owned: bool = course_job.get("desk_id","")=="research_desk" and course_job.get("state","") in ["travelling","working"]
	var shared_start: CommandResult = _start(sharing,"R12",{"allow_waiting":true})
	sharing.development.dispatch(sharing.world)
	var shared_job: Dictionary = sharing.research.active_job(sharing.world,"R12")
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
	_assign_research_room(parallel,"second_research_worker")
	_fresh_space(parallel)
	var one: CommandResult = _start(parallel,"R12",{"desk_id":"research_desk","worker_id":"research_worker"})
	var two: CommandResult = _start(parallel,"R14",{"desk_id":"second_research_desk","worker_id":"second_research_worker"})
	_research_tick(parallel)
	var one_job: Dictionary = parallel.research.active_job(parallel.world,"R12")
	var two_job: Dictionary = parallel.research.active_job(parallel.world,"R14")
	t.check("GROW-30",scheduled.accepted and course.accepted and prior_owned and shared_start.accepted and exclusive and retained_desk and one.accepted and two.accepted and one_job.get("state","")=="working" and two_job.get("state","")=="working" and one_job.get("desk_id","")!=two_job.get("desk_id","") and not _start(parallel,"R12",{"allow_waiting":true}).accepted,{"start_one":one.to_record(),"start_two":two.to_record(),"shared_start":shared_start.to_record(),"exclusive":exclusive,"retained":retained_desk,"original_gp_doctor_busy":opening_doctor_busy,"course_accepted":course.accepted,"schedule":scheduled.to_record(),"prior_owned":prior_owned,"course_reason":course.reason,"course":course_job,"shared":shared_job,"first":one_job,"second":two_job})

func _case_31(t) -> void:
	var pausing: Dictionary = _research_context()
	var start: CommandResult = _start(pausing)
	if not start.accepted:
		t.check("GROW-31",false,{"research_start":start.to_record()})
		return
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
	var natural_candidates: int = 0
	var checked_d04: int = 0
	for row: Dictionary in unbuilt:
		if not row.ok: continue # A body may still lack a safe static entrance.
		natural_candidates += 1
		var candidate: Dictionary = _clinical_query_input(unlocking,str(row.binding_id))
		if not candidate.ok:
			missing_real_resources=false
			continue
		var quotes: Array = candidate.clinic.compare_plans(candidate.world,candidate.visit.id)
		row.treatment_quotes = quotes
		missing_real_resources = missing_real_resources and not quotes.is_empty()
		# Unlocks admit cases independently of the treatment option. D04's
		# common plan needs no new resource in this initial hospital; its other
		# plans must explain their distinct expertise and research gaps.
		var available: Dictionary = {}
		for quote: Dictionary in quotes:
			available[quote.plan_id] = quote
			if not quote.ok: missing_real_resources = missing_real_resources and not str(quote.reason).is_empty()
		if row.disease_id=="D04":
			var common: Dictionary = available.get("P_D04_COMMON",{})
			var gentle: Dictionary = available.get("P_D04_GENTLE",{})
			var surgery: Dictionary = available.get("P_D04_SURGERY",{})
			missing_real_resources = missing_real_resources and common.get("ok",false) and not gentle.get("ok",true) and "等级" in str(gentle.get("reason","")) and not surgery.get("ok",true) and "研究" in str(surgery.get("reason",""))
			checked_d04 += 1
	missing_real_resources = missing_real_resources and natural_candidates>0 and checked_d04>0
	var actual_before: Dictionary = {"actors":unlocking.world.facts.actors.duplicate(true),"facilities":unlocking.world.facts.facilities.duplicate(true),"staff":unlocking.world.facts.staff.duplicate(true),"intake":unlocking.world.facts.arrivals.intake_open}
	unlocking.research.reception_readiness(unlocking.world,"R01")
	var ordinary: Dictionary = _context()
	var ordinary_ready: Dictionary = ordinary.clinic.arrival_readiness(ordinary.world,"B_S49_D37_M37")
	t.check("GROW-37",unlock_start.accepted and unlock_finished and "R01" in unlocking.world.facts.research and unlock_rewards.get("disease_ids",[])==["D03","D04","D25"] and missing_real_resources and unlocking.world.facts.actors==actual_before.actors and unlocking.world.facts.facilities==actual_before.facilities and unlocking.world.facts.staff==actual_before.staff and unlocking.world.facts.arrivals.intake_open==actual_before.intake and ordinary_ready.get("ok",false),{"started":unlock_start.to_record(),"finished":unlock_finished,"rewards":unlock_rewards,"missing_resources":missing_real_resources,"natural_candidates":natural_candidates,"missing":unbuilt,"ordinary_ready":ordinary_ready})

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

# Calculation cases use a private copy and the real entrance contract. No
# production reference simulator or retired capacity model supplies the input.
func _clinical_query_input(ctx: Dictionary, binding_id: String) -> Dictionary:
	var world:=WorldState.new(ctx.world.freeze())
	var sim:=HospitalSimulation.new(world,_content)
	_simulations.append(sim)
	var result: CommandResult=sim.clinic.execute(world,"clinical_arrive",{"arrival_key":world.new_id("query_input"),"binding_id":binding_id,"complex":false,"personality_id":"PP01","expression":"clear"})
	if not result.accepted: return {"ok":false,"reason":result.reason,"code":result.code}
	return {"ok":true,"world":world,"visit":world.facts.visits[result.changed_ids[0]],"clinic":sim.clinic,"space":sim.space}
