class_name HospitalEnvironment
extends RefCounted

var content: HospitalContent
var space: HospitalSpace
var recruitment: RefCounted
var waiting_life: RefCounted
var _worked: Dictionary = {}
var _coverage_cache: Dictionary = {}
var _coverage_used: int = 0
var _query: Dictionary = {}
var _query_depth: int = 0
var query_builds: int = 0
var _water_ids: Dictionary = {}
var _positive_definitions: Dictionary = {}

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry
	for amenity: Dictionary in content.catalog.get("amenity_services",[]):
		if amenity.get("purpose","")=="water":
			for field: String in ["ordinary_facility_id","universal_facility_id"]: _water_ids[str(amenity.get(field,""))] = true
	_water_ids.erase("")

func _positive_definition(id: String) -> Dictionary:
	if not _positive_definitions.has(id):
		var definition: Dictionary = content.facility_definition(id)
		var record: Dictionary = {"decoration":definition.get("passive_decoration",false),"light":definition.get("environment","")=="light" or definition.get("environment_function","")=="light"}
		if definition.has("decoration_category"): record.category = definition.decoration_category
		_positive_definitions[id] = record
	return _positive_definitions[id]

# A synchronous observation batch changes experience records only. Geometry and
# coverage can be shared; water, noise, dirt and nearby people are still read live.
func begin_query(world: WorldState) -> void:
	if _query_depth>0 and _query.get("world")==world:
		_query_depth += 1
		return
	_query_depth = 1
	query_builds += 1
	_query = {"world":world,"edges":{},"coverage":{},"facilities":{},"screens":{},"actors":{},"samples":{"walls":{},"dirt":{},"machines":{},"construction":{}}}
	for facility: Dictionary in world.facts.facilities.values():
		var floor_id: int = int(facility.floor_id)
		if facility.definition_id in content.balance.environment.noise_barrier_definition_ids:
			if not _query.screens.has(floor_id): _query.screens[floor_id] = []
			_query.screens[floor_id].append(facility)
		var definition: Dictionary = _positive_definition(str(facility.definition_id))
		if not definition.decoration and not definition.light and not _is_water(str(facility.definition_id)): continue
		if not _query.facilities.has(floor_id): _query.facilities[floor_id] = {}
		var key: String = _cell_key(facility.cell)
		if not _query.facilities[floor_id].has(key): _query.facilities[floor_id][key] = []
		_query.facilities[floor_id][key].append(facility)
	for actor: Dictionary in world.facts.actors.values():
		if actor.location.kind!="floor": continue
		var floor_id: int = int(actor.location.floor_id)
		if not _query.actors.has(floor_id): _query.actors[floor_id] = {}
		var bucket: Vector2i = Vector2i(floori(float(actor.location.cell[0])/4.0),floori(float(actor.location.cell[1])/4.0))
		if not _query.actors[floor_id].has(bucket): _query.actors[floor_id][bucket] = []
		_query.actors[floor_id][bucket].append(actor)
	for surface: Dictionary in world.facts.get("environment",{}).get("surfaces",{}).values():
		if surface.surface=="wall": _index_sample("walls",int(surface.floor_id),surface.cell,surface)
	for patch: Dictionary in world.facts.get("environment",{}).get("dirt",{}).values():
		if str(patch.bin_id).is_empty(): _index_sample("dirt",int(patch.floor_id),patch.cell,patch)
	for session: Dictionary in world.facts.sessions.values():
		var facility: Dictionary = world.facts.facilities[session.facility_id]
		if facility.definition_id in content.balance.environment.machine_noise_definition_ids and session.kind in ["outpatient","surgery","operate"] and not facility.get("failed",false):
			_index_noise(world,"machines",facility)
	for id: String in world.active_operation_ids("environment","orders",["completed","cancelled"]):
		var order: Dictionary = world.facts.environment.orders[id]
		if order.paused: continue
		for unit: Dictionary in order.units:
			if unit.phase=="working" and not str(unit.worker_id).is_empty(): _index_sample("construction",int(order.floor_id),unit.cell,unit)
	for id: String in world.active_operation_ids("maintenance","upgrades",["completed","cancelled"]):
		var order: Dictionary = world.facts.maintenance.upgrades[id]
		if order.get("phase","")=="working" and world.facts.facilities.has(order.facility_id): _index_noise(world,"construction",world.facts.facilities[order.facility_id])

func _index_sample(kind: String, floor_id: int, cell: Array, record: Dictionary) -> void:
	var floors: Dictionary = _query.samples[kind]
	if not floors.has(floor_id): floors[floor_id] = {}
	var key: String = _cell_key(cell)
	if not floors[floor_id].has(key): floors[floor_id][key] = []
	floors[floor_id][key].append(record)

