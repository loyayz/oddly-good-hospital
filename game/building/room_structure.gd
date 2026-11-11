extends RefCounted

# Walls and directed doors own structure. Rooms retain only the resulting
# interior, chosen purpose and opening intention; recognition runs on edits.
const DIRS: Array[Vector2i] = [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN]

static func key(axis: String, line: int, along: int) -> String:
	return "%s:%d:%d" % [axis,line,along]

static func units(edges: Array) -> Dictionary:
	var result: Dictionary = {}
	for edge: Dictionary in edges:
		for along: int in range(int(edge.low),int(edge.high)):
			result[key(edge.axis,int(edge.line),along)] = {"axis":edge.axis,"line":int(edge.line),"low":along,"high":along+1}
	return result

static func edges(pieces: Dictionary) -> Array:
	var groups: Dictionary = {}
	for edge: Dictionary in pieces.values():
		var line_key: String = str(edge.axis)+":"+str(edge.line)
		groups.get_or_add(line_key,[]).append(int(edge.low))
	var result: Array = []
	var lines: Array = groups.keys()
	lines.sort()
	for line_key: String in lines:
		var positions: Array = groups[line_key]
		positions.sort()
		var parts: PackedStringArray = line_key.split(":")
		var start: int = int(positions[0])
		var end: int = start+1
		for along: int in positions.slice(1):
			if along==end: end += 1
			else:
				result.append({"axis":parts[0],"line":int(parts[1]),"low":start,"high":end})
				start = along
				end = along+1
		result.append({"axis":parts[0],"line":int(parts[1]),"low":start,"high":end})
	return result

static func door_sides(door: Dictionary, offset: int = 0) -> Array[Vector2i]:
	var along: int = int(door.cell[0] if door.axis=="x" else door.cell[1])+offset
	var line: int = int(door.cell[1] if door.axis=="x" else door.cell[0])
	var before: Vector2i = Vector2i(along,line-1) if door.axis=="x" else Vector2i(line-1,along)
	var after: Vector2i = Vector2i(along,line) if door.axis=="x" else Vector2i(line,along)
	var result: Array[Vector2i] = []
	result.append(after if int(door.get("interior_side",-1))>0 else before)
	result.append(before if int(door.get("interior_side",-1))>0 else after)
	return result

