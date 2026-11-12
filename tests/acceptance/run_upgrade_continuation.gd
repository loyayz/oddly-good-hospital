extends "res://tests/acceptance/run_upgrade_handoff.gd"
const ORDER: String="upgrade_00000225"
const WORKER: String="maintenance_contractor_00000226"
func _commitment(order: Dictionary) -> Dictionary:
	var value: Dictionary={}
	for key: String in ["id","facility_id","created_tick","cost","hospital_paid","direct_paid"]: value[key]=order.get(key)
	value.stages=[]
	for stage: Dictionary in order.stages:
		var frozen: Dictionary={}
		for key: String in ["level","price","total_milli","hospital_paid","direct_paid","rule"]: frozen[key]=stage.get(key)
		value.stages.append(frozen)
	return value.duplicate(true)
func _order_ledger(world: WorldState) -> Dictionary:
	var rows: Dictionary={}
	for key: String in world.facts.ledger.entries:
		var entry: Dictionary=world.facts.ledger.entries[key]
		if str(entry.get("owner_id",""))==ORDER or str(entry.get("owner_id","")).begins_with(ORDER+":") or key.begins_with(ORDER+":"):
			rows[key]=entry.duplicate(true)
	return rows
func _owner_valid(world: WorldState, order: Dictionary) -> bool:
	var id: String=str(order.worker_id)
	if id.is_empty(): return true # Legitimate release/reassignment is not frozen.
	var worker: Dictionary=world.facts.maintenance.contractors.get(id,{})
	return worker.get("job_id","")==ORDER and worker.get("phase","")=="assigned" and world.facts.actors.has(id)
func _phase_facts() -> Dictionary:
	var w: WorldState=sim.world
	var m: Dictionary=w.facts.moves.get(WORKER,{})
	var o: Dictionary=w.facts.maintenance.upgrades[ORDER]
	var assigned: String=str(o.get("worker_id",""))
	var movement: Dictionary=m.duplicate(true)
	for key: String in ["request_sequence","cursor"]:
		if not movement.has(key): movement[key]=-1
	for key: String in ["local_move","transit_ticket"]:
		if not movement.has(key): movement[key]={}
	if not movement.has("owner_job_id"): movement.owner_job_id=""
	# Full raw movement includes actual path/transit_wait/route_waypoint fields.
	# No geometry, route, readiness or other business query is performed.
	return {"tick":w.sim_tick,"worker":w.facts.actors.get(WORKER,{}).duplicate(true),"movement":movement,"assigned_worker_id":assigned,"assigned_worker":w.facts.actors.get(assigned,{}).duplicate(true),"assigned_movement":w.facts.moves.get(assigned,{}).duplicate(true),"lift":w.facts.connectors.benchmark_lift.duplicate(true),"order":o.duplicate(true),"grade":w.facts.facilities[TARGET].grade}
func _restore(name: String) -> bool:
	# Expected data must never be the Dictionary passed to WorldState._init.
	var frozen: Dictionary=sim.world.freeze()
	var expected: Dictionary=frozen.duplicate(true)
	_save(name)
	var before_bytes: PackedByteArray=FileAccess.get_file_as_bytes(directory+"/"+name+".bin")
	sim.dispose();sim=HospitalSimulation.new(WorldState.new(frozen),content)
	_save(name+"-restored")
	var facts_equal: bool=sim.world.freeze()==expected
	var bytes_equal: bool=before_bytes==FileAccess.get_file_as_bytes(directory+"/"+name+"-restored.bin")
	_json(name+"-restore-check.json",{"facts_equal_independent_expected":facts_equal,"full_binary_equal":bytes_equal})
	return facts_equal and bytes_equal
