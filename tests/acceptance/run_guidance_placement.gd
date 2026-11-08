extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var result: Dictionary = preload("res://tests/acceptance/guidance_placement.gd").new().run_placement(HospitalContent.new())
	if args.size()>1:
		var input: FileAccess = FileAccess.open(args[1],FileAccess.READ)
		var envelope: Dictionary = input.get_var(false)
		input.close()
		var world: WorldState = WorldState.new(envelope.facts)
		var builder: BuildService = BuildService.new(HospitalContent.new())
		var floors: Dictionary = {}
		for facility: Dictionary in world.facts.facilities.values():
			if facility.get("definition_id","")=="SE01": floors[int(facility.floor_id)] = true
		result.input_checks = {}
		for floor_id: int in floors:
			var checked: Dictionary = builder.guidance_floor_error(world,floor_id)
			result.input_checks[str(floor_id)] = checked
			result.ok = result.ok and checked.ok
	if not args.is_empty(): FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("GUIDANCE_PLACEMENT "+JSON.stringify(result))
	quit(0 if result.ok else 1)
