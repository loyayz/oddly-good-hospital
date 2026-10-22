class_name HospitalMovement
extends RefCounted

class MotionResult:
	extends RefCounted
	# One synchronous attempt, never a second copy of a journey or world fact.
	var requested_motion: Vector2 = Vector2.ZERO
	var actual_motion: Vector2 = Vector2.ZERO
	var blocker_actor_ids: Array[String] = []
	var reservation_ids: Array[String] = []
	var door_id: String = ""
	var blocked: bool:
		get: return not door_id.is_empty() or not blocker_actor_ids.is_empty() or not reservation_ids.is_empty()

var _space: WeakRef
var space: HospitalSpace:
	get: return _space.get_ref()

var _sweep_index: BodyIndex
var _accepted_sweeps: Dictionary = {}
var _route_checks: Dictionary = {}
var _movement_reservations: Dictionary = {}
var _world: WeakRef
var _pending_world: WeakRef
var _pending_routes: Dictionary = {}
var _ready_routes: PlatformRouteQueue
var _delayed_routes: PlatformRouteQueue
var _phase_owners: Dictionary = {}
var _route_failures: Dictionary = {}

func _init(geometry: HospitalSpace) -> void:
	_space = weakref(geometry)
	var cells: Array = geometry.content.balance.pathfinding.local_updates.chunk_cells
	_sweep_index = BodyIndex.new(Vector2(float(cells[0]),float(cells[1])))

func request_move(world: WorldState, actor_id: String, floor_id: int, target: Array) -> String:
	if world.facts.moves.has(actor_id):
		return _retarget(world,world.facts.moves[actor_id],floor_id,target)
	var actor: Dictionary = world.facts.actors[actor_id]
	if actor.location.kind!="floor":
		return "角色正在竖向通行或院外"
	if actor.get("posture","standing") == "lying":
		var facility: Dictionary = space.facility_layout(world,actor.support_facility_id)
		world.facts.moves[actor_id] = {"actor_id":actor_id,"path":[{"kind":"support_exit","floor_id":int(facility.floor_id),"cell":facility.patient_cell.duplicate()}],
			"cursor":0,"travelled":[_checkpoint(actor)],"blocked_since":-1,"yielding":false,"target_floor":floor_id,"target_cell":target.duplicate()}
		if space.public_areas!=null: space.public_areas.changed(world)
		return ""
	var reason: String = space.navigation.destination_reason(world,actor,floor_id,Vector2i(roundi(target[0]),roundi(target[1])))
	if not reason.is_empty():
		return reason
	world.facts.moves[actor_id] = {"actor_id":actor_id,"path":[],"cursor":0,
		"travelled":[_checkpoint(actor)],"blocked_since":-1,"yielding":false,"target_floor":floor_id,"target_cell":target.duplicate()}
	_queue_route(world,world.facts.moves[actor_id])
	if space.public_areas!=null: space.public_areas.changed(world)
	return ""

func _retarget(world: WorldState, previous: Dictionary, floor_id: int, target: Array) -> String:
	if previous.target_floor==floor_id and previous.target_cell==target: return previous.get("waiting_reason","")
	var actor: Dictionary = world.facts.actors[previous.actor_id]
	var reason: String = space.navigation.destination_reason(world,actor,floor_id,Vector2i(roundi(target[0]),roundi(target[1])),previous.get("members",[]),previous.get("offsets",{}))
	if not reason.is_empty(): return reason
	HospitalTransit.cancel_waiting(world,previous)
	previous.erase("route_waypoint")
	previous.target_floor = floor_id
	previous.target_cell = target.duplicate()
	previous.erase("route_retry_tick")
	previous.erase("waiting_reason")
	if actor.location.kind=="transit": previous.replan_after_transit = true
	elif previous.path.is_empty() or int(previous.cursor)>=previous.path.size() or previous.path[int(previous.cursor)].kind!="support_exit":
		_replan_goal(world,previous,bool(previous.get("route_pending",false)))
	if space.public_areas!=null: space.public_areas.changed(world)
	return previous.get("waiting_reason","")

func request_group_move(world: WorldState, primary_id: String, members: Array, offsets: Dictionary, floor_id: int, target: Array) -> String:
	if world.facts.moves.has(primary_id):
		var previous: Dictionary = world.facts.moves[primary_id]
		if previous.get("members",[primary_id])!=members or previous.get("offsets",{})!=offsets:
			return "等待原同行组结束或取消后再变更成员与配位"
		return _retarget(world,previous,floor_id,target)
	for member_id: String in members:
		if world.facts.moves.has(member_id):
			return "等待陪同成员结束当前真实移动"
	var actor: Dictionary = world.facts.actors[primary_id]
	if actor.location.kind!="floor":
		return "等待完整通行组到达地面"
	for id: String in members:
		var offset: Array = offsets[id]
		if not space.at(world,id,int(actor.location.floor_id),[float(actor.location.cell[0])+float(offset[0]),float(actor.location.cell[1])+float(offset[1])]):
			return "等待完整陪同组到达真实配位"
	var reason: String = space.navigation.destination_reason(world,actor,floor_id,Vector2i(roundi(target[0]),roundi(target[1])),members,offsets)
	if not reason.is_empty():
		return reason
	world.facts.moves[primary_id] = {"actor_id":primary_id,"members":members.duplicate(),"offsets":offsets.duplicate(true),
		"path":[],"cursor":0,"travelled":[_checkpoint(actor)],"blocked_since":-1,"yielding":false,"target_floor":floor_id,"target_cell":target.duplicate()}
	_queue_route(world,world.facts.moves[primary_id])
	if space.public_areas!=null: space.public_areas.changed(world)
	return ""

