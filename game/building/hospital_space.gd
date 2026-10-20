class_name HospitalSpace
extends RefCounted

const CELL_METERS: float = 1.5
var content: HospitalContent
var _bodies: Dictionary = {}
var _actor_shapes: Dictionary = {}
var _actor_index: BodyIndex = BodyIndex.new()
var _indexed_world: WorldState
var _indexed_revision: int = -1
var _indexed_actor_scope: Dictionary = {}
var _navigation: NavigationCache = NavigationCache.new()
var _envelope_next: int = 0
var _route_queries: Array[Dictionary] = []
var _reservation_views: Dictionary = {}
var _door_views: Dictionary = {}
var movement: HospitalMovement
var navigation: HospitalNavigation
var public_areas: HospitalPublicAreas
var query_counts: Dictionary = {"routes":0,"journey_hits":0,"journey_invalidations":0,"transport_builds":0,"transport_searches":0,"candidate_connections":0,"floor_route_hits":0,"floor_route_builds":0,"static_path_hits":0,"static_path_builds":0,"materialized_floor_cells":0,"reservation_index_builds":0,"reservation_index_updates":0,"door_candidates":0,"movement_candidates":0,"reservation_candidate_queries":0,"route_checks":0,"route_revalidations":0,"route_dispatch_scans":0,"route_dispatch_restores":0,"yield_attempts":0,"yield_candidates":0,"connector_topology_builds":0}

# These scopes contain synchronous, read-only enumeration only. Results never
# survive an actual reservation, movement or any other world fact change.
func begin_route_query(world: WorldState, reference: Dictionary = {}, inherit_reference: bool = true) -> void:
	var parent: Dictionary = _route_queries.back() if not _route_queries.is_empty() and _route_queries.back().world==world else {}
	var views: Dictionary = {}
	var exits: Dictionary = parent.get("exits",{})
	if inherit_reference and reference.is_empty() and not _route_queries.is_empty():
		reference = _route_queries.back().reference
	# Some views include fit/trip results: actual occupancy and nominal geometry
	# are different queries even on the same world. Independent reference batches
	# can also own distinct transport bases. Ordinary read-only children still share.
	if not parent.is_empty() and (parent.reference.is_empty() and reference.is_empty() or is_same(parent.reference,reference)):
		views = parent.views
	if not reference.is_empty() and not reference.has("routes"):
		reference.routes = {}
		reference.fits = {}
		reference.journeys = {}
	if not _route_queries.is_empty() and not reference.is_empty() and is_same(reference,_route_queries.back().reference):
		# Nested scopes belong to the same sealed read-only transport batch.
		_route_queries.append({"world":world,"routes":reference.routes,"exits":exits,"views":views,"reference":reference,"journeys_allowed":_route_queries.back().journeys_allowed})
		return
	if not parent.is_empty() and parent.get("dynamic",false) and reference.is_empty():
		# Child helpers are part of this same sealed enumeration. A projected
		# world has no parent here and must build its own access/occupancy views.
		_route_queries.append({"world":world,"routes":parent.routes,"exits":exits,"views":views,"reference":reference,"journeys_allowed":false,"dynamic":true,"transport":parent.transport})
		return
	var journeys_allowed: bool = not reference.is_empty()
	_route_queries.append({"world":world,"routes":reference.get("routes",parent.get("routes",{})),"exits":exits,"views":views,"reference":reference,"journeys_allowed":journeys_allowed})

func end_route_query() -> void:
	var finished: Dictionary = _route_queries.pop_back()
	if is_same(_indexed_actor_scope,finished): _indexed_actor_scope = {}
	if _route_queries.is_empty(): return
	var child: Dictionary = finished.reference
	var parent: Dictionary = _route_queries.back().reference
	if not child.is_empty() and not parent.is_empty() and not is_same(child,parent) and child.get("transport_dependent",false):
		_mark_transport_dependency(parent)

func begin_dynamic_route_query(world: WorldState, refresh_actors: bool = true) -> void:
	# A single real actor's sealed candidate enumeration. This never enables
	# nominal transport, and ends before any task/reservation/move is committed.
	if refresh_actors: _indexed_revision = -1
	_ensure_actor_index(world)
	_route_queries.append({"world":world,"routes":{},"exits":{},"views":{},"reference":{},"journeys_allowed":false,"dynamic":true,"transport":{}})

func dynamic_transport_view(world: WorldState, actor_id: String, members: Array, offsets: Dictionary) -> Dictionary:
	if _route_queries.is_empty() or _route_queries.back().world!=world or not _route_queries.back().get("dynamic",false): return {}
	var views: Dictionary = _route_queries.back().transport
	var key: String = JSON.stringify([actor_id,members,offsets])
	if not views.has(key): views[key] = {}
	return views[key]

func _mark_transport_dependency(reference: Dictionary) -> void:
	reference.transport_dependent = true
	reference.dependency_revision = int(reference.get("dependency_revision",0))+1

func read_view(world: WorldState, name: String, build: Callable) -> Dictionary:
	if _route_queries.is_empty() or _route_queries.back().world!=world: return build.call()
	var views: Dictionary = _route_queries.back().views
	if not views.has(name): views[name] = build.call()
	return views[name]

func prepare_projection(world: WorldState, projected: WorldState, facility_ids: Array = [], route_floors: Array = []) -> void:
	if not route_floors.is_empty():
		# Prepare the original owner once for the same sparse floor candidates
		# a complete transit query can visit, then inherit its exact delta.
		var floors: Dictionary = HospitalTransit._routing_candidates(world,int(route_floors[0]),int(route_floors.back()))
		for floor_id: int in route_floors: floors[floor_id] = true
		for floor_id: int in floors: _navigation.floor_source(self,world,floor_id)
	_navigation.inherit_projection(self,world,projected,facility_ids)
	navigation.inherit_projection(world,projected)

func nominal_query(world: WorldState) -> bool:
	return not _route_queries.is_empty() and _route_queries.back().world==world and not _route_queries.back().reference.is_empty()

func transport_search(world: WorldState) -> void:
	query_counts.transport_searches += 1
	if not _route_queries.is_empty() and _route_queries.back().world==world:
		var reference: Dictionary = _route_queries.back().reference
		if not reference.is_empty():
			_mark_transport_dependency(reference)
			reference.transport_searches = int(reference.get("transport_searches",0))+1

func _blocking_facility(world: WorldState, floor_id: int, rect: Rect2, except_id: String = "") -> String:
	var hits: Array[String] = _navigation.facility_index(self,world,floor_id).candidates(floor_id,rect,[except_id])
	if hits.is_empty(): return ""
	if hits.size()==1 or not _route_queries.is_empty() and _route_queries.back().world==world: return hits[0]
	# The unscoped diagnostic keeps the original facts order when several
	# facilities block. Clear paths never scan the full collection or layouts.
	for id: String in world.facts.facilities:
		if id in hits: return id
	return ""

func _blocking_actor(world: WorldState, floor_id: int, rect: Rect2, allowed: Array) -> String:
	if not _route_queries.is_empty() and _route_queries.back().world==world:
		_ensure_actor_index(world)
		var hits: Array[String] = _actor_index.candidates(floor_id,rect,allowed)
		return "" if hits.is_empty() else hits[0]
	for actor: Dictionary in world.facts.actors.values():
		if not actor.id in allowed and actor.location.kind=="floor" and int(actor.location.floor_id)==floor_id and rect.intersects(body_rectangle(actor),false): return actor.id
	return ""

