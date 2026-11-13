extends HospitalSpace

# Exact pre-optimization movement_doors body, isolated test oracle.
func movement_doors(world: WorldState, actor: Dictionary, swept: Rect2, members: Array = [], floor_id: int = 0, geometry: FloorStaticGeometry = null) -> Array[Dictionary]:
	if floor_id==0: floor_id = int(actor.location.floor_id)
	if geometry==null: geometry = _navigation.floor_geometry(self,world,floor_id)
	var entry: Dictionary = {"index":geometry.door_index,"doors":geometry.door_order,"order":geometry.door_order}
	var ids: Dictionary = {}
	# A door may grow from its fixed anchor to fit this body's envelope.
	var reach: float = float(clearance(actor))+1.0
	for id: String in members:
		if is_same(world.facts.actors[id],actor): continue
		reach = maxf(reach,float(clearance(world.facts.actors[id]))+1.0)
	for id: String in entry.index.candidates(floor_id,swept.grow(reach)): ids[id] = true
	for region: Dictionary in _reservation_regions(world,floor_id,swept):
		if region.reservation.kind=="door" and entry.doors.has(region.reservation_id): ids[region.reservation_id] = true
	# All live index and reservation checks above still run. An empty
	# union has no ordering or floor-record projection work to perform.
	if ids.is_empty(): return []
	var ordered: Array = ids.keys()
	ordered.sort_custom(func(a: String,b: String) -> bool: return int(entry.order[a])<int(entry.order[b]))
	var result: Array[Dictionary] = []
	var actual: Array = world.facts.floors.overrides.get(str(floor_id),{}).get("doors",[])
	for id: String in ordered: result.append(actual[int(entry.order[id])])
	query_counts.door_candidates += result.size()
	return result
