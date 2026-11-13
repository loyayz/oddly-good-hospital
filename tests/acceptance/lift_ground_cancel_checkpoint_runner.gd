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
	# Independent cancel at this genuine loaded checkpoint: other nonempty
	# queues must retain byte-for-byte identity and FIFO, without a sync tick.
	var peers_sim:=HospitalSimulation.new(WorldState.new(e.facts.duplicate(true)),content)
	var peers_world:WorldState=peers_sim.world
	var cancelled:String="patient_00000364"
	var peers_before:Dictionary={}
	var total:int=0
	for c:Dictionary in peers_world.facts.connectors.values():
		var queues:Dictionary=c.get("landing_queues",{}).duplicate(true)
		for line:Array in queues.values():
			for i:int in range(line.size()-1,-1,-1):
				if cancelled in line[i].get("leader_ids",[line[i].actor_id]):line.remove_at(i)
				total+=1
		peers_before[c.id]=queues
	var removed:bool=peers_sim.space.cancel_ground_move(peers_world,cancelled)
	var peers_after:Dictionary={}
	for c:Dictionary in peers_world.facts.connectors.values():peers_after[c.id]=c.get("landing_queues",{})
	var peer_checks:Dictionary={"nonempty_other_rows":total>1,"cancelled":removed,"other_rows_unchanged":peers_before==peers_after,"immediate_valid":peers_world.validate(content).is_empty(),"cold_valid":WorldState.new(peers_world.freeze()).validate(content).is_empty()}
	FileAccess.open(args[1]+".peer-checks.json",FileAccess.WRITE).store_string(JSON.stringify(peer_checks,"\t"))
	peers_sim.dispose()
	var initial: int=w.sim_tick
	var errors: Array=[]
	if not peer_checks.values().all(func(v:bool)->bool:return v):errors.append(peer_checks)
	var before_validation: String=w.validate(content)
	var log: FileAccess=FileAccess.open(args[1]+".steps.ndjson",FileAccess.WRITE)
	for index: int in 499:
		operations.enqueue(sim,int(e.completed_steps)+index-1000)
		log.store_line(JSON.stringify({"enter":w.sim_tick}));log.flush()
		var tick: TickResult=sim.step()
		if tick==null: errors.append("null tick");break
		var missing: Array=[]
		for c: Dictionary in w.facts.connectors.values():
			for line: Array in c.get("landing_queues",{}).values():
				for entry: Dictionary in line:
					if not w.facts.moves.has(entry.actor_id): missing.append({"actor":entry.actor_id,"connector":c.id,"arrived_tick":entry.arrived_tick})
		log.store_line(JSON.stringify({"complete":w.sim_tick,"missing":missing}));log.flush()
		if not missing.is_empty(): errors.append({"tick":w.sim_tick,"missing":missing})
	if not w.validate(content).is_empty():errors.append(w.validate(content))
	var result: Dictionary={"initial_tick":initial,"final_tick":w.sim_tick,"completed_steps":w.sim_tick-initial,"initial_validation":before_validation,"final_validation":w.validate(content),"errors":errors,"restored_submitted_command_keys":operations.submitted.keys(),"scope":"499 real production steps from failed run checkpoint, cold runtime, original ongoing commands reconstructed from receipts. Not a performance sample or full coverage proof."}
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));sim.dispose();quit(0 if errors.is_empty() else 1)
