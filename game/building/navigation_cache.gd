class_name NavigationCache
extends RefCounted

var _entries: Dictionary = {}
var _sources: Dictionary = {}
var _used: int = 0
var _charged: int = 0
var _source_version: int = 0

func invalidate(world: WorldState, floor_id: int) -> void:
	var key: String = str(world.get_instance_id())+":"+str(floor_id)
	_sources.erase(key)

func floor_source(space: HospitalSpace, world: WorldState, floor_id: int) -> Dictionary:
	var key: String = str(world.get_instance_id())+":"+str(floor_id)
	var entry: Dictionary = _sources.get(key,{})
	if entry.is_empty() or entry.revision!=world.revision:
		var current: Dictionary = RouteClearance.capture_source(space,world,floor_id)
		if entry.is_empty() or entry.source!=current:
			_source_version += 1
			entry = {"source":current,"world":weakref(world),"version":_source_version}
		entry.revision = world.revision
		_sources[key] = entry
	return entry.source

func floor_version(space: HospitalSpace, world: WorldState, floor_id: int) -> int:
	floor_source(space,world,floor_id)
	return int(_sources[str(world.get_instance_id())+":"+str(floor_id)].version)

func graph(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, members: Array, offsets: Dictionary) -> FloorNavigation:
	var key: String = str(world.get_instance_id())+":"+str(floor_id)+":"+_envelope(space,world,actor,members,offsets)
	var source: Dictionary = floor_source(space,world,floor_id)
	var entry: Dictionary = _entries.get(key,{})
	_used += 1
	if entry.is_empty() or entry.source!=source:
		var geometry: RouteClearance = RouteClearance.new(space,world,actor,floor_id,members,offsets,false,source)
		var bases: Array[FloorNavigation] = []
		var shifts: Array[Vector2i] = []
		if members.size()>1:
			var ids: Array = [actor.id]
			for id: String in members:
				if id!=actor.id:
					ids.append(id)
			for id: String in ids:
				var offset: Array = offsets.get(id,[0,0])
				if float(offset[0])!=floor(float(offset[0])) or float(offset[1])!=floor(float(offset[1])) or absf(float(offset[0]))>=96 or absf(float(offset[1]))>=96:
					shifts.clear()
					break
				shifts.append(Vector2i(int(offset[0]),int(offset[1])))
			if shifts.size()==ids.size():
				for id: String in ids:
					bases.append(graph(space,world,floor_id,world.facts.actors[id],[],{}))
		var floor_graph: FloorNavigation
		if entry.is_empty():
			floor_graph = FloorNavigation.new(geometry,bases,shifts)
		else:
			floor_graph = entry.graph
			floor_graph.refresh(geometry,bases,shifts)
		# Recursive constituent lookups may have evicted this older group entry.
		if _entries.has(key):
			_charged -= int(_entries[key].charge)
		# Capacity charge includes native points/adjacency and projection containers.
		# This is an eviction allowance, not a measured Release allocation count.
		var charge: int = floor_graph.get_point_count()*2048+var_to_bytes(source).size()*8+16384
		entry = {"graph":floor_graph,"source":source,"used":_used,"charge":charge,"world":weakref(world),"floor_key":str(world.get_instance_id())+":"+str(floor_id)}
		_entries[key] = entry
		_charged += charge
	entry.used = _used
	var result: FloorNavigation = entry.graph
	_trim(int(space.content.balance.pathfinding.graph_cache_target_bytes))
	return result

func _trim(target: int) -> void:
	var keys: Array = _entries.keys()
	keys.sort_custom(func(a: String,b: String) -> bool:
		return int(_entries[a].used)<int(_entries[b].used) if _entries[a].used!=_entries[b].used else a<b)
	for key: String in keys:
		var entry: Dictionary = _entries[key]
		if _charged<=target and entry.world.get_ref()!=null:
			continue
		_charged -= int(entry.charge)
		_entries.erase(key)
	var retained: Dictionary = {}
	for entry: Dictionary in _entries.values():
		retained[entry.floor_key] = true
	for key: String in _sources.keys():
		if not retained.has(key):
			_sources.erase(key)

func _envelope(space: HospitalSpace, world: WorldState, actor: Dictionary, members: Array, offsets: Dictionary) -> String:
	var shapes: Array = [[space.body(actor),actor.get("posture","standing"),[0,0]]]
	for id: String in members:
		if id!=actor.id:
			shapes.append([space.body(world.facts.actors[id]),world.facts.actors[id].get("posture","standing"),offsets[id]])
	return JSON.stringify(shapes,"",true,true)
