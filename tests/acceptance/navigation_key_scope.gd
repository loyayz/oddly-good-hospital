extends RefCounted

const ACTOR: String = "navigation_key_actor"
const OTHER: String = "navigation_key_other"

class KeyProbe extends NavigationCache:
	var shapes: int = 0
	func _traversal_shape(space: HospitalSpace, actor: Dictionary, offset: Array, source: Dictionary) -> Array:
		shapes += 1
		return super._traversal_shape(space,actor,offset,source)

# Original complete serialization, independent of every new scope key view.
class FullKeys extends KeyProbe:
	func _graph_key(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, members: Array, offsets: Dictionary, source: Dictionary) -> String:
		return str(floor_id)+":"+_envelope(space,world,actor,members,offsets,source)
	func _distance_destination(_space: HospitalSpace, _world: WorldState, _floor_id: int, _actor: Dictionary, start: Vector2i, goal: Vector2i, forward: bool, structural_only: bool, exemptions: Array) -> String:
		return JSON.stringify(["from",start.x,start.y,structural_only,exemptions]) if forward else JSON.stringify([goal.x,goal.y,exemptions])
	func _envelope(space: HospitalSpace, world: WorldState, actor: Dictionary, members: Array, offsets: Dictionary, source: Dictionary) -> String:
		var shapes: Array = [_traversal_shape(space,actor,[0,0],source)]
		for id: String in members:
			if id!=actor.id: shapes.append(_traversal_shape(space,world.facts.actors[id],offsets[id],source))
		return JSON.stringify(shapes,"",true,true)

class RouteProbe extends HospitalNavigation:
	var envelopes: int = 0
	func _init(geometry: HospitalSpace) -> void:
		super(geometry)
	func _route_envelope(world: WorldState, actor: Dictionary, members: Array, offsets: Dictionary) -> Array:
		envelopes += 1
		return super._route_envelope(world,actor,members,offsets)

