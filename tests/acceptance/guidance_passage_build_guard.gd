extends "res://tests/acceptance/guidance_fixed_queue.gd"
func run_build_guard(content: HospitalContent)->Dictionary:
	_content=content
	var x: Dictionary=_base()
	HospitalFactory._add_room(x.world,{"id":"queue_room","type":"gp","anchor":[45,81],"size":[10,8],"door":{"definition_id":"DR04","offset":5}},_content)
	_facility(x,"guide","SE01",[47,83],"queue_room");x.world.touch()
	var gate: Dictionary=_visit(x,"gate",[48,85])
	for tick: int in 600:
		_step(x)
		if x.g.state(x.world,gate.id).get("phase","")=="working":break
	var v: Dictionary=_visit(x,"queued",[50,85])
	var actual: bool=false
	for tick: int in 60:
		_step(x)
		var row: Dictionary=x.g.state(x.world,v.id)
		actual=row.get("phase","")=="desk_queue" and row.has("queue_seq") and row.has("queue_cell") and x.space.at(x.world,v.actor_id,1,row.queue_cell) and not x.world.facts.moves.has(v.actor_id)
		if actual:break
	var state: Dictionary=x.g.state(x.world,v.id).duplicate(true)
	if not actual:
		var failure: Dictionary={"ok":false,"case":"later_build_preserves_actual_queue_passage","actual_queue":false,"state":state}
		_dispose(x);return {"passed":false,"cases":[failure]}
	var cell: Array=[state.queue_cell[0],state.queue_cell[1]+2]
	var builder: BuildService=BuildService.new(_content,x.space)
	var before: Dictionary=x.world.freeze()
	var attempted: CommandResult=builder.execute(x.world,"build_facility",{"id":"obstructing_water","definition_id":"FUR17","floor_id":1,"cell":cell,"room_id":"queue_room"})
	var atomic: bool=before==x.world.freeze()
	var row: Dictionary={"case":"later_build_preserves_actual_queue_passage","ok":actual and not attempted.accepted and attempted.reason.contains("两格静态通路") and atomic,"actual_queue":actual,"state":state,"new_furniture_cell":cell,"attempt":attempted.to_record(),"world_unchanged":atomic}
	_dispose(x);return {"passed":row.ok,"cases":[row]}
