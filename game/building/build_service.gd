class_name BuildService
extends RefCounted

const HISTORY_LIMIT: int = 20
const KINDS: Array[String] = ["build_room","build_facility","build_store","build_door","build_move","build_rotate","build_demolish","build_undo","build_land"]
var content: HospitalContent
var space: HospitalSpace
var _deferred_checks: bool = false
var _prepared_shape: Dictionary = {}

func _init(database: HospitalContent, geometry: HospitalSpace = null) -> void:
	content = database
	space = geometry if geometry!=null else HospitalSpace.new(database)

func ensure(world: WorldState) -> void:
	if not world.facts.has("build_transactions"):
		world.facts.build_transactions = {}
	if not world.facts.has("build_history"):
		world.facts.build_history = []
	if not world.facts.inventory.has("build_items"):
		world.facts.inventory.build_items = {}

func preview(world: WorldState, draft: Dictionary) -> Dictionary:
	var kind: String = str(draft.get("kind","build_room"))
	var planned: Dictionary = _plan(world,kind,draft)
	planned.erase("candidate")
	if planned.ok:
		planned.world_revision = world.revision
		planned.balance_after = HospitalLedger.balance(world)-int(planned.price)+int(planned.refund)
		planned.ready = true
		planned.quote = {"kind":kind,"price":planned.price,"refund":planned.refund,"targets":_target_basis(world,kind,draft)}
		planned.draft = draft.duplicate(true)
	else:
		planned.ready = false
	return planned

