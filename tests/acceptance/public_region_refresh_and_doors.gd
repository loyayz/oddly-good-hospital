extends "res://tests/acceptance/public_region_build.gd"

const RegionBuild = preload("res://tests/acceptance/public_region_build.gd")

class FullDoorAreas extends HospitalPublicAreas:
	func _wait_door_view(_world: WorldState, _floor_id: int, _spans: Array) -> Dictionary:
		return {}

func run_case(database: HospitalContent) -> Dictionary:
	_content = database
	var x: Dictionary = _build_fixture()
	var actual_space: LayoutCounts = LayoutCounts.new(_content)
	var reference_space: HospitalSpace = HospitalSpace.new(_content)
	var actual: HospitalPublicAreas = HospitalPublicAreas.new(actual_space)
	var reference: HospitalPublicAreas = RegionBuild.ReferenceAreas.new(reference_space)
	var checks: Dictionary = {"valid_input":x.world.validate(_content).is_empty()}
	var observations: Array = [_compare_build("cold",x.world,actual,reference)]
	checks.region_only_reads_geometry_without_full_facility_copy = actual_space.layouts==0
	var mapping_builds: int = int(actual_space.query_counts.get("public_region_mapping_builds",0))
	var floor_builds: int = int(actual_space.query_counts.get("public_region_floor_builds",0))
	x.world.facts.facilities.west_chair.failed = true
	x.world.touch()
	observations.append(_compare_build("full_basis_fallback_for_unscoped_revision",x.world,actual,reference))
	checks.identical_complete_basis_retains_existing_global_maps = int(actual_space.query_counts.get("public_region_mapping_builds",0))==mapping_builds and int(actual_space.query_counts.get("public_region_floor_builds",0))==floor_builds and int(actual_space.query_counts.get("public_region_mapping_hits",0))==1 and actual_space.layouts==0
	x.world.facts.floors.overrides["1"].blocked.append([37,70])
	x.world.touch()
	observations.append(_compare_build("real_change_still_rebuilds_and_reindexes",x.world,actual,reference))
	checks.real_change_rebuilds_one_floor_and_mapping = int(actual_space.query_counts.get("public_region_mapping_builds",0))==mapping_builds+1 and int(actual_space.query_counts.get("public_region_floor_builds",0))==floor_builds+1
	var doors: Dictionary = _door_corpus(x,actual)
	# Removing the explicit upper floor, its rooms and facilities leaves a legal
	# lazy completed floor. Full comparison must drop all its old global keys.
	for id: String in x.world.ids("facilities"):
		if int(x.world.facts.facilities[id].floor_id)==2: x.world.facts.facilities.erase(id)
	for id: String in x.world.ids("rooms"):
		if int(x.world.facts.rooms[id].floor_id)==2: x.world.facts.rooms.erase(id)
	x.world.facts.floors.overrides.erase("2")
	x.world.touch()
	observations.append(_compare_build("removed_explicit_floor",x.world,actual,reference))
	checks.removed_floor_has_no_stale_mapping = actual._floor_regions.keys()==[1] and not actual._by_cell.has("2:32:64") and not actual._by_facility.has("upper_west_chair")
	var other: WorldState = WorldState.new(x.world.freeze())
	var before_other: int = int(actual_space.query_counts.get("public_region_mapping_builds",0))
	observations.append(_compare_build("equal_facts_different_world",other,actual,reference))
	checks.other_world_rebuilds_mapping = int(actual_space.query_counts.get("public_region_mapping_builds",0))==before_other+1
	var ok: bool = doors.ok and not checks.values().has(false) and observations.all(func(row: Dictionary)->bool:return row.ok)
	var result: Dictionary = {"ok":ok,"checks":checks,"region_observations":observations,"door_broadphase":doors,"scope":"Complete region fallback and door geometry calculations; no movement or arrival is substituted."}
	x.a.dispose()
	x.p.waiting_life = null
	x.p.environment = null
	x.e.waiting_life = null
	x.l.environment = null
	x.l.visitors = null
	x.c.recruitment = null
	x.clear()
	return result

