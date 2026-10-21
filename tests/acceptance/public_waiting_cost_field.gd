extends "res://tests/acceptance/public_area_use.gd"

const ACTOR: String = "field_entry_actor"
const OriginalTravel = preload("res://tests/acceptance/single_connector_route.gd")

# Frozen complete 899df40 selection, before the warm-field consumer existed.
class OriginalAreas extends HospitalPublicAreas:
	func _waiting_point(world: WorldState, actor_id: String, reference: Dictionary, maximum_travel_ticks: int) -> Dictionary:
		var area: Dictionary = region(world,reference)
		if area.is_empty(): return {}
		var actor: Dictionary = world.facts.actors[actor_id]
		var floor_id: int = int(reference.floor_id)
		if contains(world,reference,actor_id) and safe_wait(world,actor_id,floor_id,actor.location.cell):
			return {"floor_id":floor_id,"cell":actor.location.cell.duplicate(),"travel_ticks":0}
		var origin: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
		var bounds: Dictionary = space.read_view(world,"public_entry_landings:"+actor_id+":"+str(floor_id),_entry_landings.bind(world,actor_id,floor_id))
		# Every complete cross-floor estimate must first reach a connector anchor
		# on this floor. With no complete landing estimate, trying every area cell
		# cannot produce one either, even when the common prefix is unknown.
		# This rejects only this read-only query; a later exit change is rechecked.
		if int(actor.location.floor_id)!=floor_id and bounds.landings.is_empty(): return {}
		if not bounds.landings.is_empty() and not bounds.unknown:
			var earliest: int = 9223372036854775807
			for landing: Dictionary in bounds.landings: earliest = mini(earliest,int(landing.ticks))
			if earliest>maximum_travel_ticks: return {}
		var geometry: Dictionary = _entry_geometry_view(world,actor,area)
		var ordered: Dictionary = _entry_order(actor,origin,bounds,geometry,maximum_travel_ticks)
		var packed: PackedInt64Array = ordered.packed
		var fallback: Array = ordered.fallback
		var best: Dictionary = {}
		for index: int in (packed.size() if ordered.compact else fallback.size()):
			var lower: int
			var point: Vector2i
			if ordered.compact:
				var key: int = packed[index]
				var cell_id: int = key%ENTRY_CELL_COUNT
				lower = key/ENTRY_CELL_COUNT+int(ordered.get("offset_ticks",0))
				point = Vector2i(cell_id%ENTRY_GRID_WIDTH,cell_id/ENTRY_GRID_WIDTH)
			else:
				lower = int(fallback[index].lower)
				point = fallback[index].cell
			if lower>maximum_travel_ticks: break
			if not best.is_empty() and lower>int(best.travel_ticks): break
			var cell: Array = [point.x,point.y]
			if not safe_wait(world,actor_id,floor_id,cell,geometry): continue
			var route: Dictionary = space.travel_quote(world,actor_id,floor_id,cell)
			if not route.ok or not route.has("travel_ticks"): continue
			if int(route.travel_ticks)<=maximum_travel_ticks and (best.is_empty() or int(route.travel_ticks)<int(best.travel_ticks)): best = {"floor_id":floor_id,"cell":cell,"travel_ticks":int(route.travel_ticks)}
		return best

