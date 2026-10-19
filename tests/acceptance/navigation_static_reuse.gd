extends RefCounted

const OWNER: String = "permission_owner"
const STAFF: String = "permission_staff"
const OTHER: String = "permission_other"
const PEER: String = "permission_peer"

func run_case(sim: HospitalSimulation, content: HospitalContent) -> Dictionary:
	var built: CommandResult = sim.apply(GameCommand.new("permissions_second",sim.world.hospital_id,sim.world.revision,"build_facility",BusinessPayload.new({"id":"permissions_second","definition_id":"M37","floor_id":1,"cell":[46,76]})))
	if not built.accepted: return {"ok":false,"build":built.to_record()}
	var reserved: String = sim.space.reserve_facility(sim.world,"permissions_second",OTHER,OTHER)
	if not reserved.is_empty(): return {"ok":false,"reservation":reserved}
	var world: WorldState = WorldState.new(sim.world.freeze())
	world.facts.actors[PEER].species_id = "S53"
	world.touch()
	var validation: String = world.validate(content)
	var space: HospitalSpace = HospitalSpace.new(content)
	var actor: Dictionary = world.facts.actors[PEER]
	var observations: Array = []
	var ok: bool = validation.is_empty()
	var previous: RouteClearance
	for pass_id: int in 5:
		if pass_id==1:
			# Insertion order, rather than sorted facility identity, chooses the
			# first failure when a large body's rectangle intersects both areas.
			var reversed: Dictionary = {}
			var ids: Array = world.facts.adaptations.keys()
			ids.reverse()
			for id: String in ids: reversed[id] = world.facts.adaptations[id]
			world.facts.adaptations = reversed
		elif pass_id==2:
			space.grant_facility_access(world,"permissions_second",STAFF)
		elif pass_id==3:
			space.grant_facility_access(world,"permissions_second",PEER)
		elif pass_id==4:
			# Existing arrays may change in place. A retained signature must own
			# its snapshot rather than follow this mutable facts array.
			world.facts.adaptations.permissions_machine.regions[0][0] += 0.25
		world.touch()
		var before: Dictionary = world.freeze()
		space.begin_route_query(world)
		var query: RouteClearance = space._navigation.clearance(space,world,1,actor)
		var cold: RouteClearance = RouteClearance.new(HospitalSpace.new(content),world,actor,1)
		var equal: bool = true
		for id: int in FloorNavigation.LIMIT:
			var cell: Vector2i = FloorNavigation._cell(id)
			equal = equal and query.reason(cell)==cold.reason(cell)
		var identity_ok: bool = previous==null or (query==previous if pass_id==2 else query!=previous)
		var endpoints: Array = [[Vector2i(38,86),Vector2i(40,90)],[Vector2i(38,86),Vector2i(42,78)]]
		var paths_equal: bool = true
		for pair: Array in endpoints:
			var graph: FloorNavigation = space._navigation.graph(space,world,1,actor,[],{})
			var expected: Dictionary = graph.find_path(pair[0],pair[1],cold)
			var first: Dictionary = space._navigation.cached_floor_path(space,world,1,actor,graph,query,pair[0],pair[1])
			var retained: Dictionary = first.duplicate(true)
			if first.has("cells") and not first.cells.is_empty(): first.cells[0][0] = -900
			var hit: Dictionary = space._navigation.cached_floor_path(space,world,1,actor,graph,query,pair[0],pair[1])
			paths_equal = paths_equal and retained==expected and hit==expected
			var field: Dictionary = {}
			for count: int in 13: field = space._navigation.forward_distance(space,world,1,actor,pair[0],pair[1])
			paths_equal = paths_equal and field.ready and field.ok==expected.ok and field.reason==expected.reason
			if expected.ok: paths_equal = paths_equal and int(field.distance)==int(expected.walking_distance)
		space.end_route_query()
		ok = ok and equal and identity_ok and paths_equal and before==world.freeze()
		observations.append({"pass":pass_id,"all_9216_reasons_cold_equal":equal,"query_identity_correct":identity_ok,"full_paths_fields_and_owned_result":paths_equal,"readonly":before==world.freeze()})
		previous = query
	# Geometry refresh and complete eviction cannot retain an old path/query.
	world.facts.floors.overrides["1"].blocked.append([40,90])
	world.touch()
	var changed: Dictionary = _path(space,world,actor)
	var cold_changed: Dictionary = _path(HospitalSpace.new(content),world,actor)
	space._navigation._trim(0)
	var evicted: bool = space._navigation._entries.is_empty() and space._navigation._charged==0 and space._navigation._query_charged==0
	var rebuilt: Dictionary = _path(space,world,actor)
	var invalidated: bool = not changed.ok and changed==cold_changed and rebuilt==cold_changed
	var order: Dictionary = _fit_order(sim.world.freeze(),content)
	var bodies: Dictionary = _actor_scope(sim.world.freeze(),content)
	var points: Dictionary = _point_checks(sim.world.freeze(),content)
	return {"ok":ok and evicted and invalidated and order.ok and bodies.ok and points.ok,"validation":validation,"observations":observations,"geometry_refresh_and_eviction":invalidated and evicted,"static_hits":space.query_counts.static_path_hits,"fit_failure_order":order,"actor_scope":bodies,"point_checks":points}