func _init(database: HospitalContent) -> void:
	content = database
	movement = HospitalMovement.new(self)
	navigation = HospitalNavigation.new(self)
	public_areas = HospitalPublicAreas.new(self)
	var cells: Array = content.balance.pathfinding.local_updates.chunk_cells
	_actor_index = BodyIndex.new(Vector2(float(cells[0]),float(cells[1])))

func body(actor: Dictionary) -> Dictionary:
	var key: String = str(actor.species_id)+":"+str(actor.get("body_binding_id",""))
	if not _bodies.has(key):
		_bodies[key] = content.actor_body(actor)
	return _bodies[key]

func _ensure_actor_index(world: WorldState) -> void:
	var scope: Dictionary = {}
	for active: Dictionary in _route_queries:
		if is_same(active.world.facts.actors,world.facts.actors):
			scope = active
			break
	if world==_indexed_world and world.revision==_indexed_revision:
		_indexed_actor_scope = scope
		return
	# A sealed read-only enumeration may alternate reservation projections
	# with the exact same actors collection. Its active scope owns this reuse;
	# crossing scope/world boundaries retains the original rebuild behavior.
	var shared: bool = world!=_indexed_world and _indexed_world!=null and _indexed_revision>=0 and not scope.is_empty() and is_same(scope,_indexed_actor_scope) and is_same(world.facts.actors,_indexed_world.facts.actors)
	if world!=_indexed_world:
		if not shared: _actor_shapes.clear()
	if not shared: _actor_index.clear()
	_indexed_world = world
	_indexed_revision = world.revision
	_indexed_actor_scope = scope
	if not shared:
		for id: String in world.ids("actors"):
			_sync_actor(world,id)

func sync_actor(world: WorldState, id: String) -> void:
	_ensure_actor_index(world)
	_sync_actor(world,id)

func _sync_actor(world: WorldState, id: String) -> void:
	var actor: Dictionary = world.facts.actors[id]
	if actor.location.kind=="floor":
		_actor_index.update(id,int(actor.location.floor_id),body_rectangle(actor))
	else:
		_actor_index.remove(id)

func finish_boundary(world: WorldState) -> void:
	_indexed_revision = world.revision

func clearance(actor: Dictionary) -> int:
	var dimensions: Dictionary = body(actor)
	return ceili(maxf(float(dimensions.width_m), float(dimensions.depth_m)) / CELL_METERS)

func owned(world: WorldState, floor_id: int, cell: Vector2i) -> bool:
	if floor_id<1 or cell.x<0 or cell.y<0 or cell.x>=96 or cell.y>=96:
		return false
	for plot: Array in floor_plots(world,floor_id):
		if cell.x >= int(plot[0]) * 32 and cell.x < (int(plot[0]) + 1) * 32 and cell.y >= int(plot[1]) * 32 and cell.y < (int(plot[1]) + 1) * 32:
			return true
	return false

static func plot_key(plot: Array) -> String:
	return "%d:%d" % [int(plot[0]),int(plot[1])]

static func floor_plots(world: WorldState, floor_id: int) -> Array:
	if not world.facts.floors.has("completed_top_floor"):
		return world.facts.floors.overrides.get(str(floor_id),{}).get("plots",[])
	var result: Array = []
	for plot: Array in world.facts.floors.overrides["1"].plots:
		if floor_id>=1 and floor_id<=int(world.facts.floors.completed_top_floor.get(plot_key(plot),1)):
			result.append(plot)
	return result

static func floor_layout(world: WorldState, floor_id: int) -> Dictionary:
	var result: Dictionary = world.facts.floors.overrides.get(str(floor_id),{}).duplicate()
	result.plots = floor_plots(world,floor_id)
	return result

static func materialize_layout(world: WorldState, floor_id: int) -> void:
	if not world.facts.floors.overrides.has(str(floor_id)):
		world.facts.floors.overrides[str(floor_id)] = {"doors":[],"blocked":[],"paths":[]}

func static_reason(world: WorldState, actor: Dictionary, floor_id: int, origin: Vector2i, members: Array = [], offsets: Dictionary = {}) -> String:
	if members.is_empty() and not _route_queries.is_empty() and _route_queries.back().world==world:
		return _navigation.clearance(self,world,floor_id,actor).reason(origin)
	if members.is_empty():
		var geometry: RouteClearance = _navigation.cached_static_geometry(self,world,floor_id,actor)
		if geometry!=null:
			return RouteClearance.new(self,world,actor,floor_id,[],{},true,_navigation.floor_source(self,world,floor_id),geometry).reason(origin)
	return RouteClearance.new(self,world,actor,floor_id,members,offsets,true,_navigation.floor_source(self,world,floor_id)).reason(origin)

func route(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false) -> Dictionary:
	return _route_result(world,actor_id,floor_id,target,members,offsets,ignore_people,false)

func route_cost(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false) -> Dictionary:
	return _route_result(world,actor_id,floor_id,target,members,offsets,ignore_people,true)

func can_reach(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false) -> bool:
	return bool(_route_result(world,actor_id,floor_id,target,members,offsets,ignore_people,true).ok)

func _route_result(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array, offsets: Dictionary, ignore_people: bool, distance_only: bool) -> Dictionary:
	return self.navigation._route_result(world,actor_id,floor_id,target,members,offsets,ignore_people,distance_only)

func travel_quote(world: WorldState, actor_id: String, floor_id: int, target: Array) -> Dictionary:
	return self.navigation.travel_quote(world,actor_id,floor_id,target)

func request_move(world: WorldState, actor_id: String, floor_id: int, target: Array) -> String:
	return self.movement.request_move(world,actor_id,floor_id,target)

func at(world: WorldState, actor_id: String, floor_id: int, target: Array) -> bool:
	var location: Dictionary = world.facts.actors[actor_id].location
	return location.kind == "floor" and int(location.floor_id) == floor_id and Vector2(float(location.cell[0]),float(location.cell[1])).distance_to(Vector2(float(target[0]),float(target[1]))) < 0.001

func request_group_move(world: WorldState, primary_id: String, members: Array, offsets: Dictionary, floor_id: int, target: Array) -> String:
	return self.movement.request_group_move(world,primary_id,members,offsets,floor_id,target)

func advance(world: WorldState, present_at_start: int = -1) -> void:
	self.movement.advance(world,present_at_start)

func _floor_route(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2i, goal: Vector2i, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false, navigation: Dictionary = {}, cost_only: bool = false) -> Dictionary:
	return self.navigation._floor_route(world,actor,floor_id,start,goal,members,offsets,ignore_people,navigation,false,cost_only)

func _route_envelope(world: WorldState, actor: Dictionary, members: Array, offsets: Dictionary) -> Array:
	return self.navigation._route_envelope(world,actor,members,offsets)

