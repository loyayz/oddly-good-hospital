extends RefCounted

# Observe actual movement and the real local-route handoff; all collision,
# courtesy, search, FIFO and motion decisions still run in production code.
class ObservingMovement extends HospitalMovement:
	var contacts: Dictionary = {}
	var contact_attempts: Dictionary = {}
	var local_requests: int = 0
	var safety_failures: Array = []
	var body_index_drift: Array = []
	func _init(geometry: HospitalSpace) -> void:
		super(geometry)
	func _move_step(world: WorldState, actor: Dictionary, movement: Dictionary, segment: Dictionary) -> HospitalMovement.MotionResult:
		var result: HospitalMovement.MotionResult = super._move_step(world,actor,movement,segment)
		contacts[actor.id] = {"blocked":result.blocked,"actors":result.blocker_actor_ids.duplicate(),"actual":result.actual_motion}
		return result
	func _queue_local_route(world: WorldState, actor: Dictionary, movement: Dictionary) -> void:
		local_requests += 1
		super._queue_local_route(world,actor,movement)
	func _movement_contacts(world: WorldState, actor_id: String, floor_id: int, broad: Rect2, sweeps: Array[BodyIndex.Record], members: Array, result: HospitalMovement.MotionResult) -> void:
		# Copy numeric envelopes before committing this attempt. Records are
		# shared runtime scratch; retaining their references would lose evidence.
		var proposed: Dictionary = {}
		for sweep: BodyIndex.Record in sweeps:
			proposed[sweep.id] = {"from":_rectangle(sweep.sweep_from),"to":_rectangle(sweep.sweep_to)}
		var accepted: Dictionary = {}
		for id: String in _accepted_sweeps:
			var sweep: BodyIndex.Record = _accepted_sweeps[id]
			accepted[id] = {"from":_rectangle(sweep.sweep_from),"to":_rectangle(sweep.sweep_to)}
		super._movement_contacts(world,actor_id,floor_id,broad,sweeps,members,result)
		contact_attempts[actor_id] = {"proposed":proposed,"accepted_earlier":accepted,"actual_contact_ids":result.blocker_actor_ids.duplicate()}
	func _rectangle(rectangle: Rect2) -> Array:
		return [rectangle.position.x,rectangle.position.y,rectangle.size.x,rectangle.size.y]

func run(suite: RefCounted) -> Dictionary:
	var single: Dictionary = _occupied_goal(suite,false)
	var follower: Dictionary = _occupied_goal(suite,true)
	var gap: Dictionary = _group_gap(suite)
	var facing: Dictionary = _alternative_facing(suite)
	var sweep: Dictionary = _accepted_sweep_boundary(suite)
	return {"ok":single.ok and follower.ok and gap.ok and facing.ok and sweep.ok,"actual_occupied_destination":single,"actual_follower_destination":follower,"actual_midroute_obstacle_in_group_goal_gap":gap,"rectangular_body_alternative_arrival_facing":facing,"accepted_sweep_with_current_goal_clear":sweep}

