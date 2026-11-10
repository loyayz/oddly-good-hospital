extends RefCounted

class ObservedMovement extends HospitalMovement:
	var intended: Array=[]
	var blocked: Array=[]
	var cursor_kept_on_contact: bool=true
	var future_body_probes: int=0
	var fixed_exit_checks: int=0
	func _init(geometry: HospitalSpace) -> void: super(geometry)
	func _move_step(world: WorldState, actor: Dictionary, movement: Dictionary, segment: Dictionary) -> MotionResult:
		var point: Array=movement.get("local_move",{}).get("rejoin",{}).get("cell",[]).duplicate()
		if actor.id=="walker" and not point.is_empty() and (intended.is_empty() or intended.back()!=point): intended.append(point)
		var result: MotionResult=super._move_step(world,actor,movement,segment)
		if actor.id=="walker" and result.blocked and not point.is_empty(): blocked.append(point)
		return result
	func _local_collision(world: WorldState, actor: Dictionary, movement: Dictionary, contact: MotionResult) -> void:
		var cursor: int=int(movement.cursor)
		super._local_collision(world,actor,movement,contact)
		cursor_kept_on_contact=cursor_kept_on_contact and int(movement.cursor)==cursor
	func _local_path_clear(world: WorldState, actor: Dictionary, path: Array, query: RouteClearance = null) -> bool:
		if path.size()>1: future_body_probes+=1
		return super._local_path_clear(world,actor,path,query)
	func _local_side_exit(world: WorldState, actor: Dictionary, movement: Dictionary, side: Vector2, fixed: Array) -> bool:
		fixed_exit_checks+=1
		return super._local_side_exit(world,actor,movement,side,fixed)

func run(content: HospitalContent) -> Dictionary:
	var suite: RefCounted=load("res://tests/acceptance/space.gd").new()
	suite.content=content
	var rows: Array=[_sequence(suite,false),_sequence(suite,true),_sequence(suite,false,true),_fixed_contact(suite),_retreat_axis(suite)]
	return {"ok":rows.all(func(row: Dictionary)->bool: return row.ok),"cases":rows}

func _sequence(suite: RefCounted, compressed: bool, bend: bool = false) -> Dictionary:
	var sim: HospitalSimulation=suite._fixture()
	suite._add_actor(sim,"walker","S49",[40,71])
	suite._add_actor(sim,"B","S49",[41,70])
	suite._add_actor(sim,"C","S49",[42,70])
	var path: Array=[]
	var goal: Array=[45,69] if bend else [45,70]
	for cell: Array in ([[45,70]] if compressed else [[41,70],[42,70],[42,69],[45,69]] if bend else [[41,70],[42,70],[43,70],[45,70]]):
		path.append({"kind":"floor","floor_id":1,"cell":cell})
	# Legal boundary after a side step; all return attempts and arrivals below
	# execute real movement. The route cursor has earned no progress yet.
	sim.world.facts.move_request_next=1
	sim.world.facts.moves["walker"]={"actor_id":"walker","path":path.duplicate(true),"cursor":0,"travelled":[{"kind":"floor","floor_id":1,"cell":[40,70]}],"blocked_since":-1,"target_floor":1,"target_cell":goal.duplicate(),"request_sequence":1,"local_move":{"origin":[40,70],"target":{"kind":"floor","floor_id":1,"cell":[40,71]}}}
	sim.world.touch()
	var initial: String=sim.world.validate(suite.content)
	var observer:=ObservedMovement.new(sim.space)
	sim.space.movement=observer
	var probe: RefCounted=load("res://tests/acceptance/movement_detour.gd").new()
	var errors: Array=[]
	var fixed: bool=true
	var original: bool=true
	var restored: Dictionary={}
	var ticks: int=0
	for tick: int in 180:
		var error: String=probe._tick(suite,sim,["walker","B","C"])
		ticks=tick+1
		if not error.is_empty(): errors.append(error);break
		fixed=fixed and sim.space.at(sim.world,"B",1,[41,70]) and sim.space.at(sim.world,"C",1,[42,70]) and not sim.world.facts.moves.has("B") and not sim.world.facts.moves.has("C")
		var move: Dictionary=sim.world.facts.moves.get("walker",{})
		if move.is_empty(): break
		original=original and move.path==path and move.target_cell==goal and int(move.request_sequence)==1 and not move.get("route_pending",false)
		if restored.is_empty() and observer.blocked.size()>=2:
			restored=probe._restore_boundary(suite,sim,"walker",["walker","B","C"])
	var arrived: bool=not sim.world.facts.moves.has("walker") and sim.space.at(sim.world,"walker",1,goal)
	var order: bool=observer.intended.size()>=3 and ConvoyTrail.point(observer.intended[0])==Vector2(41,70) and ConvoyTrail.point(observer.intended[1])==Vector2(42,70) and ConvoyTrail.point(observer.intended[2])==(Vector2(42,69) if bend else Vector2(43,70))
	var actual_contacts: bool=observer.blocked.any(func(point: Array)->bool: return ConvoyTrail.point(point)==Vector2(41,70)) and observer.blocked.any(func(point: Array)->bool: return ConvoyTrail.point(point)==Vector2(42,70))
	var checks: Dictionary={"initial_valid":initial.is_empty(),"arrived":arrived,"safe_real_steps":errors.is_empty(),"B_C_D_order":order,"B_C_actual_contacts":actual_contacts,"cursor_not_advanced_by_attempt":observer.cursor_kept_on_contact,"original_request_and_path":original,"fixed_actors_kept":fixed,"no_future_body_probe":observer.future_body_probes==0,"restore":restored.get("ok",false)}
	var result: Dictionary={"case":"bent_route_B_C_D" if bend else "compressed_B_C_D" if compressed else "B_C_D","ok":checks.values().all(func(value: Variant)->bool: return value==true),"checks":checks,"initial_validation":initial,"errors":errors,"intended":observer.intended,"blocked":observer.blocked,"restored":restored,"ticks":ticks,"remaining":sim.world.facts.moves.duplicate(true)}
	sim.dispose()
	return result

