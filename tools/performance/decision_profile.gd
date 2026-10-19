extends "res://tools/performance/all_instance_profile.gd"

# Complete nested accounting for selected real steps in an offline copy only.
# Rows retain caller identities and business outcomes, not full world snapshots.
var _ledger: Array = []
var _ledger_stack: Array = []
var _ledger_steps: Array = []

func begin_selected_step(index: int) -> void:
	_ledger = []
	_ledger_stack = []
	super.begin_selected_step(index)

func enter_instance(operation: String, instance_id: int, arguments: Dictionary) -> void:
	var started: int = Time.get_ticks_usec()
	var row: Dictionary = {"id":_ledger.size(),"parent":_ledger_stack.back().id if not _ledger_stack.is_empty() else -1,
		"operation":operation,"root":_root_name,"instance":instance_id,"arguments":{},"owner":""}
	if not _ledger_stack.is_empty(): row.owner = _ledger_stack.back().owner
	for name: String in arguments:
		var argument: Variant = arguments[name]
		if argument is WorldState:
			row.arguments[name] = {"world":argument.get_instance_id(),"tick":argument.sim_tick,"revision":argument.revision,"geometry_revision":argument.geometry_revision}
			_world_identities[argument.get_instance_id()] = true
		elif name in ["visit","actor","ticket"] and argument is Dictionary:
			row.arguments[name] = _business_record(argument)
			if name=="visit": row.owner = str(argument.get("id",""))
		elif name in ["actor_id","visit_id"]:
			row.arguments[name] = argument
			if str(row.owner).is_empty(): row.owner = str(argument)
		else: row.arguments[name] = _compact(argument)
	_ledger.append(row)
	_ledger_stack.append(row)
	# Retain only the three input records needed to observe dispatch's actual
	# outcome. They are read after the original method; never modified here.
	if operation=="clinic._dispatch_service": row._dispatch = {"visit":arguments.visit,"ticket":arguments.ticket}
	_observer_us += Time.get_ticks_usec()-started
	# The complete ledger replaces bounded parameter grouping; do not serialize
	# full floor sources again through the older aggregate observer.
	super.enter_instance(operation,instance_id,{})

func exit_instance(operation: String, result: Variant) -> void:
	var started: int = Time.get_ticks_usec()
	if _ledger_stack.is_empty() or _ledger_stack.back().operation!=operation:
		errors.append("decision ledger mismatch: "+operation)
		return
	var row: Dictionary = _ledger_stack.pop_back()
	row.result = _compact(result)
	if row.has("_dispatch"):
		row.dispatch_outcome = {"visit":_business_record(row._dispatch.visit),"ticket":_business_record(row._dispatch.ticket)}
		row.erase("_dispatch")
	var inclusive_before: int = int(_current.calls.get(operation,{}).get("inclusive_us",0))
	var exclusive_before: int = int(_current.calls.get(operation,{}).get("exclusive_us",0))
	_observer_us += Time.get_ticks_usec()-started
	super.exit_instance(operation,result)
	started = Time.get_ticks_usec()
	row.inclusive_us = int(_current.calls[operation].inclusive_us)-inclusive_before
	row.exclusive_us = int(_current.calls[operation].exclusive_us)-exclusive_before
	_observer_us += Time.get_ticks_usec()-started

func end_selected_step(result: TickResult, elapsed_us: int) -> Dictionary:
	var record: Dictionary = super.end_selected_step(result,elapsed_us)
	if not _ledger_stack.is_empty(): errors.append("unbalanced decision ledger")
	var exclusive_sum: int = 0
	var root_children: Dictionary = {}
	for row: Dictionary in _ledger:
		exclusive_sum += int(row.exclusive_us)
		if int(row.parent)<0: root_children[row.root] = int(root_children.get(row.root,0))+int(row.inclusive_us)
	var partition: Array = []
	for stage: String in record.stages:
		var total: int = int(record.stages[stage].total_us)
		var nested: int = int(root_children.get(stage,0))
		partition.append({"stage":stage,"total_us":total,"timed_top_level_us":nested,"untimed_body_us":total-nested})
	_ledger_steps.append({"index":_index,"tick":record.get("tick",-1),"calls":_ledger,"call_count":_ledger.size(),
		"exclusive_sum_us":exclusive_sum,"root_top_level_sum_us":_sum_values(root_children),
		"call_partition_difference_us":_sum_values(root_children)-exclusive_sum,"root_partition":partition,
		"outer_elapsed_us":elapsed_us,"root_stage_us":record.root_stage_us,"observer_handler_us":record.observer_handler_us,"residual_us":record.residual_us})
	return record

func _sum_values(values: Dictionary) -> int:
	var total: int = 0
	for value: int in values.values(): total += value
	return total

func _business_record(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for name: String in ["id","actor_id","kind","phase","department_id","definition_id","location","posture","body","body_size","plan_decision","requested_plan_id","binding_id","waiting_reason","service_assigned","called_tick","session_id","facility_id","staff_id","staff_ids"]:
		if value.has(name): result[name] = _compact(value[name])
	return result

func _compact(value: Variant, depth: int = 0) -> Variant:
	if value is WorldState: return {"world":value.get_instance_id()}
	if value is Object: return {"instance":value.get_instance_id(),"class":value.get_class()}
	if value is Callable: return {"callable":value.is_valid()}
	if value is Vector2i or value is Vector2: return [value.x,value.y]
	if value is Rect2i or value is Rect2: return {"position":_compact(value.position),"size":_compact(value.size)}
	if value is Array:
		if depth>=3: return {"count":value.size()}
		var items: Array = []
		# Full route arrays are represented by length and endpoints. Candidate
		# arrays retain every pair so final selection can be joined exactly.
		if value.size()>64 and not (value.front() is Dictionary and value.front().has("facility_id")):
			return {"count":value.size(),"first":_compact(value.front(),depth+1),"last":_compact(value.back(),depth+1)}
		for item: Variant in value: items.append(_compact(item,depth+1))
		return items
	if value is Dictionary:
		if depth>=3: return {"keys":value.keys()}
		var result: Dictionary = {}
		for name: Variant in value:
			if str(name) in ["facts","geometry","room_bounds","actors","facilities","cells","path","source","query","base_layout","navigation"]:
				var item: Variant = value[name]
				result[name] = {"count":item.size()} if item is Array or item is Dictionary else _compact(item,depth+1)
			else: result[str(name)] = _compact(value[name],depth+1)
		return result
	return value

func report() -> Dictionary:
	var result: Dictionary = super.report()
	result.decision_ledger = _ledger_steps
	result.semantics.decision_ledger = "All wrapped invocations on selected complete real steps, with parent links, root stages, compact arguments and outcomes. No parameter-group truncation. Keys are attribution, not proof of cache equivalence. Exclusive call costs plus untimed root bodies, observer handlers and residual account for the full step."
	return result
