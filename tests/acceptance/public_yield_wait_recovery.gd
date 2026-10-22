extends "res://tests/acceptance/staff_fixtures.gd"

# Observe the real automatic fallback. The probe neither changes its result nor
# requests another quote, invalidates waiting, or advances any actor itself.
class WaitingProbe extends HospitalWaitingLife:
	var observed_visit: String = ""
	var automatic_quotes: Array = []
	func _manual_seat_quote(world: WorldState, visit: Dictionary, facility_id: String) -> Dictionary:
		var result: Dictionary = super._manual_seat_quote(world,visit,facility_id)
		if visit.id==observed_visit:
			automatic_quotes.append({"tick":world.sim_tick,"facility_id":facility_id,"quote":result.duplicate(true)})
		return result

func _tick(x: Dictionary) -> void:
	x.world.facts.sim_tick += 1
	x.c.visitors.dispatch(x.world)
	x.l.dispatch(x.world)
	x.space.advance(x.world)
	x.l.advance(x.world)
	x.world.touch(false)

func _until_patient_seated(x: Dictionary, visit: Dictionary, limit: int = 600) -> bool:
	for _step: int in limit:
		if x.world.facts.waiting_life.seats.get(visit.id,{}).get("phase","")=="seated": return true
		_tick(x)
	return x.world.facts.waiting_life.seats.get(visit.id,{}).get("phase","")=="seated"

func _outside_regions(rectangle: Rect2, regions: Array) -> bool:
	for area: Array in regions:
		if rectangle.intersects(Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3])),false): return false
	return true

func _rect_record(rectangle: Rect2) -> Array:
	return [rectangle.position.x,rectangle.position.y,rectangle.size.x,rectangle.size.y]

func _dispose(x: Dictionary) -> void:
	x.a.dispose()
	x.p.waiting_life = null
	x.p.environment = null
	x.l.environment = null
	x.l.visitors = null
	x.c.recruitment = null
	x.clear()

