extends SceneTree

var _checks: Dictionary = {}
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	if "--navigation-only" in OS.get_cmdline_user_args():
		_navigation_rules(content)
		_finish()
		return
	var world: WorldState = FeasibilityHospitals.create("kernel-rules",false,content)
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	var session: GameSession = GameSession.new(simulation,"session-a")
	_check("initial_world",world.validate(content).is_empty())
	var untouched: String = _canonical(world)
	var old_input: GameCommand = _move(world,"old-input","other-session")
	_check("old_session_rejected_atomically",session.submit(old_input).code=="session_mismatch" and untouched==_canonical(world))
	var wrong_hospital: GameCommand = _move(world,"wrong-hospital","session-a")
	wrong_hospital.hospital_id = "another-hospital"
	_check("wrong_hospital_rejected_atomically",not session.submit(wrong_hospital).accepted and untouched==_canonical(world))
	var stale: GameCommand = _move(world,"stale","session-a")
	(stale.typed_payload as MoveActorPayload).confirmed_location.cell = [1,1]
	_check("material_change_keeps_world",session.submit(stale).code=="material_change" and untouched==_canonical(world))
	var clinical: GameCommand = GameCommand.new("clinical",world.hospital_id,world.revision,"move_actor",MoveActorPayload.new("patient",1,Vector2i(35,66),world.facts.actors.patient.location),"session-a")
	_check("clinical_person_keeps_original_route",session.submit(clinical).code=="clinical_occupancy" and untouched==_canonical(world))
	var command: GameCommand = _move(world,"accepted","session-a")
	world.touch()
	var tick: int = world.sim_tick
	_check("unrelated_revision_does_not_reject",session.submit(command).accepted)
	_check("paused_command_does_not_tick",world.sim_tick==tick)
	var after: String = _canonical(world)
	_check("duplicate_command_exactly_once",session.submit(command).accepted and _canonical(world)==after)
	var conflict: GameCommand = _move(world,"accepted","session-a")
	(conflict.typed_payload as MoveActorPayload).cell = Vector2i(35,67)
	_check("same_id_changed_payload_rejected",session.submit(conflict).code=="command_id_conflict" and _canonical(world)==after)
	var restored: WorldState = WorldState.new(world.freeze())
	var restored_simulation: HospitalSimulation = HospitalSimulation.new(restored,content)
	_check("restored_receipt_prevents_second_effect",restored_simulation.apply(command).accepted and _canonical(restored)==after)
	var owner: String = world.facts.visits.keys()[0]
	var money: int = HospitalLedger.balance(world)
	_check("paused_payment",HospitalLedger.post(world,LedgerEntry.new(owner,"confirmed_payment",-50)).accepted and HospitalLedger.balance(world)==money-50 and world.sim_tick==tick)
	after = _canonical(world)
	_check("duplicate_payment",HospitalLedger.post(world,LedgerEntry.new(owner,"confirmed_payment",-50)).accepted and after==_canonical(world))
	_check("payment_conflict_atomic",not HospitalLedger.post(world,LedgerEntry.new(owner,"confirmed_payment",-51)).accepted and after==_canonical(world))
	_check("negative_balance_atomic",not HospitalLedger.post(world,LedgerEntry.new(owner,"too_expensive",-1000000)).accepted and after==_canonical(world))
	_check("paused_refund",HospitalLedger.post(world,LedgerEntry.new(owner,"confirmed_refund",50)).accepted and HospitalLedger.balance(world)==money and world.sim_tick==tick)
	var pending_world: WorldState = FeasibilityHospitals.create("pending-funds",false,content)
	var pending_owner: String = pending_world.facts.visits.keys()[0]
	HospitalLedger.post(pending_world,LedgerEntry.new(pending_owner,"pending_income",100000),false)
	var pending_before: String = _canonical(pending_world)
	_check("pending_income_cannot_fund_confirmed_payment",not HospitalLedger.post(pending_world,LedgerEntry.new(pending_owner,"confirmed_payment",-150000)).accepted and _canonical(pending_world)==pending_before and HospitalLedger.balance(pending_world)==100000)
	var missing_location: GameCommand = GameCommand.from_record({"id":"missing-location","hospital_id":world.hospital_id,"expected_revision":world.revision,"kind":"move_actor","typed_payload":{"actor_id":"sample_S21","floor_id":1,"cell":[35,66]}})
	_check("typed_payload_requires_confirmation",missing_location.typed_payload==null)
	var overflow: MoveActorPayload = MoveActorPayload.from_record({"actor_id":"sample_S21","floor_id":1,"cell":[4294967330,66],"confirmed_location":world.facts.actors.sample_S21.location})
	_check("target_coordinate_never_wraps",overflow==null)
	_routing_projection(content)
	_sweep_boundaries()
	_shape_refresh(content)
	_navigation_rules(content)
	session.set_speed(3)
	session.pause("photo")
	session.pause("focus")
	session.resume("photo")
	_check("independent_pause_sources",session.actual_speed()==0 and session.pause_reasons()==["focus"])
	session.set_speed(1)
	session.resume("focus")
	_check("current_player_intent_wins",session.actual_speed()==1)
	session.set_watching(true)
	session.set_speed(3)
	_check("manual_speed_clears_watch_override",session.actual_speed()==3)
	tick = world.sim_tick
	session.pause("sleep")
	session.resume("sleep")
	session.advance(10.0)
	_check("sleep_does_not_catch_up",world.sim_tick==tick)
	session.advance(0.5)
	_check("eight_step_cap_keeps_backlog",world.sim_tick==tick+8 and session.running_slow)
	session.advance(0.0)
	_check("backlog_settles_without_skips",world.sim_tick==tick+15 and not session.running_slow)
	_check("phase_order",HospitalSimulation.PHASES==["commands","boundaries","arrivals","dispatch","movement","work","needs","interactions","settlement","snapshot"])
	for input_surgical: bool in [false,true]:
		_determinism(content,input_surgical)
	_finish()

