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
	return {"ok":ok and evicted and invalidated and order.ok,"validation":validation,"observations":observations,"geometry_refresh_and_eviction":invalidated and evicted,"static_hits":space.query_counts.static_path_hits,"fit_failure_order":order}

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
