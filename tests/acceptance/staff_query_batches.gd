extends "res://tests/acceptance/staff_fixtures.gd"

const ClinicalFixtures = preload("res://tests/acceptance/clinical_fixtures.gd")

func run(t, database: HospitalContent) -> void:
	_content = database
	var tea: Dictionary = tea_rules()
	var facilities: Dictionary = facility_rules()
	var handoff: Dictionary = await handoff_rules(t)
	t.check("STAFF-41",tea.ok and facilities.ok and handoff.ok,{"tea":tea,"facilities":facilities,"handoff":handoff})

func tea_rules() -> Dictionary:
	var x: Dictionary = _fixture({"searcher":"doctor","other":"nurse"})
	var room_id: String = _room(x)
	_facility(x,"chair","FUR06",[43,75],room_id)
	x.world.touch()
	var checks: Array = []
	var immutable: bool = true
	for species_id: String in ["S49","S01","S08"]:
		x.world.facts.actors.searcher.species_id = species_id
		var before: Dictionary = x.world.freeze()
		var point: Dictionary = x.w._tea_position(x.world,"searcher")
		var legal: bool = not point.is_empty() and x.space.static_reason(x.world,x.world.facts.actors.searcher,1,Vector2i(point.cell[0],point.cell[1])).is_empty() and x.space.route(x.world,"searcher",1,point.cell).ok and x.space.public_areas.safe_wait(x.world,"searcher",1,point.cell)
		checks.append(legal)
		immutable = immutable and before==x.world.freeze()
	return {"ok":not false in checks and immutable,"three_real_bodies":checks,"readonly":immutable}

func facility_rules() -> Dictionary:
	var x: Dictionary = _fixture({"searcher":"doctor","reserved":"nurse"})
	var room_id: String = _room(x)
	_facility(x,"a_bed","SE04",[40,75],room_id)
	_facility(x,"b_bed","SE04",[48,75],room_id)
	_position(x,"searcher",[38,79])
	x.w.ensure(x.world)
	var before: Dictionary = x.world.freeze()
	var selected: Dictionary = x.w._select_facility(x.world,"searcher","sleep")
	var immutable: bool = before==x.world.freeze()
	var route_ok: bool = false
	if not selected.is_empty():
		var fit: Dictionary = x.space.facility_quote(x.world,selected.facility_id,"searcher")
		var candidate: WorldState = x.w._adapted_candidate(x.world,selected.facility_id,fit,"searcher")
		var outward: Dictionary = HospitalSpace.new(_content).route(candidate,"searcher",selected.floor_id,selected.cell)
		candidate.facts.actors.searcher.location = {"kind":"floor","floor_id":selected.floor_id,"cell":selected.cell.duplicate(),"height_m":0.0}
		var back: Dictionary = HospitalSpace.new(_content).route(candidate,"searcher",1,before.actors.searcher.location.cell)
		route_ok = outward.ok and back.ok
	var own_bed: String = str(selected.get("facility_id",""))
	var refused: String = x.space.reserve_facility(x.world,own_bed,"reserved","other_sleep") if not own_bed.is_empty() else "missing"
	if not own_bed.is_empty(): x.world.facts.facilities[own_bed].failed = true
	var none: Dictionary = x.w._select_facility(x.world,"searcher","sleep")
	return {"ok":not selected.is_empty() and immutable and route_ok and refused=="他人个人床" and none.is_empty(),"selected":selected,"other_owner_refused":refused,"immutable":immutable,"independent_round_trip":route_ok}

