extends "res://tests/acceptance/environment_cache_scope.gd"

const RawQuery = preload("res://tests/acceptance/environment_direct_reference.gd")
var _door_observations: Array = []

func run_direct_cases(database: HospitalContent, selected: Array) -> Dictionary:
	_content = database
	var cases: Dictionary = {"ENV-DIRECT-VALUES":_values,"ENV-DIRECT-SCOPES":_scopes,"ENV-DIRECT-LIVE":_live,"ENV-DIRECT-DOOR":_direct_door}
	var rows: Dictionary = {}
	for id: String in selected:
		if not cases.has(id): return {"ok":false,"unknown_case":id}
		rows[id] = cases[id].call()
	return {"ok":not rows.is_empty() and rows.values().all(func(row: Dictionary)->bool:return row.ok),"cases":rows}

func _canonical(value: Dictionary) -> Dictionary:
	var result: Dictionary = value.duplicate(true)
	# Explanatory order is not a business contract; retain all records and fields.
	result.sources.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return JSON.stringify(a)<JSON.stringify(b))
	return result

func _reference_for(x: Dictionary) -> HospitalEnvironment:
	var result: HospitalEnvironment = RawQuery.new(_content,HospitalSpace.new(_content))
	result.waiting_life = x.get("l")
	return result

func _compare_direct(x: Dictionary, reference: HospitalEnvironment, cell: Array, actor_id: String = "", floor_id: int = 1) -> Dictionary:
	var before: Dictionary = x.world.freeze()
	var actual: Dictionary = x.e.environment_at(x.world,floor_id,cell,actor_id)
	var brief: Dictionary = x.e.sample_at(x.world,floor_id,cell,actor_id)
	var expected: Dictionary = reference.environment_at(x.world,floor_id,cell,actor_id)
	var expected_brief: Dictionary = reference.sample_at(x.world,floor_id,cell,actor_id)
	var equal: bool = _canonical(actual)==_canonical(expected) and brief==expected_brief
	return {"ok":equal and before==x.world.freeze(),"cell":cell,"floor_id":floor_id,"value":actual.value,"noise":actual.noise,"dirt":actual.dirt,"water":actual.water,"nearby":actual.nearby_count,"complete_fields_equal":equal,"readonly":before==x.world.freeze()}

func _coverage_matches(x: Dictionary, origin: Array, noise: bool = false) -> bool:
	# Inherited actual door movement/JSON restore now exercises both public reads
	# before checking the independent raw-fact propagation distances and order.
	var reference: HospitalEnvironment = _reference_for(x)
	var compared: Dictionary = _compare_direct(x,reference,origin)
	_door_observations.append({"tick":x.world.sim_tick,"held":not x.world.facts.adaptations.is_empty(),"value":compared.value})
	return compared.ok and x.e._query.is_empty() and x.e._query_depth==0 and super._coverage_matches(x,origin,noise)

func _seed_door_sources(x: Dictionary) -> void:
	# Legal completed wall finish before movement: the adjacent wall edge is
	# closed initially, becomes an actual opening, then returns on release.
	var helper: RefCounted = preload("res://tests/acceptance/environment_source_intersection.gd").new()
	helper._content = _content
	helper._surface(x,[37,79],"south","MAT08")

func _direct_door() -> Dictionary:
	_door_observations = []
	var result: Dictionary = super._door()
	var held: int = 0
	var closed: int = 0
	var equal: bool = true
	for row: Dictionary in _door_observations:
		if row.held: held += 1
		else: closed += 1
		equal = equal and int(row.value)==(43 if row.held else 53)
	result.checks.direct_score_tracks_real_opening_and_restore = equal and held>1 and closed>1
	result.direct_observations = _door_observations
	result.ok = result.ok and result.checks.direct_score_tracks_real_opening_and_restore
	return result

