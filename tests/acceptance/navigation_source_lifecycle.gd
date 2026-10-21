extends RefCounted

const ACTOR: String = "source_lifecycle_actor"

class SourceProbe extends NavigationCache:
	var refreshes: int = 0
	func floor_source(space: HospitalSpace, world: WorldState, floor_id: int) -> Dictionary:
		# This is the production capture branch's entry condition, observed
		# before calling it. It counts fresh source collection, not getter calls.
		var entry: Dictionary = _sources.get(str(world.get_instance_id())+":"+str(floor_id),{})
		if entry.is_empty() or entry.world.get_ref()!=world or entry.revision!=world.geometry_revision: refreshes += 1
		return super.floor_source(space,world,floor_id)

func _versions(cache: NavigationCache, space: HospitalSpace, world: WorldState) -> Dictionary:
	var result: Dictionary = {}
	for floor_id: int in [1,2,3,4]: result[floor_id] = cache.floor_static_version(space,world,floor_id)
	return result

func _temporary_source(cache: NavigationCache, space: HospitalSpace, facts: Dictionary) -> WeakRef:
	var temporary: WorldState = WorldState.new(facts.duplicate(true))
	cache.floor_static_version(space,temporary,3)
	return weakref(temporary)

func run_case(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	suite._history_height(sim,4)
	var checks: Dictionary = {}
	var extended: bool = true
	for floor_id: int in [3,4]:
		var result: CommandResult = suite._command(sim,"connector_extend",{"connection_id":suite._connection(sim),"floor_id":floor_id})
		extended = extended and result.accepted
	for floor_id: int in [2,3,4]: HospitalSpace.materialize_layout(sim.world,floor_id)
	suite._add_actor(sim,ACTOR,"S49",[44,80])
	var world: WorldState = sim.world
	var space: HospitalSpace = HospitalSpace.new(suite.content)
	var cache: SourceProbe = SourceProbe.new()
	space._navigation = cache
	var validation: String = world.validate(suite.content)
	checks.legal_four_floor_input = extended and validation.is_empty()
	checks.starts_without_any_graph = cache._entries.is_empty()
	var before: Dictionary = world.freeze()
	var initial: Dictionary = _versions(cache,space,world)
	var initial_source_version: int = cache._source_version
	var initial_static_version: int = cache._static_source_version
	var stable: bool = true
	for _round: int in 5: stable = stable and _versions(cache,space,world)==initial
	checks.cold_four_floor_poll_captures_only_first_four_sources = stable and cache.refreshes==4 and cache._source_version==initial_source_version and cache._static_source_version==initial_static_version and cache._sources.size()==4 and cache._entries.is_empty() and world.freeze()==before
	world.facts.floors.overrides["2"].blocked.append([46,82])
	world.touch()
	before = world.freeze()
	var changed: Dictionary = _versions(cache,space,world)
	checks.one_real_floor_edit_changes_only_that_static_identity = changed[2]!=initial[2] and changed[1]==initial[1] and changed[3]==initial[3] and changed[4]==initial[4] and cache._source_version==initial_source_version+1 and cache._static_source_version==initial_static_version+1 and cache.refreshes==8 and cache._sources.size()==4 and before==world.freeze()
	var refreshes: int = cache.refreshes
	cache._trim(1)
	cache._prune_sources()
	checks.cold_pruning_keeps_live_sources_without_graphs = _versions(cache,space,world)==changed and cache.refreshes==refreshes and cache._sources.size()==4 and cache._entries.is_empty()
	var move: Dictionary = _active_path(sim,space,cache)
	checks.real_multifloor_path_proof = move.ok
	var current: Dictionary = _versions(cache,space,world)
	var actor: Dictionary = world.facts.actors[ACTOR]
	before = world.freeze()
	cache.graph(space,world,1,actor,[],{})
	var built: bool = not cache._entries.is_empty()
	var proof_keys: Array = cache._entries.keys()
	var proof_present: bool = false
	for record: Dictionary in cache._sources.values():
		for key: String in proof_keys: proof_present = proof_present or record.graphs.has(key)
	cache._trim(1)
	var evicted: bool = cache._entries.is_empty() and cache._charged==0 and cache._query_charged==0
	var proofs_removed: bool = true
	for record: Dictionary in cache._sources.values():
		for key: String in proof_keys: proofs_removed = proofs_removed and not record.graphs.has(key)
	checks.graph_eviction_discards_proof_keys_without_source_history = proof_present and proofs_removed
	refreshes = cache.refreshes
	checks.graph_eviction_does_not_revoke_source_identity = built and evicted and _versions(cache,space,world)==current and cache.refreshes==refreshes and cache._sources.size()==4 and before==world.freeze()
	var rebuilt: Dictionary = space.route(world,ACTOR,1,[48,84],[],{},true)
	var cold: HospitalSpace = HospitalSpace.new(suite.content)
	var expected: Dictionary = cold.route(world,ACTOR,1,[48,84],[],{},true)
	checks.route_after_eviction_matches_complete_cold_route = rebuilt==expected and rebuilt.ok and _versions(cache,space,world)==current and cache.refreshes==refreshes and before==world.freeze()
	var replaced_in_place: bool = true
	for _edit: int in 3:
		world.facts.floors.overrides["2"].blocked.append([47,82])
		world.touch()
		_versions(cache,space,world)
		replaced_in_place = replaced_in_place and cache._sources.size()==4
		world.facts.floors.overrides["2"].blocked.erase([47,82])
		world.touch()
		_versions(cache,space,world)
		replaced_in_place = replaced_in_place and cache._sources.size()==4
	checks.real_revisions_replace_world_floor_record_without_history = replaced_in_place
	var live: Dictionary = _versions(cache,space,world)
	var temporary: WeakRef = _temporary_source(cache,space,world.freeze())
	checks.source_records_do_not_retain_world_strongly = temporary.get_ref()==null and cache._sources.size()==5
	cache._prune_sources()
	checks.dead_world_is_removed_and_live_versions_retained = cache._sources.size()==4 and _versions(cache,space,world)==live
	var final_validation: String = world.validate(suite.content)
	checks.final_input_still_valid = final_validation.is_empty()
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"validation":validation,"final_validation":final_validation,"initial_static_versions":initial,"after_single_edit":changed,"source_refreshes":cache.refreshes,"live_source_records":cache._sources.size(),"multifloor_active_path":move}
	sim.dispose()
	return result

