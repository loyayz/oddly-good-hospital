class_name HospitalEnvironment
extends RefCounted

var content: HospitalContent
var space: HospitalSpace
var recruitment: RefCounted
var waiting_life: RefCounted
var _worked: Dictionary = {}

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry

func ensure(world: WorldState) -> void:
	if not world.facts.has("environment"):
		world.facts.environment = {"dirt":{},"orders":{},"surfaces":{},"receipts":{},"pinned_dirt_id":""}

func worked_staff() -> Dictionary:
	return _worked.duplicate()

func _surface_key(floor_id: int, cell: Array, surface: String, edge: String = "") -> String:
	return "%d:%d:%d:%s:%s" % [floor_id,int(cell[0]),int(cell[1]),surface,edge]

func record_use(world: WorldState, source: String, facility_id: String, receipt_id: String) -> void:
	if not world.facts.facilities.has(facility_id):
		return
	var definition: Dictionary = {}
	for candidate: Dictionary in content.catalog.cleanup_sources:
		if candidate.source == source:
			definition = candidate
	if definition.is_empty() or definition.uses_per_patch == null:
		return
	var facility: Dictionary = world.facts.facilities[facility_id]
	if not facility.has("cleanup_uses"):
		facility.cleanup_uses = {}
		facility.cleanup_receipts = {}
	var key: String = source+":"+receipt_id
	if facility.cleanup_receipts.has(key):
		return
	facility.cleanup_receipts[key] = world.sim_tick
	facility.cleanup_uses[source] = int(facility.cleanup_uses.get(source,0))+1
	if int(facility.cleanup_uses[source]) >= int(definition.uses_per_patch):
		facility.cleanup_uses[source] = 0
		spawn_dirt(world,str(definition.id),facility_id,key,int(facility.floor_id),facility.cell)

func spawn_dirt(world: WorldState, source_kind: String, source_id: String, source_receipt: String, floor_id: int, cell: Array) -> String:
	var source: Dictionary = content.definition("cleanup_sources",source_kind)
	if source.is_empty():
		return ""
	for patch: Dictionary in world.facts.environment.dirt.values():
		if patch.source_id == source_id and patch.source_kind == source_kind:
			return str(patch.id)
	var bin_id: String = ""
	var target: Array = []
	if bool(source.bin_collects):
		var reachable: Dictionary = _coverage(world,floor_id,cell,int(content.balance.cleanup.bin_range_cells),false)
		for id: String in world.ids("facilities"):
			var bin: Dictionary = world.facts.facilities[id]
			if bin.definition_id == content.balance.cleanup.bin_definition_id and int(bin.floor_id)==floor_id and reachable.has(_cell_key(bin.cell)):
				bin_id = id
				target = bin.cell.duplicate()
				break
		if not bin_id.is_empty():
			for patch: Dictionary in world.facts.environment.dirt.values():
				if patch.bin_id == bin_id:
					return str(patch.id)
	if target.is_empty():
		var candidates: Array = []
		for x: int in range(int(cell[0])-4,int(cell[0])+5):
			for y: int in range(int(cell[1])-4,int(cell[1])+5):
				var point: Array = [x,y]
				if _ground_spawn_legal(world,floor_id,point):
					candidates.append({"cell":point,"distance":absi(x-int(cell[0]))+absi(y-int(cell[1]))})
		candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
			if a.distance!=b.distance: return a.distance<b.distance
			if a.cell[0]!=b.cell[0]: return a.cell[0]<b.cell[0]
			return a.cell[1]<b.cell[1])
		if candidates.is_empty():
			return ""
		target = candidates[0].cell
	var count: int = 0
	for patch: Dictionary in world.facts.environment.dirt.values():
		if int(patch.floor_id)==floor_id and int(patch.cell[0])/32==int(target[0])/32 and int(patch.cell[1])/32==int(target[1])/32:
			count += 1
	if count>=int(content.balance.cleanup.active_patches_per_plot):
		return ""
	var id: String = world.new_id("dirt")
	var work: int = int(content.balance.cleanup.bin_work_seconds)*1000 if not bin_id.is_empty() else int(source.work_seconds)*1000
	world.facts.environment.dirt[id] = {"id":id,"source_kind":source_kind,"source_id":source_id,"source_receipt":source_receipt,
		"floor_id":floor_id,"cell":target.duplicate(),"bin_id":bin_id,"generated_tick":world.sim_tick,
		"total_milli":work,"remaining_milli":work,"contributions":{},"worker_id":"","work_cell":[],"phase":"queued","reason":""}
	world.touch()
	return id

