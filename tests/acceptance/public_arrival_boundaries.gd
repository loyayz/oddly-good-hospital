extends "res://tests/acceptance/public_area_use.gd"

func run_boundaries(database: HospitalContent) -> Dictionary:
	_content = database
	var rows: Array = [_geometry(),_compact_entries(),_fractional_entry(),_fallback_waypoint(),_roomless(),_cross_floor()]
	return {"ok":rows.all(func(row: Dictionary)->bool:return row.ok),"cases":rows}

func _fractional_entry() -> Dictionary:
	var x: Dictionary = _fixture()
	HospitalFactory._add_room(x.world,{"id":"west","type":"rest","anchor":[34,66],"size":[10,12],"door":{"definition_id":"DR05","offset":3}},_content)
	var actor: Dictionary = {"id":"fractional_probe","name":"fractional_probe","species_id":"S02","facing":0.0,"posture":"standing","location":{"kind":"floor","floor_id":1,"cell":[38,81],"height_m":0.0}}
	for binding: Dictionary in _content.catalog.treatment_bindings:
		if binding.species_id==actor.species_id: actor.body_binding_id=binding.id;break
	x.world.facts.actors[actor.id]=actor;x.world.touch()
	var predecessor: Array = []
	# Both requests finish through ordinary movement. The second request has
	# only a diagonal departure stub, which leaves the real body across the
	# region boundary despite the integer origin being inside it.
	for target: Array in [[38.2,77.2],[38,77]]:
		predecessor.append(_walk_entry_leg(x,actor.id,target,100))
	x.space.public_areas._ensure(x.world,1)
	var area: Dictionary = x.space.public_areas._cell_region(1,Vector2i(38,76)).ref
	var initially_outside: bool = not x.space.public_areas.contains(x.world,area,actor.id)
	var initial_facing: float = float(actor.facing)
	var before: Dictionary = x.world.freeze()
	var selected: Dictionary = x.space.public_areas.arrival_point(x.world,actor.id,area)
	var readonly: bool = before==x.world.freeze()
	var legs: Array = []
	for _leg: int in 4:
		if x.space.public_areas.contains(x.world,area,actor.id): break
		var point: Dictionary = x.space.public_areas.arrival_point(x.world,actor.id,area)
		if point.is_empty(): break
		legs.append(_walk_entry_leg(x,actor.id,point.cell,100))
	var checks: Dictionary = {"real_predecessor":predecessor.all(func(row: Dictionary)->bool:return row.ok and int(row.steps)>0),"actual_boundary_pose":initially_outside and absf(sin(initial_facing))>0.1 and absf(cos(initial_facing))>0.1,"read_only_quote":readonly,"no_zero_distance_false_arrival":not selected.is_empty() and int(selected.travel_ticks)>0,"actual_full_body_arrival":not legs.is_empty() and legs.all(func(row: Dictionary)->bool:return row.ok and int(row.steps)>1) and x.space.public_areas.contains(x.world,area,actor.id),"valid_world":x.world.validate(_content).is_empty(),"no_full_order":int(x.space.query_counts.get("entry_order_builds",0))==0}
	x.a.dispose()
	return {"case":"fractional_stub_then_real_entry","ok":checks.values().all(func(v: Variant)->bool:return v==true),"checks":checks,"predecessor":predecessor,"entry":selected,"legs":legs}

func _walk_entry_leg(x: Dictionary, actor_id: String, target: Array, limit: int) -> Dictionary:
	var reason: String = x.space.request_move(x.world,actor_id,1,target)
	var steps: int = 0
	for _tick: int in limit:
		if not x.world.facts.moves.has(actor_id): break
		x.space.advance(x.world);x.world.facts.sim_tick+=1;x.world.touch(false);steps+=1
	return {"ok":reason.is_empty() and not x.world.facts.moves.has(actor_id),"reason":reason,"steps":steps,"target":target.duplicate(),"actual":x.world.facts.actors[actor_id].location.cell.duplicate()}

