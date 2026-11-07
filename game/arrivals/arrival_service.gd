class_name HospitalArrivalService
extends RefCounted

const F = preload("res://game/arrivals/exact_fraction.gd")
const Plan = preload("res://game/arrivals/day_plan.gd")
const ResearchJobs = preload("res://game/community/research_job_index.gd")

var content: HospitalContent
var space: HospitalSpace
var clinic: HospitalClinic
var departments: RefCounted
var environment: RefCounted
var development: RefCounted
var _research_jobs: RefCounted = ResearchJobs.new()
var _scheduled: Dictionary = {}
var _next_due: int = -1
var _indexed_world: int = 0
var _events: Array[SimEvent] = []
var _slot_world: int = 0
var _slot_plan: Dictionary = {}
var _slot_basis: Array = []
var _slot_due: int = -1

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry
	clinic = HospitalClinic.new(content,space)

func ensure(world: WorldState) -> void:
	if not world.facts.has("arrivals"):
		world.facts.arrivals = {"intake_open":true,"preset":"normal","next_preset":"normal",
			"mode":"follow_capacity","next_mode":"follow_capacity","held_capacity_fraction":F.make(),
			"held_scale_numerator":0,"disease_weights":{},"plan":{},"daily_stats":{}}
	for collection: String in ["residents","wait_departures"]:
		if not world.facts.has(collection):
			world.facts[collection] = {}
	if not world.facts.has("hospital_meta"):
		world.facts.hospital_meta = {}
	if not world.facts.hospital_meta.has("tutorial_flags"):
		var requests: Dictionary = {}
		for step: Dictionary in content.catalog.get("onboarding_steps",[]):
			if step.get("patient_seed") is Dictionary:
				requests[step.id] = {"state":"pending","visit_id":""}
		world.facts.hospital_meta.tutorial_flags = {"enabled":true,"requests":requests}

