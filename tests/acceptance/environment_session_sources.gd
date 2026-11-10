extends "res://tests/acceptance/environment_direct_query.gd"

const Ops = preload("res://tests/acceptance/operations.gd")
const Clinical = preload("res://tests/acceptance/clinical_fixtures.gd")
const Checkpoints = preload("res://tests/acceptance/checkpoints.gd")
const Batch = preload("res://game/operations/environment_sample_batch.gd")
var _ops: RefCounted
var _clinical: RefCounted
var _tree: SceneTree
var evidence_directory: String = ""
var _running: Dictionary = {}
var _start_evidence: Dictionary = {}

func run_session_sources(tree: SceneTree, database: HospitalContent, selected: Array) -> Dictionary:
	_content = database
	_tree = tree
	_ops = Ops.new();_ops._content = database
	_clinical = Clinical.new();_clinical._content = database
	_clinical._cache = Checkpoints.new(database,"res://tests/acceptance/clinical_fixtures.gd",weakref(_clinical))
	var cases: Dictionary = {"ENV-SESSION-CLINICAL":_session_clinical,"ENV-SESSION-RESUME":_session_resume,"ENV-SESSION-SURGERY":_session_surgery,"ENV-SESSION-INDEX":_session_index,"ENV-SESSION-LAYOUT":_session_layout,"ENV-SESSION-FLOORS":_session_floors,"ENV-SESSION-EMPTY":_session_empty,"ENV-SESSION-RESTORE":_session_restore,"ENV-SESSION-WORKERS":_session_workers,"ENV-SESSION-MEASURE":_session_measure}
	var rows: Dictionary = {}
	for id: String in selected:
		if not cases.has(id): return {"ok":false,"unknown_case":id}
		print("CASE_BEGIN "+id)
		var began: int = Time.get_ticks_usec()
		rows[id] = await cases[id].call()
		rows[id].elapsed_us = Time.get_ticks_usec()-began
		print("CASE_RESULT "+id+" "+JSON.stringify(rows[id]))
	for sim: HospitalSimulation in _ops._live: sim.dispose()
	_ops._live.clear()
	_clinical._dispose_simulations()
	return {"ok":not rows.is_empty() and rows.values().all(func(row: Dictionary)->bool:return row.get("ok",false)),"cases":rows,"fixtures":_clinical._cache.observations}

func _sx(f: Dictionary) -> Dictionary:
	return {"world":f.w,"space":f.s.space,"e":f.s.services.environment}

func _sess(world: WorldState, kind: String) -> Dictionary:
	for record: Dictionary in world.facts.sessions.values():
		if record.kind==kind: return record
	return {}

func _result_checks(checks: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"ok":not checks.is_empty() and not checks.values().has(false),"checks":checks}
	result.merge(extra)
	return result

func _running_copy() -> Dictionary:
	if _running.is_empty():
		var f: Dictionary = _ops._new("环境会话真实开工",true,20000)
		_clinical._seed_stream(f.w,"treatment",true,true,100,100)
		var visit_id: String = _ops._diagnosed_outpatient(f,"env-session-start",[48,92])
		var x: Dictionary = _sx(f)
		var reference: HospitalEnvironment = _reference_for(x)
		var before: Dictionary = _compare_direct(x,reference,[51,88])
		var builds: int = _count(x.space,"session_source_builds")
		var updates: int = _count(x.space,"session_source_updates")
		var start_tick: int = f.w.sim_tick
		for step: int in 1200:
			if not _sess(f.w,"outpatient").is_empty(): break
			_ops._clinic_tick(f)
		var running: Dictionary = _sess(f.w,"outpatient")
		_start_evidence = {"legal_input":not visit_id.is_empty() and f.errors.is_empty(),"warm_empty_noise":before.noise,"before_readonly":before.ok,"start_tick":start_tick,"started_tick":f.w.sim_tick,"real_started":not running.is_empty(),"builds_before":builds,"builds_after":_count(x.space,"session_source_builds"),"updates":_count(x.space,"session_source_updates")-updates,"validation":f.w.validate(_content)}
		if running.is_empty(): return {}
		_start_evidence.running_comparison = _compare_direct(x,reference,[51,88])
		_running = f.w.freeze()
		if not evidence_directory.is_empty():
			var path: String = evidence_directory.path_join("real-outpatient-started.bin")
			if not FileAccess.file_exists(path):
				var snapshot: FileAccess = FileAccess.open(path,FileAccess.WRITE)
				if snapshot!=null: snapshot.store_buffer(var_to_bytes(_running));snapshot.close()
	var world: WorldState = WorldState.new(_running.duplicate(true))
	var sim: HospitalSimulation = HospitalSimulation.new(world,_content)
	_ops._live.append(sim)
	return {"w":world,"s":sim,"errors":[]}