# An unreachable search is different from traffic contention. Its proof is
# query-local runtime data, rechecked against current static geometry and body
# conditions before the owning task may act on it.
func failure(world: WorldState, actor_id: String) -> Dictionary:
	var saved: Dictionary = _route_failures.get(actor_id,{})
	var movement: Dictionary = world.facts.moves.get(actor_id,{})
	if saved.is_empty() or movement.is_empty() or saved.world.get_ref()!=world or int(saved.sequence)!=int(movement.get("request_sequence",-1)) or int(saved.geometry)!=world.geometry_revision: return {}
	if saved.basis!=_failure_body_basis(world,movement) or saved.connectors!=space.navigation.connection_basis(world): return {}
	for floor_id: int in saved.floors:
		if int(saved.floors[floor_id])!=space._navigation.floor_static_version(space,world,floor_id): return {}
	return {"status":"unreachable","reason":saved.reason,"floor_id":movement.target_floor,"cell":movement.target_cell.duplicate()}

# A task can stop a ground walk or landing queue. It cannot interrupt a real
# ride, a support-exit segment or a group whose full body is not on the floor.
func cancel_ground(world: WorldState, actor_id: String) -> bool:
	var movement: Dictionary = world.facts.moves.get(actor_id,{})
	if movement.is_empty():
		var actor: Dictionary = world.facts.actors[actor_id]
		return actor.location.kind=="floor" and actor.get("posture","standing")!="lying"
	for id: String in movement.get("members",[actor_id]):
		var actor: Dictionary = world.facts.actors[id]
		if actor.location.kind!="floor" or actor.get("posture","standing")=="lying": return false
	if int(movement.cursor)<movement.path.size() and int(movement.cursor)>=0 and movement.path[int(movement.cursor)].kind=="support_exit": return false
	HospitalTransit.cancel_waiting(world,movement)
	world.facts.moves.erase(actor_id)
	_pending_routes.erase(actor_id)
	_route_checks.erase(actor_id)
	_route_failures.erase(actor_id)
	if space.public_areas!=null: space.public_areas.changed(world)
	return true

func _failure_body_basis(world: WorldState, movement: Dictionary) -> Array:
	var result: Array = [movement.target_floor,movement.target_cell,movement.get("members",[]),movement.get("offsets",{})]
	for id: String in movement.get("members",[str(movement.actor_id)]):
		var actor: Dictionary = world.facts.actors[id]
		result.append([id,actor.location,_route_body_basis(actor)])
	return result

func _remember_failure(world: WorldState, movement: Dictionary, reason: String) -> void:
	var floors: Dictionary = {}
	for entry: Dictionary in space._navigation._sources.values():
		if entry.world.get_ref()==world: floors[int(entry.floor_id)] = int(entry.static_version)
	_route_failures[movement.actor_id] = {"world":weakref(world),"sequence":int(movement.request_sequence),"geometry":world.geometry_revision,"basis":_failure_body_basis(world,movement).duplicate(true),"connectors":space.navigation.connection_basis(world).duplicate(true),"floors":floors,"reason":reason}
	if space.public_areas!=null: space.public_areas.changed(world)

func advance(world: WorldState, present_at_start: int = -1) -> void:
	# Read-only facility projections can temporarily replace the geometry
	# index's world. They never replace this world's actual journeys.
	if _world==null or _world.get_ref()!=world:
		_route_checks.clear()
		_route_failures.clear()
		_world = weakref(world)
	_sweep_index.begin_boundary(world.facts.actors)
	_accepted_sweeps.clear()
	_phase_owners.clear()
	space._ensure_actor_index(world)
	space.release_adaptations(world)
	_movement_reservations = space.reservation_view(world)
	HospitalTransit.advance(space,world)
	_dispatch_routes(world,world.present_actor_count() if present_at_start<0 else present_at_start)
	for id: String in _route_checks.keys():
		if not world.facts.moves.has(id):
			_route_checks.erase(id)
	for id: String in _route_failures.keys():
		if not world.facts.moves.has(id): _route_failures.erase(id)
	var floor_versions: Dictionary = {}
	for actor_id: String in world.ids("moves"):
		if not world.facts.moves.has(actor_id):
			continue
		var movement: Dictionary = world.facts.moves[actor_id]
		var actor: Dictionary = world.facts.actors[actor_id]
		if movement.get("replan_after_transit",false) and actor.location.kind=="floor":
			movement.erase("replan_after_transit")
			_replan_goal(world,movement)
		if actor.location.kind == "transit" or movement.get("route_pending",false):
			continue
		if not _active_route_clear(world,actor,movement,floor_versions):
			if int(movement.cursor)<movement.path.size() and movement.path[int(movement.cursor)].kind=="support_exit":
				movement.waiting_reason = "等待支撑设施离位通路恢复"
			else:
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
			_route_failures.erase(actor_id)
			if space.public_areas!=null: space.public_areas.changed(world)
			continue
		var segment: Dictionary = movement.path[int(movement.cursor)]
		if segment.kind == "connector":
			HospitalTransit.begin(space,world,actor,movement,segment)
			continue
		var result: MotionResult = _move_step(world,actor,movement,segment)
		# Door ownership retains its own wait; it never pushes the owner aside.
		if not result.door_id.is_empty(): continue
		if result.blocked:
			if int(movement.blocked_since) < 0:
				movement.blocked_since = world.facts.sim_tick
			elif int(world.facts.sim_tick) - int(movement.blocked_since) >= int(space.content.balance.movement_courtesy.blocked_before_yield_seconds) * 10:
				_yield(world,actor,movement,result)
	# Historic sweeps exist only during movement phase, never in later queries.
	_accepted_sweeps.clear()
	_sweep_index.expire_boundary()
	_movement_reservations = {}

