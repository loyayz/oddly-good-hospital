extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size()!=1: quit(2);return
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new()
	suite.content=HospitalContent.new()
	var rows: Array = []
	var ok: bool = true
	for name: String in ["h2_scratch_oracle","h3_prefix_oracle","h5_sequence_oracle","movement_detour","detour_step_proof","detour_segment_proof","detour_contact_scratch","detour_first_contact"]:
		print("H8_ENTER ",name)
		var path: String = "res://tools/performance/current/"+name+".gd" if name in ["h2_scratch_oracle","h3_prefix_oracle","h5_sequence_oracle"] else "res://tests/acceptance/"+name+".gd"
		var test: RefCounted = load(path).new()
		var begin: int = Time.get_ticks_usec()
		var result: Dictionary = test.run(suite) if name=="movement_detour" else test.run(suite.content)
		var passed: bool = result.get("passed",result.get("ok",false))
		ok=ok and passed;rows.append({"name":name,"passed":passed,"elapsed_usec":Time.get_ticks_usec()-begin,"result":result})
		var file: FileAccess = FileAccess.open(args[0],FileAccess.WRITE)
		file.store_string(JSON.stringify({"complete":rows.size()==8,"passed":ok,"rows":rows},"\t"));file.close()
		print("H8_COMPLETE ",name," ",passed)
	quit(0 if ok else 1)
