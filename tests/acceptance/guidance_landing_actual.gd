extends "res://tests/acceptance/guidance_fixed_queue.gd"
# Counterfactual test-only boundary: exact current position predicate minus
# only the new landing standing exclusion. Production remains untouched.
class BeforeLandingGuidance extends HospitalFloorGuidance:
	func _queue_position_allowed(world: WorldState, actor_id: String, desk_id: String, slot: Array, span: int) -> bool:
		var floor_id: int=int(world.facts.facilities[desk_id].floor_id)
		var actor: Dictionary=world.facts.actors[actor_id]
		var geometry: RouteClearance=space.navigation.structural_clearance(world,actor,floor_id)
		var key: String=desk_id+":"+str(span)+":"+str(slot)+":"+space._navigation._graph_key(space,world,floor_id,actor,[],{},geometry.source)
		if _queue_valid.has(key):return _queue_valid[key]
		var point:=Vector2i(int(slot[0]),int(slot[1]))
		# Culling static obstacles to the desk's room is sound only if every
		# accepted body stays inside its actual cells, including concave rooms.
		var room_cells: Dictionary=_queue_context(world,desk_id).get("room_cells",{})
		if not room_cells.is_empty():
			for xx: int in range(point.x,point.x+span):
				for yy: int in range(point.y,point.y+span):
					if not room_cells.has(Vector2i(xx,yy)):
						if _queue_valid.size()>=512:_queue_valid.clear()
						_queue_valid[key]=false
						return false
		space.public_areas._ensure(world,floor_id)
		var valid: bool=geometry.reason(point).is_empty() and not space.public_areas._cell_region(floor_id,point).is_empty()
		var rectangle:=Rect2(Vector2(point),Vector2.ONE*span)
		if valid:
			for door: Dictionary in world.facts.floors.overrides.get(str(floor_id),{}).get("doors",[]):
				if rectangle.intersects(space._door_rect(door,int(door.span)).grow(1.0),false):valid=false;break
		if valid:
			for facility: Dictionary in world.facts.facilities.values():
				if int(facility.floor_id)!=floor_id:continue
				var points: Array=facility.get("operator_cells",[]).duplicate()
				points.append(facility.repair_cell)
				if facility.id!=desk_id:points.append(facility.patient_cell)
				for work: Array in points:
					if rectangle.intersects(Rect2(Vector2(work[0],work[1]),Vector2.ONE),false):valid=false;break
				if not valid:break
		if _queue_valid.size()>=512:_queue_valid.clear()
		_queue_valid[key]=valid
		return valid

func run_landing(content: HospitalContent)->Dictionary:
	_content=content
	var cases: Array=[_actual_before(),_current_passage()]
	return {"passed":not cases.any(func(r: Dictionary)->bool:return not r.ok),"cases":cases}
func _landing_fixture(old: bool)->Dictionary:
	var x: Dictionary=_base(false,true)
	_facility(x,"guide","SE01",[58,88])
	var builder: BuildService=BuildService.new(_content,x.space)
	var turn: CommandResult=builder.execute(x.world,"build_rotate",{"target_id":"guide","rotation":3})
	x.rotation_ok=turn.accepted
	if old:
		var previous: RefCounted=x.g
		x.g=BeforeLandingGuidance.new(_content,x.space)
		x.g.clinic=x.c;x.g.waiting=x.l;x.c.floor_guidance=x.g;x.l.floor_guidance=x.g
		previous.clinic=null;previous.waiting=null
		x.g.ensure(x.world)
	return x
