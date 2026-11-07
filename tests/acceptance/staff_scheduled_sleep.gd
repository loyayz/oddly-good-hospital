extends "res://tests/acceptance/staff_fixtures.gd"

func _input(kinds: Array, tick: int, awake: int, bed: bool = true, role: String = "nurse") -> Dictionary:
	var x: Dictionary = _fixture({"sleeper":role})
	var room: String = _room(x)
	if bed: _facility(x,"bed","SE04",[43,75],room)
	_position(x,"sleeper",[43,80])
	# Legal pre-dispatch boundaries, not fabricated sleep completion. Journeys
	# below execute every actual travel, sleeping and next-shift tick.
	x.world.facts.sim_tick = tick
	x.world.facts.staff.sleeper.awake_ticks = awake
	x.request = {"changes":[{"staff_id":"sleeper","schedule":_schedule(kinds)}]}
	x.result = x.s.execute(x.world,"apply_schedule",x.request)
	x.s.boundaries(x.world)
	x.w.ensure(x.world)
	return x

func _boundaries() -> Dictionary:
	var samples: Array = [
		{"id":"first_rest_before_idle_threshold","tick":0,"awake":0,"kinds":["rest","work","work"],"due":true},
		{"id":"middle_rest_before_idle_threshold","tick":6000,"awake":6000,"kinds":["work","rest","work"],"due":true},
		{"id":"exact_limit_not_early","tick":4500,"awake":0,"kinds":["rest","work","work"],"due":false},
		{"id":"one_tick_over_limit","tick":4499,"awake":0,"kinds":["rest","work","work"],"due":true},
		{"id":"working_shift_not_scheduled_rest","tick":0,"awake":0,"kinds":["work","work","rest"],"due":false},
		{"id":"adjacent_next_rest_within_limit","tick":0,"awake":0,"kinds":["rest","rest","work"],"due":false},
		{"id":"second_adjacent_rest_before_long_gap","tick":6000,"awake":6000,"kinds":["rest","rest","work"],"due":true}
	]
	var results: Dictionary = {}
	var passed: bool = true
	for sample: Dictionary in samples:
		var x: Dictionary = _input(sample.kinds,sample.tick,sample.awake)
		var due: bool = x.w._rest_shift_sleep_due(x.world,x.world.facts.staff.sleeper)
		x.w.dispatch(x.world)
		var selected: bool = x.world.facts.staff.sleeper.life_task.get("kind","")=="sleep"
		var ok: bool = x.result.accepted and due==sample.due and selected==sample.due and x.w.personal_beds.bed_for(x.world,"sleeper")=="bed"
		results[sample.id] = {"passed":ok,"due":due,"selected":selected,"task":x.world.facts.staff.sleeper.life_task.duplicate(true)}
		passed = passed and ok
	# Valid effective-assignment inputs: today's overrides take precedence;
	# tomorrow must use the repeating template, not today's overrides.
	for sample: Dictionary in [
		{"id":"today_current_override_work","tick":0,"kinds":["rest","work","work"],"overrides":{"0":{"kind":"work","pools":[],"locked":false},"1":{"kind":"rest","pools":[],"locked":false}},"due":false},
		{"id":"today_next_override_rest","tick":0,"kinds":["rest","work","work"],"overrides":{"1":{"kind":"rest","pools":[],"locked":false}},"due":false},
		{"id":"tomorrow_ignores_today_override","tick":16000,"kinds":["work","work","rest"],"overrides":{"0":{"kind":"rest","pools":[],"locked":false}},"due":true}
	]:
		var x: Dictionary = _input(sample.kinds,sample.tick,0)
		x.world.facts.staff.sleeper.schedule_overrides = sample.overrides.duplicate(true)
		var due: bool = x.w._rest_shift_sleep_due(x.world,x.world.facts.staff.sleeper)
		var valid: String = x.s.validate(x.world)
		results[sample.id] = {"passed":due==sample.due and valid.is_empty(),"due":due,"schedule_validation":valid}
		passed = passed and results[sample.id].passed
	return {"passed":passed,"results":results}

