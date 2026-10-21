extends "res://tests/acceptance/public_region_build.gd"

const RegionBuild = preload("res://tests/acceptance/public_region_build.gd")

# Count real cell traversal/hash builds, not calls to the region getter or the
# small source comparison. The frozen independent traversal checks all output.
class BuildCounts extends HospitalPublicAreas:
	var builds: Array = []
	func _derive_floor(floor_id: int, layout: Dictionary, rooms: Array, facilities: Array, connectors: Array) -> Dictionary:
		builds.append(floor_id)
		return super._derive_floor(floor_id,layout,rooms,facilities,connectors)

func run_case(database: HospitalContent) -> Dictionary:
	_content = database
	var x: Dictionary = _build_fixture()
	var actual_space: HospitalSpace = HospitalSpace.new(_content)
	var reference_space: HospitalSpace = HospitalSpace.new(_content)
	var actual: BuildCounts = BuildCounts.new(actual_space)
	var reference: HospitalPublicAreas = RegionBuild.ReferenceAreas.new(reference_space)
	var checks: Dictionary = {"valid_input":x.world.validate(_content).is_empty()}
	var observations: Array = [_observe("cold_two_floors",x.world,actual,reference,[1,2])]
	var ground: Dictionary = actual._by_facility.west_chair
	var upper: Dictionary = actual._by_facility.upper_west_chair
	# A broad owner notification, a metadata change and an explicit invalidation
	# retain the same actual region inputs; none may rerun cell traversal.
	x.world.touch()
	observations.append(_observe("unrelated_geometry_revision",x.world,actual,reference,[]))
	checks.identical_regions_retain_identity = is_same(ground,actual._by_facility.west_chair) and is_same(upper,actual._by_facility.upper_west_chair)
	x.world.facts.facilities.west_chair.failed = true
	x.world.touch()
	observations.append(_observe("failure_is_not_membership",x.world,actual,reference,[]))
	checks.failed_still_in_complete_membership = actual._by_facility.west_chair.facilities.has("west_chair")
	actual.invalidate()
	reference.invalidate()
	observations.append(_observe("explicit_invalidation_same_source",x.world,actual,reference,[]))
	# A real single-floor obstacle changes connectivity and keeps the other
	# floor's original region object, component order and facility association.
	x.world.facts.floors.overrides["1"].blocked.append([37,70])
	x.world.touch()
	observations.append(_observe("ground_obstacle",x.world,actual,reference,[1]))
	checks.only_ground_replaced = not is_same(ground,actual._by_facility.west_chair) and is_same(upper,actual._by_facility.upper_west_chair) and actual._cell_region(1,Vector2i(37,70)).is_empty()
	# The explicit legal room-cell representation is an input independently of
	# its rectangular shorthand, and must be frozen rather than aliased to facts.
	var room: Dictionary = x.world.facts.rooms.west
	var room_type: Dictionary = _content.definition("build_room_types","rest")
	var room_shape: Dictionary = BuildGeometry.shape(room,room_type.min_inner_size)
	checks.explicit_room_shape_is_legal = room_shape.ok
	if room_shape.ok:
		room.kind = "rest"
		room.room_type_id = "rest"
		room.cells = room_shape.cells
		room.wall_edges = room_shape.wall_edges
	x.world.touch()
	observations.append(_observe("explicit_room_cells",x.world,actual,reference,[1]))
	var quote: Dictionary = _bed_expansion(x)
	checks.real_adaptation_available = not quote.is_empty()
	if not quote.is_empty():
		var base: Dictionary = x.world.facts.facilities[BED]
		x.world.facts.adaptations[BED] = quote
		x.space.reservation_changed(x.world,BED)
		actual.facility_changed(base,quote)
		reference.facility_changed(base,quote)
		observations.append(_observe("actual_bed_adaptation_without_geometry_revision",x.world,actual,reference,[1]))
		checks.actual_footprint_and_patient_cell = _footprint_excluded(actual,1,base.cell,quote.footprint) and actual._by_facility.get(BED,{}).get("ref",{})==actual._cell_region(1,Vector2i(quote.patient_cell[0],quote.patient_cell[1])).get("ref",{})
		x.world.facts.adaptations.erase(BED)
		x.space.reservation_changed(x.world,BED)
		actual.facility_changed(quote,base)
		reference.facility_changed(quote,base)
		observations.append(_observe("actual_adaptation_release",x.world,actual,reference,[1]))
	# A real connector consumes its footprint on every actual stop, including
	# an upper floor. Stored/removal transitions must not retain those obstacles.
	var connector: Dictionary = _connector()
	checks.connector_definition_available = not connector.is_empty()
	if not connector.is_empty():
		x.world.facts.connectors[connector.id] = connector
		x.world.touch()
		observations.append(_observe("connector_on_both_stops",x.world,actual,reference,[1,2]))
		checks.connector_blocks_both_floors = actual._cell_region(1,Vector2i(55,80)).is_empty() and actual._cell_region(2,Vector2i(55,80)).is_empty()
		connector.stored = true
		x.world.touch()
		observations.append(_observe("stored_connector",x.world,actual,reference,[1,2]))
		checks.stored_connector_no_longer_blocks = not actual._cell_region(1,Vector2i(55,80)).is_empty() and not actual._cell_region(2,Vector2i(55,80)).is_empty()
		x.world.facts.connectors.erase(connector.id)
		x.world.touch()
		observations.append(_observe("remove_already_stored_connector",x.world,actual,reference,[]))
	observations.append(_observe("lazy_sparse_upper_floor",x.world,actual,reference,[3],3))
	checks.lazy_floor_is_bounded = actual._floor_regions.size()==3 and not actual._cell_region(3,Vector2i(32,64)).is_empty() and actual._cell_region(3,Vector2i(0,0)).is_empty()
	x.world.touch()
	observations.append(_observe("refresh_preserves_original_lazy_membership",x.world,actual,reference,[]))
	checks.unrequested_lazy_floor_dropped = actual._floor_regions.keys()==[1,2] and not actual._derived_floors.has(3)
	var old_ground: Dictionary = actual._by_facility.west_chair
	var other: WorldState = WorldState.new(x.world.freeze())
	observations.append(_observe("other_world_same_values",other,actual,reference,[1,2]))
	checks.world_identity_isolated = not is_same(old_ground,actual._by_facility.west_chair) and actual._world.get_ref()==other and actual._floor_regions.size()==2
	observations.append(_observe("return_to_original_world",x.world,actual,reference,[1,2]))
	checks.only_latest_world_is_retained = actual._world.get_ref()==x.world and actual._floor_regions.size()==2
	var high_floors: Dictionary = _high_floor_keys(x.world)
	var ok: bool = true
	for passed: bool in checks.values(): ok = ok and passed
	for observation: Dictionary in observations: ok = ok and observation.ok
	var result: Dictionary = {"ok":ok and high_floors.ok,"checks":checks,"observations":observations,"actual_floor_traversals":actual.builds,"full_width_floor_identity":high_floors,"scope":"Legal region-calculation boundaries; no movement, arrival or service completion is simulated."}
	x.a.dispose()
	x.p.waiting_life = null
	x.p.environment = null
	x.e.waiting_life = null
	x.l.environment = null
	x.l.visitors = null
	x.c.recruitment = null
	x.clear()
	return result