func _session_clinical() -> Dictionary:
	var f: Dictionary = _running_copy()
	if f.is_empty(): return {"ok":false,"prerequisite":_start_evidence}
	var x: Dictionary = _sx(f)
	var reference: HospitalEnvironment = _reference_for(x)
	var session: Dictionary = _sess(f.w,"outpatient")
	var id: String = session.id
	var item: Dictionary = f.w.facts.facilities[session.facility_id]
	var running: Dictionary = _compare_direct(x,reference,[51,88])
	var checks: Dictionary = {"legal_input":_start_evidence.legal_input and _start_evidence.validation.is_empty(),"warm_empty_real_start":_start_evidence.warm_empty_noise==0 and _start_evidence.real_started and _start_evidence.running_comparison.noise==10 and _start_evidence.running_comparison.ok,"start_uses_local_notification":_start_evidence.builds_before==_start_evidence.builds_after and _start_evidence.updates>0,"running_complete_values_match_raw":running.ok and running.noise==10}
	var playback: GameSession = GameSession.new(f.s,"environment-global-pause")
	playback.set_speed(1);playback.pause("acceptance")
	var paused: Dictionary = f.w.freeze()
	for index: int in 4: playback.advance(0.5)
	checks.global_pause_keeps_noise_and_all_facts = f.w.freeze()==paused and x.e.sample_at(f.w,1,[51,88]).noise==10
	# Pending fault is an explicit lawful input while the current use completes.
	item.pending_failure = true
	f.s.services.maintenance.boundaries(f.w)
	var pending: Dictionary = _compare_direct(x,reference,[51,88])
	checks.pending_failure_while_working_does_not_mute = pending.ok and pending.noise==10 and not item.failed and item.pending_failure
	var builds: int = _count(x.space,"session_source_builds")
	var updates: int = _count(x.space,"session_source_updates")
	var begin: int = f.w.sim_tick
	for step: int in 1600:
		if not f.w.facts.sessions.has(id): break
		_ops._clinic_tick(f)
	var finished: Dictionary = _compare_direct(x,reference,[51,88])
	checks.actual_complete_removes_last_source = not f.w.facts.sessions.has(id) and finished.ok and finished.noise==0 and x.e._session_sources._view.floors.is_empty()
	checks.completion_does_not_rebuild = _count(x.space,"session_source_builds")==builds and _count(x.space,"session_source_updates")>updates
	checks.final_world_valid = f.w.validate(_content).is_empty()
	return _result_checks(checks,{"start":_start_evidence,"work_ticks_executed":f.w.sim_tick-begin,"pending":pending,"finished":finished,"validation":f.w.validate(_content)})

