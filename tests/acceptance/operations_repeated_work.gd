extends RefCounted

# Independent full reservation enumeration retains the pre-index collision
# authority. It uses the real route, transit, body and sweep implementations.
class FullReservationSpace extends HospitalSpace:
	func _reservation_regions(world: WorldState, _floor_id: int, _rect: Rect2) -> Array:
		var result: Array = []
		for id: String in world.facts.adaptations:
			var reservation: Dictionary = world.facts.adaptations[id]
			for area: Array in reservation.regions:
				result.append({"reservation":reservation,"reservation_id":id,"rect":Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3]))})
		return result

func _builder(content: HospitalContent) -> RefCounted:
	var builder: RefCounted = load("res://tests/acceptance/operations.gd").new()
	builder._content = content
	return builder

func _dispose(builder: RefCounted) -> void:
	for simulation: HospitalSimulation in builder._live: simulation.dispose()

func run_indices(content: HospitalContent) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var builder: RefCounted = _builder(content)
	var f: Dictionary = builder._new("可重建运营观察索引")
	var world: WorldState = f.w
	var checks: Dictionary = {}
	var records: Dictionary = {"first":{"consumed":false}}
	var before: Dictionary = world.freeze()
	checks.independent_observers = world.pending_fact_ids("a","boundary",records)==["first"] and world.pending_fact_ids("b","boundary",records)==["first"] and world.pending_fact_ids("a","boundary",records).is_empty()
	records.second = {"consumed":false}
	world.fact_record_changed("boundary","second")
	checks.append_once = world.pending_fact_ids("a","boundary",records)==["second"] and world.pending_fact_ids("a","boundary",records).is_empty() and world.pending_fact_ids("b","boundary",records)==["second"]
	records.first.consumed = false
	world.fact_record_changed("boundary","first")
	checks.rewrite_reenters = world.pending_fact_ids("a","boundary",records)==["first"]
	var replaced: Dictionary = {"replacement":{"consumed":false},"other":{"consumed":false}}
	checks.same_count_replacement = world.pending_fact_ids("a","boundary",replaced)==["replacement","other"]
	checks.observation_readonly = world.freeze()==before
	var restored: WorldState = WorldState.new(world.freeze())
	checks.restore_rebuild = restored.pending_fact_ids("a","boundary",records)==["first","second"]
	var observer_count: int = world._pending_sources.size()
	var first_owner: RefCounted = RefCounted.new()
	var second_owner: RefCounted = RefCounted.new()
	checks.live_owner_isolation = world.pending_fact_ids("owned_first","owned",records,first_owner)==["first","second"] and world.pending_fact_ids("owned_second","owned",records,second_owner)==["first","second"]
	first_owner = null
	world.fact_record_changed("owned","first")
	checks.dead_owner_pruned = world._pending_sources.size()==observer_count+1 and world.pending_fact_ids("owned_second","owned",records,second_owner)==["first"]
	second_owner = null
	world.fact_record_changed("owned","first")
	checks.all_owned_observers_released = world._pending_sources.size()==observer_count
	var finance: FinanceService = f.s.services.finance
	checks.base_operating_rate = finance.operating_rate(world)==800
	var placed: bool = builder._place(f,"indexed_seat","FUR01",[42,80])
	checks.formal_build_rate = placed and finance.operating_rate(world)==960 and finance.operating_rate(world)==960
	var stored: CommandResult = builder._command(f,"build_store",{"target_id":"indexed_seat"})
	checks.formal_inventory_rate = stored.accepted and finance.operating_rate(world)==800
	var ordered: CommandResult = builder._command(f,"renovation_order",{"material_id":"MAT01","floor_id":1,"units":[{"cell":[44,80]}],"allow_waiting":true})
	if not ordered.accepted:
		_dispose(builder)
		return {"ok":false,"details":{"setup":ordered.reason,"checks":checks}}
	var order_id: String = ordered.changed_ids[0]
	checks.active_order = world.active_operation_ids("environment","orders",["completed","cancelled"])==[order_id]
	var sorted_ids: Array = world.active_operation_ids("environment","orders",["completed","cancelled"],true)
	sorted_ids.clear()
	var unsorted_ids: Array = world.active_operation_ids("environment","orders",["completed","cancelled"])
	unsorted_ids.append("caller_only")
	checks.active_return_isolation = world.active_operation_ids("environment","orders",["completed","cancelled"],true)==[order_id] and world.active_operation_ids("environment","orders",["completed","cancelled"])==[order_id]
	var unit_id: String = world.facts.environment.orders[order_id].units[0].id
	HospitalLedger.post(world,LedgerEntry.new(unit_id,"owner_boundary",0),false)
	var owned: Array = world.ledger_owner_ids([unit_id])
	checks.ledger_owner = owned==[unit_id+":owner_boundary"] and not world.facts.ledger.entries[owned[0]].settled
	HospitalLedger.settle(world)
	checks.settlement_live = world.facts.ledger.entries[owned[0]].settled
	var valid: String = world.validate(content)
	checks.known_unit_owner = valid.is_empty()
	var corrupt: WorldState = WorldState.new(world.freeze())
	corrupt.facts.ledger.entries["absent_unit:bad"] = {"owner_id":"absent_unit","component":"bad","amount":0,"settled":true,"tick":world.sim_tick}
	checks.unknown_owner_rejected = not corrupt.validate(content).is_empty()
	var cancelled: CommandResult = builder._command(f,"renovation_cancel",{"order_id":order_id})
	checks.terminal_retained = cancelled.accepted and world.active_operation_ids("environment","orders",["completed","cancelled"]).is_empty() and world.facts.environment.orders.has(order_id)
	var restored_f: Dictionary = builder._restore(f)
	checks.terminal_restore = restored_f.w.active_operation_ids("environment","orders",["completed","cancelled"]).is_empty() and restored_f.w.ledger_owner_ids([unit_id])==owned and restored_f.s.services.finance.operating_rate(restored_f.w)==800
	var chairs: bool = builder._place(f,"remodel_seat_a","FUR01",[46,80]) and builder._place(f,"remodel_seat_b","FUR01",[50,80])
	var first: CommandResult = builder._command(f,"remodel_prepare",{"commands":[{"kind":"build_move","target_id":"remodel_seat_a","floor_id":1,"cell":[46,84]}]})
	var second: CommandResult = builder._command(f,"remodel_prepare",{"commands":[{"kind":"build_move","target_id":"remodel_seat_b","floor_id":1,"cell":[50,84]}]})
	checks.remodel_setup = chairs and first.accepted and second.accepted
	if checks.remodel_setup:
		var first_id: String = first.changed_ids[0]
		var second_id: String = second.changed_ids[0]
		builder._staff(f,"target_observer","cleaner",[46,84])
		var boundary: Dictionary = world.freeze()
		var waiting: Dictionary = f.s.services.remodel.waiting_all(world)
		checks.live_waiting_batch = waiting[first_id]=="等待实际人员走出源布局和目标范围" and waiting[second_id]=="" and world.freeze()==boundary
		checks.preparing_members = HospitalRemodel.blocked(world,"remodel_seat_a") and HospitalRemodel.blocked(world,"remodel_seat_b")
		var release: CommandResult = builder._command(f,"remodel_cancel",{"order_id":first_id})
		checks.cancel_invalidates_members = release.accepted and not HospitalRemodel.blocked(world,"remodel_seat_a") and HospitalRemodel.blocked(world,"remodel_seat_b") and world.facts.remodels.has(first_id)
	_dispose(builder)
	return {"ok":not checks.values().has(false),"details":{"checks":checks,"validation":valid,"elapsed_including_fixture_us":Time.get_ticks_usec()-started}}

