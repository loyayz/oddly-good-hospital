class_name BuildGeometry
extends RefCounted

const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN]

static func point(value: Variant, positive: bool = false) -> bool:
	if not value is Array or value.size()!=2:
		return false
	for number: Variant in value:
		if not (number is int or number is float) or not is_finite(float(number)) or float(number)!=floorf(float(number)) or absf(float(number))>100000:
			return false
		if positive and int(number)<=0:
			return false
	return true

static func cells(room: Dictionary) -> Array:
	if room.has("cells"):
		return room.cells
	var result: Array = []
	for y: int in range(int(room.origin[1]),int(room.origin[1])+int(room.size[1])):
		for x: int in range(int(room.origin[0]),int(room.origin[0])+int(room.size[0])):
			result.append([x,y])
	return result

static func room_walls(room: Dictionary) -> Array:
	if room.has("wall_edges"):
		return room.wall_edges
	var occupied: Dictionary = {}
	for cell: Array in cells(room):
		occupied[Vector2i(int(cell[0]),int(cell[1]))] = true
	return walls(occupied)

static func shape(draft: Dictionary, minimum: Array) -> Dictionary:
	var actual: Array = []
	if draft.has("cells"):
		if not draft.cells is Array or draft.cells.is_empty() or draft.cells.size()>9216:
			return failure("房间需要1至9216个实际内格")
		actual = draft.cells.duplicate(true)
	else:
		if not point(draft.get("origin")) or not point(draft.get("size"),true):
			return failure("房间原点或尺寸无效")
		if int(draft.size[0])>96 or int(draft.size[1])>96:
			return failure("房间超出96格院区")
		actual = cells(draft)
	var occupied: Dictionary = {}
	var low: Vector2i = Vector2i(96,96)
	var high: Vector2i = Vector2i(-1,-1)
	for cell: Variant in actual:
		if not point(cell) or int(cell[0])<0 or int(cell[1])<0 or int(cell[0])>=96 or int(cell[1])>=96:
			return failure("房间内格超出本层96×96范围",[cell] if cell is Array else [])
		var position: Vector2i = Vector2i(int(cell[0]),int(cell[1]))
		if occupied.has(position):
			return failure("房间内格重复",[cell])
		occupied[position] = true
		low = low.min(position)
		high = high.max(position)
	var visited: Dictionary = _flood(occupied,Vector2i(int(actual[0][0]),int(actual[0][1])),true,low,high)
	if visited.size()!=actual.size():
		return failure("房间内格必须四邻连续")
	var outside: Dictionary = _flood(occupied,low-Vector2i.ONE,false,low-Vector2i.ONE,high+Vector2i.ONE)
	for y: int in range(low.y,high.y+1):
		for x: int in range(low.x,high.x+1):
			if not occupied.has(Vector2i(x,y)) and not outside.has(Vector2i(x,y)):
				return failure("房间不能包含内部孔洞",[[x,y]])
	var fits: bool = false
	for origin: Vector2i in occupied:
		if _rectangle_inside(occupied,origin,Vector2i(int(minimum[0]),int(minimum[1]))) or _rectangle_inside(occupied,origin,Vector2i(int(minimum[1]),int(minimum[0]))):
			fits = true
			break
	if not fits:
		return failure("房型需要至少%d×%d的完整内接矩形" % [int(minimum[0]),int(minimum[1])])
	actual.sort_custom(func(a: Array,b: Array) -> bool: return a[1]<b[1] or (a[1]==b[1] and a[0]<b[0]))
	return {"ok":true,"cells":actual,"origin":[low.x,low.y],"size":[high.x-low.x+1,high.y-low.y+1],"wall_edges":walls(occupied)}

static func _rectangle_inside(occupied: Dictionary, origin: Vector2i, dimensions: Vector2i) -> bool:
	for y: int in range(origin.y,origin.y+dimensions.y):
		for x: int in range(origin.x,origin.x+dimensions.x):
			if not occupied.has(Vector2i(x,y)):
				return false
	return true

static func _flood(occupied: Dictionary, start: Vector2i, filled: bool, low: Vector2i, high: Vector2i) -> Dictionary:
	var seen: Dictionary = {start:true}
	var queue: Array[Vector2i] = [start]
	var cursor: int = 0
	while cursor<queue.size():
		var current: Vector2i = queue[cursor]
		cursor += 1
		for direction: Vector2i in DIRECTIONS:
			var next: Vector2i = current+direction
			if next.x<low.x or next.x>high.x or next.y<low.y or next.y>high.y or seen.has(next) or occupied.has(next)!=filled:
				continue
			seen[next] = true
			queue.append(next)
	return seen