func _index_noise(world: WorldState, kind: String, facility: Dictionary) -> void:
	var layout: Dictionary = space.facility_layout(world,facility.id)
	for x: int in range(int(facility.cell[0]),int(facility.cell[0])+int(layout.footprint[0])):
		for y: int in range(int(facility.cell[1]),int(facility.cell[1])+int(layout.footprint[1])): _index_sample(kind,int(facility.floor_id),[x,y],facility)

func _sample_records(kind: String, floor_id: int, coverage: Dictionary) -> Array:
	var cells: Dictionary = _query.samples[kind].get(floor_id,{})
	var result: Array = []
	if cells.is_empty(): return result
	for key: String in coverage: result.append_array(cells.get(key,[]))
	return result

func _has_sample(kind: String, floor_id: int, coverage: Dictionary) -> bool:
	var cells: Dictionary = _query.samples[kind].get(floor_id,{})
	if cells.is_empty(): return false
	for key: String in coverage:
		if cells.has(key) and not cells[key].is_empty(): return true
	return false

func end_query() -> void:
	_query_depth -= 1
	if _query_depth>0: return
	# Preserve static coverage across consumers; each floor retains a bounded
	# set of origins. Viewing another floor cannot evict the operating batch.
	for floor_id: int in _query.get("edges",{}):
		if not _coverage_cache.has(floor_id): continue
		var entry: Dictionary = _coverage_cache[floor_id]
		entry.coverage.merge(_query.coverage.get(floor_id,{}))
		while entry.coverage.size()>128: entry.coverage.erase(entry.coverage.keys()[0])
	_query.clear()

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
		for id: String in world.facility_ids(str(content.balance.cleanup.bin_definition_id)):
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
		var ground: Dictionary = _ground_spawn_view(world,floor_id)
		for x: int in range(int(cell[0])-4,int(cell[0])+5):
			for y: int in range(int(cell[1])-4,int(cell[1])+5):
				var point: Array = [x,y]
				if _ground_spawn_legal(world,floor_id,point,ground):
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

func _ground_spawn_view(world: WorldState, floor_id: int) -> Dictionary:
	var points: Dictionary = {}
	var rectangles: Dictionary = {}
	var index: BodyIndex = BodyIndex.new()
	var floor_data: Dictionary = world.facts.floors.overrides.get(str(floor_id),{})
	for cell: Array in floor_data.get("blocked",[]): points[Vector2(float(cell[0]),float(cell[1]))] = true
	for door: Dictionary in floor_data.get("doors",[]): points[Vector2(float(door.cell[0]),float(door.cell[1]))] = true
	for patch: Dictionary in world.facts.environment.dirt.values():
		if int(patch.floor_id)==floor_id and patch.bin_id.is_empty(): points[Vector2(float(patch.cell[0]),float(patch.cell[1]))] = true
	for id: String in world.facts.facilities:
		var facility: Dictionary = world.facts.facilities[id]
		if int(facility.get("floor_id",-1))!=floor_id or facility.get("location","floor")=="inventory": continue
		var rect: Rect2 = _rectangle(facility)
		index.update(id,floor_id,rect)
		rectangles[id] = rect
		var cells: Array = facility.get("operator_cells",[]).duplicate()
		for field: String in ["patient_cell","repair_cell"]:
			if not facility.get(field,[]).is_empty(): cells.append(facility[field])
		for cell: Array in cells: points[Vector2(float(cell[0]),float(cell[1]))] = true
	for reservation: Dictionary in world.facts.adaptations.values():
		if int(reservation.get("floor_id",-1))!=floor_id: continue
		for cell: Array in reservation.get("occupied_cells",[]): points[Vector2(float(cell[0]),float(cell[1]))] = true
	return {"points":points,"rectangles":rectangles,"index":index}

