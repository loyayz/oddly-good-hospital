extends SceneTree

const Cases = preload("res://tests/acceptance/wall_batch_view.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var input: String=""
	var fixture_kind: String=""
	var output: String=""
	var floor_id: int=2
	var repeats: int=3
	var selected_width: int=0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="): input=argument.trim_prefix("--input=")
		if argument.begins_with("--fixture="): fixture_kind=argument.trim_prefix("--fixture=")
		if argument.begins_with("--output="): output=argument.trim_prefix("--output=")
		if argument.begins_with("--floor="): floor_id=argument.trim_prefix("--floor=").to_int()
		if argument.begins_with("--repeats="): repeats=argument.trim_prefix("--repeats=").to_int()
		if argument.begins_with("--width="): selected_width=argument.trim_prefix("--width=").to_int()
	if input.is_empty()==fixture_kind.is_empty() or not fixture_kind in ["","geometry640"] or repeats<=0 or floor_id<1 or selected_width not in [0,85,96] or output.is_empty() or FileAccess.file_exists(output):
		push_error("Choose one complete input or --fixture=geometry640, a new output path, and width 85/96 (omitted runs both).")
		quit(2)
		return
	var policy: Dictionary={"applied":false,"reason":"platform_default"}
	if OS.get_name()=="Windows" and ClassDB.class_exists("PlatformThreadPolicy"): policy=ClassDB.class_call_static("PlatformThreadPolicy","apply_main_thread")
	var content: HospitalContent=HospitalContent.new()
	if not content.error.is_empty():
		push_error(content.error)
		quit(2)
		return
	var world: WorldState
	var fixture: RefCounted
	if fixture_kind=="geometry640":
		fixture=load("res://tools/performance/fixture.gd").new(content,640,"tall")
		if not fixture.errors.is_empty():
			push_error(str(fixture.errors))
			quit(2)
			return
		world=fixture.world
	else:
		var input_file: FileAccess=FileAccess.open(input,FileAccess.READ)
		if input_file==null:
			push_error("Cannot open the complete benchmark input.")
			quit(2)
			return
		var envelope: Variant=input_file.get_var(false)
		input_file.close()
		if not envelope is Dictionary or envelope.get("content_fingerprint","")!=content.content_fingerprint or not envelope.get("facts") is Dictionary:
			push_error("Input content or facts identity mismatch.")
			quit(2)
			return
		world=WorldState.new(envelope.facts)
	var declared: Dictionary={"tick":world.sim_tick,"rng":world.facts.rng.duplicate(true),"ledger":world.facts.ledger.duplicate(true),"actors":world.facts.actors.size(),"facilities":world.facts.facilities.size()}
	if fixture_kind=="geometry640":
		# Same ordinary service binding as SPACE-52, without a simulation step.
		var initializer: HospitalSimulation=HospitalSimulation.new(world,content)
		initializer.dispose()
	if HospitalSpace.floor_plots(world,floor_id).is_empty():
		push_error("The requested floor has no declared completed hospital plots.")
		quit(2)
		return
	var materialized: bool=not world.facts.floors.overrides.has(str(floor_id))
	# _plan does this before _change_walls. It only materializes layout for
	# already completed plots; ownership, height and connector stops stay intact.
	HospitalSpace.materialize_layout(world,floor_id)
	var preparation: Dictionary={"ordinary_services_initialized":fixture_kind=="geometry640","layout_materialized":materialized,"floor_id":floor_id,"completed_plots":HospitalSpace.floor_plots(world,floor_id).size(),"tick_unchanged":world.sim_tick==declared.tick,"rng_unchanged":world.facts.rng==declared.rng,"ledger_unchanged":world.facts.ledger==declared.ledger,"actor_count_unchanged":world.facts.actors.size()==declared.actors,"facility_count_unchanged":world.facts.facilities.size()==declared.facilities}
	var validation: String=world.validate(content)
	if not validation.is_empty() or not preparation.tick_unchanged or not preparation.rng_unchanged or not preparation.ledger_unchanged or not preparation.actor_count_unchanged or not preparation.facility_count_unchanged:
		push_error("Invalid hospital/floor input: "+validation)
		quit(2)
		return
	var facts: Dictionary=world.freeze()
	var rows: Array=[]
	var ok: bool=true
	for width: int in ([85,96] if selected_width==0 else [selected_width]):
		var row: Dictionary=Cases.new().measure(content,facts,floor_id,width,95,repeats)
		ok=ok and row.ok
		rows.append(row)
	var unchanged: bool=facts==world.freeze()
	var result: Dictionary={"complete":true,"ok":ok and unchanged,"scope":"Local wall planning only. geometry640 retains the complete SPACE-52 geometry load and ordinary initialization; a supplied input retains every current 160-person hospital fact. Neither is a full simulation performance acceptance.","input":input,"fixture":fixture_kind,"preparation":preparation,"actors":world.present_actor_count(),"staff":world.facts.staff.size(),"facilities":world.facts.facilities.size(),"tick":world.sim_tick,"world_revision":world.revision,"content_fingerprint":content.content_fingerprint,"main_thread_policy":policy,"repeats_per_variant":repeats,"prepared_input_facts_unchanged":unchanged,"cases":rows}
	var directory: String=output.get_base_dir()
	if not directory.is_empty() and DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))!=OK:
		push_error("Cannot create probe output directory.")
		quit(2)
		return
	var output_file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if output_file==null:
		push_error("Cannot write probe output.")
		quit(2)
		return
	output_file.store_string(JSON.stringify(result,"\t"))
	output_file.close()
	print("WALL_BATCH_PROBE="+JSON.stringify({"ok":result.ok,"actors":result.actors,"cases":rows.size(),"repeats_per_variant":repeats,"output":output}))
	quit(0 if result.ok else 1)
