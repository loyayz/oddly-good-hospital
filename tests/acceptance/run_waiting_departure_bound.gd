extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var content:=HospitalContent.new()
	var result: Dictionary=load("res://tests/acceptance/waiting_departure_bound.gd").new().run_focused(content)
	var suite: RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
	var regression: Dictionary=load("res://tests/acceptance/public_waiting_cost_field.gd").new().run_case(suite)
	var passed: bool=result.passed and regression.ok
	var f:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);f.store_string(JSON.stringify({"passed":passed,"bound":result,"regression":regression},"\t"));f.close();print("DEPARTURE_BOUND ",passed);quit(0 if passed else 1)
