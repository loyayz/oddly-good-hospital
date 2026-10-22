class_name BodyIndex
extends RefCounted

class Record:
	extends RefCounted
	var id: String
	var floor_id: int
	var rect: Rect2
	# Scratch geometry; movement marks which records were actually accepted.
	var sweep_from: Rect2
	var sweep_to: Rect2
	var boundary: int

# Boost.Geometry owns broadphase insertion/removal/intersection. This adapter
# retains boundary lifetime, stable identities and strict edge-touch semantics.
var bucket_cells: Vector2
var _tree: PlatformSpatialIndex = PlatformSpatialIndex.new()
var _records: Dictionary = {}
var _boundary: int = 0

func _init(cells: Vector2 = Vector2(8,8)) -> void:
	bucket_cells = cells

func clear() -> void:
	_tree.clear()
	_records.clear()
	_boundary = 0

func begin_boundary(active: Dictionary) -> void:
	_boundary += 1
	for id: String in _records.keys():
		if not active.has(id): remove(id)

func expire_boundary() -> void:
	_boundary += 1

func update(id: String, floor_id: int, rect: Rect2) -> void:
	var record: Record = _records.get(id)
	if record!=null:
		record.boundary = _boundary
		if record.floor_id==floor_id and record.rect==rect: return
	else:
		record = Record.new()
		record.id = id
		_records[id] = record
	record.floor_id = floor_id
	record.rect = rect
	record.boundary = _boundary
	_tree.update(id,floor_id,[rect.position.x,rect.position.y,rect.size.x,rect.size.y])

func remove(id: String) -> void:
	if not _records.has(id): return
	_tree.remove(id)
	_records.erase(id)

func intersects(floor_id: int, rect: Rect2, ignored_id: String, ignored_ids: Array = []) -> bool:
	for id: String in _query(floor_id,rect):
		var record: Record = _records[id]
		if record.boundary==_boundary and id!=ignored_id and not id in ignored_ids and rect.intersects(record.rect,false): return true
	return false

func candidates(floor_id: int, rect: Rect2, ignored_ids: Array = []) -> Array[String]:
	var result: Array[String] = []
	for id: String in _query(floor_id,rect):
		var record: Record = _records[id]
		if record.boundary==_boundary and not id in ignored_ids and rect.intersects(record.rect,false): result.append(id)
	result.sort()
	return result

func candidates_in_regions(floor_id: int, regions: Array[Rect2], ignored_ids: Array = []) -> Array[String]:
	var result: Array[String] = []
	if regions.is_empty(): return result
	var rectangles: Array = []
	for rect: Rect2 in regions: rectangles.append([rect.position.x,rect.position.y,rect.size.x,rect.size.y])
	# Boost queries every original box; the standard-library set only removes
	# repeated broadphase identities. Exact engine geometry still decides below.
	for id: String in _tree.query_many(floor_id,rectangles).ids:
		var record: Record = _records[id]
		if record.boundary!=_boundary or id in ignored_ids: continue
		for rect: Rect2 in regions:
			if rect.intersects(record.rect,false):
				result.append(id)
				break
	result.sort()
	return result

func _query(floor_id: int, rect: Rect2) -> Array:
	return _tree.query(floor_id,[rect.position.x,rect.position.y,rect.size.x,rect.size.y]).ids

func rectangle(id: String) -> Rect2:
	return (_records[id] as Record).rect

func record(id: String) -> Record:
	return _records[id] as Record
