class_name HospitalBlueprints
extends RefCounted

var content: HospitalContent
var space: HospitalSpace
var services: Dictionary = {}

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry

func ensure(_world: WorldState) -> void:
	pass

func capture(world: WorldState, room_ids: Array, object_ids: Array, name: String) -> Dictionary:
	if room_ids.is_empty() and object_ids.is_empty(): return BuildGeometry.failure("请选择完整房间或公共物件")
	var rooms: Array = []
	var objects: Array = []
	var surfaces: Array = []
	var low: Vector2i = Vector2i(96,96)
	var floor_id: int = -1
	for id: String in room_ids:
		if not world.facts.rooms.has(id): return BuildGeometry.failure("原房间已不存在")
		var room: Dictionary = world.facts.rooms[id]
		if floor_id!=-1 and floor_id!=int(room.floor_id): return BuildGeometry.failure("蓝图只保存单层完整布局")
		floor_id = int(room.floor_id)
		low = low.min(Vector2i(int(room.origin[0]),int(room.origin[1])))
		var doors: Array = []
		for door: Dictionary in world.facts.floors.overrides[str(floor_id)].doors:
			if door.room_id==id: doors.append({"definition_id":door.definition_id,"cell":door.cell.duplicate(),"edge":"south" if door.axis=="x" else "east","offset":0})
		rooms.append({"local_id":id,"kind":room.kind,"cells":BuildGeometry.cells(room).duplicate(true),"doors":doors})
	for id: String in world.ids("facilities"):
		var object: Dictionary = world.facts.facilities[id]
		if not id in object_ids and not object.get("room_id","") in room_ids: continue
		if object.get("borrowed",false) or object.get("ownership","")=="borrowed" or object.get("unique",false) or object.has("gratitude_receipt_id") or object.has("story_id"): continue
		if floor_id!=-1 and floor_id!=int(object.floor_id): return BuildGeometry.failure("蓝图只保存单层布局")
		floor_id = int(object.floor_id)
		low = low.min(Vector2i(int(object.cell[0]),int(object.cell[1])))
		objects.append({"local_id":id,"definition_id":object.definition_id,"cell":object.cell.duplicate(),"rotation":int(object.get("rotation",0)),"grade":int(object.grade),"style":object.get("style",""),"room_ref":object.get("room_id","")})
	for room: Dictionary in rooms:
		for cell: Array in room.cells:
			cell[0] = int(cell[0])-low.x
			cell[1] = int(cell[1])-low.y
		for door: Dictionary in room.doors:
			door.cell[0] = int(door.cell[0])-low.x
			door.cell[1] = int(door.cell[1])-low.y
	for object: Dictionary in objects:
		object.cell[0] = int(object.cell[0])-low.x
		object.cell[1] = int(object.cell[1])-low.y
	for surface: Dictionary in world.facts.get("environment",{}).get("surfaces",{}).values():
		if int(surface.floor_id)!=floor_id: continue
		for room_id: String in room_ids:
			if BuildGeometry.contains(world.facts.rooms[room_id],surface.cell):
				surfaces.append({"cell":[int(surface.cell[0])-low.x,int(surface.cell[1])-low.y],"surface":surface.surface,"edge":surface.get("edge",""),"material_id":surface.material_id})
				break
	var links: Array = []
	for index: int in objects.size():
		if objects[index].definition_id=="EQ05": links.append({"bed_index":index})
	return {"ok":true,"reason":"","blueprint":{"schema_version":1,"id":"","revision":1,"name":name,"description":"","thumbnail":"","content_dependencies":[],"rooms":rooms,"objects":objects,"surfaces":surfaces,"bed_links":links}}

func builtin(id: String) -> Dictionary:
	var definition: Dictionary = content.definition("blueprint_presets",id)
	if definition.is_empty(): return BuildGeometry.failure("内置蓝图不存在")
	if definition.source_type=="starter_room":
		var source: WorldState = HospitalFactory.create("blueprint_source","蓝图来源",true,content)
		var result: Dictionary = capture(source,[str(definition.source_id)],[],str(definition.name))
		if result.ok:
			result.blueprint.id = id
			result.blueprint.description = definition.description
		return result
	for layout: Dictionary in content.layouts.layouts:
		if layout.id!=definition.source_id: continue
		var cells: Array = []
		for y: int in int(layout.size[1]):
			for x: int in int(layout.size[0]): cells.append([x,y])
		var objects: Array = []
		for index: int in layout.objects.size():
			var item: Dictionary = layout.objects[index]
			objects.append({"local_id":"object_"+str(index),"definition_id":item.definition_id,"cell":item.anchor.duplicate(),"rotation":int(item.get("rotation",0)),"grade":0,"style":"","room_ref":"room"})
		return {"ok":true,"reason":"","blueprint":{"schema_version":1,"id":id,"revision":1,"name":definition.name,"description":definition.description,"thumbnail":"","content_dependencies":[],"rooms":[{"local_id":"room","kind":layout.room_type_id,"cells":cells,"doors":[{"definition_id":layout.door_id,"edge":"south","offset":layout.door_offset}]}],"objects":objects,"surfaces":[],"bed_links":layout.bed_links.duplicate(true)}}
	return BuildGeometry.failure("内置蓝图源布局不存在")

