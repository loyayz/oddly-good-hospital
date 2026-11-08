extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	if OS.get_cmdline_user_args().size()!=1: quit(2);return
	var suite: RefCounted=load("res://tests/acceptance/space.gd").new()
	suite.content=HospitalContent.new()
	var row: Dictionary=suite._case_51(null)
	var f:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
	f.store_string(JSON.stringify({"scope":"SPACE-51 route permissions, graph/cache lifecycle, structural batches and actual waiting dispatch","result":row},"\t"));f.close()
	print("MULTICORE_INTEGRATION ",row.ok)
	quit(0 if row.ok else 1)
