extends "res://tests/acceptance/staff_fixtures.gd"

class ClinicalSelectionProbe extends HospitalClinic:
	var selections: int = 0
	func _dispatch_service(_world: WorldState, _visit: Dictionary, _ticket: Dictionary) -> void:
		selections += 1
	func _prepare_surgery(_world: WorldState, _visit: Dictionary, _ticket: Dictionary) -> void:
		selections += 1

class MixedEntryKnowledge extends HospitalPublicAreas:
	func _entry_landings(world: WorldState, actor_id: String, floor_id: int) -> Dictionary:
		var result: Dictionary = super._entry_landings(world,actor_id,floor_id)
		result.unknown = true
		return result

func run(t, database: HospitalContent, case_id: String) -> void:
	_content = database
	call("_case_"+case_id.right(2),t)

func _areas(staff: Dictionary = {}) -> Dictionary:
	var x: Dictionary = _fixture(staff)
	for entry: Array in [["west",34],["east",48]]:
		HospitalFactory._add_room(x.world,{"id":entry[0],"type":"waiting" if staff.is_empty() else "rest","anchor":[entry[1],66],"size":[10,12],"door":{"definition_id":"DR04","offset":3}},_content)
		_facility(x,str(entry[0])+"_chair","FUR09",[int(entry[1])+2,68],str(entry[0]))
	x.world.touch()
	return x

func _tick_waiting(x: Dictionary, ticks: int = 1) -> void:
	for _tick: int in ticks:
		x.world.facts.sim_tick += 1
		x.c.visitors.dispatch(x.world)
		x.l.dispatch(x.world)
		x.space.advance(x.world)
		x.l.advance(x.world)
		x.world.touch(false)

func _until_seated(x: Dictionary, visit: Dictionary, limit: int = 600) -> bool:
	for _tick: int in limit:
		if x.world.facts.waiting_life.seats.get(visit.id,{}).get("phase","")=="seated": return true
		_tick_waiting(x)
	return false

func _case_45(t) -> void:
	var x: Dictionary = _areas()
	var visit: Dictionary = _visit(x,"regional",[38,90])
	x.world.facts.sim_tick = 50
	x.l.dispatch(x.world)
	var intent: Dictionary = x.world.facts.waiting_life.seats.get(visit.id,{})
	var departure: bool = intent.get("mode","")=="auto" and intent.get("facility_id","missing")=="" and intent.get("area",{}).get("room_id","")=="west" and x.world.facts.adaptations.is_empty()
	var travel_energy: float = float(visit.anger)
	var seated: bool = _until_seated(x,visit)
	t.check("STAFF-45",departure and seated and visit.anger==travel_energy and intent.facility_id=="west_chair" and intent.arrived_tick>=50 and x.l.validate(x.world).is_empty(),{"departure":departure,"seated":seated,"intent":intent,"validation":x.l.validate(x.world)})

func _case_46(t) -> void:
	var x: Dictionary = _areas()
	var first: Dictionary = _visit(x,"holder",[36,70])
	var second: Dictionary = _visit(x,"manual",[51,74])
	var occupied: bool = _seat_checkpoint(x,first,"west_chair")
	var request: CommandResult = x.l.execute(x.world,"waiting_select_seat",{"visit_id":second.id,"facility_id":"west_chair"})
	var fixed: bool = request.accepted and x.world.facts.waiting_life.seats.get(second.id,{}).get("manual_facility_id","")=="west_chair"
	_tick_waiting(x,25)
	fixed = fixed and x.world.facts.actors[second.actor_id].get("support_facility_id","")!="east_chair" and first.get("chair_calm_claimed",false)==false
	x.l.execute(x.world,"waiting_release_seat",{"visit_id":first.id})
	x.c.execute(x.world,"clinical_refer",{"visit_id":first.id})
	var exit: String = x.space.request_move(x.world,first.actor_id,1,[40,74])
	var seated: bool = _until_seated(x,second)
	t.check("STAFF-46",occupied and fixed and exit.is_empty() and seated and x.world.facts.actors[second.actor_id].support_facility_id=="west_chair",{"request":request.to_record(),"fixed":fixed,"seated":seated,"intent":x.world.facts.waiting_life.seats.get(second.id,{})})