func _fallback_waypoint() -> Dictionary:
	var rows: Array = []
	for foreign: bool in [false,true]:
		var x: Dictionary = _areas()
		var visit: Dictionary = _visit(x,"waypoint",[37,78])
		var actor: Dictionary = x.world.facts.actors[visit.actor_id]
		var blocker: Dictionary = actor.duplicate(true)
		blocker.id="waypoint_blocker";blocker.name="waypoint_blocker";blocker.location.cell=[42,90]
		x.world.facts.actors[blocker.id]=blocker;x.space.sync_actor(x.world,blocker.id);x.world.touch(false)
		var unsafe: bool = not x.space.public_areas.safe_wait(x.world,actor.id,1,actor.location.cell)
		x.l._begin_need(x.world,visit)
		var need: Dictionary = x.world.facts.waiting_life.needs[visit.id]
		var start: int = int(need.started_tick)
		var pending: bool = need.phase=="fallback_travel" and need.remaining_ticks==0
		# A legitimate safety trip may have a distant static waypoint which
		# becomes occupied. The movement and safe intermediate arrival below
		# are real; no fallback work or position is supplied by this fixture.
		var reason: String = x.l._request_need_move(x.world,need,actor.id,1,[42,90])
		if foreign and x.world.facts.moves.has(actor.id): x.world.facts.moves[actor.id].waiting_need_id="another_task"
		var safe_seen: bool = false
		var completion: bool = false
		var steps: int = 0
		for _tick: int in 100:
			x.world.facts.sim_tick+=1
			x.l._dispatch_need(x.world,visit,need)
			var safe: bool = x.space.public_areas.safe_wait(x.world,actor.id,1,actor.location.cell)
			if safe:
				safe_seen=true
				completion=need.phase=="fallback_travel" and x.world.facts.moves.has(actor.id) and need.remaining_ticks==0 if foreign else need.phase=="fallback" and not x.world.facts.moves.has(actor.id) and need.remaining_ticks==80
				break
			x.space.advance(x.world);x.world.touch(false);steps+=1
		var checks: Dictionary = {"unsafe_input_and_real_pending_need":unsafe and pending,"real_safety_journey":reason.is_empty() and steps>0,"actual_safe_intermediate_position":safe_seen and actor.location.cell!=[37,78] and actor.location.cell!=[42,90],"correct_owner_controls_completion":completion,"original_clock_kept":int(need.started_tick)==start,"valid_world":x.world.validate(_content).is_empty()}
		rows.append({"foreign":foreign,"ok":checks.values().all(func(v: Variant)->bool:return v==true),"checks":checks,"steps":steps,"actual":actor.location.cell.duplicate(),"phase":need.phase,"remaining_ticks":need.remaining_ticks})
		x.a.dispose()
	return {"case":"safe_fallback_before_busy_waypoint","ok":rows.all(func(row: Dictionary)->bool:return row.ok),"variants":rows}

func _compact_entries() -> Dictionary:
	var rows: Array = []
	for side: int in [4,3]:
		var x: Dictionary = _fixture()
		HospitalFactory._add_room(x.world,{"id":"compact","type":"rest","anchor":[34,66],"size":[side,side],"door":{"definition_id":"DR05","offset":0}},_content)
		var actor: Dictionary = {"id":"compact_probe","name":"compact_probe","species_id":"S11","body_binding_id":"","facing":PI/4.0,"posture":"standing","location":{"kind":"floor","floor_id":1,"cell":[35,76],"height_m":0.0}}
		for binding: Dictionary in _content.catalog.treatment_bindings:
			if binding.species_id==actor.species_id: actor.body_binding_id=binding.id;break
		x.world.facts.actors[actor.id]=actor
		x.space.sync_actor(x.world,actor.id);x.world.touch()
		x.space.public_areas._ensure(x.world,1)
		var area: Dictionary = x.space.public_areas._cell_region(1,Vector2i(35,67)).ref
		var initial_valid: String = x.world.validate(_content)
		var before: Dictionary = x.world.freeze()
		var known_route: Dictionary = x.space.travel_quote(x.world,actor.id,1,[35,67])
		var point: Dictionary = x.space.public_areas.arrival_point(x.world,actor.id,area)
		var readonly: bool = before==x.world.freeze()
		var initial_facing_fits: bool = not point.is_empty() and x.space.public_areas._contains_point(actor,x.space.public_areas.region(x.world,area),Vector2(point.cell[0],point.cell[1]))
		var reason: String = x.space.request_move(x.world,actor.id,1,point.cell) if not point.is_empty() else "no ingress"
		var steps: int = 0
		for _tick: int in 180:
			if not x.world.facts.moves.has(actor.id): break
			x.space.advance(x.world);x.world.facts.sim_tick+=1;x.world.touch(false);steps+=1
		var checks: Dictionary = {"legal_input_and_output":initial_valid.is_empty() and x.world.validate(_content).is_empty(),"known_legal_route_not_rejected":known_route.get("ok",false) and not point.is_empty(),"read_only_quote":readonly,"actual_full_body_arrival":reason.is_empty() and steps>0 and not x.world.facts.moves.has(actor.id) and x.space.public_areas.contains(x.world,area,actor.id),"departure_facing_not_required":side!=3 or not initial_facing_fits,"no_full_order":int(x.space.query_counts.get("entry_order_builds",0))==0}
		rows.append({"side":side,"ok":checks.values().all(func(v: Variant)->bool:return v==true),"checks":checks,"point":point,"steps":steps,"final":actor.location.cell.duplicate(),"final_facing":actor.facing})
		x.a.dispose()
	return {"case":"compact_rooms_and_departure_facing","ok":rows.all(func(row: Dictionary)->bool:return row.ok),"variants":rows,"scope":"Valid 4x4 and 3x3 rooms, real 0.1-second movements from a diagonal departure pose; no manufactured arrival."}

