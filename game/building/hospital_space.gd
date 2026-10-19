class_name HospitalSpace
extends RefCounted

const CELL_METERS: float = 1.5
var content: HospitalContent
var _bodies: Dictionary = {}
var _actor_shapes: Dictionary = {}
var _actor_index: BodyIndex = BodyIndex.new()
var _sweep_index: BodyIndex = BodyIndex.new()
var _indexed_world: WorldState
var _indexed_revision: int = -1
var _navigation: NavigationCache = NavigationCache.new()
var _accepted_sweeps: Dictionary = {}
var _route_checks: Dictionary = {}
var _envelope_next: int = 0
var _route_queries: Array[Dictionary] = []
var _movement_reservations: Dictionary = {}
var public_areas: HospitalPublicAreas
var query_counts: Dictionary = {"routes":0,"journey_hits":0,"journey_invalidations":0,"transport_builds":0,"transport_searches":0,"candidate_connections":0,"floor_route_hits":0,"floor_route_builds":0}

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
	if journeys_allowed:
		for movement: Dictionary in world.facts.moves.values():
			if movement.has("transit_ticket"):
				journeys_allowed = false
				break
	if journeys_allowed:
		reference.transport_builds = int(reference.get("transport_builds",0))+1
		var transport: Dictionary = reference.transport_basis if reference.has("transport_basis") else HospitalTransit.reference_basis(self,world)
		if not reference.has("transport_basis"): query_counts.transport_builds += 1
		if reference.get("journey_transport",{})!=transport:
			query_counts.journey_invalidations += 1
			reference.journeys.clear()
			reference.journey_transport = transport.duplicate(true)
	_route_queries.append({"world":world,"routes":reference.get("routes",parent.get("routes",{})),"exits":exits,"views":views,"reference":reference,"journeys_allowed":journeys_allowed})

func end_route_query() -> void:
	var finished: Dictionary = _route_queries.pop_back()
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
	public_areas = HospitalPublicAreas.new(self)
	var cells: Array = content.balance.pathfinding.local_updates.chunk_cells
	_actor_index = BodyIndex.new(Vector2(float(cells[0]),float(cells[1])))
	_sweep_index = BodyIndex.new(Vector2(float(cells[0]),float(cells[1])))

func body(actor: Dictionary) -> Dictionary:
	var key: String = str(actor.species_id)+":"+str(actor.get("body_binding_id",""))
	if not _bodies.has(key):
		_bodies[key] = content.actor_body(actor)
	return _bodies[key]

func _ensure_actor_index(world: WorldState) -> void:
	if world==_indexed_world and world.revision==_indexed_revision:
		return
	if world!=_indexed_world:
		_actor_shapes.clear()
		_route_checks.clear()
	_actor_index.clear()
	_indexed_world = world
	_indexed_revision = world.revision
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
	return RouteClearance.new(self,world,actor,floor_id,members,offsets,true,_navigation.floor_source(self,world,floor_id)).reason(origin)

func route(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false) -> Dictionary:
	return _route_result(world,actor_id,floor_id,target,members,offsets,ignore_people,false)

# Existence consumers do not need the last unknown reason or a failed path.
# Actual movement and complete quotes retain route's full result contract.
func can_reach(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false) -> bool:
	return bool(_route_result(world,actor_id,floor_id,target,members,offsets,ignore_people,true).ok)

func _route_result(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array, offsets: Dictionary, ignore_people: bool, stop_on_unknown: bool) -> Dictionary:
	query_counts.routes += 1
	var actor: Dictionary = world.facts.actors[actor_id]
	if actor.location.kind != "floor":
		return {"ok": false, "reason": "角色正在竖向通行或院外"}
	var reference: Dictionary = _route_queries.back().reference if not _route_queries.is_empty() and _route_queries.back().world==world else {}
	var key: String = ""
	if not reference.is_empty() and ignore_people and members.is_empty() and offsets.is_empty() and _route_queries.back().journeys_allowed:
		# Reference actors have no transport tickets. A complete journey depends
		# on the body, reservation access, endpoints and this sealed clock.
		key = JSON.stringify([body(actor),RouteClearance.reservation_exemptions(world,actor_id),actor.get("posture","standing"),actor.facing,actor.location.floor_id,actor.location.cell,floor_id,target,world.sim_tick])
		if reference.journeys.has(key):
			query_counts.journey_hits += 1
			var retained: Dictionary = reference.journeys[key]
			if retained.transport_dependent: _mark_transport_dependency(reference)
			return retained.quote.duplicate()
	var start: Vector2i = Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1]))
	var goal: Vector2i = Vector2i(int(target[0]),int(target[1]))
	var source_floor: int = int(actor.location.floor_id)
	var actual: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	var stub: float = actual.distance_to(Vector2(start))
	if stub>0.0:
		var query: RouteClearance = _navigation.clearance(self,world,source_floor,actor) if members.is_empty() else RouteClearance.new(self,world,actor,source_floor,members,offsets,true,_navigation.floor_source(self,world,source_floor))
		var reason: String = query.sweep_reason(actual,Vector2(start))
		if not reason.is_empty():
			return {"ok":false,"status":"unreachable","reason":reason}
	var dependency: int = int(reference.get("dependency_revision",0))
	var result: Dictionary = HospitalTransit.route(self,world,actor,source_floor,start,floor_id,goal,members,offsets,ignore_people,HospitalTransit.walking_ticks(self,actor,members,stub),stop_on_unknown)
	if result.ok and stub>0.0:
		result.path.push_front({"kind":"floor","floor_id":source_floor,"cell":[start.x,start.y]})
		result.walking_distance += stub
	# A boolean failure may stop before the complete query's final reason.
	if not key.is_empty() and not stop_on_unknown: reference.journeys[key] = {"quote":result.duplicate(),"transport_dependent":int(reference.get("dependency_revision",0))>dependency}
	return result

