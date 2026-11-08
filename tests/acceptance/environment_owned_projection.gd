extends "res://tests/acceptance/staff_fixtures.gd"

const Batch = preload("res://game/operations/environment_sample_batch.gd")
var _contexts: Array = []
var _sources: Array = []

class CustomSpace extends HospitalSpace:
	var owned_calls: int = 0
	func owned(_world: WorldState, _floor_id: int, _cell: Vector2i) -> bool:
		owned_calls += 1
		return false

class CustomEnvironment extends HospitalEnvironment:
	pass

func _context(other: bool = false, legacy: bool = false, zero_plot: bool = false) -> Dictionary:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"所有权投影计算前提",false,_content)
	world.facts.floors.overrides["1"].plots = [[1,2],[2,2]]
	world.facts.floors.height_intervals[0].last = 2
	world.facts.floors.overrides["2"] = {"plots":[[4294967297,2]] if legacy else [[2,2]],"blocked":[],"doors":[],"paths":[]}
	if not legacy: world.facts.floors.completed_top_floor = {"1:2":2,"2:2":1} if other else {"1:2":1,"2:2":2}
	if zero_plot:
		# Existing ground ownership connects the starting plot to the origin.
		world.facts.floors.overrides["1"].plots.append_array([[0,2],[0,1],[0,0]])
		world.facts.floors.completed_top_floor.merge({"0:2":1,"0:1":1,"0:0":1})
	var x: Dictionary = _bind(world)
	x.validation = world.validate(_content)
	x.before = world.freeze()
	x.legacy = legacy
	_contexts.append(x)
	return x

# The expected answer comes from raw plot rectangles, not the projection map.
# A plot is 32 by 32 cells and its upper X/Y edges are excluded.
func _expected(world: WorldState, floor_id: int, cell: Vector2i) -> bool:
	if floor_id<1 or cell.x<0 or cell.y<0 or cell.x>=96 or cell.y>=96: return false
	var floors: Dictionary = world.facts.floors
	var plots: Array = floors.overrides.get(str(floor_id),{}).get("plots",[])
	if floors.has("completed_top_floor"): plots = floors.overrides["1"].plots
	for plot: Array in plots:
		if floors.has("completed_top_floor") and floor_id>int(floors.completed_top_floor.get("%d:%d" % plot,1)): continue
		var left: int = int(plot[0])*32
		var top: int = int(plot[1])*32
		if cell.x>=left and cell.x<left+32 and cell.y>=top and cell.y<top+32: return true
	return false

func _source(x: Dictionary, service: HospitalEnvironment = null) -> HospitalEnvironment:
	var source: HospitalEnvironment = service if service!=null else x.e
	source.begin_query(x.world)
	source._prepare_facility_sources(x.world)
	source._prepare_sample_sources(x.world)
	for floor_id: int in [1,2,3]: source._coverage_edges(x.world,floor_id)
	_sources.append(source)
	return source

func _job(source: HospitalEnvironment, world: WorldState, diagnostics: bool = true) -> RefCounted:
	var job: RefCounted = Batch.SampleJob.new(_content)
	job.prepare(source,world,[],{},diagnostics)
	return job

func _probe(job: RefCounted, x: Dictionary, name: String, floor_id: int, cell: Vector2i, mode: String, override_result: Variant = null) -> Dictionary:
	var worker: RefCounted = job.environment
	var fast: int = worker._owned_fast_checks
	var fallback: int = worker._owned_fallback_checks
	var expected: bool = _expected(x.world,floor_id,cell) if override_result==null else bool(override_result)
	var actual: bool = worker._owned_at(x.world,floor_id,cell)
	fast = int(worker._owned_fast_checks)-fast
	fallback = int(worker._owned_fallback_checks)-fallback
	var witnessed: bool = fast==1 and fallback==0 if mode=="fast" else fast==0 and fallback==1
	if mode=="diagnostics_off": witnessed = fast==0 and fallback==0
	return {"name":name,"floor_id":floor_id,"cell":[cell.x,cell.y],"expected":expected,"actual":actual,"mode":mode,
		"fast_checks":fast,"fallback_checks":fallback,"facts_readonly":x.world.freeze()==x.before,
		"ok":actual==expected and witnessed and x.world.freeze()==x.before}

