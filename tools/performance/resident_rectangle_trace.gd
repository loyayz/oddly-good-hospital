extends RefCounted

static var active: bool = false
static var baseline: bool = false
static var replaying: bool = false
static var reference_replay: bool = false
static var thread_id: int = 0
static var mode: String = "counts"
static var stack: Array = []
static var rows: Array = []
static var errors: Array = []

static func start(selected: String) -> void:
	mode = selected
	thread_id = OS.get_thread_caller_id()
	stack.clear()
	rows.clear()
	errors.clear()
	active = true

static func observing() -> bool:
	return active and OS.get_thread_caller_id()==thread_id and not replaying

static func enter(kind: String, query: RefCounted, arguments: Array) -> void:
	stack.append({"kind":kind,"query":query,"arguments":arguments,"reason_calls":0,"blocked_id":-2,"rectangle":false,"depth":stack.size()})

static func reason() -> void:
	if observing() and not stack.is_empty(): stack[-1].reason_calls+=1

static func rectangle(low: Vector2i, high: Vector2i, blocked: int) -> void:
	if not observing() or stack.is_empty(): return
	stack[-1].low=low
	stack[-1].high=high
	stack[-1].blocked_id=blocked
	stack[-1].rectangle=true

static func leave(result: String) -> void:
	var frame: Dictionary = stack.pop_back()
	var query: Variant = frame.query
	var arguments: Array = frame.arguments
	if mode=="timing" and not (frame.kind=="sweep_reason" and (query._plain or query._height_m>float(query.source.height))):
		var first: Vector2 = arguments[0]
		var last: Vector2 = arguments[-1]
		frame.low=Vector2i(floori(minf(first.x,last.x)),floori(minf(first.y,last.y)))
		frame.high=Vector2i(ceili(maxf(first.x,last.x)),ceili(maxf(first.y,last.y)))
		replaying=true
		frame.blocked_id=query._resident_first_disabled(frame.low,frame.high)
		replaying=false
		frame.rectangle=true
	var eligible: bool = frame.rectangle and int(frame.blocked_id)>=-1
	var record: Dictionary = {"kind":frame.kind,"depth":frame.depth,"arguments":arguments.map(func(point: Vector2)->Array:return [point.x,point.y]),"size":query._size,"eligible":eligible,"reason":result,"actual_origin_reason_calls":frame.reason_calls if mode=="counts" else null,"blocked_id":frame.blocked_id}
	if frame.rectangle:
		record.low=[frame.low.x,frame.low.y]
		record.high=[frame.high.x,frame.high.y]
		record.origin_area=(frame.high.x-frame.low.x+1)*(frame.high.y-frame.low.y+1)
	if eligible:
		var legacy_calls: int = int(record.origin_area) if int(frame.blocked_id)==-1 else (int(frame.blocked_id)/96-frame.low.y)*(frame.high.x-frame.low.x+1)+int(frame.blocked_id)%96-frame.low.x+1
		record.legacy_origin_reason_calls=legacy_calls
	if eligible or mode=="timing":
		var reference: Callable = Callable(query,"_rectangle_original_"+frame.kind)
		var candidate: Callable = Callable(query,"_rectangle_body_"+frame.kind)
		replaying=true
		reference_replay=true
		var expected: String = reference.callv(arguments)
		reference_replay=false
		if expected!=result: errors.append({"kind":frame.kind,"expected":expected,"actual":result,"low":record.get("low",[]),"high":record.get("high",[])})
		if mode=="counts":
			var wanted: int = 0 if int(frame.blocked_id)==-1 else 1
			if frame.reason_calls!=wanted: errors.append({"kind":frame.kind,"expected_origin_calls":wanted,"actual":frame.reason_calls})
		else:
			record.timing=[]
			for repeat: int in 3:
				for label: String in (["reference","candidate"] if repeat%2==0 else ["candidate","reference"]):
					var operation: Callable = reference if label=="reference" else candidate
					reference_replay=label=="reference"
					var started_at: int = Time.get_ticks_usec()
					var value: String = operation.callv(arguments)
					var elapsed: int = Time.get_ticks_usec()-started_at
					record.timing.append({"repeat":repeat+1,"variant":label,"elapsed_usec":elapsed})
					if value!=result: errors.append({"kind":frame.kind,"variant":label,"expected":result,"actual":value})
		reference_replay=false
		replaying=false
	rows.append(record)

static func finish() -> Dictionary:
	active=false
	var eligible: int = 0
	var legacy: int = 0
	var actual: int = 0
	for row: Dictionary in rows:
		if not row.eligible: continue
		eligible+=1
		legacy+=int(row.legacy_origin_reason_calls)
		if mode=="counts": actual+=int(row.actual_origin_reason_calls)
	return {"mode":mode,"main_thread_only":true,"calls":rows.size(),"eligible":eligible,"legacy_origin_reason_calls":legacy,"actual_origin_reason_calls":actual if mode=="counts" else null,"replaced_origin_calls":legacy-actual if mode=="counts" else null,"errors":errors,"queries":rows,"scope":"Every actual main-thread position/sweep request during the selected real step. No candidate cap. Counts overlay has no timing claim; timing overlay leaves reason and helper uninstrumented and calls complete6e8d59c method bodies for A."}
