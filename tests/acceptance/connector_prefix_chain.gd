extends "res://tests/acceptance/convoy_transit.gd"

# Test-only observer: records the actual kernel result before unchanged handling.
class ContactMovement extends HospitalMovement:
	var contacts: Array=[]
	func _init(geometry: HospitalSpace) -> void: super(geometry)
	func _local_collision(world: WorldState, actor: Dictionary, movement: Dictionary, contact: HospitalMovement.MotionResult) -> void:
		contacts.append({"tick":world.sim_tick,"actor":actor.id,"blockers":contact.blocker_actor_ids.duplicate(),"requested":[contact.requested_motion.x,contact.requested_motion.y],"actual":[contact.actual_motion.x,contact.actual_motion.y],"static":contact.static_reason,"door":contact.door_id})
		super._local_collision(world,actor,movement,contact)

func _sequential_contacts(contacts: Array) -> bool:
	var first: int=-1
	for index: int in contacts.size():
		var entry: Dictionary=contacts[index]
		if entry.actor=="b_retreat" and "a_waiter" in entry.blockers and ConvoyTrail.point(entry.requested).length()>0.0:
			if first<0:first=index
		if first>=0 and index>first and entry.actor=="a_waiter" and "protected_stationary" in entry.blockers and ConvoyTrail.point(entry.requested).length()>0.0:return true
	return false

