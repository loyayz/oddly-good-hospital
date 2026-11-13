extends SceneTree
# Independent declared spatial input, not a clinical admission/return-to-bed
# benchmark. A registered patient and companion keep fixed species/bodies;
# actual movement, queue arrival, boarding and exits are never fabricated.
const Cases=preload("res://tests/acceptance/space.gd")
var suite=Cases.new()
func _initialize()->void:call_deferred("run")
func run()->void:
 suite.content=HospitalContent.new()
 var args:=OS.get_cmdline_user_args();var stem:String=args[0] if not args.is_empty() else "/tmp/group-journey"
 var s:HospitalSimulation=suite._fixture();suite._history_height(s,2)
 var commands:Array=[]
 commands.append(suite._command(s,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[36,72]}).to_record())
 var small:String=suite._connection(s)
 commands.append(suite._command(s,"connector_build",{"definition_id":"VC03","floor_id":1,"cell":[51,72]}).to_record())
 var big:String=""
 for cid:String in s.world.ids("connectors"):
  if cid!=small:big=cid
  commands.append(suite._command(s,"connector_extend",{"connection_id":cid,"floor_id":2}).to_record())
 var binding:String=""
 for b:Dictionary in suite.content.catalog.treatment_bindings:
  if b.species_id=="S28":binding=b.id;break
 var visit:Dictionary=suite._waiting_visit(s,"group_patient",[40,82],binding)
 var patient:String=visit.actor_id;var companion:String="group_companion"
 suite._add_actor(s,companion,"S28",[40,85],1);s.world.facts.actors[companion].relative_of=patient
 s.world.facts.visitors={"next_scan_tick":s.world.sim_tick,"requests":{},"stays":{"group_family":{"id":"group_family","visit_id":visit.id,"actor_id":companion,"purpose":"companion","phase":"walking","remaining_ticks":0,"life_task":{},"return_ward_first":false,"yielding":false,"destination":{},"waiting_floor":1,"waiting_cell":[40,85],"next_need_tick":s.world.sim_tick+10000,"next_purpose":"water"}}}
 var targets:Dictionary={patient:[40,82],companion:[43,85]}
 var requests:Array=[]
 for id:String in targets:requests.append(s.space.request_move(s.world,id,2,targets[id]))
 var input_validation:String=s.world.validate(suite.content)
 FileAccess.open(stem+"-input.bin",FileAccess.WRITE).store_var(s.world.freeze(),false)
 var initial_obligations:Dictionary={}
 for id:String in targets:
  var m:Dictionary=s.world.facts.moves[id];initial_obligations[id]=[m.target_floor,m.target_cell.duplicate(),m.request_sequence]
 var errors:Array=[];var trace:Array=[];var saw_small:bool=false;var saw_reroute:bool=false;var shared_big:bool=false;var completed:bool=false;var steps:int=0
 for i:int in 1800:
  if not input_validation.is_empty() or not commands.all(func(r:Dictionary)->bool:return r.accepted):break
  suite._movement_tick(s);steps=i+1
  var v:String=s.world.validate(suite.content)
  if not v.is_empty():errors.append({"tick":s.world.sim_tick,"validation":v});break
  var c:Dictionary=s.world.facts.connectors[big]
  if patient in c.riders and companion in c.riders:shared_big=true
  for id:String in targets:
   var m:Dictionary=s.world.facts.moves.get(id,{})
   if m.is_empty():continue
   if [m.target_floor,m.target_cell,m.request_sequence]!=initial_obligations[id]:errors.append({"tick":s.world.sim_tick,"changed_obligation":id})
   if HospitalTransit.journey(m).get("connector_id","")==small:saw_small=true
   if small in m.get("route_filter",{}).get("excluded_connectors",[]):saw_reroute=true
  if i%10==0:trace.append({"tick":s.world.sim_tick,"actors":{patient:s.world.facts.actors[patient].duplicate(true),companion:s.world.facts.actors[companion].duplicate(true)},"moves":s.world.facts.moves.duplicate(true),"connectors":s.world.facts.connectors.duplicate(true)})
  completed=targets.keys().all(func(id:String)->bool:return s.space.at(s.world,id,2,targets[id]) and not s.world.facts.moves.has(id))
  if completed or not errors.is_empty():break
  if i%100==99:print("GROUP_PROGRESS ",s.world.sim_tick);await process_frame
 var report:Dictionary={"ok":completed and saw_small and saw_reroute and shared_big and errors.is_empty() and input_validation.is_empty(),"completed":completed,"saw_original_small_trip":saw_small,"saw_group_filter":saw_reroute,"both_physically_in_big_car":shared_big,"steps":steps,"errors":errors,"input_validation":input_validation,"commands":commands,"requests":requests,"patient_binding":binding,"scope":"Declared patient/companion spatial contract; real walking/FIFO/boarding/alighting; no full clinical admission claim"}
 FileAccess.open(stem+"-trace.json",FileAccess.WRITE).store_string(JSON.stringify(trace,"\t"))
 FileAccess.open(stem+"-final.bin",FileAccess.WRITE).store_var(s.world.freeze(),false)
 FileAccess.open(stem+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print(JSON.stringify(report));s.dispose();quit(0 if report.ok else 1)
