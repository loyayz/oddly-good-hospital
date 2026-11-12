extends SceneTree
const TARGET: String="bench_room_2_15_0"
var content: HospitalContent
var sim: HospitalSimulation
var directory: String
var serial: int=0
var commands: Array=[]
var events: Array=[]
var checks: Dictionary={}
var trace: Array=[]
var watched_session: String=""
var watched_attempt: String=""
func _initialize() -> void:call_deferred("_run")
func _json(name: String,value: Variant) -> void:
	var f:=FileAccess.open(directory+"/"+name,FileAccess.WRITE);f.store_string(JSON.stringify(value,"\t"));f.close()
func _save(name: String) -> void:
	var f:=FileAccess.open(directory+"/"+name+".bin",FileAccess.WRITE);f.store_var(sim.world.freeze(),false);f.close()
func _record(kind: String,payload: Dictionary) -> Dictionary:
	serial+=1
	return {"id":"upgrade-handoff-%d"%serial,"hospital_id":sim.world.hospital_id,"expected_revision":-1,"kind":kind,"typed_payload":payload,"loading_session_id":"upgrade-handoff"}
func _batch(records: Array) -> Array:
	for record: Dictionary in records:sim.enqueue(record)
	var results: Array=sim.drain_commands()
	for i: int in records.size():commands.append({"tick":sim.world.sim_tick,"command":records[i],"result":results[i].to_record()})
	_json("commands.json",commands)
	return results
func _promise_equal(actual: Dictionary, promised: Dictionary) -> bool:
	var expected: Dictionary=promised.duplicate(true)
	# Existing one-time staff experience settlement receipt is not a quoted
	# clinical promise; no other field or value may differ.
	if actual.has("plan_experience_awarded") and not expected.has("plan_experience_awarded"):
		if actual.plan_experience_awarded!=true:return false
		expected.plan_experience_awarded=true
	return actual==expected
func _clinical_state() -> Dictionary:
	if watched_session.is_empty():return {}
	var world: WorldState=sim.world
	var record: Dictionary=world.facts.sessions.get(watched_session,{})
	if not record.is_empty():return {"kind":"working","attempt_id":record.get("attempt_id",""),"remaining":record.remaining_ticks,"facility":record.facility_id}
	record=world.facts.clinical_suspensions.get(watched_session,{})
	if not record.is_empty():return {"kind":"paused","attempt_id":record.get("attempt_id",""),"remaining":record.remaining_ticks,"facility":record.facility_id}
	return {"kind":"finished"}
func _step(phase: String) -> void:
	var before: Dictionary=_clinical_state()
	var result: TickResult=sim.step()
	for event: SimEvent in result.facts:events.append(event.to_record())
	var after: Dictionary=_clinical_state()
	if not watched_session.is_empty():
		checks.paused_remaining_frozen=checks.get("paused_remaining_frozen",true) and (before.get("remaining")==after.get("remaining") if before.kind=="paused" and after.kind=="paused" else true)
		checks.original_session_identity=checks.get("original_session_identity",true) and after.get("attempt_id",watched_attempt)==watched_attempt
		if before.has("remaining") and after.has("remaining"):
			var decrease: int=int(before.remaining)-int(after.remaining)
			checks.remaining_only_real_work=checks.get("remaining_only_real_work",true) and decrease>=0 and decrease<=1 and (decrease==0 or before.kind=="working" or after.kind=="working")
	trace.append({"tick":sim.world.sim_tick,"phase":phase,"actors":sim.world.present_actor_count(),"clinical_before":before,"clinical_after":after})
func _restore(name: String) -> bool:
	_save(name)
	var frozen: Dictionary=sim.world.freeze()
	sim.dispose();sim=HospitalSimulation.new(WorldState.new(frozen),content)
	return sim.world.freeze()==frozen
func _inspect() -> Dictionary:
	var sessions: Array=[]
	for session: Dictionary in sim.world.facts.sessions.values():
		if session.get("facility_id","")==TARGET:sessions.append(session)
	return {"tick":sim.world.sim_tick,"validation":sim.world.validate(content),"target":sim.world.facts.facilities.get(TARGET,{}),"sessions":sessions,"adaptation":sim.world.facts.adaptations.get(TARGET,{}),"actors":sim.world.present_actor_count(),"upgrade_preview":sim.services.maintenance.upgrade_quote(sim.world,{"facility_id":TARGET,"target_level":1}),"original_visit":sim.world.facts.visits.get("bench_visit_0109",{}),"original_attempt":sim.world.facts.attempts.get("attempt_00000206",{}),"patient":sim.world.facts.actors.get("bench_patient_0109",{}),"patient_move":sim.world.facts.moves.get("bench_patient_0109",{}),"suspensions":sim.world.facts.clinical_suspensions,"supported_actors":sim.world.facts.actors.values().filter(func(actor:Dictionary)->bool:return actor.get("support_facility_id","")==TARGET),"upgrade_orders":sim.world.facts.maintenance.upgrades,"worker226_move":sim.world.facts.moves.get("maintenance_contractor_00000226",{}),"worker226_neighbors":sim.world.facts.actors.values().filter(func(actor:Dictionary)->bool:return actor.location.kind=="floor" and int(actor.location.floor_id)==1 and Vector2(float(actor.location.cell[0]),float(actor.location.cell[1])).distance_to(Vector2(83,43.6))<5),"lift":sim.world.facts.connectors.get("benchmark_lift",{})}
