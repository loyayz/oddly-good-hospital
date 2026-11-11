class_name HospitalFacilityAreaIndex
extends RefCounted

# Rebuilt from layout facts. Each facility retains its own bounded projection;
# overlapping projections never become a connected-component business area.
var regions: Array = []
var by_facility: Dictionary = {}
var by_floor: Dictionary = {}
var room_cells: Dictionary = {}
var room_points: Dictionary = {}
var _world: WeakRef
var _revision: int = -1
var _facts: Dictionary = {}
var _basis: Dictionary = {}
var _walls: Dictionary = {}
var _plots: Dictionary = {}
var _obstacles: Dictionary = {}

func invalidate() -> void:
	_revision=-1

func refresh(world: WorldState, space: HospitalSpace) -> bool:
	if _world!=null and _world.get_ref()==world and _revision==world.geometry_revision and is_same(_facts,world.facts): return false
	var same_world: bool = _world!=null and _world.get_ref()==world
	_world=weakref(world)
	_revision=world.geometry_revision
	_facts=world.facts
	_walls.clear(); _plots.clear(); _obstacles.clear(); room_cells.clear(); room_points.clear()
	var floors: Dictionary = {}
	for key: String in world.facts.floors.overrides: floors[int(key)]=true
	for room: Dictionary in world.facts.rooms.values():
		floors[int(room.floor_id)]=true
		if not room.get("structure_valid",true): continue
		var cells: Dictionary=room_cells.get_or_add(int(room.floor_id),{})
		var points: Array=[]
		for cell: Array in BuildGeometry.cells(room):
			var point:=Vector2i(int(cell[0]),int(cell[1]))
			cells[point]=room.id
			points.append(point)
		room_points[room.id]=points
	for facility: Dictionary in world.facts.facilities.values():
		if facility.get("stored",false): continue
		floors[int(facility.floor_id)]=true
		if not space.content.facility_definition(facility.definition_id).get("blocks_movement",true): continue
		var obstacles: Dictionary=_obstacles.get_or_add(int(facility.floor_id),{})
		var footprint: Array=world.facts.adaptations.get(facility.id,{}).get("footprint",facility.footprint)
		for x: int in range(int(facility.cell[0]),int(facility.cell[0])+int(footprint[0])):
			for y: int in range(int(facility.cell[1]),int(facility.cell[1])+int(footprint[1])):
				obstacles.get_or_add(Vector2i(x,y),[]).append(facility.id)
	for floor_id: int in floors:
		var layout: Dictionary=HospitalSpace.floor_layout(world,floor_id)
		var obstacles: Dictionary=_obstacles.get_or_add(floor_id,{})
		for cell: Array in layout.get("blocked",[]):
			obstacles.get_or_add(Vector2i(int(cell[0]),int(cell[1])),[]).append("floor_block")
		for connector: Dictionary in world.facts.connectors.values():
			if connector.get("stored",false) or not HospitalTransit.has_stop(connector,floor_id): continue
			for x: int in range(int(connector.cell[0]),int(connector.cell[0])+int(connector.footprint[0])):
				for y: int in range(int(connector.cell[1]),int(connector.cell[1])+int(connector.footprint[1])):
					obstacles.get_or_add(Vector2i(x,y),[]).append("connector:"+str(connector.id))
		var plots: Dictionary={}
		for plot: Array in layout.plots: plots[Vector2i(int(plot[0]),int(plot[1]))]=true
		_plots[floor_id]=plots
		var walls: Dictionary={}
		for wall: Dictionary in layout.get("wall_edges",[]):
			for unit: int in range(int(wall.low),int(wall.high)): walls[_key(str(wall.axis),int(wall.line),unit)]=true
		for door: Dictionary in layout.get("doors",[]):
			var line: int=int(door.cell[1] if door.axis=="x" else door.cell[0])
			var low: int=int(door.cell[0] if door.axis=="x" else door.cell[1])
			for unit: int in range(low,low+int(door.span)): walls[_key(str(door.axis),line,unit)]=true
		_walls[floor_id]=walls
	var definitions: Array=HospitalWaitingLife.PUBLIC_SEAT_DEFINITIONS.duplicate()
	definitions.append_array(["FUR07","FUR17","AE02","AE03"])
	for item: Dictionary in space.content.catalog.get("staff_recreation_equipment",[]):
		var id: String=str(item.get("equipment_id",item.get("definition_id",item.get("id",""))))
		if not id.is_empty(): definitions.append(id)
	var eligible: Dictionary={}
	for definition: String in definitions:
		for id: String in world.facility_ids(definition):
			var facility: Dictionary=world.facts.facilities[id]
			var point:=Vector2i(int(facility.cell[0]),int(facility.cell[1]))
			if not facility.get("stored",false) and public_point(world,int(facility.floor_id),point): eligible[id]=facility
	var next: Dictionary={}
	var bases: Dictionary={}
	for id: String in eligible:
		var facility: Dictionary=eligible[id]
		var floor_id: int=int(facility.floor_id)
		var room_id: String=str(room_cells.get(floor_id,{}).get(Vector2i(int(facility.cell[0]),int(facility.cell[1])),""))
		var rect:=Rect2i(Vector2i(int(facility.cell[0]),int(facility.cell[1])),Vector2i(int(facility.footprint[0]),int(facility.footprint[1])))
		var bounds: Rect2i=rect.grow(3)
		var local_walls: Array=[]
		var local_obstacles: Array=[]
		for x: int in range(bounds.position.x,bounds.end.x+1):
			for y: int in range(bounds.position.y,bounds.end.y+1):
				for axis: String in ["x","y"]:
					var key: String=_key(axis,y if axis=="x" else x,x if axis=="x" else y)
					if _walls.get(floor_id,{}).has(key): local_walls.append(key)
				var point:=Vector2i(x,y)
				if _obstacles.get(floor_id,{}).has(point): local_obstacles.append([point,_obstacles[floor_id][point]])
		var local_land: Array=[]
		var local_rooms: Array=[]
		for x: int in range(bounds.position.x,bounds.end.x):
			for y: int in range(bounds.position.y,bounds.end.y):
				var point:=Vector2i(x,y)
				if _plots.get(floor_id,{}).has(Vector2i(x/32,y/32)): local_land.append(point)
				var enclosing: String=str(room_cells.get(floor_id,{}).get(point,""))
				if not enclosing.is_empty(): local_rooms.append([point,enclosing,world.facts.rooms[enclosing].kind])
		var basis: Array=[floor_id,room_id,rect,world.facts.rooms.get(room_id,{}).get("kind",""),local_walls,local_obstacles,local_land,local_rooms]
		bases[id]=basis
		if same_world and _basis.get(id,[])==basis and by_facility.has(id): next[id]=by_facility[id]
		else:
			next[id]=_build(world,id,floor_id,room_id,rect,bounds)
			space.query_counts["public_local_area_builds"]=int(space.query_counts.get("public_local_area_builds",0))+1
	_basis=bases
	by_facility=next
	regions.clear(); by_floor.clear()
	for id: String in by_facility:
		var area: Dictionary=by_facility[id]
		area.facilities=[]; area.facility_definitions={}
		regions.append(area)
		var cells: Dictionary=by_floor.get_or_add(int(area.ref.floor_id),{})
		for point: Vector2i in area.cells: cells.get_or_add(point,[]).append(area)
	# Local candidate membership comes from indexed arrival points, never a
	# per-person search of all facilities or all floor cells.
	var arrivals: Dictionary={}
	for id: String in eligible:
		var facility: Dictionary=eligible[id]
		var point:=Vector2i(int(facility.patient_cell[0]),int(facility.patient_cell[1]))
		arrivals.get_or_add(int(facility.floor_id),{}).get_or_add(point,[]).append(id)
	for area: Dictionary in regions:
		var found: Dictionary={str(area.ref.facility_id):true}
		for point: Vector2i in area.cells:
			for id: String in arrivals.get(int(area.ref.floor_id),{}).get(point,[]): found[id]=true
		var ids: Array=found.keys(); ids.sort()
		for id: String in ids:
			if not eligible.has(id): continue
			var definition: String=str(eligible[id].definition_id)
			var positions: PackedInt32Array=area.facility_definitions.get(definition,PackedInt32Array())
			positions.append(area.facilities.size())
			area.facility_definitions[definition]=positions
			area.facilities.append(id)
	return true

