extends NavigationCache

var timings: Dictionary = {}

func graph(space: HospitalSpace, world: WorldState, floor_id: int, actor: Dictionary, members: Array, offsets: Dictionary) -> FloorNavigation:
	var started: int = Time.get_ticks_usec()
	var key: String = str(world.get_instance_id())+":"+str(floor_id)+":"+_envelope(space,world,actor,members,offsets)
	var entry: Dictionary = _entries.get(key,{})
	var source: Dictionary = floor_source(space,world,floor_id)
	var category: String = "cold_group" if members.size()>1 else "cold_single"
	if not entry.is_empty():
		category = "repair" if entry.source!=source else "hit"
	var result: FloorNavigation = super.graph(space,world,floor_id,actor,members,offsets)
	var elapsed: int = Time.get_ticks_usec()-started
	var record: Dictionary = timings.get(category,{"calls":0,"usec":0,"max_usec":0})
	record.calls += 1
	record.usec += elapsed
	record.max_usec = maxi(int(record.max_usec),elapsed)
	timings[category] = record
	return result
