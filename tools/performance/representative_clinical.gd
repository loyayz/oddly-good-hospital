extends RefCounted

const Fixture = preload("res://tools/performance/fixture.gd")
const EXPECTED_PRESENT: int = 160

# Continue the complete legal input. This helper only observes production steps;
# it never seeds a service, changes a route, or shortens clinical work.
var world: WorldState
var simulation: HospitalSimulation
var content: HospitalContent
var errors: Array[String] = []
var source_path: String
var source_sha256: String
var source_tick: int = -1
var floors: Array[int] = []
var visitor_ids: Array[String] = []

var _source_actor_ids: Array = []
var _previous_sessions: Dictionary = {}
var _last_tick: int = -1
var _steps: int = 0
var _minimum_present: int = EXPECTED_PRESENT
var _maximum_present: int = EXPECTED_PRESENT
var _started: Dictionary = {}
var _completed: Dictionary = {}
var _work_ticks: Dictionary = {}
var _session_progress: Dictionary = {}
var _events: Dictionary = {}
var _last_lifecycle_events: Array = []
var _last_preparations: Dictionary = {}
var _preparations_seen: Dictionary = {}
var _source_rng: Dictionary = {}
var _source_chain: Array = []

func _init(database: HospitalContent, input_path: String) -> void:
	content = database
	source_path = input_path
	if not FileAccess.file_exists(input_path):
		errors.append("Clinical source input does not exist: "+input_path)
		return
	source_sha256 = FileAccess.get_sha256(input_path)
	var input_file: FileAccess = FileAccess.open(input_path,FileAccess.READ)
	var input_record: Dictionary = input_file.get_var()
	input_file.close()
	var prior: Dictionary = input_record.get("representative_clinical",{})
	_source_chain.assign(prior.get("source_chain",[]))
	if not prior.is_empty():
		var prior_observation: Dictionary = prior.get("observation",{}).duplicate(true)
		prior_observation.erase("source_chain")
		_source_chain.append({"source_input":prior.get("source_input",""),"source_sha256":prior.get("source_sha256",""),"observation":prior_observation,"metadata":prior.get("metadata",{})})
	var fixture: RefCounted = Fixture.new(content,EXPECTED_PRESENT,"four_floors",input_path)
	errors.assign(fixture.errors)
	world = fixture.world
	floors.assign(fixture.floors)
	visitor_ids.assign(fixture.visitor_ids)
	source_tick = world.sim_tick
	_last_tick = source_tick
	_source_actor_ids = world.facts.actors.keys()
	_source_actor_ids.sort()
	_source_rng = world.facts.rng.duplicate(true)
	var validation: String = world.validate(content)
	if not validation.is_empty(): errors.append("Clinical source validation: "+validation)
	if world.present_actor_count()!=EXPECTED_PRESENT:
		errors.append("Clinical source does not contain exactly 160 present actors")
	if not errors.is_empty(): return
	simulation = HospitalSimulation.new(world,content)
	_previous_sessions = _sessions()
	_previous_sessions.merge(_session_records(world.facts.get("clinical_suspensions",{})))
	_last_preparations = _preparations()
	for id: String in _last_preparations: _preparations_seen[id] = _last_preparations[id]

