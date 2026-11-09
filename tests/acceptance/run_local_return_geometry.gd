extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var result:Dictionary=load("res://tests/acceptance/local_return_geometry.gd").new().run(HospitalContent.new())
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));quit(0 if result.ok else 1)
