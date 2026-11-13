class_name HospitalTransit
extends RefCounted

const Lift = preload("res://game/building/lift_controller.gd")

const MAX_TICK: int = 9223372036854775807

static func _convoy(world: WorldState, primary_id: String) -> bool:
	return world.facts.moves.get(primary_id,{}).has("convoy")

# Only a complete group physically at the entrance can board.
static func walking_ticks(space: HospitalSpace, actor: Dictionary, members: Array, distance: float) -> int:
	# A queue shares its leader's real speed; the enlarged routing proxy is
	# only a clearance envelope and must not change walking time.
	return ceili(distance/space.walking_speed(actor)/WorldState.TICK_SECONDS)

static func has_stop(connection: Dictionary, floor_id: int) -> bool:
	if connection.has("first_floor"):
		return floor_id>=int(connection.first_floor) and floor_id<=int(connection.last_floor)
	for stop: Variant in connection.get("stops",[]):
		if (stop is int or stop is float) and float(stop)==float(floor_id):
			return true
	return false

static func endpoints(connection: Dictionary) -> Array:
	if connection.has("first_floor"):
		return [int(connection.first_floor),int(connection.last_floor)]
	return connection.get("stops",[])

static func _routing_candidates(world: WorldState, source: int, target: int) -> Dictionary:
	var candidates: Dictionary = {source:true,target:true}
	for key: String in world.facts.floors.overrides: candidates[int(key)] = true
	for other: Dictionary in world.facts.connectors.values():
		for floor_id: int in endpoints(other): candidates[floor_id] = true
	return candidates

static func routing_stops(connection: Dictionary, world: WorldState, source: int, target: int, candidates: Dictionary = {}) -> Array:
	if not connection.has("first_floor"): return connection.stops.duplicate()
	if candidates.is_empty(): candidates = _routing_candidates(world,source,target)
	candidates[int(connection.first_floor)] = true
	candidates[int(connection.last_floor)] = true
	var result: Array = []
	for floor_id: int in candidates:
		if has_stop(connection,floor_id): result.append(floor_id)
	result.sort()
	return result

static func fits(space: HospitalSpace, world: WorldState, connection: Dictionary, primary_id: String, members: Array) -> Dictionary:
	if _convoy(world,primary_id) and space.content.definition("vertical_connectors",connection.definition_id).kind!="stairs":
		var movement: Dictionary = world.facts.moves[primary_id]
		var plan: Dictionary = ConvoyPortal.plan(space,world,connection,primary_id,movement.members,movement.convoy)
		return {"ok":plan.ok,"reason":plan.reason,"cabin_positions":{},"plan":plan}
	var definition: Dictionary = space.content.definition("vertical_connectors",connection.definition_id)
	var ids: Array = members if not members.is_empty() else [primary_id]
	if ids.size()>int(definition.max_group_size):
		return {"ok":false,"reason":"竖向连接不能容纳完整通行组"}
	var sizes: Array[int] = []
	var positions: Dictionary = {}
	for id: String in ids:
		var actor: Dictionary = world.facts.actors[id]
		var body: Dictionary = space.body(actor)
		var k: int = space.clearance(actor)
		if k>int(definition.max_clearance_cells) or maxf(float(body.width_m),float(body.depth_m))+0.1>float(definition.clear_width_m) or float(body.height_m)+0.1>float(definition.clear_height_m):
			return {"ok":false,"reason":"竖向连接净宽、净高不足"}
		sizes.append(k)
	if definition.kind=="lift":
		var cabin: Array = definition.cabin_size
		if sizes.size()==1 and (sizes[0]>int(cabin[0]) or sizes[0]>int(cabin[1])):
			return {"ok":false,"reason":"轿厢不能容纳真实身体"}
		if sizes.size()==2 and not ((sizes[0]+sizes[1]<=int(cabin[0]) and maxi(sizes[0],sizes[1])<=int(cabin[1])) or (sizes[0]+sizes[1]<=int(cabin[1]) and maxi(sizes[0],sizes[1])<=int(cabin[0]))):
			return {"ok":false,"reason":"轿厢不能合法摆放完整通行组"}
		positions[ids[0]] = [0,0]
		if sizes.size()==2:
			positions[ids[1]] = [sizes[0],0] if sizes[0]+sizes[1]<=int(cabin[0]) else [0,sizes[0]]
	return {"ok":true,"reason":"","cabin_positions":positions}

static func quote(space: HospitalSpace, world: WorldState, connection: Dictionary, actor_id: String, from: int, to: int, at_landing: int, members: Array = [], offsets: Dictionary = {}) -> Dictionary:
	if not has_stop(connection,from) or not has_stop(connection,to) or not fits(space,world,connection,actor_id,members).ok:
		return _unavailable("竖向连接或完整身体不兼容")
	return _quote_known_fit(space,world,connection,actor_id,from,to,at_landing,members,offsets,{})

static func _quote_known_fit(space: HospitalSpace, world: WorldState, connection: Dictionary, actor_id: String, from: int, to: int, at_landing: int, members: Array, offsets: Dictionary, prefixes: Dictionary, egresses: Variant = null) -> Dictionary:
	if connection.has("lift_control_version"):
		return preload("res://game/building/lift_estimate.gd").quote(space,world,connection,actor_id,from,to,at_landing,members,offsets)
	var definition: Dictionary = space.content.definition("vertical_connectors",connection.definition_id)
	if definition.kind=="stairs" and absi(to-from)!=1:
		return _unavailable("楼梯只连接相邻楼层")
	if _lowering(connection) and to>=from:
		return _unavailable("故障电梯仅提供向下安全缓降")
	# The route caller fixes world, actor, group and offsets for this local map.
	# Prefixes for other actors and independent quotes retain fresh checks.
	var key: Array = [connection.id,to]
	var clear: bool
	if egresses!=null and egresses.has(key): clear = egresses[key]
	else:
		clear = egress_clear(space,world,connection,actor_id,to,members,offsets)
		if egresses!=null: egresses[key] = clear
	if not clear:
		return {"ok":false,"status":"estimate_unknown","reason":"目标出口当前被占用，暂时无法估计离舱时间"}
	if not prefixes.has(connection.id): prefixes[connection.id] = _prefix(space,world,connection,actor_id)
	var prefix: Dictionary = prefixes[connection.id]
	if not prefix.ok:
		return prefix
	var empty: int = _travel_ticks(space,connection,int(prefix.floor_id),from) if definition.kind=="lift" else 0
	var group: int = _add(_unit_phase_ticks(space,world,connection,actor_id,"boarding"),_travel_ticks(space,connection,from,to))
	group = _add(group,_unit_phase_ticks(space,world,connection,actor_id,"alighting"))
	var arrival: int = _add(_add(maxi(at_landing,int(prefix.ticks)),empty),group)
	if arrival<0:
		return _unavailable("交通预计超出可表示的模拟时间")
	return {"ok":true,"status":"complete","arrival_ticks":arrival,"queue_ticks":maxi(0,int(prefix.ticks)-at_landing),"empty_ticks":empty,"group_ticks":group,"quoted_tick":world.sim_tick,"reason":""}

