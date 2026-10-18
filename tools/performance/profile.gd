extends RefCounted

# Root stages are disjoint. Call totals are inclusive and can be nested.
var stages: Dictionary = {}
var calls: Dictionary = {}
var _call_samples: Dictionary = {}
var profile_sources: Dictionary = {}
var profile_errors: Array = []
var snapshot_path: String = ""
var checkpoints: Array = []
var snapshot_overhead_us: int = 0
var trace_phases: bool = false
var phase_trace_path: String = ""
var _phase_trace: FileAccess

func enable_phase_trace(path: String) -> bool:
	_phase_trace = FileAccess.open(path,FileAccess.WRITE)
	if _phase_trace==null:
		profile_errors.append({"error":"cannot open phase trace","path":path})
		return false
	phase_trace_path = path
	trace_phases = true
	return true

func trace_phase(operation: String, world: WorldState, edge: String, result: Variant = null) -> void:
	if not trace_phases: return
	# Diagnostic only: flush each small record so a blocked original call leaves
	# its enter event on disk. Never serialize a world, path or profile here.
	var record: Dictionary = {"engine_us":Time.get_ticks_usec(),"tick":world.sim_tick,"op":operation,"pid":OS.get_process_id(),"edge":edge}
	if edge=="return":
		record.return_type = type_string(typeof(result))
		if result==null or result is bool or result is int or result is float: record["return"] = result
		elif result is String: record["return"] = result.left(160)
		elif result is Array: record.return_count = result.size()
		elif result is Dictionary:
			for key: String in ["ok","status","reason"]:
				if result.has(key) and (result[key] is bool or result[key] is int or result[key] is String):
					record["return_"+key] = str(result[key]).left(160) if result[key] is String else result[key]
	_phase_trace.store_line(JSON.stringify(record))
	_phase_trace.flush()

func checkpoint(stage: String) -> void:
	checkpoints.append({"stage":stage,"ticks_us":Time.get_ticks_usec()})
	_snapshot()

func finish(stage: String, started: int) -> void:
	var elapsed: int = Time.get_ticks_usec()-started
	stages[stage] = elapsed
	print("CASE_STAGE "+JSON.stringify({"stage":stage,"elapsed_us":elapsed}))
	_snapshot()

func count(operation: String, started: int) -> void:
	var elapsed: int = Time.get_ticks_usec()-started
	var entry: Dictionary = calls.get(operation,{"calls":0,"total_us":0,"max_us":0})
	entry.calls += 1
	entry.total_us += elapsed
	entry.max_us = maxi(entry.max_us,elapsed)
	calls[operation] = entry
	if not _call_samples.has(operation): _call_samples[operation] = []
	if _call_samples[operation].size()<10000: _call_samples[operation].append(elapsed)
	# Hot-path counters remain in memory. Serialization belongs to an explicit
	# diagnostic boundary, outside measured execution.

func _snapshot() -> void:
	if snapshot_path.is_empty(): return
	var started: int = Time.get_ticks_usec()
	var file: FileAccess = FileAccess.open(snapshot_path,FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report(),"\t"))
	snapshot_overhead_us += Time.get_ticks_usec()-started

func report() -> Dictionary:
	var distributions: Dictionary = {}
	for operation: String in _call_samples:
		var values: Array = _call_samples[operation].duplicate()
		values.sort()
		var complete: bool = values.size()==int(calls[operation].calls)
		distributions[operation] = {"samples":values.size(),"complete":complete}
		if complete and not values.is_empty():
			for percentile: int in [50,95,99]: distributions[operation]["p%d_us"%percentile] = values[ceili(values.size()*percentile/100.0)-1]
	return {"stages_us":stages.duplicate(true),"inclusive_calls":calls.duplicate(true),"call_distributions":distributions,"profile_sources":profile_sources.duplicate(),"profile_errors":profile_errors.duplicate(),"checkpoints":checkpoints.duplicate(),"previous_snapshot_overhead_us":snapshot_overhead_us}

