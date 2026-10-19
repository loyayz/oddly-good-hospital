class_name NavigationCache
extends RefCounted

const FIELD_STEPS: Array[int] = [-FloorNavigation.SIDE,-1,1,FloorNavigation.SIDE]

var _entries: Dictionary = {}
var _sources: Dictionary = {}
var _used: int = 0
var _charged: int = 0
var _query_charged: int = 0
var _source_version: int = 0

func invalidate(world: WorldState, floor_id: int) -> void:
	var key: String = str(world.get_instance_id())+":"+str(floor_id)
	if _sources.has(key): _sources[key].revision = -1

# A synchronous projection changes only actors and the listed adaptations.
# Built floors, rooms, facilities and connectors retain their original owners.
# Copy the exact footprint delta and current permission records; never inherit
# actor indices, transport prefixes, exit witnesses or route results.
func inherit_projection(space: HospitalSpace, world: WorldState, projected: WorldState, facility_ids: Array = []) -> void:
	_prune_sources()
	for original: Dictionary in _sources.values():
		if original.world.get_ref()!=world or original.revision!=world.geometry_revision: continue
		var floor_id: int = int(original.floor_id)
		var current: Dictionary = original.source.duplicate()
		for id: String in facility_ids:
			if not current.facilities.has(id): continue
			var facility: Dictionary = projected.facts.facilities[id]
			var footprint: Array = projected.facts.adaptations.get(id,{}).get("footprint",facility.footprint)
			if current.facilities[id].footprint==footprint: continue
			if is_same(current.facilities,original.source.facilities): current.facilities = current.facilities.duplicate()
			current.facilities[id] = {"cell":facility.cell.duplicate(),"footprint":footprint.duplicate()}
		current.occupancy = RouteClearance.capture_occupancy(projected,floor_id)
		var identical: bool = current==original.source
		if not identical: _source_version += 1
		var entry: Dictionary = {"source":original.source if identical else current,"world":weakref(projected),"floor_id":floor_id,"revision":projected.geometry_revision,"version":original.version if identical else _source_version,"graphs":original.graphs if identical else {}}
		if original.has("facility_index") and current.facilities==original.source.facilities: entry.facility_index = original.facility_index
		_sources[str(projected.get_instance_id())+":"+str(floor_id)] = entry

func floor_source(space: HospitalSpace, world: WorldState, floor_id: int) -> Dictionary:
	var key: String = str(world.get_instance_id())+":"+str(floor_id)
	var entry: Dictionary = _sources.get(key,{})
	if entry.is_empty() or entry.revision!=world.geometry_revision:
		if entry.is_empty(): _prune_sources(floor_id)
		var current: Dictionary = RouteClearance.capture_source(space,world,floor_id)
		if entry.is_empty() or entry.source!=current:
			var shared: Dictionary = {}
			for retained: Dictionary in _sources.values():
				if int(retained.floor_id)==floor_id and retained.source==current:
					shared = retained
					break
			if shared.is_empty():
				_source_version += 1
				shared = {"source":current,"version":_source_version,"graphs":{}}
			var previous: Dictionary = entry
			entry = {"source":shared.source,"world":weakref(world),"floor_id":floor_id,"version":shared.version,"graphs":shared.graphs}
			if previous.has("facility_index") and previous.source.facilities==current.facilities: entry.facility_index = previous.facility_index
		entry.revision = world.geometry_revision
		_sources[key] = entry
	return entry.source

func facility_index(space: HospitalSpace, world: WorldState, floor_id: int) -> BodyIndex:
	var source: Dictionary = floor_source(space,world,floor_id)
	var entry: Dictionary = _sources[str(world.get_instance_id())+":"+str(floor_id)]
	if not entry.has("facility_index"):
		var index: BodyIndex = BodyIndex.new()
		for id: String in source.facilities:
			var facility: Dictionary = source.facilities[id]
			index.update(id,floor_id,Rect2(float(facility.cell[0]),float(facility.cell[1]),float(facility.footprint[0]),float(facility.footprint[1])))
		entry.facility_index = index
	return entry.facility_index

func floor_version(space: HospitalSpace, world: WorldState, floor_id: int) -> int:
	floor_source(space,world,floor_id)
	return int(_sources[str(world.get_instance_id())+":"+str(floor_id)].version)

