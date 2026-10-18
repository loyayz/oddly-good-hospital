extends SceneTree

const Representative = preload("res://tools/performance/representative_clinical.gd")
var _output: String = ""
var _run_id: String = "r1"
var _started: int
var _captured: Dictionary = {}
var _log: FileAccess

func _initialize() -> void:
	call_deferred("_run")

func _emit(stage: String, details: Dictionary = {}) -> void:
	var record: Dictionary = {"stage":stage,"elapsed_us":Time.get_ticks_usec()-_started,"details":details}
	print("CLINICAL_CONTINUE="+JSON.stringify(record))
	_log.store_line(JSON.stringify(record))
	_log.flush()

func _capture(fixture: RefCounted, name: String) -> void:
	if _captured.has(name): return
	var result: Dictionary = fixture.store_input(_output.path_join("clinical-"+_run_id+"-"+name+".input.bin"),{"boundary":name,"maximum_steps_for_probe":2000,"maximum_real_seconds_for_probe":60})
	_captured[name] = result
	_emit("captured",{"name":name,"ok":result.ok,"path":result.get("path",""),"sha256":result.get("sha256",""),"tick":fixture.world.sim_tick})

func _run() -> void:
	var input: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="): input = argument.trim_prefix("--input=")
		if argument.begins_with("--output-dir="): _output = argument.trim_prefix("--output-dir=")
		if argument.begins_with("--run-id="): _run_id = argument.trim_prefix("--run-id=")
	_started = Time.get_ticks_usec()
	if input.is_empty() or not FileAccess.file_exists(input) or _output.is_empty() or not _run_id.is_valid_filename():
		push_error("Expected existing --input, --output-dir and a valid --run-id.")
		quit(2)
		return
	if FileAccess.file_exists(_output.path_join("clinical-"+_run_id+"-progress.ndjson")) or FileAccess.file_exists(_output.path_join("clinical-"+_run_id+"-result.json")):
		push_error("Representative continuation evidence already exists; choose a new run id.")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))!=OK:
		quit(2)
		return
	_log = FileAccess.open(_output.path_join("clinical-"+_run_id+"-progress.ndjson"),FileAccess.WRITE)
	if _log==null:
		quit(2)
		return
	var content: HospitalContent = HospitalContent.new()
	var fixture: RefCounted = Representative.new(content,input)
	_emit("loaded",fixture.inspect(true))
	if not content.error.is_empty() or not fixture.errors.is_empty():
		fixture.dispose()
		quit(2)
		return
	var steps: int = 0
	var reason: String = "maximum_steps"
	while steps<2000:
		if Time.get_ticks_usec()-_started>=60000000:
			reason = "bounded_watchdog"
			break
		var result: TickResult = fixture.simulation.step_nonblocking()
		while result==null and fixture.simulation.preparing_error().is_empty() and Time.get_ticks_usec()-_started<60000000:
			await process_frame
			result = fixture.simulation.step_nonblocking()
		if result==null:
			reason = "preparation_error_or_watchdog:"+fixture.simulation.preparing_error()
			break
		steps += 1
		var observed: Dictionary = fixture.observe(result)
		if not observed.ok:
			reason = "fixed_load_violation"
			break
		if fixture.boundary("gp_started"): _capture(fixture,"gp_started")
		if fixture.boundary("gp_handoff"): _capture(fixture,"gp_handoff")
		if fixture.boundary("clinical_preparation"): _capture(fixture,"clinical_preparation")
		if fixture.boundary("outpatient_started"): _capture(fixture,"outpatient_started")
		if not _captured.has("gp_work_handoff"):
			for session: Dictionary in observed.sessions.values():
				if session.kind=="gp" and int(session.remaining_ticks)<=55 and int(session.remaining_ticks)>=45:
					_capture(fixture,"gp_work_handoff")
		if steps%32==0:
			var state: Dictionary = fixture.inspect()
			_emit("progress",{"steps":steps,"tick":fixture.world.sim_tick,"present":state.present,"sessions":state.sessions,"phase_counts":state.phase_counts,"moves":state.moves,"work_ticks":state.work_ticks_by_kind,"completed":state.services_completed,"waiting_reasons":state.waiting_reasons})
			await process_frame
		if _captured.has("outpatient_started"):
			reason = "representative_boundaries_captured"
			break
	var state: Dictionary = fixture.inspect(true)
	var checkpoint: Dictionary = fixture.store_input(_output.path_join("clinical-"+_run_id+"-continuation.input.bin"),{"boundary":"bounded_continuation","stop_reason":reason})
	if not bool(checkpoint.ok):
		var failure_path: String = _output.path_join("clinical-"+_run_id+"-failure.bin")
		if not FileAccess.file_exists(failure_path):
			var failure_file: FileAccess = FileAccess.open(failure_path,FileAccess.WRITE)
			failure_file.store_var({"qualified_fixed160":false,"reason":reason,"content_fingerprint":content.content_fingerprint,"facts":fixture.world.freeze(),"floors":fixture.floors,"visitor_ids":fixture.visitor_ids})
			failure_file.close()
	var elapsed: int = Time.get_ticks_usec()-_started
	var report: Dictionary = {"schema_version":1,"preparation_only":true,"source":input,"source_sha256":FileAccess.get_sha256(input),"stop_reason":reason,"steps":steps,"elapsed_us":elapsed,"soft_watchdog_us":60000000,"watchdog_scope":"checked between original complete steps; one whole step may overrun","whole_step_or_output_overrun_us":maxi(0,elapsed-60000000),"captured":_captured,"final":state,"checkpoint":checkpoint}
	var file: FileAccess = FileAccess.open(_output.path_join("clinical-"+_run_id+"-result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	_emit("finished",{"stop_reason":reason,"steps":steps,"tick":fixture.world.sim_tick,"present":state.present,"validation":state.validation,"captures":_captured.keys(),"checkpoint":checkpoint.get("ok",false)})
	fixture.dispose()
	quit(0 if bool(state.ok) else 1)
