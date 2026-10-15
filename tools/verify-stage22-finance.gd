extends SceneTree

const Finance = preload("res://game/economy/finance_service.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = FeasibilityHospitals.create("finance-rules",false,content)
	var finance = Finance.new(content,HospitalSpace.new(content))
	finance.ensure(world)
	world.facts.rooms = {"room":{"id":"room","kind":"gp","floor_id":1,"origin":[34,65],"size":[11,11]}}
	_check("four_stations_121_cells_rate",finance.operating_rate(world)==1561)
	var frozen: Dictionary = world.freeze()
	var projection: Array = finance.forecast(world)
	_check("three_days_exact_forecast",projection.size()==3 and projection[0].operations==78 and projection[2].subsidy==1200)
	_check("queries_do_not_pay_or_mutate",world.freeze()==frozen and HospitalLedger.balance(world)==100000)
	world.facts.staff.clear()
	world.facts.actors.clear()
	var operation_total: int = 0
	for day: int in range(1,21):
		world.facts.sim_tick = day*WorldState.TICKS_PER_DAY-1
		world.facts.economy.operating_accrued_tick = world.sim_tick
		world.facts.economy.daily_accumulators.operating_numerator += 1561*WorldState.TICKS_PER_DAY
		finance.settle(world)
		var entry: Dictionary = world.facts.ledger.entries[world.hospital_id+":operations_day_%d"%day]
		operation_total += int(entry.cost)
		_check("operating_day_%d"%day,int(entry.cost)==(79 if day==20 else 78))
	_check("twenty_day_carry_exact",operation_total==1561 and int(world.facts.economy.daily_accumulators.operating_numerator)==0)
	var after: Dictionary = world.freeze()
	finance.settle(world)
	_check("duplicate_daily_settlement",after==world.freeze())
	var restored: WorldState = WorldState.new(world.freeze())
	finance.settle(restored)
	_check("restore_does_not_repeat_subsidy",after==restored.freeze())
	world = FeasibilityHospitals.create("shortfall",false,content)
	finance = Finance.new(content,HospitalSpace.new(content))
	finance.ensure(world)
	world.facts.ledger.opening_balance = 100
	var payment: CommandResult = finance.pay_necessary(world,world.hospital_id,"maintenance_example",940)
	var entry: Dictionary = world.facts.ledger.entries[world.hospital_id+":maintenance_example"]
	_check("direct_aid_is_not_cash",payment.accepted and HospitalLedger.balance(world)==0 and entry.cost==940 and entry.hospital_paid==100 and entry.direct_paid==840)
	after = world.freeze()
	_check("same_necessary_cost_once",finance.pay_necessary(world,world.hospital_id,"maintenance_example",940).accepted and world.freeze()==after)
	_check("changed_cost_atomic",not finance.pay_necessary(world,world.hospital_id,"maintenance_example",941).accepted and world.freeze()==after)
	var report: Dictionary = finance.query(world)
	_check("cost_and_cash_change_separate",report.today.operating_surplus==-940 and report.today.cash_change==-100 and report.today.direct_support==840 and report.views.size()==6)
	world = FeasibilityHospitals.create("partial-wages",false,content)
	finance = Finance.new(content,HospitalSpace.new(content))
	finance.ensure(world)
	for id: String in world.facts.staff.keys():
		if id!="reception":
			world.facts.staff.erase(id)
	world.facts.staff.reception.hired_tick = 17900
	world.facts.sim_tick = 17900
	world.facts.economy.operating_accrued_tick = 17899
	world.facts.staff.reception.wage_accrued_tick = 17899
	for tick: int in range(17900,18000):
		world.facts.sim_tick = tick
		finance.settle(world)
	_check("hire_tick_wages_partial_day",world.facts.ledger.entries["reception:wages_day_1"].cost==0 and world.facts.staff.reception.wage_numerator==6000)
	_check("departure_rounds_up_once",finance.settle_departure(world,"reception").accepted and world.facts.ledger.entries["reception:wages_departure"].cost==1 and world.facts.staff.reception.wage_numerator==0)
	after = world.freeze()
	_check("departure_duplicate_preserves_cost",finance.settle_departure(world,"reception").accepted and after==world.freeze())
	world = FeasibilityHospitals.create("rounding",false,content)
	finance = Finance.new(content,HospitalSpace.new(content))
	finance.ensure(world)
	world.facts.sim_tick = 17999
	world.facts.economy.operating_accrued_tick = 17999
	for id: String in world.facts.staff.keys():
		if not id in ["reception","exam_nurse"]:
			world.facts.staff.erase(id)
	for staff: Dictionary in world.facts.staff.values():
		staff.wage_numerator = 17900
		staff.wage_accrued_tick = 17999
	_check("forecast_rounds_each_employee",finance.forecast(world)[0].wages==0)
	world.facts.mode = "creative"
	_check("creative_does_not_forecast_cash_grants",finance.forecast(world)[2].subsidy==0)
	world.facts.inventory.orders = {"supply_aid":{"cost":400,"hospital_paid":0,"direct_paid":400,"direct_source":"community_aid"}}
	HospitalLedger.post(world,LedgerEntry.new("supply_aid","supply_purchase",0))
	report = finance.query(world)
	_check("supplies_own_real_purchase_cost",report.today.operating_cost==400 and report.today.direct_support==400)
	world = FeasibilityHospitals.create("rescue",false,content)
	finance = Finance.new(content,HospitalSpace.new(content))
	finance.ensure(world)
	world.facts.ledger.opening_balance = 0
	world.facts.facilities.clear()
	world.facts.actors.clear()
	world.facts.staff.clear()
	_check("real_rescue_inventory_and_paid_staff",finance.execute(world,"finance_rescue",{}).accepted and world.facts.inventory.build_items.size()==3 and world.facts.staff.size()==4 and world.facts.facilities.is_empty())
	after = world.freeze()
	_check("rescue_once_per_hospital",not finance.execute(world,"finance_rescue",{}).accepted and after==world.freeze())
	print(JSON.stringify({"stage":22,"checks":checks,"failures":failures,"performance":"skipped"}))
	quit(0 if failures.is_empty() else 1)

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures.append(label)
