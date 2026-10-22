extends RefCounted

class FullScanAreas extends HospitalPublicAreas:
	func _candidate_regions(_definitions: Array) -> Array:
		return _regions

func run_case(suite: RefCounted) -> Dictionary:
	var x: Dictionary = suite._areas()
	suite._facility(x,"membership_chair","FUR09",[39,68],"west")
	suite._facility(x,"membership_light","FUR19",[40,71],"west")
	suite._facility(x,"membership_bin","FUR24",[40,74],"west")
	var visit: Dictionary = suite._visit(x,"membership_selection",[38,74])
	x.world.touch()
	var area: Dictionary = x.space.public_areas.for_facility(x.world,"west_chair")
	var reference_space: HospitalSpace = HospitalSpace.new(suite._content)
	var reference: FullScanAreas = FullScanAreas.new(reference_space)
	reference_space.public_areas = reference
	var checks: Dictionary = {}
	checks.valid_input = x.world.validate(suite._content).is_empty()
	var rows: Array = []
	for definitions: Array in [[],["FUR09"],["FUR19","FUR09","FUR19"],["FUR09","FUR19"],["FUR24"],["unknown"]]:
		rows.append(_observe(x,area,definitions))
	checks.original_order_duplicates_empty_and_missing_match_full_enumeration = rows.all(func(row: Dictionary)->bool:return row.ok)
	var region: Dictionary = x.space.public_areas.region(x.world,area)
	var indexed: int = 0
	for positions: PackedInt32Array in region.facility_definitions.values(): indexed += positions.size()
	checks.membership_is_bounded_by_original_region_list = indexed==region.facilities.size()
	var selections: Array = [_selection(x,reference,visit.actor_id,["FUR09","FUR09"],["waiting"],"seat","west",1),_selection(x,reference,visit.actor_id,["unknown"],["waiting"],"seat","",0)]
	checks.real_region_visits_are_reduced = int(selections[0].visited)<int(selections[0].full_pool)
	var geometry_fit: Dictionary = _geometry_fit(x,area,[visit.actor_id])
	checks.compatible_geometry_prepares_body_once = geometry_fit.ok and geometry_fit.actual
	var geometry: int = x.world.geometry_revision
	x.world.facts.facilities.membership_chair.failed = true
	x.world.touch(false)
	var failed: Dictionary = _observe(x,area,["FUR09"])
	checks.current_failure_does_not_become_static_membership = failed.ok and not "membership_chair" in failed.actual and geometry==x.world.geometry_revision
	x.world.facts.facilities.membership_chair.failed = false
	x.world.touch(false)
	var restored: Dictionary = _observe(x,area,["FUR09"])
	checks.same_layout_recovery_is_immediate = restored.ok and "membership_chair" in restored.actual
	selections.append(_selection(x,reference,visit.actor_id,["FUR09"],["waiting"],"seat","west",1))
	# A room purpose is live eligibility, not part of static definition membership.
	x.world.facts.rooms.west.kind = "rest"
	x.world.facts.rooms.west.room_type_id = "rest"
	x.world.touch(false)
	selections.append(_selection(x,reference,visit.actor_id,["FUR09"],["waiting"],"seat","east",1))
	selections.append(_selection(x,reference,visit.actor_id,[],["rest"],"rest","west",0))
	x.world.facts.rooms.west.kind = "waiting"
	x.world.facts.rooms.west.room_type_id = "waiting"
	x.world.touch(false)
	x.world.facts.facilities.membership_chair = x.world.facts.facilities.membership_chair.duplicate(true)
	checks.same_identity_record_replacement_reads_current_facts = _observe(x,area,["FUR09"]).ok
	x.world.facts.facilities.erase("membership_chair")
	x.world.touch()
	var removed: Dictionary = _observe(x,area,["FUR09"])
	checks.geometry_removal_rebuilds_membership = removed.ok and not "membership_chair" in removed.actual
	var previous: WorldState = x.world
	x.world = WorldState.new(previous.freeze())
	checks.other_world_rebuilds_original_membership = _observe(x,area,["FUR19","FUR09"]).ok
	selections.append(_selection(x,reference,visit.actor_id,["FUR09"],["waiting"],"seat","west",1))
	checks.full_scan_choices_entries_and_live_permissions_equal = selections.all(func(row: Dictionary)->bool:return row.ok)
	checks.all_calculation_inputs_remain_legal = x.world.validate(suite._content).is_empty()
	# Release the fixture's service graph; observations retain only value results.
	x.a.dispose()
	x.p.environment = null
	x.p.waiting_life = null
	x.l.environment = null
	x.l.visitors = null
	x.c.recruitment = null
	x.clear()
	return {"ok":not checks.values().has(false),"checks":checks,"observations":rows,"failed":failed,"restored":restored,"removed":removed,"selections":selections,"compatible_geometry":geometry_fit}

