extends "res://tests/acceptance/environment_cache_scope.gd"

const Reference = preload("res://tests/acceptance/environment_wall_reference.gd")

func run_wall_cases(database: HospitalContent, selected: Array) -> Dictionary:
	_content = database
	var cases: Dictionary = {"ENV-WALL-LAYOUT":_wall_layout,"ENV-WALL-DOOR":_door,"ENV-WALL-LOCAL":_wall_local}
	var rows: Dictionary = {}
	for id: String in selected:
		if not cases.has(id): return {"ok":false,"unknown_case":id}
		rows[id] = cases[id].call()
	return {"ok":not rows.is_empty() and rows.values().all(func(row: Dictionary)->bool:return row.ok),"cases":rows}

# The inherited door case performs actual movement, widening, JSON restore,
# hold and release. Compare local direct queries too, not just prepared masks.
func _coverage_matches(x: Dictionary, origin: Array, noise: bool = false) -> bool:
	if not super._coverage_matches(x,origin,noise): return false
	return _compare_edges(x,Rect2i(int(origin[0])-4,int(origin[1])-4,9,9)).ok

func _compare_edges(x: Dictionary, area: Rect2i, floor_id: int = 1) -> Dictionary:
	var reference: HospitalEnvironment = Reference.new(_content,x.space)
	var before: Dictionary = x.world.freeze()
	var errors: Array = []
	var count: int = 0
	for y: int in range(area.position.y,area.end.y):
		for column: int in range(area.position.x,area.end.x):
			var cell: Array = [column,y]
			for edge: String in ["north","south","west","east"]:
				var offset: Array = {"north":[0,-1],"south":[0,1],"west":[-1,0],"east":[1,0]}[edge]
				var other: Array = [column+offset[0],y+offset[1]]
				if x.e._wall_edge(x.world,floor_id,cell,edge)!=reference._wall_edge(x.world,floor_id,cell,edge) or x.e._wall_between(x.world,floor_id,cell,other)!=reference._wall_between(x.world,floor_id,cell,other):
					if errors.size()<8: errors.append({"cell":cell,"edge":edge,"floor_id":floor_id})
				count += 1
	return {"ok":errors.is_empty() and before==x.world.freeze(),"edge_pairs":count,"errors":errors,"readonly":before==x.world.freeze()}

func _wall_layout() -> Dictionary:
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new()
	suite.content = _content
	var sim: HospitalSimulation = suite._fixture()
	var x: Dictionary = {"world":sim.world,"space":sim.space,"e":sim.services.environment}
	var cells: Array = []
	for y: int in range(68,74):
		for column: int in range(35,41):
			if column<39 or y<72: cells.append([column,y])
	var commands: Array = [
		["build_room",{"id":"shape","room_type_id":"gp","floor_id":1,"cells":cells,"door":{"definition_id":"DR01","edge":"south","offset":1}}],
		["build_rotate",{"target_id":"shape","turns":1}],
		["build_rotate",{"target_id":"shape","turns":1}],
		["build_rotate",{"target_id":"shape","turns":1}],
		["build_rotate",{"target_id":"shape","turns":1}],
		["build_move",{"target_id":"shape","floor_id":1,"cell":[48,68]}],
		["build_demolish",{"target_id":"shape"}],
		["build_undo",{}]
	]
	var rows: Array = []
	for command: Array in commands:
		var outcome: CommandResult = suite._command(sim,command[0],command[1])
		var compared: Dictionary = _compare_edges(x,Rect2i(33,66,24,11))
		var validation: String = sim.world.validate(_content)
		rows.append({"command":command[0],"ok":outcome.accepted and compared.ok and validation.is_empty(),"accepted":outcome.accepted,"reason":outcome.reason,"validation":validation,"comparison":compared})
	var checks: Dictionary = {"actual_layout_commands_match":rows.all(func(row: Dictionary)->bool:return row.ok)}
	var saved: Dictionary = sim.world.freeze()
	var retained: FloorStaticGeometry = sim.space._navigation.floor_geometry(sim.space,sim.world,1)
	sim.world.facts = saved.duplicate(true)
	checks.complete_facts_replacement_matches = _compare_edges(x,Rect2i(47,67,8,8)).ok
	checks.shared_geometry_remains_immutable = retained.source==sim.space._navigation.floor_geometry(sim.space,sim.world,1).source
	var fresh: WorldState = WorldState.new(saved)
	checks.other_world_same_revision_matches = _compare_edges({"world":fresh,"space":x.space,"e":x.e},Rect2i(47,67,8,8)).ok
	checks.same_cell_has_no_crossing = not x.e._wall_between(x.world,1,[48,68],[48,68])
	checks.invalid_edge_has_no_surface = not x.e._wall_edge(x.world,1,[48,68],"invalid")
	checks.other_floor_has_no_wall = not x.e._wall_between(x.world,2,[48,67],[48,68])
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"commands":rows}
	sim.dispose()
	return result

