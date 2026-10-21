extends "res://tests/acceptance/public_area_use.gd"

# Observe work; eligibility, geometry, routes, actual movement and commit remain
# the production implementation rather than substitutes returning success.
class WaitingWorkProbe extends HospitalWaitingLife:
	var quotes: int = 0
	var scores: int = 0
	var quoted_facilities: Dictionary = {}
	func _facility_quote_in_query(world: WorldState, visit: Dictionary, facility_id: String) -> Dictionary:
		quotes += 1
		quoted_facilities[facility_id] = int(quoted_facilities.get(facility_id,0))+1
		return super._facility_quote_in_query(world,visit,facility_id)
	func _score_seat(world: WorldState, visit: Dictionary, facility_id: String, quote: Dictionary, observation: Dictionary, actor_index: Variant = null) -> Dictionary:
		scores += 1
		return super._score_seat(world,visit,facility_id,quote,observation,actor_index)

# A cold-current calculation reference: identical rules, with an explicit
# forced physical index refresh at every regional choice.
class FreshEntryAreas extends HospitalPublicAreas:
	func select(world: WorldState, actor_id: String, definitions: Array, room_kinds: Array, purpose: String, members: Array = [], maximum_travel_ticks: int = 9223372036854775807, selected_entries: Dictionary = {}) -> Dictionary:
		space.begin_dynamic_route_query(world,true)
		var result: Dictionary = super.select(world,actor_id,definitions,room_kinds,purpose,members,maximum_travel_ticks,selected_entries)
		space.end_route_query()
		return result

func _observe_waiting(x: Dictionary) -> WaitingWorkProbe:
	var probe: WaitingWorkProbe = WaitingWorkProbe.new(_content,x.space)
	probe.environment = x.e
	probe.visitors = x.c.visitors
	x.l = probe
	x.p.waiting_life = probe
	return probe

func _occupied_west() -> Dictionary:
	var x: Dictionary = _areas()
	var holder: Dictionary = _visit(x,"holder",[36,70])
	var waiter: Dictionary = _visit(x,"waiter",[40,74])
	var held: bool = _seat_checkpoint(x,holder,"west_chair")
	var probe: WaitingWorkProbe = _observe_waiting(x)
	x.world.facts.sim_tick = 50
	x.l.dispatch(x.world)
	x.holder = holder
	x.waiter = waiter
	x.held = held
	x.probe = probe
	return x

func _case_69(t) -> void:
	var connector_basis: Dictionary = _connector_wait_basis()
	var snapshot: Dictionary = _wait_value_snapshot()
	var samples: Dictionary = _complete_environment_samples()
	var qualifications: Dictionary = preload("res://tests/acceptance/public_queue_fit_lifecycle.gd").new().run_case(self)
	var membership: Dictionary = preload("res://tests/acceptance/public_facility_membership.gd").new().run_case(self)
	var dependencies: Dictionary = preload("res://tests/acceptance/public_wait_dependency_queries.gd").new().run_case(self)
	var x: Dictionary = _occupied_west()
	var intent: Dictionary = x.world.facts.waiting_life.seats.get(x.waiter.id,{})
	var arrived: bool = intent.get("phase","")=="local_wait" and int(intent.get("arrived_tick",-1))==50
	var queued_at: int = int(intent.get("arrived_tick",-1))
	var quotes: int = x.probe.quotes
	var scores: int = x.probe.scores
	_tick_waiting(x,5)
	var unchanged: bool = x.probe.quotes==quotes and x.probe.scores==scores and int(intent.get("arrived_tick",-1))==queued_at
	var unrelated: Dictionary = _visit(x,"other_area",[51,74])
	var other_move: String = x.space.request_move(x.world,unrelated.actor_id,1,[53,75])
	_tick_waiting(x,5)
	var local_dependencies: bool = x.probe.quotes==quotes and x.probe.scores==scores and intent.get("phase","")=="local_wait"
	x.l.execute(x.world,"waiting_release_seat",{"visit_id":x.holder.id})
	x.c.execute(x.world,"clinical_refer",{"visit_id":x.holder.id})
	var release_move: String = x.space.request_move(x.world,x.holder.actor_id,1,[40,76])
	var seated: bool = _until_seated(x,x.waiter)
	var timely: bool = seated and intent.get("facility_id","")=="west_chair" and int(intent.get("arrived_tick",-1))==queued_at and not x.space.overlaps_facility(x.world,x.holder.actor_id,"west_chair")
	t.check("STAFF-69",membership.ok and dependencies.ok and qualifications.ok and snapshot.ok and samples.ok and connector_basis.ok and x.held and arrived and unchanged and other_move.is_empty() and local_dependencies and release_move.is_empty() and timely and x.l.validate(x.world).is_empty(),{"static_facility_membership":membership,"wait_dependency_queries":dependencies,"queue_qualification_lifecycle":qualifications,"immutable_wait_basis":snapshot,"complete_environment_dependencies":samples,"connector_dependency_boundary":connector_basis,"arrived_waiting":arrived,"unchanged_wait_did_not_requote":unchanged,"unrelated_area_real_move":other_move,"unrelated_movement_did_not_requote":local_dependencies,"actual_holder_exit":release_move,"original_queue_time_kept":int(intent.get("arrived_tick",-1))==queued_at,"actually_seated_after_release":timely,"quotes_before":quotes,"quotes_after":x.probe.quotes,"intent":intent})

func _wait_value_snapshot() -> Dictionary:
	var x: Dictionary = _occupied_west()
	var intent: Dictionary = x.world.facts.waiting_life.seats[x.waiter.id]
	var extra: Dictionary = {"nested":{"values":[1,2]},"flag":true}
	var before: Dictionary = x.world.freeze()
	x.space.public_areas.remember_wait(x.world,intent,x.l.PUBLIC_SEAT_DEFINITIONS,[],extra)
	var initial: bool = not x.space.public_areas.should_recheck(x.world,intent,x.l.PUBLIC_SEAT_DEFINITIONS,[],extra)
	extra["nested"]["values"][0] = 3
	var changed: bool = x.space.public_areas.should_recheck(x.world,intent,x.l.PUBLIC_SEAT_DEFINITIONS,[],extra)
	extra["nested"]["values"][0] = 1
	var unchanged: bool = not x.space.public_areas.should_recheck(x.world,intent,x.l.PUBLIC_SEAT_DEFINITIONS,[],{"flag":true,"nested":{"values":[1,2]}})
	return {"ok":x.held and initial and changed and unchanged and before==x.world.freeze(),"initial_hit":initial,"nested_input_change_rechecked":changed,"retained_snapshot_not_aliased":unchanged,"world_and_rng_unchanged":before==x.world.freeze()}