func _values() -> Dictionary:
	var x: Dictionary = _fixture({"subject":"doctor","neighbor":"nurse"})
	HospitalFactory._add_room(x.world,{"id":"room","type":"waiting","anchor":[40,72],"size":[12,12],"door":{"definition_id":"DR04","offset":3}},_content)
	_facility(x,"plant","FUR25",[42,79],"room")
	_facility(x,"light","FUR19",[46,80],"room")
	_facility(x,"screen","FUR23",[44,82],"room")
	_position(x,"subject",[44,80]);_position(x,"neighbor",[45,80])
	var helper: RefCounted = preload("res://tests/acceptance/environment_source_intersection.gd").new()
	helper._content = _content
	helper._surface(x,[42,72],"north","MAT05");helper._surface(x,[44,80],"","MAT02")
	x.world.touch()
	var reference: HospitalEnvironment = _reference_for(x)
	var rows: Array = []
	for dx: int in range(-4,5):
		for dy: int in range(-4,5): rows.append(_compare_direct(x,reference,[44+dx,80+dy],"subject"))
	for cell: Array in [[44.25,80.75],[43.99,80.01],[0,0],[95,95]]: rows.append(_compare_direct(x,reference,cell,"subject"))
	rows.append(_compare_direct(x,reference,[44,80],"subject",2))
	var checks: Dictionary = {"legal_input":x.world.validate(_content).is_empty(),"all_observation_fields_match":rows.all(func(row: Dictionary)->bool:return row.ok),"all_direct_scopes_close":x.e._query_depth==0 and x.e._query.is_empty()}
	var reads: int = _count(x.space,"coverage_source_checks")
	var calls: int = _count(x.space,"coverage_native_calls")
	var builds: int = x.e.query_builds
	var before: Dictionary = x.world.freeze()
	for _repeat: int in 200: x.e.sample_at(x.world,1,[44,80],"subject")
	checks.warm_direct_reads_reuse_static_sources = _count(x.space,"coverage_source_checks")==reads
	checks.warm_direct_reads_reuse_coverage = _count(x.space,"coverage_native_calls")==calls
	checks.each_direct_read_closes_its_own_batch = x.e.query_builds==builds+200 and x.e._query_depth==0 and x.e._query.is_empty() and x.world.freeze()==before
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"rows":rows,"warm_queries":200,"warm_source_checks":_count(x.space,"coverage_source_checks")-reads,"warm_coverage_calls":_count(x.space,"coverage_native_calls")-calls}
	Coverage.new()._dispose(x)
	return result

func _scopes() -> Dictionary:
	var x: Dictionary = _fixture()
	_facility(x,"plant","FUR25",[43,80]);x.world.touch()
	var reference: HospitalEnvironment = _reference_for(x)
	var expected: Dictionary = reference.sample_at(x.world,1,[44,80])
	x.e.begin_query(x.world);x.e.begin_query(x.world)
	var parent: Dictionary = x.e._query
	var builds: int = x.e.query_builds
	var actual: Dictionary = x.e.sample_at(x.world,1,[44,80])
	var outside: Dictionary = x.e.environment_at(x.world,1,[0,0])
	var checks: Dictionary = {"legal_input":x.world.validate(_content).is_empty(),"same_world_nested_read_keeps_parent":actual==expected and x.e.query_builds==builds and x.e._query_depth==2 and is_same(parent,x.e._query),"nested_early_return_keeps_parent":outside.status=="outside_owned_floor" and x.e._query_depth==2 and is_same(parent,x.e._query)}
	var foreign: WorldState = WorldState.new(x.world.freeze())
	foreign.facts.floors.overrides["1"].blocked.append([43,80]);foreign.touch()
	var foreign_expected: Dictionary = reference.sample_at(foreign,1,[44,80])
	var foreign_actual: Dictionary = x.e.sample_at(foreign,1,[44,80])
	checks.other_world_read_does_not_replace_parent_scope = foreign_actual==foreign_expected and foreign_expected.value!=expected.value and x.e._query_depth==2 and is_same(parent,x.e._query) and x.e.query_builds==builds
	x.e.end_query();x.e.end_query()
	checks.closed_parent_does_not_seed_other_world_coverage = x.e.sample_at(foreign,1,[44,80])==foreign_expected
	checks.original_world_reacquires_its_own_coverage = x.e.sample_at(x.world,1,[44,80])==expected
	builds = x.e.query_builds
	outside = x.e.sample_at(x.world,1,[0,0])
	checks.direct_early_return_closes_scope = outside.status=="outside_owned_floor" and x.e.query_builds==builds+1 and x.e._query_depth==0 and x.e._query.is_empty()
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"original_value":expected.value,"other_world_value":foreign_expected.value}
	Coverage.new()._dispose(x)
	return result

