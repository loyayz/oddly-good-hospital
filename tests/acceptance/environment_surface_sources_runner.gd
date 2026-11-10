extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size()<2: quit(2);return
	var suite: RefCounted = preload("res://tests/acceptance/environment_surface_sources.gd").new()
	var result: Dictionary = suite.run_sources(HospitalContent.new(),Array(args.slice(1)))
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(0 if result.ok else 1)
