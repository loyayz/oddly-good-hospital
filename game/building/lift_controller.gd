class_name LiftController
extends RefCounted

# Physical landing queues and a car manifest. No passenger is reserved for a
# future journey: only the currently open door may invite its actual FIFO head.
const Landing = preload("res://game/building/lift_landing_queue.gd")

static func pending_holds(world: WorldState, actor_id: String) -> bool:
	var m: Dictionary=world.facts.moves.get(actor_id,{})
	var marker: Dictionary=m.get("lift_pending_boarding",{})
	if marker.is_empty():return false
	var c: Dictionary=world.facts.connectors.get(marker.get("connector_id",""),{})
	if c.get("phase","")!="boarding" or c.get("active_group","")!=marker.get("group_leader",""):return false
	for pending: Dictionary in group(c,str(c.active_group)).get("pending_boarding",[]):
		if pending.actor_id==actor_id:return true
	return false

static func ensure(c: Dictionary) -> void:
	if c.has("lift_control_version") or c.phase!="idle" or not c.riders.is_empty(): return
	c.lift_control_version=1
	c.direction=0
	c.landing_queues={}
	c.passenger_groups=[]
	c.active_group=""

static func group(c: Dictionary, id: String) -> Dictionary:
	for g: Dictionary in c.passenger_groups:
		if g.actor_id==id: return g
	return {}

static func _leaders(g: Dictionary) -> Array:
	return g.get("leader_ids",[g.actor_id])

static func _riders(c: Dictionary) -> void:
	c.riders=[]
	for g: Dictionary in c.passenger_groups:
		for id: String in g.members: c.riders.append(id)

static func _convoy(world: WorldState, g: Dictionary) -> bool:
	for id: String in _leaders(g):
		if world.facts.moves.get(id,{}).has("convoy"): return true
	return false

