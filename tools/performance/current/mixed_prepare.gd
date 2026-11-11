extends "res://tools/performance/current/comprehensive_prepare.gd"

const MixedInputs = preload("res://tools/performance/current/mixed_clinical_inputs.gd")

func _init() -> void:
	_scenario=MixedInputs.SCENARIO
	_input_name="mixed160"

func _declare_clinical_boundary(pending: Dictionary, world: WorldState, content: HospitalContent) -> Dictionary:
	var cohorts: Dictionary=super._declare_clinical_boundary(pending,world,content)
	if not cohorts.ok: return cohorts
	cohorts=MixedInputs.declare(pending,world,content,cohorts)
	if not cohorts.ok: return cohorts
	_setup.mixed_clinical_boundary=cohorts.mixed_declaration
	_setup.additional_patients=cohorts.additional_records
	return cohorts

func _join_patient_batch(sim: HospitalSimulation, pending: Dictionary, visit_ids: Array, name: String) -> Dictionary:
	var world: WorldState=sim.world
	var opening: int=HospitalLedger.balance(world)
	var old_entries: Dictionary=world.facts.ledger.entries.duplicate(true)
	var old_rng: Dictionary=world.facts.rng.duplicate(true)
	var expected: Dictionary={}
	var expected_amount: int=0
	for row: Dictionary in _setup.initial_cohorts:
		for receipt: Dictionary in row.receipts:
			var entry_id: String=str(row.visit_id)+":"+str(receipt.component)
			expected[entry_id]={"owner_id":row.visit_id,"component":receipt.component,"amount":int(receipt.amount),"tick":world.sim_tick,"settled":true}
			expected_amount+=int(receipt.amount)
	var result: Dictionary=super._join_patient_batch(sim,pending,visit_ids,name)
	var actual: Dictionary={}
	var retained: bool=true
	for id: String in old_entries: retained=retained and world.facts.ledger.entries.get(id,{})==old_entries[id]
	for id: String in world.facts.ledger.entries:
		if not old_entries.has(id): actual[id]=world.facts.ledger.entries[id].duplicate(true)
	var closing: int=HospitalLedger.balance(world)
	var audit: Dictionary={"ok":retained and actual==expected and closing-opening==expected_amount and old_rng==world.facts.rng,"opening_cash":opening,"closing_cash":closing,"cash_delta":closing-opening,"expected_historical_receipts":expected,"actual_historical_receipts":actual,"existing_ledger_preserved":retained,"receipt_count":actual.size(),"rng_before":old_rng,"rng_after":world.facts.rng.duplicate(true),"rng_unchanged":old_rng==world.facts.rng,"scope":"Only saved historical diagnostic receipts are posted once through HospitalLedger during the initial declaration. Cash increases by their exact sum; no balancing reset, fabricated completion event, patient step or RNG draw occurs. All future service work and income remain measured production outcomes."}
	_setup.historical_ledger_audit=audit
	result.ok=result.ok and audit.ok
	if not audit.ok: result.reason="Mixed historical receipt/identity/RNG declaration failed"
	return result

func _identity() -> Dictionary:
	var result: Dictionary=super._identity()
	for path: String in ["res://tools/performance/current/mixed_prepare.gd","res://tools/performance/current/mixed_clinical_inputs.gd"]: result.sources[path]=FileAccess.get_sha256(path)
	return result
