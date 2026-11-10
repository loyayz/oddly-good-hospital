extends RefCounted

enum RequestSlot { VISIT_ID, ACTOR_ID, FLOOR_ID, CELL }
enum ResultSlot { OBSERVATION, COVERAGE, SIZE }

# Read-only observation workers. Every mutable service and result slot has one job
# owner; the main world and prepared source values are borrowed until the barrier.
class WorkerEnvironment extends HospitalEnvironment:
	var water_candidates: Array[String] = []
	var coverage_seed: Dictionary = {}
	func _cached_coverage(floor_id: int, key: String) -> Variant:
		var previous: Variant = super._cached_coverage(floor_id,key)
		if previous!=null: return previous
		# _coverage_edges replaces rebuilt floors with source-bearing entries,
		# invalidating every historical seed value for that floor.
		var local_entry: Variant = _coverage_cache.get(floor_id)
		if local_entry!=null and local_entry.has("source"): return null
		var seed_entry: Variant = coverage_seed.get(floor_id)
		if seed_entry==null: return null
		var coverage: Variant = seed_entry.get("coverage")
		return coverage.get(key) if coverage!=null else null
	var _owned_diagnostics: bool = false
	var _owned_fast_checks: int = 0
	var _owned_fallback_checks: int = 0
	func _owned_at(world: WorldState, floor_id: int, cell: Vector2i) -> bool:
		if _query.get("worker_owned_prepared",false)!=true or _query_depth<=0 or not is_same(_query.get("world"),world) or space==null or space.get_script()!=preload("res://game/building/hospital_space.gd"):
			if _owned_diagnostics: _owned_fallback_checks += 1
			return super._owned_at(world,floor_id,cell)
		var raw_floors: Variant = _query.get("edges")
		if not raw_floors is Dictionary:
			if _owned_diagnostics: _owned_fallback_checks += 1
			return super._owned_at(world,floor_id,cell)
		var floors: Dictionary = raw_floors
		var raw_edge: Variant = floors.get(floor_id)
		if not raw_edge is Dictionary:
			if _owned_diagnostics: _owned_fallback_checks += 1
			return super._owned_at(world,floor_id,cell)
		var edge: Dictionary = raw_edge
		var raw_owned: Variant = edge.get("owned")
		if not raw_owned is Dictionary:
			if _owned_diagnostics: _owned_fallback_checks += 1
			return super._owned_at(world,floor_id,cell)
		if _owned_diagnostics: _owned_fast_checks += 1
		if floor_id<1 or cell.x<0 or cell.y<0 or cell.x>=96 or cell.y>=96: return false
		var owned: Dictionary = raw_owned
		return owned.has(Vector2i(cell.x/32,cell.y/32))
	func _water_usable(_world: WorldState, facility: Dictionary, _actor_id: String) -> bool:
		water_candidates.append(str(facility.id))
		return false
	func _finish_preference_sources(result: Dictionary, moisture: Dictionary, water_distances: Dictionary) -> void:
		super._finish_preference_sources(result,moisture,water_distances)
		if water_candidates.is_empty(): return
		result._worker_sample_moisture = moisture
		result._worker_sample_water_distances = water_distances
	func _finish_observation(result: Dictionary) -> Dictionary:
		if water_candidates.is_empty(): return super._finish_observation(result)
		result.quiet = int(result.noise)==0
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
	func prepare(source: HospitalEnvironment, current: WorldState, batch: Array, seed: Dictionary, diagnostic_times: bool = false, bounds: Variant = null) -> void:
		world = current
		requests = batch
		results = []
		results.resize(requests.size())
		processed = 0
		thread_id = 0
		coverage_lookups = 0
		elapsed_us = 0
		diagnostics = diagnostic_times
		environment._owned_diagnostics = diagnostic_times
		environment._owned_fast_checks = 0
		environment._owned_fallback_checks = 0
		environment.begin_query(current)
		environment._query.facilities = source._query.facilities
		environment._query.screens = source._query.screens
		environment._query.samples = source._query.samples
		environment._query.facilities_ready = true
		environment._query.samples_ready = true
		environment._query.edges = source._query.edges.duplicate()
		# Canonical floors use bounded ground plots; legacy upper plots can alias
		# when converted to Vector2i, so they retain HospitalSpace.owned.
		environment._query.worker_owned_prepared = current.facts.floors.has("completed_top_floor") and source.get_script()==preload("res://game/operations/environment_service.gd") and source.space!=null and source.space.get_script()==preload("res://game/building/hospital_space.gd") and source._query_depth>0 and is_same(source._query.get("world"),current)
		if environment._query.worker_owned_prepared and bounds is Dictionary:
			environment._query.observation_bounds = bounds
			environment._query.observation_bounds_complete = true
		environment._positive_definitions = source._positive_definitions.duplicate()
		environment._coverage_cache = {}
		environment.coverage_seed = seed
		environment.space.query_counts.clear()
	func run() -> void:
		var started: int = Time.get_ticks_usec() if diagnostics else 0
		for index: int in requests.size():
			var request: Array = requests[index]
			environment._query.coverage = {}
			environment.water_candidates = []
			var observation: Dictionary = environment.sample_at(world,int(request[RequestSlot.FLOOR_ID]),request[RequestSlot.CELL],str(request[RequestSlot.ACTOR_ID]))
			var coverage: Dictionary = environment._query.coverage
			results[index] = [observation,coverage]
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
		environment.coverage_seed = {}
		environment._facility_sources = {}
		environment._owned_diagnostics = false
		environment._owned_fast_checks = 0
		environment._owned_fallback_checks = 0

