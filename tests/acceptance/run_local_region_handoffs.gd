extends SceneTree
class Recorder:
	extends RefCounted
	var rows: Array=[]
	func check(id: String, passed: bool, details: Dictionary={}) -> void: rows.append({"id":id,"passed":passed,"details":details})
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var content:=HospitalContent.new()
	var occupancy: Dictionary=load("res://tests/acceptance/waiting_target_occupancy.gd").new().run(content)
	var recorder:=Recorder.new()
	load("res://tests/acceptance/public_area_use.gd").new().run(recorder,content,"STAFF-68")
	var passed: bool=occupancy.get("ok",occupancy.get("passed",false)) and not recorder.rows.is_empty() and recorder.rows.all(func(row: Dictionary)->bool:return row.passed)
	var f:=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);f.store_string(JSON.stringify({"passed":passed,"occupancy":occupancy,"life_handoff":recorder.rows},"\t"));f.close();print("HANDOFFS ",passed);quit(0 if passed else 1)