func _field_fixture(cross_floor: bool, fractional: bool = false, unreachable: bool = false, multiple: bool = false) -> Dictionary:
	var x: Dictionary = _areas()
	var cell: Array = [38.35,90.35] if fractional else [38,90]
	x.world.facts.actors[ACTOR] = {"id":ACTOR,"name":ACTOR,"species_id":"S49","location":{"kind":"floor","floor_id":2 if cross_floor else 1,"cell":cell,"height_m":0.0},"facing":0.0,"posture":"standing"}
	if cross_floor:
		var plots: Array = HospitalSpace.floor_plots(x.world,1).duplicate(true)
		x.world.facts.floors.completed_top_floor = {}
		for plot: Array in plots: x.world.facts.floors.completed_top_floor[HospitalSpace.plot_key(plot)] = 2
		x.world.facts.floors.height_intervals = [{"first":1,"last":2,"height_m":float(_content.balance.floors.clear_height_m)}]
		x.world.facts.floors.overrides["2"] = {"plots":plots,"blocked":[],"doors":[],"paths":[]}
		x.world.facts.connectors["lift"] = {"id":"lift","definition_id":"VC02","first_floor":1,"last_floor":2,"cell":[58,84],"footprint":[4,4],"rotation":0,"anchor":[59,88],"repair_cell":[57,85],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0,"ticket_next":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},"paid_cost":3200,"used":false}
		if multiple:
			var second: Dictionary = x.world.facts.connectors.lift.duplicate(true)
			second.id = "second_lift"
			second.cell = [48,82]
			second.anchor = [49,86]
			second.repair_cell = [47,83]
			x.world.facts.connectors["second_lift"] = second
	if unreachable:
		# A complete real barrier leaves the actor's body and the target room
		# legal, while all same-floor paths between them are disconnected.
		for column: int in range(32,64): x.world.facts.floors.overrides["1"].blocked.append([column,80])
	x.world.touch()
	x.actual = HospitalSpace.new(_content)
	x.original = HospitalSpace.new(_content)
	x.original.navigation = OriginalTravel.FullSolver.new(x.original)
	x.original.public_areas = OriginalAreas.new(x.original)
	x.area = x.actual.public_areas.for_facility(x.world,"west_chair")
	x.root = Vector2i(59,88) if cross_floor else Vector2i(roundi(cell[0]),roundi(cell[1]))
	return x

func _field_begin(x: Dictionary) -> void:
	x.actual.begin_dynamic_route_query(x.world)
	x.original.begin_dynamic_route_query(x.world)

func _field_end(x: Dictionary) -> void:
	x.actual.end_route_query()
	x.original.end_route_query()

func _field_dispose(x: Dictionary) -> void:
	x.a.dispose()
	x.p.waiting_life = null
	x.p.environment = null
	x.e.waiting_life = null
	x.l.environment = null
	x.l.visitors = null
	x.c.recruitment = null
	x.clear()

func _warm(x: Dictionary) -> Dictionary:
	var valid: bool = true
	var count: int = 0
	var region: Dictionary = x.actual.public_areas.region(x.world,x.area)
	for point: Vector2i in region.cells:
		var cell: Array = [point.x,point.y]
		if not x.actual.public_areas.safe_wait(x.world,ACTOR,1,cell): continue
		var actual: Dictionary = x.actual.travel_quote(x.world,ACTOR,1,cell)
		var expected: Dictionary = x.original.travel_quote(x.world,ACTOR,1,cell)
		valid = valid and var_to_bytes(actual)==var_to_bytes(expected)
		count += 1
		if count>=18: break
	return {"ok":valid and count==18,"real_complete_quotes":count,"complete_quote_types_cost_status_equal":valid}

func _compare_wait(x: Dictionary, budget: int = HospitalTransit.MAX_TICK) -> Dictionary:
	var before: Dictionary = x.world.freeze()
	var actual_routes: int = int(x.actual.query_counts.routes)
	var original_routes: int = int(x.original.query_counts.routes)
	var field_hits: int = int(x.actual.query_counts.get("public_entry_field_hits",0))
	var field_builds: int = int(x.actual.query_counts.get("distance_field_builds",0))
	var actual: Dictionary = x.actual.public_areas.waiting_point(x.world,ACTOR,x.area,budget)
	var expected: Dictionary = x.original.public_areas.waiting_point(x.world,ACTOR,x.area,budget)
	var equal: bool = var_to_bytes(actual)==var_to_bytes(expected)
	return {"ok":equal and before==x.world.freeze(),"complete_waiting_point_equal":equal,"facts_rng_and_positions_unchanged":before==x.world.freeze(),"budget":budget,"actual":actual,"expected":expected if not equal else {},"actual_complete_quote_calls":int(x.actual.query_counts.routes)-actual_routes,"reference_complete_quote_calls":int(x.original.query_counts.routes)-original_routes,"warm_field_reads":int(x.actual.query_counts.get("public_entry_field_hits",0))-field_hits,"distance_fields_built":int(x.actual.query_counts.get("distance_field_builds",0))-field_builds}

