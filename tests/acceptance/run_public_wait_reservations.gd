extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var result: Dictionary=load("res://tests/acceptance/public_wait_reservations.gd").new().run_focused(HospitalContent.new())
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1: push_error("Expected output JSON path");quit(2);return
	var file:=FileAccess.open(args[0],FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"));file.close()
	print("PUBLIC_WAIT_RESERVATIONS ",result.passed)
	quit(0 if result.passed else 1)
