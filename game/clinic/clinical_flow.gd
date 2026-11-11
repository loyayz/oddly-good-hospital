extends RefCounted

# These operations write the existing Visit/Session owners. There is no
# second clinical clock, random generator or copy of a treatment commitment.
static func diagnosis(visit: Dictionary) -> Dictionary:
	if visit.get("diagnosis",{}).is_empty():
		visit.diagnosis = {"state":"pending","gp_completed":false,"exam_kind":"","exam_completed":false,"review_completed":false,"doctor_id":"","facility_id":""}
	return visit.diagnosis

static func freeze_gp(clinic: HospitalClinic, world: WorldState, visit: Dictionary, staff: Dictionary, facility: Dictionary, data: Dictionary) -> void:
	var progress: Dictionary = diagnosis(visit)
	progress.doctor_id = staff.id
	progress.facility_id = facility.id
	progress.state = "working"
	data.insufficient_bp = int(clinic.content.balance.clinical.diagnosis_insufficient_bp[int(staff.abilities.diagnosis)])
	data.insufficient = world.draw("treatment",10000)<int(data.insufficient_bp)

static func complete_diagnostic(clinic: HospitalClinic, world: WorldState, visit: Dictionary, session: Dictionary) -> void:
	var progress: Dictionary = diagnosis(visit)
	if session.kind=="gp":
		progress.gp_completed = true
		progress.insufficient_bp = int(session.insufficient_bp)
		progress.insufficient = bool(session.insufficient)
		progress.state = "insufficient" if progress.insufficient else "diagnosed"
		if progress.insufficient:
			clinic._queue(world,visit,"examination")
		else:
			choose_plan(clinic,world,visit,str(progress.doctor_id))
	else:
		progress.exam_kind = session.kind
		progress.exam_completed = true
		progress.state = "review_pending"
		clinic._queue(world,visit,"consult")
		continuation_ready(clinic,world,visit)
	if clinic.research!=null: clinic.research.call("record_diagnostic_work",world,visit,str(session.kind))

static func choose_plan(clinic: HospitalClinic, world: WorldState, visit: Dictionary, doctor_id: String) -> bool:
	var selected: Dictionary = clinic._select_plan(world,visit,doctor_id)
	if selected.is_empty():
		if clinic.floor_guidance!=null: clinic.floor_guidance.release(world,visit.id)
		if str(visit.get("ticket_id","")).is_empty(): clinic._queue(world,visit,"plan")
		visit.phase = "wait_plan"
		visit.waiting_reason = "等待医生可选择的合法治疗方案"
		return false
	visit.plan_decision = {"plan_id":selected.plan_id,"source":"doctor","doctor_id":doctor_id,"revision":int(visit.plan_decision.get("revision",0))+1,"reason":"医生依据当前合法方案选择","probability_bp":int(selected.probability_bp),"expected_team":selected.staff_ids.duplicate()}
	var protocol: Dictionary = clinic.content.definition("treatment_protocols",clinic.content.definition("treatment_plans",selected.plan_id).protocol_id)
	clinic._retarget_ticket(world,visit,str(protocol.kind))
	return true

static func reconsider(clinic: HospitalClinic, world: WorldState, visit: Dictionary) -> void:
	var doctor_id: String=str(visit.plan_decision.get("doctor_id",diagnosis(visit).doctor_id))
	release_unadmitted(clinic,world,visit)
	var stay: Dictionary=ward_stay(world,visit.id)
	if not stay.is_empty() and stay.phase=="to_surgery": stay.phase="return_preop"
	clinic._release_preparation(world,visit.id)
	if clinic.floor_guidance!=null: clinic.floor_guidance.release(world,visit.id)
	visit.plan_decision={}
	choose_plan(clinic,world,visit,doctor_id)

