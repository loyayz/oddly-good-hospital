extends RefCounted

# The native value is Windows QueryPerformanceCounter, the same raw domain
# selected by PresentMon --qpc_time. Engine timestamps still need a bracket.
static func available() -> bool:
	return ClassDB.class_exists("PlatformArrivalMath") and ClassDB.class_has_method("PlatformArrivalMath", "monotonic_clock")

static func read() -> Dictionary:
	var value: Variant = ClassDB.class_call_static("PlatformArrivalMath", "monotonic_clock")
	if not value is Dictionary or int(value.get("qpc_frequency", 0))<=0 or int(value.get("qpc_ticks", -1))<0:
		return {"qpc_ticks":null,"qpc_frequency":null,"clock_error":"Native monotonic_clock failed","native_result":value}
	return {"qpc_ticks":int(value.qpc_ticks),"qpc_frequency":int(value.qpc_frequency)}
