class_name ArrivalDayPlan
extends RefCounted

const F = preload("res://game/arrivals/exact_fraction.gd")
const SHIFT_TICKS: int = 6000
const WORD_RANGE: int = 4294967296

static func allocate_shifts(day: int, seed: String, count: int, capacities: Array) -> Array:
	var total: Dictionary = F.make()
	for capacity: Dictionary in capacities:
		total = F.add(total,capacity)
	var allocation: Array = [0,0,0]
	if total.n == "0" or count == 0:
		return allocation
	var order: Array = []
	var used: int = 0
	for shift: int in 3:
		var amount: Dictionary = F.div(F.mul(F.make(count),capacities[shift]),total)
		allocation[shift] = F.floor_value(amount)
		used += int(allocation[shift])
		order.append({"shift":shift,"remainder":F.sub(amount,F.make(allocation[shift])),
			"hash":hash32("arrival-load-shift-v1|%d|%s|%d" % [day,seed,shift])})
	order.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		var comparison: int = F.compare(a.remainder,b.remainder)
		return comparison > 0 if comparison != 0 else a.hash < b.hash if a.hash != b.hash else a.shift < b.shift)
	for index: int in count-used:
		allocation[int(order[index].shift)] += 1
	return allocation

static func slot_tick(plan: Dictionary, global_index: int) -> int:
	if global_index < 0 or global_index >= int(plan.opportunity_count):
		return -1
	var day: int = int(plan.day_index)
	var seed: String = str(plan.schedule_seed)
	if plan.schedule_algorithm == "arrival-slot-v1":
		return _window_tick(day,seed,global_index,int(plan.opportunity_count),WorldState.TICKS_PER_DAY,"arrival-slot-v1",-1)
	if plan.schedule_algorithm != "arrival-load-slot-v1":
		return -1
	var local: int = global_index
	for shift: int in 3:
		var count: int = int(plan.shift_opportunity_counts[shift])
		if local < count:
			return shift*SHIFT_TICKS+_window_tick(day,seed,local,count,SHIFT_TICKS,"arrival-load-slot-v1",shift)
		local -= count
	return -1

static func sample_count(world: WorldState, capacity: Dictionary, preset: Dictionary) -> int:
	if capacity.n == "0":
		return 0
	var deviation: int = int(preset.daily_variation_bp)
	var density: int = int(uniform_decimal(world,str(deviation*2+1)))-deviation
	var expected: Dictionary = F.mul(capacity,F.make(int(preset.target_load_bp)*(10000+density),100000000))
	var parts: Array = F.divmod(expected.n,expected.d)
	var result: int = int(parts[0])
	if parts[1] != "0" and F.compare_integer(uniform_decimal(world,expected.d),parts[1]) < 0:
		result += 1
	return result

static func draw_seed(world: WorldState) -> String:
	var generator: RandomNumberGenerator = _generator(world)
	var high: int = generator.randi()
	var low: int = generator.randi()
	world.facts.rng.arrival.state_decimal = str(generator.state)
	return F.add_integer(F.multiply_integer(str(high),str(WORD_RANGE)),str(low))

static func uniform_decimal(world: WorldState, bound: String) -> String:
	assert(F.valid_integer(bound) and bound != "0")
	if bound == "1":
		return "0"
	var range_size: String = str(WORD_RANGE)
	var words: int = 1
	while F.compare_integer(range_size,bound) < 0:
		range_size = F.multiply_integer(range_size,str(WORD_RANGE))
		words += 1
	var remainder: String = F.divmod(range_size,bound)[1]
	var limit: String = F.add_integer(range_size,F.negate_integer(remainder))
	var generator: RandomNumberGenerator = _generator(world)
	while true:
		var sample: String = "0"
		for index: int in words:
			sample = F.add_integer(F.multiply_integer(sample,str(WORD_RANGE)),str(generator.randi()))
		if F.compare_integer(sample,limit) < 0:
			world.facts.rng.arrival.state_decimal = str(generator.state)
			return F.divmod(sample,bound)[1]
	return "0"

static func count_range(capacity: Dictionary, preset: Dictionary) -> Array:
	var target: Dictionary = F.mul(capacity,F.make(preset.target_load_bp,10000))
	return [F.floor_value(F.mul(target,F.make(10000-int(preset.daily_variation_bp),10000))),
		F.ceil_value(F.mul(target,F.make(10000+int(preset.daily_variation_bp),10000)))]

static func validate(plan: Variant) -> String:
	if not plan is Dictionary:
		return "来客日计划必须是映射"
	if plan.is_empty():
		return ""
	for field: String in ["day_index","scale_numerator","opportunity_count","next_slot_index"]:
		if not _natural(plan.get(field)):
			return "来客日计划整数无效："+field
	if int(plan.day_index) < 1 or int(plan.next_slot_index) > int(plan.opportunity_count):
		return "来客日计划日期或游标无效"
	if not plan.get("preset") is String or not plan.get("shift_capacities") is Array or plan.shift_capacities.size() != 3:
		return "来客冻结档位或三班能力无效"
	for capacity: Variant in plan.shift_capacities:
		if not F.valid(capacity):
			return "来客冻结能力必须是约分非负整数分数"
	if not plan.get("schedule_algorithm") in ["arrival-load-slot-v1","arrival-slot-v1"]:
		return "未知来客时刻算法"
	if not plan.get("shift_opportunity_counts") is Array or plan.shift_opportunity_counts.size() != 3:
		return "来客三班机会数缺失"
	var total: int = 0
	for shift: int in 3:
		var amount: Variant = plan.shift_opportunity_counts[shift]
		if not _natural(amount):
			return "来客班次机会数无效"
		if plan.schedule_algorithm == "arrival-load-slot-v1" and plan.shift_capacities[shift].n == "0" and int(amount) != 0:
			return "零能力班不能拥有机会"
		total += int(amount)
	if total != int(plan.opportunity_count):
		return "来客班次机会数总和不符"
	if total == 0:
		if plan.get("schedule_seed") != null:
			return "零机会日不能有随机种子"
	elif not F.valid_integer(plan.get("schedule_seed")) or F.compare_integer(plan.schedule_seed,"18446744073709551615") > 0:
		return "来客日种子无效"
	return ""

static func hash32(key: String) -> int:
	var bytes: PackedByteArray = key.sha256_buffer()
	return (int(bytes[0]) << 24) | (int(bytes[1]) << 16) | (int(bytes[2]) << 8) | int(bytes[3])

static func _window_tick(day: int, seed: String, index: int, count: int, length: int, algorithm: String, shift: int) -> int:
	var left: int = index*length/count
	var right: int = (index+1)*length/count
	if right-left < 2:
		return left
	var low: int = (left*4+(right-left)+3)/4
	var high: int = (left*4+(right-left)*3)/4
	if low == high:
		return low
	var width: int = high-low+1
	var limit: int = WORD_RANGE-WORD_RANGE%width
	var nonce: int = 0
	while true:
		var key: String = "%s|%d|%s|%d|%d" % [algorithm,day,seed,index,nonce]
		if shift >= 0:
			key = "%s|%d|%s|%d|%d|%d" % [algorithm,day,seed,shift,index,nonce]
		var value: int = hash32(key)
		if value < limit:
			return low+value%width
		nonce += 1
	return -1

static func _generator(world: WorldState) -> RandomNumberGenerator:
	var generator: RandomNumberGenerator = RandomNumberGenerator.new()
	generator.seed = str(world.facts.rng.arrival.seed_decimal).to_int()
	generator.state = str(world.facts.rng.arrival.state_decimal).to_int()
	return generator

static func _natural(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and float(value) == floor(float(value))