func _complete_environment_samples() -> Dictionary:
	return preload("res://tests/acceptance/public_environment_view.gd").new().run_case(_content)

# This calculation boundary starts with a genuinely arrived negative result.
# The main case then independently exercises real release and use. Live lift
# queue and countdown changes cannot invalidate structural reachability, while
# a changed allowed direction or installed stop can do so without a layout edit.
func _connector_wait_basis() -> Dictionary:
	var x: Dictionary = _occupied_west()
	var plots: Array = HospitalSpace.floor_plots(x.world,1).duplicate(true)
	x.world.facts.floors.completed_top_floor = {}
	for plot: Array in plots: x.world.facts.floors.completed_top_floor[HospitalSpace.plot_key(plot)] = 2
	x.world.facts.floors.height_intervals = [{"first":1,"last":2,"height_m":float(_content.balance.floors.clear_height_m)}]
	x.world.facts.floors.overrides["2"] = {"plots":plots,"blocked":[],"doors":[],"paths":[]}
	x.world.facts.connectors.lift = {"id":"lift","definition_id":"VC02","stops":[1,2],"cell":[58,84],"footprint":[4,4],"rotation":0,"anchor":[59,88],"repair_cell":[57,85],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0,"ticket_next":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},"paid_cost":3200,"used":false}
	x.m.ensure(x.world)
	x.world.touch()
	x.l.dispatch(x.world)
	var intent: Dictionary = x.world.facts.waiting_life.seats[x.waiter.id]
	var basis: int = x.world.geometry_revision
	var before: Dictionary = x.world.freeze()
	x.space.public_areas.remember_wait(x.world,intent,x.l.PUBLIC_SEAT_DEFINITIONS)
	var unchanged: bool = not x.space.public_areas.should_recheck(x.world,intent,x.l.PUBLIC_SEAT_DEFINITIONS)
	var readonly: bool = before==x.world.freeze()
	var lift: Dictionary = x.world.facts.connectors.lift
	lift.phase = "empty_riding"
	lift.from = 1
	lift.to = 2
	lift.remaining_ticks = 40
	var normal_motion: bool = not x.space.public_areas.should_recheck(x.world,intent,x.l.PUBLIC_SEAT_DEFINITIONS)
	lift.remaining_ticks = 39
	var queue_visit: Dictionary = _visit(x,"lift_queue",[59,88])
	var request: String = x.space.request_move(x.world,queue_visit.actor_id,2,[59,88])
	HospitalTransit.begin(x.space,x.world,x.world.facts.actors[queue_visit.actor_id],x.world.facts.moves[queue_visit.actor_id],{"kind":"connector","connector_id":"lift","from":1,"to":2})
	var actual_ticket: bool = x.world.facts.moves[queue_visit.actor_id].has("transit_ticket")
	var queue_only: bool = not x.space.public_areas.should_recheck(x.world,intent,x.l.PUBLIC_SEAT_DEFINITIONS)
	lift.phase = "idle"
	lift.remaining_ticks = 0
	lift.pending_failure = true
	x.world.touch(false)
	var direction_changed: bool = x.space.public_areas.should_recheck(x.world,intent,x.l.PUBLIC_SEAT_DEFINITIONS)
	x.space.public_areas.remember_wait(x.world,intent,x.l.PUBLIC_SEAT_DEFINITIONS)
	lift.pending_failure = false
	lift.failed = false
	x.world.touch(false)
	var repaired: bool = x.space.public_areas.should_recheck(x.world,intent,x.l.PUBLIC_SEAT_DEFINITIONS)
	x.space.public_areas.remember_wait(x.world,intent,x.l.PUBLIC_SEAT_DEFINITIONS)
	var queue_cancelled: bool = x.space.cancel_ground_move(x.world,queue_visit.actor_id)
	var cancelled_queue_only: bool = not x.space.public_areas.should_recheck(x.world,intent,x.l.PUBLIC_SEAT_DEFINITIONS)
	var before_stop_removal: Dictionary = x.space.route_cost(x.world,queue_visit.actor_id,2,[59,88])
	lift.stops = [1]
	x.world.touch(false)
	var stops_changed: bool = x.space.public_areas.should_recheck(x.world,intent,x.l.PUBLIC_SEAT_DEFINITIONS)
	var after_stop_removal: Dictionary = x.space.route_cost(x.world,queue_visit.actor_id,2,[59,88])
	lift.stops = [1,2]
	x.world.touch(false)
	var after_stop_restore: Dictionary = x.space.route_cost(x.world,queue_visit.actor_id,2,[59,88])
	var live_topology: bool = before_stop_removal.ok and not after_stop_removal.ok and after_stop_removal.get("status","")=="unreachable" and after_stop_restore.ok
	lift.stops = [1]
	x.world.touch(false)
	var no_layout_edit: bool = x.world.geometry_revision==basis
	x.space.public_areas.remember_wait(x.world,intent,x.l.PUBLIC_SEAT_DEFINITIONS)
	# Floor 2 is now empty and has no installed connection to this waiting area.
	# Its layout edit must not invalidate this floor's unchanged negative result.
	x.world.facts.floors.overrides["2"].blocked.append([40,90])
	x.world.touch()
	var unrelated_floor: bool = not x.space.public_areas.should_recheck(x.world,intent,x.l.PUBLIC_SEAT_DEFINITIONS)
	x.space.public_areas.remember_wait(x.world,intent,x.l.PUBLIC_SEAT_DEFINITIONS)
	x.world.facts.floors.overrides["1"].blocked.append([42,75])
	x.world.touch()
	var local_geometry: bool = x.space.public_areas.should_recheck(x.world,intent,x.l.PUBLIC_SEAT_DEFINITIONS)
	return {"ok":unchanged and readonly and normal_motion and request.is_empty() and actual_ticket and queue_only and direction_changed and repaired and queue_cancelled and cancelled_queue_only and stops_changed and no_layout_edit and unrelated_floor and local_geometry and live_topology,"unchanged_negative_hit":unchanged,"cache_queries_readonly":readonly,"normal_phase_and_countdown_hit":normal_motion,"real_arrived_transit_ticket":actual_ticket,"queue_only_hit":queue_only,"lowering_direction_rechecked":direction_changed,"repair_without_geometry_rechecked":repaired,"queue_cancelled_before_stop_removal":queue_cancelled,"queue_cancellation_only_hit":cancelled_queue_only,"installed_stop_rechecked":stops_changed,"connection_changes_without_geometry_revision":no_layout_edit,"unconnected_empty_floor_edit_hit":unrelated_floor,"current_area_geometry_rechecked":local_geometry,"hot_topology_observes_stop_remove_and_restore":live_topology,"route_before_removal":before_stop_removal,"route_after_removal":after_stop_removal,"route_after_restore":after_stop_restore}

