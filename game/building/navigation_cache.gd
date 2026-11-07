class_name NavigationCache
extends RefCounted


var _entries: Dictionary = {}
var _sources: Dictionary = {}
var _used: int = 0
var _charged: int = 0
var _query_charged: int = 0
var _source_charged: int = 0

# Static floors and body-dependent graphs share one allowance. A floor is
# prepared completely even if too large to retain; the returned object remains
# valid and later queries can rebuild it. There is no partial floor or body cap.
var _floor_geometries: Dictionary = {}
var _floor_charged: int = 0
var _defer_trim: int = 0

func prepare_floor(space: HospitalSpace, world: WorldState, floor_id: int) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var source: Dictionary = floor_source(space,world,floor_id)
	var version: String = _source_record(space,world,floor_id).static_version
	var hit: bool = _floor_geometries.has(version)
	var geometry: FloorStaticGeometry = floor_geometry(space,world,floor_id,source)
	return {"complete":true,"floor_id":floor_id,"resident_hit":hit,"retained":_floor_geometries.has(version),"elapsed_usec":Time.get_ticks_usec()-started,"plots":geometry._plots.size(),"walls":geometry._walls.size(),"doors":geometry.doors.size(),"blocking_facilities":geometry._facilities.size(),"connectors":geometry._connectors.size(),"charge_bytes":geometry.charge}

func floor_geometry(space: HospitalSpace, world: WorldState, floor_id: int, supplied: Dictionary = {}) -> FloorStaticGeometry:
	var current: Dictionary = floor_source(space,world,floor_id)
	var record: Dictionary = _source_record(space,world,floor_id)
	# Explicit hypothetical sources must not borrow a current world's geometry.
	if not supplied.is_empty() and not is_same(supplied,current) and not is_same(supplied,record.static_source):
		var static_supplied: Dictionary = supplied.duplicate()
		static_supplied.erase("occupancy")
		if static_supplied!=record.static_source: return FloorStaticGeometry.new(space,floor_id,static_supplied)
	var version: String = record.static_version
	var entry: Dictionary = _floor_geometries.get(version,{})
	if entry.is_empty():
		var built: FloorStaticGeometry = FloorStaticGeometry.new(space,floor_id,record.static_source)
		entry = {"geometry":built,"charge":built.charge}
		_floor_charged += built.charge
	_floor_geometries.erase(version)
	_floor_geometries[version] = entry
	var result: FloorStaticGeometry = entry.geometry
	if _defer_trim==0: _trim(int(space.content.balance.pathfinding.graph_cache_target_bytes),space.query_counts)
	return result

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
		var identity: Dictionary = _static_identity(projected,floor_id,current)
		var same_static: bool = identity.version==original.static_version
		var entry: Dictionary = {"source":original.source if identical else current,"world":weakref(projected),"floor_id":floor_id,"revision":projected.geometry_revision,"version":original.version if identical else _identity(floor_id,current),"static_source":identity.source,"static_version":identity.version,"graphs":original.graphs.duplicate() if same_static else {}}
		_store_source(str(projected.get_instance_id())+":"+str(floor_id),entry)
	if _defer_trim==0: _trim_source_payloads(int(space.content.balance.pathfinding.graph_cache_target_bytes),space.query_counts)

# A returned record is a synchronous borrower even when the target cannot
# retain it. No caller may require a resident _sources entry after trimming.
func floor_source(space: HospitalSpace, world: WorldState, floor_id: int) -> Dictionary:
	return _source_record(space,world,floor_id).source

func _source_record(space: HospitalSpace, world: WorldState, floor_id: int) -> Dictionary:
	var key: String = str(world.get_instance_id())+":"+str(floor_id)
	var entry: Dictionary = _sources.get(key,{})
	if not entry.is_empty() and entry.world.get_ref()!=world: entry = {}
	if entry.is_empty() or entry.revision!=world.geometry_revision:
		var current: Dictionary = RouteClearance.capture_source(space,world,floor_id)
		if entry.is_empty() or entry.source!=current:
			var identity: Dictionary = _static_identity(world,floor_id,current)
			var graphs: Dictionary = entry.graphs if not entry.is_empty() and entry.static_version==identity.version else {}
			entry = {"source":current,"world":weakref(world),"floor_id":floor_id,"version":_identity(floor_id,current),"static_source":identity.source,"static_version":identity.version,"graphs":graphs}
		entry.revision = world.geometry_revision
	_store_source(key,entry)
	if _defer_trim==0: _trim_source_payloads(int(space.content.balance.pathfinding.graph_cache_target_bytes),space.query_counts)
	return entry