func _ground_spawn_legal(world: WorldState, floor_id: int, cell: Array, view: Dictionary = {}) -> bool:
	if not space.owned(world,floor_id,Vector2i(int(cell[0]),int(cell[1]))):
		return false
	if view.is_empty(): view = _ground_spawn_view(world,floor_id)
	var point: Vector2 = Vector2(float(cell[0]),float(cell[1]))
	if view.points.has(point): return false
	for id: String in view.index.candidates(floor_id,Rect2(point,Vector2(0.001,0.001))):
		if view.rectangles[id].has_point(point): return false
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
	world.operation_records_changed("environment","orders")
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
	var pending: Dictionary = {}
	var pending_floors: Dictionary = {}
	var cleanup_indexed: bool = false
	for staff_id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[staff_id]
		if staff.role!="cleaner" or not _worker_ready(world,staff_id):
			continue
		if not cleanup_indexed:
			for patch: Dictionary in world.facts.environment.dirt.values():
				if not str(patch.worker_id).is_empty(): continue
				pending[patch.id] = patch
				var floor_id: int = int(patch.floor_id)
				if not pending_floors.has(floor_id): pending_floors[floor_id] = {}
				pending_floors[floor_id][patch.id] = patch
			cleanup_indexed = true
		var candidates: Array = []
		var zone: Dictionary = staff.get("work_region",{})
		var available: Dictionary = pending_floors.get(int(zone.floor_id),{}) if zone.get("strict",false) and zone.has("floor_id") else pending
		if available.is_empty(): continue
		# Selection only reads routes. Commit the winning task after closing the
		# scope, so the next worker sees every earlier assignment immediately.
		space.begin_dynamic_route_query(world)
		for patch: Dictionary in available.values():
			if not _allowed_region(staff,int(patch.floor_id),patch.cell):
				continue
			var place: Dictionary = _work_position(world,staff_id,int(patch.floor_id),patch.cell,not str(patch.bin_id).is_empty())
			if place.is_empty():
				patch.reason = "没有本员工可达的完整清扫操作位"
				continue
			candidates.append({"patch":patch,"place":place,"aged":world.sim_tick-int(patch.generated_tick)>=int(content.balance.cleanup.aging_seconds)*10,
				"pinned":str(world.facts.environment.pinned_dirt_id)==str(patch.id)})
		space.end_route_query()
		candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
			if a.aged!=b.aged: return a.aged
			if a.pinned!=b.pinned: return a.pinned
			if a.patch.generated_tick!=b.patch.generated_tick: return a.patch.generated_tick<b.patch.generated_tick
			if a.place.distance!=b.place.distance: return a.place.distance<b.place.distance
			return a.patch.id<b.patch.id)
		if not candidates.is_empty():
			var selected: Dictionary = candidates[0]
			if HospitalStaffWellbeing.yield_for_work(world,content,space,[staff_id]): continue
			selected.patch.worker_id = staff_id
			selected.patch.work_cell = selected.place.cell
			selected.patch.phase = "travelling"
			selected.patch.reason = ""
			staff.active_job_id = selected.patch.id
			pending.erase(selected.patch.id)
			pending_floors[int(selected.patch.floor_id)].erase(selected.patch.id)
	var safety: Dictionary = {}
	var tool_checked: bool = false
	var available_tool: String = ""
	for order_id: String in world.active_operation_ids("environment","orders",["completed","cancelled"],true):
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
			if not tool_checked:
				available_tool = _tool(world)
				tool_checked = true
			var tool_id: String = available_tool
			if tool_id.is_empty():
				order.reason = "等待正常装修工具台"
				break
			if not _unit_safe(world,order,unit,safety):
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
				if HospitalStaffWellbeing.yield_for_work(world,content,space,[staff_id]): continue
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
			space.public_areas.changed(world)
	var safety: Dictionary = {}
	for id: String in world.active_operation_ids("environment","orders",["completed","cancelled"],true):
		var order: Dictionary = world.facts.environment.orders[id]
		if order.paused or order.phase in ["completed","cancelled"]:
			continue
		for unit: Dictionary in order.units:
			if str(unit.worker_id).is_empty() or unit.phase in ["completed","cancelled"]:
				continue
			var tool: Dictionary = world.facts.facilities.get(unit.tool_id,{})
			if tool.is_empty() or bool(tool.get("failed",false)) or not _unit_safe(world,order,unit,safety):
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
				space.public_areas.changed(world)
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
	# The movement service owns this real journey and rechecks its next segment.
	# Requoting the whole trip cannot advance an already travelling worker.
	if world.facts.moves.has(worker_id): return false
	var route: Dictionary = space.route_cost(world,worker_id,floor_id,cell)
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
	return bool(staff.on_shift) and not staff.get("block_new_work",false) and not staff.get("supply_strike",false) and world.sim_tick>=int(staff.get("supply_return_tick",0)) and str(staff.get("training_job_id","")).is_empty() and HospitalStaffWellbeing.work_window(staff) and str(staff.get("active_job_id","")) in ["",own_job] and float(staff.get("energy",100))>15.0

func _release(world: WorldState, job: Dictionary) -> void:
	var worker_id: String = str(job.get("worker_id",""))
	if world.facts.staff.has(worker_id) and world.facts.staff[worker_id].get("active_job_id","")==job.id:
		world.facts.staff[worker_id].active_job_id = ""
	job.worker_id = ""
	if job.get("phase","") in ["working","travelling"]:
		job.phase = "queued"

