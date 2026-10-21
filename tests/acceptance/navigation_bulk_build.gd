extends RefCounted

const ColdGraph = preload("res://tests/acceptance/navigation_cold_graph.gd")

# Frozen pre-bucket-borrowing predicate. Every wall/door cut and its original
# failure ordering remains explicit here rather than sharing the new helper.
class OriginalClearance extends RouteClearance:
	func _wall_reason(rect: Rect2) -> String:
		var walls: Array = _walls
		if _indexed_static:
			walls = []
			for line: int in range(floori(rect.position.y)+1,ceili(rect.end.y)):
				walls.append_array(_horizontal_walls.get(line,[]))
			for line: int in range(floori(rect.position.x)+1,ceili(rect.end.x)):
				walls.append_array(_vertical_walls.get(line,[]))
		for wall: Dictionary in walls:
			var low: float = maxf(rect.position.x if wall.axis=="x" else rect.position.y,float(wall.low))
			var high: float = minf(rect.end.x if wall.axis=="x" else rect.end.y,float(wall.high))
			var before: float = rect.position.y if wall.axis=="x" else rect.position.x
			var after: float = rect.end.y if wall.axis=="x" else rect.end.x
			if low>=high or before>=float(wall.line) or after<=float(wall.line): continue
			var opening: bool = false
			for door: Dictionary in _doors:
				if door.room_id!=wall.room_id or door.axis!=wall.axis or not door.ok: continue
				var line: float = door.opening.position.y if wall.axis=="x" else door.opening.position.x
				var a: float = door.opening.position.x if wall.axis=="x" else door.opening.position.y
				var b: float = door.opening.end.x if wall.axis=="x" else door.opening.end.y
				if line==float(wall.line) and a<=low and b>=high:
					opening = true
					break
			if not opening: return "房间墙边阻挡真实身体"
		return ""

# The complete pre-bulk engine assembly remains an independent reference.
# It does not consume the optimized builder's prepared masks or adapter.
class ScriptBuild extends FloorNavigation:
	func _build() -> void:
		var ids: Array[int] = []
		for plot: Vector2i in geometry._plots:
			for y: int in range(plot.y*32,(plot.y+1)*32):
				for x: int in range(plot.x*32,(plot.x+1)*32): ids.append(y*SIDE+x)
		ids.sort()
		reserve_space(ids.size())
		for id: int in ids:
			var cell: Vector2i = _cell(id)
			add_point(id,Vector2(cell))
			_enabled[id] = int(geometry.reason(cell).is_empty())
			if _enabled[id]==0: set_point_disabled(id,true)
		for id: int in ids:
			if _enabled[id]==0: continue
			var cell: Vector2i = _cell(id)
			for direction: int in range(2,4):
				var next: Vector2i = cell+NEIGHBOURS[direction]
				if _inside(next) and _enabled[_id(next)]!=0 and geometry.edge_reason(cell,next).is_empty():
					var other: int = _id(next)
					connect_points(id,other,true)
					_edges[id] |= 1<<direction
					_edges[other] |= 1<<(3-direction)

