extends "res://tests/acceptance/staff_fixtures.gd"

func _tick(x: Dictionary) -> void:
	x.w.dispatch(x.world)
	var previous: Dictionary = {}
	for id: String in x.world.ids("staff"): previous[id] = x.world.facts.actors[id].location.duplicate(true)
	x.space.advance(x.world)
	x.w.advance(x.world,{},previous)
	x.world.facts.sim_tick += 1
	x.world.touch(false)
	x.space.finish_boundary(x.world)

func _case(role: String, kind: String, restore: bool) -> Dictionary:
	var x: Dictionary = _fixture({"exiting_staff":role})
	# Initial position only. The measured walk to the entrance is real.
	_position(x,"exiting_staff",[48,94])
	var actor: Dictionary = x.world.facts.actors.exiting_staff
	var staff: Dictionary = x.world.facts.staff.exiting_staff
	var request_ok: bool = true
	if kind=="leave": request_ok = x.s.execute(x.world,"plan_leave",{"staff_id":"exiting_staff","days":1,"start":"now"}).accepted
	else: staff.awake_ticks = 13500
	x.world.touch()
	var input_validation: String = x.world.validate(_content)
	var start: Dictionary = actor.location.duplicate(true)
	var boundary: bool = false
	for n: int in 400:
		_tick(x)
		if staff.life_task.phase=="exiting" and x.space.at(x.world,staff.id,int(staff.life_task.floor_id),staff.life_task.cell) and x.world.facts.moves.has(staff.id):
			boundary = true
			break
	var before_validation: String = x.world.validate(_content)
	var moved: bool = start!=actor.location
	var endpoint: Dictionary = actor.location.duplicate(true)
	var task: Dictionary = staff.life_task.duplicate(true)
	var movement: Dictionary = x.world.facts.moves.get(staff.id,{}).duplicate(true)
	if restore:
		x = _restore(x)
		staff = x.world.facts.staff.exiting_staff
		actor = x.world.facts.actors.exiting_staff
	var departure_tick: int = x.world.sim_tick
	x.w.dispatch(x.world)
	var clean_exit: bool = staff.life_task.phase=="offsite" and actor.location.kind=="outside" and not x.world.facts.moves.has(staff.id)
	var zero_clock: bool = int(staff.life_task.get("offsite_ticks",-1))==0
	var leave_clock: bool = kind!="leave" or int(staff.leave_plan.actual_start_tick)==departure_tick and int(staff.leave_plan.end_tick)==departure_tick+WorldState.TICKS_PER_DAY
	x.w.dispatch(x.world)
	var idempotent: bool = int(staff.life_task.get("offsite_ticks",-1))==0 and (kind!="leave" or int(staff.leave_plan.actual_start_tick)==departure_tick)
	var next_step: bool = false
	if clean_exit:
		# This was the crashing next phase: route validation must never see an
		# outside actor still owned by its old floor movement.
		x.space.advance(x.world)
		next_step = not x.world.facts.moves.has(staff.id) and actor.location.kind=="outside"
	var recovery: Dictionary = {"passed":true,"tested":false}
	if clean_exit and role=="nurse" and kind=="sleep" and not restore:
		recovery = _recover_and_return(x,task)
	var final_validation: String = x.world.validate(_content)
	return {"passed":request_ok and input_validation.is_empty() and before_validation.is_empty() and boundary and moved and clean_exit and zero_clock and leave_clock and idempotent and next_step and recovery.passed and final_validation.is_empty(),"role":role,"kind":kind,"restored":restore,"input_validation":input_validation,"before_validation":before_validation,"real_terminal_move_boundary":boundary,"walked":moved,"endpoint":endpoint,"terminal_cursor":movement.get("cursor",-1),"terminal_path_size":movement.get("path",[]).size(),"clean_exit":clean_exit,"zero_offsite_clock":zero_clock,"leave_clock":leave_clock,"idempotent":idempotent,"next_movement_phase":next_step,"recovery":recovery,"final_validation":final_validation}

func _recover_and_return(x: Dictionary, exit_task: Dictionary) -> Dictionary:
	var staff: Dictionary = x.world.facts.staff.exiting_staff
	var actor: Dictionary = x.world.facts.actors.exiting_staff
	# Another real body occupies the entrance while the full offsite sleep
	# elapses. Do not replace the endpoint with a fabricated completed timer.
	HospitalFactory._add_staff(x.world,"entry_occupant","入口使用者","cleaner",exit_task.cell,_content)
	for key: String in ["r","d","s","w","l","c","f","e","p","m","a"]: x[key].ensure(x.world)
	x.world.touch()
	var input_validation: String = x.world.validate(_content)
	for n: int in 4500: _tick(x)
	var blocked_return: bool = staff.life_task.phase=="offsite" and actor.location.kind=="outside" and not x.world.facts.moves.has(staff.id) and int(staff.life_task.offsite_ticks)==4500 and int(staff.sleep_remaining_ticks)==0
	var reason: String = x.space.request_move(x.world,"entry_occupant",1,[44,92])
	var returning: bool = false
	var fresh_route: bool = false
	for n: int in 300:
		_tick(x)
		returning = returning or staff.life_task.phase=="returning" and actor.location.kind=="floor"
		var move: Dictionary = x.world.facts.moves.get(staff.id,{})
		fresh_route = fresh_route or not move.is_empty() and move.target_cell==[48,94] and move.target_cell!=exit_task.cell
		if staff.life_task.phase=="idle": break
	var completed: bool = staff.life_task.phase=="idle" and actor.location.kind=="floor" and x.space.public_areas.safe_wait(x.world,staff.id,int(actor.location.floor_id),actor.location.cell)
	return {"passed":input_validation.is_empty() and blocked_return and reason.is_empty() and returning and fresh_route and completed,"tested":true,"input_validation":input_validation,"full_sleep_ticks":4500,"blocked_entrance_wait":blocked_return,"returning":returning,"fresh_return_route":fresh_route,"completed":completed,"return_location":actor.location.duplicate(true)}

func run_case(t, database: HospitalContent) -> void:
	_content = database
	var results: Dictionary = {}
	var passed: bool = true
	for role: String in ["doctor","nurse","cleaner","researcher"]:
		for restore: bool in [false,true]:
			var result: Dictionary = _case(role,"sleep",restore)
			results[role+"_sleep_"+str(restore)] = result
			passed = passed and result.passed
	for restore: bool in [false,true]:
		var result: Dictionary = _case("doctor","leave",restore)
		results["doctor_leave_"+str(restore)] = result
		passed = passed and result.passed
	t.check("STAFF-76",passed,results)