static func seeds(changed: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for edge: Dictionary in changed:
		for along: int in range(int(edge.low),int(edge.high)):
			var before: Vector2i = Vector2i(along,int(edge.line)-1) if edge.axis=="x" else Vector2i(int(edge.line)-1,along)
			var after: Vector2i = before+(Vector2i.DOWN if edge.axis=="x" else Vector2i.RIGHT)
			if not before in result: result.append(before)
			if not after in result: result.append(after)
	return result

static func owned(plots: Dictionary, point: Vector2i) -> bool:
	return point.x>=0 and point.y>=0 and point.x<96 and point.y<96 and plots.has(Vector2i(point.x/32,point.y/32))

static func edge_key(first: Vector2i, second: Vector2i) -> String:
	if first.y!=second.y: return key("x",maxi(first.y,second.y),first.x)
	return key("y",maxi(first.x,second.x),first.y)

static func _component(start: Vector2i, plots: Dictionary, barriers: Dictionary, visited: Dictionary) -> Dictionary:
	var pending: Array[Vector2i] = [start]
	var cursor: int = 0
	var points: Dictionary = {start:true}
	var closed: bool = true
	visited[start] = true
	while cursor<pending.size():
		var point: Vector2i = pending[cursor]
		cursor += 1
		for direction: Vector2i in DIRS:
			var next: Vector2i = point+direction
			if barriers.has(edge_key(point,next)): continue
			if not owned(plots,next):
				closed = false
				continue
			if not points.has(next):
				points[next] = true
				visited[next] = true
				pending.append(next)
	var cells: Array = []
	for point: Vector2i in pending: cells.append([point.x,point.y])
	cells.sort_custom(func(a: Array,b: Array)->bool: return a[1]<b[1] or a[1]==b[1] and a[0]<b[0])
	return {"cells":cells,"points":points,"closed":closed,"doors":[]}

static func reconcile(world: WorldState, floor_id: int, starts: Array[Vector2i], protected_facilities: Dictionary = {}, requested: Dictionary = {}) -> Array:
	var layout: Dictionary = world.facts.floors.overrides[str(floor_id)]
	var barriers: Dictionary = units(layout.get("wall_edges",[]))
	for door: Dictionary in layout.doors:
		for offset: int in int(door.span):
			var along: int = int(door.cell[0] if door.axis=="x" else door.cell[1])+offset
			barriers[key(door.axis,int(door.cell[1] if door.axis=="x" else door.cell[0]),along)] = true
	var plots: Dictionary = {}
	for plot: Array in HospitalSpace.floor_plots(world,floor_id): plots[Vector2i(int(plot[0]),int(plot[1]))] = true
	var visited: Dictionary = {}
	var components: Array = []
	for start: Vector2i in starts:
		if owned(plots,start) and not visited.has(start): components.append(_component(start,plots,barriers,visited))
	for component: Dictionary in components:
		if not component.closed: continue
		for door: Dictionary in layout.doors:
			var inside: bool = true
			var facing_away: bool = false
			for offset: int in int(door.span):
				var sides: Array[Vector2i] = door_sides(door,offset)
				if component.points.has(sides[1]) and not component.points.has(sides[0]): facing_away = true
				if not component.points.has(sides[0]) or component.points.has(sides[1]) or not owned(plots,sides[1]): inside = false
			if facing_away: component.closed = false
			if inside: component.doors.append(door.id)
	var affected: Dictionary = {}
	for room: Dictionary in world.facts.rooms.values():
		if int(room.floor_id)!=floor_id or not room.get("structure_valid",true): continue
		for cell: Array in BuildGeometry.cells(room):
			if visited.has(Vector2i(int(cell[0]),int(cell[1]))):
				affected[room.id] = room
				break
	var next_rooms: Dictionary = {}
	for component: Dictionary in components:
		if not component.closed or component.doors.is_empty(): continue
		var shape: Dictionary = BuildGeometry.shape({"cells":component.cells},[1,1])
		if not shape.ok: continue
		var room: Dictionary = {}
		for previous: Dictionary in affected.values():
			if BuildGeometry.cells(previous)==shape.cells:
				room = previous
				break
		if room.is_empty():
			var id: String = str(requested.get("id","")) if requested.get("cells",[])==shape.cells else ""
			if id.is_empty(): id = world.new_id("room")
			room = {"id":id,"kind":"","floor_id":floor_id,"origin":shape.origin,"size":shape.size,"cells":shape.cells,"open_intent":true,"paid_cost":0,"used":false,"ownership":"purchased"}
		room.structure_valid = true
		# Boundary edges are derived only for existing geometric consumers; the
		# independent floor wall source alone determines collision and formation.
		room.wall_edges = shape.wall_edges
		next_rooms[room.id] = room
	var changed: Array = []
	for id: String in affected:
		if next_rooms.has(id): continue
		var retained: bool = false
		for facility: Dictionary in world.facts.facilities.values():
			if facility.get("room_id","")==id and protected_facilities.has(facility.id): retained = true
		if retained:
			world.facts.rooms[id].structure_valid = false
			world.facts.rooms[id].open_intent = false
			world.facts.rooms[id].kind = ""
			world.facts.rooms[id].erase("room_type_id")
		else: world.facts.rooms.erase(id)
		changed.append(id)
	for id: String in next_rooms:
		world.facts.rooms[id] = next_rooms[id]
		changed.append(id)
	for door: Dictionary in layout.doors:
		var sides: Array[Vector2i] = door_sides(door)
		if not visited.has(sides[0]) and not affected.has(door.get("room_id","")): continue
		door.room_id = ""
		for room: Dictionary in next_rooms.values():
			if [sides[0].x,sides[0].y] in room.cells:
				door.room_id = room.id
				break
	for facility: Dictionary in world.facts.facilities.values():
		if int(facility.floor_id)!=floor_id or protected_facilities.has(facility.id): continue
		var room_id: String = str(facility.get("room_id",""))
		if not room_id.is_empty() and not affected.has(room_id): continue
		facility.erase("room_id")
		for room: Dictionary in next_rooms.values():
			if BuildGeometry.intersects_room(BuildGeometry.rectangle(facility),room) and _facility_inside(facility,room):
				facility.room_id = room.id
				break
	return changed

static func _facility_inside(facility: Dictionary, room: Dictionary) -> bool:
	for y: int in range(int(facility.cell[1]),int(facility.cell[1])+int(facility.footprint[1])):
		for x: int in range(int(facility.cell[0]),int(facility.cell[0])+int(facility.footprint[0])):
			if not [x,y] in room.cells: return false
	return true

static func room_error(world: WorldState, room: Dictionary) -> String:
	var floor_id: int = int(room.floor_id)
	var layout: Dictionary = world.facts.floors.overrides[str(floor_id)]
	if not layout.has("wall_edges"): return ""
	var barriers: Dictionary = units(layout.wall_edges)
	var owned_doors: int = 0
	for door: Dictionary in layout.doors:
		var line: int = int(door.cell[1] if door.axis=="x" else door.cell[0])
		var low: int = int(door.cell[0] if door.axis=="x" else door.cell[1])
		for offset: int in int(door.span): barriers[key(door.axis,line,low+offset)] = true
		if door.room_id!=room.id: continue
		owned_doors += 1
		for offset: int in int(door.span):
			var sides: Array[Vector2i] = door_sides(door,offset)
			if not [sides[0].x,sides[0].y] in room.cells or [sides[1].x,sides[1].y] in room.cells: return "房门后侧未指向所属房间"
	if owned_doors==0: return "闭合空间没有合法房门"
	var plots: Dictionary = {}
	for plot: Array in HospitalSpace.floor_plots(world,floor_id): plots[Vector2i(int(plot[0]),int(plot[1]))] = true
	var component: Dictionary = _component(Vector2i(int(room.cells[0][0]),int(room.cells[0][1])),plots,barriers,{})
	if not component.closed or component.cells!=room.cells: return "房间内格与实际墙门闭合范围不符"
	return ""
