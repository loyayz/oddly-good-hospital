class_name HospitalTransit
extends RefCounted

const MAX_TICK: int = 9223372036854775807

# Queries only read the current transport facts. Tickets are created by begin(),
# after the complete movement unit actually reaches its departure landing.
static func route(space: HospitalSpace, world: WorldState, actor: Dictionary, source_floor: int, start: Vector2i, target_floor: int, goal: Vector2i, members: Array, offsets: Dictionary, ignore_people: bool, initial_ticks: int = 0) -> Dictionary:
	var direct: Dictionary = {"ok":false,"status":"unreachable","reason":"真实身体无法到达目标"}
	if source_floor==target_floor:
		direct = space._floor_route(world,actor,source_floor,start,goal,members,offsets,ignore_people)
		var delta: Vector2i = goal-start
		# With current unit floor costs, this attains the geometric lower bound.
		# A vertical detour cannot remove horizontal displacement or its own time.
		if direct.ok and int(direct.walking_distance)==absi(delta.x)+absi(delta.y):
			direct.arrival_ticks = _add(initial_ticks,walking_ticks(space,actor,members,float(direct.walking_distance)))
			direct.quoted_tick = world.sim_tick
			return direct
	space.transport_search(world)
	var nodes: Dictionary = {"start":{"floor_id":source_floor,"cell":start},"goal":{"floor_id":target_floor,"cell":goal}}
	var arrival: Dictionary = {"start":initial_ticks}
	var previous: Dictionary = {}
	var heap: Array = []
	_push(heap,{"id":"start","tick":initial_ticks})
	var unknown: bool = false
	var unknown_reason: String = ""
	var egresses: Dictionary = {}
	# This search is synchronous and read-only. Keep stable structure and queue
	# prefixes only until it returns; later movement observes current facts again.
	var transport: Dictionary = space.dynamic_transport_view(world,actor.id,members,offsets)
	if not transport.has("connector_ids"):
		transport.merge({"connector_ids":world.ids("connectors"),"connections":{},"compatible":{},"stops":{},"prefixes":{}})
	var connector_ids: Array = transport.connector_ids
	var connections_by_floor: Dictionary = transport.connections
	var compatible: Dictionary = transport.compatible
	var stop_key: String = str(source_floor)+":"+str(target_floor)
	if not transport.stops.has(stop_key): transport.stops[stop_key] = {"candidates":{},"connections":{}}
	var stop_view: Dictionary = transport.stops[stop_key]
	var stop_candidates: Dictionary = stop_view.candidates
	var stops_by_connection: Dictionary = stop_view.connections
	var prefixes: Dictionary = transport.prefixes
	while not heap.is_empty():
		var item: Dictionary = _pop(heap)
		var id: String = item.id
		if int(item.tick)!=int(arrival[id]):
			continue
		if id=="goal":
			var chunks: Array = []
			var walking: float = 0.0
			while id!="start":
				chunks.push_front(previous[id].path)
				walking += float(previous[id].walking_distance)
				id = previous[id].from
			var path: Array = []
			for chunk: Array in chunks:
				path.append_array(chunk)
			if unknown:
				return {"ok":false,"status":"estimate_unknown","reason":unknown_reason}
			return {"ok":true,"status":"complete","path":path,"walking_distance":walking,"arrival_ticks":item.tick,"quoted_tick":world.sim_tick,"reason":""}
		var node: Dictionary = nodes[id]
		if int(node.floor_id)==target_floor:
			var finish: Dictionary = direct if id=="start" and source_floor==target_floor else space._floor_route(world,actor,target_floor,node.cell,goal,members,offsets,ignore_people)
			if finish.ok:
				_relax(heap,arrival,previous,id,"goal",_add(int(item.tick),walking_ticks(space,actor,members,float(finish.walking_distance))),finish.path,float(finish.walking_distance))
		var node_floor: int = int(node.floor_id)
		if not connections_by_floor.has(node_floor):
			var candidates: Array = []
			for connector_id: String in connector_ids:
				space.query_counts.candidate_connections += 1
				var connection: Dictionary = world.facts.connectors[connector_id]
				if not has_stop(connection,node_floor): continue
				if not compatible.has(connector_id): compatible[connector_id] = fits(space,world,connection,actor.id,members).ok
				if compatible[connector_id]: candidates.append(connector_id)
			connections_by_floor[node_floor] = candidates
		for connector_id: String in connections_by_floor[node_floor]:
			var connection: Dictionary = world.facts.connectors[connector_id]
			var anchor: Vector2i = Vector2i(int(connection.anchor[0]),int(connection.anchor[1]))
			var before: Dictionary = space._floor_route(world,actor,int(node.floor_id),node.cell,anchor,members,offsets,ignore_people)
			if not before.ok:
				continue
			var at_landing: int = _add(int(item.tick),walking_ticks(space,actor,members,float(before.walking_distance)))
			if at_landing<0:
				continue
			if not stops_by_connection.has(connector_id):
				if connection.has("first_floor") and stop_candidates.is_empty():
					stop_candidates = _routing_candidates(world,source_floor,target_floor)
					stop_view.candidates = stop_candidates
				stops_by_connection[connector_id] = routing_stops(connection,world,source_floor,target_floor,stop_candidates)
			var stops: Array = stops_by_connection[connector_id]
			for destination: int in stops:
				if destination==int(node.floor_id):
					continue
				var quote: Dictionary = _quote_known_fit(space,world,connection,actor.id,int(node.floor_id),destination,at_landing,members,offsets,prefixes,egresses)
				if not quote.ok:
					if quote.status=="estimate_unknown":
						unknown = true
						unknown_reason = quote.reason
					continue
				var next: String = connector_id+":"+str(destination)
				nodes[next] = {"floor_id":destination,"cell":anchor}
				var path: Array = before.path.duplicate()
				path.append({"kind":"connector","connector_id":connector_id,"from":int(node.floor_id),"to":destination})
				_relax(heap,arrival,previous,id,next,int(quote.arrival_ticks),path,float(before.walking_distance))
	if unknown:
		return {"ok":false,"status":"estimate_unknown","reason":unknown_reason}
	return direct if source_floor==target_floor else {"ok":false,"status":"unreachable","reason":"没有净宽、净高和出口均合格的竖向连接"}

