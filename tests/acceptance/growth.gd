extends RefCounted

const F = preload("res://game/arrivals/exact_fraction.gd")
const DayPlan = preload("res://game/arrivals/day_plan.gd")
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
	"GROW-38":"docs/design/04-technical.md §4研究进度；资料简报排序与任务恢复"
}

# This observer counts real production queries without substituting a result.
class AdmissionObserver extends HospitalClinic:
	var readiness_queries: int = 0
	func arrival_readiness(world: WorldState, binding_id: String, complex_case: bool = false) -> Dictionary:
		readiness_queries += 1
		return super.arrival_readiness(world,binding_id,complex_case)

var _content: HospitalContent
var _simulations: Array[HospitalSimulation] = []
var _opened_snapshot: Dictionary = {}
var _fixture_errors: Array = []

func run(t) -> void:
	_content = HospitalContent.new()
	_arrival_cases(t)
	_patience_cases(t)
	_resident_cases(t)
	_prepare_opened_snapshot()
	_research_cases(t)
	for simulation: HospitalSimulation in _simulations:
		simulation.dispose()
	_simulations.clear()

func _context(preset: bool = true, opened: bool = false) -> Dictionary:
	var world: WorldState = WorldState.new(_opened_snapshot.duplicate(true)) if opened and not _opened_snapshot.is_empty() else HospitalFactory.create(HospitalSnapshots.uuid(),"来客与研究专项医院",preset,_content)
	var simulation: HospitalSimulation = HospitalSimulation.new(world,_content)
	_simulations.append(simulation)
	var arrivals: HospitalArrivalService = simulation.services.arrivals
	arrivals.execute(world,"tutorial_set_enabled",{"enabled":false})
	# Non-capacity cases start inside an already frozen day. Manual patients and
	# actual research/clinical work must not trigger an unrelated whole-case solver.
	world.facts.arrivals.plan = _plan(world,0,[0,0,0],[F.make(),F.make(),F.make()])
	arrivals.execute(world,"arrivals_intake",{"open":false})
	return {"world":world,"simulation":simulation,"space":simulation.space,"clinic":simulation.clinic,
		"arrivals":arrivals,"research":simulation.services.research,"development":simulation.services.development}

func _single_case(ctx: Dictionary, disease_id: String = "D09") -> void:
	for disease: Dictionary in _content.catalog.diseases:
		ctx.arrivals.execute(ctx.world,"arrivals_weight",{"disease_id":disease.id,"weight":1 if disease.id==disease_id else 0})
	ctx.arrivals.execute(ctx.world,"arrivals_intake",{"open":true})

func _plan(world: WorldState, count: int, counts: Array, capacities: Array = []) -> Dictionary:
	return {"day_index":world.sim_tick/18000+1,"preset":"normal","scale_numerator":3,
		"shift_capacities":capacities if not capacities.is_empty() else [F.make(1),F.make(),F.make()],
		"opportunity_count":count,"shift_opportunity_counts":counts.duplicate(),"schedule_seed":"321" if count>0 else null,
		"schedule_algorithm":"arrival-load-slot-v1","next_slot_index":0,"held_capacity_fraction":F.make(),"held_scale_numerator":0}

func _slot_ticks(plan: Dictionary) -> Array:
	var result: Array = []
	for index: int in int(plan.opportunity_count):
		result.append(DayPlan.slot_tick(plan,index))
	return result

func _add_room(world: WorldState, id: String, kind: String, origin: Array, size: Array) -> void:
	HospitalFactory._add_room(world,{"id":id,"type":kind,"anchor":origin,"size":size,"door":{"offset":1,"definition_id":"DR04"}},_content)
	world.touch()

func _add_facility(world: WorldState, id: String, definition_id: String, room_id: Variant, cell: Array) -> void:
	var definition: Dictionary = _content.facility_definition(definition_id)
	HospitalFactory._add_facility(world,{"id":id,"definition_id":definition_id,"room_id":room_id,"anchor":cell,"size":definition.footprint.duplicate()},_content)
	world.touch()

func _fresh_space(ctx: Dictionary) -> void:
	var geometry: HospitalSpace = HospitalSpace.new(_content)
	ctx.space = geometry
	ctx.clinic.space = geometry
	ctx.arrivals.space = geometry
	ctx.arrivals.clinic.space = geometry
	ctx.research.space = geometry
	ctx.development.space = geometry

func _observer(ctx: Dictionary) -> AdmissionObserver:
	var observer: AdmissionObserver = AdmissionObserver.new(_content,ctx.space)
	ctx.arrivals.clinic = observer
	return observer

