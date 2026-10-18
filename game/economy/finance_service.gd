class_name FinanceService
extends RefCounted

const OPERATING_DENOMINATOR: int = 360000
var content: HospitalContent
var space: HospitalSpace
var supplies: RefCounted
var maintenance: RefCounted
var _indoor_geometry: Dictionary = {}
var _indoor_count: int = 0
var _station_world: int = 0
var _station_revision: int = -1
var _station_facilities: Dictionary = {}
var _station_count: int = -1
var _stations: int = 0

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry

func validate(world: WorldState) -> String:
	var facts: Dictionary = world.facts
	if not facts.get("staff") is Dictionary or not facts.get("ledger") is Dictionary or not facts.ledger.get("entries") is Dictionary:
		return "财务员工或账本集合无效"
	var has_economy: bool = facts.has("economy")
	var economy: Dictionary = {}
	if has_economy:
		if not facts.economy is Dictionary:
			return "财务事实必须是对象"
		economy = facts.economy
		if not economy.get("daily_accumulators") is Dictionary or not _saved_integer(economy.daily_accumulators.get("operating_numerator")):
			return "运营费用累计余数无效"
		if not _saved_integer(economy.get("operating_accrued_tick"),-1,world.sim_tick) or not _saved_integer(economy.get("last_settled_day"),0,(world.sim_tick+1)/WorldState.TICKS_PER_DAY):
			return "财务累计或日结时点无效"
		if not _saved_integer(economy.get("subsidy_next_day"),1) or not _saved_integer(economy.get("last_subsidy_period"),0,(world.sim_tick+1)/WorldState.TICKS_PER_DAY):
			return "补助周期无效"
		if not economy.get("saving_note") is String or economy.saving_note.length()>int(content.balance.finance_review.note_characters) or not economy.get("rescue_claimed") is bool:
			return "财务便签或救援领取事实无效"
		if economy.has("saving_target_amount") and (not _saved_integer(economy.saving_target_amount) or economy.saving_note.is_empty() and int(economy.saving_target_amount)!=0 or not economy.saving_note.is_empty() and int(economy.saving_target_amount)<1):
			return "存钱便签的目标金额无效"
		if economy.rescue_claimed:
			if not _saved_integer(economy.get("rescue_tick"),0,world.sim_tick) or not economy.get("rescue_blueprint_id") is String or content.definition("blueprint_presets",economy.rescue_blueprint_id).is_empty():
				return "救援领取时点或蓝图引用无效"
		elif economy.has("rescue_tick") or economy.has("rescue_blueprint_id"):
			return "未领取救援却保存了领取凭据"
	for id: Variant in facts.staff:
		var staff: Variant = facts.staff[id]
		if not id is String or not staff is Dictionary:
			return "工资员工身份结构无效"
		var has_wages: bool = staff.has("hired_tick") or staff.has("wage_numerator") or staff.has("wage_accrued_tick")
		if not has_wages and not has_economy:
			continue
		if not _saved_integer(staff.get("hired_tick"),0,world.sim_tick) or not _saved_integer(staff.get("wage_numerator")) or not _saved_integer(staff.get("wage_accrued_tick"),int(staff.get("hired_tick",0))-1,world.sim_tick):
			return "员工工资累计、聘用或已计薪时点无效"
		if staff.has("departed") and not staff.departed is bool:
			return "员工离职状态无效"
		if staff.get("departed",false) and (int(staff.wage_numerator)!=0 or not facts.ledger.entries.has(id+":wages_departure")):
			return "离职工资缺少结清凭据或仍有未结工资"
	for key: Variant in facts.ledger.entries:
		var entry: Variant = facts.ledger.entries[key]
		if not key is String or not entry is Dictionary or not entry.get("owner_id") is String or not entry.get("component") is String or not _saved_integer(entry.get("tick"),0,world.sim_tick):
			return "财务账目身份或时点结构无效"
		if key!=entry.owner_id+":"+entry.component or not _saved_integer(entry.get("amount"),-1000000000000) or not entry.get("settled") is bool:
			return "财务账目凭据或金额无效"
		if entry.has("cost") or entry.has("hospital_paid") or entry.has("direct_paid"):
			if not _saved_integer(entry.get("cost")) or not _saved_integer(entry.get("hospital_paid")) or not _saved_integer(entry.get("direct_paid")):
				return "费用实际支付分项无效"
			if int(entry.hospital_paid)+int(entry.direct_paid)!=int(entry.cost) or int(entry.amount)!=-int(entry.hospital_paid):
				return "费用、医院实付及直接支持不守恒"
			if not entry.get("funding_source") in ["community_aid","creative_fund"] or not entry.get("summary") is String:
				return "直接支持来源或费用摘要无效"
		var component: String = entry.component
		if component.begins_with("wages_day_") or component=="wages_departure":
			if not facts.staff.has(entry.owner_id) or not entry.has("cost") or not entry.settled:
				return "工资账目未引用实际员工或原支付凭据"
			if component.begins_with("wages_day_") and not _settlement_day(component.trim_prefix("wages_day_"),int(entry.tick)):
				return "工资日结身份与结算时点不符"
		elif component.begins_with("operations_day_"):
			if entry.owner_id!=world.hospital_id or not entry.has("cost") or not entry.settled or not _settlement_day(component.trim_prefix("operations_day_"),int(entry.tick)):
				return "运营日结医院、日期或支付凭据无效"
		elif component.begins_with("subsidy_"):
			var suffix: String = component.trim_prefix("subsidy_")
			if not suffix.is_valid_int() or suffix!=str(suffix.to_int()) or suffix.to_int()<1 or entry.owner_id!=world.hospital_id or int(entry.amount)<0 or not entry.settled:
				return "补助账目身份或金额无效"
			if has_economy and suffix.to_int()>int(economy.last_subsidy_period):
				return "补助账目超前于已结周期"
	if has_economy and int(economy.last_subsidy_period)>0 and not facts.ledger.entries.has(world.hospital_id+":subsidy_%d"%int(economy.last_subsidy_period)):
		return "已结补助周期缺少原账本凭据"
	return ""

