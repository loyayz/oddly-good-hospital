extends RefCounted

# Read-only observation workers. Every mutable service and result slot has one job
# owner; the main world and prepared source values are borrowed until the barrier.
class WorkerEnvironment extends HospitalEnvironment:
	var water_candidates: Array[String] = []
	func _water_usable(_world: WorldState, facility: Dictionary, _actor_id: String) -> bool:
		water_candidates.append(str(facility.id))
		return false
	func _finish_observation(result: Dictionary) -> Dictionary:
		result.value = int(result.value)-int(result.noise)
		result.status = "current"
		result._worker_sample_raw = true
		result._worker_sample_water = water_candidates
		return result

class SampleJob extends RefCounted:
	var environment: WorkerEnvironment
	var world: WorldState
	var requests: Array = []
	var results: Array = []
	var processed: int = 0
	var thread_id: int = 0
	var coverage_lookups: int = 0
	var elapsed_us: int = 0
	var diagnostics: bool = false
	func _init(database: HospitalContent) -> void:
		environment = WorkerEnvironment.new(database,HospitalSpace.new(database))
	func prepare(source: HospitalEnvironment, current: WorldState, batch: Array, diagnostic_times: bool = false) -> void:
		world = current
		requests = batch
		results = []
		results.resize(requests.size())
		processed = 0
		thread_id = 0
		coverage_lookups = 0
		elapsed_us = 0
		diagnostics = diagnostic_times
		environment.begin_query(current)
		environment._query.facilities = source._query.facilities
		environment._query.screens = source._query.screens
		environment._query.samples = source._query.samples
		environment._query.facilities_ready = true
		environment._query.samples_ready = true
		environment._query.edges = source._query.edges.duplicate()
		environment._positive_definitions = source._positive_definitions.duplicate()
		environment._coverage_cache = {}
		# Only mappings are copied. Completed coverage dictionaries and all edge
		# masks remain shared read-only; workers never end/merge a main query.
		for floor_id: int in source._coverage_cache:
			environment._coverage_cache[floor_id] = {"coverage":source._coverage_cache[floor_id].coverage.duplicate()}
		for floor_id: int in source._query.coverage:
			var previous: Dictionary = environment._coverage_cache.get_or_add(floor_id,{"coverage":{}})
			previous.coverage.merge(source._query.coverage[floor_id],true)
		environment.space.query_counts.clear()
	func run() -> void:
		var started: int = Time.get_ticks_usec() if diagnostics else 0
		for index: int in requests.size():
			var request: Dictionary = requests[index]
			environment._query.coverage = {}
			environment.water_candidates = []
			var observation: Dictionary = environment.sample_at(world,int(request.floor_id),request.cell,str(request.actor_id))
			var coverage: Dictionary = environment._query.coverage
			results[index] = {"observation":observation,"coverage":coverage}
			# This job's next request may reuse every earlier result. The per-query
			# map stays separate so main can insert it at the original visit point.
			for floor_id: int in coverage:
				coverage_lookups += (coverage[floor_id] as Dictionary).size()
				var previous: Dictionary = environment._coverage_cache.get_or_add(floor_id,{"coverage":{}})
				previous.coverage.merge(coverage[floor_id])
			processed += 1
		if diagnostics: elapsed_us = Time.get_ticks_usec()-started
		thread_id = OS.get_thread_caller_id()
	func release_borrowed() -> void:
		world = null
		requests = []
		environment._query = {}
		environment._query_depth = 0
		environment._coverage_cache = {}
		environment._facility_sources = {}

var _jobs: Array = []
var _content: HospitalContent
var _observations: Dictionary = {}
var _diagnostics: bool = false
var _timing: Dictionary = {}
var _apply_started: int = 0
var _last: Dictionary = {}
var _stats: Dictionary = {"batches":0,"jobs":0,"processed":0,"consumed":0,"failed_batches":0,"coverage_distinct_lookups":0,"coverage_native_calls":0,"coverage_fallback_calls":0,"threads":{},"timings_us":{}}

