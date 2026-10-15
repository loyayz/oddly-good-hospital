extends Control

const Palette = preload("res://game/view/hospital_palette.gd")

var _guard: RefCounted
var _content: HospitalContent
var _snapshots: HospitalSnapshots
var _simulation: HospitalSimulation
var _session: GameSession
var _view: HospitalView
var _viewport: SubViewport
var _world_container: SubViewportContainer
var _details: RichTextLabel
var _status: Label
var _clock: Label
var _title: Label
var _header: PanelContainer
var _toolbar: HFlowContainer
var _hospital_ids: Array[String] = []
var _auto_deadline_ms: int = 0
var _details_deadline_ms: int = 0
var _last_process_us: int = 0
var _saved_revision: int = -1
var _ui_scale: int = 1
var _observed_floor: int = 1
var _selected_actor: String = "patient"
var _selected_object: String = ""
var _leave_operation: Dictionary = {}
var _candidate: WorldState
var _drafts: Dictionary = {}
var _save_requests: Dictionary = {}
var _library: RefCounted
var _library_panel: HospitalLibraryPanel
var _library_thread: Thread
var _library_job: Dictionary = {}
var _file_dialog: FileDialog
var _panel_picker: OptionButton
var _management_scroll: ScrollContainer
var _management_panels: VBoxContainer
var _build_panel: HospitalBuildPanel
var _build_overlay: HospitalBuildOverlay
var _build_drag_start: Array = []
var _expansion_panel: HospitalExpansionPanel
var _remodel_panel: HospitalRemodelPanel
var _draft_confirmation: ConfirmationDialog
var _draft_leave: Callable
var _draft_leave_confirmed: bool = false
var _draft_commands: Dictionary = {}

func _ready() -> void:
	get_tree().auto_accept_quit = false
	_build_ui()
	_acquire()

func _exit_tree() -> void:
	if _simulation!=null:
		_simulation.dispose()

