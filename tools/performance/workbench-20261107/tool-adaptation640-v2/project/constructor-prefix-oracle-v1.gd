extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var output: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if output.is_empty() or FileAccess.file_exists(output): quit(2);return
	var content: HospitalContent = HospitalContent.new()
	var start: int = Time.get_ticks_usec()
	var a: RefCounted = load("res://prefix-original-v1.gd").new(content,640,"wide")
	var original_us: int = Time.get_ticks_usec()-start
	start=Time.get_ticks_usec()
	var b: RefCounted = load("res://prefix-candidate-v1.gd").new(content,640,"wide")
	var candidate_us: int = Time.get_ticks_usec()-start
	var ok: bool = var_to_bytes(a.world.freeze())==var_to_bytes(b.world.freeze()) and a.prefix_trace==b.prefix_trace and a._position_next==b._position_next and a.errors==b.errors and a.world.facts.staff.size()==3
	var f: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	f.store_string(JSON.stringify({"ok":ok,"facts_rng_exact":var_to_bytes(a.world.freeze())==var_to_bytes(b.world.freeze()),"trace_equal":a.prefix_trace==b.prefix_trace,"trace":a.prefix_trace,"original_us":original_us,"candidate_us":candidate_us,"staff":3,"formal_requested_load":640,"legal_input":false,"scope":"Only original constructor first3staff prefix; all64rooms/128facilities/1200props retained. Not a workload or formal performance sample."},"\t"));f.close();quit(0 if ok else 1)