func _case_47(t) -> void:
	var modes: Dictionary = _queue_mode_boundary()
	var x: Dictionary = _areas()
	_facility(x,"toilet","FUR07",[39,68],"west")
	x.world.touch()
	var first: Dictionary = _visit(x,"first",[38,73])
	var second: Dictionary = _visit(x,"second",[40,73])
	x.world.facts.sim_tick = 1800
	x.l._begin_need(x.world,first)
	var first_using: bool = false
	for _tick: int in 150:
		if x.world.facts.waiting_life.needs[first.id].phase=="using": first_using = true; break
		_tick_waiting(x)
	x.l._begin_need(x.world,second)
	var queued: bool = x.world.facts.waiting_life.needs[second.id].phase=="local_wait"
	var area: Dictionary = x.space.public_areas.for_facility(x.world,"toilet")
	var reordered: Dictionary = {}
	var keys: Array = area.keys()
	keys.reverse()
	for key: String in keys: reordered[key] = area[key]
	var queue_need: Dictionary = x.world.facts.waiting_life.needs[second.id]
	var original_area: Dictionary = queue_need.area
	queue_need.area = reordered
	var queue_before: Dictionary = x.world.freeze()
	var service_ticks: int = 0
	for service: Dictionary in _content.catalog.amenity_services:
		if service.purpose=="toilet": service_ticks = ceili(float(service.ordinary_seconds)/WorldState.TICK_SECONDS)
	var expected_wait: int = int(x.world.facts.waiting_life.needs[first.id].remaining_ticks)+service_ticks
	x.space.begin_route_query(x.world,{},false)
	var estimate: int = x.space.public_areas._wait_estimate(x.world,area,["toilet"],"toilet")
	var reverse_estimate: int = x.space.public_areas._wait_estimate(x.world,reordered,["toilet"],"toilet")
	x.space.end_route_query()
	var queue_boundary: Dictionary = {"same_region_value":area==reordered,"original_hash":area.hash(),"reordered_hash":reordered.hash(),"former_dictionary_lookup":{reordered:1}.get(area,0),"expected_wait":expected_wait,"estimate":estimate,"reversed_reference_estimate":reverse_estimate,"readonly":queue_before==x.world.freeze()}
	var queue_order_safe: bool = area==reordered and estimate==expected_wait and reverse_estimate==expected_wait and queue_before==x.world.freeze()
	queue_need.area = original_area
	var second_using: bool = false
	var safe_release: bool = true
	for _tick: int in 350:
		var need: Dictionary = x.world.facts.waiting_life.needs.get(second.id,{})
		if need.get("phase","")=="using":
			second_using = true
			safe_release = not x.space.overlaps_facility(x.world,first.actor_id,"toilet")
			break
		_tick_waiting(x)
	var y: Dictionary = _areas()
	_facility(y,"toilet","FUR07",[39,68],"west")
	var exact: Dictionary = _visit(y,"exact",y.space.facility_layout(y.world,"toilet").patient_cell)
	y.world.touch()
	y.l._begin_need(y.world,exact)
	var boundary: Dictionary = y.world.facts.waiting_life.needs[exact.id]
	boundary.phase = "local_wait"
	boundary.remaining_ticks = 0
	boundary.facility_id = ""
	y.world.facts.adaptations.clear()
	y.world.facts.sim_tick = int(boundary.started_tick)+450
	y.l.dispatch(y.world)
	var exact_start: bool = boundary.phase=="using" and boundary.remaining_ticks==80
	t.check("STAFF-47",modes.passed and queue_order_safe and first_using and queued and second_using and safe_release and exact_start,{"nominal_actual_queue_modes":modes,"queue_region_key_order":queue_boundary,"first_started":first_using,"queued":queued,"second_started":second_using,"prior_physically_left":safe_release,"exact_45_seconds":exact_start,"second":x.world.facts.waiting_life.needs.get(second.id,{})})

func _queue_mode_boundary() -> Dictionary:
	var x: Dictionary = _areas()
	_facility(x,"toilet","FUR07",[39,68],"west")
	var requester: Dictionary = _visit(x,"mode_requester",[38,73])
	_visit(x,"mode_blocker",x.space.facility_layout(x.world,"toilet").patient_cell)
	x.world.touch()
	var validation: String = x.world.validate(_content)
	var source: Dictionary = x.world.freeze()
	var observations: Array = []
	var passed: bool = validation.is_empty()
	for nominal_first: bool in [true,false]:
		x.space.begin_route_query(x.world,{"nominal":true},false)
		var nominal: Dictionary = {}
		if nominal_first: nominal = x.space.public_areas._queue_fit(x.world,"toilet",[requester.actor_id])
		x.space.begin_route_query(x.world,{},false)
		var actual: Dictionary = x.space.public_areas._queue_fit(x.world,"toilet",[requester.actor_id])
		x.space.end_route_query()
		if not nominal_first: nominal = x.space.public_areas._queue_fit(x.world,"toilet",[requester.actor_id])
		x.space.end_route_query()
		var cold: Dictionary = x.space.public_areas._queue_fit(x.world,"toilet",[requester.actor_id])
		var exact: bool = nominal.ok and not actual.ok and actual==cold and source==x.world.freeze()
		passed = passed and exact
		observations.append({"nominal_first":nominal_first,"nominal_ok":nominal.ok,"actual_ok":actual.ok,"actual_matches_cold":actual==cold,"readonly":source==x.world.freeze()})
	return {"passed":passed,"validation":validation,"observations":observations}

func _case_48(t) -> void:
	var x: Dictionary = _areas()
	var first: Dictionary = _visit(x,"a_first",[37,73])
	var second: Dictionary = _visit(x,"z_second",[39,73])
	var one: CommandResult = x.l.execute(x.world,"waiting_select_seat",{"visit_id":first.id,"facility_id":"west_chair"})
	var two: CommandResult = x.l.execute(x.world,"waiting_select_seat",{"visit_id":second.id,"facility_id":"west_chair"})
	var no_remote: bool = x.world.facts.adaptations.is_empty()
	var first_seated: bool = _until_seated(x,first)
	var second_seated: bool = x.world.facts.waiting_life.seats[second.id].phase=="seated"
	var ticket: String = first.ticket_id
	var wait_ticks: int = int(x.world.facts.tickets[ticket].waited_ticks)
	var called: bool = x.l.call_patient(x.world,first.id)
	t.check("STAFF-48",one.accepted and two.accepted and no_remote and first_seated and not second_seated and called and first.ticket_id==ticket and x.world.facts.tickets[ticket].waited_ticks==wait_ticks,{"first_seated":first_seated,"second_seated":second_seated,"no_remote_claim":no_remote,"clinical_called":called})

