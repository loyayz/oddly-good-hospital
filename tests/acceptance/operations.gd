extends RefCounted

# Requirements are fixed in operations.md before API mapping. Fixtures use the
# production factory, definitions, commands, movement and work services.
const CASES: Dictionary = {
	"OPS-01":"docs/design/08-hospital-life.md §22；固定20包采购只入库20、付款400一次",
	"OPS-02":"docs/design/08-hospital-life.md §22/22.2；资金容量单价失败整单不变",
	"OPS-03":"docs/design/08-hospital-life.md §22/22.1；自动保留1000且不追补目标",
	"OPS-04":"docs/design/08-hospital-life.md §22；C560/R80/T240/B4000与缩容保留",
	"OPS-05":"docs/design/08-hospital-life.md §22；命令先于自动采购且最多一单",
	"OPS-06":"docs/design/08-hospital-life.md §22；创作基金代付真实入库且不发现金",
	"OPS-07":"docs/design/08-hospital-life.md §22；并发预留取消和唯一领用守恒",
	"OPS-08":"docs/design/08-hospital-life.md §23；真实受阻60/120/180秒与30秒复工",
	"OPS-09":"docs/design/08-hospital-life.md §22.2；首项缺量建议只读且不占资源",
	"OPS-10":"docs/design/08-hospital-life.md §22；每日一次真实20包援助采购",
	"OPS-11":"docs/design/08-hospital-life.md §4/20；同类装饰不叠加且四污渍差24分",
	"OPS-12":"docs/design/08-hospital-life.md §4；50币装修冻结两格各8秒且暂停不生效",
	"OPS-13":"docs/design/08-hospital-life.md §4；实际工人与工具完成才安装表面",
	"OPS-14":"docs/design/08-hospital-life.md §4；只退未开工格且已开工恢复收尾",
	"OPS-15":"docs/design/08-hospital-life.md §20；6次水/8次厕/8次治疗唯一生成污物",
	"OPS-16":"docs/design/08-hospital-life.md §20；真实清洁余量贡献和唯一完成",
	"OPS-17":"docs/design/08-hospital-life.md §20；桶内合并4秒且旧地污不吸走",
	"OPS-18":"docs/design/08-hospital-life.md §4；真实运行10施工15取最大及格边隔音",
	"OPS-19":"docs/design/01-simulation.md §6；维护显式集合与首次真实使用磨损",
	"OPS-20":"docs/design/08-hospital-life.md §15；默认45/手动60阈值与唯一待工单",
	"OPS-21":"docs/design/01-simulation.md §6；真实维修30秒40币恢复100及免抽180秒",
	"OPS-22":"docs/design/08-hospital-life.md §15；8秒保养转修只余22秒补付20",
	"OPS-23":"docs/design/08-hospital-life.md §15；维护暂停库存接续不重付零件",
	"OPS-24":"docs/design/08-hospital-life.md §21；研究资金借用品限制失败原子",
	"OPS-25":"docs/design/08-hospital-life.md §21；M09一级420待工与未开工取消全退一次",
	"OPS-26":"docs/design/08-hospital-life.md §21；原病例设备安全释放后实际升级，旧承诺不变且后续服务读取新等级",
	"OPS-27":"docs/design/08-hospital-life.md §21；已开工12秒升级保留18秒不退材料",
	"OPS-28":"docs/design/08-hospital-life.md §5；一房一科与200币600秒专注过渡",
	"OPS-29":"docs/design/08-hospital-life.md §5；能力2/5病例/75分专注仅操作乘0.95",
	"OPS-30":"docs/design/08-hospital-life.md §6；暂时不足不是挂错且等价目的地就地接续",
	"OPS-31":"docs/design/08-hospital-life.md §6；真实错入口唯一怒气12流程8并保留票证",
	"OPS-32":"docs/design/08-hospital-life.md §1/18/19；评分缺样本与真实完成事实去重只读",
	"OPS-33":"docs/design/01-simulation.md §8/8.2；运营20日1561持余及工资逐人取整",
	"OPS-34":"docs/design/01-simulation.md §8；第三日首补助与1F地块周期幂等",
	"OPS-35":"docs/design/01-simulation.md §8/8.1；成本940实付100援助840不算盈利",
	"OPS-36":"docs/design/01-simulation.md §8.1/8.2；六账页三日展望与目标便签不圈存",
	"OPS-37":"docs/design/01-simulation.md §8；同院救援箱仅一次且只补缺岗正常付薪",
	"OPS-38":"docs/design/08-hospital-life.md §15；派单按设备停机用途分级，同级置顶且不打断已开工单",
	"OPS-39":"docs/design/01-simulation.md §6；预约与实际占用释放前不得维修，恢复后真实到场开工",
	"OPS-40":"docs/design/08-hospital-life.md §18；评价回收保护已发布窗口和下一日候选",
	"OPS-41":"docs/design/01-simulation.md §6；维护设备索引随几何和事实失效，保留原设备顺序、当前状态及随机流",
	"OPS-42":"docs/design/08-hospital-life.md §4、§20；施工安全查询读取当前完整身体与临床边界，清扫派工保留区域、优先级和竞争"
}

var _content: HospitalContent
var _live: Array[HospitalSimulation] = []
var _serial: int = 0
var _current_case: String = ""

func run(t) -> void:
	_content = HospitalContent.new()
	for id: String in CASES:
		if not t.wants(id): continue
		_current_case = id
		t.begin_case(id)
		var result: Dictionary = {"ok":false,"details":"发布内容未加载："+_content.error}
		if _content.error.is_empty():
			result = call("_case_"+id.right(2))
		t.check(id,bool(result.get("ok",false)),result.get("details",{}))
	for simulation: HospitalSimulation in _live:
		simulation.dispose()
	_live.clear()

func _case_42() -> Dictionary:
	return preload("res://tests/acceptance/environment_query_batches.gd").new().run(_content)

func _result(ok: bool, details: Variant = null) -> Dictionary:
	return {"ok":ok,"details":details}

func _new(label: String, preset: bool = false, cash: int = 5000) -> Dictionary:
	_serial += 1
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),label,preset,_content)
	var simulation: HospitalSimulation = HospitalSimulation.new(world,_content)
	_live.append(simulation)
	world.facts.inventory.auto_restock = false
	_zero_arrivals(world)
	_cash(world,cash)
	return {"s":simulation,"w":world,"errors":[]}

func _zero_arrivals(world: WorldState) -> void:
	# Arrival planning is outside this specialist fixture. Keep a valid frozen
	# zero-opportunity plan for its actual hospital day, including checkpoints.
	var day: int = world.sim_tick/WorldState.TICKS_PER_DAY+1
	world.facts.arrivals.intake_open = false
	var plan: Dictionary = world.facts.arrivals.plan
	if not plan.is_empty() and int(plan.day_index)==day and int(plan.opportunity_count)==0:
		return
	world.facts.arrivals.plan = {"day_index":day,"preset":"normal","scale_numerator":3,
		"shift_capacities":[ArrivalFraction.make(1),ArrivalFraction.make(),ArrivalFraction.make()],
		"opportunity_count":0,"shift_opportunity_counts":[0,0,0],"schedule_seed":null,
		"schedule_algorithm":"arrival-load-slot-v1","next_slot_index":0,
		"held_capacity_fraction":ArrivalFraction.make(),"held_scale_numerator":0}

func _cash(world: WorldState, target: int) -> void:
	# Initial capital is fixture input, never asserted as earned income.
	world.facts.ledger.opening_balance += target-HospitalLedger.balance(world)

func _command(f: Dictionary, kind: String, payload: Dictionary, id: String = "") -> CommandResult:
	_serial += 1
	return f.s.apply(GameCommand.new("ops_command_%d"%_serial if id.is_empty() else id,f.w.hospital_id,-1,kind,BusinessPayload.new(payload)))

func _restore(f: Dictionary) -> Dictionary:
	var world: WorldState = WorldState.new(f.w.freeze())
	var simulation: HospitalSimulation = HospitalSimulation.new(world,_content)
	_live.append(simulation)
	_zero_arrivals(world)
	return {"s":simulation,"w":world,"errors":f.errors.duplicate()}

func _place(f: Dictionary, id: String, definition_id: String, cell: Array, room_id: String = "", inventory_id: String = "") -> bool:
	var payload: Dictionary = {"id":id,"definition_id":definition_id,"floor_id":1,"cell":cell}
	if not room_id.is_empty(): payload.room_id = room_id
	if not inventory_id.is_empty(): payload.inventory_id = inventory_id
	var applied: CommandResult = _command(f,"build_facility",payload)
	if not applied.accepted: f.errors.append({"place":id,"reason":applied.reason})
	return applied.accepted

func _staff(f: Dictionary, id: String, role: String, cell: Array) -> void:
	HospitalFactory._add_staff(f.w,id,id,role,cell,_content)
	f.w.touch()
	f.s.space.sync_actor(f.w,id)
	for service: RefCounted in f.s.services.values(): service.call("ensure",f.w)

func _work_tick(f: Dictionary, service: String) -> void:
	var worker: RefCounted = f.s.services[service]
	worker.call("dispatch",f.w)
	f.s.space.advance(f.w,f.w.present_actor_count())
	worker.call("advance",f.w)
	f.w.facts.sim_tick += 1
	_zero_arrivals(f.w)
	f.w.touch()
	f.s.space.finish_boundary(f.w)

func _clinic_tick(f: Dictionary, maintenance: bool = false) -> void:
	# Advance the real waiting, shift and clinical phases. OPS07–10 supply their
	# completed diagnostic and work-base history before entering this driver.
	f.s.services.scheduler.boundaries(f.w)
	if maintenance: f.s.services.remodel.dispatch(f.w)
	f.s.services.scheduler.dispatch(f.w)
	f.s.services.development.dispatch(f.w)
	f.s.services.waiting.dispatch(f.w)
	f.s.services.departments.dispatch(f.w)
	if maintenance: f.s.services.maintenance.dispatch(f.w)
	f.s.clinic.dispatch(f.w)
	f.s.space.advance(f.w,f.w.present_actor_count())
	f.s.clinic.advance(f.w)
	f.s.services.development.advance(f.w)
	f.s.services.scheduler.advance(f.w)
	if maintenance: f.s.services.maintenance.advance(f.w)
	f.s.services.departments.advance(f.w)
	f.s.services.waiting.advance(f.w)
	f.s.clinic.release_departed(f.w)
	HospitalLedger.settle(f.w)
	f.w.facts.sim_tick += 1
	_zero_arrivals(f.w)
	f.w.touch()
	f.s.space.finish_boundary(f.w)
	if f.w.sim_tick%100==0:
		_clinic_progress(f)

func _clinic_progress(f: Dictionary) -> void:
	var patients: Array = []
	for id: String in f.w.ids("visits"):
		var visit: Dictionary = f.w.facts.visits[id]
		patients.append({"id":id,"phase":visit.phase,"ticket":visit.get("ticket_id",""),
			"reason":visit.get("waiting_reason",""),"position":f.w.facts.actors[visit.actor_id].location.duplicate(true),
			"move":_clinic_move(f,visit.actor_id)})
	var clinicians: Array = []
	for id: String in f.w.ids("staff"):
		var staff: Dictionary = f.w.facts.staff[id]
		if not staff.role in ["doctor","nurse"]: continue
		var base: Dictionary = staff.get("base_task",{})
		clinicians.append({"id":id,"shift":staff.on_shift,"blocked":staff.get("block_new_work",false),
			"prepared":staff.get("base_prepared",false),"base":base.get("phase",""),
			"base_at":base.get("facility_id",""),"base_left":base.get("remaining_ticks",0),
			"position":f.w.facts.actors[id].location.duplicate(true),"clinical_release":staff.get("clinical_release",{}).duplicate(true),
			"move":_clinic_move(f,id)})
	print("OPS_PROGRESS "+_current_case+" "+JSON.stringify({"tick":f.w.sim_tick,"patients":patients,"clinicians":clinicians}))

func _clinic_move(f: Dictionary, actor_id: String) -> Dictionary:
	var movement: Dictionary = f.w.facts.moves.get(actor_id,{})
	if movement.is_empty(): return {}
	var cursor: int = int(movement.get("cursor",0))
	var path: Array = movement.get("path",[])
	return {"target":{"floor_id":movement.get("target_floor",-1),"cell":movement.get("target_cell",[])},
		"cursor":cursor,"blocked_since":movement.get("blocked_since",-1),"yielding":movement.get("yielding",false),
		"pending":movement.get("route_pending",false),"next3segments":path.slice(cursor,mini(path.size(),cursor+3))}

func _outpatient(f: Dictionary, key: String) -> String:
	var arrived: CommandResult = _command(f,"clinical_arrive",{"arrival_key":key,"binding_id":"B_S49_D37_M37","personality_id":"PP01"})
	if not arrived.accepted:
		f.errors.append({"arrival":key,"reason":arrived.reason})
		return ""
	var visit_id: String = str(arrived.changed_ids[0])
	for tick: int in 2200:
		var visit: Dictionary = f.w.facts.visits[visit_id]
		if visit.phase=="wait_outpatient": return visit_id
		if visit.phase in ["leaving","departed"]: break
		_clinic_tick(f)
	f.errors.append({"outpatient_not_reached":visit_id,"visit":f.w.facts.visits[visit_id].duplicate(true)})
	return ""