func _case_70(t) -> void:
	var manual_recreation: Dictionary = _manual_recreation_batch()
	var outside_recreation: Dictionary = _manual_recreation_batch(true)
	var x: Dictionary = _areas()
	_facility(x,"west_second","FUR09",[40,70],"west")
	x.world.touch()
	var visit: Dictionary = _visit(x,"chosen",[39,75])
	var probe: WaitingWorkProbe = _observe_waiting(x)
	x.world.facts.sim_tick = 50
	x.l.dispatch(x.world)
	var intent: Dictionary = x.world.facts.waiting_life.seats.get(visit.id,{})
	var target: String = str(intent.get("facility_id",""))
	var selected: bool = intent.get("phase","")=="local_travel" and not target.is_empty() and x.world.facts.moves.has(visit.actor_id) and x.world.facts.adaptations.is_empty()
	var quotes: int = probe.quotes
	var scores: int = probe.scores
	var quoted_before: Dictionary = probe.quoted_facilities.duplicate()
	var seated: bool = _until_seated(x,visit)
	var no_other_quotes: bool = true
	for id: String in probe.quoted_facilities:
		if id!=target: no_other_quotes = no_other_quotes and int(probe.quoted_facilities[id])==int(quoted_before.get(id,0))
	# The chosen object still needs a current atomic fit/ownership check. Only
	# reconsidering unrelated alternatives and ranking the whole area is rejected.
	var no_reselection: bool = seated and intent.facility_id==target and no_other_quotes and probe.scores==scores
	var manual: Dictionary = _areas()
	var manual_visit: Dictionary = _visit(manual,"specified",[40,75])
	var manual_probe: WaitingWorkProbe = _observe_waiting(manual)
	var specified: CommandResult = manual.l.execute(manual.world,"waiting_select_seat",{"visit_id":manual_visit.id,"facility_id":"east_chair"})
	var no_manual_ranking: bool = specified.accepted and manual_probe.scores==0
	var manual_seated: bool = _until_seated(manual,manual_visit)
	no_manual_ranking = no_manual_ranking and manual_probe.scores==0 and manual.world.facts.waiting_life.seats.get(manual_visit.id,{}).get("facility_id","")=="east_chair"
	t.check("STAFF-70",manual_recreation.ok and outside_recreation.ok and selected and no_reselection and manual_seated and no_manual_ranking,{"manual_recreation_single_readonly_batch":manual_recreation,"manual_recreation_from_other_area":outside_recreation,"unreserved_local_target":selected,"target":target,"actual_target_taken_without_reranking":no_reselection,"other_candidates_not_requoted":no_other_quotes,"quotes_at_departure":quotes,"quotes_after_arrival":probe.quotes,"scores_at_departure":scores,"scores_after_arrival":probe.scores,"manual_request":specified.to_record(),"manual_actual_seating":manual_seated,"manual_score_calls":manual_probe.scores})

func _manual_recreation_batch(outside: bool = false) -> Dictionary:
	var x: Dictionary = _areas({"first":"doctor","second":"nurse"})
	_facility(x,"specified_game","RC03",[36,71],"west")
	x.world.touch()
	_position(x,"first",[51,75] if outside else [38,75])
	_position(x,"second",[53,76] if outside else [40,76])
	for staff: Dictionary in x.world.facts.staff.values():
		staff.energy = 60.0
		staff.stress_milli = 50000
		staff.on_shift = false
	var before: int = int(x.space.query_counts.routes)
	var request: CommandResult = x.w.execute(x.world,"staff_recreation",{"staff_ids":["first","second"],"facility_id":"specified_game"})
	var queries: int = int(x.space.query_counts.routes)-before
	var no_early_use: bool = x.world.facts.staff_life.reservations.is_empty() and x.world.facts.staff.first.recreation_count==0 and x.world.facts.staff.second.recreation_count==0
	var started: bool = _reach_life_phase(x,"first","recreation")
	var together: bool = started and x.world.facts.staff.second.life_task.phase=="recreation" and x.world.facts.staff.first.life_task.facility_id=="specified_game" and x.world.facts.staff.second.life_task.facility_id=="specified_game" and x.world.facts.staff.first.recreation_count==1 and x.world.facts.staff.second.recreation_count==1
	return {"ok":request.accepted and queries==2 and no_early_use and together,"request":request.to_record(),"two_members_one_initial_route_each":queries==2,"initial_route_queries":queries,"no_remote_occupancy_or_counts":no_early_use,"all_members_actually_started_specified_equipment":together,"first_actor":x.world.facts.actors.first.duplicate(true),"second_actor":x.world.facts.actors.second.duplicate(true),"remaining_movements":x.world.facts.moves.duplicate(true)}

