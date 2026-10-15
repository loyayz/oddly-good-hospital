extends SceneTree

const Supplies = preload("res://game/operations/supply_service.gd")

class ClinicalRequests extends RefCounted:
	var blocked: Array = []
	func shortage_requests(_world: WorldState) -> Array:
		return blocked

class Reserve extends RefCounted:
	var calls: int = 0
	var amount: int = 1000
	func required_reserve(_world: WorldState) -> int:
		calls += 1
		return amount

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = FeasibilityHospitals.create("stage18",false,content)
	var service: RefCounted = Supplies.new(content,HospitalSpace.new(content))
	var requests: ClinicalRequests = ClinicalRequests.new()
	var reserve: Reserve = Reserve.new()
	service.clinic = requests
	service.finance = reserve
	service.ensure(world)
	world.facts.inventory.auto_restock = false
	var initial: int = int(world.facts.inventory.units)
	var cash: int = HospitalLedger.balance(world)
	_check("manual_paid_stock",service.execute(world,"supply_purchase",{"units":7,"unit_price":20,"order_id":"purchase-one"}).accepted and int(world.facts.inventory.units)==initial+7 and HospitalLedger.balance(world)==cash-140)
	var frozen: Dictionary = world.freeze()
	_check("duplicate_order_exactly_once",service.execute(world,"supply_purchase",{"units":7,"order_id":"purchase-one"}).accepted and frozen==world.freeze())
	_check("price_change_is_atomic",not service.execute(world,"supply_purchase",{"units":3,"unit_price":21}).accepted and frozen==world.freeze())
	_check("capacity_rejects_whole_order",not service.execute(world,"supply_purchase",{"units":1000}).accepted and frozen==world.freeze())
	world.facts.preparations["held"] = {"supply_units":8}
	world.facts.inventory.units = 10
	_check("available_derived_from_preparation",service.available(world)==2 and service.reserved(world)==8)
	requests.blocked = [{"ticket_id":"ticket-original","visit_id":world.facts.visits.keys()[0],"staff_ids":["treat_doctor"],"units":4}]
	var suggestion: Dictionary = service.top_up(world)
	_check("top_up_exact_full_case",int(suggestion.units)==2 and int(suggestion.cost)==40)
	world.facts.ledger = {"opening_balance":1819,"entries":{}}
	world.facts.preparations.clear()
	world.facts.inventory.units = 19
	world.facts.inventory.auto_restock = true
	service.boundaries(world)
	_check("auto_partial_whole_units",int(world.facts.inventory.units)==59 and HospitalLedger.balance(world)==1019)
	world.facts.inventory.units = 60
	reserve.calls = 0
	service.boundaries(world)
	_check("no_demand_does_not_read_finance",reserve.calls==0)
	world.facts.inventory.units = 0
	service.boundaries(world)
	_check("cash_floor_proof_avoids_budget",reserve.calls==0 and int(world.facts.inventory.units)==0)
	world.facts.mode = "creative"
	world.facts.ledger = {"opening_balance":25,"entries":{}}
	world.facts.inventory.orders.clear()
	var creative: CommandResult = service.execute(world,"supply_purchase",{"units":7,"order_id":"creative-seven"})
	_check("creative_direct_payment",creative.accepted and int(world.facts.inventory.orders["creative-seven"].hospital_paid)==25 and int(world.facts.inventory.orders["creative-seven"].direct_paid)==115 and HospitalLedger.balance(world)==0)
	world.facts.mode = "normal"
	world.facts.inventory.auto_restock = false
	world.facts.inventory.units = 0
	world.facts.staff.treat_doctor.stress_milli = 40000
	for index: int in 1800:
		world.facts.sim_tick = index
		service.advance(world)
	_check("actual_blocked_time_warns_and_strikes",world.facts.staff.treat_doctor.supply_strike and int(world.facts.staff.treat_doctor.stress_milli)==58000)
	world.facts.inventory.units = 4
	service.advance(world)
	_check("restock_closes_original_episode",not world.facts.staff.treat_doctor.supply_strike and int(world.facts.staff.treat_doctor.supply_return_tick)==world.sim_tick+300 and int(world.facts.staff.treat_doctor.stress_milli)==52000)
	service.advance(world)
	_check("episode_relief_once",int(world.facts.staff.treat_doctor.stress_milli)==52000)
	world.facts.inventory.units = 0
	_check("aid_real_purchase",service.execute(world,"supply_aid",{}).accepted and int(world.facts.inventory.units)==20)
	world.facts.inventory.units = 0
	frozen = world.freeze()
	_check("aid_once_per_hospital_day",not service.execute(world,"supply_aid",{}).accepted and frozen==world.freeze())
	var restored: WorldState = WorldState.new(world.freeze())
	service.ensure(restored)
	_check("restore_keeps_stock_and_order_receipts",restored.freeze()==world.freeze() and service.validate(restored).is_empty())
	print("STAGE18 checks="+str(17)+" failures="+str(failures))
	quit(0 if failures.is_empty() else 1)

func _check(label: String, success: bool) -> void:
	if not success:
		failures.append(label)
	print(("PASS " if success else "FAIL ")+label)
