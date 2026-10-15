extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = FeasibilityHospitals.create("stage12-surgery",true,content)
	var space: HospitalSpace = HospitalSpace.new(content)
	var clinic: HospitalClinic = HospitalClinic.new(content,space)
	var visit: Dictionary = world.facts.visits.values()[0]
	visit.plan_decision = {"plan_id":visit.requested_plan_id,"source":"director"}
	var before: String = JSON.stringify(world.freeze())
	var quote: Dictionary = clinic.plan_quote(world,visit.id,visit.requested_plan_id)
	_check("surgery_quote_is_read_only",before==JSON.stringify(world.freeze()))
	_check("full_bundle",quote.ok)
	if quote.ok:
		_check("three_distinct_staff",quote.staff_ids.size()==3 and quote.staff_ids[0]!=quote.staff_ids[1] and quote.staff_ids[0]!=quote.staff_ids[2] and quote.staff_ids[1]!=quote.staff_ids[2])
		_check("coverage_separate_from_team",not quote.nurse_id in quote.staff_ids)
		_check("bed_quote_not_commitment",world.facts.ward_stays.is_empty() and world.facts.preparations.is_empty() and world.facts.inventory.issues.is_empty())
		world.facts.staff[quote.staff_ids[1]].abilities.surgery = 0
		_check("missing_anesthetist_cannot_start",not clinic.plan_quote(world,visit.id,visit.requested_plan_id).ok)
	var admitted: WorldState = FeasibilityHospitals.create("stage12-adapters",true,content)
	var case_visit: Dictionary = admitted.facts.visits.values()[0]
	for adapter: Dictionary in content.catalog.surgical_adapters:
		var binding: Dictionary = content.definition("treatment_bindings",adapter.binding_id)
		case_visit.binding_id = binding.id
		case_visit.disease_id = binding.disease_id
		case_visit.requested_plan_id = adapter.plan_id
		case_visit.plan_decision = {"plan_id":adapter.plan_id,"source":"director"}
		admitted.facts.actors[case_visit.actor_id].species_id = binding.species_id
		admitted.facts.actors[case_visit.actor_id].body_binding_id = binding.id
		var fitted: Dictionary = clinic.plan_quote(admitted,case_visit.id,adapter.plan_id,{"structural_only":true,"ignore_supplies":true})
		_check("adapter_"+str(adapter.id),fitted.has("ok") and (fitted.ok or not str(fitted.get("reason","")).is_empty()))
	print(JSON.stringify({"stage":12,"failures":failures,"performance":"skipped"}))
	quit(0 if failures.is_empty() else 1)

func _check(id: String, passed: bool) -> void:
	print(id+": "+("pass" if passed else "FAIL"))
	if not passed:
		failures.append(id)
