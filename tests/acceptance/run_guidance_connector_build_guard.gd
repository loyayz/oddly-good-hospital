extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var result: Dictionary=preload("res://tests/acceptance/guidance_connector_build_guard.gd").new().run_connector_guard(HospitalContent.new())
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
 quit(0 if result.passed else 1)