func _wall_local() -> Dictionary:
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new()
	suite.content = _content
	var sim: HospitalSimulation = suite._fixture()
	var x: Dictionary = {"world":sim.world,"space":sim.space,"e":sim.services.environment}
	var first: CommandResult = suite._command(sim,"build_room",suite._room("left",[35,68],[6,6]))
	var second: CommandResult = suite._command(sim,"build_room",suite._room("right",[41,68],[6,6]))
	var side: CommandResult = suite._command(sim,"build_door",{"room_id":"left","edge":"east","offset":1,"definition_id":"DR01"})
	var checks: Dictionary = {"built_legal_shared_wall":first.accepted and second.accepted and side.accepted and sim.world.validate(_content).is_empty(),"other_room_still_closes_shared_edge":x.e._wall_between(x.world,1,[40,69],[41,69]),"original_door_is_open":not x.e._wall_between(x.world,1,[36,73],[36,74]),"adjacent_solid_edge_is_closed":x.e._wall_between(x.world,1,[37,73],[37,74])}
	var before_quote: Dictionary = sim.world.freeze()
	var wall_quote: Dictionary = x.e.renovation_quote(x.world,{"floor_id":1,"material_id":"MAT05","units":[{"cell":[37,73],"edge":"south"}],"allow_waiting":true})
	var door_quote: Dictionary = x.e.renovation_quote(x.world,{"floor_id":1,"material_id":"MAT05","units":[{"cell":[36,73],"edge":"south"}],"allow_waiting":true})
	checks.only_real_wall_can_be_renovated = wall_quote.ok and wall_quote.cost==20 and wall_quote.work_seconds==8 and not door_quote.ok and before_quote==sim.world.freeze()
	var helper: RefCounted = preload("res://tests/acceptance/environment_source_intersection.gd").new()
	helper._content = _content
	helper._surface(x,[36,73],"south","MAT08")
	helper._surface(x,[37,73],"south","MAT05")
	sim.world.touch(false)
	var reference: HospitalEnvironment = Reference.new(_content,x.space)
	var scores: Array = []
	x.e.begin_query(x.world);reference.begin_query(x.world)
	for cell: Array in [[36,73],[37,73],[38,73],[36.5,73.5],[40,69],[41,69]]:
		var actual: Dictionary = x.e.environment_at(x.world,1,cell)
		var expected: Dictionary = reference.environment_at(x.world,1,cell)
		scores.append({"cell":cell,"ok":actual==expected,"value":actual.value,"sources":actual.sources})
	x.e.end_query();reference.end_query()
	checks.complete_environment_values_and_source_order = scores.all(func(row: Dictionary)->bool:return row.ok)
	checks.material_on_opening_does_not_contribute = scores[0].value==47 and scores[1].value==47 and scores[2].value==47
	# Populate genuinely distant legal rooms, including many collinear walls.
	var distant: bool = true
	for y: int in [79,84,89]:
		for column: int in [32,37,42,47,52,57]:
			var built: CommandResult = suite._command(sim,"build_room",suite._room("far_%d_%d" % [column,y],[column,y]))
			distant = distant and built.accepted
	checks.distant_rooms_built = distant
	var before: Dictionary = sim.world.freeze()
	var geometry: FloorStaticGeometry = sim.space._navigation.floor_geometry(sim.space,sim.world,1)
	var walls: int = int(sim.space.query_counts.get("environment_wall_candidates",0))
	var doors: int = int(sim.space.query_counts.get("environment_wall_door_candidates",0))
	var began: int = Time.get_ticks_usec()
	for _repeat: int in 200: x.e._wall_between(x.world,1,[36,73],[36,74])
	var local_usec: int = Time.get_ticks_usec()-began
	checks.steady_queries_borrow_existing_geometry = geometry==sim.space._navigation.floor_geometry(sim.space,sim.world,1) and before==sim.world.freeze()
	var local_walls: int = int(sim.space.query_counts.environment_wall_candidates)-walls
	var local_doors: int = int(sim.space.query_counts.environment_wall_door_candidates)-doors
	checks.only_local_wall_and_door_candidates = local_walls==200 and local_doors==200
	checks.all_local_edges_match_raw_facts = _compare_edges(x,Rect2i(34,67,15,9)).ok
	# Explicit fixed-source work, not a claim about whole-simulation frame time.
	reference.room_visits = 0
	reference.door_visits = 0
	began = Time.get_ticks_usec()
	for _repeat: int in 200: reference._wall_between(x.world,1,[36,73],[36,74])
	var full_usec: int = Time.get_ticks_usec()-began
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"scores":scores,"repeated_queries":200,"local_wall_candidates":local_walls,"local_door_candidates":local_doors,"local_usec":local_usec,"raw_full_scan_usec":full_usec,"raw_room_visits":reference.room_visits,"raw_door_visits":reference.door_visits,"rooms":x.world.facts.rooms.size(),"floor_doors":x.world.facts.floors.overrides["1"].doors.size(),"validation":sim.world.validate(_content)}
	sim.dispose()
	return result