func _session_resume() -> Dictionary:
	var f: Dictionary = _running_copy()
	if f.is_empty(): return {"ok":false,"prerequisite":_start_evidence}
	var x: Dictionary = _sx(f)
	var reference: HospitalEnvironment = _reference_for(x)
	var old: Dictionary = _sess(f.w,"outpatient").duplicate(true)
	var item: Dictionary = f.w.facts.facilities[old.facility_id]
	# A second ordinary same-kind treatment room is legal fixture input. The
	# paused patient's actual exit, new reservation and arrival are never moved.
	HospitalFactory._add_room(f.w,{"id":"resume_room","type":f.w.facts.rooms[item.room_id].room_type_id,"anchor":[34,66],"size":[10,10],"door":{"definition_id":"DR06","offset":5}},_content)
	_facility(x,"resume_machine",str(item.definition_id),[39,69],"resume_room")
	f.w.touch()
	var department_id: String = f.w.facts.visits[old.visit_id].get("department_id","")
	if f.w.facts.departments.units.has(department_id): f.w.facts.departments.units[department_id].room_ids.append("resume_room")
	var initial_valid: String = f.w.validate(_content)
	_compare_direct(x,reference,[51,88])
	var builds: int = _count(x.space,"session_source_builds")
	var prepare: CommandResult = _ops._command(f,"remodel_prepare",{"commands":[{"kind":"build_move","target_id":item.id,"floor_id":1,"cell":item.cell.duplicate()}],"safe_transfer":true})
	if not prepare.accepted: return {"ok":false,"prerequisite":"remodel_prepare","reason":prepare.reason,"validation":initial_valid}
	var held: bool = false
	var resumed: bool = false
	var removed_noise: int = -1
	var resumed_noise: int = -1
	var comparisons: bool = true
	var session: Dictionary = {}
	var max_step: float = 0.0
	var actor_id: String = f.w.facts.visits[old.visit_id].actor_id
	var resume_debug: Dictionary = {}
	var started: int = f.w.sim_tick
	for step: int in 1400:
		if f.w.facts.actors[actor_id].location.kind!="floor": break
		var previous: Vector2 = ConvoyTrail.point(f.w.facts.actors[actor_id].location.cell)
		_ops._clinic_tick(f,true)
		if f.w.facts.actors[actor_id].location.kind!="floor": break
		var current: Vector2 = ConvoyTrail.point(f.w.facts.actors[actor_id].location.cell)
		max_step = maxf(max_step,previous.distance_to(current))
		if f.w.facts.clinical_suspensions.has(old.id) and not held:
			held = true
			var observed: Dictionary = _compare_direct(x,reference,[51,88]);comparisons = comparisons and observed.ok;removed_noise = observed.noise
		if step==180:
			resume_debug = {"candidates":f.s.clinic.service_candidates(f.w,f.w.facts.visits[old.visit_id],"outpatient",true),"quote":f.s.space.facility_quote(f.w,"resume_machine",actor_id,[old.staff_ids[0]]),"doctor_busy":f.s.clinic._staff_busy(f.w,old.staff_ids[0]),"doctor_schedule":f.s.clinic._schedule_allows(f.w,old.staff_ids[0],"outpatient",f.w.facts.visits[old.visit_id],"resume_machine"),"doctor_can_start":f.s.clinic._can_start(f.w,f.w.facts.staff[old.staff_ids[0]])}
		if f.w.facts.sessions.has(old.id):
			session = f.w.facts.sessions[old.id]
			if session.facility_id=="resume_machine":
				resumed = true
				var observed: Dictionary = _compare_direct(x,reference,[39,69]);comparisons = comparisons and observed.ok;resumed_noise = observed.noise
				break
	var checks: Dictionary = {"legal_input":initial_valid.is_empty(),"real_safe_pause_removes_noise":held and removed_noise==0,"same_id_resumes_on_other_same_kind":resumed and session.get("id","")==old.id and session.get("attempt_id","")==old.attempt_id,"real_arrival_no_teleport":resumed and max_step>0 and max_step<=0.201,"resumed_noise_matches_raw":comparisons and resumed_noise==10,"no_source_rebuild":_count(x.space,"session_source_builds")==builds,"valid_final":f.w.validate(_content).is_empty()}
	return _result_checks(checks,{"resume_debug":resume_debug,"ticks":f.w.sim_tick-started,"original_id":old.id,"old_facility":old.facility_id,"resumed_facility":session.get("facility_id",""),"removed_noise":removed_noise,"resumed_noise":resumed_noise,"max_movement_step":max_step,"validation":f.w.validate(_content),"visit":f.w.facts.visits[old.visit_id],"suspensions":f.w.facts.clinical_suspensions})