func _point_checks(source: Dictionary, content: HospitalContent) -> Dictionary:
	var world: WorldState = WorldState.new(source.duplicate(true))
	var actor: Dictionary = world.facts.actors[PEER]
	var space: HospitalSpace = HospitalSpace.new(content)
	var cold: RouteClearance = RouteClearance.new(HospitalSpace.new(content),world,actor,1)
	var point: Vector2i = Vector2i(38,86)
	var no_build: bool = space._navigation.cached_static_geometry(space,world,1,actor)==null and space.static_reason(world,actor,1,point)==cold.reason(point) and space._navigation._entries.is_empty()
	var ok: bool = no_build
	var observations: Array = []
	var old_geometry: RouteClearance
	for pass_id: int in 3:
		if pass_id==1: space.grant_facility_access(world,"permissions_second",PEER)
		if pass_id==2:
			world.facts.floors.overrides["1"].blocked.append([38,86])
			world.touch()
			ok = ok and space._navigation.cached_static_geometry(space,world,1,actor)==null and not space.static_reason(world,actor,1,point).is_empty()
		space._navigation.graph(space,world,1,actor,[],{})
		var geometry: RouteClearance = space._navigation.cached_static_geometry(space,world,1,actor)
		var identity_ok: bool = geometry!=null and (pass_id!=1 or geometry==old_geometry) and (pass_id!=2 or geometry!=old_geometry)
		cold = RouteClearance.new(HospitalSpace.new(content),world,actor,1)
		var before: Dictionary = world.freeze()
		var equal: bool = true
		for id: int in FloorNavigation.LIMIT:
			var cell: Vector2i = FloorNavigation._cell(id)
			equal = equal and space.static_reason(world,actor,1,cell)==cold.reason(cell)
		ok = ok and identity_ok and equal and before==world.freeze()
		observations.append({"pass":pass_id,"all_9216_reasons_equal":equal,"geometry_identity":identity_ok,"readonly":before==world.freeze()})
		old_geometry = geometry
	space._navigation._trim(0)
	var after_eviction: bool = space._navigation.cached_static_geometry(space,world,1,actor)==null and space.static_reason(world,actor,1,point)==cold.reason(point) and space._navigation._entries.is_empty()
	return {"ok":ok and after_eviction,"cold_does_not_build_astar":no_build,"observations":observations,"evicted_fallback":after_eviction}

