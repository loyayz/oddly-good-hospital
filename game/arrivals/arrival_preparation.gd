class_name ArrivalPreparation
extends RefCounted

class Cancellation extends RefCounted:
	var _mutex: Mutex = Mutex.new()
	var _requested: bool = false
	var _requested_us: int = 0
	func request() -> void:
		_mutex.lock()
		if not _requested: _requested_us = Time.get_ticks_usec()
		_requested = true
		_mutex.unlock()
	func requested() -> bool:
		_mutex.lock()
		var value: bool = _requested
		_mutex.unlock()
		return value
	func requested_at_us() -> int:
		_mutex.lock()
		var value: int = _requested_us
		_mutex.unlock()
		return value

# The main thread owns requests. The worker owns its geometry, quote caches and
# native models; only fully owned fact inputs and completed values cross over.
var content: HospitalContent
var _thread: Thread
var _active_cancellation: Cancellation
var _active: Dictionary = {}
var _latest: Dictionary = {}
var _completed: Dictionary = {}
var _sealed: Dictionary = {}
var _sealed_result: Dictionary = {}
var _sequence: int = 0
var _active_id: int = -1
var _latest_id: int = -1
var _completed_id: int = -1
var _sealed_id: int = -1
var _worker: HospitalArrivalService
var _capture_base: Dictionary = {}
var _layout_values: Dictionary = {}
var _metrics: Dictionary = {"jobs":0,"worker_wall_us":0,"worker_cpu_us":0,"cpu_measured_jobs":0,"latest_worker_us":0,"main_us":0,"max_main_us":0,"requests":0,"captures":0,"capture_us":0,"copied_records":0,"reused_records":0,"reused":0,"superseded":0}

func _init(database: HospitalContent) -> void:
	content = database

func poll(dispatch: bool = true) -> void:
	if _thread!=null and not _thread.is_alive():
		var finished: Variant = _thread.wait_to_finish()
		if not finished is Dictionary or not finished.has("projection"):
			finished = {"projection":{"complete":false,"reason":"接诊能力准备任务异常结束"},"elapsed_us":0}
		if not finished.projection.get("cancelled",false):
			_completed = {"input":_active,"projection":finished.projection}
			_completed_id = _active_id
			if _completed_id==_sealed_id: _sealed_result = _completed.projection
		_record_worker(finished)
		if not _latest.is_empty() and not _same_input(_active,_latest) and (_sealed.is_empty() or not _same_input(_active,_sealed)):
			_metrics.obsolete_jobs = int(_metrics.get("obsolete_jobs",0))+1
			_metrics.obsolete_cpu_us = int(_metrics.get("obsolete_cpu_us",0))+int(finished.get("cpu_us",0))
		_thread = null
		_active_cancellation = null
		_active = {}
		_active_id = -1
	if dispatch and _thread==null and not _latest.is_empty():
		_active = _latest
		_active_id = _latest_id
		_latest = {}
		_latest_id = -1
		_thread = Thread.new()
		_active_cancellation = Cancellation.new()
		var error: Error = _thread.start(_compute.bind(_active,_active_cancellation))
		if error!=OK:
			_completed = {"input":_active,"projection":{"complete":false,"reason":"无法启动接诊能力准备：%d" % error}}
			_completed_id = _active_id
			if _completed_id==_sealed_id: _sealed_result = _completed.projection
			_thread = null
			_active_cancellation = null
			_active = {}
			_active_id = -1

func projection(world: WorldState, subtract_existing: bool, target_tick: int = -1) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	if not _sealed.is_empty():
		if _sealed.subtract_existing!=subtract_existing: return {"complete":false,"pending":true,"reason":"正在完成已封闭的接诊边界"}
		var result: Dictionary = _poll_request(_sealed_id)
		_record_main(started)
		return result
	var result: Dictionary = _poll_request(_select_request(_capture(world,subtract_existing,target_tick)))
	_record_main(started)
	return result

func sealed_projection(world: WorldState, subtract_existing: bool) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	if _sealed.is_empty():
		_sealed = _capture(world,subtract_existing,-1)
		_sealed_id = _select_request(_sealed)
		if _sealed_id==_completed_id: _sealed_result = _completed.projection
	var result: Dictionary = _poll_request(_sealed_id)
	_record_main(started)
	return result

func release_sealed() -> void:
	_sealed = {}
	_sealed_id = -1
	_sealed_result = {}

