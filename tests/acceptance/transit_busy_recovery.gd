extends "res://tests/acceptance/transit_waypoint_order.gd"

# A41: clearing an incoming rider does not suspend ground recovery throughout
# a subsequent unrelated empty-car trip. Tickets still require actual return.
func _run() -> void:
	suite.content=HospitalContent.new()
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var rows: Array=[]
	for convoy: bool in [false,true]:
		var started: int=Time.get_ticks_usec()
		var row: Dictionary=_busy_recovery(convoy)
		row.elapsed_us=Time.get_ticks_usec()-started
		rows.append(row)
		print(JSON.stringify(row))
		var guard_row: Dictionary=_source_boarding_guard(convoy)
		rows.append(guard_row)
		print(JSON.stringify(guard_row))
	var ok: bool=rows.all(func(row: Dictionary)->bool:return row.ok)
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify({"ok":ok,"rows":rows},"\t"))
	quit(0 if ok else 1)

func _busy_recovery(convoy: bool) -> Dictionary:
	var sim: HospitalSimulation=_order_fixture(convoy,2)
	suite._history_height(sim,3)
	var connection_id: String=suite._connection(sim)
	var extended: CommandResult=suite._command(sim,"connector_extend",{"connection_id":connection_id,"floor_id":3})
	var world: WorldState=sim.world
	var connection: Dictionary=world.facts.connectors[connection_id]
	# Initial lawful arrivals only; all subsequent stand-aside, return and
	# portal motion must run through production movement at 0.1 seconds.
	suite._add_actor(sim,"aaa_incoming","S49",connection.anchor,1)
	suite._add_actor(sim,"bbb_present","S49",connection.anchor,3)
	var checks: Dictionary={"extension":extended.accepted}
	var job_id: String=""
	if not convoy:
		# A legal existing contractor/job boundary. The movement test starts
		# after admission; it does not claim to test spawning or work payment.
		connection.condition=45.0
		var order: CommandResult=suite._command(sim,"maintenance_order",{"facility_id":connection_id})
		checks.order_accepted=order.accepted
		job_id=str(order.changed_ids[0])
		var job: Dictionary=world.facts.maintenance.jobs[job_id]
		job.worker_id="leader";job.phase="travelling";job.work_floor=1;job.work_cell=connection.repair_cell.duplicate()
		world.facts.actors.leader.service_role="mechanic"
		world.facts.maintenance.contractors.leader={"id":"leader","job_id":job_id,"phase":"assigned"}
	checks.requests=sim.space.request_move(world,"aaa_incoming",2,[44,86]).is_empty() and sim.space.request_move(world,"bbb_present",1,[44,86]).is_empty() and (_request_waiter(sim,true,1).is_empty() if convoy else sim.space.request_move(world,"leader",1,connection.repair_cell).is_empty())
	if not job_id.is_empty(): world.facts.moves.leader.owner_job_id=job_id
	var original_jobs: Dictionary=world.facts.maintenance.duplicate(true)
	checks.initial_valid=world.validate(suite.content).is_empty()
	var original_sequence: int=int(world.facts.moves.leader.request_sequence)
	var goal: Array=world.facts.moves.leader.target_cell.duplicate()
	var clinical: Dictionary=world.facts.tickets.duplicate(true)
	var twin: HospitalSimulation=null
	var departed: bool=false
	var incoming_trip: int=-1
	var old_ticket: int=-1
	var present_ticket: int=-1
	var recovery_tick: int=-1
	var released_tick: int=-1
	var new_ticket: int=-1
	var arrived: bool=false
	var waiting_safely: bool=true
	var sequence_kept: bool=true
	var jobs_kept: bool=true
	var tickets_legal: bool=true
	var cold_equal: bool=true
	var bounded: bool=true
	var safe: bool=true
	var valid: String=""
	var rows: Array=[]
	var boarding_order: Array=[]
	for index: int in 500:
		var all_before: Dictionary=world.facts.actors.duplicate(true)
		var previous: Dictionary=world.facts.actors.leader.location.duplicate(true)
		suite._movement_tick(sim)
		if twin!=null:
			suite._movement_tick(twin)
			cold_equal=cold_equal and twin.world.freeze()==world.freeze()
		connection=world.facts.connectors[connection_id]
		var primary: String=str(connection.get("primary_actor_id",""))
		if not primary.is_empty() and not boarding_order.has(primary): boarding_order.append(primary)
		var actor: Dictionary=world.facts.actors.leader
		var m: Dictionary=world.facts.moves.get("leader",{})
		var bm: Dictionary=world.facts.moves.get("bbb_present",{})
		if connection.get("primary_actor_id","")=="aaa_incoming": incoming_trip=int(connection.trip_sequence)
		if bm.has("transit_ticket"): present_ticket=int(bm.transit_ticket.sequence)
		if m.has("transit_ticket"):
			if old_ticket<0: old_ticket=int(m.transit_ticket.sequence)
			elif int(m.transit_ticket.sequence)!=old_ticket: new_ticket=int(m.transit_ticket.sequence)
			tickets_legal=tickets_legal and HospitalTransit._at_landing(sim.space,world,connection,m,m.transit_ticket)
		jobs_kept=jobs_kept and world.facts.maintenance==original_jobs
		if not m.is_empty():
			jobs_kept=jobs_kept and (job_id.is_empty() or m.get("owner_job_id","")==job_id)
			sequence_kept=sequence_kept and int(m.request_sequence)==original_sequence and m.target_floor==1 and m.target_cell==goal
		if previous.kind=="floor" and actor.location.kind=="floor" and previous.floor_id==actor.location.floor_id:
			bounded=bounded and ConvoyTrail.point(previous.cell).distance_to(ConvoyTrail.point(actor.location.cell))<=sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001
		safe=safe and _floor_safety(sim,all_before)
		if convoy and not m.is_empty(): safe=safe and _safe_positions(sim,m)
		var error: String=world.validate(suite.content)
		if valid.is_empty() and not error.is_empty(): valid=error
		if not departed and old_ticket>0 and actor.location.kind=="floor" and not m.has("transit_ticket"):
			departed=true
			# Byte serialization and fresh services, not a shallow fact clone.
			var encoded: PackedByteArray=var_to_bytes(world.freeze())
			var decoded: Dictionary=bytes_to_var(encoded)
			twin=HospitalSimulation.new(WorldState.new(decoded),suite.content)
			cold_equal=cold_equal and twin.world.freeze()==world.freeze() and twin.world.validate(suite.content).is_empty()
		var incoming_active: bool=connection.get("primary_actor_id","")=="aaa_incoming"
		if departed and incoming_active and not m.is_empty() and int(m.cursor)<m.path.size() and m.path[int(m.cursor)].kind=="connector":
			waiting_safely=waiting_safely and not m.get("route_pending",false) and not m.has("transit_ticket")
		if incoming_trip>0 and connection.get("use_receipts",{}).has("transit:"+str(incoming_trip)) and released_tick<0:
			released_tick=world.sim_tick
			var is_unrelated_empty: bool=connection.phase=="empty_riding" and int(connection.to)==3 and not bm.is_empty() and bm.has("transit_ticket")
			var queued_recovery: bool=not m.is_empty() and m.get("route_pending",false) and not m.has("transit_ticket")
			checks.unrelated_trip_started=is_unrelated_empty
			checks.recovery_after_safe_release=is_unrelated_empty and queued_recovery
			rows.append({"tick":world.sim_tick,"connection":connection.duplicate(true),"move":_compact_move(m),"location":actor.location.duplicate(true)})
			if queued_recovery: recovery_tick=world.sim_tick
			else: break
		if connection.get("primary_actor_id","")=="leader": new_ticket=int(connection.trip_sequence)
		if released_tick>0 and actor.location.kind=="floor" and int(actor.location.floor_id)==1 and m.is_empty():
			arrived=sim.space.at(world,"leader",1,goal)
			break
	checks.real_departure=departed
	checks.original_incoming_safe=waiting_safely
	checks.original_request_and_goal=sequence_kept
	checks.original_jobs_and_no_work_or_charge=jobs_kept
	checks.no_absent_ticket=tickets_legal
	checks.actual_boarding_order=boarding_order==["aaa_incoming","bbb_present","leader"]
	checks.new_ticket_after_present=new_ticket>present_ticket and present_ticket>0 and new_ticket>old_ticket
	checks.cold_continuation=cold_equal and twin!=null
	checks.real_arrival=arrived
	checks.speed_and_body_safety=bounded and safe
	checks.world_valid=valid.is_empty()
	checks.clinical_ownership=world.facts.tickets==clinical
	var result: Dictionary={"ok":_all(checks),"case":"convoy" if convoy else "solo","checks":checks,"release_tick":released_tick,"recovery_tick":recovery_tick,"boarding_order":boarding_order,"old_ticket":old_ticket,"present_ticket":present_ticket,"new_ticket":new_ticket,"validation":valid,"boundary":rows}
	if twin!=null:twin.dispose()
	sim.dispose()
	return result

