extends "res://tests/acceptance/staff_fixtures.gd"

const Coverage = preload("res://tests/acceptance/environment_coverage.gd")

func run_cases(database: HospitalContent, selected: Array) -> Dictionary:
	_content = database
	var cases: Dictionary = {"ENV-CACHE-LAYOUT":_layout,"ENV-CACHE-DOOR":_door,"ENV-HEATMAP":_heatmap}
	var rows: Dictionary = {}
	for id: String in selected:
		if not cases.has(id): return {"ok":false,"unknown_case":id}
		rows[id] = cases[id].call()
	return {"ok":not rows.is_empty() and rows.values().all(func(row: Dictionary)->bool:return row.ok),"cases":rows}

func _count(space: HospitalSpace, key: String) -> int:
	return int(space.query_counts.get("environment_"+key,0))

func _edges(e: HospitalEnvironment, world: WorldState, floor_id: int = 1) -> Dictionary:
	e.begin_query(world)
	var result: Dictionary = e._coverage_edges(world,floor_id)
	e.end_query()
	return result

func _coverage_matches(x: Dictionary, origin: Array, noise: bool = false) -> bool:
	# Read the prepared result first. The independent raw-fact traversal must
	# never refresh this cache before a missed owner notification can be seen.
	x.e.begin_query(x.world)
	var edges: Dictionary = x.e._coverage_edges(x.world,1)
	var actual: Dictionary = Coverage.new()._coordinate_view(x.e._coverage(x.world,1,origin,4,noise,edges))
	x.e.end_query()
	var expected: Dictionary = Coverage.new()._reference(x,1,origin,4,noise)
	return actual==expected and actual.keys()==expected.keys()

func _layout() -> Dictionary:
	var x: Dictionary = _fixture()
	HospitalFactory._add_room(x.world,{"id":"room","type":"waiting","anchor":[40,70],"size":[8,8],"door":{"definition_id":"DR04","offset":3}},_content)
	_facility(x,"screen","FUR23",[45,75],"room")
	x.world.touch()
	var checks: Dictionary = {"legal_input":x.world.validate(_content).is_empty()}
	var first: Dictionary = _edges(x.e,x.world)
	var before: Dictionary = x.world.freeze()
	var reads: int = _count(x.space,"coverage_source_checks")
	var unchanged: bool = true
	for _scope: int in 20:
		unchanged = unchanged and is_same(first,_edges(x.e,x.world)) and _coverage_matches(x,[45,76],true)
	checks.unchanged_scopes_do_not_enumerate_layout = unchanged and _count(x.space,"coverage_source_checks")==reads and before==x.world.freeze()
	x.world.touch(false)
	checks.non_geometry_commit_reuses_edges = is_same(first,_edges(x.e,x.world)) and _count(x.space,"coverage_source_checks")==reads
	x.world.touch()
	checks.unrelated_geometry_notification_reuses_equal_mask = is_same(first,_edges(x.e,x.world)) and _count(x.space,"coverage_source_checks")==reads+1 and _count(x.space,"coverage_mask_builds")==1
	var original: Dictionary = x.world.freeze()
	var all_changes: bool = true
	var rows: Array = []
	for kind: String in ["blocked","door","screen_move","screen_rotate","room_walls","plots"]:
		x.world.facts = original.duplicate(true)
		_edges(x.e,x.world)
		match kind:
			"blocked": x.world.facts.floors.overrides["1"].blocked.append([45,76])
			"door": x.world.facts.floors.overrides["1"].doors.clear()
			"screen_move": x.world.facts.facilities.screen.cell = [44,75]
			"screen_rotate": x.world.facts.facilities.screen.rotation = 1
			"room_walls": x.world.facts.rooms.room.size = [8,9]
			"plots": x.world.facts.floors.overrides["1"].plots = []
		x.world.touch()
		var old: Dictionary = x.e._coverage_cache[1].edges
		var equal: bool = _coverage_matches(x,[45,76],true) and _coverage_matches(x,[43,77])
		var changed: bool = not is_same(old,x.e._coverage_cache[1].edges)
		all_changes = all_changes and equal and changed
		rows.append({"boundary":kind,"complete_distances_and_order":equal,"replaced_changed_edges":changed})
	checks.owner_published_changes_update_coverage = all_changes
	x.world.facts = original.duplicate(true)
	checks.same_world_facts_replacement_invalidates = _coverage_matches(x,[45,76],true)
	var previous: WorldState = x.world
	x.world = WorldState.new(previous.freeze())
	x.world.facts.facilities.screen.rotation = 1
	checks.other_world_does_not_reuse_matching_numeric_revision = _coverage_matches(x,[45,76],true) and previous.facts.facilities.screen.rotation!=x.world.facts.facilities.screen.rotation
	var commands: Dictionary = _layout_commands()
	checks.real_layout_commands = commands.ok
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"commands":commands,"changes":rows,"source_checks":_count(x.space,"coverage_source_checks"),"source_hits":_count(x.space,"coverage_source_hits")}
	Coverage.new()._dispose(x)
	return result

