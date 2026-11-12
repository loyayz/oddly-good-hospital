extends RefCounted

# Boundary facts only. No service query, quote, geometry decision, draw or command.
const EXAM_VISITS: Array = ["bench_visit_0020","bench_visit_0021","bench_visit_0044","bench_visit_0045","bench_visit_0046","bench_visit_0047","bench_visit_0048","bench_visit_0049","bench_visit_0050","bench_visit_0051","bench_visit_0052","bench_visit_0053"]
const OPERATION_FACILITIES: Array = ["bench_room_2_12_0","bench_room_2_15_0"]
const MOVE_FIELDS: Array = ["actor_id","members","request_sequence","path","cursor","target_floor","target_cell","route_pending","route_retry_tick","blocked_since","waiting_reason","local_move","detour","transit_ticket","visitor_stay_id","job_id","queue_waypoint","replan_after_transit"]
const VISIT_FIELDS: Array = ["id","actor_id","phase","ticket_id","diagnosis","final_result","waiting_reason","attempt_ids","continuation","continuation_complaint","visitor_consent","plan_decision","requested_plan_id"]
const TASK_FIELDS: Array = ["id","actor_id","owner_kind","kind","purpose","public_purpose","phase","facility_id","remaining_ticks","waiting_reason","return_to","return_area"]
var _previous: Dictionary = {}
var _family_actors: Dictionary = {}
var _tracked_visits: Dictionary = {}
var _tracked_actors: Dictionary = {}
var _tracked_facilities: Dictionary = {}
var _stream: FileAccess
var _row_number: int = 0
var _initial_tick: int = -1
var _observed_steps: int = 0
var _prefix_steps: int = 1000
var _sample_steps: int = 6000
var _counts: Dictionary = {"input":0,"prefix":0,"sample":0}
var _capture_us: int = 0
var _write_us: int = 0
var errors: Array = []

static func pick(source: Dictionary, fields: Array) -> Dictionary:
	var result: Dictionary = {}
	for field: String in fields:
		if source.has(field):
			var value: Variant = source[field]
			result[field] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result

