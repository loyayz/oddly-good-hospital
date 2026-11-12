extends SceneTree

const Capture = preload("res://tools/performance/current/spatial_query_capture.gd")

func _initialize() -> void: call_deferred("run")

func _hash(value: Variant) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256); context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func _coordinates(rect: Rect2) -> Array:
	return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]

func _identity() -> Dictionary:
	var result: Dictionary = {"engine":OS.get_executable_path(),"engine_sha256":FileAccess.get_sha256(OS.get_executable_path())}
	for path: String in ["game/building/body_index.gd","game/platform/windows/platform_spatial_index.h","game/platform/windows/platform_arrivals.cpp","game/platform/windows/bin/oddly_good_platform.windows.x86_64.dll","tools/performance/current/spatial_query_probe.gd","tools/performance/current/spatial_query_capture.gd"]:
		result[path]=FileAccess.get_sha256("res://"+path)
	return result

func _capture(input: String, output: String, expected_sha: String) -> Dictionary:
	if not FileAccess.get_file_as_string("res://game/building/body_index.gd").contains("const SpatialCapture"):
		return {"ok":false,"error":"Install capture hooks in an isolated diagnostic project first"}
	if FileAccess.get_sha256(input)!=expected_sha: return {"ok":false,"error":"Input identity changed"}
	var file: FileAccess = FileAccess.open(input,FileAccess.READ)
	if file==null: return {"ok":false,"error":"Cannot read the complete input"}
	var envelope: Dictionary = file.get_var(false); file.close()
	var content: HospitalContent = HospitalContent.new()
	if envelope.get("content_fingerprint","")!=content.content_fingerprint: return {"ok":false,"error":"Content identity changed"}
	var world: WorldState = WorldState.new(envelope.facts)
	var validation: String = world.validate(content)
	if not validation.is_empty(): return {"ok":false,"error":validation}
	var header: Dictionary = {"input":input,"input_sha256":expected_sha,"identity":_identity(),"content_fingerprint":content.content_fingerprint,"facts":world.freeze(),"actor_records":world.facts.actors.size(),"present":world.present_actor_count(),"tick":world.sim_tick,"scope":"One actual fixed Simulation.step from the complete declared boundary. Every BodyIndex is registered before construction work; capture uses the original Array query API. Mutations, queries and original ordered IDs are retained without truncation. Diagnostic hooks are excluded from plain timing."}
	if not Capture.begin(output,header): return {"ok":false,"error":"Cannot start a fresh diagnostic stream"}
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	var tick: int = world.sim_tick
	var step: TickResult = simulation.step()
	var events: Array = []
	for event: SimEvent in step.facts: events.append({"kind":event.kind,"tick":event.sim_tick,"changed_ids":event.changed_ids,"details":event.details})
	var facts: Dictionary = world.freeze()
	var summary: Dictionary = Capture.finish({"start_tick":tick,"end_tick":world.sim_tick,"final_world_sha256":_hash(facts),"events":events,"events_sha256":_hash(events)})
	validation=world.validate(content); simulation.dispose()
	return {"ok":summary.errors.is_empty() and world.sim_tick==tick+1 and int(summary.counts.get("query",0))>0 and validation.is_empty(),"summary":summary,"world_validation":validation,"stream":output,"stream_sha256":FileAccess.get_sha256(output),"timed":false}

func _measure(batch: Array, before: bool, iterations: int) -> int:
	var _last: Array = []
	var started: int = Time.get_ticks_usec()
	if before:
		for repeat: int in iterations:
			for item: Array in batch:
				if not item[4]: _last=[]; continue
				var index: PlatformSpatialIndex = item[0]
				var rect: Rect2 = item[3]
				_last=index.query(int(item[2]),[rect.position.x,rect.position.y,rect.size.x,rect.size.y]).ids
	else:
		for repeat: int in iterations:
			for item: Array in batch:
				if not item[4]: _last=[]; continue
				var index: PlatformSpatialIndex = item[1]
				var rect: Rect2 = item[3]
				_last=index.query_rect(int(item[2]),rect).ids
	return Time.get_ticks_usec()-started

func _batch(batch: Array, pair: int, iterations: int, errors: Array, digest: HashingContext) -> Dictionary:
	for item: Array in batch:
		var old: PlatformSpatialIndex = item[0]
		var current: PlatformSpatialIndex = item[1]
		var rect: Rect2 = item[3]
		var expected: Array = item[5]
		var old_ids: Array = []
		var new_ids: Array = []
		if item[4]:
			old_ids=old.query(int(item[2]),_coordinates(rect)).ids
			new_ids=current.query_rect(int(item[2]),rect).ids
		if old_ids!=expected or new_ids!=expected: errors.append("Complete captured IDs or native order differ")
		digest.update(var_to_bytes([int(item[2]),item[3],old_ids,new_ids]))
	var result: Dictionary = {"before_us":0,"after_us":0}
	var order: Array[String] = ["before","after"]
	if pair%2!=0: order.reverse()
	if errors.is_empty():
		for side: String in order: result[side+"_us"]=_measure(batch,side=="before",iterations)
	return result