func _diagnosed_outpatient(f: Dictionary, key: String, waiting_cell: Array) -> String:
	# Focused cases begin with a diagnosed, unpaid-treatment patient. Completed
	# earlier visits retain their actual Attempts, issues and departure facts.
	# Identity and plan selection remain production commands; only the completed
	# diagnostic background is supplied, never a reservation, attempt or issue.
	if not f.w.facts.sessions.is_empty() or not f.w.facts.preparations.is_empty():
		f.errors.append({"diagnosed_input":key,"reason":"前置医院已有在途临床工作或准备"})
		return ""
	for earlier: Dictionary in f.w.facts.visits.values():
		if not earlier.attempt_ids.is_empty() and earlier.phase!="departed":
			f.errors.append({"diagnosed_input":key,"reason":"原病例尚未实际离院"})
			return ""
	for staff: Dictionary in f.w.facts.staff.values():
		if f.w.facts.attempts.is_empty() and staff.role in ["doctor","nurse"] and staff.on_shift:
			staff.base_prepared = true
			staff.base_task = {}
			staff.block_new_work = false
	f.w.touch()
	var arrival: CommandResult = _command(f,"clinical_arrive",{"arrival_key":key,"binding_id":"B_S49_D37_M37","personality_id":"PP01"})
	if not arrival.accepted:
		f.errors.append({"diagnosed_input":key,"arrival_reason":arrival.reason})
		return ""
	var visit_id: String = arrival.changed_ids[0]
	var visit: Dictionary = f.w.facts.visits[visit_id]
	var actor: Dictionary = f.w.facts.actors[visit.actor_id].duplicate(true)
	actor.location.cell = waiting_cell.duplicate()
	var reason: String = f.s.space.static_reason(f.w,actor,1,Vector2i(int(waiting_cell[0]),int(waiting_cell[1])))
	for room: Dictionary in f.w.facts.rooms.values():
		if int(room.floor_id)==1 and BuildGeometry.contains(room,waiting_cell): reason = "前置站位必须在真实公共区域"
	if not reason.is_empty() or not f.s.space._dynamic_clear(f.w,actor.id,1,f.s.space.body_rectangle(actor)):
		f.errors.append({"diagnosed_input":key,"waiting_cell":waiting_cell,"position_reason":reason if not reason.is_empty() else "前置站位存在真实身体占用"})
		return ""
	f.w.facts.actors[actor.id] = actor
	var diagnostic: Dictionary = f.w.facts.staff.starter_doctor_a
	var profile: Dictionary = _content.catalog.profiles[_content.definition("diseases",visit.disease_id).profile]
	visit.evidence_by_source = {"gp":float(profile.gp_confidence)}
	visit.doctor_fee_quote = _content.doctor_fee(str(diagnostic.title_id))
	visit.clinical_participants = {diagnostic.id:true}
	visit.department_id = "general"
	visit.phase = "wait_consult"
	visit.waiting_reason = "已诊断，等待选择合法方案"
	visit.ticket_id = f.w.new_id("ticket")
	f.w.facts.tickets[visit.ticket_id] = {"id":visit.ticket_id,"visit_id":visit_id,"kind":"consult","enqueued_tick":f.w.sim_tick,
		"service_assigned":false,"called_tick":-1,"waited_ticks":0,"pause_reasons":{}}
	var history_id: String = visit_id+":given_gp"
	var consultation: CommandResult = HospitalLedger.post(f.w,LedgerEntry.new(visit_id,"consultation",int(visit.doctor_fee_quote)))
	var facility_fee: CommandResult = HospitalLedger.post(f.w,LedgerEntry.new(visit_id,"gp",_content.facility_fee("FUR02","gp")))
	var gp: Dictionary = f.w.facts.facilities.gp_station
	gp.used = true
	gp.use_receipts[history_id] = f.w.sim_tick
	gp.condition = maxf(0.0,float(gp.condition)-2.0)
	f.w.facts.rooms.room_gp.used = true
	for payment: Dictionary in f.w.facts.rooms.room_gp.get("cell_payments",{}).values(): payment.used = true
	diagnostic.completed_jobs[history_id] = "diagnosis"
	diagnostic.practice.diagnosis += 1
	f.s.services.research.record_diagnostic_work(f.w,visit,"gp")
	f.s.services.research.settle(f.w)
	var experience: Dictionary = f.w.facts.departments.experience[visit_id]
	experience.phase = visit.phase
	experience.phase_started_tick = f.w.sim_tick
	f.w.touch()
	f.s.space.sync_actor(f.w,actor.id)
	if not consultation.accepted or not facility_fee.accepted or float(profile.gp_confidence)<float(_content.balance.diagnosis_threshold):
		f.errors.append({"diagnosed_input":key,"reason":"给定诊断证据或历史收费前提不成立"})
		return ""
	var selected_plan: CommandResult = _command(f,"clinical_select_plan",{"visit_id":visit_id,"plan_id":"P_D37_COMMON"})
	if not selected_plan.accepted:
		f.errors.append({"diagnosed_input":key,"selection_reason":selected_plan.reason,"ticket_id":visit.ticket_id})
		return ""
	return visit_id

func _case_01() -> Dictionary:
	var f: Dictionary = _new("固定数量采购")
	var start: Dictionary = f.w.freeze()
	var buy: CommandResult = _command(f,"purchase_supplies",{"units":20,"unit_price":20,"order_id":"ops01_order"},"ops01_buy")
	var after: Dictionary = f.w.freeze()
	var again: CommandResult = _command(f,"purchase_supplies",{"units":20,"unit_price":20,"order_id":"ops01_order"},"ops01_buy")
	var restored: Dictionary = _restore(f)
	var replay: CommandResult = _command(restored,"purchase_supplies",{"units":20,"unit_price":20,"order_id":"ops01_order"},"ops01_buy")
	return _result(buy.accepted and again.accepted and replay.accepted and int(f.w.facts.inventory.units)==int(start.inventory.units)+20 and HospitalLedger.balance(f.w)==4600 and f.w.facts.inventory.orders.size()==1 and f.w.freeze()==after and restored.w.freeze()==after,{"cash":HospitalLedger.balance(f.w),"orders":f.w.facts.inventory.orders})

func _case_02() -> Dictionary:
	var reasons: Array = []
	for variant: int in 3:
		var f: Dictionary = _new("采购原子失败",false,399 if variant==0 else 5000)
		if variant==1: f.w.facts.inventory.units = 190
		var before: Dictionary = f.w.freeze()
		var reply: CommandResult = _command(f,"purchase_supplies",{"units":20,"unit_price":21 if variant==2 else 20})
		reasons.append({"variant":variant,"rejected":not reply.accepted,"unchanged":before==f.w.freeze(),"reason":reply.reason})
	var passed: bool = true
	for item: Dictionary in reasons: passed = passed and item.rejected and item.unchanged
	return _result(passed,reasons)

func _case_03() -> Dictionary:
	var f: Dictionary = _new("自动采购整包边界",false,1819)
	f.w.facts.inventory.units = 19
	f.w.facts.inventory.auto_restock = true
	f.s.services.supplies.boundaries(f.w)
	var first: bool = f.w.facts.inventory.units==59 and HospitalLedger.balance(f.w)==1019 and f.w.facts.inventory.orders.size()==1
	f.s.services.supplies.boundaries(f.w)
	first = first and f.w.facts.inventory.orders.size()==1
	var g: Dictionary = _new("预算不足目标仍部分补",false,1200)
	g.w.facts.inventory.units = 0
	g.w.facts.inventory.auto_restock = true
	g.s.services.supplies.boundaries(g.w)
	var second: bool = g.w.facts.inventory.units==10 and HospitalLedger.balance(g.w)==1000
	var manual: CommandResult = _command(g,"purchase_supplies",{"units":1,"unit_price":20})
	return _result(first and second and manual.accepted and HospitalLedger.balance(g.w)==980,{"first_cash":HospitalLedger.balance(f.w),"second_units":g.w.facts.inventory.units,"second_cash":HospitalLedger.balance(g.w)})

func _case_04() -> Dictionary:
	var f: Dictionary = _new("实际扩建采购容量",false,200000)
	f.w.facts.research.append("R34")
	for index: int in 20:
		_place(f,"ops04_out_%d"%index,"M09",[34+(index%5)*5,66+(index/5)*5])
	for index: int in 2:
		_place(f,"ops04_or_%d"%index,"EQ01",[35+index*10,88])
	if not f.errors.is_empty(): return _result(false,f.errors)
	# A lawful accrued day-end obligation of 4000; no fictitious employee budget.
	f.w.facts.economy.daily_accumulators.operating_numerator = 4000*360000
	f.w.facts.economy.operating_accrued_tick = 17999
	f.w.facts.sim_tick = 17999
	_zero_arrivals(f.w)
	f.w.facts.inventory.usage.day_index = 0
	f.w.facts.inventory.usage.previous_units = 320
	f.w.facts.inventory.units = 70
	f.w.facts.inventory.auto_restock = true
	_cash(f.w,8500)
	var quote: Dictionary = f.s.services.supplies.query(f.w)
	f.s.services.supplies.boundaries(f.w)
	var correct: bool = quote.capacity==560 and quote.reorder==80 and quote.target==240 and quote.reserve_budget==4000 and f.w.facts.inventory.units==240 and HospitalLedger.balance(f.w)==5100
	for id: String in f.w.ids("facilities"):
		if id.begins_with("ops04_"):
			var stored: CommandResult = _command(f,"build_store",{"target_id":id})
			if not stored.accepted: f.errors.append(stored.reason)
	var units: int = int(f.w.facts.inventory.units)
	var orders: int = f.w.facts.inventory.orders.size()
	f.s.services.supplies.boundaries(f.w)
	return _result(correct and f.errors.is_empty() and f.s.services.supplies.capacity(f.w)==200 and units==240 and f.w.facts.inventory.units==units and f.w.facts.inventory.orders.size()==orders,{"quote":quote,"errors":f.errors,"stock_after_shrink":f.w.facts.inventory.units})

func _case_05() -> Dictionary:
	var f: Dictionary = _new("命令先关闭补货")
	f.w.facts.inventory.units = 0
	f.w.facts.inventory.auto_restock = true
	var off: GameCommand = GameCommand.new("ops05_off",f.w.hospital_id,-1,"set_auto_restock",BusinessPayload.new({"enabled":false}))
	var off_commands: Array[GameCommand] = [off]
	f.s.step(null,off_commands)
	var closed: bool = f.w.facts.inventory.units==0 and f.w.facts.inventory.orders.is_empty()
	var g: Dictionary = _new("手动入库后再检查")
	g.w.facts.inventory.units = 0
	g.w.facts.inventory.auto_restock = true
	var buy: GameCommand = GameCommand.new("ops05_manual",g.w.hospital_id,-1,"purchase_supplies",BusinessPayload.new({"units":20,"unit_price":20}))
	var purchase_commands: Array[GameCommand] = [buy]
	g.s.step(null,purchase_commands)
	return _result(closed and g.w.facts.inventory.units==20 and g.w.facts.inventory.orders.size()==1 and HospitalLedger.balance(g.w)==4600,{"off_orders":f.w.facts.inventory.orders,"manual_orders":g.w.facts.inventory.orders})

func _case_06() -> Dictionary:
	var f: Dictionary = _new("创作基金采购",false,25)
	f.w.facts.mode = "creative"
	f.w.facts.inventory.units = 5
	var buy: CommandResult = _command(f,"purchase_supplies",{"units":7,"unit_price":20,"order_id":"ops06_order"})
	var order: Dictionary = f.w.facts.inventory.orders.get("ops06_order",{})
	var g: Dictionary = _new("创作基金自动采购",false,0)
	g.w.facts.mode = "creative"
	g.w.facts.inventory.units = 0
	g.w.facts.inventory.auto_restock = true
	g.s.services.supplies.boundaries(g.w)
	var auto_order: Dictionary = g.w.facts.inventory.orders.values()[0] if not g.w.facts.inventory.orders.is_empty() else {}
	return _result(buy.accepted and order.get("cost")==140 and order.get("hospital_paid")==25 and order.get("direct_paid")==115 and order.get("direct_source")=="creative_fund" and f.w.facts.inventory.units==12 and HospitalLedger.balance(f.w)==0 and auto_order.get("units")==60 and auto_order.get("direct_paid")==1200 and g.w.facts.inventory.units==60 and HospitalLedger.balance(g.w)==0 and g.w.facts.inventory.aid_orders==0,{"manual":order,"automatic":auto_order})

func _case_07() -> Dictionary:
	var f: Dictionary = _new("并发治疗包准备",true)
	var first: String = _diagnosed_outpatient(f,"ops07_first",[48,92])
	if first.is_empty(): return _result(false,f.errors)
	var second: String = _diagnosed_outpatient(f,"ops07_second",[49,92])
	if second.is_empty(): return _result(false,f.errors)
	f.w.facts.inventory.units = 1
	var second_ticket: String = f.w.facts.visits[second].ticket_id
	f.s.clinic.dispatch(f.w)
	var reserved: int = f.s.services.supplies.reserved(f.w)
	var one_only: bool = reserved==1 and f.w.facts.preparations.size()==1 and f.w.facts.attempts.is_empty()
	var owner: String = str(f.w.facts.preparations.keys()[0]) if not f.w.facts.preparations.is_empty() else ""
	if owner.is_empty(): return _result(false,{"preparations":f.w.facts.preparations,"visits":f.w.facts.visits})
	var remaining: String = second if owner==first else first
	var ticket: String = f.w.facts.visits[remaining].ticket_id
	var cancelled: CommandResult = _command(f,"clinical_refer",{"visit_id":owner})
	var released: bool = f.s.services.supplies.reserved(f.w)==0 and f.w.facts.inventory.units==1
	var cash: int = HospitalLedger.balance(f.w)
	for tick: int in 900:
		_clinic_tick(f)
		if not f.w.facts.attempts.is_empty(): break
	var committed: bool = f.w.facts.attempts.size()==1 and f.w.facts.inventory.issues.size()==1 and f.w.facts.inventory.units==0 and f.w.facts.inventory.usage.today_units==1 and HospitalLedger.balance(f.w)==cash
	var working: Dictionary = {}
	for session: Dictionary in f.w.facts.sessions.values():
		if session.visit_id==remaining and session.kind=="outpatient": working = session.duplicate(true)
	var original_ticket: bool = working.get("original_ticket",{}).get("id","")==ticket
	var restored: Dictionary = _restore(f)
	var snapshot_units: int = int(restored.w.facts.inventory.units)
	for tick: int in 3: _clinic_tick(restored)
	var resumed: Dictionary = restored.w.facts.sessions.get(str(working.get("id","")),{})
	var same_session: bool = not resumed.is_empty() and resumed.get("original_ticket",{}).get("id","")==ticket
	return _result(one_only and cancelled.accepted and released and committed and original_ticket and same_session and restored.w.facts.inventory.units==snapshot_units and restored.w.facts.inventory.issues.size()==1,{"reserved":reserved,"stock":f.w.facts.inventory.units,"issues":f.w.facts.inventory.issues,"original_remaining_ticket":ticket,"session_id":working.get("id",""),"restored_original_ticket":resumed.get("original_ticket",{}).get("id",""),"second_ticket":second_ticket})

func _case_08() -> Dictionary:
	var empty: Dictionary = _new("空库存不抗议",true)
	empty.w.facts.inventory.units = 0
	var pressure: int = int(empty.w.facts.staff.starter_doctor_b.stress_milli)
	for tick: int in 3: empty.s.services.supplies.advance(empty.w)
	var quiet: bool = empty.w.facts.inventory.shortage.id=="" and empty.w.facts.staff.starter_doctor_b.stress_milli==pressure
	var f: Dictionary = _new("真实缺货与复工",true)
	var visit_id: String = _diagnosed_outpatient(f,"ops08_request",[48,92])
	if visit_id.is_empty(): return _result(false,f.errors)
	f.w.facts.inventory.units = 0
	var requests: Array = f.s.services.supplies.requests(f.w)
	if requests.is_empty(): return _result(false,{"request_missing":f.w.facts.visits[visit_id]})
	var worker_id: String = str(requests[0].staff_ids[0])
	f.w.facts.staff[worker_id].stress_milli = 32000
	var started_tick: int = f.w.sim_tick
	for tick: int in 2:
		f.s.services.supplies.advance(f.w)
		f.w.facts.sim_tick += 1
	var episode_id: String = str(f.w.facts.inventory.shortage.id)
	var participant: Dictionary = f.w.facts.inventory.shortage.participants.get(worker_id,{})
	var accumulated: bool = not episode_id.is_empty() and int(participant.get("blocked_ticks",-1))==2 and int(participant.get("warnings",-1))==0 and int(f.w.facts.staff[worker_id].stress_milli)==32000
	if not accumulated: return _result(false,{"accumulation":participant})
	var thresholds: Array = []
	var boundary_inputs: Array = []
	var warning_once: bool = true
	for index: int in 3:
		# Legal historical input immediately before the next 60-second boundary.
		# The production service performs the actual increment and warning.
		var threshold: int = (index+1)*600
		participant.blocked_ticks = threshold-1
		f.w.facts.sim_tick = started_tick+threshold-1
		f.w.touch()
		var validation: String = f.w.validate(_content)
		boundary_inputs.append({"blocked_ticks":participant.blocked_ticks,"warnings":participant.warnings,"validation":validation})
		if not validation.is_empty(): return _result(false,{"boundary_inputs":boundary_inputs})
		f.s.services.supplies.advance(f.w)
		f.w.facts.sim_tick += 1
		var pressure_after: int = int(f.w.facts.staff[worker_id].stress_milli)
		thresholds.append(pressure_after)
		f.s.services.supplies.advance(f.w)
		f.w.facts.sim_tick += 1
		warning_once = warning_once and int(f.w.facts.staff[worker_id].stress_milli)==pressure_after and int(participant.warnings)==index+1 and str(f.w.facts.inventory.shortage.id)==episode_id
	var striking: bool = f.w.facts.staff[worker_id].get("supply_strike",false)
	var buy: CommandResult = _command(f,"purchase_supplies",{"units":1,"unit_price":20})
	f.s.services.supplies.advance(f.w)
	var until: int = int(f.w.facts.staff[worker_id].get("supply_return_tick",-1))
	var closed: bool = f.w.facts.inventory.shortage.id=="" and f.w.facts.inventory.shortage.get("last_id")==episode_id and int(f.w.facts.staff[worker_id].stress_milli)==44000 and not f.w.facts.staff[worker_id].get("supply_strike",false) and until==f.w.sim_tick+300
	var restored: Dictionary = _restore(f)
	restored.s.services.supplies.advance(restored.w)
	var no_repeat: bool = restored.w.facts.staff[worker_id].stress_milli==44000 and restored.w.facts.staff[worker_id].supply_return_tick==until
	restored.w.facts.sim_tick = until-1
	_zero_arrivals(restored.w)
	var before_return: Dictionary = restored.s.clinic.plan_quote(restored.w,visit_id,str(restored.w.facts.visits[visit_id].requested_plan_id))
	restored.w.facts.sim_tick = until
	_zero_arrivals(restored.w)
	var after_return: Dictionary = restored.s.clinic.plan_quote(restored.w,visit_id,str(restored.w.facts.visits[visit_id].requested_plan_id))
	for tick: int in 500:
		_clinic_tick(restored)
		if not restored.w.facts.attempts.is_empty(): break
	return _result(quiet and accumulated and warning_once and thresholds==[38000,44000,50000] and striking and buy.accepted and closed and no_repeat and not before_return.get("ok",true) and after_return.get("ok",false) and restored.w.facts.attempts.size()==1,{"boundary_inputs":boundary_inputs,"accumulated":accumulated,"warning_once":warning_once,"thresholds":thresholds,"strike":striking,"return_tick":until,"closed":f.w.facts.inventory.shortage,"before_return":before_return,"after_return":after_return,"attempts_after_return":restored.w.facts.attempts.size()})

