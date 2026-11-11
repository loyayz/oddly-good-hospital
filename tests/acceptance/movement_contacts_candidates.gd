extends RefCounted

const Oracle=preload("res://tests/acceptance/movement_contacts_oracle.gd")
const CASES: Array[String]=["current_only","accepted_only","both_duplicate_distinct","empty_with_reservation","order_first_contact","compound_gap","strict_edge"]
var content: HospitalContent

func run(database: HospitalContent, selected: Array) -> Dictionary:
	content=database
	var rows: Array=[]
	for name: String in selected:
		if not name in CASES: return {"ok":false,"error":"Unknown contact candidate selector: "+name}
		var started: int=Time.get_ticks_usec()
		var row: Dictionary=_case(name)
		row.id=name;row.elapsed_us=Time.get_ticks_usec()-started;rows.append(row)
	return {"ok":not rows.is_empty() and rows.all(func(row: Dictionary)->bool:return row.ok),"rows":rows,"scope":"Complete collision calculations from lawful current-body, one accepted 0.2-cell sweep, reservation and turning-convoy boundaries. No journey or elapsed gameplay is fabricated. Oracle enumerates all facts/sweeps and independently applies exact geometry, permissions and sorted identities."}

func _sweep(id: String, from: Rect2, to: Rect2) -> BodyIndex.Record:
	var result:=BodyIndex.Record.new()
	result.id=id;result.sweep_from=from;result.sweep_to=to
	return result

func _accepted(sim: HospitalSimulation, id: String, from_cell: Vector2) -> void:
	var actor: Dictionary=sim.world.facts.actors[id]
	var from: Rect2=sim.space._actor_rect(actor,from_cell)
	var delta: Vector2=ConvoyTrail.point(actor.location.cell)-from_cell
	assert(delta.length()<=sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.00001)
	actor.facing=atan2(delta.x,delta.y)
	sim.world.touch(false);sim.space.sync_actor(sim.world,id)
	var sweep: BodyIndex.Record=_sweep(id,from,sim.space.body_rectangle(actor))
	sweep.floor_id=int(actor.location.floor_id)
	sim.space.movement._accepted_sweeps[id]=sweep
	sim.space.movement._sweep_index.update(id,sweep.floor_id,sweep.sweep_from.merge(sweep.sweep_to))

