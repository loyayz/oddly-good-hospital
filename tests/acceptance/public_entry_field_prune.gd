extends "res://tests/acceptance/public_waiting_cost_field.gd"

const Baseline = preload("public_entry_field_original.gd")
const PhaseUse = preload("res://tests/acceptance/public_phase_use.gd")

# Observe actual predicates only. Neither probe substitutes safety or costs.
class ActualAreas extends HospitalPublicAreas:
	var trace: Array = []
	func _safe_wait_at(world: WorldState, actor_id: String, floor_id: int, point: Vector2i, origin: Vector2, actor: Dictionary, geometry: Dictionary) -> bool:
		var result: bool = super._safe_wait_at(world,actor_id,floor_id,point,origin,actor,geometry)
		trace.append({"kind":"safe","point":point,"safe":result})
		return result

class BaselineAreas extends Baseline:
	var trace: Array = []
	func _safe_wait_at(world: WorldState, actor_id: String, floor_id: int, point: Vector2i, origin: Vector2, actor: Dictionary, geometry: Dictionary) -> bool:
		var result: bool = super._safe_wait_at(world,actor_id,floor_id,point,origin,actor,geometry)
		trace.append({"kind":"safe","point":point,"safe":result})
		return result

class NavigationProbe extends HospitalNavigation:
	var trace: Array = []
	var observed_field: Dictionary = {}
	func ready_waiting_cost_field(world: WorldState, actor_id: String, floor_id: int, bounds: Dictionary) -> Dictionary:
		var result: Dictionary = super.ready_waiting_cost_field(world,actor_id,floor_id,bounds)
		trace.append({"kind":"borrow","ready":not result.is_empty()})
		# The copy is observational evidence, never supplied back to production.
		if not result.is_empty(): observed_field = result.duplicate(true)
		return result

# Unsupported-coordinate calculation projection, as in public_region_components.
# Legal world facts remain unchanged. Real safety must reject the projected
# domain-exterior point before any field access. No outcome/safety is mocked.
class OutsideActual extends ActualAreas:
	func _entry_geometry_view(world: WorldState, actor: Dictionary, area: Dictionary) -> Dictionary:
		var result: Dictionary = super._entry_geometry_view(world,actor,area).duplicate()
		result.cells = result.cells.duplicate()
		result.cells.append(Vector2i(96,96))
		result.native_order = false
		result.ordering = {}
		result.previous_ordering = {}
		return result

class OutsideBaseline extends BaselineAreas:
	func _entry_geometry_view(world: WorldState, actor: Dictionary, area: Dictionary) -> Dictionary:
		var result: Dictionary = super._entry_geometry_view(world,actor,area).duplicate()
		result.cells = result.cells.duplicate()
		result.cells.append(Vector2i(96,96))
		result.native_order = false
		result.ordering = {}
		result.previous_ordering = {}
		return result

func _setup(cross_floor: bool = false, fractional: bool = false, unreachable: bool = false) -> Dictionary:
	var x: Dictionary = _field_fixture(cross_floor,fractional,unreachable)
	x.actual.public_areas = ActualAreas.new(x.actual)
	x.original.public_areas = BaselineAreas.new(x.original)
	x.actual.navigation = NavigationProbe.new(x.actual)
	x.original.navigation = NavigationProbe.new(x.original)
	x.literal = HospitalSpace.new(_content)
	x.literal.navigation = OriginalTravel.FullSolver.new(x.literal)
	x.area = x.actual.public_areas.for_facility(x.world,"west_chair")
	return x

func _reset_probe(owner: HospitalSpace) -> void:
	owner.public_areas.trace = []
	owner.navigation.trace = owner.public_areas.trace
	owner.navigation.observed_field = {}

func _safes(events: Array) -> Array:
	return events.filter(func(row: Dictionary)->bool:return row.kind=="safe")

func _borrows(events: Array) -> Array:
	var result: Array = []
	var count: int = 0
	for event: Dictionary in events:
		if event.kind=="safe": count += 1
		else: result.append({"safe_calls_before_borrow":count,"ready":event.ready})
	return result

func _field_cost(field: Dictionary, point: Vector2i) -> int:
	if not FloorNavigation._inside(point): return -1
	var distance: int = field.distances[FloorNavigation._id(point)]
	return -1 if distance<0 else HospitalTransit._add(int(field.prefix_ticks),ceili(float(distance)/float(field.speed)/WorldState.TICK_SECONDS))

