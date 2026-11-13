class_name LiftLandingQueue
extends RefCounted

# Saved failed layouts belong to the planner that produced them. A change
# to single-person routing must retry old failures once after cold restore.
const LAYOUT_VERSION: int = 2

# Only actually arrived groups enter these arrays. A walking target is not a
# queue position, a car reservation, or a transport ticket.
static func _key(floor_id: int, direction: int) -> String:
	return "%d:%d" % [floor_id,direction]

static func head(connection: Dictionary, floor_id: int, direction: int) -> Dictionary:
	var line: Array=connection.get("landing_queues",{}).get(_key(floor_id,direction),[])
	return line[0] if not line.is_empty() else {}

static func remove(connection: Dictionary, leader: String) -> void:
	for key: String in connection.get("landing_queues",{}):
		var line: Array=connection.landing_queues[key]
		for index: int in range(line.size()-1,-1,-1):
			if line[index].actor_id==leader: line.remove_at(index)

# Cancel a ground journey at the same boundary as its movement owner. A
# patient's companion can own a separate movement within this one queue row.
# Remove that whole waiting row, not accepted cabin groups or another row's FIFO.
static func cancel_waiting(world: WorldState, actor_id: String) -> void:
	for connection: Dictionary in world.facts.connectors.values():
		for line: Array in connection.get("landing_queues",{}).values():
			for index: int in range(line.size()-1,-1,-1):
				var entry: Dictionary=line[index]
				var owners: Array=entry.get("leader_ids",[entry.actor_id])
				if not actor_id in owners: continue
				line.remove_at(index)
				connection.get("unavailable_heads",{}).erase(entry.actor_id)
				for owner: String in owners:
					var movement: Dictionary=world.facts.moves.get(owner,{})
					for key: String in ["lift_queue_target","lift_queue_standby"]:
						if movement.get(key,{}).get("connector_id","")==connection.id: movement.erase(key)
					var call: Dictionary=movement.get("lift_boarding_call",{})
					if call.get("connector_id","")==connection.id and call.get("group_leader","")==entry.actor_id: movement.erase("lift_boarding_call")
					movement.erase("lift_queue_wait_basis")

static func holds(world: WorldState, actor_id: String) -> bool:
	var movement: Dictionary=world.facts.moves.get(actor_id,{})
	if movement.has("lift_boarding_call") or movement.has("local_move") or movement.has("detour"): return false
	var standby: Dictionary=movement.get("lift_queue_standby",{})
	if not standby.is_empty():
		var trip: Dictionary=_trip(world,movement,str(standby.connector_id))
		if not trip.is_empty() and _intent_matches(world,movement,standby):
			var body: Dictionary=world.facts.actors[actor_id]
			if standby.get("blocked_in_place",false):
				movement.waiting_reason="没有不阻断通道的可达候补位，当前身体被困；保持真实位置并报告阻挡"
				return true
			if space_at_cell(body,int(standby.floor_id),standby.cell):
				standby.traveling=false
				movement.waiting_reason="电梯候梯空间不足，先在附近等待补位"
				return true
	var target: Dictionary=movement.get("lift_queue_target",{})
	if target.is_empty() or not _intent_matches(world,movement,target) or movement.has("local_move") or movement.has("detour"): return false
	var actor: Dictionary=world.facts.actors.get(actor_id,{})
	return actor.get("location",{}).get("kind")=="floor" and int(actor.location.floor_id)==int(target.floor_id) and ConvoyTrail.point(actor.location.cell)==ConvoyTrail.point(target.cell)

static func space_at_cell(actor: Dictionary, floor_id: int, cell: Array) -> bool:
	return actor.get("location",{}).get("kind")=="floor" and int(actor.location.floor_id)==floor_id and ConvoyTrail.point(actor.location.cell)==ConvoyTrail.point(cell)

