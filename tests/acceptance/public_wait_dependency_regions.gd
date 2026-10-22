extends RefCounted

func run_case() -> Dictionary:
	var index: BodyIndex = BodyIndex.new()
	var records: Dictionary = {
		"first":{"floor":1,"rect":Rect2(10,10,1,1)},
		"edge":{"floor":1,"rect":Rect2(11,10,1,1)},
		"gap":{"floor":1,"rect":Rect2(14,10,1,1)},
		"last":{"floor":1,"rect":Rect2(18,10,1,1)},
		"fraction":{"floor":1,"rect":Rect2(10.75,12.25,0.5,0.5)},
		"upper":{"floor":10000,"rect":Rect2(10,10,1,1)}
	}
	for id: String in records: index.update(id,int(records[id].floor),records[id].rect)
	var cases: Array = [
		{"name":"empty","floor":1,"regions":[],"ignored":[]},
		{"name":"overlap","floor":1,"regions":[Rect2(10,10,1,1),Rect2(10,10,1,1),Rect2(10.25,10.25,0.5,0.5)],"ignored":[]},
		{"name":"touch_then_overlap","floor":1,"regions":[Rect2(10,10,1,1),Rect2(11,10,1,1)],"ignored":[]},
		{"name":"disjoint_gap","floor":1,"regions":[Rect2(10,10,1,1),Rect2(18,10,1,1)],"ignored":[]},
		{"name":"ignored_group","floor":1,"regions":[Rect2(10,10,2,1),Rect2(18,10,1,1)],"ignored":["first","last"]},
		{"name":"fractional_touch","floor":1,"regions":[Rect2(10.5,12,0.25,1)],"ignored":[]},
		{"name":"fractional_overlap","floor":1,"regions":[Rect2(10.74,12,0.25,1)],"ignored":[]},
		{"name":"zero_width","floor":1,"regions":[Rect2(10.5,10,0,1)],"ignored":[]},
		{"name":"zero_height","floor":1,"regions":[Rect2(10,10.5,1,0)],"ignored":[]},
		{"name":"high_floor","floor":10000,"regions":[Rect2(10,10,1,1)],"ignored":[]},
		{"name":"empty_floor","floor":20000,"regions":[Rect2(10,10,1,1)],"ignored":[]}
	]
	var rows: Array = []
	for item: Dictionary in cases:
		var regions: Array[Rect2] = []
		regions.assign(item.regions)
		# Full record enumeration uses the engine's exact geometry, independent
		# of the native tree, its broadphase candidates and batch implementation.
		var expected: Array[String] = []
		for id: String in records:
			if int(records[id].floor)!=int(item.floor) or id in item.ignored: continue
			for rectangle: Rect2 in regions:
				if rectangle.intersects(records[id].rect,false):
					expected.append(id)
					break
		expected.sort()
		var actual: Array[String] = index.candidates_in_regions(int(item.floor),regions,item.ignored)
		rows.append({"boundary":item.name,"expected":expected,"actual":actual,"ok":actual==expected})
	var unicode_ids: Array[String] = ["Z","a","e\u0301","é","中","😀"]
	for id: String in unicode_ids: index.update(id,3,Rect2(30,30,1,1))
	unicode_ids.sort()
	var unicode_order: bool = index.candidates_in_regions(3,[Rect2(30,30,1,1),Rect2(30,30,1,1)])==unicode_ids
	index.begin_boundary({"first":true,"last":true})
	index.update("first",1,Rect2(10,10,1,1))
	var boundary: bool = index.candidates_in_regions(1,[Rect2(10,10,10,1)])==["first"]
	index.expire_boundary()
	boundary = boundary and index.candidates_in_regions(1,[Rect2(10,10,10,1)]).is_empty()
	index.update("first",10000,Rect2(10,10,1,1))
	var moved: bool = index.candidates_in_regions(1,[Rect2(10,10,1,1)]).is_empty() and index.candidates_in_regions(10000,[Rect2(10,10,1,1)])==["first"]
	index.remove("first")
	var removed: bool = index.candidates_in_regions(10000,[Rect2(10,10,1,1)]).is_empty()
	var native: PlatformSpatialIndex = PlatformSpatialIndex.new()
	native.update("seed",1,[4,4,2,2])
	var invalid: Array = [[17],[[1,2,3]],[["1",2,3,4]],[[true,2,3,4]],[[NAN,2,3,4]],[[INF,2,3,4]],[[1,2,-1,4]],[[1.7e308,2,1.7e308,4]]]
	var rejected: bool = true
	for input: Array in invalid:
		for floor_id: int in [1,20000]: rejected = rejected and native.query_many(floor_id,input).has("error")
	var readonly_failure: bool = native.query_many(1,[[4,4,2,2]]).ids==["seed"] and native.query_many(1,[]).ids.is_empty()
	return {"ok":rows.all(func(row: Dictionary)->bool:return row.ok) and unicode_order and boundary and moved and removed and rejected and readonly_failure,"geometry":rows,"unicode_ids_preserved_and_engine_sorted":unicode_order,"boundary_lifetime":boundary,"floor_change":moved,"removed":removed,"malformed_inputs_rejected_atomically":rejected,"valid_query_after_failure":readonly_failure}
