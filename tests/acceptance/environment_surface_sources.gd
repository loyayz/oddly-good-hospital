extends "res://tests/acceptance/environment_direct_query.gd"

func run_sources(database: HospitalContent, selected: Array) -> Dictionary:
	_content = database
	var cases: Dictionary = {"ENV-SOURCE-SCOPES":_source_scopes,"ENV-SOURCE-OWNERS":_source_owners,"ENV-SOURCE-RESTORE":_source_restore,"ENV-SOURCE-EDGES":_source_edges,"ENV-SOURCE-WORKERS":_source_workers}
	var rows: Dictionary = {}
	for id: String in selected:
		if not cases.has(id): return {"ok":false,"unknown_case":id}
		rows[id] = cases[id].call()
	return {"ok":not rows.is_empty() and rows.values().all(func(row: Dictionary)->bool:return row.ok),"cases":rows}

func _source_fixture() -> Dictionary:
	var x: Dictionary = _fixture()
	HospitalFactory._add_room(x.world,{"id":"room","type":"","anchor":[40,72],"size":[12,12],"door":{"definition_id":"DR04","edge":"south","offset":3}},_content)
	var helper: RefCounted = preload("res://tests/acceptance/environment_source_intersection.gd").new()
	helper._content = _content
	for x_cell: int in range(32,64):
		for y_cell: int in range(64,96): helper._surface(x,[x_cell,y_cell],"","MAT01")
	for offset: int in 12:
		helper._surface(x,[40+offset,72],"north","MAT05")
		helper._surface(x,[40+offset,83],"south","MAT08")
		helper._surface(x,[40,72+offset],"west","MAT05")
		helper._surface(x,[51,72+offset],"east","MAT08")
	for index: int in 12: x.e.spawn_dirt(x.world,"CL01","source_%d"%index,"source:%d"%index,1,[34+index*2,88])
	x.world.touch()
	return x

func _source_scopes() -> Dictionary:
	var x: Dictionary = _source_fixture()
	var reference: HospitalEnvironment = _reference_for(x)
	var comparisons: Array = []
	for cell: Array in [[40,72],[41,73],[50,82],[44,78],[34,88],[60,94],[0,0],[40.5,72.5]]:
		comparisons.append(_compare_direct(x,reference,cell))
	var before: Dictionary = x.world.freeze()
	var wall_visits: int = _count(x.space,"surfaces_source_visits")
	var dirt_visits: int = _count(x.space,"dirt_source_visits")
	var wall_builds: int = _count(x.space,"surfaces_source_builds")
	var dirt_builds: int = _count(x.space,"dirt_source_builds")
	for repeat: int in 300:
		x.e.sample_at(x.world,1,[40+repeat%12,72+repeat%12])
	var checks: Dictionary = {"legal_input":x.world.validate(_content).is_empty(),"complete_observations_match_raw":comparisons.all(func(row: Dictionary)->bool:return row.ok),"read_only_complete_facts_and_random":x.world.freeze()==before,"warm_scopes_no_source_enumeration":_count(x.space,"surfaces_source_visits")==wall_visits and _count(x.space,"dirt_source_visits")==dirt_visits and wall_visits>0 and dirt_builds>0,"warm_scopes_no_source_rebuild":_count(x.space,"surfaces_source_builds")==wall_builds and _count(x.space,"dirt_source_builds")==dirt_builds}
	x.world.touch()
	checks.unrelated_geometry_does_not_rebuild_positions = _compare_direct(x,reference,[40,72]).ok and _count(x.space,"surfaces_source_builds")==wall_builds and _count(x.space,"dirt_source_builds")==dirt_builds
	# Position identity is stable, but replaced material/value records are live.
	var key: String = x.e._surface_key(1,[40,72],"wall","north")
	x.world.facts.environment.surfaces[key] = x.world.facts.environment.surfaces[key].duplicate(true)
	x.world.facts.environment.surfaces[key].material_id = "MAT08"
	checks.same_key_record_replacement_is_live = _compare_direct(x,reference,[40,72]).ok
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"warm_scopes":300,"source_records":{"surfaces":wall_visits,"dirt":dirt_visits},"comparisons":comparisons}
	Coverage.new()._dispose(x)
	return result

