class_name HospitalBuildPanel
extends VBoxContainer

signal command_requested(kind: String, payload: Dictionary)
signal preview_changed(draft: Dictionary, result: Dictionary)

var simulation: HospitalSimulation
var session: GameSession
var floor_id: int = 1
var _preview: BuildPreview
var _mode: OptionButton
var _definition: OptionButton
var _target: OptionButton
var _door: OptionButton
var _x: SpinBox
var _y: SpinBox
var _width: SpinBox
var _height: SpinBox
var _rotation: OptionButton
var _inventory: OptionButton
var _reason: Label
var _confirm: Button
var _result: Dictionary = {}
var _draft: Dictionary = {}
var _command_id: String = ""
var _definition_row: Control
var _target_row: Control
var _size_row: Control
var _door_row: Control
var _inventory_row: Control

func _ready() -> void:
	add_theme_constant_override("separation",10)
	var heading: Label = Label.new()
	heading.text = "建造与布置"
	heading.add_theme_font_size_override("font_size",22)
	add_child(heading)
	var hint: Label = Label.new()
	hint.text = "选择用途后，在院区点击定位。新房间可以拖动画框，也可填写位置与大小。草案不会扣款。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	_mode = OptionButton.new()
	for entry: Array in [["新建房间","build_room"],["放置设施","build_facility"],["移动对象","build_move"],["旋转对象","build_rotate"],["更换房门","build_door"],["拆除与退款","build_demolish"],["撤销上次建造","build_undo"]]:
		_mode.add_item(entry[0])
		_mode.set_item_metadata(_mode.item_count-1,entry[1])
	_mode.item_selected.connect(func(_index: int) -> void: _populate())
	add_child(_mode)
	_definition = OptionButton.new()
	_definition_row = _field("用途",_definition)
	_inventory = OptionButton.new()
	_inventory_row = _field("购买或复用库存",_inventory)
	_target = OptionButton.new()
	_target_row = _field("现有对象",_target)
	var position: HBoxContainer = HBoxContainer.new()
	_x = _number(0,95,34)
	_y = _number(0,95,67)
	position.add_child(_x)
	position.add_child(_y)
	_field("位置 · 横向 / 纵向",position)
	var dimensions: HBoxContainer = HBoxContainer.new()
	_width = _number(1,96,4)
	_height = _number(1,96,4)
	dimensions.add_child(_width)
	dimensions.add_child(_height)
	_size_row = _field("房间内部 · 宽 / 深",dimensions)
	_door = OptionButton.new()
	_door_row = _field("房门",_door)
	_rotation = OptionButton.new()
	for turns: int in 4:
		_rotation.add_item("朝向 %d°" % (turns*90))
	_field("朝向",_rotation)
	_reason = Label.new()
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_reason)
	_confirm = Button.new()
	_confirm.text = "确认建造"
	_confirm.custom_minimum_size.y = 42
	_confirm.disabled = true
	_confirm.pressed.connect(_submit)
	add_child(_confirm)
	var cancel: Button = Button.new()
	cancel.text = "取消当前草案"
	cancel.pressed.connect(cancel_draft)
	add_child(cancel)
	for picker: OptionButton in [_definition,_target,_door,_rotation,_inventory]:
		picker.item_selected.connect(func(_index: int) -> void: _request())
	for number: SpinBox in [_x,_y,_width,_height]:
		number.value_changed.connect(func(_value: float) -> void: _request())
	_populate()

func attach(kernel: HospitalSimulation, active_session: GameSession, observed_floor: int) -> void:
	simulation = kernel
	session = active_session
	floor_id = observed_floor
	_preview = BuildPreview.new(simulation.services.building)
	if is_node_ready():
		_populate()

func set_floor(observed_floor: int) -> void:
	floor_id = observed_floor
	if not _draft.is_empty():
		_preview.rebind(_binding())

func _populate() -> void:
	if simulation==null or _mode==null:
		return
	var kind: String = _mode.get_item_metadata(_mode.selected)
	var database: HospitalContent = simulation.content
	_definition.clear()
	_target.clear()
	_door.clear()
	_inventory.clear()
	_inventory.add_item("从目录购买")
	_inventory.set_item_metadata(0,"")
	for id: String in simulation.world.facts.inventory.get("build_items",{}):
		var item: Dictionary = simulation.world.facts.inventory.build_items[id]
		_inventory.add_item(str(database.facility_definition(item.definition_id).get("name",item.definition_id))+" · 库存")
		_inventory.set_item_metadata(_inventory.item_count-1,id)
	var definitions: Array = []
	if kind=="build_room":
		definitions = database.catalog.get("build_room_types",[])
	elif kind=="build_facility":
		var seen: Dictionary = {}
		for collection: String in ["machines","clinical_equipment","furniture_equipment","service_equipment","accessibility_equipment","staff_recreation_equipment"]:
			for item: Variant in database.catalog.get(collection,[]):
				if item is Dictionary:
					var identifier: String = str(item.get("id",item.get("definition_id","")))
					if identifier.is_empty() or seen.has(identifier):
						continue
					var definition: Dictionary = database.facility_definition(identifier)
					if not definition.is_empty():
						definitions.append(definition)
						seen[identifier] = true
	for definition: Dictionary in definitions:
		var identifier: String = str(definition.get("id",definition.get("definition_id","")))
		_definition.add_item(str(definition.get("name",identifier)))
		_definition.set_item_metadata(_definition.item_count-1,identifier)
	for collection: String in ["rooms","facilities"]:
		for id: String in simulation.world.ids(collection):
			var record: Dictionary = simulation.world.facts[collection][id]
			if int(record.floor_id)!=floor_id:
				continue
			var label: String = str(record.get("name",id))
			if collection=="facilities":
				label = str(database.facility_definition(record.definition_id).get("name",id))+" · "+id
			_target.add_item(label)
			_target.set_item_metadata(_target.item_count-1,id)
	for door: Dictionary in simulation.world.facts.floors.overrides.get(str(floor_id),{}).get("doors",[]):
		_target.add_item("房门 · "+str(door.id))
		_target.set_item_metadata(_target.item_count-1,door.id)
	for definition: Dictionary in database.catalog.doors:
		_door.add_item(str(definition.get("name",definition.id)))
		_door.set_item_metadata(_door.item_count-1,definition.id)
	_definition_row.visible = kind in ["build_room","build_facility"]
	_inventory_row.visible = kind=="build_facility"
	_target_row.visible = kind in ["build_move","build_rotate","build_door","build_demolish"]
	_size_row.visible = kind=="build_room"
	_door_row.visible = kind in ["build_room","build_door"]
	_confirm.text = {"build_demolish":"确认拆除与退款","build_undo":"撤销上次建造","build_move":"确认移动","build_rotate":"确认旋转","build_door":"确认换门"}.get(kind,"确认建造")
	_request()