var _jobs: Array = []
var _content: HospitalContent
var _observations: Dictionary = {}
var _diagnostics: bool = false
var _timing: Dictionary = {}
var _apply_started: int = 0
var _last: Dictionary = {}
var _stats: Dictionary = {"batches":0,"jobs":0,"processed":0,"consumed":0,"failed_batches":0,"main_empty_observations":0,"coverage_distinct_lookups":0,"coverage_native_calls":0,"coverage_fallback_calls":0,"threads":{},"timings_us":{}}

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
		requests.append([visit_id,str(visit.actor_id),int(actor.location.floor_id),actor.location.cell.duplicate()])
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
	var request_floors: Dictionary = {}
	for request: Array in requests: request_floors[int(request[RequestSlot.FLOOR_ID])] = true
	var observation_bounds: Variant = source._prepare_observation_bounds(world,request_floors.keys())
	for request: Array in requests:
		var floor_id: int = int(request[RequestSlot.FLOOR_ID])
		var cell: Array = request[RequestSlot.CELL]
		if source._query.edges.has(floor_id) or not source.space.owned(world,floor_id,Vector2i(int(cell[0]),int(cell[1]))): continue
		var positive: bool = not source._query.facilities.get(floor_id,{}).is_empty() or not source._query.samples.walls.get(floor_id,{}).is_empty()
		var dirt: bool = not source._query.samples.dirt.get(floor_id,{}).is_empty()
		var noise: bool = not source._query.samples.machines.get(floor_id,{}).is_empty() or not source._query.samples.construction.get(floor_id,{}).is_empty()
		if positive or dirt or noise: source._coverage_edges(world,floor_id)
	# The native empty-source fast path needs no worker observation. Keep every
	# requested result, and dispatch only the requests that still need sampling.
	var worker_requests: Array = _prepare_empty_samples(world,source,requests,observation_bounds)
	var main_empty: int = requests.size()-worker_requests.size()
	count = mini(4,mini(maxi(1,task_count),worker_requests.size()))
	# Copy the historical mappings once. Workers share this immutable seed and
	# write only their own overlays; completed coverage values stay borrowed.
	var coverage_seed: Dictionary = {}
	for floor_id: int in source._coverage_cache:
		coverage_seed[floor_id] = {"coverage":source._coverage_cache[floor_id].coverage.duplicate()}
	for floor_id: int in source._query.coverage:
		var previous: Dictionary = coverage_seed.get_or_add(floor_id,{"coverage":{}})
		previous.coverage.merge(source._query.coverage[floor_id],true)
	for entry: Dictionary in coverage_seed.values():
		entry.coverage.make_read_only()
		entry.make_read_only()
	coverage_seed.make_read_only()
	for index: int in count:
		var low: int = worker_requests.size()*index/count
		var high: int = worker_requests.size()*(index+1)/count
		(_jobs[index] as SampleJob).prepare(source,world,worker_requests.slice(low,high),coverage_seed,_diagnostics,observation_bounds)
	_mark("preparation_us",stamp)
	stamp = Time.get_ticks_usec() if _diagnostics else 0
	var group: int = -1
	if count==1:
		# One independent observation job needs no thread-pool dispatch/barrier.
		# Use the same virtual runner and result validation as the parallel path.
		_run_job(0)
		_mark("inline_job_us",stamp)
	elif count>1:
		group = WorkerThreadPool.add_group_task(_run_job,count,count,false,"Department environment observations")
		_mark("dispatch_us",stamp)
		stamp = Time.get_ticks_usec() if _diagnostics else 0
		WorkerThreadPool.wait_for_group_task_completion(group)
		_mark("wait_us",stamp)
	stamp = Time.get_ticks_usec() if _diagnostics else 0
	var valid: bool = true
	var processed: int = main_empty
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
			job_row.owned_fast_checks = job.environment._owned_fast_checks
			job_row.owned_fallback_checks = job.environment._owned_fallback_checks
			_timing["worker_job_elapsed_us"] = int(_timing.get("worker_job_elapsed_us",0))+job.elapsed_us
		job_rows.append(job_row)
		_stats.coverage_distinct_lookups += job.coverage_lookups
		_stats.coverage_native_calls += native_calls
		_stats.coverage_fallback_calls += fallback_calls
		for number: int in job.requests.size():
			var request: Array = job.requests[number]
			var item: Variant = job.results[number] if number<job.results.size() else null
			if not item is Array:
				valid = false
				continue
			if item.size()!=ResultSlot.SIZE:
				valid = false
				continue
			if not item[ResultSlot.OBSERVATION] is Dictionary or not item[ResultSlot.COVERAGE] is Dictionary:
				valid = false
				continue
			var observation: Dictionary = item[ResultSlot.OBSERVATION]
			if not observation.get("value") is int or not observation.get("noise") is int or not observation.get("dirt") is int or not observation.get("clean") is bool or not observation.get("water") is bool or not observation.get("subject_id") is String or not observation.get("status") is String:
				valid = false
				continue
			var status: String = observation.status
			if observation.subject_id!=str(request[RequestSlot.ACTOR_ID]) or not status in ["current","outside_owned_floor"]:
				valid = false
				continue
			if status=="current" and observation.has("_worker_sample_raw"):
				if not observation.get("_worker_sample_raw") is bool or not observation._worker_sample_raw or not observation.get("_worker_sample_water") is Array or not observation.get("_worker_sample_moisture") is Dictionary or not observation.get("_worker_sample_water_distances") is Dictionary:
					valid = false
					continue
				var candidates_valid: bool = true
				for candidate: Variant in observation._worker_sample_water:
					if not candidate is String or not world.facts.facilities.has(candidate) or not observation._worker_sample_water_distances.get(candidate) is int: candidates_valid = false
				if not candidates_valid:
					valid = false
					continue
			elif status=="current":
				# A worker can finish the standard observation when no live
				# water permission remains for the serial consumer.
				var finished_value: int = int(observation.value)
				if finished_value<0 or finished_value>100 or observation.water or observation.has("_worker_sample_water") or observation.has("_worker_sample_moisture") or observation.has("_worker_sample_water_distances"):
					valid = false
					continue
			elif observation.has("_worker_sample_raw") or observation.has("_worker_sample_water"):
				valid = false
				continue
			_observations[str(request[RequestSlot.VISIT_ID])] = item
		for key: String in job.environment.space.query_counts:
			source.space.query_counts[key] = int(source.space.query_counts.get(key,0))+int(job.environment.space.query_counts[key])
		var thread_key: String = str(job.thread_id)
		_stats.threads[thread_key] = int(_stats.threads.get(thread_key,0))+1
		job.release_borrowed()
	valid = valid and processed==requests.size() and _observations.size()==requests.size()
	_stats.batches += 1
	_stats.jobs += count
	_stats.processed += processed
	_stats.main_empty_observations += main_empty
	_last = {"ok":valid,"main_empty_observations":main_empty,"group_id":group,"main_thread_id":OS.get_main_thread_id(),"jobs":job_rows,"requested":requests.size(),"processed":processed,"consumed":0}
	_mark("harvest_us",stamp)
	if not valid:
		_stats.failed_batches += 1
		_observations = {}
		for job: SampleJob in _jobs: job.results = []
		_record_times(source)
	return valid

