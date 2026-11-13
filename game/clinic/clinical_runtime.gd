class_name HospitalClinic
extends RefCounted

const LEGACY_SERVICE_FACILITIES: Dictionary = {"gp":"gp","spectrum":"exam","resonance":"exam","consult":"gp","outpatient":"treatment"}
const LEGACY_SERVICE_STAFF: Dictionary = {"gp":"gp_doctor","spectrum":"exam_nurse","resonance":"exam_nurse","consult":"gp_doctor","outpatient":"treat_doctor"}

const ResearchJobs = preload("res://game/community/research_job_index.gd")
var _research_jobs: RefCounted = ResearchJobs.new()

const Visitors = preload("res://game/clinic/hospital_visitors.gd")
const Flow = preload("res://game/clinic/clinical_flow.gd")

var content: HospitalContent
var space: HospitalSpace
var floor_guidance: HospitalFloorGuidance
var waiting_life: RefCounted
var experience: RefCounted
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
	if waiting_life!=null: visitors.waiting_life=weakref(waiting_life)
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
		if not stay.get("phase","") in ["admitting","waiting_surgery","to_surgery","return_preop","reserved","transfer","recovery","release_wait","referral_release"] or not WorldState._natural(stay.get("remaining_ticks",-1)) or not WorldState._natural(stay.get("work_credit_milli",-1)) or int(stay.work_credit_milli)>=1000 or not stay.get("care_completed") is bool:
			return "住院阶段、恢复余量或护理完成事实无效"
		if stay.phase=="admitting":
			if stay.has("admitted_tick") or not stay.attempt_id.is_empty(): return "尚未入住不能保存入住或开术事实"
		elif not WorldState._natural(stay.get("admitted_tick")) or int(stay.admitted_tick)>world.sim_tick:
			return "住院缺少实际入住时刻"
		if stay.phase in ["reserved","recovery"] and not world.facts.attempts.has(stay.get("attempt_id","")): return "手术或恢复阶段缺少实际开工尝试"
		if stay.phase in ["waiting_surgery","to_surgery","return_preop"] and (int(stay.remaining_ticks)!=0 or int(stay.work_credit_milli)!=0): return "术前候诊不能保存未来恢复工作量"
		for field: String in ["nurse_id","escort_id"]:
			if not world.facts.staff.has(stay.get(field,"")):
				return "住院护理覆盖或陪护人员引用无效"
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
		"clinical_transfer_bed", "clinical_ward_refer", "clinical_visit_consent":
			return _ward_command(world,kind,payload)
	return CommandResult.new(false,"unknown_command","未知临床命令",[],world.revision)

func _change_plan(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	var id: String = str(payload.get("visit_id",""))
	var visit: Dictionary = world.facts.visits.get(id,{})
	if visit.is_empty() or not str(visit.phase).begins_with("wait_"):
		return CommandResult.new(false,"clinical_busy","请选择正在候诊且尚未开工的病例",[],world.revision)
	if visit.get("diagnosis",{}).get("state","")!="diagnosed":
		return CommandResult.new(false,"diagnosis_pending","完成诊断后才能安排治疗方案",[],world.revision)
	if world.facts.tickets.get(visit.get("ticket_id",""),{}).has("resume_session_id"):
		return CommandResult.new(false,"clinical_busy","原疗程已开工，安全暂停期间仍保留原方案",[],world.revision)
	if kind == "clinical_auto_plan":
		Flow.reconsider(self,world,visit)
		return CommandResult.new(true,"applied","",[id],world.revision)
	var plan_id: String = str(payload.get("plan_id",visit.plan_decision.get("plan_id","")))
	# Choosing a surgical plan precedes admission and OR scheduling. It does
	# not require the future team's current availability or reserve its supplies.
	var quote: Dictionary = selection_quote(world,id,plan_id) if kind=="clinical_select_plan" else plan_quote(world,id,plan_id)
	if not quote.ok:
		return CommandResult.new(false,"plan_not_ready",quote.reason,[],world.revision)
	if payload.has("probability_bp") and int(payload.probability_bp)!=int(quote.probability_bp):
		return CommandResult.new(false,"material_change","当前预计效果已改变，请刷新本次方案",[],world.revision)
	if content.definition("treatment_protocols",content.definition("treatment_plans",plan_id).protocol_id).kind!="surgery": Flow.release_unadmitted(self,world,visit)
	_release_preparation(world,id)
	visit.requested_plan_id = plan_id
	visit.plan_decision = {"plan_id":plan_id,"source":"director","doctor_id":str(Flow.diagnosis(visit).doctor_id),
		"revision":int(visit.plan_decision.get("revision",0))+1,"probability_bp":int(quote.probability_bp),"reason":"院长指定当前合法方案","expected_team":quote.staff_ids.duplicate()}
	var stay: Dictionary=Flow.ward_stay(world,visit.id)
	if not stay.is_empty() and stay.phase=="to_surgery": stay.phase="return_preop"
	_retarget_ticket(world,visit,str(content.definition("treatment_protocols",content.definition("treatment_plans",plan_id).protocol_id).kind))
	return CommandResult.new(true,"applied","",[id],world.revision)

func _retarget_ticket(world: WorldState, visit: Dictionary, kind: String) -> void:
	if not world.facts.tickets.has(visit.ticket_id):
		_queue(world,visit,kind)
		return
	var ticket: Dictionary = world.facts.tickets[visit.ticket_id]
	_release_preparation(world,visit.id)
	ticket.kind = kind
	ticket.service_assigned = false
	ticket.called_tick = -1
	visit.phase = "wait_"+kind
	visit.waiting_reason = ""

func _arrive(world: WorldState, payload: Dictionary) -> CommandResult:
	var entry_error: String = world.entry_validation_error()
	if not entry_error.is_empty():
		return CommandResult.new(false,"invalid_hospital_entry",entry_error,[],world.revision)
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
		# Static and dynamic entry checks above already cover this synchronous
		# admission. Keep public/overridden readiness fully validating for callers.
		var readiness: Dictionary
		if get_script()==load("res://game/clinic/clinical_runtime.gd"):
			readiness = _arrival_case_readiness(world,binding)
		else:
			readiness = arrival_readiness(world,binding.id,bool(payload.get("complex",false)))
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
		"anger":float(personality.initial_anger),"phase":"arrival","diagnosis":{},"attempt_ids":[],"plan_decision":{},
		"complex":bool(payload.get("complex",false)),"final_result":"","waiting_reason":"","ticket_id":"","doctor_fee_quote":-1,
		"arrived_tick":world.sim_tick,"arrival_key":key}
	world.facts.visits[visit_id].last_progress_tick = world.sim_tick
	world.facts.visits[visit_id].last_service_tick = world.sim_tick
	world.register_visit(visit_id)
	if research!=null: research.call("record_arrival",world,world.facts.visits[visit_id])
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
	var need: Dictionary = world.facts.get("waiting_life",{}).get("needs",{}).get(visit_id,{})
	if need.get("phase","") in ["using","fallback","returning"]: return false
	var movement: Dictionary = world.facts.moves.get(visit.actor_id,{})
	if movement.has("detour") or not space.movement._member_owner(world,visit.actor_id).is_empty(): return false
	var suspended: bool = false
	for record: Dictionary in world.facts.get("clinical_suspensions",{}).values():
		if record.visit_id==visit_id: suspended = true
	for stay: Dictionary in world.facts.ward_stays.values().duplicate():
		if stay.visit_id == visit_id:
			if not stay.has("admitted_tick"):
				Flow.release_unadmitted(self,world,visit)
				continue
			if suspended and stay.phase=="reserved":
				world.facts.ward_stays.erase(stay.id)
				continue
			return false
	for id: String in world.facts.get("clinical_suspensions",{}).keys():
		if world.facts.clinical_suspensions[id].visit_id==visit_id: world.facts.clinical_suspensions.erase(id)
	_release_preparation(world,visit_id)
	var life: HospitalWaitingLife = waiting_life as HospitalWaitingLife
	if life==null: life = HospitalWaitingLife.new(content,space)
	life.release_for_departure(world,visit_id)
	# The arrival service commits an abandonment decision after this returns.
	# Referral discards only an unselected record; selected history remains.
	var departure: Dictionary = world.facts.get("wait_departures",{}).get(visit.actor_id,{})
	if result!="abandoned" and not departure.is_empty() and not departure.get("selected",false): world.facts.wait_departures.erase(visit.actor_id)
	if floor_guidance!=null: floor_guidance.release(world,visit.id)
	world.facts.tickets.erase(visit.ticket_id)
	visit.ticket_id = ""
	visit.final_result = result
	visit.phase = "leaving"
	visit.waiting_reason = ""
	return true

func _release_preparation(world: WorldState, visit_id: String) -> void:
	world.facts.preparations.erase(visit_id)
	# Completed service may already have handed the envelope to the patient
	# Actor. Cancellation still owes its idle gathering staff a real exit.
	var owners: Array = [visit_id,str(world.facts.visits[visit_id].get("ticket_id","")),str(world.facts.visits[visit_id].actor_id)]
	for reservation: Dictionary in world.facts.adaptations.values():
		if reservation.kind=="facility" and reservation.owner_id in owners:
			# Cancelled work no longer owns space. Any body still inside keeps
			# its physical envelope until it has actually walked clear.
			_release_gathering_staff(world,visit_id,reservation)
			reservation.owner_id = reservation.actor_id
	space.release_adaptations(world)
	_dispatch_clinical_releases(world)

func _release_gathering_staff(world: WorldState, visit_id: String, reservation: Dictionary) -> void:
	for index: int in reservation.get("staff_ids",[]).size():
		var staff_id: String = str(reservation.staff_ids[index])
		if not world.facts.staff.has(staff_id) or _staff_busy(world,staff_id,visit_id): continue
		var movement: Dictionary = world.facts.moves.get(staff_id,{})
		var approaching: bool = index<reservation.get("operator_cells",[]).size() and _gathering_move(movement,int(reservation.floor_id),reservation.operator_cells[index])
		# Access permission alone (for example a future recovery bed) is not
		# an active assignment and must not claim a worker's unrelated movement.
		if not approaching and not _inside_release_region(world.facts.actors[staff_id],reservation): continue
		var release: Dictionary = {"facility_id":reservation.facility_id,"visit_id":visit_id,"phase":"seek","reason":""}
		if approaching:
			if not space.cancel_ground_move(world,staff_id):
				# A ride/support exit must finish safely. Keep this obligation even
				# if the unoccupied facility envelope is released meanwhile.
				release.cancel_floor = int(movement.target_floor)
				release.cancel_cell = movement.target_cell.duplicate()
		world.facts.staff[staff_id].clinical_release = release

func _gathering_move(movement: Dictionary, floor_id: int, cell: Array) -> bool:
	return not movement.is_empty() and not movement.has("convoy") and movement.get("members",[]).size()<=1 and int(movement.target_floor)==floor_id and movement.target_cell==cell

