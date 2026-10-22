extends RefCounted

# This is one finite GROW-75 helper, not
# a replacement for the fixed 160-person whole-step measurements.
const WorkerBatch = preload("res://game/operations/environment_sample_batch.gd")

class MissingSlotBatch extends WorkerBatch:
	func _run_job(index: int) -> void:
		super._run_job(index)
		if index==0 and not _jobs[index].results.is_empty():
			_jobs[index].results[0] = null

class CustomEnvironment extends HospitalEnvironment:
	var sample_calls: int = 0
	func sample_at(world: WorldState, floor_id: int, cell: Array, actor_id: String = "") -> Dictionary:
		sample_calls += 1
		return super.sample_at(world,floor_id,cell,actor_id)

class CustomSpace extends HospitalSpace:
	var owned_calls: int = 0
	func owned(world: WorldState, floor_id: int, cell: Vector2i) -> bool:
		owned_calls += 1
		return super.owned(world,floor_id,cell)

func run(suite: RefCounted, content: HospitalContent) -> Dictionary:
	var checks: Dictionary = {}
	var rows: Array = []
	var empty: Dictionary = _seed(suite,content,0)
	var one: Dictionary = _seed(suite,content,1)
	var many: Dictionary = _seed(suite,content,4)
	for input: Dictionary in [empty,one,many]:
		if not str(input.validation).is_empty():
			return {"ok":false,"failure_kind":"fixture","prerequisite":input.name,"reason":input.validation,"admissions":input.get("admissions",[])}
		var row: Dictionary = _sample_pair(input,content,false,false,false)
		rows.append(row)
		checks["base_"+str(input.name)] = row.ok
	var nested: Dictionary = _sample_pair(many,content,true,false,false)
	rows.append(nested)
	checks.original_query_nesting_and_cache_order = nested.ok
	var missing: Dictionary = _sample_pair(many,content,false,false,true)
	rows.append(missing)
	checks.missing_slot_falls_back_before_experience = missing.ok
	var custom: Dictionary = _sample_pair(one,content,false,true,false)
	rows.append(custom)
	checks.custom_override_stays_serial = custom.ok
	var custom_space: Dictionary = _sample_pair(one,content,false,false,false,true)
	rows.append(custom_space)
	checks.custom_space_stays_serial = custom_space.ok
	var water: Dictionary = _water_inputs(suite,content)
	checks.water_candidates_and_live_permission = water.ok
	var numeric: Dictionary = _numeric_finish(empty.facts,content)
	checks.unclamped_numeric_finish = numeric.ok
	return {"ok":not checks.values().has(false),"checks":checks,"sample_pairs":rows,
		"water":water,"numeric_finish_only":numeric,"not_covered":["cross-floor Worker requests","outside-owned Worker requests"],
		"scope":"Real base Department.sample uses the original serial switch as oracle. Numeric finish checks are calculation inputs, not simulated travel or patient relocation."}

func _bind(facts: Dictionary, content: HospitalContent) -> Dictionary:
	var world: WorldState = WorldState.new(facts.duplicate(true))
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	return {"world":world,"simulation":simulation,"space":simulation.space,"clinic":simulation.clinic,
		"arrivals":simulation.services.arrivals,"environment":simulation.services.environment,"departments":simulation.services.departments}

func _seed(suite: RefCounted, content: HospitalContent, count: int) -> Dictionary:
	var original: Dictionary = suite._context()
	# Staff exists before rebinding, so normal service initialization supplies
	# the complete staff facts. Staff-day accumulation is not vacuous.
	HospitalFactory._add_staff(original.world,"worker_check_staff","采样职员","cleaner",[36,90],content)
	original.world.touch()
	var x: Dictionary = _bind(original.world.freeze(),content)
	if original.has("simulation") and original.simulation!=null:
		original.simulation.dispose()
	var ids: Array = []
	var admissions: Array = []
	for index: int in count:
		var visit: Dictionary = suite._patient(x,[[44,80],[46,80],[48,80],[45,83]][index])
		admissions.append(x.get("last_admission",{}).duplicate(true))
		if visit.is_empty():
			var failed: Dictionary = {"facts":x.world.freeze(),"ids":ids,"validation":"合法患者前提未生成完整请求数","name":"count_"+str(count),"admissions":admissions}
			x.simulation.dispose()
			return failed
		ids.append(str(visit.id))
	suite._add_facility(x.world,"worker_check_plant","FUR25",null,[42,79])
	suite._add_facility(x.world,"worker_check_light","FUR19",null,[42,82])
	x.world.facts.sim_tick = 1200
	x.departments.ensure(x.world)
	for id: String in ids:
		var visit: Dictionary = x.world.facts.visits[id]
		var data: Dictionary = x.world.facts.departments.experience[id]
		data.phase = "arrival"
		data.phase_started_tick = 0
		data.next_anger_tick = 0
		data.cause_clocks = {"no_compatible_seat":0}
		x.world.facts.tickets[visit.ticket_id].waited_ticks = 1200
	x.world.touch()
	var validation: String = x.world.validate(content)
	if ids.size()!=count: validation = "合法患者前提未生成完整请求数"
	var result: Dictionary = {"facts":x.world.freeze(),"ids":ids,"validation":validation,"name":"count_"+str(count),"admissions":admissions}
	x.simulation.dispose()
	return result

