class_name HospitalPlansPanel
extends HospitalActionPanel

var _visits: OptionButton
var _plans: OptionButton
var _visit_id: String = ""
var _plan_id: String = ""
var _apply: Button
var _auto: Button

func build_controls() -> void:
	heading("治疗方案")
	note("默认由医生自主选择。当前报价随真实团队、设备和治疗包变化；开工前再次核验。")
	var entries: Array = []
	for id: String in simulation.world.ids("visits"):
		var visit: Dictionary = simulation.world.facts.visits[id]
		entries.append({"id":id,"name":str(simulation.world.facts.actors.get(visit.actor_id,{}).get("name",id))+" · "+id})
	_visits = choice("病例",entries)
	_visits.fit_to_longest_item = false
	_visits.clip_text = true
	for index: int in _visits.item_count:
		if str(_visits.get_item_metadata(index))==_visit_id: _visits.select(index)
	_visit_id = selected(_visits)
	_visits.item_selected.connect(func(_index: int) -> void:
		_visit_id = selected(_visits)
		_populate_plans())
	_plans = choice("比较方案",[])
	_plans.fit_to_longest_item = false
	_plans.clip_text = true
	_plans.item_selected.connect(func(_index: int) -> void: _plan_id = selected(_plans))
	_populate_plans()
	action("刷新病例与方案",rebuild)
	_apply = action("选择当前合法方案",_submit,false)
	_auto = action("恢复医生自主选择",func() -> void: send("clinical_auto_plan",{"visit_id":_visit_id}),false)
	report(_details)

func _populate_plans() -> void:
	_plans.clear()
	for quote: Dictionary in simulation.clinic.compare_plans(simulation.world,_visit_id):
		var id: String = str(quote.plan_id)
		var plan: Dictionary = simulation.content.definition("treatment_plans",id)
		_plans.add_item(str(plan.get("name",id)))
		_plans.set_item_metadata(_plans.item_count-1,id)
		if id==_plan_id: _plans.select(_plans.item_count-1)
	_plan_id = selected(_plans)

func _submit() -> void:
	var quote: Dictionary = simulation.clinic.plan_quote(simulation.world,_visit_id,_plan_id)
	if quote.get("ok",false):
		send("clinical_select_plan",{"visit_id":_visit_id,"plan_id":_plan_id,"probability_bp":int(quote.probability_bp)})

func _details() -> String:
	var visit: Dictionary = simulation.world.facts.get("visits",{}).get(_visit_id,{})
	var waiting: bool = str(visit.get("phase","")).begins_with("wait_")
	_auto.disabled = not waiting
	_apply.disabled = true
	if visit.is_empty(): return "尚无病例。来院后可以比较适用于该病例的实际方案。"
	var decision: Dictionary = visit.get("plan_decision",{})
	var lines: Array[String] = ["当前决定："+("医生自主" if decision.is_empty() else str(simulation.content.definition("treatment_plans",str(decision.get("plan_id",""))).get("name","医生正在评估")))]
	if not str(decision.get("reason","")).is_empty(): lines.append(str(decision.reason))
	for quote: Dictionary in simulation.clinic.compare_plans(simulation.world,_visit_id):
		var id: String = str(quote.plan_id)
		var name: String = str(simulation.content.definition("treatment_plans",id).get("name",id))
		if id==_plan_id: _apply.disabled = not waiting or not bool(quote.get("ok",false))
		if not quote.get("ok",false):
			lines.append(name+"\n当前不可开工："+str(quote.get("reason","等待资源")))
			continue
		lines.append("%s\n当前资格满足 · 预计效果 %.1f%%\n治疗约 %d 医院分钟 · 恢复工作量约 %d 医院分钟\n治疗包 %d 包 · 设备收费 %d · 治愈收费 %d" % [name,float(quote.probability_bp)/100.0,ceili(float(quote.get("work_ticks",0))/12.5),ceili(float(quote.get("recovery_ticks",0))/12.5),int(quote.get("supply_units",0)),int(quote.get("facility_fee",0)),int(quote.get("cure_fee",0))])
	if not waiting: lines.append("当前安全医疗段完成后，才能更改方案。")
	return "\n\n".join(lines)
