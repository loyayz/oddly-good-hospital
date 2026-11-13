extends SceneTree
# A legitimate furniture corridor and an actual remote journey create this
# boundary. No call, queue position, in-flight state or completion is fabricated.
const Cases=preload("res://tests/acceptance/space.gd")
var suite=Cases.new()
func _initialize()->void:call_deferred("run")
func input()->Dictionary:
 var s:HospitalSimulation=suite._fixture();suite._history_height(s,12);var commands:Array=[]
 commands.append(suite._command(s,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[36,72]}).to_record())
 var cid:String=suite._connection(s)
 for f:int in range(2,13):commands.append(suite._command(s,"connector_extend",{"connection_id":cid,"floor_id":f}).to_record())
 # The lift occupies the missing top-barrier cells. A single lower opening
 # at x=50 connects a real waiting pocket, not an alternate cross-corridor.
 for x:int in range(32,64):
  if x<36 or x>=40:commands.append(suite._command(s,"build_facility",{"id":"top_%d"%x,"definition_id":"SE02","floor_id":1,"cell":[x,75]}).to_record())
  if x!=50:commands.append(suite._command(s,"build_facility",{"id":"bottom_%d"%x,"definition_id":"SE02","floor_id":1,"cell":[x,77]}).to_record())
 suite._add_actor(s,"remote_rider","S49",[39,76],1)
 suite._add_actor(s,"queue_rider","S49",[50,80],1)
 suite._add_actor(s,"passer","S49",[33,76],1)
 var result:Dictionary={"commands":commands,"facts":s.world.freeze(),"validation":s.world.validate(suite.content)};s.dispose();return result
func trial(facts:Dictionary,with_queue:bool,trigger_tick:int,stem:String)->Dictionary:
 var s:=HospitalSimulation.new(WorldState.new(facts.duplicate(true)),suite.content);var c:Dictionary=s.world.facts.connectors[suite._connection(s)]
 var requests:Array=[s.space.request_move(s.world,"remote_rider",12,[48,82])]
 if with_queue:requests.append(s.space.request_move(s.world,"queue_rider",2,[48,82]))
 var errors:Array=[];var captured:bool=false;var capture_tick:int=-1;var queued_entry:Dictionary={}
 for i:int in 1200:
  suite._movement_tick(s)
  var v:String=s.world.validate(suite.content)
  if not v.is_empty():errors.append(v);break
  if with_queue:
   for line:Array in c.get("landing_queues",{}).values():
    for entry:Dictionary in line:
     if entry.actor_id=="queue_rider":queued_entry=entry.duplicate(true)
   captured=s.world.sim_tick>=trigger_tick
  else:captured=s.world.sim_tick>=trigger_tick
  if captured:capture_tick=s.world.sim_tick;break
 var at_trigger:Dictionary=s.world.freeze();var quote:Dictionary={};var request:String="not triggered";var readonly:bool=true
 if captured:
  quote=s.space.route(s.world,"passer",1,[55,76],[],{},false)
  readonly=at_trigger==s.world.freeze()
  request=s.space.request_move(s.world,"passer",1,[55,76])
 var arrived:bool=false;var steps:int=0;var trace:Array=[];var waiting_reasons:Array=[];var max_still:int=0;var still:int=0;var last:Dictionary={}
 for i:int in 1200:
  if not captured or not errors.is_empty():break
  suite._movement_tick(s);steps=i+1
  var v:String=s.world.validate(suite.content)
  if not v.is_empty():errors.append(v);break
  var a:Dictionary=s.world.facts.actors.passer;var m:Dictionary=s.world.facts.moves.get("passer",{})
  if last==a.location:still+=1
  else:still=0;last=a.location.duplicate(true)
  max_still=maxi(max_still,still)
  var reason:String=m.get("waiting_reason","")
  if not reason.is_empty() and not reason in waiting_reasons:waiting_reasons.append(reason)
  if i%10==0:trace.append({"tick":s.world.sim_tick,"passer":a.duplicate(true),"passer_move":m.duplicate(true),"queue_actor":s.world.facts.actors.queue_rider.duplicate(true),"queue_move":s.world.facts.moves.get("queue_rider",{}).duplicate(true),"connector":c.duplicate(true)})
  arrived=s.space.at(s.world,"passer",1,[55,76]) and not s.world.facts.moves.has("passer")
  if arrived:break
 var r:Dictionary={"with_queue":with_queue,"captured":captured,"trigger_tick":capture_tick,"queued_entry":queued_entry,"initial_requests":requests,"passer_route":quote,"query_readonly":readonly,"passer_request":request,"arrived":arrived,"steps_after_trigger":steps,"max_stationary_ticks":max_still,"waiting_reasons":waiting_reasons,"errors":errors,"final_passer":s.world.facts.actors.passer.duplicate(true),"final_queue_move":s.world.facts.moves.get("queue_rider",{}).duplicate(true)}
 if not stem.is_empty():
  FileAccess.open(stem+"-trigger.bin",FileAccess.WRITE).store_var(at_trigger,true)
  FileAccess.open(stem+"-final.bin",FileAccess.WRITE).store_var(s.world.freeze(),true)
  FileAccess.open(stem+"-trace.json",FileAccess.WRITE).store_string(JSON.stringify(trace,"\t"))
 s.dispose();return r
func run()->void:
 suite.content=HospitalContent.new();var args:=OS.get_cmdline_user_args();var stem:String=args[0] if not args.is_empty() else "";var start:Dictionary=input()
 var accepted:bool=start.commands.all(func(c:Dictionary)->bool:return c.accepted)
 var q:Dictionary={};var b:Dictionary={}
 if accepted and start.validation.is_empty():
  q=trial(start.facts,true,76,stem+"-queued")
  if q.captured:b=trial(start.facts,false,q.trigger_tick,stem+"-baseline")
 var ok:bool=accepted and start.validation.is_empty() and not b.is_empty() and b.arrived and b.passer_route.get("ok",false) and q.arrived and q.passer_route.get("ok",false) and b.errors.is_empty() and q.errors.is_empty()
 var report:Dictionary={"ok":ok,"all_construction_accepted":accepted,"commands":start.commands,"input_validation":start.validation,"queued":q,"baseline":b,"trigger_policy":"Fixed original external passer request tick 76; do not require the old defective queue location or a particular car phase",
 "scope":"Same lawful narrow furniture corridor, with/without naturally arrived elevator queue; 12-floor real trip only provides a waiting window, not a full hospital load benchmark"}
 if not stem.is_empty():
  FileAccess.open(stem+"-input.bin",FileAccess.WRITE).store_var(start.facts,true)
  FileAccess.open(stem+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print(JSON.stringify(report));quit(0 if ok else 1)
