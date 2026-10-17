class_name HospitalClinic
extends RefCounted

const Visitors = preload("res://game/clinic/hospital_visitors.gd")
const ReferenceFraction = preload("res://game/arrivals/exact_fraction.gd")

var content: HospitalContent
var space: HospitalSpace
var waiting_life: RefCounted
var departments: RefCounted
var environment: RefCounted
var recruitment: RefCounted
var scheduler: RefCounted
var visitors: RefCounted
var _worked_staff: Dictionary = {}
var _practice_awards: Dictionary = {}
var _events: Array[SimEvent] = []
var research: RefCounted

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry
	visitors = Visitors.new(database,geometry)

func ensure(world: WorldState) -> void:
	visitors.call("ensure",world)
	if not world.facts.has("clinical_suspensions"): world.facts.clinical_suspensions = {}

func arrivals(world: WorldState) -> void:
	if int(world.facts.get("gameplay_version",0))>=1:
		visitors.call("arrivals",world)

func validate(world: WorldState) -> String:
	var visitor_error: String = str(visitors.call("validate",world))
	if not visitor_error.is_empty():
		return visitor_error
	var beds: Dictionary = {}
	for stay: Dictionary in world.facts.ward_stays.values():
		if not stay.get("phase","") in ["reserved","transfer","recovery","round_wait","round","release_wait","referral_release"] or not WorldState._natural(stay.get("remaining_ticks",-1)) or not WorldState._natural(stay.get("work_credit_milli",-1)) or int(stay.work_credit_milli)>=1000 or not stay.get("care_completed") is bool:
			return "住院阶段、恢复余量或护理完成事实无效"
		for field: String in ["nurse_id","round_doctor_id","escort_id"]:
			if not world.facts.staff.has(stay.get(field,"")):
				return "住院覆盖、查房或陪护人员引用无效"
		for bed_id: String in [stay.bed_id,stay.get("transfer_from_bed_id","")]:
			if bed_id.is_empty(): continue
			if not world.facts.facilities.has(bed_id) or beds.has(bed_id):
				return "住院当前床与安全交接原床被重复承诺"
			beds[bed_id] = stay.id
	for session: Dictionary in world.facts.sessions.values():
		if session.has("stay_id") and not world.facts.ward_stays.has(session.stay_id):
			return "床边工作缺少原住院事实"
	return ""

