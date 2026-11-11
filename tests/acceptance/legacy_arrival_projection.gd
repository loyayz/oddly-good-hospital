# Historical exact-capacity fixtures only. Not instantiated by game code.
# Their old capacity assertions are not requirements of random demand.
class_name LegacyArrivalProjection
extends HospitalArrivalService

var _reference_cache: Dictionary = {}
var _role_models: Dictionary = {}
var _structure_cache: Dictionary = {}
var _reference_version: int = 0
var _basis_records: Dictionary = {}
var _budget_scheduler: HospitalShiftScheduler
var reference_counts: Dictionary = {"basis_changes":0,"case_quotes":0,"case_hits":0,"transport_independent_hits":0,"basis_us":0,"basis_change_fields":{}}

var preparation_error: String = ""

func capacity(world: WorldState, subtract_existing: bool = true, cancellation: Callable = Callable()) -> Dictionary:
	if _capacity_cancelled(cancellation): return {"complete":false,"cancelled":true}
	preparation_error = ""
	if not clinic.has_method("reference_demand"):
		return {"complete":false,"reason":"临床参考报价尚未就绪"}
	if not subtract_existing and world.sim_tick%WorldState.TICKS_PER_DAY != 0:
		var clock: Dictionary = world.facts.duplicate()
		clock.sim_tick = world.sim_tick/WorldState.TICKS_PER_DAY*WorldState.TICKS_PER_DAY
		world = WorldState.new(clock)
	var shift_capacities: Array = []
	var shift_pairs: Array = []
	var explanations: Array = []
	var total: Dictionary = F.make()
	var commitments: Dictionary = clinic.remaining_commitments(world) if subtract_existing else {}
	var maintenance: Dictionary = _maintenance_view(world)
	for shift: int in 3:
		if _capacity_cancelled(cancellation): return {"complete":false,"cancelled":true}
		var query: Dictionary = {}
		var classes: Array = _reference_classes(world,shift,query,cancellation)
		if query.get("cancelled",false): return {"complete":false,"cancelled":true}
		if query.has("error"):
			preparation_error = str(query.reason)
			return {"complete":false,"error":query.error,"reason":query.reason}
		var budgets: Dictionary = _resource_budgets(world,classes,shift,query.resource_ids,maintenance)
		var locked_roles: Dictionary = {}
		if subtract_existing:
			var workload: Dictionary = _existing_workload(world,shift,query,commitments,cancellation)
			if query.get("cancelled",false): return {"complete":false,"cancelled":true}
			if query.has("error"):
				preparation_error = str(query.reason)
				return {"complete":false,"error":query.error,"reason":query.reason}
			for resource_id: String in workload:
				if resource_id.begins_with("coverage:") and F.compare(workload[resource_id],F.make())>0:
					var parts: PackedStringArray = resource_id.split(":")
					locked_roles[parts[1]] = parts[2]
				if budgets.has(resource_id):
					budgets[resource_id] = F.maximum(F.make(),F.sub(F.from_value(budgets[resource_id]),F.from_value(workload[resource_id])))
		if _capacity_cancelled(cancellation): return {"complete":false,"cancelled":true}
		var solved: Dictionary = _solve_roles(world,classes,budgets,shift,query.model_key,locked_roles)
		if _capacity_cancelled(cancellation): return {"complete":false,"cancelled":true}
		if solved.has("error"):
			preparation_error = str(solved.bottleneck)
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

func _capacity_cancelled(cancellation: Callable) -> bool:
	return cancellation.is_valid() and bool(cancellation.call())

func _prepared_projection(projection: Dictionary) -> Dictionary:
	preparation_error = str(projection.get("reason","")) if not projection.get("complete",false) and not projection.get("pending",false) else ""
	return projection

func _solve_roles(world: WorldState, classes: Array, budgets: Dictionary, shift: int, model_key: Variant = null, locked_roles: Dictionary = {}) -> Dictionary:
	var cached: Dictionary = _role_models.get(shift,{})
	var same_model: bool = model_key!=null and cached.get("key") == model_key
	if same_model:
		var updated: Dictionary = cached.backend.call("solve_with_roles",budgets,locked_roles)
		if updated.has("error"): _role_models.erase(shift)
		else: cached.roles = locked_roles.duplicate()
		updated.structural_pairs = cached.pairs
		return updated
	var backend: RefCounted = ClassDB.instantiate("PlatformArrivalCapacity")
	var result: Dictionary = backend.call("prepare_with_roles",classes,budgets,locked_roles)
	if result.has("error"): return result
	var structure: Dictionary = {"pairs":cached.pairs} if same_model else _structural_pairs(world,classes,shift)
	if structure.has("error"): return structure
	result.structural_pairs = structure.pairs
	if model_key!=null: _role_models[shift] = {"key":model_key.duplicate(true),"roles":locked_roles.duplicate(),"backend":backend,"pairs":result.structural_pairs}
	return result

