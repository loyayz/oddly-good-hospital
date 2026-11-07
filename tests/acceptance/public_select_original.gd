extends HospitalPublicAreas

# Frozen pre-optimization select body; its real geometry, collisions, routes
# and availability helpers remain production code. No fabricated route result.
# Source public_areas.gd SHA256:
# 5642782f1cb44249158a9ca40874faaebeb6a53b6faa0ae3a5462cb56fcc36ee

func select(world: WorldState, actor_id: String, definitions: Array, room_kinds: Array, purpose: String, members: Array = [], maximum_travel_ticks: int = 9223372036854775807, selected_entries: Dictionary = {}, current_floor_only: bool = false) -> Dictionary:
	_ensure(world)
	var actor: Dictionary = world.facts.actors[actor_id]
	if actor.location.kind!="floor": return {}
	var best: Dictionary = {}
	var best_entries: Dictionary = {}
	var travellers: Array = [actor_id] if members.is_empty() else members
	var body_key: String = ""
	# Rest and return-to-waiting also permit a safe standing region without furniture.
	var candidates: Array = _regions if purpose in ["rest","waiting"] else _candidate_regions(definitions)
	space.query_counts["public_select_regions_total"] = int(space.query_counts.get("public_select_regions_total",0))+_regions.size()
	space.query_counts["public_select_regions_visited"] = int(space.query_counts.get("public_select_regions_visited",0))+candidates.size()
	# The caller may already own this unchanged, real-body enumeration. Its
	# actor index is reusable; this child still gets independent query views.
	space.begin_dynamic_route_query(world,not space.in_dynamic_route_query(world))
	for area: Dictionary in candidates:
		if current_floor_only and int(area.ref.floor_id)!=int(actor.location.floor_id): continue
		var room: Dictionary = world.facts.rooms.get(area.ref.room_id,{})
		if not room.is_empty() and (not str(room.get("kind",room.get("type",""))) in room_kinds or HospitalRemodel.blocked(world,area.ref.room_id)): continue
		if room.is_empty() and not "" in room_kinds: continue
		var local: Array = facilities(world,area.ref,definitions)
		if not local.is_empty() and body_key.is_empty(): body_key = _body_key(world,travellers)
		local = local.filter(func(id: String)->bool:
			if _geometry_fits.get(id,{}).get(body_key,true)==false: return false
			if maximum_travel_ticks<9223372036854775807 and space.facility_travel_lower_bound_ticks(world,id,actor_id)>maximum_travel_ticks: return false
			var definition: Dictionary = space.content.facility_definition(world.facts.facilities[id].definition_id)
			var capacity: Dictionary = definition.get("adapter_capacity",definition)
			for member: String in travellers:
				var body: Dictionary = world.facts.actors[member]
				if space.clearance(body)>int(capacity.get("max_clearance_cells",96)) or float(space.body(body).height_m)>float(capacity.get("max_height_m",INF)): return false
			return true)
		if local.is_empty() and not purpose in ["rest","waiting"]: continue
		var inside: bool = contains(world,area.ref,actor_id)
		var waiting: int = _wait_estimate(world,area.ref,local,purpose)
		var travel_limit: int = maximum_travel_ticks
		if not best.is_empty():
			if purpose in ["water","toilet"]:
				if waiting>int(best.start_ticks): continue
				travel_limit = mini(travel_limit,int(best.start_ticks)-waiting)
			else:
				if best.inside and not inside: continue
				if inside==bool(best.inside): travel_limit = mini(travel_limit,int(best.travel_ticks))
		# Equal bounds remain candidates: the original stable area tie-break
		# and the slowest member's actual journey still decide the winner.
		var point: Dictionary = waiting_point(world,actor_id,area.ref,travel_limit)
		if point.is_empty(): continue
		var entries: Dictionary = {actor_id:point.duplicate(true)}
		var all_reachable: bool = true
		for member: String in travellers:
			if member==actor_id: continue
			var entry: Dictionary = waiting_point(world,member,area.ref,travel_limit)
			if entry.is_empty(): all_reachable = false; break
			entries[member] = entry
			point.travel_ticks = maxi(int(point.travel_ticks),int(entry.travel_ticks))
		if not all_reachable: continue
		point.area = area.ref.duplicate(true)
		point.inside = inside
		point.start_ticks = int(point.travel_ticks)+waiting
		if best.is_empty() or _earlier(point,best,purpose):
			best = point
			best_entries = entries
	space.end_route_query()
	selected_entries.merge(best_entries,true)
	return best