# A point check can borrow already-built static geometry without paying to
# build an A* graph. Its reservation query is always constructed afresh.
func cached_static_geometry(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary) -> RouteClearance:
	var current: Dictionary = floor_source(space,world,floor_id)
	var key: String = str(floor_id)+":"+_envelope(space,world,actor,[],{},current)
	var entry: Dictionary = _entries.get(key,{})
	if entry.is_empty(): return null
	var source_record: Dictionary = _sources[str(world.get_instance_id())+":"+str(floor_id)]
	if int(source_record.graphs.get(key,0))!=entry.graph.geometry.get_instance_id():
		var source: Dictionary = current.duplicate()
		source.erase("occupancy")
		if entry.source!=source: return null
		source_record.graphs[key] = entry.graph.geometry.get_instance_id()
	_used += 1
	entry.used = _used
	return entry.graph.geometry

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
	var current: Dictionary = floor_source(space,world,floor_id)
	var key: String = str(floor_id)+":"+_envelope(space,world,actor,members,offsets,current)
	var source_record: Dictionary = _sources[str(world.get_instance_id())+":"+str(floor_id)]
	var entry: Dictionary = _entries.get(key,{})
	_used += 1
	if entry.is_empty() or int(source_record.graphs.get(key,0))!=entry.graph.geometry.get_instance_id():
		# Each immutable source remembers the graph geometries it has compared.
		# Query-only reservations may alternate worlds without comparing again.
		var source: Dictionary = current.duplicate()
		source.erase("occupancy")
		if entry.is_empty() or entry.source!=source:
			entry = _refresh_graph(space,world,floor_id,actor,members,offsets,source,entry)
			_entries[key] = entry
		source_record.graphs[key] = entry.graph.geometry.get_instance_id()
	entry.used = _used
	var result: FloorNavigation = entry.graph
	_trim(int(space.content.balance.pathfinding.graph_cache_target_bytes))
	return result

func _refresh_graph(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, members: Array, offsets: Dictionary, source: Dictionary, entry: Dictionary) -> Dictionary:
	var geometry: RouteClearance = RouteClearance.new(space,world,actor,floor_id,members,offsets,false,source)
	var floor_graph: FloorNavigation
	if entry.is_empty():
		floor_graph = FloorNavigation.new(geometry)
	else:
		floor_graph = entry.graph
		floor_graph.refresh(geometry)
		_charged -= int(entry.charge)
		_query_charged -= int(entry.get("query_charge",0))
	# Capacity charge includes native points/adjacency and projection containers.
	# This is an eviction allowance, not a measured Release allocation count.
	var charge: int = floor_graph.get_point_count()*1024+var_to_bytes(source).size()*8+16384
	entry = {"graph":floor_graph,"source":source,"used":_used,"charge":charge,"floor_id":floor_id}
	_charged += charge
	return entry

func _trim(target: int) -> void:
	if _charged+_query_charged<=target and _query_charged<=target/4: return
	var keys: Array = _entries.keys()
	keys.sort_custom(func(a: String,b: String) -> bool:
		return int(_entries[a].used)<int(_entries[b].used) if _entries[a].used!=_entries[b].used else a<b)
	for key: String in keys:
		var entry: Dictionary = _entries[key]
		if _query_charged>target/4:
			_query_charged -= int(entry.get("query_charge",0))
			entry.query_charge = 0
			entry.erase("queries")
			entry.erase("estimates")
			entry.erase("structural_paths")
	for key: String in keys:
		var entry: Dictionary = _entries[key]
		if _charged+_query_charged<=target: break
		_charged -= int(entry.charge)
		_query_charged -= int(entry.get("query_charge",0))
		_entries.erase(key)
	_prune_sources()

func _prune_sources(current_floor: int = 0) -> void:
	var retained: Dictionary = {current_floor:true}
	for entry: Dictionary in _entries.values():
		retained[entry.floor_id] = true
	for key: String in _sources.keys():
		if _sources[key].world.get_ref()==null or not retained.has(_sources[key].floor_id):
			_sources.erase(key)