static func walking_ticks(space: HospitalSpace, actor: Dictionary, members: Array, distance: float) -> int:
	var size: String = "2" if members.size()>1 else str(space.clearance(actor))
	return ceili(distance/float(space.content.balance.movement_speeds[size])/WorldState.TICK_SECONDS)

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
	var group: int = _add(_boarding(definition),_travel_ticks(space,connection,from,to))
	group = _add(group,_alighting(definition))
	var arrival: int = _add(_add(maxi(at_landing,int(prefix.ticks)),empty),group)
	if arrival<0:
		return _unavailable("交通预计超出可表示的模拟时间")
	return {"ok":true,"status":"complete","arrival_ticks":arrival,"queue_ticks":maxi(0,int(prefix.ticks)-at_landing),"empty_ticks":empty,"group_ticks":group,"quoted_tick":world.sim_tick,"reason":""}

static func _prefix(space: HospitalSpace, world: WorldState, connection: Dictionary, querying_actor: String) -> Dictionary:
	var definition: Dictionary = space.content.definition("vertical_connectors",connection.definition_id)
	var ticks: int = 0
	var floor_id: int = int(connection.floor_id)
	if connection.phase!="idle":
		ticks = int(connection.remaining_ticks)
		floor_id = int(connection.to)
		if connection.phase=="boarding":
			ticks = _add(ticks,int(connection.get("trip_travel_ticks",_travel_ticks(space,connection,int(connection.from),floor_id,true))))
		if connection.phase in ["boarding","riding"]:
			ticks = _add(ticks,_alighting(definition))
		if connection.phase in ["boarding","riding","alighting"]:
			var primary: String = connection.get("primary_actor_id",connection.riders[0])
			var movement: Dictionary = world.facts.moves.get(primary,{})
			if not egress_clear(space,world,connection,primary,floor_id,movement.get("members",[]),movement.get("offsets",{})):
				return {"ok":false,"status":"estimate_unknown","reason":"当前通行组尚无可用出口，暂时无法估计后续交通"}
	var queued: Array = _waiting(world,connection.id)
	var assigned: String = connection.get("assigned_actor_id","")
	if not assigned.is_empty():
		for index: int in queued.size():
			if queued[index]==assigned:
				queued.remove_at(index)
				queued.push_front(assigned)
				break
	for actor_id: String in queued:
		if actor_id==querying_actor:
			break
		var movement: Dictionary = world.facts.moves[actor_id]
		var ticket: Dictionary = movement.transit_ticket
		if _lowering(connection) and int(ticket.to)>=int(ticket.from):
			continue
		if not egress_clear(space,world,connection,actor_id,int(ticket.to),movement.get("members",[]),movement.get("offsets",{})):
			return {"ok":false,"status":"estimate_unknown","reason":"前方已到站通行组的出口暂不可用"}
		if definition.kind=="lift":
			ticks = _add(ticks,_travel_ticks(space,connection,floor_id,int(ticket.from)))
		ticks = _add(ticks,_boarding(definition))
		ticks = _add(ticks,_travel_ticks(space,connection,int(ticket.from),int(ticket.to)))
		ticks = _add(ticks,_alighting(definition))
		floor_id = int(ticket.to)
	return {"ok":ticks>=0,"status":"complete" if ticks>=0 else "unreachable","ticks":ticks,"floor_id":floor_id,"reason":"" if ticks>=0 else "交通工作量超出可表示的模拟时间"}