func execute(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	ensure(world)
	var settings: Dictionary = world.facts.arrivals
	match kind:
		"arrivals_intake", "set_intake_open":
			if not payload.get("open") is bool:
				return _reject(world,"invalid_payload","请选择是否开始新接诊")
			settings.intake_open = payload.open
		"arrivals_preset":
			if not content.balance.arrival_presets.has(payload.get("preset","")):
				return _reject(world,"invalid_preset","未定义的来客档位")
			settings.next_preset = payload.preset
		"arrivals_scale":
			var mode: String = str(payload.get("mode",""))
			if not mode in ["follow_capacity","hold_capacity"]:
				return _reject(world,"invalid_scale_mode","请选择随医院成长或保持当前客流")
			if mode == "hold_capacity":
				var projection: Dictionary = capacity(world,false)
				settings.held_capacity_fraction = projection.capacity.duplicate(true)
				settings.held_scale_numerator = projection.scale_numerator
			settings.next_mode = mode
		"arrivals_weight":
			var disease_id: String = str(payload.get("disease_id",""))
			var weight: Variant = payload.get("weight")
			if content.definition("diseases",disease_id).is_empty() or not _natural(weight) or int(weight) > 3:
				return _reject(world,"invalid_disease_weight","接诊权重必须为0、1、2或3")
			settings.disease_weights[disease_id] = int(weight)
		"resident_remember", "resident_forget":
			return _remember(world,payload,kind == "resident_remember")
		"tutorial_skip_request":
			var requests: Dictionary = world.facts.hospital_meta.tutorial_flags.requests
			var step_id: String = str(payload.get("step_id",""))
			if not requests.has(step_id):
				return _reject(world,"tutorial_request_missing","教学来院请求不存在")
			if requests[step_id].state == "pending":
				requests[step_id].state = "skipped"
		"tutorial_set_enabled":
			if not payload.get("enabled") is bool:
				return _reject(world,"invalid_payload","引导开关类型无效")
			var flags: Dictionary = world.facts.hospital_meta.tutorial_flags
			flags.enabled = payload.enabled
			if not flags.enabled:
				for request: Dictionary in flags.requests.values():
					if request.state == "pending":
						request.state = "cancelled"
		_:
			return _reject(world,"unknown_command","未知来客命令")
	return CommandResult.new(true,"applied","",["arrivals"],world.revision)

# Random interest is immediate; there is no background capacity computation.
func dispose() -> void:
	pass

func boundaries(world: WorldState) -> bool:
	ensure(world)
	var settings: Dictionary = world.facts.arrivals
	var day: int = world.sim_tick/WorldState.TICKS_PER_DAY+1
	if not settings.plan.is_empty() and int(settings.plan.day_index) == day:
		return true
	var projection: Dictionary = capacity(world)
	settings.preset = settings.next_preset
	settings.mode = settings.next_mode
	var capacities: Array = projection.shift_capacities.duplicate(true)
	var effective: Dictionary = projection.capacity
	var scale: int = int(projection.scale_numerator)
	if settings.mode == "hold_capacity":
		effective = F.minimum(effective,settings.held_capacity_fraction)
		scale = mini(scale,int(settings.held_scale_numerator))
		if projection.capacity.n != "0":
			var factor: Dictionary = F.div(effective,projection.capacity)
			for shift: int in 3:
				capacities[shift] = F.mul(capacities[shift],factor)
	var preset: Dictionary = content.balance.arrival_presets[settings.preset]
	var count: int = Plan.sample_count(world,effective,preset)
	var seed: Variant = Plan.draw_seed(world) if count > 0 else null
	var allocation: Array = Plan.allocate_shifts(day,str(seed),count,capacities)
	settings.plan = {"day_index":day,"preset":settings.preset,"scale_numerator":scale,
		"shift_capacities":capacities,"opportunity_count":count,"shift_opportunity_counts":allocation,
		"schedule_seed":seed,"schedule_algorithm":content.balance.arrivals.schedule.algorithm,"next_slot_index":0,
		"held_capacity_fraction":settings.held_capacity_fraction.duplicate(true),"held_scale_numerator":settings.held_scale_numerator}
	_stat(world,day)
	_events.append(SimEvent.new(world.sim_tick,"arrival_day_planned",[],{"day_index":day,"opportunities":count,"capacity":effective}))
	return true

func _next_slot_tick(world: WorldState, plan: Dictionary, index: int) -> int:
	var basis: Array = [plan.day_index,plan.opportunity_count,str(plan.schedule_seed),plan.schedule_algorithm,plan.shift_opportunity_counts,index]
	if _slot_world!=world.get_instance_id() or not is_same(_slot_plan,plan) or _slot_basis!=basis:
		_slot_world = world.get_instance_id()
		_slot_plan = plan
		_slot_basis = basis.duplicate(true)
		_slot_due = Plan.slot_tick(plan,index)
	return _slot_due

func arrivals(world: WorldState) -> void:
	ensure(world)
	var settings: Dictionary = world.facts.arrivals
	var plan: Dictionary = settings.plan
	if plan.is_empty():
		return
	if int(plan.day_index) != world.sim_tick/WorldState.TICKS_PER_DAY+1:
		return
	var day_tick: int = world.sim_tick%WorldState.TICKS_PER_DAY
	while int(plan.next_slot_index) < int(plan.opportunity_count):
		var index: int = int(plan.next_slot_index)
		if _next_slot_tick(world,plan,index) > day_tick:
			break
		# Cursor consumption and a successful admission are part of this same step.
		plan.next_slot_index += 1
		var statistics: Dictionary = _stat(world,int(plan.day_index))
		statistics.opportunities += 1
		if not settings.intake_open:
			statistics.closed += 1
			continue
		if outpatient_count(world) >= outpatient_allowance(plan):
			statistics.full += 1
			continue
		var tutorial: Dictionary = _tutorial_request(world)
		var chosen: Dictionary = {}
		if not tutorial.is_empty():
			# Teaching asks for one known case, not a hospital-wide feasibility scan.
			chosen = _tutorial_candidate(world,tutorial)
		else:
			var candidates: Array = _admission_candidates(world)
			if not candidates.is_empty(): chosen = _choose_case(world,candidates)
		if chosen.is_empty():
			statistics.unready += 1
			continue
		var resident: Dictionary = _returning_resident(world,str(chosen.species_id),str(chosen.binding_id))
		var new_resident: bool = resident.is_empty()
		if new_resident:
			resident = _new_identity(world,str(chosen.species_id))
		var expression: String = _expression(world)
		var result: CommandResult = clinic.call("execute",world,"clinical_arrive",{
			"arrival_key":"day:%d:slot:%d" % [int(plan.day_index),index],"binding_id":chosen.binding_id,
			"complex":chosen.complex,"resident_id":resident.id,"name":resident.name,
			"personality_id":resident.personality_id,"expression":expression})
		if not result.accepted:
			statistics.unready += 1
			continue
		if new_resident:
			world.facts.residents[resident.id] = resident
		var visit: Dictionary = _result_visit(world,result)
		if visit.is_empty():
			continue
		var actor: Dictionary = world.facts.actors[visit.actor_id]
		actor.resident_id = resident.id
		actor.appearance = resident.appearance.duplicate(true)
		visit.arrival_day_index = int(plan.day_index)
		visit.arrival_slot_index = index
		visit.arrival_tick = world.sim_tick
		visit.last_progress_tick = world.sim_tick
		visit.last_service_tick = world.sim_tick
		visit.departure_recorded = false
		if not tutorial.is_empty():
			visit.tutorial_success_pending = true
			visit.tutorial_step_id = tutorial.step_id
			var request: Dictionary = world.facts.hospital_meta.tutorial_flags.requests[tutorial.step_id]
			request.state = "admitted"
			request.visit_id = visit.id
		resident.current_actor_id = actor.id
		statistics.arrived += 1
		_events.append(SimEvent.new(world.sim_tick,"arrival_opportunity_admitted",[visit.id,actor.id],{"resident_id":resident.id,"returning":not new_resident,"slot_index":index}))

func advance_wait(world: WorldState) -> void:
	ensure(world)
	for ticket_id: String in world.ids("tickets"):
		var ticket: Dictionary = world.facts.tickets[ticket_id]
		var visit: Dictionary = world.facts.visits.get(ticket.visit_id,{})
		if visit.is_empty():
			continue
		var state: Dictionary = _departure_state(world,visit,ticket)
		if not ticket.has("waited_ticks"):
			ticket.waited_ticks = maxi(0,world.sim_tick-int(ticket.enqueued_tick))
		if not state.selected and _eligible_wait(world,visit,ticket) and int(ticket.get("wait_accounted_tick",-1)) != world.sim_tick:
			ticket.waited_ticks += 1
			ticket.wait_accounted_tick = world.sim_tick

# Run after the current tick's department/anger sample. This phase consumes
# the original queue clock; it never advances a second waiting clock.
func needs(world: WorldState) -> void:
	ensure(world)
	if _indexed_world != world.get_instance_id():
		_scheduled.clear()
		_next_due = -1
		_indexed_world = world.get_instance_id()
	var active_tickets: Dictionary = {}
	for ticket_id: String in world.ids("tickets"):
		var ticket: Dictionary = world.facts.tickets[ticket_id]
		var visit: Dictionary = world.facts.visits.get(ticket.visit_id,{})
		if visit.is_empty():
			continue
		var actor_id: String = str(visit.actor_id)
		var state: Dictionary = _departure_state(world,visit,ticket)
		active_tickets[ticket_id] = true
		if not ticket.has("waited_ticks"):
			_unschedule(ticket_id)
			continue
		if not _eligible_wait(world,visit,ticket) or state.selected:
			_unschedule(ticket_id)
			continue
		var reason: String = _deterministic_exit(world,visit,ticket)
		if not reason.is_empty():
			_depart_wait(world,visit,ticket,state,reason)
			continue
		_schedule(ticket_id,actor_id,world.sim_tick+maxi(0,int(state.next_check_wait_ticks)-int(ticket.waited_ticks)),int(state.next_check_wait_ticks))
	for ticket_id: String in _scheduled.keys():
		if not active_tickets.has(ticket_id):
			_unschedule(ticket_id)
	for actor_id: String in world.facts.wait_departures.keys():
		var old: Dictionary = world.facts.wait_departures[actor_id]
		if not old.selected and not active_tickets.has(old.ticket_id):
			world.facts.wait_departures.erase(actor_id)
	if _next_due < 0 or _next_due > world.sim_tick:
		return
	var due: Array = []
	for ticket_id: String in _scheduled:
		if int(_scheduled[ticket_id].due_tick) <= world.sim_tick:
			due.append(_scheduled[ticket_id].duplicate())
	due.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.actor_id < b.actor_id if a.actor_id != b.actor_id else a.ticket_id < b.ticket_id)
	for entry: Dictionary in due:
		var ticket_id: String = entry.ticket_id
		_unschedule(ticket_id)
		var ticket: Dictionary = world.facts.tickets.get(ticket_id,{})
		var state: Dictionary = world.facts.wait_departures.get(entry.actor_id,{})
		if ticket.is_empty() or state.is_empty() or state.ticket_id != ticket_id or int(state.next_check_wait_ticks) != int(entry.threshold):
			continue
		var visit: Dictionary = world.facts.visits.get(ticket.visit_id,{})
		if visit.is_empty() or state.selected or not _eligible_wait(world,visit,ticket):
			continue
		if int(ticket.waited_ticks) < int(state.next_check_wait_ticks):
			continue
		# Advance the one original threshold before consuming its one random sign.
		state.next_check_wait_ticks += _ticks(content.balance.wait_departure.check_interval_seconds)
		var probability: int = patience_probability(world,visit,ticket)
		var roll: int = world.draw(str(content.balance.wait_departure.rng_stream),10000)
		_events.append(SimEvent.new(world.sim_tick,"patience_evaluated",[visit.id,ticket_id],{"waited_ticks":ticket.waited_ticks,"probability_bp":probability,"roll":roll}))
		if roll < probability:
			_depart_wait(world,visit,ticket,state,"wait_departure")
		else:
			_schedule(ticket_id,str(visit.actor_id),world.sim_tick+maxi(0,int(state.next_check_wait_ticks)-int(ticket.waited_ticks)),int(state.next_check_wait_ticks))