func _store_source(key: String, entry: Dictionary) -> void:
	if _sources.has(key): _source_charged -= int(_sources[key].charge)
	# Conservative allowance for both payload views, equality proof keys and
	# record metadata. Shared containers may be charged twice, never omitted.
	entry.charge = 2048+(var_to_bytes(entry.source).size()+var_to_bytes(entry.static_source).size())*8+entry.graphs.size()*1024
	_sources.erase(key)
	_sources[key] = entry
	_source_charged += int(entry.charge)

# Source acquisition can occur while a graph/query owner is borrowed by a
# caller. Reclaim only source records here; never evict that graph mid-update.
func _trim_source_payloads(target: int, _counts: Dictionary = {}) -> void:
	_prune_sources()
	var allowance: int = maxi(0,mini(target/4,target-_floor_charged-_charged-_query_charged))
	for key: String in _sources.keys():
		if _source_charged<=allowance: break
		_source_charged -= int(_sources[key].charge)
		_sources.erase(key)

func _identity(floor_id: int, source: Dictionary) -> String:
	# Canonical keys, full-precision numbers and ordered arrays. Reconstructed
	# content identity survives eviction without a permanent floor history map.
	return JSON.stringify([floor_id,source],"",true,true).sha256_text()

func facility_index(space: HospitalSpace, world: WorldState, floor_id: int) -> BodyIndex:
	return floor_geometry(space,world,floor_id).facility_index

func floor_version(space: HospitalSpace, world: WorldState, floor_id: int) -> String:
	return _source_record(space,world,floor_id).version

func floor_static_version(space: HospitalSpace, world: WorldState, floor_id: int) -> String:
	return _source_record(space,world,floor_id).static_version

func _static_identity(_world: WorldState, floor_id: int, current: Dictionary) -> Dictionary:
	var source: Dictionary = current.duplicate()
	source.erase("occupancy")
	return {"source":source,"version":_identity(floor_id,source)}

# A point check can borrow already-built static geometry without paying to
# build an A* graph. Its reservation query is always constructed afresh.
func cached_static_geometry(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary) -> RouteClearance:
	var current: Dictionary = floor_source(space,world,floor_id)
	var key: String = _graph_key(space,world,floor_id,actor,[],{},current)
	var source_record: Dictionary = _source_record(space,world,floor_id)
	var entry: Dictionary = _entries.get(key,{})
	if entry.is_empty(): return null
	if int(source_record.graphs.get(key,0))!=entry.graph.geometry.get_instance_id():
		var source: Dictionary = source_record.static_source
		if entry.source!=source: return null
		source_record.graphs[key] = entry.graph.geometry.get_instance_id()
		if _sources.has(str(world.get_instance_id())+":"+str(floor_id)): _store_source(str(world.get_instance_id())+":"+str(floor_id),source_record)
	_used += 1
	entry.used = _used
	_entries.erase(key)
	_entries[key] = entry
	var result: RouteClearance = entry.graph.geometry
	_trim(int(space.content.balance.pathfinding.graph_cache_target_bytes),space.query_counts)
	return result

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
	if ids.is_empty(): return {"graph":primary,"bases":bases,"shifts":shifts}
	var member_geometries: Dictionary = {}
	for id: String in ids:
		var member_graph: FloorNavigation = graph(space,world,floor_id,world.facts.actors[id],[],{})
		bases.append(member_graph)
		member_geometries[id] = member_graph.geometry
	var result: Dictionary = {"graph":primary,"bases":bases,"shifts":shifts}
	# These immutable geometries were acquired for this exact query already;
	# no extra graph build or retained cross-query permission is introduced.
	result.member_geometries = member_geometries
	return result

func graph(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, members: Array, offsets: Dictionary) -> FloorNavigation:
	var current: Dictionary = floor_source(space,world,floor_id)
	var key: String = _graph_key(space,world,floor_id,actor,members,offsets,current)
	var source_record: Dictionary = _source_record(space,world,floor_id)
	var entry: Dictionary = _entries.get(key,{})
	_used += 1
	if entry.is_empty() or int(source_record.graphs.get(key,0))!=entry.graph.geometry.get_instance_id():
		# Each immutable source remembers the graph geometries it has compared.
		# Query-only reservations may alternate worlds without comparing again.
		var source: Dictionary = source_record.static_source
		if entry.is_empty() or entry.source!=source:
			entry = _refresh_graph(space,world,floor_id,actor,members,offsets,source,entry)
			_entries[key] = entry
		source_record.graphs[key] = entry.graph.geometry.get_instance_id()
		if _sources.has(str(world.get_instance_id())+":"+str(floor_id)): _store_source(str(world.get_instance_id())+":"+str(floor_id),source_record)
	entry.used = _used
	_entries.erase(key)
	_entries[key] = entry
	var result: FloorNavigation = entry.graph
	_trim(int(space.content.balance.pathfinding.graph_cache_target_bytes),space.query_counts)
	return result

