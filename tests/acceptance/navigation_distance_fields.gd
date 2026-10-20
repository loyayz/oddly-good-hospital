extends RefCounted

func run(suite: RefCounted) -> Dictionary:
	# Flat IDs 97/98/99 are the consecutive cells (1,1)/(2,1)/(3,1).
	# Edges and every expected reachable value are literal, with no test BFS.
	var cases: Array[Dictionary] = [
		{"name":"directed_forward","cells":[97,98,99],"edges":[[97,98],[98,99]],"root":97,"reverse":false,"distances":{97:0,98:1,99:2}},
		{"name":"directed_reverse","cells":[97,98,99],"edges":[[97,98],[98,99]],"root":99,"reverse":true,"distances":{99:0,98:1,97:2},"successors":{98:99,97:98}},
		{"name":"forward_does_not_reverse_edges","cells":[97,98,99],"edges":[[97,98],[98,99]],"root":99,"reverse":false,"distances":{99:0}},
		{"name":"reverse_does_not_use_forward_edges","cells":[97,98,99],"edges":[[97,98],[98,99]],"root":97,"reverse":true,"distances":{97:0}},
		{"name":"forward_leaves_reserved_start","cells":[97,98,99],"edges":[[97,98],[98,99]],"reserved":[97],"root":97,"reverse":false,"distances":{97:0,98:1,99:2}},
		{"name":"forward_cannot_enter_reserved_middle","cells":[97,98,99],"edges":[[97,98],[98,99]],"reserved":[98],"root":97,"reverse":false,"distances":{97:0}},
		{"name":"forward_cannot_enter_reserved_goal","cells":[97,98,99],"edges":[[97,98],[98,99]],"reserved":[99],"root":97,"reverse":false,"distances":{97:0,98:1}},
		{"name":"reverse_includes_reserved_start","cells":[97,98,99],"edges":[[97,98],[98,99]],"reserved":[97],"root":99,"reverse":true,"distances":{99:0,98:1,97:2},"successors":{98:99,97:98}},
		{"name":"reverse_stops_at_reserved_current","cells":[97,98,99],"edges":[[97,98],[98,99]],"reserved":[98],"root":99,"reverse":true,"distances":{99:0,98:1},"successors":{98:99}},
		{"name":"reverse_reserved_goal_does_not_expand","cells":[97,98,99],"edges":[[97,98],[98,99]],"reserved":[99],"root":99,"reverse":true,"distances":{99:0}},
		{"name":"disabled_middle_forward","cells":[97,99],"edges":[[97,98],[98,99]],"root":97,"reverse":false,"distances":{97:0}},
		{"name":"disabled_middle_reverse","cells":[97,99],"edges":[[97,98],[98,99]],"root":99,"reverse":true,"distances":{99:0}},
		{"name":"disabled_root","cells":[98,99],"edges":[[97,98],[98,99]],"root":97,"reverse":false,"distances":{}},
		{"name":"disabled_goal","cells":[97,98],"edges":[[97,98],[98,99]],"root":99,"reverse":true,"distances":{}},
		{"name":"missing_root","cells":[97,98,99],"edges":[[97,98],[98,99]],"root":100,"reverse":false,"distances":{}},
		{"name":"isolated_forward_zero","cells":[0],"edges":[],"root":0,"reverse":false,"distances":{0:0}},
		{"name":"isolated_reverse_zero","cells":[0],"edges":[],"root":0,"reverse":true,"distances":{0:0}},
		{"name":"reverse_up_precedes_left","cells":[97,98,193,194],"edges":[[97,98],[97,193],[98,194],[193,194]],"root":194,"reverse":true,"distances":{194:0,98:1,193:1,97:2},"successors":{98:194,193:194,97:98}},
		{"name":"reverse_left_precedes_right","cells":[194,193,195,97,99,98],"edges":[[193,194],[195,194],[97,193],[99,195],[98,97],[98,99]],"root":194,"reverse":true,"distances":{194:0,193:1,195:1,97:2,99:2,98:3},"successors":{193:194,195:194,97:193,99:195,98:97}},
		{"name":"right_edge_does_not_wrap_row","cells":[95,96],"edges":[],"masks":{95:4,96:2},"root":95,"reverse":false,"distances":{95:0}},
		{"name":"left_edge_does_not_wrap_row","cells":[95,96],"edges":[],"masks":{95:4,96:2},"root":96,"reverse":false,"distances":{96:0}},
		{"name":"top_left_has_no_negative_neighbours","cells":[0,9215],"edges":[],"masks":{0:3,9215:12},"root":0,"reverse":false,"distances":{0:0}},
		{"name":"bottom_right_has_no_outside_neighbours","cells":[0,9215],"edges":[],"masks":{0:3,9215:12},"root":9215,"reverse":false,"distances":{9215:0}},
		{"name":"outside_floor_sentinel","cells":[97],"edges":[],"root":-1,"reverse":false,"distances":{}}
	]
	var checks: Dictionary = {}
	var failures: Dictionary = {}
	var unchanged: bool = true
	for sample: Dictionary in cases:
		var inputs: Dictionary = _masks(sample)
		var before: Dictionary = inputs.duplicate(true)
		var result: Dictionary = PlatformArrivalMath.grid_distance_field(inputs.enabled,inputs.edges,inputs.reservations,{"root":sample.root,"reverse":sample.reverse})
		var passed: bool = _literal_field(result,sample.distances,sample.get("successors",{}),sample.reverse)
		checks[sample.name] = passed
		unchanged = unchanged and inputs==before
		if not passed: failures[sample.name] = {"error":result.get("error",""),"native_ok":result.get("ok",false),"expected_distances":sample.distances,"expected_successors":sample.get("successors",{})}
	var valid: Dictionary = _masks({"cells":[97],"edges":[]})
	var invalid: Array[Dictionary] = [
		{"name":"missing_enabled_mask","enabled":PackedByteArray(),"edges":valid.edges,"reservations":valid.reservations,"options":{"root":97,"reverse":false}},
		{"name":"short_edge_mask","enabled":valid.enabled,"edges":PackedByteArray([0]),"reservations":valid.reservations,"options":{"root":97,"reverse":false}},
		{"name":"short_reservation_mask","enabled":valid.enabled,"edges":valid.edges,"reservations":PackedByteArray([0]),"options":{"root":97,"reverse":false}},
		{"name":"outside_native_root","enabled":valid.enabled,"edges":valid.edges,"reservations":valid.reservations,"options":{"root":9216,"reverse":false}},
		{"name":"non_integer_native_root","enabled":valid.enabled,"edges":valid.edges,"reservations":valid.reservations,"options":{"root":97.5,"reverse":false}},
		{"name":"non_boolean_direction","enabled":valid.enabled,"edges":valid.edges,"reservations":valid.reservations,"options":{"root":97,"reverse":1}}
	]
	for sample: Dictionary in invalid:
		var before: Dictionary = sample.duplicate(true)
		var result: Dictionary = PlatformArrivalMath.grid_distance_field(sample.enabled,sample.edges,sample.reservations,sample.options)
		var passed: bool = not result.get("ok",true) and not str(result.get("error","")).is_empty() and not result.has("distances") and not result.has("successors")
		checks[sample.name] = passed
		unchanged = unchanged and sample==before
		if not passed: failures[sample.name] = result
	checks.native_inputs_unchanged = unchanged
	var integration: Dictionary = _mask_handoff(suite)
	checks.graph_build_repair_and_failure_handoff = integration.ok
	var ok: bool = true
	for name: String in checks: ok = ok and checks[name]
	return {"ok":ok,"checks":checks,"failures":failures,"graph_handoff":integration,"literal_fields":cases.size(),"invalid_inputs":invalid.size()}