static func _prefix(space: HospitalSpace, world: WorldState, connection: Dictionary, querying_actor: String) -> Dictionary:
	if connection.has("lift_control_version"):
		if connection.passenger_groups.is_empty() and connection.landing_queues.values().all(func(line:Array)->bool:return line.is_empty()):
			return {"ok":true,"status":"complete","ticks":int(connection.remaining_ticks),"floor_id":int(connection.to) if connection.phase=="empty_riding" else int(connection.floor_id),"reason":""}
		return {"ok":false,"status":"estimate_unknown","reason":"多目的地电梯按实际队列运行，当前交通预计尚不可确定"}
	var definition: Dictionary = space.content.definition("vertical_connectors",connection.definition_id)
	var ticks: int = 0
	var floor_id: int = int(connection.floor_id)
	if connection.phase!="idle":
		ticks = int(connection.remaining_ticks)
		if connection.phase in ["boarding","alighting"]:
			ticks = _unit_phase_ticks(space,world,connection,str(connection.get("primary_actor_id",connection.riders[0])),str(connection.phase),true)
		floor_id = int(connection.to)
		if connection.phase=="boarding":
			ticks = _add(ticks,int(connection.get("trip_travel_ticks",_travel_ticks(space,connection,int(connection.from),floor_id,true))))
		if connection.phase in ["boarding","riding"]:
			ticks = _add(ticks,_unit_phase_ticks(space,world,connection,str(connection.get("primary_actor_id",connection.riders[0])),"alighting"))
		if connection.phase in ["boarding","riding","alighting"]:
			var primary: String = connection.get("primary_actor_id",connection.riders[0])
			var movement: Dictionary = world.facts.moves.get(primary,{})
			if not egress_clear(space,world,connection,primary,floor_id,movement.get("members",[]),movement.get("offsets",{})):
				return {"ok":false,"status":"estimate_unknown","reason":"当前通行组尚无可用出口，暂时无法估计后续交通"}
	var queued: Array = _waiting(space,world,connection.id,false)
	while not queued.is_empty():
		_sort_waiting(world,queued,floor_id)
		var actor_id: String = queued.pop_front()
		var movement: Dictionary = world.facts.moves[actor_id]
		if actor_id==querying_actor:
			break
		var trip: Dictionary = journey(movement)
		if _lowering(connection) and int(trip.to)>=int(trip.from):
			continue
		if not egress_clear(space,world,connection,actor_id,int(trip.to),movement.get("members",[]),movement.get("offsets",{})):
			return {"ok":false,"status":"estimate_unknown","reason":"前方已到站通行组的出口暂不可用"}
		if definition.kind=="lift":
			ticks = _add(ticks,_travel_ticks(space,connection,floor_id,int(trip.from)))
		ticks = _add(ticks,_unit_phase_ticks(space,world,connection,actor_id,"boarding"))
		ticks = _add(ticks,_travel_ticks(space,connection,int(trip.from),int(trip.to)))
		ticks = _add(ticks,_unit_phase_ticks(space,world,connection,actor_id,"alighting"))
		floor_id = int(trip.to)
	return {"ok":ticks>=0,"status":"complete" if ticks>=0 else "unreachable","ticks":ticks,"floor_id":floor_id,"reason":"" if ticks>=0 else "交通工作量超出可表示的模拟时间"}

static func egress_clear(space: HospitalSpace, world: WorldState, connection: Dictionary, actor_id: String, floor_id: int, members: Array, offsets: Dictionary) -> bool:
	if _convoy(world,actor_id) and space.content.definition("vertical_connectors",connection.definition_id).kind!="stairs":
		var movement: Dictionary = world.facts.moves[actor_id]
		var plan: Dictionary = movement.convoy.get("portal",{}).get("plan",{})
		if plan.is_empty(): plan = ConvoyPortal.plan(space,world,connection,actor_id,movement.members,movement.convoy)
		if not plan.get("ok",false): return false
		var proxy: Dictionary = ConvoyTrail.proxy(world,movement)
		var shift: Vector2 = Vector2.ONE*float(movement.convoy.shift)
		var start: Vector2 = ConvoyTrail.point(plan.entry)+shift
		var end: Vector2 = ConvoyTrail.point(plan.egress)+shift
		var query: RouteClearance = space.navigation.structural_clearance(world,proxy,floor_id)
		if not query.sweep_reason(start,end).is_empty(): return false
		var envelope: Rect2 = Rect2(start,Vector2.ONE*float(movement.convoy.size)).merge(Rect2(end,Vector2.ONE*float(movement.convoy.size)))
		return space.nominal_query(world) or space._dynamic_clear(world,actor_id,floor_id,envelope,movement.members,false,true)
	var actor: Dictionary = world.facts.actors[actor_id]
	var anchor: Vector2i = Vector2i(int(connection.anchor[0]),int(connection.anchor[1]))
	if not space.static_reason(world,actor,floor_id,anchor,members,offsets).is_empty():
		return false
	if space.nominal_query(world): return true
	var ignored: Array = members if not members.is_empty() else [actor_id]
	for id: String in ignored:
		var offset: Array = offsets.get(id,[0,0])
		var rect: Rect2 = space._actor_rect(world.facts.actors[id],Vector2(anchor)+Vector2(float(offset[0]),float(offset[1])))
		if not space._dynamic_clear(world,actor_id,floor_id,rect,ignored,false,true):
			return false
	return true

static func reference_movements(world: WorldState) -> Dictionary:
	# An in-flight group still owns its known transport remainder and body
	# envelope. Nominal queries remove queued contention, not these inputs.
	var result: Dictionary = {}
	for connection: Dictionary in world.facts.connectors.values():
		if connection.has("lift_control_version"):
			for g: Dictionary in connection.passenger_groups:
				for owner: String in g.get("leader_ids",[g.actor_id]):
					var m: Dictionary=world.facts.moves.get(owner,{})
					result[owner]={"actor_id":owner,"members":m.get("members",[owner]),"offsets":m.get("offsets",{})}
					if m.has("convoy"): result[owner].convoy=m.convoy
			continue
		if not connection.phase in ["boarding","riding","alighting"]: continue
		var primary: String = str(connection.get("primary_actor_id",connection.riders[0]))
		var movement: Dictionary = world.facts.moves.get(primary,{})
		result[primary] = {"actor_id":primary,"members":movement.get("members",[]),"offsets":movement.get("offsets",{})}
		if movement.has("convoy"): result[primary].convoy = movement.convoy
	return result

