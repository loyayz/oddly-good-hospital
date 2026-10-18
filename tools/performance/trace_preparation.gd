extends SceneTree

const Fixture = preload("res://tools/performance/fixture.gd")

# Diagnostic only. Capture uses ArrivalPreparation's original implementation;
# one synchronous owner then builds the same fresh worker services as _compute.
# No GameSession or competing simulation thread runs here. Trace I/O and this
# scheduling difference prevent these timings from being Release acceptance.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source: String = ""
	var output: String = ""
	var subtract_existing: bool = true
	var target: String = "next_day"
	var single_binding: String = ""
	var fine: bool = false
	var reserved_world: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="): source = argument.trim_prefix("--input=")
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument=="--subtract-existing=false": subtract_existing = false
		if argument.begins_with("--target="): target = argument.trim_prefix("--target=")
		if argument.begins_with("--binding="): single_binding = argument.trim_prefix("--binding=")
		if argument=="--fine": fine = true
		if argument=="--reserved-world": reserved_world = true
	if source.is_empty() or not FileAccess.file_exists(source) or output.is_empty() or FileAccess.file_exists(output) or not target in ["current","next_day"]:
		push_error("Expected existing --input, new --output NDJSON, optional --target=current|next_day and --subtract-existing=false.")
		quit(2)
		return
	var trace: Trace = Trace.new(output)
	trace.fine = fine
	trace.reserved_world = reserved_world
	if trace.file==null:
		push_error("Cannot open preparation trace: "+output)
		quit(2)
		return
	trace.emit("diagnostic","enter",{"input":source,"input_sha256":FileAccess.get_sha256(source),"synchronous_owner":true,"game_session":false,"flush_each_event":true,"tracked_memory_is_os_memory":false})
	var content: HospitalContent = HospitalContent.new()
	if not content.error.is_empty():
		trace.emit("content","failure",{"reason":content.error.left(240)})
		quit(2)
		return
	var fixture: RefCounted = Fixture.new(content,160,"four_floors",source)
	var validation: String = fixture.world.validate(content)
	if not validation.is_empty() or not fixture.errors.is_empty():
		trace.emit("input","failure",{"reason":validation.left(240),"fixture_errors":fixture.errors.size()})
		quit(2)
		return
	trace.emit("input","return",{"source_tick":fixture.world.sim_tick,"content_fingerprint":content.content_fingerprint,"actors":fixture.world.facts.actors.size(),"staff":fixture.world.facts.staff.size(),"catalog_bindings":content.catalog.treatment_bindings.size()})
	var preparation: ArrivalPreparation = ArrivalPreparation.new(content)
	var target_tick: int = (fixture.world.sim_tick/WorldState.TICKS_PER_DAY+1)*WorldState.TICKS_PER_DAY if target=="next_day" else -1
	trace.emit("capture","enter",{"subtract_existing":subtract_existing,"target_tick":target_tick})
	var input: Dictionary = preparation._capture(fixture.world,subtract_existing,target_tick)
	trace.emit("capture","return",{"captured_tick":input.facts.sim_tick,"captured_actors":input.facts.actors.size(),"captured_visits":input.facts.visits.size(),"captured_facilities":input.facts.facilities.size()})
	var geometry: HospitalSpace = TracedSpace.new(content) if fine else HospitalSpace.new(content)
	var worker: TracedArrivalService = TracedArrivalService.new(content,geometry,trace)
	worker.clinic = TracedClinic.new(content,geometry,trace)
	worker.clinic.scheduler = HospitalShiftScheduler.new(content,geometry)
	worker.clinic.recruitment = RecruitmentService.new(content,geometry)
	worker.clinic.departments = HospitalDepartments.new(content,geometry)
	worker.departments = worker.clinic.departments
	trace.emit("worker","enter",{},null,worker,geometry)
	# The optional single case is a complete-candidate localization probe. It
	# cannot establish full-catalog C/K or Release acceptance.
	var projection: Dictionary
	if single_binding.is_empty():
		projection = worker.capacity(WorldState.new(input.facts),input.subtract_existing)
	else:
		var nominal: WorldState = worker._capacity_reference_world(WorldState.new(input.facts))
		trace.emit("single_case_probe","enter",{"single_binding":single_binding,"full_capacity":false,"nominal_reference_world":true,"reserved_world":reserved_world,"adaptations":nominal.facts.adaptations.size()})
		var quote: Dictionary = worker.clinic.reference_demand(nominal,single_binding,false,0,{})
		projection = {"complete":quote.get("ok",false),"reason":quote.get("reason","")}
		trace.emit("single_case_probe","return",{"single_binding":single_binding,"full_capacity":false,"ok":quote.get("ok",false)})
	var final_fields: Dictionary = {"complete":projection.get("complete",false),"cancelled":projection.get("cancelled",false),"reason":str(projection.get("reason","")).left(240)}
	for key: String in ["capacity","shift_capacities","shift_pairs","bottleneck"]:
		if projection.has(key): final_fields[key] = projection[key]
	trace.emit("worker","return",final_fields,null,worker,geometry)
	var complete: bool = projection.get("complete",false)
	worker = null
	geometry = null
	input = {}
	preparation.dispose()
	trace.emit("worker_released","return")
	trace.file.close()
	print("PREPARATION_TRACE="+JSON.stringify({"path":output,"pid":OS.get_process_id(),"complete":complete,"diagnostic_only":true}))
	quit(0 if complete else 1)