func prepare(world: WorldState, source: HospitalEnvironment, visit_ids: Array, task_count: int, diagnostics: bool) -> bool:
	_diagnostics = diagnostics
	_timing = {}
	_observations = {}
	var stamp: int = Time.get_ticks_usec() if _diagnostics else 0
	var requests: Array = []
	for visit_id: String in visit_ids:
		if not world.facts.departments.experience.has(visit_id): continue
		if int(world.facts.departments.experience[visit_id].closed_tick)>=0: continue
		var visit: Dictionary = world.facts.visits[visit_id]
		var actor: Dictionary = world.facts.actors[visit.actor_id]
		if actor.location.kind!="floor": continue
		requests.append({"visit_id":visit_id,"actor_id":str(visit.actor_id),"floor_id":int(actor.location.floor_id),"cell":actor.location.cell.duplicate()})
	_mark("requests_us",stamp)
	if requests.is_empty():
		_last = {"ok":true,"jobs":[],"requested":0,"processed":0,"consumed":0}
		return false
	var count: int = mini(4,mini(maxi(1,task_count),requests.size()))
	stamp = Time.get_ticks_usec() if _diagnostics else 0
	if _content!=source.content:
		_jobs = []
		_content = source.content
	while _jobs.size()<count: _jobs.append(SampleJob.new(_content))
	_mark("initialization_us",stamp)
	stamp = Time.get_ticks_usec() if _diagnostics else 0
	# These are the only lazy source builders that can touch WorldState's
	# operation indexes. Complete them on main before any job is dispatched.
	source._prepare_facility_sources(world)
	source._prepare_sample_sources(world)
	for request: Dictionary in requests:
		var floor_id: int = int(request.floor_id)
		if source._query.edges.has(floor_id) or not source.space.owned(world,floor_id,Vector2i(int(request.cell[0]),int(request.cell[1]))): continue
		var positive: bool = not source._query.facilities.get(floor_id,{}).is_empty() or not source._query.samples.walls.get(floor_id,{}).is_empty()
		var dirt: bool = not source._query.samples.dirt.get(floor_id,{}).is_empty()
		var noise: bool = not source._query.samples.machines.get(floor_id,{}).is_empty() or not source._query.samples.construction.get(floor_id,{}).is_empty()
		if positive or dirt or noise: source._coverage_edges(world,floor_id)
	for index: int in count:
		var low: int = requests.size()*index/count
		var high: int = requests.size()*(index+1)/count
		(_jobs[index] as SampleJob).prepare(source,world,requests.slice(low,high),_diagnostics)
	_mark("preparation_us",stamp)
	stamp = Time.get_ticks_usec() if _diagnostics else 0
	var group: int = WorkerThreadPool.add_group_task(_run_job,count,count,false,"Department environment observations")
	_mark("dispatch_us",stamp)
	stamp = Time.get_ticks_usec() if _diagnostics else 0
	WorkerThreadPool.wait_for_group_task_completion(group)
	_mark("wait_us",stamp)
	stamp = Time.get_ticks_usec() if _diagnostics else 0
	var valid: bool = true
	var processed: int = 0
	var job_rows: Array = []
	for index: int in count:
		var job: SampleJob = _jobs[index]
		valid = valid and job.processed==job.requests.size() and job.results.size()==job.requests.size()
		processed += job.processed
		var native_calls: int = int(job.environment.space.query_counts.get("environment_coverage_native_calls",0))
		var fallback_calls: int = int(job.environment.space.query_counts.get("environment_coverage_fallbacks",0))
		var job_row: Dictionary = {"job":index,"thread_id":job.thread_id,"requested":job.requests.size(),"processed":job.processed,"coverage_distinct_lookups":job.coverage_lookups,"coverage_native_calls":native_calls,"coverage_fallback_calls":fallback_calls}
		if _diagnostics:
			job_row.elapsed_us = job.elapsed_us
			_timing["worker_job_elapsed_us"] = int(_timing.get("worker_job_elapsed_us",0))+job.elapsed_us
		job_rows.append(job_row)
		_stats.coverage_distinct_lookups += job.coverage_lookups
		_stats.coverage_native_calls += native_calls
		_stats.coverage_fallback_calls += fallback_calls
		for number: int in job.requests.size():
			var request: Dictionary = job.requests[number]
			var item: Variant = job.results[number] if number<job.results.size() else null
			if not item is Dictionary or not item.get("observation") is Dictionary or not item.get("coverage") is Dictionary:
				valid = false
				continue
			var observation: Dictionary = item.observation
			if not observation.get("value") is int or not observation.get("noise") is int or not observation.get("dirt") is int or not observation.get("clean") is bool or not observation.get("water") is bool or not observation.get("subject_id") is String or not observation.get("status") is String:
				valid = false
				continue
			var status: String = observation.status
			if observation.subject_id!=str(request.actor_id) or not status in ["current","outside_owned_floor"]:
				valid = false
				continue
			if status=="current":
				if not observation.get("_worker_sample_raw") is bool or not observation._worker_sample_raw or not observation.get("_worker_sample_water") is Array:
					valid = false
					continue
				var candidates_valid: bool = true
				for candidate: Variant in observation._worker_sample_water:
					if not candidate is String or not world.facts.facilities.has(candidate): candidates_valid = false
				if not candidates_valid:
					valid = false
					continue
			elif observation.has("_worker_sample_raw") or observation.has("_worker_sample_water"):
				valid = false
				continue
			_observations[str(request.visit_id)] = item
		for key: String in job.environment.space.query_counts:
			source.space.query_counts[key] = int(source.space.query_counts.get(key,0))+int(job.environment.space.query_counts[key])
		var thread_key: String = str(job.thread_id)
		_stats.threads[thread_key] = int(_stats.threads.get(thread_key,0))+1
		job.release_borrowed()
	valid = valid and processed==requests.size() and _observations.size()==requests.size()
	_stats.batches += 1
	_stats.jobs += count
	_stats.processed += processed
	_last = {"ok":valid,"group_id":group,"main_thread_id":OS.get_main_thread_id(),"jobs":job_rows,"requested":requests.size(),"processed":processed,"consumed":0}
	_mark("harvest_us",stamp)
	if not valid:
		_stats.failed_batches += 1
		_observations = {}
		for job: SampleJob in _jobs: job.results = []
		_record_times(source)
	return valid

