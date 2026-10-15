class_name HospitalRemodelPanel
extends HospitalActionPanel

signal draft_changed(draft: Dictionary)
signal preview_changed(draft: Dictionary, result: Dictionary)
signal page_requested(id: String)
var _rooms: ItemList
var _objects: ItemList
var _floor: SpinBox
var _x: SpinBox
var _y: SpinBox
var _rotation: OptionButton
var _orders: OptionButton
var _presets: OptionButton
var _name: LineEdit
var _description: TextEdit
var _inventory: CheckBox
var _surfaces: CheckBox
var _safe_transfer: CheckBox
var _department: OptionButton
var _result: Label
var _image: TextureRect
var _library: HospitalBlueprintLibrary
var _cursor: String = ""
var _blueprint: Dictionary = {}
var _preview: Dictionary = {}
var _draft: Dictionary = {}
var _kind: String = ""
var _thumbnail: String = ""
var _pinned_guide: String = ""
var _bound_session: String = ""

func attach(kernel: HospitalSimulation, active_session: GameSession) -> void:
	if _bound_session!=active_session.loading_session_id:
		clear_draft()
		_blueprint = {}
		_thumbnail = ""
		_bound_session = active_session.loading_session_id
	super.attach(kernel,active_session)

func build_controls() -> void:
	_library = HospitalBlueprintLibrary.new(simulation.services.blueprints)
	heading("安全改建与空间蓝图")
	note("选择完整房间或公共物件。安排只停止新预约；人员和现有工作安全退出后，仍需查看最新报价并确认应用。")
	_rooms = _selection("完整房间",true)
	_objects = _selection("公共物件",false)
	_floor = number("目标楼层",1,10000,1)
	_floor.allow_greater = true
	_x = number("目标横向格",0,95,34)
	_y = number("目标纵向格",0,95,67)
	_rotation = choice("整组旋转",[0,1,2,3])
	_safe_transfer = CheckBox.new()
	_safe_transfer.text = "对可安全接续的门诊采用安全转移"
	add_child(_safe_transfer)
	action("预览整组搬迁目标",_group_preview)
	action("确认停止新预约并准备改建",_prepare)
	var width: SpinBox = number("调整房间内宽",1,96,4)
	var depth: SpinBox = number("调整房间内深",1,96,4)
	action("预览所选单房间扩缩",func() -> void:
		var ids: Array = _selected_ids(_rooms)
		if ids.size()!=1:
			_result.text = "请选择一间完整房间"
			return
		_kind = "remodel_prepare"
		_draft = {"commands":[{"kind":"build_resize","target_id":ids[0],"origin":[int(_x.value),int(_y.value)],"size":[int(width.value),int(depth.value)]}],"safe_transfer":_safe_transfer.button_pressed}
		_preview = {"ok":true}
		_result.text = "扩缩目标已冻结，确认安排后等待安全腾空。"
		_show_commands(_draft.commands)
		draft_changed.emit(_draft))
	_orders = choice("已确认改建安排",_order_entries())
	action("核对当前改建报价",_order_preview)
	action("应用已核对的改建",func() -> void: _confirm("remodel_apply"))
	action("取消所选安排",func() -> void: send("remodel_cancel",{"order_id":selected(_orders)}))
	heading("保存与复用蓝图")
	_name = LineEdit.new()
	field("蓝图名称",_name)
	_description = TextEdit.new()
	_description.custom_minimum_size.y = 70
	field("说明",_description)
	_image = TextureRect.new()
	_image.custom_minimum_size = Vector2(144,96)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_image)
	action("将所选布局保存为新蓝图",_save_selection)
	_presets = choice("内置与共享蓝图",_blueprint_entries())
	action("载入所选蓝图",_load)
	action("移除缺失内容及不完整房间，形成新草案",func() -> void:
		if _blueprint.is_empty(): return
		_blueprint = simulation.services.blueprints.without_missing(_blueprint)
		_result.text = "已形成独立草案，请重新核对并另存。原蓝图保持不变。"
		draft_changed.emit({"blueprint":_blueprint.duplicate(true)}))
	action("共享蓝图下一页",func() -> void:
		var page: Dictionary = _library.list_page(_cursor)
		_presets.clear()
		for item: Dictionary in page.get("items",[]):
			_presets.add_item(str(item.name))
			_presets.set_item_metadata(_presets.item_count-1,item.id)
		_cursor = str(page.get("next_cursor","")))
	action("更新所选共享蓝图的名称和说明",_update)
	action("更换缩略图",_choose_thumbnail)
	action("删除所选共享蓝图",func() -> void:
		var result: Dictionary = _library.remove(selected(_presets))
		_result.text = "蓝图已删除" if result.ok else result.reason)
	_inventory = CheckBox.new()
	_inventory.text = "优先使用当前医院匹配库存"
	_inventory.button_pressed = true
	add_child(_inventory)
	_surfaces = CheckBox.new()
	_surfaces.text = "同时购买美化材料并建立原装修工单"
	add_child(_surfaces)
	var departments: Array = [{"id":"","name":"暂不分配科室"}]
	for item: Dictionary in simulation.world.facts.get("departments",{}).get("units",{}).values(): departments.append({"id":item.id,"name":item.name})
	_department = choice("新房间所属运营科室",departments)
	action("核对整张蓝图与库存报价",_blueprint_preview)
	action("确认原子放置蓝图",func() -> void: _confirm("blueprint_place"))
	action("取消当前草案",func() -> void:
		clear_draft()
		_result.text = "草案已取消，已确认安排保持原状态")
	_result = note("草案不改变医院和资金。")
	for input: SpinBox in [_floor,_x,_y,width,depth]: input.value_changed.connect(func(_value: float) -> void: _invalidate())
	for picker: OptionButton in [_rotation,_department]: picker.item_selected.connect(func(_index: int) -> void: _invalidate())
	for toggle: CheckBox in [_safe_transfer,_inventory,_surfaces]: toggle.toggled.connect(func(_value: bool) -> void: _invalidate())
	_rooms.multi_selected.connect(func(_index: int,_selected: bool) -> void: _invalidate())
	_objects.multi_selected.connect(func(_index: int,_selected: bool) -> void: _invalidate())
	var guides: Array = simulation.content.catalog.remodel_guides
	var guide: OptionButton = choice("改造引导",guides)
	var guide_text: Label = note("")
	guide.item_selected.connect(func(_index: int) -> void:
		var definition: Dictionary = simulation.content.definition("remodel_guides",selected(guide))
		_pinned_guide = str(definition.id)
		guide_text.text = _guide_text(definition))
	action("查看引导所用的蓝图",func() -> void:
		var definition: Dictionary = simulation.content.definition("remodel_guides",selected(guide))
		if definition.get("blueprint_ids",[]).is_empty(): return
		var id: String = str(definition.blueprint_ids[0])
		for index: int in _presets.item_count:
			if str(_presets.get_item_metadata(index))==id:
				_presets.select(index)
				_load()
				break)
	action("查看相关建造目录",func() -> void: page_requested.emit("building"))
	action("关闭改造引导",func() -> void:
		_pinned_guide = ""
		guide_text.text = "")
	report(func() -> String:
		refresh_choices(_orders,_order_entries())
		_fill_selection(_rooms,true)
		_fill_selection(_objects,false)
		var lines: PackedStringArray = []
		for order: Dictionary in simulation.world.facts.get("remodels",{}).values():
			if order.state=="preparing":
				var reason: String = simulation.services.remodel._waiting(simulation.world,order)
				lines.append(order.id+" · "+("可以核对并应用" if reason.is_empty() else reason))
		return "\n".join(lines))

