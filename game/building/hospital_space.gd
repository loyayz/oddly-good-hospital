class_name HospitalSpace
extends RefCounted

signal reservation_updated(world: WorldState, id: String)

const CELL_METERS: float = 1.5
const GuidanceQueueLayout = preload("res://game/operations/guidance_queue_layout.gd")
var content: HospitalContent
var _convoy_owner: Dictionary = {}
var _convoy_members: Dictionary = {}

var _bodies: Dictionary = {}
var _actor_shapes: Dictionary = {}
var _actor_index: BodyIndex = BodyIndex.new()
var _indexed_world: WorldState
var _indexed_facts: Dictionary = {}
var _indexed_revision: int = -1
var _indexed_actor_scope: Dictionary = {}
# Derived traversal profiles, updated by the same physical fact handoffs as
# BodyIndex. Coordinates/counts do not invalidate the profile-set signature.
var _passage_actor_profiles: Dictionary = {}
var _passage_floor_profiles: Dictionary = {}
var _passage_signatures: Dictionary = {}
var _passage_profile_world: WorldState
var _passage_profile_facts: Dictionary = {}
var passage_profile_changes: int = 0
var _navigation: NavigationCache = NavigationCache.new()
var _envelope_next: int = 0
var _route_queries: Array[Dictionary] = []
var _reservation_views: Dictionary = {}
var reservation_revision: int = 0
var _facility_geometry: Dictionary = {}
var guidance_queue_provider: WeakRef
var movement: HospitalMovement
var navigation: HospitalNavigation
var public_areas: HospitalPublicAreas
var room_use: HospitalRoomUse
var query_counts: Dictionary = {"routes":0,"journey_hits":0,"journey_invalidations":0,"transport_builds":0,"transport_searches":0,"candidate_connections":0,"floor_route_hits":0,"floor_route_builds":0,"static_path_hits":0,"static_path_builds":0,"materialized_floor_cells":0,"actor_index_builds":0,"actor_index_actor_visits":0,"reservation_index_builds":0,"reservation_index_updates":0,"door_candidates":0,"movement_candidates":0,"reservation_candidate_queries":0,"route_checks":0,"route_revalidations":0,"route_dispatch_scans":0,"route_dispatch_restores":0,"yield_attempts":0,"yield_candidates":0,"connector_topology_builds":0}

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
	_route_queries.append({"world":world,"routes":{},"exits":{},"views":{},"reference":{},"journeys_allowed":false,"dynamic":true,"transport":{}})
	_ensure_actor_index(world)

func in_dynamic_route_query(world: WorldState) -> bool:
	return not _route_queries.is_empty() and _route_queries.back().world==world and _route_queries.back().get("dynamic",false)

func begin_actor_exclusion_query(source: WorldState, projected: WorldState, excluded_ids: Array) -> void:
	# This projection owns only departures: the listed private actor records
	# are outside, and every other actor record is shared with the source.
	# An independent caller still refreshes raw input before borrowing bodies.
	if _route_queries.is_empty() or _route_queries.back().world!=source: _indexed_revision = -1
	_ensure_actor_index(source)
	begin_route_query(projected,{},false)
	var query: Dictionary = _route_queries.back()
	query.actor_source = source
	query.actor_source_facts = source.facts
	query.actor_projection_facts = projected.facts
	query.actor_source_revision = source.revision
	query.actor_projection_revision = projected.revision
	query.actor_exclusions = excluded_ids.duplicate()

func _actor_exclusion_scope(world: WorldState) -> Dictionary:
	if _indexed_world==world: return {}
	for number: int in range(_route_queries.size()-1,-1,-1):
		var query: Dictionary = _route_queries[number]
		if query.world!=world or not query.has("actor_source"): continue
		var source: WorldState = query.actor_source
		if _indexed_world==source and is_same(_indexed_facts,source.facts) and is_same(query.actor_source_facts,source.facts) and is_same(query.actor_projection_facts,world.facts) and _indexed_revision==int(query.actor_source_revision) and source.revision==int(query.actor_source_revision) and world.revision==int(query.actor_projection_revision): return query
	return {}

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

# Optional geometry is borrowed only within one synchronous call for the same
# world and floor; never retain it across world mutations or query boundaries.
func _blocking_facility(world: WorldState, floor_id: int, rect: Rect2, except_id: String = "", geometry: FloorStaticGeometry = null) -> String:
	var index: BodyIndex = _navigation.facility_index(self,world,floor_id) if geometry==null else geometry.facility_index
	var hits: Array[String] = index.candidates(floor_id,rect,[except_id])
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
		var projection: Dictionary = _actor_exclusion_scope(world)
		var ignored: Array = allowed if projection.is_empty() else allowed+projection.actor_exclusions
		var hits: Array[String] = _actor_index.candidates(floor_id,rect,ignored)
		return "" if hits.is_empty() else hits[0]
	for actor: Dictionary in world.facts.actors.values():
		if not actor.id in allowed and actor.location.kind=="floor" and int(actor.location.floor_id)==floor_id and rect.intersects(body_rectangle(actor),false): return actor.id
	return ""

func _init(database: HospitalContent) -> void:
	content = database
	room_use = HospitalRoomUse.new(database)
	movement = HospitalMovement.new(self)
	navigation = HospitalNavigation.new(self)
	public_areas = HospitalPublicAreas.new(self)
	var cells: Array = content.balance.pathfinding.local_updates.chunk_cells
	_actor_index = BodyIndex.new(Vector2(float(cells[0]),float(cells[1])))

func body(actor: Dictionary) -> Dictionary:
	if actor.has("_convoy_body"): return actor._convoy_body
	var key: String = str(actor.species_id)+":"+str(actor.get("body_binding_id",""))
	if not _bodies.has(key):
		_bodies[key] = content.actor_body(actor)
	return _bodies[key]

func _ensure_actor_index(world: WorldState) -> void:
	# A facts replacement may preserve the numeric revision (restore/projection).
	# Cached bodies belong to the exact facts owner, not just world/revision.
	var same_facts: bool = is_same(_indexed_facts,world.facts)
	# An existing binding belongs to an active read-only scope; popping that
	# scope clears it. Equal source/revision needs no repeated owner lookup.
	if world==_indexed_world and same_facts and world.revision==_indexed_revision and (not _indexed_actor_scope.is_empty() or _route_queries.is_empty()): return
	if not _actor_exclusion_scope(world).is_empty(): return
	var scope: Dictionary = _actor_index_scope(world)
	if world==_indexed_world and same_facts and world.revision==_indexed_revision:
		_indexed_actor_scope = scope
		return
	# A sealed read-only enumeration may alternate reservation projections
	# with the exact same actors collection. Its active scope owns this reuse;
	# crossing scope/world boundaries retains the original rebuild behavior.
	var shared: bool = world!=_indexed_world and _indexed_world!=null and is_same(_indexed_facts,_indexed_world.facts) and _indexed_revision>=0 and not scope.is_empty() and is_same(scope,_indexed_actor_scope) and is_same(world.facts.actors,_indexed_world.facts.actors)
	if world!=_indexed_world or not same_facts:
		if not shared: _actor_shapes.clear()
	if not shared:
		_passage_actor_profiles.clear()
		_passage_floor_profiles.clear()
		_passage_signatures.clear()
		_passage_profile_world=world
		_passage_profile_facts=world.facts
		_actor_index.clear()
		_convoy_owner.clear()
		_convoy_members.clear()
	_indexed_world = world
	_indexed_facts = world.facts
	_indexed_revision = world.revision
	_indexed_actor_scope = scope
	if not shared:
		query_counts.actor_index_builds += 1
		for id: String in world.ids("actors"):
			query_counts.actor_index_actor_visits += 1
			_sync_actor(world,id,false)
		_sync_convoys(world)

