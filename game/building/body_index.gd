class_name BodyIndex
extends RefCounted

const BUCKET_CELLS: float = 4.0
var _buckets: Dictionary = {}
var _records: Dictionary = {}
var _boundary: int = 0

func clear() -> void:
	_buckets.clear()
	_records.clear()
	_boundary = 0

func begin_boundary(active: Dictionary) -> void:
	_boundary += 1
	# Reuse live buckets; expired movement records cannot grow the sweep cache.
	for id: String in _records.keys():
		if not active.has(id):
			remove(id)

func update(id: String, floor_id: int, rect: Rect2) -> void:
	var original: Dictionary = _records.get(id,{})
	if not original.is_empty():
		original.boundary = _boundary
	if not original.is_empty() and original.floor_id==floor_id and original.rect==rect:
		return
	var low: Vector2i = Vector2i(floori(rect.position.x/BUCKET_CELLS),floori(rect.position.y/BUCKET_CELLS))
	var high: Vector2i = Vector2i(floori(rect.end.x/BUCKET_CELLS),floori(rect.end.y/BUCKET_CELLS))
	if not original.is_empty() and original.floor_id==floor_id and original.low==low and original.high==high:
		original.rect = rect
		return
	remove(id)
	var keys: Array[Vector2i] = _keys(rect)
	var floor: Dictionary = _buckets.get(floor_id,{})
	for key: Vector2i in keys:
		var bucket: Dictionary = floor.get(key,{})
		bucket[id] = true
		floor[key] = bucket
	_buckets[floor_id] = floor
	_records[id] = {"floor_id":floor_id,"rect":rect,"bucket_keys":keys,"low":low,"high":high,"boundary":_boundary}

func remove(id: String) -> void:
	var original: Dictionary = _records.get(id,{})
	if original.is_empty():
		return
	var floor: Dictionary = _buckets[original.floor_id]
	for key: Vector2i in original.bucket_keys:
		floor[key].erase(id)
		if floor[key].is_empty():
			floor.erase(key)
	_records.erase(id)

func intersects(floor_id: int, rect: Rect2, ignored_id: String, ignored_ids: Array = []) -> bool:
	var floor: Dictionary = _buckets.get(floor_id,{})
	for x: int in range(floori(rect.position.x/BUCKET_CELLS),floori(rect.end.x/BUCKET_CELLS)+1):
		for y: int in range(floori(rect.position.y/BUCKET_CELLS),floori(rect.end.y/BUCKET_CELLS)+1):
			for id: String in floor.get(Vector2i(x,y),{}):
				if _records[id].boundary==_boundary and id!=ignored_id and not id in ignored_ids and rect.intersects(_records[id].rect,false):
					return true
	return false

func rectangle(id: String) -> Rect2:
	return _records[id].rect

func _keys(rect: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x: int in range(floori(rect.position.x/BUCKET_CELLS),floori(rect.end.x/BUCKET_CELLS)+1):
		for y: int in range(floori(rect.position.y/BUCKET_CELLS),floori(rect.end.y/BUCKET_CELLS)+1):
			result.append(Vector2i(x,y))
	return result