func execute(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	match kind:
		"clinical_arrive":
			return _arrive(world,payload)
		"clinical_refer":
			var id: String = str(payload.get("visit_id",""))
			if not world.facts.visits.has(id):
				return CommandResult.new(false,"visit_missing","原病例已不存在",[],world.revision)
			var departed: bool = depart_visit(world,id,"referred")
			return CommandResult.new(departed,"applied" if departed else "safe_work_in_progress","" if departed else "患者须先完成当前安全医疗段",[id] if departed else [],world.revision)
		"clinical_select_plan", "clinical_auto_plan", "clinical_confirm_plan":
			return _change_plan(world,kind,payload)
		"clinical_assign_ward", "clinical_transfer_bed", "clinical_ward_refer", "clinical_visit_consent":
			return _ward_command(world,kind,payload)
	return CommandResult.new(false,"unknown_command","未知临床命令",[],world.revision)

func _change_plan(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	var id: String = str(payload.get("visit_id",""))
	var visit: Dictionary = world.facts.visits.get(id,{})
	if visit.is_empty() or not str(visit.phase).begins_with("wait_"):
		return CommandResult.new(false,"clinical_busy","请选择正在候诊且尚未开工的病例",[],world.revision)
	if world.facts.tickets.get(visit.get("ticket_id",""),{}).has("resume_session_id"):
		return CommandResult.new(false,"clinical_busy","原疗程已开工，安全暂停期间仍保留原方案",[],world.revision)
	if kind == "clinical_auto_plan":
		_release_preparation(world,id)
		visit.plan_decision = {}
		_retarget_ticket(world,visit,"consult")
		return CommandResult.new(true,"applied","",[id],world.revision)
	var plan_id: String = str(payload.get("plan_id",visit.plan_decision.get("plan_id","")))
	var quote: Dictionary = plan_quote(world,id,plan_id)
	if not quote.ok:
		return CommandResult.new(false,"plan_not_ready",quote.reason,[],world.revision)
	if payload.has("probability_bp") and int(payload.probability_bp)!=int(quote.probability_bp):
		return CommandResult.new(false,"material_change","当前预计效果已改变，请刷新本次方案",[],world.revision)
	_release_preparation(world,id)
	visit.requested_plan_id = plan_id
	visit.plan_decision = {"plan_id":plan_id,"source":"director","doctor_id":str(quote.staff_ids[0]),
		"revision":int(visit.plan_decision.get("revision",0))+1,"probability_bp":int(quote.probability_bp),"reason":"院长指定当前合法方案","expected_team":quote.staff_ids.duplicate()}
	_retarget_ticket(world,visit,str(content.definition("treatment_protocols",content.definition("treatment_plans",plan_id).protocol_id).kind))
	return CommandResult.new(true,"applied","",[id],world.revision)

func _retarget_ticket(world: WorldState, visit: Dictionary, kind: String) -> void:
	if not world.facts.tickets.has(visit.ticket_id):
		_queue(world,visit,kind)
		return
	var ticket: Dictionary = world.facts.tickets[visit.ticket_id]
	ticket.kind = kind
	ticket.service_assigned = false
	ticket.called_tick = -1
	visit.phase = "wait_"+kind
	visit.waiting_reason = ""

func _arrive(world: WorldState, payload: Dictionary) -> CommandResult:
	var binding: Dictionary = content.definition("treatment_bindings",str(payload.get("binding_id","")))
	if binding.is_empty():
		return CommandResult.new(false,"binding_missing","病例缺少完整身体与治疗适配",[],world.revision)
	var key: String = str(payload.get("arrival_key",""))
	if key.is_empty():
		return CommandResult.new(false,"arrival_identity_missing","到院请求缺少稳定身份",[],world.revision)
	var receipts: Dictionary = world.facts.get("arrival_receipts",{})
	if receipts.has(key):
		var original: String = receipts[key]
		if world.facts.visits[original].binding_id!=binding.id:
			return CommandResult.new(false,"arrival_id_conflict","同一到院请求身份已对应其他病例",[],world.revision)
		return CommandResult.new(true,"duplicate","",[original,world.facts.visits[original].actor_id],world.revision)
	var personality_id: String = str(payload.get("personality_id","PP01"))
	var personality: Dictionary = content.definition("patient_personalities",personality_id)
	var plan_id: String = str(payload.get("requested_plan_id","P_"+str(binding.disease_id)+"_COMMON"))
	var plan: Dictionary = content.definition("treatment_plans",plan_id)
	if personality.is_empty() or plan.is_empty() or plan.disease_id != binding.disease_id:
		return CommandResult.new(false,"invalid_patient","性格或治疗方案不属于本病例",[],world.revision)
	var entry: Dictionary = world.facts.get("entry",{"floor_id":1,"cell":[47,93]})
	var actor: Dictionary = {"id":"arrival_probe","name":str(payload.get("name",content.definition("species",binding.species_id).name)),
		"species_id":binding.species_id,"body_binding_id":binding.id,"location":{"kind":"floor","floor_id":int(entry.floor_id),"cell":entry.cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
	var geometry_reason: String = space.static_reason(world,actor,int(entry.floor_id),Vector2i(int(entry.cell[0]),int(entry.cell[1])))
	if not geometry_reason.is_empty():
		return CommandResult.new(false,"arrival_blocked",geometry_reason,[],world.revision)
	if not space._dynamic_clear(world,actor.id,int(entry.floor_id),space.body_rectangle(actor)):
		return CommandResult.new(false,"arrival_occupied","入口尚未腾出真实身体空间",[],world.revision)
	if int(world.facts.get("gameplay_version",0))>=1:
		var readiness: Dictionary = arrival_readiness(world,binding.id,bool(payload.get("complex",false)))
		if not readiness.ok:
			return CommandResult.new(false,"admission_unavailable",readiness.reason,[],world.revision)
	var actor_id: String = world.new_id("patient")
	var visit_id: String = world.new_id("visit")
	actor.id = actor_id
	if payload.has("resident_id"):
		actor.resident_id = payload.resident_id
	world.facts.actors[actor_id] = actor
	world.facts.visits[visit_id] = {"id":visit_id,"actor_id":actor_id,"disease_id":binding.disease_id,"binding_id":binding.id,
		"requested_plan_id":plan_id,"expression":str(payload.get("expression","clear")),"personality_id":personality_id,
		"anger":float(personality.initial_anger),"phase":"arrival","evidence_by_source":{},"attempt_ids":[],"plan_decision":{},
		"complex":bool(payload.get("complex",false)),"final_result":"","waiting_reason":"","ticket_id":"","doctor_fee_quote":-1,
		"arrived_tick":world.sim_tick,"arrival_key":key}
	world.facts.visits[visit_id].last_progress_tick = world.sim_tick
	world.facts.visits[visit_id].last_service_tick = world.sim_tick
	world.register_visit(visit_id)
	receipts[key] = visit_id
	world.facts.arrival_receipts = receipts
	space.sync_actor(world,actor_id)
	_events.append(SimEvent.new(world.sim_tick,"patient_arrived",[visit_id,actor_id],{"arrival_key":key}))
	return CommandResult.new(true,"applied","",[visit_id,actor_id],world.revision)

func depart_visit(world: WorldState, visit_id: String, result: String = "abandoned") -> bool:
	var visit: Dictionary = world.facts.visits.get(visit_id,{})
	if visit.is_empty() or visit.phase in ["leaving","departed"]:
		return not visit.is_empty()
	for session: Dictionary in world.facts.sessions.values():
		if session.visit_id == visit_id:
			return false
	var suspended: bool = false
	for record: Dictionary in world.facts.get("clinical_suspensions",{}).values():
		if record.visit_id==visit_id: suspended = true
	for stay: Dictionary in world.facts.ward_stays.values().duplicate():
		if world.facts.attempts[stay.attempt_id].visit_id == visit_id:
			if suspended and stay.phase=="reserved":
				world.facts.ward_stays.erase(stay.id)
				continue
			return false
	for id: String in world.facts.get("clinical_suspensions",{}).keys():
		if world.facts.clinical_suspensions[id].visit_id==visit_id: world.facts.clinical_suspensions.erase(id)
	_release_preparation(world,visit_id)
	world.facts.tickets.erase(visit.ticket_id)
	visit.ticket_id = ""
	visit.final_result = result
	visit.phase = "leaving"
	visit.waiting_reason = ""
	return true

func _release_preparation(world: WorldState, visit_id: String) -> void:
	world.facts.preparations.erase(visit_id)
	for reservation: Dictionary in world.facts.adaptations.values():
		if reservation.kind=="facility" and reservation.owner_id==visit_id:
			# Cancelled work no longer owns space. Any body still inside keeps
			# its physical envelope until it has actually walked clear.
			reservation.owner_id = reservation.actor_id
	space.release_adaptations(world)

func dispatch(world: WorldState) -> void:
	_worked_staff.clear()
	_dispatch_clinical_releases(world)
	if int(world.facts.get("gameplay_version",0))>=1:
		visitors.call("dispatch",world)
	for preparation_id: String in world.ids("preparations"):
		var pending: Dictionary = world.facts.preparations[preparation_id]
		if pending.get("kind","")=="outpatient" and world.sim_tick>=int(pending.deadline_tick):
			_release_preparation(world,preparation_id)
			world.facts.visits[pending.visit_id].waiting_reason = "准备到期，释放原资源并保留票号"
	for visit_id: String in world.active_visit_ids():
		var visit: Dictionary = world.facts.visits[visit_id]
		if visit.phase == "arrival":
			_queue(world,visit,"reception")
		elif visit.phase == "leaving":
			var exit_cell: Array = space.exit_cell(world,world.facts.actors[visit.actor_id])
			if space.at(world,visit.actor_id,1,exit_cell):
				world.facts.actors[visit.actor_id].location = {"kind":"outside"}
				space.sync_actor(world,visit.actor_id)
				visit.phase = "departed"
				visit.departed_tick = world.sim_tick
				_events.append(SimEvent.new(world.sim_tick,"patient_departed",[visit.id,visit.actor_id],{"result":visit.final_result}))
			else:
				visit.waiting_reason = space.request_move(world,visit.actor_id,1,exit_cell)
	for ticket_id: String in world.ids("tickets"):
		if not world.facts.tickets.has(ticket_id):
			continue
		var ticket: Dictionary = world.facts.tickets[ticket_id]
		var visit: Dictionary = world.facts.visits[ticket.visit_id]
		if ticket.kind == "surgery":
			_prepare_surgery(world,visit,ticket)
		else:
			_dispatch_service(world,visit,ticket)
	for stay_id: String in world.ids("ward_stays"):
		var stay: Dictionary = world.facts.ward_stays[stay_id]
		var visit: Dictionary = world.facts.visits[world.facts.attempts[stay.attempt_id].visit_id]
		if not stay.has("last_progress_tick"):
			stay.last_progress_tick = world.sim_tick
		if stay.phase in ["recovery","round_wait","round"]:
			var bed: Dictionary = world.facts.facilities[stay.bed_id]
			if bed.failed:
				if _transfer_stay(world,visit,stay).is_empty():
					continue
				visit.waiting_reason = "护理床故障，等待安全转床或维修"
				if world.sim_tick-int(stay.last_progress_tick)>=int(content.balance.clinical.equipment_no_progress_referral_seconds)*10:
					_begin_ward_referral(world,visit,stay)
				continue
			if world.sim_tick-int(stay.last_progress_tick)>=int(content.balance.clinical.staff_no_progress_referral_seconds)*10:
				_begin_ward_referral(world,visit,stay)
				continue
		if stay.phase=="referral_release":
			var release_bed: Dictionary = space.facility_layout(world,stay.bed_id)
			_clear_bed_exit(world,visit,stay)
			space.request_move(world,visit.actor_id,int(release_bed.floor_id),release_bed.patient_cell)
			continue
		if stay.phase == "release_wait" and world.facts.actors[visit.actor_id].get("posture","standing")=="lying":
			var completed_bed: Dictionary = space.facility_layout(world,stay.bed_id)
			_clear_bed_exit(world,visit,stay)
			space.request_move(world,visit.actor_id,int(completed_bed.floor_id),completed_bed.patient_cell)
		if stay.phase == "transfer":
			var bed: Dictionary = space.facility_layout(world,stay.bed_id)
			var actor: Dictionary = world.facts.actors[visit.actor_id]
			if actor.get("posture","standing")=="lying":
				var table: Dictionary = space.facility_layout(world,actor.support_facility_id)
				space.request_move(world,visit.actor_id,int(table.floor_id),table.patient_cell)
				continue
			if not space.at(world,visit.actor_id,int(bed.floor_id),bed.patient_cell):
				if world.facts.moves.has(visit.actor_id):
					continue
				var alongside: Array = [float(actor.location.cell[0])-1,float(actor.location.cell[1])]
				if not space.at(world,stay.escort_id,int(bed.floor_id),alongside):
					visit.waiting_reason = space.request_move(world,stay.escort_id,int(bed.floor_id),alongside)
					continue
				visit.waiting_reason = space.request_group_move(world,visit.actor_id,[visit.actor_id,stay.escort_id],{visit.actor_id:[0,0],stay.escort_id:[-1,0]},int(bed.floor_id),bed.patient_cell)
			else:
				stay.phase = "recovery"
				visit.phase = "recovery"
				stay.entered_tick = world.sim_tick
				_support(world,visit,bed,"lying")
				_use(world,bed,stay.attempt_id)
				_practice(world,stay.escort_id,"care",stay.attempt_id+":escort")
				_release_ward_operator(world,stay,stay.escort_id)
		elif stay.phase == "recovery" and not stay.care_completed and not _staff_busy(world,stay.nurse_id):
			_start_bed_service(world,visit,stay,"care",stay.nurse_id)
		elif stay.phase == "round_wait":
			var doctor_id: String = _round_candidate(world,visit,stay)
			if not doctor_id.is_empty():
				stay.round_doctor_id = doctor_id
				_start_bed_service(world,visit,stay,"round",doctor_id)
			else:
				visit.waiting_reason = _ward_staff_wait_reason(world,stay,"round")
	if int(world.facts.get("gameplay_version",0))>=1:
		_dispatch_ward_returns(world)

func advance(world: WorldState) -> void:
	for session_id: String in world.ids("sessions"):
		if not world.facts.sessions.has(session_id):
			continue
		var session: Dictionary = world.facts.sessions[session_id]
		var facility: Dictionary = world.facts.facilities[session.facility_id]
		if facility.failed and session.kind not in ["wake","surgery"]:
			world.facts.visits[session.visit_id].waiting_reason = "设备暂停，保留原工作和承诺结果"
			continue
		for staff_id: String in session.staff_ids:
			_worked_staff[staff_id] = true
		session.remaining_ticks -= 1
		world.facts.visits[session.visit_id].last_progress_tick = world.sim_tick
		world.facts.visits[session.visit_id].last_service_tick = world.sim_tick
		if session.has("stay_id") and world.facts.ward_stays.has(session.stay_id):
			world.facts.ward_stays[session.stay_id].last_progress_tick = world.sim_tick
		if session.kind in ["outpatient","surgery"]:
			var completed: int = int(session.total_ticks)-int(session.remaining_ticks)
			var boundaries: Array = world.facts.attempts[session.attempt_id].get("beat_end_ticks",[])
			var beat: int = 0
			for boundary: int in boundaries:
				if completed>=boundary:
					beat += 1
			session.clinical_beat = mini(3,beat)
		if int(session.remaining_ticks) <= 0:
			_complete_service(world,session)
	for stay_id: String in world.ids("ward_stays"):
		if not world.facts.ward_stays.has(stay_id):
			continue
		var stay: Dictionary = world.facts.ward_stays[stay_id]
		if stay.phase != "recovery":
			continue
		var bed: Dictionary = world.facts.facilities[stay.bed_id]
		var nurse: Dictionary = world.facts.staff[stay.nurse_id]
		if not _ward_covering(world,stay):
			world.facts.visits[world.facts.attempts[stay.attempt_id].visit_id].waiting_reason = _ward_staff_wait_reason(world,stay,"care")
			continue
		var rate_key: String = stay.bed_id+":"+stay.nurse_id+":"+str(nurse.abilities.care)+":"+str(bed.grade)
		if stay.get("coverage_segment",{}).get("key","")!=rate_key:
			stay.coverage_segment = {"key":rate_key,"start_tick":world.sim_tick,"rate_milli":_recovery_rate(world,stay.bed_id,stay.nurse_id)}
		stay.work_credit_milli += int(stay.coverage_segment.rate_milli)
		var credit: int = int(stay.work_credit_milli) / 1000
		stay.work_credit_milli = int(stay.work_credit_milli) % 1000
		var before_ticks: int = int(stay.remaining_ticks)
		stay.remaining_ticks = maxi(0,int(stay.remaining_ticks)-credit)
		if int(stay.remaining_ticks)<before_ticks:
			stay.last_progress_tick = world.sim_tick
			world.facts.visits[world.facts.attempts[stay.attempt_id].visit_id].last_progress_tick = world.sim_tick
		if int(stay.remaining_ticks) == 0 and stay.care_completed:
			stay.phase = "round_wait"
			world.facts.visits[world.facts.attempts[stay.attempt_id].visit_id].phase = "round_wait"
	if int(world.facts.get("gameplay_version",0))>=1:
		visitors.call("advance",world)

func release_departed(world: WorldState) -> void:
	for stay_id: String in world.ids("ward_stays"):
		var stay: Dictionary = world.facts.ward_stays[stay_id]
		if stay.has("transfer_from_bed_id"):
			var actor_id: String = world.facts.visits[world.facts.attempts[stay.attempt_id].visit_id].actor_id
			if not space.overlaps_facility(world,actor_id,stay.transfer_from_bed_id):
				stay.erase("transfer_from_bed_id")
		if stay.phase in ["release_wait","referral_release"]:
			var visit: Dictionary = world.facts.visits[world.facts.attempts[stay.attempt_id].visit_id]
			var bed: Dictionary = world.facts.facilities[stay.bed_id]
			if not space.overlaps_facility(world,visit.actor_id,stay.bed_id):
				if stay.phase=="referral_release":
					visit.final_result = "referred"
					visit.phase = "leaving"
					visit.waiting_reason = "已安全转交院外照护，未完成住院项目不收费"
				world.facts.ward_stays.erase(stay_id)

func _queue(world: WorldState, visit: Dictionary, kind: String) -> void:
	if not str(visit.get("ticket_id","")).is_empty() and world.facts.tickets.has(visit.ticket_id):
		return
	var ticket_id: String = world.new_id("ticket")
	world.facts.tickets[ticket_id] = {"id":ticket_id,"visit_id":visit.id,"kind":kind,"enqueued_tick":world.facts.sim_tick}
	visit.ticket_id = ticket_id
	visit.phase = "wait_" + kind
	visit.waiting_reason = ""
	_events.append(SimEvent.new(world.sim_tick,"service_queued",[visit.id,ticket_id],{"kind":kind}))

func _dispatch_service(world: WorldState, visit: Dictionary, ticket: Dictionary) -> void:
	if ticket.has("resume_session_id"):
		_dispatch_suspended(world,visit,ticket)
		return
	if _gather_assigned(world,visit,ticket):
		return
	var kind: String = ticket.kind
	if kind=="outpatient" and int(world.facts.get("gameplay_version",0))>=1 and not visit.plan_decision.is_empty():
		var current_quote: Dictionary = plan_quote(world,visit.id,visit.plan_decision.plan_id)
		if not current_quote.ok and not current_quote.get("structural_ok",false):
			_release_preparation(world,visit.id)
			ticket.service_assigned = false
			ticket.called_tick = -1
			if visit.plan_decision.get("source","")=="doctor":
				_retarget_ticket(world,visit,"consult")
			else:
				visit.plan_decision.pending_reason = "方案条件变化："+str(current_quote.reason)
			visit.waiting_reason = str(current_quote.reason)
			return
	var recommendation: Dictionary = {}
	if kind=="consult" and int(world.facts.get("gameplay_version",0))>=1:
		recommendation = _select_plan(world,visit)
		if recommendation.is_empty():
			visit.waiting_reason = "暂无完整可执行方案，保留原票号等待资源与资格"
			return
	if kind=="gp" and departments!=null and not departments.call("route_patient",world,visit.id):
		return
	var facility_id: String = {"reception":"reception_desk","gp":"gp","spectrum":"exam",
		"resonance":"exam","consult":"gp","outpatient":"treatment"}.get(kind,"")
	var staff_id: String = {"reception":"reception","gp":"gp_doctor","spectrum":"exam_nurse",
		"resonance":"exam_nurse","consult":"gp_doctor","outpatient":"treat_doctor"}.get(kind,"")
	if int(world.facts.get("gameplay_version",0)) >= 1:
		var selection: Dictionary = {"first_only":true}
		if kind=="consult" and scheduler!=null: selection.staff_id = recommendation.get("consulting_doctor_id","")
		var candidates: Array = service_candidates(world,visit,kind,false,false,selection)
		if candidates.is_empty():
			visit.waiting_reason = "等待实际可用设备、合格人员及合法路线"
			return
		facility_id = candidates[0].facility_id
		staff_id = candidates[0].staff_id
	if facility_id.is_empty() or not world.facts.facilities.has(facility_id):
		visit.waiting_reason = "缺少实际设施"
		return
	var facility: Dictionary = world.facts.facilities[facility_id]
	if facility.failed or _facility_busy(world,facility_id,visit.id) or _staff_busy(world,staff_id,visit.id):
		visit.waiting_reason = "保留原票号，等待设备与合格人员"
		return
	var staff: Dictionary = world.facts.staff[staff_id]
	if not staff.on_shift or not _can_start(world,staff):
		visit.waiting_reason = "等待当班且可以安全接单的职员"
		return
	var track: String = "treatment" if kind in ["outpatient","consult"] else "diagnosis"
	if kind != "reception" and int(staff.abilities[track]) < 1:
		visit.waiting_reason = "职员缺少对应能力资格"
		return
	if waiting_life != null and not waiting_life.call("call_patient",world,visit.id):
		return
	if kind == "outpatient":
		var ready_quote: Dictionary = _outpatient_quote(world,visit,staff,facility)
		if not ready_quote.ok:
			visit.waiting_reason = ready_quote.reason
			_release_preparation(world,visit.id)
			ticket.service_assigned = false
			ticket.called_tick = -1
			return
		if not _decision_valid(world,visit,ready_quote):
			return
		if not world.facts.preparations.has(visit.id):
			var bundle_reason: String = _reserve_bundle(world,visit,ready_quote,visit.id)
			if not bundle_reason.is_empty():
				visit.waiting_reason = bundle_reason
				return
			world.facts.preparations[visit.id] = {"id":visit.id,"visit_id":visit.id,"kind":"outpatient","bed_id":str(ready_quote.get("bed_id","")),"facility_id":facility_id,"staff_ids":[staff_id],
				"supply_units":int(ready_quote.supply_units),"setup_remaining_ticks":0,"deadline_tick":world.sim_tick+int(content.balance.supplies.reservation_seconds)*10}
			for field: String in ["nurse_id","round_doctor_id","ward_id"]:
				if ready_quote.has(field):
					world.facts.preparations[visit.id][field] = ready_quote[field]
	var fit_reason: String = space.reserve_facility(world,facility_id,visit.actor_id,ticket.id,[staff_id])
	if not fit_reason.is_empty():
		visit.waiting_reason = fit_reason
		return
	ticket.service_assigned = true
	if int(ticket.get("called_tick",-1))<0:
		ticket.called_tick = world.sim_tick
	facility = space.facility_layout(world,facility_id)
	if not _gather(world,visit,facility,[staff_id]):
		return
	var ticks: int = 0
	var effective: float = float(facility.grade) * float(content.balance.medical_equipment_effects.utilization_by_level[int(staff.abilities[track])]) if kind != "reception" else 0.0
	var session_data: Dictionary = {"evidence":0.0,"doctor_fee":0,"facility_fee":content.facility_fee(facility.definition_id,kind)}
	match kind:
		"reception":
			ticks = ceili(float(content.balance.reception_seconds)*10/_talent_rate(world,staff.id,"registration",visit))
		"gp":
			ticks = ceili(float(_gp_work_ticks(visit,staff,effective))/_talent_rate(world,staff.id,"gp",visit))
			var profile: Dictionary = _profile(visit)
			session_data.evidence = minf(100.0,float(profile.gp_confidence)+2.0*(int(staff.abilities.diagnosis)-1)+2.0*effective)
			if int(visit.doctor_fee_quote) < 0:
				visit.doctor_fee_quote = content.doctor_fee(staff.title_id)
			session_data.doctor_fee = visit.doctor_fee_quote
		"spectrum", "resonance":
			var test: Dictionary = content.balance.tests[kind]
			var seconds: float = float(test.seconds)
			if staff.role=="doctor":
				seconds *= 1.0+float(content.balance.wellbeing.fatigue_work_multiplier_per_point)*float(staff.fatigue)
			ticks = ceili(seconds/(1.0+0.05*(int(staff.abilities.diagnosis)-1)+0.15*effective)*10/_talent_rate(world,staff.id,"test",visit))
			session_data.evidence = float(test.confidence)+2.0*(int(staff.abilities.diagnosis)-1)+3.0*effective
		"consult":
			ticks = ceili(maxf(4.0,float(content.balance.clinical.consult_seconds)*(1.0+0.003*float(staff.fatigue)))*10)
			if not visit.plan_decision.is_empty():
				session_data.resume_ticket = ticket.duplicate(true)
		"outpatient":
			var quote: Dictionary = _outpatient_quote(world,visit,staff,facility)
			if not quote.ok:
				visit.waiting_reason = quote.reason
				return
			var attempt: Dictionary = _commit_attempt(world,visit,quote)
			if int(attempt.recovery_ticks)>0:
				world.facts.ward_stays[attempt.id] = {"id":attempt.id,"attempt_id":attempt.id,"bed_id":attempt.bed_id,"phase":"reserved",
					"remaining_ticks":attempt.recovery_ticks,"work_credit_milli":0,"care_completed":false,"nurse_id":attempt.nurse_id,
					"round_doctor_id":attempt.round_doctor_id,"escort_id":attempt.nurse_id,"last_progress_tick":world.sim_tick}
			ticks = int(attempt.work_ticks)
			session_data.attempt_id = attempt.id
	var session: Dictionary = _start(world,visit,kind,facility_id,[staff_id],ticks,session_data)
	if kind == "outpatient":
		_support(world,visit,facility,"seated")
	_use(world,facility,str(session.get("attempt_id",session.id)))
	world.facts.tickets.erase(ticket.id)
	world.facts.preparations.erase(visit.id)
	visit.ticket_id = ""
	visit.phase = kind
	visit.waiting_reason = ""

func _gather_assigned(world: WorldState, visit: Dictionary, ticket: Dictionary) -> bool:
	if not bool(ticket.get("service_assigned",false)):
		return false
	for facility_id: String in world.ids("adaptations"):
		var held: Dictionary = world.facts.adaptations[facility_id]
		if held.get("kind","")!="facility" or held.owner_id!=ticket.id or held.actor_id!=visit.actor_id or held.staff_ids.size()!=1:
			continue
		var facility: Dictionary = world.facts.facilities.get(facility_id,{})
		var staff_id: String = str(held.staff_ids[0])
		var staff: Dictionary = world.facts.staff.get(staff_id,{})
		if facility.is_empty() or staff.is_empty() or not bool(facility.get("open",true)) or not bool(facility.get("intake_open",true)) or HospitalRemodel.blocked(world,facility_id) or _facility_unavailable(facility) or _facility_busy(world,facility_id,visit.id) or _staff_busy(world,staff_id,visit.id):
			return false
		if not staff.on_shift or not _can_start(world,staff) or not _service_qualified(world,staff,ticket.kind) or not _schedule_allows(world,staff_id,ticket.kind,visit,facility_id):
			return false
		# The ticket already owns this real reservation. Movement checks its live
		# route and sweeps; the complete quote is checked again before work starts.
		return not _gather(world,visit,space.facility_layout(world,facility_id),[staff_id])
	return false

func service_candidates(world: WorldState, visit: Dictionary, kind: String, structural_only: bool = false, reference_schedule: bool = false, selection: Dictionary = {}) -> Array:
	var equipment_id: String = "FUR01" if kind == "reception" else "FUR02"
	if kind == "outpatient":
		var binding: Dictionary = content.definition("treatment_bindings",visit.binding_id)
		equipment_id = str(content.definition("treatment_routines",binding.routine_id).equipment_id)
	var candidates: Array = []
	# This enumeration is synchronous and read-only. Rebuild from the owners
	# after every dispatch, so an earlier ticket's new reservation is visible.
	var preparation: Dictionary = world.facts.preparations.get(visit.id,{})
	var staff_ids: Array = []
	var staff_ids_ready: bool = false
	var facility_ids: Array = world.facility_ids(equipment_id)
	space.begin_route_query(world)
	var availability: Dictionary = {}
	for facility_id: String in facility_ids:
		var facility: Dictionary = world.facts.facilities[facility_id]
		if facility.definition_id!=equipment_id:
			continue
		if HospitalRemodel.blocked(world,facility_id) or facility.failed or not bool(facility.get("open",true)) or not bool(facility.get("intake_open",true)):
			continue
		if not preparation.is_empty() and preparation.facility_id!=facility_id:
			continue
		if not structural_only and not space.facility_reservation_reason(world,facility_id,visit.actor_id).is_empty():
			continue
		if not structural_only and _facility_unavailable(facility):
			continue
		var department_id: String = str(visit.get("department_id",""))
		var department: Dictionary = world.facts.get("departments",{}).get("units",{}).get(department_id,{})
		if kind!="reception" and department_id!="general" and not department.is_empty() and not facility.get("room_id","") in department.get("room_ids",[])+department.get("shared_room_ids",[]):
			continue
		var base_layout: Dictionary = space.facility_layout(world,facility_id)
		if base_layout.operator_cells.is_empty():
			continue
		if not structural_only:
			if availability.is_empty(): availability = _availability(world)
			if _facility_busy(world,facility_id,visit.id,availability): continue
		if not staff_ids_ready:
			staff_ids = [str(selection.staff_id)] if selection.has("staff_id") else world.ids("staff")
			staff_ids_ready = true
		for staff_id: String in staff_ids:
			if not world.facts.staff.has(staff_id): continue
			var staff: Dictionary = world.facts.staff[staff_id]
			if not preparation.is_empty() and not staff_id in preparation.staff_ids:
				continue
			if not structural_only and (_staff_busy(world,staff_id,visit.id,availability) or not staff.on_shift or not _can_start(world,staff)):
				continue
			if not structural_only and not _schedule_allows(world,staff_id,kind,visit,facility_id):
				continue
			if not _service_qualified(world,staff,kind):
				continue
			if reference_schedule and not _reference_assignment_allows(world,staff_id,kind,visit,facility_id):
				continue
			var layout: Dictionary = base_layout
			var fit: Dictionary = space.facility_quote(world,facility_id,visit.actor_id,[staff_id])
			if not fit.ok:
				continue
			var routing_world: WorldState = world
			if not fit.get("unchanged",false):
				routing_world = _reservation_candidate(world,[facility_id])
				var handoff: Dictionary = fit.duplicate(true)
				handoff.erase("ok")
				handoff.owner_id = visit.id
				routing_world.facts.adaptations[facility_id] = handoff
				layout = handoff
				space.begin_route_query(routing_world,{"nominal":true} if space.nominal_query(world) else {})
			var reachable: bool = space.route(routing_world,visit.actor_id,int(layout.floor_id),layout.patient_cell,[],{},true).ok and space.route(routing_world,staff_id,int(layout.floor_id),layout.operator_cells[0],[],{},true).ok
			if routing_world!=world: space.end_route_query()
			if not reachable:
				continue
			candidates.append({"facility_id":facility_id,"staff_id":staff_id})
			if selection.get("first_only",false):
				space.end_route_query()
				return candidates
	space.end_route_query()
	return candidates

func _service_qualified(world: WorldState, staff: Dictionary, kind: String) -> bool:
	if staff.get("departed",false):
		return false
	if kind in ["spectrum","resonance"]:
		for mode: Dictionary in content.catalog.diagnostic_modes:
			if mode.service!=kind:
				continue
			for requirement: Dictionary in mode.operators:
				var allowed: bool = staff.role==requirement.role and int(staff.abilities.get(requirement.ability,0))>=int(requirement.min_level)
				for research_id: String in requirement.requires_research:
					allowed = allowed and research_id in world.facts.research
				if allowed:
					return true
		return false
	if kind=="reception":
		return staff.role=="receptionist"
	return staff.role=="doctor" and int(staff.abilities.get("treatment" if kind in ["outpatient","consult"] else "diagnosis",0))>=1

func _missing_service_reason(world: WorldState, visit: Dictionary, kind: String) -> String:
	var equipment_id: String = "FUR01" if kind=="reception" else "FUR02"
	if kind=="outpatient":
		equipment_id = str(content.definition("treatment_routines",content.definition("treatment_bindings",visit.binding_id).routine_id).equipment_id)
	var facilities: Array = []
	var staff_ids: Array = []
	for id: String in world.ids("facilities"):
		if world.facts.facilities[id].definition_id==equipment_id:
			facilities.append(id)
	if facilities.is_empty():
		return "缺少实际设施："+str(content.facility_definition(equipment_id).get("name",equipment_id))
	for id: String in world.ids("staff"):
		if _service_qualified(world,world.facts.staff[id],kind):
			staff_ids.append(id)
	if staff_ids.is_empty():
		var qualifications: PackedStringArray = []
		for mode: Dictionary in content.catalog.diagnostic_modes:
			if mode.service!=kind:
				continue
			for requirement: Dictionary in mode.operators:
				qualifications.append(("医生" if requirement.role=="doctor" else "护士")+"诊断%d级" % int(requirement.min_level)+("，研究 "+"、".join(requirement.requires_research) if not requirement.requires_research.is_empty() else ""))
		return "缺少"+("或".join(qualifications) if not qualifications.is_empty() else ("接待员" if kind=="reception" else ("具有诊断1级的医生" if kind=="gp" else "具有治疗1级的医生")))
	var reason: String = "设施未开放或缺少合法房间、门与路线"
	for facility_id: String in facilities:
		var facility: Dictionary = world.facts.facilities[facility_id]
		if facility.failed or not facility.get("open",true) or not facility.get("intake_open",true):
			reason = "设施故障或尚未开放："+str(content.facility_definition(equipment_id).get("name",equipment_id))
			continue
		var layout: Dictionary = space.facility_layout(world,facility_id)
		if layout.get("operator_cells",[]).is_empty():
			reason = "设备缺少真实操作位"
			continue
		for staff_id: String in staff_ids:
			var fit: Dictionary = space.facility_quote(world,facility_id,visit.actor_id,[staff_id])
			if not fit.ok:
				reason = str(fit.reason)
				continue
			var patient_route: Dictionary = space.route(world,visit.actor_id,int(layout.floor_id),layout.patient_cell,[],{},true)
			if not patient_route.ok:
				reason = "患者路线："+str(patient_route.reason)
				continue
			var worker_route: Dictionary = space.route(world,staff_id,int(layout.floor_id),layout.operator_cells[0],[],{},true)
			if not worker_route.ok:
				reason = "工作人员路线："+str(worker_route.reason)
	return reason

func compare_plans(world: WorldState, visit_id: String) -> Array:
	var visit: Dictionary = world.facts.visits.get(visit_id,{})
	var results: Array = []
	if visit.is_empty():
		return results
	space.begin_route_query(world)
	for plan: Dictionary in content.catalog.treatment_plans:
		if plan.disease_id==visit.disease_id:
			results.append(plan_quote(world,visit_id,plan.id))
	space.end_route_query()
	return results

func plan_quote(world: WorldState, visit_id: String, plan_id: String, options: Dictionary = {}) -> Dictionary:
	var visit: Dictionary = world.facts.visits.get(visit_id,{})
	var plan: Dictionary = content.definition("treatment_plans",plan_id)
	if visit.is_empty() or plan.is_empty() or plan.disease_id!=visit.disease_id:
		return {"ok":false,"structural_ok":false,"plan_id":plan_id,"reason":"方案不属于当前病例"}
	for research_id: String in plan.requires_research:
		if not research_id in world.facts.research:
			return {"ok":false,"structural_ok":false,"plan_id":plan_id,"reason":"方案研究尚未完成"}
	var protocol: Dictionary = content.definition("treatment_protocols",plan.protocol_id)
	var candidate: Dictionary = visit.duplicate(true)
	candidate.plan_decision = {"plan_id":plan_id}
	var structural: bool = bool(options.get("structural_only",false))
	if protocol.kind=="surgery":
		var structural_options: Dictionary = options.duplicate()
		structural_options.structural_only = true
		structural_options.ignore_supplies = true
		var structural_quote: Dictionary = _surgery_quote(world,candidate,[],structural_options)
		var surgery: Dictionary = structural_quote if structural else _surgery_quote(world,candidate,[],options)
		surgery.plan_id = plan_id
		surgery.structural_ok = bool(structural_quote.ok)
		return surgery
	var reason: String = "缺少合法门诊设备、医生能力或完整路线"
	var structural_ok: bool = false
	for pair: Dictionary in service_candidates(world,candidate,"outpatient",true):
		if options.has("doctor_id") and pair.staff_id!=options.doctor_id:
			continue
		var staff: Dictionary = world.facts.staff[pair.staff_id]
		var facility: Dictionary = world.facts.facilities[pair.facility_id]
		var quote: Dictionary = _outpatient_quote(world,candidate,staff,facility,plan_id,true,true)
		if not quote.ok:
			reason = quote.reason
			continue
		structural_ok = true
		var availability: String = ""
		if not structural and int(quote.recovery_ticks)>0:
			var actual_bed: Dictionary = _outpatient_quote(world,candidate,staff,facility,plan_id,true,false)
			if not actual_bed.ok:
				availability = actual_bed.reason
			else:
				quote = actual_bed
		if not structural and (_facility_unavailable(facility) or _facility_busy(world,pair.facility_id,visit.id) or _staff_busy(world,pair.staff_id,visit.id) or not staff.on_shift or not _can_start(world,staff)):
			availability = "等待原方案的当班医护与设备"
		if not structural and not _schedule_allows(world,pair.staff_id,"outpatient",visit,pair.facility_id):
			availability = "等待当前排班服务池内的治疗医生"
		if not bool(options.get("ignore_supplies",false)) and _available_supplies(world,visit.id)<int(quote.supply_units):
			availability = "治疗包不足，保留原票号"
		quote.ok = availability.is_empty()
		quote.structural_ok = true
		quote.reason = availability
		quote.availability_reason = availability
		quote.facility_id = pair.facility_id
		quote.estimated_total_ticks = int(quote.work_ticks)+int(quote.recovery_ticks)
		if quote.ok:
			return quote
		reason = availability
	return {"ok":false,"structural_ok":structural_ok,"plan_id":plan_id,"reason":reason,"availability_reason":reason if structural_ok else ""}

func _select_plan(world: WorldState, visit: Dictionary, doctor_id: String = "") -> Dictionary:
	var quotes: Array = []
	if scheduler!=null and doctor_id.is_empty():
		for pair: Dictionary in service_candidates(world,visit,"consult"):
			var recommendation: Dictionary = _select_plan(world,visit,pair.staff_id)
			if not recommendation.is_empty(): return recommendation
		return {}
	var selected_doctor: String = doctor_id
	if selected_doctor.is_empty():
		for pair: Dictionary in service_candidates(world,visit,"consult"):
			selected_doctor = pair.staff_id
			break
	if selected_doctor.is_empty():
		return {}
	var staff: Dictionary = world.facts.staff[selected_doctor]
	var personality: Dictionary = content.definition("doctor_personalities",str(staff.get("personality_id","DP01")))
	var weights: Dictionary = personality.weights
	for plan: Dictionary in content.catalog.treatment_plans:
		if plan.disease_id!=visit.disease_id:
			continue
		var quote: Dictionary = plan_quote(world,visit.id,plan.id,{"doctor_id":selected_doctor})
		if not quote.ok:
			continue
		var protocol: Dictionary = content.definition("treatment_protocols",plan.protocol_id)
		if protocol.kind=="surgery" and int(staff.abilities.treatment)<2:
			continue
		var completed: int = int(staff.get("plan_experience",{}).get(plan.id,0))
		quote.score = float(weights.success)*float(quote.probability_bp)/100.0-float(weights.time)*float(quote.get("estimated_total_ticks",quote.work_ticks))/100.0-float(weights.burden)*float(protocol.burden)
		quote.score += float(weights.familiarity)*mini(int(content.balance.clinical.score_familiarity_cap),completed/int(content.balance.clinical.score_familiarity_cases_per_band))+float(weights.novelty)*(1 if completed==0 else 0)+float(weights.team)
		quote.consulting_doctor_id = selected_doctor
		quotes.append(quote)
	return _choose_plan(quotes,str(world.facts.get("plan_strategy","doctor")))

func _choose_plan(legal_quotes: Array, strategy: String) -> Dictionary:
	var quotes: Array = legal_quotes.duplicate()
	quotes.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if float(a.score)!=float(b.score): return float(a.score)>float(b.score)
		if int(a.probability_bp)!=int(b.probability_bp): return int(a.probability_bp)>int(b.probability_bp)
		if int(a.get("estimated_total_ticks",a.work_ticks))!=int(b.get("estimated_total_ticks",b.work_ticks)): return int(a.get("estimated_total_ticks",a.work_ticks))<int(b.get("estimated_total_ticks",b.work_ticks))
		return str(a.plan_id)<str(b.plan_id))
	if strategy=="outpatient_first":
		for quote: Dictionary in quotes:
			if content.definition("treatment_protocols",content.definition("treatment_plans",quote.plan_id).protocol_id).kind=="outpatient" and int(quote.probability_bp)>=roundi(float(content.balance.clinical.outpatient_priority_success)*10000):
				return quote
	elif strategy=="safety_first" and not quotes.is_empty():
		var maximum: int = 0
		for quote: Dictionary in quotes:
			maximum = maxi(maximum,int(quote.probability_bp))
		for quote: Dictionary in quotes:
			if maximum-int(quote.probability_bp)<=roundi(float(content.balance.clinical.safety_strategy_tolerance)*10000):
				return quote
	return quotes[0] if not quotes.is_empty() else {}

func _decision_valid(world: WorldState, visit: Dictionary, quote: Dictionary) -> bool:
	var decision: Dictionary = visit.plan_decision
	var previous: int = int(decision.get("probability_bp",quote.probability_bp))
	if previous-int(quote.probability_bp)<=roundi(float(content.balance.clinical.reconsult_probability_delta)*10000) and int(quote.probability_bp)>=roundi(float(content.balance.clinical.minimum_predicted_success)*10000):
		return true
	_release_preparation(world,visit.id)
	if decision.get("source","")=="director":
		decision.pending_reason = "方案条件变化，请确认当前效果或交给医生"
		visit.waiting_reason = decision.pending_reason
	else:
		decision.pending_reason = "原预计效果降低，需要实际重新会诊"
		_retarget_ticket(world,visit,"consult")
	return false

func _gather(world: WorldState, visit: Dictionary, facility: Dictionary, staff_ids: Array) -> bool:
	var all_present: bool = space.at(world,visit.actor_id,int(facility.floor_id),facility.patient_cell)
	if not all_present:
		visit.waiting_reason = space.request_move(world,visit.actor_id,int(facility.floor_id),facility.patient_cell)
	for index: int in staff_ids.size():
		var staff_id: String = staff_ids[index]
		var position: Array = facility.operator_cells[index]
		if not space.at(world,staff_id,int(facility.floor_id),position):
			all_present = false
			var reason: String = space.request_move(world,staff_id,int(facility.floor_id),position)
			if not reason.is_empty():
				visit.waiting_reason = reason
	return all_present

func _outpatient_minimum(visit: Dictionary, plan_id: String) -> int:
	var plan: Dictionary = content.definition("treatment_plans",plan_id)
	var protocol: Dictionary = content.definition("treatment_protocols",plan.protocol_id)
	if bool(protocol.uses_disease_profile): return int(_profile(visit).min_skill)
	return int(protocol.clinical_profiles[content.definition("diseases",visit.disease_id).profile].min_treatment)

func _required_supplies(visit: Dictionary, protocol: Dictionary) -> int:
	if protocol.kind=="surgery":
		return int(protocol.supply_units)
	if bool(protocol.uses_disease_profile):
		return int(_profile(visit).supply_units)
	return int(protocol.clinical_profiles[content.definition("diseases",visit.disease_id).profile].supply_units)

func _outpatient_quote(world: WorldState, visit: Dictionary, staff: Dictionary, facility: Dictionary, plan_id: String = "", ignore_supplies: bool = false, structural_only: bool = false, reference_schedule: bool = false, bed_quotes: Variant = null) -> Dictionary:
	if plan_id.is_empty():
		plan_id = str(visit.plan_decision.get("plan_id",visit.requested_plan_id))
	var plan: Dictionary = content.definition("treatment_plans",plan_id)
	var protocol: Dictionary = content.definition("treatment_protocols",plan.protocol_id)
	var disease: Dictionary = content.definition("diseases",visit.disease_id)
	var profile: Dictionary = _profile(visit)
	var minimum: int = _outpatient_minimum(visit,plan_id)
	var base_success: float = float(profile.base_success)
	var supply_units: int = _required_supplies(visit,protocol)
	var recovery_seconds: float = 0.0
	if not bool(protocol.uses_disease_profile):
		var gentle: Dictionary = protocol.clinical_profiles[disease.profile]
		base_success = float(gentle.base_success)
		recovery_seconds = float(gentle.recovery_seconds)
	if not ignore_supplies and _available_supplies(world,visit.id)<supply_units:
		return {"ok":false,"reason":"治疗包不足，保留原票号"}
	if visit.attempt_ids.size()>=int(content.balance.max_treatment_attempts):
		return {"ok":false,"reason":"已达到实际治疗次数上限"}
	if staff.role!="doctor" or int(staff.abilities.treatment) < minimum:
		return {"ok":false,"reason":"医生治疗等级不足"}
	var effective: float = float(facility.grade)*float(content.balance.medical_equipment_effects.utilization_by_level[int(staff.abilities.treatment)])
	var probability: float = clampf(base_success+0.02*(int(staff.abilities.treatment)-1)+0.025*effective
		- (0.03 if float(staff.energy)<35.0 else 0.0) - (0.04 if float(facility.condition)<40.0 else 0.0)
		+ (float(content.balance.second_attempt_bonus) if not visit.attempt_ids.is_empty() else 0.0) - (float(protocol.complex_penalty) if visit.complex else 0.0),0.70,0.98)
	if recruitment!=null:
		var talent: Dictionary = recruitment.call("talent_effect",world,staff.id,"outpatient",visit.actor_id,content.definition("treatment_routines",content.definition("treatment_bindings",visit.binding_id).routine_id).specialty_id)
		if talent.get("handler_id","")=="treatment_success":
			probability = clampf(probability+float(talent.value),0.70,0.98)
	if probability < float(content.balance.clinical.minimum_predicted_success):
		return {"ok":false,"reason":"预计效果低于原安全底线"}
	var binding: Dictionary = content.definition("treatment_bindings",visit.binding_id)
	var routine: Dictionary = content.definition("treatment_routines",binding.routine_id)
	if routine.equipment_id != facility.definition_id:
		return {"ok":false,"reason":"病例与医疗主体不适配"}
	var bed_bundle: Dictionary = {}
	if recovery_seconds>0.0:
		if not "R33" in world.facts.research:
			return {"ok":false,"reason":"舒缓观察需要住院照护研究"}
		var preferred: String = str(world.facts.preparations.get(visit.id,{}).get("bed_id",""))
		var key: String = JSON.stringify([int(facility.floor_id),[],structural_only,preferred,reference_schedule])
		if bed_quotes==null: bed_quotes = {}
		if not bed_quotes.has(key): bed_quotes[key] = _compatible_bed(world,visit,int(facility.floor_id),[staff.id],structural_only,preferred,reference_schedule)
		bed_bundle = bed_quotes[key]
		if not bed_bundle.ok:
			return bed_bundle
	var quote: Dictionary = {"ok":true,"plan_id":plan_id,"probability_bp":floori(probability*10000),
		"work_ticks":_outpatient_work_ticks(world,visit,staff,facility,protocol),"recovery_ticks":ceili(recovery_seconds*10),"supply_units":supply_units,
		"cure_fee":_quoted_fee(int(disease.cure_fee),protocol.cure_fee_multiplier),"facility_fee":content.facility_fee(facility.definition_id,"outpatient"),
		"staff_ids":[staff.id],"effective_level":effective,"facility_id":facility.id}
	for key: String in ["bed_id","nurse_id","round_doctor_id","ward_id"]:
		if bed_bundle.has(key):
			quote[key] = bed_bundle[key]
	return quote

func _outpatient_work_ticks(world: WorldState, visit: Dictionary, staff: Dictionary, facility: Dictionary, protocol: Dictionary) -> int:
	var routine: Dictionary = content.definition("treatment_routines",content.definition("treatment_bindings",visit.binding_id).routine_id)
	var effective: float = float(facility.grade)*float(content.balance.medical_equipment_effects.utilization_by_level[int(staff.abilities.treatment)])
	var seconds: float = float(routine.service_seconds)*float(protocol.work_multiplier)/(1.0+0.05*(int(staff.abilities.treatment)-1)+0.2*effective)*(1.0+0.003*float(staff.fatigue))
	if departments!=null: seconds *= float(departments.call("focus_multiplier",world,visit.id,staff.id,"treatment"))
	return ceili(seconds*10)

func _compatible_bed(world: WorldState, visit: Dictionary, floor_id: int, excluded: Array, structural_only: bool = false, preferred_bed: String = "", reference_schedule: bool = false, alternatives: Variant = null) -> Dictionary:
	var nurses: Dictionary = {}
	var doctors: Array = []
	var loads: Dictionary = {}
	var availability: Dictionary = {} if structural_only else _availability(world)
	for id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[id]
		if staff.role=="nurse" and "q_ward" in staff.certificates and not id in excluded:
			var ward_id: String = str(staff.get("ward_id",""))
			if not nurses.has(ward_id): nurses[ward_id] = []
			nurses[ward_id].append(id)
		elif staff.role=="doctor" and int(staff.abilities.diagnosis)>=2 and int(staff.abilities.treatment)>=1:
			doctors.append(id)
	for stay: Dictionary in world.facts.ward_stays.values(): loads[stay.nurse_id] = int(loads.get(stay.nurse_id,0))+1
	for preparation: Dictionary in world.facts.preparations.values():
		if preparation.visit_id!=visit.id:
			var id: String = str(preparation.get("nurse_id",""))
			loads[id] = int(loads.get(id,0))+1
	var workbenches: Array = world.facility_ids("SE06").filter(func(id: String)->bool:
		return int(world.facts.facilities[id].floor_id)==floor_id and not world.facts.facilities[id].failed)
	for bed_id: String in world.facility_ids("EQ05"):
		if not preferred_bed.is_empty() and bed_id!=preferred_bed:
			continue
		var bed: Dictionary = world.facts.facilities[bed_id]
		if HospitalRemodel.blocked(world,bed_id) or bed.definition_id!="EQ05" or int(bed.floor_id)!=floor_id or not world.facts.rooms.has(bed.get("room_id","")):
			continue
		var ward: Dictionary = world.facts.rooms[bed.room_id]
		if ward.kind!="ward" or bed.failed or not bool(ward.get("open",true)) or int(ward.size[0])<6 or int(ward.size[1])<6 or (not structural_only and (_facility_unavailable(bed) or _bed_busy(world,bed_id,visit.id))):
			continue
		for nurse_id: String in nurses.get(ward.id,[]):
			var nurse: Dictionary = world.facts.staff[nurse_id]
			if nurse_id in excluded or nurse.role!="nurse" or not "q_ward" in nurse.certificates or str(nurse.get("ward_id",""))!=ward.id:
				continue
			if reference_schedule and not _reference_assignment_allows(world,nurse_id,"care",visit,bed_id):
				continue
			if not structural_only and (not nurse.on_shift or not _can_start(world,nurse)):
				continue
			if not structural_only and _staff_busy(world,nurse_id,"",availability):
				var unrelated_work: bool = false
				for session: Dictionary in world.facts.sessions.values():
					if nurse_id in session.staff_ids and (session.kind!="care" or world.facts.facilities[session.facility_id].get("room_id","")!=ward.id):
						unrelated_work = true
				for preparation: Dictionary in world.facts.preparations.values():
					unrelated_work = unrelated_work or nurse_id in preparation.staff_ids
				if unrelated_work or not str(nurse.get("active_job_id","")).is_empty():
					continue
			var location: Dictionary = world.facts.actors[nurse_id].location
			var room_rect: Rect2 = Rect2(float(ward.origin[0]),float(ward.origin[1]),float(ward.size[0]),float(ward.size[1]))
			if not structural_only and (location.kind!="floor" or int(location.floor_id)!=floor_id or not room_rect.has_point(Vector2(float(location.cell[0]),float(location.cell[1])))):
				continue
			if int(world.facts.get("gameplay_version",0))>=1:
				var has_workbench: bool = false
				for id: String in workbenches:
					var position: Array = world.facts.facilities[id].operator_cells[0]
					if space.travel_quote(world,nurse_id,floor_id,position).ok:
						has_workbench = true
						break
				if not has_workbench:
					continue
			var load: int = int(loads.get(nurse_id,0))
			if load>=int(content.balance.clinical.beds_per_nurse):
				continue
			for doctor_id: String in doctors:
				var doctor: Dictionary = world.facts.staff[doctor_id]
				if doctor.role!="doctor" or int(doctor.abilities.diagnosis)<2 or int(doctor.abilities.treatment)<1:
					continue
				if not structural_only and (not doctor.on_shift or not _can_start(world,doctor)):
					continue
				if (not structural_only or reference_schedule) and not _schedule_allows(world,doctor_id,"round",visit,bed_id):
					continue
				var fit: Dictionary = space.facility_quote(world,bed_id,visit.actor_id,[nurse_id,doctor_id])
				if not fit.ok:
					continue
				var layout: Dictionary = fit if not fit.get("unchanged",false) else space.facility_layout(world,bed_id)
				if space.travel_quote(world,visit.actor_id,floor_id,layout.patient_cell).ok and space.travel_quote(world,nurse_id,floor_id,layout.operator_cells[0]).ok and space.travel_quote(world,doctor_id,floor_id,layout.operator_cells[1]).ok:
					var quote: Dictionary = {"ok":true,"bed_id":bed_id,"nurse_id":nurse_id,"round_doctor_id":doctor_id,"ward_id":ward.id}
					if alternatives==null: return quote
					alternatives.append(quote)
	if alternatives!=null and not alternatives.is_empty(): return alternatives[0]
	return {"ok":false,"reason":"等待同层兼容床位、真实护理覆盖与出院查房医生"}

func _prepare_surgery(world: WorldState, visit: Dictionary, ticket: Dictionary) -> void:
	var existing: Dictionary = world.facts.preparations.get(visit.id,{})
	var quote: Dictionary = _surgery_quote(world,visit,existing.get("staff_ids",[]),{"facility_id":existing.facility_id,"bed_id":existing.bed_id} if not existing.is_empty() else {})
	if not quote.ok:
		_release_preparation(world,visit.id)
		visit.waiting_reason = quote.reason
		ticket.service_assigned = false
		ticket.called_tick = -1
		return
	if not _decision_valid(world,visit,quote):
		return
	var team: Array = quote.staff_ids
	var preparation: Dictionary = world.facts.preparations.get(visit.id,{})
	if preparation.is_empty():
		if waiting_life!=null and not waiting_life.call("call_patient",world,visit.id):
			return
		var reason: String = _reserve_bundle(world,visit,quote,visit.id)
		if not reason.is_empty():
			visit.waiting_reason = reason
			return
		preparation = {"id":visit.id,"visit_id":visit.id,"kind":"surgery","bed_id":quote.bed_id,"facility_id":quote.facility_id,"staff_ids":team.duplicate(),
			"nurse_id":quote.nurse_id,"round_doctor_id":quote.round_doctor_id,"ward_id":quote.ward_id,"supply_units":int(quote.supply_units),
			"deadline_tick":int(world.facts.sim_tick)+int(content.balance.clinical.bed_reservation_seconds)*10,
			"setup_remaining_ticks":ceili(float(content.balance.clinical.or_setup_seconds)*10/(1.0+0.05*(int(world.facts.staff[team[2]].abilities.surgery)-1))/_talent_rate(world,team[2],"or_assist",visit))}
		world.facts.preparations[visit.id] = preparation
	if int(world.facts.sim_tick) >= int(preparation.deadline_tick):
		_release_preparation(world,visit.id)
		visit.waiting_reason = "准备超过30秒，原票号保留；资源已释放"
		return
	ticket.service_assigned = true
	if int(ticket.get("called_tick",-1))<0:
		ticket.called_tick = world.sim_tick
	var facility: Dictionary = space.facility_layout(world,preparation.facility_id)
	if not _gather(world,visit,facility,team):
		return
	if int(preparation.setup_remaining_ticks) > 0:
		_worked_staff[team[2]] = true
		preparation.setup_remaining_ticks -= 1
		visit.waiting_reason = "护士正在真实器械核对"
		return
	# Recheck the entire bundle at the actual start, not a cached authorization.
	quote = _surgery_quote(world,visit,team,{"facility_id":preparation.facility_id,"bed_id":preparation.bed_id})
	if not quote.ok:
		visit.waiting_reason = quote.reason
		return
	var attempt: Dictionary = _commit_attempt(world,visit,quote)
	world.facts.ward_stays[attempt.id] = {"id":attempt.id,"attempt_id":attempt.id,"bed_id":quote.bed_id,"phase":"reserved",
		"remaining_ticks":attempt.recovery_ticks,"work_credit_milli":0,"care_completed":false,
		"nurse_id":quote.nurse_id,"round_doctor_id":quote.round_doctor_id,"escort_id":team[2],"last_progress_tick":world.sim_tick}
	if world.facts.adaptations.has(quote.bed_id):
		world.facts.adaptations[quote.bed_id].owner_id = attempt.id
	_start(world,visit,"surgery",quote.facility_id,team,int(attempt.work_ticks),{"attempt_id":attempt.id,"clinical_beat":0})
	_support(world,visit,facility,"lying")
	_use(world,facility,attempt.id)
	world.facts.preparations.erase(visit.id)
	world.facts.tickets.erase(ticket.id)
	visit.ticket_id = ""
	visit.phase = "surgery"
	visit.waiting_reason = ""

func _surgery_quote(world: WorldState, visit: Dictionary, requested_team: Array = [], options: Dictionary = {}) -> Dictionary:
	var plan: Dictionary = content.definition("treatment_plans",visit.plan_decision.get("plan_id",""))
	if plan.is_empty():
		return {"ok":false,"structural_ok":false,"reason":"缺少原手术方案"}
	var protocol: Dictionary = content.definition("treatment_protocols",plan.protocol_id)
	var pools: Array = [[],[],[]]
	var structural: bool = bool(options.get("structural_only",false))
	var requirements: Array = [protocol.min_surgeon_surgery,protocol.min_anesthetist_surgery,protocol.min_nurse_surgery]
	var titles: Array = [protocol.min_surgeon_title_id,protocol.min_anesthetist_title_id,""]
	var tables: Array = []
	var table_ids: Array = [str(options.facility_id)] if options.has("facility_id") else world.facility_ids("EQ01")
	for facility_id: String in table_ids:
		if not world.facts.facilities.has(facility_id): continue
		var table: Dictionary = world.facts.facilities[facility_id]
		if table.definition_id=="EQ01" and (not options.has("facility_id") or options.facility_id==facility_id) and not HospitalRemodel.blocked(world,facility_id):
			tables.append(facility_id)
	var team_ids: Array = requested_team if not requested_team.is_empty() else world.ids("staff")
	for staff_id: String in team_ids:
		if not world.facts.staff.has(staff_id): continue
		var staff: Dictionary = world.facts.staff[staff_id]
		for index: int in 3:
			if not requested_team.is_empty() and (requested_team.size()!=3 or staff_id!=requested_team[index]):
				continue
			if staff.role!=("nurse" if index==2 else "doctor") or int(staff.abilities.surgery)<int(requirements[index]):
				continue
			if index==2 and not "q_or" in staff.certificates:
				continue
			if index<2 and int(content.definition("doctor_titles",staff.title_id).rank)<int(content.definition("doctor_titles",titles[index]).rank):
				continue
			if not structural and (not staff.on_shift or not _can_start(world,staff) or _staff_busy(world,staff_id,visit.id)):
				continue
			pools[index].append(staff_id)
	# This read-only enumeration shares bed checks only until it returns.
	# The doctors cannot be ward-nurse candidates; only the team's nurse is excluded.
	var bed_quotes: Dictionary = options.get("bed_quotes",{})
	var alternatives: Variant = options.get("alternatives")
	space.begin_route_query(world)
	var best: Dictionary = {"ok":false,"structural_ok":false,"reason":"缺少当前可执行的三个互异手术岗位"}
	if not pools[0].is_empty() and not pools[1].is_empty() and not pools[2].is_empty() and not tables.is_empty():
		var has_bed: bool = false
		for facility_id: String in tables:
			var table: Dictionary = world.facts.facilities[facility_id]
			for nurse_id: String in pools[2]:
				var key: String = JSON.stringify([int(table.floor_id),nurse_id,structural,str(options.get("bed_id","")),bool(options.get("reference_schedule",false))])
				if not bed_quotes.has(key):
					bed_quotes[key] = _compatible_bed(world,visit,int(table.floor_id),[nurse_id],structural,str(options.get("bed_id","")),bool(options.get("reference_schedule",false)))
				has_bed = has_bed or bool(bed_quotes[key].ok)
				best = bed_quotes[key]
		if not has_bed:
			space.end_route_query()
			return best
		best = {"ok":false,"structural_ok":false,"reason":"缺少当前可执行的三个互异手术岗位"}
	for surgeon_id: String in pools[0]:
		for anesthetist_id: String in pools[1]:
			if surgeon_id==anesthetist_id:
				continue
			for nurse_id: String in pools[2]:
				for facility_id: String in tables:
					var table: Dictionary = world.facts.facilities[facility_id]
					if best.ok and alternatives==null:
						var predicted: Dictionary = _surgery_probability(world,visit,[surgeon_id,anesthetist_id,nurse_id],table,protocol)
						if int(predicted.probability_bp)<int(best.probability_bp) or (int(predicted.probability_bp)==int(best.probability_bp) and str([surgeon_id,anesthetist_id,nurse_id])+facility_id>=str(best.staff_ids)+str(best.facility_id)):
							continue
					var quote: Dictionary = _surgery_bundle_quote(world,visit,[surgeon_id,anesthetist_id,nurse_id],facility_id,options,bed_quotes)
					if quote.ok and alternatives!=null: alternatives.append(quote)
					if quote.ok and (not best.ok or int(quote.probability_bp)>int(best.probability_bp) or (int(quote.probability_bp)==int(best.probability_bp) and str(quote.staff_ids)+facility_id<str(best.staff_ids)+str(best.facility_id))):
						best = quote
					elif not best.ok:
						best = quote
	space.end_route_query()
	return best

func _surgery_probability(world: WorldState, visit: Dictionary, team: Array, table: Dictionary, protocol: Dictionary) -> Dictionary:
	var utilization_sum: float = 0.0
	for staff_id: String in team:
		utilization_sum += float(content.balance.medical_equipment_effects.utilization_by_level[int(world.facts.staff[staff_id].abilities.surgery)])
	var effective: float = float(table.grade)*utilization_sum/3.0
	var surgeon: Dictionary = world.facts.staff[team[0]]
	var anesthetist: Dictionary = world.facts.staff[team[1]]
	var probability: float = float(protocol.base_success)+0.015*(int(surgeon.abilities.surgery)-int(protocol.min_surgeon_surgery))
	probability += 0.005*(int(anesthetist.abilities.surgery)-int(protocol.min_anesthetist_surgery))+0.01*effective
	probability -= 0.03 if float(surgeon.energy)<35 else 0.0
	probability -= 0.04 if float(table.condition)<40 else 0.0
	probability += 0.15 if not visit.attempt_ids.is_empty() else 0.0
	return {"effective_level":effective,"probability_bp":floori(clampf(probability,0.70,0.98)*10000)}

func _surgery_bundle_quote(world: WorldState, visit: Dictionary, team: Array, facility_id: String, options: Dictionary, bed_quotes: Dictionary) -> Dictionary:
	var plan: Dictionary = content.definition("treatment_plans",visit.plan_decision.get("plan_id",""))
	if plan.is_empty():
		return {"ok":false,"reason":"缺少原手术方案"}
	var protocol: Dictionary = content.definition("treatment_protocols",plan.protocol_id)
	if visit.attempt_ids.size()>=int(content.balance.max_treatment_attempts):
		return {"ok":false,"reason":"已达到实际治疗次数上限"}
	for research_id: String in plan.requires_research:
		if not research_id in world.facts.research:
			return {"ok":false,"reason":"手术研究尚未完成"}
	var requirements: Array = [protocol.min_surgeon_surgery,protocol.min_anesthetist_surgery,protocol.min_nurse_surgery]
	var titles: Array = [protocol.min_surgeon_title_id,protocol.min_anesthetist_title_id,""]
	for index: int in team.size():
		var staff_id: String = team[index]
		if not world.facts.staff.has(staff_id):
			return {"ok":false,"reason":"手术团队缺员"}
		var staff: Dictionary = world.facts.staff[staff_id]
		if int(staff.abilities.surgery) < int(requirements[index]):
			return {"ok":false,"reason":"手术人员未在班或资格不足"}
		if index < 2 and int(content.definition("doctor_titles",staff.title_id).rank) < int(content.definition("doctor_titles",titles[index]).rank):
			return {"ok":false,"reason":"外科职称不足"}
		if index == 2 and not "q_or" in staff.certificates:
			return {"ok":false,"reason":"护士未取得手术资格"}
	if team[0] == team[1] or team[0] == team[2] or team[1] == team[2]:
		return {"ok":false,"reason":"手术岗位必须互异"}
	var table: Dictionary = world.facts.facilities[facility_id]
	var structural: bool = bool(options.get("structural_only",false))
	if not structural or bool(options.get("reference_schedule",false)):
		for staff_id: String in team:
			if not _reference_assignment_allows(world,staff_id,"surgery",visit,facility_id):
				return {"ok":false,"structural_ok":true,"reason":"等待排班手术池内的完整团队"}
	if not world.facts.rooms.has(table.get("room_id","")):
		return {"ok":false,"reason":"手术台缺少合法手术室"}
	var operating_room: Dictionary = world.facts.rooms[table.room_id]
	if table.failed or not bool(table.get("open",true)) or not bool(table.get("intake_open",true)) or not bool(operating_room.get("open",true)) or operating_room.kind!="operating_room" or int(operating_room.size[0])<8 or int(operating_room.size[1])<8:
		return {"ok":false,"reason":"手术室未满足最小内部8×8"}
	if not structural and (_facility_unavailable(table) or _facility_busy(world,facility_id,visit.id)):
		return {"ok":false,"structural_ok":true,"reason":"等待原手术台安全可用"}
	var bed_key: String = JSON.stringify([int(table.floor_id),team[2],structural,str(options.get("bed_id","")),bool(options.get("reference_schedule",false))])
	if not bed_quotes.has(bed_key):
		bed_quotes[bed_key] = _compatible_bed(world,visit,int(table.floor_id),team,structural,str(options.get("bed_id","")),bool(options.get("reference_schedule",false)))
	var bed_bundle: Dictionary = bed_quotes[bed_key]
	if not bed_bundle.ok:
		return bed_bundle
	if options.has("bed_id") and options.bed_id!=bed_bundle.bed_id:
		return {"ok":false,"reason":"原准备床位已失效，需要重新取得完整资源束"}
	if not bool(options.get("ignore_supplies",false)) and _available_supplies(world,visit.id) < int(protocol.supply_units):
		return {"ok":false,"reason":"治疗包不足"}
	var compatible: bool = false
	for adapter: Dictionary in content.catalog.surgical_adapters:
		if adapter.binding_id == visit.binding_id and adapter.plan_id == plan.id:
			compatible = true
	if not compatible:
		return {"ok":false,"reason":"病例缺少合法手术承托适配"}
	var fit: Dictionary = space.facility_quote(world,facility_id,visit.actor_id,team)
	if not fit.ok:
		return fit
	var layout: Dictionary = space.facility_layout(world,facility_id) if fit.get("unchanged",false) else fit
	if layout.operator_cells.size()!=3:
		return {"ok":false,"reason":"手术台缺少三个互异实际医护站位"}
	var gathering_ticks: int = 0
	for index: int in 4:
		var actor_id: String = visit.actor_id if index==0 else str(team[index-1])
		var position: Array = layout.patient_cell if index==0 else layout.operator_cells[index-1]
		var route: Dictionary = space.travel_quote(world,actor_id,int(table.floor_id),position)
		if not route.ok:
			return route
		gathering_ticks = maxi(gathering_ticks,int(route.arrival_ticks))
	var predicted: Dictionary = _surgery_probability(world,visit,team,table,protocol)
	var effective: float = float(predicted.effective_level)
	var seconds: float = _surgery_work_seconds(world,visit,team[0],protocol,effective)
	for staff_id: String in team:
		var consumption: float = float(content.balance.wellbeing.energy_work_per_second)*(seconds+float(content.balance.clinical.wake_seconds)+float(content.balance.clinical.or_setup_seconds))
		if not structural and float(world.facts.staff[staff_id].energy)-consumption<=15.0:
			return {"ok":false,"reason":"团队体力不足以安全覆盖操作和苏醒全过程"}
	var quote: Dictionary = {"ok":true,"structural_ok":true,"plan_id":plan.id,"probability_bp":int(predicted.probability_bp),"work_ticks":ceili(seconds*10),
		"recovery_ticks":ceili(float(protocol.recovery_seconds)*10),"supply_units":int(protocol.supply_units),
		"cure_fee":_quoted_fee(int(content.definition("diseases",visit.disease_id).cure_fee),protocol.cure_fee_multiplier),
		"facility_fee":content.facility_fee(table.definition_id,"surgery"),"staff_ids":team.duplicate(),"effective_level":effective,"facility_id":facility_id,
		"gathering_ticks":gathering_ticks,"estimated_total_ticks":gathering_ticks+ceili(seconds*10)+ceili(float(protocol.recovery_seconds)*10)+int(content.balance.clinical.wake_seconds)*10}
	quote.merge(bed_bundle)
	return quote

func _surgery_work_seconds(world: WorldState, visit: Dictionary, surgeon_id: String, protocol: Dictionary, effective: float) -> float:
	var surgeon: Dictionary = world.facts.staff[surgeon_id]
	var seconds: float = float(protocol.work_seconds)/(1.0+0.05*(int(surgeon.abilities.surgery)-int(protocol.min_surgeon_surgery))+0.1*effective)*(1.0+0.003*float(surgeon.fatigue))
	if departments!=null: seconds *= float(departments.call("focus_multiplier",world,visit.id,surgeon_id,"surgery"))
	return seconds

func _bed_service_ticks(world: WorldState, visit: Dictionary, kind: String, staff_id: String) -> int:
	var staff: Dictionary = world.facts.staff[staff_id]
	var seconds: float = float(content.balance.clinical.nurse_visit_seconds if kind=="care" else content.balance.clinical.discharge_round_seconds)
	var level: int = int(staff.abilities.care) if kind=="care" else int(staff.abilities.treatment)
	if staff.role=="doctor": seconds *= 1.0+float(content.balance.wellbeing.fatigue_work_multiplier_per_point)*float(staff.fatigue)
	return ceili(seconds/(1.0+0.05*(level-1))*10/_talent_rate(world,staff_id,"ward_visit",visit))

func _recovery_rate(world: WorldState, bed_id: String, nurse_id: String) -> int:
	var bed: Dictionary = world.facts.facilities[bed_id]
	var nurse: Dictionary = world.facts.staff[nurse_id]
	var effective: float = float(bed.grade)*float(content.balance.medical_equipment_effects.utilization_by_level[int(nurse.abilities.care)])
	return roundi((1.0+0.15*effective)*1000)

func _recovery_ticks(world: WorldState, bed_id: String, nurse_id: String, work: int, credit: int = 0) -> int:
	var rate: int = _recovery_rate(world,bed_id,nurse_id)
	return (maxi(0,1000*work-credit)+rate-1)/rate

# Actual promises are read independently of the new-admission case pool. The
# projection never reads Attempt.result or changes the original work owners.
func remaining_commitments(world: WorldState) -> Dictionary:
	var result: Dictionary = {"resources":{},"coverage":{},"visits":{}}
	var sessions: Dictionary = {}
	var prefixes: Dictionary = {}
	for session: Dictionary in world.facts.sessions.values():
		result.visits[session.visit_id] = true
		var ticks: int = int(session.remaining_ticks)
		if session.kind=="surgery": ticks += int(content.balance.clinical.wake_seconds)*10
		for staff_id: String in session.staff_ids: _commitment_add(result,"staff:"+staff_id,ticks)
		if session.kind in ["care","round"]:
			if not sessions.has(session.stay_id): sessions[session.stay_id] = {}
			sessions[session.stay_id][session.kind] = ticks
		else:
			_commitment_add(result,"facility:"+str(session.facility_id),ticks)
			prefixes[session.visit_id] = ticks
	for preparation: Dictionary in world.facts.preparations.values():
		var visit: Dictionary = world.facts.visits[preparation.visit_id]
		result.visits[visit.id] = true
		var plan: Dictionary = content.definition("treatment_plans",visit.plan_decision.plan_id)
		var protocol: Dictionary = content.definition("treatment_protocols",plan.protocol_id)
		var facility: Dictionary = world.facts.facilities[preparation.facility_id]
		var work: int
		var recovery: int
		var setup: int = int(preparation.setup_remaining_ticks)
		var gathering: int = _gathering_ticks(world,visit,preparation.facility_id,preparation.staff_ids)
		# No known release route means this existing reservation stays held for
		# the planning horizon. Do not invent a future repair or free budget.
		if gathering<0: gathering = WorldState.TICKS_PER_DAY
		if preparation.kind=="surgery":
			var effective: float = float(_surgery_probability(world,visit,preparation.staff_ids,facility,protocol).effective_level)
			work = ceili(_surgery_work_seconds(world,visit,preparation.staff_ids[0],protocol,effective)*10)+int(content.balance.clinical.wake_seconds)*10
			recovery = ceili(float(protocol.recovery_seconds)*10)
		else:
			work = _outpatient_work_ticks(world,visit,world.facts.staff[preparation.staff_ids[0]],facility,protocol)
			recovery = 0 if bool(protocol.uses_disease_profile) else ceili(float(protocol.clinical_profiles[content.definition("diseases",visit.disease_id).profile].recovery_seconds)*10)
		_commitment_add(result,"facility:"+str(preparation.facility_id),gathering+setup+work)
		for staff_id: String in preparation.staff_ids: _commitment_add(result,"staff:"+staff_id,gathering+setup+work)
		if not str(preparation.get("bed_id","")).is_empty():
			_commitment_bed(world,visit,preparation,recovery,0,gathering+setup+work,{},result)
	for stay: Dictionary in world.facts.ward_stays.values():
		var visit: Dictionary = world.facts.visits[world.facts.attempts[stay.attempt_id].visit_id]
		result.visits[visit.id] = true
		_commitment_bed(world,visit,stay,int(stay.remaining_ticks),int(stay.work_credit_milli),int(prefixes.get(visit.id,0)),sessions.get(stay.id,{}),result)
	return result

func _commitment_bed(world: WorldState, visit: Dictionary, owner: Dictionary, recovery_work: int, credit: int, prefix: int, active: Dictionary, result: Dictionary) -> void:
	var phase: String = str(owner.get("phase","reserved"))
	var nurse_id: String = owner.nurse_id
	var round_id: String = owner.round_doctor_id
	var recovery: int = _recovery_ticks(world,owner.bed_id,nurse_id,recovery_work,credit)
	var care: int = 0 if owner.get("care_completed",false) else int(active.get("care",owner.get("care_remaining_ticks",_bed_service_ticks(world,visit,"care",nurse_id))))
	var round_ticks: int = int(active.get("round",owner.get("round_remaining_ticks",_bed_service_ticks(world,visit,"round",round_id))))
	var source: Dictionary = owner if owner.has("facility_id") else world.facts.attempts[owner.attempt_id]
	var transfer: Dictionary = {"ticks":0,"exit_ticks":0}
	if phase in ["reserved","transfer"]:
		transfer = _bed_transport(world,visit,source,owner,phase=="transfer")
		if not transfer.ok:
			transfer.ticks = WorldState.TICKS_PER_DAY
		_commitment_add(result,"facility:"+str(transfer.source_id),int(transfer.exit_ticks))
		_commitment_add(result,"staff:"+str(transfer.escort_id),int(transfer.ticks))
	var bed: Dictionary = space.facility_layout(world,owner.bed_id)
	var patient: Dictionary = world.facts.actors[visit.actor_id].duplicate(true)
	patient.posture = "lying"
	patient.location = space.support_location(world,patient,bed)
	var release_ticks: int = space.support_exit_ticks(patient,bed,true)
	var bed_ticks: int = prefix+int(transfer.ticks)+maxi(recovery,care)+round_ticks+release_ticks
	if phase=="round": bed_ticks = int(active.get("round",round_ticks))+release_ticks
	elif phase=="round_wait": bed_ticks = round_ticks+release_ticks
	elif phase in ["release_wait","referral_release"]: bed_ticks = space.support_exit_ticks(world.facts.actors[visit.actor_id],bed,true)
	_commitment_add(result,"facility:"+str(owner.bed_id),bed_ticks)
	var ward_id: String = str(world.facts.facilities[owner.bed_id].room_id)
	var coverage_id: String = "coverage:"+nurse_id+":"+ward_id
	if not result.coverage.has(coverage_id): result.coverage[coverage_id] = []
	result.coverage[coverage_id].append(bed_ticks)
	if not active.has("care") and care>0 and not phase in ["round","round_wait","release_wait","referral_release"]:
		_commitment_add(result,"staff:"+nurse_id,care)
	if not active.has("round") and not phase in ["release_wait","referral_release"]:
		_commitment_add(result,"staff:"+round_id,round_ticks)

func _commitment_add(result: Dictionary, resource_id: String, ticks: int) -> void:
	result.resources[resource_id] = int(result.resources.get(resource_id,0))+ticks

func _gathering_ticks(world: WorldState, visit: Dictionary, facility_id: String, staff_ids: Array) -> int:
	var layout: Dictionary = space.facility_layout(world,facility_id)
	var ticks: int = 0
	for index: int in staff_ids.size()+1:
		var id: String = visit.actor_id if index==0 else str(staff_ids[index-1])
		var target: Array = layout.patient_cell if index==0 else layout.operator_cells[index-1]
		var quote: Dictionary = space.travel_quote(world,id,int(layout.floor_id),target)
		if not quote.ok: return -1
		ticks = maxi(ticks,int(quote.arrival_ticks))
	return ticks

func _bed_transport(world: WorldState, visit: Dictionary, source: Dictionary, bed_owner: Dictionary, current: bool = false) -> Dictionary:
	var table: Dictionary = space.facility_layout(world,source.facility_id)
	var bed: Dictionary = space.facility_layout(world,bed_owner.bed_id)
	var surgery: bool = source.staff_ids.size()==3
	var escort_id: String = str(bed_owner.get("escort_id",source.staff_ids[-1] if surgery else bed_owner.nurse_id))
	var facts: Dictionary = world.facts.duplicate()
	facts.actors = world.facts.actors.duplicate()
	for id: String in [visit.actor_id,escort_id]: facts.actors[id] = world.facts.actors[id].duplicate(true)
	var candidate: WorldState = WorldState.new(facts)
	var patient: Dictionary = facts.actors[visit.actor_id]
	var escort: Dictionary = facts.actors[escort_id]
	if not current:
		patient.location = space.support_location(candidate,patient,table) if surgery else {"kind":"floor","floor_id":int(table.floor_id),"cell":table.patient_cell.duplicate(),"height_m":0.0}
		patient.posture = "lying" if surgery else "standing"
		if surgery: escort.location = {"kind":"floor","floor_id":int(table.floor_id),"cell":table.operator_cells[-1].duplicate(),"height_m":0.0}
	var exit_ticks: int = 0
	var source_ticks: int = 0
	var source_id: String = str(bed_owner.get("transfer_from_bed_id",source.facility_id)) if current else str(source.facility_id)
	if patient.get("posture","standing")=="lying":
		var support: Dictionary = space.facility_layout(candidate,str(patient.get("support_facility_id",table.id))) if current else table
		source_id = str(support.id)
		exit_ticks = space.support_exit_ticks(patient,support)
		source_ticks = space.support_exit_ticks(patient,support,true)
		patient.location = {"kind":"floor","floor_id":int(support.floor_id),"cell":support.patient_cell.duplicate(),"height_m":0.0}
	patient.posture = "standing"
	patient.erase("support_facility_id")
	var alongside: Array = [float(patient.location.cell[0])-1,float(patient.location.cell[1])]
	var nominal: bool = space.nominal_query(world)
	if nominal: space.begin_route_query(candidate)
	var gathering: Dictionary = space.travel_quote(candidate,escort_id,int(bed.floor_id),alongside)
	var transfer: Dictionary = space.route(candidate,visit.actor_id,int(bed.floor_id),bed.patient_cell,[visit.actor_id,escort_id],{visit.actor_id:[0,0],escort_id:[-1,0]},true)
	if nominal: space.end_route_query()
	if not gathering.ok or not transfer.ok: return {"ok":false,"exit_ticks":source_ticks,"source_id":source_id,"escort_id":escort_id,"gathering":gathering,"transfer":transfer}
	return {"ok":true,"ticks":exit_ticks+int(gathering.arrival_ticks)+int(transfer.arrival_ticks),"exit_ticks":source_ticks,"source_id":source_id,"escort_id":escort_id}

func _quoted_fee(amount: int, multiplier: Variant) -> int:
	var parts: PackedStringArray = str(multiplier).to_lower().split("e")
	var mantissa: String = parts[0]
	var exponent: int = parts[1].to_int() if parts.size()>1 else 0
	var decimal_places: int = mantissa.length()-mantissa.find(".")-1 if mantissa.contains(".") else 0
	var numerator: int = mantissa.replace(".","").to_int()
	var denominator: int = 1
	for index: int in absi(decimal_places-exponent):
		if decimal_places>exponent: denominator *= 10
		else: numerator *= 10
	var whole: int = amount/denominator
	var remainder_product: int = (amount%denominator)*numerator
	return whole*numerator+remainder_product/denominator+(1 if remainder_product%denominator!=0 else 0)

func _reservation_candidate(world: WorldState, facility_ids: Array, actor_ids: Array = []) -> WorldState:
	# Synchronous quote validation writes only these reservation records and
	# projected actors. Ledger, history and unrelated owners remain read-only.
	var facts: Dictionary = world.facts.duplicate()
	facts.adaptations = world.facts.adaptations.duplicate()
	for id: String in facility_ids:
		if facts.adaptations.has(id): facts.adaptations[id] = facts.adaptations[id].duplicate(true)
	if not actor_ids.is_empty():
		facts.actors = world.facts.actors.duplicate()
		for id: String in actor_ids: facts.actors[id] = facts.actors[id].duplicate(true)
	return WorldState.new(facts)

func _reserve_bundle(world: WorldState, visit: Dictionary, quote: Dictionary, owner_id: String) -> String:
	var facility_ids: Array = [quote.facility_id]
	if quote.has("bed_id"): facility_ids.append(quote.bed_id)
	var candidate: WorldState = _reservation_candidate(world,facility_ids)
	var geometry: HospitalSpace = HospitalSpace.new(content)
	geometry._navigation = space._navigation
	var reason: String = geometry.reserve_facility(candidate,quote.facility_id,visit.actor_id,owner_id,quote.staff_ids)
	if not reason.is_empty():
		return reason
	if quote.has("bed_id"):
		reason = geometry.reserve_facility(candidate,quote.bed_id,visit.actor_id,owner_id,[quote.nurse_id,quote.round_doctor_id])
		if not reason.is_empty():
			return reason
	space.commit_facility_reservations(world,candidate.facts.adaptations,facility_ids)
	return ""

func _commit_attempt(world: WorldState, visit: Dictionary, quote: Dictionary) -> Dictionary:
	var id: String = world.new_id("attempt")
	var attempt: Dictionary = quote.duplicate(true)
	attempt.erase("ok")
	attempt.id = id
	attempt.visit_id = visit.id
	attempt.result = world.draw("treatment",10000) < int(attempt.probability_bp)
	if bool(visit.get("tutorial_success_pending",false)) and visit.attempt_ids.is_empty():
		attempt.result = true
		attempt.tutorial_protected = true
		visit.tutorial_success_pending = false
	attempt.start_tick = world.facts.sim_tick
	attempt.protocol_id = content.definition("treatment_plans",attempt.plan_id).protocol_id
	if quote.has("bed_id"):
		attempt.ward_fee = content.facility_fee(world.facts.facilities[quote.bed_id].definition_id,"ward")
	attempt.beat_end_ticks = []
	var cumulative: int = 0
	for points: int in content.balance.treatment_presentation.beat_basis_points:
		cumulative += points
		attempt.beat_end_ticks.append(ceili(float(attempt.work_ticks)*float(cumulative)/10000.0))
	world.facts.inventory.units -= int(attempt.supply_units)
	world.facts.inventory.issues[id] = {"attempt_id":id,"units":attempt.supply_units,"tick":world.facts.sim_tick}
	if world.facts.inventory.has("usage"):
		world.facts.inventory.usage.today_units = int(world.facts.inventory.usage.get("today_units",0))+int(attempt.supply_units)
	world.facts.attempts[id] = attempt
	visit.attempt_ids.append(id)
	_events.append(SimEvent.new(world.sim_tick,"attempt_committed",[visit.id,id],{"supply_units":attempt.supply_units}))
	return attempt

func _start(world: WorldState, visit: Dictionary, kind: String, facility_id: String, staff_ids: Array,
		ticks: int, extra: Dictionary) -> Dictionary:
	var id: String = world.new_id("service")
	var session: Dictionary = {"id":id,"visit_id":visit.id,"kind":kind,"facility_id":facility_id,
		"staff_ids":staff_ids.duplicate(),"resources":[visit.actor_id,facility_id]+staff_ids,
		"total_ticks":ticks,"remaining_ticks":ticks,"start_tick":world.facts.sim_tick}
	session.merge(extra)
	if world.facts.tickets.has(str(visit.get("ticket_id",""))): session.original_ticket = world.facts.tickets[visit.ticket_id].duplicate(true)
	world.facts.sessions[id] = session
	visit.last_service_tick = world.sim_tick
	visit.last_progress_tick = world.sim_tick
	if departments != null:
		departments.call("service_started",world,session)
	_events.append(SimEvent.new(world.sim_tick,"service_started",[visit.id,id],{"kind":kind}))
	if world.facts.adaptations.has(facility_id):
		world.facts.adaptations[facility_id].owner_id = str(extra.get("stay_id",id))
	return session

func _complete_service(world: WorldState, session: Dictionary) -> void:
	if not world.facts.sessions.has(session.id):
		return
	var visit: Dictionary = world.facts.visits[session.visit_id]
	var reservation: Dictionary = world.facts.adaptations.get(session.facility_id,{})
	if reservation.get("owner_id","")==session.id:
		reservation.owner_id = visit.actor_id
	if recruitment!=null:
		var action: String = {"reception":"registration","gp":"gp","spectrum":"test","resonance":"test","outpatient":"outpatient","care":"ward_visit"}.get(session.kind,"")
		if not action.is_empty():
			for staff_id: String in session.staff_ids:
				recruitment.call("service_mood",world,staff_id,action,visit.id,session)
	if departments != null:
		departments.call("service_completed",world,session)
	if session.kind in ["gp","outpatient","surgery","round"]:
		if not visit.has("clinical_participants"):
			visit.clinical_participants = {}
		for staff_id: String in session.staff_ids:
			if world.facts.staff[staff_id].role=="doctor":
				visit.clinical_participants[staff_id] = true
	world.facts.sessions.erase(session.id)
	_events.append(SimEvent.new(world.sim_tick,"service_completed",[visit.id,session.id],{"kind":session.kind}))
	match session.kind:
		"reception":
			visit.registration_receipt = {"id":session.id,"staff_id":session.staff_ids[0],"standard_work_milli":int(session.total_ticks)*100,"completed_tick":world.sim_tick,"practice_awarded":false}
			_queue(world,visit,"gp")
		"gp", "spectrum", "resonance":
			if not visit.evidence_by_source.has(session.kind):
				visit.evidence_by_source[session.kind] = session.evidence
			if session.kind == "gp":
				HospitalLedger.post(world,LedgerEntry.new(visit.id,"consultation",int(session.doctor_fee)),false)
			HospitalLedger.post(world,LedgerEntry.new(visit.id,str(session.kind),int(session.facility_fee)),false)
			_practice(world,session.staff_ids[0],"diagnosis",session.id)
			var evidence: float = 0.0
			for value: Variant in visit.evidence_by_source.values():
				evidence += float(value)
			if research!=null:
				research.call("record_diagnostic_work",world,visit,str(session.kind))
			if evidence >= float(content.balance.diagnosis_threshold):
				_queue(world,visit,"consult")
			elif not visit.evidence_by_source.has("spectrum"):
				_queue(world,visit,"spectrum")
			elif not visit.evidence_by_source.has("resonance"):
				_queue(world,visit,"resonance")
			else:
				visit.waiting_reason = "已完成全部检查但证据未达诊断门槛，友好转诊"
				visit.final_result = "referred"
				visit.phase = "leaving"
		"consult":
			var selected: Dictionary = _select_plan(world,visit,session.staff_ids[0]) if int(world.facts.get("gameplay_version",0))>=1 else {}
			if selected.is_empty() and int(world.facts.get("gameplay_version",0))>=1:
				_queue(world,visit,"consult")
				visit.waiting_reason = "会诊期间资源变化，保留票号等待完整合法方案"
				return
			var plan_id: String = str(selected.get("plan_id",visit.requested_plan_id))
			var protocol: Dictionary = content.definition("treatment_protocols",content.definition("treatment_plans",plan_id).protocol_id)
			visit.plan_decision = {"plan_id":plan_id,"source":"doctor" if int(world.facts.get("gameplay_version",0))>=1 else "director","doctor_id":session.staff_ids[0],
				"revision":int(visit.plan_decision.get("revision",0))+1,"reason":"医生依据当前合法报价与性格评分选择" if not selected.is_empty() else "样板医院既有指定",
				"probability_bp":int(selected.get("probability_bp",0)),"expected_team":selected.get("staff_ids",[]).duplicate()}
			_queue(world,visit,str(protocol.kind))
			if session.has("resume_ticket"):
				world.facts.tickets.erase(visit.ticket_id)
				var original: Dictionary = session.resume_ticket
				original.kind = str(protocol.kind)
				original.service_assigned = false
				original.called_tick = -1
				world.facts.tickets[original.id] = original
				visit.ticket_id = original.id
		"outpatient":
			var attempt: Dictionary = world.facts.attempts[session.attempt_id]
			if environment != null:
				environment.call("record_use",world,"outpatient_completed",session.facility_id,attempt.id)
			HospitalLedger.post(world,LedgerEntry.new(attempt.id,"outpatient",int(attempt.facility_fee)),false)
			_practice(world,session.staff_ids[0],"treatment",session.id)
			_record_plan_experience(world,attempt)
			if int(attempt.recovery_ticks)>0:
				world.facts.ward_stays[attempt.id].phase = "transfer"
				visit.phase = "transfer"
				world.facts.actors[visit.actor_id].posture = "standing"
			else:
				_settle(world,visit,attempt)
		"surgery":
			_start(world,visit,"wake",session.facility_id,session.staff_ids,int(content.balance.clinical.wake_seconds)*10,{"attempt_id":session.attempt_id})
			visit.phase = "wake"
		"wake":
			var attempt: Dictionary = world.facts.attempts[session.attempt_id]
			HospitalLedger.post(world,LedgerEntry.new(attempt.id,"surgery",int(attempt.facility_fee)),false)
			for staff_id: String in session.staff_ids:
				_practice(world,staff_id,"surgery",attempt.id)
			_record_plan_experience(world,attempt)
			var room: Dictionary = world.facts.rooms[world.facts.facilities[session.facility_id].room_id]
			for index: int in 2:
				space.request_move(world,session.staff_ids[index],int(room.floor_id),[int(room.origin[0])+index*2,int(room.origin[1])])
			world.facts.ward_stays[attempt.id].phase = "transfer"
			visit.phase = "transfer"
		"care":
			world.facts.ward_stays[session.stay_id].care_completed = true
			_practice(world,session.staff_ids[0],"care",session.id)
			_release_ward_operator(world,world.facts.ward_stays[session.stay_id],session.staff_ids[0])
		"round":
			var stay: Dictionary = world.facts.ward_stays[session.stay_id]
			var attempt: Dictionary = world.facts.attempts[stay.attempt_id]
			var ward_fee: int = int(attempt.ward_fee) if attempt.has("ward_fee") else content.facility_fee("EQ05","ward")
			HospitalLedger.post(world,LedgerEntry.new(attempt.id,"ward",ward_fee),false)
			_practice(world,session.staff_ids[0],"treatment",visit.id+":round")
			stay.phase = "release_wait"
			_settle(world,visit,attempt)
			_release_ward_operator(world,stay,session.staff_ids[0])
	_mark_clinical_release(world,visit,session)

func _mark_clinical_release(world: WorldState, visit: Dictionary, session: Dictionary) -> void:
	if int(world.facts.get("gameplay_version",0))<1 or not world.facts.adaptations.has(session.facility_id):
		return
	var ticket: Dictionary = world.facts.tickets.get(visit.get("ticket_id",""),{})
	var facility: Dictionary = world.facts.facilities[session.facility_id]
	for staff_id: String in session.staff_ids:
		if _staff_busy(world,staff_id):
			continue
		var staff: Dictionary = world.facts.staff[staff_id]
		# A qualified continuation by this patient keeps its actual operator.
		if facility.definition_id=="FUR02" and staff.role=="doctor":
			if ticket.get("kind","")=="gp" and int(staff.abilities.get("diagnosis",0))>=1 and _schedule_allows(world,staff_id,"gp",visit,session.facility_id):
				continue
			if ticket.get("kind","")=="consult" and int(staff.abilities.get("treatment",0))>=1 and not _select_plan(world,visit,staff_id).is_empty():
				continue
		if ticket.get("kind","")=="outpatient" and facility.definition_id==content.definition("treatment_routines",content.definition("treatment_bindings",visit.binding_id).routine_id).equipment_id and staff.role=="doctor":
			continue
		staff.clinical_release = {"facility_id":session.facility_id,"visit_id":visit.id,"phase":"seek","reason":""}
	_dispatch_clinical_releases(world)

func _dispatch_clinical_releases(world: WorldState) -> void:
	for staff_id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[staff_id]
		if not staff.has("clinical_release"):
			continue
		var release: Dictionary = staff.clinical_release
		var actor: Dictionary = world.facts.actors[staff_id]
		var reservation: Dictionary = world.facts.adaptations.get(release.facility_id,{})
		var completed: bool = false
		if not reservation.is_empty():
			completed = space.at(world,staff_id,int(release.target_floor),release.target_cell) if release.has("target_cell") else not _inside_release_region(actor,reservation)
		if reservation.is_empty() or actor.location.kind=="outside" or completed:
			staff.erase("clinical_release")
			continue
		if world.facts.moves.has(staff_id):
			release.phase = "walking"
			continue
		var busy: bool = false
		for session: Dictionary in world.facts.sessions.values():
			busy = busy or staff_id in session.staff_ids
		for preparation: Dictionary in world.facts.preparations.values():
			busy = busy or staff_id in preparation.staff_ids
		if busy or actor.location.kind!="floor":
			continue
		if release.has("target_cell"):
			release.reason = space.request_move(world,staff_id,int(release.target_floor),release.target_cell)
			continue
		var origin: Vector2i = Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1]))
		var source: Dictionary = world.facts.facilities.get(release.facility_id,{})
		var room: Dictionary = world.facts.rooms.get(source.get("room_id",""),{})
		var search_distance: int = maxi(4,maxi(int(room.size[0]),int(room.size[1]))+space.clearance(actor)+1) if source.get("definition_id","")=="FUR02" and not room.is_empty() else 4
		var selected: Array = []
		for distance: int in range(1,search_distance+1):
			for delta: Vector2i in [Vector2i(0,-distance),Vector2i(distance,0),Vector2i(0,distance),Vector2i(-distance,0)]:
				var point: Vector2i = origin+delta
				var rect: Rect2 = space._actor_rect(actor,Vector2(point))
				# The narrow space beside a GP operator can be a dead end. A doctor
				# handing over that station leaves the room instead of parking there.
				if source.get("definition_id","")=="FUR02" and not room.is_empty() and space.room_contains(room,rect):
					continue
				var intersects: bool = false
				for region: Array in reservation.regions:
					intersects = intersects or rect.intersects(Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3])),false)
				if intersects or not space.static_reason(world,actor,int(actor.location.floor_id),point).is_empty() or space._narrow(world,actor,point) or not space._dynamic_clear(world,staff_id,int(actor.location.floor_id),rect):
					continue
				if space.route(world,staff_id,int(actor.location.floor_id),[point.x,point.y],[],{},true).ok:
					selected = [point.x,point.y]
					break
			if not selected.is_empty(): break
		if selected.is_empty():
			release.phase = "blocked"
			release.reason = "等待真实可达的安全离位空间"
		else:
			release.phase = "walking"
			release.reason = space.request_move(world,staff_id,int(actor.location.floor_id),selected)