# Compatibility for completed historical outpatient seating. Reconcile only
# a proved clinical owner during normal dispatch, never a generic actor sweep.
func _release_completed_seated_support(world: WorldState, visit: Dictionary) -> void:
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	var support_id: String = str(actor.get("support_facility_id",""))
	if support_id.is_empty() or not world.facts.facilities.has(support_id): return
	if actor.get("posture","standing")!="standing" or actor.location.kind!="floor" or float(actor.location.get("height_m",0.0))!=0.0: return
	var receipt: Dictionary = visit.get("result_receipt",{})
	var attempt_id: String = str(receipt.get("attempt_id",""))
	var attempt: Dictionary = world.facts.attempts.get(attempt_id,{})
	if attempt.is_empty() or not attempt_id in visit.get("attempt_ids",[]) or attempt.get("visit_id","")!=visit.id or attempt.get("facility_id","")!=support_id: return
	if content.definition("treatment_protocols",str(attempt.get("protocol_id",""))).get("kind","")!="outpatient": return
	for session: Dictionary in world.facts.sessions.values():
		if session.get("visit_id","")==visit.id or actor.id in session.get("resources",[]): return
	for stay: Dictionary in world.facts.ward_stays.values():
		if stay.get("visit_id","")==visit.id: return
	if world.facts.preparations.has(visit.id) or world.facts.get("waiting_life",{}).get("needs",{}).has(visit.id) or world.facts.get("waiting_life",{}).get("seats",{}).has(visit.id): return
	var movement: Dictionary = world.facts.moves.get(actor.id,{})
	var cursor: int = int(movement.get("cursor",-1))
	var path: Array = movement.get("path",[])
	if cursor>=0 and cursor<path.size() and path[cursor].kind=="support_exit": return
	var reservation: Dictionary = world.facts.adaptations.get(support_id,{})
	if reservation.get("actor_id","")==actor.id or actor.id in reservation.get("staff_ids",[]): return
	var layout: Dictionary = space.facility_layout(world,support_id)
	if int(actor.location.floor_id)==int(layout.floor_id):
		var body: Rect2 = space.body_rectangle(actor)
		var regions: Array = reservation.get("regions",[]).duplicate()
		regions.append([layout.cell[0],layout.cell[1],layout.footprint[0],layout.footprint[1]])
		for cell: Array in [layout.patient_cell,layout.repair_cell]+layout.operator_cells: regions.append([cell[0],cell[1],1,1])
		for region: Array in regions:
			if body.intersects(Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3])),false): return
	actor.erase("support_facility_id")
	space.sync_actor(world,actor.id)

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
		_release_completed_seated_support(world,visit)
		if visit.phase in ["continuation_leaving","continuation_outside"]:
			Flow.dispatch_continuation(self,world,visit)
			continue
		if visit.phase in ["wait_consult","wait_plan"] and not Flow.resolve_doctor(self,world,visit): continue
		if visit.phase=="wait_plan" and visit.get("continuation",{}).get("stage","")!="guidance":
			if Flow.continuation_ready(self,world,visit): Flow.choose_plan(self,world,visit,str(Flow.diagnosis(visit).doctor_id))
		if visit.phase == "arrival":
			_queue(world,visit,"gp")
		elif visit.phase == "leaving":
			var exit_cell: Array = space.exit_cell(world,world.facts.actors[visit.actor_id])
			if space.at(world,visit.actor_id,1,exit_cell):
				# Reaching the exit can occur during a local return leg. End its
				# real ground journey before the actor leaves the floor.
				if not space.cancel_ground_move(world,visit.actor_id): continue
				world.facts.actors[visit.actor_id].location = {"kind":"outside"}
				space.sync_actor(world,visit.actor_id)
				visit.phase = "departed"
				visit.departed_tick = world.sim_tick
				_events.append(SimEvent.new(world.sim_tick,"patient_departed",[visit.id,visit.actor_id],{"result":visit.final_result}))
			else:
				visit.waiting_reason = space.request_move(world,visit.actor_id,1,exit_cell)
	var guidance_ready: Dictionary = {}
	if floor_guidance!=null:
		for id: String in world.ids("tickets"):
			var row: Dictionary = world.facts.tickets[id]
			if world.facts.visits[row.visit_id].phase in ["continuation_leaving","continuation_outside","leaving","departed"]: continue
			if Flow.ward_stay(world,str(row.visit_id)).get("phase","")=="return_preop": continue
			if world.facts.visits[row.visit_id].phase=="wait_plan" and world.facts.visits[row.visit_id].get("continuation",{}).get("stage","")!="guidance": continue
			guidance_ready[id] = floor_guidance.prepare(world,world.facts.visits[row.visit_id],row)
	var ordered_tickets: Array = world.ids("tickets") if floor_guidance==null else floor_guidance.ordered_tickets(world)
	for ticket_id: String in ordered_tickets:
		if not world.facts.tickets.has(ticket_id):
			continue
		var ticket: Dictionary = world.facts.tickets[ticket_id]
		var visit: Dictionary = world.facts.visits[ticket.visit_id]
		if visit.phase in ["continuation_leaving","continuation_outside","leaving","departed"]: continue
		if visit.phase=="wait_plan" and visit.get("continuation",{}).get("stage","")!="guidance": continue
		var current_stay: Dictionary=Flow.ward_stay(world,visit.id)
		if not current_stay.is_empty() and current_stay.phase=="return_preop": continue
		if floor_guidance!=null and not floor_guidance.can_call(world,visit,ticket): continue
		if floor_guidance!=null and not guidance_ready.get(ticket_id,false): continue
		if ticket.kind in ["consult","plan"] and not ticket.has("resume_session_id"):
			if not Flow.continuation_ready(self,world,visit): continue
			if ticket.kind=="plan":
				Flow.choose_plan(self,world,visit,str(Flow.diagnosis(visit).doctor_id))
				continue
		if ticket.kind=="examination":
			var modes: Array=[]
			for mode: String in ["spectrum","resonance"]:
				var selection: Dictionary={"first_only":true}
				if floor_guidance!=null: _destination_selection(world,selection,floor_guidance.target(world,visit.id))
				if not service_candidates(world,visit,mode,false,false,selection).is_empty(): modes.append(mode)
			if modes.is_empty(): continue
			var progress: Dictionary=Flow.diagnosis(visit)
			if str(progress.exam_kind).is_empty(): progress.exam_kind=modes[world.draw("treatment",modes.size())]
			ticket.kind=progress.exam_kind
			visit.phase="wait_"+str(ticket.kind)
		# The life service keeps its original ticket until the real return ends.
		# No clinical candidate can be called in that interval; preparation
		# expiry and other safety boundaries above still run normally.
		if world.facts.get("waiting_life",{}).get("needs",{}).has(visit.id) and not ticket.get("service_assigned",false) and not world.facts.preparations.has(visit.id) and not ticket.has("resume_session_id"): continue
		if ticket.kind == "surgery":
			_prepare_surgery(world,visit,ticket)
		else:
			_dispatch_service(world,visit,ticket)
	for stay_id: String in world.ids("ward_stays"):
		var stay: Dictionary = world.facts.ward_stays[stay_id]
		var visit: Dictionary = world.facts.visits[stay.visit_id]
		if stay.phase=="admitting": continue
		if stay.phase=="return_preop":
			Flow.return_preop(self,world,visit,stay)
			continue
		if stay.phase=="waiting_surgery":
			var waiting_bed: Dictionary=world.facts.facilities[stay.bed_id]
			if waiting_bed.failed and _transfer_stay(world,visit,stay).is_empty(): continue
			if waiting_bed.failed or not _ward_covering(world,stay):
				var limit: int=int(content.balance.clinical.equipment_no_progress_referral_seconds if waiting_bed.failed else content.balance.clinical.staff_no_progress_referral_seconds)*10
				if world.sim_tick-int(stay.last_progress_tick)>=limit: _begin_ward_referral(world,visit,stay)
			else: stay.last_progress_tick=world.sim_tick
		if not stay.has("last_progress_tick"):
			stay.last_progress_tick = world.sim_tick
		if stay.phase in ["recovery"]:
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
				var formation: Dictionary = _escort_formation(world,visit.actor_id,stay.escort_id,int(bed.floor_id),bed.patient_cell)
				if not formation.get("ok",false):
					visit.waiting_reason = formation.get("reason","队列成队空间不足")
					continue
				var alongside: Array = formation.targets[stay.escort_id]
				var source_floor: int = int(actor.location.floor_id)
				if not space.at(world,stay.escort_id,source_floor,alongside):
					visit.waiting_reason = space.request_move(world,stay.escort_id,source_floor,alongside)
					continue
				visit.waiting_reason = space.request_group_move(world,visit.actor_id,[visit.actor_id,stay.escort_id],{},int(bed.floor_id),bed.patient_cell)
			else:
				# Arrival of the head is not the clinical handoff. Finish the
				# convoy, then let its escort walk to the actual bedside position.
				if world.facts.moves.has(visit.actor_id): continue
				if bed.operator_cells.is_empty():
					visit.waiting_reason = "队列交接缺少真实床旁护理位置"
					continue
				space.grant_facility_access(world,stay.bed_id,stay.escort_id)
				if not space.at(world,stay.escort_id,int(bed.floor_id),bed.operator_cells[0]):
					visit.waiting_reason = space.request_move(world,stay.escort_id,int(bed.floor_id),bed.operator_cells[0])
					continue
				if world.facts.moves.has(stay.escort_id): continue
				visit.waiting_reason = ""
				var preoperative: bool=stay.get("transfer_resume_phase","")=="waiting_surgery"
				stay.phase = "waiting_surgery" if preoperative else "recovery"
				visit.phase = "wait_surgery" if preoperative else "recovery"
				stay.erase("transfer_resume_phase")
				stay.entered_tick = world.sim_tick
				_support(world,visit,bed,"lying")
				_use(world,bed,str(stay.id))
				_practice(world,stay.escort_id,"care",str(stay.id)+":escort:"+str(stay.attempt_id))
				_release_ward_operator(world,stay,stay.escort_id)
		elif stay.phase == "recovery" and not stay.care_completed and not _staff_busy(world,stay.nurse_id):
			_start_bed_service(world,visit,stay,"care",stay.nurse_id)

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
	# Sessions may complete above; only the following recovery loop is sealed.
	var nurse_coverage: Dictionary = {}
	for stay_id: String in world.ids("ward_stays"):
		if not world.facts.ward_stays.has(stay_id):
			continue
		var stay: Dictionary = world.facts.ward_stays[stay_id]
		if stay.phase != "recovery":
			continue
		var bed: Dictionary = world.facts.facilities[stay.bed_id]
		var nurse: Dictionary = world.facts.staff[stay.nurse_id]
		if not _ward_covering(world,stay,nurse_coverage):
			world.facts.visits[stay.visit_id].waiting_reason = _ward_staff_wait_reason(world,stay,"care")
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
			world.facts.visits[stay.visit_id].last_progress_tick = world.sim_tick
		if int(stay.remaining_ticks) == 0 and stay.care_completed:
			_complete_ward(world,world.facts.visits[stay.visit_id],stay)
	if int(world.facts.get("gameplay_version",0))>=1:
		visitors.call("advance",world)

func release_departed(world: WorldState) -> void:
	for stay_id: String in world.ids("ward_stays"):
		var stay: Dictionary = world.facts.ward_stays[stay_id]
		if stay.has("transfer_from_bed_id"):
			var actor_id: String = world.facts.visits[stay.visit_id].actor_id
			if not space.overlaps_facility(world,actor_id,stay.transfer_from_bed_id):
				stay.erase("transfer_from_bed_id")
		if stay.phase in ["release_wait","referral_release"]:
			var visit: Dictionary = world.facts.visits[stay.visit_id]
			var bed: Dictionary = world.facts.facilities[stay.bed_id]
			if not space.overlaps_facility(world,visit.actor_id,stay.bed_id):
				if stay.phase=="referral_release":
					visit.final_result = "referred"
					visit.phase = "leaving"
					visit.waiting_reason = "已安全转交院外照护，未完成住院项目不收费"
				# The bed body may already be clear while its patient/operator
				# envelope is still in use. Hand ownership to the real patient;
				# only release_adaptations may remove it after physical clearance.
				var held: Dictionary = world.facts.adaptations.get(str(stay.bed_id),{})
				if held.get("owner_id","")==stay_id: held.owner_id=visit.actor_id
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
	var assigned_pair: Dictionary = {}
	if _gather_assigned(world,visit,ticket,assigned_pair):
		return
	var kind: String = ticket.kind
	if kind=="outpatient" and not _decision_policy_valid(world,visit,ticket): return
	var consultation: Dictionary = {}
	var facility_id: String = LEGACY_SERVICE_FACILITIES.get(kind,"")
	var staff_id: String = LEGACY_SERVICE_STAFF.get(kind,"")
	if int(world.facts.get("gameplay_version",0)) >= 1:
		var selection: Dictionary = {"first_only":true}
		if floor_guidance!=null: _destination_selection(world,selection,floor_guidance.target(world,visit.id))
		if kind=="outpatient" and floor_guidance!=null and floor_guidance.state(world,visit.id).has("direct_doctor_id"):
			selection.staff_id=str(floor_guidance.state(world,visit.id).direct_doctor_id)
		if kind=="consult":
			selection.staff_id=str(Flow.diagnosis(visit).doctor_id)
			selection.facility_id=str(Flow.diagnosis(visit).facility_id)
		selection.merge(assigned_pair)
		var treatment_selection: Dictionary = {"reason":"","policy_ok":false,"review_quote":{}}
		if kind=="outpatient":
			var plan_id: String = str(visit.plan_decision.get("plan_id",visit.requested_plan_id))
			selection.eligible = _plan_candidate_eligible.bind(world,visit,plan_id,treatment_selection)
			selection.accept = _accept_outpatient_dispatch.bind(world,visit,treatment_selection)
		var candidates: Array = [consultation.pair] if kind=="consult" and consultation.has("pair") else service_candidates(world,visit,kind,false,false,selection)
		if candidates.is_empty():
			if not assigned_pair.is_empty():
				_release_preparation(world,visit.id)
				ticket.service_assigned = false
				ticket.called_tick = -1
			if kind=="outpatient":
				_release_preparation(world,visit.id)
				ticket.service_assigned = false
				ticket.called_tick = -1
				if not treatment_selection.policy_ok and not treatment_selection.review_quote.is_empty(): _decision_valid(world,visit,treatment_selection.review_quote)
			visit.waiting_reason = str(treatment_selection.reason) if not str(treatment_selection.reason).is_empty() else "等待实际可用设备、合格人员及合法路线"
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
	var track: String = "treatment" if kind=="outpatient" else "diagnosis"
	if int(staff.abilities[track]) < 1:
		visit.waiting_reason = "职员缺少对应能力资格"
		return
	if HospitalStaffWellbeing.yield_for_work(world,content,space,[staff_id]):
		visit.waiting_reason = "公共娱乐尚未开始，等待整组安全离位后接单"
		return
	if waiting_life != null and not waiting_life.call("call_patient",world,visit.id):
		return
	if kind == "outpatient":
		var ready_quote: Dictionary = _outpatient_quote(world,visit,staff,facility)
		if not ready_quote.ok:
			if ready_quote.get("requires_review",false):
				_decision_valid(world,visit,ready_quote)
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
			for field: String in ["nurse_id","ward_id"]:
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
	var effective: float = float(facility.grade) * float(content.balance.medical_equipment_effects.utilization_by_level[int(staff.abilities[track])])
	var session_data: Dictionary = {"doctor_fee":0,"facility_fee":content.facility_fee(facility.definition_id,kind)}
	match kind:
		"gp":
			ticks = ceili(float(_gp_work_ticks(visit,staff,effective))/_talent_rate(world,staff.id,"gp",visit))
			Flow.freeze_gp(self,world,visit,staff,facility,session_data)
			if int(visit.doctor_fee_quote) < 0:
				visit.doctor_fee_quote = content.doctor_fee(staff.title_id)
			session_data.doctor_fee = visit.doctor_fee_quote
		"spectrum", "resonance":
			var test: Dictionary = content.balance.tests[kind]
			var seconds: float = float(test.seconds)
			if staff.role=="doctor":
				seconds *= 1.0+float(content.balance.wellbeing.fatigue_work_multiplier_per_point)*float(staff.fatigue)
			ticks = ceili(seconds/(1.0+0.05*(int(staff.abilities.diagnosis)-1)+0.15*effective)*10/_talent_rate(world,staff.id,"test",visit))
		"consult":
			ticks = Flow.review_ticks(self,world,visit,staff,effective)
			session_data.facility_fee=0
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

