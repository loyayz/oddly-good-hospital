extends "res://tests/acceptance/run_upgrade_handoff.gd"
const ORDER: String="upgrade_00000225"
const WORKER: String="maintenance_contractor_00000226"
func _phase_facts() -> Dictionary:
	var w: WorldState=sim.world
	var m: Dictionary=w.facts.moves.get(WORKER,{})
	var o: Dictionary=w.facts.maintenance.upgrades[ORDER]
	return {"tick":w.sim_tick,"worker":w.facts.actors.get(WORKER,{}).duplicate(true),"movement":{"request_sequence":m.get("request_sequence",-1),"cursor":m.get("cursor",-1),"local_move":m.get("local_move",{}).duplicate(true),"transit_ticket":m.get("transit_ticket",{}).duplicate(true),"owner_job_id":m.get("owner_job_id","")},"lift":w.facts.connectors.benchmark_lift.duplicate(true),"order":o.duplicate(true),"grade":w.facts.facilities[TARGET].grade}
func _run() -> void:
	var args:=OS.get_cmdline_user_args();directory=args[1];content=HospitalContent.new()
	var f:=FileAccess.open(args[2],FileAccess.READ);var input: Dictionary=f.get_var(false);f.close()
	sim=HospitalSimulation.new(WorldState.new(input),content)
	var w: WorldState=sim.world
	var payment: Dictionary=w.facts.ledger.entries.get(ORDER+":upgrade_material",{}).duplicate(true)
	var frozen_order: Dictionary=w.facts.maintenance.upgrades[ORDER].duplicate(true)
	checks.initial_restore_exact=w.freeze()==input
	checks.original_4046_boundary=w.sim_tick==4046 and frozen_order.remaining_milli==30000 and payment.get("amount",0)==-420 and frozen_order.hospital_paid==420
	checks.no_early_grade=true;checks.payment_not_repeated=true;checks.actual_attendance_for_work=true
	_save("start")
	_json("commands.json",[])
	_json("initial-commitments.json",{"order":frozen_order,"payment":payment,"ledger":w.facts.ledger.duplicate(true),"command_keys":w.facts.keys().filter(func(key:Variant)->bool:return str(key).contains("command")),"restore_exact":checks.initial_restore_exact})
	var ordered:=FileAccess.open(directory+"/ordered-events.ndjson",FileAccess.WRITE)
	var fact_log:=FileAccess.open(directory+"/phase-facts.ndjson",FileAccess.WRITE)
	fact_log.store_line(JSON.stringify(_phase_facts()))
	var partial_restored: bool=false
	var steps: int=0
	var work: int=0
	var stop_reason: String="original_tick7633_limit"
	if checks.initial_restore_exact and checks.original_4046_boundary:
		while w.sim_tick<7633:
			var o: Dictionary=w.facts.maintenance.upgrades[ORDER]
			if o.phase=="completed":stop_reason="completed";break
			checks.no_early_grade=checks.no_early_grade and w.facts.facilities[TARGET].grade==0
			var previous: int=o.remaining_milli
			var tick: TickResult=sim.step();steps+=1
			var es: Array=[]
			for event: SimEvent in tick.facts:es.append(event.to_record())
			ordered.store_line(JSON.stringify({"tick":tick.sim_tick,"events":es}))
			o=w.facts.maintenance.upgrades[ORDER]
			var delta: int=previous-int(o.remaining_milli);work+=delta
			if delta>0:
				var loc: Dictionary=w.facts.actors[WORKER].location
				checks.actual_attendance_for_work=checks.actual_attendance_for_work and loc.kind=="floor" and int(loc.floor_id)==int(o.work_floor) and Vector2(float(loc.cell[0]),float(loc.cell[1])).distance_to(Vector2(float(o.work_cell[0]),float(o.work_cell[1])))<0.001
			checks.payment_not_repeated=checks.payment_not_repeated and w.facts.ledger.entries.get(ORDER+":upgrade_material",{})==payment and o.hospital_paid==420
			fact_log.store_line(JSON.stringify(_phase_facts()))
			if not partial_restored and delta>0 and o.remaining_milli>0:
				checks.partial_restore_exact=_restore("actual-paid-partial")
				w=sim.world;partial_restored=true
				_json("partial-restore.json",{"tick":w.sim_tick,"remaining_milli":w.facts.maintenance.upgrades[ORDER].remaining_milli,"exact":checks.partial_restore_exact,"cold_restore_during_functional_branch":true})
				if not checks.partial_restore_exact:stop_reason="restore_mismatch";break
			if not checks.actual_attendance_for_work or not checks.payment_not_repeated or not checks.no_early_grade or delta<0:
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