func _session_surgery() -> Dictionary:
	var checks: Dictionary = {}
	var rows: Array = []
	for boundary: String in ["gp_started","surgery_started","ward_care"]:
		if not await _clinical._ensure_boundary(_tree,boundary): return {"ok":false,"prerequisite":boundary,"failures":_clinical._fixture_failures}
		var c: Dictionary = _clinical._copy(boundary)
		var kind: String = {"gp_started":"gp","surgery_started":"surgery","ward_care":"care"}[boundary]
		var session: Dictionary = _clinical._session(c,kind)
		var x: Dictionary = {"world":c.world,"e":c.sim.services.environment,"space":c.sim.space}
		var cell: Array = c.world.facts.facilities[session.facility_id].cell.duplicate()
		# A last-work-tick is declared input, not credit for previous elapsed work.
		# The production advance performs the completion and successor insertion.
		session.remaining_ticks = 1
		if kind=="surgery": session.clinical_beat = 3
		c.world.touch(false)
		var validation: String = c.world.validate(_content)
		var reference: HospitalEnvironment = _reference_for(x)
		var before: Dictionary = _compare_direct(x,reference,cell)
		var builds: int = _count(x.space,"session_source_builds")
		var updates: int = _count(x.space,"session_source_updates")
		var count_before: int = c.world.facts.sessions.size()
		var id: String = session.id
		var paused_copy: Dictionary = {}
		if kind=="care":
			paused_copy = _clinical._copy(boundary)
			var p: Dictionary = {"world":paused_copy.world,"e":paused_copy.sim.services.environment,"space":paused_copy.sim.space}
			_compare_direct(p,_reference_for(p),cell)
			var b: int = _count(p.space,"session_source_builds")
			var count: int = p.world.facts.sessions.size()
			paused_copy.sim.clinic._pause_bed_sessions(p.world,_clinical._stay(paused_copy))
			checks.care_pause_owner_removal = p.world.facts.sessions.size()==count-1 and _compare_direct(p,_reference_for(p),cell).ok and _count(p.space,"session_source_builds")==b and p.e._session_sources._view.count==p.world.facts.sessions.size()
		c.sim.clinic.advance(c.world)
		var after: Dictionary = _compare_direct(x,reference,cell)
		checks[kind+"_legal_boundary"] = validation.is_empty()
		checks[kind+"_real_completion"] = not c.world.facts.sessions.has(id) and before.ok and after.ok
		checks[kind+"_local_membership"] = _count(x.space,"session_source_builds")==builds and _count(x.space,"session_source_updates")>updates and x.e._session_sources._view.count==c.world.facts.sessions.size()
		checks[kind+"_noise"] = before.noise==(10 if kind=="surgery" else 0) and after.noise==0
		if kind=="surgery": checks.equal_count_surgery_to_wake = c.world.facts.sessions.size()==count_before and not _clinical._session(c,"wake").is_empty()
		rows.append({"boundary":boundary,"input":"one remaining work tick; preceding work is input","validation":validation,"count_before":count_before,"count_after":c.world.facts.sessions.size(),"before":before,"after":after})
	return _result_checks(checks,{"rows":rows})

func _raw_fixture(count: int = 1) -> Dictionary:
	# This is a source/index calculation input, not a claimed clinical hospital.
	var x: Dictionary = _fixture()
	x.world.facts.floors.completed_top_floor = {}
	for plot: Array in x.world.facts.floors.overrides["1"].plots: x.world.facts.floors.completed_top_floor["%d:%d" % plot] = 1
	for index: int in count:
		var id: String = "raw_machine_%d"%index
		_facility(x,id,["M09","M37","M17","EQ01"][index%4],[36+(index%5)*5,68+(index/5)*4])
		x.world.facts.sessions["raw_%d"%index] = {"id":"raw_%d"%index,"kind":"outpatient","facility_id":id}
	x.world.touch()
	return x

func _write_raw(x: Dictionary, id: String, kind: String, facility_id: String) -> void:
	x.world.facts.sessions[id] = {"id":id,"kind":kind,"facility_id":facility_id}
	x.e.session_written(x.world,id)

func _remove_raw(x: Dictionary, id: String) -> void:
	x.e.session_removing(x.world,id)
	x.world.facts.sessions.erase(id)

