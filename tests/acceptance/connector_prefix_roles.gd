extends "res://tests/acceptance/convoy_transit.gd"
func _save(path: String,value: Variant) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_var(value,false);file.close()
func _run() -> void:
	var args:=OS.get_cmdline_user_args();var out: String=args[1]
	suite.content=HospitalContent.new()
	var rows: Array=[]
	for role: String in (["nurse_"+args[2]] if args.size()>2 and args[2]=="multiple" else ["nurse","cleaner"]):
		rows.append(_case(out,role))
	var passed: bool=rows.all(func(row: Dictionary)->bool:return row.passed)
	var file:=FileAccess.open(out+"/result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"passed":passed,"rows":rows},"\t"));file.close();quit(0 if passed else 1)
func _case(out: String, role: String) -> Dictionary:
	var sim: HospitalSimulation=suite._transit_fixture();var world: WorldState=sim.world
	var connection: Dictionary=world.facts.connectors[suite._connection(sim)]
	var anchor: Vector2=ConvoyTrail.point(connection.anchor)
	var retreat_y: float=anchor.y+0.3 if role.ends_with("multiple") else anchor.y
	# Declared legal pre-contact input, not a claimed replay of boarding.
	# Staff records come from the same factory as normal new staff.
	suite._add_staff(sim,"role_waiter",role.split("_")[0],[anchor.x+1,anchor.y])
	suite._add_actor(sim,"retreater","S49",[anchor.x+0.4,retreat_y],2)
	suite._add_actor(sim,"incoming","S49",connection.anchor,1)
	world.facts.actors.role_waiter.location.floor_id=2
	world.facts.actors.role_waiter.species_id="S49"
	connection.phase="alighting";connection.from=1;connection.to=2;connection.floor_id=1;connection.remaining_ticks=1;connection.riders=["incoming"];connection.primary_actor_id="incoming";connection.ticket_next=1;connection.trip_sequence=1
	world.facts.actors.incoming.location={"kind":"transit","connector_id":connection.id,"from":1,"to":2}
	var segment: Dictionary={"kind":"connector","connector_id":connection.id,"from":2,"to":1}
	world.facts.moves["role_waiter"]={"actor_id":"role_waiter","path":[segment.duplicate()],"cursor":0,"travelled":[{"kind":"floor","floor_id":2,"cell":[anchor.x+1,anchor.y]}],"blocked_since":-1,"request_sequence":2,"target_floor":1,"target_cell":[44,82]}
	world.facts.moves["retreater"]={"actor_id":"retreater","path":[{"kind":"floor","floor_id":2,"cell":[anchor.x-1,retreat_y]},segment.duplicate()],"cursor":0,"travelled":[{"kind":"floor","floor_id":2,"cell":connection.anchor.duplicate()}],"blocked_since":-1,"request_sequence":3,"target_floor":1,"target_cell":[44,84],"local_move":{"origin":connection.anchor.duplicate(),"retreat":true,"target":{"kind":"floor","floor_id":2,"cell":[anchor.x+2.8,retreat_y]}}}
	world.facts.moves["incoming"]={"actor_id":"incoming","path":[{"kind":"connector","connector_id":connection.id,"from":1,"to":2},{"kind":"floor","floor_id":2,"cell":[44,86]}],"cursor":1,"travelled":[],"blocked_since":-1,"request_sequence":1,"target_floor":2,"target_cell":[44,86]}
	world.facts.move_request_next=3
	if role.ends_with("multiple"):suite._add_actor(sim,"protected_stationary","S49",[anchor.x+1,anchor.y+0.6],2)
	var input: Dictionary=world.freeze()
	var replay: PackedStringArray=OS.get_cmdline_user_args()
	if replay.size()>3:
		var saved:=FileAccess.open(replay[3],FileAccess.READ);input=saved.get_var(false);saved.close()
	sim.dispose();world=WorldState.new(input);sim=HospitalSimulation.new(world,suite.content)
	var error: String=world.validate(suite.content)
	for actor: Dictionary in world.facts.actors.values():
		if actor.location.kind=="floor":
			var point: Vector2=ConvoyTrail.point(actor.location.cell)
			var reason: String=sim.space.navigation.structural_clearance(world,actor,int(actor.location.floor_id)).sweep_reason(point,point)
			if not reason.is_empty():error="initial structural "+actor.id+": "+reason
	var protected_initial: Dictionary=world.facts.actors.get("protected_stationary",{}).duplicate(true)
	_save(out+"/"+role+"-preWorld.bin",input)
	if not error.is_empty():sim.dispose();return {"passed":false,"role":role,"validation":error}
	var frames: Array=[];var accepted: bool=false;var moved: bool=false;var stable: bool=true;var valid: bool=true;var bounded: bool=true;var bodies_clear: bool=true
	for n: int in range(40):
		var before: Dictionary=world.facts.actors.role_waiter.location.duplicate(true)
		var prior: Dictionary=world.facts.actors.duplicate(true)
		suite._movement_tick(sim)
		var m: Dictionary=world.facts.moves.get("role_waiter",{})
		accepted=accepted or m.get("route_waypoint",{}).has("prefix")
		moved=moved or before!=world.facts.actors.role_waiter.location
		stable=stable and not m.is_empty() and m.get("request_sequence",-1)==2 and m.get("target_floor",-1)==1 and m.get("target_cell",[])==[44,82]
		valid=valid and world.validate(suite.content).is_empty()
		for id: String in ["role_waiter","retreater"]:
			var actor: Dictionary=world.facts.actors[id]
			if actor.location.kind=="floor" and prior[id].location.kind=="floor" and actor.location.floor_id==prior[id].location.floor_id:
				bounded=bounded and ConvoyTrail.point(actor.location.cell).distance_to(ConvoyTrail.point(prior[id].location.cell))<=sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001
			if actor.location.kind!="floor":continue
			for other: Dictionary in world.facts.actors.values():
				if other.id==id or other.location.kind!="floor" or other.location.floor_id!=actor.location.floor_id:continue
				bodies_clear=bodies_clear and not sim.space.body_rectangle(actor).intersects(sim.space.body_rectangle(other),false)
		frames.append({"tick":world.sim_tick,"waiter":world.facts.actors.role_waiter.duplicate(true),"move":m.duplicate(true),"retreater":world.facts.actors.retreater.duplicate(true),"connection":world.facts.connectors[connection.id].duplicate(true)})
		if accepted and moved and world.facts.connectors[connection.id].get("trip_sequence",-1)!=1:break
	_save(out+"/"+role+"-frames.bin",frames);_save(out+"/"+role+"-final.bin",world.freeze())
	var protected_unchanged: bool=not (role.ends_with("multiple")) or world.facts.actors.protected_stationary==protected_initial
	var cleared: bool=world.facts.connectors[connection.id].get("trip_sequence",-1)!=1
	var row: Dictionary={"passed":accepted and stable and valid and bounded and bodies_clear and protected_unchanged and (role.ends_with("multiple") or moved and cleared),"protected_unchanged":protected_unchanged,"scope":"protected multi-contact outcome" if role.ends_with("multiple") else "positive release","every_world_valid":valid,"step_budget":bounded,"bodies_clear":bodies_clear,"role":role,"floor":2,"actual_contact_handoff":accepted,"actual_movement":moved,"original_request_target":stable,"steps":frames.size(),"trip_cleared":world.facts.connectors[connection.id].get("trip_sequence",-1)!=1,"validation":error,"final_validation":world.validate(suite.content)}
	sim.dispose();return row