# A proposed reservation can change these groups' exit permissions even when
# the querying patient's own body and destination stay unchanged.
static func route_participants(world: WorldState) -> Dictionary:
	var result: Dictionary = {}
	for primary: String in reference_movements(world):
		result[primary] = true
		for id: String in world.facts.moves.get(primary,{}).get("members",[]): result[id] = true
	for primary: String in world.facts.moves:
		var movement: Dictionary = world.facts.moves[primary]
		if not waiting(world,movement): continue
		result[primary] = true
		result[movement.actor_id] = true
		for id: String in movement.get("members",[]): result[id] = true
	return result

static func reference_conditions(world: WorldState) -> Dictionary:
	# Quote dependencies only. Wear receipts and completed
	# uses do not change geometry, lowering rules or the known transport prefix.
	var result: Dictionary = {}
	for id: String in world.facts.connectors:
		var connection: Dictionary = world.facts.connectors[id]
		var record: Dictionary = {}
		for field: String in ["id","definition_id","rotation","first_floor","last_floor","stops","cell","footprint","anchor","failed","pending_failure","floor_id","phase","remaining_ticks","from","to","trip_travel_ticks","riders","primary_actor_id","lift_control_version","direction","passenger_groups","landing_queues","active_group"]:
			if connection.has(field): record[field] = connection[field]
		result[id] = record
	return result

static func reference_basis(space: HospitalSpace, world: WorldState) -> Dictionary:
	# A known in-flight prefix also reads its complete group's exit envelope.
	# Actual waiting bodies and dynamic occupancy belong only to actual commitments.
	var movements: Dictionary = reference_movements(world)
	var bodies: Dictionary = {}
	for connection: Dictionary in world.facts.connectors.values():
		for id: String in connection.get("riders",[]):
			var actor: Dictionary = world.facts.actors[id]
			bodies[id] = {"body":space.body(actor),"posture":actor.get("posture","standing"),"facing":actor.facing}
	return {"connections":reference_conditions(world),"movements":movements,"bodies":bodies}

static func begin(space: HospitalSpace, world: WorldState, actor: Dictionary, movement: Dictionary, segment: Dictionary) -> void:
	var car: Dictionary=world.facts.connectors[segment.connector_id]
	if space.content.definition("vertical_connectors",car.definition_id).kind=="lift":
		Lift.ensure(car)
		if car.has("lift_control_version"):
			Lift.begin(space,world,actor,movement,segment)
			return
	if movement.has("convoy"):
		var connector: Dictionary = world.facts.connectors[segment.connector_id]
		if space.content.definition("vertical_connectors",connector.definition_id).kind=="stairs" and movement.members.size()==1:
			var saved: Dictionary = movement.convoy
			movement.erase("convoy")
			begin(space,world,actor,movement,segment)
			movement.convoy = saved
			space._sync_convoy(world,movement)
			return
		_begin_convoy(space,world,actor,movement,segment)
		return
	var connection: Dictionary = world.facts.connectors[segment.connector_id]
	var members: Array = movement.get("members",[actor.id])
	var offsets: Dictionary = movement.get("offsets",{})
	if not fits(space,world,connection,actor.id,members).ok or (_lowering(connection) and int(segment.to)>=int(segment.from)):
		space.movement._queue_route(world,movement)
		return
	var at_entry: bool=_at_landing(space,world,connection,movement,segment)
	# Ground recovery waits for boarding/arrival at this landing, not for
	# unrelated work to leave a globally idle car. Actual return still owns
	# collision checks and physical arrival.
	if not at_entry and not _landing_in_use(connection,int(segment.from)):
		space.movement._queue_route(world,movement,true)
		return
	if connection.phase!="idle":
		if int(connection.to)==int(segment.from) and connection.phase=="alighting":
			_stand_aside(space,world,connection,actor,movement,members,offsets)
		return
	var waiting: Array = _waiting(space,world,connection.id)
	var selected: String = str(waiting[0]) if not waiting.is_empty() else ""
	if selected!=actor.id:
		return
	var definition: Dictionary = space.content.definition("vertical_connectors",connection.definition_id)
	if definition.kind=="lift" and int(connection.floor_id)!=int(segment.from):
		connection.phase = "empty_riding"
		connection.from = connection.floor_id
		connection.to = segment.from
		connection.remaining_ticks = _travel_ticks(space,connection,int(connection.from),int(connection.to))
		return
	if not at_entry:
		space.movement.queue_waypoint(world,movement,int(segment.from),connection.anchor,true)
		return
	var travel: int = _travel_ticks(space,connection,int(segment.from),int(segment.to))
	if travel<0:
		movement.waiting_reason = "交通工作量超出可表示的模拟时间"
		return
	connection.phase = "boarding"
	connection.riders = members.duplicate()
	connection.primary_actor_id = actor.id
	connection.from = segment.from
	connection.to = segment.to
	connection.remaining_ticks = _boarding(definition)
	connection.trip_travel_ticks = travel
	connection.trip_receipt = "ride:%s:%s:%s" % [actor.id,movement.get("request_sequence",0),world.sim_tick]
	if int(connection.remaining_ticks)==0:
		connection.phase = "riding"
		connection.remaining_ticks = connection.trip_travel_ticks
	for id: String in members:
		world.facts.actors[id].location = {"kind":"transit","connector_id":connection.id,"from":segment.from,"to":segment.to}
		var placement: Dictionary = fits(space,world,connection,actor.id,members).cabin_positions
		if placement.has(id):
			world.facts.actors[id].location.cabin_cell = placement[id]
		space._sync_actor(world,id)
	movement.cursor += 1

# An empty car has no boarding/alighting body. Boarding keeps its source
# entrance, and a loaded arrival keeps its destination until safe release.
static func _landing_in_use(connection: Dictionary, floor_id: int) -> bool:
	return connection.phase=="boarding" and int(connection.from)==floor_id or connection.phase in ["boarding","riding","alighting"] and int(connection.to)==floor_id

# The route is the only journey intention. No ticket, reservation or queue token.
static func journey(movement: Dictionary) -> Dictionary:
	var path: Array = movement.get("route_waypoint",{}).get("continuation",movement.get("path",[]).slice(int(movement.get("cursor",0))))
	for segment: Dictionary in path:
		if segment.kind=="connector": return segment
	return {}