func _case_09() -> Dictionary:
	var f: Dictionary = _new("先补首项准备",true,5000)
	var visit_id: String = _diagnosed_outpatient(f,"ops09_request",[48,92])
	if visit_id.is_empty(): return _result(false,f.errors)
	f.w.facts.inventory.units = 0
	_cash(f.w,35)
	var before: Dictionary = f.w.freeze()
	var suggestion: Dictionary = f.s.services.supplies.top_up(f.w)
	var readonly: bool = before==f.w.freeze()
	var exact: bool = suggestion.get("units")==1 and suggestion.get("cost")==20 and suggestion.get("cash_after")==15 and suggestion.get("target",{}).get("visit_id")==visit_id and f.w.facts.preparations.is_empty()
	var buy: CommandResult = _command(f,"purchase_supplies",{"units":1,"unit_price":20})
	return _result(readonly and exact and buy.accepted and f.w.facts.inventory.units==1 and HospitalLedger.balance(f.w)==15 and f.w.facts.preparations.is_empty() and f.s.services.supplies.top_up(f.w).is_empty(),suggestion)

func _case_10() -> Dictionary:
	var f: Dictionary = _new("每天一次援助采购",true)
	var visit_id: String = _diagnosed_outpatient(f,"ops10_request",[48,92])
	if visit_id.is_empty(): return _result(false,f.errors)
	f.w.facts.inventory.units = 0
	_cash(f.w,100)
	var buy: CommandResult = _command(f,"supply_aid",{"units":20,"unit_price":20,"order_id":"ops10_aid"},"ops10_buy")
	var order: Dictionary = f.w.facts.inventory.orders.get("ops10_aid",{})
	var first: bool = buy.accepted and f.w.facts.inventory.units==20 and HospitalLedger.balance(f.w)==0 and order.get("hospital_paid")==100 and order.get("direct_paid")==300 and order.get("direct_source")=="community_aid" and f.w.facts.inventory.aid_orders==1
	var restored: Dictionary = _restore(f)
	# The later same-day branch has genuinely insufficient stock again; quota is
	# independent of the current shortage and survives restoration.
	restored.w.facts.inventory.units = 0
	var before: Dictionary = restored.w.freeze()
	var again: CommandResult = _command(restored,"supply_aid",{"units":20,"unit_price":20})
	var none: Dictionary = _new("无需求援助拒绝",false,0)
	var no_request: CommandResult = _command(none,"supply_aid",{"units":20})
	return _result(first and not again.accepted and before==restored.w.freeze() and not no_request.accepted and none.w.facts.inventory.aid_orders==0,{"order":order,"initial_reason":buy.reason,"repeat_reason":again.reason,"no_request":no_request.reason})

func _case_11() -> Dictionary:
	var f: Dictionary = _new("真实环境来源")
	var clean: Dictionary = f.s.services.environment.environment_at(f.w,1,[44,80])
	_place(f,"ops11_plant_a","FUR25",[42,79])
	var once: Dictionary = f.s.services.environment.environment_at(f.w,1,[44,80])
	_place(f,"ops11_plant_b","FUR25",[43,79])
	var twice: Dictionary = f.s.services.environment.environment_at(f.w,1,[44,80])
	var ids: Array = []
	for index: int in 4:
		ids.append(f.s.services.environment.spawn_dirt(f.w,"CL01","ops11_spill_%d"%index,"ops11_fact_%d"%index,1,[43+index,81]))
	var dirty: Dictionary = f.s.services.environment.environment_at(f.w,1,[44,80])
	var brief: Dictionary = f.s.services.environment.environment_at(f.w,1,[44,80],"",false)
	var expected_brief: Dictionary = dirty.duplicate(true)
	expected_brief.sources = []
	var ranges: Dictionary = _new("R15仅扩大正面覆盖")
	_place(ranges,"range_plant","FUR25",[44,80])
	var far_dirt: String = ranges.s.services.environment.spawn_dirt(ranges.w,"CL01","ops11_far_spill","ops11_far_fact",1,[43,81])
	var original_range: Dictionary = ranges.s.services.environment.environment_at(ranges.w,1,[44,85])
	ranges.w.facts.research.append("R15")
	var before: Dictionary = ranges.w.freeze()
	var upgraded_range: Dictionary = ranges.s.services.environment.environment_at(ranges.w,1,[44,85])
	var exact_ranges: bool = brief==expected_brief and not far_dirt.is_empty() and ranges.w.facts.environment.dirt[far_dirt].cell==[43,81] and original_range.value==43 and upgraded_range.value==49 and upgraded_range.dirt==0 and upgraded_range.clean and before==ranges.w.freeze()
	exact_ranges = exact_ranges and _sampling_matches(f,[[44,80],[44.25,80.0]]) and _sampling_matches(ranges,[[44,85]])
	return _result(exact_ranges and f.errors.is_empty() and ranges.errors.is_empty() and clean.value==43 and once.value==49 and twice.value==49 and ids.size()==4 and not "" in ids and dirty.dirt==4 and not dirty.clean and dirty.value==25 and int(twice.value)-int(dirty.value)==24,{"base":clean,"one_category":once,"duplicate_category":twice,"dirty":dirty,"original_range":original_range,"upgraded_range":upgraded_range,"exact_ranges":exact_ranges,"errors":f.errors})

func _case_12() -> Dictionary:
	var f: Dictionary = _new("暂停付费装修")
	var payload: Dictionary = {"material_id":"MAT01","floor_id":1,"units":[{"cell":[42,80]},{"cell":[44,80]}],"allow_waiting":true}
	var before_value: int = int(f.s.services.environment.environment_at(f.w,1,[42,80]).value)
	var quote: Dictionary = f.s.services.environment.renovation_quote(f.w,payload)
	var ordered: CommandResult = _command(f,"renovation_order",payload)
	var order: Dictionary = f.w.facts.environment.orders.values()[0] if not f.w.facts.environment.orders.is_empty() else {}
	var paused: bool = f.w.sim_tick==0 and f.w.facts.environment.surfaces.is_empty() and f.s.services.environment.environment_at(f.w,1,[42,80]).value==before_value
	var g: Dictionary = _new("不足材料费",false,49)
	var before: Dictionary = g.w.freeze()
	var denied: CommandResult = _command(g,"renovation_order",payload)
	return _result(quote.get("cost")==50 and quote.get("work_seconds")==16 and ordered.accepted and HospitalLedger.balance(f.w)==4950 and order.get("units",[]).size()==2 and order.units[0].remaining_milli==8000 and order.units[1].remaining_milli==8000 and paused and not denied.accepted and before==g.w.freeze(),{"quote":quote,"order":order,"rejection":denied.reason})

func _decorator(f: Dictionary) -> bool:
	var placed: bool = _place(f,"ops_tool","SE02",[38,80])
	_staff(f,"ops_decorator","decorator",[39,80])
	return placed

func _case_13() -> Dictionary:
	var f: Dictionary = _new("真实装修完工")
	var ordered: CommandResult = _command(f,"renovation_order",{"material_id":"MAT01","floor_id":1,"units":[{"cell":[42,80]}],"allow_waiting":true})
	if not ordered.accepted: return _result(false,ordered.reason)
	var id: String = ordered.changed_ids[0]
	_work_tick(f,"environment")
	var waiting: bool = f.w.facts.environment.orders[id].units[0].remaining_milli==8000 and f.w.facts.environment.surfaces.is_empty()
	if not _decorator(f): return _result(false,f.errors)
	for tick: int in 400:
		_work_tick(f,"environment")
		if f.w.facts.environment.orders[id].phase=="completed": break
	var unit: Dictionary = f.w.facts.environment.orders[id].units[0]
	var surface: Dictionary = f.w.facts.environment.surfaces.get("1:42:80:floor:",{})
	var receipt: Dictionary = f.w.facts.environment.receipts.get(str(unit.id)+":renovation_completed",{})
	return _result(waiting and unit.phase=="completed" and unit.remaining_milli==0 and surface.get("material_id")=="MAT01" and surface.get("paid_cost")==25 and receipt.get("standard_work_milli")==8000 and receipt.get("staff_id")=="ops_decorator" and f.s.services.environment.environment_at(f.w,1,[42,80]).value==49,{"unit":unit,"surface":surface,"receipt":receipt})

func _case_14() -> Dictionary:
	var f: Dictionary = _new("装修取消与恢复")
	if not _decorator(f): return _result(false,f.errors)
	var ordered: CommandResult = _command(f,"renovation_order",{"material_id":"MAT01","floor_id":1,"units":[{"cell":[42,80]},{"cell":[44,80]},{"cell":[46,80]}]})
	if not ordered.accepted: return _result(false,ordered.reason)
	var id: String = ordered.changed_ids[0]
	for tick: int in 600:
		_work_tick(f,"environment")
		var units: Array = f.w.facts.environment.orders[id].units
		if units[0].phase=="completed" and units[1].started: break
	var order: Dictionary = f.w.facts.environment.orders[id]
	if order.units[0].phase!="completed" or not order.units[1].started: return _result(false,order)
	_command(f,"renovation_pause",{"order_id":id})
	var remaining: int = int(f.w.facts.environment.orders[id].units[1].remaining_milli)
	var cash: int = HospitalLedger.balance(f.w)
	_command(f,"renovation_cancel",{"order_id":id})
	_command(f,"renovation_cancel",{"order_id":id})
	for tick: int in 5: _work_tick(f,"environment")
	var held: bool = f.w.facts.environment.orders[id].units[1].remaining_milli==remaining and HospitalLedger.balance(f.w)==cash+25 and f.w.facts.environment.orders[id].units[2].phase=="cancelled"
	var restored: Dictionary = _restore(f)
	_command(restored,"renovation_resume",{"order_id":id})
	for tick: int in 350:
		_work_tick(restored,"environment")
		if restored.w.facts.environment.orders[id].phase=="cancelled": break
	var finished: bool = restored.w.facts.environment.orders[id].phase=="cancelled" and restored.w.facts.environment.orders[id].units[1].phase=="completed" and restored.w.facts.environment.surfaces.size()==2
	var replace: CommandResult = _command(restored,"renovation_order",{"material_id":"MAT02","floor_id":1,"units":[{"cell":[42,80]}]})
	if not replace.accepted: return _result(false,{"cancel_held":held,"finished":finished,"replace_reason":replace.reason})
	var replace_id: String = replace.changed_ids[0]
	var prepaid: int = HospitalLedger.balance(restored.w)
	for tick: int in 400:
		_work_tick(restored,"environment")
		if restored.w.facts.environment.orders[replace_id].phase=="completed": break
	var reclaimed: bool = HospitalLedger.balance(restored.w)==prepaid+20 and restored.w.facts.environment.surfaces["1:42:80:floor:"].material_id=="MAT02"
	return _result(held and finished and reclaimed,{"cancel":restored.w.facts.environment.orders[id],"replacement":restored.w.facts.environment.orders[replace_id],"cash":HospitalLedger.balance(restored.w)})

func _case_15() -> Dictionary:
	var f: Dictionary = _new("真实使用产生持久垃圾",false,20000)
	_place(f,"ops_water","FUR17",[40,80])
	_place(f,"ops_toilet","FUR07",[46,80])
	_place(f,"ops_outpatient","M09",[52,80])
	if not f.errors.is_empty(): return _result(false,f.errors)
	for source: Dictionary in [{"kind":"water_completed","id":"ops_water","uses":6},{"kind":"toilet_completed","id":"ops_toilet","uses":8},{"kind":"outpatient_completed","id":"ops_outpatient","uses":8}]:
		for index: int in int(source.uses):
			f.s.services.environment.record_use(f.w,source.kind,source.id,"actual_%d"%index)
		f.s.services.environment.record_use(f.w,source.kind,source.id,"actual_%d"%(int(source.uses)-1))
	var work: Array = []
	for patch: Dictionary in f.w.facts.environment.dirt.values(): work.append(int(patch.remaining_milli))
	work.sort()
	var before: Dictionary = f.w.facts.environment.dirt.duplicate(true)
	var stored: CommandResult = _command(f,"build_store",{"target_id":"ops_outpatient"})
	var restored: Dictionary = _restore(f)
	return _result(stored.accepted and work==[4000,6000,6000] and f.w.facts.environment.dirt.size()==3 and before==restored.w.facts.environment.dirt,{"work_milli":work,"dirt":restored.w.facts.environment.dirt,"store":stored.reason})

func _case_16() -> Dictionary:
	var f: Dictionary = _new("清扫接班与真实完成")
	var id: String = f.s.services.environment.spawn_dirt(f.w,"CL01","ops16_incident","ops16_spill_fact",1,[42,80])
	if id.is_empty(): return _result(false,"合法地格未生成污物")
	for tick: int in 5: _work_tick(f,"environment")
	var unattended: bool = f.w.facts.environment.dirt[id].remaining_milli==4000
	_staff(f,"ops_cleaner_a","cleaner",[40,80])
	for tick: int in 100:
		_work_tick(f,"environment")
		if int(f.w.facts.environment.dirt.get(id,{}).get("remaining_milli",0))<=3000: break
	if not f.w.facts.environment.dirt.has(id): return _result(false,"清扫在接班前意外完成")
	var remaining: int = int(f.w.facts.environment.dirt[id].remaining_milli)
	var copied: Dictionary = _restore(f)
	var paused: bool = copied.w.facts.environment.dirt[id].remaining_milli==remaining
	copied.w.facts.staff.ops_cleaner_a.on_shift = false
	copied.s.space.request_move(copied.w,"ops_cleaner_a",1,[39,83])
	_staff(copied,"ops_cleaner_b","cleaner",[40,81])
	for tick: int in 200:
		_work_tick(copied,"environment")
		if not copied.w.facts.environment.dirt.has(id): break
	var receipt: Dictionary = copied.w.facts.environment.receipts.get(id+":cleanup_completed",{})
	var receipts: int = copied.w.facts.environment.receipts.size()
	for tick: int in 3: _work_tick(copied,"environment")
	return _result(unattended and paused and remaining>0 and remaining<4000 and not copied.w.facts.environment.dirt.has(id) and receipt.get("standard_work_milli")==4000 and receipt.get("staff_id")=="ops_cleaner_b" and copied.w.facts.environment.receipts.size()==receipts,{"remaining_at_handoff":remaining,"receipt":receipt,"pending":copied.w.facts.environment.dirt})

