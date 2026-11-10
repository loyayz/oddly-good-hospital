extends RefCounted

# Current positions only. The environment owner updates one completed surface or
# dirt record; restore/collection replacement rebuilds once. No histories or facts
# copies are retained. Buckets hold identities so values are always read live.
var _views: Dictionary = {}

func sources(world: WorldState, space: HospitalSpace, collection: String) -> Dictionary:
	var records: Dictionary = world.facts.get("environment",{}).get(collection,{})
	var view: Dictionary = _views.get(collection,{})
	if not _current(view,world,records):
		view = {"world":weakref(world),"records":records,"count":records.size(),"floors":{},"members":{},"bounds":{}}
		_views[collection] = view
		for id: String in records:
			_add(view,collection,id,records[id])
		_count(space,collection+"_source_builds",1)
		_count(space,collection+"_source_visits",records.size())
	else:
		_count(space,collection+"_source_hits",1)
	return view.floors

# Bounds are conservative after removal: they only skip proven empty regions,
# never determine an observation value. Each live floor keeps one bounded rect;
# its last source removal clears it. No scan is needed to shrink an extent.
func bounds(collection: String) -> Dictionary:
	return _views[collection].bounds

func written(world: WorldState, space: HospitalSpace, collection: String, id: String) -> void:
	var view: Dictionary = _views.get(collection,{})
	var records: Dictionary = world.facts.environment[collection]
	# A cold owner need not build just to publish a change. An unexpected raw
	# replacement/count mismatch is reacquired by the next real observation.
	if not _owner(view,world,records) or records.size()!=int(view.count)+(0 if view.members.has(id) else 1):
		_views.erase(collection)
		return
	_remove(view,id)
	_add(view,collection,id,records[id])
	view.count = records.size()
	_count(space,collection+"_source_updates",1)

func removing(world: WorldState, space: HospitalSpace, collection: String, id: String) -> void:
	var view: Dictionary = _views.get(collection,{})
	if not _current(view,world,world.facts.environment[collection]):
		_views.erase(collection)
		return
	_remove(view,id)
	view.count -= 1
	_count(space,collection+"_source_updates",1)

func _owner(view: Dictionary, world: WorldState, records: Dictionary) -> bool:
	return not view.is_empty() and view.world.get_ref()==world and is_same(view.records,records)

func _current(view: Dictionary, world: WorldState, records: Dictionary) -> bool:
	return _owner(view,world,records) and int(view.count)==records.size()

func _add(view: Dictionary, collection: String, id: String, record: Dictionary) -> void:
	view.members[id] = null
	if collection=="surfaces" and record.surface!="wall" or collection=="dirt" and not str(record.bin_id).is_empty(): return
	var floor_id: int = int(record.floor_id)
	var key: Variant = _cell_key(record.cell)
	var cells: Dictionary = view.floors.get_or_add(floor_id,{})
	cells.get_or_add(key,[]).append(id)
	if not view.bounds.has(floor_id): view.bounds[floor_id] = Rect2i()
	if view.bounds[floor_id]!=null:
		if not key is Vector2i:
			view.bounds[floor_id] = null
		else:
			var previous: Rect2i = view.bounds[floor_id]
			var point: Rect2i = Rect2i(key,Vector2i.ONE)
			view.bounds[floor_id] = previous.merge(point) if previous.has_area() else point
	view.members[id] = {"floor":floor_id,"key":key}

func _remove(view: Dictionary, id: String) -> void:
	if not view.members.has(id): return
	var member: Variant = view.members[id]
	view.members.erase(id)
	if member==null: return
	var cells: Dictionary = view.floors[member.floor]
	var records: Array = cells[member.key]
	records.erase(id)
	if records.is_empty(): cells.erase(member.key)
	if cells.is_empty():
		view.floors.erase(member.floor)
		view.bounds.erase(member.floor)

func _cell_key(cell: Array) -> Variant:
	var x: int = int(cell[0])
	var y: int = int(cell[1])
	return Vector2i(x,y) if x>=0 and y>=0 and x<96 and y<96 else "%d:%d" % [x,y]

func _count(space: HospitalSpace, name: String, amount: int) -> void:
	var key: String = "environment_"+name
	space.query_counts[key] = int(space.query_counts.get(key,0))+amount
