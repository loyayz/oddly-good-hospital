extends "res://tools/performance/acceptance/fixtures/prepare_inputs.gd"

const Operations = preload("res://tools/performance/current/comprehensive_operations.gd")
const ClinicalInputs = preload("res://tools/performance/current/comprehensive_clinical_inputs.gd")
const SCENARIO: String = "comprehensive160-clinical-family-v3"
const WARD_OPENING: Dictionary={"bench_staff_0025":"bench_room_1_03","bench_staff_0027":"bench_room_3_03"}
var _setup: Dictionary = {"commands":[],"initial_cohorts":[],"added_facilities":[],"moved_facilities":[],"errors":[],"limitations":[]}
var _failure_boundary_path: String=""
var _preparation_events: Array=[]

func _run() -> void:
	var output_dir: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="): output_dir=argument.trim_prefix("--output-dir=")
		if argument.begins_with("--maximum-steps="): _maximum_steps=argument.trim_prefix("--maximum-steps=").to_int()
		if argument.begins_with("--maximum-real-seconds="): _maximum_us=argument.trim_prefix("--maximum-real-seconds=").to_int()*1000000
	if output_dir.is_empty() or _maximum_steps<=0 or _maximum_us<=0:
		push_error("Expected --output-dir and positive preparation watchdogs.");quit(2);return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))!=OK: quit(2);return
	var output: String=output_dir.path_join("comprehensive160.input.bin")
	_failure_boundary_path=output+".failed-boundary"
	for existing: String in [output,output_dir.path_join("comprehensive160.manifest.json"),_failure_boundary_path+".bin",_failure_boundary_path+".json"]:
		if FileAccess.file_exists(existing): push_error("Preserve the existing preparation evidence; choose a new directory: "+existing);quit(2);return
	_started=Time.get_ticks_usec();_steps=0;_case_id="comprehensive160"
	var content: HospitalContent=HospitalContent.new()
	if not content.error.is_empty(): push_error(content.error);quit(2);return
	var result: Dictionary=await _construct(content,output)
	result.preparation_us=Time.get_ticks_usec()-_started
	result.scenario=SCENARIO
	var report_file: FileAccess=FileAccess.open(output_dir.path_join("comprehensive160.manifest.json"),FileAccess.WRITE)
	if report_file==null: quit(2);return
	report_file.store_string(JSON.stringify(result,"\t"));report_file.close()
	print("COMPREHENSIVE_PREPARATION="+JSON.stringify(result))
	quit(0 if result.ok else 1)

