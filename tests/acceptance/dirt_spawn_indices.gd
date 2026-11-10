extends SceneTree

# Scope: §20 spawn selection, bounded derived indices and their invalidation.
# Cleanup uses actual dispatch, travel and work; no completion is synthesized.
var _oracle: RefCounted
var _checks: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func _count(space: HospitalSpace, key: String) -> int:
	return int(space.query_counts.get(key,0))

func _nearest(world: WorldState, space: HospitalSpace, origin: Array) -> Array:
	var candidates: Array = []
	for x: int in range(int(origin[0])-4,int(origin[0])+5):
		for y: int in range(int(origin[1])-4,int(origin[1])+5):
			if _oracle._ground_full(world,space,1,[x,y]):
				candidates.append({"cell":[x,y],"distance":absi(x-int(origin[0]))+absi(y-int(origin[1]))})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.distance<b.distance if a.distance!=b.distance else (a.cell[0]<b.cell[0] if a.cell[0]!=b.cell[0] else a.cell[1]<b.cell[1]))
	return [] if candidates.is_empty() else candidates[0].cell

func _ground_case(f: Dictionary, source: String, origin: Array, content: HospitalContent) -> bool:
	var target: Array = _nearest(f.w,f.s.space,origin)
	if target.is_empty(): return false
	# Independent complete expected facts, using only the specified spawn fields.
	var expected: WorldState = WorldState.new(f.w.freeze())
	var id: String = expected.new_id("dirt")
	var work: int = int(content.definition("cleanup_sources","CL01").work_seconds)*1000
	expected.facts.environment.dirt[id] = {"id":id,"source_kind":"CL01","source_id":source,"source_receipt":source+":1","floor_id":1,"cell":target.duplicate(),"bin_id":"","generated_tick":expected.sim_tick,"total_milli":work,"remaining_milli":work,"contributions":{},"worker_id":"","work_cell":[],"phase":"queued","reason":""}
	expected.touch(false)
	var actual: String = f.s.services.environment.spawn_dirt(f.w,"CL01",source,source+":1",1,origin)
	return actual==id and f.w.freeze()==expected.freeze()

func _raw_reservations(f: Dictionary) -> void:
	# Explicit calculation-only worlds: no claimed service or completed event.
	var world: WorldState = WorldState.new(f.w.freeze())
	var e: HospitalEnvironment = f.s.services.environment
	var space: HospitalSpace = f.s.space
	world.facts.environment.dirt = {}
	world.facts.adaptations = {"calculation_regions":{"floor_id":1,"regions":[[40,88,1,1],[44,88,1,1]]}}
	_checks.disjoint_regions_do_not_fill_gap = not e._ground_spawn_legal(world,1,[40,88]) and not e._ground_spawn_legal(world,1,[44,88]) and e._ground_spawn_legal(world,1,[42,88])
	world.facts.adaptations = {"other_floor":{"floor_id":2,"regions":[[40,88,5,1]]}}
	_checks.other_floor_reservation_ignored = e._ground_spawn_legal(world,1,[42,88])
	world.facts.adaptations = {"all_candidates":{"floor_id":1,"regions":[[38,84,9,9]]}}
	var before: Dictionary = world.freeze()
	_checks.all_candidates_reserved_atomic = e.spawn_dirt(world,"CL01","blocked","blocked:1",1,[42,88]).is_empty() and world.freeze()==before
	# Return to the original owner after a same-service calculation projection.
	_checks.original_world_after_projection = e._ground_spawn_legal(f.w,1,[42,88])==_oracle._ground_full(f.w,space,1,[42,88])

func _cleanup_owner(suite: RefCounted, content: HospitalContent) -> void:
	var f: Dictionary = suite._new("Warm dirt index cleanup boundary")
	var e: HospitalEnvironment = f.s.services.environment
	var space: HospitalSpace = f.s.space
	var id: String = e.spawn_dirt(f.w,"CL01","cleanup_source","cleanup_source:1",1,[42,80])
	suite._staff(f,"index_cleaner","cleaner",[40,80])
	var boundary: Dictionary = {}
	var observe: Callable = func(stage: String) -> void:
		if stage=="before":
			e._ground_spawn_view(f.w,1)
			boundary.builds = _count(space,"dirt_spawn_dirt_builds")
			boundary.visits = _count(space,"dirt_spawn_dirt_visits")
		elif not f.w.facts.environment.dirt.has(id):
			e._ground_spawn_view(f.w,1)
			var dirt: Dictionary = e._spawn_index.dirt(f.w,space)
			boundary.released = not dirt.sources.get("CL01",{}).has("cleanup_source") and dirt.points.get(1,{}).is_empty() and dirt.plots.get(1,{}).is_empty()
			boundary.no_rebuild = _count(space,"dirt_spawn_dirt_builds")==boundary.builds and _count(space,"dirt_spawn_dirt_visits")==boundary.visits
	for tick: int in 200:
		suite._work_tick(f,"environment",observe)
		if not f.w.facts.environment.dirt.has(id): break
	var receipt: Dictionary = f.w.facts.environment.receipts.get(id+":cleanup_completed",{})
	_checks.actual_cleanup_updates_warm_maps = not id.is_empty() and receipt.get("standard_work_milli")==4000 and boundary.get("released",false) and boundary.get("no_rebuild",false) and f.w.validate(content).is_empty()
	# This source becomes eligible again only after the actual completed work.
	_checks.cleaned_source_can_spawn_again = not e.spawn_dirt(f.w,"CL01","cleanup_source","cleanup_source:2",1,[42,80]).is_empty()

