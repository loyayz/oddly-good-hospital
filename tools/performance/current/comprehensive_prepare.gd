extends "res://tools/performance/acceptance/fixtures/prepare_inputs.gd"

const Operations = preload("res://tools/performance/current/comprehensive_operations.gd")
const SCENARIO: String = "comprehensive160-v1"
var _setup: Dictionary = {"commands":[],"initial_cohorts":[],"added_facilities":[],"moved_facilities":[],"errors":[],"limitations":[]}

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
	if FileAccess.file_exists(output): push_error("Preserve the existing fixed input; choose a new directory.");quit(2);return
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
	var original_rooms: Array=world.facts.rooms.keys()
	var original_definitions: Dictionary={}
	for id: String in world.facts.facilities: original_definitions[id]=world.facts.facilities[id].definition_id
	# This is the initial, pre-step hospital boundary. No existing employee or
	# patient is removed, and no completed service/progress is manufactured.
	var researcher: Dictionary=world.facts.staff[Operations.RESEARCHER]
	researcher.role="researcher";researcher.title_id="";researcher.certificates=[]
	researcher.abilities={"diagnosis":0,"treatment":0,"care":0,"surgery":0}
	researcher.schedule=[{"kind":"work","pools":["bench_room_4_14"],"locked":false},{"kind":"work","pools":["bench_room_4_14"],"locked":false},{"kind":"rest","pools":[],"locked":false}]
	var student: Dictionary=world.facts.staff[Operations.STUDENT]
	student.title_id="DT01";student.abilities.treatment=0
	_setup.staff_initial_conditions={"researcher":Operations.RESEARCHER,"student":Operations.STUDENT,"student_treatment_level":0,"cleaners_preserved":4,"boundary":"Initial employee qualifications; no work, preparation, practice or attendance supplied."}
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
	# Historical diagnostic evidence is a legal input boundary, never measured
	# diagnostic work. Fresh GP cohorts below still execute complete real service.
	for index: int in 20:
		var visit: Dictionary=world.facts.visits["bench_visit_%04d"%index]
		var kind: String="surgery" if index<8 else ("outpatient" if index<16 else ("spectrum" if index<18 else "resonance"))
		if kind in ["spectrum","resonance"]:
			# Select actual catalog B/C bindings. Prefer the existing species,
			# then the canonical staff-sized species; no profile is inferred
			# from a disease number or from an earlier content release.
			var binding: Dictionary=_diagnostic_binding(content,"B" if kind=="spectrum" else "C")
			if binding.is_empty(): return {"ok":false,"reason":"No legal catalog binding for diagnostic cohort","kind":kind}
			visit.binding_id=binding.id;visit.disease_id=binding.disease_id
			world.facts.actors[visit.actor_id].species_id=binding.species_id
			world.facts.actors[visit.actor_id].body_binding_id=visit.binding_id
		var profile: Dictionary=content.catalog.profiles[content.definition("diseases",visit.disease_id).profile]
		# Input history uses a diagnosis-level-2 doctor and an unupgraded
		# diagnostic table: effective equipment grade is exactly zero.
		var gp_evidence: float=minf(100.0,float(profile.gp_confidence)+2.0)
		var spectrum_evidence: float=float(content.balance.tests.spectrum.confidence)+2.0
		visit.evidence_by_source={"gp":gp_evidence}
		var sum_evidence: float=gp_evidence
		if kind=="resonance" or (not kind in ["spectrum","resonance"] and sum_evidence<float(content.balance.diagnosis_threshold)):
			visit.evidence_by_source.spectrum=spectrum_evidence;sum_evidence+=spectrum_evidence
		if not kind in ["spectrum","resonance"] and sum_evidence<float(content.balance.diagnosis_threshold):
			visit.evidence_by_source.resonance=float(content.balance.tests.resonance.confidence)+2.0
			sum_evidence+=float(visit.evidence_by_source.resonance)
		if (kind in ["spectrum","resonance"] and sum_evidence>=float(content.balance.diagnosis_threshold)) or (not kind in ["spectrum","resonance"] and sum_evidence<float(content.balance.diagnosis_threshold)):
			return {"ok":false,"reason":"Selected diagnostic history does not legally precede its next service","kind":kind,"evidence":sum_evidence}
		visit.doctor_fee_quote=content.doctor_fee("DT02")
		visit.requested_plan_id="P_D09_SURGERY" if kind=="surgery" else "P_D09_COMMON"
		if kind in ["spectrum","resonance"]: visit.requested_plan_id="P_"+str(visit.disease_id)+"_COMMON"
		if not kind in ["spectrum","resonance"]: visit.plan_decision={"plan_id":visit.requested_plan_id,"source":"director","revision":1,"reason":"Saved, diagnosed patient before unstarted service"}
		for component: String in ["consultation","gp","spectrum","resonance"]:
			if component!="consultation" and not visit.evidence_by_source.has(component): continue
			var amount: int=int(visit.doctor_fee_quote) if component=="consultation" else content.facility_fee("FUR02",component)
			var paid: CommandResult=HospitalLedger.post(world,LedgerEntry.new(visit.id,component,amount))
			if not paid.accepted: return {"ok":false,"reason":"Initial historical diagnosis receipt rejected","receipt":paid.to_record()}
		_setup.initial_cohorts.append({"visit_id":visit.id,"binding_id":visit.binding_id,"profile":content.definition("diseases",visit.disease_id).profile,"initial_species_id":world.facts.actors[visit.actor_id].species_id,"initial_location":world.facts.actors[visit.actor_id].location.duplicate(true),"next_service":kind,"evidence":visit.evidence_by_source.duplicate(),"diagnostic_input_basis":{"profile_gp_confidence":profile.gp_confidence,"doctor_diagnosis":2,"equipment_effective_grade":0,"spectrum_confidence":content.balance.tests.spectrum.confidence},"scope":"Requirement-defined saved patient before its unstarted next service. Historical evidence and fees are input only; excluded from every observed service/receipt delta."})
	if not _fresh_gp_inputs(world,content): return {"ok":false,"reason":"Fresh profile-B input is not legal","setup":_setup}
	for actor_id: String in fixture.visitor_ids:
		if not _unowned_placeholder(world,actor_id): return {"ok":false,"reason":"Refuse replacing an owned companion","actor_id":actor_id}
		world.facts.actors.erase(actor_id)
	fixture.visitor_ids.clear();world.touch()
	var sim: HospitalSimulation=HospitalSimulation.new(world,content)
	if not _layout(sim):
		var failed: Dictionary={"ok":false,"reason":"Initial lawful construction failed","setup":_setup};sim.dispose();return failed
	for row: Dictionary in _setup.initial_cohorts: sim.clinic._queue(world,world.facts.visits[row.visit_id],row.next_service)
	_setup.initial_deployment=_deploy_initial_core(sim)
	if not _setup.initial_deployment.ok:
		sim.dispose();return {"ok":false,"reason":"Initial public-corridor deployment failed","setup":_setup}
	for row: Dictionary in _setup.initial_cohorts+_setup.fresh_gp_cohorts:
		row.initial_location=world.facts.actors[world.facts.visits[row.visit_id].actor_id].location.duplicate(true)
	# A physically worn spare device is an operation-before input. Automatic
	# dispatch remains enabled; a premature completion will be reported honestly.
	world.facts.facilities[Operations.MAINTENANCE_ITEM].condition=float(content.balance.maintenance_dispatch.manual_threshold)
	_setup.maintenance_input={"id":Operations.MAINTENANCE_ITEM,"condition":world.facts.facilities[Operations.MAINTENANCE_ITEM].condition}
	var stock_limit: int=sim.services.supplies.capacity(world)
	world.facts.inventory.units=mini(200,stock_limit-20)
	_setup.supply_input={"units":world.facts.inventory.units,"capacity":stock_limit,"purchase_units":20,"boundary":"Initial legal stock below installed capacity, replacing Fixture's 10000-unit construction convenience. No supply capacity, consumption requirement, candidate, reservation or replenishment rule is changed; not a performance optimization."}
	if int(world.facts.inventory.units)<20: sim.dispose();return {"ok":false,"reason":"Insufficient lawful supply capacity for the complete clinical cohorts and purchase."}
	# Dirt appears through the real event owner at legal ground locations. Its
	# complete worker selection, route, use and receipts are not prefilled.
	for floor_id: int in [1,2,3,4]:
		for index: int in 4:
			var source: String="comprehensive-initial-dirt-%d-%d"%[floor_id,index]
			var dirt: String=sim.services.environment.spawn_dirt(world,"CL01",source,source+":scatter",floor_id,[40+index*2,83])
			if dirt.is_empty(): _setup.errors.append("No lawful initial dirt location: "+source)
	var visitor_service: HospitalVisitors=sim.clinic.visitors
	var visits: Array=world.active_visit_ids()
	for id: String in visits: world.facts.visits[id].companion_intent=false
	for index: int in 8:
		var visit: Dictionary=world.facts.visits[visits[visits.size()-1-index]]
		visit.companion_intent=true;visitor_service._request(world,visit,"companion","")
	_enqueue_setup(sim,"intake-close","arrivals_intake",{"open":false})
	while world.facts.visitors.stays.size()<8:
		var eligible: Array=_companion_request_ids(world)
		if eligible.is_empty(): sim.dispose();return {"ok":false,"reason":"Actual companion requests exhausted","setup":_setup}
		var request_id: String=eligible[0]
		var request: Dictionary=world.facts.visitors.requests[request_id]
		if visitor_service._admit(world,world.facts.visits[request.visit_id],request): world.facts.visitors.requests.erase(request_id)
		else:
			var advanced: Dictionary=await _advance(sim)
			if not advanced.ok: sim.dispose();return advanced.merged({"setup":_setup})
	for stay: Dictionary in world.facts.visitors.stays.values(): fixture.visitor_ids.append(str(stay.actor_id))
	_enqueue_setup(sim,"intake-open","arrivals_intake",{"open":true})
	var advanced: Dictionary=await _advance(sim)
	if not advanced.ok: sim.dispose();return advanced
	var retained: bool=true
	for id: String in original_rooms: retained=retained and world.facts.rooms.has(id)
	for id: String in original_definitions: retained=retained and world.facts.facilities.has(id) and world.facts.facilities[id].definition_id==original_definitions[id]
	var validation: String=world.validate(content)
	var population: Dictionary=population_of(world)
	var layout: Dictionary=_layout_counts(world)
	var beds: int=world.facility_ids("EQ05").size()
	var rules: Dictionary=_comprehensive_rules(sim)
	var ok: bool=validation.is_empty() and rules.ok and _setup.errors.is_empty() and retained and beds==24 and layout.props==1200 and population.staff==32 and population.patients==120 and population.visitors==8 and population.present==160 and _companion_profiles_valid(world,fixture.visitor_ids)
	var identity: Dictionary=_identity()
	for path: String in ["res://tools/performance/current/comprehensive_prepare.gd","res://tools/performance/current/comprehensive_operations.gd","res://tools/performance/current/comprehensive_observer.gd"]: identity.sources[path]=FileAccess.get_sha256(path)
	var metadata: Dictionary={"ok":ok,"population":population,"layout":layout,"care_beds":beds,"original_entities_retained":retained,"room_rules":rules,"setup":_setup,"validation":validation,"actual_preparation_steps":_steps,"source_tick":world.sim_tick,"scenario":SCENARIO,"identity":identity}
	if ok:
		var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
		if file==null: sim.dispose();return {"ok":false,"reason":"Cannot publish new complete input"}
		file.store_var({"content_fingerprint":content.content_fingerprint,"facts":world.freeze(),"floors":fixture.floors,"visitor_ids":fixture.visitor_ids,"fixture_migration":fixture.migration,"scenario":SCENARIO,"comprehensive_setup":_setup})
		file.close();metadata.input=output;metadata.input_sha256=FileAccess.get_sha256(output)
	else:
		var file: FileAccess=FileAccess.open(output+".blocked.bin",FileAccess.WRITE)
		if file!=null: file.store_var({"facts":world.freeze(),"setup":_setup});file.close()
	sim.dispose();return metadata

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