func _case_71(t) -> void:
	var observations: Array = []
	for purpose: String in ["rest","recreation"]:
		var x: Dictionary = _areas({"a_earlier":"doctor","z_later":"nurse"})
		_facility(x,"a_choice","FUR52" if purpose=="rest" else "RC01",[36,71],"west")
		_facility(x,"b_choice","FUR52" if purpose=="rest" else "RC01",[40,71],"west")
		x.world.touch()
		_position(x,"a_earlier",[38,75])
		# Both prefer A before queue eligibility; B remains independently usable.
		_position(x,"z_later",[36,76])
		for staff: Dictionary in x.world.facts.staff.values():
			staff.on_shift = false
			staff.energy = 35.0 if purpose=="rest" else 60.0
			staff.stress_milli = 50000
		var accepted: bool = true
		if purpose=="rest": x.w._begin(x.world,"a_earlier","rest")
		else: accepted = x.w.execute(x.world,"staff_recreation",{"staff_id":"a_earlier","facility_id":"a_choice"}).accepted
		var first: Dictionary = x.world.facts.staff.a_earlier.life_task
		var first_target: String = str(first.get("facility_id",""))
		var first_en_route: bool = first.get("phase","")=="local_travel" and not first_target.is_empty() and x.world.facts.moves.has("a_earlier")
		x.world.facts.sim_tick += 1
		if purpose=="rest": x.w._begin(x.world,"z_later","rest")
		else: accepted = accepted and x.w.execute(x.world,"staff_recreation",{"staff_id":"z_later"}).accepted
		var second: Dictionary = x.world.facts.staff.z_later.life_task
		var other_target: String = str(second.get("facility_id",""))
		var parallel: bool = second.get("phase","")=="local_travel" and not other_target.is_empty() and other_target!=first_target and x.world.facts.moves.has("z_later") and x.world.facts.staff_life.reservations.is_empty()
		var working: bool = _reach_life_phase(x,"z_later","rest" if purpose=="rest" else "recreation")
		var actual: bool = working and x.world.facts.staff.z_later.life_task.facility_id==other_target and x.world.facts.staff_life.reservations.has(other_target)
		var people: Dictionary = {}
		for id: String in ["a_earlier","z_later"]:
			var actor: Dictionary = x.world.facts.actors[id]
			var movement: Dictionary = x.world.facts.moves.get(id,{})
			var pending: Dictionary = {}
			for field: String in ["target_floor","target_cell","cursor","blocked_since","waiting_reason","route_pending","route_retry_tick","yielding","yield_to","request_sequence"]:
				if movement.has(field): pending[field] = movement[field]
			if not movement.is_empty(): pending.path = movement.get("path",[]).slice(maxi(0,int(movement.get("cursor",0))),maxi(0,int(movement.get("cursor",0)))+6)
			people[id] = {"location":actor.location.duplicate(true),"body":x.space.body(actor),"posture":actor.get("posture",""),"life_task":x.world.facts.staff[id].life_task.duplicate(true),"reason":x.world.facts.staff[id].life_reason,"movement":pending,"failure":x.space.movement_failure(x.world,id)}
		var current_fit: Dictionary = x.space.facility_quote(x.world,other_target,"z_later") if not other_target.is_empty() else {}
		var current_turn: bool = not other_target.is_empty() and x.space.public_areas.turn(x.world,second,other_target)
		observations.append({"purpose":purpose,"accepted":accepted,"earlier_walks_to_one_target":first_en_route,"first_target":first_target,"later_walks_to_another_target":parallel,"other_target":other_target,"actually_started_other_facility":actual,"tick":x.world.sim_tick,"people":people,"current_fit":current_fit,"current_turn":current_turn,"adaptations":x.world.facts.adaptations.duplicate(true),"reservations":x.world.facts.staff_life.reservations.duplicate(true)})
	t.check("STAFF-71",observations.all(func(row: Dictionary)->bool: return row.accepted and row.earlier_walks_to_one_target and row.later_walks_to_another_target and row.actually_started_other_facility),{"independent_available_targets":observations})

func _case_72(t) -> void:
	var x: Dictionary = _occupied_west()
	var intent: Dictionary = x.world.facts.waiting_life.seats.get(x.waiter.id,{})
	var started: int = int(intent.get("started_tick",-1))
	x.world.facts.rooms.west.kind = "rest"
	x.world.facts.rooms.west.type = "rest"
	x.world.touch()
	x.l.dispatch(x.world)
	intent = x.world.facts.waiting_life.seats.get(x.waiter.id,{})
	var reselected: bool = intent.get("area",{}).get("room_id","")=="east" and int(intent.get("started_tick",-1))==started and intent.get("facility_id","")==""
	var y: Dictionary = _areas()
	_facility(y,"toilet","FUR07",[39,68],"west")
	y.world.touch()
	var visit: Dictionary = _visit(y,"expired_route",[38,90])
	y.world.facts.sim_tick = 1800
	y.l._begin_need(y.world,visit)
	var need: Dictionary = y.world.facts.waiting_life.needs.get(visit.id,{})
	var original: int = int(need.get("started_tick",-1))
	var requested: bool = y.world.facts.moves.has(visit.actor_id) and y.world.facts.actors[visit.actor_id].location.kind=="floor"
	# A layout change closes the door after the real movement request, while
	# the actor remains outside on the ground. A pending failed route cannot
	# hide the original deadline or grant service at a distant facility.
	for door: Dictionary in y.world.facts.floors.overrides["1"].doors:
		if door.get("room_id","")=="west":
			for offset: int in int(door.span):
				var blocked: Array = [int(door.cell[0])+(offset if door.axis=="x" else 0),int(door.cell[1])+(offset if door.axis=="y" else 0)]
				if not blocked in y.world.facts.floors.overrides["1"].blocked: y.world.facts.floors.overrides["1"].blocked.append(blocked)
	y.world.touch()
	y.world.facts.sim_tick = original+451
	y.space.advance(y.world)
	y.l.dispatch(y.world)
	var safe_timeout: bool = need.get("phase","")=="fallback" and need.get("remaining_ticks",-1)==80 and need.get("facility_id","")=="" and not y.world.facts.moves.has(visit.actor_id) and y.world.facts.actors[visit.actor_id].location.kind=="floor" and int(need.get("started_tick",-1))==original
	t.check("STAFF-72",x.held and reselected and requested and safe_timeout,{"purpose_changed_reselected_area":reselected,"original_start_kept":int(intent.get("started_tick",-1))==started,"real_route_requested_before_change":requested,"ground_route_cannot_hide_original_deadline":safe_timeout,"need":need,"remaining_move":y.world.facts.moves.get(visit.actor_id,{})})

