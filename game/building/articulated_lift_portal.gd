class_name ArticulatedLiftPortal
extends RefCounted

# Pure two-body portal plan. The ordinary ground convoy remains unchanged.
# Every frame is explicit about side/backward motion and facing; callers must
# sweep these frames against actual landing geometry/people before publishing.
const VERSION: int=1
const LIMIT: int=12000

static func _raw(v: Vector2) -> Array: return [v.x,v.y]
static func _rect(r: Rect2) -> Array: return [r.position.x,r.position.y,r.size.x,r.size.y]

static func plan(space: HospitalSpace, world: WorldState, c: Dictionary, owner: String, members: Array, convoy: Dictionary) -> Dictionary:
	var definition: Dictionary=space.content.definition("vertical_connectors",c.definition_id)
	var bodies: Array=[]
	for id: String in members:
		if not world.facts.actors.has(id): return {"ok":false,"reason":"独立门户成员不存在"}
		if str(world.facts.actors[id].get("posture","standing"))!="standing": return {"ok":false,"reason":"独立门户仅支持站立成员"}
		bodies.append([id,world.facts.actors[id].get("posture","standing"),space.body(world.facts.actors[id]),space.clearance(world.facts.actors[id]),space.walking_speed(world.facts.actors[id])])
	var key: String=JSON.stringify([VERSION,c.definition_id,c.anchor,c.get("rotation",0),definition,owner,members,convoy.get("spacing"),convoy.get("size"),convoy.get("shift"),convoy.get("centers"),bodies],"",true,true)
	var cache: Dictionary=space.get_meta("articulated_lift_plan_cache",{})
	if cache.has(key): return cache[key].duplicate(true)
	var result: Dictionary=_build(space,world,c,owner,members,convoy,definition)
	if cache.size()>=64: cache.clear()
	cache[key]=result.duplicate(true);space.set_meta("articulated_lift_plan_cache",cache)
	return result

