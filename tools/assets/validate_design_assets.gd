extends SceneTree

var failures: Array[String] = []
var clips_checked: int = 0
var scenes_checked: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://" + path))

func _check_scene(path: String) -> void:
	var packed: PackedScene = load("res://" + path) as PackedScene
	if packed == null:
		failures.append("Missing scene: " + path)
		return
	var node: Node = packed.instantiate()
	scenes_checked += 1
	if node.has_node("AnimationPlayer"):
		var player: AnimationPlayer = node.get_node("AnimationPlayer")
		for key: StringName in player.get_animation_list():
			var animation: Animation = player.get_animation(key)
			for track: int in animation.get_track_count():
				if animation.track_get_type(track) in [Animation.TYPE_METHOD, Animation.TYPE_AUDIO]:
					failures.append("Presentation has business/audio callback: " + path)
			player.play(key)
			player.seek(0.5, true)
			player.pause()
			clips_checked += 1
	node.free()

func _run() -> void:
	var ui_only: bool = OS.get_cmdline_user_args().has("--ui-only")
	var supplement: Dictionary = _read("assets/ui/supplement-index.json")
	var pictures: Dictionary = {}
	for graphic: Dictionary in supplement.graphics:
		var texture: Texture2D = load("res://" + str(graphic.path)) as Texture2D
		if texture == null:
			failures.append("Missing supplement texture: " + str(graphic.id))
		elif texture.get_width() != int(graphic.width) or texture.get_height() != int(graphic.height):
			failures.append("Supplement dimensions mismatch: " + str(graphic.id))
		pictures[str(graphic.path)] = true
		if graphic.has("card"):
			_check_scene(str(graphic.card))
	var presentation: Dictionary = _read("assets/presentation/index.json")
	if not ui_only:
		for item: Dictionary in presentation.scenes:
			_check_scene(str(item.path))
	var plan: Dictionary = _read("assets/asset-plan.json")
	for requirement: Dictionary in plan.requirements:
		if str(requirement.kind) in ["native_prop", "overlay", "ui_component", "ui_illustration", "profession_accessory"]:
			if ui_only and str(requirement.kind) in ["native_prop","overlay"]:
				continue
			for path: String in requirement.required_paths:
				if path.ends_with(".tscn"):
					_check_scene(path)
	var welcome: Texture2D = load("res://assets/ui/illustrations/hospital_welcome.png") as Texture2D
	if welcome == null:
		failures.append("Missing hospital welcome illustration")
	var font_checks: int = 0
	for weight: String in ["Regular","Medium"]:
		var font: Font = load("res://assets/fonts/HospitalUI-" + weight + ".tres") as Font
		for sample: String in ["龘","齉","𠮷","é","1,234,567.89"]:
			for letter: int in sample.length():
				if not font.has_char(sample.unicode_at(letter)):
					failures.append("Font fallback missing: " + weight + " " + sample)
			for scale: float in [1.0,1.25,1.5,1.75,2.0]:
				for size: int in [14,16,18,24]:
					var measured: Vector2 = font.get_string_size(sample,HORIZONTAL_ALIGNMENT_LEFT,-1,int(round(size*scale)))
					if measured.x <= 0.0:
						failures.append("Font shaping failed: " + sample)
					font_checks += 1
	var result: Dictionary = {"engine":Engine.get_version_info().string,
		"supplement_graphic_definitions":supplement.graphics.size(),"unique_supplement_png":pictures.size(),
		"native_scenes_instantiated":scenes_checked,"animation_states_sampled":clips_checked,
		"business_and_audio_callbacks":"none","failures":failures,
		"font_fallback_shaping_checks":font_checks,
		"selection":"UI layout correction" if ui_only else "all content presentations and new native assets",
		"scope":"new UI, native props, overlays, and all content presentation scenes; unchanged models and clinical libraries reuse prior evidence"}
	var file: FileAccess = FileAccess.open("res://design-check.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("DESIGN_ASSET_RESULT=" + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