static func release_unadmitted(clinic: HospitalClinic, world: WorldState, visit: Dictionary) -> void:
	var stay: Dictionary=ward_stay(world,visit.id)
	if stay.is_empty() or stay.has("admitted_tick"): return
	var held: Dictionary=world.facts.adaptations.get(str(stay.bed_id),{})
	if held.get("owner_id","")==stay.id: held.owner_id=visit.actor_id
	world.facts.ward_stays.erase(stay.id)
	# Any body already walking through a door completes its safe movement.
	# Releasing the admission promise never removes its physical envelope.
	clinic.space.release_adaptations(world)

static func review_ticks(clinic: HospitalClinic, world: WorldState, visit: Dictionary, staff: Dictionary, effective: float) -> int:
	var expression: float = {"clear":1.0,"vague":1.8,"off_topic":2.4}.get(visit.expression,1.0)
	var personality: Dictionary = clinic.content.definition("patient_personalities",visit.personality_id)
	var seconds: float = float(clinic.content.balance.clinical.consult_seconds)*expression*float(personality.speech_multiplier)*(1.0+float(visit.anger)/200.0)
	seconds *= 1.0+float(clinic.content.balance.wellbeing.fatigue_work_multiplier_per_point)*float(staff.fatigue)
	seconds /= (1.0+0.05*(int(staff.abilities.diagnosis)-1)+0.15*effective)*clinic._talent_rate(world,staff.id,"gp",visit)
	return ceili(maxf(4.0,seconds)*10)

static func resolve_doctor(clinic: HospitalClinic, world: WorldState, visit: Dictionary) -> bool:
	var progress: Dictionary = diagnosis(visit)
	var old: Dictionary = world.facts.staff.get(str(progress.doctor_id),{})
	if not old.is_empty() and not old.get("departed",false): return true
	var candidates: Array = []
	for id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[id]
		if staff.get("departed",false) or staff.role!="doctor" or int(staff.abilities.diagnosis)<1: continue
		# A replacement is a qualified employed GP with a legal assignment,
		# not an arbitrary globally optimal treatment chain.
		var rooms: Array = []
		var assignments: Array=staff.get("schedule",[]).duplicate()
		assignments.append_array(staff.get("schedule_overrides",{}).values())
		for facility_id: String in world.facility_ids("FUR02"):
			var facility: Dictionary = world.facts.facilities[facility_id]
			var room: Dictionary=world.facts.rooms.get(str(facility.get("room_id","")),{})
			if room.get("kind","")!="gp" or not clinic.service_room_reason(world,facility).is_empty(): continue
			for assignment: Dictionary in assignments:
				if assignment.get("kind","")=="outpatient" and room.id in assignment.get("pools",[]):
					rooms.append(facility_id)
					break
		if not rooms.is_empty(): candidates.append({"doctor_id":id,"facility_id":rooms[0]})
	if candidates.is_empty():
		visit.waiting_reason = "原医生已离职，等待合格门诊医生接续"
		return false
	var selected: Dictionary = candidates[world.draw("treatment",candidates.size())]
	progress.doctor_id = selected.doctor_id
	progress.facility_id = selected.facility_id
	if clinic.floor_guidance!=null: clinic.floor_guidance.release(world,visit.id)
	return true

static func continuation_ready(clinic: HospitalClinic, world: WorldState, visit: Dictionary) -> bool:
	if not resolve_doctor(clinic,world,visit): return false
	var staff: Dictionary = world.facts.staff[diagnosis(visit).doctor_id]
	if staff.get("on_shift",false): return true
	if not ward_stay(world,visit.id).is_empty():
		visit.waiting_reason="在原病房等待合格医生接续治疗方案"
		return false
	leave_until_return(clinic,world,visit)
	return false