func _sync_passage_profile(world: WorldState, id: String) -> void:
	var actor: Dictionary=world.facts.actors[id]
	var floor_id: int=int(actor.location.floor_id) if actor.location.kind=="floor" else 0
	var journey: Dictionary=world.facts.moves.get(id,{})
	var convoy: Dictionary=journey.get("convoy",{})
	var source: Array=[floor_id,str(actor.species_id),str(actor.get("body_binding_id","")),convoy.get("size",0),convoy.get("height",0.0)]
	var old: Dictionary=_passage_actor_profiles.get(id,{})
	if old.get("source",[])==source: return
	if not old.is_empty() and int(old.floor)>0:
		var entries: Dictionary=_passage_floor_profiles[int(old.floor)]
		var entry: Dictionary=entries[old.profile]
		entry.ids.erase(id)
		if entry.ids.is_empty():
			entries.erase(old.profile)
			_passage_signatures.erase(int(old.floor))
			passage_profile_changes+=1
		elif str(entry.actor.id)==id:
			var other_id: String=str(entry.ids.keys()[0])
			var other_move: Dictionary=world.facts.moves.get(other_id,{})
			entry.actor=ConvoyTrail.proxy(world,other_move) if other_move.has("convoy") else world.facts.actors[other_id].duplicate(true)
	var record: Dictionary={"source":source,"floor":floor_id,"profile":""}
	if floor_id>0:
		var proxy: Dictionary=ConvoyTrail.proxy(world,journey) if journey.has("convoy") else actor
		var profile: String=JSON.stringify([clearance(proxy),body(proxy)],"",true,true)
		record.profile=profile
		if not _passage_floor_profiles.has(floor_id): _passage_floor_profiles[floor_id]={}
		var entries: Dictionary=_passage_floor_profiles[floor_id]
		if not entries.has(profile):
			entries[profile]={"ids":{},"actor":proxy.duplicate(true)}
			_passage_signatures.erase(floor_id)
			passage_profile_changes+=1
		entries[profile].ids[id]=true
	_passage_actor_profiles[id]=record

func _ensure_passage_profiles(world: WorldState) -> void:
	_ensure_actor_index(world)
	# Sealed spatial projections may share the BodyIndex while their Move
	# collection differs. Never share traversal profiles across those worlds.
	if _passage_profile_world!=world or not is_same(_passage_profile_facts,world.facts):
		_passage_actor_profiles.clear();_passage_floor_profiles.clear();_passage_signatures.clear()
		_passage_profile_world=world;_passage_profile_facts=world.facts
		for id: String in world.ids("actors"): _sync_passage_profile(world,id)

func passage_profiles(world: WorldState, floor_id: int) -> Dictionary:
	_ensure_passage_profiles(world)
	return _passage_floor_profiles.get(floor_id,{})

func passage_profile_signature(world: WorldState, floor_id: int) -> Array:
	_ensure_passage_profiles(world)
	if not _passage_signatures.has(floor_id):
		var keys: Array=_passage_floor_profiles.get(floor_id,{}).keys()
		keys.sort();_passage_signatures[floor_id]=keys
	return _passage_signatures[floor_id]

func _actor_index_scope(world: WorldState) -> Dictionary:
	for active: Dictionary in _route_queries:
		if is_same(active.world.facts.actors,world.facts.actors): return active
	return {}

func sync_actor(world: WorldState, id: String) -> void:
	_ensure_actor_index(world)
	_sync_actor(world,id)

# The fact owner calls this only after real departure, while the outside actor
# still exists. Remove its derived spatial identity before deleting that fact.
func forget_actor(world: WorldState, id: String) -> bool:
	_ensure_actor_index(world)
	var actor: Dictionary=world.facts.actors[id]
	if actor.location.kind!="outside" or world.facts.moves.has(id) or _convoy_owner.has(id) or not movement._member_owner(world,id).is_empty(): return false
	_sync_actor(world,id)
	_actor_shapes.erase(id)
	return true

func _sync_actor(world: WorldState, id: String, notify: bool = true) -> void:
	var actor: Dictionary = world.facts.actors[id]
	_sync_passage_profile(world,id)
	var previous: BodyIndex.Record = _actor_index._records.get(id)
	var old_floor: int = previous.floor_id if previous!=null else 0
	var old_rect: Rect2 = previous.rect if previous!=null else Rect2()
	var floor_id: int = 0
	var rectangle: Rect2 = Rect2()
	if actor.location.kind=="floor":
		rectangle = body_rectangle(actor)
		floor_id = int(actor.location.floor_id)
		if not _convoy_owner.has(id): _actor_index.update(id,floor_id,rectangle)
	elif not _convoy_owner.has(id):
		# Independent family alighting remains a real, indexed body even
		# before it is handed back to its ordinary floor movement. This is
		# also used by cold index reconstruction, not only the live step.
		var connection: Dictionary=world.facts.connectors.get(actor.location.get("connector_id",""),{})
		var handoff: Dictionary={}
		for group: Dictionary in connection.get("passenger_groups",[]):
			var portal: Dictionary=group.get("companion_portals",{}).get(id,{})
			if not portal.is_empty() and portal.get("stage","")=="alighting": handoff=portal;break
		if handoff.is_empty(): _actor_index.remove(id)
		else:
			var cursor: int=int(handoff.cursor)
			var pose: Dictionary=handoff.plan.seated_pose if cursor==0 else handoff.plan.alighting[cursor-1].poses[id]
			var r: Array=pose.region
			rectangle=Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3]))
			floor_id=int(connection.floor_id)
			_actor_index.update(id,floor_id,rectangle)
	if notify and public_areas!=null: public_areas.actor_changed(world,id,old_floor,old_rect,floor_id,rectangle)

func finish_boundary(world: WorldState) -> void:
	_indexed_revision = world.revision

