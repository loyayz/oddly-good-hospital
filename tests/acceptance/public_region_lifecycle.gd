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
	checks.only_ground_replaced = not is_same(ground,actual._by_facility.west_chair) and is_same(upper,actual._by_facility.upper_west_chair) and not actual._by_cell.has("1:37:70")
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
		checks.actual_footprint_and_patient_cell = _footprint_excluded(actual,1,base.cell,quote.footprint) and actual._by_facility.get(BED,{}).get("ref",{})==actual._by_cell.get(HospitalPublicAreas._key(1,Vector2i(quote.patient_cell[0],quote.patient_cell[1])),{}).get("ref",{})
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
		checks.connector_blocks_both_floors = not actual._by_cell.has("1:55:80") and not actual._by_cell.has("2:55:80")
		connector.stored = true
		x.world.touch()
		observations.append(_observe("stored_connector",x.world,actual,reference,[1,2]))
		checks.stored_connector_no_longer_blocks = actual._by_cell.has("1:55:80") and actual._by_cell.has("2:55:80")
		x.world.facts.connectors.erase(connector.id)
		x.world.touch()
		observations.append(_observe("remove_already_stored_connector",x.world,actual,reference,[]))
	observations.append(_observe("lazy_sparse_upper_floor",x.world,actual,reference,[3],3))
	checks.lazy_floor_is_bounded = actual._floor_regions.size()==3 and actual._by_cell.has("3:32:64") and not actual._by_cell.has("3:0:0")
	x.world.touch()
	observations.append(_observe("refresh_preserves_original_lazy_membership",x.world,actual,reference,[]))
	checks.unrequested_lazy_floor_dropped = actual._floor_regions.keys()==[1,2] and not actual._derived_floors.has(3)
	var old_ground: Dictionary = actual._by_facility.west_chair
	var other: WorldState = WorldState.new(x.world.freeze())
	observations.append(_observe("other_world_same_values",other,actual,reference,[1,2]))
	checks.world_identity_isolated = not is_same(old_ground,actual._by_facility.west_chair) and actual._world.get_ref()==other and actual._floor_regions.size()==2
	observations.append(_observe("return_to_original_world",x.world,actual,reference,[1,2]))
	checks.only_latest_world_is_retained = actual._world.get_ref()==x.world and actual._floor_regions.size()==2
	var ok: bool = true
	for passed: bool in checks.values(): ok = ok and passed
	for observation: Dictionary in observations: ok = ok and observation.ok
	var result: Dictionary = {"ok":ok,"checks":checks,"observations":observations,"actual_floor_traversals":actual.builds,"scope":"Legal region-calculation boundaries; no movement, arrival or service completion is simulated."}
	x.a.dispose()
	x.p.waiting_life = null
	x.p.environment = null
	x.e.waiting_life = null
	x.l.environment = null
	x.l.visitors = null
	x.c.recruitment = null
	x.clear()
	return result

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
