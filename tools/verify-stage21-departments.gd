extends SceneTree

const Departments = preload("res://game/operations/department_service.gd")
var failures: Array[String] = []
var checks: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = FeasibilityHospitals.create("department-rules",false,content)
	var space: HospitalSpace = HospitalSpace.new(content)
	var departments: RefCounted = Departments.new(content,space)
	var visit: Dictionary = world.facts.visits.values()[0]
	var ticket_id: String = world.new_id("ticket")
	visit.phase = "wait_gp"
	visit.ticket_id = ticket_id
	world.facts.tickets[ticket_id] = {"id":ticket_id,"visit_id":visit.id,"kind":"gp","enqueued_tick":0,"waited_ticks":123,"pause_reasons":{}}
	world.facts.rooms.annex = {"id":"annex","kind":"treatment","floor_id":1,"origin":[52,84],"size":[10,8]}
	world.facts.facilities.annex_machine = {"id":"annex_machine","definition_id":"M09","room_id":"annex","floor_id":1,"cell":[53,85],"footprint":[2,2],"patient_cell":[53,87],"operator_cells":[[52,85]],"repair_cell":[55,85],"grade":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{}}
	departments.ensure(world)
	var opening: int = HospitalLedger.balance(world)
	var created: CommandResult = departments.execute(world,"department_create",{"department_id":"annex_department","name":"体态门诊","room_ids":["annex"],"shared_room_ids":[],"entry":{"floor_id":1,"cell":[57,91]},"intake_disease_ids":["D01"],"focus_id":"T01"})
	_check("physical_department_creation_and_first_focus_free",created.accepted and HospitalLedger.balance(world)==opening)
	_check("rooms_have_one_owner",not "annex" in world.facts.departments.units.general.room_ids and "annex" in world.facts.departments.units.annex_department.room_ids)
	var good: Dictionary = departments.readiness(world,"general",visit.id)
	var bad: Dictionary = departments.readiness(world,"annex_department",visit.id)
	_check("wrong_candidate_is_actual_scope_mismatch",good.structurally_compatible and bad.reason_id=="intake_scope_excludes_case" and bad.reachable)
	_choose_error_seed(world)
	var evidence: Dictionary = visit.evidence_by_source.duplicate(true)
	var ledger: Dictionary = world.facts.ledger.duplicate(true)
	var corrected: bool = false
	for index: int in range(700):
		corrected = departments.route_patient(world,visit.id)
		if corrected: break
		departments.dispatch(world)
		space.advance(world)
		departments.advance(world)
		world.facts.sim_tick += 1
		world.touch()
		space.finish_boundary(world)
	var route: Dictionary = world.facts.departments.routes.get(visit.id,{})
	_check("real_wrong_entry_safely_self_corrects",corrected and route.get("error_rolled",false) and route.get("corrected",false) and not route.get("actual_mismatched_entry_arrival",{}).is_empty())
	_check("guidance_preserves_ticket_evidence_and_charges",visit.ticket_id==ticket_id and world.facts.tickets[ticket_id].waited_ticks==123 and visit.evidence_by_source==evidence and world.facts.ledger==ledger)
	_check("wrong_entry_once_has_traceable_penalty",departments.patient_rating(world,visit.id).parts.flow==92.0 and is_equal_approx(float(visit.anger),17.0))
	var restored: WorldState = WorldState.new(world.freeze())
	var recovered: RefCounted = Departments.new(content,HospitalSpace.new(content))
	for index: int in range(5): recovered.route_patient(restored,visit.id)
	_check("restoration_does_not_repeat_wrong_entry",is_equal_approx(float(restored.facts.visits[visit.id].anger),17.0) and restored.facts.departments.experience[visit.id].wrong_entries.size()==1)
	var changed: CommandResult = departments.execute(world,"department_set_focus",{"department_id":"annex_department","focus_id":"T02"})
	_check("focus_change_paid_and_delayed",changed.accepted and HospitalLedger.balance(world)==opening-200 and int(world.facts.departments.units.annex_department.focus_ready_tick)==world.sim_tick+6000)
	var frozen: Dictionary = world.freeze()
	var early_change: CommandResult = departments.execute(world,"department_set_focus",{"department_id":"annex_department","focus_id":"T03"})
	_check("reconfiguration_does_not_reset_room_cooldown",not early_change.accepted and frozen==world.freeze())
	departments.summary(world)
	departments.patient_summary(world,visit.id)
	departments.receipt(world,visit.id)
	_check("all_panels_are_read_only",frozen==world.freeze())
	var staff_rating: Dictionary = departments.staff_rating(world,"gp_doctor")
	_check("no_sample_is_not_zero_or_five_stars",staff_rating.score==null and staff_rating.stars==null and departments.aggregate_rating(world).score==null)
	departments.retire_ticket(world,visit.id)
	world.facts.tickets.erase(ticket_id)
	visit.ticket_id = ""
	visit.final_result = "referred"
	visit.phase = "departed"
	world.facts.actors[visit.actor_id].location = {"kind":"outside"}
	departments.settle(world)
	departments.settle(world)
	_check("final_case_and_receipt_are_idempotent",world.facts.departments.cases.size()==1 and departments.receipt(world,visit.id).result=="referred")
	world.facts.sim_tick = WorldState.TICKS_PER_DAY
	var hospital_rating: Dictionary = departments.aggregate_rating(world)
	_check("three_settled_day_window_requires_five_for_stars",hospital_rating.samples==1 and hospital_rating.score!=null and hospital_rating.stars==null)
	_check("no_treatment_has_no_final_treatment_department",world.facts.departments.cases[0].department_id.is_empty())
	var snapshot_error: String = departments.validate(world)
	if not snapshot_error.is_empty():
		print("department_snapshot_invariants error: "+snapshot_error)
		print(JSON.stringify({"departments":world.facts.departments,"staff_ids":world.facts.staff.keys(),"room_ids":world.facts.rooms.keys(),"visit_ids":world.facts.visits.keys(),"floor_ids":world.facts.floors.overrides.keys()}))
	_check("department_snapshot_invariants",snapshot_error.is_empty())
	print(JSON.stringify({"stage":21,"checks":checks,"failures":failures,"performance":"skipped"}))
	quit(0 if failures.is_empty() else 1)

func _choose_error_seed(world: WorldState) -> void:
	for seed_value: int in range(100):
		var generator: RandomNumberGenerator = RandomNumberGenerator.new()
		generator.seed = seed_value
		var state: String = str(generator.state)
		if generator.randi_range(0,9999)<1800:
			world.facts.rng.registration.seed_decimal = str(seed_value)
			world.facts.rng.registration.state_decimal = state
			return

func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	if not passed: failures.append(label)