func _move_step(world: WorldState, actor: Dictionary, movement: Dictionary, segment: Dictionary) -> MotionResult:
	var result: MotionResult = MotionResult.new()
	var target: Vector2 = Vector2(float(segment.cell[0]),float(segment.cell[1]))
	var start: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	var speed: float = float(space.content.balance.movement_speeds[str(space.clearance(actor))])
	var members: Array = movement.get("members",[actor.id])
	var offsets: Dictionary = movement.get("offsets",{})
	if members.size()>1: speed = float(space.content.balance.movement_speeds["2"])
	var next: Vector2 = start.move_toward(target,speed*WorldState.TICK_SECONDS)
	if next.distance_to(target)<0.001: next = target
	result.requested_motion = next-start
	var initial_rect: Rect2 = space._actor_index.rectangle(actor.id) if members.size()==1 else space._unit_rect(world,actor,start,members,offsets)
	var sweeps: Array[BodyIndex.Record] = _unit_sweeps(world,actor,next,members,offsets,target-start)
	var swept: Rect2 = initial_rect
	for sweep: BodyIndex.Record in sweeps: swept = swept.merge(sweep.sweep_from).merge(sweep.sweep_to)
	var doors: Array[Dictionary] = space.movement_doors(world,actor,swept,members)
	if not _reserve_doors(world,actor,movement,swept,doors,result): return result
	_movement_contacts(world,actor.id,int(actor.location.floor_id),swept,sweeps,members,result)
	if result.blocked: return result
	# Commit the complete fixed step only after the one collision attempt.
	# A rejected step keeps every member, facing and support height unchanged.
	movement.blocked_since = -1
	movement.erase("waiting_reason")
	actor.location.cell = [next.x,next.y]
	result.actual_motion = next-start
	_mark_door_use(world,int(actor.location.floor_id),swept,doors)
	if segment.kind=="support_exit":
		actor.location.height_m = move_toward(float(actor.location.get("height_m",0)),0.0,speed*HospitalSpace.CELL_METERS*WorldState.TICK_SECONDS)
	actor.facing = atan2(target.x-start.x,target.y-start.y)
	for member_id: String in members:
		if member_id==actor.id: continue
		var offset: Array = offsets[member_id]
		world.facts.actors[member_id].location.cell = [next.x+float(offset[0]),next.y+float(offset[1])]
		world.facts.actors[member_id].facing = actor.facing
	for sweep: BodyIndex.Record in sweeps:
		_accepted_sweeps[sweep.id] = sweep
		_sweep_index.update(sweep.id,int(actor.location.floor_id),sweep.sweep_from.merge(sweep.sweep_to))
		space._actor_index.update(sweep.id,int(actor.location.floor_id),sweep.sweep_to)
	if next.is_equal_approx(target):
		if segment.kind=="support_exit":
			actor.posture = "standing"
			actor.location.height_m = 0.0
			actor.erase("support_facility_id")
			space._sync_actor(world,actor.id)
			movement.path = []
			movement.cursor = -1
			_queue_route(world,movement)
		movement.travelled.append({"kind":"floor","floor_id":actor.location.floor_id,"cell":segment.cell.duplicate()})
		movement.cursor += 1
	return result

func _ensure_route_queue(world: WorldState) -> void:
	if _pending_world!=null and _pending_world.get_ref()==world: return
	_pending_world = weakref(world)
	_pending_routes.clear()
	_ready_routes = PlatformRouteQueue.new()
	_delayed_routes = PlatformRouteQueue.new()
	for id: String in world.facts.moves:
		if world.facts.moves[id].get("route_pending",false): _schedule_route(world,world.facts.moves[id])
	space.query_counts.route_dispatch_restores += 1

func _schedule_route(world: WorldState, movement: Dictionary) -> void:
	_pending_routes[movement.actor_id] = int(movement.request_sequence)
	if int(movement.get("route_retry_tick",0))>world.sim_tick:
		_delayed_routes.push({"id":movement.actor_id,"tick":int(movement.route_retry_tick),"sequence":int(movement.request_sequence)})
	else:
		_ready_routes.push({"id":movement.actor_id,"tick":int(movement.request_sequence)})

func _queue_route(world: WorldState, movement: Dictionary) -> void:
	_ensure_route_queue(world)
	world.facts.move_request_next = int(world.facts.get("move_request_next",0))+1
	movement.request_sequence = world.facts.move_request_next
	movement.route_pending = true
	_schedule_route(world,movement)

func _checkpoint(actor: Dictionary) -> Dictionary:
	return {"kind":"floor","floor_id":int(actor.location.floor_id),"cell":actor.location.cell.duplicate()}

func _replan_goal(world: WorldState, movement: Dictionary, preserve_order: bool = false) -> void:
	HospitalTransit.cancel_waiting(world,movement)
	movement.erase("route_waypoint")
	movement.yielding = false
	movement.erase("yield_partner")
	_route_checks.erase(movement.actor_id)
	if not preserve_order:
		_queue_route(world,movement)
	else:
		_ensure_route_queue(world)
		_schedule_route(world,movement)

