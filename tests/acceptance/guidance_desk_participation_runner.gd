extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var selected: Array = []
	for arg: String in args.slice(1): selected.append(arg.trim_prefix("--case="))
	var result: Dictionary = preload("res://tests/acceptance/guidance_desk_participation.gd").new().run_participation(HospitalContent.new(),selected)
	if not args.is_empty(): FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("GUIDANCE_DESK_PARTICIPATION "+JSON.stringify(result))
	quit(0 if result.ok else 1)