func _case_17() -> Dictionary:
	var f: Dictionary = _new("桶内垃圾合并")
	_place(f,"ops_bin","FUR18",[42,80])
	var first: String = f.s.services.environment.spawn_dirt(f.w,"CL02","ops17_water_a","ops17_sixth_drink",1,[40,80])
	var second: String = f.s.services.environment.spawn_dirt(f.w,"CL02","ops17_water_b","ops17_other_drink",1,[40,82])
	if first.is_empty(): return _result(false,{"errors":f.errors,"dirt":f.w.facts.environment.dirt})
	var patch: Dictionary = f.w.facts.environment.dirt[first]
	var observation: Dictionary = f.s.services.environment.environment_at(f.w,1,[43,80])
	var refused: CommandResult = _command(f,"build_store",{"target_id":"ops_bin"})
	_staff(f,"ops_bin_cleaner","cleaner",[43,80])
	for tick: int in 200:
		_work_tick(f,"environment")
		if not f.w.facts.environment.dirt.has(first): break
	var g: Dictionary = _new("后摆桶不吸地污")
	var ground_id: String = g.s.services.environment.spawn_dirt(g.w,"CL02","ops17_earlier_water","ops17_old_ground",1,[40,80])
	_place(g,"ops_later_bin","FUR18",[42,80])
	return _result(f.errors.is_empty() and g.errors.is_empty() and first==second and patch.bin_id=="ops_bin" and patch.total_milli==4000 and observation.dirt==0 and observation.clean and observation.value==43 and not refused.accepted and not f.w.facts.environment.dirt.has(first) and g.w.facts.environment.dirt.has(ground_id) and g.w.facts.environment.dirt[ground_id].bin_id=="",{"bin_patch":patch,"environment":observation,"refused_store":refused.reason,"old_ground":g.w.facts.environment.dirt})

func _case_18() -> Dictionary:
	var f: Dictionary = _new("实际临床噪声",true)
	var visit_id: String = _diagnosed_outpatient(f,"ops18_work",[48,92])
	if visit_id.is_empty(): return _result(false,f.errors)
	var before: Dictionary = f.s.services.environment.environment_at(f.w,1,[51,88])
	for tick: int in 500:
		_clinic_tick(f)
		if not f.w.facts.attempts.is_empty(): break
	var running: Dictionary = f.s.services.environment.environment_at(f.w,1,[51,88])
	var paused_query: Dictionary = f.s.services.environment.environment_at(f.w,1,[51,88])
	var g: Dictionary = _new("施工格边隔音")
	if not _decorator(g): return _result(false,g.errors)
	var applied: CommandResult = _command(g,"renovation_order",{"material_id":"MAT01","floor_id":1,"units":[{"cell":[42,80]}]})
	if not applied.accepted: return _result(false,applied.reason)
	var id: String = applied.changed_ids[0]
	var queued: Dictionary = g.s.services.environment.environment_at(g.w,1,[42,84])
	for tick: int in 200:
		_work_tick(g,"environment")
		if g.w.facts.environment.orders[id].units[0].started: break
	var construction: Dictionary = g.s.services.environment.environment_at(g.w,1,[42,84])
	_place(g,"ops_noise_screen","FUR23",[42,82])
	var screened: Dictionary = g.s.services.environment.environment_at(g.w,1,[42,84])
	var screened_cell: Dictionary = g.s.services.environment.environment_at(g.w,1,[42,83])
	var screened_fraction: Dictionary = g.s.services.environment.environment_at(g.w,1,[42.25,83.0])
	var bypass: Dictionary = g.s.services.environment.environment_at(g.w,1,[43,82])
	var moved: CommandResult = _command(g,"build_move",{"target_id":"ops_noise_screen","floor_id":1,"cell":[46,82]})
	var after_move: Dictionary = g.s.services.environment.environment_at(g.w,1,[42.25,83.0])
	var moved_back: CommandResult = _command(g,"build_move",{"target_id":"ops_noise_screen","floor_id":1,"cell":[42,82]})
	var rotated: CommandResult = _command(g,"build_rotate",{"target_id":"ops_noise_screen","rotation":1})
	var after_rotation: Dictionary = g.s.services.environment.environment_at(g.w,1,[42.25,83.0])
	var reset_screen: CommandResult = _command(g,"build_rotate",{"target_id":"ops_noise_screen","rotation":0})
	var after_reset: Dictionary = g.s.services.environment.environment_at(g.w,1,[42.25,83.0])
	if not _sampling_matches(f,[[51,88]]) or not _sampling_matches(g,[[42,84],[42,83],[42.25,83.0],[43,82]]): return _result(false,{"sampling_index":"与同一观察边界的逐项来源结果不一致"})
	return _result(before.noise==0 and running.noise==10 and paused_query.noise==10 and queued.noise==0 and construction.noise==15 and screened.noise==0 and screened_cell.noise==0 and screened_fraction.noise==0 and bypass.noise==15 and moved.accepted and after_move.noise==15 and moved_back.accepted and rotated.accepted and after_rotation.noise==15 and reset_screen.accepted and after_reset.noise==0 and g.errors.is_empty(),{"before":before.noise,"running":running.noise,"queued":queued.noise,"construction":construction.noise,"screened":screened.noise,"screened_cell":screened_cell.noise,"screened_fraction":screened_fraction.noise,"bypass":bypass.noise,"after_move":after_move.noise,"after_rotation":after_rotation.noise,"after_reset":after_reset.noise,"errors":g.errors})

func _sampling_matches(f: Dictionary, cells: Array) -> bool:
	var service: RefCounted = f.s.services.environment
	var expected: Array = []
	var before: Dictionary = f.w.freeze()
	for cell: Array in cells: expected.append(service.environment_at(f.w,1,cell))
	service.begin_query(f.w)
	var equal: bool = true
	for index: int in cells.size():
		var current: Dictionary = service.environment_at(f.w,1,cells[index])
		# Source order is explanatory; compare the same complete source records.
		for result: Dictionary in [expected[index],current]:
			result.sources.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return JSON.stringify(a)<JSON.stringify(b))
		equal = equal and current==expected[index]
	service.end_query()
	return equal and before==f.w.freeze()

func _machine(label: String) -> Dictionary:
	var f: Dictionary = _new(label,false,10000)
	_place(f,"ops_machine","M09",[42,80])
	return f

func _case_19() -> Dictionary:
	var f: Dictionary = _new("首次真实工作磨损",true)
	var visit_id: String = _outpatient(f,"ops19_visit")
	if visit_id.is_empty(): return _result(false,f.errors)
	var before: float = float(f.w.facts.facilities.cold_machine.condition)
	for tick: int in 500:
		_clinic_tick(f)
		if not f.w.facts.attempts.is_empty(): break
	var worn: float = float(f.w.facts.facilities.cold_machine.condition)
	var restored: Dictionary = _restore(f)
	for tick: int in 5: _clinic_tick(restored)
	var chair: CommandResult = _command(restored,"maintenance_order",{"facility_id":"chair_1"})
	var water: CommandResult = _command(restored,"maintenance_order",{"facility_id":"water"})
	restored.s.services.maintenance.boundaries(restored.w)
	var illegal_job: bool = false
	for job: Dictionary in restored.w.facts.maintenance.jobs.values():
		if job.facility_id in ["chair_1","water","bin"]: illegal_job = true
	return _result(before==100.0 and worn==98.0 and restored.w.facts.facilities.cold_machine.condition==98.0 and f.w.facts.facilities.cold_machine.use_receipts.size()==1 and not chair.accepted and not water.accepted and not illegal_job,{"before":before,"after":worn,"uses":f.w.facts.facilities.cold_machine.use_receipts,"jobs":restored.w.facts.maintenance.jobs})

func _case_20() -> Dictionary:
	var f: Dictionary = _machine("维护阈值唯一工单")
	if not f.errors.is_empty(): return _result(false,f.errors)
	f.w.facts.facilities.ops_machine.condition = 46.0
	f.s.services.maintenance.boundaries(f.w)
	var above: bool = f.w.facts.maintenance.jobs.is_empty()
	f.w.facts.facilities.ops_machine.condition = 45.0
	f.s.services.maintenance.boundaries(f.w)
	f.s.services.maintenance.boundaries(f.w)
	var id: String = str(f.w.facts.facilities.ops_machine.maintenance_order_id)
	if id.is_empty(): return _result(false,f.w.facts.maintenance)
	var unique: bool = f.w.facts.maintenance.jobs.size()==1 and f.w.facts.maintenance.jobs[id].paid_parts==0
	var cash: int = HospitalLedger.balance(f.w)
	_command(f,"maintenance_policy",{"policy_id":"MP01"})
	f.s.services.maintenance.boundaries(f.w)
	var removed: bool = f.w.facts.maintenance.jobs[id].phase=="cancelled" and HospitalLedger.balance(f.w)==cash
	f.w.facts.facilities.ops_machine.condition = 61.0
	var high: CommandResult = _command(f,"maintenance_order",{"facility_id":"ops_machine"})
	f.w.facts.facilities.ops_machine.condition = 60.0
	var allowed: CommandResult = _command(f,"maintenance_order",{"facility_id":"ops_machine"})
	return _result(above and unique and removed and not high.accepted and allowed.accepted and HospitalLedger.balance(f.w)==cash,{"jobs":f.w.facts.maintenance.jobs,"high_reason":high.reason})

func _case_21() -> Dictionary:
	var f: Dictionary = _machine("实际维修员修复")
	if not f.errors.is_empty(): return _result(false,f.errors)
	f.w.facts.facilities.ops_machine.condition = 18.0
	f.w.facts.facilities.ops_machine.failed = true
	f.s.services.maintenance.boundaries(f.w)
	var id: String = str(f.w.facts.facilities.ops_machine.maintenance_order_id)
	if id.is_empty(): return _result(false,f.w.facts.maintenance)
	var cash: int = HospitalLedger.balance(f.w)
	var before_quote: Dictionary = f.w.freeze()
	var quote: Dictionary = f.s.services.maintenance.service_quote(f.w,"ops_machine")
	var quote_readonly: bool = before_quote==f.w.freeze() and quote.ok and quote.cost==40 and quote.remaining_milli==30000
	var entry: Array = f.w.facts.entry.cell.duplicate()
	f.w.facts.floors.overrides["1"].blocked.append(entry)
	for tick: int in 5: _work_tick(f,"maintenance")
	var unattended: bool = f.w.facts.facilities.ops_machine.failed and f.w.facts.maintenance.jobs[id].remaining_milli==30000 and HospitalLedger.balance(f.w)==cash and f.w.facts.maintenance.contractors.is_empty() and f.w.facts.staff.is_empty()
	f.w.facts.floors.overrides["1"].blocked.erase(entry)
	for tick: int in 500:
		_work_tick(f,"maintenance")
		if f.w.facts.maintenance.jobs[id].phase=="completed": break
	var job: Dictionary = f.w.facts.maintenance.jobs[id]
	var item: Dictionary = f.w.facts.facilities.ops_machine
	var receipt: Dictionary = f.w.facts.maintenance.receipts.get(id+":repair_completed",{})
	var worker_id: String = str(receipt.get("worker_id",""))
	var finished_in_hospital: bool = not worker_id.is_empty() and f.w.facts.actors[worker_id].location.kind=="floor" and f.w.facts.maintenance.contractors[worker_id].phase=="leaving" and f.w.facts.staff.is_empty()
	var restored: Dictionary = _restore(f)
	var exit: Array = restored.s.space.exit_cell(restored.w,restored.w.facts.actors[worker_id])
	restored.w.facts.floors.overrides["1"].blocked.append(exit)
	for tick: int in 5: _work_tick(restored,"maintenance")
	var held_at_blocked_exit: bool = restored.w.facts.actors[worker_id].location.kind=="floor" and restored.w.facts.maintenance.contractors[worker_id].phase=="leaving"
	restored.w.facts.floors.overrides["1"].blocked.erase(exit)
	for tick: int in 500:
		_work_tick(restored,"maintenance")
		if restored.w.facts.actors[worker_id].location.kind=="outside": break
	var departed: bool = restored.w.facts.actors[worker_id].location.kind=="outside" and restored.w.facts.maintenance.contractors[worker_id].phase=="departed" and restored.w.facts.staff.is_empty()
	return _result(quote_readonly and unattended and job.phase=="completed" and job.completed_milli==30000 and job.paid_parts==40 and HospitalLedger.balance(restored.w)==cash-40 and item.condition==100.0 and not item.failed and item.repair_grace_until==int(receipt.get("tick",-2000))+1800 and receipt.get("staff_id","").is_empty() and finished_in_hospital and held_at_blocked_exit and departed and restored.w.validate(_content).is_empty(),{"quote":quote,"quote_readonly":quote_readonly,"no_worker_before_entry_space":unattended,"job":job,"item":item,"receipt":receipt,"retained_body_at_completion":finished_in_hospital,"blocked_exit_no_teleport":held_at_blocked_exit,"actual_departure":departed,"validation":restored.w.validate(_content)})

func _case_22() -> Dictionary:
	var f: Dictionary = _machine("保养转故障同单")
	if not f.errors.is_empty(): return _result(false,f.errors)
	f.w.facts.facilities.ops_machine.condition = 45.0
	f.s.services.maintenance.boundaries(f.w)
	var id: String = str(f.w.facts.facilities.ops_machine.maintenance_order_id)
	if id.is_empty(): return _result(false,f.w.facts.maintenance)
	var cash: int = HospitalLedger.balance(f.w)
	for tick: int in 200:
		_work_tick(f,"maintenance")
		if int(f.w.facts.maintenance.jobs[id].completed_milli)>=8000: break
	var first: bool = f.w.facts.maintenance.jobs[id].completed_milli==8000 and f.w.facts.maintenance.jobs[id].paid_parts==20 and HospitalLedger.balance(f.w)==cash-20
	f.w.facts.facilities.ops_machine.pending_failure = true
	f.s.services.maintenance.boundaries(f.w)
	var promoted: Dictionary = f.w.facts.maintenance.jobs[id].duplicate(true)
	var carried: bool = promoted.kind=="repair" and promoted.remaining_milli==22000 and promoted.completed_milli==8000 and promoted.repair_difference_due==20 and f.w.facts.maintenance.jobs.size()==1
	for tick: int in 400:
		_work_tick(f,"maintenance")
		if f.w.facts.maintenance.jobs[id].phase=="completed": break
	return _result(first and carried and f.w.facts.maintenance.jobs[id].phase=="completed" and f.w.facts.maintenance.jobs[id].paid_parts==40 and HospitalLedger.balance(f.w)==cash-40 and f.w.facts.maintenance.receipts.size()==1,{"promoted":promoted,"final":f.w.facts.maintenance.jobs[id],"receipts":f.w.facts.maintenance.receipts})