class Trace extends RefCounted:
	var file: FileAccess
	var binding: String = ""
	var complex_case: bool = false
	var shift: int = -1
	var reference_calls: int = 0
	var variants_returned: int = 0
	var normalized_parts: int = 0
	var capacity_parts: int = 0
	var clinical_components: int = 0
	var sequence: int = 0
	var fine: bool = false
	var reserved_world: bool = false

	func _init(path: String) -> void:
		file = FileAccess.open(path,FileAccess.WRITE)

	func emit(operation: String, edge: String, fields: Dictionary = {}, query: Variant = null, service: HospitalArrivalService = null, geometry: HospitalSpace = null) -> void:
		sequence += 1
		var record: Dictionary = {"sequence":sequence,"engine_us":Time.get_ticks_usec(),"pid":OS.get_process_id(),"op":operation,"edge":edge,"binding":binding,"complex":complex_case,"shift":shift,
			"tracked_bytes":OS.get_static_memory_usage(),"debug_feature":OS.has_feature("debug"),"reference_calls_started":reference_calls,"variants_returned":variants_returned,
			"normalized_parts":normalized_parts,"capacity_parts":capacity_parts,"clinical_components":clinical_components}
		var clock: Dictionary = PlatformArrivalMath.monotonic_clock()
		if clock.has("qpc_ticks"):
			record.qpc_ticks = clock.qpc_ticks
			record.qpc_frequency = clock.qpc_frequency
		if query is Dictionary:
			for name: String in ["candidates","plans","bed_transport","diagnostics","diagnostic_stages","consultations","resource_maps","parts","fractions","normalized_fractions","references"]:
				record["query_"+name] = query.get(name,{}).size()
			var batch: Variant = query.get("component_batch",[])
			record.query_pending_component_requests = batch.pending.size() if batch is Dictionary else batch.size()
			record.query_waiting_component_targets = int(batch.waiting_targets) if batch is Dictionary else batch.size()
			var reference: Dictionary = query.get("geometry",{})
			for name: String in ["routes","fits","journeys"]: record["geometry_"+name] = reference.get(name,{}).size()
		if service!=null:
			if service.clinic.has_method("reference_component_observation"):
				var numbers: Dictionary = service.clinic.call("reference_component_observation",query)
				for name: String in numbers: record["numeric_"+name] = numbers[name]
			for index: int in 3: record["cached_cases_"+str(index)] = service._reference_cache.get(index,{}).get("cases",{}).size()
			record.retained_role_models = service._role_models.size()
			record.retained_structure_models = service._structure_cache.size()
		if geometry!=null:
			record.route_scope_depth = geometry._route_queries.size()
			record.navigation_entries = geometry._navigation._entries.size()
			record.navigation_sources = geometry._navigation._sources.size()
			record.navigation_charged_estimate = geometry._navigation._charged+geometry._navigation._query_charged
		record.merge(fields,true)
		# Only fresh scalar records cross into JSON; no world, model, path or
		# mutable cache is retained by this observer or read by another thread.
		file.store_line(JSON.stringify(record))
		file.flush()

	func model_counts(model: Dictionary) -> Dictionary:
		var groups: Dictionary = model.get("choice_groups",{})
		var parts: int = model.get("bundles",[]).size()
		for group: String in groups: parts += groups[group].size()
		return {"model_bases":model.get("bundles",[]).size(),"model_groups":groups.size(),"model_parts":parts}

