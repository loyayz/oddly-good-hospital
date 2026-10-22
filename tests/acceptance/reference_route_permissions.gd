extends RefCounted

const START: Array = [38,80]
const OWNER: String = "permission_owner"
const STAFF: String = "permission_staff"
const OTHER: String = "permission_other"
const PEER: String = "permission_peer"

func run_case(sim: HospitalSimulation, content: HospitalContent) -> Dictionary:
	var built: CommandResult = sim.apply(GameCommand.new("permissions_machine",sim.world.hospital_id,sim.world.revision,"build_facility",BusinessPayload.new({"id":"permissions_machine","definition_id":"M37","floor_id":1,"cell":[42,76]})))
	if not built.accepted: return {"ok":false,"details":built.to_record()}
	var goal: Array = sim.space.facility_layout(sim.world,"permissions_machine").patient_cell
	for sample: Array in [[OWNER,goal],[OTHER,[35,86]],[PEER,[38,86]]]:
		sim.world.facts.actors[sample[0]] = {"id":sample[0],"name":sample[0],"species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":sample[1].duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
	HospitalFactory._add_staff(sim.world,STAFF,STAFF,"doctor",[35,82],content)
	sim._ensure_services()
	sim.world.touch()
	var reserved: String = sim.space.reserve_facility(sim.world,"permissions_machine",OWNER,OWNER)
	if not reserved.is_empty(): return {"ok":false,"details":{"reservation":reserved}}
	sim.space.grant_facility_access(sim.world,"permissions_machine",STAFF)
	var source: Dictionary = sim.world.freeze()
	var valid: bool = true
	var observations: Array = []
	for mode: String in ["floor","journey"]:
		var cold: Dictionary = {}
		var worlds: Dictionary = {}
		for id: String in [OWNER,STAFF,OTHER,PEER]:
			var facts: Dictionary = source.duplicate(true)
			# A prospective quote begins at the same legal point for each actor.
			# The other actors retain their separate actual positions.
			facts.actors[id].location.cell = START.duplicate()
			var world: WorldState = WorldState.new(facts)
			var validation: String = world.validate(content)
			valid = valid and validation.is_empty()
			worlds[id] = world
			cold[id] = _quote(HospitalSpace.new(content),world,id,goal,{"nominal":true},mode)
			var expected: bool = mode=="journey" or id in [OWNER,STAFF]
			valid = valid and cold[id].ok==expected
			observations.append({"mode":mode,"actor":id,"validation":validation,"cold":cold[id]})
		for first: String in [OWNER,STAFF]:
			for order: Array in [[first,OTHER,first],[OTHER,first,OTHER]]:
				var space: HospitalSpace = HospitalSpace.new(content)
				var reference: Dictionary = {"nominal":true}
				var equal: bool = true
				for id: String in order:
					var world: WorldState = worlds[id]
					var before: Dictionary = world.freeze()
					var actual: Dictionary = _quote(space,world,id,goal,reference,mode)
					equal = equal and actual==cold[id] and world.freeze()==before and space._route_queries.is_empty()
				valid = valid and equal
				observations.append({"mode":mode,"order":order,"complete_cold_equal":equal})
		# The signature preserves sharing for equally authorized actors and for
		# equally unauthorized actors; adding actor IDs would fail this check.
		for pair: Array in [[OWNER,STAFF],[OTHER,PEER]]:
			var space: HospitalSpace = HospitalSpace.new(content)
			var reference: Dictionary = {"nominal":true}
			var first_quote: Dictionary = _quote(space,worlds[pair[0]],pair[0],goal,reference,mode)
			var before_size: int = reference.routes.size()
			var next_quote: Dictionary = _quote(space,worlds[pair[1]],pair[1],goal,reference,mode)
			var after_size: int = reference.routes.size()
			var shared: bool = first_quote==next_quote and before_size==after_size
			valid = valid and shared
			observations.append({"mode":mode,"same_permissions":pair,"shared":shared})
	var fields: Dictionary = _forward_contract(source,goal,content)
	var reverse: Dictionary = _reverse_contract(source,goal,content)
	var masks: Dictionary = _mask_contract(source,content)
	var projections: Dictionary = _projection_contract(source,content)
	var reuse: Dictionary = preload("res://tests/acceptance/navigation_static_reuse.gd").new().run_case(sim,content)
	return {"ok":valid and fields.ok and reverse.ok and masks.ok and projections.ok and reuse.ok,"details":{"observations":observations,"forward_fields":fields,"reverse_structural_fields":reverse,"reservation_masks":masks,"projection_sources":projections,"static_reuse":reuse,"no_simulation_steps":true}}

func _reverse_contract(source: Dictionary, goal: Array, content: HospitalContent) -> Dictionary:
	var world: WorldState = WorldState.new(source.duplicate(true))
	var space: HospitalSpace = HospitalSpace.new(content)
	var before: Dictionary = world.freeze()
	var target: Vector2i = Vector2i(goal[0],goal[1])
	var valid: bool = world.validate(content).is_empty()
	var observations: Array = []
	space.begin_dynamic_route_query(world)
	# Distinct origins keep every forward field cold. The shared destination
	# must warm only after twelve real cost queries across equivalent bodies.
	for index: int in 16:
		var actor: Dictionary = world.facts.actors[[OWNER,OTHER,PEER][index%3]]
		var origin: Vector2i = Vector2i(35+index,88)
		var cold_space: HospitalSpace = HospitalSpace.new(content)
		var expected: Dictionary = cold_space.navigation._floor_route(world,actor,1,origin,target,[],{},true,{},true,true)
		var actual: Dictionary = space.navigation._floor_route(world,actor,1,origin,target,[],{},true,{},true,true)
		var builds: int = int(space.query_counts.get("distance_field_builds",0))
		var equal: bool = actual==expected and builds==(0 if index<11 else 1)
		valid = valid and equal
		observations.append({"query":index+1,"complete_cost_equal":equal,"field_builds":builds})
	space.end_route_query()
	valid = valid and int(space.query_counts.get("structural_reverse_field_hits",0))==5
	var failed_schema: bool = true
	space.begin_dynamic_route_query(world)
	for index: int in 13:
		var failed_actor: Dictionary = world.facts.actors[OTHER]
		var origin: Vector2i = Vector2i(35+index,88)
		var blocked_goal: Vector2i = Vector2i(42,76)
		var cold_space: HospitalSpace = HospitalSpace.new(content)
		var expected: Dictionary = cold_space.navigation._floor_route(world,failed_actor,1,origin,blocked_goal,[],{},true,{},true,true)
		var actual: Dictionary = space.navigation._floor_route(world,failed_actor,1,origin,blocked_goal,[],{},true,{},true,true)
		failed_schema = failed_schema and not expected.ok and var_to_bytes(actual)==var_to_bytes(expected)
	space.end_route_query()
	valid = valid and failed_schema
	# Structural reachability never supplies permission to enter another
	# patient's reservation, including when its reverse field is already warm.
	var actor: Dictionary = world.facts.actors[OTHER]
	var permission: Dictionary = space._floor_route(world,actor,1,Vector2i(START[0],START[1]),target,[],{},true,{},true)
	var permission_cold: Dictionary = HospitalSpace.new(content)._floor_route(world,actor,1,Vector2i(START[0],START[1]),target,[],{},true,{},true)
	var isolated: bool = permission==permission_cold and not permission.ok
	valid = valid and isolated and world.freeze()==before
	world.facts.floors.overrides["1"].blocked.append([35,88])
	world.touch()
	var edited_before: Dictionary = world.freeze()
	var first: Dictionary = space._navigation.reverse_structural_distance(space,world,1,actor,Vector2i(35,88),target)
	var invalidated: bool = not first.ready
	var changed: Dictionary
	for hit: int in 12: changed = space._navigation.reverse_structural_distance(space,world,1,actor,Vector2i(35,88),target)
	var cold_space: HospitalSpace = HospitalSpace.new(content)
	var cold: Dictionary = cold_space.navigation._floor_route(world,actor,1,Vector2i(35,88),target,[],{},true,{},true,true)
	invalidated = invalidated and changed.ready and changed.ok==cold.ok and changed.reason==cold.reason
	var zero: Dictionary = space._navigation.reverse_structural_distance(space,world,1,actor,target,target)
	var outside: Dictionary = space._navigation.reverse_structural_distance(space,world,1,actor,Vector2i(-1,88),target)
	var boundaries: bool = zero.ready and zero.ok and zero.distance==0 and outside.ready and not outside.ok and outside.reason=="目标超出96×96真实楼面"
	valid = valid and invalidated and boundaries and world.freeze()==edited_before
	space._navigation._trim(0)
	var evicted: bool = space._navigation._entries.is_empty() and space._navigation._charged==0 and space._navigation._query_charged==0
	return {"ok":valid and evicted,"observations":observations,"failed_floor_result_schema_equal":failed_schema,"permission_isolated":isolated,"geometry_invalidated":invalidated,"zero_and_outside":boundaries,"complete_budget_eviction":evicted,"facts_rng_readonly":world.freeze()==edited_before}

func _mask_contract(source: Dictionary, content: HospitalContent) -> Dictionary:
	var world: WorldState = WorldState.new(source.duplicate(true))
	var before: Dictionary = world.freeze()
	var space: HospitalSpace = HospitalSpace.new(content)
	var sizes: Dictionary = {}
	var observations: Array = []
	var passed: bool = true
	for species: Dictionary in content.catalog.species:
		var actor: Dictionary = world.facts.actors[OTHER].duplicate()
		actor.species_id = species.id
		var size: int = space.clearance(actor)
		if not size in [1,2,3] or sizes.has(size): continue
		sizes[size] = true
		for group: bool in [false,true]:
			for offset: Array in [[0,0],[0.25,-0.5],[0.99999994,1.0000001]]:
				var members: Array = [OTHER,OWNER] if group else []
				var offsets: Dictionary = {OTHER:[0,0],OWNER:offset} if group else {}
				var query: RouteClearance = RouteClearance.new(space,world,actor,1,members,offsets)
				var mask: PackedByteArray = query.reservation_mask()
				var equal: bool = true
				for id: int in FloorNavigation.LIMIT:
					equal = equal and (not mask.is_empty() and mask[id]!=0)==(not query.reservation_reason(FloorNavigation._cell(id)).is_empty())
				passed = passed and equal
				observations.append({"size":size,"group":group,"offset":offset,"all_9216_origins_equal":equal})
	# An authorized primary with an unauthorized member exercises the shifted
	# member's rectangle, rather than only the primary's reservation union.
	for offset: Array in [[0,0],[0.25,-0.5],[0.99999994,1.0000001]]:
		var query: RouteClearance = RouteClearance.new(space,world,world.facts.actors[OWNER],1,[OWNER,OTHER],{OWNER:[0,0],OTHER:offset})
		var mask: PackedByteArray = query.reservation_mask()
		for id: int in FloorNavigation.LIMIT:
			passed = passed and (not mask.is_empty() and mask[id]!=0)==(not query.reservation_reason(FloorNavigation._cell(id)).is_empty())
	var authorized: RouteClearance = RouteClearance.new(space,world,world.facts.actors[OWNER],1)
	return {"ok":passed and sizes.size()==3 and authorized.reservation_mask().is_empty() and before==world.freeze(),"sizes":sizes.keys(),"observations":observations,"authorized_empty":authorized.reservation_mask().is_empty(),"readonly":before==world.freeze()}

func _projection_contract(source: Dictionary, content: HospitalContent) -> Dictionary:
	var world: WorldState = WorldState.new(source.duplicate(true))
	var plots: Array = HospitalSpace.floor_plots(world,1).duplicate(true)
	for floor_id: int in [2,3]: world.facts.floors.overrides[str(floor_id)] = {"plots":plots.duplicate(true),"blocked":[],"doors":[],"paths":[]}
	world.facts.floors.completed_top_floor = {}
	for plot: Array in plots: world.facts.floors.completed_top_floor[HospitalSpace.plot_key(plot)] = 3
	world.facts.floors.height_intervals = [{"first":1,"last":3,"height_m":float(content.balance.floors.clear_height_m)}]
	world.touch()
	var space: HospitalSpace = HospitalSpace.new(content)
	var observations: Array = []
	var passed: bool = true
	for pass_id: int in 3:
		if pass_id==2:
			world.facts.floors.overrides["2"].blocked.append([38,80])
			world.touch()
		var before: Dictionary = world.freeze()
		var facts: Dictionary = world.facts.duplicate()
		facts.adaptations = world.facts.adaptations.duplicate()
		facts.adaptations.permissions_machine = facts.adaptations.permissions_machine.duplicate(true)
		facts.adaptations.permissions_machine.staff_ids = [OTHER] if pass_id==1 else [STAFF]
		var projected: WorldState = WorldState.new(facts)
		var projected_before: Dictionary = projected.freeze()
		space.prepare_projection(world,projected,["permissions_machine"],[1,2,3])
		var equal: bool = true
		for floor_id: int in [1,2,3]:
			var actual: Dictionary = space._navigation.floor_source(space,projected,floor_id)
			var expected: Dictionary = RouteClearance.capture_source(HospitalSpace.new(content),projected,floor_id)
			equal = equal and actual==expected
			space._navigation.graph(space,projected,floor_id,projected.facts.actors[OWNER],[],{})
		var root_ready: bool = true
		if pass_id>0:
			for floor_id: int in [1,2,3]: root_ready = root_ready and space._navigation._sources.has(str(world.get_instance_id())+":"+str(floor_id))
		passed = passed and equal and root_ready and before==world.freeze() and projected_before==projected.freeze()
		observations.append({"pass":pass_id,"full_capture_equal":equal,"root_sources_prepared":root_ready,"readonly":before==world.freeze() and projected_before==projected.freeze()})
	return {"ok":passed,"observations":observations}

func _forward_contract(source: Dictionary, goal: Array, content: HospitalContent) -> Dictionary:
	var space: HospitalSpace = HospitalSpace.new(content)
	var valid: bool = true
	var observations: Array = []
	for actor_id: String in [OWNER,OTHER,STAFF,PEER]:
		var world: WorldState = WorldState.new(source.duplicate(true))
		var before: Dictionary = world.freeze()
		for pair: Array in [[START,goal],[goal,START],[goal,goal],[START,[-1,80]]]:
			var start: Vector2i = Vector2i(pair[0][0],pair[0][1])
			var target: Vector2i = Vector2i(pair[1][0],pair[1][1])
			var expected: Dictionary = HospitalSpace.new(content)._floor_route(world,world.facts.actors[actor_id],1,start,target,[],{},true)
			var actual: Dictionary = {}
			for hit: int in 13: actual = space._navigation.forward_distance(space,world,1,world.facts.actors[actor_id],start,target)
			var equal: bool = actual.ready and actual.ok==expected.ok and actual.reason==expected.reason
			if expected.ok: equal = equal and int(actual.distance)==int(expected.walking_distance)
			valid = valid and equal and world.freeze()==before
			observations.append({"actor":actor_id,"start":pair[0],"goal":pair[1],"equal":equal,"ok":actual.ok,"reason":actual.reason})
	# The same cache must discard its field after geometry changes and eviction.
	var changed: WorldState = WorldState.new(source.duplicate(true))
	changed.facts.floors.overrides["1"].blocked.append(START.duplicate())
	changed.touch()
	var blocked: Dictionary = {}
	for hit: int in 13: blocked = space._navigation.forward_distance(space,changed,1,changed.facts.actors[OWNER],Vector2i(goal[0],goal[1]),Vector2i(START[0],START[1]))
	var complete: Dictionary = HospitalSpace.new(content)._floor_route(changed,changed.facts.actors[OWNER],1,Vector2i(goal[0],goal[1]),Vector2i(START[0],START[1]),[],{},true)
	var invalidated: bool = blocked.ready and not blocked.ok and blocked.reason==complete.reason
	space._navigation._trim(0)
	var evicted: bool = space._navigation._entries.is_empty() and space._navigation._charged==0 and space._navigation._query_charged==0
	# Primitive directed-graph contract: a field follows outgoing edges. A*
	# provides the independent distance oracle; no world fact is modified.
	var world: WorldState = WorldState.new(source.duplicate(true))
	var actor: Dictionary = world.facts.actors[OTHER]
	var graph: FloorNavigation = space._navigation.graph(space,world,1,actor,[],{})
	var query: RouteClearance = space._navigation.clearance(space,world,1,actor)
	var a: Vector2i = Vector2i(START[0],START[1])
	var b: Vector2i = a+Vector2i.RIGHT
	graph._disconnect_edge(FloorNavigation._id(a),FloorNavigation._id(b))
	var directed: bool = graph.are_points_connected(FloorNavigation._id(b),FloorNavigation._id(a),false)
	for pair: Array in [[a,b],[b,a]]:
		var field: Dictionary = graph.distance_field(query,pair[0])
		if not field.get("ready",false): return {"ok":false,"native_distance_field":field}
		var distances: PackedInt32Array = field.distances
		var expected: Dictionary = graph.find_path(pair[0],pair[1],query)
		directed = directed and expected.ok and distances[FloorNavigation._id(pair[1])]==int(expected.walking_distance)
		var reverse: Dictionary = graph.distance_field(query,pair[1],true)
		directed = directed and reverse.get("ready",false) and reverse.distances[FloorNavigation._id(pair[0])]==int(expected.walking_distance)
	return {"ok":valid and invalidated and evicted and directed,"observations":observations,"geometry_invalidated":invalidated,"complete_budget_eviction":evicted,"directed_astar_equal":directed}

func _quote(space: HospitalSpace, world: WorldState, id: String, goal: Array, reference: Dictionary, mode: String) -> Dictionary:
	space.begin_route_query(world,reference)
	var result: Dictionary
	if mode=="floor":
		result = space._floor_route(world,world.facts.actors[id],1,Vector2i(START[0],START[1]),Vector2i(goal[0],goal[1]),[],{},true)
	else:
		result = space.route(world,id,1,goal,[],{},true)
	space.end_route_query()
	return result