func _door_corpus(x: Dictionary, actual: HospitalPublicAreas) -> Dictionary:
	var original: Dictionary = x.world.freeze()
	var actor: Dictionary = x.world.facts.actors[BED_USER]
	var saved_actor: Dictionary = actor.duplicate(true)
	var reference_space: HospitalSpace = HospitalSpace.new(_content)
	var reference: FullDoorAreas = FullDoorAreas.new(reference_space)
	reference._ensure(x.world)
	var observations: Array = []
	var checks: Dictionary = {}
	var broadphase_equal: bool = true
	var safety_equal: bool = true
	var integrated_checks: Array = [0,0]
	var matched: int = 0
	for variant: Array in [["S01",0.0],["S49",0.0],["S01",PI*0.25]]:
		actor.species_id = variant[0]
		actor.facing = variant[1]
		actor.posture = "standing"
		var area: Dictionary = actual._by_facility.west_chair
		var geometry: Dictionary = actual._entry_geometry_view(x.world,actor,area)
		var expected_geometry: Dictionary = reference._entry_geometry_view(x.world,actor,reference._by_facility.west_chair)
		var doors: Dictionary = geometry.doors
		var local: Rect2 = actual.space._actor_rect(actor,Vector2.ZERO)
		var origins: Array[Vector2] = [Vector2(36,75),Vector2(55,90),Vector2(37.25,73.75),Vector2(38,90)]
		for rect: Rect2 in doors.rectangles:
			var left: Vector2 = Vector2(rect.position.x-local.end.x,rect.position.y-local.position.y)
			var right: Vector2 = Vector2(rect.end.x-local.position.x,rect.position.y-local.position.y)
			var above: Vector2 = Vector2(rect.position.x-local.position.x,rect.position.y-local.end.y)
			var below: Vector2 = Vector2(rect.position.x-local.position.x,rect.end.y-local.position.y)
			for point: Vector2 in [left,right,above,below]:
				origins.append(point)
				origins.append(point+Vector2(0.0001,0.0001))
				origins.append(point-Vector2(0.0001,0.0001))
		for point: Vector2 in origins:
			var bounds: Rect2 = actual.space._actor_rect(actor,point)
			var expected: Array = []
			for number: int in doors.rectangles.size():
				if bounds.intersects(doors.rectangles[number],false): expected.append(number)
			var observed: PackedInt32Array = PackedInt32Array()
			for id: String in (doors.index as BodyIndex).candidates(1,bounds): observed.append(int(id))
			observed.sort()
			broadphase_equal = broadphase_equal and Array(observed)==expected
			matched += expected.size()
			var before: int = int(actual.space.query_counts.get("public_wait_door_checks",0))
			var a: bool = actual._safe_wait_geometry(x.world,actor,1,point,geometry.geometry,doors)
			integrated_checks[0] += int(actual.space.query_counts.get("public_wait_door_checks",0))-before
			before = int(reference_space.query_counts.get("public_wait_door_checks",0))
			var b: bool = reference._safe_wait_geometry(x.world,actor,1,point,expected_geometry.geometry)
			integrated_checks[1] += int(reference_space.query_counts.get("public_wait_door_checks",0))-before
			safety_equal = safety_equal and a==b
		observations.append({"species":variant[0],"facing":variant[1],"tested_integer_fractional_edge_touch_and_nearby_origins":origins.size(),"source_doors":doors.rectangles.size()})
		var spans: Array = doors.spans
		checks.same_span_owner_reused = bool(checks.get("same_span_owner_reused",true)) and is_same(doors,actual._wait_door_view(x.world,1,spans))
		# The input here is the complete geometric span declaration, not an
		# adaptation grant. Changing it must replace the one latest index even
		# without a global world revision; restoring it does not retain history.
		var expanded: Array = spans.duplicate(true)
		expanded[0][1] = int(expanded[0][1])+1
		var original_rectangles: Array = doors.rectangles.duplicate()
		var changed: Dictionary = actual._wait_door_view(x.world,1,expanded)
		var changed_spans: bool = changed.spans==expanded and changed.rectangles!=original_rectangles
		var restored: Dictionary = actual._wait_door_view(x.world,1,spans)
		checks.span_change_updates_one_current_view_without_history = bool(checks.get("span_change_updates_one_current_view_without_history",true)) and changed_spans and is_same(doors,changed) and is_same(changed,restored) and restored.spans==spans and restored.rectangles==original_rectangles
	checks.integer_fractional_and_edge_touch_complete_door_order = broadphase_equal and matched>0
	checks.original_geometry_and_work_rules_equal = safety_equal
	checks.far_doors_not_rechecked_per_candidate = integrated_checks[0]<integrated_checks[1] and integrated_checks[1]>0
	x.world.facts.actors[BED_USER] = saved_actor
	checks.world_facts_unchanged = original==x.world.freeze()
	return {"ok":not checks.values().has(false),"checks":checks,"observations":observations,"door_predicate_calls":{"indexed":integrated_checks[0],"complete_reference":integrated_checks[1]},"complete_geometric_intersections":matched}