func execute(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	if not kind in KINDS:
		return CommandResult.new(false,"unsupported_command","未知建造操作",[],world.revision)
	var key: String = str(payload.get("record_key",payload.get("command_id","")))
	for receipt: Dictionary in world.facts.get("build_transactions",{}).values():
		if not key.is_empty() and receipt.record_key==key:
			if receipt.kind!=kind or receipt.get("payload",{})!=_intent(payload):
				return CommandResult.new(false,"command_id_conflict","同一建造凭据的操作内容发生变化",[],world.revision)
			return CommandResult.new(true,"duplicate","",receipt.changed_ids,world.revision)
	var planned: Dictionary = _plan(world,kind,payload)
	if not planned.ok:
		return CommandResult.new(false,"build_blocked",planned.reason,[],world.revision)
	if payload.has("quote"):
		var actual: Dictionary = {"kind":kind,"price":planned.price,"refund":planned.refund,"targets":_target_basis(world,kind,payload)}
		if not payload.quote is Dictionary or actual!=payload.quote:
			return CommandResult.new(false,"material_change","实际对象、价款或退款依据已改变，请刷新原草案",[],world.revision)
	var candidate: WorldState = planned.candidate
	ensure(candidate)
	var transaction_id: String = candidate.new_id("build")
	var amount: int = int(planned.refund)-int(planned.price)
	candidate.facts.build_transactions[transaction_id] = {"id":transaction_id,"kind":kind,"tick":world.sim_tick,"amount":amount,"changed_ids":planned.changed_ids.duplicate(),"undone":false,"record_key":key,"payload":_intent(payload)}
	if amount!=0:
		var payment: CommandResult = HospitalLedger.post(candidate,LedgerEntry.new(transaction_id,"construction" if amount<0 else "construction_refund",amount))
		if not payment.accepted:
			return CommandResult.new(false,payment.code,payment.reason,[],world.revision)
	if kind=="build_undo":
		var previous: Dictionary = candidate.facts.build_history.pop_back()
		candidate.facts.build_transactions[previous.transaction_id].undone = true
	elif kind!="build_land":
		candidate.facts.build_history.append(_history(world,candidate,transaction_id,planned.changed_ids,amount))
		while candidate.facts.build_history.size()>HISTORY_LIMIT:
			candidate.facts.build_history.pop_front()
	candidate.touch()
	world.facts = candidate.facts
	return CommandResult.new(true,"applied","",planned.changed_ids+[transaction_id],world.revision)

func _intent(payload: Dictionary) -> Dictionary:
	var result: Dictionary = payload.duplicate(true)
	for field: String in ["quote","expected_revision","record_key","command_id"]:
		result.erase(field)
	return result

func _scratch(world: WorldState) -> WorldState:
	# The preview shares read-only actors/clinical facts and copies only affected ownership.
	var data: Dictionary = world.facts.duplicate()
	for field: String in ["rooms","facilities","floors","ledger","inventory","build_transactions","build_history"]:
		if data.has(field):
			data[field] = data[field].duplicate(true)
	return WorldState.new(data)

func _plan(world: WorldState, kind: String, payload: Dictionary) -> Dictionary:
	if not kind in KINDS:
		return BuildGeometry.failure("未知建造操作")
	var payload_error: String = _payload_error(payload)
	if not payload_error.is_empty():
		return BuildGeometry.failure(payload_error)
	# Moving a working object into or out of inventory also changes its original
	# work orders and their exclusive worker routes. Keep that whole transaction
	# isolated until the final spatial and quoted-intent checks have succeeded.
	var inventory_transfer: bool = kind=="build_store" or kind=="build_facility" and not str(payload.get("inventory_id","")).is_empty()
	var candidate: WorldState = WorldState.new(world.freeze()) if inventory_transfer else _scratch(world)
	var result: Dictionary
	match kind:
		"build_room": result = _add_room(candidate,payload)
		"build_facility": result = _add_facility(candidate,payload)
		"build_store": result = _store_facility(candidate,payload)
		"build_door": result = _replace_door(candidate,payload)
		"build_move", "build_rotate": result = _move(candidate,kind,payload)
		"build_demolish": result = _demolish(candidate,payload)
		"build_undo": result = _undo(candidate)
		"build_land": result = _land(candidate,payload)
	if not result.ok:
		return result
	if HospitalLedger.balance(world)+int(result.refund)-int(result.price)<0:
		return BuildGeometry.failure("资金不足，草案和原布局保留")
	for floor_id: int in ([] if _deferred_checks else result.get("floors",[])):
		var safety: Dictionary = _safety(world,candidate,floor_id)
		if not safety.ok:
			return safety
	result.candidate = candidate
	return result

func prepare_preview(world: WorldState, kind: String, draft: Dictionary, prepared_shape: Dictionary = {}) -> Dictionary:
	var staging: BuildService = BuildService.new(content)
	staging._deferred_checks = true
	staging._prepared_shape = prepared_shape
	return staging._plan(world,kind,draft)

func _payload_error(payload: Dictionary) -> String:
	for field: String in ["floor_id","rotation","turns","offset"]:
		if payload.has(field) and (not (payload[field] is int or payload[field] is float) or not is_finite(float(payload[field])) or floorf(float(payload[field]))!=float(payload[field]) or absf(float(payload[field]))>1000000000):
			return "建造整数输入无效："+field
	for field: String in ["id","target_id","definition_id","room_id","room_type_id","room_type","type","inventory_id","edge","record_key","command_id"]:
		if payload.has(field) and not payload[field] is String:
			return "建造身份输入无效："+field
	if payload.has("floor_id") and int(payload.floor_id)<1:
		return "建造楼层无效"
	if payload.has("door") and not payload.door is Dictionary:
		return "房门草案结构无效"
	if payload.has("doors") and not payload.doors is Array:
		return "房门草案列表无效"
	return ""

func _room_type(id: String) -> Dictionary:
	return content.definition("build_room_types",id)

func _unlocked(world: WorldState, definition: Dictionary) -> String:
	for research: String in definition.get("requires_research",[]):
		if not research in world.facts.research:
			return "尚未完成研究："+research
	return ""

func _add_room(world: WorldState, payload: Dictionary) -> Dictionary:
	var type_id: String = str(payload.get("room_type_id",payload.get("room_type",payload.get("type","gp"))))
	var definition: Dictionary = _room_type(type_id)
	if definition.is_empty():
		return BuildGeometry.failure("未知房型："+type_id)
	var locked: String = _unlocked(world,definition)
	if not locked.is_empty():
		return BuildGeometry.failure(locked)
	var shape: Dictionary = _prepared_shape if not _prepared_shape.is_empty() else BuildGeometry.shape(payload,definition.min_inner_size)
	if not shape.ok:
		return shape
	var floor_id: int = int(payload.get("floor_id",1))
	var id: String = str(payload.get("id",""))
	if id.is_empty():
		id = world.new_id("room")
	if _exists(world,id):
		return BuildGeometry.failure("对象身份已存在："+id)
	var rects: Array = []
	for cell: Array in shape.cells:
		rects.append(Rect2(float(cell[0]),float(cell[1]),1,1))
	var collision: Dictionary = {"ok":true} if _deferred_checks else BuildGeometry.occupied_error(world,space,floor_id,rects)
	if not collision.ok:
		return collision
	for other: Dictionary in ([] if _deferred_checks else world.facts.rooms.values()):
		if int(other.floor_id)==floor_id:
			for cell: Array in shape.cells:
				if BuildGeometry.contains(other,cell):
					return BuildGeometry.failure("房间内格与实际房间重叠："+str(other.id),[cell])
	var room: Dictionary = {"id":id,"kind":type_id,"floor_id":floor_id,"origin":shape.origin,"size":shape.size,"cells":shape.cells,"wall_edges":shape.wall_edges,
		"open_intent":bool(payload.get("open_intent",true)),"paid_cost":shape.cells.size()*(int(content.balance.floor_cost_cell)+int(content.balance.room_fitout_cost_cell)),"used":false,"ownership":"purchased"}
	world.facts.rooms[id] = room
	var door_drafts: Array = payload.get("doors",[payload.get("door",{"definition_id":"DR01","edge":"south","offset":1})])
	if door_drafts.is_empty():
		return BuildGeometry.failure("房间至少需要一扇通向公共区域的门")
	var price: int = int(room.paid_cost)
	var changed: Array = [id]
	for door_draft: Variant in door_drafts:
		if not door_draft is Dictionary:
			return BuildGeometry.failure("房门草案结构无效")
		var request: Dictionary = door_draft.duplicate(true)
		request.room_id = id
		var placed: Dictionary = _add_door(world,request)
		if not placed.ok:
			return placed
		price += int(placed.price)
		changed.append_array(placed.changed_ids)
	var public: String = "" if _deferred_checks else _public_door(world,room)
	if not public.is_empty():
		return BuildGeometry.failure(public)
	return _success(price,0,changed,[floor_id])

func _add_door(world: WorldState, payload: Dictionary) -> Dictionary:
	var room_id: String = str(payload.get("room_id",""))
	if not world.facts.rooms.has(room_id):
		return BuildGeometry.failure("房门缺少实际房间")
	var room: Dictionary = world.facts.rooms[room_id]
	var definition: Dictionary = content.definition("doors",str(payload.get("definition_id","DR01")))
	if definition.is_empty():
		return BuildGeometry.failure("未知房门定义")
	var edge: String = str(payload.get("edge","south"))
	var offset: int = int(payload.get("offset",1))
	if not edge in ["north","south","west","east"] or offset<0:
		return BuildGeometry.failure("门墙边或偏移无效")
	var axis: String = "x" if edge in ["north","south"] else "y"
	var cell: Array = payload.get("cell",[int(room.origin[0])+(offset if axis=="x" else int(room.size[0]) if edge=="east" else 0),int(room.origin[1])+(offset if axis=="y" else int(room.size[1]) if edge=="south" else 0)])
	if not BuildGeometry.point(cell):
		return BuildGeometry.failure("房门墙边坐标无效")
	var span: int = int(definition.span_cells)
	var low: int = int(cell[0] if axis=="x" else cell[1])
	var line: int = int(cell[1] if axis=="x" else cell[0])
	var on_wall: bool = false
	for wall: Dictionary in _walls(room):
		if wall.axis==axis and int(wall.line)==line and low>=int(wall.low) and low+span<=int(wall.high):
			on_wall = true
	if not on_wall:
		return BuildGeometry.failure("门须落在同一段真实连续墙边，不能越墙角",[cell])
	var id: String = str(payload.get("id",""))
	if id.is_empty():
		id = world.new_id("door")
	if _exists(world,id):
		return BuildGeometry.failure("对象身份已存在："+id)
	var door: Dictionary = {"id":id,"definition_id":definition.id,"cell":cell.duplicate(),"span":span,"axis":axis,"room_id":room_id,"active_actor_id":"","clear_height_m":float(definition.clear_height_m),"paid_cost":int(definition.price),"used":false,"ownership":"purchased"}
	var rect: Rect2 = space._door_rect(door,span)
	for other: Dictionary in world.facts.floors.overrides[str(int(room.floor_id))].doors:
		if other.axis==axis and rect.intersects(space._door_rect(other,int(other.span)),false):
			return BuildGeometry.failure("门与已有房门相交",[cell])
	for facility: Dictionary in world.facts.facilities.values():
		if int(facility.floor_id)==int(room.floor_id) and rect.intersects(BuildGeometry.rectangle(facility),false):
			return BuildGeometry.failure("门口有实际设施："+str(facility.id),[cell])
	for reservation: Dictionary in world.facts.adaptations.values():
		if int(reservation.floor_id)==int(room.floor_id):
			for region: Array in reservation.regions:
				if rect.intersects(Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3])),false):
					return BuildGeometry.failure("门口有尚未释放的真实预约",[cell])
	world.facts.floors.overrides[str(int(room.floor_id))].doors.append(door)
	return _success(int(definition.price),0,[id],[int(room.floor_id)])