func clearance(actor: Dictionary) -> int:
	if actor.has("_convoy_size"): return int(actor._convoy_size)
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
	# A transport unit containing only its primary has no additional body.
	# Keep the primary's current reservation permissions in the single-body query.
	if members.size()==1 and members[0]==actor.id: members = []
	if members.is_empty() and not _route_queries.is_empty() and _route_queries.back().world==world:
		return _navigation.clearance(self,world,floor_id,actor).reason(origin)
	if members.is_empty():
		var geometry: RouteClearance = _navigation.cached_static_geometry(self,world,floor_id,actor)
		if geometry!=null:
			return RouteClearance.new(self,world,actor,floor_id,[],{},true,_navigation.floor_source(self,world,floor_id),geometry).reason(origin)
	return RouteClearance.new(self,world,actor,floor_id,members,offsets,true,_navigation.floor_source(self,world,floor_id)).reason(origin)

func route(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false, route_filter: Dictionary = {}) -> Dictionary:
	return _route_result(world,actor_id,floor_id,target,members,offsets,ignore_people,false,route_filter)

func route_cost(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false, route_filter: Dictionary = {}) -> Dictionary:
	return _route_result(world,actor_id,floor_id,target,members,offsets,ignore_people,true,route_filter)

func can_reach(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false, route_filter: Dictionary = {}) -> bool:
	return bool(_route_result(world,actor_id,floor_id,target,members,offsets,ignore_people,true,route_filter).ok)

func _route_result(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array, offsets: Dictionary, ignore_people: bool, distance_only: bool, route_filter: Dictionary = {}) -> Dictionary:
	return self.navigation._route_result(world,actor_id,floor_id,target,members,offsets,ignore_people,distance_only,route_filter)

func travel_quote(world: WorldState, actor_id: String, floor_id: int, target: Array) -> Dictionary:
	return self.navigation.travel_quote(world,actor_id,floor_id,target)

func request_move(world: WorldState, actor_id: String, floor_id: int, target: Array) -> String:
	return self.movement.request_move(world,actor_id,floor_id,target)

func movement_failure(world: WorldState, actor_id: String) -> Dictionary:
	return movement.failure(world,actor_id)

# Waiting and same-floor guidance must not use another floor as a shortcut.
func request_floor_move(world: WorldState, actor_id: String, floor_id: int, target: Array) -> String:
	var actor: Dictionary = world.facts.actors.get(actor_id,{})
	if actor.get("location",{}).get("kind","")!="floor" or int(actor.location.floor_id)!=floor_id: return "本层移动不能跨楼层"
	var reason: String = movement.request_move(world,actor_id,floor_id,target)
	if reason.is_empty() and world.facts.moves.has(actor_id): world.facts.moves[actor_id].floor_only = true
	return reason

func cancel_ground_move(world: WorldState, actor_id: String) -> bool:
	return movement.cancel_ground(world,actor_id)

# Local personality conditions ask only whether a point is reachable within a
# few grid steps. Share one bounded native BFS with the same reservation rights.
func nearby_reachable(world: WorldState, actor_id: String, floor_id: int, start: Vector2i, goal: Vector2i, radius: int = 3) -> bool:
	if radius<0 or absi(goal.x-start.x)+absi(goal.y-start.y)>radius: return false
	var actor: Dictionary = world.facts.actors[actor_id]
	var graph: FloorNavigation = _navigation.graph(self,world,floor_id,actor,[],{})
	var query: RouteClearance = _navigation.clearance(self,world,floor_id,actor)
	if not query.reason(goal).is_empty(): return false
	var fields: Dictionary = read_view(world,"nearby_distance_fields",func()->Dictionary: return {})
	var key: String = JSON.stringify([graph.geometry.get_instance_id(),RouteClearance.reservation_exemptions(world,actor_id,floor_id),start.x,start.y,radius])
	if not fields.has(key):
		fields[key] = graph.distance_field(query,start,false,radius)
		query_counts["nearby_field_builds"] = int(query_counts.get("nearby_field_builds",0))+1
	var field: Dictionary = fields[key]
	if not field.get("ready",false):
		var fallback: Dictionary = _floor_route(world,actor,floor_id,start,goal,[],{},true,{},true)
		return fallback.get("ok",false) and float(fallback.walking_distance)<=radius
	if not FloorNavigation._inside(goal): return false
	var distance: int = field.distances[FloorNavigation._id(goal)]
	return distance>=0 and distance<=radius

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

func _unit_step_dynamic_clear(world: WorldState, actor: Dictionary, floor_id: int, from: Vector2i, to: Vector2i, members: Array, offsets: Dictionary, prepared: Dictionary = {}) -> bool:
	# A prepared projection belongs only to one synchronous A* invocation.
	# The common single standing body keeps the original addition order.
	if prepared.has("shape"):
		var shape: Rect2 = prepared.shape
		var origin: Vector2 = prepared.origin if prepared.on_floor and from==prepared.start else Vector2(from)
		var from_rect: Rect2 = Rect2(origin+shape.position,shape.size)
		var to_rect: Rect2 = Rect2(Vector2(to)+shape.position,shape.size)
		return not (prepared.index as BodyIndex).intersects(floor_id,from_rect.merge(to_rect),"")

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
		var member: Dictionary = actor if id==actor.id else world.facts.actors[id]
		var from_origin: Vector2 = start_origin if actual_floor_start and from==start_cell else Vector2(from)
		var from_rect: Rect2 = _actor_rect(member,from_origin+offset)
		var to_rect: Rect2 = _actor_rect(member,Vector2(to)+offset)
		var swept: Rect2 = from_rect.merge(to_rect)
		if prepared.is_empty():
			if not _dynamic_clear(world,actor.id,floor_id,swept,members,false,true): return false
		elif (prepared.index as BodyIndex).intersects(floor_id,swept,""):
			return false
	return true


# Freeze only the forbidden dynamic rectangles for one synchronous A* search.
# Boost remains the broadphase and Godot Rect2 retains strict intersections.
# The projection is discarded before another query or any real move commits.
func _dynamic_route_query(world: WorldState, actor: Dictionary, floor_id: int, members: Array, offsets: Dictionary) -> Dictionary:
	_ensure_actor_index(world)
	var index: BodyIndex = BodyIndex.new()
	var projection: Dictionary = _actor_exclusion_scope(world)
	var ignored: Array = members+[actor.id]
	for source_id: int in 2:
		var source: BodyIndex = _actor_index if source_id==0 else movement._sweep_index
		var excluded: Array = ignored+projection.get("actor_exclusions",[]) if source_id==0 else ignored
		for id: String in source._records:
			var record: BodyIndex.Record = source._records[id]
			if record.boundary!=source._boundary or record.floor_id!=floor_id or id in excluded: continue
			var key: String = str(source_id)+":"+id
			if record.regions.is_empty(): index.update(key,floor_id,record.rect)
			else: index.update_compound(key,floor_id,record.regions)
	var reservations: Dictionary = reservation_view(world).regions
	for key: String in reservations:
		var region: Dictionary = reservations[key]
		if not bool(region.blocks_passage): continue
		var reservation: Dictionary = region.reservation
		if int(reservation.floor_id)==floor_id and not RouteClearance.reservation_allows(reservation,actor.id,members):
			index.update("r:"+key,floor_id,region.rect)
	var prepared: Dictionary = {"index":index}
	if (members.is_empty() or members==[actor.id]) and offsets.is_empty() and actor.get("posture","standing")!="lying":
		var on_floor: bool = actor.location.kind=="floor" and int(actor.location.floor_id)==floor_id
		var origin: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1])) if on_floor else Vector2.ZERO
		prepared.merge({"shape":_actor_rect(actor,Vector2.ZERO),"on_floor":on_floor,"origin":origin,"start":Vector2i(roundi(origin.x),roundi(origin.y))})
	query_counts["dynamic_route_projections"] = int(query_counts.get("dynamic_route_projections",0))+1
	return prepared

