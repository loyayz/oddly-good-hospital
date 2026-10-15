class_name HospitalClinic
extends RefCounted

const Visitors = preload("res://game/clinic/hospital_visitors.gd")

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

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry
	visitors = Visitors.new(database,geometry)

func ensure(world: WorldState) -> void:
	visitors.call("ensure",world)

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
	if kind == "clinical_auto_plan":
		world.facts.preparations.erase(id)
		visit.plan_decision = {}
		_retarget_ticket(world,visit,"consult")
		return CommandResult.new(true,"applied","",[id],world.revision)
	var plan_id: String = str(payload.get("plan_id",visit.plan_decision.get("plan_id","")))
	var quote: Dictionary = plan_quote(world,id,plan_id)
	if not quote.ok:
		return CommandResult.new(false,"plan_not_ready",quote.reason,[],world.revision)
	if payload.has("probability_bp") and int(payload.probability_bp)!=int(quote.probability_bp):
		return CommandResult.new(false,"material_change","当前预计效果已改变，请刷新本次方案",[],world.revision)
	world.facts.preparations.erase(id)
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
	for stay: Dictionary in world.facts.ward_stays.values():
		if world.facts.attempts[stay.attempt_id].visit_id == visit_id:
			return false
	world.facts.preparations.erase(visit_id)
	world.facts.tickets.erase(visit.ticket_id)
	visit.ticket_id = ""
	visit.final_result = result
	visit.phase = "leaving"
	visit.waiting_reason = ""
	return true

func dispatch(world: WorldState) -> void:
	_worked_staff.clear()
	_dispatch_clinical_releases(world)
	if int(world.facts.get("gameplay_version",0))>=1:
		visitors.call("dispatch",world)
	for preparation_id: String in world.ids("preparations"):
		var pending: Dictionary = world.facts.preparations[preparation_id]
		if pending.get("kind","")=="outpatient" and world.sim_tick>=int(pending.deadline_tick):
			world.facts.preparations.erase(preparation_id)
			world.facts.visits[pending.visit_id].waiting_reason = "准备到期，释放原资源并保留票号"
	for visit_id: String in world.ids("visits"):
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
			_start_bed_service(world,visit,stay,"care",stay.nurse_id,float(content.balance.clinical.nurse_visit_seconds))
		elif stay.phase == "round_wait":
			var doctor_id: String = _round_candidate(world,visit,stay)
			if not doctor_id.is_empty():
				stay.round_doctor_id = doctor_id
				_start_bed_service(world,visit,stay,"round",doctor_id,float(content.balance.clinical.discharge_round_seconds))

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
			world.facts.visits[world.facts.attempts[stay.attempt_id].visit_id].waiting_reason = "等待本病房实际护理覆盖"
			continue
		var effective: float = float(bed.grade) * float(content.balance.medical_equipment_effects.utilization_by_level[int(nurse.abilities.care)])
		var rate_key: String = stay.bed_id+":"+stay.nurse_id+":"+str(nurse.abilities.care)+":"+str(bed.grade)
		if stay.get("coverage_segment",{}).get("key","")!=rate_key:
			stay.coverage_segment = {"key":rate_key,"start_tick":world.sim_tick,"rate_milli":roundi((1.0+0.15*effective)*1000)}
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
	var kind: String = ticket.kind
	if kind=="outpatient" and int(world.facts.get("gameplay_version",0))>=1 and not visit.plan_decision.is_empty():
		var current_quote: Dictionary = plan_quote(world,visit.id,visit.plan_decision.plan_id)
		if not current_quote.ok and not current_quote.get("structural_ok",false):
			world.facts.preparations.erase(visit.id)
			ticket.service_assigned = false
			ticket.called_tick = -1
			if visit.plan_decision.get("source","")=="doctor":
				_retarget_ticket(world,visit,"consult")
			else:
				visit.plan_decision.pending_reason = "方案条件变化："+str(current_quote.reason)
			visit.waiting_reason = str(current_quote.reason)
			return
	if kind=="consult" and int(world.facts.get("gameplay_version",0))>=1 and _select_plan(world,visit).is_empty():
		visit.waiting_reason = "暂无完整可执行方案，保留原票号等待资源与资格"
		return
	if kind=="gp" and departments!=null and not departments.call("route_patient",world,visit.id):
		return
	var facility_id: String = {"reception":"reception_desk","gp":"gp","spectrum":"exam",
		"resonance":"exam","consult":"gp","outpatient":"treatment"}.get(kind,"")
	var staff_id: String = {"reception":"reception","gp":"gp_doctor","spectrum":"exam_nurse",
		"resonance":"exam_nurse","consult":"gp_doctor","outpatient":"treat_doctor"}.get(kind,"")
	if int(world.facts.get("gameplay_version",0)) >= 1:
		var candidates: Array = service_candidates(world,visit,kind)
		if kind=="consult" and scheduler!=null:
			var recommendation: Dictionary = _select_plan(world,visit)
			candidates = candidates.filter(func(pair: Dictionary)->bool: return pair.staff_id==recommendation.get("consulting_doctor_id",""))
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
	if not staff.on_shift or not _can_start(staff):
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
			world.facts.preparations.erase(visit.id)
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

