extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size()!=1:
		push_error("Expected output JSON path")
		quit(2)
		return
	var started: int = Time.get_ticks_usec()
	var result: Dictionary = load("res://tests/acceptance/prepared_waiting_fields.gd").new().run_failure_contract(HospitalContent.new())
	result.elapsed_ms = float(Time.get_ticks_usec()-started)/1000.0
	var file: FileAccess = FileAccess.open(args[0],FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("PREPARED_WAITING_FAILURE ",result.ok)
	quit(0 if result.ok else 1)