func _finish() -> void:
	var path: String = "res://.cache/validation/stage03-navigation-rules.json" if "--navigation-only" in OS.get_cmdline_user_args() else "res://.cache/validation/stage03-kernel-rules.json"
	var output: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":_checks,"failures":_failures,"engine":Engine.get_version_info()},"\t",true,true))
	print("KERNEL_RULES="+str(_checks.size())+" failures="+str(_failures.size()))
	quit(0 if _failures.is_empty() else 1)

func _determinism(content: HospitalContent, surgical: bool) -> void:
	var states: Array[WorldState] = []
	for index: int in 3:
		states.append(FeasibilityHospitals.create("replay",surgical,content))
	var sessions: Array[GameSession] = []
	for state: WorldState in states:
		sessions.append(GameSession.new(HospitalSimulation.new(state,content),"replay-session"))
	var target: int = 12000 if surgical else 6000
	for index: int in sessions.size():
		var session: GameSession = sessions[index]
		session.set_speed(1 if index==0 else 3)
		var command: GameCommand = _move(states[index],"replay-move","replay-session")
		session.submit(command)
		while states[index].sim_tick<target:
			var delta: float = 1.0/60.0 if index==0 else (1.0/24.0 if index==1 else 1.0/144.0)
			delta = minf(delta,float(target-states[index].sim_tick)*WorldState.TICK_SECONDS/session.actual_speed())
			session.advance(delta)
	_check(("surgery" if surgical else "outpatient")+"_same_tick_all_facts_and_rng",_canonical(states[0])==_canonical(states[1]) and _canonical(states[0])==_canonical(states[2]))
	_check(("surgery" if surgical else "outpatient")+"_final_world_valid",states[0].validate(content).is_empty())
	var final: WorldState = states[0]
	var visit: Dictionary = final.facts.visits.values()[0]
	var prefix: String = "surgery" if surgical else "outpatient"
	_check(prefix+"_really_cures_and_departs",visit.phase=="departed" and visit.final_result=="cured",{"visit":visit,"moves":final.facts.moves})
	var issued: int = 0
	var cure_entries: int = 0
	var cure_amount: int = 0
	for attempt: Dictionary in final.facts.attempts.values():
		issued += int(attempt.supply_units)
	for entry: Dictionary in final.facts.ledger.entries.values():
		if entry.component=="cure":
			cure_entries += 1
			cure_amount += int(entry.amount)
	_check(prefix+"_supplies_and_cure_settle_once",60-int(final.facts.inventory.units)==issued and final.facts.inventory.issues.size()==final.facts.attempts.size() and cure_entries==1 and cure_amount==ceili(float(content.definition("diseases",visit.disease_id).cure_fee)*(1.8 if surgical else 1.0)))
	if surgical:
		_check("navigation_preserves_real_ward_care_and_release",final.facts.ward_stays.is_empty() and final.facts.staff.ward_nurse.practice.care>0 and final.facts.staff.round_doctor.practice.treatment>0)

func _move(world: WorldState, id: String, session: String) -> GameCommand:
	return GameCommand.new(id,world.hospital_id,world.revision,"move_actor",MoveActorPayload.new("sample_S21",1,Vector2i(35,66),world.facts.actors.sample_S21.location),session)