func run_case(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var built: CommandResult = suite._command(sim,"build_room",suite._room("bulk_graph_room",[42,68],[14,10]))
	if not built.accepted:
		sim.dispose()
		return {"ok":false,"room":built.to_record()}
	suite._add_actor(sim,"bulk_small","S49",[35,82])
	suite._add_actor(sim,"bulk_wide","S59",[35.25,84.5])
	var validation: String = sim.world.validate(suite.content)
	var before: Dictionary = sim.world.freeze()
	var rows: Array = []
	var ok: bool = validation.is_empty()
	var oracle: RefCounted = ColdGraph.new()
	for mode: String in ["small","wide","fractional_group"]:
		var actor: Dictionary = sim.world.facts.actors.bulk_wide if mode=="wide" else sim.world.facts.actors.bulk_small
		var members: Array = ["bulk_small","bulk_wide"] if mode=="fractional_group" else []
		var offsets: Dictionary = {"bulk_small":[0,0],"bulk_wide":[0.25,2.5]} if not members.is_empty() else {}
		var geometry: RouteClearance = RouteClearance.new(sim.space,sim.world,actor,1,members,offsets,false)
		var actual: FloorNavigation = FloorNavigation.new(geometry)
		var original: RouteClearance = _original_clearance(sim.space,sim.world,actor,members,offsets,false,geometry.source)
		var reference: ScriptBuild = ScriptBuild.new(original)
		var comparison: Dictionary = oracle._compare(actual,{"graph":reference,"enabled":reference._enabled,"edges":reference._edges})
		var query: RouteClearance = RouteClearance.new(sim.space,sim.world,actor,1,members,offsets,true,geometry.source)
		var reference_query: RouteClearance = _original_clearance(sim.space,sim.world,actor,members,offsets,true,geometry.source)
		var predicates: Dictionary = _wall_predicates(geometry,original,query,reference_query)
		var paths: Array = []
		var exact_paths: bool = true
		for ends: Array in [[Vector2i(35,82),Vector2i(59,82)],[Vector2i(35,82),Vector2i(45,72)],[Vector2i(35,82),Vector2i(0,0)],[Vector2i(-1,82),Vector2i(59,82)]]:
			for cost_only: bool in [false,true]:
				for partial: bool in [false,true]:
					var observed: Dictionary = actual.find_path(ends[0],ends[1],query,Callable(),partial,[],[],false,cost_only)
					var expected: Dictionary = reference.find_path(ends[0],ends[1],reference_query,Callable(),partial,[],[],false,cost_only)
					var exact: bool = observed==expected
					exact_paths = exact_paths and exact
					paths.append({"from":ends[0],"to":ends[1],"cost_only":cost_only,"partial":partial,"full_result_equal":exact,"difference":{} if exact else {"actual":observed,"expected":expected}})
		ok = ok and comparison.ok and exact_paths and predicates.ok
		rows.append({"mode":mode,"complete_graph":comparison,"wall_predicates":predicates,"all_full_path_and_cost_results":exact_paths,"paths":paths})
	var errors: Dictionary = _invalid_inputs()
	var readonly: bool = before==sim.world.freeze()
	var result: Dictionary = {"ok":ok and errors.ok and readonly,"validation":validation,"all_cells_points_masks_order_and_paths":rows,"atomic_invalid_input":errors,"world_and_rng_unchanged":readonly}
	sim.dispose()
	return result

func _original_clearance(space: HospitalSpace, world: WorldState, actor: Dictionary, members: Array, offsets: Dictionary, reservations: bool, source: Dictionary, geometry: RouteClearance = null) -> RouteClearance:
	var result: RouteClearance = OriginalClearance.new(space,world,actor,1,members,offsets,reservations,source,geometry)
	# The base constructor uses its ordinary RouteClearance class for children.
	# Replace each test reference child with the frozen predicate as well.
	result._members.clear()
	for id: String in members:
		if id==actor.id: continue
		var offset: Array = offsets[id]
		result._members.append({"query":OriginalClearance.new(space,world,world.facts.actors[id],1,[],{},reservations,source),"offset":Vector2(float(offset[0]),float(offset[1]))})
	return result

func _wall_predicates(actual: RouteClearance, original: RouteClearance, query: RouteClearance, reference_query: RouteClearance) -> Dictionary:
	var checked: int = 0
	for indexed: bool in [true,false]:
		var left: RouteClearance = actual if indexed else query
		var right: RouteClearance = original if indexed else reference_query
		# Cross every original room wall and door with integer, wide and fractional
		# bodies; blocked endpoints also exercise reasons omitted by graph edges.
		for y: int in range(66,80):
			for x: int in range(40,58):
				for offset: Vector2 in [Vector2.ZERO,Vector2(0.25,0.5)]:
					var origin: Vector2 = Vector2(x,y)+offset
					var rect: Rect2 = Rect2(origin,Vector2.ONE*left._size)
					checked += 1
					if left._wall_reason(rect)!=right._wall_reason(rect): return {"ok":false,"indexed":indexed,"rect":rect,"kind":"node"}
					for direction: Vector2i in FloorNavigation.NEIGHBOURS:
						var sweep: Rect2 = rect.merge(Rect2(origin+Vector2(direction),rect.size))
						checked += 1
						if left._wall_reason(sweep)!=right._wall_reason(sweep): return {"ok":false,"indexed":indexed,"rect":sweep,"kind":"edge"}
	return {"ok":true,"exact_original_node_and_sweep_reasons":checked}

func _invalid_inputs() -> Dictionary:
	var present: PackedByteArray = PackedByteArray()
	var enabled: PackedByteArray = PackedByteArray()
	var edges: PackedByteArray = PackedByteArray()
	present.resize(9216)
	enabled.resize(9216)
	edges.resize(9216)
	present[96] = 1
	present[97] = 1
	enabled[96] = 1
	enabled[97] = 1
	var observations: Array = []
	var passed: bool = true
	for mode: String in ["short_mask","asymmetric","disabled_edge","row_wrap","wrong_class","nonempty"]:
		var graph: AStar2D = AStar2D.new()
		var p: PackedByteArray = present.duplicate()
		var e: PackedByteArray = enabled.duplicate()
		var links: PackedByteArray = edges.duplicate()
		if mode=="short_mask": p.resize(9215)
		if mode=="asymmetric": links[96] = 4
		if mode=="disabled_edge":
			e[96] = 0
			links[96] = 4
			links[97] = 2
		if mode=="row_wrap":
			p[95] = 1
			e[95] = 1
			links[95] = 4
			links[96] = 2
		if mode=="nonempty": graph.add_point(91,Vector2(7,9))
		var original: PackedInt64Array = graph.get_point_ids()
		var result: Dictionary = PlatformArrivalMath.floor_graph_build(RefCounted.new() if mode=="wrong_class" else graph,p,e,links)
		var atomic: bool = not result.get("ok",false) and graph.get_point_ids()==original and (mode!="nonempty" or graph.get_point_position(91)==Vector2(7,9))
		passed = passed and atomic
		observations.append({"mode":mode,"rejected_without_engine_change":atomic,"result":result})
	var valid: AStar2D = AStar2D.new()
	edges[96] = 4
	edges[97] = 2
	var assembled: Dictionary = PlatformArrivalMath.floor_graph_build(valid,present,enabled,edges)
	var positive: bool = assembled.get("ok",false) and assembled.get("points",-1)==2 and assembled.get("connections",-1)==1 and valid.get_point_count()==2 and valid.get_point_position(96)==Vector2(0,1) and valid.get_point_position(97)==Vector2(1,1) and valid.get_point_weight_scale(96)==1.0 and valid.get_point_connections(96)==PackedInt64Array([97]) and valid.get_point_connections(97)==PackedInt64Array([96])
	return {"ok":passed and positive,"observations":observations,"positive_adapter_without_script_fallback":positive,"positive_result":assembled}
