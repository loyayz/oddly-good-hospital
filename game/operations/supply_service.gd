class_name HospitalSupplies
extends RefCounted

var content: HospitalContent
var space: HospitalSpace
var clinic: RefCounted
var finance: RefCounted

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry

func ensure(world: WorldState) -> void:
	var stock: Dictionary = world.facts.inventory
	if not stock.has("orders"):
		stock.orders = {}
	if not stock.has("auto_restock"):
		stock.auto_restock = bool(content.balance.supplies.auto_restock_default)
	if not stock.has("usage"):
		stock.usage = {"day_index":world.sim_tick / WorldState.TICKS_PER_DAY,"today_units":0,"previous_units":0}
	if not stock.has("aid_day"):
		stock.aid_day = -1
		stock.aid_orders = 0
	if not stock.has("shortage"):
		stock.shortage = {"id":"","participants":{},"closed_tick":-1}

func reserved(world: WorldState) -> int:
	var total: int = 0
	for preparation: Dictionary in world.facts.preparations.values():
		total += int(preparation.get("supply_units",0))
	return total

func available(world: WorldState) -> int:
	return int(world.facts.inventory.units)-reserved(world)

func unit_price() -> int:
	return int(content.definition("medical_supplies",str(content.balance.supplies.definition_id)).unit_price)

func capacity(world: WorldState) -> int:
	var outpatient: int = 0
	var surgery: int = 0
	for facility: Dictionary in world.facts.facilities.values():
		if facility.get("location", "floor") == "inventory" or not facility.get("completed",true):
			continue
		var kind: String = content.registry.equipment_effect_kind(facility.definition_id)
		if kind == "outpatient":
			outpatient += 1
		elif kind == "surgery":
			surgery += 1
	var rules: Dictionary = content.balance.supplies
	return maxi(int(rules.capacity_floor),outpatient*int(rules.growth.outpatient_buffer_units)+surgery*int(rules.growth.surgery_buffer_units))

func reserve_budget(world: WorldState) -> int:
	var floor_amount: int = int(content.balance.supplies.cash_reserve_floor)
	if finance != null and finance.has_method("required_reserve"):
		return maxi(floor_amount,int(finance.call("required_reserve",world)))
	# Until the financial service is attached, the same actual wages and installed
	# station/floor facts supply the next daily payable upper bound.
	var payable: int = int(content.balance.daily_base_cost)
	for staff: Dictionary in world.facts.staff.values():
		payable += int(staff.get("daily_wage",staff.get("wage",0)))
	payable += int(content.balance.daily_cost_per_station)*world.facts.facilities.size()
	for room: Dictionary in world.facts.rooms.values():
		payable += ceili(float(room.size[0])*float(room.size[1])*float(content.balance.daily_cost_per_indoor_cell))
	return maxi(floor_amount,payable)

func query(world: WorldState) -> Dictionary:
	var rules: Dictionary = content.balance.supplies
	var cap: int = capacity(world)
	var demand: int = int(world.facts.inventory.get("usage",{}).get("previous_units",0))
	var target: int = mini(cap,maxi(int(rules.restock_floor),ceili(float(3*demand)/4.0)))
	var held: int = reserved(world)
	return {"definition_id":rules.definition_id,"units":world.facts.inventory.units,"reserved":held,
		"available":int(world.facts.inventory.units)-held,"capacity":cap,"unit_price":unit_price(),"target":target,
		"reorder":mini(target,maxi(int(rules.reorder_floor),ceili(float(demand)/4.0))),
		"reserve_budget":reserve_budget(world),"auto_restock":world.facts.inventory.get("auto_restock",true),
		"top_up":top_up(world),"shortage":world.facts.inventory.get("shortage",{}).duplicate(true)}

func purchase_quote(world: WorldState, units: int, source: String = "manual") -> Dictionary:
	var cost: int = units*unit_price()
	var cash: int = HospitalLedger.balance(world)
	var reason: String = ""
	if units < 1:
		reason = "采购数量必须为正整数"
	elif units > capacity(world)-int(world.facts.inventory.units):
		reason = "治疗包库存空间不足，保留原采购数量"
	elif source == "community_aid":
		var day_index: int = world.sim_tick / WorldState.TICKS_PER_DAY
		if units != int(content.balance.supplies.aid_purchase_units) or cash >= cost or requests(world).is_empty():
			reason = "援助仅用于实际缺包且现金不足的20包采购"
		elif int(world.facts.inventory.get("aid_day",-1)) == day_index and int(world.facts.inventory.get("aid_orders",0)) >= int(content.balance.supplies.aid_orders_per_day):
			reason = "本医院日的援助采购已经使用"
	elif world.facts.mode != "creative" and cash < cost:
		reason = "资金不足，原库存与采购草案保留"
	var hospital_paid: int = mini(cash,cost) if source == "community_aid" or world.facts.mode == "creative" else cost
	return {"ok":reason.is_empty(),"reason":reason,"units":units,"unit_price":unit_price(),"cost":cost,
		"hospital_paid":hospital_paid,"direct_paid":cost-hospital_paid,
		"direct_source":"community_aid" if source == "community_aid" else ("creative_fund" if cost>hospital_paid else ""),
		"cash_after":cash-hospital_paid,"stock_after":int(world.facts.inventory.units)+units}

