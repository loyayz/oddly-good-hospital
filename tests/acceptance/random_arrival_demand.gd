extends SceneTree

const F = preload("res://game/arrivals/exact_fraction.gd")
const Plan = preload("res://game/arrivals/day_plan.gd")
var checks: Dictionary = {}
var content: HospitalContent

func _initialize() -> void:
	call_deferred("_run")

func _check(name: String, passed: bool, details: Variant = null) -> void:
	checks[name] = {"passed":passed,"details":details}
	print("RANDOM_DEMAND "+name+" "+("PASS" if passed else "FAIL")+" "+JSON.stringify(details))

func _context(preset: bool = true) -> HospitalSimulation:
	return HospitalSimulation.new(HospitalFactory.create("random-demand-test","随机需求验收",preset,content),content)

func _run() -> void:
	content = HospitalContent.new()
	if not content.error.is_empty():
		_check("content",false,content.error)
		_finish()
		return
	var empty: HospitalSimulation = _context(false)
	var original_rng: Dictionary = empty.world.facts.rng.duplicate(true)
	empty.services.arrivals.boundaries(empty.world)
	_check("empty_land_no_random_draw",empty.world.facts.arrivals.plan.opportunity_count==0 and empty.world.facts.rng==original_rng,empty.world.facts.arrivals.plan)
	empty.dispose()
	var sim: HospitalSimulation = _context()
	var service: HospitalArrivalService = sim.services.arrivals
	var world: WorldState = sim.world
	var before: Dictionary = world.freeze()
	var projection: Dictionary = service.capacity(world)
	var desks: int = service.demand_desks(world)
	_check("desk_demand_readonly",desks==1 and projection.capacity==F.make(6) and projection.shift_capacities==[F.make(2),F.make(2),F.make(2)] and before==world.freeze(),projection)
	# The same hospital opening with no available clinicians is still interesting
	# to residents. These are lawful starting conditions, not forged work results.
	for staff: Dictionary in world.facts.staff.values(): staff.on_shift = false
	world.facts.facilities[world.facility_ids("FUR02")[0]].failed = true
	world.touch()
	_check("temporary_resources_do_not_change_demand",service.capacity(world).capacity==F.make(6),service.capacity(world))
	world.facts.arrivals.plan.clear()
	service.boundaries(world)
	var day_one: Dictionary = world.facts.arrivals.plan.duplicate(true)
	var rng: Dictionary = world.facts.rng.duplicate(true)
	var data: Dictionary = world.freeze()
	var restored: HospitalSimulation = HospitalSimulation.new(WorldState.new(data),content)
	restored.services.arrivals.boundaries(restored.world)
	var stable: bool = restored.world.facts.arrivals.plan==day_one and restored.world.facts.rng==rng and Plan.validate(day_one).is_empty()
	for i: int in 4: service.capacity(world); service.daystats(world); service.boundaries(world)
	_check("freeze_restore_and_reads",stable and day_one==world.facts.arrivals.plan and rng==world.facts.rng,day_one)
	restored.dispose()
	# An installed second desk is a legitimate day-boundary input. No actor was
	# moved or completed; room/facility construction itself is outside this test.
	HospitalFactory._add_room(world,{"id":"demand_gp2","type":"gp","anchor":[35,69],"size":[6,6],"door":{"offset":1,"definition_id":"DR04"}},content)
	HospitalFactory._add_facility(world,{"id":"demand_desk2","definition_id":"FUR02","room_id":"demand_gp2","anchor":[37,71],"size":[2,1]},content)
	world.touch()
	service.boundaries(world)
	_check("expansion_keeps_current_day",service.capacity(world).capacity==F.make(12) and day_one==world.facts.arrivals.plan and rng==world.facts.rng,{"today":world.facts.arrivals.plan,"tomorrow":service.capacity(world)})
	world.facts.sim_tick = WorldState.TICKS_PER_DAY
	service.boundaries(world)
	_check("expansion_next_day_and_crowd_limit",world.facts.arrivals.plan.scale_numerator==2 and service.outpatient_allowance(world.facts.arrivals.plan)==32 and world.facts.arrivals.plan.shift_capacities==[F.make(4),F.make(4),F.make(4)],world.facts.arrivals.plan)
	var session: GameSession = GameSession.new(sim,"demand-session")
	var held: CommandResult = session.submit(GameCommand.new("hold-demand",world.hospital_id,world.revision,"arrivals_scale",BusinessPayload.new({"mode":"hold_capacity"}),"demand-session"))
	_check("paused_hold_is_immediate",held.accepted and held.code=="applied" and world.sim_tick==WorldState.TICKS_PER_DAY and not sim.pending(),held.to_record())
	world.facts.facilities.demand_desk2.open = false
	world.touch()
	world.facts.sim_tick = 2*WorldState.TICKS_PER_DAY
	service.boundaries(world)
	_check("hold_uses_current_open_desks",held.accepted and world.facts.arrivals.plan.scale_numerator==1 and service.outpatient_allowance(world.facts.arrivals.plan)==16,world.facts.arrivals.plan)
	world.facts.facilities.demand_desk2.open = true
	world.facts.patient_experience.units.general.open = false
	world.touch()
	_check("closed_department_excluded",service.demand_desks(world)==1,service.capacity(world))
	world.facts.rooms.demand_gp2.open = false
	world.touch()
	_check("closed_room_excluded",service.demand_desks(world)==0,service.capacity(world))
	var hold_preview: Array = service.daystats(world).tomorrow_range
	_check("tomorrow_preview_matches_closed_scale",hold_preview==[0,0],hold_preview)
	var replay_a: HospitalSimulation = _context()
	var replay_b: HospitalSimulation = _context()
	replay_a.services.arrivals.boundaries(replay_a.world)
	replay_b.services.arrivals.boundaries(replay_b.world)
	_check("seeded_day_replay",replay_a.world.facts.arrivals.plan==replay_b.world.facts.arrivals.plan and replay_a.world.facts.rng==replay_b.world.facts.rng,replay_a.world.facts.arrivals.plan)
	replay_a.dispose()
	replay_b.dispose()
	sim.dispose()
	_finish()

func _finish() -> void:
	var passed: bool = not checks.is_empty()
	for check: Dictionary in checks.values(): passed = passed and check.passed
	var output: FileAccess = FileAccess.open("res://random-arrival-demand-results.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"passed":passed,"checks":checks},"\t"))
	output.close()
	quit(0 if passed else 1)
