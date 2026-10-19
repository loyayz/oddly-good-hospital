class_name RouteClearance
extends RefCounted

# Immutable geometry for one floor and traversal envelope. Reservations are query-local.
var _size: int
var source: Dictionary
var _plots: Dictionary = {}
var _blocked: Dictionary = {}
var _doors: Array[Dictionary] = []
var _facilities: Array[Dictionary] = []
var _connectors: Array[Dictionary] = []
var _reservations: Array[Dictionary] = []
var _members: Array[Dictionary] = []
var _walls: Array[Dictionary] = []
var _dependencies: Dictionary = {}
var _plain: bool = false
var _height_m: float = 0.0
var _indexed_static: bool = false
var _facility_cells: Dictionary = {}
var _connector_cells: Dictionary = {}
var _open_door_cells: Dictionary = {}
var _closed_door_cells: Dictionary = {}
var _horizontal_walls: Dictionary = {}
var _vertical_walls: Dictionary = {}

# Only these original reservation exceptions change query-level clearance.
# Sorted facility identities preserve sharing between equally authorized actors.
static func reservation_exemptions(world: WorldState, actor_id: String, floor_id: int = 0) -> Array:
	var result: Array = []
	for id: String in world.ids("adaptations"):
		var reservation: Dictionary = world.facts.adaptations[id]
		if reservation.kind=="facility" and (floor_id==0 or int(reservation.floor_id)==floor_id) and reservation_allows(reservation,actor_id):
			result.append(id)
	return result

static func reservation_allows(reservation: Dictionary, actor_id: String, members: Array = []) -> bool:
	return actor_id==reservation.actor_id or actor_id in reservation.staff_ids or reservation.actor_id in members

func _init(space: HospitalSpace, world: WorldState, actor: Dictionary, floor_id: int, members: Array = [], offsets: Dictionary = {}, include_reservations: bool = true, floor_source: Dictionary = {}, static_geometry: RouteClearance = null) -> void:
	_indexed_static = not include_reservations
	_size = space.clearance(actor)
	var body: Dictionary = space.body(actor)
	_height_m = float(body.depth_m if actor.get("posture","standing")=="lying" else body.height_m)
	source = capture_source(space,world,floor_id) if floor_source.is_empty() else floor_source
	for member_id: String in members:
		if member_id!=actor.id:
			var offset: Array = offsets[member_id]
			_members.append({"query":RouteClearance.new(space,world,world.facts.actors[member_id],floor_id,[],{},include_reservations,source),"offset":Vector2(float(offset[0]),float(offset[1]))})
	if static_geometry==null:
		_build_static(space,world,actor,floor_id)
	else:
		# The graph owns immutable geometry for this complete body envelope.
		# Only reservations depend on the current actor's identity.
		_indexed_static = static_geometry._indexed_static
		for field: String in ["_plots","_blocked","_doors","_facilities","_connectors","_walls","_dependencies","_facility_cells","_connector_cells","_open_door_cells","_closed_door_cells","_horizontal_walls","_vertical_walls"]:
			set(field,static_geometry.get(field))
	if include_reservations:
		for reservation: Dictionary in world.facts.adaptations.values():
			if reservation.kind=="facility" and int(reservation.floor_id)==floor_id and not reservation_allows(reservation,actor.id,members):
				var regions: Array[Rect2] = []
				for area: Array in reservation.regions:
					regions.append(Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3])))
				_reservations.append({"regions":regions,"id":reservation.facility_id})
	_plain = _plain_geometry()

