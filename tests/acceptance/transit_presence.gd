extends "res://tests/acceptance/convoy_transit.gd"

# A41: only physically present units retain a waiting ticket. These fixtures
# begin at a legal landing; every departure, return and ride uses real motion.
func _run() -> void:
	suite.content=HospitalContent.new()
	var rows: Array=[]
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var cases: Array[String]=["leave_solo","leave_convoy","order_solo","order_convoy","repeated"]
	for name: String in cases:
		if args.size()>1 and not name in args[1].split(","): continue
		match name:
			"leave_solo": rows.append(_leave_and_return(false))
			"leave_convoy": rows.append(_leave_and_return(true))
			"order_solo": rows.append(_present_order(false))
			"order_convoy": rows.append(_present_order(true))
			"repeated": rows.append(_repeated_opposing())
	var ok: bool=not rows.is_empty()
	for row: Dictionary in rows:
		print(JSON.stringify(row))
		ok=ok and row.ok
	if not args.is_empty(): FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify({"ok":ok,"rows":rows},"  "))
	quit(0 if ok else 1)

func _leave_and_return(convoy: bool) -> Dictionary:
	var sim: HospitalSimulation=suite._transit_fixture()
	var world: WorldState=sim.world
	var connection: Dictionary=world.facts.connectors[suite._connection(sim)]
	connection.floor_id=2
	var m: Dictionary
	var segment: Dictionary={"kind":"connector","connector_id":connection.id,"from":1,"to":2}
	if convoy:
		var seed: Dictionary=_seed(sim,connection)
		m=seed.movement
	else:
		suite._add_actor(sim,"leader","S49",connection.anchor)
		m={"actor_id":"leader","path":[segment],"cursor":0,"travelled":[],"blocked_since":-1,"target_floor":2,"target_cell":[44,82]}
		world.facts.moves["leader"]=m
	HospitalTransit.begin(sim.space,world,world.facts.actors.leader,m,segment)
	var first_ticket: int=int(m.get("transit_ticket",{}).get("sequence",-1))
	var started_empty: bool=connection.phase=="empty_riding" and first_ticket==1
	var empty_remaining: int=int(connection.remaining_ticks)
	# Existing ground waypoint API keeps the final goal but walks away first.
	sim.space.queue_waypoint(world,m,1,[44,82])
	var left: bool=false
	var cancelled_on_departure: bool=true
	var assignment_released: bool=false
	var empty_preserved: bool=true
	var returned_ticket: int=-1
	var committed_sequence: int=-1
	var bounded: bool=true
	var valid: String=""
	var restored: bool=false
	var arrived: bool=false
	var ticks: int=0
	for index: int in 500:
		var old: Vector2=ConvoyTrail.point(world.facts.actors.leader.location.get("queue_cell",world.facts.actors.leader.location.get("cell",[0,0])))
		suite._movement_tick(sim)
		ticks+=1
		var actor: Dictionary=world.facts.actors.leader
		if convoy: bounded=bounded and old.distance_to(ConvoyTrail.point(actor.location.get("queue_cell",actor.location.get("cell",[0,0]))))<=sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001
		var current_error: String=world.validate(suite.content)
		if valid.is_empty() and not current_error.is_empty(): valid=current_error
		if not left and actor.location.kind=="floor" and not sim.space.at(world,"leader",1,connection.anchor):
			left=true
			cancelled_on_departure=not m.has("transit_ticket")
			assignment_released=not connection.has("assigned_actor_id")
			# Restore the actual departed state, not a fabricated replacement.
			var saved: Dictionary=world.freeze()
			sim.dispose()
			sim=HospitalSimulation.new(WorldState.new(saved),suite.content)
			world=sim.world
			connection=world.facts.connectors[suite._connection(sim)]
			m=world.facts.moves.leader
			restored=world.validate(suite.content).is_empty() and not m.has("transit_ticket")
		if ticks<empty_remaining: empty_preserved=empty_preserved and connection.phase=="empty_riding" and int(connection.to)==1 and int(connection.remaining_ticks)==empty_remaining-ticks and connection.riders.is_empty()
		if left and m.has("transit_ticket"): returned_ticket=int(m.transit_ticket.sequence)
		if connection.get("primary_actor_id","")=="leader": committed_sequence=int(connection.trip_sequence)
		if actor.location.kind=="floor" and int(actor.location.floor_id)==2 and not world.facts.moves.has("leader"):
			arrived=true
			break
	var checks: Dictionary={"empty_started":started_empty,"actually_left":left,"ticket_cancelled_same_boundary":cancelled_on_departure,"assignment_released":assignment_released,"empty_commitment_unchanged":empty_preserved,"departed_restore_has_no_ticket":restored,"returned_uses_new_ticket":maxi(returned_ticket,committed_sequence)>first_ticket,"arrived":arrived,"bounded_convoy":bounded,"world_valid":valid.is_empty()}
	var result: Dictionary={"ok":_all(checks),"case":"convoy_leave_return" if convoy else "solo_leave_return","checks":checks,"first_ticket":first_ticket,"returned_ticket":returned_ticket,"committed_sequence":committed_sequence,"ticks":ticks,"validation":valid,"remaining":world.facts.moves.duplicate(true)}
	sim.dispose()
	return result

