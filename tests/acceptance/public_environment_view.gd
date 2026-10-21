extends "res://tests/acceptance/public_area_use.gd"

# The reference reads original facts in source order. It does not consume the
# production view, its floor rows or its spatial index.
func _literal_rows(world: WorldState, floor_id: int) -> Array:
	var result: Array = []
	for facility: Dictionary in world.facts.facilities.values():
		if int(facility.floor_id)==floor_id:
			result.append([facility.cell,"facility",[facility.id,facility.definition_id,facility.get("level",1),facility.get("failed",false)]])
	for collection: String in ["surfaces","dirt"]:
		for record: Dictionary in world.facts.get("environment",{}).get(collection,{}).values():
			if int(record.floor_id)!=floor_id or collection=="dirt" and not str(record.get("bin_id","")).is_empty(): continue
			result.append([record.cell,collection,record])
	for session: Dictionary in world.facts.sessions.values():
		if not session.kind in ["outpatient","surgery","operate"]: continue
		var facility: Dictionary = world.facts.facilities.get(session.get("facility_id",""),{})
		if not facility.is_empty() and int(facility.floor_id)==floor_id:
			result.append([facility.cell,"machine",[facility.definition_id,facility.get("failed",false)]])
	for order: Dictionary in world.facts.get("environment",{}).get("orders",{}).values():
		if int(order.floor_id)!=floor_id or order.get("paused",false): continue
		for unit: Dictionary in order.get("units",[]):
			if unit.get("phase","")=="working" and not str(unit.get("worker_id","")).is_empty():
				result.append([unit.cell,"construction",unit.get("worker_id","")])
	for order: Dictionary in world.facts.get("maintenance",{}).get("upgrades",{}).values():
		if order.get("phase","")!="working": continue
		var facility: Dictionary = world.facts.facilities.get(order.get("facility_id",""),{})
		if not facility.is_empty() and int(facility.floor_id)==floor_id:
			result.append([facility.cell,"upgrade",facility.id])
	return result

func _literal_samples(world: WorldState, floor_id: int, points: Array) -> Array:
	var result: Array = []
	for row: Array in _literal_rows(world,floor_id):
		for point: Array in points:
			if absf(float(row[0][0])-float(point[0]))+absf(float(row[0][1])-float(point[1]))<=8.0:
				result.append(row)
				break
	return result

func _observe(x: Dictionary, points: Array, floor_id: int = 1) -> Dictionary:
	var before: Dictionary = x.world.freeze()
	var view: Dictionary = x.space.public_areas._decision_view(x.world)
	var expected: Array = _literal_samples(x.world,floor_id,points)
	var actual: Array = x.space.public_areas._environment_samples(view,floor_id,points)
	return {"ok":actual==expected and before==x.world.freeze(),"expected":expected,"actual":actual,"view":view,"readonly":before==x.world.freeze()}

