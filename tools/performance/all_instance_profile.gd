extends "res://tools/performance/step_profile.gd"

# Observer used only with instrument_all_instances.py's frozen project. It is
# absent from Engine metadata outside explicitly selected complete steps.
const METADATA_KEY: StringName = &"oddly_good_tail_profile_observer_v1"
const MAX_PARAMETER_GROUPS: int = 256
const MAX_IDENTITY_EXAMPLES: int = 32
const MAX_REASON_GROUPS: int = 1024

var _instance_rows: Dictionary = {}
var _parameter_rows: Dictionary = {}
var _reason_rows: Dictionary = {}
var _contexts: Array = []
var _diagnostics: Array = []
var _index: int = -1
var _instance_by_group: Dictionary = {}
var _world_identities: Dictionary = {}

func begin_selected_step(index: int) -> void:
	_index = index
	_instance_rows = {}
	_parameter_rows = {}
	_reason_rows = {}
	_contexts = []
	_instance_by_group = {}
	_world_identities = {}
	begin_step()
	if Engine.has_meta(METADATA_KEY): errors.append("all-instance observer metadata was already installed")
	Engine.set_meta(METADATA_KEY,self)

func end_selected_step(result: TickResult, elapsed_us: int) -> Dictionary:
	Engine.remove_meta(METADATA_KEY)
	var record: Dictionary = end_step(result,elapsed_us)
	if not _contexts.is_empty(): errors.append("unbalanced all-instance context stack")
	var instances: Array = []
	for operation: String in _instance_rows:
		var row: Dictionary = _instance_rows[operation].duplicate(true)
		row.operation = operation
		row.instance_count = row.instance_ids.size()
		row.instance_ids = row.instance_ids.keys()
		instances.append(row)
	instances.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.calls)>int(b.calls))
	var groups: Dictionary = {}
	for group: String in _instance_by_group:
		groups[group] = {"instance_count":_instance_by_group[group].size(),"instance_ids":_instance_by_group[group].keys()}
	var parameters: Array = []
	for operation: String in _parameter_rows:
		var row: Dictionary = _parameter_rows[operation].duplicate(true)
		var retained: Array = []
		for key: String in row.groups:
			var value: Dictionary = row.groups[key]
			value.parameter_key = key
			value.world_instance_ids = value.world_instance_ids.keys()
			value.instance_ids = value.instance_ids.keys()
			retained.append(value)
		retained.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.inclusive_us)>int(b.inclusive_us))
		row.operation = operation
		row.groups = retained
		parameters.append(row)
	var reasons: Array = []
	for key: String in _reason_rows: reasons.append(_reason_rows[key].duplicate(true))
	reasons.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.inclusive_us)>int(b.inclusive_us))
	var diagnostic: Dictionary = {"index":_index,"tick":result.sim_tick if result!=null else -1,
		"instances_by_group":groups,"instance_calls":instances,"world_instance_ids":_world_identities.keys(),
		"parameter_groups":parameters,"result_groups":reasons,
		"parameter_group_limit_per_operation":MAX_PARAMETER_GROUPS,"reason_group_limit":MAX_REASON_GROUPS,
		"identity_example_limit_per_parameter_group":MAX_IDENTITY_EXAMPLES}
	_diagnostics.append(diagnostic)
	# This diagnostic is outside the step timer and outside inherited totals.
	# StepProfile's root/call durations remain the authoritative timing table.
	record.all_instances = diagnostic
	return record

func enter_instance(operation: String, instance_id: int, arguments: Dictionary) -> void:
	if not _active: return
	var entered: int = Time.get_ticks_usec()
	var instance: Dictionary = _instance_rows.get(operation,{"calls":0,"instance_ids":{}})
	instance.calls += 1
	if instance_id!=0:
		instance.instance_ids[instance_id] = true
		var group: String = operation.get_slice(".",0)
		if not _instance_by_group.has(group): _instance_by_group[group] = {}
		_instance_by_group[group][instance_id] = true
	_instance_rows[operation] = instance
	var context: Dictionary = {"operation":operation,"instance_id":instance_id,"parameter_key":"","world_instance_id":0,
		"root_stage":_root_name,"caller":str(_stack.back().name) if not _stack.is_empty() else "<root>"}
	if not arguments.is_empty():
		var parameters: Dictionary = {}
		for name: String in arguments:
			var argument: Variant = arguments[name]
			if argument is WorldState:
				context.world_instance_id = argument.get_instance_id()
				context.sim_tick = argument.sim_tick
				context.revision = argument.revision
				_world_identities[context.world_instance_id] = true
				parameters[name] = "<world:identity-recorded-separately>"
			elif argument is Object:
				# Services/caches passed to static helpers are recorded as identities,
				# but excluded from the parameter key to expose repeated queries
				# across separate projected spaces. This grants no equivalence.
				parameters[name] = "<object:"+argument.get_class()+">"
			elif name in ["actor","visit","connection"] and argument is Dictionary:
				parameters[name] = _identity_argument(argument)
			elif name in ["quote","base_layout","navigation"] and argument is Dictionary:
				parameters[name] = {"supplied":not argument.is_empty(),"keys":argument.keys()}
			else:
				parameters[name] = argument
		if operation=="clearance.capture_source" and context.caller=="navigation.floor_source" and not _contexts.is_empty():
			var navigation: Object = instance_from_id(int(_contexts.back().instance_id))
			var source_world: WorldState = arguments.world
			var source_key: String = str(source_world.get_instance_id())+":"+str(arguments.floor_id)
			var cached: Dictionary = navigation.get("_sources").get(source_key,{})
			parameters.parent_source_state = "absent" if cached.is_empty() else ("stale" if cached.revision!=source_world.geometry_revision else "current")
		context.parameter_key = JSON.stringify({"root_stage":context.root_stage,"caller":context.caller,"arguments":parameters},"",true,true)
	_contexts.append(context)
	_observer_us += Time.get_ticks_usec()-entered
	enter_call(operation)