func _request() -> void:
	if simulation==null or _preview==null:
		return
	var kind: String = _mode.get_item_metadata(_mode.selected)
	_draft = {"kind":kind,"floor_id":floor_id,"origin":[int(_x.value),int(_y.value)],"cell":[int(_x.value),int(_y.value)],"rotation":_rotation.selected,"turns":1}
	match kind:
		"build_room":
			if _definition.item_count==0 or _door.item_count==0:
				return
			_draft.room_type_id = _definition.get_item_metadata(_definition.selected)
			_draft.size = [int(_width.value),int(_height.value)]
			_draft.door = {"definition_id":_door.get_item_metadata(_door.selected),"edge":"south","offset":1}
		"build_facility":
			if _definition.item_count==0:
				return
			_draft.definition_id = _definition.get_item_metadata(_definition.selected)
			var inventory_id: String = str(_inventory.get_item_metadata(_inventory.selected))
			if not inventory_id.is_empty():
				_draft.inventory_id = inventory_id
				_draft.definition_id = simulation.world.facts.inventory.build_items[inventory_id].definition_id
		"build_move","build_rotate","build_demolish","build_door":
			if _target.item_count==0:
				_confirm.disabled = true
				_reason.text = "这一层还没有可操作的对象。"
				return
			_draft.target_id = _target.get_item_metadata(_target.selected)
			if kind=="build_door":
				_draft.definition_id = _door.get_item_metadata(_door.selected)
	_preview.request(_draft,_binding())
	_result = {}
	_command_id = HospitalSnapshots.uuid()
	_confirm.disabled = true
	_reason.text = "正在检查占地、价格和安全出口…"

func _binding() -> Dictionary:
	return {"hospital_id":simulation.world.hospital_id,"loading_session_id":session.loading_session_id,"view_floor_id":floor_id}

func _process(_delta: float) -> void:
	if not is_visible_in_tree() or _preview==null or _draft.is_empty():
		return
	_result = _preview.update(simulation.world)
	_confirm.disabled = not bool(_result.get("ready",false)) or not bool(_result.get("ok",false))
	if not bool(_result.get("draw_on_current_floor",true)):
		_confirm.disabled = true
		_reason.text = "草案保留在%dF，请切回该层查看并确认。" % int(_draft.floor_id)
		return
	if not bool(_result.get("ok",false)):
		_reason.text = str(_result.get("reason","正在检查当前草案…"))
	else:
		_reason.text = "费用 %d · 退款 %d\n确认后资金 %d" % [int(_result.get("price",0)),int(_result.get("refund",0)),int(_result.get("balance_after",HospitalLedger.balance(simulation.world)))]
	preview_changed.emit(_draft.duplicate(true),_result.duplicate(true))

func set_map_cell(cell: Array) -> void:
	if cell.size()!=2:
		return
	_x.value = int(cell[0])
	_y.value = int(cell[1])
	_request()

func draw_room(first: Array, last: Array) -> void:
	if _mode.get_item_metadata(_mode.selected)!="build_room":
		set_map_cell(last)
		return
	_x.value = mini(int(first[0]),int(last[0]))
	_y.value = mini(int(first[1]),int(last[1]))
	_width.value = absi(int(first[0])-int(last[0]))+1
	_height.value = absi(int(first[1])-int(last[1]))+1
	_request()

func cancel_draft() -> void:
	if _preview!=null:
		_preview.cancel()
	_draft = {}
	_result = {}
	_confirm.disabled = true
	_reason.text = "草案已取消，已确认布局保持不变。"
	preview_changed.emit({},{})

func _submit() -> void:
	if _confirm.disabled or not _result.get("ready",false):
		return
	var payload: Dictionary = _draft.duplicate(true)
	payload.quote = _result.quote.duplicate(true)
	payload.command_id = _command_id
	command_requested.emit(str(_draft.kind),payload)
	_confirm.disabled = true
	_reason.text = "已提交确认，正在重新检查实际条件。"

func _field(label_text: String, input: Control) -> VBoxContainer:
	var group: VBoxContainer = VBoxContainer.new()
	var label: Label = Label.new()
	label.text = label_text
	group.add_child(label)
	group.add_child(input)
	add_child(group)
	return group

func _number(minimum: int, maximum: int, initial: int) -> SpinBox:
	var number: SpinBox = SpinBox.new()
	number.min_value = minimum
	number.max_value = maximum
	number.step = 1
	number.value = initial
	number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return number
