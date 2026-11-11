class_name ConvoyTrail
extends RefCounted

# Points are leader-cell coordinates, oldest (tail) first. Members only publish
# positions along this path. Permission never inspects follower collisions.
static func formation(space: HospitalSpace, world: WorldState, primary: String, members: Array, direction: Vector2 = Vector2.RIGHT) -> Dictionary:
 var leader: Dictionary = world.facts.actors[primary]
 var size: int = 1
 var height: float = 0.0
 for id: String in members:
  var body: Dictionary = space.body(world.facts.actors[id])
  size = maxi(size,ceili(Vector2(float(body.width_m),float(body.depth_m)).length()/HospitalSpace.CELL_METERS))
  height = maxf(height,float(body.height_m))
 var leader_size: int = space.clearance(leader)
 if (size-leader_size)%2!=0: size+=1
 var spacing: float = 2.0*size
 var centers: Dictionary = {};var targets: Dictionary = {}
 var head: Vector2 = Vector2(leader.location.cell[0],leader.location.cell[1])
 for i: int in members.size():
  var id: String = members[i]
  var offset: Vector2 = Vector2.ONE*(leader_size-space.clearance(world.facts.actors[id]))*0.5
  centers[id] = [offset.x,offset.y]
  var point: Vector2 = head-direction*spacing*i+offset
  targets[id] = [point.x,point.y]
 return {"size":size,"spacing":spacing,"centers":centers,"targets":targets,"shift":(leader_size-size)*0.5,"height":height}

static func create(space: HospitalSpace, world: WorldState, primary: String, members: Array) -> Dictionary:
 if members.is_empty() or members[0]!=primary: return {"ok":false,"reason":"队列首位必须为队长"}
 var head: Vector2 = Vector2(world.facts.actors[primary].location.cell[0],world.facts.actors[primary].location.cell[1])
 var dir: Vector2 = Vector2.RIGHT
 var actual_spacing: float=0.0
 if members.size()>1:
  var follower: Dictionary = world.facts.actors[members[1]]
  if follower.location.kind!="floor": return {"ok":false,"reason":"等待队列全员真实到场"}
  var delta: Vector2 = head-Vector2(follower.location.cell[0],follower.location.cell[1])+Vector2.ONE*(space.clearance(world.facts.actors[primary])-space.clearance(follower))*0.5
  actual_spacing=delta.length()
  if actual_spacing<0.000001: return {"ok":false,"reason":"队列成员不能重叠成队"}
  dir = Vector2(signf(delta.x),0) if absf(delta.x)>absf(delta.y) else Vector2(0,signf(delta.y))
 var form: Dictionary = formation(space,world,primary,members,dir)
 if members.size()>1 and actual_spacing>float(form.spacing):
  form.spacing=actual_spacing
  for i: int in members.size():
   var offset: Vector2=point(form.centers[members[i]])
   var at: Vector2=head-dir*actual_spacing*i+offset
   form.targets[members[i]]=[at.x,at.y]
 var floor_id: int = int(world.facts.actors[primary].location.floor_id)
 for id: String in members:
  if world.facts.actors[id].get("posture","standing")!="standing" or not space.at(world,id,floor_id,form.targets[id]): return {"ok":false,"reason":"等待前后队列真实成队（间距 %s 格）"%form.spacing}
 var tail: Vector2 = head-dir*form.spacing*(members.size()-1)
 var points: Array = [[tail.x,tail.y],[head.x,head.y]] if members.size()>1 else [[head.x,head.y]]
 var convoy: Dictionary={"version":1,"points":points,"spacing":form.spacing,"size":form.size,"centers":form.centers,"floor_id":floor_id,"shift":form.shift,"height":form.height}
 var separation_error: String=_trail_separation_error(convoy)
 if not separation_error.is_empty(): return {"ok":false,"reason":separation_error}
 return {"ok":true,"convoy":convoy}

static func point(raw: Array) -> Vector2: return Vector2(float(raw[0]),float(raw[1]))
static func length(points: Array) -> float:
 var total: float = 0.0
 for i: int in range(1,points.size()): total+=point(points[i]).distance_to(point(points[i-1]))
 return total
