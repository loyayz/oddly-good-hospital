class_name HospitalMaintenancePanel
extends HospitalActionPanel

var _facility_id: String = ""
var _page: int = 0

func build_controls() -> void:
	heading("设备维护")
	var service: Variant = simulation.services.maintenance
	var policy: OptionButton = choice("维护策略",simulation.content.catalog.get("maintenance_policies",[]))
	var state: Dictionary = service.query(simulation.world)
	for index: int in range(policy.item_count):
		if str(policy.get_item_metadata(index))==str(state.policy_id): policy.select(index)
	action("应用维护策略",func() -> void: send("maintenance_policy",{"policy_id":selected(policy)}))
	var facilities: Array = entity_choices("facilities")
	_page = clampi(_page,0,maxi(0,(facilities.size()-1)/16))
	var picker: OptionButton = choice("设备 · 第%d页" % (_page+1),facilities.slice(_page*16,_page*16+16))
	for index: int in range(picker.item_count):
		if str(picker.get_item_metadata(index))==_facility_id: picker.select(index)
	_facility_id=selected(picker)
	picker.item_selected.connect(func(_index: int) -> void: _facility_id=selected(picker); rebuild())
	action("上一页设备",func() -> void: _page-=1; rebuild(),_page>0)
	action("下一页设备",func() -> void: _page+=1; rebuild(),(_page+1)*16<facilities.size())
	if _facility_id.is_empty(): note("尚无实际设备。家具及免维护附件无需维修。"); return
	var quote: Dictionary = service.upgrade_quote(simulation.world,{"facility_id":_facility_id})
	note("下一等级当前报价 ¥%s\n%s" % [quote.cost,quote.reason])
	var hospital_paid: int = mini(HospitalLedger.balance(simulation.world),int(quote.cost)) if simulation.world.facts.mode=="creative" else int(quote.cost)
	note(payment_summary(hospital_paid))
	action("为这台设备安排保养",func() -> void: send("maintenance_order",{"facility_id":_facility_id}))
	action("确认升级这台设备",func() -> void: send("machine_upgrade",{"facility_id":_facility_id}),quote.ok)
	var current: Dictionary = service.query(simulation.world,_facility_id)
	for collection: String in ["jobs","upgrades"]:
		var rows: Array = current[collection]
		if rows.is_empty(): note("这台设备暂无"+("维护工单" if collection=="jobs" else "升级施工"))
		var picker_job: OptionButton = choice("维护工单" if collection=="jobs" else "升级工单",rows)
		var detail: Label = note("")
		var show_detail: Callable = func() -> void:
			if rows.is_empty(): return
			var row: Dictionary = rows[picker_job.selected]
			detail.text="剩余 %.1f秒\n%s" % [float(row.get("remaining_milli",0))/1000.0,row.get("reason","")]
		picker_job.item_selected.connect(func(_index: int) -> void: show_detail.call())
		show_detail.call()
		for operation: Dictionary in [{"id":"pause","name":"暂停"},{"id":"resume","name":"继续"},{"id":"cancel","name":"取消可取消部分"}]:
			action(operation.name,func() -> void:
				var key: String = "job_id" if collection=="jobs" else "order_id"
				send(("maintenance_" if collection=="jobs" else "upgrade_")+str(operation.id),{key:selected(picker_job)}),not rows.is_empty())
	note("维修与已开工保养须安全完成。缺维修员、工具或路线时保留剩余工作；解除原因后继续原单。")
	action("刷新工单与报价",rebuild)
