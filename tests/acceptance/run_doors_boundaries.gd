extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.is_empty(): quit(2);return
	var result: Dictionary=preload("res://tests/acceptance/doors_local_boundaries.gd").new().run_boundaries(HospitalContent.new())
	result["passed"]=bool(result.ok)
	var file: FileAccess=FileAccess.open(args[0],FileAccess.WRITE)
	if file==null: quit(2);return
	file.store_string(JSON.stringify(result,"\t"));file.close()
	quit(0 if result.ok else 2)
