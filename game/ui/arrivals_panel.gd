class_name HospitalArrivalsPanel
extends HospitalActionPanel

var _resident_page: int = 0

func build_controls() -> void:
	heading("来客与熟客")
	var service: Variant = simulation.services.arrivals
	report(func() -> String:
		var stats: Dictionary = service.daystats(simulation.world)
		var today: String = str(simulation.world.sim_tick/WorldState.TICKS_PER_DAY+1)
		var counts: Dictionary = stats.days.get(today,{})
		return "今日机会 %s · 实到 %s\n完诊 %s · 弃候 %s\n当前在院门诊 %s / %s\n今日客流 %s · 明日客流 %s\n%s" % [counts.get("opportunities",0),counts.get("arrived",0),counts.get("completed",0),counts.get("abandoned",0),stats.outpatients,stats.allowance,_preset_name(stats.today_preset),_preset_name(stats.tomorrow_preset),"正在接受新来客" if stats.intake_open else "已暂停新来客"])
	var presets: Array = []
	for id: String in simulation.content.balance.arrival_presets: presets.append({"id":id,"name":_preset_name(id)})
	var preset: OptionButton = choice("明日客流档",presets)
	action("设定明日客流",func() -> void: send("arrivals_preset",{"preset":selected(preset)}))
	action("立即开诊",func() -> void: send("arrivals_intake",{"open":true}))
	action("立即暂停新来客",func() -> void: send("arrivals_intake",{"open":false}))
	var mode: OptionButton = choice("明日客流模式",[{"id":"follow_capacity","name":"随医院能力成长"},{"id":"hold_capacity","name":"保持当前客流规模"}])
	action("设定明日客流模式",func() -> void: send("arrivals_scale",{"mode":selected(mode)}))
	note("机会依实际接诊能力生成；关诊、满员或准备不足时不保证到院。客流档与规模模式明日生效。")
	var disease: OptionButton = choice("病症权重",simulation.content.catalog.get("diseases",[]))
	var weight: SpinBox = number("权重（0为不接收）",0,3,1)
	action("应用病症权重",func() -> void: send("arrivals_weight",{"disease_id":selected(disease),"weight":int(weight.value)}))
	var residents: Array = []
	for id: String in simulation.world.facts.get("residents",{}):
		var resident: Dictionary = simulation.world.facts.residents[id]
		residents.append({"id":id,"name":str(resident.get("name",id))+(" · 已关注" if resident.get("remembered",false) else "")})
	_resident_page=clampi(_resident_page,0,maxi(0,(residents.size()-1)/16))
	var resident_picker: OptionButton = choice("真实居民 · 第%d页" % (_resident_page+1),residents.slice(_resident_page*16,_resident_page*16+16))
	if residents.is_empty(): note("还没有真实居民记录。实际接诊和离院后才形成回访经历。")
	action("记住这位熟客",func() -> void: send("resident_remember",{"resident_id":selected(resident_picker)}),not residents.is_empty())
	action("取消关注",func() -> void: send("resident_forget",{"resident_id":selected(resident_picker)}),not residents.is_empty())
	action("上一页居民",func() -> void: _resident_page-=1; rebuild(),_resident_page>0)
	action("下一页居民",func() -> void: _resident_page+=1; rebuild(),(_resident_page+1)*16<residents.size())
	action("刷新来客设置",rebuild)

func _preset_name(id: String) -> String:
	return str({"slow":"悠闲","normal":"日常","busy":"热闹","festival":"节庆"}.get(id,id))
