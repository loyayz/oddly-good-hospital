extends "res://tests/acceptance/guidance_nurse_local_release.gd"

const LOCAL_CASES: Array[String]=["safe_release_collision","amenity_walk","fixed_clinical","seated_use","convoy"]
const PROBE: String="a_retreat"

# Observe production decisions and MotionResults. No decision, contact,
# return connector or actual movement is supplied by this observer.
class ObserveMovement extends HospitalMovement:
	var watched: String
	var contacts: Array=[]
	var choices: Array=[]
	var eligibility: Array=[]
	func _init(owner: HospitalSpace, id: String) -> void:
		super(owner)
		watched=id
	func _move_step(world: WorldState, actor: Dictionary, movement: Dictionary, segment: Dictionary) -> MotionResult:
		var result: MotionResult=super._move_step(world,actor,movement,segment)
		if actor.id==PROBE and result.blocked:
			contacts.append({"tick":world.sim_tick,"requested":[result.requested_motion.x,result.requested_motion.y],"actual":[result.actual_motion.x,result.actual_motion.y],"body_blockers":Array(result.blocker_actor_ids),"reservations":Array(result.reservation_ids),"static_reason":result.static_reason})
		return result
	func _local_movable(world: WorldState, actor: Dictionary, journey: Dictionary) -> bool:
		var result: bool=super._local_movable(world,actor,journey)
		if actor.id==watched: eligibility.append({"tick":world.sim_tick,"movable":result,"posture":actor.posture,"has_ground_move":_local_floor_segment(actor,journey),"convoy":journey.has("convoy")})
		return result
	func _local_choose_options(world: WorldState, actor: Dictionary, movement: Dictionary, motion: Vector2, fixed: Array) -> bool:
		if actor.id!=watched: return super._local_choose_options(world,actor,movement,motion,fixed)
		var before: Dictionary=movement.duplicate(true)
		var body: Dictionary=actor.duplicate(true)
		var staff: Dictionary=world.facts.staff.get(watched,{}).duplicate(true)
		var releases: Dictionary=world.facts.floor_guidance.releases.duplicate(true)
		var reservations: Dictionary=world.facts.adaptations.duplicate(true)
		var tickets: Dictionary=world.facts.tickets.duplicate(true)
		var result: bool=super._local_choose_options(world,actor,movement,motion,fixed)
		var after: Dictionary=movement.duplicate(true)
		before.erase("local_move"); after.erase("local_move")
		choices.append({"tick":world.sim_tick,"accepted":result,"local":movement.get("local_move",{}).duplicate(true),"original_move_unchanged":before==after,"body_not_moved_by_choice":body==actor,"staff_owner_unchanged":staff==world.facts.staff.get(watched,{}),"release_owner_unchanged":releases==world.facts.floor_guidance.releases,"reservations_unchanged":reservations==world.facts.adaptations,"clinical_tickets_unchanged":tickets==world.facts.tickets})
		return result

func run_local(database: HospitalContent, selected: Array = []) -> Dictionary:
	content=database
	var rows: Array=[]
	for name: String in LOCAL_CASES:
		if not selected.is_empty() and not name in selected: continue
		var started: int=Time.get_ticks_usec()
		var row: Dictionary
		match name:
			"safe_release_collision": row=_walking_need(true)
			"amenity_walk": row=_walking_need(false)
			"fixed_clinical": row=_fixed_clinical()
			"seated_use": row=_seated_use()
			"convoy": row=_convoy()
		row.case=name; row.elapsed_ms=float(Time.get_ticks_usec()-started)/1000.0
		rows.append(row)
	return {"ok":not rows.is_empty() and rows.all(func(row: Dictionary)->bool:return row.ok),"cases":rows,"scope":"Actual collision and complete original obligations from legal pre-contact boundaries. A declared pending retreat is input, never evidence of an earlier completed move. No synthetic MotionResult or forced navigation result."}

func _actor_input(x: Dictionary, id: String, point: Vector2, floor_id: int = 1) -> void:
	x.world.facts.actors[id]={"id":id,"name":id,"species_id":"S49","location":{"kind":"floor","floor_id":floor_id,"cell":[point.x,point.y],"height_m":0.0},"facing":0.0,"posture":"standing"}
	x.world.touch()
	x.sim.space.sync_actor(x.world,id)

