extends RefCounted

# Explicit local-detour inputs followed by real movement ticks. No location,
# arrival, or service completion is written by these tests after setup.
func _point(x: float,y: float) -> Dictionary:
	return {"kind":"floor","floor_id":1,"cell":[x,y]}

func run(suite: RefCounted) -> Dictionary:
	var rows: Array=[_fixed_desk_return_l(suite),_static_successor(suite),_fractional_target(suite),_trail_boundary(suite),_back_interrupted(suite),_back_interrupted(suite,true)]
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
	var dispatch_before: int=int(sim.space.query_counts.get("route_dispatches",0))
	# Subdivide the still-unwalked straight route into equivalent floor
	# checkpoints, then declare a new static obstacle at its nearest checkpoint.
	move.path=[_point(40,70),_point(41,70),_point(45,70)];move.cursor=0
	sim.world.facts.floors.overrides["1"].blocked.append([40,70]);sim.world.touch()
	var input_validation: String=sim.world.validate(suite.content)
	sim.space.movement._start_detour(sim.world,sim.world.facts.actors.walker,move)
	var helper: RefCounted=load("res://tests/acceptance/movement_detour.gd").new()
	var errors: Array=[];var side_seen: bool=false;var passed_obstacle: bool=false;var steps: int=0
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
			if int(active.request_sequence)<sequence or active.target_cell!=[45,70] or int(active.target_floor)!=1: errors.append("original goal changed");break
			passed_obstacle=passed_obstacle or float(actor.location.cell[0])>=41.0
		if active.is_empty(): break
	var arrived: bool=sim.space.at(sim.world,"walker",1,[45,70]) and not sim.world.facts.moves.has("walker")
	var extra_dispatches: int=int(sim.space.query_counts.get("route_dispatches",0))-dispatch_before
	var row: Dictionary={"case":"static_nearest_successor","ok":request.is_empty() and input_validation.is_empty() and errors.is_empty() and side_seen and passed_obstacle and arrived and extra_dispatches<=1,"additional_route_dispatches":extra_dispatches,"input_validation":input_validation,"errors":errors,"side_seen":side_seen,"passed_obstacle":passed_obstacle,"arrived":arrived,"ticks":steps}
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
	var held_ticks: int=0;var preserved: bool=true;var released: bool=false
	var valid_observations: int=0;var first_change: Dictionary={};var pending_trace: Array=[]
	var errors: Array=[];var rear_requested: bool=false;var back_seen: bool=false;var back_interrupted: bool=false;var side_after_interrupt: bool=false
	var original_sequence: int=sim.world.facts.moves.walker.request_sequence
	var trace: Array=[]
	for tick: int in 260:
		var before: Vector2=ConvoyTrail.point(sim.world.facts.actors.walker.location.cell)
		var before_move: Dictionary=sim.world.facts.moves.get("walker",{})
		var was_back: bool=before_move.has("detour") and before_move.detour.phase=="back" and int(before_move.cursor)<int(before_move.detour.prefix_size)
		var pending_before: Dictionary={}
		var all_blocked: bool=false
		if sealed and was_back:
			pending_before={"path":before_move.path.duplicate(true),"cursor":before_move.cursor,"backtrack":before_move.detour.backtrack.duplicate(true),"back_cursor":before_move.detour.back_cursor,"phase":before_move.detour.phase}
			var target: Vector2=ConvoyTrail.point(before_move.path[int(before_move.cursor)].cell)
			var motion: Vector2=target-before
			var axis: Vector2=Vector2(signf(motion.x),0) if absf(motion.x)>=absf(motion.y) else Vector2(0,signf(motion.y))
			var side: Vector2=Vector2(-axis.y,axis.x)*float(sim.space.clearance(sim.world.facts.actors.walker))
			var next: Vector2=sim.space.movement._step_toward(before,target,sim.space.walking_speed(sim.world.facts.actors.walker)*WorldState.TICK_SECONDS)
			all_blocked=true
			for point: Vector2 in [next,before+side,before-side]:
				if sim.space.movement._detour_path_clear(sim.world,sim.world.facts.actors.walker,before_move,[_point(point.x,point.y)]):all_blocked=false
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
		if sealed and not pending_before.is_empty():
			var pending_after: Dictionary={}
			if move.has("detour"):
				pending_after={"path":move.path.duplicate(true),"cursor":move.cursor,"backtrack":move.detour.backtrack.duplicate(true),"back_cursor":move.detour.back_cursor,"phase":move.detour.phase}
			var still_back: bool=move.has("detour") and move.detour.phase=="back" and int(move.cursor)<int(move.detour.prefix_size)
			var observe: bool=all_blocked and now==before and still_back
			if observe:
				valid_observations+=1
				preserved=preserved and pending_before==pending_after
			if first_change.is_empty() and pending_before!=pending_after:
				first_change={"tick":tick,"before":pending_before,"after":pending_after,"position_before":before,"position_after":now,"rear":sim.world.facts.actors.rear.location.cell.duplicate(),"all_blocked_before":all_blocked,"qualified_observation":observe}
			pending_trace.append({"tick":tick,"all_blocked_before":all_blocked,"stationary":now==before,"still_back":still_back,"qualified":observe,"pending_equal":pending_before==pending_after})
		if sealed and back_interrupted and not released:
			held_ticks+=1
			# Ten ticks schedule real side-body departure only, not a claim
			# that the mobile rear actor remained an obstruction throughout.
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
	var result: Dictionary={"case":"blocked_retreat_preserves_pending_leg_until_sides_clear" if sealed else "third_actor_interrupts_active_backtrack","ok":(not sealed or (preserved and valid_observations>0 and released)) and request.is_empty() and errors.is_empty() and back_seen and back_interrupted and side_after_interrupt and arrived and rear_arrived,"errors":errors,"pending_leg_preserved":preserved,"valid_blocked_observations":valid_observations,"first_pending_change":first_change,"pending_tick_trace":pending_trace,"held_ticks":held_ticks,"back_seen":back_seen,"back_interrupted":back_interrupted,"side_after_interrupt":side_after_interrupt,"walker_arrived":arrived,"rear_arrived":rear_arrived,"trace":trace}
	sim.dispose();return result

