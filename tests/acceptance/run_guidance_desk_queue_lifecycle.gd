extends SceneTree
func _initialize() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var result: Dictionary=preload("res://tests/acceptance/guidance_desk_queue_lifecycle.gd").new().run_desk_queue_checks(HospitalContent.new(),not args.has("--helpers-only"))
	if args.is_empty():
		print(JSON.stringify(result))
	else:
		FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result))
	quit(0 if result.ok else 1)