func _settlement() -> Dictionary:
	var world: WorldState=sim.world
	var observed: Array=[]
	for i: int in 350:
		var before: Dictionary={}
		for session: Dictionary in world.facts.sessions.values():
			if session.kind=="outpatient":
				var visit: Dictionary=world.facts.visits[session.visit_id]
				before[visit.id]={"receipt":visit.get("result_receipt",{}).duplicate(true),"support":world.facts.actors[visit.actor_id].get("support_facility_id",""),"posture":world.facts.actors[visit.actor_id].posture,"attempt":world.facts.attempts[session.attempt_id].duplicate(true)}
		_step("real_settlement")
		for visit_id: String in before:
			var visit: Dictionary=world.facts.visits[visit_id]
			if visit.get("result_receipt",{})==before[visit_id].receipt:continue
			var actor: Dictionary=world.facts.actors[visit.actor_id]
			observed.append({"visit":visit_id,"result":visit.final_result,"previous_posture":before[visit_id].posture,"posture":actor.posture,"reference_cleared":not actor.has("support_facility_id"),"attempt_unchanged":_promise_equal(world.facts.attempts[before[visit_id].attempt.id],before[visit_id].attempt),"tick":world.sim_tick})
			if visit_id=="bench_visit_0109":
				_save("settled-at-post")
				var blocked: String=sim.services.building._busy(world,TARGET)
				checks.actual_seated_settlement=before[visit_id].posture=="seated" and actor.posture=="standing" and not actor.has("support_facility_id")
				checks.still_physically_protected=not blocked.is_empty() and world.facts.adaptations.has(TARGET)
				checks.settlement_promise_unchanged=_promise_equal(world.facts.attempts[before[visit_id].attempt.id],before[visit_id].attempt)
				checks.valid_settlement=world.validate(content).is_empty()
				return {"observed":observed,"blocked_reason":blocked,"actor":actor,"adaptation":world.facts.adaptations.get(TARGET,{})}
	return {"reason":"target did not settle within bound","observed":observed}
func _compatibility(post_path: String) -> Dictionary:
	var world: WorldState=sim.world
	var visit: Dictionary=world.facts.visits.bench_visit_0085
	var actor: Dictionary=world.facts.actors[visit.actor_id]
	var original: Dictionary=world.freeze()
	var expected: Dictionary=original.duplicate(true);expected.actors[actor.id].erase("support_facility_id")
	checks.old_visit_in_active_loop=visit.id in world.active_visit_ids()
	var matching: Dictionary={"visit":visit.id,"phase":visit.phase,"receipt":visit.result_receipt.duplicate(true),"attempt":world.facts.attempts[visit.result_receipt.attempt_id].duplicate(true),"actor":actor.duplicate(true)}
	sim.clinic._release_completed_seated_support(world,visit)
	checks.exact_compatibility_change=world.freeze()==expected
	sim.clinic._release_completed_seated_support(world,visit)
	checks.compatibility_idempotent=world.freeze()==expected
	var negatives: Array=[]
	for id: String in ["bench_visit_0109","bench_visit_0004"]:
		var negative: Dictionary=world.facts.visits[id]
		var before: Dictionary=world.freeze()
		sim.clinic._release_completed_seated_support(world,negative)
		negatives.append({"visit":id,"posture":world.facts.actors[negative.actor_id].posture,"unchanged":world.freeze()==before})
	checks.real_seated_lying_preserved=negatives.all(func(row:Dictionary)->bool:return row.unchanged)
	if not post_path.is_empty():
		var f:=FileAccess.open(post_path,FileAccess.READ);var post: Dictionary=f.get_var(false);f.close()
		var restored:=HospitalSimulation.new(WorldState.new(post),content)
		var v: Dictionary=restored.world.facts.visits.bench_visit_0109
		var before: Dictionary=restored.world.freeze()
		restored.clinic._release_completed_seated_support(restored.world,v)
		checks.real_standing_at_post_preserved=restored.world.facts.actors[v.actor_id].posture=="standing" and restored.world.facts.actors[v.actor_id].has("support_facility_id") and restored.world.facts.adaptations.has(TARGET) and restored.world.freeze()==before and restored.world.validate(content).is_empty()
		restored.dispose()
	return {"matching_history":matching,"negative_real_states":negatives}

