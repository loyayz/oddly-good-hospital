extends SceneTree

const SIDE: int = 5
const COUNT: int = SIDE * SIDE

func make_graph() -> AStar2D:
	var graph: AStar2D = AStar2D.new()
	for id: int in range(COUNT):
		graph.add_point(id, Vector2(id % SIDE, id / SIDE))
	for id: int in range(COUNT):
		for other: int in neighbours(id):
			graph.connect_points(id, other, false)
	return graph

func neighbours(id: int) -> Array[int]:
	var result: Array[int] = []
	for other: int in [id - SIDE, id - 1, id + 1, id + SIDE]:
		if other >= 0 and other < COUNT and absi(id % SIDE - other % SIDE) + absi(id / SIDE - other / SIDE) == 1:
			result.append(other)
	result.sort()
	return result

func canonicalise(graph: AStar2D, id: int) -> void:
	var adjacent: PackedInt64Array = graph.get_point_connections(id)
	adjacent.sort()
	for other: int in adjacent:
		graph.disconnect_points(id, other, false)
	for other: int in adjacent:
		graph.connect_points(id, other, false)

func paths(graph: AStar2D) -> Array[PackedInt64Array]:
	var result: Array[PackedInt64Array] = []
	for start: int in range(COUNT):
		for goal: int in range(COUNT):
			result.append(graph.get_id_path(start, goal))
	return result

func differences(graph: AStar2D, baseline: Array[PackedInt64Array]) -> int:
	var count: int = 0
	for start: int in range(COUNT):
		for goal: int in range(COUNT):
			if graph.get_id_path(start, goal) != baseline[start * COUNT + goal]:
				count += 1
	return count

func _initialize() -> void:
	var baseline: Array[PackedInt64Array] = paths(make_graph())
	var edge_cases: int = 0
	var edge_raw: int = 0
	var edge_normalised: int = 0
	var node_raw: int = 0
	var node_normalised: int = 0
	for id: int in range(COUNT):
		for other: int in neighbours(id):
			var graph: AStar2D = make_graph()
			graph.disconnect_points(id, other, false)
			graph.connect_points(id, other, false)
			edge_raw += differences(graph, baseline)
			canonicalise(graph, id)
			edge_normalised += differences(graph, baseline)
			edge_cases += 1
		var graph: AStar2D = make_graph()
		graph.remove_point(id)
		graph.add_point(id, Vector2(id % SIDE, id / SIDE))
		var touched: Array[int] = neighbours(id)
		for other: int in touched:
			graph.connect_points(id, other, true)
		node_raw += differences(graph, baseline)
		touched.append(id)
		for source: int in touched:
			canonicalise(graph, source)
		node_normalised += differences(graph, baseline)
	var result: Dictionary = {
		"engine": Engine.get_version_info().string,
		"scope": "native AStar2D equal-cost path identity on one 5x5 open grid; no hospital rules or performance measurement",
		"pairs_per_case": COUNT * COUNT,
		"edge_cases": edge_cases,
		"node_cases": COUNT,
		"raw_edge_path_differences": edge_raw,
		"raw_node_path_differences": node_raw,
		"normalised_edge_path_differences": edge_normalised,
		"normalised_node_path_differences": node_normalised
	}
	print(JSON.stringify(result))
	quit(0 if edge_normalised == 0 and node_normalised == 0 else 1)
