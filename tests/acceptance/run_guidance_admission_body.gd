extends SceneTree
func _initialize() -> void:
	var result: Dictionary=preload("res://tests/acceptance/guidance_admission_body.gd").new().run_rules(HospitalContent.new())
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.is_empty():print(JSON.stringify(result))
	else:FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result))
	quit(0 if result.ok else 1)