func _restrict_roles(classes: Array, roles: Dictionary) -> Array:
	if roles.is_empty(): return classes
	var result: Array = []
	for case: Dictionary in classes:
		var restricted: Dictionary = case.duplicate()
		restricted.bundles = case.bundles.filter(func(part: Dictionary) -> bool: return _committed_role_allows(part,roles))
		restricted.choice_groups = {}
		for group: String in case.get("choice_groups",{}):
			restricted.choice_groups[group] = case.choice_groups[group].filter(func(part: Dictionary) -> bool: return _committed_role_allows(part,roles))
		_prune_choices(restricted)
		result.append(restricted)
	return result

func _committed_role_allows(part: Dictionary, roles: Dictionary) -> bool:
	for nurse_id: String in roles:
		var wards: Array = part.get("coverage_roles",{}).get(nurse_id,[])
		for ward_id: String in wards:
			if ward_id!=roles[nurse_id]: return false
		if part.resources.has("staff:"+nurse_id) and not roles[nurse_id] in wards: return false
	return true

func _model_parts(case: Dictionary) -> Array:
	var result: Array = case.bundles.duplicate()
	for options: Array in case.get("choice_groups",{}).values(): result.append_array(options)
	return result

func _prune_choices(case: Dictionary) -> void:
	var changed: bool = true
	while changed:
		changed = false
		for group: String in case.choice_groups:
			var before: int = case.choice_groups[group].size()
			case.choice_groups[group] = case.choice_groups[group].filter(func(bundle: Dictionary) -> bool: return _choices_available(case,bundle))
			changed = changed or before!=case.choice_groups[group].size()
	case.bundles = case.bundles.filter(func(bundle: Dictionary) -> bool: return _choices_available(case,bundle))

func _choices_available(case: Dictionary, bundle: Dictionary) -> bool:
	for group: String in bundle.get("choices",[]):
		if case.choice_groups.get(group,[]).is_empty(): return false
	return true

