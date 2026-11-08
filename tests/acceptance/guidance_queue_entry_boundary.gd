extends "res://tests/acceptance/floor_guidance.gd"
const Entry=preload("res://game/operations/guidance_queue_entry.gd")
const Wait=preload("res://game/operations/guidance_queue_wait.gd")
func run_boundary(content: HospitalContent)->Dictionary:
	_content=content
	var cases: Array=[_door_boundary(),_fallback_geometry(),_external_need(),_no_safe_point()]
	return {"passed":not cases.any(func(r: Dictionary)->bool:return not r.ok),"cases":cases}
func _entry_fixture()->Dictionary:
	var x: Dictionary=_base()
	HospitalFactory._add_room(x.world,{"id":"entry_room","type":"gp","anchor":[49,71],"size":[8,8],"door":{"definition_id":"DR04","offset":3}},_content)
	_facility(x,"guide","SE01",[50,73],"entry_room")
	_facility(x,"entry_water","FUR17",[54,73],"entry_room")
	x.world.touch();return x
func _fill_physical(x: Dictionary)->void:
	# These are physical occupancy fixtures, deliberately NOT invented queue
	# admissions. Entry capacity must include patient bodies without numbers.
	for i: int in 3:_visit(x,"occupant_%d"%i,[51,74+i])
	x.world.touch(false)
func _door_boundary()->Dictionary:
	var x: Dictionary=_entry_fixture();_fill_physical(x)
	var v: Dictionary=_visit(x,"probe",[52,81])
	# Pure gate input metadata, not a movement/arrival or queue-number claim.
	x.world.facts.floor_guidance.visits[v.id]={"visit_id":v.id,"phase":"seek","desk_id":"guide","request_key":"boundary"}
	var ctx: Dictionary=Entry.context(x.space,x.world,"guide")
	var move: Dictionary={"floor_guidance_key":"boundary","members":[v.actor_id]}
	var before: Dictionary=x.world.freeze()
	var full: bool=not Entry.capacity_available(x.space,x.world,x.g,v.actor_id,"guide")
	var actor: Dictionary=x.world.facts.actors[v.actor_id]
	var origin_body: Rect2=x.space._actor_rect(actor,Vector2.ZERO)
	var door: Rect2=ctx.door_bounds[0]
	# Actor cell is not the body's top-left: derive a genuine south-door
	# crossing from the production body envelope, using 0.2-cell steps.
	var xx: float=door.get_center().x-origin_body.get_center().x
	var boundary_y: float=door.end.y-origin_body.position.y
	var outside: Vector2=Vector2(xx,boundary_y+0.1)
	var crossing_point: Vector2=outside+Vector2(0,-0.2)
	var next_inside: Vector2=crossing_point+Vector2(0,-0.2)
	var blocked: bool=Entry.block_entry(x.space,x.world,x.g,v.actor_id,move,outside,crossing_point)
	var crossing: bool=not Entry.block_entry(x.space,x.world,x.g,v.actor_id,move,crossing_point,next_inside)
	var outward: bool=not Entry.block_entry(x.space,x.world,x.g,v.actor_id,move,crossing_point,outside)
	var foreign: bool=not Entry.block_entry(x.space,x.world,x.g,v.actor_id,{},outside,crossing_point)
	var geometry: bool=not Entry.is_inside(ctx,x.space,actor,outside) and Entry.is_inside(ctx,x.space,actor,crossing_point) and Entry.is_inside(ctx,x.space,actor,next_inside)
	var evidence: Dictionary={"door_rect":_rect_evidence(door),"body_at_origin":_rect_evidence(origin_body),"outside_cell":[outside.x,outside.y],"crossing_cell":[crossing_point.x,crossing_point.y],"next_cell":[next_inside.x,next_inside.y],"outside_body":_rect_evidence(x.space._actor_rect(actor,outside)),"crossing_body":_rect_evidence(x.space._actor_rect(actor,crossing_point)),"next_body":_rect_evidence(x.space._actor_rect(actor,next_inside)),"actual_boundary_verified":geometry}
	var row: Dictionary={"case":"pure_gate_boundary_no_tokens","ok":not ctx.is_empty() and geometry and full and blocked and crossing and outward and foreign and before==x.world.freeze(),"geometry":evidence,"full":full,"external_entry_blocked":blocked,"already_door_crossing_not_stopped":crossing,"exit_not_stopped":outward,"foreign_owner_not_gated":foreign,"no_world_mutation":before==x.world.freeze()}
	_dispose(x);return row