func _replace_door(world: WorldState, payload: Dictionary) -> Dictionary:
	var id: String = str(payload.get("target_id",""))
	if id.is_empty():
		return _add_door(world,payload)
	var found: Dictionary = _door(world,id)
	if found.is_empty():
		return BuildGeometry.failure("原房门已不存在")
	var busy: String = _busy(world,id)
	if not busy.is_empty():
		return BuildGeometry.failure(busy)
	var request: Dictionary = payload.duplicate(true)
	request.id = id
	request.room_id = found.door.room_id
	world.facts.floors.overrides[str(found.floor_id)].doors.erase(found.door)
	var placed: Dictionary = _add_door(world,request)
	if placed.ok:
		placed.refund = _refund(found.door)
	return placed

func _add_facility(world: WorldState, payload: Dictionary) -> Dictionary:
	var definition: Dictionary = content.facility_definition(str(payload.get("definition_id","")))
	if definition.is_empty() or not definition.has("price") or not BuildGeometry.point(definition.get("footprint"),true):
		return BuildGeometry.failure("设施缺少完整购买定义")
	var locked: String = _unlocked(world,definition)
	if not locked.is_empty():
		return BuildGeometry.failure(locked)
	if not BuildGeometry.point(payload.get("cell",payload.get("anchor"))):
		return BuildGeometry.failure("设施格坐标无效")
	var floor_id: int = int(payload.get("floor_id",1))
	var rotation: int = posmod(int(payload.get("rotation",0)),4)
	var footprint: Array = definition.footprint.duplicate()
	if rotation%2==1:
		footprint.reverse()
	var id: String = str(payload.get("id",""))
	var inventory_id: String = str(payload.get("inventory_id",""))
	var inventory: Dictionary = world.facts.inventory.get("build_items",{})
	var owned_item: Dictionary = {}
	if not inventory_id.is_empty():
		if not inventory.has(inventory_id) or inventory[inventory_id].get("definition_id","")!=str(payload.definition_id):
			return BuildGeometry.failure("选中的真实库存已不存在或品项已改变")
		owned_item = inventory[inventory_id]
		id = inventory_id
	if id.is_empty():
		id = world.new_id("facility")
	if _exists(world,id):
		return BuildGeometry.failure("对象身份已存在："+id)
	var facility: Dictionary = {"id":id,"definition_id":str(payload.definition_id),"floor_id":floor_id,"cell":payload.get("cell",payload.get("anchor")).duplicate(),"footprint":footprint,"rotation":rotation,
		"grade":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},"paid_cost":int(definition.price),"used":false,"ownership":"purchased"}
	if not owned_item.is_empty():
		# The inventory owns this same physical object. Preserve every business
		# fact, including future content fields, and replace only its placement.
		for field: String in owned_item:
			var value: Variant = owned_item[field]
			facility[field] = value.duplicate(true) if value is Dictionary or value is Array else value
		facility.id = id
		facility.definition_id = str(payload.definition_id)
		facility.floor_id = floor_id
		facility.cell = payload.get("cell",payload.get("anchor")).duplicate()
		facility.footprint = footprint
		facility.rotation = rotation
		facility.location = "floor"
		facility.erase("room_id")
		facility.last_wear_day = world.sim_tick/WorldState.TICKS_PER_DAY
	var room_id: String = str(payload.get("room_id",""))
	if not room_id.is_empty():
		facility.room_id = room_id
	_set_anchors(facility,definition)
	var reason: Dictionary = {"ok":true} if _deferred_checks else _facility_position(world,facility)
	if not reason.ok:
		return reason
	world.facts.facilities[id] = facility
	if not inventory_id.is_empty():
		inventory.erase(inventory_id)
		for collection: String in ["jobs","upgrades"]:
			for order: Dictionary in world.facts.get("maintenance",{}).get(collection,{}).values():
				if order.get("facility_id","")==id and order.get("phase","")=="inventory":
					order.phase = "queued"
					order.reason = "设备已重新放置，等待原工单实际接续"
	return _success(int(definition.price) if inventory_id.is_empty() else 0,0,[id],[floor_id])

func _store_facility(world: WorldState, payload: Dictionary) -> Dictionary:
	var id: String = str(payload.get("target_id",""))
	if not world.facts.facilities.has(id):
		return BuildGeometry.failure("待入库的实际设施不存在")
	var busy: String = _busy(world,id,true)
	if not busy.is_empty():
		return BuildGeometry.failure(busy)
	for collection: String in ["needs","sessions"]:
		for reservation: Dictionary in world.facts.get("waiting_life",{}).get(collection,{}).values():
			if _references(reservation,id):
				return BuildGeometry.failure("等待生活服务使用者完成并释放实际设施预约")
	var facility: Dictionary = world.facts.facilities[id]
	var floor_id: int = int(facility.floor_id)
	var rectangle: Rect2 = BuildGeometry.rectangle(facility)
	for actor: Dictionary in world.facts.actors.values():
		if actor.location.kind=="floor" and int(actor.location.floor_id)==floor_id and space.body_rectangle(actor).intersects(rectangle,false):
			return BuildGeometry.failure("等待实际身体离开设备主体后再入库",[actor.location.cell])
	ensure(world)
	if world.facts.inventory.build_items.has(id):
		return BuildGeometry.failure("同一设施已经存在另一份库存记录")
	for collection: String in ["jobs","upgrades"]:
		for order: Dictionary in world.facts.get("maintenance",{}).get(collection,{}).values():
			if order.get("facility_id","")==id and order.get("phase","") not in ["completed","cancelled","abandoned"]:
				_suspend_inventory_work(world,order)
	facility.location = "inventory"
	world.facts.inventory.build_items[id] = facility
	world.facts.facilities.erase(id)
	return _success(0,0,[id],[floor_id])