func _session_index() -> Dictionary:
	var x: Dictionary = _raw_fixture(4)
	var reference: HospitalEnvironment = _reference_for(x)
	var checks: Dictionary = {"initial":_compare_direct(x,reference,[36,68]).ok}
	var builds: int = _count(x.space,"session_source_builds")
	var rows: Array = []
	for index: int in 4:
		var id: String = "raw_%d"%index
		var facility_id: String = "raw_machine_%d"%index
		var cell: Array = x.world.facts.facilities[facility_id].cell
		for kind: String in ["outpatient","surgery","operate","wake","care","gp"]:
			_write_raw(x,id,kind,facility_id)
			var compared: Dictionary = _compare_direct(x,reference,cell)
			rows.append({"definition":x.world.facts.facilities[facility_id].definition_id,"kind":kind,"noise":compared.noise,"ok":compared.ok and compared.noise==(10 if kind in ["outpatient","surgery","operate"] else 0)})
		_remove_raw(x,id)
	checks.definition_and_kind_matrix = rows.all(func(row: Dictionary)->bool:return row.ok)
	checks.excluded_members_counted_without_rebuild = _count(x.space,"session_source_builds")==builds and x.e._session_sources._view.count==0 and x.e._session_sources._view.members.is_empty() and x.e._session_sources._view.floors.is_empty() and x.e._session_sources.bounds().is_empty()
	_write_raw(x,"one","outpatient","raw_machine_0");_write_raw(x,"two","operate","raw_machine_0")
	_remove_raw(x,"one")
	checks.duplicate_facility_retains_other_member = _compare_direct(x,reference,[36,68]).ok and x.e.sample_at(x.world,1,[36,68]).noise==10
	var item: Dictionary = x.world.facts.facilities.raw_machine_0
	item.failed = true
	checks.failure_is_live_without_index_write = _compare_direct(x,reference,[36,68]).ok and x.e.sample_at(x.world,1,[36,68]).noise==0
	x.world.facts.facilities.raw_machine_0 = item.duplicate(true)
	x.world.facts.facilities.raw_machine_0.failed = false
	x.world.facts.facilities.raw_machine_0.pending_failure = true
	checks.same_key_repair_and_pending_are_live = _compare_direct(x,reference,[36,68]).ok and x.e.sample_at(x.world,1,[36,68]).noise==10
	# Empty corridors: footprint edge is x=37, range four reaches 41, not 42.
	checks.footprint_four_step_boundary = x.e.sample_at(x.world,1,[41,68]).noise==10 and x.e.sample_at(x.world,1,[42,68]).noise==0
	_remove_raw(x,"two")
	checks.last_member_clears_floor_and_bounds = _compare_direct(x,reference,[36,68]).ok and x.e._session_sources._view.floors.is_empty() and x.e._session_sources.bounds().is_empty()
	var visits: int = _count(x.space,"session_source_visits")
	_write_raw(x,"excluded","gp","raw_machine_0")
	checks.excluded_new_member_counts_without_source = x.e._session_sources._view.count==1 and x.e._session_sources._view.members.has("excluded") and x.e._session_sources._view.members.excluded==null and _compare_direct(x,reference,[36,68]).ok and x.e.sample_at(x.world,1,[36,68]).noise==0
	_remove_raw(x,"excluded")
	checks.excluded_removal_keeps_warm_count = _count(x.space,"session_source_visits")==visits and x.e._session_sources._view.count==0
	_facility(x,"silent_machine","M14",[40,80]);x.world.touch()
	_write_raw(x,"silent","outpatient","silent_machine")
	checks.other_definition_never_noisy = _compare_direct(x,reference,[40,80]).ok and x.e.sample_at(x.world,1,[40,80]).noise==0 and x.e._session_sources._view.members.silent==null
	_remove_raw(x,"silent")
	_write_raw(x,"live","outpatient","raw_machine_0")
	x.e.begin_query(x.world)
	var live: Dictionary = x.e.sample_at(x.world,1,[36,68])
	x.world.facts.facilities.raw_machine_0.failed = true
	checks.failure_changes_inside_open_scope = live.noise==10 and _compare_direct(x,reference,[36,68]).ok and x.e.sample_at(x.world,1,[36,68]).noise==0
	x.world.facts.facilities.raw_machine_0.failed = false
	checks.repair_changes_inside_open_scope = _compare_direct(x,reference,[36,68]).ok and x.e.sample_at(x.world,1,[36,68]).noise==10
	x.e.end_query();_remove_raw(x,"live")
	# The 64-bit position is raw key/bounds arithmetic, never a legal floor.
	x.world.facts.facilities.raw_machine_0.cell = [4294967300,68]
	x.world.touch()
	_write_raw(x,"huge","outpatient","raw_machine_0")
	var positions: Dictionary = x.e._session_sources.sources(x.world,x.space,_content.balance.environment.machine_noise_definition_ids)
	checks.raw_64_bit_key_kept_without_wrapping = positions[1].has("4294967300:68") and x.e._session_sources.bounds()[1]==null
	_remove_raw(x,"huge")
	checks.raw_last_extreme_removal_clears_bounds = x.e._session_sources.bounds().is_empty()
	var result: Dictionary = _result_checks(checks,{"input_scope":"Raw source/index calculations only; no claim of clinical legality or elapsed service","matrix":rows})
	Coverage.new()._dispose(x)
	return result

