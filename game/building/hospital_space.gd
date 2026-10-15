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

func _init(database: HospitalContent) -> void:
	content = database
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
	var layout: Dictionary = world.facts.floors.overrides.get(str(floor_id), {})
	if layout.is_empty():
		return false
	for plot: Array in layout.plots:
		if cell.x >= int(plot[0]) * 32 and cell.x < (int(plot[0]) + 1) * 32 and cell.y >= int(plot[1]) * 32 and cell.y < (int(plot[1]) + 1) * 32:
			return true
	return false

func static_reason(world: WorldState, actor: Dictionary, floor_id: int, origin: Vector2i, members: Array = [], offsets: Dictionary = {}) -> String:
	return RouteClearance.new(self,world,actor,floor_id,members,offsets,true,_navigation.floor_source(self,world,floor_id)).reason(origin)

func route(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false) -> Dictionary:
	var actor: Dictionary = world.facts.actors[actor_id]
	if actor.location.kind != "floor":
		return {"ok": false, "reason": "角色正在竖向通行或院外"}
	var start: Vector2i = Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1]))
	var goal: Vector2i = Vector2i(int(target[0]),int(target[1]))
	var source_floor: int = int(actor.location.floor_id)
	var actual: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	var stub: float = actual.distance_to(Vector2(start))
	if stub>0.0:
		var query: RouteClearance = RouteClearance.new(self,world,actor,source_floor,members,offsets,true,_navigation.floor_source(self,world,source_floor))
		var reason: String = query.sweep_reason(actual,Vector2(start))
		if not reason.is_empty():
			return {"ok":false,"status":"unreachable","reason":reason}
	var result: Dictionary = HospitalTransit.route(self,world,actor,source_floor,start,floor_id,goal,members,offsets,ignore_people,HospitalTransit.walking_ticks(self,actor,members,stub))
	if result.ok and stub>0.0:
		result.path.push_front({"kind":"floor","floor_id":source_floor,"cell":[start.x,start.y]})
		result.walking_distance += stub
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
	HospitalTransit.advance(self,world)
	_dispatch_routes(world,world.present_actor_count() if present_at_start<0 else present_at_start)
	for id: String in _route_checks.keys():
		if not world.facts.moves.has(id):
			_route_checks.erase(id)
	var clearance_queries: Dictionary = {}
	var floor_versions: Dictionary = {}
	var reserved_floors: Dictionary = {}
	for reservation: Dictionary in world.facts.adaptations.values():
		if reservation.kind=="facility":
			reserved_floors[int(reservation.floor_id)] = true
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
			var query: RouteClearance
			var floor_id: int = int(actor.location.floor_id)
			if members.size()<=1 and not reserved_floors.has(floor_id):
				var key: String = str(floor_id)+":"+str(actor.species_id)+":"+str(actor.get("body_binding_id",""))
				query = clearance_queries.get(key)
				if query==null:
					query = RouteClearance.new(self,world,actor,floor_id)
					clearance_queries[key] = query
			else:
				query = RouteClearance.new(self,world,actor,floor_id,members,offsets)
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

func _floor_route(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2i, goal: Vector2i, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false) -> Dictionary:
	var navigation: Dictionary = _navigation.query_graphs(self,world,floor_id,actor,members,offsets)
	var graph: FloorNavigation = navigation.graph
	var query: RouteClearance = RouteClearance.new(self,world,actor,floor_id,members,offsets,true,graph.geometry.source)
	var people: Callable = Callable()
	if not ignore_people:
		people = func(cell: Vector2i) -> bool: return _dynamic_clear(world,actor.id,floor_id,_unit_rect(world,actor,Vector2(cell),members,offsets),members)
	var result: Dictionary = graph.find_path(start,goal,query,Callable(),false,navigation.bases,navigation.shifts)
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
			for cell: Array in result.cells:
				if not bool(people.call(Vector2i(int(cell[0]),int(cell[1])))):
					blocked = true
					break
			if blocked:
				var alternative: Dictionary = graph.find_path(start,goal,query,people,false,navigation.bases,navigation.shifts)
				if alternative.ok:
					result = alternative
				else:
					result.status = "contention"
	if result.ok:
		var path: Array = []
		for cell: Array in result.cells:
			path.append({"kind":"floor","floor_id":floor_id,"cell":cell})
		result.path = path
		result.erase("cells")
	return result

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
		stamp.append([connection.definition_id,connection.stops,connection.anchor,connection.get("failed",false),connection.get("pending_failure",false)])
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
			queries[floor_id] = RouteClearance.new(self,world,actor,floor_id,members,offsets,true,_navigation.floor_source(self,world,floor_id))
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
		for reservation: Dictionary in world.facts.adaptations.values():
			if int(reservation.floor_id)!=floor_id or actor_id==reservation.actor_id or actor_id in reservation.get("staff_ids",[]) or reservation.actor_id in members:
				continue
			for area: Array in reservation.regions:
				var rect: Rect2 = Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3]))
				if BodySweep.intersects(sweep.sweep_from,sweep.sweep_to,rect,rect):
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
			shape.offset = Vector2(float(dimensions.width_m)*0.5,float(dimensions.height_m))/CELL_METERS
			shape.size = Vector2(float(dimensions.width_m),float(dimensions.height_m))/CELL_METERS
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

