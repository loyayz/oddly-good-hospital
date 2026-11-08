class_name HospitalNavigation
extends RefCounted

var _space: WeakRef
var _topologies: Dictionary = {}
var _observed_floors: Dictionary = {}
var space: HospitalSpace:
	get: return _space.get_ref()

func _init(geometry: HospitalSpace) -> void:
	_space = weakref(geometry)

# A route proves a structural journey. Queues and movable people are handled
# by movement when encountered; their release time is not a path prerequisite.
func _route_result(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array, offsets: Dictionary, _ignore_people: bool, distance_only: bool) -> Dictionary:
	if not members.is_empty(): return _convoy_route_result(world,actor_id,floor_id,target,members,offsets,distance_only)
	space.query_counts.routes += 1
	var actor: Dictionary = world.facts.actors[actor_id]
	if actor.location.kind!="floor": return {"ok":false,"status":"unavailable","reason":"角色正在竖向通行或院外"}
	_observe_floor(world,actor_id,int(actor.location.floor_id))
	var owner: Dictionary = space.read_view(world,"point_journeys",func()->Dictionary:return {})
	var subject: Dictionary
	var journeys: Dictionary
	var key: String
	var single: bool = members.is_empty() and offsets.is_empty()
	if single:
		# Source position, body and facing are fixed throughout this existing
		# sealed read-only scope. Different goals share that source proof only.
		# Without a scope, read_view returns a new disposable owner each time.
		var subjects: Dictionary = owner.get_or_add("subjects",{})
		if not subjects.has(actor_id): subjects[actor_id] = _prepare_route_subject(world,actor,[],{})
		subject = subjects[actor_id]
		journeys = subject.get_or_add("journeys",{})
	else:
		# Formations retain their complete original key and source acquisition.
		subject = _prepare_route_subject(world,actor,members,offsets)
		journeys = owner.get_or_add("groups",{})
	if not str(subject.reason).is_empty(): return {"ok":false,"status":"unreachable","reason":subject.reason}
	key = JSON.stringify([floor_id,target,distance_only],"",true,true) if single else JSON.stringify([actor.id,actor.location.floor_id,actor.location.cell,floor_id,target,_route_envelope(world,actor,members,offsets),distance_only],"",true,true)
	if journeys.has(key):
		space.query_counts.journey_hits += 1
		return journeys[key].duplicate(true)
	var start: Vector2i = subject.start
	var stub: float = float(subject.stub)
	var destination: Vector2 = Vector2(float(target[0]),float(target[1]))
	var goal: Vector2i = Vector2i(int(target[0]),int(target[1]))
	var final_leg: Dictionary = {"points":[],"distance":0.0,"ticks":0}
	if Vector2(goal)!=destination:
		# The graph endpoint is only an anchor, not the requested destination.
		# Orthogonal legs keep actual facing inside the proved body envelope.
		final_leg = _grid_stub(world,actor,floor_id,Vector2(goal),destination)
		if not final_leg.ok: return {"ok":false,"status":"unreachable","reason":final_leg.reason}
	var result: Dictionary = _point_route(world,actor,int(subject.floor_id),start,floor_id,goal,members,offsets,int(subject.initial_ticks),distance_only)
	if result.ok and stub>0.0:
		if not distance_only: result.path.push_front({"kind":"floor","floor_id":int(actor.location.floor_id),"cell":[start.x,start.y]})
		result.walking_distance += stub
	if result.ok and not final_leg.points.is_empty():
		var ticks: int = HospitalTransit._add(int(result.travel_ticks),int(final_leg.ticks))
		if ticks<0: return {"ok":false,"status":"time_overflow","reason":"基准通行时间超出整数范围"}
		if not distance_only:
			for point: Array in final_leg.points: result.path.append({"kind":"floor","floor_id":floor_id,"cell":point.duplicate()})
		result.walking_distance += float(final_leg.distance)
		result.travel_ticks = ticks
	journeys[key] = result.duplicate(true)
	return result

func _prepare_route_subject(world: WorldState, actor: Dictionary, members: Array, offsets: Dictionary) -> Dictionary:
	var start: Vector2i = Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1]))
	var actual: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	var stub: float = actual.distance_to(Vector2(start))
	var reason: String = ""
	if stub>0.0:
		var query: RouteClearance = structural_clearance(world,actor,int(actor.location.floor_id),members,offsets)
		reason = query.sweep_reason(actual,Vector2(start))
	return {"floor_id":int(actor.location.floor_id),"start":start,"stub":stub,"reason":reason,"initial_ticks":HospitalTransit.walking_ticks(space,actor,members,stub) if reason.is_empty() else 0}

func travel_quote(world: WorldState, actor_id: String, floor_id: int, target: Array) -> Dictionary:
	return _route_result(world,actor_id,floor_id,target,[],{},true,true)

# Structural choices read these original declarations and failure directions.
# Queue tickets, current cabin trips and remaining times do not deny a route.
func connection_basis(world: WorldState) -> Array:
	var result: Array = []
	for id: String in world.ids("connectors"):
		var connection: Dictionary = world.facts.connectors[id]
		result.append([id,connection.definition_id,connection.get("first_floor",0),connection.get("last_floor",0),connection.get("stops",[]),connection.cell,connection.footprint,connection.anchor,HospitalTransit._lowering(connection)])
	return result

func _observe_floor(world: WorldState, actor_id: String, floor_id: int) -> void:
	var key: int = world.get_instance_id()
	if not _observed_floors.has(key) or _observed_floors[key].world.get_ref()!=world:
		for old: int in _observed_floors.keys():
			if _observed_floors[old].world.get_ref()==null: _observed_floors.erase(old)
		_observed_floors[key] = {"world":weakref(world),"tick":world.sim_tick,"actors":{}}
	elif int(_observed_floors[key].tick)!=world.sim_tick:
		_observed_floors[key].tick = world.sim_tick
		_observed_floors[key].actors.clear()
	_observed_floors[key].actors.get_or_add(actor_id,{})[floor_id] = true

func observed_floors(world: WorldState, actor_ids: Array) -> Array:
	var result: Dictionary = {}
	var record: Dictionary = _observed_floors.get(world.get_instance_id(),{})
	if not record.is_empty() and record.world.get_ref()==world and int(record.tick)==world.sim_tick:
		for id: String in actor_ids: result.merge(record.actors.get(id,{}))
	var floors: Array = result.keys()
	floors.sort()
	return floors

func routing_floor_basis(world: WorldState) -> Array:
	var floors: Array = world.facts.floors.overrides.keys()
	floors.sort()
	return floors

func destination_reason(world: WorldState, actor: Dictionary, floor_id: int, target: Vector2, members: Array = [], offsets: Dictionary = {}) -> String:
	if not members.is_empty():
		if not offsets.is_empty(): return "同行组只支持前后队列"
		var m: Dictionary = _convoy_query_movement(world,actor.id,members)
		var proxy: Dictionary = ConvoyTrail.proxy(world,m)
		return structural_clearance(world,proxy,floor_id).position_reason(Vector2(target)+Vector2.ONE*float(m.convoy.shift))
	var query: RouteClearance = structural_clearance(world,actor,floor_id,members,offsets)
	# Integer admission retains the existing graph predicate. A fractional
	# body can overlap a wall or fixture absent from its rounded neighbor.
	return query.reason(Vector2i(target)) if target==target.floor() else query.sweep_reason(target,target)