func _active_route_clear(world: WorldState, actor: Dictionary, movement: Dictionary, versions: Dictionary) -> bool:
	space.query_counts.route_checks += 1
	var sequence: int = int(movement.get("request_sequence",0))
	var record: Dictionary = _route_checks.get(actor.id,{})
	if record.is_empty() or int(record.sequence)!=sequence:
		var floors: Dictionary = {}
		var connections: Dictionary = {}
		for segment: Dictionary in movement.path.slice(int(movement.cursor)):
			if segment.kind=="connector": connections[segment.connector_id] = []
			else: floors[int(segment.floor_id)] = -1
		record = {"sequence":sequence,"floors":floors,"connections":connections,"bodies":{},"members":[],"offsets":{},"validated":false}
	var members: Array = movement.get("members",[actor.id])
	var offsets: Dictionary = movement.get("offsets",{})
	# Collision-index shapes are disposable when a read-only projection changes
	# its indexed world. A route instead owns the actual body facts it proved.
	var bodies: Dictionary = {actor.id:_route_body_basis(actor)}
	for id: String in members:
		if id!=actor.id: bodies[id] = _route_body_basis(world.facts.actors[id])
	var body_changed: bool = record.bodies!=bodies
	var formation_changed: bool = record.members!=members or record.offsets!=offsets
	var floor_changed: bool = false
	var connection_changed: bool = false
	for floor_id: int in record.floors:
		if not versions.has(floor_id): versions[floor_id] = space._navigation.floor_static_version(space,world,floor_id)
		if record.floors[floor_id]!=versions[floor_id]: floor_changed = true
	if not versions.has("connections"): versions.connections = {}
	for id: String in record.connections:
		if not versions.connections.has(id):
			var connection: Dictionary = world.facts.connectors.get(id,{})
			if connection.is_empty(): return false
			versions.connections[id] = [connection.definition_id,HospitalTransit.endpoints(connection).duplicate(),connection.anchor.duplicate(),connection.get("failed",false),connection.get("pending_failure",false)]
		if record.connections[id]!=versions.connections[id]: connection_changed = true
	if record.validated and not body_changed and not formation_changed and not floor_changed and not connection_changed: return true
	space.query_counts.route_revalidations += 1
	# Reasons count checks which actually revalidate. An unproved route counts
	# only as unvalidated; an existing proof can have several changed reasons.
	var reasons: Array[String] = []
	if not record.validated: reasons.append("unvalidated")
	else:
		if body_changed: reasons.append("body")
		if formation_changed: reasons.append("formation")
		if floor_changed: reasons.append("floor")
		if connection_changed: reasons.append("connection")
	for reason: String in reasons:
		var key: String = "route_revalidation_"+reason
		space.query_counts[key] = int(space.query_counts.get(key,0))+1
	var floor_id: int = int(actor.location.floor_id)
	var current: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	var queries: Dictionary = {}
	for segment: Dictionary in movement.path.slice(int(movement.cursor)):
		if segment.kind=="support_exit":
			# Leaving a support begins inside that owned support. Exclude only
			# its solid footprint; walls, edits and every other obstacle remain.
			var source: Dictionary = space._navigation.floor_source(space,world,floor_id).duplicate()
			source.facilities = source.facilities.duplicate()
			source.facilities.erase(actor.get("support_facility_id",""))
			var departure: RouteClearance = RouteClearance.new(space,world,actor,floor_id,members,offsets,false,source)
			var exit: Vector2 = Vector2(float(segment.cell[0]),float(segment.cell[1]))
			if not departure.sweep_reason(current,exit).is_empty(): return false
			current = exit
			continue
		if segment.kind=="connector":
			var connection: Dictionary = world.facts.connectors.get(segment.connector_id,{})
			if connection.is_empty() or int(segment.from)!=floor_id or not HospitalTransit.has_stop(connection,int(segment.from)) or not HospitalTransit.has_stop(connection,int(segment.to)) or not HospitalTransit.fits(space,world,connection,actor.id,members).ok or (HospitalTransit._lowering(connection) and int(segment.to)>=int(segment.from)):
				return false
			floor_id = int(segment.to)
			current = Vector2(float(connection.anchor[0]),float(connection.anchor[1]))
			continue
		if int(segment.floor_id)!=floor_id:
			return false
		var target: Vector2 = Vector2(float(segment.cell[0]),float(segment.cell[1]))
		if not queries.has(floor_id):
			queries[floor_id] = space.navigation.structural_clearance(world,actor,floor_id,members,offsets)
		if not (queries[floor_id] as RouteClearance).sweep_reason(current,target).is_empty():
			return false
		current = target
	record.validated = true
	record.members = members.duplicate()
	record.offsets = offsets.duplicate(true)
	record.bodies = bodies
	for id: int in record.floors: record.floors[id] = versions[id]
	for id: String in record.connections: record.connections[id] = versions.connections[id]
	_route_checks[actor.id] = record
	return true

func _route_body_basis(actor: Dictionary) -> Array:
	# RouteClearance uses integer width/depth clearance and posture-dependent
	# height; doors and connector fits also use the full standing dimensions.
	# Facing belongs to the exact collision sweep performed during movement.
	var body: Dictionary = space.body(actor)
	var posture: String = actor.get("posture","standing")
	return [actor.species_id,actor.get("body_binding_id",""),posture,float(body.width_m),float(body.depth_m),float(body.height_m),actor.get("support_facility_id","") if posture=="lying" else ""]

