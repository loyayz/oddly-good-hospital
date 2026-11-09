extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var result:Dictionary=preload("res://tests/acceptance/guidance_snake_geometry.gd").new().run_checks()
 var args:=OS.get_cmdline_user_args()
 if not args.is_empty():FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
 print(JSON.stringify(result));quit(0 if result.ok else 1)