func _high_floor_keys(world: WorldState) -> Dictionary:
	var original: Dictionary = world.freeze()
	var high: WorldState = WorldState.new(original.duplicate(true))
	var first: int = 2147483649
	var second: int = 4294967297
	# A completed sparse structural interval is a legal calculation input. No
	# intermediate floors, fake journeys or per-floor world copies are created.
	high.facts.floors.completed_top_floor["1:2"] = second
	for floor_id: int in [first,second]:
		high.facts.floors.overrides[str(floor_id)] = {"blocked":[],"doors":[]}
	high.touch()
	var actual_space: HospitalSpace = HospitalSpace.new(_content)
	var reference_space: HospitalSpace = HospitalSpace.new(_content)
	var actual: BuildCounts = BuildCounts.new(actual_space)
	var reference: HospitalPublicAreas = RegionBuild.ReferenceAreas.new(reference_space)
	var observations: Array = [_observe("sparse_floors_above_int32_and_uint32",high,actual,reference,[1,2,first,second])]
	var point: Vector2i = Vector2i(35,82)
	var ground: Dictionary = actual._cell_region(1,point)
	var a: Dictionary = actual._cell_region(first,point)
	var b: Dictionary = actual._cell_region(second,point)
	var checks: Dictionary = {"same_xy_keeps_complete_floor_identity":not ground.is_empty() and not a.is_empty() and not b.is_empty() and int(ground.ref.floor_id)==1 and int(a.ref.floor_id)==first and int(b.ref.floor_id)==second and not is_same(ground,a) and not is_same(ground,b) and not is_same(a,b)}
	checks.floor_map_is_the_only_cell_index = is_same(a,actual._floor_regions[first].by_cell.get(point,{})) and is_same(b,actual._floor_regions[second].by_cell.get(point,{}))
	var before: Dictionary = high.freeze()
	checks.public_reference_lookup_preserves_high_floor = is_same(actual.region(high,a.ref),a) and is_same(actual.region(high,b.ref),b) and before==high.freeze()
	high.touch()
	observations.append(_observe("high_floor_unrelated_revision",high,actual,reference,[]))
	checks.unchanged_high_floor_objects_are_reused = is_same(a,actual._cell_region(first,point)) and is_same(b,actual._cell_region(second,point))
	high.facts.floors.overrides[str(first)].blocked.append([point.x,point.y])
	high.touch()
	observations.append(_observe("high_floor_local_obstacle",high,actual,reference,[first]))
	checks.high_floor_change_never_aliases_ground_or_other_high_floor = actual._cell_region(first,point).is_empty() and is_same(ground,actual._cell_region(1,point)) and is_same(b,actual._cell_region(second,point))
	high.facts.floors.overrides.erase(str(first))
	high.touch()
	observations.append(_observe("removed_high_floor_releases_index",high,actual,reference,[]))
	checks.removed_high_floor_has_no_stale_cells = not actual._floor_regions.has(first) and actual._cell_region(first,point).is_empty() and is_same(b,actual._cell_region(second,point))
	var other: WorldState = WorldState.new(high.freeze())
	observations.append(_observe("same_high_facts_different_world",other,actual,reference,[1,2,second]))
	checks.other_world_owns_new_cell_map = actual._world.get_ref()==other and not is_same(b,actual._cell_region(second,point)) and int(actual._cell_region(second,point).get("ref",{}).get("floor_id",0))==second
	checks.original_world_and_rng_unchanged = original==world.freeze()
	return {"ok":not checks.values().has(false) and observations.all(func(row: Dictionary)->bool:return row.ok),"checks":checks,"observations":observations,"actual_floor_traversals":actual.builds}

