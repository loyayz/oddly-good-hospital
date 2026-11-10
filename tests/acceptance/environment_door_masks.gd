extends "res://tests/acceptance/environment_direct_query.gd"

const Batch = preload("res://game/operations/environment_sample_batch.gd")
var _snapshots: Dictionary = {}
var _events: Array = []
var _mask_errors: Array = []
var _screen_case: bool = false

func run_mask_cases(database: HospitalContent, selected: Array) -> Dictionary:
	_content = database
	var cases: Dictionary = {"ENV-MASK-MOVE":_moving_masks,"ENV-MASK-SCREEN":_screen_masks,"ENV-MASK-CANCEL":_cancel_masks,"ENV-MASK-ISOLATION":_isolation,"ENV-MASK-BOUNDS":_bounds,"ENV-MASK-RAW":_raw_masks}
	var rows: Dictionary = {}
	for id: String in selected:
		if not cases.has(id): return {"ok":false,"unknown_case":id}
		_snapshots = {}; _events = []; _mask_errors = []
		rows[id] = cases[id].call()
	return {"ok":not rows.is_empty() and rows.values().all(func(row: Dictionary)->bool:return row.ok),"cases":rows}

func _counts(space: HospitalSpace) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ["source_checks","mask_builds","door_edge_checks","mask_patches","mask_copied_bytes"]:
		result[key] = _count(space,"coverage_"+key)
	return result

func _seed_door_sources(x: Dictionary) -> void:
	super._seed_door_sources(x)
	if _screen_case:
		_facility(x,"door_screen","FUR23",[37,79],"room")
		x.world.touch()

func _edges(e: HospitalEnvironment, world: WorldState, floor_id: int = 1) -> Dictionary:
	var before: Dictionary = _counts(e.space)
	var result: Dictionary = super._edges(e,world,floor_id)
	var overrides: Dictionary = result.get("wall_overrides",{})
	if not world.facts.adaptations.is_empty():
		if overrides.size()!=2 or overrides.values().any(func(value: Variant)->bool:return not value is bool or value): _mask_errors.append("Widened door needs exactly two explicit false wall overrides")
	elif not overrides.is_empty(): _mask_errors.append("Released door kept stale overrides")
	var key: int = e.get_instance_id()
	var prior: Dictionary = _snapshots.get(key,{})
	var after: Dictionary = _counts(e.space)
	if not prior.is_empty():
		if prior.edges.native_coverage.ordinary!=prior.ordinary or prior.edges.native_coverage.noise!=prior.noise or prior.edges.walls!=prior.walls:
			_mask_errors.append("Published snapshot mutated in place")
		if not is_same(prior.edges,result):
			var delta: Dictionary = {}
			for name: String in before: delta[name] = after[name]-before[name]
			var valid: bool = delta.source_checks==0 and delta.mask_builds==0 and delta.door_edge_checks==2 and delta.mask_patches==1 and delta.mask_copied_bytes==18432
			_events.append({"tick":world.sim_tick,"held":not world.facts.adaptations.is_empty(),"delta":delta,"ok":valid})
			if not valid: _mask_errors.append("Hot doorway change rebuilt static geometry or copied wrong mask size")
			if not is_same(prior.edges.walls,result.walls): _mask_errors.append("Door patch copied static walls")
			if not _grid_matches({"world":world,"space":e.space,"e":e},result): _mask_errors.append("Changed snapshot differs from raw BFS on local grid")
	else:
		_events.append({"tick":world.sim_tick,"cold":true,"held":not world.facts.adaptations.is_empty(),"ok":after.source_checks-before.source_checks==1 and after.mask_builds-before.mask_builds==1})
	_snapshots[key] = {"edges":result,"ordinary":result.native_coverage.ordinary.duplicate(),"noise":result.native_coverage.noise.duplicate(),"walls":result.walls.duplicate(true)}
	return result

