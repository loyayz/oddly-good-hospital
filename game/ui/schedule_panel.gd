class_name HospitalSchedulePanel
extends HospitalActionPanel

const KINDS: Dictionary = {"work":"岗位工作","outpatient":"门诊","surgery":"手术","round":"查房","training":"培训","rest":"休息"}
var _staff: OptionButton
var _slots: Array[OptionButton] = []
var _proposal: Dictionary = {}
var _preview: Label

func build_controls() -> void:
	heading("班表与休假")
	_staff = choice("员工",entity_choices("staff"))
	_staff.item_selected.connect(func(_index: int) -> void: _load_staff())
	_slots.clear()
	var entries: Array = []
	for key: String in KINDS:
		entries.append({"id":key,"name":KINDS[key]})
	for slot: int in int(simulation.content.balance.schedule.shifts_per_day):
		_slots.append(choice("第%d班" % (slot+1),entries))
		var index: int = slot
		action("切换第%d班锁定" % (slot+1),func() -> void: _toggle_lock(index))
	_preview = note("修改后先预览覆盖情况，再应用班表。")
	action("预览当前班表",_preview_manual)
	action("预览建议排班",_preview_suggestion)
	action("应用已预览班表",func() -> void:
		if not _proposal.is_empty():
			send("apply_schedule",_proposal)
	)
	var days: SpinBox = number("休假天数",1,3,1)
	var start: OptionButton = choice("开始时间",[{"id":"now","name":"现在（安全交接后离院）"},{"id":"next_day","name":"明天"}])
	action("安排休假",func() -> void: send("plan_leave",{"staff_id":selected(_staff),"days":int(days.value),"start":selected(start)}))
	action("取消假期 / 召回",func() -> void: send("cancel_leave",{"staff_id":selected(_staff)}))
	report(_status)
	_load_staff()

func _load_staff() -> void:
	_proposal = {}
	var schedule: Array = simulation.world.facts.staff.get(selected(_staff),{}).get("schedule",[])
	for index: int in mini(schedule.size(),_slots.size()):
		for option: int in _slots[index].item_count:
			if _slots[index].get_item_metadata(option)==schedule[index].kind:
				_slots[index].select(option)

func _toggle_lock(slot: int) -> void:
	var staff: Dictionary = simulation.world.facts.staff.get(selected(_staff),{})
	if not staff.is_empty():
		send("set_schedule_lock",{"staff_id":selected(_staff),"shift":slot,"locked":not bool(staff.schedule[slot].locked)})

func _preview_manual() -> void:
	var staff: Dictionary = simulation.world.facts.staff.get(selected(_staff),{})
	if staff.is_empty():
		return
	var schedule: Array = staff.schedule.duplicate(true)
	for index: int in _slots.size():
		schedule[index].kind = selected(_slots[index])
	var suggestion: Dictionary = simulation.services.scheduler.suggestion(simulation.world)
	_proposal = {"basis":suggestion.basis,"changes":[{"staff_id":selected(_staff),"schedule":schedule}]}
	_show_coverage(simulation.services.scheduler.coverage(simulation.world,_proposal.changes))

func _preview_suggestion() -> void:
	_proposal = simulation.services.scheduler.suggestion(simulation.world)
	_show_coverage(_proposal.coverage)

func _show_coverage(rows: Array) -> void:
	var lines: PackedStringArray = []
	for row: Dictionary in rows:
		lines.append("第%d班：门诊%d · 手术%d · 查房%d · 护士%d\n%s" % [int(row.shift)+1,row.outpatient,row.surgeon,row.ward,row.nurse,"；".join(row.gaps) if not row.gaps.is_empty() else "覆盖完整"])
	_preview.text = "\n".join(lines)

func _status() -> String:
	var staff: Dictionary = simulation.world.facts.staff.get(selected(_staff),{})
	if staff.is_empty():
		return "暂无员工"
	var lines: PackedStringArray = []
	for index: int in staff.get("schedule",[]).size():
		var entry: Dictionary = staff.schedule[index]
		lines.append("第%d班：%s%s" % [index+1,KINDS.get(entry.kind,entry.kind)," · 已锁定" if entry.locked else ""])
	lines.append(str(staff.get("schedule_reason","")))
	var leave: Dictionary = staff.get("leave_plan",{})
	if not leave.is_empty():
		lines.append("休假：%d天 · %s" % [int(leave.get("days",0)),"待离院" if leave.get("state","")=="planned" else "休假中"])
	return "\n".join(lines)
