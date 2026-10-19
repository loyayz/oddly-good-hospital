extends RefCounted

const Gathering = preload("res://tests/acceptance/clinical_gathering.gd")

class Queries extends HospitalClinic:
	var quotes: Dictionary = {}
	var gp_queries: int = 0
	var projection_observed: bool = false
	var projection_source: WorldState
	func plan_quote(world: WorldState, visit_id: String, plan_id: String, options: Dictionary = {}) -> Dictionary:
		var key: String = str(options.get("doctor_id",""))+":"+plan_id
		quotes[key] = int(quotes.get(key,0))+1
		if projection_source!=null and world!=projection_source:
			projection_observed = is_same(world.facts.actors,projection_source.facts.actors) and is_same(world.facts.visits,projection_source.facts.visits) and not is_same(world.facts.staff,projection_source.facts.staff) and not is_same(world.facts.staff.gather_worker,projection_source.facts.staff.gather_worker) and not world.facts.staff.gather_worker.supply_strike and projection_source.facts.staff.gather_worker.supply_strike
		return super.plan_quote(world,visit_id,plan_id,options)
	func service_candidates(world: WorldState, visit: Dictionary, kind: String, structural_only: bool = false, reference_schedule: bool = false, selection: Dictionary = {}) -> Array:
		if kind=="gp": gp_queries += 1
		return super.service_candidates(world,visit,kind,structural_only,reference_schedule,selection)

# Independent control retains the former second GP enumeration. Every returned
# quote, diagnostic stage and route is still produced by the production service.
class RepeatedReadiness extends Queries:
	func arrival_readiness(world: WorldState, binding_id: String, complex_case: bool = false, explain: bool = true) -> Dictionary:
		var candidate: Dictionary = _arrival_candidate(world,binding_id,complex_case)
		if not candidate.get("ok",false): return candidate
		var plans: Array = []
		var executable: bool = false
		var reasons: PackedStringArray = []
		if not HospitalResearch.disease_unlocked(world,content,candidate.visit.disease_id): reasons.append("病例研究尚未完成")
		for plan: Dictionary in content.catalog.treatment_plans:
			if plan.disease_id!=candidate.visit.disease_id: continue
			var quote: Dictionary = plan_quote(candidate.world,candidate.visit.id,plan.id,{"structural_only":true,"ignore_supplies":true})
			plans.append(quote)
			executable = executable or bool(quote.ok)
			if executable and not explain: break
		for kind: String in ["reception","gp"]:
			if service_candidates(candidate.world,candidate.visit,kind,true).is_empty(): reasons.append(_missing_service_reason(candidate.world,candidate.visit,kind))
		var diagnostics_ok: bool = false
		var query: Dictionary = {"candidates":{},"reference_schedule":false}
		for pair: Dictionary in service_candidates(candidate.world,candidate.visit,"gp",true):
			if _build_reference_diagnostic_stages(candidate.world,candidate.visit,pair,query).ok:
				diagnostics_ok = true
				break
		if not diagnostics_ok: reasons.append("全部合法检查仍未达到诊断阈值")
		if not executable:
			for quote: Dictionary in plans:
				reasons.append(str(content.definition("treatment_plans",quote.plan_id).get("name",quote.plan_id))+"："+str(quote.reason))
		return {"ok":executable and reasons.is_empty(),"reason":"；".join(reasons),"plans":plans}

