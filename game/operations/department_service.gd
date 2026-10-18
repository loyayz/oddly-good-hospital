class_name HospitalDepartments
extends RefCounted

var content: HospitalContent
var space: HospitalSpace
var clinic: RefCounted
var waiting_life: RefCounted
var environment: RefCounted
var _worked: Dictionary = {}
var _pruned_boundary: Array = []

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry

func ensure(world: WorldState) -> void:
	if not world.facts.has("departments"):
		world.facts.departments = {"units":{},"room_focus":{},"routes":{},"guidance":{},"experience":{},"cases":[],"staff_jobs":{},"staff_consumed":{},"staff_days":{}}
	var state: Dictionary = world.facts.departments
	if state.units.is_empty():
		var rooms: Array = []
		var shared: Array = []
		for room_id: String in world.ids("rooms"):
			var kind: String = str(world.facts.rooms[room_id].get("kind",""))
			if kind in ["rest","staff_garden","doctor_office","research","workshop","toilet"]: continue
			if kind in ["ward","operating_room","diagnosis"]: shared.append(room_id)
			else: rooms.append(room_id)
		var entry: Dictionary = {"floor_id":1,"cell":[48,93]}
		if world.facts.facilities.has("reception_desk"):
			entry = {"floor_id":world.facts.facilities.reception_desk.floor_id,"cell":world.facts.facilities.reception_desk.patient_cell.duplicate()}
		state.units.general = {"id":"general","name":"综合诊疗科","room_ids":rooms,"shared_room_ids":shared,"public_cells":[],"entry":entry,"focus_id":"","focus_ready_tick":0,"intake_disease_ids":[],"open":true}
	for id: String in state.units: world.department_changed(id,true)
	for visit_id: String in world.active_visit_ids():
		if not state.experience.has(visit_id):
			var visit: Dictionary = world.facts.visits[visit_id]
			if visit.phase=="departed": continue
			state.experience[visit_id] = {"visit_id":visit_id,"arrival_tick":int(visit.get("arrival_tick",world.sim_tick)),"phase":visit.phase,"phase_started_tick":world.sim_tick,
				"phase_totals":{},"details":[],"early_details_merged":false,"retired_tickets":{},"excess_wait_ticks":0,"environment_total":0.0,"environment_ticks":0,
				"helps":{},"unhandled":{},"wrong_entries":{},"broken_promises":{},"started_services":{},"completed_services":{},"staff_ids":[],"final_department_id":"",
				"cause_clocks":{},"anger_sources":{},"next_anger_tick":world.sim_tick+_ticks(content.balance.anger.update_seconds),"last_progress_tick":world.sim_tick,"closed_tick":-1}

