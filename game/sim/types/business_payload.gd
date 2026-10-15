class_name BusinessPayload
extends RefCounted

var _record: Dictionary

func _init(record: Dictionary = {}) -> void:
	_record = record.duplicate(true)

func to_record() -> Dictionary:
	return _record.duplicate(true)