func _construct(content: HospitalContent, output: String) -> Dictionary:
	var fixture: RefCounted=Fixture.new(content,160,"four_floors","")
	if not fixture.errors.is_empty(): return {"ok":false,"errors":fixture.errors}
	var world: WorldState=fixture.world
	var input_reason: String=ClinicalInputs.unstarted_reason(world)
	if not input_reason.is_empty(): return {"ok":false,"reason":input_reason}
	var pending: Dictionary=_defer_initial_patients(world)
	if not pending.ok: return pending
	var original_bodies: Dictionary={}
	for id: String in world.ids("staff"): original_bodies[id]=content.actor_body(world.facts.actors[id]).duplicate(true)
	for id: String in pending.actors: original_bodies[id]=content.actor_body(pending.actors[id]).duplicate(true)
	var original_rooms: Array=world.facts.rooms.keys()
	var original_definitions: Dictionary={}
	for id: String in world.facts.facilities: original_definitions[id]=world.facts.facilities[id].definition_id
	# Only the employees participate in opening preparation. Unstarted patient
	# records are immutable construction input until all real desks are staffed.
	var researcher: Dictionary=world.facts.staff[Operations.RESEARCHER]
	researcher.role="researcher";researcher.title_id="";researcher.certificates=[]
	researcher.abilities={"diagnosis":0,"treatment":0,"care":0,"surgery":0}
	researcher.schedule=[{"kind":"work","pools":["bench_room_4_14"],"locked":false},{"kind":"work","pools":["bench_room_4_14"],"locked":false},{"kind":"rest","pools":[],"locked":false}]
	var student: Dictionary=world.facts.staff[Operations.STUDENT]
	student.title_id="DT01";student.abilities.treatment=0
	var gentle_doctor: Dictionary=world.facts.staff["bench_staff_0000"]
	var original_treatment: int=int(gentle_doctor.abilities.treatment)
	var original_schedule: Array=gentle_doctor.schedule.duplicate(true)
	gentle_doctor.abilities.treatment=3
	_setup.staff_initial_conditions={"researcher":Operations.RESEARCHER,"student":Operations.STUDENT,"student_treatment_level":0,"c_gentle_operator":{"staff_id":gentle_doctor.id,"original_treatment":original_treatment,"declared_treatment":3,"original_schedule":original_schedule,"declared_schedule":gentle_doctor.schedule.duplicate(true),"room_id":"bench_room_1_00","reason":"C palliative treatment retains its level-3 qualification. The original GP's legal GP-room assignment and diagnostic work remain; the added M17 permits treatment in that same room."},"cleaners_preserved":4,"boundary":"Initial employee qualifications before the first real step; no work, preparation, practice or attendance supplied."}
	_setup.cleaner_schedules=[]
	for id: String in Operations.CLEANERS:
		var cleaner: Dictionary=world.facts.staff[id]
		if cleaner.role!="cleaner" or cleaner.schedule[0]!={"kind":"work","pools":[],"locked":false}:
			return {"ok":false,"reason":"Original cleaner first work shift differs from the declared sample-start restoration","staff_id":id}
		var original: Array=cleaner.schedule.duplicate(true)
		cleaner.schedule[0]={"kind":"rest","pools":[],"locked":false}
		_setup.cleaner_schedules.append({"staff_id":id,"original_schedule":original,"initial_schedule":cleaner.schedule.duplicate(true),"sample_command":"apply_schedule","boundary":"Only the initial first shift rests. The sample-start command restores the original work shift; real travel, tools and all cleaning work remain production-owned."})
	# Keep an actual uncompleted non-clinical leaf topic without invalidating any
	# completed prerequisite or removing clinical/equipment unlocks.
	var required: Dictionary={}
	for definition: Dictionary in content.catalog.research:
		for id: String in definition.requires: required[id]=true
	var topic: String=""
	for definition: Dictionary in content.catalog.research:
		if definition.disease_ids.is_empty() and not required.has(definition.id): topic=definition.id;break
	if topic.is_empty(): return {"ok":false,"reason":"No independent non-clinical leaf research topic."}
	world.facts.research.erase(topic);_setup.research_id=topic
	for actor_id: String in fixture.visitor_ids:
		if not _unowned_placeholder(world,actor_id): return {"ok":false,"reason":"Refuse replacing an owned companion","actor_id":actor_id}
		world.facts.actors.erase(actor_id)
	fixture.visitor_ids.clear();world.touch()
	var sim: HospitalSimulation=HospitalSimulation.new(world,content)
	if not _layout(sim):
		var failed: Dictionary={"ok":false,"reason":"Initial lawful construction failed","setup":_setup};sim.dispose();return failed
	# Capacity is legal before the first real employee step as well as at freeze.
	var stock_limit: int=sim.services.supplies.capacity(world)
	world.facts.inventory.units=mini(200,stock_limit-20)
	_setup.supply_input={"units":world.facts.inventory.units,"capacity":stock_limit,"purchase_units":20,"boundary":"Initial legal stock below installed capacity, replacing Fixture's 10000-unit construction convenience. No supply capacity, consumption requirement, candidate, reservation or replenishment rule is changed; not a performance optimization."}
	if int(world.facts.inventory.units)<20: sim.dispose();return {"ok":false,"reason":"Insufficient lawful supply capacity for the complete clinical cohorts and purchase."}
	var staff_deployment: Dictionary=_deploy_initial_core(sim,world.ids("staff"),"staff")
	_setup.initial_deployment={"ok":false,"staff_stage":staff_deployment}
	if not staff_deployment.ok:
		sim.dispose();return {"ok":false,"reason":"Initial employee public deployment failed","setup":_setup}
	if not _add_c_gentle_equipment(sim):
		sim.dispose();return {"ok":false,"reason":"C palliative equipment has no complete lawful placement before the first real staff step","setup":_setup}
	var closed: CommandResult=_intake(sim,false,"comprehensive-setup-staff-intake-close")
	_setup.commands.append({"kind":"arrivals_intake","open":false,"stage":"employee_opening","result":closed.to_record()})
	if not closed.accepted:
		sim.dispose();return {"ok":false,"reason":"Cannot close normal intake for employee opening","setup":_setup}
	_setup.staff_preparation=await _prepare_employee_staff(sim)
	if not _setup.staff_preparation.ok:
		var failure: Dictionary=_save_failed_boundary(sim,"Real guidance and ward-nurse opening preparation did not finish",[],_setup.staff_preparation)
		sim.dispose();return failure.merged({"setup":_setup})
	var cohorts: Dictionary=ClinicalInputs.prepare(pending,world,content)
	if not cohorts.ok: sim.dispose();return cohorts.merged({"setup":_setup})
	_setup.initial_cohorts=cohorts.historical
	_setup.fresh_gp_cohorts=cohorts.fresh
	var additional: Dictionary=ClinicalInputs.add_fresh(pending,content)
	if not additional.ok: sim.dispose();return additional
	_setup.additional_fresh_patients=additional.records
	for row: Dictionary in additional.records: original_bodies[row.actor_id]=row.body_dimensions.duplicate(true)
	var all_patients: Array=pending.visits.keys()
	all_patients.sort()
	_setup.patient_join=_join_patient_batch(sim,pending,all_patients,"patients")
	if not _setup.patient_join.ok: sim.dispose();return _setup.patient_join.merged({"setup":_setup})
	var patient_deployment: Dictionary=_deploy_initial_core(sim,_setup.patient_join.actor_ids,"patients")
	var staff_stage: Dictionary=staff_deployment.duplicate();staff_stage.erase("records")
	var patient_stage: Dictionary=patient_deployment.duplicate();patient_stage.erase("records")
	_setup.initial_deployment={"ok":staff_deployment.ok and patient_deployment.ok,"count":staff_deployment.count+patient_deployment.get("count",0),"staff_stage":staff_stage,"patient_stage":patient_stage,"records":staff_deployment.records+patient_deployment.get("records",[]),"boundary":"All original 120 patients and eight additional full-body fresh patients join once, before any patient's first step. Participating employees and their actual work, locations, travel and clocks remain unchanged."}
	for key: String in ["same_floors","only_locations_and_revision_changed","all_full_bodies_public_and_clear"]: _setup.initial_deployment[key]=staff_deployment.get(key,false) and patient_deployment.get(key,false)
	_setup.initial_deployment.validation_scope="Each cohort at its own initial declaration, not a requirement that actual final work posts be public waiting cells. Final world/build/schedule validation is separate."
	if not patient_deployment.ok:
		sim.dispose();return {"ok":false,"reason":"New patient public deployment failed","setup":_setup}
	for row: Dictionary in _setup.initial_cohorts+_setup.fresh_gp_cohorts:
		row.freeze_location=world.facts.actors[world.facts.visits[row.visit_id].actor_id].location.duplicate(true)
	_setup.clinical_start={"joined_tick":world.sim_tick,"original_patients":120,"additional_fresh_patients":8,"total_patients":128,"patient_steps":_steps-int(_setup.patient_join.joined_step),"ward_stays":world.facts.ward_stays.size(),"attempts":world.facts.attempts.size(),"sessions":world.facts.sessions.size(),"preparations":world.facts.preparations.size(),"scope":"No patient, admission, relative or clinical work is advanced during preparation. Saved diagnostic history is declared input. Real admission, family decisions, visits and all clinical progress must execute after this boundary."}
	# The worn spare is declared at the complete patient input boundary. The
	# employee-only opening phase cannot consume the sample's maintenance job.
	world.facts.facilities[Operations.MAINTENANCE_ITEM].condition=float(content.balance.maintenance_dispatch.manual_threshold)
	_setup.maintenance_input={"id":Operations.MAINTENANCE_ITEM,"condition":world.facts.facilities[Operations.MAINTENANCE_ITEM].condition,"declared_tick":world.sim_tick}
	# Dirt appears through the real event owner at legal ground locations. Its
	# complete worker selection, route, use and receipts are not prefilled.
	for floor_id: int in [1,2,3,4]:
		for index: int in 4:
			var source: String="comprehensive-initial-dirt-%d-%d"%[floor_id,index]
			var dirt: String=sim.services.environment.spawn_dirt(world,"CL01",source,source+":scatter",floor_id,[40+index*2,83])
			if dirt.is_empty(): _setup.errors.append("No lawful initial dirt location: "+source)
	var reopened: CommandResult=_intake(sim,true,"comprehensive-setup-intake-open")
	_setup.commands.append({"kind":"arrivals_intake","open":true,"result":reopened.to_record(),"scope":"No simulation step follows the final patient declaration before the input freezes."})
	if not reopened.accepted: sim.dispose();return {"ok":false,"reason":"Cannot restore normal intake after preparing the complete population"}
	var retained: bool=true
	for id: String in original_rooms: retained=retained and world.facts.rooms.has(id)
	for id: String in original_definitions: retained=retained and world.facts.facilities.has(id) and world.facts.facilities[id].definition_id==original_definitions[id]
	var validation: String=world.validate(content)
	var population: Dictionary=population_of(world)
	var layout: Dictionary=_layout_counts(world)
	var beds: int=world.facility_ids("EQ05").size()
	var rules: Dictionary=_comprehensive_rules(sim)
	var core_identity: Dictionary=_core_body_audit(world,content,original_bodies)
	var family_input: Dictionary={"present":population.visitors,"stays":world.facts.visitors.stays.size(),"requests":world.facts.visitors.requests.size(),"coverage_established":false,"scope":"No family result or body is supplied. Sampled production entry and effective ward-visit work must establish both roles; an empty initial family collection is not family coverage."}
	var no_patient_progress: bool=_steps==int(_setup.patient_join.joined_step) and world.sim_tick==int(_setup.patient_join.joined_tick) and world.facts.ward_stays.is_empty() and world.facts.attempts.is_empty() and world.facts.sessions.is_empty() and world.facts.preparations.is_empty() and world.facts.visitors.stays.is_empty() and world.facts.visitors.requests.is_empty()
	var ok: bool=validation.is_empty() and rules.ok and core_identity.ok and _setup.errors.is_empty() and retained and beds==24 and layout.rooms==64 and layout.facilities==1361 and layout.service_objects==161 and layout.props==1200 and population.staff==32 and population.patients==128 and population.visitors==0 and population.present==160 and no_patient_progress
	var identity: Dictionary=_identity()
	for path: String in ["res://tools/performance/current/comprehensive_prepare.gd","res://tools/performance/current/comprehensive_clinical_inputs.gd","res://tools/performance/current/comprehensive_operations.gd","res://tools/performance/current/comprehensive_observer.gd"]: identity.sources[path]=FileAccess.get_sha256(path)
	var metadata: Dictionary={"ok":ok,"population":population,"family_input":family_input,"no_patient_progress":no_patient_progress,"layout":layout,"care_beds":beds,"original_entities_retained":retained,"room_rules":rules,"core_identity":core_identity,"setup":_setup,"validation":validation,"actual_preparation_steps":_steps,"source_tick":world.sim_tick,"scenario":SCENARIO,"identity":identity}
	if ok:
		var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
		if file==null: sim.dispose();return {"ok":false,"reason":"Cannot publish new complete input"}
		file.store_var({"content_fingerprint":content.content_fingerprint,"facts":world.freeze(),"floors":fixture.floors,"visitor_ids":fixture.visitor_ids,"fixture_migration":fixture.migration,"scenario":SCENARIO,"comprehensive_setup":_setup})
		file.close();metadata.input=output;metadata.input_sha256=FileAccess.get_sha256(output)
	else:
		metadata.merge(_save_failed_boundary(sim,"Complete initial boundary did not qualify",all_patients,{}),true)
	sim.dispose();return metadata