func _suspend_inventory_work(world: WorldState, order: Dictionary) -> void:
	var worker_id: String = str(order.get("worker_id",""))
	if world.facts.staff.has(worker_id) and world.facts.staff[worker_id].get("active_job_id","")==order.id:
		var movement: Dictionary = world.facts.moves.get(worker_id,{})
		var matching_target: bool = not movement.is_empty() and movement.get("target_floor",-1)==order.get("work_floor",-2) and movement.get("target_cell",[])==order.get("work_cell",["no-work-position"])
		var owned_move: bool = movement.get("owner_job_id","")==order.id or matching_target and str(movement.get("owner_job_id","")).is_empty()
		var actor: Dictionary = world.facts.actors.get(worker_id,{})
		# An embarked ride is a separate safe movement commitment. Let it finish;
		# only an unembarked route owned by this work order can be withdrawn.
		if owned_move and not actor.is_empty() and actor.location.kind=="floor" and movement.get("members",[]).is_empty():
			HospitalTransit.cancel_waiting(world,movement)
			world.facts.moves.erase(worker_id)
		world.facts.staff[worker_id].active_job_id = ""
	order.worker_id = ""
	order.phase = "inventory"
	order.reason = "设备已入库，保留原工单、实付款和剩余工作"
	order.resume_not_before_tick = world.sim_tick+1

func _set_anchors(facility: Dictionary, definition: Dictionary) -> void:
	var w: int = int(facility.footprint[0])
	var h: int = int(facility.footprint[1])
	var patient: Vector2i = _rotate_offset(Vector2i(0,int(definition.footprint[1])),definition.footprint,int(facility.rotation))
	var operator: Vector2i = _rotate_offset(Vector2i(int(definition.footprint[0]),maxi(0,int(definition.footprint[1])-1)),definition.footprint,int(facility.rotation))
	var repair: Vector2i = _rotate_offset(Vector2i(maxi(0,int(definition.footprint[0])-1),-1),definition.footprint,int(facility.rotation))
	var origin: Vector2i = Vector2i(int(facility.cell[0]),int(facility.cell[1]))
	facility.patient_cell = [origin.x+patient.x,origin.y+patient.y]
	facility.operator_cells = [[origin.x+operator.x,origin.y+operator.y]]
	facility.repair_cell = [origin.x+repair.x,origin.y+repair.y]
	if facility.definition_id=="EQ01":
		facility.operator_cells = [[origin.x-1,origin.y+1],[origin.x+w,origin.y],[origin.x+w,origin.y+h-1]]

static func _rotate_offset(point: Vector2i, size: Array, turns: int) -> Vector2i:
	match posmod(turns,4):
		1: return Vector2i(int(size[1])-1-point.y,point.x)
		2: return Vector2i(int(size[0])-1-point.x,int(size[1])-1-point.y)
		3: return Vector2i(point.y,int(size[0])-1-point.x)
	return point

func _facility_position(world: WorldState, facility: Dictionary, ignore: Array = []) -> Dictionary:
	var collision: Dictionary = BuildGeometry.occupied_error(world,space,int(facility.floor_id),[BuildGeometry.rectangle(facility)],ignore)
	if not collision.ok:
		return collision
	var room_id: String = str(facility.get("room_id",""))
	for x: int in range(int(facility.cell[0]),int(facility.cell[0])+int(facility.footprint[0])):
		for y: int in range(int(facility.cell[1]),int(facility.cell[1])+int(facility.footprint[1])):
			if not room_id.is_empty() and (not world.facts.rooms.has(room_id) or int(world.facts.rooms[room_id].floor_id)!=int(facility.floor_id) or not BuildGeometry.contains(world.facts.rooms[room_id],[x,y])):
				return BuildGeometry.failure("设备主体必须完整位于所属房间的实际内格",[[x,y]])
			for room: Dictionary in world.facts.rooms.values():
				if int(room.floor_id)==int(facility.floor_id) and room.id!=room_id and BuildGeometry.contains(room,[x,y]):
					return BuildGeometry.failure("公共家具或其他房间设备不能侵入本房间",[[x,y]])
	for door: Dictionary in world.facts.floors.overrides[str(int(facility.floor_id))].get("doors",[]):
		if BuildGeometry.rectangle(facility).intersects(space._door_rect(door,int(door.span)),false):
			return BuildGeometry.failure("设施不能占据真实门口",[door.cell])
	return {"ok":true}

func _move(world: WorldState, kind: String, payload: Dictionary) -> Dictionary:
	var id: String = str(payload.get("target_id",""))
	var busy: String = _busy(world,id)
	if not busy.is_empty():
		return BuildGeometry.failure(busy)
	if world.facts.facilities.has(id):
		var facility: Dictionary = world.facts.facilities[id]
		var previous_floor: int = int(facility.floor_id)
		if kind=="build_move":
			if not BuildGeometry.point(payload.get("cell")):
				return BuildGeometry.failure("移动目标坐标无效")
			facility.cell = payload.cell.duplicate()
			facility.floor_id = int(payload.get("floor_id",facility.floor_id))
			if payload.has("room_id"):
				facility.erase("room_id")
				if not str(payload.room_id).is_empty():
					facility.room_id = str(payload.room_id)
		else:
			facility.rotation = posmod(int(payload.get("rotation",int(facility.get("rotation",0))+1)),4)
		var definition: Dictionary = content.facility_definition(facility.definition_id)
		facility.footprint = definition.footprint.duplicate()
		if int(facility.get("rotation",0))%2==1:
			facility.footprint.reverse()
		facility.rotation = int(facility.get("rotation",0))
		_set_anchors(facility,definition)
		var positioned: Dictionary = {"ok":true} if _deferred_checks else _facility_position(world,facility,[id])
		if not positioned.ok:
			return positioned
		return _success(0,0,[id],[previous_floor,int(facility.floor_id)])
	if world.facts.rooms.has(id):
		if kind=="build_rotate":
			return _rotate_room(world,payload)
		return _move_room(world,payload)
	var found: Dictionary = _door(world,id)
	if not found.is_empty():
		var before: Dictionary = found.door.duplicate(true)
		if payload.has("definition_id") and payload.definition_id!=before.definition_id:
			return BuildGeometry.failure("更换门外观须使用当前购买及原门退款报价")
		world.facts.floors.overrides[str(found.floor_id)].doors.erase(found.door)
		var request: Dictionary = payload.duplicate(true)
		request.id = id
		request.room_id = before.room_id
		request.definition_id = str(payload.get("definition_id",before.definition_id))
		var placed: Dictionary = _add_door(world,request)
		if placed.ok:
			var current: Dictionary = _door(world,id).door
			current.paid_cost = before.get("paid_cost",0)
			current.used = before.get("used",false)
			return _success(0,0,[id],[int(found.floor_id)])
		return placed
	return BuildGeometry.failure("移动对象不存在")

func _move_room(world: WorldState, payload: Dictionary) -> Dictionary:
	var room: Dictionary = world.facts.rooms[payload.target_id]
	if not BuildGeometry.point(payload.get("cell",payload.get("origin"))):
		return BuildGeometry.failure("房间移动目标无效")
	var origin: Array = payload.get("cell",payload.get("origin"))
	var delta: Vector2i = Vector2i(int(origin[0])-int(room.origin[0]),int(origin[1])-int(room.origin[1]))
	return _transform_room(world,room,delta,0,int(payload.get("floor_id",room.floor_id)))

