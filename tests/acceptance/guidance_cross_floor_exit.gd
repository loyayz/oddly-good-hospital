extends "res://tests/acceptance/floor_guidance.gd"
const Routes=preload("res://game/operations/guidance_queue_routes.gd")
const Flow=preload("res://game/operations/guidance_queue_flow.gd")

func run_exits(database: HospitalContent) -> Dictionary:
	_content=database
	var cases: Array=[_actual_exit(2),_actual_exit(3),_actual_exit(2,true),_actual_exit(3,true),_actual_exit(2,false,true),_actual_exit(3,false,true),_no_connector(),_suffix_mask()]
	var passed: bool=true
	for result: Dictionary in cases:passed=passed and result.ok
	return {"passed":passed,"cases":cases}

func _exit_fixture(source_floor: int) -> Dictionary:
	var x: Dictionary=_base(false,true)
	if source_floor==3:
		for key: String in x.world.facts.floors.completed_top_floor:x.world.facts.floors.completed_top_floor[key]=3
		x.world.facts.floors.height_intervals=[{"first":1,"last":3,"height_m":float(_content.balance.floors.clear_height_m)}]
		x.world.facts.floors.overrides["3"]={"plots":HospitalSpace.floor_plots(x.world,2).duplicate(true),"blocked":[],"doors":[],"paths":[]}
		x.world.facts.facilities.upper_guide.floor_id=3
		x.world.facts.actors.upper_nurse.location.floor_id=3
		x.world.facts.connectors.lift.stops=[1,2,3]
	var visit: Dictionary=_visit(x,"exit",[48,84])
	# Legal starting boundary of a queue departure. No queue number, completed
	# guidance receipt, physical arrival or ride is forged by this fixture.
	x.world.facts.actors[visit.actor_id].location.floor_id=source_floor
	x.world.touch()
	x.exit_visit=visit
	return x

