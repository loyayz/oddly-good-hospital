extends SceneTree

const Population = preload("res://tools/performance/acceptance/fixtures/prepare_inputs.gd")
var _content: HospitalContent

func _initialize() -> void: call_deferred("_run")

func _bind(facts: Dictionary, script: GDScript) -> Dictionary:
	var world: WorldState = WorldState.new(facts.duplicate(true))
	var sim: HospitalSimulation = HospitalSimulation.new(world,_content)
	sim.services.experience.ensure(world)
	sim.prepare_floor_static(1)
	return {"world":world,"sim":sim,"source":sim.services.environment,"batch":script.new(),"before":world.freeze()}

func _distinct(values: Array) -> int:
	var unique: Array = []
	for value: Variant in values:
		if not unique.any(func(previous: Variant)->bool:return is_same(previous,value)): unique.append(value)
	return unique.size()

func _containers(batch: RefCounted) -> Dictionary:
	var observations: Array = [];var sources: Array = [];var results: Array = [];var coverage: Array = [];var empty: Array = []
	for item: Array in batch._observations.values():
		results.append(item);observations.append(item[0]);sources.append(item[0].sources);coverage.append(item[1])
		if item[1].is_empty(): empty.append(item[1])
	var seed: Dictionary = batch._prepare_probe_seed
	var seed_maps: Array = [seed];var keys: int = 0
	for entry: Dictionary in seed.values():
		seed_maps.append(entry);seed_maps.append(entry.coverage);keys += entry.coverage.size()
	return {"observations":_distinct(observations),"sources_arrays":_distinct(sources),"result_arrays":_distinct(results),"result_coverage_maps":_distinct(coverage),"empty_result_coverage_maps":_distinct(empty),"seed_floors":seed.size(),"seed_entries":keys,"seed_maps":_distinct(seed_maps),"allocated_jobs":batch._jobs.size(),"scope":"Distinct reachable containers observed by identity before consume; seed entries count actual keys. Not total allocator calls, process allocations, bytes, or GC time. Borrowed coverage values inside seed entries are excluded."}

func _call(x: Dictionary, counted: bool = false) -> Dictionary:
	var world: WorldState = x.world;var source: HospitalEnvironment = x.source;var batch: RefCounted = x.batch
	var ids: Array = world.active_visit_ids()
	x.sim.space.begin_route_query(world,{},false);source.begin_query(world)
	var started: int = Time.get_ticks_usec()
	var prepared: bool = batch.prepare(world,source,ids,4,false)
	var elapsed: int = Time.get_ticks_usec()-started
	var counts: Dictionary = _containers(batch) if counted else {}
	var observations: Dictionary = {}
	if prepared:
		batch.begin_apply()
		for id: String in ids:
			if batch._observations.has(id): observations[id]=batch.consume(world,source,id,str(world.facts.visits[id].actor_id))
		batch.end_apply(source)
	source.end_query();x.sim.space.end_route_query()
	var last: Dictionary = batch._last
	var worker_requests: int = 0
	for job: Dictionary in last.jobs: worker_requests += int(job.requested)
	counts.merge({"requested":int(last.requested),"worker_requests":worker_requests,"main_empty":int(last.get("main_empty_observations",0)),"jobs":last.jobs.size(),"consumed":int(last.consumed)})
	return {"ok":prepared and last.ok and int(last.consumed)==int(last.requested) and x.sim.space._route_queries.is_empty() and source._query_depth==0,"prepare_us":elapsed,"observations":observations,"counts":counts}

func _statistics(values: Array) -> Dictionary:
	var ordered: Array = values.duplicate();ordered.sort();var total: int = 0
	for value: int in values: total += value
	return {"calls":values.size(),"total_us":total,"mean_us":float(total)/values.size(),"p50_us":ordered[ceili(values.size()*0.5)-1],"p95_us":ordered[ceili(values.size()*0.95)-1],"max_us":ordered.back()}

func _finish(x: Dictionary) -> Dictionary:
	var result: Dictionary = {"facts_unchanged":x.before==x.world.freeze(),"validation":x.world.validate(_content),"population":Population.population_of(x.world),"batch":x.batch.report()}
	x.sim.dispose()
	return result