func _dynamic_clear(world: WorldState, actor_id: String, floor_id: int, rect: Rect2, members: Array = []) -> bool:
	_ensure_actor_index(world)
	for reservation: Dictionary in world.facts.adaptations.values():
		if int(reservation.floor_id)!=floor_id or actor_id==reservation.actor_id or actor_id in reservation.get("staff_ids",[]) or reservation.actor_id in members:
			continue
		for area: Array in reservation.regions:
			if rect.intersects(Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3])),false):
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

func support_anchor(world: WorldState, facility_id: String) -> Vector3:
	var facility: Dictionary = world.facts.facilities[facility_id]
	var anchor: Vector3 = content.asset_anchor(facility.definition_id,"patient_support")
	var layout: Dictionary = facility_layout(world,facility_id)
	anchor += Vector3(float(layout.footprint[0])-float(facility.footprint[0]),0,float(layout.footprint[1])-float(facility.footprint[1]))*CELL_METERS*0.5
	return anchor

func facility_quote(world: WorldState, facility_id: String, actor_id: String, staff_ids: Array = []) -> Dictionary:
	var facility: Dictionary = world.facts.facilities[facility_id]
	var actor: Dictionary = world.facts.actors[actor_id]
	var definition: Dictionary = content.facility_definition(facility.definition_id)
	if not definition.has("adapter_capacity"):
		return {"ok":true,"unchanged":true}
	var dimensions: Dictionary = body(actor)
	if clearance(actor)>int(definition.adapter_capacity.max_clearance_cells) or float(dimensions.height_m)>float(definition.adapter_capacity.max_height_m):
		return {"ok":false,"reason":"身体超过设备实际适配能力"}
	var depth: float = maxf(float(dimensions.depth_m),float(dimensions.height_m)) if facility.definition_id in ["EQ01","EQ05"] else float(dimensions.depth_m)
	var footprint: Array = [maxi(int(facility.footprint[0]),ceili(float(dimensions.width_m)/CELL_METERS)),maxi(int(facility.footprint[1]),ceili(depth/CELL_METERS))]
	if footprint==facility.footprint:
		return {"ok":true,"unchanged":true}
	var x: int = int(facility.cell[0])
	var y: int = int(facility.cell[1])
	var w: int = int(footprint[0])
	var h: int = int(footprint[1])
	var patient_cell: Array = [x,y+h]
	var operators: Array = []
	for index: int in staff_ids.size():
		var staff_size: int = clearance(world.facts.actors[staff_ids[index]])
		operators.append([x-staff_size,y+1] if index==0 else [x+w,y if index==1 else y+h-staff_size])
	var repair: Array = [x-1,y]
	var regions: Array = [[x,y,w,h],[x,y+h,clearance(actor),clearance(actor)],[repair[0],repair[1],1,1]]
	for index: int in operators.size():
		var k: int = clearance(world.facts.actors[staff_ids[index]])
		regions.append([operators[index][0],operators[index][1],k,k])
	var allowed: Array = [actor_id]+staff_ids
	var room: Dictionary = world.facts.rooms.get(facility.get("room_id",""),{})
	for area: Array in regions:
		var rect: Rect2 = Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3]))
		for cx: int in range(int(area[0]),int(area[0])+int(area[2])):
			for cy: int in range(int(area[1]),int(area[1])+int(area[3])):
				if not owned(world,int(facility.floor_id),Vector2i(cx,cy)) or [cx,cy] in world.facts.floors.overrides[str(facility.floor_id)].blocked:
					return {"ok":false,"reason":"展开或退出区域受墙、地块阻挡：%d,%d" % [cx,cy]}
		if not room.is_empty() and not room_contains(room,rect):
			return {"ok":false,"reason":"展开、岗位或出口超出本房间"}
		for other: Dictionary in world.facts.facilities.values():
			if other.id!=facility_id and int(other.floor_id)==int(facility.floor_id):
				var layout: Dictionary = facility_layout(world,other.id)
				if rect.intersects(Rect2(float(other.cell[0]),float(other.cell[1]),float(layout.footprint[0]),float(layout.footprint[1])),false):
					return {"ok":false,"reason":"展开区域有其他实际设施："+str(other.id)}
		for other: Dictionary in world.facts.actors.values():
			if not other.id in allowed and other.location.kind=="floor" and int(other.location.floor_id)==int(facility.floor_id) and rect.intersects(body_rectangle(other),false):
				return {"ok":false,"reason":"展开或操作区域有实际身体："+str(other.id)}
		if not _dynamic_clear(world,actor_id,int(facility.floor_id),rect,allowed):
			return {"ok":false,"reason":"展开区域与已有实际预约相交"}
	var quote: Dictionary = {"ok":true,"kind":"facility","facility_id":facility_id,"actor_id":actor_id,"staff_ids":staff_ids.duplicate(),"floor_id":facility.floor_id,
		"footprint":footprint,"patient_cell":patient_cell,"operator_cells":operators,"repair_cell":repair,"regions":regions}
	var candidate: WorldState = WorldState.new(world.freeze())
	candidate.facts.adaptations[facility_id] = quote
	for other: Dictionary in world.facts.actors.values():
		if other.id in allowed or other.location.kind!="floor" or int(other.location.floor_id)!=int(facility.floor_id):
			continue
		var start: Vector2i = Vector2i(roundi(other.location.cell[0]),roundi(other.location.cell[1]))
		var exit: Vector2i = Vector2i(47,93) if int(facility.floor_id)==1 else Vector2i(54,83)
		if _floor_route(world,other,int(facility.floor_id),start,exit,[],{},true).ok and not _floor_route(candidate,other,int(facility.floor_id),start,exit,[],{},true).ok:
			return {"ok":false,"reason":"展开会切断在院角色的安全出口："+str(other.id)}
	return quote