func _rotate_room(world: WorldState, payload: Dictionary) -> Dictionary:
	var room: Dictionary = world.facts.rooms[payload.target_id]
	return _transform_room(world,room,Vector2i.ZERO,posmod(int(payload.get("turns",1)),4),int(room.floor_id))

func _transform_room(world: WorldState, room: Dictionary, delta: Vector2i, turns: int, target_floor: int) -> Dictionary:
	var previous_floor: int = int(room.floor_id)
	var old_origin: Vector2i = Vector2i(int(room.origin[0]),int(room.origin[1]))
	var old_size: Array = room.size.duplicate()
	var new_cells: Array = []
	for cell: Array in BuildGeometry.cells(room):
		var transformed: Vector2i = old_origin+delta+_rotate_offset(Vector2i(int(cell[0]),int(cell[1]))-old_origin,old_size,turns)
		new_cells.append([transformed.x,transformed.y])
	var shape: Dictionary = BuildGeometry.shape({"cells":new_cells},_room_type(room.kind).get("min_inner_size",[1,1]))
	if not shape.ok:
		return shape
	var ignored: Array = []
	for facility: Dictionary in world.facts.facilities.values():
		if facility.get("room_id","")==room.id:
			var busy: String = _busy(world,facility.id)
			if not busy.is_empty():
				return BuildGeometry.failure(busy)
			ignored.append(facility.id)
	var rects: Array = []
	for cell: Array in shape.cells:
		rects.append(Rect2(float(cell[0]),float(cell[1]),1,1))
	var collision: Dictionary = {"ok":true} if _deferred_checks else BuildGeometry.occupied_error(world,space,target_floor,rects,ignored)
	if not collision.ok:
		return collision
	for other: Dictionary in ([] if _deferred_checks else world.facts.rooms.values()):
		if other.id!=room.id and int(other.floor_id)==target_floor:
			for cell: Array in shape.cells:
				if BuildGeometry.contains(other,cell):
					return BuildGeometry.failure("移动房间与已有房间内格重叠",[cell])
	room.origin = shape.origin
	room.size = shape.size
	room.cells = shape.cells
	room.wall_edges = shape.wall_edges
	room.floor_id = target_floor
	var changed: Array = [room.id]
	for id: String in ignored:
		var facility: Dictionary = world.facts.facilities[id]
		var position: Vector2i = Vector2i(int(facility.cell[0]),int(facility.cell[1]))-old_origin
		var corners: Array[Vector2i] = [position,position+Vector2i(int(facility.footprint[0])-1,0),position+Vector2i(0,int(facility.footprint[1])-1),position+Vector2i(int(facility.footprint[0])-1,int(facility.footprint[1])-1)]
		var start: Vector2i = Vector2i(96,96)
		for corner: Vector2i in corners:
			start = start.min(old_origin+delta+_rotate_offset(corner,old_size,turns))
		facility.cell = [start.x,start.y]
		facility.rotation = posmod(int(facility.get("rotation",0))+turns,4)
		facility.floor_id = target_floor
		var definition: Dictionary = content.facility_definition(facility.definition_id)
		facility.footprint = definition.footprint.duplicate()
		if int(facility.rotation)%2==1:
			facility.footprint.reverse()
		_set_anchors(facility,definition)
		changed.append(id)
	var moved_doors: Array = []
	for door: Dictionary in world.facts.floors.overrides[str(previous_floor)].doors.duplicate():
		if door.room_id!=room.id:
			continue
		world.facts.floors.overrides[str(previous_floor)].doors.erase(door)
		var a: Vector2i = Vector2i(int(door.cell[0]),int(door.cell[1]))-old_origin
		var b: Vector2i = a+(Vector2i(int(door.span),0) if door.axis=="x" else Vector2i(0,int(door.span)))
		var aa: Vector2i = _rotate_vertex(a,old_size,turns)+old_origin+delta
		var bb: Vector2i = _rotate_vertex(b,old_size,turns)+old_origin+delta
		door.cell = [mini(aa.x,bb.x),mini(aa.y,bb.y)]
		door.axis = "x" if aa.y==bb.y else "y"
		moved_doors.append(door)
		changed.append(door.id)
	if not world.facts.floors.overrides.has(str(target_floor)):
		return BuildGeometry.failure("目标楼层没有取得真实楼板")
	world.facts.floors.overrides[str(target_floor)].doors.append_array(moved_doors)
	for id: String in ([] if _deferred_checks else ignored):
		var positioned: Dictionary = _facility_position(world,world.facts.facilities[id],[id])
		if not positioned.ok:
			return positioned
	var public: String = "" if _deferred_checks else _public_door(world,room)
	if not public.is_empty():
		return BuildGeometry.failure(public)
	return _success(0,0,changed,[previous_floor,target_floor])

static func _rotate_vertex(point: Vector2i, size: Array, turns: int) -> Vector2i:
	match posmod(turns,4):
		1: return Vector2i(int(size[1])-point.y,point.x)
		2: return Vector2i(int(size[0])-point.x,int(size[1])-point.y)
		3: return Vector2i(point.y,int(size[0])-point.x)
	return point

func _demolish(world: WorldState, payload: Dictionary) -> Dictionary:
	var id: String = str(payload.get("target_id",""))
	var busy: String = _busy(world,id)
	if not busy.is_empty():
		return BuildGeometry.failure(busy)
	if world.facts.rooms.has(id):
		for facility: Dictionary in world.facts.facilities.values():
			if facility.get("room_id","")==id:
				return BuildGeometry.failure("请先搬出或拆除房间内实际设施")
		var room: Dictionary = world.facts.rooms[id]
		var refund: int = _refund(room)
		var changed: Array = [id]
		for door: Dictionary in world.facts.floors.overrides[str(int(room.floor_id))].doors.duplicate():
			if door.room_id==id:
				refund += _refund(door)
				changed.append(door.id)
				world.facts.floors.overrides[str(int(room.floor_id))].doors.erase(door)
		world.facts.rooms.erase(id)
		return _success(0,refund,changed,[int(room.floor_id)])
	if world.facts.facilities.has(id):
		var facility: Dictionary = world.facts.facilities[id]
		world.facts.facilities.erase(id)
		return _success(0,_refund(facility),[id],[int(facility.floor_id)])
	var found: Dictionary = _door(world,id)
	if found.is_empty():
		return BuildGeometry.failure("拆除对象不存在；土地不能出售或撤销")
	world.facts.floors.overrides[str(found.floor_id)].doors.erase(found.door)
	var reason: String = "" if _deferred_checks else _public_door(world,world.facts.rooms[found.door.room_id])
	if not reason.is_empty():
		return BuildGeometry.failure("不能封掉房间唯一公共出口")
	return _success(0,_refund(found.door),[id],[int(found.floor_id)])