func _reference_classes(world: WorldState, shift: int, query: Variant = null, cancellation: Callable = Callable()) -> Array:
	if query==null: query = {}
	# No clinical operator can form a legal case in an unstaffed hospital.
	if world.facts.staff.is_empty():
		query.merge({"resource_ids":[],"model_key":[],"references":{}},true)
		return []
	var basis_started: int = Time.get_ticks_usec()
	var basis: Dictionary = _reference_basis(world,shift)
	reference_counts.basis_us += Time.get_ticks_usec()-basis_started
	if not _reference_cache.has(shift) or _reference_cache[shift].basis!=basis:
		reference_counts.basis_changes += 1
		var previous: Dictionary = _reference_cache.get(shift,{})
		var old_basis: Dictionary = previous.get("basis",{})
		for field: String in basis:
			if old_basis.get(field)!=basis[field]: reference_counts.basis_change_fields[field] = int(reference_counts.basis_change_fields.get(field,0))+1
		var stable: Dictionary = basis.duplicate()
		stable.erase("transport")
		var prior: Dictionary = previous.get("basis",{}).duplicate()
		prior.erase("transport")
		_reference_cache[shift] = {"basis":basis.duplicate(true),"cases":previous.cases if prior==stable else {}}
	var cached: Dictionary = _reference_cache[shift]
	var experience_basis: Dictionary = {}
	for staff_id: String in world.facts.staff:
		experience_basis[staff_id] = world.facts.staff[staff_id].get("plan_experience",{})
	var weights: Dictionary = world.facts.get("arrivals",{}).get("disease_weights",{})
	if cached.has("outputs") and cached.experience_basis==experience_basis and cached.weights==weights:
		query.clear()
		query.merge(cached.outputs)
		return cached.classes
	world = _capacity_reference_world(world)
	var cached_cases: Dictionary = cached.cases
	var by_disease: Dictionary = {}
	var experience_by_disease: Dictionary = {}
	var references: Dictionary = {}
	var resource_ids: Dictionary = {}
	var model_key: Array = []
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
		if not experience_by_disease.has(binding.disease_id): experience_by_disease[binding.disease_id] = _case_experience(world,str(binding.disease_id))
		var experience: Dictionary = experience_by_disease[binding.disease_id]
		for complex_case: bool in [false,true]:
			# Cache only a complete case. Clinical scopes and native component
			# assembly have returned before cancellation is observed here.
			if _capacity_cancelled(cancellation):
				query.clear()
				query.cancelled = true
				return []
			var case_key: String = JSON.stringify([binding.id,complex_case])
			var retained: Dictionary = cached_cases.get(case_key,{})
			var transport_changed: bool = not retained.is_empty() and retained.transport!=basis.transport
			if not retained.is_empty() and transport_changed and not retained.get("transport_dependent",true):
				retained.transport = cached.basis.transport
				reference_counts.transport_independent_hits += 1
			if retained.is_empty() or retained.experience!=experience or retained.transport!=basis.transport:
				reference_counts.case_quotes += 1
				query.transport_basis = basis.transport
				var quote: Dictionary = clinic.call("reference_demand",world,str(binding.id),complex_case,shift,query)
				if quote.has("error"):
					query.clear()
					if _capacity_cancelled(cancellation):
						query.cancelled = true
						return []
					query.merge({"error":quote.error,"reason":quote.reason})
					return []
				var variant: Dictionary = _reference_variant(world,binding,complex_case,shift,quote,query)
				var resources: Dictionary = {}
				for part: Dictionary in _model_parts(variant):
					for resource: String in part.resources: resources[resource] = true
				var remaining: Dictionary = _remaining_reference(quote)
				var previous: Dictionary = cached_cases.get(case_key,{})
				var version: int = int(previous.get("version",-1))
				if previous.get("variant",{})!=variant:
					_reference_version += 1
					version = _reference_version
				cached_cases[case_key] = {"experience":experience.duplicate(true),"transport":cached.basis.transport,"transport_dependent":quote.get("transport_dependent",true),"variant":variant,"version":version,"resources":resources.keys(),"reference":remaining}
			else: reference_counts.case_hits += 1
			var prepared: Dictionary = cached_cases[case_key]
			var variant: Dictionary = prepared.variant.duplicate()
			references[case_key] = prepared.reference
			model_key.append([case_key,prepared.version])
			if not variant.bundles.is_empty():
				variants.append(variant)
				for resource: String in prepared.resources: resource_ids[resource] = true
		if not variants.is_empty():
			species[key] = variants
	if _capacity_cancelled(cancellation):
		query.clear()
		query.cancelled = true
		return []
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
				model_key.append(probability)
	# Factory keys, candidate paths and quote scratch are not retained alongside
	# the immutable model. The three handoffs below are the projection outputs.
	query.clear()
	query.resource_ids = resource_ids.keys()
	query.model_key = model_key
	query.references = references
	cached.outputs = query.duplicate()
	cached.classes = result
	cached.experience_basis = experience_basis.duplicate(true)
	cached.weights = weights.duplicate(true)
	return result

func _reference_variant(world: WorldState, binding: Dictionary, complex_case: bool, shift: int, quote: Dictionary, query: Dictionary) -> Dictionary:
	var model: Dictionary = quote.get("model",{"bundles":quote.get("bundles",[]),"choice_groups":{}})
	var groups: Dictionary = {}
	for group: String in model.get("choice_groups",{}):
		groups[group] = []
		for source: Dictionary in model.choice_groups[group]:
			var option: Dictionary = _normalize_bundle(world,source,query)
			option.binding_id = str(binding.id)
			if option.valid and _bundle_available(world,option,shift,query): groups[group].append(_capacity_part(option,query,group.begins_with("diagnostic") or group.begins_with("consult:")))
	var bundles: Array = []
	for source: Dictionary in model.bundles:
		var bundle: Dictionary = _normalize_bundle(world,source,query)
		bundle.binding_id = str(binding.id)
		if bundle.valid and not bundle.resources.is_empty() and _bundle_available(world,bundle,shift,query):
			bundles.append(_capacity_part(bundle,query,true))
	var variant: Dictionary = {"binding_id":binding.id,"species_id":binding.species_id,"disease_id":binding.disease_id,"complex":complex_case,"bundles":bundles,"choice_groups":groups}
	_prune_choices(variant)
	# K consumes the complete first-attempt structure and the registration
	# choices; retry work belongs to C and need not be reparsed for matching.
	variant.reception_bundles = groups.get("reception",[])
	return variant

