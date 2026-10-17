extends SceneTree

const Fixture = preload("res://tools/performance/fixture.gd")
const Inputs = preload("res://tools/performance/acceptance/fixtures/prepare_inputs.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source: String = ""
	var output: String = ""
	var mode: String = ""
	var maximum_steps: int = 18000
	var maximum_us: int = 3600000000
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="): source = argument.trim_prefix("--input=")
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument.begins_with("--mode="): mode = argument.trim_prefix("--mode=")
		if argument.begins_with("--maximum-steps="): maximum_steps = argument.trim_prefix("--maximum-steps=").to_int()
		if argument.begins_with("--maximum-real-seconds="): maximum_us = argument.trim_prefix("--maximum-real-seconds=").to_int()*1000000
	if source.is_empty() or output.is_empty() or not mode in ["clinical_midstep","day_boundary_before"] or FileAccess.file_exists(output):
		push_error("Expected existing --input, new --output and --mode=clinical_midstep|day_boundary_before.")
		quit(2)
		return
	var started: int = Time.get_ticks_usec()
	var content: HospitalContent = HospitalContent.new()
	var fixture: RefCounted = Fixture.new(content,160,"four_floors",source)
	var world: WorldState = fixture.world
	var validation: String = world.validate(content)
	if not validation.is_empty() or not fixture.errors.is_empty():
		push_error("Source validation failed: "+validation+JSON.stringify(fixture.errors))
		quit(2)
		return
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	var boundary_source_tick: int = (world.sim_tick/WorldState.TICKS_PER_DAY+1)*WorldState.TICKS_PER_DAY
	# Default visible warmup is 32 real complete steps. Keep 64 ticks before
	# the actual day-source boundary; never warm past the operation under test.
	var target_tick: int = boundary_source_tick-64
	var steps: int = 0
	var witness: Dictionary = _clinical_witness(world) if mode=="clinical_midstep" else {}
	while (mode=="clinical_midstep" and witness.is_empty()) or (mode=="day_boundary_before" and world.sim_tick<target_tick):
		if steps>=maximum_steps or Time.get_ticks_usec()-started>=maximum_us:
			_write_failure(output,{"ok":false,"mode":mode,"reason":"No legal named boundary before watchdog.","steps":steps,"tick":world.sim_tick,
				"target_tick":target_tick,"population":Inputs.population_of(world),"sessions":world.facts.sessions.size(),"preparations":world.facts.preparations.size(),"ward_stays":world.facts.ward_stays.size()})
			simulation.dispose()
			quit(1)
			return
		var result: TickResult = simulation.step_nonblocking()
		while result==null:
			if not simulation.preparing_error().is_empty() or Time.get_ticks_usec()-started>=maximum_us:
				_write_failure(output,{"ok":false,"mode":mode,"reason":"Original boundary did not complete.","error":simulation.preparing_error(),"steps":steps,"tick":world.sim_tick})
				simulation.dispose()
				quit(1)
				return
			await process_frame
			result = simulation.step_nonblocking()
		steps += 1
		witness = _clinical_witness(world) if mode=="clinical_midstep" else {}
		await process_frame
	validation = world.validate(content)
	var day_valid: bool = mode!="day_boundary_before" or (world.sim_tick==target_tick and not world.facts.arrivals.plan.is_empty() and int(world.facts.arrivals.plan.day_index)==world.sim_tick/WorldState.TICKS_PER_DAY+1)
	if not validation.is_empty() or not day_valid or simulation.step_in_progress():
		_write_failure(output,{"ok":false,"reason":"Final named boundary invalid.","validation":validation,"day_valid":day_valid})
		simulation.dispose()
		quit(1)
		return
	fixture.store_input(output)
	var metadata: Dictionary = {"ok":true,"preparation_only":true,"mode":mode,"input_path":output,"source":source,"source_sha256":FileAccess.get_sha256(source),
		"input_sha256":FileAccess.get_sha256(output),"hospital_id":world.hospital_id,"content_fingerprint":content.content_fingerprint,
		"engine":Engine.get_version_info().string,"tick":world.sim_tick,"actual_steps":steps,"preparation_us":Time.get_ticks_usec()-started,
		"population":Inputs.population_of(world),"witness":witness,"validation":validation,
		"boundary_note":"Complete production steps; no clock/phase/remaining-work rewrite, no actor hold or random reseed."}
	if mode=="day_boundary_before":
		metadata.boundary_source_tick = boundary_source_tick
		metadata.target_executed_tick = boundary_source_tick
		metadata.target_completed_tick = boundary_source_tick+1
		metadata.target_day_index = boundary_source_tick/WorldState.TICKS_PER_DAY+1
		metadata.pre_boundary_margin_ticks = 64
	var file: FileAccess = FileAccess.open(output+".manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata,"\t"))
	file.close()
	print("ACCEPTANCE_BOUNDARY="+JSON.stringify(metadata))
	simulation.dispose()
	quit(0)

func _clinical_witness(world: WorldState) -> Dictionary:
	for session: Dictionary in world.facts.sessions.values():
		if session.kind in ["outpatient","surgery"] and int(session.remaining_ticks)>=64 and int(session.remaining_ticks)<int(session.total_ticks):
			return {"owner":"session","id":session.id,"visit_id":session.visit_id,"kind":session.kind,
				"total_ticks":session.total_ticks,"remaining_ticks":session.remaining_ticks,"facility_id":session.facility_id,"staff_ids":session.staff_ids.duplicate()}
	return {}

func _write_failure(output: String, details: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(output+".blocked.json",FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(details,"\t"))
		file.close()
	push_error(JSON.stringify(details))
