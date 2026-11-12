extends "res://tests/acceptance/transit_busy_recovery.gd"

class ContactMovement extends HospitalMovement:
	var contacts: Array=[]
	func _init(geometry: HospitalSpace) -> void: super(geometry)
	func _local_collision(world: WorldState, actor: Dictionary, movement: Dictionary, contact: HospitalMovement.MotionResult) -> void:
		contacts.append({"tick":world.sim_tick,"id":actor.id,"blockers":contact.blocker_actor_ids.duplicate(),"requested":[contact.requested_motion.x,contact.requested_motion.y],"actual":[contact.actual_motion.x,contact.actual_motion.y]})
		super._local_collision(world,actor,movement,contact)

func _run() -> void:
	suite.content=HospitalContent.new()
	var out: String=OS.get_cmdline_user_args()[0]
	var stop_body: bool=OS.get_cmdline_user_args().size()>1 and OS.get_cmdline_user_args()[1]=="stop_body"
	if OS.get_cmdline_user_args().size()>1 and OS.get_cmdline_user_args()[1]=="continue":
		_continue_saved(out,OS.get_cmdline_user_args()[2]);return
	if OS.get_cmdline_user_args().size()>1 and OS.get_cmdline_user_args()[1]=="tail_audit":
		var source: String=OS.get_cmdline_user_args()[2]
		var final: Dictionary=FileAccess.open(source+"/final.bin",FileAccess.READ).get_var()
		var frames: Array=FileAccess.open(source+"/frames.bin",FileAccess.READ).get_var()
		var tail: Array=[]
		for facts: Dictionary in frames.slice(maxi(0,frames.size()-8)):
			tail.append({"tick":facts.sim_tick,"actor":facts.actors.zzz_later,"move":facts.moves.get("zzz_later",{})})
		FileAccess.open(out+"/audit.json",FileAccess.WRITE).store_string(JSON.stringify({"final_actor":final.actors.zzz_later,"final_move":final.moves.get("zzz_later",{}),"tail":tail},"  "))
		quit(0);return
	var sim: HospitalSimulation=suite._transit_fixture()
	var world: WorldState=sim.world
	var c: Dictionary=world.facts.connectors[suite._connection(sim)]
	suite._add_actor(sim,"aaa_incoming","S49",c.anchor,1)
	suite._add_actor(sim,"leader","S69",c.anchor,2)
	suite._add_actor(sim,"zzz_later","S52",[38,78],2)
	suite._add_actor(sim,"protected","S52",[38,76],2)
	var observer: ContactMovement=ContactMovement.new(sim.space)
	sim.space.movement=observer
	world.facts.actors.leader.facing=0.0
	world.facts.actors.zzz_later.facing=0.0
	var requests: Dictionary={}
	requests.incoming=sim.space.request_move(world,"aaa_incoming",2,[44,86])
	requests.leader=sim.space.request_move(world,"leader",1,[44,82])
	requests.later=sim.space.request_move(world,"zzz_later",1,[48,86])
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var expected_replay: Dictionary={}
	if args.size()>2:
		var loaded: Dictionary=FileAccess.open(args[2],FileAccess.READ).get_var()
		expected_replay=loaded.duplicate(true)
		sim.dispose();sim=HospitalSimulation.new(WorldState.new(loaded.duplicate(true)),suite.content);world=sim.world;c=world.facts.connectors[suite._connection(sim)]
		observer=ContactMovement.new(sim.space);sim.space.movement=observer
	var input: Dictionary=world.freeze().duplicate(true)
	var selected_envelope: Rect2=HospitalTransit._selected_entry(sim.space,world,c,"leader")
	var selected_original: Rect2=sim.space._actor_rect(world.facts.actors.leader,ConvoyTrail.point(c.anchor))
	var sample: Dictionary=world.facts.actors.zzz_later.duplicate();sample.facing=0.0
	var hypothetical_stop: Rect2=sim.space._actor_rect(sample,ConvoyTrail.point(c.anchor)+Vector2.RIGHT)
	var selected_orientation_guard: bool=not selected_original.intersects(hypothetical_stop,false) and selected_envelope.intersects(hypothetical_stop,false)
	var geometry_read_only: bool=world.freeze()==input
	FileAccess.open(out+"/preWorld.bin",FileAccess.WRITE).store_var(input)
	var error: String=world.validate(suite.content)
	var safe: bool=_floor_safety(sim,world.facts.actors.duplicate(true))
	var initial_static: Dictionary={}
	for id: String in ["leader","zzz_later"]:
		var actor: Dictionary=world.facts.actors[id]
		var point: Vector2=ConvoyTrail.point(actor.location.cell)
		initial_static[id]=sim.space.navigation.structural_clearance(world,actor,int(actor.location.floor_id)).sweep_reason(point,point)
	var stable: bool=true
	var protected: bool=true
	var bounded: bool=true
	var frames: Array=[]
	var choices: Array=[]
	var order: Array=[]
	var seen: Dictionary={}
	var reached: bool=false
	for step: int in (40 if stop_body else 400):
		if not error.is_empty() or not safe or not requests.values().all(func(v: String)->bool:return v.is_empty()) or not initial_static.values().all(func(v: String)->bool:return v.is_empty()): break
		var before: Dictionary=world.facts.actors.duplicate(true)
		suite._movement_tick(sim)
		for id: String in ["leader","zzz_later"]:
			var m: Dictionary=world.facts.moves.get(id,{})
			var original_move: Dictionary=input.moves[id]
			if not m.is_empty(): stable=stable and m.request_sequence==original_move.request_sequence and m.target_floor==original_move.target_floor and m.target_cell==original_move.target_cell
			var previous: Dictionary=before[id].location
			var current: Dictionary=world.facts.actors[id].location
			if previous.kind=="floor" and current.kind=="floor" and previous.floor_id==current.floor_id:
				bounded=bounded and ConvoyTrail.point(previous.cell).distance_to(ConvoyTrail.point(current.cell))<=sim.space.walking_speed(world.facts.actors[id])*WorldState.TICK_SECONDS+0.0001
			if m.has("route_waypoint"):
				var key: String=id+str(m.route_waypoint.cell)
				if not seen.has(key):
					seen[key]=true
					choices.append({"tick":world.sim_tick,"id":id,"actor":world.facts.actors[id].duplicate(true),"waypoint":m.route_waypoint.duplicate(true),"selected":c.get("assigned_actor_id",""),"phase":c.phase,"actors":world.facts.actors.duplicate(true)})
		var primary: String=c.get("primary_actor_id","")
		if not primary.is_empty() and not order.has(primary):order.append(primary)
		protected=protected and world.facts.actors.protected==input.actors.protected
		safe=safe and _floor_safety(sim,before)
		error=world.validate(suite.content)
		frames.append({"tick":world.sim_tick,"actors":world.facts.actors.duplicate(true),"moves":world.facts.moves.duplicate(true),"connector":c.duplicate(true)})
		if not world.facts.moves.has("leader") and not world.facts.moves.has("zzz_later"):
			reached=sim.space.at(world,"leader",1,[44,82]) and sim.space.at(world,"zzz_later",1,[48,86]);break
	var result: Dictionary={"ok":reached and safe and error.is_empty(),"requests":requests,"initial_static":initial_static,"safe":safe,"valid":error,"reached_both":reached,"ticks":frames.size(),"order":order,"choices":choices,"final_moves":world.facts.moves.duplicate(true),"contacts":observer.contacts,"selected_orientation_guard":selected_orientation_guard,"geometry_read_only":geometry_read_only,"stop_choice_safe":not choices.any(func(choice: Dictionary)->bool:return choice.id=="leader" and ConvoyTrail.point(choice.waypoint.cell)==Vector2(37,76))}
	if stop_body: result.ok=safe and error.is_empty() and result.stop_choice_safe
	result.replay_exact=expected_replay.is_empty() or input==expected_replay
	result.original_request_goal=stable
	result.protected_each_step=protected
	result.step_budget=bounded
	result.service_order=order==["aaa_incoming","leader","zzz_later"]
	result.ok=result.ok and selected_orientation_guard and geometry_read_only and result.replay_exact and stable and protected and bounded and (stop_body or result.service_order)
	FileAccess.open(out+"/frames.bin",FileAccess.WRITE).store_var(frames)
	FileAccess.open(out+"/final.bin",FileAccess.WRITE).store_var(world.freeze())
	FileAccess.open(out+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	sim.dispose();quit(0 if result.ok else 1)

func _continue_saved(out: String, source: String) -> void:
	var original: Dictionary=FileAccess.open(source,FileAccess.READ).get_var()
	var expected: Dictionary=original.duplicate(true)
	var sim: HospitalSimulation=HospitalSimulation.new(WorldState.new(original.duplicate(true)),suite.content)
	var world: WorldState=sim.world
	var exact: bool=world.freeze()==expected
	var m: Dictionary=world.facts.moves.zzz_later
	var identity: Dictionary={"sequence":m.request_sequence,"floor":m.target_floor,"cell":m.target_cell.duplicate()}
	var actor: Dictionary=world.facts.actors.zzz_later
	var point: Vector2=ConvoyTrail.point(actor.location.cell)
	var distance: float=0.0
	for segment: Dictionary in m.path.slice(int(m.cursor)):
		if segment.kind!="floor": push_error("Continuation is not only remaining ground walk");quit(1);return
		var target: Vector2=ConvoyTrail.point(segment.cell)
		distance+=point.distance_to(target);point=target
	var explanation: Dictionary={"position":actor.location.duplicate(true),"remaining_path":m.path.slice(int(m.cursor)).duplicate(true),"remaining_distance_cells":distance,"speed_cells_per_second":sim.space.walking_speed(actor),"cap":120}
	FileAccess.open(out+"/preWorld.bin",FileAccess.WRITE).store_var(expected)
	FileAccess.open(out+"/actual-preWorld.bin",FileAccess.WRITE).store_var(world.freeze())
	var safe: bool=true
	var valid: bool=true
	var stable: bool=true
	var protected: bool=true
	var arrived: bool=false
	var frames: Array=[]
	for step: int in 120:
		var before: Dictionary=world.facts.actors.duplicate(true)
		suite._movement_tick(sim)
		safe=safe and _floor_safety(sim,before)
		valid=valid and world.validate(suite.content).is_empty()
		protected=protected and world.facts.actors.protected==expected.actors.protected
		if world.facts.moves.has("zzz_later"):
			m=world.facts.moves.zzz_later
			stable=stable and m.request_sequence==identity.sequence and m.target_floor==identity.floor and m.target_cell==identity.cell
		frames.append(world.freeze().duplicate(true))
		if not world.facts.moves.has("zzz_later"):
			arrived=sim.space.at(world,"zzz_later",int(identity.floor),identity.cell);break
	var checks: Dictionary={"cold_exact":exact,"arrived":arrived,"body_sweep_safe":safe,"world_valid":valid,"original_request_goal":stable,"protected_each_step":protected}
	FileAccess.open(out+"/frames.bin",FileAccess.WRITE).store_var(frames)
	FileAccess.open(out+"/final.bin",FileAccess.WRITE).store_var(world.freeze())
	var result: Dictionary={"ok":_all(checks),"checks":checks,"input_explanation":explanation,"ticks":frames.size()}
	FileAccess.open(out+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	sim.dispose();quit(0 if result.ok else 1)
