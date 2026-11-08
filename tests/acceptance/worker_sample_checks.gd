extends RefCounted

# This is one finite GROW-75 helper, not
# a replacement for the fixed 160-person whole-step measurements.
const WorkerBatch = preload("res://game/operations/environment_sample_batch.gd")

class MissingSlotBatch extends WorkerBatch:
	func _run_job(index: int) -> void:
		super._run_job(index)
		if index==0 and not _jobs[index].results.is_empty():
			_jobs[index].results[0] = null

class SeedInspectionBatch extends WorkerBatch:
	var captured_seed: Dictionary = {}
	var shared_seed: bool = true
	func _run_job(index: int) -> void:
		if index==0:
			captured_seed = _jobs[index].environment.coverage_seed
			for job: RefCounted in _jobs:
				if not job.requests.is_empty(): shared_seed = shared_seed and is_same(captured_seed,job.environment.coverage_seed)
		super._run_job(index)

class MalformedSlotBatch extends WorkerBatch:
	var corruption: String = ""
	func _run_job(index: int) -> void:
		super._run_job(index)
		if index!=0 or _jobs[index].results.is_empty(): return
		var item: Array = _jobs[index].results[0]
		var observed: Dictionary = item[WorkerBatch.ResultSlot.OBSERVATION]
		match corruption:
			"result_dictionary":
				_jobs[index].results[0] = {"observation":item[WorkerBatch.ResultSlot.OBSERVATION],"coverage":item[WorkerBatch.ResultSlot.COVERAGE]}
			"short_result": item.resize(WorkerBatch.ResultSlot.SIZE-1)
			"extra_result": item.append(null)
			"observation_slot_type": item[WorkerBatch.ResultSlot.OBSERVATION] = []
			"coverage_slot_type": item[WorkerBatch.ResultSlot.COVERAGE] = []
			"observation_field_type":
				var observation: Dictionary = item[WorkerBatch.ResultSlot.OBSERVATION]
				observation.value = "invalid"
			"missing_raw_marker":
				observed.erase("_worker_sample_raw")
				observed._worker_sample_water = []
			"false_raw_marker": observed._worker_sample_raw = false
			"raw_without_water":
				observed._worker_sample_raw = true
				observed.erase("_worker_sample_water")
			"finished_water", "finished_unclamped", "finished_moisture":
				for field: String in ["_worker_sample_raw","_worker_sample_water","_worker_sample_moisture","_worker_sample_water_distances"]: observed.erase(field)
				if corruption=="finished_water": observed.water = true
				elif corruption=="finished_unclamped": observed.value = 101
				else: observed._worker_sample_moisture = {}

class CustomEnvironment extends HospitalEnvironment:
	var sample_calls: int = 0
	func sample_at(world: WorldState, floor_id: int, cell: Array, actor_id: String = "") -> Dictionary:
		sample_calls += 1
		return super.sample_at(world,floor_id,cell,actor_id)

class CustomSpace extends HospitalSpace:
	var owned_calls: int = 0
	func owned(world: WorldState, floor_id: int, cell: Vector2i) -> bool:
		owned_calls += 1
		return super.owned(world,floor_id,cell)

