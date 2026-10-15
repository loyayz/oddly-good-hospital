class_name HospitalEnvironmentPanel
extends HospitalActionPanel

signal location_requested(floor_id: int, cell: Array)
signal heatmap_requested(cells: Array)
var floor_id: int = 1
var _page: int = 0
var _cells: Array = []

func build_controls() -> void:
	heading("清洁与装修")
	var service: Variant = simulation.services.environment
	var floor_input: SpinBox = number("观察楼层",1,999,floor_id)
	floor_input.value_changed.connect(func(value: float) -> void: floor_id=int(value); _cells.clear(); heatmap_requested.emit([]); rebuild())
	var dirt: Array = []
	for item: Dictionary in simulation.world.facts.get("environment",{}).get("dirt",{}).values():
		if int(item.floor_id)==floor_id: dirt.append(item)
	if dirt.is_empty(): note("本层目前很清爽。实际产生垃圾后，清洁员会按可达路线处理。")
	_page = clampi(_page,0,maxi(0,(dirt.size()-1)/8))
	for item: Dictionary in dirt.slice(_page*8,_page*8+8):
		note("%s · %s格 · %s\n%s" % ["桶内垃圾" if not str(item.bin_id).is_empty() else "地面垃圾",item.cell,item.source_kind,item.reason])
		action("定位这处垃圾",func() -> void: location_requested.emit(int(item.floor_id),item.cell))
		action("优先处理这处垃圾",func() -> void: send("cleanup_pin",{"dirt_id":item.id}))
	action("上一页垃圾",func() -> void: _page-=1; rebuild(),_page>0)
	action("下一页垃圾",func() -> void: _page+=1; rebuild(),(_page+1)*8<dirt.size())
	var material: OptionButton = choice("装修材料",simulation.content.catalog.get("renovation_materials",[]))
	var plots: Array = simulation.world.facts.floors.overrides.get(str(floor_id),{}).get("plots",[])
	var reference: Array = [int(plots[0][0])*32+16,int(plots[0][1])*32+16] if not plots.is_empty() else [0,0]
	var x: SpinBox = number("目标格 X",-999,999,reference[0])
	var y: SpinBox = number("目标格 Y",-999,999,reference[1])
	var edge: OptionButton = choice("墙面朝向（地板忽略）",[{"id":"north","name":"北墙"},{"id":"south","name":"南墙"},{"id":"west","name":"西墙"},{"id":"east","name":"东墙"}])
	var observation: Label = note("")
	var observe: Callable = func() -> void:
		var current: Dictionary = service.environment_at(simulation.world,floor_id,[int(x.value),int(y.value)])
		observation.text = "本层所选格环境 %s · 噪声 %s · 垃圾 %s" % [current.value,current.noise,current.dirt]
	x.value_changed.connect(func(_value: float) -> void: observe.call())
	y.value_changed.connect(func(_value: float) -> void: observe.call())
	observe.call()
	action("显示这一格周围的环境热图",func() -> void:
		var cells: Array = []
		for dx: int in range(-4,5):
			for dy: int in range(-4,5):
				cells.append([int(x.value)+dx,int(y.value)+dy])
		heatmap_requested.emit(cells)
		location_requested.emit(floor_id,[int(x.value),int(y.value)]))
	action("隐藏环境热图",func() -> void: heatmap_requested.emit([]))
	note("热图只观察当前楼层：棕色较低，浅色居中，蓝色较高；未启用地面不着色。环境来源变化后需刷新采样。")
	var draft: Label = note("已选 %d 格" % _cells.size())
	action("添加这一格到装修草案",func() -> void:
		var unit: Dictionary = {"cell":[int(x.value),int(y.value)],"edge":selected(edge)}
		if not unit in _cells: _cells.append(unit)
		draft.text="已选 %d 格" % _cells.size())
	action("清空装修草案",func() -> void: _cells.clear(); draft.text="已选 0 格")
	var quote_label: Label = note("先选格，再查看当前报价。")
	var payload: Callable = func() -> Dictionary: return {"floor_id":floor_id,"material_id":selected(material),"units":_cells.duplicate(true),"allow_waiting":true}
	action("查看装修报价",func() -> void:
		var quote: Dictionary = service.renovation_quote(simulation.world,payload.call())
		quote_label.text="材料 ¥%s / 格 · 共 ¥%s · 工时 %s秒\n%s\n%s" % [quote.get("unit_price",0),quote.get("cost",0),quote.get("work_seconds",0),quote.get("reason",""),payment_summary(int(quote.get("cost",0)))])
	action("确认所选格装修",func() -> void: send("renovation_order",payload.call()))
	var orders: Array = []
	for order: Dictionary in simulation.world.facts.get("environment",{}).get("orders",{}).values():
		if int(order.floor_id)==floor_id and not order.phase in ["completed","cancelled"]: orders.append(order)
	var order_picker: OptionButton = choice("进行中装修",orders)
	order_picker.item_selected.connect(func(index: int) -> void: quote_label.text=str(orders[index].get("reason","")))
	for operation: Dictionary in [{"id":"pause","name":"暂停"},{"id":"resume","name":"继续"},{"id":"cancel","name":"取消未开工部分"}]:
		action(operation.name,func() -> void: send("renovation_"+str(operation.id),{"order_id":selected(order_picker)}),not orders.is_empty())
	note("取消时退还未开工材料；正在施工的格先安全完成。缺装修员或工具时保留原单等待。")
	action("刷新本层工作",rebuild)
