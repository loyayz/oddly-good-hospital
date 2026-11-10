extends SceneTree

class ContactMovement extends HospitalMovement:
	var goal_contacts: int=0
	var middle_contacts: int=0
	func _init(geometry: HospitalSpace) -> void:super(geometry)
	func _local_collision(world: WorldState, actor: Dictionary, movement: Dictionary, contact: MotionResult) -> void:
		if actor.id=="walker":
			if "holder" in contact.blocker_actor_ids:goal_contacts+=1
			if "middle" in contact.blocker_actor_ids:middle_contacts+=1
		super._local_collision(world,actor,movement,contact)

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1:push_error("Output JSON required");quit(2);return
	var suite: RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=HospitalContent.new()
	var cases: Array=[_case(suite,false),_case(suite,true)]
	var result: Dictionary={"ok":cases.all(func(row: Dictionary)->bool:return row.ok),"cases":cases}
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify({"ok":result.ok,"cases":cases.map(func(row: Dictionary)->Dictionary:return {"case":row.case,"checks":row.checks})}))
	quit(0 if result.ok else 1)

func _case(suite: RefCounted, middle: bool) -> Dictionary:
	var sim: HospitalSimulation=suite._fixture()
	var goal: Array=[46,70] if middle else [43,70]
	suite._add_actor(sim,"walker","S49",[40,70])
	suite._add_actor(sim,"holder","S49",goal)
	if middle:suite._add_actor(sim,"middle","S49",[42,70])
	var observer:=ContactMovement.new(sim.space);sim.space.movement=observer
	var validation: String=sim.world.validate(suite.content)
	var request: String=sim.space.request_move(sim.world,"walker",1,goal)
	var sequence: int=int(sim.world.facts.moves.walker.request_sequence)
	var paths: Array=[]
	var ids: Array=["walker","holder","middle"] if middle else ["walker","holder"]
	var probe: RefCounted=load("res://tests/acceptance/movement_detour.gd").new()
	var errors: Array=[]
	var trace: Array=[]
	var position: Array=[]
	var held_ticks: int=0
	var stable: bool=true
	var original: bool=true
	var passed_middle: bool=not middle
	for tick: int in 180:
		var error: String=probe._tick(suite,sim,ids)
		if not error.is_empty():errors.append(error);break
		var move: Dictionary=sim.world.facts.moves.get("walker",{})
		if paths.is_empty():paths=move.get("path",[]).duplicate(true)
		original=original and move.get("target_cell",[])==goal and int(move.get("request_sequence",-1))==sequence and move.get("path",[])==paths
		var cell: Array=sim.world.facts.actors.walker.location.cell
		if observer.goal_contacts==0 and middle:passed_middle=passed_middle or float(cell[0])>43.0
		if observer.goal_contacts>0:
			if position.is_empty():position=cell.duplicate()
			stable=stable and cell==position
			held_ticks+=1
		if tick%10==0:trace.append({"tick":tick,"cell":cell.duplicate(),"local":move.get("local_move",{}).duplicate(true),"goal_contacts":observer.goal_contacts})
		if held_ticks>=30:break
	var cold: Dictionary=_restore(suite,sim,ids,goal,sequence,paths)
	var released: Dictionary=_finish(suite,sim,ids,goal,sequence,paths)
	var checks: Dictionary={"initial_valid":validation.is_empty() and request.is_empty(),"real_goal_contact":observer.goal_contacts>0,"safe_real_steps":errors.is_empty(),"stationary_contact_waits_stably":stable and held_ticks>=30,"original_goal_path_request":original,"future_goal_body_does_not_veto_middle_bypass":passed_middle and (not middle or observer.middle_contacts>0),"real_release_and_arrival":released.get("ok",false),"current_json_cold_complete_arrival":cold.get("ok",false)}
	var result: Dictionary={"case":"LOCAL-GOAL-CONTACT-MIDDLE" if middle else "LOCAL-GOAL-CONTACT","ok":checks.values().all(func(value: Variant)->bool:return value==true),"checks":checks,"errors":errors,"trace":trace,"release":released,"restore":cold}
	sim.dispose();return result

func _finish(suite: RefCounted, sim: HospitalSimulation, ids: Array, goal: Array, sequence: int, path: Array) -> Dictionary:
	var probe: RefCounted=load("res://tests/acceptance/movement_detour.gd").new()
	var request: String=sim.space.request_move(sim.world,"holder",1,[goal[0],67])
	var errors: Array=[]
	var original: bool=true
	var middle_kept: bool=true
	var steps: int=0
	for tick: int in 180:
		var error: String=probe._tick(suite,sim,ids);steps+=1
		if not error.is_empty():errors.append(error);break
		var move: Dictionary=sim.world.facts.moves.get("walker",{})
		original=original and (move.is_empty() or move.target_cell==goal and int(move.request_sequence)==sequence and move.path==path)
		if ids.has("middle"):middle_kept=middle_kept and sim.world.facts.actors.middle.location.cell==[42,70] and not sim.world.facts.moves.has("middle")
		if sim.world.facts.moves.is_empty():break
	var arrived: bool=sim.space.at(sim.world,"walker",1,goal) and sim.space.at(sim.world,"holder",1,[goal[0],67]) and sim.world.facts.moves.is_empty()
	return {"ok":request.is_empty() and arrived and original and middle_kept and errors.is_empty(),"both_arrived":arrived,"original_goal_path_request":original,"middle_kept":middle_kept,"steps":steps,"errors":errors}

func _restore(suite: RefCounted, sim: HospitalSimulation, ids: Array, goal: Array, sequence: int, path: Array) -> Dictionary:
	var facts: Dictionary=sim.world.freeze()
	var encoder:=HospitalJsonStream.new();var file: String="user://local-goal-contact.json"
	if not encoder.encode(file,facts,func(_bytes: int)->bool:return true):return {"ok":false,"error":encoder.error}
	var decoder:=HospitalJsonStream.new()
	var decoded: Dictionary=decoder.decode(file,encoder.bytes,encoder.digest,func(_bytes: int)->bool:return true)
	if not decoded.ok:return {"ok":false,"error":decoder.error}
	var world:=WorldState.new(decoded.value)
	var exact: bool=world.freeze()==facts and world.validate(suite.content).is_empty()
	var cold:=HospitalSimulation.new(world,suite.content)
	var result: Dictionary=_finish(suite,cold,ids,goal,sequence,path)
	result.stream_exact=exact;result.ok=result.ok and exact
	cold.dispose();return result