func _select_request(input: Dictionary) -> int:
	# Collect completion before selecting the newest/sealed input. Dispatching
	# the old queued request here would put stale work ahead of this boundary.
	poll(false)
	if not _completed.is_empty() and _same_input(_completed.input,input):
		_metrics.reused += 1
		_latest = {}
		_latest_id = -1
		return _completed_id
	if not _active.is_empty() and _same_input(_active,input):
		_metrics.reused += 1
		_latest = {}
		_latest_id = -1
		return _active_id
	if not _latest.is_empty() and _same_input(_latest,input): return _latest_id
	if not _latest.is_empty(): _metrics.superseded += 1
	_sequence += 1
	_latest = input
	_latest_id = _sequence
	return _latest_id

func _same_input(first: Dictionary, second: Dictionary) -> bool:
	if not first.has("layers") or not second.has("layers"): return first==second
	if first.subtract_existing!=second.subtract_existing: return false
	if first.layers.size()!=second.layers.size(): return false
	for layer: String in first.layers:
		if not second.layers.has(layer): return false
		var a: Dictionary = first.layers[layer]
		var b: Dictionary = second.layers[layer]
		if a.size()!=b.size(): return false
		for field: String in a:
			if not b.has(field): return false
			if not is_same(a[field],b[field]) and a[field]!=b[field]: return false
	return true

func _poll_request(request_id: int) -> Dictionary:
	if request_id==_sealed_id and not _sealed_result.is_empty(): return _sealed_result
	if request_id==_completed_id: return _completed.projection
	poll()
	if request_id==_sealed_id and not _sealed_result.is_empty(): return _sealed_result
	if request_id==_completed_id: return _completed.projection
	return {"complete":false,"pending":true,"reason":"接诊能力准备中"}

func metrics() -> Dictionary:
	return _metrics.duplicate()

func _record_worker(finished: Dictionary) -> void:
	_metrics.jobs += 1
	_metrics.latest_worker_us = finished.elapsed_us
	_metrics.worker_wall_us += finished.elapsed_us
	if finished.has("cpu_us"):
		_metrics.worker_cpu_us += int(finished.cpu_us)
		_metrics.cpu_measured_jobs += 1
	if finished.projection.get("cancelled",false):
		_metrics.cancelled_jobs = int(_metrics.get("cancelled_jobs",0))+1
		_metrics.cancel_response_us = int(finished.get("cancel_response_us",0))
		_metrics.max_cancel_response_us = maxi(int(_metrics.get("max_cancel_response_us",0)),int(_metrics.cancel_response_us))

func _record_main(started: int) -> void:
	var elapsed: int = Time.get_ticks_usec()-started
	_metrics.requests += 1
	_metrics.main_us += elapsed
	_metrics.max_main_us = maxi(_metrics.max_main_us,elapsed)

func prepare_next_day(world: WorldState) -> void:
	# There is no useful slot while both a worker and its coalesced successor
	# are pending. Capture current owners at the next free slot or sealed day
	# boundary, rather than copying them again on every ordinary step.
	poll(false)
	if _thread!=null and not _latest.is_empty(): return
	projection(world,true,(world.sim_tick/WorldState.TICKS_PER_DAY+1)*WorldState.TICKS_PER_DAY)

func retry() -> void:
	if not _sealed.is_empty() or not _completed.is_empty():
		_latest = _sealed if not _sealed.is_empty() else _completed.input
		_sequence += 1
		_latest_id = _sequence
		if not _sealed.is_empty():
			_sealed_id = _sequence
			_sealed_result = {}
		_completed = {}
		_completed_id = -1
	poll()

func dispose() -> void:
	_latest = {}
	if _thread!=null:
		# Finish the current case or native call normally, then stop before the
		# next unit. Replacing latest or retaining a sealed consumer never cancels.
		var started: int = Time.get_ticks_usec()
		if _active_cancellation!=null: _active_cancellation.request()
		var finished: Variant = _thread.wait_to_finish()
		_metrics.dispose_wait_us = Time.get_ticks_usec()-started
		if finished is Dictionary and finished.has("projection") and finished.has("elapsed_us"): _record_worker(finished)
		_thread = null
	_active_cancellation = null
	_worker = null
	release_sealed()
	_completed = {}
	_completed_id = -1
	_active = {}
	_active_id = -1
	_capture_base = {}
	_layout_values = {}

