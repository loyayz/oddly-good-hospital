extends "res://tests/acceptance/growth_fixtures.gd"

class ScalarComponents extends HospitalClinic:
	func _reference_component(full: Dictionary, stages: Array, weight: Dictionary = {"n":"1","d":"1"}, _batch: Variant = null) -> Dictionary:
		return super._reference_component(full,stages,weight)
	func _reference_bed_alternatives(world: WorldState, visit: Dictionary, floor_id: int, excluded: Array, _cache: Dictionary) -> Array:
		var beds: Array = []
		_compatible_bed(world,visit,floor_id,excluded,true,"",true,beds)
		return beds

class FailedReference extends HospitalClinic:
	var fail: bool = true
	var failed_binding: String = ""
	var failures: int = 0
	func reference_demand(world: WorldState, binding_id: String, complex_case: bool = false, shift: int = 0, query: Variant = null) -> Dictionary:
		if fail and (failed_binding.is_empty() or failed_binding==binding_id):
			failures += 1
			return {"ok":false,"error":"reference_component_failure","reason":"injected numerical failure","bundles":[]}
		return super.reference_demand(world,binding_id,complex_case,shift,query)

# Fault injection tests the private numerical handoff, not a hospital process or
# an accepted clinical commitment. Every input below is an exact stage amount.
class FailureProbe extends HospitalClinic:
	var fail_on_flush: int = 2
	var flushes: int = 0
	var early_failure: bool = false
	var empty_model: bool = false
	var first_target: Dictionary = {}
	var amount_count: int = REFERENCE_COMPONENT_REQUEST_LIMIT+1
	func _flush_reference_components(batch: Dictionary) -> void:
		flushes += 1
		if flushes==fail_on_flush:
			batch.error = "injected later numerical batch failure"
			return
		super._flush_reference_components(batch)
	func _build_reference_model(options: Dictionary, _binding_id: String, _complex_case: bool, _shift: int) -> Dictionary:
		var targets: Array = []
		for amount: int in range(1,amount_count+1):
			var full: Dictionary = {"stage_resources":{"consult":{"staff:doctor":{"n":str(amount),"d":"1"}}},"structural_resources":[],"staff_ids":[]}
			var target: Dictionary = _reference_component(full,["consult"],{"n":"1","d":"1"},options.query.component_batch)
			target.choices = ["choice_"+str(amount)]
			targets.append(target)
			if amount==1: first_target = target
			if early_failure: return {"ok":false,"reason":"original early business failure","bundles":[]}
		if empty_model: return {"ok":false,"bundles":[],"model":{"bundles":[],"choice_groups":{"diagnostic":targets}}}
		return {"ok":true,"bundles":[],"model":{"bundles":targets,"choice_groups":{}}}

func run_case(t, database: HospitalContent) -> void:
	_content = database
	var observations: Dictionary = {"exact_inputs":_exact_inputs(),"unique_boundary":_unique_boundary(),"target_boundary":_target_boundary(),
		"memo_bound":_memo_bound(),"prefix_weighting":_prefix_weighting(),"failure_cleanup":_failure_cleanup(),"capacity_failure":_capacity_failure(),"complete_models":_complete_models()}
	var correct: bool = true
	for name: String in observations: correct = correct and bool(observations[name].passed)
	for simulation: HospitalSimulation in _simulations: simulation.dispose()
	_simulations.clear()
	t.check("GROW-79",correct,observations)

func _clinic() -> HospitalClinic:
	return HospitalClinic.new(_content,HospitalSpace.new(_content))

func _full(stages: Dictionary, staff_ids: Array = []) -> Dictionary:
	var structural: Array = []
	for stage: Dictionary in stages.values():
		for resource: String in stage:
			if not resource in structural: structural.append(resource)
	structural.sort()
	return {"stage_resources":stages,"staff_ids":staff_ids,"structural_resources":structural}

func _append_number(clinic: HospitalClinic, batch: Dictionary, pairs: Array, stages: Dictionary, weight: Dictionary, staff_ids: Array = []) -> Dictionary:
	var target: Dictionary = clinic._reference_component(_full(stages,staff_ids),stages.keys(),weight,batch)
	pairs.append({"target":target,"expected":PlatformArrivalMath.aggregate_stages(stages,weight)})
	return target