func exit_instance(operation: String, result: Variant) -> void:
	if not _active: return
	var entered: int = Time.get_ticks_usec()
	if _contexts.is_empty() or _contexts.back().operation!=operation or _stack.is_empty():
		errors.append("all-instance context mismatch: "+operation)
		return
	var context: Dictionary = _contexts.pop_back()
	var frame: Dictionary = _stack.back()
	var inclusive: int = entered-int(frame.started)-(_observer_us-int(frame.observer_started))
	var status: Dictionary = _result_status(result)
	if not str(context.parameter_key).is_empty():
		var row: Dictionary = _parameter_rows.get(operation,{"calls":0,"groups":{},"overflow_calls":0,"overflow_inclusive_us":0})
		row.calls += 1
		if row.groups.has(context.parameter_key) or row.groups.size()<MAX_PARAMETER_GROUPS:
			var group: Dictionary = row.groups.get(context.parameter_key,{"calls":0,"inclusive_us":0,"max_inclusive_us":0,"world_instance_ids":{},"instance_ids":{},"identity_examples_truncated":false,"results":{}})
			group.calls += 1
			group.inclusive_us += inclusive
			group.max_inclusive_us = maxi(int(group.max_inclusive_us),inclusive)
			for spec: Array in [["world_instance_ids",int(context.world_instance_id)],["instance_ids",int(context.instance_id)]]:
				var identities: Dictionary = group[spec[0]]
				if int(spec[1])!=0:
					if identities.has(spec[1]) or identities.size()<MAX_IDENTITY_EXAMPLES: identities[spec[1]] = true
					else: group.identity_examples_truncated = true
			var result_key: String = JSON.stringify(status,"",true,true)
			group.results[result_key] = int(group.results.get(result_key,0))+1
			row.groups[context.parameter_key] = group
		else:
			row.overflow_calls += 1
			row.overflow_inclusive_us += inclusive
		_parameter_rows[operation] = row
	if not status.is_empty():
		var reason_key: String = JSON.stringify([context.root_stage,context.caller,operation,status],"",true,true)
		if _reason_rows.has(reason_key) or _reason_rows.size()<MAX_REASON_GROUPS:
			var reason: Dictionary = _reason_rows.get(reason_key,{"root_stage":context.root_stage,"caller":context.caller,"operation":operation,"result":status,"calls":0,"inclusive_us":0})
			reason.calls += 1
			reason.inclusive_us += inclusive
			_reason_rows[reason_key] = reason
		else:
			var overflow: Dictionary = _reason_rows.get("<overflow>",{"operation":"<overflow>","calls":0,"inclusive_us":0})
			overflow.calls += 1
			overflow.inclusive_us += inclusive
			_reason_rows["<overflow>"] = overflow
	_observer_us += Time.get_ticks_usec()-entered
	exit_call(operation)

func _identity_argument(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for name: String in ["id","actor_id","definition_id","case_id","phase","kind","location","posture","facing","body","body_size","plan_decision"]:
		if value.has(name): result[name] = value[name]
	return result

func _result_status(value: Variant) -> Dictionary:
	if value is Dictionary:
		var result: Dictionary = {}
		for name: String in ["ok","ready","status","reason"]:
			if value.has(name): result[name] = value[name]
		return result
	if value is bool: return {"boolean":value}
	return {}

func report() -> Dictionary:
	var result: Dictionary = super.report()
	result.all_instance_steps = _diagnostics.duplicate(true)
	result.semantics.all_instances = "Offline wrappers cover every invocation of the listed script methods, including newly created projected spaces, navigation caches and static transit/clearance helpers. Static helpers have no instance id. Instance counts are observed called instances, not all allocated objects."
	result.semantics.selected_indices = "Only selected ordinary complete steps install the observer. All earlier prefix steps execute; wrappers take their inactive branch and collect no records. Dispatch/metadata lookup overhead remains, so compare this diagnostic run only with its paired untransformed plain control."
	result.semantics.parameter_groups = "Bounded identity-agnostic compact parameter groups include root and immediate timed caller. World/space identities are counted separately. Equal keys do not establish equal world facts, permission, reservation, cache lifetime or legal reuse. Inclusive group/result rows overlap; never add them to call or root timing tables."
	result.semantics.inclusive_group_timers = "Auxiliary group/result inclusive timers stop just before bookkeeping and differ by a few timer/dispatch instructions from the authoritative inherited nested-call table."
	return result
