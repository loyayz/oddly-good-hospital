extends SceneTree

# Legal mid-journey contact: the leaver already owns a side step. Both actors
# execute production movement; no displacement or successful arrival is mocked.

class ObserveMovement extends HospitalMovement:
	var contacts: int=0
	func _init(geometry: HospitalSpace) -> void: super(geometry)
	func _move_step(world: WorldState, actor: Dictionary, movement: Dictionary, segment: Dictionary) -> MotionResult:
		var result: MotionResult=super._move_step(world,actor,movement,segment)
		if actor.id=="walker" and result.blocker_actor_ids.has("leaver"): contacts+=1
		return result

func _point(cell: Array) -> Dictionary:
	return {"kind":"floor","floor_id":1,"cell":cell.duplicate()}

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1: push_error("Output JSON required");quit(2);return
	var content:=HospitalContent.new()
	var suite: RefCounted=load("res://tests/acceptance/space.gd").new()
	suite.content=content
	var sim: HospitalSimulation=suite._fixture()
	suite._add_actor(sim,"walker","S49",[40,70])
	suite._add_actor(sim,"leaver","S49",[40.6,70])
	var paths: Dictionary={"walker":[_point([41,70]),_point([43,70])],"leaver":[_point([41,70]),_point([45,70])]}
	var goals: Dictionary={"walker":[43,70],"leaver":[45,70]}
	sim.world.facts.move_request_next=2
	sim.world.facts.moves["walker"]={"actor_id":"walker","path":paths.walker.duplicate(true),"cursor":0,"travelled":[_point([39,70]),_point([39,71]),_point([40,71]),_point([40,70])],"blocked_since":-1,"target_floor":1,"target_cell":goals.walker.duplicate(),"request_sequence":1,"local_move":{"origin":[39,70],"target":_point([41,70]),"rejoin":{"index":0,"cell":[41,70]}}}
	sim.world.facts.moves["leaver"]={"actor_id":"leaver","path":paths.leaver.duplicate(true),"cursor":0,"travelled":[_point([40.6,70])],"blocked_since":-1,"target_floor":1,"target_cell":goals.leaver.duplicate(),"request_sequence":2,"local_move":{"origin":[40.6,70],"target":_point([40.6,71])}}
	sim.world.touch()
	var initial: String=sim.world.validate(content)
	var observer:=ObserveMovement.new(sim.space)
	sim.space.movement=observer
	var probe: RefCounted=load("res://tests/acceptance/movement_detour.gd").new()
	var errors: Array=[]
	var original: bool=true
	var first_intent_kept: bool=false
	var unnecessary_aside: bool=false
	var resumed_before_finished: bool=false
	var first: Dictionary={}
	var restored: Dictionary={}
	var trace: Array=[]
	for tick: int in 180:
		var error: String=probe._tick(suite,sim,["walker","leaver"])
		if not error.is_empty(): errors.append(error);break
		for id: String in goals:
			var move: Dictionary=sim.world.facts.moves.get(id,{})
			original=original and (move.is_empty() or move.path==paths[id] and move.target_cell==goals[id] and int(move.request_sequence)==(1 if id=="walker" else 2))
		var a: Dictionary=sim.world.facts.actors["walker"]
		var b: Dictionary=sim.world.facts.actors["leaver"]
		if float(b.location.cell[1])<70.99:
			unnecessary_aside=unnecessary_aside or not is_equal_approx(float(a.location.cell[1]),70.0)
			resumed_before_finished=resumed_before_finished or float(a.location.cell[0])>40.01
		if tick==0:
			first=sim.world.facts.moves["walker"].duplicate(true)
			first_intent_kept=first.has("local_move") and first.local_move.has("rejoin") and ConvoyTrail.point(first.local_move.target.cell)==Vector2(41,70) and int(first.local_move.rejoin.index)==0
			restored=probe._restore_boundary(suite,sim,"walker",["walker","leaver"])
		if tick<10 or tick%20==0: trace.append({"tick":tick,"walker":a.location.cell.duplicate(),"leaver":b.location.cell.duplicate(),"a_local":sim.world.facts.moves.get("walker",{}).get("local_move",{}).duplicate(true)})
		if sim.world.facts.moves.is_empty(): break
	var arrived: bool=sim.space.at(sim.world,"walker",1,goals.walker) and sim.space.at(sim.world,"leaver",1,goals.leaver) and sim.world.facts.moves.is_empty()
	var checks: Dictionary={"initial_valid":initial.is_empty(),"real_contact":observer.contacts>0,"existing_intent_kept_while_other_clears":first_intent_kept,"only_existing_actor_takes_aside":not unnecessary_aside,"resume_without_waiting_for_whole_aside":resumed_before_finished,"both_arrived":arrived,"safe_real_steps":errors.is_empty(),"original_goals_paths_requests":original,"current_json_restore":restored.get("ok",false),"final_valid":sim.world.validate(content).is_empty()}
	var result: Dictionary={"case":"LOCAL-ONE-AVOIDER","ok":checks.values().all(func(value: Variant)->bool:return value==true),"checks":checks,"initial_validation":initial,"first_move":first,"errors":errors,"trace":trace,"restored":restored}
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(checks))
	sim.dispose()
	quit(0 if result.ok else 1)
