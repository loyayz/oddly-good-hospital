extends RefCounted

# Prepared regression module; must be executed before candidate adoption.
func _point(x: float,y: float) -> Dictionary:
	return {"kind":"floor","floor_id":1,"cell":[x,y]}

func _proof(actor: Dictionary) -> Dictionary:
	return {"sweeps":{},"segments":{},"_capture_entry":true,"_return_sample":actor.duplicate(true)}

func run(content: HospitalContent) -> Dictionary:
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new()
	suite.content = content
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker","S49",[35,70])
	suite._add_actor(sim,"blocker","S49",[36,70])
	var service: HospitalMovement = HospitalMovement.new(sim.space)
	var actor: Dictionary = sim.world.facts.actors.walker
	var movement: Dictionary = {"actor_id":"walker","detour":{"original_path":[_point(36,70),_point(37,70)]}}
	var query: RouteClearance = sim.space.navigation.structural_clearance(sim.world,actor,1)
	var before: Dictionary = sim.world.freeze()
	var proof: Dictionary = _proof(actor)
	var failed: bool = service._detour_path_clear(sim.world,actor,movement,[_point(36,70)],query,proof)
	var scratch: HospitalMovement.ReturnContactScratch = proof.get("_return_contact_scratch")
	if scratch==null:
		sim.dispose()
		return {"passed":false,"details":{"error":"blocked contact did not allocate owner scratch"}}
	var first_id: int = scratch.get_instance_id()
	var blocked_ids: Array = scratch.result.blocker_actor_ids.duplicate()
	# Result fields must have fresh-object values even across candidate calls.
	scratch.result.door_id = "test_stale_door"
	scratch.result.reservation_ids.append("test_stale_reservation")
	scratch.result.requested_motion = Vector2.ONE
	scratch.result.actual_motion = Vector2.ONE
	var passed: bool = service._detour_path_clear(sim.world,actor,movement,[_point(35,71)],query,proof)
	var fresh: Dictionary = _proof(actor)
	var fresh_passed: bool = service._detour_path_clear(sim.world,actor,movement,[_point(35,71)],query,fresh)
	var skipped: Dictionary = _proof(actor)
	var empty_passed: bool = service._detour_path_clear(sim.world,actor,movement,[],query,skipped)
	var generic: Dictionary = {"sweeps":{},"segments":{}}
	var generic_passed: bool = service._detour_path_clear(sim.world,actor,movement,[_point(35,71)],query,generic)
	var checks: Dictionary = {
		"collision_false":not failed,
		"original_blocker_found":"blocker" in blocked_ids,
		"next_candidate_clear":passed,
		"same_owner_reuses_scratch":proof._return_contact_scratch.get_instance_id()==first_id,
		"both_contact_lists_reset":scratch.result.blocker_actor_ids.is_empty() and scratch.result.reservation_ids.is_empty(),
		"result_defaults_reset":scratch.result.door_id.is_empty() and scratch.result.requested_motion==Vector2.ZERO and scratch.result.actual_motion==Vector2.ZERO,
		"typed_singleton_identity":scratch.sweeps.is_typed() and scratch.sweeps.size()==1 and is_same(scratch.sweeps[0],scratch.sweep),
		"next_owner_new_scratch":fresh_passed and fresh._return_contact_scratch.get_instance_id()!=first_id,
		"empty_path_lazy":empty_passed and not skipped.has("_return_contact_scratch"),
		"generic_fallback":generic_passed and not generic.has("_return_contact_scratch"),
		"world_unchanged":sim.world.freeze()==before
	}
	var ok: bool = true
	for value: bool in checks.values(): ok = ok and value
	sim.dispose()
	return {"passed":ok,"details":checks}
