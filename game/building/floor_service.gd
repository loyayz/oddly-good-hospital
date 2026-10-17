class_name HospitalFloors
extends RefCounted

const KINDS: Array[String] = ["floor_purchase","floor_pause","floor_resume","floor_cancel"]
var content: HospitalContent
var space: HospitalSpace
var environment: HospitalEnvironment
var _worked: Dictionary = {}

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry

func ensure(world: WorldState) -> void:
	if not world.facts.floors.has("completed_top_floor"):
		world.facts.floors.completed_top_floor = {}
	for plot: Array in world.facts.floors.overrides["1"].plots:
		var key: String = HospitalSpace.plot_key(plot)
		if not world.facts.floors.completed_top_floor.has(key):
			world.facts.floors.completed_top_floor[key] = 1
	if not world.facts.floors.has("orders"):
		world.facts.floors.orders = {}

func preview(world: WorldState, draft: Dictionary) -> Dictionary:
	var floor_id: int = int(draft.get("floor_id",0))
	var plot: Array = draft.get("plot",[])
	if floor_id<2 or not BuildGeometry.point(plot) or not plot in world.facts.floors.overrides["1"].plots:
		return BuildGeometry.failure("请先取得对应1F地块，并选择合法上层模块")
	var key: String = HospitalSpace.plot_key(plot)
	var top: int = int(world.facts.floors.get("completed_top_floor",{}).get(key,1))
	if floor_id!=top+1:
		return BuildGeometry.failure("只能购买该地块实完高度的下一层")
	for order: Dictionary in world.facts.floors.get("orders",{}).values():
		if order.floor_id==floor_id and order.plot==plot and not terminal(order):
			return {"ok":false,"reason":"该模块已有未完工单，请定位原进度","order_id":order.id}
	var source: String = str(draft.get("source","lift"))
	if source=="lift":
		var connection: Dictionary = world.facts.connectors.get(str(draft.get("connection_id","")),{})
		if connection.is_empty() or content.definition("vertical_connectors",connection.definition_id).kind!="lift" or [int(connection.cell[0])/32,int(connection.cell[1])/32]!=plot:
			return BuildGeometry.failure("请选择主锚点位于该地块的真实电梯")
	elif source!="same_floor" or HospitalSpace.floor_plots(world,floor_id).is_empty():
		return BuildGeometry.failure("本层尚无实完模块，请先沿实际电梯购买")
	if not below_room(world,floor_id,plot):
		return BuildGeometry.failure("下层尚无建筑：需要实际完工房间的内格")
	var crew: Dictionary = _crew(world,floor_id,plot)
	if world.facts.mode!="creative" and not crew.ok:
		return crew
	var pricing: Dictionary = content.balance.floors.section_pricing
	var price: int = mini(int(pricing.max_material_cost),int(pricing.base_material_cost)+(floor_id-int(pricing.first_upper_floor))*int(pricing.material_increment_per_floor))
	var seconds: int = mini(int(pricing.max_work_seconds),int(pricing.base_work_seconds)+(floor_id-int(pricing.first_upper_floor))*int(pricing.work_increment_per_floor))
	if world.facts.mode=="creative":
		price = 0
	if HospitalLedger.balance(world)<price:
		return BuildGeometry.failure("资金不足，未建立模块工单")
	return {"ok":true,"reason":"","floor_id":floor_id,"plot":plot.duplicate(),"price":price,"total_milli":seconds*1000,"world_revision":world.revision,"crew":crew}