func _saved_integer(value: Variant, minimum: int = 0, maximum: int = 1000000000000) -> bool:
	return value is int and int(value)>=minimum and int(value)<=maximum

func _settlement_day(suffix: String, tick: int) -> bool:
	return suffix.is_valid_int() and suffix==str(suffix.to_int()) and suffix.to_int()>0 and suffix.to_int()==(tick+1)/WorldState.TICKS_PER_DAY

func ensure(world: WorldState) -> void:
	if not world.facts.has("economy"):
		world.facts.economy = {"daily_accumulators":{"operating_numerator":0},"operating_accrued_tick":world.sim_tick-1,
			"last_settled_day":world.sim_tick/WorldState.TICKS_PER_DAY,"subsidy_next_day":int(content.balance.subsidy.first_payment_day),
			"last_subsidy_period":0,"saving_note":"","saving_target_amount":0,"rescue_claimed":false}
	for id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[id]
		if not staff.has("hired_tick"):
			staff.hired_tick = 0
		if not staff.has("wage_numerator"):
			staff.wage_numerator = 0
		if not staff.has("wage_accrued_tick"):
			staff.wage_accrued_tick = world.sim_tick-1

func wage(staff: Dictionary) -> int:
	var source: Array = content.balance.doctor_pay if staff.role=="doctor" else content.balance.staff
	for row: Dictionary in source:
		if (staff.role=="doctor" and row.title_id==staff.get("title_id","")) or (staff.role!="doctor" and row.role==staff.role):
			return int(row.wage_day)
	return 0

func pay_necessary(world: WorldState, owner: String, component: String, cost: int) -> CommandResult:
	if cost<0:
		return _result(world,false,"invalid_cost","费用不能为负")
	var key: String = owner+":"+component
	if world.facts.ledger.entries.has(key):
		var original: Dictionary = world.facts.ledger.entries[key]
		return _result(world,int(original.get("cost",-1))==cost,"duplicate" if int(original.get("cost",-1))==cost else "entry_id_conflict","原费用凭据已存在")
	var cash: int = world.available_ledger_balance()
	var paid: int = mini(maxi(0,cash),cost)
	var result: CommandResult = HospitalLedger.post(world,LedgerEntry.new(owner,component,-paid))
	if not result.accepted:
		return result
	var entry: Dictionary = world.facts.ledger.entries[key]
	entry.cost = cost
	entry.hospital_paid = paid
	entry.direct_paid = cost-paid
	entry.funding_source = "creative_fund" if world.facts.mode=="creative" else "community_aid"
	entry.summary = _owner_name(world,owner)
	return result