func execute(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	ensure(world)
	if kind=="department_create" or kind=="department_configure": return _configure(world,payload,kind=="department_create")
	var id: String = str(payload.get("department_id",""))
	if not world.facts.departments.units.has(id): return _result(world,false,"department_missing","原科室不存在")
	var department: Dictionary = world.facts.departments.units[id]
	if kind=="department_rename":
		var label: String = str(payload.get("name","")).strip_edges()
		if label.is_empty() or label.length()>40: return _result(world,false,"invalid_name","科室名称须为1至40字")
		department.name = label
		return _result(world,true,"applied","",[id])
	if kind=="department_set_open":
		if not payload.get("open") is bool: return _result(world,false,"invalid_payload","缺少接诊意愿")
		department.open = payload.open
		return _result(world,true,"applied","",[id])
	if kind=="department_set_focus":
		return _set_focus(world,department,str(payload.get("focus_id","")))
	return _result(world,false,"unknown_command","未知科室操作")

func dispatch(world: WorldState) -> void:
	ensure(world)
	_worked.clear()
	for visit_id: String in world.facts.departments.guidance.keys():
		var job: Dictionary = world.facts.departments.guidance[visit_id]
		if job.phase=="travel":
			var actor: Dictionary = world.facts.actors[world.facts.visits[visit_id].actor_id]
			var nurse_id: String = job.staff_ids[0]
			if actor.location.kind!="floor" or world.facts.moves.has(nurse_id): continue
			var bedside: Array = _guide_position(world,visit_id,nurse_id)
			if bedside.is_empty(): continue
			if not space.at(world,nurse_id,int(actor.location.floor_id),bedside):
				space.request_move(world,nurse_id,int(actor.location.floor_id),bedside)
			else:
				job.phase = "working"
				job.remaining_ticks = _ticks(content.balance.guidance.nurse_seconds if job.kind=="nurse" else content.balance.guidance.doctor_redirect_seconds)

func advance(world: WorldState) -> void:
	for visit_id: String in world.facts.get("departments",{}).get("guidance",{}).keys():
		var job: Dictionary = world.facts.departments.guidance[visit_id]
		if job.phase!="working": continue
		for staff_id: String in job.staff_ids: _worked[staff_id] = true
		job.remaining_ticks -= 1
		if int(job.remaining_ticks)>0: continue
		var route: Dictionary = world.facts.departments.routes[visit_id]
		var nurse_id: String = job.staff_ids[0]
		if job.kind=="doctor":
			_correct(world,visit_id,"doctor")
			continue
		var corrected: bool = world.draw("registration",10000)<floori(float(content.balance.guidance.nurse_correction_probability)*10000)
		_record_staff_job(world,{"id":job.id,"staff_id":nurse_id,"visit_id":visit_id,"kind":"guidance","tick":world.sim_tick,"success":corrected})
		route.nurse_attempted = true
		if corrected:
			_record_help(world,visit_id,nurse_id,job.id,"guidance")
			var staff: Dictionary = world.facts.staff[nurse_id]
			if not staff.completed_jobs.has(job.id):
				staff.completed_jobs[job.id] = "care"
				staff.practice.care = mini(int(content.balance.clinical_ability_growth.practice_total_cap),int(staff.practice.care)+1)
			_correct(world,visit_id,"nurse")
		else:
			if world.facts.staff[nurse_id].get("active_job_id","")==job.id: world.facts.staff[nurse_id].active_job_id = ""
			world.facts.departments.guidance.erase(visit_id)
			world.facts.tickets[world.facts.visits[visit_id].ticket_id].pause_reasons.erase("guidance")

func worked_staff() -> Dictionary:
	return _worked.duplicate()

func sample(world: WorldState) -> void:
	ensure(world)
	if environment!=null: environment.begin_query(world)
	for visit_id: String in world.active_visit_ids():
		var visit: Dictionary = world.facts.visits[visit_id]
		if not world.facts.departments.experience.has(visit_id): continue
		var experience: Dictionary = world.facts.departments.experience[visit_id]
		if int(experience.closed_tick)>=0: continue
		_track_phase(world,visit,experience)
		var actor: Dictionary = world.facts.actors[visit.actor_id]
		var observation: Dictionary = {}
		if actor.location.kind=="floor":
			observation = _environment(world,visit.actor_id,int(actor.location.floor_id),actor.location.cell)
			experience.environment_total += float(observation.value)
			experience.environment_ticks += 1
			_update_cause_clocks(world,visit,experience,observation)
		if world.sim_tick>=int(experience.next_anger_tick):
			experience.next_anger_tick = world.sim_tick+_ticks(content.balance.anger.update_seconds)
			_sample_anger(world,visit,experience,observation)
			var reasons: Array = reason_cards(world,visit_id)
			if not reasons.is_empty(): _detail(world,experience,{"kind":"cause","tick":world.sim_tick,"cause_id":reasons[0].id,"text":reasons[0].reason})
	if environment!=null: environment.end_query()
	for staff_id: String in world.ids("staff"):
		var day_key: String = str(world.sim_tick/WorldState.TICKS_PER_DAY)
		if not world.facts.departments.staff_days.has(day_key): world.facts.departments.staff_days[day_key] = {}
		var days: Dictionary = world.facts.departments.staff_days[day_key]
		if not days.has(staff_id): days[staff_id] = {"energy_total":0.0,"ticks":0,"rest_ticks":0,"required_rest_ticks":0}
		var daily: Dictionary = days[staff_id]
		daily.energy_total += float(world.facts.staff[staff_id].energy)
		daily.ticks += 1
		var task: Dictionary = world.facts.staff[staff_id].get("life_task",{})
		if task.get("phase","") in ["rest","sleep","offsite"]: daily.rest_ticks += 1
		if not world.facts.staff[staff_id].get("on_shift",false) or float(world.facts.staff[staff_id].energy)<=35.0: daily.required_rest_ticks += 1

func settle(world: WorldState) -> void:
	ensure(world)
	for visit_id: String in world.active_visit_ids():
		var visit: Dictionary = world.facts.visits[visit_id]
		if not world.facts.departments.experience.has(visit_id): continue
		var experience: Dictionary = world.facts.departments.experience[visit_id]
		if visit.phase=="departed" and int(experience.closed_tick)<0:
			_track_phase(world,visit,experience)
			experience.closed_tick = world.sim_tick
			experience.final_score = patient_rating(world,visit_id)
			experience.final_result = visit.final_result
			experience.final_department_name = str(world.facts.departments.units.get(experience.final_department_id,{}).get("name","未进入治疗科室"))
			experience.staff_names = {}
			for staff_id: String in experience.staff_ids: experience.staff_names[staff_id] = world.facts.actors[staff_id].name
			experience.charges = _charges(world,visit)
			world.facts.departments.cases.append({"visit_id":visit_id,"tick":world.sim_tick,"day":world.sim_tick/WorldState.TICKS_PER_DAY,"department_id":experience.final_department_id,
				"result":visit.final_result,"treated":not visit.attempt_ids.is_empty(),"rating":experience.final_score.duplicate(true)})
	for source: String in ["environment","maintenance"]:
		for receipt_id: String in world.completion_receipt_ids(source):
			var receipt: Dictionary = world.facts.get(source,{}).get("receipts",{}).get(receipt_id,{})
			if receipt.is_empty() or int(receipt.tick)/WorldState.TICKS_PER_DAY<maxi(0,world.sim_tick/WorldState.TICKS_PER_DAY-int(content.balance.ratings.window_days)): continue
			if world.facts.departments.staff_consumed.has(str(receipt.get("staff_id",""))+":"+str(receipt.id)): continue
			if world.facts.staff.has(receipt.get("staff_id","")):
				var job: Dictionary = receipt.duplicate(true)
				job.success = true
				_record_staff_job(world,job)
	_prune(world)

func service_started(world: WorldState, session: Dictionary) -> void:
	ensure(world)
	var experience: Dictionary = world.facts.departments.experience[session.visit_id]
	if experience.started_services.has(session.id): return
	experience.started_services[session.id] = {"kind":session.kind,"tick":world.sim_tick,"facility_id":session.facility_id,"staff_ids":session.staff_ids.duplicate()}
	var visit: Dictionary = world.facts.visits[session.visit_id]
	retire_ticket(world,session.visit_id)
	for staff_id: String in session.staff_ids:
		if not staff_id in experience.staff_ids: experience.staff_ids.append(staff_id)
	if session.kind in ["outpatient","surgery"]:
		experience.final_department_id = str(visit.get("department_id","general"))
	var stage_key: String = str(session.kind)+":"+str(session.get("attempt_id",""))
	if not experience.get("service_relief",{}).has(stage_key):
		if not experience.has("service_relief"): experience.service_relief = {}
		experience.service_relief[stage_key] = true
		_anger_change(visit,experience,"clinical_service",-float(content.balance.anger.new_service_relief))
	experience.last_progress_tick = world.sim_tick

func service_completed(world: WorldState, session: Dictionary) -> void:
	ensure(world)
	var experience: Dictionary = world.facts.departments.experience[session.visit_id]
	if experience.completed_services.has(session.id): return
	experience.completed_services[session.id] = {"kind":session.kind,"tick":world.sim_tick,"staff_ids":session.staff_ids.duplicate(),"facility_id":session.facility_id,"attempt_id":session.get("attempt_id","")}
	experience.last_progress_tick = world.sim_tick
	for staff_id: String in session.staff_ids:
		var success: bool = true
		if session.kind=="outpatient": success = bool(world.facts.attempts[session.attempt_id].result)
		_record_staff_job(world,{"id":session.id,"staff_id":staff_id,"visit_id":session.visit_id,"kind":session.kind,"tick":world.sim_tick,"success":success,"attempt_id":session.get("attempt_id","")})
		if session.kind=="care": _record_help(world,session.visit_id,staff_id,session.id,"care")

func retire_ticket(world: WorldState, visit_id: String) -> void:
	ensure(world)
	var visit: Dictionary = world.facts.visits[visit_id]
	var data: Dictionary = world.facts.departments.experience.get(visit_id,{})
	var ticket: Dictionary = world.facts.tickets.get(visit.get("ticket_id",""),{})
	if data.is_empty() or ticket.is_empty() or data.retired_tickets.has(ticket.id): return
	data.retired_tickets[ticket.id] = true
	data.excess_wait_ticks += maxi(0,int(ticket.get("waited_ticks",0))-_grace_ticks(str(ticket.kind)))

func route_patient(world: WorldState, visit_id: String) -> bool:
	ensure(world)
	var visit: Dictionary = world.facts.visits[visit_id]
	var units: Dictionary = world.facts.departments.units
	var readiness_by_department: Dictionary = {}
	if not world.facts.departments.routes.has(visit_id):
		var correct: Array = []
		var wrong: Array = []
		for id: String in _sorted(units):
			var readiness: Dictionary = readiness(world,id,visit_id,true)
			readiness_by_department[id] = readiness
			if not readiness.reachable or not units[id].open: continue
			if readiness.structurally_compatible: correct.append(id)
			elif readiness.reason_id in content.balance.guidance.wrong_destination_reason_ids and _serves_other_case(world,units[id]): wrong.append(id)
		if correct.is_empty():
			visit.waiting_reason = "没有具备本病例完整路线的开放科室"
			return false
		var selected: String = correct[0]
		var error_rolled: bool = false
		if not wrong.is_empty() and correct.size()+wrong.size()>=2:
			var probability: float = float(content.balance.guidance.regular_error_probability if visit.get("returning_resident",false) else content.balance.guidance.first_visit_error_probability)
			if _has_guide_screen(world,units[selected],visit): probability = maxf(0.0,probability-float(content.balance.guidance.sign_reduction))
			error_rolled = world.draw("registration",10000)<floori(probability*10000)
			if error_rolled: selected = wrong[0]
		world.facts.departments.routes[visit_id] = {"visit_id":visit_id,"registration_choice":selected,"correct_department_id":correct[0],"error_rolled":error_rolled,"corrected":false,"nurse_attempted":false,"started_tick":world.sim_tick,"actual_mismatched_entry_arrival":{},"correction_source":""}
		visit.department_id = selected
	var route: Dictionary = world.facts.departments.routes[visit_id]
	var current: Dictionary = readiness_by_department.get(str(visit.department_id),{})
	if current.is_empty(): current = readiness(world,str(visit.department_id),visit_id,true)
	if current.structurally_compatible:
		if world.facts.departments.guidance.get(visit_id,{}).get("phase","")=="working": return false
		if route.error_rolled and not route.corrected: _correct(world,visit_id,"capacity_recheck",str(visit.department_id))
		return true
	var targets: Array = eligible_departments(world,visit_id,true,readiness_by_department)
	if targets.is_empty():
		visit.waiting_reason = "正确科室临时不可用，保留票号等待合格窗口"
		return false
	route.correct_department_id = targets[0].id
	if route.corrected:
		visit.department_id = route.correct_department_id
		return true
	if world.facts.departments.guidance.has(visit_id):
		visit.waiting_reason = "导诊护士正在核对去向，保留原票号"
		return false
	if not route.nurse_attempted and _start_guidance(world,visit_id): return false
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	var department: Dictionary = units.get(str(visit.department_id),{})
	if department.is_empty():
		_correct(world,visit_id,"route_recheck")
		return true
	if actor.location.kind!="floor" or world.facts.moves.has(actor.id): return false
	if not space.at(world,actor.id,int(department.entry.floor_id),department.entry.cell):
		visit.waiting_reason = space.request_move(world,actor.id,int(department.entry.floor_id),department.entry.cell)
		return false
	if route.actual_mismatched_entry_arrival.is_empty():
		route.actual_mismatched_entry_arrival = {"id":visit_id+":mismatched_entry","tick":world.sim_tick,"department_id":department.id,"department_name":department.name}
		var experience: Dictionary = world.facts.departments.experience[visit_id]
		experience.wrong_entries[route.actual_mismatched_entry_arrival.id] = route.actual_mismatched_entry_arrival.duplicate(true)
		_anger_change(visit,experience,"wrong_department",_cause("wrong_department").one_shot)
		route.arrived_tick = world.sim_tick
	var waited: int = world.sim_tick-int(route.arrived_tick)
	var doctor_id: String = _available_doctor(world,department)
	if not doctor_id.is_empty():
		_start_guide_job(world,visit_id,doctor_id,"doctor")
		return false
	elif waited>=_ticks(content.balance.guidance.self_service_after_seconds):
		_correct(world,visit_id,"self_service")
		return true
	visit.waiting_reason = "等待导诊核对" if waited<_ticks(content.balance.guidance.help_after_seconds) else "已请求导诊，保留原号；可沿公共路线自助纠正"
	return false

func readiness(world: WorldState, department_id: String, visit_id: String, structural_only: bool = false) -> Dictionary:
	var department: Dictionary = world.facts.get("departments",{}).get("units",{}).get(department_id,{})
	var visit: Dictionary = world.facts.visits.get(visit_id,{})
	if department.is_empty() or visit.is_empty(): return {"ok":false,"reachable":false,"structurally_compatible":false,"reason_id":"department_missing","reason":"科室或就诊不存在"}
	var route: Dictionary = space.route(world,visit.actor_id,int(department.entry.floor_id),department.entry.cell)
	if not route.ok: return {"ok":false,"reachable":false,"structurally_compatible":false,"reason_id":"traversal","reason":route.reason}
	if not department.intake_disease_ids.is_empty() and not visit.disease_id in department.intake_disease_ids:
		return {"ok":false,"reachable":true,"structurally_compatible":false,"reason_id":"intake_scope_excludes_case","reason":"接诊范围明确排除本病例"}
	var binding: Dictionary = content.definition("treatment_bindings",visit.binding_id)
	var routine: Dictionary = content.definition("treatment_routines",binding.get("routine_id",""))
	var equipment: bool = false
	for facility_id: String in world.facility_ids(str(routine.get("equipment_id",""))):
		if _belongs(department,world.facts.facilities[facility_id]): equipment = true
	var surgery_equipment: bool = false
	for facility_id: String in world.facility_ids("EQ01"):
		if _belongs(department,world.facts.facilities[facility_id]): surgery_equipment = true
	var unlocked: bool = false
	for plan: Dictionary in content.catalog.treatment_plans:
		if plan.disease_id!=visit.disease_id: continue
		var allowed: bool = true
		for research_id: String in plan.requires_research:
			if not research_id in world.facts.research: allowed = false
		var protocol: Dictionary = content.definition("treatment_protocols",plan.protocol_id)
		if allowed and (equipment if protocol.kind=="outpatient" else surgery_equipment): unlocked = true
	if not unlocked: return {"ok":false,"reachable":true,"structurally_compatible":false,"reason_id":"equipment_has_no_unlocked_plan","reason":"实际设备没有对应已解锁方案"}
	var quotes: Array = []
	if clinic!=null and clinic.has_method("compare_plans"):
		var facts: Dictionary = world.facts.duplicate()
		facts.visits = world.facts.visits.duplicate()
		facts.visits[visit_id] = visit.duplicate(true)
		var candidate: WorldState = WorldState.new(facts)
		candidate.facts.visits[visit_id].department_id = department_id
		space.begin_route_query(candidate)
		if structural_only:
			for plan: Dictionary in content.catalog.treatment_plans:
				if plan.disease_id!=visit.disease_id: continue
				var quote: Dictionary = clinic.plan_quote(candidate,visit_id,plan.id,{"structural_only":true,"ignore_supplies":true})
				quotes.append(quote)
				if quote.get("structural_ok",quote.get("ok",false)): break
		else: quotes = clinic.compare_plans(candidate,visit_id)
		space.end_route_query()
	var ready: bool = false
	var structurally_compatible: bool = clinic==null
	for quote: Dictionary in quotes:
		if quote.get("ok",false): ready = true
		if quote.get("structural_ok",quote.get("ok",false)): structurally_compatible = true
	return {"ok":department.open and ready,"reachable":true,"structurally_compatible":structurally_compatible,"reason_id":"" if ready else "clinical_readiness","reason":"" if ready else "等待本病例实际岗位、设备、床位与物资就绪","plans":quotes,"department_id":department_id,"entry":department.entry.duplicate(true)}

func eligible_departments(world: WorldState, visit_id: String, structural_only: bool = false, observed: Dictionary = {}) -> Array:
	var values: Array = []
	for id: String in _sorted(world.facts.get("departments",{}).get("units",{})):
		var department: Dictionary = world.facts.departments.units[id]
		if not department.open: continue
		var status: Dictionary = observed.get(id,{})
		if status.is_empty(): status = readiness(world,id,visit_id,structural_only)
		if department.open and status.reachable and status.structurally_compatible:
			values.append({"id":id,"name":department.name,"status":status})
	return values

func focus_multiplier(world: WorldState, visit_id: String, staff_id: String, track: String) -> float:
	var visit: Dictionary = world.facts.visits[visit_id]
	var id: String = str(visit.get("department_id","general"))
	var unit: Dictionary = world.facts.get("departments",{}).get("units",{}).get(id,{})
	if unit.is_empty() or str(unit.focus_id).is_empty() or world.sim_tick<int(unit.focus_ready_tick) or int(world.facts.staff[staff_id].abilities.get(track,0))<int(content.balance.care_departments.focus_min_ability): return 1.0
	var routine: Dictionary = content.definition("treatment_routines",content.definition("treatment_bindings",visit.binding_id).routine_id)
	if routine.get("specialty_id","")!=unit.focus_id: return 1.0
	var rating: Dictionary = aggregate_rating(world,id)
	return float(content.balance.care_departments.focus_work_multiplier) if int(rating.samples)>=int(content.balance.care_departments.focus_min_cases) and rating.score!=null and float(rating.score)>=float(content.balance.care_departments.focus_min_score) else 1.0

func patient_rating(world: WorldState, visit_id: String) -> Dictionary:
	var visit: Dictionary = world.facts.visits[visit_id]
	var data: Dictionary = world.facts.get("departments",{}).get("experience",{}).get(visit_id,{})
	if data.is_empty(): return {"score":null,"samples":0,"status":"积累评价中","parts":{}}
	if int(data.closed_tick)>=0 and data.has("final_score"): return data.final_score.duplicate(true)
	var parts: Dictionary = {}
	var outcome: Variant = null
	if visit.phase in ["leaving","departed"]:
		if visit.final_result=="cured": outcome = content.balance.ratings.outcome_scores.cured
		elif visit.final_result in ["abandoned","abandoned_wait","wait_departure"]: outcome = 50
		elif visit.attempt_ids.size()>=int(content.balance.max_treatment_attempts): outcome = content.balance.ratings.outcome_scores.failed_after_attempts
		else: outcome = content.balance.ratings.outcome_scores.safe_referral
	if outcome!=null: parts.outcome = float(outcome)
	var excess: int = int(data.excess_wait_ticks)
	var ticket: Dictionary = world.facts.tickets.get(visit.get("ticket_id",""),{})
	if not ticket.is_empty() and not data.retired_tickets.has(ticket.id): excess += maxi(0,int(ticket.get("waited_ticks",0))-_grace_ticks(str(ticket.kind)))
	parts.flow = clampf(100.0-float(excess)*WorldState.TICK_SECONDS/float(content.balance.ratings.flow_seconds_per_point)-data.wrong_entries.size()*float(content.balance.ratings.wrong_department_penalty)-data.broken_promises.size()*float(content.balance.ratings.broken_promise_penalty),0.0,100.0)
	parts.care = clampf(float(content.balance.ratings.care_base)+data.helps.size()*float(content.balance.ratings.care_help_bonus)-data.unhandled.size()*float(content.balance.ratings.care_unhandled_penalty),0.0,100.0)
	if int(data.environment_ticks)>0: parts.environment = float(data.environment_total)/float(data.environment_ticks)
	return {"score":_weighted(parts,content.balance.ratings.weights.patient),"samples":1,"parts":parts,"status":"已离院" if visit.phase=="departed" else "进行中"}

func aggregate_rating(world: WorldState, department_id: String = "") -> Dictionary:
	var cases: Array = _window_cases(world,department_id)
	var totals: Dictionary = {}
	var counts: Dictionary = {}
	var treated: int = 0
	var cured: int = 0
	for record: Dictionary in cases:
		for part: String in record.rating.parts:
			totals[part] = float(totals.get(part,0.0))+float(record.rating.parts[part])
			counts[part] = int(counts.get(part,0))+1
		totals.patient = float(totals.get("patient",0))+float(record.rating.score)
		if record.treated:
			treated += 1
			if record.result=="cured": cured += 1
	var parts: Dictionary = {}
	if not cases.is_empty(): parts.patient = float(totals.patient)/cases.size()
	for key: String in ["flow","environment"]:
		if counts.has(key): parts[key] = float(totals[key])/int(counts[key])
	if treated>0: parts.clinical = float(cured+int(content.balance.ratings.clinical_prior_success))/float(treated+int(content.balance.ratings.clinical_prior_total))*100.0
	if department_id.is_empty():
		var experience: Variant = _staff_experience(world)
		if experience!=null: parts.staff_experience = experience
	var weights: Dictionary = content.balance.ratings.weights.hospital if department_id.is_empty() else content.balance.ratings.weights.care_department
	var score: Variant = _weighted(parts,weights)
	return {"score":score,"parts":parts,"samples":cases.size(),"stars":_stars(score) if cases.size()>=int(content.balance.ratings.minimum_samples) and score!=null else null,"window_days":int(content.balance.ratings.window_days),"status":"积累评价中" if cases.is_empty() else "已结算医院日"}

func staff_rating(world: WorldState, staff_id: String) -> Dictionary:
	var jobs: Array = world.facts.get("departments",{}).get("staff_jobs",{}).get(staff_id,[])
	var total: int = 0
	var successful: int = 0
	var feedback: Array = []
	var visited: Dictionary = {}
	var first_day: int = maxi(0,world.sim_tick/WorldState.TICKS_PER_DAY-int(content.balance.ratings.window_days))
	for job: Dictionary in jobs:
		if int(job.tick)/WorldState.TICKS_PER_DAY<first_day: continue
		total += 1
		if job.success: successful += 1
		var visit_id: String = str(job.get("visit_id",""))
		if not visit_id.is_empty() and not visited.has(visit_id):
			visited[visit_id] = true
			var data: Dictionary = world.facts.departments.experience.get(visit_id,{})
			if not data.is_empty():
				var helped: int = 0
				var unhandled: int = 0
				for source: Dictionary in data.helps.values():
					if source.get("staff_id","")==staff_id: helped += 1
				for source: Dictionary in data.unhandled.values():
					if source.get("staff_id","")==staff_id: unhandled += 1
				feedback.append(clampf(80.0+5.0*helped-10.0*unhandled,0.0,100.0))
	var parts: Dictionary = {}
	if total>0:
		if world.facts.staff.get(staff_id,{}).get("role","")=="doctor":
			var outcomes: Array = []
			for record: Dictionary in _window_cases(world,""):
				var case_visit: Dictionary = world.facts.visits[record.visit_id]
				for attempt_id: String in case_visit.attempt_ids:
					if staff_id in world.facts.attempts[attempt_id].staff_ids: outcomes.append(bool(world.facts.attempts[attempt_id].result))
			if not outcomes.is_empty():
				var cures: int = outcomes.count(true)
				parts.quality = float(cures+int(content.balance.ratings.clinical_prior_success))/float(outcomes.size()+int(content.balance.ratings.clinical_prior_total))*100.0
		else:
			parts.quality = float(successful+int(content.balance.ratings.job_prior_success))/float(total+int(content.balance.ratings.job_prior_total))*100.0
	if not feedback.is_empty(): parts.personal_feedback = _mean(feedback)
	var staff: Dictionary = world.facts.staff.get(staff_id,{})
	var weights: Dictionary = content.balance.ratings.weights.doctor if staff.get("role","")=="doctor" else content.balance.ratings.weights.staff
	var score: Variant = _weighted(parts,weights)
	return {"score":score,"parts":parts,"samples":total,"stars":_stars(score) if score!=null and total>=int(content.balance.ratings.minimum_samples) else null,"status":"积累评价中" if total==0 else "最近实际完成任务"}

func reason_cards(world: WorldState, visit_id: String) -> Array:
	var visit: Dictionary = world.facts.visits.get(visit_id,{})
	if visit.is_empty() or visit.phase in ["departed","leaving"]: return []
	var reason: String = str(visit.get("waiting_reason",""))
	var ids: Array = []
	var need: Dictionary = world.facts.get("waiting_life",{}).get("needs",{}).get(visit_id,{})
	if not need.is_empty(): ids.append("JC06")
	if visit.phase=="round_wait": ids.append("JC08")
	if "治疗包" in reason or "耗材" in reason: ids.append("JC09")
	if "床" in reason or "护理覆盖" in reason: ids.append("JC04")
	if "故障" in reason or "检修" in reason or "设备暂停" in reason: ids.append("JC02")
	if "路线" in reason or "通路" in reason or "展开" in reason or "身体" in reason or "墙" in reason: ids.append("JC03")
	if "职员" in reason or "当班" in reason or "资格" in reason or "医生" in reason or "护士" in reason: ids.append("JC01")
	if world.facts.get("incidents",{}).get(visit.actor_id,{})!={}: ids.append("JC07")
	if ids.is_empty() and world.facts.tickets.has(visit.get("ticket_id","")): ids.append("JC05")
	var cards: Array = []
	for id: String in ids:
		var definition: Dictionary = content.definition("journey_reason_cards",id)
		var card: Dictionary = definition.duplicate(true)
		card.visit_id = visit_id
		card.reason = reason if not reason.is_empty() else definition.name
		card.ticket_id = str(visit.get("ticket_id",""))
		card.actor_id = visit.actor_id
		cards.append(card)
	return cards

func hospital_reasons(world: WorldState) -> Array:
	var grouped: Dictionary = {}
	for visit_id: String in world.active_visit_ids():
		for card: Dictionary in reason_cards(world,visit_id):
			if not grouped.has(card.id): grouped[card.id] = {"id":card.id,"name":card.name,"target_panel":card.target_panel,"visit_ids":[],"reason":card.reason}
			grouped[card.id].visit_ids.append(visit_id)
	var cards: Array = []
	for id: String in _sorted(grouped): cards.append(grouped[id])
	return cards

func receipt(world: WorldState, visit_id: String) -> Dictionary:
	var visit: Dictionary = world.facts.visits.get(visit_id,{})
	var data: Dictionary = world.facts.get("departments",{}).get("experience",{}).get(visit_id,{})
	if visit.is_empty() or data.is_empty(): return {}
	var result: Dictionary = {"visit_id":visit_id,"actor_name":world.facts.actors[visit.actor_id].name,"phase":visit.phase,"phase_totals":data.phase_totals.duplicate(true),"details":data.details.duplicate(true),"early_details_merged":data.early_details_merged,"rating":patient_rating(world,visit_id),"reasons":reason_cards(world,visit_id),"closed_tick":data.closed_tick}
	if int(data.closed_tick)>=0:
		result.merge({"result":data.final_result,"department_name":data.final_department_name,"staff_names":data.staff_names.duplicate(true),"charges":data.charges.duplicate(true)},true)
	else:
		result.phase_totals[data.phase] = int(result.phase_totals.get(data.phase,0))+maxi(0,world.sim_tick-int(data.phase_started_tick))
		result.charges = _charges(world,visit)
	return result

func summary(world: WorldState, department_id: String = "") -> Dictionary:
	var units: Array = []
	var queued_by_department: Dictionary = {}
	for visit: Dictionary in world.facts.visits.values():
		if not world.facts.tickets.has(visit.get("ticket_id","")): continue
		var id: String = str(visit.get("department_id","general"))
		if not queued_by_department.has(id): queued_by_department[id] = []
		queued_by_department[id].append(visit.id)
	for id: String in _sorted(world.facts.get("departments",{}).get("units",{})):
		if not department_id.is_empty() and id!=department_id: continue
		var unit: Dictionary = world.facts.departments.units[id]
		var queued: Array = queued_by_department.get(id,[])
		units.append({"id":id,"name":unit.name,"room_ids":unit.room_ids.duplicate(),"shared_room_ids":unit.shared_room_ids.duplicate(),"entry":unit.entry.duplicate(true),"focus_id":unit.focus_id,"focus_remaining_ticks":maxi(0,int(unit.focus_ready_tick)-world.sim_tick),"open":unit.open,"intake_disease_ids":unit.intake_disease_ids.duplicate(),"queued_visit_ids":queued,"rating":aggregate_rating(world,id)})
	return {"units":units,"hospital_rating":aggregate_rating(world),"reasons":hospital_reasons(world)}

func patient_summary(world: WorldState, visit_id: String) -> Dictionary:
	var visit: Dictionary = world.facts.visits.get(visit_id,{})
	if visit.is_empty(): return {}
	var data: Dictionary = world.facts.get("departments",{}).get("experience",{}).get(visit_id,{})
	var anger: float = float(visit.anger)
	var thresholds: Array = content.balance.anger.thresholds
	return {"personality_id":visit.personality_id,"anger":anger,"mood":clampf(100.0-anger,0.0,100.0),"expression":"平静" if anger<float(thresholds[0]) else "烦躁" if anger<float(thresholds[1]) else "生气" if anger<float(thresholds[2]) else "请求帮助","anger_sources":data.get("anger_sources",{}).duplicate(true),"rating":patient_rating(world,visit_id),"reasons":reason_cards(world,visit_id),"department_id":visit.get("department_id",""),"route":world.facts.get("departments",{}).get("routes",{}).get(visit_id,{}).duplicate(true)}

func validate(world: WorldState) -> String:
	var state: Variant = world.facts.get("departments")
	if not state is Dictionary or not world.facts.get("floors") is Dictionary or not world.facts.floors.get("overrides") is Dictionary or not world.facts.get("rooms") is Dictionary or not world.facts.get("visits") is Dictionary or not world.facts.get("staff") is Dictionary: return "缺少科室与体验事实"
	for collection: String in ["units","room_focus","routes","guidance","experience","staff_jobs","staff_consumed","staff_days"]:
		if not state.get(collection) is Dictionary: return "科室体验集合无效："+collection
	if not state.get("cases") is Array: return "科室评分窗口无效"
	var rooms: Dictionary = {}
	for id: Variant in state.units:
		var unit: Variant = state.units[id]
		if not (id is String or id is StringName): return "科室定义键类型无效"
		if not unit is Dictionary: return "科室定义记录类型无效"
		if not unit.get("id") is String or str(unit.get("id"))!=str(id): return "科室定义身份无效"
		if not unit.get("name") is String or not unit.get("open") is bool: return "科室名称或开放状态类型无效"
		if not unit.get("room_ids") is Array or not unit.get("shared_room_ids") is Array or not unit.get("intake_disease_ids") is Array or not unit.get("public_cells") is Array: return "科室成员集合类型无效"
		if not unit.get("focus_id","") is String or not _natural(unit.get("focus_ready_tick")): return "科室专业或生效时间类型无效"
		if not _entry_shape(unit.get("entry")) or not world.facts.floors.overrides.has(str(int(unit.entry.floor_id))): return "科室入口无效"
		if unit.get("focus_id","")!="" and content.definition("specialties",unit.focus_id).is_empty(): return "科室专业引用无效"
		for room_id: Variant in unit.room_ids:
			if not room_id is String or not world.facts.rooms.has(room_id) or rooms.has(room_id): return "科室房间引用或唯一归属无效"
			rooms[room_id] = str(id)
		for room_id: Variant in unit.shared_room_ids:
			if not room_id is String or not world.facts.rooms.has(room_id): return "科室共享房间引用无效"
		for disease_id: Variant in unit.intake_disease_ids:
			if not disease_id is String or content.definition("diseases",disease_id).is_empty(): return "科室接诊范围无效"
	for visit_id: Variant in state.routes:
		var route: Variant = state.routes[visit_id]
		if not visit_id is String or not world.facts.visits.has(visit_id) or not world.facts.visits[visit_id] is Dictionary or not route is Dictionary or not route.get("registration_choice") is String or not route.get("correct_department_id") is String or not route.get("error_rolled") is bool or not route.get("corrected") is bool or not route.get("actual_mismatched_entry_arrival") is Dictionary or not state.units.has(route.registration_choice) or not state.units.has(route.correct_department_id): return "挂号路线与科室引用无效"
	var staff_locks: Dictionary = {}
	for visit_id: Variant in state.guidance:
		var job: Variant = state.guidance[visit_id]
		if not visit_id is String or not world.facts.visits.has(visit_id) or not state.routes.has(visit_id) or not job is Dictionary or not job.get("phase") is String or not job.get("phase") in ["travel","working"] or not job.get("kind") is String or not job.get("kind") in ["nurse","doctor"] or not job.get("id") is String or not job.get("staff_ids") is Array or job.staff_ids.size()!=1 or not _natural(job.get("remaining_ticks")): return "导诊工作无效"
		for staff_id: Variant in job.staff_ids:
			if not staff_id is String or not world.facts.staff.has(staff_id) or not world.facts.staff[staff_id] is Dictionary or staff_locks.has(staff_id) or world.facts.staff[staff_id].get("active_job_id","")!=job.get("id",""): return "导诊岗位重复或缺失"
			staff_locks[staff_id] = true
	for visit_id: Variant in state.experience:
		var data: Variant = state.experience[visit_id]
		if not visit_id is String or not world.facts.visits.has(visit_id) or not data is Dictionary or not data.get("details") is Array or data.details.size()>int(content.balance.journey_review.details_per_visit) or not data.get("phase_totals") is Dictionary or not _natural(data.get("environment_ticks")) or not _natural(data.get("excess_wait_ticks")): return "就诊体验进度无效"
		for field: String in ["helps","unhandled","wrong_entries","broken_promises","started_services","completed_services","cause_clocks","anger_sources","retired_tickets"]:
			if not data.get(field) is Dictionary: return "体验来源集合无效："+field
	for staff_id: Variant in state.staff_jobs:
		if not staff_id is String or not world.facts.staff.has(staff_id) or not world.facts.staff[staff_id] is Dictionary or not state.staff_jobs[staff_id] is Array or state.staff_jobs[staff_id].size()>int(content.balance.ratings.staff_job_limit): return "员工评价窗口引用无效"
		for record: Variant in state.staff_jobs[staff_id]:
			if not record is Dictionary: return "员工评价窗口记录无效"
	var cases: Dictionary = {}
	for record: Variant in state.cases:
		if not record is Dictionary or not record.get("visit_id") is String or not world.facts.visits.has(record.get("visit_id","")) or cases.has(record.visit_id) or not _natural(record.get("tick")) or not _natural(record.get("day")) or not record.get("treated") is bool or not record.get("rating") is Dictionary or not record.get("department_id","") is String: return "科室病例评分窗口无效"
		if record.get("department_id","")!="" and not state.units.has(record.department_id): return "最终治疗科室引用无效"
		cases[record.visit_id] = true
	return ""

func _configure(world: WorldState, payload: Dictionary, create: bool) -> CommandResult:
	var id: String = str(payload.get("department_id",""))
	if not create and not world.facts.departments.units.has(id): return _result(world,false,"department_missing","原科室不存在")
	if create and not id.is_empty() and world.facts.departments.units.has(id): return _result(world,false,"department_exists","科室身份已经存在")
	var old: Dictionary = world.facts.departments.units.get(id,{})
	var rooms: Variant = payload.get("room_ids",old.get("room_ids",[]))
	var shared: Variant = payload.get("shared_room_ids",old.get("shared_room_ids",[]))
	var entry: Variant = payload.get("entry",old.get("entry",{}))
	var scope: Variant = payload.get("intake_disease_ids",old.get("intake_disease_ids",[]))
	var public_cells: Variant = payload.get("public_cells",old.get("public_cells",[]))
	var label: String = str(payload.get("name",old.get("name","新科室"))).strip_edges()
	var focus: String = str(payload.get("focus_id",old.get("focus_id","")))
	if not rooms is Array or rooms.is_empty() or not shared is Array or not scope is Array or not public_cells is Array or not _entry_shape(entry) or label.is_empty() or label.length()>40: return _result(world,false,"invalid_department","科室须有完整房间、入口和有效名称")
	if not focus.is_empty() and content.definition("specialties",focus).is_empty(): return _result(world,false,"unknown_focus","医疗专业不存在")
	var seen: Dictionary = {}
	for room_id: Variant in rooms:
		if not room_id is String or not world.facts.rooms.has(room_id) or seen.has(room_id): return _result(world,false,"room_missing","房间引用无效或重复")
		seen[room_id] = true
	for room_id: Variant in shared:
		if not room_id is String or not world.facts.rooms.has(room_id): return _result(world,false,"shared_room_missing","共享房间不存在")
	for disease_id: Variant in scope:
		if not disease_id is String or content.definition("diseases",disease_id).is_empty(): return _result(world,false,"unknown_disease","接诊范围引用不存在")
	var floor_id: int = int(entry.floor_id)
	var cell: Vector2i = Vector2i(int(entry.cell[0]),int(entry.cell[1]))
	if not space.owned(world,floor_id,cell) or entry.cell in world.facts.floors.overrides[str(floor_id)].blocked: return _result(world,false,"entry_unavailable","科室入口须在实际已购通行区域")
	var adjacent: bool = false
	for room_id: String in rooms:
		var room: Dictionary = world.facts.rooms[room_id]
		var expanded: Rect2 = Rect2(float(room.origin[0])-2,float(room.origin[1])-2,float(room.size[0])+4,float(room.size[1])+4)
		if int(room.floor_id)==floor_id and expanded.has_point(Vector2(cell)): adjacent = true
	if not adjacent: return _result(world,false,"entry_disconnected","科室入口须与实际科室房间相邻")
	for point: Variant in public_cells:
		if not point is Array or point.size()!=2 or not space.owned(world,floor_id,Vector2i(int(point[0]),int(point[1]))) or point in world.facts.floors.overrides[str(floor_id)].blocked: return _result(world,false,"public_region_unavailable","公共区域包含不可通行格")
	var focus_quote: Dictionary = _focus_quote(world,rooms,focus)
	if not focus_quote.ok: return _result(world,false,"focus_cooldown",focus_quote.reason)
	if HospitalLedger.balance(world)<int(focus_quote.cost): return _result(world,false,"insufficient_funds","资金不足，科室配置保留")
	if id.is_empty(): id = world.new_id("department")
	if int(focus_quote.cost)>0:
		var paid: CommandResult = HospitalLedger.post(world,LedgerEntry.new(id,"focus:"+str(world.sim_tick),-int(focus_quote.cost)))
		if not paid.accepted: return paid
	for other: Dictionary in world.facts.departments.units.values():
		if other.id==id: continue
		var previous_rooms: int = other.room_ids.size()
		for room_id: String in rooms: other.room_ids.erase(room_id)
		if previous_rooms!=other.room_ids.size(): world.department_changed(other.id)
	world.facts.departments.units[id] = {"id":id,"name":label,"room_ids":rooms.duplicate(),"shared_room_ids":shared.duplicate(),"public_cells":public_cells.duplicate(true),"entry":entry.duplicate(true),"intake_disease_ids":scope.duplicate(),"open":old.get("open",true),"focus_id":focus,"focus_ready_tick":focus_quote.ready_tick}
	_apply_focus(world,rooms,focus,focus_quote)
	return _result(world,true,"applied","",[id])

func _set_focus(world: WorldState, unit: Dictionary, focus_id: String) -> CommandResult:
	if not focus_id.is_empty() and content.definition("specialties",focus_id).is_empty(): return _result(world,false,"unknown_focus","医疗专业不存在")
	var quote: Dictionary = _focus_quote(world,unit.room_ids,focus_id)
	if not quote.ok: return _result(world,false,"focus_cooldown",quote.reason)
	if int(quote.cost)>0:
		var paid: CommandResult = HospitalLedger.post(world,LedgerEntry.new(unit.id,"focus:"+str(world.sim_tick),-int(quote.cost)))
		if not paid.accepted: return paid
	unit.focus_id = focus_id
	unit.focus_ready_tick = quote.ready_tick
	_apply_focus(world,unit.room_ids,focus_id,quote)
	return _result(world,true,"applied","",[unit.id])

func _focus_quote(world: WorldState, rooms: Array, focus: String) -> Dictionary:
	var changed: bool = false
	var ready_tick: int = world.sim_tick
	for id: String in rooms:
		var previous: Dictionary = world.facts.departments.room_focus.get(id,{})
		if previous.is_empty() or str(previous.focus_id).is_empty(): continue
		if previous.focus_id!=focus:
			if world.sim_tick<int(previous.ready_tick): return {"ok":false,"reason":"房间原专业调整仍在600秒过渡期"}
			changed = true
		else: ready_tick = maxi(ready_tick,int(previous.ready_tick))
	return {"ok":true,"cost":int(content.balance.care_departments.focus_change_cost) if changed else 0,"ready_tick":world.sim_tick+_ticks(content.balance.care_departments.focus_change_seconds) if changed else ready_tick}

func _apply_focus(world: WorldState, rooms: Array, focus: String, quote: Dictionary) -> void:
	for id: String in rooms: world.facts.departments.room_focus[id] = {"focus_id":focus,"ready_tick":quote.ready_tick}

func _belongs(unit: Dictionary, facility: Dictionary) -> bool:
	return facility.get("room_id","") in unit.room_ids or facility.get("room_id","") in unit.shared_room_ids or unit.id=="general" and not facility.has("room_id")

func _serves_other_case(world: WorldState, unit: Dictionary) -> bool:
	for facility: Dictionary in world.facts.facilities.values():
		if not _belongs(unit,facility): continue
		for binding: Dictionary in content.catalog.treatment_bindings:
			var routine: Dictionary = content.definition("treatment_routines",binding.routine_id)
			if routine.equipment_id==facility.definition_id and (unit.intake_disease_ids.is_empty() or binding.disease_id in unit.intake_disease_ids): return true
	return false

func _has_guide_screen(world: WorldState, unit: Dictionary, visit: Dictionary) -> bool:
	for facility: Dictionary in world.facts.facilities.values():
		if facility.definition_id!="SE03" or int(facility.floor_id)!=int(unit.entry.floor_id): continue
		if Vector2(float(facility.cell[0]),float(facility.cell[1])).distance_to(Vector2(float(unit.entry.cell[0]),float(unit.entry.cell[1])))<=float(content.balance.patient_behavior.crowd_radius_cells) and space.route(world,visit.actor_id,int(facility.floor_id),facility.patient_cell).ok: return true
	return false

func _start_guidance(world: WorldState, visit_id: String) -> bool:
	var visit: Dictionary = world.facts.visits[visit_id]
	if world.facts.moves.has(visit.actor_id) or world.facts.actors[visit.actor_id].location.kind!="floor": return false
	for staff_id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[staff_id]
		if staff.role!="nurse" or not "q_guide" in staff.get("certificates",[]) or not staff.on_shift or staff.get("block_new_work",false) or _staff_busy(world,staff_id) or world.facts.moves.has(staff_id): continue
		var destination: Array = _guide_position(world,visit_id,staff_id)
		if destination.is_empty(): continue
		if HospitalStaffWellbeing.yield_for_work(world,content,space,[staff_id]): continue
		if waiting_life!=null and not waiting_life.call_patient(world,visit_id): return false
		_start_guide_job(world,visit_id,staff_id,"nurse")
		return true
	return false

func _start_guide_job(world: WorldState, visit_id: String, staff_id: String, kind: String) -> void:
	var visit: Dictionary = world.facts.visits[visit_id]
	var ticket: Dictionary = world.facts.tickets[visit.ticket_id]
	if not ticket.has("pause_reasons"): ticket.pause_reasons = {}
	var id: String = visit_id+":guidance:"+kind
	ticket.pause_reasons.guidance = id
	world.facts.departments.guidance[visit_id] = {"id":id,"visit_id":visit_id,"staff_ids":[staff_id],"kind":kind,"phase":"travel","remaining_ticks":0}
	world.facts.staff[staff_id].active_job_id = id
	var destination: Array = _guide_position(world,visit_id,staff_id)
	if not destination.is_empty(): space.request_move(world,staff_id,int(world.facts.actors[visit.actor_id].location.floor_id),destination)

func _record_help(world: WorldState, visit_id: String, staff_id: String, source_id: String, stage: String) -> void:
	var data: Dictionary = world.facts.departments.experience[visit_id]
	var key: String = stage+":"+staff_id
	if not data.helps.has(key): data.helps[key] = {"source_id":source_id,"staff_id":staff_id,"stage":stage,"tick":world.sim_tick}

func _guide_position(world: WorldState, visit_id: String, nurse_id: String) -> Array:
	var actor: Dictionary = world.facts.actors[world.facts.visits[visit_id].actor_id]
	if actor.location.kind!="floor": return []
	var size: int = space.clearance(actor)
	var nurse_size: int = space.clearance(world.facts.actors[nurse_id])
	for offset: Array in [[-nurse_size,0],[size,0],[0,-nurse_size],[0,size]]:
		var target: Array = [roundi(actor.location.cell[0])+int(offset[0]),roundi(actor.location.cell[1])+int(offset[1])]
		if space.route(world,nurse_id,int(actor.location.floor_id),target).ok: return target
	return []

func _staff_busy(world: WorldState, staff_id: String) -> bool:
	var staff: Dictionary = world.facts.staff[staff_id]
	if not HospitalStaffWellbeing.work_window(staff) or float(staff.energy)<=15.0 or not str(staff.get("active_job_id","")).is_empty() or staff.get("block_new_work",false): return true
	for session: Dictionary in world.facts.sessions.values():
		if staff_id in session.staff_ids: return true
	for preparation: Dictionary in world.facts.preparations.values():
		if staff_id in preparation.staff_ids: return true
	for stay: Dictionary in world.facts.ward_stays.values():
		if stay.get("nurse_id","")==staff_id: return true
	for job: Dictionary in world.facts.departments.guidance.values():
		if staff_id in job.staff_ids: return true
	return false

func _available_doctor(world: WorldState, unit: Dictionary) -> String:
	for staff_id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[staff_id]
		var actor: Dictionary = world.facts.actors[staff_id]
		if staff.role!="doctor" or not staff.on_shift or _staff_busy(world,staff_id) or world.facts.moves.has(staff_id) or actor.location.kind!="floor" or int(actor.location.floor_id)!=int(unit.entry.floor_id): continue
		if Vector2(float(actor.location.cell[0]),float(actor.location.cell[1])).distance_to(Vector2(float(unit.entry.cell[0]),float(unit.entry.cell[1])))<=float(content.balance.patient_behavior.crowd_radius_cells): return staff_id
	return ""

func _correct(world: WorldState, visit_id: String, source: String, target: String = "") -> void:
	var route: Dictionary = world.facts.departments.routes[visit_id]
	var visit: Dictionary = world.facts.visits[visit_id]
	route.corrected = true
	route.correction_source = source
	visit.department_id = target if not target.is_empty() else route.correct_department_id
	var ticket: Dictionary = world.facts.tickets.get(visit.get("ticket_id",""),{})
	if not ticket.is_empty(): ticket.get("pause_reasons",{}).erase("guidance")
	var job: Dictionary = world.facts.departments.guidance.get(visit_id,{})
	for staff_id: String in job.get("staff_ids",[]):
		if world.facts.staff[staff_id].get("active_job_id","")==job.id: world.facts.staff[staff_id].active_job_id = ""
	world.facts.departments.guidance.erase(visit_id)
	visit.waiting_reason = "已指向可接诊科室，原票号与证据保留"

func _sample_anger(world: WorldState, visit: Dictionary, data: Dictionary, provided: Variant = null) -> void:
	var active: Dictionary = {}
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	var observation: Dictionary = provided if provided!=null else (_environment(world,visit.actor_id,int(actor.location.floor_id),actor.location.cell) if actor.location.kind=="floor" else {})
	var need: Dictionary = world.facts.get("waiting_life",{}).get("needs",{}).get(visit.id,{})
	var ticket: Dictionary = world.facts.tickets.get(visit.get("ticket_id",""),{})
	if not need.is_empty():
		if need.purpose=="toilet" and need.phase=="local_wait" and not world.facts.moves.has(visit.actor_id): active.wait_toilet = int(need.queued_ticks)
	elif world.facts.departments.guidance.has(visit.id):
		active.wait_guidance = world.sim_tick-int(world.facts.departments.routes[visit.id].started_tick)
	elif not ticket.is_empty() and ticket.get("pause_reasons",{}).is_empty():
		active["wait_doctor" if ticket.kind in ["gp","consult","outpatient","round"] else "wait_clinical"] = int(ticket.get("waited_ticks",0))
		if world.facts.get("waiting_life",{}).get("seats",{}).get(visit.id,{}).is_empty(): active.no_compatible_seat = _clock(world,data,"no_compatible_seat")
	if not observation.is_empty():
		if not bool(observation.get("clean",true)): active.dirty = _clock(world,data,"dirty")
		if float(observation.get("noise",0.0))>0.0: active.construction_noise = _clock(world,data,"construction_noise")
	var base: float = 0.0
	var contributions: Dictionary = {}
	for cause_id: String in active:
		var cause: Dictionary = _cause(cause_id)
		if int(active[cause_id])<_ticks(cause.grace_seconds): continue
		var amount: float = float(cause.per_update)
		if cause_id=="construction_noise" and waiting_life!=null: amount *= waiting_life.noise_multiplier(world,visit.id)
		contributions[cause_id] = amount
		base += amount
	var personality: Dictionary = content.definition("patient_personalities",visit.personality_id)
	if base>0:
		var cap_multiplier: float = minf(1.0,float(content.balance.anger.continuous_base_cap)/base)
		var environment_multiplier: float = 1.0 if observation.is_empty() or float(observation.value)<60.0 else 0.75 if float(observation.value)<80.0 else 0.5
		var increase: float = base*cap_multiplier*float(personality.anger_growth_multiplier)
		for cause_id: String in contributions:
			_anger_change(visit,data,cause_id,float(contributions[cause_id])*cap_multiplier*float(personality.anger_growth_multiplier)*environment_multiplier)
		data.anger_sources.environment_buffer = float(data.anger_sources.get("environment_buffer",0.0))+increase*(1.0-environment_multiplier)
	else:
		var decay: float = float(content.balance.anger.natural_decay)*float(personality.anger_decay_multiplier)
		var summary: Dictionary = waiting_life.patient_summary(world,visit.id) if waiting_life!=null else {}
		if not summary.get("seat",{}).is_empty() and summary.seat.phase=="seated" and not summary.get("reasons",[]).is_empty(): decay += float(content.balance.anger.preferred_seat_decay)
		_anger_change(visit,data,"natural_calm",-decay)

func _update_cause_clocks(world: WorldState, visit: Dictionary, data: Dictionary, observation: Dictionary) -> void:
	var active: Dictionary = {}
	var ticket: Dictionary = world.facts.tickets.get(visit.get("ticket_id",""),{})
	if not ticket.is_empty() and ticket.get("pause_reasons",{}).is_empty() and world.facts.get("waiting_life",{}).get("seats",{}).get(visit.id,{}).is_empty(): active.no_compatible_seat = true
	if not bool(observation.get("clean",true)): active.dirty = true
	if float(observation.get("noise",0.0))>0: active.construction_noise = true
	for id: String in active:
		if not data.cause_clocks.has(id): data.cause_clocks[id] = world.sim_tick
	for id: String in data.cause_clocks.keys():
		if not active.has(id): data.cause_clocks.erase(id)

func _clock(world: WorldState, data: Dictionary, cause_id: String) -> int:
	if not data.cause_clocks.has(cause_id): data.cause_clocks[cause_id] = world.sim_tick
	return world.sim_tick-int(data.cause_clocks[cause_id])

func _cause(id: String) -> Dictionary:
	for cause: Dictionary in content.balance.anger.causes:
		if cause.id==id: return cause
	return {}

func _anger_change(visit: Dictionary, data: Dictionary, source: String, delta: float) -> void:
	var previous: float = float(visit.anger)
	visit.anger = clampf(previous+delta,0.0,100.0)
	data.anger_sources[source] = float(data.anger_sources.get(source,0.0))+float(visit.anger)-previous

func _record_staff_job(world: WorldState, source: Dictionary) -> void:
	var state: Dictionary = world.facts.departments
	if int(source.tick)/WorldState.TICKS_PER_DAY<maxi(0,world.sim_tick/WorldState.TICKS_PER_DAY-int(content.balance.ratings.window_days)): return
	var key: String = str(source.staff_id)+":"+str(source.id)
	if state.staff_consumed.has(key): return
	state.staff_consumed[key] = int(source.tick)
	if not state.staff_jobs.has(source.staff_id): state.staff_jobs[source.staff_id] = []
	state.staff_jobs[source.staff_id].append(source.duplicate(true))
	state.staff_jobs[source.staff_id].sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.tick<b.tick if a.tick!=b.tick else a.id<b.id)
	while state.staff_jobs[source.staff_id].size()>int(content.balance.ratings.staff_job_limit): state.staff_jobs[source.staff_id].pop_front()