func run_case(t, content: HospitalContent) -> void:
	var started: int = Time.get_ticks_usec()
	var first_doctor: Dictionary = _first_doctor_boundary(content)
	var c: Dictionary = Gathering.new()._context(content,"gp")
	var clinic: Queries = Queries.new(content,c.space)
	clinic.scheduler = HospitalShiftScheduler.new(content,c.space)
	clinic.scheduler.ensure(c.world)
	var visit: Dictionary = c.world.facts.visits.gather_visit_0
	var pairs: Array = clinic.service_candidates(c.world,visit,"consult")
	var before: Dictionary = c.world.freeze()
	var selected: Dictionary = clinic._select_plan(c.world,visit)
	var once: bool = not clinic.quotes.is_empty()
	for count: int in clinic.quotes.values(): once = once and count==1
	var recommendation: Dictionary = {"consult_pairs":pairs.size(),"quote_calls_by_doctor_plan":clinic.quotes.duplicate(),"no_executable_plan":selected.is_empty(),"readonly":before==c.world.freeze()}
	var actual: Queries = Queries.new(content,c.space)
	var control: RepeatedReadiness = RepeatedReadiness.new(content,c.space)
	var readiness: Dictionary = actual.arrival_readiness(c.world,visit.binding_id)
	var expected: Dictionary = control.arrival_readiness(c.world,visit.binding_id)
	var readiness_ok: bool = readiness==expected and actual.gp_queries+1==control.gp_queries and before==c.world.freeze()
	var projection: Queries = Queries.new(content,c.space)
	projection.projection_source = c.world
	c.world.facts.staff.gather_worker.supply_strike = true
	c.world.facts.inventory.units = 0
	c.world.facts.tickets[visit.ticket_id].kind = "outpatient"
	visit.phase = "wait_outpatient"
	var shortage_before: Dictionary = c.world.freeze()
	projection.shortage_requests(c.world)
	var projection_ok: bool = projection.projection_observed and shortage_before==c.world.freeze()
	t.check("CLIN-35",first_doctor.passed and c.validation.is_empty() and pairs.size()>1 and once and selected.is_empty() and recommendation.readonly and readiness_ok and projection_ok,{"input_validation":c.validation,"first_doctor_boundary":first_doctor,"CL-A01":{"recommendation":recommendation,"readiness_equal":readiness==expected,"gp_calls":actual.gp_queries,"control_gp_calls":control.gp_queries},"CL-A06":{"isolated_written_path_shared_readonly_facts":projection.projection_observed,"readonly":shortage_before==c.world.freeze()},"elapsed_usec":Time.get_ticks_usec()-started})

func _first_doctor_boundary(content: HospitalContent) -> Dictionary:
	var c: Dictionary = Gathering.new()._context(content,"gp")
	HospitalFactory._add_room(c.world,{"id":"later_treatment","type":"T01","anchor":[46,30],"size":[8,8],"door":{"definition_id":"DR04","offset":3}},content)
	HospitalFactory._add_facility(c.world,{"id":"later_machine","definition_id":"M09","anchor":[47,31],"size":content.facility_definition("M09").footprint,"room_id":"later_treatment"},content)
	HospitalFactory._add_staff(c.world,"later_doctor","可治疗医生","doctor",[36,24],content)
	c.world.facts.staff.gather_worker.abilities.treatment = 1
	c.world.facts.staff.later_doctor.abilities.treatment = 3
	for definition: Dictionary in content.catalog.research: c.world.facts.research.append(definition.id)
	c.world.touch()
	var clinic: Queries = Queries.new(content,c.space)
	var scheduler: HospitalShiftScheduler = HospitalShiftScheduler.new(content,c.space)
	scheduler.ensure(c.world)
	var visit: Dictionary = c.world.facts.visits.gather_visit_0
	var binding: Dictionary = content.definition("treatment_bindings","B_S22_D14_M14")
	visit.binding_id = binding.id
	visit.disease_id = binding.disease_id
	visit.requested_plan_id = "P_D14_COMMON"
	c.world.facts.actors[visit.actor_id].species_id = binding.species_id
	c.world.facts.actors[visit.actor_id].body_binding_id = binding.id
	c.world.touch()
	var validation: String = c.world.validate(content)
	var before: Dictionary = c.world.freeze()
	var pairs: Array = clinic.service_candidates(c.world,visit,"consult")
	var explicit_later: Dictionary = clinic._select_plan(c.world,visit,"later_doctor")
	var first_only: Dictionary = clinic._select_plan(c.world,visit)
	clinic.scheduler = scheduler
	var scheduled_before: Dictionary = c.world.freeze()
	var selected_pair: Dictionary = {}
	var scheduled: Dictionary = clinic._select_plan(c.world,visit,"",selected_pair)
	return {"passed":validation.is_empty() and not pairs.is_empty() and pairs[0].staff_id=="gather_worker" and not explicit_later.is_empty() and first_only.is_empty() and scheduled==explicit_later and selected_pair.get("pair",{}).get("staff_id","")=="later_doctor" and c.world.freeze()==scheduled_before and before==scheduled_before,"validation":validation,"first_pair":pairs[0] if not pairs.is_empty() else {},"later_doctor_has_legal_plan":not explicit_later.is_empty(),"no_scheduler_preserves_first_failure":first_only.is_empty(),"scheduler_selects_original_next_doctor":scheduled==explicit_later,"selected_pair":selected_pair,"facts_rng_readonly":c.world.freeze()==scheduled_before}
