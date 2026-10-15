class_name HospitalLibraryPanel
extends VBoxContainer

signal action_requested(kind: String, payload: Dictionary)

var library: RefCounted
var current_hospital_id: String = ""
var _search: LineEdit
var _name: LineEdit
var _preset: OptionButton
var _recycled: CheckBox
var _records: VBoxContainer
var _status: Label
var _next: Button
var _cursor: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override("separation",12)
	var heading: Label = Label.new()
	heading.text = "医院资料库"
	heading.add_theme_font_size_override("font_size",22)
	add_child(heading)
	_name = LineEdit.new()
	_name.placeholder_text = "新医院名称"
	_name.text = "奇妙小院"
	_name.max_length = 24
	_name.accessibility_name = "新医院名称"
	add_child(_name)
	_preset = OptionButton.new()
	_preset.add_item("预设院区")
	_preset.add_item("空地开局")
	add_child(_preset)
	_action(self,"开一家医院",func() -> void:
		action_requested.emit("create",{"name":_name.text.strip_edges(),"preset":_preset.selected==0}))
	_action(self,"导入医院备份",func() -> void: action_requested.emit("import",{}))
	add_child(HSeparator.new())
	_search = LineEdit.new()
	_search.placeholder_text = "按医院名称查找"
	_search.accessibility_name = "查找医院"
	_search.text_submitted.connect(func(_text: String) -> void: refresh())
	add_child(_search)
	var filters: HBoxContainer = HBoxContainer.new()
	add_child(filters)
	_action(filters,"查找 / 刷新",refresh)
	_recycled = CheckBox.new()
	_recycled.text = "回收站"
	_recycled.toggled.connect(func(_pressed: bool) -> void: refresh())
	filters.add_child(_recycled)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_records = VBoxContainer.new()
	_records.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_records.add_theme_constant_override("separation",12)
	scroll.add_child(_records)
	_next = Button.new()
	_next.text = "下一页"
	_next.pressed.connect(_load_page)
	add_child(_next)
	refresh()

func attach(source: RefCounted, hospital_id: String) -> void:
	library = source
	current_hospital_id = hospital_id
	if is_node_ready():
		refresh()

func refresh() -> void:
	if library==null or _records==null:
		return
	library.call("cancel_scan")
	_cursor = {}
	_load_page()

func _load_page() -> void:
	for child: Node in _records.get_children():
		_records.remove_child(child)
		child.queue_free()
	var result: Dictionary = library.call("scan_page",_cursor,12,_search.text,_recycled.button_pressed)
	if not result.get("ok",false):
		_status.text = str(result.get("error","资料扫描未完成，可以重试。"))
		return
	_cursor = result.cursor
	_next.disabled = bool(result.done)
	_status.text = "选择医院继续经营。保存点只读取摘要，进入时再完整校验。"
	if result.records.is_empty():
		_status.text = "回收站目前为空。" if _recycled.button_pressed else "这里还没有医院。可以开一家医院，或导入已有备份。"
	for record: Dictionary in result.records:
		_add_record(record)
	if not result.errors.is_empty():
		_status.text += "\n部分资料暂不可用，原文件已保留。"

func _add_record(record: Dictionary) -> void:
	var summary: Dictionary = record.get("display_summary",{})
	var title: Label = Label.new()
	title.text = str(summary.get("display_name",record.get("display_name","未命名医院")))
	if record.hospital_id==current_hospital_id:
		title.text += " · 当前医院"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_records.add_child(title)
	var detail: Label = Label.new()
	detail.text = "第%d日 · 保存进展 %d" % [int(record.get("sim_tick",0))/WorldState.TICKS_PER_DAY+1,int(record.get("world_revision",0))]
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_records.add_child(detail)
	var actions: HFlowContainer = HFlowContainer.new()
	_records.add_child(actions)
	if _recycled.button_pressed:
		_action(actions,"恢复医院",func() -> void: action_requested.emit("restore",{"hospital_id":record.hospital_id}))
	else:
		_action(actions,"继续经营",func() -> void: action_requested.emit("continue",record.duplicate(true)))
		_action(actions,"保存点",func() -> void: _show_slots(record.hospital_id))
		_action(actions,"导出备份",func() -> void: action_requested.emit("export",record.duplicate(true)))
		var remove: Button = _action(actions,"移至回收站",func() -> void: action_requested.emit("trash",{"hospital_id":record.hospital_id}))
		remove.disabled = record.hospital_id==current_hospital_id
		remove.tooltip_text = "切换到另一家医院后，可以将本院移至回收站。" if remove.disabled else "医院资料可从回收站恢复。"
	_records.add_child(HSeparator.new())

func _show_slots(hospital_id: String) -> void:
	var result: Dictionary = library.call("slots",hospital_id)
	if not result.get("ok",false):
		_status.text = str(result.get("error","无法读取保存点。"))
		return
	for child: Node in _records.get_children():
		_records.remove_child(child)
		child.queue_free()
	_status.text = "选择保存点继续；当前医院会先建立检查点。"
	_next.disabled = true
	for record: Dictionary in result.records.slice(0,28):
		var row: VBoxContainer = VBoxContainer.new()
		_records.add_child(row)
		var label: Label = Label.new()
		label.text = "第%d日 · %s · 进展 %d" % [int(record.get("sim_tick",0))/WorldState.TICKS_PER_DAY+1,str(record.get("slot_kind","manual")),int(record.get("world_revision",0))]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var actions: HFlowContainer = HFlowContainer.new()
		row.add_child(actions)
		_action(actions,"从此继续",func() -> void: action_requested.emit("continue",record.duplicate(true)))
		_action(actions,"导出",func() -> void: action_requested.emit("export",record.duplicate(true)))
		_action(actions,"删除此保存点",func() -> void: action_requested.emit("delete_slot",record.duplicate(true)))
	_action(_records,"返回医院列表",refresh)

func _action(parent: Node, text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
