extends SceneTree

const Fixture = preload("res://tools/performance/fixture.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	if output.is_empty() or FileAccess.file_exists(output):
		push_error("Expected new --output JSON")
		quit(2)
		return
	var content: HospitalContent = HospitalContent.new()
	var fixture: RefCounted = Fixture.new(content,640,"tall")
	var validation: String = fixture.world.validate(content)
	if not fixture.errors.is_empty() or not validation.is_empty():
		push_error("Illegal preview input: "+validation)
		quit(2)
		return
	fixture.store_input(output+".input.bin")
	var observations: Array = []
	var passed: bool = true
	var completed_boundary_supported: bool = false
	for method: Dictionary in load("res://game/building/build_preview.gd").get_script_method_list():
		if method.name=="update": completed_boundary_supported = method.args.size()>=3
	for width: int in [85,96]:
		var draft: Dictionary = {"kind":"build_room","room_type_id":"gp","floor_id":2,"origin":[0,0],"size":[width,95],"door":{"definition_id":"DR01","edge":"south","offset":1}}
		var preview: BuildPreview = BuildPreview.new(BuildService.new(content))
		preview.request(draft,{"hospital_id":fixture.world.hospital_id,"view_floor_id":2})
		var updates: int = 0
		var maximum_update_us: int = 0
		var started: int = Time.get_ticks_usec()
		while (preview.job==null or not preview.job.complete) and Time.get_ticks_usec()-started<120000000:
			var begin: int = Time.get_ticks_usec()
			if completed_boundary_supported:
				preview.call("update",fixture.world,0,[fixture.world,fixture.world.revision])
			else: preview.update(fixture.world)
			maximum_update_us = maxi(maximum_update_us,Time.get_ticks_usec()-begin)
			updates += 1
		var complete: bool = preview.job!=null and preview.job.complete
		passed = passed and complete and (bool(preview.result.get("ok",false)) if width==85 else not bool(preview.result.get("ok",false)))
		observations.append({"width":width,"height":95,"updates":updates,"elapsed_us":Time.get_ticks_usec()-started,"maximum_update_us":maximum_update_us,"complete":complete,"result":preview.result,"atomic_overruns":preview.job.atomic_overruns,"units_checked":preview.job.units_checked})
	var report: Dictionary = {"diagnostic_only":true,"scope":"headless complete preview CPU/update costs; not OS input or displayed latency","completed_boundary_supported":completed_boundary_supported,"passed":passed,"engine":Engine.get_version_info().string,"input_sha256":FileAccess.get_sha256(output+".input.bin"),"observations":observations}
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("PREVIEW_DIAGNOSTIC="+JSON.stringify({"output":output,"passed":passed}))
	quit(0 if passed else 1)