func _departure_state(world: WorldState, visit: Dictionary, ticket: Dictionary) -> Dictionary:
	var state: Dictionary = world.facts.wait_departures.get(visit.actor_id,{})
	if state.is_empty() or state.ticket_id != ticket.id:
		state = {"ticket_id":ticket.id,"next_check_wait_ticks":_ticks(content.balance.wait_departure.first_check_seconds),"selected":false,"reason":""}
		world.facts.wait_departures[visit.actor_id] = state
	return state

func settle(world: WorldState) -> void:
	ensure(world)
	for visit_id: String in world.active_visit_ids():
		var visit: Dictionary = world.facts.visits[visit_id]
		var actor: Dictionary = world.facts.actors[visit.actor_id]
		if actor.location.kind != "outside" or visit.get("departure_recorded",false) or visit.phase != "departed":
			continue
		visit.departure_recorded = true
		visit.departure_tick = world.sim_tick
		if development!=null: development.call("queue_case",world,visit)
		else: world.fact_record_changed("visits",visit_id)
		var statistics: Dictionary = _stat(world,world.sim_tick/WorldState.TICKS_PER_DAY+1)
		statistics.departed += 1
		if visit.get("final_result","") in ["cured","success","referred","failed"]:
			statistics.completed += 1
		elif visit.get("final_result","") in ["abandoned","departing_wait","wait_departure"]:
			statistics.abandoned += 1
		var resident_id: String = str(actor.get("resident_id",""))
		if world.facts.residents.has(resident_id):
			var resident: Dictionary = world.facts.residents[resident_id]
			resident.last_departure_tick = int(visit.get("departed_tick",world.sim_tick))
			resident.current_actor_id = ""
			resident.visits_completed += 1
			resident.last_visit_id = visit_id
			resident.memories.append({"visit_id":visit_id,"disease_id":visit.disease_id,"result":visit.get("final_result",""),"departure_tick":world.sim_tick})
			var history_limit: int = int(content.balance.limits.history_entries)
			while resident.memories.size() > history_limit:
				resident.memories.pop_front()
		world.facts.wait_departures.erase(visit.actor_id)
	var protection: Variant = null
	for resident_id: String in world.ids("residents"):
		var resident: Dictionary = world.facts.residents[resident_id]
		if not (resident.get("pending_release",false) or not resident.get("remembered",false)): continue
		if not resident.get("story_binding","").is_empty(): continue
		var current: Dictionary = world.facts.actors.get(str(resident.get("current_actor_id","")),{})
		if current.get("resident_id","")==resident_id and current.get("location",{}).get("kind","outside")!="outside": continue
		if protection==null: protection = _resident_protection(world)
		if _protected_reasons(world,resident,false,protection).is_empty():
			_release_identity(world,resident_id)