func run(suite: RefCounted, content: HospitalContent) -> Dictionary:
	var checks: Dictionary = {}
	var rows: Array = []
	var empty: Dictionary = _seed(suite,content,0)
	var one: Dictionary = _seed(suite,content,1)
	var many: Dictionary = _seed(suite,content,4)
	for input: Dictionary in [empty,one,many]:
		if not str(input.validation).is_empty():
			return {"ok":false,"failure_kind":"fixture","prerequisite":input.name,"reason":input.validation,"admissions":input.get("admissions",[])}
		var row: Dictionary = _sample_pair(input,content,false,false,false)
		rows.append(row)
		checks["base_"+str(input.name)] = row.ok
	var inline_repeat: Dictionary = _sample_pair(many,content,false,false,false,false,1,2)
	rows.append(inline_repeat)
	checks.single_task_multiple_requests_reuses_batch = inline_repeat.ok
	var inline_missing: Dictionary = _sample_pair(one,content,false,false,true)
	rows.append(inline_missing)
	checks.single_task_missing_slot_preserves_fallback = inline_missing.ok
	var no_diagnostics: Dictionary = _sample_pair(one,content,false,false,false,false,4,2,false)
	rows.append(no_diagnostics)
	checks.single_task_without_diagnostics_reuses_batch = no_diagnostics.ok
	var nested: Dictionary = _sample_pair(many,content,true,false,false)
	rows.append(nested)
	checks.original_query_nesting_and_cache_order = nested.ok
	var budget: Dictionary = _sample_pair(many,content,false,false,false,false,1,1,true,true)
	rows.append(budget)
	checks.seed_handoff_preserves_coverage_budget_and_order = budget.ok
	var seed_reuse: Dictionary = _seed_reuse(many,content)
	checks.seed_reuse_across_worlds_and_request_sets = seed_reuse.ok
	var seed_contract: Dictionary = _seed_contract(many,content)
	checks.readonly_seed_and_cache_lookup_contract = seed_contract.ok
	var missing: Dictionary = _sample_pair(many,content,false,false,true)
	rows.append(missing)
	checks.missing_slot_falls_back_before_experience = missing.ok
	for task_count: int in [1,4]:
		for corruption: String in ["result_dictionary","short_result","extra_result","observation_slot_type","coverage_slot_type","observation_field_type","missing_raw_marker","false_raw_marker","raw_without_water","finished_water","finished_unclamped","finished_moisture"]:
			var malformed: Dictionary = _sample_pair(many,content,false,false,false,false,task_count,2 if corruption=="coverage_slot_type" else 1,true,false,corruption)
			rows.append(malformed)
			checks["malformed_"+corruption+"_tasks_"+str(task_count)] = malformed.ok
	var custom: Dictionary = _sample_pair(one,content,false,true,false)
	rows.append(custom)
	checks.custom_override_stays_serial = custom.ok
	var custom_space: Dictionary = _sample_pair(one,content,false,false,false,true)
	rows.append(custom_space)
	checks.custom_space_stays_serial = custom_space.ok
	var water: Dictionary = _water_inputs(suite,content)
	checks.water_candidates_and_live_permission = water.ok
	var numeric: Dictionary = _numeric_finish(empty.facts,content)
	checks.unclamped_numeric_finish = numeric.ok
	var finished: Dictionary = _no_water_finish(empty.facts,content)
	checks.no_water_finishes_on_worker = finished.ok
	var owned_projection: Dictionary = preload("res://tests/acceptance/environment_owned_projection.gd").new().run(content)
	checks.owned_projection = owned_projection.ok
	return {"ok":not checks.values().has(false),"checks":checks,"sample_pairs":rows,
		"water":water,"numeric_finish_only":numeric,"no_water_finish":finished,"owned_projection":owned_projection,"seed_reuse":seed_reuse,"seed_cache_contract":seed_contract,"not_covered":["cross-floor Worker requests","outside-owned Worker requests"],
		"scope":"Real base Department.sample uses the original serial switch as oracle. Numeric finish checks are calculation inputs, not simulated travel or patient relocation."}

func _bind(facts: Dictionary, content: HospitalContent) -> Dictionary:
	var world: WorldState = WorldState.new(facts.duplicate(true))
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	return {"world":world,"simulation":simulation,"space":simulation.space,"clinic":simulation.clinic,
		"arrivals":simulation.services.arrivals,"environment":simulation.services.environment,"departments":simulation.services.departments}

