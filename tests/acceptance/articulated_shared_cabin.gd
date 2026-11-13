extends SceneTree
# Actual independent floor-to-floor journeys; no transit/arrival fabrication.
# The separate corrupted-cabin negative is explicitly a fault injection only.
const Cases=preload("res://tests/acceptance/space.gd")
var suite=Cases.new()
var lift_cell:Array=[36,32]
var wide_input:bool=true
func _initialize()->void:call_deferred("run")
func prepare(species:String="S63", nurse_destination:int=2)->Dictionary:
 suite.content=HospitalContent.new()
 var s:HospitalSimulation=suite._fixture()
 # Explicit independent historical wide/high landing. No in-flight person,
 # previous clinical obligation, species or movement is rewritten.
 s.world.facts.floors.overrides["1"].plots.append([1,1])
 s.world.facts.floors.completed_top_floor["1:1"]=3
 s.world.facts.floors.completed_top_floor["1:2"]=3
 s.world.facts.floors.height_intervals=[{"first":1,"last":3,"height_m":8.0}]
 if wide_input:
  for x:int in range(3):
   for y:int in range(3):
    if not [x,y] in s.world.facts.floors.overrides["1"].plots:s.world.facts.floors.overrides["1"].plots.append([x,y])
    s.world.facts.floors.completed_top_floor[str(x)+":"+str(y)]=3
 s.world.touch()
 var built:CommandResult=suite._command(s,"connector_build",{"definition_id":"VC03","floor_id":1,"cell":lift_cell})
 if not built.accepted:return {"ok":false,"error":built.reason,"sim":s}
 var id:String=str(built.changed_ids[0])
 var extended:CommandResult=suite._command(s,"connector_extend",{"connection_id":id,"floor_id":2})
 if not extended.accepted:return {"ok":false,"error":extended.reason,"sim":s}
 suite._command(s,"connector_extend",{"connection_id":id,"floor_id":3})
 suite._add_actor(s,"max_nurse","S49",[50,50]);suite._add_actor(s,"max_patient",species,[39,49])
 var members:Array=["max_nurse","max_patient"]
 var form:Dictionary=ConvoyTrail.formation(s.space,s.world,members[0],members,Vector2.UP)
 for who:String in members:s.world.facts.actors[who].location.cell=form.targets[who].duplicate();s.space.sync_actor(s.world,who)
 var created:Dictionary=ConvoyTrail.create(s.space,s.world,members[0],members)
 if not created.ok:return {"ok":false,"error":created.reason,"sim":s}
 var plan:Dictionary=ConvoyPortal.plan(s.space,s.world,s.world.facts.connectors[id],members[0],members,created.convoy)
 if not plan.ok:return {"ok":false,"error":plan.reason,"sim":s}
 # Declared pre-move initial formation; neither branch starts in transit.
 var initial_poses:Dictionary=plan.get("initial_poses",{})
 if initial_poses.is_empty():
  var seed:Dictionary=created.convoy.duplicate(true)
  var entry:Vector2=ConvoyTrail.point(plan.entry)
  var tail:Vector2=entry-ConvoyTrail.point(plan.inward)*float(seed.spacing)*(members.size()-1)
  seed.points=[[tail.x,tail.y],[entry.x,entry.y]]
  initial_poses=ConvoyTrail.positions(seed,members)
 for who:String in members:
  s.world.facts.actors[who].location.cell=initial_poses[who].cell.duplicate()
  s.world.facts.actors[who].facing=initial_poses[who].facing
  s.space.sync_actor(s.world,who)
 created=ConvoyTrail.create(s.space,s.world,members[0],members)
 s.world.facts.move_request_next=int(s.world.facts.get("move_request_next",0))+1
 var move:Dictionary={"actor_id":members[0],"members":members,"convoy":created.convoy,"path":[{"kind":"connector","connector_id":id,"from":1,"to":nurse_destination}],"cursor":0,"travelled":[s.space.movement._checkpoint(s.world.facts.actors[members[0]])],"blocked_since":-1,"yielding":false,"target_floor":nurse_destination,"target_cell":plan.egress.duplicate(),"request_sequence":s.world.facts.move_request_next}
 s.world.facts.moves[members[0]]=move;s.world.touch();s.space._sync_convoys(s.world)
 return {"ok":true,"sim":s,"connector_id":id,"leader":members[0],"members":members,"target":plan.egress,"plan":plan}