func outpatient_count(world: WorldState) -> int:
	var bed_visits: Dictionary = {}
	for preparation: Dictionary in world.facts.preparations.values():
		if world.facts.facilities.has(preparation.get("bed_id","")):
			bed_visits[preparation.visit_id] = true
	for stay: Dictionary in world.facts.ward_stays.values():
		var attempt: Dictionary = world.facts.attempts.get(stay.get("attempt_id",""),{})
		if not attempt.is_empty() and world.facts.facilities.has(stay.get("bed_id","")):
			bed_visits[attempt.visit_id] = true
	for session: Dictionary in world.facts.sessions.values():
		if session.get("kind","") in ["surgery","wake"]:
			var visit: Dictionary = world.facts.visits.get(session.visit_id,{})
			if world.facts.facilities.has(visit.get("reserved_bed_id","")):
				bed_visits[session.visit_id] = true
	var counted_actors: Dictionary = {}
	for visit_id: String in world.active_visit_ids():
		var visit: Dictionary = world.facts.visits[visit_id]
		var actor: Dictionary = world.facts.actors.get(visit.actor_id,{})
		if not actor.is_empty() and actor.location.kind != "outside" and not bed_visits.has(visit.id):
			counted_actors[visit.actor_id] = true
	return counted_actors.size()

func outpatient_allowance(plan: Dictionary) -> int:
	if plan.is_empty():
		return 0
	return int(content.balance.arrivals.random_demand.concurrent_outpatients_per_open_gp_desk)*int(plan.scale_numerator)

func patience_probability(world: WorldState, visit: Dictionary, ticket: Dictionary) -> int:
	var rules: Dictionary = content.balance.wait_departure
	var waited_seconds: float = float(ticket.get("waited_ticks",0))*WorldState.TICK_SECONDS
	var probability: float = float(rules.base_probability)+float(rules.per_extra_wait_second)*maxf(0,waited_seconds-float(rules.first_check_seconds))
	probability += float(rules.per_extra_anger)*maxf(0,float(visit.get("anger",0))-float(rules.anger_threshold))
	probability *= float(content.definition("patient_personalities",visit.personality_id).get("wait_leave_multiplier",1))
	var environment: float = _environment_score(world,visit)
	for buffer: Dictionary in content.balance.environment.anger_buffer:
		if environment >= float(buffer.min_value):
			probability *= float(buffer.multiplier)
			break
	return int(floor(clampf(probability,float(rules.probability_min),float(rules.probability_max))*10000.0+0.5))

func daystats(world: WorldState) -> Dictionary:
	var settings: Dictionary = world.facts.get("arrivals",{})
	var result: Dictionary = settings.get("daily_stats",{}).duplicate(true)
	var demand: Dictionary = capacity(world)
	var effective: Dictionary = demand.capacity
	if settings.get("next_mode","follow_capacity")=="hold_capacity": effective = F.minimum(effective,settings.held_capacity_fraction)
	var tomorrow: Array = Plan.count_range(effective,content.balance.arrival_presets[str(settings.get("next_preset","normal"))])
	return {"days":result,"plan":settings.get("plan",{}).duplicate(true),"outpatients":outpatient_count(world),"open_desks":demand.desk_count,"tomorrow_range":tomorrow,
		"allowance":outpatient_allowance(settings.get("plan",{})),"intake_open":settings.get("intake_open",true),
		"today_preset":settings.get("preset","normal"),"tomorrow_preset":settings.get("next_preset","normal"),"tomorrow_mode":settings.get("next_mode","follow_capacity")}

func residents(world: WorldState) -> Array:
	var result: Array = []
	for resident_id: String in world.facts.get("residents",{}):
		var resident: Dictionary = world.facts.residents[resident_id]
		if resident.get("remembered",false) or not resident.get("story_binding","").is_empty() or resident.get("pending_release",false):
			var record: Dictionary = resident.duplicate(true)
			record.protected_reasons = _protected_reasons(world,resident)
			result.append(record)
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.id < b.id)
	return result

func take_events() -> Array[SimEvent]:
	var result: Array[SimEvent] = _events
	_events = []
	return result

# Six daily opportunities and sixteen concurrent outpatients per open GP desk
# are provisional pacing values, not promises of completed treatment.
func demand_desks(world: WorldState) -> int:
	var count: int = 0
	var units: Dictionary = world.facts.get("departments",{}).get("units",{})
	for id: String in world.facility_ids("FUR02"):
		var desk: Dictionary = world.facts.facilities[id]
		var room: Dictionary = world.facts.rooms.get(str(desk.get("room_id","")),{})
		if room.is_empty() or not bool(room.get("open",true)) or not bool(desk.get("open",true)) or not bool(desk.get("intake_open",true)):
			continue
		if HospitalRemodel.blocked(world,id): continue
		var owned: bool = false
		var open_owner: bool = false
		for department: Dictionary in units.values():
			if desk.room_id in department.get("room_ids",[])+department.get("shared_room_ids",[]):
				owned = true
				open_owner = open_owner or bool(department.get("open",true))
		if owned and not open_owner: continue
		count += 1
	return count

func capacity(world: WorldState, _subtract_existing: bool = true, _cancellation: Callable = Callable()) -> Dictionary:
	# Kept as the read-only UI projection entry point, now a demand estimate.
	# Busy/missing staff, broken treatment equipment and old patients do not
	# suppress residents' interest. Their consequences happen during real care.
	var desks: int = demand_desks(world)
	var interest: int = int(content.balance.arrivals.random_demand.daily_interest_per_open_gp_desk)
	var total: Dictionary = F.make(desks*interest)
	var shift: Dictionary = F.make(desks*interest,3)
	var preset: Dictionary = content.balance.arrival_presets[str(world.facts.get("arrivals",{}).get("next_preset","normal"))]
	return {"complete":true,"capacity":total,"shift_capacities":[shift.duplicate(),shift.duplicate(),shift.duplicate()],
		"scale_numerator":desks,"desk_count":desks,"reference_average":F.mul(total,F.make(preset.target_load_bp,10000)),
		"tomorrow_range":Plan.count_range(total,preset)}

