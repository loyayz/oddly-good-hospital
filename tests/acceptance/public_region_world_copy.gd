extends "res://tests/acceptance/public_region_build.gd"

class CountingAreas extends HospitalPublicAreas:
	var builds: Array = []
	func _derive_floor(floor_id: int, layout: Dictionary, rooms: Array, facilities: Array, connectors: Array) -> Dictionary:
		builds.append(floor_id)
		return super._derive_floor(floor_id,layout,rooms,facilities,connectors)

func run_case(database: HospitalContent) -> Dictionary:
	_content = database
	var x: Dictionary = _build_fixture()
	var actual_space: HospitalSpace = HospitalSpace.new(database)
	var reference_space: HospitalSpace = HospitalSpace.new(database)
	var actual: CountingAreas = CountingAreas.new(actual_space)
	var reference: HospitalPublicAreas = ReferenceAreas.new(reference_space)
	var checks: Dictionary = {"legal_original":x.world.validate(database).is_empty()}
	var observations: Array = [_compare_build("cold_original",x.world,actual,reference)]
	var old_floor: Dictionary = actual._floor_regions[1]
	var old_area: Dictionary = actual._by_facility.west_chair
	old_area.entry_order_cells = {"probe_only":true}
	actual._entry_geometry["probe_only"] = true
	actual._geometry_fits["probe_only"] = true
	actual._wait_geometry["probe_only"] = true
	var copied: WorldState = WorldState.new(x.world.freeze())
	var before: int = actual.builds.size()
	observations.append(_compare_build("equal_facts_new_owner",copied,actual,reference))
	var area: Dictionary = actual._by_facility.west_chair
	checks.equal_worlds_skip_component_traversal = actual.builds.size()==before
	checks.mutable_region_and_all_indices_have_new_owner = not is_same(old_area,area) and not is_same(old_area.cells,area.cells) and not is_same(old_area.facilities,area.facilities) and not is_same(old_area.facility_definitions,area.facility_definitions) and not is_same(old_area.ref,area.ref) and not is_same(old_floor,actual._floor_regions[1]) and not is_same(old_floor.by_cell,actual._floor_regions[1].by_cell) and not is_same(old_floor.by_facility,actual._floor_regions[1].by_facility)
	checks.body_door_fit_and_entry_caches_not_inherited = actual._entry_geometry.is_empty() and actual._geometry_fits.is_empty() and actual._wait_geometry.is_empty() and not area.has("entry_order_cells")
	var alias_ok: bool = true
	for point: Vector2i in area.cells: alias_ok = alias_ok and is_same(actual._floor_regions[1].by_cell[point],area)
	for id: String in area.facilities: alias_ok = alias_ok and is_same(actual._floor_regions[1].by_facility[id],area)
	checks.internal_component_aliases_preserved = alias_ok
	# Mutate only detached former runtime views, never either world's facts.
	# A shallow region copy would leak these changes into the current owner.
	var prior: Dictionary = _snapshot(actual)
	var basis: Array = actual._floor_regions[1].basis.duplicate(true)
	old_area.ref.anchor[0] = -999
	old_area.cells.clear()
	old_area.facilities.clear()
	old_area.facility_definitions.clear()
	old_floor.basis.clear()
	checks.detached_view_mutations_do_not_leak = prior==_snapshot(actual) and basis==actual._floor_regions[1].basis
	# World identity/revision equality alone cannot authorize reuse. A real
	# different floor source rebuilds only that floor and still matches the oracle.
	var changed: WorldState = WorldState.new(copied.freeze())
	changed.facts.floors.overrides["1"].blocked.append([37,70])
	checks.same_revision_different_geometry_input = changed.geometry_revision==copied.geometry_revision and changed.validate(database).is_empty()
	before = actual.builds.size()
	observations.append(_compare_build("same_revision_new_geometry",changed,actual,reference))
	checks.only_changed_floor_traversed = actual.builds.slice(before)==[1] and actual._cell_region(1,Vector2i(37,70)).is_empty()
	before = actual.builds.size()
	observations.append(_compare_build("return_to_original_geometry",copied,actual,reference))
	checks.return_rechecks_complete_source = actual.builds.slice(before)==[1] and not actual._cell_region(1,Vector2i(37,70)).is_empty()
	# Removing an explicit floor must discard its old mapping, even though its
	# last equal components remain available while comparing this new owner.
	var removed: WorldState = WorldState.new(copied.freeze())
	for id: String in removed.ids("facilities"):
		if int(removed.facts.facilities[id].floor_id)==2: removed.facts.facilities.erase(id)
	for id: String in removed.ids("rooms"):
		if int(removed.facts.rooms[id].floor_id)==2: removed.facts.rooms.erase(id)
	removed.facts.floors.overrides.erase("2")
	before = actual.builds.size()
	observations.append(_compare_build("removed_explicit_floor",removed,actual,reference))
	checks.removed_floor_not_retained = actual.builds.size()==before and actual._floor_regions.keys()==[1] and not actual._derived_floors.has(2) and actual._cell_region(2,Vector2i(35,82)).is_empty()
	before = actual.builds.size()
	observations.append(_compare_build("lazy_floor_after_owner_change",removed,actual,reference,2))
	checks.lazy_floor_built_from_current_world = actual.builds.slice(before)==[2] and not actual._cell_region(2,Vector2i(35,82)).is_empty()
	checks.single_latest_world_only = actual._world.get_ref()==removed and actual._floor_regions.size()==2
	var result: Dictionary = {"ok":not checks.values().has(false) and observations.all(func(row: Dictionary)->bool:return row.ok),"checks":checks,"observations":observations,"floor_traversals":actual.builds,"floor_copies":int(actual_space.query_counts.get("public_region_floor_copies",0)),"scope":"Read-only legal region-calculation inputs and detached runtime-view alias checks; actual movement is covered separately."}
	x.a.dispose()
	x.p.waiting_life = null
	x.p.environment = null
	x.e.waiting_life = null
	x.l.environment = null
	x.l.visitors = null
	x.c.recruitment = null
	x.clear()
	return result