# Fixture patients have not participated in any step. Hold their full immutable
# input outside the employee-only world; no live actor or journey is withdrawn.
func _defer_initial_patients(world: WorldState) -> Dictionary:
	if world.sim_tick!=0 or world.facts.staff.size()!=32 or world.facts.visits.size()!=120 or world.facts.actors.size()!=160 or not world.facts.moves.is_empty(): return {"ok":false,"reason":"Fixture is not the complete unstarted 160-person input"}
	for key: String in ["tickets","sessions","attempts","preparations","ward_stays"]:
		if not world.facts[key].is_empty(): return {"ok":false,"reason":"Cannot defer a patient with existing clinical commitments","collection":key}
	var pending: Dictionary={"ok":true,"source_tick":world.sim_tick,"actors":{},"visits":{},"receipts":{}}
	for index: int in 120:
		var id: String="bench_visit_%04d"%index
		var visit: Dictionary=world.facts.visits.get(id,{})
		var actor_id: String="bench_patient_%04d"%index
		if visit.get("actor_id","")!=actor_id or visit.get("phase","")!="arrival" or not str(visit.get("ticket_id","")).is_empty() or not visit.get("diagnosis",{}).is_empty() or not visit.get("attempt_ids",[]).is_empty() or not visit.get("plan_decision",{}).is_empty() or not world.facts.actors.has(actor_id) or world.facts.arrival_receipts.get(visit.get("arrival_key",""),"")!=id:
			return {"ok":false,"reason":"Deferred patient is not an unstarted original input","visit_id":id}
		pending.actors[actor_id]=world.facts.actors[actor_id].duplicate(true)
		pending.visits[id]=visit.duplicate(true)
		pending.receipts[visit.arrival_key]=id
	for entry: Dictionary in world.facts.ledger.entries.values():
		if pending.visits.has(str(entry.owner_id)): return {"ok":false,"reason":"Historical patient money must be declared only at patient join"}
	for id: String in pending.actors: world.facts.actors.erase(id)
	for id: String in pending.visits: world.facts.visits.erase(id)
	for key: String in pending.receipts: world.facts.arrival_receipts.erase(key)
	world.touch(false)
	return pending