static func waiting(world: WorldState, movement: Dictionary) -> bool:
	if movement.is_empty() or movement.get("route_pending",false) or movement.has("local_move") or movement.has("detour"): return false
	var actor: Dictionary = world.facts.actors.get(movement.get("actor_id",""),{})
	if actor.get("location",{}).get("kind")!="floor": return false
	var cursor: int = int(movement.get("cursor",-1))
	var path: Array = movement.get("path",[])
	return cursor>=0 and cursor<path.size() and path[cursor].kind=="connector" and int(path[cursor].from)==int(actor.location.floor_id)

static func _at_landing(space: HospitalSpace, world: WorldState, connection: Dictionary, movement: Dictionary, trip: Dictionary) -> bool:
	if _lowering(connection) and int(trip.to)>=int(trip.from): return false
	var members: Array=movement.get("members",[movement.actor_id])
	if movement.has("convoy") and space.content.definition("vertical_connectors",connection.definition_id).kind!="stairs":
		var plan: Dictionary=ConvoyPortal.plan(space,world,connection,movement.actor_id,members,movement.convoy)
		return plan.ok and space.at(world,movement.actor_id,int(trip.from),plan.entry) and _convoy_entry_aligned(movement.convoy,plan)
	if not fits(space,world,connection,movement.actor_id,members).ok: return false
	var offsets: Dictionary=movement.get("offsets",{})
	for id: String in members:
		var offset: Array=offsets.get(id,[0,0])
		if not space.at(world,id,int(trip.from),[float(connection.anchor[0])+float(offset[0]),float(connection.anchor[1])+float(offset[1])]): return false
	return true

static func advance(space: HospitalSpace, world: WorldState) -> void:
	for id: String in world.ids("connectors"):
		var connection: Dictionary = world.facts.connectors[id]
		if space.content.definition("vertical_connectors",connection.definition_id).kind=="lift":
			Lift.ensure(connection)
			if connection.has("lift_control_version"):
				Lift.advance(space,world,connection)
				continue
		if connection.phase=="idle":
			_finish_failure(connection)
			continue
		var primary: String = str(connection.get("primary_actor_id",""))
		if not primary.is_empty() and world.facts.moves.get(primary,{}).get("convoy",{}).has("portal"):
			_advance_convoy(space,world,connection,world.facts.moves[primary])
			continue
		connection.remaining_ticks = maxi(0,int(connection.remaining_ticks)-1)
		if int(connection.remaining_ticks)>0:
			continue
		var definition: Dictionary = space.content.definition("vertical_connectors",connection.definition_id)
		match connection.phase:
			"empty_riding":
				connection.floor_id = connection.to
				connection.phase = "idle"
				_finish_failure(connection)
			"boarding":
				connection.phase = "riding"
				connection.remaining_ticks = int(connection.get("trip_travel_ticks",_travel_ticks(space,connection,int(connection.from),int(connection.to),true)))
				connection.erase("trip_travel_ticks")
			"riding":
				connection.phase = "alighting"
				connection.remaining_ticks = _alighting(definition)
		if connection.phase=="alighting" and int(connection.remaining_ticks)==0:
			_alight(space,world,connection)

static func _alight(space: HospitalSpace, world: WorldState, connection: Dictionary) -> void:
	var primary: String = connection.get("primary_actor_id",connection.riders[0])
	var movement: Dictionary = world.facts.moves[primary]
	var offsets: Dictionary = movement.get("offsets",{})
	if not egress_clear(space,world,connection,primary,int(connection.to),connection.riders,offsets):
		connection.remaining_ticks = 1
		return
	# If the original goal is now claimed, the actual landing must be a safe
	# waiting position. A clear landing still leaves the connector normally.
	if not space.movement._bed_goal_blocker(world,world.facts.actors[primary],movement).is_empty():
		for actor_id: String in connection.riders:
			var offset: Array=offsets.get(actor_id,[0,0])
			var body: Rect2=space._actor_rect(world.facts.actors[actor_id],ConvoyTrail.point(connection.anchor)+ConvoyTrail.point(offset))
			var held: String=space.bed_destination_blocker(world,primary,int(connection.to),body,connection.riders)
			if not held.is_empty():
				movement.waiting_reason="护理床岗位已有使用预约："+held
				connection.remaining_ticks=1
				return
	for actor_id: String in connection.riders:
		var offset: Array = offsets.get(actor_id,[0,0])
		world.facts.actors[actor_id].location = {"kind":"floor","floor_id":connection.to,"cell":[float(connection.anchor[0])+float(offset[0]),float(connection.anchor[1])+float(offset[1])]}
		space._sync_actor(world,actor_id)
	if movement.has("convoy"):
		movement.convoy.floor_id = int(connection.to)
		movement.convoy.points = [world.facts.actors[primary].location.cell.duplicate()]
		space._sync_convoy(world,movement)
	connection.floor_id = connection.to
	connection.used = true
	var definition: Dictionary = space.content.definition("vertical_connectors",connection.definition_id)
	if definition.kind=="lift":
		var receipt: String = str(connection.trip_receipt)
		if not connection.get("use_receipts",{}).has(receipt):
			if not connection.has("use_receipts"): connection.use_receipts = {}
			connection.use_receipts[receipt] = world.sim_tick
			for category: Dictionary in space.content.balance.equipment.classes:
				if category.id==definition.equipment_class: connection.condition = maxf(0.0,float(connection.get("condition",100.0))-float(category.wear_per_use))
	movement.travelled.append(space.movement._checkpoint(world.facts.actors[primary]))
	connection.phase = "idle"
	connection.riders = []
	connection.erase("trip_travel_ticks")
	connection.erase("primary_actor_id")
	connection.erase("trip_receipt")
	_finish_failure(connection)

# Only an actual retreat collision requests this connector-owned handoff.
# It does not make connector waiters generic locally movable bodies.
static func yield_to_retreat(space: HospitalSpace, world: WorldState, actor: Dictionary, movement: Dictionary, retreating: Dictionary, retreat: Dictionary, motion: Vector2) -> bool:
	return _yield_contact(space,world,actor,movement,retreating,retreat,motion)