func _cache_view(environment: HospitalEnvironment) -> Array:
	var result: Array = []
	for floor_id: int in environment._coverage_cache:
		var entry: Dictionary = environment._coverage_cache[floor_id]
		var coverage: Dictionary = entry.get("coverage",{})
		result.append([floor_id,coverage.keys(),coverage.duplicate(true)])
	return result

func _sample_pair(input: Dictionary, content: HospitalContent, nested: bool, custom: bool, missing: bool, custom_space: bool = false) -> Dictionary:
	var serial: Dictionary = _bind(input.facts,content)
	var parallel: Dictionary = _bind(input.facts,content)
	if custom:
		for x: Dictionary in [serial,parallel]:
			var observer: CustomEnvironment = CustomEnvironment.new(content,x.space)
			observer.waiting_life = x.simulation.services.waiting
			x.environment = observer
			x.departments.environment = observer
			x.simulation.services.waiting.environment = observer
	if custom_space:
		for x: Dictionary in [serial,parallel]:
			var geometry: CustomSpace = CustomSpace.new(content)
			var observer: HospitalEnvironment = HospitalEnvironment.new(content,geometry)
			observer.waiting_life = x.simulation.services.waiting
			x.environment = observer
			x.departments.environment = observer
			x.simulation.services.waiting.environment = observer
	var defaults: bool = bool(parallel.departments.sample_workers_enabled) and int(parallel.departments.sample_worker_tasks)==4
	serial.departments.sample_workers_enabled = false
	parallel.departments.sample_worker_diagnostics = true
	if missing: parallel.departments._worker_sample_batch = MissingSlotBatch.new()
	var before: Dictionary = serial.world.freeze()
	var nesting: bool = true
	if nested:
		for x: Dictionary in [serial,parallel]:
			x.environment.begin_query(x.world)
			x.environment.begin_query(x.world)
			if not input.ids.is_empty():
				var actor: Dictionary = x.world.facts.actors[x.world.facts.visits[input.ids[0]].actor_id]
				x.environment.sample_at(x.world,int(actor.location.floor_id),actor.location.cell,str(actor.id))
	for x: Dictionary in [serial,parallel]: x.departments.sample(x.world)
	if nested:
		nesting = serial.environment._query_depth==2 and parallel.environment._query_depth==2
		for x: Dictionary in [serial,parallel]:
			x.environment.end_query()
			x.environment.end_query()
	var report: Dictionary = parallel.departments.sample_worker_report()
	var requested: int = input.ids.size()
	var execution: bool
	if custom or custom_space or requested==0:
		execution = int(report.batches)==0 and int(report.processed)==0 and int(report.consumed)==0
	elif missing:
		execution = int(report.batches)==1 and int(report.failed_batches)==1 and int(report.processed)==requested and int(report.consumed)==0
	else:
		execution = int(report.batches)==1 and int(report.failed_batches)==0 and int(report.processed)==requested and int(report.consumed)==requested and bool(report.last_batch.get("all_results_consumed",false))
		for job: Dictionary in report.last_batch.jobs:
			execution = execution and int(job.thread_id)!=0 and int(job.thread_id)!=OS.get_main_thread_id()
	var equal: bool = serial.world.freeze()==parallel.world.freeze()
	var rng: bool = serial.world.facts.rng==before.rng and parallel.world.facts.rng==before.rng
	var cache_equal: bool = _cache_view(serial.environment)==_cache_view(parallel.environment)
	var scopes: bool = serial.environment._query.is_empty() and parallel.environment._query.is_empty() and serial.environment._query_depth==0 and parallel.environment._query_depth==0 and serial.space._route_queries.is_empty() and parallel.space._route_queries.is_empty()
	var staff_days: bool = not parallel.world.facts.departments.staff_days.is_empty()
	var overrides: bool = not custom or int(parallel.environment.sample_calls)==requested and int(serial.environment.sample_calls)==requested
	var space_override: bool = not custom_space or int(parallel.environment.space.owned_calls)>0 and int(serial.environment.space.owned_calls)>0
	var valid: String = parallel.world.validate(content)
	var row: Dictionary = {"name":input.name,"nested":nested,"custom":custom,"custom_space":custom_space,"missing_slot":missing,
		"ok":input.validation.is_empty() and valid.is_empty() and defaults and execution and equal and rng and cache_equal and scopes and staff_days and overrides and space_override and nesting,
		"input_validation":input.validation,"output_validation":valid,"real_worker_execution_or_expected_fallback":execution,
		"default_workers_enabled_with_four_tasks":defaults,
		"complete_facts_equal_including_experience_anger_details_staff_days":equal,"rng_unchanged":rng,
		"retained_coverage_order_and_values_equal":cache_equal,"scopes_closed":scopes,"staff_days_present":staff_days,"nested_depth_preserved":nesting,"override_calls_preserved":overrides,"custom_space_owned_called":space_override,"worker_report":report}
	for x: Dictionary in [serial,parallel]:
		if custom or custom_space: x.environment.waiting_life = null
		x.simulation.dispose()
	return row