func _refresh_graph(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, members: Array, offsets: Dictionary, source: Dictionary, entry: Dictionary) -> Dictionary:
	_defer_trim += 1
	var geometry: RouteClearance = RouteClearance.new(space,world,actor,floor_id,members,offsets,false,source)
	_defer_trim -= 1
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
	var charge: int = floor_graph.get_point_count()*1024+var_to_bytes(source).size()*8+16384+FloorNavigation.LIMIT
	entry = {"graph":floor_graph,"source":source,"used":_used,"charge":charge,"floor_id":floor_id}
	_charged += charge
	return entry

func _trim(target: int, counts: Dictionary = {}) -> void:
	# Limit shared floor ownership to one quarter of the same existing target,
	# then give graphs/queries the remainder. Never increase the total allowance.
	_prune_sources()
	for key: String in _sources.keys():
		if _source_charged<=maxi(0,target/4): break
		_source_charged -= int(_sources[key].charge)
		_sources.erase(key)
	for version: String in _floor_geometries.keys():
		if _floor_charged+_source_charged<=maxi(0,target/4): break
		_floor_charged -= int(_floor_geometries[version].charge)
		_floor_geometries.erase(version)
		counts["cache_floor_evictions"] = int(counts.get("cache_floor_evictions",0))+1
	target = maxi(0,target-_floor_charged-_source_charged)
	if _charged+_query_charged<=target and _query_charged<=target/4: return
	counts["cache_trims"] = int(counts.get("cache_trims",0))+1
	var keys: Array = _entries.keys()
	# Dictionary preserves insertion order; touches move entries to the tail.
	for key: String in keys:
		var entry: Dictionary = _entries[key]
		if _query_charged>target/4:
			counts["cache_query_clears"] = int(counts.get("cache_query_clears",0))+1
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
		# Geometry equality proofs belong to the resident graph, while the
		# latest live floor facts retain their identity after graph eviction.
		for source: Dictionary in _sources.values():
			source.graphs.erase(key)
		counts["cache_graph_evictions"] = int(counts.get("cache_graph_evictions",0))+1
	_prune_sources()

func _prune_sources() -> void:
	for key: String in _sources.keys():
		if _sources[key].world.get_ref()==null:
			_source_charged -= int(_sources[key].charge)
			_sources.erase(key)