func _routing_projection(content: HospitalContent) -> void:
	var world: WorldState = FeasibilityHospitals.create("route-projection",true,content)
	var space: HospitalSpace = HospitalSpace.new(content)
	var before: String = _canonical(world)
	var matched: bool = true
	for floor_id: int in [1,2]:
		for actor_id: String in world.ids("actors"):
			var actor: Dictionary = world.facts.actors[actor_id]
			var query: RouteClearance = RouteClearance.new(space,world,actor,floor_id)
			for x: int in range(31,56):
				for y: int in range(63,97):
					var cell: Vector2i = Vector2i(x,y)
					if query.reason(cell)!=space.static_reason(world,actor,floor_id,cell):
						matched = false
	_check("route_projection_matches_live_geometry",matched and _canonical(world)==before)

func _sweep_boundaries() -> void:
	var index: BodyIndex = BodyIndex.new()
	var rect: Rect2 = Rect2(3.5,3.5,2.0,2.0)
	index.update("old",1,rect)
	index.begin_boundary({"old":true,"new":true})
	_check("sweep_requires_current_boundary",not index.intersects(1,rect,""))
	index.update("old",1,rect)
	_check("same_rectangle_reactivates_sweep",index.intersects(1,rect,""))
	index.begin_boundary({"new":true})
	_check("retired_sweep_pruned",not index.intersects(1,rect,"") and index._records.is_empty())
	index.update("new",2,rect)
	_check("sweep_floor_isolation",not index.intersects(1,rect,"") and index.intersects(2,rect,""))

func _shape_refresh(content: HospitalContent) -> void:
	var world: WorldState = FeasibilityHospitals.create("shape-refresh",true,content)
	var space: HospitalSpace = HospitalSpace.new(content)
	var actor: Dictionary = world.facts.actors.sample_S59
	var original: Rect2 = space.body_rectangle(actor)
	actor.posture = "lying"
	_check("shape_refreshes_posture",space.body_rectangle(actor)==HospitalSpace.new(content).body_rectangle(actor) and space.body_rectangle(actor)!=original)
	actor.posture = "standing"
	actor.facing = PI/4.0
	_check("shape_refreshes_facing",space.body_rectangle(actor)==HospitalSpace.new(content).body_rectangle(actor))
	actor.location.cell = [41.125,88.375]
	_check("shape_translates_current_origin",space.body_rectangle(actor)==HospitalSpace.new(content).body_rectangle(actor))
	var patient: Dictionary = world.facts.actors.patient
	space.body_rectangle(patient)
	patient.erase("body_binding_id")
	_check("shape_refreshes_body_binding",space.body_rectangle(patient)==HospitalSpace.new(content).body_rectangle(patient))

func _canonical(world: WorldState) -> String:
	return JSON.stringify(world.facts,"",true,true)

func _nav_world(content: HospitalContent, count: int = 2) -> WorldState:
	var world: WorldState = FeasibilityHospitals.create("navigation-rules",false,content)
	for field: String in ["actors","staff","visits","tickets","sessions","attempts","preparations","ward_stays","facilities","rooms","adaptations","connectors","moves"]:
		world.facts[field] = {}
	for floor_id: int in [1,2,3]:
		world.facts.floors.overrides[str(floor_id)] = {"plots":[[0,0]],"blocked":[],"doors":[]}
	for index: int in count:
		var id: String = "actor_%02d" % index
		world.facts.actors[id] = {"id":id,"name":id,"species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":[2+(index%6)*4,2+(index/6)*4]},"facing":0.0,"posture":"standing"}
	return world

func _nav_lift(world: WorldState, definition: String = "VC02") -> void:
	var size: int = 7 if definition=="VC03" else 4
	world.facts.connectors["lift"] = {"id":"lift","definition_id":definition,"stops":[1,2,3],"anchor":[10,15],"cell":[10,15-size],"footprint":[size,size],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0}