func _enqueue_setup(sim: HospitalSimulation, key: String, kind: String, payload: Dictionary) -> void:
	sim.enqueue({"id":"comprehensive-setup-"+key,"hospital_id":sim.world.hospital_id,"expected_revision":sim.world.revision,"kind":kind,"typed_payload":payload,"loading_session_id":"comprehensive160"})

func _diagnostic_binding(content: HospitalContent, profile: String) -> Dictionary:
	for species: String in ["S13","S49"]:
		for binding: Dictionary in content.catalog.treatment_bindings:
			if binding.species_id==species and content.definition("diseases",binding.disease_id).profile==profile:
				return binding
	return {}

func _fresh_gp_inputs(world: WorldState, content: HospitalContent) -> bool:
	_setup.fresh_gp_cohorts=[]
	var binding: Dictionary=content.definition("treatment_bindings","B_S13_D53_M51")
	var plan: Dictionary=content.definition("treatment_plans","P_D53_COMMON")
	if binding.get("species_id","")!="S13" or binding.get("disease_id","")!="D53" or plan.get("disease_id","")!="D53" or content.definition("diseases","D53").get("profile","")!="B":
		_setup.errors.append("Declared fresh B binding, species, disease or plan differs from actual content");return false
	var routine: Dictionary=content.definition("treatment_routines",binding.routine_id)
	if routine.get("equipment_id","")!="M37":
		_setup.errors.append("Fresh B routine no longer uses the installed M37");return false
	for index: int in 20:
		# These are original common-plan patients, preserving every fresh surgery request.
		var visit: Dictionary=world.facts.visits["bench_visit_%04d"%(21+5*index)]
		var actor: Dictionary=world.facts.actors[visit.actor_id]
		if visit.phase!="arrival" or not visit.evidence_by_source.is_empty() or not visit.attempt_ids.is_empty() or not visit.plan_decision.is_empty() or not str(visit.ticket_id).is_empty() or visit.requested_plan_id!="P_D09_COMMON" or actor.species_id!="S13":
			_setup.errors.append("Fresh B patient is not at its original unstarted GP boundary: "+visit.id);return false
		var original_binding: String=visit.binding_id
		var dimensions: Dictionary=content.actor_body(actor)
		visit.binding_id=binding.id;visit.disease_id=binding.disease_id;visit.requested_plan_id=plan.id
		actor.body_binding_id=binding.id
		var actual: Dictionary=content.actor_body(actor)
		if actual!=dimensions:
			_setup.errors.append("Fresh B binding changes the original complete S13 body: "+visit.id);return false
		_setup.fresh_gp_cohorts.append({"visit_id":visit.id,"actor_id":actor.id,"original_binding_id":original_binding,"binding_id":binding.id,"disease_id":binding.disease_id,"profile":"B","species_id":actor.species_id,"body_dimensions":actual,"original_body_dimensions":dimensions,"next_service":"gp","evidence":visit.evidence_by_source.duplicate(),"routine_id":routine.id,"equipment_id":routine.equipment_id,"treatment_seconds":routine.service_seconds,"initial_location":actor.location.duplicate(true),"scope":"Fresh arrival with no diagnosis, ticket, attempt, plan decision or fee supplied. Real GP and subsequent examination/treatment execute normally."})
	return true