func _active_path(sim: HospitalSimulation, space: HospitalSpace, cache: SourceProbe) -> Dictionary:
	var world: WorldState = sim.world
	# The real movement owner requests and dispatches this complete journey.
	# Its graphs are independent of the tested cache, which stays graph-free.
	var request: String = sim.space.request_move(world,ACTOR,4,[48,84])
	sim.space.movement._dispatch_routes(world,world.present_actor_count())
	var movement: Dictionary = world.facts.moves.get(ACTOR,{})
	if not request.is_empty() or movement.get("route_pending",true) or movement.get("path",[]).is_empty():
		return {"ok":false,"request":request,"pending":movement.get("route_pending",true),"reason":movement.get("waiting_reason","")}
	var actor: Dictionary = world.facts.actors[ACTOR]
	var floors: Dictionary = {}
	for segment: Dictionary in movement.path:
		if segment.kind=="floor": floors[int(segment.floor_id)] = true
	var before: Dictionary = world.freeze()
	var accepted: bool = space.movement._active_route_clear(world,actor,movement,{})
	var revalidations: int = int(space.query_counts.route_revalidations)
	var refreshes: int = cache.refreshes
	var unchanged: bool = accepted
	for _round: int in 5:
		_versions(cache,space,world)
		unchanged = unchanged and space.movement._active_route_clear(world,actor,movement,{})
	var stable: bool = unchanged and floors.size()>=2 and revalidations==1 and int(space.query_counts.route_revalidations)==revalidations and cache.refreshes==refreshes and cache._entries.is_empty() and before==world.freeze()
	world.facts.floors.overrides["4"].blocked.append([48,84])
	world.touch()
	before = world.freeze()
	var blocked: bool = not space.movement._active_route_clear(world,actor,movement,{})
	var blocked_readonly: bool = before==world.freeze()
	world.facts.floors.overrides["4"].blocked.erase([48,84])
	world.touch()
	before = world.freeze()
	var restored: bool = space.movement._active_route_clear(world,actor,movement,{})
	var after_restore: int = int(space.query_counts.route_revalidations)
	var hit: bool = space.movement._active_route_clear(world,actor,movement,{})
	return {"ok":stable and blocked and blocked_readonly and restored and hit and after_restore==3 and int(space.query_counts.route_revalidations)==after_restore and cache._entries.is_empty() and before==world.freeze(),"real_requested_path_floors":floors.keys(),"five_unchanged_checks_add_no_revalidation":stable,"real_goal_block_rejected":blocked,"restored_path_accepted":restored,"revalidations_including_block_and_restore":after_restore,"no_graph_built_for_proof":cache._entries.is_empty()}