# This is exactly the source-free branch of native _observe_at, before any
# coverage, water permission or floor material is needed. Unknown/custom paths
# retain their original workers, including result validation and failure hooks.
func _prepare_empty_samples(world: WorldState, source: HospitalEnvironment, requests: Array, bounds: Variant) -> Array:
	if get_script()!=preload("res://game/operations/environment_sample_batch.gd") or source.get_script()!=HospitalEnvironment or source.space==null or source.space.get_script()!=HospitalSpace or not bounds is Dictionary or not world.facts.floors.has("completed_top_floor") or source._query_depth<=0 or not is_same(source._query.get("world"),world):
		return requests
	var pending: Array = []
	var rules: Dictionary = source.content.balance.environment
	var template: Dictionary = {"value":clampi(int(rules.base)+int(rules.clean_bonus),0,100),"noise":0,"dirt":0,"clean":true,"water":false,"light":false,"quiet":true,"moist":false,"dry":false,"cool":false,"sources":[],"subject_id":"","reference":false,"status":"current"}
	var surfaces: Dictionary = world.facts.get("environment",{}).get("surfaces",{})
	for request: Array in requests:
		var floor_id: int = int(request[RequestSlot.FLOOR_ID])
		var cell: Array = request[RequestSlot.CELL]
		var point: Variant = source._cell_key(cell)
		var regions: Variant = bounds.get(floor_id)
		var empty: bool = point is Vector2i and regions is Array
		if empty:
			for region: Rect2i in regions:
				if region.has_point(point): empty = false; break
		if empty: empty = surfaces.get(source._surface_key(floor_id,cell,"floor"),{}).is_empty()
		if empty:
			# Same canonical owned projection as WorkerEnvironment._owned_at.
			var edge: Variant = source._query.edges.get(floor_id)
			if edge is Dictionary and edge.get("owned") is Dictionary:
				empty = floor_id>=1 and edge.owned.has(Vector2i(point.x/32,point.y/32))
			else:
				empty = source.space.owned(world,floor_id,point)
		if not empty:
			pending.append(request)
			continue
		var observation: Dictionary = template.duplicate()
		observation.sources = []
		observation.subject_id = str(request[RequestSlot.ACTOR_ID])
		observation.reference = observation.subject_id.is_empty()
		_observations[str(request[RequestSlot.VISIT_ID])] = [observation,{}]
	return pending