func _work_position(world: WorldState, staff_id: String, floor_id: int, target: Array, adjacent: bool) -> Dictionary:
	var best: Dictionary = {}
	var actor: Dictionary = world.facts.actors[staff_id]
	var origin: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1])) if actor.location.kind=="floor" else Vector2.ZERO
	var start: Vector2i = Vector2i(roundi(origin.x),roundi(origin.y))
	var stub: float = origin.distance_to(Vector2(start))
	for offset: Array in ([[0,0],[-1,0],[0,-1],[0,1],[1,0]] if not adjacent else [[-1,0],[0,-1],[0,1],[1,0]]):
		var cell: Array = [int(target[0])+int(offset[0]),int(target[1])+int(offset[1])]
		if not _edge_open(world,floor_id,target,cell,false):
			continue
		# Connectors preserve XY and all floor edges are orthogonal. Equal
		# distance cannot replace the original first winner's strict comparison.
		if not best.is_empty() and stub+absi(start.x-int(cell[0]))+absi(start.y-int(cell[1]))>=float(best.distance): continue
		var path: Dictionary = space.route_cost(world,staff_id,floor_id,cell)
		if path.ok and (best.is_empty() or float(path.walking_distance)<float(best.distance)):
			best = {"cell":cell,"distance":path.walking_distance}
	return best

func _safety_query(world: WorldState) -> Dictionary:
	# Dispatch and advance do not move actors or change clinical commitments.
	# Rebuild from their live facts at each boundary, including direct writes;
	# no safety result or geometry survives the local synchronous phase.
	var occupied: BodyIndex = BodyIndex.new()
	var rooms: Dictionary = {}
	for actor_id: String in world.facts.actors:
		var actor: Dictionary = world.facts.actors[actor_id]
		if actor.location.kind=="floor": occupied.update("actor:"+actor_id,int(actor.location.floor_id),space.body_rectangle(actor))
	for stay_id: String in world.facts.ward_stays:
		var stay: Dictionary = world.facts.ward_stays[stay_id]
		var bed: Dictionary = world.facts.facilities[stay.bed_id]
		occupied.update("bed:"+stay_id,int(bed.floor_id),_rectangle(bed).grow(1))
	for session_id: String in world.facts.sessions:
		var session: Dictionary = world.facts.sessions[session_id]
		var facility: Dictionary = world.facts.facilities[session.facility_id]
		var floor_id: int = int(facility.floor_id)
		occupied.update("session:"+session_id,floor_id,_rectangle(facility).grow(1))
		if session.kind in ["surgery","operate","wake"]:
			if not rooms.has(floor_id): rooms[floor_id] = {}
			rooms[floor_id][str(facility.get("room_id",""))] = true
	return {"occupied":occupied,"rooms":rooms}

func _unit_safe(world: WorldState, order: Dictionary, unit: Dictionary, safety: Variant = null) -> bool:
	# A lone query or a run of occupied cells keeps the cheap early exit.
	# Build the batch only after a complete successful scan was necessary.
	if safety==null: return _unit_safe_direct(world,order,unit)
	if not safety.get("ready",false):
		var clear: bool = _unit_safe_direct(world,order,unit)
		if clear: safety.ready = true
		return clear
	if not safety.has("occupied"): safety.merge(_safety_query(world))
	var floor_id: int = int(order.floor_id)
	var rectangle: Rect2 = Rect2(float(unit.cell[0]),float(unit.cell[1]),1,1)
	# BodyIndex retains the original full Rect2 intersection, not just an
	# anchor-cell test. Excluding this worker never excludes beds or sessions.
	if safety.occupied.intersects(floor_id,rectangle,"actor:"+str(unit.worker_id)): return false
	if safety.rooms.has(floor_id) and safety.rooms[floor_id].has(_room_at(world,floor_id,unit.cell)): return false
	return true

func _unit_safe_direct(world: WorldState, order: Dictionary, unit: Dictionary) -> bool:
	var rectangle: Rect2 = Rect2(float(unit.cell[0]),float(unit.cell[1]),1,1)
	for actor_id: String in world.facts.actors:
		var actor: Dictionary = world.facts.actors[actor_id]
		if actor_id!=str(unit.worker_id) and actor.location.kind=="floor" and int(actor.location.floor_id)==int(order.floor_id) and space.body_rectangle(actor).intersects(rectangle): return false
	for stay: Dictionary in world.facts.ward_stays.values():
		var bed: Dictionary = world.facts.facilities[stay.bed_id]
		if int(bed.floor_id)==int(order.floor_id) and _rectangle(bed).grow(1).intersects(rectangle): return false
	for session: Dictionary in world.facts.sessions.values():
		var facility: Dictionary = world.facts.facilities[session.facility_id]
		if int(facility.floor_id)!=int(order.floor_id): continue
		if _rectangle(facility).grow(1).intersects(rectangle): return false
		if session.kind in ["surgery","operate","wake"] and facility.get("room_id","")==_room_at(world,int(order.floor_id),unit.cell): return false
	return true

