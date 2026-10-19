class_name HospitalMovement
extends RefCounted

var _space: WeakRef
var space: HospitalSpace:
	get: return _space.get_ref()

var _sweep_index: BodyIndex
var _accepted_sweeps: Dictionary = {}
var _route_checks: Dictionary = {}
var _movement_reservations: Dictionary = {}
var _world: WeakRef

func _init(geometry: HospitalSpace) -> void:
	_space = weakref(geometry)
	var cells: Array = geometry.content.balance.pathfinding.local_updates.chunk_cells
	_sweep_index = BodyIndex.new(Vector2(float(cells[0]),float(cells[1])))

func request_move(world: WorldState, actor_id: String, floor_id: int, target: Array) -> String:
	if world.facts.moves.has(actor_id):
		var previous: Dictionary = world.facts.moves[actor_id]
		if previous.target_floor!=floor_id or previous.target_cell!=target:
			var reason: String = space.navigation.destination_reason(world,world.facts.actors[actor_id],floor_id,Vector2i(roundi(target[0]),roundi(target[1])))
			if not reason.is_empty():
				return reason
			HospitalTransit.cancel_waiting(world,previous)
			previous.erase("route_waypoint")
			previous.target_floor = floor_id
			previous.target_cell = target.duplicate()
			previous.erase("route_retry_tick")
			if world.facts.actors[actor_id].location.kind=="transit":
				previous.replan_after_transit = true
			elif previous.path.is_empty() or int(previous.cursor)>=previous.path.size() or previous.path[int(previous.cursor)].kind!="support_exit":
				_replan_goal(world,previous,bool(previous.get("route_pending",false)))
		return previous.get("waiting_reason","")
	var actor: Dictionary = world.facts.actors[actor_id]
	if actor.location.kind!="floor":
		return "角色正在竖向通行或院外"
	if actor.get("posture","standing") == "lying":
		var facility: Dictionary = space.facility_layout(world,actor.support_facility_id)
		world.facts.moves[actor_id] = {"actor_id":actor_id,"path":[{"kind":"support_exit","floor_id":int(facility.floor_id),"cell":facility.patient_cell.duplicate()}],
			"cursor":0,"travelled":[_checkpoint(actor)],"blocked_since":-1,"yielding":false,"target_floor":floor_id,"target_cell":target.duplicate()}
		return ""
	var reason: String = space.navigation.destination_reason(world,actor,floor_id,Vector2i(roundi(target[0]),roundi(target[1])))
	if not reason.is_empty():
		return reason
	world.facts.moves[actor_id] = {"actor_id":actor_id,"path":[],"cursor":0,
		"travelled":[_checkpoint(actor)],"blocked_since":-1,"yielding":false,"target_floor":floor_id,"target_cell":target.duplicate()}
	_queue_route(world,world.facts.moves[actor_id])
	return ""

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
		if not space.at(world,id,int(actor.location.floor_id),[float(actor.location.cell[0])+float(offset[0]),float(actor.location.cell[1])+float(offset[1])]):
			return "等待完整陪同组到达真实配位"
	var reason: String = space.navigation.destination_reason(world,actor,floor_id,Vector2i(roundi(target[0]),roundi(target[1])),members,offsets)
	if not reason.is_empty():
		return reason
	world.facts.moves[primary_id] = {"actor_id":primary_id,"members":members.duplicate(),"offsets":offsets.duplicate(true),
		"path":[],"cursor":0,"travelled":[_checkpoint(actor)],"blocked_since":-1,"yielding":false,"target_floor":floor_id,"target_cell":target.duplicate()}
	_queue_route(world,world.facts.moves[primary_id])
	return ""

