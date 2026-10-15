class_name HospitalClinic
extends RefCounted

var content: HospitalContent
var space: HospitalSpace
var waiting_life: RefCounted
var departments: RefCounted
var environment: RefCounted
var _worked_staff: Dictionary = {}
var _practice_awards: Dictionary = {}
var _events: Array[SimEvent] = []

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry

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
	return CommandResult.new(false,"unknown_command","未知临床命令",[],world.revision)

func _arrive(world: WorldState, payload: Dictionary) -> CommandResult:
	var binding: Dictionary = content.definition("treatment_bindings",str(payload.get("binding_id","")))
	if binding.is_empty():
		return CommandResult.new(false,"binding_missing","病例缺少完整身体与治疗适配",[],world.revision)
	var key: String = str(payload.get("arrival_key",""))
	if key.is_empty():
		return CommandResult.new(false,"arrival_identity_missing","到院请求缺少稳定身份",[],world.revision)
	if not world.facts.has("arrival_receipts"):
		world.facts.arrival_receipts = {}
	if world.facts.arrival_receipts.has(key):
		var original: String = world.facts.arrival_receipts[key]
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
	world.facts.arrival_receipts[key] = visit_id
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
			var exit_cell: Array = world.facts.get("entry",{}).get("exit_cell",[48,95])
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
		if stay.phase == "release_wait" and world.facts.actors[visit.actor_id].get("posture","standing")=="lying":
			var completed_bed: Dictionary = space.facility_layout(world,stay.bed_id)
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
				_support(world,visit,bed,"lying")
				_use(world,bed,stay.attempt_id)
				_practice(world,stay.escort_id,"care",stay.attempt_id+":escort")
				var table: Dictionary = world.facts.facilities["or"]
				space.request_move(world,stay.escort_id,int(table.floor_id),table.operator_cells[2])
		elif stay.phase == "recovery" and not stay.care_completed and not _staff_busy(world,stay.nurse_id):
			_start_bed_service(world,visit,stay,"care",stay.nurse_id,float(content.balance.clinical.nurse_visit_seconds))
		elif stay.phase == "round_wait" and not _staff_busy(world,stay.round_doctor_id):
			_start_bed_service(world,visit,stay,"round",stay.round_doctor_id,float(content.balance.clinical.discharge_round_seconds))

func advance(world: WorldState) -> void:
	for session_id: String in world.ids("sessions"):
		if not world.facts.sessions.has(session_id):
			continue
		var session: Dictionary = world.facts.sessions[session_id]
		var facility: Dictionary = world.facts.facilities[session.facility_id]
		if facility.failed and session.kind != "wake":
			world.facts.visits[session.visit_id].waiting_reason = "设备暂停，保留原工作和承诺结果"
			continue
		for staff_id: String in session.staff_ids:
			_worked_staff[staff_id] = true
		session.remaining_ticks -= 1
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
		var location: Dictionary = world.facts.actors[stay.nurse_id].location
		var ward: Dictionary = world.facts.rooms[bed.room_id]
		var ward_rect: Rect2 = Rect2(float(ward.origin[0]),float(ward.origin[1]),float(ward.size[0]),float(ward.size[1]))
		var covering: bool = nurse.on_shift and "q_ward" in nurse.certificates and nurse.ward_id==ward.id and not bed.failed and location.kind == "floor" and int(location.floor_id) == int(bed.floor_id) and ward_rect.has_point(Vector2(float(location.get("cell",[0,0])[0]),float(location.get("cell",[0,0])[1])))
		if not covering:
			world.facts.visits[world.facts.attempts[stay.attempt_id].visit_id].waiting_reason = "等待本病房实际护理覆盖"
			continue
		var effective: float = float(bed.grade) * float(content.balance.medical_equipment_effects.utilization_by_level[int(nurse.abilities.care)])
		stay.work_credit_milli += roundi((1.0 + 0.15 * effective) * 1000)
		var credit: int = int(stay.work_credit_milli) / 1000
		stay.work_credit_milli = int(stay.work_credit_milli) % 1000
		stay.remaining_ticks = maxi(0,int(stay.remaining_ticks)-credit)
		if int(stay.remaining_ticks) == 0 and stay.care_completed:
			stay.phase = "round_wait"
			world.facts.visits[world.facts.attempts[stay.attempt_id].visit_id].phase = "round_wait"

