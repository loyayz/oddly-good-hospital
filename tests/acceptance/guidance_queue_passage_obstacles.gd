extends "res://tests/acceptance/guidance_fixed_queue.gd"
const Packing=preload("res://game/operations/guidance_queue_layout.gd")
func run_passage_obstacles(content: HospitalContent)->Dictionary:
	_content=content
	var cases: Array=[]
	for large: bool in [false,true]:
		for furniture: bool in [false,true]:cases.append(_obstacle(large,furniture))
	return {"passed":not cases.any(func(r: Dictionary)->bool:return not r.ok),"cases":cases}
func _obstacle(large: bool, furniture: bool)->Dictionary:
	var x: Dictionary=_base()
	HospitalFactory._add_room(x.world,{"id":"queue_room","type":"gp","anchor":[45,81],"size":[10,8],"door":{"definition_id":"DR04","offset":5}},_content)
	_facility(x,"guide","SE01",[47,83],"queue_room");x.world.touch()
	var visitor: Dictionary=_visit(x,"body",[35,89])
	var chosen: bool=not large or _make_large(x,visitor)
	var spans: Array=[3] if large else [1,1,1]
	var span: int=3 if large else 1
	var context: Dictionary=x.g._queue_context(x.world,"guide")
	var valid: Callable=func(_i: int,cell: Array)->bool:return x.g._queue_position_allowed(x.world,visitor.actor_id,"guide",cell,span)
	var original: Dictionary=Packing.pack(context.facility,context.walls,context.bounds,spans,valid)
	if not chosen or not original.complete:
		var failure: Dictionary={"case":"passage_fixture","ok":false,"large":large,"chosen":chosen,"packing":original}
		_dispose(x);return failure
	var tail: Array=original.placements[-1]
	# Room south wall is y=89. Both the third ordinary slot and the
	# one three-cell body end at y=87, so these are precisely the final
	# two wall-side passage rows, not an intermediate future queue slot.
	var rear: Rect2i=Rect2i(Vector2i(tail[0],tail[1]+span),Vector2i(span,2))
	# Large footprint expands beyond the desk's original frontage. Put the
	# obstruction in that lateral extension, not in any candidate body cell.
	var obstacle: Array=[rear.end.x-1,rear.end.y-1]
	var command: Dictionary={}
	if furniture:
		var build: BuildService=BuildService.new(_content,x.space)
		var result: CommandResult=build.execute(x.world,"build_facility",{"id":"rear_water","definition_id":"FUR17","floor_id":1,"cell":obstacle,"room_id":"queue_room"})
		command=result.to_record()
		if not result.accepted:
			var failure: Dictionary={"case":"rear_furniture_legal_setup","ok":false,"large":large,"command":command,"tail":tail,"obstacle":obstacle}
			_dispose(x);return failure
	else:
		HospitalFactory._put_cell(x.world.facts.floors.overrides["1"].blocked,obstacle)
		x.world.touch()
	context=x.g._queue_context(x.world,"guide")
	var core_clear: bool=x.g._queue_position_allowed(x.world,visitor.actor_id,"guide",tail,span)
	var blocked_cells: Array=[]
	for yy: int in range(rear.position.y,rear.end.y):
		for xx: int in range(rear.position.x,rear.end.x):
			var cell: Array=[xx,yy]
			var blocker: String=x.space._blocking_facility(x.world,1,Rect2(xx,yy,1,1))
			if cell in x.world.facts.floors.overrides["1"].blocked or not blocker.is_empty():blocked_cells.append({"cell":cell,"facility":blocker})
	var after: Dictionary=Packing.pack(context.facility,context.walls,context.bounds,spans,valid)
	var rejected_or_shortened: bool=not after.complete or after.placements[-1]!=tail
	var recovered: bool=false
	var restore_command: Dictionary={}
	if furniture:
		var builder: BuildService=BuildService.new(_content,x.space)
		var removed: CommandResult=builder.execute(x.world,"build_demolish",{"target_id":"rear_water"})
		restore_command=removed.to_record()
	else:
		x.world.facts.floors.overrides["1"].blocked.erase(obstacle);x.world.touch()
	var refreshed: Dictionary=x.g._queue_context(x.world,"guide")
	var restored: Dictionary=Packing.pack(refreshed.facility,refreshed.walls,refreshed.bounds,spans,valid)
	recovered=restored.complete and restored.placements==original.placements
	var row: Dictionary={"case":("large_lateral_" if large else "ordinary_tail_")+("furniture" if furniture else "blocked_cell"),"ok":chosen and core_clear and not blocked_cells.is_empty() and rejected_or_shortened and recovered,"scope":"production pack/validator with real geometry; no invented queue admissions or performance claim","span":span,"original_tail":tail,"rear_passage":{"position":[rear.position.x,rear.position.y],"size":[rear.size.x,rear.size.y]},"obstacle":obstacle,"build_command":command,"candidate_body_still_legal":core_clear,"blocked_passage_cells":blocked_cells,"accepted_blocked_tail":after.complete and after.placements[-1]==tail,"before_placements":original.placements,"after_placements":after.placements,"after_complete":after.complete,"geometry_cache_recovers_after_removal":recovered,"restore_command":restore_command,"validation":x.world.validate(_content)}
	_dispose(x);return row