func _ground_spawn_legal(world: WorldState, floor_id: int, cell: Array) -> bool:
	if not space.owned(world,floor_id,Vector2i(int(cell[0]),int(cell[1]))):
		return false
	var floor_data: Dictionary = world.facts.floors.overrides.get(str(floor_id),{})
	if cell in floor_data.get("blocked",[]):
		return false
	for door: Dictionary in floor_data.get("doors",[]):
		if door.cell == cell:
			return false
	for patch: Dictionary in world.facts.environment.dirt.values():
		if int(patch.floor_id)==floor_id and patch.bin_id.is_empty() and patch.cell==cell:
			return false
	for facility: Dictionary in world.facts.facilities.values():
		if int(facility.get("floor_id",-1))!=floor_id or facility.get("location","floor")=="inventory":
			continue
		if _rectangle(facility).has_point(Vector2(float(cell[0]),float(cell[1]))) or cell in facility.get("operator_cells",[]) or cell==facility.get("patient_cell",[]) or cell==facility.get("repair_cell",[]):
			return false
	for reservation: Dictionary in world.facts.adaptations.values():
		if int(reservation.get("floor_id",-1))==floor_id and cell in reservation.get("occupied_cells",[]):
			return false
	return true

func renovation_quote(world: WorldState, payload: Dictionary) -> Dictionary:
	var material: Dictionary = content.definition("renovation_materials",str(payload.get("material_id","")))
	var floor_id: int = int(payload.get("floor_id",0))
	var units: Variant = payload.get("units",[])
	var reason: String = ""
	var accepted: Array = []
	if material.is_empty() or not units is Array or units.is_empty() or units.size()>int(content.balance.renovation.max_units_per_order):
		reason = "材料或装修单元数量无效"
	else:
		var seen: Dictionary = {}
		for raw: Variant in units:
			if not raw is Dictionary or not raw.get("cell") is Array or raw.cell.size()!=2:
				reason = "装修坐标无效"
				break
			var cell: Array = [int(raw.cell[0]),int(raw.cell[1])]
			var edge: String = str(raw.get("edge","")) if material.surface=="wall" else ""
			if not space.owned(world,floor_id,Vector2i(int(cell[0]),int(cell[1]))):
				reason = "装修目标不在已启用楼板"
				break
			if material.surface == "wall" and not _wall_edge(world,floor_id,cell,edge):
				reason = "墙材需要真实墙边"
				break
			var key: String = _surface_key(floor_id,cell,str(material.surface),edge)
			if seen.has(key):
				reason = "同一表面不能重复计价"
				break
			seen[key] = true
			var original: Dictionary = world.facts.environment.surfaces.get(key,{})
			if original.get("material_id","")==material.id:
				continue
			if _surface_ordered(world,key):
				reason = "该表面已有未完成装修单"
				break
			accepted.append({"key":key,"cell":cell,"edge":edge,"original":original.duplicate(true)})
	if accepted.is_empty() and reason.is_empty():
		reason = "所选表面已经是同款材料"
	var price: int = int(material.get("unit_price",0))
	if payload.has("unit_price") and int(payload.unit_price)!=price:
		reason = "材料单价已经改变"
	var cost: int = accepted.size()*price
	if reason.is_empty() and HospitalLedger.balance(world)<cost:
		reason = "装修材料资金不足"
	if reason.is_empty() and not bool(payload.get("allow_waiting",false)) and (not _has_role(world,"decorator") or _tool(world).is_empty()):
		reason = "缺装修工或正常工具台，可明确选择付费待工"
	return {"ok":reason.is_empty(),"reason":reason,"floor_id":floor_id,"material_id":str(material.get("id","")),
		"surface":str(material.get("surface","")),"unit_price":price,"units":accepted,"cost":cost,
		"work_seconds":accepted.size()*int(content.balance.renovation.work_seconds_per_unit)}