func _occupied_goal(suite: RefCounted, group: bool) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var observer: ObservingMovement = ObservingMovement.new(sim.space)
	sim.space.movement = observer
	suite._add_actor(sim,"z_walker","S49",[40,82])
	if group: suite._add_actor(sim,"z_follower","S49",[40,85])
	var blocker_cell: Array = [44,85] if group else [44,82]
	suite._add_actor(sim,"a_blocker","S49",blocker_cell)
	var requested: String = sim.space.request_group_move(sim.world,"z_walker",["z_walker","z_follower"],{"z_walker":[0,0],"z_follower":[0,3]},1,[44,82]) if group else sim.space.request_move(sim.world,"z_walker",1,[44,82])
	var sequence: int = int(sim.world.facts.moves.get("z_walker",{}).get("request_sequence",-1))
	var original_target: bool = true
	var safe: bool = true
	for _tick: int in 100:
		safe = _physical_tick(suite,sim) and safe
		var move: Dictionary = sim.world.facts.moves.get("z_walker",{})
		original_target = original_target and move.get("target_cell",[])==[44,82] and int(move.get("request_sequence",-2))==sequence
	var occupied_waits: int = int(sim.space.query_counts.get("local_goal_occupied_waits",0))
	var dispatches: int = int(sim.space.query_counts.get("route_dispatches",0))
	var held_position: Array = sim.world.facts.actors.z_walker.location.cell.duplicate()
	var held_path: Array = sim.world.facts.moves.get("z_walker",{}).get("path",[]).duplicate(true)
	for _tick: int in 40: safe = _physical_tick(suite,sim) and safe
	var stable: bool = occupied_waits>0 and int(sim.space.query_counts.get("local_goal_occupied_waits",0))>occupied_waits and observer.local_requests==0 and int(sim.space.query_counts.get("route_dispatches",0))==dispatches and dispatches==1 and sim.world.facts.actors.z_walker.location.cell==held_position and sim.world.facts.moves.get("z_walker",{}).get("path",[])==held_path and int(sim.world.facts.moves.get("z_walker",{}).get("request_sequence",-2))==sequence
	# The blocking body leaves through real movement. A separate calculation
	# boundary below supplies an accepted sweep that really crosses this step.
	var leave: String = sim.space.request_move(sim.world,"a_blocker",1,[44,88] if group else [44,85])
	var accepted_old_sweep: bool = false
	var old_sweep_allowed_detour: bool = false
	var clear_tick: int = -1
	var resume_tick: int = -1
	var arrived: bool = false
	for tick: int in 240:
		var previous: Array = sim.world.facts.actors.z_walker.location.cell.duplicate()
		var previous_requests: int = observer.local_requests
		var previous_waits: int = int(sim.space.query_counts.get("local_goal_occupied_waits",0))
		safe = _physical_tick(suite,sim) and safe
		var goal_actor: Dictionary = sim.world.facts.actors.z_follower if group else sim.world.facts.actors.z_walker
		var goal_rect: Rect2 = sim.space._actor_rect(goal_actor,Vector2(blocker_cell[0],blocker_cell[1]))
		var current_clear: bool = not goal_rect.intersects(sim.space.body_rectangle(sim.world.facts.actors.a_blocker),false)
		if current_clear and clear_tick<0: clear_tick = tick
		if current_clear and sim.world.facts.actors.z_walker.location.cell!=previous and resume_tick<0: resume_tick = tick
		var contact: Dictionary = observer.contacts.get("z_walker",{})
		if not group and current_clear and contact.get("blocked",false) and "a_blocker" in contact.get("actors",[]):
			accepted_old_sweep = true
			old_sweep_allowed_detour = observer.local_requests>previous_requests and int(sim.space.query_counts.get("local_goal_occupied_waits",0))==previous_waits
		if not sim.world.facts.moves.has("z_walker"):
			arrived = sim.space.at(sim.world,"z_walker",1,[44,82]) and (not group or sim.space.at(sim.world,"z_follower",1,[44,85]))
			break
	var promptly: bool = clear_tick>=0 and resume_tick>=clear_tick and resume_tick-clear_tick<=1
	var validation: String = sim.world.validate(suite.content)
	var result: Dictionary = {"ok":requested.is_empty() and original_target and stable and safe and leave.is_empty() and promptly and arrived and validation.is_empty(),"group":group,"request_error":requested,"target_and_fifo_sequence_preserved":original_target,"repeated_current_goal_occupancy_did_not_redispatch":stable,"initial_dispatches":dispatches,"goal_waits_before_hold":occupied_waits,"safe_real_steps":safe,"safety_failures":observer.safety_failures,"blocker_departure_error":leave,"actual_goal_body_cleared_tick":clear_tick,"actual_motion_resumed_tick":resume_tick,"resumed_by_next_boundary":promptly,"accepted_past_sweep_observed_after_current_body_left":accepted_old_sweep if not group else null,"past_sweep_did_not_gate_local_route":old_sweep_allowed_detour if not group else null,"actual_original_goal_arrival":arrived,"local_route_requests_after_release":observer.local_requests,"validation":validation,"remaining":sim.world.facts.moves.duplicate(true)}
	sim.dispose()
	return result

