extends SceneTree

const Observer = preload("res://tools/performance/current/comprehensive_observer.gd")
const V3_SHA256: String="752924c562f275804cee40cbd2a8760f8f0780cab3276a04330db63a2866e780"
const MIXED: String="mixed160-clinical-ops-v1"
var _checks: Dictionary={}
var _differences: Dictionary={}

func _initialize() -> void: call_deferred("_run")

func _check(name: String, passed: bool, details: Variant = null) -> void:
	_checks[name]={"passed":passed,"details":details}

func _hash(value: Variant) -> String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value));return context.finish().hex_encode()

func _load_input(path: String) -> Dictionary:
	var file: FileAccess=FileAccess.open(path,FileAccess.READ)
	if file==null: return {}
	var value: Variant=file.get_var(false);file.close()
	return value if value is Dictionary else {}

# Preserve exact field differences for an unexpected default-v3 drift. The
# typed binary hash is the strict witness; JSON differences are explanatory.
func _diff(left: Variant, right: Variant, path: String, rows: Array) -> void:
	if typeof(left)!=typeof(right):
		rows.append({"path":path,"left_type":typeof(left),"right_type":typeof(right),"left":left,"right":right});return
	if left is Dictionary:
		var keys: Array=left.keys()
		for key: Variant in right:
			if not key in keys: keys.append(key)
		for key: Variant in keys:
			var next: String=path+"/"+str(key)
			if not left.has(key) or not right.has(key): rows.append({"path":next,"left_present":left.has(key),"right_present":right.has(key),"left":left.get(key),"right":right.get(key)})
			else: _diff(left[key],right[key],next,rows)
	elif left is Array:
		if left.is_typed()!=right.is_typed() or left.get_typed_builtin()!=right.get_typed_builtin(): rows.append({"path":path,"array_element_type_left":left.get_typed_builtin(),"array_element_type_right":right.get_typed_builtin()})
		if left.size()!=right.size(): rows.append({"path":path,"left":left,"right":right})
		else:
			for index: int in left.size(): _diff(left[index],right[index],path+"/"+str(index),rows)
	elif left!=right: rows.append({"path":path,"left":left,"right":right})