func _case_49(t) -> void:
	var x: Dictionary = _areas({"first":"doctor","second":"nurse"})
	_facility(x,"game","RC03",[36,71],"west")
	x.world.touch()
	for staff: Dictionary in x.world.facts.staff.values():
		staff.energy = 60.0
		staff.stress_milli = 50000
		staff.on_shift = false
	_position(x,"first",[37,75])
	_position(x,"second",[54,87])
	var request: CommandResult = x.w.execute(x.world,"staff_recreation",{"staff_ids":["first","second"],"facility_id":"game"})
	var travelling: bool = request.accepted and not x.world.facts.staff_life.reservations.has("game") and x.world.facts.staff.first.recreation_count==0 and x.w._recreation_count(x.world)==2
	_life_ticks(x,20,true)
	x.w.dispatch(x.world)
	var waiting: bool = x.world.facts.staff.first.recreation_count==0
	x.world.facts.staff.second.active_job_id = "necessary_safe_work"
	x.w.dispatch(x.world)
	var cancelled: bool = x.world.facts.staff.first.life_task.phase=="returning" and x.world.facts.staff.second.life_task.phase=="returning" and x.world.facts.staff.first.recreation_count==0 and not x.world.facts.staff_life.reservations.has("game")
	t.check("STAFF-49",travelling and waiting and cancelled,{"request":request.to_record(),"travelling":travelling,"waited_for_last_member":waiting,"cancelled_before_start":cancelled})

func _case_50(t) -> void:
	var x: Dictionary = _areas()
	var visit: Dictionary = _visit(x,"saved",[37,73])
	x.l.execute(x.world,"waiting_select_seat",{"visit_id":visit.id,"facility_id":"east_chair"})
	var before: Dictionary = x.world.freeze()
	x = _restore(x)
	var same: bool = x.world.freeze()==before
	var seated: bool = _until_seated(x,x.world.facts.visits[visit.id])
	var intent: Dictionary = x.world.facts.waiting_life.seats.get(visit.id,{})
	t.check("STAFF-50",same and seated and intent.mode=="manual" and intent.manual_facility_id=="east_chair" and intent.started_tick==0 and x.l.validate(x.world).is_empty(),{"restore_equal":same,"seated":seated,"intent":intent,"validation":x.l.validate(x.world)})

func _case_51(t) -> void:
	var x: Dictionary = _areas()
	var visit: Dictionary = _visit(x,"manual_invalid",[37,73])
	x.l.execute(x.world,"waiting_select_seat",{"visit_id":visit.id,"facility_id":"west_chair"})
	x.world.facts.facilities.erase("west_chair")
	x.world.touch()
	for _tick: int in 300:
		_tick_waiting(x)
		if not x.world.facts.waiting_life.seats.has(visit.id): break
	var stopped: bool = not x.world.facts.waiting_life.seats.has(visit.id) and x.world.facts.actors[visit.actor_id].get("support_facility_id","")!="east_chair"
	t.check("STAFF-51",stopped,{"stopped_invalid_exact_target":stopped,"reason":visit.waiting_reason})

func _case_52(t) -> void:
	var x: Dictionary = _areas({"resting":"doctor"})
	_position(x,"resting",[38,90])
	x.world.facts.staff.resting.energy = 35.0
	x.w.dispatch(x.world)
	var task: Dictionary = x.world.facts.staff.resting.life_task
	var no_claim: bool = task.phase=="area_travel" and task.facility_id=="" and x.world.facts.staff_life.reservations.is_empty()
	var before: float = float(x.world.facts.staff.resting.energy)
	_life_ticks(x,10,true)
	var no_recovery: bool = float(x.world.facts.staff.resting.energy)<=before
	var rested: bool = _reach_life_phase(x,"resting","rest")
	var start: float = float(x.world.facts.staff.resting.energy)
	_life_ticks(x,10)
	t.check("STAFF-52",no_claim and no_recovery and rested and x.world.facts.staff.resting.energy>start and x.world.facts.staff.resting.awake_ticks>0,{"no_remote_claim":no_claim,"walking_did_not_recover":no_recovery,"rested":rested,"task":task,"energy":x.world.facts.staff.resting.energy})

func _beds() -> Dictionary:
	var x: Dictionary = _fixture({"first":"doctor","second":"nurse"})
	var room: String = _room(x)
	_facility(x,"bed_a","SE04",[40,70],room)
	_facility(x,"bed_b","SE04",[50,70],room)
	x.world.touch()
	x.w.ensure(x.world)
	return x

func _case_53(t) -> void:
	var x: Dictionary = _beds()
	var owners: Dictionary = x.world.facts.staff_life.personal_beds.duplicate(true)
	var own: String = x.w.personal_beds.bed_for(x.world,"first")
	var other: Dictionary = x.space.facility_quote(x.world,own,"second")
	x.world.facts.staff.second.awake_ticks = 13500
	x.world.facts.staff.second.energy = 1.0
	x.w.ensure(x.world)
	var fixed: bool = owners==x.world.facts.staff_life.personal_beds and owners.size()==2 and x.world.facts.adaptations.is_empty()
	x = _restore(x)
	t.check("STAFF-53",fixed and not other.ok and other.reason=="他人个人床" and owners==x.world.facts.staff_life.personal_beds and x.w.validate(x.world).is_empty(),{"fixed":fixed,"owners":owners,"other_employee":other,"validation":x.w.validate(x.world)})