# Assignment is a calculation boundary, not a sleep or elevator-completion
# fixture. The descending-only fault supplies an independent one-way example.
func _case_73(t) -> void:
	var x: Dictionary = _areas({"owner":"doctor"})
	_facility(x,"personal_bed","SE04",[39,71],"west")
	var plots: Array = HospitalSpace.floor_plots(x.world,1).duplicate(true)
	x.world.facts.floors.completed_top_floor = {}
	for plot: Array in plots: x.world.facts.floors.completed_top_floor[HospitalSpace.plot_key(plot)] = 2
	x.world.facts.floors.height_intervals = [{"first":1,"last":2,"height_m":float(_content.balance.floors.clear_height_m)}]
	x.world.facts.floors.overrides["2"] = {"plots":plots,"blocked":[],"doors":[],"paths":[]}
	var origin: Array = [40,90]
	x.world.facts.actors.owner.location = {"kind":"floor","floor_id":2,"cell":origin.duplicate(),"height_m":0.0}
	x.world.facts.connectors.lift = {"id":"lift","definition_id":"VC02","first_floor":1,"last_floor":2,"cell":[58,84],"footprint":[4,4],"rotation":0,"anchor":[59,88],"repair_cell":[57,85],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0,"ticket_next":0,"condition":100.0,"failed":true,"pending_failure":false,"use_receipts":{},"paid_cost":3200,"used":false}
	x.world.touch()
	var target: Array = x.space.facility_layout(x.world,"personal_bed").patient_cell
	var source: Dictionary = x.world.freeze()
	var outward: Dictionary = x.space.route_cost(x.world,"owner",1,target)
	var preview: WorldState = WorldState.new(source.duplicate(true))
	preview.facts.actors.owner.location = {"kind":"floor","floor_id":1,"cell":target.duplicate(),"height_m":0.0}
	var back: Dictionary = HospitalSpace.new(_content).route_cost(preview,"owner",2,origin)
	var trip: Dictionary = x.space.facility_trip_quote(x.world,"personal_bed","owner")
	var readonly: bool = source==x.world.freeze()
	x.w.ensure(x.world)
	var refused: bool = x.w.personal_beds.bed_for(x.world,"owner").is_empty() and x.world.facts.staff_life.personal_beds.is_empty()
	x.world.facts.connectors.lift.failed = false
	x.world.touch(false)
	x.w.ensure(x.world)
	var assigned: bool = x.w.personal_beds.bed_for(x.world,"owner")=="personal_bed"
	var no_execution: bool = x.world.facts.moves.is_empty() and x.world.facts.adaptations.is_empty() and x.world.facts.actors.owner.location.floor_id==2 and x.world.facts.actors.owner.location.cell==origin
	t.check("STAFF-73",outward.get("ok",false) and not back.get("ok",true) and not trip.get("ok",true) and readonly and refused and assigned and no_execution,{"legal_outward_descent":outward.get("ok",false),"return_upward_refused":not back.get("ok",true),"personal_trip_requires_return":not trip.get("ok",true),"quote_readonly":readonly,"one_way_bed_not_assigned":refused,"bidirectional_bed_assigned":assigned,"assignment_did_not_move_or_reserve":no_execution,"owners":x.world.facts.staff_life.personal_beds})

