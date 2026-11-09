extends RefCounted

func _worker() -> Dictionary:
	return ClassDB.class_call_static("PlatformThreadPolicy","apply_main_thread")

func run(t) -> void:
	if not ClassDB.class_exists("PlatformThreadPolicy"):
		t.check("CORE-56",false,{"reason":"native_policy_missing"})
		return
	var first: Dictionary = ClassDB.class_call_static("PlatformThreadPolicy","apply_main_thread")
	var repeated: Dictionary = ClassDB.class_call_static("PlatformThreadPolicy","apply_main_thread")
	var thread: Thread = Thread.new()
	var started: Error = thread.start(_worker)
	var worker: Dictionary = thread.wait_to_finish() if started==OK else {}
	var valid: bool = started==OK
	if OS.get_name()=="Windows":
		valid = valid and not worker.get("applied",true) and worker.get("reason","")=="not_main_thread"
		valid = valid and first.has("hybrid") and not str(first.get("reason","")).is_empty()
		if first.get("applied",false):
			valid = valid and first.get("mask_hex","")!="0" and repeated.get("applied",false) and repeated.get("mask_hex","")==first.mask_hex and repeated.get("reason","")=="already_performance"
	else:
		valid = valid and not first.get("applied",true) and first.get("reason","")=="platform_default" and not worker.get("applied",true)
	t.check("CORE-56",valid,{"first":first,"repeated":repeated,"worker":worker})