func _observe(label: String, world: WorldState, actual: BuildCounts, reference: HospitalPublicAreas, expected: Array, requested_floor: int = 0) -> Dictionary:
	var begin: int = actual.builds.size()
	var result: Dictionary = _compare_build(label,world,actual,reference,requested_floor)
	var traversals: Array = actual.builds.slice(begin)
	var memberships: bool = true
	for region: Dictionary in actual._regions:
		var expected_index: Dictionary = {}
		for number: int in region.facilities.size():
			var definition: String = world.facts.facilities[region.facilities[number]].definition_id
			var positions: PackedInt32Array = expected_index.get(definition,PackedInt32Array())
			positions.append(number)
			expected_index[definition] = positions
		memberships = memberships and region.facility_definitions==expected_index
	var validation: String = world.validate(_content)
	result.ok = result.ok and traversals==expected and memberships and validation.is_empty()
	result.floor_traversals = traversals
	result.expected_floor_traversals = expected
	result.complete_definition_membership_equal = memberships
	result.validation = validation
	return result

func _connector() -> Dictionary:
	for definition: Dictionary in _content.catalog.vertical_connectors:
		if definition.kind!="stairs": continue
		return {"id":"region_lifecycle_stairs","definition_id":definition.id,"anchor":[55,80],"cell":[55,80],"footprint":definition.footprint.duplicate(),"floor_id":1,"stops":[1,2],"phase":"idle","riders":[],"remaining_ticks":0}
	return {}