func _floor_retention(f: Dictionary) -> void:
	# Empty floor inputs exercise retention only; no fictitious owned floors.
	var world: WorldState = WorldState.new(f.w.freeze())
	var e: HospitalEnvironment = f.s.services.environment
	var before: Dictionary = world.freeze()
	for floor_id: int in range(20,30): e._ground_spawn_view(world,floor_id)
	_checks.floor_retention_bounded = e._spawn_index._layout.floors.size()<=8 and world.freeze()==before
	var builds: int = _count(f.s.space,"dirt_spawn_layout_builds")
	e._ground_spawn_view(world,29)
	_checks.empty_floor_identity_stable = _count(f.s.space,"dirt_spawn_layout_builds")==builds

func _restored_over_budget(f: Dictionary, content: HospitalContent) -> void:
	# Legal restored calculation input may exceed today's capacity. It is not
	# produced by pretending that a capped spawn or cleanup event completed.
	var world: WorldState = WorldState.new(f.w.freeze())
	var e: HospitalEnvironment = f.s.services.environment
	var template: Dictionary = world.facts.environment.dirt.values().filter(func(patch: Dictionary)->bool:return patch.bin_id.is_empty())[0]
	var duplicate_ids: Array = []
	for ordinal: int in 3:
		var point: Array = _nearest(world,f.s.space,[60,90])
		var id: String = world.new_id("dirt")
		var patch: Dictionary = template.duplicate(true)
		patch.id = id
		patch.cell = point
		patch.source_id = "restored_duplicate_source"
		world.facts.environment.dirt[id] = patch
		duplicate_ids.append(id)
	var before: Dictionary = world.freeze()
	var count: int = int(content.balance.cleanup.active_patches_per_plot)+3
	var lookup: Dictionary = e._spawn_index.dirt(world,f.s.space)
	_checks.over_budget_restore_preserved = world.validate(content).is_empty() and world.facts.environment.dirt.size()==count and int(lookup.plots.get(1,{}).get("1:2",0))==count and e.spawn_dirt(world,"CL01","restored_overflow","restored_overflow:1",1,[60,90]).is_empty() and world.freeze()==before
	_checks.restored_duplicate_source_order = lookup.sources.CL01.restored_duplicate_source==duplicate_ids and e.spawn_dirt(world,"CL01","restored_duplicate_source","duplicate:1",1,[60,90])==duplicate_ids[0] and world.freeze()==before

