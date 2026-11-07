extends SceneTree
const Fixture = preload("res://tools/performance/fixture.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var output: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	if output.is_empty() or FileAccess.file_exists(output):
		push_error("Expected new --output absolute JSON path")
		quit(2)
		return
	print("DIAGNOSTIC640_DRIVER=content_enter")
	var content: HospitalContent = HospitalContent.new()
	if not content.error.is_empty():
		push_error(content.error)
		quit(2)
		return
	print("DIAGNOSTIC640_DRIVER=fixture_enter")
	var fixture: RefCounted = Fixture.new(content,640,"wide")
	var report: Dictionary = {"diagnostic_only":true,"legal_input_qualified":false,"performance_pass":null,"simulation_steps_run":0,"construction_returned":true,"description":fixture.describe(),"errors":fixture.errors.duplicate(),"content_fingerprint":content.content_fingerprint}
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	if file==null:
		push_error("Cannot write diagnostic output")
		quit(2)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("DIAGNOSTIC640_DRIVER="+JSON.stringify(report))
	quit(0 if fixture.errors.is_empty() else 1)