func _released(job: RefCounted) -> bool:
	var worker: RefCounted = job.environment
	return job.world==null and job.requests.is_empty() and worker._query.is_empty() and worker._query_depth==0 and worker._coverage_cache.is_empty() and worker.coverage_seed.is_empty() and worker._facility_sources.is_empty() and not worker._owned_diagnostics and worker._owned_fast_checks==0 and worker._owned_fallback_checks==0

func _sample_probe(job: RefCounted, x: Dictionary, cell: Array) -> Dictionary:
	var worker: RefCounted = job.environment
	var fast: int = worker._owned_fast_checks
	var fallback: int = worker._owned_fallback_checks
	var normalized: Vector2i = Vector2i(int(cell[0]),int(cell[1]))
	var expected: String = "current" if _expected(x.world,2,normalized) else "outside_owned_floor"
	var actual: Dictionary = worker.sample_at(x.world,2,cell)
	fast = int(worker._owned_fast_checks)-fast
	fallback = int(worker._owned_fallback_checks)-fallback
	var readonly: bool = x.world.freeze()==x.before
	return {"name":"array_float_sample_entry","floor_id":2,"cell":cell,"normalized_cell":[normalized.x,normalized.y],
		"expected_status":expected,"actual_status":actual.status,"fast_checks":fast,"fallback_checks":fallback,"facts_readonly":readonly,
		"ok":actual.status==expected and fast==1 and fallback==0 and readonly}

func _result(rows: Array, checks: Dictionary = {}) -> Dictionary:
	return {"ok":rows.all(func(row: Dictionary)->bool:return row.ok) and not checks.values().has(false),"rows":rows,"checks":checks}

func _boundaries() -> Dictionary:
	var x: Dictionary = _context()
	var source: HospitalEnvironment = _source(x)
	var source_edges: Dictionary = source._query.edges.duplicate(true)
	var job: RefCounted = _job(source,x.world)
	var rows: Array = []
	for floor_id: int in [1,2]:
		for cell: Vector2i in [Vector2i(31,80),Vector2i(32,80),Vector2i(63,80),Vector2i(64,80),Vector2i(95,95),Vector2i(96,80),Vector2i(-1,80),Vector2i(44,80)]:
			rows.append(_probe(job,x,"plot_half_open_and_floor",floor_id,cell,"fast"))
	rows.append(_probe(job,x,"legal_empty_floor_projection",3,Vector2i(44,80),"fast"))
	for cell: Array in [[63.99,80.99],[64.01,80.99]]: rows.append(_sample_probe(job,x,cell))
	var checks: Dictionary = {"canonical_world_valid":x.validation.is_empty(),"source_projection_unmodified":source._query.edges==source_edges,
		"owned_mapping_borrowed":is_same(job.environment._query.edges[1].owned,source._query.edges[1].owned)}
	job.release_borrowed()
	checks.borrow_released = _released(job)
	var zero: Dictionary = _context(false,false,true)
	var zero_source: HospitalEnvironment = _source(zero)
	var zero_job: RefCounted = _job(zero_source,zero.world)
	rows.append(_probe(zero_job,zero,"owned_origin_is_included",1,Vector2i(0,0),"fast"))
	zero_job.release_borrowed()
	checks.origin_world_valid = zero.validation.is_empty()
	checks.origin_borrow_released = _released(zero_job)
	return _result(rows,checks)