func _case_23() -> Dictionary:
	var f: Dictionary = _machine("维修库存与暂停接续")
	if not f.errors.is_empty(): return _result(false,f.errors)
	f.w.facts.facilities.ops_machine.failed = true
	f.s.services.maintenance.boundaries(f.w)
	var id: String = str(f.w.facts.facilities.ops_machine.maintenance_order_id)
	if id.is_empty(): return _result(false,f.w.facts.maintenance)
	for tick: int in 100:
		_work_tick(f,"maintenance")
		if int(f.w.facts.maintenance.jobs[id].completed_milli)>=1000: break
	_command(f,"maintenance_pause",{"job_id":id})
	var remaining: int = int(f.w.facts.maintenance.jobs[id].remaining_milli)
	var cash: int = HospitalLedger.balance(f.w)
	var no_cancel: CommandResult = _command(f,"maintenance_cancel",{"job_id":id})
	for tick: int in 3: _work_tick(f,"maintenance")
	var held: bool = f.w.facts.maintenance.jobs[id].remaining_milli==remaining and not no_cancel.accepted
	var stored: CommandResult = _command(f,"build_store",{"target_id":"ops_machine"})
	if not stored.accepted: return _result(false,{"stored":stored.reason,"job":f.w.facts.maintenance.jobs[id]})
	var restored: Dictionary = _restore(f)
	var in_stock: bool = restored.w.facts.maintenance.jobs[id].phase=="inventory" and restored.w.facts.maintenance.jobs[id].remaining_milli==remaining
	_place(restored,"ops_machine","M09",[42,80],"","ops_machine")
	_command(restored,"maintenance_resume",{"job_id":id})
	for tick: int in 500:
		_work_tick(restored,"maintenance")
		if restored.w.facts.maintenance.jobs[id].phase=="completed": break
	return _result(held and in_stock and restored.errors.is_empty() and restored.w.facts.maintenance.jobs[id].phase=="completed" and restored.w.facts.maintenance.jobs[id].paid_parts==40 and HospitalLedger.balance(restored.w)==cash and restored.w.facts.maintenance.receipts.size()==1,{"remaining":remaining,"job":restored.w.facts.maintenance.jobs[id],"errors":restored.errors})

func _case_24() -> Dictionary:
	var checks: Array = []
	for variant: int in 3:
		var f: Dictionary = _machine("升级前置原子拒绝")
		if variant!=0: f.w.facts.research.append("R12")
		if variant==1: _cash(f.w,419)
		if variant==2:
			f.w.facts.facilities.ops_machine.borrowed = true
			f.w.facts.facilities.ops_machine.ownership = "borrowed"
			f.w.facts.facilities.ops_machine.paid_cost = 0
		var before: Dictionary = f.w.freeze()
		var denied: CommandResult = _command(f,"upgrade_order",{"facility_id":"ops_machine","target_level":1})
		checks.append({"variant":variant,"ok":not denied.accepted and before==f.w.freeze() and f.errors.is_empty(),"reason":denied.reason})
	var gift: Dictionary = _new("赠机可付费升级")
	gift.w.facts.research.append("R12")
	_place(gift,"starter_gift_M09","M09",[42,80],"","starter_gift_M09")
	var quote: Dictionary = gift.s.services.maintenance.upgrade_quote(gift.w,{"facility_id":"starter_gift_M09","target_level":1})
	var passed: bool = gift.errors.is_empty() and quote.ok and quote.cost==420 and gift.w.facts.facilities.starter_gift_M09.paid_cost==0
	for check: Dictionary in checks: passed = passed and check.ok
	return _result(passed,{"rejections":checks,"gift_quote":quote,"errors":gift.errors})

func _case_25() -> Dictionary:
	var f: Dictionary = _machine("未开工升级取消")
	if not f.errors.is_empty(): return _result(false,f.errors)
	f.w.facts.research.append("R12")
	var cash: int = HospitalLedger.balance(f.w)
	var applied: CommandResult = _command(f,"upgrade_order",{"facility_id":"ops_machine","target_level":1})
	if not applied.accepted: return _result(false,applied.reason)
	var id: String = applied.changed_ids[0]
	for tick: int in 5: _work_tick(f,"maintenance")
	var paid_wait: bool = f.w.facts.facilities.ops_machine.grade==0 and f.w.facts.maintenance.upgrades[id].remaining_milli==30000 and HospitalLedger.balance(f.w)==cash-420
	var cancel: CommandResult = _command(f,"upgrade_cancel",{"order_id":id})
	var again: CommandResult = _command(f,"upgrade_cancel",{"order_id":id})
	return _result(paid_wait and cancel.accepted and again.accepted and HospitalLedger.balance(f.w)==cash and f.w.facts.maintenance.upgrades[id].refunded==420 and f.w.facts.maintenance.upgrades[id].phase=="cancelled" and not f.w.facts.facilities.ops_machine.upgrading_block and f.w.facts.facilities.ops_machine.get("completed_upgrade_paid_cost",0)==0,{"order":f.w.facts.maintenance.upgrades[id],"item":f.w.facts.facilities.ops_machine})

func _case_26() -> Dictionary:
	var f: Dictionary = _new("完成升级不改临床承诺",true)
	# Select a reproducible successful input before the first real Attempt exists.
	var seeded: bool = false
	for seed_value: int in range(1,1000):
		var generator: RandomNumberGenerator = RandomNumberGenerator.new()
		generator.seed = seed_value
		var initial: int = generator.state
		if generator.randi_range(0,9999)<100:
			f.w.facts.rng.treatment = {"algorithm":"godot-pcg32-4.7.2","seed_decimal":str(seed_value),"state_decimal":str(initial)}
			seeded = true
			break
	if not seeded: return _result(false,"未建立首试成功的确定性随机输入")
	var visit_id: String = _diagnosed_outpatient(f,"ops26_visit",[48,92])
	if visit_id.is_empty(): return _result(false,f.errors)
	# Continue the doctor's existing plan while its previous service releases.
	# Re-selecting it here would recheck readiness before safe handoff completes.
	if f.w.facts.visits[visit_id].plan_decision.get("plan_id","")!="P_D37_COMMON":
		return _result(false,{"unexpected_plan":f.w.facts.visits[visit_id].plan_decision})
	for tick: int in 500:
		_clinic_tick(f)
		if not f.w.facts.attempts.is_empty(): break
	if f.w.facts.attempts.is_empty(): return _result(false,"未形成实际Attempt")
	var attempt_id: String = str(f.w.facts.attempts.keys()[0])
	var promised: Dictionary = f.w.facts.attempts[attempt_id].duplicate(true)
	var facility_id: String = str(promised.get("facility_id",""))
	var item: Dictionary = f.w.facts.facilities.get(facility_id,{})
	if item.get("definition_id","")!="M37" or not promised.get("result",false):
		return _result(false,{"prerequisite":"D37常规首试必须在实际M37上成功开工","attempt":promised})
	var clinical_session: Dictionary = {}
	for session: Dictionary in f.w.facts.sessions.values():
		if session.get("attempt_id","")==attempt_id: clinical_session = session.duplicate(true)
	if clinical_session.is_empty(): return _result(false,"原病例没有实际治疗会话")
	var issue: Dictionary = f.w.facts.inventory.issues[attempt_id].duplicate(true)
	item.condition = 83.0
	f.w.facts.research.append("R12")
	var cash: int = HospitalLedger.balance(f.w)
	# Stop at the existing safe-transfer boundary before upgrading this same asset.
	var prepare: CommandResult = _command(f,"remodel_prepare",{"commands":[{"kind":"build_move","target_id":facility_id,"floor_id":int(item.floor_id),"cell":item.cell.duplicate()}],"safe_transfer":true})
	if not prepare.accepted: return _result(false,prepare.reason)
	var arrangement_id: String = str(prepare.changed_ids[0])
	var released: bool = false
	for tick: int in 400:
		_clinic_tick(f,true)
		if f.s.services.remodel._waiting(f.w,f.w.facts.remodels[arrangement_id]).is_empty():
			released = true
			break
	var suspended: Dictionary = f.w.facts.clinical_suspensions.get(str(clinical_session.id),{})
	var retained_work: bool = released and suspended.get("attempt_id","")==attempt_id and suspended.get("remaining_ticks",-1)==clinical_session.remaining_ticks and not f.w.facts.adaptations.has(facility_id) and not f.w.facts.sessions.has(clinical_session.id)
	if not retained_work: return _result(false,{"prerequisite":"原治疗未安全停靠并释放实际设备占用","released":released,"session":clinical_session,"suspended":suspended})
	var arrangement_quote: Dictionary = f.s.services.remodel.preview(f.w,arrangement_id)
	var release: CommandResult = _command(f,"remodel_apply",{"order_id":arrangement_id,"quote":{"price":arrangement_quote.get("price",-1),"refund":arrangement_quote.get("refund",-1),"layout":arrangement_quote.get("layout",[])}})
	if not release.accepted: return _result(false,release.reason)
	item = f.w.facts.facilities[facility_id]
	var applied: CommandResult = _command(f,"upgrade_order",{"facility_id":facility_id,"target_level":1})
	if not applied.accepted: return _result(false,applied.reason)
	var id: String = applied.changed_ids[0]
	var order: Dictionary = f.w.facts.maintenance.upgrades[id]
	var level_before: bool = item.grade==0
	var held_ticks: int = 0
	var holds_original_work: bool = true
	var continuation: Dictionary = {}
	for tick: int in 1800:
		if order.phase!="completed":
			var waiting: Dictionary = f.w.facts.clinical_suspensions.get(str(clinical_session.id),{})
			held_ticks += 1
			holds_original_work = holds_original_work and waiting.get("attempt_id","")==attempt_id and waiting.get("remaining_ticks",-1)==clinical_session.remaining_ticks and not f.w.facts.sessions.has(clinical_session.id)
		_clinic_tick(f,true)
		if order.phase=="completed" and continuation.is_empty():
			var doctors: Array = []
			for staff_id: String in f.w.ids("staff"):
				var staff: Dictionary = f.w.facts.staff[staff_id]
				if staff.role!="doctor": continue
				doctors.append({"staff_id":staff_id,"busy":f.s.clinic._staff_busy(f.w,staff_id),"can_start":f.s.clinic._can_start(f.w,staff),"schedule_allows":f.s.clinic._schedule_allows(f.w,staff_id,"outpatient",f.w.facts.visits[visit_id],facility_id),"quote":f.s.space.facility_quote(f.w,facility_id,f.w.facts.visits[visit_id].actor_id,[staff_id])})
			continuation = {"tick":f.w.sim_tick,"doctors":doctors,"suspensions":f.w.facts.clinical_suspensions.duplicate(true),"preparations":f.w.facts.preparations.duplicate(true),"adaptations":f.w.facts.adaptations.duplicate(true),"candidates":f.s.clinic.service_candidates(f.w,f.w.facts.visits[visit_id],"outpatient",true)}
		if order.phase!="completed": level_before = level_before and item.grade==0
		if order.phase=="completed" and f.w.facts.visits[visit_id].phase=="departed": break
	var upgraded: Dictionary = item.duplicate(true)
	var receipt: Dictionary = f.w.facts.maintenance.receipts.get(id+":1:upgrade_completed",{})
	# M37 costs 1400; its first upgrade is ceil(1400*30%)=420 and takes 30 standard seconds.
	var upgraded_safely: bool = retained_work and level_before and held_ticks>0 and holds_original_work and order.phase=="completed" and order.facility_id==facility_id and upgraded.grade==1 and upgraded.get("upgrade_level",0)==1 and upgraded.condition==83.0 and upgraded.get("completed_upgrade_paid_cost",0)==420 and not upgraded.upgrading_block and receipt.get("standard_work_milli")==30000 and receipt.get("facility_id","")==facility_id and f.w.facts.visits[visit_id].phase=="departed" and f.w.facts.visits[visit_id].final_result=="cured" and f.w.facts.visits[visit_id].attempt_ids==[attempt_id] and f.w.facts.inventory.issues[attempt_id]==issue and HospitalLedger.balance(f.w)==cash-420+10+200
	if not upgraded_safely:
		return _result(false,{"facility_id":facility_id,"held_ticks":held_ticks,"holds_original_work":holds_original_work,"item":upgraded,"order":order,"receipt":receipt,"visit":f.w.facts.visits[visit_id],"suspensions":f.w.facts.clinical_suspensions,"preparations":f.w.facts.preparations,"adaptations":f.w.facts.adaptations,"remodels":f.w.facts.remodels,"continuation":continuation})
	f.s.services.recruitment.settle(f.w)
	var worker_id: String = str(receipt.get("worker_id",""))
	var external_only: bool = not worker_id.is_empty() and not f.w.facts.staff.has(worker_id) and receipt.get("staff_id","").is_empty()
	for tick: int in 800:
		if f.w.facts.maintenance.contractors[worker_id].phase=="departed": break
		_clinic_tick(f,true)
	f.s.services.recruitment.settle(f.w)
	external_only = external_only and f.w.facts.maintenance.contractors[worker_id].phase=="departed" and f.w.facts.actors[worker_id].location.kind=="outside"
	var next_visit: String = _diagnosed_outpatient(f,"ops26_after_upgrade",[48,92])
	if next_visit.is_empty(): return _result(false,f.errors)
	var next_selected: bool = f.w.facts.visits[next_visit].plan_decision.get("plan_id","")=="P_D37_COMMON"
	if not next_selected: return _result(false,{"unexpected_plan":f.w.facts.visits[next_visit].plan_decision})
	for tick: int in 500:
		if not f.w.facts.visits[next_visit].attempt_ids.is_empty(): break
		_clinic_tick(f)
	var next_ids: Array = f.w.facts.visits[next_visit].attempt_ids
	var next_attempt: Dictionary = f.w.facts.attempts.get(str(next_ids[0]),{}) if next_ids.size()==1 else {}
	var next_staff: Array = next_attempt.get("staff_ids",[])
	var level: int = int(f.w.facts.staff[str(next_staff[0])].abilities.treatment) if next_staff.size()==1 else 0
	var utilization: Dictionary = {1:0.60,2:0.70,3:0.80,4:0.90,5:1.00}
	var next_uses_grade: bool = next_selected and utilization.has(level) and next_attempt.get("facility_id","")==facility_id and is_equal_approx(float(next_attempt.get("effective_level",-1.0)),float(utilization.get(level,0.0))) and float(promised.get("effective_level",-1.0))==0.0
	var unchanged: bool = true
	for key: String in promised:
		unchanged = unchanged and f.w.facts.attempts[attempt_id].get(key)==promised[key]
	return _result(upgraded_safely and external_only and next_uses_grade and unchanged and f.w.facts.inventory.issues[attempt_id]==issue and f.w.facts.inventory.issues.size()==2,{"facility_id":facility_id,"item_at_upgrade_completion":upgraded,"order":order,"receipt":receipt,"safe_release":retained_work,"holds_original_work":holds_original_work,"held_ticks":held_ticks,"external_worker_departed":external_only,"original_attempt":promised,"original_terms_unchanged":unchanged,"next_attempt":next_attempt,"expected_effective_level":utilization.get(level)})

