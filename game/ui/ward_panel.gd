class_name HospitalWardPanel
extends HospitalActionPanel

signal locate_requested(entity_id: String)

var _visit_id: String = ""
var _visits: OptionButton
var _beds: OptionButton
var _nurses: OptionButton
var _wards: OptionButton
var _transfer: Button
var _refer: Button
var _allow: Button
var _decline: Button

const STATES: Dictionary = {
	"reserved":"已承诺床位", "transfer":"护送转床", "recovery":"住院恢复",
	"round_wait":"等待出院查房", "round":"查房中", "release_wait":"等待安全离床",
	"referral_release":"等待安全转诊", "surgery":"手术中", "wake":"苏醒中",
	"to_waiting":"正前往候诊区", "waiting":"在候诊区等候", "to_bed":"正前往床边",
	"visiting":"床边探视", "yielding":"为护理让出床边", "leaving":"正在离院"
}

func build_controls() -> void:
	heading("手术与住院")
	note("床位承诺沿原病例保留。护理、查房与家属来院按实际现场推进。")
	var entries: Array = []
	for id: String in simulation.world.ids("visits"):
		var visit: Dictionary = simulation.world.facts.visits[id]
		entries.append({"id":id,"name":_actor_name(str(visit.actor_id))+" · "+id})
	_visits = choice("病例",entries)
	_visits.fit_to_longest_item = false
	_visits.clip_text = true
	for index: int in _visits.item_count:
		if str(_visits.get_item_metadata(index))==_visit_id: _visits.select(index)
	_visit_id = selected(_visits)
	_visits.item_selected.connect(func(_index: int) -> void: _visit_id = selected(_visits))
	action("刷新床位与人员",rebuild)
	action("定位患者",func() -> void:
		var visit: Dictionary = simulation.world.facts.visits.get(_visit_id,{})
		if not visit.is_empty(): locate_requested.emit(str(visit.actor_id)))
	action("定位承诺床位",_locate_bed)
	var beds: Array = []
	for id: String in simulation.world.ids("facilities"):
		var facility: Dictionary = simulation.world.facts.facilities[id]
		var definition: Dictionary = simulation.content.facility_definition(str(facility.definition_id))
		if "bed" in definition.get("integrated_functions",[]):
			beds.append({"id":id,"name":str(definition.get("name","病床"))+" · "+id})
	_beds = choice("安全转床目标（提交时核验）",beds)
	_beds.fit_to_longest_item = false
	_beds.clip_text = true
	_transfer = action("申请安全转床",func() -> void: send("clinical_transfer_bed",{"visit_id":_visit_id,"bed_id":selected(_beds)}),false)
	_refer = action("申请住院安全转诊",func() -> void: send("clinical_ward_refer",{"visit_id":_visit_id}),false)
	var nurses: Array = []
	for id: String in simulation.world.ids("staff"):
		var staff: Dictionary = simulation.world.facts.staff[id]
		if staff.get("role","")=="nurse" and "q_ward" in staff.get("certificates",[]):
			nurses.append({"id":id,"name":_actor_name(id)})
	var wards: Array = []
	for id: String in simulation.world.ids("rooms"):
		if simulation.world.facts.rooms[id].get("kind","")=="ward": wards.append({"id":id,"name":"病房 · "+id})
	_nurses = choice("病房护士",nurses)
	_wards = choice("覆盖病房",wards)
	_nurses.fit_to_longest_item = false
	_nurses.clip_text = true
	_wards.fit_to_longest_item = false
	_wards.clip_text = true
	action("安排护士到病房",func() -> void: send("clinical_assign_ward",{"staff_id":selected(_nurses),"ward_id":selected(_wards)}),not nurses.is_empty() and not wards.is_empty())
	_allow = action("允许家属探视",func() -> void: send("clinical_visit_consent",{"visit_id":_visit_id,"allow":true}),false)
	_decline = action("婉拒探视（无惩罚）",func() -> void: send("clinical_visit_consent",{"visit_id":_visit_id,"allow":false}),false)
	report(_details)

func _actor_name(id: String) -> String:
	return str(simulation.world.facts.actors.get(id,{}).get("name",id))

func _locate_bed() -> void:
	var facts: Dictionary = simulation.world.facts
	for stay: Dictionary in facts.get("ward_stays",{}).values():
		if facts.get("attempts",{}).get(stay.get("attempt_id",""),{}).get("visit_id","")==_visit_id:
			locate_requested.emit(str(stay.bed_id))
			return
	for preparation: Dictionary in facts.get("preparations",{}).values():
		if preparation.get("visit_id","")==_visit_id and not str(preparation.get("bed_id","")).is_empty():
			locate_requested.emit(str(preparation.bed_id))
			return