static func _yield_contact(space: HospitalSpace, world: WorldState, actor: Dictionary, movement: Dictionary, retreating: Dictionary, retreat: Dictionary, motion: Vector2) -> bool:
	if actor.get("location",{}).get("kind")!="floor" or actor.get("posture")!="standing" or float(actor.location.get("height_m",0))!=0.0 or actor.has("support_facility_id"): return false
	if movement.is_empty() or movement.get("members",[actor.id])!=[actor.id] or not movement.get("offsets",{}).is_empty(): return false
	for key: String in ["convoy","detour","local_move","route_waypoint"]:
		if movement.has(key): return false
	if movement.get("route_pending",false): return false
	var cursor: int=int(movement.get("cursor",-1))
	var path: Array=movement.get("path",[])
	if cursor<0 or cursor>=path.size() or path[cursor].kind!="connector": return false
	var segment: Dictionary=path[cursor]
	var connection: Dictionary=world.facts.connectors.get(segment.connector_id,{})
	var floor_id: int=int(actor.location.floor_id)
	if connection.is_empty() or int(segment.from)!=floor_id or actor.id in connection.riders: return false
	if not waiting(world,movement): return false
	if retreating.get("location",{}).get("kind")!="floor" or int(retreating.location.floor_id)!=floor_id or retreating.get("posture")!="standing": return false
	if retreat.get("members",[retreating.id])!=[retreating.id] or retreat.has("convoy") or not bool(retreat.get("local_move",{}).get("retreat",false)): return false
	var target: Dictionary=retreat.get("local_move",{}).get("target",{})
	if target.get("kind")!="floor" or int(target.floor_id)!=floor_id: return false
	if not space.movement._local_floor_segment(retreating,retreat) or retreating.has("support_facility_id") or float(retreating.location.get("height_m",0))!=0.0: return false
	var owner: Dictionary={"connector_id":connection.id,"retreat_actor":retreating.id,"retreat_request":retreat.request_sequence,"retreat_target":target.cell.duplicate()}
	var service: Dictionary=_waiting_contact_exit(space,world,connection,floor_id)
	if not service.ok: return false
	var exit: Rect2=service.rect
	var retreat_body: Rect2=space._actor_rect(retreating,ConvoyTrail.point(retreating.location.cell))
	var corridor: Rect2=retreat_body.merge(space._actor_rect(retreating,ConvoyTrail.point(target.cell)))
	var actual: Vector2=ConvoyTrail.point(actor.location.cell)
	if motion.length()<0.001: return false
	var away: Vector2=Vector2(signf(motion.x),0) if absf(motion.x)>=absf(motion.y) else Vector2(0,signf(motion.y))
	var side: Vector2=Vector2(-away.y,away.x)
	var distance: float=float(space.clearance(actor))
	# A fixed local set; bodies still own every real step, not future space.
	for directions: Array in [[side],[-side],[away],[side,away],[-side,away],[away,side],[away,-side]]:
		var points: Array=[]
		var end: Vector2=actual
		for direction: Vector2 in directions:
			end+=direction*distance
			points.append({"kind":"floor","floor_id":floor_id,"cell":[end.x,end.y]})
		var rect: Rect2=_release_stop_rect(space,actor,end,directions[-1])
		if rect.intersects(exit,false) or rect.intersects(corridor,false): continue
		if not space._dynamic_clear(world,actor.id,floor_id,rect,[actor.id]): continue
		var public_space: bool=true
		for room: Dictionary in world.facts.rooms.values():
			if int(room.floor_id)==floor_id and rect.intersects(Rect2(float(room.origin[0]),float(room.origin[1]),float(room.size[0]),float(room.size[1])),false): public_space=false
		if not public_space: continue
		if not space.movement._bounded_prefix_clear(world,actor,movement,points): continue
		space.movement.queue_waypoint_prefix(world,movement,points,owner)
		return true
	return false

# Only the actual current service owner's envelope filters a proposed stop.
# This is not a reservation of a future passenger's body or corridor.
static func _waiting_contact_exit(space: HospitalSpace, world: WorldState, connection: Dictionary, floor_id: int) -> Dictionary:
	var exit: Rect2
	if _landing_in_use(connection,floor_id):
		var primary: String=connection.get("primary_actor_id","")
		var incoming: Dictionary=world.facts.moves.get(primary,{})
		if incoming.is_empty() or incoming.has("convoy") or not primary in connection.get("riders",[]) or not world.facts.actors.has(primary): return {"ok":false}
		exit=space._unit_rect(world,world.facts.actors[primary],ConvoyTrail.point(connection.anchor),connection.riders,incoming.get("offsets",{}))
	return {"ok":true,"rect":exit}

static func contact_owner_valid(space: HospitalSpace, world: WorldState, movement: Dictionary, binding: Dictionary) -> bool:
	var connection: Dictionary=world.facts.connectors.get(binding.connector_id,{})
	var actor: Dictionary=world.facts.actors[movement.actor_id]
	if connection.is_empty(): return false
	if binding.has("retreat_actor"):
		var root: Dictionary=world.facts.actors.get(binding.retreat_actor,{})
		var journey: Dictionary=world.facts.moves.get(binding.retreat_actor,{})
		var local: Dictionary=journey.get("local_move",{})
		if root.is_empty() or not space.movement._local_floor_segment(root,journey) or root.get("posture")!="standing" or root.has("support_facility_id") or float(root.location.get("height_m",0))!=0 or int(root.location.floor_id)!=int(actor.location.floor_id): return false
		if journey.get("request_sequence",-1)!=binding.retreat_request or journey.has("convoy") or journey.get("members",[root.id])!=[root.id] or not local.get("retreat",false): return false
		if local.get("target",{}).get("cell",[])!=binding.retreat_target or local.target.get("kind")!="floor" or int(local.target.get("floor_id",-1))!=int(actor.location.floor_id): return false
		var service: Dictionary=_waiting_contact_exit(space,world,connection,int(actor.location.floor_id))
		if not service.ok: return false
		var prefix: Array=movement.route_waypoint.prefix
		var previous: Vector2=ConvoyTrail.point(binding.origin) if prefix.size()==1 else ConvoyTrail.point(prefix[-2].cell)
		var endpoint: Vector2=ConvoyTrail.point(prefix[-1].cell)
		if _release_stop_rect(space,actor,endpoint,endpoint-previous).intersects(service.rect,false): return false
		var start: Vector2=ConvoyTrail.point(root.location.cell)
		var next: Vector2=space.movement._step_toward(start,ConvoyTrail.point(binding.retreat_target),space.walking_speed(root)*WorldState.TICK_SECONDS)
		if next==start: return false
		var sample: Dictionary=root.duplicate();sample.facing=atan2(next.x-start.x,next.y-start.y)
		var body: Rect2=space._actor_rect(actor,ConvoyTrail.point(actor.location.cell))
		return BodySweep.intersects(space._actor_rect(root,start),space._actor_rect(sample,next),body,body)
	return connection.get("trip_receipt","")==binding.get("trip_receipt","") and not str(binding.get("trip_receipt","")).is_empty() and int(connection.to)==int(actor.location.floor_id) and _landing_in_use(connection,int(actor.location.floor_id))

