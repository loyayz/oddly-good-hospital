extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var result: Dictionary=preload("res://tests/acceptance/visitor_seat_no_area.gd").new().run_no_area(HospitalContent.new())
	FileAccess.open(args[0]+".result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(0 if result.ok else 1)