func _layout_commands() -> Dictionary:
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new()
	suite.content = _content
	var sim: HospitalSimulation = suite._fixture()
	var x: Dictionary = {"world":sim.world,"space":sim.space,"e":sim.services.environment}
	var rows: Array = []
	_edges(x.e,x.world)
	var commands: Array = [
		["build_room",suite._room("command_room",[35,68],[12,12])],
		["build_facility",{"id":"command_screen","definition_id":"FUR23","floor_id":1,"cell":[40,74],"room_id":"command_room"}],
		["build_rotate",{"target_id":"command_screen","rotation":1}],
		["build_move",{"target_id":"command_screen","floor_id":1,"cell":[42,74]}],
		["build_demolish",{"target_id":"command_screen"}],
		["build_undo",{}]
	]
	for command: Array in commands:
		var result: CommandResult = suite._command(sim,command[0],command[1])
		var valid: String = sim.world.validate(_content)
		var matches: bool = _coverage_matches(x,[40,75],true) and _coverage_matches(x,[36,79])
		rows.append({"command":command[0],"ok":result.accepted and valid.is_empty() and matches,"accepted":result.accepted,"reason":result.reason,"validation":valid,"complete_coverage_matches":matches})
	var result: Dictionary = {"ok":rows.all(func(row: Dictionary)->bool:return row.ok),"rows":rows}
	sim.dispose()
	return result

func _normalized(rows: Array) -> Array:
	var copy: Array = rows.duplicate(true)
	# Source explanations have no gameplay ordering contract. Cell order,
	# complete source records and every observation field are compared.
	for row: Dictionary in copy:
		row.environment.sources.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return JSON.stringify(a)<JSON.stringify(b))
	return copy

func _heatmap() -> Dictionary:
	var x: Dictionary = _fixture({"subject":"doctor","neighbor":"nurse"})
	_facility(x,"plant","FUR25",[42,79])
	_facility(x,"light","FUR19",[42,82])
	_facility(x,"water","FUR17",[50,80])
	_facility(x,"screen","FUR23",[48,84])
	_position(x,"subject",[44,80])
	_position(x,"neighbor",[45,80])
	x.world.touch()
	var cells: Array = []
	for dx: int in range(-4,5):
		for dy: int in range(-4,5): cells.append([44+dx,80+dy])
	var expected: Array = []
	for cell: Array in cells: expected.append({"cell":cell.duplicate(),"environment":x.e.environment_at(x.world,1,cell)})
	var reference_checks: int = _count(x.space,"coverage_source_checks")
	# Use a cold service to count this user action, not the reference's work.
	x.e = HospitalEnvironment.new(_content,x.space)
	for key: String in x.space.query_counts: x.space.query_counts[key] = 0
	var before: Dictionary = x.world.freeze()
	var actual: Array = x.e.heatmap(x.world,1,cells)
	var checks: Dictionary = {"legal_input":x.world.validate(_content).is_empty(),"complete_81_cell_observations_match":reference_checks==81 and actual.size()==81 and _normalized(actual)==_normalized(expected),"query_is_readonly":before==x.world.freeze(),"one_query_and_one_source_acquisition":x.e.query_builds==1 and _count(x.space,"coverage_source_checks")==1 and _count(x.space,"facility_source_builds")==1 and _count(x.space,"dynamic_source_builds")==1 and _count(x.space,"actor_source_builds")==1,"scope_closed":x.e._query.is_empty() and x.e._query_depth==0}
	var native_calls: int = _count(x.space,"coverage_native_calls")
	checks.unchanged_heatmap_reuses_coverage = x.e.heatmap(x.world,1,cells)==actual and _count(x.space,"coverage_source_checks")==1 and _count(x.space,"coverage_native_calls")==native_calls
	x.e.begin_query(x.world)
	var parent: Dictionary = x.e._query
	checks.nested_heatmap_preserves_parent = x.e.heatmap(x.world,1,cells)==actual and x.e._query_depth==1 and is_same(parent,x.e._query)
	x.e.end_query()
	var builds: int = x.e.query_builds
	checks.empty_heatmap_acquires_nothing = x.e.heatmap(x.world,1,[]).is_empty() and x.e.query_builds==builds
	# Each new scope must read current mutable values without a geometry edit.
	x.world.facts.facilities.light.failed = true
	_position(x,"neighbor",[60,80])
	expected.clear()
	for cell: Array in cells: expected.append({"cell":cell.duplicate(),"environment":x.e.environment_at(x.world,1,cell)})
	var changed: Array = x.e.heatmap(x.world,1,cells)
	checks.next_heatmap_reads_live_failure_and_people = _normalized(changed)==_normalized(expected) and changed!=actual
	var outside: Array = x.e.heatmap(x.world,1,[[0,0],[95,95]])
	checks.unowned_floor_is_still_uncolored = outside.all(func(row: Dictionary)->bool:return row.environment.status=="outside_owned_floor")
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"first_heatmap_cells":81,"direct_reference_source_checks":reference_checks,"source_checks_per_cold_heatmap":1,"warm_additional_coverage_calls":0}
	Coverage.new()._dispose(x)
	return result