func _case_27() -> Dictionary:
	var f: Dictionary = _machine("已施工升级库存接续")
	if not f.errors.is_empty(): return _result(false,f.errors)
	f.w.facts.research.append("R12")
	var applied: CommandResult = _command(f,"upgrade_order",{"facility_id":"ops_machine","target_level":1})
	if not applied.accepted: return _result(false,applied.reason)
	var id: String = applied.changed_ids[0]
	for tick: int in 300:
		_work_tick(f,"maintenance")
		if f.w.facts.maintenance.upgrades[id].stages[0].completed_milli>=12000: break
	_command(f,"upgrade_pause",{"order_id":id})
	var remaining: int = int(f.w.facts.maintenance.upgrades[id].remaining_milli)
	var cash: int = HospitalLedger.balance(f.w)
	var cancel: CommandResult = _command(f,"upgrade_cancel",{"order_id":id})
	var stored: CommandResult = _command(f,"build_store",{"target_id":"ops_machine"})
	if not stored.accepted: return _result(false,{"reason":stored.reason,"remaining":remaining})
	var restored: Dictionary = _restore(f)
	var retained: bool = remaining==18000 and not cancel.accepted and restored.w.facts.maintenance.upgrades[id].remaining_milli==remaining and restored.w.facts.inventory.build_items.ops_machine.grade==0 and restored.w.facts.maintenance.upgrades[id].phase=="inventory"
	_place(restored,"ops_machine","M09",[42,80],"","ops_machine")
	_command(restored,"upgrade_resume",{"order_id":id})
	for tick: int in 500:
		_work_tick(restored,"maintenance")
		if restored.w.facts.maintenance.upgrades[id].phase=="completed": break
	return _result(retained and restored.errors.is_empty() and restored.w.facts.facilities.ops_machine.grade==1 and restored.w.facts.maintenance.upgrades[id].remaining_milli==0 and restored.w.facts.maintenance.upgrades[id].refunded==0 and HospitalLedger.balance(restored.w)==cash and restored.w.facts.maintenance.receipts.size()==1,{"retained_milli":remaining,"order":restored.w.facts.maintenance.upgrades[id],"errors":restored.errors})

func _case_28() -> Dictionary:
	var f: Dictionary = _new("科室归属与专注过渡",true)
	var cash: int = HospitalLedger.balance(f.w)
	var first: CommandResult = _command(f,"department_create",{"department_id":"ops28_unit","name":"日常专科","room_ids":["room_daily"],"entry":{"floor_id":1,"cell":[52,91]},"focus_id":"T10"})
	if not first.accepted: return _result(false,first.reason)
	var free: bool = HospitalLedger.balance(f.w)==cash and not "room_daily" in f.w.facts.departments.units.general.room_ids
	var change: CommandResult = _command(f,"department_set_focus",{"department_id":"ops28_unit","focus_id":"T01"})
	var deadline: int = int(f.w.facts.departments.units.ops28_unit.focus_ready_tick)
	var paid: bool = change.accepted and HospitalLedger.balance(f.w)==cash-200 and deadline==f.w.sim_tick+6000
	var reset: CommandResult = _command(f,"department_create",{"department_id":"ops28_bypass","name":"不能刷新冷却","room_ids":["room_daily"],"entry":{"floor_id":1,"cell":[52,91]},"focus_id":"T10"})
	var inherited: CommandResult = _command(f,"department_create",{"department_id":"ops28_inherit","name":"承接原调整","room_ids":["room_daily"],"entry":{"floor_id":1,"cell":[52,91]},"focus_id":"T01"})
	var restored: Dictionary = _restore(f)
	var before: Dictionary = restored.s.services.departments.summary(restored.w,"ops28_inherit")
	restored.w.facts.sim_tick = deadline-1
	_zero_arrivals(restored.w)
	var almost: Dictionary = restored.s.services.departments.summary(restored.w,"ops28_inherit")
	restored.w.facts.sim_tick = deadline
	_zero_arrivals(restored.w)
	var complete: Dictionary = restored.s.services.departments.summary(restored.w,"ops28_inherit")
	return _result(free and paid and not reset.accepted and inherited.accepted and restored.w.facts.departments.units.ops28_inherit.focus_ready_tick==deadline and before.units[0].focus_remaining_ticks==6000 and almost.units[0].focus_remaining_ticks==1 and complete.units[0].focus_remaining_ticks==0 and HospitalLedger.balance(restored.w)==cash-200,{"deadline":deadline,"before":before,"almost":almost,"complete":complete,"bypass_reason":reset.reason})

func _visit_stage(f: Dictionary, key: String, target: String) -> String:
	var arrived: CommandResult = _command(f,"clinical_arrive",{"arrival_key":key,"binding_id":"B_S49_D37_M37","personality_id":"PP01"})
	if not arrived.accepted:
		f.errors.append(arrived.reason)
		return ""
	var visit_id: String = arrived.changed_ids[0]
	for tick: int in 1600:
		if f.w.facts.visits[visit_id].phase==target: return visit_id
		if f.w.facts.visits[visit_id].phase in ["leaving","departed"]: break
		_clinic_tick(f)
	f.errors.append({"target_not_reached":target,"visit":f.w.facts.visits[visit_id]})
	return ""

func _case_40() -> Dictionary:
	var f: Dictionary = _new("已发布评价窗口回收",true)
	var departments: HospitalDepartments = f.s.services.departments
	var limit: int = int(_content.balance.ratings.case_window_limit)
	var admitted: CommandResult = _command(f,"clinical_arrive",{"arrival_key":"rating_template","binding_id":"B_S49_D37_M37","personality_id":"PP01"})
	if not admitted.accepted: return _result(false,admitted.reason)
	var prototype: Dictionary = f.w.facts.visits[admitted.changed_ids[0]]
	# Archived rating facts are calculation inputs, not newly executed Visits.
	for index: int in limit:
		_rating_input(f,prototype,"past_"+str(index),1000+index,75.0)
	f.w.facts.sim_tick = 18000
	var published: Dictionary = departments.aggregate_rating(f.w,"general")
	for index: int in limit+3:
		_rating_input(f,prototype,"today_"+str(index),18000+index,25.0)
		departments._prune(f.w)
	_zero_arrivals(f.w)
	var validation: String = f.w.validate(_content)
	var current: Dictionary = departments.aggregate_rating(f.w,"general")
	var hospital: Dictionary = departments.aggregate_rating(f.w)
	var restored: WorldState = WorldState.new(f.w.freeze())
	var restored_current: Dictionary = HospitalDepartments.new(_content,f.s.space).aggregate_rating(restored,"general")
	f.w.facts.sim_tick = 36000
	departments._prune(f.w)
	var next: Dictionary = departments.aggregate_rating(f.w,"general")
	return _result(validation.is_empty() and current==published and current==restored_current and int(current.samples)==limit and int(hospital.samples)==limit and int(next.samples)==limit and float(next.parts.patient)==25.0,{"validation":validation,"published":published,"current":current,"next":next,"retained":f.w.facts.departments.cases.size()})

func _rating_input(f: Dictionary, prototype: Dictionary, id: String, tick: int, score: float) -> void:
	f.w.facts.sim_tick = tick
	var actor: Dictionary = f.w.facts.actors[prototype.actor_id].duplicate(true)
	actor.id = id+"_actor"
	actor.location = {"kind":"outside"}
	var visit: Dictionary = prototype.duplicate(true)
	visit.id = id
	visit.actor_id = actor.id
	visit.arrival_key = id
	visit.phase = "departed"
	visit.final_result = "referred"
	visit.ticket_id = ""
	visit.departed_tick = tick
	f.w.facts.actors[actor.id] = actor
	f.w.facts.visits[id] = visit
	f.w.facts.arrival_receipts[id] = id
	f.w.facts.departments.cases.append({"visit_id":id,"tick":tick,"day":tick/WorldState.TICKS_PER_DAY,"department_id":"general","result":"referred","treated":false,"rating":{"score":score,"parts":{"flow":score,"environment":score}}})

func _case_29() -> Dictionary:
	var f: Dictionary = _new("专注门槛边界",true,10000)
	var visit_id: String = _visit_stage(f,"ops29_active","wait_gp")
	if visit_id.is_empty(): return _result(false,f.errors)
	var created: CommandResult = _command(f,"department_create",{"department_id":"ops29_focus","name":"日常专注","room_ids":["room_daily"],"shared_room_ids":["room_gp"],"entry":{"floor_id":1,"cell":[52,91]},"focus_id":"T10"})
	if not created.accepted: return _result(false,created.reason)
	f.w.facts.visits[visit_id].department_id = "ops29_focus"
	# A historical RatingWindow is explicit input to the focus predicate. It is
	# not evidence that five new treatments were performed by this test.
	for index: int in 5:
		var archived_id: String = "ops29_archived_%d"%index
		var actor_id: String = archived_id+"_actor"
		f.w.facts.actors[actor_id] = {"id":actor_id,"name":"历史病例%d"%index,"species_id":"S49","location":{"kind":"outside"},"facing":0.0,"posture":"standing"}
		var archived: Dictionary = f.w.facts.visits[visit_id].duplicate(true)
		archived.id = archived_id
		archived.actor_id = actor_id
		archived.phase = "departed"
		archived.final_result = "referred"
		archived.ticket_id = ""
		archived.arrived_tick = 0
		archived.departed_tick = 1000
		archived.arrival_key = archived_id
		f.w.facts.visits[archived_id] = archived
		f.w.facts.arrival_receipts[archived_id] = archived_id
		f.w.facts.departments.cases.append({"visit_id":archived_id,"tick":1000,"day":0,"department_id":"ops29_focus","result":"referred","treated":false,"rating":{"score":75.0,"parts":{"outcome":65.0,"flow":75.0,"care":90.0,"environment":75.0}}})
	f.w.facts.sim_tick = 18000
	_zero_arrivals(f.w)
	f.w.facts.staff.starter_doctor_b.abilities.treatment = 1
	var low_ability: float = f.s.services.departments.focus_multiplier(f.w,visit_id,"starter_doctor_b","treatment")
	f.w.facts.staff.starter_doctor_b.abilities.treatment = 2
	var eligible: float = f.s.services.departments.focus_multiplier(f.w,visit_id,"starter_doctor_b","treatment")
	var arrivals: HospitalArrivalService = f.s.services.arrivals
	var reference: Dictionary = f.s.clinic._arrival_candidate(arrivals._capacity_reference_world(f.w),"B_S49_D37_M37",false)
	var reference_focus: float = f.s.services.departments.focus_multiplier(reference.world,reference.visit.id,"starter_doctor_b","treatment") if reference.ok else 1.0
	var basis: Dictionary = arrivals._reference_basis(f.w,0)
	f.w.facts.departments.units.ops29_focus.name = "科室新显示名"
	var rename_stable: bool = basis==arrivals._reference_basis(f.w,0)
	var last: Dictionary = f.w.facts.departments.cases.pop_back()
	var four: float = f.s.services.departments.focus_multiplier(f.w,visit_id,"starter_doctor_b","treatment")
	f.w.facts.departments.cases.append(last)
	for record: Dictionary in f.w.facts.departments.cases:
		record.rating.score = 74.0
		record.rating.parts.flow = 74.0
		record.rating.parts.environment = 74.0
	var low_score: float = f.s.services.departments.focus_multiplier(f.w,visit_id,"starter_doctor_b","treatment")
	for record: Dictionary in f.w.facts.departments.cases:
		record.rating.score = 75.0
		record.rating.parts.flow = 75.0
		record.rating.parts.environment = 75.0
	f.w.facts.departments.units.ops29_focus.focus_ready_tick = 18001
	var transition: float = f.s.services.departments.focus_multiplier(f.w,visit_id,"starter_doctor_b","treatment")
	f.w.facts.departments.units.ops29_focus.focus_ready_tick = 18000
	f.w.facts.departments.units.ops29_focus.focus_id = "T01"
	var mismatch: float = f.s.services.departments.focus_multiplier(f.w,visit_id,"starter_doctor_b","treatment")
	return _result(low_ability==1.0 and is_equal_approx(eligible,0.95) and reference.ok and reference.visit.department_id=="ops29_focus" and reference_focus==eligible and rename_stable and four==1.0 and low_score==1.0 and transition==1.0 and mismatch==1.0,{"ability1":low_ability,"eligible":eligible,"reference_focus":reference_focus,"rename_stable":rename_stable,"four_cases":four,"score74":low_score,"transition":transition,"mismatch":mismatch})

func _route_fixture(label: String) -> Dictionary:
	var f: Dictionary = _new(label,true,20000)
	var right: CommandResult = _command(f,"department_create",{"department_id":"ops_right","name":"日常门诊","room_ids":["room_daily"],"shared_room_ids":["room_gp"],"entry":{"floor_id":1,"cell":[52,91]},"focus_id":"T10","intake_disease_ids":["D37"]})
	var wrong: CommandResult = _command(f,"department_create",{"department_id":"ops_wrong","name":"体态门诊","room_ids":["room_physical"],"shared_room_ids":["room_gp"],"entry":{"floor_id":1,"cell":[44,91]},"focus_id":"T01","intake_disease_ids":["D09"]})
	if not right.accepted: f.errors.append(right.reason)
	if not wrong.accepted: f.errors.append(wrong.reason)
	f.visit_id = _visit_stage(f,label,"wait_gp")
	# No eligible guide is the normal self-service/doctor fallback condition.
	for staff: Dictionary in f.w.facts.staff.values():
		if staff.role=="nurse": staff.on_shift = false
	return f

func _registration_seed(world: WorldState, below: bool) -> void:
	for candidate: int in 100:
		var generator: RandomNumberGenerator = RandomNumberGenerator.new()
		generator.seed = candidate+100
		var state: int = generator.state
		var roll: int = generator.randi_range(0,9999)
		if (roll<1800)==below:
			world.facts.rng.registration = {"algorithm":"godot-pcg32-4.7.2","seed_decimal":str(candidate+100),"state_decimal":str(state)}
			return

func _case_30() -> Dictionary:
	var f: Dictionary = _route_fixture("暂时缺包不是挂错")
	var visit_id: String = str(f.visit_id)
	if visit_id.is_empty() or not f.errors.is_empty(): return _result(false,f.errors)
	f.w.facts.inventory.units = 0
	var right: Dictionary = f.s.services.departments.readiness(f.w,"ops_right",visit_id)
	var wrong: Dictionary = f.s.services.departments.readiness(f.w,"ops_wrong",visit_id)
	_registration_seed(f.w,false)
	f.s.services.departments.route_patient(f.w,visit_id)
	var route: Dictionary = f.w.facts.departments.routes[visit_id]
	var temporary: bool = right.structurally_compatible and not right.ok and wrong.reason_id=="intake_scope_excludes_case" and route.registration_choice=="ops_right" and not route.error_rolled
	var g: Dictionary = _route_fixture("错误目的地后来等价")
	var other_id: String = str(g.visit_id)
	if other_id.is_empty() or not g.errors.is_empty(): return _result(false,g.errors)
	_registration_seed(g.w,true)
	g.s.services.departments.route_patient(g.w,other_id)
	var was_wrong: bool = g.w.facts.departments.routes[other_id].registration_choice=="ops_wrong"
	var jobs: int = g.w.facts.departments.staff_consumed.size()
	var anger: float = float(g.w.facts.visits[other_id].anger)
	var changed: CommandResult = _command(g,"department_configure",{"department_id":"ops_wrong","intake_disease_ids":[]})
	_place(g,"ops_equivalent_machine","M37",[42,85],"room_physical")
	var accepted: bool = g.s.services.departments.route_patient(g.w,other_id)
	var corrected: Dictionary = g.w.facts.departments.routes[other_id]
	return _result(temporary and was_wrong and changed.accepted and g.errors.is_empty() and accepted and corrected.corrected and corrected.correction_source=="capacity_recheck" and g.w.facts.visits[other_id].department_id=="ops_wrong" and corrected.actual_mismatched_entry_arrival.is_empty() and g.w.facts.departments.guidance.is_empty() and g.w.facts.departments.staff_consumed.size()==jobs and g.w.facts.visits[other_id].anger==anger,{"temporary_right":right,"wrong":wrong,"equivalent":corrected,"errors":g.errors})

func _guide_tick(f: Dictionary) -> void:
	f.s.services.departments.dispatch(f.w)
	f.s.space.advance(f.w,f.w.present_actor_count())
	f.s.services.departments.advance(f.w)
	f.w.facts.sim_tick += 1
	_zero_arrivals(f.w)
	f.w.touch()
	f.s.space.finish_boundary(f.w)

