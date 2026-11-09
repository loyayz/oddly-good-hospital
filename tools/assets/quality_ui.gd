extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load("res://tools/assets/asset_browser.tscn") as PackedScene
	root.add_child(scene.instantiate())
	for count: int in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	print("ASSET_BROWSER_RENDERED")
	quit()