func travel_quote(world: WorldState, actor_id: String, floor_id: int, target: Array) -> Dictionary:
	# Clinical estimates ignore people, like the original read-only route.
	# Connectors and actual movement continue through the complete path query.
	var actor: Dictionary = world.facts.actors[actor_id]
	if actor.location.kind!="floor" or (int(actor.location.floor_id)!=floor_id and nominal_query(world)):
		return route(world,actor_id,floor_id,target,[],{},true)
	var source_floor: int = int(actor.location.floor_id)
	var start: Vector2i = Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1]))
	var goal: Vector2i = Vector2i(int(target[0]),int(target[1]))
	var actual: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	var stub: float = actual.distance_to(Vector2(start))
	if stub>0.0:
		var query: RouteClearance = _navigation.clearance(self,world,source_floor,actor)
		var reason: String = query.sweep_reason(actual,Vector2(start))
		if not reason.is_empty(): return {"ok":false,"status":"unreachable","reason":reason}
	if source_floor!=floor_id: return _travel_route_quote(world,actor,source_floor,start,floor_id,goal,stub)
	var result: Dictionary = _navigation.travel_distance(self,world,floor_id,actor,start,goal)
	if not result.ready:
		return route(world,actor_id,floor_id,target,[],{},true) if nominal_query(world) else _travel_route_quote(world,actor,source_floor,start,floor_id,goal,stub)
	var delta: Vector2i = goal-start
	if not world.facts.connectors.is_empty() and (not result.ok or int(result.distance)!=absi(delta.x)+absi(delta.y)):
		return route(world,actor_id,floor_id,target,[],{},true) if nominal_query(world) else _travel_route_quote(world,actor,source_floor,start,floor_id,goal,stub)
	result.erase("ready")
	result.status = "complete" if result.ok else "unreachable"
	if result.ok:
		result.walking_distance = float(result.distance)+stub
		result.arrival_ticks = HospitalTransit.walking_ticks(self,actor,[],stub)+HospitalTransit.walking_ticks(self,actor,[],float(result.distance))
		result.quoted_tick = world.sim_tick
	return result

func _travel_route_quote(world: WorldState, actor: Dictionary, source_floor: int, start: Vector2i, target_floor: int, goal: Vector2i, stub: float) -> Dictionary:
	query_counts.routes += 1
	var result: Dictionary = HospitalTransit.route(self,world,actor,source_floor,start,target_floor,goal,[],{},true,HospitalTransit.walking_ticks(self,actor,[],stub),false,true)
	if result.ok: result.walking_distance += stub
	return result

func _floor_travel_quote(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2i, goal: Vector2i) -> Dictionary:
	var result: Dictionary = _navigation.forward_distance(self,world,floor_id,actor,start,goal)
	if not result.ready:
		result = _floor_route(world,actor,floor_id,start,goal,[],{},true)
		result.erase("path")
		return result
	result.erase("ready")
	result.status = "complete" if result.ok else "unreachable"
	if result.ok: result.walking_distance = float(result.distance)
	return result

func request_move(world: WorldState, actor_id: String, floor_id: int, target: Array) -> String:
	if world.facts.moves.has(actor_id):
		var previous: Dictionary = world.facts.moves[actor_id]
		if previous.get("route_pending",false) and (previous.target_floor!=floor_id or previous.target_cell!=target):
			var reason: String = static_reason(world,world.facts.actors[actor_id],floor_id,Vector2i(roundi(target[0]),roundi(target[1])))
			if not reason.is_empty():
				return reason
			HospitalTransit.cancel_waiting(world,previous)
			previous.erase("route_waypoint")
			previous.target_floor = floor_id
			previous.target_cell = target.duplicate()
			previous.erase("route_retry_tick")
		return previous.get("waiting_reason","")
	var actor: Dictionary = world.facts.actors[actor_id]
	if actor.location.kind!="floor":
		return "角色正在竖向通行或院外"
	if actor.get("posture","standing") == "lying":
		var facility: Dictionary = facility_layout(world,actor.support_facility_id)
		world.facts.moves[actor_id] = {"actor_id":actor_id,"path":[{"kind":"support_exit","floor_id":int(facility.floor_id),"cell":facility.patient_cell.duplicate()}],
			"cursor":0,"travelled":[_checkpoint(actor)],"blocked_since":-1,"yielding":false,"target_floor":floor_id,"target_cell":target.duplicate()}
		return ""
	var reason: String = static_reason(world,actor,floor_id,Vector2i(roundi(target[0]),roundi(target[1])))
	if not reason.is_empty():
		return reason
	world.facts.moves[actor_id] = {"actor_id":actor_id,"path":[],"cursor":0,
		"travelled":[_checkpoint(actor)],"blocked_since":-1,"yielding":false,"target_floor":floor_id,"target_cell":target.duplicate()}
	_queue_route(world,world.facts.moves[actor_id])
	return ""

func at(world: WorldState, actor_id: String, floor_id: int, target: Array) -> bool:
	var location: Dictionary = world.facts.actors[actor_id].location
	return location.kind == "floor" and int(location.floor_id) == floor_id and Vector2(float(location.cell[0]),float(location.cell[1])).distance_to(Vector2(float(target[0]),float(target[1]))) < 0.001

func request_group_move(world: WorldState, primary_id: String, members: Array, offsets: Dictionary, floor_id: int, target: Array) -> String:
	if world.facts.moves.has(primary_id):
		return ""
	for member_id: String in members:
		if world.facts.moves.has(member_id):
			return "等待陪同成员结束当前真实移动"
	var actor: Dictionary = world.facts.actors[primary_id]
	if actor.location.kind!="floor":
		return "等待完整通行组到达地面"
	for id: String in members:
		var offset: Array = offsets[id]
		if not at(world,id,int(actor.location.floor_id),[float(actor.location.cell[0])+float(offset[0]),float(actor.location.cell[1])+float(offset[1])]):
			return "等待完整陪同组到达真实配位"
	var reason: String = static_reason(world,actor,floor_id,Vector2i(roundi(target[0]),roundi(target[1])),members,offsets)
	if not reason.is_empty():
		return reason
	world.facts.moves[primary_id] = {"actor_id":primary_id,"members":members.duplicate(),"offsets":offsets.duplicate(true),
		"path":[],"cursor":0,"travelled":[_checkpoint(actor)],"blocked_since":-1,"yielding":false,"target_floor":floor_id,"target_cell":target.duplicate()}
	_queue_route(world,world.facts.moves[primary_id])
	return ""

