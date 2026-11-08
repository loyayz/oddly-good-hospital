extends SceneTree
func _initialize()->void:
 var r: Dictionary=preload("res://tests/acceptance/guidance_queue_capacity_index.gd").new().run_index()
 FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(r));quit(0 if r.ok else 1)