func release_departed(world: WorldState) -> void:
	for stay_id: String in world.ids("ward_stays"):
		var stay: Dictionary = world.facts.ward_stays[stay_id]
		if stay.phase == "release_wait":
			var visit: Dictionary = world.facts.visits[world.facts.attempts[stay.attempt_id].visit_id]
			var bed: Dictionary = world.facts.facilities[stay.bed_id]
			if not space.overlaps_facility(world,visit.actor_id,stay.bed_id):
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
	if kind=="gp" and departments!=null and not departments.call("route_patient",world,visit.id):
		return
	var facility_id: String = {"reception":"reception_desk","gp":"gp","spectrum":"exam",
		"resonance":"exam","consult":"gp","outpatient":"treatment"}.get(kind,"")
	var staff_id: String = {"reception":"reception","gp":"gp_doctor","spectrum":"exam_nurse",
		"resonance":"exam_nurse","consult":"gp_doctor","outpatient":"treat_doctor"}.get(kind,"")
	if int(world.facts.get("gameplay_version",0)) >= 1:
		var candidates: Array = service_candidates(world,visit,kind)
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
			return
		if not world.facts.preparations.has(visit.id):
			world.facts.preparations[visit.id] = {"id":visit.id,"visit_id":visit.id,"kind":"outpatient","bed_id":"","facility_id":facility_id,"staff_ids":[staff_id],
				"supply_units":int(ready_quote.supply_units),"setup_remaining_ticks":0,"deadline_tick":world.sim_tick+int(content.balance.supplies.reservation_seconds)*10}
	var fit_reason: String = space.reserve_facility(world,facility_id,visit.actor_id,ticket.id,[staff_id])
	if not fit_reason.is_empty():
		visit.waiting_reason = fit_reason
		return
	facility = space.facility_layout(world,facility_id)
	if not _gather(world,visit,facility,[staff_id]):
		return
	var ticks: int = 0
	var effective: float = float(facility.grade) * float(content.balance.medical_equipment_effects.utilization_by_level[int(staff.abilities[track])]) if kind != "reception" else 0.0
	var session_data: Dictionary = {"evidence":0.0,"doctor_fee":0,"facility_fee":content.facility_fee(facility.definition_id,kind)}
	match kind:
		"reception":
			ticks = ceili(float(content.balance.reception_seconds)*10)
		"gp":
			ticks = _gp_work_ticks(visit,staff,effective)
			var profile: Dictionary = _profile(visit)
			session_data.evidence = minf(100.0,float(profile.gp_confidence)+2.0*(int(staff.abilities.diagnosis)-1)+2.0*effective)
			if int(visit.doctor_fee_quote) < 0:
				visit.doctor_fee_quote = content.doctor_fee(staff.title_id)
			session_data.doctor_fee = visit.doctor_fee_quote
		"spectrum", "resonance":
			var seconds: float = 18.0 if kind == "spectrum" else 22.0
			if staff.role=="doctor":
				seconds *= 1.0+float(content.balance.wellbeing.fatigue_work_multiplier_per_point)*float(staff.fatigue)
			ticks = ceili(seconds/(1.0+0.05*(int(staff.abilities.diagnosis)-1)+0.15*effective)*10)
			session_data.evidence = (35.0 if kind == "spectrum" else 25.0)+2.0*(int(staff.abilities.diagnosis)-1)+3.0*effective
		"consult":
			ticks = ceili(maxf(4.0,float(content.balance.clinical.consult_seconds)*(1.0+0.003*float(staff.fatigue)))*10)
		"outpatient":
			var quote: Dictionary = _outpatient_quote(world,visit,staff,facility)
			if not quote.ok:
				visit.waiting_reason = quote.reason
				return
			var attempt: Dictionary = _commit_attempt(world,visit,quote)
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