class TracedArrivalService extends HospitalArrivalService:
	var trace: Trace

	func _init(database: HospitalContent, geometry: HospitalSpace, observer: Trace) -> void:
		super(database,geometry)
		trace = observer

	func capacity(world: WorldState, subtract_existing: bool = true, cancellation: Callable = Callable()) -> Dictionary:
		trace.emit("capacity","enter",{"binding":"","tick":world.sim_tick,"subtract_existing":subtract_existing},null,self,space)
		var result: Dictionary = super.capacity(world,subtract_existing,cancellation)
		trace.emit("capacity","return",{"binding":"","complete":result.get("complete",false)},null,self,space)
		return result

	func _reference_classes(world: WorldState, shift: int, query: Variant = null, cancellation: Callable = Callable()) -> Array:
		trace.shift = shift
		trace.emit("reference_classes","enter",{"binding":""},query,self,space)
		var result: Array = super._reference_classes(world,shift,query,cancellation)
		trace.emit("reference_classes","return",{"binding":"","classes":result.size()},query,self,space)
		return result

	func _reference_variant(world: WorldState, binding: Dictionary, complex_case: bool, shift: int, quote: Dictionary, query: Dictionary) -> Dictionary:
		trace.emit("reference_variant","enter",trace.model_counts(quote.get("model",{})),query,self,space)
		var result: Dictionary = super._reference_variant(world,binding,complex_case,shift,quote,query)
		trace.variants_returned += 1
		trace.emit("reference_variant","return",trace.model_counts(result),query,self,space)
		return result

	func _normalize_bundle(world: WorldState, source: Dictionary, query: Variant = null) -> Dictionary:
		var result: Dictionary = super._normalize_bundle(world,source,query)
		trace.normalized_parts += 1
		return result

	func _capacity_part(bundle: Dictionary, query: Dictionary, structural: bool) -> Dictionary:
		var result: Dictionary = super._capacity_part(bundle,query,structural)
		trace.capacity_parts += 1
		return result

	func _existing_workload(world: WorldState, shift: int, query: Variant = null, commitments: Dictionary = {}, cancellation: Callable = Callable()) -> Dictionary:
		trace.emit("existing_workload","enter",{"binding":"","tickets":world.facts.tickets.size()},query,self,space)
		var result: Dictionary = super._existing_workload(world,shift,query,commitments,cancellation)
		trace.emit("existing_workload","return",{"binding":"","workload_resources":result.size()},query,self,space)
		return result

	func _solve_roles(world: WorldState, classes: Array, budgets: Dictionary, shift: int, model_key: Variant = null, locked_roles: Dictionary = {}) -> Dictionary:
		trace.emit("solve_roles","enter",{"binding":"","classes":classes.size(),"budgets":budgets.size(),"locked_roles":locked_roles.size(),"has_cached_backend":_role_models.has(shift)},null,self,space)
		var result: Dictionary = super._solve_roles(world,classes,budgets,shift,model_key,locked_roles)
		var fields: Dictionary = {"binding":"","error":str(result.get("error","")),"reason":str(result.get("bottleneck","")).left(240)}
		for key: String in ["node_count","edge_count","coefficient_count","bundle_count","mip_variables","mip_constraints","lp_rounds","certificate_nonzeros","structural_pairs","prepare_fraction_requests","prepare_fraction_hits","pricing_calls","timing_us","nursing_timing_us"]:
			if result.has(key): fields[key] = result[key]
		trace.emit("solve_roles","return",fields,null,self,space)
		return result

	func _structural_pairs(world: WorldState, classes: Array, shift: int) -> Dictionary:
		# On a cold role solve this enter event is after native C has returned;
		# super may reuse K's structural cache or call the original native K.
		trace.emit("structural_pairs","enter",{"binding":"","native_c_returned":true},null,self,space)
		var result: Dictionary = super._structural_pairs(world,classes,shift)
		var fields: Dictionary = {"binding":"","pairs":result.get("pairs",0),"error":str(result.get("error",""))}
		for key: String in ["terminals","structure_encoding","structural_nodes","structural_slots","structural_variables","structural_constraints"]:
			if result.has(key): fields[key] = result[key]
		trace.emit("structural_pairs","return",fields,null,self,space)
		return result

