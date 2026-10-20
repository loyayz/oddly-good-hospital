extends RefCounted

class QueryCountingIndex extends BodyIndex:
	var queries: int = 0
	func _query(floor_id: int, rect: Rect2) -> Array:
		queries += 1
		return super._query(floor_id,rect)

# The calculation cases supply literal valid envelopes to the collision
# boundary. Actual movement and door cases below use the real body index.
class LiteralSpace extends HospitalSpace:
	func _init(database: HospitalContent) -> void:
		super(database)
		_actor_index = QueryCountingIndex.new()
	func _ensure_actor_index(_world: WorldState) -> void:
		pass

class RecordingMovement extends HospitalMovement:
	var results: Dictionary = {}
	func _init(geometry: HospitalSpace) -> void:
		super(geometry)
	func _move_step(world: WorldState, actor: Dictionary, movement: Dictionary, segment: Dictionary) -> HospitalMovement.MotionResult:
		var result: HospitalMovement.MotionResult = super._move_step(world,actor,movement,segment)
		results[actor.id] = {"requested":result.requested_motion,"actual":result.actual_motion,"actors":result.blocker_actor_ids.duplicate(),"reservations":result.reservation_ids.duplicate(),"door":result.door_id,"blocked":result.blocked}
		return result

class CourtesyProbe extends HospitalMovement:
	var chosen_partner: String = ""
	var idle_ids: Array[String] = []
	var local_detours: int = 0
	var goal_queries: int = 0
	func _init(geometry: HospitalSpace) -> void:
		super(geometry)
	func _has_priority(_world: WorldState, _first_id: String, second_id: String) -> bool:
		chosen_partner = second_id
		return true
	func _yield_idle_staff(_world: WorldState, _actor: Dictionary, _movement: Dictionary, blocker_ids: Array[String]) -> bool:
		idle_ids.assign(blocker_ids)
		return false
	func _queue_local_route(_world: WorldState, _actor: Dictionary, _movement: Dictionary) -> void:
		local_detours += 1
	func _local_goal_occupied(world: WorldState, actor: Dictionary, movement: Dictionary, contact: MotionResult) -> bool:
		var index: QueryCountingIndex = space._actor_index
		var before: int = index.queries
		var occupied: bool = super._local_goal_occupied(world,actor,movement,contact)
		goal_queries += index.queries-before
		return occupied

func run(suite: RefCounted) -> Dictionary:
	var contacts: Dictionary = _literal_contacts(suite)
	var courtesy: Dictionary = _courtesy_handoff(suite)
	var movement: Dictionary = _actual_movement(suite)
	var group: Dictionary = _actual_group(suite)
	var door: Dictionary = _door_wait(suite)
	return {"ok":contacts.ok and courtesy.ok and movement.ok and group.ok and door.ok,"literal_contacts":contacts,"courtesy_handoff":courtesy,"actual_movement":movement,"actual_group":group,"door_wait":door}