func _source_restore() -> Dictionary:
	var x: Dictionary = _source_fixture()
	var reference: HospitalEnvironment = _reference_for(x)
	var checks: Dictionary = {"initial":_compare_direct(x,reference,[40,72]).ok}
	for collection: String in ["surfaces","dirt"]:
		var builds: int = _count(x.space,collection+"_source_builds")
		x.world.facts.environment[collection] = x.world.facts.environment[collection].duplicate(true)
		checks[collection+"_same_count_replacement"] = _compare_direct(x,reference,[40,72]).ok and _count(x.space,collection+"_source_builds")==builds+1
	var id: String = str(x.world.facts.environment.dirt.keys()[0])
	x.world.facts.environment.dirt.erase(id)
	checks.raw_removal_count_rebuilds = _compare_direct(x,reference,[34,88]).ok
	x.world.facts = x.world.freeze().duplicate(true)
	checks.same_world_facts_replacement = _compare_direct(x,reference,[40,72]).ok
	var old: WorldState = x.world
	x.world = WorldState.new(old.freeze())
	checks.other_world_same_numeric_identity = _compare_direct(x,reference,[40,72]).ok
	# Alternating an explicit foreign-world read must preserve the open owner.
	x.e.begin_query(x.world)
	checks.foreign_query_preserves_scope = _compare_direct({"world":old,"e":x.e},reference,[34,88]).ok and x.e._query.world==x.world
	x.e.end_query()
	var empty: WorldState = WorldState.new(x.world.freeze())
	empty.facts.environment.dirt.clear();empty.facts.environment.surfaces.clear()
	checks.empty_replacement_clears_maps = _compare_direct({"world":empty,"e":x.e},reference,[40,72]).ok and x.e._surface_sources._views.dirt.floors.is_empty() and x.e._surface_sources._views.surfaces.floors.is_empty()
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks}
	Coverage.new()._dispose(x)
	return result

func _source_owners() -> Dictionary:
	var suite: RefCounted = preload("res://tests/acceptance/operations.gd").new()
	suite._content = _content
	var f: Dictionary = suite._new("Environment source owner boundaries",false,20000)
	HospitalFactory._add_room(f.w,{"id":"room","type":"","anchor":[40,72],"size":[12,12],"door":{"definition_id":"DR04","edge":"south","offset":3}},_content)
	f.w.touch()
	suite._staff(f,"source_cleaner","cleaner",[38,88])
	var x: Dictionary = {"world":f.w,"e":f.s.services.environment,"space":f.s.space}
	var reference: HospitalEnvironment = _reference_for(x)
	var checks: Dictionary = {"warm_empty":_compare_direct(x,reference,[40,88]).ok}
	# A neutral, genuinely enclosed room supplies the actual west wall; waiting
	# space is an area, not a room type.
	checks.real_wall_fixture = f.w.facts.rooms.has("room") and x.e._wall_edge(f.w,1,[40,78],"west")
	var builds: int = _count(x.space,"dirt_source_builds")
	var id: String = x.e.spawn_dirt(f.w,"CL01","warm_new","warm_new:1",1,[40,88])
	checks.actual_spawn_updates_one = not id.is_empty() and _compare_direct(x,reference,[40,88]).ok and _count(x.space,"dirt_source_builds")==builds and x.e.sample_at(f.w,1,[40,88]).dirt==1
	var boundaries: Array = []
	var observer: Callable = func(stage: String) -> void:
		boundaries.append(_compare_direct(x,reference,[40,88]))
	for _step: int in 250:
		suite._work_tick(f,"environment",observer)
		if not f.w.facts.environment.dirt.has(id): break
	checks.actual_cleanup_clears_last_source_without_rebuild = not f.w.facts.environment.dirt.has(id) and f.w.facts.environment.receipts.get(id+":cleanup_completed",{}).get("standard_work_milli")==4000 and _count(x.space,"dirt_source_builds")==builds and x.e._surface_sources._views.dirt.floors.is_empty() and boundaries.all(func(row: Dictionary)->bool:return row.ok)
	checks.tool_placed = suite._construction_tools(f)
	var wall_builds: int = _count(x.space,"surfaces_source_builds")
	var rows: Array = []
	for material: String in ["MAT05","MAT08"]:
		var applied: CommandResult = suite._command(f,"renovation_order",{"material_id":material,"floor_id":1,"units":[{"cell":[40,78],"edge":"west"}]})
		if not applied.accepted:
			rows.append({"ok":false,"reason":applied.reason});continue
		var order_id: String = str(applied.changed_ids[0])
		var order: Dictionary = f.w.facts.environment.orders[order_id]
		var samples_equal: bool = true
		for _step: int in 600:
			suite._work_tick(f,"environment")
			samples_equal = _compare_direct(x,reference,[40,78]).ok and samples_equal
			if order.phase=="completed": break
		var key: String = x.e._surface_key(1,[40,78],"wall","west")
		rows.append({"ok":order.phase=="completed" and samples_equal and f.w.facts.environment.surfaces.get(key,{}).get("material_id")==material,"material":material,"phase":order.phase,"samples_equal":samples_equal})
	checks.real_wall_install_and_same_key_replacement = rows.size()==2 and rows.all(func(row: Dictionary)->bool:return row.ok)
	checks.wall_owners_no_full_rebuild = _count(x.space,"surfaces_source_builds")==wall_builds and _count(x.space,"surfaces_source_updates")>=2
	checks.valid_final = f.w.validate(_content).is_empty()
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"wall_orders":rows,"final_validation":f.w.validate(_content),"dirt_boundaries":boundaries.size()}
	for sim: HospitalSimulation in suite._live: sim.dispose()
	suite._live.clear()
	return result

