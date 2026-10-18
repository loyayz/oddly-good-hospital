extends SceneTree

# Separate the new hospital's first allocation from already-assigned step
# measurements. This is a declared unassigned boundary, not save migration.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var options: Dictionary = {"input":"","output":""}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument: options[argument.trim_prefix("--").get_slice("=",0)] = argument.substr(argument.find("=")+1)
	if not FileAccess.file_exists(options.input) or str(options.output).is_empty() or FileAccess.file_exists(options.output): quit(2); return
	var content: HospitalContent = HospitalContent.new()
	var file: FileAccess = FileAccess.open(options.input,FileAccess.READ)
	var input: Dictionary = file.get_var()
	file.close()
	var world: WorldState = WorldState.new(input.facts)
	# All staff are idle in this input; no actual sleep or public reservations
	# are removed. Only the initial unassigned relation is declared.
	for reservation: Dictionary in world.facts.staff_life.reservations.values():
		if reservation.kind=="sleep": quit(2); return
	world.facts.staff_life.personal_beds = {}
	var before: Dictionary = world.freeze()
	var space: HospitalSpace = HospitalSpace.new(content)
	var service: HospitalStaffWellbeing = HospitalStaffWellbeing.new(content,space)
	var started: int = Time.get_ticks_usec()
	service.ensure(world)
	var first: int = Time.get_ticks_usec()-started
	var assigned_queries: Dictionary = space.query_counts.duplicate()
	started = Time.get_ticks_usec()
	service.ensure(world)
	var repeated: int = Time.get_ticks_usec()-started
	var validation: String = world.validate(content)
	var same: bool = before.actors==world.facts.actors and before.moves==world.facts.moves and before.adaptations==world.facts.adaptations and before.tickets==world.facts.tickets and before.sessions==world.facts.sessions
	var report: Dictionary = {"diagnostic_only":true,"formal_pass":false,"input_sha256":FileAccess.get_sha256(options.input),"declared_boundary":"existing idle staff and existing compatible beds, initially unassigned","present":world.present_actor_count(),"staff":world.facts.staff.size(),"beds":world.facility_ids("SE04").size(),"initial_allocation_us":first,"repeat_ensure_us":repeated,"allocation_query_counts":assigned_queries,"repeat_added_queries":{},"owners":world.facts.staff_life.personal_beds,"no_movement_or_clinical_changes":same,"validation":validation}
	for key: String in space.query_counts: report.repeat_added_queries[key] = int(space.query_counts[key])-int(assigned_queries[key])
	report.ok = same and validation.is_empty() and world.present_actor_count()==160
	file = FileAccess.open(options.output,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("PERSONAL_BED_PROBE="+JSON.stringify(report))
	quit(0 if report.ok else 1)