func service_candidates(world: WorldState, visit: Dictionary, kind: String) -> Array:
	var equipment_id: String = "FUR01" if kind == "reception" else "FUR02"
	if kind == "outpatient":
		var binding: Dictionary = content.definition("treatment_bindings",visit.binding_id)
		equipment_id = str(content.definition("treatment_routines",binding.routine_id).equipment_id)
	var candidates: Array = []
	var preparation: Dictionary = world.facts.preparations.get(visit.id,{})
	for facility_id: String in world.ids("facilities"):
		var facility: Dictionary = world.facts.facilities[facility_id]
		if not preparation.is_empty() and preparation.facility_id!=facility_id:
			continue
		if facility.definition_id != equipment_id or facility.failed or _facility_busy(world,facility_id,visit.id):
			continue
		for staff_id: String in world.ids("staff"):
			var staff: Dictionary = world.facts.staff[staff_id]
			if not preparation.is_empty() and not staff_id in preparation.staff_ids:
				continue
			if _staff_busy(world,staff_id,visit.id) or not staff.on_shift or not _can_start(staff):
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

func _outpatient_quote(world: WorldState, visit: Dictionary, staff: Dictionary, facility: Dictionary) -> Dictionary:
	var profile: Dictionary = _profile(visit)
	if _available_supplies(world,visit.id)<int(profile.supply_units):
		return {"ok":false,"reason":"治疗包不足，保留原票号"}
	if visit.attempt_ids.size()>=int(content.balance.max_treatment_attempts):
		return {"ok":false,"reason":"已达到实际治疗次数上限"}
	if int(staff.abilities.treatment) < int(profile.min_skill):
		return {"ok":false,"reason":"医生治疗等级不足"}
	var effective: float = float(facility.grade)*float(content.balance.medical_equipment_effects.utilization_by_level[int(staff.abilities.treatment)])
	var probability: float = clampf(float(profile.base_success)+0.02*(int(staff.abilities.treatment)-1)+0.025*effective
		- (0.03 if float(staff.energy)<35.0 else 0.0) - (0.04 if float(facility.condition)<40.0 else 0.0)
		+ (0.15 if not visit.attempt_ids.is_empty() else 0.0) - (0.18 if visit.complex else 0.0),0.70,0.98)
	if probability < float(content.balance.clinical.minimum_predicted_success):
		return {"ok":false,"reason":"预计效果低于原安全底线"}
	var binding: Dictionary = content.definition("treatment_bindings",visit.binding_id)
	var routine: Dictionary = content.definition("treatment_routines",binding.routine_id)
	if routine.equipment_id != facility.definition_id:
		return {"ok":false,"reason":"病例与医疗主体不适配"}
	var seconds: float = float(routine.service_seconds)/(1.0+0.05*(int(staff.abilities.treatment)-1)+0.2*effective)*(1.0+0.003*float(staff.fatigue))
	return {"ok":true,"plan_id":visit.plan_decision.plan_id,"probability_bp":floori(probability*10000),
		"work_ticks":ceili(seconds*10),"recovery_ticks":0,"supply_units":int(profile.supply_units),
		"cure_fee":int(content.definition("diseases",visit.disease_id).cure_fee),"facility_fee":content.facility_fee(facility.definition_id,"outpatient"),
		"staff_ids":[staff.id],"effective_level":effective}

