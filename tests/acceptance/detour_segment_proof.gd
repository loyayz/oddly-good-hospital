extends RefCounted

# Requirements: task-navigation-movement.md sections 3-4. These are read-only
# return-link calculations, not fabricated journeys, arrivals or work progress.
# Every body rectangle, structural check and dynamic contact is production code.
class CountingSpace extends HospitalSpace:
	var rectangle_calls: int = 0
	func _init(database: HospitalContent) -> void:
		super(database)
	func _actor_rect(actor: Dictionary, origin: Vector2) -> Rect2:
		rectangle_calls += 1
		return super._actor_rect(actor,origin)

class CountingMovement extends HospitalMovement:
	var contacts: int = 0
	var paths: Array = []
	var proofs: Array = []
	var initial_sizes: Array = []
	func _init(geometry: HospitalSpace) -> void:
		super(geometry)
	func _movement_contacts(world: WorldState, actor_id: String, floor_id: int, broad: Rect2, sweeps: Array[BodyIndex.Record], members: Array, result: MotionResult) -> void:
		contacts += 1
		super._movement_contacts(world,actor_id,floor_id,broad,sweeps,members,result)
	func _detour_path_clear(world: WorldState, actor: Dictionary, movement: Dictionary, path: Array, query: RouteClearance = null, proof: Dictionary = {}) -> bool:
		if not proof.is_empty():
			var known: bool = false
			for existing: Dictionary in proofs:
				known = known or is_same(existing.sweeps,proof.sweeps)
			if not known:
				proofs.append(proof)
				initial_sizes.append({"sweeps":proof.sweeps.size(),"segments":proof.get("segments",{}).size(),"has_segments":proof.has("segments")})
		var before_contacts: int = contacts
		var geometry: CountingSpace = space as CountingSpace
		var before_rectangles: int = geometry.rectangle_calls
		var clear: bool = super._detour_path_clear(world,actor,movement,path,query,proof)
		paths.append({"path":path.duplicate(true),"clear":clear,"contacts":contacts-before_contacts,"rectangles":geometry.rectangle_calls-before_rectangles})
		return clear

class QuarterOnlyMovement extends CountingMovement:
	func _init(geometry: HospitalSpace) -> void:
		super(geometry)
	func _detour_path_clear(world: WorldState, actor: Dictionary, movement: Dictionary, path: Array, query: RouteClearance = null, proof: Dictionary = {}) -> bool:
		# Same production loop and exact sweep map, without the new segment map.
		var quarter: Dictionary = {"sweeps":proof.sweeps} if proof.has("sweeps") else {}
		return super._detour_path_clear(world,actor,movement,path,query,quarter)

class NoMemoMovement extends CountingMovement:
	func _init(geometry: HospitalSpace) -> void:
		super(geometry)
	func _detour_path_clear(world: WorldState, actor: Dictionary, movement: Dictionary, path: Array, query: RouteClearance = null, _proof: Dictionary = {}) -> bool:
		return super._detour_path_clear(world,actor,movement,path,query,{})

func run(content: HospitalContent) -> Dictionary:
	return run_selected(content)

func run_selected(content: HospitalContent, selected: String = "") -> Dictionary:
	# Runtime load avoids a preload cycle after registration in SPACE-10.
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new()
	suite.content = content
	var names: Array = ["positive_negative_and_selection","exact_segment_keys","terminal_tolerance","zero_length_legs","budget_preserves_search"]
	if not selected.is_empty() and not selected in names:
		return {"passed":false,"details":{"error":"Unknown focused case: "+selected}}
	var cases: Array = []
	for name: String in names:
		if selected.is_empty() or selected==name: cases.append(call("_"+name,suite))
	var ok: bool = true
	for row: Dictionary in cases: ok = ok and bool(row.ok)
	return {"passed":ok,"details":{"case":"invocation_local_exact_segment_proof","cases":cases,"scope":"Pure return-link calculation boundaries. Actual movement and production workload remain separate SPACE-10/56/57 and warm-workload evidence."}}

func _point(x: float, y: float) -> Dictionary:
	return {"kind":"floor","floor_id":1,"cell":[x,y]}

