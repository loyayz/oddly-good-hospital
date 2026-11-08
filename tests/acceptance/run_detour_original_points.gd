extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var args:=OS.get_cmdline_user_args()
 if args.size()!=1:push_error("usage: output.json");quit(2);return
 var result: Dictionary=preload("res://tests/acceptance/detour_original_points.gd").new().run(HospitalContent.new())
 FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
 print("DETOUR_ORIGINAL_POINTS "+JSON.stringify(result));quit(0 if result.ok else 1)