func advance(world: WorldState, present_at_start: int = -1) -> void:
	_sweep_index.begin_boundary(world.facts.actors)
	_accepted_sweeps.clear()
	_ensure_actor_index(world)
	release_adaptations(world)
	_movement_reservations = _build_reservation_view(world)
	HospitalTransit.advance(self,world)
	_dispatch_routes(world,world.present_actor_count() if present_at_start<0 else present_at_start)
	for id: String in _route_checks.keys():
		if not world.facts.moves.has(id):
			_route_checks.erase(id)
	var floor_versions: Dictionary = {}
	for actor_id: String in world.ids("moves"):
		if not world.facts.moves.has(actor_id):
			continue
		var movement: Dictionary = world.facts.moves[actor_id]
		var actor: Dictionary = world.facts.actors[actor_id]
		if actor.location.kind == "transit" or movement.get("route_pending",false):
			continue
		if not _active_route_clear(world,actor,movement,floor_versions):
			_replan_goal(world,movement)
			continue
		if int(movement.cursor)==0:
			movement.cursor = _initial_route_cursor(actor,movement.path)
		if int(movement.cursor) >= movement.path.size():
			if movement.yielding:
				if world.facts.moves.has(movement.get("yield_partner","")):
					continue
				movement.yielding = false
				_queue_route(world,movement)
				continue
			world.facts.moves.erase(actor_id)
			continue
		var segment: Dictionary = movement.path[int(movement.cursor)]
		if segment.kind == "connector":
			HospitalTransit.begin(self,world,actor,movement,segment)
			continue
		var target: Vector2 = Vector2(float(segment.cell[0]),float(segment.cell[1]))
		var start: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
		var speed: float = float(content.balance.movement_speeds[str(clearance(actor))])
		var members: Array = movement.get("members",[actor_id])
		var offsets: Dictionary = movement.get("offsets",{})
		if members.size()>1:
			speed = float(content.balance.movement_speeds["2"])
		var next: Vector2 = start.move_toward(target,speed * WorldState.TICK_SECONDS)
		if next.distance_to(target)<0.001:
			next = target
		var initial_rect: Rect2 = _actor_index.rectangle(actor_id) if members.size()==1 else _unit_rect(world,actor,start,members,offsets)
		var sweeps: Array[BodyIndex.Record] = _unit_sweeps(world,actor,next,members,offsets,target-start)
		var swept: Rect2 = initial_rect
		for sweep: BodyIndex.Record in sweeps:
			swept = swept.merge(sweep.sweep_from).merge(sweep.sweep_to)
		if segment.kind!="support_exit":
			var floor_id: int = int(actor.location.floor_id)
			var query: RouteClearance = _navigation.clearance(self,world,floor_id,actor,members if members.size()>1 else [],offsets)
			if not _step_static_clear(world,actor,movement,next,query):
				continue
		if not _reserve_doors(world,actor,movement,swept):
			continue
		if not _movement_clear(world,actor_id,int(actor.location.floor_id),swept,sweeps,members):
			if int(movement.blocked_since) < 0:
				movement.blocked_since = world.facts.sim_tick
			elif int(world.facts.sim_tick) - int(movement.blocked_since) >= int(content.balance.movement_courtesy.blocked_before_yield_seconds) * 10:
				_yield(world,actor,movement,swept)
			continue
		movement.blocked_since = -1
		actor.location.cell = [next.x,next.y]
		_mark_door_use(world,int(actor.location.floor_id),swept)
		if segment.kind == "support_exit":
			actor.location.height_m = move_toward(float(actor.location.get("height_m",0)),0.0,speed*CELL_METERS*WorldState.TICK_SECONDS)
		actor.facing = atan2(target.x-start.x,target.y-start.y)
		for member_id: String in members:
			if member_id == actor_id:
				continue
			var offset: Array = offsets[member_id]
			world.facts.actors[member_id].location.cell = [next.x+float(offset[0]),next.y+float(offset[1])]
			world.facts.actors[member_id].facing = actor.facing
		for sweep: BodyIndex.Record in sweeps:
			_accepted_sweeps[sweep.id] = sweep
			_sweep_index.update(sweep.id,int(actor.location.floor_id),sweep.sweep_from.merge(sweep.sweep_to))
			_actor_index.update(sweep.id,int(actor.location.floor_id),sweep.sweep_to)
		if next.is_equal_approx(target):
			if segment.kind == "support_exit":
				actor.posture = "standing"
				actor.location.height_m = 0.0
				actor.erase("support_facility_id")
				_sync_actor(world,actor_id)
				movement.path = []
				movement.cursor = -1
				_queue_route(world,movement)
			movement.travelled.append({"kind":"floor","floor_id":actor.location.floor_id,"cell":segment.cell.duplicate()})
			movement.cursor += 1
	# Historic sweeps exist only during movement phase, never in later queries.
	_accepted_sweeps.clear()
	_sweep_index.expire_boundary()
	_movement_reservations = {}