func solver() -> RefCounted:
	var base: GDScript = preload("res://game/arrivals/capacity_solver.gd")
	# A private diagnostic copy changes static calls into instance calls so
	# wrappers can observe internal stages. Every original body runs once.
	var source: String = base.source_code.replace("class_name ArrivalCapacitySolver\n","").replace("static func ","func ")
	var wrappers: String = "\nvar _performance_timing: RefCounted\n"
	for method: Dictionary in base.get_script_method_list():
		var name: String = str(method.name)
		if not name in ["solve","_maximize","_price_case","_coalesce_cases","_eliminate"]: continue
		var expression: RegEx = RegEx.new()
		expression.compile("(?m)^func "+name+"\\([^\\r\\n]*\\)[^\\r\\n]*:[ \\t]*$")
		var match: RegExMatch = expression.search(source)
		var header: String = match.get_string()
		source = source.replace(header,header.replace("func "+name,"func _performance_original_"+name))
		var arguments: PackedStringArray = []
		for argument: Dictionary in method.args: arguments.append(str(argument.name))
		wrappers += header+"\n\tvar started: int = Time.get_ticks_usec()\n"
		var returns: bool = int(method["return"].type)!=TYPE_NIL
		wrappers += "\t"+("var result: "+type_string(int(method["return"].type))+" = " if returns else "")+"_performance_original_"+name+"("+",".join(arguments)+")\n"
		wrappers += "\t_performance_timing.count(\"solver."+name+"\",started)\n"
		if returns: wrappers += "\treturn result\n"
	source += wrappers
	var file: FileAccess = FileAccess.open("res://performance-solver-profile.gd",FileAccess.WRITE)
	file.store_string(source)
	var script: GDScript = GDScript.new()
	script.source_code = source
	if script.reload()!=OK: return null
	var result: RefCounted = script.new()
	result.set("_performance_timing",self)
	profile_sources.capacity_solver = source.sha256_text()
	return result

func attach(simulation: HospitalSimulation) -> bool:
	# Install before dispatch. Keep the same simulation, services and facts.
	# Every timed override delegates once to its production implementation.
	var before: Dictionary = simulation.world.freeze()
	var old_space: HospitalSpace = simulation.space
	var old_clinic: HospitalClinic = simulation.clinic
	var geometry: HospitalSpace = PhaseSpace.new(simulation.content,self) if trace_phases else TimedSpace.new(simulation.content,self)
	var clinic: HospitalClinic = PhaseClinic.new(simulation.content,geometry,self) if trace_phases else TimedClinic.new(simulation.content,geometry,self)
	for property: Dictionary in old_clinic.get_property_list():
		if (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)!=0:
			clinic.set(property.name,old_clinic.get(property.name))
	simulation.space = geometry
	simulation.clinic = clinic
	_redirect(clinic,old_space,geometry,old_clinic,clinic)
	_redirect(clinic.visitors,old_space,geometry,old_clinic,clinic)
	if trace_phases:
		var visitors: HospitalVisitors = PhaseVisitors.new(simulation.content,geometry,self)
		for property: Dictionary in clinic.visitors.get_property_list():
			if (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)!=0: visitors.set(property.name,clinic.visitors.get(property.name))
		clinic.visitors = visitors
	for service: RefCounted in simulation.services.values():
		_redirect(service,old_space,geometry,old_clinic,clinic)
	for kind: String in simulation._business_handlers:
		if simulation._business_handlers[kind]==old_clinic:
			simulation._business_handlers[kind] = clinic
	for key: String in simulation.services.keys():
		_profile_service(simulation,key)
	return profile_errors.is_empty() and simulation.world.freeze()==before

