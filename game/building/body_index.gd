class_name BodyIndex
extends RefCounted

class Record:
	extends RefCounted
	var id: String
	var floor_id: int
	var rect: Rect2
	var bucket_keys: Array[Vector2i] = []
	var low: Vector2i
	var high: Vector2i
	var boundary: int

class Bucket:
	extends RefCounted
	var records: Array[Record] = []

var bucket_cells: Vector2 = Vector2(8,8)
var _buckets: Dictionary = {}
var _records: Dictionary = {}
var _boundary: int = 0

func _init(cells: Vector2 = Vector2(8,8)) -> void:
	bucket_cells = cells

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

func expire_boundary() -> void:
	_boundary += 1

func update(id: String, floor_id: int, rect: Rect2) -> void:
	var record: Record = _records.get(id)
	if record!=null:
		record.boundary = _boundary
		if record.floor_id==floor_id and record.rect==rect:
			return
	var low: Vector2i = Vector2i(floori(rect.position.x/bucket_cells.x),floori(rect.position.y/bucket_cells.y))
	var high: Vector2i = Vector2i(floori(rect.end.x/bucket_cells.x),floori(rect.end.y/bucket_cells.y))
	if record!=null and record.floor_id==floor_id and record.low==low and record.high==high:
		record.rect = rect
		return
	if record==null:
		record = Record.new()
		record.id = id
		_records[id] = record
	else:
		_unlink(record)
	record.floor_id = floor_id
	record.rect = rect
	record.low = low
	record.high = high
	record.boundary = _boundary
	record.bucket_keys = _keys(rect)
	var floor: Dictionary = _buckets.get(floor_id,{})
	for key: Vector2i in record.bucket_keys:
		var bucket: Bucket = floor.get(key)
		if bucket==null:
			bucket = Bucket.new()
			floor[key] = bucket
		bucket.records.append(record)
	_buckets[floor_id] = floor

func remove(id: String) -> void:
	var record: Record = _records.get(id)
	if record==null:
		return
	_unlink(record)
	_records.erase(id)

func _unlink(record: Record) -> void:
	var floor: Dictionary = _buckets[record.floor_id]
	for key: Vector2i in record.bucket_keys:
		var bucket: Bucket = floor[key]
		bucket.records.erase(record)
		if bucket.records.is_empty():
			floor.erase(key)
	if floor.is_empty():
		_buckets.erase(record.floor_id)

func intersects(floor_id: int, rect: Rect2, ignored_id: String, ignored_ids: Array = []) -> bool:
	var floor: Dictionary = _buckets.get(floor_id,{})
	for x: int in range(floori(rect.position.x/bucket_cells.x),floori(rect.end.x/bucket_cells.x)+1):
		for y: int in range(floori(rect.position.y/bucket_cells.y),floori(rect.end.y/bucket_cells.y)+1):
			var bucket: Bucket = floor.get(Vector2i(x,y))
			if bucket==null:
				continue
			for record: Record in bucket.records:
				if record.boundary==_boundary and record.id!=ignored_id and not record.id in ignored_ids and rect.intersects(record.rect,false):
					return true
	return false

func candidates(floor_id: int, rect: Rect2, ignored_ids: Array = []) -> Array[String]:
	var found: Dictionary = {}
	var floor: Dictionary = _buckets.get(floor_id,{})
	for key: Vector2i in _keys(rect):
		var bucket: Bucket = floor.get(key)
		if bucket==null:
			continue
		for record: Record in bucket.records:
			if record.boundary==_boundary and not record.id in ignored_ids and rect.intersects(record.rect,false):
				found[record.id] = true
	var result: Array[String] = []
	result.assign(found.keys())
	result.sort()
	return result

func rectangle(id: String) -> Rect2:
	return (_records[id] as Record).rect

func _keys(rect: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x: int in range(floori(rect.position.x/bucket_cells.x),floori(rect.end.x/bucket_cells.x)+1):
		for y: int in range(floori(rect.position.y/bucket_cells.y),floori(rect.end.y/bucket_cells.y)+1):
			result.append(Vector2i(x,y))
	return result
