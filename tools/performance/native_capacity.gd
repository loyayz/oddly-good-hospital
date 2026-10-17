extends SceneTree

const F = preload("res://game/arrivals/exact_fraction.gd")

func _initialize() -> void:
	var input: String = ""
	var output: String = "res://native-capacity.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="): input = argument.trim_prefix("--input=")
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	var file: FileAccess = FileAccess.open(input,FileAccess.READ)
	var saved: Dictionary = file.get_var()
	file.close()
	var backend: RefCounted = ClassDB.instantiate("PlatformArrivalCapacity")
	var samples: Array = []
	var started: int = Time.get_ticks_usec()
	var initial: Dictionary = backend.call("prepare",saved.classes,saved.budgets)
	samples.append({"operation":"prepare","elapsed_ms":(Time.get_ticks_usec()-started)/1000.0,"capacity":initial.get("capacity",{}),"error":initial.get("error","")})
	if initial.has("error"):
		print("NATIVE_CAPACITY="+JSON.stringify(samples))
		quit(1)
		return
	var half: Dictionary = {}
	for resource: String in saved.budgets: half[resource] = F.mul(F.from_value(saved.budgets[resource]),F.make(1,2))
	var valid: bool = true
	for operation: String in ["unchanged","half_budgets","restored"]:
		var budgets: Dictionary = half if operation=="half_budgets" else saved.budgets
		started = Time.get_ticks_usec()
		var result: Dictionary = backend.call("solve",budgets)
		var elapsed_ms: float = (Time.get_ticks_usec()-started)/1000.0
		var expected: Dictionary = F.mul(initial.capacity,F.make(1,2)) if operation=="half_budgets" else initial.capacity
		valid = valid and not result.has("error") and result.get("capacity",{})==expected
		samples.append({"operation":operation,"elapsed_ms":elapsed_ms,"capacity":result.get("capacity",{}),"error":result.get("error","")})
	var report: Dictionary = {"diagnostic":true,"classes":saved.classes.size(),"samples":samples,"valid":valid,
		"input_sha256":FileAccess.get_sha256(input),"script_sha256":FileAccess.get_sha256("res://tools/performance/native_capacity.gd"),
		"native_sha256":FileAccess.get_sha256("res://game/platform/windows/bin/oddly_good_platform.windows.x86_64.dll"),"engine":Engine.get_version_info().string}
	var result_file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	result_file.store_string(JSON.stringify(report,"\t"))
	print("NATIVE_CAPACITY="+JSON.stringify(report))
	quit(0 if valid else 1)