func _geometry() -> Dictionary:
	var x: Dictionary = _areas()
	var visit: Dictionary = _visit(x,"geometry",[38,90])
	var actor: Dictionary = x.world.facts.actors[visit.actor_id]
	var area: Dictionary = x.space.public_areas.for_facility(x.world,"west_chair")
	var rows: Array = []
	for spec: Array in [["S49",0.0,"standing"],["S02",0.0,"standing"],["S02",PI/4.0,"standing"],["S49",0.0,"seated"]]:
		actor.species_id = spec[0];actor.body_binding_id = "";actor.facing = spec[1];actor.posture = spec[2]
		x.space.sync_actor(x.world,actor.id);x.world.touch(false)
		var before: Dictionary = x.world.freeze()
		var point: Dictionary = x.space.public_areas.arrival_point(x.world,actor.id,area)
		var cold: Dictionary = HospitalSpace.new(_content).public_areas.arrival_point(x.world,actor.id,area)
		var route: Dictionary = x.space.travel_quote(x.world,actor.id,1,point.cell) if not point.is_empty() else {}
		rows.append({"species":spec[0],"facing":spec[1],"posture":spec[2],"ok":not point.is_empty() and point==cold and route.get("ok",false) and point.travel_ticks==route.travel_ticks and before==x.world.freeze(),"point":point})
	actor.species_id = "S49";actor.posture = "standing";actor.facing = 0.0
	x.space.sync_actor(x.world,actor.id);x.world.touch(false)
	var original: Dictionary = x.space.public_areas.arrival_point(x.world,actor.id,area)
	var doors: Array = x.world.facts.floors.overrides["1"].doors.duplicate(true)
	var removed: Array = doors.filter(func(door: Dictionary)->bool:return door.room_id!="west")
	x.world.facts.floors.overrides["1"].doors = removed;x.world.touch()
	var absent: Dictionary = x.space.public_areas.arrival_point(x.world,actor.id,area)
	x.world.facts.floors.overrides["1"].doors = doors;x.world.touch()
	var restored: Dictionary = x.space.public_areas.arrival_point(x.world,actor.id,area)
	var no_cells: bool = x.space.public_areas._entry_geometry.values().all(func(g: Dictionary)->bool:return not g.has("cells") and not g.has("entry_cells"))
	var checks: Dictionary = {"body_facing_posture_matches_cold":rows.all(func(row: Dictionary)->bool:return row.ok),"removed_door_not_reused":absent.is_empty(),"restored_door_rebuilt":original==restored and not restored.is_empty(),"no_copied_or_sorted_area_cells":no_cells and int(x.space.query_counts.get("entry_order_builds",0))==0,"query_scopes_closed":x.space._route_queries.is_empty()}
	x.a.dispose()
	return {"case":"cold_body_and_structural_invalidation","ok":checks.values().all(func(v: Variant)->bool:return v==true),"checks":checks,"variants":rows,"scope":"Declared independent body/posture input variants and real static door removal/restoration; read-only quotes, not four physical mutation journeys."}

func _roomless() -> Dictionary:
	var x: Dictionary = _areas()
	var visit: Dictionary = _visit(x,"lobby",[38,74])
	var lobby: Dictionary = x.space.public_areas.current_area(x.world,visit.actor_id)
	x.space.public_areas.region(x.world,lobby)
	lobby = x.space.public_areas._cell_region(1,Vector2i(38,90)).ref
	var point: Dictionary = x.space.public_areas.arrival_point(x.world,visit.actor_id,lobby)
	var reason: String = x.space.request_move(x.world,visit.actor_id,1,point.cell) if not point.is_empty() else "no ingress"
	var moved: bool = false
	for tick: int in 300:
		if not x.world.facts.moves.has(visit.actor_id): break
		var before: Array = x.world.facts.actors[visit.actor_id].location.cell.duplicate()
		x.space.advance(x.world);x.world.facts.sim_tick += 1;x.world.touch(false)
		moved = moved or before!=x.world.facts.actors[visit.actor_id].location.cell
	var final: Array = x.world.facts.actors[visit.actor_id].location.cell
	var checks: Dictionary = {"roomless_area":lobby.room_id=="","real_departure":reason.is_empty() and moved,"actual_lobby_arrival":x.space.public_areas.contains(x.world,lobby,visit.actor_id) and not x.world.facts.moves.has(visit.actor_id),"safe_local_wait":x.space.public_areas.safe_wait(x.world,visit.actor_id,1,final),"no_full_order":int(x.space.query_counts.get("entry_order_builds",0))==0}
	x.a.dispose()
	return {"case":"room_to_roomless_lobby","ok":checks.values().all(func(v: Variant)->bool:return v==true),"checks":checks,"point":point,"final":final}