func _case_31() -> Dictionary:
	var f: Dictionary = _route_fixture("真实错入口唯一事实")
	var visit_id: String = str(f.visit_id)
	if visit_id.is_empty() or not f.errors.is_empty(): return _result(false,f.errors)
	# The other cell outside the same two-cell clinic door is a lawful entry;
	# [44,91] is the receptionist's actual safety-release destination.
	var entry: Array = [45,91]
	var configured: CommandResult = _command(f,"department_configure",{"department_id":"ops_wrong","entry":{"floor_id":1,"cell":entry}})
	if not configured.accepted: return _result(false,{"entry_configuration":configured.reason})
	_registration_seed(f.w,true)
	var visit: Dictionary = f.w.facts.visits[visit_id]
	var ticket_id: String = str(visit.ticket_id)
	var evidence: Dictionary = visit.evidence_by_source.duplicate(true)
	var anger: float = float(visit.anger)
	var flow: float = float(f.s.services.departments.patient_rating(f.w,visit_id).parts.flow)
	var cash: int = HospitalLedger.balance(f.w)
	f.s.services.departments.route_patient(f.w,visit_id)
	var before_arrival: bool = f.w.facts.departments.routes[visit_id].actual_mismatched_entry_arrival.is_empty() and visit.anger==anger and is_equal_approx(float(f.s.services.departments.patient_rating(f.w,visit_id).parts.flow),flow)
	for tick: int in 350:
		f.s.space.advance(f.w,f.w.present_actor_count())
		f.w.facts.sim_tick += 1
		_zero_arrivals(f.w)
		f.w.touch()
		f.s.space.finish_boundary(f.w)
		# No resource or destination changes occur during this physical walk.
		# Recheck the business boundary when its current movement has finished.
		if not f.w.facts.moves.has(visit.actor_id): f.s.services.departments.route_patient(f.w,visit_id)
		if not f.w.facts.departments.routes[visit_id].actual_mismatched_entry_arrival.is_empty(): break
	var route: Dictionary = f.w.facts.departments.routes[visit_id]
	var actual_position: Dictionary = f.w.facts.actors[visit.actor_id].location.duplicate(true)
	var actual: bool = f.s.space.at(f.w,visit.actor_id,1,entry) and not route.actual_mismatched_entry_arrival.is_empty() and float(f.w.facts.visits[visit_id].anger)==anger+12.0 and is_equal_approx(float(f.s.services.departments.patient_rating(f.w,visit_id).parts.flow),flow-8.0)
	var restored: Dictionary = _restore(f)
	for repeat: int in 3: restored.s.services.departments.route_patient(restored.w,visit_id)
	var unique: bool = restored.w.facts.departments.experience[visit_id].wrong_entries.size()==1 and restored.w.facts.visits[visit_id].anger==anger+12.0
	var self_service_tick: int = int(route.arrived_tick)+roundi(float(_content.balance.guidance.self_service_after_seconds)*10)
	var held_before_deadline: bool = false
	for tick: int in 400:
		_guide_tick(restored)
		if restored.w.sim_tick>=self_service_tick-1:
			restored.s.services.departments.route_patient(restored.w,visit_id)
			if restored.w.sim_tick==self_service_tick-1: held_before_deadline = not restored.w.facts.departments.routes[visit_id].corrected
		if restored.w.facts.departments.routes[visit_id].corrected: break
	var after: Dictionary = restored.w.facts.visits[visit_id]
	return _result(before_arrival and actual and unique and held_before_deadline and restored.w.sim_tick==self_service_tick and restored.w.facts.departments.routes[visit_id].corrected and after.ticket_id==ticket_id and after.evidence_by_source==evidence and HospitalLedger.balance(restored.w)==cash and restored.w.facts.departments.experience[visit_id].wrong_entries.size()==1,{"route":restored.w.facts.departments.routes[visit_id],"entry":entry,"actual_position":actual_position,"before_arrival_unchanged":before_arrival,"held_before_deadline":held_before_deadline,"self_service_tick":self_service_tick,"anger_before":anger,"anger_after_entry":f.w.facts.visits[visit_id].anger,"flow_after_entry":f.s.services.departments.patient_rating(f.w,visit_id).parts.flow,"ticket":after.ticket_id})

func _case_32() -> Dictionary:
	var f: Dictionary = _new("真实完成评分与无数据状态")
	var initial: Dictionary = f.s.services.departments.aggregate_rating(f.w)
	_staff(f,"ops_rating_cleaner","cleaner",[40,80])
	var no_jobs: Dictionary = f.s.services.departments.staff_rating(f.w,"ops_rating_cleaner")
	for index: int in 5:
		var id: String = f.s.services.environment.spawn_dirt(f.w,"CL01","ops32_source_%d"%index,"ops32_fact_%d"%index,1,[42,80])
		if id.is_empty(): return _result(false,"评分前提污物未生成")
		for tick: int in 200:
			_work_tick(f,"environment")
			if not f.w.facts.environment.dirt.has(id): break
		f.s.services.departments.settle(f.w)
		f.s.services.departments.settle(f.w)
	var staff_rating: Dictionary = f.s.services.departments.staff_rating(f.w,"ops_rating_cleaner")
	var g: Dictionary = _new("未治疗离院小票",true)
	var visit_id: String = _visit_stage(g,"ops32_untreated","wait_gp")
	if visit_id.is_empty(): return _result(false,g.errors)
	_command(g,"clinical_refer",{"visit_id":visit_id})
	for tick: int in 400:
		_clinic_tick(g)
		if g.w.facts.visits[visit_id].phase=="departed": break
	g.s.services.departments.settle(g.w)
	g.s.services.departments.settle(g.w)
	var before: Dictionary = g.w.freeze()
	var receipt: Dictionary = g.s.services.departments.receipt(g.w,visit_id)
	g.s.services.departments.patient_summary(g.w,visit_id)
	g.s.services.departments.reason_cards(g.w,visit_id)
	g.s.services.departments.summary(g.w)
	var readonly: bool = g.w.freeze()==before
	return _result(initial.score==null and initial.stars==null and initial.samples==0 and no_jobs.score==null and no_jobs.stars==null and staff_rating.samples==5 and staff_rating.stars!=null and is_equal_approx(float(staff_rating.parts.quality),100.0) and g.w.facts.departments.cases.size()==1 and g.w.facts.departments.cases[0].department_id=="" and receipt.get("department_name")=="未进入治疗科室" and readonly,{"initial":initial,"staff":staff_rating,"cases":g.w.facts.departments.cases,"receipt":receipt,"readonly":readonly})

func _case_33() -> Dictionary:
	var f: Dictionary = _new("运营精确持余",true,100000)
	var finance: FinanceService = f.s.services.finance
	var rate: int = finance.operating_rate(f.w)
	for tick: int in 3:
		finance.settle(f.w)
		f.w.facts.sim_tick += 1
		_zero_arrivals(f.w)
	var actual_accrual: bool = f.w.facts.economy.daily_accumulators.operating_numerator==4683
	var costs: Array = []
	var total: int = 0
	for day: int in range(1,21):
		# Checkpoints contain the exact historical integral. No twenty-day replay
		# or guessed rounded daily amount is used to prove the carry contract.
		var ticks: int = 17997 if day==1 else 18000
		f.w.facts.economy.daily_accumulators.operating_numerator += rate*ticks
		f.w.facts.sim_tick = day*18000-1
		_zero_arrivals(f.w)
		f.w.facts.economy.operating_accrued_tick = f.w.sim_tick
		for staff: Dictionary in f.w.facts.staff.values():
			staff.wage_numerator += finance.wage(staff)*ticks
			staff.wage_accrued_tick = f.w.sim_tick
		finance.settle(f.w)
		var entry: Dictionary = f.w.facts.ledger.entries.get(f.w.hospital_id+":operations_day_%d"%day,{})
		var cost: int = int(entry.get("cost",-1))
		costs.append(cost)
		total += cost
	var restored: Dictionary = _restore(f)
	var before: Dictionary = restored.w.freeze()
	restored.s.services.finance.settle(restored.w)
	var duplicate: bool = restored.w.freeze()==before
	var g: Dictionary = _new("逐员工工资舍入")
	_staff(g,"ops33_doctor_a","doctor",[40,80])
	_staff(g,"ops33_doctor_b","doctor",[42,80])
	g.w.facts.sim_tick = 17999
	_zero_arrivals(g.w)
	g.w.facts.economy.operating_accrued_tick = 17999
	for staff: Dictionary in g.w.facts.staff.values():
		staff.wage_numerator = 17900
		staff.wage_accrued_tick = 17999
	g.s.services.finance.settle(g.w)
	var wage_a: Dictionary = g.w.facts.ledger.entries.get("ops33_doctor_a:wages_day_1",{})
	var wage_b: Dictionary = g.w.facts.ledger.entries.get("ops33_doctor_b:wages_day_1",{})
	var expected: bool = costs.size()==20
	for index: int in costs.size(): expected = expected and costs[index]==(79 if index==19 else 78)
	return _result(rate==1561 and actual_accrual and expected and total==1561 and f.w.facts.economy.daily_accumulators.operating_numerator==0 and duplicate and wage_a.get("cost")==0 and wage_b.get("cost")==0 and g.w.facts.staff.ops33_doctor_a.wage_numerator==17900 and g.w.facts.staff.ops33_doctor_b.wage_numerator==17900,{"per_tick_numerator":rate,"daily_costs":costs,"total":total,"wages":[wage_a,wage_b],"duplicate_unchanged":duplicate})

func _case_34() -> Dictionary:
	var f: Dictionary = _new("补助医院日周期",false,10000)
	var payments: Array = []
	for day: int in [1,2,3,6]:
		f.w.facts.sim_tick = day*18000-1
		_zero_arrivals(f.w)
		f.w.facts.economy.operating_accrued_tick = f.w.sim_tick
		if day==6:
			f.w.facts.floors.overrides["1"].plots.append([0,2])
		f.s.services.finance.settle(f.w)
		payments.append({"day":day,"count":_subsidies(f.w),"cash":HospitalLedger.balance(f.w)})
	var first: Dictionary = f.w.facts.ledger.entries.get(f.w.hospital_id+":subsidy_1",{})
	var second: Dictionary = f.w.facts.ledger.entries.get(f.w.hospital_id+":subsidy_2",{})
	var restored: Dictionary = _restore(f)
	var before: Dictionary = restored.w.freeze()
	restored.s.services.finance.settle(restored.w)
	return _result(payments[0].count==0 and payments[1].count==0 and payments[2].count==1 and payments[3].count==2 and first.get("amount")==1200 and second.get("amount")==1400 and restored.w.facts.economy.subsidy_next_day==9 and before==restored.w.freeze(),{"payments":payments,"first":first,"second":second,"next_day":restored.w.facts.economy.subsidy_next_day})

func _subsidies(world: WorldState) -> int:
	var count: int = 0
	for entry: Dictionary in world.facts.ledger.entries.values():
		if str(entry.component).begins_with("subsidy_"): count += 1
	return count

func _case_35() -> Dictionary:
	var f: Dictionary = _new("必要支出成本与非现金援助",true,100)
	# A day-2 checkpoint excludes the new-hospital purchase ledger from today's
	# result and carries 650 wages plus 200 actually accrued operations.
	f.w.facts.sim_tick = 35999
	_zero_arrivals(f.w)
	f.w.facts.economy.last_settled_day = 1
	f.w.facts.economy.operating_accrued_tick = 35999
	f.w.facts.economy.daily_accumulators.operating_numerator = 200*360000
	for staff: Dictionary in f.w.facts.staff.values():
		staff.wage_numerator = f.s.services.finance.wage(staff)*18000
		staff.wage_accrued_tick = 35999
	f.s.services.finance.settle(f.w)
	var query: Dictionary = f.s.services.finance.query(f.w,2)
	var totals: Dictionary = query.today
	var cost: int = 0
	var paid: int = 0
	var aid: int = 0
	for entry: Dictionary in f.w.facts.ledger.entries.values():
		if int(entry.tick)!=35999: continue
		cost += int(entry.get("cost",0))
		paid += int(entry.get("hospital_paid",0))
		aid += int(entry.get("direct_paid",0))
	var before: Dictionary = f.w.freeze()
	var denied: CommandResult = _command(f,"build_facility",{"id":"ops35_unfunded","definition_id":"M09","floor_id":1,"cell":[34,66]})
	return _result(HospitalLedger.balance(f.w)==0 and cost==850 and paid==100 and aid==750 and cost==paid+aid and totals.operating_surplus==-850 and totals.cash_change==-100 and totals.direct_support==750 and not denied.accepted and f.w.freeze()==before,{"cost":cost,"hospital_paid":paid,"direct_paid":aid,"today":totals,"construction_rejection":denied.reason})

func _case_36() -> Dictionary:
	var f: Dictionary = _new("财务投影与目标便签",true,5000)
	var before: Dictionary = f.w.freeze()
	var first: Dictionary = f.s.services.finance.query(f.w)
	var groups: Array = []
	for view: Dictionary in first.views: groups.append(str(view.group))
	var readonly: bool = before==f.w.freeze()
	var forecast: Array = first.forecast
	var estimated: bool = forecast.size()==3 and forecast[0].day==1 and forecast[1].day==2 and forecast[2].day==3 and forecast[0].wages==650 and forecast[0].operations==78 and forecast[0].closing_cash==4272 and forecast[0].forecast and forecast[2].subsidy==1200
	var note: CommandResult = _command(f,"finance_note",{"text":"扩建诊室","target_amount":6000})
	var noted: Dictionary = f.s.services.finance.query(f.w)
	var goal: bool = note.accepted and noted.get("saving_note")=="扩建诊室" and noted.get("target_amount")==6000 and noted.get("remaining_to_target")==1000 and HospitalLedger.balance(f.w)==5000
	var payment_panel: HospitalActionPanel = HospitalActionPanel.new()
	payment_panel.simulation = f.s
	var payment_before: Dictionary = f.w.freeze()
	var below: String = payment_panel.payment_summary(400,100)
	var at_target: String = payment_panel.payment_summary(0,1000)
	var payment_readonly: bool = payment_before==f.w.freeze()
	var payment_values: bool = below=="购买后现金 4700 · 低于便签目标 6000" and at_target=="购买后现金 6000 · 不低于便签目标 6000" and HospitalActionPanel.format_payment_summary(f.w,400,100)==below
	var funded: Dictionary = _new("预览只扣医院实付",false,25)
	funded.w.facts.mode = "creative"
	funded.w.facts.inventory.units = 5
	var funding_before: Dictionary = funded.w.freeze()
	var funding_quote: Dictionary = funded.s.services.supplies.purchase_quote(funded.w,7)
	var funding_panel: HospitalActionPanel = HospitalActionPanel.new()
	funding_panel.simulation = funded.s
	var funded_summary: String = funding_panel.payment_summary(int(funding_quote.hospital_paid))
	var funding_correct: bool = funding_quote.cost==140 and funding_quote.hospital_paid==25 and funding_quote.direct_paid==115 and funded_summary=="购买后现金 0" and funding_before==funded.w.freeze()
	funding_panel.free()
	var buy: CommandResult = _command(f,"purchase_supplies",{"units":1,"unit_price":20})
	var after_buy: Dictionary = f.s.services.finance.query(f.w)
	var invalid_before: Dictionary = f.w.freeze()
	var invalid: CommandResult = _command(f,"finance_note",{"text":"错误目标","target_amount":0})
	var invalid_unchanged: bool = not invalid.accepted and invalid_before==f.w.freeze()
	var long_note: CommandResult = _command(f,"finance_note",{"text":"长".repeat(41),"target_amount":6000})
	invalid_unchanged = invalid_unchanged and not long_note.accepted and invalid_before==f.w.freeze()
	var negative: CommandResult = _command(f,"finance_note",{"text":"错误目标","target_amount":-1})
	invalid_unchanged = invalid_unchanged and not negative.accepted and invalid_before==f.w.freeze()
	var clear: CommandResult = _command(f,"finance_note",{"text":"","target_amount":0})
	var cleared: Dictionary = f.s.services.finance.query(f.w)
	var cleared_before: Dictionary = f.w.freeze()
	var no_goal: String = payment_panel.payment_summary(400,100)
	var cleared_readonly: bool = cleared_before==f.w.freeze() and no_goal=="购买后现金 4680" and not "目标" in no_goal
	payment_panel.free()
	return _result(readonly and groups==["clinical","operation","development","grant","refund","direct_support"] and estimated and goal and payment_readonly and payment_values and funding_correct and buy.accepted and after_buy.get("remaining_to_target")==1020 and invalid_unchanged and clear.accepted and cleared.get("saving_note")=="" and cleared.get("target_amount")==0 and cleared_readonly and HospitalLedger.balance(f.w)==4980,{"groups":groups,"forecast":forecast,"note":noted,"payment_summary":below,"at_target":at_target,"funded_summary":funded_summary,"after_purchase_target_gap":after_buy.get("remaining_to_target"),"invalid_reason":invalid.reason,"cleared_target":cleared.get("target_amount"),"cleared_summary":no_goal})

