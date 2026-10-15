extends SceneTree

const Factory = preload("res://game/sim/hospital_factory.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	_check("content_loaded",content.error.is_empty())
	if not content.error.is_empty():
		print(JSON.stringify({"stage":24,"suite":"integration","failures":failures,"content_error":content.error}))
		quit(1)
		return
	var world: WorldState = Factory.create(HospitalSnapshots.uuid(),"Stage24 集成验证",true,content)
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	var initial_reason: String = world.validate(content)
	print("INITIAL_WORLD_VALIDATE_REASON="+initial_reason)
	_check("actual_factory_world_initially_valid",initial_reason.is_empty())
	if not initial_reason.is_empty():
		_finish()
		return
	var old_id: String = world.hospital_id
	var new_id: String = HospitalSnapshots.uuid()
	var source_ledger_key: String = ""
	for key: String in world.facts.ledger.entries:
		if str(world.facts.ledger.entries[key].owner_id)==old_id:
			source_ledger_key=key
			break
	var library: HospitalLibrary = HospitalLibrary.new(content,HospitalSnapshots.new(content,null))
	var remapped_facts: Dictionary = library.call("_remap_hospital",world.freeze(),old_id,new_id)
	var remapped: WorldState = WorldState.new(remapped_facts)
	var remapped_reason: String = remapped.validate(content)
	print("REMAPPED_FACTORY_VALIDATE_REASON="+remapped_reason)
	_check("remapped_factory_world_valid",remapped_reason.is_empty())
	_check("remapped_hospital_identity",remapped.hospital_id==new_id)
	_check("ordinary_starter_entities_and_definitions_are_stable",JSON.stringify(world.facts.facilities.keys())==JSON.stringify(remapped.facts.facilities.keys()) and JSON.stringify(world.facts.staff.keys())==JSON.stringify(remapped.facts.staff.keys()))
	var remapped_ledger_key: String = ""
	var ledger_owner_sync: bool = not source_ledger_key.is_empty()
	if not source_ledger_key.is_empty():
		var source_entry: Dictionary = world.facts.ledger.entries[source_ledger_key]
		remapped_ledger_key=new_id+":"+str(source_entry.component)
		var remapped_entry: Dictionary = remapped.facts.ledger.entries.get(remapped_ledger_key,{})
		ledger_owner_sync=remapped_entry.get("owner_id","")==new_id and int(remapped_entry.get("amount",0))==int(source_entry.amount) and not remapped.facts.ledger.entries.has(source_ledger_key)
	_check("hospital_owned_ledger_key_and_owner_are_remapped",ledger_owner_sync)
	_check("initial_factory_world_has_owner_ledger_entry",not source_ledger_key.is_empty())
	var quote: Dictionary = simulation.services.recruitment.standard_preview(world,{"role":"receptionist"})
	_check("standard_receptionist_quote_available",bool(quote.get("ok",false)))
	if not quote.get("ok",false):
		_finish(simulation)
		return
	var hire_payload: Dictionary = {"standard_key":quote.standard_key,"ordinal":quote.ordinal,"filter":{"role":"receptionist"},"quote_hash":quote.quote_hash}
	var hire: CommandResult = simulation.apply(GameCommand.new("stage24-integration-hire",world.hospital_id,world.revision,"recruitment_hire",BusinessPayload.new(hire_payload),"stage24-integration-session"))
	_check("real_receptionist_hire_command_accepted",hire.accepted and not hire.changed_ids.is_empty())
	if not hire.accepted or hire.changed_ids.is_empty():
		_finish(simulation)
		return
	var hired_id: String = str(hire.changed_ids[0])
	_check("immediate_hire_has_training_schedule_and_life_defaults",world.facts.has("training_jobs") and world.facts.has("staff_schedule") and world.facts.has("staff_life") and world.facts.staff.has(hired_id))
	_check("immediate_hire_world_valid_before_tick",world.validate(content).is_empty())
	var guard: RefCounted = ClassDB.instantiate("PlatformSessionGuard") as RefCounted
	_check("native_session_guard_available",guard!=null)
	if guard==null:
		_finish(simulation)
		return
	var acquired: Dictionary = guard.call("acquire")
	_check("native_session_guard_acquired",bool(acquired.get("ok",false)))
	if not acquired.get("ok",false):
		_finish(simulation,guard)
		return
	var snapshots: HospitalSnapshots = HospitalSnapshots.new(content,guard)
	var saved: Dictionary = snapshots.begin(simulation,"stage24-integration-session","checkpoint","stage24-command-save-load")
	_check("immediate_hire_snapshot_started",bool(saved.get("ok",false)))
	if not saved.get("ok",false):
		print("IMMEDIATE_SQL_SAVE_ERROR="+str(saved.get("error","")))
		guard.call("release")
		_finish(simulation)
		return
	var receipt: Dictionary = snapshots.wait_for_idle()
	print("IMMEDIATE_SQL_SAVE_RECEIPT="+JSON.stringify(receipt))
	_check("immediate_hire_snapshot_written",bool(receipt.get("ok",false)))
	var loaded: Dictionary = snapshots.load_commit(str(receipt.get("hospital_id","")),str(receipt.get("snapshot_id","")))
	print("IMMEDIATE_SQL_LOAD_ERROR="+str(loaded.get("error","")))
	_check("immediate_hire_snapshot_read_from_sql",bool(loaded.get("ok",false)))
	if loaded.get("ok",false):
		var loaded_world: WorldState = loaded.world as WorldState
		_check("immediate_hire_sql_roundtrip_valid",loaded_world.validate(content).is_empty())
		_check("immediate_hire_sql_roundtrip_preserves_hired_staff",loaded_world.facts.staff.has(hired_id))
		_check("immediate_hire_sql_roundtrip_preserves_facts",JSON.stringify(loaded_world.freeze(),"",true,true)==JSON.stringify(world.freeze(),"",true,true))
	guard.call("release")
	_finish(simulation)

func _check(label: String, passed: bool) -> void:
	if not passed:
		failures.append(label)

func _finish(simulation: HospitalSimulation = null, guard: RefCounted = null) -> void:
	if guard!=null and guard.call("is_held"):
		guard.call("release")
	if simulation!=null:
		simulation.dispose()
	print(JSON.stringify({"stage":24,"suite":"integration","passed":failures.is_empty(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