func _grid_matches(x: Dictionary, edges: Dictionary) -> bool:
	var ok: bool = true
	x.e.begin_query(x.world)
	for y: int in range(76,84):
		for column: int in range(34,41):
			for noise: bool in [false,true]:
				var actual: Dictionary = Coverage.new()._coordinate_view(x.e._coverage(x.world,1,[column,y],4,noise,edges))
				var expected: Dictionary = Coverage.new()._reference(x,1,[column,y],4,noise)
				ok = ok and actual==expected and actual.keys()==expected.keys()
	x.e.end_query()
	return ok

func _coverage_matches(x: Dictionary, origin: Array, noise: bool = false) -> bool:
	var edges: Dictionary = _edges(x.e,x.world)
	var result: bool = super._coverage_matches(x,origin,noise) and super._coverage_matches(x,origin,true)
	if _screen_case and not x.world.facts.adaptations.is_empty():
		result = result and (int(edges.native_coverage.ordinary[79*96+37])&8)!=0 and (int(edges.native_coverage.noise[79*96+37])&8)==0
	return result

func _moving_masks() -> Dictionary:
	_screen_case = false
	return _finish_moving(_direct_door())

func _screen_masks() -> Dictionary:
	_screen_case = true
	# The screen changes scoring; the inherited raw public-read comparison still
	# applies, but the no-screen authored score assertion does not.
	return _finish_moving(super._door())

func _finish_moving(result: Dictionary) -> Dictionary:
	result.checks.exact_hold_and_arrival = result.held_ticks==26 and result.final_tick==105
	result.checks.hot_changes_are_two_local_edges = _mask_errors.is_empty() and _events.all(func(row: Dictionary)->bool:return row.ok)
	result.checks.two_hot_events_and_two_cold_acquisitions = _events.size()==4
	result.events = _events; result.mask_errors = _mask_errors
	result.ok = result.ok and not result.checks.values().has(false)
	return result

func _cancel_masks() -> Dictionary:
	_screen_case = false
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new()
	suite.content = _content
	var sim: HospitalSimulation = suite._fixture()
	var built: CommandResult = suite._command(sim,"build_room",suite._room("room",[35,68],[12,12]))
	suite._add_actor(sim,"giant","S59",[36,84])
	var x: Dictionary = {"world":sim.world,"space":sim.space,"e":sim.services.environment}
	var initial: Dictionary = _edges(x.e,x.world)
	var second: HospitalEnvironment = HospitalEnvironment.new(_content,x.space)
	var other_world: WorldState = WorldState.new(x.world.freeze())
	var foreign_service: HospitalEnvironment = HospitalEnvironment.new(_content,x.space)
	var foreign_edges: Dictionary = super._edges(foreign_service,other_world)
	var second_initial: Dictionary = super._edges(second,x.world)
	var reason: String = sim.space.request_move(sim.world,"giant",1,[36,71])
	for _step: int in 120:
		_movement_tick(sim)
		if not sim.world.facts.adaptations.is_empty(): break
	var held: Dictionary = _edges(x.e,x.world)
	var second_held: Dictionary = super._edges(second,x.world)
	var foreign_held: Dictionary = super._edges(foreign_service,other_world)
	# Prepare and finish a legitimate synchronous read batch while world is fixed.
	x.e.begin_query(x.world);x.e._coverage_edges(x.world,1)
	var job: RefCounted = Batch.SampleJob.new(_content)
	job.prepare(x.e,x.world,[],{})
	job.run()
	var borrowed: Dictionary = job.environment._query.edges[1]
	var old_ordinary: PackedByteArray = borrowed.native_coverage.ordinary.duplicate()
	var old_noise: PackedByteArray = borrowed.native_coverage.noise.duplicate()
	job.release_borrowed();x.e.end_query()
	# Only retained data is inspected after this point; no worker reads a changed world.
	var cancelled: bool = sim.space.cancel_ground_move(sim.world,"giant")
	sim.space.release_adaptations(sim.world)
	var safely_held: bool = not sim.world.facts.adaptations.is_empty()
	var retreat: String = sim.space.request_move(sim.world,"giant",1,[36,84])
	for _step: int in 150:
		_movement_tick(sim)
		if sim.world.facts.moves.is_empty(): break
	var released: Dictionary = _edges(x.e,x.world)
	var second_released: Dictionary = super._edges(second,x.world)
	var checks: Dictionary = {"two_services_receive_changes_independently":second_held.native_coverage==held.native_coverage and second_released.native_coverage==released.native_coverage and second_initial.native_coverage!=second_held.native_coverage,"foreign_world_listener_isolated":is_same(foreign_edges,foreign_held) and is_same(foreign_edges,super._edges(foreign_service,other_world)),"legal_real_move":built.accepted and reason.is_empty() and not is_same(initial,held),"cancel_preserves_body_then_real_retreat_releases":cancelled and safely_held and retreat.is_empty() and sim.space.at(sim.world,"giant",1,[36,84]) and sim.world.facts.adaptations.is_empty(),"old_worker_snapshot_immutable":borrowed.native_coverage.ordinary==old_ordinary and borrowed.native_coverage.noise==old_noise,"old_range_disappears":released.native_coverage==initial.native_coverage and released.native_coverage!=held.native_coverage,"raw_grid_equal":_grid_matches(x,released),"local_patch_counts":_mask_errors.is_empty(),"valid":sim.world.validate(_content).is_empty()}
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"events":_events,"errors":_mask_errors}
	sim.dispose()
	return result