class TracedClinic extends HospitalClinic:
	var trace: Trace

	func _init(database: HospitalContent, geometry: HospitalSpace, observer: Trace) -> void:
		super(database,geometry)
		trace = observer

	func _emit(operation: String, edge: String, fields: Dictionary = {}, query: Variant = null) -> void:
		if has_method("reference_component_observation"):
			var numbers: Dictionary = call("reference_component_observation",query)
			for name: String in numbers: fields["numeric_"+name] = numbers[name]
		trace.emit(operation,edge,fields,query,null,space)

	func _arrival_candidate(world: WorldState, binding_id: String, complex_case: bool) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._arrival_candidate(world,binding_id,complex_case)
		if trace.fine: _emit("arrival_candidate","return",{"elapsed_us":Time.get_ticks_usec()-started,"ok":result.get("ok",false),"reason":result.get("reason","")})
		return result

	func _reference_routing_unchanged(world: WorldState, layout: Dictionary, fit: Dictionary) -> bool:
		return false if trace.reserved_world else super._reference_routing_unchanged(world,layout,fit)

	func service_candidates(world: WorldState, visit: Dictionary, kind: String, structural_only: bool = false, reference_schedule: bool = false, selection: Dictionary = {}) -> Array:
		var started: int = Time.get_ticks_usec()
		var before: Dictionary = (space as TracedSpace).snapshot() if space is TracedSpace else {}
		var result: Array = super.service_candidates(world,visit,kind,structural_only,reference_schedule,selection)
		if trace.fine:
			_emit("service_candidates","return",{"kind":kind,"structural_only":structural_only,"reference_schedule":reference_schedule,"selection":selection,"elapsed_us":Time.get_ticks_usec()-started,"candidates":result.size(),"geometry_delta":(space as TracedSpace).delta(before)})
		return result

	func reference_demand(world: WorldState, binding_id: String, complex_case: bool = false, shift: int = 0, query: Variant = null) -> Dictionary:
		trace.binding = binding_id
		trace.complex_case = complex_case
		trace.shift = shift
		trace.reference_calls += 1
		_emit("reference_demand","enter",{},query)
		var result: Dictionary = super.reference_demand(world,binding_id,complex_case,shift,query)
		var fields: Dictionary = trace.model_counts(result.get("model",{}))
		fields.ok = result.get("ok",false)
		fields.reason = result.get("reason","")
		fields.queue_representatives = result.get("bundles",[]).size()
		_emit("reference_demand","return",fields,query)
		return result

	func _reference_options(world: WorldState, binding_id: String, complex_case: bool, shift: int, prior_quote: Dictionary = {}, shared: Dictionary = {}, query: Dictionary = {}) -> Dictionary:
		var operation: String = "reference_options_retry" if not prior_quote.is_empty() else "reference_options_first"
		_emit(operation,"enter",{},query)
		var result: Dictionary = super._reference_options(world,binding_id,complex_case,shift,prior_quote,shared,query)
		var fields: Dictionary = {"ok":result.get("ok",false),"terminals":result.get("terminals",[]).size(),"bed_quotes":result.get("bed_quotes",{}).size()}
		for kind: String in ["outpatient","surgery"]: fields["physical_"+kind] = result.get("physical",{}).get(kind,{}).size()
		_emit(operation,"return",fields,query)
		return result

	func _reference_model(options: Dictionary, binding_id: String, complex_case: bool, shift: int) -> Dictionary:
		_emit("reference_model","enter",{"terminals":options.terminals.size()},options.query)
		var result: Dictionary = super._reference_model(options,binding_id,complex_case,shift)
		_emit("reference_model","return",trace.model_counts(result.get("model",{})),options.query)
		return result

	func _reference_component(full: Dictionary, stages: Array, weight: Dictionary = {"n":"1","d":"1"}, batch: Variant = null) -> Dictionary:
		var result: Dictionary = super._reference_component(full,stages,weight,batch)
		trace.clinical_components += 1
		return result

