extends SceneTree

const Waiting = preload("res://game/life/waiting_life.gd")
var failures: Array[String] = []
var checks: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = FeasibilityHospitals.create("waiting-rules",false,content)
	var space: HospitalSpace = HospitalSpace.new(content)
	var life: RefCounted = Waiting.new(content,space)
	var visit: Dictionary = world.facts.visits.values()[0]
	var ticket_id: String = world.new_id("ticket")
	visit.phase = "wait_gp"
	visit.ticket_id = ticket_id
	world.facts.tickets[ticket_id] = {"id":ticket_id,"visit_id":visit.id,"kind":"gp","enqueued_tick":0,"waited_ticks":123,"pause_reasons":{}}
	world.facts.facilities.calm = {"id":"calm","definition_id":"FUR49","floor_id":1,"cell":[48,92],"footprint":[1,1],"patient_cell":[48,93],"operator_cells":[],"repair_cell":[47,92],"grade":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{}}
	life.ensure(world)
	# The original gallery chair blocks the wide sample resident's real exit.
	# Keep that negative case, then use a nearby public seat with safe clearance.
	var unsafe_before: Dictionary = world.freeze()
	var unsafe: CommandResult = life.execute(world,"waiting_select_seat",{"visit_id":visit.id,"facility_id":"calm"})
	_check("seat_cannot_block_other_resident_exit",not unsafe.accepted and "安全出口" in unsafe.reason and world.freeze()==unsafe_before)
	world.facts.facilities.calm.cell = [50,92]
	world.facts.facilities.calm.patient_cell = [50,93]
	world.facts.facilities.calm.repair_cell = [49,92]
	world.facts.actors[visit.actor_id].location.cell = [50,93]
	var rng_before: Dictionary = world.facts.rng.duplicate(true)
	var before: Dictionary = world.freeze()
	var candidates: Array = life.seat_candidates(world,visit.id)
	_check("seat_query_is_read_only",world.freeze()==before and world.facts.rng==rng_before)
	_check("actual_public_chair_candidate",not candidates.is_empty() and candidates[0].facility_id=="calm")
	var result: CommandResult = life.execute(world,"waiting_select_seat",{"visit_id":visit.id,"facility_id":"calm"})
	_check("manual_compatible_seat_reserved",result.accepted)
	for index: int in range(3): _step(world,space,life)
	_check("actual_sitting_required",world.facts.actors[visit.actor_id].posture=="seated" and not visit.get("chair_calm_claimed",false))
	var original_anger: float = float(visit.anger)
	for index: int in range(200): _step(world,space,life)
	_check("continuous_calm_has_visit_receipt",visit.get("chair_calm_claimed",false) and is_equal_approx(float(visit.anger),maxf(0.0,original_anger-3.0)))
	_check("seating_keeps_original_queue_clock",world.facts.tickets[ticket_id].waited_ticks==123)
	var restored: WorldState = WorldState.new(world.freeze())
	var restored_space: HospitalSpace = HospitalSpace.new(content)
	var restored_life: RefCounted = Waiting.new(content,restored_space)
	var restored_visit: Dictionary = restored.facts.visits[visit.id]
	var claimed_anger: float = float(restored_visit.anger)
	for index: int in range(210): _step(restored,restored_space,restored_life)
	_check("restore_does_not_reclaim_calm",is_equal_approx(float(restored_visit.anger),claimed_anger))
	_check("call_releases_chair_without_new_ticket",restored_life.call_patient(restored,visit.id) and not restored.facts.waiting_life.seats.has(visit.id) and restored_visit.ticket_id==ticket_id)
	restored.facts.tickets[ticket_id].erase("called_tick")
	restored.facts.sim_tick = 1800
	restored_life.dispatch(restored)
	restored.facts.tickets[ticket_id].pause_reasons.incident = "another-owner"
	_check("need_pauses_only_original_ticket",restored.facts.waiting_life.needs.has(visit.id) and restored.facts.tickets[ticket_id].pause_reasons.get("need_service","")!="" and restored.facts.tickets[ticket_id].waited_ticks==123)
	_check("called_patient_waits_for_safe_life_segment",not restored_life.call_patient(restored,visit.id))
	var fallback_anger: float = float(restored_visit.anger)
	for index: int in range(81): _step(restored,restored_space,restored_life)
	_check("eight_second_fallback_returns_to_original_ticket",not restored.facts.waiting_life.needs.has(visit.id) and restored_visit.ticket_id==ticket_id)
	_check("fallback_charged_once_and_other_pause_preserved",is_equal_approx(float(restored_visit.anger),minf(100.0,fallback_anger+5.0)) and restored.facts.tickets[ticket_id].pause_reasons=={"incident":"another-owner"})
	_check("need_alternates_after_real_completion",restored.facts.waiting_life.clocks[visit.id].next_purpose=="water" and int(restored.facts.waiting_life.clocks[visit.id].next_need_tick)>=int(restored.facts.sim_tick)+1700)
	_check("waiting_snapshot_invariants",restored_life.validate(restored).is_empty())
	print(JSON.stringify({"stage":17,"checks":checks,"failures":failures,"performance":"skipped"}))
	quit(0 if failures.is_empty() else 1)

func _step(world: WorldState, space: HospitalSpace, life: RefCounted) -> void:
	life.dispatch(world)
	space.advance(world)
	life.advance(world)
	world.facts.sim_tick += 1
	world.touch()
	space.finish_boundary(world)

func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	if not passed: failures.append(label)