func settle(world: WorldState) -> void:
	ensure(world)
	var economy: Dictionary = world.facts.economy
	if int(economy.operating_accrued_tick)<world.sim_tick:
		economy.daily_accumulators.operating_numerator += operating_rate(world)
		economy.operating_accrued_tick = world.sim_tick
	for id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[id]
		if int(staff.wage_accrued_tick)<world.sim_tick and int(staff.hired_tick)<=world.sim_tick and not staff.get("departed",false):
			staff.wage_numerator += wage(staff)
			staff.wage_accrued_tick = world.sim_tick
	var day: int = (world.sim_tick+1)/WorldState.TICKS_PER_DAY
	if (world.sim_tick+1)%WorldState.TICKS_PER_DAY!=0 or day<=int(economy.last_settled_day):
		return
	# Clinical pending entries settle before the daily grant and necessary charges.
	HospitalLedger.settle(world)
	if day>=int(economy.subsidy_next_day):
		var interval: int = int(content.balance.subsidy.interval_days)
		var period: int = day/interval
		if world.facts.mode!="creative" and period>int(economy.last_subsidy_period):
			HospitalLedger.post(world,LedgerEntry.new(world.hospital_id,"subsidy_%d"%period,subsidy_amount(world)))
			economy.last_subsidy_period = period
		economy.subsidy_next_day = (period+1)*interval
	for id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[id]
		var numerator: int = int(staff.wage_numerator)
		var result: CommandResult = pay_necessary(world,id,"wages_day_%d"%day,numerator/WorldState.TICKS_PER_DAY)
		if result.accepted:
			staff.wage_numerator = numerator%WorldState.TICKS_PER_DAY
	var numerator: int = int(economy.daily_accumulators.operating_numerator)
	var operating: CommandResult = pay_necessary(world,world.hospital_id,"operations_day_%d"%day,numerator/OPERATING_DENOMINATOR)
	if operating.accepted:
		economy.daily_accumulators.operating_numerator = numerator%OPERATING_DENOMINATOR
	economy.last_settled_day = day

func settle_departure(world: WorldState, staff_id: String) -> CommandResult:
	ensure(world)
	if not world.facts.staff.has(staff_id):
		return _result(world,false,"staff_missing","员工不存在")
	var staff: Dictionary = world.facts.staff[staff_id]
	if staff.get("departed",false):
		return _result(world,true,"duplicate","该员工已完成离职结清")
	var numerator: int = int(staff.wage_numerator)
	var result: CommandResult = pay_necessary(world,staff_id,"wages_departure",(numerator+WorldState.TICKS_PER_DAY-1)/WorldState.TICKS_PER_DAY)
	if result.accepted:
		staff.wage_numerator = 0
		staff.departed = true
		staff.on_shift = false
		staff.block_new_work = true
	return result

func operating_rate(world: WorldState) -> int:
	if _station_world!=world.get_instance_id() or _station_revision!=world.geometry_revision or not is_same(_station_facilities,world.facts.facilities) or _station_count!=world.facts.facilities.size():
		_stations = 0
		for facility: Dictionary in world.facts.facilities.values():
			if facility.get("stored",false) or facility.get("under_construction",false): continue
			var id: String = str(facility.definition_id)
			if id.begins_with("M") or id in ["FUR01","FUR02","EQ01","EQ05","FUR05"]:
				_stations += int(facility.get("capacity",1)) if id=="EQ05" else 1
		_station_world = world.get_instance_id()
		_station_revision = world.geometry_revision
		_station_facilities = world.facts.facilities
		_station_count = world.facts.facilities.size()
	# Source rates are expressed as twentieths of a coin per hospital day.
	return roundi(float(content.balance.daily_base_cost)*20.0)+roundi(float(content.balance.daily_cost_per_station)*20.0)*_stations+roundi(float(content.balance.daily_cost_per_indoor_cell)*20.0)*_indoor_cells(world)