func _unit_step_dynamic_clear(world: WorldState, actor: Dictionary, floor_id: int, from: Vector2i, to: Vector2i, members: Array, offsets: Dictionary) -> bool:
	var unit_ids: Array = [actor.id]
	for member_id: String in members:
		if member_id!=actor.id:
			unit_ids.append(member_id)
	var actual_floor_start: bool = actor.location.kind=="floor" and int(actor.location.floor_id)==floor_id
	var start_origin: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1])) if actual_floor_start else Vector2.ZERO
	var start_cell: Vector2i = Vector2i(roundi(start_origin.x),roundi(start_origin.y))
	for id: String in unit_ids:
		var offset: Vector2 = Vector2.ZERO
		if id!=actor.id:
			var raw_offset: Array = offsets.get(id,[0,0])
			offset = Vector2(float(raw_offset[0]),float(raw_offset[1]))
		var member: Dictionary = world.facts.actors[id]
		var from_origin: Vector2 = start_origin if actual_floor_start and from==start_cell else Vector2(from)
		var from_rect: Rect2 = _actor_rect(member,from_origin+offset)
		var to_rect: Rect2 = _actor_rect(member,Vector2(to)+offset)
		if not _dynamic_clear(world,actor.id,floor_id,from_rect.merge(to_rect),members):
			return false
	return true

func queue_waypoint(world: WorldState, movement: Dictionary, floor_id: int, cell: Array) -> void:
	self.movement.queue_waypoint(world,movement,floor_id,cell)

func _actor_rect(actor: Dictionary, origin: Vector2) -> Rect2:
	var posture: String = actor.get("posture","standing")
	var binding: String = actor.get("body_binding_id","")
	var facing: float = float(actor.facing)
	var shape: Dictionary = _actor_shapes.get(actor.id,{})
	if shape.is_empty() or shape.species_id!=actor.species_id or shape.binding!=binding or shape.posture!=posture or shape.facing!=facing:
		var token: int = int(shape.get("token",0))
		if shape.is_empty() or shape.species_id!=actor.species_id or shape.binding!=binding or shape.posture!=posture:
			_envelope_next += 1
			token = _envelope_next
		var dimensions: Dictionary = body(actor)
		var cells: int = ceili(maxf(float(dimensions.width_m),float(dimensions.depth_m))/CELL_METERS)
		shape = {"species_id":actor.species_id,"binding":binding,"posture":posture,"facing":facing,"token":token}
		if posture=="lying":
			shape.center = Vector2.ONE*cells*0.5
			var low: Vector2 = Vector2(INF,INF)
			var high: Vector2 = Vector2(-INF,-INF)
			for x: float in [-float(dimensions.width_m)*0.5,float(dimensions.width_m)*0.5]:
				for z: float in [-float(dimensions.height_m),0.0]:
					var point: Vector2 = Vector2(x*cos(facing)+z*sin(facing),-x*sin(facing)+z*cos(facing))/CELL_METERS
					low = low.min(point)
					high = high.max(point)
			shape.offset = -low
			shape.size = high-low
		else:
			var size: Vector2 = Vector2(float(dimensions.width_m),float(dimensions.depth_m))/CELL_METERS
			var cosine: float = absf(cos(facing))
			var sine: float = absf(sin(facing))
			shape.size = Vector2(size.x*cosine+size.y*sine,size.x*sine+size.y*cosine)
			shape.offset = (Vector2.ONE*cells-shape.size)*0.5
		_actor_shapes[actor.id] = shape
	if posture=="lying":
		return Rect2(origin+shape.center-shape.offset,shape.size)
	return Rect2(origin+shape.offset,shape.size)

func overlaps_facility(world: WorldState, actor_id: String, facility_id: String) -> bool:
	var actor: Dictionary = world.facts.actors[actor_id]
	var facility: Dictionary = facility_layout(world,facility_id)
	if actor.location.kind != "floor" or int(actor.location.floor_id)!=int(facility.floor_id):
		return false
	return _actor_rect(actor,Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))).intersects(Rect2(float(facility.cell[0]),float(facility.cell[1]),float(facility.footprint[0]),float(facility.footprint[1])),false)

func body_rectangle(actor: Dictionary) -> Rect2:
	return _actor_rect(actor,Vector2(float(actor.location.cell[0]),float(actor.location.cell[1])))

func _unit_rect(world: WorldState, actor: Dictionary, origin: Vector2, members: Array, offsets: Dictionary) -> Rect2:
	var rect: Rect2 = _actor_rect(actor,origin)
	for member_id: String in members:
		if member_id != actor.id:
			var offset: Array = offsets[member_id]
			rect = rect.merge(_actor_rect(world.facts.actors[member_id],origin+Vector2(float(offset[0]),float(offset[1]))))
	return rect

func _build_reservation_view(world: WorldState) -> Dictionary:
	query_counts.reservation_index_builds += 1
	var view: Dictionary = {"index":BodyIndex.new(),"regions":{},"reservation_keys":{}}
	for id: String in world.facts.adaptations: _index_reservation(view,id,world.facts.adaptations[id])
	return view

func reservation_view(world: WorldState) -> Dictionary:
	var key: int = world.get_instance_id()
	var cached: Dictionary = _reservation_views.get(key,{})
	if cached.is_empty() or not is_same(cached.source,world.facts.adaptations) or int(cached.revision)!=world.geometry_revision:
		for id: int in _reservation_views.keys():
			if _reservation_views[id].world.get_ref()==null: _reservation_views.erase(id)
		cached = {"world":weakref(world),"source":world.facts.adaptations,"revision":world.geometry_revision,"view":_build_reservation_view(world)}
		_reservation_views[key] = cached
	return cached.view

func reservation_changed(world: WorldState, id: String) -> void:
	var cached: Dictionary = _reservation_views.get(world.get_instance_id(),{})
	if not cached.is_empty(): _index_reservation(cached.view,id,world.facts.adaptations.get(id,{}))

func movement_doors(world: WorldState, actor: Dictionary, swept: Rect2, members: Array = [], floor_id: int = 0) -> Array[Dictionary]:
	if floor_id==0: floor_id = int(actor.location.floor_id)
	var key: String = str(world.get_instance_id())+":"+str(floor_id)
	var version: int = _navigation.floor_version(self,world,floor_id)
	var entry: Dictionary = _door_views.get(key,{})
	if entry.is_empty() or entry.version!=version:
		for old: String in _door_views.keys():
			if _door_views[old].world.get_ref()==null: _door_views.erase(old)
		entry = {"world":weakref(world),"version":version,"index":BodyIndex.new(),"doors":{},"order":{}}
		for door: Dictionary in world.facts.floors.overrides.get(str(floor_id),{}).get("doors",[]):
			entry.order[door.id] = entry.doors.size()
			entry.doors[door.id] = door
			entry.index.update(door.id,floor_id,_door_rect(door,int(door.span)))
		_door_views[key] = entry
	var ids: Dictionary = {}
	# A door may grow from its fixed anchor to fit this body's envelope.
	var reach: float = float(clearance(actor))+1.0
	for id: String in members: reach = maxf(reach,float(clearance(world.facts.actors[id]))+1.0)
	for id: String in entry.index.candidates(floor_id,swept.grow(reach)): ids[id] = true
	for region: Dictionary in _reservation_regions(world,floor_id,swept):
		if region.reservation.kind=="door" and entry.doors.has(region.reservation_id): ids[region.reservation_id] = true
	var ordered: Array = ids.keys()
	ordered.sort_custom(func(a: String,b: String) -> bool: return int(entry.order[a])<int(entry.order[b]))
	var result: Array[Dictionary] = []
	var actual: Array = world.facts.floors.overrides.get(str(floor_id),{}).get("doors",[])
	for id: String in ordered: result.append(actual[int(entry.order[id])])
	query_counts.door_candidates += result.size()
	return result

