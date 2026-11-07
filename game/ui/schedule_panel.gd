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
	_preview = note("预览只生成草案；确认后才应用。医生建议不调整护士、接待等岗位。")
	action("预览所选员工修改",_preview_manual)
	action("预览医生建议排班",_preview_suggestion)
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
	if _preview!=null: _preview.text = "尚未预览。修改后请重新预览，再应用草案。"
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
	var lines: PackedStringArray = ["今日有效排班（草案，未应用）", "已过班次仅作排班记录，今日覆盖保留；人数仅表示排班资格，不代表已到岗或整班可用。休假与班次部分重叠也不计入。"]
	for row: Dictionary in rows:
		lines.append("第%d班：初诊医生%d · 手术医生%d · 查房医生%d\n护士%d（护理/导诊%d · 检查%d · 手术%d · 病房资格%d）\n接待%d · 清洁%d · 研究%d · 装修%d · 培训%d" % [int(row.shift)+1,row.outpatient,row.surgeon,row.ward,row.nurse,row.care,row.nurse_diagnosis,row.nurse_surgery,row.ward_nurse,row.receptionist,row.cleaner,row.researcher,row.decorator,row.training])
		if int(row.leave_excluded)>0: lines.append("休假重叠未计入：%d人" % row.leave_excluded)
		lines.append("；".join(row.gaps) if not row.gaps.is_empty() else "未发现上述排班零人缺口；仍需核验实际服务条件")
	lines.append("护士能力人数可重叠，不能相加或同时用于导诊、检查、手术和病房。仍须核对各台/各病房独立人员、技能等级、工作池、路线及工作时窗。其他岗位仅列人数，不判断工作量是否足够。")
	lines.append("当前实际状态（不随草案变化）：")
	if simulation.services.has("floor_guidance"):
		lines.append(simulation.services.floor_guidance.summary(simulation.world))
	for id: String in simulation.world.ids("staff"):
		var staff: Dictionary = simulation.world.facts.staff[id]
		if staff.get("departed",false): continue
		var reasons: PackedStringArray = []
		var job: String = str(staff.get("active_job_id",""))
		if job.begins_with("floor_desk:"): reasons.append("导诊岗位已占用，不能同时承担其他护理")
		elif not job.is_empty(): reasons.append("已有工作占用")
		if simulation.world.facts.moves.has(id): reasons.append("途中")
		if staff.get("life_task",{}).get("phase","idle")!="idle": reasons.append("休息/生活任务中")
		if staff.get("block_new_work",false): reasons.append("暂不接新工作")
		if not reasons.is_empty(): lines.append("%s：%s" % [simulation.world.facts.actors.get(id,{}).get("name",id),"、".join(reasons)])
	lines.append("以上为预览时快照；实际接单还须重新核验睡眠、休假、占用和到场。")
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