static func egress_clear(space: HospitalSpace, world: WorldState, connection: Dictionary, actor_id: String, floor_id: int, members: Array, offsets: Dictionary) -> bool:
	var actor: Dictionary = world.facts.actors[actor_id]
	var anchor: Vector2i = Vector2i(int(connection.anchor[0]),int(connection.anchor[1]))
	if not space.static_reason(world,actor,floor_id,anchor,members,offsets).is_empty():
		return false
	if space.nominal_query(world): return true
	var ignored: Array = members if not members.is_empty() else [actor_id]
	for id: String in ignored:
		var offset: Array = offsets.get(id,[0,0])
		var rect: Rect2 = space._actor_rect(world.facts.actors[id],Vector2(anchor)+Vector2(float(offset[0]),float(offset[1])))
		if not space._dynamic_clear(world,actor_id,floor_id,rect,ignored):
			return false
	return true

static func reference_movements(world: WorldState) -> Dictionary:
	# An in-flight group still owns its known transport remainder and body
	# envelope. Nominal queries remove queued contention, not these inputs.
	var result: Dictionary = {}
	for connection: Dictionary in world.facts.connectors.values():
		if not connection.phase in ["boarding","riding","alighting"]: continue
		var primary: String = str(connection.get("primary_actor_id",connection.riders[0]))
		var movement: Dictionary = world.facts.moves.get(primary,{})
		result[primary] = {"members":movement.get("members",[]),"offsets":movement.get("offsets",{})}
	return result

static func reference_conditions(world: WorldState) -> Dictionary:
	# Quote dependencies only. Wear receipts, historical tickets and completed
	# uses do not change geometry, lowering rules or the known transport prefix.
	var result: Dictionary = {}
	for id: String in world.facts.connectors:
		var connection: Dictionary = world.facts.connectors[id]
		var record: Dictionary = {}
		for field: String in ["id","definition_id","first_floor","last_floor","stops","cell","footprint","anchor","failed","pending_failure","floor_id","phase","remaining_ticks","from","to","trip_travel_ticks","riders","primary_actor_id"]:
			if connection.has(field): record[field] = connection[field]
		result[id] = record
	return result

static func reference_basis(space: HospitalSpace, world: WorldState) -> Dictionary:
	# A known in-flight prefix also reads its complete group's exit envelope.
	# Queue tickets and dynamic occupancy belong only to actual commitments.
	var movements: Dictionary = reference_movements(world)
	var bodies: Dictionary = {}
	for connection: Dictionary in world.facts.connectors.values():
		for id: String in connection.get("riders",[]):
			var actor: Dictionary = world.facts.actors[id]
			bodies[id] = {"body":space.body(actor),"posture":actor.get("posture","standing"),"facing":actor.facing}
	return {"connections":reference_conditions(world),"movements":movements,"bodies":bodies}

