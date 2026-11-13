extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var c:=HospitalContent.new();var f:=FileAccess.open("/tmp/ogh-mixed-visit-b87545e/r10-owner-fix.json.final.bin",FileAccess.READ);var e:Dictionary=f.get_var(false);f.close();var w:=WorldState.new(e.facts);var s:=HospitalSimulation.new(w,c);s.prepare_floor_static(1);var rows:Array=[];var errors:Array=[]
 for i:int in 200:
  s.step();var err:String=w.validate(c);var car:Dictionary=w.facts.connectors.benchmark_lift
  rows.append({"tick":w.sim_tick,"phase":car.phase,"riders":car.riders.duplicate(),"direction":car.get("direction",0),"groups":car.get("passenger_groups",[]).duplicate(true),"queues":car.get("landing_queues",{}).duplicate(true),"error":err})
  if not err.is_empty():errors.append(err);break
 f=FileAccess.open("/workspace/scratch/6962cc21ddf3/lift-controller-smoke.json",FileAccess.WRITE);f.store_string(JSON.stringify({"errors":errors,"rows":rows},"\t"));f.close();s.dispose();quit(0 if errors.is_empty() else 1)
