extends RefCounted

const START: Array = [35.125,70.375]
const GOAL: Array = [45.625,70.375]
const OriginalNavigation = preload("res://tests/acceptance/navigation_route_subject.gd").OriginalNavigation

func run(suite: RefCounted) -> Dictionary:
	var rows: Array = [_quotes(suite),_walk(suite,false),_walk(suite,true),_retarget(suite),_rejection(suite,false),_rejection(suite,true),_cross_floor(suite),_cross_floor(suite,true),_cancel(suite),_stale_checkpoint(suite),_departure(suite),_departure(suite,true),_departure(suite,false,true),_departure(suite,true,true),_checkpoint_precision(suite),_sleep_handoff(suite),_body(suite,"S06"),_body(suite,"S50")]
	return {"ok":rows.all(func(row: Dictionary)->bool:return row.ok),"cases":rows,"fixed_tick_seconds":WorldState.TICK_SECONDS}

func _point(cell: Array) -> Vector2:
	return Vector2(float(cell[0]),float(cell[1]))

func _equal(a: Array, b: Array) -> bool:
	return _point(a)==_point(b)

func _same_quote(full: Dictionary, cost: Dictionary) -> bool:
	var copy: Dictionary = full.duplicate(true)
	copy.erase("path")
	return var_to_bytes(copy)==var_to_bytes(cost)

