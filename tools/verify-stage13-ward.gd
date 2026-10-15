extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = FeasibilityHospitals.create("stage13-ward",true,content)
	var treatment_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	treatment_rng.seed = 1
	world.facts.rng.treatment = {"algorithm":"godot-pcg32-4.7.2","seed_decimal":str(treatment_rng.seed),"state_decimal":str(treatment_rng.state)}
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	var visit: Dictionary = world.facts.visits.values()[0]
	for tick: int in 8000:
		simulation.step()
		if visit.phase=="recovery": break
	_check("real_surgery_handoff",visit.phase=="recovery" and world.facts.ward_stays.size()==1)
	if world.facts.ward_stays.is_empty():
		_finish()
		return
	var stay: Dictionary = world.facts.ward_stays.values()[0]
	var attempt_count: int = visit.attempt_ids.size()
	var units: int = int(world.facts.inventory.units)
	var remaining: int = int(stay.remaining_ticks)
	world.facts.staff[stay.nurse_id].on_shift = false
	for tick: int in 10: simulation.step()
	_check("no_remote_or_off_shift_recovery",int(stay.remaining_ticks)==remaining)
	world.facts.staff[stay.nurse_id].on_shift = true
	var restored: WorldState = WorldState.new(world.freeze())
	_check("ward_snapshot_invariants",simulation.clinic.validate(restored).is_empty())
	var continued: HospitalSimulation = HospitalSimulation.new(restored,content)
	var restored_visit: Dictionary = restored.facts.visits[visit.id]
	for tick: int in 8000:
		continued.step()
		if restored_visit.phase=="departed": break
	_check("safe_ward_completes",restored_visit.phase=="departed" and restored_visit.final_result=="cured")
	_check("recovery_does_not_create_attempt",restored_visit.attempt_ids.size()==attempt_count)
	_check("original_attempt_supply_receipt",restored.facts.inventory.issues.has(stay.attempt_id) and int(restored.facts.inventory.units)==units)
	var ward_fee_count: int = 0
	for entry: Dictionary in restored.facts.ledger.entries.values():
		if entry.owner_id==stay.attempt_id and entry.component=="ward": ward_fee_count += 1
	_check("one_fee_after_actual_recovery",ward_fee_count==1)
	continued.clinic.ensure(restored)
	_check("visitor_collection_saved",restored.freeze().has("visitors"))
	_check("visitor_invariants",continued.clinic.validate(restored).is_empty())
	_finish()

func _check(id: String, passed: bool) -> void:
	print(id+": "+("pass" if passed else "FAIL"))
	if not passed: failures.append(id)

func _finish() -> void:
	print(JSON.stringify({"stage":13,"failures":failures,"performance":"skipped"}))
	quit(0 if failures.is_empty() else 1)
