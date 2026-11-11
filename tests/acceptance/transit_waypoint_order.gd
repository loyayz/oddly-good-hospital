extends "res://tests/acceptance/convoy_transit.gd"

# A41 waiting tickets follow physical presence. The movement request remains
# the same request while its own temporary stand-aside is walked and restored.
const ORDER_CASES: Array[String]=["waypoint_solo","waypoint_convoy","aside_solo","aside_convoy"]

func _run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=2:
		push_error("Expected output JSON and selectors: "+",".join(ORDER_CASES)); quit(2); return
	var selected: PackedStringArray=args[1].split(",")
	var seen: Dictionary={}
	for name: String in selected:
		if not name in ORDER_CASES or seen.has(name):
			push_error("Unknown or duplicate transit-waypoint selector: "+name); quit(2); return
		seen[name]=true
	suite.content=HospitalContent.new()
	var rows: Array=[]
	for name: String in selected:
		var started: int=Time.get_ticks_msec()
		var row: Dictionary=_order_case(name.ends_with("convoy"),name.begins_with("aside"))
		row.selector=name; row.elapsed_ms=Time.get_ticks_msec()-started
		rows.append(row); print(JSON.stringify(row))
	var ok: bool=rows.all(func(row: Dictionary)->bool:return row.ok)
	var file: FileAccess=FileAccess.open(args[0],FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":ok,"rows":rows,"engine":Engine.get_version_info().string,"scope":"Original movement request order through actual ground waypoint, automatic stand-aside, pause and fresh-runtime restore. Actual departure still cancels its transport ticket; a real return obtains a new ticket."},"\t")); file.close()
	quit(0 if ok else 1)

func _order_fixture(convoy: bool, floor_id: int) -> HospitalSimulation:
	var sim: HospitalSimulation=suite._transit_fixture()
	var connection: Dictionary=sim.world.facts.connectors[suite._connection(sim)]
	if convoy:
		# Only the initial aligned boundary is declared. This scope does not
		# test gathering; all temporary motion and later transport must execute.
		var input: Dictionary=_seed(sim,connection,floor_id,3-floor_id)
		if not input.ok: return sim
		var facts: Dictionary=sim.world.freeze()
		facts.moves.clear()
		sim.dispose()
		sim=HospitalSimulation.new(WorldState.new(facts),suite.content)
	else:
		suite._add_actor(sim,"leader","S49",connection.anchor,floor_id)
	return sim

func _request_waiter(sim: HospitalSimulation, convoy: bool, floor_id: int) -> String:
	return sim.space.request_group_move(sim.world,"leader",["leader","follower"],{},floor_id,[44,82]) if convoy else sim.space.request_move(sim.world,"leader",floor_id,[44,82])

func _order_case(convoy: bool, automatic: bool) -> Dictionary:
	var origin_floor: int=2 if automatic else 1
	var sim: HospitalSimulation=_order_fixture(convoy,origin_floor)
	var world: WorldState=sim.world
	var connection_id: String=suite._connection(sim)
	var connection: Dictionary=world.facts.connectors[connection_id]
	var checks: Dictionary={"legal_initial_boundary":world.validate(suite.content).is_empty()}
	if automatic:
		suite._add_actor(sim,"aaa_incoming","S49",connection.anchor,1)
		checks.incoming_request=sim.space.request_move(world,"aaa_incoming",2,[44,86]).is_empty()
	else:
		# A legal empty car at the remote station; its subsequent pickup is real.
		connection.floor_id=2
	checks.waiter_request=_request_waiter(sim,convoy,3-origin_floor).is_empty()
	if not world.facts.moves.has("leader"):
		var rejected: Dictionary={"ok":false,"checks":checks,"reason":"waiter request did not create a movement"}
		sim.dispose(); return rejected
	var movement: Dictionary=world.facts.moves.leader
	var original_sequence: int=int(movement.request_sequence)
	var original_target: Dictionary={"floor_id":movement.target_floor,"cell":movement.target_cell.duplicate()}
	var original_tickets: Dictionary=world.facts.tickets.duplicate(true)
	var before_next: int=int(world.facts.move_request_next)
	var initial: Dictionary=world.freeze()
	var submitted: bool=false
	var submit_tick: int=-1
	var prior_ticket: Dictionary={}
	var submitted_pending: Dictionary={}
	var validation: String=""
	var automatic_no_teleport: bool=true
	for index: int in 100:
		var positions: Dictionary=world.facts.actors.duplicate(true)
		suite._movement_tick(sim)
		movement=world.facts.moves.get("leader",{})
		if movement.is_empty(): break
		if automatic and movement.has("route_waypoint"):
			submitted=true; submit_tick=world.sim_tick-1
			prior_ticket=movement.get("transit_ticket",{}).duplicate(true)
			automatic_no_teleport=positions.leader.location==world.facts.actors.leader.location
			break
		if not automatic and movement.has("transit_ticket"):
			prior_ticket=movement.transit_ticket.duplicate(true)
			var before: Dictionary=world.freeze()
			var continuation: Array=movement.path.slice(int(movement.cursor)).duplicate(true)
			sim.space.queue_waypoint(world,movement,origin_floor,[44,82])
			submitted=true; submit_tick=world.sim_tick
			checks.helper_preserves_original_remainder=movement.route_waypoint.continuation==continuation
			checks.helper_preserves_physical_facts=before.actors==world.facts.actors and before.connectors==world.facts.connectors and before.rng==world.facts.rng and before.ledger==world.facts.ledger
			checks.helper_preserves_current_transit_ticket=prior_ticket==movement.get("transit_ticket",{})
			break
	checks.actual_waypoint_submitted=submitted and movement.has("route_waypoint")
	if not submitted:
		var failed: Dictionary={"ok":false,"checks":checks,"move":_compact_move(movement),"connection":connection.duplicate(true),"validation":world.validate(suite.content)}
		sim.dispose(); return failed
	submitted_pending=movement.duplicate(true)
	checks.original_request_sequence=movement.request_sequence==original_sequence
	checks.no_new_request_identity=world.facts.move_request_next==before_next
	checks.final_goal_preserved=movement.target_floor==original_target.floor_id and movement.target_cell==original_target.cell
	checks.clinical_ticket_ownership_unchanged=world.facts.tickets==original_tickets
	checks.real_ticket_still_owned_at_submission=not prior_ticket.is_empty() and prior_ticket.connector_id==connection_id and int(prior_ticket.from)==origin_floor and int(prior_ticket.to)==3-origin_floor
	checks.automatic_aside_did_not_move_body=automatic_no_teleport
	# A real pause cannot advance pending routes, tickets or the committed car.
	var session: GameSession=GameSession.new(sim,"waypoint_order")
	session.set_speed(1); session.pause("waypoint_order")
	var paused: Dictionary=world.freeze()
	checks.paused_facts_unchanged=session.advance(0.4).is_empty() and world.freeze()==paused
	session.resume("waypoint_order")
	checks.resume_keeps_original_sequence=session.actual_speed()==1 and world.facts.moves.leader.request_sequence==original_sequence
	var restored_facts: Dictionary=world.freeze()
	validation=world.validate(suite.content)
	sim.dispose()
	sim=HospitalSimulation.new(WorldState.new(restored_facts),suite.content)
	world=sim.world; connection=world.facts.connectors[connection_id]; movement=world.facts.moves.leader
	checks.pending_restore_preserves_facts=world.freeze()==restored_facts and world.validate(suite.content).is_empty() and movement==submitted_pending
	var left: bool=false
	var restored_departed: bool=false
	var arrived: bool=false
	var returned_ticket: int=-1
	var committed_ticket: int=-1
	var order_preserved: bool=true
	var target_preserved: bool=true
	var bounded: bool=true
	var cancelled_on_departure: bool=false
	var checkpoints: Dictionary={"submitted_tick":submit_tick}
	for index: int in 800:
		var previous: Dictionary=world.facts.actors.leader.location.duplicate(true)
		suite._movement_tick(sim)
		var actor: Dictionary=world.facts.actors.leader
		movement=world.facts.moves.get("leader",{})
		var error: String=world.validate(suite.content)
		if validation.is_empty() and not error.is_empty(): validation=error
		if previous.kind=="floor" and actor.location.kind=="floor" and previous.floor_id==actor.location.floor_id:
			bounded=bounded and ConvoyTrail.point(previous.cell).distance_to(ConvoyTrail.point(actor.location.cell))<=sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001
		if not movement.is_empty():
			order_preserved=order_preserved and int(movement.request_sequence)==original_sequence
			target_preserved=target_preserved and movement.target_floor==original_target.floor_id and movement.target_cell==original_target.cell
		if not left and actor.location.kind=="floor" and int(actor.location.floor_id)==origin_floor and actor.location.cell!=initial.actors.leader.location.cell and not movement.has("transit_ticket"):
			left=true; cancelled_on_departure=true; checkpoints.actual_departure_tick=world.sim_tick
			var departed: Dictionary=world.freeze()
			sim.dispose()
			sim=HospitalSimulation.new(WorldState.new(departed),suite.content)
			world=sim.world; connection=world.facts.connectors[connection_id]; movement=world.facts.moves.leader
			restored_departed=world.freeze()==departed and world.validate(suite.content).is_empty() and not movement.has("transit_ticket") and int(movement.request_sequence)==original_sequence
		if left and movement.has("transit_ticket"): returned_ticket=int(movement.transit_ticket.sequence)
		if connection.get("primary_actor_id","")=="leader": committed_ticket=int(connection.trip_sequence)
		if actor.location.kind=="floor" and int(actor.location.floor_id)==int(original_target.floor_id) and movement.is_empty():
			arrived=sim.space.at(world,"leader",int(original_target.floor_id),original_target.cell)
			checkpoints.actual_arrival_tick=world.sim_tick
			break
	checks.real_departure_cancels_transit_ticket=left and cancelled_on_departure
	checks.departed_restore_keeps_original_movement=restored_departed
	checks.actual_return_has_new_transit_ticket=maxi(returned_ticket,committed_ticket)>int(prior_ticket.sequence)
	checks.request_order_through_waypoint_and_return=order_preserved
	checks.target_through_waypoint_and_return=target_preserved
	checks.bounded_actual_walking=bounded
	checks.actual_final_arrival=arrived
	checks.world_valid=validation.is_empty() and world.validate(suite.content).is_empty()
	checks.clinical_ticket_ownership_still_unchanged=world.facts.tickets==original_tickets
	var result: Dictionary={"ok":_all(checks),"checks":checks,"original_sequence":original_sequence,"submitted_sequence":submitted_pending.request_sequence,"prior_transit_ticket":prior_ticket,"returned_transit_ticket":returned_ticket,"committed_transit_ticket":committed_ticket,"checkpoints":checkpoints,"validation":validation,"remaining_move":_compact_move(movement),"connection_phase":connection.phase,"initial_tick":initial.sim_tick}
	sim.dispose()
	return result

func _compact_move(movement: Dictionary) -> Dictionary:
	var result: Dictionary=movement.duplicate(true)
	result.erase("path"); result.erase("travelled")
	return result
