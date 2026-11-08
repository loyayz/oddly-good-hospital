extends SceneTree
class Recorder:
	extends RefCounted
	var rows: Array=[]
	func check(id: String, passed: bool, details: Dictionary={}) -> void: rows.append({"case":id,"passed":passed,"details":details})
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var content:=HospitalContent.new()
	var suite: RefCounted=load("res://tests/acceptance/space.gd").new();suite.content=content
	var rows: Array=[]
	rows.append({"case":"navigation_distance_fields","result":load("res://tests/acceptance/navigation_distance_fields.gd").new().run(suite)})
	rows.append({"case":"navigation_static_versions","result":load("res://tests/acceptance/navigation_static_versions.gd").new().run()})
	rows.append({"case":"waiting_target_occupancy","result":load("res://tests/acceptance/waiting_target_occupancy.gd").new().run(content)})
	var recorder:=Recorder.new()
	for id: String in ["STAFF-47","STAFF-48","STAFF-68"]: load("res://tests/acceptance/public_area_use.gd").new().run(recorder,content,id)
	var ok: bool=true
	for row: Dictionary in rows: ok=ok and row.result.get("ok",row.result.get("passed",false))
	for row: Dictionary in recorder.rows: ok=ok and row.passed
	var f:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);f.store_string(JSON.stringify({"passed":ok,"groups":rows,"staff":recorder.rows},"\t"));f.close()
	print("MULTICORE_REMAINING ",ok);quit(0 if ok else 1)