func _floor_route(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2i, goal: Vector2i, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false, navigation: Dictionary = {}) -> Dictionary:
	var routes: Dictionary = {}
	var key: String = ""
	if navigation.is_empty() and not _route_queries.is_empty() and _route_queries.back().world==world and (ignore_people or _route_queries.back().get("dynamic",false)):
		routes = _route_queries.back().routes
		var identity: Variant = actor.id
		if not _route_queries.back().reference.is_empty() and members.is_empty() and offsets.is_empty():
			identity = [body(actor),RouteClearance.reservation_exemptions(world,actor.id,floor_id)]
		key = JSON.stringify([identity,floor_id,start.x,start.y,goal.x,goal.y,members,offsets,ignore_people,_route_envelope(world,actor,members,offsets)])
		if routes.has(key):
			query_counts.floor_route_hits += 1
			return routes[key].duplicate(true)
	query_counts.floor_route_builds += 1
	if navigation.is_empty():
		navigation = _navigation.query_graphs(self,world,floor_id,actor,members,offsets)
	var graph: FloorNavigation = navigation.graph
	var query: RouteClearance
	if navigation.has("query"): query = navigation.query
	else: query = _navigation.clearance(self,world,floor_id,actor) if members.is_empty() else RouteClearance.new(self,world,actor,floor_id,members,offsets,true,graph.geometry.source)
	var people: Callable = Callable()
	if not ignore_people:
		people = func(from_cell: Vector2i,to_cell: Vector2i) -> bool:
			return _unit_step_dynamic_clear(world,actor,floor_id,from_cell,to_cell,members,offsets)
	var result: Dictionary = graph.find_path(start,goal,query,Callable(),false,navigation.bases,navigation.shifts,bool(navigation.get("overlay",false)))
	if result.ok and people.is_valid():
		var low: Vector2 = Vector2(start)
		var high: Vector2 = low
		for cell: Array in result.cells:
			low = low.min(Vector2(float(cell[0]),float(cell[1])))
			high = high.max(Vector2(float(cell[0]),float(cell[1])))
		var shape: Rect2 = _unit_rect(world,actor,Vector2.ZERO,members,offsets)
		var broad: Rect2 = Rect2(low+shape.position,high-low+shape.size)
		if not _dynamic_clear(world,actor.id,floor_id,broad,members):
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
				# fractional stub makes its self-query wider, so retain A* there.
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
	var result: Array = [[body(actor),actor.get("posture","standing"),float(actor.get("facing",0.0)),[0,0]]]
	for member_id: String in members:
		if member_id==actor.id: continue
		var member: Dictionary = world.facts.actors[member_id]
		result.append([body(member),member.get("posture","standing"),float(member.get("facing",0.0)),offsets[member_id]])
	return result

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

func _queue_route(world: WorldState, movement: Dictionary) -> void:
	world.facts.move_request_next = int(world.facts.get("move_request_next",0))+1
	movement.request_sequence = world.facts.move_request_next
	movement.route_pending = true

func _checkpoint(actor: Dictionary) -> Dictionary:
	return {"kind":"floor","floor_id":int(actor.location.floor_id),"cell":actor.location.cell.duplicate()}

func _replan_goal(world: WorldState, movement: Dictionary) -> void:
	HospitalTransit.cancel_waiting(world,movement)
	movement.erase("route_waypoint")
	movement.yielding = false
	movement.erase("yield_partner")
	_queue_route(world,movement)

func _active_route_clear(world: WorldState, actor: Dictionary, movement: Dictionary, versions: Dictionary) -> bool:
	var sequence: int = int(movement.get("request_sequence",0))
	var record: Dictionary = _route_checks.get(actor.id,{})
	if record.is_empty() or int(record.sequence)!=sequence:
		var floors: Dictionary = {}
		var connections: Dictionary = {}
		for segment: Dictionary in movement.path.slice(int(movement.cursor)):
			if segment.kind=="connector":
				connections[segment.connector_id] = true
			else:
				floors[int(segment.floor_id)] = true
		record = {"sequence":sequence,"floors":floors.keys(),"connections":connections.keys(),"stamp":[]}
	for floor_id: int in record.floors:
		if not versions.has(floor_id):
			versions[floor_id] = _navigation.floor_version(self,world,floor_id)
	if record.get("simple",false) and int(record.token)==int(_actor_shapes[actor.id].token) and int(record.version)==int(versions[record.floors[0]]):
		return true
	var stamp: Array = []
	for id: String in movement.get("members",[actor.id]):
		var member: Dictionary = world.facts.actors[id]
		stamp.append([member.species_id,member.get("body_binding_id",""),member.get("posture","standing"),movement.get("offsets",{}).get(id,[0,0])])
	for floor_id: int in record.floors:
		stamp.append(versions[floor_id])
	for id: String in record.connections:
		var connection: Dictionary = world.facts.connectors.get(id,{})
		if connection.is_empty():
			return false
		stamp.append([connection.definition_id,HospitalTransit.endpoints(connection),connection.anchor,connection.get("failed",false),connection.get("pending_failure",false)])
	if record.stamp==stamp:
		return true
	var floor_id: int = int(actor.location.floor_id)
	var current: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	var queries: Dictionary = {}
	var members: Array = movement.get("members",[])
	var offsets: Dictionary = movement.get("offsets",{})
	for segment: Dictionary in movement.path.slice(int(movement.cursor)):
		if segment.kind=="support_exit":
			current = Vector2(float(segment.cell[0]),float(segment.cell[1]))
			continue
		if segment.kind=="connector":
			var connection: Dictionary = world.facts.connectors.get(segment.connector_id,{})
			if connection.is_empty() or int(segment.from)!=floor_id or not HospitalTransit.has_stop(connection,int(segment.from)) or not HospitalTransit.has_stop(connection,int(segment.to)) or not HospitalTransit.fits(self,world,connection,actor.id,members).ok or (HospitalTransit._lowering(connection) and int(segment.to)>=int(segment.from)):
				return false
			floor_id = int(segment.to)
			current = Vector2(float(connection.anchor[0]),float(connection.anchor[1]))
			continue
		if int(segment.floor_id)!=floor_id:
			return false
		var target: Vector2 = Vector2(float(segment.cell[0]),float(segment.cell[1]))
		if not queries.has(floor_id):
			queries[floor_id] = _navigation.clearance(self,world,floor_id,actor) if members.is_empty() else RouteClearance.new(self,world,actor,floor_id,members,offsets,true,_navigation.floor_source(self,world,floor_id))
		if not (queries[floor_id] as RouteClearance).sweep_reason(current,target).is_empty():
			return false
		current = target
	record.stamp = stamp.duplicate(true)
	record.simple = members.size()<=1 and record.connections.is_empty() and record.floors.size()==1
	if record.simple:
		record.token = _actor_shapes[actor.id].token
		record.version = versions[record.floors[0]]
	_route_checks[actor.id] = record
	return true