func _inside_release_region(actor: Dictionary, reservation: Dictionary) -> bool:
	if actor.location.kind!="floor" or int(actor.location.floor_id)!=int(reservation.floor_id):
		return false
	var rect: Rect2 = space.body_rectangle(actor)
	for region: Array in reservation.regions:
		if rect.intersects(Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3])),false):
			return true
	return false

func _release_ward_operator(world: WorldState, stay: Dictionary, staff_id: String) -> void:
	var bed: Dictionary = space.facility_layout(world,stay.bed_id)
	var ward: Dictionary = world.facts.rooms[bed.room_id]
	var actor: Dictionary = world.facts.actors[staff_id]
	var reservation: Dictionary = world.facts.adaptations.get(stay.bed_id,{})
	var candidates: Array = []
	for y: int in range(int(ward.origin[1]),int(ward.origin[1])+int(ward.size[1])):
		for x: int in range(int(ward.origin[0]),int(ward.origin[0])+int(ward.size[0])):
			var point: Vector2i = Vector2i(x,y)
			var body: Rect2 = space._actor_rect(actor,Vector2(point))
			var blocked: bool = false
			for region: Array in reservation.get("regions",[]):
				blocked = blocked or body.intersects(Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3])).grow(1.0),false)
			for other: Dictionary in world.facts.staff.values():
				var release: Dictionary = other.get("clinical_release",{})
				blocked = blocked or (other.id!=staff_id and release.get("target_cell",[])==[x,y])
			if blocked or not space.static_reason(world,actor,int(bed.floor_id),point).is_empty() or not space._dynamic_clear(world,staff_id,int(bed.floor_id),body):
				continue
			candidates.append({"cell":[x,y],"distance":absf(float(actor.location.cell[0])-x)+absf(float(actor.location.cell[1])-y)})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a.distance<b.distance)
	for candidate: Dictionary in candidates:
		var route: Dictionary = space.route(world,staff_id,int(bed.floor_id),candidate.cell)
		if not route.ok or route.get("status","")=="contention": continue
		world.facts.staff[staff_id].clinical_release = {"facility_id":stay.bed_id,"visit_id":world.facts.attempts[stay.attempt_id].visit_id,"phase":"walking","reason":"","target_floor":int(bed.floor_id),"target_cell":candidate.cell}
		space.request_move(world,staff_id,int(bed.floor_id),candidate.cell)
		return
	world.facts.visits[world.facts.attempts[stay.attempt_id].visit_id].waiting_reason = "等待真实可达且不占床边通路的离位空间"