func _remaining_reference(quote: Dictionary) -> Dictionary:
	# Queue deduction asks for the first quote matching a first/retry plan. Keep
	# those representatives; every legal solver choice remains in the model.
	var seen: Dictionary = {}
	var bundles: Array = []
	for bundle: Dictionary in quote.get("bundles",[]):
		var key: String = JSON.stringify([bundle.plan_id,bundle.get("retry_plan_id",bundle.plan_id)])
		if seen.has(key): continue
		seen[key] = true
		bundles.append(bundle)
	return {"ok":quote.get("ok",false),"reason":quote.get("reason",""),"bundles":bundles}

func _case_experience(world: WorldState, disease_id: String) -> Dictionary:
	var result: Dictionary = {}
	for plan: Dictionary in content.catalog.treatment_plans:
		if plan.disease_id!=disease_id: continue
		for staff_id: String in world.ids("staff"):
			result[staff_id+":"+str(plan.id)] = int(world.facts.staff[staff_id].get("plan_experience",{}).get(plan.id,0))
	return result

func _reference_basis(world: WorldState, shift: int) -> Dictionary:
	var result: Dictionary = {"hospital":world.hospital_id,"content":content.content_fingerprint,"clinic":clinic.get_instance_id(),"shift":shift,"staff":{},"actors":{},"facilities":{},"rooms":{}}
	for field: String in ["gameplay_version","entry","research","allow_outpatient_rounds","plan_strategy","remodels"]:
		result[field] = world.facts.get(field)
	result.transport = HospitalTransit.reference_basis(space,world)
	result.transport_layout = {}
	for id: String in result.transport.connections:
		var connection: Dictionary = result.transport.connections[id]
		var layout: Dictionary = {}
		for field: String in ["id","definition_id","first_floor","last_floor","stops","cell","footprint","anchor"]:
			if connection.has(field): layout[field] = connection[field]
		result.transport_layout[id] = layout
	result.floors = {}
	for field: String in ["overrides","completed_top_floor","height_intervals"]: result.floors[field] = world.facts.floors.get(field)
	result.departments = _reference_geometry_basis("departments",world.facts.get("patient_experience",{}).get("units",{}),["id","room_ids","shared_room_ids","public_cells","entry","focus_id","intake_disease_ids","open"])
	result.focus_active = {}
	result.focus_ratings = {}
	var clock: int = world.sim_tick/WorldState.TICKS_PER_DAY*WorldState.TICKS_PER_DAY+shift*_ticks(content.balance.schedule.shift_seconds)
	for id: String in result.departments:
		result.focus_active[id] = clock>=int(world.facts.patient_experience.units[id].get("focus_ready_tick",0))
		if experience!=null and not str(result.departments[id].get("focus_id","")).is_empty(): result.focus_ratings[id] = experience.call("aggregate_rating",world,id)
	result.talents = clinic.recruitment!=null
	result.department_effects = clinic.experience!=null
	var scheduler: RefCounted = clinic.scheduler
	for staff_id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[staff_id]
		var record: Dictionary = {}
		for field: String in ["id","role","departed","abilities","certificates","title_id","personality_id","skill","ward_id"]: record[field] = staff.get(field)
		record.available = _staff_budget(world,staff_id,shift)>0
		if scheduler!=null: record.assignment = scheduler.call("assignment",world,staff_id,shift)
		result.staff[staff_id] = record
		var actor: Dictionary = world.facts.actors[staff_id]
		result.actors[staff_id] = [actor.species_id,actor.get("body_binding_id","")]
	result.facilities = _reference_geometry_basis("facilities",world.facts.facilities,["id","definition_id","floor_id","room_id","cell","footprint","rotation","patient_cell","operator_cells","repair_cell","grade","failed","open","intake_open","stop_new_service"])
	result.rooms = _reference_geometry_basis("rooms",world.facts.rooms,["id","kind","floor_id","origin","size","cells","wall_edges","open"])
	return result

