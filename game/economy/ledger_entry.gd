class_name LedgerEntry
extends RefCounted

var owner_id: String
var component: String
var amount: int
var entry_id: String:
	get:
		return owner_id+":"+component

func _init(owner: String = "", part: String = "", value: int = 0) -> void:
	owner_id = owner
	component = part
	amount = value