static func leave_until_return(clinic: HospitalClinic, world: WorldState, visit: Dictionary) -> void:
	if visit.has("continuation_complaint"): return
	for session: Dictionary in world.facts.sessions.values():
		if session.visit_id==visit.id: return
	for record: Dictionary in world.facts.get("clinical_suspensions",{}).values():
		if record.visit_id==visit.id: return
	var need: Dictionary=world.facts.get("waiting_life",{}).get("needs",{}).get(visit.id,{})
	if need.get("phase","") in ["using","fallback","returning"]: return
	var plan: Dictionary = visit.get("continuation",{})
	if plan.is_empty():
		# D belongs to actual departure. A long exit journey may cross midnight.
		plan = {"first_day":-1,"return_day":-1,"due_tick":-1,"stage":"leaving","outside_periods":[]}
		visit.continuation = plan
	elif int(plan.return_day)>=int(plan.first_day)+2:
		# The experience owner records the single complaint when the final
		# continuation fails. It is never an extra fine or a refund.
		visit.continuation_complaint = {"tick":world.sim_tick,"doctor_id":diagnosis(visit).doctor_id}
		visit.final_result = "referred"
		plan.stage = "finished"
	else:
		plan.return_day = int(plan.first_day)+2
		plan.due_tick = int(plan.return_day)*WorldState.TICKS_PER_DAY+world.draw("arrival",WorldState.TICKS_PER_DAY)
		plan.stage = "leaving"
	clinic._release_preparation(world,visit.id)
	if clinic.waiting_life!=null: clinic.waiting_life.call("release_for_departure",world,visit.id)
	if clinic.floor_guidance!=null: clinic.floor_guidance.release(world,visit.id)
	var ticket: Dictionary=world.facts.tickets.get(str(visit.get("ticket_id","")),{})
	if plan.stage=="finished":
		world.facts.tickets.erase(str(visit.get("ticket_id","")))
		visit.ticket_id=""
	elif not ticket.is_empty():
		ticket.service_assigned=false
		ticket.called_tick=-1
	visit.phase = "leaving" if plan.stage=="finished" else "continuation_leaving"

static func dispatch_continuation(clinic: HospitalClinic, world: WorldState, visit: Dictionary) -> void:
	var plan: Dictionary = visit.continuation
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	if visit.phase=="continuation_leaving":
		var exit: Array = clinic.space.exit_cell(world,actor)
		if clinic.space.at(world,actor.id,1,exit):
			if not clinic.space.cancel_ground_move(world,actor.id): return
			actor.location = {"kind":"outside"}
			var resident: Dictionary=world.facts.get("residents",{}).get(str(actor.get("resident_id","")),{})
			if not resident.is_empty(): resident.current_actor_id=""
			clinic.space.sync_actor(world,actor.id)
			visit.phase = "continuation_outside"
			plan.stage = "outside"
			plan.outside_periods.append({"left_tick":world.sim_tick,"returned_tick":-1})
			if int(plan.first_day)<0:
				plan.first_day=world.sim_tick/WorldState.TICKS_PER_DAY
				plan.return_day=int(plan.first_day)+1
				plan.due_tick=int(plan.return_day)*WorldState.TICKS_PER_DAY+world.draw("arrival",WorldState.TICKS_PER_DAY)
		else: visit.waiting_reason = clinic.space.request_move(world,actor.id,1,exit)
	elif world.sim_tick>=int(plan.due_tick):
		var entry: Dictionary = world.facts.get("entry",{"floor_id":1,"cell":[47,93]})
		var probe: Dictionary = actor.duplicate(true)
		probe.location = {"kind":"floor","floor_id":int(entry.floor_id),"cell":entry.cell.duplicate(),"height_m":0.0}
		if not clinic.space.static_reason(world,probe,int(entry.floor_id),Vector2i(roundi(entry.cell[0]),roundi(entry.cell[1]))).is_empty() or not clinic.space._dynamic_clear(world,actor.id,int(entry.floor_id),clinic.space.body_rectangle(probe)): return
		plan.outside_periods.back().returned_tick=world.sim_tick
		actor.location = probe.location
		var resident: Dictionary=world.facts.get("residents",{}).get(str(actor.get("resident_id","")),{})
		if not resident.is_empty(): resident.current_actor_id=actor.id
		clinic.space.sync_actor(world,actor.id)
		plan.stage = "guidance"
		var kind: String="consult" if diagnosis(visit).exam_completed and not diagnosis(visit).review_completed else "plan"
		clinic._retarget_ticket(world,visit,kind)