# A singleton has no historical segment. Its publisher supplies the accepted
# motion tangent, or the actor's existing heading when no motion was accepted.
static func positions(convoy: Dictionary, members: Array, leader_facing: float = PI*0.5) -> Dictionary:
 var result: Dictionary={}
 for index: int in members.size():
  var distance: float=index*float(convoy.spacing)
  var pose: Dictionary={"cell":convoy.points[-1].duplicate(),"facing":leader_facing}
  for i: int in range(convoy.points.size()-1,0,-1):
   var a: Vector2=point(convoy.points[i-1]);var b: Vector2=point(convoy.points[i]);var span: float=a.distance_to(b)
   if span<0.000001: continue
   if distance<=span+0.00001 or i==1:
    var direction: Vector2=(b-a).normalized()
    var at: Vector2=b-direction*minf(distance,span)
    pose={"cell":[at.x,at.y],"facing":atan2(direction.x,direction.y)}
    break
   distance-=span
  var offset: Array=convoy.centers[members[index]]
  pose.cell=[float(pose.cell[0])+float(offset[0]),float(pose.cell[1])+float(offset[1])]
  result[members[index]]=pose
 return result
static func regions(convoy: Dictionary, points: Array = []) -> Array[Rect2]:
 if points.is_empty(): points=convoy.points
 var result: Array[Rect2]=[];var shift: Vector2 = Vector2.ONE*float(convoy.shift);var size: Vector2=Vector2.ONE*float(convoy.size)
 if points.size()==1: result.append(Rect2(point(points[0])+shift,size))
 for i: int in range(1,points.size()):
  result.append(Rect2(point(points[i-1])+shift,size).merge(Rect2(point(points[i])+shift,size)))
 return result
static func drop(points: Array, distance: float) -> Array:
 for i: int in range(1,points.size()):
  var a: Vector2=point(points[i-1]);var b: Vector2=point(points[i]);var span: float=a.distance_to(b)
  if span<0.000001: continue
  if distance<span-0.000001:
   var at: Vector2=a.lerp(b,distance/span)
   # Vector2 interpolation can round an interior scalar fraction to the
   # exact float32 endpoint. Retain that endpoint once, never a zero segment.
   if at==b: return points.slice(i)
   var result: Array=[[at.x,at.y]]
   result.append_array(points.slice(i));return result
  distance-=span
 return [points[-1].duplicate()]
static func extended(points: Array, end: Vector2) -> Array:
 var result: Array=points.duplicate(true)
 if end.distance_to(point(result[-1]))<0.000001: return result
 result.append([end.x,end.y])
 if result.size()>=3:
  var a: Vector2=point(result[-3]);var b: Vector2=point(result[-2]);var c: Vector2=point(result[-1])
  # Approximate tangents can accumulate transverse drift. Keep the real
  # vertex unless the compressed segment still obeys the axial contract.
  var combined: Vector2=c-a
  if (absf(combined.x)<=0.00001 or absf(combined.y)<=0.00001) and (b-a).normalized().is_equal_approx((c-b).normalized()): result.remove_at(result.size()-2)
 return result
static func propose(convoy: Dictionary, end: Vector2) -> Dictionary:
 var start: Vector2=point(convoy.points[-1]);var delta: Vector2=end-start;var advance: float=delta.length()
 if absf(delta.x)>0.00001 and absf(delta.y)>0.00001: return {"ok":false,"reason":"队列原型只支持正交逐段移动"}
 if advance>float(convoy.size)*0.5+0.00001: return {"ok":false,"reason":"队列步长超过已验证前端上限"}
 var front: Rect2=regions(convoy,[[start.x,start.y],[end.x,end.y]])[0]
 # Check only the new leader segment against its own older trail. Pair
 # positions by arc separation: an old head and a future tail are not a
 # simultaneous collision. Reuse the boundary proof's exact overlap bands.
 var arc: float=length(convoy.points)
 if advance>0.000001:
  for i: int in range(1,convoy.points.size()):
   var a: Vector2=point(convoy.points[i-1]);var b: Vector2=point(convoy.points[i])
   if arc+advance>=float(convoy.spacing) and _separated_segments_overlap(a,b,start,end,arc,float(convoy.spacing),float(convoy.size)): return {"ok":false,"reason":"队长不能折回当前队尾"}
   arc-=a.distance_to(b)
 var path: Array=extended(convoy.points,end)
 return {"ok":true,"front":front,"points":drop(path,maxf(0,length(path)-float(convoy.spacing)*(convoy.centers.size()-1))) if convoy.centers.size()>1 else [[end.x,end.y]],"history":regions(convoy,path)}
