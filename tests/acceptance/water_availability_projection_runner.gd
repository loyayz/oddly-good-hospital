extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()<2: quit(2);return
	var suite: RefCounted=preload("res://tests/acceptance/water_availability_projection.gd").new();var selectors: Array=[];var input: String=""
	for arg: String in args.slice(1):
		if arg.begins_with("--family-input="): input=arg.trim_prefix("--family-input=")
		else: selectors.append(arg)
	if not input.is_empty():
		var file: FileAccess=FileAccess.open(input,FileAccess.READ);suite.family_input=file.get_var(false);file.close()
		suite.family_source={"path":input,"sha256":FileAccess.get_sha256(input)}
	var content: HospitalContent=HospitalContent.new()
	if not input.is_empty() and suite.family_input.content_fingerprint!=content.content_fingerprint: quit(2);return
	var result: Dictionary=suite.run_selected(content,selectors)
	if not input.is_empty(): result.original_family_file_unchanged=FileAccess.get_sha256(input)==suite.family_source.sha256;result.ok=result.ok and result.original_family_file_unchanged
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));quit(0 if result.ok else 1)
