extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1: quit(2);return
	var content: HospitalContent=HospitalContent.new()
	var predicate: Dictionary=load("res://tests/acceptance/waiting_target_occupancy.gd").new().run(content)
	var race: Dictionary=load("res://tests/acceptance/waiting_followup.gd").new().run_followups(content,["A23"])
	var ok: bool=predicate.passed and race.ok
	var file: FileAccess=FileAccess.open(args[0],FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":ok,"predicate":predicate,"actual_seat_race":race},"\t"));file.close()
	print("H10_FUNCTIONAL ",ok)
	quit(0 if ok else 1)