func _actual_exit(source_floor: int, left_lift: bool=false, queue_room: bool=false) -> Dictionary:
	var x: Dictionary=_exit_fixture(source_floor)
	if left_lift:
		x.world.facts.connectors.lift.cell=[35,84]
		x.world.facts.connectors.lift.anchor=[36,88]
		x.world.facts.connectors.lift.repair_cell=[34,85]
	if queue_room:
		# Factory's starter-room builder writes floor 1. Temporarily select the
		# source floor's real layout, then restore floor 1 before any query.
		var ground_layout: Dictionary=x.world.facts.floors.overrides["1"]
		x.world.facts.floors.overrides["1"]=x.world.facts.floors.overrides[str(source_floor)]
		HospitalFactory._add_room(x.world,{"id":"departure_room","type":"gp","anchor":[45,81],"size":[10,10],"door":{"definition_id":"DR04","offset":5}},_content)
		x.world.facts.floors.overrides["1"]=ground_layout
		x.world.facts.rooms.departure_room.floor_id=source_floor
		x.world.facts.facilities.upper_guide.room_id="departure_room"
	x.world.touch()
	var expect_flow: bool=left_lift or queue_room
	var actor_id: String=x.exit_visit.actor_id
	var actor: Dictionary=x.world.facts.actors[actor_id]
	var stationary: Dictionary=_visit(x,"stationary_queue_member",[48,85])
	x.world.facts.actors[stationary.actor_id].location.floor_id=source_floor
	var stationary_before: Dictionary=x.world.facts.actors[stationary.actor_id].location.duplicate(true)
	x.world.touch()
	var no_overlap: bool=true
	var goal: Array=[40.25,88.5]
	var initial: Vector2=Vector2(actor.location.cell[0],actor.location.cell[1])
	var span: int=x.space.clearance(actor)
	var slots: Array=x.g._queue_slots(x.world,"upper_guide",span)
	var fixed: RouteClearance=x.space.navigation.structural_clearance(x.world,actor,source_floor)
	var service: Array=x.space.facility_layout(x.world,"upper_guide").patient_cell
	var expected: Array=Flow.hints(slots,span,0,initial,Vector2(goal[0],goal[1]),Vector2(service[0],service[1]),false,fixed)
	var reason: String=x.space.request_move(x.world,actor_id,1,goal)
	var initial_move: Dictionary=x.world.facts.moves.get(actor_id,{})
	if not initial_move.is_empty():initial_move.test_route_owner="cross_floor_exit_owner"
	var sequence: int=int(initial_move.get("request_sequence",-1))
	var quoted: Dictionary=Routes.quote(x.space,x.world,initial_move,1,goal) if not initial_move.is_empty() else {}
	var quoted_prefix: bool=quoted.get("ok",false) and not expected.is_empty() and quoted.path.size()>=expected.size()
	if quoted_prefix:
		for index: int in expected.size():
			var segment: Dictionary=quoted.path[index]
			quoted_prefix=quoted_prefix and segment.kind=="floor" and int(segment.floor_id)==source_floor and Vector2(segment.cell[0],segment.cell[1]).distance_to(expected[index])<0.001
	var prefix_walk: bool=false
	var ride: bool=false
	var target_preserved: bool=true
	var own: bool=true
	var same_request: bool=true
	var visited: Array=[]
	var arrived: bool=false
	for tick: int in 1800:
		x.space.advance(x.world)
		actor=x.world.facts.actors[actor_id]
		var move: Dictionary=x.world.facts.moves.get(actor_id,{})
		if not move.is_empty():
			target_preserved=target_preserved and int(move.target_floor)==1 and move.target_cell==goal
			own=own and move.get("test_route_owner","")=="cross_floor_exit_owner"
			same_request=same_request and int(move.request_sequence)==sequence
		if actor.location.kind=="transit":ride=true
		elif actor.location.kind=="floor":
			var point: Vector2=Vector2(actor.location.cell[0],actor.location.cell[1])
			if int(actor.location.floor_id)==source_floor:
				var other: Dictionary=x.world.facts.actors[stationary.actor_id]
				no_overlap=no_overlap and not x.space._actor_rect(actor,point).intersects(x.space._actor_rect(other,Vector2(other.location.cell[0],other.location.cell[1])),false)
				if point.distance_to(initial)>0.001 and point.x<initial.x-0.001:prefix_walk=true
				if visited.size()<16 and (visited.is_empty() or visited.back()!=actor.location.cell):visited.append(actor.location.cell.duplicate())
		if x.space.at(x.world,actor_id,1,goal) and move.is_empty():arrived=true;break
		x.world.facts.sim_tick+=1;x.world.touch(false)
	var flow_count: int=int(x.space.query_counts.get("guidance_cross_floor_exits",0))
	var flow_ok: bool=(quoted_prefix and prefix_walk and flow_count>0) if expect_flow else (quoted.is_empty() and flow_count==0)
	var variant: String="ROOM-TAIL-DOOR" if queue_room else "LEFT-LIFT" if left_lift else "RIGHT-LIFT-SAFE-FALLBACK"
	var result: Dictionary={"case":"ACTUAL-EXIT-"+str(source_floor)+"-TO-1-"+variant,"ok":reason.is_empty() and flow_ok and ride and arrived and target_preserved and own and same_request and no_overlap and x.world.facts.actors[stationary.actor_id].location==stationary_before,"expected_flow":expect_flow,"flow_or_safe_fallback":flow_ok,"request_reason":reason,"quoted_prefix":quoted_prefix,"walked_left_from_queue":prefix_walk,"actual_transit":ride,"arrived_fractional_goal":arrived,"target_preserved":target_preserved,"owner_preserved":own,"same_request":same_request,"stationary_member_unchanged":x.world.facts.actors[stationary.actor_id].location==stationary_before,"no_overlap_with_stationary_member":no_overlap,"first_positions":visited,"final_location":actor.location.duplicate(true),"remaining_move":x.world.facts.moves.get(actor_id,{}).duplicate(true),"flow_quotes":x.space.query_counts.get("guidance_cross_floor_exits",0),"fixture_scope":"legal queue-departure boundary; real movement and transit, not admission"}
	_dispose(x);return result

func _no_connector() -> Dictionary:
	var x: Dictionary=_exit_fixture(2)
	x.world.facts.connectors.clear();x.world.touch()
	var id: String=x.exit_visit.actor_id
	var before: Dictionary=x.world.facts.actors[id].duplicate(true)
	var result: Dictionary=Routes.quote(x.space,x.world,{"actor_id":id,"members":[id]},1,[40,88])
	var row: Dictionary={"case":"NO-CONNECTOR-FALLBACK","ok":result.is_empty() and x.world.facts.actors[id]==before,"quote":result}
	_dispose(x);return row

func _suffix_mask() -> Dictionary:
	var x: Dictionary=_exit_fixture(2)
	var mask: Rect2=Rect2(48,84,1,10)
	var safe: Array=[{"kind":"floor","floor_id":2,"cell":[47,94]},{"kind":"floor","floor_id":2,"cell":[59,94]},{"kind":"floor","floor_id":2,"cell":[59,88]},{"kind":"connector","connector_id":"lift","from":2,"to":1},{"kind":"floor","floor_id":1,"cell":[48,85]}]
	var blocked: Array=[{"kind":"floor","floor_id":2,"cell":[49,85]}]
	var checks: Dictionary={"safe_source_other_floor_overlap":Routes._source_suffix_outside(x.world,safe,2,Vector2(47,94),1,mask),"source_cross_rejected":not Routes._source_suffix_outside(x.world,blocked,2,Vector2(47,85),1,mask)}
	var row: Dictionary={"case":"SUFFIX-MASK-PURE","ok":checks.safe_source_other_floor_overlap and checks.source_cross_rejected,"checks":checks}
	_dispose(x);return row