func queue_waypoint(world: WorldState, movement: Dictionary, floor_id: int, cell: Array) -> void:
	self.movement.queue_waypoint(world,movement,floor_id,cell)

func _actor_rect(actor: Dictionary, origin: Vector2) -> Rect2:
	if actor.has("_convoy_size"): return Rect2(origin,Vector2.ONE*int(actor._convoy_size))
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

func intersects_actor_body(world: WorldState, floor_id: int, rect: Rect2, ignored_id: String = "") -> bool:
	_ensure_actor_index(world)
	# The movement index may contain a whole convoy corridor, not individual
	# bodies. Legal ground convoys contain standing members covered by that
	# envelope; support/lying begins only after the convoy ends. Expand local
	# owners and test their current floor bodies. Corridor gaps, transit
	# riders, reservations and sweeps are not occupancy.
	for owner: String in _actor_index.candidates(floor_id,rect):
		for id: String in _convoy_members.get(owner,[owner]):
			if id==ignored_id: continue
			var actor: Dictionary = world.facts.actors[id]
			if actor.location.kind=="floor" and int(actor.location.floor_id)==floor_id and rect.intersects(body_rectangle(actor),false): return true
	return false

func _unit_rect(world: WorldState, actor: Dictionary, origin: Vector2, members: Array, offsets: Dictionary) -> Rect2:
	var rect: Rect2 = _actor_rect(actor,origin)
	for member_id: String in members:
		if member_id != actor.id:
			var offset: Array = offsets[member_id]
			rect = rect.merge(_actor_rect(world.facts.actors[member_id],origin+Vector2(float(offset[0]),float(offset[1]))))
	return rect

func _build_reservation_view(world: WorldState) -> Dictionary:
	query_counts.reservation_index_builds += 1
	var view: Dictionary = {"index":BodyIndex.new(),"regions":{},"reservation_keys":{},"destination_claims":{},"destination_claim_floors":{}}
	for id: String in world.facts.adaptations: _index_reservation(world,view,id,world.facts.adaptations[id])
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
	# Temporary door spans change environmental propagation without changing
	# the structural floor. All reservation owners already publish here.
	reservation_revision += 1
	var cached: Dictionary = _reservation_views.get(world.get_instance_id(),{})
	if not cached.is_empty(): _index_reservation(world,cached.view,id,world.facts.adaptations.get(id,{}))
	reservation_updated.emit(world,id)
	if public_areas!=null: public_areas.reservation_changed(world,id)

# Optional geometry has the same world/floor synchronous borrowing contract
# as _blocking_facility; reservations below are always queried live.
func movement_doors(world: WorldState, actor: Dictionary, swept: Rect2, members: Array = [], floor_id: int = 0, geometry: FloorStaticGeometry = null) -> Array[Dictionary]:
	if floor_id==0: floor_id = int(actor.location.floor_id)
	if geometry==null: geometry = _navigation.floor_geometry(self,world,floor_id)
	var entry: Dictionary = {"index":geometry.door_index,"doors":geometry.door_order,"order":geometry.door_order}
	var ids: Dictionary = {}
	# A door may grow from its fixed anchor to fit this body's envelope.
	var reach: float = float(clearance(actor))+1.0
	for id: String in members:
		if is_same(world.facts.actors[id],actor): continue
		reach = maxf(reach,float(clearance(world.facts.actors[id]))+1.0)
	for id: String in entry.index.candidates(floor_id,swept.grow(reach)): ids[id] = true
	for region: Dictionary in _reservation_regions(world,floor_id,swept):
		if region.reservation.kind=="door" and entry.doors.has(region.reservation_id): ids[region.reservation_id] = true
	# All live index and reservation checks above still run. An empty
	# union has no ordering or floor-record projection work to perform.
	if ids.is_empty(): return []
	var ordered: Array = ids.keys()
	ordered.sort_custom(func(a: String,b: String) -> bool: return int(entry.order[a])<int(entry.order[b]))
	var result: Array[Dictionary] = []
	var actual: Array = world.facts.floors.overrides.get(str(floor_id),{}).get("doors",[])
	for id: String in ordered: result.append(actual[int(entry.order[id])])
	query_counts.door_candidates += result.size()
	return result

func _index_reservation(world: WorldState, view: Dictionary, id: String, reservation: Dictionary) -> void:
	query_counts.reservation_index_updates += 1
	var previous_floor: int = int(view.destination_claims.get(id,0))
	if previous_floor>0:
		var remaining: int = int(view.destination_claim_floors[previous_floor])-1
		if remaining==0: view.destination_claim_floors.erase(previous_floor)
		else: view.destination_claim_floors[previous_floor] = remaining
	view.destination_claims.erase(id)
	for key: String in view.reservation_keys.get(id,[]):
		view.index.remove(key)
		view.regions.erase(key)
	if reservation.is_empty():
		view.reservation_keys.erase(id)
		return
	var keys: Array = []
	var destination_claim: bool = false
	for ordinal: int in reservation.get("regions",[]).size():
		var area: Array = reservation.regions[ordinal]
		var rect: Rect2 = Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3]))
		var key: String = id+":"+str(ordinal)
		view.index.update(key,int(reservation.floor_id),rect)
		var blocks_passage: bool=ordinal==0 or not RouteClearance.is_soft_bed(world,reservation)
		view.regions[key] = {"reservation":reservation,"reservation_id":id,"rect":rect,"blocks_passage":blocks_passage}
		if not blocks_passage: destination_claim = true
		keys.append(key)
	view.reservation_keys[id] = keys
	if destination_claim:
		var floor_id: int = int(reservation.floor_id)
		view.destination_claims[id] = floor_id
		view.destination_claim_floors[floor_id] = int(view.destination_claim_floors.get(floor_id,0))+1

func _reservation_regions(world: WorldState, floor_id: int, rect: Rect2) -> Array:
	if world.facts.adaptations.is_empty(): return []
	query_counts.reservation_candidate_queries += 1
	var view: Dictionary = reservation_view(world)
	var regions: Array = []
	for key: String in view.index.candidates(floor_id,rect): regions.append(view.regions[key])
	return regions