func _quotes(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker","S49",START)
	var actor: Dictionary = sim.world.facts.actors.walker
	var before: Dictionary = sim.world.freeze()
	var rows: Array = []
	var ok: bool = true
	var speed: float = sim.space.walking_speed(actor)
	var prefix: float = _point(START).distance_to(Vector2(35,70))
	var integer_reference: HospitalSpace = HospitalSpace.new(suite.content)
	integer_reference.navigation = OriginalNavigation.new(integer_reference)
	sim.space.begin_dynamic_route_query(sim.world)
	for goal: Array in [GOAL,[45.125,70.875],[45.125,70.125],[45,70],[45.0,70.0]]:
		var full: Dictionary = sim.space.route(sim.world,"walker",1,goal)
		var cost: Dictionary = sim.space.route_cost(sim.world,"walker",1,goal)
		var dx: float = float(goal[0])-45.0
		var dy: float = float(goal[1])-70.0
		var expected_distance: float = prefix+10.0+dx+dy
		var expected_ticks: int = ceili(prefix/speed/WorldState.TICK_SECONDS)+ceili(10.0/speed/WorldState.TICK_SECONDS)+ceili(dx/speed/WorldState.TICK_SECONDS)+ceili(dy/speed/WorldState.TICK_SECONDS)
		var matches: bool = full.ok and _same_quote(full,cost) and _equal(full.path.back().cell,goal) and is_equal_approx(float(full.walking_distance),expected_distance) and int(full.travel_ticks)==expected_ticks
		if dx==0.0 and dy==0.0:
			matches = matches and var_to_bytes(full)==var_to_bytes(integer_reference.route(sim.world,"walker",1,goal)) and var_to_bytes(cost)==var_to_bytes(integer_reference.route_cost(sim.world,"walker",1,goal))
		var saved: Dictionary = full.duplicate(true)
		full.path.back().cell[0] = 99.0
		full.path[0].cell[1] = 99.0
		var cached: Dictionary = sim.space.route(sim.world,"walker",1,goal)
		matches = matches and var_to_bytes(saved)==var_to_bytes(cached)
		ok = ok and matches
		rows.append({"ok":matches,"goal":goal,"full":saved,"cost":cost,"independent_distance":expected_distance,"independent_ticks":expected_ticks,"caller_mutation_isolated":var_to_bytes(saved)==var_to_bytes(cached)})
	sim.space.end_route_query()
	var readonly: bool = before==sim.world.freeze()
	var result: Dictionary = {"case":"precise_quotes_and_integer_compatibility","ok":ok and readonly,"facts_rng_unchanged":readonly,"rows":rows}
	sim.dispose()
	return result

# Execute only the normal movement boundary and original fixed tick. Track real
# position, body, heading, per-step budget and each arrival before move removal.
func _tick(suite: RefCounted, sim: HospitalSimulation, goal: Array, floor_id: int, trace: Array, errors: Array, obstacles: Array = []) -> void:
	var actor: Dictionary = sim.world.facts.actors.walker
	var before: Dictionary = actor.duplicate(true)
	var before_rect: Rect2 = sim.space.body_rectangle(actor) if actor.location.kind=="floor" else Rect2()
	var tick: int = sim.world.sim_tick
	suite._movement_tick(sim)
	actor = sim.world.facts.actors.walker
	if sim.world.sim_tick!=tick+1: errors.append("Not one original fixed tick")
	if sim.space.body(actor)!=sim.space.body(before): errors.append("Body changed")
	var distance: float = 0.0
	if actor.location.kind=="floor" and before.location.kind=="floor" and actor.location.floor_id==before.location.floor_id:
		var delta: Vector2 = _point(actor.location.cell)-_point(before.location.cell)
		distance = delta.length()
		if distance>sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001: errors.append("Exceeded original movement budget")
		if distance>0.00001 and absf(angle_difference(float(actor.facing),atan2(delta.x,delta.y)))>0.0001: errors.append("Facing disagrees with actual movement")
		var after_rect: Rect2 = sim.space.body_rectangle(actor)
		for rect: Rect2 in obstacles:
			if after_rect.intersects(rect,false) or BodySweep.intersects(before_rect,after_rect,rect,rect): errors.append("Static body/swept overlap")
	if not sim.world.facts.moves.has("walker") and not sim.space.at(sim.world,"walker",floor_id,goal): errors.append("Move ended before actual target")
	var validation: String = sim.world.validate(suite.content)
	if not validation.is_empty(): errors.append(validation)
	trace.append({"tick":sim.world.sim_tick,"location":actor.location.duplicate(true),"facing":actor.facing,"step_cells":distance,"move_present":sim.world.facts.moves.has("walker"),"sequence":sim.world.facts.moves.get("walker",{}).get("request_sequence",-1)})

func _walk(suite: RefCounted, repeated: bool) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker","S49",START)
	var quote: Dictionary = sim.space.route(sim.world,"walker",1,GOAL)
	var request: String = sim.space.request_move(sim.world,"walker",1,GOAL)
	var sequence: int = int(sim.world.facts.moves.walker.request_sequence)
	var errors: Array = []
	var trace: Array = []
	var positive_steps: int = 0
	for i: int in 160:
		if repeated and sim.world.facts.moves.has("walker"):
			sim.space.request_move(sim.world,"walker",1,GOAL)
			if int(sim.world.facts.moves.walker.request_sequence)!=sequence: errors.append("Identical goal changed request order")
		_tick(suite,sim,GOAL,1,trace,errors)
		if float(trace.back().step_cells)>0: positive_steps += 1
		if not errors.is_empty() or not sim.world.facts.moves.has("walker"): break
	var arrived: bool = sim.space.at(sim.world,"walker",1,GOAL) and not sim.world.facts.moves.has("walker")
	var result: Dictionary = {"case":"repeated_exact_goal" if repeated else "unobstructed_exact_goal","ok":request.is_empty() and errors.is_empty() and arrived and positive_steps==int(quote.travel_ticks) and int(sim.space.query_counts.route_dispatches)==1,"positive_walking_steps":positive_steps,"quoted_walking_ticks":quote.travel_ticks,"actual_arrival":arrived,"errors":errors,"trace":trace}
	sim.dispose()
	return result

func _retarget(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker","S49",START)
	var request: String = sim.space.request_move(sim.world,"walker",1,GOAL)
	var errors: Array = []
	var trace: Array = []
	for i: int in 6: _tick(suite,sim,GOAL,1,trace,errors)
	var previous: Array = sim.world.facts.actors.walker.location.cell.duplicate()
	var goal: Array = [42.125,71.625]
	var changed: String = sim.space.request_move(sim.world,"walker",1,goal)
	var no_jump: bool = _equal(previous,sim.world.facts.actors.walker.location.cell)
	for i: int in 160:
		_tick(suite,sim,goal,1,trace,errors)
		if not errors.is_empty() or not sim.world.facts.moves.has("walker"): break
	var result: Dictionary = {"case":"retarget_between_real_steps","ok":request.is_empty() and changed.is_empty() and no_jump and errors.is_empty() and sim.space.at(sim.world,"walker",1,goal) and not sim.world.facts.moves.has("walker"),"request_did_not_move_actor":no_jump,"final":sim.world.facts.actors.walker.location.duplicate(true),"errors":errors,"trace":trace}
	sim.dispose()
	return result

func _rejection(suite: RefCounted, wall: bool) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker","S49",[35,80])
	var goal: Array = [44.625,71] if wall else [45.25,70]
	var setup: bool = true
	if wall: setup = suite._command(sim,"build_room",suite._room("target_wall",[45,70])).accepted
	else:
		sim.world.facts.floors.overrides["1"].blocked.append([46,70])
		sim.world.touch()
	var actor: Dictionary = sim.world.facts.actors.walker
	var query: RouteClearance = sim.space.navigation.structural_clearance(sim.world,actor,1)
	var rounded_clear: bool = query.reason(Vector2i(_point(goal).round())).is_empty()
	var before: Dictionary = sim.world.freeze()
	var full: Dictionary = sim.space.route(sim.world,"walker",1,goal)
	var cost: Dictionary = sim.space.route_cost(sim.world,"walker",1,goal)
	var request: String = sim.space.request_move(sim.world,"walker",1,goal)
	var fresh_atomic: bool = before==sim.world.freeze()
	var prior: String = sim.space.request_move(sim.world,"walker",1,[40.25,80.5])
	before = sim.world.freeze()
	var changed: String = sim.space.request_move(sim.world,"walker",1,goal)
	var retarget_atomic: bool = before==sim.world.freeze()
	var validation: String = sim.world.validate(suite.content)
	var result: Dictionary = {"case":"fractional_body_crosses_wall" if wall else "fractional_body_overlaps_block","ok":setup and rounded_clear and not full.ok and _same_quote(full,cost) and not request.is_empty() and fresh_atomic and prior.is_empty() and not changed.is_empty() and retarget_atomic and validation.is_empty(),"rounded_neighbor_is_clear":rounded_clear,"full":full,"cost":cost,"request_reason":request,"retarget_reason":changed,"fresh_request_atomic":fresh_atomic,"retarget_atomic":retarget_atomic,"validation":validation}
	sim.dispose()
	return result

func _cross_floor(suite: RefCounted, retarget_in_transit: bool = false) -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	suite._add_actor(sim,"walker","S49",[44.25,80.25])
	var goal: Array = [46.625,82.375]
	var before: Dictionary = sim.world.freeze()
	sim.space.begin_dynamic_route_query(sim.world)
	var full: Dictionary = sim.space.route(sim.world,"walker",2,goal)
	var cost: Dictionary = sim.space.route_cost(sim.world,"walker",2,goal)
	sim.space.end_route_query()
	var readonly: bool = before==sim.world.freeze()
	var request: String = sim.space.request_move(sim.world,"walker",2,goal)
	var trace: Array = []
	var errors: Array = []
	var saw_transit: bool = false
	var retargeted: bool = false
	var safe_ride: bool = true
	for i: int in 700:
		_tick(suite,sim,goal,2,trace,errors)
		saw_transit = saw_transit or sim.world.facts.actors.walker.location.kind=="transit"
		if retarget_in_transit and not retargeted and sim.world.facts.actors.walker.location.kind=="transit":
			var ride: Dictionary = sim.world.facts.actors.walker.location.duplicate(true)
			goal = [47.125,83.625]
			var changed: String = sim.space.request_move(sim.world,"walker",2,goal)
			safe_ride = changed.is_empty() and ride==sim.world.facts.actors.walker.location and sim.world.facts.moves.walker.get("replan_after_transit",false)
			retargeted = true
		if not errors.is_empty() or not sim.world.facts.moves.has("walker"): break
	var result: Dictionary = {"case":"cross_floor_retarget_during_real_ride" if retarget_in_transit else "cross_floor_exact_quote_and_real_arrival","ok":full.ok and _same_quote(full,cost) and _equal(full.path.back().cell,[46.625,82.375]) and (not retarget_in_transit or retargeted and safe_ride) and readonly and request.is_empty() and errors.is_empty() and saw_transit and sim.space.at(sim.world,"walker",2,goal) and not sim.world.facts.moves.has("walker"),"readonly":readonly,"full":full,"cost":cost,"real_transit_observed":saw_transit,"retargeted_during_transit":retargeted,"ride_not_interrupted":safe_ride,"errors":errors,"trace":trace}
	sim.dispose()
	return result

func _cancel(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker","S49",START)
	var requested: String = sim.space.request_move(sim.world,"walker",1,GOAL)
	for i: int in 4: suite._movement_tick(sim)
	var cancelled: bool = sim.space.movement.cancel_ground(sim.world,"walker")
	var at_cancel: Array = sim.world.facts.actors.walker.location.cell.duplicate()
	for i: int in 8: suite._movement_tick(sim)
	var active_absent: bool = not sim.world.facts.moves.has("walker") and _equal(at_cancel,sim.world.facts.actors.walker.location.cell)
	var pending: String = sim.space.request_move(sim.world,"walker",1,GOAL)
	var pending_cancelled: bool = sim.space.movement.cancel_ground(sim.world,"walker")
	for i: int in 8: suite._movement_tick(sim)
	var pending_absent: bool = not sim.world.facts.moves.has("walker") and _equal(at_cancel,sim.world.facts.actors.walker.location.cell)
	var result: Dictionary = {"case":"cancelled_active_and_pending_do_not_revive","ok":requested.is_empty() and cancelled and active_absent and pending.is_empty() and pending_cancelled and pending_absent,"active_stays_cancelled":active_absent,"pending_stays_cancelled":pending_absent}
	sim.dispose()
	return result

func _body(suite: RefCounted, species: String) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker",species,[35,70])
	var size: int = sim.space.clearance(sim.world.facts.actors.walker)
	var block: Array = [46+size,70]
	sim.world.facts.floors.overrides["1"].blocked.append(block)
	sim.world.touch()
	var goal: Array = [45.875,70.875]
	var full: Dictionary = sim.space.route(sim.world,"walker",1,goal)
	var cost: Dictionary = sim.space.route_cost(sim.world,"walker",1,goal)
	var axis: bool = full.ok
	var previous: Vector2 = Vector2(35,70)
	if full.ok:
		for segment: Dictionary in full.path:
			var next: Vector2 = _point(segment.cell)
			axis = axis and (previous.x==next.x or previous.y==next.y)
			previous = next
	var requested: String = sim.space.request_move(sim.world,"walker",1,goal)
	var trace: Array = []
	var errors: Array = []
	var rect: Rect2 = Rect2(_point(block),Vector2.ONE)
	for i: int in 220:
		_tick(suite,sim,goal,1,trace,errors,[rect])
		if not errors.is_empty() or not sim.world.facts.moves.has("walker"): break
	var result: Dictionary = {"case":"non_square_body_near_static_edge_"+species,"ok":axis and _same_quote(full,cost) and requested.is_empty() and errors.is_empty() and sim.space.at(sim.world,"walker",1,goal) and not sim.world.facts.moves.has("walker"),"clearance":size,"axis_aligned_path":axis,"body":sim.space.body(sim.world.facts.actors.walker),"block":block,"full":full,"errors":errors,"trace":trace}
	sim.dispose()
	return result

# Stage 4 may publish outside only after the owner has observed real arrival.
# Its exhausted stage-5 route is then cleanup, not an unfinished floor target.
func _departure(suite: RefCounted, restore_at_exit: bool = false, final_rejoin: bool = false) -> Dictionary:
	var fixtures: RefCounted = load("res://tests/acceptance/floor_guidance.gd").new()
	fixtures._content = suite.content
	var x: Dictionary = fixtures._fixture()
	var visit: Dictionary = fixtures._visit(x,"exact_target_departure",[41.125,95.0] if final_rejoin else [40.125,88.375])
	var actor: Dictionary = x.world.facts.actors[visit.actor_id]
	var exit: Array = x.space.exit_cell(x.world,actor)
	if final_rejoin:
		x.world.facts.actors["exit_blocker"] = suite._actor("exit_blocker","S49",[float(exit[0])-1,float(exit[1])])
		x.world.touch()
		x.space.sync_actor(x.world,"exit_blocker")
	var initial: String = x.world.validate(suite.content)
	var referred: CommandResult = x.c.execute(x.world,"clinical_refer",{"visit_id":visit.id})
	var trace: Array = []
	var errors: Array = []
	var arrived_before_outside: bool = false
	var exhausted_before_outside: bool = false
	var sequence: int = -1
	var same_sequence: bool = true
	var removed_at_handoff: bool = false
	var total_distance: float = 0.0
	var restored: bool = false
	var terminal_rejoin_observed: bool = false
	for index: int in 180:
		var prior: Dictionary = actor.location.duplicate(true)
		var before_rect: Rect2 = x.space.body_rectangle(actor)
		var real_exit: bool = x.space.at(x.world,actor.id,1,exit)
		var move: Dictionary = x.world.facts.moves.get(actor.id,{})
		var exhausted: bool = not move.is_empty() and int(move.cursor)>=move.path.size()
		if real_exit and exhausted and move.get("detour",{}).get("phase","")=="rejoin": terminal_rejoin_observed = true
		if restore_at_exit and not restored and real_exit and exhausted:
			var original: Dictionary = x.world.freeze()
			var old: Dictionary = x
			x = fixtures._restore(old)
			fixtures._dispose(old)
			actor = x.world.facts.actors[visit.actor_id]
			visit = x.world.facts.visits[visit.id]
			restored = original==x.world.freeze()
		x.c.dispatch(x.world)
		var published_outside: bool = actor.location.kind=="outside"
		if published_outside:
			arrived_before_outside = real_exit and prior.kind=="floor"
			exhausted_before_outside = exhausted
		x.space.advance(x.world)
		x.world.facts.sim_tick += 1
		x.world.touch(false)
		x.space.finish_boundary(x.world)
		move = x.world.facts.moves.get(actor.id,{})
		if sequence<0 and not move.is_empty(): sequence = int(move.request_sequence)
		if not move.is_empty(): same_sequence = same_sequence and int(move.request_sequence)==sequence
		var distance: float = 0.0
		if prior.kind=="floor" and actor.location.kind=="floor":
			distance = _point(prior.cell).distance_to(_point(actor.location.cell))
			total_distance += distance
			if distance>x.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001: errors.append("Departure exceeded original walking budget")
			if final_rejoin:
				var after_rect: Rect2 = x.space.body_rectangle(actor)
				var block_rect: Rect2 = x.space.body_rectangle(x.world.facts.actors.exit_blocker)
				if after_rect.intersects(block_rect,false) or BodySweep.intersects(before_rect,after_rect,block_rect,block_rect): errors.append("Departure body/sweep crossed stationary blocker")
		var validation: String = x.world.validate(suite.content)
		if not validation.is_empty(): errors.append(validation)
		trace.append({"tick":x.world.sim_tick,"before":prior,"real_exit_before_dispatch":real_exit,"exhausted_before_dispatch":exhausted,"location":actor.location.duplicate(true),"move_present":not move.is_empty(),"route_pending":move.get("route_pending",false),"step_cells":distance,"phase":visit.phase})
		if published_outside:
			removed_at_handoff = move.is_empty()
			break
		if not errors.is_empty(): break
	var dispatches: int = int(x.space.query_counts.get("route_dispatches",0))
	var no_revival: bool = removed_at_handoff
	if removed_at_handoff:
		for index: int in 3:
			x.c.dispatch(x.world)
			x.space.advance(x.world)
			x.world.facts.sim_tick += 1
			x.world.touch(false)
			x.space.finish_boundary(x.world)
			no_revival = no_revival and actor.location.kind=="outside" and not x.world.facts.moves.has(actor.id) and x.world.validate(suite.content).is_empty()
	var result: Dictionary = {"case":("cold_" if restore_at_exit else "")+("real_final_rejoin_then_departure" if final_rejoin else "real_exit_then_exhausted_route_cleanup"),"ok":(not final_rejoin or terminal_rejoin_observed) and (not restore_at_exit or restored) and initial.is_empty() and referred.accepted and errors.is_empty() and arrived_before_outside and exhausted_before_outside and removed_at_handoff and no_revival and same_sequence and dispatches==(0 if restore_at_exit else 1) and total_distance>1.0 and visit.phase=="departed","terminal_rejoin_at_actual_target":terminal_rejoin_observed,"restored_identical_real_arrival_boundary":restored,"initial_validation":initial,"referral_accepted":referred.accepted,"real_exit_before_outside":arrived_before_outside,"path_exhausted_before_outside":exhausted_before_outside,"removed_on_same_completed_boundary":removed_at_handoff,"no_revival":no_revival,"original_order_kept":same_sequence,"global_route_dispatches":dispatches,"actual_walking_distance":total_distance,"errors":errors,"trace":trace}
	fixtures._dispose(x)
	return result

# Reuse the legal CORE-55 mandatory-sleep input, but stop shortly after actual
# arrival and the first sleep boundaries. No actor, arrival or sleep is supplied.
func _sleep_handoff(suite: RefCounted) -> Dictionary:
	var world: WorldState = HospitalFactory.create("exact_target_sleep","Exact target sleep handoff",true,suite.content)
	var sim: HospitalSimulation = HospitalSimulation.new(world,suite.content)
	var owners: Dictionary = world.facts.staff_life.personal_beds.duplicate(true)
	var observed: Dictionary = {}
	var before: Dictionary = {}
	for bed_id: String in owners:
		var id: String = owners[bed_id].staff_id
		world.facts.staff[id].awake_ticks = 13500
		observed[id] = 0
	var close: CommandResult = sim.apply(GameCommand.from_record({"id":"exact_target_close_intake","hospital_id":world.hospital_id,"kind":"set_intake_open","typed_payload":{"open":false},"expected_revision":world.revision}))
	var initial: String = world.validate(suite.content)
	var errors: Array = []
	var trace: Array = []
	var arrivals: Dictionary = {}
	for index: int in 600:
		before.clear()
		for id: String in observed:
			before[id] = {"actor":world.facts.actors[id].duplicate(true),"task":world.facts.staff[id].life_task.duplicate(true),"move":world.facts.moves.get(id,{}).duplicate(true),"sleep_remaining_ticks":world.facts.staff[id].sleep_remaining_ticks}
		var step = sim.step()
		if step==null: errors.append("Production step did not complete");break
		for id: String in observed:
			var staff: Dictionary = world.facts.staff[id]
			if staff.life_task.phase!="sleep": continue
			observed[id] += 1
			var actor: Dictionary = world.facts.actors[id]
			if before[id].task.phase!="sleep":
				var move: Dictionary = before[id].move
				var target: Array = move.get("target_cell",[])
				var travelled: Array = move.get("travelled",[])
				var actual_arrival: bool = not move.is_empty() and int(move.cursor)>=move.path.size() and before[id].actor.location.kind=="floor" and int(before[id].actor.location.floor_id)==int(move.target_floor) and _equal(before[id].actor.location.cell,target) and not travelled.is_empty() and _equal(travelled.back().cell,target)
				arrivals[id] = {"tick":world.sim_tick,"real_target_arrival_before_support":actual_arrival,"before":before[id],"supported_actor":actor.duplicate(true),"move_after":world.facts.moves.get(id,{}).duplicate(true)}
				if not actual_arrival: errors.append("Sleep began without real target arrival: "+id)
			if world.facts.moves.has(id): errors.append("Completed bed walk retained or requeued after support: "+id)
			if actor.get("posture","")!="lying": errors.append("Sleep lost supported posture: "+id)
			if int(staff.sleep_remaining_ticks)!=int(before[id].sleep_remaining_ticks)-1: errors.append("Sleep did not advance by one real fixed tick: "+id)
			trace.append({"tick":world.sim_tick,"staff_id":id,"phase":staff.life_task.phase,"location":actor.location.duplicate(true),"remaining_sleep":staff.sleep_remaining_ticks,"move_present":world.facts.moves.has(id)})
		var validation: String = world.validate(suite.content)
		if not validation.is_empty(): errors.append(validation)
		if not errors.is_empty() or observed.values().all(func(count: int)->bool:return count>=5): break
	var result: Dictionary = {"case":"real_bed_arrival_then_support_pose_handoff","ok":close.accepted and initial.is_empty() and owners.size()==2 and arrivals.size()==2 and errors.is_empty() and observed.values().all(func(count: int)->bool:return count>=5),"initial_validation":initial,"owners":owners,"sleep_boundaries":observed,"arrivals":arrivals,"errors":errors,"trace":trace,"real_simulation_ticks":world.sim_tick}
	sim.dispose()
	return result

# The initial checkpoint remains A while the first real step travels toward B.
# Retargeting to A must execute its new route, not reuse that stale checkpoint.
func _stale_checkpoint(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker","S49",START)
	var request: String = sim.space.request_move(sim.world,"walker",1,GOAL)
	var trace: Array = []
	var errors: Array = []
	_tick(suite,sim,GOAL,1,trace,errors)
	var move: Dictionary = sim.world.facts.moves.get("walker",{})
	var stale: bool = not move.is_empty() and _equal(move.travelled.back().cell,START) and not sim.space.at(sim.world,"walker",1,START)
	var changed: String = sim.space.request_move(sim.world,"walker",1,START)
	var pending: bool = sim.world.facts.moves.walker.get("route_pending",false)
	var kept_live_until_arrival: bool = true
	for index: int in 50:
		_tick(suite,sim,START,1,trace,errors)
		if not sim.space.at(sim.world,"walker",1,START): kept_live_until_arrival = kept_live_until_arrival and sim.world.facts.moves.has("walker")
		if not errors.is_empty() or not sim.world.facts.moves.has("walker"): break
	var returned: bool = sim.space.at(sim.world,"walker",1,START) and not sim.world.facts.moves.has("walker")
	var return_dispatches: int = int(sim.space.query_counts.get("route_dispatches",0))
	sim.dispose()
	var zero: HospitalSimulation = suite._fixture()
	suite._add_actor(zero,"walker","S49",[35,70])
	var to_b: String = zero.space.request_move(zero.world,"walker",1,GOAL)
	var to_a: String = zero.space.request_move(zero.world,"walker",1,[35,70])
	var pending_zero: bool = zero.world.facts.moves.walker.get("route_pending",false)
	var zero_trace: Array = []
	_tick(suite,zero,[35,70],1,zero_trace,errors)
	var no_motion: bool = zero.space.at(zero.world,"walker",1,[35,70]) and not zero.world.facts.moves.has("walker") and float(zero_trace.back().step_cells)==0.0
	var result: Dictionary = {"case":"retarget_A_B_A_with_stale_initial_checkpoint","ok":request.is_empty() and changed.is_empty() and stale and pending and kept_live_until_arrival and returned and return_dispatches==2 and errors.is_empty() and to_b.is_empty() and to_a.is_empty() and pending_zero and no_motion,"old_checkpoint_matches_target_before_return":stale,"new_return_route_was_pending":pending,"kept_live_until_real_return":kept_live_until_arrival,"real_return_arrival":returned,"global_return_dispatches":return_dispatches,"already_at_initial_integer_goal_finishes_without_motion":no_motion,"errors":errors,"trace":trace,"initial_zero_distance_trace":zero_trace}
	zero.dispose()
	return result

# Godot vector relative equality at large coordinates is looser than the
# original Euclidean arrival tolerance. Only actual arrival earns a checkpoint.
func _checkpoint_precision(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var start: Array = [59.89516,94.82844]
	var goal: Array = [60,95]
	suite._add_actor(sim,"walker","S49",start)
	var quote: Dictionary = sim.space.route(sim.world,"walker",1,goal)
	var request: String = sim.space.request_move(sim.world,"walker",1,goal)
	var errors: Array = []
	var trace: Array = []
	_tick(suite,sim,goal,1,trace,errors)
	var movement: Dictionary = sim.world.facts.moves.get("walker",{})
	var no_premature_proof: bool = not sim.space.at(sim.world,"walker",1,goal) and not movement.is_empty() and int(movement.cursor)<movement.path.size() and not _equal(movement.travelled.back().cell,goal)
	for index: int in 5:
		_tick(suite,sim,goal,1,trace,errors)
		if not errors.is_empty() or not sim.world.facts.moves.has("walker"): break
	var walking_steps: int = trace.filter(func(row: Dictionary)->bool:return float(row.step_cells)>0.0).size()
	var result: Dictionary = {"case":"checkpoint_requires_real_arrival_not_relative_vector_equality","ok":request.is_empty() and quote.ok and int(quote.travel_ticks)==2 and no_premature_proof and errors.is_empty() and walking_steps==2 and sim.space.at(sim.world,"walker",1,goal) and not sim.world.facts.moves.has("walker"),"after_first_step_no_false_checkpoint":no_premature_proof,"quoted_walking_ticks":quote.get("travel_ticks",-1),"actual_walking_steps":walking_steps,"errors":errors,"trace":trace}
	sim.dispose()
	return result
