extends RefCounted

const Structure = preload("res://game/building/room_structure.gd")

# Complete pre-optimization shape calculation. Point validation, floods and
# wall generation keep their unchanged implementations; sorting/proofs do not.
func reference_shape(draft: Dictionary) -> Dictionary:
	var actual: Array=[]
	if draft.has("cells"):
		if not draft.cells is Array or draft.cells.is_empty() or draft.cells.size()>9216: return BuildGeometry.failure("房间需要1至9216个实际内格")
		actual=draft.cells.duplicate(true)
	else:
		if not BuildGeometry.point(draft.get("origin")) or not BuildGeometry.point(draft.get("size"),true): return BuildGeometry.failure("房间原点或尺寸无效")
		if int(draft.size[0])>96 or int(draft.size[1])>96: return BuildGeometry.failure("房间超出96格院区")
		actual=BuildGeometry.cells(draft)
	var occupied: Dictionary={}
	var low: Vector2i=Vector2i(96,96)
	var high: Vector2i=Vector2i(-1,-1)
	for cell: Variant in actual:
		if not BuildGeometry.point(cell) or int(cell[0])<0 or int(cell[1])<0 or int(cell[0])>=96 or int(cell[1])>=96: return BuildGeometry.failure("房间内格超出本层96×96范围",[cell] if cell is Array else [])
		var position: Vector2i=Vector2i(int(cell[0]),int(cell[1]))
		if occupied.has(position): return BuildGeometry.failure("房间内格重复",[cell])
		occupied[position]=true
		low=low.min(position)
		high=high.max(position)
	var visited: Dictionary=BuildGeometry._flood(occupied,Vector2i(int(actual[0][0]),int(actual[0][1])),true,low,high)
	if visited.size()!=actual.size(): return BuildGeometry.failure("房间内格必须四邻连续")
	var outside: Dictionary=BuildGeometry._flood(occupied,low-Vector2i.ONE,false,low-Vector2i.ONE,high+Vector2i.ONE)
	for y: int in range(low.y,high.y+1):
		for x: int in range(low.x,high.x+1):
			if not occupied.has(Vector2i(x,y)) and not outside.has(Vector2i(x,y)): return BuildGeometry.failure("房间不能包含内部孔洞",[[x,y]])
	actual.sort_custom(func(a: Array,b: Array)->bool:return a[1]<b[1] or a[1]==b[1] and a[0]<b[0])
	return {"ok":true,"cells":actual,"origin":[low.x,low.y],"size":[high.x-low.x+1,high.y-low.y+1],"wall_edges":BuildGeometry.walls(occupied)}

func reference_component(start: Vector2i, plots: Dictionary, barriers: Dictionary, visited: Dictionary) -> Dictionary:
	var pending: Array[Vector2i]=[start]
	var cursor: int=0
	var points: Dictionary={start:true}
	var closed: bool=true
	visited[start]=true
	while cursor<pending.size():
		var point: Vector2i=pending[cursor]
		cursor+=1
		for direction: Vector2i in Structure.DIRS:
			var next: Vector2i=point+direction
			if barriers.has(Structure.edge_key(point,next)): continue
			if not Structure.owned(plots,next):
				closed=false
				continue
			if not points.has(next):
				points[next]=true
				visited[next]=true
				pending.append(next)
	var cells: Array=[]
	for point: Vector2i in pending: cells.append([point.x,point.y])
	cells.sort_custom(func(a: Array,b: Array)->bool:return a[1]<b[1] or a[1]==b[1] and a[0]<b[0])
	return {"cells":cells,"points":points,"closed":closed,"doors":[]}

func samples() -> Array:
	var ring: Array=[]
	for y: int in 3:
		for x: int in 3:
			if x!=1 or y!=1: ring.append([x,y])
	var floats: Array=[]
	for y: int in range(94,96):
		for x: int in range(93,96): floats.append([float(x),float(y)])
	floats.reverse()
	var oversized: Array=BuildGeometry.cells({"origin":[0,0],"size":[96,96]})
	oversized.append([0,0])
	return [
		{"id":"full96","draft":{"origin":[0,0],"size":[96,96]},"valid":true},
		{"id":"large85","draft":{"origin":[0,0],"size":[85,95]},"valid":true},
		{"id":"last_column","draft":{"origin":[95,0],"size":[1,96]},"valid":true},
		{"id":"last_row","draft":{"origin":[0,95],"size":[96,1]},"valid":true},
		{"id":"corner","draft":{"cells":[[95,95]]},"valid":true},
		{"id":"whole_float_types","draft":{"cells":floats},"valid":true},
		{"id":"signed_zero","draft":{"cells":[[-0.0,0.0]]},"valid":true},
		{"id":"irregular_L","draft":{"cells":[[1,0],[0,1],[0,0]]},"valid":true},
		{"id":"irregular_long","draft":{"cells":[[94,0],[95,0],[95,1],[95,2]]},"valid":true},
		{"id":"empty","draft":{"cells":[]},"valid":false},
		{"id":"too_many","draft":{"cells":oversized},"valid":false},
		{"id":"duplicates_mask_missing_cell","draft":{"cells":[[0,0],[1,0],[1,0],[0,1]]},"valid":false},
		{"id":"integer_float_duplicate","draft":{"cells":[[0,0],[-0.0,0.0]]},"valid":false},
		{"id":"disconnected","draft":{"cells":[[0,0],[1,1]]},"valid":false},
		{"id":"hole","draft":{"cells":ring},"valid":false},
		{"id":"negative","draft":{"cells":[[-1,0]]},"valid":false},
		{"id":"outside96","draft":{"origin":[95,95],"size":[2,2]},"valid":false},
		{"id":"fractional_cell","draft":{"cells":[[0.5,1]]},"valid":false},
		{"id":"fractional_origin","draft":{"origin":[0.5,0],"size":[2,2]},"valid":false},
		{"id":"nonfinite_cell","draft":{"cells":[[NAN,0]]},"valid":false},
		{"id":"infinite_extent","draft":{"origin":[0,0],"size":[INF,1]},"valid":false},
		{"id":"bad_point_type","draft":{"cells":["0,0"]},"valid":false},
		{"id":"bad_point_length","draft":{"cells":[[0,0,0]]},"valid":false},
		{"id":"zero_extent","draft":{"origin":[0,0],"size":[0,1]},"valid":false},
		{"id":"oversized_extent","draft":{"origin":[0,0],"size":[97,1]},"valid":false}
	]

