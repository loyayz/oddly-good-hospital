extends RefCounted
const Flow=preload("res://game/operations/guidance_queue_flow.gd")

# Optional static circulation only. No ticket, reservation, actor or route owner
# is changed here; normal real-step collision checks remain authoritative.
static func quote(space: HospitalSpace, world: WorldState, movement: Dictionary, floor_id: int, goal: Array) -> Dictionary:
 if space.guidance_queue_provider==null or movement.has("convoy") or movement.get("members",[]).size()>1:return {}
 var provider: RefCounted=space.guidance_queue_provider.get_ref()
 if provider==null:return {}
 var actor: Dictionary=world.facts.actors[movement.actor_id]
 if actor.location.kind!="floor":return {}
 if int(actor.location.floor_id)!=floor_id:return _cross_floor_exit(space,world,provider,actor,floor_id,goal)
 var start:=Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
 var target:=Vector2(float(goal[0]),float(goal[1]))
 # An exterior guidance wait must not be routed back through the queue's
 # entry boundary. The same real-body region used by block_entry applies.
 var entry: Dictionary=exterior_context(space,world,movement)
 if not entry.is_empty():return _exterior_wait(space,world,actor,floor_id,start,target,entry)
 for desk_id: String in world.facility_ids("SE01"):
  var desk: Dictionary=world.facts.facilities[desk_id]
  if int(desk.floor_id)!=floor_id:continue
  var span: int=space.clearance(actor)
  var uniform: bool=true
  for row: Dictionary in provider._queue_members(world,desk_id):
   var visit: Dictionary=world.facts.visits.get(str(row.visit_id),{})
   if not visit.is_empty() and space.clearance(world.facts.actors[visit.actor_id])!=span:uniform=false;break
  if not uniform:continue
  var slots: Array=provider._queue_slots(world,desk_id,span)
  if slots.is_empty():continue
  var entering: bool=false
  for slot: Array in slots:
   if target.distance_to(Vector2(slot[0],slot[1]))<0.001:entering=true;break
  var already_in_column: bool=false
  for slot: Array in slots:
   if start.distance_to(Vector2(slot[0],slot[1]))<0.001:already_in_column=true;break
  if entering and already_in_column:continue
  var service: Array=space.facility_layout(world,desk_id).patient_cell
  var fixed: RouteClearance=space.navigation.structural_clearance(world,actor,floor_id)
  var service_goal: bool=target.distance_to(Vector2(service[0],service[1]))<0.001
  var hints: Array=[]
  var remote_first: bool=entering
  if service_goal:
   var approach: Dictionary=Flow.service_approach(slots,span,int(desk.rotation),start,target,fixed)
   if approach.get("mode","none") in ["none","direct"]:continue
   remote_first=approach.mode=="remote"
   hints=approach.points
  else:
   hints=Flow.hints(slots,span,int(desk.rotation),start,target,Vector2(service[0],service[1]),entering,fixed)
  if hints.is_empty():continue
  var mask:=Rect2(Vector2(slots[0][0],slots[0][1]),Vector2.ONE*span)
  for slot: Array in slots:mask=mask.merge(Rect2(Vector2(slot[0],slot[1]),Vector2.ONE*span))
  var path: Array=[]
  var first: Vector2=hints[0]
  if remote_first:
   var lead: Dictionary=_outside(space,world,actor,floor_id,start,first,mask)
   if not lead.get("ok",false):continue
   path.append_array(lead.path)
  elif start.distance_to(first)>0.001:path.append(_point(floor_id,first))
  for index: int in range(1,hints.size()):path.append(_point(floor_id,hints[index]))
  var last: Vector2=hints.back()
  if entering or service_goal:
   if last.distance_to(target)>0.001:path.append(_point(floor_id,target))
  else:
   var tail: Dictionary=_outside(space,world,actor,floor_id,last,target,mask)
   if not tail.get("ok",false):continue
   path.append_array(tail.path)
  space.query_counts["guidance_flow_routes"]=int(space.query_counts.get("guidance_flow_routes",0))+1
  return {"ok":true,"path":path}
 return {}

