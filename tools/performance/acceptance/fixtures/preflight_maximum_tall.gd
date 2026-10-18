extends SceneTree

# Complete original synchronous correctness quotes only. This is neither the
# sliced UI computation nor an OS-input/displayed-latency measurement.
const Fixture = preload("res://tools/performance/fixture.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var input: String = ""
	var output: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="): input = argument.trim_prefix("--input=")
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	if input.is_empty() or output.is_empty() or not FileAccess.file_exists(input) or FileAccess.file_exists(output):
		push_error("Expected existing --input and new --output for original tall maximum correctness preflight.")
		quit(2)
		return
	var content: HospitalContent = HospitalContent.new()
	if not content.error.is_empty():
		push_error(content.error)
		quit(2)
		return
	var fixture: RefCounted = Fixture.new(content,640,"tall",input)
	var world: WorldState = fixture.world
	var validation: String = world.validate(content)
	if not fixture.errors.is_empty() or not validation.is_empty() or fixture.floors!=[1,10,1000,10000] or world.present_actor_count()!=640:
		push_error("Original 640 tall source invalid: "+validation+JSON.stringify(fixture.errors))
		quit(2)
		return
	var before: Dictionary = world.freeze()
	var observations: Array = []
	var valid: bool = true
	for width: int in [85,96]:
		var probe: WorldState = WorldState.new(before.duplicate(true))
		var builder: BuildService = BuildService.new(content)
		var started: int = Time.get_ticks_usec()
		var quote: Dictionary = builder.preview(probe,{"kind":"build_room","room_type_id":"gp","floor_id":2,"origin":[0,0],"size":[width,95],"door":{"definition_id":"DR01","edge":"south","offset":1}})
		var elapsed: int = Time.get_ticks_usec()-started
		var readonly: bool = probe.freeze()==before
		var outcome: bool = bool(quote.get("ok",false)) if width==85 else not bool(quote.get("ok",false)) and str(quote.get("reason","")).contains("竖向结构")
		if width==85: outcome = outcome and int(quote.get("price",-1))==323050
		valid = valid and outcome and readonly
		observations.append({"width":width,"height":95,"floor_id":2,"expected_ok":width==85,"actual_complete_quote":quote,"readonly":readonly,"outcome_matches":outcome,"correctness_preflight_us":elapsed})
	valid = valid and world.freeze()==before
	var report: Dictionary = {"schema_version":1,"ok":valid,"preparation_only":true,"source":input,"source_sha256":FileAccess.get_sha256(input),
		"engine":Engine.get_version_info().string,"content_fingerprint":content.content_fingerprint,"validation":validation,"observations":observations,
		"metric_scope":"Synchronous original correctness preflight. Not actual sliced UI completion or external input/displayed latency. Original 640 world and shaft retained."}
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	if file==null:
		push_error("Cannot write tall correctness preflight report.")
		quit(2)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("ACCEPTANCE_TALL_MAXIMUM_PREFLIGHT="+JSON.stringify(report))
	quit(0 if valid else 1)
