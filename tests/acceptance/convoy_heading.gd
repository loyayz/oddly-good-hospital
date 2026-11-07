extends "res://tests/acceptance/convoy_transit.gd"

# Focused singleton publication regression. Expected headings come from actual
# actor displacements, never ConvoyTrail.positions or stored trail samples.
func _run() -> void:
	suite.content=HospitalContent.new()
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var rows: Array=[]
	for name: String in ["ground","zero","blocked","portal"]:
		if args.size()>1 and not name in args[1].split(","): continue
		match name:
			"ground": rows.append(_ground_heading())
			"zero": rows.append(_stationary_heading(false))
			"blocked": rows.append(_stationary_heading(true))
			"portal": rows.append(_portal_heading())
	var ok: bool=not rows.is_empty()
	for row: Dictionary in rows:
		print(JSON.stringify(row))
		ok=ok and row.ok
	var result: Dictionary={"ok":ok,"rows":rows,"scope":"Actual singleton heading publication and frozen-world rebind; no performance, full-suite, or native persistence claim"}
	if not args.is_empty(): FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	quit(0 if ok else 1)

func _heading_matches(facing: float, delta: Vector2) -> bool:
	return absf(wrapf(facing-atan2(delta.x,delta.y),-PI,PI))<0.0001

func _ground_heading() -> Dictionary:
	var sim: HospitalSimulation=suite._fixture()
	suite._add_actor(sim,"leader","S49",[54,72])
	var world: WorldState=sim.world
	world.facts.actors.leader.facing=-PI*0.5
	sim.space.sync_actor(world,"leader")
	var errors: Array=[]
	var directions: Dictionary={}
	var ticks: int=0
	var moving_ticks: int=0
	var turns: int=0
	var previous_direction: Vector2=Vector2.ZERO
	var restored: bool=false
	var goals: int=0
	for goal: Array in [[58,76],[54,76],[54,72]]:
		var request: String=sim.space.request_group_move(world,"leader",["leader"],{},1,goal)
		if not request.is_empty(): errors.append(request);break
		for index: int in 150:
			var actor: Dictionary=world.facts.actors.leader
			var before: Vector2=ConvoyTrail.point(actor.location.cell)
			var old_facing: float=float(actor.facing)
			var checks: int=int(sim.space.query_counts.get("convoy_leader_checks",0))
			suite._movement_tick(sim)
			ticks+=1
			actor=world.facts.actors.leader
			var delta: Vector2=ConvoyTrail.point(actor.location.cell)-before
			var attempts: int=int(sim.space.query_counts.get("convoy_leader_checks",0))-checks
			if attempts>1 or delta.length()>sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001: errors.append("Leader permission or walking budget exceeded")
			if delta.length()>0.000001:
				moving_ticks+=1
				if attempts!=1 or not _heading_matches(float(actor.facing),delta): errors.append("Heading differs from actual ground tangent")
				var direction: Vector2=delta.normalized()
				directions[str(direction)]=true
				if previous_direction!=Vector2.ZERO and not previous_direction.is_equal_approx(direction): turns+=1
				previous_direction=direction
			else:
				if float(actor.facing)!=old_facing: errors.append("Stationary ground actor changed heading")
			var validation: String=world.validate(suite.content)
			if not validation.is_empty(): errors.append(validation)
			if not restored and delta.y>0.001:
				var saved: Dictionary=world.freeze()
				var facing: float=float(actor.facing)
				sim.dispose()
				sim=HospitalSimulation.new(WorldState.new(saved),suite.content)
				world=sim.world
				restored=float(world.facts.actors.leader.facing)==facing and world.validate(suite.content).is_empty()
				if not restored: errors.append("Frozen-world heading did not survive fresh runtime")
			if not errors.is_empty() or not world.facts.moves.has("leader"): break
		if sim.space.at(world,"leader",1,goal) and not world.facts.moves.has("leader"): goals+=1
		if not errors.is_empty(): break
	var result: Dictionary={"case":"singleton_ground_heading","ok":errors.is_empty() and goals==3 and directions.size()==4 and turns==3 and restored,"errors":errors,"goals":goals,"directions":directions.keys(),"turns":turns,"moving_ticks":moving_ticks,"ticks":ticks,"fresh_runtime_restore":restored}
	sim.dispose()
	return result