func _reference_geometry_basis(collection: String, sources: Dictionary, fields: Array) -> Dictionary:
	var previous: Dictionary = _basis_records.get(collection,{})
	var current: Dictionary = {}
	var result: Dictionary = {}
	for id: String in sources:
		var cached: Dictionary = previous.get(id,{})
		var record: Dictionary = {}
		for field: String in fields: record[field] = sources[id].get(field)
		if collection=="facilities": record.low_condition = float(sources[id].condition)<40.0
		if cached.is_empty() or cached.value!=record:
			cached = {"value":record.duplicate(true)}
		current[id] = cached
		result[id] = cached.value
	_basis_records[collection] = current
	return result

static func _capacity_reference_world(world: WorldState) -> WorldState:
	# A nominal reference has real staff bodies and built geometry, without
	# today's transient people/reservations. Reference operators start at the
	# same actual entrance as the reference patient; no real actor is moved.
	var facts: Dictionary = world.facts.duplicate()
	var entry: Dictionary = world.facts.get("entry",{"floor_id":1,"cell":[47,93]})
	facts.actors = {}
	for staff_id: String in world.ids("staff"):
		var actor: Dictionary = world.facts.actors[staff_id].duplicate()
		actor.location = {"kind":"floor","floor_id":int(entry.floor_id),"cell":entry.cell.duplicate(),"height_m":0.0}
		actor.posture = "standing"
		actor.erase("support_facility_id")
		facts.actors[staff_id] = actor
	for collection: String in ["visits","sessions","preparations","ward_stays","moves","adaptations"]:
		facts[collection] = {}
	facts.moves = HospitalTransit.reference_movements(world)
	facts.connectors = HospitalTransit.reference_conditions(world)
	for connection: Dictionary in world.facts.connectors.values():
		for actor_id: String in connection.get("riders",[]):
			if not facts.actors.has(actor_id): facts.actors[actor_id] = world.facts.actors[actor_id]
	return WorldState.new(facts)

func _capacity_part(bundle: Dictionary, query: Dictionary, structural: bool) -> Dictionary:
	# Scheduling and qualification have already consumed the clinical quote.
	# The optimizer retains only its actual constraints, not presentation and
	# stage copies for every legal resource choice.
	var result: Dictionary = {"resources":bundle.resources}
	for field: String in ["choices","structural_group","structural_choices","coverage_roles","coverage_nurse_id","ward_id"]:
		if not bundle.has(field): continue
		var value: Variant = bundle[field]
		if (value is Dictionary or value is Array or value is String) and value.is_empty(): continue
		result[field] = value
	if structural: result.structural_resources = bundle.structural_resources
	# Repeated diseases/body variants often have exactly the same immutable
	# resource coefficients. Share those values within this projection only.
	if not query.has("resource_maps"): query.resource_maps = {}
	if not query.has("fractions"): query.fractions = {}
	for resource: String in result.resources:
		var fraction: Dictionary = result.resources[resource]
		var value: String = str(fraction.n)+"/"+str(fraction.d)
		if not query.fractions.has(value): query.fractions[value] = fraction
		result.resources[resource] = query.fractions[value]
	var key: Array = []
	var names: Array = result.resources.keys()
	names.sort()
	for resource: String in names:
		var amount: Dictionary = result.resources[resource]
		key.append_array([resource,amount.n,amount.d])
	if not query.resource_maps.has(key): query.resource_maps[key] = {"id":query.resource_maps.size(),"values":result.resources}
	var shared: Dictionary = query.resource_maps[key]
	result.resources = shared.values
	if not query.has("parts"): query.parts = {}
	var part_key: Array = [shared.id]
	var fields: Array = result.keys()
	fields.sort()
	for field: String in fields:
		if field!="resources": part_key.append_array([field,result[field]])
	part_key = part_key.duplicate(true)
	if not query.parts.has(part_key): query.parts[part_key] = result
	return query.parts[part_key]

func _bundle_available(world: WorldState, bundle: Dictionary, shift: int, query: Variant = null) -> bool:
	if query==null: query = {}
	if not query.has("staff_budgets"): query.staff_budgets = {}
	for resource_id: String in bundle.resources:
		if resource_id.begins_with("staff:") or resource_id.begins_with("coverage:"):
			var staff_id: String = resource_id.substr(6) if resource_id.begins_with("staff:") else resource_id.split(":")[1]
			if not query.staff_budgets.has(staff_id): query.staff_budgets[staff_id] = _staff_budget(world,staff_id,shift)
			if query.staff_budgets[staff_id]==0: return false
		if resource_id.begins_with("facility:"):
			var facility: Dictionary = world.facts.facilities.get(resource_id.substr(9),{})
			if facility.is_empty() or facility.get("failed",false) or not facility.get("open",true) or not facility.get("intake_open",true) or facility.get("stop_new_service",false):
				return false
	return _schedule_bundle_allowed(world,bundle,shift,query)