func _reservation_regions_many(world: WorldState, floor_id: int, bounds: Array[Rect2]) -> Array:
	if bounds.is_empty() or world.facts.adaptations.is_empty(): return []
	query_counts.reservation_candidate_queries += 1
	var view: Dictionary = reservation_view(world)
	var regions: Array = []
	for key: String in view.index.candidates_in_regions(floor_id,bounds): regions.append(view.regions[key])
	return regions

func _dynamic_clear(world: WorldState, actor_id: String, floor_id: int, rect: Rect2, members: Array = [], actors_checked: bool = false, passing: bool = false) -> bool:
	if not actors_checked: _ensure_actor_index(world)
	for region: Dictionary in _reservation_regions(world,floor_id,rect):
		if passing and not bool(region.blocks_passage): continue
		var reservation: Dictionary = region.reservation
		if int(reservation.floor_id)!=floor_id or RouteClearance.reservation_allows(reservation,actor_id,members):
			continue
		if rect.intersects(region.rect,false):
			return false
	if not actors_checked:
		var projection: Dictionary = _actor_exclusion_scope(world)
		var ignored: Array = members if projection.is_empty() else members+projection.actor_exclusions
		if _actor_index.intersects(floor_id,rect,actor_id,ignored):
			return false
	if movement._sweep_index.intersects(floor_id,rect,actor_id,members):
		return false
	return true

# Destination claims stay exclusive even when empty bedside floor can be
# crossed. This local indexed check never treats people as permanent walls.
func has_bed_destination_claims(world: WorldState) -> bool:
	# This summary belongs to the same current reservation view. Door and
	# ordinary facility claims still run all physical passage checks.
	return not bed_destination_view(world).is_empty()

# A read-only borrower for one synchronous check. Actual owner updates still
# maintain this view; no borrower survives a move or a world/facts replacement.
# Floor zero asks for the complete summary, without imposing a floor limit.
func bed_destination_view(world: WorldState, floor_id: int = 0) -> Dictionary:
	if world.facts.adaptations.is_empty(): return {}
	var view: Dictionary = reservation_view(world)
	if view.destination_claims.is_empty() or floor_id>0 and not view.destination_claim_floors.has(floor_id): return {}
	return view

func bed_destination_blocker(world: WorldState, actor_id: String, floor_id: int, rect: Rect2, members: Array = []) -> String:
	var view: Dictionary = bed_destination_view(world,floor_id)
	if view.is_empty(): return ""
	return _bed_destination_blocker_in_view(view,actor_id,floor_id,rect,members)

func _bed_destination_blocker_in_view(view: Dictionary, actor_id: String, floor_id: int, rect: Rect2, members: Array) -> String:
	if not view.destination_claim_floors.has(floor_id): return ""
	query_counts.reservation_candidate_queries += 1
	for key: String in view.index.candidates(floor_id,rect):
		var region: Dictionary = view.regions[key]
		if bool(region.blocks_passage) or RouteClearance.reservation_allows(region.reservation,actor_id,members): continue
		if rect.intersects(region.rect,false): return str(region.reservation_id)
	return ""

func facility_layout(world: WorldState, facility_id: String) -> Dictionary:
	var facility: Dictionary = world.facts.facilities[facility_id]
	var layout: Dictionary = facility.duplicate()
	var reservation: Dictionary = world.facts.adaptations.get(facility_id,{})
	for field: String in ["footprint","patient_cell","operator_cells","repair_cell"]:
		if reservation.has(field):
			layout[field] = reservation[field]
	if facility.definition_id=="SE01":
		if not reservation.has("patient_cell"): layout.patient_cell=guidance_patient_post(world,facility_id).cell
		var nurses: Array=reservation.get("staff_ids",[]).duplicate()
		if not reservation.has("operator_cells"):
			var nurse: String=str(world.facts.get("floor_guidance",{}).get("desks",{}).get(facility_id,{}).get("nurse_id",""))
			if not world.facts.actors.has(nurse): nurse=""
			nurses=[] if nurse.is_empty() else [nurse]
			layout.operator_cells=[guidance_operator_cell(world,facility_id,nurse)]
		layout.operator_clearances=[]
		for index: int in layout.operator_cells.size():
			var size: int=clearance(world.facts.actors[nurses[index]]) if index<nurses.size() and world.facts.actors.has(nurses[index]) else 1
			# The frozen quote remains authoritative after its nurse is released.
			if reservation.has("operator_cells") and index+3<reservation.get("regions",[]).size(): size=int(reservation.regions[index+3][2])
			layout.operator_clearances.append(size)
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

func guidance_body(world: WorldState, actor: Dictionary, facility_id: String = "") -> Dictionary:
	var shapes: Array=[]
	var sample: Dictionary=actor.duplicate()
	for facing: float in [0.0,PI*0.5,PI,PI*1.5]:
		sample.facing=facing
		shapes.append(_actor_rect(sample,Vector2.ZERO))
	var result: Dictionary={"shapes":shapes,"clearance":clearance(actor)}
	var frozen: Dictionary=world.facts.adaptations.get(facility_id,{})
	if frozen.get("kind","")=="facility" and frozen.get("actor_id","")==actor.id and frozen.has("patient_cell"):
		result.frozen_cell=frozen.patient_cell.duplicate()
		result.frozen_facing=float(actor.facing)
		result.frozen_shape=_actor_rect(actor,Vector2.ZERO)
	return result

func guidance_patient_post(world: WorldState, facility_id: String, actor_id: String = "") -> Dictionary:
	var shape:=Rect2(Vector2.ZERO,Vector2.ONE)
	var data: Dictionary={"clearance":1,"shapes":[shape,shape,shape,shape]}
	if not actor_id.is_empty(): data=guidance_body(world,world.facts.actors[actor_id],facility_id)
	var post: Dictionary=GuidanceQueueLayout.patient_post(world.facts.facilities[facility_id],data)
	if not actor_id.is_empty() and not post.is_empty():
		# Reconstruct at the published actor cell through the exact body owner.
		# Subtracting a shape offset and adding it back can round by one ulp.
		var actual: Dictionary=world.facts.actors[actor_id].duplicate()
		actual.facing=float(post.facing)
		post.rect=_actor_rect(actual,Vector2(float(post.cell[0]),float(post.cell[1])))
	return post