func _clear_bed_exit(world: WorldState, visit: Dictionary, stay: Dictionary) -> void:
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	if actor.get("posture","standing")!="lying": return
	var bed: Dictionary = space.facility_layout(world,stay.bed_id)
	var origin: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	var target: Vector2 = Vector2(float(bed.patient_cell[0]),float(bed.patient_cell[1]))
	var moving: Dictionary = actor.duplicate(true)
	moving.facing = atan2(target.x-origin.x,target.y-origin.y)
	var swept: Rect2 = space.body_rectangle(actor).merge(space._actor_rect(moving,origin)).merge(space._actor_rect(moving,target))
	for staff_id: String in world.ids("staff"):
		var other: Dictionary = world.facts.actors[staff_id]
		if _staff_busy(world,staff_id) or world.facts.moves.has(staff_id) or other.location.kind!="floor" or int(other.location.floor_id)!=int(bed.floor_id): continue
		if space.body_rectangle(other).intersects(swept,false):
			_release_ward_operator(world,stay,staff_id)

func _start_bed_service(world: WorldState, visit: Dictionary, stay: Dictionary, kind: String, staff_id: String) -> void:
	var bed: Dictionary = space.facility_layout(world,stay.bed_id)
	var staff: Dictionary = world.facts.staff[staff_id]
	var can_work: bool = _can_start(world,staff) if kind=="round" else staff.on_shift and float(staff.energy)>15.0 and str(staff.get("life_task",{}).get("phase","idle")) in ["idle","wait_safe"]
	if not staff.on_shift or not can_work or bed.failed:
		visit.waiting_reason = "等待可以安全执行床边工作的医护"
		return
	if int(world.facts.get("gameplay_version",0))>=1 and not visitors.call("yield_for_care",world,visit.id):
		visit.waiting_reason = "等待实际家属让出医疗操作区"
		return
	if kind == "round" and (int(staff.abilities.diagnosis)<2 or int(staff.abilities.treatment)<1):
		visit.waiting_reason = "等待具备查房资格的医生"
		return
	var index: int = 0 if kind == "care" else 1
	if kind == "round" and space.at(world,stay.nurse_id,int(bed.floor_id),bed.operator_cells[index]):
		_release_ward_operator(world,stay,stay.nurse_id)
		return
	if not space.at(world,staff_id,int(bed.floor_id),bed.operator_cells[index]):
		visit.waiting_reason = space.request_move(world,staff_id,int(bed.floor_id),bed.operator_cells[index])
		return
	var ticks: int = int(stay.get(kind+"_remaining_ticks",_bed_service_ticks(world,visit,kind,staff_id)))
	_start(world,visit,kind,stay.bed_id,[staff_id],ticks,{"stay_id":stay.id})
	if kind == "round":
		stay.phase = "round"
		visit.phase = "round"

