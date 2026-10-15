class_name HospitalWaitingPanel
extends HospitalActionPanel

var _visit_id: String = ""
var _page: int = 0
var _seat_page: int = 0

func build_controls() -> void:
	heading("候诊生活")
	var visits: Array = []
	for id: String in simulation.world.ids("visits"):
		var visit: Dictionary = simulation.world.facts.visits[id]
		if str(visit.phase).begins_with("wait_"):
			visits.append({"id":id,"name":simulation.world.facts.actors[visit.actor_id].name})
	if visits.is_empty():
		note("目前没有候诊患者。生活暂离会保留原票号，安全完成后沿路返回。")
		action("刷新候诊患者",rebuild)
		return
	_page = clampi(_page,0,maxi(0,(visits.size()-1)/12))
	var picker: OptionButton = choice("候诊患者 · 第%d页" % (_page+1),visits.slice(_page*12,_page*12+12))
	for index: int in range(picker.item_count):
		if str(picker.get_item_metadata(index))==_visit_id: picker.select(index)
	_visit_id = selected(picker)
	picker.item_selected.connect(func(_index: int) -> void: _visit_id = selected(picker); _seat_page=0; rebuild())
	action("上一页",func() -> void: _page-=1; rebuild(),_page>0)
	action("下一页",func() -> void: _page+=1; rebuild(),(_page+1)*12<visits.size())
	var service: Variant = simulation.services.waiting
	report(func() -> String:
		var info: Dictionary = service.patient_summary(simulation.world,_visit_id)
		return "票号：%s\n%s\n%s\n%s" % [info.get("ticket_id",""),info.get("reason",""),info.get("scene",""),"、".join(info.get("reasons",[]))])
	var seats: Array = []
	for candidate: Dictionary in service.seat_candidates(simulation.world,_visit_id):
		seats.append({"id":candidate.facility_id,"name":"%s · 步行约%.1f秒" % [candidate.facility_id,float(candidate.travel_ticks)*0.1]})
	_seat_page=clampi(_seat_page,0,maxi(0,(seats.size()-1)/12))
	var seat: OptionButton = choice("当前合法空座 · 第%d页" % (_seat_page+1),seats.slice(_seat_page*12,_seat_page*12+12))
	action("上一页空座",func() -> void: _seat_page-=1; rebuild(),_seat_page>0)
	action("下一页空座",func() -> void: _seat_page+=1; rebuild(),(_seat_page+1)*12<seats.size())
	note("无合法空座时可继续原地候诊；饮水、如厕和叫号优先安全完成。")
	action("前往所选座位",func() -> void: send("waiting_select_seat",{"visit_id":_visit_id,"facility_id":selected(seat)}),not seats.is_empty())
	action("离开当前座位",func() -> void: send("waiting_release_seat",{"visit_id":_visit_id}))
	action("重新查看空座",rebuild)