func _profile_service(simulation: HospitalSimulation, key: String) -> void:
	var original: RefCounted = simulation.services[key]
	var base: GDScript = original.get_script()
	var source: String = "extends \""+base.resource_path+"\"\nvar _acceptance_timing: RefCounted\n"
	var wrapped: int = 0
	for method: Dictionary in base.get_script_method_list():
		var name: String = str(method.name)
		if not name in ["boundaries","arrivals","dispatch","advance","advance_wait","needs","sample","settle"] and not (key=="arrivals" and name in ["capacity","_reference_basis","_reference_geometry_basis","_capacity_reference_world","_case_experience","_reference_classes","_reference_variant","_normalize_bundle","_capacity_part","_resource_budgets","_solve_roles","_existing_workload","_structural_pairs"]) and not (key=="environment" and name in ["environment_at","sample_at","begin_query","_positive_facilities","_nearby_actors","_coverage_edges","_coverage","_water_usable"]) and not (trace_phases and key=="waiting" and name in ["seat_candidates","_seat_quote"]): continue
		var expression: RegEx = RegEx.new()
		expression.compile("(?m)^func "+name+"\\([^\\r\\n]*\\)[^\\r\\n]*:[ \\t]*$")
		var header: RegExMatch = expression.search(base.source_code)
		if header==null: continue
		var arguments: PackedStringArray = []
		for argument: Dictionary in method.args: arguments.append(str(argument.name))
		var returns_value: bool = int(method["return"].type)!=TYPE_NIL
		var assignment: String = "var result: "+type_string(int(method["return"].type))+" = " if returns_value else ""
		var phase: bool = trace_phases and (name in ["boundaries","arrivals","dispatch","advance","advance_wait","needs","sample","settle"] or key=="waiting" and name in ["seat_candidates","_seat_quote"])
		var operation: String = "service."+key+"."+name
		source += header.get_string()+"\n\tvar started: int = Time.get_ticks_usec()\n"
		if phase: source += "\t_acceptance_timing.trace_phase(\""+operation+"\",world,\"enter\")\n"
		source += "\t"+assignment+"super."+name+"("+",".join(arguments)+")\n"
		if phase: source += "\t_acceptance_timing.trace_phase(\""+operation+"\",world,\"return\""+(",result" if returns_value else "")+")\n"
		source += "\t_acceptance_timing.count(\""+operation+"\",started)\n"
		if returns_value: source += "\treturn result\n"
		wrapped += 1
	if wrapped==0: return
	var script: GDScript = GDScript.new()
	script.source_code = source
	if script.reload()!=OK:
		profile_errors.append({"service":key,"error":"timing wrapper did not compile"})
		return
	var replacement: RefCounted = script.new(simulation.content,simulation.space)
	for property: Dictionary in original.get_property_list():
		if (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)!=0: replacement.set(property.name,original.get(property.name))
	replacement.set("_acceptance_timing",self)
	simulation.services[key] = replacement
	var objects: Array = [simulation.clinic,simulation.clinic.visitors]+simulation.services.values()
	for object: Object in objects:
		for property: Dictionary in object.get_property_list():
			if int(property.type)==TYPE_OBJECT and (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)!=0 and object.get(property.name)==original:
				object.set(property.name,replacement)
	for kind: String in simulation._business_handlers:
		if simulation._business_handlers[kind]==original: simulation._business_handlers[kind] = replacement
	profile_sources[key] = source.sha256_text()
	var file: FileAccess = FileAccess.open("res://clinical-profile-"+key+".gd",FileAccess.WRITE)
	if file!=null: file.store_string(source)

func _redirect(object: Object, old_space: HospitalSpace, geometry: HospitalSpace, old_clinic: HospitalClinic, clinic: HospitalClinic) -> void:
	for property: Dictionary in object.get_property_list():
		if int(property.type)!=TYPE_OBJECT or (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)==0: continue
		var value: Variant = object.get(property.name)
		if value==old_space: object.set(property.name,geometry)
		elif value==old_clinic: object.set(property.name,clinic)

