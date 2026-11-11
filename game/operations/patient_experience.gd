class_name HospitalExperience
extends RefCounted

var content: HospitalContent
var space: HospitalSpace
var clinic: RefCounted
var waiting_life: RefCounted
var environment: RefCounted
var sample_workers_enabled: bool = true
var sample_worker_tasks: int = 4
var sample_worker_diagnostics: bool = false
var _worker_sample_batch: RefCounted
var _pruned_boundary: Array = []

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry

func ensure(world: WorldState) -> void:
	if not world.facts.has("patient_experience"):
		world.facts.patient_experience = {"experience":{},"cases":[],"staff_jobs":{},"staff_consumed":{},"staff_days":{}}
	var state: Dictionary = world.facts.patient_experience
	for visit_id: String in world.active_visit_ids():
		if not state.experience.has(visit_id):
			var visit: Dictionary = world.facts.visits[visit_id]
			if visit.phase=="departed": continue
			state.experience[visit_id] = {"visit_id":visit_id,"arrival_tick":int(visit.get("arrival_tick",world.sim_tick)),"phase":visit.phase,"phase_started_tick":world.sim_tick,
				"phase_totals":{},"details":[],"early_details_merged":false,"retired_tickets":{},"excess_wait_ticks":0,"environment_total":0.0,"environment_ticks":0,
				"helps":{},"unhandled":{},"broken_promises":{},"started_services":{},"completed_services":{},"staff_ids":[],
				"cause_clocks":{},"anger_sources":{},"next_anger_tick":world.sim_tick+_ticks(content.balance.anger.update_seconds),"last_progress_tick":world.sim_tick,"closed_tick":-1}