func structural_clearance(world: WorldState, actor: Dictionary, floor_id: int, members: Array = [], offsets: Dictionary = {}) -> RouteClearance:
	if actor.has("_convoy_size") or members.size()==1 and members[0]==actor.id: members = []
	var source: Dictionary = space._navigation.floor_source(space,world,floor_id)
	var query: RouteClearance = space._navigation.cached_static_geometry(space,world,floor_id,actor) if members.is_empty() else null
	if query==null: query = RouteClearance.new(space,world,actor,floor_id,members,offsets,false,source)
	return query

# This synchronous projection retains the original floor and connector owners.
# Only actors and adaptations differ. Share structural declarations and their
# floor lookups, while body compatibility and routes remain query-local.
func inherit_projection(world: WorldState, projected: WorldState) -> void:
	if world==projected or world.facts.connectors.is_empty(): return
	var original: Dictionary = _topology(world)
	_prune_topologies()
	var inherited: Dictionary = original.duplicate()
	inherited.world = weakref(projected)
	inherited.revision = projected.geometry_revision
	_topologies[projected.get_instance_id()] = inherited
	space.query_counts["connector_topology_inherits"] = int(space.query_counts.get("connector_topology_inherits",0))+1

func _prune_topologies() -> void:
	for old: int in _topologies.keys():
		if _topologies[old].world.get_ref()==null: _topologies.erase(old)

func _topology(world: WorldState) -> Dictionary:
	var key: int = world.get_instance_id()
	var cached: Dictionary = _topologies.get(key,{})
	var basis: Array = connection_basis(world)
	if not cached.is_empty() and cached.world.get_ref()==world and int(cached.revision)==world.geometry_revision and cached.get("basis",[])==basis: return cached
	_prune_topologies()
	cached = {"world":weakref(world),"revision":world.geometry_revision,"basis":basis.duplicate(true),"explicit":{},"ranges":{},"floors":{},"candidates":{},"nodes":{},"node_ids":["start","goal"],"stops":{},"extra_floors":{}}
	for floor_key: String in world.facts.floors.overrides: cached.candidates[int(floor_key)] = true
	var connector_ids: Array = world.ids("connectors")
	for id: String in connector_ids:
		var connection: Dictionary = world.facts.connectors[id]
		for floor_id: int in HospitalTransit.endpoints(connection): cached.candidates[floor_id] = true
		if connection.has("first_floor"):
			cached.ranges[id] = [int(connection.first_floor),int(connection.last_floor)]
		else:
			for floor_id: int in connection.stops:
				if not cached.explicit.has(floor_id): cached.explicit[floor_id] = []
				cached.explicit[floor_id].append(id)
	# Stable structural declarations are shared by every point query until a
	# topology revision. Only the queried source/target can add other floors.
	for id: String in connector_ids:
		var connection: Dictionary = world.facts.connectors[id]
		cached.stops[id] = HospitalTransit.routing_stops(connection,world,0,0,cached.candidates)
		var anchor: Vector2i = Vector2i(int(connection.anchor[0]),int(connection.anchor[1]))
		for floor_id: int in cached.stops[id]:
			var node_id: String = id+":"+str(floor_id)
			cached.nodes[node_id] = {"floor_id":floor_id,"cell":anchor}
			cached.node_ids.append(node_id)
	_topologies[key] = cached
	space.query_counts.connector_topology_builds += 1
	space.query_counts["connector_node_declarations"] = int(space.query_counts.get("connector_node_declarations",0))+cached.nodes.size()
	return cached

func _floor_connections(topology: Dictionary, floor_id: int) -> Array:
	if not topology.floors.has(floor_id):
		var ids: Array = topology.explicit.get(floor_id,[]).duplicate()
		for id: String in topology.ranges:
			var interval: Array = topology.ranges[id]
			if floor_id>=int(interval[0]) and floor_id<=int(interval[1]): ids.append(id)
		ids.sort()
		topology.floors[floor_id] = ids
	return topology.floors[floor_id]

func _topology_floor_nodes(world: WorldState, topology: Dictionary, floor_id: int) -> Dictionary:
	if not topology.extra_floors.has(floor_id):
		var entry: Dictionary = {"nodes":{},"ids":[],"connectors":_floor_connections(topology,floor_id)}
		for id: String in entry.connectors:
			var connection: Dictionary = world.facts.connectors[id]
			var node_id: String = id+":"+str(floor_id)
			entry.nodes[node_id] = {"floor_id":floor_id,"cell":Vector2i(int(connection.anchor[0]),int(connection.anchor[1]))}
			entry.ids.append(node_id)
		topology.extra_floors[floor_id] = entry
		space.query_counts["connector_node_extensions"] = int(space.query_counts.get("connector_node_extensions",0))+entry.nodes.size()
	return topology.extra_floors[floor_id]