func _upgrade() -> Dictionary:
	var world: WorldState=sim.world
	var item: Dictionary=world.facts.facilities[TARGET]
	var session: Dictionary={}
	for row: Dictionary in world.facts.sessions.values():
		if row.get("facility_id","")==TARGET:session=row.duplicate(true)
	checks.legal_active_M09=world.validate(content).is_empty() and item.definition_id=="M09" and not session.is_empty() and world.facts.adaptations.has(TARGET)
	if not checks.legal_active_M09:return {"reason":"active M09 boundary missing"}
	var attempt_id: String=session.attempt_id
	watched_session=session.id;watched_attempt=attempt_id
	var promised: Dictionary=world.facts.attempts[attempt_id].duplicate(true)
	var visit_id: String=promised.visit_id
	var issue: Dictionary=world.facts.inventory.issues[attempt_id].duplicate(true)
	var initial_cash: int=HospitalLedger.balance(world)
	var initial_grade: int=item.grade
	var initial_orders: Dictionary=world.facts.maintenance.upgrades.duplicate(true)
	_save("preWorld")
	var rejected: Array=_batch([_record("machine_upgrade",{"facility_id":TARGET,"target_level":1})])
	checks.direct_rejection_atomic=not rejected[0].accepted and HospitalLedger.balance(world)==initial_cash and item.grade==initial_grade and world.facts.maintenance.upgrades==initial_orders and _promise_equal(world.facts.attempts[attempt_id],promised) and world.facts.inventory.issues[attempt_id]==issue
	if not checks.direct_rejection_atomic:return {"reason":"original rejection/atomicity not established"}
	var prepare: Array=_batch([_record("remodel_prepare",{"commands":[{"kind":"build_move","target_id":TARGET,"floor_id":item.floor_id,"cell":item.cell.duplicate()}],"safe_transfer":true})])
	if not prepare[0].accepted:return {"reason":"prepare rejected"}
	var arrangement: String=prepare[0].changed_ids[0]
	checks.preparation_cold_restore=_restore("preparing")
	world=sim.world
	var quote: Dictionary={}
	var prepare_steps: int=0
	for i: int in 600:
		quote=sim.services.remodel.preview(world,arrangement)
		if quote.get("ok",false):break
		_step("safe_transfer");prepare_steps+=1
	_save("safe-transfer-boundary")
	var suspended: Dictionary=world.facts.clinical_suspensions.get(session.id,{})
	checks.frozen_safe_release=quote.get("ok",false) and not world.facts.adaptations.has(TARGET) and _promise_equal(world.facts.attempts[attempt_id],promised) and world.facts.inventory.issues[attempt_id]==issue
	checks.compatibility_reached_by_dispatch=not world.facts.actors.bench_patient_0085.has("support_facility_id")
	if not checks.frozen_safe_release:return {"reason":"safe release not reached","prepare_steps":prepare_steps,"quote_reason":quote.get("reason",""),"suspended":suspended,"original_session":session,"remodel":world.facts.remodels[arrangement]}
	var cash: int=HospitalLedger.balance(world)
	var applied: Array=_batch([_record("remodel_apply",{"order_id":arrangement,"quote":{"price":quote.price,"refund":quote.refund,"layout":quote.layout}}),_record("machine_upgrade",{"facility_id":TARGET,"target_level":1})])
	checks.same_command_phase=applied.size()==2 and applied[0].accepted and applied[1].accepted
	if not checks.same_command_phase:return {"reason":"apply/upgrade rejected","quote":{ "price":quote.price,"refund":quote.refund,"layout":quote.layout}}
	var order_id: String=applied[1].changed_ids[0]
	var order: Dictionary=world.facts.maintenance.upgrades[order_id]
	checks.one_420_payment=HospitalLedger.balance(world)==cash-420 and order.stages.size()==1 and order.stages[0].price==420 and order.remaining_milli==30000
	checks.zero_before_arrival=true;checks.old_promise_kept=true;checks.grade_only_on_completion=true;checks.suspended_work_kept=true
	var partial_restored: bool=false
	var work_sum: int=0
	var upgrade_steps: int=0
	var first_work_tick: int=-1
	for i: int in 2400:
		order=world.facts.maintenance.upgrades[order_id]
		if order.phase=="completed":break
		checks.grade_only_on_completion=checks.grade_only_on_completion and world.facts.facilities[TARGET].grade==0
		var held: Dictionary=world.facts.clinical_suspensions.get(session.id,{})
		if not held.is_empty():checks.suspended_work_kept=checks.suspended_work_kept and held.get("attempt_id","")==attempt_id and int(held.get("remaining_ticks",-1))<=int(session.remaining_ticks)
		var before_work: int=order.remaining_milli
		_step("upgrade");upgrade_steps+=1
		order=world.facts.maintenance.upgrades[order_id]
		var delta: int=before_work-int(order.remaining_milli)
		work_sum+=delta
		if delta>0 and first_work_tick<0:first_work_tick=world.sim_tick
		if delta>0 and order.phase!="completed":checks.zero_before_arrival=checks.zero_before_arrival and sim.space.at(world,order.worker_id,int(order.work_floor),order.work_cell) and not world.facts.moves.has(order.worker_id)
		checks.old_promise_kept=checks.old_promise_kept and _promise_equal(world.facts.attempts[attempt_id],promised) and world.facts.inventory.issues[attempt_id]==issue
		trace[-1].remaining_milli=order.remaining_milli;trace[-1].order_phase=order.phase;trace[-1].worker_id=order.worker_id;trace[-1].reason=order.get("reason","")
		if not partial_restored and order.remaining_milli<=18000 and order.remaining_milli>0:
			checks.partial_cold_restore=_restore("partial-paid-upgrade");world=sim.world;partial_restored=true
		if i%100==0:_json("progress.json",{"phase":"upgrade","steps":upgrade_steps,"tick":world.sim_tick,"order":order,"checks":checks})
	order=world.facts.maintenance.upgrades[order_id]
	var receipt: Dictionary=world.facts.maintenance.receipts.get(order_id+":1:upgrade_completed",{})
	checks.completed_real_30000=order.phase=="completed" and work_sum==30000 and world.facts.facilities[TARGET].grade==1 and world.facts.facilities[TARGET].upgrade_level==1 and receipt.get("standard_work_milli",0)==30000 and not receipt.get("worker_id","").is_empty()
	checks.existing_upgrade_coverage_1ms=work_sum>=1
	checks.paid_partial_restore_exercised=partial_restored
	_save("upgrade-end")
	if not checks.completed_real_30000:return {"reason":"bounded upgrade did not complete","order":order,"prepare_steps":prepare_steps,"upgrade_steps":upgrade_steps,"work_sum":work_sum,"receipt":receipt,"worker":world.facts.actors.get(order.worker_id,{})}
	var continuation_steps: int=0
	var resumed: bool=world.facts.visits[visit_id].get("result_receipt",{}).get("attempt_id","")==attempt_id
	var next_attempt: Dictionary={}
	for i: int in 1600:
		for current: Dictionary in world.facts.sessions.values():
			if current.get("attempt_id","")==attempt_id:resumed=true
		for current: Dictionary in world.facts.attempts.values():
			if current.id!=attempt_id and current.get("facility_id","")==TARGET and int(current.get("start_tick",0))>first_work_tick:next_attempt=current.duplicate(true)
		if resumed and not next_attempt.is_empty():break
		_step("clinical_continuation");continuation_steps+=1
	checks.original_promise_and_issue_final=_promise_equal(world.facts.attempts[attempt_id],promised) and world.facts.inventory.issues[attempt_id]==issue
	checks.original_case_resumed=resumed
	checks.new_case_uses_upgrade=not next_attempt.is_empty() and float(next_attempt.get("effective_level",0))>0.0
	checks.unique_completion_receipt=world.facts.maintenance.receipts.has(order_id+":1:upgrade_completed") and world.facts.facilities[TARGET].completed_upgrade_paid_cost==420
	checks.final_valid=world.validate(content).is_empty()
	return {"prepare_steps":prepare_steps,"upgrade_steps":upgrade_steps,"continuation_steps":continuation_steps,"work_sum":work_sum,"first_work_tick":first_work_tick,"order":order,"receipt":receipt,"original_attempt":promised,"next_attempt":next_attempt,"original_visit":world.facts.visits[visit_id]}

