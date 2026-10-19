class_name HospitalClinicalPanel
extends HospitalActionPanel

signal locate_requested(entity_id: String)

var _visits: OptionButton
var _visit_id: String = ""
var _refer: Button

const PHASES: Dictionary = {
	"arrival":"正在到院", "wait_reception":"等待接待", "reception":"接待中",
	"wait_gp":"等待初诊", "gp":"初诊中", "wait_spectrum":"等待光谱检查",
	"spectrum":"光谱检查中", "wait_resonance":"等待共振检查", "resonance":"共振检查中",
	"wait_consult":"等待会诊", "consult":"会诊中", "wait_outpatient":"等待门诊治疗",
	"outpatient":"门诊治疗中", "wait_surgery":"等待手术", "surgery":"手术中",
	"wake":"苏醒中", "transfer":"转往病床", "recovery":"住院恢复",
	"round_wait":"等待出院查房", "round":"出院查房中", "ward_referral":"安全转诊中",
	"leaving":"正在离院", "departed":"已离院"
}

func build_controls() -> void:
	heading("病例与候诊")
	note("病例沿原号签推进；等待原因来自当前现场。")
	var entries: Array = []
	for id: String in simulation.world.ids("visits"):
		var visit: Dictionary = simulation.world.facts.visits[id]
		var actor: Dictionary = simulation.world.facts.actors.get(visit.actor_id,{})
		entries.append({"id":id,"name":str(actor.get("name","患者"))+" · "+id})
	_visits = choice("病例",entries)
	_visits.fit_to_longest_item = false
	_visits.clip_text = true
	for index: int in _visits.item_count:
		if str(_visits.get_item_metadata(index))==_visit_id:
			_visits.select(index)
	_visit_id = selected(_visits)
	_visits.item_selected.connect(func(_index: int) -> void: _visit_id = selected(_visits))
	action("刷新病例列表",rebuild)
	action("定位患者与当前阻碍",func() -> void:
		var visit: Dictionary = simulation.world.facts.visits.get(_visit_id,{})
		if not visit.is_empty(): locate_requested.emit(str(visit.actor_id)))
	_refer = action("友好转诊",func() -> void: send("clinical_refer",{"visit_id":_visit_id}),false)
	report(_details)

func _details() -> String:
	var facts: Dictionary = simulation.world.facts
	var active: int = 0
	var waiting: int = 0
	for visit_id: String in simulation.world.active_visit_ids():
		var visit: Dictionary = facts.visits[visit_id]
		if visit.get("phase","")!="departed": active += 1
		if str(visit.get("phase","")).begins_with("wait_"): waiting += 1
	var lines: Array[String] = ["在院 %d 位 · 候诊 %d 位" % [active,waiting]]
	var visit: Dictionary = facts.get("visits",{}).get(_visit_id,{})
	_refer.disabled = visit.is_empty() or not str(visit.get("phase","")).begins_with("wait_")
	if visit.is_empty():
		lines.append("尚无病例。开诊后，真实来院患者会出现在这里。")
		return "\n\n".join(lines)
	var phase: String = str(visit.get("phase",""))
	lines.append("当前阶段："+str(PHASES.get(phase,"诊疗进行中")))
	var ticket: Dictionary = facts.get("tickets",{}).get(visit.get("ticket_id",""),{})
	if not ticket.is_empty():
		lines.append("原号签：%s\n本段候诊已过约 %d 医院分钟" % [ticket.id,ceili(float(simulation.world.sim_tick-int(ticket.get("enqueued_tick",0)))/12.5)])
	else:
		lines.append("当前无需候诊号签")
	var reason: String = str(visit.get("waiting_reason",""))
	lines.append("当前阻碍："+(reason if not reason.is_empty() else "暂无；按当前流程继续"))
	lines.append("已完成诊疗尝试：%d" % visit.get("attempt_ids",[]).size())
	if phase in ["leaving","departed"]:
		var results: Dictionary = {"cured":"治愈", "referred":"转诊", "abandoned":"离开候诊", "retry":"重新评估"}
		lines.append("离院反馈："+str(results.get(str(visit.get("final_result","")),"正在整理")))
	return "\n\n".join(lines)
