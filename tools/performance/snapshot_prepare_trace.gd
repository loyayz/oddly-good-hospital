extends RefCounted

# Each caller owns its scope; worker timing never mutates main-thread state.
static func start(scope: Dictionary, label: String) -> void:
	scope["_started_"+label]=Time.get_ticks_usec()

static func stop(scope: Dictionary, label: String) -> void:
	var key: String="_started_"+label
	var elapsed: int=Time.get_ticks_usec()-int(scope[key])
	scope.erase(key)
	var row: Dictionary=scope.get(label,{"elapsed_usec":0,"calls":0})
	row.elapsed_usec+=elapsed
	row.calls+=1
	scope[label]=row

static func measure(scope: Dictionary, label: String, operation: Callable, arguments: Array) -> Variant:
	start(scope,label)
	var value: Variant=operation.callv(arguments)
	stop(scope,label)
	if label=="estimate": scope.estimated_bytes=value
	if label=="freeze":
		var source: Dictionary=operation.get_object().get("facts")
		scope.freeze_copy={"root_detached":not is_same(value,source),"actors_detached":not is_same(value.actors,source.actors),"rng_detached":not is_same(value.rng,source.rng)}
	return value