func _deploy_initial_core(sim: HospitalSimulation) -> Dictionary:
	var world: WorldState=sim.world
	if world.sim_tick!=0 or not world.facts.moves.is_empty() or not world.facts.visitors.stays.is_empty() or world.facts.actors.size()!=152:
		return {"ok":false,"reason":"Initial locations may only be declared before all movement and real companion admission","tick":world.sim_tick,"actors":world.facts.actors.size()}
	var expected: Dictionary=world.freeze()
	var actors: Array=world.ids("staff").duplicate()
	for index: int in 120: actors.append("bench_patient_%04d"%index)
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
		var order_key: String=JSON.stringify(anchor.cell)
		if not ordered.has(order_key):
			var options: Array=candidates.duplicate()
			options.sort_custom(func(a:Array,b:Array)->bool:
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
		records.append({"actor_id":id,"role":world.facts.staff[id].role if world.facts.staff.has(id) else "patient","original_location":original,"declared_location":actor.location.duplicate(true),"anchor":anchor,"original_anchor_distance_cells":Vector2(float(original.cell[0]),float(original.cell[1])).distance_to(origin),"declared_anchor_distance_cells":Vector2(float(cell[0]),float(cell[1])).distance_to(origin),"checked_candidates":checked,"body_dimensions":sim.space.body(actor).duplicate(true),"bounds_size_cells":[bounds.size.x,bounds.size.y]})
	world.touch(false);expected.world_revision=world.revision
	var unchanged: bool=expected==world.facts
	var clear: bool=true
	for id: String in actors:
		var actor: Dictionary=world.facts.actors[id]
		clear=clear and _initial_public_cell(sim,id,int(actor.location.floor_id),actor.location.cell,rooms.get(int(actor.location.floor_id),[]))
	var validation: String=world.validate(sim.content)
	var building: String=sim.services.building.validate(world)
	var schedule: String=sim.clinic.scheduler.validate(world)
	return {"ok":actors.size()==152 and same_floors and unchanged and clear and validation.is_empty() and building.is_empty() and schedule.is_empty(),"tick":world.sim_tick,"count":actors.size(),"same_floors":same_floors,"only_locations_and_revision_changed":unchanged,"all_full_bodies_public_and_clear":clear,"candidate_cells_per_anchor":candidates.size(),"validation":validation,"building_validation":building,"schedule_validation":schedule,"records":records,"boundary":"Initial same-floor location declaration after real construction and before the first simulation step. Complete floor-grid candidates are ordered by the recorded real business anchor, squared distance, y and x; no nearest-N cutoff or runtime cache. No companion, body, journey, attendance, progress, reservation or random fact is supplied or changed."}

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