func _seed(suite: RefCounted, content: HospitalContent, count: int) -> Dictionary:
	var original: Dictionary = suite._context()
	# Staff exists before rebinding, so normal service initialization supplies
	# the complete staff facts. Staff-day accumulation is not vacuous.
	HospitalFactory._add_staff(original.world,"worker_check_staff","采样职员","cleaner",[36,90],content)
	original.world.touch()
	var x: Dictionary = _bind(original.world.freeze(),content)
	if original.has("simulation") and original.simulation!=null:
		original.simulation.dispose()
	var ids: Array = []
	var admissions: Array = []
	for index: int in count:
		var visit: Dictionary = suite._patient(x,[[44,80],[46,80],[48,80],[45,83]][index])
		admissions.append(x.get("last_admission",{}).duplicate(true))
		if visit.is_empty():
			var failed: Dictionary = {"facts":x.world.freeze(),"ids":ids,"validation":"合法患者前提未生成完整请求数","name":"count_"+str(count),"admissions":admissions}
			x.simulation.dispose()
			return failed
		ids.append(str(visit.id))
	suite._add_facility(x.world,"worker_check_plant","FUR25",null,[42,79])
	suite._add_facility(x.world,"worker_check_light","FUR19",null,[42,82])
	x.world.facts.sim_tick = 1200
	x.departments.ensure(x.world)
	for id: String in ids:
		var visit: Dictionary = x.world.facts.visits[id]
		var data: Dictionary = x.world.facts.departments.experience[id]
		data.phase = "arrival"
		data.phase_started_tick = 0
		data.next_anger_tick = 0
		data.cause_clocks = {"no_compatible_seat":0}
		x.world.facts.tickets[visit.ticket_id].waited_ticks = 1200
	x.world.touch()
	var validation: String = x.world.validate(content)
	if ids.size()!=count: validation = "合法患者前提未生成完整请求数"
	var result: Dictionary = {"facts":x.world.freeze(),"ids":ids,"validation":validation,"name":"count_"+str(count),"admissions":admissions}
	x.simulation.dispose()
	return result

func _cache_view(environment: HospitalEnvironment) -> Array:
	var result: Array = []
	for floor_id: int in environment._coverage_cache:
		var entry: Dictionary = environment._coverage_cache[floor_id]
		var coverage: Dictionary = entry.get("coverage",{})
		result.append([floor_id,coverage.keys(),coverage.duplicate(true)])
	return result

func _changed_fact_keys(before: Dictionary, after: Dictionary) -> Array:
	var keys: Array = before.keys()
	for key: String in after:
		if not before.has(key): keys.append(key)
	var result: Array = []
	for key: String in keys:
		if before.has(key)!=after.has(key) or before.get(key)!=after.get(key): result.append(key)
	return result

