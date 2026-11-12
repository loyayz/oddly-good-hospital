extends "res://tests/acceptance/transit_busy_recovery.gd"

func _run() -> void:
	suite.content=HospitalContent.new()
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var out: String=args[0]
	if args.size()>1 and args[1]=="decode":
		var data: Variant=FileAccess.open(args[2],FileAccess.READ).get_var()
		FileAccess.open(out+"/decoded.json",FileAccess.WRITE).store_string(JSON.stringify(data,"  "))
		quit(0);return
	if args.size()>1 and args[1]=="regression":
		var rows: Array=[_source_boarding_guard(false),_source_boarding_guard(true),_order_case(false,false),_order_case(true,false)]
		var ok: bool=rows.all(func(row: Dictionary)->bool:return row.ok)
		FileAccess.open(out+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":ok,"rows":rows},"  "))
		quit(0 if ok else 1);return
	if args.size()>1 and args[1]=="edges":
		var result: Dictionary=_edges(out,args[2])
		FileAccess.open(out+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
		print(JSON.stringify(result));quit(0 if result.ok else 1);return
	if args.size()>1 and args[1]=="compare":
		var left: Dictionary=FileAccess.open(args[2],FileAccess.READ).get_var()
		var right: Dictionary=FileAccess.open(args[3],FileAccess.READ).get_var()
		var differences: Dictionary={}
		for key: Variant in left:
			if left[key]!=right.get(key): differences[str(key)]={"before":left[key],"after":right.get(key)}
		FileAccess.open(out+"/differences.json",FileAccess.WRITE).store_string(JSON.stringify(differences,"  "))
		quit(0);return
	var convoy: bool=args.size()>1 and args[1]=="convoy"
	var sim: HospitalSimulation=_order_fixture(convoy,2)
	suite._history_height(sim,3)
	var cid: String=suite._connection(sim)
	var extended: CommandResult=suite._command(sim,"connector_extend",{"connection_id":cid,"floor_id":3})
	var world: WorldState=sim.world
	var c: Dictionary=world.facts.connectors[cid]
	suite._add_actor(sim,"aaa_incoming","S49",c.anchor,1)
	suite._add_actor(sim,"zzz_later","S49",c.anchor,3)
	var requested: bool=sim.space.request_move(world,"aaa_incoming",2,[44,86]).is_empty()
	requested=requested and _request_waiter(sim,convoy,1).is_empty()
	requested=requested and sim.space.request_move(world,"zzz_later",1,[48,86]).is_empty()
	if args.size()>2:
		var input: Dictionary=FileAccess.open(args[2],FileAccess.READ).get_var()
		sim.dispose();sim=HospitalSimulation.new(WorldState.new(input.duplicate(true)),suite.content);world=sim.world;c=world.facts.connectors[suite._connection(sim)];cid=c.id
	var expected: Dictionary=world.freeze().duplicate(true)
	FileAccess.open(out+"/preWorld.bin",FileAccess.WRITE).store_var(expected)
	var valid: String=world.validate(suite.content)
	var ticket: int=-1
	var kept: bool=true
	var departed: bool=false
	var safe: bool=true
	var stable: bool=true
	var original: Dictionary=world.facts.moves.leader.duplicate(true)
	var order: Array=[]
	var frames: Array=[]
	var arrived: bool=false
	var twin: HospitalSimulation=null
	var restored: bool=false
	var cold_equal: bool=true
	var restored_boundaries: Dictionary={}
	var quote_order: bool=false
	var quote_read_only: bool=true
	for step: int in 240:
		if not valid.is_empty(): break
		var before: Dictionary=world.facts.actors.duplicate(true)
		suite._movement_tick(sim)
		if twin!=null:
			suite._movement_tick(twin)
			cold_equal=cold_equal and twin.world.freeze()==world.freeze()
		c=world.facts.connectors[cid]
		var m: Dictionary=world.facts.moves.get("leader",{})
		var actor: Dictionary=world.facts.actors.leader
		if c.get("assigned_actor_id","")=="leader" and actor.location.kind=="floor" and m.has("transit_wait") and not FileAccess.file_exists(out+"/assigned.bin"):
			FileAccess.open(out+"/assigned.bin",FileAccess.WRITE).store_var(world.freeze())
		if m.has("transit_ticket") and ticket<0: ticket=int(m.transit_ticket.sequence)
		if ticket>0 and actor.location.kind=="floor" and int(actor.location.floor_id)==2 and not sim.space.at(world,"leader",2,c.anchor):
			departed=true
			kept=kept and int(m.get("transit_ticket",{}).get("sequence",-1))==ticket
		if departed and not restored:
			var saved: Dictionary=bytes_to_var(var_to_bytes(world.freeze()))
			FileAccess.open(out+"/restore.bin",FileAccess.WRITE).store_var(saved)
			twin=HospitalSimulation.new(WorldState.new(saved),suite.content)
			restored=true
			cold_equal=cold_equal and twin.world.freeze()==world.freeze()
		if m.has("transit_wait"):
			var boundary: String=""
			if c.get("assigned_actor_id","")=="leader": boundary="summoned"
			elif actor.location.kind=="floor" and ConvoyTrail.point(actor.location.cell)==ConvoyTrail.point(m.transit_wait.cell): boundary="waiting"
			if not boundary.is_empty() and not restored_boundaries.has(boundary):
				var exact: Dictionary=world.freeze().duplicate(true)
				FileAccess.open(out+"/"+boundary+"-restore.bin",FileAccess.WRITE).store_var(exact)
				if twin!=null: twin.dispose()
				twin=HospitalSimulation.new(WorldState.new(bytes_to_var(var_to_bytes(exact))),suite.content)
				cold_equal=cold_equal and twin.world.freeze()==exact
				restored_boundaries[boundary]=true
			if c.phase=="idle" and HospitalTransit._at_landing(sim.space,world,c,m,m.transit_ticket):
				var before_query: Dictionary=world.freeze().duplicate(true)
				var prefix: Dictionary=HospitalTransit._prefix(sim.space,world,c,"leader")
				quote_order=prefix.ok
				quote_read_only=quote_read_only and before_query==world.freeze()
		if not m.is_empty(): stable=stable and m.request_sequence==original.request_sequence and m.target_cell==original.target_cell and m.target_floor==original.target_floor
		var primary: String=str(c.get("primary_actor_id",""))
		if not primary.is_empty() and not order.has(primary): order.append(primary)
		safe=safe and _floor_safety(sim,before)
		valid=world.validate(suite.content)
		frames.append({"tick":world.sim_tick,"actors":world.facts.actors.duplicate(true),"moves":world.facts.moves.duplicate(true),"connector":c.duplicate(true)})
		if m.is_empty() and sim.space.at(world,"leader",1,[44,82]): arrived=true;break
	var checks: Dictionary={"requested":requested,"extension":extended.accepted,"valid":valid.is_empty(),"departed":departed,"ticket_unchanged":kept and ticket>0,"service_order":order.size()>=2 and order[0]=="aaa_incoming" and order[1]=="leader","arrived":arrived,"safe":safe,"original_request_goal":stable,"cold_equal":cold_equal and restored,"waiting_summoned_restore":restored_boundaries.size()==2,"later_ticket_not_in_prefix":quote_order,"prefix_read_only":quote_read_only}
	FileAccess.open(out+"/frames.bin",FileAccess.WRITE).store_var(frames)
	FileAccess.open(out+"/final.bin",FileAccess.WRITE).store_var(world.freeze())
	var result: Dictionary={"ok":checks.values().all(func(v: bool)->bool:return v),"checks":checks,"order":order,"ticket":ticket,"validation":valid,"ticks":frames.size()}
	FileAccess.open(out+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result));sim.dispose()
	if twin!=null: twin.dispose()
	quit(0 if result.ok else 1)

func _edges(out: String, source: String) -> Dictionary:
	var input: Dictionary=FileAccess.open(source,FileAccess.READ).get_var()
	var sim: HospitalSimulation=HospitalSimulation.new(WorldState.new(input.duplicate(true)),suite.content)
	var world: WorldState=sim.world
	var m: Dictionary=world.facts.moves.leader
	var cid: String=m.transit_ticket.connector_id
	var c: Dictionary=world.facts.connectors[cid]
	var original_ticket: Dictionary=m.transit_ticket.duplicate(true)
	var before: Dictionary=world.freeze().duplicate(true)
	var quote: Dictionary=HospitalTransit.quote(sim.space,world,c,"leader",2,1,0)
	var checks: Dictionary={"input_exact":before==input,"quote_unknown":quote.get("status")=="estimate_unknown","query_read_only":world.freeze()==before}
	# Declared failure target uses the formal temporary-waypoint API. The shaft
	# interior is structurally forbidden; no actor or original goal is moved.
	sim.space.movement.queue_waypoint(world,m,2,c.cell,true)
	checks.failed_waypoint_legal=world.validate(suite.content).is_empty()
	FileAccess.open(out+"/failure-preWorld.bin",FileAccess.WRITE).store_var(world.freeze())
	suite._movement_tick(sim)
	checks.failure_releases_assignment=not c.has("assigned_actor_id")
	checks.failure_keeps_ticket=m.get("transit_ticket",{})==original_ticket
	checks.failure_returns_waiting=m.get("route_waypoint",{}).get("cell",[])==m.transit_wait.cell
	checks.failure_not_final_goal=not sim.space.movement._route_failures.has("leader")
	checks.failure_valid=world.validate(suite.content).is_empty()
	FileAccess.open(out+"/failure-final.bin",FileAccess.WRITE).store_var(world.freeze())
	var retarget: String=sim.space.request_move(world,"leader",2,[44,86])
	checks.retarget_accepted=retarget.is_empty()
	checks.retarget_releases=not m.has("transit_ticket") and not m.has("transit_wait") and not c.has("assigned_actor_id")
	sim.dispose()
	sim=HospitalSimulation.new(WorldState.new(input.duplicate(true)),suite.content)
	m=sim.world.facts.moves.leader
	c=sim.world.facts.connectors[cid]
	sim.space.queue_waypoint(sim.world,m,2,[44,86])
	checks.unrelated_waypoint_releases=not m.has("transit_ticket") and not m.has("transit_wait") and not c.has("assigned_actor_id")
	sim.dispose()
	var empty: Dictionary=_cancel_empty_ride()
	checks.empty_cancel=empty.ok
	return {"ok":_all(checks),"checks":checks,"quote":quote,"empty_cancel":empty}
