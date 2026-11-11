extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var args:PackedStringArray=OS.get_cmdline_user_args()
 var selectors:Array=[]
 var test=load("res://tests/acceptance/life_local_movement.gd").new()
 if args.size()>1:
  for name:String in args[1].split(","):
   if not name in test.LOCAL_CASES or name in selectors:push_error("Unknown or duplicate life movement selector: "+name);quit(2);return
   selectors.append(name)
 var result:Dictionary=test.run_local(HospitalContent.new(),selectors)
 if not args.is_empty():
  var file:FileAccess=FileAccess.open(args[0],FileAccess.WRITE)
  if file==null:push_error("Cannot write life movement contract report");quit(2);return
  file.store_string(JSON.stringify(result,"\t"))
 print("LIFE_LOCAL_MOVEMENT "+JSON.stringify(result))
 quit(0 if result.ok else 1)
