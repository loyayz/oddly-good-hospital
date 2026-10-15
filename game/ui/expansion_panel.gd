class_name HospitalExpansionPanel
extends HospitalActionPanel

signal floor_requested(floor_id: int)
signal location_requested(floor_id: int, cell: Array)
signal draft_changed(draft: Dictionary)
var _bound_session: String = ""
var _floor: SpinBox
var _plot: OptionButton
var _connections: OptionButton
var _orders: OptionButton
var _definition: OptionButton
var _x: SpinBox
var _y: SpinBox
var _rotation: OptionButton
var _quote: Dictionary = {}
var _draft: Dictionary = {}
var _kind: String = ""
var _result: Label

func attach(kernel: HospitalSimulation, active_session: GameSession) -> void:
	if _bound_session!=active_session.loading_session_id:
		clear_draft()
		_bound_session = active_session.loading_session_id
	super.attach(kernel,active_session)

func clear_draft() -> void:
	_quote = {}
	_draft = {}
	_kind = ""
	draft_changed.emit({})

func build_controls() -> void:
	heading("扩建与跨层交通")
	note("土地、楼板与交通分别核对。上层完工后仍需安装电梯站和实际诊疗配套。")
	_floor = number("目标楼层",1,10000,1)
	_floor.allow_greater = true
	action("观察这一层",func() -> void: floor_requested.emit(int(_floor.value)))
	var plots: Array = []
	for y: int in 3:
		for x: int in 3: plots.append({"id":"%d:%d" % [x,y],"name":"地块 %d-%d" % [x+1,y+1]})
	_plot = choice("目标地块",plots)
	action("核对1F购地",func() -> void: _preview("build_land",{"floor_id":1,"plot":_selected_plot()}))
	var connections: Array = []
	for id: String in simulation.world.ids("connectors"):
		var connection: Dictionary = simulation.world.facts.connectors[id]
		connections.append({"id":id,"name":str(simulation.content.definition("vertical_connectors",connection.definition_id).name)+" · "+id})
	_connections = choice("现有连接设施",connections)
	action("定位所选连接的主设备",func() -> void:
		var connection: Dictionary = simulation.world.facts.connectors.get(selected(_connections),{})
		if not connection.is_empty(): location_requested.emit(int(HospitalTransit.endpoints(connection).min()),connection.cell))
	action("沿所选电梯核对上一模块",func() -> void:
		var connection: Dictionary = simulation.world.facts.connectors.get(selected(_connections),{})
		if connection.is_empty(): return
		var plot: Array = [int(connection.cell[0])/32,int(connection.cell[1])/32]
		var target: int = int(simulation.world.facts.floors.completed_top_floor.get(HospitalSpace.plot_key(plot),1))+1
		_floor.value = target
		_preview("floor_purchase",{"source":"lift","connection_id":connection.id,"floor_id":target,"plot":plot}))
	action("核对本层其他地块",func() -> void: _preview("floor_purchase",{"source":"same_floor","floor_id":int(_floor.value),"plot":_selected_plot()}))
	_orders = choice("模块施工单",_order_entries())
	action("定位所选施工单工作点",func() -> void:
		var order: Dictionary = simulation.world.facts.floors.orders.get(selected(_orders),{})
		if not order.is_empty(): location_requested.emit(int(order.floor_id)-1,order.work_cell if not order.work_cell.is_empty() else [int(order.plot[0])*32,int(order.plot[1])*32]))
	for entry: Array in [["暂停模块施工","floor_pause"],["继续模块施工","floor_resume"],["取消模块并按余量退款","floor_cancel"]]:
		var kind: String = entry[1]
		action(entry[0],func() -> void: send(kind,{"order_id":selected(_orders)}))
	_definition = choice("新建交通设施",simulation.content.catalog.vertical_connectors)
	_x = number("横向格",0,95,51)
	_y = number("纵向格",0,95,89)
	_rotation = choice("朝向",[0,1,2,3])
	action("核对新建连接",func() -> void: _preview("connector_build",{"definition_id":selected(_definition),"cell":[int(_x.value),int(_y.value)],"floor_id":int(_floor.value),"rotation":int(selected(_rotation))}))
	action("核对安装下一站",func() -> void: _preview("connector_extend",{"connection_id":selected(_connections),"floor_id":int(_floor.value)}))
	action("核对拆除连接",func() -> void: _preview("connector_remove",{"connection_id":selected(_connections)}))
	_result = note("先核对完整条件，再确认。")
	action("确认当前报价",_confirm)
	action("取消当前扩建草案",func() -> void:
		clear_draft()
		_result.text = "扩建草案已取消，已付施工单保持原状态。")
	for input: SpinBox in [_floor,_x,_y]: input.value_changed.connect(func(_value: float) -> void: _invalidate())
	for picker: OptionButton in [_plot,_connections,_definition,_rotation]: picker.item_selected.connect(func(_index: int) -> void: _invalidate())
	report(func() -> String:
		var entries: Array = []
		for connection: Dictionary in simulation.world.facts.connectors.values(): entries.append({"id":connection.id,"name":str(simulation.content.definition("vertical_connectors",connection.definition_id).name)+" · "+connection.id})
		refresh_choices(_connections,entries)
		refresh_choices(_orders,_order_entries())
		var lines: PackedStringArray = ["实完高度："+JSON.stringify(simulation.world.facts.floors.get("completed_top_floor",{}))]
		for order: Dictionary in simulation.world.facts.floors.get("orders",{}).values():
			if not HospitalFloors.terminal(order): lines.append("%s · %dF · %.1f%% · %s" % [order.id,int(order.floor_id),100.0*(1.0-float(order.remaining_milli)/float(order.total_milli)),order.reason])
		for connection: Dictionary in simulation.world.facts.connectors.values(): lines.append("%s · %s · 车在%dF · %s" % [connection.id,str(HospitalTransit.endpoints(connection)),int(connection.floor_id),"故障，仅缓降" if connection.failed else connection.phase])
		return "\n".join(lines))