func clearance(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, members: Array = [], offsets: Dictionary = {}) -> RouteClearance:
	var current: FloorNavigation = graph(space,world,floor_id,actor,[],{})
	var key: String = _graph_key(space,world,floor_id,actor,[],{},floor_source(space,world,floor_id))
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
		# A grouped query constructs member projections. Do not evict this
		# partially accounted owner until the complete query is published.
		_defer_trim += 1
		var query: RouteClearance = RouteClearance.new(space,world,actor,floor_id,members,offsets,true,source,current.geometry)
		_defer_trim -= 1
		record = {"stamp":stamp.duplicate(true),"query":query,"charge":charge}
		entry.queries[actor.id] = record
		entry.query_charge += int(record.charge)
		_query_charged += int(record.charge)
	_trim(int(space.content.balance.pathfinding.graph_cache_target_bytes),space.query_counts)
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
func cached_floor_path(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, graph: FloorNavigation, query: RouteClearance, start: Vector2i, goal: Vector2i, cost_only: bool = false) -> Dictionary:
	var key: String = _graph_key(space,world,floor_id,actor,[],{},floor_source(space,world,floor_id))
	var entry: Dictionary = _entries.get(key,{})
	var record: Dictionary = entry.get("queries",{}).get(actor.id,{})
	if not entry.is_empty() and entry.graph==graph and query==graph.geometry:
		if not entry.has("structural_paths"): entry.structural_paths = {"charge":0}
		record = entry.structural_paths
	# clearance() can evict its own entry; externally supplied graphs/queries
	# also remain valid computations but cannot use this record's allowance.
	if entry.is_empty() or entry.graph!=graph or record.is_empty() or (query!=graph.geometry and record.query!=query):
		space.query_counts.static_path_builds += 1
		return graph.find_path(start,goal,query,Callable(),false,[],[],false,cost_only)
	if not record.has("paths"): record.paths = {}
	var endpoints: Vector4i = Vector4i(start.x,start.y,goal.x,goal.y)
	if record.paths.has(endpoints) and (cost_only or not record.paths[endpoints].value.get("ok",false) or record.paths[endpoints].has("cells")):
		space.query_counts.static_path_hits += 1
		var saved: Dictionary = record.paths[endpoints]
		var result: Dictionary = saved.value.duplicate()
		if saved.has("cells") and not cost_only:
			result.cells = []
			for id: int in saved.cells:
				# Cached IDs are bounded floor cells; decode without a temporary vector.
				result.cells.append([id%FloorNavigation.SIDE,id/FloorNavigation.SIDE])
		return result
	space.query_counts.static_path_builds += 1
	var result: Dictionary = graph.find_path(start,goal,query,Callable(),false,[],[],false,cost_only)
	var saved: Dictionary = {"value":result.duplicate()}
	var charge: int = 512+var_to_bytes(result).size()*8
	if result.has("cells"):
		var cells: PackedInt32Array = PackedInt32Array()
		for cell: Array in result.cells: cells.append(int(cell[1])*FloorNavigation.SIDE+int(cell[0]))
		saved.value.erase("cells")
		saved.cells = cells
		charge += cells.size()*16
	# Replacing an earlier cost-only record must not charge its allowance twice.
	var previous_charge: int = int(record.paths.get(endpoints,{}).get("charge",0))
	charge -= previous_charge
	saved.charge = charge+previous_charge
	record.paths[endpoints] = saved
	record.charge += charge
	entry.query_charge = int(entry.get("query_charge",0))+charge
	_query_charged += charge
	_trim(int(space.content.balance.pathfinding.graph_cache_target_bytes),space.query_counts)
	return result

func travel_distance(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, start: Vector2i, goal: Vector2i, witness: bool = false) -> Dictionary:
	return _travel_distance(space,world,floor_id,actor,start,goal,witness,false)

# Region quotes ask for many goals from the same start or connector landing.
# Share exact distances only; actual movement still obtains its original path.
func forward_distance(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, start: Vector2i, goal: Vector2i, structural_only: bool = false, prepared_graph: FloorNavigation = null) -> Dictionary:
	return _travel_distance(space,world,floor_id,actor,start,goal,false,true,structural_only,prepared_graph)

# Different travellers can share a complete structural graph and destination.
# This cost-only field owns no route, actor permission or extra cache budget.
func reverse_structural_distance(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, start: Vector2i, goal: Vector2i, prepared_graph: FloorNavigation = null) -> Dictionary:
	return _travel_distance(space,world,floor_id,actor,start,goal,false,false,true,prepared_graph)

# Borrow only a resident, already-built field for one synchronous task loop.
# This does not advance its warmup, retain a graph or create an extra allowance.
func ready_structural_field(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, root: Vector2i) -> Dictionary:
	if not space.in_dynamic_route_query(world): return {}
	# This performs the original complete current-source proof before exposing
	# any old field. A same-key graph can still describe a previous floor edit.
	var geometry: RouteClearance = cached_static_geometry(space,world,floor_id,actor)
	if geometry==null: return {}
	var key: String = _graph_key(space,world,floor_id,actor,[],{},floor_source(space,world,floor_id))
	var entry: Dictionary = _entries.get(key,{})
	if entry.is_empty(): return {}
	var destination: String = _distance_destination(space,world,floor_id,actor,root,root,true,true,[])
	var record: Dictionary = entry.get("estimates",{}).get(destination,{})
	if not record.get("ready",false) or record.get("stamp",[])!=[geometry.get_instance_id()]: return {}
	return {"ready":true,"distances":record.distances}

