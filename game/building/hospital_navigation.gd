class_name HospitalNavigation
extends RefCounted

var _space: WeakRef
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
	var start: Vector2i = Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1]))
	var goal: Vector2i = Vector2i(int(target[0]),int(target[1]))
	var actual: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	var stub: float = actual.distance_to(Vector2(start))
	if stub>0.0:
		var query: RouteClearance = structural_clearance(world,actor,int(actor.location.floor_id),members,offsets)
		var reason: String = query.sweep_reason(actual,Vector2(start))
		if not reason.is_empty(): return {"ok":false,"status":"unreachable","reason":reason}
	var journeys: Dictionary = space.read_view(world,"point_journeys",func()->Dictionary:return {})
	var key: String = JSON.stringify([actor.id,actor.location.floor_id,actor.location.cell,floor_id,target,_route_envelope(world,actor,members,offsets),distance_only],"",true,true)
	if journeys.has(key):
		space.query_counts.journey_hits += 1
		return journeys[key].duplicate(true)
	var result: Dictionary = _point_route(world,actor,int(actor.location.floor_id),start,floor_id,goal,members,offsets,HospitalTransit.walking_ticks(space,actor,members,stub),distance_only)
	if result.ok and stub>0.0:
		if not distance_only: result.path.push_front({"kind":"floor","floor_id":int(actor.location.floor_id),"cell":[start.x,start.y]})
		result.walking_distance += stub
	journeys[key] = result.duplicate(true)
	return result

func travel_quote(world: WorldState, actor_id: String, floor_id: int, target: Array) -> Dictionary:
	return _route_result(world,actor_id,floor_id,target,[],{},true,true)

func destination_reason(world: WorldState, actor: Dictionary, floor_id: int, target: Vector2i, members: Array = [], offsets: Dictionary = {}) -> String:
	return structural_clearance(world,actor,floor_id,members,offsets).reason(target)

func structural_clearance(world: WorldState, actor: Dictionary, floor_id: int, members: Array = [], offsets: Dictionary = {}) -> RouteClearance:
	var source: Dictionary = space._navigation.floor_source(space,world,floor_id)
	var query: RouteClearance = space._navigation.cached_static_geometry(space,world,floor_id,actor) if members.is_empty() else null
	if query==null: query = RouteClearance.new(space,world,actor,floor_id,members,offsets,false,source)
	return query

func _point_route(world: WorldState, actor: Dictionary, source_floor: int, start: Vector2i, target_floor: int, goal: Vector2i, members: Array, offsets: Dictionary, initial_ticks: int, distance_only: bool) -> Dictionary:
	var direct: Dictionary = {"ok":false,"status":"unreachable","reason":"没有合法通路"}
	if source_floor==target_floor:
		direct = _floor_route(world,actor,source_floor,start,goal,members,offsets,true,{},true)
		if direct.ok and (world.facts.connectors.is_empty() or int(direct.walking_distance)==absi(goal.x-start.x)+absi(goal.y-start.y)):
			direct.travel_ticks = HospitalTransit._add(initial_ticks,HospitalTransit.walking_ticks(space,actor,members,float(direct.walking_distance)))
			if int(direct.travel_ticks)<0: return {"ok":false,"status":"time_overflow","reason":"基准通行时间超出整数范围"}
			direct.quoted_tick = world.sim_tick
			if distance_only: direct.erase("path")
			return direct
	space.query_counts.transport_searches += 1
	var nodes: Dictionary = {"start":{"floor_id":source_floor,"cell":start},"goal":{"floor_id":target_floor,"cell":goal}}
	var costs: Dictionary = {"start":initial_ticks}
	var previous: Dictionary = {}
	var heap: Array = []
	HospitalTransit._push(heap,{"id":"start","tick":initial_ticks})
	var compatible: Dictionary = {}
	var connections: Dictionary = {}
	var stops: Dictionary = {}
	var candidates: Dictionary = HospitalTransit._routing_candidates(world,source_floor,target_floor)
	while not heap.is_empty():
		var item: Dictionary = HospitalTransit._pop(heap)
		var id: String = item.id
		if int(item.tick)!=int(costs[id]): continue
		if id=="goal":
			var chunks: Array = []
			var distance: float = 0.0
			while id!="start":
				if not distance_only: chunks.push_front(previous[id].path)
				distance += float(previous[id].walking_distance)
				id = previous[id].from
			var result: Dictionary = {"ok":true,"status":"complete","reason":"","walking_distance":distance,"travel_ticks":int(item.tick),"quoted_tick":world.sim_tick}
			if not distance_only:
				var path: Array = []
				for chunk: Array in chunks: path.append_array(chunk)
				result.path = path
			return result
		var node: Dictionary = nodes[id]
		var floor_id: int = int(node.floor_id)
		if floor_id==target_floor:
			var finish: Dictionary = direct if id=="start" and source_floor==target_floor else _floor_route(world,actor,target_floor,node.cell,goal,members,offsets,true,{},true)
			if finish.ok:
				var cost: int = HospitalTransit._add(int(item.tick),HospitalTransit.walking_ticks(space,actor,members,float(finish.walking_distance)))
				if cost>=0: HospitalTransit._relax(heap,costs,previous,id,"goal",cost,[] if distance_only else finish.path,float(finish.walking_distance))
		if not connections.has(floor_id):
			connections[floor_id] = []
			for connector_id: String in world.ids("connectors"):
				space.query_counts.candidate_connections += 1
				var connection: Dictionary = world.facts.connectors[connector_id]
				if not HospitalTransit.has_stop(connection,floor_id): continue
				if not compatible.has(connector_id): compatible[connector_id] = HospitalTransit.fits(space,world,connection,actor.id,members).ok
				if compatible[connector_id]: connections[floor_id].append(connector_id)
		for connector_id: String in connections[floor_id]:
			var connection: Dictionary = world.facts.connectors[connector_id]
			var anchor: Vector2i = Vector2i(int(connection.anchor[0]),int(connection.anchor[1]))
			var before: Dictionary = _floor_route(world,actor,floor_id,node.cell,anchor,members,offsets,true,{},true)
			if not before.ok: continue
			if not stops.has(connector_id): stops[connector_id] = HospitalTransit.routing_stops(connection,world,source_floor,target_floor,candidates)
			var definition: Dictionary = space.content.definition("vertical_connectors",connection.definition_id)
			for destination: int in stops[connector_id]:
				if destination==floor_id or definition.kind=="stairs" and absi(destination-floor_id)!=1: continue
				if HospitalTransit._lowering(connection) and destination>=floor_id: continue
				var travel: int = HospitalTransit._travel_ticks(space,connection,floor_id,destination)
				var cost: int = HospitalTransit._add(int(item.tick),HospitalTransit.walking_ticks(space,actor,members,float(before.walking_distance)))
				cost = HospitalTransit._add(cost,HospitalTransit._add(HospitalTransit._boarding(definition),HospitalTransit._add(travel,HospitalTransit._alighting(definition))))
				if cost<0: continue
				var next: String = connector_id+":"+str(destination)
				nodes[next] = {"floor_id":destination,"cell":anchor}
				var path: Array = [] if distance_only else before.path.duplicate()
				if not distance_only: path.append({"kind":"connector","connector_id":connector_id,"from":floor_id,"to":destination})
				HospitalTransit._relax(heap,costs,previous,id,next,cost,path,float(before.walking_distance))
	if direct.ok: return {"ok":false,"status":"time_overflow","reason":"基准通行时间超出整数范围"}
	return direct if source_floor==target_floor else {"ok":false,"status":"unreachable","reason":"没有身体、停层和运行方向均合法的竖向通路"}

