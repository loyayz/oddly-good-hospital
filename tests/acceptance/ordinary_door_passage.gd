extends RefCounted
var suite=preload("res://tests/acceptance/space.gd").new()
func run_passage(content: HospitalContent)->Dictionary:
	suite.content=content
	var cases: Array=[_wide(),_narrow(),_remodel(),_expanded_owner()]
	return {"passed":not cases.any(func(r: Dictionary)->bool:return not r.ok),"cases":cases}
func _setup(wide: bool)->Dictionary:
	var sim: HospitalSimulation=suite._fixture()
	var draft: Dictionary=suite._room("passage",[45,70],[8,8])
	draft.door.definition_id="DR04" if wide else "DR01"
	var build: CommandResult=suite._command(sim,"build_room",draft)
	var doors: Array=suite._doors(sim.world,"passage")
	return {"sim":sim,"built":build.accepted,"door":doors[0] if not doors.is_empty() else {}}
func _touching(sim: HospitalSimulation, id: String, door: Dictionary)->bool:
	return sim.space.body_rectangle(sim.world.facts.actors[id]).intersects(sim.space._door_rect(door,int(door.span)),false)
func _wide()->Dictionary:
	var f: Dictionary=_setup(true);var sim: HospitalSimulation=f.sim;var w: WorldState=sim.world;var door: Dictionary=f.door
	if door.is_empty():sim.dispose();return {"case":"two_lanes_real_opposite_passage","ok":false,"build":f.built}
	var xx: int=int(door.cell[0]);var yy: int=int(door.cell[1])
	suite._add_actor(sim,"out","S49",[xx,yy-2]);suite._add_actor(sim,"in","S49",[xx+1,yy+3])
	var before_used: bool=bool(door.get("used",false))
	var a: String=sim.space.request_move(w,"out",1,[xx,yy+3])
	var b: String=sim.space.request_move(w,"in",1,[xx+1,yy-3])
	var no_early: bool=not before_used and not bool(door.get("used",false))
	var no_overlap: bool=true;var simultaneous: bool=false;var no_reservation: bool=true;var no_premature: bool=true;var physical_seen: bool=false;var busy_seen: bool=false
	var trace: Array=[]
	for tick: int in 100:
		var old_a: Rect2=sim.space.body_rectangle(w.facts.actors.out);var old_b: Rect2=sim.space.body_rectangle(w.facts.actors["in"])
		suite._movement_tick(sim)
		var ra: Rect2=sim.space.body_rectangle(w.facts.actors.out);var rb: Rect2=sim.space.body_rectangle(w.facts.actors["in"])
		var aperture: Rect2=sim.space._door_rect(door,int(door.span))
		physical_seen=physical_seen or old_a.merge(ra).intersects(aperture,false) or old_b.merge(rb).intersects(aperture,false)
		no_premature=no_premature and (not bool(door.get("used",false)) or physical_seen)
		no_overlap=no_overlap and not ra.intersects(rb,false)
		simultaneous=simultaneous or (_touching(sim,"out",door) and _touching(sim,"in",door))
		no_reservation=no_reservation and not w.facts.adaptations.has(door.id)
		if _touching(sim,"out",door) or _touching(sim,"in",door):
			busy_seen=busy_seen or sim.services.remodel._waiting_view(w).occupied_door_rooms.has("passage")
			trace.append({"tick":tick,"out":w.facts.actors.out.location.cell.duplicate(),"in":w.facts.actors["in"].location.cell.duplicate(),"used":door.get("used",false),"adaptation":w.facts.adaptations.get(door.id,{})})
		if not w.facts.moves.has("out") and not w.facts.moves.has("in"):break
	var arrived: bool=sim.space.at(w,"out",1,[xx,yy+3]) and sim.space.at(w,"in",1,[xx+1,yy-3])
	var validation: String=w.validate(suite.content)
	var row: Dictionary={"case":"two_lanes_real_opposite_passage","ok":f.built and int(door.span)==2 and a.is_empty() and b.is_empty() and arrived and no_overlap and simultaneous and no_reservation and no_early and no_premature and bool(door.get("used",false)) and busy_seen and validation.is_empty(),"arrived":arrived,"both_bodies_in_door_same_step":simultaneous,"no_overlap":no_overlap,"no_exclusive_reservation":no_reservation,"no_early_use":no_early and no_premature,"used_after_actual_crossing":door.get("used",false),"physical_door_seen_by_remodel":busy_seen,"requests":[a,b],"trace":trace,"validation":validation}
	sim.dispose();return row
func _narrow()->Dictionary:
	var f: Dictionary=_setup(false);var sim: HospitalSimulation=f.sim;var w: WorldState=sim.world;var door: Dictionary=f.door
	if door.is_empty():sim.dispose();return {"case":"single_lane_no_passing_through_body","ok":false}
	var xx: int=int(door.cell[0]);var yy: int=int(door.cell[1])
	suite._add_actor(sim,"blocker","S49",[xx,yy]);suite._add_actor(sim,"walker","S49",[xx,yy-2])
	var reason: String=sim.space.request_move(w,"walker",1,[xx,yy+3])
	var safe: bool=true;var crossed: bool=false
	for tick: int in 80:
		suite._movement_tick(sim)
		safe=safe and not sim.space.body_rectangle(w.facts.actors.walker).intersects(sim.space.body_rectangle(w.facts.actors.blocker),false)
		crossed=crossed or float(w.facts.actors.walker.location.cell[1])>yy+1
	var row: Dictionary={"case":"single_lane_no_passing_through_body","ok":f.built and int(door.span)==1 and safe and not crossed and sim.space.at(w,"blocker",1,[xx,yy]) and w.validate(suite.content).is_empty(),"no_overlap":safe,"crossed_stationary_body":crossed,"request":reason,"walker":w.facts.actors.walker.location.duplicate(true),"movement":w.facts.moves.get("walker",{}).duplicate(true)}
	sim.dispose();return row