# Existing canonical body envelopes define capacity. Articulated groups also
# prove both boarding and alighting routes before sharing the cabin.
static func placement(space: HospitalSpace, world: WorldState, c: Dictionary, entry: Dictionary) -> Dictionary:
	for stay: Dictionary in world.facts.get("visitors",{}).get("stays",{}).values():
		if stay.get("purpose","")!="companion" or stay.get("phase","")=="outside": continue
		var visit: Dictionary=world.facts.visits.get(stay.get("visit_id",""),{})
		if visit.get("actor_id","") in entry.members and not stay.actor_id in entry.members:
			return {"ok":false,"reason":"等待陪同家属实际会合，一起乘梯","awaiting_companion":true}
	var definition: Dictionary=space.content.definition("vertical_connectors",c.definition_id)
	var dims: Vector2i=Vector2i(int(definition.cabin_size[0]),int(definition.cabin_size[1]))
	var used: Array[Rect2]=[]
	var departure_sweeps: Array[Rect2]=[]
	for existing: Dictionary in c.passenger_groups:
		var plans: Array=[]
		for owner: String in _leaders(existing):
			var p: Dictionary=world.facts.moves.get(owner,{}).get("convoy",{}).get("portal",{}).get("plan",{})
			if p.get("mode","")=="articulated": plans.append(p)
			elif not p.is_empty():
				# Keep the existing legacy whole-convoy turning contract. A
				# later independent group cannot sit inside its departure area;
				# compatible cabin space outside this region remains shareable.
				var old: Dictionary=world.facts.moves[owner]
				var size: float=float(old.convoy.size)
				departure_sweeps.append(Rect2(0,0,size if old.members.size()==1 else size*2.5,size if old.members.size()==1 else size*3.0))
		for portal: Dictionary in existing.get("companion_portals",{}).values(): plans.append(portal.plan)
		for p: Dictionary in plans:
			for frame: Dictionary in p.alighting:
				for sweep: Dictionary in frame.get("cabin_sweeps",[]):
					var r: Array=sweep.rect
					departure_sweeps.append(Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3])))
	for g: Dictionary in c.passenger_groups:
		for id: String in g.members:
			var k: int=space.clearance(world.facts.actors[id])
			var plan: Dictionary=world._articulated_member_plan(id)
			if not plan.is_empty():
				var r: Array=plan.cabin_regions[id]
				used.append(Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3])))
			else: used.append(Rect2(ConvoyTrail.point(g.cabin_positions[id]),Vector2(k,k)))
	var exclusive: bool=_convoy(world,entry)
	var positions: Dictionary={}
	for owner: String in _leaders(entry):
		var movement: Dictionary=world.facts.moves.get(owner,{})
		var fit: Dictionary=HospitalTransit.fits(space,world,c,owner,movement.get("members",[owner]))
		if not fit.ok: return fit
	for owner: String in _leaders(entry):
		var movement: Dictionary=world.facts.moves[owner]
		if not movement.has("convoy"): continue
		var plan: Dictionary=ConvoyPortal.plan(space,world,c,owner,movement.members,movement.convoy)
		var trial: Dictionary=movement.convoy.duplicate(true)
		if not plan.get("ok",false): return plan
		if plan.get("mode","")=="articulated":
			# The plan proves actual bodies, rotation and the open doorway. Do
			# not turn its final positions back into the old giant trail proxy.
			for frame: Dictionary in plan.boarding+plan.alighting:
				for sweep: Dictionary in frame.get("cabin_sweeps",[]):
					var r: Array=sweep.rect
					var rect: Rect2=Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3]))
					if used.any(func(other:Rect2)->bool:return other.intersects(rect,false)):
						return {"ok":false,"reason":"已有乘员阻挡护理组分阶段入舱，整组等待下一趟"}
			for id: String in movement.members:
				positions[id]=plan.cabin_positions[id].duplicate()
				var r: Array=plan.cabin_regions[id]
				var region: Rect2=Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3]))
				if departure_sweeps.any(func(other:Rect2)->bool:return other.intersects(region,false)):return {"ok":false,"reason":"护理组座位会阻挡已有乘员真实出舱路线"}
				used.append(region)
			continue
		var swept_size: float=float(movement.convoy.size)
		var swept: Rect2=Rect2(0,0,swept_size if movement.members.size()==1 else swept_size*2.5,swept_size if movement.members.size()==1 else swept_size*3.0)
		if used.any(func(rect:Rect2)->bool:return rect.intersects(swept,false)):
			return {"ok":false,"reason":"现有乘员占据护理组实际转弯包络，整组等待下一趟"}
		var entry_point: Vector2=ConvoyTrail.point(plan.entry)
		var tail_point: Vector2=entry_point-ConvoyTrail.point(plan.inward)*float(trial.spacing)*(movement.members.size()-1)
		trial.points=[[tail_point.x,tail_point.y],[entry_point.x,entry_point.y]] if movement.members.size()>1 else [[entry_point.x,entry_point.y]]
		var portal_cursor: int=0
		var safety: int=0
		while portal_cursor<plan.boarding.size() and safety<10000:
			var proposal: Dictionary=ConvoyPortal.propose_step(trial,plan.boarding,portal_cursor,space.walking_speed(world.facts.actors[owner])*WorldState.TICK_SECONDS)
			if not proposal.ok: return {"ok":false,"reason":"完整同行组无法沿真实登舱路径进入"}
			trial.points=proposal.points;portal_cursor=int(proposal.cursor);safety+=1
		if portal_cursor<plan.boarding.size(): return {"ok":false,"reason":"完整同行组登舱路径没有有限进展"}
		var inward: Vector2=ConvoyTrail.point(plan.inward)
		var side: Vector2=Vector2(-inward.y,inward.x)
		var origin: Vector2=ConvoyTrail.point(plan.entry)
		var poses: Dictionary=ConvoyTrail.positions(trial,movement.members)
		for id: String in movement.members:
			var p: Vector2=ConvoyTrail.point(poses[id].cell)-origin
			var k: float=float(space.clearance(world.facts.actors[id]))
			var corners: Array[Vector2]=[p,p+Vector2(k,0),p+Vector2(0,k),p+Vector2(k,k)]
			var x: float=INF;var y: float=INF
			for corner: Vector2 in corners: x=minf(x,corner.dot(side));y=minf(y,corner.dot(inward))
			positions[id]=[x,y]
		# The portal proves the complete turn in an empty cabin. Companions
		# enter only AFTER that turn, so final bodies, not the swept union,
		# consume the shared destination capacity.
		for id: String in movement.members:
			var size: int=space.clearance(world.facts.actors[id])
			var region: Rect2=Rect2(ConvoyTrail.point(positions[id]),Vector2(size,size))
			if departure_sweeps.any(func(other:Rect2)->bool:return region.intersects(other,false)):
				return {"ok":false,"reason":"护理组座位会阻挡已有乘员真实出舱路线"}
			used.append(region)
	var companions: Dictionary={}
	var nursing_plan: Dictionary={}
	for owner: String in _leaders(entry):
		var m: Dictionary=world.facts.moves[owner]
		if m.has("convoy"):
			var candidate: Dictionary=ConvoyPortal.plan(space,world,c,owner,m.members,m.convoy)
			if candidate.get("mode","")=="articulated": nursing_plan=candidate
	for id: String in entry.members:
		if positions.has(id): continue
		var k: int=space.clearance(world.facts.actors[id]);var found: bool=false
		var offset: int=0
		for owner: String in _leaders(entry):
			if owner==id: break
			offset+=maxi(1,space.clearance(world.facts.actors[owner]))
		for y: int in range(dims.y-k+1):
			if found: break
			for x: int in range(dims.x-k+1):
				var rect: Rect2=Rect2(x,y,k,k)
				var portal: Dictionary={}
				if not nursing_plan.is_empty():
					var target: Vector2=Landing.companion_entry(space,world.facts.actors[id],nursing_plan,offset)
					portal=ArticulatedLiftPortal.companion_plan(space,world,c,nursing_plan,id,[target.x,target.y],[x,y],float(world.facts.actors[id].facing))
					if not portal.get("ok",false): continue
					var inward: Vector2=ConvoyTrail.point(nursing_plan.inward)
					var side: Vector2=Vector2(-inward.y,inward.x)
					var r: Array=portal.seated_pose.region
					var actual: Rect2=Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3]))
					var lo: Vector2=Vector2(INF,INF);var hi: Vector2=Vector2(-INF,-INF)
					for corner: Vector2 in [actual.position,Vector2(actual.end.x,actual.position.y),actual.end,Vector2(actual.position.x,actual.end.y)]:
						var d: Vector2=corner-ConvoyTrail.point(c.anchor)
						var projected: Vector2=Vector2(d.dot(side),d.dot(inward))
						lo=lo.min(projected);hi=hi.max(projected)
					rect=Rect2(lo,hi-lo)
					var blocked: bool=false
					for frame: Dictionary in portal.boarding:
						for sweep: Dictionary in frame.cabin_sweeps:
							var raw: Array=sweep.rect
							var swept: Rect2=Rect2(float(raw[0]),float(raw[1]),float(raw[2]),float(raw[3]))
							if used.any(func(other:Rect2)->bool:return other.intersects(swept,false)): blocked=true;break
						if blocked: break
					if blocked: continue
				if used.any(func(other:Rect2)->bool:return rect.intersects(other,false)): continue
				if departure_sweeps.any(func(other:Rect2)->bool:return rect.intersects(other,false)): continue
				positions[id]=[x,y];used.append(rect);found=true
				if not portal.is_empty():companions[id]={"plan":portal,"cursor":0,"stage":"boarding"}
				break
		if not found: return {"ok":false,"reason":"轿厢或真实连续入口无法容纳队首完整同行组"}
	return {"ok":true,"reason":"","positions":positions,"exclusive":exclusive,"companion_portals":companions}

