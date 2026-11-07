extends HospitalPublicAreas

# Exact frozen baseline method. All inherited helpers are unchanged.
func _waiting_point(world: WorldState, actor_id: String, reference: Dictionary, maximum_travel_ticks: int) -> Dictionary:
	var area: Dictionary = region(world,reference)
	if area.is_empty(): return {}
	var actor: Dictionary = world.facts.actors[actor_id]
	var floor_id: int = int(reference.floor_id)
	if contains(world,reference,actor_id) and safe_wait(world,actor_id,floor_id,actor.location.cell):
		return {"floor_id":floor_id,"cell":actor.location.cell.duplicate(),"travel_ticks":0}
	var origin: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	var bounds: Dictionary = space.read_view(world,"public_entry_landings:"+actor_id+":"+str(floor_id),_entry_landings.bind(world,actor_id,floor_id))
	# Every complete cross-floor estimate must first reach a connector anchor
	# on this floor. With no complete landing estimate, trying every area cell
	# cannot produce one either, even when the common prefix is unknown.
	# This rejects only this read-only query; a later exit change is rechecked.
	if int(actor.location.floor_id)!=floor_id and bounds.landings.is_empty(): return {}
	if not bounds.landings.is_empty() and not bounds.unknown:
		var earliest: int = 9223372036854775807
		for landing: Dictionary in bounds.landings: earliest = mini(earliest,int(landing.ticks))
		if earliest>maximum_travel_ticks: return {}
	var geometry: Dictionary = _entry_geometry_view(world,actor,area)
	var ordered: Dictionary = _entry_order(actor,origin,bounds,geometry,maximum_travel_ticks)
	var packed: PackedInt64Array = ordered.packed
	var fallback: Array = ordered.fallback
	var compact: bool = ordered.compact
	var entry_count: int = packed.size() if compact else fallback.size()
	if entry_count==0: return {}
	var best: Dictionary = {}
	var field: Dictionary = {}
	var full_quotes: int = 0
	var next_field_check: int = 0
	var offset_ticks: int = int(ordered.get("offset_ticks",0))
	for index: int in entry_count:
		var lower: int
		var point: Vector2i
		if compact:
			var key: int = packed[index]
			var cell_id: int = key%ENTRY_CELL_COUNT
			lower = key/ENTRY_CELL_COUNT+offset_ticks
			point = Vector2i(cell_id%ENTRY_GRID_WIDTH,cell_id/ENTRY_GRID_WIDTH)
		else:
			lower = int(fallback[index].lower)
			point = fallback[index].cell
		if lower>maximum_travel_ticks: break
		if not best.is_empty() and lower>int(best.travel_ticks): break
		if not _safe_wait_at(world,actor_id,floor_id,point,Vector2(point),actor,geometry): continue
		if field.is_empty() and full_quotes>=next_field_check:
			field = space.navigation.ready_waiting_cost_field(world,actor_id,floor_id,bounds)
			next_field_check = full_quotes+12
		var travel_ticks: int = -1
		if not field.is_empty():
			# The complete resident field is borrowed only by this synchronous
			# loop. safe_wait does not acquire graphs or trim their cache; no
			# navigation query runs while this local array is being consumed.
			space.query_counts["public_entry_field_hits"] = int(space.query_counts.get("public_entry_field_hits",0))+1
			var distance: int = field.distances[FloorNavigation._id(point)]
			if distance<0: continue
			travel_ticks = HospitalTransit._add(int(field.prefix_ticks),ceili(float(distance)/float(field.speed)/WorldState.TICK_SECONDS))
		else:
			var leg: Dictionary = space.navigation.waiting_travel_ticks(world,actor_id,floor_id,point,bounds)
			full_quotes += 1
			if not leg.is_empty(): travel_ticks = int(leg.travel_ticks)
			else:
				var route: Dictionary = space.travel_quote(world,actor_id,floor_id,[point.x,point.y])
				if route.ok and route.has("travel_ticks"): travel_ticks = int(route.travel_ticks)
		if travel_ticks>=0 and travel_ticks<=maximum_travel_ticks and (best.is_empty() or travel_ticks<int(best.travel_ticks)): best = {"floor_id":floor_id,"cell":[point.x,point.y],"travel_ticks":travel_ticks}
	return best