func execute(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	match kind:
		"set_auto_restock", "supply_auto":
			if not payload.get("enabled") is bool:
				return _reject(world,"invalid_payload","自动补货开关无效")
			world.facts.inventory.auto_restock = payload.enabled
			world.touch()
			return CommandResult.new(true,"applied","",["SUP01"],world.revision)
		"purchase_supplies", "supply_purchase", "supply_aid":
			var units_value: Variant = payload.get("units",int(content.balance.supplies.aid_purchase_units) if kind=="supply_aid" else 0)
			if not units_value is int or int(units_value)<1 or int(units_value)>1000000:
				return _reject(world,"invalid_quantity","采购数量必须为正整数")
			if int(payload.get("unit_price",unit_price())) != unit_price():
				return _reject(world,"material_change","治疗包单价已经改变，保留原数量供刷新")
			return _purchase(world,int(units_value),"community_aid" if kind=="supply_aid" else "manual",str(payload.get("order_id","")))
	return _reject(world,"unknown_command","未知耗材操作")

func _purchase(world: WorldState, units: int, source: String, requested_id: String = "") -> CommandResult:
	var orders: Dictionary = world.facts.inventory.orders
	if not requested_id.is_empty() and orders.has(requested_id):
		var prior: Dictionary = orders[requested_id]
		if int(prior.units)!=units or prior.source!=source or int(prior.unit_price)!=unit_price():
			return _reject(world,"order_conflict","同一采购凭据的数量或来源已改变")
		return CommandResult.new(true,"duplicate","",[],world.revision)
	var quote: Dictionary = purchase_quote(world,units,source)
	if not quote.ok:
		return _reject(world,"purchase_unavailable",quote.reason)
	# An id is allocated only after all quote conditions are valid. Ledger posting
	# is the final fallible operation; unpaid orders never change the stock.
	var id: String = requested_id if not requested_id.is_empty() else "supply_%08d" % (int(world.facts.entity_next)+1)
	var payment: CommandResult = HospitalLedger.post(world,LedgerEntry.new(id,"supply_purchase",-int(quote.hospital_paid)))
	if not payment.accepted:
		return payment
	if requested_id.is_empty():
		world.new_id("supply")
	orders[id] = {"id":id,"units":units,"unit_price":unit_price(),"cost":quote.cost,"source":source,
		"hospital_paid":quote.hospital_paid,"direct_paid":quote.direct_paid,"direct_source":quote.direct_source,
		"tick":world.sim_tick,"completed":true}
	world.facts.inventory.units += units
	if source == "community_aid":
		var day_index: int = world.sim_tick / WorldState.TICKS_PER_DAY
		if int(world.facts.inventory.aid_day) != day_index:
			world.facts.inventory.aid_day = day_index
			world.facts.inventory.aid_orders = 0
		world.facts.inventory.aid_orders += 1
	world.touch()
	return CommandResult.new(true,"applied","",[id,"SUP01"],world.revision)

func boundaries(world: WorldState) -> void:
	ensure(world)
	_roll_usage(world)
	var stock: Dictionary = world.facts.inventory
	if not stock.auto_restock:
		return
	var rules: Dictionary = content.balance.supplies
	var amount: int = available(world)
	var demand: int = int(stock.usage.previous_units)
	var unclamped_reorder: int = maxi(int(rules.reorder_floor),ceili(float(demand)/4.0))
	if amount >= unclamped_reorder:
		return
	var creative: bool = world.facts.mode == "creative"
	var cash: int = HospitalLedger.balance(world)
	if not creative and cash < int(rules.cash_reserve_floor)+unit_price():
		return
	var cap: int = capacity(world)
	var target: int = mini(cap,maxi(int(rules.restock_floor),ceili(float(3*demand)/4.0)))
	var reorder: int = mini(target,unclamped_reorder)
	if amount >= reorder or int(stock.units)>=cap:
		return
	var units: int = mini(target-amount,cap-int(stock.units))
	if not creative:
		units = mini(units,maxi(0,(cash-reserve_budget(world))/unit_price()))
	if units > 0:
		_purchase(world,units,"automatic")

func _roll_usage(world: WorldState) -> void:
	var usage: Dictionary = world.facts.inventory.usage
	var day_index: int = world.sim_tick / WorldState.TICKS_PER_DAY
	if day_index > int(usage.day_index):
		usage.previous_units = usage.today_units if day_index==int(usage.day_index)+1 else 0
		usage.today_units = 0
		usage.day_index = day_index

func requests(world: WorldState) -> Array:
	if clinic != null and clinic.has_method("shortage_requests"):
		return clinic.call("shortage_requests",world)
	return []

func top_up(world: WorldState) -> Dictionary:
	var candidates: Array = requests(world)
	if candidates.is_empty():
		return {}
	var required: int = int(candidates[0].units)
	var episode: Dictionary = world.facts.inventory.get("shortage",{})
	var recovering: bool = false
	for staff_id: String in episode.get("participants",{}):
		if world.facts.staff.has(staff_id) and world.facts.staff[staff_id].get("supply_strike",false):
			recovering = true
	if recovering:
		for request: Dictionary in candidates:
			required = maxi(required,int(request.units))
	var units: int = maxi(0,required-available(world))
	if units == 0:
		return {}
	var result: Dictionary = purchase_quote(world,units)
	result["target"] = candidates[0].duplicate(true) if not recovering else {}
	result["recovering"] = recovering
	return result

func advance(world: WorldState) -> void:
	var candidates: Array = requests(world)
	var episode: Dictionary = world.facts.inventory.shortage
	var blocked: Array = []
	var amount: int = available(world)
	for request: Dictionary in candidates:
		if int(request.units)>amount:
			blocked.append(request)
	if blocked.is_empty():
		if not str(episode.id).is_empty():
			_close_shortage(world,episode)
		return
	if str(episode.id).is_empty():
		episode.id = world.new_id("shortage")
		episode.participants = {}
		episode.closed_tick = -1
	var active: Dictionary = {}
	for request: Dictionary in blocked:
		for staff_id: String in request.staff_ids:
			if world.facts.staff.has(staff_id):
				active[staff_id] = true
	var rules: Dictionary = content.balance.supplies
	for staff_id: String in active:
		var staff: Dictionary = world.facts.staff[staff_id]
		if not episode.participants.has(staff_id):
			episode.participants[staff_id] = {"blocked_ticks":0,"warnings":0}
		var participant: Dictionary = episode.participants[staff_id]
		participant.blocked_ticks += 1
		var warnings: int = mini(int(rules.warnings_per_episode),int(participant.blocked_ticks)/(int(rules.shortage_repeat_seconds)*10))
		if warnings > int(participant.warnings):
			staff.stress_milli = mini(100000,int(staff.stress_milli)+(warnings-int(participant.warnings))*int(rules.shortage_stress_per_warning)*1000)
			participant.warnings = warnings
		if int(participant.blocked_ticks)>=int(rules.strike_after_seconds)*10 and int(staff.stress_milli)>=int(rules.strike_stress_threshold)*1000:
			staff.supply_strike = true
			staff.supply_shortage_id = episode.id

func _close_shortage(world: WorldState, episode: Dictionary) -> void:
	var rules: Dictionary = content.balance.supplies
	for staff_id: String in episode.participants:
		if not world.facts.staff.has(staff_id):
			continue
		var staff: Dictionary = world.facts.staff[staff_id]
		staff.stress_milli = maxi(0,int(staff.stress_milli)-int(rules.restock_stress_relief)*1000)
		if staff.get("supply_strike",false):
			staff.supply_strike = false
			staff.supply_return_tick = world.sim_tick+int(rules.return_to_work_seconds)*10
		staff.erase("supply_shortage_id")
	world.facts.inventory.shortage = {"id":"","participants":{},"closed_tick":world.sim_tick,"last_id":episode.id}

func validate(world: WorldState) -> String:
	var stock_value: Variant = world.facts.get("inventory")
	if not stock_value is Dictionary or not stock_value.get("units") is int or not stock_value.get("orders") is Dictionary or not world.facts.get("preparations") is Dictionary or not world.facts.get("ledger") is Dictionary or not world.facts.ledger.get("entries") is Dictionary:
		return "治疗包或付款事实集合无效"
	var stock: Dictionary = stock_value
	for preparation: Variant in world.facts.preparations.values():
		if not preparation is Dictionary or not preparation.get("supply_units",0) is int or int(preparation.get("supply_units",0))<0:
			return "治疗包治疗预留记录无效"
	if int(stock.units)<0 or reserved(world)>int(stock.units):
		return "治疗包实存或有效预留不守恒"
	for order_value: Variant in stock.orders.values():
		if not order_value is Dictionary:
			return "采购记录无效"
		var order: Dictionary = order_value
		if not order.get("id") is String:
			return "采购记录身份类型无效"
		for field: String in ["units","unit_price","cost","hospital_paid","direct_paid"]:
			if not order.get(field) is int:
				return "采购记录字段类型无效"
		if int(order.units)<=0 or int(order.cost)!=int(order.units)*int(order.unit_price) or int(order.cost)!=int(order.hospital_paid)+int(order.direct_paid):
			return "采购付款与实到数量不一致"
		var entry_value: Variant = world.facts.ledger.entries.get(str(order.id)+":supply_purchase",{})
		if not entry_value is Dictionary or not entry_value.get("settled") is bool or not entry_value.get("amount") is int or not entry_value.settled or int(entry_value.amount)!=-int(order.hospital_paid):
			return "治疗包入库缺少真实付款凭据"
	return ""

func _reject(world: WorldState, code: String, reason: String) -> CommandResult:
	return CommandResult.new(false,code,reason,[],world.revision)
