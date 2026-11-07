extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=2 or not args[1].begins_with("--case="): quit(2);return
	var result: Dictionary=preload("res://tests/acceptance/visitor_seat_retry.gd").new().run_case(HospitalContent.new(),args[1].trim_prefix("--case="))
	FileAccess.open(args[0]+".result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(0 if result.ok else 1)