func _save(path: String,value: Variant) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_var(value,false);file.close()
func _run() -> void:
	var args:=OS.get_cmdline_user_args();var out: String=args[1]
	suite.content=HospitalContent.new()
	var rows: Array=[]
	for role: String in ["nurse_chain"]:
		rows.append(_case(out,role))
	var passed: bool=rows.all(func(row: Dictionary)->bool:return row.passed)
	var file:=FileAccess.open(out+"/result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"passed":passed,"rows":rows},"\t"));file.close();quit(0 if passed else 1)
func _case(out: String, role: String) -> Dictionary:
	var sim: HospitalSimulation=suite._transit_fixture();var world: WorldState=sim.world
	var connection: Dictionary=world.facts.connectors[suite._connection(sim)]
	var anchor: Vector2=ConvoyTrail.point(connection.anchor)
	var retreat_y: float=anchor.y
	# Declared legal pre-contact input. a_waiter sorts before b_retreat;
	# this fixes input order, never production priority. Not a boarding replay.
	# Staff records come from the same factory as normal new staff.
	suite._add_staff(sim,"a_waiter",role.split("_")[0],[anchor.x+1,anchor.y])
	suite._add_actor(sim,"b_retreat","S49",[anchor.x+0.4,retreat_y],2)
	suite._add_actor(sim,"incoming","S49",connection.anchor,1)
	world.facts.actors.a_waiter.location.floor_id=2
	world.facts.actors.a_waiter.species_id="S49"
	connection.phase="alighting";connection.from=1;connection.to=2;connection.floor_id=1;connection.remaining_ticks=1;connection.riders=["incoming"];connection.primary_actor_id="incoming";connection.ticket_next=1;connection.trip_sequence=1
	world.facts.actors.incoming.location={"kind":"transit","connector_id":connection.id,"from":1,"to":2}
	var segment: Dictionary={"kind":"connector","connector_id":connection.id,"from":2,"to":1}
	world.facts.moves["a_waiter"]={"actor_id":"a_waiter","path":[segment.duplicate()],"cursor":0,"travelled":[{"kind":"floor","floor_id":2,"cell":[anchor.x+1,anchor.y]}],"blocked_since":-1,"request_sequence":2,"target_floor":1,"target_cell":[44,82]}
	world.facts.moves["b_retreat"]={"actor_id":"b_retreat","path":[{"kind":"floor","floor_id":2,"cell":[anchor.x-1,retreat_y]},segment.duplicate()],"cursor":0,"travelled":[{"kind":"floor","floor_id":2,"cell":connection.anchor.duplicate()}],"blocked_since":-1,"request_sequence":3,"target_floor":1,"target_cell":[44,84],"local_move":{"origin":connection.anchor.duplicate(),"retreat":true,"target":{"kind":"floor","floor_id":2,"cell":[anchor.x+2.8,retreat_y]}}}
	world.facts.moves["incoming"]={"actor_id":"incoming","path":[{"kind":"connector","connector_id":connection.id,"from":1,"to":2},{"kind":"floor","floor_id":2,"cell":[44,86]}],"cursor":1,"travelled":[],"blocked_since":-1,"request_sequence":1,"target_floor":2,"target_cell":[44,86]}
	world.facts.move_request_next=3
	suite._add_actor(sim,"protected_stationary","S49",[anchor.x+1,anchor.y+0.5],2)
	var input: Dictionary=world.freeze()
	var replay: PackedStringArray=OS.get_cmdline_user_args()
	if replay.size()>3:
		var saved:=FileAccess.open(replay[3],FileAccess.READ);input=saved.get_var(false);saved.close()
	var expected: Dictionary=input.duplicate(true)
	_save(out+"/"+role+"-preWorld.bin",expected)
	sim.dispose();world=WorldState.new(input);sim=HospitalSimulation.new(world,suite.content)
	var restore_exact: bool=world.freeze()==expected
	_save(out+"/"+role+"-actual-preWorld.bin",world.freeze())
	var plain: bool=replay.size()>2 and replay[2]=="plain"
	var observer: ContactMovement=null
	if not plain:
		observer=ContactMovement.new(sim.space)
		sim.space.movement=observer
	var error: String=world.validate(suite.content)
	for actor: Dictionary in world.facts.actors.values():
		if actor.location.kind=="floor":
			var point: Vector2=ConvoyTrail.point(actor.location.cell)
			var reason: String=sim.space.navigation.structural_clearance(world,actor,int(actor.location.floor_id)).sweep_reason(point,point)
			if not reason.is_empty():error="initial structural "+actor.id+": "+reason
	var start_rect: Rect2=sim.space.body_rectangle(world.facts.actors.a_waiter)
	var obstacle_rect: Rect2=sim.space.body_rectangle(world.facts.actors.protected_stationary)
	var end_rect: Rect2=HospitalTransit._release_stop_rect(sim.space,world.facts.actors.a_waiter,Vector2(37,77),Vector2.DOWN)
	var start_gap: float=obstacle_rect.position.y-start_rect.end.y
	var end_gap: float=end_rect.position.y-obstacle_rect.end.y
	var initial_geometry: bool=start_gap>0.03 and end_gap>0.03 and not start_rect.intersects(obstacle_rect,false) and not end_rect.intersects(obstacle_rect,false)
	for a: Dictionary in world.facts.actors.values():
		if a.location.kind!="floor":continue
		for b: Dictionary in world.facts.actors.values():
			if b.id<=a.id or b.location.kind!="floor" or b.location.floor_id!=a.location.floor_id:continue
			initial_geometry=initial_geometry and not sim.space.body_rectangle(a).intersects(sim.space.body_rectangle(b),false)
	var protected_initial: Dictionary=expected.actors["protected_stationary"].duplicate(true)
	var protected_unchanged: bool=true
	if not error.is_empty():sim.dispose();return {"passed":false,"role":role,"validation":error}
	var frames: Array=[];var accepted: bool=false;var moved: bool=false;var stable: bool=true;var valid: bool=true;var bounded: bool=true;var bodies_clear: bool=true
	for n: int in range(40):
		var before: Dictionary=world.facts.actors.a_waiter.location.duplicate(true)
		var prior: Dictionary=world.facts.actors.duplicate(true)
		suite._movement_tick(sim)
		var m: Dictionary=world.facts.moves.get("a_waiter",{})
		accepted=accepted or m.get("route_waypoint",{}).has("prefix")
		moved=moved or before!=world.facts.actors.a_waiter.location
		stable=stable and not m.is_empty() and m.get("request_sequence",-1)==2 and m.get("target_floor",-1)==1 and m.get("target_cell",[])==[44,82]
		valid=valid and world.validate(suite.content).is_empty()
		protected_unchanged=protected_unchanged and world.facts.actors.protected_stationary==protected_initial
		for id: String in ["a_waiter","b_retreat"]:
			var actor: Dictionary=world.facts.actors[id]
			if actor.location.kind=="floor" and prior[id].location.kind=="floor" and actor.location.floor_id==prior[id].location.floor_id:
				bounded=bounded and ConvoyTrail.point(actor.location.cell).distance_to(ConvoyTrail.point(prior[id].location.cell))<=sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001
			if actor.location.kind!="floor":continue
			for other: Dictionary in world.facts.actors.values():
				if other.id==id or other.location.kind!="floor" or other.location.floor_id!=actor.location.floor_id:continue
				bodies_clear=bodies_clear and not sim.space.body_rectangle(actor).intersects(sim.space.body_rectangle(other),false)
		frames.append({"tick":world.sim_tick,"protected":world.facts.actors.protected_stationary.duplicate(true),"incoming":world.facts.actors.incoming.duplicate(true),"waiter":world.facts.actors.a_waiter.duplicate(true),"move":m.duplicate(true),"b_retreat":world.facts.actors.b_retreat.duplicate(true),"connection":world.facts.connectors[connection.id].duplicate(true)})

		if world.facts.connectors[connection.id].get("trip_sequence",-1)!=1 and world.facts.actors.incoming.location.kind=="floor" and int(world.facts.actors.incoming.location.floor_id)==2 and (plain or _sequential_contacts(observer.contacts)):break
	var contacts: Array=[] if plain else observer.contacts
	var chain_proved: bool=not plain and _sequential_contacts(contacts)
	var contact_file:=FileAccess.open(out+"/contacts.json",FileAccess.WRITE);contact_file.store_string(JSON.stringify({"plain":plain,"sequential_contacts":chain_proved,"contacts":contacts},"\t"));contact_file.close()
	_save(out+"/"+role+"-frames.bin",frames);_save(out+"/"+role+"-final.bin",world.freeze())
	protected_unchanged=protected_unchanged and world.facts.actors.protected_stationary==protected_initial
	var cleared: bool=world.facts.connectors[connection.id].get("trip_sequence",-1)!=1 and world.facts.actors.incoming.location.kind=="floor" and int(world.facts.actors.incoming.location.floor_id)==2
	var row: Dictionary={"passed":restore_exact and accepted and moved and stable and valid and bounded and bodies_clear and protected_unchanged and initial_geometry and cleared and (plain or chain_proved),"constructor_exact":restore_exact,"incoming_landed":cleared,"plain_mode":plain,"sequential_contacts":chain_proved,"initial_geometry":initial_geometry,"start_gap":start_gap,"end_gap":end_gap,"protected_unchanged":protected_unchanged,"scope":"plain qualification arm only" if plain else "self-asserting actual sequential contact and trip release","every_world_valid":valid,"step_budget":bounded,"bodies_clear":bodies_clear,"role":role,"floor":2,"actual_contact_handoff":accepted,"actual_movement":moved,"original_request_target":stable,"steps":frames.size(),"trip_cleared":world.facts.connectors[connection.id].get("trip_sequence",-1)!=1,"validation":error,"final_validation":world.validate(suite.content)}
	sim.dispose();return row