func _point_route(world: WorldState, actor: Dictionary, source_floor: int, start: Vector2i, target_floor: int, goal: Vector2i, members: Array, offsets: Dictionary, initial_ticks: int, distance_only: bool) -> Dictionary:
	var direct: Dictionary = {"ok":false,"status":"unreachable","reason":"没有合法通路"}
	if source_floor==target_floor:
		direct = _floor_route(world,actor,source_floor,start,goal,members,offsets,true,{},true,distance_only)
		# Current floor edges have unit cost. A sole connector returns to the
		# same anchor, so leaving and returning cannot improve this shortest walk.
		if direct.ok and (world.facts.connectors.size()<=1 or int(direct.walking_distance)==absi(goal.x-start.x)+absi(goal.y-start.y)):
			direct.travel_ticks = HospitalTransit._add(initial_ticks,HospitalTransit.walking_ticks(space,actor,members,float(direct.walking_distance)))
			if int(direct.travel_ticks)<0: return {"ok":false,"status":"time_overflow","reason":"基准通行时间超出整数范围"}
			# This new case previously returned the full solver's float distance.
			if world.facts.connectors.size()==1 and int(direct.walking_distance)!=absi(goal.x-start.x)+absi(goal.y-start.y): direct.walking_distance = float(direct.walking_distance)
			direct.quoted_tick = world.sim_tick
			if distance_only: direct.erase("path")
			return direct
	space.query_counts["transport_requests"] = int(space.query_counts.get("transport_requests",0))+1
	var nodes: Dictionary = {"start":{"floor_id":source_floor,"cell":start},"goal":{"floor_id":target_floor,"cell":goal}}
	var topology: Dictionary = _topology(world)
	var node_ids: Array = topology.node_ids
	if actor.has("_convoy_size"):
		for id: String in topology.nodes:
			var node: Dictionary = topology.nodes[id].duplicate()
			var cid: String = id.get_slice(":",0)
			var p: Dictionary = ConvoyPortal.plan(space,world,world.facts.connectors[cid],actor.id,members,world.facts.moves[actor.id].convoy)
			if p.get("ok",false):
				node.cell = Vector2i(ConvoyTrail.point(p.egress)+Vector2.ONE*float(world.facts.moves[actor.id].convoy.shift))
				node.convoy = ConvoyPortal.predict(world.facts.moves[actor.id].convoy,p,int(node.floor_id))
			nodes[id] = node
	var extra_stops: Dictionary = {}
	for floor_id: int in {source_floor:true,target_floor:true}:
		if topology.candidates.has(floor_id): continue
		var extra: Dictionary = _topology_floor_nodes(world,topology,floor_id)
		if extra.ids.is_empty(): continue
		if is_same(node_ids,topology.node_ids): node_ids = node_ids.duplicate()
		node_ids.append_array(extra.ids)
		for id: String in extra.nodes:
			var node: Dictionary = extra.nodes[id].duplicate()
			if actor.has("_convoy_size"):
				var cid: String = id.get_slice(":",0)
				var p: Dictionary = ConvoyPortal.plan(space,world,world.facts.connectors[cid],actor.id,members,world.facts.moves[actor.id].convoy)
				if p.get("ok",false):
					node.cell = Vector2i(ConvoyTrail.point(p.egress)+Vector2.ONE*float(world.facts.moves[actor.id].convoy.shift))
					node.convoy = ConvoyPortal.predict(world.facts.moves[actor.id].convoy,p,int(node.floor_id))
			nodes[id] = node
		for id: String in extra.connectors:
			if not extra_stops.has(id): extra_stops[id] = []
			extra_stops[id].append(floor_id)
	# Native vertex declarations reuse the topology; floor A* still runs only
	# when Boost settles a node and requests its business-defined outgoing edges.
	# Compatibility is independent of the destination. The existing sealed
	# read-only scope owns reuse for this exact actor and ordered member list.
	var compatible: Dictionary = space.read_view(world,"point_connector_fits:"+JSON.stringify([actor.id,members]),func()->Dictionary:return {})
	var prepared: Dictionary = _connector_preparation(world,actor,members,offsets,distance_only,topology,extra_stops)
	var context: Dictionary = {"nodes":nodes,"stops":topology.stops,"extra_stops":extra_stops,"query_stops":{},"topology":topology,"connections":{},"compatible":compatible,"connector_prepared":prepared,"edges":{},"source_floor":source_floor,"target_floor":target_floor,"goal":goal,"members":members,"offsets":offsets,"distance_only":distance_only,"direct":direct}
	if distance_only and members.is_empty() and offsets.is_empty() and world.facts.connectors.size()==1:
		var connection: Dictionary = world.facts.connectors.values()[0]
		context.direct_lift_stops = space.content.definition("vertical_connectors",connection.definition_id).kind=="lift"
	var shared: Dictionary = _source_quote(world,actor,context,node_ids,initial_ticks)
	if not shared.is_empty(): return shared
	space.query_counts.transport_searches += 1
	var solved: Dictionary = PlatformArrivalMath.route_search({"nodes":node_ids,"start":"start","goal":"goal","initial_ticks":initial_ticks,"expand":_point_edges.bind(world,actor,context)})
	if solved.has("error"):
		return {"ok":false,"status":"navigation_failed","reason":str(solved.get("bottleneck",solved.error))}
	if solved.get("ok",false):
		var chain: Array = solved.nodes
		var chunks: Array = []
		var distance: float = 0.0
		# Retain the original reverse accumulation order for floating distances.
		for index: int in range(chain.size()-1,0,-1):
			var edge: Dictionary = context.edges[chain[index-1]][chain[index]]
			distance += float(edge.walking_distance)
			if not distance_only: chunks.push_front(edge.path)
		var result: Dictionary = {"ok":true,"status":"complete","reason":"","walking_distance":distance,"travel_ticks":int(solved.travel_ticks),"quoted_tick":world.sim_tick}
		if not distance_only:
			var path: Array = []
			# Returned executable segments belong to this journey. Connector
			# preparation remains immutable when a caller edits its own path.
			for chunk: Array in chunks: path.append_array(chunk.duplicate(true))
			result.path = path
		return result
	if direct.ok: return {"ok":false,"status":"time_overflow","reason":"基准通行时间超出整数范围"}
	return direct if source_floor==target_floor else {"ok":false,"status":"unreachable","reason":"没有身体、停层和运行方向均合法的竖向通路"}

# The task consumes only exact candidate times. A warm field stays local to
# that synchronous loop; executable routes and complex journeys use the solver.
func _waiting_cost_basis(world: WorldState, actor_id: String, floor_id: int, bounds: Dictionary, prepare_source: bool = false) -> Dictionary:
	if not space.in_dynamic_route_query(world) or world.facts.connectors.size()>1: return {}
	var bases: Dictionary = space.read_view(world,"waiting_cost_bases",func()->Dictionary:return {})
	var floors: Dictionary = bases.get_or_add(actor_id,{})
	var retained: Dictionary = floors.get(floor_id,{})
	if prepare_source and not retained.is_empty() and retained.bounds==bounds: return retained.basis
	var owner: Dictionary = space.read_view(world,"point_journeys",func()->Dictionary:return {})
	var subjects: Dictionary = owner.get_or_add("subjects",{})
	if prepare_source and not subjects.has(actor_id): subjects[actor_id] = _prepare_route_subject(world,world.facts.actors[actor_id],[],{})
	var subject: Dictionary = subjects.get(actor_id,{})
	if subject.is_empty() or not str(subject.reason).is_empty(): return {}
	var actor: Dictionary = world.facts.actors[actor_id]
	var root: Vector2i = subject.start
	var prefix: int = int(subject.initial_ticks)
	if int(subject.floor_id)!=floor_id:
		if world.facts.connectors.size()!=1 or bounds.get("unknown",false) or bounds.get("landings",[]).size()!=1: return {}
		var connection: Dictionary = world.facts.connectors.values()[0]
		if space.content.definition("vertical_connectors",connection.definition_id).kind!="lift": return {}
		var landing: Dictionary = bounds.landings[0]
		root = Vector2i(int(connection.anchor[0]),int(connection.anchor[1]))
		if Vector2(landing.cell)!=Vector2(root): return {}
		# _entry_landings already issued this complete structural quote in the
		# same owner. It proves actual stop, direction, body and fractional stub.
		var quote_key: String = JSON.stringify([floor_id,connection.anchor,true],"",true,true)
		var quote: Dictionary = subject.get("journeys",{}).get(quote_key,{})
		if not quote.get("ok",false) or not quote.has("travel_ticks") or int(quote.travel_ticks)!=int(landing.ticks): return {}
		prefix = int(quote.travel_ticks)
	var basis: Dictionary = {"root":root,"prefix_ticks":prefix,"speed":float(space.content.balance.movement_speeds[str(space.clearance(actor))])}
	if prepare_source: floors[floor_id] = {"bounds":bounds.duplicate(true),"basis":basis}
	return basis

# A single connector cannot improve a same-floor walk by returning to its
# own anchor. A sole lift's complete landing quote already proves the entire
# cross-floor prefix. Only the final floor leg varies between waiting cells.
func waiting_travel_ticks(world: WorldState, actor_id: String, floor_id: int, point: Vector2i, bounds: Dictionary) -> Dictionary:
	var basis: Dictionary = _waiting_cost_basis(world,actor_id,floor_id,bounds,true)
	if basis.is_empty(): return {}
	var actor: Dictionary = world.facts.actors[actor_id]
	var leg: Dictionary = _floor_route(world,actor,floor_id,basis.root,point,[],{},true,{},true,true)
	space.query_counts["public_entry_leg_quotes"] = int(space.query_counts.get("public_entry_leg_quotes",0))+1
	if not leg.ok: return {"ready":true,"travel_ticks":-1}
	# The sealed single-actor basis already resolved this same walking speed.
	return {"ready":true,"travel_ticks":HospitalTransit._add(int(basis.prefix_ticks),ceili(float(leg.walking_distance)/float(basis.speed)/WorldState.TICK_SECONDS))}