func service_candidates(world: WorldState, visit: Dictionary, kind: String, structural_only: bool = false) -> Array:
	var equipment_id: String = "FUR01" if kind == "reception" else "FUR02"
	if kind == "outpatient":
		var binding: Dictionary = content.definition("treatment_bindings",visit.binding_id)
		equipment_id = str(content.definition("treatment_routines",binding.routine_id).equipment_id)
	var candidates: Array = []
	var preparation: Dictionary = world.facts.preparations.get(visit.id,{})
	for facility_id: String in world.ids("facilities"):
		var facility: Dictionary = world.facts.facilities[facility_id]
		if facility.failed or not bool(facility.get("open",true)) or not bool(facility.get("intake_open",true)):
			continue
		if not preparation.is_empty() and preparation.facility_id!=facility_id:
			continue
		if facility.definition_id != equipment_id or (not structural_only and (_facility_unavailable(facility) or _facility_busy(world,facility_id,visit.id))):
			continue
		var department_id: String = str(visit.get("department_id",""))
		var department: Dictionary = world.facts.get("departments",{}).get("units",{}).get(department_id,{})
		if department_id!="general" and not department.is_empty() and not facility.get("room_id","") in department.get("room_ids",[])+department.get("shared_room_ids",[]):
			continue
		for staff_id: String in world.ids("staff"):
			var staff: Dictionary = world.facts.staff[staff_id]
			if not preparation.is_empty() and not staff_id in preparation.staff_ids:
				continue
			if not structural_only and (_staff_busy(world,staff_id,visit.id) or not staff.on_shift or not _can_start(staff)):
				continue
			if not structural_only and not _schedule_allows(world,staff_id,kind,visit,facility_id):
				continue
			var qualified: bool = staff.role == "receptionist" if kind == "reception" else staff.role == "doctor"
			if kind in ["spectrum","resonance"]:
				qualified = false
				for mode: Dictionary in content.catalog.diagnostic_modes:
					if mode.service != kind:
						continue
					for requirement: Dictionary in mode.operators:
						var allowed: bool = staff.role == requirement.role and int(staff.abilities.get(requirement.ability,0)) >= int(requirement.min_level)
						for research_id: String in requirement.requires_research:
							allowed = allowed and research_id in world.facts.research
						qualified = qualified or allowed
			elif kind != "reception":
				qualified = qualified and int(staff.abilities.get("treatment" if kind in ["outpatient","consult"] else "diagnosis",0)) >= 1
			if not qualified:
				continue
			var layout: Dictionary = space.facility_layout(world,facility_id)
			if layout.operator_cells.is_empty():
				continue
			var fit: Dictionary = space.facility_quote(world,facility_id,visit.actor_id,[staff_id])
			if not fit.ok:
				continue
			if not space.route(world,visit.actor_id,int(layout.floor_id),layout.patient_cell,[],{},true).ok or not space.route(world,staff_id,int(layout.floor_id),layout.operator_cells[0],[],{},true).ok:
				continue
			candidates.append({"facility_id":facility_id,"staff_id":staff_id})
	return candidates

func compare_plans(world: WorldState, visit_id: String) -> Array:
	var visit: Dictionary = world.facts.visits.get(visit_id,{})
	var results: Array = []
	if visit.is_empty():
		return results
	for plan: Dictionary in content.catalog.treatment_plans:
		if plan.disease_id==visit.disease_id:
			results.append(plan_quote(world,visit_id,plan.id))
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
		if not structural and (_facility_unavailable(facility) or _facility_busy(world,pair.facility_id,visit.id) or _staff_busy(world,pair.staff_id,visit.id) or not staff.on_shift or not _can_start(staff)):
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
	quotes.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if float(a.score)!=float(b.score): return float(a.score)>float(b.score)
		if int(a.probability_bp)!=int(b.probability_bp): return int(a.probability_bp)>int(b.probability_bp)
		if int(a.get("estimated_total_ticks",a.work_ticks))!=int(b.get("estimated_total_ticks",b.work_ticks)): return int(a.get("estimated_total_ticks",a.work_ticks))<int(b.get("estimated_total_ticks",b.work_ticks))
		return str(a.plan_id)<str(b.plan_id))
	var strategy: String = str(world.facts.get("plan_strategy","doctor"))
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
	world.facts.preparations.erase(visit.id)
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

func _outpatient_quote(world: WorldState, visit: Dictionary, staff: Dictionary, facility: Dictionary, plan_id: String = "", ignore_supplies: bool = false, structural_only: bool = false) -> Dictionary:
	if plan_id.is_empty():
		plan_id = str(visit.plan_decision.get("plan_id",visit.requested_plan_id))
	var plan: Dictionary = content.definition("treatment_plans",plan_id)
	var protocol: Dictionary = content.definition("treatment_protocols",plan.protocol_id)
	var disease: Dictionary = content.definition("diseases",visit.disease_id)
	var profile: Dictionary = _profile(visit)
	var minimum: int = int(profile.min_skill)
	var base_success: float = float(profile.base_success)
	var supply_units: int = int(profile.supply_units)
	var recovery_seconds: float = 0.0
	if not bool(protocol.uses_disease_profile):
		var gentle: Dictionary = protocol.clinical_profiles[disease.profile]
		minimum = int(gentle.min_treatment)
		base_success = float(gentle.base_success)
		supply_units = int(gentle.supply_units)
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
		bed_bundle = _compatible_bed(world,visit,int(facility.floor_id),[staff.id],structural_only,str(world.facts.preparations.get(visit.id,{}).get("bed_id","")))
		if not bed_bundle.ok:
			return bed_bundle
	var seconds: float = float(routine.service_seconds)*float(protocol.work_multiplier)/(1.0+0.05*(int(staff.abilities.treatment)-1)+0.2*effective)*(1.0+0.003*float(staff.fatigue))
	if departments!=null:
		seconds *= float(departments.call("focus_multiplier",world,visit.id,staff.id,"treatment"))
	var quote: Dictionary = {"ok":true,"plan_id":plan_id,"probability_bp":floori(probability*10000),
		"work_ticks":ceili(seconds*10),"recovery_ticks":ceili(recovery_seconds*10),"supply_units":supply_units,
		"cure_fee":_quoted_fee(int(disease.cure_fee),protocol.cure_fee_multiplier),"facility_fee":content.facility_fee(facility.definition_id,"outpatient"),
		"staff_ids":[staff.id],"effective_level":effective,"facility_id":facility.id}
	for key: String in ["bed_id","nurse_id","round_doctor_id","ward_id"]:
		if bed_bundle.has(key):
			quote[key] = bed_bundle[key]
	return quote