func sample(world: WorldState) -> void:
	ensure(world)
	# Sampling changes experience records, not bodies or facility ownership.
	# Share read-only water fit/occupancy views only inside this sample; a
	# hypothetical world keeps its own scope and the view ends before movement.
	var shared_water_scope: bool=(environment!=null
		and environment.get_script()==preload("res://game/operations/environment_service.gd")
		and environment.space!=null and environment.space.get_script()==preload("res://game/building/hospital_space.gd")
		and (environment.waiting_life==null or environment.waiting_life.get_script()==preload("res://game/life/waiting_life.gd")))
	if shared_water_scope:environment.space.begin_route_query(world,{},environment.space.nominal_query(world))
	if environment!=null: environment.begin_query(world)
	var _worker_visit_ids: Array = world.active_visit_ids()
	var _worker_sample_active: bool = sample_workers_enabled and environment!=null and environment.get_script()==preload("res://game/operations/environment_service.gd") and environment.space!=null and environment.space.get_script()==preload("res://game/building/hospital_space.gd")
	if _worker_sample_active:
		if _worker_sample_batch==null: _worker_sample_batch = preload("res://game/operations/environment_sample_batch.gd").new()
		_worker_sample_active = _worker_sample_batch.prepare(world,environment,_worker_visit_ids,sample_worker_tasks,sample_worker_diagnostics)
		if _worker_sample_active: _worker_sample_batch.begin_apply()
	for visit_id: String in _worker_visit_ids:
		var visit: Dictionary = world.facts.visits[visit_id]
		if not world.facts.patient_experience.experience.has(visit_id): continue
		var experience: Dictionary = world.facts.patient_experience.experience[visit_id]
		if int(experience.closed_tick)>=0: continue
		_track_phase(world,visit,experience)
		var actor: Dictionary = world.facts.actors[visit.actor_id]
		var observation: Dictionary = {}
		if actor.location.kind=="floor":
			observation = _worker_sample_batch.consume(world,environment,visit_id,str(visit.actor_id)) if _worker_sample_active else _environment(world,visit.actor_id,int(actor.location.floor_id),actor.location.cell)
			experience.environment_total += float(observation.value)
			experience.environment_ticks += 1
			_update_cause_clocks(world,visit,experience,observation)
		if world.sim_tick>=int(experience.next_anger_tick):
			experience.next_anger_tick = world.sim_tick+_ticks(content.balance.anger.update_seconds)
			_sample_anger(world,visit,experience,observation)
			var reasons: Array = reason_cards(world,visit_id)
			if not reasons.is_empty(): _detail(world,experience,{"kind":"cause","tick":world.sim_tick,"cause_id":reasons[0].id,"text":reasons[0].reason})
	if _worker_sample_active: _worker_sample_batch.end_apply(environment)
	if environment!=null: environment.end_query()
	if shared_water_scope:environment.space.end_route_query()
	var staff_ids: Array = world.ids("staff")
	if staff_ids.is_empty(): return
	# All employees in this synchronous sample share the same hospital day.
	var day_key: String = str(world.sim_tick/WorldState.TICKS_PER_DAY)
	if not world.facts.patient_experience.staff_days.has(day_key): world.facts.patient_experience.staff_days[day_key] = {}
	var days: Dictionary = world.facts.patient_experience.staff_days[day_key]
	for staff_id: String in staff_ids:
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
		if not world.facts.patient_experience.experience.has(visit_id): continue
		var experience: Dictionary = world.facts.patient_experience.experience[visit_id]
		if visit.phase=="departed" and int(experience.closed_tick)<0:
			_track_phase(world,visit,experience)
			experience.closed_tick = world.sim_tick
			experience.final_score = patient_rating(world,visit_id)
			experience.final_result = visit.final_result
			experience.staff_names = {}
			for staff_id: String in experience.staff_ids: experience.staff_names[staff_id] = world.facts.actors[staff_id].name
			experience.charges = _charges(world,visit)
			world.facts.patient_experience.cases.append({"visit_id":visit_id,"tick":world.sim_tick,"day":world.sim_tick/WorldState.TICKS_PER_DAY,
				"result":visit.final_result,"treated":not visit.attempt_ids.is_empty(),"rating":experience.final_score.duplicate(true)})
	for source: String in ["environment","maintenance"]:
		for receipt_id: String in world.completion_receipt_ids(source):
			var receipt: Dictionary = world.facts.get(source,{}).get("receipts",{}).get(receipt_id,{})
			if receipt.is_empty() or int(receipt.tick)/WorldState.TICKS_PER_DAY<maxi(0,world.sim_tick/WorldState.TICKS_PER_DAY-int(content.balance.ratings.window_days)): continue
			if world.facts.patient_experience.staff_consumed.has(str(receipt.get("staff_id",""))+":"+str(receipt.id)): continue
			if world.facts.staff.has(receipt.get("staff_id","")):
				var job: Dictionary = receipt.duplicate(true)
				job.success = true
				_record_staff_job(world,job)
	_prune(world)

func service_started(world: WorldState, session: Dictionary) -> void:
	ensure(world)
	var experience: Dictionary = world.facts.patient_experience.experience[session.visit_id]
	if experience.started_services.has(session.id): return
	experience.started_services[session.id] = {"kind":session.kind,"tick":world.sim_tick,"facility_id":session.facility_id,"staff_ids":session.staff_ids.duplicate()}
	var visit: Dictionary = world.facts.visits[session.visit_id]
	retire_ticket(world,session.visit_id)
	for staff_id: String in session.staff_ids:
		if not staff_id in experience.staff_ids: experience.staff_ids.append(staff_id)
	var stage_key: String = str(session.kind)+":"+str(session.get("attempt_id",""))
	if not experience.get("service_relief",{}).has(stage_key):
		if not experience.has("service_relief"): experience.service_relief = {}
		experience.service_relief[stage_key] = true
		_anger_change(visit,experience,"clinical_service",-float(content.balance.anger.new_service_relief))
	experience.last_progress_tick = world.sim_tick

func service_completed(world: WorldState, session: Dictionary) -> void:
	ensure(world)
	var experience: Dictionary = world.facts.patient_experience.experience[session.visit_id]
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
	var data: Dictionary = world.facts.patient_experience.experience.get(visit_id,{})
	var ticket: Dictionary = world.facts.tickets.get(visit.get("ticket_id",""),{})
	if data.is_empty() or ticket.is_empty() or data.retired_tickets.has(ticket.id): return
	data.retired_tickets[ticket.id] = true
	data.excess_wait_ticks += maxi(0,int(ticket.get("waited_ticks",0))-_grace_ticks(str(ticket.kind)))