func _case(name: String) -> Dictionary:
	var suite: RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
	var sim: HospitalSimulation=suite._fixture()
	suite._add_actor(sim,"walker","S49",[35,70])
	var walker: Dictionary=sim.world.facts.actors.walker
	var paths: Array=[]
	var checks: Dictionary={}
	if name=="empty_with_reservation":
		checks.real_facility=suite._command(sim,"build_facility",{"id":"reserved_machine","definition_id":"M37","floor_id":1,"cell":[44,76]}).accepted
		suite._add_actor(sim,"owner","S49",[52,85])
		checks.real_reservation=sim.space.reserve_facility(sim.world,"reserved_machine","owner","owner").is_empty()
		var raw: Array=sim.world.facts.adaptations.get("reserved_machine",{}).get("regions",[[0,0,0,0]])[0]
		var box:=Rect2(float(raw[0]),float(raw[1]),float(raw[2]),float(raw[3]))
		paths.append([box,box])
	elif name=="compound_gap":
		var members: Array=["group","middle","tail"]
		for pair: Array in [["group",[42,74]],["middle",[40,74]],["tail",[40,72]]]: suite._add_actor(sim,pair[0],"S49",pair[1])
		var form: Dictionary=ConvoyTrail.formation(sim.space,sim.world,"group",members)
		var convoy: Dictionary={"version":1,"points":[[40,72],[40,74],[42,74]],"spacing":form.spacing,"size":form.size,"centers":form.centers,"floor_id":1,"shift":form.shift,"height":form.height}
		var move: Dictionary={"actor_id":"group","members":members,"convoy":convoy,"path":[{"kind":"floor","floor_id":1,"cell":[46,74]}],"cursor":0,"travelled":[{"kind":"floor","floor_id":1,"cell":[42,74]}],"blocked_since":-1,"target_floor":1,"target_cell":[46,74],"request_sequence":1}
		sim.world.facts.move_request_next=1;sim.world.facts.moves["group"]=move
		var poses: Dictionary=ConvoyTrail.positions(convoy,members)
		for id: String in members:
			var pose: Dictionary=poses[id]
			sim.world.facts.actors[id].location.cell=pose.cell.duplicate();sim.world.facts.actors[id].facing=pose.facing
		sim.world.touch();sim.space._ensure_actor_index(sim.world)
		for point: Vector2 in [Vector2(41.2,72.2),Vector2(40.2,72.2),Vector2(41.2,74.2)]:
			var box: Rect2=sim.space._actor_rect(walker,point);paths.append([box,box])
	else:
		suite._add_actor(sim,"alpha","S49",[40.2,74] if name in ["accepted_only","both_duplicate_distinct","order_first_contact"] else [40,74])
		if name in ["both_duplicate_distinct","order_first_contact"]: suite._add_actor(sim,"beta","S49",[40.2,75.2])
		sim.space._ensure_actor_index(sim.world)
		if name in ["accepted_only","both_duplicate_distinct","order_first_contact"]: _accepted(sim,"alpha",Vector2(40,74))
		if name=="accepted_only":
			var box: Rect2=sim.space._actor_rect(walker,Vector2(39.7,74));paths.append([box,box])
		elif name in ["both_duplicate_distinct","order_first_contact"]:
			paths.append([sim.space._actor_rect(walker,Vector2(40.2,72.8)),sim.space._actor_rect(walker,Vector2(40.2,75.8))])
		elif name=="strict_edge":
			var body: Rect2=sim.space.body_rectangle(sim.world.facts.actors.alpha)
			var edge:=Rect2(Vector2(body.end.x,body.position.y),body.size)
			var overlap:=Rect2(edge.position-Vector2(0.0001,0),edge.size)
			paths.append([overlap,overlap]);paths.append([edge,edge])
		else:
			var box: Rect2=sim.space.body_rectangle(sim.world.facts.actors.alpha);paths.append([box,box])
	checks.legal_world=sim.world.validate(content).is_empty()
	var before: Dictionary=sim.world.freeze()
	var snapshot: Dictionary=Oracle.capture(sim.world,sim.space,sim.space.movement._accepted_sweeps)
	var observations: Array=[]
	var cache: Dictionary={"regions":{}}
	for pair: Array in paths:
		var sweep: BodyIndex.Record=_sweep("walker",pair[0],pair[1])
		var probes: Array[BodyIndex.Record]=[sweep]
		var broad: Rect2=pair[0].merge(pair[1])
		var expected: Dictionary=Oracle.query(snapshot,"walker",1,broad,probes,["walker"])
		var row: Dictionary={"expected":expected,"modes":[]}
		for mode: String in ["full","first","cached_full","cached_first"]:
			var result:=HospitalMovement.MotionResult.new();result.first_contact_only=mode.ends_with("first")
			var counts: int=int(sim.space.query_counts.movement_candidates)
			sim.space.movement._movement_contacts(sim.world,"walker",1,broad,probes,["walker"],result,cache if mode.begins_with("cached") else {})
			var oracle: Dictionary=Oracle.query(snapshot,"walker",1,broad,probes,["walker"],result.first_contact_only)
			var actual: Dictionary=Oracle.typed(result)
			var exact: bool=var_to_bytes(actual)==var_to_bytes(Oracle.expected_typed(oracle,result.first_contact_only))
			var candidate_count: int=int(sim.space.query_counts.movement_candidates)-counts
			row.modes.append({"mode":mode,"typed_outputs_equal":exact,"candidate_count":candidate_count,"expected_candidate_count":expected.candidate_ids.size(),"actors":Array(result.blocker_actor_ids),"reservations":Array(result.reservation_ids)})
			checks["complete_typed_result_"+str(observations.size())+"_"+mode]=exact
			checks["complete_candidates_"+str(observations.size())+"_"+mode]=candidate_count==expected.candidate_ids.size()
		observations.append(row)
	var first: Dictionary=observations[0].expected
	match name:
		"current_only": checks.target_branch=first.current_candidates==["alpha"] and first.accepted_candidates.is_empty() and first.actors==["alpha"]
		"accepted_only": checks.target_branch=first.current_candidates.is_empty() and first.accepted_candidates==["alpha"] and first.actors==["alpha"]
		"both_duplicate_distinct","order_first_contact": checks.target_branch=first.current_candidates==["alpha","beta"] and first.accepted_candidates==["alpha"] and first.candidate_ids==["alpha","beta"] and first.actors==["alpha","beta"]
		"empty_with_reservation": checks.target_branch=first.candidate_ids.is_empty() and first.reservations==["reserved_machine"]
		"compound_gap": checks.target_branch=first.actors.is_empty() and observations[1].expected.actors==["group"] and observations[2].expected.actors==["group"]
		"strict_edge": checks.target_branch=first.actors==["alpha"] and observations[1].expected.actors.is_empty()
	checks.full_world_readonly=before==sim.world.freeze()
	var result: Dictionary={"ok":checks.values().all(func(value: Variant)->bool:return value==true),"checks":checks,"observations":observations,"world_validation":sim.world.validate(content)}
	sim.dispose();return result