func advance(world: WorldState, present_at_start: int = -1) -> void:
	# Read-only facility projections can temporarily replace the geometry
	# index's world. They never replace this world's actual journeys.
	if _world==null or _world.get_ref()!=world:
		_route_checks.clear()
		_world = weakref(world)
	_sweep_index.begin_boundary(world.facts.actors)
	_accepted_sweeps.clear()
	space._ensure_actor_index(world)
	space.release_adaptations(world)
	_movement_reservations = space._build_reservation_view(world)
	HospitalTransit.advance(space,world)
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
		if movement.get("replan_after_transit",false) and actor.location.kind=="floor":
			movement.erase("replan_after_transit")
			_replan_goal(world,movement)
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
			HospitalTransit.begin(space,world,actor,movement,segment)
			continue
		var target: Vector2 = Vector2(float(segment.cell[0]),float(segment.cell[1]))
		var start: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
		var speed: float = float(space.content.balance.movement_speeds[str(space.clearance(actor))])
		var members: Array = movement.get("members",[actor_id])
		var offsets: Dictionary = movement.get("offsets",{})
		if members.size()>1:
			speed = float(space.content.balance.movement_speeds["2"])
		var next: Vector2 = start.move_toward(target,speed * WorldState.TICK_SECONDS)
		if next.distance_to(target)<0.001:
			next = target
		var initial_rect: Rect2 = space._actor_index.rectangle(actor_id) if members.size()==1 else space._unit_rect(world,actor,start,members,offsets)
		var sweeps: Array[BodyIndex.Record] = _unit_sweeps(world,actor,next,members,offsets,target-start)
		var swept: Rect2 = initial_rect
		for sweep: BodyIndex.Record in sweeps:
			swept = swept.merge(sweep.sweep_from).merge(sweep.sweep_to)
		if segment.kind!="support_exit":
			var floor_id: int = int(actor.location.floor_id)
			var query: RouteClearance = space.navigation.structural_clearance(world,actor,floor_id,members if members.size()>1 else [],offsets)
			if not _step_static_clear(world,actor,movement,next,query):
				continue
		if not _reserve_doors(world,actor,movement,swept):
			continue
		if not _movement_clear(world,actor_id,int(actor.location.floor_id),swept,sweeps,members):
			if int(movement.blocked_since) < 0:
				movement.blocked_since = world.facts.sim_tick
			elif int(world.facts.sim_tick) - int(movement.blocked_since) >= int(space.content.balance.movement_courtesy.blocked_before_yield_seconds) * 10:
				_yield(world,actor,movement,swept)
			continue
		movement.blocked_since = -1
		actor.location.cell = [next.x,next.y]
		_mark_door_use(world,int(actor.location.floor_id),swept)
		if segment.kind == "support_exit":
			actor.location.height_m = move_toward(float(actor.location.get("height_m",0)),0.0,speed*HospitalSpace.CELL_METERS*WorldState.TICK_SECONDS)
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
			space._actor_index.update(sweep.id,int(actor.location.floor_id),sweep.sweep_to)
		if next.is_equal_approx(target):
			if segment.kind == "support_exit":
				actor.posture = "standing"
				actor.location.height_m = 0.0
				actor.erase("support_facility_id")
				space._sync_actor(world,actor_id)
				movement.path = []
				movement.cursor = -1
				_queue_route(world,movement)
			movement.travelled.append({"kind":"floor","floor_id":actor.location.floor_id,"cell":segment.cell.duplicate()})
			movement.cursor += 1
	# Historic sweeps exist only during movement phase, never in later queries.
	_accepted_sweeps.clear()
	_sweep_index.expire_boundary()
	_movement_reservations = {}

func _queue_route(world: WorldState, movement: Dictionary) -> void:
	world.facts.move_request_next = int(world.facts.get("move_request_next",0))+1
	movement.request_sequence = world.facts.move_request_next
	movement.route_pending = true

func _checkpoint(actor: Dictionary) -> Dictionary:
	return {"kind":"floor","floor_id":int(actor.location.floor_id),"cell":actor.location.cell.duplicate()}

func _replan_goal(world: WorldState, movement: Dictionary, preserve_order: bool = false) -> void:
	HospitalTransit.cancel_waiting(world,movement)
	movement.erase("route_waypoint")
	movement.yielding = false
	movement.erase("yield_partner")
	_route_checks.erase(movement.actor_id)
	if not preserve_order: _queue_route(world,movement)

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
			versions[floor_id] = space._navigation.floor_version(space,world,floor_id)
	if record.get("simple",false) and int(record.token)==int(space._actor_shapes[actor.id].token) and int(record.version)==int(versions[record.floors[0]]):
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
	record.stamp = stamp.duplicate(true)
	record.simple = members.size()<=1 and record.connections.is_empty() and record.floors.size()==1
	if record.simple:
		record.token = space._actor_shapes[actor.id].token
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
	var budget: int = maxi(int(space.content.balance.pathfinding.minimum_actor_requests_per_tick),ceili(float(present_at_start)/float(space.content.balance.pathfinding.actors_per_request)))
	for index: int in mini(budget,pending.size()):
		var id: String = pending[index]
		var movement: Dictionary = world.facts.moves[id]
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

