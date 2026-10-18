class_name HospitalStaffLifePanel
extends HospitalActionPanel

var _staff: OptionButton

func build_controls() -> void:
	heading("员工生活")
	_staff = choice("员工",entity_choices("staff"))
	var facilities: Array = [{"id":"","name":"自动选择合适设施"}]
	for entry: Dictionary in entity_choices("facilities"):
		if not simulation.content.definition("staff_recreation_equipment",simulation.world.facts.facilities[entry.id].definition_id).is_empty():
			facilities.append(entry)
	var facility: OptionButton = choice("娱乐设施",facilities)
	action("安排娱乐",func() -> void: send("staff_recreation",{"staff_id":selected(_staff),"facility_id":selected(facility)}))
	note("休息、睡眠和离院会按需求自动安排，正在承担的工作先完成安全交接。")
	var settings: Dictionary = simulation.world.facts.get("staff_life",{}).get("settings",{})
	var maximum: SpinBox = number("同时娱乐人数上限",0,30,int(settings.get("maximum_recreation",2)))
	action("保存娱乐上限",func() -> void: send("set_staff_recreation",{"maximum":int(maximum.value),"roles":settings.get("roles",[])}))
	report(_status)

func _status() -> String:
	var staff: Dictionary = simulation.world.facts.staff.get(selected(_staff),{})
	if staff.is_empty():
		return "暂无员工"
	var task: Dictionary = staff.get("life_task",{})
	var activity: Dictionary = {"rest":"休息","sleep":"睡眠","leave":"休假","recreation":"娱乐"}
	return "精力 %.0f · 疲劳 %.0f · 压力 %.0f\n睡眠待补 %.1f 秒\n%s\n%s" % [float(staff.get("energy",0)),float(staff.get("fatigue",0)),float(staff.get("stress",0)),float(staff.get("sleep_remaining_ticks",0))*WorldState.TICK_SECONDS,activity.get(task.get("kind",""),"目前没有生活安排"),str(staff.get("life_reason",""))]