func _schedule_bundle_allowed(world: WorldState, bundle: Dictionary, shift: int, query: Variant = null) -> bool:
	if query==null: query = {}
	if clinic.scheduler == null:
		return true
	# A shallow facts wrapper changes only the clock read by the original
	# scheduling predicate. Staff, rosters and the real hospital stay untouched.
	if not query.has("schedule_world"):
		var future_facts: Dictionary = world.facts.duplicate()
		future_facts.sim_tick = world.sim_tick/WorldState.TICKS_PER_DAY*WorldState.TICKS_PER_DAY+shift*_ticks(content.balance.schedule.shift_seconds)
		query.schedule_world = WorldState.new(future_facts)
		query.schedule_allowed = {}
	var future: WorldState = query.schedule_world
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
						var key: String = JSON.stringify([staff_id,kind,facility_id,visit])
						if not query.schedule_allowed.has(key): query.schedule_allowed[key] = clinic.call("_schedule_allows",future,staff_id,kind,visit,facility_id)
						if query.schedule_allowed[key]:
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
	for department_id: String in world.facts.get("patient_experience",{}).get("units",{}):
		var department: Dictionary = world.facts.patient_experience.units[department_id]
		if not department.get("open",true) or not room_id in department.get("room_ids",[])+department.get("shared_room_ids",[]):
			continue
		var scope: Array = department.get("intake_disease_ids",[])
		if not scope.is_empty() and not disease_id in scope:
			continue
		contexts.append({"binding_id":binding_id,"department_id":department_id})
	return contexts

func _normalize_bundle(world: WorldState, source: Dictionary, query: Variant = null) -> Dictionary:
	if query==null: query = {}
	var result: Dictionary = source.duplicate()
	result.erase("full")
	# Quote metadata and stages are read-only. Own only the normalized map;
	# copying all nested stage fractions for every alternative wastes memory.
	result.valid = true
	for resource_id: String in source.get("stage_resources",{}).get("gp",{}):
		if resource_id.begins_with("staff:") and resource_id.substr(6) in source.get("staff_ids",[]):
			result.valid = false
	var resources: Dictionary = result.get("resources",{}).duplicate()
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
	if not query.has("normalized_fractions"): query.normalized_fractions = {}
	for resource_id: String in resources:
		var value: Variant = resources[resource_id]
		var key: String = str(value.n)+"/"+str(value.d) if value is Dictionary and value.has("n") and value.has("d") else JSON.stringify(value)
		if not query.normalized_fractions.has(key): query.normalized_fractions[key] = F.from_value(value)
		resources[resource_id] = query.normalized_fractions[key]
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
				if staff_id != coverage_nurse:
					structural.append(resource_id)
			elif resource_id.begins_with("facility:"):
				var facility_id: String = resource_id.substr(9)
				structural.append(resource_id)
		structural.sort()
		result.structural_resources = structural
	return result

