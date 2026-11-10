extends RefCounted

# Clinical owners publish membership changes. This is a rebuildable position
# projection, not a second work state: local consumers still read current facts.
var _view: Dictionary = {}
var _definitions: Dictionary = {}

func sources(world: WorldState, space: HospitalSpace, definitions: Array) -> Dictionary:
	if _definitions.is_empty():
		for id: String in definitions: _definitions[id] = true
	var records: Dictionary = world.facts.sessions
	if not _current(world,records):
		_view = {"world":weakref(world),"records":records,"count":records.size(),"members":{},"facilities":{},"floors":{},"bounds":{},"geometry":world.geometry_revision,"facility_records":world.facts.facilities}
		for id: String in records: _add(world,space,id,records[id])
		_count(space,"source_builds",1)
		_count(space,"source_visits",records.size())
	else:
		# A structural edit may replace/move a facility. Revisit only installed
		# noisy candidates, not every clinical session or each source on each read.
		if _view.geometry!=world.geometry_revision or not is_same(_view.facility_records,world.facts.facilities):
			for facility_id: String in _view.facilities.keys(): layout_changed(world,space,facility_id)
			_view.geometry = world.geometry_revision
			_view.facility_records = world.facts.facilities
		_count(space,"source_hits",1)
	return _view.floors

func bounds() -> Dictionary:
	return _view.bounds

func observed_empty(world: WorldState) -> void:
	# The authoritative empty collection already proves absence. Retain a warm
	# empty owner for its next notification, but discard an unnotified raw clear.
	if not _view.is_empty() and int(_view.count)!=0 and _view.world.get_ref()==world: _view = {}

func written(world: WorldState, space: HospitalSpace, id: String) -> void:
	var records: Dictionary = world.facts.sessions
	if not _owner(world,records) or records.size()!=int(_view.count)+(0 if _view.members.has(id) else 1):
		_view = {}
		return
	_remove(id)
	_add(world,space,id,records[id])
	_view.count = records.size()
	_count(space,"source_updates",1)

func removing(world: WorldState, space: HospitalSpace, id: String) -> void:
	if not _current(world,world.facts.sessions):
		_view = {}
		return
	_remove(id)
	_view.count -= 1
	_count(space,"source_updates",1)

func layout_changed(world: WorldState, space: HospitalSpace, facility_id: String) -> void:
	if not _owner(world,world.facts.sessions): return
	var ids: Array = _view.facilities.get(facility_id,{}).keys()
	for id: String in ids:
		_remove(id)
		if world.facts.sessions.has(id): _add(world,space,id,world.facts.sessions[id])
	if not ids.is_empty(): _count(space,"layout_updates",ids.size())

func _owner(world: WorldState, records: Dictionary) -> bool:
	return not _view.is_empty() and _view.world.get_ref()==world and is_same(_view.records,records)

func _current(world: WorldState, records: Dictionary) -> bool:
	return _owner(world,records) and int(_view.count)==records.size() and is_same(_view.facility_records,world.facts.facilities)

func _add(world: WorldState, space: HospitalSpace, id: String, record: Dictionary) -> void:
	# Excluded kinds are still members. Their insertion/removal must not make a
	# warmed source view mistake a known local change for untracked replacement.
	_view.members[id] = null
	if not record.kind in ["outpatient","surgery","operate"]: return
	var facility: Dictionary = world.facts.facilities.get(str(record.facility_id),{})
	if facility.is_empty() or not _definitions.has(str(facility.definition_id)): return
	var layout: Dictionary = space.facility_layout(world,str(facility.id))
	var floor_id: int = int(facility.floor_id)
	var keys: Array = []
	var cells: Dictionary = _view.floors.get_or_add(floor_id,{})
	for x: int in range(int(facility.cell[0]),int(facility.cell[0])+int(layout.footprint[0])):
		for y: int in range(int(facility.cell[1]),int(facility.cell[1])+int(layout.footprint[1])):
			var key: Variant = Vector2i(x,y) if x>=0 and y>=0 and x<96 and y<96 else "%d:%d" % [x,y]
			cells.get_or_add(key,[]).append(id)
			keys.append(key)
			_expand_bound(floor_id,key)
	_view.facilities.get_or_add(str(facility.id),{})[id] = true
	_view.members[id] = {"floor":floor_id,"keys":keys,"facility":str(facility.id)}

func _remove(id: String) -> void:
	if not _view.members.has(id): return
	var member: Variant = _view.members[id]
	_view.members.erase(id)
	if member==null: return
	var facilities: Dictionary = _view.facilities[member.facility]
	facilities.erase(id)
	if facilities.is_empty(): _view.facilities.erase(member.facility)
	var cells: Dictionary = _view.floors[member.floor]
	for key: Variant in member.keys:
		var ids: Array = cells[key]
		ids.erase(id)
		if ids.is_empty(): cells.erase(key)
	if cells.is_empty():
		_view.floors.erase(member.floor)
		_view.bounds.erase(member.floor)

func _expand_bound(floor_id: int, key: Variant) -> void:
	# Removal retains a conservative extent until the last source leaves. This
	# avoids a source scan to shrink bounds and cannot skip a real observation.
	if not _view.bounds.has(floor_id): _view.bounds[floor_id] = Rect2i()
	if _view.bounds[floor_id]==null: return
	if not key is Vector2i:
		_view.bounds[floor_id] = null
		return
	var previous: Rect2i = _view.bounds[floor_id]
	var point: Rect2i = Rect2i(key,Vector2i.ONE)
	_view.bounds[floor_id] = previous.merge(point) if previous.has_area() else point

func _count(space: HospitalSpace, name: String, amount: int) -> void:
	var key: String = "environment_session_"+name
	space.query_counts[key] = int(space.query_counts.get(key,0))+amount
