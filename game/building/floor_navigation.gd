class_name FloorNavigation
extends AStar2D

const SIDE: int = 96
const LIMIT: int = SIDE*SIDE
const NEIGHBOURS: Array[Vector2i] = [Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN]

var geometry: RouteClearance
var _enabled: PackedByteArray = PackedByteArray()
var _query: RouteClearance
var _people: Callable
var _bases: Array[FloorNavigation] = []
var _shifts: Array[Vector2i] = []
var _overlay: bool = false

func _init(projection: RouteClearance) -> void:
	geometry = projection
	_enabled.resize(LIMIT)
	_build()
	neighbor_filter_enabled = true

func _build() -> void:
	var ids: Array[int] = []
	for plot: Vector2i in geometry._plots:
		for y: int in range(plot.y*32,(plot.y+1)*32):
			for x: int in range(plot.x*32,(plot.x+1)*32): ids.append(y*SIDE+x)
	ids.sort()
	reserve_space(ids.size())
	for id: int in ids:
		var cell: Vector2i = _cell(id)
		add_point(id,Vector2(cell))
		_enabled[id] = int(geometry.reason(cell).is_empty())
		if _enabled[id]==0: set_point_disabled(id,true)
	for id: int in ids:
		if _enabled[id]==0: continue
		var cell: Vector2i = _cell(id)
		# These target IDs are already ascending; retain directed edge order.
		for offset: Vector2i in NEIGHBOURS:
			var next: Vector2i = cell+offset
			if _inside(next) and _enabled[_id(next)]!=0 and geometry.edge_reason(cell,next).is_empty():
				connect_points(id,_id(next),false)

func refresh(projection: RouteClearance) -> void:
	var regions: Array[Rect2i] = projection.dirty_regions(geometry)
	geometry = projection
	_repair(regions)

func _repair(regions: Array[Rect2i]) -> void:
	var affected: Dictionary = {}
	for region: Rect2i in regions:
		var clipped: Rect2i = region.intersection(Rect2i(0,0,SIDE,SIDE))
		for y: int in range(clipped.position.y,clipped.end.y):
			for x: int in range(clipped.position.x,clipped.end.x):
				affected[y*SIDE+x] = true
	var touched: Dictionary = affected.duplicate()
	for id: int in affected:
		var cell: Vector2i = _cell(id)
		if not has_point(id):
			add_point(id,Vector2(cell))
		_enabled[id] = int(geometry.reason(cell).is_empty())
		set_point_disabled(id,_enabled[id]==0)
		for offset: Vector2i in NEIGHBOURS:
			var next: Vector2i = cell+offset
			if _inside(next) and has_point(_id(next)):
				touched[_id(next)] = true
	var ids: Array = touched.keys()
	ids.sort()
	for id: int in ids:
		for other: int in get_point_connections(id):
			disconnect_points(id,other,false)
		if _enabled[id]==0:
			continue
		var adjacent: Array[int] = []
		for offset: Vector2i in NEIGHBOURS:
			var next: Vector2i = _cell(id)+offset
			if _inside(next) and _enabled[_id(next)]!=0:
				if geometry.edge_reason(_cell(id),next).is_empty():
					adjacent.append(_id(next))
		adjacent.sort()
		for other: int in adjacent:
			connect_points(id,other,false)

# Integer translations preserve each constituent's complete footprint and edge
# sweep. Only the current search borrows bases; cache eviction does not pin them.
func _composed_node(cell: Vector2i, bases: Array[FloorNavigation], shifts: Array[Vector2i]) -> bool:
	for index: int in bases.size():
		var point: Vector2i = cell+shifts[index]
		if not _inside(point) or bases[index]._enabled[_id(point)]==0:
			return false
	return true

func _composed_edge(from: Vector2i, to: Vector2i, bases: Array[FloorNavigation], shifts: Array[Vector2i]) -> bool:
	for index: int in bases.size():
		if not bases[index].are_points_connected(_id(from+shifts[index]),_id(to+shifts[index]),false):
			return false
	return true

func find_path(start: Vector2i, goal: Vector2i, query: RouteClearance, people: Callable = Callable(), partial: bool = false, bases: Array[FloorNavigation] = [], shifts: Array[Vector2i] = [], overlay: bool = false, cost_only: bool = false) -> Dictionary:
	if not _inside(start) or not _inside(goal):
		return {"ok":false,"status":"unreachable","reason":"目标超出96×96真实楼面"}
	var reason: String = query.reason(goal)
	if not reason.is_empty() and not partial:
		return {"ok":false,"status":"unreachable","reason":reason}
	if not has_point(_id(start)) or is_point_disabled(_id(start)) or not has_point(_id(goal)) or not _composed_node(start,bases,shifts):
		return {"ok":false,"status":"unreachable","reason":"真实身体无法到达目标"}
	_query = query
	_people = people
	_bases = bases
	_shifts = shifts
	_overlay = overlay
	neighbor_filter_enabled = overlay or not bases.is_empty() or people.is_valid() or query.has_reservations()
	var ids: PackedInt64Array = get_id_path(_id(start),_id(goal),partial)
	_query = null
	_people = Callable()
	_bases = []
	_shifts = []
	_overlay = false
	neighbor_filter_enabled = false
	if ids.is_empty():
		return {"ok":false,"status":"unreachable","reason":"真实身体无法到达目标"}
	var complete: bool = ids[ids.size()-1]==_id(goal)
	var result: Dictionary = {"ok":complete,"status":"complete" if complete else "partial","reason":"" if complete else "只能到达部分路线","walking_distance":ids.size()-1}
	# AStar2D exposes the native ID path. Cost queries retain its exact search
	# and tie order without materializing script cells or executable segments.
	if cost_only: return result
	var path: Array = []
	for index: int in range(1,ids.size()):
		var cell: Vector2i = _cell(ids[index])
		path.append([cell.x,cell.y])
	result.cells = path
	return result

func _filter_neighbor(from_id: int, to_id: int) -> bool:
	var cell: Vector2i = _cell(to_id)
	if _overlay and (not _query.reason(cell).is_empty() or not _query.edge_reason(_cell(from_id),cell).is_empty()):
		return true
	if not _bases.is_empty() and (not _composed_node(cell,_bases,_shifts) or not _composed_edge(_cell(from_id),cell,_bases,_shifts)):
		return true
	return not _query.reservation_reason(cell).is_empty() or (_people.is_valid() and not bool(_people.call(_cell(from_id),cell)))

func _estimate_cost(from_id: int, end_id: int) -> float:
	var delta: Vector2i = _cell(from_id)-_cell(end_id)
	return float(absi(delta.x)+absi(delta.y))

static func _inside(cell: Vector2i) -> bool:
	return cell.x>=0 and cell.y>=0 and cell.x<SIDE and cell.y<SIDE

static func _id(cell: Vector2i) -> int:
	return cell.y*SIDE+cell.x

static func _cell(id: int) -> Vector2i:
	return Vector2i(id%SIDE,id/SIDE)
