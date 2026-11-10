extends "res://tests/acceptance/clinical_fixtures.gd"

# Named bedside-service input, independently copied from the real CLIN-20
# ward_entered handoff. No completed care/round or pre-completed repair input.
var report: Dictionary = {"checks":{},"observations":{}}
var evidence: String

func run_selected(tree: SceneTree, directory: String, selected: Array) -> Dictionary:
	evidence = directory
	if not ("CLINICAL" in selected or "REPAIR" in selected):
		report.checks.explicit_case_selection=false
		report.ok=false
		return report
	_content = HospitalContent.new()
	_cache = preload("res://tests/acceptance/checkpoints.gd").new(_content,"res://tests/acceptance/clinical_fixtures.gd",weakref(self))
	var path: String = directory.path_join("bed_service_ward_entered.bin")
	var manifest_path: String=directory.path_join("bed_service_ward_entered_manifest.json")
	var basis: Dictionary=_source_basis()
	var manifest: Variant=JSON.parse_string(FileAccess.get_file_as_string(manifest_path)) if FileAccess.file_exists(manifest_path) else {}
	var reusable: bool=not "REBUILD" in selected and manifest is Dictionary and manifest.get("basis_sha256","")==JSON.stringify(basis).sha256_text() and FileAccess.file_exists(path) and manifest.get("sha256","")==FileAccess.get_sha256(path)
	var setup_started: int=Time.get_ticks_msec()
	if reusable:
		var input: Dictionary = FileAccess.open(path,FileAccess.READ).get_var()
		_snapshots.ward_entered = input
		report.observations.source = {"kind":"frozen_real_ward_entered","path":path,"sha256":FileAccess.get_sha256(path),"tick":input.facts.sim_tick,"validation":WorldState.new(input.facts.duplicate(true)).validate(_content)}
	else:
		if not await _ensure_boundary(tree,"ward_entered"):
			report.checks.real_ward_entered=false
			report.observations.prerequisites=_fixture_failures
			return report
		if _source_basis()!=basis:
			report.checks.source_unchanged=false
			report.observations.blocker="Production input changed while building ward_entered; frozen input was not published."
			_dispose_simulations()
			return report
		FileAccess.open(path,FileAccess.WRITE).store_var(_snapshots.ward_entered)
		FileAccess.open(manifest_path,FileAccess.WRITE).store_string(JSON.stringify({"basis":basis,"basis_sha256":JSON.stringify(basis).sha256_text(),"sha256":FileAccess.get_sha256(path),"boundary":"ward_entered","generated_by":"clinical_fixtures.gd _ensure_boundary","created_utc":Time.get_datetime_string_from_system(true)},"\t"))
		report.observations.source = {"kind":"built_real_ward_entered","path":path,"sha256":FileAccess.get_sha256(path),"tick":_snapshots.ward_entered.facts.sim_tick,"fixtures":_cache.observations}
	report.observations.source.setup_ms=Time.get_ticks_msec()-setup_started
	report.observations.source.basis=basis
	report.checks.real_ward_entered_valid=WorldState.new(_snapshots.ward_entered.facts.duplicate(true)).validate(_content).is_empty()
	FileAccess.open(directory.path_join("bed_service_source.json"),FileAccess.WRITE).store_string(JSON.stringify(_snapshots.ward_entered,"\t"))
	if "CLINICAL" in selected: await _clinical(tree)
	if "REPAIR" in selected: await _repair(tree)
	_dispose_simulations()
	report.checks.source_unchanged=_source_basis()==basis
	var ok: bool = not report.checks.is_empty()
	for value: bool in report.checks.values(): ok=ok and value
	report.ok=ok
	return report

func _source_files(path: String, output: Dictionary) -> void:
	var dir: DirAccess=DirAccess.open(path)
	if dir==null:return
	var names: PackedStringArray=dir.get_files()
	names.sort()
	for name: String in names:
		if name.ends_with(".gd"):output[path.path_join(name)]=FileAccess.get_sha256(path.path_join(name))
	var children: PackedStringArray=dir.get_directories()
	children.sort()
	for child: String in children:
		if child!="ui":_source_files(path.path_join(child),output)

