extends Control

const Palette = preload("res://game/view/hospital_palette.gd")

var _guard: RefCounted
var _content: HospitalContent
var _snapshots: HospitalSnapshots
var _simulation: HospitalSimulation
var _loading_session: String = ""
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
var _speed: int = 0
var _accumulator: float = 0.0
var _auto_deadline_ms: int = 0
var _pause_tokens: Dictionary = {}
var _saved_revision: int = -1
var _ui_scale: int = 1
var _observed_floor: int = 1
var _selected_actor: String = "patient"
var _leave_operation: Dictionary = {}
var _candidate: HospitalWorld
var _drafts: Dictionary = {}
var _save_requests: Dictionary = {}

func _ready() -> void:
	get_tree().auto_accept_quit = false
	_build_ui()
	_acquire()

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
	_button("切换医院",_switch_hospital)
	_button("取消切院",_cancel_switch)
	_button("1F",_change_floor.bind(1))
	_button("2F",_change_floor.bind(2))
	_button("跟随选中",_follow_selected)
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
	panel.add_child(_details)
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
	if not ClassDB.class_exists("PlatformSessionGuard"):
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
	_auto_deadline_ms = Time.get_ticks_msec()+roundi(float(_content.balance.save.autosave_real_seconds)*1000)
	_hospital_ids = _snapshots.hospital_ids()
	if _hospital_ids.is_empty():
		_hospital_ids = [HospitalSnapshots.uuid(),HospitalSnapshots.uuid()]
		if _activate(FeasibilityHospitals.create(_hospital_ids[0],false,_content)):
			_status.text = "小帆门诊医院已准备好。开始经营后观察纸巾小帆与治疗小风车。"
		return
	var unavailable: PackedStringArray = PackedStringArray()
	var previous_save: Dictionary = {}
	for hospital_id: String in _hospital_ids:
		var records: Array[Dictionary] = _snapshots.list_commits(hospital_id)
		if records.is_empty():
			unavailable.append("一座医院没有完整有效的保存清单，原文件保留。")
			continue
		var restored: Dictionary = _snapshots.load_commit(records[0].hospital_id,records[0].snapshot_id)
		if not restored.ok:
			unavailable.append(str(records[0].display_summary.display_name)+"的保存点需要恢复："+str(restored.error))
			if previous_save.is_empty():
				for record: Dictionary in records.slice(1):
					if _snapshots.load_commit(record.hospital_id,record.snapshot_id).ok:
						previous_save = record
						break
			continue
		if _activate(restored.world,true):
			_status.text = "已继续"+str(restored.world.facts.display_name)+"，医院处于暂停。"
			if not unavailable.is_empty():
				_status.text += " 另有医院暂不可用，原文件保留。"
			return
		unavailable.append(_status.text)
	_status.text = "医院资料需要恢复：\n"+"\n".join(unavailable)
	if not previous_save.is_empty():
		_button("恢复上一有效保存点",_restore_older.bind(previous_save.hospital_id,previous_save.snapshot_id))

func _activate(world: HospitalWorld, restored: bool = false) -> bool:
	var prepared: HospitalView = HospitalView.new(_content)
	_viewport.add_child(prepared)
	prepared.visible = false
	prepared.bind(world,_observed_floor)
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
	_simulation = HospitalSimulation.new(world,_content)
	_loading_session = HospitalSnapshots.uuid()
	_accumulator = 0.0
	_speed = 0
	_saved_revision = int(world.facts.world_revision) if restored else -1
	return true

func _restore_older(hospital_id: String, snapshot_id: String) -> void:
	var restored: Dictionary = _snapshots.load_commit(hospital_id,snapshot_id)
	if not restored.ok:
		_status.text = "此保存点已不可恢复："+str(restored.error)
		return
	if _activate(restored.world,true):
		_status.text = "已恢复上一有效保存点。原提交保留，医院保持暂停。"