func run()->void:
 var args:=OS.get_cmdline_user_args()
 if args.size()<1 or args.size()>2:push_error("Expected fresh evidence directory and optional patient species");quit(2);return
 var out:String=args[0]
 if DirAccess.dir_exists_absolute(out):push_error("Evidence directory exists");quit(2);return
 DirAccess.make_dir_recursive_absolute(out)
 var species:String=args[1] if args.size()==2 else "S63"
 var reports:Array=[]
 for nurse_dest:int in [2,3]:
  var c:Dictionary=prepare(species,nurse_dest)
  var s:HospitalSimulation=c.sim
  var errors:Array=[]
  if not c.ok:errors.append(c.error)
  var ordinary_dest:int=5-nurse_dest
  suite._add_actor(s,"ordinary","S49",[50,32] if c.plan.get("mode","")=="articulated" else [45,40])
  s.world.touch();s.space.sync_actor(s.world,"ordinary")
  # Validate declared ground geometry explicitly: schema validation alone
  # does not prove a starting body is outside the shaft or another body.
  var initial_bodies:Array=[]
  for actor:Dictionary in s.world.facts.actors.values():
   if actor.location.kind!="floor":continue
   var point:Vector2=ConvoyTrail.point(actor.location.cell)
   var static_error:String=s.space.static_reason(s.world,actor,int(actor.location.floor_id),Vector2i(point.floor()))
   var body:Rect2=s.space.body_rectangle(actor)
   var query:RouteClearance=s.space.navigation.structural_clearance(s.world,actor,int(actor.location.floor_id))
   var body_error:String=query.rectangle_reason(body)
   if not static_error.is_empty() or not body_error.is_empty():errors.append({"actor":actor.id,"invalid_initial_geometry":static_error,"actual_body_error":body_error})
   for prior:Dictionary in initial_bodies:
    if prior.floor_id==actor.location.floor_id and body.intersects(prior.body,false):errors.append({"actor":actor.id,"initial_body_overlap":prior.id})
   initial_bodies.append({"id":actor.id,"floor_id":actor.location.floor_id,"body":body})
  var initial:String=s.world.validate(suite.content)
  if not initial.is_empty():errors.append(initial)
  var name:String="nurse_to_"+str(nurse_dest)
  FileAccess.open(out.path_join(name+"-input.bin"),FileAccess.WRITE).store_var(s.world.freeze(),false)
  var requested:bool=false;var shared:bool=false;var correct_first_exit:bool=false;var done:bool=false
  var shared_facts:Dictionary={};var trace:Array=[]
  for i:int in 4000:
   if not errors.is_empty():break
   var lift:Dictionary=s.world.facts.connectors[c.connector_id]
   # Issue a real second journey while the first actual group is boarding.
   # No queue membership, cabin position or transit phase is manufactured.
   if not requested and lift.phase=="boarding":
    var reason:String=s.space.request_move(s.world,"ordinary",ordinary_dest,[50,44])
    if not reason.is_empty():errors.append(reason);break
    requested=true
   suite._movement_tick(s)
   var error:String=s.world.validate(suite.content)
   if not error.is_empty():errors.append({"tick":s.world.sim_tick,"validation":error});break
   if lift.passenger_groups.size()==2 and lift.riders.size()==3:
    shared=true
    if shared_facts.is_empty() and lift.phase in ["idle","riding"]:
     shared_facts=s.world.freeze()
     FileAccess.open(out.path_join(name+"-shared.bin"),FileAccess.WRITE).store_var(shared_facts,false)
   var early:String="max_nurse" if nurse_dest==2 else "ordinary"
   var late:String="ordinary" if nurse_dest==2 else "max_nurse"
   var a:Dictionary=s.world.facts.actors[early];var b:Dictionary=s.world.facts.actors[late]
   if shared and a.location.kind=="floor" and int(a.location.floor_id)==2 and b.location.kind=="transit":correct_first_exit=true
   if i%25==0:trace.append({"tick":s.world.sim_tick,"phase":lift.phase,"floor":lift.floor_id,"groups":lift.passenger_groups.duplicate(true)})
   if s.space.at(s.world,"max_nurse",nurse_dest,c.target) and s.space.at(s.world,"ordinary",ordinary_dest,[50,44]) and not s.world.facts.moves.has("max_nurse") and not s.world.facts.moves.has("ordinary"):done=true;break
   if i%100==99:print("SHARED_PROGRESS ",name," ",s.world.sim_tick," ",lift.phase);await process_frame
  var report:Dictionary={"name":name,"patient_species":species,"portal_mode":c.plan.get("mode","legacy"),"ok":errors.is_empty() and requested and shared and correct_first_exit and done,"errors":errors,"requested":requested,"actual_shared_cabin":shared,"earlier_destination_exited_while_later_still_aboard":correct_first_exit,"completed":done,"tick":s.world.sim_tick}
  if nurse_dest==2 and not shared_facts.is_empty():report.runtime_negative=runtime_blocker(shared_facts,c.connector_id)
  if nurse_dest==2:report.ok=report.ok and report.get("runtime_negative",{}).get("ok",false)
  FileAccess.open(out.path_join(name+"-final.bin"),FileAccess.WRITE).store_var(s.world.freeze(),false)
  FileAccess.open(out.path_join(name+"-trace.json"),FileAccess.WRITE).store_string(JSON.stringify(trace))
  reports.append(report);s.dispose()
 FileAccess.open(out.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(reports,"\t"))
 print(JSON.stringify(reports));quit(0 if reports.all(func(r:Dictionary)->bool:return r.ok) else 1)