func _navigation_rules(content: HospitalContent) -> void:
	var world: WorldState = _nav_world(content)
	world.facts.actors.actor_01.location.cell = [25,25]
	var space: HospitalSpace = HospitalSpace.new(content)
	var before: String = _canonical(world)
	var original: Dictionary = space.route(world,"actor_00",1,[20,20])
	_check("native_floor_route_is_readonly_and_shortest",original.ok and original.walking_distance==36 and _canonical(world)==before)
	var blocked: Array = original.path[original.path.size()/2].cell.duplicate()
	world.facts.floors.overrides["1"].blocked.append(blocked)
	world.touch()
	var repaired: Dictionary = space.route(world,"actor_00",1,[20,20])
	var cold: Dictionary = HospitalSpace.new(content).route(world,"actor_00",1,[20,20])
	_check("incremental_graph_matches_cold_path",repaired.ok and repaired.path==cold.path)
	world.facts.floors.overrides["1"].blocked.clear()
	world.touch()
	_check("restored_edges_keep_native_path_identity",space.route(world,"actor_00",1,[20,20]).path==original.path)
	world.facts.rooms["room"] = {"id":"room","kind":"diagnosis","floor_id":1,"origin":[8,8],"size":[6,6]}
	world.facts.floors.overrides["1"].doors = [{"id":"door","definition_id":"DR01","cell":[10,14],"span":1,"axis":"x","room_id":"room"}]
	world.facts.actors.actor_00.location.cell = [8,10]
	world.touch()
	var wall: Dictionary = space.route(world,"actor_00",1,[7,10])
	_check("grid_edge_wall_requires_actual_door",wall.ok and wall.path.size()>1)
	var current: Array = [8,10]
	var valid_edges: bool = true
	for segment: Dictionary in wall.path:
		var next: Array = segment.cell
		if (int(current[0])==8 and int(next[0])==7) or (int(current[0])==7 and int(next[0])==8):
			if int(current[1])>=8 and int(current[1])<14:
				valid_edges = false
		current = next
	_check("legal_endpoints_do_not_bypass_wall_edges",valid_edges)
	world.facts.actors.actor_01.species_id = "S55"
	world.facts.actors.actor_01.location.cell = [9,10]
	var tall: Dictionary = space.route(world,"actor_01",1,[7,10])
	world.facts.floors.height_intervals[0].height_m = 3.0
	world.touch()
	var short_result: Dictionary = space.route(world,"actor_00",1,[7,10])
	var tall_result: Dictionary = space.route(world,"actor_01",1,[7,10])
	_check("same_grid_size_keeps_full_height_identity",tall.ok and short_result.ok and not tall_result.ok)
	world.facts.floors.height_intervals[0].height_m = 7.5
	world.touch()
	var restored_path: Dictionary = space.route(world,"actor_01",1,[7,10])
	space._navigation._trim(0)
	_check("height_repair_and_eviction_keep_cold_identity",restored_path.ok and restored_path.path==tall.path and space.route(world,"actor_01",1,[7,10]).path==tall.path)
	_small_grid_paths(content)
	_reservation_queries(content)
	_request_fifo(content)
	_active_route_changes(content)
	_support_departure_floor(content)
	_first_segment_courtesy(content)
	_transport_quotes(content)
	_transport_groups(content)
	_transport_transfers(content)
	_transport_waiting(content)
	_check("parallel_sweeps_are_not_coarse_collisions",not BodySweep.intersects(Rect2(0,0,1,1),Rect2(1,0,1,1),Rect2(1,0,1,1),Rect2(2,0,1,1)))
	_check("head_on_swap_collides_in_time",BodySweep.intersects(Rect2(0,0,1,1),Rect2(1,0,1,1),Rect2(1,0,1,1),Rect2(0,0,1,1)))
	_check("stationary_body_is_not_skipped_by_sweep",BodySweep.intersects(Rect2(0,0,0.5,0.5),Rect2(2,0,0.5,0.5),Rect2(1,0,0.5,0.5),Rect2(1,0,0.5,0.5)))
	_check("crossing_at_different_times_stays_clear",not BodySweep.intersects(Rect2(-1,0,0.1,0.1),Rect2(1,0,0.1,0.1),Rect2(0,-0.1,0.1,0.1),Rect2(0,1.9,0.1,0.1)))
	var buckets: BodyIndex = BodyIndex.new(Vector2(8,8))
	buckets.update("wide",1,Rect2(7.8,7.8,3.2,3.4))
	buckets.update("upper",2,Rect2(8.2,8.2,1,1))
	_check("wide_fractional_bodies_cover_all_floor_buckets",buckets.candidates(1,Rect2(10.8,10.8,0.1,0.1))==["wide"] and buckets.candidates(2,Rect2(8.2,8.2,0.1,0.1))==["upper"])

