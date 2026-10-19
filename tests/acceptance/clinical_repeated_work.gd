extends RefCounted

const Gathering = preload("res://tests/acceptance/clinical_gathering.gd")

class Queries extends HospitalClinic:
	var quotes: Dictionary = {}
	var gp_queries: int = 0
	var projection_observed: bool = false
	var projection_source: WorldState
	var physical_calls: int = 0
	func _service_pair_reachable(world: WorldState, visit: Dictionary, facility_id: String, staff_id: String, layout: Dictionary) -> bool:
		physical_calls += 1
		return super._service_pair_reachable(world,visit,facility_id,staff_id,layout)
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
	var plan_batch: Dictionary = _plan_batch_boundary(content)
	var reachability: Dictionary = _reachability_boundary(content)
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
	t.check("CLIN-35",reachability.passed and plan_batch.passed and first_doctor.passed and c.validation.is_empty() and pairs.size()>1 and once and selected.is_empty() and recommendation.readonly and readiness_ok and projection_ok,{"input_validation":c.validation,"boolean_reachability":reachability,"plan_batch":plan_batch,"first_doctor_boundary":first_doctor,"CL-A01":{"recommendation":recommendation,"readiness_equal":readiness==expected,"gp_calls":actual.gp_queries,"control_gp_calls":control.gp_queries},"CL-A06":{"isolated_written_path_shared_readonly_facts":projection.projection_observed,"readonly":shortage_before==c.world.freeze()},"elapsed_usec":Time.get_ticks_usec()-started})

func _reachability_boundary(content: HospitalContent) -> Dictionary:
	var c: Dictionary = Gathering.new()._context(content,"gp")
	var world: WorldState = c.world
	var plots: Array = HospitalSpace.floor_plots(world,1).duplicate(true)
	world.facts.floors.completed_top_floor = {}
	for plot: Array in plots: world.facts.floors.completed_top_floor[HospitalSpace.plot_key(plot)] = 2
	world.facts.floors.height_intervals = [{"first":1,"last":2,"height_m":float(content.balance.floors.clear_height_m)}]
	world.facts.floors.overrides["2"] = {"plots":plots,"blocked":[],"doors":[],"paths":[]}
	world.facts.actors.gather_patient_0.location.floor_id = 2
	world.facts.actors.gather_patient_0.location.cell = [20.35,24.35]
	for index: int in 2:
		var id: String = "reach_lift_"+str(index)
		world.facts.connectors[id] = {"id":id,"definition_id":"VC02","first_floor":1,"last_floor":2,"cell":[60+index*10,20],"footprint":[4,4],"rotation":0,"anchor":[61+index*10,24],"repair_cell":[59+index*10,21],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0,"ticket_next":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},"paid_cost":3200,"used":false}
	HospitalFactory._add_staff(world,"reach_blocker","出口人物","cleaner",[61,24],content)
	world.touch()
	var validation: String = world.validate(content)
	var before: Dictionary = world.freeze()
	var results: Array = []
	var passed: bool = validation.is_empty()
	var goal: Array = c.space.facility_layout(world,"gather_facility_0").patient_cell
	for nominal: bool in [false,true]:
		var actual: HospitalSpace = HospitalSpace.new(content)
		var cold: HospitalSpace = HospitalSpace.new(content)
		var reference: Dictionary = {"nominal":true} if nominal else {}
		actual.begin_route_query(world,reference,false)
		cold.begin_route_query(world,{"nominal":true} if nominal else {},false)
		var reachable: bool = actual.can_reach(world,"gather_patient_0",1,goal,[],{},true)
		var no_partial_cache: bool = reference.get("journeys",{}).is_empty()
		var full: Dictionary = actual.route(world,"gather_patient_0",1,goal,[],{},true)
		var expected: Dictionary = cold.route(world,"gather_patient_0",1,goal,[],{},true)
		var warm: bool = actual.can_reach(world,"gather_patient_0",1,goal,[],{},true)
		var exact: bool = reachable==bool(expected.ok) and warm==reachable and full==expected and no_partial_cache
		if not nominal: exact = exact and not reachable and full.get("status","")=="estimate_unknown"
		else: exact = exact and reachable
		actual.end_route_query()
		cold.end_route_query()
		passed = passed and exact and before==world.freeze()
		results.append({"nominal":nominal,"boolean":reachable,"full_ok":full.ok,"status":full.get("status",""),"full_after_boolean_matches_cold":full==expected,"no_partial_journey_cache":no_partial_cache,"warm_equal":warm==reachable,"readonly":before==world.freeze()})
	# The first blocked connection coexists with a clear second connection.
	# Only actual walking clears that first exit; the next query must recover.
	var live: HospitalSpace = HospitalSpace.new(content)
	var move_reason: String = live.request_move(world,"reach_blocker",1,[65,28])
	var steps: int = 0
	while world.facts.moves.has("reach_blocker") and steps<100:
		live.advance(world)
		world.facts.sim_tick += 1
		world.touch(false)
		live.finish_boundary(world)
		steps += 1
	var recovered: bool = live.can_reach(world,"gather_patient_0",1,goal,[],{},true)
	var complete: Dictionary = live.route(world,"gather_patient_0",1,goal,[],{},true)
	var same_floor: Array = world.facts.actors.gather_patient_0.location.cell.duplicate()
	var same_floor_ok: bool = live.can_reach(world,"gather_patient_0",2,same_floor,[],{},true)==bool(live.route(world,"gather_patient_0",2,same_floor,[],{},true).ok)
	var outside: bool = live.can_reach(world,"gather_patient_0",2,[200,200],[],{},true)
	return {"passed":passed and move_reason.is_empty() and steps>0 and steps<100 and recovered and complete.ok and same_floor_ok and not outside and world.validate(content).is_empty(),"validation":validation,"queries":results,"real_exit_steps":steps,"recovered_after_real_walk":recovered and complete.ok,"same_floor_boolean_equal":same_floor_ok,"outside_rejected":not outside}

