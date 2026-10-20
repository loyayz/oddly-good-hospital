extends RefCounted

func run_case(suite: RefCounted) -> Dictionary:
	var spatial: Dictionary = _spatial()
	var quotes: Dictionary = _quotes(suite)
	var trips: Dictionary = _trip_quotes(suite)
	var topology: Dictionary = preload("res://tests/acceptance/navigation_topology_projection.gd").new().run(suite)
	var static_versions: Dictionary = preload("res://tests/acceptance/navigation_static_versions.gd").new().run()
	var distance_fields: Dictionary = preload("res://tests/acceptance/navigation_distance_fields.gd").new().run(suite)
	var shapes: Dictionary = preload("res://tests/acceptance/build_geometry_components.gd").new().run()
	var matching: Dictionary = preload("res://tests/acceptance/bed_matching_boundaries.gd").new().run()
	var search: Dictionary = preload("res://tests/acceptance/route_search_boundaries.gd").new().run()
	var ready_reuse: Dictionary = _ready_support_exit(suite)
	var delayed_retarget: Dictionary = _delayed_retarget(suite)
	var delayed_cancel: Dictionary = _delayed_cancel(suite)
	var high_floors: Dictionary = _high_floor_topology(suite)
	var door_layers: Dictionary = _door_layers(suite)
	var group_door: Dictionary = _group_door(suite)
	var page_sizes: Dictionary = _pose_page_sizes()
	var groups: Array = []
	var ok: bool = spatial.ok and quotes.ok and trips.ok and topology.ok and static_versions.ok and distance_fields.ok and shapes.ok and matching.ok and search.ok and ready_reuse.ok and delayed_retarget.ok and delayed_cancel.ok and high_floors.ok and door_layers.ok and group_door.ok and page_sizes.ok
	for phase: String in ["pending","waiting","riding"]:
		var result: Dictionary = _group(suite,phase)
		groups.append(result)
		ok = ok and result.ok
	return {"ok":ok,"spatial":spatial,"quotes":quotes,"trip_quotes":trips,"projection_topology":topology,"static_versions":static_versions,"distance_fields":distance_fields,"shapes":shapes,"matching":matching,"search":search,"group_retargets":groups,"ready_support_exit":ready_reuse,"delayed_retarget":delayed_retarget,"delayed_cancel":delayed_cancel,"high_floor_topology":high_floors,"door_layers":door_layers,"group_door":group_door,"pose_page_sizes":page_sizes}

func _pose_page_sizes() -> Dictionary:
	var rows: Array = []
	var ok: bool = true
	for pair: Array in [[1,1],[2,2],[3,4],[64,64],[65,128],[120,128],[192,256]]:
		var actual: int = nearest_po2(int(pair[0]))
		ok = ok and actual==int(pair[1])
		rows.append({"required_texels":pair[0],"expected_page_extent":pair[1],"actual_page_extent":actual})
	return {"ok":ok,"literal_page_boundaries":rows}

