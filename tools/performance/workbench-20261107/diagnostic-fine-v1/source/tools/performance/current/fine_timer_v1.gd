extends RefCounted
static var active: bool = false
static var stack: Array = []
static var rows: Dictionary = {}
static var errors: Array = []
static func begin() -> void:
	active=true;stack=[];rows={};errors=[]
static func enter(name: String) -> void:
	if not active: return
	stack.append({"name":name,"start":Time.get_ticks_usec(),"children":0})
static func leave(name: String) -> void:
	if not active: return
	var now: int = Time.get_ticks_usec()
	if stack.is_empty() or stack.back().name!=name: errors.append("stack mismatch "+name);return
	var frame: Dictionary = stack.pop_back()
	var elapsed: int = now-int(frame.start)
	var row: Dictionary = rows.get(name,{"calls":0,"inclusive_us":0,"exclusive_us":0,"max_us":0})
	row.calls+=1;row.inclusive_us+=elapsed;row.exclusive_us+=elapsed-int(frame.children);row.max_us=maxi(row.max_us,elapsed);rows[name]=row
	if not stack.is_empty(): stack.back().children+=elapsed
static func finish() -> Dictionary:
	active=false
	if not stack.is_empty(): errors.append("unclosed calls")
	return {"rows":rows.duplicate(true),"errors":errors.duplicate()}
