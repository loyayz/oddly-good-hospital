extends "res://tests/acceptance/guidance_fixed_queue.gd"
const Geometry=preload("res://game/operations/guidance_queue_geometry.gd")
func run_scope(content: HospitalContent)->Dictionary:
	_content=content
	var x: Dictionary=_base()
	HospitalFactory._add_room(x.world,{"id":"queue_room","type":"gp","anchor":[45,81],"size":[10,8],"door":{"definition_id":"DR04","offset":5}},_content)
	_facility(x,"guide","SE01",[47,83],"queue_room");x.world.touch()
	var v: Dictionary=_visit(x,"large",[35,89]);var chosen: bool=_make_large(x,v)
	var ordinary_scope: Dictionary=Geometry.room_scope(x.world,1,"guide")
	var legal: bool=x.g._queue_position_allowed(x.world,v.actor_id,"guide",[47,84],3)
	var outside_rejected: bool=not x.g._queue_position_allowed(x.world,v.actor_id,"guide",[56,84],3)
	# A real concave cell set retains its whole actual boundary. The missing
	# corner is inside the AABB but is not room interior.
	var room: Dictionary=x.world.facts.rooms.queue_room
	var cells: Array=BuildGeometry.cells(room).duplicate(true)
	for xx: int in range(52,55):
		for yy: int in range(81,84):cells.erase([xx,yy])
	room.cells=cells;room.erase("wall_edges");x.world.touch()
	var concave: Dictionary=Geometry.room_scope(x.world,1,"guide")
	var concave_rejected: bool=not x.g._queue_position_allowed(x.world,v.actor_id,"guide",[52,81],3)
	var retained_valid: bool=x.g._queue_position_allowed(x.world,v.actor_id,"guide",[47,84],3)
	var bounded: Array=Geometry.walls(x.world,1,"guide",concave)
	var physical_before: Dictionary=x.world.freeze()
	var count_rooms: int=0
	for r: Dictionary in x.world.facts.rooms.values():
		if int(r.floor_id)==1:count_rooms+=BuildGeometry.room_walls(r).size()
	var ids_before: Dictionary=x.world.facts.facilities.guide.duplicate(true)
	x.world.facts.facilities.guide.room_id="missing-room";x.world.touch()
	var invalid: Dictionary=Geometry.room_scope(x.world,1,"guide")
	var unbounded: Array=Geometry.walls(x.world,1,"guide")
	var fallback: bool=invalid.is_empty() and unbounded.size()>=bounded.size()
	x.world.facts.facilities.guide=ids_before;x.world.touch()
	var raw: Dictionary=x.world.freeze();var cached: Dictionary=x.g._queue_context(x.world,"guide")
	var readonly: bool=raw==x.world.freeze()
	var checks: Dictionary={"large_selected":chosen,"ordinary_scope_valid":not ordinary_scope.is_empty(),"large_inside_legal":legal,"large_outside_room_rejected":outside_rejected,"concave_scope_valid":not concave.is_empty(),"concave_missing_corner_rejected":concave_rejected,"concave_actual_inside_still_legal":retained_valid,"invalid_room_falls_back_all":fallback,"context_readonly":readonly}
	var result: Dictionary={"passed":not checks.values().has(false),"checks":checks,"bounded_edges":bounded.size(),"fallback_full_floor_edges":unbounded.size(),"real_room_edges_retained":count_rooms,"cached_edges":cached.walls.size(),"bounds":str(concave.get("bounds",Rect2i()))}
	_dispose(x);return result
