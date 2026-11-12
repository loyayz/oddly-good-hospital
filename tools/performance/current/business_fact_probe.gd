extends "res://tools/performance/current/plain_v4.gd"

# Separate driver; the plain driver and its observer are never patched.
const Trace = preload("res://tools/performance/current/business_fact_trace.gd")
const MIXED_SHA: String = "75f5e1d922f39f12382c0ceb74806bda0293251189f68a1ac158842f65fa78ca"
const FULL_SHA: String = "0daf82b82da618af8818aed962d5ef2bf9bad1b00be01c4f5a7ce71efb52662e"
const SMOKE_SHA: String = "21aff2546935022312333b67605680c491292575aaa845b07733db993a415a51"

func _run() -> void:
	var input: String = ""
	var inspect: bool = false
	var smoke: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="): input = argument.trim_prefix("--input=")
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument=="--inspect": inspect = true
		elif argument=="--smoke": smoke = true
		else: push_error("Unknown diagnostic argument: "+argument);quit(2);return
	if input.is_empty() or output.is_empty() or inspect and smoke: quit(2);return
	for suffix: String in ["",".initial.json",".execution.json",".steps.ndjson",".final.bin",".business.ndjson"]:
		if FileAccess.file_exists(output+suffix): quit(2);return
	var input_sha: String = FileAccess.get_sha256(input)
	if input_sha!=(FULL_SHA if inspect else MIXED_SHA): write_json(output,{"complete":false,"reason":"Unexpected complete input","input_sha256":input_sha});quit(2);return
	var content: HospitalContent = HospitalContent.new()
	var file: FileAccess = FileAccess.open(input,FileAccess.READ)
	if file==null: quit(2);return
	var envelope: Dictionary = file.get_var(false)
	file.close()
	if envelope.get("content_fingerprint","")!=content.content_fingerprint: write_json(output,{"complete":false,"reason":"Content mismatch"});quit(2);return
	var inspect_before: Dictionary = envelope.facts.duplicate(true) if inspect else {}
	var world: WorldState = WorldState.new(envelope.facts)
	var validation: String = world.validate(content)
	if not validation.is_empty(): write_json(output,{"complete":false,"reason":validation});quit(2);return
	if inspect:
		var inspector = Trace.new()
		var records: Dictionary = inspector.capture(world,true)
		var entry_actors: Dictionary = {}
		var actor_visit_ids: Dictionary = {}
		for id: String in world.facts.actors:
			var actor: Dictionary = world.facts.actors[id]
			if actor.location.kind=="floor" and int(actor.location.floor_id)==int(world.facts.entry.floor_id): entry_actors[id] = actor.duplicate(true)
		for id: String in world.facts.visits: actor_visit_ids[str(world.facts.visits[id].actor_id)] = id
		var unchanged: bool = inspect_before==world.freeze() and FileAccess.get_sha256(input)==input_sha
		write_json(output,{"complete":unchanged,"mode":"read_only_final_boundary","input":input,"input_sha256":input_sha,"tick":world.sim_tick,"world_validation":validation,"complete_facts_and_rng_unchanged":unchanged,"records":records,"entry":world.facts.entry.duplicate(true),"entry_floor_actors":entry_actors,"actor_visit_ids":actor_visit_ids,"retained_ledger":world.facts.ledger.duplicate(true),"scope":"No Simulation, step, command, service query, quote or draw. Only retained owner facts are shown. Missing retired WardStays, requests and daily intentions cannot establish that no earlier family visit occurred."})
		quit(0 if unchanged else 1);return
	if envelope.get("scenario","")!="mixed160-clinical-ops-v1": quit(2);return
	var policy: Dictionary = {"requested":"app","applied":false}
	if ClassDB.class_exists("PlatformThreadPolicy"): policy.merge(ClassDB.class_call_static("PlatformThreadPolicy","apply_main_thread"),true)
	if not policy.applied: write_json(output,{"complete":false,"reason":"App thread policy unavailable","policy":policy});quit(2);return
	var sim: HospitalSimulation = HospitalSimulation.new(world,content)
	sim.services.experience.sample_workers_enabled = true
	sim.services.experience.sample_worker_tasks = 4
	var floor_preparation: Dictionary = sim.prepare_floor_static(1)
	var observer = Observer.new(content,"mixed160-clinical-ops-v1")
	var operations = load("res://tools/performance/current/comprehensive_operations.gd").new()
	var trace = Trace.new()
	var prefix: int = 0 if smoke else 1000
	var steps: int = 2 if smoke else 6000
	var expected: String = SMOKE_SHA if smoke else FULL_SHA
	var initial: Dictionary = snapshot(world)
	var before_capture: Dictionary = world.freeze()
	if not trace.open(world,output+".business.ndjson",input_sha,expected,prefix,steps) or before_capture!=world.freeze():
		write_json(output,{"complete":false,"reason":"Initial read-only capture failed"});sim.dispose();quit(2);return
	write_json(output+".initial.json",initial)
	var stream: FileAccess = FileAccess.open(output+".steps.ndjson",FileAccess.WRITE)
	var events: Array = []
	var samples: Array = []
	var errors: Array = []
	var start: int = Time.get_ticks_usec()
	var sample_start: int = start
	var prefix_wall: int = 0
	for index: int in prefix+steps:
		var iteration_start: int = Time.get_ticks_usec()
		if index==prefix: sample_start = iteration_start;prefix_wall = iteration_start-start
		if index>=prefix: operations.enqueue(sim,index-prefix)
		var observed_before: Dictionary = observer.capture(world)
		stream.store_line(JSON.stringify({"kind":"enter","index":index,"tick":world.sim_tick}));stream.flush()
		var step_start: int = Time.get_ticks_usec()
		var result: TickResult = sim.step()
		var elapsed: int = Time.get_ticks_usec()-step_start
		if result==null or world.sim_tick!=int(initial.tick)+index+1: errors.append("Incomplete production step");break
		observer.observe(observed_before,world,result,index>=prefix)
		for event: SimEvent in result.facts: events.append(event.to_record())
		var row: Dictionary = {"index":index,"tick":world.sim_tick,"elapsed_us":elapsed,"wall_start_us":iteration_start,"present":world.present_actor_count(),"sessions":world.facts.sessions.size(),"moves":world.facts.moves.size()}
		samples.append(row)
		stream.store_line(JSON.stringify({"kind":"complete","sample":row}));stream.flush()
		if not trace.observe(world,index): errors.append("Read-only capture changed facts");break
		if index%100==0: print("BUSINESS_FACT_PROGRESS="+JSON.stringify(row))
	var ending_us: int = Time.get_ticks_usec()
	stream.close()
	validation = world.validate(content)
	if not validation.is_empty(): errors.append(validation)
	var final: Dictionary = snapshot(world)
	var before_final_capture: Dictionary = world.freeze()
	var trace_report: Dictionary = trace.finish()
	if before_final_capture!=world.freeze(): errors.append("Final capture changed complete facts")
	var ending: FileAccess = FileAccess.open(output+".final.bin",FileAccess.WRITE)
	ending.store_var({"content_fingerprint":content.content_fingerprint,"facts":world.freeze(),"floors":envelope.floors,"visitor_ids":envelope.visitor_ids,"events":events});ending.close()
	var final_sha: String = FileAccess.get_sha256(output+".final.bin")
	if final_sha!=expected: errors.append("Complete World and ordered events differ from plain witness")
	if FileAccess.get_sha256(input)!=input_sha: errors.append("Input changed during diagnostics")
	var comprehensive: Dictionary = observer.report(world)
	if not smoke and not comprehensive.coverage_pass: errors.append("Comprehensive workload did not satisfy its business coverage contract")
	var metrics: Dictionary = _time_statistics(samples.slice(prefix),ending_us-sample_start)
	metrics.dense_intervals = _dense_statistics(samples.slice(prefix),ending_us,144)
	write_json(output+".execution.json",{"main_thread_policy":policy,"worker_tasks":4,"worker_samples":sim.services.experience.sample_worker_report(),"profile_stages":false,"trace":trace_report,"scope":"Read-only boundary diagnostic; capture/IO overhead is present and timings are not plain CPU measurements."})
	write_json(output,{"complete":samples.size()==prefix+steps and errors.is_empty(),"performance_pass":null,"source_input_sha256":input_sha,"mode":"business_fact_diagnostic","requested_prefix_steps":prefix,"requested_sample_steps":steps,"all_completed_steps":samples.size(),"prefix_wall_us":prefix_wall,"all_wall_us":ending_us-start,"initial":initial,"final":final,"metrics":metrics,"sample_business":{"comprehensive":comprehensive},"floor_static_preparation":floor_preparation,"errors":errors,"trace":trace_report,"final_sha256":final_sha,"world_validation":validation,"scope":"Only owner facts at real step boundaries. No plain source or coverage rule is patched; no candidate, request, actor, worker, random stream or workload is changed. Timings are diagnostic only."})
	sim.dispose();quit(0 if errors.is_empty() else 1)
