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
	var origin_floor: int=1 if args[0] in ["up","nurse"] else 2
	var destination_floor: int=3-origin_floor
	var sim: HospitalSimulation=_order_fixture(false,origin_floor)
	var world: WorldState=sim.world;var c: Dictionary=world.facts.connectors[suite._connection(sim)]
	var anchor: Vector2=ConvoyTrail.point(c.anchor)
	suite._add_actor(sim,"aaa_incoming","S49",c.anchor,destination_floor)
	if args[0]=="nurse":
		suite._add_staff(sim,"later","nurse",[anchor.x+2,anchor.y+2])
		world.facts.actors.later.species_id="S27"
		sim.space.sync_actor(world,"later")
	else:
		suite._add_actor(sim,"later","S49",[anchor.x+2,anchor.y+2],origin_floor)
	if args[0]=="nurse":
		# Complete ordinary staff growth defaults during fixture generation,
		# before requests and before the independently saved test boundary.
		var generated: Dictionary=world.freeze().duplicate(true)
		FileAccess.open(out+"/generated-before-initialization.bin",FileAccess.WRITE).store_var(generated)
		sim.dispose();sim=HospitalSimulation.new(WorldState.new(generated.duplicate(true)),suite.content)
		world=sim.world;c=world.facts.connectors[suite._connection(sim)]
	var requested: bool=sim.space.request_move(world,"aaa_incoming",origin_floor,[44,86]).is_empty()
	requested=requested and _request_waiter(sim,false,destination_floor).is_empty()
	requested=requested and sim.space.request_move(world,"later",destination_floor,[44,84]).is_empty()
	var original: Dictionary=world.facts.moves.duplicate(true)
	FileAccess.open(out+"/preWorld.bin",FileAccess.WRITE).store_var(world.freeze())
	var observer:=ContactMovement.new(sim.space);sim.space.movement=observer
	var declared_layout: Dictionary={}
	var reached: Dictionary={"leader":false,"later":false}
	var published_restored: bool=false
	var declared: bool=false
	var declaration_legal: bool=true
	var twin: HospitalSimulation=null
	var restored: bool=false
	var cold_equal: bool=true
	var bounded: bool=true
	var bodies_clear: bool=true
	var quote_readonly: bool=true
	var frames: Array=[];var stable: bool=true;var legal: bool=true;var boarded: bool=false;var later_boarded: bool=false;var tokens: Dictionary={};var kept: bool=true
	for step: int in 240:
		var prior: Dictionary=world.facts.actors.duplicate(true)
		suite._movement_tick(sim)
		if twin!=null:
			suite._movement_tick(twin)
			cold_equal=cold_equal and world.freeze()==twin.world.freeze()
		for id: String in world.facts.actors:
			var actor: Dictionary=world.facts.actors[id]
			if actor.location.kind=="floor" and prior[id].location.kind=="floor" and actor.location.floor_id==prior[id].location.floor_id:
				bounded=bounded and ConvoyTrail.point(actor.location.cell).distance_to(ConvoyTrail.point(prior[id].location.cell))<=sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001
			if actor.location.kind!="floor":continue
			for other: Dictionary in world.facts.actors.values():
				if other.id<=id or other.location.kind!="floor" or other.location.floor_id!=actor.location.floor_id:continue
				bodies_clear=bodies_clear and not sim.space.body_rectangle(actor).intersects(sim.space.body_rectangle(other),false)
		if not restored:
			for m: Dictionary in world.facts.moves.values():
				if not m.get("route_waypoint",{}).has("prefix"):continue
				var frozen: Dictionary=world.freeze().duplicate(true)
				FileAccess.open(out+"/actual-pending.bin",FileAccess.WRITE).store_var(frozen)
				twin=HospitalSimulation.new(WorldState.new(frozen.duplicate(true)),suite.content)
				cold_equal=cold_equal and frozen==twin.world.freeze()
				restored=true
				var before_quote: Dictionary=world.freeze().duplicate(true)
				HospitalTransit.quote(sim.space,world,c,m.actor_id,int(m.transit_ticket.from),int(m.transit_ticket.to),0,[m.actor_id],{})
				quote_readonly=quote_readonly and world.freeze()==before_quote
				break
		if declared:
			for id: String in reached:
				var location: Dictionary=world.facts.actors[id].location
				if location.kind=="floor" and int(location.floor_id)==origin_floor and ConvoyTrail.point(location.cell)==ConvoyTrail.point(declared_layout[id]):reached[id]=true
		if restored and not published_restored and not world.facts.moves.get("later",{}).has("route_waypoint"):
			var frozen: Dictionary=world.freeze().duplicate(true)
			FileAccess.open(out+"/actual-published.bin",FileAccess.WRITE).store_var(frozen)
			if twin!=null:twin.dispose()
			twin=HospitalSimulation.new(WorldState.new(frozen.duplicate(true)),suite.content)
			cold_equal=cold_equal and twin.world.freeze()==frozen
			published_restored=true
		legal=legal and world.validate(suite.content).is_empty()
		for id: String in ["leader","later"]:
			var m: Dictionary=world.facts.moves.get(id,{})
			if not m.is_empty():stable=stable and m.request_sequence==original[id].request_sequence and m.target_floor==original[id].target_floor and m.target_cell==original[id].target_cell
			if m.has("transit_ticket"):
				if not tokens.has(id):tokens[id]=m.transit_ticket.duplicate(true)
				kept=kept and tokens[id]==m.transit_ticket
		if not declared and tokens.has("leader") and tokens.has("later"):
			var ready: bool=true
			for id: String in ["leader","later"]:
				var m: Dictionary=world.facts.moves[id]
				ready=ready and not m.get("route_pending",false) and not m.has("local_move") and int(m.cursor)<m.path.size() and m.path[int(m.cursor)].kind=="connector"
			if ready:
				FileAccess.open(out+"/declaration-before.bin",FileAccess.WRITE).store_var(world.freeze())
				var declared_points: Dictionary={"leader":[anchor.x-2,anchor.y],"later":[anchor.x-1,anchor.y]}
				declared_layout=declared_points.duplicate(true)
				for id: String in declared_points:
					var actor: Dictionary=world.facts.actors[id];var cell: Array=declared_points[id]
					declaration_legal=declaration_legal and sim.space.static_reason(world,actor,origin_floor,Vector2i(int(cell[0]),int(cell[1])),[id],{}).is_empty()
					var rect: Rect2=sim.space._actor_rect(actor,ConvoyTrail.point(cell))
					for room: Dictionary in world.facts.rooms.values():
						if int(room.floor_id)==origin_floor and rect.intersects(Rect2(ConvoyTrail.point(room.origin),ConvoyTrail.point(room.size)),false):declaration_legal=false
					sim.space.movement.queue_waypoint(world,world.facts.moves[id],origin_floor,cell,true)
					world.facts.moves[id].transit_wait={"sequence":world.facts.moves[id].request_sequence,"cell":cell.duplicate()}
				FileAccess.open(out+"/declaration-after.bin",FileAccess.WRITE).store_var(world.freeze())
				FileAccess.open(out+"/declaration.json",FileAccess.WRITE).store_string(JSON.stringify({"kind":"declared Transit-owned public waiting layout, not natural stand-aside selection","points":declared_points,"tick":world.sim_tick}))
				declared=true
		if world.facts.actors.leader.location.kind=="transit":boarded=true
		if world.facts.actors.later.location.kind=="transit":later_boarded=true
		frames.append({"tick":world.sim_tick,"actors":world.facts.actors.duplicate(true),"moves":world.facts.moves.duplicate(true),"connector":c.duplicate(true)})
		if boarded and later_boarded:break
	var accepted: bool=observer.contacts.any(func(row: Dictionary)->bool:return not row.pending.is_empty())
	var result: Dictionary={"ok":published_restored and reached.values().all(func(v: Variant)->bool:return bool(v)) and restored and cold_equal and bounded and bodies_clear and quote_readonly and declared and declaration_legal and requested and legal and stable and kept and accepted and boarded and later_boarded,"actual_declared_points_reached":reached,"published_restored":published_restored,"pending_restored":restored,"cold_continuation_equal":cold_equal,"step_budget":bounded,"bodies_clear":bodies_clear,"quote_readonly":quote_readonly,"declared":declared,"declaration_static_legal":declaration_legal,"requested":requested,"legal":legal,"original_task":stable,"tickets_kept":kept,"actual_contact_handoff":accepted,"leader_boarded":boarded,"later_boarded":later_boarded,"ticks":frames.size(),"validation":world.validate(suite.content)}
	FileAccess.open(out+"/frames.bin",FileAccess.WRITE).store_var(frames)
	FileAccess.open(out+"/final.bin",FileAccess.WRITE).store_var(world.freeze())
	FileAccess.open(out+"/contacts.json",FileAccess.WRITE).store_string(JSON.stringify(observer.contacts,"  "))
	FileAccess.open(out+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	if twin!=null:twin.dispose()
	sim.dispose();quit(0 if result.ok else 1)
