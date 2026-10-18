extends SceneTree

# Resume an actually measured complete boundary. This never supplies progress,
# positions or completion and is separate from the fixed-window qualification.
func _initialize() -> void:
	var options: Dictionary = {"source":"","final":"","output":""}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument: options[argument.trim_prefix("--").get_slice("=",0)] = argument.substr(argument.find("=")+1)
	if not FileAccess.file_exists(options.source) or not FileAccess.file_exists(options.final) or str(options.output).is_empty() or FileAccess.file_exists(options.output):
		push_error("Expected original input, completed final binary and new output")
		quit(2)
		return
	var content: HospitalContent = HospitalContent.new()
	var file: FileAccess = FileAccess.open(options.source,FileAccess.READ)
	var payload: Dictionary = file.get_var()
	file.close()
	file = FileAccess.open(options.final,FileAccess.READ)
	var ending: Dictionary = file.get_var()
	file.close()
	var world: WorldState = WorldState.new(ending.facts)
	var original_ids: Array = payload.facts.actors.keys()
	var actual_ids: Array = world.facts.actors.keys()
	original_ids.sort()
	actual_ids.sort()
	if payload.content_fingerprint!=content.content_fingerprint or original_ids!=actual_ids or world.present_actor_count()!=160 or not world.validate(content).is_empty():
		push_error("Measured boundary failed content, actor identity or world validation")
		quit(2)
		return
	payload.facts = ending.facts
	payload.representative_clinical.metadata = {"public_input":{"diagnostic_continuation":true,"source_input_sha256":FileAccess.get_sha256(options.source),"source_final_sha256":FileAccess.get_sha256(options.final),"source_final_path":options.final}}
	file = FileAccess.open(options.output,FileAccess.WRITE)
	file.store_var(payload)
	file.close()
	print("CONTINUATION_INPUT="+JSON.stringify({"output":options.output,"sha256":FileAccess.get_sha256(options.output),"tick":world.sim_tick,"present":world.present_actor_count(),"world_facts_unchanged":payload.facts==ending.facts,"diagnostic_only":true}))
	quit(0)
