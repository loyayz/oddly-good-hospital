extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var e: Dictionary=FileAccess.open(args[0],FileAccess.READ).get_var()
	var content:=HospitalContent.new()
	var w:=WorldState.new(e.facts)
	var sim:=HospitalSimulation.new(w,content)
	sim.services.experience.sample_workers_enabled=true
	sim.services.experience.sample_worker_tasks=4
	var operations=load("res://tools/performance/current/comprehensive_operations.gd").new()
	for key: String in w.facts.command_receipts:
		if key.begins_with(operations.PREFIX): operations.submitted[key.trim_prefix(operations.PREFIX)]={}
	var initial: int=w.sim_tick
	var errors: Array=[]
	var before_validation: String=w.validate(content)
	var log: FileAccess=FileAccess.open(args[1]+".steps.ndjson",FileAccess.WRITE)
	for index: int in 200:
		operations.enqueue(sim,int(e.completed_steps)+index-1000)
		log.store_line(JSON.stringify({"enter":w.sim_tick}));log.flush()
		var tick: TickResult=sim.step()
		if tick==null: errors.append("null tick");break
		log.store_line(JSON.stringify({"complete":w.sim_tick}));log.flush()
	var result: Dictionary={"initial_tick":initial,"final_tick":w.sim_tick,"completed_steps":w.sim_tick-initial,"initial_validation":before_validation,"final_validation":w.validate(content),"errors":errors,"restored_submitted_command_keys":operations.submitted.keys(),"scope":"200 real production steps from failed run checkpoint, cold runtime, original ongoing commands reconstructed from receipts. Not a performance sample or full coverage proof."}
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));sim.dispose();quit(0 if errors.is_empty() else 1)