func _isolation() -> Dictionary:
	var x: Dictionary = _fixture()
	HospitalFactory._add_room(x.world,{"id":"room","type":"waiting","anchor":[35,68],"size":[12,12],"door":{"definition_id":"DR01","offset":1}},_content)
	x.world.touch()
	var e2: HospitalEnvironment = HospitalEnvironment.new(_content,x.space)
	var a: Dictionary = super._edges(x.e,x.world)
	var b: Dictionary = super._edges(e2,x.world)
	var foreign: WorldState = WorldState.new(x.world.freeze())
	var before: Dictionary = _counts(x.space)
	var ephemeral: HospitalEnvironment = HospitalEnvironment.new(_content,x.space)
	super._edges(ephemeral,x.world)
	var weak_service: WeakRef = weakref(ephemeral)
	ephemeral = null
	before = _counts(x.space)
	var door: Dictionary = x.world.facts.floors.overrides["1"].doors[0]
	x.space.emit_signal("reservation_updated",foreign,str(door.id))
	x.space.emit_signal("reservation_updated",x.world,"not_a_door")
	x.space.emit_signal("reservation_updated",x.world,str(door.id))
	var checks: Dictionary = {"legal":x.world.validate(_content).is_empty(),"signals_do_not_retain_temporary_services":weak_service.get_ref()==null,"foreign_non_door_same_span_do_not_replace":is_same(a,super._edges(x.e,x.world)) and is_same(b,super._edges(e2,x.world)),"no_work_for_noop_notifications":before==_counts(x.space)}
	# Existing shared-wall case uses real room and static-door commands and a raw oracle.
	var wall_suite: RefCounted = preload("res://tests/acceptance/environment_wall_lookup.gd").new()
	wall_suite._content = _content
	var shared: Dictionary = wall_suite._wall_local()
	checks.legal_shared_wall_and_static_door = shared.ok
	var shared_geometry: Dictionary = _shared_geometry()
	checks.shared_owner_keeps_dynamic_edges_closed = shared_geometry.ok
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"shared_wall":shared,"pure_shared_geometry":shared_geometry}
	Coverage.new()._dispose(x)
	return result

