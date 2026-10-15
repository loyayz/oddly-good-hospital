extends SceneTree

const F = preload("res://game/arrivals/exact_fraction.gd")
const Scheduler = preload("res://game/staff/shift_scheduler.gd")
const Recruitment = preload("res://game/staff/recruitment_service.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = FeasibilityHospitals.create("reference-shift-rules",false,content)
	var scheduler: RefCounted = Scheduler.new(content,HospitalSpace.new(content))
	scheduler.ensure(world)
	var specialty: String = content.definition("treatment_routines",content.definition("treatment_bindings","B_S49_D37_M37").routine_id).specialty_id
	for staff: Dictionary in world.facts.staff.values():
		var duty: String = "outpatient" if staff.role=="doctor" else "work"
		var pools: Array = ["diagnosis"] if staff.id=="gp_doctor" else [specialty] if staff.role=="doctor" else []
		staff.schedule = [{"kind":duty,"pools":pools,"locked":false},{"kind":"rest","pools":[],"locked":false},{"kind":duty,"pools":pools.duplicate(),"locked":false}]
	world.facts.actors.gp_doctor.species_id = "S09"
	world.facts.sim_tick = 9000
	var clinic: HospitalClinic = HospitalClinic.new(content,HospitalSpace.new(content))
	clinic.scheduler = scheduler
	clinic.recruitment = Recruitment.new(content,HospitalSpace.new(content))
	var original: Dictionary = world.freeze()
	var early: Dictionary = clinic.reference_demand(world,"B_S49_D37_M37",false,0)
	var rest: Dictionary = clinic.reference_demand(world,"B_S49_D37_M37",false,1)
	var late: Dictionary = clinic.reference_demand(world,"B_S49_D37_M37",false,2)
	_check("reference_uses_target_shift_assignments",early.ok and late.ok and not rest.ok)
	if early.ok and late.ok:
		var first: Dictionary = early.bundles[0]
		var last: Dictionary = late.bundles[0]
		var early_gp: int = int(F.from_value(first.stage_resources.gp["staff:gp_doctor"]).n)
		var late_gp: int = int(F.from_value(last.stage_resources.gp["staff:gp_doctor"]).n)
		_check("late_shift_talent_uses_reference_clock",late_gp==ceili(float(early_gp)/1.1) and late_gp<early_gp)
		_check("reference_plan_is_filtered_by_actual_duty_and_pool",first.staff_ids==["treat_doctor"] and last.staff_ids==["treat_doctor"] and first.stage_resources.gp.has("staff:gp_doctor") and not first.stage_resources.gp.has("staff:treat_doctor"))
	_check("reference_shift_queries_do_not_change_world",original==world.freeze())
	var surgical: WorldState = FeasibilityHospitals.create("reference-route-clock",true,content)
	var visit: Dictionary = surgical.facts.visits.values()[0]
	var surgery_clinic: HospitalClinic = HospitalClinic.new(content,HospitalSpace.new(content))
	var first_quote: Dictionary = surgery_clinic.plan_quote(surgical,visit.id,"P_D23_SURGERY",{"structural_only":true,"ignore_supplies":true})
	surgical.facts.sim_tick = 6000
	var next_quote: Dictionary = surgery_clinic.plan_quote(surgical,visit.id,"P_D23_SURGERY",{"structural_only":true,"ignore_supplies":true})
	_check("surgery_route_duration_is_relative_to_clock",first_quote.ok and next_quote.ok and int(first_quote.gathering_ticks)==int(next_quote.gathering_ticks) and int(first_quote.estimated_total_ticks)==int(next_quote.estimated_total_ticks))
	print(JSON.stringify({"stage":24,"suite":"clinical_reference_shifts","failures":failures,"performance":"skipped"}))
	quit(0 if failures.is_empty() else 1)

func _check(id: String, passed: bool) -> void:
	print(id+": "+("pass" if passed else "FAIL"))
	if not passed: failures.append(id)
