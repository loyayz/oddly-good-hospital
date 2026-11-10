extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if args.size()<2:push_error("Expected output path and NEED-CHOICES selectors");quit(2);return
	var c:HospitalContent=HospitalContent.new()
	var result:Dictionary=preload("res://tests/acceptance/waiting_need_choices.gd").new().run_selected(c,Array(args.slice(1)))
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print(JSON.stringify(result));quit(0 if result.ok else 1)
