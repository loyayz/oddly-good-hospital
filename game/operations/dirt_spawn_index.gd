extends RefCounted

# Rebuildable current-state lookups, never saved. Only the active world's
# layout is retained, with at most eight sparse floor views and no cell grid.
# Geometry edits use the building owner's existing revision boundary.
var _layout: Dictionary = {}
var _dirt: Dictionary = {}

func layout(world: WorldState, space: HospitalSpace, floor_id: int) -> Dictionary:
	var facilities: Dictionary = world.facts.facilities
	var overrides: Dictionary = world.facts.floors.overrides
	if _layout.is_empty() or _layout.world.get_ref()!=world or _layout.revision!=world.geometry_revision or not is_same(_layout.facilities,facilities) or _layout.count!=facilities.size() or not is_same(_layout.overrides,overrides):
		_layout = {"world":weakref(world),"revision":world.geometry_revision,"facilities":facilities,"count":facilities.size(),"overrides":overrides,"empty_floor":{},"floors":{}}
	var floor_data: Dictionary = overrides.get(str(floor_id),_layout.empty_floor)
	var view: Dictionary = _layout.floors.get(floor_id,{})
	if view.is_empty() or not is_same(view.floor_data,floor_data):
		view = {"floor_data":floor_data,"points":{},"index":BodyIndex.new()}
		for cell: Array in floor_data.get("blocked",[]): view.points[_point(cell)] = true
		for door: Dictionary in floor_data.get("doors",[]): view.points[_point(door.cell)] = true
		for id: String in facilities:
			_count(space,"facility_visits")
			var facility: Dictionary = facilities[id]
			if int(facility.get("floor_id",-1))!=floor_id or facility.get("location","floor")=="inventory": continue
			var rect: Rect2 = Rect2(_point(facility.cell),_point(facility.get("footprint",[1,1])))
			view.index.update(id,floor_id,rect)
			for cell: Array in facility.get("operator_cells",[]): view.points[_point(cell)] = true
			for field: String in ["patient_cell","repair_cell"]:
				if not facility.get(field,[]).is_empty(): view.points[_point(facility[field])] = true
		_count(space,"layout_builds")
	# Insertion order is LRU. No historical layouts or rejected candidates are
	# retained; each native record represents one live facility rectangle.
	_layout.floors.erase(floor_id)
	_layout.floors[floor_id] = view
	if _layout.floors.size()>8: _layout.floors.erase(_layout.floors.keys()[0])
	return view

func dirt(world: WorldState, space: HospitalSpace) -> Dictionary:
	if not _dirt_current(world):
		_dirt = {"world":weakref(world),"revision":world.geometry_revision,"records":world.facts.environment.dirt,"count":world.facts.environment.dirt.size(),"sources":{},"bins":{},"points":{},"plots":{}}
		for patch: Dictionary in world.facts.environment.dirt.values():
			_count(space,"dirt_visits")
			_add(patch)
		_count(space,"dirt_builds")
	return _dirt

func inserted(world: WorldState, patch: Dictionary) -> void:
	# spawn_dirt already acquired the view before committing this one record.
	_add(patch)
	_dirt.count = world.facts.environment.dirt.size()

func removing(world: WorldState, patch: Dictionary) -> void:
	# Cleanup may finish without any spawn having prepared this owner's view.
	if not _dirt_current(world):
		_dirt = {}
		return
	var kinds: Dictionary = _dirt.sources[str(patch.source_kind)]
	var ids: Array = kinds[str(patch.source_id)]
	ids.erase(str(patch.id))
	if ids.is_empty(): kinds.erase(str(patch.source_id))
	if kinds.is_empty(): _dirt.sources.erase(str(patch.source_kind))
	if str(patch.bin_id).is_empty():
		_decrement(_dirt.points,int(patch.floor_id),_point(patch.cell))
	else:
		var bins: Array = _dirt.bins[str(patch.bin_id)]
		bins.erase(str(patch.id))
		if bins.is_empty(): _dirt.bins.erase(str(patch.bin_id))
	_decrement(_dirt.plots,int(patch.floor_id),plot_key(patch.cell))
	_dirt.count -= 1

func _dirt_current(world: WorldState) -> bool:
	return not _dirt.is_empty() and _dirt.world.get_ref()==world and _dirt.revision==world.geometry_revision and is_same(_dirt.records,world.facts.environment.dirt) and _dirt.count==world.facts.environment.dirt.size()

func _add(patch: Dictionary) -> void:
	# Restored inputs can contain several tasks with the same source. Keep
	# their original first-ID choice, even after its actual cleanup removes it.
	var kinds: Dictionary = _dirt.sources.get_or_add(str(patch.source_kind),{})
	kinds.get_or_add(str(patch.source_id),[]).append(str(patch.id))
	if str(patch.bin_id).is_empty():
		_increment(_dirt.points,int(patch.floor_id),_point(patch.cell))
	else:
		_dirt.bins.get_or_add(str(patch.bin_id),[]).append(str(patch.id))
	_increment(_dirt.plots,int(patch.floor_id),plot_key(patch.cell))

func _increment(floors: Dictionary, floor_id: int, key: Variant) -> void:
	var cells: Dictionary = floors.get_or_add(floor_id,{})
	cells[key] = int(cells.get(key,0))+1

func _decrement(floors: Dictionary, floor_id: int, key: Variant) -> void:
	var cells: Dictionary = floors[floor_id]
	cells[key] -= 1
	if cells[key]==0: cells.erase(key)
	if cells.is_empty(): floors.erase(floor_id)

func plot_key(cell: Array) -> String:
	# Preserve the original integer division and complete integer coordinates.
	return "%d:%d" % [int(cell[0])/32,int(cell[1])/32]

func _point(cell: Array) -> Vector2:
	return Vector2(float(cell[0]),float(cell[1]))

func _count(space: HospitalSpace, name: String) -> void:
	var key: String = "dirt_spawn_"+name
	space.query_counts[key] = int(space.query_counts.get(key,0))+1