func _compatible_bed(world: WorldState, visit: Dictionary, floor_id: int, excluded: Array, structural_only: bool = false, preferred_bed: String = "") -> Dictionary:
	for bed_id: String in world.ids("facilities"):
		if not preferred_bed.is_empty() and bed_id!=preferred_bed:
			continue
		var bed: Dictionary = world.facts.facilities[bed_id]
		if bed.definition_id!="EQ05" or int(bed.floor_id)!=floor_id or not world.facts.rooms.has(bed.get("room_id","")):
			continue
		var ward: Dictionary = world.facts.rooms[bed.room_id]
		if ward.kind!="ward" or bed.failed or not bool(ward.get("open",true)) or int(ward.size[0])<6 or int(ward.size[1])<6 or (not structural_only and (_facility_unavailable(bed) or _bed_busy(world,bed_id,visit.id))):
			continue
		for nurse_id: String in world.ids("staff"):
			var nurse: Dictionary = world.facts.staff[nurse_id]
			if nurse_id in excluded or nurse.role!="nurse" or not "q_ward" in nurse.certificates or str(nurse.get("ward_id",""))!=ward.id:
				continue
			if not structural_only and (not nurse.on_shift or not _can_start(nurse)):
				continue
			if not structural_only and _staff_busy(world,nurse_id):
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
				for workbench: Dictionary in world.facts.facilities.values():
					if workbench.definition_id=="SE06" and int(workbench.floor_id)==floor_id and not workbench.failed:
						var position: Array = workbench.operator_cells[0]
						has_workbench = has_workbench or bool(space.route(world,nurse_id,floor_id,position,[],{},true).ok)
				if not has_workbench:
					continue
			var load: int = 0
			for stay: Dictionary in world.facts.ward_stays.values():
				if stay.nurse_id==nurse_id:
					load += 1
			for preparation: Dictionary in world.facts.preparations.values():
				if preparation.get("nurse_id","")==nurse_id and preparation.visit_id!=visit.id:
					load += 1
			if load>=int(content.balance.clinical.beds_per_nurse):
				continue
			for doctor_id: String in world.ids("staff"):
				var doctor: Dictionary = world.facts.staff[doctor_id]
				if doctor.role!="doctor" or int(doctor.abilities.diagnosis)<2 or int(doctor.abilities.treatment)<1:
					continue
				if not structural_only and (not doctor.on_shift or not _can_start(doctor)):
					continue
				if not structural_only and not _schedule_allows(world,doctor_id,"round",visit,bed_id):
					continue
				var fit: Dictionary = space.facility_quote(world,bed_id,visit.actor_id,[nurse_id,doctor_id])
				if not fit.ok:
					continue
				var layout: Dictionary = fit if not fit.get("unchanged",false) else space.facility_layout(world,bed_id)
				if space.route(world,visit.actor_id,floor_id,layout.patient_cell,[],{},true).ok and space.route(world,nurse_id,floor_id,layout.operator_cells[0],[],{},true).ok and space.route(world,doctor_id,floor_id,layout.operator_cells[1],[],{},true).ok:
					return {"ok":true,"bed_id":bed_id,"nurse_id":nurse_id,"round_doctor_id":doctor_id,"ward_id":ward.id}
	return {"ok":false,"reason":"等待同层兼容床位、真实护理覆盖与出院查房医生"}

func _prepare_surgery(world: WorldState, visit: Dictionary, ticket: Dictionary) -> void:
	var existing: Dictionary = world.facts.preparations.get(visit.id,{})
	var quote: Dictionary = _surgery_quote(world,visit,existing.get("staff_ids",[]),{"facility_id":existing.facility_id,"bed_id":existing.bed_id} if not existing.is_empty() else {})
	if not quote.ok:
		world.facts.preparations.erase(visit.id)
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
		world.facts.preparations.erase(visit.id)
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
	for staff_id: String in world.ids("staff"):
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
			if not structural and (not staff.on_shift or not _can_start(staff) or _staff_busy(world,staff_id,visit.id)):
				continue
			pools[index].append(staff_id)
	var best: Dictionary = {"ok":false,"structural_ok":false,"reason":"缺少当前可执行的三个互异手术岗位"}
	for surgeon_id: String in pools[0]:
		for anesthetist_id: String in pools[1]:
			if surgeon_id==anesthetist_id:
				continue
			for nurse_id: String in pools[2]:
				for facility_id: String in world.ids("facilities"):
					var table: Dictionary = world.facts.facilities[facility_id]
					if table.definition_id!="EQ01" or (options.has("facility_id") and options.facility_id!=facility_id):
						continue
					var quote: Dictionary = _surgery_bundle_quote(world,visit,[surgeon_id,anesthetist_id,nurse_id],facility_id,options)
					if quote.ok and (not best.ok or int(quote.probability_bp)>int(best.probability_bp) or (int(quote.probability_bp)==int(best.probability_bp) and str(quote.staff_ids)+facility_id<str(best.staff_ids)+str(best.facility_id))):
						best = quote
					elif not best.ok:
						best = quote
	return best

