extends SceneTree
const Family=preload("res://tests/acceptance/inpatient_family.gd")
var helper=Family.new()
var output:String
func _initialize()->void:call_deferred("run")
func save_state(name:String,facts:Dictionary)->void:
 FileAccess.open(output.path_join(name+".bin"),FileAccess.WRITE).store_var(facts,false)
func returned(c:Dictionary)->bool:
 var ward:Dictionary=helper._stay(c);var actor:Dictionary=c.world.facts.actors[helper._visit(c).actor_id]
 return ward.phase=="recovery" and actor.posture=="lying" and actor.get("support_facility_id","")==ward.bed_id and not c.world.facts.moves.has(actor.id)
func phase(c:Dictionary)->String:
 var patient:String=helper._visit(c).actor_id
 for lift:Dictionary in c.world.facts.connectors.values():
  for g:Dictionary in lift.get("passenger_groups",[]):
   if not patient in g.members or int(g.to)!=2:continue
   var nursing:bool=g.leader_ids.any(func(id:String)->bool:return c.world.facts.moves.get(id,{}).has("convoy"))
   if not nursing:continue
   if not g.get("pending_boarding",[]).is_empty():return "family_pending_outside"
   if lift.phase=="boarding" and g.members.size()==3:return "family_boarding"
   if lift.phase=="idle" and g.members.size()==3:return "loaded_idle"
   if lift.phase=="riding" and g.members.size()==3:return "riding"
   if g.get("exit_stage","")=="companions":return "family_exits_first"
   if lift.phase=="alighting" and g.members.size()==2:return "nursing_exits_after_family"
 return ""
func run()->void:
 var args:=OS.get_cmdline_user_args()
 if args.size()<1:quit(2);return
 output=args[0];DirAccess.make_dir_recursive_absolute(output)
 helper._content=HospitalContent.new()
 var original:Dictionary=FileAccess.open("/workspace/scratch/6962cc21ddf3/clinical-lift-r6/clinical-start.bin",FileAccess.READ).get_var(false)
 var c:Dictionary=helper._copy_facts(original,"visit_00000006")
 var errors:Array=[];var snapshots:Dictionary={};var done:bool=false
 var declarations:Array=[]
 if args.size()>1 and args[1]=="VC02":
  var old_id:String=str(c.world.facts.connectors.keys()[0])
  var build:CommandResult=helper._command(c,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[80,68],"rotation":0})
  if not build.accepted:errors.append(build.to_record())
  if build.accepted:
   var extend:CommandResult=helper._command(c,"connector_extend",{"connection_id":str(build.changed_ids[0]),"floor_id":2})
   if not extend.accepted:errors.append(extend.to_record())
  if errors.is_empty():
   var remove:CommandResult=helper._command(c,"connector_remove",{"connection_id":old_id})
   if not remove.accepted:errors.append(remove.to_record())
  declarations.append({"independent_input":"Real remove/build/extend before replay; VC02 replaces VC03 at clear site; same people, bodies, RNG and clinical obligations","no_performance_comparison":true})
 save_state("actual-input",c.world.freeze())
 for i:int in 6000:
  if not errors.is_empty():break
  helper._tick(c)
  var error:String=c.world.validate(helper._content)
  if not error.is_empty():errors.append(error);break
  var key:String=phase(c)
  if not key.is_empty() and not snapshots.has(key):snapshots[key]=c.world.freeze();save_state(key,snapshots[key])
  if returned(c):done=true;break
  if i%100==99:print("PARTIAL_COLD_PROGRESS ",c.world.sim_tick);await process_frame
 var reference:Dictionary=c.world.freeze();save_state("original-final",reference)
 var details:Array=[]
 if done:
  for key:String in snapshots:
   var restored:Dictionary=helper._copy_facts(snapshots[key],"visit_00000006")
   var exact:bool=restored.world.freeze()==snapshots[key];var finished:bool=false;var failure:String=""
   for i:int in 1200:
    helper._tick(restored);failure=restored.world.validate(helper._content)
    if not failure.is_empty():break
    if returned(restored):finished=true;break
    if i%100==99:await process_frame
   save_state(key+"-restored-final",restored.world.freeze())
   details.append({"phase":key,"exact_restore":exact,"true_bed_return":finished,"validation":failure,"same_final":restored.world.freeze()==reference,"tick":restored.world.sim_tick})
 var report:Dictionary={"ok":done and errors.is_empty() and snapshots.size()==6 and details.all(func(d:Dictionary)->bool:return d.exact_restore and d.true_bed_return and d.validation.is_empty() and d.same_final),"true_bed_return":done,"phases":snapshots.keys(),"errors":errors,"details":details,"final_ward":helper._stay(c),"declarations":declarations,"scope":"Declared clinical input, full real return-to-bed; not mixed160 or performance comparison"}
 FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 helper._dispose_simulations();print(JSON.stringify(report));quit(0 if report.ok else 1)