func _warm_case(cross_floor: bool, fractional: bool = false, unreachable: bool = false, multiple: bool = false) -> Dictionary:
	var x: Dictionary = _field_fixture(cross_floor,fractional,unreachable,multiple)
	var validation: String = x.world.validate(_content)
	var checks: Dictionary = {"legal_input":validation.is_empty()}
	_field_begin(x)
	var warm: Dictionary = _warm(x)
	checks.original_real_quote_warmup_and_results = warm.ok
	var bounds: Dictionary = x.actual.public_areas._entry_landings(x.world,ACTOR,1)
	var borrow: Dictionary = x.actual.navigation.ready_waiting_cost_field(x.world,ACTOR,1,bounds)
	checks.expected_single_or_multiple_connector_guard = borrow.get("ready",false)==(not multiple)
	var comparison: Dictionary = _compare_wait(x)
	checks.whole_waiting_point_and_world_equal = comparison.ok
	if multiple:
		checks.multiple_connections_keep_complete_queries = comparison.warm_field_reads==0 and comparison.actual_complete_quote_calls>0
	else:
		checks.warm_loop_removes_complete_point_query_calls = comparison.warm_field_reads>0 and comparison.actual_complete_quote_calls<comparison.reference_complete_quote_calls
		checks.borrow_contains_only_array_and_scalars = borrow.keys().size()==4 and borrow.distances is PackedInt32Array and borrow.prefix_ticks is int and borrow.speed is float
		if not comparison.actual.is_empty():
			var exact: Dictionary = _compare_wait(x,int(comparison.actual.travel_ticks))
			var below: Dictionary = _compare_wait(x,int(comparison.actual.travel_ticks)-1)
			checks.exact_budget_and_stable_tie_preserved = exact.ok and exact.actual==comparison.actual and below.ok and below.actual.is_empty()
		else:
			checks.disconnected_area_is_still_unreachable = unreachable and comparison.actual.is_empty()
	if cross_floor and not multiple:
		var unknown: Dictionary = bounds.duplicate(true)
		unknown.unknown = true
		checks.unknown_landing_prefix_keeps_full_fallback = x.actual.navigation.ready_waiting_cost_field(x.world,ACTOR,1,unknown).is_empty()
		var wrong: Dictionary = bounds.duplicate(true)
		wrong.landings[0].ticks += 1
		checks.only_original_complete_landing_quote_can_supply_prefix = x.actual.navigation.ready_waiting_cost_field(x.world,ACTOR,1,wrong).is_empty()
	borrow = {}
	# Actual cache cleanup must remove borrowing eligibility even in this same
	# live scope; no graph or distance array is kept in a persistent task view.
	var query_clears: int = int(x.actual.query_counts.get("cache_query_clears",0))
	x.actual._navigation._trim(0,x.actual.query_counts)
	x.original._navigation._trim(0,x.original.query_counts)
	checks.real_trim_removes_ready_field = x.actual._navigation.ready_structural_field(x.actual,x.world,1,x.world.facts.actors[ACTOR],x.root).is_empty() and x.actual._navigation._entries.is_empty() and int(x.actual.query_counts.get("cache_query_clears",0))>query_clears
	var after_trim: Dictionary = _compare_wait(x)
	checks.after_trim_uses_original_complete_query_result = after_trim.ok and after_trim.actual_complete_quote_calls>0
	# Trimming removes the original field, but later real complete queries may
	# rebuild it. Borrowing is retried only after twelve such quotes.
	checks.after_trim_reactivation_requires_real_quote_warmup = after_trim.warm_field_reads==0 or (after_trim.actual_complete_quote_calls>=12 and after_trim.distance_fields_built>0)
	_field_end(x)
	var ok: bool = not checks.values().has(false)
	var result: Dictionary = {"ok":ok,"cross_floor":cross_floor,"fractional":fractional,"unreachable":unreachable,"multiple_connections":multiple,"validation":validation,"checks":checks,"warmup":warm,"comparison":comparison,"after_real_trim":after_trim}
	_field_dispose(x)
	return result

