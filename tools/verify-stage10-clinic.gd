extends SceneTree

const Factory = preload("res://game/sim/hospital_factory.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var preset: WorldState = Factory.create("stage10-preset","预设院",true,content)
	var empty: WorldState = Factory.create("stage10-empty","空院",false,content)
	_check("preset_cash",HospitalLedger.balance(preset)==10600)
	_check("empty_cash",HospitalLedger.balance(empty)==24800)
	_check("actual_starter_stock",preset.facts.inventory.units==60 and empty.facts.inventory.units==60)
	_check("starter_roster",preset.facts.staff.size()==7 and empty.facts.staff.is_empty())
	_check("starter_layout",preset.facts.rooms.size()==6 and preset.facts.facilities.size()==19 and empty.facts.facilities.is_empty())
	_check("preset_valid",preset.validate(content).is_empty(),preset.validate(content))
	_check("empty_valid",empty.validate(content).is_empty(),empty.validate(content))
	var simulation: HospitalSimulation = HospitalSimulation.new(preset,content)
	var arrival: Dictionary = {"arrival_key":"opportunity-1","binding_id":"B_S49_D37_M37","name":"门诊患者"}
	var receipt: CommandResult = simulation.clinic.execute(preset,"clinical_arrive",arrival)
	_check("real_arrival",receipt.accepted and receipt.changed_ids.size()==2)
	if not receipt.accepted:
		_finish()
		return
	var visit_id: String = receipt.changed_ids[0]
	var actor_id: String = receipt.changed_ids[1]
	var count: int = preset.facts.actors.size()
	_check("arrival_once",simulation.clinic.execute(preset,"clinical_arrive",arrival).accepted and preset.facts.actors.size()==count and preset.facts.visits.size()==1)
	for step: int in 5000:
		simulation.step()
		if preset.facts.visits[visit_id].phase=="outpatient":
			break
	_check("real_attempt_started",preset.facts.visits[visit_id].attempt_ids.size()==1)
	var continuing: WorldState = WorldState.new(preset.freeze())
	_check("mid_treatment_valid",continuing.validate(content).is_empty(),continuing.validate(content))
	var restored: HospitalSimulation = HospitalSimulation.new(continuing,content)
	for step: int in 6000:
		restored.step()
		if continuing.facts.visits[visit_id].phase=="departed":
			break
	_check("actual_departure",continuing.facts.visits[visit_id].phase=="departed" and continuing.facts.actors[actor_id].location.kind=="outside",str(continuing.facts.visits[visit_id]))
	_check("attempt_supply_conservation",int(continuing.facts.inventory.units)+_issued(continuing)==60)
	_check("no_duplicate_consultation",_component_count(continuing,"consultation")==1)
	_check("no_duplicate_cure",_component_count(continuing,"cure")<=1)
	_check("final_valid",continuing.validate(content).is_empty(),continuing.validate(content))
	_finish()

func _issued(world: WorldState) -> int:
	var total: int = 0
	for issue: Dictionary in world.facts.inventory.issues.values():
		total += int(issue.units)
	return total

func _component_count(world: WorldState, component: String) -> int:
	var count: int = 0
	for entry: Dictionary in world.facts.ledger.entries.values():
		if entry.component==component:
			count += 1
	return count

func _check(id: String, passed: bool, reason: String = "") -> void:
	print(id+": "+("pass" if passed else "FAIL "+reason))
	if not passed:
		failures.append(id)

func _finish() -> void:
	print(JSON.stringify({"stage":10,"failures":failures,"performance":"skipped"}))
	quit(0 if failures.is_empty() else 1)
