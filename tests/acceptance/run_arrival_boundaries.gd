extends SceneTree
var rows: Array = []
func _initialize() -> void: call_deferred("_run")
func check(id: String, passed: bool, details: Variant = null) -> void:
	rows.append({"id":id,"passed":passed,"details":details});print("ARRIVAL_BOUNDARY ",id," ",passed)
func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var result: Dictionary = load("res://tests/acceptance/public_arrival_boundaries.gd").new().run_boundaries(content)
	check("GEOMETRY-AND-TRANSIT",result.ok,result)
	var ownership: Dictionary = load("res://tests/acceptance/arrival_entry_ownership_edges.gd").new().run_entry_ownership_edges(content)
	check("ENTRY-OWNERSHIP-EDGES",ownership.ok,ownership)
	var phases: RefCounted = load("res://tests/acceptance/public_phase_use.gd").new()
	phases._content = content
	for id: String in ["72","73","74"]: phases.call("_case_"+id,self)
	var passed: bool = rows.all(func(row: Dictionary)->bool:return row.passed)
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"cases":rows},"\t"))
	quit(0 if passed else 1)