func _travel_distance(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, start: Vector2i, goal: Vector2i, witness: bool, forward: bool, structural_only: bool = false, prepared_graph: FloorNavigation = null) -> Dictionary:
	# Only a structural query may pass its just-acquired graph. Permission-
	# dependent distance fields retain the original graph/clearance acquisition.
	var current: FloorNavigation = prepared_graph if structural_only and prepared_graph!=null else graph(space,world,floor_id,actor,[],{})
	var key: String = _graph_key(space,world,floor_id,actor,[],{},floor_source(space,world,floor_id))
	if not _entries.has(key): return {"ready":false}
	var entry: Dictionary = _entries[key]
	if not entry.has("estimates"): entry.estimates = {}
	# A distance field depends on the body envelope and forbidden reservations,
	# not the traveller's identity when it grants no different exemption.
	var exemptions: Array = []
	if not structural_only:
		for reservation: Array in floor_source(space,world,floor_id).occupancy:
			if actor.id==reservation[1] or actor.id in reservation[2]: exemptions.append(reservation[0])
	var destination: String = _distance_destination(space,world,floor_id,actor,start,goal,forward,structural_only,exemptions)
	var stamp: Array = [current.geometry.get_instance_id()] if structural_only else _reservation_stamp(space,current,world,floor_id,actor.id)
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
		var query: RouteClearance = current.geometry if structural_only else RouteClearance.new(space,world,actor,floor_id,[],{},true,current.geometry.source,current.geometry)
		record.reason = "" if forward else (query.reason(goal) if FloorNavigation._inside(goal) else "目标超出96×96真实楼面")
		var field: Dictionary
		if forward:
			record.query = query
			field = current.distance_field(query,start)
		else:
			field = current.distance_field(query,goal,true) if str(record.reason).is_empty() else {"ready":true,"distances":PackedInt32Array(),"successors":PackedInt32Array()}
		if not field.get("ready",false):
			space.query_counts["distance_field_failures"] = int(space.query_counts.get("distance_field_failures",0))+1
			return {"ready":false}
		space.query_counts["distance_field_builds"] = int(space.query_counts.get("distance_field_builds",0))+1
		record.distances = field.distances
		record.successors = PackedInt32Array() if structural_only and not forward else field.successors
		record.ready = true
		var charge: int = ((record.distances as PackedInt32Array).size()+(record.successors as PackedInt32Array).size())*16
		if forward: charge += floor_source(space,world,floor_id).occupancy.size()*256+16384
		record.charge += charge
		entry.query_charge = int(entry.get("query_charge",0))+charge
		_query_charged += charge
	_trim(int(space.content.balance.pathfinding.graph_cache_target_bytes),space.query_counts)
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

func _graph_key(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, members: Array, offsets: Dictionary, source: Dictionary) -> String:
	if members.is_empty() and offsets.is_empty() and space.in_dynamic_route_query(world):
		# Keys contain immutable values only. Graph acquisition, source validation
		# and budget eviction remain in each caller; no graph is held by the scope.
		var view: Dictionary = space.read_view(world,"navigation_graph_keys",func()->Dictionary:return {})
		var floors: Dictionary = view.get_or_add(actor.id,{})
		var heights: Dictionary = floors.get_or_add(floor_id,{})
		var keys: Dictionary = heights.get_or_add(float(source.height),{})
		var door_height: float = float(source.door_height)
		if not keys.has(door_height): keys[door_height] = str(floor_id)+":"+_envelope(space,world,actor,[],{},source)
		return keys[door_height]
	return str(floor_id)+":"+_envelope(space,world,actor,members,offsets,source)

func _distance_destination(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, start: Vector2i, goal: Vector2i, forward: bool, structural_only: bool, exemptions: Array) -> String:
	if structural_only and space.in_dynamic_route_query(world):
		# Permission-dependent consumers retain their complete live exemption key.
		# This view reuses only the original structural endpoint serialization.
		var view: Dictionary = space.read_view(world,"navigation_distance_keys",func()->Dictionary:return {})
		var roots: Dictionary = view.get_or_add(actor.id,{}).get_or_add(floor_id,{}).get_or_add(forward,{})
		var point: Vector2i = start if forward else goal
		if not roots.has(point): roots[point] = JSON.stringify(["from",start.x,start.y,true,[]]) if forward else JSON.stringify(["to",goal.x,goal.y,true,[]])
		return roots[point]
	if forward: return JSON.stringify(["from",start.x,start.y,structural_only,exemptions])
	return JSON.stringify(["to",goal.x,goal.y,true,[]]) if structural_only else JSON.stringify([goal.x,goal.y,exemptions])

func _envelope(space: HospitalSpace, world: WorldState, actor: Dictionary, members: Array, offsets: Dictionary, source: Dictionary) -> String:
	if members.is_empty() and offsets.is_empty() and space.in_dynamic_route_query(world):
		var view: Dictionary = space.read_view(world,"navigation_envelopes",func()->Dictionary:return {})
		var heights: Dictionary = view.get_or_add(actor.id,{})
		var variants: Dictionary = heights.get_or_add(float(source.height),{})
		var door_height: float = float(source.door_height)
		if not variants.has(door_height): variants[door_height] = JSON.stringify([_traversal_shape(space,actor,[0,0],source)],"",true,true)
		return variants[door_height]
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
