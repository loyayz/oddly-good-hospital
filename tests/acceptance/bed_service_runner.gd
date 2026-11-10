extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()<2:push_error("Evidence directory and CLINICAL/REPAIR required");quit(2);return
	var result: Dictionary=await preload("res://tests/acceptance/bed_service.gd").new().run_selected(self,args[0],Array(args.slice(1)))
	FileAccess.open(args[0].path_join("bed_service_result.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print("BED_SERVICE_RESULT "+JSON.stringify(result));quit(0 if result.get("ok",false) else 1)