# Only an obstacle actually encountered by this movement triggers a local
# detour. Future landings and queues do not enter this floor query.
func _queue_local_route(world: WorldState, actor: Dictionary, movement: Dictionary) -> void:
	var end: int = int(movement.cursor)
	while end+1<movement.path.size() and movement.path[end+1].kind=="floor" and int(movement.path[end+1].floor_id)==int(actor.location.floor_id):
		end += 1
	var target: Dictionary = movement.path[end]
	movement.route_waypoint = {"floor_id":int(actor.location.floor_id),"cell":target.cell.duplicate(),"continuation":movement.path.slice(end+1)}
	_queue_route(world,movement)

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
			to = Rect2(from.position+position-Vector2(float(member.location.cell[0]),float(member.location.cell[1])),from.size)
		else:
			var sample: Dictionary = member.duplicate()
			sample.facing = facing
			to = space._actor_rect(sample,position)
		sweep.sweep_from = from
		sweep.sweep_to = to
		result.append(sweep)
	return result

func _movement_clear(world: WorldState, actor_id: String, floor_id: int, broad: Rect2, sweeps: Array[BodyIndex.Record], members: Array) -> bool:
	space._ensure_actor_index(world)
	if world.facts.adaptations.is_empty() and not space._actor_index.intersects(floor_id,broad,actor_id,members) and not _sweep_index.intersects(floor_id,broad,actor_id,members):
		return true
	var candidates: Dictionary = {}
	for id: String in space._actor_index.candidates(floor_id,broad,members):
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
			var other_from: Rect2 = space._actor_index.rectangle(id) if other==null else other.sweep_from
			var other_to: Rect2 = other_from if other==null else other.sweep_to
			if envelope.intersects(other_from.merge(other_to),false) and BodySweep.intersects(sweep.sweep_from,sweep.sweep_to,other_from,other_to):
				return false
		for region: Dictionary in space._reservation_regions(world,floor_id,envelope):
			var reservation: Dictionary = region.reservation
			if int(reservation.floor_id)!=floor_id or actor_id==reservation.actor_id or actor_id in reservation.get("staff_ids",[]) or reservation.actor_id in members:
				continue
			if BodySweep.intersects(sweep.sweep_from,sweep.sweep_to,region.rect,region.rect):
				return false
	return true

func _reserve_doors(world: WorldState, actor: Dictionary, movement: Dictionary, swept: Rect2) -> bool:
	var floor_id: int = int(actor.location.floor_id)
	for door: Dictionary in world.facts.floors.overrides.get(str(floor_id),{}).get("doors",[]):
		if not swept.intersects(space._door_rect(door,space._door_span(actor,door)),false):
			continue
		var quote: Dictionary = space.door_quote(world,actor,floor_id,door)
		if not quote.ok or not swept.intersects(space._door_rect(door,int(quote.span)),false):
			continue
		var current: Dictionary = world.facts.adaptations.get(door.id,{})
		if not current.is_empty() and current.actor_id!=actor.id:
			return false
		var rect: Rect2 = space._door_rect(door,int(quote.span))
		var members: Array = movement.get("members",[actor.id])
		if not space._dynamic_clear(world,actor.id,floor_id,rect,members):
			return false
		world.facts.adaptations[door.id] = {"kind":"door","owner_id":actor.id,"actor_id":actor.id,"staff_ids":members,"floor_id":floor_id,
			"span":quote.span,"clear_height_m":quote.clear_height_m,"clear_width_m":quote.clear_width_m,"regions":[[rect.position.x,rect.position.y,rect.size.x,rect.size.y]]}
		if not _movement_reservations.is_empty(): space._index_reservation(_movement_reservations,str(door.id),world.facts.adaptations[door.id])
	return true

func _mark_door_use(world: WorldState, floor_id: int, swept: Rect2) -> void:
	for door: Dictionary in world.facts.floors.overrides.get(str(floor_id),{}).get("doors",[]):
		var current: Dictionary = world.facts.adaptations.get(door.id,{})
		if not current.is_empty() and swept.intersects(space._door_rect(door,int(current.span)),false):
			door.used = true

