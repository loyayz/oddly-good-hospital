extends SceneTree
func _initialize()->void:
 var result: Dictionary=load("res://tests/acceptance/guidance_queue_flow.gd").new().run_geometry()
 var args=OS.get_cmdline_user_args()
 FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
 quit(0 if result.get("ok",result.get("passed",false)) else 1)
