extends SceneTree
# Separate spatial contract: 8 real riders leave one cabin cell; the 2-person
# patient-family head must wait intact and the one-person follower cannot pass.
const Cases=preload("res://tests/acceptance/space.gd")
var suite=Cases.new()
func _initialize()->void:call_deferred("run")
func run()->void:
 suite.content=HospitalContent.new();var args:=OS.get_cmdline_user_args();var stem:String=args[0] if not args.is_empty() else "/tmp/group-fifo"
 var s:HospitalSimulation=suite._fixture();suite._history_height(s,3)
 var commands:Array=[suite._command(s,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[36,72]}).to_record()]
 var cid:String=suite._connection(s)
 for f:int in [2,3]:commands.append(suite._command(s,"connector_extend",{"connection_id":cid,"floor_id":f}).to_record())
 var c:Dictionary=s.world.facts.connectors[cid]
 var visit:Dictionary=suite._waiting_visit(s,"fifo_patient",[39,76]);var patient:String=visit.actor_id
 # Independent input declaration before any travel or clinical use.
 s.world.facts.actors[patient].location.floor_id=2;s.space.sync_actor(s.world,patient)
 var family:String="fifo_companion";suite._add_actor(s,family,"S49",[40,76],2)
 s.world.facts.actors[family].relative_of=patient
 s.world.facts.visitors={"next_scan_tick":s.world.sim_tick,"requests":{},"stays":{"fifo_family":{"id":"fifo_family","visit_id":visit.id,"actor_id":family,"purpose":"companion","phase":"walking","remaining_ticks":0,"life_task":{},"return_ward_first":false,"yielding":false,"destination":{},"waiting_floor":2,"waiting_cell":[40,76],"next_need_tick":10000,"next_purpose":"water"}}}
 var goals:Dictionary={patient:[43,88],family:[45,88],"follower":[47,88]}
 suite._add_actor(s,"follower","S49",[41,76],2)
 var fillers:Array=[]
 for i:int in 8:
  var id:String="fill_%02d"%i;fillers.append(id)
  suite._add_actor(s,id,"S49",[40+(i%4)*2,82+(i/4)*2],1)
  goals[id]=[40+(i%4)*2,82+(i/4)*2]
  s.space.request_move(s.world,id,3,goals[id])
 var input_validation:String=s.world.validate(suite.content);var errors:Array=[];var events:Array=[];var trace:Array=[]
 var requested:bool=false;var follower_requested:bool=false;var blocked_head:bool=false;var no_overtake:bool=true;var together:bool=true;var board_ticks:Dictionary={};var previous:Dictionary={};var complete:bool=false;var steps:int=0
 FileAccess.open(stem+"-input.bin",FileAccess.WRITE).store_var(s.world.freeze(),false)
 for i:int in 2600:
  if not input_validation.is_empty():break
  suite._movement_tick(s);steps=i+1
  if not requested and c.riders.size()==7:
   requested=true
   for id:String in [patient,family]:
    var reason:String=s.space.request_move(s.world,id,3,goals[id])
    if not reason.is_empty():errors.append(reason)
   events.append({"tick":s.world.sim_tick,"event":"group_requested_after_seven_real_riders_before_final_boarding"})
  var line:Array=c.get("landing_queues",{}).get("2:1",[])
  if requested and not follower_requested and not line.is_empty() and line[0].actor_id==patient:
   follower_requested=true;s.space.request_move(s.world,"follower",3,goals.follower)
   events.append({"tick":s.world.sim_tick,"event":"follower_requested_after_actual_group_arrival"})
  if not line.is_empty() and line[0].actor_id==patient and int(c.floor_id)==2 and c.riders.size()==8:
   var fit:Dictionary=LiftController.placement(s.space,s.world,c,line[0])
   if not fit.ok and c.phase=="riding" and int(c.get("from",-1))==2 and int(c.get("to",-1))==3 and int(c.remaining_ticks)==HospitalTransit._travel_ticks(s.space,c,2,3) and c.get("waiting_reason","")==fit.reason and line.size()>1 and LiftController.placement(s.space,s.world,c,line[1]).ok:blocked_head=true;events.append({"tick":s.world.sim_tick,"event":"whole_head_does_not_fit","riders":c.riders.duplicate(),"queue":line.duplicate(true)})
  for id:String in goals:
   var location:Dictionary=s.world.facts.actors[id].location
   if location.kind!=previous.get(id,""):
    events.append({"tick":s.world.sim_tick,"actor":id,"location":location.duplicate(true),"riders":c.riders.duplicate()});previous[id]=location.kind
    if location.kind=="transit":board_ticks[id]=s.world.sim_tick
  if "follower" in c.riders and not board_ticks.has(patient):no_overtake=false
  if (patient in c.riders)!=(family in c.riders):together=false
  var validation:String=s.world.validate(suite.content)
  if not validation.is_empty():errors.append({"tick":s.world.sim_tick,"validation":validation})
  if i%10==0:trace.append({"tick":s.world.sim_tick,"connector":c.duplicate(true),"moves":s.world.facts.moves.duplicate(true),"actors":s.world.facts.actors.duplicate(true)})
  complete=goals.keys().all(func(id:String)->bool:return s.space.at(s.world,id,3,goals[id]) and not s.world.facts.moves.has(id))
  if complete or not errors.is_empty():break
  if i%100==99:print("FIFO_PROGRESS ",s.world.sim_tick);await process_frame
 var checks:Dictionary={"complete":complete,"input_valid":input_validation.is_empty(),"group_requested":requested,"follower_requested":follower_requested,"observed_insufficient_remainder":blocked_head,"no_overtake":no_overtake,"never_split":together,"same_board_tick":board_ticks.has(patient) and board_ticks.get(patient)==board_ticks.get(family),"follower_after_group":board_ticks.has("follower") and board_ticks.has(patient) and int(board_ticks.follower)>int(board_ticks[patient]),"valid":errors.is_empty()}
 var report:Dictionary={"ok":checks.values().all(func(v:bool)->bool:return v),"checks":checks,"commands":commands,"input_validation":input_validation,"errors":errors,"events":events,"board_ticks":board_ticks,"steps":steps,"scope":"Declared fixed patient/companion facts; only actual walking/FIFO/cabin/arrival, not full clinical workflow"}
 FileAccess.open(stem+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));FileAccess.open(stem+"-trace.json",FileAccess.WRITE).store_string(JSON.stringify(trace,"\t"));FileAccess.open(stem+"-final.bin",FileAccess.WRITE).store_var(s.world.freeze(),false)
 print(JSON.stringify({"ok":report.ok,"checks":checks,"errors":errors,"steps":steps}));s.dispose();quit(0 if report.ok else 1)
