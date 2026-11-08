extends RefCounted

# Explicit local-detour inputs followed by real movement ticks. No location,
# arrival, or service completion is written by these tests after setup.
func _point(x: float,y: float) -> Dictionary:
	return {"kind":"floor","floor_id":1,"cell":[x,y]}

func run(suite: RefCounted) -> Dictionary:
	var rows: Array=[_static_successor(suite),_fractional_target(suite),_trail_boundary(suite),_back_interrupted(suite),_back_interrupted(suite,true)]
	# Existing production support-exit fixture includes real departure, a newly
	# obstructed exit, bounded steps, posture handoff and original-goal completion.
	var support: Dictionary=load("res://tests/acceptance/movement_review.gd").new()._ready_support_exit(suite)
	rows.append({"case":"existing_real_support_exit","ok":support.ok,"details":support})
	var ok: bool=true
	for row: Dictionary in rows: ok=ok and bool(row.ok)
	return {"ok":ok,"cases":rows,"scope":"Incremental movement and predicate boundaries; cross-floor travelled requires a separate actual transit fixture and is not claimed covered here."}

func _static_successor(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation=suite._fixture()
	suite._add_actor(sim,"walker","S49",[35,70])
	var request: String=sim.space.request_move(sim.world,"walker",1,[45,70])
	suite._movement_tick(sim)
	var move: Dictionary=sim.world.facts.moves.get("walker",{})
	if move.is_empty():
		sim.dispose();return {"case":"static_nearest_successor","ok":false,"reason":"request did not produce movement"}
	var sequence: int=move.request_sequence
	# Subdivide the still-unwalked straight route into equivalent floor
	# checkpoints, then declare a new static obstacle at its nearest checkpoint.
	move.path=[_point(40,70),_point(41,70),_point(45,70)];move.cursor=0
	sim.world.facts.floors.overrides["1"].blocked.append([40,70]);sim.world.touch()
	var input_validation: String=sim.world.validate(suite.content)
	sim.space.movement._start_detour(sim.world,sim.world.facts.actors.walker,move)
	var helper: RefCounted=load("res://tests/acceptance/movement_detour.gd").new()
	var errors: Array=[];var side_seen: bool=false;var successor_seen: bool=false;var steps: int=0
	for tick: int in 250:
		var error: String=helper._tick(suite,sim,["walker"])
		if not error.is_empty(): errors.append(error);break
		steps=tick+1
		var actor: Dictionary=sim.world.facts.actors.walker
		var rect: Rect2=sim.space.body_rectangle(actor)
		if rect.intersects(Rect2(40,70,1,1),false): errors.append("crossed static obstacle");break
		side_seen=side_seen or not is_equal_approx(float(actor.location.cell[1]),70.0)
		var active: Dictionary=sim.world.facts.moves.get("walker",{})
		if not active.is_empty():
			if active.request_sequence!=sequence or active.target_cell!=[45,70]: errors.append("original request changed");break
			if active.has("detour") and active.detour.phase=="rejoin": successor_seen=successor_seen or int(active.detour.resume_index)>0
		if active.is_empty(): break
	var arrived: bool=sim.space.at(sim.world,"walker",1,[45,70]) and not sim.world.facts.moves.has("walker")
	var row: Dictionary={"case":"static_nearest_successor","ok":request.is_empty() and input_validation.is_empty() and errors.is_empty() and side_seen and successor_seen and arrived,"input_validation":input_validation,"errors":errors,"side_seen":side_seen,"successor_seen":successor_seen,"arrived":arrived,"ticks":steps}
	sim.dispose();return row

func _fractional_target(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation=suite._fixture()
	suite._add_actor(sim,"walker","S49",[35,70])
	sim.world.facts.floors.overrides["1"].blocked.append([41,70]);sim.world.touch()
	var actor: Dictionary=sim.world.facts.actors.walker
	var query: RouteClearance=sim.space.navigation.structural_clearance(sim.world,actor,1)
	var before: Dictionary=sim.world.freeze()
	# Integer truncation at (40,70) misses the adjacent static cell. This is a
	# decision boundary only, not a fabricated arrival at the fractional goal.
	var rejected: bool=not sim.space.movement._return_link_can_start(sim.world,actor,{"actor_id":"walker"},[_point(40.25,70)],query)
	var discriminates: bool=query.reason(Vector2i(40,70)).is_empty() and not query.position_reason(Vector2(40.25,70)).is_empty()
	var readonly: bool=before==sim.world.freeze()
	var request: String=sim.space.request_move(sim.world,"walker",1,[35,72.25])
	var helper: RefCounted=load("res://tests/acceptance/movement_detour.gd").new()
	var errors: Array=[]
	for tick: int in 120:
		var error: String=helper._tick(suite,sim,["walker"])
		if not error.is_empty(): errors.append(error);break
		if not sim.world.facts.moves.has("walker"): break
	var arrived: bool=sim.space.at(sim.world,"walker",1,[35,72.25]) and not sim.world.facts.moves.has("walker")
	var row: Dictionary={"case":"fractional_target_static_and_actual_safe_arrival","ok":rejected and discriminates and readonly and request.is_empty() and errors.is_empty() and arrived,"fractional_obstacle_rejected":rejected,"integer_vs_fractional_discriminates":discriminates,"readonly":readonly,"errors":errors,"safe_fractional_arrived":arrived}
	sim.dispose();return row

# Pure retained-checkpoint projection, not a claim that transit occurred here.
func _trail_boundary(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation=suite._fixture()
	var old: Dictionary=_point(10,10)
	var foreign: Dictionary=_point(20,20);foreign.floor_id=2
	var current: Dictionary=_point(30,30)
	var last: Dictionary=_point(31,30)
	var movement: Dictionary={"travelled":[old,foreign,current,last]}
	var before: Dictionary=current.duplicate(true)
	var history: Array=sim.space.movement._local_travelled(movement,1)
	var same: bool=history==[current,last]
	history[0].cell[0]=999
	var readonly: bool=current==before
	var other: Array=sim.space.movement._local_travelled(movement,2)
	sim.dispose()
	return {"case":"continuous_floor_trail_projection","ok":same and readonly and other.is_empty(),"last_visit_only":same,"deep_copy":readonly,"not_current_floor_empty":other.is_empty(),"scope":"Projection boundary only; no fabricated completed A-B-A travel."}

func _back_interrupted(suite: RefCounted, sealed: bool=false) -> Dictionary:
	var sim: HospitalSimulation=suite._fixture()
	suite._add_actor(sim,"walker","S49",[39.4,70])
	suite._add_actor(sim,"rear","S49",[37,70])
	var request: String=sim.space.request_move(sim.world,"walker",1,[45,70])
	suite._movement_tick(sim)
	suite._add_actor(sim,"front","S49",[40.2,70])
	suite._add_actor(sim,"left","S49",[39.6,69.3])
	suite._add_actor(sim,"right","S49",[39.6,70.7])
	var helper: RefCounted=load("res://tests/acceptance/movement_detour.gd").new()
	var ids: Array=["walker","rear","front","left","right"]
	if sealed:
		suite._add_actor(sim,"low","S49",[38.6,69.3]);suite._add_actor(sim,"high","S49",[38.6,70.7]);ids.append_array(["low","high"])
	var held: Dictionary={};var held_ticks: int=0;var preserved: bool=true;var released: bool=false
	var errors: Array=[];var rear_requested: bool=false;var back_seen: bool=false;var back_interrupted: bool=false;var side_after_interrupt: bool=false
	var original_sequence: int=sim.world.facts.moves.walker.request_sequence
	var trace: Array=[]
	for tick: int in 260:
		var before: Vector2=ConvoyTrail.point(sim.world.facts.actors.walker.location.cell)
		var before_move: Dictionary=sim.world.facts.moves.get("walker",{})
		var was_back: bool=before_move.has("detour") and before_move.detour.phase=="back" and int(before_move.cursor)<int(before_move.detour.prefix_size)
		var error: String=helper._tick(suite,sim,ids)
		if not error.is_empty():errors.append(error);break
		var move: Dictionary=sim.world.facts.moves.get("walker",{})
		var now: Vector2=ConvoyTrail.point(sim.world.facts.actors.walker.location.cell)
		if move.has("detour") and move.detour.phase=="back" and int(move.cursor)<int(move.detour.prefix_size):
			back_seen=true
			if not rear_requested:
				var reason: String=sim.space.request_move(sim.world,"rear",1,[38.8,70])
				if not reason.is_empty():errors.append(reason);break
				rear_requested=true
		if was_back and rear_requested and now==before and now.x<39.4:back_interrupted=true
		if sealed and back_interrupted and not released:
			var pending: Dictionary={"path":move.path.duplicate(true),"cursor":move.cursor,"backtrack":move.detour.backtrack.duplicate(true),"back_cursor":move.detour.back_cursor,"phase":move.detour.phase}
			if held.is_empty():held=pending
			else:preserved=preserved and held==pending
			held_ticks+=1
			if held_ticks==10:
				for pair: Array in [["low",[38.6,67]],["high",[38.6,73]]]:
					var release_reason: String=sim.space.request_move(sim.world,pair[0],1,pair[1])
					if not release_reason.is_empty():errors.append(release_reason)
				released=true
		if back_interrupted and absf(now.y-70)>0.1:side_after_interrupt=true
		if not move.is_empty() and move.request_sequence!=original_sequence:errors.append("original request changed");break
		if tick%10==0:trace.append({"tick":tick,"walker":now,"rear":sim.world.facts.actors.rear.location.cell.duplicate(),"phase":move.get("detour",{}).get("phase","")})
		if move.is_empty() and not sim.world.facts.moves.has("rear"):break
	var arrived: bool=sim.space.at(sim.world,"walker",1,[45,70]) and not sim.world.facts.moves.has("walker")
	var rear_arrived: bool=sim.space.at(sim.world,"rear",1,[38.8,70]) and not sim.world.facts.moves.has("rear")
	var result: Dictionary={"case":"blocked_retreat_preserves_pending_leg_until_sides_clear" if sealed else "third_actor_interrupts_active_backtrack","ok":(not sealed or (preserved and held_ticks==10 and released)) and request.is_empty() and errors.is_empty() and back_seen and back_interrupted and side_after_interrupt and arrived and rear_arrived,"errors":errors,"pending_leg_preserved":preserved,"held_ticks":held_ticks,"back_seen":back_seen,"back_interrupted":back_interrupted,"side_after_interrupt":side_after_interrupt,"walker_arrived":arrived,"rear_arrived":rear_arrived,"trace":trace}
	sim.dispose();return result
