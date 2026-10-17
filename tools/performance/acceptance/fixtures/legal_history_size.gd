extends SceneTree

# Preparation only. This script does not advance or benchmark a hospital.
# The three added collections follow tools/performance/history.gd's legal
# archived-input pattern. Added history is fixture input, not simulated history.
const MIB: int = 1024 * 1024
const TARGETS: Array[int] = [64,128]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var input_path: String = ""
	var output_dir: String = ""
	var template_id: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="): input_path = argument.trim_prefix("--input=")
		if argument.begins_with("--output-dir="): output_dir = argument.trim_prefix("--output-dir=")
		if argument.begins_with("--template-visit="): template_id = argument.trim_prefix("--template-visit=")
	if input_path.is_empty() or output_dir.is_empty():
		_fail("Provide --input=<Fixture.store_input bin> and --output-dir=<new fixture directory>.")
		return
	var content: HospitalContent = HospitalContent.new()
	if not content.error.is_empty():
		_fail(content.error)
		return
	var source_file: FileAccess = FileAccess.open(input_path,FileAccess.READ)
	if source_file==null:
		_fail("Cannot read input: "+input_path)
		return
	var raw: Variant = source_file.get_var()
	source_file.close()
	if not raw is Dictionary or not raw.get("facts") is Dictionary or raw.get("content_fingerprint","")!=content.content_fingerprint:
		_fail("Input must be a current-content Fixture.store_input envelope.")
		return
	var source: Dictionary = raw
	var baseline: Dictionary = source.facts
	var before: WorldState = WorldState.new(baseline)
	var validation: String = before.validate(content)
	if not validation.is_empty():
		_fail("Source validation failed: "+validation)
		return
	if template_id.is_empty():
		for id: String in baseline.visits:
			if _eligible_template(baseline,baseline.visits[id]):
				template_id = id
				break
	if not baseline.visits.has(template_id) or not _eligible_template(baseline,baseline.visits[template_id]):
		_fail("A resident-free, unserved Visit with no attempt/evidence/decision/relative is required; keep the actual workload in this same input.")
		return
	var template: Dictionary = baseline.visits[template_id]
	var active_before: Array = before.active_visit_ids()
	var present_before: int = before.present_actor_count()
	# Only these three containers receive new records. Every original record and
	# all other facts, including entity_next, RNG, ledger and active work, stay put.
	var facts: Dictionary = baseline.duplicate()
	facts.visits = baseline.visits.duplicate()
	facts.actors = baseline.actors.duplicate()
	facts.arrival_receipts = baseline.get("arrival_receipts",{}).duplicate()
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	if directory_error!=OK:
		_fail("Cannot create output directory: %d"%directory_error)
		return
	var added: int = 0
	var encoded_bytes: int = _canonical_bytes(facts)
	if encoded_bytes<0: return
	var bytes_per_record: float = 0.0
	var observations: Array = []
	for target_mib: int in TARGETS:
		var target_bytes: int = target_mib*MIB
		while encoded_bytes<target_bytes:
			var batch: int = 256 if bytes_per_record<=0.0 else maxi(1,ceili(float(target_bytes-encoded_bytes)/bytes_per_record)+16)
			var previous_size: int = encoded_bytes
			for index: int in batch:
				if not _append_history(facts,template,baseline.actors[template.actor_id],added): return
				added += 1
			encoded_bytes = _canonical_bytes(facts)
			if encoded_bytes<0: return
			bytes_per_record = float(encoded_bytes-previous_size)/float(batch)
		var world: WorldState = WorldState.new(facts)
		validation = world.validate(content)
		var preserved: bool = _original_facts_preserved(baseline,facts,added)
		var active_equal: bool = world.active_visit_ids()==active_before and world.present_actor_count()==present_before
		if not validation.is_empty() or not preserved or not active_equal:
			_fail("Generated history invalid; validation=%s original_facts=%s active=%s"%[validation,preserved,active_equal])
			return
		var output: String = output_dir.path_join("history_%dmib.input.bin"%target_mib)
		var world_json: String = output_dir.path_join("history_%dmib.world.json"%target_mib)
		if FileAccess.file_exists(output) or FileAccess.file_exists(world_json):
			_fail("Output already exists; preserve it and choose a new directory: "+output)
			return
		var envelope: Dictionary = source.duplicate()
		envelope.facts = facts
		var encoder: HospitalJsonStream = HospitalJsonStream.new()
		if not encoder.encode(world_json,facts,_preparation_budget) or encoder.bytes<target_bytes:
			_fail("Canonical world JSON did not meet target: "+encoder.error)
			return
		var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
		if file==null:
			_fail("Cannot create fixture: "+output)
			return
		file.store_var(envelope)
		file.flush()
		var file_bytes: int = file.get_length()
		var write_error: Error = file.get_error()
		file.close()
		if write_error!=OK:
			_fail("Fixture write failed: "+output)
			return
		observations.append({"path":output,"world_json":world_json,"target_mib":target_mib,"canonical_world_json_bytes":encoder.bytes,"world_json_sha256":encoder.digest,"fixture_file_bytes":file_bytes,
			"added_archived_visits":added,"active_visits":active_before.size(),"present_actors":present_before,
			"original_facts_and_rng_preserved":preserved,"validation":validation,"sha256":FileAccess.get_sha256(output)})
		print("HISTORY_FIXTURE="+JSON.stringify(observations.back()))
	var report: Dictionary = {"preparation_only":true,"engine":Engine.get_version_info().string,
		"content_fingerprint":content.content_fingerprint,"source":input_path,"source_sha256":FileAccess.get_sha256(input_path),
		"template_visit":template_id,"sizes_kind":"Original HospitalJsonStream canonical world JSON bytes; Fixture binary length recorded separately",
		"history_origin":"legal archived fixture records; not simulated past events","outputs":observations}
	var report_file: FileAccess = FileAccess.open(output_dir.path_join("history-generation.json"),FileAccess.WRITE)
	if report_file==null:
		_fail("Cannot write generation report.")
		return
	report_file.store_string(JSON.stringify(report,"\t"))
	report_file.close()
	quit(0)