func _dispatch_routes(world: WorldState, present_at_start: int) -> void:
	_ensure_route_queue(world)
	while _delayed_routes.size()>0:
		var due: Dictionary = _delayed_routes.pop()
		if int(due.tick)>world.sim_tick:
			_delayed_routes.push(due)
			break
		if not _pending_routes.has(due.id) or int(_pending_routes[due.id])!=int(due.sequence): continue
		if not world.facts.moves.has(due.id):
			_pending_routes.erase(due.id)
			continue
		var movement: Dictionary = world.facts.moves[due.id]
		if not movement.get("route_pending",false):
			_pending_routes.erase(due.id)
			continue
		if int(movement.get("route_retry_tick",0))<=world.sim_tick:
			_ready_routes.push({"id":due.id,"tick":int(movement.request_sequence)})
	var budget: int = maxi(int(space.content.balance.pathfinding.minimum_actor_requests_per_tick),ceili(float(present_at_start)/float(space.content.balance.pathfinding.actors_per_request)))
	var dispatched: int = 0
	while dispatched<budget and _ready_routes.size()>0:
		space.query_counts.route_dispatch_scans += 1
		var item: Dictionary = _ready_routes.pop()
		var id: String = str(item.id)
		if not _pending_routes.has(id): continue
		if not world.facts.moves.has(id):
			_pending_routes.erase(id)
			continue
		var movement: Dictionary = world.facts.moves[id]
		if not movement.get("route_pending",false):
			_pending_routes.erase(id)
			continue
		if int(item.tick)!=int(movement.get("request_sequence",-1)): continue
		if int(movement.get("route_retry_tick",0))>world.sim_tick: continue
		dispatched += 1
		space.query_counts["route_dispatches"] = int(space.query_counts.get("route_dispatches",0))+1
		_pending_routes.erase(id)
		var waypoint: Dictionary = movement.get("route_waypoint",{})
		var floor_id: int = int(movement.target_floor) if waypoint.is_empty() else int(waypoint.floor_id)
		var cell: Array = movement.target_cell if waypoint.is_empty() else waypoint.cell
		var quote: Dictionary
		if waypoint.is_empty():
			quote = space.route(world,id,floor_id,cell,movement.get("members",[]),movement.get("offsets",{}))
		else:
			var actor: Dictionary = world.facts.actors[id]
			var start: Vector2i = Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1]))
			var goal: Vector2i = Vector2i(roundi(cell[0]),roundi(cell[1]))
			var actual: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
			var target: Vector2 = Vector2(float(cell[0]),float(cell[1]))
			quote = space._floor_route(world,actor,floor_id,start,goal,movement.get("members",[]),movement.get("offsets",{}))
			if quote.ok:
				var query: RouteClearance = RouteClearance.new(space,world,actor,floor_id,movement.get("members",[]),movement.get("offsets",{}),false,space._navigation.floor_source(space,world,floor_id))
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
			movement.route_retry_tick = world.sim_tick+int(space.content.balance.movement_courtesy.retry_hard_block_seconds)*10
			_queue_route(world,movement)
			if quote.get("status","")=="unreachable": _remember_failure(world,movement,str(quote.reason))
			else: _route_failures.erase(id)
			continue
		movement.path = quote.path
		if not waypoint.is_empty():
			movement.path.append_array(waypoint.continuation)
			movement.erase("route_waypoint")
		movement.cursor = 0
		movement.route_pending = false
		movement.erase("route_retry_tick")
		movement.erase("waiting_reason")
		_route_failures.erase(id)

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

# Only an obstacle actually encountered by this movement triggers a local
# detour. Future landings and queues do not enter this floor query.
func _queue_local_route(world: WorldState, actor: Dictionary, movement: Dictionary) -> void:
	var end: int = int(movement.cursor)
	while end+1<movement.path.size() and movement.path[end+1].kind=="floor" and int(movement.path[end+1].floor_id)==int(actor.location.floor_id):
		end += 1
	var target: Dictionary = movement.path[end]
	movement.route_waypoint = {"floor_id":int(actor.location.floor_id),"cell":target.cell.duplicate(),"continuation":movement.path.slice(end+1)}
	_queue_route(world,movement)

func _local_goal_occupied(world: WorldState, actor: Dictionary, movement: Dictionary, contact: MotionResult) -> bool:
	if contact.blocker_actor_ids.is_empty(): return false
	var end: int = int(movement.cursor)
	if end<0 or end>=movement.path.size(): return false
	var floor_id: int = int(actor.location.floor_id)
	while end+1<movement.path.size() and movement.path[end+1].kind=="floor" and int(movement.path[end+1].floor_id)==floor_id:
		end += 1
	var target: Dictionary = movement.path[end]
	if target.kind!="floor" or int(target.floor_id)!=floor_id: return false
	var origin: Vector2 = Vector2(float(target.cell[0]),float(target.cell[1]))
	var members: Array = [actor.id]
	for id: String in movement.get("members",[]):
		if id!=actor.id: members.append(id)
	var unavoidable: Array[Rect2] = []
	for id: String in members:
		var member: Dictionary = world.facts.actors[id]
		if member.get("posture","standing")=="lying": continue
		var dimensions: Dictionary = space.body(member)
		var width: Variant = dimensions.get("width_m")
		var depth: Variant = dimensions.get("depth_m")
		if not (width is float or width is int) or not (depth is float or depth is int): continue
		if not is_finite(float(width)) or not is_finite(float(depth)) or float(width)<=0.0 or float(depth)<=0.0: continue
		var side: float = minf(float(width),float(depth))/HospitalSpace.CELL_METERS
		var offset: Array = movement.get("offsets",{}).get(id,[0,0])
		var center: Vector2 = space._actor_rect(member,origin+Vector2(float(offset[0]),float(offset[1]))).get_center()
		unavoidable.append(Rect2(center-Vector2.ONE*side*0.5,Vector2.ONE*side))
	# Every upright facing's collision AABB contains this centered square.
	# Current-facing corners alone do not prove an alternative approach blocked.
	# An actual collision triggered this decision. A different current body
	# may occupy the destination; every detour would still meet it there.
	# The current body index excludes past sweeps and member-to-member gaps.
	for rectangle: Rect2 in unavoidable:
		if not space._actor_index.intersects(floor_id,rectangle,actor.id,members): continue
		space.query_counts["local_goal_occupied_waits"] = int(space.query_counts.get("local_goal_occupied_waits",0))+1
		return true
	return false

