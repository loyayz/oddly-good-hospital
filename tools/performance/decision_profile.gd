extends "res://tools/performance/step_profile.gd"

# Complete nested accounting for selected real steps in an offline copy only.
# Rows retain caller identities and business outcomes, not full world snapshots.
const METADATA_KEY: StringName = &"oddly_good_tail_profile_observer_v1"
const BUSINESS_ARGUMENTS: Array[String] = [
	"clinic._dispatch_service","clinic.service_candidates","clinic._service_pair_reachable","clinic.plan_quote","clinic._plan_quote_in_query",
	"visitors._public_waiting","waiting._manual_seat_quote","waiting._dispatch_public_seat",
	"space._facility_quote","space.facility_preflight_quote","space._facility_exit_quote","space._exit_witness","space.can_reach",
	"space._floor_route","space.reserve_facility","floor_graph.find_path",
	"point_navigation._route_result","point_navigation._point_route","point_navigation._floor_route","movement.request_move","movement._yield",
	"transit.route","transit._quote_known_fit","transit._prefix","transit.egress_clear","environment._work_position",
	"navigation._distance_field","navigation._forward_field","clearance.capture_source"
]
var _ledger: Array = []
var _ledger_stack: Array = []
var _ledger_steps: Array = []
var _index: int = -1

func begin_selected_step(index: int) -> void:
	_ledger = []
	_ledger_stack = []
	_index = index
	begin_step()
	if Engine.has_meta(METADATA_KEY): errors.append("decision observer metadata was already installed")
	Engine.set_meta(METADATA_KEY,self)

func enter_instance(operation: String, instance_id: int, arguments: Dictionary) -> void:
	var started: int = Time.get_ticks_usec()
	var row: Dictionary = {"id":_ledger.size(),"parent":_ledger_stack.back().id if not _ledger_stack.is_empty() else -1,
		"operation":operation,"root":_root_name,"instance":instance_id,"arguments":{},"owner":""}
	if not _ledger_stack.is_empty(): row.owner = _ledger_stack.back().owner
	var retained_arguments: Dictionary = arguments if operation in BUSINESS_ARGUMENTS else {}
	for name: String in retained_arguments:
		var argument: Variant = arguments[name]
		if argument is WorldState:
			row.arguments[name] = {"world":argument.get_instance_id(),"tick":argument.sim_tick,"revision":argument.revision,"geometry_revision":argument.geometry_revision}
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
	if operation=="clinic._dispatch_service": row._dispatch = {"world":arguments.world,"visit":arguments.visit,"ticket":arguments.ticket}
	_observer_us += Time.get_ticks_usec()-started
	# Keep one timing stack. The older observer's instance/result grouping and
	# JSON serialization duplicate this complete tree and are intentionally absent.
	enter_call(operation)

func exit_instance(operation: String, result: Variant) -> void:
	var started: int = Time.get_ticks_usec()
	if _ledger_stack.is_empty() or _ledger_stack.back().operation!=operation:
		errors.append("decision ledger mismatch: "+operation)
		return
	var row: Dictionary = _ledger_stack.pop_back()
	row.result = _compact(result) if operation in BUSINESS_ARGUMENTS else _status(result)
	if row.has("_dispatch"):
		row.dispatch_outcome = {"visit":_business_record(row._dispatch.visit),"ticket":_business_record(row._dispatch.ticket)}
		var world: WorldState = row._dispatch.world
		row.dispatch_outcome.ticket_exists = world.facts.tickets.has(str(row._dispatch.ticket.id))
		row.dispatch_outcome.sessions = []
		for session: Dictionary in world.facts.sessions.values():
			if session.visit_id==row._dispatch.visit.id:
				row.dispatch_outcome.sessions.append(_business_record(session))
		row.erase("_dispatch")
	var inclusive_before: int = int(_current.calls.get(operation,{}).get("inclusive_us",0))
	var exclusive_before: int = int(_current.calls.get(operation,{}).get("exclusive_us",0))
	_observer_us += Time.get_ticks_usec()-started
	exit_call(operation)
	started = Time.get_ticks_usec()
	row.inclusive_us = int(_current.calls[operation].inclusive_us)-inclusive_before
	row.exclusive_us = int(_current.calls[operation].exclusive_us)-exclusive_before
	_observer_us += Time.get_ticks_usec()-started

func end_selected_step(result: TickResult, elapsed_us: int) -> Dictionary:
	Engine.remove_meta(METADATA_KEY)
	var record: Dictionary = end_step(result,elapsed_us)
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

func _status(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for name: String in ["ok","ready","status","reason"]:
			if value.has(name): result[name] = value[name]
		return result
	if value is Array: return {"count":value.size()}
	if value is Object: return {"instance":value.get_instance_id()}
	return value

func _sum_values(values: Dictionary) -> int:
	var total: int = 0
	for value: int in values.values(): total += value
	return total

func _business_record(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for name: String in ["id","actor_id","visit_id","ticket_id","kind","phase","department_id","definition_id","location","posture","body","body_size","plan_decision","requested_plan_id","binding_id","waiting_reason","service_assigned","called_tick","session_id","facility_id","staff_id","staff_ids"]:
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
			if str(name) in ["facts","geometry","room_bounds","actors","facilities","cells","path","source","query","base_layout","navigation","pairs","patient_rejections","transport_actors"]:
				var item: Variant = value[name]
				result[name] = {"count":item.size()} if item is Array or item is Dictionary else _compact(item,depth+1)
			else: result[str(name)] = _compact(value[name],depth+1)
		return result
	return value

func report() -> Dictionary:
	var result: Dictionary = super.report()
	result.decision_ledger = _ledger_steps
	result.semantics.decision_ledger = "All wrapped invocations on selected complete real steps, with parent links, root stages and outcomes. Business arguments are retained only for BUSINESS_ARGUMENTS; other calls keep status and timing. No call-group truncation. Keys are attribution, not proof of cache equivalence. Exclusive call costs plus untimed root bodies, observer handlers and residual account for the full step."
	return result