# The independent actor starts at a declared pending-retreat boundary.
# The original route and request sequence come from the real owner. Only
# the unexecuted local intention is input; every collision is real.
func _retreat_input(x: Dictionary, point: Vector2, outward: Vector2, inward_distance: float = 1.0) -> bool:
	_actor_input(x,PROBE,point)
	var actor: Dictionary=x.world.facts.actors[PROBE]
	if not x.sim.space.navigation.structural_clearance(x.world,actor,1).position_reason(point).is_empty() or not x.sim.space._dynamic_clear(x.world,PROBE,1,x.sim.space.body_rectangle(actor),[PROBE],false,true):
		x.probe_error="Initial retreat body is not legally clear"; return false
	var goal: Vector2=point+outward*2.0
	x.probe_goal=[goal.x,goal.y]
	var reason: String=x.sim.space.request_move(x.world,PROBE,1,x.probe_goal)
	if not reason.is_empty(): x.probe_error=reason; return false
	x.sim.space.movement._dispatch_routes(x.world,x.world.present_actor_count())
	var move: Dictionary=x.world.facts.moves.get(PROBE,{})
	if move.get("route_pending",false) or move.get("path",[]).is_empty(): x.probe_error="Retreat input did not receive a real original route"; return false
	var target: Vector2=point-outward*inward_distance
	move.local_move={"origin":[point.x,point.y],"target":{"kind":"floor","floor_id":1,"cell":[target.x,target.y]},"retreat":true}
	x.world.facts.actors[PROBE].facing=atan2(-outward.x,-outward.y)
	x.sim.space.sync_actor(x.world,PROBE)
	x.world.touch(false)
	return true

func _observe(x: Dictionary, id: String) -> ObserveMovement:
	var observer:=ObserveMovement.new(x.sim.space,id)
	x.sim.space.movement=observer
	return observer

func _choice_ok(observer: ObserveMovement) -> bool:
	return observer.choices.any(func(row: Dictionary)->bool:return row.accepted and row.original_move_unchanged and row.body_not_moved_by_choice and row.staff_owner_unchanged and row.release_owner_unchanged and row.reservations_unchanged and row.clinical_tickets_unchanged)

func _probe_touched(observer: ObserveMovement, id: String) -> bool:
	return observer.contacts.any(func(row: Dictionary)->bool:return id in row.body_blockers)

func _clear_probe(x: Dictionary) -> bool:
	# A later independent movement command clears the probe after the tested
	# encounter. The protected body's goal and ownership never change.
	var goal: Array=x.probe_goal.duplicate()
	return x.sim.space.cancel_ground_move(x.world,PROBE) and x.sim.space.request_move(x.world,PROBE,1,goal).is_empty()

