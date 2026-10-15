class_name HospitalArrivalService
extends RefCounted

const F = preload("res://game/arrivals/exact_fraction.gd")
const Plan = preload("res://game/arrivals/day_plan.gd")
const Solver = preload("res://game/arrivals/capacity_solver.gd")

var content: HospitalContent
var space: HospitalSpace
var clinic: HospitalClinic
var departments: RefCounted
var _scheduled: Dictionary = {}
var _next_due: int = -1
var _indexed_world: int = 0
var _events: Array[SimEvent] = []

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
				if not projection.get("complete",false):
					return _reject(world,"capacity_incomplete",projection.get("reason","完整接诊能力尚未求得"))
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

func boundaries(world: WorldState) -> void:
	ensure(world)
	var settings: Dictionary = world.facts.arrivals
	var day: int = world.sim_tick/WorldState.TICKS_PER_DAY+1
	if not settings.plan.is_empty() and int(settings.plan.day_index) == day:
		return
	var projection: Dictionary = capacity(world,true)
	if not projection.get("complete",false):
		# An incomplete solver result is never frozen as a fictional zero day.
		return
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
		if Plan.slot_tick(plan,index) > day_tick:
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
		var candidates: Array = _admission_candidates(world)
		if candidates.is_empty():
			statistics.unready += 1
			continue
		var tutorial: Dictionary = _tutorial_request(world)
		var chosen: Dictionary = {}
		if not tutorial.is_empty():
			for candidate: Dictionary in candidates:
				if candidate.species_id == tutorial.species_id and candidate.disease_id == tutorial.disease_id and false in candidate.variants:
					chosen = candidate.duplicate(true)
					chosen.complex = false
					break
			if chosen.is_empty():
				statistics.unready += 1
				continue
		else:
			chosen = _choose_case(world,candidates)
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
	for visit_id: String in world.ids("visits"):
		var visit: Dictionary = world.facts.visits[visit_id]
		var actor: Dictionary = world.facts.actors[visit.actor_id]
		if actor.location.kind != "outside" or visit.get("departure_recorded",false) or visit.phase != "departed":
			continue
		visit.departure_recorded = true
		visit.departure_tick = world.sim_tick
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
	for resident_id: String in world.ids("residents"):
		var resident: Dictionary = world.facts.residents[resident_id]
		if (resident.get("pending_release",false) or not resident.get("remembered",false)) and _protected_reasons(world,resident).is_empty():
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
	for visit: Dictionary in world.facts.visits.values():
		var actor: Dictionary = world.facts.actors.get(visit.actor_id,{})
		if not actor.is_empty() and actor.location.kind != "outside" and not bed_visits.has(visit.id):
			counted_actors[visit.actor_id] = true
	return counted_actors.size()

