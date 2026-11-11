extends "res://tests/acceptance/floor_guidance.gd"

# Calculation inputs are assembled before operation. Motion cases execute real
# 0.1-second advances; no location/cursor/work edits occur after the request.
func run_friend_cases(database: HospitalContent, output_prefix: String) -> Dictionary:
	_content = database
	var rows: Array = []
	for kind: String in ["idle","own_move","convoy","foreign_floor","outside","clinical","visitor_waiting","visitor_leaving"]:
		rows.append(_friend_case(kind,output_prefix))
	return {"ok":rows.all(func(row: Dictionary)->bool:return row.ok),"cases":rows}

func _friend_case(kind: String, prefix: String) -> Dictionary:
	var x: Dictionary = _base(kind=="clinical",kind=="foreign_floor")
	var observer: Dictionary = _visit(x,"observer",[40,90],"PP04")
	var friend: Dictionary
	if kind.begins_with("visitor_"):
		friend = {"id":"friend","actor_id":"relative_friend"}
		x.world.facts.actors[friend.actor_id] = {"id":friend.actor_id,"name":"亲友","species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":[44,90],"height_m":0.0},"facing":0.0,"posture":"standing"}
	else:
		friend = _visit(x,"friend",[44,90] if kind=="idle" else [42,88])
	_facility(x,"friend_chair","FUR09",[42,89])
	if kind=="convoy": _visit(x,"leader",[44,88])
	if kind=="foreign_floor": x.world.facts.actors[friend.actor_id].location.floor_id = 2
	if kind=="outside":
		x.world.facts.actors[friend.actor_id].location = {"kind":"outside"}
		x.world.facts.tickets.erase(friend.ticket_id);friend.ticket_id="";friend.phase="departed"
	if kind.begins_with("visitor_"):
		_inpatient_relative_input(x,friend.actor_id,"waiting" if kind=="visitor_waiting" else "leaving")
	if kind=="clinical":
		# Legal pre-operation ready-at-station input. This tests dispatch into
		# actual GP ownership, not how the patient or doctor arrived here.
		var layout: Dictionary = x.space.facility_layout(x.world,"diagnosis")
		x.world.facts.actors[friend.actor_id].location.cell = layout.patient_cell.duplicate()
		x.world.facts.actors.doctor.location.cell = layout.operator_cells[0].duplicate()
		# This fixture uses the clinical boundary directly, before floor guidance
		# is configured. No guidance completion is asserted.
		x.c.floor_guidance = null
	var pair: Array = [observer.actor_id,friend.actor_id];pair.sort()
	x.world.facts.get_or_add("relationships",{})[":".join(pair)] = {"kind":"friend"}
	x.world.touch()
	var input_validation: String = x.world.validate(_content)
	FileAccess.open(prefix+"-"+kind+"-input.bin",FileAccess.WRITE).store_var(x.world.freeze(),true)
	var start: Dictionary = x.world.facts.actors[friend.actor_id].location.duplicate(true)
	var request: String = ""
	var moved: bool = false
	var clinical_started: bool = false
	if kind=="own_move": request = x.space.request_move(x.world,friend.actor_id,1,[54,88])
	if kind=="convoy": request = x.space.request_group_move(x.world,"patient_leader",["patient_leader",friend.actor_id],{},1,[54,88])
	if kind in ["own_move","convoy"]:
		for i: int in 4:
			x.space.advance(x.world);x.world.facts.sim_tick+=1;x.world.touch(false)
		moved = start!=x.world.facts.actors[friend.actor_id].location
	if kind=="clinical":
		x.c.dispatch(x.world)
		for session: Dictionary in x.world.facts.sessions.values():
			if session.visit_id==friend.id and session.kind=="gp": clinical_started=true
	var before: Dictionary = x.world.freeze()
	var quote: Dictionary = x.l._seat_quote(x.world,observer,"friend_chair")
	var actor: Dictionary = x.world.facts.actors[friend.actor_id]
	var eligible: bool = actor.location.kind=="floor" and x.l._idle_public_friend(x.world,actor)
	var observed_end: Dictionary = actor.location.duplicate(true)
	var no_own_convoy_record: bool = kind=="convoy" and not x.world.facts.moves.has(friend.actor_id) and x.world.facts.moves.get("patient_leader",{}).has("convoy")
	var unchanged: bool = before==x.world.freeze()
	var validation: String = x.world.validate(_content)
	var expected: bool = kind in ["idle","visitor_waiting"]
	var ok: bool = input_validation.is_empty() and validation.is_empty() and quote.get("ok",false) and quote.get("conditions",{}).get("friendly_neighbor",not expected)==expected and unchanged and request.is_empty()
	if kind in ["own_move","convoy"]: ok = ok and moved and not eligible
	if kind=="clinical": ok = ok and clinical_started and not eligible
	if kind=="convoy": ok = ok and no_own_convoy_record
	FileAccess.open(prefix+"-"+kind+"-result.bin",FileAccess.WRITE).store_var(x.world.freeze(),true)
	var arrived_idle: bool = false
	var restored_moving_excluded: bool = false
	if kind in ["own_move","convoy"]:
		var restored: Dictionary = _guide_bind(WorldState.new(x.world.freeze()))
		restored_moving_excluded = not restored.l._idle_public_friend(restored.world,restored.world.facts.actors[friend.actor_id])
		_dispose(restored)
		for i: int in 150:
			x.space.advance(x.world);x.world.facts.sim_tick+=1;x.world.touch(false)
			if x.world.facts.moves.is_empty(): break
		arrived_idle = x.world.facts.moves.is_empty() and x.l._idle_public_friend(x.world,x.world.facts.actors[friend.actor_id])
		ok = ok and restored_moving_excluded and arrived_idle and x.world.validate(_content).is_empty()
		FileAccess.open(prefix+"-"+kind+"-arrived.bin",FileAccess.WRITE).store_var(x.world.freeze(),true)
	var result: Dictionary = {"case":kind,"ok":ok,"input_validation":input_validation,"validation":validation,"quote":quote,"expected_friend":expected,"eligible_idle_public":eligible,"read_only":unchanged,"actual_motion":moved,"restored_moving_excluded":restored_moving_excluded,"actual_arrival_idle":arrived_idle,"request":request,"clinical_started_by_dispatch":clinical_started,"start":start,"observed_end":observed_end,"final_location":actor.location.duplicate(true),"convoy_follower_has_no_own_record":no_own_convoy_record,"sessions":x.world.facts.sessions.duplicate(true)}
	_dispose(x)
	return result

