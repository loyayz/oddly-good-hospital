class_name GameCommand
extends RefCounted

var id: String
var hospital_id: String
var expected_revision: int
var kind: String
var typed_payload: RefCounted
var loading_session_id: String

func _init(command_id: String = "", hospital: String = "", revision: int = -1, command_kind: String = "", payload: RefCounted = null, session: String = "") -> void:
	id = command_id
	hospital_id = hospital
	expected_revision = revision
	kind = command_kind
	typed_payload = payload
	loading_session_id = session

func to_record() -> Dictionary:
	return {"id":id,"hospital_id":hospital_id,"expected_revision":expected_revision,"kind":kind,
		"typed_payload":typed_payload.to_record() if typed_payload!=null else {},"loading_session_id":loading_session_id}

func identity() -> Dictionary:
	return {"hospital_id":hospital_id,"kind":kind,"typed_payload":typed_payload.to_record() if typed_payload!=null else {}}

static func from_record(record: Dictionary) -> GameCommand:
	var payload: RefCounted = null
	if record.get("kind","")=="move_actor":
		var source: Variant = record.get("typed_payload",record)
		if source is Dictionary:
			payload = MoveActorPayload.from_record(source)
			if record.has("typed_payload") and payload!=null and payload.confirmed_location.is_empty():
				payload = null
	elif record.get("typed_payload") is Dictionary:
		payload = BusinessPayload.new(record.typed_payload)
	return GameCommand.new(str(record.get("id","")),str(record.get("hospital_id","")),int(record.get("expected_revision",-1)),str(record.get("kind","")),payload,str(record.get("loading_session_id","")))