func _fixed_desk_return_l(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation=suite._fixture()
	HospitalFactory._add_facility(sim.world,{"id":"return_desk","definition_id":"SE01","anchor":[47,83],"size":[2,1],"room_id":null},suite.content)
	suite._add_actor(sim,"return_walker","S49",[46.4,84])
	var request: String=sim.space.request_move(sim.world,"return_walker",1,[47,82])
	suite._movement_tick(sim)
	var movement: Dictionary=sim.world.facts.moves.get("return_walker",{})
	if movement.is_empty():
		sim.dispose();return {"case":"fixed_desk_return_l_replans_same_goal","ok":false,"reason":"no initial movement"}
	# Explicit mid-detour regression input from the failed nurse handoff:
	# the future L is an intention, not static permission. From here onward
	# all locations and route changes are production movement results.
	movement.guidance_nurse_desk="return_desk"
	movement.path=[_point(47,84),_point(47,82)]
	movement.cursor=0
	movement.detour={"original_path":[_point(46,82),_point(47,82)],"direction":[1.0,0.0],"phase":"rejoin","prefix_size":2,"resume_index":1,"backtrack":movement.travelled.duplicate(true),"back_cursor":movement.travelled.size()-1}
	var original_sequence: int=int(movement.request_sequence)
	var helper: RefCounted=load("res://tests/acceptance/movement_detour.gd").new()
	var errors: Array=[]
	var replanned: bool=false
	var pending_after_static: bool=false
	var max_history: int=0
	var steps: int=0
	for tick: int in 250:
		var error: String=helper._tick(suite,sim,["return_walker"])
		steps=tick+1
		if not error.is_empty():errors.append(error);break
		var actor: Dictionary=sim.world.facts.actors.return_walker
		if sim.space.body_rectangle(actor).intersects(Rect2(47,83,2,1),false):errors.append("crossed fixed desk body");break
		var active: Dictionary=sim.world.facts.moves.get(actor.id,{})
		if active.is_empty():break
		if active.get("guidance_nurse_desk","")!="return_desk" or int(active.target_floor)!=1 or Vector2(float(active.target_cell[0]),float(active.target_cell[1]))!=Vector2(47,82):errors.append("movement goal or owner lost");break
		replanned=replanned or int(active.request_sequence)>original_sequence
		pending_after_static=pending_after_static or (active.get("route_pending",false) and not active.has("detour"))
		max_history=maxi(max_history,active.get("travelled",[]).size())
	var arrived: bool=sim.space.at(sim.world,"return_walker",1,[47,82]) and not sim.world.facts.moves.has("return_walker")
	var result: Dictionary={"case":"fixed_desk_return_l_replans_same_goal","ok":request.is_empty() and errors.is_empty() and replanned and pending_after_static and arrived,"actual_static_replan_observed":pending_after_static,"new_route_request":replanned,"same_goal_arrived":arrived,"errors":errors,"ticks":steps,"maximum_history":max_history,"input_scope":"explicit failed-L continuation, not a claimed complete nurse journey"}
	sim.dispose();return result