func guidance_operator_cell(world: WorldState, facility_id: String, nurse_id: String = "") -> Array:
	var facility: Dictionary = world.facts.facilities[facility_id]
	var k: int = 1 if nurse_id.is_empty() else clearance(world.facts.actors[nurse_id])
	var x: int = int(facility.cell[0]); var y: int = int(facility.cell[1])
	var w: int = int(facility.footprint[0]); var h: int = int(facility.footprint[1])
	match posmod(int(facility.get("rotation",0)),4):
		1: return [x+w,y]
		2: return [x+maxi(0,w-k),y+h]
		3: return [x-k,y+maxi(0,h-k)]
	return [x,y-k]

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
	var guidance_post: Dictionary=guidance_patient_post(world,facility_id,actor_id) if facility.definition_id=="SE01" else {}
	var reference: Dictionary = _route_queries.back().reference if not _route_queries.is_empty() and _route_queries.back().world==world else {}
	if geometry_only: reference = {"fits":{}}
	var reference_key: String = ""
	if not reference.is_empty():
		var bodies: Array = [body(actor)]
		for staff_id: String in staff_ids:
			bodies.append(body(world.facts.actors[staff_id]))
		reference_key = JSON.stringify([facility_id,bodies])
		if not guidance_post.is_empty():
			var post: Rect2=guidance_post.rect
			reference_key=JSON.stringify([facility_id,bodies,guidance_post.cell,guidance_post.facing,[post.position.x,post.position.y,post.size.x,post.size.y]])
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
	var actor_clearance: int = clearance(actor)
	var capacity: Dictionary = definition.get("adapter_capacity",definition)
	if actor_clearance>int(capacity.get("max_clearance_cells",96)) or float(dimensions.height_m)>float(capacity.get("max_height_m",INF)):
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
		patient_cell = _adapted_front(facility,footprint,actor_clearance)
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
	if facility.definition_id=="SE01":
		patient_cell = guidance_post.cell.duplicate()
		if staff_ids.is_empty(): operators=[guidance_operator_cell(world,facility_id)]
		else: operators[0]=guidance_operator_cell(world,facility_id,str(staff_ids[0]))
	var regions: Array = [[x,y,w,h],[patient_cell[0],patient_cell[1],actor_clearance,actor_clearance],[repair[0],repair[1],1,1]]
	if not guidance_post.is_empty():
		var post: Rect2=guidance_post.rect
		regions[1]=[post.position.x,post.position.y,post.size.x,post.size.y]
	for index: int in staff_ids.size():
		var k: int = clearance(world.facts.actors[staff_ids[index]])
		regions.append([operators[index][0],operators[index][1],k,k])
	var allowed: Array = [actor_id]+staff_ids
	var room: Dictionary = world.facts.rooms.get(facility.get("room_id",""),{})
	var static_regions: Dictionary = _facility_geometry_view(world,facility)
	for area: Array in regions:
		var rect: Rect2 = Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3]))
		var region_key: String = JSON.stringify(area,"",true,true)
		if not static_regions.has(region_key): static_regions[region_key] = _facility_region_reason(world,facility,room,area,rect)
		var static_reason: String = static_regions[region_key]
		if not static_reason.is_empty(): return {"ok":false,"reason":static_reason}
		if reference.is_empty():
			var other_actor: String = _blocking_actor(world,int(facility.floor_id),rect,allowed)
			if not other_actor.is_empty(): return {"ok":false,"reason":"展开或操作区域有实际身体："+other_actor}
			# The scoped blocker just checked the identical body index and exclusions.
			# Unscoped diagnostics use raw bodies and retain the indexed safety check.
			var actors_checked: bool = not _route_queries.is_empty() and _route_queries.back().world==world
			if not _dynamic_clear(world,actor_id,int(facility.floor_id),rect,allowed,actors_checked):
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

# Region legality depends on built geometry and the actual fixed/bed footprint,
# never on the current people or queue. A new source replaces this floor's views;
# actual quotes and commits still execute every dynamic conflict check below.
func _facility_geometry_view(world: WorldState, facility: Dictionary) -> Dictionary:
	var floor_id: int = int(facility.floor_id)
	var version: String = _navigation.floor_static_version(self,world,floor_id)
	var saved: Dictionary = _facility_geometry.get(floor_id,{})
	if saved.is_empty() or saved.version!=version:
		saved = {"version":version,"facilities":{}}
		_facility_geometry[floor_id] = saved
	var key: String = str(facility.id)+":"+str(facility.get("room_id",""))
	if not saved.facilities.has(key): saved.facilities[key] = {}
	return saved.facilities[key]

# Built geometry is fixed within the owning read-only query scope. Dynamic
# bodies and reservation permissions still run in the original region order.
func _facility_region_reason(world: WorldState, facility: Dictionary, room: Dictionary, area: Array, rect: Rect2) -> String:
	for cx: int in range(floori(rect.position.x),ceili(rect.end.x)):
		for cy: int in range(floori(rect.position.y),ceili(rect.end.y)):
			if not owned(world,int(facility.floor_id),Vector2i(cx,cy)) or [cx,cy] in world.facts.floors.overrides.get(str(facility.floor_id),{}).get("blocked",[]):
				return "展开或退出区域受墙、地块阻挡：%d,%d" % [cx,cy]
	if facility.definition_id=="SE01":
		# Guidance belongs to the desk, not its room label. Preserve real
		# walls (including partial/concave walls and actual doorway gaps).
		var walls: Array = world.facts.floors.overrides.get(str(facility.floor_id),{}).get("wall_edges",[])
		if not world.facts.floors.overrides.get(str(facility.floor_id),{}).has("wall_edges"):
			for actual_room: Dictionary in world.facts.rooms.values():
				if int(actual_room.floor_id)==int(facility.floor_id): walls.append_array(BuildGeometry.room_walls(actual_room))
		for wall: Dictionary in walls:
			var horizontal: bool=str(wall.axis)=="x"
			var low: float=rect.position.y if horizontal else rect.position.x
			var high: float=rect.end.y if horizontal else rect.end.x
			var across_low: float=rect.position.x if horizontal else rect.position.y
			var across_high: float=rect.end.x if horizontal else rect.end.y
			if float(wall.line)>low and float(wall.line)<high and float(wall.high)>across_low and float(wall.low)<across_high:return "导诊操作区域跨越实际墙体"
	elif not room.is_empty() and not room_contains(room,rect): return "展开、岗位或出口超出本房间"
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
	# Bedside use claims do not add passage obstacles. The preflight still
	# checked current bodies, competing uses and the whole placement bundle.
	if facility.definition_id=="EQ05" and same_footprint:
		query_counts["bed_unchanged_passage_quotes"] = int(query_counts.get("bed_unchanged_passage_quotes",0))+1
		return quote
	# A real extension may not materialize through any body, including its
	# own nurse/doctor. Permission to use a post is not a collision exception.
	var x: int=int(facility.cell[0]);var y: int=int(facility.cell[1])
	var additions: Array[Rect2]=[]
	if int(footprint[0])>int(previous_footprint[0]): additions.append(Rect2(x+int(previous_footprint[0]),y,int(footprint[0])-int(previous_footprint[0]),int(footprint[1])))
	if int(footprint[1])>int(previous_footprint[1]): additions.append(Rect2(x,y+int(previous_footprint[1]),mini(int(footprint[0]),int(previous_footprint[0])),int(footprint[1])-int(previous_footprint[1])))
	for addition: Rect2 in additions:
		if intersects_actor_body(world,int(facility.floor_id),addition) or movement._sweep_index.intersects(int(facility.floor_id),addition,""): return {"ok":false,"reason":"护理床新增实体区域仍有实际身体"}
	# Genuine changed bed geometry retains the existing full safety proof.
	# This is not a fallback for unchanged beds or a claim of local expansion.
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
	if world.facts.facilities[facility_id].definition_id!=str(content.balance.staff_sleep.bed_definition_id):
		# A fixed public object only contributes short-lived use occupancy. That
		# occupancy does not change the structural navigation problem.
		var target: Array = fit.get("patient_cell",layout.patient_cell)
		var forward: Dictionary = {"ok":true,"travel_ticks":0} if at(world,actor_id,int(layout.floor_id),target) else route_cost(world,actor_id,int(layout.floor_id),target)
		if not forward.ok or not forward.has("travel_ticks"): return {"ok":false,"reason":forward.get("reason","实际设施行程无法估计")}
		return {"ok":true,"facility_id":facility_id,"floor_id":int(layout.floor_id),"cell":target.duplicate(),"patient_cell":target.duplicate(),"travel_ticks":int(forward.travel_ticks),"fit":fit}
	# Long-term personal-bed assignment still owns the original lawful round
	# trip. It shares this helper, but is not a public-facility selection.
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
	begin_route_query(candidate,{},false)
	var forward: Dictionary = _route_result(candidate,actor_id,int(layout.floor_id),layout.patient_cell,[],{},true,true)
	end_route_query()
	if not forward.ok or not forward.has("travel_ticks"): return {"ok":false,"reason":forward.get("reason","实际设施行程无法估计")}
	var origin: Dictionary = world.facts.actors[actor_id].location
	candidate.facts.actors[actor_id].location = {"kind":"floor","floor_id":int(layout.floor_id),"cell":layout.patient_cell.duplicate(),"height_m":0.0}
	begin_route_query(candidate,{},false)
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
	_facility_layout_changed(world,before,facility_layout(world,facility_id))
	return ""

