extends RefCounted

# Diagnostic-only source instrumentation. Production scripts, facts, random
# streams and phase bodies are unchanged. The driver times plain .step()
# separately; profiled durations only describe where the observed step ran.
const SIMULATION = preload("res://game/sim/simulation.gd")
const COMMON_METHODS: Array[String] = ["boundaries","arrivals","dispatch","advance","advance_wait","needs","sample","settle","worked_staff","take_events"]
const HOT_METHODS: Dictionary = {
	"clinic":["arrivals","dispatch","advance","release_departed","settle_practice","service_candidates","_dispatch_service","_gather_assigned","_prepare_surgery","_surgery_quote","_surgery_bundle_quote","_qualified_surgery_bundle_quote","_compatible_bed","_ward_covering","_round_candidate","_select_plan","plan_quote","_outpatient_quote","_availability","_build_availability","_gather","_complete_service","_dispatch_clinical_releases","_dispatch_ward_returns","_reserve_bundle","_reservation_candidate","arrival_readiness","reference_demand","_reference_options"],
	"space":["advance","route","route_cost","can_reach","_route_result","travel_quote","nearby_reachable","facility_quote","facility_preflight_quote","facility_geometry_quote","_facility_quote","_facility_geometry_view","_facility_exit_quote","facility_trip_quote","reserve_facility","_floor_route","_exit_witness","_ensure_actor_index","begin_actor_exclusion_query","_actor_exclusion_scope","_build_reservation_view","reservation_view","_reservation_regions","_dynamic_clear","movement_doors","prepare_projection","finish_boundary"],
	"point_navigation":["_route_result","travel_quote","connection_basis","routing_floor_basis","structural_clearance","_topology","_topology_floor_nodes","_point_route","_point_edges","_floor_route"],
	"movement":["request_move","request_group_move","_retarget","failure","cancel_ground","advance","_move_step","_unit_sweeps","_queue_route","_replan_goal","_active_route_clear","_dispatch_routes","queue_waypoint","_queue_local_route","_local_goal_occupied","_movement_contacts","_reserve_doors","_route_occupancy","_yield","_yield_idle_staff"],
	"navigation":["floor_source","floor_static_version","_static_identity","facility_index","cached_static_geometry","query_graphs","graph","_refresh_graph","_trim","clearance","_reservation_stamp","_build_reservation_stamp","cached_floor_path","travel_distance","forward_distance","_travel_distance"],
	"floor_graph":["_build","refresh","_repair","find_path","distance_field"],
	"clearance":["_init","_build_static","capture_source","capture_occupancy"],
	"visitors":["arrivals","dispatch","advance","_waiting_point","_public_waiting","_public_wait_position","_public_seat_quote","_take_waiting_seat","yield_seat","_bedside","_bedside_in_query"],
	"public_areas":["_ensure","region","contains","current_area","select","waiting_point","_waiting_point","_entry_order","_ordered_entry_cells","_entry_landings","_entry_lower_bound","_entry_geometry_view","safe_wait","_safe_wait_geometry","_wait_constraints","facilities","compatible_geometry","should_recheck","remember_wait","_decision_view","_decision_signature","_environment_samples","_add_dynamic_dependencies","turn","_queue_members","_facility_queue","_queue_fit","_queue_fit_in_query","_intent_view","_wait_estimate","_wait_estimate_view"],
	"personal_beds":["sync","bed_for"],
	"environment":["begin_query","end_query","environment_at","sample_at","_observe_at","_coverage_edges","_coverage","_positive_facilities","_nearby_actors","_water_usable","_work_position","_safety_query","_tool","_arrive"],
	"waiting":["_dispatch_public_seat","_dispatch_public_need","seat_candidates","_seat_candidates_in_query","_seat_quote","_seat_quote_in_query","_manual_seat_quote","_seat_target_quote","_claim_seat","_wait_safely","_claim_need","_wait_need","_start_fallback","_score_seat","_conditions","_condition_actor_index","_environment","facility_availability","_facility_availability","_facility_quote","_facility_quote_in_query","_occupancy_view"],
	"wellbeing":["_dispatch_task","_dispatch_public_rest","_dispatch_public_recreation","_recreation_choice","_recreation_choice_in_query","_recreation_equipment_quote","_select_facility","_tea_position","_public_entry","_public_wait_safety","_reserve","_adapted_candidate","_staff_query","_patient_occupancy"],
	"maintenance":["_position","_any_repair_position","_dispatch_departures","_worker_ready"],
	"arrivals":["capacity","_reference_basis","_existing_workload","_case_experience","_resource_budgets"]
}