func _replay(input: String, iterations: int, expected_sha: String) -> Dictionary:
	if FileAccess.get_file_as_string("res://game/building/body_index.gd").contains("const SpatialCapture"):
		return {"ok":false,"error":"Restore the byte-exact plain BodyIndex before timing"}
	if FileAccess.get_sha256(input)!=expected_sha: return {"ok":false,"error":"Captured request identity changed"}
	var file: FileAccess = FileAccess.open(input,FileAccess.READ)
	if file==null: return {"ok":false,"error":"Cannot read the complete capture"}
	var first: Dictionary = file.get_var(false)
	if first.get("format","")!="spatial-query-stream-v1": return {"ok":false,"error":"Unsupported capture format"}
	var records: Array = []
	var footer: Dictionary = {}
	while file.get_position()<file.get_length():
		var value: Array = file.get_var(false)
		if value[0]=="end": footer=value[1]; break
		records.append(value)
	var complete: bool = not footer.is_empty() and file.get_position()==file.get_length()
	file.close()
	var errors: Array = []
	if not complete or not footer.get("errors",[]).is_empty(): errors.append("Capture was interrupted or had unregistered indexes")
	var counts: Dictionary = {}
	var active_queries: int = 0
	for record: Array in records:
		counts[str(record[0])]=int(counts.get(str(record[0]),0))+1
		if record[0]=="query" and record[4]: active_queries+=1
	if counts!=footer.get("counts",{}): errors.append("Capture record counts differ from the complete footer")
	if active_queries<=0: errors.append("The captured step has no actual native query")
	var content: HospitalContent = HospitalContent.new()
	var header: Dictionary = first.header
	var world: WorldState = WorldState.new(header.facts)
	if header.content_fingerprint!=content.content_fingerprint or not world.validate(content).is_empty(): errors.append("Captured complete world/content validation failed")
	var pairs: Array = []
	for pair: int in 3:
		var indexes: Dictionary = {}
		var batch: Array = []
		var totals: Dictionary = {"pair":pair+1,"before_us":0,"after_us":0,"segments":0,"queries":0,"native_queries":active_queries,"iterations":iterations}
		var digest: HashingContext = HashingContext.new(); digest.start(HashingContext.HASH_SHA256)
		for record: Array in records:
			if record[0]=="query":
				var owners: Array = indexes[int(record[1])]
				batch.append([owners[0],owners[1],record[2],record[3],record[4],record[5]])
				continue
			if not batch.is_empty():
				var timing: Dictionary = _batch(batch,pair,iterations,errors,digest)
				totals.before_us+=int(timing.before_us); totals.after_us+=int(timing.after_us)
				totals.segments+=1; totals.queries+=batch.size(); batch.clear()
			var id: int = int(record[1])
			if record[0]=="index": indexes[id]=[PlatformSpatialIndex.new(),PlatformSpatialIndex.new()]
			else:
				for tree: PlatformSpatialIndex in indexes[id]:
					if record[0]=="clear": tree.clear()
					elif record[0]=="remove": tree.remove(str(record[2]))
					elif record[0]=="update": tree.update(str(record[2]),int(record[3]),_coordinates(record[4]))
		if not batch.is_empty():
			var timing: Dictionary = _batch(batch,pair,iterations,errors,digest)
			totals.before_us+=int(timing.before_us); totals.after_us+=int(timing.after_us)
			totals.segments+=1; totals.queries+=batch.size()
		if int(totals.queries)!=int(counts.get("query",0)): errors.append("A real query was omitted or duplicated")
		totals.complete_results_sha256=digest.finish().hex_encode(); pairs.append(totals)
	return {"ok":errors.is_empty(),"errors":errors,"capture_sha256":expected_sha,"capture_identity":header.identity,"identity":_identity(),"source_input_sha256":header.input_sha256,"world_sha256":_hash(header.facts),"actor_records":world.facts.actors.size(),"present":world.present_actor_count(),"source_counts":counts,"native_queries":active_queries,"pairs":pairs,"scope":"All real tree mutations and requests from the complete captured step are replayed in order. Mutations, one complete warm comparison per segment and all ordered-ID checks are untimed; only original request segments are repeated for three plain AB/BA/AB pairs. Empty-generation requests remain skips. No permission or candidate is cached, no fixed rectangle substitutes for the corpus, and this bridge microbenchmark does not establish full160 performance."}

func run() -> void:
	var options: Dictionary = {"mode":"","input":"","output":"","expected-sha":"","iterations":"100"}
	for arg: String in OS.get_cmdline_user_args():
		for key: String in options:
			if arg.begins_with("--"+key+"="): options[key]=arg.trim_prefix("--"+key+"=")
	if not options.mode in ["capture","replay"] or str(options.input).is_empty() or str(options.output).is_empty() or str(options["expected-sha"]).is_empty() or int(options.iterations)<=0 or FileAccess.file_exists(str(options.output)): quit(2); return
	var report_path: String = str(options.output)+".summary.json" if options.mode=="capture" else str(options.output)
	if FileAccess.file_exists(report_path): quit(2); return
	var policy: Dictionary = ClassDB.class_call_static("PlatformThreadPolicy","apply_main_thread") if ClassDB.class_exists("PlatformThreadPolicy") else {"applied":false}
	if not policy.get("applied",false): quit(2); return
	var result: Dictionary
	if options.mode=="capture": result=_capture(options.input,options.output,options["expected-sha"])
	else: result=_replay(options.input,int(options.iterations),options["expected-sha"])
	result.policy=policy
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify({"ok":result.ok,"mode":options.mode,"report":report_path}))
	quit(0 if result.ok else 1)