func _gather_assigned(world: WorldState, visit: Dictionary, ticket: Dictionary, assigned_pair: Dictionary = {}) -> bool:
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
			break
		if not staff.on_shift or not _can_start(world,staff) or not _service_qualified(world,staff,ticket.kind) or not _schedule_allows(world,staff_id,ticket.kind,visit,facility_id):
			break
		# Diagnosis retain the real pair they called. Arrival is
		# not permission to choose a newly earlier desk and strand the old hold.
		if ticket.kind=="gp":
			assigned_pair.facility_id = facility_id
			assigned_pair.staff_id = staff_id
		# The ticket already owns this real reservation. Movement checks its live
		# route and sweeps; the complete quote is checked again before work starts.
		return not _gather(world,visit,space.facility_layout(world,facility_id),[staff_id])
	if ticket.kind=="gp":
		_release_preparation(world,visit.id)
		ticket.service_assigned = false
		ticket.called_tick = -1
	return false

func service_candidates(world: WorldState, visit: Dictionary, kind: String, structural_only: bool = false, reference_schedule: bool = false, selection: Dictionary = {}) -> Array:
	if not kind in ["gp","spectrum","resonance","consult","outpatient"]: return []
	var equipment_id: String = "FUR02"
	if kind == "outpatient":
		var binding: Dictionary = content.definition("treatment_bindings",visit.binding_id)
		equipment_id = str(content.definition("treatment_routines",binding.routine_id).equipment_id)
	var candidates: Array = []
	# This enumeration is synchronous and read-only. Rebuild from the owners
	# after every dispatch, so an earlier ticket's new reservation is visible.
	var preparation: Dictionary = world.facts.preparations.get(visit.id,{})
	var staff_ids: Array = []
	var staff_ids_ready: bool = false
	# Lazy, invocation-local facts only: keep first_only early exits and never
	# carry eligibility past the next actual dispatch or reservation.
	var staff_ready: Dictionary = {}
	var facility_ids: Array = space.room_use.facilities(world,str(selection.room_id),[equipment_id]) if selection.has("room_id") else world.facility_ids(equipment_id)
	var query_ready: bool = false
	var physical: Dictionary = {}
	var availability: Dictionary = {}
	for facility_id: String in facility_ids:
		if selection.has("facility_id") and selection.facility_id!=facility_id: continue
		var facility: Dictionary = world.facts.facilities[facility_id]
		if selection.has("floor_id") and int(facility.floor_id)!=int(selection.floor_id): continue
		if facility.definition_id!=equipment_id:
			continue
		# A failed outpatient machine remains a structural treatment option;
		# actual starts and other service kinds still require working equipment.
		if HospitalRemodel.blocked(world,facility_id) or (facility.failed and (not structural_only or kind!="outpatient")) or not bool(facility.get("open",true)) or not bool(facility.get("intake_open",true)):
			continue
		# Closed rooms block new service, not structural recommendations or active work.
		if not structural_only and not service_room_reason(world,facility).is_empty():
			continue
		if not preparation.is_empty() and preparation.facility_id!=facility_id:
			continue
		if not structural_only and not space.facility_reservation_reason(world,facility_id,visit.actor_id).is_empty():
			continue
		if not structural_only and _facility_unavailable(facility):
			continue
		var base_layout: Dictionary = space.facility_layout(world,facility_id)
		if base_layout.operator_cells.is_empty():
			continue
		if not structural_only:
			if availability.is_empty(): availability = _availability(world)
			if _facility_busy(world,facility_id,visit.id,availability): continue
		if not query_ready:
			space.begin_route_query(world)
			query_ready = true
			# Physical views are needed only after cheap facility exclusions.
			if kind=="outpatient":
				var physical_visit: Dictionary = visit.duplicate()
				physical_visit.erase("plan_decision")
				physical = space.read_view(world,"clinical_pairs:"+JSON.stringify([kind,structural_only,reference_schedule,space.nominal_query(world),physical_visit]),func()->Dictionary: return {"pairs":{},"patient_rejections":{},"transport_actors":HospitalTransit.route_participants(world)})
		if not staff_ids_ready:
			staff_ids = [str(selection.staff_id)] if selection.has("staff_id") else world.ids("staff")
			staff_ids_ready = true
		for staff_id: String in staff_ids:
			if selection.get("considered",{}).has(staff_id): continue
			if not staff_ready.has(staff_id):
				staff_ready[staff_id] = false
				if not world.facts.staff.has(staff_id): continue
				var staff: Dictionary = world.facts.staff[staff_id]
				if not preparation.is_empty() and not staff_id in preparation.staff_ids: continue
				if not structural_only and (_staff_busy(world,staff_id,visit.id,availability) or not staff.on_shift or not _can_start(world,staff)): continue
				if not _service_qualified(world,staff,kind): continue
				staff_ready[staff_id] = true
			if not staff_ready[staff_id]: continue
			if not structural_only and not _schedule_allows(world,staff_id,kind,visit,facility_id):
				continue
			if reference_schedule and not _reference_assignment_allows(world,staff_id,kind,visit,facility_id):
				continue
			var eligible: Callable = selection.get("eligible",Callable())
			if eligible.is_valid() and not eligible.call({"facility_id":facility_id,"staff_id":staff_id}): continue
			if kind=="outpatient":
				var pair_key: String = JSON.stringify([facility_id,staff_id])
				if not physical.pairs.has(pair_key): physical.pairs[pair_key] = _service_pair_reachable(world,visit,facility_id,staff_id,base_layout,physical)
				if not physical.pairs[pair_key]: continue
			elif not _service_pair_reachable(world,visit,facility_id,staff_id,base_layout): continue
			var pair: Dictionary = {"facility_id":facility_id,"staff_id":staff_id}
			var accept: Callable = selection.get("accept",Callable())
			if accept.is_valid() and not accept.call(pair):
				continue
			candidates.append(pair)
			if selection.get("first_only",false):
				space.end_route_query()
				return candidates
	if query_ready: space.end_route_query()
	return candidates

func _service_pair_reachable(world: WorldState, visit: Dictionary, facility_id: String, staff_id: String, base_layout: Dictionary, physical: Dictionary = {}) -> bool:
	var layout: Dictionary = base_layout
	# A complete arrival route is required even when the facility fits.
	# Reject unreachable pairs before proving every other actor's exit;
	# Layout and current occupancy alone never authorize a reservation.
	var fit: Dictionary = space.facility_preflight_quote(world,facility_id,visit.actor_id,[staff_id])
	if not fit.ok:
		return false
	var patient_key: String = ""
	if not physical.is_empty() and not physical.transport_actors.has(staff_id):
		# Within this sealed physical view, changing only a non-travelling
		# operator's permission cannot alter the patient's route. Transit owns
		# the full set of other groups whose exits may be queried by a prefix.
		var patient_fit: Dictionary = fit.duplicate()
		patient_fit.erase("staff_ids")
		patient_key = JSON.stringify([facility_id,base_layout,patient_fit],"",true,true)
		if physical.patient_rejections.has(patient_key): return false
	var routing_world: WorldState = world
	if not fit.get("unchanged",false):
		# This record is replaced below, so only the adaptations container needs
		# ownership. The verified fit's nested geometry remains read-only.
		routing_world = _reservation_candidate(world,[])
		var handoff: Dictionary = fit.duplicate()
		handoff.erase("ok")
		handoff.owner_id = visit.id
		routing_world.facts.adaptations[facility_id] = handoff
		layout = handoff
		var route_floors: Array = [int(layout.floor_id)]
		for actor_id: String in [visit.actor_id,staff_id]:
			var location: Dictionary = world.facts.actors[actor_id].location
			if location.kind=="floor" and not int(location.floor_id) in route_floors: route_floors.append(int(location.floor_id))
		space.prepare_projection(world,routing_world,[facility_id],route_floors)
		space.begin_route_query(routing_world,{"nominal":true} if space.nominal_query(world) else {})
	var patient_reachable: bool = space.can_reach(routing_world,visit.actor_id,int(layout.floor_id),layout.patient_cell,[],{},true)
	# Never cache an operator or exit failure as a failed patient journey.
	if not patient_key.is_empty() and not patient_reachable: physical.patient_rejections[patient_key] = true
	var reachable: bool = patient_reachable and space.can_reach(routing_world,staff_id,int(layout.floor_id),layout.operator_cells[0],[],{},true)
	if routing_world!=world: space.end_route_query()
	if not reachable:
		return false
	if not space._facility_exit_quote(world,facility_id,visit.actor_id,[staff_id],fit).ok:
		return false
	return true

func _service_qualified(world: WorldState, staff: Dictionary, kind: String) -> bool:
	if staff.get("departed",false):
		return false
	if kind in ["spectrum","resonance"]:
		for mode: Dictionary in content.catalog.diagnostic_modes:
			if mode.service!=kind:
				continue
			var unlock: String=str(mode.get("unlock","initial"))
			if unlock=="first_profile_B" and int(world.facts.get("research_progress",{}).get("first_profile_b_tick",-1))<0: return false
			if unlock.begins_with("R") and not unlock in world.facts.research: return false
			for requirement: Dictionary in mode.operators:
				var allowed: bool = staff.role==requirement.role and int(staff.abilities.get(requirement.ability,0))>=int(requirement.min_level)
				for research_id: String in requirement.requires_research:
					allowed = allowed and research_id in world.facts.research
				if allowed:
					return true
		return false
	return staff.role=="doctor" and int(staff.abilities.get("treatment" if kind=="outpatient" else "diagnosis",0))>=1

func service_room_reason(world: WorldState, facility: Dictionary) -> String:
	return space.room_use.facility_reason(world,facility)

func _missing_service_reason(world: WorldState, visit: Dictionary, kind: String) -> String:
	var equipment_id: String = "FUR02"
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
		return "缺少"+("或".join(qualifications) if not qualifications.is_empty() else ("具有诊断1级的医生" if kind=="gp" else "具有治疗1级的医生"))
	var reason: String = "设施未开放或缺少合法房间、门与路线"
	for facility_id: String in facilities:
		var facility: Dictionary = world.facts.facilities[facility_id]
		if facility.failed or not facility.get("open",true) or not facility.get("intake_open",true):
			reason = "设施故障或尚未开放："+str(content.facility_definition(equipment_id).get("name",equipment_id))
			continue
		var room_reason: String = service_room_reason(world,facility)
		if not room_reason.is_empty():
			reason = room_reason
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
			var patient_route: Dictionary = space.route_cost(world,visit.actor_id,int(layout.floor_id),layout.patient_cell,[],{},true)
			if not patient_route.ok:
				reason = "患者路线："+str(patient_route.reason)
				continue
			var worker_route: Dictionary = space.route_cost(world,staff_id,int(layout.floor_id),layout.operator_cells[0],[],{},true)
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
			results.append(selection_quote(world,visit_id,plan.id))
	space.end_route_query()
	return results

func selection_quote(world: WorldState, visit_id: String, plan_id: String) -> Dictionary:
	var actual: Dictionary=plan_quote(world,visit_id,plan_id)
	if actual.get("ok",false): return actual
	var plan: Dictionary=content.definition("treatment_plans",plan_id)
	var protocol: Dictionary=content.definition("treatment_protocols",str(plan.get("protocol_id","")))
	if protocol.get("kind","")!="surgery": return actual
	var visit: Dictionary=world.facts.visits.get(visit_id,{})
	if visit.is_empty() or not _plan_policy_reason(world,visit,plan_id).is_empty() or visit.attempt_ids.size()>=int(content.balance.max_treatment_attempts): return actual
	var adapted: bool=false
	for adapter: Dictionary in content.catalog.surgical_adapters:
		if adapter.binding_id==visit.binding_id and adapter.plan_id==plan_id:
			adapted=true
			break
	if not adapted: return actual
	# The catalog's standard qualified team/equipment is a plan estimate,
	# not an installed OR, reserved bed or promise about future performers.
	# Actual start always obtains the complete current bundle again.
	var probability: int=floori(clampf(float(protocol.base_success),0.70,0.98)*10000)
	if probability<roundi(float(content.balance.clinical.minimum_predicted_success)*10000): return actual
	var work: int=ceili(float(protocol.work_seconds)*10)
	var recovery: int=ceili(float(protocol.recovery_seconds)*10)
	return {"ok":true,"ready":false,"structural_ok":true,"plan_id":plan_id,"quote_basis":"standard_protocol",
		"probability_bp":probability,"work_ticks":work,"recovery_ticks":recovery,"supply_units":int(protocol.supply_units),
		"facility_fee":content.facility_fee("EQ01","surgery"),"cure_fee":_quoted_fee(int(content.definition("diseases",visit.disease_id).cure_fee),protocol.cure_fee_multiplier),
		"staff_ids":[],"effective_level":0.0,"estimated_total_ticks":work+recovery+int(content.balance.clinical.wake_seconds)*10,
		"reason":str(actual.get("reason","等待手术团队和设备"))}

func plan_quote(world: WorldState, visit_id: String, plan_id: String, options: Dictionary = {}) -> Dictionary:
	space.begin_route_query(world)
	var result: Dictionary = _plan_quote_in_query(world,visit_id,plan_id,options)
	space.end_route_query()
	return result