func _actor_scope(source: Dictionary, content: HospitalContent) -> Dictionary:
	var world: WorldState = WorldState.new(source.duplicate(true))
	var facts: Dictionary = world.facts.duplicate()
	facts.adaptations = world.facts.adaptations.duplicate(true)
	facts.adaptations.permissions_second.staff_ids.append(STAFF)
	var projected: WorldState = WorldState.new(facts)
	var before: Dictionary = world.freeze()
	var space: HospitalSpace = HospitalSpace.new(content)
	space.begin_route_query(world)
	space._ensure_actor_index(world)
	var original: BodyIndex.Record = space._actor_index._records[PEER]
	space._route_checks.sentinel = true
	space._ensure_actor_index(projected)
	var shared: bool = space._actor_index._records[PEER]==original and space._route_checks.is_empty()
	space._ensure_actor_index(world)
	shared = shared and space._actor_index._records[PEER]==original
	space.begin_route_query(projected)
	space._ensure_actor_index(projected)
	space.end_route_query()
	shared = shared and space._actor_index._records[PEER]==original and not space._indexed_actor_scope.is_empty()
	space.end_route_query()
	var released: bool = space._indexed_actor_scope.is_empty() and world.freeze()==before
	# After a scope closes, the old C -> W world switch must still rebuild,
	# even if no revision changed between those two diagnostic input states.
	world.facts.actors[PEER].location.cell[0] += 0.25
	space._ensure_actor_index(world)
	var outside: BodyIndex.Record = space._actor_index._records[PEER]
	var rebuilt: bool = outside!=original and _bodies_cold_equal(space,world,content)
	space.begin_route_query(world)
	space._ensure_actor_index(world)
	space._ensure_actor_index(projected)
	var next_scope: bool = space._actor_index._records[PEER]==outside
	# A private projected actor changes physical geometry. Sharing unrelated
	# records inside its actors map does not authorize sharing the whole index.
	var private_facts: Dictionary = world.facts.duplicate()
	private_facts.actors = world.facts.actors.duplicate()
	private_facts.actors[PEER] = world.facts.actors[PEER].duplicate()
	private_facts.actors[PEER].location = world.facts.actors[PEER].location.duplicate(true)
	private_facts.actors[PEER].location.cell[0] += 1.0
	var private_world: WorldState = WorldState.new(private_facts)
	space.begin_route_query(private_world)
	space._ensure_actor_index(private_world)
	var isolated: bool = space._actor_index._records[PEER]!=outside and _bodies_cold_equal(space,private_world,content)
	space.end_route_query()
	space._ensure_actor_index(world)
	var forced_before: BodyIndex.Record = space._actor_index._records[PEER]
	space.begin_dynamic_route_query(world,true)
	var forced: bool = space._actor_index._records[PEER]!=forced_before and _bodies_cold_equal(space,world,content)
	space.end_route_query()
	space.end_route_query()
	return {"ok":shared and released and rebuilt and next_scope and isolated and forced and space._indexed_actor_scope.is_empty(),"same_scope_shared":shared,"scope_owner_released":released,"outside_scope_rebuilt":rebuilt,"next_scope_current_bodies":next_scope,"private_actor_map_isolated":isolated,"forced_refresh":forced}

func _bodies_cold_equal(space: HospitalSpace, world: WorldState, content: HospitalContent) -> bool:
	var cold: HospitalSpace = HospitalSpace.new(content)
	cold._ensure_actor_index(world)
	if space._actor_index._records.keys()!=cold._actor_index._records.keys(): return false
	for id: String in cold._actor_index._records:
		var actual: BodyIndex.Record = space._actor_index._records[id]
		var expected: BodyIndex.Record = cold._actor_index._records[id]
		if actual.floor_id!=expected.floor_id or actual.rect!=expected.rect: return false
	return true

func _path(space: HospitalSpace, world: WorldState, actor: Dictionary) -> Dictionary:
	return space._floor_route(world,actor,1,Vector2i(38,86),Vector2i(40,90),[],{},true)

func _fit_order(source: Dictionary, content: HospitalContent) -> Dictionary:
	var world: WorldState = WorldState.new(source.duplicate(true))
	var layout: Dictionary = HospitalSpace.new(content).facility_layout(world,"permissions_machine")
	# The later repair area fails static geometry while the earlier patient
	# area is still reserved for OWNER. A geometry-only warm-up cannot move
	# that later failure ahead of the earlier dynamic reservation failure.
	world.facts.floors.overrides["1"].blocked.append(layout.repair_cell.duplicate())
	world.touch()
	var before: Dictionary = world.freeze()
	var expected: Dictionary = HospitalSpace.new(content).facility_preflight_quote(world,"permissions_machine",OTHER)
	var observations: Array = []
	var ok: bool = not expected.ok
	for warm_first: bool in [false,true]:
		var space: HospitalSpace = HospitalSpace.new(content)
		space.begin_route_query(world)
		var nominal: Dictionary = {}
		if warm_first: nominal = space.facility_geometry_quote(world,"permissions_machine",OTHER)
		var actual: Dictionary = space.facility_preflight_quote(world,"permissions_machine",OTHER)
		if not warm_first: nominal = space.facility_geometry_quote(world,"permissions_machine",OTHER)
		var again: Dictionary = space.facility_preflight_quote(world,"permissions_machine",OTHER)
		space.end_route_query()
		var equal: bool = actual==expected and again==expected and not nominal.ok and nominal.reason!=expected.reason
		ok = ok and equal and before==world.freeze()
		observations.append({"geometry_first":warm_first,"full_dynamic_result_equal":equal,"actual_reason":actual.reason,"geometry_reason":nominal.reason})
	return {"ok":ok,"observations":observations,"readonly":before==world.freeze()}