func _facility_layout_changed(world: WorldState, before: Dictionary, after: Dictionary) -> void:
	public_areas.facility_changed(before,after)
	if guidance_queue_provider==null:return
	var provider: RefCounted=guidance_queue_provider.get_ref()
	if provider!=null and provider.has_method("facility_layout_changed"):provider.facility_layout_changed(world,before,after)

func commit_facility_reservations(world: WorldState, validated: Dictionary, facility_ids: Array) -> void:
	# The complete bundle was checked on a clone in this synchronous command.
	# Publish only its facility reservations; no world or service state is copied.
	for facility_id: String in facility_ids:
		if validated.has(facility_id):
			var before: Dictionary = facility_layout(world,facility_id)
			world.facts.adaptations[facility_id] = validated[facility_id].duplicate(true)
			reservation_changed(world,facility_id)
			_navigation.invalidate(world,int(validated[facility_id].floor_id))
			_facility_layout_changed(world,before,facility_layout(world,facility_id))

func grant_facility_access(world: WorldState, facility_id: String, staff_id: String) -> void:
	var reservation: Dictionary = world.facts.adaptations.get(facility_id,{})
	if reservation.is_empty() or staff_id in reservation.staff_ids: return
	reservation.staff_ids.append(staff_id)
	_navigation.invalidate(world,int(reservation.floor_id))

# Ordinary consultation posts remain usable while the same doctor stays at work.
# Expanded bodies and every active service retain the original reservation rules.
func ordinary_consultation_regions(facility: Dictionary) -> Array:
	if facility.get("definition_id","")!="FUR02": return []
	var cell: Array = facility.cell
	var size: Array = facility.footprint
	var patient: Array = facility.patient_cell
	var repair: Array = facility.repair_cell
	var regions: Array = [[cell[0],cell[1],size[0],size[1]],[patient[0],patient[1],1,1],[repair[0],repair[1],1,1]]
	for point: Array in facility.operator_cells: regions.append([point[0],point[1],1,1])
	return regions

func _ordinary_consultation_reservation(world: WorldState, reservation: Dictionary) -> bool:
	if reservation.kind!="facility" or reservation.owner_id!=reservation.actor_id: return false
	var facility: Dictionary = world.facts.facilities.get(reservation.facility_id,{})
	var regions: Array = ordinary_consultation_regions(facility)
	if regions.is_empty() or regions!=reservation.regions: return false
	for key: String in ["floor_id","footprint","patient_cell","operator_cells","repair_cell"]:
		if facility.get(key)!=reservation.get(key): return false
	return true

func _at_ordinary_operator_post(actor: Dictionary, reservation: Dictionary) -> bool:
	if actor.location.kind!="floor" or int(actor.location.floor_id)!=int(reservation.floor_id): return false
	var rectangle: Rect2 = body_rectangle(actor)
	for point: Array in reservation.operator_cells:
		if Rect2(float(point[0]),float(point[1]),1,1).encloses(rectangle): return true
	return false

func release_adaptations(world: WorldState) -> void:
	for id: String in world.ids("adaptations"):
		var reservation: Dictionary = world.facts.adaptations[id]
		var actor: Dictionary = world.facts.actors[reservation.actor_id]
		if reservation.kind=="facility" and (world.facts.tickets.has(reservation.owner_id) or world.facts.sessions.has(reservation.owner_id) or world.facts.preparations.has(reservation.owner_id) or world.facts.ward_stays.has(reservation.owner_id) or world.facts.get("staff_life",{}).get("reservations",{}).has(id) or HospitalFloorGuidance.owns_reservation(world,reservation)):
			continue
		var inside: bool = false
		var ordinary_consultation: bool = _ordinary_consultation_reservation(world,reservation)
		var participants: Array = reservation.staff_ids.duplicate()
		if not actor.id in participants: participants.append(actor.id)
		for participant_id: String in participants:
			var participant: Dictionary = world.facts.actors[participant_id]
			if ordinary_consultation and participant_id!=actor.id and _at_ordinary_operator_post(participant,reservation): continue
			# A newer journey cannot substitute its trail for the original
			# participants still physically using the held opening.
			for area: Array in reservation.regions:
				if participant.location.kind=="floor" and int(participant.location.floor_id)==int(reservation.floor_id) and body_rectangle(participant).intersects(Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3])),false): inside = true
			var journey: Dictionary = world.facts.moves.get(participant_id,{})
			if reservation.kind!="door" or not journey.has("convoy") or not RouteClearance.reservation_allows(reservation,participant_id,journey.members): continue
			if int(journey.convoy.floor_id)!=int(reservation.floor_id): continue
			var trail: Array[Rect2] = ConvoyPortal.ground_regions(journey.convoy,world.facts.connectors[participant.location.connector_id]) if participant.location.kind=="transit" else ConvoyTrail.regions(journey.convoy)
			for region: Rect2 in trail:
				for area: Array in reservation.regions:
					if region.intersects(Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3])),false): inside = true
		if not inside:
			var before: Dictionary=facility_layout(world,id) if reservation.kind=="facility" and world.facts.facilities.has(id) else reservation
			world.facts.adaptations.erase(id)
			reservation_changed(world,id)
			# Static navigation sources contain facility occupancy/footprints, not
			# temporary door spans. Door release uses the same live path as acquire.
			if reservation.kind=="facility": _navigation.invalidate(world,int(reservation.floor_id))
			if reservation.kind=="facility" and world.facts.facilities.has(id): _facility_layout_changed(world,before,facility_layout(world,id))

