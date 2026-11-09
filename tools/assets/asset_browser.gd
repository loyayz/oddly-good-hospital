extends Node3D

const Factory = preload("res://tools/assets/asset_factory.gd")
const SoundBank = preload("res://tools/assets/sound_bank.gd")
var _entries: Array[Dictionary] = []
var _visible_entries: Array[Dictionary] = []
var _list: ItemList
var _filter: LineEdit
var _category: OptionButton
var _phase: OptionButton
var _look: OptionButton
var _role: OptionButton
var _level: OptionButton
var _state: OptionButton
var _low: CheckButton
var _progress: HSlider
var _details: Label
var _camera: Camera3D
var _display: Node3D
var _audio: Node
var _current: Dictionary = {}
var _playing: bool = false
var _auto_progress: float = 0.0

func _ready() -> void:
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/asset-plan.json"))
	for entry: Dictionary in plan.requirements:
		if entry.kind in ["body", "equipment", "case", "presentation", "music", "sound", "gift", "memento", "architecture", "upgrade"]:
			_entries.append(entry)
	_audio = SoundBank.new()
	add_child(_audio)
	_display = Node3D.new()
	add_child(_display)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 5.0
	add_child(_camera)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.90, 0.87, 0.80)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(1, 0.97, 0.90)
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -25, 0)
	sun.light_energy = 0.8
	add_child(sun)
	_build_ui()
	_refilter()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_right = 320
	panel.theme = load("res://assets/ui/hospital_theme.tres") as Theme
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := Label.new()
	title.text = "怪好的医院 · 素材预览"
	title.theme_type_variation = "Header"
	column.add_child(title)
	_filter = LineEdit.new()
	_filter.placeholder_text = "搜索名称或内容 ID"
	_filter.text_changed.connect(func(_text: String) -> void: _refilter())
	column.add_child(_filter)
	_category = OptionButton.new()
	for label: String in ["全部", "body", "equipment", "case", "presentation", "music", "sound", "gift", "memento", "architecture", "upgrade"]:
		_category.add_item(label)
	_category.item_selected.connect(func(_index: int) -> void: _refilter())
	column.add_child(_category)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(280, 260)
	_list.item_selected.connect(_selected)
	column.add_child(_list)
	_phase = OptionButton.new()
	for phase: String in ["idle", "walk", "sit", "symptom", "prepare", "process", "climax", "safe_finish", "paused", "awaiting_result", "failure", "recovery", "sleep", "wake", "job_operate", "job_record", "job_carry", "job_repair", "job_clean", "job_build", "job_teach", "job_sleep", "job_wake"]:
		_phase.add_item(phase)
	_phase.item_selected.connect(func(_index: int) -> void: _refresh())
	column.add_child(_phase)
	_look = OptionButton.new()
	for number: int in 4:
		_look.add_item("外观 " + str(number + 1))
	_look.item_selected.connect(func(_index: int) -> void: _refresh())
	column.add_child(_look)
	_role = OptionButton.new()
	for role: String in ["无岗位", "doctor", "nurse", "receptionist", "cleaner", "mechanic", "researcher", "decorator"]:
		_role.add_item(role)
	_role.item_selected.connect(func(_index: int) -> void: _refresh())
	column.add_child(_role)
	var device_options := HBoxContainer.new()
	column.add_child(device_options)
	_level = OptionButton.new()
	for level: String in ["基础形态", "升级 1", "升级 2"]:
		_level.add_item(level)
	_level.item_selected.connect(func(_index: int) -> void: _refresh())
	device_options.add_child(_level)
	_state = OptionButton.new()
	for state: String in ["idle", "working", "paused", "broken", "repairing", "maintenance", "construction"]:
		_state.add_item(state)
	_state.item_selected.connect(func(_index: int) -> void: _refresh())
	device_options.add_child(_state)
	_low = CheckButton.new()
	_low.text = "低动态"
	_low.toggled.connect(func(_pressed: bool) -> void: _refresh())
	column.add_child(_low)
	_progress = HSlider.new()
	_progress.min_value = 0
	_progress.max_value = 1
	_progress.step = 0.001
	_progress.value_changed.connect(func(_value: float) -> void: _seek())
	column.add_child(_progress)
	var play := Button.new()
	play.text = "播放 / 暂停"
	play.pressed.connect(_toggle_play)
	column.add_child(play)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.custom_minimum_size = Vector2(280, 96)
	_details.max_lines_visible = 5
	column.add_child(_details)