func _selection(x: Dictionary, reference: HospitalPublicAreas, actor_id: String, definitions: Array, room_kinds: Array, purpose: String, expected_room: String, expected_preparations: int) -> Dictionary:
	var before: Dictionary = x.world.freeze()
	var counts: Dictionary = x.space.query_counts.duplicate()
	var entries: Dictionary = {}
	var expected_entries: Dictionary = {}
	var actual: Dictionary = x.space.public_areas.select(x.world,actor_id,definitions,room_kinds,purpose,[],9223372036854775807,entries)
	var expected: Dictionary = reference.select(x.world,actor_id,definitions,room_kinds,purpose,[],9223372036854775807,expected_entries)
	var preparations: int = int(x.space.query_counts.get("public_fit_body_key_preparations",0))-int(counts.get("public_fit_body_key_preparations",0))
	var pool: int = int(x.space.query_counts.get("public_select_regions_total",0))-int(counts.get("public_select_regions_total",0))
	var visited: int = int(x.space.query_counts.get("public_select_regions_visited",0))-int(counts.get("public_select_regions_visited",0))
	var right_area: bool = actual.is_empty() if expected_room.is_empty() else actual.get("area",{}).get("room_id","")==expected_room
	return {"ok":actual==expected and entries==expected_entries and right_area and preparations==expected_preparations and (purpose!="rest" or pool==visited) and before==x.world.freeze() and x.space._route_queries.is_empty() and reference.space._route_queries.is_empty(),"purpose":purpose,"definitions":definitions,"expected_room":expected_room,"actual":actual,"full_scan":expected,"full_pool":pool,"visited":visited,"body_key_preparations":preparations,"facts_and_rng_unchanged":before==x.world.freeze()}

func _geometry_fit(x: Dictionary, reference: Dictionary, members: Array) -> Dictionary:
	var before: Dictionary = x.world.freeze()
	var expected: bool = false
	for id: String in x.space.public_areas.facilities(x.world,reference,["FUR09"]):
		if x.space.facility_geometry_quote(x.world,id,members[0],members.slice(1)).ok: expected = true
	var preparations: int = int(x.space.query_counts.get("public_fit_body_key_preparations",0))
	var actual: bool = x.space.public_areas.compatible_geometry(x.world,reference,["FUR09"],members)
	var warm: bool = x.space.public_areas.compatible_geometry(x.world,reference,["FUR09"],members)
	preparations = int(x.space.query_counts.get("public_fit_body_key_preparations",0))-preparations
	return {"ok":actual==expected and warm==expected and preparations==2 and before==x.world.freeze(),"actual":actual,"independent_current_quotes":expected,"two_call_body_key_preparations":preparations,"facts_and_rng_unchanged":before==x.world.freeze()}

func _observe(x: Dictionary, reference: Dictionary, definitions: Array) -> Dictionary:
	var area: Dictionary = x.space.public_areas.region(x.world,reference)
	var expected: Array = []
	var applicable: int = 0
	for id: String in area.get("facilities",[]):
		var record: Dictionary = x.world.facts.facilities[id]
		if not record.definition_id in definitions: continue
		applicable += 1
		if not record.get("failed",false) and not HospitalRemodel.blocked(x.world,id): expected.append(id)
	var before: Dictionary = x.world.freeze()
	var count: int = int(x.space.query_counts.get("public_facility_candidates",0))
	var actual: Array = x.space.public_areas.facilities(x.world,reference,definitions)
	var candidates: int = int(x.space.query_counts.get("public_facility_candidates",0))-count
	return {"ok":actual==expected and before==x.world.freeze() and candidates==applicable,"definitions":definitions,"actual":actual,"expected":expected,"applicable_candidates":candidates,"original_region_records":area.get("facilities",[]).size(),"facts_and_rng_unchanged":before==x.world.freeze()}
