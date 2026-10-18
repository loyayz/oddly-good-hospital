extends SceneTree

func _initialize() -> void:
	var paths: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			paths[argument.trim_prefix("--").get_slice("=",0)] = argument.substr(argument.find("=")+1)
	if not paths.has("before") or not paths.has("after"):
		push_error("Use --before and --after complete binary boundaries")
		quit(2)
		return
	var before: Dictionary = FileAccess.open(paths.before,FileAccess.READ).get_var()
	var after: Dictionary = FileAccess.open(paths.after,FileAccess.READ).get_var()
	var changed: Array = []
	for key: String in before.facts:
		if not after.facts.has(key) or before.facts[key]!=after.facts[key]: changed.append(key)
	for key: String in after.facts:
		if not before.facts.has(key): changed.append(key)
	var added: Dictionary = {}
	var removed: Array = []
	for id: String in after.facts.actors:
		if not before.facts.actors.has(id): added[id] = after.facts.actors[id]
	for id: String in before.facts.actors:
		if not after.facts.actors.has(id): removed.append(id)
	var events_equal: bool = before.get("events",[])==after.get("events",[])
	var report: Dictionary = {"facts_equal":before.facts==after.facts,"rng_equal":before.facts.rng==after.facts.rng,
		"events_equal":events_equal,"changed_fact_fields":changed,"added_actors":added,"removed_actors":removed,
		"before_sha256":FileAccess.get_sha256(paths.before),"after_sha256":FileAccess.get_sha256(paths.after)}
	if paths.has("output"):
		var file: FileAccess = FileAccess.open(paths.output,FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"\t"))
	print("REPRESENTATIVE_COMPARE="+JSON.stringify(report))
	quit(0 if report.facts_equal and events_equal else 1)