func run_case() -> Dictionary:
	var checks: Dictionary={}
	var first_difference: Dictionary={}
	var observations: Array=[]
	for sample: Dictionary in samples():
		var before: PackedByteArray=var_to_bytes(sample.draft)
		var actual: Dictionary=BuildGeometry.shape(sample.draft)
		var expected: Dictionary=reference_shape(sample.draft)
		var equal: bool=var_to_bytes(actual)==var_to_bytes(expected)
		checks[sample.id]=equal and bool(actual.ok)==bool(sample.valid) and var_to_bytes(sample.draft)==before
		if not equal and first_difference.is_empty(): first_difference={"shape":sample.id,"actual_ok":actual.ok,"expected_ok":expected.ok,"actual_reason":actual.get("reason",""),"expected_reason":expected.get("reason","")}
		if sample.id=="whole_float_types": checks.original_coordinate_types_preserved=actual.ok and typeof(actual.cells[0][0])==TYPE_FLOAT and typeof(actual.cells[0][1])==TYPE_FLOAT
		if sample.id=="duplicates_mask_missing_cell": checks.unique_before_rectangle_proof=not actual.ok and actual.reason=="房间内格重复"
		if sample.id=="hole": checks.hole_rejected_at_actual_cell=not actual.ok and actual.reason=="房间不能包含内部孔洞" and actual.blocked_cells==[[1,1]]
		if sample.id=="disconnected": checks.four_neighbor_connectivity_kept=not actual.ok and actual.reason=="房间内格必须四邻连续"
		if sample.id=="full96": checks.full_perimeter_literal=actual.ok and actual.cells.size()==9216 and actual.wall_edges==[{"axis":"x","line":0,"low":0,"high":96},{"axis":"x","line":96,"low":0,"high":96},{"axis":"y","line":0,"low":0,"high":96},{"axis":"y","line":96,"low":0,"high":96}]
		observations.append({"id":sample.id,"ok":actual.ok,"complete_output_equal":equal,"reason":actual.get("reason","")})
	var owned_input: Dictionary={"cells":[[1,0],[0,0]]}
	var owned_before: PackedByteArray=var_to_bytes(owned_input)
	var owned: Dictionary=BuildGeometry.shape(owned_input)
	owned.cells[0][0]=95
	checks.result_cells_do_not_alias_input=var_to_bytes(owned_input)==owned_before
	var plots: Dictionary={}
	for y: int in 3:
		for x: int in 3: plots[Vector2i(x,y)]=true
	var component_cases: Array=[
		{"id":"open_full_floor","origin":[0,0],"size":[0,0],"start":Vector2i(0,0),"cells":9216,"closed":false},
		{"id":"closed85","origin":[0,0],"size":[85,95],"start":Vector2i(0,0),"cells":8075,"closed":true},
		{"id":"open85","origin":[0,0],"size":[85,95],"start":Vector2i(85,0),"cells":1141,"closed":false},
		{"id":"closed96","origin":[0,0],"size":[96,95],"start":Vector2i(0,0),"cells":9120,"closed":true},
		{"id":"open_last_row","origin":[0,0],"size":[96,95],"start":Vector2i(0,95),"cells":96,"closed":false},
		{"id":"closed_auxiliary","origin":[16,82],"size":[8,8],"start":Vector2i(16,82),"cells":64,"closed":true},
		{"id":"open_auxiliary","origin":[16,82],"size":[8,8],"start":Vector2i(0,0),"cells":9152,"closed":false},
		{"id":"closed_narrow","origin":[95,0],"size":[1,96],"start":Vector2i(95,0),"cells":96,"closed":true}
	]
	for sample: Dictionary in component_cases:
		var barriers: Dictionary=Structure.units(BuildGeometry.room_walls({"origin":sample.origin,"size":sample.size})) if int(sample.size[0])>0 else {}
		var before: PackedByteArray=var_to_bytes([plots,barriers])
		var actual_visited: Dictionary={Vector2i(40,40):true}
		var original_visited: Dictionary=actual_visited.duplicate()
		var actual: Dictionary=Structure._component(sample.start,plots,barriers,actual_visited)
		var expected: Dictionary=reference_component(sample.start,plots,barriers,original_visited)
		var equal: bool=var_to_bytes(actual)==var_to_bytes(expected) and var_to_bytes(actual_visited)==var_to_bytes(original_visited)
		checks[sample.id]=equal and actual.cells.size()==sample.cells and actual.closed==sample.closed and var_to_bytes([plots,barriers])==before
		if not equal and first_difference.is_empty(): first_difference={"component":sample.id,"actual_cells":actual.cells.size(),"expected_cells":expected.cells.size(),"actual_closed":actual.closed,"expected_closed":expected.closed}
	return {"checks":checks,"shape_cases":observations,"component_cases":component_cases.size(),"first_difference":first_difference}