# Standby is a physical waiting action, never a FIFO entry or car claim.
# Keep the original movement and connector continuation intact for recovery.
static func _standby(space: HospitalSpace, world: WorldState, connection: Dictionary, group: Dictionary, occupied: Array) -> void:
	var used: Array=occupied.duplicate()
	for id: String in group.leader_ids:
		var movement: Dictionary=world.facts.moves[id]
		if movement.has("local_move") or movement.has("detour") or movement.has("lift_boarding_call"): continue
		var actor: Dictionary=world.facts.actors[id]
		if actor.location.kind!="floor": continue
		var floor_id: int=int(actor.location.floor_id)
		var current: Array=actor.location.cell.duplicate()
		var body: Rect2=_body(space,world,movement,current)
		var anchor: Vector2=ConvoyTrail.point(connection.anchor)
		var normal: Vector2i=_normal(connection)
		var side: Vector2=Vector2(normal.y,-normal.x)
		var lo: float=minf((body.position-anchor).dot(side),(body.end-anchor).dot(side))
		var hi: float=maxf((body.position-anchor).dot(side),(body.end-anchor).dot(side))
		var safe: bool=lo>=3.0 or hi<=-3.0
		for rect: Rect2 in used:
			if body.intersects(rect,false): safe=false
		if safe and not _preserves_passage(space,world,floor_id,body,used): safe=false
		var target: Dictionary={"cell":current,"body":body}
		if not safe:
			target=_slot(space,world,connection,movement,floor_id,int(group.direction),used,true)
			if target.is_empty(): target=_slot(space,world,connection,movement,floor_id,-int(group.direction),used,true)
		movement.erase("lift_queue_target")
		if target.is_empty():
			movement.lift_queue_standby={"connector_id":connection.id,"floor_id":floor_id,"cell":current,"request_sequence":movement.request_sequence,"target_floor":movement.target_floor,"target_cell":movement.target_cell.duplicate(),"destination":group.destination,"blocked_in_place":true,"traveling":false}
			movement.waiting_reason="没有不阻断通道的可达候补位，当前身体被困；保持真实位置并报告阻挡"
			continue
		used.append(target.body)
		var standby: Dictionary={"connector_id":connection.id,"floor_id":floor_id,"cell":target.cell.duplicate(),"request_sequence":movement.request_sequence,"target_floor":movement.target_floor,"target_cell":movement.target_cell.duplicate(),"destination":group.destination,"blocked_in_place":false,"traveling":not space_at_cell(actor,floor_id,target.cell)}
		if movement.get("lift_queue_standby",{})==standby: continue
		movement.lift_queue_standby=standby
		movement.waiting_reason="电梯候梯空间不足，先在附近等待补位"
		if not space_at_cell(actor,floor_id,target.cell):
			var continuation: Array=_continuation(movement,connection.id)
			if continuation.is_empty(): continue
			movement.path=continuation
			movement.cursor=0
			movement.erase("route_waypoint")
			space.movement.queue_waypoint(world,movement,floor_id,target.cell,true)

static func release(space: HospitalSpace, world: WorldState, connection: Dictionary, entry: Dictionary) -> bool:
	if entry.get("layout_blocked",false): return false
	var owners: Array=entry.get("leader_ids",[entry.actor_id])
	var targets: Dictionary={}
	var approaches: Dictionary={}
	var normal: Vector2i=_normal(connection)
	var side: Vector2i=Vector2i(normal.y,-normal.x)
	var offset: int=0
	var articulated: Dictionary={}
	for owner: String in owners:
		var nursing: Dictionary=world.facts.moves.get(owner,{})
		if nursing.has("convoy"):
			var candidate: Dictionary=ConvoyPortal.plan(space,world,connection,owner,nursing.members,nursing.convoy)
			if candidate.get("mode","")=="articulated": articulated=candidate
	for id: String in owners:
		var movement: Dictionary=world.facts.moves.get(id,{})
		if movement.is_empty() or movement.has("local_move") or movement.has("detour"): return false
		var actor: Dictionary=world.facts.actors[id]
		if actor.location.kind!="floor" or not _has_continuation(movement,connection.id): return false
		var cell: Vector2=ConvoyTrail.point(connection.anchor)+Vector2(side)*offset
		if not movement.has("convoy") and not articulated.is_empty():
			# Keep the independent family fully outside and clear of the
			# nursing approach/egress lane; it walks in only once they sit.
			cell=companion_entry(space,actor,articulated,offset)
		if not movement.has("convoy") and not space.static_reason(world,actor,int(actor.location.floor_id),cell,movement.get("members",[id]),movement.get("offsets",{})).is_empty():
			movement.waiting_reason="电梯同行组入口站位被墙或家具阻挡"
			return false
		if movement.has("convoy"):
			var plan: Dictionary=ConvoyPortal.plan(space,world,connection,id,movement.members,movement.convoy)
			if not plan.get("ok",false): movement.waiting_reason=plan.get("reason","");return false
			var proxy: Dictionary=ConvoyTrail.proxy(world,movement)
			var approach: Dictionary=space.navigation._convoy_portal_approach(world,proxy,int(actor.location.floor_id),{"cell":Vector2(proxy.location.cell[0],proxy.location.cell[1]),"convoy":movement.convoy},plan)
			if not approach.ok: movement.waiting_reason=approach.get("reason","护理同行组无法真实对齐入口");return false
			var shift: float=float(movement.convoy.shift)
			for segment: Dictionary in approach.path: segment.cell=[float(segment.cell[0])-shift,float(segment.cell[1])-shift]
			approaches[id]=approach.path
			targets[id]=plan.entry.duplicate()
		else: targets[id]=[cell.x,cell.y]
		offset+=maxi(1,space.clearance(actor))
	for id: String in owners:
		var movement: Dictionary=world.facts.moves[id]
		var call: Dictionary={"connector_id":connection.id,"floor_id":int(world.facts.actors[id].location.floor_id),"direction":int(entry.direction),"entry_cell":targets[id].duplicate(),"group_leader":entry.actor_id}
		if movement.get("lift_boarding_call",{})==call: continue
		movement.lift_boarding_call=call
		movement.erase("lift_queue_standby")
		movement.erase("lift_queue_target")
		movement.path=_continuation(movement,connection.id)
		movement.cursor=0
		movement.erase("route_waypoint")
		if approaches.has(id):
			movement.path=approaches[id].duplicate(true)+movement.path
			movement.route_pending=false
			space.movement._route_checks.erase(id)
		else: space.movement.queue_waypoint(world,movement,int(call.floor_id),targets[id],true)
	entry.entry_cells=targets
	return true

