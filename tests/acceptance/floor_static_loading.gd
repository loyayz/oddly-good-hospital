extends RefCounted

class LimitedCache extends NavigationCache:
	var small: bool = false
	func _trim(target: int, counts: Dictionary = {}) -> void:
		super._trim(1 if small else target,counts)

# Reproduce pressure arising specifically inside a grouped query's member
# construction, after clearance() already acquired its graph/owner record.
class MemberPressureCache extends NavigationCache:
	var armed: bool = false
	var pressure: bool = false
	func floor_geometry(space: HospitalSpace, world: WorldState, floor_id: int, supplied: Dictionary = {}) -> FloorStaticGeometry:
		if armed: pressure = true
		return super.floor_geometry(space,world,floor_id,supplied)
	func _trim(target: int, counts: Dictionary = {}) -> void:
		super._trim(1 if pressure else target,counts)

func run_case(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	suite._history_height(sim,10000)
	var chair: CommandResult = suite._command(sim,"build_facility",{"id":"static_chair","definition_id":"SE02","floor_id":1,"cell":[43,75]})
	var room: CommandResult = suite._command(sim,"build_room",suite._room("static_room",[42,68],[10,5]))
	suite._add_actor(sim,"floor_load_walker","S49",[44,80])
	suite._add_actor(sim,"floor_load_wide","S06",[35,85])
	sim.world.facts.actors.floor_load_wide.body_binding_id = "B_S06_D04_M04"
	sim.world.touch()
	# Test the new owner's cold caches, not incidental construction queries.
	sim.space = HospitalSpace.new(suite.content)
	sim.space._navigation = LimitedCache.new()
	var world: WorldState = sim.world
	var space: HospitalSpace = sim.space
	var cache: LimitedCache = space._navigation
	var actor: Dictionary = world.facts.actors.floor_load_walker
	var before: Dictionary = world.freeze()
	var checks: Dictionary = {"valid_input":world.validate(suite.content).is_empty() and chair.accepted and room.accepted}
	var first: Dictionary = sim.prepare_floor_static(1)
	# Public-arrival preparation also reads body dimensions. That dictionary
	# is not an A* graph; raw floor preparation must still create no body graph.
	checks.only_displayed_floor_no_body_graphs = first.complete and cache._sources.size()==1 and cache._floor_geometries.size()==1 and cache._entries.is_empty()
	var one: FloorStaticGeometry = cache.floor_geometry(space,world,1)
	checks.complete_floor = one._plots.size()==HospitalSpace.floor_plots(world,1).size() and one.doors.size()==HospitalSpace.floor_layout(world,1).get("doors",[]).size() and one._facilities.size()==one.source.facilities.size() and one._connectors.size()==one.source.connectors.size() and one.facility_index._records.size()==one._facilities.size() and one.door_index._records.size()==one.doors.size() and one.wall_index._records.size()==one._walls.size()
	var second: Dictionary = sim.prepare_floor_static(2)
	var again: Dictionary = sim.prepare_floor_static(1)
	checks.whole_unoccupied_floor_and_return = second.complete and second.floor_id==2 and again.resident_hit and cache._sources.size()==2 and cache._floor_geometries.size()==2 and cache.floor_geometry(space,world,1)==one and cache._entries.is_empty()
	checks.preparation_preserves_facts_rng = before==world.freeze()
	# Derived body graphs share only raw static structures, not door fit/query state.
	var unit: FloorNavigation = cache.graph(space,world,1,actor,[],{})
	var wide: FloorNavigation = cache.graph(space,world,1,world.facts.actors.floor_load_wide,[],{})
	checks.body_graphs_share_only_raw_geometry = unit!=wide and is_same(unit.geometry._walls,wide.geometry._walls) and is_same(unit.geometry._facility_cells,one._facility_cells) and not is_same(unit.geometry._dependencies,wide.geometry._dependencies)
	# Explicit support/portal projections must never silently use canonical blocks.
	var isolated: bool = true
	for kind: String in ["facilities","connectors"]:
		var supplied: Dictionary = one.source.duplicate(true)
		if supplied[kind].is_empty(): isolated = false;continue
		var id: String = supplied[kind].keys()[0]
		supplied[kind].erase(id)
		var projected: FloorStaticGeometry = cache.floor_geometry(space,world,1,supplied)
		var query: RouteClearance = RouteClearance.new(space,world,actor,1,[],{},false,supplied)
		isolated = isolated and projected!=one and not projected.source[kind].has(id) and one.source[kind].has(id) and query.source==supplied and not query._dependencies.has(("facility:" if kind=="facilities" else "connector:")+id)
	checks.support_and_portal_exclusions_are_isolated = isolated and cache.floor_geometry(space,world,1)==one
	# Never displayed floors are still traversable through the ordinary route API.
	var lazy: HospitalSpace = HospitalSpace.new(suite.content)
	lazy._navigation.prepare_floor(lazy,world,1)
	var route: Dictionary = lazy.route(world,actor.id,2,[48,84],[],{},true)
	var cold: Dictionary = HospitalSpace.new(suite.content).route(world,actor.id,2,[48,84],[],{},true)
	checks.cross_floor_lazy_route_matches_cold = route.ok and route==cold and lazy._navigation._sources.size()<=3 and lazy._navigation._floor_geometries.size()<=3
	# Actual geometry edit invalidates the changed layer, not the other layer.
	var two: FloorStaticGeometry = cache.floor_geometry(space,world,2)
	world.facts.floors.overrides["1"].blocked.append([46,82])
	world.touch()
	var changed: FloorStaticGeometry = cache.floor_geometry(space,world,1)
	checks.edit_replaces_only_affected_floor_and_old_maps_stay_immutable = changed!=one and changed._blocked.has(Vector2i(46,82)) and not one._blocked.has(Vector2i(46,82)) and cache.floor_geometry(space,world,2)==two
	# Trimming while replacing a graph must not double-subtract its ownership.
	var target: int = int(suite.content.balance.pathfinding.graph_cache_target_bytes)
	cache.small = true
	var tiny: Dictionary = sim.prepare_floor_static(1)
	cache.graph(space,world,1,actor,[],{})
	checks.budget_eviction_is_complete_and_nonnegative = tiny.complete and not tiny.retained and cache._floor_geometries.is_empty() and cache._floor_charged==0 and cache._entries.is_empty() and cache._charged==0 and cache._query_charged==0 and cache._body_entries.is_empty() and cache.total_charge()==0
	cache.small = false
	var fallback: Dictionary = space.route(world,actor.id,2,[48,84],[],{},true)
	var expected: Dictionary = HospitalSpace.new(suite.content).route(world,actor.id,2,[48,84],[],{},true)
	checks.eviction_keeps_lazy_fallback = fallback.ok and fallback==expected and cache._floor_charged>0 and cache.total_charge()<=target
	var pressured: HospitalSpace = HospitalSpace.new(suite.content)
	var pressure_cache: MemberPressureCache = MemberPressureCache.new()
	pressured._navigation = pressure_cache
	var members: Array = [actor.id,"floor_load_wide"]
	var offsets: Dictionary = {actor.id:[0,0],"floor_load_wide":[1,0]}
	pressure_cache.clearance(pressured,world,1,actor,members,offsets)
	# Clear only the raw cache: the group graph and query owner stay resident.
	pressure_cache._floor_geometries.clear();pressure_cache._floor_charged = 0
	offsets["floor_load_wide"] = [2,0]
	pressure_cache.armed = true
	var under_pressure: RouteClearance = pressure_cache.clearance(pressured,world,1,actor,members,offsets)
	var independent: RouteClearance = RouteClearance.new(HospitalSpace.new(suite.content),world,actor,1,members,offsets)
	checks.group_member_trim_waits_for_publication = pressure_cache.pressure and pressure_cache._entries.is_empty() and pressure_cache._query_charged==0 and pressure_cache._charged==0 and pressure_cache._floor_charged==0 and pressure_cache._body_entries.is_empty() and pressure_cache.total_charge()==0 and under_pressure.reason(Vector2i(40,85))==independent.reason(Vector2i(40,85))
	before = world.freeze()
	var loaded: HospitalSimulation = HospitalSimulation.new(WorldState.new(before.duplicate(true)),suite.content)
	var restored: Dictionary = loaded.prepare_floor_static(2)
	checks.new_owner_loads_selected_floor_only = restored.complete and not restored.resident_hit and loaded.space._navigation._sources.size()==1 and loaded.space._navigation._entries.is_empty() and loaded.world.freeze()==before
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"first":first,"second":second,"again":again,"tiny":tiny,"restored":restored,"route":route,"final_validation":world.validate(suite.content)}
	result.ok = result.ok and result.final_validation.is_empty()
	loaded.dispose();sim.dispose()
	return result