func _tool(world: WorldState) -> String:
	for id: String in world.facility_ids(str(content.balance.renovation.tool_equipment_id)):
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
	for order_id: String in world.active_operation_ids("environment","orders",["completed","cancelled"]):
		var order: Dictionary = world.facts.environment.orders[order_id]
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
	world.completion_receipt_added("environment",id)
	# Completion evidence changes no floor geometry. The producing owner
	# publishes its actual material, dirt or completed-floor change separately.
	world.touch(false)

func _allowed_region(staff: Dictionary, floor_id: int, cell: Array) -> bool:
	var zone: Dictionary = staff.get("work_region",{})
	if zone.is_empty() or not zone.get("strict",false):
		return true
	return int(zone.get("floor_id",floor_id))==floor_id and Rect2(float(zone.origin[0]),float(zone.origin[1]),float(zone.size[0]),float(zone.size[1])).has_point(Vector2(float(cell[0]),float(cell[1])))

func _work_amount(world: WorldState, staff_id: String, action: String = "") -> int:
	if recruitment!=null and recruitment.has_method("work_rate"):
		if action.is_empty(): action = "cleanup" if world.facts.staff[staff_id].role=="cleaner" else "surface_unit"
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
		if int(room.floor_id)==floor_id and BuildGeometry.contains(room,cell):
			return str(room.id)
	return ""

func _wall_edge(world: WorldState, floor_id: int, cell: Array, edge: String) -> bool:
	var offset: Array = {"north":[0,-1],"south":[0,1],"west":[-1,0],"east":[1,0]}.get(edge,[])
	if offset.is_empty():
		return false
	var other: Array = [int(cell[0])+int(offset[0]),int(cell[1])+int(offset[1])]
	return other in world.facts.floors.overrides.get(str(floor_id),{}).get("blocked",[]) or _wall_between(world,floor_id,cell,other)

func _wall_between(world: WorldState, floor_id: int, first: Array, second: Array) -> bool:
	if first==second:
		return false
	var horizontal: bool = int(first[1])!=int(second[1])
	var axis: String = "x" if horizontal else "y"
	var line: int = maxi(int(first[1]),int(second[1])) if horizontal else maxi(int(first[0]),int(second[0]))
	var along: int = int(first[0]) if horizontal else int(first[1])
	for room: Dictionary in world.facts.rooms.values():
		if int(room.floor_id)!=floor_id:
			continue
		for wall: Dictionary in BuildGeometry.room_walls(room):
			if wall.axis!=axis or int(wall.line)!=line or along<int(wall.low) or along>=int(wall.high):
				continue
			var opening: bool = false
			for door: Dictionary in world.facts.floors.overrides.get(str(floor_id),{}).get("doors",[]):
				var door_line: int = int(door.cell[1] if horizontal else door.cell[0])
				var door_start: int = int(door.cell[0] if horizontal else door.cell[1])
				var span: int = int(world.facts.adaptations.get(door.id,{}).get("span",door.span))
				if door.room_id==room.id and door.axis==axis and door_line==line and along>=door_start and along<door_start+span:
					opening = true
					break
			if not opening:
				return true
	return false

func _cell_key(cell: Array) -> String:
	return "%d:%d" % [int(cell[0]),int(cell[1])]

func _coverage_edge_key(first: Array, second: Array) -> Vector3i:
	var horizontal: bool = int(first[1])!=int(second[1])
	return Vector3i(0 if horizontal else 1,maxi(int(first[1]),int(second[1])) if horizontal else maxi(int(first[0]),int(second[0])),int(first[0]) if horizontal else int(first[1]))

