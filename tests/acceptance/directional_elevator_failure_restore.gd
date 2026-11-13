extends SceneTree
const Cases=preload("res://tests/acceptance/space.gd")
var suite=Cases.new()
func _initialize()->void:call_deferred("run")
func run()->void:
 suite.content=HospitalContent.new();var args:=OS.get_cmdline_user_args();var source:String=args[0];var out:String=args[1]
 var before:Dictionary=FileAccess.open(source+"-before-scan.bin",FileAccess.READ).get_var(true)
 var pending:Dictionary=FileAccess.open(source+"-after-scan.bin",FileAccess.READ).get_var(true)
 var expected:Dictionary=FileAccess.open(source+"-final.bin",FileAccess.READ).get_var(true)
 var before_world:=WorldState.new(before.duplicate(true));var before_exact:bool=before_world.freeze()==before
 var bs:=HospitalSimulation.new(before_world,suite.content);var initial_before_validation:String=before_world.validate(suite.content)
 bs.services.maintenance.boundaries(before_world);var same_natural_scan:bool=before_world.freeze()==pending;bs.dispose()
 var world:=WorldState.new(pending.duplicate(true));var exact:bool=world.freeze()==pending;var s:=HospitalSimulation.new(world,suite.content);var c:Dictionary=world.facts.connectors[suite._connection(s)]
 var initial_validation:String=world.validate(suite.content);var initial_connector:Dictionary=c.duplicate(true);var errors:Array=[];var complete:bool=false
 for i:int in 1200:
  suite._movement_tick(s);s.services.maintenance.boundaries(world)
  var error:String=world.validate(suite.content)
  if not error.is_empty():errors.append(error);break
  complete=s.space.at(world,"near",2,[45,82]) and s.space.at(world,"far",3,[48,82]) and not world.facts.moves.has("near") and not world.facts.moves.has("far")
 var report:Dictionary={"restore_integrity_ok":before_exact and exact and same_natural_scan and initial_before_validation.is_empty() and initial_validation.is_empty() and errors.is_empty(),"safety_destination_ok":complete,"before_scan_exact":before_exact,"same_natural_scan":same_natural_scan,"pending_restore_exact":exact,"initial_before_validation":initial_before_validation,"initial_pending_validation":initial_validation,"initial_connector":initial_connector,"continued_steps":1200,"same_failure_final_state":world.freeze()==expected,"completed_original_destinations":complete,"final_connector":c.duplicate(true),"errors":errors,"scope":"Exact cold restoration of actual loaded-idle before/after natural RNG failure; integrity does not imply safe arrival"}
 FileAccess.open(out+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));FileAccess.open(out+"-final.bin",FileAccess.WRITE).store_var(world.freeze(),true);print(JSON.stringify(report));s.dispose();quit(0 if report.restore_integrity_ok and complete else 1)