func _source_basis() -> Dictionary:
	# The real prefix uses the complete production simulation phases, so its
	# identity includes game rules (not UI), content, producer and runtime.
	var sources: Dictionary={}
	_source_files("res://game",sources)
	return {"runtime":Engine.get_version_info().string,"runtime_sha256":FileAccess.get_sha256(OS.get_executable_path()),"content":_content.content_fingerprint,"producer":_checkpoint_dependencies("ward_entered"),"production_sources":sources}

func _input() -> Dictionary:
	var c: Dictionary = _copy("ward_entered")
	c.clinical_scenario=true
	var w: WorldState=c.world
	# Explicit legal boundary inputs: the covering nurse and round doctor are
	# available at non-work cells inside the ward. The escort has completed
	# the preceding release and stands clear. These are inputs, not a proof
	# of the known blocked generated escort-to-care prefix.
	var positions: Dictionary={"clin_cover":[45,69],"clin_round":[49,65],"clin_or_nurse":[52,72]}
	for id: String in positions:
		w.facts.moves.erase(id)
		w.facts.staff[id].erase("clinical_release")
		w.facts.actors[id].location={"kind":"floor","floor_id":1,"cell":positions[id].duplicate(),"height_m":0.0}
		w.facts.actors[id].posture="standing"
		w.facts.staff[id].on_shift=true
		w.facts.staff[id].base_prepared=true
		w.facts.staff[id].base_task={}
		w.facts.staff[id].energy=100.0
		w.facts.staff[id].fatigue=0.0
		w.facts.staff[id].block_new_work=false
		w.facts.staff[id].schedule=_schedule("round" if id=="clin_round" else "work")
	# Recovery is a declared unfinished boundary, not timed evidence for the
	# prior surgery/recovery. Both bedside services run their entire duration.
	_stay(c).remaining_ticks=200
	_stay(c).work_credit_milli=0
	_stay(c).last_progress_tick=w.sim_tick
	_visit(c).last_progress_tick=w.sim_tick
	w.touch()
	c.sim._ensure_services()
	c.audit={"steps":0,"maximum_step":{},"body_overlaps":[],"work_errors":[],"care_decrements":0,"round_decrements":0,"service_inputs":{}}
	c.input={"positions":positions,"nurse":"clin_cover","doctor":"clin_round","availability":"on_shift, prepared, energy 100, fatigue 0, work/round schedule","recovery_remaining_ticks":200,"care_completed":_stay(c).care_completed,"validation":w.validate(_content),"unverified_prefix":"Generated ward_care blocks at tick 4452 behind escort in baseline and candidate; this independent input does not pass CLIN-24/25/27/37."}
	return c