func _coverage_edges(world: WorldState, floor_id: int) -> Dictionary:
	if _query.get("world")==world and _query.edges.has(floor_id):
		return _query.edges[floor_id]
	var layout: Dictionary = world.facts.floors.overrides.get(str(floor_id),{})
	var source: Dictionary = {"floor_id":floor_id,"plots":space.floor_plots(world,floor_id),"blocked":layout.get("blocked",[]),"rooms":[],"doors":[],"screens":[]}
	for room: Dictionary in world.facts.rooms.values():
		if int(room.floor_id)!=floor_id: continue
		var shape: Dictionary = {"id":room.id,"origin":room.origin,"size":room.size}
		for field: String in ["cells","wall_edges"]:
			if room.has(field): shape[field] = room[field]
		source.rooms.append(shape)
	for door: Dictionary in layout.get("doors",[]):
		source.doors.append({"room_id":door.room_id,"axis":door.axis,"cell":door.cell,"span":int(world.facts.adaptations.get(door.id,{}).get("span",door.span))})
	var screens: Array = _query.screens.get(floor_id,[]) if _query.get("world")==world else world.facts.facilities.values()
	for facility: Dictionary in screens:
		if int(facility.floor_id)!=floor_id or not facility.definition_id in content.balance.environment.noise_barrier_definition_ids: continue
		var facing: int = int(facility.get("rotation",0))%4
		var across: Array = [int(facility.cell[0])+(1 if facing in [1,3] else 0),int(facility.cell[1])+(1 if facing in [0,2] else 0)]
		source.screens.append(_coverage_edge_key(facility.cell,across))
	var cached: Dictionary = _coverage_cache.get(floor_id,{})
	if cached.get("source",{})==source:
		_coverage_used += 1
		cached.used = _coverage_used
		if _query.get("world")==world: _query.edges[floor_id] = cached.edges
		return cached.edges
	var edges: Dictionary = {"walls":{},"noise":{},"blocked":{},"owned":{}}
	for plot: Array in source.plots: edges.owned[Vector2i(int(plot[0]),int(plot[1]))] = true
	for cell: Array in source.blocked: edges.blocked[Vector2i(int(cell[0]),int(cell[1]))] = true
	for room: Dictionary in source.rooms:
		for wall: Dictionary in BuildGeometry.room_walls(room):
			for along: int in range(int(wall.low),int(wall.high)):
				var opening: bool = false
				for door: Dictionary in source.doors:
					var line: int = int(door.cell[1] if wall.axis=="x" else door.cell[0])
					var begin: int = int(door.cell[0] if wall.axis=="x" else door.cell[1])
					var span: int = int(door.span)
					if door.room_id==room.id and door.axis==wall.axis and line==int(wall.line) and along>=begin and along<begin+span:
						opening = true
						break
				if not opening: edges.walls[Vector3i(0 if wall.axis=="x" else 1,int(wall.line),along)] = true
	for edge: Vector3i in source.screens: edges.noise[edge] = true
	_coverage_used += 1
	var entry: Dictionary = {"source":source.duplicate(true),"edges":edges,"coverage":{},"used":_coverage_used}
	_coverage_cache[floor_id] = entry
	if _coverage_cache.size()>8:
		var floors: Array = _coverage_cache.keys()
		floors.sort_custom(func(a: int,b: int)->bool: return int(_coverage_cache[a].used)<int(_coverage_cache[b].used))
		while _coverage_cache.size()>8: _coverage_cache.erase(floors.pop_front())
	if _query.get("world")==world: _query.edges[floor_id] = edges
	return edges

func _edge_open(world: WorldState, floor_id: int, first: Array, second: Array, noise: bool, edges: Dictionary = {}) -> bool:
	if not edges.is_empty() and float(first[0])==float(int(first[0])) and float(first[1])==float(int(first[1])):
		var cell: Vector2i = Vector2i(int(second[0]),int(second[1]))
		if cell.x<0 or cell.y<0 or cell.x>=96 or cell.y>=96 or edges.blocked.has(cell) or not edges.owned.has(Vector2i(cell.x/32,cell.y/32)): return false
		var key: Vector3i = _coverage_edge_key(first,second)
		return not edges.walls.has(key) and (not noise or not edges.noise.has(key))
	var floor_data: Dictionary = world.facts.floors.overrides.get(str(floor_id),{})
	if second in floor_data.get("blocked",[]):
		return false
	if not space.owned(world,floor_id,Vector2i(int(second[0]),int(second[1]))):
		return false
	if _wall_between(world,floor_id,first,second):
		return false
	if noise:
		for facility: Dictionary in world.facts.facilities.values():
			if facility.definition_id in content.balance.environment.noise_barrier_definition_ids and int(facility.floor_id)==floor_id:
				var facing: int = int(facility.get("rotation",0)) % 4
				var across: Array = [int(facility.cell[0])+(1 if facing in [1,3] else 0),int(facility.cell[1])+(1 if facing in [0,2] else 0)]
				if first==facility.cell and second==across or second==facility.cell and first==across:
					return false
	return true

func _coverage(world: WorldState, floor_id: int, origin: Array, radius: int, noise: bool, edges: Dictionary = {}) -> Dictionary:
	var origin_cell: Array = [int(origin[0]),int(origin[1])]
	var key: String = "%d:%d:%d:%d:%d" % [floor_id,origin_cell[0],origin_cell[1],radius,int(noise)]
	var scoped: bool = _query.get("world")==world and not edges.is_empty()
	if scoped:
		if not _query.coverage.has(floor_id): _query.coverage[floor_id] = {}
		if _query.coverage[floor_id].has(key): return _query.coverage[floor_id][key]
		var previous: Dictionary = _coverage_cache.get(floor_id,{}).get("coverage",{})
		if previous.has(key):
			_query.coverage[floor_id][key] = previous[key]
			return previous[key]
	var visited: Dictionary = {_cell_key(origin_cell):0}
	var queue: Array = [origin_cell]
	var cursor: int = 0
	while cursor<queue.size():
		var cell: Array = queue[cursor]
		cursor += 1
		var distance: int = int(visited[_cell_key(cell)])
		if distance>=radius:
			continue
		for offset: Array in [[-1,0],[0,-1],[0,1],[1,0]]:
			var next: Array = [int(cell[0])+int(offset[0]),int(cell[1])+int(offset[1])]
			var next_key: String = _cell_key(next)
			if not visited.has(next_key) and _edge_open(world,floor_id,cell,next,noise,edges):
				visited[next_key] = distance+1
				queue.append(next)
	if scoped: _query.coverage[floor_id][key] = visited
	return visited

