extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()<2:push_error("Output JSON and explicit BED-PASS/BED-CLAIM/BED-COLLISION/BED-EXPAND/BED-RELEASE/BED-GROUP/BED-LOCAL/BED-CANDIDATE/BED-TRANSIT/BED-RESTORE/BED-FACING/BED-BLUEPRINT required");quit(2);return
	var result: Dictionary=preload("res://tests/acceptance/bed_passage.gd").new().run_cases(HospitalContent.new(),Array(args.slice(1)))
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print(JSON.stringify(result));quit(0 if result.get("ok",false) else 1)