func _track_phase(world: WorldState, visit: Dictionary, data: Dictionary) -> void:
	if data.phase==visit.phase: return
	data.phase_totals[data.phase] = int(data.phase_totals.get(data.phase,0))+maxi(0,world.sim_tick-int(data.phase_started_tick))
	_detail(world,data,{"kind":"phase","phase":data.phase,"start_tick":data.phase_started_tick,"end_tick":world.sim_tick})
	data.phase = visit.phase
	data.phase_started_tick = world.sim_tick

func _detail(_world: WorldState, data: Dictionary, detail: Dictionary) -> void:
	if not data.details.is_empty() and detail.kind=="cause" and data.details[-1].kind=="cause" and data.details[-1].cause_id==detail.cause_id: return
	data.details.append(detail)
	while data.details.size()>int(content.balance.journey_review.details_per_visit):
		data.details.pop_front()
		data.early_details_merged = true

func _charges(world: WorldState, visit: Dictionary) -> Array:
	var charges: Array = []
	for key: String in world.ledger_owner_ids([visit.id]+visit.attempt_ids):
		var entry: Dictionary = world.facts.ledger.entries[key]
		if entry.settled and (entry.owner_id==visit.id or entry.owner_id in visit.attempt_ids):
			charges.append({"id":key,"component":entry.component,"amount":entry.amount,"tick":entry.tick})
	return charges