func _fallback_metadata() -> Dictionary:
	var x: Dictionary = _context()
	var source: HospitalEnvironment = _source(x)
	var source_edges: Dictionary = source._query.edges.duplicate(true)
	var job: RefCounted = _job(source,x.world)
	var original: Dictionary = job.environment._query.edges
	var rows: Array = []
	# Only worker query metadata is replaced. Actors and world facts stay legal.
	for fault: Dictionary in [{"name":"edges_wrong_type","edges":[]},{"name":"missing_floor","edges":{}},{"name":"floor_wrong_type","edges":{1:[]}},
		{"name":"missing_owned","edges":{1:{}}},{"name":"owned_wrong_type","edges":{1:{"owned":[]}}},{"name":"owned_null","edges":{1:{"owned":null}}}]:
		job.environment._query.edges = fault.edges
		rows.append(_probe(job,x,fault.name,1,Vector2i(44,80),"fallback"))
	job.environment._query.edges = original
	rows.append(_probe(job,x,"projection_restored",1,Vector2i(44,80),"fast"))
	job.release_borrowed()
	return _result(rows,{"canonical_world_valid":x.validation.is_empty(),"source_projection_unmodified":source._query.edges==source_edges,"borrow_released":_released(job)})

func _scope_lifecycle() -> Dictionary:
	var x: Dictionary = _context()
	var other: Dictionary = _context(true)
	var source: HospitalEnvironment = _source(x)
	var second: HospitalEnvironment = _source(other)
	var job: RefCounted = _job(source,x.world)
	var rows: Array = [_probe(job,x,"initial_scope",1,Vector2i(44,80),"fast")]
	job.environment.end_query()
	rows.append(_probe(job,x,"closed_scope",1,Vector2i(44,80),"fallback"))
	job.environment.begin_query(x.world)
	rows.append(_probe(job,x,"same_world_new_scope_has_no_borrow_proof",1,Vector2i(44,80),"fallback"))
	job.release_borrowed()
	var checks: Dictionary = {"first_release_clears_borrow":_released(job),"both_worlds_valid":x.validation.is_empty() and other.validation.is_empty()}
	job.prepare(source,x.world,[],{},true)
	rows.append(_probe(job,other,"foreign_world_uses_current_facts",2,Vector2i(44,80),"fallback"))
	job.release_borrowed()
	job.prepare(second,other.world,[],{},true)
	checks.reused_job_counters_reset = job.environment._owned_fast_checks==0 and job.environment._owned_fallback_checks==0
	rows.append(_probe(job,other,"same_job_rebound_to_other_world",2,Vector2i(44,80),"fast"))
	job.release_borrowed()
	job.prepare(second,other.world,[],{},false)
	rows.append(_probe(job,other,"diagnostics_disabled",1,Vector2i(80,80),"diagnostics_off"))
	job.release_borrowed()
	checks.final_release_clears_borrow = _released(job)
	job.prepare(source,x.world,[],{},true)
	rows.append(_probe(job,x,"same_world_before_property_change",2,Vector2i(44,80),"fast"))
	var old_owned: Dictionary = job.environment._query.edges[2].owned
	var old_view: Dictionary = old_owned.duplicate()
	job.release_borrowed()
	checks.property_change_old_borrow_released = _released(job)
	source.end_query()
	checks.property_change_source_closed = source._query_depth==0 and source._query.is_empty()
	checks.before_property_change_queries_readonly = x.world.freeze()==x.before
	# This is the next legal historical ownership input. Construction and its
	# completion are not exercised; each query interval has its own snapshot.
	x.world.facts.floors.completed_top_floor["1:2"] = 2
	x.world.touch()
	var changed_validation: String = x.world.validate(_content)
	checks.changed_ownership_world_valid = changed_validation.is_empty()
	x.before = x.world.freeze()
	var reopened: HospitalEnvironment = _source(x)
	checks.same_source_instance_reopened = is_same(source,reopened)
	job.prepare(reopened,x.world,[],{},true)
	checks.property_change_projection_replaced = not is_same(old_owned,job.environment._query.edges[2].owned) and old_owned==old_view
	rows.append(_probe(job,x,"same_world_changed_property_reprepared",2,Vector2i(44,80),"fast"))
	job.release_borrowed()
	checks.property_change_new_borrow_released = _released(job)
	var result: Dictionary = _result(rows,checks)
	result.changed_ownership_validation = changed_validation
	return result