func _audit(actual: Array, baseline: Array, field: Dictionary, budget: int) -> Dictionary:
	var calls: Array = _safes(actual)
	var cursor: int = 0
	var incumbent: int = HospitalTransit.MAX_TICK
	var has_best: bool = false
	var borrowed: bool = false
	var skipped: Array = []
	var ok: bool = true
	for event: Dictionary in baseline:
		if event.kind=="borrow":
			continue
		var retained: bool = cursor<calls.size() and calls[cursor].point==event.point
		if retained:
			ok = ok and calls[cursor].safe==event.safe
			cursor += 1
		else:
			# Acquisition may occur earlier after the first full quote. Judge the
			# actual consumer timeline, not the old selector's retry schedule.
			borrowed = _borrows(actual).any(func(row: Dictionary)->bool:return row.ready and int(row.safe_calls_before_borrow)<=cursor)
			var ticks: int = _field_cost(field,event.point) if not field.is_empty() else -1
			var cannot_win: bool = ticks<0 or ticks>budget or has_best and ticks>=incumbent
			ok = ok and borrowed and FloorNavigation._inside(event.point) and cannot_win
			skipped.append({"point":event.point,"ticks":ticks,"incumbent":incumbent if has_best else -1,"baseline_safe":event.safe,"proved_nonwinner":cannot_win})
		if event.safe and not field.is_empty():
			var ticks: int = _field_cost(field,event.point)
			if ticks>=0 and ticks<=budget and (not has_best or ticks<incumbent):
				incumbent = ticks
				has_best = true
	ok = ok and cursor==calls.size() and _borrows(actual).all(func(row: Dictionary)->bool:return int(row.safe_calls_before_borrow)>0)
	return {"ok":ok,"actual_safe_wait_at_calls":calls.size(),"baseline_safe_wait_at_calls":_safes(baseline).size(),"skipped":skipped,"same_original_field_acquisition_timing":_borrows(actual)==_borrows(baseline),"borrows":_borrows(actual)}

func _observe(x: Dictionary, budget: int = HospitalTransit.MAX_TICK) -> Dictionary:
	_reset_probe(x.actual)
	_reset_probe(x.original)
	var before: Dictionary = x.world.freeze()
	var reference_before: Dictionary = x.area.duplicate(true)
	var depths: Array = [x.actual._route_queries.size(),x.original._route_queries.size()]
	var routes: int = int(x.actual.query_counts.routes)+int(x.actual.query_counts.get("public_entry_leg_quotes",0))
	var actual: Dictionary = x.actual.public_areas.waiting_point(x.world,ACTOR,x.area,budget)
	var expected: Dictionary = x.original.public_areas.waiting_point(x.world,ACTOR,x.area,budget)
	var trace: Array = x.actual.public_areas.trace.duplicate(true)
	var audit: Dictionary = _audit(trace,x.original.public_areas.trace,x.actual.navigation.observed_field,budget)
	var checks: Dictionary = {
		"exact_baseline_output":var_to_bytes(actual)==var_to_bytes(expected),
		"world_rng_and_reference_unchanged":before==x.world.freeze() and x.area==reference_before,
		"caller_query_depth_preserved":depths==[x.actual._route_queries.size(),x.original._route_queries.size()],
		"only_proved_nonwinners_skip_safety":audit.ok,
		"winner_received_real_safety_check":actual.is_empty() or _safes(trace).any(func(row: Dictionary)->bool:return row.safe and [row.point.x,row.point.y]==actual.cell)}
	return {"ok":not checks.values().has(false),"checks":checks,"actual":actual,"budget":budget,"audit":audit,"trace":trace,"field_ready":not x.actual.navigation.observed_field.is_empty(),"field_prefix_ticks":int(x.actual.navigation.observed_field.get("prefix_ticks",-1)),"real_quotes":int(x.actual.query_counts.routes)+int(x.actual.query_counts.get("public_entry_leg_quotes",0))-routes}