func _positive_facilities(world: WorldState, floor_id: int, coverage: Dictionary) -> Array:
	if _query.get("world")!=world: return world.facts.facilities.values()
	var result: Array = []
	var cells: Dictionary = _query.facilities.get(floor_id,{})
	if cells.is_empty(): return result
	if cells.size()<coverage.size():
		for key: String in cells:
			if coverage.has(key): result.append_array(cells[key])
	else:
		for key: String in coverage: result.append_array(cells.get(key,[]))
	return result

func _nearby_actors(world: WorldState, floor_id: int, cell: Array) -> Array:
	if _query.get("world")!=world: return world.facts.actors.values()
	var buckets: Dictionary = _query.actors.get(floor_id,{})
	var result: Array = []
	for y: int in range(floori((float(cell[1])-3.0)/4.0),floori((float(cell[1])+3.0)/4.0)+1):
		for x: int in range(floori((float(cell[0])-3.0)/4.0),floori((float(cell[0])+3.0)/4.0)+1):
			result.append_array(buckets.get(Vector2i(x,y),[]))
	return result

func environment_at(world: WorldState, floor_id: int, cell: Array, actor_id: String = "", explain: bool = true) -> Dictionary:
	return _observe_at(world,floor_id,cell,actor_id,explain,true)

# Experience and anger consume environmental values without nearby-person detail.
func sample_at(world: WorldState, floor_id: int, cell: Array, actor_id: String = "") -> Dictionary:
	return _observe_at(world,floor_id,cell,actor_id,false,false)