func _prepare_surgery(world: WorldState, visit: Dictionary, ticket: Dictionary) -> void:
	var team: Array = ["surgeon","anesthetist","or_nurse"]
	var quote: Dictionary = _surgery_quote(world,visit,team)
	if not quote.ok:
		world.facts.preparations.erase(visit.id)
		visit.waiting_reason = quote.reason
		return
	var preparation: Dictionary = world.facts.preparations.get(visit.id,{})
	if preparation.is_empty():
		if _facility_busy(world,"or") or _bed_busy(world,"bed"):
			visit.waiting_reason = "等待手术台及同层兼容床位"
			return
		for staff_id: String in team:
			if _staff_busy(world,staff_id):
				visit.waiting_reason = "等待完整互异团队"
				return
		preparation = {"id":visit.id,"visit_id":visit.id,"bed_id":"bed","facility_id":"or","staff_ids":team,
			"deadline_tick":int(world.facts.sim_tick)+int(content.balance.clinical.bed_reservation_seconds)*10,
			"setup_remaining_ticks":ceili(float(content.balance.clinical.or_setup_seconds)*10/(1.0+0.05*(int(world.facts.staff.or_nurse.abilities.surgery)-1)))}
		world.facts.preparations[visit.id] = preparation
		var table_reason: String = space.reserve_facility(world,"or",visit.actor_id,visit.id,team)
		var bed_reason: String = space.reserve_facility(world,"bed",visit.actor_id,visit.id,["ward_nurse","round_doctor"]) if table_reason.is_empty() else ""
		if not table_reason.is_empty() or not bed_reason.is_empty():
			visit.waiting_reason = table_reason if not table_reason.is_empty() else bed_reason
			world.facts.preparations.erase(visit.id)
			return
	if int(world.facts.sim_tick) >= int(preparation.deadline_tick):
		world.facts.preparations.erase(visit.id)
		visit.waiting_reason = "准备超过30秒，原票号保留；资源已释放"
		return
	var facility: Dictionary = space.facility_layout(world,"or")
	if not _gather(world,visit,facility,team):
		return
	if int(preparation.setup_remaining_ticks) > 0:
		_worked_staff[team[2]] = true
		preparation.setup_remaining_ticks -= 1
		visit.waiting_reason = "护士正在真实器械核对"
		return
	# Recheck the entire bundle at the actual start, not a cached authorization.
	quote = _surgery_quote(world,visit,team)
	if not quote.ok:
		visit.waiting_reason = quote.reason
		return
	var attempt: Dictionary = _commit_attempt(world,visit,quote)
	world.facts.ward_stays[attempt.id] = {"id":attempt.id,"attempt_id":attempt.id,"bed_id":"bed","phase":"reserved",
		"remaining_ticks":attempt.recovery_ticks,"work_credit_milli":0,"care_completed":false,
		"nurse_id":"ward_nurse","round_doctor_id":"round_doctor","escort_id":"or_nurse"}
	if world.facts.adaptations.has("bed"):
		world.facts.adaptations.bed.owner_id = attempt.id
	_start(world,visit,"surgery","or",team,int(attempt.work_ticks),{"attempt_id":attempt.id})
	_support(world,visit,facility,"lying")
	_use(world,facility,attempt.id)
	world.facts.preparations.erase(visit.id)
	world.facts.tickets.erase(ticket.id)
	visit.ticket_id = ""
	visit.phase = "surgery"
	visit.waiting_reason = ""