func _admission_candidates(world: WorldState) -> Array:
	# Interest depends on unlocked diseases and the player's weights. Actual
	# reception, diagnosis and treatment decide what can happen after arrival.
	var candidates: Array = []
	var seen: Dictionary = {}
	for binding: Dictionary in content.catalog.get("treatment_bindings",[]):
		var key: String = str(binding.species_id)+"|"+str(binding.disease_id)
		if seen.has(key) or _disease_weight(world,str(binding.disease_id))==0: continue
		seen[key] = true
		candidates.append({"binding_id":binding.id,"disease_id":binding.disease_id,"species_id":binding.species_id,"variants":_arrival_variants(world,str(binding.disease_id))})
	return candidates

func _arrival_variants(world: WorldState, disease_id: String) -> Array:
	# Research controls when the complex-case feature opens, not whether this
	# hospital can already execute a future treatment for a randomly drawn visit.
	if "R34" in world.facts.research and not content.definition("treatment_plans","P_"+disease_id+"_SURGERY").is_empty(): return [false,true]
	return [false]

func _tutorial_candidate(world: WorldState, request: Dictionary) -> Dictionary:
	if _disease_weight(world,str(request.disease_id))==0: return {}
	for binding: Dictionary in content.catalog.get("treatment_bindings",[]):
		if binding.species_id==request.species_id and binding.disease_id==request.disease_id:
			return {"binding_id":binding.id,"disease_id":binding.disease_id,"species_id":binding.species_id,"complex":false}
	return {}

func _choose_case(world: WorldState, candidates: Array) -> Dictionary:
	var diseases: Dictionary = {}
	for candidate: Dictionary in candidates:
		if not diseases.has(candidate.disease_id):
			diseases[candidate.disease_id] = []
		diseases[candidate.disease_id].append(candidate)
	var disease_ids: Array = diseases.keys()
	disease_ids.sort()
	var weight: int = 0
	for disease_id: String in disease_ids:
		weight += _disease_weight(world,disease_id)
	var chosen_weight: int = int(Plan.uniform_decimal(world,str(weight)))
	var disease: String = ""
	for disease_id: String in disease_ids:
		chosen_weight -= _disease_weight(world,disease_id)
		if chosen_weight < 0:
			disease = disease_id
			break
	var species_candidates: Array = diseases[disease]
	species_candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.species_id < b.species_id)
	var candidate: Dictionary = species_candidates[int(Plan.uniform_decimal(world,str(species_candidates.size())))].duplicate(true)
	candidate.complex = bool(candidate.variants[0])
	if candidate.variants.size() > 1:
		candidate.complex = int(Plan.uniform_decimal(world,"10000")) < roundi(float(content.balance.clinical.complex_probability)*10000)
	return candidate

func _disease_weight(world: WorldState, disease_id: String) -> int:
	if not HospitalResearch.disease_unlocked(world,content,disease_id,_research_jobs.view(world)):
		return 0
	return int(world.facts.get("arrivals",{}).get("disease_weights",{}).get(disease_id,1))

func _tutorial_request(world: WorldState) -> Dictionary:
	var flags: Dictionary = world.facts.get("hospital_meta",{}).get("tutorial_flags",{})
	if not flags.get("enabled",false):
		return {}
	var steps: Array = content.catalog.get("onboarding_steps",[]).duplicate()
	steps.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.order) < int(b.order))
	for step: Dictionary in steps:
		if step.get("patient_seed") is Dictionary and flags.get("requests",{}).get(step.id,{}).get("state","") == "pending":
			var request: Dictionary = step.patient_seed.duplicate()
			request.step_id = step.id
			return request
	return {}

func _new_identity(world: WorldState, species_id: String) -> Dictionary:
	var id: String = world.new_id("resident")
	var identity_number: String = Plan.uniform_decimal(world,"1000000000")
	var personality_id: String = _personality(world)
	return {"id":id,"name":str(content.definition("species",species_id).name)+"居民"+identity_number.right(4),
		"species_id":species_id,"personality_id":personality_id,
		"appearance":{"identity_variant":Plan.uniform_decimal(world,"1000000000")},"relationships":{},
		"remembered":false,"pending_release":false,"story_binding":"","current_actor_id":"",
		"last_departure_tick":-1,"last_visit_id":"","visits_completed":0,"memories":[]}

func _personality(world: WorldState) -> String:
	var profiles: Array = content.catalog.get("patient_personalities",[])
	var total: int = 0
	for profile: Dictionary in profiles:
		total += int(profile.probability_percent)
	var roll: int = world.draw("personality",total)
	for profile: Dictionary in profiles:
		roll -= int(profile.probability_percent)
		if roll < 0:
			return profile.id
	return "PP01"

func _expression(world: WorldState) -> String:
	var roll: int = world.draw("personality",10000)
	for state: Dictionary in content.balance.consultation.communication_states:
		roll -= roundi(float(state.probability)*10000)
		if roll < 0:
			return state.id
	return "clear"

func _returning_resident(world: WorldState, species_id: String, binding_id: String) -> Dictionary:
	var candidates: Array = []
	var protection: Variant = null
	var minimum: int = int(content.balance.resident_returns.minimum_absence_days)*WorldState.TICKS_PER_DAY
	for resident_id: String in world.ids("residents"):
		var resident: Dictionary = world.facts.residents[resident_id]
		if resident.species_id != species_id or not resident.get("remembered",false) or resident.get("pending_release",false):
			continue
		if int(resident.get("last_departure_tick",-1)) < 0 or world.sim_tick-int(resident.last_departure_tick) < minimum:
			continue
		if protection==null: protection = _resident_protection(world)
		if not _protected_reasons(world,resident,true,protection).is_empty():
			continue
		var binding: Dictionary = content.definition("treatment_bindings",binding_id)
		if binding.get("species_id","") != resident.species_id:
			continue
		candidates.append(resident)
	if candidates.is_empty():
		return {}
	if int(Plan.uniform_decimal(world,"10000")) >= roundi(float(content.balance.resident_returns.probability)*10000):
		return {}
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return int(a.last_departure_tick) < int(b.last_departure_tick) if a.last_departure_tick != b.last_departure_tick else a.id < b.id)
	return candidates[0]