func patient_rating(world: WorldState, visit_id: String) -> Dictionary:
	var visit: Dictionary = world.facts.visits[visit_id]
	var data: Dictionary = world.facts.get("patient_experience",{}).get("experience",{}).get(visit_id,{})
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
	parts.flow = clampf(100.0-float(excess)*WorldState.TICK_SECONDS/float(content.balance.ratings.flow_seconds_per_point)-data.broken_promises.size()*float(content.balance.ratings.broken_promise_penalty),0.0,100.0)
	parts.care = clampf(float(content.balance.ratings.care_base)+data.helps.size()*float(content.balance.ratings.care_help_bonus)-data.unhandled.size()*float(content.balance.ratings.care_unhandled_penalty),0.0,100.0)
	if int(data.environment_ticks)>0: parts.environment = float(data.environment_total)/float(data.environment_ticks)
	return {"score":_weighted(parts,content.balance.ratings.weights.patient),"samples":1,"parts":parts,"status":"已离院" if visit.phase=="departed" else "进行中"}

func aggregate_rating(world: WorldState) -> Dictionary:
	var cases: Array = _window_cases(world)
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
	var experience: Variant = _staff_experience(world)
	if experience!=null: parts.staff_experience = experience
	var weights: Dictionary = content.balance.ratings.weights.hospital
	var score: Variant = _weighted(parts,weights)
	return {"score":score,"parts":parts,"samples":cases.size(),"stars":_stars(score) if cases.size()>=int(content.balance.ratings.minimum_samples) and score!=null else null,"window_days":int(content.balance.ratings.window_days),"status":"积累评价中" if cases.is_empty() else "已结算医院日"}

func staff_rating(world: WorldState, staff_id: String) -> Dictionary:
	var jobs: Array = world.facts.get("patient_experience",{}).get("staff_jobs",{}).get(staff_id,[])
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
			var data: Dictionary = world.facts.patient_experience.experience.get(visit_id,{})
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
			for record: Dictionary in _window_cases(world):
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
	var data: Dictionary = world.facts.get("patient_experience",{}).get("experience",{}).get(visit_id,{})
	if visit.is_empty() or data.is_empty(): return {}
	var result: Dictionary = {"visit_id":visit_id,"actor_name":world.facts.actors[visit.actor_id].name,"phase":visit.phase,"phase_totals":data.phase_totals.duplicate(true),"details":data.details.duplicate(true),"early_details_merged":data.early_details_merged,"rating":patient_rating(world,visit_id),"reasons":reason_cards(world,visit_id),"closed_tick":data.closed_tick}
	if int(data.closed_tick)>=0:
		result.merge({"result":data.final_result,"staff_names":data.staff_names.duplicate(true),"charges":data.charges.duplicate(true)},true)
	else:
		result.phase_totals[data.phase] = int(result.phase_totals.get(data.phase,0))+maxi(0,world.sim_tick-int(data.phase_started_tick))
		result.charges = _charges(world,visit)
	return result

func summary(world: WorldState) -> Dictionary:
	return {"hospital_rating":aggregate_rating(world),"reasons":hospital_reasons(world)}

func patient_summary(world: WorldState, visit_id: String) -> Dictionary:
	var visit: Dictionary = world.facts.visits.get(visit_id,{})
	if visit.is_empty(): return {}
	var data: Dictionary = world.facts.get("patient_experience",{}).get("experience",{}).get(visit_id,{})
	var anger: float = float(visit.anger)
	var thresholds: Array = content.balance.anger.thresholds
	return {"personality_id":visit.personality_id,"anger":anger,"mood":clampf(100.0-anger,0.0,100.0),"expression":"平静" if anger<float(thresholds[0]) else "烦躁" if anger<float(thresholds[1]) else "生气" if anger<float(thresholds[2]) else "请求帮助","anger_sources":data.get("anger_sources",{}).duplicate(true),"rating":patient_rating(world,visit_id),"reasons":reason_cards(world,visit_id)}