static func _service_blocked(c: Dictionary) -> bool:
	return bool(c.get("maintenance_block",false)) or bool(c.get("upgrading_block",false))

static func begin(space: HospitalSpace, world: WorldState, actor: Dictionary, movement: Dictionary, segment: Dictionary) -> void:
	var c: Dictionary=world.facts.connectors[segment.connector_id]
	ensure(c)
	# sync owns seeking, actual arrival and safe queue positions. Calling this
	# on a connector never boards a remote group or bypasses the physical FIFO.
	if not movement.has("lift_boarding_call"): return
	if c.phase!="idle" or int(c.floor_id)!=int(segment.from): return
	# An invitation is not acceptance: equipment state can change while the
	# group walks to the door. Recheck at the actual boarding boundary.
	if _service_blocked(c) or bool(c.get("pending_failure",false)): return
	if bool(c.get("failed",false)) and int(segment.to)>=int(segment.from): return
	var entry: Dictionary=head(c,int(segment.from),int(c.direction))
	if entry.is_empty() or not actor.id in _leaders(entry): return
	if actor.id!=str(entry.actor_id): return
	if not _entry_ready(space,world,c,entry): return
	var fit: Dictionary=placement(space,world,c,entry)
	if not fit.ok:
		c.waiting_reason=fit.reason
		return
	_board(space,world,c,entry,fit)

static func _entry_ready(space: HospitalSpace, world: WorldState, c: Dictionary, entry: Dictionary) -> bool:
	if entry.get("layout_blocked",false): return false
	for owner: String in _leaders(entry):
		var m: Dictionary=world.facts.moves.get(owner,{})
		if m.is_empty() or m.has("local_move") or m.has("detour") or m.get("route_pending",false): return false
		var a: Dictionary=world.facts.actors[owner]
		var trip: Dictionary=HospitalTransit.journey(m)
		if trip.is_empty() or int(trip.to)!=int(entry.destination): return false
		if m.has("convoy"):
			var plan: Dictionary=ConvoyPortal.plan(space,world,c,owner,m.members,m.convoy)
			if not plan.ok or not space.at(world,owner,int(entry.floor_id),plan.entry) or not HospitalTransit._convoy_entry_aligned(m.convoy,plan): return false
		else:
			var target: Array=entry.get("entry_cells",{}).get(owner,c.anchor)
			if not space.at(world,owner,int(entry.floor_id),target): return false
		if a.location.kind!="floor": return false
	return true