func _case_54(t) -> void:
	var input: Dictionary = {"small":[{"bed_id":"A","travel_ticks":1},{"bed_id":"B","travel_ticks":2}],"giant":[{"bed_id":"A","travel_ticks":1}]}
	var before: Dictionary = input.duplicate(true)
	var complete: Dictionary = HospitalPersonalBedMatching.solve(["small","giant"],input)
	var scarce: Dictionary = HospitalPersonalBedMatching.solve(["first","second"],{"first":[{"bed_id":"A","travel_ticks":9}],"second":[{"bed_id":"A","travel_ticks":1}]})
	var tied: Dictionary = HospitalPersonalBedMatching.solve(["first","second"],{"first":[{"bed_id":"A","travel_ticks":1},{"bed_id":"B","travel_ticks":1}],"second":[{"bed_id":"A","travel_ticks":2},{"bed_id":"B","travel_ticks":2}]})
	t.check("STAFF-54",complete=={"B":"small","A":"giant"} and scarce=={"A":"first"} and tied=={"A":"first","B":"second"} and input==before,{"full_compatible_matching":complete,"scarce_priority":scarce,"stable_tie":tied,"input_unchanged":input==before})

func _case_55(t) -> void:
	var x: Dictionary = _beds()
	var owners: Dictionary = x.world.facts.staff_life.personal_beds.duplicate(true)
	var bed_id: String = x.w.personal_beds.bed_for(x.world,"first")
	var builder: BuildService = BuildService.new(_content,x.space)
	var stored: CommandResult = builder.execute(x.world,"build_store",{"target_id":bed_id})
	x.w.ensure(x.world)
	var kept: bool = stored.accepted and owners==x.world.facts.staff_life.personal_beds and HospitalPersonalBeds.validate(x.world).is_empty()
	var item: Dictionary = x.world.facts.inventory.get("build_items",{}).get(bed_id,{})
	var placed: CommandResult = builder.execute(x.world,"build_facility",{"inventory_id":bed_id,"definition_id":"SE04","floor_id":1,"cell":item.get("cell",[40,70]),"room_id":"support_room"})
	x.w.ensure(x.world)
	var same_id: bool = placed.accepted and owners==x.world.facts.staff_life.personal_beds and x.world.facts.facilities.has(bed_id)
	var removed: CommandResult = builder.execute(x.world,"build_demolish",{"target_id":bed_id})
	x.w.ensure(x.world)
	t.check("STAFF-55",kept and same_id and removed.accepted and not x.world.facts.staff_life.personal_beds.has(bed_id) and x.w.personal_beds.bed_for(x.world,"first").is_empty(),{"stored":stored.to_record(),"ownership_kept_in_inventory":kept,"replaced_same_id":placed.to_record(),"same_id":same_id,"removed":removed.to_record(),"owners":x.world.facts.staff_life.personal_beds})

func _case_56(t) -> void:
	var x: Dictionary = _beds()
	var old_id: String = x.world.hospital_id
	var new_id: String = HospitalSnapshots.uuid()
	var old_staff: String = old_id+":staff"
	var old_bed: String = old_id+":bed"
	var data: Dictionary = {"staff_life":{"personal_beds":{old_bed:{"staff_id":old_staff}}},"staff":{old_staff:{"id":old_staff,"life_task":{"phase":"local_wait","area":{"room_id":old_id+":room","floor_id":1,"anchor":[1,1]},"manual_facility_id":old_bed}}}}
	var library: HospitalLibrary = HospitalLibrary.new(_content,null)
	var ids: Dictionary = {old_staff:new_id+":staff",old_bed:new_id+":bed",old_id+":room":new_id+":room"}
	var rewritten: Dictionary = library._rewrite_ids(data,"",old_id,new_id,ids)
	var owner: Dictionary = rewritten.staff_life.personal_beds.get(new_id+":bed",{})
	var task: Dictionary = rewritten.staff[new_id+":staff"].life_task
	t.check("STAFF-56",owner.get("staff_id","")==new_id+":staff" and task.area.room_id==new_id+":room" and task.manual_facility_id==new_id+":bed" and data.staff_life.personal_beds.has(old_bed),{"owner":owner,"task":task,"source_unchanged":data.staff_life.personal_beds.has(old_bed)})

func _case_57(t) -> void:
	var x: Dictionary = _areas()
	x.world.facts.entry = {"floor_id":1,"cell":[38,90],"exit_cell":[38,90]}
	var owner: Dictionary = _visit(x,"owner",[53,74])
	var admitted: bool = x.c.visitors._admit(x.world,owner,{"purpose":"companion","window":""})
	var seated: bool = false
	var visitor: Dictionary = {}
	for tick: int in 500:
		visitor = x.c.visitors._present(x.world,owner.id)
		if visitor.get("public_use",{}).get("phase","")=="seated": seated = true; break
		_tick_waiting(x)
	var patient: Dictionary = _visit(x,"priority",[40,74])
	var request: CommandResult = x.l.execute(x.world,"waiting_select_seat",{"visit_id":patient.id,"facility_id":"west_chair"})
	var taken: bool = _until_seated(x,patient)
	var clear: bool = not visitor.is_empty() and not x.space.overlaps_facility(x.world,visitor.actor_id,"west_chair")
	t.check("STAFF-57",admitted and seated and request.accepted and taken and clear,{"visitor_admitted":admitted,"visitor_actually_seated":seated,"patient_request":request.to_record(),"patient_seated":taken,"visitor_actually_clear":clear,"patient_intent":x.world.facts.waiting_life.seats.get(patient.id,{}),"patient_actor":x.world.facts.actors[patient.actor_id],"visitor":visitor,"quote":x.l._seat_quote(x.world,patient,"west_chair"),"adaptations":x.world.facts.adaptations,"other_seats":x.world.facts.waiting_life.seats})

