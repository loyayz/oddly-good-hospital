extends SceneTree

const Factory = preload("res://game/sim/hospital_factory.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = Factory.create("stage11-two-receptions","连续接待",true,content)
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	var first: CommandResult = simulation.clinic.execute(world,"clinical_arrive",{"arrival_key":"first","binding_id":"B_S49_D37_M37"})
	_check("first_real_arrival",first.accepted)
	if first.accepted:
		for tick: int in 300:
			simulation.step()
			if world.facts.visits[first.changed_ids[0]].has("registration_receipt"): break
	var second: CommandResult = simulation.clinic.execute(world,"clinical_arrive",{"arrival_key":"second","binding_id":"B_S49_D37_M37"})
	_check("second_real_arrival",second.accepted)
	if first.accepted and second.accepted:
		var first_visit: Dictionary = world.facts.visits[first.changed_ids[0]]
		var second_visit: Dictionary = world.facts.visits[second.changed_ids[0]]
		for tick: int in 500:
			simulation.step()
			if second_visit.has("registration_receipt"): break
		_check("two_patients_complete_real_reception",first_visit.has("registration_receipt") and second_visit.has("registration_receipt") and first_visit.registration_receipt.id!=second_visit.registration_receipt.id)
		_check("operator_reused_without_teleport",first_visit.get("registration_receipt",{}).get("staff_id","")==second_visit.get("registration_receipt",{}).get("staff_id","") and not second_visit.get("registration_receipt",{}).is_empty())
		_check("real_reservations_keep_valid_owners",world.validate(content).is_empty())
	print(JSON.stringify({"stage":11,"suite":"consecutive_receptions","failures":failures,"performance":"skipped"}))
	quit(0 if failures.is_empty() else 1)

func _check(id: String, passed: bool) -> void:
	print(id+": "+("pass" if passed else "FAIL"))
	if not passed: failures.append(id)