func _ready_support_exit(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	# The queue is tested at the existing supported-body departure boundary.
	# Construct the bed and supported pose; do not simulate or assert sleep work.
	HospitalFactory._add_room(sim.world,{"id":"support_room","type":"rest","anchor":[34,66],"size":[12,12],"door":{"definition_id":"DR01","offset":4}},suite.content)
	HospitalFactory._add_facility(sim.world,{"id":"support_bed","definition_id":"SE04","anchor":[39,69],"size":[1,2],"room_id":"support_room"},suite.content)
	suite._add_staff(sim,"reused_ready","doctor",[44,82])
	var wellbeing: HospitalStaffWellbeing = HospitalStaffWellbeing.new(suite.content,sim.space)
	wellbeing.ensure(sim.world)
	var requested: String = sim.space.request_move(sim.world,"reused_ready",1,[44,85])
	var queued: bool = sim.world.facts.moves.get("reused_ready",{}).get("route_pending",false)
	sim.world.facts.moves.erase("reused_ready")
	var actor: Dictionary = sim.world.facts.actors.reused_ready
	actor.posture = "lying"
	actor.support_facility_id = "support_bed"
	actor.location = sim.space.support_location(sim.world,actor,sim.world.facts.facilities.support_bed)
	sim.world.facts.staff.reused_ready.sleep_remaining_ticks = 4500
	sim.world.facts.staff.reused_ready.life_task = {"kind":"sleep","phase":"returning","facility_id":"support_bed"}
	# Entity collections require String IDs; dot insertion creates StringName.
	sim.world.facts.staff_life.reservations["support_bed"] = {"kind":"sleep","staff_ids":[actor.id],"state":"releasing"}
	sim.world.touch()
	sim.space.sync_actor(sim.world,actor.id)
	var validation: String = wellbeing.validate(sim.world)
	var legal_support: bool = validation.is_empty()
	var bed_owner: Dictionary = sim.world.facts.staff_life.personal_beds.get("support_bed",{}).duplicate(true)
	var original_goal: Array = [44,74]
	var departure: String = sim.space.request_move(sim.world,actor.id,1,original_goal)
	var move_before: Dictionary = sim.world.facts.moves.get(actor.id,{}).duplicate(true)
	var location: Dictionary = actor.location.duplicate(true)
	sim.space.movement._dispatch_routes(sim.world,1)
	var retained: bool = sim.world.facts.moves.get(actor.id,{})==move_before and actor.location==location
	var support: bool = not move_before.has("request_sequence") and move_before.get("path",[]).size()==1 and move_before.path[0].kind=="support_exit"
	var cleared: bool = not sim.space.movement._pending_routes.has(actor.id)
	var exit_cell: Array = sim.space.facility_layout(sim.world,"support_bed").patient_cell.duplicate()
	# The new obstacle is beyond the supported body, at its real landing point.
	# A geometry change must stop departure before any position or height moves.
	sim.world.facts.floors.overrides["1"].blocked.append(exit_cell.duplicate())
	sim.world.touch()
	suite._movement_tick(sim)
	var blocked_move: Dictionary = sim.world.facts.moves.get(actor.id,{})
	var safely_waited: bool = actor.location==location and actor.posture=="lying" and actor.get("support_facility_id","")=="support_bed" and blocked_move.get("path",[])==move_before.path and int(blocked_move.get("cursor",-1))==0 and blocked_move.get("target_cell",[])==original_goal and not blocked_move.get("route_pending",false) and not str(blocked_move.get("waiting_reason","")).is_empty()
	sim.world.facts.floors.overrides["1"].blocked.erase(exit_cell)
	sim.world.touch()
	var stood_at_exit: bool = false
	var displaced: bool = false
	var bounded_steps: bool = true
	var waiting_cleared: bool = true
	var max_step: float = 0.0
	for tick: int in 400:
		var before_cell: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
		var permitted: float = float(suite.content.balance.movement_speeds[str(sim.space.clearance(actor))])*WorldState.TICK_SECONDS
		suite._movement_tick(sim)
		var after_cell: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
		var travelled: float = before_cell.distance_to(after_cell)
		max_step = maxf(max_step,travelled)
		# Vector2 positions use binary32 over the fixed 96-cell floor. Allow
		# representation rounding at the two endpoints, not an extra move tick.
		var position_rounding: float = 2.0*96.0*pow(2.0,-23.0)
		bounded_steps = bounded_steps and travelled<=permitted+position_rounding
		if travelled>0.00001:
			displaced = true
			waiting_cleared = waiting_cleared and not sim.world.facts.moves.get(actor.id,{}).has("waiting_reason")
		if actor.posture=="standing" and is_zero_approx(float(actor.location.height_m)) and not actor.has("support_facility_id") and sim.space.at(sim.world,actor.id,1,exit_cell): stood_at_exit = true
		if not sim.world.facts.moves.has(actor.id): break
	var continued: bool = stood_at_exit and not sim.world.facts.moves.has(actor.id) and sim.space.at(sim.world,actor.id,1,original_goal)
	sim.dispose()
	return {"ok":legal_support and requested.is_empty() and queued and departure.is_empty() and support and retained and cleared and safely_waited and displaced and bounded_steps and waiting_cleared and continued,"legal_personal_bed_departure":legal_support,"support_validation":validation,"personal_bed_owner":bed_owner,"support_exit_without_sequence":support,"departure_retained":retained,"cancelled_ready_removed":cleared,"new_obstacle_preserves_supported_body":safely_waited,"real_departure_after_clearance":displaced,"standing_at_original_exit":stood_at_exit,"original_goal_completed":continued,"bounded_actual_steps":bounded_steps,"maximum_step_cells":max_step,"waiting_reason_cleared_after_moving":waiting_cleared}

func _blocked_goal(suite: RefCounted, ids: Array[String]) -> HospitalSimulation:
	var sim: HospitalSimulation = suite._fixture()
	# An empty enclosed tile is a legal unreachable destination. The actors stay
	# outside the enclosure and retain their unobstructed hospital exit.
	for x: int in range(42,45):
		for y: int in range(79,82):
			if x!=43 or y!=80: sim.world.facts.floors.overrides["1"].blocked.append([x,y])
	for index: int in ids.size(): suite._add_actor(sim,ids[index],"S49",[35+index*2,84])
	sim.world.touch()
	for id: String in ids: sim.space.request_move(sim.world,id,1,[43,80])
	sim.space.movement._dispatch_routes(sim.world,ids.size())
	return sim

func _delayed_retarget(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = _blocked_goal(suite,["delayed_retarget"])
	var prior: Dictionary = sim.world.facts.moves.delayed_retarget
	var sequence: int = int(prior.request_sequence)
	var due: int = int(prior.get("route_retry_tick",-1))
	var delayed: bool = prior.get("route_pending",false) and due>sim.world.sim_tick
	# Restore before changing the delayed goal, so readiness is reconstructed
	# from saved facts and the original request's FIFO position survives.
	var restored: HospitalSimulation = HospitalSimulation.new(WorldState.new(sim.world.freeze()),suite.content)
	sim.dispose()
	sim = restored
	var changed: String = sim.space.request_move(sim.world,"delayed_retarget",1,[35,88])
	suite._movement_tick(sim)
	var current: Dictionary = sim.world.facts.moves.get("delayed_retarget",{})
	var immediate: bool = not current.is_empty() and not current.get("route_pending",true) and sim.world.sim_tick<due
	var retained: bool = int(current.get("request_sequence",-1))==sequence and current.get("target_cell",[])==[35,88]
	var moved: bool = sim.world.facts.actors.delayed_retarget.location.cell!=[35,84]
	sim.dispose()
	return {"ok":delayed and changed.is_empty() and immediate and retained and moved,"old_retry_tick":due,"next_boundary_started":immediate,"original_fifo_sequence":retained,"actual_displacement":moved,"restored_before_retarget":true}

func _delayed_cancel(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = _blocked_goal(suite,["cancelled_delayed","reused_delayed"])
	var due: int = int(sim.world.facts.moves.cancelled_delayed.get("route_retry_tick",-1))
	var old_sequence: int = int(sim.world.facts.moves.reused_delayed.request_sequence)
	var delayed: bool = due>sim.world.sim_tick
	sim.world.facts.moves.erase("cancelled_delayed")
	sim.world.facts.moves.erase("reused_delayed")
	suite._movement_tick(sim)
	var requested: String = sim.space.request_move(sim.world,"reused_delayed",1,[43,80])
	sim.space.movement._dispatch_routes(sim.world,2)
	var next: Dictionary = sim.world.facts.moves.reused_delayed
	var new_sequence: int = int(next.request_sequence)
	var later_due: int = int(next.get("route_retry_tick",-1))
	# Advance real movement boundaries up to the cancelled request's expiry.
	# The replacement's own retry is one tick later and must remain pending.
	while sim.world.sim_tick<=due: suite._movement_tick(sim)
	var current: Dictionary = sim.world.facts.moves.get("reused_delayed",{})
	var retained: bool = current.get("route_pending",false) and int(current.get("request_sequence",-1))==new_sequence and int(current.get("route_retry_tick",-1))==later_due and sim.space.movement._pending_routes.has("reused_delayed")
	var cleaned: bool = not sim.space.movement._pending_routes.has("cancelled_delayed")
	sim.dispose()
	return {"ok":delayed and requested.is_empty() and new_sequence>old_sequence and later_due>due and retained and cleaned,"cancelled_expiry":due,"replacement_expiry":later_due,"replacement_survives_stale_item":retained,"cancelled_record_removed":cleaned}

func _high_floor_topology(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	const HIGH: int = 16777217
	suite._history_height(sim,HIGH+2)
	var original: Dictionary = sim.world.facts.connectors[suite._connection(sim)]
	var interval: Dictionary = original.duplicate(true)
	interval.id = "high_continuous"
	interval.first_floor = HIGH
	interval.last_floor = HIGH+1
	interval.floor_id = HIGH
	interval.from = HIGH
	interval.to = HIGH
	interval.erase("stops")
	var exact: Dictionary = interval.duplicate(true)
	exact.id = "high_exact"
	exact.erase("first_floor")
	exact.erase("last_floor")
	exact.stops = [HIGH+2]
	exact.floor_id = HIGH+2
	exact.from = HIGH+2
	exact.to = HIGH+2
	sim.world.facts.connectors[interval.id] = interval
	sim.world.facts.connectors[exact.id] = exact
	sim.world.touch()
	var before: Dictionary = sim.world.freeze()
	var topology: Dictionary = sim.space.navigation._topology(sim.world)
	var rows: Array = []
	var ok: bool = true
	for floor_id: int in [HIGH-1,HIGH,HIGH+1,HIGH+2]:
		var expected: Array = ["high_continuous"] if floor_id in [HIGH,HIGH+1] else ["high_exact"] if floor_id==HIGH+2 else []
		var actual: Array = sim.space.navigation._floor_connections(topology,floor_id)
		ok = ok and actual==expected
		rows.append({"floor_id":floor_id,"expected":expected,"actual":actual})
	var readonly: bool = before==sim.world.freeze()
	sim.dispose()
	return {"ok":ok and readonly,"integer_floor_identity":ok,"readonly":readonly,"queries":rows}

func _door_layers(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._history_height(sim,2)
	var lower: CommandResult = suite._command(sim,"build_room",suite._room("lower_door_room",[42,68],[14,10],1))
	var upper: CommandResult = suite._command(sim,"build_room",suite._room("upper_door_room",[42,68],[14,10],2))
	if not lower.accepted or not upper.accepted:
		sim.dispose()
		return {"ok":false,"lower":lower.to_record(),"upper":upper.to_record()}
	suite._add_actor(sim,"future_upper_user","S59",[35,84])
	var actor: Dictionary = sim.world.facts.actors.future_upper_user
	var door: Dictionary = suite._doors(sim.world,"upper_door_room")[0]
	var before: Dictionary = sim.world.freeze()
	var clear: Dictionary = sim.space.door_quote(sim.world,actor,2,door)
	var readonly: bool = before==sim.world.freeze()
	var neighbor: CommandResult = suite._command(sim,"build_door",{"id":"upper_neighbor","room_id":"upper_door_room","definition_id":"DR01","edge":"south","offset":3})
	var blocked: Dictionary = sim.space.door_quote(sim.world,actor,2,door)
	var proper_layer: bool = clear.get("ok",false) and not blocked.get("ok",true) and blocked.get("reason","")=="门展开与另一扇门相交"
	sim.dispose()
	return {"ok":readonly and neighbor.accepted and proper_layer,"source_floor_door_ignored":clear,"target_floor_neighbor_blocks_expansion":blocked,"readonly":readonly}

func _group_door(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var built: CommandResult = suite._command(sim,"build_room",suite._room("group_door_room",[42,68],[14,10]))
	if not built.accepted:
		sim.dispose()
		return {"ok":false,"room":built.to_record()}
	suite._add_actor(sim,"small_leader","S49",[43,80])
	suite._add_actor(sim,"large_follower","S59",[43,83])
	var members: Array = ["small_leader","large_follower"]
	var offsets: Dictionary = {"small_leader":[0,0],"large_follower":[0,3]}
	var door: Dictionary = suite._doors(sim.world,"group_door_room")[0]
	var quote: Dictionary = sim.space.door_quote(sim.world,sim.world.facts.actors.small_leader,1,door,members)
	# S59 is 3.4m wide, 3.2m deep and 6.2m high; the required door adds
	# 0.1m clearance, yielding a three-cell opening with 3.5m/6.3m clearance.
	var fit: bool = quote.get("ok",false) and int(quote.get("span",0))==3 and float(quote.get("clear_width_m",0))>=3.5-0.00001 and float(quote.get("clear_height_m",0))>=6.3-0.00001
	var requested: String = sim.space.movement.request_group_move(sim.world,"small_leader",members,offsets,1,[43,72])
	var seen: bool = false
	var actual_fit: bool = true
	for tick: int in 400:
		var reservation: Dictionary = sim.world.facts.adaptations.get(door.id,{})
		if not reservation.is_empty():
			seen = true
			actual_fit = actual_fit and int(reservation.span)==3 and float(reservation.clear_width_m)>=3.5-0.00001 and float(reservation.clear_height_m)>=6.3-0.00001
		if not sim.world.facts.moves.has("small_leader"): break
		suite._movement_tick(sim)
	var arrived: bool = not sim.world.facts.moves.has("small_leader") and sim.space.at(sim.world,"small_leader",1,[43,72]) and sim.space.at(sim.world,"large_follower",1,[43,75])
	sim.dispose()
	return {"ok":fit and requested.is_empty() and seen and actual_fit and arrived,"group_quote":quote,"actual_expansion_seen":seen,"actual_group_dimensions":actual_fit,"both_members_arrived":arrived,"request_error":requested}

func _spatial() -> Dictionary:
	var index: BodyIndex = BodyIndex.new()
	var rectangles: Dictionary = {}
	for n: int in 32:
		var rect: Rect2 = Rect2(float(n%8)*2.0,float(n/8)*2.0,1.0+float(n%3)*0.25,1.0)
		var id: String = "r%02d"%n
		rectangles[id] = {"floor":1+n%2,"rect":rect}
		index.update(id,1+n%2,rect)
	var ok: bool = true
	for floor_id: int in [1,2,10000]:
		for n: int in 40:
			var rect: Rect2 = Rect2(float(n%10)*1.5,float(n/10),1.5,2.0)
			var expected: Array[String] = []
			for id: String in rectangles:
				if rectangles[id].floor==floor_id and rect.intersects(rectangles[id].rect,false): expected.append(id)
			expected.sort()
			ok = ok and index.candidates(floor_id,rect)==expected
	index.update("r00",10000,Rect2(0,0,1,1))
	var moved: bool = index.candidates(10000,Rect2(0,0,1,1))==["r00"] and not "r00" in index.candidates(1,Rect2(0,0,1,1))
	var touching: bool = not index.intersects(10000,Rect2(1,0,1,1),"")
	var ignored: bool = not index.intersects(10000,Rect2(0,0,1,1),"r00")
	index.remove("r00")
	var removed: bool = index.candidates(10000,Rect2(0,0,1,1)).is_empty()
	index.begin_boundary(rectangles)
	index.update("r01",1,Rect2(0,0,1,1))
	var boundary: bool = index.candidates(1,Rect2(0,0,1,1))==["r01"]
	index.expire_boundary()
	boundary = boundary and index.candidates(1,Rect2(0,0,20,20)).is_empty()
	var sweeps: bool = BodySweep.intersects(Rect2(0,0,1,1),Rect2(2,0,1,1),Rect2(2,0,1,1),Rect2(0,0,1,1))
	sweeps = sweeps and not BodySweep.intersects(Rect2(0,0,1,1),Rect2(1,0,1,1),Rect2(2,0,1,1),Rect2(2,0,1,1))
	sweeps = sweeps and BodySweep.intersects(Rect2(0,0,1,1),Rect2(0,0,2,1),Rect2(1.5,0,1,1),Rect2(1.5,0,1,1))
	return {"ok":ok and moved and touching and ignored and removed and boundary and sweeps,"brute_force_queries_equal":ok,"floor_update":moved,"touching_legal":touching,"ignored":ignored,"removed":removed,"boundary_lifetime":boundary,"moving_and_growing_envelopes":sweeps}

func _quotes(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	suite._add_actor(sim,"quote_subject","S49",[40.25,85.5])
	var before: Dictionary = sim.world.freeze()
	var observations: Array = []
	var ok: bool = true
	for destination: Array in [[1,[44,86]],[1,[60,90]],[2,[44,84]],[2,[90,12]]]:
		var count: int = int(sim.space.query_counts.materialized_floor_cells)
		var quote: Dictionary = sim.space.travel_quote(sim.world,"quote_subject",int(destination[0]),destination[1])
		var no_cells: bool = count==int(sim.space.query_counts.materialized_floor_cells) and not quote.has("path")
		var route: Dictionary = sim.space.route(sim.world,"quote_subject",int(destination[0]),destination[1])
		var equivalent: bool = true
		for key: String in ["ok","status","reason","walking_distance","travel_ticks"]:
			equivalent = equivalent and quote.get(key)==route.get(key)
		observations.append({"target":destination,"cost_equals_route":equivalent,"no_script_path_cells":no_cells,"ok":quote.get("ok",false)})
		ok = ok and equivalent and no_cells
	var readonly: bool = sim.world.freeze()==before
	sim.dispose()
	return {"ok":ok and readonly,"readonly":readonly,"observations":observations}

func _trip_quotes(suite: RefCounted) -> Dictionary:
	var observations: Array = []
	var ok: bool = true
	for floor_id: int in [1,2]:
		var sim: HospitalSimulation = suite._transit_fixture()
		var built: CommandResult = suite._command(sim,"build_facility",{"id":"trip_seat","definition_id":"FUR06","floor_id":floor_id,"cell":[44,84]})
		if not built.accepted:
			observations.append({"floor":floor_id,"build":built.to_record()})
			ok = false
			sim.dispose()
			continue
		suite._add_actor(sim,"trip_subject","S49",[44,88])
		var before: Dictionary = sim.world.freeze()
		var cells: int = int(sim.space.query_counts.materialized_floor_cells)
		var trip: Dictionary = sim.space.facility_trip_quote(sim.world,"trip_seat","trip_subject")
		var no_cells: bool = cells==int(sim.space.query_counts.materialized_floor_cells)
		var layout: Dictionary = sim.space.facility_layout(sim.world,"trip_seat")
		var direct: Dictionary = sim.space.travel_quote(sim.world,"trip_subject",floor_id,layout.patient_cell)
		var equivalent: bool = trip.get("ok",false) and direct.get("ok",false) and int(trip.get("travel_ticks",-1))==int(direct.get("travel_ticks",-2)) and trip.get("cell",[])==layout.patient_cell
		var readonly: bool = before==sim.world.freeze()
		ok = ok and equivalent and no_cells and readonly
		observations.append({"floor":floor_id,"trip":trip,"direct":direct,"cost_equals_direct_quote":equivalent,"no_script_path_cells":no_cells,"facts_unchanged":readonly})
		sim.dispose()
	return {"ok":ok,"observations":observations}

func _group(suite: RefCounted, phase: String) -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	var busy_started: bool = true
	var connection_id: String = suite._connection(sim)
	if phase=="waiting":
		# A real earlier passenger occupies the lift while the group walks its
		# final cell to the landing. No ticket, rider or phase is fabricated.
		suite._add_actor(sim,"earlier_passenger","S49",[36,76])
		var earlier: String = sim.space.request_move(sim.world,"earlier_passenger",2,[52,84])
		busy_started = earlier.is_empty() and suite._wait(sim,func()->bool:
			return sim.world.facts.actors.earlier_passenger.location.kind=="transit",40,suite._movement_tick.bind(sim))
		if not busy_started:
			var failed: Dictionary = {"ok":false,"phase":phase,"earlier_passenger_actually_boarded":false,"connection":sim.world.facts.connectors[connection_id].duplicate(true)}
			sim.dispose()
			return failed
	suite._add_actor(sim,"party_a","S49",[36,77] if phase=="waiting" else [40,80])
	suite._add_actor(sim,"party_b","S49",[37,77] if phase=="waiting" else [41,80])
	var members: Array = ["party_a","party_b"]
	var offsets: Dictionary = {"party_a":[0,0],"party_b":[1,0]}
	var requested: String = sim.space.movement.request_group_move(sim.world,"party_a",members,offsets,2,[46,84])
	if not requested.is_empty():
		sim.dispose()
		return {"ok":false,"phase":phase,"request_error":requested}
	var reached: bool = true
	if phase!="pending":
		reached = suite._wait(sim,func()->bool:
			return sim.world.facts.actors.party_a.location.kind=="transit" if phase=="riding" else sim.world.facts.moves.get("party_a",{}).has("transit_ticket") and sim.world.facts.actors.party_a.location.kind=="floor" and sim.world.facts.connectors[connection_id].phase!="idle",600,suite._movement_tick.bind(sim))
	var location: Dictionary = sim.world.facts.actors.party_a.location.duplicate(true)
	var sequence: int = int(sim.world.facts.moves.get("party_a",{}).get("request_sequence",-1))
	var same: String = sim.space.movement.request_group_move(sim.world,"party_a",members,offsets,2,[46,84])
	var reused: bool = int(sim.world.facts.moves.get("party_a",{}).get("request_sequence",-2))==sequence
	var invalid_before: Dictionary = sim.world.freeze()
	var invalid: String = sim.space.movement.request_group_move(sim.world,"party_a",members,offsets,1,[-4,-4])
	var atomic: bool = not invalid.is_empty() and invalid_before==sim.world.freeze()
	var changed: String = sim.space.movement.request_group_move(sim.world,"party_a",members,offsets,1,[50,86])
	var goal: bool = sim.world.facts.moves.party_a.target_floor==1 and sim.world.facts.moves.party_a.target_cell==[50,86]
	var safe: bool = sim.world.facts.actors.party_a.location==location
	if phase=="riding":
		safe = safe and sim.world.facts.moves.party_a.get("replan_after_transit",false)
		var restored: HospitalSimulation = HospitalSimulation.new(WorldState.new(sim.world.freeze()),suite.content)
		sim.dispose()
		sim = restored
	var arrived: bool = suite._wait(sim,func()->bool:
		return not sim.world.facts.moves.has("party_a") and sim.space.at(sim.world,"party_a",1,[50,86]) and sim.space.at(sim.world,"party_b",1,[51,86]),1400,suite._movement_tick.bind(sim))
	var result: Dictionary = {"ok":busy_started and reached and same.is_empty() and reused and atomic and changed.is_empty() and goal and safe and arrived,"phase":phase,"earlier_passenger_actually_boarded":busy_started if phase=="waiting" else null,"boundary_reached":reached,"same_goal_reused":reused,"invalid_goal_atomic":atomic,"change_error":changed,"new_goal_retained":goal,"safe_position_retained":safe,"actual_group_arrival":arrived,"remaining":sim.world.facts.moves.duplicate(true)}
	sim.dispose()
	return result