func _session_layout() -> Dictionary:
	var x: Dictionary = _raw_fixture()
	HospitalFactory._add_staff(x.world,"large","large","doctor",[54,88],_content)
	x.world.facts.actors.large.species_id = "S59"
	x.world.touch()
	var reference: HospitalEnvironment = _reference_for(x)
	var initial: Dictionary = _compare_direct(x,reference,[42,69])
	var original: Array = x.space.facility_layout(x.world,"raw_machine_0").footprint.duplicate()
	var builds: int = _count(x.space,"session_source_builds")
	var updates: int = _count(x.space,"session_layout_updates")
	var reserved: String = x.space.reserve_facility(x.world,"raw_machine_0","large","raw_0",[])
	var footprint: Array = x.space.facility_layout(x.world,"raw_machine_0").footprint.duplicate()
	var expanded: Dictionary = _compare_direct(x,reference,[42,69])
	var checks: Dictionary = {"real_large_body_reservation_preserves_machine_base":reserved.is_empty() and footprint==original and x.world.facts.adaptations.has("raw_machine_0"),"base_edge_remains_outside_four_steps":initial.noise==0 and expanded.noise==0 and initial.ok and expanded.ok,"reservation_updates_locally":_count(x.space,"session_source_builds")==builds and _count(x.space,"session_layout_updates")>updates}
	# A non-machine reservation callback must do no machine source work.
	updates = _count(x.space,"session_layout_updates")
	x.space.reservation_changed(x.world,"unrelated-door")
	checks.unrelated_reservation_does_no_machine_work = _count(x.space,"session_layout_updates")==updates
	x.world.facts.adaptations.raw_machine_0.footprint = [3,3]
	x.space.reservation_changed(x.world,"raw_machine_0")
	checks.raw_expanded_footprint_boundary = _compare_direct(x,reference,[42,69]).ok and x.e.sample_at(x.world,1,[42,69]).noise==10
	var result: Dictionary = _result_checks(checks,{"input_scope":"Raw session; real S59 reserve_facility uses FF03 fixed machine base. Raw expanded footprint is a separate arithmetic boundary.","reservation_reason":reserved,"original_footprint":original,"expanded_footprint":footprint,"before":initial,"after":expanded})
	Coverage.new()._dispose(x)
	return result

func _session_restore() -> Dictionary:
	var f: Dictionary = _running_copy()
	if f.is_empty(): return {"ok":false,"prerequisite":_start_evidence}
	var x: Dictionary = _sx(f)
	var reference: HospitalEnvironment = _reference_for(x)
	var checks: Dictionary = {"initial":_compare_direct(x,reference,[51,88]).ok}
	var builds: int = _count(x.space,"session_source_builds")
	f.w.facts.sessions = f.w.facts.sessions.duplicate(true)
	checks.same_count_collection_replacement_cold_build = _compare_direct(x,reference,[51,88]).ok and _count(x.space,"session_source_builds")==builds+1
	var c: Dictionary = {"world":f.w,"sim":f.s}
	var restored: Dictionary = _clinical._roundtrip(c)
	checks.stream_save_restore_complete_facts = restored.ok
	if not restored.ok: return _result_checks(checks,{"restore":restored})
	var loaded: Dictionary = {"world":c.world,"e":c.sim.services.environment,"space":c.sim.space}
	checks.restored_service_cold_binding = _count(loaded.space,"session_source_builds")==1 and _compare_direct(loaded,_reference_for(loaded),[51,88]).ok
	var old: WorldState = x.world
	var cross_builds: int = _count(x.space,"session_source_builds")
	x.world = c.world
	checks.cross_world_numeric_identity = old.hospital_id==x.world.hospital_id and old.geometry_revision==x.world.geometry_revision and _compare_direct(x,reference,[51,88]).ok and x.e._session_sources._view.world.get_ref()==x.world and _count(x.space,"session_source_builds")==cross_builds+1
	x.e.begin_query(x.world)
	var scope: Dictionary = x.e._query
	checks.foreign_query_preserves_parent_scope = _compare_direct({"world":old,"e":x.e},reference,[51,88]).ok and is_same(scope,x.e._query) and x.e._query.world==x.world
	x.e.end_query()
	x.world.facts = x.world.freeze().duplicate(true)
	checks.same_world_facts_replacement = _compare_direct(x,reference,[51,88]).ok
	return _result_checks(checks,{"restore":restored})

