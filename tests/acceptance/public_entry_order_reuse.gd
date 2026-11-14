extends RefCounted

class OrderProbe extends HospitalPublicAreas:
	var builds: int = 0
	func _ordered_entry_cells(actor: Dictionary, origin: Vector2, bounds: Dictionary, geometry: Dictionary, maximum_travel_ticks: int) -> Dictionary:
		builds += 1
		return super._ordered_entry_cells(actor,origin,bounds,geometry,maximum_travel_ticks)

func run_case(suite: RefCounted) -> Dictionary:
	var x: Dictionary = suite._areas()
	var visit: Dictionary = suite._visit(x,"entry_order_owner",[38,90])
	var peer: Dictionary = suite._visit(x,"entry_order_peer",[42,90])
	var actor: Dictionary = x.world.facts.actors[visit.actor_id]
	var probe: OrderProbe = OrderProbe.new(x.space)
	x.space.public_areas = probe
	var before: Dictionary = x.world.freeze()
	var corpus: Dictionary = _complete_order_corpus(x,actor)
	var alternating: Dictionary = _two_recent_bases(x,probe,actor)
	var readonly: bool = before==x.world.freeze()
	var reference: Dictionary = probe.for_facility(x.world,"west_chair")
	var area: Dictionary = probe.region(x.world,reference)
	var original: Dictionary = probe._entry_geometry_view(x.world,actor,area)
	var shared: Dictionary = probe._entry_geometry_view(x.world,x.world.facts.actors[peer.actor_id],area)
	var first: Dictionary = _compare_owner(x,probe,actor,original)
	x.world.facts.floors.overrides["1"].blocked.append([37,70])
	x.world.touch()
	area = probe.region(x.world,reference)
	var changed: Dictionary = probe._entry_geometry_view(x.world,actor,area)
	var replaced: bool = not is_same(original,changed) and changed.ordering.is_empty() and changed.previous_ordering.is_empty()
	var second: Dictionary = _compare_owner(x,probe,actor,changed)
	var result: Dictionary = {"ok":corpus.ok and alternating.ok and readonly and is_same(original,shared) and first.ok and replaced and second.ok and x.space._route_queries.is_empty(),"complete_native_and_original_orders":corpus,"two_recent_basis_lifecycle":alternating,"same_body_other_identity_shares_static_preparation":is_same(original,shared),"cold_static_owner":first,"real_static_change_replaces_owner_and_both_slots":replaced,"changed_static_owner":second,"calculation_leaves_facts_and_rng_unchanged":readonly,"closed_scopes":x.space._route_queries.is_empty(),"scope":"Complete candidate ordering calculations. Actual legal selection, arrival and use remain STAFF-75's independent full-cell reference and movement cases."}
	x.a.dispose()
	x.p.waiting_life = null
	x.p.environment = null
	x.l.environment = null
	x.l.visitors = null
	x.c.recruitment = null
	x.clear()
	return result

func _points() -> Array:
	return [Vector2i(42,76),Vector2i(41,75),Vector2i(40,75),Vector2i(40,74)]

func _geometry(points: Array) -> Dictionary:
	var encoded: PackedInt32Array = PackedInt32Array()
	for point: Vector2i in points: encoded.append(point.y*96+point.x)
	return {"cells":points.duplicate(),"entry_cells":encoded,"native_order":true,"points":{},"ordering":{},"previous_ordering":{}}

func _decoded(ordered: Dictionary, limit: int = HospitalTransit.MAX_TICK) -> Array:
	if not ordered.compact: return ordered.fallback.filter(func(row: Dictionary)->bool:return int(row.lower)<=limit)
	var result: Array = []
	for key: int in ordered.packed:
		var id: int = key%HospitalPublicAreas.ENTRY_CELL_COUNT
		var lower: int = key/HospitalPublicAreas.ENTRY_CELL_COUNT+int(ordered.get("offset_ticks",0))
		if lower>limit: break
		result.append({"cell":Vector2i(id%96,id/96),"lower":lower})
	return result

func _original_order(x: Dictionary, actor: Dictionary, origin: Vector2, bounds: Dictionary, geometry: Dictionary, limit: int) -> Array:
	# Independent literal oracle: never calls the production preparation,
	# native encoder, fallback branch, or either cached-order slot.
	var start := Vector2i(roundi(origin.x),roundi(origin.y))
	var speed: float = float(x.space.content.balance.movement_speeds[str(x.space.clearance(actor))])
	var prefix: int = ceili(origin.distance_to(Vector2(start))/speed/WorldState.TICK_SECONDS)
	var rows: Array = []
	for cell: Vector2i in geometry.cells:
		if geometry.points.get(Vector2(cell),true)==false: continue
		var distance: int = absi(cell.x-start.x)+absi(cell.y-start.y)
		var lower: int = prefix+ceili(float(distance)/speed/WorldState.TICK_SECONDS)
		if not bounds.unknown and not bounds.landings.is_empty():
			lower = HospitalTransit.MAX_TICK
			for landing: Dictionary in bounds.landings:
				distance = absi(cell.x-int(landing.cell.x))+absi(cell.y-int(landing.cell.y))
				var walking: int = ceili(float(distance)/speed/WorldState.TICK_SECONDS)
				lower = mini(lower,int(landing.ticks)+walking)
		if lower<=limit: rows.append({"cell":cell,"lower":lower})
	rows.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		if int(a.lower)!=int(b.lower): return int(a.lower)<int(b.lower)
		return a.cell.y<b.cell.y or a.cell.y==b.cell.y and a.cell.x<b.cell.x)
	return rows