func _compute(input: Dictionary, cancellation: Cancellation = null) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var cpu_started: Dictionary = PlatformArrivalMath.thread_cpu()
	if _worker==null:
		var geometry: HospitalSpace = HospitalSpace.new(content)
		_worker = HospitalArrivalService.new(content,geometry)
		_worker.clinic.scheduler = HospitalShiftScheduler.new(content,geometry)
		_worker.clinic.recruitment = RecruitmentService.new(content,geometry)
		_worker.clinic.departments = HospitalDepartments.new(content,geometry)
		_worker.departments = _worker.clinic.departments
	var stop: Callable = cancellation.requested if cancellation!=null else Callable()
	var projection: Dictionary = _worker.capacity(WorldState.new(input.facts),input.subtract_existing,stop)
	var result: Dictionary = {"projection":projection,"elapsed_us":Time.get_ticks_usec()-started}
	if cancellation!=null and cancellation.requested(): result.cancel_response_us = Time.get_ticks_usec()-cancellation.requested_at_us()
	var cpu_finished: Dictionary = PlatformArrivalMath.thread_cpu()
	if cpu_started.has("cpu_us") and cpu_finished.has("cpu_us"): result.cpu_us = int(cpu_finished.cpu_us)-int(cpu_started.cpu_us)
	return result

func _capture(world: WorldState, subtract_existing: bool, target_tick: int) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	# Copy the geometry and current resource owners, never the hospital's ledger,
	# RNG, receipts, residents, completed visits or accumulated attempt history.
	var clock: int = world.sim_tick if subtract_existing else world.sim_tick/WorldState.TICKS_PER_DAY*WorldState.TICKS_PER_DAY
	var facts: Dictionary = {"hospital_id":world.hospital_id,"world_revision":0,"entity_next":0,
		"sim_tick":target_tick if target_tick>=0 else clock}
	_layout_values = world.capacity_layout()
	for field: String in ["gameplay_version","entry","facilities","rooms","floors","remodels","research","allow_outpatient_rounds","plan_strategy"]:
		if world.facts.has(field): facts[field] = _layout_values.get(field,world.facts[field])
	facts.connectors = HospitalTransit.reference_conditions(world)
	facts.staff = {}
	for id: String in world.facts.staff:
		var staff: Dictionary = world.facts.staff[id]
		var record: Dictionary = {}
		for field: String in ["id","role","departed","abilities","certificates","title_id","personality_id","skill","ward_id","plan_experience",
			"schedule","schedule_day","schedule_overrides","leave_plan","fatigue","energy","rest_debt_ticks","rest_obligation","sleep_remaining_ticks","life_task"]:
			if staff.has(field): record[field] = staff[field]
		facts.staff[id] = record
	facts.arrivals = {"disease_weights":world.facts.arrivals.disease_weights,"next_preset":world.facts.arrivals.next_preset}
	facts.departments = {"units":world.department_records()}
	for unit: Dictionary in facts.departments.units.values():
		if not str(unit.get("focus_id","")).is_empty():
			facts.departments.cases = world.facts.get("departments",{}).get("cases",[])
			break
	facts.maintenance = {"jobs":{},"upgrades":{}}
	for collection: String in facts.maintenance:
		for id: String in world.facts.get("maintenance",{}).get(collection,{}):
			var job: Dictionary = world.facts.maintenance[collection][id]
			if not job.get("phase","") in ["completed","cancelled"]: facts.maintenance[collection][id] = job
	facts.actors = {}
	for id: String in world.facts.staff:
		var actor: Dictionary = world.facts.actors[id]
		facts.actors[id] = {"id":id,"species_id":actor.species_id,"body_binding_id":actor.get("body_binding_id",""),
			"location":actor.location if subtract_existing else {"kind":"outside"},"facing":actor.facing,"posture":actor.get("posture","standing")}
		if subtract_existing and actor.has("support_facility_id"): facts.actors[id].support_facility_id = actor.support_facility_id
	facts.moves = HospitalTransit.reference_movements(world)
	if subtract_existing:
		for id: String in world.facts.connectors:
			if world.facts.connectors[id].has("assigned_actor_id"): facts.connectors[id].assigned_actor_id = world.facts.connectors[id].assigned_actor_id
		for id: String in world.facts.moves:
			var movement: Dictionary = world.facts.moves[id]
			if movement.has("transit_ticket"):
				facts.moves[id] = {"members":movement.get("members",[]),"offsets":movement.get("offsets",{}),"transit_ticket":movement.transit_ticket}
		# Dynamic exit occupancy is read by the original transit estimator.
		for id: String in world.facts.actors:
			var actor: Dictionary = world.facts.actors[id]
			if actor.location.kind=="floor":
				facts.actors[id] = {"id":id,"species_id":actor.species_id,"body_binding_id":actor.get("body_binding_id",""),"location":actor.location,"facing":actor.facing,"posture":actor.get("posture","standing")}
				if actor.has("support_facility_id"): facts.actors[id].support_facility_id = actor.support_facility_id
		for id: String in facts.moves:
			for member: String in facts.moves[id].get("members",[id]): facts.actors[member] = world.facts.actors[member]
	for connection: Dictionary in world.facts.connectors.values():
		for id: String in connection.get("riders",[]): facts.actors[id] = world.facts.actors[id]
	for field: String in ["sessions","preparations","ward_stays","tickets","visits","attempts","adaptations"]: facts[field] = {}
	if subtract_existing:
		# The nominal reference removes these later; actual promises require the
		# currently expanded anchors, participants and release envelope.
		facts.adaptations = world.facts.adaptations
		var visits: Dictionary = {}
		for field: String in ["sessions","preparations","ward_stays","tickets"]:
			facts[field] = world.facts[field]
			for record: Dictionary in world.facts[field].values():
				if record.has("visit_id"): visits[record.visit_id] = true
				var attempt_id: String = str(record.get("attempt_id",""))
				if world.facts.attempts.has(attempt_id):
					visits[world.facts.attempts[attempt_id].visit_id] = true
		for id: String in visits:
			var visit: Dictionary = world.facts.visits[id]
			facts.visits[id] = visit
			facts.actors[visit.actor_id] = world.facts.actors[visit.actor_id]
			for attempt_id: String in visit.attempt_ids:
				var attempt: Dictionary = world.facts.attempts[attempt_id]
				facts.attempts[attempt_id] = {"visit_id":attempt.visit_id,"bed_id":attempt.get("bed_id",""),"facility_id":attempt.facility_id,"staff_ids":attempt.staff_ids}
	var owned: Dictionary = _own_capture(facts)
	_metrics.captures += 1
	_metrics.capture_us += Time.get_ticks_usec()-started
	_metrics.source_tick = world.sim_tick
	_metrics.target_tick = facts.sim_tick
	var layers: Dictionary = {"layout":{},"reference":{},"current":{}}
	for field: String in owned:
		var layer: String = "layout" if _layout_values.has(field) else ("reference" if field in ["gameplay_version","facilities","staff","research","arrivals","departments","allow_outpatient_rounds","plan_strategy","remodels"] else "current")
		layers[layer][field] = owned[field]
	return {"facts":owned,"layers":layers,"subtract_existing":subtract_existing}