func _window_cases(world: WorldState, department_id: String) -> Array:
	var current_day: int = world.sim_tick/WorldState.TICKS_PER_DAY
	var cases: Array = []
	for record: Dictionary in world.facts.get("departments",{}).get("cases",[]):
		if int(record.day)>=current_day or int(record.day)<maxi(0,current_day-int(content.balance.ratings.window_days)): continue
		if not department_id.is_empty() and record.department_id!=department_id: continue
		cases.append(record)
	return cases.slice(maxi(0,cases.size()-int(content.balance.ratings.case_window_limit)))

func _staff_experience(world: WorldState) -> Variant:
	var staff_values: Dictionary = {}
	var today: int = world.sim_tick/WorldState.TICKS_PER_DAY
	for day_key: String in world.facts.get("departments",{}).get("staff_days",{}):
		if int(day_key)>=today or int(day_key)<maxi(0,today-int(content.balance.ratings.window_days)): continue
		for staff_id: String in world.facts.departments.staff_days[day_key]:
			var daily: Dictionary = world.facts.departments.staff_days[day_key][staff_id]
			if not staff_values.has(staff_id): staff_values[staff_id] = []
			var energy: float = float(daily.energy_total)/maxi(1,int(daily.ticks))
			var coverage: float = 100.0 if int(daily.required_rest_ticks)==0 else minf(1.0,float(daily.rest_ticks)/int(daily.required_rest_ticks))*100.0
			staff_values[staff_id].append(energy*float(content.balance.ratings.staff_energy_weight)+coverage*float(content.balance.ratings.staff_rest_coverage_weight))
	var means: Array = []
	for values: Array in staff_values.values(): means.append(_mean(values))
	return _mean(means) if not means.is_empty() else null

