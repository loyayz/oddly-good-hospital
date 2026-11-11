extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()<2:
		push_error("Output path and explicit BED-INDEX selectors required");quit(2);return
	if FileAccess.file_exists(args[0]): quit(2);return
	var result: Dictionary=preload("res://tests/acceptance/bed_destination_index.gd").new().run_cases(HospitalContent.new(),Array(args.slice(1)))
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify({"ok":result.get("ok",false),"cases":result.get("cases",[]).map(func(row: Dictionary)->Dictionary:return {"id":row.id,"ok":row.ok,"failed":row.failed})}))
	quit(0 if result.get("ok",false) else 1)
