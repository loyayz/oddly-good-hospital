class_name HospitalRemodel
extends RefCounted

const KINDS: Array[String] = ["remodel_prepare","remodel_apply","remodel_cancel"]
var content: HospitalContent
var space: HospitalSpace
var services: Dictionary = {}
var clinic: HospitalClinic

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry

func ensure(world: WorldState) -> void:
	if not world.facts.has("remodels"): world.facts.remodels = {}

static func blocked(world: WorldState, id: String) -> bool:
	return world.remodel_blocked(id)

func group_commands(world: WorldState, room_ids: Array, object_ids: Array, floor_id: int, origin: Array, turns: int) -> Dictionary:
	if not BuildGeometry.point(origin) or room_ids.is_empty() and object_ids.is_empty(): return BuildGeometry.failure("请选择完整房间或公共物件及目标位置")
	var low: Vector2i = Vector2i(96,96)
	var high: Vector2i = Vector2i.ZERO
	var source_floor: int = -1
	var records: Array = []
	for id: String in room_ids:
		if not world.facts.rooms.has(id): return BuildGeometry.failure("原房间已不存在")
		var room: Dictionary = world.facts.rooms[id]
		if source_floor!=-1 and int(room.floor_id)!=source_floor: return BuildGeometry.failure("整组只能选择同一层的完整布局")
		source_floor = int(room.floor_id)
		records.append({"id":id,"cell":room.origin,"size":room.size,"room":true})
	for id: String in object_ids:
		if not world.facts.facilities.has(id): return BuildGeometry.failure("原公共物件已不存在")
		var item: Dictionary = world.facts.facilities[id]
		if not str(item.get("room_id","")).is_empty(): return BuildGeometry.failure("房内物件随完整房间搬迁，请勿重复选择")
		if source_floor!=-1 and int(item.floor_id)!=source_floor: return BuildGeometry.failure("整组只能选择同一层布局")
		source_floor = int(item.floor_id)
		records.append({"id":id,"cell":item.cell,"size":item.footprint,"room":false})
	for record: Dictionary in records:
		low = low.min(Vector2i(int(record.cell[0]),int(record.cell[1])))
		high = high.max(Vector2i(int(record.cell[0])+int(record.size[0]),int(record.cell[1])+int(record.size[1])))
	var size: Array = [high.x-low.x,high.y-low.y]
	var commands: Array = []
	for record: Dictionary in records:
		var target: Vector2i = Vector2i(96,96)
		for corner: Vector2i in [Vector2i.ZERO,Vector2i(int(record.size[0])-1,0),Vector2i(0,int(record.size[1])-1),Vector2i(int(record.size[0])-1,int(record.size[1])-1)]:
			var local: Vector2i = Vector2i(int(record.cell[0]),int(record.cell[1]))-low+corner
			target = target.min(BuildService._rotate_offset(local,size,turns)+Vector2i(int(origin[0]),int(origin[1])))
		commands.append({"kind":"build_move","target_id":record.id,"cell":[target.x,target.y],"floor_id":floor_id,"turns":posmod(turns,4)})
	return {"ok":true,"commands":commands,"reason":""}