func clearance(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, members: Array = [], offsets: Dictionary = {}) -> RouteClearance:
	var current: FloorNavigation = graph(space,world,floor_id,actor,[],{})
	var key: String = str(floor_id)+":"+_envelope(space,world,actor,[],{},floor_source(space,world,floor_id))
	if not _entries.has(key): return RouteClearance.new(space,world,actor,floor_id,members,offsets,true,floor_source(space,world,floor_id),current.geometry)
	var entry: Dictionary = _entries[key]
	if not entry.has("queries"): entry.queries = {}
	# Query lifetime follows current actors, never the history of actor IDs.
	if entry.get("query_boundary",[])!=[world.get_instance_id(),world.revision]:
		for id: String in entry.queries.keys():
			if not world.facts.actors.has(id) or world.facts.actors[id].location.kind=="outside":
				_query_charged -= int(entry.queries[id].charge)
				entry.query_charge = int(entry.get("query_charge",0))-int(entry.queries[id].charge)
				entry.queries.erase(id)
		entry.query_boundary = [world.get_instance_id(),world.revision]
	var stamp: Array = _reservation_stamp(space,current,world,floor_id,actor.id) if members.is_empty() else [floor_version(space,world,floor_id)]
	if not members.is_empty():
		# Identical bodies do not grant another group the same reservation access.
		stamp.append(members.duplicate())
		stamp.append(_envelope(space,world,actor,members,offsets,floor_source(space,world,floor_id)))
	var record: Dictionary = entry.queries.get(actor.id,{})
	if record.is_empty() or record.stamp!=stamp:
		var old_charge: int = int(record.get("charge",0))
		entry.query_charge = int(entry.get("query_charge",0))-old_charge
		_query_charged -= old_charge
		var source: Dictionary = floor_source(space,world,floor_id)
		# Static geometry is shared with the graph, not copied per identity.
		var charge: int = (source.occupancy.size()*256+16384)*(members.size()+1)+var_to_bytes(stamp).size()*8
		record = {"stamp":stamp.duplicate(true),"query":RouteClearance.new(space,world,actor,floor_id,members,offsets,true,source,current.geometry),"charge":charge}
		entry.queries[actor.id] = record
		entry.query_charge += int(record.charge)
		_query_charged += int(record.charge)
	_trim(int(space.content.balance.pathfinding.graph_cache_target_bytes))
	return record.query

# Complete inputs consumed by a single body's reservation checks. Actor/staff
# names that leave this ordered forbidden view identical do not change it.
# The caller compares live references; retained records own a deep signature.
func _reservation_stamp(space: HospitalSpace, graph: FloorNavigation, world: WorldState, floor_id: int, actor_id: String) -> Array:
	if space._route_queries.is_empty() or space._route_queries.back().world!=world:
		return _build_reservation_stamp(graph,world,floor_id,actor_id)
	var views: Dictionary = space.read_view(world,"reservation_stamps:"+str(graph.geometry.get_instance_id()),func()->Dictionary: return {})
	if not views.has(actor_id): views[actor_id] = _build_reservation_stamp(graph,world,floor_id,actor_id)
	return views[actor_id]

func _build_reservation_stamp(graph: FloorNavigation, world: WorldState, floor_id: int, actor_id: String) -> Array:
	var forbidden: Array = []
	for reservation: Dictionary in world.facts.adaptations.values():
		if reservation.kind=="facility" and int(reservation.floor_id)==floor_id and not RouteClearance.reservation_allows(reservation,actor_id):
			forbidden.append([reservation.facility_id,reservation.regions])
	return [graph.geometry.get_instance_id(),forbidden]

# Cache only the pure single-body A* result of this exact clearance query.
# Dynamic bodies, group overlays and complete transit are checked by Space.
func cached_floor_path(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, graph: FloorNavigation, query: RouteClearance, start: Vector2i, goal: Vector2i) -> Dictionary:
	var key: String = str(floor_id)+":"+_envelope(space,world,actor,[],{},floor_source(space,world,floor_id))
	var entry: Dictionary = _entries.get(key,{})
	var record: Dictionary = entry.get("queries",{}).get(actor.id,{})
	if not entry.is_empty() and entry.graph==graph and query==graph.geometry:
		if not entry.has("structural_paths"): entry.structural_paths = {"charge":0}
		record = entry.structural_paths
	# clearance() can evict its own entry; externally supplied graphs/queries
	# also remain valid computations but cannot use this record's allowance.
	if entry.is_empty() or entry.graph!=graph or record.is_empty() or (query!=graph.geometry and record.query!=query):
		space.query_counts.static_path_builds += 1
		return graph.find_path(start,goal,query)
	if not record.has("paths"): record.paths = {}
	var endpoints: Vector4i = Vector4i(start.x,start.y,goal.x,goal.y)
	if record.paths.has(endpoints):
		space.query_counts.static_path_hits += 1
		var saved: Dictionary = record.paths[endpoints]
		var result: Dictionary = saved.value.duplicate()
		if saved.has("cells"):
			result.cells = []
			for id: int in saved.cells:
				var cell: Vector2i = FloorNavigation._cell(id)
				result.cells.append([cell.x,cell.y])
		return result
	space.query_counts.static_path_builds += 1
	var result: Dictionary = graph.find_path(start,goal,query)
	var saved: Dictionary = {"value":result.duplicate()}
	var charge: int = 512+var_to_bytes(result).size()*8
	if result.has("cells"):
		var cells: PackedInt32Array = PackedInt32Array()
		for cell: Array in result.cells: cells.append(FloorNavigation._id(Vector2i(cell[0],cell[1])))
		saved.value.erase("cells")
		saved.cells = cells
		charge += cells.size()*16
	record.paths[endpoints] = saved
	record.charge += charge
	entry.query_charge = int(entry.get("query_charge",0))+charge
	_query_charged += charge
	_trim(int(space.content.balance.pathfinding.graph_cache_target_bytes))
	return result