func _build_ui() -> void:
	var theme: Theme = Theme.new()
	theme.default_font = load("res://assets/fonts/NotoSansCJKsc-Regular.otf")
	theme.default_font_size = 18
	theme.set_color("font_color","Label",Palette.INK)
	theme.set_color("font_color","Button",Palette.HEADER_TEXT)
	for state: String in ["hover","pressed","focus"]:
		theme.set_color("font_"+state+"_color","Button",Palette.HEADER_TEXT)
	theme.set_color("font_disabled_color","Button",Palette.DISABLED_INK)
	theme.set_font("bold_font","RichTextLabel",load("res://assets/fonts/NotoSansCJKsc-Medium.otf"))
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Palette.SURFACE
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 14
	panel_style.content_margin_right = 14
	panel_style.content_margin_top = 12
	panel_style.content_margin_bottom = 12
	theme.set_stylebox("panel","PanelContainer",panel_style)
	for state: String in ["normal","hover","pressed","disabled"]:
		var button_style: StyleBoxFlat = StyleBoxFlat.new()
		button_style.bg_color = {"normal":Palette.BUTTON,"hover":Palette.BUTTON_HOVER,"pressed":Palette.BUTTON_PRESSED,"disabled":Palette.BUTTON_DISABLED}[state]
		button_style.border_color = Palette.BORDER
		button_style.set_border_width_all(1)
		button_style.set_corner_radius_all(7)
		button_style.content_margin_left = 10
		button_style.content_margin_right = 10
		theme.set_stylebox(state,"Button",button_style)
	var focus_style: StyleBoxFlat = StyleBoxFlat.new()
	focus_style.draw_center = false
	focus_style.border_color = Palette.HEADER_TEXT
	focus_style.set_border_width_all(2)
	focus_style.set_corner_radius_all(7)
	focus_style.set_expand_margin_all(2)
	theme.set_stylebox("focus","Button",focus_style)
	self.theme = theme
	var background: ColorRect = ColorRect.new()
	background.color = Palette.CANVAS
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","top","right","bottom"]:
		margin.add_theme_constant_override("margin_"+side,18)
	add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	margin.add_child(column)
	_header = PanelContainer.new()
	var header_style: StyleBoxFlat = StyleBoxFlat.new()
	header_style.bg_color = Palette.HEADER
	header_style.set_corner_radius_all(10)
	header_style.content_margin_left = 18
	header_style.content_margin_right = 18
	header_style.content_margin_top = 12
	header_style.content_margin_bottom = 14
	_header.add_theme_stylebox_override("panel",header_style)
	column.add_child(_header)
	var header_column: VBoxContainer = VBoxContainer.new()
	header_column.add_theme_constant_override("separation",12)
	_header.add_child(header_column)
	var heading: HBoxContainer = HBoxContainer.new()
	heading.add_theme_constant_override("separation",24)
	header_column.add_child(heading)
	_title = Label.new()
	_title.text = "怪好的医院"
	_title.add_theme_font_size_override("font_size",26)
	_title.add_theme_color_override("font_color",Palette.HEADER_TEXT)
	_title.add_theme_font_override("font",load("res://assets/fonts/NotoSansCJKsc-Medium.otf"))
	heading.add_child(_title)
	_clock = Label.new()
	_clock.text = "正在准备医院资料"
	_clock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_clock.add_theme_color_override("font_color",Palette.HEADER_MUTED)
	_clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(_clock)
	_toolbar = HFlowContainer.new()
	_toolbar.add_theme_constant_override("h_separation",8)
	_toolbar.add_theme_constant_override("v_separation",8)
	header_column.add_child(_toolbar)
	_button("暂停",func() -> void: _set_speed(0))
	for speed: int in [1,2,3]:
		_button(str(speed)+"×",_set_speed.bind(speed))
	_button("保存",_save,true)
	_button("医院资料库",_toggle_library)
	_button("建造布置",func() -> void: _show_panel("building"))
	_button("切换医院",_switch_hospital)
	_button("取消切院",_cancel_switch)
	_button("1F",_change_floor.bind(1))
	_button("2F",_change_floor.bind(2))
	_button("跟随选中",_follow_selected)
	_button("全层概览",func() -> void:
		if _view!=null:
			_view.overview())
	_button("前往1F",_move_selected.bind(1))
	_button("前往2F",_move_selected.bind(2))
	_button("界面100%",_set_ui_scale.bind(1))
	_button("界面200%",_set_ui_scale.bind(2))
	_button("低动态",_toggle_motion)
	_button("退出",_request_quit)
	var split: HSplitContainer = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(split)
	_world_container = SubViewportContainer.new()
	_world_container.stretch = true
	_world_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_world_container.custom_minimum_size = Vector2(400,260)
	_world_container.gui_input.connect(_world_input)
	split.add_child(_world_container)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1000,650)
	_viewport.scaling_3d_scale = 0.75
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_world_container.add_child(_viewport)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(340,0)
	split.add_child(panel)
	_details = RichTextLabel.new()
	_details.bbcode_enabled = true
	_details.scroll_active = true
	_details.add_theme_color_override("default_color",Palette.INK)
	var side: VBoxContainer = VBoxContainer.new()
	panel.add_child(side)
	_panel_picker = OptionButton.new()
	for entry: Array in [["院内情况","details"],["医院资料库","library"]]:
		_panel_picker.add_item(entry[0])
		_panel_picker.set_item_metadata(_panel_picker.item_count-1,entry[1])
	_panel_picker.item_selected.connect(func(index: int) -> void: _show_panel(str(_panel_picker.get_item_metadata(index))))
	side.add_child(_panel_picker)
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_details)
	_library_panel = HospitalLibraryPanel.new()
	_library_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_library_panel.visible = false
	_library_panel.action_requested.connect(_library_action)
	side.add_child(_library_panel)
	_management_scroll = ScrollContainer.new()
	_management_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_management_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_management_scroll.visible = false
	side.add_child(_management_scroll)
	_management_panels = VBoxContainer.new()
	_management_panels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_management_scroll.add_child(_management_panels)
	_build_panel = HospitalBuildPanel.new()
	_build_panel.preview_changed.connect(_show_build_preview)
	_add_management_panel("building","建造与布置",_build_panel)
	var clinical_panel: HospitalClinicalPanel = HospitalClinicalPanel.new()
	clinical_panel.locate_requested.connect(_locate_entity)
	_add_management_panel("clinical","接诊与病例",clinical_panel)
	_add_management_panel("plans","治疗方案",HospitalPlansPanel.new())
	var ward_panel: HospitalWardPanel = HospitalWardPanel.new()
	ward_panel.locate_requested.connect(_locate_entity)
	_add_management_panel("ward","住院与探视",ward_panel)
	_add_management_panel("training","医护培养",HospitalTrainingPanel.new())
	var research_panel: HospitalResearchPanel = HospitalResearchPanel.new()
	research_panel.page_requested.connect(_show_panel)
	_add_management_panel("research","研究与资料柜",research_panel)
	_expansion_panel = HospitalExpansionPanel.new()
	_expansion_panel.floor_requested.connect(_change_floor)
	_expansion_panel.location_requested.connect(_locate_cell)
	_expansion_panel.draft_changed.connect(func(draft: Dictionary) -> void:
		if draft.is_empty(): _drafts.erase("expansion")
		else: _drafts.expansion = draft.duplicate(true))
	_add_management_panel("expansion","土地与楼层交通",_expansion_panel)
	_remodel_panel = HospitalRemodelPanel.new()
	_remodel_panel.preview_changed.connect(_show_layout_preview)
	_remodel_panel.page_requested.connect(_show_panel)
	_remodel_panel.draft_changed.connect(func(draft: Dictionary) -> void:
		if draft.is_empty(): _drafts.erase("remodel")
		else: _drafts.remodel = draft.duplicate(true))
	_add_management_panel("remodel","改建与蓝图",_remodel_panel)
	_add_management_panel("schedule","排班与休假",HospitalSchedulePanel.new())
	_add_management_panel("staff_life","员工需求",HospitalStaffLifePanel.new())
	_add_management_panel("waiting","候诊生活",HospitalWaitingPanel.new())
	_add_management_panel("supplies","治疗包库存",HospitalSuppliesPanel.new())
	var environment_panel: HospitalEnvironmentPanel = HospitalEnvironmentPanel.new()
	environment_panel.location_requested.connect(_locate_cell)
	environment_panel.heatmap_requested.connect(_show_environment_heatmap)
	_add_management_panel("environment","环境与装修",environment_panel)
	_add_management_panel("maintenance","维护与升级",HospitalMaintenancePanel.new())
	_add_management_panel("departments","科室与体验",HospitalDepartmentsPanel.new())
	_add_management_panel("finance","经营账目",HospitalFinancePanel.new())
	_add_management_panel("recruitment","招聘与履历",HospitalRecruitmentPanel.new())
	_add_management_panel("arrivals","来院与熟客",HospitalArrivalsPanel.new())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color",Palette.MUTED_INK)
	column.add_child(_status)