func ready_waiting_cost_field(world: WorldState, actor_id: String, floor_id: int, bounds: Dictionary) -> Dictionary:
	var basis: Dictionary = _waiting_cost_basis(world,actor_id,floor_id,bounds)
	if basis.is_empty(): return {}
	var actor: Dictionary = world.facts.actors[actor_id]
	var field: Dictionary = space._navigation.ready_structural_field(space,world,floor_id,actor,basis.root)
	if not field.get("ready",false): return {}
	_observe_floor(world,actor_id,floor_id)
	space.query_counts["public_entry_field_preparations"] = int(space.query_counts.get("public_entry_field_preparations",0))+1
	return {"ready":true,"distances":field.distances,"prefix_ticks":basis.prefix_ticks,"speed":basis.speed}

func _source_quote(world: WorldState, actor: Dictionary, context: Dictionary, node_ids: Array, initial_ticks: int) -> Dictionary:
	if not context.distance_only or not context.members.is_empty() or not context.offsets.is_empty() or not space.in_dynamic_route_query(world): return {}
	var owner: Dictionary = space.dynamic_transport_view(world,actor.id,[],{})
	var retained: Dictionary = owner.get("point_source_queries",{})
	if retained.is_empty() or not is_same(retained.topology,context.topology):
		retained = {"topology":context.topology,"variants":{}}
		owner.point_source_queries = retained
	var start: Vector2i = context.nodes.start.cell
	var key: String = JSON.stringify([context.source_floor,start.x,start.y,initial_ticks,context.extra_stops],"",true,true)
	var source: Dictionary = retained.variants.get(key,{})
	if source.is_empty():
		# Preserve lazy single-goal work. Only a second distinct goal establishes
		# demand for a complete source tree inside this sealed candidate batch.
		retained.variants[key] = {"seen":true}
		return {}
	if not source.has("tree"):
		var common: Dictionary = context.duplicate()
		common.single_source = true
		common.direct_lift_stops = false
		if world.facts.connectors.size()==1:
			var connection: Dictionary = world.facts.connectors.values()[0]
			common.direct_lift_stops = space.content.definition("vertical_connectors",connection.definition_id).kind=="lift"
		common.edges = {}
		common.connections = {}
		common.query_stops = {}
		space.query_counts.transport_searches += 1
		space.query_counts["point_source_builds"] = int(space.query_counts.get("point_source_builds",0))+1
		source.tree = PlatformArrivalMath.route_search({"nodes":node_ids,"start":"start","goal":"goal","initial_ticks":initial_ticks,"single_source":true,"expand":_point_edges.bind(world,actor,common)})
		source.context = common
	else:
		space.query_counts["point_source_hits"] = int(space.query_counts.get("point_source_hits",0))+1
	var tree: Dictionary = source.tree
	if tree.has("error"): return {"ok":false,"status":"navigation_failed","reason":str(tree.get("bottleneck",tree.error))}
	var direct: Dictionary = context.direct
	var best: Dictionary = {}
	if direct.ok:
		var ticks: int = HospitalTransit._add(initial_ticks,HospitalTransit.walking_ticks(space,actor,[],float(direct.walking_distance)))
		if ticks>=0: best = {"node":"start","ticks":ticks,"distance":float(direct.walking_distance)}
	# The library's real settlement order includes zero-edge discoveries. A
	# globally sorted label list could pick a different equally short journey.
	for label: Dictionary in tree.settled:
		if not best.is_empty() and int(label.travel_ticks)>=int(best.ticks): break
		var id: String = str(label.id)
		if id=="start": continue
		var node: Dictionary = source.context.nodes.get(id,source.context.topology.nodes.get(id,{}))
		if int(node.floor_id)!=int(context.target_floor): continue
		var finish: Dictionary = _floor_route(world,actor,int(node.floor_id),node.cell,context.goal,[],{},true,{},true,true)
		space.query_counts["point_source_goal_legs"] = int(space.query_counts.get("point_source_goal_legs",0))+1
		if not finish.ok: continue
		var ticks: int = HospitalTransit._add(int(label.travel_ticks),HospitalTransit.walking_ticks(space,actor,[],float(finish.walking_distance)))
		if ticks>=0 and (best.is_empty() or ticks<int(best.ticks)): best = {"node":id,"ticks":ticks,"distance":float(finish.walking_distance)}
	if not best.is_empty():
		var distance: float = 0.0
		distance += float(best.distance)
		var current: String = str(best.node)
		while current!="start":
			var previous: String = str(tree.previous[current])
			distance += float(source.context.edges[previous][current].walking_distance)
			current = previous
		return {"ok":true,"status":"complete","reason":"","walking_distance":distance,"travel_ticks":int(best.ticks),"quoted_tick":world.sim_tick}
	if direct.ok: return {"ok":false,"status":"time_overflow","reason":"基准通行时间超出整数范围"}
	return direct if int(context.source_floor)==int(context.target_floor) else {"ok":false,"status":"unreachable","reason":"没有身体、停层和运行方向均合法的竖向通路"}

func _connector_preparation(world: WorldState, actor: Dictionary, members: Array, offsets: Dictionary, distance_only: bool, topology: Dictionary, extra_stops: Dictionary) -> Dictionary:
	# This existing owner lasts only for one real, synchronous candidate batch;
	# ordinary queries outside a dynamic scope receive a fresh disposable view.
	var owner: Dictionary = space.dynamic_transport_view(world,actor.id,members,offsets)
	var retained: Dictionary = owner.get("point_connector_edges",{})
	if retained.is_empty() or not is_same(retained.topology,topology):
		retained = {"topology":topology,"variants":{}}
		owner.point_connector_edges = retained
	# A query can introduce source/target floors absent from the topology.
	# Its complete stop declaration and output mode define one expansion view.
	var variant: String = JSON.stringify([distance_only,extra_stops],"",true,true)
	return retained.variants.get_or_add(variant,{})

func _point_edges(id: String, world: WorldState, actor: Dictionary, context: Dictionary) -> Array:
	var node: Dictionary = context.nodes.get(id,context.topology.nodes.get(id,{}))
	var floor_id: int = int(node.floor_id)
	var target_floor: int = int(context.target_floor)
	var members: Array = context.members
	var offsets: Dictionary = context.offsets
	var distance_only: bool = bool(context.distance_only)
	var outgoing: Array = []
	var facts: Dictionary = {}
	if not context.get("single_source",false) and floor_id==target_floor:
		var finish: Dictionary = context.direct if id=="start" and int(context.source_floor)==target_floor else _floor_route(world,actor,target_floor,node.cell,context.goal,members,offsets,true,{},true,distance_only)
		if finish.ok:
			var ticks: int = HospitalTransit.walking_ticks(space,actor,members,float(finish.walking_distance))
			if ticks>=0:
				outgoing.append({"to":"goal","ticks":ticks})
				facts.goal = {"path":[] if distance_only else finish.path,"walking_distance":float(finish.walking_distance)}
	# The sole lift's start already offered every legal stop. Linear integer
	# travel and nonnegative boarding/alighting make another ride unhelpful.
	# A lazy goal query still consumes its complete target-floor finish above;
	# the common source tree has no target edge and retains only start edges.
	if context.get("direct_lift_stops",false) and id!="start":
		if not context.get("single_source",false): space.query_counts["point_cost_lift_arrival_prunes"] = int(space.query_counts.get("point_cost_lift_arrival_prunes",0))+1
		context.edges[id] = facts
		return outgoing
	var prepared: Dictionary = context.get("connector_prepared",{}).get_or_add(floor_id,{})
	var connectors: Dictionary = prepared.get(node.cell,{})
	if connectors.is_empty():
		connectors = _connector_edges(world,actor,context,node)
		prepared[node.cell] = connectors
		space.query_counts["connector_edge_builds"] = int(space.query_counts.get("connector_edge_builds",0))+1
	else:
		space.query_counts["connector_edge_hits"] = int(space.query_counts.get("connector_edge_hits",0))+1
	# Goal is target-dependent and remains first. The cached arrays contain no
	# goal edge and are only read while composing this query's private result.
	outgoing.append_array(connectors.outgoing)
	facts.merge(connectors.facts)
	context.edges[id] = facts
	return outgoing