func _run() -> void:
	var input: String = "";var output: String = "";var iterations: int = 200;var warmup: int = 10
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--input="): input=arg.trim_prefix("--input=")
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg.begins_with("--iterations="): iterations=arg.trim_prefix("--iterations=").to_int()
		if arg.begins_with("--warmup="): warmup=arg.trim_prefix("--warmup=").to_int()
	if input.is_empty() or output.is_empty() or iterations<1 or warmup<1 or FileAccess.file_exists(output): quit(2);return
	var policy: Dictionary = {"applied":false,"reason":"native_policy_unavailable"}
	if ClassDB.class_exists("PlatformThreadPolicy"): policy=ClassDB.class_call_static("PlatformThreadPolicy","apply_main_thread")
	_content=HospitalContent.new()
	var file: FileAccess = FileAccess.open(input,FileAccess.READ);var envelope: Dictionary = file.get_var(false);file.close()
	if envelope.content_fingerprint!=_content.content_fingerprint: quit(2);return
	var original: WorldState = WorldState.new(envelope.facts)
	var input_validation: String = original.validate(_content)
	if not input_validation.is_empty(): push_error(input_validation);quit(2);return
	if envelope.get("scenario","")!="comprehensive160-clinical-family-v3" or int(Population.population_of(original).present)!=160:
		push_error("The local pair requires the unchanged real comprehensive 160-person input");quit(2);return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/performance/prepared_experience_sample/manifest.json"))
	if FileAccess.get_sha256("res://"+str(manifest.original_source))!=str(manifest.original_sha256.b): quit(2);return
	for path: String in manifest.source:
		if FileAccess.get_sha256("res://"+path)!=str(manifest.source[path].sha256): quit(2);return
	var scripts: Dictionary = {}
	for key: String in manifest.scripts: scripts[key]=load(manifest.scripts[key])
	var ok: bool = true;var rounds: Array = []
	for repeat: int in 3:
		var pair: Dictionary = {"a":_bind(envelope.facts,scripts.a),"b":_bind(envelope.facts,scripts.b)}
		var order: Array = ["a","b"] if repeat%2==0 else ["b","a"]
		var times: Dictionary = {"a":[],"b":[]};var counts: Dictionary = {};var equal: bool = true;var work_equal: bool = true
		for index: int in warmup+iterations:
			var observed: Dictionary = {}
			for key: String in order:
				var row: Dictionary = _call(pair[key]);ok=ok and row.ok;observed[key]=row.observations;counts[key]=row.counts
				if index>=warmup: times[key].append(row.prepare_us)
			equal=equal and observed.a==observed.b
			for field: String in ["requested","worker_requests","main_empty","jobs","consumed"]: work_equal=work_equal and counts.a[field]==counts.b[field]
		var endings: Dictionary = {"a":_finish(pair.a),"b":_finish(pair.b)}
		for end: Dictionary in endings.values(): ok=ok and end.facts_unchanged and str(end.validation).is_empty()
		ok=ok and equal and work_equal
		rounds.append({"repeat":repeat+1,"order":order,"observations_equal_every_call":equal,"work_equal_every_call":work_equal,"a":_statistics(times.a),"b":_statistics(times.b),"last_counts":counts,"endings":endings})
	var counted: Dictionary = {}
	for key: String in ["a","b"]:
		var x: Dictionary = _bind(envelope.facts,scripts[key+"_counted"])
		for index: int in warmup:
			var warm_row: Dictionary = _call(x);ok=ok and warm_row.ok
		var row: Dictionary = _call(x,true);var end: Dictionary = _finish(x)
		counted[key]={"counts":row.counts,"facts_unchanged":end.facts_unchanged,"validation":end.validation}
		ok=ok and row.ok and end.facts_unchanged and str(end.validation).is_empty()
	var result: Dictionary = {"ok":ok,"input":input,"input_sha256":FileAccess.get_sha256(input),"input_validation":input_validation,"input_population":Population.population_of(original),"input_tick":original.sim_tick,"boundary":"The unchanged real comprehensive input after Simulation initialization and experience.ensure; each pair owns fresh services and naturally warms on the identical facts, without advancing time or inventing cached origins.","main_thread_policy":policy,"worker_tasks":4,"iterations":iterations,"warmup":warmup,"rounds":rounds,"untimed_counted_calls":counted,"source":manifest,"scope":"Local EnvironmentSampleBatch.prepare elapsed, including actual worker dispatch and barrier; opening/closing query, consume, validation, counters and comparison are outside timing. Three fresh-service paired rounds in one engine process, alternating A/B order. Not Simulation.step, a 6000-step business coverage test, or a full160 performance pass."}
	file=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	quit(0 if ok else 1)
