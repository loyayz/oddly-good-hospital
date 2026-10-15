class_name HospitalFinancePanel
extends HospitalActionPanel

var _day: int = -1
var _page: int = 0
var _view_id: String = ""

func build_controls() -> void:
	heading("财务")
	var service: Variant = simulation.services.finance
	var info: Dictionary = service.query(simulation.world,_day,_page,12)
	note("实际现金 ¥%s\n第%s日已记账：现金变化 ¥%s · 经营盈余 ¥%s" % [info.cash,info.day,info.today.cash_change,info.today.operating_surplus])
	var day_input: SpinBox = number("账目日期",1,maxi(1,simulation.world.sim_tick/WorldState.TICKS_PER_DAY+1),int(info.day))
	day_input.value_changed.connect(func(value: float) -> void: _day=int(value); _page=0; rebuild())
	var picker: OptionButton = choice("账页",info.views)
	for index: int in range(picker.item_count):
		if str(picker.get_item_metadata(index))==_view_id: picker.select(index)
	_view_id=selected(picker)
	picker.item_selected.connect(func(_index: int) -> void: _view_id=selected(picker); _page=0; rebuild())
	if not info.views.is_empty():
		var view: Dictionary = info.views[picker.selected]
		note("合计 ¥%s · 共%s笔 · 第%s页" % [view.amount,view.row_count,_page+1])
		if view.rows.is_empty(): note("这一页没有已结算账目。接诊收入在实际结算后记入。")
		for row: Dictionary in view.rows:
			note("%s\n金额 ¥%s · 医院支付 ¥%s · 代付 ¥%s" % [row.get("summary",row.get("funding_source","费用援助")),row.amount,row.get("hospital_paid",0),row.get("direct_paid",0)])
		action("上一页账目",func() -> void: _page-=1; rebuild(),_page>0)
		action("下一页账目",func() -> void: _page+=1; rebuild(),(_page+1)*12<int(view.row_count))
	heading("未来三日预测")
	note("预测不计入可用现金，按当前人员和布局估算。未计未来诊疗收入、尚未发生故障与待生效变更。")
	for row: Dictionary in info.forecast.slice(0,3):
		note("第%s日预计：工资 ¥%s · 运营 ¥%s\n预计补助 ¥%s · 期末现金 ¥%s" % [row.day,row.wages,row.operations,row.subsidy,row.closing_cash])
	var memo: TextEdit = TextEdit.new()
	memo.custom_minimum_size.y=90
	memo.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	memo.text=info.saving_note
	field("经营便签",memo)
	action("保存便签",func() -> void: send("finance_note",{"text":memo.text}))
	note("恢复经营援助在资金与诊疗能力满足条件时提供实际支持。归还借用设备须先结束真实占用。")
	action("申请恢复经营援助",func() -> void: send("finance_rescue"),info.rescue_available)
	action("归还援助借用品",func() -> void: send("finance_return_rescue"))
	action("刷新实际账目",rebuild)
