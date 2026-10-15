extends SceneTree

const F = preload("res://game/arrivals/exact_fraction.gd")
const Arrivals = preload("res://game/arrivals/arrival_service.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = FeasibilityHospitals.create("stage24-reference-retry",false,content)
	for staff: Dictionary in world.facts.staff.values():
		if staff.role=="doctor":
			staff.abilities.treatment = 1
			staff.personality_id = "DP01"
	var clinic: HospitalClinic = HospitalClinic.new(content,HospitalSpace.new(content))
	var original: String = JSON.stringify(world.freeze())
	var projection: Dictionary = clinic.reference_demand(world,"B_S49_D37_M37")
	var found: bool = false
	var switched_bundle: Dictionary = {}
	for bundle: Dictionary in projection.get("bundles",[]):
		if bundle.plan_id!="P_D37_GENTLE" or bundle.get("retry_plan_id","")!="P_D37_COMMON" or bundle.staff_ids!=["treat_doctor"]:
			continue
		found = true
		switched_bundle = bundle
		# The cautious doctor chooses 54-second gentle work at 97% first;
		# the retry bonus makes the 30-second common plan equally effective.
		var terminal: String = "facility:"+str(bundle.terminal_id)
		var first: Dictionary = F.from_value(bundle.first_stage_resources.outpatient[terminal])
		var retry: Dictionary = F.from_value(bundle.retry_stage_resources.outpatient[terminal])
		var expected: Dictionary = F.add(first,F.mul(F.make(3,100),retry))
		_check("auto_retry_can_change_plan_and_weights_its_own_work",F.compare(first,F.make(540))==0 and F.compare(retry,F.make(300))==0 and F.compare(F.from_value(bundle.resources[terminal]),expected)==0 and F.compare(expected,F.make(549))==0)
		_check("diagnostics_count_once",bundle.stage_resources.gp==bundle.first_stage_resources.gp and not bundle.retry_stage_resources.has("gp") and not bundle.retry_stage_resources.has("reception"))
		var consult_resource: String = "facility:"+str(bundle.gp_id)
		_check("auto_failure_reconsult_is_real_weighted_work",bundle.retry_stage_resources.has("consult") and F.compare(F.from_value(bundle.stage_resources.consult[consult_resource]),F.make(412,5))==0)
		break
	_check("original_auto_score_has_retry_switch_case",found)
	_check("projection_does_not_draw_or_change_world",original==JSON.stringify(world.freeze()))
	if found:
		var remaining_world: WorldState = WorldState.new(world.freeze())
		var remaining_visit: Dictionary = remaining_world.facts.visits.values()[0]
		remaining_visit.attempt_ids = ["original_failed_attempt"]
		remaining_visit.ticket_id = "retry_ticket"
		remaining_visit.plan_decision = {"plan_id":switched_bundle.retry_plan_id}
		remaining_world.facts.tickets.retry_ticket = {"id":"retry_ticket","visit_id":remaining_visit.id,"kind":"outpatient","enqueued_tick":0}
		var arrivals: RefCounted = Arrivals.new(content,HospitalSpace.new(content))
		var normalized: Dictionary = arrivals._normalize_bundle(remaining_world,switched_bundle)
		var remaining: Dictionary = arrivals._remaining_bundle(remaining_world,remaining_visit,switched_bundle)
		var terminal: String = "facility:"+str(switched_bundle.terminal_id)
		_check("arrival_solver_preserves_authoritative_merged_work",F.compare(normalized.resources[terminal],F.make(549))==0)
		_check("existing_retry_uses_conditional_new_plan_work_once",remaining.plan_id==switched_bundle.retry_plan_id and F.compare(remaining.resources[terminal],F.make(300))==0)
		var reception_resource: String = "facility:"+str(switched_bundle.reception_id)
		var consult_resource: String = "facility:"+str(switched_bundle.gp_id)
		_check("completed_reconsult_is_not_counted_again",not remaining.resources.has(reception_resource) and not remaining.resources.has(consult_resource))
		remaining_visit.phase = "wait_consult"
		remaining_world.facts.tickets.retry_ticket.kind = "consult"
		var before_consult: Dictionary = arrivals._remaining_bundle(remaining_world,remaining_visit,switched_bundle)
		_check("pending_reconsult_counts_only_its_remaining_work",not before_consult.resources.has(reception_resource) and F.compare(F.from_value(before_consult.resources.get(consult_resource,F.make())),F.make(80))==0 and F.compare(F.from_value(before_consult.resources.get(terminal,F.make())),F.make(300))==0)
	print(JSON.stringify({"stage":24,"suite":"clinical_reference_retry","failures":failures,"performance":"skipped"}))
	quit(0 if failures.is_empty() else 1)

func _check(id: String, passed: bool) -> void:
	print(id+": "+("pass" if passed else "FAIL"))
	if not passed: failures.append(id)
