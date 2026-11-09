extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var args:=OS.get_cmdline_user_args()
 var result:Dictionary=preload("res://tests/acceptance/unified_local_behavior.gd").new().run_focus(HospitalContent.new()) if args.size()>1 and args[1]=="focus" else preload("res://tests/acceptance/unified_local_behavior.gd").new().run(HospitalContent.new())
 FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print(JSON.stringify(result));quit(0 if result.ok else 1)
