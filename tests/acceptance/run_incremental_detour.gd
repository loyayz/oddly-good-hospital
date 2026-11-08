extends SceneTree
# Reproducible entry: godot --headless --path . --script
# res://tests/acceptance/run_incremental_detour.gd -- /absolute/output.json
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	if OS.get_cmdline_user_args().size()!=1: push_error("Expected one output JSON path");quit(2);return
	var suite: RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=HospitalContent.new()
	var tests: RefCounted=load("res://tests/acceptance/movement_detour.gd").new()
	var rows: Array=[]
	rows.append(tests._head_on(suite,false));rows.append(tests._head_on(suite,true));rows.append(tests._head_on(suite,false,true))
	rows.append(tests._stationary(suite,false));rows.append(tests._stationary(suite,true))
	rows.append(tests._backward(suite,false,false));rows.append(tests._backward(suite,true,false));rows.append(tests._backward(suite,true,true));rows.append(tests._backward(suite,true,false,true))
	rows.append(tests._convoy_cannot_back_into_tail(suite));rows.append(tests._double_corner_rejoin(suite))
	for name: String in ["46","53","56","57"]:
		var row: Dictionary=suite.call("_case_"+name,null);row.case="SPACE-"+name;rows.append(row)
	var new_cases: Dictionary=load("res://tests/acceptance/incremental_detour.gd").new().run(suite)
	rows.append_array(new_cases.cases)
	var ok: bool=true
	for row: Dictionary in rows:ok=ok and row.get("passed",row.get("ok",false))
	var f:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);f.store_string(JSON.stringify({"passed":ok,"rows":rows},"\t"));f.close()
	print("INCREMENTAL_ALL_CASES ",ok);quit(0 if ok else 1)
