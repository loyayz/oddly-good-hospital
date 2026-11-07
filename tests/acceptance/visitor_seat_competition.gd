extends "res://tests/acceptance/guided_waiting_yield.gd"

var competition_safe: int = -1
var competition_boundaries: Dictionary = {}

# Select one physical case. --input restores an immutable pre-trip boundary;
# otherwise build the named pre-guidance fixture and execute its real approach.
func run_competition(database: HospitalContent, output: String, input: String = "", restore_trip: bool = false) -> Dictionary:
	_content = database
	var x: Dictionary
	var setup: bool = true
	if input.is_empty():
		x = _base()
		_facility(x,"far_chair","FUR09",[55,92])
		var initial: Dictionary = _visit(x,"real_standing",[40,88])
		x.world.touch()
		var ready: int = -1
		for i: int in 800:
			step(x)
			setup = setup and x.world.validate(_content).is_empty()
			if x.g.state(x.world,initial.id).get("phase","")=="ready" and ready<0: ready=x.world.sim_tick
			if ready>=0 and x.world.sim_tick-ready>=180: break
		setup = setup and ready>=0
		setup = setup and BuildService.new(_content,x.space).execute(x.world,"build_facility",{"id":"race_chair","definition_id":"FUR09","floor_id":1,"cell":[44,80]}).accepted
		setup = setup and BuildService.new(_content,x.space).execute(x.world,"build_demolish",{"target_id":"far_chair"}).accepted
		setup = setup and x.c.visitors._admit(x.world,initial,{"purpose":"companion","window":""})
	else:
		var facts: Dictionary = FileAccess.open(input,FileAccess.READ).get_var(true)
		x = _guide_bind(WorldState.new(facts))
		setup = x.world.freeze()==facts
	var patient: Dictionary = x.world.facts.visits.real_standing
	var visitor: Dictionary = x.c.visitors._present(x.world,patient.id)
	var ticket: String = patient.ticket_id
	var enqueue: int = x.world.facts.tickets[ticket].enqueued_tick
	var sequence: int = x.g.state(x.world,patient.id).arrived_seq
	var arrival: int = int(visitor.public_use.arrived_tick)
	var checks: Dictionary = {"legal_setup":setup and x.world.validate(_content).is_empty(),"all_steps_valid":true,"no_overlap":true,"only_actual_owner":true,"no_walking_reservation":true,"no_failed_seat_queue":true,"first_safe_boundary_stops":true,"restore_exact":not restore_trip}
	_save(x,output+"-input.bin")
	var trip_tick: int = -1
	var win_tick: int = -1
	var stop_tick: int = -1
	var first_safe: int = -1
	var trace: Array = []
	var boundaries: Dictionary = {}
	var restored: bool = false
	for i: int in 250:
		var prior: Dictionary = x.world.facts.moves.get(visitor.actor_id,{})
		var cancellable: bool = win_tick>=0 and _ordinary_trip(x,visitor,prior)
		if cancellable and first_safe<0: first_safe=x.world.sim_tick
		_competition_step(x)
		if competition_safe>=0: first_safe=competition_safe
		var movement: Dictionary = x.world.facts.moves.get(visitor.actor_id,{})
		var intent: Dictionary = visitor.public_use
		var owned: bool = movement.get("waiting_seat_id","")==intent.id
		if owned and intent.facility_id=="race_chair" and trip_tick<0:
			trip_tick=x.world.sim_tick
			arrival=int(intent.arrived_tick)
			_save(x,output+"-tagged-trip.bin")
			if restore_trip:
				var frozen: Dictionary = x.world.freeze()
				_dispose(x)
				x=_guide_bind(WorldState.new(frozen))
				patient=x.world.facts.visits.real_standing
				visitor=x.c.visitors._present(x.world,patient.id)
				checks.restore_exact=x.world.freeze()==frozen and x.world.facts.moves[visitor.actor_id].waiting_seat_id==visitor.public_use.id
				restored=true
		if HospitalWaitingLife.is_seated(x.world,patient.id) and win_tick<0:
			win_tick=x.world.sim_tick
			_save(x,output+"-winner.bin")
			boundaries=competition_boundaries
		if win_tick>=0 and not _targets_chair(x,movement) and stop_tick<0: stop_tick=x.world.sim_tick
		if cancellable: checks.first_safe_boundary_stops=checks.first_safe_boundary_stops and not _targets_chair(x,movement) and intent.facility_id!="race_chair"
		var owner: String = str(x.world.facts.adaptations.get("race_chair",{}).get("actor_id",""))
		if not owner.is_empty():
			checks.only_actual_owner=checks.only_actual_owner and x.space.at(x.world,owner,1,x.space.facility_layout(x.world,"race_chair").patient_cell) and x.world.facts.actors[owner].posture=="seated"
		if owned: checks.no_walking_reservation=checks.no_walking_reservation and owner!=visitor.actor_id
		var a: Dictionary=x.world.facts.actors[patient.actor_id]
		var b: Dictionary=x.world.facts.actors[visitor.actor_id]
		if a.location.kind=="floor" and b.location.kind=="floor" and a.location.floor_id==b.location.floor_id:
			checks.no_overlap=checks.no_overlap and not x.space.body_rectangle(a).intersects(x.space.body_rectangle(b),false)
		checks.all_steps_valid=checks.all_steps_valid and x.world.validate(_content).is_empty()
		var patient_intent: Dictionary=x.world.facts.waiting_life.seats.get(patient.id,{})
		checks.no_failed_seat_queue=checks.no_failed_seat_queue and not x.space.public_areas._wait_results.has(str(patient_intent.get("id",""))) and not x.space.public_areas._wait_dependencies.waiters.has(str(patient_intent.get("id",""))) and not x.space.public_areas._wait_results.has(str(intent.id)) and not x.space.public_areas._wait_dependencies.waiters.has(str(intent.id)) and x.space.public_areas.turn(x.world,intent,"race_chair")
		if i%5==0 or x.world.sim_tick==win_tick or x.world.sim_tick==stop_tick:
			trace.append({"tick":x.world.sim_tick,"visitor_phase":intent.phase,"visitor_target":intent.facility_id,"visitor_location":b.location.duplicate(true),"owner":owner,"owned_move":owned})
		if win_tick>=0 and x.world.sim_tick-win_tick>=40: break
	checks.real_contention=trip_tick>=0 and win_tick>trip_tick
	checks.visitor_stops=stop_tick>=win_tick and first_safe>=0 and stop_tick==first_safe+1
	checks.no_stale_intent=visitor.public_use.facility_id!="race_chair" and visitor.public_use.phase=="local_wait"
	checks.ticket_and_arrival_preserved=patient.ticket_id==ticket and int(x.world.facts.tickets[ticket].enqueued_tick)==enqueue and int(x.g.state(x.world,patient.id).arrived_seq)==sequence and int(visitor.public_use.arrived_tick)==arrival
	checks.handoff_boundaries=not boundaries.is_empty() and boundaries.values().all(func(value:Variant)->bool:return bool(value))
	if restore_trip: checks.fresh_runtime_used=restored
	_save(x,output+"-final.bin")
	var result: Dictionary={"ok":checks.values().all(func(value:Variant)->bool:return bool(value)),"case":"VISITOR-SEAT-RESTORE" if restore_trip else "VISITOR-SEAT-LOST","checks":checks,"handoff_boundaries":boundaries,"trip_tick":trip_tick,"win_tick":win_tick,"first_safe_dispatch_tick":first_safe,"stop_tick":stop_tick,"trace":trace,"input":input,"tick_seconds":WorldState.TICK_SECONDS,"validation":x.world.validate(_content)}
	_dispose(x)
	return result