func _walking_need(releasing: bool) -> Dictionary:
	var x: Dictionary=_input("landing") if releasing else _base()
	var id: String=NURSE if releasing else "amenity_employee"
	if not releasing:
		x.checks.water=_facility(x,"water","FUR17",[37,82])
		var layout: Dictionary=x.sim.space.facility_layout(x.world,"water")
		var point: Vector2=ConvoyTrail.point(layout.patient_cell)+Vector2(6,0)
		_staff(x,id,"cleaner",[point.x,point.y])
	var original: Dictionary=x.world.facts.actors[id].location.duplicate(true)
	var start: Vector2=ConvoyTrail.point(original.cell)
	x.checks.actual_probe_route=_retreat_input(x,start+Vector2(0.6,0),Vector2.RIGHT)
	x.checks.need_accepted=x.sim.services.wellbeing.begin_amenity(x.world,id,"water")
	if releasing:
		x.sim.services.floor_guidance._assign_desks(x.world)
		x.sim.services.floor_guidance._release_nurses(x.world)
	else: x.sim.services.wellbeing.dispatch(x.world)
	x.sim.space.movement._dispatch_routes(x.world,x.world.present_actor_count())
	var move: Dictionary=x.world.facts.moves.get(id,{})
	x.checks.real_need_walk=not move.is_empty() and x.sim.space.movement._local_floor_segment(x.world.facts.actors[id],move)
	x.checks.release_owned_before_collision=not releasing or x.world.facts.floor_guidance.releases.has(id) and x.world.facts.staff[id].active_job_id=="floor_desk_release:"+DESK and x.world.facts.staff[id].life_task.phase=="wait_safe"
	x.checks.legal_precontact=x.world.validate(content).is_empty()
	var original_release: Dictionary=x.world.facts.floor_guidance.releases.get(id,{}).duplicate(true)
	if not x.checks.values().all(func(value: Variant)->bool:return value==true): return _finish(x,{"probe_error":x.get("probe_error",""),"reason":"Walking prerequisite failed","move":move.duplicate(true),"release":original_release})
	var observer: ObserveMovement=_observe(x,id)
	var release_point: Dictionary={}
	var release_walks: int=0
	var water_ticks: int=0
	var finished: bool=false
	var cleared: bool=false
	var original_goal: Dictionary={"floor":move.get("target_floor",0),"cell":move.get("target_cell",[]).duplicate(),"sequence":move.get("request_sequence",-1)}
	x.checks.release_only_after_safe_walk=true
	x.checks.water_at_real_facility=true
	x.checks.original_work_segment=true
	var errors: Array=[]
	for tick: int in 1800:
		var task: Dictionary=x.world.facts.staff[id].life_task.duplicate(true)
		var previous: Dictionary=x.world.facts.actors[id].location.duplicate(true)
		var had_release: bool=x.world.facts.floor_guidance.releases.has(id)
		_step(x)
		var staff: Dictionary=x.world.facts.staff[id]
		var actor: Dictionary=x.world.facts.actors[id]
		var current: Dictionary=staff.life_task
		var validation: String=x.world.validate(content)
		if not validation.is_empty(): errors.append({"tick":x.world.sim_tick,"validation":validation}); break
		if _probe_touched(observer,id) and not cleared: cleared=_clear_probe(x)
		if had_release:
			if previous!=actor.location: release_walks+=1
			if not x.world.facts.floor_guidance.releases.has(id):
				release_point=actor.location.duplicate(true)
				var prior: Rect2=Rect2(ConvoyTrail.point(original_release.cell),Vector2.ONE*int(original_release.clearance))
				x.checks.release_only_after_safe_walk=x.checks.release_only_after_safe_walk and release_walks>0 and actor.location.kind=="floor" and int(actor.location.floor_id)==1 and not x.sim.space.body_rectangle(actor).intersects(prior,false) and x.sim.space.public_areas.safe_wait(x.world,id,1,actor.location.cell)
		if releasing: x.checks.original_work_segment=x.checks.original_work_segment and staff.base_prepared and staff.get("base_task",{}).is_empty() and int(staff.last_rest_end_tick)==int(x.before_rest)
		var worked: int=0
		if task.get("phase","")=="using": worked=int(task.remaining_ticks)-int(current.get("remaining_ticks",0))
		elif current.get("phase","")=="using": worked=80-int(current.remaining_ticks)
		if worked>0:
			water_ticks+=worked
			var facility_id: String=str(task.get("facility_id",current.get("facility_id","")))
			if facility_id.is_empty(): facility_id=str(current.get("facility_id",""))
			var used: Dictionary=x.sim.space.facility_layout(x.world,facility_id)
			x.checks.water_at_real_facility=x.checks.water_at_real_facility and worked==1 and not used.is_empty() and x.sim.space.at(x.world,id,int(used.get("floor_id",0)),used.get("patient_cell",[]))
		var returned: bool=x.sim.space.at(x.world,id,2,x.sim.space.guidance_operator_cell(x.world,DESK,id)) and staff.active_job_id=="floor_desk:"+DESK if releasing else actor.location==original
		if water_ticks==80 and current.phase=="idle" and returned and not x.world.facts.moves.has(id): finished=true; break
	x.checks.actual_body_contact=_probe_touched(observer,id)
	x.checks.walking_blocker_can_yield=observer.eligibility.any(func(row: Dictionary)->bool:return row.movable)
	x.checks.actual_local_intention_keeps_all_owners=_choice_ok(observer)
	x.checks.real_release_completed=not releasing or release_walks>0 and not release_point.is_empty() and not x.world.facts.floor_guidance.releases.has(id)
	x.checks.full_eight_seconds_and_real_return=water_ticks==80 and finished
	x.checks.no_validation_errors=errors.is_empty()
	x.checks.no_extra_clinical_work=x.world.facts.sessions.is_empty() and x.world.facts.attempts.is_empty() and x.world.facts.preparations.is_empty()
	if releasing: x.checks.no_extra_charge_or_supply=_accounts_unchanged(x)
	return _finish(x,{"input_goal":original_goal,"probe_error":x.get("probe_error",""),"water_work_ticks":water_ticks,"release_walk_steps":release_walks,"release_point":release_point,"observed_contacts":observer.contacts,"observed_choices":observer.choices,"observed_eligibility":observer.eligibility,"errors":errors})