class TimedClinic extends HospitalClinic:
	var timing: RefCounted
	func _init(database: HospitalContent, geometry: HospitalSpace, observer: RefCounted) -> void:
		super(database,geometry)
		timing = observer
	func _arrival_candidate(world: WorldState, binding_id: String, complex_case: bool) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._arrival_candidate(world,binding_id,complex_case)
		timing.count("clinical.arrival_candidate",started)
		return result
	func _reference_options(world: WorldState, binding_id: String, complex_case: bool, shift: int, prior_quote: Dictionary = {}, shared: Dictionary = {}, query: Dictionary = {}) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._reference_options(world,binding_id,complex_case,shift,prior_quote,shared,query)
		timing.count("clinical.reference_options.retry" if not prior_quote.is_empty() else "clinical.reference_options.first",started)
		timing.checkpoint("reference_options.retry" if not prior_quote.is_empty() else "reference_options.first")
		return result
	func _reference_terminal_bundle(world: WorldState, visit: Dictionary, reception: Dictionary, diagnostic: Dictionary, quote: Dictionary, stages: Dictionary, query: Dictionary = {}) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._reference_terminal_bundle(world,visit,reception,diagnostic,quote,stages,query)
		timing.count("clinical.reference_terminal_bundle",started)
		return result
	func reference_demand(world: WorldState, binding_id: String, complex_case: bool = false, shift: int = 0, query: Variant = null) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super.reference_demand(world,binding_id,complex_case,shift,query)
		timing.count("clinical.reference_demand",started)
		return result
	func service_candidates(world: WorldState, visit: Dictionary, kind: String, structural_only: bool = false, reference_schedule: bool = false, selection: Dictionary = {}) -> Array:
		var started: int = Time.get_ticks_usec()
		var result: Array = super.service_candidates(world,visit,kind,structural_only,reference_schedule,selection)
		timing.count("clinical.service_candidates."+kind,started)
		return result
	func _reference_bundle(world: WorldState, visit: Dictionary, reception: Dictionary, diagnostic: Dictionary, quote: Dictionary, tests: Dictionary, consultation: Dictionary = {}) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._reference_bundle(world,visit,reception,diagnostic,quote,tests,consultation)
		timing.count("clinical.reference_bundle",started)
		return result
	func _reference_with_retry(first: Dictionary, retry: Dictionary, first_probability_bp: int) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._reference_with_retry(first,retry,first_probability_bp)
		timing.count("clinical.reference_with_retry",started)
		return result
	func _reference_model(options: Dictionary, binding_id: String, complex_case: bool, shift: int) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._reference_model(options,binding_id,complex_case,shift)
		timing.count("clinical.reference_model",started)
		return result
	func dispatch(world: WorldState) -> void:
		var started: int = Time.get_ticks_usec()
		super.dispatch(world)
		timing.count("clinical.dispatch",started)
	func advance(world: WorldState) -> void:
		var started: int = Time.get_ticks_usec()
		super.advance(world)
		timing.count("clinical.advance",started)
	func _ward_covering(world: WorldState, stay: Dictionary) -> bool:
		var started: int = Time.get_ticks_usec()
		var result: bool = super._ward_covering(world,stay)
		timing.count("clinical.ward_covering",started)
		return result
	func _surgery_quote(world: WorldState, visit: Dictionary, requested_team: Array = [], options: Dictionary = {}) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._surgery_quote(world,visit,requested_team,options)
		timing.count("clinical.surgery_quote",started)
		return result
	func _surgery_bundle_quote(world: WorldState, visit: Dictionary, team: Array, facility_id: String, options: Dictionary, bed_quotes: Dictionary) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._surgery_bundle_quote(world,visit,team,facility_id,options,bed_quotes)
		timing.count("clinical.bundle_quote",started)
		return result
	func _compatible_bed(world: WorldState, visit: Dictionary, floor_id: int, excluded: Array, structural_only: bool = false, preferred_bed: String = "", reference_schedule: bool = false, alternatives: Variant = null) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._compatible_bed(world,visit,floor_id,excluded,structural_only,preferred_bed,reference_schedule,alternatives)
		timing.count("clinical.compatible_bed",started)
		return result
	func _reserve_bundle(world: WorldState, visit: Dictionary, quote: Dictionary, owner_id: String) -> String:
		var started: int = Time.get_ticks_usec()
		var result: String = super._reserve_bundle(world,visit,quote,owner_id)
		timing.count("clinical.reserve_bundle",started)
		return result