func _dispatch_routes(world: WorldState, present_at_start: int) -> void:
	var pending: Array[String] = []
	for id: String in world.ids("moves"):
		var movement: Dictionary = world.facts.moves[id]
		if movement.get("route_pending",false) and int(movement.get("route_retry_tick",0))<=world.sim_tick:
			pending.append(id)
	pending.sort_custom(func(a: String,b: String) -> bool:
		var left: int = int(world.facts.moves[a].request_sequence)
		var right: int = int(world.facts.moves[b].request_sequence)
		return left<right if left!=right else a<b)
	var budget: int = maxi(int(content.balance.pathfinding.minimum_actor_requests_per_tick),ceili(float(present_at_start)/float(content.balance.pathfinding.actors_per_request)))
	for index: int in mini(budget,pending.size()):
		var id: String = pending[index]
		var movement: Dictionary = world.facts.moves[id]
		var waypoint: Dictionary = movement.get("route_waypoint",{})
		var floor_id: int = int(movement.target_floor) if waypoint.is_empty() else int(waypoint.floor_id)
		var cell: Array = movement.target_cell if waypoint.is_empty() else waypoint.cell
		var quote: Dictionary
		if waypoint.is_empty():
			quote = route(world,id,floor_id,cell,movement.get("members",[]),movement.get("offsets",{}))
		else:
			var actor: Dictionary = world.facts.actors[id]
			var start: Vector2i = Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1]))
			var goal: Vector2i = Vector2i(roundi(cell[0]),roundi(cell[1]))
			var actual: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
			var target: Vector2 = Vector2(float(cell[0]),float(cell[1]))
			quote = _floor_route(world,actor,floor_id,start,goal,movement.get("members",[]),movement.get("offsets",{}))
			if quote.ok:
				var query: RouteClearance = RouteClearance.new(self,world,actor,floor_id,movement.get("members",[]),movement.get("offsets",{}),true,_navigation.floor_source(self,world,floor_id))
				var reason: String = query.sweep_reason(actual,Vector2(start))
				if reason.is_empty():
					reason = query.sweep_reason(Vector2(goal),target)
				if not reason.is_empty():
					quote = {"ok":false,"reason":reason}
				else:
					if actual!=Vector2(start):
						quote.path.push_front({"kind":"floor","floor_id":floor_id,"cell":[start.x,start.y]})
					if target!=Vector2(goal):
						quote.path.append({"kind":"floor","floor_id":floor_id,"cell":cell.duplicate()})
		if not quote.ok:
			movement.waiting_reason = quote.reason
			movement.route_retry_tick = world.sim_tick+int(content.balance.movement_courtesy.retry_hard_block_seconds)*10
			_queue_route(world,movement)
			continue
		movement.path = quote.path
		if not waypoint.is_empty():
			movement.path.append_array(waypoint.continuation)
			movement.erase("route_waypoint")
		movement.cursor = 0
		movement.route_pending = false
		movement.erase("route_retry_tick")
		movement.erase("waiting_reason")

func _initial_route_cursor(actor: Dictionary, path: Array) -> int:
	if path.size()<2 or path[0].kind!="floor" or path[1].kind!="floor" or int(path[0].floor_id)!=int(actor.location.floor_id) or int(path[1].floor_id)!=int(actor.location.floor_id):
		return 0
	var actual: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	var first: Vector2 = Vector2(float(path[0].cell[0]),float(path[0].cell[1]))
	var next: Vector2 = Vector2(float(path[1].cell[0]),float(path[1].cell[1]))
	# A retreat can begin between these cells. Returning to the rounded start
	# would move toward the body being yielded to before moving away from it.
	if actual.distance_to(first)>0.001 and absf(actual.distance_to(first)+actual.distance_to(next)-first.distance_to(next))<0.001:
		return 1
	return 0

func queue_waypoint(world: WorldState, movement: Dictionary, floor_id: int, cell: Array) -> void:
	var remaining: Array = movement.path.slice(int(movement.cursor))
	movement.route_waypoint = {"floor_id":floor_id,"cell":cell.duplicate(),"continuation":remaining}
	_queue_route(world,movement)

func _unit_sweeps(world: WorldState, actor: Dictionary, next: Vector2, members: Array, offsets: Dictionary, direction: Vector2) -> Array[BodyIndex.Record]:
	var result: Array[BodyIndex.Record] = []
	for id: String in members:
		var member: Dictionary = world.facts.actors[id]
		var offset: Array = offsets.get(id,[0,0])
		var sweep: BodyIndex.Record = _actor_index.record(id)
		var from: Rect2 = sweep.rect
		var position: Vector2 = next+Vector2(float(offset[0]),float(offset[1]))
		var facing: float = atan2(direction.x,direction.y)
		var to: Rect2
		if facing==float(member.facing):
			to = Rect2(from.position+position-Vector2(float(member.location.cell[0]),float(member.location.cell[1])),from.size)
		else:
			var sample: Dictionary = member.duplicate()
			sample.facing = facing
			to = _actor_rect(sample,position)
		sweep.sweep_from = from
		sweep.sweep_to = to
		result.append(sweep)
	return result

