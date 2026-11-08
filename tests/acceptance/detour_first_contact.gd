extends RefCounted

func _pair(sim: HospitalSimulation, movement: HospitalMovement, box: Rect2) -> Dictionary:
	var sweep: BodyIndex.Record = BodyIndex.Record.new()
	sweep.id = "walker"; sweep.sweep_from = box; sweep.sweep_to = box
	var sweeps: Array[BodyIndex.Record] = [sweep]
	var full: HospitalMovement.MotionResult = HospitalMovement.MotionResult.new()
	var first: HospitalMovement.MotionResult = HospitalMovement.MotionResult.new()
	first.first_contact_only = true
	var before: Dictionary = sim.world.freeze()
	# First-hit runs before full collection, so full cannot prewarm its view.
	var counts: Dictionary = sim.space.query_counts.duplicate(true)
	movement._movement_contacts(sim.world,"walker",1,box,sweeps,["walker"],first)
	var first_candidates: int = int(sim.space.query_counts.movement_candidates)-int(counts.movement_candidates)
	var first_reservations: int = int(sim.space.query_counts.reservation_candidate_queries)-int(counts.reservation_candidate_queries)
	counts = sim.space.query_counts.duplicate(true)
	movement._movement_contacts(sim.world,"walker",1,box,sweeps,["walker"],full)
	return {"full":full,"first":first,"same_blocked":full.blocked==first.blocked,"candidate_count_equal":first_candidates==int(sim.space.query_counts.movement_candidates)-int(counts.movement_candidates),"reservation_count_equal":first_reservations==int(sim.space.query_counts.reservation_candidate_queries)-int(counts.reservation_candidate_queries),"reservation_queries":first_reservations,"readonly":before==sim.world.freeze()}

func run(content: HospitalContent) -> Dictionary:
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new()
	suite.content = content
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker","S49",[35,70])
	suite._add_actor(sim,"owner","S49",[50,85])
	HospitalFactory._add_facility(sim.world,{"id":"first_hit_facility","definition_id":"M37","anchor":[44,76],"size":content.facility_definition("M37").footprint.duplicate(),"room_id":null},content)
	var error: String = sim.space.reserve_facility(sim.world,"first_hit_facility","owner","owner")
	if not error.is_empty():
		sim.dispose()
		return {"passed":false,"details":{"reserve_error":error}}
	var reservation: Dictionary = sim.world.facts.adaptations.first_hit_facility
	var raw: Array = reservation.regions[0]
	var box: Rect2 = Rect2(float(raw[0]),float(raw[1]),float(raw[2]),float(raw[3]))
	var movement: HospitalMovement = HospitalMovement.new(sim.space)
	sim.space._ensure_actor_index(sim.world)
	sim.space._actor_index.clear()
	# Explicit collision-kernel fixture, not fabricated actor journeys.
	sim.space._actor_index.update("alpha",1,box)
	sim.space._actor_index.update("beta",1,box)
	var both: Dictionary = _pair(sim,movement,box)
	sim.space._actor_index.clear()
	var denied: Dictionary = _pair(sim,movement,box)
	sim.space.grant_facility_access(sim.world,"first_hit_facility","walker")
	var granted: Dictionary = _pair(sim,movement,box)
	# Explicit revocation boundary input, not a simulated authorization workflow.
	reservation.staff_ids = []
	sim.space.reservation_changed(sim.world,"first_hit_facility")
	var revoked: Dictionary = _pair(sim,movement,box)
	var empty: Dictionary = _pair(sim,movement,Rect2(1,1,0.1,0.1))
	var checks: Dictionary = {
		"real_environment_worker_gate_preserved":sim.services.departments.sample_workers_enabled and sim.services.environment.get_script()==preload("res://game/operations/environment_service.gd") and sim.services.environment.space.get_script()==preload("res://game/building/hospital_space.gd"),
		"default_mode_collects_all_actors":both.full.blocker_actor_ids==["alpha","beta"],
		"default_mode_collects_reservation":both.full.reservation_ids==["first_hit_facility"],
		"first_mode_stops_after_true_actor_hit":both.first.blocker_actor_ids==["alpha"] and both.first.reservation_ids.is_empty(),
		"first_mode_still_queries_reservations":both.reservation_queries==1 and both.reservation_count_equal,
		"first_mode_preserves_full_candidate_count":both.candidate_count_equal,
		"reservation_denied":denied.first.blocked and denied.first.reservation_ids==["first_hit_facility"],
		"permission_granted":not granted.first.blocked,
		"permission_revoked":revoked.first.blocked,
		"empty_is_clear":not empty.first.blocked,
		"only_return_scratch_opts_in":HospitalMovement.ReturnContactScratch.new().result.first_contact_only and not HospitalMovement.MotionResult.new().first_contact_only
	}
	for row: Dictionary in [both,denied,granted,revoked,empty]:
		checks["all_same_boolean"] = bool(checks.get("all_same_boolean",true)) and row.same_blocked
		checks["all_counts_and_facts_preserved"] = bool(checks.get("all_counts_and_facts_preserved",true)) and row.candidate_count_equal and row.reservation_count_equal and row.readonly
	var ok: bool = true
	for value: bool in checks.values(): ok = ok and value
	sim.dispose()
	return {"passed":ok,"details":checks,"scope":"real reserve/grant APIs plus explicit revocation and synthetic collision-kernel inputs; existing owner/geometry/convoy suites remain required"}