func _literal_contacts(suite: RefCounted) -> Dictionary:
	var cases: Array[Dictionary] = [
		{"name":"edge_touch_is_clear","from":Rect2(10,10,1,1),"to":Rect2(11,10,1,1),"others":{"edge":Rect2(12,10,1,1)},"expected":[]},
		{"name":"all_hits_sorted_and_deduplicated","from":Rect2(10,10,1,1),"to":Rect2(11,10,1,1),"others":{"z_hit":Rect2(11.5,10,0.25,1),"a_hit":Rect2(11.25,10,0.25,1)},"expected":["a_hit","z_hit"]},
		{"name":"group_gap_is_not_a_hit","from":Rect2(10,10,1,1),"to":Rect2(11,10,1,1),"follower_from":Rect2(10,14,1,1),"follower_to":Rect2(11,14,1,1),"others":{"gap":Rect2(10.5,12,1,1)},"expected":[]},
		{"name":"parallel_accepted_sweeps_are_clear","from":Rect2(10,10,1,1),"to":Rect2(12,10,1,1),"others":{"parallel":Rect2(13,10,1,1)},"accepted":{"parallel":[Rect2(11,10,1,1),Rect2(13,10,1,1)]},"expected":[]},
		{"name":"accepted_sweep_blocks_after_endpoint_left","from":Rect2(10,11,1,1),"to":Rect2(12,11,1,1),"others":{"crossing":Rect2(11,12,1,1)},"accepted":{"crossing":[Rect2(11,10,1,1),Rect2(11,12,1,1)]},"expected":["crossing"]},
		{"name":"other_floor_is_clear","from":Rect2(10,10,1,1),"to":Rect2(11,10,1,1),"others":{"upstairs":Rect2(11.5,10,0.25,1)},"other_floor":2,"expected":[]},
		{"name":"multiple_regions_report_reservation_once","from":Rect2(10,10,1,1),"to":Rect2(11,10,1,1),"reservations":{"z_reservation":{"actor_id":"owner","staff_ids":[],"floor_id":1,"regions":[[11.2,10,0.2,1],[11.4,10,0.2,1]]},"a_reservation":{"actor_id":"owner","staff_ids":[],"floor_id":1,"regions":[[11.6,10,0.2,1]]}},"expected":[],"expected_reservations":["a_reservation","z_reservation"]},
		{"name":"reservation_permission_exemptions","from":Rect2(10,10,1,1),"to":Rect2(11,10,1,1),"follower_from":Rect2(10,14,1,1),"follower_to":Rect2(11,14,1,1),"reservations":{"own":{"actor_id":"probe","staff_ids":[],"floor_id":1,"regions":[[11.2,10,0.2,1]]},"staff_permission":{"actor_id":"owner","staff_ids":["probe"],"floor_id":1,"regions":[[11.4,10,0.2,1]]},"member_owner":{"actor_id":"follower","staff_ids":[],"floor_id":1,"regions":[[11.6,10,0.2,1]]},"other_floor":{"actor_id":"owner","staff_ids":[],"floor_id":2,"regions":[[11.6,10,0.2,1]]}},"expected":[],"expected_reservations":[]}
	]
	var rows: Array = []
	var ok: bool = true
	for item: Dictionary in cases:
		var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"碰撞结果字面边界",false,suite.content)
		var space: LiteralSpace = LiteralSpace.new(suite.content)
		var members: Array = ["probe"]
		world.facts.actors["probe"] = suite._actor("probe","S49",[10,10])
		world.facts.actors["owner"] = suite._actor("owner","S49",[40,80])
		space._actor_index.update("probe",1,item.from)
		var sweeps: Array[BodyIndex.Record] = [_sweep("probe",item.from,item.to)]
		var broad: Rect2 = item.from.merge(item.to)
		if item.has("follower_from"):
			members.append("follower")
			world.facts.actors["follower"] = suite._actor("follower","S49",[10,14])
			space._actor_index.update("follower",1,item.follower_from)
			sweeps.append(_sweep("follower",item.follower_from,item.follower_to))
			broad = broad.merge(item.follower_from).merge(item.follower_to)
		for id: String in item.get("others",{}):
			var rect: Rect2 = item.others[id]
			world.facts.actors[id] = suite._actor(id,"S49",[rect.position.x,rect.position.y],int(item.get("other_floor",1)))
			space._actor_index.update(id,int(item.get("other_floor",1)),rect)
		for id: String in item.get("accepted",{}):
			var accepted: BodyIndex.Record = _sweep(id,item.accepted[id][0],item.accepted[id][1])
			space.movement._accepted_sweeps[id] = accepted
			space.movement._sweep_index.update(id,1,accepted.sweep_from.merge(accepted.sweep_to))
		for id: String in item.get("reservations",{}):
			var reservation: Dictionary = item.reservations[id].duplicate(true)
			reservation.kind = "facility"
			world.facts.adaptations[id] = reservation
		var before: Dictionary = world.freeze()
		var result: HospitalMovement.MotionResult = HospitalMovement.MotionResult.new()
		space.movement._movement_contacts(world,"probe",1,broad,sweeps,members,result)
		var expected_reservations: Array = item.get("expected_reservations",[])
		var matches: bool = result.blocker_actor_ids==item.expected and result.reservation_ids==expected_reservations and result.blocked==(not item.expected.is_empty() or not expected_reservations.is_empty()) and result.door_id.is_empty() and world.freeze()==before
		ok = ok and matches
		rows.append({"name":item.name,"ok":matches,"expected_actor_ids":item.expected,"actual_actor_ids":result.blocker_actor_ids.duplicate(),"expected_reservation_ids":expected_reservations,"actual_reservation_ids":result.reservation_ids.duplicate(),"facts_unchanged":world.freeze()==before})
	return {"ok":ok,"cases":rows}