func handoff_rules(t) -> Dictionary:
	var fixture = ClinicalFixtures.new()
	fixture._content = _content
	fixture._cache = t.checkpoints(_content,"res://tests/acceptance/clinical_fixtures.gd",fixture)
	if not await fixture._ensure_boundary(t,"ward_after_care"):
		fixture._dispose_simulations()
		return {"ok":false,"missing":"ward_after_care"}
	var c: Dictionary = fixture._copy("ward_after_care")
	var stay: Dictionary = fixture._stay(c)
	var old_id: String = stay.nurse_id
	var ward_id: String = c.world.facts.facilities[stay.bed_id].room_id
	for staff: Dictionary in c.world.facts.staff.values():
		if staff.role=="nurse": staff.on_shift = false
	# Finish the original nurse's real safe release, then let them actually
	# leave the ward. A missing replacement does not force endless overtime.
	var old_location: Dictionary = c.world.facts.actors[old_id].location.duplicate(true)
	for tick: int in 300:
		c.sim.clinic._dispatch_clinical_releases(c.world)
		if not c.world.facts.staff[old_id].has("clinical_release") and not c.world.facts.moves.has(old_id): break
		_advance_people(c)
	var departure_reason: String = c.sim.space.request_move(c.world,old_id,1,[43,75])
	for tick: int in 500:
		if c.sim.space.at(c.world,old_id,1,[43,75]): break
		_advance_people(c)
	var departed: bool = c.sim.space.at(c.world,old_id,1,[43,75]) and c.world.facts.actors[old_id].location!=old_location
	if not departed:
		var failure: Dictionary = {"ok":false,"old_departure":false,"departure_reason":departure_reason,"old_actor":c.world.facts.actors[old_id].duplicate(true),"old_move":c.world.facts.moves.get(old_id,{}).duplicate(true)}
		fixture._dispose_simulations()
		return failure
	fixture._add_worker(c.world,"a_relief","nurse",[44,74],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":0})
	c.sim._ensure_services()
	var scheduler: HospitalShiftScheduler = c.sim.services.scheduler
	var bedside: Array = HospitalShiftScheduler._bedside(c.sim.space.facility_layout(c.world,stay.bed_id))
	var default_route: Dictionary = c.sim.space.route(c.world,"a_relief",int(c.world.facts.facilities[stay.bed_id].floor_id),bedside)
	var blocked: WorldState = WorldState.new(c.world.freeze())
	blocked.facts.floors.overrides["1"].blocked.append(bedside.duplicate())
	blocked.touch()
	var blocked_before: Dictionary = blocked.freeze()
	HospitalShiftScheduler.new(_content,HospitalSpace.new(_content)).dispatch(blocked)
	var failure_atomic: bool = blocked.freeze()==blocked_before
	scheduler.dispatch(c.world)
	var handoff: Dictionary = c.world.facts.staff_schedule.handoffs.get(ward_id,{})
	var started: bool = handoff.get("new_id","")=="a_relief" and handoff.get("stay_ids",[])==[stay.id] and stay.nurse_id==old_id and c.world.facts.staff.a_relief.block_new_work
	var access: Array = c.world.facts.adaptations.get(stay.bed_id,{}).get("staff_ids",[])
	started = started and "a_relief" in access and old_id in access and stay.round_doctor_id in access
	if not started:
		var details: Dictionary = {"ok":false,"started":false,"default_route":default_route,"bed_adaptation":c.world.facts.adaptations.get(stay.bed_id,{}).duplicate(true)}
		fixture._dispose_simulations()
		return details
	var frozen: Dictionary = c.world.freeze()
	var restored: WorldState = WorldState.new(frozen.duplicate(true))
	var geometry: HospitalSpace = HospitalSpace.new(_content)
	scheduler = HospitalShiftScheduler.new(_content,geometry)
	var before_arrival: bool = true
	var actual_work: int = 0
	for tick: int in 900:
		scheduler.dispatch(restored)
		geometry.advance(restored)
		var active: Dictionary = restored.facts.staff_schedule.handoffs.get(ward_id,{})
		if not active.is_empty() and active.phase!="working":
			before_arrival = before_arrival and int(active.remaining_ticks)==50 and restored.facts.ward_stays[stay.id].nurse_id==old_id
		if not active.is_empty() and active.phase=="working": actual_work += 1
		scheduler.advance(restored)
		restored.facts.sim_tick += 1
		restored.touch(false)
		if restored.facts.staff_schedule.handoffs.is_empty(): break
	var completed: bool = restored.facts.ward_stays[stay.id].nurse_id=="a_relief" and restored.facts.staff.a_relief.ward_id==ward_id and not restored.facts.staff.a_relief.block_new_work and actual_work==50
	# A replacement going off shift cancels the saved handoff without moving
	# responsibility or consuming the original five seconds again.
	var cancelled: WorldState = WorldState.new(frozen.duplicate(true))
	cancelled.facts.staff.a_relief.on_shift = false
	HospitalShiftScheduler.new(_content,HospitalSpace.new(_content)).advance(cancelled)
	var cancellation: bool = cancelled.facts.staff_schedule.handoffs.is_empty() and cancelled.facts.ward_stays[stay.id].nurse_id==old_id
	fixture._dispose_simulations()
	return {"ok":departed and started and failure_atomic and before_arrival and completed and cancellation,"old_departure":departed,"started":started,"route_before_handoff_permission":default_route,"blocked_failure_atomic":failure_atomic,"before_arrival":before_arrival,"actual_work_ticks":actual_work,"completed_after_restore":completed,"cancelled_on_shift_change":cancellation,"final_new_location":restored.facts.actors.a_relief.location,"remaining_handoff":restored.facts.staff_schedule.handoffs.get(ward_id,{}),"remaining_move":restored.facts.moves.get("a_relief",{})}

func _advance_people(c: Dictionary) -> void:
	var previous: Dictionary = {}
	for id: String in c.world.ids("staff"): previous[id] = c.world.facts.actors[id].location.duplicate(true)
	c.sim.space.advance(c.world)
	c.sim.services.wellbeing.advance(c.world,{},previous)
	c.world.facts.sim_tick += 1
	c.world.touch(false)