# Frozen 899df40 full floor route entry. All modes keep its original complete
# key and no numerical endpoint view is used by the reference.
class FullRoutes extends RouteProbe:
	func _floor_route(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2i, goal: Vector2i, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false, navigation: Dictionary = {}, structural_only: bool = false, cost_only: bool = false) -> Dictionary:
		_observe_floor(world,str(actor.id),floor_id)
		var routes: Dictionary = {}
		var key: String = ""
		if navigation.is_empty() and not space._route_queries.is_empty() and space._route_queries.back().world==world and (ignore_people or space._route_queries.back().get("dynamic",false)):
			routes = space._route_queries.back().routes
			var identity: Variant = actor.id
			if not space._route_queries.back().reference.is_empty() and members.is_empty() and offsets.is_empty():
				identity = [space.body(actor),[] if structural_only else RouteClearance.reservation_exemptions(world,actor.id,floor_id)]
			key = JSON.stringify([identity,floor_id,start.x,start.y,goal.x,goal.y,members,offsets,ignore_people,structural_only,cost_only,_route_envelope(world,actor,members,offsets)])
			if routes.has(key):
				space.query_counts.floor_route_hits += 1
				return routes[key].duplicate(true)
		space.query_counts.floor_route_builds += 1
		var fresh_structural_graph: bool = structural_only and navigation.is_empty()
		if navigation.is_empty():
			navigation = space._navigation.query_graphs(space,world,floor_id,actor,members,offsets)
		var graph: FloorNavigation = navigation.graph
		var query: RouteClearance
		if structural_only: query = graph.geometry
		elif navigation.has("query"): query = navigation.query
		else: query = space._navigation.clearance(space,world,floor_id,actor) if members.is_empty() else RouteClearance.new(space,world,actor,floor_id,members,offsets,true,graph.geometry.source)
		var people: Callable = Callable()
		if not ignore_people:
			people = func(from_cell: Vector2i,to_cell: Vector2i) -> bool:
				return space._unit_step_dynamic_clear(world,actor,floor_id,from_cell,to_cell,members,offsets)
		var result: Dictionary
		var repeated: Dictionary = {}
		if cost_only and ignore_people and members.is_empty() and offsets.is_empty() and not navigation.has("query") and not navigation.get("overlay",false) and navigation.bases.is_empty() and navigation.shifts.is_empty():
			# The structural graph was acquired above in this same invocation. No
			# intervening query can refresh it; dynamic clearance keeps its own path.
			repeated = space._navigation.forward_distance(space,world,floor_id,actor,start,goal,structural_only,graph if fresh_structural_graph else null)
		if repeated.get("ready",false):
			space.query_counts["distance_field_hits"] = int(space.query_counts.get("distance_field_hits",0))+1
			result = {"ok":bool(repeated.ok),"status":"complete" if repeated.ok else "unreachable","reason":repeated.get("reason",""),"walking_distance":int(repeated.get("distance",-1))}
		elif not space._route_queries.is_empty() and space._route_queries.back().world==world and members.is_empty() and offsets.is_empty() and not navigation.has("query") and not navigation.get("overlay",false) and navigation.bases.is_empty() and navigation.shifts.is_empty():
			result = space._navigation.cached_floor_path(space,world,floor_id,actor,graph,query,start,goal,cost_only)
		else:
			result = graph.find_path(start,goal,query,Callable(),false,navigation.bases,navigation.shifts,bool(navigation.get("overlay",false)),cost_only)
		if result.ok and people.is_valid() and not cost_only:
			var low: Vector2 = Vector2(start)
			var high: Vector2 = low
			for cell: Array in result.cells:
				low = low.min(Vector2(float(cell[0]),float(cell[1])))
				high = high.max(Vector2(float(cell[0]),float(cell[1])))
			var shape: Rect2 = space._unit_rect(world,actor,Vector2.ZERO,members,offsets)
			var broad: Rect2 = Rect2(low+shape.position,high-low+shape.size)
			if not space._dynamic_clear(world,actor.id,floor_id,broad,members):
				var blocked: bool = false
				var previous: Vector2i = start
				for cell: Array in result.cells:
					var next: Vector2i = Vector2i(int(cell[0]),int(cell[1]))
					if not bool(people.call(previous,next)):
						blocked = true
						break
					previous = next
				if blocked:
					# Every incoming sweep contains the destination body. An occupied
					# destination cannot have a dynamic detour. The actual start's
					# fractional stub makes its space-query wider, so retain A* there.
					var actual_start: bool = actor.location.kind=="floor" and int(actor.location.floor_id)==floor_id and goal==Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1]))
					var alternative: Dictionary = {}
					if actual_start or bool(people.call(goal,goal)):
						alternative = graph.find_path(start,goal,query,people,false,navigation.bases,navigation.shifts,bool(navigation.get("overlay",false)),cost_only)
					if alternative.get("ok",false):
						result = alternative
					else:
						result.status = "contention"
		if result.ok and not cost_only:
			space.query_counts.materialized_floor_cells += result.cells.size()
			var path: Array = []
			for cell: Array in result.cells:
				path.append({"kind":"floor","floor_id":floor_id,"cell":cell})
			result.path = path
			result.erase("cells")
		if not key.is_empty():
			routes[key] = result.duplicate(true)
		return result

func _pair(content: HospitalContent) -> Dictionary:
	var actual: HospitalSpace = HospitalSpace.new(content)
	var original: HospitalSpace = HospitalSpace.new(content)
	actual._navigation = KeyProbe.new()
	original._navigation = FullKeys.new()
	actual.navigation = RouteProbe.new(actual)
	original.navigation = FullRoutes.new(original)
	return {"actual":actual,"original":original}

func _begin(pair: Dictionary, world: WorldState, dynamic: bool = true) -> void:
	if dynamic:
		pair.actual.begin_dynamic_route_query(world)
		pair.original.begin_dynamic_route_query(world)
	else:
		pair.actual.begin_route_query(world,{},false)
		pair.original.begin_route_query(world,{},false)

func _end(pair: Dictionary) -> void:
	pair.actual.end_route_query()
	pair.original.end_route_query()

func _leg(pair: Dictionary, world: WorldState, goal: Vector2i, cost_only: bool = true, structural_only: bool = true, members: Array = [], offsets: Dictionary = {}) -> Dictionary:
	var actor: Dictionary = world.facts.actors[ACTOR]
	var actual: Dictionary = pair.actual.navigation._floor_route(world,actor,1,Vector2i(44,80),goal,members,offsets,true,{},structural_only,cost_only)
	var expected: Dictionary = pair.original.navigation._floor_route(world,actor,1,Vector2i(44,80),goal,members,offsets,true,{},structural_only,cost_only)
	var equal: bool = var_to_bytes(actual)==var_to_bytes(expected)
	return {"ok":equal,"goal":goal,"cost_only":cost_only,"structural_only":structural_only,"members":members,"complete_result_and_types_equal":equal,"actual":actual,"expected":expected if not equal else {}}