func _complete_order_corpus(x: Dictionary, actor: Dictionary) -> Dictionary:
	var high: int = HospitalTransit.MAX_TICK-2000
	var mixed: int = HospitalPublicAreas.ENTRY_SORT_LIMIT-2
	var cases: Array = [
		{"name":"ordinary_ties","origin":Vector2(38,90),"bounds":{"landings":[],"unknown":false},"limit":HospitalTransit.MAX_TICK,"native":true},
		{"name":"fractional_stub","origin":Vector2(38.35,90.35),"bounds":{"landings":[],"unknown":false},"limit":HospitalTransit.MAX_TICK,"native":true},
		{"name":"empty_budget","origin":Vector2(38,90),"bounds":{"landings":[],"unknown":false},"limit":84,"native":true},
		{"name":"exact_budget","origin":Vector2(38,90),"bounds":{"landings":[],"unknown":false},"limit":85,"native":true},
		{"name":"multiple_weighted_landings","origin":Vector2(38,90),"bounds":{"landings":[{"cell":Vector2(40,75),"ticks":50},{"cell":Vector2(43,75),"ticks":57}],"unknown":false},"limit":HospitalTransit.MAX_TICK,"native":true},
		{"name":"unknown_keeps_walking_bound","origin":Vector2(38,90),"bounds":{"landings":[{"cell":Vector2(40,75),"ticks":500}],"unknown":true},"limit":HospitalTransit.MAX_TICK,"native":true},
		{"name":"known_static_false","origin":Vector2(38,90),"bounds":{"landings":[],"unknown":false},"limit":HospitalTransit.MAX_TICK,"native":true,"excluded":Vector2(40,75)},
		{"name":"fractional_false_does_not_exclude_integer","origin":Vector2(38,90),"bounds":{"landings":[],"unknown":false},"limit":HospitalTransit.MAX_TICK,"native":true,"excluded":Vector2(40.25,75)},
		{"name":"large_finite_int64","origin":Vector2(38,90),"bounds":{"landings":[{"cell":Vector2(40,75),"ticks":high}],"unknown":false},"limit":HospitalTransit.MAX_TICK,"native":false},
		{"name":"mixed_packed_and_int64","origin":Vector2(38,90),"bounds":{"landings":[{"cell":Vector2(40,75),"ticks":mixed}],"unknown":false},"limit":HospitalTransit.MAX_TICK,"native":false}
	]
	var rows: Array = []
	for item: Dictionary in cases:
		var points: Array = [Vector2i(40,75),Vector2i(41,75),Vector2i(40,74),Vector2i(42,76)] if item.name=="mixed_packed_and_int64" else _points()
		var geometry: Dictionary = _geometry(points)
		if item.has("excluded"): geometry.points[item.excluded] = false
		var native_before: int = int(x.space.query_counts.get("entry_order_native_builds",0))
		var actual: Dictionary = x.space.public_areas._ordered_entry_cells(actor,item.origin,item.bounds,geometry,item.limit)
		var expected: Array = _original_order(x,actor,item.origin,item.bounds,geometry,item.limit)
		var native_used: bool = int(x.space.query_counts.get("entry_order_native_builds",0))==native_before+1
		var decoded: Array = _decoded(actual)
		var literal: bool = true
		if item.name=="ordinary_ties": literal = decoded==[{"cell":Vector2i(40,75),"lower":85},{"cell":Vector2i(40,74),"lower":90},{"cell":Vector2i(41,75),"lower":90},{"cell":Vector2i(42,76),"lower":90}]
		if item.name=="exact_budget": literal = decoded==[{"cell":Vector2i(40,75),"lower":85}]
		if item.name=="empty_budget": literal = decoded.is_empty()
		rows.append({"ok":decoded==expected and native_used==bool(item.native) and literal,"case":item.name,"all_candidates_and_order_match_original":decoded==expected,"native_used":native_used,"expected_native":item.native,"literal_boundary":literal,"decoded":decoded})
	# The full 96x96 literal grid catches lost far points, duplicate keys and
	# y/x tie changes. It does not impose a nearest-N or travel-time cap.
	var complete: Array = []
	for y: int in 96:
		for px: int in 96: complete.append(Vector2i(px,y))
	var geometry: Dictionary = _geometry(complete)
	var bounds: Dictionary = {"landings":[{"cell":Vector2(0,0),"ticks":17},{"cell":Vector2(95,95),"ticks":23}],"unknown":false}
	var actual: Dictionary = x.space.public_areas._ordered_entry_cells(actor,Vector2(38,90),bounds,geometry,HospitalTransit.MAX_TICK)
	var expected: Array = _original_order(x,actor,Vector2(38,90),bounds,geometry,HospitalTransit.MAX_TICK)
	var all_cells: bool = _decoded(actual)==expected and actual.packed.size()==9216
	return {"ok":all_cells and rows.all(func(row: Dictionary)->bool: return row.ok),"literal_small_boundaries":rows,"complete_grid_9216_cells_and_total_order":all_cells}

