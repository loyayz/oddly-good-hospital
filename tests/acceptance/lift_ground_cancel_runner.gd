extends SceneTree
const Cases=preload("res://tests/acceptance/space.gd")
var suite=Cases.new()
var rows:Array=[]
func _initialize()->void:call_deferred("run")
func restored(facts:Dictionary)->HospitalSimulation:return HospitalSimulation.new(WorldState.new(facts.duplicate(true)),suite.content)
func row(name:String,checks:Dictionary,details:Dictionary={})->void:
 rows.append({"name":name,"passed":checks.values().all(func(v:bool)->bool:return v),"checks":checks,"details":details})
func ordinary(grouped:bool)->void:
 var s:HospitalSimulation=suite._transit_fixture()
 var patient:String="single"
 if grouped:
  var v:Dictionary=suite._waiting_visit(s,"cancel_patient",[42,82]);patient=v.actor_id
  suite._add_actor(s,"companion","S49",[44,82])
  s.world.facts.actors.companion.relative_of=patient
  s.world.facts.visitors={"next_scan_tick":0,"requests":{},"stays":{"family":{"id":"family","visit_id":v.id,"actor_id":"companion","purpose":"companion","phase":"walking","remaining_ticks":0,"life_task":{},"return_ward_first":false,"yielding":false}}}
 else:suite._add_actor(s,patient,"S49",[42,82])
 s.space.request_move(s.world,patient,2,[46,82])
 if grouped:s.space.request_move(s.world,"companion",2,[48,82])
 var cid:String=suite._connection(s);var found:bool=false
 for i:int in 800:
  suite._movement_tick(s)
  for line:Array in s.world.facts.connectors[cid].get("landing_queues",{}).values():
   for entry:Dictionary in line:
    if entry.actor_id==patient and (not grouped or entry.get("leader_ids",[]).size()==2):found=true
  if found:break
 if not found:row("group" if grouped else "single",{"captured_real_queue":false});s.dispose();return
 var before:Dictionary=s.world.freeze()
 for who:String in [patient,"companion"] if grouped else [patient]:
  var w:HospitalSimulation=restored(before)
  var body_before:Dictionary=w.world.facts.actors.duplicate(true)
  var others:Array=[]
  for line:Array in w.world.facts.connectors[cid].landing_queues.values():
   for entry:Dictionary in line:
    if not who in entry.get("leader_ids",[entry.actor_id]):others.append(entry.duplicate(true))
  var okay:bool=w.space.cancel_ground_move(w.world,who)
  var remains:Array=[]
  for line:Array in w.world.facts.connectors[cid].landing_queues.values():remains.append_array(line)
  var after:Dictionary=w.world.freeze()
  var valid:String=w.world.validate(suite.content)
  var duplicate:bool=w.space.cancel_ground_move(w.world,who) and w.world.freeze()==after
  var cold:HospitalSimulation=restored(after)
  var sibling:String=patient if who=="companion" else "companion"
  var cleaned:bool=true
  if grouped:
   var m:Dictionary=w.world.facts.moves.get(sibling,{})
   cleaned=not m.is_empty() and not m.has("lift_queue_target") and not m.has("lift_queue_wait_basis") and not m.has("lift_boarding_call") and not m.has("lift_queue_standby")
  row(("group_" if grouped else "single_")+who,{"captured_real_queue":true,"input_valid":WorldState.new(before).validate(suite.content).is_empty(),"cancelled":okay,"movement_removed":not w.world.facts.moves.has(who),"whole_row_removed_other_fifo_unchanged":remains==others,"other_owner_markers_released":cleaned,"no_body_motion":w.world.facts.actors==body_before,"immediate_valid":valid.is_empty(),"repeat_idempotent":duplicate,"same_boundary_cold_valid":cold.world.validate(suite.content).is_empty() and cold.world.freeze()==after},{"tick":w.world.sim_tick,"validation":valid})
  cold.dispose();w.dispose()
 # The same original actual queue must still board normally when not cancelled.
 var aboard:bool=false
 for i:int in 800:
  suite._movement_tick(s)
  if s.world.facts.actors[patient].location.kind=="transit":aboard=true;break
 var committed:Dictionary=s.world.freeze()
 row("accepted_group" if grouped else "accepted_single",{"real_boarding":aboard,"cancel_denied":aboard and not s.space.cancel_ground_move(s.world,patient),"failure_atomic":s.world.freeze()==committed,"valid":s.world.validate(suite.content).is_empty()})
 s.dispose()
func pending_family()->void:
 var base=load("res://tests/acceptance/directional_max_group.gd").new()
 base.wide_input=true;base.lift_cell=[48,40]
 var c:Dictionary=base.prepare();var s:HospitalSimulation=c.sim
 var binding:Dictionary={}
 for b:Dictionary in suite.content.catalog.treatment_bindings:
  if b.species_id=="S63":binding=b;break
 var v:Dictionary=base.suite._waiting_visit(s,"pending_cancel",[80,50],binding.id)
 s.world.facts.actors.erase(v.actor_id);v.actor_id="max_patient";s.world.facts.actors.max_patient.body_binding_id=binding.id
 base.suite._add_actor(s,"max_family","S63",[65,50]);s.world.facts.actors.max_family.relative_of="max_patient"
 s.world.facts.visitors={"next_scan_tick":0,"requests":{},"stays":{"relative":{"id":"relative","visit_id":v.id,"actor_id":"max_family","purpose":"companion","phase":"walking","remaining_ticks":0,"life_task":{},"return_ward_first":false,"yielding":false}}}
 s.world.touch();s.space.request_move(s.world,"max_family",2,[65,50])
 var found:bool=false
 for i:int in 1800:
  base.step(c)
  if LiftController.pending_holds(s.world,"max_family"):found=true;break
 var before:Dictionary=s.world.freeze()
 var denied:bool=found and not s.space.cancel_ground_move(s.world,"max_family")
 var cold:HospitalSimulation=restored(before)
 var cold_before:Dictionary=cold.world.freeze()
 var cold_denied:bool=found and not cold.space.cancel_ground_move(cold.world,"max_family")
 row("accepted_pending_family_on_floor",{"captured_actual_pending":found,"on_floor":s.world.facts.actors.max_family.location.kind=="floor","cancel_denied":denied,"failure_atomic":s.world.freeze()==before,"cold_cancel_denied":cold_denied,"cold_failure_atomic":cold.world.freeze()==cold_before,"cold_manifest_retained":cold.world.facts.connectors[c.connector_id]==before.connectors[c.connector_id],"valid":s.world.validate(suite.content).is_empty()},{"tick":s.world.sim_tick})
 cold.dispose();s.dispose();base.free()
func run()->void:
 suite.content=HospitalContent.new()
 var args:PackedStringArray=OS.get_cmdline_user_args()
 if args.size()<2 or args[1]=="ordinary":ordinary(false);ordinary(true)
 if args.size()<2 or args[1]=="pending":pending_family()
 var result:Dictionary={"passed":rows.all(func(r:Dictionary)->bool:return r.passed),"rows":rows,"scope":"Actual queue/boarding boundaries; immediate cancellation ownership and cold world reconstruction. Not full clinical/performance acceptance."}
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
 print(JSON.stringify(result));quit(0 if result.passed else 1)
