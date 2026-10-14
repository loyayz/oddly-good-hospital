extends SceneTree

var _checks: Dictionary = {}
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
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
	var path: String = "res://.cache/validation/stage03-kernel-rules.json"
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
	var target: int = 12000 if surgical else 1800
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

func _canonical(world: WorldState) -> String:
	return JSON.stringify(world.facts,"",true,true)

func _check(name: String, passed: bool) -> void:
	_checks[name] = passed
	if not passed:
		_failures.append(name)
		push_error(name)