func cabin_rect(c:Dictionary,region:Array)->Rect2:
 var rect:=Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3]))
 var inward:=Vector2.UP.rotated(float(c.get("rotation",0))*PI*0.5).round();var side:=Vector2(-inward.y,inward.x)
 var lo:=Vector2(INF,INF);var hi:=Vector2(-INF,-INF)
 for corner:Vector2 in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
  var d:Vector2=corner-ConvoyTrail.point(c.anchor);var p:=Vector2(d.dot(side),d.dot(inward));lo=lo.min(p);hi=hi.max(p)
 return Rect2(lo,hi-lo)

func runtime_blocker(raw:Dictionary,connection_id:String)->Dictionary:
 # Negative only: a corrupted retained passenger occupies a previously clear
 # later-frame sweep. No result from this branch counts as actual travel.
 var s:=HospitalSimulation.new(WorldState.new(raw.duplicate(true)),suite.content)
 var c:Dictionary=s.world.facts.connectors[connection_id]
 var m:Dictionary=s.world.facts.moves.max_nurse;var plan:Dictionary=m.convoy.portal.plan
 if plan.get("mode","")!="articulated":return legacy_runtime_blocker(s,c,m,plan)
 var ordinary:Dictionary=LiftController.group(c,"ordinary")
 var def:Dictionary=suite.content.definition("vertical_connectors",c.definition_id)
 var k:int=s.space.clearance(s.world.facts.actors.ordinary)
 for index:int in plan.alighting.size():
  var previous:Dictionary=plan.boarding[-1].poses if index==0 else plan.alighting[index-1].poses
  var occupied:Array=[]
  for id:String in m.members:occupied.append(cabin_rect(c,previous[id].region))
  for y:int in range(int(def.cabin_size[1])-k+1):
   for x:int in range(int(def.cabin_size[0])-k+1):
    var region:=Rect2(x,y,k,k)
    if occupied.any(func(r:Rect2)->bool:return r.intersects(region,false)):continue
    var collision:bool=false
    for sweep:Dictionary in plan.alighting[index].cabin_sweeps:
     var r:Array=sweep.rect
     if region.intersects(Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3])),false):collision=true
    if not collision:continue
    c.floor_id=2;c.phase="alighting";c.active_group="max_nurse";c.primary_actor_id="max_nurse";c.from=2;c.to=2
    m.convoy.floor_id=2;m.convoy.portal.stage="alighting";m.convoy.portal.cursor=index
    for id:String in m.members:
     s.world.facts.actors[id].location.queue_cell=previous[id].cell.duplicate();s.world.facts.actors[id].facing=previous[id].facing
    ordinary.cabin_positions.ordinary=[x,y];s.world.facts.actors.ordinary.location.cabin_cell=[x,y]
    s.world.touch();s.space._ensure_actor_index(s.world)
    var before:Dictionary=s.world.facts.actors.duplicate(true)
    s.space.movement._move_articulated_portal(s.world,s.world.facts.actors.max_nurse,m,plan.alighting,2,connection_id)
    var result:Dictionary={"ok":m.convoy.portal.cursor==index and before==s.world.facts.actors and str(m.get("waiting_reason","")).contains("舱内身体阻挡"),"cursor":index,"blocker_cell":[x,y],"reason":m.get("waiting_reason",""),"scope":"Injected blocking-state safety only, not actual journey completion"}
    s.dispose();return result
 s.dispose();return {"ok":false,"reason":"No disjoint integer retained-body sweep candidate found; negative scenario needs a different declared fixture"}

