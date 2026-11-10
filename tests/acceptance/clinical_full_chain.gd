extends "res://tests/acceptance/clinical_fixtures.gd"

# Shared, freshly generated lawful wait-surgery input. No gathered-team,
# last-work-tick or completed-care boundary substitutes any operation below.
func run_selected(tree: SceneTree, selected: Array) -> Dictionary:
	_content=HospitalContent.new()
	_cache=preload("res://tests/acceptance/checkpoints.gd").new(_content,"res://tests/acceptance/clinical_fixtures.gd",weakref(self))
	for mode: String in selected:
		if not mode in ["LIVE","RESTORE"]: return {"ok":false,"error":"Unknown selector: "+mode}
	var setup_started: int=Time.get_ticks_msec()
	var ready: bool=await _ensure_boundary(tree,"surgery_queue")
	var setup_ms: int=Time.get_ticks_msec()-setup_started
	if not ready:
		_dispose_simulations()
		return {"ok":false,"fixture_failures":_fixture_failures}
	var source: Dictionary=_snapshots.surgery_queue.duplicate(true)
	var results: Array=[]
	var okay: bool=true
	for mode: String in selected:
		var started: int=Time.get_ticks_msec()
		var row: Dictionary=await _continue_chain(tree,mode)
		row.body_ms=Time.get_ticks_msec()-started
		row.source_unchanged=_snapshots.surgery_queue==source
		row.ok=row.ok and row.source_unchanged
		results.append(row);okay=okay and row.ok
	_dispose_simulations()
	return {"ok":okay,"cases":results,"setup_ms":setup_ms,"fixtures":_cache.observations,"scope":"Full real team gathering, surgery, wake, convoy, recovery, care, round and departure from a lawful wait-surgery input. Earlier GP/consult are real; surgical resources are lawful boundary input."}