func _sample_pair(input: Dictionary, content: HospitalContent, nested: bool, custom: bool, missing: bool, custom_space: bool = false, task_count: int = 4, repetitions: int = 1, diagnostics: bool = true, warm_budget: bool = false, malformed: String = "") -> Dictionary:
	var serial: Dictionary = _bind(input.facts,content)
	var parallel: Dictionary = _bind(input.facts,content)
	if custom:
		for x: Dictionary in [serial,parallel]:
			var observer: CustomEnvironment = CustomEnvironment.new(content,x.space)
			observer.waiting_life = x.simulation.services.waiting
			x.environment = observer
			x.departments.environment = observer
			x.simulation.services.waiting.environment = observer
	if custom_space:
		for x: Dictionary in [serial,parallel]:
			var geometry: CustomSpace = CustomSpace.new(content)
			var observer: HospitalEnvironment = HospitalEnvironment.new(content,geometry)
			observer.waiting_life = x.simulation.services.waiting
			x.environment = observer
			x.departments.environment = observer
			x.simulation.services.waiting.environment = observer
	var defaults: bool = bool(parallel.departments.sample_workers_enabled) and int(parallel.departments.sample_worker_tasks)==4
	serial.departments.sample_workers_enabled = false
	parallel.departments.sample_worker_diagnostics = diagnostics
	parallel.departments.sample_worker_tasks = task_count
	if missing: parallel.departments._worker_sample_batch = MissingSlotBatch.new()
	if warm_budget:
		for x: Dictionary in [serial,parallel]: _warm_coverage_budget(x)
	if not malformed.is_empty():
		var broken: MalformedSlotBatch = MalformedSlotBatch.new()
		broken.corruption = malformed
		parallel.departments._worker_sample_batch = broken
	var before: Dictionary = serial.world.freeze()
	var nesting: bool = true
	if nested:
		for x: Dictionary in [serial,parallel]:
			x.environment.begin_query(x.world)
			x.environment.begin_query(x.world)
			if not input.ids.is_empty():
				var actor: Dictionary = x.world.facts.actors[x.world.facts.visits[input.ids[0]].actor_id]
				x.environment.sample_at(x.world,int(actor.location.floor_id),actor.location.cell,str(actor.id))
	for repetition: int in repetitions:
		for x: Dictionary in [serial,parallel]: x.departments.sample(x.world)
	if nested:
		nesting = serial.environment._query_depth==2 and parallel.environment._query_depth==2
		for x: Dictionary in [serial,parallel]:
			x.environment.end_query()
			x.environment.end_query()
	var report: Dictionary = parallel.departments.sample_worker_report()
	var requested: int = input.ids.size()
	var owned_fast: int = 0
	var owned_fallback: int = 0
	for job: Dictionary in report.get("last_batch",{}).get("jobs",[]):
		owned_fast += int(job.get("owned_fast_checks",0))
		owned_fallback += int(job.get("owned_fallback_checks",0))
	var owned_witness: bool = true
	if not custom and not custom_space and requested>0:
		if diagnostics:
			owned_witness = owned_fast+owned_fallback==requested
			owned_witness = owned_witness and (owned_fast>0 if parallel.world.facts.floors.has("completed_top_floor") else owned_fast==0 and owned_fallback==requested)
		else: owned_witness = owned_fast==0 and owned_fallback==0
	var execution: bool
	if custom or custom_space or requested==0:
		execution = int(report.batches)==0 and int(report.processed)==0 and int(report.consumed)==0
	elif missing or not malformed.is_empty():
		execution = int(report.batches)==repetitions and int(report.failed_batches)==repetitions and int(report.processed)==requested*repetitions and int(report.consumed)==0
	else:
		execution = int(report.batches)==repetitions and int(report.failed_batches)==0 and int(report.processed)==requested*repetitions and int(report.consumed)==requested*repetitions and bool(report.last_batch.get("all_results_consumed",false))
	if not custom and not custom_space and requested>0:
		var inline_job: bool = mini(maxi(1,task_count),requested)==1
		execution = execution and report.last_batch.jobs.size()==mini(4,mini(maxi(1,task_count),requested))
		execution = execution and (int(report.last_batch.group_id)==-1 if inline_job else int(report.last_batch.group_id)>=0)
		for job: Dictionary in report.last_batch.jobs:
			execution = execution and int(job.thread_id)!=0 and ((int(job.thread_id)==OS.get_main_thread_id())==inline_job)
	var equal: bool = serial.world.freeze()==parallel.world.freeze()
	var rng: bool = serial.world.facts.rng==before.rng and parallel.world.facts.rng==before.rng
	var cache_equal: bool = _cache_view(serial.environment)==_cache_view(parallel.environment)
	var budget: bool = not warm_budget or serial.environment._coverage_cache[1].coverage.size()==128 and parallel.environment._coverage_cache[1].coverage.size()==128
	var seed_released: bool = parallel.departments._worker_sample_batch==null or _seed_released(parallel.departments._worker_sample_batch)
	var scopes: bool = serial.environment._query.is_empty() and parallel.environment._query.is_empty() and serial.environment._query_depth==0 and parallel.environment._query_depth==0 and serial.space._route_queries.is_empty() and parallel.space._route_queries.is_empty()
	var staff_days: bool = not parallel.world.facts.departments.staff_days.is_empty()
	var overrides: bool = not custom or int(parallel.environment.sample_calls)==requested and int(serial.environment.sample_calls)==requested
	var space_override: bool = not custom_space or int(parallel.environment.space.owned_calls)>0 and int(serial.environment.space.owned_calls)>0
	var valid: String = parallel.world.validate(content)
	var row: Dictionary = {"name":input.name,"task_count":task_count,"repetitions":repetitions,"diagnostics":diagnostics,"nested":nested,"custom":custom,"custom_space":custom_space,"missing_slot":missing,"warm_coverage_budget":warm_budget,"malformed_result":malformed,
		"ok":input.validation.is_empty() and valid.is_empty() and defaults and execution and equal and rng and cache_equal and budget and seed_released and scopes and staff_days and overrides and space_override and nesting and owned_witness,
		"input_validation":input.validation,"output_validation":valid,"real_worker_execution_or_expected_fallback":execution,
		"default_workers_enabled_with_four_tasks":defaults,
		"owned_branch_witness":owned_witness,"owned_fast_checks":owned_fast,"owned_fallback_checks":owned_fallback,
		"complete_facts_equal_including_experience_anger_details_staff_days":equal,"rng_unchanged":rng,
		"retained_coverage_order_and_values_equal":cache_equal,"coverage_budget_preserved":budget,"seed_borrow_released":seed_released,"scopes_closed":scopes,"staff_days_present":staff_days,"nested_depth_preserved":nesting,"override_calls_preserved":overrides,"custom_space_owned_called":space_override,"worker_report":report}
	for x: Dictionary in [serial,parallel]:
		if custom or custom_space: x.environment.waiting_life = null
		x.simulation.dispose()
	return row

