extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var result: Dictionary = preload("res://tests/acceptance/waiting_friend_eligibility.gd").new().run_friend_cases(HospitalContent.new(),args[0])
	FileAccess.open(args[0]+".result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("WAITING_FRIEND_ELIGIBILITY "+JSON.stringify(result))
	quit(0 if result.ok else 1)
