extends RefCounted

const FIRST: String = "sole_route_first"
const SECOND: String = "sole_route_second"

# Frozen d8cb36d point solver, including its original early-return predicate.
# Its full Boost search is the independent reference for the new shortcut.
class FullSolver extends HospitalNavigation:
	func _init(geometry: HospitalSpace) -> void:
		super(geometry)
	func _point_route(world: WorldState, actor: Dictionary, source_floor: int, start: Vector2i, target_floor: int, goal: Vector2i, members: Array, offsets: Dictionary, initial_ticks: int, distance_only: bool) -> Dictionary:
		var direct: Dictionary = {"ok":false,"status":"unreachable","reason":"没有合法通路"}
		if source_floor==target_floor:
			direct = _floor_route(world,actor,source_floor,start,goal,members,offsets,true,{},true,distance_only)
			if direct.ok and (world.facts.connectors.is_empty() or int(direct.walking_distance)==absi(goal.x-start.x)+absi(goal.y-start.y)):
				direct.travel_ticks = HospitalTransit._add(initial_ticks,HospitalTransit.walking_ticks(space,actor,members,float(direct.walking_distance)))
				if int(direct.travel_ticks)<0: return {"ok":false,"status":"time_overflow","reason":"基准通行时间超出整数范围"}
				direct.quoted_tick = world.sim_tick
				if distance_only: direct.erase("path")
				return direct
		space.query_counts.transport_searches += 1
		var nodes: Dictionary = {"start":{"floor_id":source_floor,"cell":start},"goal":{"floor_id":target_floor,"cell":goal}}
		var topology: Dictionary = _topology(world)
		var node_ids: Array = topology.node_ids
		var extra_stops: Dictionary = {}
		for floor_id: int in {source_floor:true,target_floor:true}:
			if topology.candidates.has(floor_id): continue
			var extra: Dictionary = _topology_floor_nodes(world,topology,floor_id)
			if extra.ids.is_empty(): continue
			if is_same(node_ids,topology.node_ids): node_ids = node_ids.duplicate()
			node_ids.append_array(extra.ids)
			nodes.merge(extra.nodes)
			for id: String in extra.connectors:
				if not extra_stops.has(id): extra_stops[id] = []
				extra_stops[id].append(floor_id)
		var context: Dictionary = {"nodes":nodes,"stops":topology.stops,"extra_stops":extra_stops,"query_stops":{},"topology":topology,"connections":{},"compatible":{},"edges":{},"source_floor":source_floor,"target_floor":target_floor,"goal":goal,"members":members,"offsets":offsets,"distance_only":distance_only,"direct":direct}
		var solved: Dictionary = PlatformArrivalMath.route_search({"nodes":node_ids,"start":"start","goal":"goal","initial_ticks":initial_ticks,"expand":_point_edges.bind(world,actor,context)})
		if solved.has("error"):
			return {"ok":false,"status":"navigation_failed","reason":str(solved.get("bottleneck",solved.error))}
		if solved.get("ok",false):
			var chain: Array = solved.nodes
			var chunks: Array = []
			var distance: float = 0.0
			for index: int in range(chain.size()-1,0,-1):
				var edge: Dictionary = context.edges[chain[index-1]][chain[index]]
				distance += float(edge.walking_distance)
				if not distance_only: chunks.push_front(edge.path)
			var result: Dictionary = {"ok":true,"status":"complete","reason":"","walking_distance":distance,"travel_ticks":int(solved.travel_ticks),"quoted_tick":world.sim_tick}
			if not distance_only:
				var path: Array = []
				for chunk: Array in chunks: path.append_array(chunk)
				result.path = path
			return result
		if direct.ok: return {"ok":false,"status":"time_overflow","reason":"基准通行时间超出整数范围"}
		return direct if source_floor==target_floor else {"ok":false,"status":"unreachable","reason":"没有身体、停层和运行方向均合法的竖向通路"}