func _present_order(convoy: bool) -> Dictionary:
	var sim: HospitalSimulation=suite._transit_fixture()
	suite._history_height(sim,3)
	var extended: CommandResult=suite._command(sim,"connector_extend",{"connection_id":suite._connection(sim),"floor_id":3})
	var world: WorldState=sim.world
	var connection: Dictionary=world.facts.connectors[suite._connection(sim)]
	connection.floor_id=3
	var a: Dictionary
	var segment: Dictionary={"kind":"connector","connector_id":connection.id,"from":1,"to":2}
	if convoy: a=_seed(sim,connection).movement
	else:
		suite._add_actor(sim,"leader","S49",connection.anchor)
		a={"actor_id":"leader","path":[segment],"cursor":0,"travelled":[],"blocked_since":-1,"target_floor":2,"target_cell":[44,82]}
		world.facts.moves["leader"]=a
	a.target_cell=[44,82]
	HospitalTransit.begin(sim.space,world,world.facts.actors.leader,a,segment)
	var ticket_a: int=int(a.get("transit_ticket",{}).get("sequence",-1))
	sim.space.queue_waypoint(world,a,1,[39,76])
	suite._add_actor(sim,"b","S49",connection.anchor,3)
	var error_b: String
	if convoy:
		suite._add_actor(sim,"bf","S49",[36,78],3)
		error_b=sim.space.request_group_move(world,"b",["b","bf"],{},2,[48,82])
	else: error_b=sim.space.request_move(world,"b",2,[48,82])
	var ticket_b: int=-1
	var new_ticket_a: int=-1
	var order: Array=[]
	var absent_excluded: bool=false
	var b_kept_ticket: bool=true
	var safe: bool=true
	var valid: String=""
	var arrived: bool=false
	var ticks: int=0
	for index: int in 600:
		suite._movement_tick(sim)
		ticks+=1
		var bm: Dictionary=world.facts.moves.get("b",{})
		if bm.has("transit_ticket"):
			if ticket_b<0: ticket_b=int(bm.transit_ticket.sequence)
			b_kept_ticket=b_kept_ticket and int(bm.transit_ticket.sequence)==ticket_b
		if a.has("transit_ticket") and int(a.transit_ticket.sequence)>ticket_a: new_ticket_a=int(a.transit_ticket.sequence)
		if world.facts.actors.leader.location.kind=="floor" and int(world.facts.actors.leader.location.floor_id)==1 and not sim.space.at(world,"leader",1,connection.anchor) and bm.has("transit_ticket"):
			absent_excluded=absent_excluded or HospitalTransit._waiting(sim.space,world,connection.id)==["b"]
		var primary: String=str(connection.get("primary_actor_id",""))
		if not primary.is_empty() and not order.has(primary): order.append(primary)
		if primary=="leader": new_ticket_a=int(connection.trip_sequence)
		for m: Dictionary in world.facts.moves.values():
			if m.has("convoy"): safe=safe and _safe_positions(sim,m)
		var error: String=world.validate(suite.content)
		if valid.is_empty() and not error.is_empty(): valid=error
		if sim.space.at(world,"leader",2,[44,82]) and sim.space.at(world,"b",2,[48,82]) and world.facts.moves.is_empty():
			arrived=true
			break
	var checks: Dictionary={"legal_third_floor":extended.accepted,"request_accepted":error_b.is_empty(),"first_ticket":ticket_a==1,"still_present_ticket":ticket_b==2,"still_present_keeps_ticket":b_kept_ticket,"departed_excluded":absent_excluded,"returned_goes_last":new_ticket_a==3,"actual_boarding_order":order==["b","leader"],"both_real_goals":arrived,"safe":safe,"valid":valid.is_empty()}
	var result: Dictionary={"ok":_all(checks),"case":"present_order_convoy" if convoy else "present_order_solo","checks":checks,"boarding_order":order,"ticket_a":ticket_a,"ticket_b":ticket_b,"new_ticket_a":new_ticket_a,"ticks":ticks,"validation":valid,"remaining":world.facts.moves.duplicate(true)}
	sim.dispose()
	return result

func _repeated_opposing() -> Dictionary:
	var sim: HospitalSimulation=suite._transit_fixture()
	var world: WorldState=sim.world
	for floor_id: int in [1,2]:
		var id: String="a" if floor_id==1 else "b"
		suite._add_actor(sim,id,"S49",[36,76],floor_id)
		suite._add_actor(sim,id+"f","S49",[36,78],floor_id)
	var rounds: Array=[]
	var safe: bool=true
	var valid: String=""
	for round_index: int in 3:
		var target_a: int=2 if round_index%2==0 else 1
		var target_b: int=3-target_a
		var error_a: String=sim.space.request_group_move(world,"a",["a","af"],{},target_a,[44,82])
		var error_b: String=sim.space.request_group_move(world,"b",["b","bf"],{},target_b,[44,82])
		var complete: bool=false
		var ticks: int=0
		for index: int in 900:
			suite._movement_tick(sim)
			ticks+=1
			for m: Dictionary in world.facts.moves.values():
				if m.has("convoy"): safe=safe and _safe_positions(sim,m)
			var error: String=world.validate(suite.content)
			if valid.is_empty() and not error.is_empty(): valid=error
			if sim.space.at(world,"a",target_a,[44,82]) and sim.space.at(world,"b",target_b,[44,82]) and world.facts.moves.is_empty():
				complete=true
				break
		rounds.append({"ok":complete and error_a.is_empty() and error_b.is_empty(),"ticks":ticks,"ticket_next":world.facts.connectors[suite._connection(sim)].ticket_next})
		if not complete: break
	var ok: bool=rounds.size()==3 and safe and valid.is_empty()
	for row: Dictionary in rounds: ok=ok and row.ok
	var result: Dictionary={"ok":ok,"case":"three_consecutive_opposing_rounds","rounds":rounds,"safe":safe,"validation":valid,"scope":"Finite repeated arrivals, not a proof against arbitrary unbounded starvation","remaining":world.facts.moves.duplicate(true)}
	sim.dispose()
	return result