# Choose an unoccupied physical point outside current service reservations.
# The pending local leg meets those real protections. The fixed user never
# receives a fabricated Move or a body placed inside its service.
func _approach_fixed(x: Dictionary, id: String) -> bool:
	var origin: Vector2=ConvoyTrail.point(x.world.facts.actors[id].location.cell)
	var sample: Dictionary={"id":PROBE,"species_id":"S49","posture":"standing","facing":0.0,"location":{"kind":"floor","floor_id":1,"cell":[origin.x,origin.y],"height_m":0.0}}
	var query: RouteClearance=x.sim.space.navigation.structural_clearance(x.world,sample,1)
	for direction: Vector2 in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP]:
		for distance: float in [1.2,1.5,2.0,2.5]:
			var point: Vector2=origin+direction*distance
			var goal: Vector2=point+direction*2.0
			if not query.position_reason(point).is_empty() or not query.sweep_reason(point,goal).is_empty(): continue
			if not x.sim.space._dynamic_clear(x.world,PROBE,1,x.sim.space._actor_rect(sample,point),[PROBE],false,true): continue
			return _retreat_input(x,point,direction,distance)
	x.probe_error="No legal unoccupied approach to the fixed body"
	return false

func _fixed_clinical() -> Dictionary:
	var x: Dictionary=_base()
	x.checks.room=_room(x,"gp","gp",[34,66]) and _facility(x,"desk","FUR02",[38,69],"gp")
	_staff(x,"doctor","doctor",[55,90],"gp")
	var visit: Dictionary=_patient(x,"fixed_work",[38,79])
	_arranged(x,visit,"desk")
	for tick: int in 700:
		_step(x)
		if not x.world.facts.sessions.is_empty(): break
	var session: Dictionary=x.world.facts.sessions.values()[0].duplicate(true) if not x.world.facts.sessions.is_empty() else {}
	x.checks.real_clinical_started=not session.is_empty()
	if session.is_empty(): return _finish(x,{"reason":"Clinical prerequisite did not start"})
	x.checks.legal_approach=_approach_fixed(x,"doctor")
	x.checks.legal_precontact=x.world.validate(content).is_empty()
	if not x.checks.values().all(func(value: Variant)->bool:return value==true): return _finish(x,{"probe_error":x.get("probe_error",""),"reason":"Fixed clinical prerequisite failed"})
	var observer: ObserveMovement=_observe(x,"doctor")
	var original: Dictionary=x.world.facts.actors.doctor.duplicate(true)
	var reservation: Dictionary=x.world.facts.adaptations.get("desk",{}).duplicate(true)
	x.checks.real_fixed_body_not_movable=not observer._local_movable(x.world,x.world.facts.actors.doctor,x.world.facts.moves.get("doctor",{}))
	x.checks.original_post_and_reservation_retained=not reservation.is_empty()
	x.checks.original_session_commitment_retained=true
	var promise: Dictionary=session.duplicate(true)
	promise.erase("remaining_ticks")
	var contact: bool=false
	var cleared: bool=false
	for tick: int in 500:
		_step(x)
		contact=contact or not observer.contacts.is_empty()
		if contact and not cleared: cleared=_clear_probe(x)
		if not x.world.facts.sessions.has(session.get("id","")): break
		x.checks.original_post_and_reservation_retained=x.checks.original_post_and_reservation_retained and x.world.facts.actors.doctor.location==original.location and x.world.facts.actors.doctor.posture==original.posture and not x.world.facts.moves.has("doctor") and x.world.facts.adaptations.get("desk",{})==reservation
		var current: Dictionary=x.world.facts.sessions[session.id].duplicate(true)
		current.erase("remaining_ticks")
		x.checks.original_session_commitment_retained=x.checks.original_session_commitment_retained and current==promise
	x.checks.actual_rejected_approach=contact
	x.checks.fixed_post_not_selected=observer.choices.is_empty()
	x.checks.original_clinical_completed=not session.is_empty() and not x.world.facts.sessions.has(session.id) and int(x.events.get("service_completed",0))==1
	x.checks.one_original_charge=x.world.facts.ledger.entries.has(visit.id+":gp") and x.world.facts.ledger.entries.has(visit.id+":consultation") and x.sim.services.experience.receipt(x.world,visit.id).charges.size()==2
	return _finish(x,{"original_session":session,"probe_error":x.get("probe_error",""),"observed_contacts":observer.contacts,"observed_choices":observer.choices})

