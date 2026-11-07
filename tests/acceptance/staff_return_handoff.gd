extends "res://tests/acceptance/staff_fixtures.gd"

func _tick(x: Dictionary) -> void:
	x.s.boundaries(x.world)
	x.d.dispatch(x.world)
	x.w.dispatch(x.world)
	var previous: Dictionary = {}
	for id: String in x.world.ids("staff"): previous[id] = x.world.facts.actors[id].location.duplicate(true)
	x.space.advance(x.world)
	x.w.advance(x.world,{},previous)
	x.world.facts.sim_tick += 1
	x.world.touch(false)
	x.space.finish_boundary(x.world)

func _blocked(x: Dictionary, cell: Array, floor_id: int) -> void:
	HospitalFactory._add_staff(x.world,"replacement","替班职员","nurse",cell,_content)
	x.world.facts.actors.replacement.location.floor_id = floor_id
	for key: String in ["r","d","s","w","l","c","f","e","p","m","a"]: x[key].ensure(x.world)
	x.space.sync_actor(x.world,"replacement")
	x.world.touch()

func _overlap(x: Dictionary) -> bool:
	var bodies: Array = []
	for actor: Dictionary in x.world.facts.actors.values():
		if actor.location.kind=="floor": bodies.append({"floor":int(actor.location.floor_id),"rect":x.space.body_rectangle(actor)})
	for a: int in bodies.size():
		for b: int in range(a+1,bodies.size()):
			if bodies[a].floor==bodies[b].floor and bodies[a].rect.intersects(bodies[b].rect,false): return true
	return false

func _case(mode: String) -> Dictionary:
	var x: Dictionary
	var origin: Array = [42,80]
	var floor_id: int = 1
	if mode=="occupied_during_ride":
		var suite = preload("res://tests/acceptance/space.gd").new()
		suite.content = _content
		var transit: HospitalSimulation = suite._transit_fixture()
		x = _bind(WorldState.new(transit.world.freeze()))
		transit.dispose()
		HospitalFactory._add_staff(x.world,"returning_nurse","返岗护士","nurse",[52,84],_content)
		floor_id = 2
		origin = [52,84]
		x.world.facts.actors.returning_nurse.location.floor_id = floor_id
		for key: String in ["r","d","s","w","l","c","f","e","p","m","a"]: x[key].ensure(x.world)
	else:
		x = _fixture({"returning_nurse":"nurse"})
		_position(x,"returning_nurse",origin)
	var staff: Dictionary = x.world.facts.staff.returning_nurse
	var actor: Dictionary = x.world.facts.actors.returning_nurse
	var schedule: Variant = staff.get("schedule",{}).duplicate(true)
	x.world.touch()
	var input_validation: String = x.world.validate(_content)
	var leave: Dictionary = x.s.execute(x.world,"plan_leave",{"staff_id":staff.id,"days":1,"start":"now"}).to_record()
	var left: bool = false
	for n: int in 1800:
		_tick(x)
		if staff.life_task.phase=="offsite": left = true;break
	var before_recall: String = x.world.validate(_content)
	if mode in ["occupied_before_recall","occupied_restored"]: _blocked(x,origin,floor_id)
	if mode=="old_point_built_over":
		x.world.facts.floors.overrides[str(floor_id)].blocked.append(origin.duplicate())
		x.world.touch()
	var recall: Dictionary = x.s.execute(x.world,"cancel_leave",{"staff_id":staff.id}).to_record()
	var before_reentry: Dictionary = actor.location.duplicate(true)
	var at_command_outside: bool = actor.location.kind=="outside" and actor.location==before_reentry
	var old_target: Array = []
	var walked_return: bool = false
	var entered: bool = false
	var blocked_during: bool = false
	var ride_preserved: bool = true
	var overlaps: bool = false
	var validation: String = ""
	var recovered: bool = false
	var changes: Array = []
	var previous: Dictionary = actor.location.duplicate(true)
	for n: int in 1000:
		_tick(x)
		entered = entered or actor.location.kind=="floor"
		if actor.location.kind=="floor" and previous.kind=="floor" and actor.location!=previous: walked_return = true
		previous = actor.location.duplicate(true)
		if old_target.is_empty() and staff.life_task.phase=="returning": old_target = staff.life_task.cell.duplicate()
		if mode=="occupied_during_walk" and not blocked_during and walked_return:
			_blocked(x,origin,floor_id)
			blocked_during = true
		if mode=="occupied_during_ride" and not blocked_during and actor.location.kind=="transit":
			var location: Dictionary = actor.location.duplicate(true)
			var movement: Dictionary = x.world.facts.moves[staff.id].duplicate(true)
			_blocked(x,origin,floor_id)
			x.w.dispatch(x.world)
			ride_preserved = actor.location==location and x.world.facts.moves.get(staff.id,{})==movement
			blocked_during = true
		if mode=="occupied_restored" and entered and changes.is_empty():
			x = _restore(x)
			staff = x.world.facts.staff.returning_nurse
			actor = x.world.facts.actors.returning_nurse
			changes.append("restored_after_reentry")
		overlaps = overlaps or _overlap(x)
		if n%50==0: validation = x.world.validate(_content)
		if not validation.is_empty(): break
		if staff.life_task.phase=="idle": recovered = true;break
	var final_location: Dictionary = actor.location.duplicate(true)
	var replacement_unchanged: bool = not x.world.facts.actors.has("replacement") or x.world.facts.actors.replacement.location.cell==origin and int(x.world.facts.actors.replacement.location.floor_id)==floor_id
	# Only the normal next scheduler/base-preparation boundary restores work
	# eligibility. The life service does not force a shift or reclaim a bed.
	if recovered:
		x.s.boundaries(x.world)
		x.d.dispatch(x.world)
	var current_schedule: bool = staff.get("schedule",{})==schedule and staff.on_shift and not staff.block_new_work and staff.leave_plan.is_empty()
	var same_free_target: bool = mode!="free_control" or x.space.at(x.world,staff.id,floor_id,origin)
	var new_safe_target: bool = mode=="free_control" or actor.location.kind=="floor" and x.space.public_areas.safe_wait(x.world,staff.id,int(actor.location.floor_id),actor.location.cell)
	var final_validation: String = x.world.validate(_content)
	var passed: bool = input_validation.is_empty() and before_recall.is_empty() and leave.accepted and recall.accepted and left and at_command_outside and entered and recovered and current_schedule and replacement_unchanged and same_free_target and new_safe_target and not overlaps and validation.is_empty() and final_validation.is_empty() and ride_preserved and (mode!="occupied_during_ride" or blocked_during)
	return {"passed":passed,"input_validation":input_validation,"pre_recall_validation":before_recall,"leave":leave,"recall":recall,"real_departure":left,"at_command_outside":at_command_outside,"real_reentry":entered,"walked_return":walked_return,"recovered":recovered,"current_schedule":current_schedule,"replacement_unchanged":replacement_unchanged,"same_free_target":same_free_target,"new_safe_target":new_safe_target,"ride_preserved":ride_preserved,"occupied_during":blocked_during,"changes":changes,"overlaps":overlaps,"validation":validation,"final_validation":final_validation,"final_location":final_location,"final_task":staff.life_task.duplicate(true)}

func run_case(t, content: HospitalContent) -> void:
	_content = content
	var results: Dictionary = {}
	var passed: bool = true
	for mode: String in ["free_control","occupied_before_recall","occupied_during_walk","occupied_restored","old_point_built_over","occupied_during_ride"]:
		var result: Dictionary = _case(mode)
		results[mode] = result
		passed = passed and result.passed
	t.check("STAFF-77",passed,results)