static func _board(space: HospitalSpace, world: WorldState, c: Dictionary, entry: Dictionary, fit: Dictionary) -> void:
	var g: Dictionary={"actor_id":entry.actor_id,"leader_ids":_leaders(entry).duplicate(),"members":entry.members.duplicate(),"from":int(c.floor_id),"to":int(entry.destination),"cabin_positions":fit.positions,"exclusive":fit.exclusive,"entry_cells":entry.get("entry_cells",{}).duplicate(true),"receipt":"lift:%s:%s:%s"%[c.id,entry.actor_id,world.sim_tick]}
	if not fit.get("companion_portals",{}).is_empty(): g.companion_portals=fit.companion_portals.duplicate(true)
	if bool(fit.exclusive) and _leaders(g).size()>1:
		g.pending_boarding=[]
		for owner: String in _leaders(g).duplicate():
			var m: Dictionary=world.facts.moves[owner]
			if m.has("convoy"): continue
			assert(m.get("members",[owner])==[owner])
			g.pending_boarding.append({"actor_id":owner,"members":[owner],"cabin_positions":{owner:g.cabin_positions[owner].duplicate()},"entry_cell":g.entry_cells.get(owner,c.anchor).duplicate()})
			g.leader_ids.erase(owner);g.members.erase(owner);g.cabin_positions.erase(owner)
			m.lift_pending_boarding={"connector_id":c.id,"group_leader":g.actor_id}
			m.erase("lift_boarding_call");m.erase("lift_queue_target")
	c.passenger_groups.append(g)
	c.active_group=g.actor_id;c.primary_actor_id=g.actor_id;c.phase="boarding"
	c.from=c.floor_id;c.to=c.floor_id
	c.remaining_ticks=HospitalTransit._boarding(space.content.definition("vertical_connectors",c.definition_id))
	for owner: String in _leaders(g):
		var m: Dictionary=world.facts.moves[owner]
		m.erase("lift_boarding_call");m.erase("lift_queue_target")
		var trip: Dictionary=HospitalTransit.journey(m)
		while int(m.cursor)<m.path.size() and m.path[int(m.cursor)].kind!="connector": m.cursor+=1
		if int(m.cursor)<m.path.size(): m.cursor+=1
		if m.has("convoy"):
			var plan: Dictionary=ConvoyPortal.plan(space,world,c,owner,m.members,m.convoy)
			m.convoy.portal={"plan":plan,"cursor":0}
			if plan.get("mode","")=="articulated": m.convoy.portal.stage="boarding"
			var poses: Dictionary=ConvoyTrail.positions(m.convoy,m.members)
			for id: String in m.members:
				world.facts.actors[id].location={"kind":"transit","connector_id":c.id,"from":g.from,"to":g.to,"queue_cell":poses[id].cell,"cabin_cell":g.cabin_positions[id]}
		else:
			for id: String in m.get("members",[owner]): world.facts.actors[id].location={"kind":"transit","connector_id":c.id,"from":g.from,"to":g.to,"cabin_cell":g.cabin_positions[id]}
		for id: String in m.get("members",[owner]): space._sync_actor(world,id)
		if m.has("convoy"): space._sync_convoy(world,m)
	_riders(c)
	Landing.remove(c,str(entry.actor_id))

static func _service_done(c: Dictionary) -> void:
	c.phase="idle";c.active_group="";c.remaining_ticks=0
	c.erase("primary_actor_id")

static func _boarding_step(space: HospitalSpace, world: WorldState, c: Dictionary, g: Dictionary) -> void:
	c.remaining_ticks=maxi(0,int(c.remaining_ticks)-1)
	var done: bool=true
	for owner: String in _leaders(g):
		var m: Dictionary=world.facts.moves[owner]
		if not m.has("convoy"): continue
		var portal: Dictionary=m.convoy.portal
		space.movement._move_convoy_portal(world,world.facts.actors[owner],m,portal.plan.boarding,int(g.from),str(c.id))
		if int(portal.cursor)<portal.plan.boarding.size(): done=false
	if done and int(c.remaining_ticks)==0:
		if not g.get("pending_boarding",[]).is_empty():
			for pending: Dictionary in g.pending_boarding:
				var owner: String=pending.actor_id
				var m: Dictionary=world.facts.moves[owner]
				if g.get("companion_portals",{}).has(owner):
					if not _companion_step(space,world,c,g,owner,int(g.from)): return
				elif not space.at(world,owner,int(g.from),pending.entry_cell):
					c.waiting_reason="等待已到场家属完成当前入口交接";return
			for pending: Dictionary in g.pending_boarding:
				var owner: String=pending.actor_id
				var m: Dictionary=world.facts.moves[owner]
				while int(m.cursor)<m.path.size() and m.path[int(m.cursor)].kind!="connector":m.cursor+=1
				if int(m.cursor)<m.path.size():m.cursor+=1
				m.erase("lift_pending_boarding")
				g.leader_ids.append(owner);g.members.append(owner);g.cabin_positions[owner]=pending.cabin_positions[owner].duplicate()
				world.facts.actors[owner].location={"kind":"transit","connector_id":c.id,"from":g.from,"to":g.to,"cabin_cell":g.cabin_positions[owner]}
				space._sync_actor(world,owner)
			g.erase("pending_boarding");_riders(c)
			c.remaining_ticks=HospitalTransit._boarding(space.content.definition("vertical_connectors",c.definition_id))
			return
		_service_done(c)