func _selected_plot() -> Array:
	var values: PackedStringArray = selected(_plot).split(":")
	return [int(values[0]),int(values[1])]

func _invalidate() -> void:
	_quote = {}
	_draft = {}
	_kind = ""
	draft_changed.emit({"editing":true})
	if _result!=null: _result.text = "目标条件已改变，请重新核对。"

func _order_entries() -> Array:
	var result: Array = []
	for order: Dictionary in simulation.world.facts.floors.get("orders",{}).values():
		if not HospitalFloors.terminal(order): result.append({"id":order.id,"name":"%dF · %s" % [int(order.floor_id),order.id]})
	return result

func _preview(kind: String, draft: Dictionary) -> void:
	_kind = kind
	_draft = draft.duplicate(true)
	match kind:
		"build_land": _quote = simulation.services.building.preview(simulation.world,draft.merged({"kind":kind}))
		"floor_purchase": _quote = simulation.services.floors.preview(simulation.world,draft)
		_: _quote = simulation.services.connectors.preview(simulation.world,kind,draft)
	_quote.erase("candidate")
	draft_changed.emit(_draft.duplicate(true))
	_result.text = str(_quote.get("reason","")) if not _quote.ok else "费用 %d，退款 %d。确认后按当前条件执行。" % [int(_quote.get("price",0)),int(_quote.get("refund",0))]

func _confirm() -> void:
	if not _quote.get("ok",false): return
	var payload: Dictionary = _draft.duplicate(true)
	match _kind:
		"build_land": payload.quote = _quote.quote
		"floor_purchase": payload.quote = {"price":_quote.price,"total_milli":_quote.total_milli,"floor_id":_quote.floor_id,"plot":_quote.plot}
		_: payload.quote = {"price":_quote.price,"refund":_quote.refund}
	send(_kind,payload)
