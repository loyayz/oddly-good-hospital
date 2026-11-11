extends SceneTree

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size()<2 or FileAccess.file_exists(arguments[0]): push_error("Use a new output path and explicit MASK selectors");quit(2);return
	var selected: Array = []
	for argument: String in arguments.slice(1):
		for id: String in argument.split(","): selected.append(id)
	var result: Dictionary = preload("res://tests/acceptance/resident_static_rectangle.gd").new().run(HospitalContent.new(),selected)
	var file: FileAccess = FileAccess.open(arguments[0],FileAccess.WRITE)
	if file==null: push_error("Cannot write static rectangle contract result");quit(2);return
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("RESIDENT_STATIC_RECTANGLE="+str(result.ok))
	quit(0 if result.ok else 1)