func _movement_clear(world: WorldState, actor_id: String, floor_id: int, broad: Rect2, sweeps: Array[BodyIndex.Record], members: Array) -> bool:
	_ensure_actor_index(world)
	if world.facts.adaptations.is_empty() and not _actor_index.intersects(floor_id,broad,actor_id,members) and not _sweep_index.intersects(floor_id,broad,actor_id,members):
		return true
	var candidates: Dictionary = {}
	for id: String in _actor_index.candidates(floor_id,broad,members):
		candidates[id] = true
	for id: String in _sweep_index.candidates(floor_id,broad,members):
		candidates[id] = true
	var ids: Array = candidates.keys()
	ids.sort()
	for sweep: BodyIndex.Record in sweeps:
		var envelope: Rect2 = sweep.sweep_from.merge(sweep.sweep_to)
		for id: String in ids:
			if id in members:
				continue
			var other: BodyIndex.Record = _accepted_sweeps.get(id)
			var other_from: Rect2 = _actor_index.rectangle(id) if other==null else other.sweep_from
			var other_to: Rect2 = other_from if other==null else other.sweep_to
			if envelope.intersects(other_from.merge(other_to),false) and BodySweep.intersects(sweep.sweep_from,sweep.sweep_to,other_from,other_to):
				return false
		for region: Dictionary in _reservation_regions(world,floor_id,envelope):
			var reservation: Dictionary = region.reservation
			if int(reservation.floor_id)!=floor_id or actor_id==reservation.actor_id or actor_id in reservation.get("staff_ids",[]) or reservation.actor_id in members:
				continue
			if BodySweep.intersects(sweep.sweep_from,sweep.sweep_to,region.rect,region.rect):
				return false
	return true

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
	var view: Dictionary = {"index":BodyIndex.new(),"regions":{},"reservation_keys":{}}
	for id: String in world.facts.adaptations: _index_reservation(view,id,world.facts.adaptations[id])
	return view

func _index_reservation(view: Dictionary, id: String, reservation: Dictionary) -> void:
	for key: String in view.reservation_keys.get(id,[]):
		view.index.remove(key)
		view.regions.erase(key)
	var keys: Array = []
	for ordinal: int in reservation.get("regions",[]).size():
		var area: Array = reservation.regions[ordinal]
		var rect: Rect2 = Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3]))
		var key: String = id+":"+str(ordinal)
		view.index.update(key,int(reservation.floor_id),rect)
		view.regions[key] = {"reservation":reservation,"rect":rect}
		keys.append(key)
	view.reservation_keys[id] = keys

func _reservation_regions(world: WorldState, floor_id: int, rect: Rect2) -> Array:
	if world.facts.adaptations.is_empty(): return []
	var view: Dictionary = _movement_reservations
	if view.is_empty(): view = read_view(world,"dynamic_reservation_regions",func() -> Dictionary: return _build_reservation_view(world))
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
	if _sweep_index.intersects(floor_id,rect,actor_id,members):
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
	var moving: Dictionary = actor.duplicate(true)
	var start: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	var target: Vector2 = Vector2(float(facility.patient_cell[0]),float(facility.patient_cell[1]))
	var speed: float = float(content.balance.movement_speeds[str(clearance(actor))])*WorldState.TICK_SECONDS
	var ticks: int = maxi(1,ceili(start.distance_to(target)/speed))
	if not until_clear: return ticks
	var rectangle: Rect2 = Rect2(float(facility.cell[0]),float(facility.cell[1]),float(facility.footprint[0]),float(facility.footprint[1]))
	if not body_rectangle(moving).intersects(rectangle,false): return 0
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
	var footprint: Array = [maxi(int(facility.footprint[0]),depth_cells if turns%2==1 else width_cells),maxi(int(facility.footprint[1]),width_cells if turns%2==1 else depth_cells)]
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
	for area: Array in regions:
		var rect: Rect2 = Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3]))
		for cx: int in range(int(area[0]),int(area[0])+int(area[2])):
			for cy: int in range(int(area[1]),int(area[1])+int(area[3])):
				if not owned(world,int(facility.floor_id),Vector2i(cx,cy)) or [cx,cy] in world.facts.floors.overrides.get(str(facility.floor_id),{}).get("blocked",[]):
					return {"ok":false,"reason":"展开或退出区域受墙、地块阻挡：%d,%d" % [cx,cy]}
		if not room.is_empty() and not room_contains(room,rect):
			return {"ok":false,"reason":"展开、岗位或出口超出本房间"}
		var other_facility: String = _blocking_facility(world,int(facility.floor_id),rect,facility_id)
		if not other_facility.is_empty(): return {"ok":false,"reason":"展开区域有其他实际设施："+other_facility}
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
	if not prove_exits: return quote
	return _facility_exit_quote(world,facility_id,actor_id,staff_ids,quote)

# Continuation of a preflight in the same synchronous read-only enumeration.
# Actual reserve_facility always calls facility_quote and repeats full preflight.
func _facility_exit_quote(world: WorldState, facility_id: String, actor_id: String, staff_ids: Array, quote: Dictionary) -> Dictionary:
	if not quote.ok or quote.get("unchanged",false) or nominal_query(world): return quote
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
		if not _floor_route(candidate,other,int(facility.floor_id),start,exit,[],{},true,navigation).ok:
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
	var forward: Dictionary = route(candidate,actor_id,int(layout.floor_id),layout.patient_cell)
	end_route_query()
	if not forward.ok or not forward.has("arrival_ticks"): return {"ok":false,"reason":forward.get("reason","实际设施行程无法估计")}
	var origin: Dictionary = world.facts.actors[actor_id].location
	candidate.facts.actors[actor_id].location = {"kind":"floor","floor_id":int(layout.floor_id),"cell":layout.patient_cell.duplicate(),"height_m":0.0}
	sync_actor(candidate,actor_id)
	# This private projection changed only the actor just synchronized above.
	# Discard route/exit views while retaining the now-current body index.
	begin_dynamic_route_query(candidate,false)
	var back: Dictionary = route(candidate,actor_id,int(origin.floor_id),origin.cell)
	end_route_query()
	if not back.ok: return {"ok":false,"reason":"设施没有合法返回路线"}
	return {"ok":true,"facility_id":facility_id,"floor_id":int(layout.floor_id),"cell":layout.patient_cell.duplicate(),"patient_cell":layout.patient_cell.duplicate(),"travel_ticks":int(forward.arrival_ticks),"fit":fit}

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
			_navigation.invalidate(world,int(reservation.floor_id))
			if reservation.kind=="facility" and world.facts.facilities.has(id): public_areas.facility_changed(reservation,world.facts.facilities[id])

func _door_span(actor: Dictionary, door: Dictionary) -> int:
	var dimensions: Dictionary = body(actor)
	return maxi(int(door.span),ceili((maxf(float(dimensions.width_m),float(dimensions.depth_m))+0.1)/CELL_METERS))

