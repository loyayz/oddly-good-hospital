extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var args:=OS.get_cmdline_user_args()
 if args.size()!=2:push_error("usage: v18-continuation.final.bin output.json");quit(2);return
 var input:=FileAccess.open(args[0],FileAccess.READ)
 var envelope: Dictionary=input.get_var(false);input.close()
 var result: Dictionary=preload("res://tests/acceptance/ordinary_consultation_release.gd").new().run_snapshot(envelope.facts,HospitalContent.new())
 FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
 print("ORDINARY_CONSULTATION_RELEASE "+JSON.stringify(result))
 quit(0 if result.ok else 1)
