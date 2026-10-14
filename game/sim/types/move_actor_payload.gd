class_name MoveActorPayload
extends RefCounted

var actor_id: String
var floor_id: int
var cell: Vector2i
var confirmed_location: Dictionary

func _init(actor: String = "", floor: int = 1, target: Vector2i = Vector2i.ZERO, original: Dictionary = {}) -> void:
	actor_id = actor
	floor_id = floor
	cell = target
	confirmed_location = original.duplicate(true)

func to_record() -> Dictionary:
	return {"actor_id":actor_id,"floor_id":floor_id,"cell":[cell.x,cell.y],"confirmed_location":confirmed_location.duplicate(true)}

static func from_record(record: Dictionary) -> MoveActorPayload:
	var point: Variant = record.get("cell")
	if not record.get("actor_id") is String or not record.get("floor_id") is int or not point is Array or point.size()!=2:
		return null
	for value: Variant in point:
		if not value is int and not value is float or not is_finite(float(value)) or float(value)!=floorf(float(value)) or float(value)<-2147483648.0 or float(value)>2147483647.0:
			return null
	var confirmation: Variant = record.get("confirmed_location",{})
	if not confirmation is Dictionary or not confirmation.is_empty() and not _valid_confirmation(confirmation):
		return null
	return MoveActorPayload.new(record.actor_id,record.floor_id,Vector2i(int(point[0]),int(point[1])),confirmation)

static func _valid_confirmation(location: Dictionary) -> bool:
	match location.get("kind"):
		"floor":
			var point: Variant = location.get("cell")
			if not location.get("floor_id") is int or not point is Array or point.size()!=2:
				return false
			for value: Variant in point:
				if not value is int and not value is float or not is_finite(float(value)):
					return false
			var height: Variant = location.get("height_m",0.0)
			return (height is int or height is float) and is_finite(float(height))
		"transit":
			return location.get("connector_id") is String and location.get("from") is int and location.get("to") is int
		"outside":
			return true
	return false