func _employee_opening_state(sim: HospitalSimulation, work: Dictionary) -> Dictionary:
	var world: WorldState=sim.world
	var required: int=ceili(float(sim.content.balance.staff_work_bases.preparation_seconds)/WorldState.TICK_SECONDS)
	var rows: Array=[]
	var ready: int=0
	var nurses: Dictionary={}
	for id: String in sim.world.facility_ids("SE01"):
		var desk: Dictionary=sim.world.facts.floor_guidance.desks.get(id,{})
		var nurse_id: String=str(desk.get("nurse_id",""))
		var staff: Dictionary=sim.world.facts.staff.get(nurse_id,{})
		var usable: bool=sim.services.floor_guidance._desk_usable(sim.world,id)
		var actual_work: int=int(work.get(nurse_id,{}).get("nursing_preparation_work_ticks",0))
		var prepared: bool=staff.get("base_prepared",false) and staff.get("base_task",{}).is_empty() and actual_work>=required
		if usable and prepared: ready+=1
		if not nurse_id.is_empty(): nurses[nurse_id]=true
		rows.append({"desk_id":id,"floor_id":sim.world.facts.facilities[id].floor_id,"nurse_id":nurse_id,"usable":usable,"base_prepared":prepared,"actual_base_work_ticks":actual_work,"nurse_location":sim.world.facts.actors.get(nurse_id,{}).get("location",{}).duplicate(true),"reason":desk.get("reason","")})
	var wards: Array=[]
	var ward_ready: int=0
	for nurse_id: String in WARD_OPENING:
		var room_id: String=WARD_OPENING[nurse_id]
		var room: Dictionary=world.facts.rooms[room_id]
		var bench_id: String=room_id+"_2"
		var bench: Dictionary=world.facts.facilities[bench_id]
		var staff: Dictionary=world.facts.staff[nurse_id]
		var actor: Dictionary=world.facts.actors[nurse_id]
		var assignment: Dictionary=sim.services.scheduler.assignment(world,nurse_id,sim.services.scheduler.shift_index(world))
		var actual_work: int=int(work.get(nurse_id,{}).get("nursing_preparation_work_ticks",0))
		var at_workbench: bool=bench.definition_id=="SE06" and sim.space.at(world,nurse_id,int(bench.floor_id),bench.operator_cells[0]) and not world.facts.moves.has(nurse_id)
		var in_ward: bool=actor.location.kind=="floor" and int(actor.location.floor_id)==int(room.floor_id) and sim.space.room_contains(room,sim.space.body_rectangle(actor))
		var can_start: bool=staff.role=="nurse" and "q_ward" in staff.certificates and staff.on_shift and sim.clinic._can_start(world,staff) and not sim.clinic._staff_busy(world,nurse_id)
		var prepared: bool=staff.get("base_prepared",false) and staff.get("base_task",{}).is_empty() and staff.get("life_task",{}).get("phase","idle")=="idle" and actual_work>=required
		var correct_pool: bool=assignment.get("kind","")=="work" and assignment.get("pools",[])==[room_id]
		var usable: bool=at_workbench and in_ward and can_start and prepared and correct_pool and room.get("structure_valid",true) and room.get("open_intent",true) and not bench.failed
		if usable: ward_ready+=1
		wards.append({"nurse_id":nurse_id,"ward_id":room_id,"workbench_id":bench_id,"usable":usable,"at_workbench":at_workbench,"in_ward":in_ward,"can_start":can_start,"base_prepared":staff.get("base_prepared",false),"actual_base_work_ticks":actual_work,"assignment":assignment.duplicate(true),"original_pool_preserved":correct_pool,"nurse_location":actor.location.duplicate(true)})
	return {"ok":rows.size()==8 and ready==8 and nurses.size()==8 and ward_ready==WARD_OPENING.size(),"ready_desks":ready,"distinct_nurses":nurses.size(),"desks":rows,"ready_ward_nurses":ward_ready,"ward_nurses":wards}

func _prepare_employee_staff(sim: HospitalSimulation) -> Dictionary:
	var world: WorldState=sim.world
	var started: int=Time.get_ticks_usec()
	var first_step: int=_steps
	var first_tick: int=world.sim_tick
	var rows: Dictionary={}
	for id: String in world.ids("staff"):
		var staff: Dictionary=world.facts.staff[id]
		rows[id]={"staff_id":id,"role":staff.role,"hired_tick":staff.get("hired_tick",0),"initial_location":world.facts.actors[id].location.duplicate(true),"initial_amenity_clock":staff.get("amenity_clock",{}).duplicate(true),"initial_last_rest_end_tick":staff.get("last_rest_end_tick",-1),"movement_steps":0,"transit_steps":0,"actual_floor_distance_cells":0.0,"nursing_preparation_work_ticks":0,"first_base_prepared_tick":-1,"first_guidance_arrival_tick":-1,"assigned_job_steps":0}
	var state: Dictionary=_employee_opening_state(sim,rows)
	while not state.ok:
		var previous: Dictionary={}
		for id: String in rows: previous[id]={"location":world.facts.actors[id].location.duplicate(true),"moving":world.facts.moves.has(id)}
		var advanced: Dictionary=await _advance(sim)
		if not advanced.ok: return advanced.merged({"elapsed_us":Time.get_ticks_usec()-started,"start_tick":first_tick,"end_tick":world.sim_tick,"actual_steps":_steps-first_step,"last_opening_state":state,"staff":rows.values(),"scope":"Unmeasured 32-person opening preparation; never counted as 160-person coverage."})
		var worked: Dictionary=sim.services.development.worked_staff()
		for id: String in rows:
			var actor: Dictionary=world.facts.actors[id]
			var staff: Dictionary=world.facts.staff[id]
			var prior: Dictionary=previous[id].location
			if previous[id].moving or world.facts.moves.has(id): rows[id].movement_steps+=1
			if actor.location.kind=="transit" or prior.kind=="transit": rows[id].transit_steps+=1
			if prior.kind=="floor" and actor.location.kind=="floor" and int(prior.floor_id)==int(actor.location.floor_id): rows[id].actual_floor_distance_cells+=Vector2(float(prior.cell[0]),float(prior.cell[1])).distance_to(Vector2(float(actor.location.cell[0]),float(actor.location.cell[1])))
			if staff.role=="nurse" and worked.has(id): rows[id].nursing_preparation_work_ticks+=1
			if staff.get("base_prepared",false) and int(rows[id].first_base_prepared_tick)<0: rows[id].first_base_prepared_tick=world.sim_tick
			if not str(staff.get("active_job_id","")).is_empty(): rows[id].assigned_job_steps+=1
		state=_employee_opening_state(sim,rows)
		for desk: Dictionary in state.desks:
			if desk.usable and desk.base_prepared and rows.has(desk.nurse_id) and int(rows[desk.nurse_id].first_guidance_arrival_tick)<0: rows[desk.nurse_id].first_guidance_arrival_tick=world.sim_tick
		if world.facts.actors.size()!=32 or not world.facts.visits.is_empty() or world.facts.arrivals.intake_open:
			return {"ok":false,"reason":"Employee preparation admitted an unexpected participant","population":population_of(world),"actual_steps":_steps-first_step}
	var required: int=ceili(float(sim.content.balance.staff_work_bases.preparation_seconds)/WorldState.TICK_SECONDS)
	var actual_work: bool=true
	for desk: Dictionary in state.desks: actual_work=actual_work and int(rows[desk.nurse_id].nursing_preparation_work_ticks)>=required
	for ward: Dictionary in state.ward_nurses: actual_work=actual_work and int(rows[ward.nurse_id].nursing_preparation_work_ticks)>=required
	for id: String in rows:
		rows[id].final_location=world.facts.actors[id].location.duplicate(true)
		rows[id].final_amenity_clock=world.facts.staff[id].get("amenity_clock",{}).duplicate(true)
		rows[id].final_last_rest_end_tick=world.facts.staff[id].get("last_rest_end_tick",-1)
		rows[id].final_life_task=world.facts.staff[id].get("life_task",{}).duplicate(true)
	var validation: String=world.validate(sim.content)
	return {"ok":state.ok and actual_work and validation.is_empty(),"start_tick":first_tick,"end_tick":world.sim_tick,"actual_steps":_steps-first_step,"elapsed_us":Time.get_ticks_usec()-started,"population":population_of(world),"validation":validation,"required_preparation_work_ticks":required,"all_required_nurses_have_actual_work":actual_work,"opening":state,"staff":rows.values(),"scope":"Real 32-person opening preparation only. Eight guidance desks and both original ward nurses must be simultaneously usable after actual arrival and base work. Normal intake is closed; all travel, preparation, clocks and life duties execute unchanged. No patient or family step is advanced and no 160-person coverage is claimed."}