static func _start_alighting(space: HospitalSpace, world: WorldState, c: Dictionary, g: Dictionary) -> void:
	c.phase="alighting";c.active_group=g.actor_id;c.primary_actor_id=g.actor_id
	c.from=c.floor_id;c.to=c.floor_id
	c.remaining_ticks=HospitalTransit._alighting(space.content.definition("vertical_connectors",c.definition_id))
	if _convoy(world,g) and _leaders(g).any(func(owner:String)->bool:return not world.facts.moves[owner].has("convoy")):
		g.exit_stage="companions"
		for id: String in g.get("companion_portals",{}):
			var portal: Dictionary=g.companion_portals[id]
			portal.stage="alighting";portal.cursor=0
			world.facts.actors[id].location.queue_cell=portal.plan.seated_pose.cell.duplicate()
			space._sync_actor(world,id)
		return
	_start_convoy_exit(space,world,c,g)

static func _start_convoy_exit(space: HospitalSpace, world: WorldState, c: Dictionary, g: Dictionary) -> void:
	for owner: String in _leaders(g):
		var m: Dictionary=world.facts.moves[owner]
		if m.has("convoy"):
			m.convoy.portal.cursor=0;m.convoy.floor_id=int(c.floor_id)
			if m.convoy.portal.plan.get("mode","")=="articulated":m.convoy.portal.stage="alighting"
			space._sync_convoy(world,m)

static func _ordinary_egress_clear(space: HospitalSpace, world: WorldState, c: Dictionary, g: Dictionary, owner: String, m: Dictionary) -> bool:
	var target: Array=g.get("entry_cells",{}).get(owner,c.anchor)
	var proxy: Dictionary=c.duplicate(true)
	proxy.anchor=target
	return HospitalTransit.egress_clear(space,world,proxy,owner,int(c.floor_id),m.get("members",[owner]),m.get("offsets",{}))

