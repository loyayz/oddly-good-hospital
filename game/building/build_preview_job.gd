class_name BuildPreviewJob
extends RefCounted

var service: BuildService
var draft: Dictionary
var kind: String
var dependency_key: String
var complete: bool = false
var result: Dictionary = {"ok":false,"ready":false,"reason":"正在分片检查当前草案"}
var units_checked: int = 0
var atomic_overruns: int = 0
var _phase: String = "shape_start"
var _cursor: int = 0
var _actual: Array = []
var _occupied: Dictionary = {}
var _seen: Dictionary = {}
var _queue: Array[Vector2i] = []
var _low: Vector2i = Vector2i(96,96)
var _high: Vector2i = Vector2i(-1,-1)
var _minimum: Array = []
var _shape: Dictionary = {}
var _plan: Dictionary = {}
var _candidate: WorldState
var _source: WorldState
var _room_checks: Array = []
var _facility_checks: Array = []
var _public_checks: Array = []
var _actor_checks: Array = []

func _init(building: BuildService, world: WorldState, request: Dictionary) -> void:
	service = building
	draft = request.duplicate(true)
	kind = str(draft.get("kind","build_room"))
	dependency_key = dependencies(world)

func dependencies(world: WorldState) -> String:
	var floors: Array = [int(draft.get("floor_id",1))]
	var target_id: String = str(draft.get("target_id",""))
	var original: Dictionary = world.facts.rooms.get(target_id,world.facts.facilities.get(target_id,service._door(world,target_id).get("door",{})))
	var target_door: Dictionary = service._door(world,target_id)
	if not target_door.is_empty() and not int(target_door.floor_id) in floors:
		floors.append(int(target_door.floor_id))
	if original.has("floor_id") and not int(original.floor_id) in floors:
		floors.append(int(original.floor_id))
	# An upper-floor escape can depend on each actual connected floor, never empty levels.
	var cross_floor: bool = false
	for actor: Dictionary in world.facts.actors.values():
		if actor.location.kind=="floor" and int(actor.location.floor_id) in floors and int(actor.location.floor_id)!=1:
			cross_floor = true
	if cross_floor:
		for floor_key: String in world.facts.floors.overrides:
			if not int(floor_key) in floors:
				floors.append(int(floor_key))
	var values: Dictionary = {"hospital_id":world.hospital_id,"content":service.content.content_fingerprint,"floors":{},"rooms":{},"facilities":{},"actors":{},"adaptations":{},"connectors":{},"moves":{},"dirt":{},"target":service._target_basis(world,kind,draft),"busy":service._busy(world,target_id),"target_used":service._used(original),"upgrade_paid":original.get("completed_upgrade_paid_cost",0)}
	for floor_id: int in floors:
		var layout: Dictionary = HospitalSpace.floor_layout(world,floor_id)
		values.floors[str(floor_id)] = {"plots":layout.get("plots",[]),"blocked":layout.get("blocked",[]),"doors":[]}
		for door: Dictionary in layout.get("doors",[]):
			values.floors[str(floor_id)].doors.append(_fields(door,["id","definition_id","cell","span","axis","room_id"]))
	for room: Dictionary in world.facts.rooms.values():
		if int(room.floor_id) in floors:
			values.rooms[room.id] = _fields(room,["id","kind","floor_id","origin","size","cells","wall_edges"])
	for facility: Dictionary in world.facts.facilities.values():
		if int(facility.floor_id) in floors:
			values.facilities[facility.id] = _fields(facility,["id","definition_id","floor_id","cell","footprint","rotation","room_id"])
			if facility.get("room_id","")==target_id:
				values.facilities[facility.id].busy = service._busy(world,facility.id)
	for actor: Dictionary in world.facts.actors.values():
		if actor.location.kind=="floor" and int(actor.location.floor_id) in floors:
			values.actors[actor.id] = _fields(actor,["id","species_id","body_binding_id","location","posture","support_facility_id"])
			if world.facts.moves.has(actor.id):
				values.moves[actor.id] = _fields(world.facts.moves[actor.id],["target_floor","target_cell","members","offsets"])
	for key: String in world.facts.adaptations:
		if int(world.facts.adaptations[key].floor_id) in floors:
			values.adaptations[key] = world.facts.adaptations[key]
	for connector: Dictionary in world.facts.connectors.values():
		for floor_id: int in floors:
			if HospitalTransit.has_stop(connector,floor_id):
				values.connectors[connector.id] = connector
	for patch: Dictionary in world.facts.get("environment",{}).get("dirt",{}).values():
		if int(patch.get("floor_id",1)) in floors:
			values.dirt[patch.id] = _fields(patch,["id","floor_id","cell","bin_id"])
	if kind=="build_undo":
		values.history = world.facts.get("build_history",[])
		values.settlements = service._settlement_marker(world)
	if not _plan.is_empty() and _plan.get("ok",false):
		values.solvent = HospitalLedger.balance(world)+int(_plan.refund)-int(_plan.price)>=0
	elif not _plan.is_empty():
		values.retry_cash = HospitalLedger.balance(world)
	return JSON.stringify(values,"",true,true).sha256_text()