func _join_patient_batch(sim: HospitalSimulation, pending: Dictionary, visit_ids: Array, name: String) -> Dictionary:
	var world: WorldState=sim.world
	var started: int=Time.get_ticks_usec()
	var before: Dictionary=world.freeze()
	var ids: Array=visit_ids.duplicate()
	ids.sort()
	var actors: Array=[]
	var histories: Dictionary={}
	for row: Dictionary in _setup.initial_cohorts: histories[row.visit_id]=row
	var queues: Array=[]
	var profile_b_arrivals: Array=[]
	var unlock_before: int=int(world.facts.research_progress.first_profile_b_tick)
	for id: String in ids:
		if world.facts.visits.has(id) or not pending.visits.has(id): return {"ok":false,"reason":"Patient identity is already participating or missing","visit_id":id}
		var visit: Dictionary=pending.visits[id].duplicate(true)
		if world.facts.actors.has(visit.actor_id): return {"ok":false,"reason":"Patient body identity is already owned","actor_id":visit.actor_id}
		world.facts.actors[visit.actor_id]=pending.actors[visit.actor_id].duplicate(true)
		for key: String in ["arrival_tick","arrived_tick","last_progress_tick","last_service_tick"]: visit[key]=world.sim_tick
		world.facts.visits[id]=visit
		world.facts.arrival_receipts[visit.arrival_key]=id
		world.register_visit(id)
		sim.services.research.record_arrival(world,visit)
		if sim.content.definition("diseases",str(visit.disease_id)).get("profile","")=="B": profile_b_arrivals.append(id)
		actors.append(visit.actor_id)
		var historical: Dictionary=histories.get(id,{})
		for row: Dictionary in historical.get("receipts",[]):
			var paid: CommandResult=HospitalLedger.post(world,LedgerEntry.new(visit.id,str(row.component),int(row.amount)))
			if not paid.accepted: return {"ok":false,"reason":"Saved completed diagnostic fee input rejected","visit_id":id,"receipt":paid.to_record()}
		sim.clinic._queue(world,visit,str(historical.get("next_service","gp")))
		queues.append({"visit_id":id,"ticket_id":visit.ticket_id,"kind":world.facts.tickets[visit.ticket_id].kind,"enqueued_tick":world.sim_tick})
	sim.services.waiting.ensure(world)
	sim.services.experience.ensure(world)
	world.touch(false)
	var original_actors_preserved: bool=true
	for id: String in before.actors: original_actors_preserved=original_actors_preserved and before.actors[id]==world.facts.actors[id]
	var original_visits_preserved: bool=true
	for id: String in before.visits: original_visits_preserved=original_visits_preserved and before.visits[id]==world.facts.visits[id]
	var active_facts_preserved: bool=original_actors_preserved and original_visits_preserved
	for key: String in ["staff","moves","adaptations","preparations","sessions","attempts","ward_stays","visitors","floor_guidance"]: active_facts_preserved=active_facts_preserved and before.get(key,{})==world.facts.get(key,{})
	for collection: String in ["seats","needs","clocks"]:
		for id: String in before.get("waiting_life",{}).get(collection,{}): active_facts_preserved=active_facts_preserved and before.waiting_life[collection][id]==world.facts.waiting_life[collection].get(id,{})
	active_facts_preserved=active_facts_preserved and before.rng==world.facts.rng
	var first_need: int=ceili(float(sim.content.balance.amenity_flow.first_need_seconds)/WorldState.TICK_SECONDS)
	var clocks: bool=true
	for id: String in ids: clocks=clocks and int(world.facts.waiting_life.clocks[id].next_need_tick)==world.sim_tick+first_need
	if not _setup.has("join_ticks"): _setup.join_ticks={}
	for actor_id: String in actors: _setup.join_ticks[actor_id]=world.sim_tick
	var unlock_after: int=int(world.facts.research_progress.first_profile_b_tick)
	var arrival_recorded: bool=profile_b_arrivals.is_empty() or unlock_after>=0 and unlock_after<=world.sim_tick
	return {"ok":active_facts_preserved and clocks and arrival_recorded,"name":name,"joined_tick":world.sim_tick,"joined_step":_steps,"elapsed_us":Time.get_ticks_usec()-started,"patient_count":ids.size(),"actor_ids":actors,"population":population_of(world),"existing_actor_and_visit_facts_preserved":active_facts_preserved,"fresh_clocks_start_at_join":clocks,"queues":queues,"research_arrival":{"owner":"HospitalResearch.record_arrival","profile_b_visit_ids":profile_b_arrivals,"first_profile_b_tick_before":unlock_before,"first_profile_b_tick_after":unlock_after,"valid":arrival_recorded},"scope":"One first-step input declaration, with each Visit's actual arrival recorded through the existing research owner. Saved diagnostic history is separate from later real prefix/sample GP work. Previously participating bodies, travel, ward/family ownership and work are unchanged. Complete body placement and world validation follow before this cohort's first step."}

# The step and watchdog order matches the inherited preparer. Only the returned
# completed events are copied after each actual step, outside simulated work.
func _advance(simulation: HospitalSimulation) -> Dictionary:
	if _steps>=_maximum_steps or Time.get_ticks_usec()-_started>=_maximum_us:
		return {"ok":false,"reason":"Preparation watchdog reached before actual entry/route became available.","steps":_steps,"population":population_of(simulation.world)}
	var result: TickResult=simulation.step_nonblocking()
	while result==null:
		if Time.get_ticks_usec()-_started>=_maximum_us: return {"ok":false,"reason":"Preparation boundary/solver watchdog reached.","steps":_steps}
		await process_frame
		result=simulation.step_nonblocking()
	_steps+=1
	if _steps%32==0: _progress("actual_steps",{"tick":simulation.world.sim_tick})
	for event: SimEvent in result.facts:
		if event.kind!="tick_completed": _preparation_events.append(event.to_record())
	await process_frame
	return {"ok":true}

