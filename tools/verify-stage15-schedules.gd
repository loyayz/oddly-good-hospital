extends SceneTree

const Scheduler = preload("res://game/staff/shift_scheduler.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = FeasibilityHospitals.create("schedule-rules",false,content)
	var scheduler: RefCounted = Scheduler.new(content,HospitalSpace.new(content))
	scheduler.ensure(world)
	var doctor: Dictionary = world.facts.staff.gp_doctor
	var invalid: Array = []
	for index: int in int(content.balance.schedule.shifts_per_day):
		invalid.append({"kind":"outpatient","pools":[],"locked":false})
	var before: Dictionary = world.freeze()
	_check("all_work_template_rejected_atomically",not scheduler.execute(world,"apply_schedule",{"changes":[{"staff_id":"gp_doctor","schedule":invalid}]}).accepted and before==world.freeze())
	var suggestion: Dictionary = scheduler.suggestion(world)
	world.touch()
	_check("unrelated_revision_preserves_suggestion",scheduler.execute(world,"apply_schedule",suggestion).accepted)
	scheduler.execute(world,"set_schedule_lock",{"staff_id":"gp_doctor","shift":0,"locked":true})
	var changed: Array = doctor.schedule.duplicate(true)
	changed[0].kind = "rest" if changed[0].kind!="rest" else "outpatient"
	_check("locked_slot_is_not_overwritten",not scheduler.execute(world,"apply_schedule",{"changes":[{"staff_id":"gp_doctor","schedule":changed}]}).accepted)
	var stale: Dictionary = scheduler.suggestion(world)
	doctor.abilities.diagnosis += 1
	_check("qualification_change_refreshes_suggestion",scheduler.execute(world,"apply_schedule",stale).code=="material_change")
	doctor.schedule = [{"kind":"outpatient","pools":[],"locked":false},{"kind":"outpatient","pools":[],"locked":false},{"kind":"rest","pools":[],"locked":false}]
	world.facts.sim_tick = 12000
	doctor.on_shift = true
	world.facts.sessions.safety = {"staff_ids":["gp_doctor"]}
	scheduler.boundaries(world)
	_check("safe_task_keeps_current_staff_and_records_debt",doctor.on_shift and doctor.block_new_work and doctor.rest_debt_ticks==1)
	world.facts.sessions.clear()
	scheduler.boundaries(world)
	_check("safe_completion_allows_rest_without_erasing_debt",not doctor.on_shift and doctor.rest_debt_ticks==1)
	_check("leave_does_not_start_before_exit",scheduler.execute(world,"plan_leave",{"staff_id":"gp_doctor","days":2,"start":"now"}).accepted and doctor.leave_plan.actual_start_tick==-1 and doctor.leave_plan.end_tick==-1)
	var clone: WorldState = WorldState.new(world.freeze())
	_check("save_restores_original_leave_and_debt",clone.facts.staff.gp_doctor.leave_plan==doctor.leave_plan and clone.facts.staff.gp_doctor.rest_debt_ticks==1)
	_check("rest_shift_has_zero_capacity",scheduler.available_ticks(world,"gp_doctor",2)==0)
	_check("new_schedule_facts_validate",scheduler.validate(world).is_empty())
	_clinical_pool_rules(content)
	print(JSON.stringify({"stage":15,"failures":failures,"performance":"skipped"}))
	quit(0 if failures.is_empty() else 1)

func _clinical_pool_rules(content: HospitalContent) -> void:
	var world: WorldState = FeasibilityHospitals.create("schedule-clinical-pools",false,content)
	var scheduler: RefCounted = Scheduler.new(content,HospitalSpace.new(content))
	scheduler.ensure(world)
	var clinic: HospitalClinic = HospitalClinic.new(content,HospitalSpace.new(content))
	clinic.scheduler = scheduler
	var visit: Dictionary = world.facts.visits.values()[0]
	var doctor: Dictionary = world.facts.staff.gp_doctor
	doctor.schedule[0] = {"kind":"surgery","pools":[],"locked":false}
	_candidate_rule(clinic,world,visit,"gp","gp_doctor",false,"surgery_shift_cannot_start_diagnosis")
	var before: Dictionary = world.freeze()
	_check("structural_readiness_ignores_temporary_schedule",_has_candidate(clinic.service_candidates(world,visit,"gp",true),"gp_doctor") and before==world.freeze())
	doctor.schedule[0] = {"kind":"outpatient","pools":["diagnosis"],"locked":false}
	_candidate_rule(clinic,world,visit,"gp","gp_doctor",true,"diagnosis_pool_can_start_diagnosis")
	_candidate_rule(clinic,world,visit,"outpatient","gp_doctor",false,"diagnosis_pool_cannot_start_specialty_treatment")
	var routine: Dictionary = content.definition("treatment_routines",content.definition("treatment_bindings",visit.binding_id).routine_id)
	doctor.schedule[0].pools = [routine.specialty_id]
	_candidate_rule(clinic,world,visit,"outpatient","gp_doctor",true,"matching_specialty_pool_can_start_treatment")
	_candidate_rule(clinic,world,visit,"gp","gp_doctor",false,"specialty_pool_cannot_start_diagnosis")
	_candidate_rule(clinic,world,visit,"reception","reception",true,"non_doctor_work_keeps_its_assignment")

func _candidate_rule(clinic: HospitalClinic, world: WorldState, visit: Dictionary, kind: String, staff_id: String, expected: bool, id: String) -> void:
	var before: Dictionary = world.freeze()
	_check(id,_has_candidate(clinic.service_candidates(world,visit,kind),staff_id)==expected and before==world.freeze())

func _has_candidate(candidates: Array, staff_id: String) -> bool:
	for candidate: Dictionary in candidates:
		if candidate.staff_id==staff_id: return true
	return false

func _check(name: String, ok: bool) -> void:
	if not ok:
		failures.append(name)