func _build_static(space: HospitalSpace, world: WorldState, actor: Dictionary, floor_id: int) -> void:
	var layout: Dictionary = source.layout
	for plot: Array in layout.get("plots",[]):
		var cell: Vector2i = Vector2i(int(plot[0]),int(plot[1]))
		_plots[cell] = true
		_dependencies["plot:"+str(cell)] = {"rect":Rect2i(cell*32,Vector2i(32,32)),"value":true}
		_dependencies["height:"+str(cell)] = {"rect":Rect2i(cell*32,Vector2i(32,32)),"value":source.height}
	for cell: Array in layout.get("blocked",[]):
		var point: Vector2i = Vector2i(int(cell[0]),int(cell[1]))
		_blocked[point] = true
		_dependencies["blocked:"+str(point)] = {"rect":Rect2i(point,Vector2i.ONE),"value":true}
	for door: Dictionary in layout.get("doors",[]):
		var fit: Dictionary = space.door_quote(world,actor,floor_id,door)
		var record: Dictionary = {"original":space._door_rect(door,int(door.span)),"opening":space._door_rect(door,int(fit.span)) if fit.ok else Rect2(),"ok":fit.ok,"reason":fit.get("reason",""),"room_id":door.room_id,"axis":door.axis}
		_doors.append(record)
		if _indexed_static:
			if record.ok: _index_rectangle(record.opening,_open_door_cells,true)
			else: _index_rectangle(record.original,_closed_door_cells,record.reason)
		_dependencies["door:"+str(door.id)] = {"rect":Rect2i(record.original.merge(record.opening)),"value":record}
	for id: String in source.facilities:
		var facility: Dictionary = source.facilities[id]
		var rect: Rect2i = Rect2i(int(facility.cell[0]),int(facility.cell[1]),int(facility.footprint[0]),int(facility.footprint[1]))
		_facilities.append({"rect":rect,"id":id})
		if _indexed_static: _index_rectangle(Rect2(rect),_facility_cells,id)
		_dependencies["facility:"+id] = {"rect":rect,"value":facility}
	for id: String in source.connectors:
		var connector: Dictionary = source.connectors[id]
		var rect: Rect2i = Rect2i(int(connector.cell[0]),int(connector.cell[1]),int(connector.footprint[0]),int(connector.footprint[1]))
		_connectors.append({"rect":rect,"id":id})
		if _indexed_static: _index_rectangle(Rect2(rect),_connector_cells,id)
		_dependencies["connector:"+id] = {"rect":rect,"value":connector}
	for id: String in source.rooms:
		var room: Dictionary = source.rooms[id]
		var rect: Rect2i = Rect2i(int(room.origin[0]),int(room.origin[1]),int(room.size[0]),int(room.size[1]))
		_dependencies["room:"+id] = {"rect":rect.grow(1),"value":room}
		if room.has("wall_edges"):
			for edge: Dictionary in room.wall_edges:
				_walls.append({"room_id":id,"axis":edge.axis,"line":edge.line,"low":edge.low,"high":edge.high})
			continue
		for y: int in [rect.position.y,rect.end.y]:
			_walls.append({"room_id":id,"axis":"x","line":y,"low":rect.position.x,"high":rect.end.x})
		for x: int in [rect.position.x,rect.end.x]:
			_walls.append({"room_id":id,"axis":"y","line":x,"low":rect.position.y,"high":rect.end.y})
	if _indexed_static:
		for wall: Dictionary in _walls:
			var lines: Dictionary = _horizontal_walls if wall.axis=="x" else _vertical_walls
			var line: int = int(wall.line)
			if not lines.has(line): lines[line] = []
			lines[line].append(wall)

func _plain_geometry() -> bool:
	return _members.is_empty() and _blocked.is_empty() and _doors.is_empty() and _facilities.is_empty() and _connectors.is_empty() and _reservations.is_empty() and _walls.is_empty()

func _index_rectangle(rect: Rect2, cells: Dictionary, value: Variant) -> void:
	for y: int in range(maxi(0,ceili(rect.position.y)),mini(FloorNavigation.SIDE,ceili(rect.end.y))):
		for x: int in range(maxi(0,ceili(rect.position.x)),mini(FloorNavigation.SIDE,ceili(rect.end.x))):
			var cell: Vector2i = Vector2i(x,y)
			if not cells.has(cell): cells[cell] = value

