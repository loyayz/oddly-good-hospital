extends SceneTree
# Capture a naturally emitted boarding call before actual boarding; change the
# real move request, never manufacture or edit lift state to reach the boundary.
const Cases=preload("res://tests/acceptance/space.gd")
var suite=Cases.new()
func _initialize()->void:call_deferred("run")
func run()->void:
 suite.content=HospitalContent.new();var args:=OS.get_cmdline_user_args();var stem:String=args[0] if not args.is_empty() else ""
 var s:HospitalSimulation=suite._fixture();suite._history_height(s,3)
 var built:CommandResult=suite._command(s,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[36,72]})
 var cid:String=suite._connection(s);var extensions:Array=[]
 for floor:int in [2,3]:extensions.append(suite._command(s,"connector_extend",{"connection_id":cid,"floor_id":floor}).to_record())
 suite._add_actor(s,"rider","S49",[44,82],1)
 var request:String=s.space.request_move(s.world,"rider",2,[48,82]);var c:Dictionary=s.world.facts.connectors[cid]
 var captured:bool=false;var errors:Array=[];var trace:Array=[]
 for i:int in 600:
  suite._movement_tick(s)
  var validation:String=s.world.validate(suite.content)
  if not validation.is_empty():errors.append(validation);break
  var m:Dictionary=s.world.facts.moves.get("rider",{})
  if m.has("lift_boarding_call") and s.world.facts.actors.rider.location.kind=="floor":captured=true;break
 var before:Dictionary=s.world.freeze();var before_tick:int=s.world.sim_tick
 var changed:String="not captured"
 if captured:changed=s.space.request_move(s.world,"rider",3,[48,82])
 var after_request:Dictionary=s.world.freeze();var complete:bool=false;var boarded:bool=false;var steps:int=0
 for i:int in 2400:
  if not captured or not errors.is_empty():break
  suite._movement_tick(s);steps=i+1
  var v:String=s.world.validate(suite.content)
  if not v.is_empty():errors.append(v);break
  var m:Dictionary=s.world.facts.moves.get("rider",{});var a:Dictionary=s.world.facts.actors.rider
  boarded=boarded or a.location.kind=="transit"
  if i%20==0:trace.append({"tick":s.world.sim_tick,"actor":a.duplicate(true),"move":m.duplicate(true),"connector":c.duplicate(true)})
  complete=s.space.at(s.world,"rider",3,[48,82]) and not s.world.facts.moves.has("rider")
  if complete:break
 var report:Dictionary={"ok":built.accepted and extensions.all(func(e:Dictionary)->bool:return e.accepted) and request.is_empty() and captured and changed.is_empty() and boarded and complete and errors.is_empty(),"source":"Actual lawful build and movement; naturally emitted call, followed only by real request_move retarget","build":built.to_record(),"extend":extensions,"initial_request":request,"captured_floor_call":captured,"capture_tick":before_tick,"retarget_reason":changed,"steps":steps,"actual_boarding_after_retarget":boarded,"arrived_new_floor":complete,"errors":errors,"final_move":s.world.facts.moves.get("rider",{}).duplicate(true),"final_actor":s.world.facts.actors.rider.duplicate(true),"final_connector":c.duplicate(true)}
 if not stem.is_empty():
  FileAccess.open(stem+"-input.bin",FileAccess.WRITE).store_var(before,true)
  FileAccess.open(stem+"-after-request.bin",FileAccess.WRITE).store_var(after_request,true)
  FileAccess.open(stem+"-final.bin",FileAccess.WRITE).store_var(s.world.freeze(),true)
  FileAccess.open(stem+"-trace.json",FileAccess.WRITE).store_string(JSON.stringify(trace,"\t"))
  FileAccess.open(stem+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print(JSON.stringify(report));s.dispose();quit(0 if report.ok else 1)