func _session_workers() -> Dictionary:
	var f: Dictionary = _running_copy()
	if f.is_empty(): return {"ok":false,"prerequisite":_start_evidence}
	var x: Dictionary = _sx(f)
	var reference: HospitalEnvironment = _reference_for(x)
	var rows: Array = []
	var item: Dictionary = f.w.facts.facilities[_sess(f.w,"outpatient").facility_id]
	for failed: bool in [false,true,false]:
		item.failed = failed
		for count: int in [1,4]:
			x.e.begin_query(x.world)
			x.e._prepare_facility_sources(x.world);x.e._prepare_sample_sources(x.world)
			var bounds: Variant = x.e._prepare_observation_bounds(x.world)
			x.e._coverage_edges(x.world,1)
			var requests: Array = []
			for cell: Array in [[51,88],[51,86],[52,86],[51,90],[46,80],[58,90],[34,66],[63,94]]: requests.append(["probe","",1,cell])
			var expected: Array = []
			var raw: Array = []
			for request: Array in requests:
				expected.append(x.e.sample_at(x.world,1,request[3]));raw.append(reference.sample_at(x.world,1,request[3]))
			var before: Dictionary = x.world.freeze()
			var jobs: Array = []
			for index: int in count:
				var job: RefCounted = Batch.SampleJob.new(_content)
				job.prepare(x.e,x.world,requests.slice(requests.size()*index/count,requests.size()*(index+1)/count),{},true,bounds)
				jobs.append(job)
			var group: int = WorkerThreadPool.add_group_task(func(index: int)->void:jobs[index].run(),count,count,false,"Session source acceptance")
			WorkerThreadPool.wait_for_group_task_completion(group)
			var actual: Array = []
			var consumer: RefCounted = Batch.new()
			consumer._last = {"consumed":0}
			var borrowed: bool = true
			var ids: Array = []
			for job: RefCounted in jobs:
				ids.append(job.thread_id)
				borrowed = borrowed and is_same(job.environment._query.samples.machines,x.e._query.samples.machines) and job.environment._session_sources._view.is_empty() and _count(job.environment.space,"session_source_builds")==0
				for result: Array in job.results:
					consumer._observations["probe"] = result
					actual.append(consumer.consume(x.world,x.e,"probe",""))
				job.release_borrowed()
			var real_workers: bool = ids.all(func(id: int)->bool:return id!=OS.get_main_thread_id() and id>0)
			rows.append({"workers":count,"failed":failed,"thread_ids":ids,"ok":actual==expected and actual==raw and before==x.world.freeze() and borrowed and real_workers,"full_values_equal":actual==expected and actual==raw,"readonly_facts_and_rng":before==x.world.freeze(),"borrowed_without_rebuild":borrowed,"real_workers":real_workers})
			x.e.end_query()
	var production: Array = []
	var visit: Dictionary = f.w.facts.visits[_sess(f.w,"outpatient").visit_id]
	var actor: Dictionary = f.w.facts.actors[visit.actor_id]
	for requested: int in [1,4]:
		x.e.begin_query(x.world)
		var before: Dictionary = x.world.freeze()
		var expected: Dictionary = reference.sample_at(x.world,int(actor.location.floor_id),actor.location.cell,actor.id)
		var batch: RefCounted = Batch.new()
		var prepared: bool = batch.prepare(x.world,x.e,[visit.id],requested,true)
		var consumed: Dictionary = batch.consume(x.world,x.e,visit.id,actor.id) if prepared else {}
		production.append({"requested":requested,"actual_jobs":batch._last.get("jobs",[]).size(),"ok":prepared and consumed==expected and x.world.freeze()==before,"diagnostics":batch._last})
		x.e.end_query()
	return {"ok":rows.all(func(row: Dictionary)->bool:return row.ok) and production.all(func(row: Dictionary)->bool:return row.ok),"rows":rows,"production_prepare_consume":production}

func _session_measure() -> Dictionary:
	var x: Dictionary = _raw_fixture(20)
	for index: int in range(20,80): x.world.facts.sessions["excluded_%d"%index] = {"id":"excluded_%d"%index,"kind":["care","gp","wake"][index%3],"facility_id":"raw_machine_0"}
	x.e.sample_at(x.world,1,[42,74])
	var before: Dictionary = x.world.freeze()
	var counts: Dictionary = x.space.query_counts.duplicate()
	var start: int = Time.get_ticks_usec()
	for index: int in 1000: x.e.sample_at(x.world,1,[42+index%2,74])
	var elapsed: int = Time.get_ticks_usec()-start
	var checks: Dictionary = {"readonly_facts_rng":before==x.world.freeze(),"warm_no_session_enumeration":_count(x.space,"session_source_visits")==counts.get("environment_session_source_visits",0),"warm_no_rebuild":_count(x.space,"session_source_builds")==counts.get("environment_session_source_builds",0),"warm_no_layout_scan":_count(x.space,"session_layout_updates")==counts.get("environment_session_layout_updates",0),"bounds_only_requested_floor":_count(x.space,"observation_bound_floor_checks")-int(counts.get("environment_observation_bound_floor_checks",0))==1000}
	var result: Dictionary = _result_checks(checks,{"input_scope":"Fixed pure observation operation with 20 noisy and 60 excluded raw session records; not hospital throughput","sessions":80,"noisy":20,"warm_queries":1000,"elapsed_us":elapsed,"counts_before":counts,"counts_after":x.space.query_counts.duplicate()})
	Coverage.new()._dispose(x)
	return result