# Published STAFF-75 rectangle enumeration is independent of region/entry lists.
# Cross-floor costs use complete real routes; lower ordering uses complete landing
# quotes and the declared S49 2 cells/s rate, not candidate fields.
func _literal(x: Dictionary) -> Dictionary:
	var helper: RefCounted = PhaseUse.new()
	helper._content = _content
	if int(x.world.facts.actors[ACTOR].location.floor_id)==1:
		return helper._complete_entry_reference({"world":x.world,"space":x.literal},{"actor_id":ACTOR},1)
	var before: Dictionary = x.world.freeze()
	x.literal.begin_dynamic_route_query(x.world)
	var bounds: Dictionary = x.literal.public_areas._entry_landings(x.world,ACTOR,1)
	var best: Dictionary = {}
	var rows: Array = []
	for y: int in range(66,78):
		for px: int in range(34,44):
			var cell: Array = [px,y]
			if not x.literal.public_areas.safe_wait(x.world,ACTOR,1,cell): continue
			var quote: Dictionary = x.literal.route(x.world,ACTOR,1,cell,[],{},true)
			if not quote.get("ok",false) or not quote.has("travel_ticks"): continue
			var lower: int = HospitalTransit.MAX_TICK
			for landing: Dictionary in bounds.landings: lower = mini(lower,int(landing.ticks)+5*(absi(int(landing.cell.x)-px)+absi(int(landing.cell.y)-y)))
			var row: Dictionary = {"cell":cell,"lower":lower,"travel_ticks":int(quote.travel_ticks)}
			rows.append(row)
			if best.is_empty() or row.travel_ticks<best.travel_ticks or row.travel_ticks==best.travel_ticks and helper._entry_order_before(row,best): best = row
	x.literal.end_route_query()
	return {"rows":rows,"best":best,"readonly":before==x.world.freeze(),"complete_landings":bounds}

func _expected(literal: Dictionary, budget: int = HospitalTransit.MAX_TICK) -> Dictionary:
	if literal.best.is_empty() or int(literal.best.travel_ticks)>budget: return {}
	return {"floor_id":1,"cell":literal.best.cell.duplicate(),"travel_ticks":int(literal.best.travel_ticks)}

func _row(name: String, checks: Dictionary, observations: Array) -> Dictionary:
	return {"case":name,"ok":not checks.values().has(false) and observations.all(func(row: Dictionary)->bool:return row.ok),"checks":checks,"observations":observations}

func _resident(cross_floor: bool, fractional: bool, unreachable: bool = false) -> Dictionary:
	var x: Dictionary = _setup(cross_floor,fractional,unreachable)
	var checks: Dictionary = {"legal_calculation_input":x.world.validate(_content).is_empty()}
	var literal: Dictionary = _literal(x)
	_field_begin(x)
	var warm: Dictionary = _warm(x)
	checks.real_complete_quote_warmup = warm.ok
	var first: Dictionary = _observe(x)
	checks.independent_complete_result = literal.readonly and first.actual==_expected(literal)
	checks.resident_field_really_consumed = not x.actual.navigation.observed_field.is_empty()
	var observations: Array = [first]
	if not literal.best.is_empty():
		var exact: Dictionary = _observe(x,int(literal.best.travel_ticks))
		var below: Dictionary = _observe(x,int(literal.best.travel_ticks)-1)
		checks.inclusive_exact_and_under_budget = exact.actual==_expected(literal) and below.actual.is_empty()
		checks.safe_calls_actually_reduced = first.audit.actual_safe_wait_at_calls<first.audit.baseline_safe_wait_at_calls
		observations.append_array([exact,below])
	if cross_floor:
		checks.complete_original_landing = not literal.complete_landings.unknown and literal.complete_landings.landings.size()==1 and int(first.field_prefix_ticks)>=0
	_field_end(x)
	checks.scopes_closed = x.actual._route_queries.is_empty() and x.original._route_queries.is_empty() and x.literal._route_queries.is_empty()
	var result: Dictionary = _row("resident_"+("cross_floor" if cross_floor else "same_floor")+("_fractional" if fractional else "")+("_unreachable" if unreachable else ""),checks,observations)
	result.literal = literal
	_field_dispose(x)
	return result

func _cold_evicted() -> Dictionary:
	var x: Dictionary = _setup()
	var checks: Dictionary = {"legal_input":x.world.validate(_content).is_empty()}
	_field_begin(x)
	var cold: Dictionary = _observe(x)
	checks.cold_first_borrow_unavailable = not cold.audit.borrows.is_empty() and not cold.audit.borrows[0].ready and cold.real_quotes>0
	var warm: Dictionary = _warm(x)
	checks.real_warmup = warm.ok
	x.actual._navigation._trim(0,x.actual.query_counts)
	x.original._navigation._trim(0,x.original.query_counts)
	var evicted: Dictionary = _observe(x)
	checks.evicted_first_borrow_unavailable = not evicted.audit.borrows.is_empty() and not evicted.audit.borrows[0].ready and evicted.real_quotes>0
	checks.reactivation_requires_twelve_real_quotes = not evicted.audit.borrows.any(func(row: Dictionary)->bool:return row.ready) or evicted.real_quotes>=12
	_field_end(x)
	var unscoped: Dictionary = _observe(x)
	checks.ordinary_scope_never_borrows = unscoped.audit.borrows.all(func(row: Dictionary)->bool:return not row.ready) and unscoped.audit.actual_safe_wait_at_calls==unscoped.audit.baseline_safe_wait_at_calls
	checks.scopes_closed = x.actual._route_queries.is_empty() and x.original._route_queries.is_empty()
	var result: Dictionary = _row("cold_evicted_and_unscoped",checks,[cold,evicted,unscoped])
	_field_dispose(x)
	return result