func _save_failed_boundary(sim: HospitalSimulation, reason: String, visit_ids: Array, context: Dictionary) -> Dictionary:
	var world: WorldState=sim.world
	var affected: Array=[]
	for id: String in visit_ids:
		var visit: Dictionary=world.facts.visits.get(id,{})
		var actor: Dictionary=world.facts.actors.get(str(visit.get("actor_id","")),{})
		affected.append({"visit_id":id,"phase":visit.get("phase","missing"),"result":visit.get("final_result",""),"waiting_reason":visit.get("waiting_reason",""),"diagnosis":visit.get("diagnosis",{}).duplicate(true),"actor_location":actor.get("location",{}).duplicate(true),"ticket":world.facts.tickets.get(str(visit.get("ticket_id","")),{}).duplicate(true)})
	var visitor_ids: Array=[]
	for family: Dictionary in world.facts.visitors.stays.values(): visitor_ids.append(str(family.actor_id))
	var boundary: Dictionary={"scenario":SCENARIO+"-failed-preparation","content_fingerprint":sim.content.content_fingerprint,"facts":world.freeze(),"events":_preparation_events.duplicate(true),"floors":[1,2,3,4],"visitor_ids":visitor_ids,"reason":reason,"tick":world.sim_tick,"context":context.duplicate(true),"visits":affected}
	var binary: FileAccess=FileAccess.open(_failure_boundary_path+".bin",FileAccess.WRITE)
	if binary!=null: binary.store_var(boundary);binary.close()
	var json: FileAccess=FileAccess.open(_failure_boundary_path+".json",FileAccess.WRITE)
	if json!=null: json.store_string(JSON.stringify(boundary,"\t"));json.close()
	_progress("failed_business_boundary",{"tick":world.sim_tick,"reason":reason,"file":_failure_boundary_path,"event_count":_preparation_events.size(),"visits":affected})
	return context.merged({"ok":false,"reason":reason,"tick":world.sim_tick,"complete_preparation_steps":_steps,"affected_visits":affected,"family_requests":world.facts.visitors.requests.duplicate(true),"ward_stays":world.facts.ward_stays.duplicate(true),"failure_boundary_json":_failure_boundary_path+".json","failure_boundary_bin":_failure_boundary_path+".bin"},true)

func _core_body_audit(world: WorldState, content: HospitalContent, original: Dictionary) -> Dictionary:
	var records: Array=[]
	var ok: bool=original.size()==160
	for id: String in original:
		var actor: Dictionary=world.facts.actors.get(id,{})
		var current: Dictionary=content.actor_body(actor) if not actor.is_empty() else {}
		var preserved: bool=not actor.is_empty() and original[id]==current
		ok=ok and preserved
		records.append({"actor_id":id,"present":not actor.is_empty(),"full_body_preserved":preserved,"original_body_dimensions":original[id],"body_dimensions":current})
	return {"ok":ok,"core_ids":original.size(),"records":records,"scope":"All original 32 employee and 120 patient identities and complete bodies, plus explicitly declared full-body fresh patients. Actual later movement never becomes an initial deployment edit."}

func _layout(sim: HospitalSimulation) -> bool:
	if not _build(sim,"research-use",{"kind":"build_room_use","target_id":"bench_room_4_14","room_type_id":"research"}): return false
	if not _build(sim,"rest-use",{"kind":"build_room_use","target_id":"bench_room_1_14","room_type_id":"rest"}): return false
	# Move each original desk to public ground, retaining all four identities.
	for floor_id: int in [1,2,3,4]:
		var old: String="bench_room_%d_14_guidance"%floor_id
		if not _place(sim,old,"SE01",floor_id,[[8,84],[16,84],[24,84],[32,84]],"",true): return false
		if not _place(sim,"comprehensive_guidance_%d"%floor_id,"SE01",floor_id,[[24,84],[32,84],[56,84],[64,84]],"",false): return false
		for definition: String in ["SE02","SE03","SE06","FUR17"]:
			if not _place(sim,"comprehensive_%s_%d"%[definition,floor_id],definition,floor_id,[[8,80],[16,80],[24,80],[32,80],[56,80],[64,80],[72,80],[80,80]],"",false): return false
	if not _place(sim,Operations.RESEARCH_DESK,"FUR05",4,[[50,76],[52,76],[50,72]],"bench_room_4_14",false): return false
	if not _place(sim,Operations.TRAINING_DESK,"FUR05",4,[[53,76],[50,72],[53,72]],"bench_room_4_14",false): return false
	if not _place(sim,"comprehensive_rest_sofa","FUR06",1,[[50,76],[50,72],[53,76]],"bench_room_1_14",false): return false
	if not _place(sim,"comprehensive_recreation","RC01",1,[[53,76],[50,72],[53,72]],"bench_room_1_14",false): return false
	# The inherited seat authority checks actual footprint, waiting body and route.
	var seats: Dictionary=_add_public_seats(sim,8)
	_setup.companion_seats=seats
	return bool(seats.ok)

func _add_c_gentle_equipment(sim: HospitalSimulation) -> bool:
	if sim.world.sim_tick!=0 or not sim.world.facts.moves.is_empty(): return false
	var gentle_cells: Array=[]
	var gentle_room: Dictionary=sim.world.facts.rooms["bench_room_1_00"]
	for y: int in range(int(gentle_room.origin[1]),int(gentle_room.origin[1])+int(gentle_room.size[1])):
		for x: int in range(int(gentle_room.origin[0]),int(gentle_room.origin[0])+int(gentle_room.size[0])): gentle_cells.append([x,y])
	if not _place(sim,"comprehensive_c_gentle","M17",1,gentle_cells,"bench_room_1_00",false): return false
	_setup.c_gentle_equipment={"facility_id":"comprehensive_c_gentle","definition_id":"M17","room_id":"bench_room_1_00","operator_id":"bench_staff_0000","candidate_cells":gentle_cells.size(),"scope":"One additional formally placed medical station before the first staff step. All original stations remain; the GP's original room assignment also owns legal treatment here."}
	return true

func _place(sim: HospitalSimulation, id: String, definition: String, floor_id: int, cells: Array, room_id: String, moving: bool) -> bool:
	for cell: Array in cells:
		var draft: Dictionary={"kind":"build_move" if moving else "build_facility","floor_id":floor_id,"cell":cell,"room_id":room_id}
		if moving: draft.target_id=id
		else: draft.id=id;draft.definition_id=definition
		var quote: Dictionary=sim.services.building.preview(sim.world,draft)
		if not quote.get("ok",false): continue
		if not _build(sim,"place-"+id,draft): return false
		(_setup.moved_facilities if moving else _setup.added_facilities).append(id)
		return true
	_setup.errors.append("No complete lawful placement for "+id)
	return false

