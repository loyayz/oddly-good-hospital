extends RefCounted

func run_case(suite: RefCounted) -> Dictionary:
	var x: Dictionary = suite._areas()
	suite._facility(x,"membership_chair","FUR09",[39,68],"west")
	suite._facility(x,"membership_light","FUR19",[40,71],"west")
	suite._facility(x,"membership_bin","FUR24",[40,74],"west")
	x.world.touch()
	var area: Dictionary = x.space.public_areas.for_facility(x.world,"west_chair")
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
	var geometry: int = x.world.geometry_revision
	x.world.facts.facilities.membership_chair.failed = true
	x.world.touch(false)
	var failed: Dictionary = _observe(x,area,["FUR09"])
	checks.current_failure_does_not_become_static_membership = failed.ok and not "membership_chair" in failed.actual and geometry==x.world.geometry_revision
	x.world.facts.facilities.membership_chair.failed = false
	x.world.touch(false)
	var restored: Dictionary = _observe(x,area,["FUR09"])
	checks.same_layout_recovery_is_immediate = restored.ok and "membership_chair" in restored.actual
	x.world.facts.facilities.membership_chair = x.world.facts.facilities.membership_chair.duplicate(true)
	checks.same_identity_record_replacement_reads_current_facts = _observe(x,area,["FUR09"]).ok
	x.world.facts.facilities.erase("membership_chair")
	x.world.touch()
	var removed: Dictionary = _observe(x,area,["FUR09"])
	checks.geometry_removal_rebuilds_membership = removed.ok and not "membership_chair" in removed.actual
	var previous: WorldState = x.world
	x.world = WorldState.new(previous.freeze())
	checks.other_world_rebuilds_original_membership = _observe(x,area,["FUR19","FUR09"]).ok
	# Release the fixture's service graph; observations retain only value results.
	x.a.dispose()
	x.p.environment = null
	x.p.waiting_life = null
	x.l.environment = null
	x.l.visitors = null
	x.c.recruitment = null
	x.clear()
	return {"ok":not checks.values().has(false),"checks":checks,"observations":rows,"failed":failed,"restored":restored,"removed":removed}

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