static func _alighting_step(space: HospitalSpace, world: WorldState, c: Dictionary, g: Dictionary) -> void:
	c.remaining_ticks=maxi(0,int(c.remaining_ticks)-1)
	if g.get("exit_stage","")=="companions":
		if int(c.remaining_ticks)>0:return
		for owner: String in _leaders(g):
			var m: Dictionary=world.facts.moves[owner]
			if m.has("convoy"):continue
			if g.get("companion_portals",{}).has(owner):
				if not _companion_step(space,world,c,g,owner,int(c.floor_id)): return
			elif not _ordinary_egress_clear(space,world,c,g,owner,m):
				c.waiting_reason="家属先下梯，等待真实出口空出";return
		for owner: String in _leaders(g).duplicate():
			var m: Dictionary=world.facts.moves[owner]
			if m.has("convoy"):continue
			var target: Array=g.entry_cells.get(owner,c.anchor)
			if g.get("companion_portals",{}).has(owner): target=g.companion_portals[owner].plan.final_pose.cell
			world.facts.actors[owner].location={"kind":"floor","floor_id":int(c.floor_id),"cell":target.duplicate()}
			space._sync_actor(world,owner)
			m.travelled.append(space.movement._checkpoint(world.facts.actors[owner]))
			g.leader_ids.erase(owner);g.members.erase(owner);g.cabin_positions.erase(owner)
			g.get("companion_portals",{}).erase(owner)
		g.erase("exit_stage");_riders(c)
		_start_convoy_exit(space,world,c,g)
		c.remaining_ticks=HospitalTransit._alighting(space.content.definition("vertical_connectors",c.definition_id))
		return
	var done: bool=true
	for owner: String in _leaders(g):
		var m: Dictionary=world.facts.moves[owner]
		if m.has("convoy"):
			var portal: Dictionary=m.convoy.portal
			space.movement._move_convoy_portal(world,world.facts.actors[owner],m,portal.plan.alighting,int(c.floor_id),str(c.id))
			if int(portal.cursor)<portal.plan.alighting.size(): done=false
		elif not _ordinary_egress_clear(space,world,c,g,owner,m):
			c.waiting_reason="电梯出口被身体或设施阻挡，等待真实出口空出";done=false
	if not done or int(c.remaining_ticks)>0: return
	# Publish only actual completed exit. Independent companions keep their own
	# route suffixes; their egress positions are assigned collision-free below.
	var published: Array[Rect2]=[]
	var poses: Dictionary={}
	for owner: String in _leaders(g):
		var m: Dictionary=world.facts.moves[owner]
		if m.has("convoy"):
			for id: String in m.members:
				poses[id]=ConvoyTrail.positions(m.convoy,m.members)[id].cell
				published.append(space._actor_rect(world.facts.actors[id],ConvoyTrail.point(poses[id])))
		else:
			for id: String in m.get("members",[owner]):
				var offset: Array=m.get("offsets",{}).get(id,[0,0])
				var target: Vector2=ConvoyTrail.point(g.get("entry_cells",{}).get(owner,c.anchor))+ConvoyTrail.point(offset)
				var body: Rect2=space._actor_rect(world.facts.actors[id],target)
				if published.any(func(other:Rect2)->bool:return body.intersects(other,false)):
					c.waiting_reason="完整同行组出口空间不足";return
				published.append(body);poses[id]=[target.x,target.y]
	for owner: String in _leaders(g):
		var m: Dictionary=world.facts.moves[owner]
		for id: String in m.get("members",[owner]):
			world.facts.actors[id].location={"kind":"floor","floor_id":int(c.floor_id),"cell":poses[id]};space._sync_actor(world,id)
		if m.has("convoy"):
			if m.convoy.portal.plan.get("mode","")=="articulated":m.convoy.points=m.convoy.portal.plan.final_ground_points.duplicate(true)
			m.convoy.erase("portal");m.convoy.floor_id=int(c.floor_id);space._sync_convoy(world,m)
		m.travelled.append(space.movement._checkpoint(world.facts.actors[owner]))
	_record_use(space,world,c,g)
	c.passenger_groups.erase(g);_riders(c);_service_done(c)

static func _record_use(space: HospitalSpace, world: WorldState, c: Dictionary, g: Dictionary) -> void:
	if not c.has("use_receipts"): c.use_receipts={}
	if c.use_receipts.has(g.receipt): return
	c.use_receipts[g.receipt]=world.sim_tick;c.used=true
	var d: Dictionary=space.content.definition("vertical_connectors",c.definition_id)
	for row: Dictionary in space.content.balance.equipment.classes:
		if row.id==d.equipment_class: c.condition=maxf(0,float(c.get("condition",100))-float(row.wear_per_use))

static func head(c: Dictionary, floor_id: int, direction: int) -> Dictionary:
	if bool(c.get("failed",false)) and direction>0: return {}
	var entry: Dictionary=Landing.head(c,floor_id,direction)
	if entry.get("layout_blocked",false): return {}
	if not entry.is_empty() and c.get("unavailable_heads",{}).has(entry.actor_id): return {}
	return entry

static func _refresh_unavailable(space: HospitalSpace, world: WorldState, c: Dictionary) -> void:
	c.unavailable_heads={}
	var empty: Dictionary=c.duplicate();empty.passenger_groups=[]
	for key: String in c.landing_queues:
		var line: Array=c.landing_queues[key]
		if line.is_empty(): continue
		var entry: Dictionary=line[0]
		var fit: Dictionary=placement(space,world,empty,entry)
		if fit.ok: continue
		if not fit.get("awaiting_companion",false):
			var reroute: Dictionary=LiftGroupReroute.try_route(space,world,c,entry)
			if reroute.ok: continue
			if not str(reroute.get("reason","")).is_empty(): fit.reason=reroute.reason
		c.unavailable_heads[entry.actor_id]=str(fit.reason)
		for owner: String in _leaders(entry):
			var m: Dictionary=world.facts.moves.get(owner,{})
			m.waiting_reason=fit.reason
			if not fit.get("awaiting_companion",false): m.lift_capability_error={"connector_id":c.id,"reason":fit.reason,"members":entry.members.duplicate()}
	# A physically impossible head stays visible without reserving the car.
	# Its FIFO followers cannot jump it; other floors/directions remain usable.