# Shape only; current static legality is checked at dispatch and real motion.
static func _release_prefix_shape(origin: Vector2, points: Array, distance: float) -> bool:
	if points.is_empty() or points.size()>2: return false
	var previous: Vector2=Vector2.ZERO
	for point: Dictionary in points:
		var target: Vector2=ConvoyTrail.point(point.cell)
		var delta: Vector2=target-origin
		if delta==Vector2.ZERO or delta.x!=0.0 and delta.y!=0.0: return false
		# Public-floor binary32 additions can round a clearance step slightly.
		if delta.length()>distance+0.00002: return false
		if previous!=Vector2.ZERO and previous.dot(delta)!=0.0: return false
		previous=delta
		origin=target
	return true

static func _release_stop_rect(space: HospitalSpace, actor: Dictionary, target: Vector2, direction: Vector2) -> Rect2:
	var sample: Dictionary=actor.duplicate()
	sample.facing=atan2(direction.x,direction.y)
	return space._actor_rect(sample,target)

static func _stand_aside(space: HospitalSpace, world: WorldState, connection: Dictionary, actor: Dictionary, movement: Dictionary, members: Array, offsets: Dictionary) -> void:
	var floor_id: int=int(actor.location.floor_id)
	if not space.at(world,actor.id,floor_id,connection.anchor):
		return
	var anchor: Vector2i = Vector2i(int(connection.anchor[0]),int(connection.anchor[1]))
	var exit: Rect2
	var incoming_id: String = connection.get("primary_actor_id",connection.riders[0])
	var incoming: Dictionary = world.facts.moves[incoming_id]
	if incoming.has("convoy"):
		var plan: Dictionary=incoming.convoy.get("portal",{}).get("plan",{})
		if plan.is_empty(): return
		var shift: Vector2=Vector2.ONE*float(incoming.convoy.shift)
		var size: Vector2=Vector2.ONE*float(incoming.convoy.size)
		exit=Rect2(ConvoyTrail.point(plan.entry)+shift,size).merge(Rect2(ConvoyTrail.point(plan.egress)+shift,size))
	else:
		exit=space._unit_rect(world,world.facts.actors[incoming_id],Vector2(anchor),connection.riders,incoming.get("offsets",{}))
	for radius: int in range(1,192):
		# In-bounds cells sort by y then x under the original y*96+x key.
		# Generate that order directly; discarded off-floor points cannot win.
		for y: int in range(maxi(0,anchor.y-radius),mini(96,anchor.y+radius+1)):
			var dx: int = radius-absi(y-anchor.y)
			for side: int in range(1 if dx==0 else 2):
				var cell: Vector2i = Vector2i(anchor.x-dx if side==0 else anchor.x+dx,y)
				if cell.x<0 or cell.x>=96:
					continue
				# Both planners use orthogonal floor legs. Cover current and either
				# final orientation only to filter stops, never to reserve space.
				var rect: Rect2=space._unit_rect(world,actor,Vector2(cell),members,offsets)
				for approach: float in [0.0,PI*0.5]:
					rect=rect.merge(_unit_at_facing(space,world,actor,Vector2(cell),members,offsets,approach))
				if rect.intersects(exit,false) or not space.static_reason(world,actor,floor_id,cell,members,offsets).is_empty() or not space._dynamic_clear(world,actor.id,floor_id,rect,members):
					continue
				var public_space: bool = true
				for room: Dictionary in world.facts.rooms.values():
					if int(room.floor_id)==floor_id and rect.intersects(Rect2(float(room.origin[0]),float(room.origin[1]),float(room.size[0]),float(room.size[1])),false):
						public_space = false
				if not public_space:
					continue
				var path: Dictionary=space._floor_route(world,actor,floor_id,anchor,cell,members,offsets)
				if not path.ok: continue
				space.movement.queue_waypoint(world,movement,floor_id,[cell.x,cell.y],true)
				return

static func _unit_at_facing(space: HospitalSpace, world: WorldState, actor: Dictionary, origin: Vector2, members: Array, offsets: Dictionary, facing: float) -> Rect2:
	var sample: Dictionary=actor.duplicate();sample.facing=facing
	var rect: Rect2=space._actor_rect(sample,origin)
	# _move_step rotates every non-convoy member to the same actual leg.
	# Current valid saves require groups to use convoy, whose portal branch
	# above already supplies its complete authoritative envelope.
	for id: String in members:
		if id==actor.id: continue
		sample=world.facts.actors[id].duplicate();sample.facing=facing
		rect=rect.merge(space._actor_rect(sample,origin+ConvoyTrail.point(offsets[id])))
	return rect

# Only a structural routing failure ends this optional local approach.
# Dynamic contact and a temporarily unavailable side step never call this.
static func _waiting(space: HospitalSpace, world: WorldState, connector_id: String, _available_only: bool = true) -> Array:
	var result: Array = []
	var connection: Dictionary = world.facts.connectors[connector_id]
	for id: String in world.ids("moves"):
		var movement: Dictionary = world.facts.moves[id]
		if not waiting(world,movement): continue
		var trip: Dictionary = journey(movement)
		if trip.get("connector_id","")==connector_id and _at_landing(space,world,connection,movement,trip): result.append(id)
	_sort_waiting(world,result,int(connection.floor_id))
	return result

static func _sort_waiting(world: WorldState, units: Array, floor_id: int) -> void:
	units.sort_custom(func(a: String,b: String) -> bool:
		var left: Dictionary = world.facts.moves[a]
		var right: Dictionary = world.facts.moves[b]
		var here_a: bool = int(journey(left).from)==floor_id
		var here_b: bool = int(journey(right).from)==floor_id
		if here_a!=here_b: return here_a
		var order_a: int = int(left.get("request_sequence",MAX_TICK))
		var order_b: int = int(right.get("request_sequence",MAX_TICK))
		return order_a<order_b if order_a!=order_b else a<b)

static func _travel_ticks(space: HospitalSpace, connection: Dictionary, from: int, to: int, committed: bool = false) -> int:
	var definition: Dictionary = space.content.definition("vertical_connectors",connection.definition_id)
	var seconds: float = float(definition.travel_seconds_per_floor)
	if _lowering(connection) and not committed:
		seconds = float(space.content.balance.floors.emergency_travel_seconds_per_floor)
	var per_floor: int = ceili(seconds/WorldState.TICK_SECONDS)
	var distance: int = absi(to-from)
	return -1 if distance>MAX_TICK/per_floor else distance*per_floor