static func exterior_context(space: HospitalSpace, world: WorldState, movement: Dictionary) -> Dictionary:
 if space.guidance_queue_provider==null or movement.has("convoy") or movement.get("members",[]).size()>1:return {}
 var provider: RefCounted=space.guidance_queue_provider.get_ref()
 var visit_id: String=str(movement.get("floor_guidance_visit_id",""))
 if provider==null or visit_id.is_empty():return {}
 var actor: Dictionary=world.facts.actors.get(str(movement.actor_id),{})
 var visit: Dictionary=world.facts.visits.get(visit_id,{})
 var row: Dictionary=provider.state(world,visit_id)
 if actor.get("location",{}).get("kind","")!="floor" or visit.get("actor_id","")!=actor.id or row.get("phase","")!="seek" or row.get("request_key","")!=movement.get("floor_guidance_key",""):return {}
 var entry: Dictionary=preload("res://game/operations/guidance_queue_entry.gd").context(space,world,str(row.get("desk_id","")))
 if entry.is_empty() or int(entry.floor_id)!=int(actor.location.floor_id) or int(movement.target_floor)!=int(entry.floor_id):return {}
 var start: Vector2=ConvoyTrail.point(actor.location.cell)
 var target: Vector2=ConvoyTrail.point(movement.target_cell)
 if preload("res://game/operations/guidance_queue_entry.gd").is_inside(entry,space,actor,start) or preload("res://game/operations/guidance_queue_entry.gd").is_inside(entry,space,actor,target):return {}
 return entry

static func exterior_guard(space: HospitalSpace, world: WorldState, movement: Dictionary) -> Callable:
 var entry: Dictionary=exterior_context(space,world,movement)
 if entry.is_empty():return Callable()
 return _exterior_region_guard(space,world.facts.actors[movement.actor_id],entry)

static func _exterior_region_guard(space: HospitalSpace, actor: Dictionary, entry: Dictionary) -> Callable:
 var regions: Array=[entry.room_bounds]
 regions.append_array(entry.door_bounds)
 # A route can turn. Use the current and all axis-facing body extents,
 # computed once, rather than incorrectly freezing its current narrow side.
 var envelope: Rect2=space._actor_rect(actor,Vector2.ZERO)
 var sample: Dictionary=actor.duplicate()
 for facing: float in [0.0,PI*0.5,PI,PI*1.5]:
  sample.facing=facing
  envelope=envelope.merge(space._actor_rect(sample,Vector2.ZERO))
 return func(a: Vector2,b: Vector2)->bool:
  var swept: Rect2=Rect2(a+envelope.position,envelope.size).merge(Rect2(b+envelope.position,envelope.size))
  for region: Rect2 in regions:
   if swept.intersects(region,false):return false
  return true

static func _exterior_wait(space: HospitalSpace, world: WorldState, actor: Dictionary, floor_id: int, origin: Vector2, goal: Vector2, entry: Dictionary) -> Dictionary:
 var graph: FloorNavigation=space._navigation.graph(space,world,floor_id,actor,[],{})
 var fixed: RouteClearance=graph.geometry
 var clear: Callable=_exterior_region_guard(space,actor,entry)
 var a:=Vector2i(origin.round());var b:=Vector2i(goal.round())
 var failed: Dictionary={"ok":false,"status":"unreachable","reason":"导诊区域外候位没有可用的区域外路线"}
 if not clear.call(origin,Vector2(a)) or not clear.call(Vector2(b),goal):return failed
 if not fixed.sweep_reason(origin,Vector2(a)).is_empty() or not fixed.sweep_reason(Vector2(b),goal).is_empty():return failed
 var allowed: Callable=func(from:Vector2i,to:Vector2i)->bool:return clear.call(Vector2(from),Vector2(to))
 var result: Dictionary=graph.find_path(a,b,fixed,allowed)
 if not result.get("ok",false):return failed
 var path: Array=[]
 if origin!=Vector2(a):path.append(_point(floor_id,Vector2(a)))
 for cell:Array in result.cells:path.append(_point(floor_id,Vector2(cell[0],cell[1])))
 if goal!=Vector2(b):path.append(_point(floor_id,goal))
 return {"ok":true,"path":path}

static func _point(floor_id: int, point: Vector2) -> Dictionary:
 return {"kind":"floor","floor_id":floor_id,"cell":[point.x,point.y]}

static func _outside(space: HospitalSpace, world: WorldState, actor: Dictionary, floor_id: int, origin: Vector2, goal: Vector2, mask: Rect2) -> Dictionary:
 var graph: FloorNavigation=space._navigation.graph(space,world,floor_id,actor,[],{})
 var fixed: RouteClearance=graph.geometry
 var a:=Vector2i(origin.round());var b:=Vector2i(goal.round())
 if not fixed.sweep_reason(origin,Vector2(a)).is_empty() or not fixed.sweep_reason(Vector2(b),goal).is_empty():return {}
 var size: int=space.clearance(actor)
 if Rect2(origin,Vector2.ONE*size).merge(Rect2(Vector2(a),Vector2.ONE*size)).intersects(mask,false) or Rect2(Vector2(b),Vector2.ONE*size).merge(Rect2(goal,Vector2.ONE*size)).intersects(mask,false):return {}
 var outside: Callable=func(from: Vector2i,to: Vector2i)->bool:
  return not Rect2(Vector2(from),Vector2.ONE*size).merge(Rect2(Vector2(to),Vector2.ONE*size)).intersects(mask,false)
 if not outside.call(a,a) or not outside.call(b,b):return {}
 var result: Dictionary=graph.find_path(a,b,fixed,outside)
 if not result.get("ok",false):return {}
 var path: Array=[]
 if origin.distance_to(Vector2(a))>0.001:path.append(_point(floor_id,Vector2(a)))
 for cell: Array in result.cells:path.append(_point(floor_id,Vector2(cell[0],cell[1])))
 if goal.distance_to(Vector2(b))>0.001:path.append(_point(floor_id,goal))
 return {"ok":true,"path":path}