func _live() -> Dictionary:
	var x: Dictionary = _fixture({"subject":"doctor","neighbor":"nurse"})
	_facility(x,"plant","FUR25",[42,79]);_facility(x,"light","FUR19",[42,82]);_facility(x,"water","FUR17",[50,80]);_facility(x,"screen","FUR23",[48,84])
	x.world.touch();_position(x,"subject",[44,80]);_position(x,"neighbor",[45,80])
	x.e.waiting_life = x.l
	var reference: HospitalEnvironment = _reference_for(x)
	var rows: Array = [_compare_direct(x,reference,[44,80],"subject")]
	var first: Dictionary = x.e.sample_at(x.world,1,[44,80],"subject")
	x.world.facts.facilities.light.failed = true
	rows.append(_compare_direct(x,reference,[44,80],"subject"))
	var checks: Dictionary = {"same_tick_failure_is_live":x.e.sample_at(x.world,1,[44,80],"subject").value==int(first.value)-7}
	x.world.facts.facilities.light = x.world.facts.facilities.light.duplicate(true);x.world.facts.facilities.light.failed = false
	rows.append(_compare_direct(x,reference,[44,80],"subject"))
	checks.same_identity_replacement_is_live = x.e.sample_at(x.world,1,[44,80],"subject")==first
	var available: Dictionary = x.e.sample_at(x.world,1,[48,80],"subject")
	_position(x,"neighbor",x.space.facility_layout(x.world,"water").patient_cell)
	rows.append(_compare_direct(x,reference,[48,80],"subject"))
	checks.water_occupancy_is_live = available.water and not x.e.sample_at(x.world,1,[48,80],"subject").water
	_position(x,"neighbor",[45,80])
	var near: int = x.e.environment_at(x.world,1,[44,80],"subject").nearby_count
	_position(x,"neighbor",[60,80]);rows.append(_compare_direct(x,reference,[44,80],"subject"))
	checks.nearby_people_are_live = near==1 and x.e.environment_at(x.world,1,[44,80],"subject").nearby_count==0
	var patch_id: String = x.e.spawn_dirt(x.world,"CL01","direct_patch","direct_patch:1",1,[44,82])
	rows.append(_compare_direct(x,reference,[44,82],"subject"))
	var dirty: Dictionary = x.e.sample_at(x.world,1,[44,82],"subject")
	x.world.facts.environment.dirt.erase(patch_id)
	rows.append(_compare_direct(x,reference,[44,82],"subject"))
	checks.dynamic_dirt_add_remove_is_live = not patch_id.is_empty() and dirty.dirt==1 and x.e.sample_at(x.world,1,[44,82],"subject").dirt==0
	x.world.facts.facilities.screen.rotation = 1;x.world.touch()
	rows.append(_compare_direct(x,reference,[48,85],"subject"))
	x.world.facts = x.world.freeze().duplicate(true)
	rows.append(_compare_direct(x,reference,[44,80],"subject"))
	x.world = WorldState.new(x.world.freeze())
	rows.append(_compare_direct(x,reference,[44,80],"subject"))
	checks.all_dynamic_restore_and_layout_fields_match = rows.all(func(row: Dictionary)->bool:return row.ok)
	checks.no_scope_or_fact_leaks = x.e._query_depth==0 and x.e._query.is_empty() and x.world.validate(_content).is_empty()
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"rows":rows}
	reference.waiting_life = null;x.e.waiting_life = null
	Coverage.new()._dispose(x)
	return result