func room_contains(room: Dictionary, rect: Rect2) -> bool:
	if not room.has("cells"):
		return Rect2(float(room.origin[0]),float(room.origin[1]),float(room.size[0]),float(room.size[1])).encloses(rect)
	for x: int in range(floori(rect.position.x),ceili(rect.end.x)):
		for y: int in range(floori(rect.position.y),ceili(rect.end.y)):
			if not [x,y] in room.cells:
				return false
	return true

func reserve_facility(world: WorldState, facility_id: String, actor_id: String, owner_id: String, staff_ids: Array = []) -> String:
	var current: Dictionary = world.facts.adaptations.get(facility_id,{})
	if not current.is_empty():
		return "" if current.actor_id==actor_id else "等待原使用者实际离开后收拢"
	var quote: Dictionary = facility_quote(world,facility_id,actor_id,staff_ids)
	if not quote.ok:
		return quote.reason
	if quote.get("unchanged",false):
		return ""
	quote.erase("ok")
	quote.owner_id = owner_id
	world.facts.adaptations[facility_id] = quote
	_navigation.invalidate(world,int(quote.floor_id))
	return ""

func release_adaptations(world: WorldState) -> void:
	for id: String in world.ids("adaptations"):
		var reservation: Dictionary = world.facts.adaptations[id]
		var actor: Dictionary = world.facts.actors[reservation.actor_id]
		if reservation.kind=="facility" and (world.facts.tickets.has(reservation.owner_id) or world.facts.sessions.has(reservation.owner_id) or world.facts.preparations.has(reservation.owner_id) or world.facts.ward_stays.has(reservation.owner_id)):
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

