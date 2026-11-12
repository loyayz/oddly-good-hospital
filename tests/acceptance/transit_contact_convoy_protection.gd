extends "res://tests/acceptance/transit_waypoint_order.gd"
func _run() -> void:
	var args:=OS.get_cmdline_user_args();var out: String=args[1]
	suite.content=HospitalContent.new()
	var sim: HospitalSimulation=_order_fixture(true,2);var world: WorldState=sim.world
	var requested: bool=_request_waiter(sim,true,1).is_empty()
	suite._add_actor(sim,"probe","S49",[44,84],2)
	requested=requested and sim.space.request_move(world,"probe",1,[44,86]).is_empty()
	var before: Dictionary=world.freeze().duplicate(true)
	FileAccess.open(out+"/convoy-preWorld.bin",FileAccess.WRITE).store_var(before)
	var valid: String=world.validate(suite.content)
	var m: Dictionary=world.facts.moves.leader;var root: Dictionary=world.facts.moves.probe
	var selected_rejected: bool=not HospitalTransit.yield_to_selected(sim.space,world,world.facts.actors.leader,m,world.facts.actors.probe,root,Vector2.RIGHT)
	var incoming_rejected: bool=not HospitalTransit.yield_to_retreat(sim.space,world,world.facts.actors.leader,m,world.facts.actors.probe,root,Vector2.RIGHT)
	var unchanged: bool=world.freeze()==before
	var result: Dictionary={"ok":requested and valid.is_empty() and selected_rejected and incoming_rejected and unchanged,"official_group_request":requested,"initial_validation":valid,"convoy_selected_protected":selected_rejected,"convoy_incoming_protected":incoming_rejected,"full_world_unchanged":unchanged,"scope":"Direct permission negative on actual valid group state, not a simulated group-contact flow or group liveness positive."}
	FileAccess.open(out+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	sim.dispose();quit(0 if result.ok else 1)
