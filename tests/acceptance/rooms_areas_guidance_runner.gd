extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var selected: Array=[]
	var output: String=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): selected.append(arg.trim_prefix("--case="))
		elif arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	var result: Dictionary=preload("res://tests/acceptance/rooms_areas_guidance.gd").new().run_cases(HospitalContent.new(),selected)
	if not output.is_empty(): FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("ROOMS_AREAS_GUIDANCE "+JSON.stringify(result))
	quit(0 if result.get("ok",false) else 1)