func _indoor_cells(world: WorldState) -> int:
	var unchanged: bool = true
	var count: int = 0
	for id: String in world.facts.rooms:
		var room: Dictionary = world.facts.rooms[id]
		if room.get("under_construction",false): continue
		count += 1
		var previous: Array = _indoor_geometry.get(id,[])
		if previous.size()!=4 or previous[0]!=room.floor_id or previous[1]!=room.origin or previous[2]!=room.size or previous[3]!=room.get("cells"):
			unchanged = false
	if unchanged and count==_indoor_geometry.size(): return _indoor_count
	var geometry: Dictionary = {}
	for id: String in world.facts.rooms:
		var room: Dictionary = world.facts.rooms[id]
		if not room.get("under_construction",false):
			geometry[id] = [room.floor_id,room.origin,room.size,room.get("cells")]
	if geometry==_indoor_geometry: return _indoor_count
	var cells: Dictionary = {}
	for id: String in geometry:
		var room: Dictionary = world.facts.rooms[id]
		for cell: Array in BuildGeometry.cells(room):
			cells[Vector3i(int(room.floor_id),int(cell[0]),int(cell[1]))] = true
	_indoor_geometry = geometry.duplicate(true)
	_indoor_count = cells.size()
	return _indoor_count

func subsidy_amount(world: WorldState) -> int:
	var plots: int = world.facts.floors.overrides.get("1",{}).get("plots",[]).size()
	return mini(int(content.balance.subsidy.cap),int(content.balance.subsidy.base_amount)+int(content.balance.subsidy.per_extra_plot)*maxi(0,plots-1))

func forecast(world: WorldState) -> Array:
	var economy: Dictionary = world.facts.get("economy",{})
	var operating_numerator: int = int(economy.get("daily_accumulators",{}).get("operating_numerator",0))
	var wages: Dictionary = {}
	for id: String in world.ids("staff"):
		wages[id] = int(world.facts.staff[id].get("wage_numerator",0))
	var today: int = world.sim_tick/WorldState.TICKS_PER_DAY+1
	var first_day: int = maxi(today,int(economy.get("last_settled_day",today-1))+1)
	var cash: int = HospitalLedger.balance(world)
	var rows: Array = []
	var rate: int = operating_rate(world)
	for offset: int in range(int(content.balance.finance_review.closing_days)):
		var day: int = first_day+offset
		var end: int = day*WorldState.TICKS_PER_DAY-1
		var wage_due: int = 0
		var roles: Dictionary = {}
		for id: String in world.ids("staff"):
			var staff: Dictionary = world.facts.staff[id]
			if staff.get("departed",false):
				continue
			var ticks: int = maxi(0,end-maxi(int(staff.get("wage_accrued_tick",world.sim_tick-1)),int(staff.get("hired_tick",0))-1)) if offset==0 else WorldState.TICKS_PER_DAY
			wages[id] += ticks*wage(staff)
			var payable: int = int(wages[id])/WorldState.TICKS_PER_DAY
			wages[id] = int(wages[id])%WorldState.TICKS_PER_DAY
			wage_due += payable
			roles[staff.role] = int(roles.get(staff.role,0))+payable
		var ticks: int = maxi(0,end-int(economy.get("operating_accrued_tick",world.sim_tick-1))) if offset==0 else WorldState.TICKS_PER_DAY
		operating_numerator += rate*ticks
		var operation_due: int = operating_numerator/OPERATING_DENOMINATOR
		operating_numerator %= OPERATING_DENOMINATOR
		var grant: int = subsidy_amount(world) if world.facts.mode!="creative" and day%int(content.balance.subsidy.interval_days)==0 and day>=int(economy.get("subsidy_next_day",content.balance.subsidy.first_payment_day)) else 0
		var paid: int = mini(maxi(0,cash+grant),wage_due+operation_due)
		cash += grant-paid
		rows.append({"day":day,"forecast":true,"subsidy":grant,"wages":wage_due,"wages_by_role":roles,"operations":operation_due,
			"hospital_paid":paid,"direct_support":wage_due+operation_due-paid,"closing_cash":cash,"assumption":"按当前在职、职称、地块和已完布局；未计收入、未发生故障与待生效变更"})
	return rows

func required_reserve(world: WorldState) -> int:
	var next: Dictionary = forecast(world)[0]
	return int(next.wages)+int(next.operations)

