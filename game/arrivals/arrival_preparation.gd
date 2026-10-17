class_name ArrivalPreparation
extends RefCounted

# The main thread owns requests. The worker owns its geometry, quote caches and
# native models; only fully owned fact inputs and completed values cross over.
var content: HospitalContent
var _thread: Thread
var _active: Dictionary = {}
var _latest: Dictionary = {}
var _completed: Dictionary = {}
var _sealed: Dictionary = {}
var _sequence: int = 0
var _active_id: int = -1
var _latest_id: int = -1
var _completed_id: int = -1
var _sealed_id: int = -1
var _worker: HospitalArrivalService
var _metrics: Dictionary = {"jobs":0,"worker_wall_us":0,"worker_cpu_us":0,"cpu_measured_jobs":0,"latest_worker_us":0,"main_us":0,"max_main_us":0,"requests":0,"captures":0,"capture_us":0,"reused":0,"superseded":0}

func _init(database: HospitalContent) -> void:
	content = database

func poll(dispatch: bool = true) -> void:
	if _thread!=null and not _thread.is_alive():
		var finished: Variant = _thread.wait_to_finish()
		if not finished is Dictionary or not finished.has("projection"):
			finished = {"projection":{"complete":false,"reason":"接诊能力准备任务异常结束"},"elapsed_us":0}
		_completed = {"input":_active,"projection":finished.projection}
		_completed_id = _active_id
		_metrics.jobs += 1
		_metrics.latest_worker_us = finished.elapsed_us
		_metrics.worker_wall_us += finished.elapsed_us
		if finished.has("cpu_us"):
			_metrics.worker_cpu_us += int(finished.cpu_us)
			_metrics.cpu_measured_jobs += 1
		_thread = null
		_active = {}
		_active_id = -1
	if dispatch and _thread==null and not _latest.is_empty():
		_active = _latest
		_active_id = _latest_id
		_latest = {}
		_latest_id = -1
		_thread = Thread.new()
		var error: Error = _thread.start(_compute.bind(_active))
		if error!=OK:
			_completed = {"input":_active,"projection":{"complete":false,"reason":"无法启动接诊能力准备：%d" % error}}
			_completed_id = _active_id
			_thread = null
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
	var result: Dictionary = _poll_request(_sealed_id)
	_record_main(started)
	return result

func release_sealed() -> void:
	_sealed = {}
	_sealed_id = -1

func _select_request(input: Dictionary) -> int:
	# Collect completion before selecting the newest/sealed input. Dispatching
	# the old queued request here would put stale work ahead of this boundary.
	poll(false)
	if not _completed.is_empty() and _completed.input==input:
		_metrics.reused += 1
		_latest = {}
		_latest_id = -1
		return _completed_id
	if not _active.is_empty() and _active==input:
		_metrics.reused += 1
		_latest = {}
		_latest_id = -1
		return _active_id
	if not _latest.is_empty() and _latest==input: return _latest_id
	if not _latest.is_empty(): _metrics.superseded += 1
	_sequence += 1
	_latest = input
	_latest_id = _sequence
	return _latest_id

func _poll_request(request_id: int) -> Dictionary:
	poll()
	if request_id==_completed_id: return _completed.projection
	return {"complete":false,"pending":true,"reason":"接诊能力准备中"}

func metrics() -> Dictionary:
	return _metrics.duplicate()

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
	if not _completed.is_empty():
		_latest = _completed.input
		_sequence += 1
		_latest_id = _sequence
		if not _sealed.is_empty(): _sealed_id = _sequence
		_completed = {}
		_completed_id = -1
	poll()

func dispose() -> void:
	_latest = {}
	if _thread!=null:
		_thread.wait_to_finish()
		_thread = null
	_worker = null

func _compute(input: Dictionary) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var cpu_started: Dictionary = PlatformArrivalMath.thread_cpu()
	if _worker==null:
		var geometry: HospitalSpace = HospitalSpace.new(content)
		_worker = HospitalArrivalService.new(content,geometry)
		_worker.clinic.scheduler = HospitalShiftScheduler.new(content,geometry)
		_worker.clinic.recruitment = RecruitmentService.new(content,geometry)
		_worker.clinic.departments = HospitalDepartments.new(content,geometry)
		_worker.departments = _worker.clinic.departments
	var projection: Dictionary = _worker.capacity(WorldState.new(input.facts),input.subtract_existing)
	var result: Dictionary = {"projection":projection,"elapsed_us":Time.get_ticks_usec()-started}
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
	for field: String in ["gameplay_version","entry","facilities","rooms","floors","remodels","research","allow_outpatient_rounds","plan_strategy"]:
		if world.facts.has(field): facts[field] = world.facts[field]
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
	facts.departments = {"units":world.facts.get("departments",{}).get("units",{})}
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
	var owned: Dictionary = facts.duplicate(true)
	_metrics.captures += 1
	_metrics.capture_us += Time.get_ticks_usec()-started
	return {"facts":owned,"subtract_existing":subtract_existing}
