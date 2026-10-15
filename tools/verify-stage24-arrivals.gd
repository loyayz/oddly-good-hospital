extends SceneTree

const Arrivals = preload("res://game/arrivals/arrival_service.gd")
const F = preload("res://game/arrivals/exact_fraction.gd")
const Plan = preload("res://game/arrivals/day_plan.gd")
const Factory = preload("res://game/sim/hospital_factory.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	_check("published_content_loaded",content.error.is_empty())
	var empty: WorldState = Factory.create("arrival-empty","空地来客",false,content)
	var space: HospitalSpace = HospitalSpace.new(content)
	var arrivals: RefCounted = Arrivals.new(content,space)
	arrivals.ensure(empty)
	var original_rng: String = JSON.stringify(empty.facts.rng)
	arrivals.boundaries(empty)
	_check("unserviceable_empty_land_has_zero_opportunities",empty.facts.arrivals.plan.opportunity_count == 0 and empty.facts.arrivals.plan.schedule_seed == null)
	_check("zero_capacity_consumes_no_density_or_seed_draw",original_rng == JSON.stringify(empty.facts.rng))
	var before: String = JSON.stringify(empty.freeze())
	arrivals.daystats(empty)
	arrivals.residents(empty)
	arrivals.capacity(empty)
	_check("capacity_and_readonly_views_do_not_change_world",before == JSON.stringify(empty.freeze()))
	var plan: Dictionary = _plan(3,3)
	empty.facts.arrivals.plan = plan
	empty.facts.arrivals.intake_open = false
	empty.facts.sim_tick = 5999
	original_rng = JSON.stringify(empty.facts.rng)
	arrivals.arrivals(empty)
	_check("closed_hospital_consumes_each_opportunity_without_patient_draws",plan.next_slot_index == 3 and empty.facts.actors.is_empty() and original_rng == JSON.stringify(empty.facts.rng))
	_check("closed_counts_have_original_opportunity_conservation",empty.facts.arrivals.daily_stats["1"].closed == 3 and empty.facts.arrivals.daily_stats["1"].opportunities == 3)
	empty.facts.arrivals.plan = _plan(3,0)
	empty.facts.arrivals.intake_open = true
	original_rng = JSON.stringify(empty.facts.rng)
	arrivals.arrivals(empty)
	_check("full_allowance_consumes_without_case_identity_or_body_draws",empty.facts.arrivals.plan.next_slot_index == 3 and original_rng == JSON.stringify(empty.facts.rng) and empty.facts.actors.is_empty())
	var old_plan: Dictionary = empty.facts.arrivals.plan.duplicate(true)
	_check("preset_change_is_next_day",arrivals.execute(empty,"arrivals_preset",{"preset":"busy"}).accepted and empty.facts.arrivals.preset == "normal" and empty.facts.arrivals.next_preset == "busy" and empty.facts.arrivals.plan == old_plan)
	_check("tutorial_order_comes_from_published_steps",arrivals._tutorial_request(empty).step_id == "OB03")
	arrivals.execute(empty,"tutorial_skip_request",{"step_id":"OB03"})
	_check("tutorial_skip_uses_next_original_request",arrivals._tutorial_request(empty).step_id == "OB04")
	arrivals.execute(empty,"tutorial_set_enabled",{"enabled":false})
	arrivals.execute(empty,"tutorial_set_enabled",{"enabled":true})
	_check("reopening_tutorial_does_not_restore_cancelled_arrival",arrivals._tutorial_request(empty).is_empty())
	_real_capacity(content)
	_patience(content)
	_wait_sample_order(content)
	_resident(content)
	print(JSON.stringify({"stage":24,"suite":"arrivals","passed":failures.is_empty(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _real_capacity(content: HospitalContent) -> void:
	var world: WorldState = Factory.create("real-capacity","真实接诊资源",true,content)
	var space: HospitalSpace = HospitalSpace.new(content)
	var arrivals: RefCounted = Arrivals.new(content,space)
	arrivals.ensure(world)
	var scheduler_path: String = "res://game/staff/shift_scheduler.gd"
	if ResourceLoader.exists(scheduler_path):
		var scheduler: RefCounted = load(scheduler_path).new(content,space)
		scheduler.call("ensure",world)
	var before: String = JSON.stringify(world.freeze())
	var projection: Dictionary = arrivals.capacity(world)
	_check("actual_starter_resources_generate_positive_complete_capacity",projection.get("complete",false) and F.compare(projection.get("capacity",F.make()),F.make()) > 0 and int(projection.get("scale_numerator",0)) > 0)
	_check("real_capacity_solver_reserves_nothing_and_draws_nothing",before == JSON.stringify(world.freeze()))
	for staff: Dictionary in world.facts.staff.values():
		staff.on_shift = false
		if staff.has("schedule"):
			for entry: Dictionary in staff.schedule:
				entry.kind = "rest"
	var unstaffed: Dictionary = arrivals.capacity(world)
	_check("installed_devices_without_actual_roster_do_not_create_opportunities",unstaffed.get("complete",false) and unstaffed.capacity == F.make())

func _patience(content: HospitalContent) -> void:
	var world: WorldState = FeasibilityHospitals.create("wait-original-ticket",false,content)
	var space: HospitalSpace = HospitalSpace.new(content)
	var arrivals: RefCounted = Arrivals.new(content,space)
	arrivals.ensure(world)
	var visit: Dictionary = world.facts.visits.values()[0]
	visit.phase = "wait_gp"
	visit.personality_id = "PP02"
	visit.anger = 15.0
	visit.last_progress_tick = 0
	visit.last_service_tick = 0
	visit.ticket_id = "original_wait_ticket"
	world.facts.tickets[visit.ticket_id] = {"id":visit.ticket_id,"visit_id":visit.id,"kind":"gp","enqueued_tick":0,"waited_ticks":1199,"pause_reasons":{}}
	var ticket: Dictionary = world.facts.tickets[visit.ticket_id]
	_check("source_impatient_120_second_probability",arrivals.patience_probability(world,visit,{"waited_ticks":1200}) == 600)
	visit.personality_id = "PP09"
	_check("source_slow_120_second_probability",arrivals.patience_probability(world,visit,{"waited_ticks":1200}) == 260)
	visit.personality_id = "PP01"
	world.facts.sim_tick = 1199
	arrivals.advance_wait(world)
	arrivals.needs(world)
	var state: Dictionary = world.facts.wait_departures[visit.actor_id]
	_check("first_threshold_advances_before_the_only_draw",ticket.waited_ticks == 1200 and state.next_check_wait_ticks == 1500)
	var after: String = JSON.stringify(world.freeze())
	var random_after: String = JSON.stringify(world.facts.rng.patience)
	arrivals.advance_wait(world)
	arrivals.needs(world)
	_check("same_tick_duplicate_notice_does_not_recount_or_redraw",after == JSON.stringify(world.freeze()))
	var restored: WorldState = WorldState.new(world.freeze())
	var restored_service: RefCounted = Arrivals.new(content,HospitalSpace.new(content))
	restored_service.advance_wait(restored)
	restored_service.needs(restored)
	_check("restore_rebuild_does_not_replay_consumed_threshold",after == JSON.stringify(restored.freeze()))
	if not state.selected:
		ticket.pause_reasons.need_service = "actual_water_service"
		for tick: int in range(1200,1600):
			world.facts.sim_tick = tick
			arrivals.advance_wait(world)
			arrivals.needs(world)
		_check("life_service_pauses_original_ticket_clock_and_draws",ticket.waited_ticks == 1200 and random_after == JSON.stringify(world.facts.rng.patience))
		ticket.pause_reasons.erase("need_service")
		world.facts.sim_tick = 1600
		arrivals.advance_wait(world)
		arrivals.needs(world)
		_check("life_return_resumes_remaining_wait_and_fairness",ticket.waited_ticks == 1201 and state.next_check_wait_ticks == 1500 and visit.ticket_id == "original_wait_ticket")
	var safety: WorldState = FeasibilityHospitals.create("deterministic-wait",false,content)
	var safe_arrivals: RefCounted = Arrivals.new(content,HospitalSpace.new(content))
	safe_arrivals.ensure(safety)
	var angry: Dictionary = safety.facts.visits.values()[0]
	angry.phase = "wait_gp"
	angry.anger = float(content.balance.anger.leave_threshold)
	angry.ticket_id = "angry_ticket"
	angry.last_service_tick = 0
	angry.last_progress_tick = 0
	safety.facts.tickets.angry_ticket = {"id":"angry_ticket","visit_id":angry.id,"kind":"gp","enqueued_tick":0,"waited_ticks":599,"pause_reasons":{}}
	safety.facts.sim_tick = 600
	var rng: String = JSON.stringify(safety.facts.rng.patience)
	safe_arrivals.advance_wait(safety)
	safe_arrivals.needs(safety)
	_check("deterministic_safe_exit_precedes_probability",angry.phase == "leaving" and angry.final_result == "abandoned" and rng == JSON.stringify(safety.facts.rng.patience))

func _wait_sample_order(content: HospitalContent) -> void:
	var world: WorldState = FeasibilityHospitals.create("wait-sample-order",false,content)
	var arrivals: RefCounted = Arrivals.new(content,HospitalSpace.new(content))
	arrivals.ensure(world)
	var visit: Dictionary = world.facts.visits.values()[0]
	visit.phase = "wait_gp"
	visit.anger = 15.0
	visit.personality_id = "PP01"
	visit.last_progress_tick = 0
	visit.last_service_tick = 1199
	visit.ticket_id = "sample_order_ticket"
	world.facts.tickets[visit.ticket_id] = {"id":visit.ticket_id,"visit_id":visit.id,"kind":"gp","enqueued_tick":0,"waited_ticks":1199,"pause_reasons":{}}
	var original_ticket: Dictionary = world.facts.tickets[visit.ticket_id]
	world.facts.sim_tick = 1199
	var rng: String = JSON.stringify(world.facts.rng.patience)
	arrivals.advance_wait(world)
	_check("wait_advance_exposes_current_clock_without_departure_or_draw",world.facts.tickets[visit.ticket_id].waited_ticks == 1200 and visit.phase == "wait_gp" and rng == JSON.stringify(world.facts.rng.patience))
	# The department sample runs here and applies this tick's real anger input.
	visit.anger = 45.0
	arrivals.needs(world)
	var probability: int = -1
	for event: SimEvent in arrivals.take_events():
		if event.kind == "patience_evaluated":
			probability = int(event.details.probability_bp)
	_check("patience_reads_the_same_tick_sample_after_wait_advance",probability == 525)
	_check("needs_never_integrates_a_second_wait_tick",int(original_ticket.waited_ticks) == 1200)
	var deterministic: WorldState = FeasibilityHospitals.create("sampled-anger-exit",false,content)
	var service: RefCounted = Arrivals.new(content,HospitalSpace.new(content))
	service.ensure(deterministic)
	var angry: Dictionary = deterministic.facts.visits.values()[0]
	angry.phase = "wait_gp"
	angry.anger = 89.0
	angry.last_progress_tick = 0
	angry.last_service_tick = 0
	angry.ticket_id = "sampled_anger_ticket"
	deterministic.facts.tickets[angry.ticket_id] = {"id":angry.ticket_id,"visit_id":angry.id,"kind":"gp","enqueued_tick":0,"waited_ticks":1199,"pause_reasons":{}}
	deterministic.facts.sim_tick = 1199
	rng = JSON.stringify(deterministic.facts.rng.patience)
	service.advance_wait(deterministic)
	angry.anger = float(content.balance.anger.leave_threshold)
	service.needs(deterministic)
	_check("same_tick_sampled_deterministic_exit_preempts_due_random_draw",angry.phase == "leaving" and angry.final_result == "abandoned" and rng == JSON.stringify(deterministic.facts.rng.patience))

func _resident(content: HospitalContent) -> void:
	var world: WorldState = FeasibilityHospitals.create("true-resident",false,content)
	var space: HospitalSpace = HospitalSpace.new(content)
	var arrivals: RefCounted = Arrivals.new(content,space)
	arrivals.ensure(world)
	var visit: Dictionary = world.facts.visits.values()[0]
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	var resident: Dictionary = arrivals._new_identity(world,str(actor.species_id))
	resident.name = actor.name
	resident.personality_id = visit.personality_id
	resident.current_actor_id = actor.id
	world.facts.residents[resident.id] = resident
	actor.resident_id = resident.id
	_check("remember_uses_real_in_hospital_identity",arrivals.execute(world,"resident_remember",{"resident_id":resident.id}).accepted)
	_check("forget_does_not_remove_present_person",arrivals.execute(world,"resident_forget",{"resident_id":resident.id}).accepted and world.facts.residents.has(resident.id) and resident.pending_release)
	_check("remember_can_cancel_pending_release",arrivals.execute(world,"resident_remember",{"resident_id":resident.id}).accepted and not resident.pending_release)
	visit.phase = "leaving"
	visit.final_result = "cured"
	world.facts.sim_tick = 100
	arrivals.settle(world)
	_check("intention_to_leave_does_not_start_return_cooldown",resident.last_departure_tick == -1 and resident.memories.is_empty())
	actor.location = {"kind":"outside"}
	visit.phase = "departed"
	visit.departed_tick = world.sim_tick
	arrivals.settle(world)
	_check("real_departure_commits_one_memory",resident.last_departure_tick == 100 and resident.memories.size() == 1 and resident.visits_completed == 1)
	arrivals.settle(world)
	_check("departure_settlement_is_idempotent",resident.memories.size() == 1 and resident.visits_completed == 1)
	var rng: String = JSON.stringify(world.facts.rng.arrival)
	world.facts.sim_tick = 100+WorldState.TICKS_PER_DAY*2-1
	_check("no_eligible_resident_means_no_identity_draw",arrivals._returning_resident(world,str(actor.species_id),str(visit.binding_id)).is_empty() and rng == JSON.stringify(world.facts.rng.arrival))
	arrivals.execute(world,"resident_forget",{"resident_id":resident.id})
	_check("history_does_not_permanently_occupy_regular_book",not world.facts.residents.has(resident.id) and world.facts.visits.has(visit.id))

func _plan(count: int, scale: int) -> Dictionary:
	return {"day_index":1,"preset":"normal","scale_numerator":scale,"shift_capacities":[F.make(1),F.make(),F.make()],
		"opportunity_count":count,"shift_opportunity_counts":[count,0,0],"schedule_seed":"321","schedule_algorithm":"arrival-load-slot-v1",
		"next_slot_index":0,"held_capacity_fraction":F.make(),"held_scale_numerator":0}

func _check(label: String, passed: bool) -> void:
	if not passed:
		failures.append(label)