func _build(sim: HospitalSimulation, key: String, draft: Dictionary) -> bool:
	var before: Dictionary=sim.world.facts.actors.duplicate(true)
	var result: CommandResult=sim.apply(GameCommand.from_record({"id":"comprehensive-setup-"+key,"hospital_id":sim.world.hospital_id,"expected_revision":sim.world.revision,"kind":draft.kind,"typed_payload":draft,"loading_session_id":"comprehensive-initial-building"}))
	_setup.commands.append({"draft":draft.duplicate(true),"result":result.to_record(),"actor_facts_unchanged":before==sim.world.facts.actors})
	if not result.accepted or before!=sim.world.facts.actors: _setup.errors.append("Initial construction rejected or moved an actor: "+key)
	return result.accepted and before==sim.world.facts.actors

func _deploy_initial_core(sim: HospitalSimulation, actors: Array, phase: String) -> Dictionary:
	var world: WorldState=sim.world
	var expected_count: int=32 if phase=="staff" else 128
	if actors.is_empty() or not phase in ["staff","patients"]: return {"ok":false,"reason":"Empty or unknown first-step cohort","phase":phase,"records":[]}
	if phase=="staff" and (actors.size()!=32 or world.sim_tick!=0 or not world.facts.moves.is_empty()): return {"ok":false,"reason":"Employees have already started real movement","count":actors.size(),"records":[]}
	if phase!="staff":
		if not _setup.staff_preparation.ok: return {"ok":false,"reason":"Employee opening is incomplete","records":[]}
		for id: String in actors:
			if int(_setup.get("join_ticks",{}).get(id,-1))!=world.sim_tick: return {"ok":false,"reason":"Patient has already crossed its first-step declaration","actor_id":id,"records":[]}
	for id: String in actors:
		if not world.facts.actors.has(id) or world.facts.moves.has(id) or (world.facts.staff.has(id)!=(phase=="staff")):
			return {"ok":false,"reason":"A declaration cannot reposition an already moving or different-cohort body","actor_id":id,"count":actors.size(),"records":[]}
	var expected: Dictionary=world.freeze()
	var rooms: Dictionary={}
	for room: Dictionary in world.facts.rooms.values(): rooms.get_or_add(int(room.floor_id),[]).append(room)
	var desks: Dictionary={}
	for id: String in world.facility_ids("SE01"):
		var facility: Dictionary=world.facts.facilities[id]
		desks.get_or_add(int(facility.floor_id),[]).append(id)
	var candidates: Array=[]
	for y: int in 96:
		for x: int in 96: candidates.append([x,y])
	var ordered: Dictionary={}
	var patient_ordinals: Dictionary={}
	var same_floors: bool=true
	var records: Array=[]
	for id: String in actors:
		var actor: Dictionary=world.facts.actors[id]
		if actor.location.kind!="floor": return {"ok":false,"reason":"Original core actor is not on its initial floor","actor_id":id}
		var floor_id: int=int(actor.location.floor_id)
		var original: Dictionary=actor.location.duplicate(true)
		var patient: bool=not world.facts.staff.has(id)
		var anchor: Dictionary={"kind":"original_location","source_id":id,"source_field":"location.cell","floor_id":floor_id,"cell":original.cell.duplicate(),"basis":"No assigned room; retain the original initial-location preference."}
		if world.facts.staff.has(id):
			var staff: Dictionary=world.facts.staff[id]
			var assignment: Dictionary=sim.clinic.scheduler.assignment(world,id,sim.clinic.scheduler.shift_index(world))
			if not assignment.pools.is_empty():
				var room: Dictionary=world.facts.rooms.get(str(assignment.pools[0]),{})
				if room.is_empty(): return {"ok":false,"reason":"Initial staff room assignment has no actual room","actor_id":id}
				anchor={}
				if int(room.floor_id)==floor_id:
					for door: Dictionary in HospitalSpace.floor_layout(world,floor_id).doors:
						if door.get("room_id","")==room.id and (anchor.is_empty() or str(door.id)<str(anchor.source_id)):
							anchor={"kind":"scheduled_room_door","source_id":door.id,"source_field":"door.cell","room_id":room.id,"floor_id":floor_id,"cell":door.cell.duplicate()}
				else:
					# A ward nurse keeps its original floor and must really commute.
					for connection_id: String in world.ids("connectors"):
						var connection: Dictionary=world.facts.connectors[connection_id]
						if HospitalTransit.has_stop(connection,floor_id) and HospitalTransit.has_stop(connection,int(room.floor_id)):
							anchor={"kind":"cross_floor_assignment_connector","source_id":connection_id,"source_field":"connector.anchor","room_id":room.id,"target_floor_id":int(room.floor_id),"floor_id":floor_id,"cell":connection.anchor.duplicate()};break
				if anchor.is_empty(): return {"ok":false,"reason":"No actual door or connecting landing for the staff assignment","actor_id":id}
			elif staff.role=="nurse":
				anchor={}
				for facility_id: String in world.facility_ids(str(sim.content.balance.staff_work_bases.nurse_equipment_id)):
					var facility: Dictionary=world.facts.facilities[facility_id]
					if int(facility.floor_id)!=floor_id or world.facts.rooms.has(facility.get("room_id","")): continue
					var layout: Dictionary=sim.space.facility_layout(world,facility_id)
					if not layout.operator_cells.is_empty():
						anchor={"kind":"current_floor_nursing_handoff","source_id":facility_id,"source_field":"facility_layout.operator_cells[0]","floor_id":floor_id,"cell":layout.operator_cells[0].duplicate()};break
				if anchor.is_empty(): return {"ok":false,"reason":"No current-floor public nursing base for the unassigned nurse","actor_id":id}
		else:
			var local_desks: Array=desks.get(floor_id,[])
			if local_desks.size()!=2: return {"ok":false,"reason":"Expected both retained real desks on the patient's original floor","actor_id":id,"desks":local_desks}
			var ordinal: int=int(patient_ordinals.get(floor_id,0))
			patient_ordinals[floor_id]=ordinal+1
			var desk_id: String=str(local_desks[ordinal%local_desks.size()])
			anchor={"kind":"current_floor_guidance_nearby","source_id":desk_id,"source_field":"facility_layout.patient_cell","floor_id":floor_id,"cell":sim.space.facility_layout(world,desk_id).patient_cell.duplicate(),"floor_patient_ordinal":ordinal,"basis":"Alternating initial proximity only; no desk selection, queue number or arrival is supplied."}
		var origin: Vector2=Vector2(float(anchor.cell[0]),float(anchor.cell[1]))
		var order_key: String=JSON.stringify([anchor.cell,patient])
		if not ordered.has(order_key):
			var options: Array=candidates.duplicate()
			options.sort_custom(func(a:Array,b:Array)->bool:
				# Initial scene distribution only. Prefer walking gaps between
				# fresh patients; every remaining cell is still a legal candidate.
				if patient:
					var preferred_a: bool=int(a[0])%2==0 and int(a[1])%2==0
					var preferred_b: bool=int(b[0])%2==0 and int(b[1])%2==0
					if preferred_a!=preferred_b: return preferred_a
				var da: float=Vector2(float(a[0]),float(a[1])).distance_squared_to(origin)
				var db: float=Vector2(float(b[0]),float(b[1])).distance_squared_to(origin)
				return da<db if da!=db else int(a[1])<int(b[1]) if a[1]!=b[1] else int(a[0])<int(b[0]))
			ordered[order_key]=options
		var cell: Array=[]
		var checked: int=0
		for candidate: Array in ordered[order_key]:
			checked+=1
			if _initial_public_cell(sim,id,floor_id,candidate,rooms.get(floor_id,[])):
				cell=candidate;break
		if cell.is_empty(): return {"ok":false,"reason":"No complete same-floor public body position; preserve all bodies and workload","actor_id":id,"records":records}
		actor.location.cell=cell.duplicate()
		expected.actors[id].location=actor.location.duplicate(true)
		sim.space.sync_actor(world,id)
		var bounds: Rect2=sim.space.body_rectangle(actor)
		same_floors=same_floors and int(actor.location.floor_id)==int(original.floor_id)
		records.append({"actor_id":id,"role":world.facts.staff[id].role if world.facts.staff.has(id) else "patient","original_location":original,"declared_location":actor.location.duplicate(true),"anchor":anchor,"patient_grid_preference_cells":2 if patient else 0,"original_anchor_distance_cells":Vector2(float(original.cell[0]),float(original.cell[1])).distance_to(origin),"declared_anchor_distance_cells":Vector2(float(cell[0]),float(cell[1])).distance_to(origin),"checked_candidates":checked,"body_dimensions":sim.space.body(actor).duplicate(true),"bounds_size_cells":[bounds.size.x,bounds.size.y]})
	world.touch(false);expected.world_revision=world.revision
	var unchanged: bool=expected==world.facts
	var clear: bool=true
	for id: String in actors:
		var actor: Dictionary=world.facts.actors[id]
		clear=clear and _initial_public_cell(sim,id,int(actor.location.floor_id),actor.location.cell,rooms.get(int(actor.location.floor_id),[]))
	var validation: String=world.validate(sim.content)
	var building: String=sim.services.building.validate(world)
	var schedule: String=sim.clinic.scheduler.validate(world)
	return {"ok":actors.size()==expected_count and same_floors and unchanged and clear and validation.is_empty() and building.is_empty() and schedule.is_empty(),"phase":phase,"tick":world.sim_tick,"count":actors.size(),"same_floors":same_floors,"only_locations_and_revision_changed":unchanged,"all_full_bodies_public_and_clear":clear,"candidate_cells_per_anchor":candidates.size(),"validation":validation,"building_validation":building,"schedule_validation":schedule,"records":records,"boundary":"Initial same-floor location declaration after construction and before this cohort participates in its first real simulation step. Existing employee moves, actual posts and progress are not changed or audited as public waiting positions. All floor-grid candidates remain available. Patients prefer the even-coordinate grid, then all candidates follow the recorded anchor distance, y and x; no nearest-N cutoff or runtime cache. No companion, body, journey, attendance, progress, reservation or random fact is supplied or changed."}