func _connector_edges(world: WorldState, actor: Dictionary, context: Dictionary, node: Dictionary) -> Dictionary:
	var floor_id: int = int(node.floor_id)
	var members: Array = context.members
	var offsets: Dictionary = context.offsets
	var distance_only: bool = bool(context.distance_only)
	var outgoing: Array = []
	var facts: Dictionary = {}
	if not context.connections.has(floor_id):
		context.connections[floor_id] = []
		for connector_id: String in _floor_connections(context.topology,floor_id):
			space.query_counts.candidate_connections += 1
			var connection: Dictionary = world.facts.connectors[connector_id]
			if not HospitalTransit.has_stop(connection,floor_id): continue
			if not context.compatible.has(connector_id): context.compatible[connector_id] = HospitalTransit.fits(space,world,connection,actor.id,members).ok
			if context.compatible[connector_id]: context.connections[floor_id].append(connector_id)
	for connector_id: String in context.connections[floor_id]:
		var connection: Dictionary = world.facts.connectors[connector_id]
		var anchor: Vector2i = Vector2i(int(connection.anchor[0]),int(connection.anchor[1]))
		var portal: Dictionary = {}
		if actor.has("_convoy_size") and space.content.definition("vertical_connectors",connection.definition_id).kind!="stairs":
			portal = ConvoyPortal.plan(space,world,connection,actor.id,members,world.facts.moves[actor.id].convoy)
			if not portal.get("ok",false): continue
			anchor = Vector2i(ConvoyTrail.point(portal.entry)+Vector2.ONE*float(world.facts.moves[actor.id].convoy.shift))
		var before: Dictionary = _convoy_portal_approach(world,actor,floor_id,node,portal) if not portal.is_empty() else _floor_route(world,actor,floor_id,node.cell,anchor,members,offsets,true,{},true,distance_only)
		if not before.ok: continue
		var definition: Dictionary = space.content.definition("vertical_connectors",connection.definition_id)
		var walking: int = HospitalTransit.walking_ticks(space,actor,members,float(before.walking_distance))
		var boarding: int = HospitalTransit._boarding(definition)
		var alighting: int = HospitalTransit._alighting(definition)
		if not portal.is_empty():
			boarding = int(portal.boarding_ticks)
			alighting = int(portal.alighting_ticks)
		var destinations: Array = context.stops[connector_id]
		if context.extra_stops.has(connector_id):
			if not context.query_stops.has(connector_id):
				context.query_stops[connector_id] = destinations.duplicate()
				context.query_stops[connector_id].append_array(context.extra_stops[connector_id])
				context.query_stops[connector_id].sort()
			destinations = context.query_stops[connector_id]
		for destination: int in destinations:
			if destination==floor_id or definition.kind=="stairs" and absi(destination-floor_id)!=1: continue
			if HospitalTransit._lowering(connection) and destination>=floor_id: continue
			var travel: int = HospitalTransit._travel_ticks(space,connection,floor_id,destination)
			var ticks: int = HospitalTransit._add(walking,HospitalTransit._add(boarding,HospitalTransit._add(travel,alighting)))
			if ticks<0: continue
			var next: String = connector_id+":"+str(destination)
			var path: Array = [] if distance_only else before.path.duplicate()
			if not distance_only: path.append({"kind":"connector","connector_id":connector_id,"from":floor_id,"to":destination})
			outgoing.append({"to":next,"ticks":ticks})
			facts[next] = {"path":path,"walking_distance":float(before.walking_distance)}
	return {"outgoing":outgoing,"facts":facts}