func run_routes(content: HospitalContent) -> Dictionary:
	var builder: RefCounted = _builder(content)
	var f: Dictionary = builder._new("真实动态路线公共前缀")
	builder._staff(f,"route_cleaner","cleaner",[40,80])
	builder._staff(f,"route_other","cleaner",[38,78])
	builder._staff(f,"route_blocker","cleaner",[56,90])
	f.w.facts.actors.route_blocker.location.floor_id = 2
	f.w.facts.floors.overrides["2"] = {"plots":[[1,2]],"blocked":[],"doors":[],"paths":[]}
	f.w.facts.floors.completed_top_floor[HospitalSpace.plot_key([1,2])] = 2
	f.w.facts.floors.height_intervals.append({"first":2,"last":2,"height_m":float(content.balance.floors.clear_height_m)})
	f.w.facts.connectors.query_lift = {"id":"query_lift","definition_id":"VC02","first_floor":1,"last_floor":2,"cell":[50,82],"footprint":[4,4],"rotation":0,"anchor":[51,86],"repair_cell":[49,83],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0,"ticket_next":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},"paid_cost":3200,"used":false}
	var base: Dictionary = f.w.freeze()
	var results: Array = []
	var passed: bool = true
	var reduction: bool = false
	for condition: String in ["clear","egress_occupied","reservation","authorized","fractional","other_actor"]:
		var world: WorldState = WorldState.new(base.duplicate(true))
		if condition=="egress_occupied": world.facts.actors.route_blocker.location.cell = [51,86]
		if condition=="fractional": world.facts.actors.route_cleaner.location.cell = [40.25,80.0]
		if condition in ["reservation","authorized"]:
			# A legal reservation boundary, not fabricated movement or work.
			HospitalFactory._add_facility(world,{"id":"query_support","definition_id":"FUR01","anchor":[55,81],"size":content.facility_definition("FUR01").footprint,"room_id":null},content)
			var facility: Dictionary = world.facts.facilities.query_support
			facility.floor_id = 2
			world.facts.adaptations.query_support = {"kind":"facility","facility_id":"query_support","owner_id":"route_blocker","actor_id":"route_blocker","staff_ids":["route_cleaner"] if condition=="authorized" else [],"floor_id":2,"regions":[[55,81,3,3]],"footprint":facility.footprint.duplicate(),"patient_cell":facility.patient_cell.duplicate(),"operator_cells":facility.operator_cells.duplicate(true),"repair_cell":facility.repair_cell.duplicate()}
		var input: Dictionary = world.freeze()
		var actual: HospitalSpace = HospitalSpace.new(content)
		var control: HospitalSpace = FullReservationSpace.new(content)
		var quotes: Array = []
		var expected: Array = []
		var actual_us: int = 0
		var control_us: int = 0
		var scope_started: int = Time.get_ticks_usec()
		actual.begin_dynamic_route_query(world)
		var scope_build_us: int = Time.get_ticks_usec()-scope_started
		for goal: Array in [[40,80],[41,80],[40,80],[42,80]]:
			var id: String = "route_other" if condition=="other_actor" and goal==[42,80] else "route_cleaner"
			var query_started: int = Time.get_ticks_usec()
			# Public entry/fit helpers nest actual queries inside one actor's
			# sealed enumeration. These must preserve current body permissions.
			actual.begin_route_query(world,{},false)
			quotes.append(actual.route(world,id,2,goal))
			actual.end_route_query()
			actual_us += Time.get_ticks_usec()-query_started
			query_started = Time.get_ticks_usec()
			expected.append(control.route(world,id,2,goal))
			control_us += Time.get_ticks_usec()-query_started
		var rect: Rect2 = Rect2(55.25,81.25,0.25,0.25)
		var dynamic: bool = actual._dynamic_clear(world,"route_cleaner",2,rect)
		var full_dynamic: bool = control._dynamic_clear(world,"route_cleaner",2,rect)
		var sweeps_equal: bool = true
		if condition in ["reservation","authorized"]:
			var sweep: BodyIndex.Record = BodyIndex.Record.new()
			sweep.id = "route_cleaner"
			sweep.sweep_from = Rect2(54,82,1,1)
			sweep.sweep_to = Rect2(58,82,1,1)
			var sweeps: Array[BodyIndex.Record] = [sweep]
			var broad: Rect2 = sweep.sweep_from.merge(sweep.sweep_to)
			var actual_motion: HospitalMovement.MotionResult = HospitalMovement.MotionResult.new()
			var full_motion: HospitalMovement.MotionResult = HospitalMovement.MotionResult.new()
			actual.movement._movement_contacts(world,"route_cleaner",2,broad,sweeps,["route_cleaner"],actual_motion)
			control.movement._movement_contacts(world,"route_cleaner",2,broad,sweeps,["route_cleaner"],full_motion)
			var actual_sweep: bool = not actual_motion.blocked
			var full_sweep: bool = not full_motion.blocked
			sweeps_equal = actual_sweep==full_sweep and actual_sweep==(condition=="authorized")
			sweep.sweep_from = Rect2(54,80,1,1)
			sweep.sweep_to = Rect2(58,80,1,1)
			broad = sweep.sweep_from.merge(sweep.sweep_to)
			actual_motion = HospitalMovement.MotionResult.new()
			full_motion = HospitalMovement.MotionResult.new()
			actual.movement._movement_contacts(world,"route_cleaner",2,broad,sweeps,["route_cleaner"],actual_motion)
			control.movement._movement_contacts(world,"route_cleaner",2,broad,sweeps,["route_cleaner"],full_motion)
			sweeps_equal = sweeps_equal and not actual_motion.blocked and not full_motion.blocked
		actual.end_route_query()
		var actual_counts: Dictionary = actual.query_counts.duplicate()
		var control_counts: Dictionary = control.query_counts.duplicate()
		var equal: bool = quotes==expected and dynamic==full_dynamic and sweeps_equal and world.freeze()==input and actual._route_queries.is_empty()
		if condition=="clear":
			reduction = int(actual.query_counts.floor_route_hits)>0 and int(actual.query_counts.floor_route_builds)<int(control.query_counts.floor_route_builds)
			equal = equal and bool(quotes[0].get("ok",false))
		if condition=="egress_occupied":
			# Structural journeys may depart toward a busy landing. The real
			# arrival still cannot overlap the person currently blocking it.
			var landing: Vector2i = Vector2i(51,86)
			equal = equal and bool(quotes[0].get("ok",false)) and not actual._unit_step_dynamic_clear(world,world.facts.actors.route_cleaner,2,landing,landing,[],{})
		if condition in ["reservation","authorized"]: equal = equal and dynamic==(condition=="authorized")
		# The next batch must observe an actual new blocker, even without a tick.
		world.facts.actors.route_blocker.location.cell = [51,86]
		actual.begin_dynamic_route_query(world)
		var changed: Dictionary = actual.route(world,"route_cleaner",2,[40,80])
		actual.end_route_query()
		var fresh: Dictionary = HospitalSpace.new(content).route(world,"route_cleaner",2,[40,80])
		equal = equal and changed==fresh
		passed = passed and equal
		results.append({"condition":condition,"equal":equal,"route_queries":quotes.size(),"actual_scope_build_us":scope_build_us,"actual_query_us":actual_us,"actual_total_query_us":actual_us+scope_build_us,"control_query_us":control_us,"actual_counts":actual_counts,"control_counts":control_counts})
	_dispose(builder)
	return {"ok":passed and reduction,"details":{"variants":results,"dynamic_leg_computations_reduced":reduction,"complete_route_and_facts_rng_equal":passed}}

