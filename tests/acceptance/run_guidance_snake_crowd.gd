extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var args:=OS.get_cmdline_user_args()
 var suite:RefCounted=preload("res://tests/acceptance/guidance_fixed_queue.gd").new()
 suite._content=HospitalContent.new()
 var rows:Array=[suite._crowded_approach(),suite._crowded_approach(false,true)]
 var result:Dictionary={"ok":rows.all(func(row:Dictionary)->bool:return row.ok),"cases":rows}
 FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print(JSON.stringify(result));quit(0 if result.ok else 1)