func public_point(world: WorldState, floor_id: int, point: Vector2i) -> bool:
	if point.x<0 or point.y<0 or point.x>=96 or point.y>=96: return false
	if not _plots.get(floor_id,{}).has(Vector2i(point.x/32,point.y/32)): return false
	var room: Dictionary=world.facts.rooms.get(room_cells.get(floor_id,{}).get(point,""),{})
	return room.is_empty() or room.get("kind","") in ["rest","toilet"]

func _build(world: WorldState, id: String, floor_id: int, room_id: String, rect: Rect2i, bounds: Rect2i) -> Dictionary:
	var distances: Dictionary={}
	var queue: Array=[]
	for x: int in range(rect.position.x,rect.end.x):
		for y: int in range(rect.position.y,rect.end.y):
			var point:=Vector2i(x,y)
			distances[point]=0; queue.append(point)
	var cursor: int=0
	while cursor<queue.size():
		var point: Vector2i=queue[cursor]; cursor+=1
		if int(distances[point])>=3: continue
		for offset: Vector2i in BuildGeometry.DIRECTIONS:
			var candidate: Vector2i=point+offset
			if distances.has(candidate) or not public_point(world,floor_id,candidate): continue
			if str(room_cells.get(floor_id,{}).get(candidate,""))!=room_id: continue
			var axis: String="x" if offset.y!=0 else "y"
			var key: String=_key(axis,maxi(point.y,candidate.y) if axis=="x" else maxi(point.x,candidate.x),point.x if axis=="x" else point.y)
			if _walls.get(floor_id,{}).has(key): continue
			var occupied: Array=_obstacles.get(floor_id,{}).get(candidate,[])
			if not occupied.is_empty() and not (occupied.size()==1 and occupied[0]==id): continue
			distances[candidate]=int(distances[point])+1; queue.append(candidate)
	var cells: Dictionary={}
	for point: Vector2i in distances: cells[point]=true
	return {"ref":{"floor_id":floor_id,"room_id":room_id,"facility_id":id,"anchor":[rect.position.x,rect.position.y]},"cells":cells,"facilities":[],"facility_definitions":{},"bounds":bounds,"geometry":JSON.stringify([id,distances],"",true,true)}

static func _key(axis: String,line: int,unit: int) -> String:
	return axis+":"+str(line)+":"+str(unit)