func run_spawns(content: HospitalContent) -> Dictionary:
	var builder: RefCounted = _builder(content)
	var f: Dictionary = builder._new("地污来源完整占用边界")
	var placed: bool = builder._place(f,"ground_chair","FUR01",[42,80]) and builder._place(f,"ground_bin","FUR18",[50,80])
	var environment: HospitalEnvironment = f.s.services.environment
	var before: Dictionary = f.w.freeze()
	var checked: int = 0
	var equal: bool = placed
	var started: int = Time.get_ticks_usec()
	var view: Dictionary = environment._ground_spawn_view(f.w,1)
	var view_build_us: int = Time.get_ticks_usec()-started
	var indexed_us: int = 0
	var full_us: int = 0
	for x: int in range(38,55):
		for y: int in range(76,87):
			started = Time.get_ticks_usec()
			var indexed: bool = environment._ground_spawn_legal(f.w,1,[x,y],view)
			indexed_us += Time.get_ticks_usec()-started
			started = Time.get_ticks_usec()
			var full: bool = _ground_full(f.w,f.s.space,1,[x,y])
			full_us += Time.get_ticks_usec()-started
			equal = equal and indexed==full
			checked += 1
	equal = equal and f.w.freeze()==before
	var candidates: Array = []
	for x: int in range(38,47):
		for y: int in range(76,85):
			if _ground_full(f.w,f.s.space,1,[x,y]): candidates.append({"cell":[x,y],"distance":absi(x-42)+absi(y-80)})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.distance<b.distance if a.distance!=b.distance else (a.cell[0]<b.cell[0] if a.cell[0]!=b.cell[0] else a.cell[1]<b.cell[1]))
	var id: String = environment.spawn_dirt(f.w,"CL01","ground_source","ground_source:scatter",1,[42,80])
	equal = equal and not id.is_empty() and not candidates.is_empty() and f.w.facts.environment.dirt[id].cell==candidates[0].cell
	var duplicate: String = environment.spawn_dirt(f.w,"CL01","ground_source","ground_source:scatter",1,[42,80])
	equal = equal and duplicate==id and f.w.facts.environment.dirt.size()==1
	_dispose(builder)
	return {"ok":equal,"details":{"checked_cells":checked,"view_build_us":view_build_us,"indexed_cell_query_us":indexed_us,"full_cell_query_us":full_us,"full_occupancy_and_nearest_tie_order_equal":equal}}

