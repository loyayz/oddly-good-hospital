extends SceneTree
func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	var args:=OS.get_cmdline_user_args();var out: String=args[1];var content:=HospitalContent.new()
	var input: Dictionary=FileAccess.open(args[2],FileAccess.READ).get_var(false)
	var sim:=HospitalSimulation.new(WorldState.new(input.duplicate(true)),content);var w: WorldState=sim.world
	var original: Dictionary=w.facts.connectors.benchmark_lift.duplicate(true);var before: Dictionary=w.freeze().duplicate(true);var rows: Array=[]
	for item: Array in [["boarding_from","boarding",int(original.from),true],["boarding_to","boarding",int(original.to),true],["riding_to","riding",int(original.to),true],["alighting_to","alighting",int(original.to),true],["riding_from","riding",int(original.from),false],["empty_riding","empty_riding",int(original.to),false]]:
		var c: Dictionary=original.duplicate(true);c.phase=item[1]
		var result: Dictionary=HospitalTransit._waiting_contact_exit(sim.space,w,c,int(item[2]))
		rows.append({"case":item[0],"ok":result.ok and result.rect.has_area()==bool(item[3]),"owner_envelope":str(result.get("rect"))})
	for item: String in ["missing_owner","missing_rider"]:
		var c: Dictionary=original.duplicate(true);c.phase="boarding"
		if item=="missing_owner":c.primary_actor_id="no_such_actor"
		else:c.riders=[]
		var result: Dictionary=HospitalTransit._waiting_contact_exit(sim.space,w,c,int(c.from))
		rows.append({"case":item,"ok":not result.ok})
	rows.append({"case":"facts_rng_unchanged","ok":w.freeze()==before});sim.dispose()
	input=FileAccess.open(args[3],FileAccess.READ).get_var(false);sim=HospitalSimulation.new(WorldState.new(input.duplicate(true)),content);w=sim.world;before=w.freeze().duplicate(true)
	var connection: Dictionary=w.facts.connectors.values()[0].duplicate(true);connection.phase="idle";connection.floor_id=2;connection.assigned_actor_id="leader"
	var assigned: Dictionary=HospitalTransit._waiting_contact_exit(sim.space,w,connection,2)
	rows.append({"case":"idle_assigned","ok":assigned.ok and assigned.rect.has_area()})
	var absent: Dictionary=HospitalTransit._waiting_contact_exit(sim.space,w,connection,1)
	rows.append({"case":"no_local_service","ok":absent.ok and not absent.rect.has_area()})
	connection.assigned_actor_id="missing"
	rows.append({"case":"idle_missing_assigned_owner","ok":not HospitalTransit._waiting_contact_exit(sim.space,w,connection,2).ok})
	rows.append({"case":"second_facts_rng_unchanged","ok":w.freeze()==before});sim.dispose()
	var passed: bool=rows.all(func(row: Dictionary)->bool:return row.ok)
	FileAccess.open(out+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":passed,"rows":rows,"scope":"Pure helper phase table using copies of connector descriptors and actual source actors/moves. Not simulated boarding/riding transitions or a claim all descriptor combinations are legal Worlds."},"  "));quit(0 if passed else 1)
