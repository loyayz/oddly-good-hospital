extends SceneTree

var _input: String = ""
var _output: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="):
			_input = argument.trim_prefix("--input=")
		elif argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	call_deferred("_run")

func _run() -> void:
	if _input.is_empty() or _output.is_empty():
		push_error("Supply --input=<replay.json> --output=<facts.json> after --.")
		quit(2)
		return
	var file: FileAccess = FileAccess.open(_input,FileAccess.READ)
	if file==null:
		push_error("Replay input cannot be read.")
		quit(2)
		return
	var size: int = file.get_length()
	file.close()
	var codec: HospitalJsonStream = HospitalJsonStream.new()
	var decoded: Dictionary = codec.decode(_input,size,FileAccess.get_sha256(_input),func(_bytes: int) -> bool: return true)
	if not decoded.ok:
		push_error(decoded.error)
		quit(2)
		return
	var record: Dictionary = decoded.value
	if not record.get("initial_world") is Dictionary or not record.get("commands") is Array or not record.get("target_tick") is int:
		push_error("Replay requires initial_world, commands and integer target_tick.")
		quit(2)
		return
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = WorldState.new(record.initial_world)
	var error: String = world.validate(content)
	if not error.is_empty() or int(record.target_tick)<world.sim_tick:
		push_error(error if not error.is_empty() else "Target tick precedes the initial world.")
		quit(2)
		return
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	var cursor: int = 0
	var results: Array[Dictionary] = []
	while world.sim_tick<=int(record.target_tick):
		while cursor<record.commands.size():
			var row: Variant = record.commands[cursor]
			if not row is Dictionary or not row.get("at_tick") is int or not row.get("command") is Dictionary or int(row.at_tick)<world.sim_tick:
				push_error("Replay commands must be in execution-boundary order.")
				quit(2)
				return
			if int(row.at_tick)>world.sim_tick:
				break
			var command_record: Dictionary = row.command
			if not command_record.get("id") is String or not command_record.get("hospital_id") is String or not command_record.get("kind") is String or not command_record.get("expected_revision") is int or not command_record.get("typed_payload") is Dictionary:
				push_error("Replay requires a typed GameCommand record.")
				quit(2)
				return
			var command: GameCommand = GameCommand.from_record(command_record)
			if command.kind=="move_actor" and not command.typed_payload is MoveActorPayload:
				push_error("Replay move payload requires an exact integer target and complete confirmed_location.")
				quit(2)
				return
			var result: CommandResult = simulation.apply(command)
			results.append({"at_tick":world.sim_tick,"command_id":command.id,"result":result.to_record()})
			cursor += 1
		if world.sim_tick==int(record.target_tick):
			break
		simulation.step(world,[])
	if cursor!=record.commands.size():
		push_error("Replay contains commands after the requested target tick.")
		quit(2)
		return
	var canonical: String = JSON.stringify(world.facts,"",true,true)
	var report: Dictionary = {"sim_tick":world.sim_tick,"facts":world.freeze(),"rng_end":world.facts.rng.duplicate(true),"facts_sha256":canonical.sha256_text(),"command_results":results}
	var output: FileAccess = FileAccess.open(_output,FileAccess.WRITE)
	if output==null:
		push_error("Replay output cannot be written.")
		quit(2)
		return
	output.store_string(JSON.stringify(report,"\t",true,true))
	quit(0)