func run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var suite: RefCounted = load("res://tests/acceptance/operations.gd").new()
	suite._content = content
	_oracle = load("res://tests/acceptance/operations_repeated_work.gd").new()
	var f: Dictionary = suite._new("Dirt spawn indices")
	var e: HospitalEnvironment = f.s.services.environment
	var space: HospitalSpace = f.s.space
	_checks.formal_setup = suite._place(f,"index_screen","FUR23",[50,80]) and suite._place(f,"index_chair","FUR05",[54,80])
	_checks.initial_valid = f.w.validate(content).is_empty()
	var before: Dictionary = f.w.freeze()
	e._ground_spawn_view(f.w,1)
	_checks.layout_query_readonly = before==f.w.freeze()
	_checks.first_spawn_full_facts = _ground_case(f,"ground_first",[42,80],content)
	var layout_builds: int = _count(space,"dirt_spawn_layout_builds")
	var facility_visits: int = _count(space,"dirt_spawn_facility_visits")
	var dirt_builds: int = _count(space,"dirt_spawn_dirt_builds")
	var dirt_visits: int = _count(space,"dirt_spawn_dirt_visits")
	var revision: int = f.w.geometry_revision
	var exact: bool = true
	for ordinal: int in 12: exact = _ground_case(f,"ground_repeat_%d"%ordinal,[42,80],content) and exact
	_checks.repeated_full_facts_oracle = exact
	_checks.repeated_spawns_no_full_scans = layout_builds>0 and dirt_builds>0 and _count(space,"dirt_spawn_layout_builds")==layout_builds and _count(space,"dirt_spawn_facility_visits")==facility_visits and _count(space,"dirt_spawn_dirt_builds")==dirt_builds and _count(space,"dirt_spawn_dirt_visits")==dirt_visits
	_checks.dirt_does_not_invalidate_layout = f.w.geometry_revision==revision
	var first_id: String = str(f.w.facts.environment.dirt.keys()[0])
	before = f.w.freeze()
	_checks.source_merge_atomic = e.spawn_dirt(f.w,"CL01","ground_first","another_receipt",1,[60,90])==first_id and f.w.freeze()==before
	var old_view: Dictionary = space.public_areas._decision_view(f.w)
	var new_id: String = e.spawn_dirt(f.w,"CL01","public_refresh","public_refresh:1",1,[42,88])
	var new_view: Dictionary = space.public_areas._decision_view(f.w)
	var found: bool = false
	for row: Array in new_view.environment.get(1,[]):
		if row[1]=="dirt" and row[2].id==new_id: found = true
	_checks.same_tick_public_environment_current = not new_id.is_empty() and not is_same(old_view,new_view) and found
	_checks.nonblocking_screen_excluded = not e._ground_spawn_legal(f.w,1,[50,80])
	var moved: CommandResult = suite._command(f,"build_move",{"target_id":"index_screen","floor_id":1,"cell":[50,84]})
	_checks.formal_move_invalidates = moved.accepted and e._ground_spawn_legal(f.w,1,[50,80]) and not e._ground_spawn_legal(f.w,1,[50,84])
	var stored: CommandResult = suite._command(f,"build_store",{"target_id":"index_screen"})
	_checks.formal_store_invalidates = stored.accepted and e._ground_spawn_legal(f.w,1,[50,84])
	layout_builds = _count(space,"dirt_spawn_layout_builds")
	f.w.facts.facilities = f.w.facts.facilities.duplicate(true)
	e._ground_spawn_view(f.w,1)
	_checks.same_count_facilities_replacement = _count(space,"dirt_spawn_layout_builds")>layout_builds
	dirt_builds = _count(space,"dirt_spawn_dirt_builds")
	f.w.facts.environment.dirt = f.w.facts.environment.dirt.duplicate(true)
	before = f.w.freeze()
	_checks.same_count_dirt_replacement = e.spawn_dirt(f.w,"CL01","ground_first","replace:1",1,[42,80])==first_id and f.w.freeze()==before and _count(space,"dirt_spawn_dirt_builds")>dirt_builds
	var restored: Dictionary = suite._restore(f)
	_checks.restored_valid = restored.w.validate(content).is_empty()
	_checks.restore_same_owner_full_facts = _ground_case({"w":restored.w,"s":f.s},"restored_ground",[46,88],content)
	_checks.restored_service_full_facts = _ground_case(restored,"restored_fresh",[46,88],content)
	_raw_reservations(f)
	var b: Dictionary = suite._new("Dirt bins and plot budget")
	var be: HospitalEnvironment = b.s.services.environment
	_checks.bin_placed = suite._place(b,"spawn_bin","FUR18",[50,80])
	var bin_first: String = be.spawn_dirt(b.w,"CL02","cup_a","cup_a:1",1,[50,80])
	before = b.w.freeze()
	_checks.bin_merge_atomic = not bin_first.is_empty() and b.w.facts.environment.dirt[bin_first].bin_id=="spawn_bin" and be.spawn_dirt(b.w,"CL02","cup_b","cup_b:1",1,[50,80])==bin_first and b.w.freeze()==before
	var bin_space: HospitalSpace = b.s.space
	var coverage_checks: int = _count(bin_space,"environment_coverage_source_checks")
	var bin_layout_builds: int = _count(bin_space,"dirt_spawn_layout_builds")
	var bin_dirt_builds: int = _count(bin_space,"dirt_spawn_dirt_builds")
	var merges: bool = true
	for ordinal: int in 12:
		merges = be.spawn_dirt(b.w,"CL02","merged_cup_%d"%ordinal,"merged_cup_%d:1"%ordinal,1,[50,80])==bin_first and merges
	_checks.repeated_bin_merges_no_hidden_source_scans = merges and coverage_checks>0 and _count(bin_space,"environment_coverage_source_checks")==coverage_checks and _count(bin_space,"dirt_spawn_layout_builds")==bin_layout_builds and _count(bin_space,"dirt_spawn_dirt_builds")==bin_dirt_builds and b.w.freeze()==before and be._query_depth==0
	var cap: int = int(content.balance.cleanup.active_patches_per_plot)
	var filled: bool = true
	for ordinal: int in range(cap-1):
		var origin: Array = [34+ordinal%8*3,66+ordinal/8*3]
		filled = not be.spawn_dirt(b.w,"CL01","budget_%d"%ordinal,"budget_%d:1"%ordinal,1,origin).is_empty() and filled
	before = b.w.freeze()
	_checks.plot_cap_counts_ground_and_bin = filled and b.w.facts.environment.dirt.size()==cap and be.spawn_dirt(b.w,"CL01","over_budget","over_budget:1",1,[60,92]).is_empty() and b.w.freeze()==before
	_restored_over_budget(b,content)
	_cleanup_owner(suite,content)
	_floor_retention(f)
	_checks.final_valid = f.w.validate(content).is_empty() and b.w.validate(content).is_empty()
	var result: Dictionary = {"ok":not _checks.values().has(false),"checks":_checks,"counters":space.query_counts,"bin_counters":bin_space.query_counts,"setup_errors":f.errors+b.errors}
	for simulation: HospitalSimulation in suite._live: simulation.dispose()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty(): FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	quit(0 if result.ok else 1)