static func _lowering(connection: Dictionary) -> bool:
	return connection.get("failed",false) or connection.get("pending_failure",false)

static func _finish_failure(connection: Dictionary) -> void:
	if connection.get("pending_failure",false):
		connection.failed = true
		connection.pending_failure = false

static func _boarding(definition: Dictionary) -> int:
	return ceili(float(definition.boarding_seconds)/WorldState.TICK_SECONDS)

static func _alighting(definition: Dictionary) -> int:
	return ceili(float(definition.alighting_seconds)/WorldState.TICK_SECONDS)

static func _add(a: int, b: int) -> int:
	return -1 if a<0 or b<0 or a>MAX_TICK-b else a+b

static func _unavailable(reason: String) -> Dictionary:
	return {"ok":false,"status":"unreachable","reason":reason}

static func _begin_convoy(space: HospitalSpace, world: WorldState, actor: Dictionary, movement: Dictionary, segment: Dictionary) -> void:
	var connection: Dictionary=world.facts.connectors[segment.connector_id]
	var plan: Dictionary=ConvoyPortal.plan(space,world,connection,actor.id,movement.members,movement.convoy)
	if not plan.ok:
		movement.waiting_reason=plan.reason
		return
	if _lowering(connection) and int(segment.to)>=int(segment.from):
		movement.waiting_reason="故障电梯仅提供向下安全缓降"
		return
	var at_entry: bool=space.at(world,actor.id,int(segment.from),plan.entry) and _convoy_entry_aligned(movement.convoy,plan)
	if not at_entry and not _landing_in_use(connection,int(segment.from)):
		movement.waiting_reason="登梯前队列尚未沿入口成一直线"
		# The regular route planner brings the real trail back through the
		# canonical outside approach; the complete group boards only on physical arrival.
		space.movement._queue_route(world,movement,true)
		return
	if connection.phase!="idle":
		if int(connection.to)==int(segment.from) and connection.phase=="alighting":
			_stand_aside_convoy(space,world,connection,actor,movement,plan)
		return
	var waiting: Array=_waiting(space,world,connection.id)
	var selected: String = str(waiting[0]) if not waiting.is_empty() else ""
	if selected!=actor.id:
		return
	if int(connection.floor_id)!=int(segment.from):
		connection.phase="empty_riding"
		connection.from=connection.floor_id
		connection.to=segment.from
		connection.remaining_ticks=_travel_ticks(space,connection,int(connection.from),int(connection.to))
		return
	if not at_entry:
		space.movement.queue_waypoint(world,movement,int(segment.from),plan.entry,true)
		return
	var travel: int=_travel_ticks(space,connection,int(segment.from),int(segment.to))
	if travel<0:
		movement.waiting_reason="交通工作量超出可表示的模拟时间"
		return
	connection.phase="boarding"
	connection.riders=movement.members.duplicate()
	connection.primary_actor_id=actor.id
	connection.from=segment.from
	connection.to=segment.to
	connection.remaining_ticks=_boarding(space.content.definition("vertical_connectors",connection.definition_id))
	connection.trip_travel_ticks=travel
	connection.trip_receipt = "ride:%s:%s:%s" % [actor.id,movement.get("request_sequence",0),world.sim_tick]
	movement.convoy.portal={"plan":plan,"cursor":0}
	var poses: Dictionary=ConvoyTrail.positions(movement.convoy,movement.members)
	for id: String in movement.members:
		world.facts.actors[id].location={"kind":"transit","connector_id":connection.id,"from":segment.from,"to":segment.to,"queue_cell":poses[id].cell}
		space._sync_actor(world,id)
	space._sync_convoy(world,movement)
	movement.cursor+=1

static func _advance_convoy(space: HospitalSpace, world: WorldState, connection: Dictionary, movement: Dictionary) -> void:
	var portal: Dictionary=movement.convoy.portal
	var definition: Dictionary=space.content.definition("vertical_connectors",connection.definition_id)
	connection.remaining_ticks=maxi(0,int(connection.remaining_ticks)-1)
	if connection.phase=="riding":
		if int(connection.remaining_ticks)>0: return
		connection.phase="alighting"
		connection.floor_id=connection.to
		connection.remaining_ticks=_alighting(definition)
		portal.cursor=0
		movement.convoy.floor_id=int(connection.to)
		space._sync_convoy(world,movement)
		return
	if connection.phase=="alighting" and not space.movement._bed_goal_blocker(world,world.facts.actors[movement.actor_id],movement).is_empty():
		var landed: Dictionary=ConvoyPortal.predict(movement.convoy,portal.plan,int(connection.to))
		for region: Rect2 in ConvoyTrail.regions(landed):
			var held: String=space.bed_destination_blocker(world,movement.actor_id,int(connection.to),region,movement.members)
			if not held.is_empty():
				movement.waiting_reason="护理床岗位已有使用预约："+held
				return
	var targets: Array=portal.plan.boarding if connection.phase=="boarding" else portal.plan.alighting
	if int(portal.cursor)<targets.size():
		space.movement._move_convoy_portal(world,world.facts.actors[movement.actor_id],movement,targets,int(connection.from) if connection.phase=="boarding" else int(connection.to),str(connection.id))
	if int(portal.cursor)<targets.size() or int(connection.remaining_ticks)>0: return
	if connection.phase=="boarding":
		connection.phase="riding"
		connection.remaining_ticks=int(connection.trip_travel_ticks)
		connection.erase("trip_travel_ticks")
		space._sync_convoy(world,movement)
		return
	var poses: Dictionary=ConvoyTrail.positions(movement.convoy,movement.members)
	for id: String in movement.members:
		world.facts.actors[id].location={"kind":"floor","floor_id":int(connection.to),"cell":poses[id].cell}
		space._sync_actor(world,id)
	movement.convoy.floor_id=int(connection.to)
	movement.convoy.erase("portal")
	connection.floor_id=connection.to
	connection.used=true
	var receipt: String=str(connection.trip_receipt)
	if not connection.get("use_receipts",{}).has(receipt):
		if not connection.has("use_receipts"): connection.use_receipts={}
		connection.use_receipts[receipt]=world.sim_tick
		for category: Dictionary in space.content.balance.equipment.classes:
			if category.id==definition.equipment_class: connection.condition=maxf(0.0,float(connection.get("condition",100.0))-float(category.wear_per_use))
	movement.travelled.append(space.movement._checkpoint(world.facts.actors[movement.actor_id]))
	connection.phase="idle"
	connection.riders=[]
	connection.erase("trip_travel_ticks")
	connection.erase("primary_actor_id")
	connection.erase("trip_receipt")
	space._sync_convoy(world,movement)
	_finish_failure(connection)