func _observation_pair(input: Dictionary, content: HospitalContent) -> Dictionary:
	var serial: Dictionary = _bind(input.facts,content)
	var parallel: Dictionary = _bind(input.facts,content)
	serial.environment.begin_query(serial.world)
	parallel.environment.begin_query(parallel.world)
	var batch: RefCounted = WorkerBatch.new()
	var prepared: bool = batch.prepare(parallel.world,parallel.environment,input.ids,4,true)
	var rows: Array = []
	var ok: bool = prepared
	if prepared:
		batch.begin_apply()
		for visit_id: String in input.ids:
			var actor: Dictionary = serial.world.facts.actors[serial.world.facts.visits[visit_id].actor_id]
			var raw: Dictionary = batch._observations[visit_id].observation
			var candidates: Array = raw.get("_worker_sample_water",[]).duplicate()
			var expected: Dictionary = serial.environment.sample_at(serial.world,int(actor.location.floor_id),actor.location.cell,str(actor.id))
			var actual: Dictionary = batch.consume(parallel.world,parallel.environment,visit_id,str(actor.id))
			var equal: bool = expected==actual
			ok = ok and equal
			rows.append({"visit_id":visit_id,"equal":equal,"water_candidates":candidates,"expected":expected,"actual":actual})
		batch.end_apply(parallel.environment)
	serial.environment.end_query()
	parallel.environment.end_query()
	var readonly: bool = serial.world.freeze()==input.facts and parallel.world.freeze()==input.facts
	ok = ok and readonly and _cache_view(serial.environment)==_cache_view(parallel.environment)
	var result: Dictionary = {"ok":ok,"name":input.name,"observations":rows,"queries_readonly":readonly,"worker_report":batch.report()}
	serial.simulation.dispose()
	parallel.simulation.dispose()
	return result