func outpatient_allowance(plan: Dictionary) -> int:
	if plan.is_empty():
		return 0
	return F.ceil_value(F.make(int(content.balance.arrival_presets[plan.preset].active_outpatients_per_scale)*int(plan.scale_numerator),int(content.balance.arrivals.capacity_scaling.reference_shift_pairs)))

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
	return {"days":result,"plan":settings.get("plan",{}).duplicate(true),"outpatients":outpatient_count(world),
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

func capacity(world: WorldState, subtract_existing: bool = true) -> Dictionary:
	if not clinic.has_method("reference_demand"):
		return {"complete":false,"reason":"临床参考报价尚未就绪"}
	if not subtract_existing and world.sim_tick%WorldState.TICKS_PER_DAY != 0:
		world = WorldState.new(world.freeze())
		world.facts.sim_tick = world.sim_tick/WorldState.TICKS_PER_DAY*WorldState.TICKS_PER_DAY
	var shift_capacities: Array = []
	var shift_pairs: Array = []
	var explanations: Array = []
	var total: Dictionary = F.make()
	for shift: int in 3:
		var classes: Array = _reference_classes(world,shift)
		var budgets: Dictionary = _resource_budgets(world,classes,shift)
		if subtract_existing:
			var workload: Dictionary = _existing_workload(world,shift)
			for resource_id: String in workload:
				if budgets.has(resource_id):
					budgets[resource_id] = F.maximum(F.make(),F.sub(F.from_value(budgets[resource_id]),F.from_value(workload[resource_id])))
		var solved: Dictionary = _solve_roles(world,classes,budgets,shift)
		if solved.has("error"):
			return {"complete":false,"reason":solved.bottleneck}
		var structure: int = int(solved.get("structural_pairs",0))
		if structure == 0:
			solved.capacity = F.make()
		shift_capacities.append(solved.capacity)
		shift_pairs.append(structure)
		explanations.append({"shift":shift,"capacity":solved.capacity,"pairs":structure,"bottleneck":solved.bottleneck,
			"resources":budgets.size(),"case_classes":classes.size(),"bundles":solved.get("bundle_count",0)})
		total = F.add(total,solved.capacity)
	var settings: Dictionary = world.facts.get("arrivals",{})
	var preset: Dictionary = content.balance.arrival_presets[str(settings.get("next_preset","normal"))]
	return {"complete":true,"capacity":total,"shift_capacities":shift_capacities,"shift_pairs":shift_pairs,
		"scale_numerator":int(shift_pairs[0])+int(shift_pairs[1])+int(shift_pairs[2]),"shifts":explanations,
		"reference_average":F.mul(total,F.make(preset.target_load_bp,10000)),"tomorrow_range":Plan.count_range(total,preset)}

func _solve_roles(world: WorldState, classes: Array, budgets: Dictionary, shift: int) -> Dictionary:
	var alternatives: Dictionary = {}
	for case: Dictionary in classes:
		for bundle: Dictionary in case.bundles:
			for nurse_id: String in bundle.coverage_roles:
				if not alternatives.has(nurse_id):
					alternatives[nurse_id] = [""]
				for ward_id: String in bundle.coverage_roles[nurse_id]:
					if not ward_id in alternatives[nurse_id]:
						alternatives[nurse_id].append(ward_id)
	var nurse_ids: Array = alternatives.keys()
	nurse_ids.sort()
	return _role_branch(world,classes,budgets,shift,nurse_ids,alternatives,0,{})

func _role_branch(world: WorldState, classes: Array, budgets: Dictionary, shift: int, nurse_ids: Array, alternatives: Dictionary, index: int, roles: Dictionary) -> Dictionary:
	if index < nurse_ids.size():
		var best: Dictionary = {}
		var nurse_id: String = nurse_ids[index]
		var choices: Array = alternatives[nurse_id].duplicate()
		choices.sort()
		var pairs: int = 0
		for ward_id: String in choices:
			roles[nurse_id] = ward_id
			var candidate: Dictionary = _role_branch(world,classes,budgets,shift,nurse_ids,alternatives,index+1,roles)
			pairs = maxi(pairs,int(candidate.get("structural_pairs",0)))
			if best.is_empty() or F.compare(candidate.capacity,best.capacity) > 0:
				best = candidate
		roles.erase(nurse_id)
		best.structural_pairs = pairs
		return best
	var filtered: Array = []
	for case: Dictionary in classes:
		var current: Dictionary = case.duplicate()
		current.bundles = []
		for bundle: Dictionary in case.bundles:
			var valid: bool = true
			for nurse_id: String in roles:
				if bundle.coverage_roles.has(nurse_id):
					if bundle.coverage_roles[nurse_id].size() != 1 or roles[nurse_id] != bundle.coverage_roles[nurse_id][0]:
						valid = false
				elif roles[nurse_id] != "" and bundle.resources.has("staff:"+nurse_id):
					valid = false
			if valid:
				current.bundles.append(bundle)
		filtered.append(current)
	var result: Dictionary = Solver.solve(filtered,budgets)
	result.structural_pairs = _structural_pairs(world,filtered,shift)
	return result

func _reference_classes(world: WorldState, shift: int) -> Array:
	var by_disease: Dictionary = {}
	for binding: Dictionary in content.catalog.get("treatment_bindings",[]):
		if _disease_weight(world,str(binding.disease_id)) == 0:
			continue
		var key: String = str(binding.species_id)+"|"+str(binding.disease_id)
		if not by_disease.has(binding.disease_id):
			by_disease[binding.disease_id] = {}
		var species: Dictionary = by_disease[binding.disease_id]
		if species.has(key):
			continue
		var variants: Array = []
		for complex_case: bool in [false,true]:
			var quote: Dictionary = clinic.call("reference_demand",world,str(binding.id),complex_case,shift)
			if not quote.get("ok",false):
				continue
			var bundles: Array = []
			for source: Dictionary in quote.get("bundles",[]):
				var bundle: Dictionary = _normalize_bundle(world,source)
				bundle.binding_id = str(binding.id)
				if bundle.valid and not bundle.resources.is_empty() and _bundle_available(world,bundle,shift):
					bundles.append(bundle)
			if not bundles.is_empty():
				variants.append({"binding_id":binding.id,"species_id":binding.species_id,"disease_id":binding.disease_id,"complex":complex_case,"bundles":bundles})
		if not variants.is_empty():
			species[key] = variants
	var total_weight: int = 0
	for disease_id: String in by_disease.keys():
		if by_disease[disease_id].is_empty():
			by_disease.erase(disease_id)
		else:
			total_weight += _disease_weight(world,disease_id)
	var result: Array = []
	var disease_ids: Array = by_disease.keys()
	disease_ids.sort()
	for disease_id: String in disease_ids:
		var species: Dictionary = by_disease[disease_id]
		var species_ids: Array = species.keys()
		species_ids.sort()
		for species_key: String in species_ids:
			var variants: Array = species[species_key]
			for variant: Dictionary in variants:
				var probability: Dictionary = F.make(_disease_weight(world,disease_id),total_weight*species.size())
				if variants.size() == 2:
					var complex_probability: Dictionary = F.from_value(content.balance.clinical.complex_probability)
					probability = F.mul(probability,complex_probability if variant.complex else F.sub(F.make(1),complex_probability))
				variant.probability = probability
				result.append(variant)
	return result

func _bundle_available(world: WorldState, bundle: Dictionary, shift: int) -> bool:
	for resource_id: String in bundle.resources:
		if resource_id.begins_with("staff:") and _staff_budget(world,resource_id.substr(6),shift) == 0:
			return false
		if resource_id.begins_with("coverage:") and _staff_budget(world,resource_id.split(":")[1],shift) == 0:
			return false
		if resource_id.begins_with("facility:"):
			var facility: Dictionary = world.facts.facilities.get(resource_id.substr(9),{})
			if facility.is_empty() or facility.get("failed",false) or not facility.get("open",true) or not facility.get("intake_open",true) or facility.get("stop_new_service",false):
				return false
	return _schedule_bundle_allowed(world,bundle,shift)

func _schedule_bundle_allowed(world: WorldState, bundle: Dictionary, shift: int) -> bool:
	if clinic.scheduler == null:
		return true
	# A shallow facts wrapper changes only the clock read by the original
	# scheduling predicate. Staff, rosters and the real hospital stay untouched.
	var future_facts: Dictionary = world.facts.duplicate()
	future_facts.sim_tick = world.sim_tick/WorldState.TICKS_PER_DAY*WorldState.TICKS_PER_DAY+shift*_ticks(content.balance.schedule.shift_seconds)
	var future: WorldState = WorldState.new(future_facts)
	var sequences: Array = [bundle.get("first_stage_resources",bundle.get("stage_resources",{}))]
	if bundle.has("retry_stage_resources"):
		sequences.append(bundle.retry_stage_resources)
	for stages: Dictionary in sequences:
		for stage: String in stages:
			var facilities: Array = _stage_facilities(stages[stage])
			if facilities.is_empty() and stage in ["round","care"]:
				facilities = _stage_facilities(stages.get("bed",{}))
			for resource_id: String in stages[stage]:
				if not resource_id.begins_with("staff:") or F.from_value(stages[stage][resource_id]).n == "0":
					continue
				var staff_id: String = resource_id.substr(6)
				if world.facts.staff.get(staff_id,{}).get("role","") != "doctor":
					continue
				var allowed: bool = false
				var kind: String = "surgery" if stage == "surgery_setup" else stage
				for facility_id: String in facilities:
					for visit: Dictionary in _schedule_visit_contexts(world,bundle,facility_id):
						if clinic.call("_schedule_allows",future,staff_id,kind,visit,facility_id):
							allowed = true
				if not allowed:
					return false
	return true

func _stage_facilities(resources: Dictionary) -> Array:
	var result: Array = []
	for resource_id: String in resources:
		if resource_id.begins_with("facility:") and F.from_value(resources[resource_id]).n != "0":
			result.append(resource_id.substr(9))
	return result

func _schedule_visit_contexts(world: WorldState, bundle: Dictionary, facility_id: String) -> Array:
	var binding_id: String = str(bundle.get("binding_id",""))
	var visit: Dictionary = {"binding_id":binding_id,"department_id":str(bundle.get("department_id",""))}
	var contexts: Array = [visit]
	if not visit.department_id.is_empty():
		return contexts
	var room_id: String = str(world.facts.facilities.get(facility_id,{}).get("room_id",""))
	var disease_id: String = str(content.definition("treatment_bindings",binding_id).get("disease_id",""))
	for department_id: String in world.facts.get("departments",{}).get("units",{}):
		var department: Dictionary = world.facts.departments.units[department_id]
		if not department.get("open",true) or not room_id in department.get("room_ids",[])+department.get("shared_room_ids",[]):
			continue
		var scope: Array = department.get("intake_disease_ids",[])
		if not scope.is_empty() and not disease_id in scope:
			continue
		contexts.append({"binding_id":binding_id,"department_id":department_id})
	return contexts

func _normalize_bundle(world: WorldState, source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result.valid = true
	for resource_id: String in source.get("stage_resources",{}).get("gp",{}):
		if resource_id.begins_with("staff:") and resource_id.substr(6) in source.get("staff_ids",[]):
			result.valid = false
	var resources: Dictionary = result.get("resources",{}).duplicate(true)
	var bed_id: String = str(source.get("bed_id",""))
	var coverage_nurse: String = str(source.get("coverage_nurse_id",source.get("ward_nurse_id","")))
	var ward_id: String = str(source.get("ward_id",world.facts.facilities.get(bed_id,{}).get("room_id","")))
	if not source.has("resources"):
		for staff_id: String in source.get("staff_work_ticks",{}):
			resources["staff:"+staff_id] = F.from_value(source.staff_work_ticks[staff_id])
		for facility_id: String in source.get("facility_work_ticks",{}):
			resources["facility:"+facility_id] = F.from_value(source.facility_work_ticks[facility_id])
		if not bed_id.is_empty() and source.has("bed_ticks"):
			resources["facility:"+bed_id] = F.from_value(source.bed_ticks)
		if not coverage_nurse.is_empty() and source.has("bed_ticks"):
			resources["coverage:"+coverage_nurse+":"+ward_id] = F.from_value(source.bed_ticks)
	var coverage_roles: Dictionary = {}
	for resource_id: String in resources:
		resources[resource_id] = F.from_value(resources[resource_id])
		if resource_id.begins_with("coverage:") and resources[resource_id].n != "0":
			var parts: PackedStringArray = resource_id.split(":")
			if not coverage_roles.has(parts[1]):
				coverage_roles[parts[1]] = []
			if not parts[2] in coverage_roles[parts[1]]:
				coverage_roles[parts[1]].append(parts[2])
	result.resources = resources
	result.coverage_nurse_id = coverage_nurse
	result.ward_id = ward_id
	result.coverage_roles = coverage_roles
	if not result.has("structural_resources"):
		var structural: Array = []
		for resource_id: String in resources:
			if resource_id.begins_with("staff:"):
				var staff_id: String = resource_id.substr(6)
				if world.facts.staff.get(staff_id,{}).get("role","") != "receptionist" and staff_id != coverage_nurse:
					structural.append(resource_id)
			elif resource_id.begins_with("facility:"):
				var facility_id: String = resource_id.substr(9)
				var definition_id: String = world.facts.facilities.get(facility_id,{}).get("definition_id","")
				if definition_id != "FUR01":
					structural.append(resource_id)
		structural.sort()
		result.structural_resources = structural
	return result

func _resource_budgets(world: WorldState, classes: Array, shift: int) -> Dictionary:
	var result: Dictionary = {}
	var shift_ticks: int = _ticks(content.balance.schedule.shift_seconds)
	for case: Dictionary in classes:
		for bundle: Dictionary in case.bundles:
			for resource_id: String in bundle.resources:
				if result.has(resource_id):
					continue
				if resource_id.begins_with("staff:"):
					result[resource_id] = F.make(_staff_budget(world,resource_id.substr(6),shift))
				elif resource_id.begins_with("facility:"):
					var facility_id: String = resource_id.substr(9)
					var facility: Dictionary = world.facts.facilities.get(facility_id,{})
					var available: int = 0 if facility.is_empty() or facility.get("failed",false) or not facility.get("open",true) or not facility.get("intake_open",true) else shift_ticks
					result[resource_id] = F.make(maxi(0,available-_maintenance_remaining(world,facility_id,shift)))
				elif resource_id.begins_with("coverage:"):
					var nurse_id: String = resource_id.split(":")[1]
					result[resource_id] = F.make(_staff_budget(world,nurse_id,shift)*int(content.balance.clinical.beds_per_nurse))
				else:
					result[resource_id] = F.make(shift_ticks)
	return result

func _staff_budget(world: WorldState, staff_id: String, shift: int) -> int:
	var path: String = "res://game/staff/shift_scheduler.gd"
	if ResourceLoader.exists(path):
		var scheduler: RefCounted = load(path).new(content,space)
		if scheduler.has_method("available_ticks"):
			return int(scheduler.call("available_ticks",world,staff_id,shift))
	var staff: Dictionary = world.facts.staff.get(staff_id,{})
	if staff.is_empty() or not staff.get("on_shift",false):
		return 0
	return _ticks(content.balance.schedule.shift_seconds)

func _maintenance_remaining(world: WorldState, facility_id: String, shift: int) -> int:
	var remaining: int = 0
	for collection: Dictionary in [world.facts.get("maintenance",{}).get("jobs",{}),world.facts.get("maintenance",{}).get("upgrades",{})]:
		for job: Dictionary in collection.values():
			if job.get("facility_id","") != facility_id or job.get("phase","") in ["completed","cancelled"]:
				continue
			var rate: float = float(job.get("worker_rate",0))
			if rate <= 0 or job.get("worker_id","").is_empty() or job.get("paused",false):
				return _ticks(content.balance.schedule.shift_seconds)
			remaining += ceili(float(job.get("remaining_milli",0))/1000.0/rate/WorldState.TICK_SECONDS)
	return _shift_remainder(remaining,shift)

func _existing_workload(world: WorldState, shift: int) -> Dictionary:
	var result: Dictionary = {}
	var committed_visits: Dictionary = {}
	for session: Dictionary in world.facts.sessions.values():
		committed_visits[session.visit_id] = true
		var ticks: int = int(session.remaining_ticks)
		_add_demand(result,"facility:"+str(session.facility_id),ticks)
		for staff_id: String in session.staff_ids:
			_add_demand(result,"staff:"+staff_id,ticks)
		if session.get("kind","") in ["surgery","wake","outpatient"]:
			var attempt: Dictionary = world.facts.attempts.get(session.get("attempt_id",""),{})
			if not attempt.get("bed_id","").is_empty():
				_add_demand(result,"facility:"+str(attempt.bed_id),ticks)
				if session.kind == "surgery":
					_add_demand(result,"facility:"+str(attempt.bed_id),_ticks(content.balance.clinical.wake_seconds))
	for preparation: Dictionary in world.facts.preparations.values():
		committed_visits[preparation.visit_id] = true
		var visit: Dictionary = world.facts.visits[preparation.visit_id]
		var quote: Dictionary = clinic.call("reference_demand",world,visit.binding_id,visit.complex,shift)
		if quote.get("ok",false) and not quote.get("bundles",[]).is_empty():
			var bundle: Dictionary = _remaining_bundle(world,visit,quote.bundles[0])
			for resource_id: String in bundle.resources:
				_add_existing(result,resource_id,bundle.resources[resource_id],shift)
	for stay: Dictionary in world.facts.ward_stays.values():
		var attempt: Dictionary = world.facts.attempts.get(stay.get("attempt_id",""),{})
		if attempt.is_empty():
			continue
		committed_visits[attempt.visit_id] = true
		var remaining: int = int(stay.remaining_ticks)
		if stay.get("phase","") != "release_wait":
			remaining += _ticks(content.balance.clinical.discharge_round_seconds)
		_add_demand(result,"facility:"+str(stay.bed_id),remaining)
		if not stay.get("nurse_id","").is_empty():
			var ward_id: String = world.facts.facilities.get(stay.bed_id,{}).get("room_id","")
			_add_existing(result,"coverage:"+str(stay.nurse_id)+":"+ward_id,remaining,shift)
	for ticket: Dictionary in world.facts.tickets.values():
		if committed_visits.has(ticket.visit_id):
			continue
		var visit: Dictionary = world.facts.visits[ticket.visit_id]
		var quote: Dictionary = clinic.call("reference_remaining_demand",world,visit.id,shift) if clinic.has_method("reference_remaining_demand") else clinic.call("reference_demand",world,visit.binding_id,visit.complex,shift)
		if not quote.get("ok",false) or quote.get("bundles",[]).is_empty():
			continue
		committed_visits[ticket.visit_id] = true
		var source: Dictionary = quote.bundles[0]
		var chosen_plan: String = str(visit.plan_decision.get("plan_id",""))
		if not chosen_plan.is_empty():
			var matching: Array = quote.bundles.filter(func(item: Dictionary) -> bool:
				return item.get("retry_plan_id",item.plan_id) == chosen_plan if not visit.attempt_ids.is_empty() else item.plan_id == chosen_plan)
			if matching.is_empty():
				continue
			source = matching[0]
		var bundle: Dictionary = _remaining_bundle(world,visit,source)
		for resource_id: String in bundle.resources:
			_add_existing(result,resource_id,bundle.resources[resource_id],shift)
	for resource_id: String in result:
		if not resource_id.begins_with("coverage:"):
			result[resource_id] = _shift_fraction(result[resource_id],shift)
	return result

func _remaining_bundle(world: WorldState, visit: Dictionary, source: Dictionary) -> Dictionary:
	var result: Dictionary = _normalize_bundle(world,source)
	if not source.has("stage_resources"):
		return result
	var resources: Dictionary = {}
	var ticket: Dictionary = world.facts.tickets.get(visit.get("ticket_id",""),{})
	var kind: String = str(ticket.get("kind",""))
	var factor: Dictionary = F.make(1)
	var stages: Dictionary = source.stage_resources
	if not visit.attempt_ids.is_empty() and source.has("retry_stage_resources"):
		stages = source.retry_stage_resources
		result.plan_id = source.get("retry_plan_id",source.plan_id)
	elif not visit.attempt_ids.is_empty() and source.has("expected_attempts"):
		factor = F.div(F.make(1),F.from_value(source.expected_attempts))
	for stage: String in stages:
		if stage == "reception" and kind != "reception":
			continue
		if stage == "gp" and not kind in ["reception","gp"]:
			continue
		if stage in ["spectrum","resonance"] and visit.evidence_by_source.has(stage):
			continue
		if stage == "consult" and not kind in ["reception","gp","spectrum","resonance","consult"]:
			continue
		for resource_id: String in stages[stage]:
			var amount: Dictionary = F.from_value(stages[stage][resource_id])
			if stage in ["outpatient","surgery","surgery_setup","bed","care","round"]:
				amount = F.mul(amount,factor)
			_add_demand(resources,resource_id,amount)
	result.resources = resources
	return result

func _add_demand(target: Dictionary, key: String, amount: Variant) -> void:
	target[key] = F.add(F.from_value(target.get(key,0)),F.from_value(amount))

func _add_existing(target: Dictionary, key: String, amount: Variant, shift: int) -> void:
	_add_demand(target,key,_shift_fraction(F.from_value(amount),shift) if key.begins_with("coverage:") else amount)

func _shift_remainder(remaining: int, shift: int) -> int:
	var shift_ticks: int = _ticks(content.balance.schedule.shift_seconds)
	return clampi(remaining-shift*shift_ticks,0,shift_ticks)

func _shift_fraction(remaining: Dictionary, shift: int) -> Dictionary:
	var shift_ticks: int = _ticks(content.balance.schedule.shift_seconds)
	return F.minimum(F.make(shift_ticks),F.maximum(F.make(),F.sub(remaining,F.make(shift*shift_ticks))))

func _structural_pairs(world: WorldState, classes: Array, shift: int) -> int:
	var bundles: Array = []
	var unique: Dictionary = {}
	for case: Dictionary in classes:
		for bundle: Dictionary in case.bundles:
			var resources: Array = bundle.structural_resources.duplicate()
			resources.sort()
			var signature: String = JSON.stringify(resources)
			if resources.is_empty() or unique.has(signature):
				continue
			var valid: bool = true
			for resource_id: String in resources:
				if resource_id.begins_with("staff:") and _staff_budget(world,resource_id.substr(6),shift) == 0:
					valid = false
				if resource_id.begins_with("facility:"):
					var facility: Dictionary = world.facts.facilities.get(resource_id.substr(9),{})
					if facility.get("failed",false) or not facility.get("open",true) or not facility.get("intake_open",true) or facility.get("stop_new_service",false):
						valid = false
			if valid:
				unique[signature] = true
				bundles.append({"signature":signature,"resources":resources,"coverage_nurse_id":bundle.coverage_nurse_id,"ward_id":bundle.ward_id})
	bundles.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.signature < b.signature)
	var count: int = _pack_pairs(bundles,0,{}, {},0,0)
	return mini(count,_reception_pairs(world,classes,shift)*int(content.balance.arrivals.capacity_scaling.reception_pairs_per_station))

func _pack_pairs(bundles: Array, cursor: int, used: Dictionary, coverage: Dictionary, count: int, best: int) -> int:
	if cursor >= bundles.size():
		return maxi(count,best)
	if count+bundles.size()-cursor <= best:
		return best
	var bundle: Dictionary = bundles[cursor]
	var available: bool = true
	for resource_id: String in bundle.resources:
		if used.has(resource_id):
			available = false
		if resource_id.begins_with("staff:") and coverage.has(resource_id.substr(6)):
			available = false
	var nurse_id: String = bundle.coverage_nurse_id
	if not nurse_id.is_empty():
		if used.has("staff:"+nurse_id) or (coverage.has(nurse_id) and (coverage[nurse_id].ward_id != bundle.ward_id or int(coverage[nurse_id].beds) >= int(content.balance.clinical.beds_per_nurse))):
			available = false
	if available:
		var next_used: Dictionary = used.duplicate()
		for resource_id: String in bundle.resources:
			next_used[resource_id] = true
		var next_coverage: Dictionary = coverage.duplicate(true)
		if not nurse_id.is_empty():
			if not next_coverage.has(nurse_id):
				next_coverage[nurse_id] = {"ward_id":bundle.ward_id,"beds":0}
			next_coverage[nurse_id].beds += 1
		best = _pack_pairs(bundles,cursor+1,next_used,next_coverage,count+1,best)
	return _pack_pairs(bundles,cursor+1,used,coverage,count,best)

func _reception_pairs(world: WorldState, classes: Array, shift: int) -> int:
	var edges: Dictionary = {}
	for case: Dictionary in classes:
		for bundle: Dictionary in case.bundles:
			var desks: Array = []
			var people: Array = []
			for resource_id: String in bundle.resources:
				if resource_id.begins_with("staff:"):
					var id: String = resource_id.substr(6)
					if world.facts.staff.get(id,{}).get("role","") == "receptionist" and _staff_budget(world,id,shift) > 0:
						people.append(id)
				elif resource_id.begins_with("facility:"):
					var id: String = resource_id.substr(9)
					if world.facts.facilities.get(id,{}).get("definition_id","") == "FUR01":
						desks.append(id)
			for person: String in people:
				if not edges.has(person):
					edges[person] = []
				for desk: String in desks:
					if not desk in edges[person]:
						edges[person].append(desk)
	var matched: Dictionary = {}
	var people: Array = edges.keys()
	people.sort()
	for person: String in people:
		_match_reception(person,edges,matched,{})
	return matched.size()

func _match_reception(person: String, edges: Dictionary, matched: Dictionary, visited: Dictionary) -> bool:
	var desks: Array = edges.get(person,[]).duplicate()
	desks.sort()
	for desk: String in desks:
		if visited.has(desk):
			continue
		visited[desk] = true
		if not matched.has(desk) or _match_reception(matched[desk],edges,matched,visited):
			matched[desk] = person
			return true
	return false

func _admission_candidates(world: WorldState) -> Array:
	var candidates: Array = []
	if not clinic.has_method("arrival_readiness"):
		return candidates
	var seen: Dictionary = {}
	for binding: Dictionary in content.catalog.get("treatment_bindings",[]):
		if _disease_weight(world,str(binding.disease_id)) == 0:
			continue
		var key: String = str(binding.species_id)+"|"+str(binding.disease_id)
		if seen.has(key):
			continue
		var variants: Array = []
		for complex_case: bool in [false,true]:
			var ready: Dictionary = clinic.call("arrival_readiness",world,str(binding.id),complex_case)
			if ready.get("ok",false):
				variants.append(complex_case)
		if variants.is_empty():
			continue
		seen[key] = true
		candidates.append({"binding_id":binding.id,"disease_id":binding.disease_id,"species_id":binding.species_id,"variants":variants})
	return candidates

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
	var unlocked: bool = disease_id in content.catalog.get("initial_disease_ids",[])
	if not unlocked:
		for research_id: String in world.facts.research:
			if disease_id in content.definition("research",research_id).get("disease_ids",[]):
				unlocked = true
				break
	if not unlocked:
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
	var minimum: int = int(content.balance.resident_returns.minimum_absence_days)*WorldState.TICKS_PER_DAY
	for resident_id: String in world.ids("residents"):
		var resident: Dictionary = world.facts.residents[resident_id]
		if resident.species_id != species_id or not resident.get("remembered",false) or resident.get("pending_release",false):
			continue
		if int(resident.get("last_departure_tick",-1)) < 0 or world.sim_tick-int(resident.last_departure_tick) < minimum:
			continue
		if not _protected_reasons(world,resident,true).is_empty():
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

func _protected_reasons(world: WorldState, resident: Dictionary, ignore_story: bool = false) -> Array:
	var reasons: Array = []
	var resident_id: String = resident.id
	for actor: Dictionary in world.facts.actors.values():
		if actor.get("resident_id","") != resident_id:
			continue
		if actor.location.kind != "outside":
			reasons.append("本次实际离院后腾出位置")
		if world.facts.staff.has(actor.id):
			reasons.append("当前员工身份")
		for visit: Dictionary in world.facts.visits.values():
			if visit.actor_id == actor.id and visit.phase != "departed":
				reasons.append("当前就诊尚未结束")
	for collection: String in ["activities","community_activities","interactions","visitor_stays","care_jobs"]:
		for record: Dictionary in world.facts.get(collection,{}).values():
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
	var path: String = "res://game/operations/environment_service.gd"
	if ResourceLoader.exists(path):
		var environment: RefCounted = load(path).new(content,space)
		var sample: Dictionary = environment.call("environment_at",world,int(actor.location.floor_id),actor.location.cell,str(actor.id))
		return float(sample.get("value",0))
	return float(content.balance.environment.base)

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
