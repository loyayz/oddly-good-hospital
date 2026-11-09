extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var result:Dictionary=preload("res://tests/acceptance/local_only_movement.gd").new().run_local(HospitalContent.new())
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print(JSON.stringify(result));quit(0 if result.ok else 1)