static func _continuation(movement: Dictionary, connector_id: String) -> Array:
	var source: Array=movement.get("route_waypoint",{}).get("continuation",movement.get("path",[]).slice(int(movement.get("cursor",0))))
	for index: int in source.size():
		if source[index].kind=="connector" and source[index].connector_id==connector_id: return source.slice(index).duplicate(true)
	return []

static func _trip(world: WorldState, movement: Dictionary, connector_id: String) -> Dictionary:
	if LiftController.pending_holds(world,str(movement.get("actor_id",""))): return {}
	var actor: Dictionary=world.facts.actors.get(movement.get("actor_id",""),{})
	if actor.get("location",{}).get("kind")!="floor": return {}
	if actor.get("posture","standing")!="standing" or float(actor.location.get("height_m",0))!=0.0 or actor.has("support_facility_id"): return {}
	var cursor: int=int(movement.get("cursor",0))
	var path: Array=movement.get("path",[])
	if cursor<path.size() and cursor>=0 and path[cursor].kind=="support_exit": return {}
	var trip: Dictionary=HospitalTransit.journey(movement)
	if trip.get("connector_id","")!=connector_id or int(trip.from)!=int(actor.location.floor_id): return {}
	return trip

static func _intent_matches(world: WorldState, movement: Dictionary, intent: Dictionary) -> bool:
	var trip: Dictionary=_trip(world,movement,str(intent.get("connector_id","")))
	return not trip.is_empty() and int(intent.get("request_sequence",-2))==int(movement.get("request_sequence",-1)) and int(intent.get("destination",-1))==int(trip.to) and int(intent.get("floor_id",-1))==int(trip.from) and intent.get("target_floor",-1)==movement.get("target_floor",-2) and intent.get("target_cell",[])==movement.get("target_cell",[])

static func _identity(world: WorldState, connector_id: String, group: Dictionary) -> Array:
	var requests: Array=[]
	for id: String in group.leader_ids:
		var m: Dictionary=world.facts.moves[id]
		requests.append([id,m.get("request_sequence",-1),m.target_floor,m.target_cell.duplicate()])
	return [connector_id,group.floor_id,group.destination,group.direction,requests]

static func _arrived(space: HospitalSpace, world: WorldState, movement: Dictionary, target: Dictionary) -> bool:
	if movement.has("local_move") or movement.has("detour") or movement.get("route_pending",false): return false
	if not space.at(world,movement.actor_id,int(target.floor_id),target.cell): return false
	for id: String in movement.get("members",[movement.actor_id]):
		var actor: Dictionary=world.facts.actors.get(id,{})
		if actor.get("location",{}).get("kind")!="floor" or int(actor.location.floor_id)!=int(target.floor_id): return false
	# Convoys retain their actual trail rather than being folded into one cell.
	return true

static func _normal(connection: Dictionary) -> Vector2i:
	match posmod(int(connection.get("rotation",0)),4):
		1: return Vector2i(-1,0)
		2: return Vector2i(0,-1)
		3: return Vector2i(1,0)
	return Vector2i(0,1)