func validate_definition(blueprint: Variant) -> String:
	if not blueprint is Dictionary or blueprint.get("schema_version")!=1 or not blueprint.get("name") is String or not blueprint.get("rooms") is Array or not blueprint.get("objects") is Array or not blueprint.get("surfaces",[]) is Array: return "蓝图格式或版本无效"
	if not blueprint.get("id") is String or not WorldState._natural(blueprint.get("revision")) or int(blueprint.revision)<1: return "蓝图身份或修订无效"
	for room: Variant in blueprint.rooms:
		if not room is Dictionary or not room.get("local_id") is String or not room.get("kind") is String or not room.get("cells") is Array or not room.get("doors") is Array: return "蓝图房间结构无效"
		for cell: Variant in room.cells:
			if not BuildGeometry.point(cell): return "蓝图房间坐标无效"
		for door: Variant in room.doors:
			if not door is Dictionary or not door.get("definition_id") is String or not door.get("edge") in ["north","east","south","west"] or not WorldState._natural(door.get("offset",0)) or door.has("cell") and not BuildGeometry.point(door.cell): return "蓝图房门结构无效"
	for item: Variant in blueprint.objects:
		if not item is Dictionary or not item.get("local_id") is String or not item.get("definition_id") is String or not BuildGeometry.point(item.get("cell")) or not item.get("room_ref","") is String or not WorldState._natural(item.get("rotation",0)) or int(item.get("rotation",0))>3 or not WorldState._natural(item.get("grade",0)) or int(item.get("grade",0))>2: return "蓝图物件结构无效"
	for surface: Variant in blueprint.get("surfaces",[]):
		if not surface is Dictionary or not BuildGeometry.point(surface.get("cell")) or not surface.get("material_id") is String or not surface.get("surface") in ["floor","wall"] or not surface.get("edge","") is String: return "蓝图材料结构无效"
	if not blueprint.get("bed_links",[]) is Array: return "蓝图病床引用结构无效"
	for link: Variant in blueprint.get("bed_links",[]):
		if not link is Dictionary or not WorldState._natural(link.get("bed_index")): return "蓝图病床引用结构无效"
	var ids: Dictionary = {}
	for room: Variant in blueprint.rooms:
		if not room is Dictionary or not room.get("local_id") is String or ids.has(room.local_id) or not room.get("cells") is Array or not room.get("doors") is Array: return "蓝图房间结构或局部身份无效"
		var definition: Dictionary = content.definition("build_room_types",str(room.get("kind","")))
		if definition.is_empty(): return "缺少房型定义："+str(room.get("kind",""))
		var shape: Dictionary = BuildGeometry.shape(room,definition.min_inner_size)
		if not shape.ok: return shape.reason
		ids[room.local_id] = true
		for door: Variant in room.doors:
			if not door is Dictionary or content.definition("doors",str(door.get("definition_id",""))).is_empty(): return "缺少房门定义"
	var object_ids: Dictionary = {}
	for item: Variant in blueprint.objects:
		if object_ids.has(item.local_id): return "蓝图物件局部身份重复"
		if content.facility_definition(item.definition_id).is_empty(): return "缺少设施定义："+str(item.definition_id)
		if not str(item.get("room_ref","")).is_empty() and not ids.has(item.room_ref): return "蓝图物件缺少完整房间"
		object_ids[item.local_id] = true
	var beds: Dictionary = {}
	for index: Variant in blueprint.get("bed_links",[]):
		var actual: int = int(index.get("bed_index",-1)) if index is Dictionary else int(index)
		if actual<0 or actual>=blueprint.objects.size() or beds.has(actual) or blueprint.objects[actual].definition_id!="EQ05": return "蓝图病床引用缺失或重复"
		beds[actual] = true
	for index: int in blueprint.objects.size():
		if blueprint.objects[index].definition_id=="EQ05" and not beds.has(index): return "蓝图病床引用缺失或重复"
	for surface: Dictionary in blueprint.get("surfaces",[]):
		if content.definition("renovation_materials",surface.material_id).is_empty(): return "缺少材料定义："+str(surface.material_id)
	return ""