static func begin(space: HospitalSpace, world: WorldState, actor: Dictionary, movement: Dictionary, segment: Dictionary) -> void:
	var connection: Dictionary = world.facts.connectors[segment.connector_id]
	var members: Array = movement.get("members",[actor.id])
	var offsets: Dictionary = movement.get("offsets",{})
	if not fits(space,world,connection,actor.id,members).ok or (_lowering(connection) and int(segment.to)>=int(segment.from)):
		cancel_waiting(world,movement)
		space._queue_route(world,movement)
		return
	if not movement.has("transit_ticket"):
		for id: String in members:
			var offset: Array = offsets.get(id,[0,0])
			if not space.at(world,id,int(segment.from),[float(connection.anchor[0])+float(offset[0]),float(connection.anchor[1])+float(offset[1])]):
				return
		connection.ticket_next = int(connection.get("ticket_next",0))+1
		movement.transit_ticket = {"connector_id":connection.id,"sequence":connection.ticket_next,"from":segment.from,"to":segment.to}
	if connection.phase!="idle":
		if int(connection.to)==int(segment.from) and connection.phase!="empty_riding":
			_stand_aside(space,world,connection,actor,movement,members,offsets)
		return
	var waiting: Array = _waiting(world,connection.id)
	if waiting.is_empty() or waiting[0]!=actor.id:
		return
	connection.assigned_actor_id = actor.id
	for id: String in members:
		var offset: Array = offsets.get(id,[0,0])
		if not space.at(world,id,int(segment.from),[float(connection.anchor[0])+float(offset[0]),float(connection.anchor[1])+float(offset[1])]):
			space.queue_waypoint(world,movement,int(segment.from),connection.anchor)
			return
	var definition: Dictionary = space.content.definition("vertical_connectors",connection.definition_id)
	if definition.kind=="lift" and int(connection.floor_id)!=int(segment.from):
		connection.phase = "empty_riding"
		connection.from = connection.floor_id
		connection.to = segment.from
		connection.remaining_ticks = _travel_ticks(space,connection,int(connection.from),int(connection.to))
		return
	if not egress_clear(space,world,connection,actor.id,int(segment.to),members,offsets):
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
	connection.trip_sequence = movement.transit_ticket.sequence
	if int(connection.remaining_ticks)==0:
		connection.phase = "riding"
		connection.remaining_ticks = connection.trip_travel_ticks
	for id: String in members:
		world.facts.actors[id].location = {"kind":"transit","connector_id":connection.id,"from":segment.from,"to":segment.to}
		var placement: Dictionary = fits(space,world,connection,actor.id,members).cabin_positions
		if placement.has(id):
			world.facts.actors[id].location.cabin_cell = placement[id]
		space._sync_actor(world,id)
	movement.erase("transit_ticket")
	connection.erase("assigned_actor_id")
	movement.cursor += 1

static func cancel_waiting(world: WorldState, movement: Dictionary) -> void:
	var ticket: Dictionary = movement.get("transit_ticket",{})
	if not ticket.is_empty() and world.facts.connectors.has(ticket.connector_id):
		var connection: Dictionary = world.facts.connectors[ticket.connector_id]
		if connection.get("assigned_actor_id","")==movement.actor_id:
			connection.erase("assigned_actor_id")
	movement.erase("transit_ticket")

static func advance(space: HospitalSpace, world: WorldState) -> void:
	for id: String in world.ids("connectors"):
		var connection: Dictionary = world.facts.connectors[id]
		var assigned: String = connection.get("assigned_actor_id","")
		if not assigned.is_empty() and (not world.facts.moves.has(assigned) or world.facts.moves[assigned].get("transit_ticket",{}).get("connector_id","")!=id):
			connection.erase("assigned_actor_id")
		if connection.phase=="idle":
			_finish_failure(connection)
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
	for actor_id: String in connection.riders:
		var offset: Array = offsets.get(actor_id,[0,0])
		world.facts.actors[actor_id].location = {"kind":"floor","floor_id":connection.to,"cell":[float(connection.anchor[0])+float(offset[0]),float(connection.anchor[1])+float(offset[1])]}
		space._sync_actor(world,actor_id)
	connection.floor_id = connection.to
	connection.used = true
	var definition: Dictionary = space.content.definition("vertical_connectors",connection.definition_id)
	if definition.kind=="lift":
		var receipt: String = "transit:"+str(int(connection.get("trip_sequence",connection.get("ticket_next",0))))
		if not connection.get("use_receipts",{}).has(receipt):
			if not connection.has("use_receipts"): connection.use_receipts = {}
			connection.use_receipts[receipt] = world.sim_tick
			for category: Dictionary in space.content.balance.equipment.classes:
				if category.id==definition.equipment_class: connection.condition = maxf(0.0,float(connection.get("condition",100.0))-float(category.wear_per_use))
	movement.travelled.append(space._checkpoint(world.facts.actors[primary]))
	connection.phase = "idle"
	connection.riders = []
	connection.erase("trip_travel_ticks")
	connection.erase("primary_actor_id")
	connection.erase("trip_sequence")
	_finish_failure(connection)

