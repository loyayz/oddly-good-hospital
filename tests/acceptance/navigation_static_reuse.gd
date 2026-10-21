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
	var departures: Dictionary = _actor_departure_projection(sim.world.freeze(),content)
	var points: Dictionary = _point_checks(sim.world.freeze(),content)
	return {"ok":ok and evicted and invalidated and order.ok and bodies.ok and departures.ok and points.ok,"validation":validation,"observations":observations,"geometry_refresh_and_eviction":invalidated and evicted,"static_hits":space.query_counts.static_path_hits,"fit_failure_order":order,"actor_scope":bodies,"actor_departure_projection":departures,"point_checks":points}

func _point_checks(source: Dictionary, content: HospitalContent) -> Dictionary:
	var world: WorldState = WorldState.new(source.duplicate(true))
	var actor: Dictionary = world.facts.actors[PEER]
	var space: HospitalSpace = HospitalSpace.new(content)
	var cold: RouteClearance = RouteClearance.new(HospitalSpace.new(content),world,actor,1)
	var point: Vector2i = Vector2i(38,86)
	var no_build: bool = space._navigation.cached_static_geometry(space,world,1,actor)==null and space.static_reason(world,actor,1,point)==cold.reason(point) and space.static_reason(world,actor,1,point,[actor.id])==cold.reason(point) and space._navigation._entries.is_empty()
	var ok: bool = no_build
	var observations: Array = []
	var permissions: Array = []
	var owner_goal: Array = space.facility_layout(world,"permissions_machine").patient_cell
	var second_goal: Array = space.facility_layout(world,"permissions_second").patient_cell
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
		var identities_equal: bool = true
		for actor_id: String in [OWNER,STAFF,OTHER,PEER]:
			var subject: Dictionary = world.facts.actors[actor_id]
			var members: Array = [actor_id]
			var offsets: Dictionary = {actor_id:[0,0]}
			var independent: RouteClearance = RouteClearance.new(HospitalSpace.new(content),world,subject,1,members,offsets)
			var reasons: Array = []
			for target: Vector2i in [point,Vector2i(int(owner_goal[0]),int(owner_goal[1])),Vector2i(int(second_goal[0]),int(second_goal[1]))]:
				var expected: String = independent.reason(target)
				identities_equal = identities_equal and space.static_reason(world,subject,1,target,members,offsets)==expected
				space.begin_route_query(world)
				identities_equal = identities_equal and space.static_reason(world,subject,1,target,members,offsets)==expected
				space.end_route_query()
				reasons.append(expected)
			identities_equal = identities_equal and members==[actor_id] and offsets=={actor_id:[0,0]}
			if actor_id==OWNER: identities_equal = identities_equal and str(reasons[1]).is_empty()
			if actor_id==PEER: identities_equal = identities_equal and not str(reasons[1]).is_empty() and str(reasons[2]).is_empty()==(pass_id>0) and str(reasons[0]).is_empty()==(pass_id<2)
			permissions.append({"pass":pass_id,"actor":actor_id,"independent_reasons":reasons})
		ok = ok and identities_equal
		ok = ok and identity_ok and equal and before==world.freeze()
		observations.append({"pass":pass_id,"all_9216_reasons_equal":equal,"geometry_identity":identity_ok,"singleton_identity_and_scope_cold_equal":identities_equal,"readonly":before==world.freeze()})
		old_geometry = geometry
	space._navigation._trim(0)
	var after_eviction: bool = space._navigation.cached_static_geometry(space,world,1,actor)==null and space.static_reason(world,actor,1,point)==cold.reason(point) and space.static_reason(world,actor,1,point,[actor.id])==cold.reason(point) and space._navigation._entries.is_empty()
	# A different single member is still an additional body. Its offset must
	# remain effective, as must the complete two-person envelope after eviction.
	var grouped: WorldState = WorldState.new(source.duplicate(true))
	var primary: Dictionary = grouped.facts.actors[PEER]
	var group_space: HospitalSpace = HospitalSpace.new(content)
	var offset: int = group_space.clearance(primary)+1
	grouped.facts.floors.overrides["1"].blocked.append([point.x+offset,point.y])
	grouped.touch()
	var group_before: Dictionary = grouped.freeze()
	var group_offsets: Dictionary = {PEER:[0,0],OTHER:[offset,0]}
	var group_observations: Array = []
	var groups_equal: bool = true
	for temperature: String in ["cold","warm","evicted"]:
		if temperature=="warm": group_space._navigation.graph(group_space,grouped,1,primary,[],{})
		if temperature=="evicted": group_space._navigation._trim(0)
		var cached: RouteClearance = group_space._navigation.cached_static_geometry(group_space,grouped,1,primary)
		groups_equal = groups_equal and (cached!=null if temperature=="warm" else cached==null)
		for members: Array in [[],[PEER],[OTHER],[PEER,OTHER]]:
			var independent: RouteClearance = RouteClearance.new(HospitalSpace.new(content),grouped,primary,1,members,group_offsets)
			var expected: String = independent.reason(point)
			var actual: String = group_space.static_reason(grouped,primary,1,point,members,group_offsets)
			groups_equal = groups_equal and actual==expected and expected.is_empty()==(not OTHER in members)
			group_observations.append({"temperature":temperature,"members":members.duplicate(),"reason":actual,"cold_equal":actual==expected})
		if temperature!="warm": groups_equal = groups_equal and group_space._navigation._entries.is_empty()
	groups_equal = groups_equal and group_before==grouped.freeze() and group_offsets=={PEER:[0,0],OTHER:[offset,0]}
	return {"ok":ok and after_eviction and groups_equal,"cold_does_not_build_astar":no_build,"observations":observations,"singleton_permissions":permissions,"evicted_fallback":after_eviction,"different_member_and_full_group_cold_equal":groups_equal,"group_observations":group_observations}

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
	space.movement._route_checks.sentinel = true
	space._ensure_actor_index(projected)
	# A read-only projection may share this index. It cannot invalidate the
	# movement owner's real-world route checks merely by querying geometry.
	var shared: bool = space._actor_index._records[PEER]==original and space.movement._route_checks.get("sentinel",false)
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
	# Explicit refresh remains a force operation even below a dynamic parent.
	space.begin_dynamic_route_query(world,true)
	var dynamic_before: BodyIndex.Record = space._actor_index._records[PEER]
	space.begin_dynamic_route_query(world,true)
	var dynamic_forced: bool = space.in_dynamic_route_query(world) and space._actor_index._records[PEER]!=dynamic_before and _bodies_cold_equal(space,world,content)
	space.end_route_query()
	space.end_route_query()
	# The fresh owner exists before its first body query. A reservation-only
	# projection can be that first query without rebuilding the same bodies.
	space.begin_dynamic_route_query(world,true)
	var first_projection_record: BodyIndex.Record = space._actor_index._records[PEER]
	var first_projection_builds: int = int(space.query_counts.actor_index_builds)
	space.begin_route_query(projected,{},false)
	space._ensure_actor_index(projected)
	var first_projection_shared: bool = space._actor_index._records[PEER]==first_projection_record and int(space.query_counts.actor_index_builds)==first_projection_builds and _bodies_cold_equal(space,projected,content)
	space.end_route_query()
	space._ensure_actor_index(world)
	first_projection_shared = first_projection_shared and space._actor_index._records[PEER]==first_projection_record and int(space.query_counts.actor_index_builds)==first_projection_builds and _bodies_cold_equal(space,world,content)
	space.end_route_query()
	# Commit a real body update between two sealed enumerations. Reuse must
	# see this synchronization without requiring an unrelated world revision.
	world.facts.actors[PEER].location.cell[0] += 0.25
	space.sync_actor(world,PEER)
	var synchronized: BodyIndex.Record = space._actor_index._records[PEER]
	space.begin_dynamic_route_query(world,false)
	var incremental: bool = space._actor_index._records[PEER]==synchronized and _bodies_cold_equal(space,world,content)
	space.begin_route_query(private_world,{},false)
	space._ensure_actor_index(private_world)
	var dynamic_isolated: bool = space._actor_index._records[PEER]!=synchronized and _bodies_cold_equal(space,private_world,content)
	space.end_route_query()
	space._ensure_actor_index(world)
	dynamic_isolated = dynamic_isolated and _bodies_cold_equal(space,world,content)
	space.end_route_query()
	var closed: bool = space._route_queries.is_empty() and space._indexed_actor_scope.is_empty() and not space.in_dynamic_route_query(world)
	return {"ok":shared and released and rebuilt and next_scope and isolated and forced and dynamic_forced and first_projection_shared and incremental and dynamic_isolated and closed,"same_scope_shared":shared,"scope_owner_released":released,"outside_scope_rebuilt":rebuilt,"next_scope_current_bodies":next_scope,"private_actor_map_isolated":isolated,"forced_refresh":forced,"explicit_refresh_below_dynamic_parent":dynamic_forced,"first_shared_projection_uses_fresh_owner":first_projection_shared,"between_enumerations_body_sync_visible":incremental,"private_projection_under_dynamic_parent_isolated":dynamic_isolated,"all_query_scopes_released":closed}

