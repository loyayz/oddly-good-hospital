extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var input: String=""
	var restore_trip: bool=false
	for arg: String in args.slice(1):
		if arg.begins_with("--input="): input=arg.trim_prefix("--input=")
		elif arg=="--case=VISITOR-SEAT-RESTORE": restore_trip=true
		elif arg!="--case=VISITOR-SEAT-LOST": push_error("Unknown case/argument: "+arg);quit(2);return
	var result: Dictionary=preload("res://tests/acceptance/visitor_seat_competition.gd").new().run_competition(HospitalContent.new(),args[0],input,restore_trip)
	FileAccess.open(args[0]+".result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(0 if result.ok else 1)