func _audit_settlement(source: String) -> Dictionary:
	var f:=FileAccess.open(source,FileAccess.READ);var raw: Dictionary=f.get_var(false);f.close()
	var before: Dictionary=raw.before
	var rows: Array=[]
	for id: String in ["bench_visit_0065","bench_visit_0063","bench_visit_0109"]:
		var visit: Dictionary=sim.world.facts.visits[id]
		var actor: Dictionary=sim.world.facts.actors[visit.actor_id]
		var aid: String=visit.result_receipt.attempt_id
		var a: Dictionary=sim.world.facts.attempts[aid]
		var p: Dictionary=before.attempts[aid]
		var changes: Array=[]
		for key: String in a:
			if a[key]!=p.get(key):changes.append(key)
		rows.append({"visit":id,"result":visit.final_result,"changed_attempt_fields":changes,"frozen_promise_equal":_promise_equal(a,p),"support_cleared":not actor.has("support_facility_id")})
	checks.recorded_success_retry_settlements=rows.all(func(row:Dictionary)->bool:return row.frozen_promise_equal and row.support_cleared)
	checks.still_occupied=sim.world.facts.adaptations.has(TARGET) and not sim.services.building._busy(sim.world,TARGET).is_empty()
	return {"rows":rows,"uses_saved_real_step_result":true}

