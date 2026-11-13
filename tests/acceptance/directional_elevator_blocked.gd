extends SceneTree
# Actual accepted construction only; elevator movement and recovery are real.
const Cases=preload("res://tests/acceptance/space.gd")
var suite=Cases.new()
func _initialize()->void:call_deferred("run")
func fixture()->HospitalSimulation:
 var s:HospitalSimulation=suite._fixture();suite._history_height(s,2)
 suite._command(s,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[36,72]})
 suite._command(s,"connector_extend",{"connection_id":suite._connection(s),"floor_id":2})
 return s
func queue_obstacle()->Dictionary:
 var s:=fixture();var c:Dictionary=s.world.facts.connectors[suite._connection(s)];c.floor_id=2
 var block:CommandResult=suite._command(s,"build_facility",{"id":"queue_block","definition_id":"SE02","floor_id":1,"cell":[39,76]})
 suite._add_actor(s,"queue_rider","S49",[44,82],1)
 var request:String=s.space.request_move(s.world,"queue_rider",2,[48,82]);var errors:Array=[];var queued:Array=[];var boarded:bool=false;var arrived:bool=false
 for i:int in 800:
  suite._movement_tick(s)
  var v:String=s.world.validate(suite.content)
  if not v.is_empty():errors.append(v);break
  for line:Array in c.get("landing_queues",{}).values():
   for entry:Dictionary in line:
    if not entry in queued:queued.append(entry.duplicate(true))
  boarded=boarded or s.world.facts.actors.queue_rider.location.kind=="transit"
  if s.space.at(s.world,"queue_rider",2,[48,82]) and not s.world.facts.moves.has("queue_rider"):arrived=true;break
 var r:Dictionary={"ok":block.accepted and request.is_empty() and not queued.is_empty() and boarded and arrived and errors.is_empty(),"build":block.to_record(),"queue_entries":queued,"actual_boarding":boarded,"arrived":arrived,"errors":errors,"scope":"Occupied first queue position must select an actually reachable unobstructed alternate; not all-position blockage"};s.dispose();return r
func run()->void:
 suite.content=HospitalContent.new();var args:=OS.get_cmdline_user_args();var s:=fixture();var c:Dictionary=s.world.facts.connectors[suite._connection(s)]
 suite._add_actor(s,"rider","S49",[44,82],1)
 var req:String=s.space.request_move(s.world,"rider",2,[48,82]);var errors:Array=[];var started:bool=false
 for i:int in 400:
  suite._movement_tick(s)
  var v:String=s.world.validate(suite.content)
  if not v.is_empty():errors.append(v);break
  if c.phase=="riding":started=true;break
 var before:Dictionary=s.world.freeze()
 var block:CommandResult=suite._command(s,"build_facility",{"id":"exit_block","definition_id":"SE02","floor_id":2,"cell":[36,76]})
 var reasons:Array=[];var remained_transit:bool=true
 for i:int in 150:
  suite._movement_tick(s)
  var v:String=s.world.validate(suite.content)
  if not v.is_empty():errors.append(v);break
  var reason:String=str(c.get("waiting_reason",""))
  if not reason.is_empty() and not reason in reasons:reasons.append(reason)
  if s.world.facts.actors.rider.location.kind!="transit":remained_transit=false
 var blocked:Dictionary=s.world.freeze()
 var remove:CommandResult=suite._command(s,"build_demolish",{"target_id":"exit_block"})
 var arrived:bool=false
 for i:int in 800:
  suite._movement_tick(s)
  var v:String=s.world.validate(suite.content)
  if not v.is_empty():errors.append(v);break
  if s.space.at(s.world,"rider",2,[48,82]) and not s.world.facts.moves.has("rider"):arrived=true;break
 var report:Dictionary={"ok":req.is_empty() and started and block.accepted and remained_transit and reasons.any(func(reason:String)->bool:return reason.contains("电梯出口") and reason.contains("阻挡")) and remove.accepted and arrived and errors.is_empty(),"request":req,"started":started,"build":block.to_record(),"remained_transit":remained_transit,"reasons":reasons,"demolish":remove.to_record(),"arrived_after_removal":arrived,"errors":errors,"final_connector":c.duplicate(true),"scope":"One legally constructed obstruction at actual destination exit; no simulated occupancy or teleport"}
 report.queue_obstacle=queue_obstacle();report.ok=report.ok and report.queue_obstacle.ok
 if not args.is_empty():
  FileAccess.open(args[0]+"-before.bin",FileAccess.WRITE).store_var(before,true)
  FileAccess.open(args[0]+"-blocked.bin",FileAccess.WRITE).store_var(blocked,true)
  FileAccess.open(args[0]+"-after.bin",FileAccess.WRITE).store_var(s.world.freeze(),true)
  FileAccess.open(args[0]+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print(JSON.stringify(report));s.dispose();quit(0 if report.ok else 1)