func _process(delta: float) -> void:
	if _simulation == null:
		return
	if delta > 1.0:
		_accumulator = 0.0
		delta = 0.0
	_simulation.drain_commands()
	var actual_speed: int = 0 if not _pause_tokens.is_empty() or not _leave_operation.is_empty() else _speed
	_accumulator += minf(delta,0.25)*actual_speed
	var steps: int = 0
	while _accumulator >= HospitalWorld.TICK_SECONDS and steps<8:
		_simulation.step()
		_accumulator -= HospitalWorld.TICK_SECONDS
		steps += 1
	_view.update_facts()
	_update_details()
	var receipt: Dictionary = _snapshots.poll()
	if not receipt.is_empty():
		_receipt(receipt)
	if Time.get_ticks_msec()>=_auto_deadline_ms:
		_auto_deadline_ms = Time.get_ticks_msec()+roundi(float(_content.balance.save.autosave_real_seconds)*1000)
		if int(_simulation.world.facts.world_revision)>_saved_revision:
			_begin_save("auto",str(int(_simulation.world.facts.sim_tick)%5))
	if not _snapshots.busy() and _snapshots.take_pending_auto() and int(_simulation.world.facts.world_revision)>_saved_revision:
		_begin_save("auto",str(int(_simulation.world.facts.sim_tick)%5))

func _set_speed(speed: int) -> void:
	if _simulation != null and _leave_operation.is_empty():
		_speed = speed
		_accumulator = 0.0

func _save() -> void:
	if _simulation == null:
		return
	_simulation.drain_commands()
	var started: Dictionary = _begin_save("manual","1")
	_status.text = "正在保存完整医院…" if started.ok else str(started.error)

func _begin_save(kind: String, slot: String) -> Dictionary:
	var started: Dictionary = _snapshots.begin(_simulation.world,_loading_session,kind,slot)
	if started.ok:
		_save_requests[started.request.request_id] = started.request.duplicate(true)
	return started

func _switch_hospital() -> void:
	if _simulation == null or _snapshots.busy() or not _leave_operation.is_empty():
		return
	_set_speed(0)
	_simulation.drain_commands()
	if _hospital_ids.size()<2:
		_hospital_ids.append(HospitalSnapshots.uuid())
	var index: int = _hospital_ids.find(_simulation.world.facts.hospital_id)
	var target: String = _hospital_ids[(index+1)%_hospital_ids.size()]
	var started: Dictionary = _begin_save("checkpoint","switch")
	if not started.ok:
		_status.text = started.error
		return
	_leave_operation = {"kind":"switch","id":HospitalSnapshots.uuid(),"source_session":_loading_session,
		"request_id":started.request.request_id,"target_hospital_id":target}
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
	if receipt.hospital_id == _simulation.world.facts.hospital_id and receipt.loading_session_id == _loading_session:
		if receipt.ok:
			_saved_revision = maxi(_saved_revision,int(receipt.world_revision))
			_status.text = "已保存。" + ("此后还有进展。" if int(_simulation.world.facts.world_revision)>_saved_revision else "")
		else:
			_status.text = "保存失败："+str(receipt.error)
	if _leave_operation.is_empty() or receipt.request_id != _leave_operation.request_id or receipt.loading_session_id != _leave_operation.source_session:
		return
	if not receipt.ok:
		_leave_operation = {}
		return
	if _leave_operation.kind == "quit":
		_guard.call("release")
		get_tree().quit()
		return
	var target: String = _leave_operation.target_hospital_id
	var records: Array[Dictionary] = _snapshots.list_commits(target)
	if records.is_empty():
		if target in _snapshots.hospital_ids():
			_status.text = "目标医院没有完整有效的保存点，原医院保留。"
			_leave_operation = {}
			return
		_candidate = FeasibilityHospitals.create(target,true,_content)
	else:
		var loaded: Dictionary = _snapshots.load_commit(target,records[0].snapshot_id)
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
	# Candidate resources are prepared before the main-thread publication boundary.
	var candidate_view: HospitalView = HospitalView.new(_content)
	_viewport.add_child(candidate_view)
	candidate_view.visible = false
	candidate_view.bind(_candidate,_observed_floor)
	if not candidate_view.bind_error.is_empty():
		_status.text = "切院失败，原医院保留："+candidate_view.bind_error
		_viewport.remove_child(candidate_view)
		candidate_view.queue_free()
		_candidate = null
		_leave_operation = {}
		return
	_viewport.remove_child(_view)
	_view.queue_free()
	_view = candidate_view
	_view.visible = true
	_simulation = HospitalSimulation.new(_candidate,_content)
	_loading_session = HospitalSnapshots.uuid()
	_saved_revision = int(_candidate.facts.world_revision) if not records.is_empty() else -1
	_candidate = null
	_leave_operation = {}
	_drafts.clear()
	_status.text = "已进入另一座医院，医院保持暂停。"

