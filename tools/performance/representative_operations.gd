extends RefCounted

# Adds legal operations inputs at the supplied simulation boundary. Selection,
# movement, arrival and work are exclusively performed by HospitalSimulation.
const Development = preload("res://game/staff/clinical_development.gd")
const SCHEMA: int = 2

func apply(simulation: HospitalSimulation, config: Dictionary = {}) -> Dictionary:
	var world: WorldState = simulation.world
	var actor_before: Dictionary = world.facts.actors.duplicate(true)
	var clinical_before: Dictionary = _clinical_facts(world)
	var staff_before: Dictionary = world.facts.staff.duplicate(true)
	var facilities_before: Dictionary = world.facts.facilities.duplicate(true)
	var cash_before: int = HospitalLedger.balance(world)
	var metadata: Dictionary = {"schema":SCHEMA,"tick":world.sim_tick,"cleaning_mode":str(config.get("cleaning_mode","local16")),
		"dirt_ids":[],"dirt_sources":[],"order_ids":[],"commands":[],"need_inputs":[],"need_skipped":[],"errors":[],"limitations":[],
		"rules":["docs/design/08-hospital-life.md sections 4,20","docs/design/09-consultation-wellbeing.md section 4"],
		"related_cases":["OPS-11","OPS-12","OPS-13","OPS-16","OPS-42","STAFF-22","STAFF-23","STAFF-24"]}
	metadata.preexisting_dirt_ids = world.facts.environment.dirt.keys()
	metadata.candidate_policy = "Original global/region rules and all preexisting plus seeded patches remain eligible; no candidate or actor is removed."
	var cleaners: Array[String] = []
	for staff_id: String in world.ids("staff"):
		if world.facts.staff[staff_id].role=="cleaner": cleaners.append(staff_id)
	metadata.cleaner_ids = cleaners
	if cleaners.size()!=4:
		metadata.errors.append("Expected the fixed input's four original cleaners; no staff were added or converted.")
	if not metadata.cleaning_mode in ["local16","concentrated4","concentrated16"]:
		metadata.errors.append("Unknown cleaning_mode; supported: local16, concentrated4, concentrated16.")
		return metadata
	if metadata.cleaning_mode=="local16":
		for staff_id: String in cleaners:
			var location: Dictionary = world.facts.actors[staff_id].location
			if location.kind!="floor":
				metadata.errors.append("Cleaner is in transit; local input was not placed: "+staff_id)
				continue
			_spawn_group(simulation,metadata,staff_id,int(location.floor_id),location.cell,4)
	else:
		var target_floor: int = int(config.get("target_floor",1))
		var origin: Array = config.get("concentrated_origin",[40,80])
		_spawn_group(simulation,metadata,"floor_"+str(target_floor),target_floor,origin,4 if metadata.cleaning_mode=="concentrated4" else 16)
	if bool(config.get("pending_renovation",true)):
		var decorators: int = 0
		var tools: int = 0
		for staff: Dictionary in world.facts.staff.values():
			if staff.role=="decorator" and not staff.get("departed",false): decorators += 1
		for facility: Dictionary in world.facts.facilities.values():
			if facility.definition_id==simulation.content.balance.renovation.tool_equipment_id and not facility.get("failed",false) and facility.get("location","floor")!="inventory": tools += 1
		metadata.renovation_availability = {"decorators":decorators,"working_tools":tools}
		for floor_id: int in [1,2,3,4]:
			var units: Array = []
			for index: int in 4: units.append({"cell":[42+index*2,87]})
			var payload: Dictionary = {"material_id":"MAT01","floor_id":floor_id,"units":units,"allow_waiting":true}
			var command_id: String = "representative-operations-%s-renovation-%d"%[str(world.sim_tick),floor_id]
			var result: CommandResult = simulation.apply(GameCommand.from_record({"id":command_id,"hospital_id":world.hospital_id,
				"expected_revision":world.revision,"kind":"renovation_order","typed_payload":payload,"loading_session_id":"representative-operations"}))
			metadata.commands.append({"kind":"renovation_order","payload":payload,"result":result.to_record()})
			if result.accepted:
				metadata.order_ids.append_array(result.changed_ids)
			else:
				metadata.errors.append("Actual renovation command rejected: "+result.reason)
		if decorators==0 or tools==0:
			metadata.limitations.append("Paid renovation orders lack a decorator and/or working tool; no construction progress is claimed.")
	var need_kinds: Array = config.get("need_kinds",["rest","sleep"])
	_add_idle_needs(simulation,metadata,need_kinds)
	var allowed_staff_changes: Dictionary = {}
	for change: Dictionary in metadata.need_inputs: allowed_staff_changes[change.staff_id] = change.field
	var unchanged_staff: bool = true
	for staff_id: String in staff_before:
		var original: Dictionary = staff_before[staff_id].duplicate(true)
		if allowed_staff_changes.has(staff_id): original[allowed_staff_changes[staff_id]] = world.facts.staff[staff_id][allowed_staff_changes[staff_id]]
		if original!=world.facts.staff[staff_id]: unchanged_staff = false
	metadata.preservation = {"actors":world.present_actor_count(),"staff":world.facts.staff.size(),"patients":world.facts.visits.size(),
		"family_or_other_actors":world.facts.actors.size()-world.facts.staff.size()-world.facts.visits.size(),
		"actor_facts_unchanged":actor_before==world.facts.actors,"clinical_facts_unchanged":clinical_before==_clinical_facts(world),
		"facilities_unchanged":facilities_before==world.facts.facilities,"staff_unchanged_except_recorded_need_inputs":unchanged_staff,
		"regions_unchanged":true,"cash_before":cash_before,"cash_after":HospitalLedger.balance(world)}
	if not metadata.preservation.actor_facts_unchanged or not metadata.preservation.clinical_facts_unchanged or not metadata.preservation.facilities_unchanged or not unchanged_staff:
		metadata.errors.append("Operations setup unexpectedly changed an original actor, clinical fact, facility or unrelated staff fact.")
	metadata.seeded_dirt_count = metadata.dirt_ids.size()
	metadata.global_dirt_count_after_setup = world.facts.environment.dirt.size()
	metadata.initial = snapshot(world,metadata)
	return metadata