func _observation_pair(input: Dictionary, content: HospitalContent, shared_batch: RefCounted = null, warm_query: bool = false) -> Dictionary:
	var serial: Dictionary = _bind(input.facts,content)
	var parallel: Dictionary = _bind(input.facts,content)
	# Binding completes service facts before the read-only observation boundary.
	# Both prewarming and the batch itself remain inside the checked interval.
	var serial_before: Dictionary = serial.world.freeze()
	var parallel_before: Dictionary = parallel.world.freeze()
	serial.environment.begin_query(serial.world)
	parallel.environment.begin_query(parallel.world)
	if warm_query and not input.ids.is_empty():
		for x: Dictionary in [serial,parallel]:
			var actor: Dictionary = x.world.facts.actors[x.world.facts.visits[input.ids[0]].actor_id]
			x.environment.sample_at(x.world,int(actor.location.floor_id),actor.location.cell,str(actor.id))
	var batch: RefCounted = shared_batch if shared_batch!=null else WorkerBatch.new()
	var prepared: bool = batch.prepare(parallel.world,parallel.environment,input.ids,4,true)
	var rows: Array = []
	var ok: bool = prepared==(not input.ids.is_empty())
	if prepared:
		batch.begin_apply()
		for visit_id: String in input.ids:
			var actor: Dictionary = serial.world.facts.actors[serial.world.facts.visits[visit_id].actor_id]
			var raw: Dictionary = batch._observations[visit_id][WorkerBatch.ResultSlot.OBSERVATION]
			var candidates: Array = raw.get("_worker_sample_water",[]).duplicate()
			var expected: Dictionary = serial.environment.sample_at(serial.world,int(actor.location.floor_id),actor.location.cell,str(actor.id))
			var actual: Dictionary = batch.consume(parallel.world,parallel.environment,visit_id,str(actor.id))
			var equal: bool = expected==actual
			ok = ok and equal
			rows.append({"visit_id":visit_id,"equal":equal,"water_candidates":candidates,"expected":expected,"actual":actual})
		batch.end_apply(parallel.environment)
	serial.environment.end_query()
	parallel.environment.end_query()
	var serial_after: Dictionary = serial.world.freeze()
	var parallel_after: Dictionary = parallel.world.freeze()
	var readonly: bool = serial_after==serial_before and parallel_after==parallel_before
	var complete_equal: bool = serial_after==parallel_after
	ok = ok and readonly and complete_equal and _cache_view(serial.environment)==_cache_view(parallel.environment)
	var result: Dictionary = {"ok":ok,"name":input.name,"observations":rows,"queries_readonly":readonly,"complete_bound_facts_equal":complete_equal,
		"binding_fact_changes":{"serial":_changed_fact_keys(input.facts,serial_before),"worker":_changed_fact_keys(input.facts,parallel_before)},"worker_report":batch.report()}
	serial.simulation.dispose()
	parallel.simulation.dispose()
	return result

func _warm_coverage_budget(x: Dictionary) -> void:
	x.environment.begin_query(x.world)
	var edges: Dictionary = x.environment._coverage_edges(x.world,1)
	for index: int in 128: x.environment._coverage(x.world,1,[33+index%28,65+index/28],1,false,edges)
	x.environment.end_query()

func _seed_released(batch: RefCounted) -> bool:
	for job: RefCounted in batch._jobs:
		if job.world!=null or not job.environment.coverage_seed.is_empty() or not job.environment._coverage_cache.is_empty() or not job.environment._query.is_empty(): return false
	return true