# Rule inputs: life design §17 requires a usable patient seat to trigger a
# visitor's yield within two seconds, with real departure before transfer.
# Public-area specification §3.5 requires a relevant nearby body release to
# wake a negative wait. FUR10 stays 2x2 cells; its R16 unlock and the S52/D43
# binding are content facts. No old solver/signature supplies the expectation.
func run_case(database: HospitalContent) -> Dictionary:
	_content = database
	var x: Dictionary = _fixture({"yield_bystander":"nurse"})
	var room_id: String = _room(x,"waiting")
	_facility(x,"yield_host_chair","FUR09",[52,72],room_id)
	_facility(x,"yield_large_chair","FUR10",[44,72],room_id)
	x.world.facts.research.append("R16")
	x.world.facts.entry = {"floor_id":1,"cell":[38,88],"exit_cell":[38,88]}
	# Initial legal boundary only: this small standing body does not intersect
	# any region later acquired by the genuinely seated small visitor.
	_position(x,"yield_bystander",[45,75])
	x.world.touch()
	var probe: WaitingProbe = WaitingProbe.new(_content,x.space)
	probe.environment = x.e
	probe.visitors = x.c.visitors
	x.l = probe
	x.p.waiting_life = probe
	probe.ensure(x.world)
	var host: Dictionary = _visit(x,"yield_host",[53,80])
	var host_request: CommandResult = x.l.execute(x.world,"waiting_select_seat",{"visit_id":host.id,"facility_id":"yield_host_chair"})
	var host_seated: bool = _until_patient_seated(x,host)
	var admitted: bool = x.c.visitors._admit(x.world,host,{"purpose":"companion","window":""})
	var visitor: Dictionary = {}
	var visitor_seated: bool = false
	for _step: int in 600:
		visitor = x.c.visitors._present(x.world,host.id)
		if visitor.get("public_use",{}).get("phase","")=="seated":
			visitor_seated = visitor.public_use.facility_id=="yield_large_chair"
			break
		_tick(x)
	var checks: Dictionary = {"host_walked_to_own_seat":host_request.accepted and host_seated,"visitor_admitted_and_actually_seated":admitted and visitor_seated}
	if not host_seated or not visitor_seated:
		var failure: Dictionary = {"ok":false,"checks":checks,"host_request":host_request.to_record(),"host":host.duplicate(true),"visitor":visitor.duplicate(true),"moves":x.world.facts.moves.duplicate(true)}
		_dispose(x)
		return failure
	# A legal wait-GP boundary for another real case. Queue creation does not
	# depend on the disease; set the complete published S52/D43 identity before
	# any of this patient's automatic decisions or movement are executed.
	var patient: Dictionary = _visit(x,"yield_priority",[38,80])
	var actor: Dictionary = x.world.facts.actors[patient.actor_id]
	actor.species_id = "S52"
	actor.body_binding_id = "B_S52_D43_M43"
	patient.binding_id = "B_S52_D43_M43"
	patient.disease_id = "D43"
	patient.requested_plan_id = "P_D43_COMMON"
	x.space.sync_actor(x.world,patient.actor_id)
	probe.observed_visit = patient.id
	var bystander: Dictionary = x.world.facts.actors.yield_bystander
	var original_regions: Array = x.world.facts.adaptations.yield_large_chair.regions.duplicate(true)
	var original_visitor: Array = x.world.facts.actors[visitor.actor_id].location.cell.duplicate()
	var original_patient: Array = actor.location.cell.duplicate()
	var original_bystander: Array = bystander.location.cell.duplicate()
	var original_bystander_rect: Array = _rect_record(x.space.body_rectangle(bystander))
	var original_fixed: Array = x.world.facts.facilities.yield_large_chair.footprint.duplicate()
	var future_patient_region: Rect2 = Rect2(44.0,74.0,2.0,2.0)
	var body: Dictionary = x.space.body(actor)
	var geometry: Dictionary = x.space.facility_geometry_quote(x.world,"yield_large_chair",patient.actor_id)
	var input_validation: String = x.world.validate(_content)
	checks.legal_input = input_validation.is_empty()
	checks.fixed_large_chair_really_fits_patient = original_fixed==[2,2] and body.width_m==1.2 and body.depth_m==1.8 and body.width_m<=3.0 and body.depth_m<=3.0 and geometry.get("ok",false) and geometry.get("footprint",[])==[2,2]
	checks.bystander_is_not_a_public_queue_member = not x.world.facts.staff.yield_bystander.get("life_task",{}).has("public_purpose")
	checks.bystander_does_not_invade_existing_reservation = _outside_regions(x.space.body_rectangle(bystander),original_regions)
	checks.bystander_blocks_future_patient_place = x.space.body_rectangle(bystander).intersects(future_patient_region,false)
	# Let the ordinary five-second scan create the area intent. There is no
	# manual target command and no manufactured arrived/seated checkpoint.
	for _step: int in 60:
		if not probe.automatic_quotes.is_empty(): break
		_tick(x)
	var first_quotes: Array = probe.automatic_quotes.duplicate(true)
	var initial_intent: Dictionary = x.world.facts.waiting_life.seats.get(patient.id,{}).duplicate(true)
	checks.automatic_failed_quote_keeps_patient_waiting = not first_quotes.is_empty() and first_quotes.all(func(row: Dictionary)->bool:return not row.quote.get("ok",false) and str(row.quote.get("reason","")).contains("yield_bystander")) and initial_intent.get("mode","")=="auto" and initial_intent.get("phase","")=="local_wait" and not x.world.facts.moves.has(patient.actor_id) and actor.location.cell==original_patient
	var quote_count_before_hold: int = probe.automatic_quotes.size()
	for _step: int in 3: _tick(x)
	checks.failed_attempt_did_not_release_or_move_visitor = visitor.public_use.phase=="seated" and x.world.facts.actors[visitor.actor_id].location.cell==original_visitor and x.world.facts.adaptations.yield_large_chair.actor_id==visitor.actor_id
	var retained_wait_hits: int = int(x.space.query_counts.get("public_wait_hits",0))
	var quote_count_after_hold: int = probe.automatic_quotes.size()
	checks.unchanged_blocker_reuses_negative_result = quote_count_before_hold==quote_count_after_hold and retained_wait_hits>0
	var move_reason: String = x.space.request_move(x.world,"yield_bystander",1,[50,75])
	var clear_tick: int = -1
	var yield_tick: int = -1
	var seated_tick: int = -1
	var bystander_moved: bool = false
	var visitor_moved: bool = false
	var patient_moved: bool = false
	var patient_route_requested: bool = false
	var safe_handoff: bool = true
	var fixed_throughout: bool = true
	var origin_ticket: String = str(patient.ticket_id)
	var origin_queue_tick: int = int(x.world.facts.tickets[origin_ticket].enqueued_tick)
	# Two seconds is the authored yield-start limit. Once that limit expires,
	# finish a started real handoff, but do not wait for unrelated new needs to
	# hide a missing wake-up. All movement is the production advance operation.
	var maximum_ticks: int = 700
	for _step: int in maximum_ticks:
		_tick(x)
		bystander_moved = bystander_moved or bystander.location.cell!=original_bystander
		visitor_moved = visitor_moved or x.world.facts.actors[visitor.actor_id].location.cell!=original_visitor
		patient_moved = patient_moved or actor.location.cell!=original_patient
		patient_route_requested = patient_route_requested or x.world.facts.moves.has(patient.actor_id)
		if clear_tick<0 and not x.space.body_rectangle(bystander).intersects(future_patient_region,false): clear_tick = x.world.sim_tick
		if yield_tick<0 and visitor.public_use.phase!="seated": yield_tick = x.world.sim_tick
		fixed_throughout = fixed_throughout and x.world.facts.facilities.yield_large_chair.footprint==original_fixed and x.space.facility_layout(x.world,"yield_large_chair").footprint==original_fixed
		var patient_has_seat: bool = x.world.facts.waiting_life.seats.get(patient.id,{}).get("phase","")=="seated"
		if x.world.facts.adaptations.get("yield_large_chair",{}).get("actor_id","")==patient.actor_id or patient_has_seat:
			safe_handoff = safe_handoff and _outside_regions(x.space.body_rectangle(x.world.facts.actors[visitor.actor_id]),original_regions)
		if patient_has_seat:
			seated_tick = x.world.sim_tick
			break
		if clear_tick>=0 and yield_tick<0 and x.world.sim_tick-clear_tick>ceili(2.0/WorldState.TICK_SECONDS): break
	var automatic_after_exit: Array = probe.automatic_quotes.filter(func(row: Dictionary)->bool:return clear_tick>=0 and int(row.tick)>=clear_tick)
	checks.third_person_really_walked_clear = move_reason.is_empty() and bystander_moved and clear_tick>=0 and bystander.location.cell!=original_bystander
	checks.automatic_quote_recovered_after_release = automatic_after_exit.any(func(row: Dictionary)->bool:return row.quote.get("ok",false))
	checks.yield_started_within_authored_two_seconds = clear_tick>=0 and yield_tick>=clear_tick and yield_tick-clear_tick<=ceili(2.0/WorldState.TICK_SECONDS)
	checks.visitor_really_left_before_transfer = visitor_moved and safe_handoff and _outside_regions(x.space.body_rectangle(x.world.facts.actors[visitor.actor_id]),original_regions)
	checks.patient_really_walked_and_arrived = patient_route_requested and patient_moved and seated_tick>=0 and x.space.at(x.world,patient.actor_id,1,[44,74]) and actor.get("posture","")=="seated" and actor.get("support_facility_id","")=="yield_large_chair"
	checks.chair_never_stretched = fixed_throughout
	checks.original_ticket_and_queue_order_retained = patient.ticket_id==origin_ticket and int(x.world.facts.tickets[origin_ticket].enqueued_tick)==origin_queue_tick
	# Independent read after the timed observation: confirms the same complete
	# prospective vacancy is now legal even when automatic recovery stayed asleep.
	var reader: HospitalWaitingLife = HospitalWaitingLife.new(_content,x.space)
	var current_source: Dictionary = x.world.freeze()
	var after_exit_quote: Dictionary = reader._manual_seat_quote(x.world,patient,"yield_large_chair")
	checks.released_body_allows_complete_quote = after_exit_quote.get("ok",false) and current_source==x.world.freeze()
	var final_validation: String = x.world.validate(_content)
	checks.final_world_valid = final_validation.is_empty()
	var ok: bool = checks.values().all(func(value: Variant)->bool:return value==true)
	var result: Dictionary = {"ok":ok,"checks":checks,"input_validation":input_validation,"final_validation":final_validation,"first_automatic_quotes":first_quotes,"all_automatic_quotes":probe.automatic_quotes.duplicate(true),"quotes_before_stable_hold":quote_count_before_hold,"quotes_after_stable_hold":quote_count_after_hold,"wait_cache_hits_before_move":retained_wait_hits,"move_reason":move_reason,"body":body,"fixed_footprint":original_fixed,"old_visitor_regions":original_regions,"initial_bystander_rect":original_bystander_rect,"final_bystander_rect":_rect_record(x.space.body_rectangle(bystander)),"clear_tick":clear_tick,"yield_tick":yield_tick,"patient_seated_tick":seated_tick,"initial_patient_intent":initial_intent,"final_patient_intent":x.world.facts.waiting_life.seats.get(patient.id,{}).duplicate(true),"after_actual_exit_complete_quote":after_exit_quote,"visitor":visitor.duplicate(true),"moves":x.world.facts.moves.duplicate(true)}
	_dispose(x)
	return result