func legacy_cabin_rect(plan:Dictionary,rect:Rect2)->Rect2:
 var inward:Vector2=ConvoyTrail.point(plan.inward);var side:=Vector2(-inward.y,inward.x)
 var lo:=Vector2(INF,INF);var hi:=Vector2(-INF,-INF)
 for corner:Vector2 in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
  var d:Vector2=corner-ConvoyTrail.point(plan.entry);var local:=Vector2(d.dot(side),d.dot(inward));lo=lo.min(local);hi=hi.max(local)
 return Rect2(lo,hi-lo)

func legacy_runtime_blocker(s:HospitalSimulation,c:Dictionary,m:Dictionary,plan:Dictionary)->Dictionary:
 # Fault-injection boundary only, seeded from the actual shared snapshot.
 var ordinary:Dictionary=LiftController.group(c,"ordinary")
 var def:Dictionary=suite.content.definition("vertical_connectors",c.definition_id)
 var k:int=s.space.clearance(s.world.facts.actors.ordinary)
 var trial:Dictionary=m.convoy.duplicate(true);var cursor:int=0
 var budget:float=s.space.walking_speed(s.world.facts.actors.max_nurse)*WorldState.TICK_SECONDS
 while cursor<plan.alighting.size():
  var proposal:Dictionary=ConvoyPortal.propose_step(trial,plan.alighting,cursor,budget)
  if not proposal.ok:s.dispose();return {"ok":false,"reason":proposal.reason}
  var occupied:Array=[]
  # Actual current bodies, not the conservative whole-convoy corridor.
  # A corridor includes empty space between members and is not occupancy.
  var trial_poses:Dictionary=ConvoyTrail.positions(trial,m.members)
  for id:String in m.members:
   var body_actor:Dictionary=s.world.facts.actors[id].duplicate(true)
   body_actor.location={"kind":"floor","floor_id":2,"cell":trial_poses[id].cell.duplicate()}
   body_actor.facing=trial_poses[id].facing
   occupied.append(legacy_cabin_rect(plan,s.space.body_rectangle(body_actor)))
  # Fractional retained-body placements remain inside the cabin. Finer
  # sampling catches a next-frame sweep without overlapping a present body.
  for yi:int in range((int(def.cabin_size[1])-k)*8+1):
   for xi:int in range((int(def.cabin_size[0])-k)*8+1):
    var x:float=float(xi)/8.0;var y:float=float(yi)/8.0
    var region:=Rect2(x,y,k,k)
    if occupied.any(func(r:Rect2)->bool:return r.intersects(region,false)):continue
    if not proposal.fronts.any(func(r:Rect2)->bool:return legacy_cabin_rect(plan,r).intersects(region,false)):continue
    c.floor_id=2;c.phase="alighting";c.active_group="max_nurse";c.primary_actor_id="max_nurse";c.from=2;c.to=2
    m.convoy.floor_id=2;m.convoy.points=trial.points.duplicate(true);m.convoy.portal.cursor=cursor
    var poses:Dictionary=ConvoyTrail.positions(m.convoy,m.members)
    for id:String in m.members:s.world.facts.actors[id].location.queue_cell=poses[id].cell.duplicate();s.world.facts.actors[id].facing=poses[id].facing
    ordinary.cabin_positions.ordinary=[x,y];s.world.facts.actors.ordinary.location.cabin_cell=[x,y]
    s.world.touch();s.space._ensure_actor_index(s.world)
    var before:Dictionary=s.world.facts.actors.duplicate(true);var points:Array=m.convoy.points.duplicate(true)
    s.space.movement._move_convoy_portal(s.world,s.world.facts.actors.max_nurse,m,plan.alighting,2,str(c.id))
    var result:Dictionary={"ok":m.convoy.portal.cursor==cursor and m.convoy.points==points and before==s.world.facts.actors and str(m.get("waiting_reason","")).contains("舱内身体阻挡"),"cursor":cursor,"blocker_cell":[x,y],"reason":m.get("waiting_reason",""),"scope":"Injected legacy blocking-state safety only, not actual journey completion"}
    s.dispose();return result
  trial.points=proposal.points;cursor=int(proposal.cursor)
 s.dispose();return {"ok":false,"reason":"No legacy disjoint actual-body retained sweep candidate"}