# The elapsed seeking time is a legal precondition. The unsafe location, real
# safety trip after expiry and all eighty fallback work ticks are exercised.
func _case_74(t) -> void:
	var observations: Array = []
	for place: String in ["door","connector"]:
		var x: Dictionary = _areas()
		_facility(x,"toilet","FUR07",[39,68],"west")
		var start: Array = []
		if place=="door":
			for door: Dictionary in x.world.facts.floors.overrides["1"].doors:
				if door.room_id=="west": start = door.cell.duplicate()
		else:
			start = [59,88]
			x.world.facts.connectors.lift = {"id":"lift","definition_id":"VC02","first_floor":1,"last_floor":1,"cell":[58,84],"footprint":[4,4],"rotation":0,"anchor":start.duplicate(),"repair_cell":[57,85],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0,"ticket_next":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},"paid_cost":3200,"used":false}
		x.world.touch()
		# Connectors are maintained equipment. Build the complete legal input
		# before saving rather than making restore supply missing defaults.
		var connector_before: Dictionary = x.world.facts.connectors.get("lift",{}).duplicate(true)
		x.m.ensure(x.world)
		var normalized_fields: Array = []
		for field: String in x.world.facts.connectors.get("lift",{}):
			if not connector_before.has(field): normalized_fields.append(field)
		var visit: Dictionary = _visit(x,"unsafe_"+place,start)
		x.world.facts.sim_tick = 1800
		var unsafe: bool = not start.is_empty() and not x.space.public_areas.safe_wait(x.world,visit.actor_id,1,start)
		x.l._begin_need(x.world,visit)
		var need: Dictionary = x.world.facts.waiting_life.needs.get(visit.id,{})
		var original_start: int = int(need.get("started_tick",-1))
		var initial_trip: bool = x.world.facts.moves.has(visit.actor_id)
		var anger: float = float(visit.anger)
		x.world.facts.sim_tick = original_start+451
		x.l.dispatch(x.world)
		var safety_move: Dictionary = x.world.facts.moves.get(visit.actor_id,{})
		var target: Array = safety_move.get("target_cell",[]).duplicate()
		var safe_departure: bool = need.get("phase","")=="fallback_travel" and not safety_move.is_empty() and not target.is_empty() and target!=start and need.get("remaining_ticks",-1)==0 and need.get("started_tick",-1)==original_start and visit.anger==anger and x.world.facts.actors[visit.actor_id].location.cell==start
		var saved: Dictionary = x.world.freeze()
		x = _restore(x)
		visit = x.world.facts.visits[visit.id]
		need = x.world.facts.waiting_life.needs[visit.id]
		var after_restore: Dictionary = x.world.freeze()
		var changed_fields: Array = []
		for field: String in saved:
			if saved[field]!=after_restore.get(field): changed_fields.append(field)
		var restored: bool = after_restore==saved and need.phase=="fallback_travel" and need.started_tick==original_start and x.world.facts.moves.get(visit.actor_id,{}).get("target_cell",[])==target
		var no_early_work: bool = true
		var arrived: bool = false
		for _tick: int in 300:
			x.world.facts.sim_tick += 1
			x.c.visitors.dispatch(x.world)
			x.l.dispatch(x.world)
			if need.phase=="fallback":
				arrived = x.space.public_areas.safe_wait(x.world,visit.actor_id,int(x.world.facts.actors[visit.actor_id].location.floor_id),x.world.facts.actors[visit.actor_id].location.cell) and not x.world.facts.moves.has(visit.actor_id) and need.remaining_ticks==80 and need.started_tick==original_start and x.space.at(x.world,visit.actor_id,1,target)
				break
			no_early_work = no_early_work and need.phase=="fallback_travel" and need.remaining_ticks==0 and visit.anger==anger and need.started_tick==original_start
			x.space.advance(x.world)
			x.l.advance(x.world)
			x.world.touch(false)
		var work_complete: bool = false
		if arrived:
			_tick_waiting(x,79)
			var before_last: bool = need.phase=="fallback" and need.remaining_ticks==1 and visit.anger==anger
			_tick_waiting(x)
			work_complete = before_last and need.phase=="returning" and is_equal_approx(float(visit.anger),anger+float(_content.balance.amenity_flow.fallback_anger))
		observations.append({"place":place,"unsafe_initial_location":unsafe,"formal_original_trip":initial_trip,"expired_need_moves_to_safety_without_work":safe_departure,"saved_trip_identity_and_clock":restored,"normalized_input_fields":normalized_fields,"restore_changed_fields":changed_fields,"no_work_or_effect_before_safe_arrival":no_early_work,"actual_safe_arrival_starts_eighty_ticks":arrived,"eight_seconds_actually_completed":work_complete,"original_started_tick":original_start,"target":target,"actor":x.world.facts.actors[visit.actor_id].duplicate(true),"need":need.duplicate(true),"movement":x.world.facts.moves.get(visit.actor_id,{}).duplicate(true)})
	t.check("STAFF-74",observations.all(func(row: Dictionary)->bool: return row.unsafe_initial_location and row.formal_original_trip and row.expired_need_moves_to_safety_without_work and row.saved_trip_identity_and_clock and row.no_work_or_effect_before_safe_arrival and row.actual_safe_arrival_starts_eighty_ticks and row.eight_seconds_actually_completed),{"safe_fallback_after_expiry":observations})

# Candidate computation boundaries. The rectangle is the literal room input,
# not a candidate list produced by the optimized entry sorter. Physical people
# are inputs here; STAFF-45 exercises the resulting real arrival and use.
func _case_75(t) -> void:
	var large_estimate: Dictionary = _large_entry_estimate()
	var scan_batch: Dictionary = _scan_index_batch()
	var ordering: Dictionary = _entry_order_reuse()
	var prepared: Dictionary = preload("res://tests/acceptance/public_entry_order_reuse.gd").new().run_case(self)
	var regions: Dictionary = preload("res://tests/acceptance/public_region_build.gd").new().run_case(_content)
	var lifecycle: Dictionary = preload("res://tests/acceptance/public_region_lifecycle.gd").new().run_case(_content)
	var refresh: Dictionary = preload("res://tests/acceptance/public_region_refresh_and_doors.gd").new().run_case(_content)
	var observations: Array = []
	for variant: String in ["ordinary","fractional","nearest_body_occupied","only_far_point_free"]:
		var x: Dictionary = _areas()
		var visit: Dictionary = _visit(x,"entry_subject",[38.35,90.35] if variant=="fractional" else [38,90])
		var area: Dictionary = x.space.public_areas.for_facility(x.world,"west_chair")
		var original: Dictionary = _complete_entry_reference(x,visit,1)
		var blocked_cell: Array = []
		var retained_far: Array = []
		if variant=="nearest_body_occupied" and not original.best.is_empty():
			blocked_cell = original.best.cell.duplicate()
			var blocker: Dictionary = _visit(x,"entry_blocker",blocked_cell)
			x.space.sync_actor(x.world,blocker.actor_id)
			x.world.touch(false)
		elif variant=="only_far_point_free" and not original.rows.is_empty():
			var far: Dictionary = original.rows[0]
			for row: Dictionary in original.rows:
				if _entry_order_before(far,row): far = row
			retained_far = far.cell.duplicate()
			var index: int = 0
			for row: Dictionary in original.rows:
				if row.cell==retained_far: continue
				var blocker: Dictionary = _visit(x,"packed_%03d"%index,row.cell)
				x.space.sync_actor(x.world,blocker.actor_id)
				index += 1
			x.world.touch(false)
		var before: Dictionary = x.world.freeze()
		var validation: String = x.world.validate(_content)
		var expected: Dictionary = _complete_entry_reference(x,visit,1)
		var routes_before: int = int(x.space.query_counts.routes)
		var started: int = Time.get_ticks_usec()
		var actual: Dictionary = x.space.public_areas.waiting_point(x.world,visit.actor_id,area)
		var elapsed: int = Time.get_ticks_usec()-started
		var route_queries: int = int(x.space.query_counts.routes)-routes_before
		var same: bool = not expected.best.is_empty() and actual==_entry_result(expected.best,1)
		var blocked_rejected: bool = blocked_cell.is_empty() or actual.get("cell",[])!=blocked_cell
		var stable_tie_exercised: bool = variant!="nearest_body_occupied" or int(expected.order_ties)>1
		var far_retained: bool = retained_far.is_empty() or expected.rows.size()==1 and actual.get("cell",[])==retained_far and original.rows.size()>32
		var readonly: bool = before==x.world.freeze()
		observations.append({"variant":variant,"ok":validation.is_empty() and original.readonly and expected.readonly and same and blocked_rejected and stable_tie_exercised and far_retained and readonly,"validation":validation,"literal_rectangle_cells":120,"original_safe_complete_candidates":original.rows.size(),"current_safe_complete_candidates":expected.rows.size(),"minimum_cost_ties":expected.cost_ties,"minimum_cost_and_lower_ties":expected.order_ties,"expected":_entry_result(expected.best,1),"actual":actual,"same_point_cost_and_stable_order":same,"occupied_nearest_rejected":blocked_rejected,"stable_tie_exercised":stable_tie_exercised,"far_unique_candidate_retained":far_retained,"readonly":readonly,"route_queries":route_queries,"waiting_point_us":elapsed})
	t.check("STAFF-75",prepared.ok and large_estimate.ok and scan_batch.ok and ordering.ok and regions.ok and lifecycle.ok and refresh.ok and observations.all(func(row: Dictionary)->bool: return row.ok),{"complete_entry_boundaries":observations,"large_finite_estimate":large_estimate,"physical_index_scan_batch":scan_batch,"shared_entry_order":ordering,"prepared_entry_order":prepared,"complete_region_build":regions,"region_lifecycle":lifecycle,"region_refresh_and_door_broadphase":refresh})