func _index_reservation(view: Dictionary, id: String, reservation: Dictionary) -> void:
	query_counts.reservation_index_updates += 1
	for key: String in view.reservation_keys.get(id,[]):
		view.index.remove(key)
		view.regions.erase(key)
	if reservation.is_empty():
		view.reservation_keys.erase(id)
		return
	var keys: Array = []
	for ordinal: int in reservation.get("regions",[]).size():
		var area: Array = reservation.regions[ordinal]
		var rect: Rect2 = Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3]))
		var key: String = id+":"+str(ordinal)
		view.index.update(key,int(reservation.floor_id),rect)
		view.regions[key] = {"reservation":reservation,"reservation_id":id,"rect":rect}
		keys.append(key)
	view.reservation_keys[id] = keys

func _reservation_regions(world: WorldState, floor_id: int, rect: Rect2) -> Array:
	if world.facts.adaptations.is_empty(): return []
	query_counts.reservation_candidate_queries += 1
	var view: Dictionary = reservation_view(world)
	var regions: Array = []
	for key: String in view.index.candidates(floor_id,rect): regions.append(view.regions[key])
	return regions

func _dynamic_clear(world: WorldState, actor_id: String, floor_id: int, rect: Rect2, members: Array = []) -> bool:
	_ensure_actor_index(world)
	for region: Dictionary in _reservation_regions(world,floor_id,rect):
		var reservation: Dictionary = region.reservation
		if int(reservation.floor_id)!=floor_id or actor_id==reservation.actor_id or actor_id in reservation.get("staff_ids",[]) or reservation.actor_id in members:
			continue
		if rect.intersects(region.rect,false):
			return false
	if _actor_index.intersects(floor_id,rect,actor_id,members):
		return false
	if movement._sweep_index.intersects(floor_id,rect,actor_id,members):
		return false
	return true

func facility_layout(world: WorldState, facility_id: String) -> Dictionary:
	var facility: Dictionary = world.facts.facilities[facility_id]
	var layout: Dictionary = facility.duplicate()
	var reservation: Dictionary = world.facts.adaptations.get(facility_id,{})
	for field: String in ["footprint","patient_cell","operator_cells","repair_cell"]:
		if reservation.has(field):
			layout[field] = reservation[field]
	return layout

func facility_travel_lower_bound_ticks(world: WorldState, facility_id: String, actor_id: String) -> int:
	if not world.facts.facilities.has(facility_id) or not world.facts.actors.has(actor_id): return 0
	var actor: Dictionary = world.facts.actors[actor_id]
	if actor.location.kind!="floor": return 0
	var dimensions: Dictionary = body(actor)
	var longest: float = 0.0
	for axis: String in ["width_m","depth_m","height_m"]:
		var extent: Variant = dimensions.get(axis)
		if not (extent is int or extent is float) or not is_finite(float(extent)) or float(extent)<=0.0: return 0
		longest = maxf(longest,float(extent))
	var k: int = clearance(actor)
	var speed: Variant = content.balance.get("movement_speeds",{}).get(str(k))
	if not (speed is int or speed is float) or not is_finite(float(speed)) or float(speed)<=0.0: return 0
	var facility: Dictionary = world.facts.facilities[facility_id]
	var layout: Dictionary = facility_layout(world,facility_id)
	for point: Variant in [actor.location.get("cell"),facility.get("cell"),facility.get("footprint"),layout.get("footprint"),facility.get("patient_cell"),layout.get("patient_cell")]:
		if not point is Array or point.size()!=2: return 0
		for coordinate: Variant in point:
			if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)): return 0
	var maximum: int = ceili(longest/CELL_METERS)
	var width: int = maxi(maxi(int(facility.footprint[0]),int(layout.footprint[0])),maximum)
	var depth: int = maxi(maxi(int(facility.footprint[1]),int(layout.footprint[1])),maximum)
	var x: int = int(facility.cell[0])
	var y: int = int(facility.cell[1])
	# Include custom/base/current targets and every rotated adapted front.
	# route() truncates targets and rounds its start; use the same grid here.
	var low: Vector2i = Vector2i(x-k,y-k).min(Vector2i(int(facility.patient_cell[0]),int(facility.patient_cell[1]))).min(Vector2i(int(layout.patient_cell[0]),int(layout.patient_cell[1])))
	var high: Vector2i = Vector2i(x+width,y+depth).max(Vector2i(int(facility.patient_cell[0]),int(facility.patient_cell[1]))).max(Vector2i(int(layout.patient_cell[0]),int(layout.patient_cell[1])))
	var start: Vector2i = Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1]))
	var distance: int = maxi(maxi(low.x-start.x,start.x-high.x),0)+maxi(maxi(low.y-start.y,start.y-high.y),0)
	# Floor edges are orthogonal and connectors retain their anchor XY. Stub,
	# boarding, waiting and vertical travel only add nonnegative time.
	return HospitalTransit.walking_ticks(self,actor,[],float(distance))

func support_anchor(world: WorldState, facility_id: String) -> Vector3:
	var facility: Dictionary = world.facts.facilities[facility_id]
	var layout: Dictionary = facility_layout(world,facility_id)
	var asset: Dictionary = content._assets.get(facility.definition_id,{})
	if not asset.get("anchors_engine_local_m",{}).has("patient_support"):
		var definition: Dictionary = content.facility_definition(facility.definition_id)
		var profile: Dictionary = content.definition("facility_fit_profiles",str(definition.get("fit_profile_id","")))
		var height: float = float(definition.get("support_height_m",0.9 if profile.get("pose","")=="reclined" else 0.45))
		return Vector3(float(layout.footprint[0])*CELL_METERS*0.5,height,float(layout.footprint[1])*CELL_METERS*0.5)
	var anchor: Vector3 = content.asset_anchor(facility.definition_id,"patient_support")
	anchor += Vector3(float(layout.footprint[0])-float(facility.footprint[0]),0,float(layout.footprint[1])-float(facility.footprint[1]))*CELL_METERS*0.5
	return anchor

func support_location(world: WorldState, actor: Dictionary, facility: Dictionary) -> Dictionary:
	var anchor: Vector3 = support_anchor(world,facility.id)
	var dimensions: Dictionary = content.actor_body(actor)
	var center: float = float(clearance(actor))*0.5
	return {"kind":"floor","floor_id":int(facility.floor_id),"cell":[float(facility.cell[0])+anchor.x/CELL_METERS-center,float(facility.cell[1])+(anchor.z+float(dimensions.height_m)*0.5)/CELL_METERS-center],"height_m":anchor.y+float(dimensions.depth_m)*0.5}