func dependencies(blueprint: Dictionary) -> Array:
	var entries: Dictionary = {}
	for room: Dictionary in blueprint.rooms:
		entries["build_room_types:"+str(room.kind)] = {"collection":"build_room_types","id":room.kind}
		for door: Dictionary in room.doors: entries["doors:"+str(door.definition_id)] = {"collection":"doors","id":door.definition_id}
	for item: Dictionary in blueprint.objects: entries["facilities:"+str(item.definition_id)] = {"collection":"facilities","id":item.definition_id}
	for surface: Dictionary in blueprint.get("surfaces",[]): entries["renovation_materials:"+str(surface.material_id)] = {"collection":"renovation_materials","id":surface.material_id}
	var keys: Array = entries.keys()
	keys.sort()
	var result: Array = []
	for key: String in keys: result.append(entries[key])
	return result

func without_missing(blueprint: Dictionary) -> Dictionary:
	var result: Dictionary = blueprint.duplicate(true)
	result.id = ""
	result.revision = 1
	result.rooms = []
	var rooms: Dictionary = {}
	for room: Dictionary in blueprint.get("rooms",[]):
		if content.definition("build_room_types",str(room.get("kind",""))).is_empty(): continue
		var retained: Dictionary = room.duplicate(true)
		retained.doors = retained.doors.filter(func(door: Dictionary) -> bool: return not content.definition("doors",str(door.get("definition_id",""))).is_empty())
		if retained.doors.is_empty(): continue
		result.rooms.append(retained)
		rooms[room.local_id] = true
	result.objects = []
	for item: Dictionary in blueprint.get("objects",[]):
		if content.facility_definition(str(item.get("definition_id",""))).is_empty() or not str(item.get("room_ref","")).is_empty() and not rooms.has(item.room_ref): continue
		result.objects.append(item)
	result.surfaces = blueprint.get("surfaces",[]).filter(func(surface: Dictionary) -> bool: return not content.definition("renovation_materials",str(surface.get("material_id",""))).is_empty())
	result.bed_links = []
	for index: int in result.objects.size():
		if result.objects[index].definition_id=="EQ05": result.bed_links.append({"bed_index":index})
	return result

