extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var args: PackedStringArray=OS.get_cmdline_user_args()
 if args.size()<2:push_error("Output JSON and explicit LOCAL-CORNER-WIDE or LOCAL-CORNER-LOST required");quit(2);return
 var result: Dictionary=load("res://tests/acceptance/local_obstacle_corners.gd").new().run(HospitalContent.new(),Array(args.slice(1)))
 FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print(JSON.stringify(result));quit(0 if result.ok else 1)