func execute(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	ensure(world)
	if kind=="finance_note":
		var note: String = str(payload.get("text",""))
		if note.length()>int(content.balance.finance_review.note_characters):
			return _result(world,false,"note_too_long","存钱便签最多40字")
		var target: Variant = payload.get("target_amount",0)
		if not _saved_integer(target) or note.is_empty() and int(target)!=0 or not note.is_empty() and int(target)<1:
			return _result(world,false,"invalid_note_target","填写1至40字和正整数目标金额，或清除便签")
		world.facts.economy.saving_note = note
		world.facts.economy.saving_target_amount = int(target)
		world.touch()
		return _result(world,true,"applied","")
	if kind=="finance_rescue":
		return _rescue(world)
	if kind=="finance_return_rescue":
		return _return_rescue(world)
	return _result(world,false,"unknown_command","未知财务命令")

func _has_service(world: WorldState, owned_only: bool = false) -> bool:
	var desks: Dictionary = {"reception":false,"gp":false,"treatment":false}
	for facility: Dictionary in world.facts.facilities.values():
		if facility.get("stored",false) or facility.get("failed",false) or (owned_only and facility.get("ownership","")=="borrowed"):
			continue
		var id: String = str(facility.definition_id)
		if id=="FUR01":
			desks.reception = true
		if id=="FUR02":
			desks.gp = true
		if id.begins_with("M"):
			desks.treatment = true
	var receptionist: bool = false
	var diagnostic: bool = false
	var therapeutic: bool = false
	for staff: Dictionary in world.facts.staff.values():
		if staff.get("departed",false):
			continue
		receptionist = receptionist or staff.role=="receptionist"
		if staff.role=="doctor":
			diagnostic = diagnostic or int(staff.abilities.diagnosis)>0
			therapeutic = therapeutic or int(staff.abilities.treatment)>0
	return desks.reception and desks.gp and desks.treatment and receptionist and diagnostic and therapeutic

func _rescue(world: WorldState) -> CommandResult:
	if world.facts.economy.rescue_claimed:
		return _result(world,false,"rescue_claimed","本院基础救援箱已领取")
	if HospitalLedger.balance(world)>=3000 or _has_service(world):
		return _result(world,false,"rescue_not_needed","基础救援限现金不足3000且没有可接诊项目时使用")
	var clone: WorldState = WorldState.new(world.freeze())
	if not clone.facts.inventory.has("build_items"):
		clone.facts.inventory.build_items = {}
	for definition_id: String in ["FUR01","FUR02","M37"]:
		var id: String = clone.new_id("rescue_item")
		clone.facts.inventory.build_items[id] = {"id":id,"definition_id":definition_id,"paid_cost":0,"ownership":"borrowed","rotation":0,"completed_upgrade_paid_cost":0}
	var counts: Dictionary = {"receptionist":0,"doctor":0}
	for staff: Dictionary in clone.facts.staff.values():
		if counts.has(staff.role) and not staff.get("departed",false):
			counts[staff.role] += 1
	var needed: Array = []
	if int(counts.receptionist)<1:
		needed.append("receptionist")
	for index: int in range(maxi(0,2-int(counts.doctor))):
		needed.append("doctor")
	var changed: Array = []
	for role: String in needed:
		var cell: Array = _rescue_entry(clone)
		if cell.is_empty():
			return _result(world,false,"entry_blocked","入口没有足够的真实落脚位；腾出入口后可领取救援箱")
		var id: String = clone.new_id("rescue_staff")
		clone.facts.actors[id] = {"id":id,"name":"社区"+role,"species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":cell,"height_m":0.0},"facing":0.0,"posture":"standing"}
		clone.facts.staff[id] = {"id":id,"role":role,"title_id":"DT01" if role=="doctor" else "","abilities":{"diagnosis":1 if role=="doctor" else 0,"treatment":1 if role=="doctor" else 0,"care":0,"surgery":0},
			"energy":100.0,"fatigue":10.0 if role=="doctor" else 0.0,"stress_milli":10000,"on_shift":true,"certificates":[],
			"practice":{"diagnosis":0,"treatment":0,"care":0,"surgery":0},"completed_jobs":{},"hired_tick":world.sim_tick,"wage_numerator":0,"wage_accrued_tick":world.sim_tick-1,
			"personality_id":"DP01" if role=="doctor" else "","primary_track":"treatment","rescue_employee":true}
		if role!="doctor":
			clone.facts.staff[id].skill = 1
			clone.facts.staff[id].job_practice = 0
		changed.append(id)
	clone.facts.economy.rescue_claimed = true
	clone.facts.economy.rescue_blueprint_id = "BP03"
	clone.facts.economy.rescue_tick = world.sim_tick
	world.facts = clone.facts
	world.touch()
	return CommandResult.new(true,"applied","借用物已进入建造库存，可自行放置；救援员工正常计薪",changed,world.revision)