var errors: Array = []
var sources: Dictionary = {}
var source_directory: String = "res://.cache/performance-loop-20261018/profile-sources"
var samples: Array = []
var max_step_records: int = 2048
var _active: bool = false
var _current: Dictionary = {}
var _stack: Array = []
var _observer_us: int = 0
var _root_name: String = ""
var _root_started: int = 0
var _root_observer_started: int = 0
var _root_calls: int = 0
var _call_edges: int = 0
var _steps_total: int = 0
var _complete_total: int = 0
var _incomplete_total: int = 0
var _outer_total_us: int = 0
var _observer_total_us: int = 0
var _residual_total_us: int = 0
var _stage_totals: Dictionary = {}
var _call_totals: Dictionary = {}
var _generated_scripts: Array[GDScript] = []

func create(state: WorldState, database: HospitalContent, nested: bool = true) -> HospitalSimulation:
	var original: HospitalSimulation = HospitalSimulation.new(state,database)
	return attach(original,nested)

func attach(original: HospitalSimulation, nested: bool = true) -> HospitalSimulation:
	# Ownership transfers to the returned simulation. Discard the old simulation
	# without disposing it: its live service graph and cache identities transfer.
	if original.step_in_progress():
		errors.append("attach requires a complete step boundary")
		return null
	var before: Dictionary = original.world.freeze()
	var base: GDScript = SIMULATION
	var method: String = _method_source(base.source_code,"step_nonblocking")
	if method.is_empty():
		errors.append("step_nonblocking source not found")
		return null
	var instrumented: String = _instrument_root(method)
	if instrumented.is_empty(): return null
	var source: String = "extends \"res://game/sim/simulation.gd\"\nvar _step_profile_observer: RefCounted\n"+instrumented
	var script: GDScript = _compile("simulation",base,source)
	if script==null: return null
	var result: HospitalSimulation = script.new(original.world,original.content)
	# Dispose only the newly constructed services before transferring the exact
	# existing runtime state, including caches and queued command identities.
	result.dispose()
	_copy_script_properties(original,result)
	result.set("_step_profile_observer",self)
	if nested and not _attach_nested(result): return null
	if result.world.freeze()!=before:
		errors.append("attach changed frozen world state")
		return null
	sources.nested_enabled = nested
	sources.attach_world_unchanged = true
	return result

func begin_step() -> void:
	if _active:
		errors.append("begin_step called before end_step")
		return
	_current = {"stages":{},"calls":{},"nonblocking_invocations":0}
	_stack = []
	_observer_us = 0
	_root_name = ""
	_root_started = 0
	_root_calls = 0
	_call_edges = 0
	_active = true

func end_step(result: TickResult, outer_elapsed_us: int) -> Dictionary:
	if not _active:
		errors.append("end_step called without begin_step")
		return {}
	if not _root_name.is_empty(): close_root()
	_active = false
	if not _stack.is_empty(): errors.append("unbalanced nested call stack")
	var stage_sum: int = 0
	for entry: Dictionary in _current.stages.values(): stage_sum += int(entry.total_us)
	var record: Dictionary = {"complete":result!=null,"outer_elapsed_us":outer_elapsed_us,"root_stage_us":stage_sum,"observer_handler_us":_observer_us,"residual_us":outer_elapsed_us-stage_sum-_observer_us,"root_marker_calls":_root_calls,"nested_call_edges":_call_edges,"nonblocking_invocations":_current.nonblocking_invocations,"stages":_current.stages.duplicate(true),"calls":_current.calls.duplicate(true)}
	if result!=null: record.tick = result.sim_tick
	_steps_total += 1
	if result!=null: _complete_total += 1
	else: _incomplete_total += 1
	_outer_total_us += outer_elapsed_us
	_observer_total_us += _observer_us
	_residual_total_us += int(record.residual_us)
	_accumulate(_stage_totals,_current.stages)
	_accumulate(_call_totals,_current.calls)
	# Derived shares belong to the retained record only, after integer totals
	# have accumulated and after the driver's complete-step timer has stopped.
	var denominator: int = maxi(1,outer_elapsed_us)
	record.root_stage_profiled_whole_share = float(stage_sum)/denominator
	record.observer_profiled_whole_share = float(_observer_us)/denominator
	record.residual_profiled_whole_share = float(record.residual_us)/denominator
	for entry: Dictionary in record.stages.values():
		entry.profiled_whole_share = float(entry.total_us)/denominator
	for entry: Dictionary in record.calls.values():
		entry.exclusive_profiled_whole_share = float(entry.exclusive_us)/denominator
	if samples.size()<max_step_records: samples.append(record.duplicate(true))
	return record