func _step_static_clear(world: WorldState, actor: Dictionary, movement: Dictionary, next: Vector2, query: RouteClearance = null) -> bool:
	if query==null:
		query = RouteClearance.new(space,world,actor,int(actor.location.floor_id),movement.get("members",[]),movement.get("offsets",{}),false,space._navigation.floor_source(space,world,int(actor.location.floor_id)))
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
		var rect: Rect2 = space._unit_rect(world,other,Vector2(float(other.location.cell[0]),float(other.location.cell[1])),other_move.get("members",[]),other_move.get("offsets",{}))
		if swept.intersects(rect,false):
			partner = other_id
			break
	if partner.is_empty():
		if _yield_idle_staff(world,actor,movement,swept):
			return
		# A body may stop on a route after it was planned. Keep the goal and
		# request a current detour instead of waiting for a moving partner.
		_queue_local_route(world,actor,movement)
		return
	# A committed retreat keeps its winner until that winner finishes this move.
	# Re-evaluating priorities during the retreat creates mutual waiting cycles.
	if world.facts.moves[partner].yielding:
		var other_move: Dictionary = world.facts.moves[partner]
		if int(other_move.cursor)>=other_move.path.size():
			var detour: Dictionary
			if int(movement.target_floor)==int(actor.location.floor_id):
				detour = space._floor_route(world,actor,int(actor.location.floor_id),
					Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1])),
					Vector2i(int(movement.target_cell[0]),int(movement.target_cell[1])),movement.get("members",[]),movement.get("offsets",{}))
			else:
				# A person going upstairs must also route around the parked yielder.
				detour = space.route(world,actor.id,int(movement.target_floor),movement.target_cell,movement.get("members",[]),movement.get("offsets",{}))
			if detour.ok:
				_queue_local_route(world,actor,movement)
		return
	if _has_priority(world,actor.id,partner):
		return
	var current: Vector2i = Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1]))
	for index: int in range(movement.travelled.size()-1,-1,-1):
		var past: Dictionary = movement.travelled[index]
		if int(past.floor_id)!=int(actor.location.floor_id):
			continue
		if space.at(world,actor.id,int(actor.location.floor_id),past.cell):
			continue
		var cell: Vector2i = Vector2i(roundi(past.cell[0]),roundi(past.cell[1]))
		var actual: Vector2 = Vector2(float(past.cell[0]),float(past.cell[1]))
		if _narrow(world,actor,cell) or not space._dynamic_clear(world,actor.id,int(actor.location.floor_id),space._unit_rect(world,actor,actual,movement.get("members",[]),movement.get("offsets",{})),movement.get("members",[])):
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
	var checker: RouteClearance = RouteClearance.new(space,world,actor,int(actor.location.floor_id),members,offsets,true,space._navigation.floor_source(space,world,int(actor.location.floor_id)))
	var winner: Dictionary = world.facts.moves[partner]
	for radius: int in range(1,5):
		for dx: int in range(-radius,radius+1):
			var dy_abs: int = radius-absi(dx)
			for dy: int in ([0] if dy_abs==0 else [-dy_abs,dy_abs]):
				var goal: Vector2i = current+Vector2i(dx,dy)
				if _narrow(world,actor,goal,checker) or not checker.reason(goal).is_empty(): continue
				var rect: Rect2 = space._unit_rect(world,actor,Vector2(goal),members,offsets)
				if not space._dynamic_clear(world,actor.id,int(actor.location.floor_id),rect,members): continue
				var in_way: bool = false
				for segment: Dictionary in winner.path.slice(int(winner.cursor)):
					if segment.kind=="floor" and int(segment.floor_id)==int(actor.location.floor_id) and rect.intersects(space._unit_rect(world,world.facts.actors[partner],Vector2(float(segment.cell[0]),float(segment.cell[1])),winner.get("members",[]),winner.get("offsets",{})),false):
						in_way = true
						break
				if in_way: continue
				var retreat: Dictionary = space._floor_route(world,actor,int(actor.location.floor_id),current,goal,members,offsets)
				if not retreat.ok or retreat.get("status","")=="contention": continue
				movement.route_waypoint = {"floor_id":int(actor.location.floor_id),"cell":[goal.x,goal.y],"continuation":[]}
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
		var blocker_rect: Rect2 = space._actor_rect(staff_actor,Vector2(float(staff_actor.location.cell[0]),float(staff_actor.location.cell[1])))
		if not swept.intersects(blocker_rect,false) or _staff_has_movement_responsibility(world,staff_id):
			continue
		var origin: Vector2i = Vector2i(roundi(staff_actor.location.cell[0]),roundi(staff_actor.location.cell[1]))
		var checker: RouteClearance = RouteClearance.new(space,world,staff_actor,floor_id,[],{},true,space._navigation.floor_source(space,world,floor_id))
		for radius: int in range(1,5):
			for dx: int in range(-radius,radius+1):
				var dy_abs: int = radius-absi(dx)
				for dy: int in ([0] if dy_abs==0 else [-dy_abs,dy_abs]):
					var goal: Vector2i = origin+Vector2i(dx,dy)
					if goal==origin or _narrow(world,staff_actor,goal,checker):
						continue
					var goal_rect: Rect2 = space._actor_rect(staff_actor,Vector2(goal))
					var requester_path: bool = false
					for cell: Array in route_cells:
						if goal_rect.intersects(space._actor_rect(actor,Vector2(float(cell[0]),float(cell[1]))),false):
							requester_path = true
							break
					if requester_path or not checker.reason(goal).is_empty():
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
	if checker==null: checker = RouteClearance.new(space,world,actor,int(actor.location.floor_id),[],{},true,space._navigation.floor_source(space,world,int(actor.location.floor_id)))
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