func travel_distance(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, start: Vector2i, goal: Vector2i, witness: bool = false) -> Dictionary:
	return _travel_distance(space,world,floor_id,actor,start,goal,witness,false)

# Region quotes ask for many goals from the same start or connector landing.
# Share exact distances only; actual movement still obtains its original path.
func forward_distance(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, start: Vector2i, goal: Vector2i) -> Dictionary:
	return _travel_distance(space,world,floor_id,actor,start,goal,false,true)

func _travel_distance(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, start: Vector2i, goal: Vector2i, witness: bool, forward: bool) -> Dictionary:
	var current: FloorNavigation = graph(space,world,floor_id,actor,[],{})
	var key: String = str(floor_id)+":"+_envelope(space,world,actor,[],{},floor_source(space,world,floor_id))
	if not _entries.has(key): return {"ready":false}
	var entry: Dictionary = _entries[key]
	if not entry.has("estimates"): entry.estimates = {}
	# A distance field depends on the body envelope and forbidden reservations,
	# not the traveller's identity when it grants no different exemption.
	var exemptions: Array = []
	for reservation: Array in floor_source(space,world,floor_id).occupancy:
		if actor.id==reservation[1] or actor.id in reservation[2]: exemptions.append(reservation[0])
	var destination: String = JSON.stringify(["from",start.x,start.y,exemptions]) if forward else JSON.stringify([goal.x,goal.y,exemptions])
	var stamp: Array = _reservation_stamp(space,current,world,floor_id,actor.id)
	var record: Dictionary = entry.estimates.get(destination,{})
	if record.is_empty() or record.stamp!=stamp:
		var old_charge: int = int(record.get("charge",0))
		entry.query_charge = int(entry.get("query_charge",0))-old_charge
		_query_charged -= old_charge
		record = {"stamp":stamp.duplicate(true),"hits":0,"ready":false,"charge":512+destination.length()*8+var_to_bytes(stamp).size()*8}
		entry.estimates[destination] = record
		entry.query_charge += int(record.charge)
		_query_charged += int(record.charge)
	record.hits += 1
	# One-off quotes retain A*. Repeated endpoints amortize a distance field;
	# only integer distance is reused, never a route or permission to reserve.
	if not record.ready and int(record.hits)>=12:
		var query: RouteClearance = RouteClearance.new(space,world,actor,floor_id,[],{},true,current.geometry.source,current.geometry)
		record.reason = "" if forward else (query.reason(goal) if FloorNavigation._inside(goal) else "目标超出96×96真实楼面")
		var field: Dictionary
		if forward:
			record.query = query
			field = {"distances":_forward_field(current,query,start),"successors":PackedInt32Array()}
		else:
			field = _distance_field(current,query,goal) if str(record.reason).is_empty() else {"distances":PackedInt32Array(),"successors":PackedInt32Array()}
		record.distances = field.distances
		record.successors = field.successors
		record.ready = true
		var charge: int = ((record.distances as PackedInt32Array).size()+(record.successors as PackedInt32Array).size())*16
		if forward: charge += floor_source(space,world,floor_id).occupancy.size()*256+16384
		record.charge += charge
		entry.query_charge = int(entry.get("query_charge",0))+charge
		_query_charged += charge
	_trim(int(space.content.balance.pathfinding.graph_cache_target_bytes))
	if not record.ready: return {"ready":false}
	if not FloorNavigation._inside(start) or not FloorNavigation._inside(goal):
		return {"ready":true,"ok":false,"reason":"目标超出96×96真实楼面"}
	if forward:
		# Leaving a reserved start is legal, entering that same reserved cell as
		# the goal is not. Retain the full query's goal-first reason and zero leg.
		var reason: String = record.query.reason(goal)
		if not reason.is_empty(): return {"ready":true,"ok":false,"reason":reason}
	if not str(record.reason).is_empty(): return {"ready":true,"ok":false,"reason":record.reason}
	var distance: int = record.distances[FloorNavigation._id(goal if forward else start)]
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