func _settle(world: WorldState, visit: Dictionary, attempt: Dictionary) -> void:
	if world.facts.actors[visit.actor_id].get("posture","standing") == "seated":
		world.facts.actors[visit.actor_id].posture = "standing"
		space.sync_actor(world,visit.actor_id)
	if not attempt.result:
		visit.anger = minf(100.0,float(visit.anger)+15.0)
	if attempt.result:
		world.facts.actors[visit.actor_id].erase("body_binding_id")
		space.sync_actor(world,visit.actor_id)
		visit.final_result = "cured"
		HospitalLedger.post(world,LedgerEntry.new(visit.id,"cure",int(attempt.cure_fee)),false)
		visit.phase = "leaving"
	elif visit.attempt_ids.size() < int(content.balance.max_treatment_attempts):
		visit.final_result = "retry"
		if int(world.facts.get("gameplay_version",0))>=1 and visit.plan_decision.get("source","")=="doctor":
			_queue(world,visit,"consult")
		else:
			_queue(world,visit,"surgery" if content.definition("treatment_protocols",content.definition("treatment_plans",attempt.plan_id).protocol_id).kind == "surgery" else "outpatient")
	else:
		visit.final_result = "referred"
		visit.phase = "leaving"
	visit.result_receipt = {"attempt_id":attempt.id,"result":visit.final_result,"tick":world.sim_tick,"feedback_key":attempt.id+":"+str(visit.attempt_ids.size())}

func _record_plan_experience(world: WorldState, attempt: Dictionary) -> void:
	for staff_id: String in attempt.staff_ids:
		var staff: Dictionary = world.facts.staff[staff_id]
		if not staff.has("plan_experience"):
			staff.plan_experience = {}
		if not bool(attempt.get("plan_experience_awarded",false)):
			staff.plan_experience[attempt.plan_id] = int(staff.plan_experience.get(attempt.plan_id,0))+1
	attempt.plan_experience_awarded = true

func _support(world: WorldState, visit: Dictionary, facility: Dictionary, posture: String) -> void:
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	actor.posture = posture
	actor.support_facility_id = facility.id
	if posture != "lying":
		space.sync_actor(world,actor.id)
		return
	actor.location = space.support_location(world,actor,facility)
	actor.facing = 0.0
	space.sync_actor(world,actor.id)

