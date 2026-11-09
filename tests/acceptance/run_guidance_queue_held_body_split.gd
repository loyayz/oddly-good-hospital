extends SceneTree
func _initialize()->void:
 var result:Dictionary=preload("res://tests/acceptance/guidance_queue_held_body_split.gd").new().run_checks()
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result));quit(0 if result.ok else 1)
