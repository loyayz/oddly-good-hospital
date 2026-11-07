extends SceneTree

# Only legal boundary inputs are declared here. Every tested walk, encounter,
# ticket acquisition, boarding and arrival uses the real 0.1-second stage.
const OPTIONAL_FIELDS: Array[String] = ["waiting_seat_id","waiting_need_id","waiting_safety_visit","floor_guidance_key","guidance_nurse_desk","floor_only"]
const CASES: Array[String] = ["single","group","single_restore","group_restore","distinct","floor_invalid","detour","transit","optional","malformed"]
var suite = preload("res://tests/acceptance/space.gd").new()
var trace: Array = []
var errors: Array = []

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size()!=2:
		push_error("Expected output JSON path and comma-separated case selectors: "+",".join(CASES))
		quit(2);return
	var selected: PackedStringArray = args[1].split(",")
	var seen: Dictionary = {}
	for name: String in selected:
		if not name in CASES or seen.has(name):
			push_error("Unknown or duplicate movement-target-reuse selector: "+name)
			quit(2);return
		seen[name] = true
	suite.content = HospitalContent.new()
	var rows: Array = []
	for name: String in selected:
		var row: Dictionary
		match name:
			"single": row = _numeric(false,false)
			"group": row = _numeric(true,false)
			"single_restore": row = _numeric(false,true)
			"group_restore": row = _numeric(true,true)
			"distinct": row = _distinct()
			"floor_invalid": row = _floor_invalid()
			"detour": row = _detour()
			"transit": row = _transit()
			"optional": row = _optional()
			"malformed": row = _malformed()
		rows.append(row)
		print(JSON.stringify(row))
	var result: Dictionary = {"ok":not rows.is_empty() and errors.is_empty() and rows.all(func(row: Dictionary)->bool:return row.ok),"rows":rows,"errors":errors,"fixed_tick_seconds":WorldState.TICK_SECONDS,"scope":"Selected exact numeric-target reuse and affected handoffs; declared legal starting inputs, real movement and fresh frozen-world runtime restore; no performance or full-suite claim."}
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	FileAccess.open(args[0]+".trace.json",FileAccess.WRITE).store_string(JSON.stringify(trace,"  "))
	quit(0 if result.ok else 1)

func _fixture(group: bool, transit: bool = false) -> HospitalSimulation:
	var sim: HospitalSimulation = suite._transit_fixture() if transit else suite._fixture()
	# Declared already-assembled legal starting queue; formation is not tested.
	suite._add_actor(sim,"leader","S49",[54,80])
	if group: suite._add_actor(sim,"follower","S49",[52,80])
	return sim

func _request(sim: HospitalSimulation, group: bool, floor_id: int, target: Array) -> String:
	return sim.space.request_group_move(sim.world,"leader",["leader","follower"],{},floor_id,target) if group else sim.space.request_move(sim.world,"leader",floor_id,target)

func _tick(label: String, sim: HospitalSimulation) -> void:
	var before: Dictionary = sim.world.facts.actors.duplicate(true)
	suite._movement_tick(sim)
	var validation: String = sim.world.validate(suite.content)
	if not validation.is_empty(): errors.append({"case":label,"tick":sim.world.sim_tick,"validation":validation})
	var positions: Dictionary = {}
	for id: String in sim.world.facts.actors:
		var actor: Dictionary = sim.world.facts.actors[id]
		positions[id] = actor.location.duplicate(true)
		if actor.location.kind!="floor" or before[id].location.kind!="floor" or actor.location.floor_id!=before[id].location.floor_id: continue
		var distance: float = ConvoyTrail.point(before[id].location.cell).distance_to(ConvoyTrail.point(actor.location.cell))
		if distance>sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001:
			errors.append({"case":label,"tick":sim.world.sim_tick,"actor":id,"distance_exceeds_real_step":distance})
	trace.append({"case":label,"tick":sim.world.sim_tick,"positions":positions})

