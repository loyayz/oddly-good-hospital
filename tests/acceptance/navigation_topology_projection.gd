extends RefCounted

func run(suite: RefCounted) -> Dictionary:
	var projections: Dictionary = _independent_projections(suite)
	var changed: Dictionary = _changed_topology(suite)
	var without_connections: Dictionary = _without_connections(suite)
	return {"ok":projections.ok and changed.ok and without_connections.ok,"independent_projections":projections,"changed_topology":changed,"without_connections":without_connections}

# Projection inputs keep floor/connector owners and replace only the actor's
# own record. S49 fits VC02; S59 exceeds its 2.7 m width and 3.2 m height.
func _projection(world: WorldState, species_id: String, cell: Array) -> WorldState:
	var facts: Dictionary = world.facts.duplicate()
	facts.actors = world.facts.actors.duplicate()
	facts.actors["projection_subject"] = world.facts.actors["projection_subject"].duplicate(true)
	facts.actors["projection_subject"].species_id = species_id
	facts.actors["projection_subject"].location.cell = cell.duplicate()
	facts.adaptations = world.facts.adaptations.duplicate()
	return WorldState.new(facts)

func _quote(sim: HospitalSimulation, projected: WorldState, floor_id: int, cell: Array) -> Dictionary:
	sim.space.begin_route_query(projected)
	var result: Dictionary = sim.space.travel_quote(projected,"projection_subject",floor_id,cell)
	sim.space.end_route_query()
	return result

func _counts(sim: HospitalSimulation) -> Dictionary:
	return {"builds":int(sim.space.query_counts.connector_topology_builds),"nodes":int(sim.space.query_counts.get("connector_node_declarations",0))}

func _independent_projections(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	suite._add_actor(sim,"projection_subject","S49",[44,84])
	# Force only the rebuildable topology cache cold. The first projection must
	# build its original owner's declarations once, then inherit that result.
	sim.space.navigation._topologies.clear()
	var before: Dictionary = sim.world.freeze()
	var cold: Dictionary = _counts(sim)
	var small: WorldState = _projection(sim.world,"S49",[44,84])
	var large: WorldState = _projection(sim.world,"S59",[48,84])
	var small_before: Dictionary = small.freeze()
	var large_before: Dictionary = large.freeze()
	sim.space.prepare_projection(sim.world,small)
	var first: Dictionary = _counts(sim)
	sim.space.prepare_projection(sim.world,large)
	var small_quote: Dictionary = _quote(sim,small,2,[44,84])
	var large_quote: Dictionary = _quote(sim,large,2,[44,84])
	var small_again: Dictionary = _quote(sim,small,2,[44,84])
	var independent: bool = small_quote.get("ok",false) and not large_quote.get("ok",true) and small_again.get("ok",false) and int(small_again.get("travel_ticks",-1))==int(small_quote.get("travel_ticks",-2))
	var original: Dictionary = sim.space.navigation._topology(sim.world)
	var small_entry: Dictionary = sim.space.navigation._topologies.get(small.get_instance_id(),{})
	var large_entry: Dictionary = sim.space.navigation._topologies.get(large.get_instance_id(),{})
	var own_identity: bool = not small_entry.is_empty() and not large_entry.is_empty() and small_entry.world.get_ref()==small and large_entry.world.get_ref()==large and int(small_entry.get("revision",-1))==small.geometry_revision and int(large_entry.get("revision",-1))==large.geometry_revision
	var shared: bool = is_same(small_entry.get("nodes"),original.nodes) and is_same(large_entry.get("stops"),original.stops) and is_same(small_entry.get("extra_floors"),large_entry.get("extra_floors"))
	var repeated: bool = true
	var readonly: bool = before==sim.world.freeze() and small_before==small.freeze() and large_before==large.freeze()
	for index: int in 16:
		var projected: WorldState = _projection(sim.world,"S49",[44+index%4,84])
		var projected_before: Dictionary = projected.freeze()
		sim.space.prepare_projection(sim.world,projected)
		repeated = _quote(sim,projected,2,[44,84]).get("ok",false) and repeated
		readonly = projected_before==projected.freeze() and readonly
	var after: Dictionary = _counts(sim)
	var one_build: bool = int(first.builds)-int(cold.builds)==1 and int(first.nodes)>int(cold.nodes)
	var reused: bool = after==first
	readonly = before==sim.world.freeze() and readonly
	sim.dispose()
	return {"ok":independent and own_identity and shared and repeated and readonly and one_build and reused,"body_results_independent":independent,"each_projection_has_own_identity":own_identity,"structural_declarations_shared":shared,"cold_owner_built_once":one_build,"occupancy_projections_do_not_redeclare":reused,"all_projection_routes_reachable":repeated,"facts_unchanged":readonly,"cold":cold,"after_first":first,"after_repeated":after,"small_quote":small_quote,"large_quote":large_quote}

func _changed_topology(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	suite._history_height(sim,3)
	suite._add_actor(sim,"projection_subject","S49",[44,84])
	var old_projection: WorldState = _projection(sim.world,"S49",[44,84])
	sim.space.prepare_projection(sim.world,old_projection)
	var old_quote: Dictionary = _quote(sim,old_projection,3,[44,84])
	var old_nodes: Dictionary = sim.space.navigation._topology(sim.world).nodes
	var changed: CommandResult = suite._command(sim,"connector_extend",{"connection_id":suite._connection(sim),"floor_id":3})
	if not changed.accepted:
		sim.dispose()
		return {"ok":false,"extension":changed.to_record(),"before_extension_quote":old_quote}
	var before: Dictionary = sim.world.freeze()
	var projected: WorldState = _projection(sim.world,"S49",[44,84])
	var projected_before: Dictionary = projected.freeze()
	sim.space.prepare_projection(sim.world,projected)
	var quote: Dictionary = _quote(sim,projected,3,[44,84])
	var current: Dictionary = sim.space.navigation._topology(sim.world)
	var entry: Dictionary = sim.space.navigation._topologies.get(projected.get_instance_id(),{})
	var fresh: bool = not is_same(old_nodes,current.nodes) and is_same(entry.get("nodes"),current.nodes) and current.nodes.has(suite._connection(sim)+":3")
	var readonly: bool = before==sim.world.freeze() and projected_before==projected.freeze()
	sim.dispose()
	return {"ok":not old_quote.get("ok",true) and quote.get("ok",false) and fresh and readonly,"new_stop_reachable":quote.get("ok",false),"old_stop_set_not_reused":fresh,"facts_unchanged":readonly,"before_extension_quote":old_quote,"after_extension_quote":quote,"extension":changed.to_record()}

func _without_connections(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"projection_subject","S49",[40,84])
	sim.space.navigation._topologies.clear()
	var before: Dictionary = sim.world.freeze()
	var cold: Dictionary = _counts(sim)
	var all_reached: bool = true
	var readonly: bool = true
	for index: int in 8:
		var projected: WorldState = _projection(sim.world,"S49",[40+index%2,84])
		var projected_before: Dictionary = projected.freeze()
		sim.space.prepare_projection(sim.world,projected)
		all_reached = _quote(sim,projected,1,[44,84]).get("ok",false) and all_reached
		readonly = projected_before==projected.freeze() and readonly
	var after: Dictionary = _counts(sim)
	var no_topology: bool = cold==after and sim.space.navigation._topologies.is_empty()
	readonly = before==sim.world.freeze() and readonly
	sim.dispose()
	return {"ok":all_reached and readonly and no_topology,"direct_routes_reachable":all_reached,"no_connector_declarations":no_topology,"facts_unchanged":readonly,"before":cold,"after":after}