func _button(text: String, callback: Callable, primary: bool = false) -> void:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0,42)
	if primary:
		for state: String in ["normal","hover","pressed"]:
			var style: StyleBoxFlat = theme.get_stylebox(state,"Button").duplicate()
			style.bg_color = {"normal":Palette.ACTION,"hover":Palette.ACTION_HOVER,"pressed":Palette.ACTION_PRESSED}[state]
			style.border_color = style.bg_color
			button.add_theme_stylebox_override(state,style)
		for color_name: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
			button.add_theme_color_override(color_name,Palette.INK)
	button.pressed.connect(callback)
	_toolbar.add_child(button)

func _acquire() -> void:
	if not ClassDB.class_exists("PlatformSessionGuard") or not ClassDB.class_exists("PlatformSQLite"):
		_status.text = "Windows资料库组件未能加载。请重新安装完整程序。"
		return
	_guard = ClassDB.instantiate("PlatformSessionGuard") as RefCounted
	var acquired: Dictionary = _guard.call("acquire")
	if not acquired.ok:
		_status.text = acquired.message
		if acquired.busy:
			_button("重试取得资料",_acquire)
		return
	_content = HospitalContent.new()
	if not _content.error.is_empty():
		_status.text = _content.error
		return
	_snapshots = HospitalSnapshots.new(_content,_guard)
	_library = HospitalLibrary.new(_content,_snapshots)
	_library_panel.attach(_library,"")
	_auto_deadline_ms = Time.get_ticks_msec()+roundi(float(_content.balance.save.autosave_real_seconds)*1000)
	_hospital_ids = _snapshots.hospital_ids()
	if _hospital_ids.is_empty():
		_hospital_ids = [HospitalSnapshots.uuid()]
		if _activate(HospitalFactory.create(_hospital_ids[0],"奇妙小院",true,_content)):
			_status.text = "医院已准备好。可以布置院区、查看员工，按1×开始经营。"
		return
	var unavailable: PackedStringArray = PackedStringArray()
	for hospital_id: String in _hospital_ids:
		var restored: Dictionary = _snapshots.recover_latest(hospital_id)
		if not restored.ok:
			unavailable.append("一座医院暂不可用："+str(restored.error)+"。原文件保留。")
			continue
		if _activate(restored.world,true):
			_status.text = "已继续"+str(restored.world.facts.display_name)+"，医院处于暂停。"
			if not restored.get("rejected_candidates",[]).is_empty():
				_status.text += " 已恢复最近有效的保存点，损坏记录保留。"
			if not unavailable.is_empty():
				_status.text += " 另有医院暂不可用，原文件保留。"
			return
		unavailable.append(_status.text)
	_status.text = "医院资料需要恢复：\n"+"\n".join(unavailable)
	_clock.text = "医院资料需要恢复"
	_show_panel("library")

func _gameplay_world(source: WorldState) -> WorldState:
	if int(source.facts.get("gameplay_version",0))==1:
		return source
	var upgraded: WorldState = WorldState.new(source.freeze())
	upgraded.facts.gameplay_version = 1
	if not upgraded.facts.has("entry"):
		upgraded.facts.entry = {"floor_id":1,"cell":_content.starter_layout.entry.anchor.duplicate(),"exit_cell":[48,95]}
	return upgraded

func _activate(world: WorldState, restored: bool = false) -> bool:
	world = _gameplay_world(world)
	var session_id: String = HospitalSnapshots.uuid()
	if HospitalSpace.floor_plots(world,_observed_floor).is_empty():
		_observed_floor = 1
	var prepared: HospitalView = HospitalView.new(_content)
	_viewport.add_child(prepared)
	prepared.visible = false
	prepared.bind(world,_observed_floor,session_id)
	if not prepared.bind_error.is_empty():
		_status.text = prepared.bind_error
		_viewport.remove_child(prepared)
		prepared.queue_free()
		return false
	if _view!=null:
		_viewport.remove_child(_view)
		_view.queue_free()
	_view = prepared
	_view.visible = true
	if _simulation!=null:
		_simulation.dispose()
	_simulation = HospitalSimulation.new(world,_content)
	_session = GameSession.new(_simulation,session_id)
	_last_process_us = Time.get_ticks_usec()
	if not DisplayServer.window_is_focused():
		_session.pause("focus")
	_saved_revision = int(world.facts.world_revision) if restored else -1
	_library_panel.attach(_library,world.hospital_id)
	_bind_management_panels()
	return true

func _restore_older(hospital_id: String, snapshot_id: String) -> void:
	var restored: Dictionary = _snapshots.load_commit(hospital_id,snapshot_id)
	if not restored.ok:
		_status.text = "此保存点已不可恢复："+str(restored.error)
		return
	if _activate(restored.world,true):
		_status.text = "已恢复上一有效保存点。原提交保留，医院保持暂停。"