func _surgery_quote(world: WorldState, visit: Dictionary, team: Array) -> Dictionary:
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
		if not staff.on_shift or not _can_start(staff) or int(staff.abilities.surgery) < int(requirements[index]):
			return {"ok":false,"reason":"手术人员未在班或资格不足"}
		if index < 2 and int(content.definition("doctor_titles",staff.title_id).rank) < int(content.definition("doctor_titles",titles[index]).rank):
			return {"ok":false,"reason":"外科职称不足"}
		if index == 2 and not "q_or" in staff.certificates:
			return {"ok":false,"reason":"护士未取得手术资格"}
		utilization_sum += float(content.balance.medical_equipment_effects.utilization_by_level[int(staff.abilities.surgery)])
	if team[0] == team[1] or team[0] == team[2] or team[1] == team[2]:
		return {"ok":false,"reason":"手术岗位必须互异"}
	if not world.facts.facilities.has("or") or not world.facts.facilities.has("bed") or not world.facts.staff.has("ward_nurse"):
		return {"ok":false,"reason":"手术台、同层床或病房覆盖缺失"}
	var table: Dictionary = world.facts.facilities["or"]
	var bed: Dictionary = world.facts.facilities.bed
	if table.get("room_id","").is_empty() or bed.get("room_id","").is_empty():
		return {"ok":false,"reason":"手术台与护理床缺少合法房间"}
	var operating_room: Dictionary = world.facts.rooms[table.room_id]
	var ward: Dictionary = world.facts.rooms[bed.room_id]
	if operating_room.kind != "operating_room" or ward.kind != "ward" or int(operating_room.floor_id)!=int(ward.floor_id) or int(operating_room.size[0])<8 or int(operating_room.size[1])<8 or int(ward.size[0])<6 or int(ward.size[1])<6:
		return {"ok":false,"reason":"临床房间或同层照护不合格"}
	var cover: Dictionary = world.facts.staff.ward_nurse
	var cover_location: Dictionary = world.facts.actors.ward_nurse.location
	var ward_rect: Rect2 = Rect2(float(ward.origin[0]),float(ward.origin[1]),float(ward.size[0]),float(ward.size[1]))
	if not "q_ward" in cover.certificates or cover.ward_id != ward.id or cover_location.kind != "floor" or int(cover_location.floor_id)!=int(ward.floor_id) or not ward_rect.has_point(Vector2(float(cover_location.cell[0]),float(cover_location.cell[1]))):
		return {"ok":false,"reason":"护理护士尚未在本病房实际到岗"}
	if table.failed or bed.failed or not world.facts.staff.ward_nurse.on_shift:
		return {"ok":false,"reason":"手术台、床或当前病房覆盖不可用"}
	if int(world.facts.inventory.units) < int(protocol.supply_units):
		return {"ok":false,"reason":"治疗包不足"}
	var compatible: bool = false
	for adapter: Dictionary in content.catalog.surgical_adapters:
		if adapter.binding_id == visit.binding_id and adapter.plan_id == plan.id:
			compatible = true
	if not compatible:
		return {"ok":false,"reason":"病例缺少合法手术承托适配"}
	for facility_id: String in ["or","bed"]:
		var fit: Dictionary = space.facility_quote(world,facility_id,visit.actor_id,team if facility_id=="or" else ["ward_nurse","round_doctor"])
		if not fit.ok:
			return fit
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
	for staff_id: String in team:
		var consumption: float = float(content.balance.wellbeing.energy_work_per_second)*(seconds+float(content.balance.clinical.wake_seconds)+float(content.balance.clinical.or_setup_seconds))
		if float(world.facts.staff[staff_id].energy)-consumption<=15.0:
			return {"ok":false,"reason":"团队体力不足以安全覆盖操作和苏醒全过程"}
	return {"ok":true,"plan_id":plan.id,"probability_bp":floori(probability*10000),"work_ticks":ceili(seconds*10),
		"recovery_ticks":ceili(float(protocol.recovery_seconds)*10),"supply_units":int(protocol.supply_units),
		"cure_fee":ceili(float(content.definition("diseases",visit.disease_id).cure_fee)*float(protocol.cure_fee_multiplier)),
		"facility_fee":content.facility_fee(table.definition_id,"surgery"),"staff_ids":team.duplicate(),"effective_level":effective}

func _commit_attempt(world: WorldState, visit: Dictionary, quote: Dictionary) -> Dictionary:
	var id: String = world.new_id("attempt")
	var attempt: Dictionary = quote.duplicate(true)
	attempt.erase("ok")
	attempt.id = id
	attempt.visit_id = visit.id
	attempt.result = world.draw("treatment",10000) < int(attempt.probability_bp)
	attempt.start_tick = world.facts.sim_tick
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
	if departments != null:
		departments.call("service_started",world,session)
	_events.append(SimEvent.new(world.sim_tick,"service_started",[visit.id,id],{"kind":kind}))
	if world.facts.adaptations.has(facility_id):
		world.facts.adaptations[facility_id].owner_id = str(extra.get("attempt_id",id))
	return session