func _overrides_legacy() -> Dictionary:
	var x: Dictionary = _context()
	var rows: Array = []
	var source_space: CustomSpace = CustomSpace.new(_content)
	var custom_source: HospitalEnvironment = _source(x,HospitalEnvironment.new(_content,source_space))
	var job: RefCounted = _job(custom_source,x.world)
	rows.append(_probe(job,x,"custom_source_space_disables_projection",1,Vector2i(44,80),"fallback"))
	job.release_borrowed()
	var inherited: HospitalEnvironment = _source(x,CustomEnvironment.new(_content,x.space))
	job.prepare(inherited,x.world,[],{},true)
	rows.append(_probe(job,x,"custom_source_environment_disables_projection",1,Vector2i(44,80),"fallback"))
	job.release_borrowed()
	var standard: HospitalEnvironment = _source(x)
	job.prepare(standard,x.world,[],{},true)
	var worker_space: CustomSpace = CustomSpace.new(_content)
	job.environment.space = worker_space
	rows.append(_probe(job,x,"worker_space_override_called",1,Vector2i(44,80),"fallback",false))
	var checks: Dictionary = {"worker_space_override_observed":worker_space.owned_calls==1}
	job.release_borrowed()
	checks.custom_job_release = _released(job)
	var legacy: Dictionary = _context(false,true)
	var legacy_source: HospitalEnvironment = _source(legacy)
	var legacy_job: RefCounted = _job(legacy_source,legacy.world)
	rows.append(_probe(legacy_job,legacy,"legacy_large_upper_plot_retains_raw_rectangle_check",2,Vector2i(44,80),"fallback"))
	legacy_job.release_borrowed()
	checks.legacy_release = _released(legacy_job)
	var result: Dictionary = _result(rows,checks)
	result.legacy_validation = legacy.validation
	result.scope = "Custom-source direct jobs retain their own standard worker Space; public Department custom-source rejection is checked once by GROW-75. Legacy upper-plot input is a projection calculation boundary, not a normal-flow reproduction."
	return result

func run(database: HospitalContent, selected: Array = []) -> Dictionary:
	_content = database
	if selected.is_empty(): selected = ["boundaries","fallback_metadata","scope_lifecycle","overrides_legacy"]
	var groups: Dictionary = {}
	for group: String in selected:
		match group:
			"boundaries": groups[group] = _boundaries()
			"fallback_metadata": groups[group] = _fallback_metadata()
			"scope_lifecycle": groups[group] = _scope_lifecycle()
			"overrides_legacy": groups[group] = _overrides_legacy()
			_: groups[group] = {"ok":false,"reason":"Unknown owned-projection group"}
	var readonly: bool = true
	for x: Dictionary in _contexts: readonly = readonly and x.world.freeze()==x.before
	for source: HospitalEnvironment in _sources:
		while source._query_depth>0: source.end_query()
		source.waiting_life = null
	for x: Dictionary in _contexts:
		x.a.dispose()
		x.p.waiting_life = null
		x.p.environment = null
		x.l.environment = null
		x.l.visitors = null
		x.c.recruitment = null
		x.clear()
	_sources.clear()
	_contexts.clear()
	var ok: bool = readonly
	for group: Dictionary in groups.values(): ok = ok and bool(group.ok)
	return {"ok":ok,"groups":groups,"facts_readonly_after_binding":readonly,
		"rule_source":"docs/design/01-simulation.md:41-45; HospitalSpace ownership contract: raw 32x32 plot rectangles, half-open bounds and completed floor ownership. Counter expectations observe production branches, not a duplicate projection lookup.",
		"scope":"Snapshots are frozen after service binding and before every query. Out-of-floor cells and fault metadata are calculation inputs; no actor relocation, movement or work completion is fabricated."}
