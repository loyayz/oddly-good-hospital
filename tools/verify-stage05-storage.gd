extends SceneTree

class BudgetDenied:
	extends RefCounted
	func is_held() -> bool:
		return true
	func get_resource_status() -> Dictionary:
		return {"ok":true,"available_physical_bytes":0,"available_disk_bytes":0}

class FailedDatabase:
	extends RefCounted
	var native: RefCounted
	var stage: String
	func _init(database: RefCounted, fail_stage: String) -> void:
		native = database
		stage = fail_stage
	func execute(query: String,parameters: Array) -> Dictionary:
		if (stage=="world_chunk" and query.begins_with("INSERT INTO world_chunks")) or (stage=="manifest" and query.begins_with("UPDATE snapshots SET manifest")) or (stage=="before_commit" and query=="COMMIT"):
			return {"ok":false,"error":"test adapter: write refused"}
		var result: Dictionary = native.call("execute",query,parameters)
		if stage=="after_commit" and query=="COMMIT" and result.ok:
			return {"ok":false,"error":"test adapter: committed acknowledgement unavailable"}
		return result
	func close() -> Dictionary:
		return native.call("close")

class FailedSnapshots:
	extends HospitalSnapshots
	var failed_stage: String
	func _init(registry: HospitalContent,platform: RefCounted,stage: String) -> void:
		super(registry,platform)
		failed_stage = stage
	func _connect(hospital_id: String,create: bool = false) -> Dictionary:
		var result: Dictionary = super(hospital_id,create)
		if result.ok:
			result.database = FailedDatabase.new(result.database,failed_stage)
		return result

var _checks: Dictionary = {}
var _guard: RefCounted

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not "Stage05 验收" in OS.get_user_data_dir():
		push_error("Storage verification requires an isolated Stage05 验收 profile")
		quit(2)
		return
	_guard = ClassDB.instantiate("PlatformSessionGuard") as RefCounted
	_check("exclusive_guard",_guard.call("acquire").ok)
	var content: HospitalContent = HospitalContent.new()
	var storage: HospitalSnapshots = HospitalSnapshots.new(content,_guard)
	var world: WorldState = FeasibilityHospitals.create(HospitalSnapshots.uuid(),false,content)
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	var command: GameCommand = GameCommand.new("storage-command",world.hospital_id,world.revision,"move_actor",MoveActorPayload.new("sample_S21",1,Vector2i(35,66),world.facts.actors.sample_S21.location),"storage-session")
	simulation.enqueue(command.to_record())
	var tick: int = world.sim_tick
	var begin: Dictionary = storage.begin(simulation,"storage-session")
	_check("drains_accepted_commands_before_copy",begin.ok and world.facts.command_receipts.has(command.id) and world.sim_tick==tick)
	var frozen_revision: int = world.revision
	var frozen_world: Dictionary = world.freeze()
	world.touch()
	_check("serial_writer_rejects_overlap",not storage.begin(simulation,"storage-session","auto","0").ok and storage.take_pending_auto() and not storage.take_pending_auto())
	var receipt: Dictionary = storage.wait_for_idle()
	_check("receipt_confirms_frozen_revision",receipt.ok and receipt.world_revision==frozen_revision and receipt.world_revision<world.revision and not storage.busy())
	var loaded: Dictionary = storage.load_commit(world.hospital_id,receipt.snapshot_id)
	_check("same_tick_roundtrip",loaded.ok and loaded.world.facts==frozen_world and loaded.manifest.world_revision==frozen_revision)
	_check("content_identity_frozen",loaded.ok and loaded.manifest.content_packs==begin.request.content_packs and HospitalSnapshots._valid_sha(loaded.manifest.content_packs[0].fingerprint))
	var baseline_id: String = receipt.snapshot_id
	# These adapters verify transactional error paths. Actual process interruption,
	# OS sharing/byte locks and restart recovery use verify-stage01-storage.ps1.
	for phase: String in ["world_chunk","manifest","before_commit","after_commit"]:
		var failed_storage: FailedSnapshots = FailedSnapshots.new(content,_guard,phase)
		var started: Dictionary = failed_storage.begin(simulation,"storage-session","checkpoint",phase)
		var failed: Dictionary = failed_storage.wait_for_idle() if started.ok else started
		var recovered: Dictionary = storage.recover_latest(world.hospital_id)
		_check("write_error_"+phase,started.ok and recovered.ok and storage.load_commit(world.hospital_id,baseline_id).ok and not failed.ok)
		_check("guard_retained_"+phase,_guard.call("is_held"))
	var denied: HospitalSnapshots = HospitalSnapshots.new(content,BudgetDenied.new())
	var before: Dictionary = world.freeze()
	_check("resource_failure_keeps_world",not denied.begin(simulation,"storage-session").ok and world.facts==before and not denied.busy())
	storage.begin(simulation,"storage-session","manual","2")
	var latest: Dictionary = storage.wait_for_idle()
	var opened: Dictionary = storage._connect(world.hospital_id)
	var corrupt: Dictionary = opened.database.call("execute","UPDATE world_chunks SET data=? WHERE snapshot_id=? AND chunk_index=0",["broken".to_utf8_buffer(),latest.snapshot_id])
	opened.database.call("close")
	_check("corrupt_candidate_not_partially_loaded",corrupt.ok and not storage.load_commit(world.hospital_id,latest.snapshot_id).ok and world.facts==before)
	var recovered: Dictionary = storage.recover_latest(world.hospital_id)
	_check("recover_skips_corrupt_newest",recovered.ok and not recovered.rejected_candidates.is_empty() and recovered.manifest.snapshot_id!=latest.snapshot_id)
	var bad: Dictionary = world.freeze()
	bad.visits.values()[0].actor_id = "missing-actor"
	var bad_request: Dictionary = {"hospital_id":world.hospital_id,"loading_session_id":"storage-session","request_id":HospitalSnapshots.uuid(),"snapshot_id":HospitalSnapshots.uuid(),"world_revision":world.revision,"sim_tick":world.sim_tick,"slot_kind":"manual","slot_key":"3"}
	_check("bad_reference_rolls_back_transaction",not storage._write(bad,bad_request).ok and storage.load_commit(world.hospital_id,baseline_id).ok)
	var codec: HospitalJsonStream = HospitalJsonStream.new()
	var sink: Callable = func(_chunk: PackedByteArray) -> Dictionary: return {"ok":true}
	_check("codec_rejects_platform_values",not codec.encode_to({"object":RefCounted.new()},func(_size: int) -> bool: return true,sink))
	_check("codec_reusable_after_failure",codec.encode_to({"int":9223372036854775807,"float":1.23456789012345},func(_size: int) -> bool: return true,sink))
	_check("no_unfinished_io_before_release",not storage.busy() and _guard.call("is_held"))
	_guard.call("release")
	var ok: bool = not _checks.values().has(false)
	print(JSON.stringify({"stage":5,"ok":ok,"checks":_checks,"performance":"skipped"},"",true))
	quit(0 if ok else 1)

func _check(name: String,condition: bool) -> void:
	_checks[name] = condition
	if not condition:
		push_error(name)
