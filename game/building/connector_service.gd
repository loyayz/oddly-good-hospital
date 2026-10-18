class_name HospitalConnectors
extends RefCounted

const KINDS: Array[String] = ["connector_build","connector_extend","connector_remove"]
var content: HospitalContent
var space: HospitalSpace

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry

func ensure(_world: WorldState) -> void:
	pass

func preview(world: WorldState, kind: String, payload: Dictionary) -> Dictionary:
	var candidate: WorldState = WorldState.new(world.freeze())
	var price: int = 0
	var refund: int = 0
	var id: String = str(payload.get("connection_id",""))
	if kind=="connector_build":
		var definition: Dictionary = content.definition("vertical_connectors",str(payload.get("definition_id","")))
		if definition.is_empty() or not BuildGeometry.point(payload.get("cell")):
			return BuildGeometry.failure("请选择连接设施和有效格坐标")
		var first: int = int(payload.get("floor_id",1))
		if first<1 or definition.kind=="lift" and first!=1:
			return BuildGeometry.failure("电梯主设备必须初装于1F")
		var rotation: int = posmod(int(payload.get("rotation",0)),4)
		var size: Array = definition.footprint.duplicate()
		var front: Vector2i = BuildService._rotate_offset(Vector2i(int(definition.front_operation_anchor[0]),int(definition.front_operation_anchor[1])),size,rotation)
		var repair: Vector2i = Vector2i.ZERO
		if definition.kind=="lift": repair = BuildService._rotate_offset(Vector2i(int(definition.repair_anchor[0]),int(definition.repair_anchor[1])),size,rotation)
		if rotation%2==1: size.reverse()
		id = candidate.new_id("connector")
		var cell: Array = payload.cell.duplicate()
		var record: Dictionary = {"id":id,"definition_id":definition.id,"first_floor":first,"last_floor":first+1 if definition.kind=="stairs" else first,"cell":cell,"footprint":size,"rotation":rotation,"anchor":[int(cell[0])+front.x,int(cell[1])+front.y],"repair_cell":[int(cell[0])+repair.x,int(cell[1])+repair.y],"floor_id":first,"phase":"idle","riders":[],"remaining_ticks":0,"ticket_next":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},"paid_cost":int(definition.base_price),"used":false}
		var geometry: String = _geometry(candidate,record,int(record.first_floor),int(record.last_floor))
		if not geometry.is_empty(): return BuildGeometry.failure(geometry)
		candidate.facts.connectors[id] = record
		price = int(definition.base_price)
	elif not candidate.facts.connectors.has(id):
		return BuildGeometry.failure("原竖向连接已不存在")
	elif kind=="connector_extend":
		var record: Dictionary = candidate.facts.connectors[id]
		var definition: Dictionary = content.definition("vertical_connectors",record.definition_id)
		if definition.kind!="lift": return BuildGeometry.failure("楼梯只能连接原相邻两层")
		var floor_id: int = int(payload.get("floor_id",0))
		if floor_id!=int(record.last_floor)+1: return BuildGeometry.failure("只可明确安装下一连续站点")
		var geometry: String = _geometry(candidate,record,floor_id,floor_id)
		if not geometry.is_empty(): return BuildGeometry.failure(geometry)
		price = int(definition.extra_stop_price) if floor_id-int(record.first_floor)>=int(definition.base_stops) else 0
		if world.facts.mode=="creative": price = 0
		record.last_floor = floor_id
		record.paid_cost = int(record.paid_cost)+price
	elif kind=="connector_remove":
		var record: Dictionary = candidate.facts.connectors[id]
		if record.phase!="idle" or not HospitalTransit._waiting(candidate,id).is_empty(): return BuildGeometry.failure("等待原乘员和叫梯票安全完成")
		for collection: String in ["jobs","upgrades"]:
			for job: Dictionary in world.facts.get("maintenance",{}).get(collection,{}).values():
				if job.facility_id==id and not job.phase in ["completed","cancelled","abandoned"]: return BuildGeometry.failure("请先安全结束该设备维护工单")
		refund = floori(float(record.paid_cost)*(0.8 if record.used else 1.0))
		candidate.facts.connectors.erase(id)
	else:
		return BuildGeometry.failure("未知竖向设施操作")
	if world.facts.mode=="creative":
		price = 0
		refund = 0
		if kind=="connector_build": candidate.facts.connectors[id].paid_cost = 0
	if HospitalLedger.balance(world)<price: return BuildGeometry.failure("资金不足，原连接保持")
	var builder: BuildService = BuildService.new(content,space)
	var checker: HospitalSpace = HospitalSpace.new(content)
	var previous_checker: HospitalSpace = HospitalSpace.new(content)
	for actor: Dictionary in candidate.facts.actors.values():
		if actor.location.kind!="floor": continue
		var safety: Dictionary = builder.actor_safety(world,candidate,actor,checker,previous_checker)
		if not safety.ok: return safety
	return {"ok":true,"reason":"","price":price,"refund":refund,"connection_id":id,"world_revision":world.revision,"candidate":candidate}