func _surgery_bundle_quote(world: WorldState, visit: Dictionary, team: Array, facility_id: String, options: Dictionary) -> Dictionary:
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
	var utilization_sum: float = 0.0
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
		utilization_sum += float(content.balance.medical_equipment_effects.utilization_by_level[int(staff.abilities.surgery)])
	if team[0] == team[1] or team[0] == team[2] or team[1] == team[2]:
		return {"ok":false,"reason":"手术岗位必须互异"}
	var table: Dictionary = world.facts.facilities[facility_id]
	var structural: bool = bool(options.get("structural_only",false))
	if not structural:
		for staff_id: String in team:
			if not _schedule_allows(world,staff_id,"surgery",visit,facility_id):
				return {"ok":false,"structural_ok":true,"reason":"等待排班手术池内的完整团队"}
	if not world.facts.rooms.has(table.get("room_id","")):
		return {"ok":false,"reason":"手术台缺少合法手术室"}
	var operating_room: Dictionary = world.facts.rooms[table.room_id]
	if table.failed or not bool(table.get("open",true)) or not bool(table.get("intake_open",true)) or not bool(operating_room.get("open",true)) or operating_room.kind!="operating_room" or int(operating_room.size[0])<8 or int(operating_room.size[1])<8:
		return {"ok":false,"reason":"手术室未满足最小内部8×8"}
	if not structural and (_facility_unavailable(table) or _facility_busy(world,facility_id,visit.id)):
		return {"ok":false,"structural_ok":true,"reason":"等待原手术台安全可用"}
	var bed_bundle: Dictionary = _compatible_bed(world,visit,int(table.floor_id),team,structural,str(options.get("bed_id","")))
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
		var route: Dictionary = space.route(world,actor_id,int(table.floor_id),position,[],{},true)
		if not route.ok:
			return route
		gathering_ticks = maxi(gathering_ticks,int(route.arrival_ticks))
	var surgeon: Dictionary = world.facts.staff[team[0]]
	var anesthetist: Dictionary = world.facts.staff[team[1]]
	var effective: float = float(table.grade)*utilization_sum/3.0
	var probability: float = float(protocol.base_success)+0.015*(int(surgeon.abilities.surgery)-int(protocol.min_surgeon_surgery))
	probability += 0.005*(int(anesthetist.abilities.surgery)-int(protocol.min_anesthetist_surgery))+0.01*effective
	probability -= 0.03 if float(surgeon.energy)<35 else 0.0
	probability -= 0.04 if float(table.condition)<40 else 0.0
	probability += 0.15 if not visit.attempt_ids.is_empty() else 0.0
	probability = clampf(probability,0.70,0.98)
	var seconds: float = float(protocol.work_seconds)/(1.0+0.05*(int(surgeon.abilities.surgery)-int(protocol.min_surgeon_surgery))+0.1*effective)*(1.0+0.003*float(surgeon.fatigue))
	if departments!=null:
		seconds *= float(departments.call("focus_multiplier",world,visit.id,team[0],"surgery"))
	for staff_id: String in team:
		var consumption: float = float(content.balance.wellbeing.energy_work_per_second)*(seconds+float(content.balance.clinical.wake_seconds)+float(content.balance.clinical.or_setup_seconds))
		if not structural and float(world.facts.staff[staff_id].energy)-consumption<=15.0:
			return {"ok":false,"reason":"团队体力不足以安全覆盖操作和苏醒全过程"}
	var quote: Dictionary = {"ok":true,"structural_ok":true,"plan_id":plan.id,"probability_bp":floori(probability*10000),"work_ticks":ceili(seconds*10),
		"recovery_ticks":ceili(float(protocol.recovery_seconds)*10),"supply_units":int(protocol.supply_units),
		"cure_fee":_quoted_fee(int(content.definition("diseases",visit.disease_id).cure_fee),protocol.cure_fee_multiplier),
		"facility_fee":content.facility_fee(table.definition_id,"surgery"),"staff_ids":team.duplicate(),"effective_level":effective,"facility_id":facility_id,
		"gathering_ticks":gathering_ticks,"estimated_total_ticks":gathering_ticks+ceili(seconds*10)+ceili(float(protocol.recovery_seconds)*10)+int(content.balance.clinical.wake_seconds)*10}
	quote.merge(bed_bundle)
	return quote

func _reserve_bundle(world: WorldState, visit: Dictionary, quote: Dictionary, owner_id: String) -> String:
	var candidate: WorldState = WorldState.new(world.freeze())
	var geometry: HospitalSpace = HospitalSpace.new(content)
	var reason: String = geometry.reserve_facility(candidate,quote.facility_id,visit.actor_id,owner_id,quote.staff_ids)
	if not reason.is_empty():
		return reason
	if quote.has("bed_id"):
		reason = geometry.reserve_facility(candidate,quote.bed_id,visit.actor_id,owner_id,[quote.nurse_id,quote.round_doctor_id])
		if not reason.is_empty():
			return reason
	space.reserve_facility(world,quote.facility_id,visit.actor_id,owner_id,quote.staff_ids)
	if quote.has("bed_id"):
		space.reserve_facility(world,quote.bed_id,visit.actor_id,owner_id,[quote.nurse_id,quote.round_doctor_id])
	return ""

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
			HospitalLedger.post(world,LedgerEntry.new(attempt.id,"ward",content.facility_fee("EQ05","ward")),false)
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
		if facility.definition_id=="FUR02" and ticket.get("kind","") in ["gp","consult"] and staff.role=="doctor" and int(staff.abilities.get("diagnosis" if ticket.kind=="gp" else "treatment",0))>=1:
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
		var selected: Array = []
		for distance: int in range(1,5):
			for delta: Vector2i in [Vector2i(0,-distance),Vector2i(distance,0),Vector2i(0,distance),Vector2i(-distance,0)]:
				var point: Vector2i = origin+delta
				var rect: Rect2 = space._actor_rect(actor,Vector2(point))
				var intersects: bool = false
				for region: Array in reservation.regions:
					intersects = intersects or rect.intersects(Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3])),false)
				if intersects or not space.static_reason(world,actor,int(actor.location.floor_id),point).is_empty() or not space._dynamic_clear(world,staff_id,int(actor.location.floor_id),rect):
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

