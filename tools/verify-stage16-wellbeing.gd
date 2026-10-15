extends SceneTree

const Wellbeing = preload("res://game/staff/staff_wellbeing.gd")
const Scheduler = preload("res://game/staff/shift_scheduler.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = FeasibilityHospitals.create("wellbeing-rules",false,content)
	var space: HospitalSpace = HospitalSpace.new(content)
	var wellbeing: RefCounted = Wellbeing.new(content,space)
	Scheduler.new(content,space).ensure(world)
	wellbeing.ensure(world)
	var staff: Dictionary = world.facts.staff.reception
	staff.energy = 50.0
	staff.stress_milli = 10000
	var before: Dictionary = {"reception":world.facts.actors.reception.location.duplicate(true)}
	for tick: int in 10:
		wellbeing.advance(world,{"reception":true},before)
	_check("actual_work_uses_original_rate",is_equal_approx(float(staff.energy),50.0-float(content.balance.wellbeing.energy_work_per_second)) and staff.stress_milli==10010)
	var original_awake: int = staff.awake_ticks
	staff.life_task = {"phase":"rest","kind":"rest","facility_id":"","floor_id":1,"cell":world.facts.actors.reception.location.cell,"return_location":world.facts.actors.reception.location.duplicate(true)}
	staff.rest_obligation = true
	for tick: int in 10:
		wellbeing.advance(world,{},before)
	_check("short_rest_never_counts_as_sleep",staff.awake_ticks==original_awake+10 and staff.sleep_remaining_ticks==0)
	_check("fractional_stress_integral_has_no_tick_rounding_gain",staff.stress_milli==9995)
	staff.life_task = {"phase":"idle"}
	staff.rest_obligation = false
	staff.stress_milli = 10000
	var event: Dictionary = {"staff_id":"reception","event_id":"actual-frozen-event","source":"frozen"}
	wellbeing.execute(world,"staff_pressure_event",event)
	wellbeing.execute(world,"staff_pressure_event",event)
	_check("one_event_one_pressure_effect",staff.stress_milli==25000)
	world.facts.rooms.staff_rest = {"id":"staff_rest","kind":"rest","floor_id":1,"origin":[34,64],"size":[8,8]}
	world.facts.facilities.staff_bed = {"id":"staff_bed","definition_id":"SE04","room_id":"staff_rest","floor_id":1,"cell":[35,65],"footprint":[1,2],"patient_cell":[35,67],
		"operator_cells":[],"repair_cell":[34,65],"grade":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{}}
	world.facts.actors.reception.location = {"kind":"floor","floor_id":1,"cell":[35,67],"height_m":0.0}
	space.sync_actor(world,"reception")
	# The shared feasibility scene places a sample body on this bed's footprint.
	# Keep the obstruction check, then clear the real body for the sleep case.
	_check("occupied_staff_bed_rejected",not space.facility_quote(world,"staff_bed","reception").ok)
	world.facts.actors.sample_S21.location = {"kind":"floor","floor_id":1,"cell":[35,73],"height_m":0.0}
	space.sync_actor(world,"sample_S21")
	_check("sleep_fixture_has_compatible_clear_bed",space.facility_quote(world,"staff_bed","reception").ok)
	staff.awake_ticks = ceili(float(content.balance.staff_sleep.awake_limit_seconds)/WorldState.TICK_SECONDS)
	wellbeing.boundaries(world)
	_check("sleep_deadline_blocks_new_work",staff.block_new_work)
	wellbeing.dispatch(world)
	wellbeing.dispatch(world)
	_check("sleep_requires_actual_reserved_bed",staff.life_task.phase=="sleep" and world.facts.staff_life.reservations.has("staff_bed") and world.facts.actors.reception.posture=="lying")
	staff.sleep_remaining_ticks = 2
	wellbeing.advance(world)
	var clone: WorldState = WorldState.new(world.freeze())
	_check("save_preserves_sleep_remainder",clone.facts.staff.reception.sleep_remaining_ticks==1 and clone.facts.staff.reception.life_task.phase=="sleep")
	wellbeing.advance(world)
	_check("complete_sleep_resets_awake_once",staff.sleep_remaining_ticks==0 and staff.awake_ticks==0 and staff.life_task.phase=="returning")
	_check("ordinary_click_cannot_wake_sleep",not wellbeing.execute(world,"interrupt_staff_rest",{"staff_id":"gp_doctor","reason":"click"}).accepted)
	_check("all_seven_roles_share_sleep_defaults",_all_roles(content))
	_check("new_life_facts_validate",wellbeing.validate(world).is_empty())
	print(JSON.stringify({"stage":16,"failures":failures,"performance":"skipped"}))
	quit(0 if failures.is_empty() else 1)

func _all_roles(content: HospitalContent) -> bool:
	var world: WorldState = FeasibilityHospitals.create("seven-roles",false,content)
	var basis_staff: Dictionary = world.facts.staff.reception.duplicate(true)
	var basis_actor: Dictionary = world.facts.actors.reception.duplicate(true)
	for row: Dictionary in content.balance.staff:
		var id: String = "role_"+str(row.role)
		var staff: Dictionary = basis_staff.duplicate(true)
		staff.id = id
		staff.role = row.role
		var actor: Dictionary = basis_actor.duplicate(true)
		actor.id = id
		world.facts.staff[id] = staff
		world.facts.actors[id] = actor
	Wellbeing.new(content,HospitalSpace.new(content)).ensure(world)
	for staff: Dictionary in world.facts.staff.values():
		if staff.get("awake_ticks",-1)!=0 or staff.get("sleep_remaining_ticks",-1)!=0 or staff.get("life_task",{}).get("phase","")!="idle":
			return false
	return true

func _check(name: String, ok: bool) -> void:
	if not ok:
		failures.append(name)