func _finish(label: String, sim: HospitalSimulation, limit: int = 350) -> int:
	var count: int = 0
	while not sim.world.facts.moves.is_empty() and count<limit:
		_tick(label,sim);count+=1
	return count

func _repeat(sim: HospitalSimulation, group: bool, target: Array) -> Dictionary:
	var before: Dictionary = sim.world.freeze()
	var old_move: Dictionary = sim.world.facts.moves.leader.duplicate(true)
	var reason: String = _request(sim,group,int(old_move.target_floor),target)
	var current: Dictionary = sim.world.facts.moves.leader.duplicate(true)
	return {"ok":reason.is_empty() and before==sim.world.freeze(),"reason":reason,"entire_world_unchanged":before==sim.world.freeze(),"sequence_preserved":old_move.request_sequence==current.request_sequence,"entire_journey_preserved":old_move==current,"before":old_move,"after":current,"requested_target":target}

func _numeric(group: bool, restore: bool) -> Dictionary:
	var sim: HospitalSimulation = _fixture(group)
	var c: Dictionary = {"legal_input":sim.world.validate(suite.content).is_empty(),"request":_request(sim,group,1,[60,80]).is_empty()}
	for step: int in 5: _tick("numeric_initial",sim)
	c.real_departure = sim.world.facts.actors.leader.location.cell!=[54,80] and sim.world.facts.moves.has("leader") and not sim.world.facts.moves.leader.get("route_pending",true)
	if restore:
		var frozen: Dictionary = sim.world.freeze()
		var old_space_id: int = sim.space.get_instance_id()
		sim.dispose()
		sim = HospitalSimulation.new(WorldState.new(frozen),suite.content)
		c.fresh_runtime = sim.space.get_instance_id()!=old_space_id and sim.world.freeze()==frozen and sim.world.validate(suite.content).is_empty()
	var repeats: Array = []
	for target: Array in [[60.0,80.0],[60,80.0],[60.0,80],[60,80]]:
		repeats.append(_repeat(sim,group,target))
	c.exact_repeats_reuse_entire_journey = repeats.all(func(row: Dictionary)->bool:return row.ok)
	if group: c.membership_preserved = sim.space.movement._member_owner(sim.world,"follower")=="leader"
	var steps: int = _finish("numeric_finish",sim)
	c.actual_arrival = sim.world.facts.moves.is_empty() and sim.space.at(sim.world,"leader",1,[60,80])
	if group: c.complete_group_released = sim.world.facts.actors.follower.location.kind=="floor" and sim.space.movement._member_owner(sim.world,"follower").is_empty()
	var row: Dictionary = {"case":"group" if group else "single","restored":restore,"ok":not c.values().has(false),"checks":c,"repeats":repeats,"real_steps":5+steps}
	sim.dispose();return row

func _distinct() -> Dictionary:
	var rows: Array = []
	for group: bool in [false,true]:
		var sim: HospitalSimulation = _fixture(group)
		var c: Dictionary = {"request":_request(sim,group,1,[60.0,80.0]).is_empty()}
		for step: int in 5: _tick("distinct_initial",sim)
		var observations: Array = []
		# Both changes survive float64 but disappear in a float32 Vector2.
		for target: Array in [[60.00000001,80.0],[60.00000001,80.00000001]]:
			var before: Dictionary = sim.world.facts.moves.leader.duplicate(true)
			var actors: Dictionary = sim.world.facts.actors.duplicate(true)
			var accepted: String = _request(sim,group,1,target)
			var after: Dictionary = sim.world.facts.moves.leader.duplicate(true)
			var pending: bool = bool(before.get("route_pending",false))
			var changed: bool = accepted.is_empty() and after.target_cell==target and before.target_cell!=target and after.get("route_pending",false) and actors==sim.world.facts.actors
			# An already pending request retains FIFO priority by existing contract.
			changed = changed and (after.request_sequence==before.request_sequence if pending else after.request_sequence>before.request_sequence)
			observations.append({"ok":changed,"float32_points_equal":ConvoyTrail.point(before.target_cell)==ConvoyTrail.point(target),"reason":accepted,"before":before,"after":after})
			_tick("distinct_retarget",sim)
		c.distinct_targets_not_merged = observations.all(func(row: Dictionary)->bool:return row.ok and row.float32_points_equal)
		var final_goal: Array = sim.world.facts.moves.leader.target_cell.duplicate()
		var steps: int = _finish("distinct_finish",sim)
		c.actual_arrival_under_existing_position_contract = sim.world.facts.moves.is_empty() and sim.space.at(sim.world,"leader",1,final_goal)
		rows.append({"group":group,"ok":not c.values().has(false),"checks":c,"observations":observations,"remaining_steps":steps})
		sim.dispose()
	return {"case":"distinct_float64_targets","ok":rows.all(func(row: Dictionary)->bool:return row.ok),"rows":rows}