func root(name: String) -> void:
	if not _active: return
	var entered: int = Time.get_ticks_usec()
	_close_root_at(entered)
	_root_name = name
	_root_calls += 1
	if name=="step.setup": _current.nonblocking_invocations += 1
	var finished: int = Time.get_ticks_usec()
	_observer_us += finished-entered
	_root_started = finished
	_root_observer_started = _observer_us

func close_root() -> void:
	if not _active: return
	var entered: int = Time.get_ticks_usec()
	_close_root_at(entered)
	_root_name = ""
	_observer_us += Time.get_ticks_usec()-entered

func _close_root_at(now: int) -> void:
	if _root_name.is_empty(): return
	var elapsed: int = now-_root_started-(_observer_us-_root_observer_started)
	var entry: Dictionary = _current.stages.get(_root_name,{"calls":0,"total_us":0,"max_us":0})
	entry.calls += 1
	entry.total_us += elapsed
	entry.max_us = maxi(int(entry.max_us),elapsed)
	_current.stages[_root_name] = entry

func enter_call(operation: String) -> void:
	if not _active: return
	var entered: int = Time.get_ticks_usec()
	var frame: Dictionary = {"name":operation,"started":0,"observer_started":0,"children_us":0}
	_stack.append(frame)
	_call_edges += 1
	var finished: int = Time.get_ticks_usec()
	_observer_us += finished-entered
	frame.started = finished
	frame.observer_started = _observer_us

func exit_call(operation: String) -> void:
	if not _active: return
	var entered: int = Time.get_ticks_usec()
	if _stack.is_empty() or _stack.back().name!=operation:
		errors.append("nested timing stack mismatch: "+operation)
		return
	var frame: Dictionary = _stack.pop_back()
	var inclusive: int = entered-int(frame.started)-(_observer_us-int(frame.observer_started))
	var exclusive: int = inclusive-int(frame.children_us)
	var entry: Dictionary = _current.calls.get(operation,{"calls":0,"inclusive_us":0,"exclusive_us":0,"max_inclusive_us":0})
	entry.calls += 1
	entry.inclusive_us += inclusive
	entry.exclusive_us += exclusive
	entry.max_inclusive_us = maxi(int(entry.max_inclusive_us),inclusive)
	_current.calls[operation] = entry
	if not _stack.is_empty(): _stack.back().children_us += inclusive
	_observer_us += Time.get_ticks_usec()-entered

func report() -> Dictionary:
	var stage_rows: Array = []
	var sum_stages: int = 0
	for name: String in _stage_totals:
		var entry: Dictionary = _stage_totals[name].duplicate()
		entry.name = name
		entry.profiled_whole_share = float(entry.total_us)/maxi(1,_outer_total_us)
		sum_stages += int(entry.total_us)
		stage_rows.append(entry)
	stage_rows.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.total_us)>int(b.total_us))
	var call_rows: Array = []
	for name: String in _call_totals:
		var entry: Dictionary = _call_totals[name].duplicate()
		entry.name = name
		entry.exclusive_profiled_whole_share = float(entry.exclusive_us)/maxi(1,_outer_total_us)
		call_rows.append(entry)
	call_rows.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.exclusive_us)>int(b.exclusive_us))
	return {"steps":_steps_total,"complete_steps":_complete_total,"incomplete_steps":_incomplete_total,"profiled_whole_us":_outer_total_us,"disjoint_root_stage_us":sum_stages,"root_stage_profiled_whole_share":float(sum_stages)/maxi(1,_outer_total_us),"observer_handler_us":_observer_total_us,"observer_profiled_whole_share":float(_observer_total_us)/maxi(1,_outer_total_us),"residual_us":_residual_total_us,"residual_profiled_whole_share":float(_residual_total_us)/maxi(1,_outer_total_us),"partition_check_us":_outer_total_us-sum_stages-_observer_total_us-_residual_total_us,"root_stages":stage_rows,"nested_calls":call_rows,"step_records":samples.duplicate(true),"step_records_complete":samples.size()==_steps_total,"sources":sources.duplicate(true),"errors":errors.duplicate(),"semantics":{"root_stages":"Disjoint spans in the original step_nonblocking phase order; observed handler time removed.","nested_calls":"Inclusive and exclusive selected dynamic calls; exclusive subtracts timed descendants. Never add inclusive rows or add nested rows to root rows.","denominator":"Externally measured full ordinary Simulation.step elapsed, including its pending wait loop.","observer_handler_us":"Measured handler bodies only; wrapper dispatch and timer read overhead are not fully isolatable. Quantify total perturbation against a paired plain same-input window.","residual_us":"Full step minus root spans and observed handlers: outer step setup, pending sleeps, call/return gaps and timer precision.","business_validation":"Driver must compare frozen world, RNG and semantic event output against the plain same-input run."}}