func _arrival_cases(t) -> void:
	var empty: Dictionary = _context(false)
	# This case, unlike the fixed-day fixtures, exercises real plan generation.
	empty.world.facts.arrivals.plan.clear()
	var rng_before: Dictionary = empty.world.facts.rng.duplicate(true)
	empty.arrivals.boundaries(empty.world)
	var zero: Dictionary = empty.world.facts.arrivals.plan
	t.check("GROW-01",not zero.is_empty() and zero.opportunity_count==0 and zero.shift_opportunity_counts==[0,0,0] and zero.schedule_seed==null and zero.shift_capacities==[F.make(),F.make(),F.make()] and empty.world.facts.rng==rng_before,zero)

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
	t.check("GROW-02",capacity.get("complete",false) and F.compare(capacity.get("capacity",F.make()),F.make())>0 and absent.get("capacity",{})==F.make() and unmanned.get("capacity",{})==F.make() and int(unmanned.get("scale_numerator",-1))==0,{"base":capacity,"missing_team":absent,"unmanned":unmanned})
	var frozen: Dictionary = base.world.freeze()
	var repeated: Dictionary = base.arrivals.capacity(base.world,false)
	t.check("GROW-03",capacity==repeated and base.world.freeze()==frozen,{"same_projection":capacity==repeated,"world_unchanged":base.world.freeze()==frozen})
	base.arrivals.execute(base.world,"arrivals_intake",{"open":false})
	var closed_capacity: Dictionary = base.arrivals.capacity(base.world,false)
	t.check("GROW-04",closed_capacity.get("capacity",{})==capacity.get("capacity",{}) and closed_capacity.get("shift_pairs",[])==capacity.get("shift_pairs",[]),closed_capacity)

	# Today is already frozen; real capacity was calculated above and is still
	# recalculated by hold selection and the later new-day boundaries below.
	base.arrivals.boundaries(base.world)
	var today: Dictionary = base.world.facts.arrivals.plan.duplicate(true)
	var held_result: CommandResult = base.arrivals.execute(base.world,"arrivals_scale",{"mode":"hold_capacity"})
	var held: Dictionary = base.world.facts.arrivals.held_capacity_fraction.duplicate(true)
	_add_room(base.world,"second_terminal_room","T01",[42,70],[6,6])
	_add_facility(base.world,"second_terminal","M09","second_terminal_room",[44,71])
	for source_id: String in ["starter_doctor_a","starter_doctor_b","starter_doctor_c"]:
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

	var vector_world: WorldState = empty.world
	var allocation: Array = DayPlan.allocate_shifts(1,"321",8,[F.make(1),F.make(1),F.make(1)])
	var vector: Dictionary = _plan(vector_world,8,allocation,[F.make(3),F.make(3),F.make(3)])
	t.check("GROW-06",allocation==[3,2,3] and _slot_ticks(vector)==[1156,2815,5438,8035,11156,12853,15397,16553],{"allocation":allocation,"ticks":_slot_ticks(vector)})
	var gap_counts: Array = DayPlan.allocate_shifts(1,"321",8,[F.make(1),F.make(),F.make(1)])
	var gap: Dictionary = _plan(vector_world,8,gap_counts,[F.make(5),F.make(),F.make(5)])
	var no_middle: bool = true
	for tick: int in _slot_ticks(gap):
		no_middle = no_middle and (tick<6000 or tick>=12000)
	t.check("GROW-07",gap_counts==[4,0,4] and no_middle,{"counts":gap_counts,"ticks":_slot_ticks(gap)})
	var restore: Dictionary = _context()
	restore.world.facts.arrivals.plan = vector.duplicate(true)
	var restore_rng: Dictionary = restore.world.facts.rng.duplicate(true)
	var restored: WorldState = WorldState.new(restore.world.freeze())
	restored.facts.arrivals.next_preset = "festival"
	restored.facts.staff.starter_doctor_a.schedule[0].kind = "rest"
	var restored_ticks: Array = _slot_ticks(restored.facts.arrivals.plan)
	t.check("GROW-08",restored_ticks==_slot_ticks(vector) and restored.facts.arrivals.plan==vector and restored.facts.rng==restore_rng and not vector.has("slot_ticks") and DayPlan.validate(vector).is_empty(),restored.facts.arrivals.plan)
	var before_settings: Dictionary = restore.world.facts.arrivals.plan.duplicate(true)
	restore.arrivals.execute(restore.world,"arrivals_intake",{"open":true})
	restore.arrivals.execute(restore.world,"arrivals_preset",{"preset":"busy"})
	restore.arrivals.execute(restore.world,"arrivals_intake",{"open":false})
	var immediate: bool = not restore.world.facts.arrivals.intake_open
	restore.arrivals.execute(restore.world,"arrivals_intake",{"open":true})
	t.check("GROW-09",immediate and restore.world.facts.arrivals.intake_open and restore.world.facts.arrivals.preset=="normal" and restore.world.facts.arrivals.next_preset=="busy" and restore.world.facts.arrivals.plan==before_settings,restore.arrivals.daystats(restore.world))

	var excluded: Dictionary = _context()
	var observed: AdmissionObserver = _observer(excluded)
	excluded.world.facts.arrivals.plan = _plan(excluded.world,1,[1,0,0])
	excluded.world.facts.sim_tick = DayPlan.slot_tick(excluded.world.facts.arrivals.plan,0)
	excluded.arrivals.execute(excluded.world,"arrivals_intake",{"open":false})
	var excluded_before: Dictionary = excluded.world.freeze()
	excluded.arrivals.arrivals(excluded.world)
	t.check("GROW-10",observed.readiness_queries==0 and excluded.world.facts.arrivals.plan.next_slot_index==1 and excluded.world.facts.rng==excluded_before.rng and excluded.world.facts.actors==excluded_before.actors and excluded.world.facts.visits==excluded_before.visits and excluded.world.facts.tickets==excluded_before.tickets and excluded.world.facts.preparations==excluded_before.preparations,excluded.arrivals.daystats(excluded.world))

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

	var unready: Dictionary = _context()
	_single_case(unready,"D37")
	unready.world.facts.facilities.cold_machine.failed = true
	unready.world.facts.arrivals.plan = _plan(unready.world,1,[1,0,0])
	unready.world.facts.sim_tick = DayPlan.slot_tick(unready.world.facts.arrivals.plan,0)
	var unready_rng: Dictionary = unready.world.facts.rng.duplicate(true)
	unready.arrivals.arrivals(unready.world)
	unready.arrivals.arrivals(unready.world)
	t.check("GROW-13",unready.world.facts.arrivals.plan.next_slot_index==1 and unready.world.facts.visits.is_empty() and unready.world.facts.rng==unready_rng and unready.arrivals.daystats(unready.world).days.get("1",{}).get("unready",0)==1,unready.arrivals.daystats(unready.world))