func _malformed() -> Dictionary:
	var sim: HospitalSimulation = _fixture(true)
	var c: Dictionary = {"legal_input":sim.world.validate(suite.content).is_empty(),"request":_request(sim,true,1,[60,80]).is_empty()}
	for step: int in 5: _tick("malformed_initial",sim)
	c.real_departure = sim.world.facts.actors.leader.location.cell!=[54,80] and sim.world.facts.moves.has("leader") and not sim.world.facts.moves.leader.get("route_pending",true)
	var rows: Array = []
	var invalid: Dictionary = {
		"extra":[60,80,99],"short":[60],"empty":[],
		"string_x":["60",80],"string_y":[60,"80"],
		"bool_x":[true,80],"bool_y":[60,true],
		"null_x":[null,80],"null_y":[60,null],
		"infinite_x":[INF,80],"infinite_y":[60,INF],
		"nan_x":[NAN,80],"nan_y":[60,NAN]
	}
	for name: String in invalid:
		var target: Array = invalid[name]
		var before: Dictionary = sim.world.freeze()
		var expected: String = sim.space.movement._convoy_goal_reason(sim.world,sim.world.facts.moves.leader,1,target)
		var reason: String = _request(sim,true,1,target)
		rows.append({"case":name,"ok":not expected.is_empty() and reason==expected and before==sim.world.freeze(),"input":var_to_str(target),"existing_validator":expected,"reason":reason,"entire_world_unchanged":before==sim.world.freeze()})
	c.malformed_rejected_atomically = rows.all(func(row: Dictionary)->bool:return row.ok)
	var steps: int = _finish("malformed_unchanged_journey",sim)
	c.actual_original_arrival = sim.world.facts.moves.is_empty() and sim.space.at(sim.world,"leader",1,[60,80]) and sim.space.movement._member_owner(sim.world,"follower").is_empty()
	var result: Dictionary = {"case":"malformed_convoy_target_atomicity","ok":not c.values().has(false),"checks":c,"rows":rows,"real_steps":5+steps}
	sim.dispose();return result

func _floor_invalid() -> Dictionary:
	var rows: Array = []
	for group: bool in [false,true]:
		var sim: HospitalSimulation = _fixture(group,true)
		var c: Dictionary = {"legal_input":sim.world.validate(suite.content).is_empty(),"request":_request(sim,group,1,[60,80]).is_empty()}
		for step: int in 5: _tick("floor_initial",sim)
		var invalid: Array = []
		for request: Array in [[1,[-4,-4]],[3,[60,80]]]:
			var frozen: Dictionary = sim.world.freeze()
			var reason: String = _request(sim,group,int(request[0]),request[1])
			invalid.append({"ok":not reason.is_empty() and frozen==sim.world.freeze(),"reason":reason,"floor":request[0],"target":request[1]})
		c.rejected_target_atomic = invalid.all(func(row: Dictionary)->bool:return row.ok)
		var old: Dictionary = sim.world.facts.moves.leader.duplicate(true)
		var actors: Dictionary = sim.world.facts.actors.duplicate(true)
		var accepted: String = _request(sim,group,2,[60.0,80.0])
		var next: Dictionary = sim.world.facts.moves.leader.duplicate(true)
		c.same_xy_different_floor_retargets = accepted.is_empty() and next.target_floor==2 and next.request_sequence>old.request_sequence and next.get("route_pending",false) and actors==sim.world.facts.actors
		var steps: int = _finish("floor_real_crossing",sim,1200)
		c.actual_new_floor_arrival = sim.world.facts.moves.is_empty() and sim.space.at(sim.world,"leader",2,[60,80])
		rows.append({"group":group,"ok":not c.values().has(false),"checks":c,"invalid":invalid,"change_reason":accepted,"before":old,"after":next,"remaining_steps":steps})
		sim.dispose()
	return {"case":"floor_identity_and_invalid_atomicity","ok":rows.all(func(row: Dictionary)->bool:return row.ok),"rows":rows}