func _plan_batch_boundary(content: HospitalContent) -> Dictionary:
	var c: Dictionary = Gathering.new()._context(content,"gp")
	HospitalFactory._add_room(c.world,{"id":"batch_treatment","type":"T01","anchor":[46,30],"size":[8,8],"door":{"definition_id":"DR04","offset":3}},content)
	HospitalFactory._add_facility(c.world,{"id":"batch_machine","definition_id":"M09","anchor":[47,31],"size":content.facility_definition("M09").footprint,"room_id":"batch_treatment"},content)
	c.world.facts.staff.gather_worker.abilities.treatment = 2
	for definition: Dictionary in content.catalog.research: c.world.facts.research.append(definition.id)
	c.world.touch()
	var validation: String = c.world.validate(content)
	var before: Dictionary = c.world.freeze()
	var clinic: Queries = Queries.new(content,c.space)
	var independent: Array = []
	for plan: Dictionary in content.catalog.treatment_plans:
		if plan.disease_id=="D09": independent.append(clinic.plan_quote(c.world,"gather_visit_0",plan.id))
	var separate_calls: int = clinic.physical_calls
	clinic.physical_calls = 0
	var combined: Array = clinic.compare_plans(c.world,"gather_visit_0")
	var shared_calls: int = clinic.physical_calls
	var readonly: bool = c.world.freeze()==before
	# Direct live changes between queries must be seen without a touch/cache reset.
	c.world.facts.facilities.batch_machine.failed = true
	var failed: Array = clinic.compare_plans(c.world,"gather_visit_0")
	var fresh: bool = not failed.is_empty()
	for quote: Dictionary in failed: fresh = fresh and not quote.ok
	# Nominal geometry ignores people; actual structural fit still respects a
	# different patient's real body. Modes can nest on the same read-only world.
	c.world.facts.facilities.batch_machine.failed = false
	var position: Array = c.space.facility_layout(c.world,"batch_machine").patient_cell
	c.world.facts.actors.gather_patient_1.location.cell = position.duplicate()
	c.world.touch(false)
	var blocked_validation: String = c.world.validate(content)
	var blocked_source: Dictionary = c.world.freeze()
	var modes: Array = []
	var mode_safe: bool = true
	for nominal_first: bool in [true,false]:
		c.space.begin_route_query(c.world,{"nominal":true},false)
		var nominal: Dictionary = {}
		var actual: Dictionary = {}
		if nominal_first: nominal = clinic.plan_quote(c.world,"gather_visit_0","P_D09_COMMON",{"structural_only":true,"ignore_supplies":true})
		c.space.begin_route_query(c.world,{},false)
		actual = clinic.plan_quote(c.world,"gather_visit_0","P_D09_COMMON",{"structural_only":true,"ignore_supplies":true})
		c.space.end_route_query()
		if not nominal_first: nominal = clinic.plan_quote(c.world,"gather_visit_0","P_D09_COMMON",{"structural_only":true,"ignore_supplies":true})
		c.space.end_route_query()
		var cold: Dictionary = clinic.plan_quote(c.world,"gather_visit_0","P_D09_COMMON",{"structural_only":true,"ignore_supplies":true})
		var exact: bool = nominal.ok and not actual.ok and actual==cold and blocked_source==c.world.freeze()
		mode_safe = mode_safe and exact
		modes.append({"nominal_first":nominal_first,"nominal_ok":nominal.ok,"actual_ok":actual.ok,"actual_matches_cold":actual==cold,"readonly":blocked_source==c.world.freeze()})
	return {"passed":validation.is_empty() and blocked_validation.is_empty() and mode_safe and combined==independent and combined.size()>=2 and shared_calls>0 and separate_calls>shared_calls and readonly and fresh,"validation":validation,"separate_physical_calls":separate_calls,"same_query_physical_calls":shared_calls,"complete_quotes_equal":combined==independent,"readonly":readonly,"next_query_direct_failure_visible":fresh,"nested_nominal_actual":{"validation":blocked_validation,"both_orders_safe":mode_safe,"observations":modes}}

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