func validate(world: WorldState) -> String:
	var state: Variant = world.facts.get("patient_experience")
	if not state is Dictionary or not world.facts.get("floors") is Dictionary or not world.facts.floors.get("overrides") is Dictionary or not world.facts.get("rooms") is Dictionary or not world.facts.get("visits") is Dictionary or not world.facts.get("staff") is Dictionary: return "缺少就诊体验事实"
	for collection: String in ["experience","staff_jobs","staff_consumed","staff_days"]:
		if not state.get(collection) is Dictionary: return "就诊体验集合无效："+collection
	if not state.get("cases") is Array: return "医院评分窗口无效"
	for visit_id: Variant in state.experience:
		var data: Variant = state.experience[visit_id]
		if not visit_id is String or not world.facts.visits.has(visit_id) or not data is Dictionary or not data.get("details") is Array or data.details.size()>int(content.balance.journey_review.details_per_visit) or not data.get("phase_totals") is Dictionary or not _natural(data.get("environment_ticks")) or not _natural(data.get("excess_wait_ticks")): return "就诊体验进度无效"
		for field: String in ["helps","unhandled","broken_promises","started_services","completed_services","cause_clocks","anger_sources","retired_tickets"]:
			if not data.get(field) is Dictionary: return "体验来源集合无效："+field
	for staff_id: Variant in state.staff_jobs:
		if not staff_id is String or not world.facts.staff.has(staff_id) or not world.facts.staff[staff_id] is Dictionary or not state.staff_jobs[staff_id] is Array or state.staff_jobs[staff_id].size()>int(content.balance.ratings.staff_job_limit): return "员工评价窗口引用无效"
		for record: Variant in state.staff_jobs[staff_id]:
			if not record is Dictionary: return "员工评价窗口记录无效"
	var cases: Dictionary = {}
	for record: Variant in state.cases:
		if not record is Dictionary or not record.get("visit_id") is String or not world.facts.visits.has(record.get("visit_id","")) or cases.has(record.visit_id) or not _natural(record.get("tick")) or not _natural(record.get("day")) or not record.get("treated") is bool or not record.get("rating") is Dictionary: return "病例评分窗口无效"
		cases[record.visit_id] = true
	return ""

func _record_help(world: WorldState, visit_id: String, staff_id: String, source_id: String, stage: String) -> void:
	var data: Dictionary = world.facts.patient_experience.experience[visit_id]
	var key: String = stage+":"+staff_id
	if not data.helps.has(key): data.helps[key] = {"source_id":source_id,"staff_id":staff_id,"stage":stage,"tick":world.sim_tick}

func _sample_anger(world: WorldState, visit: Dictionary, data: Dictionary, provided: Variant = null) -> void:
	var active: Dictionary = {}
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	var observation: Dictionary = provided if provided!=null else (_environment(world,visit.actor_id,int(actor.location.floor_id),actor.location.cell) if actor.location.kind=="floor" else {})
	var need: Dictionary = world.facts.get("waiting_life",{}).get("needs",{}).get(visit.id,{})
	var ticket: Dictionary = world.facts.tickets.get(visit.get("ticket_id",""),{})
	if not need.is_empty():
		if need.purpose=="toilet" and need.phase=="local_wait" and not world.facts.moves.has(visit.actor_id): active.wait_toilet = int(need.queued_ticks)
	elif not ticket.is_empty() and ticket.get("pause_reasons",{}).is_empty():
		active["wait_doctor" if ticket.kind in ["gp","consult","outpatient"] else "wait_clinical"] = int(ticket.get("waited_ticks",0))
		if not HospitalWaitingLife.is_seated(world,str(visit.id)): active.no_compatible_seat = _clock(world,data,"no_compatible_seat")
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
		var seat_reason: bool = false
		if waiting_life!=null:
			if waiting_life.get_script()==HospitalWaitingLife:
				seat_reason = waiting_life.has_positive_seat_reason(world,visit.id)
			else:
				# Custom waiting services retain their existing summary contract.
				var summary: Dictionary = waiting_life.patient_summary(world,visit.id)
				seat_reason = not summary.get("seat",{}).is_empty() and summary.seat.phase=="seated" and not summary.get("reasons",[]).is_empty()
		if seat_reason: decay += float(content.balance.anger.preferred_seat_decay)
		_anger_change(visit,data,"natural_calm",-decay)

