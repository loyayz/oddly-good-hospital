extends RefCounted

func _request(cells: Array, connections: Array, root: int) -> Dictionary:
	var enabled: PackedByteArray = PackedByteArray(); enabled.resize(FloorNavigation.LIMIT)
	var edges: PackedByteArray = PackedByteArray(); edges.resize(FloorNavigation.LIMIT)
	for id: int in cells: enabled[id]=1
	for pair: Array in connections:
		var step: int = int(pair[1])-int(pair[0])
		edges[int(pair[0])] |= 1 if step==-96 else 2 if step==-1 else 4 if step==1 else 8
	return {"enabled":enabled,"edges":edges,"root":root}

func run() -> Dictionary:
	# Four-direction unit distances are literal; no test traversal algorithm.
	var cases: Array = [
		{"request":_request([97,98,99],[[97,98],[98,99]],97),"expected":{97:0,98:1,99:2}},
		{"request":_request([97,98,99],[[97,98],[98,99]],99),"expected":{99:0}},
		{"request":_request([97,99],[],97),"expected":{97:0}},
		{"request":_request([97,98,99],[[97,98],[98,99]],100),"expected":{}},
		{"request":_request([97,98,99],[[97,98],[98,99]],-1),"expected":{}},
		{"request":_request([97,99,193,194,195],[[97,193],[193,194],[194,195],[195,99]],97),"expected":{97:0,193:1,194:2,195:3,99:4}}]
	var requests: Array = []
	for repeat: int in 12:
		for row: Dictionary in cases: requests.append(row.request)
	var input: PackedByteArray = var_to_bytes(requests)
	var batch: Dictionary = PlatformArrivalMath.grid_structural_fields(requests)
	var ok: bool = batch.get("ok",false) and batch.get("fields",[]).size()==requests.size() and int(batch.get("tasks",0))==8 and int(batch.get("threads_used",0)) in range(1,9)
	if ok:
		for index: int in requests.size():
			var expected: Dictionary = cases[index%cases.size()].expected
			var distances: PackedInt32Array = batch.fields[index]
			ok = ok and distances.size()==FloorNavigation.LIMIT
			for id: int in distances.size(): ok = ok and int(distances[id])==int(expected.get(id,-1))
	var single: Dictionary = PlatformArrivalMath.grid_structural_fields([cases[0].request])
	var empty: Dictionary = PlatformArrivalMath.grid_structural_fields([])
	var invalid: Dictionary = PlatformArrivalMath.grid_structural_fields([cases[0].request,{"enabled":PackedByteArray(),"edges":PackedByteArray(),"root":97}])
	var rejected: bool = not invalid.get("ok",true) and invalid.has("error") and not invalid.has("fields")
	var original: Dictionary = PlatformArrivalMath.grid_distance_field(cases[0].request.enabled,cases[0].request.edges,PackedByteArray(),{"root":97,"reverse":false})
	var inline_equal: bool = single.get("ok",false) and int(single.tasks)==1 and int(single.threads_used)==1 and single.fields[0]==original.distances
	var unchanged: bool = input==var_to_bytes(requests)
	return {"ok":ok and inline_equal and rejected and unchanged and empty.get("ok",false) and empty.fields.is_empty() and int(empty.tasks)==0,"known_fields":requests.size(),"inline_equal":inline_equal,"invalid_batch_atomic":rejected,"input_unchanged":unchanged,"threads_used":batch.get("threads_used",0)}