static func proxy(world: WorldState, movement: Dictionary) -> Dictionary:
 var actor: Dictionary=world.facts.actors[movement.actor_id].duplicate(true);var convoy: Dictionary=movement.convoy
 actor._convoy_size=int(convoy.size)
 actor._convoy_body={"width_m":float(convoy.size)*HospitalSpace.CELL_METERS,"depth_m":float(convoy.size)*HospitalSpace.CELL_METERS,"height_m":float(convoy.height)}
 if actor.location.kind=="floor": actor.location.cell=[float(actor.location.cell[0])+float(convoy.shift),float(actor.location.cell[1])+float(convoy.shift)]
 return actor
static func validate(space: HospitalSpace, world: WorldState, movement: Dictionary) -> String:
 var convoy: Variant=movement.get("convoy")
 if not convoy is Dictionary: return "队列结构无效"
 for key: String in ["version","spacing","size","floor_id","shift","height"]:
  if not convoy.has(key) or not (convoy[key] is int or convoy[key] is float) or not is_finite(float(convoy[key])): return "队列数值字段缺失或非有限："+key
 if int(convoy.version)!=1 or float(convoy.version)!=1.0 or float(convoy.size)!=floorf(float(convoy.size)) or float(convoy.size)<1.0 or float(convoy.floor_id)!=floorf(float(convoy.floor_id)) or float(convoy.floor_id)<1.0 or float(convoy.height)<=0.0 or float(convoy.spacing)<2.0*float(convoy.size): return "无效或不支持的队列版本/间距"
 if not convoy.get("points") is Array or convoy.points.is_empty() or not convoy.get("centers") is Dictionary or not movement.get("members") is Array or movement.members.is_empty() or movement.members[0]!=movement.actor_id: return "队列必须有尾迹、成员及队长"
 var seen: Dictionary={}
 for id: Variant in movement.members:
  if not id is String or not world.facts.actors.has(id) or seen.has(id): return "队列成员不存在或重复"
  seen[id]=true
 if convoy.centers.size()!=seen.size(): return "队列中心与成员集合不一致"
 var leader: Dictionary=world.facts.actors[movement.actor_id]
 if absf(float(convoy.shift)-(space.clearance(leader)-float(convoy.size))*0.5)>0.00001: return "队列代理中心偏移无效"
 for raw: Variant in convoy.points:
  if not _finite_point(raw): return "队列尾迹坐标无效"
 for i: int in range(1,convoy.points.size()):
  var d: Vector2=point(convoy.points[i])-point(convoy.points[i-1])
  if d.length()<0.000001 or absf(d.x)>0.00001 and absf(d.y)>0.00001: return "队列尾迹不是非零正交路径"
 if absf(length(convoy.points)-float(convoy.spacing)*(movement.members.size()-1))>0.001: return "队列尾迹长度不一致"
 var separation_error: String=_trail_separation_error(convoy)
 if not separation_error.is_empty(): return separation_error
 for id: String in movement.members:
  if not convoy.centers.has(id) or not _finite_point(convoy.centers[id]): return "队列成员中心缺失"
  var body: Dictionary=space.body(world.facts.actors[id])
  if Vector2(float(body.width_m),float(body.depth_m)).length()/HospitalSpace.CELL_METERS>float(convoy.size)+0.00001 or float(body.height_m)>float(convoy.height)+0.00001: return "队列身体变化超出原代理包络"
  var center: float=(space.clearance(leader)-space.clearance(world.facts.actors[id]))*0.5
  if point(convoy.centers[id]).distance_to(Vector2.ONE*center)>0.00001: return "队列成员身体中心变化需要重新成队"
 var expected: Dictionary=positions(convoy,movement.members)
 if leader.location.kind=="transit":
  var connection: Dictionary=world.facts.connectors.get(leader.location.connector_id,{})
  if connection.is_empty() or connection.get("primary_actor_id","")!=movement.actor_id or connection.riders!=movement.members: return "队列连接拥有者不一致"
  if not convoy.has("portal"):
   if movement.members.size()!=1 or space.content.definition("vertical_connectors",connection.definition_id).kind!="stairs": return "队列登离舱路径缺失"
   return ""
  var portal: Variant=convoy.portal
  if not portal is Dictionary or portal.size()!=2 or not portal.get("plan") is Dictionary or not portal.get("cursor") is int: return "队列登离舱状态无效"
  var plan: Dictionary=portal.plan
  for field: String in ["entry","egress","inward"]:
   if not _finite_point(plan.get(field)): return "队列登离舱派生坐标缺失"
  for field: String in ["boarding_ticks","alighting_ticks","walk_distance"]:
   if not (plan.get(field) is int or plan.get(field) is float) or not is_finite(float(plan[field])) or float(plan[field])<0: return "队列登离舱计量无效"
  if not point(plan.inward) in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]: return "队列登离舱包络无效"
  for field: String in ["boarding","alighting"]:
   if not plan.get(field) is Array or plan[field].is_empty(): return "队列登离舱路径为空"
   for raw: Variant in plan[field]:
    if not _finite_point(raw): return "队列登离舱路径坐标无效"
  if not connection.phase in ["boarding","riding","alighting"]: return "队列登离舱阶段无效"
  var canonical: Dictionary=ConvoyPortal.plan(space,world,connection,movement.actor_id,movement.members,convoy)
  if not canonical.get("ok",false) or plan!=canonical: return "队列登离舱保存路径与当前连接不一致"
  var targets: Array=plan.boarding if connection.phase in ["boarding","riding"] else plan.alighting
  if int(portal.cursor)<0 or int(portal.cursor)>targets.size(): return "队列登离舱游标无效"
  var progress_error: String=_portal_progress_error(convoy,movement.members,connection,portal)
  if not progress_error.is_empty(): return progress_error
  if int(convoy.floor_id)!=(int(connection.to) if connection.phase=="alighting" else int(connection.from)): return "队列登离舱所在层不一致"
  for id: String in movement.members:
   if not _finite_point(world.facts.actors[id].location.get("queue_cell")) or point(world.facts.actors[id].location.queue_cell).distance_to(point(expected[id].cell))>0.001: return "队列乘员没有沿真实尾迹移动"
  return ""
 if convoy.has("portal"): return "地面队列不能保留登离舱状态"
 for id: String in movement.members:
  if not space.at(world,id,int(convoy.floor_id),expected[id].cell): return "队列成员未处于真实尾迹位置"
 return ""