func _movement(id: String, cells: Array) -> Dictionary:
	var original: Array = []
	for cell: Array in cells: original.append(_point(float(cell[0]),float(cell[1])))
	return {"actor_id":id,"detour":{"original_path":original}}

func _row(name: String, checks: Dictionary, details: Dictionary = {}) -> Dictionary:
	var ok: bool = true
	for value: bool in checks.values(): ok = ok and value
	return {"case":name,"ok":ok,"checks":checks,"details":details}

func _search(service: CountingMovement, world: WorldState, id: String, movement: Dictionary, origin: Vector2, prefix: Array = []) -> Dictionary:
	var geometry: CountingSpace = service.space as CountingSpace
	# Index preparation is common input setup, outside predicate work counts.
	geometry._ensure_actor_index(world)
	var before: Dictionary = world.freeze()
	var before_movement: Dictionary = movement.duplicate(true)
	var before_contacts: int = service.contacts
	var before_rectangles: int = geometry.rectangle_calls
	var before_proofs: int = service.proofs.size()
	var before_paths: int = service.paths.size()
	var chosen: Dictionary = service._detour_return_path(world,world.facts.actors[id],movement,origin,prefix)
	return {"chosen":chosen,"contacts":service.contacts-before_contacts,"rectangles":geometry.rectangle_calls-before_rectangles,"readonly":world.freeze()==before and movement==before_movement,"new_proofs":service.proofs.size()-before_proofs,"path_attempts":service.paths.size()-before_paths}

func _fresh_segment_proofs(service: CountingMovement, count: int) -> bool:
	if service.proofs.size()!=count: return false
	for sizes: Dictionary in service.initial_sizes:
		if not sizes.has_segments or sizes.segments!=0 or sizes.sweeps!=0: return false
	for i: int in service.proofs.size():
		for j: int in i:
			if is_same(service.proofs[i],service.proofs[j]) or is_same(service.proofs[i].segments,service.proofs[j].segments): return false
	return true

