extends SceneTree

# H1 affected contracts only: borrowed navigation source, cache budget/lifecycle,
# topology projections and real detour consumers. Independent ownership oracle
# is executed separately; this runner does not replace it or full acceptance.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size()!=1:
		push_error("Expected absolute JSON output path")
		quit(2)
		return
	var output: String = args[0]
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new()
	suite.content = HospitalContent.new()
	var rows: Array = []
	var passed: bool = true
	var start: int = Time.get_ticks_usec()
	for name: String in ["navigation_source_lifecycle","navigation_static_versions","floor_static_loading","navigation_topology_projection","movement_detour","detour_step_proof","detour_segment_proof"]:
		print("H1_TEST_ENTER ",name)
		var test: RefCounted = load("res://tests/acceptance/"+name+".gd").new()
		var begin: int = Time.get_ticks_usec()
		var result: Dictionary
		match name:
			"navigation_source_lifecycle", "floor_static_loading": result = test.run_case(suite)
			"navigation_static_versions": result = test.run()
			"detour_step_proof", "detour_segment_proof": result = test.run(suite.content)
			_: result = test.run(suite)
		var ok: bool = bool(result.get("ok",result.get("passed",false)))
		rows.append({"name":name,"passed":ok,"elapsed_usec":Time.get_ticks_usec()-begin,"result":result})
		passed = passed and ok
		var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
		file.store_string(JSON.stringify({"complete":rows.size()==7,"passed":passed,"elapsed_usec":Time.get_ticks_usec()-start,"rows":rows},"\t"))
		file.close()
		print("H1_TEST_COMPLETE ",name," ",ok)
	quit(0 if passed else 1)