func _case_58(t) -> void:
	var x: Dictionary = _areas({"cleaner":"cleaner"})
	_facility(x,"game","RC01",[36,71],"west")
	x.world.touch()
	_position(x,"cleaner",[40,75])
	var staff: Dictionary = x.world.facts.staff.cleaner
	staff.energy = 60.0
	staff.stress_milli = 50000
	staff.on_shift = true
	staff.dispatch_idle = true
	staff.dispatch_idle_tick = x.world.sim_tick
	var request: CommandResult = x.w.execute(x.world,"staff_recreation",{"staff_id":"cleaner","facility_id":"game"})
	var dirt: String = x.e.spawn_dirt(x.world,"CL01","real_public_handoff","receipt_public_handoff",1,[41,75])
	x.e.dispatch(x.world)
	var cancelled: bool = staff.life_task.phase=="returning" and staff.recreation_count==0 and not x.world.facts.staff_life.reservations.has("game")
	var returned: bool = _reach_life_phase(x,"cleaner","idle")
	x.e.dispatch(x.world)
	var assigned: bool = not dirt.is_empty() and x.world.facts.environment.dirt[dirt].worker_id=="cleaner"
	t.check("STAFF-58",request.accepted and cancelled and returned and assigned,{"request":request.to_record(),"cancelled_before_use":cancelled,"returned_safely":returned,"cleanup_assigned":assigned,"dirt":dirt})

func _case_59(t) -> void:
	var checks: Array = []
	for change: String in ["stress","quota"]:
		var x: Dictionary = _areas({"waiting":"nurse"})
		_facility(x,"game","RC01",[36,71],"west")
		x.world.touch()
		_position(x,"waiting",[54,87])
		var staff: Dictionary = x.world.facts.staff.waiting
		staff.energy = 60.0
		staff.stress_milli = 50000
		staff.on_shift = false
		var request: CommandResult = x.w.execute(x.world,"staff_recreation",{"staff_id":"waiting","facility_id":"game"})
		if change=="stress": staff.stress_milli = 0
		else: x.w.execute(x.world,"set_staff_recreation",{"maximum":0})
		x.w.dispatch(x.world)
		checks.append({"change":change,"accepted":request.accepted,"cancelled":staff.life_task.phase=="returning","uncharged":staff.recreation_count==0 and staff.recreation_cooldown_tick==0 and x.world.facts.staff_life.reservations.is_empty()})
	t.check("STAFF-59",checks.all(func(row: Dictionary)->bool: return row.accepted and row.cancelled and row.uncharged),{"qualification_rechecked":checks})

func _case_60(t) -> void:
	var x: Dictionary = _beds()
	var bed_id: String = x.w.personal_beds.bed_for(x.world,"first")
	var second_bed: String = x.w.personal_beds.bed_for(x.world,"second")
	HospitalFactory._add_staff(x.world,"newcomer","新员工","cleaner",[55,80],_content)
	x.world.touch()
	x.w.ensure(x.world)
	var no_borrow: bool = x.w.personal_beds.bed_for(x.world,"newcomer").is_empty()
	var departure: CommandResult = x.f.settle_departure(x.world,"first")
	x.w.ensure(x.world)
	var assigned: bool = x.w.personal_beds.bed_for(x.world,"newcomer")==bed_id and x.w.personal_beds.bed_for(x.world,"first").is_empty()
	var unchanged: bool = x.w.personal_beds.bed_for(x.world,"second")==second_bed and x.world.facts.adaptations.is_empty() and x.world.facts.moves.is_empty()
	t.check("STAFF-60",no_borrow and departure.accepted and assigned and unchanged and x.w.validate(x.world).is_empty(),{"unassigned_did_not_borrow":no_borrow,"employment_settled":departure.to_record(),"released_bed_assigned":assigned,"other_owner_and_positions_unchanged":unchanged,"owners":x.world.facts.staff_life.personal_beds})