func _values_only(value: Variant) -> bool:
	if value is Object: return false
	if value is Dictionary:
		for key: Variant in value:
			if not _values_only(key) or not _values_only(value[key]): return false
	elif value is Array:
		for item: Variant in value:
			if not _values_only(item): return false
	return true

func _envelopes(pair: Dictionary, world: WorldState) -> Dictionary:
	var actor: Dictionary = world.facts.actors[ACTOR]
	var actual: KeyProbe = pair.actual._navigation
	var original: FullKeys = pair.original._navigation
	var body: Dictionary = pair.actual.body(actor)
	var height: float = float(body.height_m)
	var door_height: float = height+0.1
	# These pairs collapse to identical float32 values. The original float64
	# comparisons must nevertheless distinguish both exact predicate edges.
	var sources: Array = [
		{"height":height,"door_height":door_height},
		{"height":height-0.0000000001,"door_height":door_height},
		{"height":height,"door_height":door_height-0.0000000001},
		{"height":height-0.0000000001,"door_height":door_height-0.0000000001}]
	_begin(pair,world)
	var before: int = actual.shapes
	var equal: bool = true
	var values: Array = []
	for _round: int in 3:
		for source: Dictionary in sources:
			var key: String = actual._envelope(pair.actual,world,actor,[],{},source)
			equal = equal and key==original._envelope(pair.original,world,actor,[],{},source)
			equal = equal and actual._graph_key(pair.actual,world,1,actor,[],{},source)==original._graph_key(pair.original,world,1,actor,[],{},source)
			if _round==0: values.append(key)
	var checks: Dictionary = {"all_original_envelope_and_graph_keys_equal":equal,"four_float64_height_predicate_edges_distinct":values.size()==4 and values[0]!=values[1] and values[0]!=values[2] and values[1]!=values[3] and values[2]!=values[3],"one_shape_prepare_per_exact_height_pair":actual.shapes-before==4}
	var source: Dictionary = sources[0]
	var offsets: Dictionary = {ACTOR:[0,0],OTHER:[1,0]}
	before = actual.shapes
	for _round: int in 2:
		equal = actual._envelope(pair.actual,world,actor,[ACTOR,OTHER],offsets,source)==original._envelope(pair.original,world,actor,[ACTOR,OTHER],offsets,source) and equal
	checks.groups_keep_complete_envelope_preparation = equal and actual.shapes-before==4
	before = actual.shapes
	for _round: int in 2:
		equal = actual._envelope(pair.actual,world,actor,[],{ACTOR:[0,0]},source)==original._envelope(pair.original,world,actor,[],{ACTOR:[0,0]},source) and equal
	checks.nonempty_offsets_keep_complete_envelope_preparation = equal and actual.shapes-before==2
	var keys_equal: bool = true
	for forward: bool in [false,true]:
		for structural: bool in [false,true]:
			for exemptions: Array in [[],["one"],["two","one"]]:
				# Permission-aware keys must retain every original exemption.
				# Structural consumers always own the empty exemption list.
				if structural and not exemptions.is_empty(): continue
				keys_equal = keys_equal and actual._distance_destination(pair.actual,world,1,actor,Vector2i(44,80),Vector2i(46,82),forward,structural,exemptions)==original._distance_destination(pair.original,world,1,actor,Vector2i(44,80),Vector2i(46,82),forward,structural,exemptions)
	checks.distance_destination_schema_and_permission_exemptions_unchanged = keys_equal
	for name: String in ["navigation_envelopes","navigation_graph_keys","navigation_distance_keys"]:
		checks[name+"_stores_values_only"] = _values_only(pair.actual._route_queries.back().views.get(name,{}))
	_end(pair)
	before = actual.shapes
	_begin(pair,world)
	actual._envelope(pair.actual,world,actor,[],{},source)
	actual._envelope(pair.actual,world,actor,[],{},source)
	checks.new_scope_prepares_once_again = actual.shapes-before==1
	_end(pair)
	before = actual.shapes
	for _round: int in 2: actual._envelope(pair.actual,world,actor,[],{},source)
	checks.raw_calls_do_not_retain_envelope = actual.shapes-before==2
	return {"ok":not checks.values().has(false),"checks":checks}