func _plan_quote_in_query(world: WorldState, visit_id: String, plan_id: String, options: Dictionary) -> Dictionary:
	var visit: Dictionary = world.facts.visits.get(visit_id,{})
	var plan: Dictionary = content.definition("treatment_plans",plan_id)
	if visit.is_empty() or plan.is_empty() or plan.disease_id!=visit.disease_id:
		return {"ok":false,"structural_ok":false,"plan_id":plan_id,"reason":"方案不属于当前病例"}
	for research_id: String in plan.requires_research:
		if not research_id in world.facts.research:
			return {"ok":false,"structural_ok":false,"plan_id":plan_id,"reason":"方案研究尚未完成"}
	var protocol: Dictionary = content.definition("treatment_protocols",plan.protocol_id)
	# This quote replaces only the top-level decision and reads nested facts.
	var candidate: Dictionary = visit.duplicate()
	candidate.plan_decision = {"plan_id":plan_id}
	var structural: bool = bool(options.get("structural_only",false))
	if protocol.kind=="surgery":
		if not structural and not options.has("alternatives") and not options.has("bed_quotes"):
			var actual: Dictionary = _surgery_quote(world,candidate,[],options)
			if actual.ok:
				actual.plan_id = plan_id
				actual.structural_ok = true
				return actual
			var fallback: Dictionary = options.duplicate()
			fallback.structural_only = true
			fallback.ignore_supplies = true
			actual.plan_id = plan_id
			actual.structural_ok = bool(_surgery_quote(world,candidate,[],fallback).ok)
			return actual
		var structural_options: Dictionary = options.duplicate()
		structural_options.structural_only = true
		structural_options.ignore_supplies = true
		var structural_quote: Dictionary = _surgery_quote(world,candidate,[],structural_options)
		var surgery: Dictionary = structural_quote if structural else _surgery_quote(world,candidate,[],options)
		surgery.plan_id = plan_id
		surgery.structural_ok = bool(structural_quote.ok)
		return surgery
	# Quote in the same candidate order, stopping only after a complete usable
	# quote. Rejected candidates still allow later facilities and doctors.
	var state: Dictionary = {"reason":"缺少合法门诊设备、医生能力或完整路线","structural_ok":false,"quote":{}}
	var equipment_id: String = str(content.definition("treatment_routines",content.definition("treatment_bindings",visit.binding_id).routine_id).equipment_id)
	if world.facility_ids(equipment_id).is_empty():
		state.reason = "缺少实际设施："+str(content.facility_definition(equipment_id).get("name",equipment_id))
	var selection: Dictionary = {"staff_id":options.doctor_id} if options.has("doctor_id") else {}
	selection.first_only = true
	selection.accept = _accept_plan_candidate.bind(world,candidate,plan_id,options,state)
	selection.eligible = _plan_candidate_eligible.bind(world,candidate,plan_id,state)
	service_candidates(world,candidate,"outpatient",true,false,selection)
	if not state.quote.is_empty():
		return state.quote
	return {"ok":false,"structural_ok":state.structural_ok,"plan_id":plan_id,"reason":state.reason,"availability_reason":state.reason if state.structural_ok else ""}

func _accept_outpatient_dispatch(pair: Dictionary, world: WorldState, visit: Dictionary, state: Dictionary) -> bool:
	var quote: Dictionary = _outpatient_quote(world,visit,world.facts.staff[pair.staff_id],world.facts.facilities[pair.facility_id])
	if quote.ok: return true
	state.reason = str(quote.reason)
	return false

func _plan_candidate_eligible(pair: Dictionary, world: WorldState, visit: Dictionary, plan_id: String, state: Dictionary) -> bool:
	var staff: Dictionary = world.facts.staff[pair.staff_id]
	if int(staff.abilities.treatment)<_outpatient_minimum(visit,plan_id):
		state.reason = "医生治疗等级不足"
		return false
	var protocol: Dictionary = content.definition("treatment_protocols",content.definition("treatment_plans",plan_id).protocol_id)
	var probability: float = _outpatient_probability(world,visit,staff,world.facts.facilities[pair.facility_id],protocol)
	if probability<float(content.balance.clinical.minimum_predicted_success):
		state.reason = "预计效果低于原玩法门槛"
		state.review_quote = {"probability_bp":floori(probability*10000)}
		return false
	state.policy_ok = true
	return true

func _accept_plan_candidate(pair: Dictionary, world: WorldState, visit: Dictionary, plan_id: String, options: Dictionary, state: Dictionary) -> bool:
	if options.has("doctor_id") and pair.staff_id!=options.doctor_id:
		return false
	var structural: bool = bool(options.get("structural_only",false))
	var staff: Dictionary = world.facts.staff[pair.staff_id]
	var facility: Dictionary = world.facts.facilities[pair.facility_id]
	var quote: Dictionary = _outpatient_quote(world,visit,staff,facility,plan_id,true,true)
	if not quote.ok:
		state.reason = quote.reason
		return false
	state.structural_ok = true
	var availability: String = ""
	if not structural and int(quote.recovery_ticks)>0:
		var actual_bed: Dictionary = _outpatient_quote(world,visit,staff,facility,plan_id,true,false)
		if not actual_bed.ok:
			availability = actual_bed.reason
		else:
			quote = actual_bed
	var availability_view: Dictionary = _availability(world) if not structural else {}
	if not structural and (_facility_unavailable(facility) or _facility_busy(world,pair.facility_id,visit.id,availability_view) or _staff_busy(world,pair.staff_id,visit.id,availability_view) or not staff.on_shift or not _can_start(world,staff)):
		availability = "等待原方案的当班医护与设备"
	if not structural and not _schedule_allows(world,pair.staff_id,"outpatient",visit,pair.facility_id):
		availability = "等待当前排班服务池内的治疗医生"
	if not bool(options.get("ignore_supplies",false)) and _available_supplies(world,visit.id)<int(quote.supply_units):
		availability = "治疗包不足，保留原票号"
	if not structural and facility.failed:
		availability = "治疗设备故障，等待修复："+str(content.facility_definition(facility.definition_id).get("name",facility.definition_id))
	# Report the actual closed destination even if staff are also unavailable.
	if not structural and not service_room_reason(world,facility).is_empty():
		availability = service_room_reason(world,facility)
	quote.ok = availability.is_empty()
	quote.structural_ok = true
	quote.reason = availability
	quote.availability_reason = availability
	quote.facility_id = pair.facility_id
	quote.estimated_total_ticks = int(quote.work_ticks)+int(quote.recovery_ticks)
	if quote.ok:
		state.quote = quote
		return true
	state.reason = availability
	return false

func _destination_selection(world: WorldState, selection: Dictionary, destination_id: String) -> Dictionary:
	if not destination_id.is_empty():
		var destination: Dictionary=world.facts.facilities.get(destination_id,{})
		# Guidance commits to a room. A later actual gathering/preparation owns
		# its specific equipment and still narrows this selection to that device.
		selection.room_id=str(destination.get("room_id",""))
	return selection

func _consult_missing_equipment_reason(world: WorldState, visit: Dictionary) -> String:
	# Absence only: installed but unavailable equipment must reach normal selection.
	var binding: Dictionary = content.definition("treatment_bindings",visit.binding_id)
	if binding.is_empty() or binding.disease_id!=visit.disease_id: return ""
	var routine: Dictionary = content.definition("treatment_routines",binding.routine_id)
	if routine.is_empty(): return ""
	var missing: Array[String] = []
	for plan: Dictionary in content.catalog.treatment_plans:
		if not _plan_policy_reason(world,visit,plan.id).is_empty(): continue
		var protocol: Dictionary = content.definition("treatment_protocols",plan.protocol_id)
		var required: Array = []
		if protocol.kind=="outpatient":
			required = [routine.equipment_id]
		elif protocol.kind=="surgery":
			var compatible: bool = false
			for adapter: Dictionary in content.catalog.surgical_adapters:
				if adapter.binding_id==visit.binding_id and adapter.plan_id==plan.id:
					compatible = true
					break
			if not compatible: continue
			required = protocol.required_equipment_ids
		else:
			continue
		var absent: Array[String] = []
		for equipment_id: String in required:
			if world.facility_ids(equipment_id).is_empty():
				absent.append(str(content.facility_definition(equipment_id).get("name",equipment_id)))
		if absent.is_empty(): return ""
		for name: String in absent:
			if not name in missing: missing.append(name)
	return "缺少实际设施："+"、".join(missing) if not missing.is_empty() else ""

func _select_plan(world: WorldState, visit: Dictionary, doctor_id: String = "", consultation: Dictionary = {}, destination_id: String = "") -> Dictionary:
	space.begin_route_query(world)
	var result: Dictionary = _select_plan_in_query(world,visit,doctor_id,consultation,destination_id)
	space.end_route_query()
	return result

func _select_plan_in_query(world: WorldState, visit: Dictionary, doctor_id: String, consultation: Dictionary, destination_id: String = "") -> Dictionary:
	var quotes: Array = []
	if scheduler!=null and doctor_id.is_empty():
		var state: Dictionary = {"considered":{},"quote":{},"consultation":consultation}
		service_candidates(world,visit,"consult",false,false,_destination_selection(world,{"first_only":true,"considered":state.considered,"accept":_accept_consultation.bind(world,visit,state)},destination_id))
		return state.quote
	var selected_doctor: String = doctor_id
	if selected_doctor.is_empty():
		for pair: Dictionary in service_candidates(world,visit,"consult",false,false,_destination_selection(world,{"first_only":true},destination_id)):
			selected_doctor = pair.staff_id
			consultation.pair = pair
			break
	if selected_doctor.is_empty():
		return {}
	var staff: Dictionary = world.facts.staff[selected_doctor]
	var personality: Dictionary = content.definition("doctor_personalities",str(staff.get("personality_id","DP01")))
	var weights: Dictionary = personality.weights
	for plan: Dictionary in content.catalog.treatment_plans:
		if plan.disease_id!=visit.disease_id:
			continue
		var protocol: Dictionary = content.definition("treatment_protocols",plan.protocol_id)
		if protocol.kind=="surgery" and int(staff.abilities.treatment)<2:
			continue
		# The consulting doctor recommends a plan; a different qualified doctor
		# may perform it later. This quote is not a future reservation.
		var quote: Dictionary = selection_quote(world,visit.id,plan.id) if protocol.kind=="surgery" else plan_quote(world,visit.id,plan.id,{"structural_only":true,"ignore_supplies":true})
		if not quote.ok:
			continue
		var completed: int = int(staff.get("plan_experience",{}).get(plan.id,0))
		quote.score = float(weights.success)*float(quote.probability_bp)/100.0-float(weights.time)*float(quote.get("estimated_total_ticks",quote.work_ticks))/100.0-float(weights.burden)*float(protocol.burden)
		quote.score += float(weights.familiarity)*mini(int(content.balance.clinical.score_familiarity_cap),completed/int(content.balance.clinical.score_familiarity_cases_per_band))+float(weights.novelty)*(1 if completed==0 else 0)+float(weights.team)
		quote.consulting_doctor_id = selected_doctor
		quotes.append(quote)
	return _choose_plan(quotes,str(world.facts.get("plan_strategy","doctor")))

func _accept_consultation(pair: Dictionary, world: WorldState, visit: Dictionary, state: Dictionary) -> bool:
	if state.considered.has(pair.staff_id): return false
	state.considered[pair.staff_id] = true
	var quote: Dictionary = _select_plan(world,visit,pair.staff_id)
	if quote.is_empty(): return false
	state.quote = quote
	state.consultation.pair = pair
	return true

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

func _decision_policy_valid(world: WorldState, visit: Dictionary, ticket: Dictionary) -> bool:
	if int(world.facts.get("gameplay_version",0))<1 or visit.plan_decision.is_empty(): return true
	var reason: String = _plan_policy_reason(world,visit,str(visit.plan_decision.plan_id))
	if reason.is_empty(): return true
	_release_preparation(world,visit.id)
	ticket.service_assigned = false
	ticket.called_tick = -1
	if visit.plan_decision.get("source","")=="doctor":
		Flow.reconsider(self,world,visit)
	else:
		visit.plan_decision.pending_reason = "方案条件变化："+reason
	visit.waiting_reason = reason
	return false

func _plan_policy_reason(world: WorldState, visit: Dictionary, plan_id: String) -> String:
	var plan: Dictionary = content.definition("treatment_plans",plan_id)
	if plan.is_empty() or plan.disease_id!=visit.disease_id: return "方案不属于当前病例"
	for research_id: String in plan.requires_research:
		if not research_id in world.facts.research: return "方案研究尚未完成"
	return ""

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
		Flow.reconsider(self,world,visit)
	return false

func _gather(world: WorldState, visit: Dictionary, facility: Dictionary, staff_ids: Array) -> bool:
	var all_present: bool = space.at(world,visit.actor_id,int(facility.floor_id),facility.patient_cell) and not world.facts.moves.has(visit.actor_id)
	if not all_present:
		visit.waiting_reason = space.request_move(world,visit.actor_id,int(facility.floor_id),facility.patient_cell)
	for index: int in staff_ids.size():
		var staff_id: String = staff_ids[index]
		var position: Array = facility.operator_cells[index]
		if not space.at(world,staff_id,int(facility.floor_id),position) or world.facts.moves.has(staff_id):
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

func _outpatient_quote(world: WorldState, visit: Dictionary, staff: Dictionary, facility: Dictionary, plan_id: String = "", ignore_supplies: bool = false, _structural_only: bool = false, _reference_schedule: bool = false, _bed_quotes: Variant = null) -> Dictionary:
	if plan_id.is_empty():
		plan_id = str(visit.plan_decision.get("plan_id",visit.requested_plan_id))
	var plan: Dictionary = content.definition("treatment_plans",plan_id)
	var protocol: Dictionary = content.definition("treatment_protocols",plan.protocol_id)
	var disease: Dictionary = content.definition("diseases",visit.disease_id)
	var minimum: int = _outpatient_minimum(visit,plan_id)
	var supply_units: int = _required_supplies(visit,protocol)
	if not ignore_supplies and _available_supplies(world,visit.id)<supply_units:
		return {"ok":false,"reason":"治疗包不足，保留原票号"}
	if visit.attempt_ids.size()>=int(content.balance.max_treatment_attempts):
		return {"ok":false,"reason":"已达到实际治疗次数上限"}
	if staff.role!="doctor" or int(staff.abilities.treatment) < minimum:
		return {"ok":false,"reason":"医生治疗等级不足"}
	var effective: float = float(facility.grade)*float(content.balance.medical_equipment_effects.utilization_by_level[int(staff.abilities.treatment)])
	var probability: float = _outpatient_probability(world,visit,staff,facility,protocol)
	if probability < float(content.balance.clinical.minimum_predicted_success):
		return {"ok":false,"reason":"预计效果低于原玩法门槛","requires_review":true,"probability_bp":floori(probability*10000)}
	var binding: Dictionary = content.definition("treatment_bindings",visit.binding_id)
	var routine: Dictionary = content.definition("treatment_routines",binding.routine_id)
	if routine.equipment_id != facility.definition_id:
		return {"ok":false,"reason":"病例与医疗主体不适配"}
	var quote: Dictionary = {"ok":true,"plan_id":plan_id,"probability_bp":floori(probability*10000),
		"work_ticks":_outpatient_work_ticks(world,visit,staff,facility,protocol),"recovery_ticks":0,"supply_units":supply_units,
		"cure_fee":_quoted_fee(int(disease.cure_fee),protocol.cure_fee_multiplier),"facility_fee":content.facility_fee(facility.definition_id,"outpatient"),
		"staff_ids":[staff.id],"effective_level":effective,"facility_id":facility.id}
	return quote