static func _build(space: HospitalSpace, world: WorldState, c: Dictionary, owner: String, members: Array, convoy: Dictionary, definition: Dictionary) -> Dictionary:
	if members.size()!=2 or members[0]!=owner or definition.kind!="lift": return {"ok":false,"reason":"独立门户仅支持护士领队的两人电梯交接"}
	var width: float=float(definition.cabin_size[0]);var depth: float=float(definition.cabin_size[1])
	var doorway: float=minf(width,float(definition.clear_width_m)/HospitalSpace.CELL_METERS)
	var inward: Vector2=Vector2.UP.rotated(float(c.get("rotation",0))*PI*0.5).round()
	var side: Vector2=Vector2(-inward.y,inward.x)
	var facing: float=atan2(inward.x,inward.y)
	var context: Dictionary={"space":space,"world":world,"members":members,"anchor":ConvoyTrail.point(c.anchor),"inward":inward,"side":side,"depth":depth,"width":width,"doorway":doorway,"poses":{},"local":{},"frames":[],"distance":0.0,"radii":{},"dimensions":{},"speeds":{},"error":""}
	var halves: Dictionary={}
	for id: String in members:
		var actor: Dictionary=world.facts.actors[id];var body: Dictionary=space.body(actor)
		var half: float=maxf(float(body.width_m),float(body.depth_m))/HospitalSpace.CELL_METERS*0.5
		if half*2.0+0.1/HospitalSpace.CELL_METERS>doorway or float(body.height_m)+0.1>float(definition.clear_height_m): return {"ok":false,"reason":"成员真实身体含安全余量超过门净宽或净高"}
		var speed: float=space.walking_speed(actor)*WorldState.TICK_SECONDS
		if speed<=0: return {"ok":false,"reason":"成员实际速度必须为正"}
		halves[id]=half;context.radii[id]=Vector2(float(body.width_m),float(body.depth_m)).length()/HospitalSpace.CELL_METERS*0.5
		context.dimensions[id]=body.duplicate(true);context.speeds[id]=speed
	var patient: String=members[1]
	var lane: float=doorway*0.5
	var outside: float=depth+maxf(float(convoy.size)*0.5,maxf(float(context.radii[owner]),float(context.radii[patient])))+0.25
	var nurse_y: float=float(halves[owner])+0.15
	var nurse_x: float=width-float(halves[owner])-0.15
	var patient_y: float=float(halves[patient])+0.15
	if nurse_x-float(halves[owner])<=lane+float(halves[patient]) or nurse_y+float(halves[owner])>=depth or patient_y+float(halves[patient])>=depth: return {"ok":false,"reason":"轿厢不能分阶段容纳真实护理两人"}
	var spacing: float=float(convoy.spacing)
	context.local[owner]=Vector2(lane,outside);context.local[patient]=Vector2(lane,outside+spacing)
	for id: String in members: context.poses[id]=_pose(context,id,context.local[id],facing)
	var initial: Dictionary=context.poses.duplicate(true)
	var entry: Array=initial[owner].cell.duplicate()
	# These are fixed-facing straight translations, explicitly including
	# lateral steps. No hidden facing-from-velocity shortcut is permissible.
	_line(context,owner,Vector2(lane,nurse_y))
	_line(context,owner,Vector2(nurse_x,nurse_y))
	_line(context,patient,Vector2(lane,patient_y))
	if not str(context.error).is_empty(): return {"ok":false,"reason":context.error}
	var boarding: Array=context.frames;context.frames=[]
	var cabin_positions: Dictionary={};var cabin_regions: Dictionary={}
	for id: String in members:
		var cell: Vector2=ConvoyTrail.point(context.poses[id].cell)-context.anchor
		cabin_positions[id]=[cell.dot(side),cell.dot(inward)]
		var region: Rect2=_region(context.poses[id]);var lo: Vector2=Vector2(INF,INF);var hi: Vector2=Vector2(-INF,-INF)
		for corner: Vector2 in [region.position,Vector2(region.end.x,region.position.y),region.end,Vector2(region.position.x,region.end.y)]:
			var delta: Vector2=corner-context.anchor;var projected: Vector2=Vector2(delta.dot(side),delta.dot(inward))
			lo=lo.min(projected);hi=hi.max(projected)
		cabin_regions[id]=_rect(Rect2(lo,hi-lo))
	# Patient reverses the verified straight door path first. Both rotate only
	# well outside the cabin; the nurse physically walks around the patient to
	# restore an outward-facing original-spacing ground convoy.
	_line(context,patient,Vector2(lane,outside+spacing))
	_turn(context,patient,facing+PI)
	_line(context,owner,Vector2(lane,nurse_y))
	_line(context,owner,Vector2(lane,outside))
	var bypass: float=lane+float(context.radii[owner])+float(context.radii[patient])+0.30
	_line(context,owner,Vector2(bypass,outside))
	_line(context,owner,Vector2(bypass,outside+2.0*spacing))
	_line(context,owner,Vector2(lane,outside+2.0*spacing))
	_turn(context,owner,facing+PI)
	if not str(context.error).is_empty(): return {"ok":false,"reason":context.error}
	var alighting: Array=context.frames
	var egress: Vector2=ConvoyTrail.point(context.poses[owner].cell)
	var final_points: Array=[_raw(egress+inward*spacing),_raw(egress)]
	var restored: Dictionary=convoy.duplicate(true);restored.points=final_points;restored.erase("portal")
	var expected: Dictionary=ConvoyTrail.positions(restored,members,facing+PI)
	for id: String in members:
		if ConvoyTrail.point(expected[id].cell).distance_to(ConvoyTrail.point(context.poses[id].cell))>0.00001: return {"ok":false,"reason":"离舱末帧不能恢复原队形"}
	return {"ok":true,"reason":"","mode":"articulated","version":VERSION,"entry":entry,"egress":_raw(egress),"inward":_raw(inward),"initial_poses":initial,"boarding":boarding,"alighting":alighting,"cabin_positions":cabin_positions,"cabin_regions":cabin_regions,"initial_ground_points":[_raw(ConvoyTrail.point(entry)-inward*spacing),entry.duplicate()],"body_dimensions":context.dimensions,"final_ground_points":final_points,"boarding_ticks":maxi(boarding.size(),HospitalTransit._boarding(definition)),"alighting_ticks":maxi(alighting.size(),HospitalTransit._alighting(definition)),"walk_distance":context.distance,"proof_scope":"Continuous member/cabin/door geometry; every external sweep still requires real landing clearance at runtime"}

static func _pose(context: Dictionary, id: String, local: Vector2, facing: float) -> Dictionary:
	var actor: Dictionary=context.world.facts.actors[id].duplicate(true)
	var size: float=context.space.clearance(actor)
	var center: Vector2=context.anchor+context.side*local.x+context.inward*(float(context.depth)-local.y)
	var cell: Vector2=center-Vector2.ONE*size*0.5
	actor.facing=wrapf(facing,-PI,PI)
	var region: Rect2=context.space._actor_rect(actor,cell)
	return {"cell":_raw(cell),"facing":actor.facing,"region":_rect(region)}

static func _region(pose: Dictionary) -> Rect2:
	var r: Array=pose.region;return Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3]))