func _small_grid_paths(content: HospitalContent) -> void:
	var world: WorldState = _nav_world(content,1)
	for y: int in 6:
		world.facts.floors.overrides["1"].blocked.append([4,y])
	var space: HospitalSpace = HospitalSpace.new(content)
	var result: Dictionary = space.route(world,"actor_00",1,[6,2])
	_check("native_detour_matches_enumerated_unit_cost",result.ok and result.walking_distance==12)
	for y: int in range(6,32):
		world.facts.floors.overrides["1"].blocked.append([4,y])
	world.touch()
	var actor: Dictionary = world.facts.actors.actor_00
	var query: RouteClearance = RouteClearance.new(space,world,actor,1)
	var warm: Dictionary = space._navigation.graph(space,world,1,actor,[],{}).find_path(Vector2i(2,2),Vector2i(6,2),query,Callable(),true)
	var cold: Dictionary = FloorNavigation.new(query).find_path(Vector2i(2,2),Vector2i(6,2),query,Callable(),true)
	_check("partial_path_is_stable_after_local_disconnect",warm==cold and warm.status=="partial" and not warm.ok)

func _reservation_queries(content: HospitalContent) -> void:
	var world: WorldState = _nav_world(content)
	for actor: Dictionary in world.facts.actors.values():
		actor.species_id = "S59"
	world.facts.actors.actor_01.location.cell = [25,25]
	world.facts.rooms["ward"] = {"id":"ward","kind":"ward","floor_id":1,"origin":[0,0],"size":[32,32]}
	var sample: WorldState = FeasibilityHospitals.create("reservation-source",true,content)
	var bed: Dictionary = sample.facts.facilities.bed.duplicate(true)
	bed.cell = [8,8]
	bed.patient_cell = [8,11]
	bed.operator_cells = [[7,9]]
	bed.repair_cell = [11,8]
	world.facts.facilities["bed"] = bed
	var space: HospitalSpace = HospitalSpace.new(content)
	var reserved: String = space.reserve_facility(world,"bed","actor_00","actor_00")
	_check("expanded_reservation_has_real_producer",reserved.is_empty() and world.facts.adaptations.has("bed"))
	if not world.facts.adaptations.has("bed"):
		return
	var target: Array = world.facts.adaptations.bed.patient_cell
	var owner: Dictionary = space.route(world,"actor_00",1,target)
	var other: Dictionary = space.route(world,"actor_01",1,target)
	var again: Dictionary = space.route(world,"actor_00",1,target)
	_check("reservation_exception_is_query_local",owner.ok and not other.ok and again.ok and owner.path==again.path)

func _request_fifo(content: HospitalContent) -> void:
	var world: WorldState = _nav_world(content,36)
	var space: HospitalSpace = HospitalSpace.new(content)
	var order: Array = world.ids("actors")
	order.reverse()
	for id: String in order:
		var actor: Dictionary = world.facts.actors[id]
		space.route(world,id,1,[int(actor.location.cell[0])+1,actor.location.cell[1]])
		space.request_move(world,id,1,[int(actor.location.cell[0])+1,actor.location.cell[1]])
	var pending_id: String = order[20]
	var sequence: int = world.facts.moves[pending_id].request_sequence
	var pending_actor: Dictionary = world.facts.actors[pending_id]
	space.request_move(world,pending_id,1,[int(pending_actor.location.cell[0])+2,pending_actor.location.cell[1]])
	_check("pending_target_replacement_keeps_fifo_identity",world.facts.moves[pending_id].request_sequence==sequence)
	space.advance(world)
	var active: Array = []
	for id: String in world.ids("moves"):
		if not world.facts.moves[id].get("route_pending",false):
			active.append(id)
	var first: Array = order.slice(0,8)
	first.sort()
	_check("cache_hits_still_consume_global_request_budget",active==first)
	_check("queued_world_roundtrip_is_valid",world.validate(content).is_empty())
	var restored: WorldState = WorldState.new(world.freeze())
	var other: HospitalSpace = HospitalSpace.new(content)
	space.advance(world)
	other.advance(restored)
	_check("request_fifo_survives_restore",_canonical(world)==_canonical(restored))
	var blocked: WorldState = _nav_world(content)
	blocked.facts.actors.actor_01.location.cell = [10,10]
	for y: int in 32:
		blocked.facts.floors.overrides["1"].blocked.append([3,y])
	var blocked_space: HospitalSpace = HospitalSpace.new(content)
	blocked_space.request_move(blocked,"actor_00",1,[4,2])
	blocked_space.request_move(blocked,"actor_01",1,[11,10])
	blocked_space.advance(blocked)
	_check("failed_route_retries_at_tail_without_teleport",blocked.facts.moves.actor_00.request_sequence>blocked.facts.moves.actor_01.request_sequence and blocked.facts.actors.actor_00.location.cell==[2,2] and blocked.facts.moves.actor_00.route_pending)

