extends SceneTree
# Natural equipment fault at the normal scan boundary. Only initial RNG seed
# selection and ordinary request timing vary; no failed/pending/phase mutation.
const Cases=preload("res://tests/acceptance/space.gd")
var suite=Cases.new()
func _initialize()->void:call_deferred("run")
func seed_record()->Dictionary:
 var limit:int=0
 for row:Dictionary in suite.content.balance.equipment.classes:
  if row.id=="utility":limit=int(row.base_failure_bp)
 for seed_value:int in range(1,100000):
  var generator:=RandomNumberGenerator.new();generator.seed=seed_value
  var state:String=str(generator.state);var value:int=generator.randi_range(0,9999)
  if value<limit:return {"record":{"algorithm":"godot-pcg32-4.7.2","seed_decimal":str(seed_value),"state_decimal":state},"first_draw":value,"threshold":limit}
 return {}
func setup(seed:Dictionary)->Dictionary:
 var s:HospitalSimulation=suite._fixture();suite._history_height(s,4);s.world.facts.rng.equipment=seed.record.duplicate(true)
 var commands:Array=[suite._command(s,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[36,72]}).to_record()]
 var cid:String=suite._connection(s)
 for f:int in [2,3,4]:commands.append(suite._command(s,"connector_extend",{"connection_id":cid,"floor_id":f}).to_record())
 suite._add_actor(s,"positioner","S49",[44,82],1)
 var request:String=s.space.request_move(s.world,"positioner",4,[55,86]);var arrived:bool=false;var error:String=""
 for i:int in 500:
  s.services.maintenance.boundaries(s.world);suite._movement_tick(s)
  error=s.world.validate(suite.content)
  if not error.is_empty():break
  arrived=s.space.at(s.world,"positioner",4,[55,86]) and not s.world.facts.moves.has("positioner")
  if arrived:break
 suite._add_actor(s,"near","S49",[42,80],1);suite._add_actor(s,"far","S49",[44,82],1)
 var r:Dictionary={"ok":commands.all(func(c:Dictionary)->bool:return c.accepted) and request.is_empty() and arrived and error.is_empty() and s.world.sim_tick<600,"commands":commands,"error":error,"tick":s.world.sim_tick,"facts":s.world.freeze()};s.dispose();return r
func requests(s:HospitalSimulation)->Array:
 return [s.space.request_move(s.world,"near",2,[45,82]),s.space.request_move(s.world,"far",3,[48,82])]
func phase_key(c:Dictionary)->String:
 if c.get("passenger_groups",[]).size()<2:return ""
 return "loaded_idle" if c.phase=="idle" else str(c.phase)
func calibrate(facts:Dictionary)->Dictionary:
 var s:=HospitalSimulation.new(WorldState.new(facts.duplicate(true)),suite.content);var start:int=s.world.sim_tick;var offsets:Dictionary={};requests(s)
 for i:int in 500:
  var c:Dictionary=s.world.facts.connectors[suite._connection(s)];var key:String=phase_key(c)
  if key in ["boarding","riding","alighting","loaded_idle"] and not offsets.has(key):offsets[key]=s.world.sim_tick-start
  suite._movement_tick(s)
  if offsets.size()==4:break
 s.dispose();return offsets
func complete(s:HospitalSimulation,down:bool=false)->bool:
 return s.space.at(s.world,"near",1 if down else 2,[45,82]) and s.space.at(s.world,"far",1 if down else 3,[48,82]) and not s.world.facts.moves.has("near") and not s.world.facts.moves.has("far")