func _toggle_library() -> void:
	_show_panel("details" if _library_panel.visible else "library")

func _add_management_panel(id: String, label: String, panel: Control) -> void:
	panel.name = id
	panel.visible = false
	panel.connect("command_requested",_submit_business)
	_management_panels.add_child(panel)
	_panel_picker.add_item(label)
	_panel_picker.set_item_metadata(_panel_picker.item_count-1,id)

func _bind_management_panels() -> void:
	for panel: Node in _management_panels.get_children():
		if panel==_build_panel:
			_build_panel.attach(_simulation,_session,_observed_floor)
		else:
			if panel is HospitalEnvironmentPanel:
				panel.floor_id = _observed_floor
			panel.call("attach",_simulation,_session)

func _show_panel(id: String) -> void:
	_details.visible = id=="details"
	_library_panel.visible = id=="library"
	_management_scroll.visible = id not in ["details","library"]
	for index: int in _panel_picker.item_count:
		if str(_panel_picker.get_item_metadata(index))==id:
			_panel_picker.select(index)
	for panel: Node in _management_panels.get_children():
		(panel as Control).visible = str(panel.name)==id
	if id=="library":
		_library_panel.refresh()
	if id!="environment" and _view!=null:
		_view.show_environment_heatmap([])
	if id!="building" and is_instance_valid(_build_overlay):
		_build_overlay.show_preview({},{},_observed_floor)

func _show_environment_heatmap(cells: Array) -> void:
	if _view!=null and _simulation!=null:
		_view.show_environment_heatmap(_simulation.services.environment.heatmap(_simulation.world,_observed_floor,cells,_selected_actor))

func _submit_business(kind: String, payload: Dictionary) -> void:
	if _simulation==null or not _leave_operation.is_empty():
		_status.text = "切换医院期间保留当前操作，完成后可以继续。"
		return
	var command_id: String = str(payload.get("command_id",HospitalSnapshots.uuid()))
	var command: GameCommand = GameCommand.new(command_id,_simulation.world.hospital_id,_simulation.world.revision,kind,BusinessPayload.new(payload),_session.loading_session_id)
	var result: CommandResult = _session.submit(command)
	_status.text = ("操作已完成。" if result.code!="queued" else result.reason) if result.accepted else result.reason
	if kind in HospitalRemodel.KINDS or kind=="blueprint_place" or kind in BuildService.KINDS or kind=="floor_purchase" or kind in HospitalConnectors.KINDS:
		if result.accepted and result.code!="queued": _clear_confirmed_draft(kind)
		elif result.accepted: _draft_commands[command_id] = kind

func _clear_confirmed_draft(kind: String) -> void:
	if kind in BuildService.KINDS:
		_drafts.erase("building")
		_build_panel.cancel_draft()
	elif kind in ["remodel_prepare","remodel_apply","blueprint_place"]:
		_drafts.erase("remodel")
		_remodel_panel.clear_draft()
	elif kind=="floor_purchase" or kind in HospitalConnectors.KINDS:
		_drafts.erase("expansion")
		_expansion_panel.clear_draft()

func _show_build_preview(draft: Dictionary, result: Dictionary) -> void:
	if draft.is_empty(): _drafts.erase("building")
	elif _build_panel.is_visible_in_tree(): _drafts.building = draft.duplicate(true)
	_show_layout_preview(draft,result)

func _show_layout_preview(draft: Dictionary, result: Dictionary) -> void:
	if _view==null:
		return
	if not is_instance_valid(_build_overlay) or _build_overlay.get_parent()!=_view:
		_build_overlay = HospitalBuildOverlay.new()
		_view.add_child(_build_overlay)
	var outline: Dictionary = draft.duplicate(true)
	if draft.get("kind","")=="build_facility":
		var definition: Dictionary = _content.facility_definition(str(draft.get("definition_id","")))
		outline.size = definition.get("footprint",[1,1]).duplicate()
		if int(draft.get("rotation",0))%2==1:
			outline.size.reverse()
	_build_overlay.show_preview(outline,result,_observed_floor)

func _locate_entity(id: String) -> void:
	if _simulation==null:
		return
	var world: WorldState = _simulation.world
	if world.facts.actors.has(id):
		_selected_actor = id
		_selected_object = ""
		var actor: Dictionary = world.facts.actors[id]
		if actor.location.kind=="floor":
			_change_floor(int(actor.location.floor_id))
			_view.follow_actor = id
		else:
			_status.text = "该居民目前已离开现场，保留其病例记录。"
	elif world.facts.facilities.has(id):
		_selected_object = id
		var facility: Dictionary = world.facts.facilities[id]
		_locate_cell(int(facility.floor_id),facility.cell)
	elif world.facts.rooms.has(id):
		_selected_object = id
		var room: Dictionary = world.facts.rooms[id]
		_locate_cell(int(room.floor_id),room.origin)

func _locate_cell(floor_id: int, cell: Array) -> void:
	_change_floor(floor_id)
	if _view!=null:
		_view.focus_cell(cell)