func door_quote(world: WorldState, actor: Dictionary, floor_id: int, door: Dictionary) -> Dictionary:
	var dimensions: Dictionary = body(actor)
	var definition: Dictionary = content.definition("doors",door.definition_id)
	var span: int = _door_span(actor,door)
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
	for other: Dictionary in world.facts.floors.overrides.get(str(floor_id),{}).get("doors",[]):
		if other.id!=door.id and opening.intersects(_door_rect(other,int(other.span)),false):
			return {"ok":false,"reason":"门展开与另一扇门相交"}
	if not _blocking_facility(world,floor_id,opening).is_empty():
		return {"ok":false,"reason":"门展开区域有实际设施"}
	var k: int = clearance(actor)
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

func _reserve_doors(world: WorldState, actor: Dictionary, movement: Dictionary, swept: Rect2) -> bool:
	var floor_id: int = int(actor.location.floor_id)
	for door: Dictionary in world.facts.floors.overrides.get(str(floor_id),{}).get("doors",[]):
		if not swept.intersects(_door_rect(door,_door_span(actor,door)),false):
			continue
		var quote: Dictionary = door_quote(world,actor,floor_id,door)
		if not quote.ok or not swept.intersects(_door_rect(door,int(quote.span)),false):
			continue
		var current: Dictionary = world.facts.adaptations.get(door.id,{})
		if not current.is_empty() and current.actor_id!=actor.id:
			return false
		var rect: Rect2 = _door_rect(door,int(quote.span))
		var members: Array = movement.get("members",[actor.id])
		if not _dynamic_clear(world,actor.id,floor_id,rect,members):
			return false
		world.facts.adaptations[door.id] = {"kind":"door","owner_id":actor.id,"actor_id":actor.id,"staff_ids":members,"floor_id":floor_id,
			"span":quote.span,"clear_height_m":quote.clear_height_m,"clear_width_m":quote.clear_width_m,"regions":[[rect.position.x,rect.position.y,rect.size.x,rect.size.y]]}
		if not _movement_reservations.is_empty(): _index_reservation(_movement_reservations,str(door.id),world.facts.adaptations[door.id])
	return true

func _mark_door_use(world: WorldState, floor_id: int, swept: Rect2) -> void:
	for door: Dictionary in world.facts.floors.overrides.get(str(floor_id),{}).get("doors",[]):
		var current: Dictionary = world.facts.adaptations.get(door.id,{})
		if not current.is_empty() and swept.intersects(_door_rect(door,int(current.span)),false):
			door.used = true

func _step_static_clear(world: WorldState, actor: Dictionary, movement: Dictionary, next: Vector2, query: RouteClearance = null) -> bool:
	if query==null:
		query = RouteClearance.new(self,world,actor,int(actor.location.floor_id),movement.get("members",[]),movement.get("offsets",{}))
	var start: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	if query.sweep_reason(start,next).is_empty():
		return true
	_replan_goal(world,movement)
	return false

func _yield(world: WorldState, actor: Dictionary, movement: Dictionary, swept: Rect2) -> void:
	if movement.yielding or movement.travelled.is_empty():
		return
	var partner: String = ""
	for other_id: String in world.ids("moves"):
		if other_id==actor.id:
			continue
		var other: Dictionary = world.facts.actors[other_id]
		var other_move: Dictionary = world.facts.moves[other_id]
		if other.location.kind!="floor" or int(other.location.floor_id)!=int(actor.location.floor_id):
			continue
		var rect: Rect2 = _unit_rect(world,other,Vector2(float(other.location.cell[0]),float(other.location.cell[1])),other_move.get("members",[]),other_move.get("offsets",{}))
		if swept.intersects(rect,false):
			partner = other_id
			break
	if partner.is_empty():
		if _yield_idle_staff(world,actor,movement,swept):
			return
		# A body may stop on a route after it was planned. Keep the goal and
		# request a current detour instead of waiting for a moving partner.
		_queue_route(world,movement)
		return
	if _has_priority(world,actor.id,partner):
		return
	# A committed retreat keeps its winner until that winner finishes this move.
	# Re-evaluating priorities during the retreat creates mutual waiting cycles.
	if world.facts.moves[partner].yielding:
		var other_move: Dictionary = world.facts.moves[partner]
		if int(other_move.cursor)>=other_move.path.size():
			var detour: Dictionary
			if int(movement.target_floor)==int(actor.location.floor_id):
				detour = _floor_route(world,actor,int(actor.location.floor_id),
					Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1])),
					Vector2i(int(movement.target_cell[0]),int(movement.target_cell[1])),movement.get("members",[]),movement.get("offsets",{}))
			else:
				# A person going upstairs must also route around the parked yielder.
				detour = route(world,actor.id,int(movement.target_floor),movement.target_cell,movement.get("members",[]),movement.get("offsets",{}))
			if detour.ok:
				_queue_route(world,movement)
		return
	var current: Vector2i = Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1]))
	for index: int in range(movement.travelled.size()-1,-1,-1):
		var past: Dictionary = movement.travelled[index]
		if int(past.floor_id)!=int(actor.location.floor_id):
			continue
		if at(world,actor.id,int(actor.location.floor_id),past.cell):
			continue
		var cell: Vector2i = Vector2i(roundi(past.cell[0]),roundi(past.cell[1]))
		var actual: Vector2 = Vector2(float(past.cell[0]),float(past.cell[1]))
		if _narrow(world,actor,cell) or not _dynamic_clear(world,actor.id,int(actor.location.floor_id),_unit_rect(world,actor,actual,movement.get("members",[]),movement.get("offsets",{})),movement.get("members",[])):
			continue
		var retreat: Dictionary = _floor_route(world,actor,int(actor.location.floor_id),current,cell,movement.get("members",[]),movement.get("offsets",{}))
		if retreat.ok:
			movement.route_waypoint = {"floor_id":int(actor.location.floor_id),"cell":past.cell.duplicate(),"continuation":[]}
			_queue_route(world,movement)
			movement.yielding = true
			movement.yield_partner = partner
			return