func _dispatch_ward_returns(world: WorldState) -> void:
	# Real bedside work above keeps priority. A shared workbench can be
	# outside the ward, so its completed preparation does not mean arrival.
	for nurse_id: String in world.ids("staff"):
		var nurse: Dictionary = world.facts.staff[nurse_id]
		if nurse.role!="nurse" or not nurse.on_shift or not "q_ward" in nurse.certificates or not _can_start(world,nurse) or _staff_busy(world,nurse_id) or HospitalClinicalDevelopment.safe_busy(world,nurse_id) or world.facts.moves.has(nurse_id):
			continue
		var training: Dictionary = world.facts.get("training_jobs",{}).get(nurse.get("training_job_id",""),{})
		if nurse.get("scheduled_kind","")=="training" or training.get("state","") in ["travelling","working"] or not nurse.get("base_task",{}).is_empty():
			continue
		var ward: Dictionary = world.facts.rooms.get(nurse.get("ward_id",""),{})
		var actor: Dictionary = world.facts.actors[nurse_id]
		if ward.get("kind","")!="ward" or actor.location.kind!="floor":
			continue
		var inside: Rect2 = Rect2(float(ward.origin[0]),float(ward.origin[1]),float(ward.size[0]),float(ward.size[1]))
		if int(actor.location.floor_id)==int(ward.floor_id) and inside.has_point(Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))):
			continue
		var reason: String = space.request_move(world,nurse_id,int(ward.floor_id),_ward_assignment_cell(ward))
		nurse.growth_reason = "前往所属病房" if reason.is_empty() else reason

func _ward_assignment_cell(ward: Dictionary) -> Array:
	return [int(ward.origin[0]),int(ward.origin[1])+int(ward.size[1])-1]