func _accumulate(target: Dictionary, rows: Dictionary) -> void:
	for name: String in rows:
		if not target.has(name):
			target[name] = rows[name].duplicate()
			continue
		for field: String in rows[name]:
			if field.begins_with("max_"): target[name][field] = maxi(int(target[name][field]),int(rows[name][field]))
			else: target[name][field] += int(rows[name][field])

func _method_source(source: String, name: String) -> String:
	var lines: PackedStringArray = source.replace("\r\n","\n").split("\n")
	var start: int = -1
	var finish: int = lines.size()
	for i: int in lines.size():
		if lines[i].begins_with("func "+name+"("): start = i
		elif start>=0 and lines[i].begins_with("func "):
			finish = i
			break
	if start<0: return ""
	return "\n".join(lines.slice(start,finish))+"\n"

func _instrument_root(method: String) -> String:
	var out: PackedStringArray = []
	var staff_loops: int = 0
	var marker_count: int = 0
	for line: String in method.split("\n"):
		var text: String = line.strip_edges()
		var marker: String = ""
		if text.begins_with("var main_started:"): marker = "step.setup"
		elif text.begins_with("drain_commands()"): marker = "commands.drain"
		elif text.begins_with("if _production() and not services.arrivals.boundaries("): marker = "boundaries.arrivals"
		elif text.begins_with("services.") and (".boundaries(world)" in text or ".arrivals(world)" in text or ".dispatch(world)" in text or ".advance(world" in text or ".advance_wait(world)" in text or ".needs(world)" in text or ".sample(world)" in text or ".settle(world)" in text or ".begin_query(world)" in text or ".end_query()" in text):
			var expression: String = text.get_slice("(",0)
			var parts: PackedStringArray = expression.split(".")
			marker = parts[2]+"."+parts[1]
		elif text.begins_with("clinic.") and "(" in text:
			marker = "clinic."+text.get_slice("(",0).get_slice(".",1)
		elif text.begins_with("for staff_id:"):
			staff_loops += 1
			marker = "dispatch.staff_idle" if staff_loops==1 else "movement.capture_staff_locations"
		elif text.begins_with("space.advance("): marker = "movement.space"
		elif text.begins_with("var worked:"): marker = "integrate.worked_staff"
		elif text.begins_with("_integrate_staff("): marker = "integrate.legacy_staff"
		elif text.begins_with("var events:"): marker = "events.collect"
		elif text.begins_with("events.append_array(HospitalLedger.settle("): marker = "settlement.ledger"
		elif text.begins_with("world.finish_visits()"): marker = "settlement.finish_visits"
		elif text.begins_with("world.facts.sim_tick +="): marker = "snapshot.world_boundary"
		elif text.begins_with("space.finish_boundary("): marker = "snapshot.space_boundary"
		elif text.begins_with("events.append(SimEvent.new("): marker = "snapshot.tick_result"
		elif text.begins_with("var finished:"): marker = "snapshot.bookkeeping"
		# Preserve exact indentation, including nested production guards.
		var indent: String = line.left(line.length()-line.lstrip("\t ").length())
		if not marker.is_empty():
			out.append(indent+"_step_profile_observer.root(\""+marker+"\") # step-profile-marker")
			marker_count += 1
		if text=="return null" or text=="return result":
			out.append(indent+"_step_profile_observer.close_root() # step-profile-marker")
		out.append(line)
	var generated: String = "\n".join(out)
	var stripped: PackedStringArray = []
	for line: String in generated.split("\n"):
		if not line.ends_with("# step-profile-marker"): stripped.append(line)
	if "\n".join(stripped)!=method:
		errors.append("root instrumentation did not preserve original source")
		return ""
	if marker_count<50:
		errors.append("root instrumentation coverage unexpectedly incomplete")
		return ""
	sources.root_markers = marker_count
	sources.root_method_original_sha256 = method.sha256_text()
	sources.root_method_preserved = true
	return generated

