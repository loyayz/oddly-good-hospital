extends RefCounted

const Bulk = preload("res://tests/acceptance/navigation_bulk_build.gd")
const Cold = preload("res://tests/acceptance/navigation_cold_graph.gd")

class CountingClearance extends RouteClearance:
	var full_wall_calls: int = 0
	func _wall_reason(rect: Rect2) -> String:
		full_wall_calls += 1
		return super._wall_reason(rect)

# Frozen pre-specialization edge: every member and merged wall sweep remains.
class CompleteEdges extends RouteClearance:
	func edge_reason(from: Vector2i, to: Vector2i) -> String:
		for member: Dictionary in _members:
			var reason: String = member.query.sweep_reason(Vector2(from)+member.offset,Vector2(to)+member.offset)
			if not reason.is_empty(): return reason
		return _wall_reason(Rect2(Vector2(from),Vector2.ONE*_size).merge(Rect2(Vector2(to),Vector2.ONE*_size)))

func run_case(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var built: bool = true
	for row: int in 4:
		for column: int in 4:
			var reply: CommandResult = suite._command(sim,"build_room",suite._room("unit_wall_%d_%d"%[row,column],[35+7*column,67+7*row]))
			built = built and reply.accepted
	suite._add_actor(sim,"unit_wall_actor","S49",[33,93])
	var actor: Dictionary = sim.world.facts.actors.unit_wall_actor
	var validation: String = sim.world.validate(suite.content)
	var before: Dictionary = sim.world.freeze()
	var actual: CountingClearance = CountingClearance.new(sim.space,sim.world,actor,1,[],{},false)
	var reference: CompleteEdges = CompleteEdges.new(sim.space,sim.world,actor,1,[],{},false,actual.source)
	var graph: FloorNavigation = FloorNavigation.new(actual)
	var full_calls: int = actual.full_wall_calls
	var expected: FloorNavigation = Bulk.ScriptBuild.new(reference)
	var complete: Dictionary = Cold.new()._compare(graph,{"graph":expected,"enabled":expected._enabled,"edges":expected._edges})
	var old_walls: RouteClearance = Bulk.OriginalClearance.new(sim.space,sim.world,actor,1,[],{},false,actual.source)
	var point_cut: bool = true
	var edges_equal: bool = true
	var checks: int = 0
	for y: int in 96:
		for x: int in 96:
			var cell: Vector2i = Vector2i(x,y)
			# An independent complete old wall predicate must find no indexed
			# integer wall inside ANY integer unit rectangle, including outside plots.
			point_cut = point_cut and old_walls._wall_reason(Rect2(Vector2(cell),Vector2.ONE)).is_empty()
			for direction: Vector2i in FloorNavigation.NEIGHBOURS:
				checks += 1
				edges_equal = edges_equal and actual.edge_reason(cell,cell+direction)==reference.edge_reason(cell,cell+direction)
	var fallback: bool = true
	var unindexed: CountingClearance = CountingClearance.new(sim.space,sim.world,actor,1,[],{},true,actual.source)
	var unindexed_reference: CompleteEdges = CompleteEdges.new(sim.space,sim.world,actor,1,[],{},true,actual.source)
	for ends: Array in [[Vector2i(34,70),Vector2i(44,78)],[Vector2i(36,71),Vector2i(36,71)],[Vector2i(34,70),Vector2i(36,70)]]:
		fallback = fallback and actual.edge_reason(ends[0],ends[1])==reference.edge_reason(ends[0],ends[1]) and unindexed.edge_reason(ends[0],ends[1])==unindexed_reference.edge_reason(ends[0],ends[1])
	var result: Dictionary = {"ok":built and validation.is_empty() and sim.space.clearance(actor)==1 and full_calls==0 and complete.ok and point_cut and edges_equal and fallback and before==sim.world.freeze(),"sixteen_real_rooms":built,"validation":validation,"all_graph_points_masks_neighbours":complete,"full_wall_dispatches_during_unit_graph_build":full_calls,"all_9216_unit_rectangles_have_no_interior_indexed_wall":point_cut,"all_four_adjacent_edges_equal":edges_equal,"edge_comparisons":checks,"nonadjacent_and_unindexed_fallback_equal":fallback,"facts_and_rng_unchanged":before==sim.world.freeze()}
	sim.dispose()
	return result
