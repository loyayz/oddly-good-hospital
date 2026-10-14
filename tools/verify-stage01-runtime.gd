extends SceneTree

var _failures: Array[String] = []
var _evidence: Dictionary = {"engine":Engine.get_version_info(),"renderer":"headless — simulation/storage only",
	"checks":{},"clinical_traces":{},"artifacts":{}}
var _guard: RefCounted

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var actual_user: String = OS.get_user_data_dir()
	if not "Stage01 验收" in actual_user:
		push_error("Use the isolated feasibility project; product user:// must not be used by this probe.")
		quit(2)
		return
	_guard = ClassDB.instantiate("PlatformSessionGuard") as RefCounted
	var acquired: Dictionary = _guard.call("acquire")
	_check("isolated_guard",acquired.get("ok",false))
	_evidence.actual_user_directory = actual_user
	var content: HospitalContent = HospitalContent.new()
	_check("registered_content",content.error.is_empty())
	var clinic: HospitalWorld = FeasibilityHospitals.create(HospitalSnapshots.uuid(),false,content)
	var surgery: HospitalWorld = FeasibilityHospitals.create(HospitalSnapshots.uuid(),true,content)
	_check("initial_outpatient_invariants",clinic.validate(content).is_empty())
	_check("initial_surgery_invariants",surgery.validate(content).is_empty())
	_run_clinical(clinic,content,6000,"outpatient")
	_run_clinical(surgery,content,12000,"surgery")
	_numerical_cases(content)
	_evidence.clinical_final = {"outpatient":clinic.freeze(),"surgery":surgery.freeze()}
	var first: HospitalSimulation = HospitalSimulation.new(FeasibilityHospitals.create("deterministic",false,content),content)
	var second: HospitalSimulation = HospitalSimulation.new(FeasibilityHospitals.create("deterministic",false,content),content)
	for index: int in 1500:
		first.step()
	for frame: int in 500:
		for index: int in 3:
			second.step()
	_check("same_tick_same_facts_and_rng",JSON.stringify(first.world.facts,"",true,true)==JSON.stringify(second.world.facts,"",true,true))
	var before_preview: String = JSON.stringify(first.world.facts,"",true,true)
	var geometry: HospitalSpace = first.space
	for index: int in 10:
		geometry.route(first.world,"sample_S59",2,[35,80])
	_check("readonly_route_preview",before_preview==JSON.stringify(first.world.facts,"",true,true))
	var command: Dictionary = {"id":"duplicate_move","hospital_id":"deterministic","kind":"move_actor","actor_id":"sample_S21","floor_id":1,"cell":[35,66]}
	first.enqueue(command)
	first.drain_commands()
	var after_command: String = JSON.stringify(first.world.facts,"",true,true)
	first.enqueue(command)
	first.drain_commands()
	_check("duplicate_command_no_effect",after_command==JSON.stringify(first.world.facts,"",true,true))
	_check("three_cell_giant",geometry.clearance(first.world.facts.actors.sample_S59)==3)
	_check("micro_one_actor",first.world.facts.actors.has("sample_S21"))
	_check("ghost_collision_is_real",geometry.clearance(first.world.facts.actors.sample_S14)==1)
	_check("compressed_ten_thousand_floors",first.world.facts.floors.height_intervals.size()==1 and first.world.facts.floors.overrides.size()==2)
	_check("vertical_giant_route",geometry.route(first.world,"sample_S59",2,[35,83]).ok)
	var storage: HospitalSnapshots = HospitalSnapshots.new(content,_guard)
	await _space_cases(content,storage)
	var started: Dictionary = storage.begin(surgery,"probe-surgery","manual","1")
	_check("begin_surgery_save",started.ok)
	var receipt: Dictionary = await _await_save(storage)
	_check("surgery_save_committed",receipt.get("ok",false))
	if receipt.get("ok",false):
		var restored: Dictionary = storage.load_commit(surgery.facts.hospital_id,receipt.snapshot_id)
		_check("restore_exact_world",restored.ok and JSON.stringify(restored.world.facts,"",true,true)==JSON.stringify(surgery.facts,"",true,true))
		_evidence.artifacts.surgery_receipt = receipt
	var frozen: HospitalWorld = FeasibilityHospitals.create(HospitalSnapshots.uuid(),true,content)
	var progress: HospitalSimulation = HospitalSimulation.new(frozen,content)
	var checkpoints: Dictionary = {}
	for index: int in 6000:
		progress.step()
		var visit: Dictionary = frozen.facts.visits.values()[0]
		if visit.phase in ["gp","surgery","wake","transfer","recovery","round"] and not checkpoints.has(visit.phase):
			checkpoints[visit.phase] = frozen.freeze()
	for phase: String in checkpoints:
		var midway: HospitalWorld = HospitalWorld.new(checkpoints[phase])
		var request: Dictionary = storage.begin(midway,"probe-midway","manual",phase)
		_check("save_started_"+phase,request.ok)
		var saved: Dictionary = await _await_save(storage)
		_check("save_committed_"+phase,saved.get("ok",false))
		if not saved.get("ok",false):
			continue
		var restored: Dictionary = storage.load_commit(midway.facts.hospital_id,saved.snapshot_id)
		_check("restore_midway_"+phase,restored.ok and JSON.stringify(midway.facts,"",true,true)==JSON.stringify(restored.world.facts,"",true,true))
		if restored.ok:
			var resumed: HospitalSimulation = HospitalSimulation.new(restored.world,content)
			var original: HospitalSimulation = HospitalSimulation.new(midway,content)
			for tick: int in 200:
				original.step()
				resumed.step()
			_check("resume_same_tick_"+phase,JSON.stringify(midway.facts,"",true,true)==JSON.stringify(restored.world.facts,"",true,true))
			if JSON.stringify(midway.facts,"",true,true)!=JSON.stringify(restored.world.facts,"",true,true):
				_evidence["resume_difference_"+phase] = _differences(midway.facts,restored.world.facts,"",[])
	_evidence.midway_phases = checkpoints.keys()
	_evidence.checks_pass = _failures.is_empty()
	_evidence.failures = _failures
	_evidence.observed_at_utc = Time.get_datetime_string_from_system(true)
	var output: FileAccess = FileAccess.open("res://runtime-evidence.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(_evidence,"\t",true,true))
	output.close()
	_guard.call("release")
	print("STAGE01_RUNTIME_PASS="+str(_failures.is_empty())+"; CHECKS="+str(_evidence.checks.size()))
	quit(0 if _failures.is_empty() else 1)

func _await_save(storage: HospitalSnapshots) -> Dictionary:
	while storage.busy():
		await process_frame
		var receipt: Dictionary = storage.poll()
		if not receipt.is_empty():
			return receipt
	return {"ok":false,"error":"missing receipt"}

func _run_clinical(world: HospitalWorld, content: HospitalContent, ticks: int, kind: String) -> void:
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	var trace: Array[Dictionary] = []
	var previous: String = ""
	for index: int in ticks:
		simulation.step()
		var visit: Dictionary = world.facts.visits.values()[0]
		if visit.phase != previous:
			trace.append({"tick":world.facts.sim_tick,"phase":visit.phase,"money":world.money(),"packages":world.facts.inventory.units})
			print(kind+" tick="+str(world.facts.sim_tick)+" phase="+str(visit.phase))
			previous = visit.phase
	_evidence.clinical_traces[kind] = trace
	var visit: Dictionary = world.facts.visits.values()[0]
	_check(kind+"_departed",visit.phase=="departed")
	_check(kind+"_actual_cure",visit.final_result=="cured")
	_check(kind+"_maximum_attempts",visit.attempt_ids.size()<=2)
	_check(kind+"_post_clinical_invariants",world.validate(content).is_empty())
	if kind == "surgery":
		_check("ward_release_after_departure",world.facts.ward_stays.is_empty())
		_check("ward_real_care_and_round",world.facts.staff.ward_nurse.practice.care>0 and world.facts.staff.round_doctor.practice.treatment>0)
	var supplies: int = 0
	for attempt: Dictionary in world.facts.attempts.values():
		supplies += int(attempt.supply_units)
	_check(kind+"_inventory_issued_once",60-int(world.facts.inventory.units)==supplies and world.facts.inventory.issues.size()==world.facts.attempts.size())
	var cure_entries: int = 0
	var cure_amount: int = 0
	for entry: Dictionary in world.facts.ledger.entries.values():
		if entry.component=="cure":
			cure_entries += 1
			cure_amount += int(entry.amount)
	_check(kind+"_single_success_charge",cure_entries==1 and cure_amount==ceili(float(content.definition("diseases",visit.disease_id).cure_fee)*(1.8 if kind=="surgery" else 1.0)))
	_evidence[kind+"_settlement"] = {"money":world.money(),"packages":world.facts.inventory.units,"attempt_count":world.facts.attempts.size(),"cure_charge":cure_amount,"ledger":world.facts.ledger.entries}

func _numerical_cases(content: HospitalContent) -> void:
	for case: String in ["stock","qualification","bed","research"]:
		var world: HospitalWorld = FeasibilityHospitals.create(HospitalSnapshots.uuid(),true,content)
		match case:
			"stock": world.facts.inventory.units = 9
			"qualification": world.facts.staff.or_nurse.certificates.erase("q_or")
			"bed": world.facts.facilities.bed.failed = true
			"research": world.facts.research.erase(str(content.definition("treatment_plans","P_D23_SURGERY").requires_research[0]))
		var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
		for tick: int in 1700:
			simulation.step()
		var visit: Dictionary = world.facts.visits.values()[0]
		_check("no_unready_attempt_"+case,world.facts.attempts.is_empty() and world.facts.inventory.issues.is_empty() and not visit.ticket_id.is_empty())
		_evidence["unready_"+case] = visit.waiting_reason
	var paused: HospitalWorld = FeasibilityHospitals.create(HospitalSnapshots.uuid(),false,content)
	var simulation: HospitalSimulation = HospitalSimulation.new(paused,content)
	for tick: int in 1700:
		simulation.step()
		if not paused.facts.attempts.is_empty():
			break
	var attempt: Dictionary = paused.facts.attempts.values()[0]
	var before: String = JSON.stringify(attempt,"",true,true)
	var supply_before: int = int(paused.facts.inventory.units)
	var rng_before: String = paused.facts.rng.treatment.state_decimal
	var session: Dictionary = paused.facts.sessions.values()[0]
	var remaining: int = int(session.remaining_ticks)
	paused.facts.facilities.treatment.failed = true
	paused.facts.staff.treat_doctor.abilities.treatment = 5
	for tick: int in 10:
		simulation.step()
	_check("equipment_failure_preserves_frozen_attempt",before==JSON.stringify(attempt,"",true,true) and int(session.remaining_ticks)==remaining and int(paused.facts.inventory.units)==supply_before and paused.facts.rng.treatment.state_decimal==rng_before)
	paused.facts.facilities.treatment.failed = false
	for tick: int in 1700:
		simulation.step()
	_check("equipment_recovery_continues_original_attempt",paused.facts.visits.values()[0].phase=="departed" and paused.facts.attempts.size()==1 and paused.facts.inventory.issues.size()==1)
	var prepare: HospitalWorld = FeasibilityHospitals.create(HospitalSnapshots.uuid(),true,content)
	var prepare_sim: HospitalSimulation = HospitalSimulation.new(prepare,content)
	for tick: int in 1700:
		prepare_sim.step()
		if not prepare.facts.preparations.is_empty():
			break
	var ticket: String = prepare.facts.visits.values()[0].ticket_id
	prepare.facts.facilities.bed.failed = true
	prepare_sim.step()
	_check("invalidated_preparation_releases_resources_keeps_ticket",prepare.facts.preparations.is_empty() and prepare.facts.attempts.is_empty() and prepare.facts.visits.values()[0].ticket_id==ticket)
	for case: String in ["rng_overflow","room_extent","dangling_visit","missing_species","position_conflict","missing_door","dangling_ledger"]:
		var invalid: HospitalWorld = FeasibilityHospitals.create(HospitalSnapshots.uuid(),true,content)
		match case:
			"rng_overflow": invalid.facts.rng.treatment.state_decimal = "9223372036854775808"
			"room_extent": invalid.facts.rooms.ward.size = [-1,8]
			"dangling_visit": invalid.facts.visits.values()[0].actor_id = "missing"
			"missing_species": invalid.facts.actors.patient.species_id = "missing"
			"position_conflict": invalid.facts.actors.patient.location.connector_id = "lift"
			"missing_door": invalid.facts.floors.overrides["1"].doors[0].definition_id = "missing"
			"dangling_ledger": invalid.facts.ledger.entries["missing:test"] = {"owner_id":"missing","component":"test","amount":1,"tick":0,"settled":true}
		_check("invalid_dto_rejected_"+case,not invalid.validate(content).is_empty())

func _check(name: String, passed: bool) -> void:
	_evidence.checks[name] = passed
	if not passed:
		_failures.append(name)
		push_error("Stage01 feasibility failure: "+name)

func _differences(a: Variant, b: Variant, path: String, result: Array) -> Array:
	if result.size()>=16:
		return result
	if a is Dictionary and b is Dictionary:
		for key: String in a:
			_differences(a[key],b.get(key),path+"/"+key,result)
	elif a is Array and b is Array and a.size()==b.size():
		for index: int in a.size():
			_differences(a[index],b[index],path+"/"+str(index),result)
	elif JSON.stringify(a,"",true,true)!=JSON.stringify(b,"",true,true):
		result.append({"path":path,"original":a,"restored":b})
	return result

func _space_cases(content: HospitalContent, storage: HospitalSnapshots) -> void:
	var narrow: HospitalWorld = FeasibilityHospitals.create(HospitalSnapshots.uuid(),false,content)
	var geometry: HospitalSpace = HospitalSpace.new(content)
	narrow.facts.actors.sample_S14.location = {"kind":"floor","floor_id":2,"cell":[35,70],"height_m":0.0}
	_check("ghost_legal_one_cell_corridor",geometry.route(narrow,"sample_S14",2,[50,70]).ok)
	narrow.facts.floors.overrides["2"].blocked.append([50,70])
	_check("transparent_body_cannot_cross_wall",not geometry.route(narrow,"sample_S14",2,[50,70]).ok)
	_check("giant_cannot_use_one_cell_corridor",not geometry.route(narrow,"sample_S59",2,[50,70]).ok)
	var tall: HospitalWorld = FeasibilityHospitals.create(HospitalSnapshots.uuid(),false,content)
	tall.facts.connectors.erase("lift")
	_check("tall_body_rejected_by_fixed_stair_clear_height",not geometry.route(tall,"sample_S55",2,[35,70]).ok)
	_check("human_can_use_same_fixed_stair",geometry.route(tall,"patient",2,[35,70]).ok)
	var transit: HospitalWorld = FeasibilityHospitals.create(HospitalSnapshots.uuid(),false,content)
	var simulation: HospitalSimulation = HospitalSimulation.new(transit,content)
	_check("real_giant_transit_requested",simulation.space.request_move(transit,"sample_S59",2,[35,83]).is_empty())
	var in_cabin: Dictionary = {}
	for tick: int in 1400:
		simulation.step()
		if transit.facts.actors.sample_S59.location.kind=="transit":
			in_cabin = transit.freeze()
			break
	_check("actual_transit_body_exclusive",not in_cabin.is_empty() and not in_cabin.actors.sample_S59.location.has("cell"))
	if not in_cabin.is_empty():
		var travelling: HospitalWorld = HospitalWorld.new(in_cabin)
		var started: Dictionary = storage.begin(travelling,"space-transit","manual","transit")
		_check("transit_save_started",started.ok)
		var receipt: Dictionary = await _await_save(storage)
		_check("transit_save_committed",receipt.get("ok",false))
		if receipt.get("ok",false):
			var restored: Dictionary = storage.load_commit(travelling.facts.hospital_id,receipt.snapshot_id)
			_check("transit_restored_exact",restored.ok and JSON.stringify(travelling.facts,"",true,true)==JSON.stringify(restored.world.facts,"",true,true))
			if restored.ok:
				var a: HospitalSimulation = HospitalSimulation.new(travelling,content)
				var b: HospitalSimulation = HospitalSimulation.new(restored.world,content)
				for tick: int in 600:
					a.step()
					b.step()
				_check("transit_resume_same_facts",JSON.stringify(travelling.facts,"",true,true)==JSON.stringify(restored.world.facts,"",true,true))
				_check("transit_real_exit_on_second_floor",travelling.facts.actors.sample_S59.location.kind=="floor" and int(travelling.facts.actors.sample_S59.location.floor_id)==2)
	var fit_world: HospitalWorld = FeasibilityHospitals.create(HospitalSnapshots.uuid(),true,content)
	fit_world.facts.floors.overrides["2"].blocked = []
	fit_world.facts.rooms["fit_room"] = {"id":"fit_room","kind":"ward","floor_id":2,"origin":[34,84],"size":[14,11]}
	var door: Dictionary = {"id":"fit_door","definition_id":"DR01","cell":[38,83],"span":1,"axis":"x","room_id":"fit_room","active_actor_id":"","clear_height_m":2.2}
	fit_world.facts.floors.overrides["2"].doors = [door]
	for x: int in range(33,49):
		if x!=38:
			fit_world.facts.floors.overrides["2"].blocked.append([x,83])
	fit_world.facts.actors.sample_S59.location = {"kind":"floor","floor_id":2,"cell":[38,86],"height_m":0.0}
	var fit: Dictionary = geometry.door_quote(fit_world,fit_world.facts.actors.sample_S59,2,door)
	_check("door_real_automatic_span_and_height",fit.ok and int(fit.span)==3 and absf(float(fit.clear_height_m)-6.3)<0.00001)
	var run: HospitalSimulation = HospitalSimulation.new(fit_world,content)
	_check("giant_door_route",run.space.request_move(fit_world,"sample_S59",2,[38,80]).is_empty())
	var active_door: Dictionary = {}
	for tick: int in 100:
		run.step()
		if fit_world.facts.adaptations.has(door.id):
			active_door = fit_world.freeze()
			break
	_check("door_extent_is_real_reservation",not active_door.is_empty() and int(active_door.adaptations[door.id].span)==3)
	_evidence.artifacts.door_world = active_door
	var bed: Dictionary = fit_world.facts.facilities.bed.duplicate(true)
	bed.id = "fit_bed"
	bed.floor_id = 2
	bed.cell = [37,86]
	bed.patient_cell = [37,89]
	bed.operator_cells = [[36,87],[40,87]]
	bed.repair_cell = [36,86]
	bed.room_id = "fit_room"
	fit_world.facts.facilities[bed.id] = bed
	fit_world.facts.moves.erase("sample_S59")
	fit_world.facts.adaptations.erase(door.id)
	fit_world.facts.actors.sample_S59.location = {"kind":"floor","floor_id":2,"cell":[37,92],"height_m":0.0}
	var before: String = JSON.stringify(fit_world.facts,"",true,true)
	var preview: Dictionary = geometry.facility_quote(fit_world,bed.id,"sample_S59",["ward_nurse","round_doctor"])
	_check("giant_bed_preview_is_three_by_five",preview.ok and preview.footprint==[3,5])
	_check("adaptation_preview_read_only",before==JSON.stringify(fit_world.facts,"",true,true))
	var reserved: String = geometry.reserve_facility(fit_world,bed.id,"sample_S59","sample_S59",["ward_nurse","round_doctor"])
	_check("expanded_bed_is_actual_obstacle",reserved.is_empty() and not geometry.static_reason(fit_world,fit_world.facts.actors.sample_S14,2,Vector2i(37,90)).is_empty())
	if reserved.is_empty():
		var service: HospitalClinic = HospitalClinic.new(content,geometry)
		service._support(fit_world,{"actor_id":"sample_S59"},geometry.facility_layout(fit_world,bed.id),"lying")
		_check("giant_body_physically_supported_without_scale",fit_world.facts.actors.sample_S59.posture=="lying" and geometry.overlaps_facility(fit_world,"sample_S59",bed.id))
		_evidence.artifacts.expanded_bed_world = fit_world.freeze()
		var started: Dictionary = storage.begin(fit_world,"space-bed","manual","expanded")
		_check("expanded_bed_save_started",started.ok)
		var receipt: Dictionary = await _await_save(storage)
		_check("expanded_bed_save_committed",receipt.get("ok",false))
		if receipt.get("ok",false):
			var restored: Dictionary = storage.load_commit(fit_world.facts.hospital_id,receipt.snapshot_id)
			_check("expanded_bed_restored_with_reservation",restored.ok and JSON.stringify(fit_world.facts,"",true,true)==JSON.stringify(restored.world.facts,"",true,true))
	var blocked: HospitalWorld = HospitalWorld.new(fit_world.freeze())
	blocked.facts.adaptations.erase(bed.id)
	blocked.facts.actors.sample_S59.location = {"kind":"floor","floor_id":2,"cell":[37,92],"height_m":0.0}
	blocked.facts.actors.sample_S59.posture = "standing"
	blocked.facts.floors.overrides["2"].blocked.append([37,90])
	var refused: Dictionary = geometry.facility_quote(blocked,bed.id,"sample_S59",["ward_nurse","round_doctor"])
	_check("blocked_extension_refused",not refused.ok)
	_evidence.artifacts.blocked_extension_reason = refused.get("reason","")
