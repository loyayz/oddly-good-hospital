class_name HospitalSuppliesPanel
extends HospitalActionPanel

func build_controls() -> void:
	heading("治疗包")
	var service: Variant = simulation.services.supplies
	report(func() -> String:
		var info: Dictionary = service.query(simulation.world)
		return "实存 %s · 预留 %s · 可用 %s\n容量 %s · 当前单价 ¥%s\n自动采购：%s · 日常保留金 ¥%s" % [info.units,info.reserved,info.available,info.capacity,info.unit_price,"开启" if info.auto_restock else "关闭",info.reserve_budget])
	var quantity: SpinBox = number("购买数量",1,10000,20)
	var quote: Label = note("")
	var refresh_quote: Callable = func() -> void:
		var current: Dictionary = service.purchase_quote(simulation.world,int(quantity.value))
		quote.text = "总价 ¥%s · 医院支付 ¥%s · 代付 ¥%s\n%s" % [current.cost,current.hospital_paid,current.direct_paid,current.reason]
	quantity.value_changed.connect(func(_value: float) -> void: refresh_quote.call())
	refresh_quote.call()
	action("按当前报价采购",func() -> void: send("supply_purchase",{"units":int(quantity.value),"unit_price":service.unit_price()}))
	action("切换自动采购",func() -> void: send("supply_auto",{"enabled":not service.query(simulation.world).auto_restock}))
	var top_up: Dictionary = service.top_up(simulation.world)
	if top_up.is_empty():
		note("当前没有缺包待续项目。补货后原准备顺序继续，已经领用的包不会重复领取。")
	else:
		note("%s：补足 %s 包，当前报价 ¥%s。%s" % ["恢复缺货停工" if top_up.recovering else "补足首个待续项目",top_up.units,top_up.cost,top_up.reason])
		action("按缺口补足",func() -> void:
			var current: Dictionary = service.top_up(simulation.world)
			if not current.is_empty(): send("supply_purchase",{"units":current.units,"unit_price":current.unit_price}))
	var aid_units: int = int(simulation.content.balance.supplies.aid_purchase_units)
	var aid: Dictionary = service.purchase_quote(simulation.world,aid_units,"community_aid")
	note("社区援助：%s包 · 医院支付 ¥%s · 援助 ¥%s\n%s" % [aid_units,aid.hospital_paid,aid.direct_paid,aid.reason])
	action("申请本次治疗包援助",func() -> void: send("supply_aid",{"units":aid_units,"unit_price":service.unit_price()}))
	action("刷新报价与缺口",rebuild)