func _transport_quotes(content: HospitalContent) -> void:
	var world: WorldState = _nav_world(content)
	_nav_lift(world)
	var space: HospitalSpace = HospitalSpace.new(content)
	var connection: Dictionary = world.facts.connectors.lift
	var quote: Dictionary = HospitalTransit.quote(space,world,connection,"actor_00",1,2,0)
	_check("idle_lift_quote_includes_board_and_alight",quote.ok and quote.arrival_ticks==40)
	connection.floor_id = 3
	quote = HospitalTransit.quote(space,world,connection,"actor_00",1,2,0)
	_check("lift_quote_includes_real_empty_return",quote.ok and quote.arrival_ticks==60)
	connection.floor_id = 1
	world.facts.actors.actor_00.location.cell = connection.anchor.duplicate()
	space.request_move(world,"actor_00",3,[12,15])
	space.advance(world)
	_check("actual_arrival_creates_one_transport_ticket",connection.get("ticket_next",0)==1 and connection.riders==["actor_00"])
	var before: String = _canonical(world)
	quote = HospitalTransit.quote(space,world,connection,"actor_01",1,2,0)
	var late: Dictionary = HospitalTransit.quote(space,world,connection,"actor_01",1,2,100)
	_check("transport_quotes_share_one_arrival_timeline",quote.ok and quote.arrival_ticks==110 and late.ok and late.arrival_ticks==160 and _canonical(world)==before)
	world.facts.actors["exit_blocker"] = {"id":"exit_blocker","name":"exit_blocker","species_id":"S49","location":{"kind":"floor","floor_id":3,"cell":connection.anchor.duplicate()},"facing":0.0,"posture":"standing"}
	world.touch()
	quote = HospitalTransit.quote(space,world,connection,"actor_01",1,2,0)
	_check("blocked_egress_is_unknown_not_zero",not quote.ok and quote.status=="estimate_unknown")
	world.facts.actors.exit_blocker.location = {"kind":"outside"}
	space.sync_actor(world,"exit_blocker")
	connection.pending_failure = true
	_check("known_failure_never_quotes_new_upward_trip",not HospitalTransit.quote(space,world,connection,"actor_01",1,2,0).ok)
	var emergency: WorldState = _nav_world(content)
	_nav_lift(emergency)
	emergency.facts.connectors.lift.failed = true
	emergency.facts.connectors.lift.floor_id = 3
	var emergency_space: HospitalSpace = HospitalSpace.new(content)
	quote = HospitalTransit.quote(emergency_space,emergency,emergency.facts.connectors.lift,"actor_00",3,1,0)
	_check("safety_lowering_uses_original_four_second_rate",quote.ok and quote.arrival_ticks==110)

func _support_departure_floor(content: HospitalContent) -> void:
	var world: WorldState = _nav_world(content,1)
	var sample: WorldState = FeasibilityHospitals.create("support-source",true,content)
	var bed: Dictionary = sample.facts.facilities.bed.duplicate(true)
	bed.cell = [8,8]
	bed.patient_cell = [8,11]
	bed.erase("room_id")
	world.facts.facilities["bed"] = bed
	world.facts.actors.actor_00.posture = "lying"
	world.facts.actors.actor_00.support_facility_id = "bed"
	world.facts.actors.actor_00.location.cell = [8,10]
	var space: HospitalSpace = HospitalSpace.new(content)
	space.request_move(world,"actor_00",2,[5,5])
	var departure: Dictionary = world.facts.moves.actor_00.path[0]
	for tick: int in 30:
		space.advance(world)
	_check("support_departure_stays_on_actual_source_floor",departure.floor_id==1 and space.at(world,"actor_00",1,[8,11]) and world.facts.moves.actor_00.target_floor==2 and world.facts.actors.actor_00.posture=="standing")

func _first_segment_courtesy(content: HospitalContent) -> void:
	var world: WorldState = _nav_world(content)
	world.facts.actors.actor_00.location.cell = [2,2]
	world.facts.actors.actor_01.location.cell = [2,3]
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	simulation.space.request_move(world,"actor_00",1,[3,4])
	simulation.space.request_move(world,"actor_01",1,[4,2])
	var collided: bool = false
	var retreated: bool = false
	for tick: int in 260:
		simulation.step()
		collided = collided or simulation.space.body_rectangle(world.facts.actors.actor_00).intersects(simulation.space.body_rectangle(world.facts.actors.actor_01),false)
		for movement: Dictionary in world.facts.moves.values():
			retreated = retreated or bool(movement.yielding)
	_check("first_segment_opposition_retreats_without_overlap",not collided and retreated and simulation.space.at(world,"actor_00",1,[3,4]) and simulation.space.at(world,"actor_01",1,[4,2]),{"actors":world.facts.actors,"moves":world.facts.moves})