# Creation/restore only. Establish the geometric invariant that movement's
# single front sweep preserves; never run a follower permission loop per step.
# Every two points at least one spacing apart along the trail must have disjoint
# square envelopes, including positions between the current member samples.
static func _trail_separation_error(convoy: Dictionary) -> String:
 var points: Array=convoy.points
 var starts: Array[float]=[0.0]
 for i: int in range(1,points.size()):
  starts.append(starts[-1]+point(points[i-1]).distance_to(point(points[i])))
 for a: int in range(points.size()-1):
  var a0: Vector2=point(points[a]);var a1: Vector2=point(points[a+1])
  for b: int in range(a+1,points.size()-1):
   var b0: Vector2=point(points[b]);var b1: Vector2=point(points[b+1])
   if starts[b+1]-starts[a]<float(convoy.spacing)-0.00001: continue
   if _separated_segments_overlap(a0,a1,b0,b1,starts[b]-starts[a],float(convoy.spacing),float(convoy.size)): return "队列尾迹不能使成员包络重叠"
 return ""

# Parameters u/v are distances along segments a/b. Clip their rectangle by
# arc separation and the two strict square-overlap bands. A surviving point
# witnesses an overlap, even if it is only a corner/endpoint in parameter space.
static func _separated_segments_overlap(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2, arc: float, spacing: float, size: float) -> bool:
 var a: Vector2=a1-a0;var b: Vector2=b1-b0
 var polygon: Array[Vector2]=[Vector2.ZERO,Vector2(a.length(),0),Vector2(a.length(),b.length()),Vector2(0,b.length())]
 polygon=_clip_parameters(polygon,Vector2(1,-1),arc-spacing)
 var da: Vector2=a.normalized();var db: Vector2=b.normalized();var delta: Vector2=b0-a0
 # Boundary contact is legal. Match the coordinate tolerance used by restore.
 var limit: float=size-0.00001
 for axis: int in 2:
  var normal: Vector2=Vector2(-da[axis],db[axis])
  polygon=_clip_parameters(polygon,normal,limit-delta[axis])
  polygon=_clip_parameters(polygon,-normal,limit+delta[axis])
 return not polygon.is_empty()