func _request_quit() -> void:
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
	_leave_operation = {"kind":"quit","source_session":_loading_session,"request_id":started.request.request_id}
	_status.text = "正在保存退出检查点…"

func _change_floor(floor_id: int) -> void:
	if _view != null:
		_observed_floor = floor_id
		_view.bind(_simulation.world,floor_id)

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
	if _simulation==null or _selected_actor.is_empty() or not _leave_operation.is_empty():
		return
	var command_id: String = HospitalSnapshots.uuid()
	_simulation.enqueue({"id":command_id,"hospital_id":_simulation.world.facts.hospital_id,"kind":"move_actor","actor_id":_selected_actor,
		"floor_id":floor_id,"cell":[47,93] if floor_id==1 else [35,83]})
	_simulation.drain_commands()
	var receipt: Dictionary = _simulation.world.facts.command_receipts.get(command_id,{})
	_status.text = "已安排实际通行，运行后会沿路线前往目标楼层。" if receipt.get("accepted",false) else str(receipt.get("reason","当前角色不可移动"))

func _world_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _view != null:
		_selected_actor = _view.pick(event.position*Vector2(_viewport.size)/_world_container.size)
	if event is InputEventMouseButton and event.pressed and _view!=null:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			_view.camera.size = clampf(_view.camera.size+(2.0 if event.button_index==MOUSE_BUTTON_WHEEL_DOWN else -2.0),18.0,90.0)

func _update_details() -> void:
	var world: HospitalWorld = _simulation.world
	var paused: bool = _speed==0 or not _pause_tokens.is_empty() or not _leave_operation.is_empty()
	_clock.text = "%s   %s   %s   资金 %d · 治疗包 %d" % [world.facts.display_name,world.clock_text(),"暂停" if paused else str(_speed)+"×",world.money(),int(world.facts.inventory.units)]
	var lines: PackedStringArray = PackedStringArray(["[b]院内情况[/b]","观察 %dF" % _observed_floor])
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
	_details.text = "\n".join(lines)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_request_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_pause_tokens["focus"] = true
		_accumulator = 0.0
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		_pause_tokens.erase("focus")
		_accumulator = 0.0

static func _phase_name(phase: String) -> String:
	return {"arrival":"到院","wait_reception":"等候接待","reception":"正在接待","wait_gp":"等候初诊","gp":"初诊中",
		"wait_spectrum":"等候光谱检查","spectrum":"光谱检查中","wait_resonance":"等候共振检查","resonance":"共振检查中",
		"wait_consult":"等候方案会诊","consult":"方案会诊中","wait_outpatient":"等候门诊治疗","outpatient":"治疗中",
		"wait_surgery":"手术准备","surgery":"手术进行中","wake":"治疗完成，苏醒中","transfer":"正在转床",
		"recovery":"住院恢复与护理","round_wait":"等待出院查房","round":"出院查房","leaving":"正在离院","departed":"已离院"}.get(phase,phase)
