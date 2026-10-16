class_name NavigationCache
extends RefCounted

var _entries: Dictionary = {}
var _sources: Dictionary = {}
var _used: int = 0
var _charged: int = 0
var _source_version: int = 0

func invalidate(world: WorldState, floor_id: int) -> void:
	var key: String = str(world.get_instance_id())+":"+str(floor_id)
	if _sources.has(key): _sources[key].revision = -1

func floor_source(space: HospitalSpace, world: WorldState, floor_id: int) -> Dictionary:
	var key: String = str(world.get_instance_id())+":"+str(floor_id)
	var entry: Dictionary = _sources.get(key,{})
	if entry.is_empty() or entry.revision!=world.revision:
		var current: Dictionary = RouteClearance.capture_source(space,world,floor_id)
		if entry.is_empty() or entry.source!=current:
			_source_version += 1
			entry = {"source":current,"world":weakref(world),"floor_id":floor_id,"version":_source_version}
		entry.revision = world.revision
		_sources[key] = entry
	return entry.source

func floor_version(space: HospitalSpace, world: WorldState, floor_id: int) -> int:
	floor_source(space,world,floor_id)
	return int(_sources[str(world.get_instance_id())+":"+str(floor_id)].version)

func query_graphs(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, members: Array, offsets: Dictionary) -> Dictionary:
	var bases: Array[FloorNavigation] = []
	var shifts: Array[Vector2i] = []
	var ids: Array[String] = []
	if members.size()>1:
		for id: String in members:
			if id==actor.id:
				continue
			var offset: Array = offsets[id]
			if float(offset[0])!=floor(float(offset[0])) or float(offset[1])!=floor(float(offset[1])) or absf(float(offset[0]))>=96 or absf(float(offset[1]))>=96:
				shifts.clear()
				return {"graph":graph(space,world,floor_id,actor,members,offsets),"bases":bases,"shifts":shifts}
			ids.append(id)
			shifts.append(Vector2i(int(offset[0]),int(offset[1])))
	var primary: FloorNavigation = graph(space,world,floor_id,actor,[],{})
	for id: String in ids:
		bases.append(graph(space,world,floor_id,world.facts.actors[id],[],{}))
	return {"graph":primary,"bases":bases,"shifts":shifts}

func graph(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, members: Array, offsets: Dictionary) -> FloorNavigation:
	var key: String = str(floor_id)+":"+_envelope(space,world,actor,members,offsets)
	var source: Dictionary = floor_source(space,world,floor_id).duplicate()
	# Reservations belong to the current query. A cloned candidate with the
	# same geometry can borrow this graph; different geometry refreshes it.
	source.erase("occupancy")
	var entry: Dictionary = _entries.get(key,{})
	_used += 1
	if entry.is_empty() or entry.source!=source:
		var geometry: RouteClearance = RouteClearance.new(space,world,actor,floor_id,members,offsets,false,source)
		var floor_graph: FloorNavigation
		if entry.is_empty():
			floor_graph = FloorNavigation.new(geometry)
		else:
			floor_graph = entry.graph
			floor_graph.refresh(geometry)
			_charged -= int(entry.charge)
		# Capacity charge includes native points/adjacency and projection containers.
		# This is an eviction allowance, not a measured Release allocation count.
		var charge: int = floor_graph.get_point_count()*2048+var_to_bytes(source).size()*8+16384
		entry = {"graph":floor_graph,"source":source,"used":_used,"charge":charge,"floor_id":floor_id}
		_entries[key] = entry
		_charged += charge
	entry.used = _used
	var result: FloorNavigation = entry.graph
	_trim(int(space.content.balance.pathfinding.graph_cache_target_bytes))
	return result

func _trim(target: int) -> void:
	var keys: Array = _entries.keys()
	keys.sort_custom(func(a: String,b: String) -> bool:
		return int(_entries[a].used)<int(_entries[b].used) if _entries[a].used!=_entries[b].used else a<b)
	for key: String in keys:
		var entry: Dictionary = _entries[key]
		if _charged<=target:
			continue
		_charged -= int(entry.charge)
		_entries.erase(key)
	var retained: Dictionary = {}
	for entry: Dictionary in _entries.values():
		retained[entry.floor_id] = true
	for key: String in _sources.keys():
		if _sources[key].world.get_ref()==null or not retained.has(_sources[key].floor_id):
			_sources.erase(key)

func clearance(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, members: Array = [], offsets: Dictionary = {}) -> RouteClearance:
	graph(space,world,floor_id,actor,[],{})
	var key: String = str(floor_id)+":"+_envelope(space,world,actor,[],{})
	if not _entries.has(key): return RouteClearance.new(space,world,actor,floor_id,members,offsets,true,floor_source(space,world,floor_id))
	var entry: Dictionary = _entries[key]
	if not entry.has("queries"): entry.queries = {}
	var stamp: Array = [world.get_instance_id(),floor_version(space,world,floor_id)]
	if not members.is_empty():
		# Identical bodies do not grant another group the same reservation access.
		stamp.append(members.duplicate())
		stamp.append(_envelope(space,world,actor,members,offsets))
	var record: Dictionary = entry.queries.get(actor.id,{})
	if record.is_empty() or record.stamp!=stamp:
		var old_charge: int = int(record.get("charge",0))
		entry.charge -= old_charge
		_charged -= old_charge
		var source: Dictionary = floor_source(space,world,floor_id)
		record = {"stamp":stamp,"query":RouteClearance.new(space,world,actor,floor_id,members,offsets,true,source),"charge":var_to_bytes(source).size()*8*(members.size()+1)+16384}
		entry.queries[actor.id] = record
		entry.charge += int(record.charge)
		_charged += int(record.charge)
	_trim(int(space.content.balance.pathfinding.graph_cache_target_bytes))
	return record.query

