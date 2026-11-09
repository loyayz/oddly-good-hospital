extends RefCounted

# Requirements: task-navigation-movement.md sections 3-4. These are local
# collision/search calculation boundaries, not fabricated journeys or arrivals.
# Counts observe real predicates. No sweep, clearance, or collision is stubbed.
class CountingMovement extends HospitalMovement:
	var contacts: int = 0
	var paths: Array = []
	var proofs: Array = []
	var proof_initial_sizes: Array = []
	var all_convoy_proofs_empty: bool = true
	func _init(geometry: HospitalSpace) -> void:
		super(geometry)
	func _movement_contacts(world: WorldState, actor_id: String, floor_id: int, broad: Rect2, sweeps: Array[BodyIndex.Record], members: Array, result: MotionResult, queries: Dictionary = {}) -> void:
		contacts += 1
		super._movement_contacts(world,actor_id,floor_id,broad,sweeps,members,result,queries)
	func _detour_path_clear(world: WorldState, actor: Dictionary, movement: Dictionary, path: Array, query: RouteClearance = null, proof: Dictionary = {}) -> bool:
		if movement.has("convoy"): all_convoy_proofs_empty = all_convoy_proofs_empty and proof.is_empty()
		if not proof.is_empty():
			var known: bool = false
			for existing: Dictionary in proofs: known = known or is_same(existing,proof)
			if not known:
				proofs.append(proof)
				proof_initial_sizes.append(proof.sweeps.size())
		var before: int = contacts
		var clear: bool = super._detour_path_clear(world,actor,movement,path,query,proof)
		paths.append({"path":path.duplicate(true),"clear":clear,"contacts":contacts-before})
		return clear

class NoMemoMovement extends CountingMovement:
	func _init(geometry: HospitalSpace) -> void:
		super(geometry)
	func _detour_path_clear(world: WorldState, actor: Dictionary, movement: Dictionary, path: Array, query: RouteClearance = null, _proof: Dictionary = {}) -> bool:
		# Original complete production predicate. No copied collision algorithm.
		return super._detour_path_clear(world,actor,movement,path,query,{})

func run(content: HospitalContent) -> Dictionary:
	return run_selected(content)

func run_selected(content: HospitalContent, selected: String = "") -> Dictionary:
	# Runtime load avoids a preload cycle when this module is registered in
	# the existing SPACE suite. Reuse only its declared input-boundary helpers.
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new()
	suite.content = content
	var names: Array = ["positive_negative_and_selection","exact_rectangle_keys","same_tick_dynamic_boundaries","accepted_sweep_boundaries","independent_and_restored_worlds","convoy_bypass","budget_preserves_search","real_intention_collision"]
	if not selected.is_empty() and not selected in names:
		return {"passed":false,"details":{"error":"Unknown focused case: "+selected}}
	var cases: Array = []
	for name: String in names:
		if selected.is_empty() or selected==name: cases.append(call("_"+name,suite))
	var ok: bool = true
	for row: Dictionary in cases: ok = ok and bool(row.ok)
	return {"passed":ok,"details":{"case":"query_local_detour_step_proof","cases":cases,"scope":"Pure return-link calculation boundaries; real movement remains covered by SPACE-10/56/57 and the full production warm workload."}}

func _point(x: float,y: float) -> Dictionary:
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
	var before: Dictionary = world.freeze()
	var before_movement: Dictionary = movement.duplicate(true)
	var before_contacts: int = service.contacts
	var before_proofs: int = service.proofs.size()
	var chosen: Dictionary = service._detour_return_path(world,world.facts.actors[id],movement,origin,prefix)
	return {"chosen":chosen,"contacts":service.contacts-before_contacts,"readonly":world.freeze()==before and movement==before_movement,"new_proofs":service.proofs.size()-before_proofs}