func _update_cause_clocks(world: WorldState, visit: Dictionary, data: Dictionary, observation: Dictionary) -> void:
	var ticket: Dictionary = world.facts.tickets.get(visit.get("ticket_id",""),{})
	var no_seat: bool = not ticket.is_empty() and ticket.get("pause_reasons",{}).is_empty() and not HospitalWaitingLife.is_seated(world,str(visit.id))
	var dirty: bool = not bool(observation.get("clean",true))
	var noisy: bool = float(observation.get("noise",0.0))>0
	var clocks: Dictionary = data.cause_clocks
	if clocks.size()==int(no_seat)+int(dirty)+int(noisy) and (not no_seat or clocks.has("no_compatible_seat")) and (not dirty or clocks.has("dirty")) and (not noisy or clocks.has("construction_noise")): return
	var active: Dictionary = {}
	if no_seat: active.no_compatible_seat = true
	if dirty: active.dirty = true
	if noisy: active.construction_noise = true
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
	var state: Dictionary = world.facts.patient_experience
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

func _window_cases(world: WorldState) -> Array:
	var current_day: int = world.sim_tick/WorldState.TICKS_PER_DAY
	var cases: Array = []
	for record: Dictionary in world.facts.get("patient_experience",{}).get("cases",[]):
		if int(record.day)>=current_day or int(record.day)<maxi(0,current_day-int(content.balance.ratings.window_days)): continue
		cases.append(record)
	return cases.slice(maxi(0,cases.size()-int(content.balance.ratings.case_window_limit)))

func _staff_experience(world: WorldState) -> Variant:
	var staff_values: Dictionary = {}
	var today: int = world.sim_tick/WorldState.TICKS_PER_DAY
	for day_key: String in world.facts.get("patient_experience",{}).get("staff_days",{}):
		if int(day_key)>=today or int(day_key)<maxi(0,today-int(content.balance.ratings.window_days)): continue
		for staff_id: String in world.facts.patient_experience.staff_days[day_key]:
			var daily: Dictionary = world.facts.patient_experience.staff_days[day_key][staff_id]
			if not staff_values.has(staff_id): staff_values[staff_id] = []
			var energy: float = float(daily.energy_total)/maxi(1,int(daily.ticks))
			var coverage: float = 100.0 if int(daily.required_rest_ticks)==0 else minf(1.0,float(daily.rest_ticks)/int(daily.required_rest_ticks))*100.0
			staff_values[staff_id].append(energy*float(content.balance.ratings.staff_energy_weight)+coverage*float(content.balance.ratings.staff_rest_coverage_weight))
	var means: Array = []
	for values: Array in staff_values.values(): means.append(_mean(values))
	return _mean(means) if not means.is_empty() else null

func _prune(world: WorldState) -> void:
	var state: Dictionary = world.facts.patient_experience
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
		for key: String in ["hospital"]:
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

func sample_worker_report() -> Dictionary:
	return _worker_sample_batch.report() if _worker_sample_batch!=null else {"batches":0,"jobs":0,"processed":0,"consumed":0,"failed_batches":0,"threads":{}}

func _environment(world: WorldState, actor_id: String, floor_id: int, cell: Array) -> Dictionary:
	if environment==null: return {"value":float(content.balance.environment.base)+float(content.balance.environment.clean_bonus),"noise":0.0,"clean":true}
	return environment.sample_at(world,floor_id,cell,actor_id) if environment.has_method("sample_at") else environment.environment_at(world,floor_id,cell,actor_id,false)

func _grace_ticks(kind: String) -> int:
	return _ticks(_cause("wait_doctor" if kind in ["gp","consult","outpatient"] else "wait_clinical").grace_seconds)

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

func _natural(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0 and float(value)<=1000000000000.0 and float(value)==floor(float(value))

func _sorted(value: Dictionary) -> Array:
	var keys: Array = value.keys()
	keys.sort()
	return keys

func _ticks(seconds: Variant) -> int:
	return ceili(float(seconds)/WorldState.TICK_SECONDS)
