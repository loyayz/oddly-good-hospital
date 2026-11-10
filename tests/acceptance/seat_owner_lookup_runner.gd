extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size()<2:
		push_error("Expected output JSON and explicit SEAT-OWNER case selectors")
		quit(2)
		return
	var selected: Array = []
	for id: String in args.slice(1): selected.append(id)
	var result: Dictionary = preload("res://tests/acceptance/seat_owner_lookup.gd").new().run_cases(HospitalContent.new(),selected)
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	quit(0 if result.ok else 1)