func _forward_field(graph: FloorNavigation, query: RouteClearance, start: Vector2i) -> PackedInt32Array:
	var distances: PackedInt32Array = PackedInt32Array()
	distances.resize(FloorNavigation.LIMIT)
	distances.fill(-1)
	if not FloorNavigation._inside(start): return distances
	var start_id: int = FloorNavigation._id(start)
	if not graph.has_point(start_id) or graph.is_point_disabled(start_id): return distances
	var reservations: PackedByteArray = query.reservation_mask()
	var queue: Array[int] = [start_id]
	distances[start_id] = 0
	var cursor: int = 0
	while cursor<queue.size():
		var current: int = queue[cursor]
		cursor += 1
		var x: int = current%FloorNavigation.SIDE
		for step: int in FIELD_STEPS:
			var id: int = current+step
			if id<0 or id>=FloorNavigation.LIMIT or step==-1 and x==0 or step==1 and x==FloorNavigation.SIDE-1: continue
			if distances[id]>=0 or not graph.has_point(id) or graph.is_point_disabled(id) or not graph.are_points_connected(current,id,false): continue
			if not reservations.is_empty() and reservations[id]!=0: continue
			distances[id] = distances[current]+1
			queue.append(id)
	return distances

func _distance_field(graph: FloorNavigation, query: RouteClearance, goal: Vector2i) -> Dictionary:
	var distances: PackedInt32Array = PackedInt32Array()
	distances.resize(FloorNavigation.LIMIT)
	distances.fill(-1)
	var successors: PackedInt32Array = distances.duplicate()
	var result: Dictionary = {"distances":distances,"successors":successors}
	var goal_id: int = FloorNavigation._id(goal)
	if not graph.has_point(goal_id) or graph.is_point_disabled(goal_id): return result
	var reservations: PackedByteArray = query.reservation_mask()
	var queue: Array[int] = [goal_id]
	distances[goal_id] = 0
	var cursor: int = 0
	while cursor<queue.size():
		var current: int = queue[cursor]
		cursor += 1
		var x: int = current%FloorNavigation.SIDE
		# The existing search permits leaving a reserved start, but never
		# entering a reserved destination. Reverse expansion keeps that rule.
		if not reservations.is_empty() and reservations[current]!=0: continue
		for step: int in FIELD_STEPS:
			var id: int = current+step
			if id<0 or id>=FloorNavigation.LIMIT or step==-1 and x==0 or step==1 and x==FloorNavigation.SIDE-1: continue
			if distances[id]>=0 or not graph.has_point(id) or graph.is_point_disabled(id) or not graph.are_points_connected(id,current,false): continue
			distances[id] = distances[current]+1
			successors[id] = current
			queue.append(id)
	return result

func _envelope(space: HospitalSpace, world: WorldState, actor: Dictionary, members: Array, offsets: Dictionary, source: Dictionary) -> String:
	var shapes: Array = [_traversal_shape(space,actor,[0,0],source)]
	for id: String in members:
		if id!=actor.id:
			shapes.append(_traversal_shape(space,world.facts.actors[id],offsets[id],source))
	return JSON.stringify(shapes,"",true,true)

func _traversal_shape(space: HospitalSpace, actor: Dictionary, offset: Array, source: Dictionary) -> Array:
	# Floor nodes/sweeps use the integer clearance; door expansion adds its
	# actual 0.1m margin. Heights enter only these two ceiling predicates.
	# Facility fits and actual body collisions still use complete dimensions.
	var body: Dictionary = space.body(actor)
	var height: float = float(body.depth_m if actor.get("posture","standing")=="lying" else body.height_m)
	return [space.clearance(actor),ceili((maxf(float(body.width_m),float(body.depth_m))+0.1)/HospitalSpace.CELL_METERS),height<=float(source.height),float(body.height_m)+0.1<=float(source.door_height),offset]
