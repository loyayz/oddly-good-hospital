extends RefCounted

const MAX_TICK: int = 9223372036854775807

func run() -> Dictionary:
	var lazy: Dictionary = _lazy()
	var zero: Dictionary = _zero_edges()
	var ties: Dictionary = _stable_ties()
	var integers: Dictionary = _integer_limits()
	var unreachable: Dictionary = _unreachable()
	var callback_failure: Dictionary = _callback_failure()
	return {"ok":lazy.ok and zero.ok and ties.ok and integers.ok and unreachable.ok and callback_failure.ok,"lazy":lazy,"zero_edges":zero,"stable_ties":ties,"integer_limits":integers,"unreachable":unreachable,"callback_failure":callback_failure}

func _search(nodes: Array, edges: Dictionary, expanded: Array, initial: int = 0) -> Dictionary:
	var expand: Callable = func(id: String) -> Array:
		expanded.append(id)
		return edges.get(id,[])
	return PlatformArrivalMath.route_search({"nodes":nodes,"start":"start","goal":"goal","initial_ticks":initial,"expand":expand})

func _lazy() -> Dictionary:
	var expanded: Array = []
	var nodes: Array = ["unused","start","goal","a","isolated"]
	var edges: Dictionary = {"start":[{"to":"unused","ticks":10},{"to":"a","ticks":1}],"a":[{"to":"goal","ticks":1}],"unused":[{"to":"goal","ticks":1}]}
	var before: Dictionary = edges.duplicate(true)
	var result: Dictionary = _search(nodes,edges,expanded)
	var lazy: bool = expanded==["start","a"]
	return {"ok":result.get("ok",false) and result.get("nodes",[])==["start","a","goal"] and int(result.get("travel_ticks",-1))==2 and lazy and edges==before,"unsettled_nodes_not_quoted":lazy,"expanded":expanded,"result":result,"input_unchanged":edges==before}

func _zero_edges() -> Dictionary:
	var expanded: Array = []
	# The z -> a edge has zero cost and moves to a smaller ID. It remains a
	# nonnegative edge; an ID tie-break must not become a negative time weight.
	var edges: Dictionary = {"start":[{"to":"z","ticks":0}],"z":[{"to":"a","ticks":0}],"a":[{"to":"goal","ticks":0}]}
	var result: Dictionary = _search(["start","z","a","goal"],edges,expanded)
	return {"ok":result.get("ok",false) and int(result.get("travel_ticks",-1))==0 and result.get("nodes",[])==["start","z","a","goal"] and expanded==["start","z","a"],"expanded":expanded,"result":result}

func _stable_ties() -> Dictionary:
	var expanded: Array = []
	# Supply z first and declare nodes out of order. Equal-cost frontier nodes
	# must still visit a before z, preserving the first equally short goal edge.
	var edges: Dictionary = {"start":[{"to":"z","ticks":1},{"to":"a","ticks":1}],"a":[{"to":"goal","ticks":1}],"z":[{"to":"goal","ticks":1}]}
	var result: Dictionary = _search(["z","start","goal","a"],edges,expanded)
	return {"ok":result.get("ok",false) and result.get("nodes",[])==["start","a","goal"] and int(result.get("travel_ticks",-1))==2 and expanded==["start","a","z"],"expanded":expanded,"result":result}

func _integer_limits() -> Dictionary:
	var expanded: Array = []
	var maximum: Dictionary = _search(["start","goal"],{"start":[{"to":"goal","ticks":2}]},expanded,MAX_TICK-2)
	var exact: bool = maximum.get("ok",false) and int(maximum.get("travel_ticks",-1))==MAX_TICK and maximum.get("nodes",[])==["start","goal"]
	expanded.clear()
	var zero_at_maximum: Dictionary = _search(["start","goal"],{"start":[{"to":"goal","ticks":0}]},expanded,MAX_TICK)
	var zero_exact: bool = zero_at_maximum.get("ok",false) and int(zero_at_maximum.get("travel_ticks",-1))==MAX_TICK
	expanded.clear()
	var overflow: Dictionary = _search(["start","goal"],{"start":[{"to":"goal","ticks":3}]},expanded,MAX_TICK-2)
	var rejected: bool = not overflow.get("ok",true) and not overflow.has("nodes") and not overflow.has("travel_ticks") and not overflow.has("error")
	return {"ok":exact and zero_exact and rejected,"maximum_is_reachable":exact,"zero_at_maximum":zero_exact,"overflow_is_unreachable":rejected,"maximum":maximum,"overflow":overflow}

func _unreachable() -> Dictionary:
	var expanded: Array = []
	var result: Dictionary = _search(["start","goal","isolated"],{},expanded)
	return {"ok":not result.get("ok",true) and not result.has("nodes") and not result.has("travel_ticks") and expanded==["start"],"expanded":expanded,"result":result}

func _callback_failure() -> Dictionary:
	var nodes: Array = ["start","goal"]
	var expanded: Array = []
	var expand: Callable = func(id: String) -> Array:
		expanded.append(id)
		return [{"to":"undeclared","ticks":0}]
	var request: Dictionary = {"nodes":nodes,"start":"start","goal":"goal","initial_ticks":9,"expand":expand}
	var result: Dictionary = PlatformArrivalMath.route_search(request)
	var atomic: bool = result.has("error") and not result.has("nodes") and not result.has("travel_ticks") and nodes==["start","goal"] and int(request.initial_ticks)==9
	return {"ok":atomic and expanded==["start"],"no_partial_path":atomic,"expanded":expanded,"result":result}