func _continue_chain(tree: SceneTree, mode: String) -> Dictionary:
	var c: Dictionary=_copy("surgery_queue")
	_seed_stream(c.world,"treatment",true,true,9600,9800)
	var initial: Dictionary={"validation":c.world.validate(_content),"tick":c.world.sim_tick,"phase":_visit(c).phase,"no_attempt":c.world.facts.attempts.is_empty(),"selection":c.plan_selection}
	var errors: Array=[]
	var phases: Array=[]
	var previous_phase: String=""
	var work: Dictionary={"surgery":0,"wake":0,"care":0,"round":0}
	var starts: Dictionary={}
	var recovery: int=0
	var restore: Dictionary={}
	var bedside: Dictionary={"care":false,"round":false}
	var original_escort: Dictionary={}
	var escort_stationary: bool=true
	var local_seen: bool=false
	var finished: bool=false
	for i: int in 6000:
		var before_sessions: Dictionary=c.world.facts.sessions.duplicate(true)
		var before_stay: Dictionary=_stay(c).duplicate(true)
		var before_staff: Dictionary={}
		for id: String in ["clin_cover","clin_round"]: before_staff[id]=c.world.facts.staff[id].duplicate(true)
		_tick(c)
		var invalid: String=c.world.validate(_content)
		if not invalid.is_empty(): errors.append({"tick":c.world.sim_tick,"validation":invalid});break
		var overlap: Array=preload("res://tests/acceptance/clinical_ward_release.gd").new()._overlap(c)
		if not overlap.is_empty(): errors.append({"tick":c.world.sim_tick,"overlap":overlap});break
		var phase: String=str(_visit(c).phase)
		if phase!=previous_phase:
			phases.append({"tick":c.world.sim_tick,"phase":phase});previous_phase=phase
		for kind: String in work:
			var old: Dictionary={}
			for session: Dictionary in before_sessions.values():
				if session.kind==kind and session.visit_id==c.visit_id: old=session;break
			var current: Dictionary=_session(c,kind)
			if not old.is_empty():
				work[kind]=int(work[kind])+1
				if not current.is_empty() and int(current.remaining_ticks)!=int(old.remaining_ticks)-1: errors.append({"kind":kind,"bad_work_decrement":c.world.sim_tick})
				if current.is_empty() and int(old.remaining_ticks)!=1: errors.append({"kind":kind,"early_finish":old.remaining_ticks})
			elif not current.is_empty():
				# Wake is created by completion during advance, after this
				# tick's session list was sealed; its first work is next tick.
				var first_work: int=int(current.total_ticks)-int(current.remaining_ticks)
				work[kind]=int(work[kind])+first_work
				starts[kind]={"tick":c.world.sim_tick-1,"total":current.total_ticks,"remaining":current.remaining_ticks,"staff_ids":current.staff_ids.duplicate()}
				if first_work not in [0,1]: errors.append({"kind":kind,"invalid_start_work":first_work})
				if kind in ["care","round"]:
					var id: String=str(current.staff_ids[0])
					starts[kind].input=before_staff[id]
					var bed: Dictionary=c.sim.space.facility_layout(c.world,current.facility_id)
					bedside[kind]=c.sim.space.at(c.world,id,int(bed.floor_id),bed.operator_cells[0 if kind=="care" else 1])
		var stay: Dictionary=_stay(c)
		if not before_stay.is_empty() and not stay.is_empty(): recovery+=maxi(0,int(before_stay.remaining_ticks)-int(stay.remaining_ticks))
		elif before_stay.is_empty() and not stay.is_empty(): recovery+=1800-int(stay.remaining_ticks)
		# Once the escort has really finished parking, it must not be pushed
		# aside to make the care nurse pass. Observe, do not pin its position.
		if phase=="recovery" and original_escort.is_empty() and not c.world.facts.staff.clin_or_nurse.has("clinical_release") and not c.world.facts.moves.has("clin_or_nurse"):
			original_escort=c.world.facts.actors.clin_or_nurse.duplicate(true)
		if not original_escort.is_empty(): escort_stationary=escort_stationary and c.world.facts.actors.clin_or_nurse==original_escort
		var move: Dictionary=c.world.facts.moves.get("clin_cover",{})
		var local: Dictionary=move.get("local_move",{})
		if phase=="recovery" and not local.is_empty(): local_seen=true
		if mode=="RESTORE" and restore.is_empty() and phase=="recovery" and not local.is_empty() and not local.get("retreat",false):
			restore=_roundtrip(c)
			if not restore.ok: errors.append({"restore":restore});break
		if phase=="departed": finished=true;break
		if not errors.is_empty(): break
		if i%100==99: await tree.process_frame
	var round_input: Dictionary=starts.get("round",{}).get("input",{})
	var expected_round: int=ceili(100.0*(1.0+0.003*float(round_input.get("fatigue",0.0)))/(1.0+0.05*(int(round_input.get("abilities",{}).get("treatment",1))-1)))
	var checks: Dictionary={"legal_input":initial.validation.is_empty() and initial.phase=="wait_surgery" and initial.no_attempt and initial.selection.accepted,"all_real_steps_valid":errors.is_empty(),"actual_departure":finished,"one_attempt":_visit(c).attempt_ids.size()==1,"full_surgery":work.surgery==1200,"full_wake":work.wake==150,"full_recovery":recovery==1800,"full_care":work.care==80 and bedside.care,"qualified_full_round":work.round==expected_round and bedside.round and int(round_input.get("abilities",{}).get("diagnosis",0))>=2,"one_service_each":true,"sole_supply_issue":_units_used(c)==8,"one_settlement":_income(c,"ward")==60 and _income(c,"cure")==360 and _income(c)==505,"local_avoidance_observed":local_seen,"stationary_escort_preserved":not original_escort.is_empty() and escort_stationary,"cold_restore":mode!="RESTORE" or restore.get("ok",false)}
	for kind: String in work: checks.one_service_each=checks.one_service_each and c.started.get(kind,0)==1
	var okay: bool=true
	for value: bool in checks.values(): okay=okay and value
	return {"case":mode,"ok":okay,"checks":checks,"initial":initial,"phases":phases,"work_ticks":work,"recovery_ticks":recovery,"round_expected_ticks":expected_round,"restore":restore,"errors":errors,"final_tick":c.world.sim_tick,"failure_world":_failure_world("CLIN-FULL-"+mode,c.world) if not okay else {}}
