extends RefCounted

const Original = preload("res://tests/acceptance/single_connector_route.gd")
const FIRST: String = "expansion_first"
const SECOND: String = "expansion_second"

class PreparationProbe extends HospitalNavigation:
	var builds: Dictionary = {}
	var goals_first: bool = true
	func _init(geometry: HospitalSpace) -> void:
		super(geometry)
	func _connector_edges(world: WorldState, actor: Dictionary, context: Dictionary, node: Dictionary) -> Dictionary:
		var key: String = JSON.stringify([actor.id,context.members,context.offsets,context.distance_only,context.extra_stops,node.floor_id,node.cell],"",true,true)
		builds[key] = int(builds.get(key,0))+1
		return super._connector_edges(world,actor,context,node)
	func _point_edges(id: String, world: WorldState, actor: Dictionary, context: Dictionary) -> Array:
		var result: Array = super._point_edges(id,world,actor,context)
		for number: int in result.size():
			if result[number].to=="goal": goals_first = goals_first and number==0
		return result

func run_case(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	suite._history_height(sim,4)
	var extended: Array = []
	for floor_id: int in [3,4]:
		var result: CommandResult = suite._command(sim,"connector_extend",{"connection_id":suite._connection(sim),"floor_id":floor_id})
		extended.append(result.accepted)
		if not result.accepted:
			sim.dispose()
			return {"ok":false,"extension":result.to_record()}
	for floor_id: int in [2,3,4]: HospitalSpace.materialize_layout(sim.world,floor_id)
	suite._add_actor(sim,FIRST,"S49",[44,80])
	suite._add_actor(sim,SECOND,"S49",[45,80])
	var probe: PreparationProbe = PreparationProbe.new(sim.space)
	sim.space.navigation = probe
	var validation: String = sim.world.validate(suite.content)
	var checks: Dictionary = {"valid_input":validation.is_empty()}
	var observations: Array = []
	var before: Dictionary = sim.world.freeze()
	sim.space.begin_dynamic_route_query(sim.world)
	for cost_only: bool in [true,false]:
		for goal: Array in [[46,82],[47,82],[48,82],[49,82]]:
			if goal==[47,82]: sim.space.begin_route_query(sim.world,{},false)
			observations.append(_observe(sim.space,sim.world,suite.content,FIRST,2,goal,cost_only))
			if goal==[47,82]: sim.space.end_route_query()
			if not cost_only and goal==[46,82] and observations.back().actual.get("ok",false):
				# A caller owns its executable result, including nested cells.
				observations.back().actual.path[0].cell[0] = 94
		observations.append(_observe(sim.space,sim.world,suite.content,FIRST,3,[50,82],cost_only))
	checks.each_unchanged_node_prepared_at_most_once_per_mode = _bounded(probe.builds,10)
	checks.later_targets_reuse_preparation = true
	for number: int in [1,2,3,4,6,7,8,9]:
		# A completed source tree also reuses these edges without re-entering
		# their lookup. Full paths must still hit the original edge preparation.
		var reused: bool = observations[number].hits>0 or observations[number].cost_only and observations[number].source_hits>0
		checks.later_targets_reuse_preparation = checks.later_targets_reuse_preparation and observations[number].new_builds==0 and reused
	# Member order and actual formation offsets own distinct complete geometry.
	observations.append(_observe(sim.space,sim.world,suite.content,FIRST,2,[46,84],true,[FIRST,SECOND],{FIRST:[0,0],SECOND:[1,0]}))
	observations.append(_observe(sim.space,sim.world,suite.content,FIRST,2,[47,84],true,[FIRST,SECOND],{FIRST:[0,0],SECOND:[1,0]}))
	checks.same_group_reuses = observations.back().new_builds==0 and observations.back().hits>0
	observations.append(_observe(sim.space,sim.world,suite.content,FIRST,2,[48,84],true,[FIRST,SECOND],{FIRST:[0,0],SECOND:[0,1]}))
	checks.changed_offsets_prepare_independently = observations.back().new_builds>0
	observations.append(_observe(sim.space,sim.world,suite.content,FIRST,2,[49,84],true,[SECOND,FIRST],{FIRST:[0,0],SECOND:[1,0]}))
	checks.changed_member_order_prepares_independently = observations.back().new_builds>0
	checks.no_cached_goal_or_materialization_mutation = _only_connector_edges(sim.space.dynamic_transport_view(sim.world,FIRST,[],{}))
	sim.space.end_route_query()
	checks.source_world_and_rng_unchanged = before==sim.world.freeze()
	# A new batch, even on unchanged facts, has a new preparation owner.
	sim.space.begin_dynamic_route_query(sim.world)
	observations.append(_observe(sim.space,sim.world,suite.content,FIRST,2,[46,82],true))
	checks.new_batch_prepares_again = observations.back().new_builds>0
	sim.space.end_route_query()
	sim.space.begin_route_query(sim.world,{},false)
	observations.append(_observe(sim.space,sim.world,suite.content,FIRST,2,[48,82],true))
	checks.non_dynamic_query_uses_disposable_preparation = observations.back().new_builds>0
	observations.append(_observe(sim.space,sim.world,suite.content,FIRST,2,[49,82],true))
	checks.non_dynamic_query_uses_disposable_preparation = checks.non_dynamic_query_uses_disposable_preparation and observations.back().new_builds>0
	sim.space.end_route_query()
	# Real structural input changes are committed before opening the next batch.
	sim.world.facts.floors.overrides["2"].blocked.append([46,82])
	sim.world.touch()
	sim.space.begin_dynamic_route_query(sim.world)
	observations.append(_observe(sim.space,sim.world,suite.content,FIRST,2,[46,82],true,[],{},false))
	checks.changed_geometry_prepares_and_rejects_current_goal = observations.back().new_builds>0
	sim.space.end_route_query()
	var sparse: WorldState = WorldState.new(sim.world.freeze())
	sparse.facts.floors.overrides.erase("2")
	sparse.facts.floors.overrides.erase("3")
	sparse.touch()
	sim.space.begin_dynamic_route_query(sparse)
	observations.append(_observe(sim.space,sparse,suite.content,FIRST,2,[46,82],true))
	observations.append(_observe(sim.space,sparse,suite.content,FIRST,3,[46,82],true))
	checks.extra_stop_sets_prepare_independently = observations.back().new_builds>0
	observations.append(_observe(sim.space,sparse,suite.content,FIRST,2,[47,82],true))
	checks.same_extra_stop_set_reuses_across_goals = observations.back().new_builds==0 and observations.back().hits>0
	sim.space.end_route_query()
	var projected: WorldState = WorldState.new(sparse.freeze())
	projected.facts.actors[FIRST].species_id = "S59"
	sim.space.begin_dynamic_route_query(projected)
	observations.append(_observe(sim.space,projected,suite.content,FIRST,2,[46,82],true,[],{},false))
	checks.other_world_and_body_prepare_independently = observations.back().new_builds>0
	sim.space.end_route_query()
	var connection: Dictionary = sparse.facts.connectors[suite._connection(sim)]
	connection.failed = true
	sparse.touch(false)
	sim.space.begin_dynamic_route_query(sparse)
	observations.append(_observe(sim.space,sparse,suite.content,FIRST,2,[48,82],true,[],{},false))
	checks.current_direction_blocks_ascent = observations.back().new_builds>0
	sim.space.end_route_query()
	checks.goal_edge_order_preserved = probe.goals_first
	checks.query_stack_closed = sim.space._route_queries.is_empty()
	var ok: bool = true
	for accepted: bool in checks.values(): ok = ok and accepted
	var details: Array = []
	for observation: Dictionary in observations:
		ok = ok and observation.ok
		var row: Dictionary = observation.duplicate()
		row.erase("actual")
		details.append(row)
	var result: Dictionary = {"ok":ok,"validation":validation,"checks":checks,"observations":details,"scope":"Only target-independent connector preparation belongs to a sealed dynamic candidate batch. Goal edges, final answers and actual movement remain independent."}
	sim.dispose()
	return result

func _observe(space: HospitalSpace, world: WorldState, content: HospitalContent, actor_id: String, floor_id: int, goal: Array, cost_only: bool, members: Array = [], offsets: Dictionary = {}, available: bool = true) -> Dictionary:
	var before: Dictionary = world.freeze()
	var builds: int = int(space.query_counts.get("connector_edge_builds",0))
	var hits: int = int(space.query_counts.get("connector_edge_hits",0))
	var source_hits: int = int(space.query_counts.get("point_source_hits",0))
	var actual: Dictionary = space.route_cost(world,actor_id,floor_id,goal,members,offsets,true) if cost_only else space.route(world,actor_id,floor_id,goal,members,offsets,true)
	# The frozen solver has no connector_prepared context and always derives
	# every settled node's connector edges through the original complete process.
	var cold: HospitalSpace = HospitalSpace.new(content)
	cold.navigation = Original.FullSolver.new(cold)
	var expected: Dictionary = cold.route_cost(world,actor_id,floor_id,goal,members,offsets,true) if cost_only else cold.route(world,actor_id,floor_id,goal,members,offsets,true)
	return {"ok":actual==expected and actual.ok==available and before==world.freeze(),"floor_id":floor_id,"goal":goal,"cost_only":cost_only,"members":members,"offsets":offsets,"new_builds":int(space.query_counts.get("connector_edge_builds",0))-builds,"hits":int(space.query_counts.get("connector_edge_hits",0))-hits,"source_hits":int(space.query_counts.get("point_source_hits",0))-source_hits,"full_path_types_cost_status_match_unprepared_solver":actual==expected,"available":actual.ok,"world_and_rng_unchanged":before==world.freeze(),"actual":actual,"expected":expected if actual!=expected else {}}

func _bounded(builds: Dictionary, maximum_nodes: int) -> bool:
	if builds.is_empty() or builds.size()>maximum_nodes: return false
	for count: int in builds.values():
		if count!=1: return false
	return true

func _only_connector_edges(owner: Dictionary) -> bool:
	for floors: Dictionary in owner.point_connector_edges.variants.values():
		for nodes: Dictionary in floors.values():
			for prepared: Dictionary in nodes.values():
				if prepared.facts.has("goal"): return false
				for edge: Dictionary in prepared.outgoing:
					if edge.to=="goal": return false
	return true