func reason(origin: Vector2i) -> String:
	if _height_m>float(source.height):
		return "真实身体超过本层实际净高"
	for member: Dictionary in _members:
		var result: String = member.query.position_reason(Vector2(origin)+member.offset)
		if not result.is_empty():
			return result
	if _plain:
		for x: int in range(floori(float(origin.x)/32.0),floori(float(origin.x+_size-1)/32.0)+1):
			for y: int in range(floori(float(origin.y)/32.0),floori(float(origin.y+_size-1)/32.0)+1):
				if not _plots.has(Vector2i(x,y)):
					return "身体超出已取得地块"
		return ""
	for x: int in range(origin.x,origin.x+_size):
		for y: int in range(origin.y,origin.y+_size):
			var cell: Vector2i = Vector2i(x,y)
			var point: Vector2 = Vector2(cell)
			if not _plots.has(Vector2i(floori(float(x)/32.0),floori(float(y)/32.0))):
				return "身体超出已取得地块"
			if _blocked.has(cell):
				var opening: bool = _open_door_cells.has(cell) if _indexed_static else false
				if not _indexed_static:
					for door: Dictionary in _doors:
						if door.ok and door.opening.has_point(point):
							opening = true
							break
				if not opening:
					return "通路不足%d格" % _size
			if _indexed_static:
				if _closed_door_cells.has(cell): return str(_closed_door_cells[cell])
				if _facility_cells.has(cell): return "设备真实占地受阻："+str(_facility_cells[cell])
				if _connector_cells.has(cell): return "竖向结构真实占地受阻："+str(_connector_cells[cell])
			else:
				for door: Dictionary in _doors:
					if door.original.has_point(point) and not door.ok:
						return door.reason
				for facility: Dictionary in _facilities:
					if facility.rect.has_point(cell):
						return "设备真实占地受阻："+str(facility.id)
				for connector: Dictionary in _connectors:
					if connector.rect.has_point(cell):
						return "竖向结构真实占地受阻："+str(connector.id)
			for reservation: Dictionary in _reservations:
				for region: Rect2 in reservation.regions:
					if region.has_point(point):
						return "真实展开与岗位预约阻挡："+str(reservation.id)
	return _wall_reason(Rect2(Vector2(origin),Vector2.ONE*_size))

func edge_reason(from: Vector2i, to: Vector2i) -> String:
	for member: Dictionary in _members:
		var reason: String = member.query.sweep_reason(Vector2(from)+member.offset,Vector2(to)+member.offset)
		if not reason.is_empty():
			return reason
	return _wall_reason(Rect2(Vector2(from),Vector2.ONE*_size).merge(Rect2(Vector2(to),Vector2.ONE*_size)))

func position_reason(origin: Vector2) -> String:
	for y: int in range(floori(origin.y),ceili(origin.y)+1):
		for x: int in range(floori(origin.x),ceili(origin.x)+1):
			var result: String = reason(Vector2i(x,y))
			if not result.is_empty():
				return result
	return ""

func sweep_reason(from: Vector2, to: Vector2) -> String:
	if _height_m>float(source.height):
		return "真实身体超过本层实际净高"
	if _plain:
		var low: Vector2i = Vector2i(floori(minf(from.x,to.x)/32.0),floori(minf(from.y,to.y)/32.0))
		var high: Vector2i = Vector2i(floori(float(ceili(maxf(from.x,to.x))+_size-1)/32.0),floori(float(ceili(maxf(from.y,to.y))+_size-1)/32.0))
		for x: int in range(low.x,high.x+1):
			for y: int in range(low.y,high.y+1):
				if not _plots.has(Vector2i(x,y)):
					return "身体超出已取得地块"
		return ""
	for y: int in range(floori(minf(from.y,to.y)),ceili(maxf(from.y,to.y))+1):
		for x: int in range(floori(minf(from.x,to.x)),ceili(maxf(from.x,to.x))+1):
			var result: String = reason(Vector2i(x,y))
			if not result.is_empty():
				return result
	for member: Dictionary in _members:
		var result: String = member.query.sweep_reason(from+member.offset,to+member.offset)
		if not result.is_empty():
			return result
	return _wall_reason(Rect2(from,Vector2.ONE*_size).merge(Rect2(to,Vector2.ONE*_size)))