func _bodies_cold_equal(space: HospitalSpace, world: WorldState, content: HospitalContent) -> bool:
	var cold: HospitalSpace = HospitalSpace.new(content)
	cold._ensure_actor_index(world)
	if space._actor_index._records.keys()!=cold._actor_index._records.keys(): return false
	for id: String in cold._actor_index._records:
		var actual: BodyIndex.Record = space._actor_index._records[id]
		var expected: BodyIndex.Record = cold._actor_index._records[id]
		if actual.floor_id!=expected.floor_id or actual.rect!=expected.rect: return false
	return true

func _actor_departure_projection(source: Dictionary, content: HospitalContent) -> Dictionary:
	var world: WorldState = WorldState.new(source.duplicate(true))
	var projected: WorldState = _departed_world(world,[OWNER,STAFF])
	var before: Dictionary = world.freeze()
	var projected_before: Dictionary = projected.freeze()
	var space: HospitalSpace = HospitalSpace.new(content)
	var cold: HospitalSpace = HospitalSpace.new(content)
	space.begin_dynamic_route_query(world,true)
	var original: BodyIndex.Record = space._actor_index._records[OWNER]
	var builds: int = int(space.query_counts.actor_index_builds)
	space.begin_actor_exclusion_query(world,projected,[OWNER,STAFF])
	cold.begin_route_query(projected,{},false)
	var equal: bool = _departure_queries_equal(space,cold,world,projected)
	space.begin_route_query(projected,{},false)
	equal = equal and _departure_queries_equal(space,cold,world,projected)
	space.end_route_query()
	var borrowed: bool = space._indexed_world==world and int(space.query_counts.actor_index_builds)==builds and space._actor_index._records[OWNER]==original
	var readonly: bool = world.freeze()==before and projected.freeze()==projected_before
	# Explicit force bypasses the borrowed source, even under this projection.
	space.begin_dynamic_route_query(projected,true)
	var forced: bool = int(space.query_counts.actor_index_builds)==builds+1 and space._indexed_world==projected and space._actor_exclusion_scope(projected).is_empty() and _bodies_cold_equal(space,projected,content)
	space.end_route_query()
	cold.end_route_query()
	space.end_route_query()
	space._ensure_actor_index(world)
	var restored: bool = _bodies_cold_equal(space,world,content) and not space._blocking_actor(world,1,space.body_rectangle(world.facts.actors[OWNER]),[]).is_empty()
	space.end_route_query()
	var invalidations: Array = []
	for changed: String in ["source","projected"]:
		projected = _departed_world(world,[OWNER,STAFF])
		space.begin_dynamic_route_query(world,true)
		space.begin_actor_exclusion_query(world,projected,[OWNER,STAFF])
		builds = int(space.query_counts.actor_index_builds)
		if changed=="source": world.touch(false)
		else: projected.touch(false)
		space._ensure_actor_index(projected)
		var fresh: bool = int(space.query_counts.actor_index_builds)==builds+1 and space._indexed_world==projected and _bodies_cold_equal(space,projected,content)
		invalidations.append({"changed":changed,"private_index_rebuilt":fresh})
		equal = equal and fresh
		space.end_route_query()
		space.end_route_query()
	# An unscoped calculation refreshes current raw source input first; no
	# notification or revision change is needed to establish this new scope.
	space._ensure_actor_index(world)
	world.facts.actors[OTHER].location.cell[0] += 0.25
	projected = _departed_world(world,[OWNER])
	builds = int(space.query_counts.actor_index_builds)
	space.begin_actor_exclusion_query(world,projected,[OWNER])
	var raw_fresh: bool = int(space.query_counts.actor_index_builds)==builds+1 and _bodies_cold_equal(space,world,content)
	cold = HospitalSpace.new(content)
	cold.begin_route_query(projected,{},false)
	equal = equal and _departure_queries_equal(space,cold,world,projected)
	cold.end_route_query()
	space.end_route_query()
	var closed: bool = space._route_queries.is_empty() and space._indexed_actor_scope.is_empty() and space._actor_exclusion_scope(projected).is_empty() and _bodies_cold_equal(space,world,content)
	return {"ok":equal and borrowed and readonly and forced and restored and raw_fresh and closed,"quotes_and_dynamic_bodies_cold_equal":equal,"source_index_borrowed_without_rebuild":borrowed,"facts_readonly":readonly,"explicit_force_private":forced,"source_bodies_after_projection":restored,"revision_invalidations":invalidations,"unscoped_raw_source_refreshed":raw_fresh,"no_scope_or_exclusion_leak":closed}