func _bounds() -> Dictionary:
	var x: Dictionary = _fixture()
	# Legal upper floors are generated from the canonical completed-floor model.
	x.world.facts.floors.completed_top_floor = {}
	for plot: Array in x.world.facts.floors.overrides["1"].plots: x.world.facts.floors.completed_top_floor["%d:%d" % plot] = 12
	x.world.touch()
	var checks: Dictionary = {"legal_input":x.world.validate(_content).is_empty()}
	for floor_id: int in range(1,13):
		x.e.begin_query(x.world)
		var edges: Dictionary = x.e._coverage_edges(x.world,floor_id)
		for n: int in 140: x.e._coverage(x.world,floor_id,[32+n%28,68+n/28],1,false,edges)
		x.e.end_query()
		checks["floor_%d_bounded"%floor_id] = x.e._coverage_cache.size()<=8 and x.e._coverage_cache[floor_id].coverage.size()<=128
	checks.eight_floors_retained = x.e._coverage_cache.size()==8
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks}
	Coverage.new()._dispose(x)
	return result

# Pure geometry counterexample, NOT a legal live reservation or a traffic test.
# Real shared rooms and the static door are built normally; only the span input
# is varied to prove another wall owner prevents blindly opening mask bits.
func _shared_geometry() -> Dictionary:
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new()
	suite.content = _content
	var sim: HospitalSimulation = suite._fixture()
	var left: CommandResult = suite._command(sim,"build_room",suite._room("left",[35,68],[6,6]))
	var right: CommandResult = suite._command(sim,"build_room",suite._room("right",[41,68],[6,6]))
	var side: CommandResult = suite._command(sim,"build_door",{"room_id":"left","edge":"east","offset":1,"definition_id":"DR01"})
	var checks: Dictionary = {"static_input_legal":left.accepted and right.accepted and side.accepted and sim.world.validate(_content).is_empty()}
	var door: Dictionary = {}
	for candidate: Dictionary in suite._doors(sim.world,"left"):
		if candidate.axis=="y": door = candidate
	var e: HospitalEnvironment = sim.services.environment
	var original: Dictionary = super._edges(e,sim.world)
	e.begin_query(sim.world)
	e._coverage_edges(sim.world,1)
	var coverage: Dictionary = e._coverage(sim.world,1,[40,70],4,false,original)
	e.end_query()
	var counters: Dictionary = _counts(sim.space)
	sim.world.facts.adaptations[door.id] = {"kind":"door","span":3}
	sim.space.emit_signal("reservation_updated",sim.world,str(door.id))
	var widened: Dictionary = super._edges(e,sim.world)
	checks.shared_wall_prevents_false_opening = is_same(original,widened) and e._wall_between(sim.world,1,[40,70],[41,70]) and e._wall_between(sim.world,1,[40,71],[41,71])
	e.begin_query(sim.world)
	e._coverage_edges(sim.world,1)
	checks.coverage_survives_ineffective_span_change = is_same(coverage,e._coverage(sim.world,1,[40,70],4,false,widened))
	e.end_query()
	var after: Dictionary = _counts(sim.space)
	checks.only_two_edges_no_mask_copy = after.door_edge_checks-counters.door_edge_checks==2 and after.mask_patches==counters.mask_patches and after.mask_copied_bytes==counters.mask_copied_bytes and after.mask_builds==counters.mask_builds and after.source_checks==counters.source_checks
	sim.world.facts.adaptations.erase(door.id)
	sim.space.emit_signal("reservation_updated",sim.world,str(door.id))
	checks.release_also_keeps_snapshot = is_same(original,super._edges(e,sim.world)) and _count(sim.space,"coverage_door_edge_checks")==int(counters.door_edge_checks)+4
	var result: Dictionary = {"ok":not checks.values().has(false),"scope":"Pure geometry span input; not an actual reservation or shared-wall crossing","checks":checks}
	sim.dispose()
	return result