func _geometry(world: WorldState, connection: Dictionary, first: int, last: int) -> String:
	var rect: Rect2 = Rect2(float(connection.cell[0]),float(connection.cell[1]),float(connection.footprint[0]),float(connection.footprint[1]))
	for y: int in range(int(rect.position.y),int(rect.end.y)):
		for x: int in range(int(rect.position.x),int(rect.end.x)):
			if not space.owned(world,first,Vector2i(x,y)) or not space.owned(world,last,Vector2i(x,y)): return "完整井道尚未取得实完楼板"
	for room: Dictionary in world.facts.rooms.values():
		if int(room.floor_id)<first or int(room.floor_id)>last: continue
		for cell: Array in BuildGeometry.cells(room):
			if rect.has_point(Vector2(float(cell[0]),float(cell[1]))): return "井道与真实房间冲突"
	for facility: Dictionary in world.facts.facilities.values():
		if int(facility.floor_id)>=first and int(facility.floor_id)<=last and rect.intersects(Rect2(float(facility.cell[0]),float(facility.cell[1]),float(facility.footprint[0]),float(facility.footprint[1])),false): return "井道与实际物件冲突"
	for other: Dictionary in world.facts.connectors.values():
		if other.id==connection.id: continue
		var ends: Array = HospitalTransit.endpoints(other)
		if int(ends.min())<=last and int(ends.max())>=first and rect.intersects(Rect2(float(other.cell[0]),float(other.cell[1]),float(other.footprint[0]),float(other.footprint[1])),false): return "竖向通道重叠"
	for actor: Dictionary in world.facts.actors.values():
		if actor.location.kind=="floor" and int(actor.location.floor_id)>=first and int(actor.location.floor_id)<=last and rect.intersects(space.body_rectangle(actor),false): return "等待真实人员离开井道范围"
	if first<=1 and Rect2(float(world.facts.entry.cell[0]),float(world.facts.entry.cell[1]),3,3).intersects(rect,false): return "竖向设施不能占用院门缓冲区"
	var definition: Dictionary = content.definition("vertical_connectors",connection.definition_id)
	var extent: int = int(definition.max_clearance_cells)
	for floor_id: int in [first,last]:
		for point: Array in [connection.anchor,connection.repair_cell] if definition.kind=="lift" and floor_id==1 else [connection.anchor]:
			var occupied: Dictionary = BuildGeometry.occupied_error(world,space,floor_id,[Rect2(float(point[0]),float(point[1]),extent,extent)])
			if not occupied.ok: return "端口操作区需要畅通空间："+occupied.reason
			for dy: int in extent:
				for dx: int in extent:
					var cell: Vector2i = Vector2i(int(point[0])+dx,int(point[1])+dy)
					if not space.owned(world,floor_id,cell) or rect.has_point(Vector2(cell)): return "端口、候位或维修位缺少实完空间"
					for room: Dictionary in world.facts.rooms.values():
						if int(room.floor_id)==floor_id and BuildGeometry.contains(room,[cell.x,cell.y]): return "端口需要合法公共候位空间"
	return ""

func execute(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	var plan: Dictionary = preview(world,kind,payload)
	if not plan.ok: return CommandResult.new(false,"connector_blocked",plan.reason,[],world.revision)
	if payload.has("quote") and payload.quote!={"price":plan.price,"refund":plan.refund}: return CommandResult.new(false,"material_change","价款已变化，请刷新原连接草案",[],world.revision)
	var candidate: WorldState = plan.candidate
	var receipt: String = candidate.new_id("vertical_build")
	if not candidate.facts.has("vertical_transactions"): candidate.facts.vertical_transactions = {}
	candidate.facts.vertical_transactions[receipt] = {"id":receipt,"connection_id":plan.connection_id,"kind":kind,"tick":world.sim_tick,"amount":int(plan.refund)-int(plan.price)}
	var paid: CommandResult = HospitalLedger.post(candidate,LedgerEntry.new(receipt,"construction",int(plan.refund)-int(plan.price)))
	if not paid.accepted: return paid
	world.facts = candidate.facts
	return CommandResult.new(true,"applied","",[plan.connection_id,receipt],world.revision)