func _guards() -> Dictionary:
	var results: Dictionary = {}
	var passed: bool = true
	for role: String in ["receptionist","doctor","nurse","cleaner","researcher","decorator"]:
		var x: Dictionary = _input(["rest","work","work"],0,0,false,role)
		x.w.dispatch(x.world)
		var staff: Dictionary = x.world.facts.staff.sleeper
		var ok: bool = x.result.accepted and staff.life_task.phase=="idle" and staff.sleep_remaining_ticks==0 and x.world.facts.actors.sleeper.location.kind=="floor"
		results[role+"_no_bed"] = {"passed":ok,"phase":staff.life_task.phase}
		passed = passed and ok
	var moving: Dictionary = _input(["rest","work","work"],0,0)
	var reason: String = moving.space.request_move(moving.world,"sleeper",1,[45,80])
	var original: Dictionary = moving.world.facts.moves.get("sleeper",{}).duplicate(true)
	moving.w.dispatch(moving.world)
	var safe: bool = reason.is_empty() and not original.is_empty() and moving.world.facts.moves.get("sleeper",{})==original and moving.world.facts.staff.sleeper.life_task.phase=="idle"
	results.safe_existing_move = {"passed":safe,"reason":reason}
	passed = passed and safe
	for awake: int in [8999,9000,13499,13500]:
		var x: Dictionary = _input(["work","work","rest"],9000,awake)
		# An original dispatcher explicitly found idle work in this boundary.
		x.world.facts.staff.sleeper.dispatch_idle = awake<=9000
		x.world.facts.staff.sleeper.dispatch_idle_tick = x.world.sim_tick
		x.w.dispatch(x.world)
		var selected: bool = x.world.facts.staff.sleeper.life_task.get("kind","")=="sleep"
		var expected: bool = awake in [9000,13500]
		results["original_awake_"+str(awake)] = {"passed":selected==expected,"selected":selected,"expected":expected}
		passed = passed and selected==expected
	return {"passed":passed,"results":results}