func _start_bed_service(world: WorldState, visit: Dictionary, stay: Dictionary, kind: String, staff_id: String, seconds: float) -> void:
	var bed: Dictionary = space.facility_layout(world,stay.bed_id)
	var staff: Dictionary = world.facts.staff[staff_id]
	var can_work: bool = _can_start(staff) if kind=="round" else staff.on_shift and float(staff.energy)>15.0 and str(staff.get("life_task",{}).get("phase","idle")) in ["idle","wait_safe"]
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
	var level: int = int(staff.abilities.care) if kind == "care" else int(staff.abilities.treatment)
	if staff.role=="doctor":
		seconds *= 1.0+float(content.balance.wellbeing.fatigue_work_multiplier_per_point)*float(staff.fatigue)
	var ticks: int = int(stay.get(kind+"_remaining_ticks",ceili(seconds/(1.0+0.05*(level-1))*10/_talent_rate(world,staff_id,"ward_visit",visit))))
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
	var anchor: Vector3 = space.support_anchor(world,facility.id)
	var dimensions: Dictionary = content.actor_body(actor)
	var center: float = float(space.clearance(actor))*0.5
	actor.location.cell = [float(facility.cell[0])+anchor.x/1.5-center,float(facility.cell[1])+(anchor.z+float(dimensions.height_m)*0.5)/1.5-center]
	actor.location.height_m = anchor.y+float(dimensions.depth_m)*0.5
	actor.facing = 0.0
	space.sync_actor(world,actor.id)

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
		var reason: String = space.request_move(world,nurse_id,int(ward.floor_id),[int(ward.origin[0]),int(ward.origin[1])+int(ward.size[1])-1])
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
	return bool(space.route(world,stay.nurse_id,int(bed.floor_id),layout.operator_cells[0],[],{},true).ok)

func _round_candidate(world: WorldState, visit: Dictionary, stay: Dictionary) -> String:
	var order: Array = [stay.round_doctor_id]
	for id: String in world.ids("staff"):
		if not id in order:
			order.append(id)
	var bed: Dictionary = space.facility_layout(world,stay.bed_id)
	for id: String in order:
		var doctor: Dictionary = world.facts.staff.get(id,{})
		if doctor.get("role","")!="doctor" or not doctor.on_shift or not _can_start(doctor) or _staff_busy(world,id) or int(doctor.abilities.diagnosis)<2 or int(doctor.abilities.treatment)<1:
			continue
		if not _schedule_allows(world,id,"round",visit,stay.bed_id):
			continue
		var candidate: WorldState = world
		var reservation: Dictionary = world.facts.adaptations.get(stay.bed_id,{})
		if not reservation.is_empty() and not id in reservation.staff_ids:
			candidate = WorldState.new(world.freeze())
			candidate.facts.adaptations[stay.bed_id].staff_ids.append(id)
		var route: Dictionary = space.route(candidate,id,int(bed.floor_id),bed.operator_cells[1])
		if route.ok and route.get("status","")!="contention":
			if not reservation.is_empty() and not id in reservation.staff_ids:
				reservation.staff_ids.append(id)
			return id
	visit.waiting_reason = "等待实际可到床边的合格出院查房医生"
	return ""

func _transfer_stay(world: WorldState, visit: Dictionary, stay: Dictionary, preferred_bed: String = "") -> String:
	if not visitors.call("yield_for_care",world,visit.id):
		return "等待家属实际让开转床通路"
	var old_bed: Dictionary = space.facility_layout(world,stay.bed_id)
	var candidate: WorldState = WorldState.new(world.freeze())
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

func _facility_busy(world: WorldState, id: String, except_preparation: String = "") -> bool:
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

func _staff_busy(world: WorldState, id: String, except_preparation: String = "") -> bool:
	if world.facts.staff.get(id,{}).has("clinical_release"):
		return true
	if not str(world.facts.staff.get(id,{}).get("active_job_id","")).is_empty():
		return true
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

func shortage_requests(world: WorldState) -> Array:
	var result: Array = []
	var candidate: WorldState = WorldState.new(world.freeze())
	for staff: Dictionary in candidate.facts.staff.values():
		staff.supply_strike = false
	for ticket_id: String in world.ids("tickets"):
		var ticket: Dictionary = world.facts.tickets[ticket_id]
		if not ticket.kind in ["outpatient","surgery"]:
			continue
		var visit: Dictionary = world.facts.visits[ticket.visit_id]
		var quote: Dictionary = plan_quote(candidate,visit.id,str(visit.plan_decision.get("plan_id",visit.requested_plan_id)),{"ignore_supplies":true})
		if quote.ok and _available_supplies(world,visit.id)<int(quote.supply_units):
			result.append({"ticket_id":ticket_id,"visit_id":visit.id,"staff_ids":quote.staff_ids.duplicate(),"units":int(quote.supply_units)})
	return result