func _courtesy_handoff(suite: RefCounted) -> Dictionary:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"精确阻挡交接",false,suite.content)
	var space: LiteralSpace = LiteralSpace.new(suite.content)
	for id: String in ["probe","follower","a_gap_primary","z_primary","secondary","reservation_owner"]:
		world.facts.actors[id] = suite._actor(id,"S49",[40,80])
	world.facts.actors.probe.location.cell = [10,10]
	world.facts.actors.follower.location.cell = [10,14]
	world.facts.actors.a_gap_primary.location.cell = [10.5,12]
	world.facts.actors.z_primary.location.cell = [11.25,8]
	world.facts.actors.secondary.location.cell = [11.25,10]
	space._actor_index.update("a_gap_primary",1,Rect2(10.5,12,1,1))
	space._actor_index.update("z_primary",1,Rect2(11.25,8,0.25,1))
	space._actor_index.update("secondary",1,Rect2(11.25,10,0.25,1))
	var movement: Dictionary = {"actor_id":"probe","members":["probe","follower"],"offsets":{"probe":[0,0],"follower":[0,4]},"travelled":[{"floor_id":1,"cell":[10,10]}],"yielding":false,"target_floor":1,"target_cell":[12,10],"cursor":0,"path":[{"kind":"floor","floor_id":1,"cell":[11,10]},{"kind":"floor","floor_id":1,"cell":[12,10]}]}
	world.facts.moves["probe"] = movement
	world.facts.moves["a_gap_primary"] = {"actor_id":"a_gap_primary","members":["a_gap_primary"],"yielding":false}
	world.facts.moves["z_primary"] = {"actor_id":"z_primary","members":["z_primary","secondary"],"offsets":{"z_primary":[0,0],"secondary":[0,2]},"yielding":false}
	var sweeps: Array[BodyIndex.Record] = [_sweep("probe",Rect2(10,10,1,1),Rect2(11,10,1,1)),_sweep("follower",Rect2(10,14,1,1),Rect2(11,14,1,1))]
	var result: HospitalMovement.MotionResult = HospitalMovement.MotionResult.new()
	space.movement._movement_contacts(world,"probe",1,Rect2(10,10,2,5),sweeps,["probe","follower"],result)
	var probe: CourtesyProbe = CourtesyProbe.new(space)
	var index: QueryCountingIndex = space._actor_index
	index.queries = 0
	probe._yield(world,world.facts.actors.probe,movement,result)
	var primary: bool = result.blocker_actor_ids==["secondary"] and probe.chosen_partner=="z_primary"
	var no_partner_requery: bool = index.queries==0
	# A group may finish before the next actor is processed in this same
	# movement phase. Cached member ownership must not override a new trip.
	probe._phase_owners["secondary"] = "z_primary"
	world.facts.moves.erase("z_primary")
	world.facts.moves["secondary"] = {"actor_id":"secondary","yielding":false}
	var new_single_owner: bool = probe._movement_owners(world,result.blocker_actor_ids)==["secondary"]
	world.facts.moves.erase("secondary")
	world.facts.moves["z_primary"] = {"actor_id":"z_primary","members":["z_primary"],"yielding":false}
	var changed_group_owner: bool = probe._movement_owners(world,result.blocker_actor_ids).is_empty()
	probe.chosen_partner = ""
	probe._yield(world,world.facts.actors.probe,movement,result)
	# Partner/courtesy selection consumes the original hits. A separate current
	# destination query may prove that a different body makes detouring futile.
	var idle_receives_hits: bool = probe.idle_ids==["secondary"] and index.queries==probe.goal_queries
	var reservation_result: HospitalMovement.MotionResult = HospitalMovement.MotionResult.new()
	reservation_result.reservation_ids.append("reservation_only")
	probe.chosen_partner = ""
	probe.idle_ids.clear()
	probe._yield(world,world.facts.actors.probe,movement,reservation_result)
	var reservation_not_body: bool = probe.chosen_partner.is_empty() and probe.idle_ids.is_empty() and probe.local_detours==2
	return {"ok":primary and no_partner_requery and new_single_owner and changed_group_owner and idle_receives_hits and reservation_not_body,"secondary_maps_to_primary":primary,"gap_actor_not_selected":probe.chosen_partner!="a_gap_primary","partner_selection_index_queries":0 if no_partner_requery else index.queries,"new_single_trip_overrides_old_group":new_single_owner,"removed_member_does_not_keep_old_owner":changed_group_owner,"idle_staff_branch_receives_only_actual_hits":idle_receives_hits,"reservation_owner_not_treated_as_body":reservation_not_body}