func execute(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	world.operation_records_changed("remodels")
	ensure(world)
	if kind=="remodel_prepare":
		var commands: Array = payload.get("commands",[]).duplicate(true)
		if commands.is_empty(): return _result(world,false,"改建安排缺少完整目标布局")
		var room_ids: Array = []
		var members: Array = []
		for command: Variant in commands:
			if not command is Dictionary or not command.get("kind","") in ["build_move","build_rotate","build_resize","build_door","build_demolish"]: return _result(world,false,"改建操作类型无效")
			var id: String = str(command.get("target_id",""))
			if blocked(world,id): return _result(world,false,"成员已经属于另一份改建安排")
			if world.facts.rooms.has(id):
				if not id in room_ids: room_ids.append(id)
			elif not world.facts.facilities.has(id):
				var found: Dictionary = services.building._door(world,id)
				if found.is_empty(): return _result(world,false,"原改建成员已不存在")
				var room_id: String = found.door.room_id
				if blocked(world,room_id): return _result(world,false,"房门所属房间已有其他改建安排")
				if not room_id in room_ids: room_ids.append(room_id)
				if not room_id in members: members.append(room_id)
			if not id in members: members.append(id)
		for facility: Dictionary in world.facts.facilities.values():
			if facility.get("room_id","") in room_ids and not facility.id in members:
				if blocked(world,facility.id): return _result(world,false,"房内成员已有其他改建安排")
				members.append(facility.id)
		var id: String = world.new_id("remodel")
		world.facts.remodels[id] = {"id":id,"state":"preparing","room_ids":room_ids,"member_ids":members,"commands":commands,"created_tick":world.sim_tick,"safe_transfer":bool(payload.get("safe_transfer",false)),"source_blueprint_revision":payload.get("source_blueprint_revision",0)}
		return _result(world,true,"",[id])
	var id: String = str(payload.get("order_id",""))
	var order: Dictionary = world.facts.remodels.get(id,{})
	if order.is_empty() or order.state!="preparing": return _result(world,false,"改建安排已经结束或不存在")
	if kind=="remodel_cancel":
		order.state = "cancelled"
		return _result(world,true,"",[id])
	var plan: Dictionary = preview(world,id)
	if not plan.ok: return _result(world,false,plan.reason)
	if payload.get("quote",{})!={"price":plan.price,"refund":plan.refund,"layout":plan.layout}:
		return _result(world,false,"请先查看当前完整改建报价，再确认应用")
	var candidate: WorldState = plan.candidate
	var paid: CommandResult = HospitalLedger.post(candidate,LedgerEntry.new(id,"remodel",int(plan.refund)-int(plan.price)))
	if not paid.accepted: return paid
	candidate.facts.remodels[id].state = "applied"
	candidate.facts.remodels[id].applied_tick = world.sim_tick
	candidate.facts.remodels[id].amount = int(plan.refund)-int(plan.price)
	world.facts = candidate.facts
	return _result(world,true,"",order.member_ids+[id])

func preview(world: WorldState, id: String) -> Dictionary:
	var order: Dictionary = world.facts.get("remodels",{}).get(id,{})
	if order.is_empty() or order.state!="preparing": return BuildGeometry.failure("改建安排已经结束")
	var reason: String = _waiting(world,order)
	if not reason.is_empty(): return BuildGeometry.failure(reason)
	var candidate: WorldState = WorldState.new(world.freeze())
	candidate.facts.remodels[id].state = "applying"
	var builder: BuildService = BuildService.new(content,HospitalSpace.new(content))
	builder._deferred_checks = true
	builder._remodel_application = true
	var price: int = 0
	var refund: int = 0
	var floors: Dictionary = {}
	for command: Dictionary in order.commands:
		var previous_room: Dictionary = candidate.facts.rooms.get(str(command.target_id),{})
		var previous_facility: Dictionary = candidate.facts.facilities.get(str(command.target_id),{})
		var source: Dictionary = previous_room if not previous_room.is_empty() else previous_facility
		if not source.is_empty(): floors[int(source.floor_id)] = true
		HospitalSpace.materialize_layout(candidate,int(command.get("floor_id",source.get("floor_id",1))))
		var result: Dictionary
		if not previous_room.is_empty() and command.kind=="build_move" and int(command.get("turns",0))!=0:
			var delta: Vector2i = Vector2i(int(command.cell[0])-int(previous_room.origin[0]),int(command.cell[1])-int(previous_room.origin[1]))
			result = builder._transform_room(candidate,previous_room,delta,int(command.turns),int(command.floor_id))
		else:
			result = builder._plan(candidate,str(command.kind),command,true)
			if result.ok: candidate = result.candidate
		if not result.ok: return result
		if not previous_facility.is_empty() and command.kind=="build_move" and int(command.get("turns",0))!=0:
			var facility: Dictionary = candidate.facts.facilities[previous_facility.id]
			facility.rotation = posmod(int(facility.get("rotation",0))+int(command.turns),4)
			facility.footprint = content.facility_definition(facility.definition_id).footprint.duplicate()
			if int(facility.rotation)%2==1: facility.footprint.reverse()
			builder._set_anchors(facility,content.facility_definition(facility.definition_id))
		price += int(result.price)
		refund += int(result.refund)
		for floor_id: int in result.floors: floors[floor_id] = true
	var surface_result: Dictionary = _move_surfaces(world,candidate,order)
	if not surface_result.ok: return surface_result
	refund += int(surface_result.refund)
	var checked: String = _final_geometry(world,candidate,builder,floors.keys(),order.member_ids)
	if not checked.is_empty(): return BuildGeometry.failure(checked)
	if HospitalLedger.balance(world)+refund<price: return BuildGeometry.failure("资金不足，源布局和安排保留")
	return {"ok":true,"reason":"","price":price,"refund":refund,"layout":order.commands.duplicate(true),"candidate":candidate,"world_revision":world.revision}

func _waiting_view(world: WorldState) -> Dictionary:
	var view: Dictionary = {"sessions":{},"beds":{},"preparations":{},"units":{},"actors":{}}
	for session: Dictionary in world.facts.sessions.values():
		view.sessions[session.facility_id] = true
	for stay: Dictionary in world.facts.ward_stays.values():
		view.beds[stay.bed_id] = true
		view.beds[stay.get("transfer_from_bed_id","")] = true
	for preparation: Dictionary in world.facts.preparations.values():
		view.preparations[preparation.facility_id] = true
		view.preparations[preparation.get("bed_id","")] = true
	for id: String in world.active_operation_ids("environment","orders",["completed","cancelled"]):
		var record: Dictionary = world.facts.environment.orders[id]
		if not view.units.has(int(record.floor_id)): view.units[int(record.floor_id)] = []
		for unit: Dictionary in record.units: view.units[int(record.floor_id)].append(unit.cell)
	for actor: Dictionary in world.facts.actors.values():
		if actor.location.kind!="floor": continue
		var floor_id: int = int(actor.location.floor_id)
		if not view.actors.has(floor_id): view.actors[floor_id] = []
		view.actors[floor_id].append(actor)
	return view

func waiting_all(world: WorldState) -> Dictionary:
	var result: Dictionary = {}
	var orders: Array = world.active_operation_ids("remodels","",["applied","cancelled"],false,"state")
	if orders.is_empty(): return result
	var view: Dictionary = _waiting_view(world)
	for id: String in orders:
		if world.facts.remodels[id].state=="preparing": result[id] = _waiting(world,world.facts.remodels[id],view)
	return result

func _waiting(world: WorldState, order: Dictionary, view: Dictionary = {}) -> String:
	if view.is_empty(): view = _waiting_view(world)
	for member: String in order.member_ids:
		if view.sessions.has(member): return "等待当前临床安全结束、苏醒与真实转床"
	for member: String in order.member_ids:
		if view.beds.has(member): return "等待病床患者和原床位承诺安全释放"
	for member: String in order.member_ids:
		if view.preparations.has(member): return "等待原临床准备安全交接"
	var source_floor: int = _source_floor(world,order)
	for cell: Array in view.units.get(source_floor,[]):
		if _inside_source(world,order,cell): return "等待原装修安全结束，或明确取消未完成单元"
	for member: String in order.member_ids:
		if world.facts.adaptations.has(member): return "等待使用者实际离开并释放原占用"
	var affected: Dictionary = _affected_view(world,order)
	for floor_id: int in affected:
		for actor: Dictionary in view.actors.get(floor_id,[]):
			if _in_affected_area(world,order,actor,affected): return "等待实际人员走出源布局和目标范围"
	return ""

func dispatch(world: WorldState) -> void:
	for order_id: String in world.active_operation_ids("remodels","",["applied","cancelled"],false,"state"):
		var order: Dictionary = world.facts.remodels[order_id]
		if order.state!="preparing": continue
		for facility_id: String in order.member_ids:
			if not world.facts.facilities.has(facility_id): continue
			if order.safe_transfer: clinic.suspend_outpatient(world,facility_id)
			services.research.suspend_facility(world,facility_id,"等待原改建安排")
			services.development.suspend_facility(world,facility_id,"等待原改建安排")
		var reservations_by_owner: Dictionary = {}
		for reservation: Dictionary in world.facts.adaptations.values():
			if not reservations_by_owner.has(reservation.owner_id): reservations_by_owner[reservation.owner_id] = []
			reservations_by_owner[reservation.owner_id].append(reservation)
		for preparation_id: String in world.facts.preparations.keys():
			var preparation: Dictionary = world.facts.preparations[preparation_id]
			if preparation.facility_id in order.member_ids:
				var visit: Dictionary = world.facts.visits[preparation.visit_id]
				for reservation: Dictionary in reservations_by_owner.get(preparation.id,[]): reservation.owner_id = visit.actor_id
				world.facts.preparations.erase(preparation_id)
				if world.facts.tickets.has(visit.ticket_id):
					world.facts.tickets[visit.ticket_id].service_assigned = false
					world.facts.tickets[visit.ticket_id].called_tick = -1
		var affected: Dictionary = _affected_view(world,order)
		for actor_id: String in world.ids("actors"):
			var actor: Dictionary = world.facts.actors[actor_id]
			if actor.location.kind!="floor" or not _in_affected_area(world,order,actor,affected) or world.facts.moves.has(actor_id): continue
			var life: Dictionary = world.facts.staff.get(actor_id,{}).get("life_task",{})
			if life.get("kind","") in ["rest","sleep","recreation"] and life.get("phase","") in ["returning","release"]:
				var safe: Array = _evacuation(world,order,actor)
				if not safe.is_empty():
					life.floor_id = int(actor.location.floor_id)
					life.cell = safe.duplicate()
					space.request_move(world,actor_id,int(life.floor_id),life.cell)
				continue
			if life.get("phase","idle")!="idle" and life.get("kind","") in ["rest","sleep","recreation"] and not life.phase in ["returning","release","offsite","exiting"]:
				var safe: Array = _evacuation(world,order,actor)
				if not safe.is_empty():
					life.return_location = {"kind":"floor","floor_id":int(actor.location.floor_id),"cell":safe.duplicate(),"height_m":0.0}
					services.wellbeing._interrupt(world,actor_id)
				continue
			if _clinical_busy(world,actor_id): continue
			var target: Array = _evacuation(world,order,actor)
			if not target.is_empty():
				actor.posture = "standing"
				actor.erase("support_facility_id")
				space.request_move(world,actor_id,int(actor.location.floor_id),target)

func _clinical_busy(world: WorldState, actor_id: String) -> bool:
	var staff: Dictionary = world.facts.staff.get(actor_id,{})
	if staff.get("life_task",{}).get("phase","idle")!="idle": return true
	var base_task: Dictionary = staff.get("base_task",{})
	if base_task.get("phase","")=="working" and int(base_task.get("remaining_ticks",0))>0 and staff.get("on_shift",false) and not world.facts.moves.has(actor_id) and world.facts.facilities.has(base_task.get("facility_id","")):
		var base: Dictionary = space.facility_layout(world,base_task.facility_id)
		var operator_cell: Array = base.operator_cells[0] if not base.get("operator_cells",[]).is_empty() else base.patient_cell
		if space.at(world,actor_id,int(base.floor_id),operator_cell): return true
	for need: Dictionary in world.facts.get("waiting_life",{}).get("needs",{}).values():
		if world.facts.visits[need.visit_id].actor_id==actor_id and need.phase=="using": return true
	if HospitalClinicalDevelopment.safe_busy(world,actor_id): return true
	for session: Dictionary in world.facts.sessions.values():
		if actor_id in session.resources: return true
	for stay: Dictionary in world.facts.ward_stays.values():
		if world.facts.visits[world.facts.attempts[stay.attempt_id].visit_id].actor_id==actor_id: return true
		# Coverage and the promised final round remain medical duties between
		# bedside sessions; evacuation must not take their staff out of service.
		if stay.phase in ["reserved","transfer","recovery","round_wait","round"] and actor_id in [stay.nurse_id,stay.round_doctor_id]: return true
	return false

func _source_floor(world: WorldState, order: Dictionary) -> int:
	for id: String in order.room_ids:
		if world.facts.rooms.has(id): return int(world.facts.rooms[id].floor_id)
	for id: String in order.member_ids:
		if world.facts.facilities.has(id): return int(world.facts.facilities[id].floor_id)
	return -1

func _inside_source(world: WorldState, order: Dictionary, cell: Array) -> bool:
	for id: String in order.room_ids:
		if world.facts.rooms.has(id) and BuildGeometry.contains(world.facts.rooms[id],cell): return true
	return false

func _affected_view(world: WorldState, order: Dictionary) -> Dictionary:
	var view: Dictionary = {}
	for id: String in order.room_ids:
		var room: Dictionary = world.facts.rooms.get(id,{})
		if room.is_empty(): continue
		if not view.has(int(room.floor_id)): view[int(room.floor_id)] = {"rooms":[],"rects":[]}
		view[int(room.floor_id)].rooms.append(room)
	for id: String in order.member_ids:
		var item: Dictionary = world.facts.facilities.get(id,{})
		if item.is_empty(): continue
		if not view.has(int(item.floor_id)): view[int(item.floor_id)] = {"rooms":[],"rects":[]}
		view[int(item.floor_id)].rects.append(BuildGeometry.rectangle(space.facility_layout(world,id).merged({"cell":item.cell})))
	for command: Dictionary in order.commands:
		if command.kind!="build_move": continue
		var item: Dictionary = world.facts.rooms.get(command.target_id,world.facts.facilities.get(command.target_id,{}))
		if item.is_empty(): continue
		var size: Array = item.get("size",item.get("footprint",[1,1])).duplicate()
		if int(command.get("turns",0))%2==1: size.reverse()
		var floor_id: int = int(command.get("floor_id",-1))
		if not view.has(floor_id): view[floor_id] = {"rooms":[],"rects":[]}
		view[floor_id].rects.append(Rect2(float(command.cell[0]),float(command.cell[1]),float(size[0]),float(size[1])))
	return view

func _in_affected_area(world: WorldState, order: Dictionary, actor: Dictionary, view: Dictionary = {}) -> bool:
	if view.is_empty(): view = _affected_view(world,order)
	var floor_view: Dictionary = view.get(int(actor.location.floor_id),{})
	var body: Rect2 = space.body_rectangle(actor)
	for room: Dictionary in floor_view.get("rooms",[]):
		if BuildGeometry.intersects_room(body,room): return true
	for rect: Rect2 in floor_view.get("rects",[]):
		if body.intersects(rect,false): return true
	return false

func _evacuation(world: WorldState, order: Dictionary, actor: Dictionary) -> Array:
	var floor_id: int = int(actor.location.floor_id)
	var probe: Dictionary = actor.duplicate()
	probe.location = actor.location.duplicate()
	probe.posture = "standing"
	var affected: Dictionary = _affected_view(world,order)
	for y: int in 96:
		for x: int in 96:
			var origin: Vector2i = Vector2i(x,y)
			if not space.owned(world,floor_id,origin) or not space.static_reason(world,probe,floor_id,origin).is_empty(): continue
			var point: Array = [x,y]
			probe.location.cell = point
			if _in_affected_area(world,order,probe,affected): continue
			var rectangle: Rect2 = space.body_rectangle(probe)
			if not space._dynamic_clear(world,actor.id,floor_id,rectangle) or not _movement_targets_clear(world,actor.id,floor_id,rectangle): continue
			var inside: bool = false
			for room: Dictionary in world.facts.rooms.values():
				if int(room.floor_id)==floor_id and BuildGeometry.intersects_room(rectangle,room): inside = true
			if inside: continue
			var route: Dictionary = space.route_cost(world,actor.id,floor_id,point)
			if route.ok and route.get("status","")!="contention": return point
	return []

func _movement_targets_clear(world: WorldState, actor_id: String, floor_id: int, rectangle: Rect2) -> bool:
	for movement: Dictionary in world.facts.moves.values():
		if int(movement.target_floor)!=floor_id: continue
		var members: Array = movement.get("members",[]).duplicate()
		if not movement.actor_id in members: members.append(movement.actor_id)
		for id: String in members:
			if id==actor_id: continue
			var offset: Array = [0,0] if id==movement.actor_id else movement.get("offsets",{}).get(id,[0,0])
			var origin: Vector2 = Vector2(float(movement.target_cell[0])+float(offset[0]),float(movement.target_cell[1])+float(offset[1]))
			if rectangle.intersects(space._actor_rect(world.facts.actors[id],origin),false): return false
	return true

func _final_geometry(previous: WorldState, candidate: WorldState, builder: BuildService, floors: Array, affected: Array) -> String:
	for room_id: String in candidate.ids("rooms"):
		var room: Dictionary = candidate.facts.rooms[room_id]
		if not room_id in affected: continue
		for door: Dictionary in candidate.facts.floors.overrides[str(int(room.floor_id))].doors:
			if door.room_id==room_id:
				var wall_error: String = builder._door_wall_error(room,door)
				if not wall_error.is_empty(): return wall_error
		var ignored: Array = []
		for facility: Dictionary in candidate.facts.facilities.values():
			if facility.get("room_id","")==room_id: ignored.append(facility.id)
		var rects: Array = []
		for cell: Array in BuildGeometry.cells(room): rects.append(Rect2(float(cell[0]),float(cell[1]),1,1))
		var checked: Dictionary = BuildGeometry.occupied_error(candidate,space,int(room.floor_id),rects,ignored)
		if not checked.ok: return checked.reason
		for other: Dictionary in candidate.facts.rooms.values():
			if other.id!=room_id and int(other.floor_id)==int(room.floor_id):
				for cell: Array in BuildGeometry.cells(room):
					if BuildGeometry.contains(other,cell): return "整组目标房间内格重叠"
	for facility: Dictionary in candidate.facts.facilities.values():
		if facility.id in affected:
			var checked: Dictionary = builder._facility_position(candidate,facility,[facility.id])
			if not checked.ok: return checked.reason
	for floor_id: int in floors:
		var checked: Dictionary = builder._safety(previous,candidate,floor_id)
		if not checked.ok: return checked.reason
	return ""

func _move_surfaces(previous: WorldState, candidate: WorldState, order: Dictionary) -> Dictionary:
	var surfaces: Dictionary = candidate.facts.get("environment",{}).get("surfaces",{})
	var originals: Dictionary = previous.facts.get("environment",{}).get("surfaces",{})
	var moves: Dictionary = {}
	var removals: Dictionary = {}
	var refund: int = 0
	for key: String in originals:
		var surface: Dictionary = originals[key]
		var source_room: Dictionary = {}
		for room_id: String in order.room_ids:
			var room: Dictionary = previous.facts.rooms.get(room_id,{})
			if not room.is_empty() and int(room.floor_id)==int(surface.floor_id) and BuildGeometry.contains(room,surface.cell): source_room = room
		if source_room.is_empty(): continue
		var target_room: Dictionary = candidate.facts.rooms.get(source_room.id,{})
		removals[key] = true
		if target_room.is_empty():
			refund += int(surface.get("paid_cost",0))*80/100
			continue
		var command: Dictionary = {}
		for item: Dictionary in order.commands:
			if item.target_id==source_room.id: command = item
		var turns: int = int(command.get("turns",1 if command.get("kind","")=="build_rotate" else 0))
		var local: Vector2i = Vector2i(int(surface.cell[0])-int(source_room.origin[0]),int(surface.cell[1])-int(source_room.origin[1]))
		var offset: Vector2i = BuildService._rotate_offset(local,source_room.size,turns)
		var cell: Array = [int(target_room.origin[0])+offset.x,int(target_room.origin[1])+offset.y]
		if not BuildGeometry.contains(target_room,cell):
			refund += int(surface.get("paid_cost",0))*80/100
			continue
		var moved: Dictionary = surface.duplicate(true)
		moved.floor_id = int(target_room.floor_id)
		moved.cell = cell
		var edges: Array = ["north","east","south","west"]
		if str(moved.get("edge","")) in edges: moved.edge = edges[posmod(edges.find(moved.edge)+turns,4)]
		if moved.surface=="wall" and not services.environment._wall_edge(candidate,int(moved.floor_id),moved.cell,moved.edge):
			refund += int(moved.get("paid_cost",0))*80/100
			continue
		var target_key: String = services.environment._surface_key(int(moved.floor_id),moved.cell,moved.surface,str(moved.get("edge","")))
		moves[target_key] = moved
	for key: String in removals: surfaces.erase(key)
	for key: String in moves:
		if surfaces.has(key):
			var existing: Dictionary = surfaces[key]
			for other: Dictionary in candidate.facts.rooms.values():
				if not other.id in order.room_ids and int(other.floor_id)==int(existing.floor_id) and BuildGeometry.contains(other,existing.cell): return BuildGeometry.failure("目标表面属于未选择房间")
			refund += int(existing.get("paid_cost",0))*80/100
		surfaces[key] = moves[key]
	return {"ok":true,"refund":refund}

func validate(world: WorldState) -> String:
	var orders: Variant = world.facts.get("remodels",{})
	if not orders is Dictionary: return "改建安排集合无效"
	var members: Dictionary = {}
	for id: Variant in orders:
		var order: Variant = orders[id]
		if not order is Dictionary or order.get("id")!=id or not order.get("state") in ["preparing","applied","cancelled"] or not order.get("room_ids") is Array or not order.get("member_ids") is Array or not order.get("commands") is Array: return "改建安排身份或目标无效"
		if order.state!="preparing": continue
		for member: Variant in order.member_ids:
			if not member is String or members.has(member): return "同一成员存在重复改建安排"
			members[member] = id
			if not world.facts.rooms.has(member) and not world.facts.facilities.has(member) and services.building._door(world,member).is_empty(): return "改建原成员已丢失"
	return ""

func _result(world: WorldState, accepted: bool, reason: String, ids: Array = []) -> CommandResult:
	return CommandResult.new(accepted,"applied" if accepted else "remodel_blocked",reason,ids,world.revision)