func _floor_route(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2i, goal: Vector2i, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false, navigation: Dictionary = {}, structural_only: bool = false, cost_only: bool = false) -> Dictionary:
	if actor.has("_convoy_size"):
		members = []
		offsets = {}
	_observe_floor(world,str(actor.id),floor_id)
	var routes: Dictionary = {}
	var key: Variant = ""
	var cacheable: bool = false
	if navigation.is_empty() and structural_only and ignore_people and cost_only and members.is_empty() and offsets.is_empty() and space.in_dynamic_route_query(world):
		# Body and mode are fixed by this sealed real-candidate batch. Keep the
		# complete endpoint result without serializing that same body per goal.
		var owner: Dictionary = space.read_view(world,"point_floor_costs",func()->Dictionary:return {"revision":world.geometry_revision,"actors":{}})
		if int(owner.revision)!=world.geometry_revision:
			owner.revision = world.geometry_revision
			owner.actors.clear()
		var floors: Dictionary = owner.actors.get_or_add(str(actor.id),{})
		routes = floors.get_or_add(floor_id,{})
		key = Vector4i(start.x,start.y,goal.x,goal.y)
		cacheable = true
	elif navigation.is_empty() and not space._route_queries.is_empty() and space._route_queries.back().world==world and (ignore_people or space._route_queries.back().get("dynamic",false)):
		routes = space._route_queries.back().routes
		var identity: Variant = actor.id
		if not space._route_queries.back().reference.is_empty() and members.is_empty() and offsets.is_empty():
			identity = [space.body(actor),[] if structural_only else RouteClearance.reservation_exemptions(world,actor.id,floor_id)]
		key = JSON.stringify([identity,floor_id,start.x,start.y,goal.x,goal.y,members,offsets,ignore_people,structural_only,cost_only,_route_envelope(world,actor,members,offsets)])
		cacheable = true
	if cacheable and routes.has(key):
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
	elif navigation.has("member_geometries"):
		query = RouteClearance.new(space,world,actor,floor_id,members,offsets,true,graph.geometry.source,graph.geometry,navigation.member_geometries)
	else: query = space._navigation.clearance(space,world,floor_id,actor) if members.is_empty() else RouteClearance.new(space,world,actor,floor_id,members,offsets,true,graph.geometry.source)
	var people: Callable = Callable()
	var dynamic: Dictionary = {}
	var convoy_start: bool = actor.has("_convoy_size") and actor.location.kind=="floor" and int(actor.location.floor_id)==floor_id and start==Vector2i(ConvoyTrail.point(actor.location.cell).round())
	if not ignore_people or convoy_start:
		people = func(from_cell: Vector2i,to_cell: Vector2i) -> bool:
			if to_cell==goal and actor.has("_convoy_goal_direction") and Vector2(to_cell-from_cell).dot(actor._convoy_goal_direction)<-0.00001: return false
			if convoy_start:
				var unit: Dictionary = world.facts.moves.get(actor.id,{})
				if unit.has("convoy") and unit.members.size()>1:
					if from_cell==start and unit.convoy.points.size()>1:
						var forward: Vector2 = ConvoyTrail.point(unit.convoy.points[-1])-ConvoyTrail.point(unit.convoy.points[-2])
						if Vector2(to_cell-from_cell).dot(forward)<-0.00001: return false
					var prefix: Array = unit.convoy.points.duplicate(true)
					prefix.reverse()
					prefix = ConvoyTrail.drop(prefix,float(unit.convoy.spacing))
					prefix.reverse()
					var swept: Rect2 = Rect2(Vector2(from_cell),Vector2.ONE*int(unit.convoy.size)).merge(Rect2(Vector2(to_cell),Vector2.ONE*int(unit.convoy.size)))
					for region: Rect2 in ConvoyTrail.regions(unit.convoy,prefix):
						if swept.intersects(region,false): return false
			return true if ignore_people else space._unit_step_dynamic_clear(world,actor,floor_id,from_cell,to_cell,members,offsets,dynamic)
	var result: Dictionary
	var repeated: Dictionary = {}
	if not convoy_start and cost_only and ignore_people and members.is_empty() and offsets.is_empty() and not navigation.has("query") and not navigation.get("overlay",false) and navigation.bases.is_empty() and navigation.shifts.is_empty():
		# The structural graph was acquired above in this same invocation. No
		# intervening query can refresh it; dynamic clearance keeps its own path.
		repeated = space._navigation.forward_distance(space,world,floor_id,actor,start,goal,structural_only,graph if fresh_structural_graph else null)
		if structural_only and not repeated.get("ready",false):
			space.query_counts["structural_reverse_field_lookups"] = int(space.query_counts.get("structural_reverse_field_lookups",0))+1
			var reverse: Dictionary = space._navigation.reverse_structural_distance(space,world,floor_id,actor,start,goal,graph if fresh_structural_graph else null)
			# Failed fields retain the original cached/A* result and failure schema.
			if reverse.get("ready",false) and reverse.get("ok",false):
				repeated = reverse
				space.query_counts["structural_reverse_field_hits"] = int(space.query_counts.get("structural_reverse_field_hits",0))+1
	if repeated.get("ready",false):
		space.query_counts["distance_field_hits"] = int(space.query_counts.get("distance_field_hits",0))+1
		result = {"ok":bool(repeated.ok),"status":"complete" if repeated.ok else "unreachable","reason":repeated.get("reason",""),"walking_distance":int(repeated.get("distance",-1))}
	elif not convoy_start and not structural_only and members.is_empty() and offsets.is_empty() and not navigation.has("query") and not navigation.get("overlay",false) and navigation.bases.is_empty() and navigation.shifts.is_empty() and not query.has_reservations():
		# A live single-body query with no unauthorized facility regions has
		# exactly the graph's static clearance. Reuse its loading-time path;
		# the ordinary people/door-reservation validation below remains live.
		# Queries with reservations retain their original search and tie order.
		result = space._navigation.cached_floor_path(space,world,floor_id,actor,graph,graph.geometry,start,goal,cost_only)
	elif not convoy_start and (structural_only or not space._route_queries.is_empty() and space._route_queries.back().world==world) and members.is_empty() and offsets.is_empty() and not navigation.has("query") and not navigation.get("overlay",false) and navigation.bases.is_empty() and navigation.shifts.is_empty():
		# Actual dispatch has no read-only query scope. Its pure static floor
		# leg can still reuse the resident body/floor/endpoint cache, including
		# lift landings to guidance desks. Live reservations and collisions
		# remain owned by movement; local dynamic replans keep their old scope.
		result = space._navigation.cached_floor_path(space,world,floor_id,actor,graph,query,start,goal,cost_only)
	else:
		if convoy_start and not ignore_people: dynamic.merge(space._dynamic_route_query(world,actor,floor_id,members,offsets),true)
		result = graph.find_path(start,goal,query,people if convoy_start else Callable(),false,navigation.bases,navigation.shifts,bool(navigation.get("overlay",false)),cost_only)
	if result.ok and people.is_valid() and not cost_only:
		var low: Vector2 = Vector2(start)
		var high: Vector2 = low
		for cell: Array in result.cells:
			low = low.min(Vector2(float(cell[0]),float(cell[1])))
			high = high.max(Vector2(float(cell[0]),float(cell[1])))
		var shape: Rect2 = space._unit_rect(world,actor,Vector2.ZERO,members,offsets)
		var broad: Rect2 = Rect2(low+shape.position,high-low+shape.size)
		if actor.has("_convoy_size") or not space._dynamic_clear(world,actor.id,floor_id,broad,members):
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
				var candidate_search: bool=actual_start or bool(people.call(goal,goal))
				var sealed_goal: bool=false
				if candidate_search and not actual_start and start!=goal and not convoy_start and not actor.has("_convoy_size") and not actor.has("_convoy_body") and not actor.has("_convoy_goal_direction") and members.is_empty() and offsets.is_empty() and not navigation.get("overlay",false) and navigation.bases.is_empty() and navigation.shifts.is_empty():
					sealed_goal=not _dynamic_goal_has_entry(graph,goal,people)
					if sealed_goal: space.query_counts["dynamic_goal_entry_prunes"]=int(space.query_counts.get("dynamic_goal_entry_prunes",0))+1
				if candidate_search and not sealed_goal:
					dynamic.merge(space._dynamic_route_query(world,actor,floor_id,members,offsets),true)
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
	if cacheable:
		routes[key] = result.duplicate(true)
	return result

# A cardinal graph path must finish along one of these exact directed edges.
# If every existing incoming edge fails the same live people predicate used
# by A*, that search can only fail. Do not alter routes with any open entry.
func _dynamic_goal_has_entry(graph: FloorNavigation, goal: Vector2i, people: Callable) -> bool:
	var goal_id: int=FloorNavigation._id(goal)
	if not graph.has_point(goal_id): return true
	for offset: Vector2i in FloorNavigation.NEIGHBOURS:
		var predecessor: Vector2i=goal+offset
		if not FloorNavigation._inside(predecessor): continue
		var from_id: int=FloorNavigation._id(predecessor)
		if graph.has_point(from_id) and graph.are_points_connected(from_id,goal_id,false) and bool(people.call(predecessor,goal)):
			return true
	return false

func _route_envelope(world: WorldState, actor: Dictionary, members: Array, offsets: Dictionary) -> Array:
	var result: Array = [[space.body(actor),actor.get("posture","standing"),float(actor.get("facing",0.0)),[0,0]]]
	for member_id: String in members:
		if member_id==actor.id: continue
		var member: Dictionary = world.facts.actors[member_id]
		result.append([space.body(member),member.get("posture","standing"),float(member.get("facing",0.0)),offsets[member_id]])
	return result


# Group queries have a single traversal envelope. A read-only projection gives
# transit access to the same queue definition before actual gathering completes.
func _convoy_query_movement(world: WorldState, primary: String, members: Array) -> Dictionary:
	var existing: Dictionary = world.facts.moves.get(primary,{})
	if existing.has("convoy") and existing.members==members: return existing
	# A legal, physically assembled queue already owns its real direction and
	# spacing even before a move is requested. Do not invent an eastbound tail
	# for its read-only quote. Unassembled planning retains a pure projection.
	var assembled: Dictionary = ConvoyTrail.create(space,world,primary,members)
	if assembled.ok: return {"actor_id":primary,"members":members.duplicate(),"convoy":assembled.convoy}
	var form: Dictionary = ConvoyTrail.formation(space,world,primary,members)
	var head: Vector2 = ConvoyTrail.point(world.facts.actors[primary].location.cell)
	var tail: Vector2 = head-Vector2.RIGHT*float(form.spacing)*(members.size()-1)
	return {"actor_id":primary,"members":members.duplicate(),"convoy":{"version":1,"points":[[tail.x,tail.y],[head.x,head.y]] if members.size()>1 else [[head.x,head.y]],"spacing":form.spacing,"size":form.size,"centers":form.centers,"floor_id":int(world.facts.actors[primary].location.floor_id),"shift":form.shift,"height":form.height}}

