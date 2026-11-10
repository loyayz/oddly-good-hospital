extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var args: PackedStringArray=OS.get_cmdline_user_args()
 var result: Dictionary=preload("res://tests/acceptance/guidance_need_return.gd").new().run_need_return(HospitalContent.new(),Array(args.slice(1)))
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
 quit(0 if result.passed else 1)