func observe(result: TickResult) -> Dictionary:
	# Call after the complete step's timer has stopped. No observation contributes
	# to the reported production execution time.
	if result==null:
		errors.append("A clinical observation requires a completed production step")
		return {"ok":false,"errors":errors.duplicate()}
	if result.sim_tick!=world.sim_tick or world.sim_tick!=_last_tick+1:
		errors.append("Clinical observation skipped or repeated a production tick")
	_steps += 1
	_last_tick = world.sim_tick
	var present: int = world.present_actor_count()
	_minimum_present = mini(_minimum_present,present)
	_maximum_present = maxi(_maximum_present,present)
	if present!=EXPECTED_PRESENT:
		errors.append("Actual population left the fixed160 workload at tick %d: %d"%[world.sim_tick,present])
	var current: Dictionary = _sessions()
	_last_lifecycle_events = []
	var finished: Dictionary = {}
	var started_ids: Dictionary = {}
	for event: SimEvent in result.facts:
		_events[event.kind] = int(_events.get(event.kind,0))+1
		if event.kind in ["service_started","service_completed"]:
			var kind: String = str(event.details.get("kind",""))
			var target: Dictionary = _started if event.kind=="service_started" else _completed
			target[kind] = int(target.get(kind,0))+1
			if event.kind=="service_started" and event.changed_ids.size()>1:
				started_ids[str(event.changed_ids[1])] = true
			if event.kind=="service_completed" and event.changed_ids.size()>1:
				finished[str(event.changed_ids[1])] = true
		if event.kind in ["service_started","service_completed","attempt_committed","patient_departed"]:
			_last_lifecycle_events.append(event.to_record())
	for id: String in current:
		var session: Dictionary = current[id]
		var prior: Dictionary = _previous_sessions.get(id,{})
		if not prior.is_empty():
			_record_progress(session,clampi(int(prior.remaining_ticks)-int(session.remaining_ticks),0,1))
		elif started_ids.has(id):
			_record_progress(session,clampi(int(session.total_ticks)-int(session.remaining_ticks),0,1))
	for id: String in finished:
		if _previous_sessions.has(id):
			var session: Dictionary = _previous_sessions[id]
			_record_progress(session,clampi(int(session.remaining_ticks),0,1))
	_previous_sessions = current
	_previous_sessions.merge(_session_records(world.facts.get("clinical_suspensions",{})))
	_last_preparations = _preparations()
	for id: String in _last_preparations: _preparations_seen[id] = _last_preparations[id]
	return {"ok":errors.is_empty(),"tick":world.sim_tick,"present":present,
		"sessions":current,"preparations":_last_preparations.duplicate(true),
		"lifecycle_events":_last_lifecycle_events.duplicate(true),"errors":errors.duplicate()}

func _record_progress(session: Dictionary, ticks: int) -> void:
	if ticks<=0: return
	var kind: String = str(session.kind)
	_work_ticks[kind] = int(_work_ticks.get(kind,0))+ticks
	var record: Dictionary = _session_progress.get(session.id,{
		"session_id":session.id,"visit_id":session.visit_id,"kind":kind,
		"facility_id":session.facility_id,"staff_ids":session.staff_ids.duplicate(),
		"total_ticks":int(session.total_ticks),"observed_work_ticks":0,
		"first_observed_tick":world.sim_tick,"start_tick":session.start_tick})
	record.observed_work_ticks += ticks
	record.last_observed_tick = world.sim_tick
	_session_progress[session.id] = record

func boundary(kind: String) -> bool:
	if not errors.is_empty() or world.present_actor_count()!=EXPECTED_PRESENT: return false
	match kind:
		"gp_started", "outpatient_started", "surgery_started":
			var service_kind: String = kind.trim_suffix("_started")
			for session: Dictionary in world.facts.sessions.values():
				if session.kind==service_kind and int(session.remaining_ticks)<int(session.total_ticks): return true
		"clinical_preparation":
			for preparation: Dictionary in _last_preparations.values():
				if preparation.kind in ["outpatient","surgery"]: return true
		"gp_handoff", "treatment_handoff":
			for event: Dictionary in _last_lifecycle_events:
				if event.kind!="service_completed": continue
				var service_kind: String = str(event.details.get("kind",""))
				if kind=="gp_handoff" and service_kind=="gp": return true
				if kind=="treatment_handoff" and service_kind in ["outpatient","surgery"]: return true
	return false