# Every pair of current floor bodies, and synchronized swept bodies for actors
# that stayed on one floor. Portal phase checks remain in the existing suite.
func _floor_safety(sim: HospitalSimulation, before: Dictionary) -> bool:
	var ids: Array=sim.world.ids("actors")
	for a: int in ids.size():
		var left: Dictionary=sim.world.facts.actors[ids[a]]
		if left.location.kind!="floor": continue
		var lr: Rect2=sim.space._actor_rect(left,ConvoyTrail.point(left.location.cell))
		for b: int in range(a+1,ids.size()):
			var right: Dictionary=sim.world.facts.actors[ids[b]]
			if right.location.kind!="floor" or left.location.floor_id!=right.location.floor_id: continue
			var rr: Rect2=sim.space._actor_rect(right,ConvoyTrail.point(right.location.cell))
			if lr.intersects(rr,false): return false
			var lb: Dictionary=before.get(ids[a],{})
			var rb: Dictionary=before.get(ids[b],{})
			if lb.is_empty() or rb.is_empty() or lb.location.kind!="floor" or rb.location.kind!="floor" or lb.location.floor_id!=left.location.floor_id or rb.location.floor_id!=right.location.floor_id: continue
			if BodySweep.intersects(sim.space._actor_rect(lb,ConvoyTrail.point(lb.location.cell)),lr,sim.space._actor_rect(rb,ConvoyTrail.point(rb.location.cell)),rr): return false
	return true