func _seated_use() -> Dictionary:
	var x: Dictionary=_base()
	x.checks.room=_room(x,"gp","gp",[34,66]) and _facility(x,"desk","FUR02",[38,69],"gp")
	x.checks.chair=_facility(x,"chair","FUR09",[44,76])
	_staff(x,"doctor","doctor",[55,90],"gp")
	var first: Dictionary=_patient(x,"first_gp",[38,79])
	# A lawful slower explanation is input before the original GP starts.
	# Its real Session creates the queue, without a synthetic staff lock.
	first.expression="off_topic"
	_arranged(x,first,"desk")
	for tick: int in 700:
		_step(x)
		if not x.world.facts.sessions.is_empty(): break
	var session_id: String=str(x.world.facts.sessions.keys()[0]) if not x.world.facts.sessions.is_empty() else ""
	x.checks.first_real_gp=not session_id.is_empty()
	if session_id.is_empty(): return _finish(x,{"reason":"Original GP did not start"})
	var visit: Dictionary=_patient(x,"fixed_seat",[44,79])
	_arranged(x,visit,"desk",true)
	x.checks.manual_seat_request=x.sim.services.waiting.execute(x.world,"waiting_select_seat",{"visit_id":visit.id,"facility_id":"chair"}).accepted
	for tick: int in 600:
		_step(x)
		if HospitalWaitingLife.is_seated(x.world,visit.id): break
	x.checks.actually_seated=HospitalWaitingLife.is_seated(x.world,visit.id)
	if not x.checks.actually_seated: return _finish(x,{"reason":"Real seating prerequisite did not finish","seat":x.world.facts.waiting_life.seats.get(visit.id,{}).duplicate(true),"visit":visit.duplicate(true),"guidance":x.sim.services.floor_guidance.state(x.world,visit.id).duplicate(true)})
	x.checks.legal_approach=_approach_fixed(x,visit.actor_id)
	x.checks.legal_precontact=x.world.validate(content).is_empty()
	if not x.checks.values().all(func(value: Variant)->bool:return value==true): return _finish(x,{"probe_error":x.get("probe_error",""),"reason":"Seated prerequisite failed"})
	var observer: ObserveMovement=_observe(x,visit.actor_id)
	var original: Dictionary=x.world.facts.actors[visit.actor_id].duplicate(true)
	var reservation: Dictionary=x.world.facts.adaptations.get("chair",{}).duplicate(true)
	var ticket: String=visit.ticket_id
	var before_use: int=int(x.world.facts.waiting_life.seats.get(visit.id,{}).get("continuous_ticks",0))
	x.checks.actual_seated_body_not_movable=not observer._local_movable(x.world,x.world.facts.actors[visit.actor_id],x.world.facts.moves.get(visit.actor_id,{}))
	x.checks.seat_support_owner_and_ticket_retained=not reservation.is_empty()
	var cleared: bool=false
	var actual_use_ticks: int=0
	for tick: int in 25:
		_step(x)
		if not observer.contacts.is_empty() and not cleared: cleared=_clear_probe(x)
		x.checks.seat_support_owner_and_ticket_retained=x.checks.seat_support_owner_and_ticket_retained and HospitalWaitingLife.is_seated(x.world,visit.id) and x.world.facts.actors[visit.actor_id].location==original.location and x.world.facts.actors[visit.actor_id].support_facility_id=="chair" and visit.ticket_id==ticket and x.world.facts.adaptations.get("chair",{})==reservation
		if HospitalWaitingLife.is_seated(x.world,visit.id) and x.world.facts.actors[visit.actor_id].location==original.location and x.world.facts.adaptations.get("chair",{})==reservation: actual_use_ticks+=1
	x.checks.actual_rejected_approach=not observer.contacts.is_empty()
	x.checks.fixed_seat_not_selected=observer.choices.is_empty()
	# FUR09 has no calming effect. continuous_ticks is the FUR49 effect
	# clock, not a universal seated-use clock; observe every real use boundary.
	x.checks.real_continuous_use=actual_use_ticks==25 and int(x.world.facts.waiting_life.seats.get(visit.id,{}).get("continuous_ticks",0))==before_use
	x.checks.normal_refer=x.sim.clinic.execute(x.world,"clinical_refer",{"visit_id":visit.id}).accepted
	for tick: int in 1500:
		_step(x)
		if x.world.facts.actors[visit.actor_id].location.kind=="outside" and not x.world.facts.sessions.has(session_id): break
	x.checks.real_safe_exit_and_release=x.world.facts.actors[visit.actor_id].location.kind=="outside" and not x.world.facts.moves.has(visit.actor_id) and not x.world.facts.adaptations.has("chair") and not x.world.facts.waiting_life.seats.has(visit.id)
	x.checks.original_gp_completed=not x.world.facts.sessions.has(session_id) and x.world.facts.ledger.entries.has(first.id+":gp")
	return _finish(x,{"probe_error":x.get("probe_error",""),"actual_seated_use_ticks":actual_use_ticks,"observed_contacts":observer.contacts,"observed_choices":observer.choices})

