extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()<2:push_error("Output JSON and explicit LIVE/RESTORE selectors required");quit(2);return
	var result: Dictionary=await preload("res://tests/acceptance/clinical_full_chain.gd").new().run_selected(self,Array(args.slice(1)))
	var file: FileAccess=FileAccess.open(args[0],FileAccess.WRITE)
	if file==null:push_error("Cannot write clinical chain report");quit(2);return
	file.store_string(JSON.stringify(result,"\t"))
	print("CLINICAL_FULL_CHAIN "+JSON.stringify(result));quit(0 if result.get("ok",false) else 1)