func reservation_reason(origin: Vector2i) -> String:
	return _reservation_at(Vector2(origin))

func has_reservations() -> bool:
	if not _reservations.is_empty():
		return true
	for member: Dictionary in _members:
		if member.query.has_reservations():
			return true
	return false

# A distance field visits thousands of integer origins. Resolve the already
# authorized reservation rectangles once, retaining exact strict intersections.
# Group members constructed by _init have their own single-body queries.
func reservation_mask() -> PackedByteArray:
	var mask: PackedByteArray = PackedByteArray()
	if not has_reservations(): return mask
	mask.resize(FloorNavigation.LIMIT)
	mask.fill(0)
	mask = _mark_reservation_mask(mask,Vector2.ZERO)
	for member: Dictionary in _members:
		mask = member.query._mark_reservation_mask(mask,member.offset)
	return mask

func _mark_reservation_mask(mask: PackedByteArray, offset: Vector2) -> PackedByteArray:
	for reservation: Dictionary in _reservations:
		for region: Rect2 in reservation.regions:
			# Pad the candidate bounds, then use the original Rect2 predicate.
			# This also preserves float rounding at fractional member offsets.
			var low: Vector2i = Vector2i(maxi(0,floori(region.position.x-offset.x-_size)-1),maxi(0,floori(region.position.y-offset.y-_size)-1))
			var high: Vector2i = Vector2i(mini(FloorNavigation.SIDE,ceili(region.end.x-offset.x)+1),mini(FloorNavigation.SIDE,ceili(region.end.y-offset.y)+1))
			for y: int in range(low.y,high.y):
				for x: int in range(low.x,high.x):
					var id: int = FloorNavigation._id(Vector2i(x,y))
					if mask[id]==0 and Rect2(Vector2(x,y)+offset,Vector2.ONE*_size).intersects(region,false): mask[id] = 1
	return mask

func _reservation_at(origin: Vector2) -> String:
	for member: Dictionary in _members:
		var reason: String = member.query._reservation_at(origin+member.offset)
		if not reason.is_empty():
			return reason
	var footprint: Rect2 = Rect2(origin,Vector2.ONE*_size)
	for reservation: Dictionary in _reservations:
		for rect: Rect2 in reservation.regions:
			if footprint.intersects(rect,false):
				return "真实展开与岗位预约阻挡："+str(reservation.id)
	return ""

func _wall_reason(rect: Rect2) -> String:
	var walls: Array = _walls
	if _indexed_static:
		walls = []
		for line: int in range(floori(rect.position.y)+1,ceili(rect.end.y)):
			walls.append_array(_horizontal_walls.get(line,[]))
		for line: int in range(floori(rect.position.x)+1,ceili(rect.end.x)):
			walls.append_array(_vertical_walls.get(line,[]))
	for wall: Dictionary in walls:
		var low: float = maxf(rect.position.x if wall.axis=="x" else rect.position.y,float(wall.low))
		var high: float = minf(rect.end.x if wall.axis=="x" else rect.end.y,float(wall.high))
		var before: float = rect.position.y if wall.axis=="x" else rect.position.x
		var after: float = rect.end.y if wall.axis=="x" else rect.end.x
		if low>=high or before>=float(wall.line) or after<=float(wall.line):
			continue
		var opening: bool = false
		for door: Dictionary in _doors:
			if door.room_id!=wall.room_id or door.axis!=wall.axis or not door.ok:
				continue
			var line: float = door.opening.position.y if wall.axis=="x" else door.opening.position.x
			var a: float = door.opening.position.x if wall.axis=="x" else door.opening.position.y
			var b: float = door.opening.end.x if wall.axis=="x" else door.opening.end.y
			if line==float(wall.line) and a<=low and b>=high:
				opening = true
				break
		if not opening:
			return "房间墙边阻挡真实身体"
	return ""

