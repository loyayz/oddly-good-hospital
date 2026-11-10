extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size()<2:
		push_error("Expected output JSON and explicit ENV-WALL-LAYOUT, ENV-WALL-DOOR or ENV-WALL-LOCAL selectors")
		quit(2)
		return
	var result: Dictionary = preload("res://tests/acceptance/environment_wall_lookup.gd").new().run_wall_cases(HospitalContent.new(),Array(args.slice(1)))
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	quit(0 if result.ok else 1)