func _prune(world: WorldState) -> void:
	var state: Dictionary = world.facts.departments
	var today: int = world.sim_tick/WorldState.TICKS_PER_DAY
	var boundary: Array = [world.get_instance_id(),today,state.cases.size()]
	if _pruned_boundary==boundary: return
	var oldest_day: int = maxi(0,today-int(content.balance.ratings.window_days))
	state.cases = state.cases.filter(func(record: Dictionary) -> bool: return int(record.day)>=oldest_day)
	var retained: Dictionary = {}
	var counts: Dictionary = {}
	var published: Dictionary = {}
	for index: int in range(state.cases.size()-1,-1,-1):
		var record: Dictionary = state.cases[index]
		for key: String in ["hospital","department:"+str(record.department_id)]:
			if int(counts.get(key,0))<int(content.balance.ratings.case_window_limit): retained[record.visit_id] = true
			counts[key] = int(counts.get(key,0))+1
			if int(record.day)<today:
				if int(published.get(key,0))<int(content.balance.ratings.case_window_limit): retained[record.visit_id] = true
				published[key] = int(published.get(key,0))+1
	state.cases = state.cases.filter(func(record: Dictionary) -> bool: return retained.has(record.visit_id))
	_pruned_boundary = [world.get_instance_id(),today,state.cases.size()]
	var closed: Array = []
	for id: String in state.experience:
		if int(state.experience[id].closed_tick)>=0: closed.append({"id":id,"tick":state.experience[id].closed_tick})
	closed.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.tick<b.tick if a.tick!=b.tick else a.id<b.id)
	while closed.size()>int(content.balance.journey_review.closed_receipts): state.experience.erase(closed.pop_front().id)
	for key: String in state.staff_consumed.keys():
		if int(state.staff_consumed[key])/WorldState.TICKS_PER_DAY<oldest_day: state.staff_consumed.erase(key)
	for key: String in state.staff_days.keys():
		if int(key)<oldest_day: state.staff_days.erase(key)
	for staff_id: String in state.staff_jobs:
		state.staff_jobs[staff_id] = state.staff_jobs[staff_id].filter(func(record: Dictionary) -> bool: return int(record.tick)/WorldState.TICKS_PER_DAY>=oldest_day)