static func _unit_phase_ticks(space: HospitalSpace, world: WorldState, connection: Dictionary, primary: String, phase: String, remainder: bool=false) -> int:
	var definition: Dictionary=space.content.definition("vertical_connectors",connection.definition_id)
	var base: int=_boarding(definition) if phase=="boarding" else _alighting(definition)
	var movement: Dictionary=world.facts.moves.get(primary,{})
	if not movement.has("convoy") or definition.kind=="stairs": return int(connection.remaining_ticks) if remainder else base
	var portal: Dictionary=movement.convoy.get("portal",{})
	var p: Dictionary=portal.get("plan",{})
	if p.is_empty(): p=ConvoyPortal.plan(space,world,connection,primary,movement.members,movement.convoy)
	if not p.get("ok",true): return -1
	if not remainder: return int(p[phase+"_ticks"])
	var targets: Array=p[phase]
	if p.get("mode","")=="articulated":return maxi(int(connection.remaining_ticks),targets.size()-int(portal.get("cursor",0)))
	var trial: Dictionary=movement.convoy.duplicate(true)
	var cursor: int=int(portal.get("cursor",0))
	var speed: float=space.walking_speed(world.facts.actors[primary])*WorldState.TICK_SECONDS
	if speed<=0.0: return -1
	var ticks: int=0
	while cursor<targets.size():
		var proposal: Dictionary=ConvoyPortal.propose_step(trial,targets,cursor,speed)
		if not proposal.ok: return -1
		trial.points=proposal.points
		cursor=int(proposal.cursor)
		ticks+=1
	return maxi(int(connection.remaining_ticks),ticks)

# Admission requires the actual published trail, not a synthetic replacement,
# to match the canonical approach used by the cabin-path proof.
static func _convoy_entry_aligned(convoy: Dictionary, plan: Dictionary) -> bool:
	var entry: Vector2=ConvoyTrail.point(plan.entry)
	var inward: Vector2=ConvoyTrail.point(plan.inward)
	var span: float=float(convoy.spacing)*(convoy.centers.size()-1)
	if ConvoyTrail.point(convoy.points[-1]).distance_to(entry)>0.001: return false
	if ConvoyTrail.point(convoy.points[0]).distance_to(entry-inward*span)>0.001: return false
	var previous: float=-span-0.001
	for raw: Array in convoy.points:
		var delta: Vector2=ConvoyTrail.point(raw)-entry
		var along: float=delta.dot(inward)
		if absf(delta.cross(inward))>0.001 or along<previous-0.00001 or along>0.001: return false
		previous=along
	return true

# Same ground-side courtesy as _stand_aside: the current rider retains the
# connector; waiting groups clear the real exit. The leader requests
# an ordinary, collision-checked waypoint; no member pose is reassigned.
static func _stand_aside_convoy(space: HospitalSpace, world: WorldState, connection: Dictionary, actor: Dictionary, movement: Dictionary, plan: Dictionary) -> void:
	var incoming_id: String=str(connection.get("primary_actor_id",""))
	if incoming_id.is_empty() or incoming_id==actor.id: return
	var incoming: Dictionary=world.facts.moves.get(incoming_id,{})
	var exit: Rect2
	if incoming.has("convoy"):
		var incoming_plan: Dictionary=incoming.convoy.get("portal",{}).get("plan",{})
		if incoming_plan.is_empty(): return
		var incoming_shift: Vector2=Vector2.ONE*float(incoming.convoy.shift)
		var incoming_size: Vector2=Vector2.ONE*float(incoming.convoy.size)
		exit=Rect2(ConvoyTrail.point(incoming_plan.entry)+incoming_shift,incoming_size).merge(Rect2(ConvoyTrail.point(incoming_plan.egress)+incoming_shift,incoming_size))
	else:
		exit=space._unit_rect(world,world.facts.actors[incoming_id],ConvoyTrail.point(connection.anchor),connection.riders,incoming.get("offsets",{}))
	var obstructing: bool=false
	for region: Rect2 in ConvoyTrail.regions(movement.convoy):
		if region.intersects(exit,false): obstructing=true;break
	if not obstructing: return
	var inward: Vector2=ConvoyTrail.point(plan.inward)
	var side: Vector2=Vector2(-inward.y,inward.x)
	var axis: int=0 if side.x!=0 else 1
	var head: Vector2=ConvoyTrail.point(actor.location.cell)
	var shift: Vector2=Vector2.ONE*float(movement.convoy.shift)
	var size: float=float(movement.convoy.size)
	var span: float=float(movement.convoy.spacing)*(movement.members.size()-1)
	var proxy: Dictionary=ConvoyTrail.proxy(world,movement)
	var floor_id: int=int(actor.location.floor_id)
	var query: RouteClearance=space.navigation.structural_clearance(world,proxy,floor_id)
	var candidates: Array[Dictionary]=[]
	for direction: Vector2 in [side,-side]:
		var positive: bool=direction[axis]>0
		var distance: float=span+(exit.end[axis]-head[axis]-shift[axis] if positive else head[axis]+shift[axis]+size-exit.position[axis])
		distance=maxf(span+size,distance)
		var target: Vector2=head+direction*distance
		candidates.append({"target":target,"direction":direction,"distance":distance})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if not is_equal_approx(a.distance,b.distance): return a.distance<b.distance
		return a.target.y<b.target.y if a.target.y!=b.target.y else a.target.x<b.target.x)
	for candidate: Dictionary in candidates:
		var target: Vector2=candidate.target
		var end_trail: Rect2=Rect2(target+shift,Vector2.ONE*size).merge(Rect2(target-candidate.direction*span+shift,Vector2.ONE*size))
		if end_trail.intersects(exit,false) or not query.sweep_reason(head+shift,target+shift).is_empty(): continue
		var swept: Rect2=Rect2(head+shift,Vector2.ONE*size).merge(Rect2(target+shift,Vector2.ONE*size))
		if not space._dynamic_clear(world,actor.id,floor_id,swept,movement.members): continue
		var public_space: bool=true
		for room: Dictionary in world.facts.rooms.values():
			if int(room.floor_id)==floor_id and end_trail.intersects(Rect2(ConvoyTrail.point(room.origin),ConvoyTrail.point(room.size)),false): public_space=false;break
		if not public_space: continue
		space.movement.queue_waypoint(world,movement,floor_id,[target.x,target.y],true)
		return