func _case_61(t) -> void:
	var x: Dictionary = _areas()
	var visit: Dictionary = _visit(x,"upstairs",[40.35,90.35])
	var plots: Array = HospitalSpace.floor_plots(x.world,1).duplicate(true)
	x.world.facts.floors.completed_top_floor = {}
	for plot: Array in plots: x.world.facts.floors.completed_top_floor[HospitalSpace.plot_key(plot)] = 2
	x.world.facts.floors.height_intervals = [{"first":1,"last":2,"height_m":float(_content.balance.floors.clear_height_m)}]
	x.world.facts.floors.overrides["2"] = {"plots":plots,"blocked":[],"doors":[],"paths":[]}
	x.world.facts.actors[visit.actor_id].location.floor_id = 2
	x.world.facts.connectors.lift = {"id":"lift","definition_id":"VC02","first_floor":1,"last_floor":2,"cell":[58,84],"footprint":[4,4],"rotation":0,"anchor":[59,88],"repair_cell":[57,85],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0,"ticket_next":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},"paid_cost":3200,"used":false}
	x.world.touch()
	var area: Dictionary = x.space.public_areas.for_facility(x.world,"west_chair")
	var before: Dictionary = x.world.freeze()
	var optimized: Dictionary = x.space.public_areas.waiting_point(x.world,visit.actor_id,area)
	var expected: int = 2147483647
	var candidates: int = 0
	var exact_quotes: bool = true
	x.space.begin_dynamic_route_query(x.world)
	for point: Vector2i in x.space.public_areas.region(x.world,area).cells:
		var cell: Array = [point.x,point.y]
		if not x.space.public_areas.safe_wait(x.world,visit.actor_id,1,cell): continue
		var quote: Dictionary = x.space.travel_quote(x.world,visit.actor_id,1,cell)
		var complete: Dictionary = x.space.route(x.world,visit.actor_id,1,cell,[],{},true)
		for field: String in ["ok","status","reason","travel_ticks","walking_distance","quoted_tick"]:
			exact_quotes = exact_quotes and quote.get(field)==complete.get(field)
		if complete.ok and complete.has("travel_ticks"): expected = mini(expected,int(complete.travel_ticks)); candidates += 1
	x.space.end_route_query()
	var tight: Dictionary = x.space.public_areas.waiting_point(x.world,visit.actor_id,area,expected-1)
	var boundary: Dictionary = x.space.public_areas.waiting_point(x.world,visit.actor_id,area,expected)
	var fractional: int = x.space.public_areas._entry_lower_bound(x.world.facts.actors[visit.actor_id],Vector2(40.35,90.35),Vector2i(40,90),{"landings":[],"unknown":false})
	var actual_stub: Dictionary = x.space.travel_quote(x.world,visit.actor_id,2,[40,90])
	var safe_fraction: bool = actual_stub.get("ok",false) and fractional<=int(actual_stub.travel_ticks)
	var readonly: bool = before==x.world.freeze()
	var mixed: MixedEntryKnowledge = MixedEntryKnowledge.new(x.space)
	var mixed_point: Dictionary = mixed.waiting_point(x.world,visit.actor_id,area)
	var finite_retained: bool = mixed_point.get("travel_ticks",-1)==expected
	x.world.facts.connectors.lift.failed = true
	var lowering: Dictionary = x.space.public_areas.waiting_point(x.world,visit.actor_id,area)
	var upward_world: WorldState = WorldState.new(x.world.freeze())
	upward_world.facts.actors[visit.actor_id].location.floor_id = 1
	var upward: Dictionary = HospitalSpace.new(_content).travel_quote(upward_world,visit.actor_id,2,[59,88])
	x.world.facts.connectors.lift.failed = false
	var blocker: Dictionary = _visit(x,"landing_blocker",[59,88])
	x.space.sync_actor(x.world,blocker.actor_id)
	var unknown: Dictionary = x.space.public_areas._entry_landings(x.world,visit.actor_id,1)
	var no_entries: bool = true
	for point: Vector2i in x.space.public_areas.region(x.world,area).cells:
		var cell: Array = [point.x,point.y]
		if not x.space.public_areas.safe_wait(x.world,visit.actor_id,1,cell): continue
		var quote: Dictionary = x.space.route(x.world,visit.actor_id,1,cell,[],{},true)
		no_entries = no_entries and quote.get("ok",false) and quote.has("travel_ticks")
	var unknown_point: Dictionary = x.space.public_areas.waiting_point(x.world,visit.actor_id,area)
	var moved: String = x.space.request_move(x.world,blocker.actor_id,1,[55,91])
	for tick: int in 200:
		if not x.world.facts.moves.has(blocker.actor_id): break
		x.world.facts.sim_tick += 1
		x.space.advance(x.world)
		x.world.touch(false)
	var restored: Dictionary = x.space.public_areas.waiting_point(x.world,visit.actor_id,area)
	var unknown_handled: bool = not unknown.unknown and not unknown.landings.is_empty() and no_entries and not unknown_point.is_empty() and not lowering.is_empty() and not upward.get("ok",true) and moved.is_empty() and not restored.is_empty()
	t.check("STAFF-61",exact_quotes and not optimized.is_empty() and candidates>0 and optimized.travel_ticks==expected and tight.is_empty() and boundary.get("travel_ticks",-1)==expected and safe_fraction and readonly and finite_retained and unknown_handled,{"all_quote_fields_match_complete_routes":exact_quotes,"exact_all_legal_entries":candidates,"expected_ticks":expected,"optimized":optimized,"below_boundary_empty":tight.is_empty(),"exact_boundary":boundary,"fractional_origin_lower_bound_valid":safe_fraction,"readonly":readonly,"finite_landing_retained_with_unknown":finite_retained,"unknown_landings":unknown,"all_legal_entries_remain_reachable":no_entries,"unknown_result":unknown_point,"failed_lift_downward_retained":not lowering.is_empty(),"failed_lift_upward_refused":not upward.get("ok",true),"actual_body_departure":moved,"restored_after_real_exit":restored})

func _case_62(t) -> void:
	var x: Dictionary = _areas()
	var visit: Dictionary = _visit(x,"physical_release",[38,74])
	var requested: CommandResult = x.l.execute(x.world,"waiting_select_seat",{"visit_id":visit.id,"facility_id":"west_chair"})
	var seated: bool = _until_seated(x,visit)
	var while_seated: String = x.world.validate(_content)
	var released: CommandResult = x.l.execute(x.world,"waiting_release_seat",{"visit_id":visit.id})
	var referred: CommandResult = x.c.execute(x.world,"clinical_refer",{"visit_id":visit.id})
	var retained: bool = x.world.facts.adaptations.has("west_chair") and not x.world.facts.waiting_life.seats.has(visit.id)
	var at_release: String = x.world.validate(_content)
	var before: Dictionary = x.world.freeze()
	x = _restore(x)
	var saved: bool = before==x.world.freeze()
	var move: String = x.space.request_move(x.world,visit.actor_id,1,[40,74])
	for _tick: int in 300:
		if not x.world.facts.adaptations.has("west_chair"): break
		_tick_waiting(x)
	var final: String = x.world.validate(_content)
	t.check("STAFF-62",requested.accepted and seated and while_seated.is_empty() and released.accepted and referred.accepted and retained and at_release.is_empty() and saved and move.is_empty() and not x.world.facts.adaptations.has("west_chair") and final.is_empty(),{"seated":seated,"while_seated_validation":while_seated,"adapter_retained_after_intent_end":retained,"release_validation":at_release,"save_equal":saved,"real_move":move,"adapter_released":not x.world.facts.adaptations.has("west_chair"),"final_validation":final})