static func _body(space: HospitalSpace, world: WorldState, movement: Dictionary, cell: Array) -> Rect2:
	var actor: Dictionary=world.facts.actors[movement.actor_id]
	if movement.has("convoy"):
		var trail: Dictionary=movement.convoy
		var reach: float=float(trail.spacing)*maxi(0,movement.members.size()-1)
		return Rect2(ConvoyTrail.point(cell)+Vector2.ONE*(float(trail.shift)-reach),Vector2.ONE*(float(trail.size)+2.0*reach))
	return space._unit_rect(world,actor,ConvoyTrail.point(cell),movement.get("members",[actor.id]),movement.get("offsets",{}))

# Runtime-only bounded proof cache, never a reservation or simulation fact.
static var _passage_cache: Dictionary={}

static func _rect_key(rect: Rect2) -> Array:
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]

# Queue-local geometry only: moving an earlier layout invalidates a proof even
# when the same request IDs and floor body-profile set remain present.
static func _occupied_signature(rects: Array) -> Array:
	var result: Array=[]
	for rect: Rect2 in rects: result.append(JSON.stringify(_rect_key(rect)))
	result.sort()
	return result

static func _intersects_any(rect: Rect2, obstacles: Array) -> bool:
	for obstacle: Rect2 in obstacles:
		if rect.intersects(obstacle,false): return true
	return false

static func _components(nodes: Dictionary, edges: Dictionary) -> Dictionary:
	var labels: Dictionary={}
	var label: int=0
	for start: Vector2i in nodes:
		if labels.has(start): continue
		label+=1
		var pending: Array[Vector2i]=[start];labels[start]=label
		var cursor: int=0
		while cursor<pending.size():
			var point: Vector2i=pending[cursor];cursor+=1
			for next: Vector2i in edges.get(point,[]):
				if nodes.has(next) and not labels.has(next): labels[next]=label;pending.append(next)
	return labels

# A local bypass must remain physically possible for each actual traversal
# body profile. Compare connectivity before/after the *whole* waiting envelope,
# not just distance from the lift door. Existing disconnected wall sides never
# have to become connected. No far-away detour is accepted as a local bypass.
static func _preserves_passage(space: HospitalSpace, world: WorldState, floor_id: int, candidate: Rect2, occupied: Array) -> bool:
	var profiles: Dictionary=space.passage_profiles(world,floor_id)
	var occupancy: Array=[]
	for rect: Rect2 in occupied: occupancy.append(_rect_key(rect))
	var version: String=space._navigation.floor_static_version(space,world,floor_id)
	for profile: String in profiles:
		var key: String=JSON.stringify([world.get_instance_id(),floor_id,version,profile,occupancy,_rect_key(candidate)],"",true,true)
		if _passage_cache.has(key):
			if not _passage_cache[key]: return false
			continue
		var actor: Dictionary=profiles[profile].actor
		var size: int=space.clearance(actor)
		var query: RouteClearance=space.navigation.structural_clearance(world,actor,floor_id)
		var radius: int=maxi(3,size+1)
		var low: Vector2i=Vector2i(candidate.position.floor())-Vector2i.ONE*(radius+size)
		var high: Vector2i=Vector2i(candidate.end.ceil())+Vector2i.ONE*radius
		var before: Dictionary={};var after: Dictionary={};var edges: Dictionary={};var after_edges: Dictionary={}
		for x: int in range(maxi(0,low.x),mini(96,high.x)+1):
			for y: int in range(maxi(0,low.y),mini(96,high.y)+1):
				var point: Vector2i=Vector2i(x,y)
				var body: Rect2=Rect2(Vector2(point),Vector2.ONE*size)
				if not query.reason(point).is_empty() or _intersects_any(body,occupied): continue
				before[point]=true
				if not body.intersects(candidate,false): after[point]=true
		for point: Vector2i in before:
			edges[point]=[];after_edges[point]=[]
			for step: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var next: Vector2i=point+step
				if not before.has(next): continue
				var sweep: Rect2=Rect2(Vector2(point),Vector2.ONE*size).merge(Rect2(Vector2(next),Vector2.ONE*size))
				if _intersects_any(sweep,occupied) or not query.sweep_reason(Vector2(point),Vector2(next)).is_empty(): continue
				edges[point].append(next)
				if after.has(point) and after.has(next) and not sweep.intersects(candidate,false): after_edges[point].append(next)
		var initial: Dictionary=_components(before,edges)
		var remaining: Dictionary=_components(after,after_edges)
		var components: Dictionary={}
		var safe: bool=true
		for point: Vector2i in remaining:
			var old_label: int=int(initial[point]);var new_label: int=int(remaining[point])
			if components.has(old_label) and int(components[old_label])!=new_label: safe=false;break
			components[old_label]=new_label
		if _passage_cache.size()>4096: _passage_cache.clear()
		_passage_cache[key]=safe
		if not safe: return false
	return true