func _seed_reuse(input: Dictionary, content: HospitalContent) -> Dictionary:
	# Each input is a legal saved world immediately before read-only sampling.
	# The changed blocker is an input geometry fact, not a completed move.
	var first: Dictionary = input.duplicate(true)
	first.name = "seed_world_a_four_requests"
	var changed: Dictionary = input.duplicate(true)
	changed.name = "seed_world_b_one_request_changed_geometry"
	changed.ids = [input.ids[0]]
	changed.facts.floors.overrides["1"].blocked.append([43,80])
	var empty: Dictionary = changed.duplicate(true)
	empty.name = "seed_world_b_zero_requests"
	empty.ids = []
	var restored: Dictionary = input.duplicate(true)
	restored.name = "seed_world_a_three_requests_reversed"
	restored.ids.reverse()
	restored.ids = restored.ids.slice(0,3)
	var batch: RefCounted = WorkerBatch.new()
	var rows: Array = []
	var ok: bool = true
	for state: Dictionary in [first,changed,empty,restored]:
		var validation: String = WorldState.new(state.facts.duplicate(true)).validate(content)
		if not validation.is_empty(): return {"ok":false,"failure_kind":"fixture","prerequisite":state.name,"reason":validation}
		var row: Dictionary = _observation_pair(state,content,batch,true)
		row.seed_borrow_released = _seed_released(batch)
		row.ok = row.ok and row.seed_borrow_released
		ok = ok and row.ok
		rows.append(row)
	return {"ok":ok,"observations":rows,"scope":"Legal current-world observations only, with one reused helper across fresh WorldState instances and 4/1/0/3 request sets. No movement or service completion is asserted."}

func _seed_contract(input: Dictionary, content: HospitalContent) -> Dictionary:
	# Deliberately different cache payloads test mapping precedence and empty-hit
	# semantics. They are not asserted to be geometric coverage results.
	var x: Dictionary = _bind(input.facts,content)
	var before: Dictionary = x.world.freeze()
	x.environment.begin_query(x.world)
	x.environment._prepare_facility_sources(x.world)
	x.environment._prepare_sample_sources(x.world)
	var edges: Dictionary = x.environment._coverage_edges(x.world,1)
	var retained: Dictionary = {"persistent":0}
	var current: Dictionary = {"query":0}
	var empty: Dictionary = {}
	var empty_key: String = "1:40:70:1:0"
	x.environment._coverage_cache[1].coverage = {"priority":retained,empty_key:empty}
	x.environment._query.coverage = {1:{"priority":current}}
	var cache_before: Array = _cache_view(x.environment)
	var query_before: Dictionary = x.environment._query.coverage.duplicate(true)
	var query_keys: Array = x.environment._query.coverage[1].keys()
	var batch: SeedInspectionBatch = SeedInspectionBatch.new()
	var prepared: bool = batch.prepare(x.world,x.environment,input.ids,4,true)
	var checks: Dictionary = {"batch_prepared":prepared,"source_cache_unchanged_before_apply":_cache_view(x.environment)==cache_before,
		"source_query_unchanged_before_apply":x.environment._query.coverage==query_before and x.environment._query.coverage[1].keys()==query_keys,
		"source_mappings_and_payloads_not_frozen":not x.environment._coverage_cache[1].coverage.is_read_only() and not x.environment._query.coverage[1].is_read_only() and not empty.is_read_only() and not current.is_read_only(),
		"main_empty_hit_and_null_miss":is_same(x.environment._cached_coverage(1,empty_key),empty) and x.environment._cached_coverage(1,"absent")==null,
		"borrow_released":_seed_released(batch)}
	if prepared and batch.captured_seed.has(1):
		var seed: Dictionary = batch.captured_seed
		checks.seed_shared_and_three_mapping_levels_readonly = batch.shared_seed and seed.is_read_only() and seed[1].is_read_only() and seed[1].coverage.is_read_only()
		checks.current_query_overrides_persistent_seed = is_same(seed[1].coverage.priority,current) and is_same(seed[1].coverage[empty_key],empty)
		var worker: RefCounted = WorkerBatch.WorkerEnvironment.new(content,HospitalSpace.new(content))
		worker.coverage_seed = seed
		worker.begin_query(x.world)
		worker._query.edges[1] = edges
		var found: Dictionary = worker._coverage(x.world,1,[40,70],1,false,edges)
		checks.empty_seed_hit_recorded_in_current_request = is_same(found,empty) and worker._query.coverage[1].has(empty_key) and is_same(worker._query.coverage[1][empty_key],empty) and worker.space.query_counts.get("environment_coverage_native_calls",0)==0 and worker.space.query_counts.get("environment_coverage_fallbacks",0)==0
		var overlay: Dictionary = {}
		worker._coverage_cache = {1:{"coverage":{"priority":overlay}}}
		checks.private_overlay_precedes_seed = is_same(worker._cached_coverage(1,"priority"),overlay) and is_same(seed[1].coverage.priority,current)
		worker._coverage_cache = {}
		worker._query.coverage = {}
		worker._query.edges = {}
		worker._coverage_edges(x.world,1)
		checks.rebuilt_private_floor_does_not_read_old_seed = worker._coverage_cache[1].has("source") and worker._cached_coverage(1,"priority")==null
		worker.end_query()
		batch.begin_apply()
		for visit_id: String in input.ids:
			batch.consume(x.world,x.environment,visit_id,str(x.world.facts.visits[visit_id].actor_id))
		batch.end_apply(x.environment)
	else:
		checks.seed_present = false
	x.environment.end_query()
	checks.world_readonly = x.world.freeze()==before
	x.simulation.dispose()
	return {"ok":not checks.values().has(false),"checks":checks,"scope":"Internal cache mapping and borrowing contract only. Artificial priority/empty payloads do not define valid environment geometry or business results; the 128-entry budget uses separate real coverage queries."}