func _movement_tick(sim: HospitalSimulation) -> void:
	# The actual production movement boundary leaves structural geometry alone.
	sim.space.advance(sim.world,sim.world.present_actor_count())
	sim.world.facts.sim_tick += 1
	sim.world.touch(false)
	sim.space.finish_boundary(sim.world)

func _door() -> Dictionary:
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new()
	suite.content = _content
	var sim: HospitalSimulation = suite._fixture()
	var built: CommandResult = suite._command(sim,"build_room",suite._room("room",[35,68],[12,12]))
	suite._add_actor(sim,"giant","S59",[36,84])
	var door: Dictionary = suite._doors(sim.world,"room")[0]
	var x: Dictionary = {"world":sim.world,"space":sim.space,"e":sim.services.environment}
	var initial: Dictionary = _edges(x.e,x.world)
	var geometry: int = sim.world.geometry_revision
	var checks: Dictionary = {"built":built.accepted,"legal_input":sim.world.validate(_content).is_empty()}
	var reason: String = sim.space.request_move(sim.world,"giant",1,[36,71])
	checks.request = reason.is_empty()
	var acquired: bool = false
	var held_ticks: int = 0
	var released: bool = false
	var restored: bool = false
	var errors: Array = []
	var samples: Array = []
	for _step: int in 220:
		_movement_tick(sim)
		x = {"world":sim.world,"space":sim.space,"e":sim.services.environment}
		var held: bool = sim.world.facts.adaptations.has(door.id)
		if held:
			acquired = true
			held_ticks += 1
			var span: int = int(sim.world.facts.adaptations[door.id].span)
			if span<=int(door.span): errors.append("Input did not exercise a widened doorway")
			if held_ticks==1:
				checks.door_notification_without_structural_invalidation = sim.world.geometry_revision==geometry and sim.space.reservation_revision>0
				checks.wider_opening_replaces_mask = not is_same(initial,_edges(x.e,x.world))
				var frozen: Dictionary = sim.world.freeze()
				var encoder: HospitalJsonStream = HospitalJsonStream.new()
				var path: String = "user://environment-door-snapshot.json"
				var encoded: bool = encoder.encode(path,frozen,func(_bytes: int)->bool:return true)
				var decoder: HospitalJsonStream = HospitalJsonStream.new()
				var decoded: Dictionary = decoder.decode(path,encoder.bytes,encoder.digest,func(_bytes: int)->bool:return true)
				var fresh: WorldState = WorldState.new(decoded.value)
				checks.snapshot_round_trip = encoded and decoded.ok and fresh.freeze()==frozen and fresh.validate(_content).is_empty()
				sim.dispose()
				sim = HospitalSimulation.new(fresh,_content)
				x = {"world":sim.world,"space":sim.space,"e":sim.services.environment}
				restored = true
		elif acquired:
			released = true
		if not _coverage_matches(x,[37,79]): errors.append("Coverage differed after movement, restore or release")
		var validation: String = sim.world.validate(_content)
		if not validation.is_empty(): errors.append(validation)
		if held_ticks==1 or released and samples.size()<2: samples.append({"tick":sim.world.sim_tick,"held":held,"reservation_revision":sim.space.reservation_revision})
		if sim.world.facts.moves.is_empty(): break
	checks.actual_expansion_hold_and_release = acquired and held_ticks>1 and released and restored
	checks.actual_arrival_after_restore = sim.space.at(sim.world,"giant",1,[36,71]) and sim.world.facts.moves.is_empty()
	checks.released_door_returns_original_edges = _edges(x.e,x.world)==initial
	checks.no_validation_or_coverage_errors = errors.is_empty()
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"held_ticks":held_ticks,"final_tick":sim.world.sim_tick,"request_reason":reason,"errors":errors,"samples":samples}
	sim.dispose()
	return result