func _source_boarding_guard(convoy: bool) -> Dictionary:
	var sim: HospitalSimulation=_order_fixture(convoy,2)
	var world: WorldState=sim.world
	var cid: String=suite._connection(sim)
	var connection: Dictionary=world.facts.connectors[cid]
	# Legal post-waypoint input boundary: leader is already clear of the
	# entrance and owns its original connector remainder, with no ticket.
	# No tested motion, boarding duration or safe release is fabricated.
	var members: Array=["leader","follower"] if convoy else ["leader"]
	for id: String in members:
		world.facts.actors[id].location.cell[0]-=4
	var request: String=_request_waiter(sim,convoy,1)
	var m: Dictionary=world.facts.moves.leader
	if convoy:
		# Rebuild only the declared input's coherent initial trail.
		m.convoy=ConvoyTrail.create(sim.space,world,"leader",members).convoy
	m.path=[{"kind":"connector","connector_id":cid,"from":2,"to":1}]
	m.cursor=0;m.route_pending=false
	var sequence: int=int(m.request_sequence)
	suite._add_actor(sim,"aaa_boarding","S49",connection.anchor,2)
	connection.floor_id=2
	var board_request: String=sim.space.request_move(world,"aaa_boarding",1,[44,86])
	var initial: Dictionary=bytes_to_var(var_to_bytes(world.freeze()))
	sim.dispose()
	sim=HospitalSimulation.new(WorldState.new(initial),suite.content)
	world=sim.world
	var checks: Dictionary={"requests":request.is_empty() and board_request.is_empty(),"legal_input":world.validate(suite.content).is_empty()}
	var held: bool=true
	var saw_boarding: bool=false
	var recovered: bool=false
	var safe: bool=true
	for index: int in 30:
		var before: Dictionary=world.facts.actors.duplicate(true)
		suite._movement_tick(sim)
		connection=world.facts.connectors[cid];m=world.facts.moves.leader
		safe=safe and _floor_safety(sim,before) and world.validate(suite.content).is_empty()
		if connection.phase=="boarding":
			saw_boarding=true
			held=held and not m.route_pending and not m.has("transit_ticket") and world.facts.actors.leader.location==before.leader.location
		if saw_boarding and connection.phase=="riding":
			recovered=m.route_pending and not m.has("transit_ticket") and int(m.request_sequence)==sequence
			break
	checks.actual_source_boarding=saw_boarding
	checks.source_entrance_retained=held
	checks.recovery_after_actual_departure=recovered
	checks.body_safety_and_validity=safe
	var result: Dictionary={"ok":_all(checks),"case":"source_boarding_convoy" if convoy else "source_boarding_solo","checks":checks,"tick":world.sim_tick,"phase":connection.phase}
	sim.dispose()
	return result