func _unit_sweeps(world: WorldState, actor: Dictionary, next: Vector2, members: Array, offsets: Dictionary, direction: Vector2) -> Array[BodyIndex.Record]:
	var result: Array[BodyIndex.Record] = []
	for id: String in members:
		var member: Dictionary = world.facts.actors[id]
		var offset: Array = offsets.get(id,[0,0])
		var sweep: BodyIndex.Record = space._actor_index.record(id)
		var from: Rect2 = sweep.rect
		var position: Vector2 = next+Vector2(float(offset[0]),float(offset[1]))
		var facing: float = atan2(direction.x,direction.y)
		var to: Rect2
		if facing==float(member.facing):
			# Derive the destination from the actual position and cached shape.
			# Repeatedly translating the old float32 rectangle drifts away from
			# the actor's body and can miss an exact edge-crossing collision.
			to = space._actor_rect(member,position)
		else:
			var sample: Dictionary = member.duplicate()
			sample.facing = facing
			to = space._actor_rect(sample,position)
		sweep.sweep_from = from
		sweep.sweep_to = to
		result.append(sweep)
	return result

func _movement_contacts(world: WorldState, actor_id: String, floor_id: int, broad: Rect2, sweeps: Array[BodyIndex.Record], members: Array, result: MotionResult) -> void:
	space._ensure_actor_index(world)
	var candidates: Dictionary = {}
	for id: String in space._actor_index.candidates(floor_id,broad,members):
		candidates[id] = true
	for id: String in _sweep_index.candidates(floor_id,broad,members):
		candidates[id] = true
	var ids: Array = candidates.keys()
	ids.sort()
	space.query_counts.movement_candidates += ids.size()
	var reservations: Array = space._reservation_regions(world,floor_id,broad)
	# Preserve all exact bodies, not the first broadphase rectangle. Courtesy
	# gives active units priority over idle staff, even if the latter sorts first.
	for id: String in ids:
		var other: BodyIndex.Record = _accepted_sweeps.get(id)
		var other_from: Rect2 = space._actor_index.rectangle(id) if other==null else other.sweep_from
		var other_to: Rect2 = other_from if other==null else other.sweep_to
		for sweep: BodyIndex.Record in sweeps:
			var envelope: Rect2 = sweep.sweep_from.merge(sweep.sweep_to)
			if envelope.intersects(other_from.merge(other_to),false) and BodySweep.intersects(sweep.sweep_from,sweep.sweep_to,other_from,other_to):
				result.blocker_actor_ids.append(id)
				break
	for region: Dictionary in reservations:
		var reservation: Dictionary = region.reservation
		if int(reservation.floor_id)!=floor_id or actor_id==reservation.actor_id or actor_id in reservation.get("staff_ids",[]) or reservation.actor_id in members or str(region.reservation_id) in result.reservation_ids:
			continue
		for sweep: BodyIndex.Record in sweeps:
			if BodySweep.intersects(sweep.sweep_from,sweep.sweep_to,region.rect,region.rect):
				result.reservation_ids.append(str(region.reservation_id))
				break
	result.reservation_ids.sort()

func _reserve_doors(world: WorldState, actor: Dictionary, movement: Dictionary, swept: Rect2, doors: Array[Dictionary], result: MotionResult) -> bool:
	var floor_id: int = int(actor.location.floor_id)
	for door: Dictionary in doors:
		var span: int = space._door_span(actor,door)
		for id: String in movement.get("members",[]): span = maxi(span,space._door_span(world.facts.actors[id],door))
		if not swept.intersects(space._door_rect(door,span),false):
			continue
		var quote: Dictionary = space.door_quote(world,actor,floor_id,door,movement.get("members",[]))
		if not quote.ok or not swept.intersects(space._door_rect(door,int(quote.span)),false):
			continue
		var current: Dictionary = world.facts.adaptations.get(door.id,{})
		if not current.is_empty() and current.actor_id!=actor.id:
			result.door_id = str(door.id)
			result.reservation_ids.append(str(door.id))
			return false
		var rect: Rect2 = space._door_rect(door,int(quote.span))
		var members: Array = movement.get("members",[actor.id])
		if not space._dynamic_clear(world,actor.id,floor_id,rect,members):
			result.door_id = str(door.id)
			return false
		var reservation: Dictionary = {"kind":"door","owner_id":actor.id,"actor_id":actor.id,"staff_ids":members,"floor_id":floor_id,
			"span":quote.span,"clear_height_m":quote.clear_height_m,"clear_width_m":quote.clear_width_m,"regions":[[rect.position.x,rect.position.y,rect.size.x,rect.size.y]]}
		if current!=reservation:
			world.facts.adaptations[door.id] = reservation
			space.reservation_changed(world,str(door.id))
	return true

