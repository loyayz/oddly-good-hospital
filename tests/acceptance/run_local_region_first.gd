extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var result: Dictionary=load("res://tests/acceptance/local_region_first.gd").new().run_focused(HospitalContent.new())
	var f:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"));f.close();print(result);quit(0 if result.passed else 1)
