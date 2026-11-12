extends "res://tests/acceptance/transit_waiting_identity.gd"
class ContactMovement extends HospitalMovement:
	var contacts: Array=[]
	func _init(geometry: HospitalSpace) -> void:super(geometry)
	func _local_collision(world: WorldState, actor: Dictionary, movement: Dictionary, contact: HospitalMovement.MotionResult) -> void:
		var before: Dictionary={"tick":world.sim_tick,"actor":actor.id,"blockers":contact.blocker_actor_ids.duplicate(),"requested":[contact.requested_motion.x,contact.requested_motion.y],"actual":[contact.actual_motion.x,contact.actual_motion.y],"assigned":world.facts.connectors.values()[0].get("assigned_actor_id",""),"phase":world.facts.connectors.values()[0].phase}
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
	for i: int in 9:
		var id: String="budget_%02d"%i
		suite._add_actor(sim,id,"S49",[52+i,90],2)
		assert(sim.space.request_move(world,id,2,[32+i,64]).is_empty())
	var requested: bool=_request_waiter(sim,false,1).is_empty()
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
	var twin: HospitalSimulation=null;var restored: bool=false;var cold_equal: bool=true
	var accepted: bool=false;var kept: bool=true;var cleared: bool=false;var frames: Array=[]
	for n: int in 80:
		if not valid:break
		var prior: Dictionary=world.facts.actors.duplicate(true)
		suite._movement_tick(sim)
		if twin!=null:
			suite._movement_tick(twin)
			cold_equal=cold_equal and twin.world.freeze()==world.freeze()
		for id: String in world.facts.actors:
			var actor: Dictionary=world.facts.actors[id]
			if actor.location.kind=="floor" and prior[id].location.kind=="floor" and actor.location.floor_id==prior[id].location.floor_id:
				bounded=bounded and ConvoyTrail.point(actor.location.cell).distance_to(ConvoyTrail.point(prior[id].location.cell))<=sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001
			if actor.location.kind!="floor":continue
			for other: Dictionary in world.facts.actors.values():
				if other.id<=id or other.location.kind!="floor" or other.location.floor_id!=actor.location.floor_id:continue
				bodies_clear=bodies_clear and not sim.space.body_rectangle(actor).intersects(sim.space.body_rectangle(other),false)
		var m: Dictionary=world.facts.moves.get("leader",{})
		accepted=accepted or observer.contacts.any(func(row: Dictionary)->bool:return row.pending.get("leader",{}).get("route_waypoint",{}).get("binding",{}).get("retreat_actor","")=="zz_retreat" and row.actor!=row.assigned)
		if not restored and m.get("route_waypoint",{}).has("prefix"):
			var expected: Dictionary=world.freeze().duplicate(true)
			FileAccess.open(out+"/actual-generic-pending.bin",FileAccess.WRITE).store_var(expected)
			twin=HospitalSimulation.new(WorldState.new(expected.duplicate(true)),suite.content)
			cold_equal=cold_equal and twin.world.freeze()==expected
			restored=true
		if restored:
			if twin!=null:twin.dispose()
			_budget(sim,out)
			return
		if world.facts.actors.leader.location.kind=="floor" and int(world.facts.actors.leader.location.floor_id)==2:kept=kept and m.get("transit_ticket",{})==ticket and m.request_sequence==original.request_sequence and m.target_cell==original.target_cell and m.target_floor==original.target_floor
		valid=valid and world.validate(suite.content).is_empty()
		frames.append({"tick":world.sim_tick,"actors":world.facts.actors.duplicate(true),"moves":world.facts.moves.duplicate(true),"connector":c.duplicate(true)})
		cleared=world.facts.actors.leader.location.kind=="transit"
		if accepted and cleared:break
	var result: Dictionary={"ok":restored and cold_equal and bounded and bodies_clear and requested and parked and declared and valid and accepted and kept and cleared,"step_budget":bounded,"bodies_clear":bodies_clear,"requested":requested,"actual_ticket_parked":parked,"declared_retreat":declared,"valid":valid,"actual_contact_handoff":accepted,"ticket_request_kept":kept,"actual_waiter_boarded":cleared,"pending_restored":restored,"cold_continuation_equal":cold_equal,"ticks":frames.size(),"validation":world.validate(suite.content)}
	FileAccess.open(out+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	FileAccess.open(out+"/contacts.json",FileAccess.WRITE).store_string(JSON.stringify(observer.contacts,"  "))
	FileAccess.open(out+"/frames.bin",FileAccess.WRITE).store_var(frames)
	FileAccess.open(out+"/final.bin",FileAccess.WRITE).store_var(world.freeze())
	if twin!=null:twin.dispose()
	sim.dispose();quit(0 if result.ok else 1)

func _budget(sim: HospitalSimulation,out: String) -> void:
	var w: WorldState=sim.world;var m: Dictionary=w.facts.moves.leader;var original: Dictionary=m.duplicate(true)
	var actor_before: Dictionary=w.facts.actors.leader.duplicate(true)
	var root_before: Dictionary=w.facts.actors.zz_retreat.duplicate(true)
	var root_request: int=w.facts.moves.zz_retreat.request_sequence
	var earlier: Array=[]
	for i: int in 9:
		var id: String="budget_%02d"%i;var journey: Dictionary=w.facts.moves.get(id,{})
		if journey.is_empty():continue
		sim.space.movement.queue_waypoint(w,journey,2,w.facts.actors[id].location.cell.duplicate())
		earlier.append({"id":id,"sequence":journey.request_sequence})
	var retarget: String=sim.space.request_move(w,"zz_retreat",2,[34,76])
	var budget: int=maxi(int(suite.content.balance.pathfinding.minimum_actor_requests_per_tick),ceili(float(w.present_actor_count())/float(suite.content.balance.pathfinding.actors_per_request)))
	var dispatched: int=int(sim.space.query_counts.get("route_dispatches",0))
	FileAccess.open(out+"/budget-pre.bin",FileAccess.WRITE).store_var(w.freeze())
	suite._movement_tick(sim)
	var checks: Dictionary={"formal_root_retarget":retarget.is_empty() and w.facts.moves.zz_retreat.request_sequence!=root_request,"earlier_genuine_requests":earlier.size()>budget and earlier.all(func(row: Dictionary)->bool:return row.sequence<original.request_sequence),"configured_budget_consumed":int(sim.space.query_counts.get("route_dispatches",0))-dispatched==budget,"actual_pending_deferred":m.has("route_waypoint") and m.get("route_pending",false),"step_end_valid":w.validate(suite.content).is_empty(),"waiter_task_ticket_preserved":m.path==original.path and m.cursor==original.cursor and m.request_sequence==original.request_sequence and m.transit_ticket==original.transit_ticket and m.transit_wait==original.transit_wait}
	var expected: Dictionary=w.freeze().duplicate(true);FileAccess.open(out+"/budget-step-end.bin",FileAccess.WRITE).store_var(expected)
	sim.dispose();sim=HospitalSimulation.new(WorldState.new(expected.duplicate(true)),suite.content);w=sim.world;m=w.facts.moves.leader
	checks.cold_exact=w.freeze()==expected
	sim.space.movement._dispatch_routes(w,w.present_actor_count())
	checks.stale_prefix_rejected=not m.has("route_waypoint") and not m.get("route_pending",false)
	checks.atomic_waiter_unchanged=m.path==original.path and m.cursor==original.cursor and m.request_sequence==original.request_sequence and m.transit_ticket==original.transit_ticket and m.transit_wait==original.transit_wait and w.facts.actors.leader==actor_before
	FileAccess.open(out+"/dispatch-final.bin",FileAccess.WRITE).store_var(w.freeze())
	suite._movement_tick(sim)
	checks.root_actual_departure=w.facts.actors.zz_retreat.location!=root_before.location
	checks.final_valid=w.validate(suite.content).is_empty()
	FileAccess.open(out+"/departure-final.bin",FileAccess.WRITE).store_var(w.freeze())
	var passed: bool=checks.values().all(func(v: Variant)->bool:return bool(v))
	FileAccess.open(out+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"ok":passed,"checks":checks,"configured_budget":budget,"earlier":earlier,"waiter_request":original.request_sequence,"validation":w.validate(suite.content)},"  "))
	sim.dispose();quit(0 if passed else 1)