func _spawn_group(simulation: HospitalSimulation, metadata: Dictionary, group: String, floor_id: int, origin: Array, count: int) -> void:
	for index: int in count:
		# Every independent event contributes one patch, below the three-patch
		# event limit; production chooses the actual nearest legal ground cell.
		var cell: Array = [int(origin[0])+(index%4)*2,int(origin[1])+(index/4)*2]
		var source: String = "representative-operations-%d-%s-%02d"%[simulation.world.sim_tick,group,index]
		var dirt_id: String = simulation.services.environment.spawn_dirt(simulation.world,"CL01",source,source+":scatter",floor_id,cell)
		metadata.dirt_sources.append({"source":source,"source_kind":"CL01","floor_id":floor_id,"requested_cell":cell,"dirt_id":dirt_id})
		if dirt_id.is_empty():
			metadata.errors.append("Production dirt generation found no legal ground cell: "+source)
		else:
			metadata.dirt_ids.append(dirt_id)

func _add_idle_needs(simulation: HospitalSimulation, metadata: Dictionary, need_kinds: Array) -> void:
	var world: WorldState = simulation.world
	var next_kind: int = 0
	var ordered: Array = world.ids("staff")
	ordered.sort_custom(func(a: String,b: String) -> bool:
		var first: int = _need_priority(world.facts.staff[a])
		var second: int = _need_priority(world.facts.staff[b])
		return first<second if first!=second else a<b)
	metadata.need_eligibility = {"preference":["idle nonclinical staff","idle scheduled surgery doctor","other idle doctor","idle nurse"],
		"exclusions":["cleaner","departed or not on a floor","safe_busy","other commitment","session/preparation/bed ownership",
			"real movement","existing life task","leave obligation","supply strike"],"fields_supplied_only":["energy for rest","awake_ticks for sleep"]}
	for staff_id: String in ordered:
		if next_kind>=need_kinds.size(): break
		var staff: Dictionary = world.facts.staff[staff_id]
		if staff.role=="cleaner": continue
		var reason: String = ""
		var clinical_owners: Array = _clinical_owners(world,staff_id)
		if staff.get("departed",false) or world.facts.actors[staff_id].location.kind!="floor": reason = "not currently present on a floor"
		elif Development.safe_busy(world,staff_id) or simulation.services.wellbeing._other_commitment(world,staff_id): reason = "existing clinical or other commitment"
		elif not clinical_owners.is_empty(): reason = "existing session/preparation/bed ownership"
		elif world.facts.moves.has(staff_id): reason = "existing real movement"
		elif staff.get("life_task",{}).get("phase","idle")!="idle": reason = "existing life task"
		elif not staff.get("leave_plan",{}).is_empty(): reason = "existing leave obligation"
		elif staff.get("supply_strike",false): reason = "existing supply obligation"
		if not reason.is_empty():
			metadata.need_skipped.append({"staff_id":staff_id,"role":staff.role,"reason":reason,"clinical_owners":clinical_owners})
			continue
		var kind: String = str(need_kinds[next_kind])
		if not kind in ["rest","sleep"]:
			metadata.errors.append("Unsupported staff need kind: "+kind)
			next_kind += 1
			continue
		var field: String = "energy" if kind=="rest" else "awake_ticks"
		var before: Variant = staff.get(field,0)
		var threshold: Variant
		if kind=="rest": threshold = float(simulation.content.balance.wellbeing.recreation_max_energy_priority)
		else: threshold = ceili(float(simulation.content.balance.staff_sleep.awake_limit_seconds)/WorldState.TICK_SECONDS)
		staff[field] = threshold
		metadata.need_inputs.append({"staff_id":staff_id,"role":staff.role,"kind":kind,"field":field,"before":before,"after":threshold,
			"sleep_total_ticks":ceili(float(simulation.content.balance.staff_sleep.sleep_seconds)/WorldState.TICK_SECONDS),
			"qualification":{"priority":_need_priority(staff),"scheduled_kind":staff.get("scheduled_kind",""),"safe_busy":false,"other_commitment":false,
				"clinical_owners":clinical_owners,"has_move":false,"life_phase":"idle","has_leave":false,"has_supply_strike":false},
			"boundary":"Idle existing staff without clinical or other ownership at the requirement's rest/sleep threshold; no task, reservation, move or progress supplied."})
		next_kind += 1
	if not metadata.need_inputs.is_empty(): world.touch()
	if next_kind<need_kinds.size(): metadata.limitations.append("Fewer than requested existing idle staff without clinical or other ownership were eligible; ongoing commitments were preserved.")