func _attach_nested(simulation: HospitalSimulation) -> bool:
	var redirects: Dictionary = {}
	var old_space: HospitalSpace = simulation.space
	var geometry: HospitalSpace = _wrap(old_space,"space",[simulation.content])
	if geometry==null: return false
	var navigation: RefCounted = _wrap(old_space._navigation,"navigation",[])
	if navigation==null: return false
	geometry._navigation = navigation
	redirects[old_space] = geometry
	redirects[old_space._navigation] = navigation
	var point_navigation: RefCounted = _wrap(old_space.navigation,"point_navigation",[geometry])
	if point_navigation==null: return false
	geometry.navigation = point_navigation
	redirects[old_space.navigation] = point_navigation
	var movement: RefCounted = _wrap(old_space.movement,"movement",[geometry])
	if movement==null: return false
	geometry.movement = movement
	redirects[old_space.movement] = movement
	var extra: Array = []
	for property: Dictionary in old_space.get_property_list():
		if property.name!="public_areas": continue
		var original: RefCounted = old_space.get(property.name)
		var replacement: RefCounted = _wrap(original,"public_areas",[geometry])
		if replacement==null: return false
		redirects[original] = replacement
		geometry.set(property.name,replacement)
		extra.append(replacement)
	var old_clinic: HospitalClinic = simulation.clinic
	var clinic: HospitalClinic = _wrap(old_clinic,"clinic",[simulation.content,geometry])
	if clinic==null: return false
	redirects[old_clinic] = clinic
	var visitors: RefCounted = _wrap(old_clinic.visitors,"visitors",[simulation.content,geometry])
	if visitors==null: return false
	redirects[old_clinic.visitors] = visitors
	clinic.visitors = visitors
	simulation.space = geometry
	simulation.clinic = clinic
	for key: String in simulation.services:
		var original: RefCounted = simulation.services[key]
		var replacement: RefCounted = _wrap(original,key,[simulation.content,geometry])
		if replacement==null: return false
		redirects[original] = replacement
		simulation.services[key] = replacement
		if key=="wellbeing":
			for property: Dictionary in original.get_property_list():
				if property.name!="personal_beds": continue
				var beds: RefCounted = original.get(property.name)
				var wrapped: RefCounted = _wrap(beds,"personal_beds",[replacement])
				if wrapped==null: return false
				redirects[beds] = wrapped
				replacement.set(property.name,wrapped)
				extra.append(wrapped)
	var objects: Array = [simulation,geometry,navigation,point_navigation,movement,clinic,visitors]+simulation.services.values()+extra
	for object: Object in objects:
		for property: Dictionary in object.get_property_list():
			if int(property.type)!=TYPE_OBJECT or (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)==0: continue
			if property.name=="space" and _space_is_accessor(object): continue
			var value: Variant = object.get(property.name)
			if value is WeakRef and value.get_ref()!=null and redirects.has(value.get_ref()): object.set(property.name,weakref(redirects[value.get_ref()])); continue
			if value!=null and redirects.has(value): object.set(property.name,redirects[value])
	for kind: String in simulation._business_handlers:
		var original: RefCounted = simulation._business_handlers[kind]
		if redirects.has(original): simulation._business_handlers[kind] = redirects[original]
	# Replaced instances no longer own their old service cycles. Calling their
	# dispose methods would shut down the transferred preparation/cache state;
	# detach only graph references after every replacement has received them.
	for original: Object in redirects:
		if original==redirects[original]: continue
		for property: Dictionary in original.get_property_list():
			if (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)==0: continue
			if property.name=="space" and _space_is_accessor(original): continue
			var value: Variant = original.get(property.name)
			if int(property.type)==TYPE_OBJECT and value!=null and redirects.has(value): original.set(property.name,null)
			elif str(property.name)=="services" and value is Dictionary and is_same(value,simulation.services): original.set(property.name,{})
	sources.nested_object_paths = {"space":"simulation.space","navigation":"simulation.space._navigation","point_navigation":"simulation.space.navigation","movement":"simulation.space.movement","public_areas":"simulation.space.public_areas","clinic":"simulation.clinic","visitors":"simulation.clinic.visitors","services":"simulation.services[*]"}
	sources.unwrapped_runtime_leaves = ["FloorNavigation instances and engine/native path kernels: included in their timed caller, not individually wrapped by this mode.","RouteClearance instances and static methods: included in their timed caller, not individually wrapped by this mode.","Future temporary service instances created inside production methods: not covered by attach-time instance replacement; use the existing offline all-instance/ledger mode if these dominate."]
	return errors.is_empty()

