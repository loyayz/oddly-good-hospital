extends SceneTree
# Independent spatial handoff restoration proof. Inputs must come from the
# declared actual max-body journey fixture, never constructed transit facts.
const Cases=preload("res://tests/acceptance/space.gd")
const LIMIT:int=4000
var suite=Cases.new()
var content:HospitalContent
var output:String
func _initialize()->void:call_deferred("run")
func save_facts(name:String,facts:Dictionary)->void:
 FileAccess.open(output.path_join(name+".bin"),FileAccess.WRITE).store_var(facts,false)
func finished(s:HospitalSimulation,targets:Dictionary)->bool:
 return targets.keys().all(func(id:String)->bool:return s.space.at(s.world,id,int(targets[id].floor_id),targets[id].cell) and not s.world.facts.moves.has(id))
func stages(s:HospitalSimulation)->Array[String]:
 var result:Array[String]=[]
 for lift:Dictionary in s.world.facts.connectors.values():
  for group:Dictionary in lift.get("passenger_groups",[]):
   for portal:Dictionary in group.get("companion_portals",{}).values():
    var cursor:int=int(portal.cursor)
    var frames:Array=portal.plan[portal.stage]
    if cursor>0 and cursor<frames.size():result.append("family_"+str(portal.stage)+"_partial")
    if cursor==frames.size():result.append("family_"+str(portal.stage)+"_complete")
 for move:Dictionary in s.world.facts.moves.values():
  var portal:Dictionary=move.get("convoy",{}).get("portal",{})
  var plan:Dictionary=portal.get("plan",{})
  if plan.get("mode","")!="articulated":continue
  var actor:Dictionary=s.world.facts.actors[move.actor_id]
  if actor.location.kind!="transit":continue
  var c:Dictionary=s.world.facts.connectors[actor.location.connector_id]
  if c.phase in ["idle","riding"]:result.append("convoy_"+c.phase);continue
  var stage:String=str(portal.get("stage",""))
  var frames:Array=plan.get(stage,[])
  var cursor:int=int(portal.get("cursor",0))
  if not frames.is_empty():
   var frame:Dictionary=frames[clampi(cursor-1,0,frames.size()-1)]
   result.append(stage+"_"+str(frame.get("moving_actor_id",move.actor_id)))
   if cursor>=frames.size():result.append(stage+"_complete")
 return result
func invalid_loaded_idle(facts:Dictionary)->Dictionary:
 var changed:Dictionary=facts.duplicate(true);var changed_owner:String=""
 for move:Dictionary in changed.moves.values():
  var portal:Dictionary=move.get("convoy",{}).get("portal",{})
  var plan:Dictionary=portal.get("plan",{})
  if plan.get("mode","")!="articulated":continue
  portal.cursor=0
  for id:String in move.members:
   changed.actors[id].location.queue_cell=plan.initial_poses[id].cell.duplicate()
   changed.actors[id].facing=plan.initial_poses[id].facing
  changed_owner=move.actor_id;break
 var bad:=HospitalSimulation.new(WorldState.new(changed),content)
 var reason:String=bad.world.validate(content);bad.dispose()
 return {"owner":changed_owner,"rejected":not changed_owner.is_empty() and not reason.is_empty(),"reason":reason,"scope":"Consistent initial handoff poses illegally substituted into actual loaded-idle snapshot"}
func run()->void:
 var args:=OS.get_cmdline_user_args()
 if args.size()!=3:push_error("Expected raw input facts, target metadata JSON, fresh output directory");quit(2);return
 output=args[2]
 if DirAccess.dir_exists_absolute(output):push_error("Output already exists");quit(2);return
 DirAccess.make_dir_recursive_absolute(output)
 content=HospitalContent.new();suite.content=content
 var facts:Dictionary=FileAccess.open(args[0],FileAccess.READ).get_var(false)
 var meta:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1]))
 var targets:Dictionary=meta.targets
 var s:=HospitalSimulation.new(WorldState.new(facts.duplicate(true)),content)
 var initial_error:String=s.world.validate(content)
 var errors:Array=[];var snapshots:Dictionary={};var complete:bool=false
 if not initial_error.is_empty():errors.append(initial_error)
 save_facts("input",s.world.freeze())
 for i:int in LIMIT:
  if not errors.is_empty():break
  suite._movement_tick(s)
  var error:String=s.world.validate(content)
  if not error.is_empty():errors.append({"tick":s.world.sim_tick,"validation":error});break
  for key:String in stages(s):
   if not snapshots.has(key):snapshots[key]=s.world.freeze();save_facts(key,snapshots[key])
  if finished(s,targets):complete=true;break
  if i%100==99:print("MAX_COLD_PROGRESS ",s.world.sim_tick);await process_frame
 var final:Dictionary=s.world.freeze();save_facts("original-final",final);s.dispose()
 var details:Array=[]
 if complete:
  for key:String in snapshots:
   var restored:=HospitalSimulation.new(WorldState.new(snapshots[key].duplicate(true)),content)
   var exact:bool=restored.world.freeze()==snapshots[key]
   var validation:String=restored.world.validate(content);var done:bool=false
   for i:int in LIMIT:
    if not validation.is_empty():break
    suite._movement_tick(restored);validation=restored.world.validate(content)
    if finished(restored,targets):done=true;break
    if i%100==99:await process_frame
   save_facts(key+"-restored-final",restored.world.freeze())
   details.append({"stage":key,"exact_restore":exact,"completed":done,"validation":validation,"same_final":restored.world.freeze()==final,"tick":restored.world.sim_tick})
   restored.dispose()
 var negative:Dictionary=invalid_loaded_idle(snapshots.convoy_idle) if snapshots.has("convoy_idle") else {"rejected":false,"reason":"No real loaded-idle snapshot"}
 var report:Dictionary={"negative_loaded_idle":negative,"ok":negative.rejected and complete and errors.is_empty() and snapshots.size()>=6 and details.all(func(d:Dictionary)->bool:return d.exact_restore and d.completed and d.validation.is_empty() and d.same_final),"completed":complete,"errors":errors,"initial_validation":initial_error,"stages":snapshots.keys(),"details":details,"metadata":meta,"step_bound":LIMIT,"input_sha256":FileAccess.get_sha256(args[0]),"scope":"Actual max-body spatial handoff and complete raw-facts cold replay; not clinical treatment or performance proof"}
 FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print(JSON.stringify(report));quit(0 if report.ok else 1)
