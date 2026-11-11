extends SceneTree

const Fixture = preload("res://tools/performance/fixture.gd")
const Timing = preload("res://tools/performance/profile.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var count: int = 160
	var steps: int = 3
	var output: String = "res://diagnostic.json"
	var layout: String = "four_floors"
	var profile: bool = false
	var trace_phases: bool = false
	var input: String = ""
	var operation: String = "step"
	var checkpoint_steps: int = 1
	var valid_checkpoint: bool = true
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--actors="): count = argument.get_slice("=",1).to_int()
		if argument.begins_with("--steps="): steps = argument.get_slice("=",1).to_int()
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument.begins_with("--layout="): layout = argument.get_slice("=",1)
		if argument=="--profile": profile = true
		if argument=="--trace-phases": trace_phases = true
		if argument.begins_with("--input="): input = argument.trim_prefix("--input=")
		if argument.begins_with("--operation="): operation = argument.get_slice("=",1)
		if argument.begins_with("--checkpoint-steps="):
			var value: String = argument.trim_prefix("--checkpoint-steps=")
			valid_checkpoint = valid_checkpoint and value.is_valid_int() and value.to_int()>0
			checkpoint_steps = value.to_int()
	if not operation in ["step","preparation","session","graphs","route"]:
		push_error("Unknown diagnostic operation: "+operation)
		quit(2)
		return
	if not valid_checkpoint:
		push_error("--checkpoint-steps must be a positive integer")
		quit(2)
		return
	var started: int = Time.get_ticks_usec()
	var content: HospitalContent = HospitalContent.new()
	var fixture: RefCounted = Fixture.new(content,count,layout,input)
	var simulation: HospitalSimulation = HospitalSimulation.new(fixture.world,content)
	var validation: String = fixture.world.validate(content)
	print("PERFORMANCE_FIXTURE="+JSON.stringify({"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0,"description":fixture.describe(),"validation":validation}))
	if not validation.is_empty() or not fixture.errors.is_empty():
		quit(2)
		return
	fixture.store_input(output+".input.bin")
	var timing: RefCounted = Timing.new()
	if trace_phases:
		if not timing.enable_phase_trace(output+".phases.ndjson"):
			push_error("Cannot open phase trace: "+output+".phases.ndjson")
			quit(2)
			return
		print("PERFORMANCE_PHASE_TRACE="+JSON.stringify({"path":timing.phase_trace_path,"pid":OS.get_process_id(),"diagnostic_only":true,"flush_each_event":true,"step_includes_trace_io":true}))
	if profile:
		timing.snapshot_path = output+".profile.json"
	if profile or trace_phases:
		if not timing.attach(simulation):
			quit(2)
			return
	var samples: Array = []
	if operation in ["preparation","session"]:
		var begin: int = Time.get_ticks_usec()
		var session: GameSession = GameSession.new(simulation,"preparation-diagnostic")
		var main_us: int = Time.get_ticks_usec()-begin
		var max_main_us: int = main_us
		session.set_speed(1)
		var completed: Array[TickResult] = []
		var polls: int = 0
		var requested_steps: int = steps if operation=="session" else 1
		while completed.size()<requested_steps:
			var poll_started: int = Time.get_ticks_usec()
			var batch: Array[TickResult] = session.advance(0.1 if not simulation.pending() else 0.0)
			completed.append_array(batch)
			var elapsed: int = Time.get_ticks_usec()-poll_started
			main_us += elapsed
			max_main_us = maxi(max_main_us,elapsed)
			polls += 1
			if batch.is_empty(): await create_timer(0.005).timeout
		var evidence: Dictionary = {"diagnostic":true,"operation":operation,"wall_ms":(Time.get_ticks_usec()-begin)/1000.0,
			"main_ms":main_us/1000.0,"max_main_slice_ms":max_main_us/1000.0,"polls":polls,
			"step_ms":completed[0].elapsed_us/1000.0 if not completed.is_empty() else null,
			"completed_steps":completed.size(),"requested_steps":requested_steps,
			"kernel_steps_ms":completed.map(func(step: TickResult)->float: return step.elapsed_us/1000.0),
			"arrival_mode":"synchronous_random_demand","plan":fixture.world.facts.arrivals.plan,
			"tracked_bytes":OS.get_static_memory_usage(),"profile":timing.report()}
		fixture.store_input(output+".after.bin")
		var report: FileAccess = FileAccess.open(output,FileAccess.WRITE)
		report.store_string(JSON.stringify(evidence,"\t"))
		print("PERFORMANCE_PREPARATION="+JSON.stringify(evidence.merged({"profile":{}})))
		simulation.dispose()
		quit(0 if completed.size()==requested_steps else 1)
		return
	if operation=="graphs":
		for actor_id: String in ["bench_staff_0000","bench_patient_0000"]:
			for floor_id: int in fixture.floors:
				var before: int = OS.get_static_memory_usage()
				var begin: int = Time.get_ticks_usec()
				var graph: FloorNavigation = simulation.space._navigation.graph(simulation.space,fixture.world,floor_id,fixture.world.facts.actors[actor_id],[],{})
				print("PERFORMANCE_GRAPH="+JSON.stringify({"actor":actor_id,"body":simulation.space.body(fixture.world.facts.actors[actor_id]),"floor":floor_id,"elapsed_ms":(Time.get_ticks_usec()-begin)/1000.0,"tracked_bytes_delta":OS.get_static_memory_usage()-before,"tracked_bytes":OS.get_static_memory_usage(),"charged":simulation.space._navigation._charged,"retained":simulation.space._navigation._entries.size(),"points":graph.get_point_count()}))
		simulation.dispose()
		quit(0)
		return
	if operation=="route":
		for index: int in 3:
			var begin: int = Time.get_ticks_usec()
			var route: Dictionary = simulation.space.route(fixture.world,"bench_staff_0000",1,[48,91],[],{},true)
			print("PERFORMANCE_ROUTE="+JSON.stringify({"elapsed_ms":(Time.get_ticks_usec()-begin)/1000.0,"ok":route.ok,"reason":route.get("reason",""),"cells":route.get("path",[]).size()}))
		simulation.dispose()
		quit(0)
		return
	var checkpoint_indices: Array = []
	for index: int in steps:
		var begin: int = Time.get_ticks_usec()
		if trace_phases: timing.trace_phase("simulation.step",fixture.world,"enter")
		var result: TickResult = simulation.step()
		if trace_phases: timing.trace_phase("simulation.step",fixture.world,"return")
		var sample: Dictionary = {"tick":fixture.world.sim_tick,"elapsed_ms":(Time.get_ticks_usec()-begin)/1000.0,"present":fixture.world.present_actor_count(),"moves":fixture.world.facts.moves.size(),"preparations":fixture.world.facts.preparations.size(),"sessions":fixture.world.facts.sessions.size(),"events":result.facts.size()}
		if profile: sample.profile = timing.report()
		samples.append(sample)
		print("PERFORMANCE_STEP="+JSON.stringify(sample.merged({"profile":{}},true) if profile else sample))
		# Persistence is outside the original complete-step timer. Less frequent
		# checkpoints retain every sample while avoiding quadratic write volume.
		if (index+1)%checkpoint_steps==0 or index+1==steps:
			checkpoint_indices.append(index+1)
			fixture.store_input(output+".after.bin")
			var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
			file.store_string(JSON.stringify({"diagnostic":true,"fixture":fixture.describe(),"steps":samples,"profile":timing.report(),"checkpoint_steps":checkpoint_steps,"checkpoint_step_indices":checkpoint_indices},"\t"))
			file.close()
	simulation.dispose()
	quit(0)