func _exact_inputs() -> Dictionary:
	var clinic: HospitalClinic = _clinic()
	var batch: Dictionary = clinic._new_reference_component_batch()
	var pairs: Array = []
	var stages: Dictionary = {"gp":{"staff:gp":{"n":"2","d":"1"},"facility:gp":{"n":"3","d":"1"}},"consult":{}}
	var a: Dictionary = _append_number(clinic,batch,pairs,stages,{"n":"1","d":"2"},["terminal_a"])
	a.choices = ["choice_a"]
	a.structural_choices = ["structure_a"]
	var reordered: Dictionary = {"consult":{},"gp":{"facility:gp":{"d":"1","n":"3"},"staff:gp":{"d":"1","n":"2"}}}
	var b: Dictionary = _append_number(clinic,batch,pairs,reordered,{"d":"2","n":"1"},["terminal_b"])
	b.choices = ["choice_b"]
	b.structural_choices = ["structure_b"]
	# A source edit cannot mutate a memo key or an already queued input.
	stages.gp["staff:gp"].n = "11"
	_append_number(clinic,batch,pairs,stages,{"n":"1","d":"2"})
	stages.gp["staff:gp"].n = "2"
	_append_number(clinic,batch,pairs,stages,{"n":"1","d":"2"})
	_append_number(clinic,batch,pairs,stages,{"n":"1","d":"3"})
	for amounts: Array in [[2,3],[3,2]]:
		_append_number(clinic,batch,pairs,{"gp":{"staff:gp":{"n":str(amounts[0]),"d":"1"}},"consult":{"staff:gp":{"n":str(amounts[1]),"d":"1"}}},{"n":"1","d":"1"})
	for amount: String in ["9007199254740992","9007199254740993"]:
		_append_number(clinic,batch,pairs,{"gp":{"staff:gp":{"n":amount,"d":"1"}}},{"n":"1","d":"1"})
	for value: Dictionary in [{"gp":{}},{"gp":{"staff:gp":{"n":"0","d":"1"}}},{}]:
		_append_number(clinic,batch,pairs,value,{"n":"0","d":"1"})
	var error: String = clinic._finish_reference_component_batch(batch)
	var equal: bool = error.is_empty()
	for pair: Dictionary in pairs:
		equal = equal and pair.target.resources==pair.expected.resources and pair.target.stage_resources==pair.expected.stage_resources
	var independent: bool = not is_same(a,b) and is_same(a.resources,b.resources) and is_same(a.stage_resources,b.stage_resources)
	a.choices.append("only_a")
	independent = independent and b.choices==["choice_b"] and b.structural_choices==["structure_b"] and a.staff_ids==["terminal_a"] and b.staff_ids==["terminal_b"]
	var observed: Dictionary = clinic.reference_component_observation()
	var counts: bool = observed.components==12 and observed.unique_inputs==10 and observed.memo_hits==2 and observed.native_requests==10
	return {"passed":equal and independent and counts and batch.memo.is_empty() and batch.pending.is_empty(),"exact_scalar_equal":equal,"independent_metadata":independent,"counts":observed}

func _unique_boundary() -> Dictionary:
	var clinic: HospitalClinic = _clinic()
	var batch: Dictionary = clinic._new_reference_component_batch()
	var targets: Array = []
	var count: int = HospitalClinic.REFERENCE_COMPONENT_REQUEST_LIMIT*2+1
	for amount: int in range(1,count+1):
		var target: Dictionary = clinic._reference_component(_full({"consult":{"staff:doctor":{"n":str(amount),"d":"1"}}}),["consult"],{"n":"1","d":"1"},batch)
		target.choices = ["choice_"+str(amount)]
		targets.append(target)
	var before: Dictionary = clinic.reference_component_observation({"component_batch":batch})
	var repeated: Dictionary = clinic._reference_component(_full({"consult":{"staff:doctor":{"n":"1","d":"1"}}}),["consult"],{"n":"1","d":"1"},batch)
	var error: String = clinic._finish_reference_component_batch(batch)
	var ordered: bool = true
	for index: int in targets.size():
		ordered = ordered and targets[index].resources["staff:doctor"]=={"n":str(index+1),"d":"1"} and targets[index].choices==["choice_"+str(index+1)]
	var observed: Dictionary = clinic.reference_component_observation()
	var bounded: bool = before.pending_requests==1 and before.waiting_targets==1 and before.native_calls==2 and observed.native_calls==3 and observed.native_requests==count and observed.max_pending_requests==HospitalClinic.REFERENCE_COMPONENT_REQUEST_LIMIT
	var shared: bool = not is_same(repeated,targets[0]) and is_same(repeated.resources,targets[0].resources)
	return {"passed":error.is_empty() and ordered and bounded and shared and batch.memo.is_empty(),"order_and_amounts":ordered,"cross_batch_reuse":shared,"counts":observed}