func _environment(world: WorldState, actor_id: String, floor_id: int, cell: Array) -> Dictionary:
	if environment==null: return {"value":float(content.balance.environment.base)+float(content.balance.environment.clean_bonus),"noise":0.0,"clean":true}
	return environment.sample_at(world,floor_id,cell,actor_id) if environment.has_method("sample_at") else environment.environment_at(world,floor_id,cell,actor_id,false)

func _grace_ticks(kind: String) -> int:
	return _ticks(_cause("wait_doctor" if kind in ["gp","consult","outpatient","round"] else "wait_clinical").grace_seconds)

func _weighted(parts: Dictionary, weights: Dictionary) -> Variant:
	var total: float = 0.0
	var weight: float = 0.0
	for key: String in weights:
		if parts.has(key):
			total += float(parts[key])*float(weights[key])
			weight += float(weights[key])
	return total/weight if weight>0 else null

func _mean(values: Array) -> float:
	var total: float = 0.0
	for value: Variant in values: total += float(value)
	return total/values.size()

func _stars(score: Variant) -> float:
	return roundf(float(score)/10.0)*0.5

func _entry_shape(value: Variant) -> bool:
	if not value is Dictionary or not _natural(value.get("floor_id")) or int(value.floor_id)<1 or not value.get("cell") is Array or value.cell.size()!=2: return false
	for number: Variant in value.cell:
		if not _natural(number): return false
	return true

func _natural(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0 and float(value)<=1000000000000.0 and float(value)==floor(float(value))

func _sorted(value: Dictionary) -> Array:
	var keys: Array = value.keys()
	keys.sort()
	return keys

func _ticks(seconds: Variant) -> int:
	return ceili(float(seconds)/WorldState.TICK_SECONDS)

func _result(world: WorldState, ok: bool, code: String, reason: String, changed: Array = []) -> CommandResult:
	if ok:
		for id: String in changed:
			if world.facts.departments.units.has(id): world.department_changed(id)
	return CommandResult.new(ok,code,reason,changed,world.revision)