func _rescue_entry(world: WorldState) -> Array:
	var entry: Dictionary = world.facts.get("entry",{"cell":[47,93]})
	var anchor: Array = entry.get("cell",entry.get("anchor",[47,93]))
	var actor: Dictionary = {"id":"rescue_preview","species_id":"S49","facing":0.0,"location":{"kind":"floor","floor_id":1,"cell":anchor}}
	for y: int in range(int(anchor[1]),int(anchor[1])+3):
		for x: int in range(int(anchor[0]),int(anchor[0])+3):
			if not space.static_reason(world,actor,1,Vector2i(x,y)).is_empty():
				continue
			actor.location.cell = [x,y]
			var occupied: bool = false
			for present: Dictionary in world.facts.actors.values():
				if present.location.kind=="floor" and int(present.location.floor_id)==1 and space.body_rectangle(actor).intersects(space.body_rectangle(present)):
					occupied = true
					break
			if not occupied:
				return [x,y]
	return []

func _return_rescue(world: WorldState) -> CommandResult:
	if HospitalLedger.balance(world)<3000 or not _has_service(world,true):
		return _result(world,false,"return_not_ready","现金恢复3000且自有等价接诊设施就绪后可归还库存中的借用物")
	var items: Dictionary = world.facts.inventory.get("build_items",{})
	var removed: bool = false
	for id: String in items.keys():
		if items[id].ownership=="borrowed":
			items.erase(id)
			removed = true
	if not removed:
		return _result(world,false,"pack_borrowed_first","先将借用设备按原建造操作打包入库存")
	world.touch()
	return _result(world,true,"applied","借用设备已归还，员工继续留任")

func query(world: WorldState, day: int = -1, page: int = 0, page_size: int = 30) -> Dictionary:
	var selected_day: int = world.sim_tick/WorldState.TICKS_PER_DAY+1 if day<1 else day
	var views: Array = []
	for definition: Dictionary in content.catalog.finance_views:
		views.append({"id":definition.id,"name":definition.name,"group":definition.group,"amount":0,"rows":[]})
	var keys: Array = world.facts.ledger.entries.keys()
	keys.sort_custom(func(a: String,b: String) -> bool:
		var ea: Dictionary = world.facts.ledger.entries[a]
		var eb: Dictionary = world.facts.ledger.entries[b]
		return int(ea.tick)<int(eb.tick) if ea.tick!=eb.tick else a<b)
	var totals: Dictionary = {"clinical_income":0,"operating_cost":0,"cash_change":0,"direct_support":0,"development_cost":0}
	var actual: Dictionary = {}
	for id: String in keys:
		var entry: Dictionary = _entry_detail(world,world.facts.ledger.entries[id])
		if not entry.settled:
			continue
		var entry_day: int = int(entry.tick)/WorldState.TICKS_PER_DAY+1
		var group: String = _group(str(entry.component),int(entry.amount))
		if not actual.has(entry_day):
			actual[entry_day] = {"day":entry_day,"forecast":false,"clinical_income":0,"operating_cost":0,"cash_change":0}
		var cost: int = int(entry.get("cost",maxi(0,-int(entry.amount))))
		actual[entry_day].cash_change += int(entry.amount)
		if group=="clinical":
			actual[entry_day].clinical_income += int(entry.amount)
		if group=="operation":
			actual[entry_day].operating_cost += cost
		if entry_day!=selected_day:
			continue
		totals.cash_change += int(entry.amount)
		if group=="clinical":
			totals.clinical_income += int(entry.amount)
		if group=="operation":
			totals.operating_cost += cost
		if group=="development":
			totals.development_cost += cost
		totals.direct_support += int(entry.get("direct_paid",0))
		for view: Dictionary in views:
			if view.group==group:
				view.amount += cost if group in ["operation","development"] else int(entry.amount)
				view.rows.append({"entry_id":id,"owner_id":entry.owner_id,"component":entry.component,"tick":entry.tick,
					"summary":entry.get("summary",_owner_name(world,entry.owner_id)),"amount":entry.amount,"cost":cost,
					"hospital_paid":entry.get("hospital_paid",maxi(0,-int(entry.amount))),"direct_paid":entry.get("direct_paid",0),"locatable":_locatable(world,entry.owner_id)})
			if view.group=="direct_support" and int(entry.get("direct_paid",0))>0:
				view.amount += int(entry.direct_paid)
				view.rows.append({"entry_id":id,"owner_id":entry.owner_id,"amount":entry.direct_paid,"cost":cost,"funding_source":entry.funding_source})
	for view: Dictionary in views:
		view.row_count = view.rows.size()
		var start: int = maxi(0,page)*clampi(page_size,1,100)
		view.rows = view.rows.slice(start,start+clampi(page_size,1,100))
	totals.operating_surplus = int(totals.clinical_income)-int(totals.operating_cost)
	var actual_days: Array = []
	var latest: int = int(world.facts.get("economy",{}).get("last_settled_day",0))
	for d: int in range(maxi(1,latest-2),latest+1):
		actual_days.append(actual.get(d,{"day":d,"forecast":false,"clinical_income":0,"operating_cost":0,"cash_change":0}))
	var possible_costs: Array = []
	if maintenance!=null and maintenance.has_method("pending_costs"):
		possible_costs.append_array(maintenance.call("pending_costs",world))
	if supplies!=null and supplies.has_method("top_up"):
		var top_up: Dictionary = supplies.call("top_up",world)
		if not top_up.is_empty():
			possible_costs.append({"owner_id":"SUP01","kind":"supply_purchase","cost":int(top_up.cost),"forecast":true,"quote":top_up})
	var cash: int = HospitalLedger.balance(world)
	var target: int = int(world.facts.get("economy",{}).get("saving_target_amount",0))
	return {"cash":cash,"day":selected_day,"views":views,"today":totals,"forecast":forecast(world),"target_amount":target,"remaining_to_target":maxi(0,target-cash),"target_reached":target>0 and cash>=target,
		"actual_days":actual_days,"possible_costs":possible_costs,"saving_note":world.facts.get("economy",{}).get("saving_note",""),"rescue_available":HospitalLedger.balance(world)<3000 and not world.facts.get("economy",{}).get("rescue_claimed",false) and not _has_service(world),"performance":"暂时跳过"}