func _sum(values: Array) -> Dictionary:
	var result: Dictionary = F.make()
	for value: Dictionary in values:
		result = F.add(result,value)
	return result

# Fixture setup uses production admission and queue creation. The chosen cell is
# the initial position of this focused saved-world input, not a movement result.
func _patient(ctx: Dictionary, cell: Array, binding: String = "B_S49_D37_M37", personality: String = "PP01", resident: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = {"arrival_key":ctx.world.new_id("acceptance_arrival"),"binding_id":binding,"personality_id":personality,"complex":false}
	if not resident.is_empty():
		payload.resident_id = resident.id
		payload.name = resident.name
		payload.personality_id = resident.personality_id
	var result: CommandResult = ctx.clinic.execute(ctx.world,"clinical_arrive",payload)
	ctx.last_admission = result.to_record()
	if not result.accepted:
		_fixture_errors.append({"code":result.code,"reason":result.reason,"binding":binding})
		return {}
	var visit: Dictionary = ctx.world.facts.visits[result.changed_ids[0]]
	ctx.world.facts.actors[visit.actor_id].location.cell = cell.duplicate()
	if not resident.is_empty():
		ctx.world.facts.actors[visit.actor_id].appearance = resident.appearance.duplicate(true)
		resident.current_actor_id = visit.actor_id
		ctx.world.facts.residents[resident.id] = resident
	ctx.world.touch()
	ctx.space.sync_actor(ctx.world,visit.actor_id)
	ctx.clinic._queue(ctx.world,visit,"reception")
	var ticket: Dictionary = ctx.world.facts.tickets[visit.ticket_id]
	ticket.waited_ticks = 0
	ticket.wait_accounted_tick = ctx.world.sim_tick
	return visit

func _wait_ctx(personality: String = "PP01") -> Dictionary:
	var ctx: Dictionary = _context()
	ctx.visit = _patient(ctx,[45,76],"B_S49_D37_M37",personality)
	ctx.ticket = ctx.world.facts.tickets.get(ctx.visit.get("ticket_id",""),{})
	_seed_survival(ctx.world)
	return ctx

func _seed_survival(world: WorldState) -> void:
	for seed: int in range(1,65):
		var generator: RandomNumberGenerator = RandomNumberGenerator.new()
		generator.seed = seed
		var initial: String = str(generator.state)
		if generator.randi_range(0,9999)>=3500 and generator.randi_range(0,9999)>=3500:
			world.facts.rng.patience.seed_decimal = str(seed)
			world.facts.rng.patience.state_decimal = initial
			return

func _patience_events(service: HospitalArrivalService) -> int:
	var count: int = 0
	for event: SimEvent in service.take_events():
		if event.kind=="patience_evaluated":
			count += 1
	return count

func _patience_cases(t) -> void:
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

func _resident(ctx: Dictionary, cell: Array) -> Dictionary:
	var resident: Dictionary = ctx.arrivals._new_identity(ctx.world,"S49")
	resident.remembered = true
	var visit: Dictionary = _patient(ctx,cell,"B_S49_D37_M37","PP01",resident)
	return {"resident":resident,"visit":visit}

func _actual_departure(ctx: Dictionary, visit: Dictionary) -> bool:
	if not ctx.clinic.depart_visit(ctx.world,visit.id,"referred"):
		return false
	for index: int in 600:
		ctx.clinic.dispatch(ctx.world)
		ctx.space.advance(ctx.world)
		ctx.arrivals.settle(ctx.world)
		if visit.phase=="departed":
			return true
		ctx.world.facts.sim_tick += 1
		ctx.world.touch()
		ctx.space.finish_boundary(ctx.world)
	return false

func _return_hit(world: WorldState) -> void:
	for seed: int in range(1,65):
		var generator: RandomNumberGenerator = RandomNumberGenerator.new()
		generator.seed = seed
		var initial: String = str(generator.state)
		var value: int = generator.randi()
		if value<4294960000 and value%10000<2000:
			world.facts.rng.arrival.seed_decimal = str(seed)
			world.facts.rng.arrival.state_decimal = initial
			return

func _resident_cases(t) -> void:
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

func mini_string(first: String, second: String) -> String:
	return first if first<second else second

func _prepare_opened_snapshot() -> void:
	var ctx: Dictionary = _context()
	# _context supplies the frozen current day; full steps here only need the
	# original manually admitted patient's real first GP, with no new arrivals.
	ctx.arrivals.execute(ctx.world,"arrivals_intake",{"open":false})
	var result: CommandResult = ctx.clinic.execute(ctx.world,"clinical_arrive",{"arrival_key":"research_opening_patient","binding_id":"B_S49_D37_M37","personality_id":"PP01"})
	if not result.accepted:
		_fixture_errors.append({"opening":result.reason})
		return
	for index: int in 1200:
		ctx.simulation.step()
		if index%100==99:
			print("GROWTH_OPENING_PROGRESS tick="+str(ctx.world.sim_tick)+" visits="+JSON.stringify(ctx.world.facts.visits))
		if ctx.research.opened(ctx.world):
			_opened_snapshot = ctx.world.freeze()
			return
	_fixture_errors.append({"opening":"First actual GP did not finish within its necessary 120-second boundary"})

func _research_context(desk: bool = true, worker: bool = true) -> Dictionary:
	var ctx: Dictionary = _context(true,true)
	if desk:
		_add_room(ctx.world,"research_room","research",[42,69],[6,6])
		_add_facility(ctx.world,"research_desk","FUR05","research_room",[43,70])
	if worker:
		HospitalFactory._add_staff(ctx.world,"research_worker","研究员","researcher",[45,70],_content)
		ctx.simulation.services.scheduler.ensure(ctx.world)
		ctx.simulation.services.recruitment.ensure(ctx.world)
	_fresh_space(ctx)
	return ctx

func _finish_opening_handoff(ctx: Dictionary) -> Dictionary:
	var opening: Dictionary = {}
	for visit: Dictionary in ctx.world.facts.visits.values():
		if visit.arrival_key=="research_opening_patient":
			opening = visit
			break
	if opening.is_empty():
		return {"cleared":false,"reason":"Actual first-GP visit is missing"}
	var referral: CommandResult = ctx.clinic.execute(ctx.world,"clinical_refer",{"visit_id":opening.id})
	var state: Dictionary = {"referral":referral.to_record(),"started_tick":ctx.world.sim_tick,"cleared":false}
	if referral.accepted:
		ctx.world.touch()
		# First GP opens research before its bodies and station have handed over.
		# Only the original patient's real exit and the GP's physical release are
		# needed before the next actual admission; no clinical facts are replaced.
		for index: int in 600:
			ctx.simulation.step()
			var gp_release: bool = false
			for staff: Dictionary in ctx.world.facts.staff.values():
				gp_release = gp_release or staff.get("clinical_release",{}).get("facility_id","")=="gp_station"
			if opening.phase=="departed" and ctx.world.facts.actors[opening.actor_id].location.kind=="outside" and not ctx.world.facts.adaptations.has("gp_station") and not gp_release:
				state.cleared = true
				break
	state.finished_tick = ctx.world.sim_tick
	state.visit_phase = opening.phase
	state.patient_location = ctx.world.facts.actors[opening.actor_id].location.duplicate(true)
	state.gp_adaptation = ctx.world.facts.adaptations.get("gp_station",{}).duplicate(true)
	state.gp_releases = {}
	for staff: Dictionary in ctx.world.facts.staff.values():
		if staff.get("clinical_release",{}).get("facility_id","")=="gp_station":
			state.gp_releases[staff.id] = {"release":staff.clinical_release.duplicate(true),"location":ctx.world.facts.actors[staff.id].location.duplicate(true),"move":ctx.world.facts.moves.get(staff.id,{}).duplicate(true)}
	return state

func _research_tick(ctx: Dictionary) -> void:
	ctx.research.boundaries(ctx.world)
	ctx.development.dispatch(ctx.world)
	ctx.space.advance(ctx.world)
	ctx.research.advance(ctx.world)
	ctx.research.settle(ctx.world)
	ctx.world.facts.sim_tick += 1
	ctx.world.touch()
	ctx.space.finish_boundary(ctx.world)

func _start(ctx: Dictionary, research_id: String = "R12", extra: Dictionary = {}) -> CommandResult:
	var payload: Dictionary = {"research_id":research_id}
	payload.merge(extra,true)
	return ctx.research.execute(ctx.world,"research_start",payload)

func _finish_research(ctx: Dictionary, research_id: String) -> bool:
	var job: Dictionary = ctx.research.active_job(ctx.world,research_id)
	if job.is_empty():
		return false
	# Only this original job's quoted work boundary is advanced.
	var limit: int = int(job.total_work_milli)/1000+300
	for index: int in limit:
		_research_tick(ctx)
		if HospitalResearch.terminal(job):
			return job.state=="completed"
	return false

func _material(ctx: Dictionary, research_id: String) -> void:
	ctx.research.execute(ctx.world,"research_request_mail",{"research_id":research_id})
	var due: int = int(ctx.world.facts.research_progress.mail.get(research_id,ctx.world.sim_tick))
	ctx.world.facts.sim_tick = due
	ctx.research.boundaries(ctx.world)
	ctx.research.settle(ctx.world)

func _research_cases(t) -> void:
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

	var waiting: Dictionary = _research_context(false,false)
	var waiting_cash: int = HospitalLedger.balance(waiting.world)
	var default_wait: CommandResult = _start(waiting)
	var default_clean: bool = not default_wait.accepted and waiting.world.facts.research_jobs.is_empty() and HospitalLedger.balance(waiting.world)==waiting_cash
	var allowed_wait: CommandResult = _start(waiting,"R12",{"allow_waiting":true})
	var paid_wait: Dictionary = waiting.research.active_job(waiting.world,"R12")
	var paid_remaining: int = int(paid_wait.get("remaining_work_milli",-1))
	_research_tick(waiting)
	t.check("GROW-27",default_clean and allowed_wait.accepted and HospitalLedger.balance(waiting.world)==waiting_cash-600 and paid_wait.get("state","")=="waiting" and paid_wait.get("remaining_work_milli",-2)==paid_remaining and str(paid_wait.get("worker_id","x")).is_empty(),{"default_clean":default_clean,"job":paid_wait})

	var community: Dictionary = _research_context()
	var rich_community: CommandResult = _start(community,"R12",{"community":true})
	community.world.facts.ledger.opening_balance -= HospitalLedger.balance(community.world)
	var low_cash: int = HospitalLedger.balance(community.world)
	var community_start: CommandResult = _start(community,"R12",{"community":true})
	var community_job: Dictionary = community.research.active_job(community.world,"R12")
	var doubled: bool = community_job.get("total_work_milli",0)==3600000 and community_job.get("mode","")=="community" and community_job.get("cost",-1)==0
	community.research.execute(community.world,"research_cancel",{"research_id":"R12"})
	t.check("GROW-28",not rich_community.accepted and low_cash==0 and community_start.accepted and doubled and community_job.get("refund",-1)==0 and HospitalLedger.balance(community.world)==0,{"rich_rejected":not rich_community.accepted,"job":community_job})

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