static func demands(c: Dictionary) -> Array:
	var result: Array=[]
	for g: Dictionary in c.passenger_groups:
		if not int(g.to) in result: result.append(int(g.to))
	for key: String in c.landing_queues:
		if bool(c.get("failed",false)) and int(key.get_slice(":",1))>0: continue
		if c.landing_queues[key].is_empty(): continue
		if c.get("unavailable_heads",{}).has(c.landing_queues[key][0].actor_id): continue
		var floor_id: int=int(key.get_slice(":",0))
		if not floor_id in result: result.append(floor_id)
	result.sort();return result

static func choose_direction(c: Dictionary) -> int:
	var floor_id: int=int(c.floor_id);var direction: int=int(c.direction)
	var floors: Array=demands(c)
	if direction!=0 and floors.any(func(f:int)->bool:return (f-floor_id)*direction>0): return direction
	if direction!=0 and not head(c,floor_id,direction).is_empty(): return direction
	if direction!=0 and (floors.any(func(f:int)->bool:return (f-floor_id)*direction<0) or not head(c,floor_id,-direction).is_empty()): return -direction
	if not head(c,floor_id,1).is_empty(): return 1
	if not head(c,floor_id,-1).is_empty(): return -1
	var best: int=0;var distance: int=MAX_TICK
	for target: int in floors:
		if target==floor_id: continue
		var d: int=absi(target-floor_id)
		if d<distance or d==distance and target>floor_id: best=signi(target-floor_id);distance=d
	return best

const MAX_TICK: int=9223372036854775807
static func next_stop(c: Dictionary) -> int:
	var here: int=int(c.floor_id);var dir: int=int(c.direction);var nearest: int=here;var farthest: int=here
	for f: int in demands(c):
		if (f-here)*dir<=0: continue
		if farthest==here or (f-farthest)*dir>0: farthest=f
		var serves: bool=not head(c,f,dir).is_empty()
		for g: Dictionary in c.passenger_groups:
			if int(g.to)==f: serves=true
		if serves and (nearest==here or (f-nearest)*dir<0): nearest=f
	return nearest if nearest!=here else farthest

static func advance(space: HospitalSpace, world: WorldState, c: Dictionary) -> void:
	Landing.sync(space,world,c)
	_refresh_unavailable(space,world,c)
	if c.phase in ["riding","empty_riding"]:
		c.remaining_ticks=maxi(0,int(c.remaining_ticks)-1)
		if int(c.remaining_ticks)>0: return
		c.floor_id=int(c.to);_service_done(c)
	if c.phase=="boarding": _boarding_step(space,world,c,group(c,str(c.active_group)));return
	if c.phase=="alighting": _alighting_step(space,world,c,group(c,str(c.active_group)));return
	for g: Dictionary in c.passenger_groups:
		if int(g.to)==int(c.floor_id): _start_alighting(space,world,c,g);return
	# New-style idle is only an open-door boundary, not an empty car. Finish
	# every already accepted destination (including the current group's pending
	# physical boarding) before failure changes the permitted service direction.
	# Do not admit or divert toward any new landing demand during that drain.
	if not c.passenger_groups.is_empty() and (bool(c.get("pending_failure",false)) or _service_blocked(c)):
		var committed: Dictionary=c.duplicate()
		committed.landing_queues={}
		committed.direction=choose_direction(committed)
		c.direction=int(committed.direction)
		var destination: int=next_stop(committed)
		if destination!=int(c.floor_id): _start_leg(space,c,destination,true)
		return
	HospitalTransit._finish_failure(c)
	if _service_blocked(c):
		c.waiting_reason="等待维修或升级完成"
		return
	# Failure restricts passenger direction, not empty-car repositioning.
	# Filtered demands contain only legal down calls; SCAN can therefore
	# reach the farthest upper call empty before turning down to board.
	c.direction=-1 if bool(c.get("failed",false)) and not c.passenger_groups.is_empty() else choose_direction(c)
	if int(c.direction)==0: c.waiting_reason="";return
	var entry: Dictionary=head(c,int(c.floor_id),int(c.direction))
	if not entry.is_empty():
		var fit: Dictionary=placement(space,world,c,entry)
		if fit.ok:
			Landing.release(space,world,c,entry)
			c.waiting_reason="等待本站队首完整同行组实际登梯"
			return
		c.waiting_reason=fit.reason
		if c.passenger_groups.is_empty():
			# No repeated fake next-trip promise for a group too large even for
			# an empty car. Its actual queue/route remains available to re-route.
			for owner: String in _leaders(entry): world.facts.moves[owner].waiting_reason=fit.reason
			return
	var target: int=next_stop(c)
	if target==int(c.floor_id) and (not HospitalTransit._lowering(c) or c.passenger_groups.is_empty()):
		c.direction=-int(c.direction);target=next_stop(c)
	if target==int(c.floor_id): return
	_start_leg(space,c,target)

