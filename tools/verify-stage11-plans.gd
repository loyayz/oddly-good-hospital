extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = FeasibilityHospitals.create("stage11-plans",false,content)
	world.facts.gameplay_version = 1
	var clinic: HospitalClinic = HospitalClinic.new(content,HospitalSpace.new(content))
	var visit: Dictionary = world.facts.visits.values()[0]
	var before: String = JSON.stringify(world.freeze())
	var common: Dictionary = clinic.plan_quote(world,visit.id,"P_D37_COMMON")
	var gentle: Dictionary = clinic.plan_quote(world,visit.id,"P_D37_GENTLE")
	_check("shared_read_only_quotes",JSON.stringify(world.freeze())==before)
	_check("common_available",common.ok)
	_check("gentle_available",gentle.ok)
	if common.ok and gentle.ok:
		print("PLAN_MULTIPLIER_QUOTES="+JSON.stringify({"common":_quote_terms(common),"gentle":_quote_terms(gentle)}))
		_check("gentle_uses_original_multipliers",int(gentle.work_ticks)>int(common.work_ticks) and int(gentle.supply_units)==2 and int(gentle.cure_fee)==220 and int(gentle.probability_bp)>=int(common.probability_bp))
	var receipt: CommandResult = clinic.execute(world,"clinical_select_plan",{"visit_id":visit.id,"plan_id":"P_D37_GENTLE"})
	_check("selection_requires_waiting_phase",not receipt.accepted)
	visit.phase = "wait_outpatient"
	visit.plan_decision = {"plan_id":"P_D37_COMMON","source":"doctor","probability_bp":int(common.get("probability_bp",0)),"revision":1}
	var ticket_id: String = world.new_id("ticket")
	visit.ticket_id = ticket_id
	world.facts.tickets[ticket_id] = {"id":ticket_id,"visit_id":visit.id,"kind":"outpatient","enqueued_tick":0,"waited_ticks":83}
	receipt = clinic.execute(world,"clinical_select_plan",{"visit_id":visit.id,"plan_id":"P_D37_GENTLE"})
	_check("manual_choice_preserves_ticket",receipt.accepted and visit.ticket_id==ticket_id and int(world.facts.tickets[ticket_id].waited_ticks)==83)
	_check("choice_does_not_reserve_or_issue",world.facts.preparations.is_empty() and world.facts.inventory.issues.is_empty() and world.facts.attempts.is_empty())
	world.facts.inventory.units = 0
	var unavailable: Dictionary = clinic.plan_quote(world,visit.id,"P_D37_GENTLE")
	_check("temporary_shortage_is_not_lost_qualification",not unavailable.ok and unavailable.structural_ok)
	_check("shortage_targets_same_original_ticket",not clinic.shortage_requests(world).is_empty() and clinic.shortage_requests(world)[0].ticket_id==ticket_id)
	world.facts.inventory.units = 60
	_check("original_quote_wakes_after_restock",clinic.plan_quote(world,visit.id,"P_D37_GENTLE").ok)
	var restores: WorldState = WorldState.new(world.freeze())
	_check("manual_decision_saved",restores.facts.visits[visit.id].plan_decision==visit.plan_decision)
	_retry_completion_rule(content,"doctor","wait_consult")
	_retry_completion_rule(content,"director","wait_outpatient")
	print(JSON.stringify({"stage":11,"failures":failures,"performance":"skipped"}))
	quit(0 if failures.is_empty() else 1)

func _retry_completion_rule(content: HospitalContent, source: String, expected_phase: String) -> void:
	var world: WorldState = FeasibilityHospitals.create("stage11-retry-"+source,false,content)
	world.facts.gameplay_version = 1
	var clinic: HospitalClinic = HospitalClinic.new(content,HospitalSpace.new(content))
	var visit: Dictionary = world.facts.visits.values()[0]
	var quote: Dictionary = clinic.plan_quote(world,visit.id,visit.requested_plan_id,{"doctor_id":"treat_doctor"})
	if not quote.ok:
		_check(source+"_retry_fixture_ready",false)
		return
	var attempt_id: String = world.new_id("attempt")
	var attempt: Dictionary = quote.duplicate(true)
	attempt.id = attempt_id
	attempt.visit_id = visit.id
	attempt.result = false
	attempt.start_tick = 0
	world.facts.attempts[attempt_id] = attempt
	world.facts.inventory.units -= int(attempt.supply_units)
	world.facts.inventory.issues[attempt_id] = {"attempt_id":attempt_id,"units":attempt.supply_units,"tick":0}
	visit.attempt_ids = [attempt_id]
	visit.plan_decision = {"plan_id":attempt.plan_id,"source":source,"probability_bp":attempt.probability_bp}
	visit.phase = "outpatient"
	var service_id: String = world.new_id("service")
	world.facts.sessions[service_id] = {"id":service_id,"visit_id":visit.id,"kind":"outpatient","facility_id":quote.facility_id,"staff_ids":quote.staff_ids.duplicate(),
		"resources":[visit.actor_id,quote.facility_id]+quote.staff_ids,"total_ticks":attempt.work_ticks,"remaining_ticks":1,"start_tick":0,"attempt_id":attempt_id}
	clinic.advance(world)
	_check(source+"_first_failure_keeps_real_attempt_and_correct_continuation",visit.phase==expected_phase and visit.attempt_ids==[attempt_id] and world.facts.inventory.issues.size()==1 and world.facts.tickets[visit.ticket_id].kind==expected_phase.trim_prefix("wait_"))

func _quote_terms(quote: Dictionary) -> Dictionary:
	return {"work_ticks":quote.work_ticks,"supply_units":quote.supply_units,"cure_fee":quote.cure_fee,"probability_bp":quote.probability_bp,"staff_ids":quote.staff_ids}

func _check(id: String, passed: bool) -> void:
	print(id+": "+("pass" if passed else "FAIL"))
	if not passed:
		failures.append(id)