func _details() -> String:
	var facts: Dictionary = simulation.world.facts
	var visit: Dictionary = facts.get("visits",{}).get(_visit_id,{})
	_allow.disabled = visit.is_empty() or bool(visit.get("visitor_consent",true))
	_decline.disabled = visit.is_empty() or not bool(visit.get("visitor_consent",true))
	_transfer.disabled = true
	_refer.disabled = true
	if visit.is_empty(): return "尚无病例。手术、床位承诺和家属到场后会显示于此。"
	var queued: int = 0
	for ticket: Dictionary in facts.get("tickets",{}).values():
		if ticket.get("kind","")=="surgery": queued += 1
	var lines: Array[String] = ["手术候诊 %d 位 · 真实住院承诺 %d 项" % [queued,facts.get("ward_stays",{}).size()]]
	var sessions: Dictionary = facts.get("sessions",{})
	for active: Dictionary in sessions.values():
		if active.get("visit_id","")==_visit_id and active.get("kind","") in ["surgery","wake","care","round"]:
			var kind: String = str(active.kind)
			var label: String = "床边护理" if kind=="care" else str(STATES.get(kind,"医疗服务"))
			lines.append("%s · 剩余约 %d 医院分钟\n设施：%s" % [label,ceili(float(active.get("remaining_ticks",0))/12.5),str(active.get("facility_id",""))])
	for stay: Dictionary in facts.get("ward_stays",{}).values():
		var attempt: Dictionary = facts.get("attempts",{}).get(stay.get("attempt_id",""),{})
		if attempt.get("visit_id","")!=_visit_id: continue
		var phase: String = str(stay.get("phase",""))
		_transfer.disabled = not phase in ["recovery","round_wait","round"] or _beds.item_count==0
		_refer.disabled = not phase in ["recovery","round_wait","round"]
		var nurse: Dictionary = facts.get("staff",{}).get(stay.get("nurse_id",""),{})
		var bed: Dictionary = facts.get("facilities",{}).get(stay.get("bed_id",""),{})
		lines.append("%s · %s\n恢复剩余工作量约 %d 医院分钟\n主动护理：%s\n查房医生：%s" % [str(STATES.get(phase,"住院处理中")),str(stay.get("bed_id","")),ceili(float(stay.get("remaining_ticks",0))/12.5),"已完成" if stay.get("care_completed",false) else "尚未完成",_actor_name(str(stay.get("round_doctor_id","")))])
		lines.append("覆盖护士：%s\n当班：%s · 分配于本病房：%s" % [_actor_name(str(stay.get("nurse_id",""))),"是" if nurse.get("on_shift",false) else "否","是" if not nurse.is_empty() and nurse.get("ward_id","")==bed.get("room_id","") else "否"])
		var nurse_actor: Dictionary = facts.get("actors",{}).get(stay.get("nurse_id",""),{})
		var location: Dictionary = nurse_actor.get("location",{})
		var ward: Dictionary = facts.get("rooms",{}).get(bed.get("room_id",""),{})
		if location.get("kind","")=="floor" and not ward.is_empty():
			var area: Rect2 = Rect2(float(ward.origin[0]),float(ward.origin[1]),float(ward.size[0]),float(ward.size[1]))
			var inside: bool = int(location.floor_id)==int(ward.floor_id) and area.has_point(Vector2(float(location.cell[0]),float(location.cell[1])))
			lines.append("护士现场："+("已在病房内" if inside else "尚未到本病房"))
	for pending: Dictionary in facts.get("preparations",{}).values():
		if pending.get("visit_id","")==_visit_id:
			lines.append("术前/治疗准备：%s\n承诺床位：%s" % [str(pending.get("facility_id","")),str(pending.get("bed_id","无住院床位"))])
	var reason: String = str(visit.get("waiting_reason",""))
	if not reason.is_empty(): lines.append("当前阻碍："+reason)
	lines.append("家属探视："+("允许" if visit.get("visitor_consent",true) else "已婉拒"))
	var relatives: Dictionary = facts.get("visitors",{})
	for request: Dictionary in relatives.get("requests",{}).values():
		if request.get("visit_id","")==_visit_id: lines.append("家属有到场意向，正在等待真实入口与候诊位置。")
	for relative: Dictionary in relatives.get("stays",{}).values():
		if relative.get("visit_id","")!=_visit_id: continue
		lines.append("%s · %s\n%s%s" % [_actor_name(str(relative.actor_id)),"陪诊" if relative.get("purpose","")=="companion" else "探视",str(STATES.get(str(relative.get("phase","")),"家属在院")),"\n"+str(relative.waiting_reason) if not str(relative.get("waiting_reason","")).is_empty() else ""])
	return "\n\n".join(lines)
