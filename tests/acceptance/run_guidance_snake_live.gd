extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var args:=OS.get_cmdline_user_args()
 var result:Dictionary=preload("res://tests/acceptance/floor_guidance.gd").new().run_cases(HospitalContent.new(),["GUIDE-REAL-ARRIVAL","GUIDE-NURSE-RECOVERY","GUIDE-SAME-FLOOR-NEW-STAGE","GUIDE-ARRIVAL-ORDER"])
 FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"));print(JSON.stringify(result));quit(0 if result.ok else 1)
