extends RefCounted

class ObserveMovement extends HospitalMovement:
	var cursor_only_on_arrival: bool=true
	var first_intent: Array=[]
	var first_connector: Array=[]
	var future_body_probes: int=0
	func _init(geometry: HospitalSpace) -> void: super(geometry)
	func _local_resume(world: WorldState, actor: Dictionary, movement: Dictionary) -> bool:
		var cursor: int=int(movement.cursor)
		var link: Dictionary=movement.local_move.get("rejoin",{}).duplicate(true)
		var result: bool=super._local_resume(world,actor,movement)
		if int(movement.cursor)!=cursor:
			cursor_only_on_arrival=cursor_only_on_arrival and not link.is_empty() and ConvoyTrail.point(actor.location.cell)==ConvoyTrail.point(link.cell)
		return result
	func _move_step(world: WorldState, actor: Dictionary, movement: Dictionary, segment: Dictionary) -> MotionResult:
		if actor.id=="walker" and first_intent.is_empty() and movement.get("local_move",{}).has("rejoin"):
			first_intent=movement.local_move.rejoin.cell.duplicate()
			first_connector=movement.local_move.target.cell.duplicate()
		return super._move_step(world,actor,movement,segment)
	func _local_path_clear(world: WorldState, actor: Dictionary, path: Array, query: RouteClearance=null) -> bool:
		if path.size()>1: future_body_probes+=1
		return super._local_path_clear(world,actor,path,query)

func run(content: HospitalContent, selected: Array) -> Dictionary:
	var suite: RefCounted=load("res://tests/acceptance/space.gd").new()
	suite.content=content
	var rows: Array=[]
	for id: String in selected:
		if id not in ["RETURN-EARLIER-SIDE","RETURN-EARLIER-RETREAT","RETURN-TARGET-GEOMETRY","RETURN-MOVING-INTENT"]:
			rows.append({"case":id,"ok":false,"error":"Unknown case"})
		else: rows.append(_case(suite,id))
	return {"ok":not rows.is_empty() and rows.all(func(row: Dictionary)->bool:return row.ok),"cases":rows}

func _point(cell: Array) -> Dictionary:
	return {"kind":"floor","floor_id":1,"cell":cell.duplicate()}