func dirty_regions(previous: RouteClearance) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	var reach: int = maxi(_size,previous._size)+1
	for member: Dictionary in _members:
		reach = maxi(reach,member.query._size+ceili(absf(member.offset.x)+absf(member.offset.y))+1)
	var keys: Dictionary = previous._dependencies.duplicate()
	keys.merge(_dependencies,true)
	for key: String in keys:
		var old: Dictionary = previous._dependencies.get(key,{})
		var current: Dictionary = _dependencies.get(key,{})
		if old==current:
			continue
		if not old.is_empty():
			result.append((old.rect as Rect2i).grow(reach))
		if not current.is_empty():
			result.append((current.rect as Rect2i).grow(reach))
	for index: int in mini(_members.size(),previous._members.size()):
		for region: Rect2i in _members[index].query.dirty_regions(previous._members[index].query):
			var offset: Vector2 = _members[index].offset
			result.append(Rect2i(region.position-Vector2i(ceili(offset.x),ceili(offset.y)),region.size).grow(1))
	return result

static func capture_source(space: HospitalSpace, world: WorldState, floor_id: int) -> Dictionary:
	var layout: Dictionary = HospitalSpace.floor_layout(world,floor_id)
	var source_layout: Dictionary = {"plots":layout.get("plots",[]).duplicate(true),"blocked":layout.get("blocked",[]).duplicate(true),"doors":[]}
	for door: Dictionary in layout.get("doors",[]):
		var shape: Dictionary = {}
		for field: String in ["id","definition_id","cell","span","axis","room_id"]:
			shape[field] = door[field].duplicate() if door[field] is Array else door[field]
		source_layout.doors.append(shape)
	var result: Dictionary = {"layout":source_layout,"rooms":{},"facilities":{},"connectors":{},"height":0.0,"door_height":float(space.content.balance.floors.clear_height_m) if world.facts.floors.has("completed_top_floor") and not layout.plots.is_empty() else 0.0,"occupancy":[]}
	for id: String in world.ids("rooms"):
		var room: Dictionary = world.facts.rooms[id]
		if int(room.floor_id)==floor_id:
			result.rooms[id] = {"origin":room.origin.duplicate(),"size":room.size.duplicate()}
			for field: String in ["cells","wall_edges"]:
				if room.has(field):
					result.rooms[id][field] = room[field].duplicate(true)
	for id: String in world.ids("facilities"):
		var facility: Dictionary = world.facts.facilities[id]
		if int(facility.floor_id)==floor_id and space.content.facility_definition(facility.definition_id).get("blocks_movement",true):
			var footprint: Array = world.facts.adaptations.get(id,{}).get("footprint",facility.footprint)
			result.facilities[id] = {"cell":facility.cell.duplicate(),"footprint":footprint.duplicate()}
	for id: String in world.ids("connectors"):
		var connector: Dictionary = world.facts.connectors[id]
		if HospitalTransit.has_stop(connector,floor_id):
			result.connectors[id] = {"cell":connector.cell.duplicate(),"footprint":connector.footprint.duplicate()}
	for interval: Dictionary in world.facts.floors.height_intervals:
		if floor_id>=int(interval.first) and floor_id<=int(interval.last):
			result.height = interval.height_m
			result.door_height = interval.height_m
	if world.facts.floors.has("completed_top_floor") and not layout.plots.is_empty():
		result.height = float(space.content.balance.floors.clear_height_m)
	result.occupancy = capture_occupancy(world,floor_id)
	return result

static func capture_occupancy(world: WorldState, floor_id: int) -> Array:
	var result: Array = []
	for id: String in world.ids("adaptations"):
		var reservation: Dictionary = world.facts.adaptations[id]
		if reservation.kind=="facility" and int(reservation.floor_id)==floor_id:
			result.append([id,reservation.actor_id,reservation.get("staff_ids",[]).duplicate(),reservation.regions.duplicate(true)])
	return result
