extends "res://tests/acceptance/public_region_build.gd"

const RegionBuild = preload("res://tests/acceptance/public_region_build.gd")

class FullDoorAreas extends HospitalPublicAreas:
	func _safe_wait_geometry(world: WorldState, actor: Dictionary, floor_id: int, origin: Vector2, geometry: RouteClearance, _doors: Dictionary = {}) -> bool:
		return super._safe_wait_geometry(world,actor,floor_id,origin,geometry,{})

func run_case(database: HospitalContent) -> Dictionary:
	_content = database
	var x: Dictionary = _build_fixture()
	var actual_space: HospitalSpace = HospitalSpace.new(_content)
	var reference_space: HospitalSpace = HospitalSpace.new(_content)
	var actual: HospitalPublicAreas = HospitalPublicAreas.new(actual_space)
	var reference: HospitalPublicAreas = RegionBuild.ReferenceAreas.new(reference_space)
	var checks: Dictionary = {"valid_input":x.world.validate(_content).is_empty()}
	var observations: Array = [_compare_build("cold",x.world,actual,reference)]
	var west: Dictionary = actual._by_facility.get("west_chair",{})
	var same_floor_other_area: Dictionary = actual._by_facility.get("east_chair",{})
	x.world.facts.facilities.west_chair.failed = true
	x.world.touch()
	observations.append(_compare_build("failure_changes_use_not_area_membership",x.world,actual,reference))
	checks.nonstructural_failure_preserves_geometry_and_refuses_use = not west.is_empty() and is_same(west,actual._by_facility.get("west_chair",{})) and actual.facilities(x.world,west.ref,["FUR06"]).is_empty()
	x.world.facts.floors.overrides["1"].blocked.append([37,70])
	x.world.touch()
	observations.append(_compare_build("real_change_still_rebuilds_and_reindexes",x.world,actual,reference))
	checks.local_geometry_replaces_only_affected_area = not is_same(west,actual._by_facility.get("west_chair",{})) and is_same(same_floor_other_area,actual._by_facility.get("east_chair",{})) and actual._cell_region(1,Vector2i(37,70)).is_empty()
	var doors: Dictionary = _door_corpus(x,actual)
	# The remaining floor is complete but has no public fixtures; it must not
	# inherit stale areas or cell keys from the removed upper-floor objects.
	for id: String in x.world.ids("facilities"):
		if int(x.world.facts.facilities[id].floor_id)==2: x.world.facts.facilities.erase(id)
	for id: String in x.world.ids("rooms"):
		if int(x.world.facts.rooms[id].floor_id)==2: x.world.facts.rooms.erase(id)
	x.world.facts.floors.overrides.erase("2")
	x.world.touch()
	observations.append(_compare_build("removed_explicit_floor",x.world,actual,reference))
	checks.removed_floor_has_no_stale_mapping = actual._floor_regions.keys()==[1] and actual._cell_region(2,Vector2i(36,68)).is_empty() and not actual._by_facility.has("upper_west_chair")
	var other: WorldState = WorldState.new(x.world.freeze())
	var old: Dictionary = actual._by_facility.get("west_chair",{})
	observations.append(_compare_build("equal_facts_different_world",other,actual,reference))
	var detached: Dictionary = actual._by_facility.get("west_chair",{})
	checks.other_world_geometry_has_independent_owner = old==detached and not is_same(old,detached) and not is_same(old.get("cells",{}),detached.get("cells",{}))
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
			var a: bool = actual._safe_wait_geometry(x.world,actor,1,point,geometry.geometry,doors)
			var b: bool = reference._safe_wait_geometry(x.world,actor,1,point,expected_geometry.geometry)
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
	x.world.facts.actors[BED_USER] = saved_actor
	checks.world_facts_unchanged = original==x.world.freeze()
	return {"ok":not checks.values().has(false),"checks":checks,"observations":observations,"complete_geometric_intersections":matched}