func _library_action(kind: String, payload: Dictionary) -> void:
	if _library==null or _library_thread!=null or not _leave_operation.is_empty():
		_status.text = "已有医院资料作业正在进行，完成后可以继续。"
		return
	match kind:
		"create":
			var hospital_name: String = str(payload.name)
			if hospital_name.is_empty() or hospital_name.length()>24:
				_status.text = "请填写1至24字的医院名称。"
				return
			var hospital_id: String = HospitalSnapshots.uuid()
			var new_world: WorldState = HospitalFactory.create(hospital_id,hospital_name,bool(payload.preset),_content)
			_start_switch(hospital_id,"",new_world)
		"continue":
			_start_switch(payload.hospital_id,str(payload.get("snapshot_id","")))
		"export","import":
			_choose_backup_file(kind,payload)
		"trash","restore","delete_slot":
			if _snapshots.busy():
				_status.text = "正在保存，完成后可以管理医院资料。"
				return
			var result: Dictionary
			var active_id: String = _simulation.world.hospital_id if _simulation!=null else ""
			if kind=="trash":
				result = _library.call("trash_hospital",payload.hospital_id,active_id)
			elif kind=="restore":
				result = _library.call("restore_hospital",payload.hospital_id)
			else:
				result = _library.call("delete_slot",payload.hospital_id,payload.snapshot_id,active_id)
			_status.text = "医院资料已更新。" if result.get("ok",false) else str(result.get("error","资料操作未完成。"))
			_hospital_ids = _snapshots.hospital_ids()
			_library_panel.refresh()

func _choose_backup_file(kind: String, payload: Dictionary) -> void:
	if _file_dialog!=null:
		_file_dialog.queue_free()
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if kind=="export" else FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.title = "导出医院备份" if kind=="export" else "导入医院备份"
	_file_dialog.filters = PackedStringArray(["*.oghbackup ; 医院备份"])
	_file_dialog.current_file = "医院备份.oghbackup" if kind=="export" else ""
	_file_dialog.file_selected.connect(func(path: String) -> void:
		var selected: Dictionary = payload.duplicate(true)
		selected.path = path
		_launch_library_job(kind,selected))
	add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.7)

func _launch_library_job(kind: String, payload: Dictionary) -> void:
	if _library_thread!=null or _snapshots.busy() or not _leave_operation.is_empty():
		_status.text = "已有资料作业正在进行，请完成后重试。"
		return
	_library_job = {"kind":kind,"payload":payload.duplicate(true)}
	_library_thread = Thread.new()
	var error: Error = _library_thread.start(_perform_library_job.bind(kind,payload.duplicate(true)))
	if error!=OK:
		_library_thread = null
		_library_job = {}
		_status.text = "无法启动医院备份作业，请重试。"
		return
	_status.text = "正在分段校验医院备份…" if kind=="import" else "正在导出独立医院备份…"

func _perform_library_job(kind: String, payload: Dictionary) -> Dictionary:
	if kind=="import":
		return _library.call("import_backup",payload.path)
	return _library.call("export_backup",payload.hospital_id,payload.snapshot_id,payload.path)

func _poll_library_job() -> void:
	if _library_thread==null or _library_thread.is_alive():
		return
	var result: Dictionary = _library_thread.wait_to_finish()
	_library_thread = null
	var kind: String = _library_job.kind
	_library_job = {}
	if result.get("ok",false):
		_status.text = "已导入为独立的新医院，可在资料库继续经营。" if kind=="import" else "医院备份已导出。"
		_hospital_ids = _snapshots.hospital_ids()
		_library_panel.refresh()
	else:
		_status.text = "医院备份未完成，原资料保留："+str(result.get("error","请检查文件与可用空间。"))

func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var real_delta: float = float(now-_last_process_us)/1000000.0 if _last_process_us>0 else 0.0
	_last_process_us = now
	_poll_library_job()
	if _snapshots!=null and _library_thread==null:
		var receipt: Dictionary = _snapshots.poll()
		if not receipt.is_empty():
			_receipt(receipt)
	if _simulation == null:
		return
	for id: String in _draft_commands.keys():
		var applied: Dictionary = _simulation.receipt(id)
		if not applied.is_empty():
			if applied.accepted: _clear_confirmed_draft(str(_draft_commands[id]))
			_draft_commands.erase(id)
	for result: TickResult in _session.advance(real_delta):
		for event: SimEvent in result.facts:
			if event.kind=="command_rejected":
				_status.text = str(event.details.result.reason)
	_view.update_facts(_session.interpolation_alpha())
	if Time.get_ticks_msec()>=_details_deadline_ms:
		_details_deadline_ms = Time.get_ticks_msec()+100
		_update_details()
	if _library_thread==null and Time.get_ticks_msec()>=_auto_deadline_ms:
		_auto_deadline_ms = Time.get_ticks_msec()+roundi(float(_content.balance.save.autosave_real_seconds)*1000)
		if int(_simulation.world.facts.world_revision)>_saved_revision:
			_begin_save("auto",str(int(_simulation.world.facts.sim_tick)%5))
	if _library_thread==null and not _snapshots.busy() and _snapshots.take_pending_auto() and int(_simulation.world.facts.world_revision)>_saved_revision:
		_begin_save("auto",str(int(_simulation.world.facts.sim_tick)%5))