func _convoy_route_result(world: WorldState, primary: String, floor_id: int, target: Array, members: Array, offsets: Dictionary, cost_only: bool) -> Dictionary:
	if not offsets.is_empty(): return {"ok":false,"status":"unreachable","reason":"同行组只支持前后队列"}
	if members.is_empty() or members[0]!=primary: return {"ok":false,"status":"unreachable","reason":"队列首位必须是队长"}
	var seen: Dictionary = {}
	for id: String in members:
		if not world.facts.actors.has(id) or seen.has(id): return {"ok":false,"status":"unreachable","reason":"队列成员无效"}
		seen[id] = true
	if world.facts.actors[primary].location.kind!="floor": return {"ok":false,"status":"unavailable","reason":"等待队长真实落地"}
	var m: Dictionary = _convoy_query_movement(world,primary,members)
	var facts: Dictionary = world.facts.duplicate()
	facts.moves = world.facts.moves.duplicate()
	facts.moves[primary] = m
	var projected: WorldState = WorldState.new(facts)
	inherit_projection(world,projected)
	var proxy: Dictionary = ConvoyTrail.proxy(projected,m)
	var shift: Vector2 = Vector2.ONE*float(m.convoy.shift)
	var actual: Vector2 = ConvoyTrail.point(proxy.location.cell)
	var goal_actual: Vector2 = ConvoyTrail.point(target)+shift
	var start: Vector2i = Vector2i(actual.round())
	if m.convoy.points.size()>1:
		var forward: Vector2 = ConvoyTrail.point(m.convoy.points[-1])-ConvoyTrail.point(m.convoy.points[-2])
		if forward.x>0: start.x=ceili(actual.x)
		elif forward.x<0: start.x=floori(actual.x)
		if forward.y>0: start.y=ceili(actual.y)
		elif forward.y<0: start.y=floori(actual.y)
	var goal: Vector2i = Vector2i(floori(goal_actual.x) if goal_actual.x>=actual.x else ceili(goal_actual.x),floori(goal_actual.y) if goal_actual.y>=actual.y else ceili(goal_actual.y))
	var entry: Dictionary = _convoy_grid_stub(projected,proxy,int(proxy.location.floor_id),actual,Vector2(start))
	if not entry.ok: return {"ok":false,"status":"unreachable","reason":entry.reason}
	var exit: Dictionary = _convoy_grid_stub(projected,proxy,floor_id,Vector2(goal),goal_actual)
	if not exit.ok: return {"ok":false,"status":"unreachable","reason":exit.reason}
	if not entry.points.is_empty():
		# The route graph begins after the real fractional prefix. Portal
		# alignment and own-tail proofs must start from that predicted trail,
		# not from the unadvanced fractional head in the caller's world.
		var prefix: Array = []
		for point: Array in entry.points: prefix.append({"kind":"floor","floor_id":int(proxy.location.floor_id),"cell":point})
		var prediction: Dictionary = _convoy_predict_floor_path(m.convoy,prefix,shift)
		if not prediction.ok: return {"ok":false,"status":"unreachable","reason":prediction.reason}
		var trial: Dictionary = m.convoy.duplicate(true)
		trial.points = prediction.points
		projected = _convoy_route_projection(projected,m,trial,int(proxy.location.floor_id),Vector2(start)-shift)
		inherit_projection(world,projected)
		proxy = ConvoyTrail.proxy(projected,projected.facts.moves[primary])
	var result: Dictionary = _point_route(projected,proxy,int(proxy.location.floor_id),start,floor_id,goal,members,{},int(entry.ticks),cost_only)
	if not result.get("ok",false) and int(proxy.location.floor_id)==floor_id:
		var prefix: Array = []
		for point: Array in entry.points: prefix.append({"kind":"floor","floor_id":floor_id,"cell":point})
		var prediction: Dictionary = _convoy_predict_floor_path(m.convoy,prefix,shift)
		if prediction.ok:
			var seed: Dictionary = m.convoy.duplicate(true)
			seed.points = prediction.points
			var detour_world: WorldState = _convoy_route_projection(projected,m,seed,floor_id,Vector2(start)-shift)
			var detour: Dictionary = _convoy_vacated_goal_route(detour_world,m.actor_id,floor_id,start,goal,int(entry.ticks))
			if detour.get("ok",false): result = detour
	if result.get("ok",false):
		if not cost_only:
			var prefix: Array = []
			for point: Array in entry.points: prefix.append({"kind":"floor","floor_id":int(proxy.location.floor_id),"cell":point})
			prefix.append_array(result.path)
			for point: Array in exit.points: prefix.append({"kind":"floor","floor_id":floor_id,"cell":point})
			result.path = prefix
			for segment: Dictionary in result.path:
				if segment.kind=="floor": segment.cell = [float(segment.cell[0])-shift.x,float(segment.cell[1])-shift.y]
		result.walking_distance += float(entry.distance)+float(exit.distance)
		result.travel_ticks = HospitalTransit._add(int(result.travel_ticks),int(exit.ticks))
		if cost_only: result.erase("path")
	return result

func convoy_local_route(world: WorldState, movement: Dictionary, floor_id: int, target: Array) -> Dictionary:
	var proxy: Dictionary = ConvoyTrail.proxy(world,movement)
	var shift: Vector2 = Vector2.ONE*float(movement.convoy.shift)
	var start: Vector2 = ConvoyTrail.point(proxy.location.cell)
	var goal: Vector2 = ConvoyTrail.point(target)+shift
	var query: RouteClearance = structural_clearance(world,proxy,floor_id)
	var reason: String = query.sweep_reason(start,Vector2(Vector2i(start.round())))
	if not reason.is_empty(): return {"ok":false,"reason":reason}
	var result: Dictionary = _floor_route(world,proxy,floor_id,Vector2i(start.round()),Vector2i(goal.round()),[],{},false,{},true,false)
	if result.get("ok",false):
		if start!=start.round(): result.path.push_front({"kind":"floor","floor_id":floor_id,"cell":[roundf(start.x),roundf(start.y)]})
		for segment: Dictionary in result.path: segment.cell = [float(segment.cell[0])-shift.x,float(segment.cell[1])-shift.y]
	return result

# Fractional endpoints join the integer route through real orthogonal legs.
# Each short floor leg consumes its actual number of fixed movement steps.
func _convoy_grid_stub(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2, end: Vector2) -> Dictionary:
	var result: Dictionary = _grid_stub(world,actor,floor_id,start,end)
	if not result.ok: result.reason = "队列分数坐标没有安全的正交接入段"
	return result

func _grid_stub(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2, end: Vector2) -> Dictionary:
	var query: RouteClearance = structural_clearance(world,actor,floor_id)
	for corner: Vector2 in [Vector2(end.x,start.y),Vector2(start.x,end.y)]:
		var current: Vector2 = start
		var points: Array = []
		var distance: float = 0.0
		var ticks: int = 0
		var reason: String = ""
		for next: Vector2 in [corner,end]:
			if current==next: continue
			reason = query.sweep_reason(current,next)
			if not reason.is_empty(): break
			distance += current.distance_to(next)
			ticks += HospitalTransit.walking_ticks(space,actor,[],current.distance_to(next))
			points.append([next.x,next.y])
			current = next
		if reason.is_empty(): return {"ok":true,"points":points,"distance":distance,"ticks":ticks}
	return {"ok":false,"reason":"分数坐标没有安全的正交接入段"}