func _mark_door_use(world: WorldState, floor_id: int, swept: Rect2, doors: Array[Dictionary]) -> void:
	for door: Dictionary in doors:
		var current: Dictionary = world.facts.adaptations.get(door.id,{})
		if not current.is_empty() and swept.intersects(space._door_rect(door,int(current.span)),false):
			door.used = true

func _movement_owners(world: WorldState, blocker_actor_ids: Array[String]) -> Array:
	if blocker_actor_ids.is_empty(): return []
	if _phase_owners.is_empty():
		for primary: String in world.facts.moves:
			for id: String in world.facts.moves[primary].get("members",[primary]): _phase_owners[id] = primary
	var found: Dictionary = {}
	for id: String in blocker_actor_ids:
		# A group can finish and its former member start an individual journey
		# later in this same phase. Prefer that current owner over the old map.
		var owner: String = id if world.facts.moves.has(id) else str(_phase_owners.get(id,id))
		if world.facts.moves.has(owner) and id in world.facts.moves[owner].get("members",[owner]): found[owner] = true
	var result: Array = found.keys()
	result.sort()
	return result

func _route_occupancy(world: WorldState, actor: Dictionary, movement: Dictionary, floor_id: int) -> BodyIndex:
	var result: BodyIndex = BodyIndex.new()
	# A pending/local route may temporarily have no remaining cells. Its real
	# destination still cannot serve as the other body's waiting retreat.
	if int(movement.target_floor)==floor_id:
		result.update("goal",floor_id,space._unit_rect(world,actor,Vector2(float(movement.target_cell[0]),float(movement.target_cell[1])),movement.get("members",[]),movement.get("offsets",{})))
	for index: int in range(int(movement.cursor),movement.path.size()):
		var segment: Dictionary = movement.path[index]
		if segment.kind=="floor" and int(segment.floor_id)==floor_id:
			result.update(str(index),floor_id,space._unit_rect(world,actor,Vector2(float(segment.cell[0]),float(segment.cell[1])),movement.get("members",[]),movement.get("offsets",{})))
	return result

func _yield(world: WorldState, actor: Dictionary, movement: Dictionary, result: MotionResult) -> void:
	if movement.yielding or movement.travelled.is_empty():
		return
	space.query_counts.yield_attempts += 1
	var partner: String = ""
	for other_id: String in _movement_owners(world,result.blocker_actor_ids):
		space.query_counts.yield_candidates += 1
		if other_id==actor.id:
			continue
		var other: Dictionary = world.facts.actors[other_id]
		if other.location.kind!="floor" or int(other.location.floor_id)!=int(actor.location.floor_id):
			continue
		partner = other_id
		break
	if partner.is_empty():
		if _yield_idle_staff(world,actor,movement,result.blocker_actor_ids):
			return
		# A body may stop on a route after it was planned. Keep the goal and
		# request a current detour instead of waiting for a moving partner.
		if not _local_goal_occupied(world,actor,movement,result): _queue_local_route(world,actor,movement)
		return
	# A committed retreat keeps its winner until that winner finishes this move.
	# Re-evaluating priorities during the retreat creates mutual waiting cycles.
	if world.facts.moves[partner].yielding:
		var other_move: Dictionary = world.facts.moves[partner]
		if int(other_move.cursor)>=other_move.path.size():
			# Resolve this actual blockage once in the normal fair dispatcher.
			if not _local_goal_occupied(world,actor,movement,result): _queue_local_route(world,actor,movement)
		return
	if _has_priority(world,actor.id,partner):
		return
	var winner: Dictionary = world.facts.moves[partner]
	var occupied: BodyIndex = _route_occupancy(world,world.facts.actors[partner],winner,int(actor.location.floor_id))
	var current: Vector2i = Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1]))
	var seen: Dictionary = {}
	for index: int in range(movement.travelled.size()-1,-1,-1):
		var past: Dictionary = movement.travelled[index]
		if int(past.floor_id)!=int(actor.location.floor_id):
			continue
		var identity: Vector2 = Vector2(float(past.cell[0]),float(past.cell[1]))
		if seen.has(identity): continue
		seen[identity] = true
		if space.at(world,actor.id,int(actor.location.floor_id),past.cell):
			continue
		var cell: Vector2i = Vector2i(roundi(past.cell[0]),roundi(past.cell[1]))
		var actual: Vector2 = Vector2(float(past.cell[0]),float(past.cell[1]))
		var rect: Rect2 = space._unit_rect(world,actor,actual,movement.get("members",[]),movement.get("offsets",{}))
		if _narrow(world,actor,cell) or occupied.intersects(int(actor.location.floor_id),rect,"") or not space._dynamic_clear(world,actor.id,int(actor.location.floor_id),rect,movement.get("members",[])):
			continue
		var retreat: Dictionary = space._floor_route(world,actor,int(actor.location.floor_id),current,cell,movement.get("members",[]),movement.get("offsets",{}))
		if retreat.ok:
			movement.route_waypoint = {"floor_id":int(actor.location.floor_id),"cell":past.cell.duplicate(),"continuation":[]}
			_queue_route(world,movement)
			movement.yielding = true
			movement.yield_partner = partner
			return
	# A newly started task may meet another actor before it has any history to
	# retrace. Use the same local passing-space search as idle-staff courtesy.
	var members: Array = movement.get("members",[])
	var offsets: Dictionary = movement.get("offsets",{})
	var checker: RouteClearance = _courtesy_clearance(world,actor,members,offsets)
	for radius: int in range(1,5):
		for dx: int in range(-radius,radius+1):
			var dy_abs: int = radius-absi(dx)
			for dy: int in ([0] if dy_abs==0 else [-dy_abs,dy_abs]):
				var goal: Vector2i = current+Vector2i(dx,dy)
				if _narrow(world,actor,goal,checker) or not checker.reason(goal).is_empty(): continue
				var rect: Rect2 = space._unit_rect(world,actor,Vector2(goal),members,offsets)
				if not space._dynamic_clear(world,actor.id,int(actor.location.floor_id),rect,members): continue
				if occupied.intersects(int(actor.location.floor_id),rect,""): continue
				var retreat: Dictionary = space._floor_route(world,actor,int(actor.location.floor_id),current,goal,members,offsets)
				if not retreat.ok or retreat.get("status","")=="contention": continue
				movement.route_waypoint = {"floor_id":int(actor.location.floor_id),"cell":[goal.x,goal.y],"continuation":[]}
				_queue_route(world,movement)
				movement.yielding = true
				movement.yield_partner = partner
				return