func _set_speed(speed: int) -> void:
	if _simulation != null and _leave_operation.is_empty():
		_session.set_speed(speed)

func _save() -> void:
	if _simulation == null:
		return
	_simulation.drain_commands()
	var started: Dictionary = _begin_save("manual","1")
	_status.text = "正在保存完整医院…" if started.ok else str(started.error)

func _begin_save(kind: String, slot: String) -> Dictionary:
	if _library_thread!=null:
		return {"ok":false,"error":"医院备份作业正在进行，完成后可以保存。"}
	var started: Dictionary = _snapshots.begin(_simulation,_session.loading_session_id,kind,slot)
	if started.ok:
		_save_requests[started.request.request_id] = started.request.duplicate(true)
	return started

func _switch_hospital() -> void:
	if _simulation == null or _snapshots.busy() or not _leave_operation.is_empty():
		return
	if _hospital_ids.size()<2:
		_toggle_library()
		return
	var index: int = _hospital_ids.find(_simulation.world.facts.hospital_id)
	var target: String = _hospital_ids[(index+1)%_hospital_ids.size()]
	_start_switch(target)

func _start_switch(target: String, snapshot_id: String = "", new_world: WorldState = null) -> void:
	if _confirm_draft_leave(func() -> void: _start_switch(target,snapshot_id,new_world)): return
	if _snapshots.busy() or _library_thread!=null or not _leave_operation.is_empty():
		_status.text = "已有资料作业正在进行，请等待完成。"
		return
	_set_speed(0)
	if _simulation==null:
		_leave_operation = {"kind":"switch","id":HospitalSnapshots.uuid(),"source_session":"",
			"origin_session":"",
			"request_id":"","target_hospital_id":target,"target_snapshot_id":snapshot_id,
			"stage":"source","new_world":new_world}
		_prepare_switch_candidate()
		return
	_simulation.drain_commands()
	var started: Dictionary = _begin_save("checkpoint","switch")
	if not started.ok:
		_status.text = started.error
		return
	_leave_operation = {"kind":"switch","id":HospitalSnapshots.uuid(),"source_session":_session.loading_session_id,
		"origin_session":_session.loading_session_id,
		"request_id":started.request.request_id,"target_hospital_id":target,"target_snapshot_id":snapshot_id,
		"stage":"source","new_world":new_world}
	_status.text = "原医院保持暂停，正在保存离院检查点…"

func _cancel_switch() -> void:
	if _leave_operation.get("kind","") == "switch":
		_leave_operation = {}
		_candidate = null
		_status.text = "已取消切院，原医院与草稿保留，医院保持暂停。"

func _receipt(receipt: Dictionary) -> void:
	var expected: Dictionary = _save_requests.get(receipt.get("request_id",""),{})
	if expected.is_empty():
		return
	for field: String in ["hospital_id","loading_session_id","request_id","snapshot_id","world_revision"]:
		if receipt.get(field)!=expected[field]:
			return
	_save_requests.erase(receipt.request_id)
	if _simulation!=null and receipt.hospital_id == _simulation.world.facts.hospital_id and receipt.loading_session_id == _session.loading_session_id:
		if receipt.ok:
			_saved_revision = maxi(_saved_revision,int(receipt.world_revision))
			_status.text = "已保存。" + ("此后还有进展。" if int(_simulation.world.facts.world_revision)>_saved_revision else "")
		else:
			_status.text = "保存失败："+str(receipt.error)
	if _leave_operation.is_empty() or receipt.request_id != _leave_operation.request_id or receipt.loading_session_id != _leave_operation.source_session:
		return
	if _leave_operation.has("origin_session") and (_session.loading_session_id if _session!=null else "")!=_leave_operation.origin_session:
		return
	if _leave_operation.get("stage","")=="source" and (_session==null or _session.loading_session_id!=_leave_operation.source_session):
		return
	if not receipt.ok:
		_status.text = "资料提交失败，原资料保留："+str(receipt.get("error","请重试。"))
		_leave_operation = {}
		return
	if _leave_operation.kind == "quit":
		_guard.call("release")
		get_tree().quit()
		return
	_prepare_switch_candidate()

