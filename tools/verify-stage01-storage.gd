extends SceneTree

var _guard: RefCounted
var _arguments: Dictionary = {}

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.trim_prefix("--").split("=",true,1)
		if pair.size()==2:
			_arguments[pair[0]] = pair[1]
	call_deferred("_run")

func _run() -> void:
	if not "Stage01 验收" in OS.get_user_data_dir():
		quit(2)
		return
	_guard = ClassDB.instantiate("PlatformSessionGuard") as RefCounted
	var acquisition: Dictionary = _guard.call("acquire")
	if _arguments.get("mode","")=="busy":
		var result: Dictionary = {"acquisition":acquisition,"actual_user_directory":OS.get_user_data_dir(),"ok":not acquisition.get("ok",true) and acquisition.get("busy",false) and int(acquisition.get("error",0))==32}
		_store(str(_arguments["control-dir"]).path_join("contention.json"),result)
		quit(0 if result.ok else 1)
		return
	if not acquisition.get("ok",false):
		quit(3)
		return
	var content: HospitalContent = HospitalContent.new()
	var storage: HospitalSnapshots = HospitalSnapshots.new(content,_guard)
	var control: String = _arguments["control-dir"]
	if _arguments.get("mode","")=="recover":
		var ready: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(control.path_join("ready.json")))
		var records: Array[Dictionary] = storage.list_commits(ready.hospital_id)
		var loaded: Dictionary = storage.load_commit(ready.hospital_id,ready.previous_snapshot_id)
		var expected_count: int = 2 if ready.stage=="after_commit" else 1
		var latest: Dictionary = storage.load_commit(records[0].hospital_id,records[0].snapshot_id) if not records.is_empty() else {"ok":false}
		var report: Dictionary = {"stage":ready.stage,"actual_user_directory":OS.get_user_data_dir(),"guard_after_crash":_guard.call("is_held"),
			"valid_commit_count":records.size(),"previous_world_unchanged":loaded.ok and JSON.stringify(loaded.world.facts,"",true,true).sha256_text()==ready.previous_world_sha256,
			"database_unchanged_after_rollback":ready.stage=="after_commit" or FileAccess.get_sha256(ready.database_path)==ready.previous_database_sha256,
			"only_complete_transactions_published":records.size()==expected_count and latest.ok and int(latest.world.facts.sim_tick)==int(ready.previous_tick)+(1 if ready.stage=="after_commit" else 0)}
		report.ok = report.guard_after_crash and report.previous_world_unchanged and report.database_unchanged_after_rollback and report.only_complete_transactions_published
		_store(control.path_join("recovery.json"),report)
		_guard.call("release")
		quit(0 if report.ok else 1)
		return
	var world: HospitalWorld = FeasibilityHospitals.create(HospitalSnapshots.uuid(),true,content)
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	for tick: int in 1500:
		simulation.step()
	var started: Dictionary = storage.begin(world,"storage-baseline","manual","1")
	if not started.ok:
		_store(control.path_join("failed.json"),started)
		quit(4)
		return
	var receipt: Dictionary = {}
	while receipt.is_empty():
		await process_frame
		receipt = storage.poll()
	if not receipt.ok:
		_store(control.path_join("failed.json"),receipt)
		quit(5)
		return
	var snapshot_id: String = HospitalSnapshots.uuid()
	var database_path: String = OS.get_user_data_dir().path_join("hospitals").path_join(world.facts.hospital_id).path_join(HospitalSnapshots.DATABASE_NAME)
	var ready: Dictionary = {"stage":_arguments.stage,"hospital_id":world.facts.hospital_id,"snapshot_id":snapshot_id,
		"database_path":database_path,"previous_snapshot_id":receipt.snapshot_id,"previous_tick":world.facts.sim_tick,
		"previous_world_sha256":JSON.stringify(world.facts,"",true,true).sha256_text(),
		"previous_database_sha256":FileAccess.get_sha256(database_path),"actual_user_directory":OS.get_user_data_dir()}
	_store(control.path_join("ready.json"),ready)
	while not FileAccess.file_exists(control.path_join("GO")):
		await process_frame
	simulation.step()
	var request: Dictionary = {"hospital_id":world.facts.hospital_id,"loading_session_id":"fault-boundary","request_id":HospitalSnapshots.uuid(),
		"snapshot_id":snapshot_id,"world_revision":world.facts.world_revision,"sim_tick":world.facts.sim_tick,"slot_kind":"manual","slot_key":"1"}
	# The controller applies actual Win32 sharing/byte locks or terminates a live SQLite transaction.
	var thread: Thread = Thread.new()
	thread.start(storage._write.bind(world.freeze(),request))
	while thread.is_alive():
		await process_frame
	var failure: Dictionary = thread.wait_to_finish()
	_store(control.path_join("writer.json"),failure)
	while true:
		await process_frame # The controller terminates this process while it still owns the library guard.

func _store(path: String, value: Dictionary) -> void:
	var temporary: String = path+".tmp"
	var file: FileAccess = FileAccess.open(temporary,FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t",true,true))
	file.flush()
	file.close()
	DirAccess.rename_absolute(temporary,path)
