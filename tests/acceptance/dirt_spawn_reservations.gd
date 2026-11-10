extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var suite: RefCounted = load("res://tests/acceptance/operations.gd").new()
	suite._content = content
	var reference: RefCounted = load("res://tests/acceptance/operations_repeated_work.gd").new()
	var f: Dictionary = suite._new("Dirt respects live reserved work regions")
	suite._staff(f,"large_user","cleaner",[36,92])
	f.w.facts.actors.large_user.species_id = "S53"
	f.w.touch()
	f.s.space.sync_actor(f.w,"large_user")
	var placed: bool = suite._place(f,"chair","FUR05",[44,80]) and suite._place(f,"screen","FUR23",[50,80])
	var e: HospitalEnvironment = f.s.services.environment
	var checks: Dictionary = {"legal_initial_world":f.w.validate(content).is_empty(),"formal_placement":placed,"unreserved_point_legal":e._ground_spawn_legal(f.w,1,[44,82])}
	var initial_index: BodyIndex = f.s.space.reservation_view(f.w).index
	var builds: int = f.s.space.query_counts.reservation_index_builds
	var before_revision: int = f.w.geometry_revision
	var reserved: String = f.s.space.reserve_facility(f.w,"chair","large_user","large_user")
	checks.real_reservation = reserved.is_empty() and f.w.facts.adaptations.has("chair") and f.w.validate(content).is_empty()
	checks.published_without_geometry_revision = f.w.geometry_revision==before_revision and initial_index==f.s.space.reservation_view(f.w).index and f.s.space.query_counts.reservation_index_builds==builds
	checks.reserved_body_interior_rejected = not e._ground_spawn_legal(f.w,1,[44,82])
	checks.reservation_edge_touch_legal = e._ground_spawn_legal(f.w,1,[47,82]) and e._ground_spawn_legal(f.w,1,[44,84])
	checks.nonblocking_furniture_still_rejected = not e._ground_spawn_legal(f.w,1,[50,80])
	var before: Dictionary = f.w.freeze()
	var restored: Dictionary = suite._restore(f)
	checks.restore_blocks_same_cell = not restored.s.services.environment._ground_spawn_legal(restored.w,1,[44,82]) and restored.w.validate(content).is_empty()
	var view: Dictionary = e._ground_spawn_view(f.w,1)
	var complete: bool = true
	var checked: int = 0
	var candidates: Array = []
	for x: int in range(40,49):
		for y: int in range(78,87):
			var expected: bool = reference._ground_full(f.w,f.s.space,1,[x,y])
			complete = complete and e._ground_spawn_legal(f.w,1,[x,y],view)==expected
			if expected: candidates.append({"cell":[x,y],"distance":absi(x-44)+absi(y-82)})
			checked += 1
	checks.complete_independent_region_oracle = complete and checked==81 and f.w.freeze()==before
	candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.distance<b.distance if a.distance!=b.distance else (a.cell[0]<b.cell[0] if a.cell[0]!=b.cell[0] else a.cell[1]<b.cell[1]))
	var patch: String = e.spawn_dirt(f.w,"CL01","reserved_source","reserved_source:1",1,[44,82])
	checks.actual_spawn_uses_nearest_legal_cell = not patch.is_empty() and not candidates.is_empty() and f.w.facts.environment.dirt[patch].cell==candidates[0].cell and f.w.facts.environment.dirt[patch].cell!=[44,82]
	var duplicate: String = e.spawn_dirt(f.w,"CL01","reserved_source","reserved_source:1",1,[44,82])
	checks.original_source_idempotency = duplicate==patch and f.w.facts.environment.dirt.size()==1
	var reservation_after: Dictionary = f.w.facts.adaptations.chair.duplicate(true)
	checks.spawn_does_not_release_or_edit_reservation = reservation_after==before.adaptations.chair
	# The original participant is still physically outside the held region.
	# Production release must update the same index without a new layout tick.
	var release_index: BodyIndex = f.s.space.reservation_view(f.w).index
	builds = f.s.space.query_counts.reservation_index_builds
	f.s.space.release_adaptations(f.w)
	checks.actual_release_reopens_cell = not f.w.facts.adaptations.has("chair") and e._ground_spawn_legal(f.w,1,[44,82]) and f.s.space.reservation_view(f.w).index==release_index and f.s.space.query_counts.reservation_index_builds==builds
	checks.final_world_valid = f.w.validate(content).is_empty()
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"checked_cells":checked,"actual_spawn":f.w.facts.environment.dirt.get(patch,{}),"reservation":reservation_after,"setup_errors":f.errors}
	for simulation: HospitalSimulation in suite._live: simulation.dispose()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty(): FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	quit(0 if result.ok else 1)