func _remember(world: WorldState, payload: Dictionary, remembered: bool) -> CommandResult:
	var resident_id: String = str(payload.get("resident_id",""))
	if resident_id.is_empty():
		var actor_id: String = str(payload.get("actor_id",""))
		resident_id = str(world.facts.actors.get(actor_id,{}).get("resident_id",""))
	var resident: Dictionary = world.facts.residents.get(resident_id,{})
	if resident.is_empty():
		return _reject(world,"resident_missing","该居民已经离开名册，历史文字不能生成回访身份")
	if remembered and not resident.get("remembered",false):
		var count: int = 0
		for existing: Dictionary in world.facts.residents.values():
			if existing.get("remembered",false) or not existing.get("story_binding","").is_empty() or existing.get("pending_release",false):
				count += 1
		if count >= int(content.balance.limits.regulars):
			return _reject(world,"resident_book_full","熟客名册已满，请先整理一位普通熟客")
	resident.remembered = remembered
	resident.pending_release = not remembered
	if not remembered and _protected_reasons(world,resident).is_empty():
		_release_identity(world,resident_id)
	return CommandResult.new(true,"applied","",[resident_id],world.revision)

func _resident_protection(world: WorldState) -> Dictionary:
	# References are shared only inside one synchronous settlement/candidate scan.
	# Release changes the resident book, never these actors, visits or activity lists.
	var index: Dictionary = {"actors":{},"visits":{},"references":{}}
	for actor: Dictionary in world.facts.actors.values():
		var resident_id: String = str(actor.get("resident_id",""))
		if resident_id.is_empty(): continue
		if not index.actors.has(resident_id): index.actors[resident_id] = []
		index.actors[resident_id].append(actor)
	for visit: Dictionary in world.facts.visits.values():
		if visit.phase=="departed": continue
		if not index.visits.has(visit.actor_id): index.visits[visit.actor_id] = []
		index.visits[visit.actor_id].append(visit)
	for collection: String in ["activities","community_activities","interactions","visitor_stays","care_jobs"]:
		for record: Dictionary in world.facts.get(collection,{}).values():
			if record.get("state",record.get("phase","")) in ["completed","cancelled","ended","departed"]: continue
			var members: Dictionary = {}
			for resident_id: String in record.get("resident_ids",record.get("participants",[])): members[resident_id] = true
			var owner: String = str(record.get("resident_id",""))
			if not owner.is_empty(): members[owner] = true
			for resident_id: String in members:
				if not index.references.has(resident_id): index.references[resident_id] = []
				index.references[resident_id].append(record)
	return index

func _protected_reasons(world: WorldState, resident: Dictionary, ignore_story: bool = false, protection: Variant = null) -> Array:
	var reasons: Array = []
	var resident_id: String = resident.id
	var actors: Array = world.facts.actors.values() if protection==null else protection.actors.get(resident_id,[])
	for actor: Dictionary in actors:
		if actor.get("resident_id","") != resident_id:
			continue
		if actor.location.kind != "outside":
			reasons.append("本次实际离院后腾出位置")
		if world.facts.staff.has(actor.id):
			reasons.append("当前员工身份")
		var visits: Array = world.facts.visits.values() if protection==null else protection.visits.get(actor.id,[])
		for visit: Dictionary in visits:
			if visit.actor_id == actor.id and visit.phase != "departed":
				reasons.append("当前就诊尚未结束")
	var references: Array = []
	if protection==null:
		for collection: String in ["activities","community_activities","interactions","visitor_stays","care_jobs"]:
			references.append_array(world.facts.get(collection,{}).values())
	else: references = protection.references.get(resident_id,[])
	for record: Dictionary in references:
		if record.get("state",record.get("phase","")) in ["completed","cancelled","ended","departed"]:
			continue
		var participants: Array = record.get("resident_ids",record.get("participants",[]))
		if resident_id in participants or record.get("resident_id","") == resident_id:
			reasons.append("仍关联活动、互动或照护")
	if not ignore_story and not resident.get("story_binding","").is_empty():
		reasons.append("故事保留同一人物身份")
	return reasons

func _release_identity(world: WorldState, resident_id: String) -> void:
	world.facts.residents.erase(resident_id)
	for resident: Dictionary in world.facts.residents.values():
		resident.get("relationships",{}).erase(resident_id)
		for memory: Dictionary in resident.get("memories",[]):
			if memory.get("callback_resident_id","") == resident_id:
				memory.erase("callback_resident_id")
	for relationship_id: String in world.facts.get("relationships",{}).keys():
		var relation: Dictionary = world.facts.relationships[relationship_id]
		if relation.get("first_id","") == resident_id or relation.get("second_id","") == resident_id:
			world.facts.relationships.erase(relationship_id)