func support_exit_ticks(actor: Dictionary, facility: Dictionary, until_clear: bool = false) -> int:
	# The same straight support-exit movement and speed as advance(). This is
	# a forecast of known geometry, never a movement of the actual actor.
	var start: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	var target: Vector2 = Vector2(float(facility.patient_cell[0]),float(facility.patient_cell[1]))
	var speed: float = float(content.balance.movement_speeds[str(clearance(actor))])*WorldState.TICK_SECONDS
	var ticks: int = maxi(1,ceili(start.distance_to(target)/speed))
	if not until_clear: return ticks
	var rectangle: Rect2 = Rect2(float(facility.cell[0]),float(facility.cell[1]),float(facility.footprint[0]),float(facility.footprint[1]))
	if not body_rectangle(actor).intersects(rectangle,false): return 0
	var moving: Dictionary = actor.duplicate()
	moving.location = actor.location.duplicate()
	for elapsed: int in range(1,ticks+1):
		var next: Vector2 = start.move_toward(target,speed*elapsed)
		moving.facing = atan2(target.x-start.x,target.y-start.y)
		moving.location.cell = [next.x,next.y]
		if elapsed==ticks: moving.posture = "standing"
		if not body_rectangle(moving).intersects(rectangle,false): return elapsed
	return ticks

func facility_quote(world: WorldState, facility_id: String, actor_id: String, staff_ids: Array = []) -> Dictionary:
	return _facility_quote(world,facility_id,actor_id,staff_ids,false)

# Check the exact layout, handoff and current occupancy before arrival routing.
# This does not prove other actors' exits or authorize a reservation; a complete
# facility_quote is still required after the arrival routes succeed.
func facility_preflight_quote(world: WorldState, facility_id: String, actor_id: String, staff_ids: Array = []) -> Dictionary:
	return _facility_quote(world,facility_id,actor_id,staff_ids,false,false)

# Read only built geometry and body dimensions. This grants no occupancy or
# route: actual arrival must still pass the complete facility_quote.
func facility_geometry_quote(world: WorldState, facility_id: String, actor_id: String, staff_ids: Array = []) -> Dictionary:
	return _facility_quote(world,facility_id,actor_id,staff_ids,true)

func _facility_quote(world: WorldState, facility_id: String, actor_id: String, staff_ids: Array, geometry_only: bool, prove_exits: bool = true) -> Dictionary:
	if not world.facts.facilities.has(facility_id) or not world.facts.actors.has(actor_id):
		return {"ok":false,"reason":"设备或实际使用者不存在"}
	var bed_owner: Dictionary = world.facts.get("staff_life",{}).get("personal_beds",{}).get(facility_id,{})
	if not bed_owner.is_empty() and bed_owner.staff_id!=actor_id: return {"ok":false,"reason":"他人个人床"}
	var facility: Dictionary = world.facts.facilities[facility_id]
	var actor: Dictionary = world.facts.actors[actor_id]
	var reference: Dictionary = _route_queries.back().reference if not _route_queries.is_empty() and _route_queries.back().world==world else {}
	if geometry_only: reference = {"fits":{}}
	var reference_key: String = ""
	if not reference.is_empty():
		var bodies: Array = [body(actor)]
		for staff_id: String in staff_ids:
			bodies.append(body(world.facts.actors[staff_id]))
		reference_key = JSON.stringify([facility_id,bodies])
		if reference.fits.has(reference_key):
			var saved: Dictionary = reference.fits[reference_key].duplicate(true)
			saved.actor_id = actor_id
			saved.staff_ids = staff_ids.duplicate()
			return saved
	var current: Dictionary = world.facts.adaptations.get(facility_id,{})
	if reference.is_empty() and facility.definition_id=="FUR02" and not current.is_empty() and current.get("staff_ids",[])!=staff_ids:
		var room: Dictionary = world.facts.rooms.get(facility.get("room_id",""),{})
		for previous_id: String in current.get("staff_ids",[]):
			if previous_id in staff_ids:
				continue
			var previous: Dictionary = world.facts.actors[previous_id]
			if previous.location.kind=="floor" and int(previous.location.floor_id)==int(facility.floor_id) and not room.is_empty() and room_contains(room,body_rectangle(previous)):
				return {"ok":false,"reason":"等待原医生沿实际路线离开诊室后交接岗位"}
	var definition: Dictionary = content.facility_definition(facility.definition_id)
	if definition.is_empty():
		return {"ok":false,"reason":"设备适配定义缺失"}
	var profile: Dictionary = content.definition("facility_fit_profiles",str(definition.get("fit_profile_id","")))
	if not definition.has("adapter_capacity") and profile.is_empty():
		return {"ok":true,"unchanged":true}
	var dimensions: Dictionary = body(actor)
	var capacity: Dictionary = definition.get("adapter_capacity",definition)
	if clearance(actor)>int(capacity.get("max_clearance_cells",96)) or float(dimensions.height_m)>float(capacity.get("max_height_m",INF)):
		return {"ok":false,"reason":"身体超过设备实际适配能力"}
	var reclined: bool = profile.get("pose","")=="reclined" or facility.definition_id in ["EQ01","EQ05"]
	var depth: float = maxf(float(dimensions.depth_m),float(dimensions.height_m)) if reclined else float(dimensions.depth_m)
	var turns: int = posmod(int(facility.get("rotation",0)),4)
	var width_cells: int = ceili(float(dimensions.width_m)/CELL_METERS)
	var depth_cells: int = ceili(depth/CELL_METERS)
	var footprint: Array = facility.footprint.duplicate()
	var stretching_bed: bool = profile.get("kind","")=="bed" and profile.get("extent_rule","")=="max_base_and_reclined_body"
	if stretching_bed:
		footprint = [maxi(int(facility.footprint[0]),depth_cells if turns%2==1 else width_cells),maxi(int(facility.footprint[1]),width_cells if turns%2==1 else depth_cells)]
	if profile.get("extent_rule","")=="base_with_real_operator_areas":
		footprint = facility.footprint.duplicate()
	if footprint==facility.footprint and profile.is_empty():
		return {"ok":true,"unchanged":true}
	var x: int = int(facility.cell[0])
	var y: int = int(facility.cell[1])
	var w: int = int(footprint[0])
	var h: int = int(footprint[1])
	var patient_cell: Array = facility.get("patient_cell",[x,y+h]).duplicate()
	var operators: Array = facility.get("operator_cells",[]).duplicate(true)
	var repair: Array = facility.get("repair_cell",[x-1,y]).duplicate()
	if footprint!=facility.footprint:
		patient_cell = _adapted_front(facility,footprint,clearance(actor))
		operators.clear()
	for index: int in staff_ids.size():
		if not world.facts.actors.has(staff_ids[index]):
			return {"ok":false,"reason":"操作岗位缺少实际人员"}
		if index>=operators.size():
			var staff_size: int = clearance(world.facts.actors[staff_ids[index]])
			if facility.definition_id=="EQ05" and operators.is_empty():
				# Care and the final round use one bedside place in sequence. An
				# expanded bed needs a place clear for both actual staff bodies.
				for participant_id: String in staff_ids:
					if not world.facts.actors.has(participant_id):
						return {"ok":false,"reason":"操作岗位缺少实际人员"}
					staff_size = maxi(staff_size,clearance(world.facts.actors[participant_id]))
				match turns:
					1: operators.append([x+w-1-staff_size,y-staff_size])
					2: operators.append([x+w,y+h-1-staff_size])
					3: operators.append([x+1,y+h])
					_: operators.append([x-staff_size,y+1])
			elif facility.definition_id=="EQ05" and index==1 and operators.size()==1:
				operators.append(operators[0].duplicate())
			else:
				operators.append([x-staff_size,y+1] if index==0 else [x+w,y if index==1 else y+h-staff_size])
	var regions: Array = [[x,y,w,h],[patient_cell[0],patient_cell[1],clearance(actor),clearance(actor)],[repair[0],repair[1],1,1]]
	for index: int in staff_ids.size():
		var k: int = clearance(world.facts.actors[staff_ids[index]])
		regions.append([operators[index][0],operators[index][1],k,k])
	var allowed: Array = [actor_id]+staff_ids
	var room: Dictionary = world.facts.rooms.get(facility.get("room_id",""),{})
	var static_regions: Dictionary = read_view(world,"facility_region_geometry:"+facility_id,func()->Dictionary: return {})
	for area: Array in regions:
		var rect: Rect2 = Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3]))
		var region_key: String = JSON.stringify(area,"",true,true)
		if not static_regions.has(region_key): static_regions[region_key] = _facility_region_reason(world,facility,room,area,rect)
		var static_reason: String = static_regions[region_key]
		if not static_reason.is_empty(): return {"ok":false,"reason":static_reason}
		if reference.is_empty():
			var other_actor: String = _blocking_actor(world,int(facility.floor_id),rect,allowed)
			if not other_actor.is_empty(): return {"ok":false,"reason":"展开或操作区域有实际身体："+other_actor}
			if not _dynamic_clear(world,actor_id,int(facility.floor_id),rect,allowed):
				return {"ok":false,"reason":"展开区域与已有实际预约相交"}
	var quote: Dictionary = {"ok":true,"kind":"facility","facility_id":facility_id,"actor_id":actor_id,"staff_ids":staff_ids.duplicate(),"floor_id":facility.floor_id,
		"footprint":footprint,"patient_cell":patient_cell,"operator_cells":operators,"repair_cell":repair,"regions":regions}
	# Nominal capacity proves built geometry and bodies. Occupancy, reservations
	# and preservation of each real actor's exit belong to actual service start.
	if not reference.is_empty():
		reference.fits[reference_key] = quote
		return quote
	if not prove_exits or not stretching_bed: return quote
	return _facility_exit_quote(world,facility_id,actor_id,staff_ids,quote)

