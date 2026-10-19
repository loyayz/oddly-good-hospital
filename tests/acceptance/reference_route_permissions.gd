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
			var expected: bool = id in [OWNER,STAFF]
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
			var before_size: int = reference.routes.size() if mode=="floor" else reference.journeys.size()
			var next_quote: Dictionary = _quote(space,worlds[pair[1]],pair[1],goal,reference,mode)
			var after_size: int = reference.routes.size() if mode=="floor" else reference.journeys.size()
			var shared: bool = first_quote==next_quote and before_size==after_size
			valid = valid and shared
			observations.append({"mode":mode,"same_permissions":pair,"shared":shared})
	var fields: Dictionary = _forward_contract(source,goal,content)
	return {"ok":valid and fields.ok,"details":{"observations":observations,"forward_fields":fields,"no_simulation_steps":true}}

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
	graph.disconnect_points(FloorNavigation._id(a),FloorNavigation._id(b),false)
	var directed: bool = graph.are_points_connected(FloorNavigation._id(b),FloorNavigation._id(a),false)
	for pair: Array in [[a,b],[b,a]]:
		var distances: PackedInt32Array = space._navigation._forward_field(graph,query,pair[0])
		var expected: Dictionary = graph.find_path(pair[0],pair[1],query)
		directed = directed and expected.ok and distances[FloorNavigation._id(pair[1])]==int(expected.walking_distance)
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