func run_case(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	suite._add_actor(sim,FIRST,"S49",[44,80])
	suite._add_actor(sim,SECOND,"S49",[45,80])
	# A literal one-cell wall makes the six-cell straight journey an eight-cell
	# detour. The existing connector is elsewhere and cannot bypass this wall.
	sim.world.facts.floors.overrides["1"].blocked.append([47,80])
	sim.world.touch()
	var validation: String = sim.world.validate(suite.content)
	var reference: HospitalSpace = HospitalSpace.new(suite.content)
	reference.navigation = FullSolver.new(reference)
	var observations: Array = []
	observations.append(_compare(sim,reference,1,[50,80],true,8))
	observations.append(_compare(sim,reference,1,[50,80],true,8,[FIRST,SECOND],{FIRST:[0,0],SECOND:[1,0]}))
	observations.append(_compare(sim,reference,2,[50,80],true))
	observations.append(_compare(sim,reference,1,[47,80],false))
	var before: Dictionary = sim.world.freeze()
	var actor: Dictionary = sim.world.facts.actors[FIRST]
	var overflow: Dictionary = sim.space.navigation._point_route(sim.world,actor,1,Vector2i(44,80),1,Vector2i(50,80),[],{},HospitalTransit.MAX_TICK-1,false)
	var expected_overflow: Dictionary = reference.navigation._point_route(sim.world,actor,1,Vector2i(44,80),1,Vector2i(50,80),[],{},HospitalTransit.MAX_TICK-1,false)
	var checks: Dictionary = {"valid_input":validation.is_empty(),"overflow_matches_full_solver":overflow==expected_overflow and not overflow.ok and overflow.status=="time_overflow","overflow_world_and_rng_unchanged":before==sim.world.freeze()}
	var cost: Dictionary = sim.space.route_cost(sim.world,FIRST,1,[50,80],[],{},true)
	var expected_cost: Dictionary = reference.route_cost(sim.world,FIRST,1,[50,80],[],{},true)
	checks.cost_only_matches_full_solver = cost==expected_cost and cost.ok and cost.walking_distance==8 and not cost.has("path")
	var dual: Dictionary = _dual_connector(suite)
	var ok: bool = dual.ok
	for accepted: bool in checks.values(): ok = ok and accepted
	for observation: Dictionary in observations: ok = ok and observation.ok
	var result: Dictionary = {"ok":ok,"validation":validation,"checks":checks,"observations":observations,"multiple_connectors":dual,"scope":"Current unit-cost floor geometry and nonnegative fixed transit times; no soft-cost weighting or future weighted objective is assumed."}
	sim.dispose()
	return result

func _compare(sim: HospitalSimulation, reference: HospitalSpace, floor_id: int, goal: Array, expected_ok: bool, expected_distance: int = -1, members: Array = [], offsets: Dictionary = {}) -> Dictionary:
	var before: Dictionary = sim.world.freeze()
	var actual: Dictionary = sim.space.route(sim.world,FIRST,floor_id,goal,members,offsets,true)
	var expected: Dictionary = reference.route(sim.world,FIRST,floor_id,goal,members,offsets,true)
	var distance_ok: bool = expected_distance<0 or actual.get("walking_distance",-1)==expected_distance
	return {"ok":actual==expected and actual.ok==expected_ok and distance_ok and before==sim.world.freeze(),"floor_id":floor_id,"goal":goal,"members":members,"full_path_distance_ticks_and_status_equal":actual==expected,"literal_expected_distance":expected_distance,"actual_distance":actual.get("walking_distance",-1),"actual_available":actual.ok,"world_and_rng_unchanged":before==sim.world.freeze(),"actual":actual if actual!=expected else {},"expected":expected if actual!=expected else {}}

func _dual_connector(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	var built: CommandResult = suite._command(sim,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[52,72]})
	if not built.accepted:
		sim.dispose()
		return {"ok":false,"build":built.to_record()}
	var connector_id: String = str(built.changed_ids[0])
	var extended: CommandResult = suite._command(sim,"connector_extend",{"connection_id":connector_id,"floor_id":2})
	if not extended.accepted:
		sim.dispose()
		return {"ok":false,"extend":extended.to_record()}
	suite._add_actor(sim,FIRST,"S49",[42,76])
	# The wall reaches the north plot edge and ends at y92. Walking on this
	# floor requires 42 cells; the two lifts provide a real shorter fixed-time
	# journey via 2F with 6+16+2 walking cells and two complete lift rides.
	for y: int in range(64,93): sim.world.facts.floors.overrides["1"].blocked.append([46,y])
	sim.world.touch()
	var validation: String = sim.world.validate(suite.content)
	var reference: HospitalSpace = HospitalSpace.new(suite.content)
	reference.navigation = FullSolver.new(reference)
	var before: Dictionary = sim.world.freeze()
	var actual: Dictionary = sim.space.route(sim.world,FIRST,1,[50,76],[],{},true)
	var expected: Dictionary = reference.route(sim.world,FIRST,1,[50,76],[],{},true)
	var direct: Dictionary = sim.space.navigation._floor_route(sim.world,sim.world.facts.actors[FIRST],1,Vector2i(42,76),Vector2i(50,76),[],{},true,{},true,false)
	var rides: Array = []
	for segment: Dictionary in actual.get("path",[]):
		if segment.kind=="connector": rides.append(segment.connector_id)
	var literal: bool = actual.get("walking_distance",-1)==24 and direct.get("walking_distance",-1)==42 and rides.size()==2 and rides[0]!=rides[1] and int(actual.get("travel_ticks",-1))<HospitalTransit.walking_ticks(sim.space,sim.world.facts.actors[FIRST],[],42.0)
	var result: Dictionary = {"ok":validation.is_empty() and actual==expected and literal and before==sim.world.freeze(),"validation":validation,"full_solver_equal":actual==expected,"literal_42_cell_walk_and_24_cell_two_lift_shortcut":literal,"walking_distance":actual.get("walking_distance",-1),"travel_ticks":actual.get("travel_ticks",-1),"direct_distance":direct.get("walking_distance",-1),"rides":rides,"world_and_rng_unchanged":before==sim.world.freeze(),"actual":actual if not literal or actual!=expected else {}}
	sim.dispose()
	return result
