extends SceneTree
var suite = preload("res://tests/acceptance/space.gd").new()
var checks: Dictionary = {}
func _initialize() -> void: call_deferred("_run")
func _group() -> HospitalSimulation:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"leader","S49",[54,80])
	suite._add_actor(sim,"follower","S49",[52,80])
	var form: Dictionary = ConvoyTrail.formation(sim.space,sim.world,"leader",["leader","follower"],Vector2.RIGHT)
	for id: String in ["leader","follower"]:
		sim.world.facts.actors[id].location.cell = form.targets[id]
		sim.space.sync_actor(sim.world,id)
	return sim
func _run() -> void:
	suite.content = HospitalContent.new()
	var sim: HospitalSimulation = _group()
	var w: WorldState = sim.world
	var movement: HospitalMovement = sim.space.movement
	checks.initial_empty = movement._member_owner(w,"follower").is_empty()
	checks.official_create = sim.space.request_group_move(w,"leader",["leader","follower"],{},1,[58,80]).is_empty()
	checks.leader_and_follower = movement._member_owner(w,"leader")=="leader" and movement._member_owner(w,"follower")=="leader"
	var before: Dictionary = w.freeze()
	checks.reject_independent_follower = not sim.space.request_move(w,"follower",1,[52,82]).is_empty() and w.freeze()==before
	checks.reject_follower_cancel = not sim.space.cancel_ground_move(w,"follower") and w.freeze()==before
	checks.reject_second_group = not sim.space.request_group_move(w,"follower",["follower"],{},1,[52,82]).is_empty() and w.freeze()==before
	var restored: HospitalSimulation = HospitalSimulation.new(WorldState.new(w.freeze()),suite.content)
	checks.restored_rebuild = restored.world.validate(suite.content).is_empty() and restored.space.movement._member_owner(restored.world,"follower")=="leader"
	restored.dispose()
	var original_moves: Dictionary = w.facts.moves
	w.facts.moves = {}
	checks.same_world_replacement = movement._member_owner(w,"follower").is_empty()
	w.facts.moves = original_moves
	checks.same_world_restore = movement._member_owner(w,"follower")=="leader"
	checks.cancel_owner = sim.space.cancel_ground_move(w,"leader") and movement._member_owners.is_empty() and movement._member_owner(w,"follower").is_empty()
	checks.independent_after_cancel = sim.space.request_move(w,"follower",1,[52,82]).is_empty()
	sim.dispose()
	sim = _group()
	w = sim.world
	movement = sim.space.movement
	w.facts.actors.follower.location.cell[1] += 0.5
	sim.space.sync_actor(w,"follower")
	checks.failed_create_atomic = not sim.space.request_group_move(w,"leader",["leader","follower"],{},1,[58,80]).is_empty() and w.facts.moves.is_empty() and movement._member_owner(w,"follower").is_empty()
	sim.dispose()
	sim = _group()
	w = sim.world
	movement = sim.space.movement
	checks.complete_request = sim.space.request_group_move(w,"leader",["leader","follower"],{},1,[58,80]).is_empty()
	for step: int in 100:
		if not w.facts.moves.has("leader"): break
		suite._movement_tick(sim)
	checks.real_completion_releases = sim.space.at(w,"leader",1,[58,80]) and not w.facts.moves.has("leader") and movement._member_owners.is_empty() and movement._member_owner(w,"follower").is_empty() and w.validate(suite.content).is_empty()
	checks.independent_after_completion = sim.space.request_move(w,"follower",1,[52,82]).is_empty()
	sim.dispose()
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"scope":"Official convoy creation, rejection, cancellation, real movement completion, and world/moves restoration; no mock geometry/movement."}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result))
	quit(0 if result.ok else 1)
