extends SceneTree
func _initialize() -> void:
	var args: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg: args[arg.trim_prefix("--").get_slice("=",0)]=arg.substr(arg.find("=")+1)
	if not args.has("before") or not args.has("after") or not args.has("output") or FileAccess.file_exists(args.output): quit(2);return
	var f: FileAccess = FileAccess.open(args.before,FileAccess.READ)
	var before: Dictionary = f.get_var(false);f.close()
	f=FileAccess.open(args.after,FileAccess.READ);var after: Dictionary=f.get_var(false);f.close()
	var added: Dictionary = {}
	var removed: Array = []
	for id: String in after.facts.actors:
		if not before.facts.actors.has(id): added[id]=after.facts.actors[id]
	for id: String in before.facts.actors:
		if not after.facts.actors.has(id): removed.append(id)
	var changed_original_facilities: Array = []
	for id: String in before.facts.facilities:
		if not after.facts.facilities.has(id) or before.facts.facilities[id].definition_id!=after.facts.facilities[id].definition_id: changed_original_facilities.append(id)
	f=FileAccess.open(args.output,FileAccess.WRITE)
	f.store_string(JSON.stringify({"added_actors":added,"removed_actors":removed,"changed_original_facility_id_or_definition":changed_original_facilities,"events":after.get("events",[]),"before_sha256":FileAccess.get_sha256(args.before),"after_sha256":FileAccess.get_sha256(args.after),"final_facts":after.facts},"\t"));f.close();quit(0)
