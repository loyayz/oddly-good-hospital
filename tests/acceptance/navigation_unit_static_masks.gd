extends RefCounted

const Bulk = preload("res://tests/acceptance/navigation_bulk_build.gd")
const Cold = preload("res://tests/acceptance/navigation_cold_graph.gd")

class UnitProbe extends RouteClearance:
	var nodes: int = 0
	var edges: int = 0
	var mask_calls: int = 0
	var native_ready: int = 0
	var native_fallback_reason: String = ""
	func unit_static_masks() -> Dictionary:
		mask_calls += 1
		var result: Dictionary = super.unit_static_masks()
		if result.get("ready",false): native_ready += 1
		else: native_fallback_reason = str(result.get("reason",result.get("error","")))
		return result
	func reason(cell: Vector2i) -> String:
		nodes += 1
		return super.reason(cell)
	func edge_reason(from: Vector2i, to: Vector2i) -> String:
		edges += 1
		return super.edge_reason(from,to)

func run_case(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var room: CommandResult = suite._command(sim,"build_room",suite._room("unit_mask_room",[42,68],[14,10]))
	if not room.accepted:
		sim.dispose()
		return {"ok":false,"real_room":room.to_record()}
	suite._add_actor(sim,"unit_mask_actor","S49",[35.25,82.5])
	var actor: Dictionary = sim.world.facts.actors.unit_mask_actor
	var source: Dictionary = RouteClearance.capture_source(sim.space,sim.world,1)
	var before: Dictionary = sim.world.freeze()
	var validation: String = sim.world.validate(suite.content)
	var rows: Array = [_one(sim,actor,"real_room_fractional_actual_source",source)]
	# These are complete immutable geometry projections, not fake arrivals or
	# mocked business quotes. The original predicate independently consumes each
	# same source; literal masks below also check obstacle/open-door precedence.
	var mixed: Dictionary = source.duplicate(true)
	var door: Dictionary = suite._doors(sim.world,"unit_mask_room")[0]
	mixed.layout.blocked.append(door.cell.duplicate())
	mixed.layout.blocked.append([36,82])
	# Entity IDs are String keys; dot insertion would create StringName and
	# intentionally select the unsupported-input fallback instead of this path.
	mixed.facilities["unit_mask_obstacle"] = {"cell":[37,82],"footprint":[1,1]}
	mixed.connectors["unit_mask_connector"] = {"cell":[38,82],"footprint":[1,1]}
	rows.append(_one(sim,actor,"blocked_door_and_distinct_obstacles",mixed))
	var shared_wall: Dictionary = source.duplicate(true)
	shared_wall.rooms["unit_mask_other_room"] = {"origin":[42,78],"size":[14,4]}
	rows.append(_one(sim,actor,"same_line_other_room_cannot_use_original_door",shared_wall))
	rows.append(_one(sim,actor,"height_exceeds_actual_source",source,true))
	# WorldState owns its input dictionary; keep the original read-only baseline
	# independent from the separate low-ceiling world's deliberately changed facts.
	var closed_world: WorldState = WorldState.new(before.duplicate(true))
	closed_world.facts.floors.height_intervals = [{"first":1,"last":1,"height_m":0.1}]
	var closed_before: Dictionary = closed_world.freeze()
	var closed: RouteClearance = RouteClearance.new(sim.space,closed_world,closed_world.facts.actors[actor.id],1,[],{},false)
	var closed_validation: String = closed_world.validate(suite.content)
	var closed_quote: bool = not closed._doors.is_empty() and closed._doors.any(func(record: Dictionary)->bool:return not record.ok and not str(record.reason).is_empty())
	rows.append(_one(sim,closed_world.facts.actors[actor.id],"real_door_quote_rejected_by_actual_ceiling",closed.source,false,closed_world))
	var raw: Dictionary = {"source":source,"doors":RouteClearance.new(sim.space,sim.world,actor,1,[],{},false,source)._doors,"height_ok":true}
	var fallback: Dictionary = _unsupported(raw)
	var readonly: bool = before==sim.world.freeze()
	var closed_readonly: bool = closed_before==closed_world.freeze()
	var result: Dictionary = {"ok":validation.is_empty() and closed_validation.is_empty() and closed_quote and readonly and closed_readonly and fallback.ok and rows.all(func(row: Dictionary)->bool:return row.ok),"validation":validation,"actual_door_failure_validation":closed_validation,"actual_ceiling_rejects_door":closed_quote,"all_complete_masks_points_edges_neighbours_and_paths":rows,"unsupported_complete_fallback":fallback,"facts_and_rng_unchanged":readonly,"low_ceiling_facts_and_rng_unchanged":closed_readonly,"scope":"Original integer geometry and resolved-door calculations; actual movement and reservation ownership remain separate SPACE cases."}
	sim.dispose()
	return result

func _one(sim: HospitalSimulation, actor: Dictionary, label: String, source: Dictionary, too_high: bool = false, world: WorldState = null) -> Dictionary:
	if world==null: world = sim.world
	var original: Dictionary = source.duplicate(true)
	var actual: UnitProbe = UnitProbe.new(sim.space,world,actor,1,[],{},false,source)
	var reference: RouteClearance = Bulk.OriginalClearance.new(sim.space,world,actor,1,[],{},false,source)
	if too_high:
		actual._height_m = float(source.height)+1.0
		reference._height_m = actual._height_m
	var graph: FloorNavigation = FloorNavigation.new(actual)
	var counted: Dictionary = {"mask_calls":actual.mask_calls,"native_ready":actual.native_ready,"script_nodes":actual.nodes,"script_edges":actual.edges}
	var expected: FloorNavigation = Bulk.ScriptBuild.new(reference)
	var complete: Dictionary = Cold.new()._compare(graph,{"graph":expected,"enabled":expected._enabled,"edges":expected._edges})
	var edge_pairs: int = 0
	var complete_directed: bool = true
	for id: int in 9216:
		var cell: Vector2i = Vector2i(id%96,id/96)
		for direction: int in 4:
			var next: Vector2i = cell+FloorNavigation.NEIGHBOURS[direction]
			if not FloorNavigation._inside(next): continue
			edge_pairs += 1
			var allowed: bool = graph.has_point(id) and reference.reason(cell).is_empty() and reference.reason(next).is_empty() and reference.edge_reason(cell,next).is_empty()
			complete_directed = complete_directed and bool(graph._edges[id]&(1<<direction))==allowed
	var paths: Array = []
	var path_equal: bool = true
	for endpoints: Array in [[Vector2i(35,82),Vector2i(59,82)],[Vector2i(35,82),Vector2i(45,72)],[Vector2i(35,82),Vector2i(0,0)]]:
		for cost_only: bool in [false,true]:
			for partial: bool in [false,true]:
				var a: Dictionary = graph.find_path(endpoints[0],endpoints[1],actual,Callable(),partial,[],[],false,cost_only)
				var b: Dictionary = expected.find_path(endpoints[0],endpoints[1],reference,Callable(),partial,[],[],false,cost_only)
				path_equal = path_equal and a==b
				paths.append({"cost_only":cost_only,"partial":partial,"equal":a==b,"actual":a,"expected":b})
	var literal: bool = true
	if label=="height_exceeds_actual_source": literal = graph._enabled.count(1)==0
	if label=="blocked_door_and_distinct_obstacles": literal = graph._enabled[82*96+36]==0 and graph._enabled[82*96+37]==0 and graph._enabled[82*96+38]==0
	return {"ok":counted=={"mask_calls":1,"native_ready":1,"script_nodes":0,"script_edges":0} and complete.ok and complete_directed and path_equal and literal and source==original,"variant":label,"positive_native_work":counted,"native_fallback_reason":actual.native_fallback_reason,"complete_graph":complete,"all_directed_edges_match_independent_predicates":complete_directed,"directed_edge_pairs":edge_pairs,"paths_and_exact_failure_reasons":paths,"literal_obstacle_height_boundaries":literal,"source_unchanged":source==original}

func _unsupported(raw: Dictionary) -> Dictionary:
	var rows: Array = []
	for mode: String in ["outside_plot","fractional_blocked","fractional_wall","fractional_raw_span","fractional_opening","empty_closed_reason","missing_source"]:
		var input: Dictionary = raw.duplicate(true)
		match mode:
			"outside_plot": input.source.layout.plots.append([3,2])
			"fractional_blocked": input.source.layout.blocked.append([35.5,82])
			"fractional_wall": input.source.rooms.unit_mask_room.wall_edges[0].line = float(input.source.rooms.unit_mask_room.wall_edges[0].line)+0.25
			"fractional_raw_span": input.source.layout.doors[0].span = float(input.source.layout.doors[0].span)+0.25
			"fractional_opening":
				var opening: Rect2 = input.doors[0].opening
				opening.position.x += 0.25
				input.doors[0].opening = opening
			"empty_closed_reason":
				input.doors[0].ok = false
				input.doors[0].reason = ""
			"missing_source": input.erase("source")
		var before: Dictionary = input.duplicate(true)
		var result: Dictionary = PlatformArrivalMath.unit_static_masks(input)
		rows.append({"variant":mode,"complete_fallback_without_error_or_partial_output":not result.get("ready",false) and not result.has("error") and not result.has("present") and not result.has("enabled") and not result.has("edges") and before==input,"result":result})
	return {"ok":rows.all(func(row: Dictionary)->bool:return row.complete_fallback_without_error_or_partial_output),"observations":rows}
