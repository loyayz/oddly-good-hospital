extends RefCounted
# Static boundaries only. Bodies, movement phases and reservations never become
# walls. The caller caches this result solely for the geometry revision.
static func walls(world: WorldState, floor_id: int, desk_id: String) -> Array:
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
		_rectangle(result,rect)
	for facility: Dictionary in world.facts.facilities.values():
		if facility.id==desk_id or int(facility.floor_id)!=floor_id:continue
		var footprint: Array=world.facts.adaptations.get(facility.id,{}).get("footprint",facility.footprint)
		var rect: Rect2i=Rect2i(int(facility.cell[0]),int(facility.cell[1]),int(footprint[0]),int(footprint[1]))
		_rectangle(result,rect)
	# Connector shafts are static solids; landing/repair squares are public
	# walkable space, not walls or permanent traffic reservations.
	for connector: Dictionary in world.facts.connectors.values():
		if not HospitalTransit.has_stop(connector,floor_id) or not connector.has("cell"):continue
		var rect:=Rect2i(Vector2i(connector.cell[0],connector.cell[1]),Vector2i(connector.footprint[0],connector.footprint[1]))
		_rectangle(result,rect)
	return result
static func _rectangle(result: Array, rect: Rect2i)->void:
	result.append({"axis":"x","line":rect.position.y,"low":rect.position.x,"high":rect.end.x})
	result.append({"axis":"x","line":rect.end.y,"low":rect.position.x,"high":rect.end.x})
	result.append({"axis":"y","line":rect.position.x,"low":rect.position.y,"high":rect.end.y})
	result.append({"axis":"y","line":rect.end.x,"low":rect.position.y,"high":rect.end.y})

# Physical owned-floor extent, independent of the desk's room label or use.
static func floor_bounds(world: WorldState, floor_id: int)->Rect2i:
	var low:=Vector2i(100000,100000);var high:=Vector2i(-100000,-100000)
	for plot: Array in HospitalSpace.floor_plots(world,floor_id):
		var corner:=Vector2i(int(plot[0])*32,int(plot[1])*32)
		low=low.min(corner);high=high.max(corner+Vector2i(32,32))
	return Rect2i(low,high-low) if high.x>low.x and high.y>low.y else Rect2i()

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
