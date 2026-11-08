extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	if OS.get_cmdline_user_args().size()!=1: quit(2);return
	var result: Dictionary=load("res://tests/acceptance/native_waiting_dispatch.gd").new().run(HospitalContent.new(),true)
	var f:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"));f.close()
	print("NATIVE_WAITING_FAILURE ",result.ok);quit(0 if result.ok else 1)
