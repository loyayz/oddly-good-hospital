extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size()<2:
		push_error("Expected output JSON and explicit WAIT-ENV-CONSUMERS , WAIT-ENV-LIVE or WAIT-ENV-SUMMARY selectors")
		quit(2)
		return
	var result: Dictionary = preload("res://tests/acceptance/waiting_environment_sample.gd").new().run_cases(HospitalContent.new(),Array(args.slice(1)))
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	quit(0 if result.ok else 1)
