extends RefCounted

const ACTOR: String = "prepared_floor_actor"

class GraphProbe extends NavigationCache:
	var graph_calls: int = 0
	func graph(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, members: Array, offsets: Dictionary) -> FloorNavigation:
		graph_calls += 1
		return super.graph(space,world,floor_id,actor,members,offsets)

# Restore the previous acquisition boundary while keeping the same complete
# source, clearance, distance field and A* implementation as the calculation.
class ReacquireGraph extends GraphProbe:
	func forward_distance(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, start: Vector2i, goal: Vector2i, structural_only: bool = false, _prepared_graph: FloorNavigation = null) -> Dictionary:
		return super.forward_distance(space,world,floor_id,actor,start,goal,structural_only)

func run_case(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	suite._add_actor(sim,ACTOR,"S49",[44,80])
	var actual: HospitalSpace = HospitalSpace.new(suite.content)
	var reference: HospitalSpace = HospitalSpace.new(suite.content)
	var actual_cache: GraphProbe = GraphProbe.new()
	var reference_cache: ReacquireGraph = ReacquireGraph.new()
	actual._navigation = actual_cache
	reference._navigation = reference_cache
	var world: WorldState = sim.world
	var actor: Dictionary = world.facts.actors[ACTOR]
	var validation: String = world.validate(suite.content)
	var before: Dictionary = world.freeze()
	var checks: Dictionary = {"valid_input":validation.is_empty()}
	var equal: bool = true
	var observations: Array = []
	actual.begin_dynamic_route_query(world)
	reference.begin_dynamic_route_query(world)
	# Distinct complete targets preserve the original 12-query threshold and
	# cross its distance-field warmup boundary; no candidate is skipped.
	for y: int in range(82,85):
		for x: int in range(44,50):
			var goal: Vector2i = Vector2i(x,y)
			var current: Dictionary = actual.navigation._floor_route(world,actor,1,Vector2i(44,80),goal,[],{},true,{},true,true)
			var expected: Dictionary = reference.navigation._floor_route(world,actor,1,Vector2i(44,80),goal,[],{},true,{},true,true)
			equal = equal and current==expected
			observations.append({"goal":goal,"equal":current==expected,"available":current.ok,"distance":current.get("walking_distance",-1)})
	checks.distinct_targets_keep_complete_cost_type_status = equal
	checks.one_graph_acquisition_per_structural_floor_query = actual_cache.graph_calls==18 and reference_cache.graph_calls==36
	checks.same_forward_field_warmup_and_reuse = int(actual.query_counts.get("distance_field_builds",0))==1 and actual.query_counts.get("distance_field_builds",0)==reference.query_counts.get("distance_field_builds",0) and actual.query_counts.get("distance_field_hits",0)==reference.query_counts.get("distance_field_hits",0)
	var impossible: Dictionary = actual.navigation._floor_route(world,actor,1,Vector2i(44,80),Vector2i(-1,80),[],{},true,{},true,true)
	var expected_impossible: Dictionary = reference.navigation._floor_route(world,actor,1,Vector2i(44,80),Vector2i(-1,80),[],{},true,{},true,true)
	checks.goal_first_failure_is_unchanged = impossible==expected_impossible and not impossible.ok
	actual.end_route_query()
	reference.end_route_query()
	checks.queries_are_readonly_and_close = before==world.freeze() and actual._route_queries.is_empty() and reference._route_queries.is_empty()
	# The optimization neither retains a graph across calls nor bypasses the
	# permission-aware acquisition path for a non-structural calculation.
	var actual_prior: int = actual_cache.graph_calls
	var reference_prior: int = reference_cache.graph_calls
	var dynamic: Dictionary = actual.navigation._floor_route(world,actor,1,Vector2i(44,80),Vector2i(46,82),[],{},true,{},false,true)
	var expected_dynamic: Dictionary = reference.navigation._floor_route(world,actor,1,Vector2i(44,80),Vector2i(46,82),[],{},true,{},false,true)
	checks.non_structural_clearance_retains_original_acquisition = dynamic==expected_dynamic and actual_cache.graph_calls-actual_prior==reference_cache.graph_calls-reference_prior
	var supplied: Dictionary = actual_cache.query_graphs(actual,world,1,actor,[],{})
	var supplied_reference: Dictionary = reference_cache.query_graphs(reference,world,1,actor,[],{})
	actual_prior = actual_cache.graph_calls
	reference_prior = reference_cache.graph_calls
	var external: Dictionary = actual.navigation._floor_route(world,actor,1,Vector2i(44,80),Vector2i(47,82),[],{},true,supplied,true,true)
	var expected_external: Dictionary = reference.navigation._floor_route(world,actor,1,Vector2i(44,80),Vector2i(47,82),[],{},true,supplied_reference,true,true)
	checks.externally_supplied_graph_keeps_original_validation = external==expected_external and actual_cache.graph_calls-actual_prior==1 and reference_cache.graph_calls-reference_prior==1
	world.facts.floors.overrides["1"].blocked.append([46,82])
	world.touch()
	before = world.freeze()
	actual_prior = actual_cache.graph_calls
	var changed: Dictionary = actual.navigation._floor_route(world,actor,1,Vector2i(44,80),Vector2i(46,82),[],{},true,{},true,true)
	var expected_changed: Dictionary = reference.navigation._floor_route(world,actor,1,Vector2i(44,80),Vector2i(46,82),[],{},true,{},true,true)
	checks.next_call_acquires_current_geometry = changed==expected_changed and not changed.ok and actual_cache.graph_calls-actual_prior==1 and before==world.freeze()
	var ok: bool = not checks.values().has(false)
	var result: Dictionary = {"ok":ok,"checks":checks,"validation":validation,"observations":observations,"graph_calls":actual_cache.graph_calls,"reference_graph_calls":reference_cache.graph_calls}
	sim.dispose()
	return result
