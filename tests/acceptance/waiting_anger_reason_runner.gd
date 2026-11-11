extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()<2:push_error("Expected output JSON and explicit ANGER-SEAT selectors");quit(2);return
	var c:HospitalContent=HospitalContent.new()
	var suite:RefCounted=preload("res://tests/acceptance/waiting_anger_reason.gd").new()
	var selectors:Array=[];var input:String=""
	for arg:String in args.slice(1):
		if arg.begins_with("--family-input="):input=arg.trim_prefix("--family-input=")
		else:selectors.append(arg)
	if not input.is_empty():
		var file:FileAccess=FileAccess.open(input,FileAccess.READ);suite.friend_family_input=file.get_var(false);file.close()
		if suite.friend_family_input.content_fingerprint!=c.content_fingerprint:quit(2);return
		suite.friend_family_source={"path":input,"sha256":FileAccess.get_sha256(input)}
	var result:Dictionary=suite.run_cases_selected(c,selectors)
	if not input.is_empty():result.original_family_file_unchanged=FileAccess.get_sha256(input)==suite.friend_family_source.sha256;result.ok=result.ok and result.original_family_file_unchanged
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(0 if result.ok else 1)