func _door_span(actor: Dictionary, door: Dictionary) -> int:
	var dimensions: Dictionary = body(actor)
	return maxi(int(door.span),ceili((maxf(float(dimensions.width_m),float(dimensions.depth_m))+0.1)/CELL_METERS))

# Actual passage only, with a current world door and the actual actor/proxy.
# Reuse an already-built, source-validated structural proof. Never construct a
# graph here: its builder uses door_quote and must not recurse through this path.
# Compound member aggregation still uses door_quote; a convoy supplies its proxy.
func door_passage_quote(world: WorldState, actor: Dictionary, floor_id: int, door: Dictionary) -> Dictionary:
	var geometry: RouteClearance=_navigation.cached_static_geometry(self,world,floor_id,actor)
	if geometry==null:return door_quote(world,actor,floor_id,door)
	var fit: Dictionary=geometry.door_static_fit(str(door.id))
	if fit.is_empty():return door_quote(world,actor,floor_id,door)
	if not fit.ok:return fit
	# Graph keys share integer spans/ceiling predicates, not exact dimensions.
	# Recompute both values for every actual reservation comparison/creation.
	var dimensions: Dictionary=body(actor)
	var definition: Dictionary=content.definition("doors",door.definition_id)
	return {"ok":true,"span":int(fit.span),"clear_height_m":maxf(float(definition.clear_height_m),float(dimensions.height_m)+0.1),"clear_width_m":maxf(float(definition.clear_width_m),maxf(float(dimensions.width_m),float(dimensions.depth_m))+0.1)}

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
	var opening: Rect2 = _door_rect(door,span)
	var along: int = 0 if door.axis=="x" else 1
	var continuous: bool = false
	var floor_walls: Variant = world.facts.floors.overrides.get(str(floor_id),{}).get("wall_edges")
	# The floor index owns independent walls, including those not enclosing a room.
	var geometry: FloorStaticGeometry = _navigation.floor_geometry(self,world,floor_id)
	if floor_walls is Array or room.has("wall_edges"):
		var door_line: int = int(door.cell[1-along])
		var local_walls: Array = (geometry._horizontal_walls if door.axis=="x" else geometry._vertical_walls).get(door_line,[]) if floor_walls is Array else room.wall_edges
		continuous = span<=int(door.span)
		for edge: Dictionary in local_walls:
			if edge.axis==door.axis and int(edge.line)==door_line and int(edge.low)<=int(door.cell[along]) and int(edge.high)>=int(door.cell[along])+span:
				continuous = true
	elif not room.is_empty():
		continuous = int(door.cell[along])>=int(room.origin[along]) and int(door.cell[along])+span<=int(room.origin[along])+int(room.size[along])
	if not continuous:
		return {"ok":false,"reason":"门展开越过连续墙段或墙角"}
	# Borrow only within this synchronous quote; live reservations are still read.
	for other: Dictionary in movement_doors(world,actor,opening,members,floor_id,geometry):
		if other.id!=door.id and opening.intersects(_door_rect(other,int(other.span)),false):
			return {"ok":false,"reason":"门展开与另一扇门相交"}
	if not _blocking_facility(world,floor_id,opening,"",geometry).is_empty():
		return {"ok":false,"reason":"门展开区域有实际设施"}
	var k: int = clearance(actor)
	for id: String in members: k = maxi(k,clearance(world.facts.actors[id]))
	var before: Rect2 = Rect2(opening.position-Vector2(0,k),Vector2(span,k)) if door.axis=="x" else Rect2(opening.position-Vector2(k,0),Vector2(k,span))
	var wall_depth: int = 0 if floor_walls is Array or room.has("wall_edges") else 1
	var after: Rect2 = Rect2(opening.position+Vector2(0,wall_depth),Vector2(span,k)) if door.axis=="x" else Rect2(opening.position+Vector2(wall_depth,0),Vector2(k,span))
	for side: Rect2 in [before,after]:
		for cx: int in range(int(side.position.x),int(side.end.x)):
			for cy: int in range(int(side.position.y),int(side.end.y)):
				if not owned(world,floor_id,Vector2i(cx,cy)) or [cx,cy] in world.facts.floors.overrides.get(str(floor_id),{}).get("blocked",[]):
					return {"ok":false,"reason":"门两侧没有容纳真实身体的完整空间"}
		if not _blocking_facility(world,floor_id,side,"",geometry).is_empty():
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

# Immutable journey membership is bound once. Each step publishes only its
# occupied trail; no follower is queried for movement permission.
func walking_speed(actor: Dictionary) -> float:
	var dimensions: Dictionary = content.actor_body(actor) if actor.has("_convoy_body") else body(actor)
	var k: int = ceili(maxf(float(dimensions.width_m),float(dimensions.depth_m))/CELL_METERS)
	return float(content.balance.movement_speeds[str(k)])

func _sync_convoys(world: WorldState) -> void:
	for owner: String in _convoy_members.keys():
		if not world.facts.moves.get(owner,{}).has("convoy"):
			_end_convoy(world,{"actor_id":owner,"members":_convoy_members[owner]})
	for journey: Dictionary in world.facts.moves.values():
		if journey.has("convoy"): _sync_convoy(world,journey)

func _sync_convoy(world: WorldState, journey: Dictionary) -> void:
	for id: String in journey.members: _sync_passage_profile(world,id)
	var owner: String = str(journey.actor_id)
	if not _convoy_members.has(owner):
		_convoy_members[owner] = journey.members.duplicate()
		for id: String in journey.members:
			_convoy_owner[id] = owner
			if id!=owner: _actor_index.remove(id)
	var actor: Dictionary = world.facts.actors[owner]
	var regions: Array[Rect2] = ConvoyTrail.regions(journey.convoy)
	if actor.location.kind=="transit": regions = ConvoyPortal.ground_regions(journey.convoy,world.facts.connectors[actor.location.connector_id])
	_actor_index.update_compound(owner,int(journey.convoy.floor_id),regions)

func _end_convoy(world: WorldState, journey: Dictionary) -> void:
	var owner: String = str(journey.actor_id)
	var former: Array = _convoy_members.get(owner,journey.get("members",[owner])).duplicate()
	_convoy_members.erase(owner)
	for id: String in former:
		_convoy_owner.erase(id)
		if world.facts.actors.has(id): _sync_actor(world,id)