func _outpatient_probability(world: WorldState, visit: Dictionary, staff: Dictionary, facility: Dictionary, protocol: Dictionary) -> float:
	var disease: Dictionary = content.definition("diseases",visit.disease_id)
	var base_success: float = float(_profile(visit).base_success) if bool(protocol.uses_disease_profile) else float(protocol.clinical_profiles[disease.profile].base_success)
	var effective: float = float(facility.grade)*float(content.balance.medical_equipment_effects.utilization_by_level[int(staff.abilities.treatment)])
	var probability: float = clampf(base_success+0.02*(int(staff.abilities.treatment)-1)+0.025*effective
		- (0.03 if float(staff.energy)<35.0 else 0.0) - (0.04 if float(facility.condition)<40.0 else 0.0)
		+ (float(content.balance.second_attempt_bonus) if not visit.attempt_ids.is_empty() else 0.0) - (float(protocol.complex_penalty) if visit.complex else 0.0),0.70,0.98)
	if recruitment!=null:
		var talent: Dictionary = recruitment.call("talent_effect",world,staff.id,"outpatient",visit.actor_id,content.definition("treatment_routines",content.definition("treatment_bindings",visit.binding_id).routine_id).specialty_id)
		if talent.get("handler_id","")=="treatment_success":
			probability = clampf(probability+float(talent.value),0.70,0.98)
	return probability

func _outpatient_work_ticks(world: WorldState, visit: Dictionary, staff: Dictionary, facility: Dictionary, protocol: Dictionary) -> int:
	var routine: Dictionary = content.definition("treatment_routines",content.definition("treatment_bindings",visit.binding_id).routine_id)
	var effective: float = float(facility.grade)*float(content.balance.medical_equipment_effects.utilization_by_level[int(staff.abilities.treatment)])
	var seconds: float = float(routine.service_seconds)*float(protocol.work_multiplier)/(1.0+0.05*(int(staff.abilities.treatment)-1)+0.2*effective)*(1.0+0.003*float(staff.fatigue))
	return ceili(seconds*10)

func _compatible_bed(world: WorldState, visit: Dictionary, floor_id: int, excluded: Array, structural_only: bool = false, preferred_bed: String = "", reference_schedule: bool = false, alternatives: Variant = null, continuing_stay: Dictionary = {}) -> Dictionary:
	var own_stay: Dictionary=Flow.ward_stay(world,visit.id)
	if not own_stay.is_empty() and not preferred_bed.is_empty() and preferred_bed==own_stay.bed_id:
		var owned_bed: Dictionary=world.facts.facilities.get(own_stay.bed_id,{})
		if owned_bed.is_empty() or owned_bed.failed or own_stay.nurse_id in excluded or not structural_only and not _ward_covering(world,own_stay): return {"ok":false,"reason":"原住院床位或独立护理覆盖暂不可用"}
		return {"ok":true,"bed_id":own_stay.bed_id,"nurse_id":own_stay.nurse_id,"ward_id":owned_bed.room_id}
	var nurses: Dictionary = {}
	var loads: Dictionary = {}
	var availability: Dictionary = {} if structural_only else _availability(world)
	for id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[id]
		if staff.role=="nurse" and "q_ward" in staff.certificates and not id in excluded:
			var ward_id: String = str(staff.get("ward_id",""))
			if scheduler!=null:
				var entry: Dictionary = scheduler.call("assignment",world,id,int(scheduler.call("shift_index",world)))
				ward_id = str(entry.get("pools",[""])[0]) if not entry.get("pools",[]).is_empty() else ""
			if not nurses.has(ward_id): nurses[ward_id] = []
			nurses[ward_id].append(id)
	for stay: Dictionary in world.facts.ward_stays.values(): loads[stay.nurse_id] = int(loads.get(stay.nurse_id,0))+1
	for preparation: Dictionary in world.facts.preparations.values():
		if preparation.visit_id!=visit.id:
			var id: String = str(preparation.get("nurse_id",""))
			loads[id] = int(loads.get(id,0))+1
	var workbenches: Array = world.facility_ids("SE06").filter(func(id: String)->bool:
		return int(world.facts.facilities[id].floor_id)==floor_id and not world.facts.facilities[id].failed)
	var workbench_reachable: Dictionary = {}
	for bed_id: String in world.facility_ids("EQ05"):
		if not preferred_bed.is_empty() and bed_id!=preferred_bed:
			continue
		var bed: Dictionary = world.facts.facilities[bed_id]
		if HospitalRemodel.blocked(world,bed_id) or bed.definition_id!="EQ05" or int(bed.floor_id)!=floor_id or not world.facts.rooms.has(bed.get("room_id","")):
			continue
		var ward: Dictionary = world.facts.rooms[bed.room_id]
		if ward.kind!="ward" or bed.failed or not ward.get("structure_valid",true) or not ward.get("open_intent",true) or (not structural_only and (_facility_unavailable(bed) or _bed_busy(world,bed_id,visit.id))):
			continue
		for nurse_id: String in nurses.get(ward.id,[]):
			var nurse: Dictionary = world.facts.staff[nurse_id]
			if nurse_id in excluded or nurse.role!="nurse" or not "q_ward" in nurse.certificates:
				continue
			if reference_schedule and not _reference_assignment_allows(world,nurse_id,"care",visit,bed_id):
				continue
			var continuing_amenity: bool = continuing_stay.get("nurse_id","")==nurse_id and continuing_stay.get("phase","")=="recovery" and nurse.get("life_task",{}).get("kind","")=="amenity" and nurse.life_task.phase=="wait_safe" and _ward_nurse_covering(world,nurse_id,str(ward.id),floor_id)
			if not structural_only and (not nurse.on_shift or not _can_start(world,nurse,continuing_amenity)):
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
			var load: int = int(loads.get(nurse_id,0))
			if load>=int(content.balance.clinical.beds_per_nurse):
				continue
			if int(world.facts.get("gameplay_version",0))>=1:
				if not workbench_reachable.has(nurse_id):
					workbench_reachable[nurse_id] = false
					for id: String in workbenches:
						var position: Array = world.facts.facilities[id].operator_cells[0]
						if space.travel_quote(world,nurse_id,floor_id,position).ok:
							workbench_reachable[nurse_id] = true
							break
				if not workbench_reachable[nurse_id]:
					continue
			var fit: Dictionary = space.facility_quote(world,bed_id,visit.actor_id,[nurse_id])
			if not fit.ok: continue
			var layout: Dictionary = fit if not fit.get("unchanged",false) else space.facility_layout(world,bed_id)
			if space.travel_quote(world,visit.actor_id,floor_id,layout.patient_cell).ok and space.travel_quote(world,nurse_id,floor_id,layout.operator_cells[0]).ok:
				var quote: Dictionary = {"ok":true,"bed_id":bed_id,"nurse_id":nurse_id,"ward_id":ward.id}
				if alternatives==null: return quote
				alternatives.append(quote)
	if alternatives!=null and not alternatives.is_empty(): return alternatives[0]
	return {"ok":false,"reason":"等待同层兼容床位与真实护理覆盖"}

func _prepare_surgery(world: WorldState, visit: Dictionary, ticket: Dictionary) -> void:
	if not _decision_policy_valid(world,visit,ticket): return
	var stay: Dictionary=Flow.ward_stay(world,visit.id)
	if stay.is_empty() or stay.phase=="admitting":
		Flow.admit(self,world,visit,ticket)
		return
	if not stay.phase in ["waiting_surgery","to_surgery"]: return
	if world.sim_tick%WorldState.TICKS_PER_DAY>=12000:
		if world.facts.preparations.has(visit.id): Flow.abort_preparation(self,world,visit,stay,ticket)
		visit.waiting_reason="夜间不启动新手术，在原病房等待白天"
		return
	var existing: Dictionary = world.facts.preparations.get(visit.id,{})
	# Only an already assigned, ready preparation can reach start without an
	# intervening reservation, ticket update, movement or setup step.
	var unchanged_ready: bool = not existing.is_empty() and int(existing.setup_remaining_ticks)==0 and ticket.get("service_assigned",false) and int(ticket.get("called_tick",-1))>=0
	var options: Dictionary = {"facility_id":existing.facility_id,"bed_id":stay.bed_id} if not existing.is_empty() else {"bed_id":stay.bed_id}
	var quote: Dictionary = _surgery_quote(world,visit,existing.get("staff_ids",[]),options)
	if not quote.ok:
		if quote.get("requires_review",false): _decision_valid(world,visit,quote)
		if not existing.is_empty(): Flow.abort_preparation(self,world,visit,stay,ticket)
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
			"nurse_id":quote.nurse_id,"ward_id":quote.ward_id,"supply_units":int(quote.supply_units),
			"deadline_tick":-1,
			"setup_remaining_ticks":ceili(float(content.balance.clinical.or_setup_seconds)*10/(1.0+0.05*(int(world.facts.staff[team[2]].abilities.surgery)-1))/_talent_rate(world,team[2],"or_assist",visit))}
		world.facts.preparations[visit.id] = preparation
		stay.phase="to_surgery"
	if int(preparation.deadline_tick)>=0 and world.sim_tick>=int(preparation.deadline_tick):
		Flow.abort_preparation(self,world,visit,stay,ticket)
		visit.waiting_reason = "准备超过30秒，原票号保留；资源已释放"
		return
	ticket.service_assigned = true
	if int(ticket.get("called_tick",-1))<0:
		ticket.called_tick = world.sim_tick
	var facility: Dictionary = space.facility_layout(world,preparation.facility_id)
	if not _gather(world,visit,facility,team):
		return
	if int(preparation.deadline_tick)<0: preparation.deadline_tick=world.sim_tick+int(content.balance.clinical.bed_reservation_seconds)*10
	if int(preparation.setup_remaining_ticks) > 0:
		_worked_staff[team[2]] = true
		preparation.setup_remaining_ticks -= 1
		visit.waiting_reason = "护士正在真实器械核对"
		return
	# This invocation already checked the fixed bundle against current facts.
	# New reservations or changed setup still require a fresh actual-start check.
	if not unchanged_ready:
		quote = _surgery_quote(world,visit,team,{"facility_id":preparation.facility_id,"bed_id":preparation.bed_id})
	if not quote.ok:
		visit.waiting_reason = quote.reason
		return
	var attempt: Dictionary = _commit_attempt(world,visit,quote)
	stay.attempt_id=attempt.id
	stay.phase="reserved"
	stay.remaining_ticks=int(attempt.recovery_ticks)
	stay.work_credit_milli=0
	stay.care_completed=false
	stay.erase("care_remaining_ticks")
	stay.escort_id=team[2]
	stay.last_progress_tick=world.sim_tick
	if world.facts.adaptations.has(quote.bed_id):
		world.facts.adaptations[quote.bed_id].owner_id = stay.id
	_start(world,visit,"surgery",quote.facility_id,team,int(attempt.work_ticks),{"attempt_id":attempt.id,"clinical_beat":0})
	_support(world,visit,facility,"lying")
	_use(world,facility,attempt.id)
	world.facts.preparations.erase(visit.id)
	world.facts.tickets.erase(ticket.id)
	visit.ticket_id = ""
	visit.phase = "surgery"
	visit.waiting_reason = ""

func _surgery_quote(world: WorldState, visit: Dictionary, requested_team: Array = [], options: Dictionary = {}) -> Dictionary:
	var current_stay: Dictionary=Flow.ward_stay(world,visit.id)
	if not current_stay.is_empty():
		if options.has("bed_id") and str(options.bed_id)!=str(current_stay.bed_id): return {"ok":false,"reason":"本次住院须保留当前原床承诺"}
		options=options.duplicate()
		options.bed_id=current_stay.bed_id
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
	if tables.is_empty(): return {"ok":false,"structural_ok":false,"reason":"缺少手术设备"}
	var team_ids: Array = requested_team if not requested_team.is_empty() else world.ids("staff")
	var availability: Dictionary = {}
	for staff_id: String in team_ids:
		if not world.facts.staff.has(staff_id): continue
		var staff: Dictionary = world.facts.staff[staff_id]
		for index: int in 3:
			if index==2 and Flow.ward_stay(world,visit.id).get("nurse_id","")==staff_id: continue
			if not requested_team.is_empty() and (requested_team.size()!=3 or staff_id!=requested_team[index]):
				continue
			if staff.role!=("nurse" if index==2 else "doctor") or int(staff.abilities.surgery)<int(requirements[index]):
				continue
			if index==2 and not "q_or" in staff.certificates:
				continue
			if index<2 and int(content.definition("doctor_titles",staff.title_id).rank)<int(content.definition("doctor_titles",titles[index]).rank):
				continue
			if not structural:
				if not staff.on_shift or not _can_start(world,staff): continue
				if availability.is_empty(): availability = _availability(world)
				if _staff_busy(world,staff_id,visit.id,availability): continue
			pools[index].append(staff_id)
	# This read-only enumeration shares bed checks only until it returns.
	# The doctors cannot be ward-nurse candidates; only the team's nurse is excluded.
	var bed_quotes: Dictionary = options.get("bed_quotes",{})
	var alternatives: Variant = options.get("alternatives")
	# Only this same-call complete reference enumeration may trust its pools.
	# Actual work and direct bundle requests retain the full validation entry.
	var prequalified: bool = structural and bool(options.get("reference_schedule",false)) and alternatives!=null and visit.attempt_ids.size()<int(content.balance.max_treatment_attempts)
	for research_id: String in plan.requires_research:
		if not research_id in world.facts.research: prequalified = false
	space.begin_route_query(world)
	var best: Dictionary = {"ok":false,"structural_ok":false,"reason":"缺少当前可执行的三个互异手术岗位"}
	if not pools[0].is_empty() and not pools[1].is_empty() and not pools[2].is_empty() and not tables.is_empty():
		var has_bed: bool = false
		for nurse_id: String in pools[2]:
			var bed_quote: Dictionary=_surgery_bed_quote(world,visit,nurse_id,structural,options,bed_quotes)
			has_bed = has_bed or bool(bed_quote.ok)
			best = bed_quote
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
					var team: Array = [surgeon_id,anesthetist_id,nurse_id]
					var quote: Dictionary = _qualified_surgery_bundle_quote(world,visit,team,facility_id,options,bed_quotes,plan,protocol) if prequalified else _surgery_bundle_quote(world,visit,team,facility_id,options,bed_quotes)
					if quote.ok and alternatives!=null: alternatives.append(quote)
					if quote.ok and (not best.ok or int(quote.probability_bp)>int(best.probability_bp) or (int(quote.probability_bp)==int(best.probability_bp) and str(quote.staff_ids)+facility_id<str(best.staff_ids)+str(best.facility_id))):
						best = quote
					elif not best.ok:
						best = quote
	space.end_route_query()
	return best