func _masks(sample: Dictionary) -> Dictionary:
	var enabled: PackedByteArray = PackedByteArray()
	var edges: PackedByteArray = PackedByteArray()
	var reservations: PackedByteArray = PackedByteArray()
	enabled.resize(FloorNavigation.LIMIT)
	edges.resize(FloorNavigation.LIMIT)
	for id: int in sample.cells: enabled[id] = 1
	for pair: Array in sample.edges:
		var step: int = int(pair[1])-int(pair[0])
		edges[int(pair[0])] |= 1 if step==-96 else 2 if step==-1 else 4 if step==1 else 8
	for id: int in sample.get("masks",{}): edges[id] = int(sample.masks[id])
	if not sample.get("reserved",[]).is_empty():
		reservations.resize(FloorNavigation.LIMIT)
		for id: int in sample.reserved: reservations[id] = 1
	return {"enabled":enabled,"edges":edges,"reservations":reservations}

func _literal_field(result: Dictionary, distances: Dictionary, successors: Dictionary, reverse: bool) -> bool:
	if not result.get("ok",false) or not result.get("distances") is PackedInt32Array or not result.get("successors") is PackedInt32Array: return false
	if result.distances.size()!=FloorNavigation.LIMIT or result.successors.size()!=(FloorNavigation.LIMIT if reverse else 0): return false
	for id: int in FloorNavigation.LIMIT:
		if result.distances[id]!=int(distances.get(id,-1)): return false
		if reverse and result.successors[id]!=int(successors.get(id,-1)): return false
	return true