func _observe_at(world: WorldState, floor_id: int, cell: Array, actor_id: String, explain: bool, nearby: bool) -> Dictionary:
	var rules: Dictionary = content.balance.environment
	var result: Dictionary = {"value":int(rules.base),"noise":0,"dirt":0,"clean":true,"water":false,"sources":[],"subject_id":actor_id,"reference":actor_id.is_empty()}
	if nearby: result.nearby_count = 0
	if not space.owned(world,floor_id,Vector2i(int(cell[0]),int(cell[1]))):
		result.status = "outside_owned_floor"
		return result
	var range_cells: int = int(rules.upgraded_range_cells if "R15" in world.facts.research else rules.range_cells)
	var scoped: bool = _query.get("world")==world
	# Only this read-only scope proves a field has no sources on the floor.
	var need_positive: bool = not scoped or not _query.facilities.get(floor_id,{}).is_empty() or not _query.samples.walls.get(floor_id,{}).is_empty()
	var need_dirt: bool = not scoped or not _query.samples.dirt.get(floor_id,{}).is_empty()
	var need_noise: bool = not scoped or not _query.samples.machines.get(floor_id,{}).is_empty() or not _query.samples.construction.get(floor_id,{}).is_empty()
	var edges: Dictionary = _coverage_edges(world,floor_id) if need_positive or need_dirt or need_noise else {}
	var positive: Dictionary = _coverage(world,floor_id,cell,range_cells,false,edges) if need_positive else {}
	var negative: Dictionary = {}
	if need_dirt or (need_noise and edges.noise.is_empty()):
		negative = positive if need_positive and range_cells==int(rules.range_cells) else _coverage(world,floor_id,cell,int(rules.range_cells),false,edges)
	var noise_cells: Dictionary = {}
	if need_noise: noise_cells = negative if edges.noise.is_empty() else _coverage(world,floor_id,cell,int(rules.range_cells),true,edges)
	var environment: Dictionary = world.facts.get("environment",{})
	var surfaces: Dictionary = environment.get("surfaces",{})
	var floor_finish: Dictionary = surfaces.get(_surface_key(floor_id,cell,"floor"),{})
	if not floor_finish.is_empty():
		var material: Dictionary = content.definition("renovation_materials",floor_finish.material_id)
		result.value += mini(int(rules.floor_cap),int(material.environment_value))
		if explain: result.sources.append({"kind":"floor","id":floor_finish.material_id,"value":int(material.environment_value)})
	var wall_value: int = 0
	var wall_distance: int = range_cells+1
	var wall_key: String = ""
	for surface: Dictionary in (_sample_records("walls",floor_id,positive) if _query.get("world")==world else surfaces.values()):
		if surface.surface!="wall" or int(surface.floor_id)!=floor_id or not positive.has(_cell_key(surface.cell)) or not _wall_edge(world,floor_id,surface.cell,str(surface.edge)):
			continue
		var distance: int = int(positive[_cell_key(surface.cell)])
		var key: String = _surface_key(floor_id,surface.cell,"wall",str(surface.edge))
		if distance<wall_distance or distance==wall_distance and (wall_key.is_empty() or key<wall_key):
			wall_distance = distance
			wall_key = key
			wall_value = int(content.definition("renovation_materials",surface.material_id).environment_value)
	result.value += mini(int(rules.wall_cap),wall_value)
	var categories: Dictionary = {}
	var light: bool = false
	for facility: Dictionary in _positive_facilities(world,floor_id,positive):
		if int(facility.get("floor_id",-1))!=floor_id or facility.get("location","floor")=="inventory" or bool(facility.get("failed",false)):
			continue
		if not positive.has(_cell_key(facility.cell)):
			continue
		var definition: Dictionary = _positive_definition(str(facility.definition_id))
		if definition.decoration:
			categories[str(definition.get("category",facility.get("decoration_category",facility.definition_id)))] = true
		if definition.light:
			light = true
		if not result.water and _is_water(str(facility.definition_id)) and _water_usable(world,facility,actor_id):
			result.water = true
	result.value += mini(int(rules.decoration_cap),categories.size()*int(rules.decoration_per_category))
	if light:
		result.value += int(rules.light_bonus)
	if result.water:
		result.value += int(rules.water_bonus)
	for patch: Dictionary in (_sample_records("dirt",floor_id,negative) if _query.get("world")==world else environment.get("dirt",{}).values()):
		if int(patch.floor_id)==floor_id and str(patch.bin_id).is_empty() and negative.has(_cell_key(patch.cell)):
			result.dirt += 1
			if explain: result.sources.append({"kind":"dirt","id":patch.id,"value":-int(rules.dirt_per_item)})
	result.clean = int(result.dirt)==0
	result.value += int(rules.clean_bonus) if result.clean else -mini(int(rules.dirt_cap),int(result.dirt)*int(rules.dirt_per_item))
	if _query.get("world")==world:
		if _has_sample("machines",floor_id,noise_cells): result.noise = maxi(int(result.noise),int(rules.machine_noise_penalty))
		if _has_sample("construction",floor_id,noise_cells): result.noise = maxi(int(result.noise),int(rules.construction_noise_penalty))
	else:
		_sample_noise(world,floor_id,noise_cells,result)
	if nearby:
		for actor: Dictionary in _nearby_actors(world,floor_id,cell):
			if actor.location.kind=="floor" and int(actor.location.floor_id)==floor_id and str(actor.id)!=actor_id and Vector2(float(actor.location.cell[0]),float(actor.location.cell[1])).distance_to(Vector2(float(cell[0]),float(cell[1])))<=3.0:
				result.nearby_count += 1
	result.value = clampi(int(result.value)-int(result.noise),0,100)
	result.status = "current"
	return result

func _sample_noise(world: WorldState, floor_id: int, noise_cells: Dictionary, result: Dictionary) -> void:
	var rules: Dictionary = content.balance.environment
	for session: Dictionary in world.facts.sessions.values():
		var facility: Dictionary = world.facts.facilities[session.facility_id]
		if int(facility.floor_id)==floor_id and facility.definition_id in rules.machine_noise_definition_ids and session.kind in ["outpatient","surgery","operate"] and not facility.get("failed",false) and _facility_in_coverage(world,facility,noise_cells):
			result.noise = maxi(int(result.noise),int(rules.machine_noise_penalty))
	for id: String in world.active_operation_ids("environment","orders",["completed","cancelled"]):
		var order: Dictionary = world.facts.environment.orders[id]
		if int(order.floor_id)!=floor_id or order.paused:
			continue
		for unit: Dictionary in order.units:
			if unit.phase=="working" and not str(unit.worker_id).is_empty() and noise_cells.has(_cell_key(unit.cell)):
				result.noise = maxi(int(result.noise),int(rules.construction_noise_penalty))
	for id: String in world.active_operation_ids("maintenance","upgrades",["completed","cancelled"]):
		var order: Dictionary = world.facts.maintenance.upgrades[id]
		if order.get("phase","")=="working" and world.facts.facilities.has(order.facility_id):
			var facility: Dictionary = world.facts.facilities[order.facility_id]
			if int(facility.floor_id)==floor_id and _facility_in_coverage(world,facility,noise_cells):
				result.noise = maxi(int(result.noise),int(rules.construction_noise_penalty))

func _is_water(definition_id: String) -> bool:
	return _water_ids.has(definition_id)

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
	return space.can_reach(world,actor_id,int(facility.floor_id),quote.get("patient_cell",facility.get("patient_cell",facility.cell)))

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