func _fixed_contact(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation=suite._fixture()
	suite._add_actor(sim,"walker","S49",[42,70.8])
	suite._add_actor(sim,"B","S49",[42,70])
	var path: Array=[]
	for y: int in [70,69,68]:path.append({"kind":"floor","floor_id":1,"cell":[42,y]})
	sim.world.facts.move_request_next=1
	sim.world.facts.moves["walker"]={"actor_id":"walker","path":path,"cursor":0,"travelled":[{"kind":"floor","floor_id":1,"cell":[42,71]}],"blocked_since":-1,"target_floor":1,"target_cell":[42,68],"request_sequence":1,"local_move":{"origin":[42,71],"target":path[0].duplicate(true),"rejoin":{"index":0,"cell":[42,70]}}}
	sim.world.touch()
	var initial: String=sim.world.validate(suite.content)
	var observer:=ObservedMovement.new(sim.space)
	sim.space.movement=observer
	var probe: RefCounted=load("res://tests/acceptance/movement_detour.gd").new()
	var errors: Array=[]
	for tick: int in 120:
		var error: String=probe._tick(suite,sim,["walker","B"])
		if not error.is_empty():errors.append(error);break
		if sim.world.facts.moves.is_empty():break
	var arrived: bool=not sim.world.facts.moves.has("walker") and sim.space.at(sim.world,"walker",1,[42,68])
	var checks: Dictionary={"initial_valid":initial.is_empty(),"arrived":arrived,"safe_real_steps":errors.is_empty(),"fixed_exit_used":observer.fixed_exit_checks>0,"fixed_body_kept":sim.space.at(sim.world,"B",1,[42,70]) and not sim.world.facts.moves.has("B"),"contact_keeps_cursor":observer.cursor_kept_on_contact,"no_future_body_probe":observer.future_body_probes==0}
	var result: Dictionary={"case":"fixed_contact_after_rejoin_attempt","ok":checks.values().all(func(value: Variant)->bool:return value==true),"checks":checks,"errors":errors,"fixed_exit_checks":observer.fixed_exit_checks}
	sim.dispose()
	return result

func _retreat_axis(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation=suite._fixture()
	var x: float=40.0000038146973
	suite._add_actor(sim,"walker","S49",[x,70.8])
	suite._add_actor(sim,"left","S49",[x-0.8,70.8])
	suite._add_actor(sim,"right","S49",[x+0.8,70.8])
	suite._add_actor(sim,"front","S49",[x,71.6])
	sim.world.facts.move_request_next=1
	sim.world.facts.moves["walker"]={"actor_id":"walker","path":[{"kind":"floor","floor_id":1,"cell":[x,75.0]}],"cursor":0,"travelled":[{"kind":"floor","floor_id":1,"cell":[40.0,69.8]}],"blocked_since":-1,"target_floor":1,"target_cell":[x,75.0],"request_sequence":1}
	sim.world.touch()
	var initial: String=sim.world.validate(suite.content)
	var probe: RefCounted=load("res://tests/acceptance/movement_detour.gd").new()
	var errors: Array=[]
	var retreat_seen: bool=false
	var exact_axis: bool=true
	var backward: bool=false
	for tick: int in 3:
		var before: Vector2=ConvoyTrail.point(sim.world.facts.actors.walker.location.cell)
		var error: String=probe._tick(suite,sim,["walker","left","right","front"])
		if not error.is_empty():errors.append(error);break
		var actor: Dictionary=sim.world.facts.actors.walker
		var local: Dictionary=sim.world.facts.moves.get("walker",{}).get("local_move",{})
		if local.get("retreat",false):
			retreat_seen=true
			exact_axis=exact_axis and ConvoyTrail.point(local.target.cell).x==ConvoyTrail.point(actor.location.cell).x
		backward=backward or float(actor.location.cell[1])<before.y
	var checks: Dictionary={"initial_valid":initial.is_empty(),"actual_contact_and_retreat":retreat_seen,"actual_backward_step":backward,"exact_axis":exact_axis,"safe_real_steps":errors.is_empty(),"current_restore_valid":WorldState.new(sim.world.freeze()).validate(suite.content).is_empty()}
	var result: Dictionary={"case":"binary32_history_retreat_axis","ok":checks.values().all(func(value: Variant)->bool:return value==true),"checks":checks,"errors":errors,"remaining":sim.world.facts.moves.get("walker",{}).get("local_move",{})}
	sim.dispose()
	return result
