extends SceneTree

const Before = preload("res://before.gd")
const After = preload("res://after.gd")
const Index = preload("res://body.gd")
var checks: int = 0
var failed: bool = false

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(label)

func observe_pair(before: RefCounted, after: RefCounted, index: RefCounted, expected: Array, label: String) -> void:
	for target: RefCounted in [before,after]:
		for waiter: Dictionary in target.waiters.values(): waiter.dirty = false
	var input: Dictionary = {}
	for id: String in index._records:
		input[id] = [index._records[id].floor_id,index._records[id].rect]
	before.observe_actors(index)
	after.observe_actors(index)
	for id: String in before.waiters:
		check(before.dirty(id)==after.dirty(id),label+": baseline "+id)
		check(after.dirty(id)==(id in expected),label+": expected "+id)
	for id: String in input:
		check(input[id]==[index._records[id].floor_id,index._records[id].rect],label+": input readonly "+id)

func semantics() -> void:
	var before: RefCounted = Before.new()
	var after: RefCounted = After.new()
	var index: RefCounted = Index.new()
	for target: RefCounted in [before,after]:
		target.remember("owner",{"actor:a":{"kind":"test","value":[]}},1,[] as Array[Rect2])
		target.remember("near",{},1,[Rect2(0,0,2,2)] as Array[Rect2])
		target.remember("far",{},1,[Rect2(10,10,2,2)] as Array[Rect2])
		target.remember("other_floor",{},2,[Rect2(0,0,2,2)] as Array[Rect2])
	observe_pair(before,after,index,[],"initial empty")
	index.update("a",1,Rect2(0.5,0.5,1,1))
	observe_pair(before,after,index,["owner","near"],"create")
	observe_pair(before,after,index,[],"unchanged")
	index.update("a",1,Rect2(0.5,0.5,1,1))
	observe_pair(before,after,index,[],"same rectangle update")
	index.update("a",1,Rect2(10.5,10.5,1,1))
	observe_pair(before,after,index,["owner","near","far"],"move old and new")
	index.update("a",2,Rect2(0.5,0.5,1,1))
	observe_pair(before,after,index,["owner","far","other_floor"],"floor transition")
	index.remove("a")
	observe_pair(before,after,index,["owner","other_floor"],"delete")
	observe_pair(before,after,index,[],"deleted unchanged")
	index.update("a",1,Rect2(2,0,1,1))
	observe_pair(before,after,index,["owner"],"edge contact excluded")
	index.update("b",1,Rect2(0.5,0.5,1,1))
	observe_pair(before,after,index,["near"],"third party creates opportunity dependency")
	index.remove("b")
	observe_pair(before,after,index,["near"],"third party removal")
	for target: RefCounted in [before,after]: target.remove("owner")
	index.update("a",1,Rect2(20,20,1,1))
	observe_pair(before,after,index,[],"removed subscriber")
	for target: RefCounted in [before,after]: target.clear()
	check(before.waiters.is_empty() and after.waiters.is_empty(),"clear waiters")
	check(before._actors.is_empty() and after._actors.is_empty(),"clear snapshots")
	observe_pair(before,after,index,[],"observe after clear")
	for target: RefCounted in [before,after]:
		target.remember("fresh",{},1,[Rect2(20,20,2,2)] as Array[Rect2])
	observe_pair(before,after,index,[],"unchanged after resubscription")
	index.remove("a")
	observe_pair(before,after,index,["fresh"],"remove after resubscription")

func benchmark(iterations: int, rounds: int, mode: String) -> Array:
	var before: RefCounted = Before.new()
	var after: RefCounted = After.new()
	var index: RefCounted = Index.new()
	var windows: Array = []
	for round: int in rounds:
		for target: RefCounted in [before,after] if round%2==0 else [after,before]:
			target.clear()
			index.clear()
			for i: int in 160: index.update(str(i),i%4+1,Rect2(i,0,1,1))
			# Keep actual reverse subscribers; broadphase is the explicit adapter.
			for i: int in 16:
				target.remember("w"+str(i),{"actor:"+str(i):{"kind":"test","value":[]}},i%4+1,[Rect2(i,0,2,2)] as Array[Rect2])
			target.observe_actors(index)
			var started: int = Time.get_ticks_usec()
			for iteration: int in iterations:
				if mode=="changing": index.update(str(iteration%160),iteration%4+1,Rect2(iteration,1,1,1))
				target.observe_actors(index)
			windows.append({"round":round,"side":"before" if target==before else "after","elapsed_us":Time.get_ticks_usec()-started})
	return windows

func _initialize() -> void:
	semantics()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var iterations: int = int(args[0])
	var rounds: int = int(args[1])
	var result: Dictionary = {"passed":not failed,"assertions":checks,"actors":160,"waiters":16,"iterations":iterations,"rounds":rounds,"steady":benchmark(iterations,rounds,"steady"),"changing":benchmark(iterations,rounds,"changing"),"limitations":["Explicit conservative broadphase input adapter; not Boost integration", "Actor observation microbenchmark only; not whole-step performance", "No complete hospital world or STAFF-69 integration"]}
	print("ACTOR_OBSERVATION_RESULT "+JSON.stringify(result))
	quit(1 if failed else 0)