func _group_gap(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var observer: ObservingMovement = ObservingMovement.new(sim.space)
	sim.space.movement = observer
	suite._add_actor(sim,"leader","S49",[44,86])
	suite._add_actor(sim,"follower","S49",[44,89])
	# This body is in the leader's original route, but between the two actual
	# destination bodies. A merged destination rectangle would misclassify it.
	suite._add_actor(sim,"gap_blocker","S49",[44,83.5])
	var leader_goal: Rect2 = sim.space._actor_rect(sim.world.facts.actors.leader,Vector2(44,82))
	var follower_goal: Rect2 = sim.space._actor_rect(sim.world.facts.actors.follower,Vector2(44,85))
	var blocker: Rect2 = sim.space.body_rectangle(sim.world.facts.actors.gap_blocker)
	var actual_gap: bool = leader_goal.merge(follower_goal).intersects(blocker,false) and not leader_goal.intersects(blocker,false) and not follower_goal.intersects(blocker,false)
	var requested: String = sim.space.request_group_move(sim.world,"leader",["leader","follower"],{"leader":[0,0],"follower":[0,3]},1,[44,82])
	var safe: bool = true
	var encountered: bool = false
	var arrived: bool = false
	for _tick: int in 400:
		safe = _physical_tick(suite,sim) and safe
		encountered = encountered or "gap_blocker" in observer.contacts.get("leader",{}).get("actors",[])
		if not sim.world.facts.moves.has("leader"):
			arrived = sim.space.at(sim.world,"leader",1,[44,82]) and sim.space.at(sim.world,"follower",1,[44,85])
			break
	var waits: int = int(sim.space.query_counts.get("local_goal_occupied_waits",0))
	var result: Dictionary = {"ok":requested.is_empty() and actual_gap and encountered and observer.local_requests>0 and waits==0 and safe and arrived,"request_error":requested,"blocker_in_merged_goal_gap_only":actual_gap,"actual_original_route_collision":encountered,"midroute_local_routes_requested":observer.local_requests,"false_goal_occupancy_waits":waits,"safe_real_steps":safe,"both_members_actually_arrived":arrived,"leader":sim.world.facts.actors.leader.location.duplicate(true),"follower":sim.world.facts.actors.follower.location.duplicate(true),"remaining":sim.world.facts.moves.duplicate(true)}
	sim.dispose()
	return result

func _alternative_facing(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var observer: ObservingMovement = ObservingMovement.new(sim.space)
	sim.space.movement = observer
	# S52 is 1.2m wide by 1.8m deep. This actual obstacle intersects the south
	# edge of its current-facing destination AABB; an east/west arrival is clear.
	suite._add_actor(sim,"rectangle","S52",[44,78])
	suite._add_actor(sim,"edge_blocker","S49",[44.5,83.23])
	var actor: Dictionary = sim.world.facts.actors.rectangle
	var current_goal: Rect2 = sim.space._actor_rect(actor,Vector2(44,82))
	var turned: Dictionary = actor.duplicate(true)
	turned.facing = PI*0.5
	var alternative_goal: Rect2 = sim.space._actor_rect(turned,Vector2(44,82))
	var obstacle: Rect2 = sim.space.body_rectangle(sim.world.facts.actors.edge_blocker)
	var geometry: bool = current_goal.intersects(obstacle,false) and not alternative_goal.intersects(obstacle,false)
	var requested: String = sim.space.request_move(sim.world,"rectangle",1,[44,82])
	var actual_contact: bool = false
	var safe: bool = true
	for _tick: int in 150:
		safe = _physical_tick(suite,sim) and safe
		actual_contact = actual_contact or "edge_blocker" in observer.contacts.get("rectangle",{}).get("actors",[])
		if observer.local_requests>0: break
	var waits: int = int(sim.space.query_counts.get("local_goal_occupied_waits",0))
	# The gate must permit a current local-route decision here. This is not an
	# acceptance of the route planner's handling of all orientation changes.
	var result: Dictionary = {"ok":requested.is_empty() and geometry and actual_contact and observer.local_requests>0 and waits==0 and safe,"request_error":requested,"current_facing_goal_intersects":current_goal.intersects(obstacle,false),"alternative_arrival_facing_goal_clear":not alternative_goal.intersects(obstacle,false),"actual_motion_collision":actual_contact,"local_route_decision_allowed":observer.local_requests>0,"false_unavoidable_goal_waits":waits,"safe_real_steps":safe,"actor":actor.location.duplicate(true),"remaining":sim.world.facts.moves.duplicate(true)}
	sim.dispose()
	return result

func _physical_tick(suite: RefCounted, sim: HospitalSimulation) -> bool:
	var before: Dictionary = {}
	for id: String in sim.world.ids("actors"): before[id] = sim.space.body_rectangle(sim.world.facts.actors[id])
	(sim.space.movement as ObservingMovement).contacts.clear()
	(sim.space.movement as ObservingMovement).contact_attempts.clear()
	suite._movement_tick(sim)
	var ids: Array = sim.world.ids("actors")
	var canonical: Dictionary = {}
	var indexed: Dictionary = {}
	var observer: ObservingMovement = sim.space.movement
	for id: String in ids:
		canonical[id] = sim.space.body_rectangle(sim.world.facts.actors[id])
		indexed[id] = sim.space._actor_index.rectangle(id)
		if canonical[id]!=indexed[id] and observer.body_index_drift.size()<4:
			observer.body_index_drift.append({"tick":sim.world.sim_tick,"actor_id":id,"canonical":_rect_fields(canonical[id]),"indexed":_rect_fields(indexed[id])})
	for first: int in ids.size():
		var a: Rect2 = canonical[ids[first]]
		if before[ids[first]].position.distance_to(a.position)>0.2+0.0001:
			_record_safety_failure(sim,{"kind":"displacement","actor":ids[first],"distance":before[ids[first]].position.distance_to(a.position),"from":_rect_fields(before[ids[first]]),"to":_rect_fields(a)})
			return false
		for second: int in range(first+1,ids.size()):
			var b: Rect2 = canonical[ids[second]]
			if a.intersects(b,false) or BodySweep.intersects(before[ids[first]],a,before[ids[second]],b):
				_record_safety_failure(sim,{"kind":"body_or_sweep","first":ids[first],"second":ids[second],"endpoint_overlap":a.intersects(b,false),"sweep_intersects":BodySweep.intersects(before[ids[first]],a,before[ids[second]],b),"first_from":_rect_fields(before[ids[first]]),"first_to":_rect_fields(a),"second_from":_rect_fields(before[ids[second]]),"second_to":_rect_fields(b)})
				return false
	return true

func _rect_fields(rectangle: Rect2) -> Array:
	return [rectangle.position.x,rectangle.position.y,rectangle.size.x,rectangle.size.y]

func _record_safety_failure(sim: HospitalSimulation, detail: Dictionary) -> void:
	var observer: ObservingMovement = sim.space.movement
	if observer.safety_failures.size()>=4: return
	detail.tick = sim.world.sim_tick
	detail.actors = sim.world.facts.actors.duplicate(true)
	detail.moves = sim.world.facts.moves.duplicate(true)
	detail.contact_attempts = observer.contact_attempts.duplicate(true)
	detail.body_index_drift = observer.body_index_drift.duplicate(true)
	detail.indexed_bodies = {}
	for id: String in sim.world.ids("actors"): detail.indexed_bodies[id] = _rect_fields(sim.space._actor_index.rectangle(id))
	observer.safety_failures.append(detail)

# Legal collision-calculation input: an earlier accepted 0.2-cell step left
# the destination clear, but its timed sweep intersects this proposed step.
# No actor, route, arrival or work completion is synthesized by this query.
func _accepted_sweep_boundary(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"sweep_subject","S49",[43.5,82])
	suite._add_actor(sim,"past_blocker","S49",[44.1,82.5])
	var request: String = sim.space.request_move(sim.world,"sweep_subject",1,[44,82])
	sim.space.movement._dispatch_routes(sim.world,sim.world.present_actor_count())
	var movement: Dictionary = sim.world.facts.moves.get("sweep_subject",{})
	var actor: Dictionary = sim.world.facts.actors.sweep_subject
	var obstacle: Dictionary = sim.world.facts.actors.past_blocker
	var accepted: BodyIndex.Record = BodyIndex.Record.new()
	accepted.id = obstacle.id
	accepted.floor_id = 1
	accepted.sweep_from = sim.space._actor_rect(obstacle,Vector2(44.1,82.3))
	accepted.sweep_to = sim.space.body_rectangle(obstacle)
	var proposed: BodyIndex.Record = BodyIndex.Record.new()
	proposed.id = actor.id
	proposed.floor_id = 1
	proposed.sweep_from = sim.space.body_rectangle(actor)
	proposed.sweep_to = sim.space._actor_rect(actor,Vector2(43.7,82))
	var legal: bool = accepted.sweep_from.position.distance_to(accepted.sweep_to.position)<=0.2001 and proposed.sweep_from.position.distance_to(proposed.sweep_to.position)<=0.2001 and not accepted.sweep_from.intersects(proposed.sweep_from,false) and not accepted.sweep_to.intersects(proposed.sweep_from,false)
	sim.space.movement._sweep_index.begin_boundary(sim.world.facts.actors)
	sim.space.movement._sweep_index.update(obstacle.id,1,accepted.sweep_from.merge(accepted.sweep_to))
	sim.space.movement._accepted_sweeps[obstacle.id] = accepted
	var before: Dictionary = sim.world.freeze()
	var contact: HospitalMovement.MotionResult = HospitalMovement.MotionResult.new()
	sim.space.movement._movement_contacts(sim.world,actor.id,1,proposed.sweep_from.merge(proposed.sweep_to),[proposed],[actor.id],contact)
	var current_goal_clear: bool = not sim.space._actor_rect(actor,Vector2(44,82)).intersects(accepted.sweep_to,false)
	var observed: bool = contact.blocked and contact.blocker_actor_ids==[obstacle.id] and BodySweep.intersects(proposed.sweep_from,proposed.sweep_to,accepted.sweep_from,accepted.sweep_to)
	var gate: bool = sim.space.movement._local_goal_occupied(sim.world,actor,movement,contact)
	var readonly: bool = before==sim.world.freeze()
	var result: Dictionary = {"ok":request.is_empty() and legal and observed and current_goal_clear and not gate and readonly,"request_error":request,"legal_fixed_step_collision_input":legal,"timed_accepted_sweep_really_hits":observed,"current_body_no_longer_at_goal":current_goal_clear,"does_not_gate_local_route":not gate,"world_unchanged":readonly,"actual_contacts":contact.blocker_actor_ids.duplicate()}
	sim.dispose()
	return result