func _surgery_bed_quote(world: WorldState, visit: Dictionary, nurse_id: String, structural: bool, options: Dictionary, cache: Dictionary) -> Dictionary:
	var preferred: String=str(options.get("bed_id",""))
	var scheduled: bool=bool(options.get("reference_schedule",false))
	var key: String="surgery_bed:"+JSON.stringify([nurse_id,structural,preferred,scheduled])
	if cache.has(key): return cache[key]
	# A plan quote proves eligibility, not an admission destination. The bed
	# can be on another floor; guidance later owns the actual local admission.
	var floors: Array=[]
	for id: String in world.facility_ids("EQ05"):
		if not preferred.is_empty() and id!=preferred: continue
		var floor_id: int=int(world.facts.facilities[id].floor_id)
		if not floor_id in floors: floors.append(floor_id)
	floors.sort()
	var result: Dictionary={"ok":false,"reason":"等待兼容床位与真实护理覆盖"}
	for floor_id: int in floors:
		if structural and scheduled and preferred.is_empty():
			var beds: Array=_scheduled_bed_alternatives(world,visit,floor_id,[nurse_id],cache)
			if not beds.is_empty(): result=beds[0]
		else:
			result=_compatible_bed(world,visit,floor_id,[nurse_id],structural,preferred,scheduled)
		if result.ok: break
	cache[key]=result
	return result

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
	return _qualified_surgery_bundle_quote(world,visit,team,facility_id,options,bed_quotes,plan,protocol)

func _qualified_surgery_bundle_quote(world: WorldState, visit: Dictionary, team: Array, facility_id: String, options: Dictionary, bed_quotes: Dictionary, plan: Dictionary, protocol: Dictionary) -> Dictionary:
	if team[0] == team[1] or team[0] == team[2] or team[1] == team[2]:
		return {"ok":false,"reason":"手术岗位必须互异"}
	var table: Dictionary = world.facts.facilities[facility_id]
	var predicted: Dictionary = _surgery_probability(world,visit,team,table,protocol)
	if int(predicted.probability_bp)<roundi(float(content.balance.clinical.minimum_predicted_success)*10000):
		return {"ok":false,"reason":"预计效果低于原玩法门槛","requires_review":true,"probability_bp":int(predicted.probability_bp)}
	var structural: bool = bool(options.get("structural_only",false))
	if not structural or bool(options.get("reference_schedule",false)):
		for staff_id: String in team:
			if not _reference_assignment_allows(world,staff_id,"surgery",visit,facility_id):
				return {"ok":false,"structural_ok":true,"reason":"等待排班手术池内的完整团队"}
	if not world.facts.rooms.has(table.get("room_id","")):
		return {"ok":false,"reason":"手术台缺少合法手术室"}
	var operating_room: Dictionary = world.facts.rooms[table.room_id]
	if table.failed or not bool(table.get("open",true)) or not bool(table.get("intake_open",true)) or not operating_room.get("open_intent",true) or not operating_room.get("structure_valid",true) or operating_room.kind!="operating_room":
		return {"ok":false,"reason":"手术室未满足最小内部8×8"}
	if not structural and (_facility_unavailable(table) or _facility_busy(world,facility_id,visit.id)):
		return {"ok":false,"structural_ok":true,"reason":"等待原手术台安全可用"}
	var bed_bundle: Dictionary = _surgery_bed_quote(world,visit,str(team[2]),structural,options,bed_quotes)
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
	var preparation: Dictionary=world.facts.preparations.get(str(visit.id),{})
	var committed: bool=preparation.get("facility_id","")==facility_id
	for index: int in 4:
		var actor_id: String = visit.actor_id if index==0 else str(team[index-1])
		var position: Array = layout.patient_cell if index==0 else layout.operator_cells[index-1]
		var movement: Dictionary=world.facts.moves.get(actor_id,{})
		if committed and not movement.is_empty() and int(movement.target_floor)==int(table.floor_id) and movement.target_cell==position:
			var failure: Dictionary=space.movement_failure(world,actor_id) if world.facts.actors[actor_id].location.kind=="floor" else {}
			if not failure.is_empty(): return {"ok":false,"reason":str(failure.reason)}
			# The original move owns this already-proved journey, including its
			# real ride. Arrival is still required by _gather before setup/start.
			# Do not estimate another ground departure from inside the cabin.
			continue
		var route: Dictionary = space.travel_quote(world,actor_id,int(table.floor_id),position)
		if not route.ok:
			return route
		gathering_ticks = maxi(gathering_ticks,int(route.travel_ticks))
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
	return seconds

func _bed_service_ticks(world: WorldState, visit: Dictionary, kind: String, staff_id: String) -> int:
	var staff: Dictionary = world.facts.staff[staff_id]
	var seconds: float = float(content.balance.clinical.nurse_visit_seconds)
	var level: int = int(staff.abilities.care) if kind=="care" else int(staff.abilities.treatment)
	if staff.role=="doctor": seconds *= 1.0+float(content.balance.wellbeing.fatigue_work_multiplier_per_point)*float(staff.fatigue)
	return ceili(seconds/(1.0+0.05*(level-1))*10/_talent_rate(world,staff_id,"ward_visit",visit))

func _recovery_rate(world: WorldState, bed_id: String, nurse_id: String) -> int:
	var bed: Dictionary = world.facts.facilities[bed_id]
	var nurse: Dictionary = world.facts.staff[nurse_id]
	var effective: float = float(bed.grade)*float(content.balance.medical_equipment_effects.utilization_by_level[int(nurse.abilities.care)])
	return roundi((1.0+0.15*effective)*1000)

# Form a real queue with enough trailing space and a reachable escort post.
# Travel headings never authorize bodies through walls or occupied doors.
func _escort_formation(world: WorldState, patient_id: String, escort_id: String, target_floor: int, target: Array) -> Dictionary:
	var actor: Dictionary = world.facts.actors[patient_id]
	if actor.location.kind!="floor": return {"ok":false,"reason":"等待患者真实落地后成队"}
	var members: Array = [patient_id,escort_id]
	var preferred: Dictionary = space.route(world,patient_id,target_floor,target,members,{},true)
	var start: Vector2 = ConvoyTrail.point(actor.location.cell)
	var directions: Array[Vector2] = []
	for segment: Dictionary in preferred.get("path",[]):
		if segment.kind=="connector": break
		if segment.kind!="floor": continue
		var delta: Vector2 = ConvoyTrail.point(segment.cell)-start
		if delta.length()>0.001:
			directions.append(Vector2(signf(delta.x),0) if absf(delta.x)>absf(delta.y) else Vector2(0,signf(delta.y)))
			break
	for direction: Vector2 in [Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT,Vector2.UP]:
		if not direction in directions: directions.append(direction)
	var reason: String = "队列成队空间不足"
	for direction: Vector2 in directions:
		var formation: Dictionary = _escort_formation_candidate(world,patient_id,escort_id,target_floor,target,direction)
		if formation.ok: return formation
		reason = formation.get("reason",reason)
	return {"ok":false,"reason":reason}

func _escort_formation_candidate(world: WorldState, patient_id: String, escort_id: String, target_floor: int, target: Array, direction: Vector2) -> Dictionary:
	var members: Array = [patient_id,escort_id]
	var actor: Dictionary = world.facts.actors[patient_id]
	var floor_id: int = int(actor.location.floor_id)
	var formation: Dictionary = ConvoyTrail.formation(space,world,patient_id,members,direction)
	var facts: Dictionary = world.facts.duplicate()
	facts.actors = world.facts.actors.duplicate()
	facts.actors[escort_id] = world.facts.actors[escort_id].duplicate()
	facts.actors[escort_id].location = {"kind":"floor","floor_id":floor_id,"cell":formation.targets[escort_id].duplicate(),"height_m":0.0}
	var projected: WorldState = WorldState.new(facts)
	var created: Dictionary = ConvoyTrail.create(space,projected,patient_id,members)
	if not created.ok: return created
	var movement: Dictionary = {"actor_id":patient_id,"members":members,"convoy":created.convoy}
	var proxy: Dictionary = ConvoyTrail.proxy(projected,movement)
	var shift: Vector2 = Vector2.ONE*float(formation.shift)
	var query: RouteClearance = space.navigation.structural_clearance(projected,proxy,floor_id)
	var reason: String = query.sweep_reason(ConvoyTrail.point(created.convoy.points[0])+shift,ConvoyTrail.point(created.convoy.points[-1])+shift)
	if not reason.is_empty(): return {"ok":false,"reason":reason}
	# A complete group must gather outside doors before acquiring door passage.
	for region: Rect2 in ConvoyTrail.regions(created.convoy):
		for door: Dictionary in space.movement_doors(projected,proxy,region):
			if region.intersects(space._door_rect(door,space._door_span(proxy,door)),false): return {"ok":false,"reason":"必须离开门口后完整成队"}
	var gathering: Dictionary = space.travel_quote(world,escort_id,floor_id,formation.targets[escort_id])
	if not gathering.ok: return {"ok":false,"reason":gathering.get("reason","护士无法到达队尾集合位置")}
	facts.moves = world.facts.moves.duplicate()
	facts.moves[patient_id] = movement
	projected = WorldState.new(facts)
	space.navigation.inherit_projection(world,projected)
	var route: Dictionary = space.route(projected,patient_id,target_floor,target,members,{},true)
	if not route.ok: return {"ok":false,"reason":route.get("reason","队长路线不可达")}
	formation.ok = true
	formation.route = route
	formation.gathering = gathering
	formation.direction = [direction.x,direction.y]
	return formation

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
		for id: String in actor_ids:
			facts.actors[id] = world.facts.actors[id].duplicate()
			facts.actors[id].location = world.facts.actors[id].location.duplicate()
	return WorldState.new(facts)