func _case(suite: RefCounted, id: String) -> Dictionary:
	var started: int=Time.get_ticks_usec()
	var sim: HospitalSimulation=suite._fixture()
	var moving: bool=id=="RETURN-MOVING-INTENT"
	var target_geometry: bool=id in ["RETURN-TARGET-GEOMETRY","RETURN-MOVING-INTENT"]
	var retreat: bool=id=="RETURN-EARLIER-RETREAT"
	var start: Array=[41.8,69] if target_geometry else [40,70] if retreat else [40,71]
	var origin: Array=[40.8,73] if target_geometry else [41,70] if retreat else [40,70]
	var goal: Array=[40.5,73] if target_geometry else [48,80]
	var path: Array=[_point(goal)] if target_geometry else [_point([42,70] if retreat else [41,70]),_point([42,78] if retreat else [41,78]),_point([48,78]),_point(goal)]
	var rectangles: Array[Rect2]=[]
	if target_geometry:
		HospitalFactory._add_facility(sim.world,{"id":"desk","definition_id":"FUR05","anchor":[40,72],"size":[2,1],"room_id":null},suite.content)
		rectangles.append(Rect2(40,72,2,1))
	else:
		HospitalFactory._add_facility(sim.world,{"id":"right_obstacle","definition_id":"FUR05","anchor":[48,74],"size":[1,2],"room_id":null},suite.content)
		sim.world.facts.facilities["right_obstacle"].rotation=1
		HospitalFactory._add_facility(sim.world,{"id":"bottom_obstacle","definition_id":"FUR05","anchor":[44,80],"size":[2,1],"room_id":null},suite.content)
		rectangles.assign([Rect2(48,74,1,2),Rect2(44,80,2,1)])
	suite._add_actor(sim,"walker","S49",start)
	var actor: Dictionary=sim.world.facts.actors["walker"]
	actor.facing=-PI/2.0 if retreat else 0.0
	var local: Dictionary={"origin":origin.duplicate(),"target":_point(start),"rejoin":{"index":path.size()-1,"cell":goal.duplicate()}}
	if retreat: local.retreat=true
	sim.world.facts.move_request_next=1
	sim.world.facts.moves["walker"]={"actor_id":"walker","path":path.duplicate(true),"cursor":0,"travelled":[_point(origin)],"blocked_since":-1,"target_floor":1,"target_cell":goal.duplicate(),"request_sequence":1,"local_move":local}
	var future_occupied: bool=false
	if moving:
		suite._add_actor(sim,"traveller","S49",[39.5,73])
		sim.world.facts.move_request_next=2
		sim.world.facts.moves["traveller"]={"actor_id":"traveller","path":[_point([38,73])],"cursor":0,"travelled":[_point([39.5,73])],"blocked_since":-1,"target_floor":1,"target_cell":[38,73],"request_sequence":2}
		var body: Rect2=sim.space.body_rectangle(sim.world.facts.actors["traveller"])
		future_occupied=BodySweep.intersects(sim.space._actor_rect(actor,Vector2(39,73)),sim.space._actor_rect(actor,ConvoyTrail.point(goal)),body,body)
	sim.world.touch()
	var initial: String=sim.world.validate(suite.content)
	var query: RouteClearance=sim.space.navigation.structural_clearance(sim.world,actor,1)
	var from: Vector2=ConvoyTrail.point(start)
	var to: Vector2=ConvoyTrail.point(goal)
	var simple_blocked: bool=true
	for corner: Vector2 in [Vector2(to.x,from.y),Vector2(from.x,to.y)]:
		simple_blocked=simple_blocked and (not query.sweep_reason(from,corner).is_empty() or not query.sweep_reason(corner,to).is_empty())
	var prepared: int=Time.get_ticks_usec()
	var observer:=ObserveMovement.new(sim.space)
	sim.space.movement=observer
	var probe: RefCounted=load("res://tests/acceptance/movement_detour.gd").new()
	var errors: Array=[]
	var original: bool=true
	var restored: Dictionary={}
	var trace: Array=[]
	var ticks: int=0
	for tick: int in 180:
		var before: Rect2=sim.space.body_rectangle(actor)
		var error: String=probe._tick(suite,sim,["walker","traveller"] if moving else ["walker"])
		if not error.is_empty(): errors.append(error);break
		var after: Rect2=sim.space.body_rectangle(actor)
		for obstacle: Rect2 in rectangles:
			if after.intersects(obstacle,false) or BodySweep.intersects(before,after,obstacle,obstacle): errors.append("Static body/sweep overlap")
		var move: Dictionary=sim.world.facts.moves.get("walker",{})
		original=original and (move.is_empty() or move.path==path and move.target_cell==goal and int(move.request_sequence)==1 and not move.get("route_pending",false))
		if tick==0 and not move.is_empty(): restored=probe._restore_boundary(suite,sim,"walker",["walker","traveller"] if moving else ["walker"])
		if tick%10==0: trace.append({"tick":tick,"cell":actor.location.cell.duplicate(),"local":move.get("local_move",{}).duplicate(true),"cursor":move.get("cursor",-1)})
		ticks=tick+1
		if move.is_empty() or not errors.is_empty(): break
	var arrived: bool=not sim.world.facts.moves.has("walker") and sim.space.at(sim.world,"walker",1,goal)
	var expected_first: Array=goal if target_geometry else path[0].cell
	var first_matches: bool=observer.first_intent.size()==2 and ConvoyTrail.point(observer.first_intent)==ConvoyTrail.point(expected_first)
	var checks: Dictionary={"initial_valid":initial.is_empty(),"two_simple_links_blocked":simple_blocked,"selected_unearned_point":first_matches,"arrived":arrived,"real_body_and_sweep_safe":errors.is_empty(),"original_route_and_request":original,"cursor_only_on_arrival":observer.cursor_only_on_arrival,"no_future_body_preflight":observer.future_body_probes==0,"no_floor_rejoin_search":int(sim.space.query_counts.get("rejoin_component_queries",0))==0,"restore":restored.get("ok",false),"final_valid":sim.world.validate(suite.content).is_empty()}
	if moving:
		checks.future_leg_initially_occupied=future_occupied
		checks.moving_body_does_not_veto_connector=observer.first_connector.size()==2 and ConvoyTrail.point(observer.first_connector)==Vector2(39,69)
		checks.other_actor_really_walked=not sim.world.facts.moves.has("traveller") and sim.space.at(sim.world,"traveller",1,[38,73])
	var result: Dictionary={"case":id,"ok":checks.values().all(func(value: Variant)->bool:return value==true),"checks":checks,"fixture_us":prepared-started,"test_us":Time.get_ticks_usec()-prepared,"initial_validation":initial,"ticks":ticks,"first_intent":observer.first_intent,"first_connector":observer.first_connector,"errors":errors,"trace":trace,"restored":restored}
	sim.dispose()
	return result
