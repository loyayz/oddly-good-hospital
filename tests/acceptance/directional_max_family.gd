extends SceneTree
const Base=preload("res://tests/acceptance/directional_max_group.gd")
var base=Base.new()
func _initialize()->void:call_deferred("run")
func run()->void:
 var args:=OS.get_cmdline_user_args();var output:String=args[0]
 base.wide_input=true;base.lift_cell=[48,40]
 var c:Dictionary=base.prepare();var s:HospitalSimulation=c.sim;var content:HospitalContent=base.suite.content
 # Independent maximal-body transport boundary. A declared visit/relative
 # relationship and their existing equal-floor travel obligations drive the
 # production landing grouping; no queued/onboard snapshots are fabricated.
 var binding:Dictionary={}
 for item:Dictionary in content.catalog.treatment_bindings:
  if item.species_id=="S63":binding=item;break
 var v:Dictionary=base.suite._waiting_visit(s,"transport",[80,50],binding.id)
 s.world.facts.actors.erase(v.actor_id)
 v.actor_id="max_patient";s.world.facts.actors.max_patient.body_binding_id=binding.id
 base.suite._add_actor(s,"max_family","S63",[65,50])
 s.world.facts.actors.max_family.relative_of="max_patient"
 s.world.facts.visitors={"next_scan_tick":0,"requests":{},"stays":{"relative":{"id":"relative","visit_id":v.id,"actor_id":"max_family","purpose":"companion","phase":"walking","remaining_ticks":0,"life_task":{},"return_ward_first":false,"yielding":false}}}
 s.world.touch()
 var reason:String=s.space.movement.request_move(s.world,"max_family",2,[65,50])
 var errors:Array=[]
 if not reason.is_empty():errors.append(reason)
 var initial:String=s.world.validate(content)
 if not initial.is_empty():errors.append(initial)
 FileAccess.open(output+".input.bin",FileAccess.WRITE).store_var(s.world.freeze(),false)
 FileAccess.open(output+".metadata.json",FileAccess.WRITE).store_string(JSON.stringify({"targets":{"max_nurse":{"floor_id":2,"cell":c.target},"max_family":{"floor_id":2,"cell":[65,50]}},"scope":"Independent max three-body ground-to-ground transport"}))
 var stages:Dictionary={};var done:bool=false
 for i:int in 3200:
  if not errors.is_empty():break
  base.step(c)
  var error:String=s.world.validate(content)
  if not error.is_empty():errors.append({"tick":s.world.sim_tick,"error":error});break
  var lift:Dictionary=s.world.facts.connectors[c.connector_id]
  for g:Dictionary in lift.get("passenger_groups",[]):
   for id:String in g.get("companion_portals",{}):
    var p:Dictionary=g.companion_portals[id]
    var label:String="family_"+str(p.stage)
    if int(p.cursor)>0 and not stages.has(label):stages[label]=s.world.sim_tick;FileAccess.open(output+"."+label+".bin",FileAccess.WRITE).store_var(s.world.freeze(),false)
  if base.complete(c) and s.space.at(s.world,"max_family",2,[65,50]) and not s.world.facts.moves.has("max_family"):done=true;break
  if i%100==99:print("MAX_FAMILY ",s.world.sim_tick," ",lift.phase," ",lift.get("waiting_reason",""));await process_frame
 var result:Dictionary={"ok":done and errors.is_empty() and stages.size()==2,"completed":done,"errors":errors,"stages":stages,"tick":s.world.sim_tick,"moves":s.world.facts.moves,"lift":s.world.facts.connectors[c.connector_id],"scope":"Independent max same-species patient+family nursing transport, production queue grouping; not clinical or performance acceptance"}
 FileAccess.open(output+".final.bin",FileAccess.WRITE).store_var(s.world.freeze(),false)
 FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
 s.dispose();base.free();print(JSON.stringify({"ok":result.ok,"errors":errors,"stages":stages,"tick":result.tick}));quit(0 if result.ok else 1)