func execute(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	match kind:
		"renovate", "renovation_order":
			var quote: Dictionary = renovation_quote(world,payload)
			if not quote.ok:
				return _reject(world,quote.reason)
			var id: String = "renovation_%08d" % (int(world.facts.entity_next)+1)
			var payment: CommandResult = HospitalLedger.post(world,LedgerEntry.new(id,"renovation_material",-int(quote.cost)))
			if not payment.accepted:
				return payment
			world.new_id("renovation")
			var units: Array = []
			for raw: Dictionary in quote.units:
				units.append({"id":id+":"+str(units.size()),"key":raw.key,"cell":raw.cell,"edge":raw.edge,
					"original":raw.original,"paid_cost":quote.unit_price,"remaining_milli":int(content.balance.renovation.work_seconds_per_unit)*1000,
					"total_milli":int(content.balance.renovation.work_seconds_per_unit)*1000,"started":false,"phase":"queued",
					"worker_id":"","work_cell":[],"contributions":{},"tool_id":"","tool_collected":false})
			world.facts.environment.orders[id] = {"id":id,"floor_id":quote.floor_id,"material_id":quote.material_id,
				"surface":quote.surface,"unit_price":quote.unit_price,"cost":quote.cost,"units":units,"created_tick":world.sim_tick,
				"paused":false,"cancel_requested":false,"refunded":0,"phase":"queued","reason":""}
			world.touch()
			return CommandResult.new(true,"applied","",[id],world.revision)
		"renovation_pause", "renovation_resume", "renovation_cancel":
			var id: String = str(payload.get("order_id",""))
			if not world.facts.environment.orders.has(id):
				return _reject(world,"装修工单不存在")
			var order: Dictionary = world.facts.environment.orders[id]
			if order.phase in ["completed","cancelled"]:
				return CommandResult.new(true,"duplicate","",[],world.revision)
			if kind=="renovation_cancel":
				var refund: int = 0
				for unit: Dictionary in order.units:
					if not unit.started and unit.phase!="cancelled":
						refund += int(unit.paid_cost)
						_release(world,unit)
						unit.phase = "cancelled"
				if not order.cancel_requested:
					HospitalLedger.post(world,LedgerEntry.new(id,"renovation_cancel_refund",refund))
					order.refunded += refund
				order.cancel_requested = true
				_finish_order(order)
			else:
				order.paused = kind=="renovation_pause"
				if order.paused:
					for unit: Dictionary in order.units:
						_release(world,unit)
			world.touch()
			return CommandResult.new(true,"applied","",[id],world.revision)
		"cleanup_pin":
			var id: String = str(payload.get("dirt_id",""))
			if not id.is_empty() and not world.facts.environment.dirt.has(id):
				return _reject(world,"待清扫目标不存在")
			world.facts.environment.pinned_dirt_id = id
			world.touch()
			return CommandResult.new(true,"applied","",[id],world.revision)
	return _reject(world,"未知环境操作")

func dispatch(world: WorldState) -> void:
	_worked.clear()
	for staff: Dictionary in world.facts.staff.values():
		if staff.role in ["cleaner","decorator"]:
			staff.dispatch_idle = false
			staff.dispatch_idle_tick = world.sim_tick
	for patch: Dictionary in world.facts.environment.dirt.values():
		if not str(patch.worker_id).is_empty() and not _worker_ready(world,str(patch.worker_id),str(patch.id)):
			_release(world,patch)
	for staff_id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[staff_id]
		if staff.role!="cleaner" or not _worker_ready(world,staff_id):
			continue
		var candidates: Array = []
		for patch: Dictionary in world.facts.environment.dirt.values():
			if not str(patch.worker_id).is_empty() or not _allowed_region(staff,int(patch.floor_id),patch.cell):
				continue
			var place: Dictionary = _work_position(world,staff_id,int(patch.floor_id),patch.cell,not str(patch.bin_id).is_empty())
			if place.is_empty():
				patch.reason = "没有本员工可达的完整清扫操作位"
				continue
			candidates.append({"patch":patch,"place":place,"aged":world.sim_tick-int(patch.generated_tick)>=int(content.balance.cleanup.aging_seconds)*10,
				"pinned":str(world.facts.environment.pinned_dirt_id)==str(patch.id)})
		candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
			if a.aged!=b.aged: return a.aged
			if a.pinned!=b.pinned: return a.pinned
			if a.patch.generated_tick!=b.patch.generated_tick: return a.patch.generated_tick<b.patch.generated_tick
			if a.place.distance!=b.place.distance: return a.place.distance<b.place.distance
			return a.patch.id<b.patch.id)
		if not candidates.is_empty():
			var selected: Dictionary = candidates[0]
			selected.patch.worker_id = staff_id
			selected.patch.work_cell = selected.place.cell
			selected.patch.phase = "travelling"
			selected.patch.reason = ""
			staff.active_job_id = selected.patch.id
	for order_id: String in _ordered(world.facts.environment.orders):
		var order: Dictionary = world.facts.environment.orders[order_id]
		if order.phase in ["completed","cancelled"] or order.paused:
			continue
		var assigned: int = 0
		for unit: Dictionary in order.units:
			if not str(unit.worker_id).is_empty():
				if not _worker_ready(world,str(unit.worker_id),str(unit.id)):
					_release(world,unit)
				else:
					assigned += 1
		for unit: Dictionary in order.units:
			if unit.phase in ["completed","cancelled"] or not str(unit.worker_id).is_empty() or assigned>=int(content.balance.renovation.max_workers_per_order):
				continue
			var tool_id: String = _tool(world)
			if tool_id.is_empty():
				order.reason = "等待正常装修工具台"
				break
			if not _unit_safe(world,order,unit):
				order.reason = "等待施工单元无人占用及临床安全边界"
				continue
			for staff_id: String in world.ids("staff"):
				var staff: Dictionary = world.facts.staff[staff_id]
				if staff.role!="decorator" or not _worker_ready(world,staff_id) or not _allowed_region(staff,int(order.floor_id),unit.cell):
					continue
				var place: Dictionary = _work_position(world,staff_id,int(order.floor_id),unit.cell,true)
				var tool: Dictionary = world.facts.facilities[tool_id]
				var tool_position: Dictionary = _work_position(world,staff_id,int(tool.floor_id),tool.cell,true)
				if place.is_empty() or tool_position.is_empty():
					continue
				unit.worker_id = staff_id
				unit.work_cell = place.cell
				unit.tool_id = tool_id
				unit.tool_cell = tool_position.cell
				unit.tool_collected = unit.started
				staff.active_job_id = unit.id
				assigned += 1
				break
	for staff_id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[staff_id]
		if staff.role in ["cleaner","decorator"] and _worker_ready(world,staff_id):
			staff.dispatch_idle = true

