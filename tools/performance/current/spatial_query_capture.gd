extends RefCounted

# Installed only in an isolated diagnostic BodyIndex. There is no production
# flag or timed hook. The stream retains every native tree mutation and query.
static var _file: FileAccess
static var _mutex: Mutex = Mutex.new()
static var _next: int = 0
static var counts: Dictionary = {}
static var errors: Array = []

static func begin(path: String, header: Dictionary) -> bool:
	if _file!=null or FileAccess.file_exists(path): return false
	_file=FileAccess.open(path,FileAccess.WRITE)
	if _file==null: return false
	_next=0; counts={}; errors=[]
	_file.store_var({"format":"spatial-query-stream-v1","header":header})
	return true

static func register_index() -> int:
	_mutex.lock()
	var id: int = 0
	if _file!=null:
		_next+=1; id=_next
		_file.store_var(["index",id])
		counts["index"]=int(counts.get("index",0))+1
	_mutex.unlock()
	return id

static func event(value: Array) -> void:
	_mutex.lock()
	if _file!=null:
		if int(value[1])<=0: errors.append("A BodyIndex existed before capture registration")
		_file.store_var(value)
		counts[str(value[0])]=int(counts.get(str(value[0]),0))+1
	_mutex.unlock()

static func finish(footer: Dictionary) -> Dictionary:
	_mutex.lock()
	var result: Dictionary = {"counts":counts.duplicate(),"errors":errors.duplicate(),"footer":footer}
	if _file!=null:
		_file.store_var(["end",result]); _file.close(); _file=null
	_mutex.unlock()
	return result
