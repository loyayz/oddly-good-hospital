extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var result: Dictionary = preload("res://tests/acceptance/waiting_need_deadline.gd").new().run_deadline_cases(HospitalContent.new(),args[0],args[1])
	FileAccess.open(args[1]+".result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(0 if result.ok else 1)
