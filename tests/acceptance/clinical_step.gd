extends RefCounted

# Clinical scenarios keep the production phase order and real 0.1-second work,
# movement, staff needs and safety. Recruitment, hospital ratings, research and
# daily operating accounts have independent specialist cases.
static func step(sim: HospitalSimulation, remodel: bool = false) -> TickResult:
	var world: WorldState = sim.world
	var services: Dictionary = sim.services
	var present: int = world.present_actor_count()
	services.supplies.boundaries(world)
	services.scheduler.boundaries(world)
	services.wellbeing.boundaries(world)
	services.maintenance.boundaries(world)
	sim.clinic.arrivals(world)
	if remodel: services.remodel.dispatch(world)
	services.scheduler.dispatch(world)
	services.development.dispatch(world)
	services.waiting.dispatch(world)
	services.maintenance.dispatch(world)
	sim.clinic.dispatch(world)
	for staff_id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[staff_id]
		staff.dispatch_idle = not HospitalClinicalDevelopment.safe_busy(world,staff_id) and not world.facts.moves.has(staff_id) and staff.get("base_task",{}).is_empty() and str(staff.get("training_job_id","")).is_empty()
	services.wellbeing.dispatch(world)
	var before_movement: Dictionary = {}
	for staff_id: String in world.ids("staff"):
		before_movement[staff_id] = world.facts.actors[staff_id].location.duplicate(true)
	sim.space.advance(world,present)
	sim.clinic.advance(world)
	services.development.advance(world)
	services.scheduler.advance(world)
	services.maintenance.advance(world)
	var worked: Dictionary = sim.clinic.worked_staff()
	worked.merge(services.development.worked_staff(),true)
	worked.merge(services.scheduler.worked_staff(),true)
	services.wellbeing.advance(world,worked,before_movement)
	services.waiting.advance(world)
	services.supplies.advance(world)
	services.arrivals.advance_wait(world)
	services.arrivals.needs(world)
	sim.clinic.release_departed(world)
	sim.clinic.settle_practice(world)
	services.development.settle(world)
	services.recruitment.settle(world)
	var events: Array[SimEvent] = sim.clinic.take_events()
	events.append_array(HospitalLedger.settle(world))
	world.facts.sim_tick += 1
	world.touch()
	sim.space.finish_boundary(world)
	return TickResult.new(world.sim_tick,world.revision,events)