func _convoy() -> Dictionary:
	var x: Dictionary=_base()
	_actor_input(x,"leader",Vector2(40,84))
	_actor_input(x,"follower",Vector2(38,84))
	x.world.facts.actors.leader.facing=PI/2.0
	x.world.facts.actors.follower.facing=PI/2.0
	x.sim.space.sync_actor(x.world,"leader"); x.sim.space.sync_actor(x.world,"follower")
	x.checks.real_group_request=x.sim.space.request_group_move(x.world,"leader",["leader","follower"],{},1,[46,84]).is_empty()
	x.sim.space.movement._dispatch_routes(x.world,x.world.present_actor_count())
	x.checks.probe_route=_retreat_input(x,Vector2(41.2,84),Vector2.RIGHT,1.2)
	x.checks.legal_precontact=x.world.validate(content).is_empty()
	if not x.checks.values().all(func(value: Variant)->bool:return value==true): return _finish(x,{"probe_error":x.get("probe_error",""),"reason":"Group prerequisite failed"})
	var move: Dictionary=x.world.facts.moves.get("leader",{})
	var sequence: int=int(move.get("request_sequence",-1))
	var observer: ObserveMovement=_observe(x,"leader")
	x.checks.actual_group_not_independently_movable=not observer._local_movable(x.world,x.world.facts.actors.leader,move) and not observer._local_movable(x.world,x.world.facts.actors.follower,x.world.facts.moves.get("follower",{}))
	x.checks.original_group_and_order=true
	x.checks.no_individual_displacement=true
	var cleared: bool=false
	var errors: Array=[]
	for tick: int in 700:
		_step(x)
		if _probe_touched(observer,"leader") and not cleared: cleared=_clear_probe(x)
		move=x.world.facts.moves.get("leader",{})
		var validation: String=x.world.validate(content)
		if not validation.is_empty(): errors.append({"tick":x.world.sim_tick,"validation":validation}); break
		x.checks.no_individual_displacement=x.checks.no_individual_displacement and not x.world.facts.moves.has("follower") and not move.has("local_move")
		if move.is_empty(): break
		x.checks.original_group_and_order=x.checks.original_group_and_order and move.get("members",[])==["leader","follower"] and move.has("convoy") and int(move.request_sequence)==sequence and int(move.target_floor)==1 and move.target_cell==[46,84]
	x.checks.actual_body_contact=_probe_touched(observer,"leader")
	x.checks.members_not_selected=observer.choices.is_empty()
	x.checks.real_group_arrival=not x.world.facts.moves.has("leader") and x.sim.space.at(x.world,"leader",1,[46,84]) and x.world.facts.actors.follower.location.kind=="floor"
	x.checks.no_validation_errors=errors.is_empty()
	return _finish(x,{"probe_error":x.get("probe_error",""),"observed_contacts":observer.contacts,"observed_choices":observer.choices,"errors":errors})