func _actual_movement(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var recording: RecordingMovement = RecordingMovement.new(sim.space)
	sim.space.movement = recording
	suite._add_actor(sim,"motion_walker","S49",[44,82])
	var reason: String = sim.space.request_move(sim.world,"motion_walker",1,[46,82])
	suite._movement_tick(sim)
	var clear: Dictionary = recording.results.get("motion_walker",{}).duplicate(true)
	# S49 is 0.7m square (7/15 cells), speed 2 cells/s and the tick is
	# 0.1s: one clear eastward step is exactly 0.2 cells before float rounding.
	var rounding: float = 2.0*96.0*pow(2.0,-23.0)
	var moved: bool = not clear.is_empty() and not clear.blocked and Vector2(clear.requested).distance_to(Vector2(0.2,0))<=rounding and Vector2(clear.actual).distance_to(Vector2(0.2,0))<=rounding and sim.space.at(sim.world,"motion_walker",1,[44.2,82])
	suite._add_actor(sim,"motion_blocker","S49",[44.7,82])
	var before: Array = sim.world.facts.actors.motion_walker.location.cell.duplicate()
	var cursor: int = int(sim.world.facts.moves.motion_walker.cursor)
	suite._movement_tick(sim)
	var blocked: Dictionary = recording.results.get("motion_walker",{}).duplicate(true)
	var waited: bool = not blocked.is_empty() and blocked.blocked and blocked.actors==["motion_blocker"] and blocked.reservations.is_empty() and str(blocked.door).is_empty() and Vector2(blocked.actual)==Vector2.ZERO and Vector2(blocked.requested).distance_to(Vector2(0.2,0))<=rounding and sim.world.facts.actors.motion_walker.location.cell==before and int(sim.world.facts.moves.motion_walker.cursor)==cursor
	var blocker_move: String = sim.space.request_move(sim.world,"motion_blocker",1,[47,83])
	var resumed: bool = suite._wait(sim,func()->bool:return not sim.world.facts.moves.has("motion_walker") and sim.space.at(sim.world,"motion_walker",1,[46,82]),120,suite._movement_tick.bind(sim))
	var result: Dictionary = {"ok":reason.is_empty() and moved and waited and blocker_move.is_empty() and resumed,"request_error":reason,"clear_step":clear,"literal_clear_displacement":moved,"blocked_step":blocked,"blocked_position_and_cursor_preserved":waited,"blocker_departure_error":blocker_move,"actual_arrival_after_release":resumed}
	sim.dispose()
	return result

func _actual_group(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var recording: RecordingMovement = RecordingMovement.new(sim.space)
	sim.space.movement = recording
	suite._add_actor(sim,"group_leader","S49",[44,82])
	suite._add_actor(sim,"group_follower","S49",[44,83])
	var request: String = sim.space.request_group_move(sim.world,"group_leader",["group_leader","group_follower"],{"group_leader":[0,0],"group_follower":[0,1]},1,[46,82])
	suite._movement_tick(sim)
	var clear: Dictionary = recording.results.get("group_leader",{}).duplicate(true)
	var rounding: float = 2.0*96.0*pow(2.0,-23.0)
	var moved_together: bool = not clear.is_empty() and not clear.blocked and Vector2(clear.actual).distance_to(Vector2(0.16,0))<=rounding and sim.space.at(sim.world,"group_leader",1,[44.16,82]) and sim.space.at(sim.world,"group_follower",1,[44.16,83])
	suite._add_actor(sim,"group_blocker","S49",[44.7,83])
	var before_leader: Array = sim.world.facts.actors.group_leader.location.cell.duplicate()
	var before_follower: Array = sim.world.facts.actors.group_follower.location.cell.duplicate()
	suite._movement_tick(sim)
	var blocked: Dictionary = recording.results.get("group_leader",{}).duplicate(true)
	var group_waited: bool = not blocked.is_empty() and blocked.blocked and blocked.actors==["group_blocker"] and Vector2(blocked.actual)==Vector2.ZERO and sim.world.facts.actors.group_leader.location.cell==before_leader and sim.world.facts.actors.group_follower.location.cell==before_follower
	var leave: String = sim.space.request_move(sim.world,"group_blocker",1,[47,85])
	var arrived: bool = suite._wait(sim,func()->bool:return not sim.world.facts.moves.has("group_leader") and sim.space.at(sim.world,"group_leader",1,[46,82]) and sim.space.at(sim.world,"group_follower",1,[46,83]),160,suite._movement_tick.bind(sim))
	var result: Dictionary = {"ok":request.is_empty() and moved_together and group_waited and leave.is_empty() and arrived,"request_error":request,"clear_step":clear,"literal_shared_displacement":moved_together,"follower_collision_blocks_whole_group":group_waited,"blocked_step":blocked,"blocker_departure_error":leave,"both_actually_arrived":arrived}
	sim.dispose()
	return result

func _door_wait(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var built: CommandResult = suite._command(sim,"build_room",suite._room("motion_door_room",[42,68],[14,10]))
	if not built.accepted:
		sim.dispose()
		return {"ok":false,"room":built.to_record()}
	var door: Dictionary = suite._doors(sim.world,"motion_door_room")[0]
	var x: float = float(door.cell[0])
	var y: float = float(door.cell[1])
	suite._add_actor(sim,"door_owner","S49",[x,y+0.1])
	suite._add_actor(sim,"door_waiter","S49",[x,y+1.1])
	var recording: RecordingMovement = RecordingMovement.new(sim.space)
	sim.space.movement = recording
	var acquisition: HospitalMovement.MotionResult = HospitalMovement.MotionResult.new()
	var owner: Dictionary = sim.world.facts.actors.door_owner
	# The owner is physically inside this opening. Acquire its normal door
	# permission; no transit, arrival, work or release is marked complete.
	var acquired: bool = recording._reserve_doors(sim.world,owner,{"actor_id":"door_owner","members":["door_owner"]},sim.space.body_rectangle(owner),[door],acquisition)
	var requested: String = sim.space.request_move(sim.world,"door_waiter",1,[x,y-2])
	var observed: bool = false
	var blocked: Dictionary = {}
	for tick: int in 10:
		var previous: Array = sim.world.facts.actors.door_waiter.location.cell.duplicate()
		suite._movement_tick(sim)
		var sample: Dictionary = recording.results.get("door_waiter",{})
		if str(sample.get("door",""))==str(door.id):
			blocked = sample.duplicate(true)
			observed = sample.blocked and Vector2(sample.actual)==Vector2.ZERO and sim.world.facts.actors.door_waiter.location.cell==previous and sim.world.facts.adaptations.get(door.id,{}).get("actor_id","")=="door_owner"
			break
	var leave: String = sim.space.request_move(sim.world,"door_owner",1,[x+2,y-2])
	var resumed: bool = suite._wait(sim,func()->bool:return not sim.world.facts.moves.has("door_waiter") and sim.space.at(sim.world,"door_waiter",1,[x,y-2]),240,suite._movement_tick.bind(sim))
	var result: Dictionary = {"ok":door.axis=="x" and acquired and requested.is_empty() and observed and leave.is_empty() and resumed,"door_id":door.id,"normal_owner_acquisition":acquired,"request_error":requested,"blocked_door_result":blocked,"door_wait_without_displacement":observed,"owner_departure_error":leave,"actual_arrival_after_owner_left":resumed}
	sim.dispose()
	return result

func _sweep(id: String, from: Rect2, to: Rect2) -> BodyIndex.Record:
	var record: BodyIndex.Record = BodyIndex.Record.new()
	record.id = id
	record.floor_id = 1
	record.rect = from
	record.sweep_from = from
	record.sweep_to = to
	return record