func _need_priority(staff: Dictionary) -> int:
	if not staff.role in ["doctor","nurse","cleaner"]: return 0
	if staff.role=="doctor" and staff.get("scheduled_kind","")=="surgery": return 1
	return 2 if staff.role=="doctor" else 3

func _clinical_owners(world: WorldState, staff_id: String) -> Array:
	var owners: Array = []
	for collection: String in ["sessions","preparations","ward_stays"]:
		for record: Dictionary in world.facts.get(collection,{}).values():
			if collection=="ward_stays" and record.get("phase","")=="complete": continue
			var owns: bool = staff_id in record.get("staff_ids",[])
			for field: String in ["nurse_id","round_doctor_id","escort_id"]:
				owns = owns or record.get(field,"")==staff_id
			if owns: owners.append({"collection":collection,"id":record.get("id",""),"phase":record.get("phase",record.get("kind",""))})
	return owners

func snapshot(world: WorldState, metadata: Dictionary) -> Dictionary:
	var result: Dictionary = {"tick":world.sim_tick,"actors":world.present_actor_count(),"dirt":[],"orders":[],"staff":[]}
	for dirt_id: String in metadata.get("dirt_ids",[]):
		var patch: Dictionary = world.facts.environment.dirt.get(dirt_id,{})
		if patch.is_empty():
			result.dirt.append({"id":dirt_id,"present":false,"receipt":world.facts.environment.receipts.get(dirt_id+":cleanup_completed",{}).duplicate(true)})
		else:
			var row: Dictionary = _fields(patch,["id","floor_id","cell","phase","worker_id","work_cell","remaining_milli","total_milli","contributions","reason"])
			row.present = true
			result.dirt.append(row)
	for order_id: String in metadata.get("order_ids",[]):
		var order: Dictionary = world.facts.environment.orders.get(order_id,{})
		var row: Dictionary = _fields(order,["id","floor_id","phase","reason","cost"])
		row.units = []
		for unit: Dictionary in order.get("units",[]): row.units.append(_fields(unit,["id","cell","phase","worker_id","started","remaining_milli","total_milli","contributions","tool_collected"]))
		result.orders.append(row)
	var staff_ids: Array = metadata.get("cleaner_ids",[]).duplicate()
	for change: Dictionary in metadata.get("need_inputs",[]):
		if not change.staff_id in staff_ids: staff_ids.append(change.staff_id)
	for staff_id: String in staff_ids:
		var staff: Dictionary = world.facts.staff[staff_id]
		var movement: Dictionary = world.facts.moves.get(staff_id,{})
		var row: Dictionary = _fields(staff,["id","role","energy","awake_ticks","sleep_remaining_ticks","life_task","active_job_id","life_reason"])
		row.location = world.facts.actors[staff_id].location.duplicate(true)
		row.movement = _fields(movement,["target_floor","target_cell","cursor","blocked_since","yielding","transit_ticket"])
		row.movement.path_steps = movement.get("path",[]).size()
		row.movement.travelled_checkpoints = movement.get("travelled",[]).size()
		result.staff.append(row)
	return result

