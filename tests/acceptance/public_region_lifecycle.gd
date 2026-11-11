extends "res://tests/acceptance/rooms_areas_guidance.gd"

# The room contract replaces whole-floor components with independent bounded
# facility projections. Count actual local builds at legal layout boundaries.
func run_case(database: HospitalContent) -> Dictionary:
	content=database
	var x: Dictionary=_base()
	x.checks.facilities=_facility(x,"west","FUR17",[36,81]) and _facility(x,"east","FUR17",[55,81])
	var areas: HospitalPublicAreas=x.sim.space.public_areas
	var index: HospitalFacilityAreaIndex=x.sim.space.public_areas._facility_areas
	var west: Dictionary=areas.region(x.world,areas.for_facility(x.world,"west"))
	var east: Dictionary=areas.region(x.world,areas.for_facility(x.world,"east"))
	var builds: int=int(x.sim.space.query_counts.get("public_local_area_builds",0))
	x.world.touch()
	areas._ensure(x.world)
	x.checks.unrelated_revision_retains_views=is_same(west,index.by_facility.west) and is_same(east,index.by_facility.east) and int(x.sim.space.query_counts.public_local_area_builds)==builds
	x.world.facts.facilities.west.failed=true
	x.world.touch()
	areas._ensure(x.world)
	x.checks.failure_changes_use_not_membership=is_same(west,index.by_facility.west) and int(x.sim.space.query_counts.public_local_area_builds)==builds
	x.checks.local_wall=_command(x,"build_wall",{"edges":[{"axis":"y","line":38,"low":79,"high":84}]}).accepted
	areas._ensure(x.world)
	x.checks.only_affected_projection_rebuilt=not is_same(west,index.by_facility.west) and is_same(east,index.by_facility.east) and int(x.sim.space.query_counts.public_local_area_builds)==builds+1
	x.checks.wall_stops_spread=not index.by_facility.west.cells.has(Vector2i(38,81))
	var old_ref: Dictionary=index.by_facility.west.ref.duplicate(true)
	x.checks.move=_command(x,"build_move",{"target_id":"west","floor_id":1,"cell":[39,86]}).accepted
	areas._ensure(x.world)
	x.checks.old_projection_removed=areas.region(x.world,old_ref).is_empty() and not areas.for_facility(x.world,"west").is_empty()
	return _finish(x,{"builds_before":builds,"builds_after":int(x.sim.space.query_counts.public_local_area_builds),"scope":"bounded region calculation, no movement or service completion claim"})
