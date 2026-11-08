extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1:push_error("Expected result JSON path");quit(2);return
	var result: Dictionary=preload("res://tests/acceptance/guidance_cross_floor_exit.gd").new().run_exits(HospitalContent.new())
	var file: FileAccess=FileAccess.open(args[0],FileAccess.WRITE)
	if file==null:push_error("Cannot open result JSON");quit(2);return
	file.store_string(JSON.stringify(result,"\t"));file.close()
	quit(0 if result.passed else 1)