func _reserve_bundle(world: WorldState, visit: Dictionary, quote: Dictionary, owner_id: String) -> String:
	var existing_stay: Dictionary=Flow.ward_stay(world,visit.id)
	var workers: Array = quote.staff_ids.duplicate()
	for field: String in ["nurse_id"]:
		if existing_stay.is_empty() and quote.has(field) and not quote[field] in workers: workers.append(quote[field])
	if HospitalStaffWellbeing.yield_for_work(world,content,space,workers): return "公共娱乐尚未开始，等待原整组安全离位"
	var facility_ids: Array = [quote.facility_id]
	var reserve_bed: bool=quote.has("bed_id") and existing_stay.is_empty()
	if reserve_bed: facility_ids.append(quote.bed_id)
	var candidate: WorldState = _reservation_candidate(world,facility_ids)
	var geometry: HospitalSpace = HospitalSpace.new(content)
	geometry._navigation = space._navigation
	var reason: String = geometry.reserve_facility(candidate,quote.facility_id,visit.actor_id,owner_id,quote.staff_ids)
	if not reason.is_empty():
		return reason
	if reserve_bed:
		reason = geometry.reserve_facility(candidate,quote.bed_id,visit.actor_id,owner_id,[quote.nurse_id])
		if not reason.is_empty():
			return reason
	space.commit_facility_reservations(world,candidate.facts.adaptations,facility_ids)
	if quote.has("bed_id"): world.facts.staff[quote.nurse_id].ward_id = quote.ward_id
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
	if environment!=null: environment.call("session_written",world,id)
	visit.last_service_tick = world.sim_tick
	visit.last_progress_tick = world.sim_tick
	if experience != null:
		experience.call("service_started",world,session)
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
		var action: String = {"gp":"gp","spectrum":"test","resonance":"test","outpatient":"outpatient","care":"ward_visit"}.get(session.kind,"")
		if not action.is_empty():
			for staff_id: String in session.staff_ids:
				recruitment.call("service_mood",world,staff_id,action,visit.id,session)
	if experience != null:
		experience.call("service_completed",world,session)
	if session.kind in ["gp","outpatient","surgery"]:
		if not visit.has("clinical_participants"):
			visit.clinical_participants = {}
		for staff_id: String in session.staff_ids:
			if world.facts.staff[staff_id].role=="doctor":
				visit.clinical_participants[staff_id] = true
	if environment!=null: environment.call("session_removing",world,str(session.id))
	world.facts.sessions.erase(session.id)
	_events.append(SimEvent.new(world.sim_tick,"service_completed",[visit.id,session.id],{"kind":session.kind}))
	match session.kind:
		"gp", "spectrum", "resonance":
			if session.kind == "gp":
				HospitalLedger.post(world,LedgerEntry.new(visit.id,"consultation",int(session.doctor_fee)),false)
			HospitalLedger.post(world,LedgerEntry.new(visit.id,str(session.kind),int(session.facility_fee)),false)
			_practice(world,session.staff_ids[0],"diagnosis",session.id)
			Flow.complete_diagnostic(self,world,visit,session)
		"consult":
			var progress: Dictionary=Flow.diagnosis(visit)
			progress.review_completed=true
			progress.state="diagnosed"
			if research!=null: research.call("record_diagnostic_work",world,visit,"consult")
			Flow.choose_plan(self,world,visit,str(progress.doctor_id))
		"outpatient":
			var attempt: Dictionary = world.facts.attempts[session.attempt_id]
			if environment != null:
				environment.call("record_use",world,"outpatient_completed",session.facility_id,attempt.id)
			HospitalLedger.post(world,LedgerEntry.new(attempt.id,"outpatient",int(attempt.facility_fee)),false)
			_practice(world,session.staff_ids[0],"treatment",session.id)
			_record_plan_experience(world,attempt)
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
			Flow.ward_stay(world,visit.id).phase = "transfer"
			visit.phase = "transfer"
		"care":
			var care_stay: Dictionary=world.facts.ward_stays[session.stay_id]
			care_stay.care_completed = true
			care_stay.erase("care_remaining_ticks")
			_practice(world,session.staff_ids[0],"care",session.id)
			_release_ward_operator(world,care_stay,session.staff_ids[0])
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
		if release.has("cancel_cell"):
			var approach: Dictionary = world.facts.moves.get(staff_id,{})
			if _gathering_move(approach,int(release.cancel_floor),release.cancel_cell) and not space.cancel_ground_move(world,staff_id):
				continue
			release.erase("cancel_floor")
			release.erase("cancel_cell")
		var reservation: Dictionary = world.facts.adaptations.get(release.facility_id,{})
		# Older saves identify ward parking by its target; new pending ward
		# releases keep their kind even when no safe route is available yet.
		if not reservation.is_empty() and world.facts.facilities.get(release.facility_id,{}).get("definition_id","")=="EQ05" and (release.has("target_cell") or bool(release.get("ward",false))):
			_dispatch_ward_release(world,staff_id,release,reservation)
			continue
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
		var checker: RouteClearance
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
				if intersects: continue
				if checker==null: checker = RouteClearance.new(space,world,actor,int(actor.location.floor_id),[],{},true,space._navigation.floor_source(space,world,int(actor.location.floor_id)))
				if not checker.reason(point).is_empty() or space.movement._narrow(world,actor,point,checker) or not space._dynamic_clear(world,staff_id,int(actor.location.floor_id),rect):
					continue
				if space.can_reach(world,staff_id,int(actor.location.floor_id),[point.x,point.y],[],{},true):
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
	var visit_id: String = str(stay.visit_id)
	var release: Dictionary = world.facts.staff[staff_id].get("clinical_release",{})
	# Care/round dispatch can request the same exit again before its first
	# physical step. Retain the owner and target of that existing journey.
	if not release.is_empty() and (release.facility_id!=stay.bed_id or release.visit_id!=visit_id): return
	if release.is_empty():
		release = {"facility_id":stay.bed_id,"visit_id":visit_id,"phase":"seek","reason":"","ward":true}
		world.facts.staff[staff_id].clinical_release = release
	else:
		release.ward = true
	_dispatch_ward_release(world,staff_id,release,world.facts.adaptations.get(stay.bed_id,{}))

func _dispatch_ward_release(world: WorldState, staff_id: String, release: Dictionary, reservation: Dictionary) -> void:
	var actor: Dictionary = world.facts.actors[staff_id]
	var staff: Dictionary = world.facts.staff[staff_id]
	var bed: Dictionary = space.facility_layout(world,str(release.facility_id))
	var movement: Dictionary = world.facts.moves.get(staff_id,{})
	# Do not take over another task, a supported exit, or a ride. Ordinary
	# clinical parking is only this actor's single-person same-floor trip.
	if actor.location.kind!="floor" or int(actor.location.floor_id)!=int(bed.floor_id) or actor.get("posture","standing")=="lying": return
	var training: Dictionary = world.facts.get("training_jobs",{}).get(staff.get("training_job_id",""),{})
	if training.get("state","") in ["travelling","working"] or not staff.get("life_task",{}).get("phase","idle") in ["idle","wait_safe"] or not str(staff.get("active_job_id","")).is_empty(): return
	for session: Dictionary in world.facts.sessions.values():
		if staff_id in session.staff_ids: return
	for preparation: Dictionary in world.facts.preparations.values():
		if staff_id in preparation.staff_ids: return
	for stay: Dictionary in world.facts.ward_stays.values():
		if stay.get("phase","")=="transfer" and stay.get("escort_id","")==staff_id: return
	for handoff: Dictionary in world.facts.get("staff_schedule",{}).get("handoffs",{}).values():
		if handoff.get("new_id","")==staff_id: return
	if not movement.is_empty():
		if not release.has("target_cell") or int(release.target_floor)!=int(bed.floor_id) or not _gathering_move(movement,int(release.target_floor),release.target_cell): return
		if int(movement.cursor)>=0 and int(movement.cursor)<movement.path.size() and movement.path[int(movement.cursor)].kind!="floor": return
	if release.has("target_cell") and space.at(world,staff_id,int(release.target_floor),release.target_cell):
		var clear: bool = true
		for region: Array in reservation.get("regions",[]):
			clear = clear and not space.body_rectangle(actor).intersects(Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3])).grow(1.0),false)
		if clear and space.cancel_ground_move(world,staff_id):
			staff.erase("clinical_release")
			return
	var parking_occupied: bool=false
	if release.has("target_cell"):
		var target_body: Rect2=space._actor_rect(actor,ConvoyTrail.point(release.target_cell))
		space._ensure_actor_index(world)
		for other_id: String in space._actor_index.candidates(int(bed.floor_id),target_body,[staff_id]):
			if not world.facts.moves.has(other_id) and target_body.intersects(space.body_rectangle(world.facts.actors[other_id]),false):
				parking_occupied=true
				break
	# A local walk is not a promise that its parking point stays available.
	# Reconsider an occupied point even between the current bypass's corners.
	if not movement.is_empty() and not parking_occupied:
		if bool(movement.get("route_pending",false)): return
		var detour: Dictionary = movement.get("detour",{})
		if not detour.is_empty() and int(movement.cursor)<int(detour.prefix_size): return
		var local: Dictionary = movement.get("local_move",{})
		if not local.is_empty() and (int(actor.location.floor_id)!=int(local.target.floor_id) or ConvoyTrail.point(actor.location.cell)!=ConvoyTrail.point(local.target.cell)): return
		if str(movement.get("waiting_reason","")).is_empty() and int(movement.get("blocked_since",-1))<0: return
	# The parking point is a preference, not a promise to wait forever for
	# a stationary colleague. Keep the bed's full exit buffer when reselecting.
	var selected: Array = _ward_release_target(world,staff_id,str(release.facility_id))
	if selected.is_empty():
		release.phase = "blocked"
		release.reason = "等待真实可达且不占床边通路的离位空间"
		return
	if parking_occupied and not movement.is_empty() and not space.cancel_ground_move(world,staff_id): return
	var reason: String = space.request_move(world,staff_id,int(bed.floor_id),selected)
	if _gathering_move(world.facts.moves.get(staff_id,{}),int(bed.floor_id),selected):
		release.target_floor = int(bed.floor_id)
		release.target_cell = selected
		release.phase = "walking"
	release.reason = reason

func _ward_release_target(world: WorldState, staff_id: String, facility_id: String) -> Array:
	var bed: Dictionary = space.facility_layout(world,facility_id)
	var ward: Dictionary = world.facts.rooms[bed.room_id]
	var actor: Dictionary = world.facts.actors[staff_id]
	var reservation: Dictionary = world.facts.adaptations.get(facility_id,{})
	var candidates: Array = []
	var release_targets: Dictionary = {}
	for other: Dictionary in world.facts.staff.values():
		var target: Array = other.get("clinical_release",{}).get("target_cell",[])
		if other.id!=staff_id and target.size()==2 and target==[int(target[0]),int(target[1])]:
			release_targets[Vector2i(int(target[0]),int(target[1]))] = true
	var checker: RouteClearance = RouteClearance.new(space,world,actor,int(bed.floor_id),[],{},true,space._navigation.floor_source(space,world,int(bed.floor_id)))
	for y: int in range(int(ward.origin[1]),int(ward.origin[1])+int(ward.size[1])):
		for x: int in range(int(ward.origin[0]),int(ward.origin[0])+int(ward.size[0])):
			var point: Vector2i = Vector2i(x,y)
			var body: Rect2 = space._actor_rect(actor,Vector2(point))
			var blocked: bool = false
			for region: Array in reservation.get("regions",[]):
				blocked = blocked or body.intersects(Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3])).grow(1.0),false)
			blocked = blocked or release_targets.has(point)
			if blocked or not checker.reason(point).is_empty() or not space._dynamic_clear(world,staff_id,int(bed.floor_id),body):
				continue
			candidates.append({"cell":[x,y],"distance":absf(float(actor.location.cell[0])-x)+absf(float(actor.location.cell[1])-y)})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a.distance<b.distance)
	# Route quotes do not account for people along the route. Prove the
	# selected route's real body sweeps now, without moving or asking any
	# other actor to yield; ordinary movement still checks every later step.
	var proof: Dictionary = {"sweeps":{},"segments":{}}
	for candidate: Dictionary in candidates:
		var route: Dictionary = space.route(world,staff_id,int(bed.floor_id),candidate.cell)
		if not route.ok or route.get("status","")=="contention": continue
		var ground: bool = true
		for segment: Dictionary in route.path:
			ground = ground and segment.kind=="floor" and int(segment.floor_id)==int(bed.floor_id)
		if ground and space.movement._detour_path_clear(world,actor,{},route.path,checker,proof):
			return candidate.cell
	return []

func _clear_bed_exit(world: WorldState, visit: Dictionary, stay: Dictionary) -> void:
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	if actor.get("posture","standing")!="lying": return
	var bed: Dictionary = space.facility_layout(world,stay.bed_id)
	var origin: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	var target: Vector2 = Vector2(float(bed.patient_cell[0]),float(bed.patient_cell[1]))
	var moving: Dictionary = actor.duplicate()
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
	if not staff.on_shift or float(staff.energy)<=15.0 or not str(staff.get("life_task",{}).get("phase","idle")) in ["idle","wait_safe"] or bed.failed:
		visit.waiting_reason = "等待可以安全执行床边护理的护士"
		return
	if int(world.facts.get("gameplay_version",0))>=1 and not visitors.call("yield_for_care",world,visit.id):
		visit.waiting_reason = "等待实际家属让出护理操作区"
		return
	if not space.at(world,staff_id,int(bed.floor_id),bed.operator_cells[0]):
		visit.waiting_reason = space.request_move(world,staff_id,int(bed.floor_id),bed.operator_cells[0])
		return
	_start(world,visit,"care",stay.bed_id,[staff_id],int(stay.get("care_remaining_ticks",_bed_service_ticks(world,visit,"care",staff_id))),{"stay_id":stay.id})

func _complete_ward(world: WorldState, visit: Dictionary, stay: Dictionary) -> void:
	var attempt: Dictionary = world.facts.attempts[stay.attempt_id]
	stay.work_credit_milli=0
	HospitalLedger.post(world,LedgerEntry.new(attempt.id,"ward",int(attempt.get("ward_fee",content.facility_fee("EQ05","ward")))),false)
	_settle(world,visit,attempt)
	stay.phase = "release_wait" if visit.phase=="leaving" else "waiting_surgery"

func _settle(world: WorldState, visit: Dictionary, attempt: Dictionary) -> void:
	if world.facts.actors[visit.actor_id].get("posture","standing") == "seated":
		world.facts.actors[visit.actor_id].posture = "standing"
		world.facts.actors[visit.actor_id].erase("support_facility_id")
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
		visit.plan_decision={}
		Flow.choose_plan(self,world,visit,str(attempt.staff_ids[0]))
	else:
		visit.final_result = "referred"
		visit.phase = "leaving"
	var stay: Dictionary=Flow.ward_stay(world,visit.id)
	if not stay.is_empty() and visit.phase=="leaving": stay.phase="release_wait"
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