func advance(world: WorldState) -> void:
	for id: String in _ordered(world.facts.environment.dirt):
		var patch: Dictionary = world.facts.environment.dirt[id]
		if str(patch.worker_id).is_empty():
			continue
		if not _arrive(world,patch,int(patch.floor_id),patch.work_cell):
			continue
		var contribution: int = _work_amount(world,str(patch.worker_id))
		contribution = mini(contribution,int(patch.remaining_milli))
		patch.phase = "working"
		patch.remaining_milli -= contribution
		_contribute(patch,str(patch.worker_id),contribution)
		_worked[patch.worker_id] = true
		if int(patch.remaining_milli)==0:
			_receipt(world,"cleanup_completed",str(patch.id),patch.contributions,int(patch.total_milli))
			_release(world,patch)
			world.facts.environment.dirt.erase(id)
			if world.facts.environment.pinned_dirt_id==id:
				world.facts.environment.pinned_dirt_id = ""
	for id: String in _ordered(world.facts.environment.orders):
		var order: Dictionary = world.facts.environment.orders[id]
		if order.paused or order.phase in ["completed","cancelled"]:
			continue
		for unit: Dictionary in order.units:
			if str(unit.worker_id).is_empty() or unit.phase in ["completed","cancelled"]:
				continue
			var tool: Dictionary = world.facts.facilities.get(unit.tool_id,{})
			if tool.is_empty() or bool(tool.get("failed",false)) or not _unit_safe(world,order,unit):
				_release(world,unit)
				continue
			if not unit.tool_collected:
				if _arrive(world,unit,int(tool.floor_id),unit.tool_cell):
					unit.tool_collected = true
				continue
			if not _arrive(world,unit,int(order.floor_id),unit.work_cell):
				continue
			unit.started = true
			unit.phase = "working"
			order.phase = "working"
			order.reason = ""
			var amount: int = mini(_work_amount(world,str(unit.worker_id)),int(unit.remaining_milli))
			unit.remaining_milli -= amount
			_contribute(unit,str(unit.worker_id),amount)
			_worked[unit.worker_id] = true
			if int(unit.remaining_milli)==0:
				var original: Dictionary = unit.original
				var refund: int = floori(float(original.get("paid_cost",0))*float(content.balance.renovation.installed_refund))
				HospitalLedger.post(world,LedgerEntry.new(str(unit.id),"surface_replacement_refund",refund))
				world.facts.environment.surfaces[unit.key] = {"floor_id":order.floor_id,"cell":unit.cell.duplicate(),
					"surface":order.surface,"edge":unit.edge,"material_id":order.material_id,"paid_cost":unit.paid_cost,"order_id":order.id}
				_receipt(world,"renovation_completed",str(unit.id),unit.contributions,int(unit.total_milli))
				_release(world,unit)
				unit.phase = "completed"
		_finish_order(order)