static func _slot(space: HospitalSpace, world: WorldState, connection: Dictionary, movement: Dictionary, floor_id: int, direction: int, occupied: Array, dynamic: bool) -> Dictionary:
	var actor: Dictionary=world.facts.actors[movement.actor_id]
	var members: Array=movement.get("members",[actor.id])
	var offsets: Dictionary=movement.get("offsets",{})
	var normal: Vector2i=_normal(connection)
	var side: Vector2i=Vector2i(normal.y,-normal.x)*direction
	var anchor: Vector2i=Vector2i(int(connection.anchor[0]),int(connection.anchor[1]))
	# Two disjoint half-planes leave a three-cell clear doorway corridor.
	# The bounded local search never invents a capacity or crosses geometry.
	for distance: int in range(3,25):
		for lateral: int in range(3,distance+1):
			var cell: Vector2i=anchor+side*lateral+normal*(distance-lateral)
			if cell.x<0 or cell.y<0 or cell.x>=96 or cell.y>=96: continue
			if movement.has("convoy"):
				var proxy: Dictionary=ConvoyTrail.proxy(world,movement)
				if not space.static_reason(world,proxy,floor_id,cell).is_empty(): continue
			else:
				if not space.static_reason(world,actor,floor_id,cell,members,offsets).is_empty(): continue
			var body: Rect2=_body(space,world,movement,[cell.x,cell.y])
			var near: Vector2=body.position-Vector2(anchor)
			var far: Vector2=body.end-Vector2(anchor)
			var side_min: float=minf(near.dot(Vector2(side)),far.dot(Vector2(side)))
			if side_min<3.0: continue
			var free: bool=true
			for rect: Rect2 in occupied:
				if body.intersects(rect.grow(0.05),false): free=false;break
			if not free: continue
			# Waiting bodies must not spill into treatment rooms or the lift.
			for room: Dictionary in world.facts.rooms.values():
				if int(room.floor_id)==floor_id and body.intersects(Rect2(float(room.origin[0]),float(room.origin[1]),float(room.size[0]),float(room.size[1])),false): free=false;break
			if not free: continue
			if dynamic and not space._dynamic_clear(world,actor.id,floor_id,body,members): continue
			if not _preserves_passage(space,world,floor_id,body,occupied): continue
			if movement.has("convoy"):
				if not space.navigation.convoy_local_route(world,movement,floor_id,[cell.x,cell.y]).ok: continue
			elif not space.can_reach(world,actor.id,floor_id,[cell.x,cell.y],movement.get("members",[]),offsets,true): continue
			return {"floor_id":floor_id,"cell":[cell.x,cell.y],"body":body}
	return {}

static func _route(space: HospitalSpace, world: WorldState, connection: Dictionary, movement: Dictionary, target: Dictionary, direction: int) -> void:
	if movement.has("local_move") or movement.has("detour") or movement.has("lift_boarding_call"): return
	var intent: Dictionary={"connector_id":connection.id,"floor_id":int(target.floor_id),"direction":direction,"cell":target.cell.duplicate(),"passage_profiles":space.passage_profile_signature(world,int(target.floor_id)).duplicate(),"geometry_revision":space._navigation.floor_static_version(space,world,int(target.floor_id)),"request_sequence":movement.get("request_sequence",-1),"target_floor":movement.target_floor,"target_cell":movement.target_cell.duplicate(),"destination":HospitalTransit.journey(movement).get("to",-1)}
	if movement.get("lift_queue_target",{})==intent: return
	var continuation: Array=_continuation(movement,connection.id)
	if continuation.is_empty(): return
	movement.erase("lift_queue_standby")
	movement.lift_queue_target=intent
	movement.path=continuation
	movement.cursor=0
	movement.erase("route_waypoint")
	space.movement.queue_waypoint(world,movement,int(target.floor_id),target.cell,true)