func _fallback_geometry()->Dictionary:
	var x: Dictionary=_entry_fixture()
	var original: Dictionary=Entry.context(x.space,x.world,"guide")
	var original_revision: int=x.world.geometry_revision
	_facility(x,"second","SE01",[54,75],"entry_room");x.world.touch()
	var shared: bool=Entry.context(x.space,x.world,"guide").is_empty()
	x.world.facts.facilities.erase("second");x.world.touch()
	var recovered: Dictionary=Entry.context(x.space,x.world,"guide")
	# A real structural door edit invalidates the formerly proven boundary.
	for door: Dictionary in x.world.facts.floors.overrides["1"].doors:
		if door.room_id=="entry_room":door.cell=[52,80]
	x.world.touch()
	var edited: bool=Entry.context(x.space,x.world,"guide").is_empty()
	x.world.facts.facilities.guide.erase("room_id");x.world.touch()
	var hall: bool=Entry.context(x.space,x.world,"guide").is_empty()
	var v: Dictionary=_visit(x,"hall_probe",[40,85])
	var fallback: bool=Entry.capacity_available(x.space,x.world,x.g,v.actor_id,"guide")
	var row: Dictionary={"case":"shared_hall_and_geometry_invalidation","ok":not original.is_empty() and shared and not recovered.is_empty() and edited and hall and fallback and x.world.geometry_revision>original_revision,"shared_room_fallback":shared,"removal_restores_context":not recovered.is_empty(),"door_edit_invalidates_context":edited,"open_hall_fallback":hall and fallback}
	_dispose(x);return row
func _external_need()->Dictionary:
	var x: Dictionary=_entry_fixture();_fill_physical(x)
	_facility(x,"outside_water","FUR17",[62,84]);x.world.touch()
	var v: Dictionary=_visit(x,"need_owner",[60,88])
	var clock: Dictionary=x.world.facts.waiting_life.clocks[v.id]
	clock.next_purpose="water";clock.next_need_tick=x.world.sim_tick
	x.world.touch(false);x.l.dispatch(x.world)
	var need: Dictionary=x.world.facts.waiting_life.needs.get(v.id,{})
	var movement: Dictionary=x.world.facts.moves.get(v.actor_id,{}).duplicate(true)
	var full: bool=not Entry.capacity_available(x.space,x.world,x.g,v.actor_id,"guide")
	var location: Dictionary=x.world.facts.actors[v.actor_id].location.duplicate(true)
	x.g.prepare(x.world,v,x.world.facts.tickets[v.ticket_id])
	var preserved: bool=not need.is_empty() and not movement.is_empty() and movement==x.world.facts.moves.get(v.actor_id,{}) and location==x.world.facts.actors[v.actor_id].location
	var no_number: bool=not x.g.state(x.world,v.id).has("queue_seq")
	# One actual movement step remains owned by the need, not the queue.
	x.space.advance(x.world)
	var after: Dictionary=x.world.facts.moves.get(v.actor_id,{})
	var ownership: bool=after.is_empty() or not after.has("floor_guidance_key")
	var row: Dictionary={"case":"full_room_does_not_steal_actual_need","ok":full and preserved and no_number and ownership,"full":full,"need":need.duplicate(true),"movement_before":movement,"movement_after":after.duplicate(true),"prepare_preserves_need_move":preserved,"no_number":no_number,"ownership_after_real_step":ownership}
	_dispose(x);return row
func _no_safe_point()->Dictionary:
	var x: Dictionary=_entry_fixture();_fill_physical(x)
	var v: Dictionary=_visit(x,"no_point",[76,90])
	# Isolated legal fixture cell with no local bypass or reachable overflow
	# point. No actors are teleported or removed during the tested operation.
	for xx: int in range(63,90):
		for yy: int in range(77,96):
			if [xx,yy]!=[76,90]:HospitalFactory._put_cell(x.world.facts.floors.overrides["1"].blocked,[xx,yy])
	x.world.touch()
	var ctx: Dictionary=Entry.context(x.space,x.world,"guide")
	var point: Dictionary=Wait.choose(x.space,x.world,v.actor_id,ctx)
	var current: Dictionary={"desk_id":"guide","request_key":"no-point-boundary","phase":"seek","receipts":[]}
	var before: Dictionary=x.world.facts.actors[v.actor_id].location.duplicate(true)
	var ticket: String=v.ticket_id
	var handled: bool=x.g._wait_outside_queue(x.world,v,current)
	x.space.advance(x.world)
	var unchanged: bool=before==x.world.facts.actors[v.actor_id].location and not x.world.facts.moves.has(v.actor_id)
	var pending: bool=v.ticket_id==ticket and x.world.facts.tickets.has(ticket) and current.phase=="seek" and not current.has("queue_seq") and current.receipts.is_empty()
	var row: Dictionary={"case":"no_safe_overflow_keeps_pending_not_arrival","ok":point.is_empty() and handled and unchanged and pending and v.waiting_reason.contains("保留待办"),"chosen":point,"unchanged_after_real_step":unchanged,"pending_without_number_or_receipt":pending,"reason":v.waiting_reason,"scope":"absence of local safe point, not a claim that every layout can clear congestion"}
	_dispose(x);return row

func _rect_evidence(rect: Rect2)->Dictionary:
	return {"position":[rect.position.x,rect.position.y],"size":[rect.size.x,rect.size.y],"end":[rect.end.x,rect.end.y]}