func _group(component: String, amount: int) -> String:
	if "refund" in component:
		return "refund"
	if component.begins_with("subsidy") or component.begins_with("task_reward"):
		return "grant"
	if component.begins_with("wages") or component.begins_with("operations") or "suppl" in component or "consum" in component or "repair" in component or "maintenance" in component:
		return "operation"
	for source: String in ["construction","land","recruitment","training","research","search","upgrade","department","renovation","build","course","promotion"]:
		if source in component:
			return "development"
	return "clinical" if amount>=0 else "development"

func _owner_name(world: WorldState, owner: String) -> String:
	if world.facts.actors.has(owner):
		return str(world.facts.actors[owner].name)
	if world.facts.visits.has(owner):
		return str(world.facts.actors.get(world.facts.visits[owner].actor_id,{}).get("name",owner))
	if world.facts.attempts.has(owner):
		return _owner_name(world,str(world.facts.attempts[owner].visit_id))
	if world.facts.facilities.has(owner):
		return str(content.facility_definition(world.facts.facilities[owner].definition_id).get("name",owner))
	return str(world.facts.display_name) if owner==world.hospital_id else owner

func _entry_detail(world: WorldState, source: Dictionary) -> Dictionary:
	var entry: Dictionary = source.duplicate(false)
	var order: Dictionary = world.facts.inventory.get("orders",{}).get(str(entry.owner_id),{})
	if not order.is_empty() and not entry.has("cost"):
		entry.cost = int(order.cost)
		entry.hospital_paid = int(order.hospital_paid)
		entry.direct_paid = int(order.direct_paid)
		entry.funding_source = str(order.get("direct_source",""))
	return entry

func _locatable(world: WorldState, owner: String) -> bool:
	return world.facts.actors.has(owner) or world.facts.facilities.has(owner) or world.facts.visits.has(owner)

func _result(world: WorldState, ok: bool, code: String, reason: String) -> CommandResult:
	return CommandResult.new(ok,code,reason,[],world.revision)