func _competition_step(x: Dictionary) -> void:
	# Same production stage order as step(), observed at the actual patient ->
	# visitor handoff, before the repaired visitor can cancel within this tick.
	x.g.dispatch(x.world)
	x.l.dispatch(x.world)
	x.p.dispatch(x.world)
	var patient: Dictionary=x.world.facts.visits.real_standing
	var visitor: Dictionary=x.c.visitors._present(x.world,patient.id)
	if HospitalWaitingLife.is_seated(x.world,patient.id) and competition_boundaries.is_empty():
		competition_boundaries=_handoff_boundaries(x,visitor)
		if _ordinary_trip(x,visitor,x.world.facts.moves.get(visitor.actor_id,{})): competition_safe=x.world.sim_tick
	x.c.dispatch(x.world)
	x.space.advance(x.world)
	x.c.advance(x.world)
	x.p.advance(x.world)
	x.g.advance(x.world)
	x.l.advance(x.world)
	x.a.advance_wait(x.world)
	x.p.sample(x.world)
	x.a.clinic=x.c
	x.a.environment=x.e
	x.a.needs(x.world)
	x.world.facts.sim_tick += 1
	x.world.touch(false)

func _save(x: Dictionary, path: String) -> void:
	FileAccess.open(path,FileAccess.WRITE).store_var(x.world.freeze(),true)

func _targets_chair(x: Dictionary, movement: Dictionary) -> bool:
	return not movement.is_empty() and int(movement.target_floor)==1 and movement.target_cell==x.space.facility_layout(x.world,"race_chair").patient_cell

func _ordinary_trip(x: Dictionary, visitor: Dictionary, movement: Dictionary) -> bool:
	if not _targets_chair(x,movement) or movement.get("waiting_seat_id","")!=visitor.public_use.id: return false
	if movement.has("detour") or movement.has("convoy") or movement.get("members",[visitor.actor_id])!=[visitor.actor_id]: return false
	if x.world.facts.actors[visitor.actor_id].location.kind!="floor": return false
	return int(movement.cursor)>=movement.path.size() or movement.path[int(movement.cursor)].kind!="support_exit"

func _handoff_boundaries(x: Dictionary, visitor: Dictionary) -> Dictionary:
	# Isolated, legal before-operation snapshots. Production requests perform
	# both ownership handoffs; no positions, arrival, motion or work are injected.
	var checks: Dictionary = {}
	for mode: String in ["same_endpoint","different_endpoint","untagged_legacy"]:
		var candidate: Dictionary = _guide_bind(WorldState.new(x.world.freeze()))
		var stay: Dictionary=candidate.world.facts.visitors.stays[visitor.id]
		var move: Dictionary=candidate.world.facts.moves.get(visitor.actor_id,{})
		if move.is_empty():
			checks[mode]=false
			_dispose(candidate)
			continue
		var reason: String = ""
		if mode=="untagged_legacy":
			# Metadata-only compatibility input, never inferred to be our trip.
			move.erase("waiting_seat_id")
		else:
			var target: Array = move.target_cell if mode=="same_endpoint" else [47,90]
			reason=candidate.space.request_move(candidate.world,stay.actor_id,int(move.target_floor),target)
		var before: Dictionary=candidate.world.freeze()
		candidate.c.visitors._stop_lost_seat_trip(candidate.world,stay)
		checks[mode]=reason.is_empty() and candidate.world.validate(_content).is_empty() and before==candidate.world.freeze() and not move.has("waiting_seat_id")
		_dispose(candidate)
	return checks