func _selection(label: String, rooms: bool) -> ItemList:
	var list: ItemList = ItemList.new()
	list.select_mode = ItemList.SELECT_MULTI
	list.custom_minimum_size.y = 130
	_fill_selection(list,rooms)
	field(label,list)
	return list

func _fill_selection(list: ItemList, rooms: bool) -> void:
	var selected_ids: Array = _selected_ids(list)
	var entries: Array = []
	var collection: String = "rooms" if rooms else "facilities"
	for id: String in simulation.world.ids(collection):
		var item: Dictionary = simulation.world.facts[collection][id]
		if not rooms and not str(item.get("room_id","")).is_empty(): continue
		var name: String = str(simulation.content.definition("build_room_types",str(item.get("kind",""))).get("name",id)) if rooms else str(simulation.content.facility_definition(item.definition_id).get("name",id))
		entries.append([id,"%dF · %s · %s" % [int(item.floor_id),name,id]])
	var current: Array = []
	for index: int in list.item_count: current.append([str(list.get_item_metadata(index)),list.get_item_text(index)])
	if current==entries: return
	list.clear()
	for entry: Array in entries:
		list.add_item(entry[1])
		list.set_item_metadata(list.item_count-1,entry[0])
		if entry[0] in selected_ids: list.select(list.item_count-1,false)