static func _start_leg(space: HospitalSpace, c: Dictionary, target: int, committed: bool=false) -> void:
	var travel: int=HospitalTransit._travel_ticks(space,c,int(c.floor_id),target,committed)
	if travel<0:
		c.waiting_reason="电梯行程时间超出可表示范围";return
	c.from=int(c.floor_id);c.to=target
	c.remaining_ticks=travel
	c.phase="empty_riding" if c.passenger_groups.is_empty() else "riding"

# Independent family motion retains its original task owner. Each explicit
# frame is swept before publishing; the cursor is saved with the manifest.
static func _companion_step(space: HospitalSpace, world: WorldState, c: Dictionary, g: Dictionary, owner: String, floor_id: int) -> bool:
	var portal: Dictionary=g.companion_portals[owner]
	var frames: Array=portal.plan[portal.stage]
	var cursor: int=int(portal.cursor)
	if cursor>=frames.size(): return true
	var actor: Dictionary=world.facts.actors[owner]
	var movement: Dictionary=world.facts.moves[owner]
	var prior: Dictionary=portal.plan.initial_pose if cursor==0 and portal.stage=="boarding" else (portal.plan.seated_pose if cursor==0 else frames[cursor-1].poses[owner])
	if absf(angle_difference(float(actor.facing),float(prior.facing)))>0.00001:
		c.waiting_reason="家属入口朝向未与连续门户对齐";return false
	var frame: Dictionary=frames[cursor]
	for sweep: Dictionary in frame.get("cabin_sweeps",[]):
		var r: Array=sweep.rect
		var swept: Rect2=Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3]))
		for other: Dictionary in c.passenger_groups:
			for id: String in other.members:
				if id==owner: continue
				var shape: Dictionary=world._articulated_member_plan(id)
				var region: Rect2=Rect2(ConvoyTrail.point(other.cabin_positions[id]),Vector2.ONE*space.clearance(world.facts.actors[id]))
				if not shape.is_empty():
					var raw: Array=shape.cabin_regions[id]
					region=Rect2(float(raw[0]),float(raw[1]),float(raw[2]),float(raw[3]))
				if swept.intersects(region,false): c.waiting_reason="家属连续过门被实际舱内身体阻挡";return false
	var source: Dictionary=space._navigation.floor_source(space,world,floor_id).duplicate()
	source.connectors=source.connectors.duplicate();source.connectors.erase(str(c.id))
	var history: Array[Rect2]=[]
	var contacts: Array[BodyIndex.Record]=[]
	var combined: Rect2=Rect2()
	for sweep: Dictionary in frame.sweeps:
		var r: Array=sweep.rect
		var rect: Rect2=Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3]))
		var query: RouteClearance=RouteClearance.new(space,world,actor,floor_id,[owner],{},true,source)
		var reason: String=query.rectangle_reason(rect)
		if not reason.is_empty(): c.waiting_reason=reason;return false
		combined=rect if history.is_empty() else combined.merge(rect)
		history.append(rect)
		var contact: BodyIndex.Record=BodyIndex.Record.new()
		contact.id=owner;contact.sweep_from=rect;contact.sweep_to=rect;contacts.append(contact)
	var result: HospitalMovement.MotionResult=HospitalMovement.MotionResult.new()
	space.movement._movement_contacts(world,owner,floor_id,combined,contacts,[owner],result)
	if result.blocked: c.waiting_reason="家属连续上下梯扫掠受阻";return false
	var doors: Array[Dictionary]=[]
	for door: Dictionary in space.movement_doors(world,actor,combined,[],floor_id):
		var quote: Dictionary=space.door_quote(world,actor,floor_id,door,[])
		if quote.ok and combined.intersects(space._door_rect(door,int(quote.span)),false): doors.append(door)
	var ground_actor: Dictionary=actor.duplicate(true)
	ground_actor.location={"kind":"floor","floor_id":floor_id,"cell":prior.cell.duplicate()}
	if not space.movement._reserve_doors(world,ground_actor,movement,combined,doors,result): return false
	var pose: Dictionary=frame.poses[owner]
	if portal.stage=="boarding": actor.location.cell=pose.cell.duplicate()
	else: actor.location.queue_cell=pose.cell.duplicate()
	actor.facing=float(pose.facing);portal.cursor=cursor+1
	space._sync_actor(world,owner)
	var accepted: BodyIndex.Record=BodyIndex.Record.new();accepted.id=owner;accepted.regions=history
	space.movement._accepted_sweeps[owner]=accepted;space.movement._sweep_index.update_compound(owner,floor_id,history)
	space.movement._mark_door_use(world,floor_id,combined,doors)
	return int(portal.cursor)>=frames.size()