static func _allowed(context: Dictionary, region: Rect2) -> bool:
	var lo: Vector2=Vector2(INF,INF);var hi: Vector2=Vector2(-INF,-INF)
	for point: Vector2 in [region.position,Vector2(region.end.x,region.position.y),region.end,Vector2(region.position.x,region.end.y)]:
		var relative: Vector2=point-context.anchor
		var p: Vector2=Vector2(relative.dot(context.side),float(context.depth)-relative.dot(context.inward))
		lo=lo.min(p);hi=hi.max(p)
	var eps: float=0.00001
	if lo.y>=float(context.depth)-eps: return true
	if lo.x>=-eps and hi.x<=float(context.width)+eps and lo.y>=-eps and hi.y<=float(context.depth)+eps: return true
	return lo.x>=-eps and hi.x<=float(context.doorway)+eps and lo.y>=-eps

static func _append(context: Dictionary, id: String, local: Vector2, facing: float) -> void:
	if not str(context.error).is_empty(): return
	if context.frames.size()>=LIMIT: context.error="独立门户预计算超过有限帧数";return
	var previous: Dictionary=context.poses[id]
	var next: Dictionary=_pose(context,id,local,facing)
	var angle: float=absf(angle_difference(float(previous.facing),float(next.facing)))
	# Endpoint AABBs plus rotational Lipschitz margin cover all intermediate
	# angles, not merely sampled endpoints. Translation is linear per frame.
	var sweep: Rect2=_region(previous).merge(_region(next)).grow(float(context.radii[id])*angle)
	if not _allowed(context,sweep): context.error="成员连续平移或转向扫掠越过门或舱边界";return
	for other: String in context.members:
		if other!=id and sweep.intersects(_region(context.poses[other]),false): context.error="成员连续扫掠与另一真实身体重叠";return
	var distance: float=context.local[id].distance_to(local)
	if distance+float(context.radii[id])*angle>float(context.speeds[id])+0.00001: context.error="成员帧移动或旋转边缘速度超过原速度";return
	context.distance+=distance
	context.local[id]=local;context.poses[id]=next
	var lo: Vector2=Vector2(INF,INF);var hi: Vector2=Vector2(-INF,-INF)
	for corner: Vector2 in [sweep.position,Vector2(sweep.end.x,sweep.position.y),sweep.end,Vector2(sweep.position.x,sweep.end.y)]:
		var delta: Vector2=corner-context.anchor
		var projected: Vector2=Vector2(delta.dot(context.side),delta.dot(context.inward))
		lo=lo.min(projected);hi=hi.max(projected)
	var cabin: Rect2=Rect2(lo,hi-lo).intersection(Rect2(0,0,float(context.width),float(context.depth)))
	var cabin_sweeps: Array=[]
	if cabin.has_area(): cabin_sweeps.append({"actor_id":id,"rect":_rect(cabin)})
	context.frames.append({"poses":context.poses.duplicate(true),"sweeps":[{"actor_id":id,"rect":_rect(sweep)}],"cabin_sweeps":cabin_sweeps,"moving_actor_id":id,"distance":distance})

static func _line(context: Dictionary, id: String, target: Vector2) -> void:
	while str(context.error).is_empty() and context.local[id].distance_to(target)>0.000001:
		var next: Vector2=context.local[id].move_toward(target,float(context.speeds[id]))
		_append(context,id,next,float(context.poses[id].facing))

static func _turn(context: Dictionary, id: String, target: float) -> void:
	while str(context.error).is_empty() and absf(angle_difference(float(context.poses[id].facing),target))>0.000001:
		var delta: float=angle_difference(float(context.poses[id].facing),target)
		var step: float=minf(absf(delta),float(context.speeds[id])/maxf(0.00001,float(context.radii[id])))
		_append(context,id,context.local[id],float(context.poses[id].facing)+signf(delta)*step)

# The nursing pair is already seated during both stages. Callers must alight
# this independent companion BEFORE beginning the nursing pair's alighting.
static func companion_plan(space: HospitalSpace, world: WorldState, c: Dictionary, nursing_plan: Dictionary, family_id: String, entry_cell: Array, cabin_position: Array, initial_facing: float=NAN) -> Dictionary:
	if not world.facts.actors.has(family_id): return {"ok":false,"reason":"家属不存在"}
	var actor: Dictionary=world.facts.actors[family_id]
	var key: String=JSON.stringify([VERSION,c.definition_id,c.anchor,c.get("rotation",0),space.content.definition("vertical_connectors",c.definition_id),nursing_plan.get("ok",false),nursing_plan.get("mode",""),nursing_plan.get("inward",[]),nursing_plan.get("boarding",[]).back().get("poses",{}) if not nursing_plan.get("boarding",[]).is_empty() else {},family_id,space.body(actor),space.clearance(actor),space.walking_speed(actor),actor.get("posture","standing"),entry_cell,cabin_position,"inward" if is_nan(initial_facing) else initial_facing],"",true,true)
	var cache: Dictionary=space.get_meta("articulated_companion_plan_cache",{})
	if cache.has(key): return cache[key].duplicate(true)
	var result: Dictionary=_build_companion(space,world,c,nursing_plan,family_id,entry_cell,cabin_position,initial_facing)
	if cache.size()>=128: cache.clear()
	cache[key]=result.duplicate(true);space.set_meta("articulated_companion_plan_cache",cache)
	return result

