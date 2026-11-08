extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
 var result: Dictionary=preload("res://tests/acceptance/guidance_queue_passage_obstacles.gd").new().run_passage_obstacles(HospitalContent.new())
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
 quit(0 if result.passed else 1)
