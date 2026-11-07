extends RefCounted

# Actual contractor admission, movement, work and departure use production
# 0.1-second phases. Storage/placement/quote/retry go through real commands.
func run(suite) -> Dictionary:
	var results: Dictionary = {}
	var passed: bool = true
	for upgrade: bool in [false,true]:
		for started: bool in [false,true]:
			var key: String = ("upgrade" if upgrade else "repair")+("_working" if started else "_travelling")
			results[key] = _scenario(suite,upgrade,started,key)
			passed = passed and results[key].ok
	return {"ok":passed,"details":results}

func _order(f: Dictionary, id: String, upgrade: bool) -> Dictionary:
	return f.w.facts.maintenance["upgrades" if upgrade else "jobs"][id]

func _progress(order: Dictionary, upgrade: bool) -> Dictionary:
	var source: Dictionary = order.stages[0] if upgrade else order
	return {"remaining":order.remaining_milli,"completed":source.completed_milli,"contributions":source.contributions.duplicate(true),"paid":source.get("hospital_paid",order.get("paid_parts",0)),"frozen":source.get("rule",order.get("frozen_class",{})).duplicate(true)}

func _scenario(suite, upgrade: bool, started: bool, key: String) -> Dictionary:
	var f: Dictionary = suite._machine("Store active external contractor work "+key)
	var cash: int = HospitalLedger.balance(f.w)
	var id: String = ""
	if upgrade:
		f.w.facts.research.append("R12")
		var accepted: CommandResult = suite._command(f,"upgrade_order",{"facility_id":"ops_machine","target_level":1})
		if not accepted.accepted: return {"ok":false,"reason":accepted.reason}
		id = accepted.changed_ids[0]
	else:
		f.w.facts.facilities.ops_machine.condition = 18.0
		f.w.facts.facilities.ops_machine.failed = true
		f.s.services.maintenance.boundaries(f.w)
		id = f.w.facts.facilities.ops_machine.maintenance_order_id
	var validations: Array = [f.w.validate(suite._content)]
	for tick: int in 400:
		suite._work_tick(f,"maintenance")
		var order: Dictionary = _order(f,id,upgrade)
		if started and int(_progress(order,upgrade).completed)>=1000: break
		var worker: String = order.worker_id
		if not started and not worker.is_empty() and f.w.facts.moves.has(worker) and f.w.facts.actors[worker].location.get("cell",[])!=f.w.facts.entry.cell: break
	var before: Dictionary = _progress(_order(f,id,upgrade),upgrade)
	var worker_id: String = _order(f,id,upgrade).worker_id
	if worker_id.is_empty() or before.completed!=(1000 if started else 0): return {"ok":false,"reason":"Real work boundary not reached","progress":before}
	var actor_before: Dictionary = f.w.facts.actors[worker_id].duplicate(true)
	var frozen: Dictionary = f.w.freeze()
	var draft: Dictionary = {"kind":"build_store","target_id":"ops_machine"}
	var first_quote: Dictionary = f.s.services.building.preview(f.w,draft)
	var second_quote: Dictionary = f.s.services.building.preview(f.w,draft)
	var preview_readonly: bool = first_quote.ok and second_quote.ok and frozen==f.w.freeze()
	# Candidate suspension must not leak out if quote validation rejects commit.
	var stale: CommandResult = suite._command(f,"build_store",{"target_id":"ops_machine","quote":{"kind":"build_store","price":1,"refund":0,"targets":{}}})
	var rejected_atomically: bool = not stale.accepted and frozen==f.w.freeze()
	var command_id: String = "inventory_store_"+key
	var stored: CommandResult = suite._command(f,"build_store",{"target_id":"ops_machine"},command_id)
	validations.append(f.w.validate(suite._content))
	var suspended: bool = stored.accepted and _order(f,id,upgrade).phase=="inventory" and _order(f,id,upgrade).worker_id=="" and f.w.facts.maintenance.contractors[worker_id].phase=="leaving" and f.w.facts.actors[worker_id]==actor_before and not f.w.facts.moves.has(worker_id) and _progress(_order(f,id,upgrade),upgrade)==before
	if not suspended or not validations[-1].is_empty():
		return {"ok":false,"preview_readonly":preview_readonly,"rejected_atomically":rejected_atomically,"suspended":suspended,"validation":validations,"order":_order(f,id,upgrade).duplicate(true),"contractor":f.w.facts.maintenance.contractors[worker_id].duplicate(true)}
	frozen = f.w.freeze()
	var repeated: CommandResult = suite._command(f,"build_store",{"target_id":"ops_machine"},command_id)
	var idempotent: bool = repeated.accepted and frozen==f.w.freeze()
	var restored: Dictionary = suite._restore(f)
	validations.append(restored.w.validate(suite._content))
	var retained: bool = _progress(_order(restored,id,upgrade),upgrade)==before and restored.w.facts.maintenance.contractors[worker_id].phase=="leaving" and restored.w.facts.actors[worker_id]==actor_before
	var blocked_exit: bool = true
	if started:
		var exit: Array = restored.s.space.exit_cell(restored.w,restored.w.facts.actors[worker_id])
		restored.w.facts.floors.overrides["1"].blocked.append(exit.duplicate())
		restored.w.touch()
		for tick: int in 15: suite._work_tick(restored,"maintenance")
		blocked_exit = restored.w.facts.maintenance.contractors[worker_id].phase=="leaving" and restored.w.facts.actors[worker_id].location.kind=="floor" and _progress(_order(restored,id,upgrade),upgrade)==before
		restored.w.facts.floors.overrides["1"].blocked.erase(exit)
		restored.w.touch()
	var same_order: bool = true
	var reissued: bool = true
	var replacement_worker: String = ""
	var reissued_before_departure: bool = true
	if started:
		# Re-place while the old worker is still leaving. The old ownership must
		# not be revived or confused with the new contractor for the same order.
		same_order = suite._place(restored,"ops_machine","M09",[46,80],"","ops_machine") and _order(restored,id,upgrade).phase=="queued" and _progress(_order(restored,id,upgrade),upgrade)==before
		suite._work_tick(restored,"maintenance")
		replacement_worker = _order(restored,id,upgrade).worker_id
		reissued = not replacement_worker.is_empty() and replacement_worker!=worker_id and _progress(_order(restored,id,upgrade),upgrade)==before
		reissued_before_departure = restored.w.facts.maintenance.contractors[worker_id].phase=="leaving" and reissued
	for tick: int in 500:
		suite._work_tick(restored,"maintenance")
		if restored.w.facts.maintenance.contractors[worker_id].phase=="departed": break
	var progress: Dictionary = _progress(_order(restored,id,upgrade),upgrade)
	var departed: bool = restored.w.facts.maintenance.contractors[worker_id].phase=="departed" and restored.w.facts.actors[worker_id].location.kind=="outside" and int(progress.contributions.get(worker_id,0))==int(before.completed) and (started or progress==before)
	validations.append(restored.w.validate(suite._content))
	if not started:
		same_order = suite._place(restored,"ops_machine","M09",[46,80],"","ops_machine") and _order(restored,id,upgrade).phase=="queued" and _progress(_order(restored,id,upgrade),upgrade)==before
		suite._work_tick(restored,"maintenance")
		replacement_worker = _order(restored,id,upgrade).worker_id
		reissued = not replacement_worker.is_empty() and replacement_worker!=worker_id and _progress(_order(restored,id,upgrade),upgrade)==before
	for tick: int in 650:
		suite._work_tick(restored,"maintenance")
		if _order(restored,id,upgrade).phase=="completed": break
	var order: Dictionary = _order(restored,id,upgrade)
	var final_progress: Dictionary = _progress(order,upgrade)
	var preserved_original_work: bool = int(final_progress.contributions.get(worker_id,0))==int(before.completed) and int(final_progress.contributions.get(replacement_worker,0))==30000-int(before.completed)
	var total_cost: int = cash-HospitalLedger.balance(restored.w)
	var finished: bool = order.phase=="completed" and final_progress.remaining==0 and final_progress.completed==30000 and total_cost==(420 if upgrade else 40) and preserved_original_work and restored.w.facts.maintenance.receipts.size()==1
	if not replacement_worker.is_empty():
		for tick: int in 500:
			suite._work_tick(restored,"maintenance")
			if restored.w.facts.maintenance.contractors[replacement_worker].phase=="departed": break
	var all_left: bool = true
	for worker: Dictionary in restored.w.facts.maintenance.contractors.values():
		all_left = all_left and worker.phase=="departed" and restored.w.facts.actors[worker.id].location.kind=="outside"
	validations.append(restored.w.validate(suite._content))
	var result: bool = finished and same_order and reissued and reissued_before_departure and all_left and departed and retained and blocked_exit and preview_readonly and rejected_atomically and idempotent and f.errors.is_empty() and restored.errors.is_empty() and validations.all(func(value: String) -> bool: return value.is_empty())
	return {"ok":result,"preview_readonly":preview_readonly,"stale_quote_atomic":rejected_atomically,"duplicate_store_unchanged":idempotent,"actual_storage_handoff":suspended,"restore_retains_ownership":retained,"blocked_exit_preserves_body":blocked_exit,"original_actual_departure":departed,"same_order_replaced":same_order,"new_worker_reissued":reissued,"reissued_while_old_leaving":reissued_before_departure,"original_work_preserved":preserved_original_work,"all_contractors_actually_left":all_left,"before":before,"final":final_progress,"total_paid":total_cost,"validations":validations,"errors":restored.errors}
