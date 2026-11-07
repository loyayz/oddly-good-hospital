extends "res://game/sim/simulation.gd"
var _step_profile_observer: RefCounted
func step_nonblocking() -> TickResult:
	_step_profile_observer.root("step.setup") # step-profile-marker
	var main_started: int = Time.get_ticks_usec()
	if _step_context.is_empty():
		_step_context = {"phase":"commands","present":world.present_actor_count(),"started_us":main_started,"main_us":0}
	if _step_context.phase=="commands":
		_step_profile_observer.root("commands.drain") # step-profile-marker
		drain_commands() # 1: the original command boundary is sealed once.
		if not _command_boundary.is_empty():
			_step_context.main_us += Time.get_ticks_usec()-main_started
			_step_profile_observer.close_root() # step-profile-marker
			return null
		if _production():
			_step_profile_observer.root("boundaries.supplies") # step-profile-marker
			services.supplies.boundaries(world)
			_step_profile_observer.root("boundaries.research") # step-profile-marker
			services.research.boundaries(world) # 2: schedules and equipment.
			_step_profile_observer.root("boundaries.scheduler") # step-profile-marker
			services.scheduler.boundaries(world)
			_step_profile_observer.root("boundaries.wellbeing") # step-profile-marker
			services.wellbeing.boundaries(world)
			_step_profile_observer.root("boundaries.maintenance") # step-profile-marker
			services.maintenance.boundaries(world)
			_step_profile_observer.root("boundaries.recruitment") # step-profile-marker
			services.recruitment.boundaries(world)
		_step_context.phase = "plan"
	_step_profile_observer.root("boundaries.arrivals") # step-profile-marker
	if _production() and not services.arrivals.boundaries(world):
		_step_context.main_us += Time.get_ticks_usec()-main_started
		_step_profile_observer.close_root() # step-profile-marker
		return null
	var present_at_start: int = int(_step_context.present)
	if _production(): # 3: real arrivals and family requests.
		_step_profile_observer.root("arrivals.arrivals") # step-profile-marker
		services.arrivals.arrivals(world)
		_step_profile_observer.root("clinic.arrivals") # step-profile-marker
		clinic.arrivals(world)
	if _production(): # 4: dispatch against current occupancy.
		_step_profile_observer.root("dispatch.remodel") # step-profile-marker
		services.remodel.dispatch(world)
		_step_profile_observer.root("dispatch.scheduler") # step-profile-marker
		services.scheduler.dispatch(world)
		_step_profile_observer.root("dispatch.development") # step-profile-marker
		services.development.dispatch(world)
		_step_profile_observer.root("dispatch.floor_guidance") # step-profile-marker
		services.floor_guidance.dispatch(world)
		_step_profile_observer.root("dispatch.waiting") # step-profile-marker
		services.waiting.dispatch(world)
		_step_profile_observer.root("dispatch.departments") # step-profile-marker
		services.departments.dispatch(world)
		_step_profile_observer.root("dispatch.environment") # step-profile-marker
		services.environment.dispatch(world)
		_step_profile_observer.root("dispatch.maintenance") # step-profile-marker
		services.maintenance.dispatch(world)
		_step_profile_observer.root("dispatch.floors") # step-profile-marker
		services.floors.dispatch(world)
	_step_profile_observer.root("clinic.dispatch") # step-profile-marker
	clinic.dispatch(world)
	if _production():
		var busy: Dictionary = HospitalClinicalDevelopment.busy_view(world)
		_step_profile_observer.root("dispatch.staff_idle") # step-profile-marker
		for staff_id: String in world.ids("staff"):
			var staff: Dictionary = world.facts.staff[staff_id]
			staff.dispatch_idle = not HospitalClinicalDevelopment.safe_busy(world,staff_id,busy) and not world.facts.moves.has(staff_id) and staff.get("base_task",{}).is_empty() and str(staff.get("training_job_id","")).is_empty()
			staff.dispatch_idle_tick = world.sim_tick
		_step_profile_observer.root("dispatch.wellbeing") # step-profile-marker
		services.wellbeing.dispatch(world)
	var before_movement: Dictionary = {}
	_step_profile_observer.root("movement.capture_staff_locations") # step-profile-marker
	for staff_id: String in world.ids("staff"):
		before_movement[staff_id] = world.facts.actors[staff_id].location.duplicate(true)
	_step_profile_observer.root("movement.space") # step-profile-marker
	space.advance(world,present_at_start) # 5: actual routes and vertical transit.
	_step_profile_observer.root("clinic.advance") # step-profile-marker
	clinic.advance(world) # 6: work and safe completion.
	if _production():
		_step_profile_observer.root("advance.development") # step-profile-marker
		services.development.advance(world)
		_step_profile_observer.root("advance.research") # step-profile-marker
		services.research.advance(world)
		_step_profile_observer.root("advance.scheduler") # step-profile-marker
		services.scheduler.advance(world)
		_step_profile_observer.root("advance.environment") # step-profile-marker
		services.environment.advance(world)
		_step_profile_observer.root("advance.maintenance") # step-profile-marker
		services.maintenance.advance(world)
		_step_profile_observer.root("advance.departments") # step-profile-marker
		services.departments.advance(world)
		_step_profile_observer.root("advance.floor_guidance") # step-profile-marker
		services.floor_guidance.advance(world)
		_step_profile_observer.root("advance.recruitment") # step-profile-marker
		services.recruitment.advance(world)
		_step_profile_observer.root("advance.floors") # step-profile-marker
		services.floors.advance(world)
	if _production(): # 7: integrate each real work/movement source once.
		_step_profile_observer.root("integrate.worked_staff") # step-profile-marker
		var worked: Dictionary = clinic.worked_staff()
		worked.merge(services.development.worked_staff(),true)
		worked.merge(services.research.worked_staff(),true)
		worked.merge(services.scheduler.worked_staff(),true)
		worked.merge(services.environment.worked_staff(),true)
		worked.merge(services.maintenance.worked_staff(),true)
		worked.merge(services.departments.worked_staff(),true)
		worked.merge(services.floor_guidance.worked_staff(),true)
		worked.merge(services.floors.worked_staff(),true)
		_step_profile_observer.root("advance.wellbeing") # step-profile-marker
		services.wellbeing.advance(world,worked,before_movement)
		_step_profile_observer.root("advance.waiting") # step-profile-marker
		services.waiting.advance(world)
		_step_profile_observer.root("advance.supplies") # step-profile-marker
		services.supplies.advance(world)
		_step_profile_observer.root("begin_query.environment") # step-profile-marker
		services.environment.begin_query(world)
		_step_profile_observer.root("advance_wait.arrivals") # step-profile-marker
		services.arrivals.advance_wait(world)
		_step_profile_observer.root("sample.departments") # step-profile-marker
		services.departments.sample(world)
		_step_profile_observer.root("needs.arrivals") # step-profile-marker
		services.arrivals.needs(world)
		_step_profile_observer.root("end_query.environment") # step-profile-marker
		services.environment.end_query()
	else:
		_step_profile_observer.root("integrate.legacy_staff") # step-profile-marker
		_integrate_staff(before_movement)
	# 8: interaction consequences precede settlement.
	_step_profile_observer.root("clinic.release_departed") # step-profile-marker
	clinic.release_departed(world) # 9: release only after physical handoff.
	_step_profile_observer.root("clinic.settle_practice") # step-profile-marker
	clinic.settle_practice(world)
	if _production():
		_step_profile_observer.root("settle.research") # step-profile-marker
		services.research.settle(world)
		_step_profile_observer.root("settle.development") # step-profile-marker
		services.development.settle(world)
		_step_profile_observer.root("settle.departments") # step-profile-marker
		services.departments.settle(world)
		_step_profile_observer.root("settle.finance") # step-profile-marker
		services.finance.settle(world)
		_step_profile_observer.root("settle.recruitment") # step-profile-marker
		services.recruitment.settle(world)
		_step_profile_observer.root("settle.arrivals") # step-profile-marker
		services.arrivals.settle(world)
	_step_profile_observer.root("events.collect") # step-profile-marker
	var events: Array[SimEvent] = _command_events
	_command_events = []
	events.append_array(clinic.take_events())
	if _production():
		events.append_array(services.arrivals.take_events())
		events.append_array(services.research.take_events())
	_step_profile_observer.root("settlement.ledger") # step-profile-marker
	events.append_array(HospitalLedger.settle(world))
	_step_profile_observer.root("settlement.finish_visits") # step-profile-marker
	world.finish_visits()
	_step_profile_observer.root("snapshot.world_boundary") # step-profile-marker
	world.facts.sim_tick += 1
	world.touch(false) # 10: complete immutable snapshot boundary; movement/work do not edit floor geometry.
	_step_profile_observer.root("snapshot.space_boundary") # step-profile-marker
	space.finish_boundary(world)
	_step_profile_observer.root("snapshot.tick_result") # step-profile-marker
	events.append(SimEvent.new(world.sim_tick,"tick_completed",[],{"revision":world.revision}))
	var result: TickResult = TickResult.new(world.sim_tick,world.revision,events)
	_step_profile_observer.root("snapshot.bookkeeping") # step-profile-marker
	var finished: int = Time.get_ticks_usec()
	result.started_engine_us = int(_step_context.started_us)
	result.completed_engine_us = finished
	result.elapsed_us = finished-result.started_engine_us
	result.main_elapsed_us = int(_step_context.main_us)+finished-main_started
	_step_context = {}
	_step_profile_observer.close_root() # step-profile-marker
	return result