func _context(world: WorldState, actor_ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for id: String in actor_ids:
		if id.is_empty() or result.has(id): continue
		result[id] = {"actor":world.facts.actors.get(id,{}).duplicate(true)}
		if world.facts.staff.has(id):
			result[id].staff = pick(world.facts.staff[id],["id","role","on_shift","block_new_work","active_job_id","abilities","certificates","energy","fatigue","schedule","scheduled_kind","schedule_reason","base_prepared","base_task","life_task","leave_plan"])
	return result

func _put(rows: Dictionary, world: WorldState, collection: String, id: String, state: Dictionary, actor_ids: Array = []) -> void:
	rows[collection+"/"+id] = {"collection":collection,"id":id,"state":state.duplicate(true),"actor_ids":actor_ids.duplicate(),"context":_context(world,actor_ids)}

func capture(world: WorldState, include_retained_family: bool = false) -> Dictionary:
	var rows: Dictionary = {}
	# A former worker/ward patient remains watched. A null record therefore
	# means the actual owner collection no longer has it, not a scope change.
	var visits: Dictionary = _tracked_visits
	var actors: Dictionary = _tracked_actors
	var facilities: Dictionary = _tracked_facilities
	for id: String in EXAM_VISITS: visits[id] = true
	for id: String in OPERATION_FACILITIES: facilities[id] = true
	for id: String in world.facts.get("ward_stays",{}):
		var ward: Dictionary = world.facts.ward_stays[id]
		visits[str(ward.visit_id)] = true
		facilities[str(ward.bed_id)] = true
		var patient_id: String = str(world.facts.visits.get(str(ward.visit_id),{}).get("actor_id",""))
		var nurse_id: String = str(ward.get("nurse_id",""))
		if not nurse_id.is_empty(): actors[nurse_id] = true
		_put(rows,world,"ward_stays",id,ward,[patient_id,nurse_id])
	for collection: String in ["requests","stays"]:
		for id: String in world.facts.get("visitors",{}).get(collection,{}):
			var family: Dictionary = world.facts.visitors[collection][id]
			visits[str(family.visit_id)] = true
			var relative_id: String = str(family.get("actor_id",""))
			if not relative_id.is_empty(): _family_actors[relative_id] = true
			var state: Dictionary = family.duplicate(true)
			if state.has("life_task"): state.life_task = pick(state.life_task,TASK_FIELDS)
			if state.has("public_use"): state.public_use = pick(state.public_use,TASK_FIELDS+["area","mode","arrived_tick"])
			_put(rows,world,"visitors."+collection,id,state,[relative_id,str(world.facts.visits.get(str(family.visit_id),{}).get("actor_id",""))])
	if include_retained_family:
		for id: String in world.facts.actors:
			if world.facts.actors[id].has("relative_of"): _family_actors[id] = true
	for id: String in _family_actors: actors[id] = true
	var jobs: Dictionary = {}
	for collection: String in ["jobs","upgrades"]:
		for id: String in world.facts.get("maintenance",{}).get(collection,{}):
			var job: Dictionary = world.facts.maintenance[collection][id]
			if not str(job.get("facility_id","")) in OPERATION_FACILITIES: continue
			var worker: String = str(job.get("worker_id",""))
			jobs[id] = true
			if not worker.is_empty(): actors[worker] = true
			_put(rows,world,"maintenance."+collection,id,job,[worker])
	for id: String in world.facts.get("maintenance",{}).get("contractors",{}):
		if jobs.has(str(world.facts.maintenance.contractors[id].get("job_id",""))): actors[id] = true
	# Resolve the actual resource owner as well as the waiting case. Another
	# patient's live service can own its original doctor or an operations target.
	for id: String in visits:
		var original: Dictionary = world.facts.visits.get(id,{}).get("diagnosis",{})
		if not str(original.get("doctor_id","")).is_empty(): actors[str(original.doctor_id)] = true
		if not str(original.get("facility_id","")).is_empty(): facilities[str(original.facility_id)] = true
	for id: String in facilities:
		var held: Dictionary = world.facts.adaptations.get(id,{})
		var owner_id: String = str(held.get("owner_id",""))
		if world.facts.tickets.has(owner_id): visits[str(world.facts.tickets[owner_id].visit_id)] = true
		elif world.facts.visits.has(owner_id): visits[owner_id] = true
	for collection: String in ["sessions","preparations","clinical_suspensions"]:
		for id: String in world.facts.get(collection,{}):
			var held: Dictionary = world.facts[collection][id]
			var related: bool = visits.has(str(held.get("visit_id",id))) or facilities.has(str(held.get("facility_id","")))
			for worker: String in held.get("staff_ids",[]): related = related or actors.has(worker)
			if related and world.facts.visits.has(str(held.get("visit_id",id))): visits[str(held.get("visit_id",id))] = true
	for id: String in visits:
		var visit: Dictionary = world.facts.visits.get(id,{})
		if visit.is_empty(): continue
		var patient: String = str(visit.actor_id)
		var doctor: String = str(visit.get("diagnosis",{}).get("doctor_id",""))
		actors[patient] = true
		if not doctor.is_empty(): actors[doctor] = true
		var doctor_facility: String = str(visit.get("diagnosis",{}).get("facility_id",""))
		if not doctor_facility.is_empty(): facilities[doctor_facility] = true
		_put(rows,world,"visits",id,pick(visit,VISIT_FIELDS),[patient,doctor])
		var ticket: String = str(visit.get("ticket_id",""))
		if world.facts.tickets.has(ticket): _put(rows,world,"tickets",ticket,world.facts.tickets[ticket],[patient,doctor])
		var guidance: Dictionary = world.facts.get("floor_guidance",{}).get("visits",{}).get(id,{})
		if not guidance.is_empty(): _put(rows,world,"floor_guidance.visits",id,guidance,[patient])
		var life: Dictionary = world.facts.get("waiting_life",{}).get("needs",{}).get(id,{})
		if not life.is_empty(): _put(rows,world,"waiting_life.needs",id,pick(life,TASK_FIELDS),[patient])
	for collection: String in ["preparations","clinical_suspensions"]:
		for id: String in world.facts.get(collection,{}):
			var record: Dictionary = world.facts[collection][id]
			if visits.has(str(record.get("visit_id",id))): _put(rows,world,collection,id,record,record.get("staff_ids",[]))
	for id: String in world.facts.sessions:
		var session: Dictionary = world.facts.sessions[id]
		if not visits.has(str(session.visit_id)): continue
		var participants: Array = session.get("staff_ids",[]).duplicate()
		participants.append(str(world.facts.visits[session.visit_id].actor_id))
		for actor_id: String in participants: actors[actor_id] = true
		facilities[str(session.facility_id)] = true
		_put(rows,world,"sessions",id,session,participants)
	for id: String in actors:
		var actor: Dictionary = world.facts.actors.get(id,{})
		if actor.is_empty(): continue
		var actor_state: Dictionary = pick(actor,["id","relative_of","service_role","posture","support_facility_id"])
		actor_state.location = pick(actor.get("location",{}),["kind","floor_id","connector_id"])
		_put(rows,world,"actors",id,actor_state,[id])
		if world.facts.moves.has(id):
			var movement: Dictionary = world.facts.moves[id]
			_put(rows,world,"moves",id,pick(movement,MOVE_FIELDS),movement.get("members",[id]))
			if movement.has("convoy"): rows["moves/"+id].context.convoy = movement.convoy.duplicate(true)
		if world.facts.staff.has(id):
			var staff: Dictionary = world.facts.staff[id]
			var state: Dictionary = pick(staff,["id","role","on_shift","block_new_work","active_job_id","schedule","scheduled_kind","schedule_reason","base_prepared","leave_plan"])
			state.base_task = pick(staff.get("base_task",{}),TASK_FIELDS)
			state.life_task = pick(staff.get("life_task",{}),TASK_FIELDS)
			_put(rows,world,"staff",id,state,[id])
		if world.facts.get("maintenance",{}).get("contractors",{}).has(id): _put(rows,world,"maintenance.contractors",id,world.facts.maintenance.contractors[id],[id])
	for id: String in facilities:
		var facility: Dictionary = world.facts.facilities.get(id,{})
		if facility.is_empty(): continue
		_put(rows,world,"facilities",id,pick(facility,["id","definition_id","floor_id","room_id","cell","condition","failed","pending_failure","open","intake_open","maintenance_order_id","maintenance_block","upgrade_level","upgrading_block"]))
		if world.facts.adaptations.has(id): _put(rows,world,"adaptations",id,world.facts.adaptations[id])
		var room: String = str(facility.get("room_id",""))
		if world.facts.rooms.has(room): _put(rows,world,"rooms",room,world.facts.rooms[room])
	for id: String in world.facts.get("floor_guidance",{}).get("clinic_queues",{}): _put(rows,world,"floor_guidance.clinic_queues",id,world.facts.floor_guidance.clinic_queues[id])
	for id: String in world.facts.connectors: _put(rows,world,"connectors",id,pick(world.facts.connectors[id],["id","phase","from","to","riders","trip_sequence","ticket_next","failed","pending_failure","condition"]))
	for id: String in world.facts.ledger.entries:
		var entry: Dictionary = world.facts.ledger.entries[id]
		if visits.has(str(entry.owner_id)) or jobs.has(str(entry.owner_id)): _put(rows,world,"ledger.entries",id,entry)
	_put(rows,world,"research_progress","clinical_unlocks",{"completed":world.facts.research.duplicate(),"first_profile_b_tick":world.facts.get("research_progress",{}).get("first_profile_b_tick",-1)})
	return rows

static func changed_fields(before: Dictionary, after: Dictionary) -> Dictionary:
	var keys: Array = before.keys()
	for key: String in after:
		if not before.has(key): keys.append(key)
	keys.sort()
	var changes: Dictionary = {}
	for key: String in keys:
		if before.has(key)==after.has(key) and before.get(key)==after.get(key): continue
		changes[key] = {"before_present":before.has(key),"after_present":after.has(key),"before":before.get(key),"after":after.get(key)}
	return changes

func _emit(row: Dictionary) -> void:
	var started: int = Time.get_ticks_usec()
	row.row_number = _row_number
	_row_number += 1
	_stream.store_line(JSON.stringify(row))
	_write_us += Time.get_ticks_usec()-started

func open(world: WorldState, path: String, input_sha: String, expected_final: String, prefix_steps: int, sample_steps: int) -> bool:
	if FileAccess.file_exists(path): return false
	_stream = FileAccess.open(path,FileAccess.WRITE)
	if _stream==null: return false
	_initial_tick = world.sim_tick
	_prefix_steps = prefix_steps
	_sample_steps = sample_steps
	_emit({"kind":"header","schema":1,"initial_tick":_initial_tick,"prefix_steps":prefix_steps,"sample_steps":sample_steps,"input_sha256":input_sha,"expected_final_sha256":expected_final,"exam_visits":EXAM_VISITS,"operation_facilities":OPERATION_FACILITIES,"scope":"Read-only step-boundary facts. Remaining deltas are unclassified raw changes, not proof of valid work. Removed facts do not recover an earlier request or lottery result."})
	return observe(world,-1)

func observe(world: WorldState, index: int) -> bool:
	var started: int = Time.get_ticks_usec()
	var rng: Dictionary = world.facts.rng.duplicate(true)
	var revision: int = world.revision
	var current: Dictionary = capture(world)
	if world.facts.rng!=rng or world.revision!=revision:
		errors.append("Fact capture changed RNG or revision")
		return false
	var keys: Array = _previous.keys()
	for key: String in current:
		if not _previous.has(key): keys.append(key)
	keys.sort()
	var window: String = "input" if index<0 else "prefix" if index<_prefix_steps else "sample"
	for key: String in keys:
		var before: Dictionary = _previous.get(key,{})
		var after: Dictionary = current.get(key,{})
		if before.get("state")==after.get("state"): continue
		var owner: Dictionary = before if after.is_empty() else after
		var deltas: Dictionary = {}
		for field: String in ["remaining_ticks","remaining_milli","completed_milli"]:
			if before.get("state",{}).has(field) and after.get("state",{}).has(field): deltas[field] = after.state[field]-before.state[field]
		var operation: String = "create" if before.is_empty() else "remove" if after.is_empty() else "update"
		var context: Dictionary = after.context if not after.is_empty() else _context(world,before.get("actor_ids",[]))
		_emit({"kind":"change","index":index,"tick":world.sim_tick,"window":window,"key":key,"collection":owner.collection,"id":owner.id,"operation":operation,"fields":changed_fields(before.get("state",{}),after.get("state",{})),"before_context":before.get("context",{}),"context":context,"raw_numeric_deltas":deltas})
		_counts[window] += 1
	_previous = current
	if index>=0: _observed_steps += 1
	_capture_us += Time.get_ticks_usec()-started
	if index%100==0: _stream.flush()
	return true

func finish() -> Dictionary:
	var summary: Dictionary = {"observed_steps":_observed_steps,"change_rows":_counts,"errors":errors.duplicate(),"capture_inclusive_us":_capture_us,"header_and_change_write_us":_write_us,"scope":"Capture includes container/comparison/serialization and change-row writes. The write counter also includes the header; both counters exclude footer writing. These overlap and cannot be subtracted as pure CPU. Remaining resets are not work."}
	_emit({"kind":"footer","summary":summary})
	_stream.close()
	return summary
