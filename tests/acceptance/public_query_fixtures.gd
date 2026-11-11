extends "res://tests/acceptance/staff_fixtures.gd"

# Calculation inputs retain the two original closed structures and seats.
# Seats stand on public ground; an empty room does not grant patient access.
func _public_query_fixture() -> Dictionary:
	var x: Dictionary = _fixture()
	for entry: Array in [["west",34,36],["east",48,54]]:
		HospitalFactory._add_room(x.world,{"id":entry[0],"type":"","anchor":[entry[1],66],"size":[10,12],"door":{"definition_id":"DR04","offset":3}},_content)
		_facility(x,str(entry[0])+"_chair","FUR09",[int(entry[2]),82])
	x.world.touch()
	var expected: Array[Vector2i] = _public_query_candidates()
	var reference: Dictionary = x.space.public_areas.for_facility(x.world,"west_chair")
	var area: Dictionary = x.space.public_areas.region(x.world,reference)
	var cells: Dictionary = area.get("cells",{})
	x.query_fixture_checks = {
		"two_original_empty_structures":x.world.facts.rooms.size()==2 and x.world.facts.rooms.west.kind=="" and x.world.facts.rooms.east.kind=="" and x.world.facts.rooms.west.origin==[34,66] and x.world.facts.rooms.east.origin==[48,66] and x.world.facts.rooms.west.size==[10,12] and x.world.facts.rooms.east.size==[10,12],
		"two_original_doors":x.world.facts.floors.overrides["1"].doors.size()==2,
		"two_public_original_seats":x.world.facts.facilities.size()==2 and x.world.facts.facilities.west_chair.cell==[36,82] and x.world.facts.facilities.east_chair.cell==[54,82] and x.world.facts.facilities.west_chair.footprint==[1,1] and x.world.facts.facilities.east_chair.footprint==[1,1] and str(x.world.facts.facilities.west_chair.get("room_id",""))=="" and str(x.world.facts.facilities.east_chair.get("room_id",""))=="",
		"independent_complete_three_cell_domain":expected.size()==25 and cells.size()==25 and expected.all(func(point: Vector2i)->bool:return cells.has(point))}
	return x

# This fixture has a one-cell chair in open public ground. Enumerate the whole
# published three-cell domain independently of production region/candidate lists.
func _public_query_candidates() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(79,86):
		for x: int in range(33,40):
			if absi(x-36)+absi(y-82)<=3: cells.append(Vector2i(x,y))
	return cells

func _query_fixture_validation(x: Dictionary) -> String:
	var reason: String = x.world.validate(_content)
	if not reason.is_empty(): return reason
	for name: String in x.query_fixture_checks:
		if not x.query_fixture_checks[name]: return "公共查询前提不符合当前完整几何："+name
	return ""