# This downstream seating case starts with lawful inpatient-family history.
# It does not assert that any preceding admission or family walk has occurred.
func _inpatient_relative_input(x: Dictionary, relative_id: String, phase: String) -> void:
	var fixture: RefCounted=load("res://tests/acceptance/clinical_fixtures.gd").new()
	fixture._content=_content
	fixture._add_layout(x.world,"ward_two_beds","friend_ward",[45,65])
	fixture._add_worker(x.world,"friend_cover","nurse",[46,72],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":0},"DT01","friend_ward")
	fixture._add_worker(x.world,"friend_host_doctor","doctor",[54,88],"outpatient",{"diagnosis":2,"treatment":2,"care":0,"surgery":0})
	x.world.facts.staff.friend_cover.base_prepared=true
	for research: Dictionary in _content.catalog.research:
		if not research.id in x.world.facts.research: x.world.facts.research.append(research.id)
	var actor_id: String="friend_host"
	x.world.facts.actors[actor_id]={"id":actor_id,"name":"住院亲属","species_id":"S49","body_binding_id":"B_S49_D23_M23","location":{"kind":"floor","floor_id":1,"cell":[47,67],"height_m":0.0},"facing":0.0,"posture":"standing"}
	var visit_id: String="friend_host_visit"
	var visit: Dictionary={"id":visit_id,"actor_id":actor_id,"disease_id":"D23","binding_id":"B_S49_D23_M23","requested_plan_id":"P_D23_SURGERY","expression":"clear","personality_id":"PP01","anger":0.0,"phase":"wait_surgery","diagnosis":preload("res://tests/acceptance/clinical_input.gd").diagnosed("friend_host_doctor","completed_gp_station"),"attempt_ids":[],"plan_decision":{"plan_id":"P_D23_SURGERY","source":"director","doctor_id":"friend_host_doctor","revision":1,"probability_bp":9600,"expected_team":[]},"complex":false,"final_result":"","waiting_reason":"","ticket_id":"friend_host_ticket","doctor_fee_quote":20,"arrived_tick":x.world.sim_tick,"arrival_key":visit_id,"last_progress_tick":x.world.sim_tick,"last_service_tick":x.world.sim_tick}
	x.world.facts.visits[visit_id]=visit
	x.world.register_visit(visit_id)
	x.world.facts.arrival_receipts[visit_id]=visit_id
	x.world.facts.tickets[visit.ticket_id]={"id":visit.ticket_id,"visit_id":visit_id,"kind":"surgery","enqueued_tick":x.world.sim_tick}
	var ward: Dictionary={"id":"friend_host_stay","visit_id":visit_id,"attempt_id":"","bed_id":"friend_ward_0","phase":"waiting_surgery","remaining_ticks":0,"work_credit_milli":0,"care_completed":false,"nurse_id":"friend_cover","escort_id":"friend_cover","last_progress_tick":x.world.sim_tick,"admitted_tick":x.world.sim_tick,"companion_evaluated":true,"companion_qualified":true,"companion_actor_id":relative_id,"visitor_day":x.world.sim_tick/WorldState.TICKS_PER_DAY,"visitor_intent":false,"visitor_requested":false}
	x.world.facts.ward_stays[ward.id]=ward
	assert(x.space.reserve_facility(x.world,ward.bed_id,actor_id,ward.id,[ward.nurse_id]).is_empty())
	x.c._support(x.world,visit,x.space.facility_layout(x.world,ward.bed_id),"lying")
	x.world.facts.actors[relative_id].relative_of=actor_id
	x.world.facts.visitors.stays["relative"]={"id":"relative","visit_id":visit_id,"actor_id":relative_id,"purpose":"companion","phase":phase,"remaining_ticks":0,"waiting_floor":1,"waiting_cell":[44,90],"life_task":{},"return_ward_first":false,"yielding":false,"next_need_tick":x.world.sim_tick+1800,"next_purpose":"toilet","public_use":{"id":"relative","actor_id":relative_id,"public_purpose":"seat","mode":"auto","area":{},"facility_id":"","arrived_tick":-1,"phase":"away","started_tick":x.world.sim_tick}}