func _active_route_changes(content: HospitalContent) -> void:
	var world: WorldState = _nav_world(content,1)
	var space: HospitalSpace = HospitalSpace.new(content)
	space.request_move(world,"actor_00",1,[20,2])
	space.advance(world)
	world.facts.floors.overrides["1"].blocked.append([18,2])
	world.touch()
	var restored: WorldState = WorldState.new(world.freeze())
	var other: HospitalSpace = HospitalSpace.new(content)
	var original: Array = world.facts.actors.actor_00.location.cell.duplicate()
	space.advance(world)
	other.advance(restored)
	_check("future_geometry_change_rechecks_remaining_route",world.facts.moves.actor_00.route_pending and world.facts.actors.actor_00.location.cell==original)
	_check("warm_and_restored_active_route_invalidation_match",_canonical(world)==_canonical(restored))
	var transit: WorldState = _nav_world(content,1)
	_nav_lift(transit)
	var transit_space: HospitalSpace = HospitalSpace.new(content)
	transit_space.request_move(transit,"actor_00",3,[12,15])
	transit_space.advance(transit)
	transit.facts.connectors.lift.pending_failure = true
	transit.touch()
	original = transit.facts.actors.actor_00.location.cell.duplicate()
	transit_space.advance(transit)
	_check("future_connection_mode_change_rechecks_active_route",transit.facts.moves.actor_00.route_pending and transit.facts.actors.actor_00.location.cell==original)

func _transport_groups(content: HospitalContent) -> void:
	var world: WorldState = _nav_world(content)
	_nav_lift(world,"VC03")
	world.facts.actors.actor_00.location.cell = [10,15]
	world.facts.actors.actor_01.location.cell = [9,15]
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	var members: Array = ["actor_00","actor_01"]
	var offsets: Dictionary = {"actor_00":[0,0],"actor_01":[-1,0]}
	var result: String = simulation.space.request_group_move(world,"actor_00",members,offsets,2,[12,15])
	simulation.step()
	var connection: Dictionary = world.facts.connectors.lift
	_check("whole_group_boards_without_ground_duplicates",result.is_empty() and connection.riders==members and world.facts.actors.actor_00.location.kind=="transit" and world.facts.actors.actor_01.location.kind=="transit" and world.facts.actors.actor_00.location.cabin_cell!=world.facts.actors.actor_01.location.cabin_cell)
	var reason: String = world.validate(content)
	_check("boarding_group_snapshot_is_valid",reason.is_empty(),{"reason":reason})
	var serialized: WorldState = WorldState.new(JSON.parse_string(_canonical(world)))
	_check("boarding_group_json_roundtrip_is_valid",serialized.validate(content).is_empty(),{"reason":serialized.validate(content)})
	var restored: WorldState = WorldState.new(world.freeze())
	var second: HospitalSimulation = HospitalSimulation.new(restored,content)
	var from_json: HospitalSimulation = HospitalSimulation.new(serialized,content)
	for tick: int in 80:
		simulation.step()
		second.step()
		from_json.step()
	_check("group_transit_restore_keeps_exact_facts",_canonical(world)==_canonical(restored))
	_check("json_restored_group_continues_same_business_facts",JSON.parse_string(_canonical(world))==JSON.parse_string(_canonical(serialized)) and serialized.validate(content).is_empty())
	reason = world.validate(content)
	_check("group_alights_at_actual_distinct_offsets",simulation.space.at(world,"actor_00",2,[12,15]) and simulation.space.at(world,"actor_01",2,[11,15]) and reason.is_empty(),{"reason":reason,"actors":world.facts.actors,"moves":world.facts.moves,"connection":connection})

func _transport_transfers(content: HospitalContent) -> void:
	var world: WorldState = _nav_world(content,1)
	world.facts.actors.actor_00.location.cell = [2,15]
	world.facts.connectors = {
		"aa_direct":{"id":"aa_direct","definition_id":"VC02","stops":[1,3],"anchor":[26,15],"cell":[26,11],"footprint":[4,4],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0},
		"m_first":{"id":"m_first","definition_id":"VC01","stops":[1,2],"anchor":[6,15],"cell":[6,9],"footprint":[4,6],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0},
		"z_second":{"id":"z_second","definition_id":"VC01","stops":[2,3],"anchor":[16,15],"cell":[16,9],"footprint":[4,6],"floor_id":2,"phase":"idle","riders":[],"remaining_ticks":0}}
	var space: HospitalSpace = HospitalSpace.new(content)
	var before: String = _canonical(world)
	var result: Dictionary = space.route(world,"actor_00",3,[2,15])
	var connections: Array = []
	for segment: Dictionary in result.get("path",[]):
		if segment.kind=="connector":
			connections.append(segment.connector_id)
	# Enumerated alternatives: stairs 28 walking cells + 50 transit ticks;
	# direct lift 48 walking cells + 50 transit ticks. S49 walks 2 cells/s.
	_check("transfer_search_beats_first_reachable_connector",result.ok and connections==["m_first","z_second"] and result.arrival_ticks==190 and result.walking_distance==28 and before==_canonical(world),result)
	world.facts.actors.actor_00.location.cell = [2.25,15]
	var fractional: Dictionary = space.route(world,"actor_00",3,[2,15])
	_check("fractional_start_time_reaches_transit_quotes",fractional.ok and fractional.arrival_ticks==192 and fractional.path[0].cell==[2,15],fractional)