# Index-contract calculations are separate from the real owner work above.
func _source_edges() -> Dictionary:
	var x: Dictionary = _source_fixture()
	var reference: HospitalEnvironment = _reference_for(x)
	var checks: Dictionary = {"initial":_compare_direct(x,reference,[34,88]).ok}
	var view: Dictionary = x.e._surface_sources._views.dirt
	var old_bounds: Rect2i = view.bounds[1]
	var id: String = str(x.world.facts.environment.dirt.keys()[0])
	x.e._surface_sources.removing(x.world,x.space,"dirt",id)
	x.world.facts.environment.dirt.erase(id)
	checks.removing_extreme_retains_safe_bound = view.bounds[1]==old_bounds and not view.floors.is_empty() and _compare_direct(x,reference,[34,88]).ok
	var helper: RefCounted = preload("res://tests/acceptance/environment_source_intersection.gd").new()
	helper._content = _content
	var key: String = helper._surface(x,[44,78],"","MAT02")
	var builds: int = _count(x.space,"surfaces_source_builds")
	x.e._surface_sources.written(x.world,x.space,"surfaces",key)
	checks.excluded_floor_replacement_keeps_count = x.e._surface_sources._views.surfaces.members.has(key) and x.e._surface_sources._views.surfaces.members[key]==null and _compare_direct(x,reference,[44,78]).ok and _count(x.space,"surfaces_source_builds")==builds
	_facility(x,"source_bin","FUR18",[60,80]);x.world.touch()
	var dirt_builds: int = _count(x.space,"dirt_source_builds")
	var bin_id: String = x.e.spawn_dirt(x.world,"CL02","bin_use","bin_use:1",1,[60,80])
	checks.actual_bin_excluded_without_rebuild = not bin_id.is_empty() and x.world.facts.environment.dirt[bin_id].bin_id=="source_bin" and view.members.has(bin_id) and view.members[bin_id]==null and _compare_direct(x,reference,[60,80]).ok and _count(x.space,"dirt_source_builds")==dirt_builds
	checks.legal_gameplay_inputs = x.world.validate(_content).is_empty()
	# Large raw coordinates are only key/bounds calculation inputs, not a legal
	# hospital floor or a claimed simulated renovation.
	var raw: WorldState = WorldState.new(x.world.freeze())
	var raw_key: String = x.e._surface_key(1,[4294967300,78],"wall","west")
	raw.facts.environment.surfaces = {raw_key:{"floor_id":1,"cell":[4294967300,78],"surface":"wall","edge":"west","material_id":"MAT05"}}
	var positions: Dictionary = x.e._surface_sources.sources(raw,x.space,"surfaces")
	checks.raw_64_bit_key_and_conservative_fallback = positions[1].has("4294967300:78") and x.e._surface_sources.bounds("surfaces")[1]==null
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks}
	Coverage.new()._dispose(x)
	return result

func _source_workers() -> Dictionary:
	var x: Dictionary = _source_fixture()
	var batch_script: GDScript = preload("res://game/operations/environment_sample_batch.gd")
	var rows: Array = []
	for round_index: int in 2:
		if round_index==1: x.e.spawn_dirt(x.world,"CL01","worker_new","worker_new:1",1,[44,78])
		for count: int in [1,4]:
			x.e.begin_query(x.world)
			x.e._prepare_facility_sources(x.world);x.e._prepare_sample_sources(x.world)
			var bounds: Variant = x.e._prepare_observation_bounds(x.world)
			x.e._coverage_edges(x.world,1)
			var requests: Array = [["wall","",1,[40,72]],["dirt","",1,[34,88]],["new","",1,[44,78]],["floor","",1,[60,94]]]
			var expected: Array = []
			for request: Array in requests: expected.append(x.e.sample_at(x.world,1,request[3]))
			var before: Dictionary = x.world.freeze()
			var jobs: Array = []
			for index: int in count:
				var job: RefCounted = batch_script.SampleJob.new(_content)
				job.prepare(x.e,x.world,requests.slice(requests.size()*index/count,requests.size()*(index+1)/count),{},true,bounds)
				jobs.append(job)
			if count==1:
				jobs[0].run()
			else:
				var group: int = WorkerThreadPool.add_group_task(func(index: int)->void:jobs[index].run(),count,count,false,"Source index acceptance")
				WorkerThreadPool.wait_for_group_task_completion(group)
			var actual: Array = []
			var borrowed: bool = true
			for job: RefCounted in jobs:
				borrowed = borrowed and is_same(job.environment._query.samples.walls,x.e._query.samples.walls) and is_same(job.environment._query.samples.dirt,x.e._query.samples.dirt) and job.environment._surface_sources._views.is_empty()
				for result: Array in job.results: actual.append(result[batch_script.ResultSlot.OBSERVATION])
				job.release_borrowed()
			rows.append({"round":round_index,"workers":count,"ok":actual==expected and before==x.world.freeze() and borrowed,"full_values_match":actual==expected,"facts_and_random_readonly":before==x.world.freeze(),"borrowed_without_rebuild":borrowed})
			x.e.end_query()
	var result: Dictionary = {"ok":rows.all(func(row: Dictionary)->bool:return row.ok),"rows":rows}
	Coverage.new()._dispose(x)
	return result