func _remodel()->Dictionary:
	var f: Dictionary=_setup(true);var sim: HospitalSimulation=f.sim;var w: WorldState=sim.world;var door: Dictionary=f.door
	if door.is_empty():sim.dispose();return {"case":"actual_unreserved_door_body_blocks_remodel","ok":false}
	var xx: int=int(door.cell[0]);var yy: int=int(door.cell[1])
	suite._add_actor(sim,"walker","S49",[xx,yy+2])
	var reason: String=sim.space.request_move(w,"walker",1,[xx,yy-3])
	var physically_inside: bool=false
	for tick: int in 50:
		suite._movement_tick(sim)
		if _touching(sim,"walker",door):physically_inside=true;break
	var unreserved: bool=not w.facts.adaptations.has(door.id)
	# Before creating any remodel order: rejection must be actual body occupancy,
	# not the later order lock or an adaptation reservation.
	var direct_busy: String=sim.services.building._busy(w,str(door.id))
	var room_busy: String=sim.services.building._busy(w,"passage")
	var prepared: CommandResult=suite._prepare(sim,["passage"],1,[35,68])
	var id: String=str(prepared.changed_ids[0]) if prepared.accepted else ""
	var plan: Dictionary=sim.services.remodel.preview(w,id) if not id.is_empty() else {}
	var row: Dictionary={"case":"actual_unreserved_door_body_blocks_remodel","ok":reason.is_empty() and physically_inside and unreserved and not direct_busy.is_empty() and not room_busy.is_empty() and prepared.accepted and not plan.get("ok",true),"physical_body_inside":physically_inside,"unreserved":unreserved,"direct_door_busy_before_remodel":direct_busy,"direct_room_busy_before_remodel":room_busy,"prepare":prepared.to_record(),"preview":plan}
	sim.dispose();return row

func _expanded_owner()->Dictionary:
	var f: Dictionary=_setup(false);var sim: HospitalSimulation=f.sim;var w: WorldState=sim.world;var door: Dictionary=f.door
	if door.is_empty():sim.dispose();return {"case":"expanded_height_width_owner_retained","ok":false}
	var xx: float=float(door.cell[0]);var yy: float=float(door.cell[1])
	suite._add_actor(sim,"owner","S01",[xx,yy+0.1]);suite._add_actor(sim,"waiter","S49",[xx,yy+3])
	var owner: Dictionary=w.facts.actors.owner
	var quote: Dictionary=sim.space.door_quote(w,owner,1,door)
	var acquisition: HospitalMovement.MotionResult=HospitalMovement.MotionResult.new()
	# Acquire through the production API for a body already physically within
	# an opening requiring both width/height adaptation. No fact is injected.
	var acquired: bool=sim.space.movement._reserve_doors(w,owner,{"actor_id":"owner","members":["owner"]},sim.space.body_rectangle(owner),[door],acquisition)
	var reservation: Dictionary=w.facts.adaptations.get(door.id,{}).duplicate(true)
	var real_owned: bool=acquired and reservation.get("actor_id","")=="owner" and int(quote.get("span",0))>int(door.span) and float(quote.get("clear_height_m",0))>float(door.clear_height_m)
	var request: String=sim.space.request_move(w,"waiter",1,[xx,yy-3])
	var stationary_wait: bool=false;var safe: bool=true;var held: bool=true
	for tick: int in 20:
		var previous: Array=w.facts.actors.waiter.location.cell.duplicate()
		suite._movement_tick(sim)
		held=held and w.facts.adaptations.get(door.id,{}).get("actor_id","")=="owner"
		stationary_wait=stationary_wait or (w.facts.moves.has("waiter") and previous==w.facts.actors.waiter.location.cell)
		safe=safe and not sim.space.body_rectangle(owner).intersects(sim.space.body_rectangle(w.facts.actors.waiter),false)
	var before_release_not_arrived: bool=not sim.space.at(w,"waiter",1,[xx,yy-3])
	var leave: String=sim.space.request_move(w,"owner",1,[xx+3,yy-3])
	for tick: int in 240:
		suite._movement_tick(sim)
		safe=safe and not sim.space.body_rectangle(owner).intersects(sim.space.body_rectangle(w.facts.actors.waiter),false)
		if sim.space.at(w,"waiter",1,[xx,yy-3]) and not w.facts.moves.has("waiter"):break
	var resumed: bool=sim.space.at(w,"waiter",1,[xx,yy-3]) and not w.facts.moves.has("waiter")
	var row: Dictionary={"case":"expanded_height_width_owner_retained","ok":real_owned and request.is_empty() and stationary_wait and held and safe and before_release_not_arrived and leave.is_empty() and resumed,"production_acquired_actual_owner":real_owned,"quote":quote,"reservation":reservation,"waiter_request":request,"stationary_wait_with_owner_held":stationary_wait and held,"not_arrived_before_release":before_release_not_arrived,"owner_departure":leave,"waiter_actually_resumed":resumed,"no_overlap":safe}
	sim.dispose();return row
