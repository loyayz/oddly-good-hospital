extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size()<2:
		print("Usage: OUTPUT.json ENV-SESSION-CASE [...]");quit(2);return
	var suite: RefCounted = preload("res://tests/acceptance/environment_session_sources.gd").new()
	suite.evidence_directory = args[0].get_base_dir()
	var result: Dictionary = await suite.run_session_sources(self,HospitalContent.new(),Array(args.slice(1)))
	var file: FileAccess = FileAccess.open(args[0],FileAccess.WRITE)
	if file==null: push_error("Cannot write selected results: "+args[0]);quit(2);return
	file.store_string(JSON.stringify(result,"\t"));file.close()
	print(JSON.stringify(result));quit(0 if result.ok else 1)