func _detour() -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"leader","S49",[34,88])
	suite._add_actor(sim,"other","S49",[34,92])
	var c: Dictionary = {"legal_input":sim.world.validate(suite.content).is_empty(),"requests":sim.space.request_move(sim.world,"leader",1,[34,94]).is_empty() and sim.space.request_move(sim.world,"other",1,[34,66]).is_empty()}
	var repeats: Array = []
	var steps: int = 0
	var seen: Dictionary = {}
	while not sim.world.facts.moves.is_empty() and steps<350:
		_tick("detour_real_encounter",sim);steps+=1
		for id: String in ["leader","other"]:
			var move: Dictionary = sim.world.facts.moves.get(id,{})
			if not move.has("detour"): continue
			var key: String = id+":"+str(move.detour.phase)
			if seen.has(key): continue
			seen[key] = true
			var before: Dictionary = sim.world.freeze()
			var original: Dictionary = move.duplicate(true)
			var reason: String = sim.space.request_move(sim.world,id,1,[float(move.target_cell[0]),float(move.target_cell[1])])
			repeats.append({"ok":reason.is_empty() and before==sim.world.freeze(),"actor":id,"phase":key,"reason":reason,"before":original,"after":move.duplicate(true)})
	c.actual_detour_and_repeats_preserved = not repeats.is_empty() and repeats.all(func(row: Dictionary)->bool:return row.ok)
	c.both_actual_arrivals = sim.world.facts.moves.is_empty() and sim.space.at(sim.world,"leader",1,[34,94]) and sim.space.at(sim.world,"other",1,[34,66])
	c.no_repeat_global_search = int(sim.space.query_counts.get("route_dispatches",0))==2
	var row: Dictionary = {"case":"repeat_during_real_detour","ok":not c.values().has(false),"checks":c,"repeats":repeats,"steps":steps}
	sim.dispose();return row

func _transit() -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	suite._add_actor(sim,"earlier","S49",[36,76])
	var c: Dictionary = {"earlier_request":sim.space.request_move(sim.world,"earlier",2,[52,84]).is_empty()}
	var steps: int = 0
	while sim.world.facts.actors.earlier.location.kind!="transit" and steps<100:
		_tick("transit_earlier_real_boarding",sim);steps+=1
	c.earlier_actually_boarded = sim.world.facts.actors.earlier.location.kind=="transit"
	# Legal newly-present queue boundary, before its own request or movement.
	suite._add_actor(sim,"leader","S49",[36,77])
	suite._add_actor(sim,"follower","S49",[36,79])
	c.group_input_valid = sim.world.validate(suite.content).is_empty()
	c.group_request = _request(sim,true,2,[46,84]).is_empty()
	var repeats: Array = []
	var phases: Dictionary = {}
	while sim.world.facts.moves.has("leader") and steps<1400:
		var move: Dictionary = sim.world.facts.moves.leader
		var actor: Dictionary = sim.world.facts.actors.leader
		var phase: String = "riding" if actor.location.kind=="transit" else "waiting" if move.has("transit_ticket") else ""
		if not phase.is_empty() and not phases.has(phase):
			phases[phase] = true
			var row: Dictionary = _repeat(sim,true,[46.0,84.0])
			row.phase = phase
			repeats.append(row)
		_tick("transit_real_group_journey",sim);steps+=1
	c.real_waiting_and_riding_repeats = phases.has("waiting") and phases.has("riding") and repeats.all(func(row: Dictionary)->bool:return row.ok)
	c.real_group_arrival = not sim.world.facts.moves.has("leader") and sim.space.at(sim.world,"leader",2,[46,84]) and sim.world.facts.actors.follower.location.kind=="floor" and int(sim.world.facts.actors.follower.location.floor_id)==2
	var result: Dictionary = {"case":"repeat_preserves_real_transit_ticket","ok":not c.values().has(false),"checks":c,"repeats":repeats,"steps":steps}
	sim.dispose();return result

