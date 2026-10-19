# Fixed160 workload/qualification from representative.gd, with offline all-instance diagnostics only on explicitly selected complete steps.
extends SceneTree

const Clinical = preload("res://tools/performance/representative_clinical.gd")
const Operations = preload("res://tools/performance/representative_operations.gd")
const StepProfile = preload("res://tools/performance/all_instance_profile.gd")
const DecisionProfile = preload("res://tools/performance/decision_profile.gd")
const Public = preload("res://tools/performance/representative_public.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var options: Dictionary = {"input":"","output":"","steps":"300","profile":"plain","setup":"","store":"","selected":"0,276,285,298"}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			options[argument.trim_prefix("--").get_slice("=",0)] = argument.substr(argument.find("=")+1)
	if str(options.input).is_empty() or str(options.output).is_empty() or not str(options.steps).is_valid_int() or int(options.steps)<0:
		push_error("representative_selected.gd requires --input, --output and nonnegative --steps")
		quit(2)
		return
	if not str(options.profile) in ["plain","all","ledger"]:
		push_error("Profile must be plain, all or ledger")
		quit(2)
		return
	var selected: Array[int] = []
	for text: String in str(options.selected).split(",",false):
		if not text.is_valid_int() or int(text)<0 or int(text)>=int(options.steps) or int(text) in selected:
			push_error("Selected indices must be unique and inside the requested real step window")
			quit(2)
			return
		selected.append(int(text))
	selected.sort()
	var identity_path: String = "res://all-instance-profile-identity.json"
	if (str(options.profile)!="plain")!=FileAccess.file_exists(identity_path):
		push_error("all requires an offline transformed project; plain requires an untransformed project")
		quit(2)
		return
	for path: String in [str(options.output),str(options.output)+".steps.ndjson",str(options.output)+".final.bin",str(options.store)]:
		if not path.is_empty() and FileAccess.file_exists(path):
			push_error("Evidence output already exists: "+path)
			quit(2)
			return
	var content: HospitalContent = HospitalContent.new()
	var initialization_started: int = Time.get_ticks_usec()
	var clinical: RefCounted = Clinical.new(content,str(options.input))
	var initialization_elapsed: int = Time.get_ticks_usec()-initialization_started
	var ops: RefCounted = Operations.new()
	var operation_metadata: Dictionary = {}
	var public_metadata: Dictionary = {}
	var source: FileAccess = FileAccess.open(str(options.input),FileAccess.READ)
	if source!=null:
		var payload: Dictionary = source.get_var()
		operation_metadata = payload.get("representative_clinical",{}).get("metadata",{}).get("operations",{})
		public_metadata = payload.get("representative_clinical",{}).get("metadata",{}).get("public_input",{})
	if not clinical.errors.is_empty():
		_write(str(options.output),{"complete":false,"errors":clinical.errors})
		quit(2)
		return
	if not str(options.setup).is_empty():
		var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(options.setup)))
		if not config is Dictionary:
			push_error("Operations configuration must be a JSON dictionary")
			quit(2)
			return
		operation_metadata = ops.apply(clinical.simulation,config)
		if not operation_metadata.errors.is_empty(): clinical.errors.append_array(operation_metadata.errors)
	var report: Dictionary = {"diagnostic_only":true,"formal_pass":false,"formal_acceptance_paused":true,
		"source_input":str(options.input),"source_input_sha256":clinical.source_sha256,
		"engine":Engine.get_version_info(),"mode":str(options.profile),"requested_steps":int(options.steps),"selected_indices":selected,
		"initialization_elapsed_us":initialization_elapsed,"public_input":public_metadata,
		"execution":{"platform":OS.get_name(),"processor":OS.get_processor_name(),"debug_build":OS.is_debug_build(),
			"editor_binary":OS.has_feature("editor"),"display_server":DisplayServer.get_name(),
			"scope":"ordinary HospitalSimulation.step; frozen legal day plan; no GameSession background capacity preparation, rendering or persistence IO"},
		"setup":operation_metadata,"initial":clinical.inspect(true),"samples":[],"event_records":[],"errors":[]}
	report.sources = {}
	for path: String in ["res://game/clinic/clinical_runtime.gd","res://game/building/hospital_space.gd","res://game/building/navigation_cache.gd",
		"res://game/building/hospital_transit.gd","res://game/operations/environment_service.gd",
		"res://game/life/waiting_life.gd","res://tools/performance/representative_selected.gd","res://tools/performance/representative_clinical.gd",
		"res://tools/performance/representative_operations.gd","res://tools/performance/step_profile.gd",
		"res://tools/performance/all_instance_profile.gd","res://tools/performance/instrument_all_instances.py"]:
		report.sources[path] = FileAccess.get_sha256(path)
	if not str(options.store).is_empty():
		report.stored = clinical.store_input(str(options.store),{"operations":operation_metadata})
		if not report.stored.ok: clinical.errors.append("Failed to freeze operations input")
	var operation_start: Dictionary = ops.snapshot(clinical.world,operation_metadata) if not operation_metadata.is_empty() else {}
	var profiler: RefCounted = null
	if str(options.profile)!="plain" and clinical.errors.is_empty():
		profiler = DecisionProfile.new() if str(options.profile)=="ledger" else StepProfile.new()
		profiler.source_directory = str(options.output)+".sources"
		var replacement: HospitalSimulation = profiler.attach(clinical.simulation,false)
		if replacement==null: clinical.errors.append_array(profiler.errors)
		else: clinical.simulation = replacement
	var public_observer: RefCounted = Public.new(clinical.simulation.space)
	print("REPRESENTATIVE_START="+JSON.stringify({"input_sha256":clinical.source_sha256,"mode":options.profile,
		"tick":clinical.world.sim_tick,"present":clinical.world.present_actor_count(),"steps":options.steps,"pid":OS.get_process_id()}))
	var progress: FileAccess = FileAccess.open(str(options.output)+".steps.ndjson",FileAccess.WRITE)
	for index: int in int(options.steps):
		if not clinical.errors.is_empty(): break
		if public_metadata.has("manual_command") and index==int(public_metadata.get("manual_command_step",0)):
			var command: Dictionary = public_metadata.manual_command.duplicate(true)
			command.expected_revision = clinical.world.revision
			clinical.simulation.enqueue(command)
		# Enter/complete markers are outside the measured operation. A watchdog
		# preserves the last marker and labels a stopped run incomplete.
		progress.store_line(JSON.stringify({"kind":"enter","index":index,"tick":clinical.world.sim_tick}))
		progress.flush()
		if index==0 or index%20==0: print("REPRESENTATIVE_ENTER="+JSON.stringify({"index":index,"tick":clinical.world.sim_tick}))
		var profile_selected: bool = profiler!=null and index in selected
		if profile_selected: profiler.begin_selected_step(index)
		var started: int = Time.get_ticks_usec()
		var result: TickResult = clinical.simulation.step()
		var elapsed: int = Time.get_ticks_usec()-started
		var step_record: Dictionary = profiler.end_selected_step(result,elapsed) if profile_selected else {}
		if result==null:
			clinical.errors.append("Production step did not complete: "+clinical.simulation.preparing_error())
			report.samples.append({"index":index,"elapsed_us":elapsed,"complete":false,"profile":step_record})
			break
		var observation: Dictionary = clinical.observe(result)
		public_observer.observe(clinical.world,clinical.simulation.space)
		for event: SimEvent in result.facts: report.event_records.append(event.to_record())
		report.samples.append({"index":index,"tick":result.sim_tick,"elapsed_us":elapsed,"complete":true,
			"present":clinical.world.present_actor_count(),"sessions":observation.sessions.size(),"moves":clinical.world.facts.moves.size(),
			"lifecycle_events":observation.lifecycle_events})
		progress.store_line(JSON.stringify({"kind":"complete","sample":report.samples.back(),"profile":step_record}))
		progress.flush()
		if index==0 or (index+1)%20==0: print("REPRESENTATIVE_COMPLETE="+JSON.stringify(report.samples.back()))
	report.final = clinical.inspect(true)
	report.public = public_observer.report(clinical.simulation.space)
	if public_metadata.has("manual_command"):
		report.public.manual_receipt = clinical.simulation.receipt(str(public_metadata.manual_command.id))
	if public_metadata.get("contention_scene",false):
		report.public_checks = {"manual_request_accepted":report.public.manual_receipt.get("accepted",false),"actual_queue_observed":report.public.queue_peak>0,"actual_uses_observed":report.public.actual_use_starts.size()>=2,"two_actual_use_regions":report.public.used_regions.size()>=2,"actual_completion_observed":report.public.actual_use_completions.size()>0,"prior_actual_exit_before_reuse":report.public.actual_exit_then_reuse_count>0,"no_observer_rule_errors":report.public.errors.is_empty()}
	report.operations = ops.assess(clinical.world,operation_metadata,operation_start) if not operation_metadata.is_empty() else {}
	if profiler!=null:
		report.all_instance_source_identity = JSON.parse_string(FileAccess.get_file_as_string(identity_path))
		report.all_instance_source_identity_sha256 = FileAccess.get_sha256(identity_path)
		report.profile = profiler.report()
		clinical.errors.append_array(profiler.errors)
	report.errors = clinical.errors.duplicate()
	report.complete = report.samples.size()==int(options.steps) and report.errors.is_empty() and report.final.ok
	var clinical_work_ticks: int = 0
	for kind: String in report.final.work_ticks_by_kind:
		if kind!="reception": clinical_work_ticks += int(report.final.work_ticks_by_kind[kind])
	report.qualification = {"all_steps_complete":report.complete,"present_160_throughout":report.final.minimum_present==160 and report.final.maximum_present==160,
		"same_actor_ids":report.final.same_actor_ids,
		"world_valid":str(report.final.validation).is_empty()}
	if int(options.steps)>0: report.qualification.actual_clinical_work = clinical_work_ticks>0
	if int(options.steps)>0 and not report.operations.is_empty():
		for check: String in report.operations.checks: report.qualification["operations."+check] = report.operations.checks[check]
	report.qualified = true
	for value: bool in report.qualification.values(): report.qualified = report.qualified and value
	report.metrics = _metrics(report.samples)
	var final_path: String = str(options.output)+".final.bin"
	var final_file: FileAccess = FileAccess.open(final_path,FileAccess.WRITE)
	final_file.store_var({"facts":clinical.world.freeze(),"events":report.event_records})
	final_file.close()
	report.final_binary_sha256 = FileAccess.get_sha256(final_path)
	_write(str(options.output),report)
	progress.close()
	print("REPRESENTATIVE_RESULT="+JSON.stringify({"complete":report.complete,"qualified":report.qualified,"qualification":report.qualification,"metrics":report.metrics,"errors":report.errors,"output":options.output}))
	clinical.dispose()
	quit(0 if report.qualified else 1)

func _metrics(samples: Array) -> Dictionary:
	var values: Array = []
	for sample: Dictionary in samples:
		if sample.complete: values.append(int(sample.elapsed_us))
	if values.is_empty(): return {}
	var ordered: Array = values.duplicate()
	ordered.sort()
	var total: int = 0
	for value: int in values: total += value
	return {"count":values.size(),"mean_us":float(total)/values.size(),"p50_us":ordered[ceili(ordered.size()*0.50)-1],
		"p95_us":ordered[ceili(ordered.size()*0.95)-1],"p99_us":ordered[ceili(ordered.size()*0.99)-1],"max_us":ordered.back(),"cold_first_us":values.front(),
		"following_mean_us":float(total-int(values.front()))/maxi(1,values.size()-1),"total_us":total}

func _write(path: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t"))
