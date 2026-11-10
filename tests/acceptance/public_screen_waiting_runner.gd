extends SceneTree
func _initialize()->void:call_deferred("_run")
func _run()->void:
 var result:Dictionary=preload("res://tests/acceptance/public_screen_waiting.gd").new().run_cases(HospitalContent.new())
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
 print("SCREEN_WAITING ",result.passed);quit(0 if result.passed else 1)