func _water_inputs(suite: RefCounted, content: HospitalContent) -> Dictionary:
	var seed: Dictionary = _seed(suite,content,2)
	if not str(seed.validation).is_empty() or seed.ids.size()!=2:
		return {"ok":false,"failure_kind":"fixture","prerequisite":"water_two_patients","reason":seed.validation,"admissions":seed.get("admissions",[])}
	var x: Dictionary = _bind(seed.facts,content)
	var subject: Dictionary = x.world.facts.actors[x.world.facts.visits[seed.ids[0]].actor_id]
	var peer: Dictionary = x.world.facts.actors[x.world.facts.visits[seed.ids[1]].actor_id]
	subject.location.cell = [48,80]
	peer.location.cell = [44,80]
	suite._add_facility(x.world,"worker_water_a","FUR17",null,[50,80])
	suite._add_facility(x.world,"worker_water_b","FUR17",null,[52,80])
	var rows: Array = []
	var checks: Dictionary = {}
	var input: Dictionary = {"ids":[seed.ids[0]],"name":"two_water_candidates"}
	input.facts = x.world.freeze()
	var available: Dictionary = _observation_pair(input,content)
	rows.append(available)
	checks.available = available.ok and available.observations.size()==1 and bool(available.observations[0].actual.water) and available.observations[0].water_candidates.size()==2
	peer.location.cell = x.space.facility_layout(x.world,"worker_water_a").patient_cell.duplicate()
	x.world.touch()
	input.facts = x.world.freeze()
	input.name = "current_body_at_first_water"
	var body: Dictionary = _observation_pair(input,content)
	rows.append(body)
	checks.current_body_uses_live_original_water_predicate = body.ok and not x.environment._water_usable(x.world,x.world.facts.facilities.worker_water_a,str(subject.id))
	peer.location.cell = [44,80]
	x.world.facts.facilities.worker_water_a.failed = true
	x.world.facts.facilities.worker_water_b.failed = true
	x.world.touch()
	input.facts = x.world.freeze()
	input.name = "failed_sources_contribute_no_water"
	var failed: Dictionary = _observation_pair(input,content)
	rows.append(failed)
	checks.both_failed = failed.ok and not bool(failed.observations[0].actual.water) and failed.observations[0].water_candidates.is_empty()
	x.world.facts.facilities.worker_water_a.failed = false
	var reserved: String = x.space.reserve_facility(x.world,"worker_water_a",str(peer.id),str(peer.id))
	checks.real_reservation_created = reserved.is_empty() and x.world.facts.adaptations.has("worker_water_a")
	if checks.real_reservation_created:
		for permission: bool in [false,true,false]:
			if permission:
				x.space.grant_facility_access(x.world,"worker_water_a",str(subject.id))
			else:
				x.world.facts.adaptations.worker_water_a.staff_ids.erase(subject.id)
				x.space.reservation_changed(x.world,"worker_water_a")
				x.space._navigation.invalidate(x.world,1)
			input.facts = x.world.freeze()
			input.name = "current_reservation_permission_"+str(permission)
			var observed: Dictionary = _observation_pair(input,content)
			rows.append(observed)
			checks["permission_boundary_"+str(rows.size())] = observed.ok and (subject.id in x.world.facts.adaptations.worker_water_a.staff_ids)==permission
	var validation: String = x.world.validate(content)
	x.simulation.dispose()
	return {"ok":seed.validation.is_empty() and validation.is_empty() and not checks.values().has(false),"checks":checks,"observations":rows,"validation":validation,"scope":"Access grant changes current reservation permission; it does not grant business ownership or bypass the original water predicate."}