func _journey(kinds: Array, start_tick: int, restore_sleep: bool) -> Dictionary:
	var x: Dictionary = _input(kinds,start_tick,start_tick)
	# Real post-rest work is an actual walk to the existing kind of guide desk.
	# These are independent legal fixture facilities, not the faulty starter beds.
	_facility(x,"nurse_base","SE06",[50,80],"support_room")
	_facility(x,"guide","SE01",[40,92])
	var sim: HospitalSimulation = HospitalSimulation.new(x.world,_content)
	var first_validation: String = sim.world.validate(_content)
	var before_cash: int = HospitalLedger.balance(sim.world)
	var before_wage: int = int(sim.world.facts.staff.sleeper.wage_numerator)
	var input_quote: Dictionary = sim.space.facility_trip_quote(sim.world,"bed","sleeper")
	var next_shift: int = start_tick+6000
	var total_sleep: int = 0
	var restored: bool = false
	var first_sleep: int = -1
	var finished_sleep: int = -1
	var sleep_entries: int = 0
	var no_early_progress: bool = true
	var actual_lying: bool = true
	var completion_reset: bool = false
	var returned_before_shift: bool = false
	var desk_ready: bool = false
	var errors: Array = []
	var steps: int = 0
	for index: int in 6800:
		var staff: Dictionary = sim.world.facts.staff.sleeper
		var prior: Dictionary = staff.life_task.duplicate(true)
		var remaining: int = int(staff.sleep_remaining_ticks)
		var tick: int = sim.world.sim_tick
		var result: TickResult = sim.step()
		steps += 1
		if result==null or sim.world.sim_tick!=tick+1: errors.append("incomplete normal step"); break
		staff = sim.world.facts.staff.sleeper
		var task: Dictionary = staff.life_task
		if task.get("kind","")=="sleep" and prior.get("kind","")!="sleep": sleep_entries += 1
		var delta: int = maxi(0,remaining-int(staff.sleep_remaining_ticks))
		if delta>0:
			total_sleep += delta
			if first_sleep<0: first_sleep = tick
			actual_lying = actual_lying and (sim.world.facts.actors.sleeper.get("posture","")=="lying" or task.phase=="returning")
		if task.get("phase","") in ["travel","wait_safe","wait_bed"] and prior.get("phase","")==task.phase and remaining>0:
			no_early_progress = no_early_progress and delta==0
		if remaining>0 and staff.sleep_remaining_ticks==0:
			finished_sleep = tick
			completion_reset = staff.awake_ticks==0 and total_sleep==4500
		if finished_sleep>=0 and tick<next_shift and task.phase=="idle": returned_before_shift = true
		if restore_sleep and not restored and total_sleep==250:
			var snapshot: Dictionary = sim.world.freeze()
			var old_remaining: int = staff.sleep_remaining_ticks
			sim.dispose()
			sim = HospitalSimulation.new(WorldState.new(snapshot),_content)
			restored = sim.world.facts.staff.sleeper.sleep_remaining_ticks==old_remaining and old_remaining==4250
		var desk: Dictionary = sim.world.facts.floor_guidance.desks.get("guide",{})
		if tick>=next_shift and desk.get("nurse_id","")=="sleeper" and desk.get("reason","")=="" and HospitalStaffWellbeing.work_window(sim.world.facts.staff.sleeper):
			desk_ready = true
			break
		if index%100==0:
			var validation: String = sim.world.validate(_content)
			if not validation.is_empty(): errors.append(validation); break
	var final_validation: String = sim.world.validate(_content)
	var final_staff: Dictionary = sim.world.facts.staff.sleeper
	var wages: bool = int(final_staff.wage_numerator)==before_wage+steps*100
	var unchanged_economics: bool = sim.world.facts.staff.size()==1 and HospitalLedger.balance(sim.world)==before_cash and wages
	var ok: bool = x.result.accepted and first_validation.is_empty() and input_quote.get("ok",false) and total_sleep==4500 and sleep_entries==1 and no_early_progress and actual_lying and completion_reset and returned_before_shift and desk_ready and (not restore_sleep or restored) and unchanged_economics and final_validation.is_empty() and errors.is_empty()
	var details: Dictionary = {"passed":ok,"start_tick":start_tick,"schedule":kinds,"command":x.result.to_record(),"input_validation":first_validation,"bed_trip":input_quote,"first_actual_sleep_tick":first_sleep,"sleep_completed_tick":finished_sleep,"actual_sleep_ticks":total_sleep,"sleep_entries":sleep_entries,"no_travel_sleep_credit":no_early_progress,"lying":actual_lying,"awake_reset_at_completion":completion_reset,"returned_before_next_shift":returned_before_shift,"next_shift_real_desk_ready":desk_ready,"end_tick":sim.world.sim_tick,"restored_after_250_actual_ticks":restored,"economics_unchanged":unchanged_economics,"wage_delta":int(final_staff.wage_numerator)-before_wage,"steps":steps,"final_validation":final_validation,"final_staff":final_staff.duplicate(true),"errors":errors}
	sim.dispose()
	return details

func run_case(t, database: HospitalContent) -> void:
	_content = database
	var boundaries: Dictionary = _boundaries()
	var guards: Dictionary = _guards()
	var first: Dictionary = _journey(["rest","work","work"],0,true)
	var middle: Dictionary = _journey(["work","rest","work"],6000,false)
	t.check("STAFF-78",boundaries.passed and guards.passed and first.passed and middle.passed,{"boundaries":boundaries,"guards":guards,"first_rest_journey":first,"middle_rest_journey":middle})
