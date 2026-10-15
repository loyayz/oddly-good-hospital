extends SceneTree

const F = preload("res://game/arrivals/exact_fraction.gd")
const Solver = preload("res://game/arrivals/capacity_solver.gd")
const Plan = preload("res://game/arrivals/day_plan.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_check("arbitrary_width_integer_product",F.multiply_integer("18446744073709551615","10000000000") == "184467440737095516150000000000")
	_check("arbitrary_width_division",F.divmod("184467440737095516150000000000","18446744073709551615") == ["10000000000","0"])
	_check("reduced_fraction_addition",F.add(F.make(1,3),F.make(1,6)) == F.make(1,2))
	_check("signed_fraction",F.sub(F.make(1,4),F.make(3,4)) == F.make(-1,2))
	var cases: Array = [{"probability":F.make(1),"bundles":[{"resources":{"gp":120,"terminal":F.make(324),"doctor":324}}]}]
	var single: Dictionary = Solver.solve(cases,{"gp":18000,"terminal":18000,"doctor":18000})
	_check("source_d09_reference_clock",single.capacity == F.make(500,9))
	var two: Dictionary = Solver.solve([{"probability":F.make(1),"bundles":[
		{"resources":{"gp":120,"terminal_a":324,"doctor_a":324}},
		{"resources":{"gp":120,"terminal_b":324,"doctor_b":324}}]}],
		{"gp":18000,"terminal_a":18000,"doctor_a":18000,"terminal_b":18000,"doctor_b":18000})
	_check("independent_terminal_improves_actual_work_capacity",two.capacity == F.make(1000,9))
	var shared: Dictionary = Solver.solve([{"probability":F.make(1),"bundles":[
		{"resources":{"gp":120,"terminal_a":324,"same_doctor":324}},
		{"resources":{"gp":120,"terminal_b":324,"same_doctor":324}}]}],
		{"gp":18000,"terminal_a":18000,"terminal_b":18000,"same_doctor":18000})
	_check("shared_operator_has_one_clock",shared.capacity == F.make(500,9))
	var mixed: Dictionary = Solver.solve([
		{"probability":F.make(3,4),"bundles":[{"resources":{"gp":100,"shared":200}}]},
		{"probability":F.make(1,4),"bundles":[{"resources":{"gp":100,"shared":600}}]}],{"gp":6000,"shared":6000})
	_check("case_proportions_constrain_full_solution",mixed.capacity == F.make(20))
	var missing: Dictionary = Solver.solve([
		{"probability":F.make(3,4),"bundles":[{"resources":{"gp":100}}]},
		{"probability":F.make(1,4),"bundles":[]}],{"gp":6000})
	_check("unready_case_is_not_assumed_served",missing.capacity == F.make())
	var day: Dictionary = {"day_index":1,"preset":"normal","scale_numerator":3,"shift_capacities":[F.make(1),F.make(1),F.make(1)],
		"opportunity_count":8,"next_slot_index":0,"schedule_seed":"321","schedule_algorithm":"arrival-load-slot-v1"}
	day.shift_opportunity_counts = Plan.allocate_shifts(1,"321",8,day.shift_capacities)
	_check("source_shift_tie_vector",day.shift_opportunity_counts == [3,2,3])
	var slots: Array = []
	for index: int in 8:
		slots.append(Plan.slot_tick(day,index))
	_check("source_day_schedule_vector",slots == [1156,2815,5438,8035,11156,12853,15397,16553])
	_check("valid_frozen_plan",Plan.validate(day).is_empty())
	day.schedule_algorithm = "arrival-slot-v1"
	slots.clear()
	for index: int in 8:
		slots.append(Plan.slot_tick(day,index))
	_check("legacy_schedule_vector",slots == [939,3797,5823,7318,9850,12430,14889,16580])
	day.schedule_algorithm = "arrival-load-slot-v1"
	day.shift_capacities = [F.make(1),F.make(),F.make(1)]
	day.shift_opportunity_counts = Plan.allocate_shifts(1,"321",8,day.shift_capacities)
	_check("zero_capacity_shift_has_no_opportunities",day.shift_opportunity_counts == [4,0,4])
	_check("source_reference_count_range",Plan.count_range(F.make(500,9),{"target_load_bp":9000,"daily_variation_bp":2500}) == [37,63])
	print(JSON.stringify({"stage":24,"suite":"arrival_math","failures":failures,"passed":failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)

func _check(label: String, passed: bool) -> void:
	if not passed:
		failures.append(label)