func _selected_ids(list: ItemList) -> Array:
	var result: Array = []
	for index: int in list.get_selected_items(): result.append(str(list.get_item_metadata(index)))
	return result

func clear_draft() -> void:
	_draft = {}
	_preview = {}
	_kind = ""
	preview_changed.emit({},{})
	draft_changed.emit({})

func _invalidate() -> void:
	_draft = {}
	_preview = {}
	_kind = ""
	preview_changed.emit({},{})
	draft_changed.emit({"editing":true})
	if _result!=null: _result.text = "目标条件已改变，请重新核对原布局草案。"

func _order_entries() -> Array:
	var result: Array = []
	for order: Dictionary in simulation.world.facts.get("remodels",{}).values():
		if order.state=="preparing": result.append({"id":order.id,"name":order.id})
	return result

func _group_preview() -> void:
	var result: Dictionary = simulation.services.remodel.group_commands(simulation.world,_selected_ids(_rooms),_selected_ids(_objects),int(_floor.value),[int(_x.value),int(_y.value)],int(selected(_rotation)))
	if not result.ok:
		_result.text = result.reason
		return
	_kind = "remodel_prepare"
	_draft = {"commands":result.commands,"safe_transfer":_safe_transfer.button_pressed}
	_preview = {"ok":true}
	_result.text = "整组目标已冻结，确认安排后等待真实腾空；此时不收建设费。"
	_show_commands(result.commands)
	draft_changed.emit(_draft)

func _prepare() -> void:
	if _kind=="remodel_prepare" and not _draft.is_empty(): send(_kind,_draft)

func _order_preview() -> void:
	_kind = "remodel_apply"
	_draft = {"order_id":selected(_orders)}
	_preview = simulation.services.remodel.preview(simulation.world,selected(_orders))
	_preview.erase("candidate")
	_result.text = "费用 %d，表面及拆除退款 %d。" % [int(_preview.price),int(_preview.refund)] if _preview.ok else _preview.reason
	var order: Dictionary = simulation.world.facts.remodels.get(selected(_orders),{})
	if not order.is_empty(): _show_commands(order.commands)

func _show_commands(commands: Array) -> void:
	var cells: Array = []
	var floor_id: int = int(_floor.value)
	for command: Dictionary in commands:
		var item: Dictionary = simulation.world.facts.rooms.get(command.target_id,simulation.world.facts.facilities.get(command.target_id,{}))
		if item.is_empty(): continue
		floor_id = int(command.get("floor_id",item.floor_id))
		var origin: Array = command.get("origin",command.get("cell",item.get("origin",item.get("cell",[0,0]))))
		var size: Array = command.get("size",item.get("size",item.get("footprint",[1,1]))).duplicate()
		var source: Array = BuildGeometry.cells(item) if simulation.world.facts.rooms.has(command.target_id) and command.kind!="build_resize" else []
		if source.is_empty():
			if int(command.get("turns",0))%2==1: size.reverse()
			for y: int in int(size[1]):
				for x: int in int(size[0]): cells.append([int(origin[0])+x,int(origin[1])+y])
		else:
			for cell: Array in source:
				var local: Vector2i = Vector2i(int(cell[0])-int(item.origin[0]),int(cell[1])-int(item.origin[1]))
				var offset: Vector2i = BuildService._rotate_offset(local,size,int(command.get("turns",0)))
				cells.append([int(origin[0])+offset.x,int(origin[1])+offset.y])
	preview_changed.emit({"floor_id":floor_id,"cells":cells},{"ready":false})

func _blueprint_entries() -> Array:
	var result: Array = simulation.content.catalog.blueprint_presets.duplicate(true)
	var page: Dictionary = _library.list_page()
	for item: Dictionary in page.get("items",[]): result.append({"id":item.id,"name":item.name})
	_cursor = str(page.get("next_cursor",""))
	return result

func _save_selection() -> void:
	var captured: Dictionary = simulation.services.blueprints.capture(simulation.world,_selected_ids(_rooms),_selected_ids(_objects),_name.text)
	if not captured.ok:
		_result.text = captured.reason
		return
	_blueprint = captured.blueprint
	_thumbnail = _layout_thumbnail(_blueprint)
	var result: Dictionary = _library.save(_blueprint,_name.text,_description.text,_thumbnail)
	if result.ok: _blueprint = result.blueprint
	_result.text = "蓝图已保存" if result.ok else result.reason
	_show_thumbnail()