static func _stand_aside(space: HospitalSpace, world: WorldState, connection: Dictionary, actor: Dictionary, movement: Dictionary, members: Array, offsets: Dictionary) -> void:
	if not space.at(world,actor.id,int(connection.to),connection.anchor):
		return
	var anchor: Vector2i = Vector2i(int(connection.anchor[0]),int(connection.anchor[1]))
	var incoming_id: String = connection.get("primary_actor_id",connection.riders[0])
	var incoming: Dictionary = world.facts.moves[incoming_id]
	var exit: Rect2 = space._unit_rect(world,world.facts.actors[incoming_id],Vector2(anchor),connection.riders,incoming.get("offsets",{}))
	for radius: int in range(1,192):
		# In-bounds cells sort by y then x under the original y*96+x key.
		# Generate that order directly; discarded off-floor points cannot win.
		for y: int in range(maxi(0,anchor.y-radius),mini(96,anchor.y+radius+1)):
			var dx: int = radius-absi(y-anchor.y)
			for side: int in range(1 if dx==0 else 2):
				var cell: Vector2i = Vector2i(anchor.x-dx if side==0 else anchor.x+dx,y)
				if cell.x<0 or cell.x>=96:
					continue
				var rect: Rect2 = space._unit_rect(world,actor,Vector2(cell),members,offsets)
				if rect.intersects(exit,false) or not space.static_reason(world,actor,int(connection.to),cell,members,offsets).is_empty() or not space._dynamic_clear(world,actor.id,int(connection.to),rect,members):
					continue
				var public_space: bool = true
				for room: Dictionary in world.facts.rooms.values():
					if int(room.floor_id)==int(connection.to) and rect.intersects(Rect2(float(room.origin[0]),float(room.origin[1]),float(room.size[0]),float(room.size[1])),false):
						public_space = false
				if not public_space:
					continue
				var path: Dictionary = space._floor_route(world,actor,int(connection.to),anchor,cell,members,offsets)
				if path.ok:
					space.queue_waypoint(world,movement,int(connection.to),[cell.x,cell.y])
					return

static func _waiting(world: WorldState, connector_id: String) -> Array:
	var result: Array = []
	for id: String in world.ids("moves"):
		var movement: Dictionary = world.facts.moves[id]
		if movement.get("transit_ticket",{}).get("connector_id","")==connector_id:
			result.append(id)
	result.sort_custom(func(a: String,b: String) -> bool:
		var left: int = int(world.facts.moves[a].transit_ticket.sequence)
		var right: int = int(world.facts.moves[b].transit_ticket.sequence)
		return left<right if left!=right else a<b)
	return result

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

static func _relax(heap: Array, arrival: Dictionary, previous: Dictionary, from: String, to: String, tick: int, path: Array, walking: float) -> void:
	if tick<0 or (arrival.has(to) and int(arrival[to])<=tick):
		return
	arrival[to] = tick
	previous[to] = {"from":from,"path":path,"walking_distance":walking}
	_push(heap,{"id":to,"tick":tick})

static func _less(a: Dictionary,b: Dictionary) -> bool:
	return int(a.tick)<int(b.tick) if a.tick!=b.tick else str(a.id)<str(b.id)

static func _push(heap: Array, item: Dictionary) -> void:
	heap.append(item)
	var index: int = heap.size()-1
	while index>0:
		var parent: int = (index-1)/2
		if not _less(item,heap[parent]):
			break
		heap[index] = heap[parent]
		index = parent
	heap[index] = item

static func _pop(heap: Array) -> Dictionary:
	var result: Dictionary = heap[0]
	var item: Dictionary = heap.pop_back()
	if heap.is_empty():
		return result
	var index: int = 0
	while index*2+1<heap.size():
		var child: int = index*2+1
		if child+1<heap.size() and _less(heap[child+1],heap[child]):
			child += 1
		if not _less(heap[child],item):
			break
		heap[index] = heap[child]
		index = child
	heap[index] = item
	return result