func _run_job(index: int) -> void:
	(_jobs[index] as SampleJob).run()

func begin_apply() -> void:
	_apply_started = Time.get_ticks_usec() if _diagnostics else 0

func consume(world: WorldState, source: HospitalEnvironment, visit_id: String, actor_id: String) -> Dictionary:
	var item: Array = _observations[visit_id]
	var stamp: int = Time.get_ticks_usec() if _diagnostics else 0
	var coverage: Dictionary = item[ResultSlot.COVERAGE]
	for floor_id: int in coverage:
		source._query.coverage.get_or_add(floor_id,{}).merge(coverage[floor_id])
	_mark("coverage_merge_us",stamp)
	stamp = Time.get_ticks_usec() if _diagnostics else 0
	var observation: Dictionary = item[ResultSlot.OBSERVATION]
	if bool(observation.get("_worker_sample_raw",false)):
		var moisture: Dictionary = observation.get("_worker_sample_moisture",{})
		for id: String in observation._worker_sample_water:
			if source._water_usable(world,world.facts.facilities[id],actor_id):
				observation.water = true
				var distance: int = int(observation._worker_sample_water_distances[id])
				if moisture.is_empty() or distance<int(moisture.distance) or distance==int(moisture.distance) and id<str(moisture.id):
					moisture = {"id":id,"distance":distance,"preference":"moist"}
		if not moisture.is_empty():
			observation.moist = moisture.preference=="moist"
			observation.dry = moisture.preference=="dry"
		if observation.water: observation.value += int(source.content.balance.environment.water_bonus)
		observation.value = clampi(int(observation.value),0,100)
		observation.erase("_worker_sample_raw")
		observation.erase("_worker_sample_water")
		observation.erase("_worker_sample_moisture")
		observation.erase("_worker_sample_water_distances")
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