func inspect(validate_world: bool = false) -> Dictionary:
	if world==null: return {"ok":false,"errors":errors.duplicate()}
	var phase_counts: Dictionary = {}
	var waiting_reasons: Dictionary = {}
	for visit_id: String in world.active_visit_ids():
		var visit: Dictionary = world.facts.visits[visit_id]
		var phase: String = str(visit.phase)
		phase_counts[phase] = int(phase_counts.get(phase,0))+1
		var reason: String = str(visit.get("waiting_reason",""))
		if not reason.is_empty(): waiting_reasons[reason] = int(waiting_reasons.get(reason,0))+1
	var actor_ids: Array = world.facts.actors.keys()
	actor_ids.sort()
	var added_actor_records: Dictionary = {}
	for id: String in actor_ids:
		if not id in _source_actor_ids: added_actor_records[id] = world.facts.actors[id].duplicate(true)
	var occupied_stays: int = 0
	for stay: Dictionary in world.facts.get("visitors",{}).get("stays",{}).values():
		if world.facts.actors[stay.actor_id].location.kind!="outside": occupied_stays += 1
	var validation: String = world.validate(content) if validate_world else "not_requested"
	return {"ok":errors.is_empty() and (not validate_world or validation.is_empty()),
		"tick":world.sim_tick,"source_tick":source_tick,"observed_steps":_steps,
		"present":world.present_actor_count(),"minimum_present":_minimum_present,"maximum_present":_maximum_present,
		"same_actor_ids":actor_ids==_source_actor_ids,"total_actor_records":actor_ids.size(),
		"added_actor_records":added_actor_records,
		"active_patients":world.active_visit_ids().size(),"staff":world.facts.staff.size(),"present_visitors":occupied_stays,
		"rooms":world.facts.rooms.size(),"facilities":world.facts.facilities.size(),
		"phase_counts":phase_counts,"waiting_reasons":waiting_reasons,"moves":world.facts.moves.size(),
		"sessions":_sessions(),"preparations":_preparations(),"attempts":world.facts.attempts.size(),
		"work_ticks_by_kind":_work_ticks.duplicate(),"services_started":_started.duplicate(),"services_completed":_completed.duplicate(),
		"session_progress":_session_progress.duplicate(true),"preparations_seen":_preparations_seen.duplicate(true),
		"event_counts":_events.duplicate(),"last_lifecycle_events":_last_lifecycle_events.duplicate(true),
		"inventory_units":int(world.facts.inventory.units),"supply_issues":world.facts.inventory.issues.duplicate(true),
		"ledger_entries":world.facts.ledger.entries.duplicate(true),"source_rng":_source_rng.duplicate(true),
		"rng":world.facts.rng.duplicate(true),"source_chain":_source_chain.duplicate(true),"validation":validation,"errors":errors.duplicate()}

func store_input(path: String, metadata: Dictionary = {}) -> Dictionary:
	if FileAccess.file_exists(path): return {"ok":false,"reason":"Boundary output already exists; original evidence is immutable."}
	var state: Dictionary = inspect(true)
	if not bool(state.get("ok",false)) or not bool(state.get("same_actor_ids",false)) or int(state.get("present",0))!=EXPECTED_PRESENT:
		return {"ok":false,"reason":"Cannot publish an invalid or changed clinical workload.","state":state}
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if file==null: return {"ok":false,"reason":"Cannot write clinical boundary: "+path}
	file.store_var({"content_fingerprint":content.content_fingerprint,"facts":world.freeze(),
		"floors":floors.duplicate(),"visitor_ids":visitor_ids.duplicate(),
		"representative_clinical":{"source_input":source_path,"source_sha256":source_sha256,
			"engine":Engine.get_version_info().string,"source_chain":_source_chain.duplicate(true),"observation":state,"metadata":metadata.duplicate(true)}})
	file.close()
	return {"ok":true,"path":path,"sha256":FileAccess.get_sha256(path),"tick":world.sim_tick,"state":state}

func _sessions() -> Dictionary:
	return _session_records(world.facts.sessions)

func _session_records(records: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in records:
		var session: Dictionary = records[id]
		var record: Dictionary = {}
		for field: String in ["id","visit_id","kind","facility_id","staff_ids","total_ticks","remaining_ticks","start_tick","attempt_id","clinical_beat"]:
			if session.has(field): record[field] = session[field].duplicate() if session[field] is Array else session[field]
		result[id] = record
	return result

func _preparations() -> Dictionary:
	var result: Dictionary = {}
	for id: String in world.facts.preparations:
		result[id] = world.facts.preparations[id].duplicate(true)
	return result

func dispose() -> void:
	if simulation!=null: simulation.dispose()
