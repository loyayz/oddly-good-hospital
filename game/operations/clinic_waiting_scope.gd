class_name HospitalClinicWaitingScope
extends RefCounted

# A six-cell public approach outside actual room doors; walls and real
# connectivity still constrain the legal waiting and chair access positions.
const ADJACENT_CELLS: int = 6
var space: HospitalSpace
var _cache: Dictionary = {}
var _world: WeakRef
var _revision: int = -1

func _init(geometry: HospitalSpace) -> void:
	space = geometry

func area(world: WorldState, actor_id: String, facility_id: String) -> Dictionary:
	if _world==null or _world.get_ref()!=world or _revision!=world.geometry_revision:
		_world = weakref(world)
		_revision = world.geometry_revision
		_cache.clear()
	var facility: Dictionary = world.facts.facilities.get(facility_id,{})
	var actor: Dictionary = world.facts.actors.get(actor_id,{})
	if facility.is_empty() or actor.is_empty(): return {}
	var graph: FloorNavigation = space._navigation.graph(space,world,int(facility.floor_id),actor,[],{})
	var key: String = JSON.stringify([facility_id,graph.geometry.get_instance_id()])
	if not _cache.has(key):
		if _cache.size()>=128: _cache.clear()
		_cache[key] = _build(world,actor_id,facility,graph.geometry)
	return _cache[key]

func _build(world: WorldState, actor_id: String, facility: Dictionary, geometry: RouteClearance) -> Dictionary:
	var actor: Dictionary = world.facts.actors[actor_id]
	var floor_id: int = int(facility.floor_id)
	var room: Dictionary = world.facts.rooms.get(facility.get("room_id",""),{})
	space.public_areas._ensure(world,floor_id)
	var points: Dictionary = {}
	var seeds: Array = []
	var candidates: Dictionary = {}
	var size: int = space.clearance(actor)
	var bounds: Rect2i
	if room.is_empty():
		var p: Array = space.facility_layout(world,facility.id).patient_cell
		bounds = Rect2i(Vector2i(int(p[0]),int(p[1]))-Vector2i(ADJACENT_CELLS,ADJACENT_CELLS),Vector2i.ONE*(ADJACENT_CELLS*2+1))
		seeds.append(Vector2i(int(p[0]),int(p[1])))
	else:
		bounds = Rect2i(Vector2i(int(room.origin[0]),int(room.origin[1])),Vector2i(int(room.size[0]),int(room.size[1]))).grow(ADJACENT_CELLS+size-1)
		for door: Dictionary in world.facts.floors.overrides.get(str(floor_id),{}).get("doors",[]):
			if door.get("room_id","")!=room.id: continue
			var quote: Dictionary = space.door_quote(world,actor,floor_id,door)
			if not quote.get("ok",false): continue
			var opening: Rect2 = space._door_rect(door,int(quote.get("span",door.span)))
			for x: int in range(floori(opening.position.x)-size,ceili(opening.end.x)+1):
				for y: int in range(floori(opening.position.y)-size,ceili(opening.end.y)+1):
					var point: Vector2i = Vector2i(x,y)
					var body: Rect2 = space._actor_rect(actor,Vector2(point))
					if body.intersects(opening,false) or space.room_contains(room,body): continue
					if Rect2(Vector2(point),Vector2.ONE*size).grow(0.01).intersects(opening,false): seeds.append(point)
	var indexed: Array=[]
	if room.is_empty():
		for x: int in range(maxi(0,bounds.position.x),mini(FloorNavigation.SIDE,bounds.end.x)):
			for y: int in range(maxi(0,bounds.position.y),mini(FloorNavigation.SIDE,bounds.end.y)): indexed.append(Vector2i(x,y))
	else: indexed=space.room_use.waiting_cells(world,str(room.id))
	for point: Vector2i in indexed:
		var body: Rect2=space._actor_rect(actor,Vector2(point))
		if not room.is_empty() and space.room_contains(room,body): continue
		if not geometry.reason(point).is_empty() or not space.room_use.public_point(world,floor_id,point): continue
		candidates[point]=true
	var queue: Array = []
	for seed: Vector2i in seeds:
		if candidates.has(seed) and not points.has(seed):
			points[seed] = true
			queue.append(seed)
	var cursor: int = 0
	while cursor<queue.size():
		var point: Vector2i = queue[cursor]
		cursor += 1
		for offset: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i = point+offset
			if points.has(next) or not candidates.has(next): continue
			var edge: Dictionary = space.navigation._floor_route(world,actor,floor_id,point,next,[],{},true,{},true,true)
			if not edge.get("ok",false) or float(edge.walking_distance)>1.0: continue
			points[next] = true
			queue.append(next)
	return {"facility_id":facility.id,"floor_id":floor_id,"room_id":str(facility.get("room_id","")),"points":points}

