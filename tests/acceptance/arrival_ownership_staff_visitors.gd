extends SceneTree

var content: HospitalContent
var suite: RefCounted
var rows: Array = []

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	content = HospitalContent.new()
	suite = load("res://tests/acceptance/public_area_use.gd").new()
	suite._content = content
	for variant: String in ["ordinary","blocked_entry","restored","no_chairs"]:
		_staff_rest(variant)
		_visitor(variant)
	_recreation(false)
	_recreation(true)
	for kind: String in ["staff","visitor"]:
		_unsafe_local_full(kind)
		for variant: String in ["foreign_same_target","foreign_invalid_area","detour","convoy","support_exit","failed_retarget","same_owned_waiting"]:
			_owner_boundary(kind,variant)
	for phase: String in ["returning","exiting"]: _staff_departure_owner(phase)
	for id: String in ["49","52","57","58","59"]:
		suite.call("_case_"+id,self)
	var phase_suite: RefCounted = load("res://tests/acceptance/public_phase_use.gd").new()
	phase_suite._content = content
	for id: String in ["70","71"]: phase_suite.call("_case_"+id,self)
	var passed: bool = rows.all(func(row: Dictionary)->bool: return row.passed)
	var result: Dictionary = {"passed":passed,"cases":rows,"scope":"Employee rest, two-person automatic/manual recreation, visitor seating, saved real ingress and task-owned ground handoffs. Actual 0.1-second movement and use; no long benchmark or full regression claim."}
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var file: FileAccess = FileAccess.open(args[0],FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"));file.close()
	print("ARRIVAL_OWNERSHIP ",passed," ",rows.size())
	quit(0 if passed else 1)

func check(id: String, passed: bool, details: Dictionary = {}) -> void:
	rows.append({"case":id,"passed":passed,"details":details})
	print(id," ",passed)

func _staff_step(x: Dictionary) -> void:
	x.w.dispatch(x.world)
	suite._life_ticks(x,1,true)
	x.world.touch(false)

func _blocker(x: Dictionary, actor_id: String, point: Dictionary) -> String:
	var actor: Dictionary = x.world.facts.actors[actor_id].duplicate(true)
	actor.id = "entry_blocker"
	actor.name = "entry_blocker"
	actor.location = {"kind":"floor","floor_id":point.floor_id,"cell":point.cell.duplicate(),"height_m":0.0}
	x.world.facts.actors[actor.id] = actor
	x.space.sync_actor(x.world,actor.id)
	x.world.touch(false)
	return actor.id

func _staff_rest(variant: String) -> void:
	var x: Dictionary = suite._areas({"resting":"doctor"})
	suite._position(x,"resting",[38,90])
	x.world.facts.staff.resting.energy = 35.0
	var area: Dictionary = x.space.public_areas.for_facility(x.world,"west_chair")
	var entry: Dictionary = x.space.public_areas.arrival_point(x.world,"resting",area)
	var blocker: String = _blocker(x,"resting",entry) if variant=="blocked_entry" else ""
	var same_entry: bool = entry==x.space.public_areas.arrival_point(x.world,"resting",area)
	x.w.dispatch(x.world)
	var task: Dictionary = x.world.facts.staff.resting.life_task
	var no_claim: bool = task.phase=="area_travel" and task.facility_id=="" and x.world.facts.staff_life.reservations.is_empty() and x.world.facts.moves.get("resting",{}).get("waiting_seat_id","")==task.id
	if variant=="no_chairs":
		for facility: Dictionary in x.world.facts.facilities.values(): facility.failed = true
		x.world.touch(false)
	var restored: bool = variant!="restored"
	var no_early_recovery: bool = true
	var no_early_wait: bool = true
	var reached: bool = false
	var release_ok: bool = blocker.is_empty()
	var first_inside: int = -1
	var first_local: int = -1
	for tick: int in 650:
		if tick==20 and variant=="restored":
			var frozen: Dictionary = x.world.freeze()
			x.a.dispose();x = suite._restore(x)
			task = x.world.facts.staff.resting.life_task
			restored = frozen==x.world.freeze() and x.world.facts.moves.get("resting",{}).get("waiting_seat_id","")==task.id
		if tick==80 and not blocker.is_empty(): release_ok = x.space.request_move(x.world,blocker,1,[41,72]).is_empty()
		var before_energy: float = float(x.world.facts.staff.resting.energy)
		var before_arrived: int = int(task.arrived_tick)
		x.w.dispatch(x.world)
		if int(task.arrived_tick)!=before_arrived: no_early_wait = no_early_wait and x.space.public_areas.contains(x.world,area,"resting") and x.space.public_areas.safe_wait(x.world,"resting",1,x.world.facts.actors.resting.location.cell) and not x.world.facts.moves.has("resting")
		suite._life_ticks(x,1,true);x.world.touch(false)
		var actor: Dictionary = x.world.facts.actors.resting
		var inside: bool = x.space.public_areas.contains(x.world,area,"resting")
		if inside and first_inside<0: first_inside = x.world.sim_tick
		if task.phase=="local_travel" and first_local<0: first_local = x.world.sim_tick
		if task.phase!="rest": no_early_recovery = no_early_recovery and float(x.world.facts.staff.resting.energy)<=before_energy
		if int(task.arrived_tick)==x.world.sim_tick: no_early_wait = no_early_wait and inside and x.space.public_areas.safe_wait(x.world,"resting",1,actor.location.cell)
		if task.phase=="rest":
			reached = inside and not x.world.facts.moves.has("resting") and (not task.get("tea",false) or x.space.public_areas.safe_wait(x.world,"resting",1,actor.location.cell))
			break
	var energy: float = float(x.world.facts.staff.resting.energy)
	if reached: suite._life_ticks(x,1)
	check("staff_rest_"+variant,same_entry and no_claim and restored and no_early_recovery and no_early_wait and reached and release_ok and float(x.world.facts.staff.resting.energy)>energy,{"busy_entry_keeps_area":same_entry,"owned_unreserved_departure":no_claim,"saved_owner_restored":restored,"no_travel_recovery":no_early_recovery,"wait_only_at_safe_arrival":no_early_wait,"real_rest":reached,"actual_recovery":float(x.world.facts.staff.resting.energy)>energy,"blocker_release":release_ok,"first_inside_tick":first_inside,"first_local_tick":first_local,"task":task.duplicate(true),"location":x.world.facts.actors.resting.location.duplicate(true)})
	x.a.dispose()

func _visitor(variant: String) -> void:
	var x: Dictionary = suite._areas()
	x.world.facts.entry = {"floor_id":1,"cell":[38,90],"exit_cell":[38,90]}
	var patient: Dictionary = suite._visit(x,"owner",[53,74])
	var admitted: bool = x.c.visitors._admit(x.world,patient,{"purpose":"companion","window":""})
	var stay: Dictionary = x.c.visitors._present(x.world,patient.id)
	if stay.is_empty(): check("visitor_"+variant,false,{"admitted":admitted});x.a.dispose();return
	var actor_id: String = str(stay.actor_id)
	var area: Dictionary = stay.public_use.area.duplicate(true)
	var entry: Dictionary = x.space.public_areas.arrival_point(x.world,actor_id,area)
	var blocker: String = _blocker(x,actor_id,entry) if variant=="blocked_entry" else ""
	var same_entry: bool = entry==x.space.public_areas.arrival_point(x.world,actor_id,area)
	x.c.visitors.dispatch(x.world)
	var no_claim: bool = stay.public_use.phase=="area_travel" and stay.public_use.facility_id=="" and x.world.facts.adaptations.is_empty() and x.world.facts.moves.get(actor_id,{}).get("waiting_seat_id","")==stay.public_use.id
	if variant=="no_chairs":
		for facility: Dictionary in x.world.facts.facilities.values(): facility.failed = true
		x.world.touch(false)
	var restored: bool = variant!="restored"
	var reached: bool = false
	var no_early_wait: bool = true
	var release_ok: bool = blocker.is_empty()
	for tick: int in 650:
		if tick==20 and variant=="restored":
			var frozen: Dictionary = x.world.freeze()
			x.a.dispose();x = suite._restore(x)
			stay = x.c.visitors._present(x.world,patient.id)
			restored = frozen==x.world.freeze() and x.world.facts.moves.get(actor_id,{}).get("waiting_seat_id","")==stay.public_use.id
		if tick==80 and not blocker.is_empty(): release_ok = x.space.request_move(x.world,blocker,1,[41,72]).is_empty()
		x.world.facts.sim_tick += 1
		x.c.visitors.dispatch(x.world)
		if int(stay.public_use.arrived_tick)==x.world.sim_tick: no_early_wait = no_early_wait and x.space.public_areas.contains(x.world,area,actor_id) and x.space.public_areas.safe_wait(x.world,actor_id,1,x.world.facts.actors[actor_id].location.cell)
		x.space.advance(x.world);x.world.touch(false)
		if variant=="no_chairs" and stay.public_use.phase=="local_wait" and not x.world.facts.moves.has(actor_id):
			reached = x.space.public_areas.contains(x.world,area,actor_id) and x.space.public_areas.safe_wait(x.world,actor_id,1,x.world.facts.actors[actor_id].location.cell) and stay.public_use.arrived_tick>=0
			if reached: break
		if stay.public_use.phase=="seated":
			reached = x.space.public_areas.contains(x.world,area,actor_id) and x.world.facts.actors[actor_id].get("support_facility_id","")==stay.public_use.facility_id and not x.world.facts.moves.has(actor_id)
			break
	check("visitor_"+variant,admitted and same_entry and no_claim and restored and no_early_wait and reached and release_ok,{"admitted":admitted,"busy_entry_keeps_area":same_entry,"owned_unreserved_departure":no_claim,"saved_owner_restored":restored,"wait_only_at_safe_arrival":no_early_wait,"real_seated_or_safe_standing":reached,"blocker_release":release_ok,"intent":stay.public_use.duplicate(true),"location":x.world.facts.actors[actor_id].location.duplicate(true)})
	x.a.dispose()

func _recreation(manual: bool) -> void:
	var x: Dictionary = suite._areas({"first":"doctor","second":"nurse"})
	suite._facility(x,"game","RC03",[36,71],"west");x.world.touch()
	for staff: Dictionary in x.world.facts.staff.values(): staff.energy = 60.0;staff.stress_milli = 50000;staff.on_shift = false
	var result: CommandResult = x.w.execute(x.world,"staff_recreation",{"staff_ids":["first","second"],"facility_id":"game" if manual else ""})
	var leader: Dictionary = x.world.facts.staff.first.life_task
	var no_claim: bool = result.accepted and x.world.facts.staff_life.reservations.is_empty() and x.world.facts.staff.first.recreation_count==0
	var restored: bool = false
	var before_all: bool = true
	var started: bool = false
	for tick: int in 700:
		if tick==20:
			var frozen: Dictionary = x.world.freeze();x.a.dispose();x = suite._restore(x)
			leader = x.world.facts.staff.first.life_task
			restored = frozen==x.world.freeze()
		x.w.dispatch(x.world)
		if leader.phase=="recreation": started = true;break
		before_all = before_all and x.world.facts.staff.first.recreation_count==0 and x.world.facts.staff.second.recreation_count==0 and x.world.facts.staff_life.reservations.is_empty()
		suite._life_ticks(x,1,true);x.world.touch(false)
	var duration: bool = false
	if started:
		var remaining: int = int(x.world.facts.staff_life.reservations.game.remaining_ticks)
		for tick: int in 299: suite._life_ticks(x,1)
		duration = remaining==300 and x.world.facts.staff_life.reservations.game.remaining_ticks==1 and leader.phase=="recreation"
		suite._life_ticks(x,1)
		duration = duration and leader.phase=="returning" and x.world.facts.staff.second.life_task.phase=="returning" and x.world.facts.staff.first.recreation_count==1 and x.world.facts.staff.second.recreation_count==1
	check("recreation_"+("manual" if manual else "auto"),no_claim and restored and before_all and started and duration,{"accepted":result.accepted,"unreserved_before_all_real_arrivals":no_claim and before_all,"saved_facts_unchanged":restored,"actual_group_start":started,"exact_300_tick_use":duration,"leader":leader.duplicate(true),"members":[x.world.facts.actors.first.location.duplicate(true),x.world.facts.actors.second.location.duplicate(true)]})
	x.a.dispose()

func _owner_boundary(kind: String, variant: String) -> void:
	# A declared legal in-area precondition followed by a real owned move. The
	# synthetic protected segment fields test only the dispatch read boundary.
	var x: Dictionary = suite._areas({"resting":"doctor"} if kind=="staff" else {})
	var actor_id: String = "resting"
	var stay: Dictionary = {}
	var task: Dictionary
	var area: Dictionary = x.space.public_areas.for_facility(x.world,"west_chair")
	if kind=="staff":
		suite._position(x,actor_id,[38,75]);x.world.facts.staff.resting.energy = 35.0
		x.w._begin(x.world,actor_id,"rest")
		task = x.world.facts.staff.resting.life_task
		if x.world.facts.moves.has(actor_id): x.space.cancel_ground_move(x.world,actor_id)
		task.phase = "area_travel";task.area = area;task.arrived_tick = -1;task.facility_id = "";task.erase("tea")
	else:
		x.world.facts.entry = {"floor_id":1,"cell":[38,75]}
		var patient: Dictionary = suite._visit(x,"owner",[53,74])
		x.c.visitors._admit(x.world,patient,{"purpose":"companion","window":""})
		stay = x.c.visitors._present(x.world,patient.id);actor_id = stay.actor_id;task = stay.public_use
	var request: String = x.space.request_move(x.world,actor_id,1,[41,75])
	var movement: Dictionary = x.world.facts.moves[actor_id]
	movement.waiting_seat_id = task.id
	if variant.begins_with("foreign"):
		x.space.request_move(x.world,actor_id,1,[41,75])
		if variant=="foreign_invalid_area": task.area = {}
	elif variant=="detour": movement.detour = {"reason":"protected_actual_detour"}
	elif variant=="convoy": movement.convoy = {"reason":"protected_group"}
	elif variant=="support_exit": movement.path = [{"kind":"support_exit","floor_id":1,"cell":[41,75]}];movement.cursor = 0
	if variant=="same_owned_waiting": movement.waiting_reason = "等待前人实际离开"
	var before: Dictionary = movement.duplicate(true)
	var before_task: Dictionary = task.duplicate(true)
	var request_result: bool = false
	if variant in ["failed_retarget","same_owned_waiting"]:
		var target: Array = [0,0] if variant=="failed_retarget" else [41,75]
		request_result = x.w._request_public_target(x.world,actor_id,task,1,target,true) if kind=="staff" else x.c.visitors._request_public_move(x.world,stay,1,target)
	else:
		if kind=="staff": x.w._dispatch_public_rest(x.world,actor_id)
		else: x.c.visitors._public_waiting(x.world,stay)
	var expected_request: bool = request_result if variant=="same_owned_waiting" else not request_result
	check(kind+"_"+variant,request.is_empty() and expected_request and x.world.facts.moves.get(actor_id,{})==before and task==before_task,{"request_result":request_result,"move_untouched":x.world.facts.moves.get(actor_id,{})==before,"intent_untouched":task==before_task})
	x.a.dispose()

func _unsafe_local_full(kind: String) -> void:
	var x: Dictionary = suite._areas({"resting":"doctor"} if kind=="staff" else {})
	var actor_id: String = "resting"
	var stay: Dictionary = {}
	var task: Dictionary
	if kind=="staff":
		suite._position(x,actor_id,[38,90]);x.world.facts.staff.resting.energy = 35.0
		x.w.dispatch(x.world);task = x.world.facts.staff.resting.life_task
	else:
		x.world.facts.entry = {"floor_id":1,"cell":[38,90]}
		var patient: Dictionary = suite._visit(x,"owner",[53,74])
		x.c.visitors._admit(x.world,patient,{"purpose":"companion","window":""})
		stay = x.c.visitors._present(x.world,patient.id);actor_id = stay.actor_id;task = stay.public_use
		x.c.visitors.dispatch(x.world)
	var area: Dictionary = task.area.duplicate(true)
	var entered: bool = false
	for tick: int in 180:
		x.world.facts.sim_tick += 1;x.space.advance(x.world);x.world.touch(false)
		if x.space.public_areas.contains(x.world,area,actor_id): entered = true;break
	var unsafe: bool = not x.space.public_areas.safe_wait(x.world,actor_id,1,x.world.facts.actors[actor_id].location.cell)
	# Declare lawful standing bodies at this arrival boundary. Each inserted
	# body occupies a currently safe, dynamically clear cell. This is not a
	# claim to execute their earlier journeys or to displace the tested actor.
	var crowd: int = 0
	for index: int in x.space.public_areas.region(x.world,area).cells.size():
		var point: Dictionary = x.space.public_areas.waiting_point(x.world,actor_id,area)
		if point.is_empty(): break
		var actor: Dictionary = x.world.facts.actors[actor_id].duplicate(true)
		actor.id = "crowd_"+str(index);actor.name = actor.id
		actor.location = {"kind":"floor","floor_id":point.floor_id,"cell":point.cell.duplicate(),"height_m":0.0}
		x.world.facts.actors[actor.id] = actor;x.space.sync_actor(x.world,actor.id);x.world.touch(false)
		crowd += 1
	for facility: Dictionary in x.world.facts.facilities.values(): facility.failed = true
	x.world.touch(false)
	var no_local: bool = x.space.public_areas.waiting_point(x.world,actor_id,area).is_empty()
	var before_move: Dictionary = x.world.facts.moves.get(actor_id,{}).duplicate(true)
	var searches: int = int(x.space.query_counts.get("public_select_regions_visited",0))
	if kind=="staff": x.w._dispatch_public_rest(x.world,actor_id)
	else: x.c.visitors._public_waiting(x.world,stay)
	var retained: bool = not before_move.is_empty() and x.world.facts.moves.get(actor_id,{})==before_move and task.area==area and task.phase=="area_travel" and int(task.arrived_tick)<0
	var no_global_reselection: bool = searches==int(x.space.query_counts.get("public_select_regions_visited",0))
	# Release the first lawful neighbour at this declared occupancy boundary,
	# then execute the tested actor's recovery rather than teleporting it.
	var released: bool = x.world.facts.actors.has("crowd_0")
	if released:
		x.world.facts.actors.crowd_0.location = {"kind":"outside"}
		x.space.sync_actor(x.world,"crowd_0");x.world.facts.actors.erase("crowd_0");x.world.touch(false)
	var recovered: bool = false
	var release_steps: int = 0
	for tick: int in 300:
		x.world.facts.sim_tick += 1
		if kind=="staff": x.w._dispatch_public_rest(x.world,actor_id)
		else: x.c.visitors._public_waiting(x.world,stay)
		if not x.world.facts.moves.has(actor_id) and x.space.public_areas.safe_wait(x.world,actor_id,1,x.world.facts.actors[actor_id].location.cell):
			recovered = task.area==area;break
		x.space.advance(x.world);x.world.touch(false);release_steps += 1
	check(kind+"_unsafe_full_local",entered and unsafe and crowd>0 and no_local and retained and no_global_reselection and released and recovered,{"real_entry_reached":entered,"unsafe_doorway":unsafe,"declared_safe_standing_bodies":crowd,"no_safe_candidate":no_local,"original_owned_ingress_retained":retained,"no_global_reselection":no_global_reselection,"one_neighbour_released":released,"actual_safe_recovery":recovered,"release_motion_steps":release_steps,"task":task.duplicate(true),"position":x.world.facts.actors[actor_id].location.duplicate(true)})
	x.a.dispose()

func _staff_departure_owner(phase: String) -> void:
	var x: Dictionary = suite._areas({"resting":"doctor"})
	suite._position(x,"resting",[38,75]);x.world.facts.staff.resting.energy = 35.0
	x.w._begin(x.world,"resting","rest")
	if x.world.facts.moves.has("resting"): x.space.cancel_ground_move(x.world,"resting")
	var task: Dictionary = x.world.facts.staff.resting.life_task
	task.phase = phase;task.facility_id = "";task.floor_id = 1;task.cell = [38,75]
	# Another task may own an identical coordinate. Finishing rest must not
	# cancel that task or publish the body outside on its behalf.
	var request: String = x.space.request_move(x.world,"resting",1,[38,75])
	var before_move: Dictionary = x.world.facts.moves.get("resting",{}).duplicate(true)
	var before_actor: Dictionary = x.world.facts.actors.resting.duplicate(true)
	x.w._dispatch_task(x.world,"resting")
	check("staff_"+phase+"_foreign_at_target",request.is_empty() and not before_move.is_empty() and before_move==x.world.facts.moves.get("resting",{}) and before_actor==x.world.facts.actors.resting and x.world.facts.staff.resting.life_task.phase==phase,{"foreign_move_kept":before_move==x.world.facts.moves.get("resting",{}),"body_kept":before_actor==x.world.facts.actors.resting,"phase":x.world.facts.staff.resting.life_task.phase})
	x.a.dispose()
