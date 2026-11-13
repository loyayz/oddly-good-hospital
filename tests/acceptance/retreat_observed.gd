extends SceneTree
class Observer extends HospitalMovement:
 var errors:Array=[]
 var observed:int=0
 var choices:Array=[]
 func _init(geometry:HospitalSpace)->void:super(geometry)
 func _move_step(world:WorldState,actor:Dictionary,movement:Dictionary,segment:Dictionary)->MotionResult:
  var before:Dictionary=actor.duplicate(true)
  var result:MotionResult=super._move_step(world,actor,movement,segment)
  if actor.id in ["bench_patient_0044","bench_patient_0048"]:
   observed+=1
   if result.blocked and actor!=before:errors.append({"tick":world.sim_tick,"error":"blocked_pose_changed"})
   if result.actual_motion.length()>space.walking_speed(actor)*WorldState.TICK_SECONDS+0.00002:errors.append({"tick":world.sim_tick,"error":"walking_budget"})
   if not result.blocked and actor.location.cell!=before.location.cell:
    var other_id:String="bench_patient_0044" if actor.id=="bench_patient_0048" else "bench_patient_0048"
    var other:Dictionary=world.facts.actors[other_id]
    if other.location.kind=="floor" and actor.location.floor_id==other.location.floor_id and space.body_rectangle(actor).intersects(space.body_rectangle(other),false):errors.append({"tick":world.sim_tick,"error":"pair_overlap"})
  return result
 func _local_choose_options(world:WorldState,actor:Dictionary,movement:Dictionary,motion:Vector2,fixed:Array)->bool:
  var before:Dictionary=movement.duplicate(true)
  var pose:Dictionary=actor.duplicate(true)
  var ok:bool=super._local_choose_options(world,actor,movement,motion,fixed)
  if actor.id in ["bench_patient_0044","bench_patient_0048"] and ok:
   var retained:bool=true
   for key:String in ["path","cursor","request_sequence","target_cell","travelled","waiting_need_id"]:
    retained=retained and movement.get(key)==before.get(key)
   if not retained or pose!=actor:errors.append({"tick":world.sim_tick,"error":"ownership_or_pose_changed"})
   var target:Vector2=ConvoyTrail.point(movement.local_move.target.cell)
   var final_pose:Dictionary=actor.duplicate()
   var direction:Vector2=target-ConvoyTrail.point(actor.location.cell)
   final_pose.facing=atan2(direction.x,direction.y)
   var rect:Rect2=space._actor_rect(final_pose,target)
   for door:Dictionary in space.movement_doors(world,actor,rect,[]):
    if rect.intersects(space._door_rect(door,space._door_span(actor,door)),false):errors.append({"tick":world.sim_tick,"error":"stops_in_door"})
   choices.append({"tick":world.sim_tick,"actor":actor.id,"from":actor.location.cell.duplicate(),"target":movement.local_move.target.cell.duplicate(),"request":movement.request_sequence})
  return ok
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var args:PackedStringArray=OS.get_cmdline_user_args()
 var e:Dictionary=FileAccess.open(args[0],FileAccess.READ).get_var()
 var content:=HospitalContent.new()
 var w:=WorldState.new(e.facts)
 var sim:=HospitalSimulation.new(w,content)
 sim.services.experience.sample_workers_enabled=true
 sim.services.experience.sample_worker_tasks=4
 var ops=load("res://tools/performance/current/comprehensive_operations.gd").new()
 for key:String in w.facts.command_receipts:
  if key.begins_with(ops.PREFIX):ops.submitted[key.trim_prefix(ops.PREFIX)]={}
 var observer:=Observer.new(sim.space)
 sim.space.movement=observer
 var initial:int=w.sim_tick
 var head:String="bench_visit_0048"
 var initial_need:Dictionary=w.facts.waiting_life.needs.get(head,{}).duplicate(true)
 var initial_move:Dictionary=w.facts.moves.get("bench_patient_0048",{}).duplicate(true)
 var gp:Array=[]
 var need_finished:Dictionary={}
 var errors:Array=[]
 var log:=FileAccess.open(args[1]+".steps.ndjson",FileAccess.WRITE)
 for index:int in 2000:
  ops.enqueue(sim,int(e.completed_steps)+index-1000)
  var tick:TickResult=sim.step()
  if tick==null:errors.append("null_tick");break
  for event:SimEvent in tick.facts:
   if event.kind in ["service_started","service_completed"] and event.details.get("kind","")=="gp":gp.append({"tick":event.sim_tick,"kind":event.kind,"ids":event.changed_ids})
  var need:Dictionary=w.facts.waiting_life.needs.get(head,{})
  if need.is_empty() and need_finished.is_empty():
   need_finished={"tick":w.sim_tick,"visit":w.facts.visits.get(head,{}).duplicate(true),"ticket":w.facts.tickets.get(initial_need.get("ticket_id",""),{}).duplicate(true)}
  var missing:Array=[]
  for c:Dictionary in w.facts.connectors.values():
   for line:Array in c.get("landing_queues",{}).values():
    for row:Dictionary in line:
     if not w.facts.moves.has(row.actor_id):missing.append(row.actor_id)
  log.store_line(JSON.stringify({"tick":w.sim_tick,"gp":gp,"need":need,"missing":missing}));log.flush()
  if not missing.is_empty():errors.append(missing);break
  if not gp.is_empty() and not need_finished.is_empty():break
 errors.append_array(observer.errors)
 if gp.is_empty():errors.append("No subsequent real GP service within 2000 steps")
 if need_finished.is_empty():errors.append("Original life need did not complete within 2000 steps")
 if not w.validate(content).is_empty():errors.append(w.validate(content))
 var result:Dictionary={"observed_steps":observer.observed,"choices":observer.choices,"initial_tick":initial,"final_tick":w.sim_tick,"initial_need":initial_need,"initial_move":initial_move,"gp":gp,"need_finished":need_finished,"final_need":w.facts.waiting_life.needs.get(head,{}),"final_move":w.facts.moves.get("bench_patient_0048",{}),"validation":w.validate(content),"errors":errors}
 FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
 FileAccess.open(args[1]+".final.bin",FileAccess.WRITE).store_var({"facts":w.freeze()})
 print(JSON.stringify(result));sim.dispose();quit(0 if errors.is_empty() else 1)