func _mask_handoff(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"field_subject","S49",[40,80])
	var world: WorldState = sim.world
	var actor: Dictionary = world.facts.actors.field_subject
	var graph: FloorNavigation = sim.space._navigation.graph(sim.space,world,1,actor,[],{})
	var query: RouteClearance = RouteClearance.new(sim.space,world,actor,1,[],{},true,graph.geometry.source,graph.geometry)
	var before: Dictionary = world.freeze()
	var field: Dictionary = graph.distance_field(query,Vector2i(40,80))
	var built: bool = field.get("ready",false) and field.distances[FloorNavigation._id(Vector2i(42,80))]==2 and _engine_masks_equal(graph) and before==world.freeze()
	world.facts.floors.overrides["1"].blocked.append([42,80])
	world.touch()
	var changed: FloorNavigation = sim.space._navigation.graph(sim.space,world,1,actor,[],{})
	query = RouteClearance.new(sim.space,world,actor,1,[],{},true,changed.geometry.source,changed.geometry)
	field = changed.distance_field(query,Vector2i(40,80))
	var repaired: bool = is_same(graph,changed) and field.get("ready",false) and field.distances[FloorNavigation._id(Vector2i(42,80))]==-1 and _engine_masks_equal(changed)
	world.facts.floors.overrides["1"].blocked.erase([42,80])
	world.touch()
	graph = sim.space._navigation.graph(sim.space,world,1,actor,[],{})
	query = RouteClearance.new(sim.space,world,actor,1,[],{},true,graph.geometry.source,graph.geometry)
	field = graph.distance_field(query,Vector2i(40,80))
	var restored: bool = field.get("ready",false) and field.distances[FloorNavigation._id(Vector2i(42,80))]==2 and _engine_masks_equal(graph)
	before = world.freeze()
	var saved: PackedByteArray = graph._edges
	graph._edges = PackedByteArray([0])
	var failed: Dictionary = graph.distance_field(query,Vector2i(40,80))
	graph._edges = saved
	var failure_handoff: bool = not failed.get("ready",true) and not failed.has("distances") and not str(failed.get("error","")).is_empty() and before==world.freeze()
	var outside: Dictionary = graph.distance_field(query,Vector2i(96,0))
	var outside_safe: bool = outside.get("ready",false) and outside.distances.count(-1)==FloorNavigation.LIMIT
	sim.dispose()
	return {"ok":built and repaired and restored and failure_handoff and outside_safe,"built":built,"repaired":repaired,"restored":restored,"native_failure_not_no_path":failure_handoff,"outside_does_not_wrap":outside_safe}

func _engine_masks_equal(graph: FloorNavigation) -> bool:
	for id: int in graph.get_point_ids():
		var cell: Vector2i = FloorNavigation._cell(id)
		if graph.is_point_disabled(id):
			if graph._enabled[id]!=0 or graph._edges[id]!=0: return false
			continue
		if graph._enabled[id]!=1: return false
		for direction: int in FloorNavigation.NEIGHBOURS.size():
			var next: Vector2i = cell+FloorNavigation.NEIGHBOURS[direction]
			var connected: bool = FloorNavigation._inside(next) and graph.has_point(FloorNavigation._id(next)) and graph.are_points_connected(id,FloorNavigation._id(next),false)
			if bool(graph._edges[id]&(1<<direction))!=connected: return false
	return graph._enabled[0]==0 and graph._edges[0]==0