func _permissions(content: HospitalContent, facts: Dictionary) -> Dictionary:
	var world: WorldState = WorldState.new(facts)
	var facility_id: String = "navigation_key_reserved_machine"
	HospitalFactory._add_facility(world,{"id":facility_id,"definition_id":"M37","anchor":[52,82],"size":content.facility_definition("M37").footprint.duplicate(),"room_id":null},content)
	world.touch()
	var pair: Dictionary = _pair(content)
	var validation: String = world.validate(content)
	var reason: String = pair.actual.reserve_facility(world,facility_id,OTHER,OTHER)
	# Both independent services receive the same actual reservation boundary.
	pair.original._navigation.invalidate(world,1)
	var goal: Array = world.facts.facilities[facility_id].patient_cell
	var target: Vector2i = Vector2i(int(goal[0]),int(goal[1]))
	var observations: Array = []
	_begin(pair,world)
	observations.append(_leg(pair,world,target,true,false))
	var checks: Dictionary = {"valid_input":validation.is_empty(),"actual_reservation_created":reason.is_empty(),"current_reservation_rejects_non_owner":not observations.back().actual.ok}
	_end(pair)
	pair.actual.grant_facility_access(world,facility_id,ACTOR)
	pair.original._navigation.invalidate(world,1)
	_begin(pair,world)
	observations.append(_leg(pair,world,target,true,false))
	checks.new_scope_reads_current_permission_grant = observations.back().actual.ok
	_end(pair)
	if world.facts.adaptations.has(facility_id): world.facts.adaptations[facility_id].staff_ids.erase(ACTOR)
	for space: HospitalSpace in [pair.actual,pair.original]:
		space.reservation_changed(world,facility_id)
		space._navigation.invalidate(world,1)
	_begin(pair,world)
	observations.append(_leg(pair,world,target,true,false))
	checks.revoked_permission_is_not_reused = not observations.back().actual.ok
	observations.append(_leg(pair,world,target,true,true))
	checks.structural_quote_still_ignores_temporary_reservation = observations.back().actual.ok
	_end(pair)
	var ok: bool = not checks.values().has(false)
	for observation: Dictionary in observations: ok = ok and observation.ok
	return {"ok":ok,"checks":checks,"validation":validation,"reservation_reason":reason,"observations":observations}

