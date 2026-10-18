extends SceneTree

const SUITES: Array[String] = ["core", "clinical", "staff", "operations", "growth", "space"]
const Checkpoints = preload("res://tests/acceptance/checkpoints.gd")
var results: Dictionary = {}
var declared: Dictionary = {}
var current_suite: String = ""
var selected_suites: Array[String] = []
var requested_cases: Array[String] = []
var _stores: Array = []
var _case_started: int = 0
var _setup_ms: int = 0
var _fixture_offsets: Array = []
var _started: int = Time.get_ticks_msec()
var _suite_results: Dictionary = {}

func checkpoints(content: HospitalContent, builder: String, producer: RefCounted = null) -> RefCounted:
	var store: RefCounted = Checkpoints.new(content,builder,weakref(producer) if producer!=null else null)
	_stores.append(store)
	return store

func begin_case(case_id: String) -> void:
	_case_started = Time.get_ticks_msec()
	_setup_ms = 0
	_fixture_offsets.clear()
	for store: RefCounted in _stores: _fixture_offsets.append(store.observations.size())
	print("CASE_BEGIN "+case_id)

func preparation_elapsed(started: int) -> void:
	_setup_ms += Time.get_ticks_msec()-started

func wants(case_id: String) -> bool:
	return requested_cases.is_empty() or case_id in requested_cases

func _initialize() -> void:
	call_deferred("_run")

func check(case_id: String, passed: bool, details: Variant = null) -> void:
	if results.has(case_id) or not declared.has(case_id):
		push_error("Duplicate or undeclared acceptance case: "+case_id)
		passed = false
	var elapsed: int = Time.get_ticks_msec()-_case_started
	var fixtures: Array = []
	for index: int in _stores.size():
		fixtures.append_array(_stores[index].observations.slice(_fixture_offsets[index] if index<_fixture_offsets.size() else 0))
	results[case_id] = {"passed":passed,"suite":current_suite,"requirement":declared.get(case_id,""),"details":details,"elapsed_ms":elapsed,"setup_ms":_setup_ms,"body_ms":maxi(0,elapsed-_setup_ms),"fixtures":fixtures}
	print("CASE "+case_id+" "+("PASS" if passed else "FAIL")+(" "+JSON.stringify(details) if not passed else ""))
	_save_results(false)

func _run() -> void:
	var requested: PackedStringArray = OS.get_cmdline_user_args()
	if requested.is_empty():
		push_error("Explicit acceptance scope required; use -Case, -Suite or -All through run-acceptance.ps1")
		quit(2)
		return
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
	if selected.is_empty() or selected.size()!=_unique(selected).size():
		push_error("Empty or duplicate acceptance suites")
		quit(2)
		return
	selected_suites = selected.duplicate()
	var suites: Dictionary = {}
	for suite_name: String in selected:
		if not suite_name in SUITES:
			push_error("Unknown acceptance suite: "+suite_name)
			quit(2)
			return
		var script: GDScript = load("res://tests/acceptance/"+suite_name+".gd")
		if script==null or not script.can_instantiate():
			push_error("Cannot load acceptance suite: "+suite_name)
			quit(2)
			return
		var suite: RefCounted = script.new()
		suites[suite_name] = suite
		for case_id: String in suite.CASES:
			if not wants(case_id): continue
			if declared.has(case_id):
				push_error("Duplicate acceptance declaration: "+case_id)
				quit(2)
				return
			declared[case_id] = suite.CASES[case_id]
	for case_id: String in requested_cases:
		if not declared.has(case_id):
			push_error("Unknown case or case outside selected suites: "+case_id)
			quit(2)
			return
	for suite_name: String in selected:
		var suite: RefCounted = suites[suite_name]
		var any_selected: bool = false
		for case_id: String in suite.CASES: any_selected = any_selected or wants(case_id)
		if not any_selected: continue
		current_suite = suite_name
		var started: int = Time.get_ticks_msec()
		print("SUITE_BEGIN "+suite_name)
		await suite.run(self)
		for case_id: String in suite.CASES:
			if wants(case_id) and not results.has(case_id): check(case_id,false,"Case did not complete")
		var suite_failed: int = 0
		var suite_checks: int = 0
		for result: Dictionary in results.values():
			if result.suite!=suite_name: continue
			suite_checks += 1
			if not result.passed: suite_failed += 1
		_suite_results[suite_name] = {"elapsed_ms":Time.get_ticks_msec()-started,"checks":suite_checks,"failed":suite_failed}
		print("SUITE "+suite_name+" elapsed_ms="+str(_suite_results[suite_name].elapsed_ms))
		_save_results(false)
	var failed: int = 0
	for result: Dictionary in results.values():
		if not result.passed: failed += 1
	_save_results(true)
	print("ACCEPTANCE checks="+str(results.size())+" failed="+str(failed))
	quit(0 if failed==0 else 1)

func _unique(values: Array[String]) -> Array[String]:
	var unique: Array[String] = []
	for value: String in values:
		if not value in unique: unique.append(value)
	return unique

func _save_results(completed: bool) -> void:
	var failed: int = 0
	for result: Dictionary in results.values():
		if not result.passed: failed += 1
	var report: Dictionary = {"suites":selected_suites,"suite_results":_suite_results,"elapsed_ms":Time.get_ticks_msec()-_started,"requested_cases":requested_cases,"completed":completed,"declared":declared.size(),"checks":results.size(),"failed":failed,"results":results,"engine":Engine.get_version_info().string,"profile":OS.get_user_data_dir()}
	var file: FileAccess = FileAccess.open("res://acceptance-results.json",FileAccess.WRITE)
	if file==null:
		push_error("Cannot write acceptance results")
		quit(2)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