func _resource_budgets(world: WorldState, classes: Array, shift: int, resource_ids: Variant = null, maintenance: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	if maintenance.is_empty(): maintenance = _maintenance_view(world)
	var shift_ticks: int = _ticks(content.balance.schedule.shift_seconds)
	if resource_ids==null:
		var used: Dictionary = {}
		for case: Dictionary in classes:
			for bundle: Dictionary in _model_parts(case):
				for resource_id: String in bundle.resources: used[resource_id] = true
		resource_ids = used.keys()
	for resource_id: String in resource_ids:
		if resource_id.begins_with("staff:"):
			result[resource_id] = F.make(_staff_budget(world,resource_id.substr(6),shift))
		elif resource_id.begins_with("facility:"):
			var facility_id: String = resource_id.substr(9)
			var facility: Dictionary = world.facts.facilities.get(facility_id,{})
			var available: int = 0 if facility.is_empty() or facility.get("failed",false) or not facility.get("open",true) or not facility.get("intake_open",true) else shift_ticks
			result[resource_id] = F.make(maxi(0,available-_maintenance_remaining(world,facility_id,shift,maintenance)))
		elif resource_id.begins_with("coverage:"):
			var nurse_id: String = resource_id.split(":")[1]
			result[resource_id] = F.make(_staff_budget(world,nurse_id,shift)*int(content.balance.clinical.beds_per_nurse))
		else:
			result[resource_id] = F.make(shift_ticks)
	return result

func _staff_budget(world: WorldState, staff_id: String, shift: int) -> int:
	if clinic.scheduler!=null: return int(clinic.scheduler.call("available_ticks",world,staff_id,shift))
	if _budget_scheduler==null: _budget_scheduler = HospitalShiftScheduler.new(content,space)
	return _budget_scheduler.available_ticks(world,staff_id,shift)

func _maintenance_view(world: WorldState) -> Dictionary:
	var result: Dictionary = {"remaining":{},"blocked":{}}
	for collection: Dictionary in [world.facts.get("maintenance",{}).get("jobs",{}),world.facts.get("maintenance",{}).get("upgrades",{})]:
		for job: Dictionary in collection.values():
			if job.get("phase","") in ["completed","cancelled"]:
				continue
			var facility_id: String = str(job.get("facility_id",""))
			var rate: float = float(job.get("worker_rate",0))
			if rate <= 0 or job.get("worker_id","").is_empty() or job.get("paused",false):
				result.blocked[facility_id] = true
			else:
				result.remaining[facility_id] = int(result.remaining.get(facility_id,0))+ceili(float(job.get("remaining_milli",0))/1000.0/rate/WorldState.TICK_SECONDS)
	return result

func _maintenance_remaining(world: WorldState, facility_id: String, shift: int, view: Dictionary = {}) -> int:
	if view.is_empty(): view = _maintenance_view(world)
	if view.blocked.has(facility_id): return _ticks(content.balance.schedule.shift_seconds)
	return _shift_remainder(int(view.remaining.get(facility_id,0)),shift)

func _existing_workload(world: WorldState, shift: int, query: Variant = null, commitments: Dictionary = {}, cancellation: Callable = Callable()) -> Dictionary:
	if query==null: query = {}
	if _capacity_cancelled(cancellation):
		query.cancelled = true
		return {}
	var result: Dictionary = {}
	var reference: WorldState
	if commitments.is_empty(): commitments = clinic.remaining_commitments(world)
	var committed_visits: Dictionary = commitments.visits.duplicate()
	for resource_id: String in commitments.resources:
		if not resource_id.begins_with("coverage:"): _add_existing(result,resource_id,commitments.resources[resource_id],shift)
	for resource_id: String in commitments.coverage:
		for ticks: int in commitments.coverage[resource_id]: _add_existing(result,resource_id,ticks,shift)
	var references: Dictionary = query.get("references",{}).duplicate()
	var reference_query: Dictionary = {}
	for ticket: Dictionary in world.facts.tickets.values():
		if _capacity_cancelled(cancellation):
			query.cancelled = true
			return {}
		if committed_visits.has(ticket.visit_id):
			continue
		var visit: Dictionary = world.facts.visits[ticket.visit_id]
		var key: String = JSON.stringify([visit.binding_id,visit.complex])
		if not references.has(key):
			if reference==null: reference = _capacity_reference_world(world)
			references[key] = clinic.call("reference_demand",reference,visit.binding_id,visit.complex,shift,reference_query)
			# A whole old-case quote has released its clinical scopes. Stop before
			# another quote or ticket, without exposing accumulated partial work.
			if _capacity_cancelled(cancellation):
				query.cancelled = true
				return {}
			if references[key].has("error"):
				query.error = references[key].error
				query.reason = references[key].reason
				return {}
		var quote: Dictionary = clinic.call("reference_remaining_demand",world,visit.id,shift) if clinic.has_method("reference_remaining_demand") else references[key]
		if _capacity_cancelled(cancellation):
			query.cancelled = true
			return {}
		if quote.has("error"):
			query.error = quote.error
			query.reason = quote.reason
			return {}
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
	if _capacity_cancelled(cancellation):
		query.cancelled = true
		return {}
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
		if stage == "gp" and not kind in ["gp"]:
			continue
		if stage in ["spectrum","resonance"] and visit.evidence_by_source.has(stage):
			continue
		if stage == "consult" and not kind in ["gp","spectrum","resonance","consult"]:
			continue
		for resource_id: String in stages[stage]:
			var amount: Dictionary = F.from_value(stages[stage][resource_id])
			if stage in ["outpatient","surgery","surgery_setup","transfer","bed","care","round"]:
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

func _structural_pairs(world: WorldState, classes: Array, shift: int) -> Dictionary:
	var blocked: Dictionary = {}
	var reception: Dictionary = {"people":{},"desks":{},"ratio":1}
	for id: String in world.facts.staff:
		if _staff_budget(world,id,shift)==0: blocked["staff:"+id] = true
	for id: String in world.facts.facilities:
		var facility: Dictionary = world.facts.facilities[id]
		if facility.get("failed",false) or not facility.get("open",true) or not facility.get("intake_open",true) or facility.get("stop_new_service",false):
			blocked["facility:"+id] = true
	var shape: Array = []
	for case: Dictionary in classes:
		shape.append(_structural_case(case,reception))
	shape = _unique_structural_parts(shape)
	var basis: Array = [shape,blocked,reception,int(content.balance.clinical.beds_per_nurse)]
	var cached: Dictionary = _structure_cache.get(shift,{})
	if not cached.is_empty() and cached.basis==basis: return cached.result.duplicate()
	var result: Dictionary = PlatformArrivalMath.structure(shape,blocked,reception,int(content.balance.clinical.beds_per_nurse))
	if not result.has("error"): _structure_cache[shift] = {"basis":basis.duplicate(true),"result":result.duplicate()}
	return result

func _structural_case(case: Dictionary, reception: Dictionary) -> Dictionary:
	# Mirror only K's actual reads. Group identities derive from their structural
	# options, so C-only retry names/probabilities cannot invalidate this input.
	var result: Dictionary = {"bundles":[],"choice_groups":{},"reception_bundles":[]}
	var groups: Dictionary = case.get("choice_groups",{})
	var translated: Dictionary = {}
	for part: Dictionary in case.bundles:
		var root: Dictionary = {"structural_resources":_structural_resources(part),"structural_choices":[]}
		for field: String in ["coverage_nurse_id","ward_id"]:
			if not str(part.get(field,"")).is_empty(): root[field] = part[field]
		var choices: Array = part.get("structural_choices",[part.structural_group] if part.has("structural_group") else [])
		for group: String in choices:
			root.structural_choices.append(_structural_group(group,groups,translated,result.choice_groups))
		root.structural_choices.sort()
		result.bundles.append(root)
	result.bundles = _unique_structural_parts(result.bundles)
	var registration: Array = case.get("reception_bundles",case.bundles).duplicate()
	if not case.has("reception_bundles"):
		for options: Array in groups.values(): registration.append_array(options)
	for part: Dictionary in registration:
		var resources: Dictionary = {}
		for resource: String in part.get("resources",{}):
			if reception.people.has(resource) or reception.desks.has(resource): resources[resource] = {"n":"1","d":"1"}
		if not resources.is_empty(): result.reception_bundles.append({"resources":resources})
	result.reception_bundles = _unique_structural_parts(result.reception_bundles)
	return result

func _structural_group(group: String, groups: Dictionary, translated: Dictionary, output: Dictionary) -> String:
	if translated.has(group): return translated[group]
	var options: Array = []
	for part: Dictionary in groups[group]:
		var option: Dictionary = {"structural_resources":_structural_resources(part)}
		var children: Array = []
		for child: String in part.get("structural_choices",[]): children.append(_structural_group(child,groups,translated,output))
		if not children.is_empty():
			children.sort()
			option.structural_choices = children
		options.append(option)
	options = _unique_structural_parts(options)
	var identity: String = str(translated.get(options,""))
	if identity.is_empty():
		identity = "group:"+str(output.size())
		output[identity] = options
		translated[options] = identity
	translated[group] = identity
	return identity

func _structural_resources(part: Dictionary) -> Array:
	var unique: Dictionary = {}
	for resource: String in part.get("structural_resources",[]): unique[resource] = true
	var result: Array = unique.keys()
	result.sort()
	return result

func _unique_structural_parts(parts: Array) -> Array:
	var unique: Dictionary = {}
	for part: Dictionary in parts: unique[JSON.stringify(part,"",true,true)] = part
	var identities: Array = unique.keys()
	identities.sort()
	var result: Array = []
	for identity: String in identities: result.append(unique[identity])
	return result