func _cross_floor() -> Dictionary:
	var x: Dictionary = _areas()
	var visit: Dictionary = _visit(x,"upper",[40.35,90.35])
	var plots: Array = HospitalSpace.floor_plots(x.world,1).duplicate(true)
	x.world.facts.floors.completed_top_floor = {}
	for plot: Array in plots: x.world.facts.floors.completed_top_floor[HospitalSpace.plot_key(plot)] = 2
	x.world.facts.floors.height_intervals = [{"first":1,"last":2,"height_m":float(_content.balance.floors.clear_height_m)}]
	x.world.facts.floors.overrides["2"] = {"plots":plots,"blocked":[],"doors":[],"paths":[]}
	x.world.facts.actors[visit.actor_id].location.floor_id = 2
	x.world.facts.connectors["lift"] = {"id":"lift","definition_id":"VC02","stops":[1,2],"cell":[58,84],"footprint":[4,4],"rotation":0,"anchor":[59,88],"repair_cell":[57,85],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0,"ticket_next":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},"paid_cost":3200,"used":false}
	x.world.touch();x.m.ensure(x.world)
	var area: Dictionary = x.space.public_areas.for_facility(x.world,"west_chair")
	var input_valid: String = x.world.validate(_content)
	var before: Dictionary = x.world.freeze()
	var point: Dictionary = x.space.public_areas.arrival_point(x.world,visit.actor_id,area)
	var exact: Dictionary = x.space.route(x.world,visit.actor_id,1,point.cell,[],{},true) if not point.is_empty() else {}
	var below: Dictionary = x.space.public_areas.arrival_point(x.world,visit.actor_id,area,int(point.get("travel_ticks",0))-1)
	var equality: Dictionary = x.space.public_areas.arrival_point(x.world,visit.actor_id,area,int(point.get("travel_ticks",0)))
	var readonly: bool = before==x.world.freeze()
	var reason: String = x.space.request_move(x.world,visit.actor_id,1,point.cell) if not point.is_empty() else "no ingress"
	if reason.is_empty(): x.world.facts.moves[visit.actor_id].waiting_seat_id = "cross_arrival"
	var transit_seen: bool = false
	var protected: bool = true
	var restored: bool = false
	var steps: int = 0
	for tick: int in 1200:
		if not x.world.facts.moves.has(visit.actor_id): break
		x.space.advance(x.world);x.world.facts.sim_tick += 1;x.world.touch(false);steps += 1
		if x.world.facts.actors[visit.actor_id].location.kind=="transit":
			transit_seen = true
			var frozen: Dictionary = x.world.freeze()
			protected = protected and not x.space.public_areas.try_finish_arrival(x.world,visit.actor_id,area,"waiting_seat_id","cross_arrival") and frozen==x.world.freeze()
			if not restored:
				x.a.dispose();x = _restore(x)
				visit = x.world.facts.visits[visit.id]
				restored = frozen==x.world.freeze() and x.world.facts.moves[visit.actor_id].waiting_seat_id=="cross_arrival"
	var checks: Dictionary = {"input_valid":input_valid.is_empty(),"quote_matches_complete_route":exact.get("ok",false) and not point.is_empty() and exact.travel_ticks==point.travel_ticks,"own_ingress_budget_boundary":below.is_empty() and equality==point,"read_only":readonly,"actual_cross_floor_arrival":reason.is_empty() and transit_seen and x.space.public_areas.contains(x.world,area,visit.actor_id) and not x.world.facts.moves.has(visit.actor_id),"transit_not_cancelled":protected,"in_transit_save_restore":restored,"no_full_order":int(x.space.query_counts.get("entry_order_builds",0))==0}
	x.a.dispose()
	return {"case":"fractional_cross_floor_and_saved_transit","ok":checks.values().all(func(v: Variant)->bool:return v==true),"checks":checks,"validation":input_valid,"point":point,"actual_steps":steps}