func _refilter() -> void:
	if _list == null:
		return
	_list.clear()
	_visible_entries.clear()
	var query: String = _filter.text.to_lower()
	var category: String = _category.get_item_text(_category.selected)
	for entry: Dictionary in _entries:
		if category != "全部" and str(entry.kind) != category:
			continue
		if not query.is_empty() and not query in (str(entry.id) + " " + str(entry.name)).to_lower():
			continue
		_list.add_item(str(entry.id) + "  " + str(entry.name))
		_visible_entries.append(entry)
	if not _visible_entries.is_empty():
		_list.select(0)
		_selected(0)

func _selected(index: int) -> void:
	_current = _visible_entries[index]
	_progress.value = 0
	_audio.stop_scene(true)
	_refresh()

func _refresh() -> void:
	for child: Node in _display.get_children():
		child.free()
	if _current.is_empty():
		return
	_details.text = str(_current.name) + "\n" + str(_current.id)
	var node: Node = null
	var phase: String = _phase.get_item_text(_phase.selected)
	if _current.kind == "body":
		node = Factory.body(str(_current.id), _look.selected + 1, "" if _role.selected == 0 else _role.get_item_text(_role.selected))
	elif _current.kind == "equipment":
		node = Factory.equipment(str(_current.id), _level.selected, _state.get_item_text(_state.selected), phase, float(_progress.value))
	elif _current.kind == "case":
		node = Factory.case_scene(str(_current.id), phase if phase != "idle" else "symptom", float(_progress.value), _look.selected + 1, _low.button_pressed)
		_details.text += "\n" + str(_current.symptom)
	elif _current.kind not in ["music", "sound"]:
		var scene: PackedScene = load("res://" + str(_current.required_paths[0])) as PackedScene
		if scene != null:
			node = scene.instantiate()
	if node != null:
		_display.add_child(node)
		var target: Node = node.get_node("ClinicalProps") if _current.kind == "case" else node
		var animation_player: AnimationPlayer = Factory.find_player(target)
		if animation_player != null:
			_phase.clear()
			var desired: int = 0
			for clip: StringName in animation_player.get_animation_list():
				if str(clip) == "RESET":
					continue
				_phase.add_item(str(clip).get_file())
				if str(clip) == phase or str(clip).ends_with("/" + phase):
					desired = _phase.item_count - 1
			_phase.select(desired)
		if node is Control:
			(node as Control).position = Vector2(365, 170)
			(node as Control).size = Vector2(600, 320)
		else:
			_frame(node)
	_seek()

func _seek() -> void:
	if _display.get_child_count() == 0:
		return
	var node: Node = _display.get_child(0)
	var phase: String = _phase.get_item_text(_phase.selected)
	if _current.kind == "case":
		Factory.seek_case(node as Node3D, str(_current.id), "symptom" if phase == "idle" else phase, float(_progress.value), _low.button_pressed)
	elif _current.kind == "equipment":
		Factory.seek(node, phase if _state.get_item_text(_state.selected) in ["working", "paused"] else "idle", float(_progress.value))
	else:
		if _low.button_pressed and phase.begins_with("job_") and not phase.ends_with("_low_motion"):
			phase += "_low_motion"
		if not Factory.seek(node, phase, float(_progress.value)):
			var player: AnimationPlayer = Factory.find_player(node)
			if player != null and not player.get_animation_list().is_empty():
				Factory.seek(node, str(player.get_animation_list()[0]), float(_progress.value))

func _bounds(node: Node, bounds: Array[AABB]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		bounds.append(mesh_node.global_transform * mesh_node.get_aabb())
	for child: Node in node.get_children():
		_bounds(child, bounds)

func _frame(node: Node) -> void:
	var boxes: Array[AABB] = []
	_bounds(node, boxes)
	if boxes.is_empty():
		return
	var box: AABB = boxes[0]
	for value: AABB in boxes:
		box = box.merge(value)
	var center: Vector3 = box.get_center()
	var span: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	_camera.size = maxf(span * 1.6, 1.0)
	_camera.position = center + Vector3(1.6, 1.4, 2.0) * maxf(span, 1.0)
	_camera.look_at(center)
	# Offset the camera framing to leave the native resolution sidebar clear.
	_camera.h_offset = -_camera.size * 0.17

func _toggle_play() -> void:
	if _current.kind in ["music", "sound"]:
		_audio.stop_scene(true)
		_audio.play_current(str(_current.id), "music" if _current.kind == "music" else "ui")
		return
	_playing = not _playing

func _process(delta: float) -> void:
	if _playing and _progress != null:
		if not _current.is_empty() and _current.kind == "equipment" and _state.get_item_text(_state.selected) == "paused":
			return
		_auto_progress = fmod(_auto_progress + delta * 0.5, 1.0)
		_progress.value = _auto_progress