func _refund(record: Dictionary) -> int:
	var paid: int = int(record.get("paid_cost",0))+int(record.get("completed_upgrade_paid_cost",0))
	if record.get("ownership","purchased") in ["gift","borrowed"]:
		paid = int(record.get("completed_upgrade_paid_cost",0)) if record.get("ownership")=="gift" else 0
	return floori(float(paid)*float(content.balance.refund_used if _used(record) else content.balance.refund_unused))

func _used(record: Dictionary) -> bool:
	return bool(record.get("used",false)) or not record.get("use_receipts",{}).is_empty()

func _land(world: WorldState, payload: Dictionary) -> Dictionary:
	if not BuildGeometry.point(payload.get("plot")) or int(payload.plot[0])<0 or int(payload.plot[0])>2 or int(payload.plot[1])<0 or int(payload.plot[1])>2 or int(payload.get("floor_id",1))!=1:
		return BuildGeometry.failure("只能逐块购买1F有效地块；上层沿楼板工单购买")
	var plots: Array = world.facts.floors.overrides["1"].plots
	if payload.plot in plots:
		return BuildGeometry.failure("该地块已取得")
	var adjacent: bool = false
	for plot: Array in plots:
		if absi(int(plot[0])-int(payload.plot[0]))+absi(int(plot[1])-int(payload.plot[1]))==1:
			adjacent = true
	if not adjacent:
		return BuildGeometry.failure("新地块必须与已有1F地块共边")
	var price: int = int(content.balance.plot_prices[plots.size()])
	plots.append(payload.plot.duplicate())
	if not world.facts.floors.has("land_purchases"):
		world.facts.floors.land_purchases = []
	world.facts.floors.land_purchases.append({"floor_id":1,"plot":payload.plot.duplicate(),"paid_cost":price,"tick":world.sim_tick})
	return _success(price,0,["plot:1:%d:%d" % [int(payload.plot[0]),int(payload.plot[1])]],[1])

func _busy(world: WorldState, id: String, allow_inventory_work: bool = false) -> String:
	for patch: Dictionary in world.facts.get("environment",{}).get("dirt",{}).values():
		if patch.get("bin_id","")==id:
			return "垃圾桶尚未清空，不能搬移或拆除"
	for collection: String in ([] if allow_inventory_work else ["jobs","upgrades"]):
		for order: Dictionary in world.facts.get("maintenance",{}).get(collection,{}).values():
			if order.get("facility_id","")==id and not order.get("phase","") in ["completed","cancelled","abandoned"]:
				return "设备存在未完成维护或升级工单，请先安全结束或取消工单"
	if world.facts.adaptations.has(id):
		return "等待当前使用者实际离开并释放伸展预约"
	for collection: String in ["sessions","preparations","ward_stays","tickets","facility_reservations","amenity_reservations","maintenance_orders","upgrade_orders"]:
		for record: Dictionary in world.facts.get(collection,{}).values():
			if _references(record,id):
				return "对象仍被实际服务、床位承诺或工作引用，请等待安全结束"
	for actor: Dictionary in world.facts.actors.values():
		if actor.get("support_facility_id","")==id:
			return "等待承托对象实际离开"
	return ""

func _references(value: Variant, id: String) -> bool:
	if value is String:
		return value==id
	if value is Array:
		for child: Variant in value:
			if _references(child,id):
				return true
	if value is Dictionary:
		for key: Variant in value:
			if str(key)==id or _references(value[key],id):
				return true
	return false

func _door(world: WorldState, id: String) -> Dictionary:
	for floor_key: String in world.facts.floors.overrides:
		for door: Dictionary in world.facts.floors.overrides[floor_key].get("doors",[]):
			if door.id==id:
				return {"floor_id":int(floor_key),"door":door}
	return {}

func _exists(world: WorldState, id: String) -> bool:
	return world.facts.rooms.has(id) or world.facts.facilities.has(id) or not _door(world,id).is_empty()

func _walls(room: Dictionary) -> Array:
	if room.has("wall_edges"):
		return room.wall_edges
	var occupied: Dictionary = {}
	for cell: Array in BuildGeometry.cells(room):
		occupied[Vector2i(int(cell[0]),int(cell[1]))] = true
	return BuildGeometry.walls(occupied)

func _public_door(world: WorldState, room: Dictionary) -> String:
	var floor_id: int = int(room.floor_id)
	for door: Dictionary in world.facts.floors.overrides[str(floor_id)].get("doors",[]):
		if door.room_id!=room.id:
			continue
		var sides: Array = [[int(door.cell[0]),int(door.cell[1])-1],[int(door.cell[0]),int(door.cell[1])]] if door.axis=="x" else [[int(door.cell[0])-1,int(door.cell[1])],[int(door.cell[0]),int(door.cell[1])]]
		for side: Array in sides:
			if BuildGeometry.contains(room,side) or not space.owned(world,floor_id,Vector2i(int(side[0]),int(side[1]))):
				continue
			var public: bool = true
			for other: Dictionary in world.facts.rooms.values():
				if int(other.floor_id)==floor_id and BuildGeometry.contains(other,side):
					public = false
			if public and not side in world.facts.floors.overrides[str(floor_id)].get("blocked",[]):
				var subject: Dictionary = {"id":"readonly-public-access","species_id":"S49","location":{"kind":"floor","floor_id":floor_id,"cell":side},"facing":0.0}
				var checker: HospitalSpace = HospitalSpace.new(content)
				if not checker.static_reason(world,subject,floor_id,Vector2i(int(side[0]),int(side[1]))).is_empty():
					continue
				if floor_id!=1 or checker._floor_route(world,subject,floor_id,Vector2i(int(side[0]),int(side[1])),Vector2i(47,93),[],{},true).get("ok",false):
					return ""
	return "至少一扇房门须通向本层已取得的公共空间"

func _safety(previous: WorldState, candidate: WorldState, floor_id: int) -> Dictionary:
	if not candidate.facts.floors.overrides.has(str(floor_id)):
		return BuildGeometry.failure("目标层没有真实地面或完工楼板")
	for room: Dictionary in candidate.facts.rooms.values():
		if int(room.floor_id)==floor_id and room.has("cells"):
			var public: String = _public_door(candidate,room)
			if not public.is_empty():
				return BuildGeometry.failure(public)
	for actor: Dictionary in candidate.facts.actors.values():
		if actor.location.kind!="floor" or int(actor.location.floor_id)!=floor_id:
			continue
		var checked: Dictionary = actor_safety(previous,candidate,actor)
		if not checked.ok:
			return checked
	return {"ok":true}