# A cross-floor journey keeps the existing transit solver and connector chunks.
# Only its departure from a supported queue receives the same local exit leg.
static func _cross_floor_exit(space: HospitalSpace, world: WorldState, provider: RefCounted, actor: Dictionary, target_floor: int, goal: Array) -> Dictionary:
 var source_floor: int=int(actor.location.floor_id)
 var start:=Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
 var target:=Vector2(float(goal[0]),float(goal[1]))
 var span: int=space.clearance(actor)
 var fixed: RouteClearance=space.navigation.structural_clearance(world,actor,source_floor)
 for desk_id: String in world.facility_ids("SE01"):
  var desk: Dictionary=world.facts.facilities[desk_id]
  if int(desk.floor_id)!=source_floor:continue
  var uniform: bool=true
  for row: Dictionary in provider._queue_members(world,desk_id):
   var visit: Dictionary=world.facts.visits.get(str(row.visit_id),{})
   if not visit.is_empty() and space.clearance(world.facts.actors[visit.actor_id])!=span:uniform=false;break
  if not uniform:continue
  var slots: Array=provider._queue_slots(world,desk_id,span)
  var service: Array=space.facility_layout(world,desk_id).patient_cell
  var hints: Array=Flow.hints(slots,span,int(desk.rotation),start,target,Vector2(service[0],service[1]),false,fixed)
  if hints.is_empty():continue
  var prefix: Array=[]
  var distance: float=0.0
  var ticks: int=0
  var previous: Vector2=start
  for hint: Vector2 in hints:
   var length: float=previous.distance_to(hint)
   ticks=HospitalTransit._add(ticks,HospitalTransit.walking_ticks(space,actor,[],length))
   distance+=length;prefix.append(_point(source_floor,hint));previous=hint
  var tail:=Vector2i(previous.round())
  if Vector2(tail)!=previous or ticks<0:continue
  var destination:=Vector2i(int(goal[0]),int(goal[1]))
  var final_leg: Dictionary={"points":[],"distance":0.0,"ticks":0}
  if Vector2(destination)!=target:
   final_leg=space.navigation._grid_stub(world,actor,target_floor,Vector2(destination),target)
   if not final_leg.get("ok",false):continue
  var result: Dictionary=space.navigation._point_route(world,actor,source_floor,tail,target_floor,destination,[],{},ticks,false)
  if not result.get("ok",false):continue
  var mask: Rect2=Flow.bounds(slots,span)
  if not _source_suffix_outside(world,result.path,source_floor,Vector2(tail),span,mask):continue
  var total: int=HospitalTransit._add(int(result.travel_ticks),int(final_leg.ticks))
  if total<0:continue
  prefix.append_array(result.path)
  for point: Array in final_leg.points:prefix.append({"kind":"floor","floor_id":target_floor,"cell":point.duplicate()})
  result.path=prefix;result.travel_ticks=total
  result.walking_distance=float(result.walking_distance)+distance+float(final_leg.distance)
  space.query_counts["guidance_cross_floor_exits"]=int(space.query_counts.get("guidance_cross_floor_exits",0))+1
  return result
 return {}

static func _source_suffix_outside(world: WorldState, path: Array, source_floor: int, start: Vector2, span: int, mask: Rect2) -> bool:
 var floor_id: int=source_floor
 var previous: Vector2=start
 for segment: Dictionary in path:
  if segment.kind=="connector":
   if int(segment.from)!=floor_id:return false
   var connector: Dictionary=world.facts.connectors.get(str(segment.connector_id),{})
   if connector.is_empty():return false
   floor_id=int(segment.to)
   previous=Vector2(connector.anchor[0],connector.anchor[1])
   if floor_id==source_floor and Rect2(previous,Vector2.ONE*span).intersects(mask,false):return false
  elif segment.kind=="floor":
   var next:=Vector2(float(segment.cell[0]),float(segment.cell[1]))
   if int(segment.floor_id)!=floor_id:return false
   if floor_id==source_floor and Rect2(previous,Vector2.ONE*span).merge(Rect2(next,Vector2.ONE*span)).intersects(mask,false):return false
   previous=next
  else:return false
 return true
