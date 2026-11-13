extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var e:Dictionary=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.READ).get_var()
 var w:=WorldState.new(e.facts)
 var content:=HospitalContent.new()
 var sim:=HospitalSimulation.new(w,content)
 for i in 6:
  print("BEFORE ",JSON.stringify({"tick":w.sim_tick,"actor":w.facts.actors["bench_patient_0048"],"move":w.facts.moves["bench_patient_0048"]}))
  sim.step()
 sim.dispose()
 quit()