func _entry_order_reuse() -> Dictionary:
	var x: Dictionary = _areas()
	var visit: Dictionary = _visit(x,"order_subject",[38,90])
	var actor: Dictionary = x.world.facts.actors[visit.actor_id]
	var geometry: Dictionary = {"cells":[Vector2i(42,76),Vector2i(41,75),Vector2i(40,75),Vector2i(40,74)],"points":{},"ordering":{}}
	var before: Dictionary = x.world.freeze()
	var cases: Array = [
		{"origin":Vector2(38,90),"bounds":{"landings":[{"cell":Vector2(40,75),"ticks":50},{"cell":Vector2(43,75),"ticks":57}],"unknown":false},"limit":1000,"hit":false},
		{"origin":Vector2(30.25,80.25),"bounds":{"landings":[{"cell":Vector2(40,75),"ticks":91},{"cell":Vector2(43,75),"ticks":98}],"unknown":false},"limit":96,"hit":true},
		{"origin":Vector2(30.25,80.25),"bounds":{"landings":[{"cell":Vector2(40,75),"ticks":91},{"cell":Vector2(43,75),"ticks":99}],"unknown":false},"limit":1000,"hit":false},
		{"origin":Vector2(38.1,90.1),"bounds":{"landings":[{"cell":Vector2(40,75),"ticks":91}],"unknown":true},"limit":1000,"hit":false},
		{"origin":Vector2(38.2,90.2),"bounds":{"landings":[],"unknown":false},"limit":1000,"hit":true},
		{"origin":Vector2(39,90),"bounds":{"landings":[],"unknown":false},"limit":1000,"hit":false}
	]
	var rows: Array = []
	for item: Dictionary in cases:
		var expected: Array = []
		var start: Vector2i = Vector2i(roundi(item.origin.x),roundi(item.origin.y))
		var stub: int = ceili(item.origin.distance_to(Vector2(start))/2.0/WorldState.TICK_SECONDS)
		for point: Vector2i in geometry.cells:
			# Published S49 rate is 2 cells/s: integer orthogonal cells cost
			# five ticks each. Fractional walking retains its separate ceil.
			var lower: int = stub+5*(absi(start.x-point.x)+absi(start.y-point.y))
			if not item.bounds.unknown and not item.bounds.landings.is_empty():
				lower = HospitalTransit.MAX_TICK
				for landing: Dictionary in item.bounds.landings:
					lower = mini(lower,int(landing.ticks)+5*(absi(int(landing.cell.x)-point.x)+absi(int(landing.cell.y)-point.y)))
			if lower<=item.limit: expected.append({"cell":point,"lower":lower})
		expected.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a.lower<b.lower or a.lower==b.lower and (a.cell.y<b.cell.y or a.cell.y==b.cell.y and a.cell.x<b.cell.x))
		var hits: int = int(x.space.query_counts.get("entry_order_hits",0))
		var actual_order: Dictionary = x.space.public_areas._entry_order(actor,item.origin,item.bounds,geometry,item.limit)
		var actual: Array = []
		for key: int in actual_order.packed:
			var lower: int = key/HospitalPublicAreas.ENTRY_CELL_COUNT+int(actual_order.get("offset_ticks",0))
			if lower>item.limit: break
			var cell_id: int = key%HospitalPublicAreas.ENTRY_CELL_COUNT
			actual.append({"cell":Vector2i(cell_id%96,cell_id/96),"lower":lower})
		var reused: bool = int(x.space.query_counts.get("entry_order_hits",0))==hits+1
		rows.append({"ok":actual==expected and reused==bool(item.hit),"expected":expected,"actual":actual,"expected_reuse":item.hit,"actual_reuse":reused})
	return {"ok":rows.all(func(row: Dictionary)->bool: return row.ok) and before==x.world.freeze(),"literal_complete_candidates_and_budget":rows,"world_and_rng_unchanged":before==x.world.freeze()}