# Built geometry is fixed within the owning read-only query scope. Dynamic
# bodies and reservation permissions still run in the original region order.
func _facility_region_reason(world: WorldState, facility: Dictionary, room: Dictionary, area: Array, rect: Rect2) -> String:
	for cx: int in range(int(area[0]),int(area[0])+int(area[2])):
		for cy: int in range(int(area[1]),int(area[1])+int(area[3])):
			if not owned(world,int(facility.floor_id),Vector2i(cx,cy)) or [cx,cy] in world.facts.floors.overrides.get(str(facility.floor_id),{}).get("blocked",[]):
				return "展开或退出区域受墙、地块阻挡：%d,%d" % [cx,cy]
	if not room.is_empty() and not room_contains(room,rect): return "展开、岗位或出口超出本房间"
	var other: String = _blocking_facility(world,int(facility.floor_id),rect,str(facility.id))
	return "" if other.is_empty() else "展开区域有其他实际设施："+other

# Continuation of a preflight in the same synchronous read-only enumeration.
# Actual reserve_facility always calls facility_quote and repeats full preflight.
func _facility_exit_quote(world: WorldState, facility_id: String, actor_id: String, staff_ids: Array, quote: Dictionary) -> Dictionary:
	if not quote.ok or quote.get("unchanged",false) or nominal_query(world): return quote
	var definition: Dictionary = content.facility_definition(world.facts.facilities[facility_id].definition_id)
	var profile: Dictionary = content.definition("facility_fit_profiles",str(definition.get("fit_profile_id","")))
	if profile.get("kind","")!="bed" or profile.get("extent_rule","")!="max_base_and_reclined_body": return quote
	var facility: Dictionary = world.facts.facilities[facility_id]
	var current: Dictionary = world.facts.adaptations.get(facility_id,{})
	var footprint: Array = quote.footprint
	var regions: Array = quote.regions
	var allowed: Array = [actor_id]+staff_ids
	var same_reservation: bool = current.get("kind","")=="facility" and current.get("actor_id","")==actor_id and current.get("staff_ids",[])==staff_ids
	for field: String in ["floor_id","footprint","patient_cell","operator_cells","repair_cell","regions"]:
		same_reservation = same_reservation and current.get(field)!=null and current[field]==quote[field]
	# All current fit/occupancy checks above still run. An identical reservation
	# cannot newly cut another actor's exit: the candidate changes no geometry.
	if same_reservation: return quote
	var candidate: WorldState
	var previous_footprint: Array = facility_layout(world,facility_id).footprint
	var same_footprint: bool = footprint==previous_footprint
	var expands: bool = int(footprint[0])>=int(previous_footprint[0]) and int(footprint[1])>=int(previous_footprint[1])
	var candidate_source: Dictionary = {}
	var geometries: Dictionary = {}
	for other: Dictionary in world.facts.actors.values():
		if other.id in allowed or other.location.kind!="floor" or int(other.location.floor_id)!=int(facility.floor_id):
			continue
		var start: Vector2i = Vector2i(roundi(other.location.cell[0]),roundi(other.location.cell[1]))
		var target: Array = exit_cell(world,other,int(facility.floor_id))
		var exit: Vector2i = Vector2i(int(target[0]),int(target[1]))
		var before: Dictionary = _exit_witness(world,other,int(facility.floor_id),start,exit)
		if not before.ok:
			continue
		if same_footprint and _route_avoids_regions(before,regions):
			continue
		if candidate==null:
			var facts: Dictionary = world.facts.duplicate()
			facts.adaptations = world.facts.adaptations.duplicate()
			candidate = WorldState.new(facts)
			candidate.facts.adaptations[facility_id] = quote
		var navigation: Dictionary = {}
		if expands:
			# Expansion can only remove routes. Search the original graph with
			# all candidate nodes/edges checked, without replacing the shared
			# live graph for each hypothetical fit. Shrinkage uses a fresh graph.
			navigation = _navigation.query_graphs(self,world,int(facility.floor_id),other,[],{})
			var geometry: RouteClearance = navigation.graph.geometry
			if not same_footprint:
				var id: int = geometry.get_instance_id()
				if not geometries.has(id):
					if candidate_source.is_empty(): candidate_source = RouteClearance.capture_source(self,candidate,int(facility.floor_id))
					begin_route_query(candidate)
					geometries[id] = RouteClearance.new(self,candidate,other,int(facility.floor_id),[],{},false,candidate_source)
					end_route_query()
				geometry = geometries[id]
			navigation.query = RouteClearance.new(self,candidate,other,int(facility.floor_id),[],{},true,geometry.source,geometry)
			navigation.overlay = not same_footprint
		if not _floor_route(candidate,other,int(facility.floor_id),start,exit,[],{},true,navigation,true).ok:
			return {"ok":false,"reason":"展开会切断在院角色的安全出口："+str(other.id)}
	return quote