func _run() -> void:
	var input: String="";var reference: String="";var generated: String="";var output: String=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--input="): input=arg.trim_prefix("--input=")
		if arg.begins_with("--v3-reference="): reference=arg.trim_prefix("--v3-reference=")
		if arg.begins_with("--v3-generated="): generated=arg.trim_prefix("--v3-generated=")
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if input.is_empty() or reference.is_empty() or generated.is_empty() or output.is_empty() or FileAccess.file_exists(output): quit(2);return
	var current: Dictionary=_load_input(input);var prior: Dictionary=_load_input(reference);var regenerated: Dictionary=_load_input(generated)
	if current.is_empty() or prior.is_empty() or regenerated.is_empty(): quit(2);return
	var content:=HospitalContent.new()
	if not content.error.is_empty(): quit(2);return
	var world:=WorldState.new(current.facts)
	var old_world:=WorldState.new(prior.facts)
	var before: Dictionary=world.freeze();var old_before: Dictionary=old_world.freeze()
	_check("original_v3_file_identity",FileAccess.get_sha256(reference)==V3_SHA256,FileAccess.get_sha256(reference))
	_check("separate_scenario_names",current.get("scenario","")==MIXED and prior.get("scenario","")=="comprehensive160-clinical-family-v3" and regenerated.get("scenario","")==prior.scenario)
	_check("same_current_content",current.content_fingerprint==content.content_fingerprint and prior.content_fingerprint==content.content_fingerprint and regenerated.content_fingerprint==content.content_fingerprint)
	_check("world_valid",world.validate(content).is_empty(),world.validate(content))
	var default_differences: Array=[];_diff(prior.facts,regenerated.facts,"facts",default_differences)
	_differences.regenerated_v3_facts=default_differences
	_check("default_v3_complete_typed_facts_unchanged",_hash(prior.facts)==_hash(regenerated.facts),{"original":_hash(prior.facts),"regenerated":_hash(regenerated.facts)})
	var metadata_differences: Array=[]
	var old_metadata: Dictionary=prior.duplicate();old_metadata.erase("facts")
	var new_metadata: Dictionary=regenerated.duplicate();new_metadata.erase("facts")
	_diff(old_metadata,new_metadata,"metadata",metadata_differences);_differences.regenerated_v3_metadata=metadata_differences
	for key: String in ["initial_cohorts","fresh_gp_cohorts","additional_fresh_patients","clinical_start","staff_initial_conditions"]:
		_check("default_v3_"+key,_hash(prior.comprehensive_setup[key])==_hash(regenerated.comprehensive_setup[key]))
	_check("default_v3_actual_preparation_steps",int(prior.comprehensive_setup.staff_preparation.actual_steps)==int(regenerated.comprehensive_setup.staff_preparation.actual_steps),regenerated.comprehensive_setup.staff_preparation.actual_steps)
	_check("complete_core_population",world.facts.actors.size()==160 and world.present_actor_count()==160 and world.facts.staff.size()==32 and world.facts.visits.size()==128)
	# These two owners publish derived facts during the original initial join:
	# Experience mirrors the current phase, and the final intake command records
	# the revision after 174 additional historical Ledger.post calls. Keep every
	# other field in both collections under the full protected-fact comparison.
	var expected_protected: Dictionary=prior.facts.duplicate(true)
	for index: int in range(44,128):
		var id: String="bench_visit_%04d"%index
		expected_protected.patient_experience.experience[id].phase="wait_examination" if index<54 else "wait_consult" if index<60 else "wait_outpatient"
	expected_protected.command_receipts["comprehensive-setup-intake-open"].new_revision+=174
	var projection_differences: Array=[]
	_diff(prior.facts.patient_experience,expected_protected.patient_experience,"facts/patient_experience",projection_differences)
	_diff(prior.facts.command_receipts,expected_protected.command_receipts,"facts/command_receipts",projection_differences)
	_differences.mixed_expected_owner_projections=projection_differences
	var protected: bool=true
	var changed_collections: Array=["visits","tickets","ledger","world_revision"]
	var protected_differences: Array=[]
	for key: Variant in prior.facts:
		if key in changed_collections: continue
		var same: bool=current.facts.has(key) and _hash(current.facts[key])==_hash(expected_protected[key])
		protected=protected and same
		if not same: _diff(expected_protected[key],current.facts.get(key),"facts/"+str(key),protected_differences)
	for key: Variant in current.facts:
		if not prior.facts.has(key): protected=false;protected_differences.append({"unexpected_fact_key":key})
	_differences.mixed_protected_facts=protected_differences
	_check("all_protected_facts_match_except_exact_approved_owner_phase_and_receipt_revision",protected)
	_check("no_prefilled_clinical_or_family_work",world.facts.sessions.is_empty() and world.facts.attempts.is_empty() and world.facts.preparations.is_empty() and world.facts.ward_stays.is_empty() and world.facts.visitors.stays.is_empty() and world.facts.visitors.requests.is_empty() and current.comprehensive_setup.clinical_start.patient_steps==0)
	var needs: Dictionary={};var expected_added: Dictionary={};var changed_visits: int=0
	var all_visits: bool=true;var all_tickets: bool=true;var histories_valid: bool=true
	for index: int in 128:
		var id: String="bench_visit_%04d"%index
		var visit: Dictionary=current.facts.visits[id]
		var original: Dictionary=prior.facts.visits[id]
		var ticket: Dictionary=current.facts.tickets[visit.ticket_id]
		needs[ticket.kind]=int(needs.get(ticket.kind,0))+1
		if index<44:
			all_visits=all_visits and _hash(visit)==_hash(original)
			all_tickets=all_tickets and _hash(ticket)==_hash(prior.facts.tickets[original.ticket_id])
			continue
		changed_visits+=1
		var expected_kind: String="examination" if index<54 else "consult" if index<60 else "outpatient"
		var stripped: Dictionary=visit.duplicate();var old_stripped: Dictionary=original.duplicate()
		for key: String in ["phase","diagnosis","doctor_fee_quote","requested_plan_id","plan_decision"]: stripped.erase(key);old_stripped.erase(key)
		all_visits=all_visits and _hash(stripped)==_hash(old_stripped) and visit.phase=="wait_"+expected_kind
		var old_ticket: Dictionary=prior.facts.tickets[original.ticket_id].duplicate();old_ticket.kind=expected_kind
		all_tickets=all_tickets and _hash(ticket)==_hash(old_ticket)
		var actor: Dictionary=current.facts.actors[visit.actor_id]
		var doctor_id: String="bench_staff_%04d"%(int(actor.location.floor_id)-1)
		var doctor: Dictionary=current.facts.staff[doctor_id]
		var progress: Dictionary=visit.diagnosis
		var state: String="insufficient" if expected_kind=="examination" else "review_pending" if expected_kind=="consult" else "diagnosed"
		histories_valid=histories_valid and progress.gp_completed and progress.state==state and not progress.review_completed and progress.doctor_id==doctor_id and progress.facility_id=="bench_room_%d_00_0"%int(actor.location.floor_id) and progress.exam_completed==(expected_kind=="consult") and progress.insufficient==(expected_kind!="outpatient") and int(progress.insufficient_bp)==int(content.balance.clinical.diagnosis_insufficient_bp[int(doctor.abilities.diagnosis)])
		histories_valid=histories_valid and int(visit.doctor_fee_quote)==content.doctor_fee(doctor.title_id) and visit.requested_plan_id=="P_D09_COMMON" and (visit.plan_decision.get("plan_id","")=="P_D09_COMMON" if expected_kind=="outpatient" else visit.plan_decision.is_empty())
		var receipts: Dictionary={"consultation":content.doctor_fee(doctor.title_id),"gp":content.facility_fee("FUR02","gp")}
		if expected_kind=="consult":
			var mode: String="spectrum" if index%2==0 else "resonance"
			histories_valid=histories_valid and progress.exam_kind==mode
			receipts[mode]=content.facility_fee("FUR02",mode)
		else: histories_valid=histories_valid and str(progress.exam_kind).is_empty()
		for component: String in receipts: expected_added[id+":"+component]={"owner_id":id,"component":component,"amount":int(receipts[component]),"tick":world.sim_tick,"settled":true}
	_check("mixed_exact_cohort_counts",needs=={"surgery":12,"outpatient":76,"examination":12,"consult":8,"gp":20},needs)
	_check("only_approved84_visit_fields_changed",all_visits and changed_visits==84)
	_check("all128_ticket_ids_and_only84_pending_kinds_changed",all_tickets and current.facts.tickets.size()==128 and prior.facts.tickets.size()==128)
	_check("historical_doctor_exam_plan_qualification_and_fee_inputs",histories_valid)
	var actual_added: Dictionary={};var entries_retained: bool=true;var added_amount: int=0
	for id: String in prior.facts.ledger.entries: entries_retained=entries_retained and current.facts.ledger.entries.get(id,{})==prior.facts.ledger.entries[id]
	for id: String in current.facts.ledger.entries:
		if not prior.facts.ledger.entries.has(id): actual_added[id]=current.facts.ledger.entries[id];added_amount+=int(actual_added[id].amount)
	_check("exact174_new_diagnostic_receipts_existing_ledger_preserved",entries_retained and actual_added==expected_added and actual_added.size()==174,{"count":actual_added.size(),"amount":added_amount})
	var ledger_before: Dictionary=prior.facts.ledger.duplicate();ledger_before.erase("entries")
	var ledger_after: Dictionary=current.facts.ledger.duplicate();ledger_after.erase("entries")
	_check("cash_conservation_no_opening_balance_reset",_hash(ledger_before)==_hash(ledger_after) and HospitalLedger.balance(world)-HospitalLedger.balance(old_world)==added_amount,{"v3_cash":HospitalLedger.balance(old_world),"mixed_cash":HospitalLedger.balance(world),"delta":added_amount})
	_check("revision_changes_only_for174_posted_receipts",int(current.facts.world_revision)-int(prior.facts.world_revision)==174)
	_check("historical_join_audit",current.comprehensive_setup.historical_ledger_audit.ok and current.comprehensive_setup.historical_ledger_audit.receipt_count==224 and current.comprehensive_setup.historical_ledger_audit.rng_unchanged)
	_check("additional_patient_metadata_conserves128",current.comprehensive_setup.additional_fresh_patients.is_empty() and current.comprehensive_setup.additional_patients.size()==8 and current.comprehensive_setup.initial_cohorts.size()==108 and current.comprehensive_setup.fresh_gp_cohorts.size()==20 and current.comprehensive_setup.clinical_start.additional_historical_patients==8 and current.comprehensive_setup.clinical_start.total_additional_patients==8 and current.comprehensive_setup.clinical_start.original_patients+current.comprehensive_setup.clinical_start.total_additional_patients==128)
	var old_gate: Dictionary=Observer.new(content).report(world)
	var new_gate: Dictionary=Observer.new(content,MIXED).report(world)
	_check("same_complete_coverage_gates_and_no_initial_coverage",old_gate.coverage==new_gate.coverage and old_gate.uncovered==new_gate.uncovered and not new_gate.coverage_pass and new_gate.scenario==MIXED and old_gate.scenario==prior.scenario,{"coverage":new_gate.coverage,"uncovered":new_gate.uncovered})
	_check("contract_checks_leave_all_world_facts_unchanged",_hash(before)==_hash(world.freeze()) and _hash(old_before)==_hash(old_world.freeze()))
	var passed: bool=true
	for value: Dictionary in _checks.values(): passed=passed and value.passed
	var result: Dictionary={"passed":passed,"checks":_checks,"differences":_differences,"input":{"path":input,"sha256":FileAccess.get_sha256(input),"facts_sha256":_hash(current.facts)},"original_v3":{"path":reference,"sha256":FileAccess.get_sha256(reference),"facts_sha256":_hash(prior.facts)},"regenerated_v3":{"path":generated,"sha256":FileAccess.get_sha256(generated),"facts_sha256":_hash(regenerated.facts)},"scope":"Readonly complete input contracts. No production step, sampled service completion, admission, family draw or performance result is claimed. Default v3 typed facts must match the immutable original; exact metadata differences are retained separately. The mixed row has a different explicit current clinical workload and its own baseline."}
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if file==null: quit(2);return
	file.store_string(JSON.stringify(result,"\t",true,true));file.close()
	print("MIXED_INPUT_CONTRACT="+JSON.stringify({"passed":passed,"checks":_checks.size(),"output":output}))
	quit(0 if passed else 1)
