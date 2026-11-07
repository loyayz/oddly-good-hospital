extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var selected: Array = []
	for arg: String in args.slice(1): selected.append(arg.trim_prefix("--case="))
	var row: Dictionary = preload("res://tests/acceptance/guidance_target_reselection.gd").new().run_reselection(HospitalContent.new(),selected)
	if not args.is_empty(): FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(row,"\t"))
	print("GUIDANCE_TARGET_RESELECTION "+JSON.stringify(row));quit(0 if row.ok else 1)