# Group only existing compatible travel obligations. This layer never gives a
# family member a destination or overwrites either owner's original journey.
static func _groups(world: WorldState, connector_id: String) -> Dictionary:
	var partners: Dictionary={}
	var patients: Dictionary={}
	var movement_owner: Dictionary={}
	for id: String in world.facts.moves:
		for member: String in world.facts.moves[id].get("members",[id]): movement_owner[member]=id
	for stay: Dictionary in world.facts.get("visitors",{}).get("stays",{}).values():
		if stay.get("purpose","")!="companion": continue
		var visit: Dictionary=world.facts.visits.get(stay.get("visit_id",""),{})
		var patient: String=str(visit.get("actor_id",""))
		var companion: String=str(stay.get("actor_id",""))
		patient=str(movement_owner.get(patient,patient))
		companion=str(movement_owner.get(companion,companion))
		if patient==companion: continue
		var left: Dictionary=_trip(world,world.facts.moves.get(patient,{}),connector_id)
		var right: Dictionary=_trip(world,world.facts.moves.get(companion,{}),connector_id)
		if not left.is_empty() and left==right:
			patients[patient]=true
			partners[patient]=companion
			partners[companion]=patient
	var result: Dictionary={}
	var covered: Dictionary={}
	for id: String in world.ids("moves"):
		if covered.has(id): continue
		var movement: Dictionary=world.facts.moves[id]
		var trip: Dictionary=_trip(world,movement,connector_id)
		if trip.is_empty(): continue
		var owners: Array=[id]
		if partners.has(id):
			var other: String=partners[id]
			# The patient is the group owner even when family ID sorts first.
			if not patients.has(id):
				owners=[other,id]
			else: owners.append(other)
		var members: Array=[]
		for owner: String in owners:
			covered[owner]=true
			for member: String in world.facts.moves[owner].get("members",[owner]):
				if not member in members: members.append(member)
		result[owners[0]]={"actor_id":owners[0],"leader_ids":owners,"members":members,"destination":int(trip.to),"floor_id":int(trip.from),"direction":signi(int(trip.to)-int(trip.from))}
	return result

static func _group_slots(space: HospitalSpace, world: WorldState, connection: Dictionary, group: Dictionary, occupied: Array, dynamic: bool) -> Dictionary:
	var cells: Dictionary={}
	var bodies: Array=[]
	var used: Array=occupied.duplicate()
	for id: String in group.leader_ids:
		var slot: Dictionary=_slot(space,world,connection,world.facts.moves[id],int(group.floor_id),int(group.direction),used,dynamic)
		if slot.is_empty(): return {}
		cells[id]=slot.cell
		used.append(slot.body)
		bodies.append(slot.body)
	return {"cells":cells,"bodies":bodies}

# A publication proof covers the whole arriving group against current queue
# geometry. Checking each leader in isolation is not equivalent.
static func _publication_clear(space: HospitalSpace, world: WorldState, floor_id: int, bodies: Array, occupied: Array) -> bool:
	var used: Array=occupied.duplicate()
	for body: Rect2 in bodies:
		for rect: Rect2 in used:
			if body.intersects(rect.grow(0.05),false): return false
		if not _preserves_passage(space,world,floor_id,body,used): return false
		used.append(body)
	return true