func _eligible_wait(world: WorldState, visit: Dictionary, ticket: Dictionary) -> bool:
	if not visit.phase in ["wait_reception","wait_gp","wait_spectrum","wait_resonance","wait_test","wait_consult","wait_consultation","wait_outpatient","wait_surgery"]:
		return false
	if not ticket.get("pause_reasons",{}).is_empty() or ticket.get("paused",false):
		return false
	var actor: Dictionary = world.facts.actors.get(visit.actor_id,{})
	if actor.is_empty() or actor.location.kind == "outside":
		return false
	for session: Dictionary in world.facts.sessions.values():
		if session.visit_id == visit.id:
			return false
	for stay: Dictionary in world.facts.ward_stays.values():
		if world.facts.attempts.get(stay.get("attempt_id",""),{}).get("visit_id","") == visit.id:
			return false
	if ticket.get("service_assigned",false) and int(ticket.get("called_tick",-1)) >= 0:
		var move: Dictionary = world.facts.moves.get(visit.actor_id,{})
		if actor.location.kind == "transit":
			return false
		if not move.is_empty() and not move.has("transit_ticket") and not move.get("route_pending",false) and int(move.get("blocked_since",-1)) < 0:
			return false
	return true

func _deterministic_exit(world: WorldState, visit: Dictionary, ticket: Dictionary) -> String:
	var last_service: int = int(visit.get("last_service_tick",visit.get("arrival_tick",ticket.enqueued_tick)))
	var last_progress: int = int(visit.get("last_progress_tick",last_service))
	if float(visit.get("anger",0)) >= float(content.balance.anger.leave_threshold) and world.sim_tick-last_service >= _ticks(content.balance.anger.leave_no_progress_seconds):
		return "anger_no_service"
	if content.balance.wait_departure.has("no_progress_seconds") and world.sim_tick-last_progress >= _ticks(content.balance.wait_departure.no_progress_seconds):
		return "no_progress"
	return ""

func _depart_wait(world: WorldState, visit: Dictionary, ticket: Dictionary, state: Dictionary, reason: String) -> void:
	if state.selected:
		return
	if departments != null:
		departments.call("retire_ticket",world,str(visit.id))
	if not clinic.call("depart_visit",world,str(visit.id),"abandoned"):
		return
	state.selected = true
	state.reason = reason
	state.selected_tick = world.sim_tick
	visit.departure_reason = reason
	visit.departure_waited_ticks = int(ticket.waited_ticks)
	visit.outcome_rating = int(content.balance.wait_departure.outcome_rating)
	_unschedule(str(ticket.id))
	_events.append(SimEvent.new(world.sim_tick,"wait_departure_selected",[visit.id,visit.actor_id],{"reason":reason,"waited_ticks":ticket.waited_ticks}))

func _environment_score(world: WorldState, visit: Dictionary) -> float:
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	if actor.location.kind != "floor":
		return 0.0
	var query: HospitalEnvironment = environment as HospitalEnvironment
	if query==null:
		# Standalone numerical callers use the same personal water contract.
		query = HospitalEnvironment.new(content,space)
		query.waiting_life = HospitalWaitingLife.new(content,space)
	return float(query.sample_at(world,int(actor.location.floor_id),actor.location.cell,str(actor.id)).value)

func _schedule(ticket_id: String, actor_id: String, tick: int, threshold: int) -> void:
	if _scheduled.has(ticket_id) and int(_scheduled[ticket_id].due_tick) == tick and int(_scheduled[ticket_id].threshold) == threshold:
		return
	if _scheduled.has(ticket_id):
		_unschedule(ticket_id)
	_scheduled[ticket_id] = {"ticket_id":ticket_id,"actor_id":actor_id,"due_tick":tick,"threshold":threshold}
	if _next_due < 0 or tick < _next_due:
		_next_due = tick

func _unschedule(ticket_id: String) -> void:
	if not _scheduled.has(ticket_id):
		return
	var tick: int = int(_scheduled[ticket_id].due_tick)
	_scheduled.erase(ticket_id)
	if tick != _next_due:
		return
	_next_due = -1
	for entry: Dictionary in _scheduled.values():
		if _next_due < 0 or int(entry.due_tick) < _next_due:
			_next_due = int(entry.due_tick)

func _stat(world: WorldState, day: int) -> Dictionary:
	var statistics: Dictionary = world.facts.arrivals.daily_stats
	if not statistics.has(str(day)):
		statistics[str(day)] = {"opportunities":0,"arrived":0,"completed":0,"abandoned":0,"departed":0,"closed":0,"full":0,"unready":0}
	return statistics[str(day)]

func _result_visit(world: WorldState, result: CommandResult) -> Dictionary:
	for id: String in result.changed_ids:
		if world.facts.visits.has(id):
			return world.facts.visits[id]
	return {}

func _reject(world: WorldState, code: String, reason: String) -> CommandResult:
	return CommandResult.new(false,code,reason,[],world.revision)

func _ticks(seconds: Variant) -> int:
	return roundi(float(seconds)/WorldState.TICK_SECONDS)

