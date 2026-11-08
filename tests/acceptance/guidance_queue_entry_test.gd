extends "res://tests/acceptance/guidance_fixed_queue.gd"
const Entry=preload("res://game/operations/guidance_queue_entry.gd")

func run_entry(content: HospitalContent) -> Dictionary:
	_content=content
	var row: Dictionary=_twenty_actual_arrivals()
	return {"passed":row.ok,"cases":[row]}

func _twenty_actual_arrivals() -> Dictionary:
	var x: Dictionary=_base()
	# Same room/door/desk geometry as bench_room_1_14 in the 160-person input.
	HospitalFactory._add_room(x.world,{"id":"entry_room","type":"gp","anchor":[49,71],"size":[8,8],"door":{"definition_id":"DR04","offset":3}},_content)
	_facility(x,"guide","SE01",[50,73],"entry_room")
	_facility(x,"entry_water","FUR17",[54,73],"entry_room")
	x.world.touch()
	var nurse_start: Dictionary=x.world.facts.actors.guide_nurse.location.duplicate(true)
	var staffed: bool=false
	for tick: int in 600:
		x.g.dispatch(x.world);x.space.advance(x.world);x.g.advance(x.world)
		x.world.facts.sim_tick+=1;x.world.touch(false)
		if x.g._desk_usable(x.world,"guide"):staffed=true;break
	var ctx: Dictionary=Entry.context(x.space,x.world,"guide")
	var visits: Array=[]
	for i: int in 20:visits.append(_visit(x,"entry_%02d"%i,[35+2*(i%10),82+2*(i/10)]))
	var slots: Array=x.g._queue_slots(x.world,"guide",1)
	var cap: int=slots.size()
	var initial_validation: String=x.world.validate(_content)
	if ctx.is_empty() or cap!=3 or not staffed or not initial_validation.is_empty():
		var failed: Dictionary={"ok":false,"case":"twenty_actual_arrivals_bounded_room","setup_failed":true,"capacity":cap,"staffed":staffed,"context":ctx,"validation":initial_validation}
		_dispose(x);return failed
	var admitted: Dictionary={};var completed: Dictionary={};var leaving: Dictionary={}
	var outside_wait: Dictionary={};var departure_capacity_observed: bool=false
	var max_inside: int=0;var max_door: int=0;var max_door_still: int=0
	var door_still: Dictionary={};var previous: Dictionary={}
	var no_overlap: bool=true;var actual_arrival: bool=true;var nurse_real: bool=true
	var no_premature: bool=true;var exit_errors: Array=[];var samples: Array=[]
	var elapsed: int=0
	for tick: int in 2600:
		var before: Dictionary={}
		for visit: Dictionary in visits:before[visit.id]=x.world.facts.actors[visit.actor_id].location.cell.duplicate()
		x.g.dispatch(x.world)
		for visit: Dictionary in visits:
			if not completed.has(visit.id):x.g.prepare(x.world,visit,x.world.facts.tickets[visit.ticket_id])
		x.space.advance(x.world);x.g.advance(x.world)
		x.world.facts.sim_tick+=1;x.world.touch(false);elapsed+=1
		var inside: int=0;var in_door: int=0;var departing_inside: int=0
		for i: int in visits.size():
			var visit: Dictionary=visits[i]
			var actor: Dictionary=x.world.facts.actors[visit.actor_id]
			var point: Vector2=Vector2(actor.location.cell[0],actor.location.cell[1])
			var here: bool=Entry.is_inside(ctx,x.space,actor,point)
			var row: Dictionary=x.g.state(x.world,visit.id)
			if here:inside+=1
			if here and completed.has(visit.id):departing_inside+=1
			var door: bool=false
			for bounds: Rect2 in ctx.door_bounds:door=door or x.space._actor_rect(actor,point).intersects(bounds,false)
			if door:in_door+=1
			var still: bool=door and previous.get(visit.id,Vector2.INF)==point
			door_still[visit.id]=int(door_still.get(visit.id,0))+1 if still else 0
			max_door_still=maxi(max_door_still,int(door_still[visit.id]));previous[visit.id]=point
			no_overlap=no_overlap and not _overlap(x,visit.actor_id)
			if not here and not admitted.has(visit.id):
				no_premature=no_premature and not row.has("queue_seq")
				if not Entry.capacity_available(x.space,x.world,x.g,visit.actor_id,"guide"):outside_wait[visit.id]=true
			if row.has("queue_seq") and not admitted.has(visit.id):
				admitted[visit.id]=int(row.queue_seq)
				actual_arrival=actual_arrival and Vector2(before[visit.id][0],before[visit.id][1]).distance_to(Vector2(row.queue_cell[0],row.queue_cell[1]))<0.001
			if row.get("phase","")=="working":
				nurse_real=nurse_real and x.space.at(x.world,"guide_nurse",1,x.space.facility_layout(x.world,"guide").operator_cells[0]) and not x.world.facts.moves.has("guide_nurse")
			if not row.receipts.is_empty() and not completed.has(visit.id):
				completed[visit.id]=int(row.receipts[0].completed_tick)
				# Real departure to a legal, separate exterior destination. Keep
				# the completed actor present; its body must still consume capacity.
				var reason: String=x.space.request_move(x.world,visit.actor_id,1,[34+2*(i%10),92+2*(i/10)])
				if not reason.is_empty():exit_errors.append({"id":visit.id,"reason":reason})
				leaving[visit.id]=true
		max_inside=maxi(max_inside,inside);max_door=maxi(max_door,in_door)
		if departing_inside>0 and inside==cap:
			for visit: Dictionary in visits:
				if not admitted.has(visit.id) and not Entry.capacity_available(x.space,x.world,x.g,visit.actor_id,"guide"):departure_capacity_observed=true
		if tick%100==0:samples.append({"tick":tick,"inside":inside,"door":in_door,"admitted":admitted.size(),"completed":completed.size()})
		if completed.size()==20 and inside==0:break
	var fair: bool=admitted.size()==20 and completed.size()==20
	for a: String in admitted:
		for b: String in admitted:
			if admitted[a]<admitted[b] and completed.has(a) and completed.has(b):fair=fair and completed[a]<completed[b]
	var recovered: bool=not outside_wait.is_empty()
	for id: String in outside_wait:recovered=recovered and completed.has(id)
	var validation: String=x.world.validate(_content)
	var result: Dictionary={"case":"twenty_actual_arrivals_bounded_room","ok":fair and actual_arrival and no_premature and no_overlap and nurse_real and max_inside<=cap and max_door_still==0 and recovered and departure_capacity_observed and exit_errors.is_empty() and validation.is_empty(),"capacity":cap,"max_actual_inside_including_door":max_inside,"max_actual_door":max_door,"max_stationary_door_ticks":max_door_still,"actual_arrival":actual_arrival,"no_premature_number":no_premature,"nurse_at_post_during_work":nurse_real,"nurse_walked":nurse_start!=x.world.facts.actors.guide_nurse.location,"no_overlap":no_overlap,"actual_sequence_service_order":fair,"capacity_release_recovers_waiters":recovered,"departing_body_capacity_observed":departure_capacity_observed,"admitted":admitted,"completed":completed,"outside_wait":outside_wait,"exit_errors":exit_errors,"elapsed":elapsed,"samples":samples,"validation":validation,"actors":x.world.facts.actors.duplicate(true),"moves":x.world.facts.moves.duplicate(true),"states":x.world.facts.floor_guidance.visits.duplicate(true)}
	_dispose(x);return result
