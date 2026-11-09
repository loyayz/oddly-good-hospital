extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args()
	var content:=HospitalContent.new()
	var crowd:RefCounted=preload("res://tests/acceptance/guidance_fixed_queue.gd").new()
	crowd._content=content
	var ordinary:Dictionary=crowd._crowded_approach()
	var stage:Dictionary=preload("res://tests/acceptance/floor_guidance.gd").new().run_cases(content,["GUIDE-SAME-FLOOR-NEW-STAGE"])
	var result:Dictionary={"ok":ordinary.ok and stage.ok,"ordinary":ordinary,"stage":stage}
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("movement guidance handoff: ",result.ok)
	quit(0 if result.ok else 1)
