extends SceneTree
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	var a:=OS.get_cmdline_user_args();var out: String=a[1]
	var f:=FileAccess.open(a[2],FileAccess.READ);var facts: Dictionary=f.get_var(false);f.close()
	var nearby: Dictionary={};var moves: Dictionary={}
	for id: String in facts.actors:
		var actor: Dictionary=facts.actors[id];var loc: Dictionary=actor.location
		if id in ["maintenance_contractor_00000226","bench_patient_0115"] or loc.kind=="floor" and int(loc.floor_id)==1 and absf(float(loc.cell[0])-86)<10 and absf(float(loc.cell[1])-44)<10:
			nearby[id]=actor;moves[id]=facts.moves.get(id,{})
	var result: Dictionary={"tick":facts.sim_tick,"actors":nearby,"moves":moves,"lift":facts.connectors.benchmark_lift,"maintenance":facts.maintenance,"visits":facts.visits,"staff":facts.staff,"waiting_life":facts.waiting_life,"adaptations":facts.adaptations,"floor_guidance":facts.get("floor_guidance",{})}
	var o:=FileAccess.open(out+"/decoded.json",FileAccess.WRITE);o.store_string(JSON.stringify(result,"\t"));o.close()
	if a[0]=="step":
		var world:=WorldState.new(facts);var content:=HospitalContent.new();var sim:=HospitalSimulation.new(world,content)
		var exact: bool=world.freeze()==facts
		var tick: TickResult=sim.step();var events: Array=[]
		for event: SimEvent in tick.facts:events.append(event.to_record())
		o=FileAccess.open(out+"/final.bin",FileAccess.WRITE);o.store_var({"facts":world.freeze(),"events":events},false);o.close()
		o=FileAccess.open(out+"/result.json",FileAccess.WRITE);o.store_string(JSON.stringify({"cold_restore_exact":exact,"tick":world.sim_tick,"events":events}));o.close();sim.dispose()
	quit(0)
