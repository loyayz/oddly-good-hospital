extends RefCounted
# Static boundaries only. Bodies, movement phases and reservations never become
# walls. The caller caches this result solely for the geometry revision.
static func walls(world: WorldState, floor_id: int, desk_id: String, scope: Dictionary = {}) -> Array:
	if scope.is_empty():scope=room_scope(world,floor_id,desk_id)
	var result: Array=[]
	for room: Dictionary in world.facts.rooms.values():
		if int(room.floor_id)==floor_id:result.append_array(BuildGeometry.room_walls(room))
	var owned: Dictionary={}
	for plot: Array in HospitalSpace.floor_plots(world,floor_id):
		for xx: int in range(int(plot[0])*32,(int(plot[0])+1)*32):
			for yy: int in range(int(plot[1])*32,(int(plot[1])+1)*32):owned[Vector2i(xx,yy)]=true
	result.append_array(BuildGeometry.walls(owned))
	for cell: Array in world.facts.floors.overrides.get(str(floor_id),{}).get("blocked",[]):
		var rect: Rect2i=Rect2i(int(cell[0]),int(cell[1]),1,1)
		if not scope.is_empty() and not rect.intersects(scope.bounds):continue
		_rectangle(result,rect)
	for facility: Dictionary in world.facts.facilities.values():
		if facility.id==desk_id or int(facility.floor_id)!=floor_id:continue
		var rect: Rect2i=Rect2i(int(facility.cell[0]),int(facility.cell[1]),int(facility.footprint[0]),int(facility.footprint[1]))
		if not scope.is_empty() and not rect.intersects(scope.bounds):continue
		_rectangle(result,rect)
	# Connector shafts are static solids; landing/repair squares are public
	# walkable space, not walls or permanent traffic reservations.
	for connector: Dictionary in world.facts.connectors.values():
		if not HospitalTransit.has_stop(connector,floor_id) or not connector.has("cell"):continue
		var rect:=Rect2i(Vector2i(connector.cell[0],connector.cell[1]),Vector2i(connector.footprint[0],connector.footprint[1]))
		if not scope.is_empty() and not rect.intersects(scope.bounds):continue
		_rectangle(result,rect)
	return result
static func _rectangle(result: Array, rect: Rect2i)->void:
	result.append({"axis":"x","line":rect.position.y,"low":rect.position.x,"high":rect.end.x})
	result.append({"axis":"x","line":rect.end.y,"low":rect.position.x,"high":rect.end.x})
	result.append({"axis":"y","line":rect.position.x,"low":rect.position.y,"high":rect.end.y})
	result.append({"axis":"y","line":rect.end.x,"low":rect.position.y,"high":rect.end.y})

# A bounded room is usable for culling only when its actual cell set contains
# the whole desk. Invalid/missing room ownership falls back to all geometry.
static func room_scope(world: WorldState, floor_id: int, desk_id: String)->Dictionary:
	var desk: Dictionary=world.facts.facilities.get(desk_id,{})
	var room: Dictionary=world.facts.rooms.get(str(desk.get("room_id","")),{})
	if room.is_empty() or int(room.get("floor_id",-1))!=floor_id:return {}
	var cells: Dictionary={}
	var low:=Vector2i(100000,100000);var high:=Vector2i(-100000,-100000)
	for raw: Array in BuildGeometry.cells(room):
		var point:=Vector2i(int(raw[0]),int(raw[1]))
		cells[point]=true;low=low.min(point);high=high.max(point+Vector2i.ONE)
	if cells.is_empty() or BuildGeometry.room_walls(room).is_empty():return {}
	for xx: int in range(int(desk.cell[0]),int(desk.cell[0])+int(desk.footprint[0])):
		for yy: int in range(int(desk.cell[1]),int(desk.cell[1])+int(desk.footprint[1])):
			if not cells.has(Vector2i(xx,yy)):return {}
	return {"bounds":Rect2i(low,high-low),"cells":cells}

# Landing squares stay walkable. Only persistent queue standing is excluded,
# just like a facility work post: transit may need the full supported body span.
static func overlaps_landing(world: WorldState, content: HospitalContent, floor_id: int, rect: Rect2) -> bool:
	for connector: Dictionary in world.facts.connectors.values():
		if not HospitalTransit.has_stop(connector,floor_id):continue
		var definition: Dictionary=content.definition("vertical_connectors",connector.definition_id)
		var span: int=int(definition.max_clearance_cells)
		var point: Array=connector.anchor
		if rect.intersects(Rect2(float(point[0]),float(point[1]),span,span),false):return true
	return false