class TimedSpace extends HospitalSpace:
	var timing: RefCounted
	var _facility_depth: int = 0
	func _init(database: HospitalContent, observer: RefCounted) -> void:
		super(database)
		timing = observer
		_navigation = TimedNavigation.new(observer)
	func advance(world: WorldState, present_at_start: int = -1) -> void:
		var started: int = Time.get_ticks_usec()
		super.advance(world,present_at_start)
		timing.count("space.advance",started)
	func _reserve_doors(world: WorldState, actor: Dictionary, movement: Dictionary, swept: Rect2) -> bool:
		var started: int = Time.get_ticks_usec()
		var result: bool = super._reserve_doors(world,actor,movement,swept)
		timing.count("space.reserve_doors",started)
		return result
	func _active_route_clear(world: WorldState, actor: Dictionary, movement: Dictionary, versions: Dictionary) -> bool:
		var started: int = Time.get_ticks_usec()
		var result: bool = super._active_route_clear(world,actor,movement,versions)
		timing.count("space.active_route_clear",started)
		return result
	func _dispatch_routes(world: WorldState, present_at_start: int) -> void:
		var started: int = Time.get_ticks_usec()
		super._dispatch_routes(world,present_at_start)
		timing.count("space.dispatch_routes",started)
	func route(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super.route(world,actor_id,floor_id,target,members,offsets,ignore_people)
		timing.count("space.route",started)
		return result
	func facility_quote(world: WorldState, facility_id: String, actor_id: String, staff_ids: Array = []) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		_facility_depth += 1
		var result: Dictionary = super.facility_quote(world,facility_id,actor_id,staff_ids)
		_facility_depth -= 1
		timing.count("space.facility_quote",started)
		return result
	func _floor_route(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2i, goal: Vector2i, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false, navigation: Dictionary = {}) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._floor_route(world,actor,floor_id,start,goal,members,offsets,ignore_people,navigation)
		timing.count("space.facility_exit_route" if _facility_depth>0 else "space.floor_route",started)
		return result
	func _exit_witness(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2i, exit: Vector2i) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._exit_witness(world,actor,floor_id,start,exit)
		timing.count("space.exit_witness",started)
		return result

class TimedNavigation extends NavigationCache:
	var timing: RefCounted
	var _seen_graphs: Dictionary = {}
	func _init(observer: RefCounted) -> void:
		timing = observer
	func graph(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, members: Array, offsets: Dictionary) -> FloorNavigation:
		var started: int = Time.get_ticks_usec()
		var result: FloorNavigation = super.graph(space,world,floor_id,actor,members,offsets)
		var id: int = result.get_instance_id()
		timing.count("navigation.graph_new" if not _seen_graphs.has(id) else "navigation.graph_reuse_or_refresh",started)
		_seen_graphs[id] = true
		timing.count("navigation.graph",started)
		return result
	func _trim(target: int) -> void:
		var started: int = Time.get_ticks_usec()
		super._trim(target)
		timing.count("navigation.trim",started)
	func _refresh_graph(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, members: Array, offsets: Dictionary, source: Dictionary, entry: Dictionary) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var fresh: bool = entry.is_empty()
		var result: Dictionary = super._refresh_graph(space,world,floor_id,actor,members,offsets,source,entry)
		timing.count("navigation.build" if fresh else "navigation.refresh",started)
		return result
	func _distance_field(graph: FloorNavigation, query: RouteClearance, goal: Vector2i) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._distance_field(graph,query,goal)
		timing.count("navigation.distance_field",started)
		return result

# These subclasses are installed only for --trace-phases. Default timed
# overrides retain their existing call path and counters without trace I/O.
class PhaseClinic extends TimedClinic:
	func _init(database: HospitalContent, geometry: HospitalSpace, observer: RefCounted) -> void:
		super(database,geometry,observer)
	func arrivals(world: WorldState) -> void:
		timing.trace_phase("clinical.arrivals",world,"enter")
		super.arrivals(world)
		timing.trace_phase("clinical.arrivals",world,"return")
	func dispatch(world: WorldState) -> void:
		timing.trace_phase("clinical.dispatch",world,"enter")
		super.dispatch(world)
		timing.trace_phase("clinical.dispatch",world,"return")
	func advance(world: WorldState) -> void:
		timing.trace_phase("clinical.advance",world,"enter")
		super.advance(world)
		timing.trace_phase("clinical.advance",world,"return")
	func release_departed(world: WorldState) -> void:
		timing.trace_phase("clinical.release_departed",world,"enter")
		super.release_departed(world)
		timing.trace_phase("clinical.release_departed",world,"return")
	func settle_practice(world: WorldState) -> void:
		timing.trace_phase("clinical.settle_practice",world,"enter")
		super.settle_practice(world)
		timing.trace_phase("clinical.settle_practice",world,"return")

class PhaseVisitors extends HospitalVisitors:
	var timing: RefCounted
	func _init(database: HospitalContent, geometry: HospitalSpace, observer: RefCounted) -> void:
		super(database,geometry)
		timing = observer
	func arrivals(world: WorldState) -> void:
		timing.trace_phase("visitor.arrivals",world,"enter")
		super.arrivals(world)
		timing.trace_phase("visitor.arrivals",world,"return")
	func _admit(world: WorldState, visit: Dictionary, request: Dictionary) -> bool:
		timing.trace_phase("visitor._admit",world,"enter")
		var result: bool = super._admit(world,visit,request)
		timing.trace_phase("visitor._admit",world,"return",result)
		return result
	func _waiting_point(world: WorldState, actor_id: String, facility_ids: Variant = null) -> Dictionary:
		timing.trace_phase("visitor._waiting_point",world,"enter")
		var result: Dictionary = super._waiting_point(world,actor_id,facility_ids)
		timing.trace_phase("visitor._waiting_point",world,"return",result)
		return result
	func dispatch(world: WorldState) -> void:
		timing.trace_phase("visitor.dispatch",world,"enter")
		super.dispatch(world)
		timing.trace_phase("visitor.dispatch",world,"return")
	func advance(world: WorldState) -> void:
		timing.trace_phase("visitor.advance",world,"enter")
		super.advance(world)
		timing.trace_phase("visitor.advance",world,"return")

class PhaseSpace extends TimedSpace:
	func _init(database: HospitalContent, observer: RefCounted) -> void:
		super(database,observer)
		_navigation = PhaseNavigation.new(observer)
	func advance(world: WorldState, present_at_start: int = -1) -> void:
		timing.trace_phase("space.advance",world,"enter")
		super.advance(world,present_at_start)
		timing.trace_phase("space.advance",world,"return")
	func static_reason(world: WorldState, actor: Dictionary, floor_id: int, origin: Vector2i, members: Array = [], offsets: Dictionary = {}) -> String:
		timing.trace_phase("space.static_reason",world,"enter")
		var result: String = super.static_reason(world,actor,floor_id,origin,members,offsets)
		timing.trace_phase("space.static_reason",world,"return",result)
		return result
	func route(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false) -> Dictionary:
		timing.trace_phase("space.route",world,"enter")
		var result: Dictionary = super.route(world,actor_id,floor_id,target,members,offsets,ignore_people)
		timing.trace_phase("space.route",world,"return",result)
		return result
	func facility_quote(world: WorldState, facility_id: String, actor_id: String, staff_ids: Array = []) -> Dictionary:
		timing.trace_phase("space.facility_quote",world,"enter")
		var result: Dictionary = super.facility_quote(world,facility_id,actor_id,staff_ids)
		timing.trace_phase("space.facility_quote",world,"return",result)
		return result
	func _floor_route(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2i, goal: Vector2i, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false, navigation: Dictionary = {}) -> Dictionary:
		timing.trace_phase("space.floor_route",world,"enter")
		var result: Dictionary = super._floor_route(world,actor,floor_id,start,goal,members,offsets,ignore_people,navigation)
		timing.trace_phase("space.floor_route",world,"return",result)
		return result

class PhaseNavigation extends TimedNavigation:
	func _init(observer: RefCounted) -> void:
		super(observer)
	func graph(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, members: Array, offsets: Dictionary) -> FloorNavigation:
		timing.trace_phase("navigation.graph",world,"enter")
		var result: FloorNavigation = super.graph(space,world,floor_id,actor,members,offsets)
		timing.trace_phase("navigation.graph",world,"return",result)
		return result
	func _refresh_graph(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, members: Array, offsets: Dictionary, source: Dictionary, entry: Dictionary) -> Dictionary:
		var operation: String = "navigation.build" if entry.is_empty() else "navigation.refresh"
		timing.trace_phase(operation,world,"enter")
		var result: Dictionary = super._refresh_graph(space,world,floor_id,actor,members,offsets,source,entry)
		timing.trace_phase(operation,world,"return",result)
		return result