func _observation_facts() -> Dictionary:
	var world: WorldState=sim.world
	var nearby: Array=[]
	for actor: Dictionary in world.facts.actors.values():
		var loc: Dictionary=actor.location
		if loc.kind=="floor" and int(loc.floor_id) in [1,3,4] and absf(float(loc.cell[0])-86)<8 and absf(float(loc.cell[1])-44)<8:nearby.append(actor.duplicate(true))
	var tickets: Array=[]
	for move: Dictionary in world.facts.moves.values():
		if move.get("transit_ticket",{}).get("connector_id","")=="benchmark_lift":tickets.append({"actor_id":move.actor_id,"ticket":move.transit_ticket.duplicate(true)})
	return {"tick":world.sim_tick,"worker":world.facts.actors.get("maintenance_contractor_00000226",{}).duplicate(true),"worker_move":world.facts.moves.get("maintenance_contractor_00000226",{}).duplicate(true),"lift":world.facts.connectors.benchmark_lift.duplicate(true),"patient0003":world.facts.actors.bench_patient_0003.duplicate(true),"patient0003_move":world.facts.moves.get("bench_patient_0003",{}).duplicate(true),"nearby_floor_bodies":nearby,"lift_tickets":tickets}
func _observe_eight(input_facts: Dictionary) -> void:
	var unchanged: bool=sim.world.freeze()==input_facts
	_save("cold-start")
	var rows: Array=[_observation_facts()]
	var ordered: Array=[]
	for i: int in 8:
		var result: TickResult=sim.step()
		var tick_events: Array=[]
		for event: SimEvent in result.facts:tick_events.append(event.to_record())
		ordered.append({"tick":result.sim_tick,"events":tick_events})
		rows.append(_observation_facts())
	_save("cold-final")
	_json("observations.json",rows);_json("ordered-events.json",ordered)
	_json("result.json",{"ok":unchanged and rows.size()==9,"cold_restore_identity":unchanged,"step_count":8,"tick_seconds":WorldState.TICK_SECONDS,"start_tick":rows[0].tick,"end_tick":rows[-1].tick,"scope":"cold diagnostic branch; direct fact snapshots only; no commands or extra business/navigation/safety queries"})
	sim.dispose();quit(0 if unchanged else 1)

func _run() -> void:
	var args:=OS.get_cmdline_user_args();directory=args[1];content=HospitalContent.new()
	var f:=FileAccess.open(args[2],FileAccess.READ);var raw: Dictionary=f.get_var(false);f.close()
	var facts: Dictionary=raw.get("before",raw.get("facts",raw))
	sim=HospitalSimulation.new(WorldState.new(facts),content)
	if args[0]=="observe8":
		_observe_eight(facts);return
	_json("input-inspection.json",_inspect())
	if args[0]=="inspect":
		_save("input");sim.dispose();quit(0);return
	checks.legal_input=sim.world.validate(content).is_empty()
	checks.restore_input_identity=sim.world.freeze()==facts
	var result: Dictionary
	if args[0]=="settle":result=_settlement()
	elif args[0]=="audit_settle":result=_audit_settlement(args[3])
	elif args[0]=="compat":result=_compatibility(args[3] if args.size()>3 else "")
	else:result=_upgrade()
	_save("final")
	_json("events.json",events);_json("trace.json",trace)
	var ok: bool=checks.values().all(func(value:Variant)->bool:return value==true) and (checks.get("completed_real_30000",false) and checks.get("new_case_uses_upgrade",false) if args[0]=="upgrade" else true)
	_json("result.json",{"ok":ok,"checks":checks,"details":result})
	sim.dispose();quit(0 if ok else 1)