func _scan_index_batch() -> Dictionary:
	var x: Dictionary = _areas()
	var first: Dictionary = _visit(x,"batch_first",[38,90])
	var second: Dictionary = _visit(x,"batch_second",[53,90])
	x.world.facts.sim_tick = 50
	x.space._ensure_actor_index(x.world)
	# A legal input can be prepared after the previous index boundary without
	# changing its revision. The first real scan must still refresh it.
	x.world.facts.actors[second.actor_id].location.cell = [52.25,90]
	var stale: bool = x.space._actor_index.rectangle(second.actor_id)!=x.space.body_rectangle(x.world.facts.actors[second.actor_id])
	var source: Dictionary = x.world.freeze()
	var cold: Dictionary = _bind(WorldState.new(source.duplicate(true)))
	cold.space.public_areas = FreshEntryAreas.new(cold.space)
	var before_builds: int = int(x.space.query_counts.actor_index_builds)
	x.l.dispatch(x.world)
	cold.l.dispatch(cold.world)
	var builds: int = int(x.space.query_counts.actor_index_builds)-before_builds
	var equal: bool = x.world.freeze()==cold.world.freeze()
	var both_selected: bool = x.world.facts.waiting_life.seats.has(first.id) and x.world.facts.waiting_life.seats.has(second.id)
	var actual_body: bool = x.space._actor_index.rectangle(second.actor_id)==x.space.body_rectangle(x.world.facts.actors[second.actor_id])
	var closed: bool = x.space._route_queries.is_empty() and x.space._indexed_actor_scope.is_empty()
	var before_idle: int = int(x.space.query_counts.actor_index_builds)
	x.l.dispatch(x.world)
	var no_empty_scan_refresh: bool = int(x.space.query_counts.actor_index_builds)==before_idle
	return {"ok":stale and equal and both_selected and actual_body and builds==1 and closed and no_empty_scan_refresh,"input_index_was_stale":stale,"same_facts_and_rng_as_forced_fresh_choices":equal,"both_actors_selected":both_selected,"first_scan_sees_current_body":actual_body,"full_index_builds_for_two_choices":builds,"all_query_scopes_released":closed,"no_extra_rebuild_without_new_scan":no_empty_scan_refresh}

# A finite route-cost input near int64's limit must remain sortable. This is
# only the numeric candidate boundary: no lift journey or arrival is fabricated.
func _large_entry_estimate() -> Dictionary:
	var x: Dictionary = _areas()
	var visit: Dictionary = _visit(x,"large_estimate",[38,90])
	var ticks: int = 9223372036854773807 # int64 maximum minus 2000.
	var bounds: Dictionary = {"landings":[{"cell":Vector2(40,75),"ticks":ticks}],"unknown":false}
	var geometry: Dictionary = {"cells":[Vector2i(42,76),Vector2i(41,75),Vector2i(40,75),Vector2i(40,74)],"points":{}}
	var original_geometry: Dictionary = geometry.duplicate(true)
	var original_bounds: Dictionary = bounds.duplicate(true)
	var before: Dictionary = x.world.freeze()
	var routes: int = int(x.space.query_counts.routes)
	var ordered: Dictionary = x.space.public_areas._ordered_entry_cells(x.world.facts.actors[visit.actor_id],Vector2(38,90),bounds,geometry,9223372036854775807)
	var shared: Dictionary = x.space.public_areas._entry_order(x.world.facts.actors[visit.actor_id],Vector2(38,90),bounds,geometry,9223372036854775807)
	# At the published 2 cells/s, zero, one and three orthogonal cells take
	# zero, five and fifteen ticks. Equal lower values compare y before x.
	var expected: Array = [{"cell":Vector2i(40,75),"lower":ticks},{"cell":Vector2i(40,74),"lower":ticks+5},{"cell":Vector2i(41,75),"lower":ticks+5},{"cell":Vector2i(42,76),"lower":ticks+15}]
	var exact: bool = not ordered.compact and ordered.packed.is_empty() and ordered.fallback==expected and not shared.compact and shared.packed.is_empty() and shared.fallback==expected
	var readonly: bool = before==x.world.freeze() and bounds==original_bounds and geometry==original_geometry and routes==int(x.space.query_counts.routes)
	return {"ok":exact and readonly,"all_finite_candidates_and_literal_order":exact,"input_and_world_unchanged_without_route_queries":readonly,"expected":expected,"actual":ordered.fallback}

func _entry_result(best: Dictionary, floor_id: int) -> Dictionary:
	return {} if best.is_empty() else {"floor_id":floor_id,"cell":best.cell.duplicate(),"travel_ticks":int(best.travel_ticks)}

func _entry_order_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a.lower)!=int(b.lower): return int(a.lower)<int(b.lower)
	return int(a.cell[1])<int(b.cell[1]) or a.cell[1]==b.cell[1] and int(a.cell[0])<int(b.cell[0])

func _complete_entry_reference(x: Dictionary, visit: Dictionary, floor_id: int) -> Dictionary:
	var before: Dictionary = x.world.freeze()
	var actor: Dictionary = x.world.facts.actors[visit.actor_id]
	var origin: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	var rounded: Vector2i = Vector2i(roundi(origin.x),roundi(origin.y))
	# S49's ordinary one-cell case uses the published 2 cells/s rate. Keep the
	# two original ceil operations separate, including the fractional stub.
	var speed: float = float(_content.balance.movement_speeds["1"])
	var stub: int = ceili(origin.distance_to(Vector2(rounded))/speed/WorldState.TICK_SECONDS)
	var rows: Array = []
	var best: Dictionary = {}
	# The west room was explicitly created at [34,66] with size [10,12].
	# Test every cell, allowing the real safety/route contracts to reject walls,
	# door margins, work positions, furniture and current physical occupants.
	x.space.begin_dynamic_route_query(x.world)
	for y: int in range(66,78):
		for px: int in range(34,44):
			var cell: Array = [px,y]
			if not x.space.public_areas.safe_wait(x.world,visit.actor_id,floor_id,cell): continue
			var complete: Dictionary = x.space.route(x.world,visit.actor_id,floor_id,cell,[],{},true)
			if not complete.get("ok",false) or not complete.has("travel_ticks"): continue
			var distance: int = absi(rounded.x-px)+absi(rounded.y-y)
			var row: Dictionary = {"cell":cell,"lower":stub+ceili(float(distance)/speed/WorldState.TICK_SECONDS),"travel_ticks":int(complete.travel_ticks)}
			rows.append(row)
			if best.is_empty() or row.travel_ticks<best.travel_ticks or row.travel_ticks==best.travel_ticks and _entry_order_before(row,best): best = row
	x.space.end_route_query()
	var cost_ties: int = 0
	var order_ties: int = 0
	for row: Dictionary in rows:
		if row.travel_ticks==best.travel_ticks:
			cost_ties += 1
			if row.lower==best.lower: order_ties += 1
	return {"rows":rows,"best":best,"cost_ties":cost_ties,"order_ties":order_ties,"readonly":before==x.world.freeze()}