static func _natural(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and float(value) == floor(float(value))

static func validate_snapshot(facts: Dictionary, database: HospitalContent) -> String:
	for collection: String in ["arrivals","residents","wait_departures"]:
		if not facts.get(collection) is Dictionary:
			return "来客快照缺少映射："+collection
	var settings: Dictionary = facts.arrivals
	for field: String in ["preset","next_preset"]:
		if not settings.get(field) is String or not database.balance.arrival_presets.has(settings[field]):
			return "来客档位无效："+field
	for field: String in ["mode","next_mode"]:
		if not settings.get(field) in ["follow_capacity","hold_capacity"]:
			return "来客规模模式无效"
	if not settings.get("intake_open") is bool or not settings.get("disease_weights") is Dictionary or not settings.get("daily_stats") is Dictionary:
		return "来客接诊开关或统计结构无效"
	if not F.valid(settings.get("held_capacity_fraction")) or not _natural(settings.get("held_scale_numerator")):
		return "冻结客流偏好无效"
	for disease_id: Variant in settings.disease_weights:
		var weight: Variant = settings.disease_weights[disease_id]
		if not disease_id is String or database.definition("diseases",disease_id).is_empty() or not _natural(weight) or int(weight) > 3:
			return "病例接诊权重引用无效"
	var plan_error: String = Plan.validate(settings.get("plan"))
	if not plan_error.is_empty():
		return plan_error
	if not settings.plan.is_empty():
		if not database.balance.arrival_presets.has(settings.plan.preset):
			return "冻结来客档位未定义"
		if int(settings.plan.day_index) > int(facts.sim_tick)/WorldState.TICKS_PER_DAY+1:
			return "来客计划不能属于未来医院日"
		if not F.valid(settings.plan.get("held_capacity_fraction")) or not _natural(settings.plan.get("held_scale_numerator")):
			return "来客计划冻结偏好无效"
	for day_key: Variant in settings.daily_stats:
		if not day_key is String or not str(day_key).is_valid_int() or int(day_key) < 1 or not settings.daily_stats[day_key] is Dictionary:
			return "来客日统计索引无效"
		var day: Dictionary = settings.daily_stats[day_key]
		for field: String in ["opportunities","arrived","completed","abandoned","departed","closed","full","unready"]:
			if not _natural(day.get(field)):
				return "来客日统计数无效"
		if int(day.arrived)+int(day.closed)+int(day.full)+int(day.unready) != int(day.opportunities) or int(day.completed)+int(day.abandoned) > int(day.departed):
			return "来客日统计守恒无效"
	var retained: int = 0
	var first: int = roundi(float(database.balance.wait_departure.first_check_seconds)/WorldState.TICK_SECONDS)
	var interval: int = roundi(float(database.balance.wait_departure.check_interval_seconds)/WorldState.TICK_SECONDS)
	for ticket: Dictionary in facts.tickets.values():
		if ticket.has("waited_ticks") and not _natural(ticket.waited_ticks):
			return "原票号有效候诊量无效"
		if ticket.has("wait_accounted_tick") and (not _natural(ticket.wait_accounted_tick) or int(ticket.wait_accounted_tick) > int(facts.sim_tick)):
			return "原票号候诊积分边界无效"
		if ticket.has("pause_reasons") and not ticket.pause_reasons is Dictionary:
			return "原票号暂停原因无效"
	for actor_id: Variant in facts.wait_departures:
		var state: Variant = facts.wait_departures[actor_id]
		if not actor_id is String or not facts.actors.has(actor_id) or not state is Dictionary:
			return "弃候状态人物引用无效"
		if not state.get("ticket_id") is String or not _natural(state.get("next_check_wait_ticks")) or not state.get("selected") is bool or not state.get("reason") is String:
			return "弃候状态字段无效"
		if int(state.next_check_wait_ticks) < first or (int(state.next_check_wait_ticks)-first)%interval != 0:
			return "弃候原门槛无效"
		if not state.selected:
			var ticket: Dictionary = facts.tickets.get(state.ticket_id,{})
			if ticket.is_empty() or facts.visits.get(ticket.visit_id,{}).get("actor_id","") != actor_id:
				return "弃候状态不属于当前原票号"
	for resident_id: Variant in facts.residents:
		var resident: Variant = facts.residents[resident_id]
		if not resident_id is String or not resident is Dictionary or resident.get("id") != resident_id:
			return "居民身份索引无效"
		for field: String in ["name","species_id","personality_id","story_binding","current_actor_id","last_visit_id"]:
			if not resident.get(field) is String:
				return "居民身份字段无效："+field
		if database.definition("species",resident.species_id).is_empty() or database.definition("patient_personalities",resident.personality_id).is_empty():
			return "居民种族或性格定义缺失"
		if not resident.get("remembered") is bool or not resident.get("pending_release") is bool or not resident.get("appearance") is Dictionary or not resident.get("relationships") is Dictionary or not resident.get("memories") is Array:
			return "居民记忆结构无效"
		if not _natural(resident.get("visits_completed")) or not (resident.get("last_departure_tick") is int or resident.get("last_departure_tick") is float) or int(resident.last_departure_tick) < -1 or int(resident.last_departure_tick) > int(facts.sim_tick):
			return "居民实际离院时钟无效"
		if not resident.current_actor_id.is_empty():
			var actor: Dictionary = facts.actors.get(resident.current_actor_id,{})
			if actor.is_empty() or actor.get("resident_id","") != resident_id or actor.location.kind == "outside":
				return "居民当前身体引用无效"
		if resident.remembered or resident.pending_release or not resident.story_binding.is_empty():
			retained += 1
		for memory: Variant in resident.memories:
			if not memory is Dictionary or not memory.get("visit_id") is String or not facts.visits.has(memory.visit_id) or not _natural(memory.get("departure_tick")):
				return "居民回访记忆缺少真实就诊事实"
			var past: Dictionary = facts.visits[memory.visit_id]
			if facts.actors[past.actor_id].get("resident_id","") != resident_id or not past.get("departure_recorded",false):
				return "居民记忆不能凭空创建离院"
	if retained > int(database.balance.limits.regulars):
		return "长期居民身份超出名册预算"
	var flags: Variant = facts.get("hospital_meta",{}).get("tutorial_flags")
	if not flags is Dictionary or not flags.get("enabled") is bool or not flags.get("requests") is Dictionary:
		return "开院教学事实缺失"
	for step_id: String in flags.requests:
		var request: Variant = flags.requests[step_id]
		if database.definition("onboarding_steps",step_id).get("patient_seed") == null or not request is Dictionary or not request.get("state") in ["pending","admitted","skipped","cancelled"] or not request.get("visit_id") is String:
			return "教学来院请求无效"
		if request.state == "admitted" and (not facts.visits.has(request.visit_id) or facts.visits[request.visit_id].get("tutorial_step_id","") != step_id):
			return "教学请求缺少一次真实入院"
	return ""
