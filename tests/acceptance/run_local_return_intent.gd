extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var result: Dictionary=preload("res://tests/acceptance/local_return_intent.gd").new().run(HospitalContent.new())
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("LOCAL_RETURN_INTENT "+str(result.ok))
	quit(0 if result.ok else 1)
