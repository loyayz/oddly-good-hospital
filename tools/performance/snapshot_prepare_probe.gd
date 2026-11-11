extends SceneTree

var _guard: RefCounted
var _store: HospitalSnapshots
var _output: String=""

func _initialize() -> void:
	call_deferred("_run")

func _finish(result: Dictionary, exit_code: int) -> void:
	if _store!=null and _store.busy(): _store.wait_for_idle()
	if _guard!=null: _guard.call("release")
	if not _output.is_empty() and not FileAccess.file_exists(_output):
		var file: FileAccess=FileAccess.open(_output,FileAccess.WRITE)
		if file==null:
			push_error("Cannot write a new snapshot preparation result")
			quit(2)
			return
		file.store_string(JSON.stringify(result,"\t"))
		file.close()
	print("SNAPSHOT_PREPARATION="+JSON.stringify({"complete":result.get("complete",false),"output":_output,"reason":result.get("reason","")}))
	quit(exit_code)

func _path(value: String) -> String:
	return value.replace("\\","/").simplify_path().to_lower()

func _same(first: Variant, second: Variant) -> bool:
	# Same complete-fact comparison as CORE persistence cases: the JSON
	# storage format has no separate integer-valued float representation.
	return JSON.parse_string(JSON.stringify(first,"",true,true))==JSON.parse_string(JSON.stringify(second,"",true,true))