func _run() -> void:
	var args:=OS.get_cmdline_user_args();directory=args[1];content=HospitalContent.new()
	var f:=FileAccess.open(args[2],FileAccess.READ);var input: Dictionary=f.get_var(false);f.close()
	var expected_input: Dictionary=input.duplicate(true)
	var original_bytes: PackedByteArray=FileAccess.get_file_as_bytes(args[2])
	var before_file:=FileAccess.open(directory+"/initial-before.bin",FileAccess.WRITE)
	before_file.store_buffer(original_bytes);before_file.close()
	sim=HospitalSimulation.new(WorldState.new(input),content)
	_save("initial-restored")
	var w: WorldState=sim.world
	var payment: Dictionary=w.facts.ledger.entries.get(ORDER+":upgrade_material",{}).duplicate(true)
	var frozen_order: Dictionary=w.facts.maintenance.upgrades[ORDER].duplicate(true)
	var promised: Dictionary=_commitment(frozen_order)
	var original_order_ledger: Dictionary=_order_ledger(w)
	checks.single_initial_payment=original_order_ledger.size()==1 and original_order_ledger.has(ORDER+":upgrade_material")
	checks.frozen_commitments=true;checks.per_step_work_bound=true;checks.order_ledger_unchanged=true;checks.worker_job_ownership=true
	checks.initial_restore_exact=w.freeze()==expected_input
	checks.initial_restore_binary_exact=original_bytes==FileAccess.get_file_as_bytes(directory+"/initial-restored.bin")
	checks.original_4046_boundary=w.sim_tick==4046 and frozen_order.remaining_milli==30000 and payment.get("amount",0)==-420 and frozen_order.hospital_paid==420
	checks.no_early_grade=true;checks.payment_not_repeated=true;checks.actual_attendance_for_work=true
	_save("start")
	_json("commands.json",[])
	_json("initial-commitments.json",{"order":frozen_order,"payment":payment,"ledger":w.facts.ledger.duplicate(true),"command_keys":w.facts.keys().filter(func(key:Variant)->bool:return str(key).contains("command")),"restore_exact":checks.initial_restore_exact})
	var ordered:=FileAccess.open(directory+"/ordered-events.ndjson",FileAccess.WRITE)
	var fact_log:=FileAccess.open(directory+"/phase-facts.ndjson",FileAccess.WRITE)
	fact_log.store_line(JSON.stringify(_phase_facts()))
	var partial_restored: bool=false
	var first_arrival_saved: bool=false
	var steps: int=0
	var work: int=0
	var stop_reason: String="original_tick7633_limit"
	if checks.initial_restore_exact and checks.initial_restore_binary_exact and checks.original_4046_boundary and checks.single_initial_payment:
		while w.sim_tick<7633:
			var o: Dictionary=w.facts.maintenance.upgrades[ORDER]
			if o.phase=="completed":stop_reason="completed";break
			checks.no_early_grade=checks.no_early_grade and w.facts.facilities[TARGET].grade==0
			var previous: int=o.remaining_milli
			var working_actor: String=str(o.worker_id)
			var tick: TickResult=sim.step();steps+=1
			var es: Array=[]
			for event: SimEvent in tick.facts:es.append(event.to_record())
			ordered.store_line(JSON.stringify({"tick":tick.sim_tick,"events":es}))
			o=w.facts.maintenance.upgrades[ORDER]
			var delta: int=previous-int(o.remaining_milli);work+=delta
			# Log the first observable full-step work-cell boundary, without queries.
			var arrival_location: Dictionary=w.facts.actors.get(working_actor,{}).get("location",{})
			var observed_at_work_cell: bool=arrival_location.get("kind","")=="floor" and int(arrival_location.floor_id)==int(o.work_floor) and Vector2(float(arrival_location.cell[0]),float(arrival_location.cell[1])).distance_to(Vector2(float(o.work_cell[0]),float(o.work_cell[1])))<0.001
			if not first_arrival_saved and observed_at_work_cell:
				_save("first-observed-work-cell")
				_json("first-observed-work-cell.json",{"tick":w.sim_tick,"worker_id":working_actor,"remaining_milli":int(o.remaining_milli),"step_work_milli":delta,"cumulative_work_milli":work,"positive_work_already_observed":work>0,"scope":"First observed full-step work-cell position; may already include actual work, not necessarily a before-work boundary"})
				first_arrival_saved=true
			if delta>0:
				var loc: Dictionary=w.facts.actors.get(working_actor,{}).get("location",{})
				checks.actual_attendance_for_work=checks.actual_attendance_for_work and loc.get("kind","")=="floor" and int(loc.floor_id)==int(o.work_floor) and Vector2(float(loc.cell[0]),float(loc.cell[1])).distance_to(Vector2(float(o.work_cell[0]),float(o.work_cell[1])))<0.001
			checks.per_step_work_bound=checks.per_step_work_bound and delta>=0 and delta<=mini(100,previous)
			checks.frozen_commitments=checks.frozen_commitments and _commitment(o)==promised
			checks.order_ledger_unchanged=checks.order_ledger_unchanged and _order_ledger(w)==original_order_ledger
			checks.worker_job_ownership=checks.worker_job_ownership and _owner_valid(w,o)
			checks.payment_not_repeated=checks.payment_not_repeated and w.facts.ledger.entries.get(ORDER+":upgrade_material",{})==payment and o.hospital_paid==420
			fact_log.store_line(JSON.stringify(_phase_facts()))
			if not partial_restored and delta>0 and o.remaining_milli>0:
				checks.partial_restore_exact=_restore("actual-paid-partial")
				w=sim.world;partial_restored=true
				_json("partial-restore.json",{"tick":w.sim_tick,"remaining_milli":w.facts.maintenance.upgrades[ORDER].remaining_milli,"exact":checks.partial_restore_exact,"cold_restore_during_functional_branch":true})
				if not checks.partial_restore_exact:stop_reason="restore_mismatch";break
			if not checks.actual_attendance_for_work or not checks.payment_not_repeated or not checks.no_early_grade or not checks.per_step_work_bound or not checks.frozen_commitments or not checks.order_ledger_unchanged or not checks.worker_job_ownership:
				stop_reason="explicit_invariant_failure";break
			if steps%100==0:
				ordered.flush();fact_log.flush();_json("progress.json",{"steps":steps,"state":_phase_facts()})
			if o.phase=="completed":stop_reason="completed";break
	ordered.close();fact_log.close()
	_save("final")
	var order: Dictionary=w.facts.maintenance.upgrades[ORDER]
	var receipt: Dictionary=w.facts.maintenance.receipts.get(ORDER+":1:upgrade_completed",{})
	checks.completed=order.phase=="completed" and order.remaining_milli==0 and work==30000 and w.facts.facilities[TARGET].grade==1 and receipt.get("standard_work_milli",0)==30000
	checks.original_coverage_1ms=work>=1
	checks.partial_restore_exercised=partial_restored
	checks.valid_final=w.validate(content).is_empty()
	checks.tick_limit=steps<=3587 and w.sim_tick<=7633
	var ok: bool=checks.values().all(func(v:Variant)->bool:return v==true)
	_json("result.json",{"ok":ok,"checks":checks,"stop_reason":stop_reason,"steps":steps,"start_tick":4046,"end_tick":w.sim_tick,"work_milli":work,"order":order,"receipt":receipt,"worker":w.facts.actors[WORKER],"scope":"cold restored 4046 continuation; no commands; original .1s full World; stop at completion or7633; any actual partial restore explicitly recorded"})
	sim.dispose();quit(0 if ok else 1)