func _canonical_bytes(facts: Dictionary) -> int:
	var encoder: HospitalJsonStream = HospitalJsonStream.new()
	if not encoder.encode_to(facts,_preparation_budget,_count_sink):
		_fail("Original canonical JSON encoder rejected input: "+encoder.error)
		return -1
	return encoder.bytes

func _preparation_budget(_bytes: int) -> bool:
	# Offline generation is not a test of the game's save admission/headroom.
	# Actual disk failure still propagates from the encoder and FileAccess.
	return true

func _count_sink(_chunk: PackedByteArray) -> Dictionary:
	return {"ok":true}

func _eligible_template(facts: Dictionary, visit: Dictionary) -> bool:
	var actor: Dictionary = facts.actors.get(visit.get("actor_id",""),{})
	return not actor.is_empty() and str(actor.get("resident_id","")).is_empty() and str(actor.get("support_facility_id","")).is_empty() \
		and str(visit.get("relative_actor_id","")).is_empty() and visit.get("attempt_ids",[]).is_empty() \
		and visit.get("evidence_by_source",{}).is_empty() and visit.get("plan_decision",{}).is_empty() \
		and int(visit.get("doctor_fee_quote",-1))==-1 and visit.get("phase","") in ["arrival","wait_reception","departed"]

func _append_history(facts: Dictionary, template: Dictionary, actor: Dictionary, index: int) -> bool:
	var visit_id: String = "formal_history_visit_%08d"%index
	var actor_id: String = "formal_history_actor_%08d"%index
	var arrival_key: String = "formal_history_arrival_%08d"%index
	if facts.visits.has(visit_id) or facts.actors.has(actor_id) or facts.arrival_receipts.has(arrival_key):
		_fail("Fixture namespace collides with source input.")
		return false
	var archived: Dictionary = template.duplicate(true)
	archived.merge({"id":visit_id,"actor_id":actor_id,"arrival_key":arrival_key,"phase":"departed","ticket_id":"",
		"final_result":"referred","departed_tick":int(facts.sim_tick),"departure_recorded":true,"companion_intent":false},true)
	var past_actor: Dictionary = actor.duplicate(true)
	past_actor.merge({"id":actor_id,"location":{"kind":"outside"}},true)
	facts.visits[visit_id] = archived
	facts.actors[actor_id] = past_actor
	facts.arrival_receipts[arrival_key] = visit_id
	return true

func _original_facts_preserved(baseline: Dictionary, facts: Dictionary, added: int) -> bool:
	var reduced: Dictionary = facts.duplicate()
	for field: String in ["visits","actors","arrival_receipts"]: reduced[field] = facts[field].duplicate()
	for index: int in added:
		reduced.visits.erase("formal_history_visit_%08d"%index)
		reduced.actors.erase("formal_history_actor_%08d"%index)
		reduced.arrival_receipts.erase("formal_history_arrival_%08d"%index)
	return reduced==baseline

func _fail(reason: String) -> void:
	push_error(reason)
	quit(2)
