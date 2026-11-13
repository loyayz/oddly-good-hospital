extends SceneTree
# Historical worn-device input only. The order, contractor journey, boarding
# call, maintenance start, work and subsequent ride all execute normally.
const Cases=preload("res://tests/acceptance/space.gd")
var suite=Cases.new()
func _initialize()->void:call_deferred("run")
func initial()->Dictionary:
 var s:HospitalSimulation=suite._fixture();suite._history_height(s,2)
 var built:CommandResult=suite._command(s,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[36,72]})
 var id:String=suite._connection(s);var ext:CommandResult=suite._command(s,"connector_extend",{"connection_id":id,"floor_id":2})
 s.world.facts.connectors[id].condition=60.0 # Legal historical wear boundary; not a claimed naturally generated wear history.
 suite._add_actor(s,"rider","S49",[44,82],1)
 var order:CommandResult=suite._command(s,"maintenance_order",{"facility_id":id})
 var r:Dictionary={"ok":built.accepted and ext.accepted and order.accepted,"order":order.to_record(),"job_id":order.changed_ids[0] if order.accepted else "","facts":s.world.freeze(),"validation":s.world.validate(suite.content)};s.dispose();return r
func calibrate(facts:Dictionary,job_id:String)->int:
 var s:=HospitalSimulation.new(WorldState.new(facts.duplicate(true)),suite.content);var tick:int=-1
 for i:int in 600:
  s.step()
  if s.world.facts.maintenance.jobs[job_id].started:tick=s.world.sim_tick;break
 s.dispose();return tick
func attempt(facts:Dictionary,job_id:String,start_tick:int,stem:String)->Dictionary:
 var s:=HospitalSimulation.new(WorldState.new(facts.duplicate(true)),suite.content);var c:Dictionary=s.world.facts.connectors[suite._connection(s)];var job:Dictionary=s.world.facts.maintenance.jobs[job_id]
 var request:String="not issued";var issued:bool=false;var overlap:bool=false;var boarded_during_work:bool=false;var actual_board:bool=false;var arrived:bool=false;var errors:Array=[];var trace:Array=[];var boundary:Dictionary={};var after:Dictionary={}
 for i:int in 1400:
  if not issued and s.world.sim_tick>=start_tick:request=s.space.request_move(s.world,"rider",2,[48,82]);issued=true
  var m:Dictionary=s.world.facts.moves.get("rider",{});var pre_call:bool=m.has("lift_boarding_call") and s.world.facts.actors.rider.location.kind=="floor";var was_working:bool=bool(c.get("maintenance_block",false));var before:Dictionary=s.world.freeze() if pre_call and not job.started else {}
  s.step()
  var v:String=s.world.validate(suite.content)
  if not v.is_empty():errors.append(v);break
  if pre_call and not before.is_empty() and job.started and c.get("maintenance_block",false):overlap=true;boundary=before;after=s.world.freeze()
  var transit:bool=s.world.facts.actors.rider.location.kind=="transit";actual_board=actual_board or transit
  boarded_during_work=boarded_during_work or (transit and (was_working or c.get("maintenance_block",false)))
  if i%10==0:trace.append({"tick":s.world.sim_tick,"job":job.duplicate(true),"connector":c.duplicate(true),"actor":s.world.facts.actors.rider.duplicate(true),"move":s.world.facts.moves.get("rider",{}).duplicate(true)})
  arrived=s.space.at(s.world,"rider",2,[48,82]) and not s.world.facts.moves.has("rider")
  if arrived and job.phase=="completed":break
 var r:Dictionary={"ok":overlap and request.is_empty() and not boarded_during_work and actual_board and arrived and job.phase=="completed" and errors.is_empty(),"request_tick":start_tick,"request":request,"actual_work_start_with_released_floor_call":overlap,"boarded_during_maintenance":boarded_during_work,"actual_boarding":actual_board,"arrived":arrived,"job":job.duplicate(true),"errors":errors,"final_connector":c.duplicate(true),"final_move":s.world.facts.moves.get("rider",{}).duplicate(true)}
 if not stem.is_empty():
  FileAccess.open(stem+"-before-work.bin",FileAccess.WRITE).store_var(boundary,true)
  FileAccess.open(stem+"-after-work-start.bin",FileAccess.WRITE).store_var(after,true)
  FileAccess.open(stem+"-final.bin",FileAccess.WRITE).store_var(s.world.freeze(),true)
  FileAccess.open(stem+"-trace.json",FileAccess.WRITE).store_string(JSON.stringify(trace,"\t"))
 s.dispose();return r
func run()->void:
 suite.content=HospitalContent.new();var args:=OS.get_cmdline_user_args();var stem:String=args[0];var source:Dictionary=initial();var start:int=-1;var rows:Array=[]
 if source.ok and source.validation.is_empty():
  start=calibrate(source.facts,source.job_id)
  if start>=61:
   for offset:int in [0,-5,5]:
    var result:Dictionary=attempt(source.facts,source.job_id,start-61+offset,stem+"-offset%d"%offset);rows.append(result)
    if result.actual_work_start_with_released_floor_call:break
 var report:Dictionary={"ok":rows.any(func(r:Dictionary)->bool:return r.ok),"source_ok":source.ok,"source_validation":source.validation,"order":source.order,"normal_worker_start_tick":start,"rows":rows,"scope":"Historical condition=60 at initial input, then real order/contractor/maintenance progression and real released boarding call; no injected maintenance block or worker position"}
 FileAccess.open(stem+"-input.bin",FileAccess.WRITE).store_var(source.facts,true);FileAccess.open(stem+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report));quit(0 if report.ok else 1)