static func _build_companion(space: HospitalSpace, world: WorldState, c: Dictionary, nursing_plan: Dictionary, family_id: String, entry_cell: Array, cabin_position: Array, initial_facing: float) -> Dictionary:
	if not nursing_plan.get("ok",false) or nursing_plan.get("mode","")!="articulated" or not world.facts.actors.has(family_id): return {"ok":false,"reason":"家属门户缺少合法护理计划或成员"}
	var actor: Dictionary=world.facts.actors[family_id]
	if str(actor.get("posture","standing"))!="standing": return {"ok":false,"reason":"家属门户仅支持站立成员"}
	var definition: Dictionary=space.content.definition("vertical_connectors",c.definition_id)
	var width: float=float(definition.cabin_size[0]);var depth: float=float(definition.cabin_size[1])
	var doorway: float=minf(width,float(definition.clear_width_m)/HospitalSpace.CELL_METERS)
	var inward: Vector2=ConvoyTrail.point(nursing_plan.inward);var side:=Vector2(-inward.y,inward.x)
	var body: Dictionary=space.body(actor);var radius: float=Vector2(float(body.width_m),float(body.depth_m)).length()/HospitalSpace.CELL_METERS*0.5
	var half: float=maxf(float(body.width_m),float(body.depth_m))/HospitalSpace.CELL_METERS*0.5
	if half*2.0+0.1/HospitalSpace.CELL_METERS>doorway or float(body.height_m)+0.1>float(definition.clear_height_m): return {"ok":false,"reason":"家属真实身体超过门净宽或净高"}
	var speed: float=space.walking_speed(actor)*WorldState.TICK_SECONDS
	if speed<=0: return {"ok":false,"reason":"家属实际速度必须为正"}
	var anchor: Vector2=ConvoyTrail.point(c.anchor);var size: float=space.clearance(actor)
	var start_center: Vector2=ConvoyTrail.point(entry_cell)+Vector2.ONE*size*0.5-anchor
	var start:=Vector2(start_center.dot(side),depth-start_center.dot(inward))
	var cabin_cell: Vector2=anchor+side*float(cabin_position[0])+inward*float(cabin_position[1])
	var target_center: Vector2=cabin_cell+Vector2.ONE*size*0.5-anchor
	var target:=Vector2(target_center.dot(side),depth-target_center.dot(inward))
	if target.x-half<0 or target.x+half>width or target.y-half<0 or target.y+half>depth: return {"ok":false,"reason":"家属最终真实身体未完整处于轿厢"}
	if start.y-radius<depth: return {"ok":false,"reason":"家属待入点必须完整在门外"}
	var nursing_final: Dictionary=nursing_plan.boarding[-1].poses
	var members: Array=nursing_final.keys();members.append(family_id)
	var context: Dictionary={"space":space,"world":world,"members":members,"anchor":anchor,"inward":inward,"side":side,"depth":depth,"width":width,"doorway":doorway,"poses":nursing_final.duplicate(true),"local":{family_id:start},"frames":[],"distance":0.0,"radii":{family_id:radius},"speeds":{family_id:speed},"error":""}
	var facing: float=atan2(inward.x,inward.y)
	context.poses[family_id]=_pose(context,family_id,start,facing if is_nan(initial_facing) else initial_facing)
	var initial: Dictionary=context.poses[family_id].duplicate(true)
	var lane: float=doorway*0.5
	_turn(context,family_id,facing)
	_line(context,family_id,Vector2(lane,start.y))
	_line(context,family_id,Vector2(lane,target.y))
	_line(context,family_id,target)
	if not str(context.error).is_empty(): return {"ok":false,"reason":context.error}
	var boarding: Array=context.frames;context.frames=[]
	var seated: Dictionary=context.poses[family_id].duplicate(true)
	_line(context,family_id,Vector2(lane,target.y))
	_line(context,family_id,Vector2(lane,start.y))
	_line(context,family_id,start)
	if not str(context.error).is_empty(): return {"ok":false,"reason":context.error}
	var alighting: Array=context.frames
	for frames: Array in [boarding,alighting]:
		for frame: Dictionary in frames: frame.poses={family_id:frame.poses[family_id]}
	return {"ok":true,"reason":"","mode":"articulated_companion","version":VERSION,"actor_id":family_id,"entry_cell":entry_cell.duplicate(),"initial_pose":initial,"boarding":boarding,"alighting":alighting,"seated_pose":seated,"final_pose":context.poses[family_id].duplicate(true),"cabin_position":cabin_position.duplicate(),"requires_nursing_seated":true,"alight_before_nursing":true,"walk_distance":context.distance}
