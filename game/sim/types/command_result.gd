class_name CommandResult
extends RefCounted

var accepted: bool
var code: String
var reason: String
var changed_ids: Array[String]
var new_revision: int

func _init(ok: bool = false, result_code: String = "", message: String = "", changed: Array = [], revision: int = 0) -> void:
	accepted = ok
	code = result_code
	reason = message
	changed_ids.assign(changed)
	new_revision = revision

func to_record() -> Dictionary:
	return {"accepted":accepted,"code":code,"reason":reason,"changed_ids":changed_ids.duplicate(),"new_revision":new_revision}

static func from_record(record: Dictionary) -> CommandResult:
	var changed: Array[String] = []
	changed.assign(record.get("changed_ids",[]))
	return CommandResult.new(record.accepted,str(record.get("code","applied" if record.accepted else "rejected")),str(record.get("reason","")),changed,int(record.get("new_revision",0)))
