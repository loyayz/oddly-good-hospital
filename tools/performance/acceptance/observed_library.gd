extends "res://game/persistence/hospital_library.gd"

var observer: Object

func _init(registry: HospitalContent, store: HospitalSnapshots, sink: Object) -> void:
	super(registry, store)
	observer = sink

func continue_hospital(hospital_id: String, snapshot_id: String = "") -> Dictionary:
	var begin: int = Time.get_ticks_usec()
	var result: Dictionary = super.continue_hospital(hospital_id, snapshot_id)
	var end: int = Time.get_ticks_usec()
	observer._emit("main_phase", {"stage":"continue_hospital_main_inclusive","hospital_id":hospital_id,"snapshot_id":snapshot_id,"begin_us":begin,"end_us":end,"elapsed_us":end-begin,"ok":result.get("ok",false),"inclusive":true}, end)
	return result