# Calculation input immediately before an anger update. Actual arrival, queue,
# eight-second work and exit are exercised separately by STAFF-47.
func _case_63(t) -> void:
	var x: Dictionary = _areas()
	var visit: Dictionary = _visit(x,"queue_anger",[40,74])
	x.world.facts.sim_tick = 2000
	var need: Dictionary = {"id":"anger_need","visit_id":visit.id,"actor_id":visit.actor_id,"ticket_id":visit.ticket_id,"purpose":"toilet","public_purpose":"toilet","mode":"auto","area":{},"arrived_tick":1800,"phase":"local_wait","queued_ticks":199,"started_tick":1800,"facility_id":"","remaining_ticks":0,"return_to":x.world.facts.actors[visit.actor_id].location.duplicate(true),"scene_id":""}
	x.world.facts.waiting_life.needs[visit.id] = need
	x.world.facts.tickets[visit.ticket_id].pause_reasons.need_service = need.id
	var results: Array = []
	for input: Array in [["toilet","local_wait",199],["toilet","local_wait",200],["toilet","local_travel",200],["toilet","using",200],["water","local_wait",200]]:
		need.purpose = input[0]
		need.phase = input[1]
		need.queued_ticks = input[2]
		visit.anger = 50.0
		var data: Dictionary = {"anger_sources":{},"cause_clocks":{}}
		x.p._sample_anger(x.world,visit,data,{"value":50.0,"clean":true,"noise":0.0})
		results.append(float(data.anger_sources.get("wait_toilet",0.0)))
	need.phase = "local_wait"
	need.purpose = "toilet"
	need.queued_ticks = 200
	var moved: String = x.space.request_move(x.world,visit.actor_id,1,[41,74])
	x.l.dispatch(x.world)
	var expected: Array = [0.0,1.4,0.0,0.0,0.0] # Original base 2 × PP01 growth 0.7, no environment buffer.
	var correct: bool = true
	for index: int in expected.size(): correct = correct and is_equal_approx(float(results[index]),float(expected[index]))
	t.check("STAFF-63",correct and moved.is_empty() and need.queued_ticks==0,{"toilet_19_9_seconds_toilet_20_seconds_walking_using_water":results,"expected_original_personality_applied":expected,"actual_move_requested":moved,"continuous_queue_cleared_while_moving":need.queued_ticks==0})

func _case_64(t) -> void:
	var x: Dictionary = _areas()
	_facility(x,"west_second","FUR09",[39,68],"west")
	x.world.touch()
	var first: Dictionary = _visit(x,"first_device",[36,74])
	var second: Dictionary = _visit(x,"second_device",[39,74])
	var one: CommandResult = x.l.execute(x.world,"waiting_select_seat",{"visit_id":first.id,"facility_id":"west_chair"})
	var two: CommandResult = x.l.execute(x.world,"waiting_select_seat",{"visit_id":second.id,"facility_id":"west_second"})
	var a: Dictionary = x.world.facts.waiting_life.seats.get(first.id,{})
	var b: Dictionary = x.world.facts.waiting_life.seats.get(second.id,{})
	var parallel: bool = a.get("phase","")=="local_travel" and b.get("phase","")=="local_travel" and x.world.facts.moves.has(first.actor_id) and x.world.facts.moves.has(second.actor_id) and x.world.facts.adaptations.is_empty()
	var both: bool = _until_seated(x,first) and _until_seated(x,second)
	t.check("STAFF-64",one.accepted and two.accepted and parallel and both,{"first":one.to_record(),"second":two.to_record(),"two_real_unreserved_journeys":parallel,"both_actually_seated":both,"intents":x.world.facts.waiting_life.seats,"moves":x.world.facts.moves,"first_actor":x.world.facts.actors[first.actor_id],"second_actor":x.world.facts.actors[second.actor_id]})

func _case_65(t) -> void:
	var x: Dictionary = _areas()
	var visit: Dictionary = _visit(x,"wide_body",[38,73])
	x.world.facts.actors[visit.actor_id].species_id = "S08"
	x.world.facts.floors.overrides["1"].blocked.append([37,70])
	x.world.touch()
	var west: Dictionary = x.space.public_areas.for_facility(x.world,"west_chair")
	var frozen: Dictionary = x.world.freeze()
	var unfit: bool = not x.space.public_areas.compatible_geometry(x.world,west,x.l.PUBLIC_SEAT_DEFINITIONS,[visit.actor_id])
	var readonly: bool = frozen==x.world.freeze()
	x.space.public_areas.invalidate()
	x.world.facts.sim_tick = 50
	x.l.dispatch(x.world)
	var intent: Dictionary = x.world.facts.waiting_life.seats.get(visit.id,{})
	var changed: bool = intent.get("area",{}).get("room_id","")=="east" and intent.get("facility_id","missing")=="" and int(intent.started_tick)==50
	var cumulative: int = int(intent.get("area_travel_ticks",0))
	var seated: bool = _until_seated(x,visit)
	x.world.facts.floors.overrides["1"].blocked.erase([37,70])
	x.world.touch()
	var invalidated: bool = x.space.public_areas.compatible_geometry(x.world,west,x.l.PUBLIC_SEAT_DEFINITIONS,[visit.actor_id])
	t.check("STAFF-65",unfit and readonly and changed and cumulative>0 and seated and intent.facility_id=="east_chair" and intent.started_tick==50 and intent.area_travel_ticks==cumulative and invalidated,{"fixed_geometry_unfit":unfit,"readonly":readonly,"changed_to_legal_area":changed,"cumulative_area_ticks":cumulative,"actually_seated":seated,"original_started_tick":intent.get("started_tick",-1),"geometry_change_rechecks_fit":invalidated})