func actor_safety(previous: WorldState, candidate: WorldState, actor: Dictionary) -> Dictionary:
	# Real actors use the same complete route authority; no proxy enters WorldState.
	var checker: HospitalSpace = HospitalSpace.new(content)
	var floor_id: int = int(actor.location.floor_id)
	var start: Vector2i = Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1]))
	var previous_checker: HospitalSpace = HospitalSpace.new(content)
	if not checker.static_reason(candidate,actor,floor_id,start).is_empty() and previous_checker.static_reason(previous,actor,floor_id,start).is_empty():
		return BuildGeometry.failure("改建会侵犯实际身体："+str(actor.id),[actor.location.cell])
	var exit: Dictionary = checker.route(candidate,actor.id,1,[47,93],[],{},true)
	if not exit.get("ok",false):
		var before: Dictionary = previous_checker.route(previous,actor.id,1,[47,93],[],{},true)
		if before.get("ok",false):
			return BuildGeometry.failure("改建会切断实际身体的安全出口："+str(actor.id),[actor.location.cell])
	var movement: Dictionary = candidate.facts.moves.get(actor.id,{})
	if not movement.is_empty():
		var target: Dictionary = checker.route(candidate,actor.id,int(movement.target_floor),movement.target_cell,movement.get("members",[]),movement.get("offsets",{}),true)
		if not target.get("ok",false):
			return BuildGeometry.failure("改建会切断已承诺的实际移动目标："+str(actor.id),[movement.target_cell])
	return {"ok":true}