func _two_recent_bases(x: Dictionary, probe: OrderProbe, actor: Dictionary) -> Dictionary:
	var geometry: Dictionary = _geometry(_points())
	var bounds: Dictionary = {"landings":[],"unknown":false}
	var origins: Array = [Vector2(38,90),Vector2(39,90),Vector2(38,90),Vector2(40,90),Vector2(38,90),Vector2(39,90)]
	var builds: Array = [1,1,0,1,0,1]
	var rows: Array = []
	var walking_before: int = int(x.space.query_counts.get("entry_walking_table_builds",0))
	for index: int in origins.size():
		var before: int = probe.builds
		var actual: Dictionary = probe._entry_order(actor,origins[index],bounds,geometry,HospitalTransit.MAX_TICK)
		var expected: Array = _original_order(x,actor,origins[index],bounds,geometry,HospitalTransit.MAX_TICK)
		rows.append({"ok":_decoded(actual)==expected and probe.builds-before==int(builds[index]),"origin":origins[index],"new_builds":probe.builds-before,"expected_builds":builds[index]})
	var walking_builds: int = int(x.space.query_counts.get("entry_walking_table_builds",0))-walking_before
	var unchanged_walking: bool = walking_builds==1
	var landing_geometry: Dictionary = _geometry(_points())
	var first_bounds: Dictionary = {"landings":[{"cell":Vector2(40,75),"ticks":50},{"cell":Vector2(43,75),"ticks":57}],"unknown":false}
	probe._entry_order(actor,Vector2(38,90),first_bounds,landing_geometry,HospitalTransit.MAX_TICK)
	var before: int = probe.builds
	var shifted: Dictionary = {"landings":[{"cell":Vector2(40,75),"ticks":91},{"cell":Vector2(43,75),"ticks":98}],"unknown":false}
	var actual: Dictionary = probe._entry_order(actor,Vector2(30.25,80.25),shifted,landing_geometry,96)
	var complete: Array = _original_order(x,actor,Vector2(30.25,80.25),shifted,landing_geometry,HospitalTransit.MAX_TICK)
	var expected: Array = _original_order(x,actor,Vector2(30.25,80.25),shifted,landing_geometry,96)
	var budget_exact: bool = _decoded(actual,96)==expected and expected.size()<complete.size()
	var complete_retained: bool = _decoded(actual)==complete
	var prefix: bool = budget_exact and complete_retained and probe.builds==before and int(actual.offset_ticks)==91
	return {"ok":unchanged_walking and prefix and rows.all(func(row: Dictionary)->bool: return row.ok),"alternating_and_true_eviction":rows,"same_speed_table_retained":unchanged_walking,"same_speed_table_builds":walking_builds,"common_landing_prefix_reuses_complete_order":prefix,"common_landing_exact_budget":budget_exact,"common_landing_retains_every_candidate":complete_retained,"common_landing_no_extra_build":probe.builds==before,"common_landing_actual_prefix":int(actual.get("offset_ticks",-1))}

func _compare_owner(x: Dictionary, probe: OrderProbe, actor: Dictionary, geometry: Dictionary) -> Dictionary:
	var before: Dictionary = x.world.freeze()
	var bounds: Dictionary = {"landings":[],"unknown":false}
	var actual: Dictionary = probe._entry_order(actor,Vector2(38,90),bounds,geometry,HospitalTransit.MAX_TICK)
	var expected: Array = _original_order(x,actor,Vector2(38,90),bounds,geometry,HospitalTransit.MAX_TICK)
	var packed_complete: bool = geometry.entry_cells.size()==geometry.cells.size()
	return {"ok":packed_complete and _decoded(actual)==expected and before==x.world.freeze(),"static_cells_prepared_once_and_complete":packed_complete,"full_order_matches_original":_decoded(actual)==expected,"world_and_rng_unchanged":before==x.world.freeze(),"cells":geometry.cells.size()}
