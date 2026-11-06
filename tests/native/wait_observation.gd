extends SceneTree

const Before = preload("res://before.gd")
const After = preload("res://after.gd")
var checks: int = 0
var failed: bool = false

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(label)

func observe_pair(before: RefCounted, after: RefCounted, facts: Dictionary, expected: Array, label: String) -> void:
	for target: RefCounted in [before,after]:
		for waiter: Dictionary in target.waiters.values(): waiter.dirty = false
	var frozen: Dictionary = facts.duplicate(true)
	before.observe_reservations(facts)
	after.observe_reservations(facts)
	check(facts==frozen,label+": readonly input")
	for id: String in before.waiters:
		check(before.dirty(id)==after.dirty(id),label+": baseline "+id)
		check(after.dirty(id)==(id in expected),label+": expected "+id)

func semantics() -> void:
	var before: RefCounted = Before.new()
	var after: RefCounted = After.new()
	for target: RefCounted in [before,after]:
		for id: String in ["owner","floor1","floor2"]:
			var key: String = "reservation:r" if id=="owner" else "floor:"+id.trim_prefix("floor")
			target.remember(id,{key:{"kind":"test","value":[]}},1,[] as Array[Rect2])
		target.remember("near",{},1,[Rect2(0,0,2,2)] as Array[Rect2])
		target.remember("far",{},1,[Rect2(10,10,2,2)] as Array[Rect2])
		target.remember("other_floor",{},2,[Rect2(0,0,2,2)] as Array[Rect2])
	var r: Dictionary = {"floor_id":1,"kind":"facility","span":0,"actor_id":"a","staff_ids":["s"],"regions":[[0.5,0.5,1.0,1.0]]}
	var facts: Dictionary = {"r":r}
	observe_pair(before,after,facts,["owner","near"],"create")
	observe_pair(before,after,facts,[],"unchanged")
	r["unobserved"] = ["extra"]
	observe_pair(before,after,facts,[],"unobserved field")
	for entry: Array in [["actor_id","b"],["span",2],["staff_ids",["x","y"]]]:
		r[entry[0]] = entry[1]
		observe_pair(before,after,facts,["owner","near"],"field "+str(entry[0]))
	r.staff_ids.append("nested")
	observe_pair(before,after,facts,["owner","near"],"nested staff snapshot")
	r.regions[0][0] = 10.5
	r.regions[0][1] = 10.5
	observe_pair(before,after,facts,["owner","near","far"],"old and new regions")
	r["kind"] = "door"
	observe_pair(before,after,facts,["owner","floor1","far"],"door kind")
	r["floor_id"] = 2
	r["regions"] = [[0.5,0.5,1.0,1.0]]
	observe_pair(before,after,facts,["owner","floor1","floor2","far","other_floor"],"floor transition")
	facts.erase("r")
	observe_pair(before,after,facts,["owner","floor2","other_floor"],"delete")
	observe_pair(before,after,facts,[],"deleted unchanged")
	facts["r"] = {"floor_id":1}
	observe_pair(before,after,facts,["owner"],"optional defaults")
	facts.r.merge({"kind":"","span":-1,"actor_id":"","staff_ids":[],"regions":[]})
	observe_pair(before,after,facts,[],"explicit defaults")
	for target: RefCounted in [before,after]: target.remove("owner")
	facts.r.actor_id = "new"
	observe_pair(before,after,facts,[],"removed subscriber")
	for target: RefCounted in [before,after]: target.clear()
	check(before.waiters==after.waiters and after.waiters.is_empty(),"clear waiters")
	check(before._reservations==after._reservations and after._reservations.is_empty(),"clear snapshots")

func benchmark(iterations: int, rounds: int, mode: String) -> Array:
	var facts: Dictionary = {}
	for i: int in 160:
		facts[str(i)] = {"floor_id":i%4+1,"kind":"facility","span":i%3,"actor_id":"actor"+str(i),"staff_ids":["staff"+str(i)],"regions":[[1.0,2.0,2.0,2.0],[5.0,6.0,2.0,2.0]]}
	var before: RefCounted = Before.new()
	var after: RefCounted = After.new()
	for target: RefCounted in [before,after]: target.observe_reservations(facts)
	var initial: Dictionary = facts.duplicate(true)
	var windows: Array = []
	for round: int in rounds:
		for target: RefCounted in [before,after] if round%2==0 else [after,before]:
			facts = initial.duplicate(true)
			target.observe_reservations(facts)
			var started: int = Time.get_ticks_usec()
			for iteration: int in iterations:
				if mode=="changing": facts[str(iteration%160)].span = iteration
				target.observe_reservations(facts)
			windows.append({"round":round,"side":"before" if target==before else "after","elapsed_us":Time.get_ticks_usec()-started})
	return windows

func _initialize() -> void:
	semantics()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var iterations: int = int(args[0])
	var rounds: int = int(args[1])
	var result: Dictionary = {"passed":not failed,"assertions":checks,"reservations":160,"iterations":iterations,"rounds":rounds,"steady":benchmark(iterations,rounds,"steady"),"changing":benchmark(iterations,rounds,"changing"),"limitations":["Explicit conservative broadphase input adapter; not Boost integration", "Observation microbenchmark only; not whole-step performance", "No complete hospital world or STAFF-69 integration"]}
	print("WAIT_OBSERVATION_RESULT "+JSON.stringify(result))
	quit(1 if failed else 0)
