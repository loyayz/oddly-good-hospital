extends SceneTree
var results: Dictionary = {}
func _initialize() -> void:
	call_deferred("_run")
func check(id: String, passed: bool, details: Dictionary) -> void:
	results[id] = {"passed":passed,"details":details}
	print("CASE "+id+" "+("PASS" if passed else "FAIL")+" "+JSON.stringify(details))
func _run() -> void:
	var suite: RefCounted = preload("res://tests/acceptance/natural_admission.gd").new()
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var group: String = arguments[1] if arguments.size()>1 else "all"
	if group=="all":
		await suite.run(self)
	elif group in ["surgery-policy","mixed-pool"]:
		suite._content = HospitalContent.new()
		if group=="surgery-policy": suite._surgery_policy(self)
		else: await suite._mixed_treatment_pool(self)
		suite._dispose_simulations()
	else:
		push_error("Unknown natural-admission test group: "+group)
		quit(2)
		return
	var failed: int = 0
	for item: Dictionary in results.values():
		if not item.passed: failed += 1
	var path: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "res://natural-admission-results.json"
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"failed":failed,"checks":results.size(),"results":results},"\t"))
	quit(1 if failed>0 else 0)