func _target_boundary() -> Dictionary:
	var clinic: HospitalClinic = _clinic()
	var batch: Dictionary = clinic._new_reference_component_batch()
	var targets: Array = []
	for index: int in HospitalClinic.REFERENCE_COMPONENT_TARGET_LIMIT+1:
		var target: Dictionary = clinic._reference_component(_full({"gp":{"staff:gp":{"n":"17","d":"1"}}},["team_"+str(index)]),["gp"],{"n":"1","d":"1"},batch)
		targets.append(target)
	var error: String = clinic._finish_reference_component_batch(batch)
	var independent: bool = true
	for index: int in targets.size():
		independent = independent and targets[index].staff_ids==["team_"+str(index)] and targets[index].resources["staff:gp"]=={"n":"17","d":"1"}
	var observed: Dictionary = clinic.reference_component_observation()
	var bounded: bool = observed.unique_inputs==1 and observed.native_calls==1 and observed.native_requests==1 and observed.max_waiting_targets==HospitalClinic.REFERENCE_COMPONENT_TARGET_LIMIT and observed.waiting_targets==0
	return {"passed":error.is_empty() and independent and bounded and not is_same(targets[0],targets[1]) and is_same(targets[0].resources,targets[-1].resources),"independent_targets":independent,"counts":observed}

func _memo_bound() -> Dictionary:
	var clinic: HospitalClinic = _clinic()
	var batch: Dictionary = clinic._new_reference_component_batch()
	var targets: Array = []
	var count: int = HospitalClinic.REFERENCE_COMPONENT_MEMO_LIMIT+HospitalClinic.REFERENCE_COMPONENT_REQUEST_LIMIT+1
	for amount: int in range(1,count+1):
		targets.append(clinic._reference_component(_full({"care":{"staff:nurse":{"n":str(amount),"d":"1"}}}),["care"],{"n":"1","d":"1"},batch))
	var retained: Dictionary = clinic._reference_component(_full({"care":{"staff:nurse":{"n":str(count-1),"d":"1"}}}),["care"],{"n":"1","d":"1"},batch)
	var evicted: Dictionary = clinic._reference_component(_full({"care":{"staff:nurse":{"n":"1","d":"1"}}}),["care"],{"n":"1","d":"1"},batch)
	var before: Dictionary = clinic.reference_component_observation({"component_batch":batch})
	var error: String = clinic._finish_reference_component_batch(batch)
	var equal: bool = error.is_empty()
	for index: int in targets.size(): equal = equal and targets[index].resources["staff:nurse"]==F.make(index+1)
	var observed: Dictionary = clinic.reference_component_observation()
	var reuse: bool = is_same(retained.resources,targets[count-2].resources) and evicted==targets[0] and not is_same(evicted.resources,targets[0].resources)
	var bounded: bool = before.active_unique_inputs==HospitalClinic.REFERENCE_COMPONENT_MEMO_LIMIT and before.active_completed_entries<=HospitalClinic.REFERENCE_COMPONENT_MEMO_LIMIT and observed.max_memo_entries==HospitalClinic.REFERENCE_COMPONENT_MEMO_LIMIT and observed.max_completed_entries<=HospitalClinic.REFERENCE_COMPONENT_MEMO_LIMIT and observed.memo_evictions==count+1-HospitalClinic.REFERENCE_COMPONENT_MEMO_LIMIT and observed.native_requests==count+1
	return {"passed":equal and reuse and bounded and batch.memo.is_empty() and batch.completed.is_empty(),"all_targets_exact":equal,"retained_hit_and_evicted_recompute":reuse,"bounded":bounded,"before_finish":before,"counts":observed}