func arrival_readiness(world: WorldState, binding_id: String, complex_case: bool = false) -> Dictionary:
	var candidate: Dictionary = _arrival_candidate(world,binding_id,complex_case)
	if not candidate.get("ok",false):
		return candidate
	var quotes: Array = []
	var executable: bool = false
	for plan: Dictionary in content.catalog.treatment_plans:
		if plan.disease_id!=candidate.visit.disease_id:
			continue
		var quote: Dictionary = plan_quote(candidate.world,candidate.visit.id,plan.id,{"structural_only":true,"ignore_supplies":true})
		quotes.append(quote)
		executable = executable or bool(quote.ok)
	var diagnostic: bool = not service_candidates(candidate.world,candidate.visit,"gp",true).is_empty() and not service_candidates(candidate.world,candidate.visit,"reception",true).is_empty()
	for mode: String in _profile(candidate.visit).tests:
		diagnostic = diagnostic and not service_candidates(candidate.world,candidate.visit,mode,true).is_empty()
	return {"ok":executable and diagnostic,"reason":"" if executable and diagnostic else "缺少完整诊断及治疗结构资格","plans":quotes}

func _arrival_candidate(world: WorldState, binding_id: String, complex_case: bool) -> Dictionary:
	var binding: Dictionary = content.definition("treatment_bindings",binding_id)
	if binding.is_empty():
		return {"ok":false,"reason":"病例绑定不存在"}
	var candidate: WorldState = WorldState.new(world.freeze())
	var entry: Dictionary = world.facts.get("entry",{"floor_id":1,"cell":[47,93]})
	var actor_id: String = "reference_patient"
	var visit_id: String = "reference_visit"
	candidate.facts.actors[actor_id] = {"id":actor_id,"name":"参考患者","species_id":binding.species_id,"body_binding_id":binding.id,
		"location":{"kind":"floor","floor_id":int(entry.floor_id),"cell":entry.cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
	candidate.facts.visits[visit_id] = {"id":visit_id,"actor_id":actor_id,"disease_id":binding.disease_id,"binding_id":binding.id,"complex":complex_case,
		"requested_plan_id":"P_"+str(binding.disease_id)+"_COMMON","plan_decision":{},"attempt_ids":[],"evidence_by_source":{},"expression":"clear","personality_id":"PP01","anger":15.0,"doctor_fee_quote":-1,"phase":"arrival","ticket_id":""}
	var actor: Dictionary = candidate.facts.actors[actor_id]
	var reason: String = space.static_reason(candidate,actor,int(entry.floor_id),Vector2i(int(entry.cell[0]),int(entry.cell[1])))
	return {"ok":reason.is_empty(),"reason":reason,"world":candidate,"visit":candidate.facts.visits[visit_id]}

func reference_demand(world: WorldState, binding_id: String, complex_case: bool = false, _shift: int = 0) -> Dictionary:
	var reference: Dictionary = _arrival_candidate(world,binding_id,complex_case)
	if not reference.ok:
		return {"ok":false,"reason":reference.reason,"bundles":[]}
	var candidate: WorldState = reference.world
	var visit: Dictionary = reference.visit
	# A reference removes temporary contention while retaining the actual built
	# geometry, bodies, qualifications and the original shift budgets.
	candidate.facts.sessions = {}
	candidate.facts.preparations = {}
	candidate.facts.ward_stays = {}
	candidate.facts.moves = {}
	for staff: Dictionary in candidate.facts.staff.values():
		staff.energy = 100.0
		staff.fatigue = 0.0
		staff.on_shift = true
		staff.block_new_work = false
		staff.base_prepared = true
		staff.supply_strike = false
		staff.life_task = {"phase":"idle"}
	var receptions: Array = service_candidates(candidate,visit,"reception",true)
	var diagnostics: Array = service_candidates(candidate,visit,"gp",true)
	if receptions.is_empty() or diagnostics.is_empty():
		return {"ok":false,"reason":"缺少实际接待或初诊资源","bundles":[]}
	var terminal_quotes: Array = []
	for pair: Dictionary in service_candidates(candidate,visit,"outpatient",true):
		var preferred: Dictionary = {}
		for plan: Dictionary in content.catalog.treatment_plans:
			if plan.disease_id!=visit.disease_id or content.definition("treatment_protocols",plan.protocol_id).kind!="outpatient":
				continue
			var allowed: bool = true
			for research_id: String in plan.requires_research:
				allowed = allowed and research_id in candidate.facts.research
			if not allowed:
				continue
			var quote: Dictionary = _outpatient_quote(candidate,visit,candidate.facts.staff[pair.staff_id],candidate.facts.facilities[pair.facility_id],plan.id,true,true)
			if not quote.ok:
				continue
			quote.estimated_total_ticks = int(quote.work_ticks)+int(quote.recovery_ticks)
			quote.score = _reference_score(candidate,visit,quote,pair.staff_id)
			if preferred.is_empty() or float(quote.score)>float(preferred.score) or (float(quote.score)==float(preferred.score) and str(quote.plan_id)<str(preferred.plan_id)):
				preferred = quote
		if not preferred.is_empty():
			terminal_quotes.append(preferred)
	for plan: Dictionary in content.catalog.treatment_plans:
		if plan.disease_id!=visit.disease_id or content.definition("treatment_protocols",plan.protocol_id).kind!="surgery":
			continue
		var quote: Dictionary = plan_quote(candidate,visit.id,plan.id,{"structural_only":true,"ignore_supplies":true})
		if quote.ok:
			terminal_quotes.append(quote)
	var bundles: Array = []
	var grouped: Dictionary = {}
	for terminal: Dictionary in terminal_quotes:
		var doctor_id: String = str(terminal.staff_ids[0])
		if not grouped.has(doctor_id): grouped[doctor_id] = []
		terminal.score = _reference_score(candidate,visit,terminal,doctor_id)
		grouped[doctor_id].append(terminal)
	var selected_plans: Dictionary = {}
	for doctor_id: String in grouped:
		var options: Array = grouped[doctor_id]
		options.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
			if float(a.score)!=float(b.score): return float(a.score)>float(b.score)
			if int(a.probability_bp)!=int(b.probability_bp): return int(a.probability_bp)>int(b.probability_bp)
			if int(a.get("estimated_total_ticks",a.work_ticks))!=int(b.get("estimated_total_ticks",b.work_ticks)): return int(a.get("estimated_total_ticks",a.work_ticks))<int(b.get("estimated_total_ticks",b.work_ticks))
			return str(a.plan_id)<str(b.plan_id))
		var selection: Dictionary = options[0]
		var strategy: String = str(world.facts.get("plan_strategy","doctor"))
		if strategy=="outpatient_first":
			for quote: Dictionary in options:
				if content.definition("treatment_protocols",content.definition("treatment_plans",quote.plan_id).protocol_id).kind=="outpatient" and int(quote.probability_bp)>=roundi(float(content.balance.clinical.outpatient_priority_success)*10000):
					selection = quote
					break
		elif strategy=="safety_first":
			var best_probability: int = 0
			for quote: Dictionary in options: best_probability = maxi(best_probability,int(quote.probability_bp))
			for quote: Dictionary in options:
				if best_probability-int(quote.probability_bp)<=roundi(float(content.balance.clinical.safety_strategy_tolerance)*10000):
					selection = quote
					break
		selected_plans[doctor_id] = selection.plan_id
	for terminal: Dictionary in terminal_quotes:
		if selected_plans.get(str(terminal.staff_ids[0]),"")!=terminal.plan_id:
			continue
		for diagnostic: Dictionary in diagnostics:
			for reception: Dictionary in receptions:
				var bundle: Dictionary = _reference_bundle(candidate,visit,reception,diagnostic,terminal)
				if bundle.get("ok",false):
					bundles.append(bundle)
	return {"ok":not bundles.is_empty(),"reason":"" if not bundles.is_empty() else "没有完整临床参考资源束","bundles":bundles}

func _reference_score(world: WorldState, _visit: Dictionary, quote: Dictionary, doctor_id: String) -> float:
	var staff: Dictionary = world.facts.staff[doctor_id]
	var personality: Dictionary = content.definition("doctor_personalities",str(staff.get("personality_id","DP01")))
	var protocol: Dictionary = content.definition("treatment_protocols",content.definition("treatment_plans",quote.plan_id).protocol_id)
	var completed: int = int(staff.get("plan_experience",{}).get(quote.plan_id,0))
	var weights: Dictionary = personality.weights
	return float(weights.success)*float(quote.probability_bp)/100.0-float(weights.time)*float(quote.get("estimated_total_ticks",quote.work_ticks))/100.0-float(weights.burden)*float(protocol.burden)+float(weights.familiarity)*mini(5,completed/5)+float(weights.novelty)*(1 if completed==0 else 0)+float(weights.team)

func _reference_bundle(world: WorldState, visit: Dictionary, reception: Dictionary, diagnostic: Dictionary, quote: Dictionary) -> Dictionary:
	var stages: Dictionary = {}
	var gp_staff: Dictionary = world.facts.staff[diagnostic.staff_id]
	var gp_facility: Dictionary = world.facts.facilities[diagnostic.facility_id]
	var gp_effective: float = float(gp_facility.grade)*float(content.balance.medical_equipment_effects.utilization_by_level[int(gp_staff.abilities.diagnosis)])
	_reference_stage(stages,"reception",["staff:"+str(reception.staff_id),"facility:"+str(reception.facility_id)],ceili(float(content.balance.reception_seconds)*10/_talent_rate(world,reception.staff_id,"registration",visit)))
	_reference_stage(stages,"gp",["staff:"+str(diagnostic.staff_id),"facility:"+str(diagnostic.facility_id)],ceili(float(_gp_work_ticks(visit,gp_staff,gp_effective))/_talent_rate(world,gp_staff.id,"gp",visit)))
	var evidence: float = float(_profile(visit).gp_confidence)+2.0*(int(gp_staff.abilities.diagnosis)-1)+2.0*gp_effective
	for mode: String in ["spectrum","resonance"]:
		if evidence>=float(content.balance.diagnosis_threshold):
			break
		var test_pairs: Array = service_candidates(world,visit,mode,true)
		if test_pairs.is_empty():
			return {"ok":false,"reason":"缺少必要检查资格"}
		var test_pair: Dictionary = test_pairs[0]
		var staff: Dictionary = world.facts.staff[test_pair.staff_id]
		var facility: Dictionary = world.facts.facilities[test_pair.facility_id]
		var effective: float = float(facility.grade)*float(content.balance.medical_equipment_effects.utilization_by_level[int(staff.abilities.diagnosis)])
		var seconds: float = float(content.balance.tests[mode].seconds)/(1.0+0.05*(int(staff.abilities.diagnosis)-1)+0.15*effective)
		_reference_stage(stages,mode,["staff:"+str(staff.id),"facility:"+str(facility.id)],ceili(seconds*10/_talent_rate(world,staff.id,"test",visit)))
		evidence += float(content.balance.tests[mode].confidence)+2.0*(int(staff.abilities.diagnosis)-1)+3.0*effective
	if evidence<float(content.balance.diagnosis_threshold):
		return {"ok":false,"reason":"全部合法检查仍未达到诊断阈值"}
	var consulting_doctor: String = quote.staff_ids[0]
	if int(world.facts.staff[consulting_doctor].abilities.treatment)<1:
		return {"ok":false,"reason":"缺少合格会诊医生"}
	_reference_stage(stages,"consult",["staff:"+consulting_doctor,"facility:"+str(diagnostic.facility_id)],ceili(float(content.balance.clinical.consult_seconds)*10))
	var count_n: int = 20000-int(quote.probability_bp)
	var count_d: int = 10000
	var protocol: Dictionary = content.definition("treatment_protocols",content.definition("treatment_plans",quote.plan_id).protocol_id)
	var treatment_ticks: int = int(quote.work_ticks)
	var wake_ticks: int = int(content.balance.clinical.wake_seconds)*10 if protocol.kind=="surgery" else 0
	var setup_ticks: int = ceili(float(content.balance.clinical.or_setup_seconds)*10/(1.0+0.05*(int(world.facts.staff[quote.staff_ids[2]].abilities.surgery)-1))) if protocol.kind=="surgery" else 0
	var work_resources: Array = ["facility:"+str(quote.facility_id)]
	for staff_id: String in quote.staff_ids:
		work_resources.append("staff:"+staff_id)
	_reference_stage(stages,str(protocol.kind),work_resources,treatment_ticks+wake_ticks,count_n,count_d)
	if setup_ticks>0:
		_reference_stage(stages,"surgery_setup",["facility:"+str(quote.facility_id),"staff:"+str(quote.staff_ids[2])],setup_ticks,count_n,count_d)
	var bed_ticks: int = 0
	if int(quote.recovery_ticks)>0:
		var nurse: Dictionary = world.facts.staff[quote.nurse_id]
		var bed: Dictionary = world.facts.facilities[quote.bed_id]
		var bed_effective: float = float(bed.grade)*float(content.balance.medical_equipment_effects.utilization_by_level[int(nurse.abilities.care)])
		var recovery_ticks: int = ceili(float(quote.recovery_ticks)/(1.0+0.15*bed_effective))
		var care_ticks: int = ceili(float(content.balance.clinical.nurse_visit_seconds)*10/(1.0+0.05*(int(nurse.abilities.care)-1)))
		var round_doctor: Dictionary = world.facts.staff[quote.round_doctor_id]
		var round_ticks: int = ceili(float(content.balance.clinical.discharge_round_seconds)*10/(1.0+0.05*(int(round_doctor.abilities.treatment)-1)))
		bed_ticks = setup_ticks+treatment_ticks+wake_ticks+maxi(recovery_ticks,care_ticks)+round_ticks
		_reference_stage(stages,"bed",["facility:"+str(quote.bed_id),"coverage:"+str(quote.nurse_id)+":"+str(quote.ward_id)],bed_ticks,count_n,count_d)
		_reference_stage(stages,"care",["staff:"+str(quote.nurse_id)],care_ticks,count_n,count_d)
		_reference_stage(stages,"round",["staff:"+str(quote.round_doctor_id)],round_ticks,count_n,count_d)
	var resources: Dictionary = {}
	var structural: Array = []
	for stage: Dictionary in stages.values():
		for resource_id: String in stage:
			var amount: Dictionary = stage[resource_id]
			if not resources.has(resource_id):
				resources[resource_id] = {"n":"0","d":str(count_d)}
			resources[resource_id].n = str(str(resources[resource_id].n).to_int()+str(amount.n).to_int()*(count_d/str(amount.d).to_int()))
			if resource_id.begins_with("coverage:") or resource_id=="staff:"+str(reception.staff_id) or resource_id=="facility:"+str(reception.facility_id) or resource_id=="staff:"+str(quote.get("nurse_id","")):
				continue
			if not resource_id in structural:
				structural.append(resource_id)
	structural.sort()
	return {"ok":true,"plan_id":quote.plan_id,"resources":resources,"stage_resources":stages,"structural_resources":structural,
		"reception_id":reception.facility_id,"gp_id":diagnostic.facility_id,"terminal_id":quote.facility_id,"staff_ids":quote.staff_ids.duplicate(),
		"bed_id":str(quote.get("bed_id","")),"ward_id":str(quote.get("ward_id","")),"coverage_nurse_id":str(quote.get("nurse_id","")),
		"bed_ticks":{"n":str(bed_ticks*count_n),"d":str(count_d)},"expected_attempts":{"n":str(count_n),"d":str(count_d)},"supply_units":quote.supply_units}

func _reference_stage(stages: Dictionary, kind: String, resources: Array, ticks: int, numerator: int = 1, denominator: int = 1) -> void:
	stages[kind] = {}
	for id: String in resources:
		stages[kind][id] = {"n":str(ticks*numerator),"d":str(denominator)}

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

func _can_start(staff: Dictionary) -> bool:
	return not staff.has("clinical_release") and bool(staff.get("base_prepared",true)) and not bool(staff.get("block_new_work",false)) and not bool(staff.get("supply_strike",false)) and str(staff.get("life_task",{}).get("phase","idle"))=="idle" and float(staff.energy)>15.0 and (staff.role!="doctor" or float(staff.fatigue)<float(content.balance.wellbeing.fatigue_stop_new_work))

func _use(world: WorldState, facility: Dictionary, receipt_id: String) -> void:
	facility = world.facts.facilities[facility.id]
	facility.used = true
	if world.facts.rooms.has(facility.get("room_id","")):
		world.facts.rooms[facility.room_id].used = true
	if not facility.use_receipts.has(receipt_id):
		facility.use_receipts[receipt_id] = world.facts.sim_tick
		if not facility.definition_id in content.balance.equipment.maintained_definition_ids:
			return
		var definition: Dictionary = content.facility_definition(facility.definition_id)
		for equipment_class: Dictionary in content.balance.equipment.classes:
			if equipment_class.id == definition.equipment_class:
				facility.condition = maxf(0.0,float(facility.condition)-float(equipment_class.wear_per_use))