func _session_floors() -> Dictionary:
	var x: Dictionary = _raw_fixture(4)
	for index: int in 4: x.world.facts.facilities["raw_machine_%d"%index].floor_id = [1,2,40,400][index]
	x.world.touch()
	x.e.begin_query(x.world)
	x.e._prepare_facility_sources(x.world);x.e._prepare_sample_sources(x.world)
	var prior: int = _count(x.space,"observation_bound_floor_checks")
	var first: Dictionary = x.e._prepare_observation_bounds(x.world,[1])
	var one: int = _count(x.space,"observation_bound_floor_checks")
	var again: Dictionary = x.e._prepare_observation_bounds(x.world,[1])
	var two: Dictionary = x.e._prepare_observation_bounds(x.world,[2])
	var checks: Dictionary = {"only_requested_floor_built":first.keys()==[1] and one==prior+1,"same_floor_no_new_work":is_same(first,again),"second_floor_appends_only_one":two.keys()==[1,2] and _count(x.space,"observation_bound_floor_checks")==prior+2,"published_bounds_stay_immutable":first.is_read_only() and first[1].is_read_only() and first.keys()==[1] and two.is_read_only(),"source_has_remote_floors":x.e._query.samples.machines.keys()==[1,2,40,400]}
	x.e.end_query()
	var result: Dictionary = _result_checks(checks,{"input_scope":"Raw multiple-floor source arithmetic, not a legal 400-floor clinical hospital"})
	Coverage.new()._dispose(x)
	return result

func _session_empty() -> Dictionary:
	var x: Dictionary = _raw_fixture()
	_facility(x,"new_machine","M37",[56,88]);x.world.touch()
	var reference: HospitalEnvironment = _reference_for(x)
	var checks: Dictionary = {"warm_original_source":_compare_direct(x,reference,[36,68]).ok and x.e.sample_at(x.world,1,[36,68]).noise==10}
	var builds: int = _count(x.space,"session_source_builds")
	# An unannounced raw clear bypasses normal owner notifications deliberately.
	x.world.facts.sessions.clear()
	checks.raw_clear_is_authoritatively_silent = _compare_direct(x,reference,[36,68]).ok and x.e.sample_at(x.world,1,[36,68]).noise==0 and x.e._session_sources._view.is_empty() and _count(x.space,"session_source_builds")==builds
	x.world.facts.sessions.new_id = {"id":"new_id","kind":"outpatient","facility_id":"new_machine"}
	checks.same_count_new_id_cold_reacquisition = _compare_direct(x,reference,[56,88]).ok and x.e.sample_at(x.world,1,[56,88]).noise==10 and _count(x.space,"session_source_builds")==builds+1 and x.e._session_sources._view.members.keys()==["new_id"]
	checks.old_source_does_not_reappear = _compare_direct(x,reference,[36,68]).ok and x.e.sample_at(x.world,1,[36,68]).noise==0
	_remove_raw(x,"new_id")
	var zero: Dictionary = x.e._session_sources._view
	var hits: int = _count(x.space,"session_source_hits")
	for index: int in 20: x.e.sample_at(x.world,1,[56,88])
	checks.notified_empty_retains_owner_without_source_checks = is_same(zero,x.e._session_sources._view) and zero.count==0 and _count(x.space,"session_source_hits")==hits
	_write_raw(x,"newer_id","outpatient","new_machine")
	checks.warm_empty_owner_accepts_next_write = _compare_direct(x,reference,[56,88]).ok and x.e.sample_at(x.world,1,[56,88]).noise==10 and _count(x.space,"session_source_builds")==builds+1
	var result: Dictionary = _result_checks(checks,{"input_scope":"Raw source clear/replacement contract; real owner empty transitions are covered by CLINICAL and SURGERY"})
	Coverage.new()._dispose(x)
	return result