func _floor_route(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2i, goal: Vector2i, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false, navigation: Dictionary = {}, structural_only: bool = false) -> Dictionary:
	var routes: Dictionary = {}
	var key: String = ""
	if navigation.is_empty() and not space._route_queries.is_empty() and space._route_queries.back().world==world and (ignore_people or space._route_queries.back().get("dynamic",false)):
		routes = space._route_queries.back().routes
		var identity: Variant = actor.id
		if not space._route_queries.back().reference.is_empty() and members.is_empty() and offsets.is_empty():
			identity = [space.body(actor),[] if structural_only else RouteClearance.reservation_exemptions(world,actor.id,floor_id)]
		key = JSON.stringify([identity,floor_id,start.x,start.y,goal.x,goal.y,members,offsets,ignore_people,structural_only,_route_envelope(world,actor,members,offsets)])
		if routes.has(key):
			space.query_counts.floor_route_hits += 1
			return routes[key].duplicate(true)
	space.query_counts.floor_route_builds += 1
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
	if not space._route_queries.is_empty() and space._route_queries.back().world==world and members.is_empty() and offsets.is_empty() and not navigation.has("query") and not navigation.get("overlay",false) and navigation.bases.is_empty() and navigation.shifts.is_empty():
		result = space._navigation.cached_floor_path(space,world,floor_id,actor,graph,query,start,goal)
	else:
		result = graph.find_path(start,goal,query,Callable(),false,navigation.bases,navigation.shifts,bool(navigation.get("overlay",false)))
	if result.ok and people.is_valid():
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
					alternative = graph.find_path(start,goal,query,people,false,navigation.bases,navigation.shifts,bool(navigation.get("overlay",false)))
				if alternative.get("ok",false):
					result = alternative
				else:
					result.status = "contention"
	if result.ok:
		var path: Array = []
		for cell: Array in result.cells:
			path.append({"kind":"floor","floor_id":floor_id,"cell":cell})
		result.path = path
		result.erase("cells")
	if not key.is_empty():
		routes[key] = result.duplicate(true)
	return result

func _route_envelope(world: WorldState, actor: Dictionary, members: Array, offsets: Dictionary) -> Array:
	var result: Array = [[space.body(actor),actor.get("posture","standing"),float(actor.get("facing",0.0)),[0,0]]]
	for member_id: String in members:
		if member_id==actor.id: continue
		var member: Dictionary = world.facts.actors[member_id]
		result.append([space.body(member),member.get("posture","standing"),float(member.get("facing",0.0)),offsets[member_id]])
	return result