func _prefix_weighting() -> Dictionary:
	var observations: Array = []
	var correct: bool = true
	for early: bool in [false,true]:
		var clinic: HospitalClinic = _clinic()
		var batch: Dictionary = clinic._new_reference_component_batch()
		var query: Dictionary = {"consultations":{},"component_batch":batch}
		var options: Dictionary = {"query":query,"consultations":[{"staff_id":"doctor","facility_id":"consultation"}]}
		var terminal: Dictionary = {"consulting_doctor_id":"doctor"}
		var prefix: Dictionary = clinic._reference_consultations(options,terminal)[0]
		if early:
			for amount: int in range(1,HospitalClinic.REFERENCE_COMPONENT_REQUEST_LIMIT):
				clinic._reference_component(_full({"gp":{"staff:gp":{"n":str(amount),"d":"1"}}}),["gp"],{"n":"1","d":"1"},batch)
		var was_assembled: bool = prefix.has("resources")
		var quarter: Dictionary = clinic._reference_consultations(options,terminal,{"n":"1","d":"4"})[0]
		var half: Dictionary = clinic._reference_consultations(options,terminal,{"n":"1","d":"2"})[0]
		var error: String = clinic._finish_reference_component_batch(batch)
		var ticks: int = ceili(float(_content.balance.clinical.consult_seconds)*10)
		var equal: bool = was_assembled==early and error.is_empty() and prefix.resources["staff:doctor"]==F.make(ticks) and quarter.resources["staff:doctor"]==F.make(ticks,4) and half.resources["staff:doctor"]==F.make(ticks,2)
		equal = equal and quarter.stage_resources.consult["staff:doctor"]==F.make(ticks,4) and half.stage_resources.consult["staff:doctor"]==F.make(ticks,2) and is_same(query.consultations.doctor[0],prefix)
		correct = correct and equal
		observations.append({"early_flush":early,"prefix_previously_assembled":was_assembled,"exact_weighting":equal,"counts":clinic.reference_component_observation()})
	return {"passed":correct,"paths":observations}

func _failure_cleanup() -> Dictionary:
	var clinic: FailureProbe = FailureProbe.new(_content,HospitalSpace.new(_content))
	var query: Dictionary = {}
	var failed: Dictionary = clinic._reference_model({"query":query},"",false,0)
	var prior: Dictionary = clinic.first_target
	var snapshot: Dictionary = prior.duplicate(true)
	var atomic: bool = not failed.ok and failed.has("error") and failed.bundles.is_empty() and not failed.has("model") and prior.has("resources") and not query.has("component_batch")
	atomic = atomic and clinic.reference_component_observation().failed_batches==1
	clinic.fail_on_flush = 0
	clinic.flushes = 0
	var resumed: Dictionary = clinic._reference_model({"query":query},"",false,0)
	var cold: FailureProbe = FailureProbe.new(_content,HospitalSpace.new(_content))
	cold.fail_on_flush = 0
	var independent: Dictionary = cold._reference_model({"query":{}},"",false,0)
	var recovered: bool = resumed.ok and resumed==independent and prior==snapshot and not query.has("component_batch")
	var early: FailureProbe = FailureProbe.new(_content,HospitalSpace.new(_content))
	early.early_failure = true
	var early_query: Dictionary = {}
	var rejected: Dictionary = early._reference_model({"query":early_query},"",false,0)
	var early_clean: bool = not rejected.ok and not rejected.has("model") and not early_query.has("component_batch") and early.reference_component_observation().native_calls==0
	var empty: FailureProbe = FailureProbe.new(_content,HospitalSpace.new(_content))
	empty.fail_on_flush = 0
	empty.empty_model = true
	var empty_query: Dictionary = {}
	var no_root: Dictionary = empty._reference_model({"query":empty_query},"",false,0)
	var empty_complete: bool = not no_root.ok and no_root.has("model") and no_root.model.bundles.is_empty() and no_root.model.choice_groups.diagnostic[-1].resources["staff:doctor"]=={"n":str(HospitalClinic.REFERENCE_COMPONENT_REQUEST_LIMIT+1),"d":"1"} and not empty_query.has("component_batch")
	var bounded_failure: FailureProbe = FailureProbe.new(_content,HospitalSpace.new(_content))
	bounded_failure.amount_count = HospitalClinic.REFERENCE_COMPONENT_MEMO_LIMIT+HospitalClinic.REFERENCE_COMPONENT_REQUEST_LIMIT+1
	bounded_failure.fail_on_flush = HospitalClinic.REFERENCE_COMPONENT_MEMO_LIMIT/HospitalClinic.REFERENCE_COMPONENT_REQUEST_LIMIT+1
	var bounded_query: Dictionary = {}
	var rejected_after_eviction: Dictionary = bounded_failure._reference_model({"query":bounded_query},"",false,0)
	var eviction_atomic: bool = not rejected_after_eviction.ok and not rejected_after_eviction.has("model") and not bounded_query.has("component_batch") and bounded_failure.first_target.resources["staff:doctor"]==F.make(1) and bounded_failure.reference_component_observation().memo_evictions>0
	return {"passed":atomic and recovered and early_clean and empty_complete and eviction_atomic,"later_batch_atomic":atomic,"retry_matches_cold":recovered,"early_return_cleanup":early_clean,"empty_model_fully_assembled":empty_complete,"failure_after_eviction_atomic":eviction_atomic}