func _case_66(t) -> void:
	var x: Dictionary = _fixture({"cleaner":"cleaner"})
	_position(x,"cleaner",[38,90])
	var dirt: String = x.e.spawn_dirt(x.world,"CL01","real_cleaning_trip","receipt_cleaning_trip",1,[48,90])
	x.e.dispatch(x.world)
	x.e.advance(x.world)
	var moving: bool = x.world.facts.moves.has("cleaner") and not dirt.is_empty() and x.world.facts.environment.dirt[dirt].worker_id=="cleaner"
	var remaining: int = int(x.world.facts.environment.dirt[dirt].remaining_milli)
	var queries: Dictionary = x.space.query_counts.duplicate()
	x.e.advance(x.world)
	var no_requote: bool = queries==x.space.query_counts and int(x.world.facts.environment.dirt[dirt].remaining_milli)==remaining
	for tick: int in 400:
		if not x.world.facts.environment.dirt.has(dirt): break
		x.world.facts.sim_tick += 1
		x.space.advance(x.world)
		x.e.dispatch(x.world)
		x.e.advance(x.world)
		x.world.touch(false)
	var complete: bool = not x.world.facts.environment.dirt.has(dirt)
	t.check("STAFF-66",moving and no_requote and complete,{"real_journey_started":moving,"no_requote_or_early_work":no_requote,"real_cleanup_completed":complete,"ticks":x.world.sim_tick})

func _case_67(t) -> void:
	var x: Dictionary = _fixture({"unassigned":"doctor"})
	var room: String = _room(x)
	_facility(x,"blocked_bed","SE04",[40,70],room)
	var target: Array = x.space.facility_layout(x.world,"blocked_bed").patient_cell
	var visitor: Dictionary = _visit(x,"temporary_body",target)
	x.world.touch()
	x.w.ensure(x.world)
	var initially_blocked: bool = x.w.personal_beds.bed_for(x.world,"unassigned").is_empty()
	var geometry: int = x.world.geometry_revision
	var moved: String = x.space.request_move(x.world,visitor.actor_id,1,[53,83])
	for tick: int in 300:
		if not x.world.facts.moves.has(visitor.actor_id): break
		x.world.facts.sim_tick += 1
		x.space.advance(x.world)
		x.world.touch(false)
	x.w.ensure(x.world)
	var assigned: bool = x.w.personal_beds.bed_for(x.world,"unassigned")=="blocked_bed"
	t.check("STAFF-67",initially_blocked and moved.is_empty() and not x.world.facts.moves.has(visitor.actor_id) and geometry==x.world.geometry_revision and assigned,{"initially_blocked":initially_blocked,"real_move":moved,"geometry_unchanged":geometry==x.world.geometry_revision,"assigned_after_actual_body_left":assigned,"owners":x.world.facts.staff_life.personal_beds})

func _case_68(t) -> void:
	var checks: Array = []
	for kind: String in ["gp","surgery"]:
		var x: Dictionary = _areas()
		_facility(x,"toilet","FUR07",[39,68],"west")
		x.world.touch()
		var visit: Dictionary = _visit(x,"clinical_pause_"+kind,[38,73])
		if kind!="gp": x.c._retarget_ticket(x.world,visit,kind)
		var ticket_id: String = str(visit.ticket_id)
		x.world.facts.sim_tick = 1800
		x.l._begin_need(x.world,visit)
		for tick: int in 200:
			if x.world.facts.waiting_life.needs.get(visit.id,{}).get("phase","")=="using": break
			_tick_waiting(x)
		var using: bool = x.world.facts.waiting_life.needs.get(visit.id,{}).get("phase","")=="using"
		var probe: ClinicalSelectionProbe = ClinicalSelectionProbe.new(_content,x.space)
		probe.dispatch(x.world)
		var skipped_using: bool = probe.selections==0 and int(x.world.facts.tickets[ticket_id].get("called_tick",-1))<0
		for tick: int in 100:
			if x.world.facts.waiting_life.needs.get(visit.id,{}).get("phase","")=="returning": break
			_tick_waiting(x)
		var returning: bool = x.world.facts.waiting_life.needs.get(visit.id,{}).get("phase","")=="returning" and x.world.facts.moves.has(visit.actor_id)
		probe.dispatch(x.world)
		var skipped_returning: bool = probe.selections==0
		for tick: int in 250:
			if not x.world.facts.waiting_life.needs.has(visit.id): break
			_tick_waiting(x)
		probe.dispatch(x.world)
		checks.append({"kind":kind,"actual_using":using,"no_selection_while_using":skipped_using,"actual_return_journey":returning,"no_selection_while_returning":skipped_returning,"selection_resumed_once_after_real_return":probe.selections==1,"same_original_ticket":visit.ticket_id==ticket_id})
	t.check("STAFF-68",checks.all(func(row: Dictionary)->bool: return row.actual_using and row.no_selection_while_using and row.actual_return_journey and row.no_selection_while_returning and row.selection_resumed_once_after_real_return and row.same_original_ticket),{"real_life_handoff":checks})
