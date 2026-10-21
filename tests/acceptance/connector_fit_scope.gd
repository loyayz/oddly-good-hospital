extends RefCounted

const FIRST: String = "fit_scope_first"
const SECOND: String = "fit_scope_second"
const LARGE: String = "fit_scope_large"

# Count actual additions to the production compatibility view. All geometry,
# complete routing, body fit and failure-direction predicates still execute.
class FitProbe extends HospitalNavigation:
	var compatibility_checks: int = 0
	func _init(geometry: HospitalSpace) -> void:
		super(geometry)
	func _point_edges(id: String, world: WorldState, actor: Dictionary, context: Dictionary) -> Array:
		var before: int = context.compatible.size()
		var result: Array = super._point_edges(id,world,actor,context)
		compatibility_checks += context.compatible.size()-before
		return result

func run_case(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	for data: Array in [[FIRST,"S49",[46,80]],[SECOND,"S49",[47,80]],[LARGE,"S59",[50,84]]]:
		suite._add_actor(sim,str(data[0]),str(data[1]),data[2])
	var validation: String = sim.world.validate(suite.content)
	var probe: FitProbe = FitProbe.new(sim.space)
	sim.space.navigation = probe
	var observations: Array = []
	var checks: Dictionary = {"valid_input":validation.is_empty()}
	var original: Dictionary = sim.world.freeze()
	sim.space.begin_route_query(sim.world,{},false)
	observations.append(_observe(sim,probe,FIRST,2,[46,82],1,true))
	sim.space.begin_route_query(sim.world,{},false)
	observations.append(_observe(sim,probe,FIRST,2,[47,82],0,true))
	sim.space.end_route_query()
	observations.append(_observe(sim,probe,FIRST,2,[48,84],1,true,[FIRST,SECOND],{FIRST:[0,0],SECOND:[1,0]}))
	observations.append(_observe(sim,probe,FIRST,2,[49,84],0,true,[FIRST,SECOND],{FIRST:[0,0],SECOND:[1,0]}))
	observations.append(_observe(sim,probe,FIRST,2,[50,84],1,true,[SECOND,FIRST],{FIRST:[0,0],SECOND:[1,0]}))
	observations.append(_observe(sim,probe,LARGE,2,[46,86],1,false))
	observations.append(_observe(sim,probe,LARGE,2,[47,86],0,false))
	# A private changed-body world cannot inherit the source's successful fit.
	var projected: WorldState = WorldState.new(sim.world.freeze())
	projected.facts.actors[FIRST].species_id = "S59"
	var projected_before: Dictionary = projected.freeze()
	sim.space.begin_route_query(projected,{},false)
	observations.append(_observe_world(sim.space,projected,suite.content,probe,FIRST,2,[48,86],1,false))
	sim.space.end_route_query()
	checks.private_world_unchanged = projected_before==projected.freeze()
	observations.append(_observe(sim,probe,FIRST,2,[49,86],0,true))
	sim.space.end_route_query()
	checks.source_world_and_rng_unchanged = original==sim.world.freeze()
	# Each following state is an independent legal route-calculation boundary;
	# no traversal, arrival or service completion is claimed by these inputs.
	sim.world.facts.actors[FIRST].species_id = "S59"
	sim.world.touch(false)
	sim.space.begin_route_query(sim.world,{},false)
	observations.append(_observe(sim,probe,FIRST,2,[46,82],1,false))
	sim.space.end_route_query()
	sim.world.facts.actors[FIRST].species_id = "S49"
	sim.world.touch(false)
	sim.space.begin_route_query(sim.world,{},false)
	observations.append(_observe(sim,probe,FIRST,2,[46,82],1,true))
	sim.space.end_route_query()
	var connection: Dictionary = sim.world.facts.connectors[suite._connection(sim)]
	connection.failed = true
	sim.world.touch(false)
	sim.space.begin_route_query(sim.world,{},false)
	observations.append(_observe(sim,probe,FIRST,2,[46,82],1,false))
	sim.space.end_route_query()
	sim.world.facts.actors[FIRST].location.floor_id = 2
	sim.world.touch(false)
	sim.space.begin_route_query(sim.world,{},false)
	observations.append(_observe(sim,probe,FIRST,1,[46,82],1,true))
	sim.space.end_route_query()
	checks.query_stack_closed = sim.space._route_queries.is_empty()
	var ok: bool = true
	for passed: bool in checks.values(): ok = ok and passed
	for observation: Dictionary in observations: ok = ok and observation.ok
	var result: Dictionary = {"ok":ok,"validation":validation,"checks":checks,"observations":observations,"compatibility_checks":probe.compatibility_checks,"scope":"Structural route calculations; actual queue, boarding and exit handoffs remain traffic acceptance cases."}
	sim.dispose()
	return result

func _observe(sim: HospitalSimulation, probe: FitProbe, actor_id: String, floor_id: int, goal: Array, expected_checks: int, expected_ok: bool, members: Array = [], offsets: Dictionary = {}) -> Dictionary:
	return _observe_world(sim.space,sim.world,sim.content,probe,actor_id,floor_id,goal,expected_checks,expected_ok,members,offsets)

func _observe_world(space: HospitalSpace, world: WorldState, content: HospitalContent, probe: FitProbe, actor_id: String, floor_id: int, goal: Array, expected_checks: int, expected_ok: bool, members: Array = [], offsets: Dictionary = {}) -> Dictionary:
	var before: Dictionary = world.freeze()
	var count: int = probe.compatibility_checks
	var actual: Dictionary = space.route(world,actor_id,floor_id,goal,members,offsets,true)
	# A new Space has no scope-shared compatibility or journey records. Compare
	# the complete production solver result, including executable floor segments.
	var cold: HospitalSpace = HospitalSpace.new(content)
	var expected: Dictionary = cold.route(world,actor_id,floor_id,goal,members,offsets,true)
	var delta: int = probe.compatibility_checks-count
	var ok: bool = actual==expected and bool(actual.ok)==expected_ok and delta==expected_checks and before==world.freeze()
	return {"ok":ok,"actor":actor_id,"members":members,"floor_id":floor_id,"goal":goal,"actual_available":actual.ok,"expected_available":expected_ok,"full_route_matches_independent_cold_solver":actual==expected,"new_compatibility_checks":delta,"expected_new_checks":expected_checks,"world_and_rng_unchanged":before==world.freeze(),"route":actual if not ok else {"status":actual.status,"travel_ticks":actual.get("travel_ticks",-1)}}
