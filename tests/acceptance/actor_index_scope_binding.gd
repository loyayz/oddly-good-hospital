extends RefCounted

const ACTOR: String = "binding_primary"
const OTHER: String = "binding_other"

class ScopeProbe extends HospitalSpace:
	var lookups: int = 0
	func _actor_index_scope(world: WorldState) -> Dictionary:
		lookups += 1
		return super._actor_index_scope(world)

func run_case(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	suite._add_actor(sim,ACTOR,"S49",[44,80])
	suite._add_actor(sim,OTHER,"S49",[50,88])
	var world: WorldState = sim.world
	var space: ScopeProbe = ScopeProbe.new(suite.content)
	var before: Dictionary = world.freeze()
	var checks: Dictionary = {}
	space._ensure_actor_index(world)
	var original: BodyIndex.Record = space._actor_index._records[ACTOR]
	var lookups: int = space.lookups
	for _query: int in 8: space._ensure_actor_index(world)
	checks.equal_world_without_scope_does_not_lookup_or_rebuild = space.lookups==lookups and space.query_counts.actor_index_builds==1 and space._actor_index._records[ACTOR]==original
	space.begin_route_query(world)
	space._ensure_actor_index(world)
	checks.new_scope_binds_current_index_once = space.lookups==lookups+1 and not space._indexed_actor_scope.is_empty() and space.query_counts.actor_index_builds==1
	lookups = space.lookups
	var binding: Dictionary = space._indexed_actor_scope
	space.begin_route_query(world)
	for _query: int in 8: space._ensure_actor_index(world)
	checks.bound_parent_and_child_do_not_rebind = space.lookups==lookups and is_same(space._indexed_actor_scope,binding)
	var facts: Dictionary = world.facts.duplicate()
	facts.adaptations = world.facts.adaptations.duplicate(true)
	var shared: WorldState = WorldState.new(facts)
	space._ensure_actor_index(shared)
	space._ensure_actor_index(world)
	checks.shared_actor_projection_keeps_original_handoff = space.lookups==lookups+2 and space.query_counts.actor_index_builds==1 and space._actor_index._records[ACTOR]==original and is_same(space._indexed_actor_scope,binding)
	space.end_route_query()
	space.end_route_query()
	checks.closing_owner_clears_binding = space._indexed_actor_scope.is_empty() and space._route_queries.is_empty()
	# Explicit refresh must still accept unannounced input changes. It cannot
	# use either the no-scope fast path or a previous batch's owner binding.
	var original_location: Dictionary = world.facts.actors[ACTOR].location.duplicate(true)
	world.facts.actors[ACTOR].location.cell[0] += 0.25
	space.begin_dynamic_route_query(world,true)
	var refreshed: BodyIndex.Record = space._actor_index._records[ACTOR]
	checks.explicit_force_refreshes_current_body = refreshed!=original and space.query_counts.actor_index_builds==2 and refreshed.rect==space.body_rectangle(world.facts.actors[ACTOR])
	lookups = space.lookups
	for _query: int in 8: space._ensure_actor_index(world)
	checks.forced_batch_binds_once = space.lookups==lookups
	var private_facts: Dictionary = world.facts.duplicate()
	private_facts.actors = world.facts.actors.duplicate()
	private_facts.actors[OTHER] = world.facts.actors[OTHER].duplicate(true)
	private_facts.actors[OTHER].location = {"kind":"outside"}
	var projected: WorldState = WorldState.new(private_facts)
	var other_bounds: Rect2 = space.body_rectangle(world.facts.actors[OTHER])
	space.begin_actor_exclusion_query(world,projected,[OTHER])
	lookups = space.lookups
	space._ensure_actor_index(projected)
	var blocked: String = space._blocking_actor(projected,1,other_bounds,[])
	checks.private_departure_uses_exclusion_contract = blocked.is_empty() and space.lookups==lookups and space.query_counts.actor_index_builds==2 and space._indexed_world==world and space._actor_index._records[ACTOR]==refreshed
	space.end_route_query()
	space.end_route_query()
	space._ensure_actor_index(projected)
	checks.outside_scope_private_world_rebuilds = space.query_counts.actor_index_builds==3 and not space._actor_index._records.has(OTHER) and space._indexed_actor_scope.is_empty()
	world.facts.actors[ACTOR].location = original_location
	checks.readonly_queries_leave_world_and_rng_unchanged = world.freeze()==before and space._route_queries.is_empty()
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"owner_lookups":space.lookups,"actual_rebuilds":space.query_counts.actor_index_builds}
	sim.dispose()
	return result