func case(facts:Dictionary,wanted:String,offset:int,stem:String)->Dictionary:
 var s:=HospitalSimulation.new(WorldState.new(facts.duplicate(true)),suite.content);var c:Dictionary=s.world.facts.connectors[suite._connection(s)]
 var delay:int=600-offset-s.world.sim_tick;var errors:Array=[];var requests_ok:bool=true;var before:Dictionary={};var after_fault:Dictionary={};var trace:Array=[]
 if delay<0:errors.append("The actual prerequisite finishes too late for the first normal fault scan")
 for i:int in maxi(delay,0):s.services.maintenance.boundaries(s.world);suite._movement_tick(s)
 for reason:String in requests(s):requests_ok=requests_ok and reason.is_empty()
 while s.world.sim_tick<600 and errors.is_empty():
  s.services.maintenance.boundaries(s.world);suite._movement_tick(s)
  var e:String=s.world.validate(suite.content)
  if not e.is_empty():errors.append(e)
 var actual_phase:String=phase_key(c);before=s.world.freeze()
 var occupied:Dictionary=HospitalEquipmentUse.query(s.world,c.id);var safe_before:bool=s.services.maintenance._safe_free(s.world,c.id)
 s.services.maintenance.boundaries(s.world);after_fault=s.world.freeze()
 var natural_fault:bool=bool(c.pending_failure) or bool(c.failed);var premature_failed:Array=[];var safe_arrivals:bool=false
 for i:int in 1200:
  if not errors.is_empty():break
  if c.failed and not c.riders.is_empty():premature_failed.append({"tick":s.world.sim_tick,"phase":c.phase,"riders":c.riders.duplicate()})
  if i%20==0:trace.append({"tick":s.world.sim_tick,"connector":c.duplicate(true),"near":s.world.facts.actors.near.duplicate(true),"far":s.world.facts.actors.far.duplicate(true)})
  suite._movement_tick(s);s.services.maintenance.boundaries(s.world)
  var e:String=s.world.validate(suite.content)
  if not e.is_empty():errors.append(e);break
  safe_arrivals=complete(s)
  if safe_arrivals:break
 var down_complete:bool=false;var up:Dictionary={};var down:Dictionary={}
 if safe_arrivals:
  up=HospitalTransit.quote(s.space,s.world,c,"near",2,3,0);down=HospitalTransit.quote(s.space,s.world,c,"far",3,1,0)
  s.space.request_move(s.world,"near",1,[45,82]);s.space.request_move(s.world,"far",1,[48,82])
  for i:int in 1600:
   suite._movement_tick(s);s.services.maintenance.boundaries(s.world)
   var e:String=s.world.validate(suite.content)
   if not e.is_empty():errors.append(e);break
   down_complete=complete(s,true)
   if down_complete:break
 var report:Dictionary={"ok":actual_phase==wanted and requests_ok and natural_fault and bool(occupied.occupied) and not safe_before and safe_arrivals and premature_failed.is_empty() and down_complete and not up.get("ok",true) and down.get("ok",false) and c.failed and errors.is_empty(),"wanted_phase":wanted,"actual_phase_at_normal_scan":actual_phase,"delay_ticks":delay,"natural_fault":natural_fault,"occupied_before_scan":occupied,"safe_free_before_scan":safe_before,"safe_original_destinations":safe_arrivals,"failed_while_riders_still_present":premature_failed,"downward_return_complete":down_complete,"up_quote":up,"down_quote":down,"errors":errors,"final_connector":c.duplicate(true),"final_moves":s.world.facts.moves.duplicate(true)}
 if not stem.is_empty():
  FileAccess.open(stem+"-before-scan.bin",FileAccess.WRITE).store_var(before,true)
  FileAccess.open(stem+"-after-scan.bin",FileAccess.WRITE).store_var(after_fault,true)
  FileAccess.open(stem+"-final.bin",FileAccess.WRITE).store_var(s.world.freeze(),true)
  FileAccess.open(stem+"-trace.json",FileAccess.WRITE).store_string(JSON.stringify(trace,"\t"))
 s.dispose();return report
func run()->void:
 suite.content=HospitalContent.new();var args:=OS.get_cmdline_user_args();var stem:String=args[0] if not args.is_empty() else "";var seed:Dictionary=seed_record();var start:Dictionary=setup(seed);var offsets:Dictionary={};var rows:Array=[]
 if start.ok:
  offsets=calibrate(start.facts)
  for key:String in ["boarding","riding","alighting","loaded_idle"]:
   if offsets.has(key):rows.append(case(start.facts,key,offsets[key],stem+"-"+key))
 var report:Dictionary={"ok":start.ok and rows.size()==4 and rows.all(func(r:Dictionary)->bool:return r.ok),"seed_selection":seed,"setup_ok":start.ok,"setup_tick":start.tick,"setup_error":start.error,"phase_offsets":offsets,"rows":rows,"scope":"Normal equipment RNG scan plus real elevator movement boundaries; repair dispatch/repair work is deliberately not executed, so this is not complete maintenance validation"}
 if not stem.is_empty():
  FileAccess.open(stem+"-input.bin",FileAccess.WRITE).store_var(start.facts,true)
  FileAccess.open(stem+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print(JSON.stringify(report));quit(0 if report.ok else 1)