# Private raw acquisition is a calculation API: these unnotified inputs are
# deliberately NOT legal reservation transitions or simulated movement.
func _raw_masks() -> Dictionary:
	var x: Dictionary = _fixture()
	HospitalFactory._add_room(x.world,{"id":"room","type":"waiting","anchor":[40,70],"size":[8,8],"door":{"definition_id":"DR04","offset":3}},_content)
	# Isolate wall-edge propagation from legacy factory blocked-cell walls.
	x.world.facts.floors.overrides["1"].blocked.clear()
	x.world.touch()
	var checks: Dictionary = {"static_fixture_legal":x.world.validate(_content).is_empty()}
	var door: Dictionary = x.world.facts.floors.overrides["1"].doors[0]
	var original_cell: Array = door.cell.duplicate()
	var index: FloorStaticGeometry = x.space._navigation.floor_geometry(x.space,x.world,1)
	var initial: Dictionary = x.e._coverage_edges(x.world,1)
	var geometry_revision: int = x.world.geometry_revision
	var reservation_revision: int = x.space.reservation_revision
	var snapshots: Array = []
	var rows: Array = []
	for boundary: String in ["span3","span4","restore3","delete","shift_cell","restore_cell"]:
		match boundary:
			"span3", "span4", "restore3":
				var span: int = 4 if boundary=="span4" else 3
				var rect: Rect2 = x.space._door_rect(door,span)
				x.world.facts.adaptations[door.id] = {"kind":"door","floor_id":1,"span":span,"regions":[[rect.position.x,rect.position.y,rect.size.x,rect.size.y]]}
			"delete": x.world.facts.adaptations.erase(door.id)
			"shift_cell": door.cell = [int(original_cell[0])+1,int(original_cell[1])]
			"restore_cell": door.cell = original_cell.duplicate()
		var reads: int = _count(x.space,"coverage_source_checks")
		var edges: Dictionary = x.e._coverage_edges(x.world,1)
		var ok: bool = _raw_grid_matches(x,edges) and _count(x.space,"coverage_source_checks")==reads+1
		var fourth: Array = [int(door.cell[0])+3,int(door.cell[1])-1]
		var other: Array = [int(door.cell[0])+3,int(door.cell[1])]
		if boundary=="span4": checks.fourth_edge_opens_without_owner_notification = x.e._edge_open(x.world,1,fourth,other,false,edges)
		if boundary=="restore3": checks.fourth_edge_closes_after_raw_restore = not x.e._edge_open(x.world,1,fourth,other,false,edges)
		if boundary in ["delete","restore_cell"]: checks[boundary+"_returns_original_masks"] = edges.native_coverage==initial.native_coverage
		for saved: Dictionary in snapshots:
			ok = ok and saved.edges.native_coverage.ordinary==saved.ordinary and saved.edges.native_coverage.noise==saved.noise
		snapshots.append({"edges":edges,"ordinary":edges.native_coverage.ordinary.duplicate(),"noise":edges.native_coverage.noise.duplicate()})
		rows.append({"boundary":boundary,"ok":ok})
	checks.no_notifications_or_index_refresh = geometry_revision==x.world.geometry_revision and reservation_revision==x.space.reservation_revision and is_same(index,x.space._navigation.floor_geometry(x.space,x.world,1))
	checks.all_raw_inputs_match_independent_bfs_and_preserve_snapshots = rows.all(func(row: Dictionary)->bool:return row.ok)
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"rows":rows,"scope":"Private raw calculation inputs without notifications; not legal reservation transitions or actual movement"}
	Coverage.new()._dispose(x)
	return result

func _raw_grid_matches(x: Dictionary, edges: Dictionary) -> bool:
	for y: int in range(75,81):
		for column: int in range(40,49):
			for noise: bool in [false,true]:
				var actual: Dictionary = Coverage.new()._coordinate_view(x.e._coverage(x.world,1,[column,y],4,noise,edges))
				var expected: Dictionary = Coverage.new()._reference(x,1,[column,y],4,noise)
				if actual!=expected or actual.keys()!=expected.keys(): return false
	return true