func _complete_service(world: WorldState, session: Dictionary) -> void:
	if not world.facts.sessions.has(session.id):
		return
	var visit: Dictionary = world.facts.visits[session.visit_id]
	var reservation: Dictionary = world.facts.adaptations.get(session.facility_id,{})
	if reservation.get("owner_id","")==session.id:
		reservation.owner_id = visit.actor_id
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
			else:
				_queue(world,visit,"resonance")
		"consult":
			var plan_id: String = visit.requested_plan_id
			var protocol: Dictionary = content.definition("treatment_protocols",content.definition("treatment_plans",plan_id).protocol_id)
			visit.plan_decision = {"plan_id":plan_id,"source":"director","doctor_id":session.staff_ids[0],"revision":1,"reason":"样板医院既有指定"}
			_queue(world,visit,str(protocol.kind))
		"outpatient":
			var attempt: Dictionary = world.facts.attempts[session.attempt_id]
			if environment != null:
				environment.call("record_use",world,"outpatient_completed",session.facility_id,attempt.id)
			HospitalLedger.post(world,LedgerEntry.new(attempt.id,"outpatient",int(attempt.facility_fee)),false)
			_practice(world,session.staff_ids[0],"treatment",session.id)
			_settle(world,visit,attempt)
		"surgery":
			_start(world,visit,"wake",session.facility_id,session.staff_ids,int(content.balance.clinical.wake_seconds)*10,{"attempt_id":session.attempt_id})
			visit.phase = "wake"
		"wake":
			var attempt: Dictionary = world.facts.attempts[session.attempt_id]
			HospitalLedger.post(world,LedgerEntry.new(attempt.id,"surgery",int(attempt.facility_fee)),false)
			for staff_id: String in session.staff_ids:
				_practice(world,staff_id,"surgery",attempt.id)
			world.facts.ward_stays[attempt.id].phase = "transfer"
			visit.phase = "transfer"
		"care":
			world.facts.ward_stays[session.stay_id].care_completed = true
			_practice(world,session.staff_ids[0],"care",session.id)
		"round":
			var stay: Dictionary = world.facts.ward_stays[session.stay_id]
			var attempt: Dictionary = world.facts.attempts[stay.attempt_id]
			HospitalLedger.post(world,LedgerEntry.new(attempt.id,"ward",content.facility_fee("EQ05","ward")),false)
			_practice(world,session.staff_ids[0],"treatment",visit.id+":round")
			stay.phase = "release_wait"
			_settle(world,visit,attempt)
			var ward: Dictionary = world.facts.rooms[world.facts.facilities[stay.bed_id].room_id]
			space.request_move(world,session.staff_ids[0],int(ward.floor_id),[int(ward.origin[0])+int(ward.size[0])-2,int(ward.origin[1])+int(ward.size[1])-2])

func _start_bed_service(world: WorldState, visit: Dictionary, stay: Dictionary, kind: String, staff_id: String, seconds: float) -> void:
	var bed: Dictionary = space.facility_layout(world,stay.bed_id)
	var staff: Dictionary = world.facts.staff[staff_id]
	if not staff.on_shift or not _can_start(staff) or bed.failed:
		visit.waiting_reason = "等待可以安全执行床边工作的医护"
		return
	if kind == "round" and (int(staff.abilities.diagnosis)<2 or int(staff.abilities.treatment)<1):
		visit.waiting_reason = "等待具备查房资格的医生"
		return
	var index: int = 0 if kind == "care" else 1
	if kind == "round" and space.at(world,stay.nurse_id,int(bed.floor_id),bed.operator_cells[index]):
		var ward: Dictionary = world.facts.rooms[bed.room_id]
		space.request_move(world,stay.nurse_id,int(bed.floor_id),[int(ward.origin[0]),int(ward.origin[1])+int(ward.size[1])-1])
		return
	if not space.at(world,staff_id,int(bed.floor_id),bed.operator_cells[index]):
		visit.waiting_reason = space.request_move(world,staff_id,int(bed.floor_id),bed.operator_cells[index])
		return
	var level: int = int(staff.abilities.care) if kind == "care" else int(staff.abilities.treatment)
	if staff.role=="doctor":
		seconds *= 1.0+float(content.balance.wellbeing.fatigue_work_multiplier_per_point)*float(staff.fatigue)
	_start(world,visit,kind,stay.bed_id,[staff_id],ceili(seconds/(1.0+0.05*(level-1))*10),{"stay_id":stay.id})
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
		_queue(world,visit,"surgery" if content.definition("treatment_protocols",content.definition("treatment_plans",attempt.plan_id).protocol_id).kind == "surgery" else "outpatient")
	else:
		visit.final_result = "referred"
		visit.phase = "leaving"

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

func _bed_busy(world: WorldState, id: String) -> bool:
	for stay: Dictionary in world.facts.ward_stays.values():
		if stay.bed_id == id:
			return true
	for preparation: Dictionary in world.facts.preparations.values():
		if preparation.bed_id == id:
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
	return bool(staff.get("base_prepared",true)) and not bool(staff.get("block_new_work",false)) and not bool(staff.get("supply_strike",false)) and str(staff.get("life_task",{}).get("phase","idle"))=="idle" and float(staff.energy)>15.0 and (staff.role!="doctor" or float(staff.fatigue)<float(content.balance.wellbeing.fatigue_stop_new_work))

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
