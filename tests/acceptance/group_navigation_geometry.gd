extends RefCounted

# SPACE-51: reuse only body-specific static projections already acquired by
# this query. Identity permissions, offsets and geometry refresh remain live.
func run_case(source: Dictionary, content: HospitalContent) -> Dictionary:
	var world: WorldState = WorldState.new(source.duplicate(true))
	var space: HospitalSpace = HospitalSpace.new(content)
	var actor: Dictionary = world.facts.actors.permission_owner
	var observations: Array = []
	var passed: bool = true
	for variant: String in ["authorized","replacement","large_member","fractional","geometry_changed","evicted"]:
		var member_id: String = "permission_staff" if variant=="authorized" else "permission_other"
		if variant=="large_member":
			world.facts.actors[member_id].species_id = "S53"
			world.touch()
		if variant=="geometry_changed":
			world.facts.floors.overrides["1"].blocked.append([40,90])
			world.touch()
		if variant=="evicted": space._navigation._trim(0)
		var members: Array = [actor.id,member_id]
		var offset: Array = [0.25,-0.5] if variant=="fractional" else [1,0]
		var offsets: Dictionary = {actor.id:[0,0],member_id:offset}
		var before: Dictionary = world.freeze()
		var navigation: Dictionary = space._navigation.query_graphs(space,world,1,actor,members,offsets)
		var graph: FloorNavigation = navigation.graph
		var expected: RouteClearance = RouteClearance.new(space,world,actor,1,members,offsets,true,graph.geometry.source)
		var actual: RouteClearance = expected
		var borrowed: bool = false
		if navigation.has("member_geometries"):
			actual = RouteClearance.new(space,world,actor,1,members,offsets,true,graph.geometry.source,graph.geometry,navigation.member_geometries)
			var member_geometry: RouteClearance = navigation.member_geometries[member_id]
			borrowed = is_same(actual._plots,graph.geometry._plots) and is_same(actual._members[0].query._doors,member_geometry._doors) and is_same(actual._members[0].query._dependencies,member_geometry._dependencies)
		var blocked_by_owner_reservation: bool = false
		for reservation: Dictionary in actual._members[0].query._reservations:
			if reservation.id=="permissions_machine": blocked_by_owner_reservation = true
		var permission_correct: bool = blocked_by_owner_reservation==(member_id!="permission_staff")
		var equal: bool = permission_correct
		for index: int in FloorNavigation.LIMIT:
			var cell: Vector2i = FloorNavigation._cell(index)
			equal = equal and actual.reason(cell)==expected.reason(cell)
		# Route output still belongs to its caller and retains the same ordered
		# four-neighbour result; the reference supplies fresh full predicates.
		var reference: Dictionary = navigation.duplicate()
		reference.query = expected
		for goal: Vector2i in [Vector2i(40,90),Vector2i(42,78),Vector2i(-1,80)]:
			var baseline: Dictionary = space._floor_route(world,actor,1,Vector2i(38,80),goal,members,offsets,true,reference)
			var result: Dictionary = space._floor_route(world,actor,1,Vector2i(38,80),goal,members,offsets,true,navigation)
			equal = equal and result==baseline
		var fallback: bool = not navigation.has("member_geometries") if variant=="fractional" else borrowed
		var readonly: bool = before==world.freeze()
		passed = passed and equal and fallback and readonly
		observations.append({"variant":variant,"all_cell_reasons_and_routes_equal":equal,"member_permission_preserved":permission_correct,"borrowed_or_complete_fallback":fallback,"readonly":readonly})
	return {"ok":passed,"observations":observations}