func _prepare_switch_candidate() -> void:
	var target: String = _leave_operation.target_hospital_id
	if _leave_operation.stage=="candidate":
		_candidate = _leave_operation.new_world
	elif _leave_operation.new_world!=null:
		var target_session: String = HospitalSnapshots.uuid()
		var created: Dictionary = _library.call("create",_leave_operation.new_world,target_session)
		if not created.ok:
			_status.text = "新医院创建失败，原医院保留："+str(created.error)
			_leave_operation = {}
			return
		_save_requests[created.request.request_id] = created.request.duplicate(true)
		_leave_operation.request_id = created.request.request_id
		_leave_operation.source_session = target_session
		_leave_operation.stage = "candidate"
		_status.text = "正在提交新医院资料…" if _simulation==null else "原医院已保存，正在提交新医院资料…"
		return
	else:
		var loaded: Dictionary = _library.call("continue_hospital",target,_leave_operation.target_snapshot_id)
		if not loaded.ok:
			_status.text = "切院失败，原医院保留："+str(loaded.error)
			_leave_operation = {}
			return
		_candidate = loaded.world
	var reason: String = _candidate.validate(_content)
	if not reason.is_empty():
		_status.text = "候选医院未通过："+reason
		_candidate = null
		_leave_operation = {}
		return
	_candidate = _gameplay_world(_candidate)
	# Candidate resources are prepared before the main-thread publication boundary.
	var candidate_view: HospitalView = HospitalView.new(_content)
	var candidate_session_id: String = HospitalSnapshots.uuid()
	_viewport.add_child(candidate_view)
	candidate_view.visible = false
	var target_floor: int = _observed_floor if not HospitalSpace.floor_plots(_candidate,_observed_floor).is_empty() else 1
	candidate_view.bind(_candidate,target_floor,candidate_session_id)
	if not candidate_view.bind_error.is_empty():
		_status.text = "切院失败，原医院保留："+candidate_view.bind_error
		_viewport.remove_child(candidate_view)
		candidate_view.queue_free()
		_candidate = null
		_leave_operation = {}
		return
	if _view!=null:
		_viewport.remove_child(_view)
		_view.queue_free()
	_view = candidate_view
	_view.visible = true
	_observed_floor = target_floor
	if _simulation!=null:
		_simulation.dispose()
	_simulation = HospitalSimulation.new(_candidate,_content)
	_session = GameSession.new(_simulation,candidate_session_id)
	_last_process_us = Time.get_ticks_usec()
	if not DisplayServer.window_is_focused():
		_session.pause("focus")
	_saved_revision = int(_candidate.facts.world_revision)
	_hospital_ids = _snapshots.hospital_ids()
	_library_panel.attach(_library,_candidate.hospital_id)
	_bind_management_panels()
	_candidate = null
	_leave_operation = {}
	_drafts.clear()
	_status.text = "已进入另一座医院，医院保持暂停。"

func _request_quit() -> void:
	if _confirm_draft_leave(_request_quit): return
	if _library_thread!=null:
		_status.text = "医院备份作业正在进行，完成后可以退出。"
		return
	if _snapshots == null or _simulation==null:
		if _guard != null:
			_guard.call("release")
		get_tree().quit()
		return
	if _snapshots.busy():
		_status.text = "已有资料写入正在进行，请等待完成后退出。"
		return
	_set_speed(0)
	_simulation.drain_commands()
	var started: Dictionary = _begin_save("checkpoint","quit")
	if not started.ok:
		_status.text = started.error
		return
	_leave_operation = {"kind":"quit","source_session":_session.loading_session_id,"request_id":started.request.request_id}
	_status.text = "正在保存退出检查点…"

func _change_floor(floor_id: int) -> void:
	if _view != null:
		if HospitalSpace.floor_plots(_simulation.world,floor_id).is_empty():
			_status.text = "这一层还没有可用楼板。"
			return
		_observed_floor = floor_id
		_view.set_floor(floor_id)
		_build_panel.set_floor(floor_id)
		var environment_panel: HospitalEnvironmentPanel = _management_panels.get_node("environment")
		environment_panel.floor_id = floor_id
		environment_panel.rebuild()

func _confirm_draft_leave(continuation: Callable) -> bool:
	if _draft_leave_confirmed:
		_draft_leave_confirmed = false
		return false
	if _simulation==null or _drafts.is_empty(): return false
	_draft_leave = continuation
	if _draft_confirmation==null:
		_draft_confirmation = ConfirmationDialog.new()
		_draft_confirmation.title = "保留已确认的医院进展"
		_draft_confirmation.dialog_text = "当前有未确认的建造或改建草案。离开时保存已确认进展，并在成功离开后舍弃草案；保存失败会保留当前医院和草案。"
		_draft_confirmation.ok_button_text = "保存已确认进展并舍弃草案"
		_draft_confirmation.cancel_button_text = "返回编辑"
		add_child(_draft_confirmation)
		_draft_confirmation.confirmed.connect(func() -> void:
			_draft_leave_confirmed = true
			var next: Callable = _draft_leave
			_draft_leave = Callable()
			if next.is_valid(): next.call())
		_draft_confirmation.canceled.connect(func() -> void: _draft_leave = Callable())
	_draft_confirmation.popup_centered(Vector2i(560,210))
	return true

func _set_ui_scale(scale: int) -> void:
	_ui_scale = scale
	theme.default_font_size = 18*scale
	_title.add_theme_font_size_override("font_size",26*scale)
	for button: Node in _toolbar.get_children():
		(button as Button).custom_minimum_size.y = 42*scale

func _toggle_motion() -> void:
	if _view != null:
		_view.low_motion = not _view.low_motion

func _follow_selected() -> void:
	if _view!=null and _simulation.world.facts.actors.has(_selected_actor):
		_view.follow_actor = _selected_actor
		_view.camera.size = 18.0

func _move_selected(floor_id: int) -> void:
	if _simulation==null or not _simulation.world.facts.actors.has(_selected_actor) or not _leave_operation.is_empty():
		return
	var command_id: String = HospitalSnapshots.uuid()
	var world: WorldState = _simulation.world
	var target: Vector2i = Vector2i(47,93) if floor_id==1 else Vector2i(35,83)
	var payload: MoveActorPayload = MoveActorPayload.new(_selected_actor,floor_id,target,world.facts.actors[_selected_actor].location)
	var result: CommandResult = _session.submit(GameCommand.new(command_id,world.hospital_id,world.revision,"move_actor",payload,_session.loading_session_id))
	_status.text = "已接收实际通行请求。" if result.accepted else result.reason

