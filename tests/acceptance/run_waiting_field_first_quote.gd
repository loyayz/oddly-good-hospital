extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var content:=HospitalContent.new()
	var targeted: Dictionary=load("res://tests/acceptance/waiting_field_first_quote.gd").new().run_focused(content)
	var regression: Dictionary=load("res://tests/acceptance/public_entry_field_prune.gd").new().run_selected(content)
	var passed: bool=targeted.passed and regression.passed
	var f:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);f.store_string(JSON.stringify({"passed":passed,"targeted":targeted,"regression":regression},"\t"));f.close();print("FIRST_QUOTE ",passed);quit(0 if passed else 1)
