extends RefCounted

class CountingClearance extends RouteClearance:
	var edge_checks: int = 0
	func edge_reason(from: Vector2i, to: Vector2i) -> String:
		edge_checks += 1
		return super.edge_reason(from,to)

func run_case(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var built: CommandResult = suite._command(sim,"build_room",suite._room("cold_graph_room",[42,68],[14,10]))
	if not built.accepted:
		sim.dispose()
		return {"ok":false,"room":built.to_record()}
	suite._add_actor(sim,"cold_small","S49",[35,82])
	suite._add_actor(sim,"cold_wide","S59",[35.25,84.5])
	var validation: String = sim.world.validate(suite.content)
	var before: Dictionary = sim.world.freeze()
	var rows: Array = []
	var ok: bool = validation.is_empty()
	var door: Dictionary = suite._doors(sim.world,"cold_graph_room")[0]
	var small_quote: Dictionary = sim.space.door_quote(sim.world,sim.world.facts.actors.cold_small,1,door)
	var wide_quote: Dictionary = sim.space.door_quote(sim.world,sim.world.facts.actors.cold_wide,1,door)
	var door_boundary: bool = small_quote.get("ok",false) and wide_quote.get("ok",false) and int(small_quote.span)==1 and int(wide_quote.span)==3
	for mode: String in ["small","wide","fractional_group"]:
		var actor: Dictionary = sim.world.facts.actors.cold_wide if mode=="wide" else sim.world.facts.actors.cold_small
		var members: Array = ["cold_small","cold_wide"] if mode=="fractional_group" else []
		var offsets: Dictionary = {"cold_small":[0,0],"cold_wide":[0.25,2.5]} if not members.is_empty() else {}
		var geometry: CountingClearance = CountingClearance.new(sim.space,sim.world,actor,1,members,offsets,false)
		var graph: FloorNavigation = FloorNavigation.new(geometry)
		var actual_checks: int = geometry.edge_checks
		geometry.edge_checks = 0
		var expected: Dictionary = _complete_directed_reference(sim.world,geometry)
		var comparison: Dictionary = _compare(graph,expected)
		var halved: bool = actual_checks>0 and actual_checks*2==geometry.edge_checks
		ok = ok and comparison.ok and halved
		rows.append({"mode":mode,"clearance":sim.space.clearance(actor),"points":graph.get_point_count(),"complete_comparison":comparison,"cold_edge_checks":actual_checks,"full_directed_edge_checks":geometry.edge_checks,"each_static_pair_checked_once":halved})
	var readonly: bool = before==sim.world.freeze()
	var result: Dictionary = {"ok":ok and door_boundary and readonly,"validation":validation,"actual_one_and_three_cell_door_rules":door_boundary,"small_door":small_quote,"wide_door":wide_quote,"all_owned_and_outside_cells":rows,"world_and_rng_unchanged":readonly,"scope":"Static topology only; SPACE-46/51 separately retain query-time group and reservation permissions."}
	sim.dispose()
	return result

# Independently enumerate all 9216 origins and all four directed neighbours.
# Geometry supplies the unchanged business predicate; this oracle never uses
# the optimized RIGHT/DOWN builder or its edge masks to form expectations.
func _complete_directed_reference(world: WorldState, geometry: RouteClearance) -> Dictionary:
	var graph: AStar2D = AStar2D.new()
	var enabled: PackedByteArray = PackedByteArray()
	var edges: PackedByteArray = PackedByteArray()
	enabled.resize(9216)
	edges.resize(9216)
	var plots: Array = HospitalSpace.floor_plots(world,1)
	for id: int in 9216:
		var cell: Vector2i = Vector2i(id%96,id/96)
		var owned: bool = false
		for plot: Array in plots:
			if Rect2i(int(plot[0])*32,int(plot[1])*32,32,32).has_point(cell): owned = true
		if not owned: continue
		graph.add_point(id,Vector2(cell))
		enabled[id] = int(geometry.reason(cell).is_empty())
		graph.set_point_disabled(id,enabled[id]==0)
	for id: int in graph.get_point_ids():
		if enabled[id]==0: continue
		var cell: Vector2i = Vector2i(id%96,id/96)
		var neighbours: Array[Vector2i] = [cell+Vector2i.UP,cell+Vector2i.LEFT,cell+Vector2i.RIGHT,cell+Vector2i.DOWN]
		for direction: int in 4:
			var next: Vector2i = neighbours[direction]
			if next.x<0 or next.y<0 or next.x>=96 or next.y>=96: continue
			var other: int = next.y*96+next.x
			if enabled[other]==0 or not geometry.edge_reason(cell,next).is_empty(): continue
			graph.connect_points(id,other,false)
			edges[id] |= 1<<direction
	return {"graph":graph,"enabled":enabled,"edges":edges}

func _compare(actual: FloorNavigation, expected: Dictionary) -> Dictionary:
	var reference: AStar2D = expected.graph
	var points: bool = actual.get_point_ids()==reference.get_point_ids()
	var enabled: bool = actual._enabled==expected.enabled
	var edges: bool = actual._edges==expected.edges
	var order: bool = true
	var failure: Dictionary = {}
	for id: int in reference.get_point_ids():
		if not actual.has_point(id):
			order = false
			failure = {"id":id,"missing":true}
			break
		if actual.is_point_disabled(id)!=reference.is_point_disabled(id) or actual.get_point_connections(id)!=reference.get_point_connections(id):
			order = false
			failure = {"id":id,"actual_disabled":actual.is_point_disabled(id),"expected_disabled":reference.is_point_disabled(id),"actual_connections":actual.get_point_connections(id),"expected_connections":reference.get_point_connections(id)}
			break
	return {"ok":points and enabled and edges and order,"all_points":points,"all_enabled_cells":enabled,"all_edge_masks":edges,"engine_neighbour_order":order,"first_difference":failure}
