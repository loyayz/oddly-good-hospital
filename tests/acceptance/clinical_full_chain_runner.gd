extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()<2:push_error("Output JSON and explicit OUTPATIENT/SURGERY/LIVE/RESTORE selectors required");quit(2);return
	if FileAccess.file_exists(args[0]):push_error("Preserve existing clinical chain evidence; choose a new output path");quit(2);return
	var result: Dictionary=await preload("res://tests/acceptance/clinical_full_chain.gd").new().run_selected(self,Array(args.slice(1)))
	var file: FileAccess=FileAccess.open(args[0],FileAccess.WRITE)
	if file==null:push_error("Cannot write clinical chain report");quit(2);return
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	var rows: Array = []
	for row: Dictionary in result.get("cases",[]): rows.append({"case":row.case,"ok":row.ok,"checks":row.checks,"body_ms":row.body_ms,"final_tick":row.final_tick,"errors":row.errors})
	print("CLINICAL_FULL_CHAIN "+JSON.stringify({"ok":result.get("ok",false),"cases":rows,"detailed_result":args[0]}));quit(0 if result.get("ok",false) else 1)