func door_quote(world: WorldState, actor: Dictionary, floor_id: int, door: Dictionary) -> Dictionary:
	var dimensions: Dictionary = body(actor)
	var definition: Dictionary = content.definition("doors",door.definition_id)
	var span: int = maxi(int(door.span),ceili((maxf(float(dimensions.width_m),float(dimensions.depth_m))+0.1)/CELL_METERS))
	var height: float = maxf(float(definition.clear_height_m),float(dimensions.height_m)+0.1)
	var ceiling: float = 0.0
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
	for other: Dictionary in world.facts.floors.overrides[str(floor_id)].doors:
		if other.id!=door.id and opening.intersects(_door_rect(other,int(other.span)),false):
			return {"ok":false,"reason":"门展开与另一扇门相交"}
	for facility: Dictionary in world.facts.facilities.values():
		if int(facility.floor_id)==floor_id and opening.intersects(Rect2(float(facility.cell[0]),float(facility.cell[1]),float(facility.footprint[0]),float(facility.footprint[1])),false):
			return {"ok":false,"reason":"门展开区域有实际设施"}
	var k: int = clearance(actor)
	var before: Rect2 = Rect2(opening.position-Vector2(0,k),Vector2(span,k)) if door.axis=="x" else Rect2(opening.position-Vector2(k,0),Vector2(k,span))
	var wall_depth: int = 0 if room.has("wall_edges") else 1
	var after: Rect2 = Rect2(opening.position+Vector2(0,wall_depth),Vector2(span,k)) if door.axis=="x" else Rect2(opening.position+Vector2(wall_depth,0),Vector2(k,span))
	for side: Rect2 in [before,after]:
		for cx: int in range(int(side.position.x),int(side.end.x)):
			for cy: int in range(int(side.position.y),int(side.end.y)):
				if not owned(world,floor_id,Vector2i(cx,cy)) or [cx,cy] in world.facts.floors.overrides[str(floor_id)].blocked:
					return {"ok":false,"reason":"门两侧没有容纳真实身体的完整空间"}
		for facility: Dictionary in world.facts.facilities.values():
			var layout: Dictionary = facility_layout(world,facility.id)
			if int(facility.floor_id)==floor_id and side.intersects(Rect2(float(facility.cell[0]),float(facility.cell[1]),float(layout.footprint[0]),float(layout.footprint[1])),false):
				return {"ok":false,"reason":"门两侧通路有实际设施"}
	return {"ok":true,"span":span,"clear_height_m":height,"clear_width_m":maxf(float(definition.clear_width_m),maxf(float(dimensions.width_m),float(dimensions.depth_m))+0.1)}

func _door_rect(door: Dictionary, span: int) -> Rect2:
	return Rect2(float(door.cell[0]),float(door.cell[1]),float(span) if door.axis=="x" else 1.0,1.0 if door.axis=="x" else float(span))

func _potential_door_opening(world: WorldState, actor: Dictionary, floor_id: int, cell: Vector2i) -> bool:
	for door: Dictionary in world.facts.floors.overrides[str(floor_id)].get("doors",[]):
		var fit: Dictionary = door_quote(world,actor,floor_id,door)
		if fit.ok and _door_rect(door,int(fit.span)).has_point(Vector2(cell)):
			return true
	return false

func _reserve_doors(world: WorldState, actor: Dictionary, movement: Dictionary, swept: Rect2) -> bool:
	var floor_id: int = int(actor.location.floor_id)
	for door: Dictionary in world.facts.floors.overrides[str(floor_id)].get("doors",[]):
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
	return true

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
	if partner.is_empty() or _has_priority(world,actor.id,partner):
		return
	# A committed retreat keeps its winner until that winner finishes this move.
	# Re-evaluating priorities during the retreat creates mutual waiting cycles.
	if world.facts.moves[partner].yielding:
		var other_move: Dictionary = world.facts.moves[partner]
		if int(other_move.cursor)>=other_move.path.size() and int(movement.target_floor)==int(actor.location.floor_id):
			var detour: Dictionary = _floor_route(world,actor,int(actor.location.floor_id),
				Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1])),
				Vector2i(int(movement.target_cell[0]),int(movement.target_cell[1])),movement.get("members",[]),movement.get("offsets",{}))
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

func _narrow(world: WorldState, actor: Dictionary, origin: Vector2i) -> bool:
	var available: int = 0
	for offset: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		if static_reason(world,actor,int(actor.location.floor_id),origin+offset).is_empty():
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
