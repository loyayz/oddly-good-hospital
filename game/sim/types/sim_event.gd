class_name SimEvent
extends RefCounted

var sim_tick: int
var kind: String
var changed_ids: Array[String]
var details: Dictionary

func _init(tick: int = 0, event_kind: String = "", changed: Array = [], values: Dictionary = {}) -> void:
	sim_tick = tick
	kind = event_kind
	changed_ids.assign(changed)
	details = values.duplicate(true)

func to_record() -> Dictionary:
	return {"sim_tick":sim_tick,"kind":kind,"changed_ids":changed_ids.duplicate(),"details":details.duplicate(true)}
