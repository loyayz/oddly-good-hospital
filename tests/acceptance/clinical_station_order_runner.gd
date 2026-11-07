extends SceneTree
# Run with -- result.json STATION-READY-ID STATION-FALLBACK STATION-OWNERSHIP.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size()<2:
		push_error("Explicit output and selected case IDs required")
		quit(2);return
	var selected: Array = []
	for arg: String in args.slice(1): selected.append(arg.trim_prefix("--case="))
	var result: Dictionary = preload("res://tests/acceptance/clinical_station_order.gd").new().run_order(HospitalContent.new(),selected,args[0].trim_suffix(".json"))
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("CLINICAL_STATION_ORDER "+JSON.stringify(result))
	quit(0 if result.ok else 1)