func _unprepared_and_changed() -> Dictionary:
	var x: Dictionary = _field_fixture(false,true)
	var validation: String = x.world.validate(_content)
	_field_begin(x)
	var actor: Dictionary = x.world.facts.actors[ACTOR]
	var cache: NavigationCache = x.actual._navigation
	var subject_missing: bool = x.actual.navigation.ready_waiting_cost_field(x.world,ACTOR,1,{}).is_empty()
	var hits: int = int(x.actual.query_counts.get("distance_field_builds",0))
	var absent: Dictionary = cache.ready_structural_field(x.actual,x.world,1,actor,x.root)
	var no_synthetic_warmup: bool = absent.is_empty() and hits==int(x.actual.query_counts.get("distance_field_builds",0))
	var cold: Dictionary = _compare_wait(x)
	var warm: Dictionary = _warm(x)
	var ready: bool = cache.ready_structural_field(x.actual,x.world,1,actor,x.root).get("ready",false)
	_field_end(x)
	var unscoped: bool = cache.ready_structural_field(x.actual,x.world,1,actor,x.root).is_empty() and x.actual.navigation.ready_waiting_cost_field(x.world,ACTOR,1,{}).is_empty()
	var ordinary: Dictionary = _compare_wait(x)
	var selected: Array = cold.actual.get("cell",[38,76])
	x.world.facts.floors.overrides["1"].blocked.append(selected.duplicate())
	x.world.touch()
	_field_begin(x)
	var changed_before_any_graph_refresh: Dictionary = cache.ready_structural_field(x.actual,x.world,1,actor,x.root)
	var changed: Dictionary = _compare_wait(x)
	_field_end(x)
	var checks: Dictionary = {"legal_initial_input":validation.is_empty(),"missing_original_source_proof_keeps_fallback":subject_missing,"getter_does_not_force_field_warmup":no_synthetic_warmup,"cold_complete_result_equal":cold.ok,"real_quotes_make_existing_field_ready":warm.ok and ready,"raw_and_ordinary_scope_keep_fallback":unscoped and ordinary.ok and ordinary.warm_field_reads==0,"source_edit_rejects_stale_ready_stamp_before_graph_refresh":changed_before_any_graph_refresh.is_empty(),"changed_geometry_keeps_complete_selection":changed.ok,"scopes_closed":x.actual._route_queries.is_empty() and x.original._route_queries.is_empty()}
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"validation":validation,"cold":cold,"warmup":warm,"ordinary":ordinary,"changed":changed}
	_field_dispose(x)
	return result

func _source_stub_failure() -> Dictionary:
	var x: Dictionary = _field_fixture(false)
	var actor: Dictionary = x.world.facts.actors[ACTOR]
	actor.location.cell = [44.75,80.0]
	x.world.facts.floors.overrides["1"].blocked.append([44,80])
	x.world.touch()
	var physically_clear: bool = not x.actual.body_rectangle(actor).intersects(Rect2(44,80,1,1),false)
	var validation: String = x.world.validate(_content)
	_field_begin(x)
	var failed: Dictionary = x.actual.travel_quote(x.world,ACTOR,1,[38,76])
	var expected: Dictionary = x.original.travel_quote(x.world,ACTOR,1,[38,76])
	var field: Dictionary = x.actual.navigation.ready_waiting_cost_field(x.world,ACTOR,1,{})
	var comparison: Dictionary = _compare_wait(x)
	_field_end(x)
	var checks: Dictionary = {"legal_actual_body_outside_block":physically_clear and validation.is_empty(),"original_fractional_source_proof_rejects":not failed.ok and var_to_bytes(failed)==var_to_bytes(expected),"failed_proof_does_not_enable_field_consumer":field.is_empty() and comparison.warm_field_reads==0,"whole_failed_selection_is_preserved":comparison.ok and comparison.actual.is_empty()}
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"validation":validation,"quote":failed,"selection":comparison}
	_field_dispose(x)
	return result

func run_case(suite: RefCounted) -> Dictionary:
	_content = suite.content
	var cases: Array = [_warm_case(false),_warm_case(false,true),_warm_case(false,false,true),_warm_case(true),_warm_case(true,true),_warm_case(true,false,false,true)]
	var lifecycle: Dictionary = _unprepared_and_changed()
	var stub: Dictionary = _source_stub_failure()
	var ok: bool = lifecycle.ok and stub.ok
	for row: Dictionary in cases: ok = ok and row.ok
	return {"ok":ok,"cases":cases,"warmup_source_and_geometry_lifetime":lifecycle,"fractional_source_failure":stub,"scope":"A resident structural field replaces only the task's repeated candidate time projection; actual safe_wait, complete candidate order and immutable facts remain independently compared with the frozen whole selector."}