func _transport_waiting(content: HospitalContent) -> void:
	var world: WorldState = _nav_world(content)
	_nav_lift(world)
	world.facts.actors.actor_00.location.cell = [10,15]
	world.facts.actors.actor_01.location = {"kind":"floor","floor_id":3,"cell":[14,15]}
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	simulation.space.request_move(world,"actor_00",3,[12,15])
	simulation.step()
	simulation.space.request_move(world,"actor_01",1,[12,15])
	for tick: int in 25:
		simulation.step()
	var connection: Dictionary = world.facts.connectors.lift
	var waiting: Dictionary = world.facts.moves.actor_01
	_check("arrived_waiter_keeps_ticket_while_clearing_exit",waiting.has("transit_ticket") and waiting.transit_ticket.sequence==2 and not simulation.space.at(world,"actor_01",3,[10,15]),{"movement":waiting,"actor":world.facts.actors.actor_01})
	var restored: WorldState = WorldState.new(world.freeze())
	var second: HospitalSimulation = HospitalSimulation.new(restored,content)
	for tick: int in 150:
		simulation.step()
		second.step()
	_check("waiting_and_empty_return_restore_exactly",_canonical(world)==_canonical(restored))
	_check("waiting_at_incoming_landing_does_not_deadlock",simulation.space.at(world,"actor_00",3,[12,15]) and simulation.space.at(world,"actor_01",1,[12,15]) and connection.ticket_next==2 and world.validate(content).is_empty(),{"actors":world.facts.actors,"moves":world.facts.moves,"connection":connection,"reason":world.validate(content)})
	var cancelled: WorldState = _nav_world(content,1)
	_nav_lift(cancelled)
	cancelled.facts.connectors.lift.floor_id = 3
	cancelled.facts.actors.actor_00.location.cell = [10,15]
	var cancel_space: HospitalSpace = HospitalSpace.new(content)
	cancel_space.request_move(cancelled,"actor_00",2,[12,15])
	cancel_space.advance(cancelled)
	var empty: Dictionary = cancelled.facts.connectors.lift
	var remaining: int = empty.remaining_ticks
	HospitalTransit.cancel_waiting(cancelled,cancelled.facts.moves.actor_00)
	cancelled.facts.moves.erase("actor_00")
	_check("cancelled_pickup_keeps_committed_empty_segment",empty.phase=="empty_riding" and empty.remaining_ticks==remaining and not empty.has("assigned_actor_id"))
	_large_arrival_waiter(content)

func _large_arrival_waiter(content: HospitalContent) -> void:
	var world: WorldState = _nav_world(content)
	_nav_lift(world,"VC03")
	world.facts.actors.actor_00.species_id = "S59"
	world.facts.actors.actor_00.location.cell = [10,15]
	world.facts.actors.actor_01.location = {"kind":"floor","floor_id":3,"cell":[16,15]}
	world.facts.floors.overrides["3"].blocked.append([9,15])
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	simulation.space.request_move(world,"actor_00",3,[16,15])
	simulation.step()
	simulation.space.request_move(world,"actor_01",1,[16,15])
	for tick: int in 220:
		simulation.step()
	_check("waiter_clears_incoming_giant_envelope",simulation.space.at(world,"actor_00",3,[16,15]) and simulation.space.at(world,"actor_01",1,[16,15]) and world.validate(content).is_empty(),{"actors":world.facts.actors,"moves":world.facts.moves,"connection":world.facts.connectors.lift,"reason":world.validate(content)})

func _check(name: String, passed: bool, details: Dictionary = {}) -> void:
	_checks[name] = passed
	if not passed:
		_failures.append(name)
		if not details.is_empty():
			print(name+" "+JSON.stringify(details))
		push_error(name)