func _arrive(world: WorldState, job: Dictionary, floor_id: int, cell: Array) -> bool:
	var worker_id: String = job.worker_id
	if not _worker_ready(world,worker_id,str(job.id)):
		_release(world,job)
		return false
	if space.at(world,worker_id,floor_id,cell):
		if world.facts.moves.has(worker_id) or not space.static_reason(world,world.facts.actors[worker_id],floor_id,Vector2i(int(cell[0]),int(cell[1]))).is_empty():
			return false
		return true
	var route: Dictionary = space.route(world,worker_id,floor_id,cell)
	if not route.ok:
		_release(world,job)
		job.reason = str(route.get("reason","清扫路线暂不可达"))
		return false
	space.request_move(world,worker_id,floor_id,cell)
	return false

func _worker_ready(world: WorldState, id: String, own_job: String = "") -> bool:
	if not world.facts.staff.has(id) or not world.facts.actors.has(id):
		return false
	var staff: Dictionary = world.facts.staff[id]
	return bool(staff.on_shift) and not staff.get("block_new_work",false) and not staff.get("supply_strike",false) and world.sim_tick>=int(staff.get("supply_return_tick",0)) and str(staff.get("training_job_id","")).is_empty() and staff.get("life_task",{"phase":"idle"}).get("phase","idle")=="idle" and str(staff.get("active_job_id","")) in ["",own_job] and float(staff.get("energy",100))>15.0

func _release(world: WorldState, job: Dictionary) -> void:
	var worker_id: String = str(job.get("worker_id",""))
	if world.facts.staff.has(worker_id) and world.facts.staff[worker_id].get("active_job_id","")==job.id:
		world.facts.staff[worker_id].active_job_id = ""
	job.worker_id = ""
	if job.get("phase","") in ["working","travelling"]:
		job.phase = "queued"

func _work_position(world: WorldState, staff_id: String, floor_id: int, target: Array, adjacent: bool) -> Dictionary:
	var best: Dictionary = {}
	for offset: Array in ([[0,0],[-1,0],[0,-1],[0,1],[1,0]] if not adjacent else [[-1,0],[0,-1],[0,1],[1,0]]):
		var cell: Array = [int(target[0])+int(offset[0]),int(target[1])+int(offset[1])]
		if not _edge_open(world,floor_id,target,cell,false):
			continue
		var path: Dictionary = space.route(world,staff_id,floor_id,cell)
		if path.ok and (best.is_empty() or float(path.walking_distance)<float(best.distance)):
			best = {"cell":cell,"distance":path.walking_distance}
	return best

func _unit_safe(world: WorldState, order: Dictionary, unit: Dictionary) -> bool:
	var rectangle: Rect2 = Rect2(float(unit.cell[0]),float(unit.cell[1]),1,1)
	for actor_id: String in world.facts.actors:
		var actor: Dictionary = world.facts.actors[actor_id]
		if actor_id==str(unit.worker_id) or actor.location.kind!="floor" or int(actor.location.floor_id)!=int(order.floor_id):
			continue
		if space.body_rectangle(actor).intersects(rectangle):
			return false
	for stay: Dictionary in world.facts.ward_stays.values():
		var bed: Dictionary = world.facts.facilities[stay.bed_id]
		if int(bed.floor_id)==int(order.floor_id) and _rectangle(bed).grow(1).intersects(rectangle):
			return false
	for session: Dictionary in world.facts.sessions.values():
		var facility: Dictionary = world.facts.facilities[session.facility_id]
		if int(facility.floor_id)==int(order.floor_id) and (facility.get("room_id","")==_room_at(world,int(order.floor_id),unit.cell) and session.kind in ["surgery","operate","wake"] or _rectangle(facility).grow(1).intersects(rectangle)):
			return false
	return true

func _tool(world: WorldState) -> String:
	for id: String in world.ids("facilities"):
		var tool: Dictionary = world.facts.facilities[id]
		if tool.definition_id==content.balance.renovation.tool_equipment_id and not tool.get("failed",false) and tool.get("location","floor")!="inventory":
			return id
	return ""

func _has_role(world: WorldState, role: String) -> bool:
	for staff: Dictionary in world.facts.staff.values():
		if staff.role==role:
			return true
	return false

func _surface_ordered(world: WorldState, key: String) -> bool:
	for order: Dictionary in world.facts.environment.orders.values():
		for unit: Dictionary in order.units:
			if unit.key==key and unit.phase not in ["completed","cancelled"]:
				return true
	return false

func _finish_order(order: Dictionary) -> void:
	for unit: Dictionary in order.units:
		if unit.phase not in ["completed","cancelled"]:
			return
	order.phase = "cancelled" if order.cancel_requested else "completed"

func _contribute(job: Dictionary, staff_id: String, amount: int) -> void:
	job.contributions[staff_id] = int(job.contributions.get(staff_id,0))+amount