static func _clip_parameters(polygon: Array[Vector2], normal: Vector2, bound: float) -> Array[Vector2]:
 var result: Array[Vector2]=[]
 if polygon.is_empty(): return result
 var previous: Vector2=polygon[-1];var previous_value: float=normal.dot(previous)-bound
 for current: Vector2 in polygon:
  var current_value: float=normal.dot(current)-bound
  if (previous_value<=0.0)!=(current_value<=0.0): result.append(previous.lerp(current,previous_value/(previous_value-current_value)))
  if current_value<=0.0: result.append(current)
  previous=current;previous_value=current_value
 return result

static func _finite_point(raw: Variant) -> bool:
 if not raw is Array or raw.size()!=2: return false
 for value: Variant in raw:
  if not (value is int or value is float) or not is_finite(float(value)): return false
 return true

# Restore validates the authoritative trail against the canonical portal path.
# Never trust a saved cursor as proof of completed boarding. This is lifecycle
# validation, not an extra follower collision loop in movement permission.
static func _portal_progress_error(convoy: Dictionary, members: Array, connection: Dictionary, portal: Dictionary) -> String:
 var plan: Dictionary=portal.plan
 var entry: Vector2=point(plan.entry)
 var tail: Vector2=entry-point(plan.inward)*float(convoy.spacing)*(members.size()-1)
 var path: Array=[[tail.x,tail.y],[entry.x,entry.y]] if members.size()>1 else [[entry.x,entry.y]]
 var targets: Array=[]
 if connection.phase in ["riding","alighting"]: targets.append_array(plan.boarding)
 if connection.phase=="riding":
  if int(portal.cursor)!=plan.boarding.size(): return "队尾未完整入舱，不能进入乘梯阶段"
 elif connection.phase=="boarding": targets.append_array(plan.boarding.slice(0,int(portal.cursor)))
 else: targets.append_array(plan.alighting.slice(0,int(portal.cursor)))
 for raw: Array in targets:
  path=extended(path,point(raw))
 var head: Vector2=point(convoy.points[-1])
 var start: Vector2=point(path[-1])
 var current: Array=plan.boarding if connection.phase=="boarding" else plan.alighting
 if connection.phase=="riding" or int(portal.cursor)==current.size():
  if head.distance_to(start)>0.001: return "队列登离舱游标跳过实际移动"
 else:
  var target: Vector2=point(current[int(portal.cursor)])
  var delta: Vector2=target-start
  var progress: Vector2=head-start
  var extent: float=delta.length()
  if extent<0.000001 or absf(delta.cross(progress))>0.001 or progress.dot(delta)<-0.00001 or progress.dot(delta)>delta.length_squared()+0.00001: return "队列登离舱实际位置不在当前路段"
  path=extended(path,head)
 # Reconstruct geometry once, not a second movement cadence. A compound
 # frame may finish just beyond a corner; relative Vector2 equality would
 # discard that real segment and falsely reject its saved trail. The full
 # saved trail separation invariant has already been checked above.
 var expected: Array=drop(path,maxf(0.0,length(path)-float(convoy.spacing)*(members.size()-1))) if members.size()>1 else [[head.x,head.y]]
 # Array order and corners matter, not just the head and tail endpoints.
 if expected.size()!=convoy.points.size(): return "队列登离舱尾迹与实际进度不一致"
 for index: int in expected.size():
  if point(expected[index]).distance_to(point(convoy.points[index]))>0.001: return "队列登离舱尾迹与实际进度不一致"
 return ""