static func walls(occupied: Dictionary) -> Array:
	var pieces: Dictionary = {}
	for p: Vector2i in occupied:
		for side: int in 4:
			var direction: Vector2i = DIRECTIONS[side]
			if occupied.has(p+direction):
				continue
			var axis: String = "x" if direction.y!=0 else "y"
			var line: int = p.y+(1 if direction.y>0 else 0) if axis=="x" else p.x+(1 if direction.x>0 else 0)
			var key: String = axis+":"+str(line)
			if not pieces.has(key):
				pieces[key] = {"axis":axis,"line":line,"points":[]}
			pieces[key].points.append(p.x if axis=="x" else p.y)
	var result: Array = []
	var keys: Array = pieces.keys()
	keys.sort()
	for key: String in keys:
		var piece: Dictionary = pieces[key]
		piece.points.sort()
		var start: int = piece.points[0]
		var end: int = start+1
		for position: int in piece.points.slice(1):
			if position==end:
				end += 1
			else:
				result.append({"axis":piece.axis,"line":piece.line,"low":start,"high":end})
				start = position
				end = position+1
		result.append({"axis":piece.axis,"line":piece.line,"low":start,"high":end})
	return result

static func contains(room: Dictionary, cell: Array) -> bool:
	return cell in cells(room)

static func rectangle(record: Dictionary) -> Rect2:
	return Rect2(float(record.cell[0]),float(record.cell[1]),float(record.footprint[0]),float(record.footprint[1]))

static func intersects_cells(rect: Rect2, inner: Array) -> bool:
	for cell: Array in inner:
		if rect.intersects(Rect2(float(cell[0]),float(cell[1]),1,1),false):
			return true
	return false

static func occupied_error(world: WorldState, space: HospitalSpace, floor_id: int, rects: Array, ignored_ids: Array = []) -> Dictionary:
	for rect: Rect2 in rects:
		for x: int in range(floori(rect.position.x),ceili(rect.end.x)):
			for y: int in range(floori(rect.position.y),ceili(rect.end.y)):
				if not space.owned(world,floor_id,Vector2i(x,y)):
					return failure("占地未购入或楼板尚未完成",[[x,y]])
				if [x,y] in world.facts.floors.overrides[str(floor_id)].get("blocked",[]):
					return failure("占地有真实结构阻挡",[[x,y]])
		if floor_id==1 and rect.intersects(Rect2(47,93,3,3),false):
			return failure("入口3×3缓冲区和南侧安全出口必须保留",[[47,93]])
		for actor: Dictionary in world.facts.actors.values():
			if actor.location.kind=="floor" and int(actor.location.floor_id)==floor_id and rect.intersects(space.body_rectangle(actor),false):
				return failure("占地有实际身体："+str(actor.id),[actor.location.cell])
		for facility: Dictionary in world.facts.facilities.values():
			if int(facility.floor_id)==floor_id and not facility.id in ignored_ids and rect.intersects(rectangle(space.facility_layout(world,facility.id).merged({"cell":facility.cell})),false):
				return failure("占地有实际设施："+str(facility.id),[facility.cell])
		for connector: Dictionary in world.facts.connectors.values():
			if floor_id in connector.get("stops",[]) and connector.has("cell") and rect.intersects(rectangle(connector),false):
				return failure("占地有真实竖向结构："+str(connector.id),[connector.cell])
		for reservation: Dictionary in world.facts.adaptations.values():
			if int(reservation.floor_id)!=floor_id:
				continue
			for area: Array in reservation.regions:
				if rect.intersects(Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3])),false):
					return failure("占地有尚未释放的真实身体或岗位预约",[[area[0],area[1]]])
		for collection: String in ["dirt_patches","dirt"]:
			for patch: Dictionary in world.facts.get(collection,{}).values():
				if int(patch.get("floor_id",1))==floor_id and patch.has("cell") and rect.has_point(Vector2(float(patch.cell[0]),float(patch.cell[1]))):
					return failure("占地有尚未清洁的真实垃圾："+str(patch.get("id","")),[patch.cell])
		for patch: Dictionary in world.facts.get("environment",{}).get("dirt",{}).values():
			if int(patch.get("floor_id",1))==floor_id and str(patch.get("bin_id","")).is_empty() and rect.has_point(Vector2(float(patch.cell[0]),float(patch.cell[1]))):
				return failure("占地有尚未清洁的真实垃圾："+str(patch.get("id","")),[patch.cell])
	return {"ok":true}

static func failure(reason: String, blocked: Array = []) -> Dictionary:
	return {"ok":false,"reason":reason,"blocked_cells":blocked}