func _departed_world(world: WorldState, ids: Array) -> WorldState:
	var facts: Dictionary = world.facts.duplicate()
	facts.adaptations = world.facts.adaptations.duplicate()
	facts.adaptations.erase("permissions_machine")
	facts.actors = world.facts.actors.duplicate()
	for id: String in ids:
		facts.actors[id] = world.facts.actors[id].duplicate()
		facts.actors[id].location = {"kind":"outside"}
	return WorldState.new(facts)

func _departure_queries_equal(actual: HospitalSpace, cold: HospitalSpace, source: WorldState, projected: WorldState) -> bool:
	var equal: bool = true
	for id: String in source.ids("actors"):
		var actor: Dictionary = source.facts.actors[id]
		if actor.location.kind!="floor": continue
		var bounds: Rect2 = actual.body_rectangle(actor)
		for rect: Rect2 in [bounds,bounds.grow(0.25),Rect2(bounds.end,bounds.size)]:
			for ignored: Array in [[],[OTHER],[OWNER,STAFF]]:
				equal = equal and actual._blocking_actor(projected,int(actor.location.floor_id),rect,ignored)==cold._blocking_actor(projected,int(actor.location.floor_id),rect,ignored)
				equal = equal and actual._dynamic_clear(projected,OTHER,int(actor.location.floor_id),rect,ignored)==cold._dynamic_clear(projected,OTHER,int(actor.location.floor_id),rect,ignored)
	for facility_id: String in ["permissions_machine","permissions_second"]:
		for actor_id: String in [OTHER,PEER]:
			equal = equal and actual.facility_quote(projected,facility_id,actor_id)==cold.facility_quote(projected,facility_id,actor_id)
	return equal

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