func _world_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_MIDDLE and _view!=null:
		_view.pan_camera(event.relative)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and _view != null:
		var point: Vector2 = event.position*Vector2(_viewport.size)/_world_container.size
		if _build_panel.visible:
			var cell: Array = _view.cell_at_screen(point)
			if event.pressed:
				_build_drag_start = cell
				_build_panel.set_map_cell(cell)
			elif not _build_drag_start.is_empty() and not cell.is_empty():
				if cell!=_build_drag_start:
					_build_panel.draw_room(_build_drag_start,cell)
				_build_drag_start = []
		else:
			var selection: Dictionary = _view.pick_entity(point)
			if not selection.is_empty():
				_locate_entity(str(selection.id))
	if event is InputEventMouseButton and event.pressed and _view!=null:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			_view.zoom_camera(1.1 if event.button_index==MOUSE_BUTTON_WHEEL_DOWN else 1.0/1.1)

func _update_details() -> void:
	var world: WorldState = _simulation.world
	var actual_speed: int = _session.actual_speed()
	var playback: String = "暂停" if actual_speed==0 else str(actual_speed)+"×"
	if _session.running_slow:
		playback += " · 运行稍慢"
	_clock.text = "%s   %s   %s   资金 %d · 治疗包 %d" % [world.facts.display_name,world.clock_text(),playback,HospitalLedger.balance(world),int(world.facts.inventory.units)]
	var lines: PackedStringArray = PackedStringArray(["[b]院内情况[/b]","观察 %dF" % _observed_floor])
	if not _session.pause_reasons().is_empty():
		var reasons: PackedStringArray = []
		for source: String in _session.pause_reasons():
			reasons.append({"focus":"窗口未聚焦"}.get(source,source))
		lines.append("暂停原因："+", ".join(reasons))
	for visit_id: String in world.ids("visits"):
		var visit: Dictionary = world.facts.visits[visit_id]
		var evidence: float = 0.0
		for value: Variant in visit.evidence_by_source.values():
			evidence += float(value)
		lines.append("\n[b]"+str(world.facts.actors[visit.actor_id].name)+"[/b]")
		lines.append(str(_content.definition("diseases",visit.disease_id).name) if evidence>=90 else str(_content.definition("treatment_bindings",visit.binding_id).symptom_variant))
		lines.append("诊断进度 %d / 90" % mini(90,floori(evidence)))
		lines.append(_phase_name(visit.phase))
		if not visit.waiting_reason.is_empty():
			lines.append(visit.waiting_reason)
		if not visit.plan_decision.is_empty():
			lines.append(str(_content.definition("treatment_plans",visit.plan_decision.plan_id).name))
		for session: Dictionary in world.facts.sessions.values():
			if session.visit_id == visit.id:
				lines.append("剩余 %d 医院分钟" % ceili(float(session.remaining_ticks)*4.8/60.0))
		if visit.final_result == "cured":
			lines.append("[color=#"+Palette.SUCCESS.to_html(false)+"]已治愈，沿原流程离院[/color]")
		elif visit.final_result == "retry":
			lines.append("本次未治愈，继续原方案复治")
		elif visit.final_result == "referred":
			lines.append("已安排友好转诊")
	if world.facts.actors.has(_selected_actor):
		var actor: Dictionary = world.facts.actors[_selected_actor]
		var body: Dictionary = _content.definition("species",actor.species_id).body
		lines.append("\n[b]"+str(actor.name)+"[/b]")
		lines.append("宽 %.1f米 · 深 %.1f米 · 高 %.1f米" % [float(body.width_m),float(body.depth_m),float(body.height_m)])
	if world.facts.facilities.has(_selected_object):
		var facility: Dictionary = world.facts.facilities[_selected_object]
		lines.append("\n[b]"+str(_content.facility_definition(facility.definition_id).get("name",_selected_object))+"[/b]")
		lines.append("%dF · 等级%d · 完好度%d%%" % [int(facility.floor_id),int(facility.grade),roundi(facility.condition)])
		lines.append("当前故障，等待维修" if facility.failed else "按真实岗位与路线接单")
	_details.text = "\n".join(lines)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_request_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if _session!=null:
			_session.pause("focus")
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		if _session!=null:
			_session.resume("focus")

static func _phase_name(phase: String) -> String:
	return {"arrival":"到院","wait_reception":"等候接待","reception":"正在接待","wait_gp":"等候初诊","gp":"初诊中",
		"wait_spectrum":"等候光谱检查","spectrum":"光谱检查中","wait_resonance":"等候共振检查","resonance":"共振检查中",
		"wait_consult":"等候方案会诊","consult":"方案会诊中","wait_outpatient":"等候门诊治疗","outpatient":"治疗中",
		"wait_surgery":"手术准备","surgery":"手术进行中","wake":"治疗完成，苏醒中","transfer":"正在转床",
		"recovery":"住院恢复与护理","round_wait":"等待出院查房","round":"出院查房","leaving":"正在离院","departed":"已离院"}.get(phase,phase)
