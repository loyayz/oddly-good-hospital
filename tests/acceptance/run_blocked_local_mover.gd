extends SceneTree

# Both journeys begin with real requests. The pocket admits a body, but its
# occupant cannot step sideways; the other walker must clear the open mouth.
func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1: push_error("Output JSON required");quit(2);return
	var content:=HospitalContent.new()
	var suite: RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
	var sim: HospitalSimulation=suite._fixture()
	var furniture: Array[Rect2]=[]
	for item: Array in [["upper",[38,69]],["lower",[38,71]],["back",[37,70]]]:
		HospitalFactory._add_facility(sim.world,{"id":item[0],"definition_id":"FUR05","anchor":item[1],"size":[2,1],"room_id":null},content)
		furniture.append(Rect2(Vector2(item[1][0],item[1][1]),Vector2(2,1)))
	sim.world.touch()
	suite._add_actor(sim,"a","S49",[39.4,70])
	suite._add_actor(sim,"b","S49",[40,70])
	var initial_validation: String=sim.world.validate(content)
	var requests: Array=[sim.space.request_move(sim.world,"a",1,[43,70]),sim.space.request_move(sim.world,"b",1,[39,70])]
	var result: Dictionary=_walk(suite,sim,furniture,true)
	result.initial_validation=initial_validation
	result.requests=requests
	result.ok=result.ok and initial_validation.is_empty() and requests==["",""]
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify({"ok":result.ok,"checks":result.checks,"steps":result.steps,"restore":result.restore.get("checks",{})}))
	sim.dispose();quit(0 if result.ok else 1)

func _walk(suite: RefCounted, sim: HospitalSimulation, furniture: Array[Rect2], save: bool) -> Dictionary:
	var probe: RefCounted=load("res://tests/acceptance/movement_detour.gd").new()
	var paths: Dictionary={}
	var requests: Dictionary={}
	var goals: Dictionary={"a":[43,70],"b":[39,70]}
	for id: String in goals:requests[id]=sim.world.facts.moves[id].request_sequence
	var errors: Array=[]
	var trace: Array=[]
	var restored: Dictionary={}
	var original: bool=true
	var only_one_aside: bool=true
	var aside_seen: bool=false
	var local_block_seen: bool=false
	var steps: int=0
	for tick: int in 300:
		var before: Dictionary={}
		for id: String in goals:before[id]=sim.space.body_rectangle(sim.world.facts.actors[id])
		var error: String=probe._tick(suite,sim,["a","b"])
		steps+=1
		if not error.is_empty():errors.append(error);break
		for id: String in goals:
			var actor: Dictionary=sim.world.facts.actors[id]
			var after: Rect2=sim.space.body_rectangle(actor)
			for rect: Rect2 in furniture:
				if before[id].intersects(rect,false) or after.intersects(rect,false) or BodySweep.intersects(before[id],after,rect,rect):errors.append("Furniture body/sweep: "+id)
			var move: Dictionary=sim.world.facts.moves.get(id,{})
			if move.is_empty():continue
			if not paths.has(id) and not move.path.is_empty():paths[id]=move.path.duplicate(true)
			original=original and move.target_cell==goals[id] and move.request_sequence==requests[id] and (not paths.has(id) or move.path==paths[id])
		only_one_aside=only_one_aside and is_equal_approx(float(sim.world.facts.actors.a.location.cell[1]),70.0)
		aside_seen=aside_seen or not is_equal_approx(float(sim.world.facts.actors.b.location.cell[1]),70.0)
		local_block_seen=local_block_seen or sim.world.facts.moves.get("a",{}).has("local_move")
		if tick<12 or tick%20==0:trace.append({"tick":tick,"a":sim.world.facts.actors.a.location.cell.duplicate(),"b":sim.world.facts.actors.b.location.cell.duplicate(),"a_local":sim.world.facts.moves.get("a",{}).get("local_move",{}).duplicate(true),"b_local":sim.world.facts.moves.get("b",{}).get("local_move",{}).duplicate(true)})
		if save and tick==0:restored=_restore(suite,sim,furniture)
		if not errors.is_empty() or sim.world.facts.moves.is_empty():break
	var arrived: bool=sim.space.at(sim.world,"a",1,goals.a) and sim.space.at(sim.world,"b",1,goals.b) and sim.world.facts.moves.is_empty()
	var checks: Dictionary={"both_arrived":arrived,"real_body_sweep_and_furniture_safe":errors.is_empty(),"original_goals_paths_requests":original,"local_action_seen":local_block_seen,"only_open_side_actor_takes_aside":only_one_aside and aside_seen,"final_valid":sim.world.validate(suite.content).is_empty(),"current_json_cold_arrival":not save or restored.get("ok",false)}
	return {"case":"LOCAL-BLOCKED-MOVER","ok":checks.values().all(func(value: Variant)->bool:return value==true),"checks":checks,"steps":steps,"errors":errors,"trace":trace,"restore":restored}

func _restore(suite: RefCounted, sim: HospitalSimulation, furniture: Array[Rect2]) -> Dictionary:
	var input: Dictionary=sim.world.freeze()
	var encoder:=HospitalJsonStream.new()
	var path: String="user://blocked-local-mover.json"
	if not encoder.encode(path,input,func(_bytes: int)->bool:return true):return {"ok":false,"error":encoder.error}
	var decoder:=HospitalJsonStream.new()
	var decoded: Dictionary=decoder.decode(path,encoder.bytes,encoder.digest,func(_bytes: int)->bool:return true)
	if not decoded.ok:return {"ok":false,"error":decoder.error}
	var world:=WorldState.new(decoded.value)
	var exact: bool=world.freeze()==input and world.validate(suite.content).is_empty()
	var cold:=HospitalSimulation.new(world,suite.content)
	var result: Dictionary=_walk(suite,cold,furniture,false)
	result.stream_exact=exact;result.ok=result.ok and exact
	cold.dispose();return result