func _initial_public_cell(sim: HospitalSimulation, id: String, floor_id: int, cell: Array, rooms: Array) -> bool:
	var bounds: Rect2=sim.space._actor_rect(sim.world.facts.actors[id],Vector2(float(cell[0]),float(cell[1])))
	for room: Dictionary in rooms:
		if BuildGeometry.intersects_room(bounds,room): return false
	var entry: Dictionary=sim.world.facts.entry
	if floor_id==int(entry.floor_id):
		for key: String in ["cell","exit_cell"]:
			var point: Array=entry[key]
			if bounds.intersects(Rect2(float(point[0]),float(point[1]),1,1).grow(1.0),false): return false
	return sim.space.public_areas.safe_wait(sim.world,id,floor_id,cell)

func _comprehensive_rules(sim: HospitalSimulation) -> Dictionary:
	var world: WorldState=sim.world
	var failures: Array=[]
	var readiness: Array=[]
	var building: String=sim.services.building.validate(world)
	if not building.is_empty(): failures.append(building)
	var schedule: String=sim.clinic.scheduler.validate(world)
	if not schedule.is_empty(): failures.append(schedule)
	var roles: Dictionary={}
	for staff: Dictionary in world.facts.staff.values(): roles[staff.role]=int(roles.get(staff.role,0))+1
	if roles!={"doctor":15,"nurse":12,"cleaner":4,"researcher":1}: failures.append("Initial staff roles differ from the declared complete 32-person cohort")
	var gentle: Dictionary=world.facts.facilities.get("comprehensive_c_gentle",{})
	var gentle_doctor: Dictionary=world.facts.staff.get("bench_staff_0000",{})
	if gentle.get("definition_id","")!="M17" or not sim.clinic.service_room_reason(world,gentle).is_empty() or int(gentle_doctor.get("abilities",{}).get("treatment",0))<3 or not sim.clinic._schedule_allows(world,"bench_staff_0000","outpatient",{},"comprehensive_c_gentle"): failures.append("The C palliative station has no lawful level-3 GP-room operator")
	for room: Dictionary in world.facts.rooms.values():
		var reason: String=sim.space.room_use.reason(world,room.id)
		if not reason.is_empty(): readiness.append({"room_id":room.id,"kind":room.kind,"reason":reason})
	# Unstaffed rooms and optional spare rooms remain installed and eligible.
	# Their mere presence never establishes actual coverage or legal capacity.
	var clinical: Array=[]
	for room_id: String in ["bench_room_1_00","bench_room_3_00","bench_room_1_01","bench_room_1_02","bench_room_1_03","bench_room_3_02","bench_room_3_03","bench_room_4_14"]:
		var reason: String=sim.space.room_use.reason(world,room_id)
		clinical.append({"room_id":room_id,"facility_reason":reason})
		if not reason.is_empty(): failures.append("Required active room is not facility-ready: "+room_id+" "+reason)
	return {"ok":failures.is_empty(),"failures":failures,"roles":roles,"active_room_facility_readiness":clinical,"spare_room_readiness_gaps":readiness,"room_coverage":sim.clinic.scheduler.room_coverage(world),"scope":"Real template/role/room facilities checked; live qualification, attendance, nursing preparation and work remain production checks."}
