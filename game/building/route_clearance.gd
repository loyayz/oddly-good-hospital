class_name RouteClearance
extends RefCounted

# Projection lifetime is one synchronous route or movement boundary.
var _size: int
var _plots: Dictionary = {}
var _blocked: Dictionary = {}
var _doors: Array[Dictionary] = []
var _facilities: Array[Dictionary] = []
var _connectors: Array[Dictionary] = []
var _reservations: Array[Dictionary] = []
var _members: Array[Dictionary] = []

func _init(space: HospitalSpace, world: WorldState, actor: Dictionary, floor_id: int, members: Array = [], offsets: Dictionary = {}) -> void:
	_size = space.clearance(actor)
	for member_id: String in members:
		if member_id!=actor.id:
			var offset: Array = offsets[member_id]
			_members.append({"query":RouteClearance.new(space,world,world.facts.actors[member_id],floor_id),"offset":Vector2i(int(offset[0]),int(offset[1]))})
	var layout: Dictionary = world.facts.floors.overrides.get(str(floor_id),{})
	for plot: Array in layout.get("plots",[]):
		_plots[Vector2i(int(plot[0]),int(plot[1]))] = true
	for cell: Array in layout.get("blocked",[]):
		_blocked[Vector2i(int(cell[0]),int(cell[1]))] = true
	for door: Dictionary in layout.get("doors",[]):
		var fit: Dictionary = space.door_quote(world,actor,floor_id,door)
		_doors.append({"original":space._door_rect(door,int(door.span)),"opening":space._door_rect(door,int(fit.span)) if fit.ok else Rect2(),"ok":fit.ok,"reason":fit.get("reason","")})
	for facility: Dictionary in world.facts.facilities.values():
		if int(facility.floor_id)==floor_id:
			var actual: Dictionary = space.facility_layout(world,facility.id)
			_facilities.append({"rect":Rect2i(int(facility.cell[0]),int(facility.cell[1]),int(actual.footprint[0]),int(actual.footprint[1])),"id":facility.id})
	for connector: Dictionary in world.facts.connectors.values():
		if floor_id in connector.stops:
			_connectors.append({"rect":Rect2i(int(connector.cell[0]),int(connector.cell[1]),int(connector.footprint[0]),int(connector.footprint[1])),"id":connector.id})
	for reservation: Dictionary in world.facts.adaptations.values():
		if reservation.kind=="facility" and int(reservation.floor_id)==floor_id and actor.id!=reservation.actor_id and not actor.id in reservation.staff_ids:
			var regions: Array[Rect2] = []
			for area: Array in reservation.regions:
				regions.append(Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3])))
			_reservations.append({"regions":regions,"id":reservation.facility_id})

func reason(origin: Vector2i) -> String:
	for member: Dictionary in _members:
		var result: String = member.query.reason(origin+member.offset)
		if not result.is_empty():
			return result
	if _blocked.is_empty() and _doors.is_empty() and _facilities.is_empty() and _connectors.is_empty() and _reservations.is_empty():
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
				var opening: bool = false
				for door: Dictionary in _doors:
					if door.ok and door.opening.has_point(point):
						opening = true
						break
				if not opening:
					return "通路不足%d格" % _size
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
	return ""