func travel_distance(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, start: Vector2i, goal: Vector2i, witness: bool = false) -> Dictionary:
	var current: FloorNavigation = graph(space,world,floor_id,actor,[],{})
	var key: String = str(floor_id)+":"+_envelope(space,world,actor,[],{})
	if not _entries.has(key): return {"ready":false}
	var entry: Dictionary = _entries[key]
	if not entry.has("estimates"): entry.estimates = {}
	var destination: String = str(actor.id)+":"+str(goal)
	var stamp: Array = [world.get_instance_id(),floor_version(space,world,floor_id)]
	var record: Dictionary = entry.estimates.get(destination,{})
	if record.is_empty() or record.stamp!=stamp:
		var old_charge: int = int(record.get("charge",0))
		entry.charge -= old_charge
		_charged -= old_charge
		record = {"stamp":stamp,"hits":0,"ready":false,"charge":512+destination.length()*8}
		entry.estimates[destination] = record
		entry.charge += int(record.charge)
		_charged += int(record.charge)
	record.hits += 1
	# One-off quotes retain A*. Repeated destinations amortize a reverse field;
	# only integer distance is reused, never a route or permission to reserve.
	if not record.ready and int(record.hits)>=12:
		var query: RouteClearance = RouteClearance.new(space,world,actor,floor_id,[],{},true,current.geometry.source)
		record.reason = query.reason(goal) if FloorNavigation._inside(goal) else "目标超出96×96真实楼面"
		var field: Dictionary = _distance_field(current,query,goal) if str(record.reason).is_empty() else {"distances":PackedInt32Array(),"successors":PackedInt32Array()}
		record.distances = field.distances
		record.successors = field.successors
		record.ready = true
		var charge: int = ((record.distances as PackedInt32Array).size()+(record.successors as PackedInt32Array).size())*16
		record.charge += charge
		entry.charge += charge
		_charged += charge
	_trim(int(space.content.balance.pathfinding.graph_cache_target_bytes))
	if not record.ready: return {"ready":false}
	if not FloorNavigation._inside(start) or not FloorNavigation._inside(goal):
		return {"ready":true,"ok":false,"reason":"目标超出96×96真实楼面"}
	if not str(record.reason).is_empty(): return {"ready":true,"ok":false,"reason":record.reason}
	var distance: int = record.distances[FloorNavigation._id(start)]
	var result: Dictionary = {"ready":true,"ok":distance>=0,"distance":distance,"reason":"" if distance>=0 else "真实身体无法到达目标"}
	if witness and result.ok:
		var path: Array = []
		var id: int = FloorNavigation._id(start)
		while id!=FloorNavigation._id(goal):
			id = record.successors[id]
			if id<0: return {"ready":false}
			var cell: Vector2i = FloorNavigation._cell(id)
			path.append({"kind":"floor","floor_id":floor_id,"cell":[cell.x,cell.y]})
		result.path = path
	return result

func _distance_field(graph: FloorNavigation, query: RouteClearance, goal: Vector2i) -> Dictionary:
	var distances: PackedInt32Array = PackedInt32Array()
	distances.resize(FloorNavigation.LIMIT)
	distances.fill(-1)
	var successors: PackedInt32Array = distances.duplicate()
	var result: Dictionary = {"distances":distances,"successors":successors}
	var goal_id: int = FloorNavigation._id(goal)
	if not graph.has_point(goal_id) or graph.is_point_disabled(goal_id): return result
	var queue: Array[int] = [goal_id]
	distances[goal_id] = 0
	var cursor: int = 0
	while cursor<queue.size():
		var current: int = queue[cursor]
		cursor += 1
		var cell: Vector2i = FloorNavigation._cell(current)
		# The existing search permits leaving a reserved start, but never
		# entering a reserved destination. Reverse expansion keeps that rule.
		if not query.reservation_reason(cell).is_empty(): continue
		for offset: Vector2i in FloorNavigation.NEIGHBOURS:
			var previous: Vector2i = cell+offset
			if not FloorNavigation._inside(previous): continue
			var id: int = FloorNavigation._id(previous)
			if distances[id]>=0 or not graph.has_point(id) or graph.is_point_disabled(id) or not graph.are_points_connected(id,current,false): continue
			distances[id] = distances[current]+1
			successors[id] = current
			queue.append(id)
	return result

func _envelope(space: HospitalSpace, world: WorldState, actor: Dictionary, members: Array, offsets: Dictionary) -> String:
	var shapes: Array = [[space.body(actor),actor.get("posture","standing"),[0,0]]]
	for id: String in members:
		if id!=actor.id:
			shapes.append([space.body(world.facts.actors[id]),world.facts.actors[id].get("posture","standing"),offsets[id]])
	return JSON.stringify(shapes,"",true,true)