func _positive_negative_and_selection(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker","S49",[35,70])
	suite._add_actor(sim,"blocker","S49",[36,70])
	var cached: CountingMovement = CountingMovement.new(sim.space)
	var oracle: NoMemoMovement = NoMemoMovement.new(sim.space)
	var actor: Dictionary = sim.world.facts.actors.walker
	var movement: Dictionary = _movement("walker",[[36,70],[37,70]])
	var query: RouteClearance = sim.space.navigation.structural_clearance(sim.world,actor,1)
	var proof: Dictionary = {"sweeps":{}}
	var before: Dictionary = sim.world.freeze()
	var positive: Array = [_point(35,71)]
	var negative: Array = [_point(36,70)]
	var first_positive: bool = cached._detour_path_clear(sim.world,actor,movement,positive,query,proof)
	var positive_contacts: int = cached.contacts
	var second_positive: bool = cached._detour_path_clear(sim.world,actor,movement,positive,query,proof)
	var positive_reused: bool = cached.contacts==positive_contacts and positive_contacts>0
	var first_negative: bool = cached._detour_path_clear(sim.world,actor,movement,negative,query,proof)
	var negative_contacts: int = cached.contacts
	var second_negative: bool = cached._detour_path_clear(sim.world,actor,movement,negative,query,proof)
	var negative_reused: bool = cached.contacts==negative_contacts and negative_contacts>positive_contacts
	var true_count: int = 0
	var false_count: int = 0
	for value: bool in proof.sweeps.values():
		if value: true_count += 1
		else: false_count += 1
	var selected: Dictionary = _search(cached,sim.world,"walker",movement,Vector2(35,70))
	var baseline: Dictionary = _search(oracle,sim.world,"walker",movement,Vector2(35,70))
	# Cell 36 is occupied. Cell 37 is the nearest unoccupied return intention.
	# Only its first actual step is proved here, not the whole blocked straight leg.
	var expected: Dictionary = {"index":1,"path":[_point(37,70)]}
	var checks: Dictionary = {
		"clear_path_true_twice":first_positive and second_positive,
		"blocked_path_false_twice":not first_negative and not second_negative,
		"positive_proof_skips_contacts":positive_reused,
		"negative_proof_skips_contacts":negative_reused,
		"both_boolean_values_cached":true_count>0 and false_count>0,
		"nearest_successor_and_ordered_path":selected.chosen==expected,
		"same_chosen_path_and_index_without_memo":selected.chosen==baseline.chosen,
		"intention_still_executes_current_contacts":selected.contacts>0 and baseline.contacts>0,
		"intention_not_full_path_permission":not oracle._detour_path_clear(sim.world,actor,movement,expected.path,query),
		"facts_and_request_readonly":before==sim.world.freeze() and selected.readonly and baseline.readonly,
		"first_intention_step_is_clear":oracle._detour_path_clear(sim.world,actor,movement,[_point(35.2,70)],query)
	}
	var result: Dictionary = _row("positive_negative_proof_and_nearest_return",checks,{"selected":selected,"no_memo":baseline,"positive_entries":true_count,"negative_entries":false_count})
	sim.dispose()
	return result

func _exact_rectangle_keys(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var origin: Vector2 = Vector2(40.125,80.375)
	suite._add_actor(sim,"walker","S03",[origin.x,origin.y])
	var cached: CountingMovement = CountingMovement.new(sim.space)
	var oracle: NoMemoMovement = NoMemoMovement.new(sim.space)
	var actor: Dictionary = sim.world.facts.actors.walker
	var movement: Dictionary = _movement("walker",[[42,82]])
	var query: RouteClearance = sim.space.navigation.structural_clearance(sim.world,actor,1)
	var proof: Dictionary = {"sweeps":{}}
	var short: Array = [_point(origin.x+0.2,origin.y)]
	var turning: Array = [_point(origin.x,origin.y+1),_point(origin.x-1,origin.y+1),_point(origin.x-1,origin.y),_point(origin.x,origin.y),_point(origin.x+0.2,origin.y)]
	var reverse: Array = [_point(origin.x+0.2,origin.y),_point(origin.x,origin.y),_point(origin.x,origin.y-0.2)]
	# One-ULP target drift is below the existing orthogonal tolerance. At the
	# first quarter step float32 coordinates coincide, but float64 atan2 yields
	# a distinct non-square next rectangle. No input/facing is changed mid-proof.
	var horizontal: Array = [_point(origin.x+20,origin.y)]
	var near_axis: Array = [_point(origin.x+20,origin.y+0.00000762939453125)]
	var paths: Array = [short,turning,reverse,horizontal,near_axis]
	var before: Dictionary = sim.world.freeze()
	var all_clear: bool = true
	var oracle_equal: bool = true
	for path: Array in paths:
		var result: bool = cached._detour_path_clear(sim.world,actor,movement,path,query,proof)
		all_clear = all_clear and result
		oracle_equal = oracle_equal and result==oracle._detour_path_clear(sim.world,actor,movement,path,query)
	var previous_distinct: bool = false
	var next_distinct: bool = false
	var by_points: Dictionary = {}
	var subquarter: bool = false
	var reverse_preserved: bool = false
	for key: Array in proof.sweeps:
		var points: Array = [key[0],key[1]]
		for prior: Array in by_points.get(points,[]):
			previous_distinct = previous_distinct or prior[2]!=key[2]
			next_distinct = next_distinct or prior[3]!=key[3]
		if not by_points.has(points): by_points[points] = []
		by_points[points].append(key)
		subquarter = subquarter or (key[0].distance_to(key[1])<0.249 and key[0].distance_to(key[1])>0.001)
		reverse_preserved = reverse_preserved or proof.sweeps.has([key[1],key[0],key[3],key[2]])
	var contacts_before_repeat: int = cached.contacts
	var repeat: bool = cached._detour_path_clear(sim.world,actor,movement,short,query,proof)
	var dimensions: Dictionary = sim.space.body(actor)
	var checks: Dictionary = {
		"legal_non_square_species":dimensions.width_m!=dimensions.depth_m,
		"all_open_fractional_turn_reverse_paths_clear":all_clear,
		"no_memo_predicate_agrees":oracle_equal,
		"same_endpoints_different_previous_rectangle_not_aliased":previous_distinct,
		"same_endpoints_different_next_rectangle_not_aliased":next_distinct,
		"short_final_step_preserved":subquarter,
		"opposite_directed_sweeps_remain_separate":reverse_preserved,
		"original_orientation_proof_still_reuses":repeat and cached.contacts==contacts_before_repeat,
		"facts_readonly":before==sim.world.freeze()
	}
	var result: Dictionary = _row("exact_points_and_both_real_rectangles",checks,{"proof_entries":proof.sweeps.size(),"contacts":cached.contacts,"no_memo_contacts":oracle.contacts,"fractional_origin":[origin.x,origin.y]})
	sim.dispose()
	return result

func _same_tick_dynamic_boundaries(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	HospitalFactory._add_facility(sim.world,{"id":"local_reservation","definition_id":"M37","anchor":[44,76],"size":suite.content.facility_definition("M37").footprint.duplicate(),"room_id":null},suite.content)
	var target:Array=sim.world.facts.facilities["local_reservation"].patient_cell.duplicate()
	var origin:Vector2=Vector2(float(target[0])-1,float(target[1]))
	suite._add_actor(sim,"walker","S49",[origin.x,origin.y])
	suite._add_actor(sim,"blocker","S49",target)
	suite._add_actor(sim,"owner","S49",[50,85])
	var cached: CountingMovement = CountingMovement.new(sim.space)
	var oracle: NoMemoMovement = NoMemoMovement.new(sim.space)
	var movement: Dictionary = _movement("walker",[target])
	var tick: int = sim.world.sim_tick
	var rows: Array = []
	var legal_inputs: Array[String] = []
	legal_inputs.append(sim.world.validate(suite.content))
	rows.append(_search(cached,sim.world,"walker",movement,origin))
	# Declare the next collision-query input. This is not a simulated move,
	# completed retreat, or arrival; actual traversal tests remain separate.
	sim.world.facts.actors.blocker.location.cell = [40,74]
	sim.world.touch()
	sim.space.sync_actor(sim.world,"blocker")
	legal_inputs.append(sim.world.validate(suite.content))
	rows.append(_search(cached,sim.world,"walker",movement,origin))
	var reservation_error:String=sim.space.reserve_facility(sim.world,"local_reservation","owner","owner")
	var reservation:Dictionary=sim.world.facts.adaptations.get("local_reservation",{})
	if not reservation_error.is_empty():
		sim.dispose()
		return _row("same_tick_body_and_reservation_changes",{"real_reservation_acquired":false},{"reason":reservation_error})
	legal_inputs.append(sim.world.validate(suite.content))
	rows.append(_search(cached,sim.world,"walker",movement,origin))
	reservation.staff_ids = ["walker"]
	sim.space.reservation_changed(sim.world,"local_reservation")
	legal_inputs.append(sim.world.validate(suite.content))
	rows.append(_search(cached,sim.world,"walker",movement,origin))
	reservation.staff_ids = []
	sim.space.reservation_changed(sim.world,"local_reservation")
	legal_inputs.append(sim.world.validate(suite.content))
	rows.append(_search(cached,sim.world,"walker",movement,origin))
	legal_inputs.append(sim.world.validate(suite.content))
	var revoked_oracle: Dictionary = _search(oracle,sim.world,"walker",movement,origin)
	sim.world.facts.adaptations.erase("local_reservation")
	sim.space.reservation_changed(sim.world,"local_reservation")
	legal_inputs.append(sim.world.validate(suite.content))
	rows.append(_search(cached,sim.world,"walker",movement,origin))
	var expected: Dictionary = {"index":0,"path":[_point(float(target[0]),float(target[1]))]}
	var fresh: bool = true
	var readonly: bool = true
	for row: Dictionary in rows: fresh = fresh and row.contacts>0;readonly = readonly and row.readonly
	var checks: Dictionary = {
		"all_query_inputs_are_legal":legal_inputs.all(func(error: String) -> bool: return error.is_empty()),
		"initial_occupied_target_rejected":rows[0].chosen.is_empty(),
		"changed_current_body_rechecked":rows[1].chosen==expected,
		"new_reservation_rechecked":rows[2].chosen.is_empty(),
		"new_staff_permission_rechecked":rows[3].chosen==expected,
		"revoked_permission_rechecked":rows[4].chosen.is_empty() and revoked_oracle.chosen.is_empty(),
		"released_reservation_rechecked":rows[5].chosen==expected,
		"same_tick_for_every_boundary":sim.world.sim_tick==tick,
		"each_boundary_rechecks_actual_contacts":fresh,
		"each_query_is_readonly":readonly
	}
	var result: Dictionary = _row("same_tick_body_and_reservation_changes",checks,{"calls":rows,"input_validation":legal_inputs})
	sim.dispose()
	return result

func _put_accepted(service: HospitalMovement, space: HospitalSpace, actor: Dictionary, from: Vector2) -> BodyIndex.Record:
	var sweep: BodyIndex.Record = BodyIndex.Record.new()
	sweep.id = actor.id
	sweep.floor_id = int(actor.location.floor_id)
	sweep.sweep_from = space._actor_rect(actor,from)
	sweep.sweep_to = space.body_rectangle(actor)
	service._accepted_sweeps[actor.id] = sweep
	service._sweep_index.update(actor.id,sweep.floor_id,sweep.sweep_from.merge(sweep.sweep_to))
	return sweep

func _accepted_sweep_boundaries(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker","S49",[43.5,82])
	suite._add_actor(sim,"crossing","S49",[44.1,82.5])
	var actor: Dictionary = sim.world.facts.actors.walker
	var obstacle: Dictionary = sim.world.facts.actors.crossing
	var movement: Dictionary = _movement("walker",[[43.7,82]])
	var direct: Array = [_point(43.7,82)]
	var cached: CountingMovement = CountingMovement.new(sim.space)
	var oracle: NoMemoMovement = NoMemoMovement.new(sim.space)
	var tick: int = sim.world.sim_tick
	cached._sweep_index.begin_boundary(sim.world.facts.actors)
	oracle._sweep_index.begin_boundary(sim.world.facts.actors)
	var crossing: BodyIndex.Record = _put_accepted(cached,sim.space,obstacle,Vector2(44.1,82.3))
	_put_accepted(oracle,sim.space,obstacle,Vector2(44.1,82.3))
	var from: Rect2 = sim.space.body_rectangle(actor)
	var to: Rect2 = sim.space._actor_rect(actor,Vector2(43.7,82))
	var direct_blocked: bool = not cached._detour_path_clear(sim.world,actor,movement,direct,null,{"sweeps":{}})
	var first: Dictionary = _search(cached,sim.world,"walker",movement,Vector2(43.5,82))
	var first_oracle: Dictionary = _search(oracle,sim.world,"walker",movement,Vector2(43.5,82))
	var replacement: BodyIndex.Record = _put_accepted(cached,sim.space,obstacle,Vector2(44.1,82.7))
	_put_accepted(oracle,sim.space,obstacle,Vector2(44.1,82.7))
	var replaced: Dictionary = _search(cached,sim.world,"walker",movement,Vector2(43.5,82))
	var replaced_oracle: Dictionary = _search(oracle,sim.world,"walker",movement,Vector2(43.5,82))
	_put_accepted(cached,sim.space,obstacle,Vector2(44.1,82.3))
	var crossing_again: Dictionary = _search(cached,sim.world,"walker",movement,Vector2(43.5,82))
	# Run the production boundary lifecycle (there are no journeys). It must
	# expire accepted motion before later queries, without advancing sim_tick.
	cached.advance(sim.world,sim.world.present_actor_count())
	var expired: Dictionary = _search(cached,sim.world,"walker",movement,Vector2(43.5,82))
	# Return-link points use real Vector2 coordinates; compare their exact
	# representable value, not a distinct float64 JSON-style literal.
	var target: Vector2 = Vector2(43.7,82)
	var expected: Dictionary = {"index":0,"path":[_point(target.x,target.y)]}
	var checks: Dictionary = {
		"legal_earlier_step_length":crossing.sweep_from.position.distance_to(crossing.sweep_to.position)<=0.2001 and replacement.sweep_from.position.distance_to(replacement.sweep_to.position)<=0.2001,
		"initial_bodies_separate":not from.intersects(crossing.sweep_from,false) and not from.intersects(crossing.sweep_to,false),
		"current_endpoint_does_not_block":not to.intersects(crossing.sweep_to,false),
		"timed_crossing_really_blocks":BodySweep.intersects(from,to,crossing.sweep_from,crossing.sweep_to) and direct_blocked,
		"crossing_cannot_choose_direct":first.chosen!=expected and first.chosen==first_oracle.chosen,
		"replacement_rechecked_same_tick":replaced.chosen==expected and replaced.chosen==replaced_oracle.chosen,
		"restored_crossing_rechecked":crossing_again.chosen==first.chosen,
		"production_expiry_releases_direct_path":expired.chosen==expected and cached._accepted_sweeps.is_empty() and not cached._sweep_index._has_current_records,
		"same_tick":sim.world.sim_tick==tick,
		"all_queries_readonly":first.readonly and first_oracle.readonly and replaced.readonly and replaced_oracle.readonly and crossing_again.readonly and expired.readonly,
		"each_boundary_executes_contacts":first.contacts>0 and replaced.contacts>0 and crossing_again.contacts>0 and expired.contacts>0
	}
	var result: Dictionary = _row("accepted_sweep_replacement_and_expiry",checks,{"crossing":first,"replacement":replaced,"expiry":expired})
	sim.dispose()
	return result

func _independent_and_restored_worlds(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker","S49",[35,70])
	suite._add_actor(sim,"blocker","S49",[36,70])
	var source: Dictionary = sim.world.freeze()
	var restored: WorldState = WorldState.new(source.duplicate(true))
	var independent_source: Dictionary = source.duplicate(true)
	independent_source.actors.blocker.location.cell = [40,74]
	var independent: WorldState = WorldState.new(independent_source)
	var cached: CountingMovement = CountingMovement.new(sim.space)
	var oracle: NoMemoMovement = NoMemoMovement.new(sim.space)
	var movement: Dictionary = _movement("walker",[[36,70]])
	var a: Dictionary = _search(cached,sim.world,"walker",movement,Vector2(35,70))
	var b: Dictionary = _search(cached,independent,"walker",movement,Vector2(35,70))
	var c: Dictionary = _search(cached,restored,"walker",movement,Vector2(35,70))
	var d: Dictionary = _search(cached,sim.world,"walker",movement,Vector2(35,70))
	var cold: Dictionary = _search(oracle,restored,"walker",movement,Vector2(35,70))
	var expected: Dictionary = {"index":0,"path":[_point(36,70)]}
	var checks: Dictionary = {
		"independent_world_does_not_inherit_negative":a.chosen.is_empty() and b.chosen==expected,
		"restored_world_does_not_inherit_positive":c.chosen.is_empty() and c.chosen==cold.chosen,
		"return_to_original_world_rechecks":d.chosen==a.chosen,
		"restore_contains_only_original_facts":restored.freeze()==source,
		"all_decisions_readonly":a.readonly and b.readonly and c.readonly and d.readonly and cold.readonly,
		"four_world_boundaries_execute_contacts":a.contacts>0 and b.contacts>0 and c.contacts>0 and d.contacts>0,
		"legal_world_inputs":sim.world.validate(suite.content).is_empty() and restored.validate(suite.content).is_empty() and independent.validate(suite.content).is_empty()
	}
	var result: Dictionary = _row("independent_and_restored_world_scope",checks)
	sim.dispose()
	return result

func _convoy_bypass(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"head","S49",[44,82])
	suite._add_actor(sim,"tail","S49",[42,82])
	var created: Dictionary = ConvoyTrail.create(sim.space,sim.world,"head",["head","tail"])
	if not created.ok:
		sim.dispose()
		return _row("convoy_keeps_original_complete_predicate",{"legal_formation":false},{"error":created.reason})
	var movement: Dictionary = _movement("head",[[45,82]])
	movement.members = ["head","tail"]
	movement.convoy = created.convoy
	var cached: CountingMovement = CountingMovement.new(sim.space)
	var oracle: NoMemoMovement = NoMemoMovement.new(sim.space)
	var a: Dictionary = _search(cached,sim.world,"head",movement,Vector2(44,82))
	var b: Dictionary = _search(oracle,sim.world,"head",movement,Vector2(44,82))
	var back: Array = [_point(42,82)]
	var reverse_a: bool = cached._detour_path_clear(sim.world,sim.world.facts.actors.head,movement,back)
	var reverse_b: bool = oracle._detour_path_clear(sim.world,sim.world.facts.actors.head,movement,back)
	var checks: Dictionary = {
		"legal_complete_convoy":created.ok,
		"forward_path_preserved":a.chosen=={"index":0,"path":[_point(45,82)]} and a.chosen==b.chosen,
		"convoy_contacts_not_memoized":a.contacts==b.contacts and a.contacts>0,
		"every_convoy_proof_empty":cached.all_convoy_proofs_empty and cached.proofs.is_empty(),
		"cannot_reverse_into_own_tail":not reverse_a and not reverse_b,
		"query_does_not_commit_trail":a.readonly and b.readonly
	}
	var result: Dictionary = _row("convoy_keeps_original_complete_predicate",checks,{"memo_contacts":a.contacts,"no_memo_contacts":b.contacts})
	sim.dispose()
	return result

func _budget_preserves_search(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker","S49",[34,66])
	suite._add_actor(sim,"blocker","S49",[60,89])
	# Legal orthogonal query prefix, entirely on the owned floor. Its many
	# distinct sweeps saturate scratch memory before original-cell selection.
	# This is calculation input, not a claimed completed walk or arrival.
	var prefix: Array = []
	for row: int in 45:
		var y: float = 66.0+0.5*row
		var x: float = 60.0 if row%2==0 else 34.0
		if row>0: prefix.append(_point(34.0 if row%2==0 else 60.0,y))
		prefix.append(_point(x,y))
	var movement: Dictionary = _movement("walker",[[60,89],[59,89]])
	var cached: CountingMovement = CountingMovement.new(sim.space)
	var oracle: NoMemoMovement = NoMemoMovement.new(sim.space)
	var before: Dictionary = sim.world.freeze()
	var actor: Dictionary=sim.world.facts.actors.walker
	var proof: Dictionary={"sweeps":{}}
	var query: RouteClearance=sim.space.navigation.structural_clearance(sim.world,actor,1)
	var clear: bool=cached._detour_path_clear(sim.world,actor,movement,prefix,query,proof)
	var prefix_contacts: int=cached.contacts
	var blocked_path: Array=prefix.duplicate(true)
	blocked_path.append(_point(60,89))
	var denied: bool=not cached._detour_path_clear(sim.world,actor,movement,blocked_path,query,proof)
	var blocked_contacts: int=cached.contacts-prefix_contacts
	var allowed_path: Array=prefix.duplicate(true)
	allowed_path.append_array([_point(59,88),_point(59,89)])
	var permitted: bool=cached._detour_path_clear(sim.world,actor,movement,allowed_path,query,proof)
	var oracle_denied: bool=not oracle._detour_path_clear(sim.world,actor,movement,blocked_path,query)
	var oracle_permitted: bool=oracle._detour_path_clear(sim.world,actor,movement,allowed_path,query)
	var checks: Dictionary={
		"real_sweeps_fill_storage_cap":clear and proof.sweeps.size()==4096,
		"full_path_work_continues_after_cap":prefix_contacts>4096 and blocked_contacts>0,
		"occupied_terminal_rejected_after_cap":denied and oracle_denied,
		"later_safe_full_path_allowed_after_cap":permitted and oracle_permitted,
		"memo_still_avoids_repeated_work":cached.contacts<oracle.contacts+prefix_contacts,
		"facts_remain_readonly":before==sim.world.freeze()
	}
	var result: Dictionary=_row("full_path_proof_budget_preserves_collision",checks,{"entries":proof.sweeps.size(),"prefix_contacts":prefix_contacts,"blocked_contacts":blocked_contacts,"scope":"complete proof API retained for clinical callers; not single-person return-intention allocation"})
	sim.dispose()
	return result

func _real_intention_collision(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation=suite._fixture()
	suite._add_actor(sim,"walker","S49",[35,70])
	suite._add_actor(sim,"blocker","S49",[36,70])
	var requested: String=sim.space.request_move(sim.world,"walker",1,[37,70])
	var safe: bool=true
	var target_kept: bool=true
	var side_seen: bool=false
	var max_step: float=float(suite.content.balance.movement_speeds["1"])*WorldState.TICK_SECONDS
	for tick: int in 180:
		var before: Rect2=sim.space.body_rectangle(sim.world.facts.actors.walker)
		var location: Vector2=ConvoyTrail.point(sim.world.facts.actors.walker.location.cell)
		suite._movement_tick(sim)
		var after: Rect2=sim.space.body_rectangle(sim.world.facts.actors.walker)
		var blocker: Rect2=sim.space.body_rectangle(sim.world.facts.actors.blocker)
		var now: Vector2=ConvoyTrail.point(sim.world.facts.actors.walker.location.cell)
		safe=safe and not BodySweep.intersects(before,after,blocker,blocker) and now.distance_to(location)<=max_step+0.0001
		side_seen=side_seen or absf(now.y-70.0)>0.01
		if sim.world.facts.moves.has("walker"):target_kept=target_kept and sim.world.facts.moves.walker.target_cell==[37,70]
		if sim.space.at(sim.world,"walker",1,[37,70]) and not sim.world.facts.moves.has("walker"):break
	var checks: Dictionary={"request_accepted":requested.is_empty(),"every_actual_sweep_safe":safe,"actual_side_motion_seen":side_seen,"original_target_preserved":target_kept,"actually_arrived":sim.space.at(sim.world,"walker",1,[37,70]) and not sim.world.facts.moves.has("walker"),"stationary_blocker_not_displaced":sim.space.at(sim.world,"blocker",1,[36,70]),"world_valid":sim.world.validate(suite.content).is_empty()}
	var result: Dictionary=_row("return_intention_never_grants_future_collision_permission",checks)
	sim.dispose()
	return result
