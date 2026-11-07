extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var output: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if output.is_empty() or FileAccess.file_exists(output): quit(2);return
	var content: HospitalContent = HospitalContent.new()
	var results: Dictionary = {}
	var passed: bool = true
	for name: String in ["detour_step_proof","detour_segment_proof","movement_detour"]:
		print("SELECTED_BEGIN="+name)
		var started: int = Time.get_ticks_usec()
		var test: RefCounted = load("res://tests/acceptance/"+name+".gd").new()
		var result: Dictionary
		if name=="movement_detour":
			var suite: RefCounted = load("res://tests/acceptance/space.gd").new();suite.content=content
			result=test.run(suite)
		else: result=test.run(content)
		result.elapsed_us=Time.get_ticks_usec()-started
		results[name]=result;passed=passed and bool(result.get("passed",result.get("ok",false)))
		var f: FileAccess = FileAccess.open(output,FileAccess.WRITE);f.store_string(JSON.stringify({"complete":false,"results":results},"\t"));f.close()
		print("SELECTED_END="+name+" "+str(passed))
	var f: FileAccess = FileAccess.open(output,FileAccess.WRITE);f.store_string(JSON.stringify({"complete":true,"passed":passed,"results":results},"\t"));f.close()
	quit(0 if passed else 1)