func _numeric_finish(facts: Dictionary, content: HospitalContent) -> Dictionary:
	var x: Dictionary = _bind(facts,content)
	var worker: RefCounted = WorkerBatch.WorkerEnvironment.new(content,HospitalSpace.new(content))
	var rows: Array = []
	var ok: bool = true
	for point: Array in [[110,15],[110,20],[1,10],[102,0]]:
		var input: Dictionary = {"value":int(point[0]),"noise":int(point[1]),"water":false}
		var expected_input: Dictionary = input.duplicate(true)
		expected_input.water = true
		expected_input.value += int(content.balance.environment.water_bonus)
		var expected: Dictionary = x.environment._finish_observation(expected_input)
		# Select the deferred path as a calculation input, then start the
		# numeric boundary after the successful live permission decision.
		worker.water_candidates.clear()
		worker.water_candidates.append("numeric_boundary")
		var raw: Dictionary = worker._finish_observation(input)
		var deferred: bool = raw.get("_worker_sample_raw",false)==true and raw.value==int(point[0])-int(point[1])
		raw._worker_sample_water = []
		# Numeric finishing begins after an already successful main-thread water
		# decision. This is not a fabricated source or a legal-world flow claim.
		raw.water = true
		var batch: RefCounted = WorkerBatch.new()
		batch._last = {"consumed":0}
		var item: Array = []
		item.resize(WorkerBatch.ResultSlot.SIZE)
		item[WorkerBatch.ResultSlot.OBSERVATION] = raw
		item[WorkerBatch.ResultSlot.COVERAGE] = {}
		batch._observations = {"numeric":item}
		var actual: Dictionary = batch.consume(x.world,x.environment,"numeric","")
		var equal: bool = actual==expected and deferred
		ok = ok and equal
		rows.append({"before_noise":point[0],"noise":point[1],"expected":expected,"actual":actual,"equal":equal})
	x.simulation.dispose()
	return {"ok":ok,"rows":rows,"scope":"Numeric function boundaries only; these raw totals are not asserted to arise from the authored legal hospital."}

func _no_water_finish(facts: Dictionary, content: HospitalContent) -> Dictionary:
	var x: Dictionary = _bind(facts,content)
	var before: Dictionary = x.world.freeze()
	var worker: RefCounted = WorkerBatch.WorkerEnvironment.new(content,HospitalSpace.new(content))
	var rows: Array = []
	var ok: bool = true
	for point: Array in [[110,15,95,"moist"],[110,20,90,"moist"],[1,10,0,"moist"],[102,0,100,"moist"],[-3,0,0,"moist"],[110,15,95,"dry"],[102,0,100,"dry"]]:
		var input: Dictionary = {"value":point[0],"noise":point[1],"water":false,"quiet":false,"clean":true,"dirt":0,"moist":false,"dry":false,"light":false,"cool":false,"status":""}
		var expected: Dictionary = input.duplicate(true)
		expected.value = point[2]
		expected.quiet = int(point[1])==0
		expected[str(point[3])] = true
		expected.status = "current"
		worker._finish_preference_sources(input,{"id":"calculation_source","distance":2,"preference":point[3]},{})
		var observation: Dictionary = worker._finish_observation(input)
		var ready: bool = true
		for field: String in ["_worker_sample_raw","_worker_sample_water","_worker_sample_moisture","_worker_sample_water_distances"]: ready = ready and not observation.has(field)
		var batch: RefCounted = WorkerBatch.new()
		batch._last = {"consumed":0}
		batch._observations = {"finished":[observation,{}]}
		var actual: Dictionary = batch.consume(x.world,x.environment,"finished","")
		var equal: bool = ready and actual==expected and x.world.freeze()==before
		ok = ok and equal
		rows.append({"raw_value":point[0],"noise":point[1],"expected":expected,"actual":actual,"finished_without_temporary_fields":ready,"equal":equal})
	x.simulation.dispose()
	return {"ok":ok,"rows":rows,"scope":"Independent arithmetic and moisture-signal calculation inputs only. No facility permission, placement or movement is asserted here."}