func _receipt(world: WorldState, kind: String, source_id: String, contributions: Dictionary, total: int) -> void:
	var id: String = source_id+":"+kind
	if world.facts.environment.receipts.has(id):
		return
	var winner: String = ""
	var largest: int = -1
	for staff_id: String in _ordered(contributions):
		if int(contributions[staff_id])>largest:
			winner = staff_id
			largest = int(contributions[staff_id])
	if not world.facts.staff.has(winner):
		winner = ""
	world.facts.environment.receipts[id] = {"id":id,"kind":kind,"source_id":source_id,"staff_id":winner,"tick":world.sim_tick,"standard_work_milli":total}
	world.touch()

func _allowed_region(staff: Dictionary, floor_id: int, cell: Array) -> bool:
	var zone: Dictionary = staff.get("work_region",{})
	if zone.is_empty() or not zone.get("strict",false):
		return true
	return int(zone.get("floor_id",floor_id))==floor_id and Rect2(float(zone.origin[0]),float(zone.origin[1]),float(zone.size[0]),float(zone.size[1])).has_point(Vector2(float(cell[0]),float(cell[1])))

func _work_amount(world: WorldState, staff_id: String) -> int:
	if recruitment!=null and recruitment.has_method("work_rate"):
		var action: String = "cleanup" if world.facts.staff[staff_id].role=="cleaner" else "surface_unit"
		return roundi(100.0*float(recruitment.call("work_rate",world,staff_id,action)))
	var skill: int = int(world.facts.staff[staff_id].get("skill",world.facts.staff[staff_id].get("level",1)))
	return roundi(100.0*(1.0+float(content.balance.staff_practice.speed_per_extra_level)*maxi(0,skill-1)))

func _ordered(collection: Dictionary) -> Array:
	var result: Array = collection.keys()
	result.sort()
	return result

func _rectangle(facility: Dictionary) -> Rect2:
	return Rect2(float(facility.cell[0]),float(facility.cell[1]),float(facility.get("footprint",[1,1])[0]),float(facility.get("footprint",[1,1])[1]))

func _room_at(world: WorldState, floor_id: int, cell: Array) -> String:
	for room: Dictionary in world.facts.rooms.values():
		if int(room.floor_id)==floor_id and Rect2(float(room.origin[0]),float(room.origin[1]),float(room.size[0]),float(room.size[1])).has_point(Vector2(float(cell[0]),float(cell[1]))):
			return str(room.id)
	return ""

func _wall_edge(world: WorldState, floor_id: int, cell: Array, edge: String) -> bool:
	var offset: Array = {"north":[0,-1],"south":[0,1],"west":[-1,0],"east":[1,0]}.get(edge,[])
	if offset.is_empty():
		return false
	var other: Array = [int(cell[0])+int(offset[0]),int(cell[1])+int(offset[1])]
	return other in world.facts.floors.overrides.get(str(floor_id),{}).get("blocked",[]) or not space.owned(world,floor_id,Vector2i(int(other[0]),int(other[1])))

func _cell_key(cell: Array) -> String:
	return "%d:%d" % [int(cell[0]),int(cell[1])]

func _edge_open(world: WorldState, floor_id: int, first: Array, second: Array, noise: bool) -> bool:
	var floor_data: Dictionary = world.facts.floors.overrides.get(str(floor_id),{})
	if second in floor_data.get("blocked",[]):
		return false
	if not space.owned(world,floor_id,Vector2i(int(second[0]),int(second[1]))):
		return false
	if noise:
		for facility: Dictionary in world.facts.facilities.values():
			if facility.definition_id in content.balance.environment.noise_barrier_definition_ids and int(facility.floor_id)==floor_id:
				var facing: int = int(facility.get("rotation",0)) % 4
				var across: Array = [int(facility.cell[0])+(1 if facing in [1,3] else 0),int(facility.cell[1])+(1 if facing in [0,2] else 0)]
				if first==facility.cell and second==across or second==facility.cell and first==across:
					return false
	return true

func _coverage(world: WorldState, floor_id: int, origin: Array, radius: int, noise: bool) -> Dictionary:
	var visited: Dictionary = {_cell_key(origin):0}
	var queue: Array = [origin]
	var cursor: int = 0
	while cursor<queue.size():
		var cell: Array = queue[cursor]
		cursor += 1
		var distance: int = int(visited[_cell_key(cell)])
		if distance>=radius:
			continue
		for offset: Array in [[-1,0],[0,-1],[0,1],[1,0]]:
			var next: Array = [int(cell[0])+int(offset[0]),int(cell[1])+int(offset[1])]
			var key: String = _cell_key(next)
			if not visited.has(key) and _edge_open(world,floor_id,cell,next,noise):
				visited[key] = distance+1
				queue.append(next)
	return visited

