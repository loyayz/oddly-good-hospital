extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var result:Dictionary=load("res://tests/acceptance/life_local_movement.gd").new().run(HospitalContent.new())
 var args:PackedStringArray=OS.get_cmdline_user_args()
 if not args.is_empty():
  var file:FileAccess=FileAccess.open(args[0],FileAccess.WRITE)
  if file==null:push_error("Cannot write life movement contract report");quit(2);return
  file.store_string(JSON.stringify(result,"\t"))
 print("LIFE_LOCAL_MOVEMENT "+JSON.stringify(result))
 quit(0 if result.ok else 1)
