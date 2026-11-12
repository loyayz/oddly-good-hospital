extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var output: String=OS.get_cmdline_user_args()[0]
	var result: Dictionary=preload("res://tests/acceptance/door_reach_same_instance.gd").new().run_reach(HospitalContent.new(),output)
	var f: FileAccess=FileAccess.open(output,FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"));f.close()
	quit(0 if result.ok else 1)
