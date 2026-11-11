extends "res://tests/acceptance/rooms_areas_guidance.gd"

func run_case(database: HospitalContent) -> Dictionary:
	content=database
	var x: Dictionary=_base()
	x.checks.facility=_facility(x,"water","FUR17",[40,81])
	var areas: HospitalPublicAreas=x.sim.space.public_areas
	var index: HospitalFacilityAreaIndex=x.sim.space.public_areas._facility_areas
	var old: Dictionary=areas.region(x.world,areas.for_facility(x.world,"water"))
	var expected: Dictionary=old.duplicate(true)
	var frozen: Dictionary=x.world.freeze()
	var copy:=WorldState.new(frozen.duplicate(true))
	areas._ensure(copy)
	var current: Dictionary=index.by_facility.water
	x.checks.new_owner_same_projection=current==expected and not is_same(old,current) and not is_same(old.cells,current.cells) and not is_same(old.ref,current.ref)
	old.cells.clear()
	old.ref.anchor[0]=-999
	old.facilities.clear()
	x.checks.detached_view_no_leak=current==expected
	x.checks.world_facts_read_only=copy.freeze()==frozen and x.world.freeze()==frozen
	copy.facts.floors.overrides["1"].blocked.append([39,81])
	copy.touch()
	areas._ensure(copy)
	x.checks.new_owner_geometry_rechecked=not index.by_facility.water.cells.has(Vector2i(39,81))
	areas._ensure(x.world)
	x.checks.original_owner_recovered=index.by_facility.water==expected and x.world.freeze()==frozen
	return _finish(x,{"scope":"legal bounded region input and detached runtime alias checks; no service completion claim"})
