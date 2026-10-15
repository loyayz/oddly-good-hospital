extends SceneTree

var _failures: Array[String] = []
var _app: Control

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not "stage24" in OS.get_user_data_dir().to_lower().replace(" ",""):
		push_error("Recovery verification requires a fresh isolated Stage24 user directory")
		quit(2)
		return
	var guard: RefCounted = ClassDB.instantiate("PlatformSessionGuard") as RefCounted
	if not guard.call("acquire").ok:
		quit(2)
		return
	var content: HospitalContent = HospitalContent.new()
	var snapshots: HospitalSnapshots = HospitalSnapshots.new(content,guard)
	if not snapshots.hospital_ids().is_empty():
		guard.call("release")
		push_error("Recovery verification requires an empty hospital directory")
		quit(2)
		return
	var library: HospitalLibrary = HospitalLibrary.new(content,snapshots)
	var id: String = HospitalSnapshots.uuid()
	var world: WorldState = FeasibilityHospitals.create(id,false,content)
	HospitalArrivalService.new(content,HospitalSpace.new(content)).ensure(world)
	var actor: Dictionary = world.facts.actors.sample_S21
	world.facts.actors.erase("sample_S21")
	actor.id = id+":sample"
	actor.name = id+":display-text"
	world.facts.actors[actor.id] = actor
	world.facts.wait_departures[actor.id] = {"ticket_id":"","next_check_wait_ticks":roundi(float(content.balance.wait_departure.first_check_seconds)/WorldState.TICK_SECONDS),"selected":true,"reason":"wait_departure"}
	var original: Dictionary = world.freeze()
	_check("fixture_valid",world.validate(content).is_empty())
	var created: Dictionary = library.create(world,"recovery-fixture")
	var receipt: Dictionary = snapshots.wait_for_idle() if created.ok else created
	_check("fixture_committed",receipt.ok)
	if not receipt.ok:
		guard.call("release")
		_finish()
		return
	var backup: String = "user://recovery.oghbackup"
	var exported: Dictionary = library.export_backup(id,receipt.snapshot_id,backup)
	_check("fixture_exported",exported.ok)
	var database_path: String = HospitalSnapshots.ROOT.path_join(id).path_join(HospitalSnapshots.DATABASE_NAME)
	var corrupt_bytes: PackedByteArray = "invalid hospital database".to_utf8_buffer()
	_check("corrupt_fixture_written",HospitalSnapshots._store(database_path,corrupt_bytes))
	guard.call("release")
	var scene: PackedScene = load(str(ProjectSettings.get_setting("application/run/main_scene"))) as PackedScene
	_app = scene.instantiate() as Control
	root.add_child(_app)
	await process_frame
	var panel: HospitalLibraryPanel = _app.get("_library_panel")
	_check("recovery_library_attached",_app.get("_simulation")==null and panel.visible and panel.library!=null and panel.current_hospital_id.is_empty())
	_app.call("_launch_library_job","import",{"path":backup})
	var deadline: int = Time.get_ticks_msec()+30000
	while _app.get("_library_thread")!=null and Time.get_ticks_msec()<deadline:
		await process_frame
	_check("import_polled_without_simulation",_app.get("_library_thread")==null and _app.get("_library_job").is_empty())
	var app_store: HospitalSnapshots = _app.get("_snapshots")
	var imported_id: String = ""
	for candidate_id: String in app_store.hospital_ids():
		if candidate_id!=id:
			imported_id = candidate_id
	_check("import_published",not imported_id.is_empty())
	if not imported_id.is_empty():
		var imported: Dictionary = app_store.recover_latest(imported_id)
		_check("import_world_valid",imported.ok and imported.world.validate(content).is_empty())
		if imported.ok:
			_check("departure_actor_reference_remapped",imported.world.facts.actors.has(imported_id+":sample") and imported.world.facts.wait_departures.has(imported_id+":sample") and not imported.world.facts.wait_departures.has(id+":sample"))
			_check("display_text_preserved",imported.world.facts.actors[imported_id+":sample"].name==actor.name)
	_check("source_world_unchanged",world.freeze()==original)
	_check("damaged_source_preserved",FileAccess.get_file_as_bytes(database_path)==corrupt_bytes)
	_app.call("_library_action","create",{"name":"恢复后新院","preset":true})
	deadline = Time.get_ticks_msec()+30000
	while not _app.get("_leave_operation").is_empty() and Time.get_ticks_msec()<deadline:
		await process_frame
	var simulation: HospitalSimulation = _app.get("_simulation")
	_check("new_hospital_activated",simulation!=null)
	if simulation!=null:
		_check("activated_world_valid",simulation.world.validate(content).is_empty())
		_check("activated_world_committed",app_store.recover_latest(simulation.world.hospital_id).ok)
	if _app.get("_library_thread")!=null:
		_app.get("_library").call("cancel_io")
		_app.get("_library_thread").wait_to_finish()
		_app.set("_library_thread",null)
	_app.get("_guard").call("release")
	root.remove_child(_app)
	_app.queue_free()
	await process_frame
	_finish()

func _check(label: String, condition: bool) -> void:
	print(label+"="+str(condition))
	if not condition:
		_failures.append(label)

func _finish() -> void:
	print("REVIEW_RECOVERY_PASS="+str(_failures.is_empty()))
	quit(0 if _failures.is_empty() else 1)
