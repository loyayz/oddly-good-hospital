extends RefCounted

static var active: bool=false
static var stack: Array=[]
static var rows: Dictionary={}
static var errors: Array=[]

static func begin() -> void:
	active=true
	stack=[]
	rows={}
	errors=[]

static func enter(name: String) -> void:
	if active: stack.append({"name":name,"started":Time.get_ticks_usec(),"children":0})

static func leave(name: String, value: Variant=null) -> void:
	if not active: return
	var now: int=Time.get_ticks_usec()
	if stack.is_empty() or stack.back().name!=name:
		errors.append("Unbalanced timer: "+name)
		return
	var frame: Dictionary=stack.pop_back()
	var elapsed: int=now-int(frame.started)
	var row: Dictionary=rows.get(name,{"calls":0,"inclusive_us":0,"exclusive_us":0,"max_us":0})
	row.calls+=1
	row.inclusive_us+=elapsed
	row.exclusive_us+=elapsed-int(frame.children)
	row.max_us=maxi(int(row.max_us),elapsed)
	if value is Dictionary:
		row.returned_entries=int(row.get("returned_entries",0))+value.size()
		if value.has("cells"):
			row.returned_cells=int(row.get("returned_cells",0))+value.cells.size()
		if value.has("closed"):
			var field: String="closed_components" if value.closed else "open_components"
			row[field]=int(row.get(field,0))+1
	elif value is Array or value is PackedInt32Array:
		row.returned_cells=int(row.get("returned_cells",0))+value.size()
	rows[name]=row
	if not stack.is_empty(): stack.back().children+=elapsed

static func finish() -> Dictionary:
	active=false
	if not stack.is_empty(): errors.append("Unclosed timer")
	return {"rows":rows,"errors":errors,"scope":"Diagnostic inclusive/exclusive wall spans. Exclusive subtracts only other probed descendants and still includes unprobed work and instrumentation overhead."}