func preview(world: WorldState, payload: Dictionary) -> Dictionary:
	var blueprint: Variant = payload.get("blueprint",{})
	var reason: String = validate_definition(blueprint)
	if not reason.is_empty(): return BuildGeometry.failure(reason)
	if not BuildGeometry.point(payload.get("cell")): return BuildGeometry.failure("请选择蓝图目标位置")
	var floor_id: int = int(payload.get("floor_id",1))
	var origin: Array = payload.cell
	if HospitalSpace.floor_plots(world,floor_id).is_empty(): return BuildGeometry.failure("目标楼层尚未取得实际楼板")
	var candidate: WorldState = WorldState.new(world.freeze())
	HospitalSpace.materialize_layout(candidate,floor_id)
	var builder: BuildService = BuildService.new(content,HospitalSpace.new(content))
	builder._deferred_checks = true
	var room_ids: Dictionary = {}
	var changed: Array = []
	var purchase: int = 0
	var upgrade_cost: int = 0
	var material_cost: int = 0
	var choices: Array = []
	for raw: Dictionary in blueprint.rooms:
		var cells: Array = []
		for cell: Array in raw.cells: cells.append([int(cell[0])+int(origin[0]),int(cell[1])+int(origin[1])])
		var doors: Array = raw.doors.duplicate(true)
		for door: Dictionary in doors:
			if door.has("cell"): door.cell = [int(door.cell[0])+int(origin[0]),int(door.cell[1])+int(origin[1])]
		var plan: Dictionary = builder._plan(candidate,"build_room",{"room_type_id":raw.kind,"floor_id":floor_id,"cells":cells,"doors":doors},true)
		if not plan.ok: return plan
		candidate = plan.candidate
		room_ids[raw.local_id] = str(plan.changed_ids[0])
		changed.append_array(plan.changed_ids)
		purchase += int(plan.price)
	for raw: Dictionary in blueprint.objects:
		var stock: String = ""
		if bool(payload.get("use_inventory",true)):
			var keys: Array = candidate.facts.inventory.build_items.keys()
			keys.sort_custom(func(a: String,b: String) -> bool:
				var aa: bool = bool(candidate.facts.inventory.build_items[a].get("failed",false))
				var bb: bool = bool(candidate.facts.inventory.build_items[b].get("failed",false))
				return a<b if aa==bb else not aa)
			for key: String in keys:
				var item: Dictionary = candidate.facts.inventory.build_items[key]
				if item.definition_id==raw.definition_id and int(item.get("grade",0))==int(raw.get("grade",0)) and item.get("style","")==raw.get("style","") and not item.get("borrowed",false) and item.get("ownership","")!="borrowed" and not item.get("reserved",false):
					stock = key
					break
		var plan: Dictionary = builder._plan(candidate,"build_facility",{"definition_id":raw.definition_id,"floor_id":floor_id,"cell":[int(raw.cell[0])+int(origin[0]),int(raw.cell[1])+int(origin[1])],"rotation":int(raw.get("rotation",0)),"room_id":room_ids.get(raw.get("room_ref",""),""),"inventory_id":stock},true)
		if not plan.ok: return plan
		candidate = plan.candidate
		var id: String = str(plan.changed_ids[0])
		candidate.facts.facilities[id].style = raw.get("style","")
		changed.append_array(plan.changed_ids)
		purchase += int(plan.price)
		choices.append({"local_id":raw.local_id,"definition_id":raw.definition_id,"inventory_id":stock,"failed":candidate.facts.facilities[id].failed,"condition":candidate.facts.facilities[id].condition,"grade":candidate.facts.facilities[id].grade})
		if stock.is_empty() and int(raw.get("grade",0))>0:
			var upgrade: Dictionary = services.maintenance.upgrade_quote(candidate,{"facility_id":id,"target_level":int(raw.grade)})
			if not upgrade.ok: return BuildGeometry.failure(upgrade.reason)
			var result: CommandResult = services.maintenance.execute(candidate,"upgrade_order",{"facility_id":id,"target_level":int(raw.grade)})
			if not result.accepted: return BuildGeometry.failure(result.reason)
			upgrade_cost += int(upgrade.cost)
	if bool(payload.get("include_surfaces",false)):
		var batches: Dictionary = {}
		for surface: Dictionary in blueprint.get("surfaces",[]):
			if not batches.has(surface.material_id): batches[surface.material_id] = []
			batches[surface.material_id].append({"cell":[int(surface.cell[0])+int(origin[0]),int(surface.cell[1])+int(origin[1])],"edge":surface.get("edge","")})
		for material_id: String in batches:
			var units: Array = batches[material_id]
			for start: int in range(0,units.size(),int(content.balance.renovation.max_units_per_order)):
				var draft: Dictionary = {"floor_id":floor_id,"material_id":material_id,"units":units.slice(start,start+int(content.balance.renovation.max_units_per_order))}
				var quote: Dictionary = services.environment.renovation_quote(candidate,draft)
				if not quote.ok: return BuildGeometry.failure(quote.reason)
				var result: CommandResult = services.environment.execute(candidate,"renovation_order",draft)
				if not result.accepted: return BuildGeometry.failure(result.reason)
				material_cost += int(quote.cost)
	var checked: String = services.remodel._final_geometry(world,candidate,builder,[floor_id],changed)
	if not checked.is_empty(): return BuildGeometry.failure(checked)
	if HospitalLedger.balance(candidate)<purchase: return BuildGeometry.failure("资金不足，布局与库存保留")
	var department_id: String = str(payload.get("department_id",""))
	if not department_id.is_empty():
		var department: Dictionary = candidate.facts.get("departments",{}).get("units",{}).get(department_id,{})
		if department.is_empty(): return BuildGeometry.failure("目标运营科室已不存在")
		for room_id: String in room_ids.values(): department.room_ids.append(room_id)
	return {"ok":true,"reason":"","price":purchase+upgrade_cost+material_cost,"purchase_cost":purchase,"upgrade_cost":upgrade_cost,"material_cost":material_cost,"inventory_choices":choices,"changed_ids":changed,"candidate":candidate,"world_revision":world.revision}

func execute(world: WorldState, _kind: String, payload: Dictionary) -> CommandResult:
	var plan: Dictionary = preview(world,payload)
	if not plan.ok: return CommandResult.new(false,"blueprint_blocked",plan.reason,[],world.revision)
	if payload.get("quote",{})!={"price":plan.price,"inventory_choices":plan.inventory_choices}: return CommandResult.new(false,"material_change","完整报价或真实库存已变化，请刷新原蓝图草案",[],world.revision)
	var candidate: WorldState = plan.candidate
	var id: String = candidate.new_id("blueprint_build")
	if not candidate.facts.has("blueprint_transactions"): candidate.facts.blueprint_transactions = {}
	candidate.facts.blueprint_transactions[id] = {"id":id,"blueprint_id":payload.blueprint.id,"revision":payload.blueprint.revision,"amount":-int(plan.purchase_cost),"tick":world.sim_tick,"changed_ids":plan.changed_ids}
	var paid: CommandResult = HospitalLedger.post(candidate,LedgerEntry.new(id,"construction",-int(plan.purchase_cost)))
	if not paid.accepted: return paid
	world.facts = candidate.facts
	return CommandResult.new(true,"applied","",plan.changed_ids+[id],world.revision)