func _tick(c: Dictionary) -> void:
	if not c.has("audit"):
		super._tick(c)
		return
	var prior: Dictionary={}
	var prior_staff: Dictionary={}
	for id: String in ["clin_cover","clin_round"]:
		prior_staff[id]=c.world.facts.staff[id].duplicate(true)
	var sessions: Dictionary=c.world.facts.sessions.duplicate(true)
	for id: String in c.world.facts.actors:
		prior[id]=c.world.facts.actors[id].location.duplicate(true)
	super._tick(c)
	c.audit.steps+=1
	for kind: String in ["care","round"]:
		for session: Dictionary in c.world.facts.sessions.values():
			if session.kind!=kind:continue
			var old: Dictionary=sessions.get(session.id,{})
			if old.is_empty():
				var staff: Dictionary=prior_staff[session.staff_ids[0]]
				c.audit.service_inputs[kind]={"fatigue":staff.fatigue,"care":staff.abilities.care,"treatment":staff.abilities.treatment,"species":c.world.facts.actors[staff.id].species_id}
			var expected: int=int(old.remaining_ticks if not old.is_empty() else session.total_ticks)-1
			if int(session.remaining_ticks)!=expected:c.audit.work_errors.append({"kind":kind,"tick":c.world.sim_tick,"expected":expected,"actual":session.remaining_ticks})
			c.audit[kind+"_decrements"]+=1
		for old: Dictionary in sessions.values():
			if old.kind==kind and not c.world.facts.sessions.has(old.id):
				if int(old.remaining_ticks)!=1:c.audit.work_errors.append({"kind":kind,"early_finish":old.remaining_ticks})
				c.audit[kind+"_decrements"]+=1
	var actor_ids: Array=c.world.ids("actors")
	for i: int in actor_ids.size():
		var id: String=actor_ids[i]
		var actor: Dictionary=c.world.facts.actors[id]
		if prior.has(id) and prior[id].kind=="floor" and actor.location.kind=="floor" and int(prior[id].floor_id)==int(actor.location.floor_id):
			var distance: float=ConvoyTrail.point(prior[id].cell).distance_to(ConvoyTrail.point(actor.location.cell))
			c.audit.maximum_step[id]=maxf(float(c.audit.maximum_step.get(id,0.0)),distance)
		if actor.location.kind!="floor":continue
		for j: int in range(i+1,actor_ids.size()):
			var other: Dictionary=c.world.facts.actors[actor_ids[j]]
			if other.location.kind=="floor" and int(actor.location.floor_id)==int(other.location.floor_id) and c.sim.space.body_rectangle(actor).intersects(c.sim.space.body_rectangle(other),false):
				if c.audit.body_overlaps.size()<20:c.audit.body_overlaps.append({"tick":c.world.sim_tick,"actors":[id,other.id]})

func _wait(tree: SceneTree,c: Dictionary,condition: Callable,limit: int) -> bool:
	for i: int in limit:
		if condition.call():return true
		_tick(c)
		if i%100==99: await tree.process_frame
	return condition.call()

func _clinical(tree: SceneTree) -> void:
	var c: Dictionary=_input()
	report.observations.clinical_input=c.input
	var bed_id: String=str(_stay(c).bed_id)
	var layout: Dictionary=c.sim.space.facility_layout(c.world,bed_id)
	var initial: Dictionary=_state(c)
	var start: int=c.world.sim_tick
	var ready: bool=await _wait(tree,c,func()->bool:return not _session(c,"care").is_empty(),250)
	var care: Dictionary=_session(c,"care").duplicate(true)
	var at_care: bool=ready and c.sim.space.at(c.world,"clin_cover",int(layout.floor_id),layout.operator_cells[0])
	var completed: bool=ready and await _wait(tree,c,func()->bool:return _stay(c).get("care_completed",false),160)
	var care_end: int=c.world.sim_tick
	var release_initial: Dictionary=c.world.facts.staff.clin_cover.get("clinical_release",{}).duplicate(true)
	var released: bool=completed and await _wait(tree,c,func()->bool:return c.world.facts.staff.clin_cover.get("clinical_release",{}).is_empty() and not c.world.facts.moves.has("clin_cover"),250)
	var nurse_position: Array=c.world.facts.actors.clin_cover.location.cell.duplicate()
	var began_round: bool=released and await _wait(tree,c,func()->bool:return not _session(c,"round").is_empty(),500)
	var rounding: Dictionary=_session(c,"round").duplicate(true)
	var round_start: int=c.world.sim_tick
	var at_round: bool=began_round and c.sim.space.at(c.world,"clin_round",int(layout.floor_id),layout.operator_cells[1])
	var uncharged: bool=_income(c,"ward")==0 and _income(c,"cure")==0
	var finished: bool=began_round and await _wait(tree,c,func()->bool:return _visit(c).get("final_result","")=="cured",250)
	var round_end: int=c.world.sim_tick
	var departed: bool=finished and await _wait(tree,c,func()->bool:return _visit(c).phase=="departed",1200)
	var income: int=_income(c)
	var ward_count: int=0;var cure_count: int=0
	for entry: Dictionary in c.world.facts.ledger.entries.values():
		if entry.component=="ward":ward_count+=1
		if entry.component=="cure":cure_count+=1
	if finished:
		c.sim.clinic._complete_service(c.world,rounding)
		HospitalLedger.settle(c.world)
	report.checks.clinical_valid_input=c.input.validation.is_empty() and not c.input.care_completed
	report.checks.nurse_real_arrival=at_care and care.get("start_tick",-1)>start
	report.checks.full_care=completed and int(care.get("total_ticks",-1))==80 and care_end-int(care.get("start_tick",care_end))==80
	report.checks.nurse_real_release=released and not release_initial.is_empty() and nurse_position!=layout.operator_cells[0]
	report.checks.doctor_real_arrival=at_round and round_start>care_end
	report.checks.full_round=finished and round_end-int(rounding.get("start_tick",round_end))==int(rounding.get("total_ticks",-1)) and int(rounding.get("total_ticks",0))==ceili(100.0*(1.0+0.003*float(c.audit.service_inputs.get("round",{}).get("fatigue",100000))))
	report.checks.actual_patient_exit=departed and c.world.facts.actors[_visit(c).actor_id].location.kind=="outside" and not c.world.facts.adaptations.has(bed_id)
	report.checks.single_settlement=uncharged and finished and ward_count==1 and cure_count==1 and _income(c,"ward")==60 and _income(c,"cure")==360 and income==505 and _income(c)==income
	report.checks.clinical_exact_work=c.audit.care_decrements==80 and c.audit.round_decrements==int(rounding.get("total_ticks",-1)) and c.audit.work_errors.is_empty()
	report.checks.clinical_no_body_overlap=c.audit.body_overlaps.is_empty()
	var bounded: bool=true
	for distance: float in c.audit.maximum_step.values():bounded=bounded and distance<=0.201
	report.checks.clinical_bounded_movement=bounded
	report.observations.clinical={"audit":c.audit,"initial":initial,"care":care,"care_end_tick":care_end,"release_initial":release_initial,"nurse_released_position":nurse_position,"round":rounding,"round_start_observed":round_start,"round_end_tick":round_end,"final":_state(c),"validation":c.world.validate(_content)}
	print("BED_SERVICE_CLINICAL "+JSON.stringify(report.checks))