func advance(world: WorldState, budget_usec: int, maximum_units: int = 128) -> void:
	var start: int = Time.get_ticks_usec()
	var count: int = 0
	while not complete and count<maximum_units and (count==0 or Time.get_ticks_usec()-start<budget_usec):
		var unit_start: int = Time.get_ticks_usec()
		_step(world)
		if Time.get_ticks_usec()-unit_start>budget_usec:
			atomic_overruns += 1
		count += 1
		units_checked += 1
	if not complete:
		result = {"ok":false,"ready":false,"reason":"正在分片检查当前草案","phase":_phase,"units_checked":units_checked}

func _step(world: WorldState) -> void:
	match _phase:
		"shape_start":
			if kind!="build_room":
				_phase = "prepare"
				return
			var error: String = service._payload_error(draft)
			if not error.is_empty():
				_fail(error)
				return
			var definition: Dictionary = service._room_type(str(draft.get("room_type_id",draft.get("room_type",draft.get("type","gp")))))
			if definition.is_empty():
				_fail("未知房型")
				return
			_minimum = definition.min_inner_size
			if draft.has("cells"):
				if not draft.cells is Array or draft.cells.is_empty() or draft.cells.size()>9216:
					_fail("房间需要1至9216个实际内格")
					return
			else:
				if not BuildGeometry.point(draft.get("origin")) or not BuildGeometry.point(draft.get("size"),true) or int(draft.size[0])>96 or int(draft.size[1])>96:
					_fail("房间原点或尺寸无效")
					return
			_phase = "collect"
		"collect":
			var total: int = draft.cells.size() if draft.has("cells") else int(draft.size[0])*int(draft.size[1])
			if _cursor>=total:
				_queue = [Vector2i(int(_actual[0][0]),int(_actual[0][1]))]
				_seen[_queue[0]] = true
				_cursor = 0
				_phase = "connected"
				return
			var cell: Variant = draft.cells[_cursor] if draft.has("cells") else [int(draft.origin[0])+_cursor%int(draft.size[0]),int(draft.origin[1])+_cursor/int(draft.size[0])]
			_cursor += 1
			if not BuildGeometry.point(cell) or int(cell[0])<0 or int(cell[0])>=96 or int(cell[1])<0 or int(cell[1])>=96:
				_fail("房间内格超出本层96×96范围")
				return
			var position: Vector2i = Vector2i(int(cell[0]),int(cell[1]))
			if _occupied.has(position):
				_fail("房间内格重复")
				return
			_actual.append([position.x,position.y])
			_occupied[position] = true
			_low = _low.min(position)
			_high = _high.max(position)
		"connected":
			if _cursor>=_queue.size():
				if _seen.size()!=_actual.size():
					_fail("房间内格必须四邻连续")
					return
				_seen = {_low-Vector2i.ONE:true}
				_queue = [_low-Vector2i.ONE]
				_cursor = 0
				_phase = "outside"
				return
			_flood_unit(true,_low,_high)
		"outside":
			if _cursor>=_queue.size():
				_cursor = 0
				_phase = "holes"
				return
			_flood_unit(false,_low-Vector2i.ONE,_high+Vector2i.ONE)
		"holes":
			var width: int = _high.x-_low.x+1
			if _cursor>=width*(_high.y-_low.y+1):
				_cursor = 0
				_phase = "minimum"
				return
			var point: Vector2i = Vector2i(_low.x+_cursor%width,_low.y+_cursor/width)
			_cursor += 1
			if not _occupied.has(point) and not _seen.has(point):
				_fail("房间不能包含内部孔洞")
		"minimum":
			if _cursor>=_actual.size():
				_fail("房型需要至少%d×%d的完整内接矩形" % [int(_minimum[0]),int(_minimum[1])])
				return
			var point: Vector2i = Vector2i(int(_actual[_cursor][0]),int(_actual[_cursor][1]))
			_cursor += 1
			if BuildGeometry._rectangle_inside(_occupied,point,Vector2i(int(_minimum[0]),int(_minimum[1]))) or BuildGeometry._rectangle_inside(_occupied,point,Vector2i(int(_minimum[1]),int(_minimum[0]))):
				_actual.sort_custom(func(a: Array,b: Array) -> bool: return a[1]<b[1] or (a[1]==b[1] and a[0]<b[0]))
				_shape = {"ok":true,"cells":_actual,"origin":[_low.x,_low.y],"size":[_high.x-_low.x+1,_high.y-_low.y+1],"wall_edges":BuildGeometry.walls(_occupied)}
				_phase = "prepare"
		"prepare":
			_plan = service.prepare_preview(world,kind,draft,_shape)
			if not _plan.ok:
				_finish(_plan,world)
				return
			_candidate = _plan.candidate
			_source = service._scratch(world)
			dependency_key = dependencies(world)
			var ignored: Array = []
			for id: String in _plan.changed_ids:
				if _candidate.facts.facilities.has(id):
					ignored.append(id)
			for id: String in _plan.changed_ids:
				if _candidate.facts.rooms.has(id):
					var room: Dictionary = _candidate.facts.rooms[id]
					for cell: Array in BuildGeometry.cells(room):
						_room_checks.append({"room_id":id,"floor_id":int(room.floor_id),"cell":cell,"ignored":ignored})
				if _candidate.facts.facilities.has(id):
					_facility_checks.append(id)
			for room: Dictionary in _candidate.facts.rooms.values():
				if int(room.floor_id) in _plan.floors and room.has("cells"):
					_public_checks.append(room.id)
			for actor: Dictionary in _candidate.facts.actors.values():
				if actor.location.kind=="floor" and int(actor.location.floor_id) in _plan.floors:
					_actor_checks.append(actor.id)
			_cursor = 0
			_phase = "room_occupancy"
		"room_occupancy":
			if _cursor>=_room_checks.size():
				_cursor = 0
				_phase = "facility_occupancy"
				return
			var check: Dictionary = _room_checks[_cursor]
			_cursor += 1
			var collision: Dictionary = BuildGeometry.occupied_error(_source,service.space,check.floor_id,[Rect2(float(check.cell[0]),float(check.cell[1]),1,1)],check.ignored)
			if not collision.ok:
				_finish(collision,world)
				return
			for other: Dictionary in _candidate.facts.rooms.values():
				if other.id!=check.room_id and int(other.floor_id)==int(check.floor_id) and BuildGeometry.contains(other,check.cell):
					_fail("房间内格与实际房间重叠")
					return
		"facility_occupancy":
			if _cursor>=_facility_checks.size():
				_cursor = 0
				_phase = "public_access"
				return
			var id: String = _facility_checks[_cursor]
			_cursor += 1
			var positioned: Dictionary = service._facility_position(_candidate,_candidate.facts.facilities[id],[id])
			if not positioned.ok:
				_finish(positioned,world)
		"public_access":
			if _cursor>=_public_checks.size():
				_cursor = 0
				_phase = "actor_safety"
				return
			var id: String = _public_checks[_cursor]
			_cursor += 1
			var reason: String = service._public_door(_candidate,_candidate.facts.rooms[id])
			if not reason.is_empty():
				_fail(reason)
		"actor_safety":
			if _cursor>=_actor_checks.size():
				_finish(_plan,world)
				return
			var id: String = _actor_checks[_cursor]
			_cursor += 1
			var safety: Dictionary = service.actor_safety(_source,_candidate,_candidate.facts.actors[id])
			if not safety.ok:
				_finish(safety,world)

func _flood_unit(filled: bool, low: Vector2i, high: Vector2i) -> void:
	var current: Vector2i = _queue[_cursor]
	_cursor += 1
	for direction: Vector2i in BuildGeometry.DIRECTIONS:
		var next: Vector2i = current+direction
		if next.x<low.x or next.x>high.x or next.y<low.y or next.y>high.y or _seen.has(next) or _occupied.has(next)!=filled:
			continue
		_seen[next] = true
		_queue.append(next)

func _finish(value: Dictionary, world: WorldState) -> void:
	result = value.duplicate()
	result.erase("candidate")
	result.ready = bool(result.ok)
	if result.ok:
		result.world_revision = world.revision
		result.balance_after = HospitalLedger.balance(world)-int(result.price)+int(result.refund)
		result.quote = {"kind":kind,"price":result.price,"refund":result.refund,"targets":service._target_basis(world,kind,draft)}
		result.draft = draft.duplicate(true)
	complete = true

func _fail(reason: String) -> void:
	result = BuildGeometry.failure(reason)
	result.ready = false
	complete = true

func _fields(record: Dictionary, names: Array) -> Dictionary:
	var selected: Dictionary = {}
	for name: String in names:
		if record.has(name):
			selected[name] = record[name]
	return selected
