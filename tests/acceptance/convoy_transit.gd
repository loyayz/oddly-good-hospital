extends SceneTree

# Transit-boundary regression: fixtures start with a legal already-assembled
# queue at the actual landing. Every boarding/alighting step is real movement.
const SpaceCases = preload("res://tests/acceptance/space.gd")
var suite = SpaceCases.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	suite.content = HospitalContent.new()
	var started: int = Time.get_ticks_usec()
	var rows: Array = []
	var selected: PackedStringArray = OS.get_cmdline_user_args()
	var cases: Array[String] = ["plans","cache","mixed","opposing","rotations","retarget","journey","ride","blocked","admission","cancel","stairs","solo_stairs","solo"]
	for name: String in cases:
		if selected.size()>1 and not name in selected[1].split(","): continue
		var row: Dictionary
		match name:
			"plans": row = _plans()
			"rotations": row = _rotated_connectors()
			"cache": row = _plan_cache()
			"mixed": row = _mixed_queues()
			"opposing": row = _opposing_queues()
			"retarget": row = _inflight_return()
			"journey": row = _journey_restore()
			"ride": row = _ride(false)
			"blocked": row = _ride(true)
			"admission": row = _admission()
			"cancel": row = _cancel_empty_ride()
			"stairs": row = _stairs()
			"solo_stairs": row = _solo_stairs()
			"solo": row = _solo()
		rows.append(row)
		print(JSON.stringify(row))
	var ok: bool = not rows.is_empty()
	for row: Dictionary in rows: ok = ok and bool(row.ok)
	var result: Dictionary = {"ok":ok,"rows":rows,"seconds":float(Time.get_ticks_usec()-started)/1000000.0,"engine":Engine.get_version_info().string,"scope":"Selected convoy transit boundary tests, not full gameplay acceptance or rendering QA"}
	if not selected.is_empty(): FileAccess.open(selected[0],FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	quit(0 if ok else 1)

func _all(checks: Dictionary) -> bool:
	for value: Variant in checks.values():
		if not bool(value): return false
	return true

func _seed(sim: HospitalSimulation, connection: Dictionary, from_floor: int = 1, to_floor: int = 2, count: int = 2, direction: Vector2 = Vector2.UP) -> Dictionary:
	var world: WorldState = sim.world
	var members: Array = ["leader"] if count==1 else ["leader","follower"]
	for id: String in members: suite._add_actor(sim,id,"S49",connection.anchor,from_floor)
	var form: Dictionary = ConvoyTrail.formation(sim.space,world,"leader",members,direction)
	for id: String in members:
		world.facts.actors[id].location.cell = form.targets[id].duplicate()
		sim.space.sync_actor(world,id)
	var created: Dictionary = ConvoyTrail.create(sim.space,world,"leader",members)
	if not created.ok: return {"ok":false,"reason":created.reason}
	var convoy: Dictionary = created.convoy
	var plan: Dictionary = ConvoyPortal.plan(sim.space,world,connection,"leader",members,convoy)
	if not plan.ok: return {"ok":false,"reason":plan.reason}
	# Input boundary only: the test starts at the exact plan entry, with the
	# entire queue already legally present. No tested motion is skipped.
	var delta: Vector2 = ConvoyTrail.point(plan.entry)-ConvoyTrail.point(world.facts.actors.leader.location.cell)
	for id: String in members:
		var cell: Vector2 = ConvoyTrail.point(world.facts.actors[id].location.cell)+delta
		world.facts.actors[id].location.cell = [cell.x,cell.y]
		sim.space.sync_actor(world,id)
	created = ConvoyTrail.create(sim.space,world,"leader",members)
	if not created.ok: return {"ok":false,"reason":created.reason}
	var segment: Dictionary = {"kind":"connector","connector_id":connection.id,"from":from_floor,"to":to_floor}
	var movement: Dictionary = {"actor_id":"leader","members":members,"convoy":created.convoy,"path":[segment],"cursor":0,"travelled":[sim.space.movement._checkpoint(world.facts.actors.leader)],"blocked_since":-1,"yielding":false,"target_floor":to_floor,"target_cell":plan.egress.duplicate()}
	world.facts.moves["leader"] = movement
	world.touch()
	sim.space._sync_convoys(world)
	return {"ok":true,"movement":movement,"segment":segment,"plan":plan}

func _plans() -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	var world: WorldState = sim.world
	var connection: Dictionary = world.facts.connectors[suite._connection(sim)]
	var seeded: Dictionary = _seed(sim,connection)
	if not seeded.ok:
		sim.dispose()
		return {"ok":false,"case":"portal_plans","reason":seeded.reason}
	var observations: Array = []
	var all_ok: bool = true
	for rotation: int in 4:
		var rotated: Dictionary = connection.duplicate(true)
		rotated.rotation = rotation
		var m: Dictionary = seeded.movement
		var p: Dictionary = ConvoyPortal.plan(sim.space,world,rotated,"leader",m.members,m.convoy)
		var safe: bool = p.ok
		var ticks: Array[int] = []
		var trial: Dictionary = m.convoy.duplicate(true)
		if p.ok:
			var tail: Vector2 = ConvoyTrail.point(p.entry)-ConvoyTrail.point(p.inward)*float(trial.spacing)
			trial.points = [[tail.x,tail.y],p.entry.duplicate()]
			for targets: Array in [p.boarding,p.alighting]:
				var cursor: int = 0
				var elapsed: int = 0
				while cursor<targets.size() and elapsed<300:
					var proposal: Dictionary = ConvoyPortal.propose_step(trial,targets,cursor,sim.space.walking_speed(world.facts.actors.leader)*WorldState.TICK_SECONDS)
					if not proposal.ok: safe = false; break
					trial.points = proposal.points
					cursor = proposal.cursor
					elapsed += 1
					var poses: Dictionary = ConvoyTrail.positions(trial,m.members)
					var a: Rect2 = Rect2(ConvoyTrail.point(poses.leader.cell)+Vector2.ONE*float(trial.shift),Vector2.ONE*float(trial.size))
					var b: Rect2 = Rect2(ConvoyTrail.point(poses.follower.cell)+Vector2.ONE*float(trial.shift),Vector2.ONE*float(trial.size))
					safe = safe and not a.intersects(b,false) and float(proposal.distance)<=sim.space.walking_speed(world.facts.actors.leader)*WorldState.TICK_SECONDS+0.0001
				ticks.append(elapsed)
				safe = safe and cursor==targets.size()
			var predicted: Dictionary = ConvoyPortal.predict(m.convoy,p,2)
			safe = safe and ConvoyTrail.point(trial.points[-1]).distance_to(ConvoyTrail.point(p.egress))<0.001 and ConvoyTrail.point(trial.points[0]).distance_to(ConvoyTrail.point(predicted.points[0]))<0.001
		var ticks_match: bool = p.ok and ticks==[p.boarding_ticks,p.alighting_ticks]
		all_ok = all_ok and safe and ticks_match
		observations.append({"rotation":rotation,"plan_ok":p.ok,"safe":safe,"ticks_match":ticks_match,"ticks":ticks,"reason":p.reason})
	sim.dispose()
	return {"ok":all_ok,"case":"portal_plans","rotations":observations}

func _safe_positions(sim: HospitalSimulation, movement: Dictionary) -> bool:
	var world: WorldState = sim.world
	var poses: Dictionary = ConvoyTrail.positions(movement.convoy,movement.members)
	var rects: Array[Rect2] = []
	for id: String in movement.members:
		var actor: Dictionary = world.facts.actors[id]
		var actual: Array = actor.location.queue_cell if actor.location.kind=="transit" else actor.location.cell
		if ConvoyTrail.point(actual).distance_to(ConvoyTrail.point(poses[id].cell))>0.001: return false
		var body: Rect2 = sim.space._actor_rect(actor,ConvoyTrail.point(actual))
		for other: Rect2 in rects:
			if body.intersects(other,false): return false
		rects.append(body)
	return true

func _ride(blocked: bool) -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	var world: WorldState = sim.world
	var connection: Dictionary = world.facts.connectors[suite._connection(sim)]
	var seeded: Dictionary = _seed(sim,connection)
	if not seeded.ok:
		sim.dispose()
		return {"ok":false,"case":"blocked_ride" if blocked else "real_ride","reason":seeded.reason}
	var movement: Dictionary = seeded.movement
	var initial_validation: String = world.validate(suite.content)
	var before: Dictionary = world.facts.actors.duplicate(true)
	var fit: Dictionary = HospitalTransit.fits(sim.space,world,connection,"leader",movement.members)
	var quote: Dictionary = HospitalTransit.quote(sim.space,world,connection,"leader",1,2,0,movement.members,{})
	HospitalTransit.begin(sim.space,world,world.facts.actors.leader,movement,seeded.segment)
	var no_teleport: bool = true
	for id: String in movement.members:
		no_teleport = no_teleport and before[id].location.cell==world.facts.actors[id].location.queue_cell
	var began: bool = connection.phase=="boarding" and connection.riders==movement.members and not movement.has("transit_ticket")
	if blocked: suite._add_actor(sim,"blocker","S49",seeded.plan.egress,2)
	var first_error: String = initial_validation
	var safe: bool = true
	var bounded: bool = true
	var saw_riding: bool = false
	var saw_alighting: bool = false
	var stalled: bool = false
	var unknown_quote: bool = false
	var released_blocker: bool = false
	var stall_ticks: int = 0
	var ticks: int = 0
	var remainder_ok: bool = true
	var failure_committed: bool = false
	var before_condition: float = float(connection.condition)
	var wear: float = 0.0
	for category: Dictionary in suite.content.balance.equipment.classes:
		if category.id==suite.content.definition("vertical_connectors",connection.definition_id).equipment_class: wear = float(category.wear_per_use)
	for index: int in 500:
		var previous_points: Array = movement.convoy.points.duplicate(true)
		var old_phase: String = connection.phase
		var previous_cursor: int = int(movement.convoy.get("portal",{}).get("cursor",-1))
		var remaining: int = HospitalTransit._unit_phase_ticks(sim.space,world,connection,"leader",old_phase,true) if old_phase in ["boarding","alighting"] else -1
		# The movement phase owns contact sweeps and runs transit before ordinary
		# actors. In the blocked case the obstruction later really walks away.
		suite._movement_tick(sim)
		ticks += 1
		saw_riding = saw_riding or connection.phase=="riding"
		saw_alighting = saw_alighting or connection.phase=="alighting"
		safe = safe and _safe_positions(sim,movement)
		var previous_head: Vector2 = ConvoyTrail.point(previous_points[-1])
		var head: Vector2 = ConvoyTrail.point(movement.convoy.points[-1])
		bounded = bounded and previous_head.distance_to(head)<=sim.space.walking_speed(world.facts.actors.leader)*WorldState.TICK_SECONDS+0.0001
		var error: String = world.validate(suite.content)
		if first_error.is_empty() and not error.is_empty(): first_error = error
		if old_phase==connection.phase and remaining>0 and old_phase in ["boarding","alighting"] and not (blocked and old_phase=="alighting"):
			remainder_ok = remainder_ok and HospitalTransit._unit_phase_ticks(sim.space,world,connection,"leader",old_phase,true)==remaining-1
		if blocked and connection.phase=="riding" and not failure_committed:
			connection.pending_failure = true
			failure_committed = true
		if blocked and connection.phase=="alighting" and movement.convoy.points==previous_points and previous_cursor==int(movement.convoy.portal.cursor):
			stalled = true
			stall_ticks += 1
			unknown_quote = unknown_quote or not HospitalTransit._prefix(sim.space,world,connection,"outside_query").ok
			if stall_ticks==4:
				released_blocker = sim.space.request_move(world,"blocker",2,[42,82]).is_empty()
		if connection.phase=="idle": break
	var completed: bool = connection.phase=="idle" and not movement.convoy.has("portal") and world.facts.actors.leader.location.kind=="floor" and int(world.facts.actors.leader.location.floor_id)==2 and sim.space.at(world,"leader",2,seeded.plan.egress)
	var use_count: int = connection.get("use_receipts",{}).size()
	var expected_ticks: int = int(seeded.plan.boarding_ticks)+HospitalTransit._travel_ticks(sim.space,connection,1,2,true)+int(seeded.plan.alighting_ticks)
	var checks: Dictionary = {"fit":fit.ok,"quote":quote.ok,"legal_input":initial_validation.is_empty(),"began":began,"no_boarding_teleport":no_teleport,"bounded_real_steps":bounded,"safe_members":safe,"valid_each_tick":first_error.is_empty(),"rode":saw_riding,"alighted":saw_alighting,"completed":completed,"remaining_quotes_match_unblocked_steps":remainder_ok,"one_use_receipt":use_count==1,"one_wear_debit":is_equal_approx(float(connection.condition),maxf(0.0,before_condition-wear))}
	if blocked:
		checks.blocked_and_kept_ownership = stalled
		checks.unknown_quote = unknown_quote
		checks.blocker_really_walked_away = released_blocker
		checks.committed_ride_finished_before_failure = failure_committed and bool(connection.failed) and not bool(connection.pending_failure)
	else:
		checks.exact_quote_ticks = ticks==expected_ticks and int(quote.group_ticks)==expected_ticks
	var result: Dictionary = {"ok":_all(checks),"case":"blocked_ride" if blocked else "real_ride","checks":checks,"ticks":ticks,"expected_unblocked_ticks":expected_ticks,"first_validation_error":first_error,"phase":connection.phase,"waiting_reason":movement.get("waiting_reason",""),"leader":world.facts.actors.leader.location.duplicate(true),"follower":world.facts.actors.follower.location.duplicate(true)}
	sim.dispose()
	return result

func _admission() -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	var world: WorldState = sim.world
	var connection: Dictionary = world.facts.connectors[suite._connection(sim)]
	var seeded: Dictionary = _seed(sim,connection,1,2,2,Vector2.RIGHT)
	if not seeded.ok:
		sim.dispose()
		return {"ok":false,"case":"admission","reason":seeded.reason}
	var movement: Dictionary = seeded.movement
	var before_actors: Dictionary = world.facts.actors.duplicate(true)
	var before_connection: Dictionary = connection.duplicate(true)
	HospitalTransit.begin(sim.space,world,world.facts.actors.leader,movement,seeded.segment)
	var checks: Dictionary = {"misalignment_blocks":not HospitalTransit._convoy_entry_aligned(movement.convoy,seeded.plan),"no_ticket":not movement.has("transit_ticket"),"no_actor_changes":before_actors==world.facts.actors,"no_connector_changes":before_connection==connection,"reason":not str(movement.get("waiting_reason","")).is_empty()}
	sim.dispose()
	return {"ok":_all(checks),"case":"admission","checks":checks}

func _stairs() -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._history_height(sim,2)
	var built: CommandResult = suite._command(sim,"connector_build",{"definition_id":"VC01","floor_id":1,"cell":[36,72]})
	if not built.accepted:
		sim.dispose()
		return {"ok":false,"case":"stairs_capacity","reason":"fixture"}
	var world: WorldState = sim.world
	var connection: Dictionary = world.facts.connectors[suite._connection(sim)]
	suite._add_actor(sim,"leader","S49",connection.anchor)
	suite._add_actor(sim,"follower","S49",[connection.anchor[0],connection.anchor[1]+2])
	var created: Dictionary = ConvoyTrail.create(sim.space,world,"leader",["leader","follower"])
	var m: Dictionary = {"actor_id":"leader","members":["leader","follower"],"convoy":created.convoy,"path":[],"cursor":0,"travelled":[],"target_floor":2,"target_cell":connection.anchor.duplicate(),"blocked_since":-1,"yielding":false}
	world.facts.moves["leader"] = m
	var before: Dictionary = world.facts.actors.duplicate(true)
	var fit: Dictionary = HospitalTransit.fits(sim.space,world,connection,"leader",m.members)
	HospitalTransit.begin(sim.space,world,world.facts.actors.leader,m,{"kind":"connector","connector_id":connection.id,"from":1,"to":2})
	var checks: Dictionary = {"pair_cannot_fit":not fit.ok,"no_ticket":not m.has("transit_ticket"),"not_boarded":connection.phase=="idle","no_teleport":before==world.facts.actors}
	sim.dispose()
	return {"ok":_all(checks),"case":"stairs_capacity","checks":checks}

func _solo() -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	var world: WorldState = sim.world
	var connection: Dictionary = world.facts.connectors[suite._connection(sim)]
	suite._add_actor(sim,"solo","S49",connection.anchor)
	var requested: String = sim.space.request_move(world,"solo",2,[44,82])
	var rode: bool = false
	var arrived: bool = false
	var first_error: String = ""
	var ticks: int = 0
	for index: int in 600:
		suite._movement_tick(sim)
		ticks += 1
		rode = rode or world.facts.actors.solo.location.kind=="transit"
		var error: String = world.validate(suite.content)
		if first_error.is_empty() and not error.is_empty(): first_error = error
		if sim.space.at(world,"solo",2,[44,82]) and not world.facts.moves.has("solo"):
			arrived = true
			break
	var result: Dictionary = {"ok":requested.is_empty() and rode and arrived and first_error.is_empty(),"case":"solo_control","request_error":requested,"rode":rode,"arrived":arrived,"first_validation_error":first_error,"ticks":ticks}
	sim.dispose()
	return result

func _cancel_empty_ride() -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	var world: WorldState = sim.world
	var connection: Dictionary = world.facts.connectors[suite._connection(sim)]
	connection.floor_id = 2
	var seeded: Dictionary = _seed(sim,connection)
	if not seeded.ok:
		sim.dispose()
		return {"ok":false,"case":"cancel_empty_ride","reason":seeded.reason}
	HospitalTransit.begin(sim.space,world,world.facts.actors.leader,seeded.movement,seeded.segment)
	var began_empty: bool = connection.phase=="empty_riding" and seeded.movement.has("transit_ticket")
	var before_actors: Dictionary = world.facts.actors.duplicate(true)
	var before_remaining: int = connection.remaining_ticks
	sim.space.cancel_ground_move(world,"leader")
	var cancellation: bool = connection.phase=="empty_riding" and int(connection.remaining_ticks)==before_remaining and not connection.has("assigned_actor_id") and not world.facts.moves.has("leader")
	var ticks: int = 0
	var valid: bool = true
	for index: int in 100:
		suite._movement_tick(sim)
		ticks += 1
		valid = valid and world.validate(suite.content).is_empty()
		if connection.phase=="idle": break
	var checks: Dictionary = {"empty_trip_started":began_empty,"cancel_keeps_committed_empty_trip":cancellation,"arrived_on_original_empty_target":connection.phase=="idle" and int(connection.floor_id)==1,"exact_remaining_ticks":ticks==before_remaining,"no_fictitious_passengers":world.facts.actors==before_actors and connection.riders.is_empty(),"no_use_receipt":connection.use_receipts.is_empty(),"valid":valid}
	sim.dispose()
	return {"ok":_all(checks),"case":"cancel_empty_ride","checks":checks,"ticks":ticks}

func _solo_stairs() -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._history_height(sim,2)
	var built: CommandResult = suite._command(sim,"connector_build",{"definition_id":"VC01","floor_id":1,"cell":[36,72]})
	if not built.accepted:
		sim.dispose()
		return {"ok":false,"case":"solo_convoy_stairs","reason":"fixture"}
	var world: WorldState = sim.world
	var connection: Dictionary = world.facts.connectors[suite._connection(sim)]
	suite._add_actor(sim,"leader","S49",connection.anchor)
	var created: Dictionary = ConvoyTrail.create(sim.space,world,"leader",["leader"])
	var segment: Dictionary = {"kind":"connector","connector_id":connection.id,"from":1,"to":2}
	var movement: Dictionary = {"actor_id":"leader","members":["leader"],"convoy":created.convoy,"path":[segment],"cursor":0,"travelled":[],"target_floor":2,"target_cell":connection.anchor.duplicate(),"blocked_since":-1,"yielding":false}
	world.facts.moves["leader"] = movement
	sim.space._sync_convoys(world)
	HospitalTransit.begin(sim.space,world,world.facts.actors.leader,movement,segment)
	var boarded: bool = world.facts.actors.leader.location.kind=="transit"
	var valid: bool = true
	var ticks: int = 0
	for index: int in 100:
		suite._movement_tick(sim)
		ticks += 1
		valid = valid and world.validate(suite.content).is_empty()
		if connection.phase=="idle": break
	var checks: Dictionary = {"boarded":boarded,"valid":valid,"arrived":sim.space.at(world,"leader",2,connection.anchor),"original_stair_time":ticks==25,"no_lift_use_receipt":connection.use_receipts.is_empty(),"trail_rebound_on_target_floor":int(movement.convoy.floor_id)==2 and movement.convoy.points.size()==1 and ConvoyTrail.point(movement.convoy.points[0]).distance_to(ConvoyTrail.point(connection.anchor))<0.001}
	sim.dispose()
	return {"ok":_all(checks),"case":"solo_convoy_stairs","checks":checks,"ticks":ticks}

func _journey_restore() -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	var world: WorldState = sim.world
	suite._add_actor(sim,"leader","S49",[36,84])
	suite._add_actor(sim,"follower","S49",[36,86])
	var requested: String = sim.space.request_group_move(world,"leader",["leader","follower"],{},2,[44,82])
	var restored: Dictionary = {}
	var valid: bool = true
	var first_error: String = ""
	var safe: bool = true
	var bounded: bool = true
	var arrived: bool = false
	var ticks: int = 0
	var last_reason: String = ""
	var last_phase: String = ""
	var last_journey: Dictionary = {}
	for index: int in 800:
		var actor: Dictionary = world.facts.actors.leader
		var previous_cell: Array = actor.location.get("queue_cell",actor.location.get("cell",[])).duplicate()
		suite._movement_tick(sim)
		ticks += 1
		actor = world.facts.actors.leader
		var next_cell: Array = actor.location.get("queue_cell",actor.location.get("cell",[]))
		bounded = bounded and ConvoyTrail.point(previous_cell).distance_to(ConvoyTrail.point(next_cell))<=sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001
		var error: String = world.validate(suite.content)
		if first_error.is_empty() and not error.is_empty(): first_error = error
		valid = valid and error.is_empty()
		var movement: Dictionary = world.facts.moves.get("leader",{})
		last_journey = movement.duplicate(true)
		last_reason = str(movement.get("waiting_reason",""))
		if movement.has("convoy"): safe = safe and _safe_positions(sim,movement)
		var connection: Dictionary = world.facts.connectors[suite._connection(sim)]
		last_phase = connection.phase
		if connection.phase in ["boarding","riding","alighting"] and not restored.has(connection.phase):
			var phase: String = connection.phase
			var frozen: Dictionary = world.freeze()
			var replacement: WorldState = WorldState.new(frozen)
			var restore_error: String = replacement.validate(suite.content)
			if first_error.is_empty() and not restore_error.is_empty(): first_error = restore_error
			valid = valid and restore_error.is_empty()
			sim.dispose()
			sim = HospitalSimulation.new(replacement,suite.content)
			world = sim.world
			restored[phase] = true
		if sim.space.at(world,"leader",2,[44,82]) and not world.facts.moves.has("leader"):
			arrived = true
			break
	var checks: Dictionary = {"request_accepted":requested.is_empty(),"real_final_goal":arrived,"all_transit_stages_restored":restored.size()==3,"world_valid":valid,"no_member_overlap":safe,"every_step_within_leader_budget":bounded}
	var result: Dictionary = {"ok":_all(checks),"case":"cross_floor_journey_restore","checks":checks,"ticks":ticks,"first_error":first_error,"request_error":requested,"restored":restored,"last_phase":last_phase,"last_waiting_reason":last_reason,"leader":world.facts.actors.leader.location.duplicate(true),"follower":world.facts.actors.follower.location.duplicate(true),"remaining":last_journey}
	sim.dispose()
	return result

func _rotated_connectors() -> Dictionary:
	var rows: Array = []
	var ok: bool = true
	for definition_id: String in ["VC01","VC02","VC03"]:
		for rotation: int in 4:
			var sim: HospitalSimulation = suite._fixture()
			suite._history_height(sim,2)
			var built: CommandResult = suite._command(sim,"connector_build",{"definition_id":definition_id,"floor_id":1,"cell":[44,76],"rotation":rotation})
			if not built.accepted:
				rows.append({"ok":false,"definition":definition_id,"rotation":rotation,"build":built.to_record()})
				ok = false
				sim.dispose()
				continue
			var world: WorldState = sim.world
			var connection: Dictionary = world.facts.connectors[suite._connection(sim)]
			var definition: Dictionary = suite.content.definition("vertical_connectors",definition_id)
			var extended: bool = true
			if definition.kind=="lift": extended = suite._command(sim,"connector_extend",{"connection_id":connection.id,"floor_id":2}).accepted
			# A command replaces facts, so reacquire the actual committed record.
			connection = world.facts.connectors[suite._connection(sim)]
			var extent: int = int(definition.max_clearance_cells)
			var shaft: Rect2 = Rect2(ConvoyTrail.point(connection.cell),ConvoyTrail.point(connection.footprint))
			var ports_clear: bool = not shaft.intersects(Rect2(ConvoyTrail.point(connection.anchor),Vector2.ONE*extent),false)
			if definition.kind=="lift": ports_clear = ports_clear and not shaft.intersects(Rect2(ConvoyTrail.point(connection.repair_cell),Vector2.ONE*extent),false)
			var validation: String = world.validate(suite.content)
			var legs: Array = []
			var actual: bool = true
			if definition_id=="VC02" and extended:
				var inward: Vector2 = Vector2.UP.rotated(float(rotation)*PI*0.5).round()
				var side: Vector2 = Vector2.RIGHT.rotated(float(rotation)*PI*0.5).round()
				suite._add_actor(sim,"leader","S49",connection.anchor)
				suite._add_actor(sim,"follower","S49",connection.anchor)
				var form: Dictionary = ConvoyTrail.formation(sim.space,world,"leader",["leader","follower"],inward)
				var shape: Dictionary = {"size":form.size,"height":form.height,"shift":form.shift,"spacing":form.spacing,"centers":form.centers,"points":[connection.anchor.duplicate()]}
				var plan: Dictionary = ConvoyPortal.plan(sim.space,world,connection,"leader",["leader","follower"],shape)
				if not plan.ok:
					actual = false
				else:
					# Legal fixture positions before requesting movement. Both
					# legs thereafter use only real production movement.
					var entry: Vector2 = ConvoyTrail.point(plan.entry)
					var start: Vector2 = entry-inward*6.0
					var follower: Vector2 = start-inward*float(form.spacing)
					world.facts.actors.leader.location.cell = [start.x,start.y]
					world.facts.actors.follower.location.cell = [follower.x,follower.y]
					sim.space.sync_actor(world,"leader")
					sim.space.sync_actor(world,"follower")
					var goal: Vector2 = entry-inward*8.0+side*6.0
					legs.append(_drive_rotated_leg(sim,2,[goal.x,goal.y]))
					if legs[-1].ok: legs.append(_drive_rotated_leg(sim,1,[start.x,start.y]))
					actual = legs.size()==2 and legs[0].ok and legs[1].ok
			var passed: bool = extended and ports_clear and validation.is_empty() and actual
			ok = ok and passed
			rows.append({"ok":passed,"definition":definition_id,"rotation":rotation,"built":built.accepted,"extended":extended,"ports_outside_shaft":ports_clear,"validation":validation,"anchor":connection.anchor.duplicate(),"repair_cell":connection.repair_cell.duplicate(),"legs":legs})
			sim.dispose()
	return {"ok":ok,"case":"real_rotated_connector_roundtrips","rows":rows}

func _drive_rotated_leg(sim: HospitalSimulation, floor_id: int, goal: Array) -> Dictionary:
	var world: WorldState = sim.world
	var requested: String = sim.space.request_group_move(world,"leader",["leader","follower"],{},floor_id,goal)
	if not requested.is_empty(): return {"ok":false,"request":requested,"goal":goal,"floor_id":floor_id}
	var first_error: String = ""
	var safe: bool = true
	var bounded: bool = true
	var arrived: bool = false
	var first_board_tick: int = -1
	var exit_tick: int = -1
	var expected_transit: int = -1
	var ticks: int = 0
	var last_journey: Dictionary = {}
	for index: int in 900:
		var leader: Dictionary = world.facts.actors.leader
		var before: Array = leader.location.get("queue_cell",leader.location.get("cell",[])).duplicate()
		suite._movement_tick(sim)
		ticks += 1
		leader = world.facts.actors.leader
		var after: Array = leader.location.get("queue_cell",leader.location.get("cell",[]))
		bounded = bounded and ConvoyTrail.point(before).distance_to(ConvoyTrail.point(after))<=sim.space.walking_speed(leader)*WorldState.TICK_SECONDS+0.0001
		var error: String = world.validate(suite.content)
		if first_error.is_empty() and not error.is_empty(): first_error = error
		var m: Dictionary = world.facts.moves.get("leader",{})
		last_journey = m.duplicate(true)
		if m.has("convoy"): safe = safe and _safe_positions(sim,m)
		var connection: Dictionary = world.facts.connectors[suite._connection(sim)]
		if first_board_tick<0 and connection.phase=="boarding":
			first_board_tick = ticks
			var p: Dictionary = m.convoy.portal.plan
			expected_transit = int(p.boarding_ticks)+HospitalTransit._travel_ticks(sim.space,connection,int(connection.from),int(connection.to),true)+int(p.alighting_ticks)
		if first_board_tick>=0 and exit_tick<0 and connection.phase=="idle": exit_tick = ticks
		if sim.space.at(world,"leader",floor_id,goal) and not world.facts.moves.has("leader"):
			arrived = true
			break
	var exact: bool = first_board_tick>=0 and exit_tick-first_board_tick==expected_transit
	return {"ok":arrived and safe and bounded and first_error.is_empty() and exact,"floor_id":floor_id,"goal":goal,"ticks":ticks,"arrived":arrived,"safe":safe,"bounded":bounded,"validation":first_error,"transit_ticks":exit_tick-first_board_tick,"expected_transit_ticks":expected_transit,"remaining":last_journey,"leader":world.facts.actors.leader.location.duplicate(true)}

func _inflight_return() -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	var world: WorldState = sim.world
	suite._add_actor(sim,"leader","S49",[36,84])
	suite._add_actor(sim,"follower","S49",[36,86])
	var request: String = sim.space.request_group_move(world,"leader",["leader","follower"],{},2,[44,82])
	var retargeted: bool = false
	var preserved: bool = false
	var arrived: bool = false
	var safe: bool = true
	var bounded: bool = true
	var first_error: String = ""
	var retarget_error: String = ""
	var last_journey: Dictionary = {}
	var ticks: int = 0
	for index: int in 900:
		var actor: Dictionary = world.facts.actors.leader
		var previous: Array = actor.location.get("queue_cell",actor.location.get("cell",[])).duplicate()
		suite._movement_tick(sim)
		ticks += 1
		actor = world.facts.actors.leader
		var current: Array = actor.location.get("queue_cell",actor.location.get("cell",[]))
		bounded = bounded and ConvoyTrail.point(previous).distance_to(ConvoyTrail.point(current))<=sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001
		var validation: String = world.validate(suite.content)
		if first_error.is_empty() and not validation.is_empty(): first_error = validation
		var m: Dictionary = world.facts.moves.get("leader",{})
		if m.has("convoy"): safe = safe and _safe_positions(sim,m)
		var connection: Dictionary = world.facts.connectors[suite._connection(sim)]
		if not retargeted and connection.phase=="riding":
			var before: Dictionary = connection.duplicate(true)
			var before_trail: Dictionary = m.convoy.duplicate(true)
			retarget_error = sim.space.request_group_move(world,"leader",["leader","follower"],{},1,[36,84])
			preserved = connection==before and m.convoy==before_trail
			retargeted = true
		last_journey = m.duplicate(true)
		if retargeted and sim.space.at(world,"leader",1,[36,84]) and not world.facts.moves.has("leader"):
			arrived = true
			break
	var result: Dictionary = {"ok":request.is_empty() and retargeted and retarget_error.is_empty() and preserved and arrived and safe and bounded and first_error.is_empty(),"case":"inflight_return_floor_retarget","request":request,"retargeted":retargeted,"retarget_error":retarget_error,"committed_ride_preserved":preserved,"arrived":arrived,"safe":safe,"bounded":bounded,"validation":first_error,"ticks":ticks,"remaining":last_journey,"leader":world.facts.actors.leader.location.duplicate(true)}
	sim.dispose()
	return result

func _opposing_queues() -> Dictionary:
	var sim: HospitalSimulation=suite._transit_fixture()
	var world: WorldState=sim.world
	for floor_id: int in [1,2]:
		var id: String="a" if floor_id==1 else "b"
		suite._add_actor(sim,id,"S49",[36,76],floor_id)
		suite._add_actor(sim,id+"f","S49",[36,78],floor_id)
	var a: String=sim.space.request_group_move(world,"a",["a","af"],{},2,[44,82])
	var b: String=sim.space.request_group_move(world,"b",["b","bf"],{},1,[44,82])
	var first_error: String=""
	var safe: bool=true
	var bounded: bool=true
	var preserved_ticket: bool=true
	var ticket: int=-1
	var stood_aside: bool=false
	var aside_quote_unknown: bool=false
	var arrived: bool=false
	var ticks: int=0
	for index: int in 900:
		var before: Dictionary={}
		for id: String in ["a","af","b","bf"]:
			var actor: Dictionary=world.facts.actors[id]
			before[id]=actor.location.get("queue_cell",actor.location.get("cell",[])).duplicate()
		suite._movement_tick(sim)
		ticks+=1
		for id: String in ["a","af","b","bf"]:
			var actor: Dictionary=world.facts.actors[id]
			var cell: Array=actor.location.get("queue_cell",actor.location.get("cell",[]))
			bounded=bounded and ConvoyTrail.point(before[id]).distance_to(ConvoyTrail.point(cell))<=sim.space.walking_speed(world.facts.actors.a if id in ["a","af"] else world.facts.actors.b)*WorldState.TICK_SECONDS+0.0001
		for m: Dictionary in world.facts.moves.values():
			if m.has("convoy"): safe=safe and _safe_positions(sim,m)
		var validation: String=world.validate(suite.content)
		if first_error.is_empty() and not validation.is_empty(): first_error=validation
		var second: Dictionary=world.facts.moves.get("b",{})
		if second.has("transit_ticket"):
			if ticket<0: ticket=int(second.transit_ticket.sequence)
			preserved_ticket=preserved_ticket and ticket==int(second.transit_ticket.sequence)
			stood_aside=stood_aside or not sim.space.at(world,"b",2,[36,76])
			if stood_aside: aside_quote_unknown=aside_quote_unknown or HospitalTransit._prefix(sim.space,world,world.facts.connectors[suite._connection(sim)],"other").get("status","")=="estimate_unknown"
		if sim.space.at(world,"a",2,[44,82]) and sim.space.at(world,"b",1,[44,82]) and not world.facts.moves.has("a") and not world.facts.moves.has("b"):
			arrived=true
			break
	var result: Dictionary={"ok":a.is_empty() and b.is_empty() and arrived and safe and bounded and first_error.is_empty() and stood_aside and preserved_ticket and ticket==2 and aside_quote_unknown,"case":"opposing_queues","request_a":a,"request_b":b,"arrived":arrived,"safe":safe,"bounded":bounded,"validation":first_error,"stood_aside":stood_aside,"aside_quote_unknown":aside_quote_unknown,"preserved_ticket":preserved_ticket,"ticket":ticket,"ticks":ticks,"remaining":world.facts.moves.duplicate(true),"connection":world.facts.connectors[suite._connection(sim)].duplicate(true)}
	sim.dispose()
	return result

func _plan_cache() -> Dictionary:
	var sim: HospitalSimulation=suite._transit_fixture()
	var world: WorldState=sim.world
	var connection: Dictionary=world.facts.connectors[suite._connection(sim)]
	var seeded: Dictionary=_seed(sim,connection)
	if not seeded.ok:
		sim.dispose()
		return {"ok":false,"case":"portal_plan_cache","reason":seeded.reason}
	var m: Dictionary=seeded.movement
	if sim.space.has_meta("convoy_portal_plan_cache"): sim.space.remove_meta("convoy_portal_plan_cache")
	sim.space.query_counts["convoy_portal_plan_builds"]=0
	sim.space.query_counts["convoy_portal_plan_hits"]=0
	var expected: Dictionary=ConvoyPortal._build_plan(sim.space,world,connection,"leader",m.members,m.convoy)
	var first: Dictionary=ConvoyPortal.plan(sim.space,world,connection,"leader",m.members,m.convoy)
	var same: bool=first==expected
	first.boarding[0][0]+=99.0
	var isolated: bool=ConvoyPortal.plan(sim.space,world,connection,"leader",m.members,m.convoy)==expected
	var start: int=Time.get_ticks_usec()
	for index: int in 1000:
		same=same and ConvoyPortal.plan(sim.space,world,connection,"leader",m.members,m.convoy)==expected
	var cached_us: int=Time.get_ticks_usec()-start
	var one_build: bool=int(sim.space.query_counts.convoy_portal_plan_builds)==1
	start=Time.get_ticks_usec()
	for index: int in 1000:
		same=same and ConvoyPortal._build_plan(sim.space,world,connection,"leader",m.members,m.convoy)==expected
	var uncached_us: int=Time.get_ticks_usec()-start
	var variants: Array=[]
	var rotated: Dictionary=connection.duplicate(true)
	rotated.rotation=1
	variants.append([rotated,m.convoy])
	var moved: Dictionary=connection.duplicate(true)
	moved.cell=[40,72]
	variants.append([moved,m.convoy])
	var spaced: Dictionary=m.convoy.duplicate(true)
	spaced.spacing=3.0
	variants.append([connection,spaced])
	var raised: Dictionary=m.convoy.duplicate(true)
	raised.height=3.3
	variants.append([connection,raised])
	var invalidated: bool=true
	for variant: Array in variants:
		var builds: int=int(sim.space.query_counts.convoy_portal_plan_builds)
		var actual: Dictionary=ConvoyPortal.plan(sim.space,world,variant[0],"leader",m.members,variant[1])
		invalidated=invalidated and int(sim.space.query_counts.convoy_portal_plan_builds)==builds+1 and actual==ConvoyPortal._build_plan(sim.space,world,variant[0],"leader",m.members,variant[1])
	# Different primary speed is an input even when this pure geometry probe
	# deliberately reuses an envelope. This does not issue a movement request.
	var original_species: String=world.facts.actors.leader.species_id
	var builds: int=int(sim.space.query_counts.convoy_portal_plan_builds)
	world.facts.actors.leader.species_id="S59"
	var slower: Dictionary=ConvoyPortal.plan(sim.space,world,connection,"leader",m.members,m.convoy)
	var speed_invalidated: bool=int(sim.space.query_counts.convoy_portal_plan_builds)==builds+1 and slower==ConvoyPortal._build_plan(sim.space,world,connection,"leader",m.members,m.convoy)
	world.facts.actors.leader.species_id=original_species
	var second: HospitalSpace=HospitalSpace.new(suite.content)
	var separate: bool=ConvoyPortal.plan(second,world,connection,"leader",m.members,m.convoy)==expected and int(second.query_counts.get("convoy_portal_plan_builds",0))==1
	var result: Dictionary={"ok":same and isolated and one_build and invalidated and speed_invalidated and separate,"case":"portal_plan_cache","identical_results":same,"returned_copy_isolated":isolated,"one_build_for_repeats":one_build,"geometry_envelope_invalidated":invalidated,"speed_invalidated":speed_invalidated,"runtime_ownership_isolated":separate,"cached_1000_us":cached_us,"uncached_1000_us":uncached_us,"ratio":float(cached_us)/maxi(1,uncached_us)}
	sim.dispose()
	return result

func _mixed_queues() -> Dictionary:
	var rows: Array=[]
	var all_ok: bool=true
	for incoming_convoy: bool in [true,false]:
		var sim: HospitalSimulation=suite._transit_fixture()
		var world: WorldState=sim.world
		var ids: Array=["a","b","af" if incoming_convoy else "bf"]
		suite._add_actor(sim,"a","S49",[36,76],1)
		suite._add_actor(sim,"b","S49",[36,76],2)
		suite._add_actor(sim,"af" if incoming_convoy else "bf","S49",[36,78],1 if incoming_convoy else 2)
		var a: String=sim.space.request_group_move(world,"a",["a","af"],{},2,[44,82]) if incoming_convoy else sim.space.request_move(world,"a",2,[44,82])
		var b: String=sim.space.request_move(world,"b",1,[44,82]) if incoming_convoy else sim.space.request_group_move(world,"b",["b","bf"],{},1,[44,82])
		var first_error: String=""
		var safe: bool=true
		var bounded: bool=true
		var arrived: bool=false
		var ticks: int=0
		for index: int in 600:
			var before: Dictionary={}
			for id: String in ids:
				var actor: Dictionary=world.facts.actors[id]
				if (id=="a" and incoming_convoy) or (id=="b" and not incoming_convoy): before[id]=actor.location.get("queue_cell",actor.location.get("cell",[])).duplicate()
			suite._movement_tick(sim)
			ticks+=1
			for id: String in before:
				var actor: Dictionary=world.facts.actors[id]
				var cell: Array=actor.location.get("queue_cell",actor.location.get("cell",[]))
				bounded=bounded and ConvoyTrail.point(before[id]).distance_to(ConvoyTrail.point(cell))<=sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001
			for m: Dictionary in world.facts.moves.values():
				if m.has("convoy"): safe=safe and _safe_positions(sim,m)
			var validation: String=world.validate(suite.content)
			if first_error.is_empty() and not validation.is_empty(): first_error=validation
			if sim.space.at(world,"a",2,[44,82]) and sim.space.at(world,"b",1,[44,82]) and not world.facts.moves.has("a") and not world.facts.moves.has("b"):
				arrived=true
				break
		var ok: bool=a.is_empty() and b.is_empty() and safe and bounded and arrived and first_error.is_empty()
		all_ok=all_ok and ok
		rows.append({"ok":ok,"incoming_convoy":incoming_convoy,"arrived":arrived,"safe":safe,"convoy_bounded":bounded,"validation":first_error,"ticks":ticks,"remaining":world.facts.moves.duplicate(true)})
		sim.dispose()
	return {"ok":all_ok,"case":"mixed_solo_convoy_transit","rows":rows}