static func ward_stay(world: WorldState, visit_id: String) -> Dictionary:
	for stay: Dictionary in world.facts.ward_stays.values():
		if stay.get("visit_id","")==visit_id: return stay
	return {}

static func admit(clinic: HospitalClinic, world: WorldState, visit: Dictionary, ticket: Dictionary) -> void:
	var stay: Dictionary=ward_stay(world,visit.id)
	if stay.is_empty():
		var target_id: String=clinic.floor_guidance.target(world,visit.id) if clinic.floor_guidance!=null else ""
		var floor_id: int=int(world.facts.actors[visit.actor_id].location.get("floor_id",1))
		var quote: Dictionary=clinic._compatible_bed(world,visit,floor_id,[],false,target_id)
		if not quote.ok:
			visit.waiting_reason=quote.reason
			return
		if clinic.waiting_life!=null and not clinic.waiting_life.call("call_patient",world,visit.id):
			return
		var id: String=world.new_id("ward")
		var reason: String=clinic.space.reserve_facility(world,quote.bed_id,visit.actor_id,id,[quote.nurse_id])
		if not reason.is_empty():
			visit.waiting_reason=reason
			return
		stay={"id":id,"visit_id":visit.id,"attempt_id":"","bed_id":quote.bed_id,"nurse_id":quote.nurse_id,"escort_id":quote.nurse_id,"phase":"admitting","remaining_ticks":0,"work_credit_milli":0,"care_completed":false,"last_progress_tick":world.sim_tick}
		world.facts.ward_stays[id]=stay
		world.facts.staff[quote.nurse_id].ward_id=quote.ward_id
	ticket.service_assigned=true
	if int(ticket.get("called_tick",-1))<0: ticket.called_tick=world.sim_tick
	var bed: Dictionary=clinic.space.facility_layout(world,stay.bed_id)
	if not clinic.space.at(world,visit.actor_id,int(bed.floor_id),bed.patient_cell) or world.facts.moves.has(visit.actor_id):
		visit.waiting_reason=clinic.space.request_move(world,visit.actor_id,int(bed.floor_id),bed.patient_cell)
		return
	clinic._support(world,visit,bed,"lying")
	clinic._use(world,bed,str(stay.id))
	stay.phase="waiting_surgery"
	stay.admitted_tick=world.sim_tick
	stay.last_progress_tick=world.sim_tick
	world.facts.tickets.erase(ticket.id)
	visit.ticket_id=""
	if clinic.floor_guidance!=null: clinic.floor_guidance.release(world,visit.id)
	clinic._queue(world,visit,"surgery")
	clinic.visitors.call("admission",world,visit,stay)

static func return_preop(clinic: HospitalClinic, world: WorldState, visit: Dictionary, stay: Dictionary) -> void:
	var bed: Dictionary=clinic.space.facility_layout(world,stay.bed_id)
	var actor: Dictionary=world.facts.actors[visit.actor_id]
	if actor.get("posture","standing")=="lying" and actor.get("support_facility_id","")==stay.bed_id and not world.facts.moves.has(visit.actor_id):
		stay.phase="waiting_surgery"
		return
	if not clinic.space.at(world,visit.actor_id,int(bed.floor_id),bed.patient_cell) or world.facts.moves.has(visit.actor_id):
		visit.waiting_reason=clinic.space.request_move(world,visit.actor_id,int(bed.floor_id),bed.patient_cell)
		return
	clinic._support(world,visit,bed,"lying")
	stay.phase="waiting_surgery"
	visit.waiting_reason="已回原床，等待下一次合法手术安排"

static func abort_preparation(clinic: HospitalClinic, world: WorldState, visit: Dictionary, stay: Dictionary, ticket: Dictionary) -> void:
	clinic._release_preparation(world,visit.id)
	ticket.service_assigned=false
	ticket.called_tick=-1
	stay.phase="return_preop"
