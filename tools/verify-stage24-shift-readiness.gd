extends SceneTree

const Arrivals = preload("res://game/arrivals/arrival_service.gd")
const Scheduler = preload("res://game/staff/shift_scheduler.gd")
const F = preload("res://game/arrivals/exact_fraction.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = FeasibilityHospitals.create("stage24-shift-readiness",false,content)
	var space: HospitalSpace = HospitalSpace.new(content)
	var arrivals: RefCounted = Arrivals.new(content,space)
	var scheduler: RefCounted = Scheduler.new(content,space)
	scheduler.ensure(world)
	arrivals.clinic.scheduler = scheduler
	var doctor: Dictionary = world.facts.staff.treat_doctor
	doctor.schedule = [{"kind":"surgery","pools":[],"locked":false},{"kind":"outpatient","pools":["T10"],"locked":false},{"kind":"outpatient","pools":["T01"],"locked":false}]
	var resources: Dictionary = {"staff:treat_doctor":F.make(300),"facility:treatment":F.make(300)}
	var bundle: Dictionary = {"binding_id":"B_S49_D37_M37","resources":resources,"stage_resources":{"outpatient":resources}}
	var before: String = JSON.stringify(world.freeze())
	_check("surgery_shift_cannot_supply_outpatient_clock",not arrivals._bundle_available(world,bundle,0))
	_check("future_outpatient_shift_is_independent_of_current_surgery_duty",arrivals._bundle_available(world,bundle,1))
	_check("future_wrong_specialty_pool_is_rejected",not arrivals._bundle_available(world,bundle,2))
	world.facts.sim_tick = 6000
	_check("changing_current_shift_does_not_rewrite_target_pool",not arrivals._bundle_available(world,bundle,2))
	world.facts.sim_tick = 0
	_check("future_roster_query_never_mutates_original_world",before==JSON.stringify(world.freeze()))
	print(JSON.stringify({"stage":24,"suite":"shift_readiness","failures":failures,"performance":"skipped"}))
	quit(0 if failures.is_empty() else 1)

func _check(label: String, passed: bool) -> void:
	if not passed:
		failures.append(label)
