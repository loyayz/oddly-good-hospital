extends SceneTree

const Trace = preload("res://tools/performance/resident_rectangle_trace.gd")

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var input: String = ""
	var output: String = ""
	var mode: String = "candidate"
	var warmup: int = 0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="): input=argument.trim_prefix("--input=")
		if argument.begins_with("--output="): output=argument.trim_prefix("--output=")
		if argument.begins_with("--mode="): mode=argument.trim_prefix("--mode=")
		if argument.begins_with("--warmup="): warmup=argument.trim_prefix("--warmup=").to_int()
	if input.is_empty() or output.is_empty() or FileAccess.file_exists(output) or not mode in ["baseline","candidate","counts","timing"] or warmup<0: push_error("Use a complete frozen input, new output and explicit probe mode");quit(2);return
	var content: HospitalContent = HospitalContent.new()
	var file: FileAccess = FileAccess.open(input,FileAccess.READ)
	var envelope: Dictionary = file.get_var(false)
	file.close()
	var world: WorldState = WorldState.new(envelope.facts)
	var initial: Dictionary = world.freeze()
	if envelope.content_fingerprint!=content.content_fingerprint or not world.validate(content).is_empty(): push_error("Invalid complete input");quit(2);return
	var policy: Dictionary = ClassDB.class_call_static("PlatformThreadPolicy","apply_main_thread")
	Trace.baseline=mode=="baseline"
	var preparation_start: int = Time.get_ticks_usec()
	var sim: HospitalSimulation = HospitalSimulation.new(world,content)
	sim.services.experience.sample_workers_enabled=true
	sim.services.experience.sample_worker_tasks=4
	# Same explicit selected-floor preparation as the existing boundary witness
	# and ordinary app restore. No extra floor/body graph is warmed for this probe.
	var floor_preparation: Dictionary = sim.prepare_floor_static(1)
	var initialization_usec: int = Time.get_ticks_usec()-preparation_start
	var initialized: Dictionary = world.freeze()
	var events: Array = envelope.get("events",[]).duplicate(true)
	var warmup_start: int = Time.get_ticks_usec()
	for step: int in warmup:
		var advanced: TickResult = sim.step()
		for event: SimEvent in advanced.facts: events.append(event.to_record())
	var warmup_usec: int = Time.get_ticks_usec()-warmup_start
	var boundary_tick: int = world.sim_tick
	if mode in ["counts","timing"]: Trace.start(mode)
	var result: TickResult = sim.step()
	var trace: Dictionary = Trace.finish() if mode in ["counts","timing"] else {}
	for event: SimEvent in result.facts: events.append(event.to_record())
	var validation: String = world.validate(content)
	var ending: Dictionary = envelope.duplicate(true)
	ending.facts=world.freeze()
	ending.events=events
	file=FileAccess.open(output+".bin",FileAccess.WRITE)
	file.store_var(ending)
	file.close()
	var ok: bool = validation.is_empty() and trace.get("errors",[]).is_empty() and world.sim_tick==boundary_tick+1
	var report: Dictionary = {"complete":true,"ok":ok,"mode":mode,"input_sha256":FileAccess.get_sha256(input),"initial_tick":int(initial.sim_tick),"initialized_facts_unchanged":initial==initialized,"initialization_usec":initialization_usec,"floor_preparation":floor_preparation,"ordinary_warmup_steps":warmup,"ordinary_warmup_usec":warmup_usec,"boundary_tick":boundary_tick,"final_tick":world.sim_tick,"actors":world.facts.actors.size(),"present_actors":world.present_actor_count(),"world_validation":validation,"main_thread_policy":policy,"worker_tasks":4,"full_world_and_ordered_events_sha256":FileAccess.get_sha256(output+".bin"),"trace":trace,"scope":"One actual production simulation step after recorded ordinary warmup and existing app floor preparation. No actor relocation, artificial graph warming, rule/load change or scripted local manoeuvre. Diagnostic step durations do not qualify game CPU performance."}
	file=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t",true,true))
	file.close()
	print("RESIDENT_RECTANGLE_PROBE="+JSON.stringify({"mode":mode,"ok":ok,"boundary_tick":boundary_tick,"eligible":trace.get("eligible",0),"sha256":report.full_world_and_ordered_events_sha256}))
	sim.dispose()
	quit(0 if ok else 1)
