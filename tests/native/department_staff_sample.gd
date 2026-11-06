extends SceneTree
const Before = preload("res://baseline.gd")
const After = preload("res://current.gd")
const World = preload("res://world.gd")

func make_world(count: int):
	var world = World.new()
	for i in count:
		var staff: Dictionary = {"energy":[0.0,35.0,35.01,100.0][i%4]}
		if i%3!=0: staff.on_shift = i%2==0
		if i%5!=0: staff.life_task = {"phase":["rest","sleep","offsite","working"][i%4]}
		world.facts.staff[str(i)] = staff
	return world

func expected(facts: Dictionary, tick: int) -> void:
	var day: String = str(floori(float(tick)/18000.0))
	for id: String in facts.staff:
		if not facts.departments.staff_days.has(day): facts.departments.staff_days[day] = {}
		var data: Dictionary = facts.departments.staff_days[day]
		if not data.has(id): data[id] = {"energy_total":0.0,"ticks":0,"rest_ticks":0,"required_rest_ticks":0}
		var staff: Dictionary = facts.staff[id]
		data[id].energy_total += float(staff.energy)
		data[id].ticks += 1
		var phase: String = str(staff.get("life_task",{}).get("phase",""))
		if phase=="rest" or phase=="sleep" or phase=="offsite": data[id].rest_ticks += 1
		if staff.get("on_shift",false)==false or float(staff.energy)<=35.0: data[id].required_rest_ticks += 1

func _initialize() -> void:
	var before = Before.new()
	var after = After.new()
	var checks: int = 0
	for count: int in [0,1,4,32,128]:
		for preexisting: bool in [false,true]:
			var a = make_world(count)
			if preexisting:
				a.facts.departments.staff_days = {"0":{"0":{"energy_total":13.5,"ticks":7,"rest_ticks":2,"required_rest_ticks":3}},"99":{"retired":{"energy_total":7.0,"ticks":1,"rest_ticks":0,"required_rest_ticks":0}}}
			var b = make_world(count)
			b.facts = a.facts.duplicate(true)
			var want: Dictionary = a.facts.duplicate(true)
			var staff_before: Dictionary = a.facts.staff.duplicate(true)
			for tick: int in [0,1,17999,18000,18000,18001,35999,36000]:
				a.sim_tick=tick
				b.sim_tick=tick
				expected(want,tick)
				var calls_a: int = before.ensure_calls
				var calls_b: int = after.ensure_calls
				before.sample(a)
				after.sample(b)
				assert(a.facts==want and b.facts==want)
				assert(a.facts.staff==staff_before and b.facts.staff==staff_before)
				assert(before.ensure_calls==calls_a+1 and after.ensure_calls==calls_b+1)
				assert(a.ids_calls==b.ids_calls)
				checks += 1
	var windows: Array = []
	for count: int in [0,1,32,128]:
		for warm in 100:
			before.sample(make_world(count))
			after.sample(make_world(count))
		var repetitions: int = 10000 if count<2 else 1000
		for cycle in 3:
			for old: bool in [true,false,false,true]:
				var world = make_world(count)
				var object = before if old else after
				var start: int = Time.get_ticks_usec()
				for rep in repetitions: object.sample(world)
				windows.append({"staff":count,"calls":repetitions,"old":old,"elapsed_us":Time.get_ticks_usec()-start})
				for id: String in world.facts.staff: assert(world.facts.departments.staff_days["0"][id].ticks==repetitions)
	print(JSON.stringify({"checks":checks,"windows":windows,"scope":"real sample function; no patients/environment; explicit staff/day input adapter; not full department or game"}))
	quit()