func _near_room(room: Dictionary, body: Rect2) -> bool:
	if not room.has("cells"):
		return Rect2(float(room.origin[0]),float(room.origin[1]),float(room.size[0]),float(room.size[1])).grow(ADJACENT_CELLS).intersects(body,false)
	# An L-shaped room's bounding box can contain a distant notch. Adjacency
	# comes from actual interior cells, still allowing a large body to extend
	# into the connected legal corridor rather than squeezing into a thin band.
	for cell: Array in room.cells:
		if Rect2(Vector2(float(cell[0]),float(cell[1])),Vector2.ONE).grow(ADJACENT_CELLS).intersects(body,false): return true
	return false

func allows(world: WorldState, actor_id: String, facility_id: String, floor_id: int, cell: Array) -> bool:
	var scope: Dictionary = area(world,actor_id,facility_id)
	return not scope.is_empty() and int(scope.floor_id)==floor_id and scope.points.has(Vector2i(roundi(cell[0]),roundi(cell[1])))

func point(world: WorldState, actor_id: String, facility_id: String, avoid: Rect2 = Rect2()) -> Dictionary:
	var scope: Dictionary = area(world,actor_id,facility_id)
	if scope.is_empty(): return {}
	var actor: Dictionary = world.facts.actors[actor_id]
	if actor.location.kind!="floor": return {}
	var options: Array = scope.points.keys()
	var origin: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	options.sort_custom(func(a: Vector2i,b: Vector2i)->bool:
		var da: float = Vector2(a).distance_squared_to(origin)
		var db: float = Vector2(b).distance_squared_to(origin)
		return da<db if da!=db else a.x<b.x if a.x!=b.x else a.y<b.y)
	for candidate: Vector2i in options:
		var cell: Array = [candidate.x,candidate.y]
		if avoid.has_area() and space._actor_rect(actor,Vector2(candidate)).intersects(avoid,false): continue
		if not space.public_areas.safe_wait(world,actor_id,int(scope.floor_id),cell): continue
		if not space.can_reach(world,actor_id,int(scope.floor_id),cell): continue
		return {"floor_id":int(scope.floor_id),"cell":cell}
	return {}

func allows_seat(world: WorldState, actor_id: String, destination_id: String, chair_id: String) -> bool:
	var chair: Dictionary = world.facts.facilities.get(chair_id,{})
	var scoped: Dictionary = area(world,actor_id,destination_id)
	if chair.is_empty() or scoped.is_empty() or int(chair.floor_id)!=int(scoped.floor_id): return false
	var indexed: Array=space.room_use.waiting_cells(world,str(scoped.room_id))
	for x: int in range(int(chair.cell[0]),int(chair.cell[0])+int(chair.footprint[0])):
		for y: int in range(int(chair.cell[1]),int(chair.cell[1])+int(chair.footprint[1])):
			if not Vector2i(x,y) in indexed: return false
	var layout: Dictionary = space.facility_layout(world,chair_id)
	if allows(world,actor_id,destination_id,int(chair.floor_id),layout.patient_cell): return true
	var base: Rect2 = Rect2(Vector2(float(chair.cell[0]),float(chair.cell[1])),Vector2(float(chair.footprint[0]),float(chair.footprint[1])))
	var goal: Vector2i = Vector2i(int(layout.patient_cell[0]),int(layout.patient_cell[1]))
	var actor: Dictionary = world.facts.actors[actor_id]
	var limit: int = space.clearance(actor)+2*maxi(int(chair.footprint[0]),int(chair.footprint[1]))
	for point: Vector2i in scoped.points:
		if not base.grow(1.0).intersects(Rect2(Vector2(point),Vector2.ONE),false): continue
		if absi(point.x-goal.x)+absi(point.y-goal.y)>limit: continue
		var access: Dictionary = space.navigation._floor_route(world,actor,int(chair.floor_id),point,goal,[],{},true,{},true,true)
		if access.get("ok",false) and float(access.walking_distance)<=limit: return true
	return false