func _run() -> void:
	var repeat: int=0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--repeat="): repeat=argument.trim_prefix("--repeat=").to_int()
	var config: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://snapshot-prepare-identity.json"))
	if not config is Dictionary or not repeat in [1,2,3]: _finish({"complete":false,"reason":"Use a frozen snapshot probe and --repeat=1, 2 or 3"},2);return
	var run: Dictionary=config.runs[repeat-1]
	_output=run.output
	if FileAccess.file_exists(_output): _finish({"complete":false,"reason":"Preserve the previous measurement"},2);return
	var environment_ok: bool=_path(OS.get_environment("APPDATA"))==_path(run.environment.APPDATA) and _path(OS.get_environment("LOCALAPPDATA"))==_path(run.environment.LOCALAPPDATA)
	var data_path: String=_path(OS.get_user_data_dir())
	if not environment_ok or not data_path.begins_with(_path(run.environment.APPDATA)+"/") or data_path.get_file()!=str(config.profile).to_lower(): _finish({"complete":false,"reason":"The actual data directory is not the isolated probe profile"},2);return
	if DirAccess.dir_exists_absolute(HospitalSnapshots.ROOT): _finish({"complete":false,"reason":"A measurement needs an empty test library"},2);return
	var policy: Dictionary={"applied":false,"reason":"platform_default"}
	if OS.get_name()=="Windows" and ClassDB.class_exists("PlatformThreadPolicy"): policy=ClassDB.class_call_static("PlatformThreadPolicy","apply_main_thread")
	var preparation_start: int=Time.get_ticks_usec()
	var content: HospitalContent=HospitalContent.new()
	if not content.error.is_empty() or FileAccess.get_sha256(config.input)!=config.input_sha256 or FileAccess.get_sha256("res://game/persistence/snapshot_store.gd")!=config.snapshot.instrumented_sha256: _finish({"complete":false,"reason":"Input, content or instrumented source identity mismatch"},2);return
	var file: FileAccess=FileAccess.open(config.input,FileAccess.READ)
	if file==null: _finish({"complete":false,"reason":"Cannot open the frozen complete input"},2);return
	var envelope: Variant=file.get_var(false)
	file.close()
	if not envelope is Dictionary or envelope.content_fingerprint!=content.content_fingerprint: _finish({"complete":false,"reason":"Complete input content identity mismatch"},2);return
	var world: WorldState=WorldState.new(envelope.facts)
	var validation: String=world.validate(content)
	if not validation.is_empty() or world.present_actor_count()!=160: _finish({"complete":false,"reason":"Invalid complete160 input: "+validation},2);return
	var original: Dictionary=world.freeze()
	var original_bytes: PackedByteArray=var_to_bytes(original)
	_guard=ClassDB.instantiate("PlatformSessionGuard") as RefCounted
	var acquired: Dictionary=_guard.call("acquire")
	if not acquired.ok: _finish({"complete":false,"reason":"Cannot hold the isolated test library guard"},2);return
	var competing: RefCounted=ClassDB.instantiate("PlatformSessionGuard") as RefCounted
	var denied: Dictionary=competing.call("acquire")
	competing.call("release")
	if denied.ok or not denied.get("busy",false): _finish({"complete":false,"reason":"The real library guard did not enforce ownership"},2);return
	_store=HospitalSnapshots.new(content,_guard)
	var failures: Array=[]
	if repeat==1:
		for kind: String in ["missing_session","invalid_slot","invalid_world"]:
			var invalid: WorldState=WorldState.new(original.duplicate(true))
			if kind=="invalid_world": invalid.facts.hospital_id="invalid-hospital-id"
			var before: PackedByteArray=var_to_bytes(invalid.facts)
			var rejected: Dictionary=_store.begin(invalid,"" if kind=="missing_session" else "probe-rejection","manual","" if kind=="invalid_slot" else "probe-rejection")
			var scope: Dictionary=rejected.get("_snapshot_prepare_begin",{})
			var correct: bool=not rejected.ok and not _store.busy() and _store.hospital_ids().is_empty() and var_to_bytes(invalid.facts)==before and not scope.has("freeze") and not scope.has("thread_start")
			failures.append({"case":kind,"ok":correct,"reason":rejected.get("error",""),"timing":scope})
			if not correct: _finish({"complete":false,"reason":"Immediate rejection contract failed","failures":failures},1);return
	var preparation_usec: int=Time.get_ticks_usec()-preparation_start
	var session_id: String="snapshot-probe-"+HospitalSnapshots.uuid()
	var started_at: int=Time.get_ticks_usec()
	var begun: Dictionary=_store.begin(world,session_id,"manual","probe")
	var begin_returned_at: int=Time.get_ticks_usec()
	var receipt: Dictionary=_store.wait_for_idle() if begun.ok else begun
	var finished_at: int=Time.get_ticks_usec()
	var restore_started_at: int=Time.get_ticks_usec()
	var loaded: Dictionary=_store.load_commit(world.hospital_id,receipt.snapshot_id) if receipt.ok else receipt
	var restore_usec: int=Time.get_ticks_usec()-restore_started_at
	var checks: Dictionary={"begin_ok":begun.ok,"worker_ok":receipt.ok,"restored":loaded.ok,"source_facts_exact":var_to_bytes(world.facts)==original_bytes,"guard_held":_guard.call("is_held"),"only_original_hospital":_store.hospital_ids()==[world.hospital_id],"snapshot_idle":not _store.busy()}
	if begun.ok and receipt.ok and loaded.ok:
		checks.full_restored_facts=_same(loaded.world.facts,original)
		checks.restored_valid=loaded.world.validate(content).is_empty()
		checks.all_request_fields_in_receipt=true
		for key: String in begun.request:
			if receipt.get(key)!=begun.request[key]: checks.all_request_fields_in_receipt=false
		checks.request_owner=begun.request.hospital_id==world.hospital_id and begun.request.loading_session_id==session_id and begun.request.world_revision==world.revision and begun.request.sim_tick==world.sim_tick
		checks.manifest_owner=loaded.manifest.hospital_id==world.hospital_id and loaded.manifest.snapshot_id==receipt.snapshot_id and loaded.manifest.sequence==1 and loaded.manifest.content_packs==content.snapshot_identity()
		checks.frozen_owned=begun._snapshot_prepare_begin.freeze_copy.root_detached and begun._snapshot_prepare_begin.freeze_copy.actors_detached and begun._snapshot_prepare_begin.freeze_copy.rng_detached
	var ok: bool=checks.values().all(func(value: Variant)->bool:return value==true)
	_finish({"complete":true,"ok":ok,"repeat":repeat,"scope":"Instrumented actual Snapshot.begin(WorldState) through worker completion on the unchanged complete160 input. Three independent empty test libraries. Diagnostic overhead is included; no complete-save or160 CPU qualification claim.","input_sha256":config.input_sha256,"source_manifest_sha256":config.base_inventory_sha256,"data_directory":OS.get_user_data_dir(),"main_thread_policy":policy,"preparation_usec":preparation_usec,"restore_validation_usec":restore_usec,"begin_return_usec":begin_returned_at-started_at,"after_begin_to_idle_usec":finished_at-begin_returned_at,"begin_through_idle_usec":finished_at-started_at,"synchronous":begun.get("_snapshot_prepare_begin",{}),"background":receipt.get("_snapshot_prepare_worker",{}),"checks":checks,"failures":failures,"facts":{"hospital_id":world.hospital_id,"tick":world.sim_tick,"revision":world.revision,"present_actors":world.present_actor_count(),"actors":world.facts.actors.size(),"visits":world.facts.visits.size(),"facilities":world.facts.facilities.size()}},0 if ok else 1)
