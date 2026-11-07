extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.is_empty():
		push_error("Expected output JSON path and optional --case=A22/A30/A35/A37 selectors")
		quit(2);return
	var selected: Array = []
	for argument: String in arguments.slice(1):
		var id: String = argument.trim_prefix("--case=")
		if not id in ["A22","A30","A35","A37"] or id in selected:
			push_error("Invalid or duplicate waiting adoption selector: "+argument)
			quit(2);return
		selected.append(id)
	var result: Dictionary = preload("res://tests/acceptance/waiting_adoption.gd").new().run_adoptions(HospitalContent.new(),selected)
	FileAccess.open(arguments[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	for row: Dictionary in result.cases: print("WAITING_ADOPTION "+JSON.stringify(row))
	quit(0 if result.ok else 1)