func _cold_restore(c: Dictionary) -> Dictionary:
	var frozen: Dictionary=c.world.freeze()
	var before: String=c.world.validate(_content)
	_simulations.erase(c.sim)
	c.sim.dispose()
	c.world=WorldState.new(frozen.duplicate(true))
	c.sim=HospitalSimulation.new(c.world,_content)
	c.sim.clinic.departments=null
	_simulations.append(c.sim)
	return {"before_validation":before,"after_validation":c.world.validate(_content),"exact_facts":frozen==c.world.freeze(),"tick":c.world.sim_tick}

func _repair(tree: SceneTree) -> void:
	var c: Dictionary=_input()
	var bed_id: String=str(_stay(c).bed_id)
	var bed: Dictionary=c.world.facts.facilities[bed_id]
	bed.condition=18.0
	bed.pending_failure=true
	c.world.touch()
	c.sim.services.maintenance.boundaries(c.world)
	var job_id: String=str(bed.maintenance_order_id)
	var input_use: Dictionary=HospitalEquipmentUse.query(c.world,bed_id)
	var initial_cash: int=HospitalLedger.balance(c.world)
	var initial_income: int=_income(c)
	var no_early_work: bool=true
	var no_work_during_travel: bool=true
	var occupied_ticks: int=0
	var travel_ticks: int=0
	var work_ticks: int=0
	var first_work: Dictionary={}
	var cold: Dictionary={}
	var first_worker_position: Dictionary={}
	var release_tick: int=-1
	var prior_remaining: int=30000
	var exact_work: bool=true
	for i: int in 1800:
		var use: Dictionary=HospitalEquipmentUse.query(c.world,bed_id)
		var job: Dictionary=c.world.facts.maintenance.jobs[job_id]
		if use.occupied:
			occupied_ticks+=1
			no_early_work=no_early_work and not job.started and int(job.completed_milli)==0 and int(job.paid_parts)==0
		elif release_tick<0:release_tick=c.world.sim_tick
		if not str(job.worker_id).is_empty() and first_worker_position.is_empty():first_worker_position=c.world.facts.actors[job.worker_id].location.duplicate(true)
		var before_completed: int=int(job.completed_milli)
		_tick(c)
		job=c.world.facts.maintenance.jobs[job_id]
		if not str(job.worker_id).is_empty() and not job.started:
			travel_ticks+=1
			no_work_during_travel=no_work_during_travel and int(job.completed_milli)==0 and int(job.paid_parts)==0
		if int(job.completed_milli)>before_completed:
			work_ticks+=1
			exact_work=exact_work and int(job.completed_milli)-before_completed==100 and prior_remaining-int(job.remaining_milli)==100
			if first_work.is_empty():
				var worker: String=str(job.worker_id)
				first_work={"tick":c.world.sim_tick,"job":job.duplicate(true),"location":c.world.facts.actors[worker].location.duplicate(true),"at_work_cell":c.sim.space.at(c.world,worker,int(job.work_floor),job.work_cell),"occupied":HospitalEquipmentUse.query(c.world,bed_id).occupied}
		prior_remaining=int(job.remaining_milli)
		if int(job.completed_milli)==10000 and cold.is_empty():
			cold={"before_job":job.duplicate(true),"cash":HospitalLedger.balance(c.world),"restore":_cold_restore(c)}
			cold.after_job=c.world.facts.maintenance.jobs[job_id].duplicate(true)
			cold.cash_after=HospitalLedger.balance(c.world)
		if job.phase=="completed":break
		if i%100==99:await tree.process_frame
	var job: Dictionary=c.world.facts.maintenance.jobs[job_id]
	bed=c.world.facts.facilities[bed_id]
	var receipt: Dictionary=c.world.facts.maintenance.receipts.get(job_id+":repair_completed",{})
	var worker_id: String=str(receipt.get("worker_id",""))
	var left: bool=not worker_id.is_empty() and await _wait(tree,c,func()->bool:return c.world.facts.actors[worker_id].location.kind=="outside",900)
	var final_cash: int=HospitalLedger.balance(c.world)
	var bounded: bool=true
	for distance: float in c.audit.maximum_step.values():bounded=bounded and distance<=0.201
	report.checks.repair_occupied_wait=input_use.occupied and occupied_ticks>0 and no_early_work
	report.checks.repair_real_release=release_tick>=0 and _visit(c).phase=="departed" and not c.world.facts.adaptations.has(bed_id)
	report.checks.repair_real_arrival=travel_ticks>0 and no_work_during_travel and first_work.get("at_work_cell",false) and not first_work.get("occupied",true) and not first_worker_position.is_empty()
	report.checks.repair_full_30_seconds=job.phase=="completed" and int(job.completed_milli)==30000 and int(job.remaining_milli)==0 and work_ticks==300 and exact_work
	report.checks.repair_cold_continuation=not cold.is_empty() and cold.restore.exact_facts and cold.restore.before_validation.is_empty() and cold.restore.after_validation.is_empty() and cold.before_job==cold.after_job and cold.cash==cold.cash_after
	report.checks.repair_cost_once=int(job.paid_parts)==40 and final_cash==initial_cash+(_income(c)-initial_income)-40 and c.world.facts.maintenance.receipts.size()==1
	report.checks.repair_restored_condition=bed.condition==100.0 and not bed.failed and not bed.pending_failure and bed.repair_grace_until==int(receipt.get("tick",-1800))+1800
	report.checks.repair_worker_real_exit=left
	report.checks.repair_no_body_overlap=c.audit.body_overlaps.is_empty()
	report.checks.repair_bounded_movement=bounded
	report.observations.repair={"input":c.input,"input_condition":18.0,"input_pending_failure":true,"initial_use":input_use,"occupied_ticks":occupied_ticks,"travel_ticks":travel_ticks,"work_ticks":work_ticks,"release_tick":release_tick,"first_worker_position":first_worker_position,"first_work":first_work,"cold":cold,"job":job.duplicate(true),"bed":bed.duplicate(true),"receipt":receipt,"initial_cash":initial_cash,"final_cash":final_cash,"audit":c.audit,"final":_state(c),"validation":c.world.validate(_content)}
	print("BED_SERVICE_REPAIR "+JSON.stringify(report.checks))