func assess(world: WorldState, metadata: Dictionary, window_start: Dictionary = {}) -> Dictionary:
	var last: Dictionary = snapshot(world,metadata)
	# A restored fixture can already contain completed work. Only progress after
	# the caller's measurement boundary qualifies the current timed window.
	var initial: Dictionary = window_start if not window_start.is_empty() else metadata.get("initial",{})
	var initial_staff: Dictionary = {}
	for staff: Dictionary in initial.get("staff",[]): initial_staff[staff.id] = staff
	var initial_dirt: Dictionary = {}
	for patch: Dictionary in initial.get("dirt",[]): initial_dirt[patch.id] = patch
	var started: int = 0
	var completed: int = 0
	var completed_total: int = 0
	var cleanup_work_milli: int = 0
	var assigned: int = 0
	var cross_floor_selected: int = 0
	var moved: int = 0
	var cleaner_moved: int = 0
	var new_selections: int = 0
	for patch: Dictionary in last.dirt:
		var previous: Dictionary = initial_dirt.get(patch.id,{})
		if not patch.present:
			if patch.receipt.get("kind","")=="cleanup_completed" and patch.receipt.get("source_id","")==patch.id:
				completed_total += 1
				if previous.get("present",false):
					completed += 1
					started += 1
					cleanup_work_milli += int(previous.remaining_milli)
					if str(previous.get("worker_id","")).is_empty(): new_selections += 1
			continue
		var work_delta: int = maxi(0,int(previous.get("remaining_milli",patch.remaining_milli))-int(patch.remaining_milli))
		if work_delta>0:
			started += 1
			cleanup_work_milli += work_delta
		if not str(patch.worker_id).is_empty():
			assigned += 1
			if str(previous.get("worker_id",""))!=str(patch.worker_id): new_selections += 1
			var origin: Dictionary = initial_staff.get(patch.worker_id,{}).get("location",{})
			if origin.get("kind","")=="floor" and int(origin.floor_id)!=int(patch.floor_id): cross_floor_selected += 1
	for staff: Dictionary in last.staff:
		if initial_staff.has(staff.id) and staff.location!=initial_staff[staff.id].location:
			moved += 1
			if staff.role=="cleaner": cleaner_moved += 1
	var needs_selected: int = 0
	var needs_working: int = 0
	var needs_new_tasks: int = 0
	var sleep_work_ticks: int = 0
	for change: Dictionary in metadata.get("need_inputs",[]):
		var staff: Dictionary = world.facts.staff[change.staff_id]
		var task: Dictionary = staff.get("life_task",{})
		var before: Dictionary = initial_staff.get(change.staff_id,{})
		if task.get("phase","idle")!="idle": needs_selected += 1
		if task.get("phase","") in ["rest","sleep"]: needs_working += 1
		if task.get("phase","idle")!="idle" and before.get("life_task",{}).get("phase","idle")=="idle": needs_new_tasks += 1
		if change.kind=="sleep" and task.get("phase","")=="sleep":
			var sleep_before: int = int(before.get("sleep_remaining_ticks",0))
			if sleep_before==0: sleep_before = int(change.get("sleep_total_ticks",staff.sleep_remaining_ticks))
			sleep_work_ticks += maxi(0,sleep_before-int(staff.sleep_remaining_ticks))
	var checks: Dictionary = {"setup_accepted":metadata.get("errors",[]).is_empty(),
		"some_cleanup_assigned_or_completed":assigned+completed>0,"real_movement_or_cleanup_work":cleaner_moved>0 or started>0,
		"staff_need_tasks_selected":needs_selected==metadata.get("need_inputs",[]).size()}
	if metadata.cleaning_mode=="local16": checks.local_cleanup_actually_progressed = started>0
	return {"steps":world.sim_tick-int(initial.get("tick",metadata.tick)),"elapsed_steps_since_setup":world.sim_tick-int(metadata.tick),
		"measurement_boundary_tick":int(initial.get("tick",metadata.tick)),"initial_dirt":metadata.get("dirt_ids",[]).size(),"assigned_remaining_dirt":assigned,
		"cleanup_started_or_completed":started,"cleanup_completed":completed,"cleanup_completed_since_setup":completed_total,
		"cleanup_work_milli_in_window":cleanup_work_milli,"new_cleanup_task_selections_at_least":new_selections,"cross_floor_remaining_task_selections":cross_floor_selected,
		"observed_staff_with_real_location_change":moved,"staff_needs_selected":needs_selected,"staff_needs_actually_resting_or_sleeping":needs_working,
		"observed_cleaners_with_real_location_change":cleaner_moved,"new_staff_need_tasks":needs_new_tasks,"sleep_work_ticks_in_window":sleep_work_ticks,
		"pending_renovation_units":_pending_units(world,metadata),"checks":checks,"setup_errors":metadata.get("errors",[]),"limitations":metadata.get("limitations",[]),"final":last}

func _pending_units(world: WorldState, metadata: Dictionary) -> int:
	var pending: int = 0
	for order_id: String in metadata.get("order_ids",[]):
		for unit: Dictionary in world.facts.environment.orders.get(order_id,{}).get("units",[]):
			if unit.phase not in ["completed","cancelled"]: pending += 1
	return pending

func _clinical_facts(world: WorldState) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ["visits","tickets","sessions","attempts","preparations","ward_stays","moves","adaptations"]:
		result[key] = world.facts.get(key,{}).duplicate(true)
	return result

func _fields(source: Dictionary, keys: Array) -> Dictionary:
	var result: Dictionary = {}
	for key: String in keys:
		if source.has(key): result[key] = source[key].duplicate(true) if source[key] is Dictionary or source[key] is Array else source[key]
	return result