func _configure(service: HospitalArrivalService) -> void:
	service.clinic.scheduler = HospitalShiftScheduler.new(_content,service.space)
	service.clinic.recruitment = RecruitmentService.new(_content,service.space)
	service.clinic.departments = HospitalDepartments.new(_content,service.space)
	service.departments = service.clinic.departments

func _capacity_failure() -> Dictionary:
	var ctx: Dictionary = _context()
	_single_case(ctx)
	var worker: HospitalArrivalService = HospitalArrivalService.new(_content,HospitalSpace.new(_content))
	var failing: FailedReference = FailedReference.new(_content,worker.space)
	worker.clinic = failing
	_configure(worker)
	var frozen: Dictionary = ctx.world.freeze()
	var failed: Dictionary = worker.capacity(ctx.world,false)
	var not_cached: bool = worker._reference_cache.get(0,{}).get("cases",{}).is_empty() and not worker._reference_cache.get(0,{}).has("outputs")
	failing.fail = false
	var resumed: Dictionary = worker.capacity(ctx.world,false)
	var cold: HospitalArrivalService = HospitalArrivalService.new(_content,HospitalSpace.new(_content))
	_configure(cold)
	var independent: Dictionary = cold.capacity(ctx.world,false)
	var new_atomic: bool = not failed.get("complete",true) and failed.has("error") and not failed.has("capacity") and not failed.has("shift_capacities") and not_cached and resumed.get("complete",false) and resumed==independent and ctx.world.freeze()==frozen
	var patient: Dictionary = _patient(ctx,[45,76],"B_S13_D09_M09")
	_single_case(ctx,"D37")
	frozen = ctx.world.freeze()
	failing.failed_binding = str(patient.get("binding_id",""))
	failing.failures = 0
	failing.fail = true
	var failed_old: Dictionary = worker.capacity(ctx.world,true)
	var old_error: bool = not patient.is_empty() and not failed_old.get("complete",true) and failed_old.has("error") and not failed_old.has("capacity") and not failed_old.has("shift_capacities") and failing.failures==1
	failing.fail = false
	var resumed_old: Dictionary = worker.capacity(ctx.world,true)
	var independent_old: Dictionary = cold.capacity(ctx.world,true)
	var old_atomic: bool = old_error and resumed_old.get("complete",false) and resumed_old==independent_old and ctx.world.freeze()==frozen
	worker.dispose()
	cold.dispose()
	return {"passed":new_atomic and old_atomic,"new_case_failure_not_cached":new_atomic,"old_queue_failure_discards_workload":old_atomic,"new_failure":failed,"old_failure":failed_old}

func _complete_models() -> Dictionary:
	var ctx: Dictionary = _context()
	_add_room(ctx.world,"component_terminal","T01",[42,70],[6,6])
	_add_facility(ctx.world,"component_treatment","M09","component_terminal",[44,71])
	var scalar: ScalarComponents = ScalarComponents.new(_content,ctx.space)
	for property: Dictionary in ctx.clinic.get_property_list():
		if (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)!=0 and str(property.name)!="reference_component_counts": scalar.set(property.name,ctx.clinic.get(property.name))
	var before: Dictionary = ctx.world.freeze()
	var nominal: WorldState = ctx.arrivals._capacity_reference_world(ctx.world)
	var nominal_before: Dictionary = nominal.freeze()
	var query: Dictionary = {}
	var retained: Array = []
	var snapshots: Array = []
	var observations: Array = []
	var correct: bool = true
	for input: Array in [["B_S13_D09_M09",false],["B_S49_D37_M37",true],["B_S13_D09_M09",false]]:
		var batch: Dictionary = ctx.clinic.reference_demand(nominal,input[0],input[1],0,query)
		var single: Dictionary = scalar.reference_demand(nominal,input[0],input[1],0)
		var equal: bool = batch.ok and batch==single and not query.has("component_batch") and ctx.space._route_queries.is_empty()
		for index: int in retained.size(): equal = equal and retained[index]==snapshots[index]
		retained.append(batch)
		snapshots.append(batch.duplicate(true))
		correct = correct and equal
		observations.append({"binding":input[0],"complex":input[1],"complete_scalar_equal":equal})
	var readonly: bool = ctx.world.freeze()==before and nominal.freeze()==nominal_before
	return {"passed":correct and readonly,"cases":observations,"readonly":readonly,"counts":ctx.clinic.reference_component_observation()}
