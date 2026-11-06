extends SceneTree
const Old = preload("res://baseline.gd")
const New = preload("res://current.gd")
var checks: int = 0
func require(value: bool) -> void:
	assert(value)
	checks += 1
func configure(service: RefCounted, count: int, old_count: int = 0, depth: int = 1) -> void:
	service._query_depth = depth
	var old: Dictionary = {}
	for i: int in range(old_count): old[str(i)] = {"distance":i}
	var incoming: Dictionary = {}
	for i: int in range(count): incoming[str(i)] = {"distance":-i-1}
	service._coverage_cache = {1:{"coverage":old},2:{"coverage":{"unchanged":42}}}
	service._query = {"edges":{1:{},99:{}},"coverage":{1:incoming,99:{"ignored":7}}}
func _initialize() -> void:
	var old = Old.new(); var current = New.new()
	for count: int in [0,1,127,128,129,256,640]:
		for before: int in [0,64,128]:
			for depth: int in [1,2]:
				configure(old,count,before,depth); configure(current,count,before,depth)
				old.end_query(); current.end_query()
				require(old._coverage_cache==current._coverage_cache)
				require(old._query==current._query)
				require(old._query_depth==current._query_depth)
				if depth==2:
					require(current._coverage_cache[1].coverage.size()==before)
					old.end_query(); current.end_query()
				var expected: Array = []
				var total: int = maxi(count,before)
				for i: int in range(maxi(0,total-128),total): expected.append(str(i))
				require(current._coverage_cache[1].coverage.keys()==expected)
				for key: String in expected:
					require(current._coverage_cache[1].coverage[key].distance==int(key) if int(key)<before else current._coverage_cache[1].coverage[key].distance==-int(key)-1)
				require(current._query.is_empty())
				require(current._coverage_cache[2].coverage=={"unchanged":42})
				require(not current._coverage_cache.has(99))
	var windows: Array = []
	for count: int in [128,129,256,640]:
		for round_index: int in range(3):
			for side: String in ["old","new","new","old"]:
				var service: RefCounted = old if side=="old" else current
				var elapsed: int = 0
				for iteration: int in range(300):
					configure(service,count,128)
					var start: int = Time.get_ticks_usec()
					service.end_query()
					elapsed += Time.get_ticks_usec()-start
				windows.append({"count":count,"side":side,"elapsed_us":elapsed})
	print(JSON.stringify({"checks":checks,"iterations_per_window":300,"windows":windows,"scope":"exact environment end_query; no full environment or whole-step claim"}))
	quit()
