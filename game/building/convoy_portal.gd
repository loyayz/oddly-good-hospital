class_name ConvoyPortal
extends RefCounted

# Persisted on convoy.portal: plan and cursor. The leader transit location
# identifies the connection, which owns phase and floor endpoints.
# plan contains actual leader-cell waypoints. Queue positions remain authoritative
# throughout boarding/riding/alighting; only their floor domain changes.
static func _raw(v: Vector2) -> Array:
	return [v.x,v.y]

static func plan(space: HospitalSpace, world: WorldState, connection: Dictionary, primary: String, members: Array, convoy: Dictionary) -> Dictionary:
	# Derived geometry is owned by this runtime space, never by a saved world
	# or a process-global cache. Every input that affects the proof is a value
	# in the key; current poses, queue tickets and occupancy are not inputs.
	var definition: Dictionary=space.content.definition("vertical_connectors",connection.definition_id)
	var key: Array=[connection.definition_id,connection.cell,connection.get("rotation",0),connection.get("footprint",[]),definition.kind,definition.max_group_size,definition.clear_width_m,definition.clear_height_m,definition.get("cabin_size"),definition.footprint,convoy.size,convoy.height,convoy.shift,convoy.spacing,convoy.centers.size(),members.size(),space.walking_speed(world.facts.actors[primary])].duplicate(true)
	var cache: Dictionary=space.get_meta("convoy_portal_plan_cache",{})
	if cache.has(key):
		space.query_counts["convoy_portal_plan_hits"]=int(space.query_counts.get("convoy_portal_plan_hits",0))+1
		# Callers persist their own copy; changing it cannot poison a later
		# canonical restore check or another actor's geometry proof.
		return cache[key].duplicate(true)
	var result: Dictionary=_build_plan(space,world,connection,primary,members,convoy)
	space.query_counts["convoy_portal_plan_builds"]=int(space.query_counts.get("convoy_portal_plan_builds",0))+1
	if cache.size()>=128: cache.clear()
	cache[key]=result.duplicate(true)
	space.set_meta("convoy_portal_plan_cache",cache)
	return result

static func _build_plan(space: HospitalSpace, world: WorldState, connection: Dictionary, primary: String, members: Array, convoy: Dictionary) -> Dictionary:
	var definition: Dictionary=space.content.definition("vertical_connectors",connection.definition_id)
	if members.size()>int(definition.max_group_size): return {"ok":false,"reason":"竖向连接容量不足以容纳完整队列"}
	if definition.kind=="stairs": return {"ok":false,"reason":"楼梯单人使用原单体通行契约"}
	var size: float=float(convoy.size)
	if size*HospitalSpace.CELL_METERS+0.1>float(definition.clear_width_m) or float(convoy.height)+0.1>float(definition.clear_height_m): return {"ok":false,"reason":"连接门净宽或净高不足以容纳队长代理"}
	var depth: float=size if members.size()==1 else 3.0*size
	var width: float=size if members.size()==1 else 2.5*size
	if width>float(definition.cabin_size[0]) or depth>float(definition.cabin_size[1]): return {"ok":false,"reason":"轿厢不足以完成前后队列真实转弯登离舱"}
	var inward: Vector2=Vector2.UP.rotated(float(connection.get("rotation",0))*PI*0.5).round()
	var side: Vector2=Vector2.RIGHT.rotated(float(connection.get("rotation",0))*PI*0.5).round()
	var dims: Vector2=Vector2(float(definition.footprint[0]),float(definition.footprint[1]))
	var center: Vector2=Vector2(size*0.5,dims.y+size*0.5)
	for turn: int in int(connection.get("rotation",0))%4:
		center=Vector2(dims.y-center.y,center.x)
		dims=Vector2(dims.y,dims.x)
	var origin: Vector2=ConvoyTrail.point(connection.cell)+center-Vector2.ONE*size*0.5
	var front: Vector2=origin+Vector2(maxf(0,inward.x),maxf(0,inward.y))*size
	var entry: Vector2=origin-Vector2.ONE*float(convoy.shift)
	var boarding: Array=[]
	if members.size()==1: boarding=[_raw(entry+inward*size)]
	else: boarding=[_raw(entry+inward*3.0*size),_raw(entry+inward*3.0*size+side*1.5*size),_raw(entry+inward*size+side*1.5*size),_raw(entry+inward*size)]
	boarding=_subdivide(entry,boarding,size*0.5)
	var egress: Vector2=entry-inward*float(convoy.spacing)*(members.size()-1)
	var result: Dictionary={"ok":true,"reason":"","entry":_raw(entry),"boarding":boarding,"egress":_raw(egress),"alighting":_subdivide(ConvoyTrail.point(boarding[-1]),[_raw(egress)],size*0.5),"inward":_raw(inward)}
	var trial: Dictionary=convoy.duplicate(true)
	var tail: Vector2=entry-inward*float(convoy.spacing)*(members.size()-1)
	trial.points=[_raw(tail),_raw(entry)] if members.size()>1 else [_raw(entry)]
	var distance: float=0.0
	var speed: float=space.walking_speed(world.facts.actors[primary])*WorldState.TICK_SECONDS
	if speed<=0: return {"ok":false,"reason":"队列通行速度必须为正"}
	var simulated_ticks: int=0
	var boarding_ticks: int=0
	# One frame has one distance budget. Milestones split the safety proof, not
	# time: unused distance continues through a corner in this same proposal.
	for targets: Array in [boarding,result.alighting]:
		var cursor: int=0
		while cursor<targets.size():
			var proposal: Dictionary=propose_step(trial,targets,cursor,speed)
			if not proposal.ok: return {"ok":false,"reason":"队列间距或转弯路径不能安全登离舱："+str(proposal.reason)}
			trial.points=proposal.points
			cursor=int(proposal.cursor)
			distance+=float(proposal.distance)
			simulated_ticks+=1
		if boarding_ticks==0:
			boarding_ticks=simulated_ticks
			# Full trail envelope must be in the cabin side of the portal.
			for region: Rect2 in ConvoyTrail.regions(trial):
				if not _outside(region,front,inward).has_area(): continue
				return {"ok":false,"reason":"完整队尾尚不能进入轿厢"}
	result.boarding_ticks=maxi(boarding_ticks,HospitalTransit._boarding(definition))
	result.alighting_ticks=maxi(simulated_ticks-boarding_ticks,HospitalTransit._alighting(definition))
	result.walk_distance=distance
	return result

