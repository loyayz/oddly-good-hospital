extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size()!=1:
		push_error("An output JSON path is required")
		quit(2)
		return
	var suite: RefCounted = preload("res://tests/acceptance/public_select_type_index.gd").new()
	var content: HospitalContent = HospitalContent.new()
	var result: Dictionary = {"type_index":suite.run_index_case(content),"selection_boundaries":suite.run_case(content)}
	result.ok = result.type_index.ok and result.selection_boundaries.ok
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("PUBLIC_SELECT_TYPE_INDEX ",result.ok)
	quit(0 if result.ok else 1)