func _case_37() -> Dictionary:
	var f: Dictionary = _new("基础救援箱按实际缺岗",false,2500)
	_staff(f,"ops37_existing_reception","receptionist",[40,80])
	_staff(f,"ops37_existing_doctor","doctor",[42,80])
	var claimed: CommandResult = _command(f,"finance_rescue",{})
	if not claimed.accepted: return _result(false,claimed.reason)
	var counts: Dictionary = {"doctor":0,"receptionist":0}
	var paid_staff: bool = true
	for staff: Dictionary in f.w.facts.staff.values():
		if counts.has(staff.role): counts[staff.role] += 1
		paid_staff = paid_staff and f.s.services.finance.wage(staff)>0
	var borrowed: Array = []
	var zero_cost: bool = true
	for item: Dictionary in f.w.facts.inventory.build_items.values():
		if item.get("ownership","")=="borrowed":
			borrowed.append(str(item.definition_id))
			zero_cost = zero_cost and item.paid_cost==0
	borrowed.sort()
	var restored: Dictionary = _restore(f)
	var before: Dictionary = restored.w.freeze()
	var again: CommandResult = _command(restored,"finance_rescue",{})
	return _result(counts=={"doctor":2,"receptionist":1} and f.w.facts.staff.size()==3 and paid_staff and zero_cost and borrowed==["FUR01","FUR02","M37"] and f.w.facts.economy.get("rescue_blueprint_id")=="BP03" and f.w.facts.facilities.is_empty() and HospitalLedger.balance(f.w)==2500 and not again.accepted and before==restored.w.freeze(),{"counts":counts,"borrowed":borrowed,"staff_count":f.w.facts.staff.size(),"cash":HospitalLedger.balance(f.w),"repeat":again.reason})

func _case_38() -> Dictionary:
	var f: Dictionary = _machine("无患者仍按设备停机用途派工")
	_place(f,"ops_older_tool","SE02",[37,80])
	if not f.errors.is_empty(): return _result(false,f.errors)
	f.w.facts.facilities.ops_older_tool.failed = true
	f.s.services.maintenance.boundaries(f.w)
	var tool_job: String = str(f.w.facts.facilities.ops_older_tool.maintenance_order_id)
	var pin_tool: CommandResult = _command(f,"maintenance_pin",{"job_id":tool_job})
	f.w.facts.facilities.ops_machine.failed = true
	f.s.services.maintenance.boundaries(f.w)
	var medical_job: String = str(f.w.facts.facilities.ops_machine.maintenance_order_id)
	var before: Dictionary = f.w.freeze()
	var use: Dictionary = HospitalEquipmentUse.query(f.w,"ops_machine")
	var readonly: bool = before==f.w.freeze() and use.placed and not use.occupied and not use.critical_commitment
	f.s.services.maintenance.dispatch(f.w)
	var category_first: bool = pin_tool.accepted and f.w.facts.visits.is_empty() and f.w.facts.maintenance.contractors.size()==1 and not str(f.w.facts.maintenance.jobs[medical_job].worker_id).is_empty() and str(f.w.facts.maintenance.jobs[tool_job].worker_id).is_empty()
	var g: Dictionary = _machine("同级置顶与已开工保护")
	_place(g,"ops_second","M09",[50,80])
	if not g.errors.is_empty(): return _result(false,g.errors)
	g.w.facts.facilities.ops_machine.failed = true
	g.s.services.maintenance.boundaries(g.w)
	var older: String = str(g.w.facts.facilities.ops_machine.maintenance_order_id)
	g.w.facts.sim_tick += 1
	g.w.facts.facilities.ops_second.failed = true
	g.s.services.maintenance.boundaries(g.w)
	var later: String = str(g.w.facts.facilities.ops_second.maintenance_order_id)
	var pin_later: CommandResult = _command(g,"maintenance_pin",{"job_id":later})
	g.s.services.maintenance.dispatch(g.w)
	var pinned_first: bool = pin_later.accepted and not str(g.w.facts.maintenance.jobs[later].worker_id).is_empty() and str(g.w.facts.maintenance.jobs[older].worker_id).is_empty()
	for tick: int in 400:
		_work_tick(g,"maintenance")
		if g.w.facts.maintenance.jobs[later].started: break
	var active: Dictionary = g.w.facts.maintenance.jobs[later]
	var worker_id: String = str(active.worker_id)
	var remaining: int = int(active.remaining_milli)
	var change_pin: CommandResult = _command(g,"maintenance_pin",{"job_id":older})
	g.s.services.maintenance.dispatch(g.w)
	var uninterrupted: bool = change_pin.accepted and active.started and active.phase=="working" and active.worker_id==worker_id and active.remaining_milli==remaining
	return _result(readonly and category_first and pinned_first and uninterrupted,{"query":use,"readonly":readonly,"no_patient_category_order":category_first,"same_grade_pin":pinned_first,"started_job_retained":uninterrupted,"first_jobs":f.w.facts.maintenance.jobs,"second_jobs":g.w.facts.maintenance.jobs})

func _case_39() -> Dictionary:
	var f: Dictionary = _new("治疗预约安全释放后才维修",true)
	var visit_id: String = _diagnosed_outpatient(f,"ops39_preparation",[48,92])
	if visit_id.is_empty(): return _result(false,f.errors)
	f.s.clinic.dispatch(f.w)
	var preparation: Dictionary = f.w.facts.preparations.get(visit_id,{})
	if preparation.is_empty(): return _result(false,{"prerequisite":"实际治疗预约未建立","visit":f.w.facts.visits[visit_id]})
	var facility_id: String = str(preparation.facility_id)
	var use: Dictionary = HospitalEquipmentUse.query(f.w,facility_id)
	f.w.facts.facilities[facility_id].pending_failure = true
	f.s.services.maintenance.boundaries(f.w)
	var job_id: String = str(f.w.facts.facilities[facility_id].maintenance_order_id)
	var cash: int = HospitalLedger.balance(f.w)
	f.s.services.maintenance.dispatch(f.w)
	var held: bool = use.occupied and not use.critical_commitment and not f.w.facts.facilities[facility_id].failed and f.w.facts.maintenance.contractors.is_empty() and f.w.facts.maintenance.jobs[job_id].remaining_milli==30000 and HospitalLedger.balance(f.w)==cash
	var restored: Dictionary = _restore(f)
	var restored_use: Dictionary = HospitalEquipmentUse.query(restored.w,facility_id)
	var restore_preserved: bool = restored_use==use and restored.w.validate(_content).is_empty()
	var cancel: CommandResult = _command(restored,"clinical_refer",{"visit_id":visit_id})
	var no_early_work: bool = true
	for tick: int in 600:
		var occupied: bool = bool(HospitalEquipmentUse.query(restored.w,facility_id).occupied)
		restored.s.services.maintenance.boundaries(restored.w)
		restored.s.services.maintenance.dispatch(restored.w)
		if occupied:
			no_early_work = no_early_work and str(restored.w.facts.maintenance.jobs[job_id].worker_id).is_empty() and not restored.w.facts.facilities[facility_id].failed and HospitalLedger.balance(restored.w)==cash
		_clinic_tick(restored,true)
		if restored.w.facts.maintenance.jobs[job_id].started: break
	var job: Dictionary = restored.w.facts.maintenance.jobs[job_id]
	var worker_id: String = str(job.worker_id)
	var released: bool = not HospitalEquipmentUse.query(restored.w,facility_id).occupied
	var validation: String = restored.w.validate(_content)
	var invalid: WorldState = WorldState.new(restored.w.freeze())
	invalid.facts.visits[visit_id].actor_id = worker_id
	var alias_rejected: bool = not worker_id.is_empty() and invalid.validate(_content)=="患者不能同时充当上门维修人员"
	return _result(held and restore_preserved and cancel.accepted and no_early_work and released and job.started and job.completed_milli==100 and job.paid_parts==40 and HospitalLedger.balance(restored.w)==cash-40 and restored.w.facts.attempts.is_empty() and restored.w.facts.inventory.issues.is_empty() and alias_rejected and validation.is_empty(),{"initial_use":use,"held":held,"restore_preserved":restore_preserved,"cancel":cancel.to_record(),"no_work_before_release":no_early_work,"released":released,"job":job,"cash_before":cash,"cash_after":HospitalLedger.balance(restored.w),"alias_rejected":alias_rejected,"validation":validation})

func _case_41() -> Dictionary:
	var f: Dictionary = _new("维护设备定义索引",false,100000)
	_place(f,"ops41_z_tool","SE02",[37,80])
	_place(f,"ops41_a_machine","M09",[42,80])
	_place(f,"ops41_middle_bin","FUR18",[60,92])
	_place(f,"ops41_inventory","M37",[52,80])
	var stored: CommandResult = _command(f,"build_store",{"target_id":"ops41_inventory"})
	var first: CommandResult = _command(f,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[36,72]})
	var second: CommandResult = _command(f,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[48,70]})
	if not f.errors.is_empty() or not stored.accepted or not first.accepted or not second.accepted:
		return _result(false,{"errors":f.errors,"stored":stored.to_record(),"connectors":[first.to_record(),second.to_record()]})
	var service: HospitalMaintenance = f.s.services.maintenance
	service.ensure(f.w)
	var connector_ids: Array = f.w.facts.connectors.keys()
	connector_ids.sort()
	# Dictionary insertion order is not connector scan order. Keep the original
	# legal records while presenting the reverse insertion order as input.
	var reordered: Dictionary = f.w.freeze()
	reordered.connectors = {}
	for index: int in range(connector_ids.size()-1,-1,-1):
		var id: String = connector_ids[index]
		reordered.connectors[id] = f.w.facts.connectors[id].duplicate(true)
	f.w.facts = reordered
	var inventory_ids: Array = ["starter_gift_M09","ops41_inventory"]
	var expected: Array = ["ops41_a_machine","ops41_z_tool"]+connector_ids+inventory_ids
	var before: Dictionary = f.w.freeze()
	var equipment: Dictionary = service._equipment(f.w)
	var ordered: bool = equipment.keys()==expected
	var readonly: bool = before==f.w.freeze()
	var live: bool = is_same(equipment.get("ops41_a_machine"),f.w.facts.facilities.ops41_a_machine) and is_same(equipment.get(connector_ids[0]),f.w.facts.connectors[connector_ids[0]]) and is_same(equipment.get("ops41_inventory"),f.w.facts.inventory.build_items.ops41_inventory)
	f.w.facts.facilities.ops41_a_machine.condition = 73.0
	f.w.facts.facilities.ops41_a_machine.failed = true
	var current: Dictionary = service._equipment(f.w)
	live = live and current.get("ops41_a_machine",{}).get("condition")==73.0 and current.get("ops41_a_machine",{}).get("failed")==true
	# Reuse a legal placed record at the same location. Only the public geometry
	# invalidation boundary, not a collection-size change, can invalidate this index.
	var count: int = f.w.facts.facilities.size()
	var replacement: Dictionary = f.w.facts.facilities.ops41_a_machine.duplicate(true)
	replacement.id = "ops41_b_machine"
	f.w.facts.facilities.erase("ops41_a_machine")
	f.w.facts.facilities[replacement.id] = replacement
	f.w.invalidate_geometry()
	var after_geometry: Dictionary = service._equipment(f.w)
	var geometry_invalidated: bool = f.w.facts.facilities.size()==count and after_geometry.keys()==["ops41_b_machine","ops41_z_tool"]+connector_ids+inventory_ids
	var replaced: Dictionary = f.w.freeze()
	replacement = replaced.facilities.ops41_b_machine
	replaced.facilities.erase("ops41_b_machine")
	replacement.id = "ops41_c_machine"
	replaced.facilities[replacement.id] = replacement
	f.w.facts = replaced
	var after_facts: Dictionary = service._equipment(f.w)
	var facts_invalidated: bool = f.w.facts.facilities.size()==count and after_facts.keys()==["ops41_c_machine","ops41_z_tool"]+connector_ids+inventory_ids and is_same(after_facts.get("ops41_c_machine"),f.w.facts.facilities.ops41_c_machine) and not is_same(after_facts.get("ops41_c_machine"),after_geometry.get("ops41_b_machine"))
	var placed_ids: Array = ["ops41_c_machine","ops41_z_tool"]+connector_ids
	for id: String in placed_ids:
		after_facts[id].condition = 35.0
		after_facts[id].failed = false
		after_facts[id].pending_failure = false
	f.w.facts.maintenance.next_scan_tick = f.w.sim_tick
	var reference: WorldState = WorldState.new(f.w.freeze())
	var expected_faults: Dictionary = {}
	for id: String in placed_ids:
		var item: Dictionary = after_facts[id]
		var definition: Dictionary = _content.facility_definition(item.definition_id)
		if definition.is_empty(): definition = _content.definition("vertical_connectors",item.definition_id)
		var base_failure: int = 0
		for category: Dictionary in _content.balance.equipment.classes:
			if category.id==definition.get("equipment_class",""): base_failure = int(category.base_failure_bp)
		# Condition 35 is below 40: the content risk multiplier is 8. Consume one
		# independent draw per placed device in the required order; inventory skips it.
		expected_faults[id] = reference.draw("equipment",10000)<base_failure*8
	service.boundaries(f.w)
	var rolls_match: bool = reference.facts.rng==f.w.facts.rng
	for id: String in placed_ids:
		var item: Dictionary = after_facts[id]
		rolls_match = rolls_match and item.get("last_fault_roll_tick",-1)==f.w.sim_tick and (bool(item.failed) or bool(item.pending_failure))==expected_faults[id]
	var job_order: Array = []
	for job: Dictionary in f.w.facts.maintenance.jobs.values(): job_order.append(str(job.facility_id))
	var inventory_unchanged: bool = true
	for id: String in inventory_ids: inventory_unchanged = inventory_unchanged and not after_facts[id].has("last_fault_roll_tick")
	return _result(ordered and readonly and live and geometry_invalidated and facts_invalidated and rolls_match and job_order==placed_ids and inventory_unchanged,{"initial_order":equipment.keys(),"expected_order":expected,"readonly":readonly,"live_references":live,"geometry_invalidated":geometry_invalidated,"facts_invalidated":facts_invalidated,"expected_faults":expected_faults,"rng_matches":rolls_match,"job_order":job_order,"inventory_skipped_scan":inventory_unchanged})