class TracedSpace extends HospitalSpace:
	# Cumulative inclusive timings; nested route/floor times must not be added.
	var observations: Dictionary = {}

	func _init(database: HospitalContent) -> void:
		super(database)
		_navigation = TracedNavigation.new(observations)

	func _add(operation: String, elapsed: int) -> void:
		observations[operation+"_calls"] = int(observations.get(operation+"_calls",0))+1
		observations[operation+"_us"] = int(observations.get(operation+"_us",0))+elapsed

	func snapshot() -> Dictionary:
		return observations.duplicate()

	func delta(before: Dictionary) -> Dictionary:
		var result: Dictionary = {}
		for key: String in observations: result[key] = int(observations[key])-int(before.get(key,0))
		return result

	func facility_quote(world: WorldState, facility_id: String, actor_id: String, staff_ids: Array = []) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super.facility_quote(world,facility_id,actor_id,staff_ids)
		_add("facility_quote",Time.get_ticks_usec()-started)
		if result.get("ok",false) and not result.get("unchanged",false):
			var base: Dictionary = facility_layout(world,facility_id)
			var same: bool = true
			for key: String in ["floor_id","footprint","patient_cell","operator_cells","repair_cell"]: same = same and base.get(key,[])==result.get(key,[])
			_add("fit_navigation_equal" if same else "fit_navigation_changed",0)
		return result

	func route(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super.route(world,actor_id,floor_id,target,members,offsets,ignore_people)
		_add("route",Time.get_ticks_usec()-started)
		return result

	func _floor_route(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2i, goal: Vector2i, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false, navigation: Dictionary = {}) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._floor_route(world,actor,floor_id,start,goal,members,offsets,ignore_people,navigation)
		_add("floor_route",Time.get_ticks_usec()-started)
		return result

class TracedNavigation extends NavigationCache:
	var observations: Dictionary

	func _init(counters: Dictionary) -> void:
		observations = counters

	func _add(operation: String, elapsed: int) -> void:
		observations[operation+"_calls"] = int(observations.get(operation+"_calls",0))+1
		observations[operation+"_us"] = int(observations.get(operation+"_us",0))+elapsed

	func floor_source(space: HospitalSpace, world: WorldState, floor_id: int) -> Dictionary:
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super.floor_source(space,world,floor_id)
		_add("floor_source",Time.get_ticks_usec()-started)
		return result

	func graph(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, members: Array, offsets: Dictionary) -> FloorNavigation:
		var started: int = Time.get_ticks_usec()
		var result: FloorNavigation = super.graph(space,world,floor_id,actor,members,offsets)
		_add("navigation_graph",Time.get_ticks_usec()-started)
		return result
