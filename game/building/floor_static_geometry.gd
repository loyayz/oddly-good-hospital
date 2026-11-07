class_name FloorStaticGeometry
extends RefCounted

# Complete immutable, body-independent geometry for a single floor. Actor door
# fitting, reservations, occupancy and A* graphs are deliberately not in here.
var source: Dictionary
var _plots: Dictionary = {}
var _blocked: Dictionary = {}
var _facilities: Array[Dictionary] = []
var _connectors: Array[Dictionary] = []
var _walls: Array[Dictionary] = []
var _dependencies: Dictionary = {}
var _facility_cells: Dictionary = {}
var _connector_cells: Dictionary = {}
var _horizontal_walls: Dictionary = {}
var _vertical_walls: Dictionary = {}
var doors: Array[Dictionary] = []
var door_order: Dictionary = {}
var door_index: BodyIndex = BodyIndex.new()
var facility_index: BodyIndex = BodyIndex.new()
var charge: int = 0

func _init(space: HospitalSpace, floor_id: int, static_source: Dictionary) -> void:
	source = static_source
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
		var original: Rect2 = space._door_rect(door,int(door.span))
		doors.append({"door":door,"original":original})
		door_order[door.id] = door_order.size()
		door_index.update(door.id,floor_id,original)
	for id: String in source.facilities:
		var facility: Dictionary = source.facilities[id]
		var rect: Rect2i = Rect2i(int(facility.cell[0]),int(facility.cell[1]),int(facility.footprint[0]),int(facility.footprint[1]))
		_facilities.append({"rect":rect,"id":id})
		facility_index.update(id,floor_id,Rect2(rect))
		_index_rectangle(Rect2(rect),_facility_cells,id)
		_dependencies["facility:"+id] = {"rect":rect,"value":facility}
	for id: String in source.connectors:
		var connector: Dictionary = source.connectors[id]
		var rect: Rect2i = Rect2i(int(connector.cell[0]),int(connector.cell[1]),int(connector.footprint[0]),int(connector.footprint[1]))
		_connectors.append({"rect":rect,"id":id})
		_index_rectangle(Rect2(rect),_connector_cells,id)
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
	for wall: Dictionary in _walls:
		var lines: Dictionary = _horizontal_walls if wall.axis=="x" else _vertical_walls
		var line: int = int(wall.line)
		if not lines.has(line): lines[line] = []
		lines[line].append(wall)
	# Conservative ownership allowance, not a measurement of native RSS.
	charge = 16384+var_to_bytes(source).size()*8+(_facility_cells.size()+_connector_cells.size())*128+(_walls.size()+doors.size()+_facilities.size())*512

func _index_rectangle(rect: Rect2, cells: Dictionary, value: Variant) -> void:
	for y: int in range(maxi(0,ceili(rect.position.y)),mini(FloorNavigation.SIDE,ceili(rect.end.y))):
		for x: int in range(maxi(0,ceili(rect.position.x)),mini(FloorNavigation.SIDE,ceili(rect.end.x))):
			var cell: Vector2i = Vector2i(x,y)
			if not cells.has(cell): cells[cell] = value