func execute(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	ensure(world)
	if kind!="floor_purchase":
		var order: Dictionary = world.facts.floors.orders.get(str(payload.get("order_id","")),{})
		if order.is_empty() or terminal(order):
			return _result(world,false,"工单已结束或不存在")
		if kind=="floor_cancel":
			var refund: int = int(order.paid_cost)*int(order.remaining_milli)/int(order.total_milli)
			var posted: CommandResult = HospitalLedger.post(world,LedgerEntry.new(order.id,"floor_refund",refund))
			if not posted.accepted: return posted
			_release(world,order)
			order.phase = "cancelled"
			order.refund = refund
		else:
			order.paused = kind=="floor_pause"
			if order.paused: _release(world,order)
		return _result(world,true,"",[order.id])
	var quote: Dictionary = preview(world,payload)
	if not quote.ok: return _result(world,false,quote.reason)
	if payload.has("quote") and payload.quote!={"price":quote.price,"total_milli":quote.total_milli,"floor_id":quote.floor_id,"plot":quote.plot}:
		return _result(world,false,"原模块或价款已变化，请刷新原草案")
	var id: String = "floor_%08d" % (int(world.facts.entity_next)+1)
	var paid: CommandResult = HospitalLedger.post(world,LedgerEntry.new(id,"floor_purchase",-int(quote.price)))
	if not paid.accepted: return paid
	world.new_id("floor")
	var order: Dictionary = {"id":id,"floor_id":quote.floor_id,"plot":quote.plot,"paid_cost":quote.price,"total_milli":quote.total_milli,"remaining_milli":quote.total_milli,"phase":"queued","paused":false,"worker_id":"","work_cell":[],"tool_id":"","tool_collected":false,"contributions":{},"reason":"等待装修工","created_tick":world.sim_tick}
	world.facts.floors.orders[id] = order
	if world.facts.mode=="creative":
		_complete(world,order)
	return _result(world,true,"",[id])

func below_room(world: WorldState, floor_id: int, plot: Array) -> bool:
	for room: Dictionary in world.facts.rooms.values():
		if int(room.floor_id)!=floor_id-1: continue
		for cell: Array in BuildGeometry.cells(room):
			if int(cell[0])/32==int(plot[0]) and int(cell[1])/32==int(plot[1]): return true
	return false

func _crew(world: WorldState, floor_id: int, plot: Array) -> Dictionary:
	var busy: Dictionary = {}
	for id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[id]
		if staff.role!=content.balance.floors.construction_role: continue
		var point: Array = _work_point(world,id,floor_id-1,plot,[])
		if point.is_empty(): continue
		for tool_id: String in world.ids("facilities"):
			var tool: Dictionary = world.facts.facilities[tool_id]
			if tool.definition_id!=content.balance.floors.construction_tool_id or tool.failed or HospitalRemodel.blocked(world,tool_id): continue
			if not space.route(world,id,int(tool.floor_id),tool.operator_cells[0],[],{},true).ok: continue
			var candidate: Dictionary = {"ok":true,"worker_id":id,"work_cell":point,"tool_id":tool_id}
			if environment._worker_ready(world,id): return candidate
			busy = candidate
	return busy if not busy.is_empty() else BuildGeometry.failure("需要合格可达装修工和正常可达SE02工具台")

func _work_point(world: WorldState, worker_id: String, floor_id: int, plot: Array, previous: Array) -> Array:
	var actor: Dictionary = world.facts.actors[worker_id]
	if not previous.is_empty() and environment._allowed_region(world.facts.staff[worker_id],floor_id,previous) and space.static_reason(world,actor,floor_id,Vector2i(int(previous[0]),int(previous[1]))).is_empty() and space.route(world,worker_id,floor_id,previous,[],{},true).ok:
		return previous
	for y: int in range(int(plot[1])*32,(int(plot[1])+1)*32):
		for x: int in range(int(plot[0])*32,(int(plot[0])+1)*32):
			if not environment._allowed_region(world.facts.staff[worker_id],floor_id,[x,y]): continue
			if space.route(world,worker_id,floor_id,[x,y],[],{},true).ok: return [x,y]
	return []

func dispatch(world: WorldState) -> void:
	_worked.clear()
	for id: String in world.facts.floors.orders:
		var order: Dictionary = world.facts.floors.orders[id]
		if terminal(order): continue
		if order.paused or not below_room(world,int(order.floor_id),order.plot):
			_release(world,order)
			order.reason = "已主动暂停" if order.paused else "下层尚无建筑"
			continue
		if not str(order.worker_id).is_empty() and not environment._worker_ready(world,order.worker_id,order.id): _release(world,order)
		if str(order.worker_id).is_empty():
			var crew: Dictionary = _crew(world,int(order.floor_id),order.plot)
			if not crew.ok or not environment._worker_ready(world,str(crew.get("worker_id",""))):
				order.reason = "等待装修工、正常工具或合法工作点"
				continue
			order.worker_id = crew.worker_id
			order.work_cell = crew.work_cell
			order.tool_id = crew.tool_id
			order.tool_collected = false
			world.facts.staff[order.worker_id].active_job_id = order.id
			order.rate_milli = environment._work_amount(world,order.worker_id,"floor_module")
		var worker_id: String = order.worker_id
		order.work_cell = _work_point(world,worker_id,int(order.floor_id)-1,order.plot,order.work_cell)
		var tool: Dictionary = world.facts.facilities.get(order.tool_id,{})
		if tool.is_empty() or tool.failed or HospitalRemodel.blocked(world,order.tool_id):
			for tool_id: String in world.ids("facilities"):
				var alternative: Dictionary = world.facts.facilities[tool_id]
				if alternative.definition_id==content.balance.floors.construction_tool_id and not alternative.failed and not HospitalRemodel.blocked(world,tool_id) and space.route(world,worker_id,int(alternative.floor_id),alternative.operator_cells[0],[],{},true).ok:
					tool = alternative
					order.tool_id = tool_id
					order.tool_collected = false
					break
		if order.work_cell.is_empty() or tool.is_empty() or tool.failed or HospitalRemodel.blocked(world,order.tool_id):
			order.phase = "queued"
			order.reason = "等待工具或合法工作点"
			continue
		var target: Array = order.work_cell if order.tool_collected else tool.operator_cells[0]
		var target_floor: int = int(order.floor_id)-1 if order.tool_collected else int(tool.floor_id)
		if space.at(world,worker_id,target_floor,target) and not world.facts.moves.has(worker_id):
			if not order.tool_collected:
				order.tool_collected = true
			else:
				order.phase = "working"
				order.reason = ""
		else:
			order.phase = "travelling"
			order.reason = space.request_move(world,worker_id,target_floor,target)

func advance(world: WorldState) -> void:
	for order: Dictionary in world.facts.floors.orders.values():
		if order.phase!="working" or order.paused: continue
		var worker_id: String = order.worker_id
		if not environment._worker_ready(world,worker_id,order.id) or not below_room(world,int(order.floor_id),order.plot) or not world.facts.facilities.has(order.tool_id) or world.facts.facilities[order.tool_id].failed or not space.at(world,worker_id,int(order.floor_id)-1,order.work_cell): continue
		var amount: int = mini(int(order.remaining_milli),int(order.rate_milli))
		order.remaining_milli -= amount
		order.contributions[worker_id] = int(order.contributions.get(worker_id,0))+amount
		_worked[worker_id] = true
		if int(order.remaining_milli)==0: _complete(world,order)

func _complete(world: WorldState, order: Dictionary) -> void:
	world.facts.floors.completed_top_floor[HospitalSpace.plot_key(order.plot)] = int(order.floor_id)
	world.invalidate_geometry()
	order.remaining_milli = 0
	order.phase = "completed"
	order.completed_tick = world.sim_tick
	_release(world,order)
	if not order.contributions.is_empty(): environment._receipt(world,"floor_module_completed",order.id,order.contributions,int(order.total_milli))

func _release(world: WorldState, order: Dictionary) -> void:
	var worker_id: String = str(order.worker_id)
	if world.facts.staff.has(worker_id) and world.facts.staff[worker_id].get("active_job_id","")==order.id:
		world.facts.staff[worker_id].active_job_id = ""
	order.worker_id = ""
	if not terminal(order): order.phase = "queued"

func worked_staff() -> Dictionary:
	return _worked.duplicate()

static func terminal(order: Dictionary) -> bool:
	return order.phase in ["completed","cancelled"]

func validate(world: WorldState) -> String:
	var tops: Variant = world.facts.floors.get("completed_top_floor",{})
	var orders: Variant = world.facts.floors.get("orders",{})
	if not tops is Dictionary or not orders is Dictionary: return "楼板高度或施工单集合无效"
	for key: Variant in tops:
		if not key is String or not WorldState._natural(tops[key]) or int(tops[key])<1: return "实完高度无效"
		var owned: bool = false
		for plot: Array in world.facts.floors.overrides["1"].plots:
			if HospitalSpace.plot_key(plot)==key: owned = true
		if not owned: return "未购地块不能拥有上层结构"
	var targets: Dictionary = {}
	for id: Variant in orders:
		var order: Variant = orders[id]
		if not order is Dictionary or order.get("id")!=id or not BuildGeometry.point(order.get("plot")) or not WorldState._natural(order.get("floor_id")) or int(order.floor_id)<2 or not order.get("phase") in ["queued","travelling","working","completed","cancelled"] or not order.get("paused") is bool or not order.get("worker_id") is String or not order.get("work_cell") is Array or not order.get("contributions") is Dictionary: return "模块工单身份或状态无效"
		if not WorldState._natural(order.get("total_milli")) or int(order.total_milli)<=0 or not WorldState._natural(order.get("remaining_milli")) or int(order.remaining_milli)>int(order.total_milli) or not WorldState._natural(order.get("paid_cost")): return "模块冻结工时或付款无效"
		var key: String = HospitalSpace.plot_key(order.plot)
		if not tops.has(key): return "模块引用未购地块"
		var purchase: Dictionary = world.facts.ledger.entries.get(str(id)+":floor_purchase",{})
		if int(purchase.get("amount",1))!=-int(order.paid_cost): return "模块冻结付款与原账目不符"
		if order.phase=="completed" and (int(order.remaining_milli)!=0 or int(tops[key])<int(order.floor_id)): return "模块完成与真实高度不符"
		if not order.work_cell.is_empty() and (not BuildGeometry.point(order.work_cell) or int(order.work_cell[0])/32!=int(order.plot[0]) or int(order.work_cell[1])/32!=int(order.plot[1])): return "模块工作点不在正下层同地块"
		if not terminal(order):
			var target: String = key+":"+str(order.floor_id)
			if targets.has(target) or int(order.floor_id)!=int(tops[key])+1: return "模块重复购买或跳层"
			targets[target] = true
		if not str(order.worker_id).is_empty() and not world.facts.staff.has(order.worker_id): return "模块当前工人不存在"
	return ""

func _result(world: WorldState, accepted: bool, reason: String, ids: Array = []) -> CommandResult:
	return CommandResult.new(accepted,"applied" if accepted else "floor_blocked",reason,ids,world.revision)