func _ward_command(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	if kind=="clinical_assign_ward":
		var nurse_id: String = str(payload.get("staff_id",""))
		var ward_id: String = str(payload.get("ward_id",""))
		var nurse: Dictionary = world.facts.staff.get(nurse_id,{})
		var ward: Dictionary = world.facts.rooms.get(ward_id,{})
		if nurse.is_empty() or nurse.role!="nurse" or not "q_ward" in nurse.certificates or ward.get("kind","")!="ward" or _staff_busy(world,nurse_id):
			return CommandResult.new(false,"ward_assignment_invalid","请选择可安全交接的合格护士与实际病房",[],world.revision)
		for stay: Dictionary in world.facts.ward_stays.values():
			if stay.nurse_id==nurse_id:
				return CommandResult.new(false,"ward_coverage_committed","该护士仍有实际床位覆盖，须先完成交接",[],world.revision)
		var reason: String = space.request_move(world,nurse_id,int(ward.floor_id),_ward_assignment_cell(ward))
		if not reason.is_empty():
			return CommandResult.new(false,"ward_route_unavailable",reason,[],world.revision)
		nurse.ward_id = ward_id
		return CommandResult.new(true,"applied","",[nurse_id,ward_id],world.revision)
	var visit_id: String = str(payload.get("visit_id",""))
	if not world.facts.visits.has(visit_id):
		return CommandResult.new(false,"visit_missing","原病例已不存在",[],world.revision)
	if kind=="clinical_visit_consent":
		world.facts.visits[visit_id].visitor_consent = bool(payload.get("allow",true))
		return CommandResult.new(true,"applied","",[visit_id],world.revision)
	for stay: Dictionary in world.facts.ward_stays.values():
		if world.facts.attempts[stay.attempt_id].visit_id!=visit_id or not stay.phase in ["recovery","round_wait","round"]:
			continue
		var visit: Dictionary = world.facts.visits[visit_id]
		if kind=="clinical_ward_refer":
			_begin_ward_referral(world,visit,stay)
			return CommandResult.new(true,"applied","",[visit_id,stay.id],world.revision)
		var reason: String = _transfer_stay(world,visit,stay,str(payload.get("bed_id","")))
		return CommandResult.new(reason.is_empty(),"applied" if reason.is_empty() else "transfer_unavailable",reason,[visit_id,stay.id] if reason.is_empty() else [],world.revision)
	return CommandResult.new(false,"ward_stay_missing","患者当前没有可交接的住院床位",[],world.revision)

func _ward_staff_wait_reason(world: WorldState, stay: Dictionary, kind: String) -> String:
	var reason: String = "等待本病房实际护理覆盖" if kind=="care" else "等待具备诊断2级、治疗1级的查房医生"
	if world.sim_tick-int(stay.last_progress_tick)<int(content.balance.clinical.staff_shortage_prompt_seconds)*10:
		return reason
	return reason+("；请调整排班、分配合格病房护士或招聘护理人员" if kind=="care" else "；请调整排班、安排合格查房医生或招聘医生")

func _ward_covering(world: WorldState, stay: Dictionary) -> bool:
	var nurse: Dictionary = world.facts.staff.get(stay.nurse_id,{})
	var bed: Dictionary = world.facts.facilities[stay.bed_id]
	if nurse.is_empty() or not nurse.on_shift or not "q_ward" in nurse.certificates or str(nurse.get("ward_id",""))!=str(bed.room_id) or bed.failed or not bool(nurse.get("base_prepared",true)):
		return false
	if not str(nurse.get("life_task",{}).get("phase","idle")) in ["idle","wait_safe"]:
		return false
	for session: Dictionary in world.facts.sessions.values():
		if stay.nurse_id in session.staff_ids and (session.kind!="care" or world.facts.facilities[session.facility_id].get("room_id","")!=bed.room_id):
			return false
	if not str(nurse.get("active_job_id","")).is_empty():
		return false
	var location: Dictionary = world.facts.actors[stay.nurse_id].location
	var ward: Dictionary = world.facts.rooms[bed.room_id]
	var inside: Rect2 = Rect2(float(ward.origin[0]),float(ward.origin[1]),float(ward.size[0]),float(ward.size[1]))
	if location.kind!="floor" or int(location.floor_id)!=int(bed.floor_id) or not inside.has_point(Vector2(float(location.cell[0]),float(location.cell[1]))):
		return false
	var layout: Dictionary = space.facility_layout(world,stay.bed_id)
	return bool(space.travel_quote(world,stay.nurse_id,int(bed.floor_id),layout.operator_cells[0]).ok)

func _round_candidate(world: WorldState, visit: Dictionary, stay: Dictionary) -> String:
	var order: Array = [stay.round_doctor_id]
	for id: String in world.ids("staff"):
		if not id in order:
			order.append(id)
	var bed: Dictionary = space.facility_layout(world,stay.bed_id)
	for id: String in order:
		var doctor: Dictionary = world.facts.staff.get(id,{})
		if doctor.get("role","")!="doctor" or not doctor.on_shift or not _can_start(world,doctor) or _staff_busy(world,id) or int(doctor.abilities.diagnosis)<2 or int(doctor.abilities.treatment)<1:
			continue
		if not _schedule_allows(world,id,"round",visit,stay.bed_id):
			continue
		var candidate: WorldState = world
		var reservation: Dictionary = world.facts.adaptations.get(stay.bed_id,{})
		if not reservation.is_empty() and not id in reservation.staff_ids:
			candidate = _reservation_candidate(world,[stay.bed_id])
			space.grant_facility_access(candidate,stay.bed_id,id)
		var route: Dictionary = space.route(candidate,id,int(bed.floor_id),bed.operator_cells[1])
		if route.ok and route.get("status","")!="contention":
			space.grant_facility_access(world,stay.bed_id,id)
			return id
	visit.waiting_reason = "等待实际可到床边的合格出院查房医生"
	return ""

func _transfer_stay(world: WorldState, visit: Dictionary, stay: Dictionary, preferred_bed: String = "") -> String:
	if not visitors.call("yield_for_care",world,visit.id):
		return "等待家属实际让开转床通路"
	var old_bed: Dictionary = space.facility_layout(world,stay.bed_id)
	var candidate: WorldState = _reservation_candidate(world,[],[visit.actor_id])
	var actor: Dictionary = candidate.facts.actors[visit.actor_id]
	actor.posture = "standing"
	actor.location.cell = old_bed.patient_cell.duplicate()
	actor.location.height_m = 0.0
	var quote: Dictionary = _compatible_bed(candidate,visit,int(old_bed.floor_id),[],false,preferred_bed)
	if not quote.ok or quote.get("bed_id","")==stay.bed_id or (not preferred_bed.is_empty() and quote.get("bed_id","")!=preferred_bed):
		return "暂无具备真实覆盖与路线的兼容替代床"
	var reason: String = space.reserve_facility(world,quote.bed_id,visit.actor_id,stay.id,[quote.nurse_id,quote.round_doctor_id])
	if not reason.is_empty():
		return reason
	_pause_bed_sessions(world,stay)
	stay.transfer_from_bed_id = stay.bed_id
	if world.facts.adaptations.has(stay.bed_id):
		world.facts.adaptations[stay.bed_id].owner_id = visit.actor_id
	stay.bed_id = quote.bed_id
	stay.nurse_id = quote.nurse_id
	stay.round_doctor_id = quote.round_doctor_id
	stay.escort_id = quote.nurse_id
	stay.phase = "transfer"
	stay.erase("coverage_segment")
	visit.phase = "transfer"
	visit.waiting_reason = "沿原尝试与恢复余量安全转床"
	return ""

func _pause_bed_sessions(world: WorldState, stay: Dictionary) -> void:
	for id: String in world.ids("sessions"):
		var session: Dictionary = world.facts.sessions[id]
		if session.get("stay_id","")==stay.id:
			stay[str(session.kind)+"_remaining_ticks"] = int(session.remaining_ticks)
			world.facts.sessions.erase(id)

func _begin_ward_referral(world: WorldState, visit: Dictionary, stay: Dictionary) -> void:
	_pause_bed_sessions(world,stay)
	visitors.call("yield_for_care",world,visit.id)
	stay.phase = "referral_release"
	visit.phase = "ward_referral"
	visit.waiting_reason = "无进展，沿真实床边出口安全转交外部照护"

func _profile(visit: Dictionary) -> Dictionary:
	return content.catalog.profiles[content.definition("diseases",visit.disease_id).profile]

func _gp_work_ticks(visit: Dictionary, staff: Dictionary, effective: float) -> int:
	var expression_rate: float = {"clear":1.0,"vague":1.8,"off_topic":2.4}.get(visit.expression,1.0)
	var personality: Dictionary = content.definition("patient_personalities",visit.personality_id)
	var seconds: float = float(content.balance.gp_seconds)*expression_rate*float(personality.speech_multiplier)*(1.0+float(visit.anger)/200.0)
	seconds *= 1.0+float(content.balance.wellbeing.fatigue_work_multiplier_per_point)*float(staff.fatigue)
	seconds /= 1.0+0.05*(int(staff.abilities.diagnosis)-1)+0.15*effective
	return ceili(clampf(seconds,8.0,60.0)*10)

func _availability(world: WorldState) -> Dictionary:
	return space.read_view(world,"clinical_availability",_build_availability.bind(world))

func _build_availability(world: WorldState) -> Dictionary:
	var result: Dictionary = {"staff":{},"facilities":{},"preparations":{},"preparation_staff":{}}
	for actor: Dictionary in world.facts.actors.values():
		var id: String = str(actor.get("support_facility_id",""))
		if not id.is_empty() and space.overlaps_facility(world,actor.id,id): result.facilities[id] = true
	for session: Dictionary in world.facts.sessions.values():
		result.facilities[session.facility_id] = true
		for id: String in session.staff_ids: result.staff[id] = true
	for stay: Dictionary in world.facts.ward_stays.values():
		if stay.phase=="transfer": result.staff[stay.escort_id] = true
	for guidance: Dictionary in world.facts.get("departments",{}).get("guidance",{}).values():
		if guidance.get("phase","") in ["working","travel"]:
			for id: String in guidance.get("staff_ids",[]): result.staff[id] = true
	for preparation: Dictionary in world.facts.preparations.values():
		result.preparations[preparation.facility_id] = preparation.id
		for id: String in preparation.staff_ids: result.preparation_staff[id] = preparation.id
	return result

func _facility_busy(world: WorldState, id: String, except_preparation: String = "", availability: Dictionary = {}) -> bool:
	if not availability.is_empty(): return availability.facilities.has(id) or availability.preparations.has(id) and availability.preparations[id]!=except_preparation
	for actor_id: String in world.facts.actors:
		var actor: Dictionary = world.facts.actors[actor_id]
		if actor.get("support_facility_id","")==id and space.overlaps_facility(world,actor_id,id):
			return true
	for session: Dictionary in world.facts.sessions.values():
		if session.facility_id == id:
			return true
	for preparation: Dictionary in world.facts.preparations.values():
		if preparation.facility_id == id and preparation.id != except_preparation:
			return true
	return false

func _staff_busy(world: WorldState, id: String, except_preparation: String = "", availability: Dictionary = {}) -> bool:
	if world.facts.staff.get(id,{}).has("clinical_release"):
		return true
	if not str(world.facts.staff.get(id,{}).get("active_job_id","")).is_empty():
		return true
	if not availability.is_empty(): return availability.staff.has(id) or availability.preparation_staff.has(id) and availability.preparation_staff[id]!=except_preparation
	for guidance: Dictionary in world.facts.get("departments",{}).get("guidance",{}).values():
		if guidance.get("phase","") in ["working","travel"] and id in guidance.get("staff_ids",[]):
			return true
	for stay: Dictionary in world.facts.ward_stays.values():
		if stay.phase=="transfer" and stay.escort_id==id:
			return true
	for session: Dictionary in world.facts.sessions.values():
		if id in session.staff_ids:
			return true
	for preparation: Dictionary in world.facts.preparations.values():
		if id in preparation.staff_ids and preparation.id != except_preparation:
			return true
	return false

func staff_busy(world: WorldState, id: String) -> bool:
	return _staff_busy(world,id)

static func equipment_uses(world: WorldState) -> Dictionary:
	var uses: Dictionary = {}
	for session: Dictionary in world.facts.sessions.values():
		uses[session.facility_id] = {"occupied":true,"critical_commitment":false}
	for preparation: Dictionary in world.facts.preparations.values():
		for id: String in [preparation.facility_id,str(preparation.get("bed_id",""))]:
			if not id.is_empty(): uses[id] = {"occupied":true,"critical_commitment":false}
	for stay: Dictionary in world.facts.ward_stays.values():
		var critical: bool = stay.phase in ["reserved","transfer","recovery","round_wait","round"]
		uses[stay.bed_id] = {"occupied":true,"critical_commitment":critical or uses.get(stay.bed_id,{}).get("critical_commitment",false)}
	return uses

static func equipment_use(world: WorldState, facility_id: String) -> Dictionary:
	return equipment_uses(world).get(facility_id,{"occupied":false,"critical_commitment":false})

func _available_supplies(world: WorldState, except_preparation: String = "") -> int:
	var units: int = int(world.facts.inventory.units)
	for preparation: Dictionary in world.facts.preparations.values():
		if preparation.id != except_preparation:
			units -= int(preparation.get("supply_units",0))
	return units

func _facility_unavailable(facility: Dictionary) -> bool:
	return bool(facility.failed) or bool(facility.get("pending_failure",false)) or bool(facility.get("stop_new_service",false)) or bool(facility.get("maintenance_block",false)) or bool(facility.get("upgrading_block",false)) or float(facility.condition)<=float(content.balance.equipment.get("stop_new_service_threshold",0.0))

func _talent_rate(world: WorldState, staff_id: String, action: String, visit: Dictionary) -> float:
	return float(recruitment.call("work_rate",world,staff_id,action,visit.actor_id)) if recruitment!=null else 1.0

func _schedule_allows(world: WorldState, staff_id: String, kind: String, visit: Dictionary, facility_id: String) -> bool:
	if scheduler==null or world.facts.staff[staff_id].role!="doctor":
		return true
	var assignment: Dictionary = scheduler.call("assignment",world,staff_id,int(scheduler.call("shift_index",world)))
	var duty: String = "surgery" if kind=="surgery" else "round" if kind=="round" else "outpatient"
	if str(assignment.kind)!=duty:
		if not (kind=="round" and assignment.kind=="outpatient" and bool(world.facts.get("allow_outpatient_rounds",false))):
			return false
		return true
	var pools: Array = assignment.get("pools",[])
	if pools.is_empty(): return true
	var facility: Dictionary = world.facts.facilities[facility_id]
	var targets: Array = [facility_id,str(facility.get("room_id",""))]
	if kind in ["gp","spectrum","resonance","consult"]:
		targets.append("diagnosis")
	if kind in ["outpatient","consult"]:
		targets.append(content.definition("treatment_routines",content.definition("treatment_bindings",visit.binding_id).routine_id).specialty_id)
		targets.append(str(visit.get("department_id","")))
	if kind=="surgery": targets.append("surgery")
	if kind=="round": targets.append("round")
	for pool: String in pools:
		if not pool.is_empty() and pool in targets: return true
	return false

func _reference_assignment_allows(world: WorldState, staff_id: String, kind: String, visit: Dictionary, facility_id: String) -> bool:
	if scheduler==null: return true
	if world.facts.staff[staff_id].role=="doctor":
		return _schedule_allows(world,staff_id,kind,visit,facility_id)
	var assignment: Dictionary = scheduler.call("assignment",world,staff_id,int(scheduler.call("shift_index",world)))
	return assignment.kind=="work"

func shortage_requests(world: WorldState) -> Array:
	var result: Array = []
	var candidate: WorldState
	for ticket_id: String in world.ids("tickets"):
		var ticket: Dictionary = world.facts.tickets[ticket_id]
		if not ticket.kind in ["outpatient","surgery"]:
			continue
		var visit: Dictionary = world.facts.visits[ticket.visit_id]
		var plan_id: String = str(visit.plan_decision.get("plan_id",visit.requested_plan_id))
		var plan: Dictionary = content.definition("treatment_plans",plan_id)
		var protocol: Dictionary = content.definition("treatment_protocols",str(plan.get("protocol_id","")))
		if protocol.is_empty() or _available_supplies(world,visit.id)>=_required_supplies(visit,protocol):
			continue
		if candidate==null:
			candidate = WorldState.new(world.freeze())
			for staff: Dictionary in candidate.facts.staff.values():
				staff.supply_strike = false
		var quote: Dictionary = plan_quote(candidate,visit.id,plan_id,{"ignore_supplies":true})
		if quote.ok and _available_supplies(world,visit.id)<int(quote.supply_units):
			result.append({"ticket_id":ticket_id,"visit_id":visit.id,"staff_ids":quote.staff_ids.duplicate(),"units":int(quote.supply_units)})
	return result

func arrival_readiness(world: WorldState, binding_id: String, complex_case: bool = false, explain: bool = true) -> Dictionary:
	var candidate: Dictionary = _arrival_candidate(world,binding_id,complex_case)
	if not candidate.get("ok",false):
		return candidate
	var quotes: Array = []
	var executable: bool = false
	var reasons: PackedStringArray = []
	if not HospitalResearch.disease_unlocked(world,content,candidate.visit.disease_id):
		reasons.append("病例研究尚未完成")
	for plan: Dictionary in content.catalog.treatment_plans:
		if plan.disease_id!=candidate.visit.disease_id:
			continue
		var quote: Dictionary = plan_quote(candidate.world,candidate.visit.id,plan.id,{"structural_only":true,"ignore_supplies":true})
		quotes.append(quote)
		executable = executable or bool(quote.ok)
		if executable and not explain: break
	for kind: String in ["reception","gp"]:
		if service_candidates(candidate.world,candidate.visit,kind,true).is_empty():
			reasons.append(_missing_service_reason(candidate.world,candidate.visit,kind))
	var diagnostics_ok: bool = false
	var diagnostic_query: Dictionary = {"candidates":{},"reference_schedule":false}
	for pair: Dictionary in service_candidates(candidate.world,candidate.visit,"gp",true):
		if _build_reference_diagnostic_stages(candidate.world,candidate.visit,pair,diagnostic_query).ok:
			diagnostics_ok = true
			break
	if not diagnostics_ok: reasons.append("全部合法检查仍未达到诊断阈值")
	if not executable:
		for quote: Dictionary in quotes:
			var plan_name: String = str(content.definition("treatment_plans",quote.plan_id).get("name",quote.plan_id))
			reasons.append(plan_name+"："+str(quote.reason))
	return {"ok":executable and reasons.is_empty(),"reason":"；".join(reasons),"plans":quotes}

func _arrival_candidate(world: WorldState, binding_id: String, complex_case: bool) -> Dictionary:
	var binding: Dictionary = content.definition("treatment_bindings",binding_id)
	if binding.is_empty():
		return {"ok":false,"reason":"病例绑定不存在"}
	# Reference quotes are synchronous and read-only. Own only the collections
	# that receive the hypothetical patient; all existing facts stay shared.
	var facts: Dictionary = world.facts.duplicate()
	facts.actors = world.facts.actors.duplicate()
	facts.visits = world.facts.visits.duplicate()
	var candidate: WorldState = WorldState.new(facts)
	var entry: Dictionary = world.facts.get("entry",{"floor_id":1,"cell":[47,93]})
	var actor_id: String = "reference_patient"
	var visit_id: String = "reference_visit"
	candidate.facts.actors[actor_id] = {"id":actor_id,"name":"参考患者","species_id":binding.species_id,"body_binding_id":binding.id,
		"location":{"kind":"floor","floor_id":int(entry.floor_id),"cell":entry.cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
	candidate.facts.visits[visit_id] = {"id":visit_id,"actor_id":actor_id,"disease_id":binding.disease_id,"binding_id":binding.id,"complex":complex_case,
		"requested_plan_id":"P_"+str(binding.disease_id)+"_COMMON","plan_decision":{},"attempt_ids":[],"evidence_by_source":{},"expression":"clear","personality_id":"PP01","anger":15.0,"doctor_fee_quote":-1,"phase":"arrival","ticket_id":""}
	var actor: Dictionary = candidate.facts.actors[actor_id]
	space.begin_route_query(candidate)
	var reason: String = space.static_reason(candidate,actor,int(entry.floor_id),Vector2i(int(entry.cell[0]),int(entry.cell[1])))
	if reason.is_empty() and departments!=null:
		var eligible: Array = departments.call("eligible_departments",candidate,visit_id,true)
		if eligible.is_empty(): reason = "没有具备本病例完整路线的开放科室"
		else: candidate.facts.visits[visit_id].department_id = eligible[0].id
	space.end_route_query()
	return {"ok":reason.is_empty(),"reason":reason,"world":candidate,"visit":candidate.facts.visits[visit_id]}

func reference_demand(world: WorldState, binding_id: String, complex_case: bool = false, _shift: int = 0, query: Variant = null) -> Dictionary:
	if query==null: query = {}
	var transport: Dictionary = query.get("transport_basis",{})
	var identity: Array = [world.get_instance_id(),world.revision,_shift]
	if query.get("identity",[])!=identity:
		query.clear()
		query.identity = identity
		query.candidates = {}
		query.geometry = {"nominal":true}
	if not transport.is_empty(): query.geometry.transport_basis = transport
	query.geometry.transport_dependent = false
	# Diagnostic prefixes are shared by this case and its retries only.
	query.diagnostics = {}
	query.diagnostic_stages = {}
	query.consultations = {}
	space.begin_route_query(world,query.geometry)
	var options: Dictionary = _reference_options(world,binding_id,complex_case,_shift,{},{},query)
	var result: Dictionary = {"ok":false,"reason":options.get("reason",""),"bundles":[]}
	if options.ok:
		space.begin_route_query(options.world,query.geometry)
		result = _reference_model(options,binding_id,complex_case,_shift)
		space.end_route_query()
	result.transport_dependent = bool(query.geometry.get("transport_dependent",false))
	space.end_route_query()
	return result

func _reference_options(world: WorldState, binding_id: String, complex_case: bool, shift: int, prior_quote: Dictionary = {}, shared: Dictionary = {}, query: Dictionary = {}) -> Dictionary:
	var reference: Dictionary
	if shared.is_empty():
		reference = _arrival_candidate(world,binding_id,complex_case)
	else:
		# Retry input is the same proven reference patient and shift. Own only
		# its attempt marker and the prior team's experience changes.
		var facts: Dictionary = world.facts.duplicate()
		facts.visits = world.facts.visits.duplicate()
		facts.visits[shared.visit.id] = shared.visit.duplicate(true)
		facts.staff = world.facts.staff.duplicate()
		for staff_id: String in prior_quote.staff_ids:
			facts.staff[staff_id] = world.facts.staff[staff_id].duplicate()
			facts.staff[staff_id].plan_experience = world.facts.staff[staff_id].get("plan_experience",{}).duplicate()
		reference = {"ok":true,"world":WorldState.new(facts),"visit":facts.visits[shared.visit.id]}
	if not reference.ok:
		return {"ok":false,"reason":reference.reason,"bundles":[]}
	var candidate: WorldState = reference.world
	var visit: Dictionary = reference.visit
	if not query.has("plans"): query.plans = {}
	if not query.plans.has(visit.disease_id):
		var plans: Dictionary = {"outpatient":[],"surgery":[]}
		for plan: Dictionary in content.catalog.treatment_plans:
			if plan.disease_id!=visit.disease_id: continue
			plans[content.definition("treatment_protocols",plan.protocol_id).kind].append(plan)
		query.plans[visit.disease_id] = plans
	if shared.is_empty(): candidate.facts.staff = world.facts.staff.duplicate()
	var shift_ticks: int = ceili(float(content.balance.schedule.shift_seconds)/WorldState.TICK_SECONDS)
	candidate.facts.sim_tick = (world.sim_tick/WorldState.TICKS_PER_DAY)*WorldState.TICKS_PER_DAY+clampi(shift,0,int(content.balance.schedule.shifts_per_day)-1)*shift_ticks
	# A reference removes temporary contention while retaining the actual built
	# geometry, bodies, qualifications and the original shift budgets.
	candidate.facts.sessions = {}
	candidate.facts.preparations = {}
	candidate.facts.ward_stays = {}
	candidate.facts.moves = HospitalTransit.reference_movements(world)
	if shared.is_empty():
		for staff_id: String in candidate.facts.staff:
			var staff: Dictionary = world.facts.staff[staff_id].duplicate()
			candidate.facts.staff[staff_id] = staff
			staff.energy = 100.0
			staff.fatigue = 0.0
			staff.on_shift = true
			staff.block_new_work = false
			staff.base_prepared = true
			staff.supply_strike = false
			staff.life_task = {"phase":"idle"}
	if not prior_quote.is_empty():
		visit.attempt_ids = ["reference_completed_attempt"]
		for staff_id: String in prior_quote.staff_ids:
			var staff: Dictionary = candidate.facts.staff[staff_id]
			if not staff.has("plan_experience"):
				staff.plan_experience = {}
			staff.plan_experience[prior_quote.plan_id] = int(staff.plan_experience.get(prior_quote.plan_id,0))+1
	var receptions: Array = shared.get("receptions",[])
	var diagnostics: Array = shared.get("diagnostics",[])
	var consultations: Array = shared.get("consultations",[])
	var outpatient: Array = shared.get("outpatient",[])
	var bed_quotes: Dictionary = shared.get("bed_quotes",{})
	# One sealed case/shift owns both attempts' complete physical quotes.
	# First-team experience changes recommendation scores, not these quotes.
	var physical: Dictionary = shared.get("physical",{"outpatient":{},"surgery":{}})
	space.begin_route_query(candidate,query.get("geometry",{}))
	if shared.is_empty():
		receptions = _reference_candidates(candidate,visit,"reception",query)
		diagnostics = _reference_candidates(candidate,visit,"gp",query)
		consultations = _reference_candidates(candidate,visit,"consult",query)
	if receptions.is_empty() or diagnostics.is_empty():
		space.end_route_query()
		return {"ok":false,"reason":"缺少实际接待或初诊资源","bundles":[]}
	if shared.is_empty(): outpatient = _reference_candidates(candidate,visit,"outpatient",query)
	var terminal_quotes: Array = []
	for pair: Dictionary in outpatient:
		# A retry remains with the first treating doctor. Other doctors' scores
		# cannot affect that doctor's independent plan selection.
		if not prior_quote.is_empty() and pair.staff_id!=prior_quote.get("consulting_doctor_id",prior_quote.staff_ids[0]):
			continue
		if not _reference_assignment_allows(candidate,pair.staff_id,"outpatient",visit,pair.facility_id):
			continue
		for plan: Dictionary in query.plans[visit.disease_id].outpatient:
			var allowed: bool = true
			for research_id: String in plan.requires_research:
				allowed = allowed and research_id in candidate.facts.research
			if not allowed:
				continue
			var physical_key: Array = [not prior_quote.is_empty(),pair.staff_id,pair.facility_id,plan.id]
			if not physical.outpatient.has(physical_key):
				physical.outpatient[physical_key] = _outpatient_quote(candidate,visit,candidate.facts.staff[pair.staff_id],candidate.facts.facilities[pair.facility_id],plan.id,true,true,true,bed_quotes)
			var quote: Dictionary = physical.outpatient[physical_key].duplicate()
			if not quote.ok:
				continue
			quote.estimated_total_ticks = int(quote.work_ticks)+int(quote.recovery_ticks)
			quote.score = _reference_score(candidate,visit,quote,pair.staff_id)
			quote.consulting_doctor_id = pair.staff_id
			terminal_quotes.append(quote)
	var consulting_doctors: Dictionary = {}
	for pair: Dictionary in consultations:
		if int(candidate.facts.staff[pair.staff_id].abilities.treatment)<2: continue
		if not prior_quote.is_empty() and pair.staff_id!=prior_quote.get("consulting_doctor_id",prior_quote.staff_ids[0]): continue
		consulting_doctors[pair.staff_id] = true
	for plan: Dictionary in query.plans[visit.disease_id].surgery:
		var physical_key: Array = [not prior_quote.is_empty(),plan.id]
		if not physical.surgery.has(physical_key):
			var quotes: Array = []
			plan_quote(candidate,visit.id,plan.id,{"structural_only":true,"ignore_supplies":true,"reference_schedule":true,"bed_quotes":bed_quotes,"alternatives":quotes})
			physical.surgery[physical_key] = quotes
		var alternatives: Array = physical.surgery[physical_key]
		for quote: Dictionary in alternatives:
			quote.plan_id = plan.id
			for doctor_id: String in consulting_doctors:
				var recommended: Dictionary = quote.duplicate()
				recommended.consulting_doctor_id = doctor_id
				recommended.score = _reference_score(candidate,visit,recommended,doctor_id)
				terminal_quotes.append(recommended)
	var grouped: Dictionary = {}
	for terminal: Dictionary in terminal_quotes:
		var doctor_id: String = str(terminal.consulting_doctor_id)
		if not grouped.has(doctor_id): grouped[doctor_id] = []
		grouped[doctor_id].append(terminal)
	var selected_plans: Dictionary = {}
	for doctor_id: String in grouped:
		var options: Array = grouped[doctor_id]
		var selection: Dictionary = _choose_plan(options,str(world.facts.get("plan_strategy","doctor")))
		selected_plans[doctor_id] = selection.plan_id
	terminal_quotes = terminal_quotes.filter(func(terminal: Dictionary) -> bool:
		return selected_plans.get(str(terminal.consulting_doctor_id),"")==terminal.plan_id)
	# Bed alternatives do not change this quote's PlanScore. Expand only the
	# selected plan, retaining every legal bed for its actual resource model.
	var selected_terminals: Array = []
	for terminal: Dictionary in terminal_quotes: selected_terminals.append_array(_reference_terminal_beds(candidate,visit,terminal,bed_quotes))
	terminal_quotes = selected_terminals
	space.end_route_query()
	return {"ok":not terminal_quotes.is_empty(),"reason":"没有完整临床参考资源束" if terminal_quotes.is_empty() else "",
		"world":candidate,"visit":visit,"terminals":terminal_quotes,"receptions":receptions,"diagnostics":diagnostics,"consultations":consultations,"outpatient":outpatient,"bed_quotes":bed_quotes,"physical":physical,"query":query}

func _reference_terminal_beds(world: WorldState, visit: Dictionary, quote: Dictionary, cache: Dictionary) -> Array:
	if int(quote.recovery_ticks)==0: return [quote]
	var floor_id: int = int(world.facts.facilities[quote.facility_id].floor_id)
	var nurses: Array = []
	for id: String in quote.staff_ids:
		if world.facts.staff[id].role=="nurse": nurses.append(id)
	var key: String = JSON.stringify(["alternatives",floor_id,nurses])
	if not cache.has(key):
		var beds: Array = []
		_compatible_bed(world,visit,floor_id,quote.staff_ids,true,"",true,beds)
		cache[key] = beds
	var result: Array = []
	for bed: Dictionary in cache[key]:
		var alternative: Dictionary = quote.duplicate()
		alternative.merge(bed,true)
		result.append(alternative)
	return result

func _reference_candidates(world: WorldState, visit: Dictionary, kind: String, query: Dictionary) -> Array:
	var routine: Dictionary = content.definition("treatment_routines",content.definition("treatment_bindings",visit.binding_id).routine_id)
	var key: String = JSON.stringify([space.body(world.facts.actors[visit.actor_id]),kind,visit.get("department_id","") if kind!="reception" else "",
			routine.equipment_id if kind=="outpatient" else "",routine.specialty_id if kind in ["outpatient","consult"] else "",query.get("reference_schedule",true)])
	if not query.candidates.has(key): query.candidates[key] = service_candidates(world,visit,kind,true,bool(query.get("reference_schedule",true)))
	return query.candidates[key]

func _reference_model(options: Dictionary, binding_id: String, complex_case: bool, shift: int) -> Dictionary:
	options.query.component_batch = []
	var groups: Dictionary = {}
	var bases: Array = []
	var concrete: Array = []
	var representatives: Dictionary = {}
	var representative_parts: Array = []
	var retries: Dictionary = {}
	var terminal_stages: Array = ["outpatient","surgery","surgery_setup","transfer","bed","care","round"]
	for terminal: Dictionary in options.terminals:
		var team_key: String = JSON.stringify(terminal.staff_ids)
		var diagnostic_group: String = "diagnostic:"+team_key
		if not groups.has(diagnostic_group):
			groups[diagnostic_group] = _reference_diagnostics(options,terminal)
		if groups[diagnostic_group].is_empty(): continue
		var first_consult_group: String = "consult:"+str(terminal.consulting_doctor_id)
		if not groups.has(first_consult_group): groups[first_consult_group] = _reference_consultations(options,terminal)
		if groups[first_consult_group].is_empty(): continue
		var first_diagnostic: Dictionary = groups[diagnostic_group][0].diagnostic
		# The model consumes terminal work; diagnostic, registration and
		# consultation work already have independent complete choice groups.
		var first: Dictionary = _reference_terminal_bundle(options.world,options.visit,options.receptions[0],first_diagnostic,terminal,{},options.query)
		if not first.ok: continue
		var base: Dictionary = _reference_component(first,terminal_stages,{"n":"1","d":"1"},options.query.component_batch)
		base.choices = ["reception",diagnostic_group,first_consult_group]
		base.structural_choices = [diagnostic_group,first_consult_group]
		if not groups.has("reception"):
			groups.reception = []
			for reception: Dictionary in options.receptions:
				var registration: Dictionary = {"stage_resources":{},"staff_ids":terminal.staff_ids,"structural_resources":[]}
				_reference_stage(registration.stage_resources,"reception",["staff:"+str(reception.staff_id),"facility:"+str(reception.facility_id)],ceili(float(content.balance.reception_seconds)*10/_talent_rate(options.world,reception.staff_id,"registration",options.visit)))
				groups.reception.append(_reference_component(registration,["reception"],{"n":"1","d":"1"},options.query.component_batch))
		var representative_retry: Dictionary = {}
		if int(content.balance.max_treatment_attempts)>1:
			# Only the continuing doctor's experience is read by PlanScore.
			# Keep graph IDs/probability weights independent of this options key.
			var option_key: Array = _reference_retry_context(terminal)
			if not retries.has(option_key):
				retries[option_key] = _reference_options(options.world,binding_id,complex_case,shift,terminal,options,options.query)
			var retry_options: Dictionary = retries[option_key]
			if retry_options.ok:
				var retry_group: String = _reference_retry_group(terminal)
				if not groups.has(retry_group):
					groups[retry_group] = []
					var weight: Dictionary = ReferenceFraction.make(10000-int(terminal.probability_bp),10000)
					for retry_terminal: Dictionary in retry_options.terminals:
						var consult_group: String = retry_group+":consult:"+str(retry_terminal.consulting_doctor_id)
						if not groups.has(consult_group):
							groups[consult_group] = _reference_consultations(retry_options,retry_terminal,weight)
						if groups[consult_group].is_empty(): continue
						var retry_core: Dictionary = _reference_terminal_bundle(retry_options.world,retry_options.visit,retry_options.receptions[0],retry_options.diagnostics[0],retry_terminal,{},retry_options.query)
						if not retry_core.ok: continue
						var retry_part: Dictionary = _reference_component(retry_core,terminal_stages,weight,options.query.component_batch)
						retry_part.choices = [consult_group]
						if groups[retry_group].is_empty():
							retry_part.representative = {"core":retry_core,"consultation":groups[consult_group][0].consultation}
							representative_parts.append(retry_part)
						groups[retry_group].append(retry_part)
				if not groups[retry_group].is_empty():
					base.choices.append(retry_group)
					representative_retry = groups[retry_group][0].representative
		bases.append(base)
		var representative_key: String = JSON.stringify([first.plan_id,representative_retry.get("core",{}).get("plan_id",first.plan_id)])
		if not representatives.has(representative_key):
			var full: Dictionary = _reference_bundle(options.world,options.visit,options.receptions[0],first_diagnostic,terminal,options.query,groups[first_consult_group][0].consultation)
			if not full.ok: return {"ok":false,"reason":full.reason,"bundles":[]}
			representatives[representative_key] = true
			if representative_retry.is_empty(): concrete.append(full)
			else:
				var retry: Dictionary = representative_retry.core.duplicate()
				retry.stage_resources = retry.stage_resources.duplicate()
				var consultation: Dictionary = representative_retry.consultation
				_reference_stage(retry.stage_resources,"consult",["staff:"+str(consultation.staff_id),"facility:"+str(consultation.facility_id)],ceili(float(content.balance.clinical.consult_seconds)*10))
				concrete.append(_reference_with_retry(full,retry,int(terminal.probability_bp)))
	# Equal-flow equations in the capacity solver join these independent
	# choices. No legal alternative is truncated or replaced by a faster plan.
	for part: Dictionary in representative_parts: part.erase("representative")
	var batch: Array = options.query.component_batch
	var requests: Array = []
	for item: Dictionary in batch: requests.append({"stages":item.stages,"weight":item.weight})
	var assembled: Dictionary = PlatformArrivalMath.aggregate_components(requests)
	options.query.erase("component_batch")
	if assembled.has("error"): return {"ok":false,"reason":assembled.error,"bundles":[]}
	for index: int in batch.size(): batch[index].target.merge(assembled.components[index],true)
	return {"ok":not bases.is_empty(),"reason":"" if not bases.is_empty() else "没有完整临床参考资源束","bundles":concrete,"model":{"bundles":bases,"choice_groups":groups}}

func _reference_diagnostics(options: Dictionary, terminal: Dictionary) -> Array:
	var key: String = JSON.stringify([options.visit.binding_id,options.visit.complex,terminal.staff_ids])
	if not options.query.diagnostics.has(key):
		var prefixes: Array = []
		for diagnostic: Dictionary in options.diagnostics:
			if diagnostic.staff_id in terminal.staff_ids: continue
			var initial: Dictionary = _reference_diagnostic_stages(options.world,options.visit,diagnostic,options.query)
			if not initial.ok: continue
			for stages: Dictionary in initial.variants:
				var full: Dictionary = {"staff_ids":terminal.staff_ids,"stage_resources":stages}
				full.merge(_reference_resource_maps(stages,[]))
				var prefix: Dictionary = _reference_component(full,["gp","spectrum","resonance"],{"n":"1","d":"1"},options.query.component_batch)
				prefix.diagnostic = diagnostic
				prefixes.append(prefix)
		options.query.diagnostics[key] = prefixes
	return options.query.diagnostics[key]

func _reference_consultations(options: Dictionary, terminal: Dictionary, weight: Dictionary = {"n":"1","d":"1"}) -> Array:
	var doctor_id: String = str(terminal.consulting_doctor_id)
	if not options.query.consultations.has(doctor_id):
		var prefixes: Array = []
		for consultation: Dictionary in options.consultations:
			if consultation.staff_id!=doctor_id: continue
			var stages: Dictionary = {}
			_reference_stage(stages,"consult",["staff:"+doctor_id,"facility:"+str(consultation.facility_id)],ceili(float(content.balance.clinical.consult_seconds)*10))
			var full: Dictionary = {"staff_ids":[],"stage_resources":stages}
			full.merge(_reference_resource_maps(stages,[]))
			var prefix: Dictionary = _reference_component(full,["consult"],{"n":"1","d":"1"},options.query.component_batch)
			prefix.consultation = consultation
			prefixes.append(prefix)
		options.query.consultations[doctor_id] = prefixes
	if weight.n=="1" and weight.d=="1": return options.query.consultations[doctor_id]
	var result: Array = []
	for prefix: Dictionary in options.query.consultations[doctor_id]:
		var part: Dictionary = _reference_component(prefix,["consult"],weight,options.query.component_batch)
		part.consultation = prefix.consultation
		result.append(part)
	return result

func _reference_component(full: Dictionary, stages: Array, weight: Dictionary = {"n":"1","d":"1"}, batch: Variant = null) -> Dictionary:
	var selected: Dictionary = {}
	for stage: String in stages:
		if full.stage_resources.has(stage): selected[stage] = full.stage_resources[stage]
	# One numerical boundary per component: GMP parses each amount once and
	# retains exact intermediate values through weighting and aggregation.
	var result: Dictionary = PlatformArrivalMath.aggregate_stages(selected,weight) if batch==null else {"stage_resources":selected}
	if batch!=null: batch.append({"stages":selected,"weight":weight,"target":result})
	result.structural_resources = []
	result.staff_ids = full.staff_ids
	if "bed" in stages:
		for field: String in ["bed_id","ward_id","coverage_nurse_id"]:
			if full.has(field): result[field] = full[field]
	for stage: Dictionary in selected.values():
		for resource_id: String in stage:
			if resource_id in full.structural_resources and not resource_id in result.structural_resources: result.structural_resources.append(resource_id)
	result.structural_resources.sort()
	return result

func _reference_retry_context(terminal: Dictionary) -> Array:
	return [terminal.plan_id,terminal.consulting_doctor_id,terminal.consulting_doctor_id in terminal.staff_ids]

func _reference_retry_group(terminal: Dictionary) -> String:
	return "retry:"+JSON.stringify([_reference_retry_context(terminal),terminal.probability_bp])

func _reference_score(world: WorldState, _visit: Dictionary, quote: Dictionary, doctor_id: String) -> float:
	var staff: Dictionary = world.facts.staff[doctor_id]
	var personality: Dictionary = content.definition("doctor_personalities",str(staff.get("personality_id","DP01")))
	var protocol: Dictionary = content.definition("treatment_protocols",content.definition("treatment_plans",quote.plan_id).protocol_id)
	var completed: int = int(staff.get("plan_experience",{}).get(quote.plan_id,0))
	var weights: Dictionary = personality.weights
	return float(weights.success)*float(quote.probability_bp)/100.0-float(weights.time)*float(quote.get("estimated_total_ticks",quote.work_ticks))/100.0-float(weights.burden)*float(protocol.burden)+float(weights.familiarity)*mini(int(content.balance.clinical.score_familiarity_cap),completed/int(content.balance.clinical.score_familiarity_cases_per_band))+float(weights.novelty)*(1 if completed==0 else 0)+float(weights.team)

func _reference_bundle(world: WorldState, visit: Dictionary, reception: Dictionary, diagnostic: Dictionary, quote: Dictionary, query: Dictionary, consultation: Dictionary = {}) -> Dictionary:
	var stages: Dictionary = {}
	_reference_stage(stages,"reception",["staff:"+str(reception.staff_id),"facility:"+str(reception.facility_id)],ceili(float(content.balance.reception_seconds)*10/_talent_rate(world,reception.staff_id,"registration",visit)))
	var prefix: Dictionary = _reference_diagnostic_stages(world,visit,diagnostic,query)
	if not prefix.ok: return prefix
	stages.merge(prefix.stages)
	var consulting_doctor: String = str(quote.get("consulting_doctor_id",quote.staff_ids[0]))
	if int(world.facts.staff[consulting_doctor].abilities.treatment)<1:
		return {"ok":false,"reason":"缺少合格会诊医生"}
	_reference_stage(stages,"consult",["staff:"+consulting_doctor,"facility:"+str(consultation.get("facility_id",diagnostic.facility_id))],ceili(float(content.balance.clinical.consult_seconds)*10))
	return _reference_terminal_bundle(world,visit,reception,diagnostic,quote,stages,query)

func _reference_diagnostic_stages(world: WorldState, visit: Dictionary, diagnostic: Dictionary, query: Dictionary) -> Dictionary:
	var key: String = JSON.stringify(diagnostic)
	if query.diagnostic_stages.has(key): return query.diagnostic_stages[key]
	var result: Dictionary = _build_reference_diagnostic_stages(world,visit,diagnostic,query)
	query.diagnostic_stages[key] = result
	return result

func _build_reference_diagnostic_stages(world: WorldState, visit: Dictionary, diagnostic: Dictionary, query: Dictionary) -> Dictionary:
	var stages: Dictionary = {}
	var gp_staff: Dictionary = world.facts.staff[diagnostic.staff_id]
	var gp_facility: Dictionary = world.facts.facilities[diagnostic.facility_id]
	var gp_effective: float = float(gp_facility.grade)*float(content.balance.medical_equipment_effects.utilization_by_level[int(gp_staff.abilities.diagnosis)])
	_reference_stage(stages,"gp",["staff:"+str(diagnostic.staff_id),"facility:"+str(diagnostic.facility_id)],ceili(float(_gp_work_ticks(visit,gp_staff,gp_effective))/_talent_rate(world,gp_staff.id,"gp",visit)))
	var evidence: float = float(_profile(visit).gp_confidence)+2.0*(int(gp_staff.abilities.diagnosis)-1)+2.0*gp_effective
	var pending: Array = [{"stages":stages,"evidence":evidence}]
	var complete: Array = []
	for mode: String in ["spectrum","resonance"]:
		var needed: Array = []
		for branch: Dictionary in pending:
			if float(branch.evidence)>=float(content.balance.diagnosis_threshold):
				complete.append(branch.stages)
			else: needed.append(branch)
		pending = []
		if needed.is_empty(): break
		var test_pairs: Array = _reference_candidates(world,visit,mode,query)
		var next: Array = []
		for branch: Dictionary in needed:
			for test_pair: Dictionary in test_pairs:
				var staff: Dictionary = world.facts.staff[test_pair.staff_id]
				var facility: Dictionary = world.facts.facilities[test_pair.facility_id]
				var effective: float = float(facility.grade)*float(content.balance.medical_equipment_effects.utilization_by_level[int(staff.abilities.diagnosis)])
				var seconds: float = float(content.balance.tests[mode].seconds)/(1.0+0.05*(int(staff.abilities.diagnosis)-1)+0.15*effective)
				var selected: Dictionary = branch.stages.duplicate()
				_reference_stage(selected,mode,["staff:"+str(staff.id),"facility:"+str(facility.id)],ceili(seconds*10/_talent_rate(world,staff.id,"test",visit)))
				next.append({"stages":selected,"evidence":float(branch.evidence)+float(content.balance.tests[mode].confidence)+2.0*(int(staff.abilities.diagnosis)-1)+3.0*effective})
		pending = next
	for branch: Dictionary in pending:
		if float(branch.evidence)>=float(content.balance.diagnosis_threshold): complete.append(branch.stages)
	if complete.is_empty():
		return {"ok":false,"reason":"全部合法检查仍未达到诊断阈值"}
	return {"ok":true,"stages":complete[0],"variants":complete}

func _reference_terminal_bundle(world: WorldState, visit: Dictionary, reception: Dictionary, diagnostic: Dictionary, quote: Dictionary, stages: Dictionary, query: Dictionary = {}) -> Dictionary:
	space.begin_route_query(world,query.get("geometry",{}))
	var result: Dictionary = _build_reference_terminal_bundle(world,visit,reception,diagnostic,quote,stages,query)
	space.end_route_query()
	return result

func _build_reference_terminal_bundle(world: WorldState, visit: Dictionary, reception: Dictionary, diagnostic: Dictionary, quote: Dictionary, stages: Dictionary, query: Dictionary) -> Dictionary:
	var count_n: int = 1
	var count_d: int = 1
	var protocol: Dictionary = content.definition("treatment_protocols",content.definition("treatment_plans",quote.plan_id).protocol_id)
	var treatment_ticks: int = int(quote.work_ticks)
	var wake_ticks: int = int(content.balance.clinical.wake_seconds)*10 if protocol.kind=="surgery" else 0
	var setup_ticks: int = ceili(float(content.balance.clinical.or_setup_seconds)*10/(1.0+0.05*(int(world.facts.staff[quote.staff_ids[2]].abilities.surgery)-1))/_talent_rate(world,quote.staff_ids[2],"or_assist",visit)) if protocol.kind=="surgery" else 0
	var work_resources: Array = ["facility:"+str(quote.facility_id)]
	for staff_id: String in quote.staff_ids:
		work_resources.append("staff:"+staff_id)
	var gathering_ticks: int = int(quote.gathering_ticks) if quote.has("gathering_ticks") else _gathering_ticks(world,visit,quote.facility_id,quote.staff_ids)
	if gathering_ticks<0: return {"ok":false,"reason":"缺少完整到场路径"}
	_reference_stage(stages,str(protocol.kind),work_resources,gathering_ticks+treatment_ticks+wake_ticks,count_n,count_d)
	if setup_ticks>0:
		_reference_stage(stages,"surgery_setup",work_resources,setup_ticks,count_n,count_d)
	var bed_ticks: int = 0
	if int(quote.recovery_ticks)>0:
		var recovery_ticks: int = _recovery_ticks(world,quote.bed_id,quote.nurse_id,int(quote.recovery_ticks))
		var care_ticks: int = _bed_service_ticks(world,visit,"care",quote.nurse_id)
		var round_ticks: int = _bed_service_ticks(world,visit,"round",quote.round_doctor_id)
		if not query.has("bed_transport"): query.bed_transport = {}
		var key: String = JSON.stringify([visit.binding_id,quote.facility_id,quote.staff_ids[-1],quote.nurse_id,quote.bed_id])
		if not query.bed_transport.has(key): query.bed_transport[key] = _bed_transport(world,visit,quote,quote)
		var transfer: Dictionary = query.bed_transport[key]
		if not transfer.ok: return {"ok":false,"reason":"缺少原同层转床路径"}
		var patient: Dictionary = world.facts.actors[visit.actor_id].duplicate(true)
		var bed: Dictionary = space.facility_layout(world,quote.bed_id)
		patient.location = space.support_location(world,patient,bed)
		patient.posture = "lying"
		var release_ticks: int = space.support_exit_ticks(patient,bed,true)
		bed_ticks = gathering_ticks+setup_ticks+treatment_ticks+wake_ticks+int(transfer.ticks)+maxi(recovery_ticks,care_ticks)+round_ticks+release_ticks
		_reference_stage(stages,"transfer",["staff:"+str(transfer.escort_id)],int(transfer.ticks))
		stages.transfer["facility:"+str(quote.facility_id)] = {"n":str(transfer.exit_ticks),"d":"1"}
		_reference_stage(stages,"bed",["facility:"+str(quote.bed_id),"coverage:"+str(quote.nurse_id)+":"+str(quote.ward_id)],bed_ticks,count_n,count_d)
		_reference_stage(stages,"care",["staff:"+str(quote.nurse_id)],care_ticks,count_n,count_d)
		_reference_stage(stages,"round",["staff:"+str(quote.round_doctor_id)],round_ticks,count_n,count_d)
	var maps: Dictionary = _reference_resource_maps(stages,["staff:"+str(reception.staff_id),"facility:"+str(reception.facility_id),"staff:"+str(quote.get("nurse_id",""))])
	return {"ok":true,"plan_id":quote.plan_id,"resources":maps.resources,"stage_resources":stages,"structural_resources":maps.structural_resources,
		"reception_id":reception.facility_id,"gp_id":diagnostic.facility_id,"terminal_id":quote.facility_id,"staff_ids":quote.staff_ids.duplicate(),
		"bed_id":str(quote.get("bed_id","")),"ward_id":str(quote.get("ward_id","")),"coverage_nurse_id":str(quote.get("nurse_id","")),
		"bed_ticks":{"n":str(bed_ticks*count_n),"d":str(count_d)},"expected_attempts":{"n":str(count_n),"d":str(count_d)},"supply_units":quote.supply_units}

func _reference_resource_maps(stages: Dictionary, excluded: Array) -> Dictionary:
	# These first-attempt stage clocks are integer ticks. Retry weighting is
	# performed separately with exact fractions after the independent choices.
	var resources: Dictionary = {}
	var structural: Array = []
	for stage: Dictionary in stages.values():
		for resource_id: String in stage:
			var amount: Dictionary = stage[resource_id]
			if not resources.has(resource_id): resources[resource_id] = {"n":"0","d":"1"}
			resources[resource_id].n = str(str(resources[resource_id].n).to_int()+str(amount.n).to_int())
			if not resource_id.begins_with("coverage:") and not resource_id in excluded and not resource_id in structural:
				structural.append(resource_id)
	structural.sort()
	return {"resources":resources,"structural_resources":structural}

func _reference_stage(stages: Dictionary, kind: String, resources: Array, ticks: int, numerator: int = 1, denominator: int = 1) -> void:
	stages[kind] = {}
	for id: String in resources:
		stages[kind][id] = {"n":str(ticks*numerator),"d":str(denominator)}

func _reference_retry_stages(stages: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for stage: String in stages:
		if stage in ["consult","outpatient","surgery","surgery_setup","transfer","bed","care","round"]:
			result[stage] = stages[stage]
	return result

func _reference_with_retry(first: Dictionary, retry: Dictionary, first_probability_bp: int) -> Dictionary:
	var result: Dictionary = first.duplicate()
	result.resources = first.resources.duplicate()
	result.stage_resources = first.stage_resources.duplicate()
	var failure_probability: Dictionary = ReferenceFraction.make(10000-first_probability_bp,10000)
	var retry_stages: Dictionary = _reference_retry_stages(retry.stage_resources)
	result.first_stage_resources = first.stage_resources
	result.retry_stage_resources = retry_stages
	result.retry_plan_id = retry.plan_id
	result.first_probability_bp = first_probability_bp
	result.expected_attempts = ReferenceFraction.add(ReferenceFraction.make(1),failure_probability)
	result.expected_supply_units = ReferenceFraction.add(ReferenceFraction.make(first.supply_units),ReferenceFraction.mul(failure_probability,ReferenceFraction.make(retry.supply_units)))
	# Initial diagnostics occur once. Only the original failure branch carries
	# the newly scored attempt's own operators, machine, bed and nursing work.
	for stage: String in retry_stages:
		result.stage_resources[stage] = result.stage_resources.get(stage,{}).duplicate()
		for resource_id: String in retry_stages[stage]:
			var weighted: Dictionary = ReferenceFraction.mul(failure_probability,ReferenceFraction.from_value(retry_stages[stage][resource_id]))
			result.stage_resources[stage][resource_id] = ReferenceFraction.add(ReferenceFraction.from_value(result.stage_resources[stage].get(resource_id,ReferenceFraction.make())),weighted)
			result.resources[resource_id] = ReferenceFraction.add(ReferenceFraction.from_value(result.resources.get(resource_id,ReferenceFraction.make())),weighted)
	# The resource map is authoritative when the conditional plan uses a
	# different bed or coverage nurse; a single bed-total would overwrite it.
	result.erase("bed_ticks")
	return result

func _bed_busy(world: WorldState, id: String, except_preparation: String = "") -> bool:
	for stay: Dictionary in world.facts.ward_stays.values():
		if stay.bed_id == id or stay.get("transfer_from_bed_id","")==id:
			return true
	for preparation: Dictionary in world.facts.preparations.values():
		if preparation.bed_id == id and preparation.id!=except_preparation:
			return true
	return false

func _practice(world: WorldState, staff_id: String, track: String, job_id: String) -> void:
	var staff: Dictionary = world.facts.staff[staff_id]
	if not staff.completed_jobs.has(job_id):
		_practice_awards[staff_id+":"+job_id] = {"staff_id":staff_id,"track":track,"job_id":job_id}

func worked_staff() -> Dictionary:
	return _worked_staff.duplicate()

func take_events() -> Array[SimEvent]:
	var events: Array[SimEvent] = _events
	_events = []
	return events

func settle_practice(world: WorldState) -> void:
	var keys: Array = _practice_awards.keys()
	keys.sort()
	for key: String in keys:
		var award: Dictionary = _practice_awards[key]
		var staff: Dictionary = world.facts.staff[award.staff_id]
		if staff.completed_jobs.has(award.job_id):
			continue
		staff.completed_jobs[award.job_id] = award.track
		staff.practice[award.track] = mini(int(content.balance.clinical_ability_growth.practice_total_cap),int(staff.practice[award.track])+1)
		if int(world.facts.get("gameplay_version",0)) == 0 and "R11" in world.facts.research and int(staff.abilities[award.track])>0:
			for level: int in range(2,6):
				if int(staff.practice[award.track])>=int(content.balance.clinical_ability_growth.auto_level_thresholds[str(level)]):
					staff.abilities[award.track] = maxi(level,int(staff.abilities[award.track]))
	_practice_awards.clear()

func _can_start(world: WorldState, staff: Dictionary) -> bool:
	return not staff.has("clinical_release") and bool(staff.get("base_prepared",true)) and not bool(staff.get("block_new_work",false)) and not bool(staff.get("supply_strike",false)) and world.sim_tick>=int(staff.get("supply_return_tick",-1)) and str(staff.get("life_task",{}).get("phase","idle"))=="idle" and float(staff.energy)>15.0 and (staff.role!="doctor" or float(staff.fatigue)<float(content.balance.wellbeing.fatigue_stop_new_work))

func _use(world: WorldState, facility: Dictionary, receipt_id: String) -> void:
	facility = world.facts.facilities[facility.id]
	facility.used = true
	if world.facts.rooms.has(facility.get("room_id","")):
		world.facts.rooms[facility.room_id].used = true
		for payment: Dictionary in world.facts.rooms[facility.room_id].get("cell_payments",{}).values(): payment.used = true
	if not facility.use_receipts.has(receipt_id):
		facility.use_receipts[receipt_id] = world.facts.sim_tick
		if not facility.definition_id in content.balance.equipment.maintained_definition_ids:
			return
		var definition: Dictionary = content.facility_definition(facility.definition_id)
		for equipment_class: Dictionary in content.balance.equipment.classes:
			if equipment_class.id == definition.equipment_class:
				facility.condition = maxf(0.0,float(facility.condition)-float(equipment_class.wear_per_use))

func suspend_outpatient(world: WorldState, facility_id: String) -> void:
	for id: String in world.ids("sessions"):
		var record: Dictionary = world.facts.sessions[id]
		if record.facility_id!=facility_id or not record.kind in ["reception","gp","spectrum","resonance","consult","outpatient"] or not record.has("original_ticket"): continue
		var visit: Dictionary = world.facts.visits[record.visit_id]
		var ticket: Dictionary = record.original_ticket
		record.erase("original_ticket")
		record.suspended_tick = world.sim_tick
		record.definition_id = world.facts.facilities[facility_id].definition_id
		record.suspended_ticket_id = ticket.id
		world.facts.sessions.erase(id)
		world.facts.clinical_suspensions[id] = record
		ticket.resume_session_id = id
		ticket.service_assigned = false
		ticket.called_tick = -1
		world.facts.tickets[ticket.id] = ticket
		visit.ticket_id = ticket.id
		visit.phase = "wait_"+str(record.kind)
		var actor: Dictionary = world.facts.actors[visit.actor_id]
		actor.posture = "standing"
		actor.erase("support_facility_id")
		for staff_id: String in record.staff_ids:
			if world.facts.staff.has(staff_id): world.facts.staff[staff_id].clinical_release = {"facility_id":facility_id,"visit_id":visit.id,"phase":"seek","reason":""}
		if world.facts.adaptations.has(facility_id): world.facts.adaptations[facility_id].owner_id = visit.actor_id
		space.sync_actor(world,visit.actor_id)

func _dispatch_suspended(world: WorldState, visit: Dictionary, ticket: Dictionary) -> void:
	var record: Dictionary = world.facts.clinical_suspensions.get(str(ticket.resume_session_id),{})
	if record.is_empty(): return
	if not ticket.get("pause_reasons",{}).is_empty(): return
	var preparation: Dictionary = world.facts.preparations.get(visit.id,{})
	if not preparation.is_empty() and (world.sim_tick>=int(preparation.deadline_tick) or HospitalRemodel.blocked(world,preparation.facility_id) or world.facts.facilities[preparation.facility_id].failed or not world.facts.staff[preparation.staff_ids[0]].on_shift):
		if world.facts.adaptations.has(preparation.facility_id): world.facts.adaptations[preparation.facility_id].owner_id = visit.actor_id
		world.facts.preparations.erase(visit.id)
		preparation = {}
		ticket.service_assigned = false
		ticket.called_tick = -1
	if preparation.is_empty():
		for pair: Dictionary in service_candidates(world,visit,str(record.kind),true):
			var facility: Dictionary = world.facts.facilities[pair.facility_id]
			var staff: Dictionary = world.facts.staff[pair.staff_id]
			if facility.definition_id!=record.definition_id or _facility_unavailable(facility) or _facility_busy(world,facility.id) or _staff_busy(world,staff.id) or not staff.on_shift or not _can_start(world,staff) or not _schedule_allows(world,staff.id,record.kind,visit,facility.id): continue
			var attempt: Dictionary = world.facts.attempts.get(record.get("attempt_id",""),{})
			if record.kind=="outpatient" and int(staff.abilities.treatment)<_outpatient_minimum(visit,attempt.plan_id): continue
			if attempt.has("bed_id") and int(world.facts.facilities[attempt.bed_id].floor_id)!=int(facility.floor_id): continue
			var quote: Dictionary = space.facility_quote(world,facility.id,visit.actor_id,[staff.id])
			if not quote.ok: continue
			if waiting_life!=null and not waiting_life.call("call_patient",world,visit.id): return
			if not space.reserve_facility(world,facility.id,visit.actor_id,visit.id,[staff.id]).is_empty(): continue
			preparation = {"id":visit.id,"visit_id":visit.id,"kind":record.kind,"facility_id":facility.id,"bed_id":"","staff_ids":[staff.id],"resources":[visit.actor_id,facility.id,staff.id],"supply_units":0,"setup_remaining_ticks":0,"deadline_tick":world.sim_tick+int(content.balance.supplies.reservation_seconds)*10}
			world.facts.preparations[visit.id] = preparation
			ticket.service_assigned = true
			ticket.called_tick = world.sim_tick
			break
	if preparation.is_empty():
		visit.waiting_reason = "等待同种可用设备接续原工作，保留票号、承诺和余量"
		if world.sim_tick-int(record.suspended_tick)>=int(content.balance.clinical.equipment_no_progress_referral_seconds)*10: depart_visit(world,visit.id,"referred")
		return
	var facility: Dictionary = space.facility_layout(world,preparation.facility_id)
	if not _gather(world,visit,facility,preparation.staff_ids): return
	record.facility_id = facility.id
	record.staff_ids = preparation.staff_ids.duplicate()
	record.resources = [visit.actor_id,facility.id]+record.staff_ids
	record.original_ticket = ticket.duplicate(true)
	record.original_ticket.erase("resume_session_id")
	record.erase("suspended_tick")
	record.erase("suspended_ticket_id")
	world.facts.sessions[record.id] = record
	world.facts.clinical_suspensions.erase(record.id)
	world.facts.preparations.erase(visit.id)
	world.facts.tickets.erase(ticket.id)
	visit.ticket_id = ""
	visit.phase = record.kind
	if world.facts.adaptations.has(facility.id): world.facts.adaptations[facility.id].owner_id = record.id
	if record.kind=="outpatient": _support(world,visit,facility,"seated")