func _exit_witness(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2i, exit: Vector2i) -> Dictionary:
	# Exit proofs may use any complete legal path. Actual movement keeps its
	# original path selection and FIFO; proposed reservations still get checked.
	var exits: Dictionary = {}
	var key: String = ""
	if not _route_queries.is_empty() and _route_queries.back().world==world:
		exits = _route_queries.back().exits
		key = JSON.stringify([actor.id,floor_id,start.x,start.y,exit.x,exit.y])
		if exits.has(key): return exits[key]
	var result: Dictionary = _navigation.travel_distance(self,world,floor_id,actor,start,exit,true)
	if not result.ready: result = _floor_route(world,actor,floor_id,start,exit,[],{},true)
	if result.ok:
		var size: int = clearance(actor)
		var previous: Rect2 = Rect2(Vector2(start),Vector2.ONE*size)
		var bounds: Rect2 = previous
		var sweeps: Array[Rect2] = [previous]
		var direction: Vector2 = Vector2.ZERO
		for segment: Dictionary in result.path:
			var current: Rect2 = Rect2(Vector2(float(segment.cell[0]),float(segment.cell[1])),Vector2.ONE*size)
			var step: Vector2 = current.position-previous.position
			if step==direction: sweeps[-1] = sweeps[-1].merge(current)
			else: sweeps.append(previous.merge(current))
			direction = step
			bounds = bounds.merge(current)
			previous = current
		result.bounds = bounds
		result.sweeps = sweeps
	if not key.is_empty(): exits[key] = result
	return result

func _route_avoids_regions(witness: Dictionary, regions: Array) -> bool:
	for area: Array in regions:
		var obstacle: Rect2 = Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3]))
		if not witness.bounds.intersects(obstacle,false): continue
		for sweep: Rect2 in witness.sweeps:
			if sweep.intersects(obstacle,false): return false
	return true

func _adapted_front(facility: Dictionary, footprint: Array, k: int) -> Array:
	var x: int = int(facility.cell[0])
	var y: int = int(facility.cell[1])
	match posmod(int(facility.get("rotation",0)),4):
		1: return [x-k,y]
		2: return [x+maxi(0,int(footprint[0])-k),y-k]
		3: return [x+int(footprint[0]),y+maxi(0,int(footprint[1])-k)]
	return [x,y+int(footprint[1])]

func room_contains(room: Dictionary, rect: Rect2) -> bool:
	if not room.has("cells"):
		return Rect2(float(room.origin[0]),float(room.origin[1]),float(room.size[0]),float(room.size[1])).encloses(rect)
	for x: int in range(floori(rect.position.x),ceili(rect.end.x)):
		for y: int in range(floori(rect.position.y),ceili(rect.end.y)):
			if not [x,y] in room.cells:
				return false
	return true

func exit_cell(world: WorldState, actor: Dictionary, floor_id: int = 1) -> Array:
	var target: Array = world.facts.get("entry",{}).get("exit_cell",[47,93]).duplicate()
	if floor_id!=1:
		for id: String in world.ids("connectors"):
			if HospitalTransit.has_stop(world.facts.connectors[id],floor_id):
				return world.facts.connectors[id].anchor.duplicate()
	var k: int = clearance(actor)
	var layout: Dictionary = world.facts.floors.overrides.get(str(floor_id),{})
	for plot: Array in layout.get("plots",[]):
		var origin: Vector2i = Vector2i(int(plot[0])*32,int(plot[1])*32)
		if Rect2i(origin,Vector2i(32,32)).has_point(Vector2i(int(target[0]),int(target[1]))):
			return [clampi(int(target[0]),origin.x,origin.x+32-k),clampi(int(target[1]),origin.y,origin.y+32-k)]
	return target

func facility_reservation_reason(world: WorldState, facility_id: String, actor_id: String) -> String:
	var owner: Dictionary = world.facts.get("staff_life",{}).get("personal_beds",{}).get(facility_id,{})
	if not owner.is_empty() and owner.staff_id!=actor_id: return "他人个人床"
	var current: Dictionary = world.facts.adaptations.get(facility_id,{})
	return "等待原使用者实际离开后收拢" if not current.is_empty() and current.actor_id!=actor_id else ""

func facility_trip_quote(world: WorldState, facility_id: String, actor_id: String, staff_ids: Array = []) -> Dictionary:
	var fit: Dictionary = facility_quote(world,facility_id,actor_id,staff_ids)
	if not fit.ok: return fit
	var layout: Dictionary = facility_layout(world,facility_id)
	var facts: Dictionary = world.facts.duplicate()
	facts.adaptations = world.facts.adaptations.duplicate()
	facts.actors = world.facts.actors.duplicate()
	facts.actors[actor_id] = world.facts.actors[actor_id].duplicate(true)
	var candidate: WorldState = WorldState.new(facts)
	if not fit.get("unchanged",false):
		var adaptation: Dictionary = fit.duplicate(true)
		adaptation.erase("ok")
		adaptation.owner_id = "public_trip_preview"
		candidate.facts.adaptations[facility_id] = adaptation
		layout = facility_layout(candidate,facility_id)
	prepare_projection(world,candidate,[facility_id])
	begin_dynamic_route_query(candidate)
	var forward: Dictionary = _route_result(candidate,actor_id,int(layout.floor_id),layout.patient_cell,[],{},true,true)
	end_route_query()
	if not forward.ok or not forward.has("travel_ticks"): return {"ok":false,"reason":forward.get("reason","实际设施行程无法估计")}
	var origin: Dictionary = world.facts.actors[actor_id].location
	candidate.facts.actors[actor_id].location = {"kind":"floor","floor_id":int(layout.floor_id),"cell":layout.patient_cell.duplicate(),"height_m":0.0}
	sync_actor(candidate,actor_id)
	# This private projection changed only the actor just synchronized above.
	# Discard route/exit views while retaining the now-current body index.
	begin_dynamic_route_query(candidate,false)
	var back: Dictionary = _route_result(candidate,actor_id,int(origin.floor_id),origin.cell,[],{},true,true)
	end_route_query()
	if not back.ok: return {"ok":false,"reason":"设施没有合法返回路线"}
	return {"ok":true,"facility_id":facility_id,"floor_id":int(layout.floor_id),"cell":layout.patient_cell.duplicate(),"patient_cell":layout.patient_cell.duplicate(),"travel_ticks":int(forward.travel_ticks),"fit":fit}

func reserve_facility(world: WorldState, facility_id: String, actor_id: String, owner_id: String, staff_ids: Array = []) -> String:
	var reason: String = facility_reservation_reason(world,facility_id,actor_id)
	if not reason.is_empty():
		return reason
	var current: Dictionary = world.facts.adaptations.get(facility_id,{})
	if not current.is_empty():
		if current.staff_ids==staff_ids:
			current.owner_id = owner_id
			return ""
	var quote: Dictionary = facility_quote(world,facility_id,actor_id,staff_ids)
	if not quote.ok:
		return quote.reason
	if quote.get("unchanged",false):
		return ""
	quote.erase("ok")
	quote.owner_id = owner_id
	var before: Dictionary = facility_layout(world,facility_id)
	world.facts.adaptations[facility_id] = quote
	reservation_changed(world,facility_id)
	_navigation.invalidate(world,int(quote.floor_id))
	public_areas.facility_changed(before,quote)
	return ""