func _load() -> void:
	var id: String = selected(_presets)
	var result: Dictionary = simulation.services.blueprints.builtin(id) if id.begins_with("BP") else _library.load_blueprint(id)
	if not result.ok and not result.get("editable",false):
		_result.text = result.reason
		return
	_blueprint = result.blueprint
	_name.text = str(_blueprint.name)
	_description.text = str(_blueprint.get("description",""))
	_thumbnail = str(_blueprint.get("thumbnail",""))
	if _thumbnail.is_empty(): _thumbnail = _layout_thumbnail(_blueprint)
	_show_thumbnail()
	_result.text = "蓝图已载入草案，请核对目标位置、研究和真实库存。" if result.ok else result.reason+"；可明确移除缺失内容后另存新草案。"
	draft_changed.emit({"blueprint":_blueprint.duplicate(true)})

func _update() -> void:
	if _blueprint.is_empty(): return
	var result: Dictionary = _library.save(_blueprint,_name.text,_description.text,_thumbnail)
	if result.ok: _blueprint = result.blueprint
	_result.text = "蓝图已保存" if result.ok else result.reason

func _blueprint_preview() -> void:
	_kind = "blueprint_place"
	_draft = {"blueprint":_blueprint.duplicate(true),"floor_id":int(_floor.value),"cell":[int(_x.value),int(_y.value)],"use_inventory":_inventory.button_pressed,"include_surfaces":_surfaces.button_pressed,"department_id":selected(_department)}
	_preview = simulation.services.blueprints.preview(simulation.world,_draft)
	if _preview.ok:
		var cells: Array = []
		var candidate: WorldState = _preview.candidate
		for id: String in _preview.changed_ids:
			if candidate.facts.rooms.has(id): cells.append_array(BuildGeometry.cells(candidate.facts.rooms[id]))
			elif candidate.facts.facilities.has(id):
				var item: Dictionary = candidate.facts.facilities[id]
				for y: int in int(item.footprint[1]):
					for x: int in int(item.footprint[0]): cells.append([int(item.cell[0])+x,int(item.cell[1])+y])
		preview_changed.emit({"floor_id":int(_floor.value),"cells":cells},{"ready":true,"ok":true})
	else: preview_changed.emit({},{})
	_preview.erase("candidate")
	_result.text = "房间家具 %d，升级材料 %d，美化材料 %d；合计 %d。" % [int(_preview.purchase_cost),int(_preview.upgrade_cost),int(_preview.material_cost),int(_preview.price)] if _preview.ok else _preview.reason
	draft_changed.emit(_draft)

func _confirm(kind: String) -> void:
	if _kind!=kind or not _preview.get("ok",false): return
	var payload: Dictionary = _draft.duplicate(true)
	payload.quote = {"price":_preview.price,"refund":_preview.refund,"layout":_preview.layout} if kind=="remodel_apply" else {"price":_preview.price,"inventory_choices":_preview.inventory_choices}
	send(kind,payload)

func _choose_thumbnail() -> void:
	var dialog: FileDialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.png ; PNG图片"])
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		var image: Image = Image.load_from_file(path)
		if image!=null and not image.is_empty():
			image.resize(192,128,Image.INTERPOLATE_LANCZOS)
			_thumbnail = Marshalls.raw_to_base64(image.save_png_to_buffer())
			_show_thumbnail()
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered_ratio(0.65)

func _show_thumbnail() -> void:
	var image: Image = Image.new()
	if not _thumbnail.is_empty() and image.load_png_from_buffer(Marshalls.base64_to_raw(_thumbnail))==OK: _image.texture = ImageTexture.create_from_image(image)

func _layout_thumbnail(blueprint: Dictionary) -> String:
	var image: Image = Image.create(192,192,false,Image.FORMAT_RGBA8)
	image.fill(Color("edf1e8"))
	for room: Dictionary in blueprint.rooms:
		for cell: Array in room.cells: image.fill_rect(Rect2i(int(cell[0])*2,int(cell[1])*2,2,2),Color("879e86"))
	for item: Dictionary in blueprint.objects: image.fill_rect(Rect2i(int(item.cell[0])*2,int(item.cell[1])*2,3,3),Color("a98053"))
	return Marshalls.raw_to_base64(image.save_png_to_buffer())

func _guide_text(guide: Dictionary) -> String:
	var lines: PackedStringArray = []
	for key: String in guide:
		if key in ["id","blueprint_ids","content_refs"]: continue
		var value: Variant = guide[key]
		if value is String: lines.append(value)
		elif value is Array:
			for item: Variant in value:
				if item is String: lines.append(item)
	return "\n".join(lines)