func _stationary_heading(blocked: bool) -> Dictionary:
	var sim: HospitalSimulation=suite._fixture()
	suite._add_actor(sim,"leader","S49",[54,72])
	var world: WorldState=sim.world
	world.facts.actors.leader.facing=-PI*0.5
	sim.space.sync_actor(world,"leader")
	var request: String=sim.space.request_group_move(world,"leader",["leader"],{},1,[58,72])
	if not request.is_empty(): sim.dispose();return {"case":"singleton_stationary_heading","ok":false,"reason":request}
	var movement: Dictionary=world.facts.moves.leader
	# A legal reached checkpoint immediately before the next waypoint. This
	# tests the publication boundary directly, with no fabricated displacement.
	var segment: Dictionary={"kind":"floor","floor_id":1,"cell":[55,72] if blocked else [54,72]}
	movement.path=[segment,{"kind":"floor","floor_id":1,"cell":[58,72]}]
	movement.cursor=0
	movement.route_pending=false
	if blocked:
		suite._add_actor(sim,"blocker","S49",[55,72])
		var face: float=sim.space.body_rectangle(world.facts.actors.blocker).position.x
		world.facts.actors.blocker.location.cell[0]+=55.05-face
		sim.space.sync_actor(world,"blocker")
	var validation: String=world.validate(suite.content)
	var before: Dictionary=world.facts.actors.duplicate(true)
	var trail: Dictionary=movement.convoy.duplicate(true)
	var motion: HospitalMovement.MotionResult=sim.space.movement._move_step(world,world.facts.actors.leader,movement,segment)
	# Accepted publication normalizes integer coordinates to floats. Compare
	# the physical pose for zero motion; a rejected proposal must stay exact.
	var same_pose: bool=ConvoyTrail.point(before.leader.location.cell)==ConvoyTrail.point(world.facts.actors.leader.location.cell) and float(before.leader.facing)==float(world.facts.actors.leader.facing)
	var unchanged: bool=before==world.facts.actors and trail==movement.convoy if blocked else same_pose and ConvoyTrail.regions(trail)==ConvoyTrail.regions(movement.convoy)
	var after_validation: String=world.validate(suite.content)
	var result: Dictionary={"case":"singleton_blocked_heading" if blocked else "singleton_zero_motion_heading","ok":validation.is_empty() and after_validation.is_empty() and unchanged and motion.actual_motion==Vector2.ZERO and motion.blocked==blocked,"input_validation":validation,"output_validation":after_validation,"pose_and_trail_unchanged":unchanged,"blocked":motion.blocked,"actual_motion":[motion.actual_motion.x,motion.actual_motion.y]}
	sim.dispose()
	return result

func _portal_heading() -> Dictionary:
	var sim: HospitalSimulation=suite._transit_fixture()
	var world: WorldState=sim.world
	var connection: Dictionary=world.facts.connectors[suite._connection(sim)]
	var seeded: Dictionary=_seed(sim,connection,1,2,1)
	if not seeded.ok: sim.dispose();return {"case":"singleton_portal_heading","ok":false,"reason":seeded.reason}
	world.facts.actors.leader.facing=-PI*0.5
	sim.space.sync_actor(world,"leader")
	var entry: Array=world.facts.actors.leader.location.cell.duplicate()
	HospitalTransit.begin(sim.space,world,world.facts.actors.leader,seeded.movement,seeded.segment)
	var entered_unchanged: bool=connection.phase=="boarding" and world.facts.actors.leader.location.queue_cell==entry and float(world.facts.actors.leader.facing)==-PI*0.5
	var errors: Array=[]
	var restored: Dictionary={}
	var directions: Dictionary={}
	var moved_by_phase: Dictionary={}
	var ticks: int=0
	var last_facing: float=-PI*0.5
	for index: int in 150:
		var actor: Dictionary=world.facts.actors.leader
		var before: Vector2=ConvoyTrail.point(actor.location.get("queue_cell",actor.location.get("cell",[])))
		var old_phase: String=connection.phase
		var old_facing: float=float(actor.facing)
		var checks: int=int(sim.space.query_counts.get("convoy_leader_checks",0))
		suite._movement_tick(sim)
		ticks+=1
		actor=world.facts.actors.leader
		var delta: Vector2=ConvoyTrail.point(actor.location.get("queue_cell",actor.location.get("cell",[])))-before
		var attempts: int=int(sim.space.query_counts.get("convoy_leader_checks",0))-checks
		if attempts>1 or delta.length()>sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001: errors.append("Portal permission or walking budget exceeded")
		if delta.length()>0.000001:
			if attempts!=1 or not _heading_matches(float(actor.facing),delta): errors.append("Heading differs from actual portal tangent")
			directions[str(delta.normalized())]=true
			moved_by_phase[old_phase]=true
			last_facing=float(actor.facing)
		elif float(actor.facing)!=old_facing: errors.append("Stationary portal handoff changed heading")
		var validation: String=world.validate(suite.content)
		if not validation.is_empty(): errors.append(validation)
		if connection.phase in ["boarding","riding","alighting"] and not restored.has(connection.phase):
			var phase: String=connection.phase
			var saved: Dictionary=world.freeze()
			var facing: float=float(actor.facing)
			sim.dispose()
			sim=HospitalSimulation.new(WorldState.new(saved),suite.content)
			world=sim.world
			connection=world.facts.connectors[suite._connection(sim)]
			restored[phase]=float(world.facts.actors.leader.facing)==facing and world.validate(suite.content).is_empty()
			if not restored[phase]: errors.append("Portal heading did not survive fresh runtime")
		if not errors.is_empty() or connection.phase=="idle": break
	var exited: bool=connection.phase=="idle" and sim.space.at(world,"leader",2,seeded.plan.egress) and float(world.facts.actors.leader.facing)==last_facing
	var result: Dictionary={"case":"singleton_portal_heading","ok":errors.is_empty() and entered_unchanged and exited and directions.size()==2 and moved_by_phase.has("boarding") and moved_by_phase.has("alighting") and restored.size()==3,"errors":errors,"entry_preserves_pose":entered_unchanged,"actual_exit_preserves_heading":exited,"directions":directions.keys(),"moving_phases":moved_by_phase.keys(),"restored":restored,"ticks":ticks}
	sim.dispose()
	return result
