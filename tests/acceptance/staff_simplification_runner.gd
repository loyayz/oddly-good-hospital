extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var content: HospitalContent = HospitalContent.new()
	if not content.error.is_empty():
		print("CONTENT_ERROR "+content.error);quit(2);return
	var result: Dictionary = preload("res://tests/acceptance/staff_simplification.gd").new().run_simplification(content)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty(): FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("STAFF_SIMPLIFICATION "+JSON.stringify(result))
	quit(0 if result.get("ok",false) else 1)