func _actual_before()->Dictionary:
	var x: Dictionary=_landing_fixture(true)
	var v: Dictionary=_visit(x,"landing_queue",[62,90])
	var landing: Rect2=Rect2(59,88,2,2)
	var actual: bool=false;var arrival_trace: Array=[]
	for tick: int in 600:
		_step(x)
		var row: Dictionary=x.g.state(x.world,v.id)
		if row.has("queue_seq") and row.get("desk_id","")=="guide":arrival_trace.append({"tick":tick,"row":row.duplicate(true),"location":x.world.facts.actors[v.actor_id].location.duplicate(true)})
		actual=row.has("queue_seq") and row.has("queue_cell") and row.get("queue_attending",false) and x.world.facts.actors[v.actor_id].location.kind=="floor" and int(x.world.facts.actors[v.actor_id].location.floor_id)==1 and x.space.body_rectangle(x.world.facts.actors[v.actor_id]).intersects(landing,false) and row.receipts.is_empty()
		if actual:break
	var queued: Dictionary=x.g.state(x.world,v.id).duplicate(true)
	var rider: Dictionary=_visit(x,"incoming",[59,88])
	var passenger: Dictionary=x.world.facts.actors[rider.actor_id]
	var real_two_cell: bool=false
	for binding: Dictionary in _content.catalog.treatment_bindings:
		var probe: Dictionary=passenger.duplicate(true);probe.species_id=binding.species_id;probe.body_binding_id=binding.id
		if x.space.clearance(probe)!=2 or float(x.space.body(probe).height_m)>3.2:continue
		passenger.species_id=binding.species_id;passenger.body_binding_id=binding.id
		rider.binding_id=binding.id;rider.disease_id=binding.disease_id;rider.requested_plan_id="P_"+str(binding.disease_id)+"_COMMON"
		real_two_cell=x.space.clearance(passenger)==2;break
	passenger.location.floor_id=2;x.world.touch()
	var landing_body: Rect2=x.space._actor_rect(passenger,Vector2(59,88))
	var overlaps_unload: bool=actual and landing_body.intersects(x.space.body_rectangle(x.world.facts.actors[v.actor_id]),false)
	var reason: String=x.space.request_move(x.world,rider.actor_id,1,[62,90])
	var saw_transit: bool=false;var blocked_at_occupied_landing: bool=false;var arrived: bool=false;var safe: bool=true
	var evidence: Array=[]
	for tick: int in 350:
		x.g.dispatch(x.world);x.g.prepare(x.world,v,x.world.facts.tickets[v.ticket_id])
		x.space.advance(x.world);x.g.advance(x.world);x.world.facts.sim_tick+=1;x.world.touch(false)
		var actor: Dictionary=x.world.facts.actors[rider.actor_id]
		var connection: Dictionary=x.world.facts.connectors.lift
		if actor.location.kind=="transit":
			saw_transit=true
			if int(connection.get("to",0))==1 and connection.phase=="alighting" and int(connection.get("remaining_ticks",-1))==1 and x.world.facts.actors[v.actor_id].location.kind=="floor" and int(x.world.facts.actors[v.actor_id].location.floor_id)==1 and landing_body.intersects(x.space.body_rectangle(x.world.facts.actors[v.actor_id]),false):
				blocked_at_occupied_landing=true
				evidence.append({"tick":tick,"connection":connection.duplicate(true),"queue_state":x.g.state(x.world,v.id).duplicate(true),"queue_actor":x.world.facts.actors[v.actor_id].location.duplicate(true)})
		safe=safe and not _overlap(x,v.actor_id) and not _overlap(x,rider.actor_id)
		if x.space.at(x.world,rider.actor_id,1,[62,90]) and not x.world.facts.moves.has(rider.actor_id):arrived=true;break
	var row: Dictionary={"case":"before_standing_exclusion_actual_queue_blocks_unload","ok":x.rotation_ok and actual and real_two_cell and overlaps_unload and reason.is_empty() and saw_transit and blocked_at_occupied_landing and evidence.size()>=2 and arrived and safe,"actual_queue_on_landing":actual,"real_two_cell_passenger":real_two_cell,"actual_queue_overlaps_unload_body":overlaps_unload,"unload_body":str(landing_body),"arrival_trace":arrival_trace,"queue_state_at_witness":queued,"request":reason,"actual_transit":saw_transit,"blocked_unload_witness":blocked_at_occupied_landing,"arrival_after_queue_moves":arrived,"no_overlap":safe,"evidence":evidence,"scope":"test-only old predicate; no production rollback or invented admission"}
	_dispose(x);return row
func _current_passage()->Dictionary:
	var x: Dictionary=_landing_fixture(false)
	var v: Dictionary=_visit(x,"walk_through",[62,90])
	var rejected: bool=not x.g._queue_position_allowed(x.world,v.actor_id,"guide",[59,88],1)
	var request: String=x.space.request_move(x.world,v.actor_id,1,[59,88])
	var arrived_landing: bool=false;var safe: bool=true
	for tick: int in 240:
		x.space.advance(x.world);x.world.facts.sim_tick+=1;x.world.touch(false)
		safe=safe and not _overlap(x,v.actor_id)
		if x.space.at(x.world,v.actor_id,1,[59,88]) and not x.world.facts.moves.has(v.actor_id):arrived_landing=true;break
	var up: String=x.space.request_move(x.world,v.actor_id,2,[62,90])
	var rode: bool=false;var arrived: bool=false
	for tick: int in 350:
		x.space.advance(x.world);x.world.facts.sim_tick+=1;x.world.touch(false)
		rode=rode or x.world.facts.actors[v.actor_id].location.kind=="transit"
		safe=safe and not _overlap(x,v.actor_id)
		if x.space.at(x.world,v.actor_id,2,[62,90]) and not x.world.facts.moves.has(v.actor_id):arrived=true;break
	var no_number: bool=not x.g.state(x.world,v.id).has("queue_seq")
	var row: Dictionary={"case":"landing_excludes_queue_standing_not_actual_transit","ok":x.rotation_ok and rejected and request.is_empty() and arrived_landing and up.is_empty() and rode and arrived and safe and no_number,"queue_slot_denied":rejected,"walk_request":request,"actually_walked_to_landing":arrived_landing,"up_request":up,"actually_rode":rode,"arrived_upstairs":arrived,"no_forged_queue_number":no_number,"no_overlap":safe,"final_location":x.world.facts.actors[v.actor_id].location.duplicate(true)}
	_dispose(x);return row
