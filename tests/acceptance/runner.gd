extends SceneTree

const SUITES: Array[String] = ["core", "clinical", "staff", "operations", "growth", "space"]
var results: Dictionary = {}
var declared: Dictionary = {}
var current_suite: String = ""
var selected_suites: Array[String] = []
var requested_cases: Array[String] = []

func wants(case_id: String) -> bool:
	return requested_cases.is_empty() or case_id in requested_cases

func _initialize() -> void:
	call_deferred("_run")

func check(case_id: String, passed: bool, details: Variant = null) -> void:
	if results.has(case_id) or not declared.has(case_id):
		push_error("Duplicate or undeclared acceptance case: "+case_id)
		passed = false
	results[case_id] = {"passed":passed,"suite":current_suite,"requirement":declared.get(case_id,""),"details":details}
	print("CASE "+case_id+" "+("PASS" if passed else "FAIL")+(" "+JSON.stringify(details) if not passed else ""))
	_save_results(false)

func _run() -> void:
	var requested: PackedStringArray = OS.get_cmdline_user_args()
	var selected: Array[String] = SUITES.duplicate()
	if not requested.is_empty():
		selected.clear()
		for argument: String in requested:
			if argument.begins_with("--case="):
				var case_id: String = argument.trim_prefix("--case=")
				if case_id.is_empty() or case_id in requested_cases:
					push_error("Empty or duplicate selected acceptance case")
					quit(2)
					return
				requested_cases.append(case_id)
			else:
				selected.append(argument)
	if not requested_cases.is_empty() and (selected.size()!=1 or not selected[0] in ["operations","space","clinical"]):
		push_error("Case selection requires one operations, space, or supported clinical suite")
		quit(2)
		return
	selected_suites = selected.duplicate()
	for suite_name: String in selected:
		if not suite_name in SUITES:
			push_error("Unknown acceptance suite: "+suite_name)
			quit(2)
			return
		current_suite = suite_name
		var script: GDScript = load("res://tests/acceptance/"+suite_name+".gd")
		if script==null or not script.can_instantiate():
			push_error("Cannot load acceptance suite: "+suite_name)
			quit(2)
			return
		var suite: RefCounted = script.new()
		for case_id: String in requested_cases:
			if not suite.CASES.has(case_id):
				push_error("Unknown selected acceptance case: "+case_id)
				quit(2)
				return
			if suite_name=="clinical" and not case_id in suite.SELECTABLE_CASES:
				push_error("Clinical case requires its complete shared chain: "+case_id)
				quit(2)
				return
		for case_id: String in suite.CASES:
			if not wants(case_id): continue
			if declared.has(case_id):
				push_error("Duplicate acceptance declaration: "+case_id)
				quit(2)
				return
			declared[case_id] = suite.CASES[case_id]
		var started: int = Time.get_ticks_msec()
		print("SUITE_BEGIN "+suite_name)
		if suite_name=="clinical" and not requested_cases.is_empty():
			await suite.run_selected(self,requested_cases)
		else:
			await suite.run(self)
		for case_id: String in suite.CASES:
			if wants(case_id) and not results.has(case_id): check(case_id,false,"Case did not complete")
		print("SUITE "+suite_name+" elapsed_ms="+str(Time.get_ticks_msec()-started))
	var failed: int = 0
	for result: Dictionary in results.values():
		if not result.passed: failed += 1
	_save_results(true)
	print("ACCEPTANCE checks="+str(results.size())+" failed="+str(failed))
	quit(0 if failed==0 else 1)

func _save_results(completed: bool) -> void:
	var failed: int = 0
	for result: Dictionary in results.values():
		if not result.passed: failed += 1
	var report: Dictionary = {"suites":selected_suites,"requested_cases":requested_cases,"completed":completed,"declared":declared.size(),"checks":results.size(),"failed":failed,"results":results,"engine":Engine.get_version_info().string,"profile":OS.get_user_data_dir()}
	var file: FileAccess = FileAccess.open("res://acceptance-results.json",FileAccess.WRITE)
	if file==null:
		push_error("Cannot write acceptance results")
		quit(2)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
