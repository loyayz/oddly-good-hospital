extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size()!=1:
		push_error("Expected a result JSON path")
		quit(2)
		return
	var suite: RefCounted = preload("res://tests/acceptance/space.gd").new()
	suite.content = HospitalContent.new()
	var result: Dictionary = preload("res://tests/acceptance/guidance_route_cache.gd").new().run_case(suite)
	FileAccess.open(arguments[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("GUIDANCE_ROUTE_CACHE "+JSON.stringify(result))
	quit(0 if result.ok else 1)