func _yield_idle_staff(world: WorldState, actor: Dictionary, movement: Dictionary, blocker_actor_ids: Array[String]) -> bool:
	if blocker_actor_ids.is_empty(): return false
	var floor_id: int = int(actor.location.floor_id)
	var occupied: BodyIndex = _route_occupancy(world,actor,movement,floor_id)
	if occupied._records.is_empty(): occupied.update("goal",floor_id,space._actor_rect(actor,Vector2(float(movement.target_cell[0]),float(movement.target_cell[1]))))
	var candidates: Array[Dictionary] = []
	var responsibilities: Dictionary = {}
	for staff_id: String in blocker_actor_ids:
		if not world.facts.staff.has(staff_id): continue
		space.query_counts.yield_candidates += 1
		if world.facts.moves.has(staff_id) or not world.facts.actors.has(staff_id):
			continue
		var staff_actor: Dictionary = world.facts.actors[staff_id]
		if staff_actor.location.kind!="floor" or int(staff_actor.location.floor_id)!=floor_id or staff_actor.get("posture","standing")!="standing":
			continue
		if _staff_has_movement_responsibility(world,staff_id,responsibilities):
			continue
		var origin: Vector2i = Vector2i(roundi(staff_actor.location.cell[0]),roundi(staff_actor.location.cell[1]))
		var checker: RouteClearance = _courtesy_clearance(world,staff_actor)
		for radius: int in range(1,5):
			for dx: int in range(-radius,radius+1):
				var dy_abs: int = radius-absi(dx)
				for dy: int in ([0] if dy_abs==0 else [-dy_abs,dy_abs]):
					var goal: Vector2i = origin+Vector2i(dx,dy)
					if goal==origin or _narrow(world,staff_actor,goal,checker):
						continue
					var goal_rect: Rect2 = space._actor_rect(staff_actor,Vector2(goal))
					if occupied.intersects(floor_id,goal_rect,"") or not checker.reason(goal).is_empty():
						continue
					if not space._dynamic_clear(world,staff_id,floor_id,goal_rect):
						continue
					var destination: Dictionary = space._floor_route(world,staff_actor,floor_id,origin,goal)
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

func _staff_has_movement_responsibility(world: WorldState, staff_id: String, context: Dictionary = {}) -> bool:
	var staff: Dictionary = world.facts.staff.get(staff_id,{})
	if staff.is_empty() or HospitalClinicalDevelopment.safe_busy(world,staff_id):
		return true
	if not staff.get("base_task",{}).is_empty() or not str(staff.get("training_job_id","")).is_empty() or staff.get("life_task",{"phase":"idle"}).get("phase","idle")!="idle":
		return true
	if not context.has("owners"):
		var owners: Dictionary = {}
		for stay: Dictionary in world.facts.ward_stays.values():
			if not stay.get("phase","") in ["release_wait","complete"]:
				for id: String in [stay.get("nurse_id",""),stay.get("round_doctor_id",""),stay.get("escort_id","")]: owners[id] = true
		for reservation: Dictionary in world.facts.adaptations.values():
			owners[reservation.get("actor_id","")] = true
			for id: String in reservation.get("staff_ids",[]): owners[id] = true
		for reservation: Dictionary in world.facts.get("staff_life",{}).get("reservations",{}).values():
			for id: String in reservation.get("staff_ids",[]): owners[id] = true
		for job: Dictionary in world.facts.get("training_jobs",{}).values():
			if not HospitalClinicalDevelopment.terminal(job):
				owners[job.get("staff_id","")] = true
				owners[job.get("mentor_id","")] = true
		context.owners = owners
	return context.owners.has(staff_id)

func _courtesy_clearance(world: WorldState, actor: Dictionary, members: Array = [], offsets: Dictionary = {}) -> RouteClearance:
	var floor_id: int = int(actor.location.floor_id)
	# Borrow only resident, source-validated static geometry. Current members
	# and reservation permissions remain query-local; a miss builds no graph.
	var geometry: RouteClearance = space._navigation.cached_static_geometry(space,world,floor_id,actor)
	var counter: String = "courtesy_static_geometry_hits" if geometry!=null else "courtesy_static_geometry_misses"
	space.query_counts[counter] = int(space.query_counts.get(counter,0))+1
	return RouteClearance.new(space,world,actor,floor_id,members,offsets,true,space._navigation.floor_source(space,world,floor_id),geometry)

func _narrow(world: WorldState, actor: Dictionary, origin: Vector2i, checker: RouteClearance = null) -> bool:
	var available: int = 0
	if checker==null: checker = _courtesy_clearance(world,actor)
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