# Admission requires the entire tail to be aligned, not just the head at a
# coordinate. Walk from the outer approach point through one real straight
# tail-length prefix. Pure trail prediction rejects a folded approach before
# it becomes an accepted journey; the two side alternatives are ordinary
# geometric detours with no queue priority or teleportation rule.
func _convoy_portal_approach(world: WorldState, actor: Dictionary, floor_id: int, node: Dictionary, portal: Dictionary) -> Dictionary:
	var original: Dictionary = world.facts.moves[actor.id]
	var seed: Dictionary = node.get("convoy",original.convoy).duplicate(true)
	var shift: Vector2 = Vector2.ONE*float(seed.shift)
	var start: Vector2 = Vector2(node.cell)
	var entry: Vector2 = ConvoyTrail.point(portal.entry)+shift
	var approach: Vector2 = ConvoyTrail.point(portal.egress)+shift
	var inward: Vector2 = ConvoyTrail.point(portal.inward)
	if start.distance_to(entry)<0.001 and HospitalTransit._convoy_entry_aligned(seed,portal):
		return {"ok":true,"path":[],"walking_distance":0.0}
	var side: Vector2 = Vector2(-inward.y,inward.x)
	var radius: float = maxf(float(seed.spacing),float(seed.size)*2.0)
	var alternatives: Array = [null,approach+side*radius,approach-side*radius]
	for staging: Variant in alternatives:
		var trial: Dictionary = seed.duplicate(true)
		var path: Array = []
		var distance: float = 0.0
		var current: Vector2 = start
		var goals: Array = [approach] if staging==null else [staging,approach]
		var valid: bool = true
		for goal: Vector2 in goals:
			var projected: WorldState = _convoy_route_projection(world,original,trial,floor_id,current-shift)
			var proxy: Dictionary = ConvoyTrail.proxy(projected,projected.facts.moves[actor.id])
			if goal==approach: proxy._convoy_goal_direction = inward
			var leg: Dictionary = _floor_route(projected,proxy,floor_id,Vector2i(current),Vector2i(goal),[],{},true,{},true,false)
			var prediction: Dictionary = _convoy_predict_floor_path(trial,leg.path,shift) if leg.get("ok",false) else {"ok":false}
			if not prediction.ok:
				leg = _convoy_vacated_goal_route(projected,actor.id,floor_id,Vector2i(current),Vector2i(goal),0,inward if goal==approach else Vector2.ZERO)
				if leg.get("ok",false): prediction = _convoy_predict_floor_path(trial,leg.path,shift)
			if not leg.get("ok",false) or not prediction.ok: valid = false;break
			trial.points = prediction.points
			path.append_array(leg.path)
			distance += float(leg.walking_distance)
			current = goal
		if not valid: continue
		var projection: WorldState = _convoy_route_projection(world,original,trial,floor_id,current-shift)
		var proxy: Dictionary = ConvoyTrail.proxy(projection,projection.facts.moves[actor.id])
		var query: RouteClearance = structural_clearance(projection,proxy,floor_id)
		if not query.sweep_reason(approach,entry).is_empty(): continue
		var straight: Array = []
		while current.distance_to(entry)>0.00001:
			var next: Vector2 = current.move_toward(entry,1.0)
			straight.append({"kind":"floor","floor_id":floor_id,"cell":[next.x,next.y]})
			distance += current.distance_to(next)
			current = next
		var prediction: Dictionary = _convoy_predict_floor_path(trial,straight,shift)
		if not prediction.ok: continue
		trial.points = prediction.points
		if not HospitalTransit._convoy_entry_aligned(trial,portal): continue
		path.append_array(straight)
		return {"ok":true,"path":path,"walking_distance":distance}
	return {"ok":false,"status":"unreachable","reason":"入口没有可真实对齐完整队列的接近通路"}

func _convoy_route_projection(world: WorldState, movement: Dictionary, convoy: Dictionary, floor_id: int, head: Vector2) -> WorldState:
	var facts: Dictionary = world.facts.duplicate()
	facts.moves = world.facts.moves.duplicate()
	var m: Dictionary = movement.duplicate()
	m.convoy = convoy.duplicate(true)
	m.convoy.floor_id = floor_id
	facts.moves[m.actor_id] = m
	facts.actors = world.facts.actors.duplicate()
	var leader: Dictionary = world.facts.actors[m.actor_id].duplicate(true)
	leader.location = {"kind":"floor","floor_id":floor_id,"cell":[head.x,head.y],"height_m":0.0}
	facts.actors[m.actor_id] = leader
	return WorldState.new(facts)

func _convoy_predict_floor_path(convoy: Dictionary, path: Array, shift: Vector2) -> Dictionary:
	var trial: Dictionary = convoy.duplicate(true)
	for segment: Dictionary in path:
		var target: Vector2 = ConvoyTrail.point(segment.cell)-shift
		var current: Vector2 = ConvoyTrail.point(trial.points[-1])
		while current.distance_to(target)>0.00001:
			var next: Vector2 = current.move_toward(target,float(trial.size)*0.5)
			var proposal: Dictionary = ConvoyTrail.propose(trial,next)
			if not proposal.ok: return {"ok":false,"reason":proposal.reason}
			trial.points = proposal.points
			current = next
	return {"ok":true,"points":trial.points}

# The present tail is temporary, so it cannot make a valid future goal
# permanently unreachable. A bounded ordinary detour vacates that old region,
# then replans with the predicted trail, without relaxing any collision proof.
func _convoy_vacated_goal_route(world: WorldState, primary: String, floor_id: int, start: Vector2i, goal: Vector2i, initial_ticks: int, final_direction: Vector2 = Vector2.ZERO) -> Dictionary:
	var movement: Dictionary = world.facts.moves[primary]
	var seed: Dictionary = movement.convoy
	if movement.members.size()<2: return {"ok":false}
	var shift: Vector2 = Vector2.ONE*float(seed.shift)
	var forward: Vector2 = (ConvoyTrail.point(seed.points[-1])-ConvoyTrail.point(seed.points[-2])).normalized()
	var side: Vector2 = Vector2(-forward.y,forward.x)
	var distance: float = ceilf(ConvoyTrail.length(seed.points)+float(seed.size))
	for direction: Vector2 in [forward,side,-side]:
		var staging: Vector2i = start+Vector2i(direction*distance)
		var proxy: Dictionary = ConvoyTrail.proxy(world,movement)
		var first: Dictionary = _floor_route(world,proxy,floor_id,start,staging,[],{},true,{},true,false)
		if not first.get("ok",false): continue
		var prediction: Dictionary = _convoy_predict_floor_path(seed,first.path,shift)
		if not prediction.ok: continue
		var trial: Dictionary = seed.duplicate(true)
		trial.points = prediction.points
		var projected: WorldState = _convoy_route_projection(world,movement,trial,floor_id,Vector2(staging)-shift)
		proxy = ConvoyTrail.proxy(projected,projected.facts.moves[primary])
		if final_direction!=Vector2.ZERO: proxy._convoy_goal_direction = final_direction
		var second: Dictionary = _floor_route(projected,proxy,floor_id,staging,goal,[],{},true,{},true,false)
		if not second.get("ok",false): continue
		if not _convoy_predict_floor_path(trial,second.path,shift).ok: continue
		var path: Array = first.path.duplicate()
		path.append_array(second.path)
		var walked: float = float(first.walking_distance)+float(second.walking_distance)
		return {"ok":true,"status":"complete","reason":"","path":path,"walking_distance":walked,"travel_ticks":HospitalTransit._add(initial_ticks,HospitalTransit.walking_ticks(space,proxy,[],walked)),"quoted_tick":world.sim_tick}
	return {"ok":false}