func _numeric_other_representation(target: Array) -> Array:
	var result: Array = []
	for number: Variant in target:
		result.append(float(number) if number is int else int(number) if float(number)==floor(float(number)) else number)
	return result

func _optional_repeat(world: WorldState, space: HospitalSpace, actor_id: String) -> Dictionary:
	var original: Dictionary = world.facts.moves.get(actor_id,{}).duplicate(true)
	if original.is_empty(): return {"ok":false,"reason":"Owner did not create a journey"}
	var before: Dictionary = world.freeze()
	var target: Array = _numeric_other_representation(original.target_cell)
	var expected: Dictionary = original.duplicate(true)
	var cleared: Array = []
	for field: String in OPTIONAL_FIELDS:
		if expected.has(field): cleared.append(field)
		expected.erase(field)
	var reason: String = space.request_move(world,actor_id,int(original.target_floor),target)
	var actual: Dictionary = world.facts.moves[actor_id].duplicate(true)
	before.moves[actor_id] = expected
	return {"ok":not cleared.is_empty() and original.target_cell!=target and reason.is_empty() and before==world.freeze(),"reason":reason,"cleared_fields":cleared,"only_ownership_changed":before==world.freeze(),"before":original,"after":actual,"requested_target":target}

func _optional() -> Dictionary:
	var waiting = preload("res://tests/acceptance/waiting_adoption.gd").new()
	waiting._content = suite.content
	var x: Dictionary = waiting._areas()
	var visit: Dictionary = waiting._visit(x,"target_reuse",[38,90])
	# Named legal scheduling input; this is ownership handoff, not seat arrival.
	x.world.facts.sim_tick = 50
	x.l.dispatch(x.world)
	var seat: Dictionary = _optional_repeat(x.world,x.space,visit.actor_id)
	var external: Dictionary = x.world.facts.moves.get(visit.actor_id,{}).duplicate(true)
	seat.old_owner_cannot_cancel = not x.l.call_patient(x.world,visit.id) and external==x.world.facts.moves.get(visit.actor_id,{})
	seat.validation = x.world.validate(suite.content)
	seat.ok = seat.ok and seat.old_owner_cannot_cancel and seat.validation.is_empty()
	x.c.departments = null
	x.p.clinic = null
	var guidance = preload("res://tests/acceptance/floor_guidance.gd").new()
	guidance._content = suite.content
	x = guidance._base()
	x.g.dispatch(x.world)
	var nurse: Dictionary = _optional_repeat(x.world,x.space,"guide_nurse")
	external = x.world.facts.moves.get("guide_nurse",{}).duplicate(true)
	x.world.facts.staff.guide_nurse.on_shift = false
	x.g.dispatch(x.world);x.g.dispatch(x.world)
	nurse.old_owner_cannot_cancel = external==x.world.facts.moves.get("guide_nurse",{})
	nurse.validation = x.world.validate(suite.content)
	nurse.ok = nurse.ok and nurse.old_owner_cannot_cancel and nurse.validation.is_empty()
	guidance._dispose(x)
	return {"case":"numeric_same_goal_optional_ownership_transfer","ok":seat.ok and nurse.ok,"seat":seat,"nurse":nurse}
