extends "res://tests/acceptance/transit_waiting_identity.gd"
class ContactMovement extends HospitalMovement:
	var contacts: Array=[]
	func _init(geometry: HospitalSpace) -> void:super(geometry)
	func _local_collision(world: WorldState, actor: Dictionary, movement: Dictionary, contact: HospitalMovement.MotionResult) -> void:
		var before: Dictionary={"tick":world.sim_tick,"actor":actor.id,"blockers":contact.blocker_actor_ids.duplicate(),"requested":[contact.requested_motion.x,contact.requested_motion.y],"actual":[contact.actual_motion.x,contact.actual_motion.y]}
		super._local_collision(world,actor,movement,contact)
		before.pending={}
		for id: String in contact.blocker_actor_ids:
			if world.facts.moves.get(id,{}).get("route_waypoint",{}).has("prefix"):before.pending[id]=world.facts.moves[id].duplicate(true)
		contacts.append(before)

func _run() -> void:
	var args:=OS.get_cmdline_user_args();var out: String=args[1]
	suite.content=HospitalContent.new()
	var sim: HospitalSimulation=_order_fixture(false,2);var world: WorldState=sim.world
	var c: Dictionary=world.facts.connectors[suite._connection(sim)];var anchor: Vector2=ConvoyTrail.point(c.anchor)
	suite._add_actor(sim,"aaa_incoming","S49",c.anchor,1)
	var requested: bool=sim.space.request_move(world,"aaa_incoming",2,[44,86]).is_empty() and _request_waiter(sim,false,1).is_empty()
	var ticket: Dictionary={};var parked: bool=false;var declared: bool=false
	for n: int in 25:
		suite._movement_tick(sim)
		var m: Dictionary=world.facts.moves.get("leader",{})
		if ticket.is_empty() and m.has("transit_ticket"):
			ticket=m.transit_ticket.duplicate(true)
			sim.space.movement.queue_waypoint(world,m,2,[anchor.x+1,anchor.y],true)
			m.transit_wait={"sequence":m.request_sequence,"cell":[anchor.x+1,anchor.y]}
		if not ticket.is_empty() and ConvoyTrail.point(world.facts.actors.leader.location.cell)==anchor+Vector2.RIGHT and not m.get("route_pending",false) and not m.has("local_move"):
			parked=true;break
	FileAccess.open(out+"/actual-ticket-parked.bin",FileAccess.WRITE).store_var(world.freeze())
	suite._add_actor(sim,"zz_retreat","S49",[anchor.x+0.4,anchor.y],2)
	requested=requested and sim.space.request_move(world,"zz_retreat",1,[44,84]).is_empty()
	suite._movement_tick(sim)
	var root: Dictionary=world.facts.moves.zz_retreat
	var point: Vector2=ConvoyTrail.point(world.facts.actors.zz_retreat.location.cell)
	# Declared legal pre-contact retreat intent; not a claim that this test
	# simulated the preceding collision that selected it. Body is never moved.
	FileAccess.open(out+"/retreat-declaration-before.bin",FileAccess.WRITE).store_var(world.freeze())
	root.local_move={"origin":[point.x,point.y],"retreat":true,"target":{"kind":"floor","floor_id":2,"cell":[point.x+2.0,point.y]}}
	declared=true
	var valid: bool=world.validate(suite.content).is_empty();var original: Dictionary=world.facts.moves.leader.duplicate(true)
	FileAccess.open(out+"/preWorld.bin",FileAccess.WRITE).store_var(world.freeze())
	var observer:=ContactMovement.new(sim.space);sim.space.movement=observer
	var bounded: bool=true;var bodies_clear: bool=true
	var accepted: bool=false;var kept: bool=true;var cleared: bool=false;var frames: Array=[]
	for n: int in 40:
		if not valid:break
		var prior: Dictionary=world.facts.actors.duplicate(true)
		suite._movement_tick(sim)
		for id: String in world.facts.actors:
			var actor: Dictionary=world.facts.actors[id]
			if actor.location.kind=="floor" and prior[id].location.kind=="floor" and actor.location.floor_id==prior[id].location.floor_id:
				bounded=bounded and ConvoyTrail.point(actor.location.cell).distance_to(ConvoyTrail.point(prior[id].location.cell))<=sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001
			if actor.location.kind!="floor":continue
			for other: Dictionary in world.facts.actors.values():
				if other.id<=id or other.location.kind!="floor" or other.location.floor_id!=actor.location.floor_id:continue
				bodies_clear=bodies_clear and not sim.space.body_rectangle(actor).intersects(sim.space.body_rectangle(other),false)
		var m: Dictionary=world.facts.moves.get("leader",{})
		accepted=accepted or observer.contacts.any(func(row: Dictionary)->bool:return row.pending.has("leader"))
		if world.facts.actors.leader.location.kind=="floor" and int(world.facts.actors.leader.location.floor_id)==2:kept=kept and m.get("transit_ticket",{})==ticket and m.request_sequence==original.request_sequence and m.target_cell==original.target_cell and m.target_floor==original.target_floor
		valid=valid and world.validate(suite.content).is_empty()
		frames.append({"tick":world.sim_tick,"actors":world.facts.actors.duplicate(true),"moves":world.facts.moves.duplicate(true),"connector":c.duplicate(true)})
		cleared=world.facts.actors.aaa_incoming.location.kind=="floor" and int(world.facts.actors.aaa_incoming.location.floor_id)==2
		if accepted and cleared:break
	var result: Dictionary={"ok":bounded and bodies_clear and requested and parked and declared and valid and accepted and kept and cleared,"step_budget":bounded,"bodies_clear":bodies_clear,"requested":requested,"actual_ticket_parked":parked,"declared_retreat":declared,"valid":valid,"actual_contact_handoff":accepted,"ticket_request_kept":kept,"incoming_landed":cleared,"ticks":frames.size(),"validation":world.validate(suite.content)}
	FileAccess.open(out+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	FileAccess.open(out+"/contacts.json",FileAccess.WRITE).store_string(JSON.stringify(observer.contacts,"  "))
	FileAccess.open(out+"/frames.bin",FileAccess.WRITE).store_var(frames)
	FileAccess.open(out+"/final.bin",FileAccess.WRITE).store_var(world.freeze())
	sim.dispose();quit(0 if result.ok else 1)