func _positive_negative_and_selection(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker","S49",[35,70])
	suite._add_actor(sim,"blocker","S49",[36,70])
	var geometry: CountingSpace = CountingSpace.new(suite.content)
	geometry._ensure_actor_index(sim.world)
	var cached: CountingMovement = CountingMovement.new(geometry)
	var quarter: QuarterOnlyMovement = QuarterOnlyMovement.new(geometry)
	var oracle: NoMemoMovement = NoMemoMovement.new(geometry)
	var actor: Dictionary = sim.world.facts.actors.walker
	var movement: Dictionary = _movement("walker",[[36,70],[37,70]])
	var query: RouteClearance = geometry.navigation.structural_clearance(sim.world,actor,1)
	var proof: Dictionary = {"sweeps":{},"segments":{}}
	var quarter_proof: Dictionary = {"sweeps":{}}
	var before: Dictionary = sim.world.freeze()
	var positive: Array = [_point(35,71)]
	var negative: Array = [_point(36,70)]
	var positive_first: bool = cached._detour_path_clear(sim.world,actor,movement,positive,query,proof)
	var positive_second: bool = cached._detour_path_clear(sim.world,actor,movement,positive,query,proof)
	var positive_row: Dictionary = cached.paths.back()
	var negative_first: bool = cached._detour_path_clear(sim.world,actor,movement,negative,query,proof)
	var negative_second: bool = cached._detour_path_clear(sim.world,actor,movement,negative,query,proof)
	var negative_row: Dictionary = cached.paths.back()
	quarter._detour_path_clear(sim.world,actor,movement,positive,query,quarter_proof)
	var quarter_positive: bool = quarter._detour_path_clear(sim.world,actor,movement,positive,query,quarter_proof)
	var quarter_positive_row: Dictionary = quarter.paths.back()
	quarter._detour_path_clear(sim.world,actor,movement,negative,query,quarter_proof)
	var quarter_negative: bool = quarter._detour_path_clear(sim.world,actor,movement,negative,query,quarter_proof)
	var quarter_negative_row: Dictionary = quarter.paths.back()
	var success_count: int = 0
	var failure_count: int = 0
	for value: Array in proof.segments.values():
		if value.is_empty(): failure_count += 1
		elif value.size()==2: success_count += 1
	var search_service: CountingMovement = CountingMovement.new(geometry)
	var selected: Dictionary = _search(search_service,sim.world,"walker",movement,Vector2(35,70))
	var old_quarters: Dictionary = _search(quarter,sim.world,"walker",movement,Vector2(35,70))
	var uncached: Dictionary = _search(oracle,sim.world,"walker",movement,Vector2(35,70))
	# The occupied original cell is impossible; take the nearest successor by
	# the first legal positive-Y local side link, preserving declared order.
	var expected: Dictionary = {"index":1,"path":[_point(35,71),_point(37,71),_point(37,70)]}
	var checks: Dictionary = {
		"positive_result_reused":positive_first and positive_second and quarter_positive,
		"negative_result_reused":not negative_first and not negative_second and not quarter_negative,
		"both_segment_result_encodings":success_count==1 and failure_count==1,
		"hits_only_prepare_initial_body":positive_row.rectangles==1 and negative_row.rectangles==1,
		"hits_skip_all_contacts":positive_row.contacts==0 and negative_row.contacts==0,
		"positive_hit_skips_quarter_rectangle_work":positive_row.rectangles<quarter_positive_row.rectangles,
		"negative_hit_skips_quarter_rectangle_work":negative_row.rectangles<quarter_negative_row.rectangles,
		"nearest_successor_ordered_path":selected.chosen==expected,
		"same_path_and_index_as_both_full_predicates":selected.chosen==old_quarters.chosen and selected.chosen==uncached.chosen,
		"segment_layer_reduces_rectangle_work":selected.rectangles<old_quarters.rectangles,
		"does_not_reexecute_quarter_contacts":selected.contacts==old_quarters.contacts and selected.contacts<uncached.contacts,
		"search_starts_with_new_empty_segment_and_sweep_maps":_fresh_segment_proofs(search_service,1),
		"inputs_unchanged":sim.world.freeze()==before and selected.readonly and old_quarters.readonly and uncached.readonly
	}
	var result: Dictionary = _row("positive_negative_hits_and_ordered_selection",checks,{"positive_hit":positive_row,"quarter_positive_hit":quarter_positive_row,"negative_hit":negative_row,"quarter_negative_hit":quarter_negative_row,"selected":selected,"quarter_only":old_quarters,"no_memo":uncached})
	sim.dispose()
	return result

func _exact_segment_keys(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var origin: Vector2 = Vector2(40.125,80.375)
	suite._add_actor(sim,"walker","S03",[origin.x,origin.y])
	var geometry: CountingSpace = CountingSpace.new(suite.content)
	geometry._ensure_actor_index(sim.world)
	var cached: CountingMovement = CountingMovement.new(geometry)
	var quarter: QuarterOnlyMovement = QuarterOnlyMovement.new(geometry)
	var actor: Dictionary = sim.world.facts.actors.walker
	var movement: Dictionary = _movement("walker",[[42,82]])
	var query: RouteClearance = geometry.navigation.structural_clearance(sim.world,actor,1)
	var proof: Dictionary = {"sweeps":{},"segments":{}}
	var quarter_proof: Dictionary = {"sweeps":{}}
	var initial: Rect2 = geometry._actor_rect(actor,origin)
	var short_target: Vector2 = origin+Vector2(0.2,0)
	var horizontal: Vector2 = origin+Vector2(20,0)
	var near_axis: Vector2 = horizontal+Vector2(0,0.00000762939453125)
	var paths: Array = [
		[_point(short_target.x,short_target.y)],
		[_point(origin.x,origin.y+1),_point(origin.x-1,origin.y+1),_point(origin.x-1,origin.y),_point(origin.x,origin.y),_point(short_target.x,short_target.y)],
		[_point(short_target.x,short_target.y),_point(origin.x,origin.y)],
		[_point(horizontal.x,horizontal.y)],
		[_point(near_axis.x,near_axis.y)]
	]
	var before: Dictionary = sim.world.freeze()
	var all_clear: bool = true
	var same_as_quarter: bool = true
	for path: Array in paths:
		var actual: bool = cached._detour_path_clear(sim.world,actor,movement,path,query,proof)
		all_clear = all_clear and actual
		same_as_quarter = same_as_quarter and actual==quarter._detour_path_clear(sim.world,actor,movement,path,query,quarter_proof)
	var different_previous: bool = false
	var reverse_present: bool = false
	for key: Array in proof.segments:
		if key[0]==origin and key[1]==short_target and key[2]!=initial: different_previous = true
		if key[0]==short_target and key[1]==origin: reverse_present = true
	var same_points_different_next_rectangle: bool = false
	var by_points: Dictionary = {}
	for key: Array in proof.sweeps:
		var points: Array = [key[0],key[1]]
		for prior: Array in by_points.get(points,[]):
			same_points_different_next_rectangle = same_points_different_next_rectangle or prior[3]!=key[3]
		if not by_points.has(points): by_points[points] = []
		by_points[points].append(key)
	var straight_value: Array = proof.segments.get([origin,horizontal,initial],[])
	var near_value: Array = proof.segments.get([origin,near_axis,initial],[])
	var repeat: bool = cached._detour_path_clear(sim.world,actor,movement,paths[0],query,proof)
	var dimensions: Dictionary = geometry.body(actor)
	var checks: Dictionary = {
		"real_fractional_non_square_body":dimensions.width_m!=dimensions.depth_m and origin.x!=floorf(origin.x) and origin.y!=floorf(origin.y),
		"short_turn_reverse_and_near_axis_are_clear":all_clear,
		"quarter_only_predicate_agrees":same_as_quarter,
		"same_endpoints_different_previous_rectangle_are_separate":different_previous and proof.segments.has([origin,short_target,initial]),
		"exact_near_axis_target_not_aliased":horizontal!=near_axis and straight_value.size()==2 and near_value.size()==2,
		"near_axis_really_needs_distinct_rectangle_work":same_points_different_next_rectangle,
		"directed_origin_and_target_not_aliased":reverse_present,
		"original_orientation_still_reuses":repeat and cached.paths.back().rectangles==1 and cached.paths.back().contacts==0,
		"facts_unchanged":before==sim.world.freeze()
	}
	var result: Dictionary = _row("exact_origin_target_previous_rectangle_keys",checks,{"segments":proof.segments.size(),"quarter_sweeps":proof.sweeps.size(),"straight_terminal":straight_value,"near_axis_terminal":near_value})
	sim.dispose()
	return result

func _terminal_tolerance(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var origin: Vector2 = Vector2(40.125,80.375)
	var target: Vector2 = Vector2(41.1255,80.375)
	var terminal: Vector2 = Vector2(41.125,80.375)
	var next_target: Vector2 = Vector2(target.x,81.375)
	suite._add_actor(sim,"walker","S03",[origin.x,origin.y])
	var geometry: CountingSpace = CountingSpace.new(suite.content)
	geometry._ensure_actor_index(sim.world)
	var cached: CountingMovement = CountingMovement.new(geometry)
	var quarter: QuarterOnlyMovement = QuarterOnlyMovement.new(geometry)
	var actor: Dictionary = sim.world.facts.actors.walker
	var movement: Dictionary = _movement("walker",[[42,82]])
	var query: RouteClearance = geometry.navigation.structural_clearance(sim.world,actor,1)
	var proof: Dictionary = {"sweeps":{},"segments":{}}
	var quarter_proof: Dictionary = {"sweeps":{}}
	var first: Array = [_point(target.x,target.y)]
	var next_path: Array = [first[0],_point(next_target.x,next_target.y)]
	var before: Dictionary = sim.world.freeze()
	var first_ok: bool = cached._detour_path_clear(sim.world,actor,movement,first,query,proof)
	var initial: Rect2 = geometry._actor_rect(actor,origin)
	var stored: Array = proof.segments.get([origin,target,initial],[])
	var next_ok: bool = cached._detour_path_clear(sim.world,actor,movement,next_path,query,proof)
	var next_work: Dictionary = cached.paths.back()
	var quarter_ok: bool = quarter._detour_path_clear(sim.world,actor,movement,next_path,query,quarter_proof)
	var actual_continuation: bool = stored.size()==2 and proof.segments.has([terminal,next_target,stored[1]])
	var no_snapped_continuation: bool = stored.size()==2 and not proof.segments.has([target,next_target,stored[1]])
	var exact_quarters: bool = proof.sweeps==quarter_proof.sweeps
	var repeat_ok: bool = cached._detour_path_clear(sim.world,actor,movement,next_path,query,proof)
	var checks: Dictionary = {
		"legal_gap_within_quarter_loop_tolerance":terminal!=target and terminal.distance_to(target)<0.001,
		"successful_leg_keeps_actual_terminal_origin":first_ok and stored.size()==2 and stored[0]==terminal,
		"following_leg_is_clear":next_ok and quarter_ok,
		"following_leg_starts_from_actual_terminal":actual_continuation and no_snapped_continuation,
		"all_exact_quarter_proofs_match_unsnapped_loop":exact_quarters,
		"cached_prefix_skips_four_quarter_rectangles":next_work.rectangles==quarter.paths.back().rectangles-4,
		"both_segments_hit_on_repeat":repeat_ok and cached.paths.back().rectangles==1 and cached.paths.back().contacts==0,
		"facts_unchanged":sim.world.freeze()==before
	}
	var result: Dictionary = _row("sub_millimeter_terminal_then_next_leg",checks,{"target":target,"actual_terminal":stored,"next_leg_work":next_work,"quarter_only_work":quarter.paths.back()})
	sim.dispose()
	return result

func _zero_length_legs(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var origin: Vector2 = Vector2(40.125,80.375)
	suite._add_actor(sim,"walker","S03",[origin.x,origin.y])
	var geometry: CountingSpace = CountingSpace.new(suite.content)
	geometry._ensure_actor_index(sim.world)
	var cached: CountingMovement = CountingMovement.new(geometry)
	var quarter: QuarterOnlyMovement = QuarterOnlyMovement.new(geometry)
	var actor: Dictionary = sim.world.facts.actors.walker
	var movement: Dictionary = _movement("walker",[[42,82]])
	var query: RouteClearance = geometry.navigation.structural_clearance(sim.world,actor,1)
	var proof: Dictionary = {"sweeps":{},"segments":{}}
	var no_step: Array = [_point(origin.x,origin.y),_point(origin.x,origin.y),_point(origin.x+0.0005,origin.y)]
	var before: Dictionary = sim.world.freeze()
	var zero_ok: bool = cached._detour_path_clear(sim.world,actor,movement,no_step,query,proof)
	var zero_row: Dictionary = cached.paths.back()
	var zero_maps_empty: bool = proof.segments.is_empty() and proof.sweeps.is_empty()
	var corner: Vector2 = origin+Vector2(1,0)
	var end: Vector2 = corner+Vector2(0,1)
	var real_legs: Array = [_point(corner.x,corner.y),_point(end.x,end.y)]
	var repeated: Array = [real_legs[0],real_legs[0],_point(corner.x+0.0005,corner.y),real_legs[1],real_legs[1]]
	var real_ok: bool = cached._detour_path_clear(sim.world,actor,movement,real_legs,query,proof)
	var repeat_ok: bool = cached._detour_path_clear(sim.world,actor,movement,repeated,query,proof)
	var oracle_ok: bool = quarter._detour_path_clear(sim.world,actor,movement,repeated,query,{"sweeps":{}})
	var all_nonempty: bool = true
	for key: Array in proof.segments: all_nonempty = all_nonempty and key[0].distance_to(key[1])>0.001
	var checks: Dictionary = {
		"zero_and_within_tolerance_legs_succeed":zero_ok,
		"zero_legs_do_not_add_sweep_or_segment_entries":zero_maps_empty,
		"zero_legs_do_not_enter_quarter_loop":zero_row.rectangles==1 and zero_row.contacts==0,
		"zero_legs_after_segment_hit_keep_next_leg":real_ok and repeat_ok and oracle_ok,
		"only_two_nonempty_segments_are_stored":proof.segments.size()==2 and all_nonempty,
		"interspersed_zero_legs_do_not_defeat_positive_hits":cached.paths.back().rectangles==1 and cached.paths.back().contacts==0,
		"facts_unchanged":before==sim.world.freeze()
	}
	var result: Dictionary = _row("empty_legs_do_not_create_segment_proofs",checks,{"zero_work":zero_row,"repeated_work":cached.paths.back(),"segment_entries":proof.segments.size()})
	sim.dispose()
	return result

func _budget_preserves_search(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker","S49",[34,66])
	suite._add_actor(sim,"blocker","S49",[36,70])
	# Legal orthogonal calculation input. 4224 distinct short legs fill both
	# maps by real successful predicate work before any original-route target.
	# This is not a claimed traversal or arrival; no fake cached proof is seeded.
	var prefix: Array = []
	for row: int in 65:
		var y: float = 66.0+0.01*row
		if row>0: prefix.append(_point(34.0 if row%2==0 else 34.64,y))
		for column: int in range(1,65):
			var x: float = 34.0+0.01*column if row%2==0 else 34.64-0.01*column
			prefix.append(_point(x,y))
	prefix.append_array([_point(35,66.64),_point(35,70)])
	var geometry: CountingSpace = CountingSpace.new(suite.content)
	var cached: CountingMovement = CountingMovement.new(geometry)
	var quarter: QuarterOnlyMovement = QuarterOnlyMovement.new(geometry)
	var movement: Dictionary = _movement("walker",[[36,70],[35,71]])
	var before: Dictionary = sim.world.freeze()
	var chosen: Dictionary = _search(cached,sim.world,"walker",movement,Vector2(35,70),prefix)
	var without_segments: Dictionary = _search(quarter,sim.world,"walker",movement,Vector2(35,70),prefix)
	var expected_path: Array = prefix.duplicate(true)
	expected_path.append(_point(35,71))
	var expected: Dictionary = {"index":1,"path":expected_path}
	var proof: Dictionary = cached.proofs[0] if not cached.proofs.is_empty() else {"sweeps":{},"segments":{}}
	var after_cap: Dictionary = cached.paths.back() if not cached.paths.is_empty() else {"contacts":0,"rectangles":0}
	var checks: Dictionary = {
		"segment_storage_cap_exactly_4096":proof.segments.size()==4096,
		"independent_quarter_storage_cap_exactly_4096":proof.sweeps.size()==4096,
		"actual_predicate_work_continues_past_both_caps":chosen.contacts>4096 and after_cap.contacts>0 and after_cap.rectangles>1,
		"all_blocked_target_links_and_later_candidate_are_tested":chosen.path_attempts==15 and without_segments.path_attempts==15,
		"occupied_target_not_admitted_when_cache_full":chosen.chosen.get("index",-1)==1,
		"later_target_and_entire_prefix_preserved":chosen.chosen==expected,
		"same_result_with_quarter_only_loop":chosen.chosen==without_segments.chosen,
		"existing_segment_hits_still_skip_quarter_rectangles":chosen.rectangles<without_segments.rectangles,
		"same_uncached_sweep_work_after_cap":chosen.contacts==without_segments.contacts,
		"new_proof_started_empty_before_real_saturation":_fresh_segment_proofs(cached,1),
		"all_inputs_remain_readonly":before==sim.world.freeze() and chosen.readonly and without_segments.readonly
	}
	# Avoid duplicating two 4227-point chosen paths in the result artifact.
	chosen.erase("chosen")
	without_segments.erase("chosen")
	var result: Dictionary = _row("storage_caps_do_not_limit_candidates_or_sweeps",checks,{"segment_entries":proof.segments.size(),"quarter_entries":proof.sweeps.size(),"prefix_segments":prefix.size(),"memo_work":chosen,"quarter_only_work":without_segments,"last_candidate_work":{"contacts":after_cap.contacts,"rectangles":after_cap.rectangles}})
	sim.dispose()
	return result