func _yield_idle_staff(world: WorldState, actor: Dictionary, movement: Dictionary, swept: Rect2) -> bool:
	var floor_id: int = int(actor.location.floor_id)
	var route_cells: Array = []
	for segment: Dictionary in movement.path.slice(int(movement.cursor)):
		if segment.get("kind","")=="floor" and int(segment.get("floor_id",-1))==floor_id:
			route_cells.append(segment.cell)
	if route_cells.is_empty():
		route_cells.append(movement.target_cell)
	var candidates: Array[Dictionary] = []
	for staff_id: String in world.ids("staff"):
		if world.facts.moves.has(staff_id) or not world.facts.actors.has(staff_id):
			continue
		var staff_actor: Dictionary = world.facts.actors[staff_id]
		if staff_actor.location.kind!="floor" or int(staff_actor.location.floor_id)!=floor_id or staff_actor.get("posture","standing")!="standing":
			continue
		var blocker_rect: Rect2 = _actor_rect(staff_actor,Vector2(float(staff_actor.location.cell[0]),float(staff_actor.location.cell[1])))
		if not swept.intersects(blocker_rect,false) or _staff_has_movement_responsibility(world,staff_id):
			continue
		var origin: Vector2i = Vector2i(roundi(staff_actor.location.cell[0]),roundi(staff_actor.location.cell[1]))
		var checker: RouteClearance = RouteClearance.new(self,world,staff_actor,floor_id,[],{},true,_navigation.floor_source(self,world,floor_id))
		for radius: int in range(1,5):
			for dx: int in range(-radius,radius+1):
				var dy_abs: int = radius-absi(dx)
				for dy: int in ([0] if dy_abs==0 else [-dy_abs,dy_abs]):
					var goal: Vector2i = origin+Vector2i(dx,dy)
					if goal==origin or _narrow(world,staff_actor,goal,checker):
						continue
					var goal_rect: Rect2 = _actor_rect(staff_actor,Vector2(goal))
					var requester_path: bool = false
					for cell: Array in route_cells:
						if goal_rect.intersects(_actor_rect(actor,Vector2(float(cell[0]),float(cell[1]))),false):
							requester_path = true
							break
					if requester_path or not checker.reason(goal).is_empty():
						continue
					if not _dynamic_clear(world,staff_id,floor_id,goal_rect):
						continue
					var destination: Dictionary = _floor_route(world,staff_actor,floor_id,origin,goal)
					if destination.ok and destination.get("status","")!="contention":
						candidates.append({"id":staff_id,"goal":goal,"distance":float(destination.walking_distance)})
				if not candidates.is_empty():
					break
			if not candidates.is_empty():
				break
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if not is_equal_approx(float(a.distance),float(b.distance)):
			return float(a.distance)<float(b.distance)
		if str(a.id)!=str(b.id):
			return str(a.id)<str(b.id)
		return Vector2i(a.goal).y<Vector2i(b.goal).y or (Vector2i(a.goal).y==Vector2i(b.goal).y and Vector2i(a.goal).x<Vector2i(b.goal).x)
	)
	if candidates.is_empty():
		return false
	var choice: Dictionary = candidates[0]
	return request_move(world,str(choice.id),floor_id,[float(choice.goal.x),float(choice.goal.y)]).is_empty()

func _staff_has_movement_responsibility(world: WorldState, staff_id: String) -> bool:
	var staff: Dictionary = world.facts.staff.get(staff_id,{})
	if staff.is_empty() or HospitalClinicalDevelopment.safe_busy(world,staff_id):
		return true
	if not staff.get("base_task",{}).is_empty() or not str(staff.get("training_job_id","")).is_empty() or staff.get("life_task",{"phase":"idle"}).get("phase","idle")!="idle":
		return true
	for stay: Dictionary in world.facts.ward_stays.values():
		if staff_id in [stay.get("nurse_id",""),stay.get("round_doctor_id",""),stay.get("escort_id","")] and not stay.get("phase","") in ["release_wait","complete"]:
			return true
	for reservation: Dictionary in world.facts.adaptations.values():
		if staff_id in reservation.get("staff_ids",[]) or staff_id==reservation.get("actor_id",""):
			return true
	for reservation: Dictionary in world.facts.get("staff_life",{}).get("reservations",{}).values():
		if staff_id in reservation.get("staff_ids",[]):
			return true
	for job: Dictionary in world.facts.get("training_jobs",{}).values():
		if staff_id in [job.get("staff_id",""),job.get("mentor_id","")] and not HospitalClinicalDevelopment.terminal(job):
			return true
	return false

func _narrow(world: WorldState, actor: Dictionary, origin: Vector2i, checker: RouteClearance = null) -> bool:
	var available: int = 0
	if checker==null: checker = RouteClearance.new(self,world,actor,int(actor.location.floor_id),[],{},true,_navigation.floor_source(self,world,int(actor.location.floor_id)))
	for offset: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		if checker.reason(origin+offset).is_empty():
			available += 1
	return available<=2

func _has_priority(world: WorldState, first_id: String, second_id: String) -> bool:
	var first: Dictionary = world.facts.moves[first_id]
	var second: Dictionary = world.facts.moves[second_id]
	var a: Dictionary = world.facts.actors[first_id]
	var b: Dictionary = world.facts.actors[second_id]
	var first_narrow: bool = _narrow(world,a,Vector2i(roundi(a.location.cell[0]),roundi(a.location.cell[1])))
	var second_narrow: bool = _narrow(world,b,Vector2i(roundi(b.location.cell[0]),roundi(b.location.cell[1])))
	if first_narrow!=second_narrow:
		return first_narrow
	if first.get("members",[]).size()!=second.get("members",[]).size():
		return first.get("members",[]).size()>second.get("members",[]).size()
	if int(first.blocked_since)!=int(second.blocked_since):
		return int(first.blocked_since)<int(second.blocked_since)
	return first_id<second_id
