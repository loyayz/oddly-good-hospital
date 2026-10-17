extends "res://game/persistence/snapshot_store.gd"

var observer: Object

func _init(registry: HospitalContent, ownership: RefCounted, sink: Object) -> void:
	super(registry, ownership)
	observer = sink

func _begin_world(world: WorldState, session_id: String, kind: String, slot: String, identity: Dictionary = {}) -> Dictionary:
	var begin: int = Time.get_ticks_usec()
	var result: Dictionary = super._begin_world(world, session_id, kind, slot, identity)
	var request: Dictionary = result.get("request",{})
	_record("snapshot_begin_world_main_inclusive", begin, {"hospital_id":world.hospital_id,"session":session_id,"slot_kind":kind,"slot":slot,"ok":result.get("ok",false),"request_id":request.get("request_id",""),"snapshot_id":request.get("snapshot_id",""),"scope":"validate, estimate, freeze, thread launch; not isolated freeze-copy time"})
	return result

func _read_snapshot(database: RefCounted, hospital_id: String, snapshot_id: String, sealed: bool = true) -> Dictionary:
	var begin: int = Time.get_ticks_usec()
	var result: Dictionary = super._read_snapshot(database, hospital_id, snapshot_id, sealed)
	_record("snapshot_read_decode_validate_main_inclusive", begin, {"hospital_id":hospital_id,"snapshot_id":snapshot_id,"sealed":sealed,"ok":result.get("ok",false)})
	return result

func _validate_world(value: Dictionary, manifest: Dictionary) -> Dictionary:
	var begin: int = Time.get_ticks_usec()
	var result: Dictionary = super._validate_world(value, manifest)
	_record("snapshot_world_validate_main_inclusive", begin, {"hospital_id":manifest.get("hospital_id",""),"ok":result.get("ok",false)})
	return result

func _record(stage: String, begin: int, details: Dictionary) -> void:
	# Backup/import workers can use these same methods. Never mutate the main
	# observer buffer from those threads or mislabel their time as main-thread work.
	if OS.get_thread_caller_id()!=OS.get_main_thread_id(): return
	var end: int = Time.get_ticks_usec()
	observer._emit("main_phase", {"stage":stage,"begin_us":begin,"end_us":end,"elapsed_us":end-begin,"inclusive":true,"details":details}, end)