func _ground_full(world: WorldState, space: HospitalSpace, floor_id: int, cell: Array) -> bool:
	if not space.owned(world,floor_id,Vector2i(int(cell[0]),int(cell[1]))): return false
	var floor_data: Dictionary = world.facts.floors.overrides.get(str(floor_id),{})
	if cell in floor_data.get("blocked",[]): return false
	for door: Dictionary in floor_data.get("doors",[]):
		if door.cell==cell: return false
	for patch: Dictionary in world.facts.environment.dirt.values():
		if int(patch.floor_id)==floor_id and patch.bin_id.is_empty() and patch.cell==cell: return false
	for facility: Dictionary in world.facts.facilities.values():
		if int(facility.get("floor_id",-1))!=floor_id or facility.get("location","floor")=="inventory": continue
		var rect: Rect2 = Rect2(float(facility.cell[0]),float(facility.cell[1]),float(facility.footprint[0]),float(facility.footprint[1]))
		if rect.has_point(Vector2(float(cell[0]),float(cell[1]))) or cell in facility.get("operator_cells",[]) or cell==facility.get("patient_cell",[]) or cell==facility.get("repair_cell",[]): return false
	for reservation: Dictionary in world.facts.adaptations.values():
		if int(reservation.get("floor_id",-1))==floor_id and cell in reservation.get("occupied_cells",[]): return false
	return true