func _run_job(index: int) -> void:
	(_jobs[index] as SampleJob).run()

func begin_apply() -> void:
	_apply_started = Time.get_ticks_usec() if _diagnostics else 0

func consume(world: WorldState, source: HospitalEnvironment, visit_id: String, actor_id: String) -> Dictionary:
	var item: Dictionary = _observations[visit_id]
	var stamp: int = Time.get_ticks_usec() if _diagnostics else 0
	for floor_id: int in item.coverage:
		source._query.coverage.get_or_add(floor_id,{}).merge(item.coverage[floor_id])
	_mark("coverage_merge_us",stamp)
	stamp = Time.get_ticks_usec() if _diagnostics else 0
	var observation: Dictionary = item.observation
	if bool(observation.get("_worker_sample_raw",false)):
		for id: String in observation._worker_sample_water:
			if source._water_usable(world,world.facts.facilities[id],actor_id):
				observation.water = true
				break
		if observation.water: observation.value += int(source.content.balance.environment.water_bonus)
		observation.value = clampi(int(observation.value),0,100)
		observation.erase("_worker_sample_raw")
		observation.erase("_worker_sample_water")
	_mark("serial_water_and_finish_us",stamp)
	_observations.erase(visit_id)
	_stats.consumed += 1
	_last.consumed += 1
	return observation

func end_apply(source: HospitalEnvironment) -> void:
	_mark("main_apply_inclusive_us",_apply_started)
	_last.all_results_consumed = _observations.is_empty()
	_observations = {}
	for job: SampleJob in _jobs: job.results = []
	_record_times(source)

func _mark(key: String, started: int) -> void:
	if _diagnostics: _timing[key] = int(_timing.get(key,0))+Time.get_ticks_usec()-started

func _record_times(source: HospitalEnvironment) -> void:
	if not _diagnostics: return
	_last.timings_us = _timing.duplicate()
	for key: String in _timing:
		_stats.timings_us[key] = int(_stats.timings_us.get(key,0))+int(_timing[key])
		var counter: String = "diag_worker_sample_"+key
		source.space.query_counts[counter] = int(source.space.query_counts.get(counter,0))+int(_timing[key])

func report() -> Dictionary:
	var result: Dictionary = _stats.duplicate(true)
	result.last_batch = _last.duplicate(true)
	result.diagnostics_enabled = _diagnostics
	result.limits = ["Timings include task/clock/container overhead and are diagnostic only.","Main apply includes serial water and coverage merge; these intervals must not be added.","Worker job elapsed spans overlap and are not thread CPU time or a complete-step partition.","Coverage lookups count distinct keys per request, compared separately with actual native/fallback computations.","Per-job independent coverage reuse can duplicate misses across chunks; all query work is retained."]
	return result