func _target_basis(world: WorldState, kind: String, payload: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var id: String = str(payload.get("target_id",""))
	if kind=="build_facility" and not str(payload.get("inventory_id","")).is_empty():
		return world.facts.inventory.get("build_items",{}).get(payload.inventory_id,{}).duplicate(true)
	if kind=="build_undo":
		return {"history":world.facts.get("build_history",[]).back().get("transaction_id","")} if not world.facts.get("build_history",[]).is_empty() else {}
	if not id.is_empty():
		var record: Dictionary = world.facts.rooms.get(id,world.facts.facilities.get(id,_door(world,id).get("door",{})))
		for field: String in ["id","kind","definition_id","floor_id","origin","size","cells","cell","rotation","room_id","paid_cost","ownership","grade"]:
			if record.has(field):
				result[field] = record[field].duplicate(true) if record[field] is Array or record[field] is Dictionary else record[field]
	return result

func _settlement_marker(world: WorldState) -> Array:
	var result: Array = []
	for key: String in world.facts.ledger.entries:
		var entry: Dictionary = world.facts.ledger.entries[key]
		if entry.settled and ("operating" in str(entry.component) or "operations" in str(entry.component) or "daily" in str(entry.component)):
			result.append(key)
	result.sort()
	return result

func _reference_marker(world: WorldState, ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for collection: String in ["sessions","preparations","ward_stays","tickets","staff","departments","amenity_reservations","facility_reservations","maintenance_orders","upgrade_orders"]:
		for key: String in world.facts.get(collection,{}):
			var record: Variant = world.facts[collection][key]
			for id: String in ids:
				if _references(record,id):
					result[collection+":"+key] = record.duplicate(true)
	return result

func _history(before: WorldState, after: WorldState, transaction_id: String, ids: Array, amount: int) -> Dictionary:
	var changes: Array = []
	for collection: String in ["rooms","facilities","build_items"]:
		for id: String in ids:
			var original: Dictionary = _records(before,collection).get(id,{})
			var current: Dictionary = _records(after,collection).get(id,{})
			if original!=current:
				changes.append({"collection":collection,"id":id,"before":original.duplicate(true),"after":current.duplicate(true)})
	var door_changes: Array = []
	for id: String in ids:
		var original: Dictionary = _door(before,id)
		var current: Dictionary = _door(after,id)
		if original!=current:
			door_changes.append({"id":id,"before":original.duplicate(true),"after":current.duplicate(true)})
	return {"transaction_id":transaction_id,"amount":amount,"tick":before.sim_tick,"changes":changes,"door_changes":door_changes,"settlements":_settlement_marker(after),"references":_reference_marker(after,ids),"changed_ids":ids.duplicate()}

func _undo(world: WorldState) -> Dictionary:
	var history: Array = world.facts.get("build_history",[])
	if history.is_empty():
		return BuildGeometry.failure("没有可撤销的普通建造操作；最多保留最近20次")
	var entry: Dictionary = history.back()
	if _settlement_marker(world)!=entry.settlements or world.sim_tick/WorldState.TICKS_PER_DAY!=int(entry.tick)/WorldState.TICKS_PER_DAY:
		return BuildGeometry.failure("该操作后已产生经营结算，请使用普通搬移或拆除")
	if _reference_marker(world,entry.changed_ids)!=entry.references:
		return BuildGeometry.failure("对象的实际引用已变化，不能撤销")
	var floors: Array = []
	for change: Dictionary in entry.changes:
		var current: Dictionary = _records(world,change.collection).get(change.id,{})
		if current!=change.after or _used(current) or _used(change.before) or not _busy(world,change.id).is_empty():
			return BuildGeometry.failure("对象已使用、改动或被预约，不能撤销")
		if current.has("floor_id") and not int(current.floor_id) in floors:
			floors.append(int(current.floor_id))
	for change: Dictionary in entry.door_changes:
		var current: Dictionary = _door(world,change.id)
		if current!=change.after or _used(current.get("door",{})) or _used(change.before.get("door",{})) or not _busy(world,change.id).is_empty():
			return BuildGeometry.failure("房门已使用、移动或被预约，不能撤销")
	for change: Dictionary in entry.changes:
		if change.before.is_empty():
			_records(world,change.collection).erase(change.id)
		else:
			_records(world,change.collection)[change.id] = change.before.duplicate(true)
			if change.before.has("floor_id") and not int(change.before.floor_id) in floors:
				floors.append(int(change.before.floor_id))
	for change: Dictionary in entry.door_changes:
		var current: Dictionary = _door(world,change.id)
		if not current.is_empty():
			world.facts.floors.overrides[str(current.floor_id)].doors.erase(current.door)
		if not change.before.is_empty():
			world.facts.floors.overrides[str(change.before.floor_id)].doors.append(change.before.door.duplicate(true))
	return _success(maxi(0,int(entry.amount)),maxi(0,-int(entry.amount)),entry.changed_ids.duplicate(),floors)

func validate(world: WorldState) -> String:
	if world.facts.has("build_history") and (not world.facts.build_history is Array or world.facts.build_history.size()>HISTORY_LIMIT):
		return "建造撤销记录结构或数量无效"
	if world.facts.has("build_transactions") and not world.facts.build_transactions is Dictionary:
		return "建造付款凭据集合无效"
	for id: Variant in world.facts.get("build_transactions",{}):
		var record: Variant = world.facts.build_transactions[id]
		if not id is String or not record is Dictionary or record.get("id")!=id or not record.get("kind") in KINDS or not record.get("tick") is int or int(record.tick)<0 or not record.get("amount") is int or not record.get("changed_ids") is Array or not record.get("undone") is bool or not record.get("record_key") is String or not record.get("payload") is Dictionary:
			return "建造付款凭据身份或结构无效"
		if int(record.tick)>world.sim_tick or absi(int(record.amount))>1000000000000:
			return "建造凭据金额或时点无效"
		for changed_id: Variant in record.changed_ids:
			if not changed_id is String or str(changed_id).is_empty():
				return "建造凭据对象身份无效"
		var posted: int = 0
		for component: String in ["construction","construction_refund"]:
			var entry: Dictionary = world.facts.ledger.entries.get(str(id)+":"+component,{})
			if not entry.is_empty():
				if not entry.get("settled",false):
					return "建造确认凭据不能保留待结算付款"
				posted += int(entry.get("amount",0))
		if posted!=int(record.amount):
			return "建造凭据与原整数账本金额不符"
	for room: Dictionary in world.facts.rooms.values():
		if not room.has("cells"):
			continue
		var definition: Dictionary = _room_type(str(room.get("kind","")))
		if definition.is_empty() or not room.get("wall_edges") is Array:
			return "建造房型或真实墙边定义缺失"
		var actual: Dictionary = BuildGeometry.shape(room,definition.min_inner_size)
		if not actual.ok or actual.origin!=room.get("origin") or actual.size!=room.get("size") or actual.wall_edges!=room.wall_edges:
			return "建造内格、无孔连通或真实墙边不一致"
		for cell: Array in actual.cells:
			if not space.owned(world,int(room.floor_id),Vector2i(int(cell[0]),int(cell[1]))):
				return "建造房间内格没有真实地面产权"
		var money_error: String = _ownership_error(room)
		if not money_error.is_empty():
			return money_error
	for facility: Dictionary in world.facts.facilities.values():
		if not facility.has("paid_cost"):
			continue
		var money_error: String = _ownership_error(facility)
		if not money_error.is_empty():
			return money_error
		if facility.has("rotation"):
			if not facility.rotation is int or int(facility.rotation)<0 or int(facility.rotation)>3:
				return "建造设施方向无效"
			var definition: Dictionary = content.facility_definition(str(facility.get("definition_id","")))
			if not BuildGeometry.point(definition.get("footprint"),true):
				return "建造设施缺少实际基座定义"
			var footprint: Array = definition.footprint.duplicate()
			if int(facility.rotation)%2==1:
				footprint.reverse()
			if footprint!=facility.get("footprint"):
				return "建造设施基座与当前旋转不一致"
	if world.facts.inventory.has("build_items") and not world.facts.inventory.build_items is Dictionary:
		return "建造实物库存集合无效"
	for id: Variant in world.facts.inventory.get("build_items",{}):
		var item: Variant = world.facts.inventory.build_items[id]
		if not id is String or not item is Dictionary or item.get("id")!=id or not item.get("definition_id") is String or content.facility_definition(item.definition_id).is_empty() or _exists(world,str(id)):
			return "建造库存身份、内容或唯一占有关系无效"
		var money_error: String = _ownership_error(item)
		if not money_error.is_empty():
			return money_error
	for history: Variant in world.facts.get("build_history",[]):
		if not history is Dictionary or not history.get("transaction_id") is String or not world.facts.get("build_transactions",{}).has(history.get("transaction_id","")) or not history.get("changes") is Array or not history.get("door_changes") is Array or not history.get("changed_ids") is Array or not history.get("references") is Dictionary or not history.get("settlements") is Array or not history.get("tick") is int or not history.get("amount") is int:
			return "建造撤销引用或结构无效"
		if world.facts.build_transactions[history.transaction_id].undone or int(world.facts.build_transactions[history.transaction_id].amount)!=int(history.amount) or int(history.tick)>world.sim_tick:
			return "建造撤销凭据已撤销或承诺不一致"
		for change: Variant in history.changes:
			if not change is Dictionary or not change.get("collection") in ["rooms","facilities","build_items"] or not change.get("id") is String or not change.get("before") is Dictionary or not change.get("after") is Dictionary:
				return "建造撤销对象快照无效"
			for snapshot: Dictionary in [change.before,change.after]:
				if not snapshot.is_empty() and (snapshot.get("id")!=change.id or not _ownership_error(snapshot).is_empty()):
					return "建造撤销对象身份或退款事实无效"
		for change: Variant in history.door_changes:
			if not change is Dictionary or not change.get("id") is String or not change.get("before") is Dictionary or not change.get("after") is Dictionary:
				return "建造撤销门引用无效"
			for snapshot: Dictionary in [change.before,change.after]:
				if not snapshot.is_empty() and (not snapshot.get("floor_id") is int or not snapshot.get("door") is Dictionary or snapshot.door.get("id")!=change.id or content.definition("doors",str(snapshot.door.get("definition_id",""))).is_empty()):
					return "建造撤销门的内容或楼层无效"
	return ""

func _ownership_error(record: Dictionary) -> String:
	if not record.get("paid_cost",0) is int or int(record.get("paid_cost",0))<0 or int(record.get("paid_cost",0))>1000000000000 or not record.get("ownership","purchased") in ["purchased","gift","borrowed"] or not record.get("used",false) is bool:
		return "建造实付、归属或已使用事实无效"
	if record.has("completed_upgrade_paid_cost") and (not record.completed_upgrade_paid_cost is int or int(record.completed_upgrade_paid_cost)<0):
		return "设施已完成升级实付无效"
	return ""

func _records(world: WorldState, collection: String) -> Dictionary:
	if collection=="build_items":
		if not world.facts.inventory.has("build_items"):
			return {}
		return world.facts.inventory.build_items
	return world.facts[collection]

func _success(price: int, refund: int, ids: Array, floors: Array) -> Dictionary:
	return {"ok":true,"reason":"","price":price,"refund":refund,"changed_ids":ids,"floors":floors,"blocked_cells":[]}