static func sync(space: HospitalSpace, world: WorldState, connection: Dictionary) -> void:
	if space.content.definition("vertical_connectors",connection.definition_id).kind!="lift": return
	if not connection.has("landing_queues"): connection.landing_queues={}
	var groups: Dictionary=_groups(world,connection.id)
	var registered: Dictionary={}
	var occupied: Dictionary={}
	for key: String in connection.landing_queues.keys():
		var line: Array=connection.landing_queues[key]
		for index: int in range(line.size()-1,-1,-1):
			var entry: Dictionary=line[index]
			var group: Dictionary=groups.get(entry.actor_id,{})
			if group.is_empty() or group.destination!=entry.destination or group.direction!=entry.direction or group.leader_ids!=entry.get("leader_ids",[entry.actor_id]) or entry.get("request_identity",[])!=_identity(world,str(connection.id),group):
				line.remove_at(index)
				for id: String in entry.get("leader_ids",[entry.actor_id]):
					var movement: Dictionary=world.facts.moves.get(id,{})
					var target: Dictionary=movement.get("lift_queue_target",{})
					if target.get("connector_id","")==connection.id: movement.erase("lift_queue_target")
					movement.erase("lift_queue_wait_basis")
					var standby: Dictionary=movement.get("lift_queue_standby",{})
					if standby.get("connector_id","")==connection.id: movement.erase("lift_queue_standby")
					var call: Dictionary=movement.get("lift_boarding_call",{})
					var actor: Dictionary=world.facts.actors.get(id,{})
					# Remove only a stale invitation owned by this departed queue
					# group. A physically active portal/transit remains untouched.
					if call.get("connector_id","")==connection.id and call.get("group_leader","")==entry.actor_id and actor.get("location",{}).get("kind")=="floor" and not movement.get("convoy",{}).has("portal") and not LiftController.pending_holds(world,id):
						movement.erase("lift_boarding_call")
		var prefix: Array=[]
		for entry: Dictionary in line.duplicate():
			var group: Dictionary=groups[entry.actor_id]
			registered[entry.actor_id]=true
			var floor_id: int=int(group.floor_id)
			if not occupied.has(floor_id): occupied[floor_id]=[]
			var basis: Array=[LAYOUT_VERSION,space._navigation.floor_static_version(space,world,floor_id),space.passage_profile_signature(world,floor_id).duplicate(),_occupied_signature(occupied[floor_id]),prefix.duplicate(),group.leader_ids.duplicate(),group.members.duplicate(),_identity(world,str(connection.id),group)]
			prefix.append(entry.actor_id)
			var has_boarding_call: bool=world.facts.moves[entry.actor_id].has("lift_boarding_call")
			var same_basis: bool=entry.get("layout_basis",[])==basis
			if has_boarding_call and same_basis: continue
			if not same_basis:
				for id: String in group.leader_ids: world.facts.moves[id].erase("lift_boarding_call")
				entry.erase("entry_cells")
			# A real queue position remains stable. Only changed predecessors,
			# membership or geometry can require another floor-route query.
			if same_basis:
				if entry.has("owner_cells"):
					for id: String in group.leader_ids: occupied[floor_id].append(_body(space,world,world.facts.moves[id],entry.owner_cells[id]))
				continue
			var slots: Dictionary=_group_slots(space,world,connection,group,occupied[floor_id],false)
			entry.layout_basis=basis
			if slots.is_empty():
				# Preserve actual arrival order but suspend unsafe geometry. No
				# later arrival may overtake this physically waiting group.
				entry.layout_blocked=true
				entry.erase("owner_cells");entry.erase("entry_cells");entry.erase("cell")
				_standby(space,world,connection,group,occupied[floor_id])
				continue
			entry.erase("layout_blocked")
			occupied[floor_id].append_array(slots.bodies)
			entry.owner_cells=slots.cells.duplicate(true)
			entry.cell=slots.cells[entry.actor_id].duplicate()
			for id: String in group.leader_ids:
				_route(space,world,connection,world.facts.moves[id],{"floor_id":floor_id,"cell":slots.cells[id]},int(group.direction))
	# IDs only break a same-tick physical arrival tie, never order walkers.
	for leader: String in groups:
		if registered.has(leader): continue
		var group: Dictionary=groups[leader]
		if int(group.direction)==0 or world.facts.moves[leader].has("lift_boarding_call"): continue
		var floor_id: int=int(group.floor_id)
		var key: String=_key(floor_id,int(group.direction))
		if not connection.landing_queues.has(key): connection.landing_queues[key]=[]
		if not occupied.has(floor_id): occupied[floor_id]=[]
		var arrived: bool=true
		var walking: bool=false
		var missing: bool=false
		var bodies: Array=[]
		var cells: Dictionary={}
		for id: String in group.leader_ids:
			var movement: Dictionary=world.facts.moves[id]
			var target: Dictionary=movement.get("lift_queue_target",{})
			if target.is_empty() or target.connector_id!=connection.id or not _intent_matches(world,movement,target):
				arrived=false
				missing=true
				continue
			if not _arrived(space,world,movement,target): arrived=false;walking=true
			var revision: String=space._navigation.floor_static_version(space,world,floor_id)
			var signature: Array=space.passage_profile_signature(world,floor_id)
			if target.get("passage_profiles",[])!=signature:
				if not _preserves_passage(space,world,floor_id,_body(space,world,movement,target.cell),occupied[floor_id]): missing=true;arrived=false
				else: target.passage_profiles=signature.duplicate()
			if str(target.get("geometry_revision",""))!=revision:
				var actor: Dictionary=world.facts.actors[id]
				var cell: Vector2i=Vector2i(int(target.cell[0]),int(target.cell[1]))
				var geometry_error: String=space.static_reason(world,ConvoyTrail.proxy(world,movement) if movement.has("convoy") else actor,floor_id,cell,[] if movement.has("convoy") else movement.get("members",[id]),{} if movement.has("convoy") else movement.get("offsets",{}))
				if not geometry_error.is_empty(): missing=true;arrived=false
				else: target.geometry_revision=revision
			cells[id]=target.cell.duplicate()
			bodies.append(_body(space,world,movement,target.cell))
		if arrived:
			var free: bool=_publication_clear(space,world,floor_id,bodies,occupied[floor_id])
			if free:
				var entry: Dictionary=group.duplicate(true)
				entry.arrived_tick=world.sim_tick
				entry.request_identity=_identity(world,str(connection.id),group)
				var preceding: Array=[]
				for previous: Dictionary in connection.landing_queues[key]: preceding.append(previous.actor_id)
				entry.layout_basis=[LAYOUT_VERSION,space._navigation.floor_static_version(space,world,floor_id),space.passage_profile_signature(world,floor_id).duplicate(),_occupied_signature(occupied[floor_id]),preceding,group.leader_ids.duplicate(),group.members.duplicate(),entry.request_identity.duplicate(true)]
				entry.owner_cells=cells
				entry.cell=cells[leader].duplicate()
				connection.landing_queues[key].append(entry)
				occupied[floor_id].append_array(bodies)
				continue
			# This old target is no longer publishable. A prior failed-slot
			# cache must not prevent a new legal layout or physical standby.
			world.facts.moves[leader].erase("lift_queue_wait_basis")
			missing=true
		if walking and not missing: continue
		var busy: bool=false
		for id: String in group.leader_ids:
			var movement: Dictionary=world.facts.moves[id]
			if movement.has("local_move") or movement.has("detour") or movement.get("route_pending",false): busy=true
		if busy: continue
		var predecessors: Array=[]
		for entry: Dictionary in connection.landing_queues[key]: predecessors.append(entry.actor_id)
		var basis: Array=[LAYOUT_VERSION,space._navigation.floor_static_version(space,world,floor_id),space.passage_profile_signature(world,floor_id).duplicate(),_occupied_signature(occupied[floor_id]),predecessors,group.leader_ids.duplicate(),group.members.duplicate(),_identity(world,str(connection.id),group)]
		var primary_move: Dictionary=world.facts.moves[leader]
		if primary_move.get("lift_queue_wait_basis",[])==basis and (not missing or primary_move.has("lift_queue_standby")):
			# A completed collision-avoidance leg may move a parked body.
			# Re-evaluate that actual handoff, not every walking simulation step.
			var displaced: bool=false
			for id: String in group.leader_ids:
				var movement: Dictionary=world.facts.moves[id]
				var standby: Dictionary=movement.get("lift_queue_standby",{})
				if not standby.is_empty() and not standby.get("traveling",false) and not movement.has("local_move") and not movement.has("detour") and not space_at_cell(world.facts.actors[id],floor_id,standby.cell): displaced=true
			if displaced: _standby(space,world,connection,group,occupied[floor_id])
			continue
		# A walking intent is not a reservation: occupied target bodies remain
		# real collision obstacles until the first group actually arrives.
		var slots: Dictionary=_group_slots(space,world,connection,group,occupied[floor_id],false)
		primary_move.lift_queue_wait_basis=basis
		if slots.is_empty():
			_standby(space,world,connection,group,occupied[floor_id])
			continue
		for id: String in group.leader_ids:
			_route(space,world,connection,world.facts.moves[id],{"floor_id":floor_id,"cell":slots.cells[id]},int(group.direction))

static func companion_entry(space: HospitalSpace, actor: Dictionary, nursing: Dictionary, offset: int) -> Vector2:
	var inward: Vector2=ConvoyTrail.point(nursing.inward)
	var side: Vector2=Vector2(-inward.y,inward.x)
	return ConvoyTrail.point(nursing.entry)-side*(offset+space.clearance(actor)+2.0)-inward*space.clearance(actor)

# Existence-only release guard: published paths still use _continuation's copy.
static func _has_continuation(movement: Dictionary, connector_id: String) -> bool:
	var waypoint: Dictionary=movement.get("route_waypoint",{})
	var source: Array
	var start: int=0
	if waypoint.has("continuation"):
		source=waypoint.continuation
	else:
		source=movement.get("path",[])
		start=int(movement.get("cursor",0))
		if start<0: start=source.size()+start
		start=clampi(start,0,source.size())
	for index: int in range(start,source.size()):
		if source[index].kind=="connector" and source[index].connector_id==connector_id: return true
	return false