func run_case(database: HospitalContent) -> Dictionary:
	_content = database
	var x: Dictionary = _areas()
	var areas: HospitalPublicAreas = x.space.public_areas
	var anchor: Array = x.world.facts.facilities.west_chair.cell.duplicate()
	var other: Array = x.world.facts.facilities.east_chair.cell.duplicate()
	var checks: Dictionary = {}
	var cases: Array = [[],[anchor],[anchor,anchor],[anchor,other],[[anchor[0]+8.0,anchor[1]]],[[anchor[0]+8.000001,anchor[1]]],[[anchor[0]+4.25,anchor[1]+3.75]],[[anchor[0]-0.25,anchor[1]+8.25]]]
	var exact: bool = true
	var observations: Array = []
	for points: Array in cases:
		var observed: Dictionary = _observe(x,points)
		exact = exact and observed.ok
		observations.append({"points":points,"equal":observed.ok,"count":observed.actual.size()})
	checks.full_enumeration_exact_boundaries_and_source_order = exact
	var first: Dictionary = areas._decision_view(x.world)
	var retained: Dictionary = first.facility_environment
	var index: BodyIndex = retained.indices[1]
	var builds: int = int(x.space.query_counts.get("facility_environment_builds",0))
	var hits: int = int(x.space.query_counts.get("facility_environment_hits",0))
	var repeated: bool = true
	for _iteration: int in 3:
		areas.changed(x.world)
		var observed: Dictionary = _observe(x,[anchor,other])
		repeated = repeated and observed.ok and is_same(observed.view.facility_environment,retained) and is_same(observed.view.facility_environment.indices[1],index) and not is_same(observed.view,first)
	checks.changed_rebuilds_dynamic_view_and_reuses_static_index = repeated and int(x.space.query_counts.get("facility_environment_builds",0))==builds and int(x.space.query_counts.get("facility_environment_hits",0))>hits
	x.world.facts.sim_tick += 1
	x.world.touch(false)
	var next_tick: Dictionary = _observe(x,[anchor,other])
	checks.next_tick_reuses_static_index = next_tick.ok and is_same(next_tick.view.facility_environment,retained) and is_same(next_tick.view.facility_environment.indices[1],index)
	var facility: Dictionary = x.world.facts.facilities.west_chair
	facility.level = 2
	facility.failed = true
	var live: Dictionary = _observe(x,[anchor])
	checks.same_tick_live_level_and_failure = live.ok and live.actual.has([anchor,"facility",[facility.id,facility.definition_id,2,true]]) and is_same(live.view.facility_environment,retained) and int(x.space.query_counts.get("facility_environment_builds",0))==builds
	var replacement: Dictionary = facility.duplicate(true)
	replacement.level = 3
	replacement.failed = false
	x.world.facts.facilities.west_chair = replacement
	var replaced_record: Dictionary = _observe(x,[anchor])
	checks.same_identity_record_replacement_reads_current_fields = replaced_record.ok and replaced_record.actual.has([anchor,"facility",[replacement.id,replacement.definition_id,3,false]]) and is_same(replaced_record.view.facility_environment,retained)
	checks.frozen_origin_has_no_fact_alias = not is_same(retained.rows[1][0][0],replacement.cell)
	# These are legal layout inputs for the observer calculation. A layout edit
	# uses the same geometry invalidation boundary as the real building owner.
	replacement.cell = [38,70]
	x.world.touch()
	var moved: Dictionary = _observe(x,[anchor,replacement.cell,other])
	checks.layout_move_rebuilds_static_positions_and_index = moved.ok and not is_same(moved.view.facility_environment,retained) and not is_same(moved.view.facility_environment.indices[1],index) and moved.actual.has([replacement.cell,"facility",[replacement.id,replacement.definition_id,3,false]]) and not moved.actual.has([anchor,"facility",[replacement.id,replacement.definition_id,3,false]])
	retained = moved.view.facility_environment
	# Source replacement/count checks also protect newly supplied calculation
	# inputs before their first query, without scanning every record on a hit.
	_facility(x,"extra_chair","FUR09",[40,74],"west")
	var added: Dictionary = _observe(x,[[40,74]])
	checks.append_rebuilds_source = added.ok and not is_same(added.view.facility_environment,retained) and int(added.view.facility_environment.count)==x.world.facts.facilities.size()
	retained = added.view.facility_environment
	x.world.facts.facilities.erase("extra_chair")
	var removed: Dictionary = _observe(x,[[40,74]])
	checks.remove_rebuilds_source = removed.ok and not is_same(removed.view.facility_environment,retained) and int(removed.view.facility_environment.count)==x.world.facts.facilities.size()
	retained = removed.view.facility_environment
	x.world.facts.facilities = x.world.facts.facilities.duplicate(true)
	var replaced_source: Dictionary = _observe(x,[replacement.cell,other])
	checks.replaced_source_rebuilds_at_same_count_and_tick = replaced_source.ok and not is_same(replaced_source.view.facility_environment,retained) and is_same(replaced_source.view.facility_environment.records,x.world.facts.facilities)
	retained = replaced_source.view.facility_environment
	# A ground patch is created by its production owner; it is dynamic even
	# when no static facility moves. Other active source kinds are independently
	# enumerated above and covered by the actual clinical/operations cases.
	var patch_id: String = x.e.spawn_dirt(x.world,"CL01","environment_view_source","environment_view_source:1",1,[42,76])
	areas.changed(x.world)
	var dirty: Dictionary = _observe(x,[[42,76]])
	var dirty_rows: Array = dirty.actual.filter(func(row: Array) -> bool: return row[1]=="dirt")
	checks.dynamic_source_append_is_current = not patch_id.is_empty() and dirty.ok and dirty_rows.size()==1
	if not patch_id.is_empty():
		var patch: Dictionary = x.world.facts.environment.dirt[patch_id]
		var before_dynamic: Dictionary = dirty.view.facility_environment
		patch.remaining_milli = maxi(1,int(patch.remaining_milli)-1)
		areas.changed(x.world)
		var current: Dictionary = _observe(x,[patch.cell])
		checks.dynamic_same_tick_state_refresh_reuses_static_index = current.ok and is_same(current.view.facility_environment,before_dynamic) and not is_same(current.view,dirty.view)
		x.world.facts.environment.dirt.erase(patch_id)
		areas.changed(x.world)
		var cleaned: Dictionary = _observe(x,[patch.cell])
		checks.dynamic_source_removal_is_current = cleaned.ok and cleaned.actual.filter(func(row: Array) -> bool: return row[1]=="dirt").is_empty() and is_same(cleaned.view.facility_environment,before_dynamic)
	else:
		checks.dynamic_same_tick_state_refresh_reuses_static_index = false
		checks.dynamic_source_removal_is_current = false
	retained = areas._decision_view(x.world).facility_environment
	var copied: Dictionary = x.duplicate()
	copied.world = WorldState.new(x.world.freeze())
	var switched: Dictionary = _observe(copied,[[38,70],other])
	checks.other_world_rebuilds_and_releases_previous_source = switched.ok and not is_same(switched.view.facility_environment,retained) and is_same(switched.view.facility_environment.records,copied.world.facts.facilities) and is_same(areas._decision_basis,switched.view) and switched.view.facility_environment.indices.size()==1
	var empty_floor: Dictionary = _observe(copied,[[38,70]],2)
	checks.empty_floor_does_not_accumulate_index = empty_floor.ok and empty_floor.actual.is_empty() and switched.view.facility_environment.indices.size()==1
	return {"ok":not checks.values().has(false),"checks":checks,"sample_cases":observations,"facility_environment_builds":x.space.query_counts.get("facility_environment_builds",0),"facility_environment_hits":x.space.query_counts.get("facility_environment_hits",0)}
