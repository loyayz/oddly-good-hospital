extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var args:=OS.get_cmdline_user_args()
	var f:=FileAccess.open(args[0],FileAccess.READ)
	var envelope: Dictionary=f.get_var(false);f.close()
	var content:=HospitalContent.new()
	var result: Dictionary=load("res://tests/acceptance/entry_geometry_key.gd").new().run(content,WorldState.new(envelope.facts))
	f=FileAccess.open(args[1],FileAccess.WRITE);f.store_string(JSON.stringify(result));f.close()
	print(result);quit(0 if result.passed else 1)