func _dynamic_body() -> Dictionary:
	var x: Dictionary = _setup()
	var literal: Dictionary = _literal(x)
	var winner: Array = literal.best.cell.duplicate()
	var blocker: Dictionary = _visit(x,"field_blocker",winner)
	x.world.touch(false)
	var blocked_literal: Dictionary = _literal(x)
	var checks: Dictionary = {"legal_blocked_input":x.world.validate(_content).is_empty(),"tie_after_occupied_minimum":int(blocked_literal.order_ties)>1}
	_field_begin(x)
	var warm: Dictionary = _warm(x)
	var blocked: Dictionary = _observe(x)
	checks.real_warmup = warm.ok
	checks.occupied_candidate_checked_and_rejected = _safes(blocked.trace).any(func(row: Dictionary)->bool:return [row.point.x,row.point.y]==winner and not row.safe)
	checks.independent_tie_winner = blocked.actual==_expected(blocked_literal) and blocked.actual.cell!=winner
	_field_end(x)
	# This is a new legal calculation boundary, not claimed movement/arrival.
	# Keep the actor, visit and ticket identities. Only the independent input
	# pose changes; this does not claim a simulated departure or arrival.
	x.world.facts.actors[blocker.actor_id].location.cell = [54,90]
	x.world.touch(false)
	_field_begin(x)
	warm = _warm(x)
	var released: Dictionary = _observe(x)
	checks.next_query_rechecks_released_body = warm.ok and released.actual==_expected(literal)
	_field_end(x)
	checks.legal_released_input = x.world.validate(_content).is_empty()
	var result: Dictionary = _row("dynamic_body_ties_and_next_query",checks,[blocked,released])
	_field_dispose(x)
	return result

func _outside_projection() -> Dictionary:
	var x: Dictionary = _setup(false,false,true)
	x.actual.public_areas = OutsideActual.new(x.actual)
	x.original.public_areas = OutsideBaseline.new(x.original)
	var checks: Dictionary = {"legal_unchanged_world":x.world.validate(_content).is_empty()}
	_field_begin(x)
	var warm: Dictionary = _warm(x)
	var observed: Dictionary = _observe(x)
	checks.real_warmup = warm.ok
	checks.resident_field_before_outside_candidate = not x.actual.navigation.observed_field.is_empty()
	checks.real_outside_safety_reached_and_rejected = _safes(observed.trace).any(func(row: Dictionary)->bool:return row.point==Vector2i(96,96) and not row.safe)
	checks.unreachable_skips_continue_to_later_outside_point = not observed.audit.skipped.is_empty() and checks.real_outside_safety_reached_and_rejected
	checks.original_empty_result = observed.actual.is_empty()
	_field_end(x)
	var result: Dictionary = _row("unsupported_coordinate_projection",checks,[observed])
	result.scope = "Unsupported helper input projection, not a gameplay region or completed journey; coordinates 96,96 would index beyond the real 9216-element field without the guard."
	_field_dispose(x)
	return result

func run_selected(content: HospitalContent, selected: String = "") -> Dictionary:
	_content = content
	var names: Array = ["same_floor","fractional","cross_floor","cross_fractional","unreachable","cold_evicted","dynamic_body","outside_projection"]
	if not selected.is_empty() and not selected in names: return {"passed":false,"error":"Unknown focused case: "+selected}
	var cases: Array = []
	for name: String in names:
		if not selected.is_empty() and selected!=name: continue
		match name:
			"same_floor": cases.append(_resident(false,false))
			"fractional": cases.append(_resident(false,true))
			"cross_floor": cases.append(_resident(true,false))
			"cross_fractional": cases.append(_resident(true,true))
			"unreachable": cases.append(_resident(false,false,true))
			"cold_evicted": cases.append(_cold_evicted())
			"dynamic_body": cases.append(_dynamic_body())
			"outside_projection": cases.append(_outside_projection())
	return {"passed":cases.all(func(row: Dictionary)->bool:return row.ok),"cases":cases,"scope":"Read-only waiting-point calculations only; no arrival, movement, reservation acquisition or use is fabricated or claimed."}