func environment_at(world: WorldState, floor_id: int, cell: Array, actor_id: String = "") -> Dictionary:
	var rules: Dictionary = content.balance.environment
	var result: Dictionary = {"value":int(rules.base),"noise":0,"dirt":0,"clean":true,"water":false,"nearby_count":0,"sources":[],"subject_id":actor_id,"reference":actor_id.is_empty()}
	if not space.owned(world,floor_id,Vector2i(int(cell[0]),int(cell[1]))):
		result.status = "outside_owned_floor"
		return result
	var range_cells: int = int(rules.upgraded_range_cells if "R15" in world.facts.research else rules.range_cells)
	var positive: Dictionary = _coverage(world,floor_id,cell,range_cells,false)
	var negative: Dictionary = _coverage(world,floor_id,cell,int(rules.range_cells),false)
	var noise_cells: Dictionary = _coverage(world,floor_id,cell,int(rules.range_cells),true)
	var environment: Dictionary = world.facts.get("environment",{})
	var surfaces: Dictionary = environment.get("surfaces",{})
	var floor_finish: Dictionary = surfaces.get(_surface_key(floor_id,cell,"floor"),{})
	if not floor_finish.is_empty():
		var material: Dictionary = content.definition("renovation_materials",floor_finish.material_id)
		result.value += mini(int(rules.floor_cap),int(material.environment_value))
		result.sources.append({"kind":"floor","id":floor_finish.material_id,"value":int(material.environment_value)})
	var wall_value: int = 0
	for surface: Dictionary in surfaces.values():
		if surface.surface=="wall" and int(surface.floor_id)==floor_id and positive.has(_cell_key(surface.cell)):
			wall_value = maxi(wall_value,int(content.definition("renovation_materials",surface.material_id).environment_value))
	result.value += mini(int(rules.wall_cap),wall_value)
	var categories: Dictionary = {}
	var light: bool = false
	for facility: Dictionary in world.facts.facilities.values():
		if int(facility.get("floor_id",-1))!=floor_id or facility.get("location","floor")=="inventory" or bool(facility.get("failed",false)):
			continue
		if not positive.has(_cell_key(facility.cell)):
			continue
		var definition: Dictionary = content.facility_definition(str(facility.definition_id))
		if definition.get("passive_decoration",false):
			categories[str(definition.get("decoration_category",facility.get("decoration_category",facility.definition_id)))] = true
		if definition.get("environment","")=="light" or definition.get("environment_function","")=="light":
			light = true
		if _is_water(str(facility.definition_id)) and _water_usable(world,facility,actor_id):
			result.water = true
	result.value += mini(int(rules.decoration_cap),categories.size()*int(rules.decoration_per_category))
	if light:
		result.value += int(rules.light_bonus)
	if result.water:
		result.value += int(rules.water_bonus)
	for patch: Dictionary in environment.get("dirt",{}).values():
		if int(patch.floor_id)==floor_id and str(patch.bin_id).is_empty() and negative.has(_cell_key(patch.cell)):
			result.dirt += 1
			result.sources.append({"kind":"dirt","id":patch.id,"value":-int(rules.dirt_per_item)})
	result.clean = int(result.dirt)==0
	result.value += int(rules.clean_bonus) if result.clean else -mini(int(rules.dirt_cap),int(result.dirt)*int(rules.dirt_per_item))
	for session: Dictionary in world.facts.sessions.values():
		var facility: Dictionary = world.facts.facilities[session.facility_id]
		if int(facility.floor_id)==floor_id and facility.definition_id in rules.machine_noise_definition_ids and session.kind in ["outpatient","surgery","operate"] and not facility.get("failed",false) and _facility_in_coverage(world,facility,noise_cells):
			result.noise = maxi(int(result.noise),int(rules.machine_noise_penalty))
	for order: Dictionary in environment.get("orders",{}).values():
		if int(order.floor_id)!=floor_id or order.paused:
			continue
		for unit: Dictionary in order.units:
			if unit.phase=="working" and not str(unit.worker_id).is_empty() and noise_cells.has(_cell_key(unit.cell)):
				result.noise = maxi(int(result.noise),int(rules.construction_noise_penalty))
	for order: Dictionary in world.facts.get("maintenance",{}).get("upgrades",{}).values():
		if order.get("phase","")=="working" and world.facts.facilities.has(order.facility_id):
			var facility: Dictionary = world.facts.facilities[order.facility_id]
			if int(facility.floor_id)==floor_id and _facility_in_coverage(world,facility,noise_cells):
				result.noise = maxi(int(result.noise),int(rules.construction_noise_penalty))
	for actor: Dictionary in world.facts.actors.values():
		if actor.location.kind=="floor" and int(actor.location.floor_id)==floor_id and str(actor.id)!=actor_id and Vector2(float(actor.location.cell[0]),float(actor.location.cell[1])).distance_to(Vector2(float(cell[0]),float(cell[1])))<=3.0:
			result.nearby_count += 1
	result.value = clampi(int(result.value)-int(result.noise),0,100)
	result.status = "current"
	return result

