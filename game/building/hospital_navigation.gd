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
	var goal: Vector2i = Vector2i(int(target[0]),int(target[1]))
	var result: Dictionary = _point_route(world,actor,int(subject.floor_id),start,floor_id,goal,members,offsets,int(subject.initial_ticks),distance_only)
	if result.ok and stub>0.0:
		if not distance_only: result.path.push_front({"kind":"floor","floor_id":int(actor.location.floor_id),"cell":[start.x,start.y]})
		result.walking_distance += stub
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

func destination_reason(world: WorldState, actor: Dictionary, floor_id: int, target: Vector2i, members: Array = [], offsets: Dictionary = {}) -> String:
	return structural_clearance(world,actor,floor_id,members,offsets).reason(target)

func structural_clearance(world: WorldState, actor: Dictionary, floor_id: int, members: Array = [], offsets: Dictionary = {}) -> RouteClearance:
	if members.size()==1 and members[0]==actor.id: members = []
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
	var extra_stops: Dictionary = {}
	for floor_id: int in {source_floor:true,target_floor:true}:
		if topology.candidates.has(floor_id): continue
		var extra: Dictionary = _topology_floor_nodes(world,topology,floor_id)
		if extra.ids.is_empty(): continue
		if is_same(node_ids,topology.node_ids): node_ids = node_ids.duplicate()
		node_ids.append_array(extra.ids)
		nodes.merge(extra.nodes)
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
func ready_waiting_cost_field(world: WorldState, actor_id: String, floor_id: int, bounds: Dictionary) -> Dictionary:
	if not space.in_dynamic_route_query(world) or world.facts.connectors.size()>1: return {}
	var owner: Dictionary = space.read_view(world,"point_journeys",func()->Dictionary:return {})
	var subject: Dictionary = owner.get("subjects",{}).get(actor_id,{})
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
	var field: Dictionary = space._navigation.ready_structural_field(space,world,floor_id,actor,root)
	if not field.get("ready",false): return {}
	_observe_floor(world,actor_id,floor_id)
	space.query_counts["public_entry_field_preparations"] = int(space.query_counts.get("public_entry_field_preparations",0))+1
	return {"ready":true,"distances":field.distances,"prefix_ticks":prefix,"speed":float(space.content.balance.movement_speeds[str(space.clearance(actor))])}

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
	# A sole lift has one anchor and linear integer time per floor. The start
	# already offered every legal stop; another boarding there cannot improve
	# any label, including equal-cost ties first relaxed by that start.
	if context.get("direct_lift_stops",false) and id!="start":
		context.edges[id] = facts
		return outgoing
	if not context.get("single_source",false) and floor_id==target_floor:
		var finish: Dictionary = context.direct if id=="start" and int(context.source_floor)==target_floor else _floor_route(world,actor,target_floor,node.cell,context.goal,members,offsets,true,{},true,distance_only)
		if finish.ok:
			var ticks: int = HospitalTransit.walking_ticks(space,actor,members,float(finish.walking_distance))
			if ticks>=0:
				outgoing.append({"to":"goal","ticks":ticks})
				facts.goal = {"path":[] if distance_only else finish.path,"walking_distance":float(finish.walking_distance)}
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
		var before: Dictionary = _floor_route(world,actor,floor_id,node.cell,anchor,members,offsets,true,{},true,distance_only)
		if not before.ok: continue
		var definition: Dictionary = space.content.definition("vertical_connectors",connection.definition_id)
		var walking: int = HospitalTransit.walking_ticks(space,actor,members,float(before.walking_distance))
		var boarding: int = HospitalTransit._boarding(definition)
		var alighting: int = HospitalTransit._alighting(definition)
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
	if cacheable:
		routes[key] = result.duplicate(true)
	return result

func _route_envelope(world: WorldState, actor: Dictionary, members: Array, offsets: Dictionary) -> Array:
	var result: Array = [[space.body(actor),actor.get("posture","standing"),float(actor.get("facing",0.0)),[0,0]]]
	for member_id: String in members:
		if member_id==actor.id: continue
		var member: Dictionary = world.facts.actors[member_id]
		result.append([space.body(member),member.get("posture","standing"),float(member.get("facing",0.0)),offsets[member_id]])
	return result