func _wrap(original: RefCounted, group: String, arguments: Array) -> RefCounted:
	var base: GDScript = original.get_script()
	var source: String = "extends \""+base.resource_path+"\"\nvar _step_profile_observer: RefCounted\n"
	var wrapped: Array = []
	var available: Array = []
	for method: Dictionary in base.get_script_method_list():
		var name: String = str(method.name)
		available.append(name)
		if not name in COMMON_METHODS and not name in HOT_METHODS.get(group,[]): continue
		var body: String = _method_source(base.source_code,name)
		if body.is_empty(): continue
		var header_lines: PackedStringArray = []
		for line: String in body.split("\n"):
			header_lines.append(line)
			if line.rstrip(" \t").ends_with(":"): break
		var header: String = "\n".join(header_lines)
		var args: PackedStringArray = []
		for argument: Dictionary in method.args: args.append(str(argument.name))
		var operation: String = group+"."+name
		var returns: bool = int(method["return"].type)!=TYPE_NIL
		source += "\n"+header+"\n\t_step_profile_observer.enter_call(\""+operation+"\")\n"
		source += "\t"+("var _step_profile_result: Variant = " if returns else "")+"super."+name+"("+",".join(args)+")\n"
		source += "\t_step_profile_observer.exit_call(\""+operation+"\")\n"
		if returns: source += "\treturn _step_profile_result\n"
		wrapped.append(name)
	var missing: Array = []
	for name: String in HOT_METHODS.get(group,[]):
		if not name in wrapped: missing.append(name)
	var unwrapped: Array = []
	for name: String in available:
		if not name in wrapped: unwrapped.append(name)
	if wrapped.is_empty():
		sources[group] = {"production_path":base.resource_path,"production_sha256":base.source_code.sha256_text(),"methods":wrapped,"unwrapped_methods":unwrapped,"configured_but_unwrapped":missing}
		return original
	var script: GDScript = _compile(group,base,source)
	if script==null: return null
	var result: RefCounted = Callable(script,"new").callv(arguments)
	_copy_script_properties(original,result)
	result.set("_step_profile_observer",self)
	sources[group].methods = wrapped
	sources[group].unwrapped_methods = unwrapped
	sources[group].configured_but_unwrapped = missing
	return result

func _compile(group: String, base: GDScript, source: String) -> GDScript:
	var script: GDScript = GDScript.new()
	script.source_code = source
	var compile_result: Error = script.reload()
	sources[group] = {"production_path":base.resource_path,"production_sha256":base.source_code.sha256_text(),"generated_sha256":source.sha256_text(),"compile_error":compile_result}
	if not source_directory.is_empty():
		DirAccess.make_dir_recursive_absolute(source_directory)
		var path: String = source_directory.path_join(group+".gd")
		var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
		if file!=null: file.store_string(source)
		else: errors.append("cannot write diagnostic source: "+path)
	if compile_result!=OK:
		errors.append("diagnostic script compile failed: "+group)
		return null
	_generated_scripts.append(script)
	return script

func _copy_script_properties(original: Object, replacement: Object) -> void:
	for property: Dictionary in original.get_property_list():
		if property.name=="space" and _space_is_accessor(original): continue
		if (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)!=0:
			replacement.set(property.name,original.get(property.name))

func _space_is_accessor(object: Object) -> bool:
	var script: Script = object.get_script()
	while script!=null:
		if script.resource_path in ["res://game/life/public_areas.gd","res://game/building/hospital_navigation.gd","res://game/building/hospital_movement.gd"]: return true
		script = script.get_base_script()
	return false