static func _outside(region: Rect2, front: Vector2, inward: Vector2) -> Rect2:
	var lo: Vector2=region.position
	var hi: Vector2=region.end
	if inward.y<0: lo.y=maxf(lo.y,front.y)
	elif inward.y>0: hi.y=minf(hi.y,front.y)
	elif inward.x<0: lo.x=maxf(lo.x,front.x)
	else: hi.x=minf(hi.x,front.x)
	return Rect2(lo,Vector2(maxf(0,hi.x-lo.x),maxf(0,hi.y-lo.y)))

static func ground_regions(convoy: Dictionary, connection: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2]=[]
	if connection.phase=="riding": return result
	if not convoy.has("portal"): return ConvoyTrail.regions(convoy)
	var cabin: Rect2=Rect2(ConvoyTrail.point(connection.cell),ConvoyTrail.point(connection.footprint))
	for region: Rect2 in ConvoyTrail.regions(convoy):
		var cut: Rect2=region.intersection(cabin)
		if not cut.has_area():
			result.append(region)
			continue
		var parts: Array[Rect2]=[
			Rect2(region.position,Vector2(region.size.x,cut.position.y-region.position.y)),
			Rect2(Vector2(region.position.x,cut.end.y),Vector2(region.size.x,region.end.y-cut.end.y)),
			Rect2(Vector2(region.position.x,cut.position.y),Vector2(cut.position.x-region.position.x,cut.size.y)),
			Rect2(Vector2(cut.end.x,cut.position.y),Vector2(region.end.x-cut.end.x,cut.size.y))]
		for part: Rect2 in parts:
			if part.has_area(): result.append(part)
	return result

static func predict(convoy: Dictionary, p: Dictionary, tofloor: int) -> Dictionary:
	var result: Dictionary=convoy.duplicate(true)
	var head: Vector2=ConvoyTrail.point(p.egress)
	var inward: Vector2=ConvoyTrail.point(p.inward)
	var span: float=float(convoy.spacing)*(convoy.centers.size()-1)
	result.points=[_raw(head+inward*span),_raw(head)] if span>0 else [_raw(head)]
	result.floor_id=tofloor
	result.erase("portal")
	return result

# Explicit portal milestones split a compound proposal at square-separation
# events after corners. They do not each consume a frame. The guard is unchanged.
static func _subdivide(start: Vector2, targets: Array, step: float) -> Array:
	var result: Array=[]
	for raw: Array in targets:
		var target: Vector2=ConvoyTrail.point(raw)
		while not start.is_equal_approx(target):
			start=start.move_toward(target,step)
			result.append(_raw(start))
	return result

# Pure proposal: no poses, ownership, cursor or world facts change before all
# subsegments pass. Only this leader path is checked; followers publish once.
static func propose_step(convoy: Dictionary, targets: Array, cursor: int, budget: float) -> Dictionary:
	if budget<=0.0 or cursor<0 or cursor>=targets.size(): return {"ok":false,"reason":"队列登离舱步进无效"}
	var trial: Dictionary=convoy.duplicate(true)
	var path: Array=[convoy.points[-1].duplicate()]
	var history: Array=convoy.points.duplicate(true)
	var fronts: Array[Rect2]=[]
	var distance: float=0.0
	while cursor<targets.size() and budget>0.000001:
		var start: Vector2=ConvoyTrail.point(trial.points[-1])
		var target: Vector2=ConvoyTrail.point(targets[cursor])
		var span: float=start.distance_to(target)
		if span<0.000001:
			cursor+=1
			continue
		# Absorb float32 coordinate drift at milestones, within the same
		# distance tolerance used by remaining-time quotes.
		var next: Vector2=target if span<=budget+0.00002 else start.move_toward(target,budget)
		var piece: Dictionary=ConvoyTrail.propose(trial,next)
		if not piece.ok: return piece
		trial.points=piece.points
		path.append(_raw(next))
		history=ConvoyTrail.extended(history,next)
		fronts.append(piece.front)
		var advance: float=start.distance_to(next)
		distance+=advance
		# Vector2 coordinates are float32: subtracting their rounded displacement
		# can leave a positive sub-ULP remainder that never moves. A partial leg
		# spends the requested budget; a completed milestone spends its span.
		# Thus every iteration advances the cursor or exhausts this frame.
		if next==target:
			budget=maxf(0.0,budget-span)
			cursor+=1
		else: budget=0.0
	if fronts.is_empty(): return {"ok":false,"reason":"队列登离舱没有实际移动"}
	var broad: Rect2=fronts[0]
	for front: Rect2 in fronts: broad=broad.merge(front)
	return {"ok":true,"points":trial.points,"cursor":cursor,"path":path,"fronts":fronts,"front":broad,"history":ConvoyTrail.regions(convoy,history),"distance":distance,"segment_count":fronts.size()}
