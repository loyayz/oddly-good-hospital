extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var suite=load("res://tests/acceptance/waiting_need_scan.gd").new()
	var content:=HospitalContent.new()
	var normal: Dictionary=suite.run(content,false)
	var mutation: Dictionary=suite.run(content,true)
	var passed: bool=normal.ok and mutation.ok
	var f:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);f.store_string(JSON.stringify({"passed":passed,"normal":normal,"mutation":mutation},"\t"));f.close()
	print("WAITING_NEED_SCAN ",passed);quit(0 if passed else 1)
