extends "res://tests/acceptance/growth_fixtures.gd"

class FullRouting extends HospitalDepartments:
	func readiness(world: WorldState, department_id: String, visit_id: String, _structural_only: bool = false) -> Dictionary:
		return super.readiness(world,department_id,visit_id,false)

class CountedClinic extends HospitalClinic:
	var comparisons: int = 0
	func compare_plans(world: WorldState, visit_id: String) -> Array:
		comparisons += 1
		return super.compare_plans(world,visit_id)

func run_case(t, database: HospitalContent) -> void:
	_content = database
	var protection: Dictionary = protection_case()
	var routing: Dictionary = routing_case()
	for simulation: HospitalSimulation in _simulations: simulation.dispose()
	_simulations.clear()
	t.check("GROW-83",protection.passed and routing.passed,{"protection":protection,"routing":routing})

func protection_case() -> Dictionary:
	var ctx: Dictionary = _context()
	var first: Dictionary = _resident(ctx,[46,93])
	var second: Dictionary = _resident(ctx,[44,93])
	if first.is_empty() or second.is_empty(): return {"passed":false,"errors":_fixture_errors}
	# Reference protection is a read-only query: these are legal reference
	# records at their active/terminal boundary, not simulated activity progress.
	ctx.world.facts.activities = {"active":{"state":"active","resident_ids":[first.resident.id,first.resident.id],"resident_id":first.resident.id},"ended":{"state":"ended","resident_ids":[second.resident.id]}}
	ctx.world.facts.community_activities = {"listed":{"phase":"recruiting","participants":[second.resident.id]}}
	ctx.world.facts.interactions = {"closed":{"state":"completed","resident_id":first.resident.id}}
	ctx.world.facts.visitor_stays = {"visiting":{"phase":"visiting","resident_id":first.resident.id}}
	ctx.world.facts.care_jobs = {"help":{"phase":"working","participants":[first.resident.id,second.resident.id]}}
	first.resident.story_binding = "protected_story"
	var before: Dictionary = ctx.world.freeze()
	var index: Dictionary = ctx.arrivals._resident_protection(ctx.world)
	var exact: bool = true
	for resident: Dictionary in [first.resident,second.resident]:
		for ignore_story: bool in [false,true]:
			exact = exact and ctx.arrivals._protected_reasons(ctx.world,resident,ignore_story)==ctx.arrivals._protected_reasons(ctx.world,resident,ignore_story,index)
	var expected: Array = ["本次实际离院后腾出位置","当前就诊尚未结束","仍关联活动、互动或照护","仍关联活动、互动或照护","仍关联活动、互动或照护","故事保留同一人物身份"]
	exact = exact and ctx.arrivals._protected_reasons(ctx.world,first.resident,false,index)==expected
	var readonly: bool = ctx.world.freeze()==before
	# A later boundary must see direct changes; no map survives the query.
	ctx.world.facts.activities.active.state = "completed"
	ctx.world.facts.visitor_stays.visiting.phase = "departed"
	ctx.world.facts.care_jobs.help.phase = "cancelled"
	ctx.world.facts.community_activities.listed.phase = "ended"
	var fresh: Dictionary = ctx.arrivals._resident_protection(ctx.world)
	var refreshed: bool = ctx.arrivals._protected_reasons(ctx.world,first.resident,true,fresh)==["本次实际离院后腾出位置","当前就诊尚未结束"] and ctx.arrivals._protected_reasons(ctx.world,first.resident,false,fresh)==ctx.arrivals._protected_reasons(ctx.world,first.resident)
	first.resident.pending_release = true
	first.resident.remembered = false
	ctx.arrivals.settle(ctx.world)
	var held: bool = ctx.world.facts.residents.has(first.resident.id)
	first.resident.story_binding = ""
	ctx.arrivals.settle(ctx.world)
	held = held and ctx.world.facts.residents.has(first.resident.id) and ctx.world.facts.residents.has(second.resident.id)
	return {"passed":exact and readonly and refreshed and held,"exact_reasons_and_multiplicity":exact,"readonly":readonly,"next_boundary_changes_visible":refreshed,"inpatient_identity_held":held}

func routing_case() -> Dictionary:
	var builder: RefCounted = load("res://tests/acceptance/operations.gd").new()
	builder._content = _content
	var source: Dictionary = builder._route_fixture("导诊结构查询对照")
	if source.visit_id.is_empty() or not source.errors.is_empty(): return {"passed":false,"errors":source.errors}
	var equal: bool = true
	var observations: Array = []
	var full_calls: int = 0
	var structural_calls: int = 0
	for condition: String in ["ordinary","supplies","off_shift","equipment","scope","research"]:
		for error_hit: bool in [false,true]:
			var facts: Dictionary = source.w.freeze()
			if condition=="supplies": facts.inventory.units = 0
			if condition=="off_shift":
				for staff: Dictionary in facts.staff.values(): staff.on_shift = false
			if condition=="equipment":
				for facility: Dictionary in facts.facilities.values():
					if facility.definition_id=="M37": facility.failed = true
			if condition=="scope": facts.departments.units.ops_right.intake_disease_ids = ["D09"]
			if condition=="research": facts.research.clear()
			var actual: HospitalSimulation = HospitalSimulation.new(WorldState.new(facts.duplicate(true)),_content)
			var previous: HospitalSimulation = HospitalSimulation.new(WorldState.new(facts.duplicate(true)),_content)
			var old_department: FullRouting = FullRouting.new(_content,previous.space)
			old_department.clinic = previous.clinic
			old_department.waiting_life = previous.services.waiting
			old_department.environment = previous.services.environment
			previous.services.departments = old_department
			previous.clinic.departments = old_department
			var observed_actual: CountedClinic = counted_clinic(actual)
			var observed_previous: CountedClinic = counted_clinic(previous)
			builder._registration_seed(actual.world,error_hit)
			builder._registration_seed(previous.world,error_hit)
			var identical: bool = true
			for repeated: int in 3:
				var routed: bool = actual.services.departments.route_patient(actual.world,source.visit_id)
				var original: bool = previous.services.departments.route_patient(previous.world,source.visit_id)
				identical = identical and routed==original and actual.world.freeze()==previous.world.freeze()
			var candidates: bool = actual.clinic.service_candidates(actual.world,actual.world.facts.visits[source.visit_id],"gp")==previous.clinic.service_candidates(previous.world,previous.world.facts.visits[source.visit_id],"gp")
			full_calls += observed_previous.comparisons
			structural_calls += observed_actual.comparisons
			equal = equal and identical and candidates
			observations.append({"condition":condition,"error_hit":error_hit,"all_facts_and_rng_equal":identical,"actual_candidates_equal":candidates})
			actual.dispose()
			previous.dispose()
	for simulation: HospitalSimulation in builder._live: simulation.dispose()
	return {"passed":equal and full_calls>0 and structural_calls==0,"comparisons_before":full_calls,"comparisons_after":structural_calls,"observations":observations}

func counted_clinic(simulation: HospitalSimulation) -> CountedClinic:
	var observed: CountedClinic = CountedClinic.new(_content,simulation.space)
	for property: Dictionary in simulation.clinic.get_property_list():
		if (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)!=0: observed.set(property.name,simulation.clinic.get(property.name))
	simulation.clinic = observed
	simulation.services.departments.clinic = observed
	return observed