func _water_inputs(suite: RefCounted, content: HospitalContent) -> Dictionary:
	var seed: Dictionary = _seed(suite,content,2)
	if not str(seed.validation).is_empty() or seed.ids.size()!=2:
		return {"ok":false,"failure_kind":"fixture","prerequisite":"water_two_patients","reason":seed.validation,"admissions":seed.get("admissions",[])}
	var x: Dictionary = _bind(seed.facts,content)
	var subject: Dictionary = x.world.facts.actors[x.world.facts.visits[seed.ids[0]].actor_id]
	var peer: Dictionary = x.world.facts.actors[x.world.facts.visits[seed.ids[1]].actor_id]
	subject.location.cell = [48,80]
	peer.location.cell = [44,80]
	suite._add_facility(x.world,"worker_water_a","FUR17",null,[50,80])
	suite._add_facility(x.world,"worker_water_b","FUR17",null,[52,80])
	var rows: Array = []
	var checks: Dictionary = {}
	var input: Dictionary = {"ids":[seed.ids[0]],"name":"two_water_candidates"}
	input.facts = x.world.freeze()
	var available: Dictionary = _observation_pair(input,content)
	rows.append(available)
	checks.available = available.ok and available.observations.size()==1 and bool(available.observations[0].actual.water) and available.observations[0].water_candidates.size()==2
	peer.location.cell = x.space.facility_layout(x.world,"worker_water_a").patient_cell.duplicate()
	x.world.touch()
	input.facts = x.world.freeze()
	input.name = "current_body_at_first_water"
	var body: Dictionary = _observation_pair(input,content)
	rows.append(body)
	checks.current_body_uses_live_original_water_predicate = body.ok and not x.environment._water_usable(x.world,x.world.facts.facilities.worker_water_a,str(subject.id))
	peer.location.cell = [44,80]
	x.world.facts.facilities.worker_water_a.failed = true
	x.world.facts.facilities.worker_water_b.failed = true
	x.world.touch()
	input.facts = x.world.freeze()
	input.name = "failed_sources_contribute_no_water"
	var failed: Dictionary = _observation_pair(input,content)
	rows.append(failed)
	checks.both_failed = failed.ok and not bool(failed.observations[0].actual.water) and failed.observations[0].water_candidates.is_empty()
	x.world.facts.facilities.worker_water_a.failed = false
	var reserved: String = x.space.reserve_facility(x.world,"worker_water_a",str(peer.id),str(peer.id))
	checks.real_reservation_created = reserved.is_empty() and x.world.facts.adaptations.has("worker_water_a")
	if checks.real_reservation_created:
		for permission: bool in [false,true,false]:
			if permission:
				x.space.grant_facility_access(x.world,"worker_water_a",str(subject.id))
			else:
				x.world.facts.adaptations.worker_water_a.staff_ids.erase(subject.id)
				x.space.reservation_changed(x.world,"worker_water_a")
				x.space._navigation.invalidate(x.world,1)
			input.facts = x.world.freeze()
			input.name = "current_reservation_permission_"+str(permission)
			var observed: Dictionary = _observation_pair(input,content)
			rows.append(observed)
			checks["permission_boundary_"+str(rows.size())] = observed.ok and (subject.id in x.world.facts.adaptations.worker_water_a.staff_ids)==permission
	var validation: String = x.world.validate(content)
	x.simulation.dispose()
	return {"ok":seed.validation.is_empty() and validation.is_empty() and not checks.values().has(false),"checks":checks,"observations":rows,"validation":validation,"scope":"Access grant changes current reservation permission; it does not grant business ownership or bypass the original water predicate."}

func _numeric_finish(facts: Dictionary, content: HospitalContent) -> Dictionary:
	var x: Dictionary = _bind(facts,content)
	var worker: HospitalEnvironment = WorkerBatch.WorkerEnvironment.new(content,HospitalSpace.new(content))
	var rows: Array = []
	var ok: bool = true
	for point: Array in [[110,15],[110,20],[1,10],[102,0]]:
		var input: Dictionary = {"value":int(point[0]),"noise":int(point[1]),"water":false}
		var expected_input: Dictionary = input.duplicate(true)
		expected_input.water = true
		expected_input.value += int(content.balance.environment.water_bonus)
		var expected: Dictionary = x.environment._finish_observation(expected_input)
		var raw: Dictionary = worker._finish_observation(input)
		# Numeric finishing begins after an already successful main-thread water
		# decision. This is not a fabricated source or a legal-world flow claim.
		raw.water = true
		var batch: RefCounted = WorkerBatch.new()
		batch._last = {"consumed":0}
		batch._observations = {"numeric":{"coverage":{},"observation":raw}}
		var actual: Dictionary = batch.consume(x.world,x.environment,"numeric","")
		var equal: bool = actual==expected
		ok = ok and equal
		rows.append({"before_noise":point[0],"noise":point[1],"expected":expected,"actual":actual,"equal":equal})
	x.simulation.dispose()
	return {"ok":ok,"rows":rows,"scope":"Numeric function boundaries only; these raw totals are not asserted to arise from the authored legal hospital."}