func _own_capture(facts: Dictionary) -> Dictionary:
	# Each request is a complete snapshot. Unchanged values can share the last
	# owned read-only records; replacing latest never discards an unapplied delta.
	if _capture_base.get("hospital_id")!=facts.hospital_id: _capture_base = {}
	var owned: Dictionary = {}
	for field: String in facts:
		var value: Variant = facts[field]
		if _layout_values.has(field) and is_same(value,_layout_values[field]):
			owned[field] = value
			_metrics.layout_reuses = int(_metrics.get("layout_reuses",0))+1
			continue
		if field=="departments":
			# Units are already isolated immutable values owned by WorldState.
			# Only the optional focus-history input still needs content ownership.
			owned[field] = {"units":value.units}
			if value.has("cases"):
				var previous_cases: Array = _capture_base.get(field,{}).get("cases",[])
				owned[field].cases = previous_cases if previous_cases==value.cases else value.cases.duplicate(true)
			continue
		if value is Dictionary:
			var previous: Dictionary = _capture_base.get(field,{})
			var records: Dictionary = {}
			var unchanged: bool = previous.size()==value.size()
			for id: Variant in value:
				var record: Variant = value[id]
				if field=="facilities" and not record.get("use_receipts",{}).is_empty():
					record = record.duplicate()
					record.use_receipts = {}
				_metrics.scanned_records = int(_metrics.get("scanned_records",0))+1
				if previous.has(id) and (record is Dictionary or record is Array): _metrics.deep_compares = int(_metrics.get("deep_compares",0))+1
				if previous.has(id) and previous[id]==record:
					records[id] = previous[id]
					_metrics.reused_records += 1
				else:
					unchanged = false
					records[id] = record.duplicate(true) if record is Dictionary or record is Array else record
					_metrics.copied_records += 1
			owned[field] = previous if unchanged else records
		else: owned[field] = value.duplicate(true) if value is Array else value
	_capture_base = owned
	return owned