func _ward_command(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	var visit_id: String = str(payload.get("visit_id",""))
	if not world.facts.visits.has(visit_id):
		return CommandResult.new(false,"visit_missing","原病例已不存在",[],world.revision)
	if kind=="clinical_visit_consent":
		world.facts.visits[visit_id].visitor_consent = bool(payload.get("allow",true))
		return CommandResult.new(true,"applied","",[visit_id],world.revision)
	for stay: Dictionary in world.facts.ward_stays.values():
		if stay.visit_id!=visit_id or not stay.phase in ["waiting_surgery","recovery"]:
			continue
		var visit: Dictionary = world.facts.visits[visit_id]
		if kind=="clinical_ward_refer":
			_begin_ward_referral(world,visit,stay)
			return CommandResult.new(true,"applied","",[visit_id,stay.id],world.revision)
		var reason: String = _transfer_stay(world,visit,stay,str(payload.get("bed_id","")))
		return CommandResult.new(reason.is_empty(),"applied" if reason.is_empty() else "transfer_unavailable",reason,[visit_id,stay.id] if reason.is_empty() else [],world.revision)
	return CommandResult.new(false,"ward_stay_missing","患者当前没有可交接的住院床位",[],world.revision)

func _ward_staff_wait_reason(world: WorldState, stay: Dictionary, _kind: String) -> String:
	var reason: String = "等待本病房实际护理覆盖"
	if world.sim_tick-int(stay.last_progress_tick)<int(content.balance.clinical.staff_shortage_prompt_seconds)*10:
		return reason
	return reason+"；请调整房间排班或招聘护理人员"

func _ward_covering(world: WorldState, stay: Dictionary, nurse_coverage: Dictionary = {}) -> bool:
	var bed: Dictionary = world.facts.facilities[stay.bed_id]
	if bed.failed: return false
	var key: String = JSON.stringify([stay.nurse_id,bed.room_id,bed.floor_id])
	if not nurse_coverage.has(key): nurse_coverage[key] = _ward_nurse_covering(world,stay.nurse_id,str(bed.room_id),int(bed.floor_id))
	if not nurse_coverage[key]: return false
	var layout: Dictionary = space.facility_layout(world,stay.bed_id)
	return bool(space.travel_quote(world,stay.nurse_id,int(bed.floor_id),layout.operator_cells[0]).ok)

func _ward_nurse_covering(world: WorldState, nurse_id: String, ward_id: String, floor_id: int) -> bool:
	var nurse: Dictionary = world.facts.staff.get(nurse_id,{})
	if nurse.is_empty() or not nurse.on_shift or not "q_ward" in nurse.certificates or str(nurse.get("ward_id",""))!=str(ward_id) or not bool(nurse.get("base_prepared",true)):
		return false
	if not str(nurse.get("life_task",{}).get("phase","idle")) in ["idle","wait_safe"]:
		return false
	for session: Dictionary in world.facts.sessions.values():
		if nurse_id in session.staff_ids and (session.kind!="care" or world.facts.facilities[session.facility_id].get("room_id","")!=ward_id):
			return false
	if not str(nurse.get("active_job_id","")).is_empty():
		return false
	var location: Dictionary = world.facts.actors[nurse_id].location
	if location.kind!="floor" or int(location.floor_id)!=floor_id:
		return false
	return true



func _transfer_stay(world: WorldState, visit: Dictionary, stay: Dictionary, preferred_bed: String = "") -> String:
	if not visitors.call("yield_for_care",world,visit.id):
		return "等待家属实际让开转床通路"
	var old_bed: Dictionary = space.facility_layout(world,stay.bed_id)
	var candidate: WorldState = _reservation_candidate(world,[],[visit.actor_id])
	var actor: Dictionary = candidate.facts.actors[visit.actor_id]
	actor.posture = "standing"
	actor.location.cell = old_bed.patient_cell.duplicate()
	actor.location.height_m = 0.0
	var quote: Dictionary = _compatible_bed(candidate,visit,int(old_bed.floor_id),[],false,preferred_bed,false,null,stay)
	if not quote.ok or quote.get("bed_id","")==stay.bed_id or (not preferred_bed.is_empty() and quote.get("bed_id","")!=preferred_bed):
		return "暂无具备真实覆盖与路线的兼容替代床"
	var reason: String = space.reserve_facility(world,quote.bed_id,visit.actor_id,stay.id,[quote.nurse_id])
	if not reason.is_empty():
		return reason
	_pause_bed_sessions(world,stay)
	stay.transfer_from_bed_id = stay.bed_id
	if world.facts.adaptations.has(stay.bed_id):
		world.facts.adaptations[stay.bed_id].owner_id = visit.actor_id
	stay.bed_id = quote.bed_id
	stay.nurse_id = quote.nurse_id
	stay.escort_id = quote.nurse_id
	stay.transfer_resume_phase="waiting_surgery" if stay.phase=="waiting_surgery" else "recovery"
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
			if environment!=null: environment.call("session_removing",world,id)
			world.facts.sessions.erase(id)

func _begin_ward_referral(world: WorldState, visit: Dictionary, stay: Dictionary) -> void:
	_release_preparation(world,visit.id)
	world.facts.tickets.erase(str(visit.get("ticket_id","")))
	visit.ticket_id=""
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
	var result: Dictionary = {"staff":{},"facilities":{},"preparations":{},"preparation_staff":{},"gathering_staff":{}}
	for actor: Dictionary in world.facts.actors.values():
		var id: String = str(actor.get("support_facility_id",""))
		if not id.is_empty() and space.overlaps_facility(world,actor.id,id): result.facilities[id] = true
	for session: Dictionary in world.facts.sessions.values():
		result.facilities[session.facility_id] = true
		for id: String in session.staff_ids: result.staff[id] = true
	for stay: Dictionary in world.facts.ward_stays.values():
		if stay.phase=="transfer": result.staff[stay.escort_id] = true
	for guidance: Dictionary in world.facts.get("patient_experience",{}).get("guidance",{}).values():
		if guidance.get("phase","") in ["working","travel"]:
			for id: String in guidance.get("staff_ids",[]): result.staff[id] = true
	for preparation: Dictionary in world.facts.preparations.values():
		result.preparations[preparation.facility_id] = preparation.id
		for id: String in preparation.staff_ids: result.preparation_staff[id] = preparation.id
	for reservation: Dictionary in world.facts.adaptations.values():
		var visit_id: String = _gathering_visit(world,reservation)
		if visit_id.is_empty(): continue
		for id: String in reservation.staff_ids:
			if not result.gathering_staff.has(id): result.gathering_staff[id] = {}
			result.gathering_staff[id][visit_id] = true
	return result

func _gathering_visit(world: WorldState, reservation: Dictionary) -> String:
	# Ticket-owned gathering holds reserve active work. Bed access, completed
	# service exit permissions and orphan holds do not own the employee's time.
	if reservation.get("kind","")!="facility" or reservation.get("staff_ids",[]).size()!=1: return ""
	var ticket_id: String = str(reservation.get("owner_id",""))
	var ticket: Dictionary = world.facts.tickets.get(ticket_id,{})
	if not bool(ticket.get("service_assigned",false)) or not ticket.get("kind","") in ["gp","spectrum","resonance","consult","outpatient"]: return ""
	var visit: Dictionary = world.facts.visits.get(str(ticket.get("visit_id","")),{})
	if visit.get("ticket_id","")!=ticket_id or visit.get("phase","")!="wait_"+str(ticket.kind) or visit.get("actor_id","")!=reservation.get("actor_id",""): return ""
	var facility: Dictionary = world.facts.facilities.get(str(reservation.get("facility_id",reservation.get("id",""))),{})
	if facility.is_empty() or facility.get("definition_id","")=="EQ05": return ""
	return str(visit.get("id",""))

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
	if not availability.is_empty():
		var gathering: Dictionary = availability.get("gathering_staff",{}).get(id,{})
		return availability.staff.has(id) or availability.preparation_staff.has(id) and availability.preparation_staff[id]!=except_preparation or not gathering.is_empty() and (gathering.size()>1 or not gathering.has(except_preparation))
	for guidance: Dictionary in world.facts.get("patient_experience",{}).get("guidance",{}).values():
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
	for reservation: Dictionary in world.facts.adaptations.values():
		if not id in reservation.get("staff_ids",[]): continue
		var visit_id: String = _gathering_visit(world,reservation)
		if not visit_id.is_empty() and visit_id!=except_preparation: return true
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
		var critical: bool = stay.phase in ["reserved","transfer","recovery"]
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

func _schedule_allows(world: WorldState, staff_id: String, kind: String, _visit: Dictionary, facility_id: String) -> bool:
	if scheduler==null: return true
	var facility: Dictionary = world.facts.facilities.get(facility_id,{})
	var room: Dictionary = world.facts.rooms.get(str(facility.get("room_id","")),{})
	if room.is_empty(): return false
	var staff: Dictionary = world.facts.staff[staff_id]
	var assignment: Dictionary = scheduler.call("assignment",world,staff_id,int(scheduler.call("shift_index",world)))
	if not str(room.id) in assignment.get("pools",[]): return false
	if room.kind=="gp": return staff.role=="doctor" and assignment.kind=="outpatient"
	if room.kind=="treatment": return not kind in ["gp","consult"] and staff.role in ["doctor","nurse"] and assignment.kind==("outpatient" if staff.role=="doctor" else "work")
	if room.kind=="operating_room": return kind=="surgery" and assignment.kind==("surgery" if staff.role=="doctor" else "work")
	if room.kind=="ward": return staff.role=="nurse" and assignment.kind=="work"
	return false

func _reference_assignment_allows(world: WorldState, staff_id: String, kind: String, visit: Dictionary, facility_id: String) -> bool:
	return _schedule_allows(world,staff_id,kind,visit,facility_id)

func shortage_requests(world: WorldState) -> Array:
	var result: Array = []
	var held: int = 0
	var held_by_preparation: Dictionary = {}
	for preparation: Dictionary in world.facts.preparations.values():
		var units: int = int(preparation.get("supply_units",0))
		held += units
		held_by_preparation[preparation.id] = int(held_by_preparation.get(preparation.id,0))+units
	var candidate: WorldState
	for ticket_id: String in world.ids("tickets"):
		var ticket: Dictionary = world.facts.tickets[ticket_id]
		if not ticket.kind in ["outpatient","surgery"]:
			continue
		var visit: Dictionary = world.facts.visits[ticket.visit_id]
		var plan_id: String = str(visit.plan_decision.get("plan_id",visit.requested_plan_id))
		var plan: Dictionary = content.definition("treatment_plans",plan_id)
		var protocol: Dictionary = content.definition("treatment_protocols",str(plan.get("protocol_id","")))
		var available: int = int(world.facts.inventory.units)-held+int(held_by_preparation.get(visit.id,0))
		if protocol.is_empty() or available>=_required_supplies(visit,protocol):
			continue
		if candidate==null:
			var facts: Dictionary = world.facts.duplicate()
			facts.staff = world.facts.staff.duplicate()
			for id: String in facts.staff: facts.staff[id] = facts.staff[id].duplicate()
			candidate = WorldState.new(facts)
			for staff: Dictionary in candidate.facts.staff.values():
				staff.supply_strike = false
		var quote: Dictionary = plan_quote(candidate,visit.id,plan_id,{"ignore_supplies":true})
		if quote.ok and available<int(quote.supply_units):
			result.append({"ticket_id":ticket_id,"visit_id":visit.id,"staff_ids":quote.staff_ids.duplicate(),"units":int(quote.supply_units)})
	return result

func arrival_readiness(world: WorldState, binding_id: String, _complex_case: bool = false, _explain: bool = true) -> Dictionary:
	var binding: Dictionary = content.definition("treatment_bindings",binding_id)
	var eligibility: Dictionary = _arrival_case_readiness(world,binding)
	if not eligibility.ok: return eligibility
	var entry: Dictionary = world.facts.get("entry",{"floor_id":1,"cell":[47,93]})
	var actor: Dictionary = {"id":"arrival_probe","species_id":binding.species_id,"body_binding_id":binding.id,
		"location":{"kind":"floor","floor_id":int(entry.floor_id),"cell":entry.cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
	var reason: String = space.static_reason(world,actor,int(entry.floor_id),Vector2i(int(entry.cell[0]),int(entry.cell[1])))
	return {"ok":reason.is_empty(),"reason":reason,"plans":[]}

# Eligibility only: callers must own their entry geometry check. This is not
# a public readiness shortcut and does not retain any proof across calls.
func _arrival_case_readiness(world: WorldState, binding: Dictionary) -> Dictionary:
	if binding.is_empty(): return {"ok":false,"reason":"病例绑定不存在","plans":[]}
	if not HospitalResearch.disease_unlocked(world,content,str(binding.disease_id),_research_jobs.view(world)):
		return {"ok":false,"reason":"病例研究尚未完成","plans":[]}
	return {"ok":true,"reason":"","plans":[]}

# Structural quote enumeration only. This local memo shares physical bed
# checks inside one synchronous quote; it never filters arrival demand.
func _scheduled_bed_alternatives(world: WorldState, visit: Dictionary, floor_id: int, excluded: Array, cache: Dictionary) -> Array:
	var key: Array=["scheduled_beds",floor_id]
	if not cache.has(key):
		var beds: Array=[]
		_compatible_bed(world,visit,floor_id,[],true,"",true,beds)
		cache[key]=beds
	var result: Array=[]
	for bed: Dictionary in cache[key]:
		if not bed.nurse_id in excluded: result.append(bed)
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

func _can_start(world: WorldState, staff: Dictionary, continuing_ward_transfer: bool = false) -> bool:
	# A pending amenity does not revoke the original ward's safe transfer duty.
	var window: bool = continuing_ward_transfer or (not bool(staff.get("block_new_work",false)) and HospitalStaffWellbeing.work_window(staff))
	return not staff.has("clinical_release") and (staff.role=="doctor" or bool(staff.get("base_prepared",true))) and window and not bool(staff.get("supply_strike",false)) and world.sim_tick>=int(staff.get("supply_return_tick",-1)) and float(staff.energy)>15.0 and (staff.role!="doctor" or float(staff.fatigue)<float(content.balance.wellbeing.fatigue_stop_new_work))

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
		if record.facility_id!=facility_id or not record.kind in ["gp","spectrum","resonance","consult","outpatient"] or not record.has("original_ticket"): continue
		var visit: Dictionary = world.facts.visits[record.visit_id]
		var ticket: Dictionary = record.original_ticket
		record.erase("original_ticket")
		record.suspended_tick = world.sim_tick
		record.definition_id = world.facts.facilities[facility_id].definition_id
		record.suspended_ticket_id = ticket.id
		if environment!=null: environment.call("session_removing",world,id)
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
	if environment!=null: environment.call("session_written",world,str(record.id))
	world.facts.clinical_suspensions.erase(record.id)
	world.facts.preparations.erase(visit.id)
	world.facts.tickets.erase(ticket.id)
	visit.ticket_id = ""
	visit.phase = record.kind
	if world.facts.adaptations.has(facility.id): world.facts.adaptations[facility.id].owner_id = record.id
	if record.kind=="outpatient": _support(world,visit,facility,"seated")
