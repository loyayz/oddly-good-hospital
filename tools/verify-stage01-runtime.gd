extends SceneTree

var _failures: Array[String] = []
var _evidence: Dictionary = {"engine":Engine.get_version_info(),"renderer":"headless — simulation/storage only",
	"checks":{},"clinical_traces":{},"artifacts":{}}
var _guard: RefCounted

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var actual_user: String = OS.get_user_data_dir()
	if not "Stage01 验收" in actual_user:
		push_error("Use the isolated feasibility project; product user:// must not be used by this probe.")
		quit(2)
		return
	_guard = ClassDB.instantiate("PlatformSessionGuard") as RefCounted
	var acquired: Dictionary = _guard.call("acquire")
	_check("isolated_guard",acquired.get("ok",false))
	_evidence.actual_user_directory = actual_user
	var content: HospitalContent = HospitalContent.new()
	_check("registered_content",content.error.is_empty())
	var clinic: WorldState = FeasibilityHospitals.create(HospitalSnapshots.uuid(),false,content)
	var surgery: WorldState = FeasibilityHospitals.create(HospitalSnapshots.uuid(),true,content)
	_check("initial_outpatient_invariants",clinic.validate(content).is_empty())
	_check("initial_surgery_invariants",surgery.validate(content).is_empty())
	_run_clinical(clinic,content,6000,"outpatient")
	_run_clinical(surgery,content,12000,"surgery")
	_numerical_cases(content)
	_evidence.clinical_final = {"outpatient":clinic.freeze(),"surgery":surgery.freeze()}
	var first: HospitalSimulation = HospitalSimulation.new(FeasibilityHospitals.create("deterministic",false,content),content)
	var second: HospitalSimulation = HospitalSimulation.new(FeasibilityHospitals.create("deterministic",false,content),content)
	for index: int in 1500:
		first.step()
	for frame: int in 500:
		for index: int in 3:
			second.step()
	_check("same_tick_same_facts_and_rng",JSON.stringify(first.world.facts,"",true,true)==JSON.stringify(second.world.facts,"",true,true))
	var before_preview: String = JSON.stringify(first.world.facts,"",true,true)
	var geometry: HospitalSpace = first.space
	for index: int in 10:
		geometry.route(first.world,"sample_S59",2,[35,80])
	_check("readonly_route_preview",before_preview==JSON.stringify(first.world.facts,"",true,true))
	var command: Dictionary = {"id":"duplicate_move","hospital_id":"deterministic","kind":"move_actor","actor_id":"sample_S21","floor_id":1,"cell":[35,66]}
	first.enqueue(command)
	first.drain_commands()
	var after_command: String = JSON.stringify(first.world.facts,"",true,true)
	first.enqueue(command)
	first.drain_commands()
	_check("duplicate_command_no_effect",after_command==JSON.stringify(first.world.facts,"",true,true))
	_check("three_cell_giant",geometry.clearance(first.world.facts.actors.sample_S59)==3)
	_check("micro_one_actor",first.world.facts.actors.has("sample_S21"))
	_check("ghost_collision_is_real",geometry.clearance(first.world.facts.actors.sample_S14)==1)
	_check("compressed_ten_thousand_floors",first.world.facts.floors.height_intervals.size()==1 and first.world.facts.floors.overrides.size()==2)
	_check("vertical_giant_route",geometry.route(first.world,"sample_S59",2,[35,83]).ok)
	var storage: HospitalSnapshots = HospitalSnapshots.new(content,_guard)
	await _sqlite_cases(content,storage)
	await _space_cases(content,storage)
	await _saved_floor_cases(content,storage)
	var started: Dictionary = storage.begin(surgery,"probe-surgery","manual","1")
	_check("begin_surgery_save",started.ok)
	var receipt: Dictionary = await _await_save(storage)
	_check("surgery_save_committed",receipt.get("ok",false))
	if receipt.get("ok",false):
		var restored: Dictionary = storage.load_commit(surgery.facts.hospital_id,receipt.snapshot_id)
		_check("restore_exact_world",restored.ok and JSON.stringify(restored.world.facts,"",true,true)==JSON.stringify(surgery.facts,"",true,true))
		_evidence.artifacts.surgery_receipt = receipt
	var frozen: WorldState = FeasibilityHospitals.create(HospitalSnapshots.uuid(),true,content)
	var progress: HospitalSimulation = HospitalSimulation.new(frozen,content)
	var checkpoints: Dictionary = {}
	for index: int in 6000:
		progress.step()
		var visit: Dictionary = frozen.facts.visits.values()[0]
		if visit.phase in ["gp","surgery","wake","transfer","recovery","round"] and not checkpoints.has(visit.phase):
			checkpoints[visit.phase] = frozen.freeze()
	for phase: String in checkpoints:
		var midway: WorldState = WorldState.new(checkpoints[phase])
		var request: Dictionary = storage.begin(midway,"probe-midway","manual",phase)
		_check("save_started_"+phase,request.ok)
		var saved: Dictionary = await _await_save(storage)
		_check("save_committed_"+phase,saved.get("ok",false))
		if not saved.get("ok",false):
			continue
		var restored: Dictionary = storage.load_commit(midway.facts.hospital_id,saved.snapshot_id)
		_check("restore_midway_"+phase,restored.ok and JSON.stringify(midway.facts,"",true,true)==JSON.stringify(restored.world.facts,"",true,true))
		if restored.ok:
			var resumed: HospitalSimulation = HospitalSimulation.new(restored.world,content)
			var original: HospitalSimulation = HospitalSimulation.new(midway,content)
			for tick: int in 200:
				original.step()
				resumed.step()
			_check("resume_same_tick_"+phase,JSON.stringify(midway.facts,"",true,true)==JSON.stringify(restored.world.facts,"",true,true))
			if JSON.stringify(midway.facts,"",true,true)!=JSON.stringify(restored.world.facts,"",true,true):
				_evidence["resume_difference_"+phase] = _differences(midway.facts,restored.world.facts,"",[])
	_evidence.midway_phases = checkpoints.keys()
	_evidence.checks_pass = _failures.is_empty()
	_evidence.failures = _failures
	_evidence.observed_at_utc = Time.get_datetime_string_from_system(true)
	var output: FileAccess = FileAccess.open("res://runtime-evidence.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(_evidence,"\t",true,true))
	output.close()
	_guard.call("release")
	print("STAGE01_RUNTIME_PASS="+str(_failures.is_empty())+"; CHECKS="+str(_evidence.checks.size()))
	quit(0 if _failures.is_empty() else 1)

func _await_save(storage: HospitalSnapshots) -> Dictionary:
	while storage.busy():
		await process_frame
		var receipt: Dictionary = storage.poll()
		if not receipt.is_empty():
			return receipt
	return {"ok":false,"error":"missing receipt"}

func _run_clinical(world: WorldState, content: HospitalContent, ticks: int, kind: String) -> void:
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	var trace: Array[Dictionary] = []
	var previous: String = ""
	for index: int in ticks:
		simulation.step()
		var visit: Dictionary = world.facts.visits.values()[0]
		if visit.phase != previous:
			trace.append({"tick":world.facts.sim_tick,"phase":visit.phase,"money":HospitalLedger.balance(world),"packages":world.facts.inventory.units})
			print(kind+" tick="+str(world.facts.sim_tick)+" phase="+str(visit.phase))
			previous = visit.phase
	_evidence.clinical_traces[kind] = trace
	var visit: Dictionary = world.facts.visits.values()[0]
	_check(kind+"_departed",visit.phase=="departed")
	_check(kind+"_actual_cure",visit.final_result=="cured")
	_check(kind+"_maximum_attempts",visit.attempt_ids.size()<=2)
	_check(kind+"_post_clinical_invariants",world.validate(content).is_empty())
	if kind == "surgery":
		_check("ward_release_after_departure",world.facts.ward_stays.is_empty())
		_check("ward_real_care_and_round",world.facts.staff.ward_nurse.practice.care>0 and world.facts.staff.round_doctor.practice.treatment>0)
	var supplies: int = 0
	var failures: int = 0
	for attempt: Dictionary in world.facts.attempts.values():
		supplies += int(attempt.supply_units)
		failures += 0 if attempt.result else 1
	var initial_anger: float = float(content.definition("patient_personalities",visit.personality_id).initial_anger)
	_check(kind+"_failure_anger",is_equal_approx(float(visit.anger),minf(100.0,initial_anger+15.0*failures)))
	_check(kind+"_inventory_issued_once",60-int(world.facts.inventory.units)==supplies and world.facts.inventory.issues.size()==world.facts.attempts.size())
	var cure_entries: int = 0
	var cure_amount: int = 0
	for entry: Dictionary in world.facts.ledger.entries.values():
		if entry.component=="cure":
			cure_entries += 1
			cure_amount += int(entry.amount)
	_check(kind+"_single_success_charge",cure_entries==1 and cure_amount==ceili(float(content.definition("diseases",visit.disease_id).cure_fee)*(1.8 if kind=="surgery" else 1.0)))
	_evidence[kind+"_settlement"] = {"money":HospitalLedger.balance(world),"packages":world.facts.inventory.units,"attempt_count":world.facts.attempts.size(),"cure_charge":cure_amount,"anger":visit.anger,"failed_attempts":failures,"ledger":world.facts.ledger.entries}

func _numerical_cases(content: HospitalContent) -> void:
	_failure_anger_cases(content)
	for case: String in ["stock","qualification","bed","research"]:
		var world: WorldState = FeasibilityHospitals.create(HospitalSnapshots.uuid(),true,content)
		match case:
			"stock": world.facts.inventory.units = 9
			"qualification": world.facts.staff.or_nurse.certificates.erase("q_or")
			"bed": world.facts.facilities.bed.failed = true
			"research": world.facts.research.erase(str(content.definition("treatment_plans","P_D23_SURGERY").requires_research[0]))
		var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
		for tick: int in 1700:
			simulation.step()
		var visit: Dictionary = world.facts.visits.values()[0]
		_check("no_unready_attempt_"+case,world.facts.attempts.is_empty() and world.facts.inventory.issues.is_empty() and not visit.ticket_id.is_empty())
		_evidence["unready_"+case] = visit.waiting_reason
	var paused: WorldState = FeasibilityHospitals.create(HospitalSnapshots.uuid(),false,content)
	var simulation: HospitalSimulation = HospitalSimulation.new(paused,content)
	for tick: int in 1700:
		simulation.step()
		if not paused.facts.attempts.is_empty():
			break
	var attempt: Dictionary = paused.facts.attempts.values()[0]
	var before: String = JSON.stringify(attempt,"",true,true)
	var supply_before: int = int(paused.facts.inventory.units)
	var rng_before: String = paused.facts.rng.treatment.state_decimal
	var session: Dictionary = paused.facts.sessions.values()[0]
	var remaining: int = int(session.remaining_ticks)
	paused.facts.facilities.treatment.failed = true
	paused.facts.staff.treat_doctor.abilities.treatment = 5
	for tick: int in 10:
		simulation.step()
	_check("equipment_failure_preserves_frozen_attempt",before==JSON.stringify(attempt,"",true,true) and int(session.remaining_ticks)==remaining and int(paused.facts.inventory.units)==supply_before and paused.facts.rng.treatment.state_decimal==rng_before)
	paused.facts.facilities.treatment.failed = false
	for tick: int in 1700:
		simulation.step()
	_check("equipment_recovery_continues_original_attempt",paused.facts.visits.values()[0].phase=="departed" and paused.facts.attempts.size()==1 and paused.facts.inventory.issues.size()==1)
	var prepare: WorldState = FeasibilityHospitals.create(HospitalSnapshots.uuid(),true,content)
	var prepare_sim: HospitalSimulation = HospitalSimulation.new(prepare,content)
	for tick: int in 1700:
		prepare_sim.step()
		if not prepare.facts.preparations.is_empty():
			break
	var ticket: String = prepare.facts.visits.values()[0].ticket_id
	prepare.facts.facilities.bed.failed = true
	prepare_sim.step()
	_check("invalidated_preparation_releases_resources_keeps_ticket",prepare.facts.preparations.is_empty() and prepare.facts.attempts.is_empty() and prepare.facts.visits.values()[0].ticket_id==ticket)
	for case: String in ["rng_overflow","room_extent","dangling_visit","missing_species","position_conflict","missing_door","dangling_ledger","missing_floor_overrides","wrong_floor_overrides","wrong_floor_layout"]:
		var invalid: WorldState = FeasibilityHospitals.create(HospitalSnapshots.uuid(),true,content)
		match case:
			"rng_overflow": invalid.facts.rng.treatment.state_decimal = "9223372036854775808"
			"room_extent": invalid.facts.rooms.ward.size = [-1,8]
			"dangling_visit": invalid.facts.visits.values()[0].actor_id = "missing"
			"missing_species": invalid.facts.actors.patient.species_id = "missing"
			"position_conflict": invalid.facts.actors.patient.location.connector_id = "lift"
			"missing_door": invalid.facts.floors.overrides["1"].doors[0].definition_id = "missing"
			"dangling_ledger": invalid.facts.ledger.entries["missing:test"] = {"owner_id":"missing","component":"test","amount":1,"tick":0,"settled":true}
			"missing_floor_overrides": invalid.facts.floors.erase("overrides")
			"wrong_floor_overrides": invalid.facts.floors.overrides = []
			"wrong_floor_layout": invalid.facts.floors.overrides["1"] = []
		_check("invalid_dto_rejected_"+case,not invalid.validate(content).is_empty())

func _failure_anger_cases(content: HospitalContent) -> void:
	var selected_seed: int = -1
	for seed_value: int in 65536:
		var generator: RandomNumberGenerator = RandomNumberGenerator.new()
		generator.seed = seed_value
		if generator.randi_range(0,9999)>=9800 and generator.randi_range(0,9999)>=9800:
			selected_seed = seed_value
			break
	_check("two_failure_seed_available",selected_seed>=0)
	if selected_seed<0:
		return
	_evidence.failure_anger_cases = []
	for initial_anger: float in [5.0,95.0]:
		var world: WorldState = FeasibilityHospitals.create(HospitalSnapshots.uuid(),false,content)
		var generator: RandomNumberGenerator = RandomNumberGenerator.new()
		generator.seed = selected_seed
		world.facts.rng.treatment.seed_decimal = str(generator.seed)
		world.facts.rng.treatment.state_decimal = str(generator.state)
		var visit: Dictionary = world.facts.visits.values()[0]
		visit.anger = initial_anger
		var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
		var duplicate_readonly: bool = true
		var completed_count: int = 0
		for tick: int in 3000:
			var completion: Dictionary = {}
			for session: Dictionary in world.facts.sessions.values():
				if session.kind=="outpatient" and int(session.remaining_ticks)==1:
					completion = session.duplicate(true)
			simulation.step()
			if not completion.is_empty():
				completed_count += 1
				var before: String = JSON.stringify(world.facts,"",true,true)
				simulation.clinic._complete_service(world,completion)
				duplicate_readonly = duplicate_readonly and before==JSON.stringify(world.facts,"",true,true)
			if visit.phase=="departed":
				break
		var key: String = "failure_anger_"+str(int(initial_anger))
		var two_failures: bool = world.facts.attempts.size()==2
		for attempt: Dictionary in world.facts.attempts.values():
			two_failures = two_failures and not attempt.result
		_check(key+"_real_two_failures",two_failures and visit.final_result=="referred" and visit.phase=="departed")
		_check(key+"_applied_and_capped",is_equal_approx(float(visit.anger),minf(100.0,initial_anger+30.0)))
		_check(key+"_duplicate_completion_readonly",duplicate_readonly and completed_count==2)
		_evidence.failure_anger_cases.append({"seed":selected_seed,"initial_anger":initial_anger,"final_anger":visit.anger,"phase":visit.phase,"attempts":world.facts.attempts.size(),"duplicate_completion_readonly":duplicate_readonly})

func _saved_floor_cases(content: HospitalContent, storage: HospitalSnapshots) -> void:
	var world: WorldState = FeasibilityHospitals.create(HospitalSnapshots.uuid(),true,content)
	var started: Dictionary = storage.begin(world,"invalid-floor","manual","floor-structure")
	_check("floor_rejection_baseline_save_started",started.ok)
	if not started.ok:
		return
	var receipt: Dictionary = await _await_save(storage)
	_check("floor_rejection_baseline_save_committed",receipt.get("ok",false))
	if not receipt.get("ok",false):
		return
	var path: String = HospitalSnapshots.ROOT.path_join(world.facts.hospital_id).path_join(HospitalSnapshots.DATABASE_NAME)
	var original_database: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var opened: Dictionary = storage._connect(world.facts.hospital_id)
	var stored_metadata: Dictionary = opened.database.call("execute","SELECT manifest FROM snapshots WHERE snapshot_id=?",[receipt.snapshot_id])
	var original_manifest: PackedByteArray = stored_metadata.rows[0].manifest
	opened.database.call("close")
	for case: String in ["missing_overrides","wrong_overrides","wrong_layout"]:
		var malformed: Dictionary = world.freeze()
		match case:
			"missing_overrides": malformed.floors.erase("overrides")
			"wrong_overrides": malformed.floors.overrides = []
			"wrong_layout": malformed.floors.overrides["1"] = []
		var bytes: PackedByteArray = JSON.stringify(malformed,"",true,true).to_utf8_buffer()
		var manifest: Dictionary = JSON.parse_string(original_manifest.get_string_from_utf8())
		manifest.world_bytes = bytes.size()
		manifest.world_sha256 = HospitalSnapshots._sha(bytes)
		var metadata: PackedByteArray = JSON.stringify(manifest,"",true,true).to_utf8_buffer()
		opened = storage._connect(world.facts.hospital_id)
		var database: RefCounted = opened.database
		var written: bool = database.call("execute","BEGIN IMMEDIATE",[]).ok and database.call("execute","DELETE FROM world_chunks WHERE snapshot_id=?",[receipt.snapshot_id]).ok
		for index: int in ceili(float(bytes.size())/HospitalJsonStream.CHUNK):
			written = written and database.call("execute","INSERT INTO world_chunks VALUES(?,?,?)",[receipt.snapshot_id,index,bytes.slice(index*HospitalJsonStream.CHUNK,(index+1)*HospitalJsonStream.CHUNK)]).ok
		written = written and database.call("execute","UPDATE snapshots SET manifest=?,manifest_sha256=? WHERE snapshot_id=?",[metadata,HospitalSnapshots._sha(metadata),receipt.snapshot_id]).ok
		written = written and database.call("execute","COMMIT",[]).ok
		database.call("close")
		var loaded: Dictionary = storage.load_commit(world.facts.hospital_id,receipt.snapshot_id)
		_check("invalid_saved_floor_rejected_"+case,written and not loaded.ok and "楼层" in str(loaded.get("error","")))
	HospitalSnapshots._store(path,original_database)
	_check("floor_rejection_baseline_restored",storage.load_commit(world.facts.hospital_id,receipt.snapshot_id).ok)

func _sqlite_cases(content: HospitalContent, storage: HospitalSnapshots) -> void:
	var world: WorldState = FeasibilityHospitals.create(HospitalSnapshots.uuid(),false,content)
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	for tick: int in 137:
		simulation.step()
	for index: int in 1280:
		simulation.enqueue({"id":"sqlite-history:%04d" % index,"hospital_id":world.facts.hospital_id,"kind":"move_actor","actor_id":"sample_S21","floor_id":1,"cell":[35,66]})
	simulation.drain_commands()
	var started_us: int = Time.get_ticks_usec()
	var started: Dictionary = storage.begin(world,"sqlite-contract","manual","sqlite")
	var freeze_us: int = Time.get_ticks_usec()-started_us
	_check("sqlite_save_started",started.ok)
	if not started.ok:
		return
	var receipt: Dictionary = await _await_save(storage)
	var save_us: int = Time.get_ticks_usec()-started_us
	_check("sqlite_save_committed",receipt.get("ok",false))
	if not receipt.get("ok",false):
		return
	var path: String = HospitalSnapshots.ROOT.path_join(world.facts.hospital_id).path_join(HospitalSnapshots.DATABASE_NAME)
	var file: FileAccess = FileAccess.open(path,FileAccess.READ)
	_check("sqlite_real_file_header",file.get_buffer(16).hex_encode()=="53514c69746520666f726d6174203300")
	var database_bytes: int = file.get_length()
	file.close()
	_check("sqlite_no_new_json_commit_directory",not DirAccess.dir_exists_absolute(HospitalSnapshots.ROOT.path_join(world.facts.hospital_id).path_join("commits")))
	var opened: Dictionary = storage._connect(world.facts.hospital_id)
	var database: RefCounted = opened.database
	var policies: Dictionary = {}
	for pragma: String in ["journal_mode","synchronous","foreign_keys","cache_size","integrity_check"]:
		var result: Dictionary = database.call("execute","PRAGMA "+pragma,[])
		policies[pragma] = result.rows[0].values()[0] if result.ok else "error"
	_check("sqlite_transaction_policy",policies.journal_mode=="delete" and policies.synchronous==3 and policies.foreign_keys==1 and policies.cache_size==-4096)
	_check("sqlite_integrity_check",policies.integrity_check=="ok")
	var numbers: Dictionary = database.call("execute","SELECT ? AS integer_value,? AS decimal_value,? AS text_value,? AS blob_value",[9223372036854775806,99.52000000000027,"医院 数据",PackedByteArray([0,255,128,1])])
	_check("sqlite_bound_values_preserve_precision",numbers.ok and numbers.rows[0].integer_value==9223372036854775806 and numbers.rows[0].decimal_value==99.52000000000027 and numbers.rows[0].text_value=="医院 数据" and numbers.rows[0].blob_value==PackedByteArray([0,255,128,1]))
	var chunks: Dictionary = database.call("execute","SELECT count(*) AS count,max(length(data)) AS largest,sum(length(data)) AS bytes FROM world_chunks WHERE snapshot_id=?",[receipt.snapshot_id])
	var records: Array[Dictionary] = storage.list_commits(world.facts.hospital_id)
	_check("sqlite_bounded_complete_chunks",chunks.ok and int(chunks.rows[0].largest)<=32768 and int(chunks.rows[0].bytes)==int(records[0].world_bytes))
	var restored: Dictionary = storage.load_commit(world.facts.hospital_id,receipt.snapshot_id)
	_check("sqlite_multiple_chunks_restore_exact_world",chunks.rows[0].count>1 and restored.ok and JSON.stringify(restored.world.facts,"",true,true)==JSON.stringify(world.facts,"",true,true))
	_evidence.sqlite_storage = {"version":opened.version,"database_bytes":database_bytes,"world_bytes":records[0].world_bytes,"chunk_count":chunks.rows[0].count,"command_receipt_count":world.facts.command_receipts.size(),"freeze_and_start_usec":freeze_us,"save_total_usec":save_us,"policies":policies}
	database.call("execute","PRAGMA user_version=2",[])
	database.call("close")
	var unsupported_hash: String = FileAccess.get_sha256(path)
	_check("sqlite_unknown_version_rejected_without_rewrite",not storage.load_commit(world.facts.hospital_id,receipt.snapshot_id).ok and FileAccess.get_sha256(path)==unsupported_hash)
	opened = storage._connect(world.facts.hospital_id)
	opened.database.call("execute","PRAGMA user_version=1",[])
	opened.database.call("close")
	var legacy_id: String = HospitalSnapshots.uuid()
	var snapshot_id: String = HospitalSnapshots.uuid()
	var legacy_world: WorldState = FeasibilityHospitals.create(legacy_id,true,content)
	var legacy_simulation: HospitalSimulation = HospitalSimulation.new(legacy_world,content)
	for tick: int in 137:
		legacy_simulation.step()
	var legacy_path: String = HospitalSnapshots.ROOT.path_join(legacy_id).path_join("commits").path_join(snapshot_id)
	DirAccess.make_dir_recursive_absolute(legacy_path)
	var encoder: HospitalJsonStream = HospitalJsonStream.new()
	var encoded: bool = encoder.encode(legacy_path.path_join("world.json"),legacy_world.freeze(),storage._budget)
	var manifest: Dictionary = {"format":HospitalSnapshots.FORMAT,"schema_version":1,"game_version":"0.1.0-stage01","hospital_id":legacy_id,"snapshot_id":snapshot_id,"sequence":7,"slot_kind":"manual","slot_key":"1","created_utc":"2026-10-14T00:00:00","sim_tick":137,"content_packs":[{"id":"core","version":str(content.catalog.content_version)}],"world_bytes":encoder.bytes,"world_sha256":encoder.digest,"display_summary":{"display_name":legacy_world.facts.display_name,"mode":legacy_world.facts.mode,"present_actor_count":legacy_world.present_actor_count()}}
	var raw: PackedByteArray = JSON.stringify(manifest,"",true).to_utf8_buffer()
	HospitalSnapshots._store(legacy_path.path_join("manifest.json"),raw)
	HospitalSnapshots._store(legacy_path.path_join("COMMITTED"),HospitalSnapshots._sha(raw).to_utf8_buffer())
	var partial: String = legacy_path.get_base_dir().path_join(".pending-"+HospitalSnapshots.uuid())
	DirAccess.make_dir_recursive_absolute(partial)
	HospitalSnapshots._store(partial.path_join("world.json"),"{".to_utf8_buffer())
	var original_hashes: Dictionary = {}
	for name: String in ["world.json","manifest.json","COMMITTED"]:
		original_hashes[name] = FileAccess.get_sha256(legacy_path.path_join(name))
	var imported: Array[Dictionary] = storage.list_commits(legacy_id)
	var loaded: Dictionary = storage.load_commit(legacy_id,snapshot_id)
	_check("sqlite_import_preserves_legacy_identity_sequence_and_facts",encoded and imported.size()==1 and imported[0].sequence==7 and imported[0].snapshot_id==snapshot_id and loaded.ok and JSON.stringify(loaded.world.facts,"",true,true)==JSON.stringify(legacy_world.facts,"",true,true))
	var originals_kept: bool = FileAccess.get_file_as_string(partial.path_join("world.json"))=="{"
	for name: String in original_hashes:
		originals_kept = originals_kept and FileAccess.get_sha256(legacy_path.path_join(name))==original_hashes[name]
	_check("sqlite_import_keeps_sources_and_ignores_pending",originals_kept)
	legacy_simulation.step()
	started = storage.begin(legacy_world,"sqlite-import-continue","manual","1")
	_check("sqlite_import_continued_save_started",started.ok)
	if started.ok:
		receipt = await _await_save(storage)
		_check("sqlite_import_continues_sequence_without_reimport",receipt.get("ok",false) and receipt.sequence==8 and storage.list_commits(legacy_id).size()==2 and FileAccess.get_sha256(legacy_path.path_join("world.json"))==original_hashes["world.json"])
	_evidence.sqlite_storage.legacy_import = {"hospital_id":legacy_id,"snapshot_id":snapshot_id,"imported_sequence":7,"source_hashes":original_hashes,"source_preserved":originals_kept}
	var history_world: WorldState = FeasibilityHospitals.create(HospitalSnapshots.uuid(),false,content)
	var history_written: bool = true
	for index: int in 6:
		started = storage.begin(history_world,"sqlite-history-retention","manual","1")
		if not started.ok:
			history_written = false
			break
		receipt = await _await_save(storage)
		if not receipt.get("ok",false):
			history_written = false
			break
	var retained: Array[Dictionary] = storage.list_commits(history_world.facts.hospital_id)
	opened = storage._connect(history_world.facts.hospital_id)
	var orphaned: Dictionary = opened.database.call("execute","SELECT count(*) AS count FROM world_chunks LEFT JOIN snapshots USING(snapshot_id) WHERE snapshots.snapshot_id IS NULL",[])
	var references: Dictionary = opened.database.call("execute","PRAGMA foreign_key_check",[])
	opened.database.call("close")
	_check("sqlite_history_retention_cascades_without_orphans",history_written and retained.size()==3 and retained[0].sequence==6 and retained[2].sequence==4 and orphaned.ok and orphaned.rows[0].count==0 and references.ok and references.rows.is_empty())
	_evidence.sqlite_storage.retention = {"written":6,"retained":retained.size(),"orphan_chunk_count":orphaned.rows[0].count,"foreign_key_errors":references.rows.size()}

func _check(name: String, passed: bool) -> void:
	_evidence.checks[name] = passed
	if not passed:
		_failures.append(name)
		push_error("Stage01 feasibility failure: "+name)

func _differences(a: Variant, b: Variant, path: String, result: Array) -> Array:
	if result.size()>=16:
		return result
	if a is Dictionary and b is Dictionary:
		for key: String in a:
			_differences(a[key],b.get(key),path+"/"+key,result)
	elif a is Array and b is Array and a.size()==b.size():
		for index: int in a.size():
			_differences(a[index],b[index],path+"/"+str(index),result)
	elif JSON.stringify(a,"",true,true)!=JSON.stringify(b,"",true,true):
		result.append({"path":path,"original":a,"restored":b})
	return result

func _space_cases(content: HospitalContent, storage: HospitalSnapshots) -> void:
	var narrow: WorldState = FeasibilityHospitals.create(HospitalSnapshots.uuid(),false,content)
	var geometry: HospitalSpace = HospitalSpace.new(content)
	narrow.facts.actors.sample_S14.location = {"kind":"floor","floor_id":2,"cell":[35,70],"height_m":0.0}
	_check("ghost_legal_one_cell_corridor",geometry.route(narrow,"sample_S14",2,[50,70]).ok)
	narrow.facts.floors.overrides["2"].blocked.append([50,70])
	_check("transparent_body_cannot_cross_wall",not geometry.route(narrow,"sample_S14",2,[50,70]).ok)
	_check("giant_cannot_use_one_cell_corridor",not geometry.route(narrow,"sample_S59",2,[50,70]).ok)
	var tall: WorldState = FeasibilityHospitals.create(HospitalSnapshots.uuid(),false,content)
	tall.facts.connectors.erase("lift")
	_check("tall_body_rejected_by_fixed_stair_clear_height",not geometry.route(tall,"sample_S55",2,[35,70]).ok)
	_check("human_can_use_same_fixed_stair",geometry.route(tall,"patient",2,[35,70]).ok)
	var transit: WorldState = FeasibilityHospitals.create(HospitalSnapshots.uuid(),false,content)
	var simulation: HospitalSimulation = HospitalSimulation.new(transit,content)
	_check("real_giant_transit_requested",simulation.space.request_move(transit,"sample_S59",2,[35,83]).is_empty())
	var in_cabin: Dictionary = {}
	for tick: int in 1400:
		simulation.step()
		if transit.facts.actors.sample_S59.location.kind=="transit":
			in_cabin = transit.freeze()
			break
	_check("actual_transit_body_exclusive",not in_cabin.is_empty() and not in_cabin.actors.sample_S59.location.has("cell"))
	if not in_cabin.is_empty():
		var travelling: WorldState = WorldState.new(in_cabin)
		var started: Dictionary = storage.begin(travelling,"space-transit","manual","transit")
		_check("transit_save_started",started.ok)
		var receipt: Dictionary = await _await_save(storage)
		_check("transit_save_committed",receipt.get("ok",false))
		if receipt.get("ok",false):
			var restored: Dictionary = storage.load_commit(travelling.facts.hospital_id,receipt.snapshot_id)
			_check("transit_restored_exact",restored.ok and JSON.stringify(travelling.facts,"",true,true)==JSON.stringify(restored.world.facts,"",true,true))
			if restored.ok:
				var a: HospitalSimulation = HospitalSimulation.new(travelling,content)
				var b: HospitalSimulation = HospitalSimulation.new(restored.world,content)
				for tick: int in 600:
					a.step()
					b.step()
				_check("transit_resume_same_facts",JSON.stringify(travelling.facts,"",true,true)==JSON.stringify(restored.world.facts,"",true,true))
				_check("transit_real_exit_on_second_floor",travelling.facts.actors.sample_S59.location.kind=="floor" and int(travelling.facts.actors.sample_S59.location.floor_id)==2)
	var fit_world: WorldState = FeasibilityHospitals.create(HospitalSnapshots.uuid(),true,content)
	fit_world.facts.floors.overrides["2"].blocked = []
	fit_world.facts.rooms["fit_room"] = {"id":"fit_room","kind":"ward","floor_id":2,"origin":[34,84],"size":[14,11]}
	var door: Dictionary = {"id":"fit_door","definition_id":"DR01","cell":[38,83],"span":1,"axis":"x","room_id":"fit_room","active_actor_id":"","clear_height_m":2.2}
	fit_world.facts.floors.overrides["2"].doors = [door]
	for x: int in range(33,49):
		if x!=38:
			fit_world.facts.floors.overrides["2"].blocked.append([x,83])
	fit_world.facts.actors.sample_S59.location = {"kind":"floor","floor_id":2,"cell":[38,86],"height_m":0.0}
	var fit: Dictionary = geometry.door_quote(fit_world,fit_world.facts.actors.sample_S59,2,door)
	_check("door_real_automatic_span_and_height",fit.ok and int(fit.span)==3 and absf(float(fit.clear_height_m)-6.3)<0.00001)
	var run: HospitalSimulation = HospitalSimulation.new(fit_world,content)
	_check("giant_door_route",run.space.request_move(fit_world,"sample_S59",2,[38,80]).is_empty())
	var active_door: Dictionary = {}
	for tick: int in 100:
		run.step()
		if fit_world.facts.adaptations.has(door.id):
			active_door = fit_world.freeze()
			break
	_check("door_extent_is_real_reservation",not active_door.is_empty() and int(active_door.adaptations[door.id].span)==3)
	_evidence.artifacts.door_world = active_door
	var bed: Dictionary = fit_world.facts.facilities.bed.duplicate(true)
	bed.id = "fit_bed"
	bed.floor_id = 2
	bed.cell = [37,86]
	bed.patient_cell = [37,89]
	bed.operator_cells = [[36,87],[40,87]]
	bed.repair_cell = [36,86]
	bed.room_id = "fit_room"
	fit_world.facts.facilities[bed.id] = bed
	fit_world.facts.moves.erase("sample_S59")
	fit_world.facts.adaptations.erase(door.id)
	fit_world.facts.actors.sample_S59.location = {"kind":"floor","floor_id":2,"cell":[37,92],"height_m":0.0}
	var before: String = JSON.stringify(fit_world.facts,"",true,true)
	var preview: Dictionary = geometry.facility_quote(fit_world,bed.id,"sample_S59",["ward_nurse","round_doctor"])
	_check("giant_bed_preview_is_three_by_five",preview.ok and preview.footprint==[3,5])
	_check("adaptation_preview_read_only",before==JSON.stringify(fit_world.facts,"",true,true))
	var reserved: String = geometry.reserve_facility(fit_world,bed.id,"sample_S59","sample_S59",["ward_nurse","round_doctor"])
	_check("expanded_bed_is_actual_obstacle",reserved.is_empty() and not geometry.static_reason(fit_world,fit_world.facts.actors.sample_S14,2,Vector2i(37,90)).is_empty())
	if reserved.is_empty():
		var service: HospitalClinic = HospitalClinic.new(content,geometry)
		service._support(fit_world,{"actor_id":"sample_S59"},geometry.facility_layout(fit_world,bed.id),"lying")
		_check("giant_body_physically_supported_without_scale",fit_world.facts.actors.sample_S59.posture=="lying" and geometry.overlaps_facility(fit_world,"sample_S59",bed.id))
		_evidence.artifacts.expanded_bed_world = fit_world.freeze()
		var started: Dictionary = storage.begin(fit_world,"space-bed","manual","expanded")
		_check("expanded_bed_save_started",started.ok)
		var receipt: Dictionary = await _await_save(storage)
		_check("expanded_bed_save_committed",receipt.get("ok",false))
		if receipt.get("ok",false):
			var restored: Dictionary = storage.load_commit(fit_world.facts.hospital_id,receipt.snapshot_id)
			_check("expanded_bed_restored_with_reservation",restored.ok and JSON.stringify(fit_world.facts,"",true,true)==JSON.stringify(restored.world.facts,"",true,true))
	var blocked: WorldState = WorldState.new(fit_world.freeze())
	blocked.facts.adaptations.erase(bed.id)
	blocked.facts.actors.sample_S59.location = {"kind":"floor","floor_id":2,"cell":[37,92],"height_m":0.0}
	blocked.facts.actors.sample_S59.posture = "standing"
	blocked.facts.floors.overrides["2"].blocked.append([37,90])
	var refused: Dictionary = geometry.facility_quote(blocked,bed.id,"sample_S59",["ward_nurse","round_doctor"])
	_check("blocked_extension_refused",not refused.ok)
	_evidence.artifacts.blocked_extension_reason = refused.get("reason","")