func _is_water(definition_id: String) -> bool:
	for amenity: Dictionary in content.catalog.get("amenity_services",[]):
		if amenity.get("purpose","")=="water" and definition_id in [str(amenity.get("ordinary_facility_id","")),str(amenity.get("universal_facility_id",""))]:
			return true
	return false

func _facility_in_coverage(world: WorldState, facility: Dictionary, coverage: Dictionary) -> bool:
	var layout: Dictionary = space.facility_layout(world,str(facility.id))
	for x: int in range(int(facility.cell[0]),int(facility.cell[0])+int(layout.footprint[0])):
		for y: int in range(int(facility.cell[1]),int(facility.cell[1])+int(layout.footprint[1])):
			if coverage.has(_cell_key([x,y])):
				return true
	return false

func _water_usable(world: WorldState, facility: Dictionary, actor_id: String) -> bool:
	if actor_id.is_empty() or not world.facts.actors.has(actor_id):
		return false
	if waiting_life!=null:
		return bool(waiting_life.call("facility_availability",world,actor_id,str(facility.id)).get("ok",false))
	var quote: Dictionary = space.facility_quote(world,str(facility.id),actor_id)
	if not quote.get("ok",false):
		return false
	var route: Dictionary = space.route(world,actor_id,int(facility.floor_id),quote.get("patient_cell",facility.get("patient_cell",facility.cell)))
	return bool(route.ok)

func heatmap(world: WorldState, floor_id: int, cells: Array, actor_id: String = "") -> Array:
	var result: Array = []
	for cell: Array in cells:
		result.append({"cell":cell.duplicate(),"environment":environment_at(world,floor_id,cell,actor_id)})
	return result

func validate(world: WorldState) -> String:
	var environment: Variant = world.facts.get("environment")
	if not environment is Dictionary or not environment.get("dirt") is Dictionary or not environment.get("orders") is Dictionary or not world.facts.get("facilities") is Dictionary:
		return "环境清洁或装修集合无效"
	var keys: Dictionary = {}
	for patch_value: Variant in environment.dirt.values():
		if not patch_value is Dictionary:
			return "清洁工作记录无效"
		var patch: Dictionary = patch_value
		if not patch.get("remaining_milli") is int or not patch.get("total_milli") is int or not patch.get("floor_id") is int or not patch.get("cell") is Array or patch.cell.size()!=2 or not patch.cell[0] is int or not patch.cell[1] is int or not patch.get("bin_id") is String:
			return "清洁工作字段类型无效"
		if int(patch.remaining_milli)<=0 or int(patch.remaining_milli)>int(patch.total_milli) or not space.owned(world,int(patch.floor_id),Vector2i(int(patch.cell[0]),int(patch.cell[1]))):
			return "清洁工作余量或位置无效"
		if not str(patch.bin_id).is_empty() and not world.facts.facilities.has(patch.bin_id):
			return "待清扫垃圾桶引用无效"
		var key: String = str(patch.bin_id) if not str(patch.bin_id).is_empty() else _surface_key(int(patch.floor_id),patch.cell,"dirt")
		if keys.has(key):
			return "同一地格或垃圾桶存在重复污物"
		keys[key] = true
	for order_value: Variant in environment.orders.values():
		if not order_value is Dictionary:
			return "装修订单记录无效"
		var order: Dictionary = order_value
		if not order.get("cost") is int or not order.get("unit_price") is int or not order.get("refunded") is int or not order.get("units") is Array or int(order.cost)!=int(order.unit_price)*order.units.size() or int(order.refunded)>int(order.cost):
			return "装修材料付款或退款不守恒"
		for unit_value: Variant in order.units:
			if not unit_value is Dictionary:
				return "装修单元记录无效"
			var unit: Dictionary = unit_value
			if not unit.get("remaining_milli") is int or not unit.get("total_milli") is int or int(unit.remaining_milli)<0 or int(unit.remaining_milli)>int(unit.total_milli):
				return "装修单元工作余量无效"
	return ""

func _reject(world: WorldState, reason: String) -> CommandResult:
	return CommandResult.new(false,"environment_unavailable",reason,[],world.revision)
