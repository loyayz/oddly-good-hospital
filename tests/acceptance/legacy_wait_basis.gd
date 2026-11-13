extends SceneTree
# Diagnostic ONLY: load an unedited previous-algorithm failure snapshot.
# Does not erase/change basis, relocate actors, or replace production routing.
const Cases=preload("res://tests/acceptance/space.gd")
var suite=Cases.new()
func _initialize()->void:call_deferred("run")
func run()->void:
 var args:=OS.get_cmdline_user_args()
 if args.size()!=2:push_error("Expected old raw failed snapshot and output JSON");quit(2);return
 var content:=HospitalContent.new();suite.content=content
 var facts:Dictionary=FileAccess.open(args[0],FileAccess.READ).get_var(false)
 var s:=HospitalSimulation.new(WorldState.new(facts.duplicate(true)),content)
 var errors:Array=[];var initial_validation:String=s.world.validate(content)
 if not initial_validation.is_empty():errors.append(initial_validation)
 var before:Dictionary=s.world.freeze();var rows:Array=[]
 for connection:Dictionary in s.world.facts.connectors.values():
  for group:Dictionary in LiftLandingQueue._groups(s.world,connection.id).values():
   var floor_id:int=int(group.floor_id)
   var key:String=LiftLandingQueue._key(floor_id,int(group.direction))
   var predecessors:Array=[];var occupied:Array=[]
   for entry:Dictionary in connection.get("landing_queues",{}).get(key,[]):predecessors.append(entry.actor_id)
   # This old fixture has no registered entries on any floor; fail diagnostic
   # rather than assume an empty occupancy basis for a different input.
   for line:Array in connection.get("landing_queues",{}).values():
    if not line.is_empty():errors.append("Diagnostic requires original empty queues")
   var basis:Array=[LiftLandingQueue.LAYOUT_VERSION,s.space._navigation.floor_static_version(s.space,s.world,floor_id),predecessors,group.leader_ids.duplicate(),group.members.duplicate(),LiftLandingQueue._identity(s.world,str(connection.id),group)]
   var movement:Dictionary=s.world.facts.moves[group.actor_id]
   var slots:Dictionary=LiftLandingQueue._group_slots(s.space,s.world,connection,group,occupied,false)
   rows.append({"leader":group.actor_id,"saved_basis":movement.get("lift_queue_wait_basis",[]),"current_basis":basis,"basis_equal":movement.get("lift_queue_wait_basis",[])==basis,"has_standby":movement.has("lift_queue_standby"),"recomputed_slots":slots})
 var readonly_unchanged:bool=before==s.world.freeze()
 var start_tick:int=s.world.sim_tick
 var locations:Dictionary={}
 for id:String in s.world.facts.actors:locations[id]=s.world.facts.actors[id].location.duplicate(true)
 var initial_moves:Dictionary=s.world.facts.moves.duplicate(true)
 var any_queued:bool=false;var any_boarded:bool=false
 for i:int in 400:
  if not errors.is_empty():break
  suite._movement_tick(s)
  var err:String=s.world.validate(content)
  if not err.is_empty():errors.append(err);break
  for connection:Dictionary in s.world.facts.connectors.values():
   any_boarded=any_boarded or not connection.get("passenger_groups",[]).is_empty()
   for line:Array in connection.get("landing_queues",{}).values():any_queued=any_queued or not line.is_empty()
  if i%100==99:await process_frame
 var locations_same:bool=true
 for id:String in locations:locations_same=locations_same and locations[id]==s.world.facts.actors[id].location
 var after:Dictionary=s.world.freeze()
 var current_restore:=HospitalSimulation.new(WorldState.new(after.duplicate(true)),content)
 var report:Dictionary={"scope":"Old pre-fix failed-save compatibility diagnostic, NOT current clean-generation cold acceptance","input_sha256":FileAccess.get_sha256(args[0]),"initial_validation":initial_validation,"errors":errors,"readonly_facts_unchanged":readonly_unchanged,"rows":rows,"observed_ticks":s.world.sim_tick-start_tick,"any_queued":any_queued,"any_boarded":any_boarded,"locations_same":locations_same,"moves_same":initial_moves==s.world.facts.moves,"unchanged_current_serialization":current_restore.world.freeze()==after,"current_restore_validation":current_restore.world.validate(content)}
 FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 current_restore.dispose();s.dispose();print(JSON.stringify(report));quit(0 if errors.is_empty() and readonly_unchanged else 1)
