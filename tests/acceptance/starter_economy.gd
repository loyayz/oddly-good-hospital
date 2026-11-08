extends RefCounted

# Source-derived calibration for a newly created preset only. Expected repair
# spending is a risk-weighted budget, not a ten-day survival or throughput proof.
func run_case(world: WorldState, content: HospitalContent) -> Dictionary:
	var before: Dictionary = world.freeze()
	var counts: Dictionary = {}
	var wages: int = 0
	var hiring: int = 0
	for role: String in content.balance.starting_staff: counts[role] = 0
	for staff: Dictionary in world.facts.staff.values():
		counts[staff.role] = int(counts.get(staff.role,0))+1
		var prices: Array = content.balance.doctor_pay if staff.role=="doctor" else content.balance.staff
		for price: Dictionary in prices:
			if staff.role=="doctor" and price.title_id!=staff.title_id: continue
			if staff.role!="doctor" and price.role!=staff.role: continue
			wages += int(price.wage_day)
			hiring += int(price.hire)
	var construction: int = 0
	for row: Dictionary in content.balance.starter_purchase: construction += int(row.amount)
	var supply_cost: int = int(content.balance.supplies.initial_purchase_units)*int(content.definition("medical_supplies","SUP01").unit_price)
	var paid: Dictionary = {"construction":0,"hiring":0,"supplies":0}
	for entry: Dictionary in world.facts.ledger.entries.values():
		if str(entry.component).begins_with("starter_build_"): paid.construction -= int(entry.amount)
		elif entry.component=="hire": paid.hiring -= int(entry.amount)
		elif entry.component=="starter_supplies": paid.supplies -= int(entry.amount)
	var indoor_cells: int = 0
	for room: Dictionary in world.facts.rooms.values(): indoor_cells += int(room.size[0])*int(room.size[1])
	var service_stations: int = 0
	var seats: int = 0
	var expected_repairs: float = 0.0
	var scans_per_day: float = float(content.balance.day_seconds)/float(content.balance.equipment.scan_seconds)
	var worst_risk_multiplier: float = float(content.balance.equipment.risk_multipliers.max())
	for facility: Dictionary in world.facts.facilities.values():
		var definition_id: String = facility.definition_id
		if definition_id.begins_with("M") or definition_id in ["FUR02","FUR05","EQ01","EQ05"]: service_stations += 1
		if definition_id=="FUR09": seats += 1
		if not definition_id in content.balance.equipment.maintained_definition_ids: continue
		var definition: Dictionary = content.facility_definition(definition_id)
		for category: Dictionary in content.balance.equipment.classes:
			if category.id==definition.equipment_class:
				expected_repairs += scans_per_day*float(category.base_failure_bp)/10000.0*worst_risk_multiplier*float(category.repair_parts)
	var operations: float = float(content.balance.daily_base_cost)+float(content.balance.daily_cost_per_station)*service_stations+float(content.balance.daily_cost_per_indoor_cell)*indoor_cells
	var maintenance: int = int(content.balance.balance_reference.maintenance_allowance_per_day)
	var daily_budget: float = wages+operations+expected_repairs+maintenance
	var cash: int = int(content.balance.starting_cash)-construction-hiring-supply_cost
	var buffer_days: float = float(cash)/daily_budget
	var checks: Dictionary = {
		"actual_roster_matches_source":counts==content.balance.starting_staff and counts.get("doctor")==3 and counts.get("nurse")==2 and world.facts.staff.size()==6,
		"actual_purchase_ledger":paid.construction==construction and paid.hiring==hiring and paid.supplies==supply_cost,
		"starting_money":construction==12370 and hiring==1380 and supply_cost==1200 and cash==11050 and HospitalLedger.balance(world)==cash,
		"preset_items":seats==5 and not world.facts.facilities.has("chair_6") and world.facts.facilities.has("warm_trolley") and world.facts.facilities.has("floor_guidance_desk") and world.facts.floors.overrides["1"].paths.is_empty(),
		"current_staff_and_service_rates":wages==690 and indoor_cells==121 and service_stations==3 and is_equal_approx(operations,70.05) and is_equal_approx(expected_repairs,94.8) and maintenance==120,
		"expectation_budget_only":is_equal_approx(daily_budget,974.85) and buffer_days>11.334 and buffer_days<11.336,
		"read_only":world.freeze()==before}
	return {"ok":not checks.values().has(false),"checks":checks,"roster":counts,"construction":construction,"hiring":hiring,"supplies":supply_cost,"cash":cash,"wages_per_day":wages,"indoor_cells":indoor_cells,"service_stations":service_stations,"operations_per_day":operations,"worst_risk_expected_repairs_per_day":expected_repairs,"maintenance_budget_per_day":maintenance,"expected_daily_budget":daily_budget,"zero_income_expected_buffer_days":buffer_days,"survival_guarantee":false}