func run_case(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	suite._add_actor(sim,ACTOR,"S49",[44,80])
	suite._add_actor(sim,OTHER,"S49",[45,80])
	var world: WorldState = sim.world
	var pair: Dictionary = _pair(suite.content)
	var actual: KeyProbe = pair.actual._navigation
	var original: FullKeys = pair.original._navigation
	var validation: String = world.validate(suite.content)
	var checks: Dictionary = {"valid_input":validation.is_empty()}
	var before: Dictionary = world.freeze()
	var observations: Array = []
	_begin(pair,world)
	var shape_count: int = actual.shapes
	var original_shapes: int = original.shapes
	for y: int in range(82,85):
		for x: int in range(44,50): observations.append(_leg(pair,world,Vector2i(x,y)))
	checks.all_targets_avoid_full_route_envelope = pair.actual.navigation.envelopes==0 and pair.original.navigation.envelopes==18
	checks.graph_and_path_consumers_prepare_shape_only_once = actual.shapes-shape_count==1 and original.shapes-original_shapes>=18
	observations.append(_leg(pair,world,Vector2i(-1,80)))
	checks.goal_failure_keeps_original_reason_and_type = not observations.back().actual.ok
	var first: Dictionary = pair.actual.navigation._floor_route(world,world.facts.actors[ACTOR],1,Vector2i(44,80),Vector2i(44,82),[],{},true,{},true,true)
	first.walking_distance = 99999
	observations.append(_leg(pair,world,Vector2i(44,82)))
	checks.returned_result_does_not_mutate_the_scope = observations.back().actual.get("walking_distance",-1)!=99999
	var envelopes: int = pair.actual.navigation.envelopes
	observations.append(_leg(pair,world,Vector2i(47,83),false))
	checks.executable_path_keeps_complete_key = pair.actual.navigation.envelopes>envelopes and observations.back().actual.has("path")
	envelopes = pair.actual.navigation.envelopes
	observations.append(_leg(pair,world,Vector2i(47,84),true,true,[ACTOR,OTHER],{ACTOR:[0,0],OTHER:[1,0]}))
	checks.groups_keep_complete_key = pair.actual.navigation.envelopes>envelopes
	envelopes = pair.actual.navigation.envelopes
	observations.append(_leg(pair,world,Vector2i(48,84),true,true,[],{ACTOR:[0,0]}))
	checks.nonempty_offsets_keep_complete_key = pair.actual.navigation.envelopes>envelopes
	var actor: Dictionary = world.facts.actors[ACTOR]
	var old_graph: FloorNavigation = actual.graph(pair.actual,world,1,actor,[],{})
	actual._trim(0,pair.actual.query_counts)
	original._trim(0,pair.original.query_counts)
	checks.scope_keys_do_not_pin_evicted_graphs_or_charges = actual._entries.is_empty() and actual._charged==0 and actual._query_charged==0 and original._entries.is_empty()
	var used: int = actual._used
	var rebuilt: FloorNavigation = actual.graph(pair.actual,world,1,actor,[],{})
	var rebuilt_original: FloorNavigation = original.graph(pair.original,world,1,actor,[],{})
	checks.same_scope_key_still_rebuilds_evicted_graph = rebuilt!=old_graph and actual._used==used+1 and actual._entries.size()==1 and actual._charged>0
	var cold_goal: Vector2i = Vector2i(49,85)
	checks.rebuilt_graph_path_and_cost_match_original = rebuilt.find_path(Vector2i(44,80),cold_goal,rebuilt.geometry)==rebuilt_original.find_path(Vector2i(44,80),cold_goal,rebuilt_original.geometry)
	for name: String in ["navigation_envelopes","navigation_graph_keys","navigation_distance_keys"]:
		checks[name+"_does_not_hold_graph_objects"] = _values_only(pair.actual._route_queries.back().views.get(name,{}))
	_end(pair)
	checks.first_batch_readonly = before==world.freeze()
	envelopes = pair.actual.navigation.envelopes
	_begin(pair,world,false)
	observations.append(_leg(pair,world,Vector2i(49,84)))
	checks.ordinary_scope_keeps_complete_key = pair.actual.navigation.envelopes>envelopes
	_end(pair)
	envelopes = pair.actual.navigation.envelopes
	observations.append(_leg(pair,world,Vector2i(48,83)))
	checks.raw_floor_route_keeps_original_acquisition = pair.actual.navigation.envelopes==envelopes
	var envelope_result: Dictionary = _envelopes(pair,world)
	checks.envelope_boundaries_and_lifetime = envelope_result.ok
	# Real geometry changes happen outside every sealed read-only scope.
	world.facts.floors.overrides["1"].blocked.append([46,82])
	world.touch()
	_begin(pair,world)
	observations.append(_leg(pair,world,Vector2i(46,82)))
	checks.current_source_change_rejects_new_obstruction = not observations.back().actual.ok
	_end(pair)
	world.facts.floors.overrides["1"].blocked.erase([46,82])
	world.touch()
	_begin(pair,world)
	observations.append(_leg(pair,world,Vector2i(46,82)))
	checks.restored_source_is_reachable = observations.back().actual.ok
	var shapes: int = actual.shapes
	var other_world: WorldState = WorldState.new(world.freeze())
	other_world.facts.actors[ACTOR].posture = "lying"
	other_world.touch()
	_begin(pair,other_world)
	observations.append(_leg(pair,other_world,Vector2i(47,82)))
	checks.other_world_owns_its_shape_preparation = actual.shapes>shapes
	_end(pair)
	shapes = actual.shapes
	observations.append(_leg(pair,world,Vector2i(48,82)))
	checks.outer_world_resumes_original_key_view = actual.shapes==shapes
	_end(pair)
	var permission_result: Dictionary = _permissions(suite.content,world.freeze())
	checks.actual_permission_handoffs = permission_result.ok
	var ok: bool = not checks.values().has(false)
	for observation: Dictionary in observations: ok = ok and observation.ok
	checks.scopes_close = pair.actual._route_queries.is_empty() and pair.original._route_queries.is_empty()
	ok = ok and checks.scopes_close
	var result: Dictionary = {"ok":ok,"validation":validation,"checks":checks,"envelope_cases":envelope_result,"permission_handoffs":permission_result,"observations":observations,"prepared_shape_calls":actual.shapes,"reference_shape_calls":original.shapes,"prepared_full_route_envelopes":pair.actual.navigation.envelopes,"reference_full_route_envelopes":pair.original.navigation.envelopes}
	sim.dispose()
	return result