func commit_facility_reservations(world: WorldState, validated: Dictionary, facility_ids: Array) -> void:
	# The complete bundle was checked on a clone in this synchronous command.
	# Publish only its facility reservations; no world or service state is copied.
	for facility_id: String in facility_ids:
		if validated.has(facility_id):
			var before: Dictionary = facility_layout(world,facility_id)
			world.facts.adaptations[facility_id] = validated[facility_id].duplicate(true)
			reservation_changed(world,facility_id)
			_navigation.invalidate(world,int(validated[facility_id].floor_id))
			public_areas.facility_changed(before,validated[facility_id])

func grant_facility_access(world: WorldState, facility_id: String, staff_id: String) -> void:
	var reservation: Dictionary = world.facts.adaptations.get(facility_id,{})
	if reservation.is_empty() or staff_id in reservation.staff_ids: return
	reservation.staff_ids.append(staff_id)
	_navigation.invalidate(world,int(reservation.floor_id))

func release_adaptations(world: WorldState) -> void:
	for id: String in world.ids("adaptations"):
		var reservation: Dictionary = world.facts.adaptations[id]
		var actor: Dictionary = world.facts.actors[reservation.actor_id]
		if reservation.kind=="facility" and (world.facts.tickets.has(reservation.owner_id) or world.facts.sessions.has(reservation.owner_id) or world.facts.preparations.has(reservation.owner_id) or world.facts.ward_stays.has(reservation.owner_id) or world.facts.get("staff_life",{}).get("reservations",{}).has(id)):
			continue
		var inside: bool = false
		for participant_id: String in [actor.id]+reservation.staff_ids:
			var participant: Dictionary = world.facts.actors[participant_id]
			for area: Array in reservation.regions:
				if participant.location.kind=="floor" and int(participant.location.floor_id)==int(reservation.floor_id) and body_rectangle(participant).intersects(Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3])),false):
					inside = true
		if not inside:
			world.facts.adaptations.erase(id)
			reservation_changed(world,id)
			_navigation.invalidate(world,int(reservation.floor_id))
			if reservation.kind=="facility" and world.facts.facilities.has(id): public_areas.facility_changed(reservation,world.facts.facilities[id])

func _door_span(actor: Dictionary, door: Dictionary) -> int:
	var dimensions: Dictionary = body(actor)
	return maxi(int(door.span),ceili((maxf(float(dimensions.width_m),float(dimensions.depth_m))+0.1)/CELL_METERS))

func door_quote(world: WorldState, actor: Dictionary, floor_id: int, door: Dictionary, members: Array = []) -> Dictionary:
	var dimensions: Dictionary = body(actor)
	if members.size()>1:
		dimensions = dimensions.duplicate()
		for id: String in members:
			var required: Dictionary = body(world.facts.actors[id])
			for axis: String in ["width_m","depth_m","height_m"]: dimensions[axis] = maxf(float(dimensions[axis]),float(required[axis]))
	var definition: Dictionary = content.definition("doors",door.definition_id)
	var span: int = maxi(int(door.span),ceili((maxf(float(dimensions.width_m),float(dimensions.depth_m))+0.1)/CELL_METERS))
	var height: float = maxf(float(definition.clear_height_m),float(dimensions.height_m)+0.1)
	var ceiling: float = float(content.balance.floors.clear_height_m) if world.facts.floors.has("completed_top_floor") and not floor_plots(world,floor_id).is_empty() else 0.0
	for interval: Dictionary in world.facts.floors.height_intervals:
		if floor_id>=int(interval.first) and floor_id<=int(interval.last):
			ceiling = float(interval.height_m)
	if height>ceiling:
		return {"ok":false,"reason":"门净高超过本层实际净高"}
	var room: Dictionary = world.facts.rooms.get(door.room_id,{})
	if room.is_empty():
		return {"ok":false,"reason":"门缺少实际连续墙段"}
	var opening: Rect2 = _door_rect(door,span)
	var along: int = 0 if door.axis=="x" else 1
	var continuous: bool = false
	if room.has("wall_edges"):
		var door_line: int = int(door.cell[1-along])
		for edge: Dictionary in room.wall_edges:
			if edge.axis==door.axis and int(edge.line)==door_line and int(edge.low)<=int(door.cell[along]) and int(edge.high)>=int(door.cell[along])+span:
				continuous = true
	else:
		continuous = int(door.cell[along])>=int(room.origin[along]) and int(door.cell[along])+span<=int(room.origin[along])+int(room.size[along])
	if not continuous:
		return {"ok":false,"reason":"门展开越过连续墙段或墙角"}
	for other: Dictionary in movement_doors(world,actor,opening,members,floor_id):
		if other.id!=door.id and opening.intersects(_door_rect(other,int(other.span)),false):
			return {"ok":false,"reason":"门展开与另一扇门相交"}
	if not _blocking_facility(world,floor_id,opening).is_empty():
		return {"ok":false,"reason":"门展开区域有实际设施"}
	var k: int = clearance(actor)
	for id: String in members: k = maxi(k,clearance(world.facts.actors[id]))
	var before: Rect2 = Rect2(opening.position-Vector2(0,k),Vector2(span,k)) if door.axis=="x" else Rect2(opening.position-Vector2(k,0),Vector2(k,span))
	var wall_depth: int = 0 if room.has("wall_edges") else 1
	var after: Rect2 = Rect2(opening.position+Vector2(0,wall_depth),Vector2(span,k)) if door.axis=="x" else Rect2(opening.position+Vector2(wall_depth,0),Vector2(k,span))
	for side: Rect2 in [before,after]:
		for cx: int in range(int(side.position.x),int(side.end.x)):
			for cy: int in range(int(side.position.y),int(side.end.y)):
				if not owned(world,floor_id,Vector2i(cx,cy)) or [cx,cy] in world.facts.floors.overrides.get(str(floor_id),{}).get("blocked",[]):
					return {"ok":false,"reason":"门两侧没有容纳真实身体的完整空间"}
		if not _blocking_facility(world,floor_id,side).is_empty():
			return {"ok":false,"reason":"门两侧通路有实际设施"}
	return {"ok":true,"span":span,"clear_height_m":height,"clear_width_m":maxf(float(definition.clear_width_m),maxf(float(dimensions.width_m),float(dimensions.depth_m))+0.1)}

func _door_rect(door: Dictionary, span: int) -> Rect2:
	return Rect2(float(door.cell[0]),float(door.cell[1]),float(span) if door.axis=="x" else 1.0,1.0 if door.axis=="x" else float(span))

func _potential_door_opening(world: WorldState, actor: Dictionary, floor_id: int, cell: Vector2i) -> bool:
	for door: Dictionary in world.facts.floors.overrides.get(str(floor_id),{}).get("doors",[]):
		var fit: Dictionary = door_quote(world,actor,floor_id,door)
		if fit.ok and _door_rect(door,int(fit.span)).has_point(Vector2(cell)):
			return true
	return false
