extends "res://tests/acceptance/public_area_use.gd"

class IndexProbe extends HospitalSpace:
	var exclusion_ids: Array = []
	var exclusion_calls: int = 0
	var projection_actor_visits: int = 0
	var source: WorldState
	func begin_actor_exclusion_query(owner: WorldState, projected: WorldState, ids: Array) -> void:
		exclusion_calls += 1
		exclusion_ids = ids.duplicate()
		super.begin_actor_exclusion_query(owner,projected,ids)
	func _sync_actor(world: WorldState, id: String, notify: bool = true) -> void:
		if source!=null and world!=source: projection_actor_visits += 1
		super._sync_actor(world,id,notify)

# Complete pre-change 5b87657 method. The fixture compares its actual dynamic
# checks, routes, failure reasons and typed result with the departure adapter.
class OriginalWaiting extends HospitalWaitingLife:
	func _manual_seat_quote(world: WorldState, visit: Dictionary, facility_id: String) -> Dictionary:
		if not world.facts.facilities.has(facility_id) or not _public_seat(world,world.facts.facilities[facility_id]): return {"ok":false,"reason":"目标不是实际公共候诊座位"}
		if not _occupied(world,facility_id,visit.actor_id): return _seat_target_quote(world,visit,facility_id)
		var facts: Dictionary = world.facts.duplicate()
		facts.actors = world.facts.actors.duplicate()
		facts.waiting_life = world.facts.waiting_life.duplicate()
		facts.waiting_life.seats = world.facts.waiting_life.seats.duplicate()
		facts.staff_life = world.facts.staff_life.duplicate()
		facts.staff_life.reservations = world.facts.staff_life.reservations.duplicate()
		facts.adaptations = world.facts.adaptations.duplicate()
		var candidate: WorldState = WorldState.new(facts)
		for id: String in candidate.facts.actors:
			var actor: Dictionary = candidate.facts.actors[id]
			if actor.get("support_facility_id","")==facility_id:
				actor = actor.duplicate(true)
				candidate.facts.actors[id] = actor
				actor.location = {"kind":"outside"}
				actor.erase("support_facility_id")
		for id: String in candidate.facts.waiting_life.seats:
			var seat: Dictionary = candidate.facts.waiting_life.seats[id]
			if seat.get("facility_id","")==facility_id:
				seat = seat.duplicate(true)
				candidate.facts.waiting_life.seats[id] = seat
				candidate.facts.actors[seat.actor_id] = candidate.facts.actors[seat.actor_id].duplicate(true)
				candidate.facts.actors[seat.actor_id].location = {"kind":"outside"}
				seat.facility_id = ""
		candidate.facts.staff_life.reservations.erase(facility_id)
		candidate.facts.adaptations.erase(facility_id)
		space.prepare_projection(world,candidate,[facility_id])
		return _seat_target_quote(candidate,visit,facility_id)

func _departure_fixture(kind: String = "both") -> Dictionary:
	var x: Dictionary = _areas()
	x.holder = _visit(x,"departure_holder",x.space.facility_layout(x.world,"west_chair").patient_cell)
	x.peer = _visit(x,"departure_peer",[42,74])
	x.obstacle = _visit(x,"departure_obstacle",[60,90])
	x.held = _seat_checkpoint(x,x.holder,"west_chair")
	if kind=="support": x.world.facts.waiting_life.seats.erase(x.holder.id)
	elif kind=="seat":
		# Retain the actual seated posture and position; isolate the seat-owned
		# identity independently of the actor's optional support reference.
		x.world.facts.actors[x.holder.actor_id].erase("support_facility_id")
	x.actual = IndexProbe.new(_content)
	x.original = IndexProbe.new(_content)
	x.actual.source = x.world
	x.original.source = x.world
	x.actual_life = HospitalWaitingLife.new(_content,x.actual)
	x.original_life = OriginalWaiting.new(_content,x.original)
	x.validation = x.world.validate(_content)
	return x

func _dispose_departure(x: Dictionary) -> void:
	x.a.dispose()
	x.p.waiting_life = null
	x.p.environment = null
	x.l.environment = null
	x.l.visitors = null
	x.c.recruitment = null
	x.actual.source = null
	x.original.source = null
	x.clear()

func _observe_departure(x: Dictionary, label: String, scoped: bool, expected: bool, count_reuse: bool = false) -> Dictionary:
	var before: Dictionary = x.world.freeze()
	if scoped:
		x.actual.begin_dynamic_route_query(x.world)
		x.original.begin_dynamic_route_query(x.world)
	else:
		x.actual._ensure_actor_index(x.world)
		x.original._ensure_actor_index(x.world)
	var actual_builds: int = int(x.actual.query_counts.actor_index_builds)
	var original_builds: int = int(x.original.query_counts.actor_index_builds)
	var actual_visits: int = x.actual.projection_actor_visits
	var original_visits: int = x.original.projection_actor_visits
	var exclusions: int = x.actual.exclusion_calls
	var actual: Dictionary = x.actual_life._manual_seat_quote(x.world,x.peer,"west_chair")
	var original: Dictionary = x.original_life._manual_seat_quote(x.world,x.peer,"west_chair")
	var complete: bool = var_to_bytes(actual)==var_to_bytes(original)
	var source_retained: bool = x.actual._indexed_world==x.world
	var exact_departures: bool = x.actual.exclusion_calls==exclusions+1 and x.actual.exclusion_ids==[x.holder.actor_id]
	x.actual._ensure_actor_index(x.world)
	x.original._ensure_actor_index(x.world)
	var actual_delta: int = int(x.actual.query_counts.actor_index_builds)-actual_builds
	var original_delta: int = int(x.original.query_counts.actor_index_builds)-original_builds
	if scoped:
		x.actual.end_route_query()
		x.original.end_route_query()
	var projection_visits: int = x.actual.projection_actor_visits-actual_visits
	var original_projection_visits: int = x.original.projection_actor_visits-original_visits
	var queries_closed: bool = x.actual._route_queries.is_empty() and x.original._route_queries.is_empty() and x.actual._indexed_actor_scope.is_empty()
	var reuse: bool = not count_reuse or (actual_delta==(0 if scoped else 1) and original_delta>=2 and projection_visits==0 and original_projection_visits==x.world.facts.actors.size())
	return {"ok":complete and bool(actual.get("ok",false))==expected and before==x.world.freeze() and source_retained and exact_departures and queries_closed and reuse,"label":label,"complete_typed_quote_equal":complete,"expected_ok":expected,"actual":actual,"original":original if not complete else {},"facts_rng_and_positions_unchanged":before==x.world.freeze(),"only_declared_former_user_excluded_once":exact_departures,"original_body_index_retained":source_retained,"actual_index_builds":actual_delta,"reference_index_builds":original_delta,"actual_projection_actor_visits":projection_visits,"reference_projection_actor_visits":original_projection_visits,"all_query_scopes_closed":queries_closed,"count_contract":reuse}

func _source_cases() -> Array:
	var rows: Array = []
	for kind: String in ["both","support","seat"]:
		var x: Dictionary = _departure_fixture(kind)
		var raw: Dictionary = _observe_departure(x,"raw_"+kind,false,true,true)
		var batch: Dictionary = _observe_departure(x,"sealed_"+kind,true,true,true)
		var repeated: Dictionary = _observe_departure(x,"next_independent_batch_"+kind,true,true,true)
		rows.append({"ok":x.held and x.validation.is_empty() and raw.ok and batch.ok and repeated.ok,"source":kind,"held":x.held,"validation":x.validation,"raw":raw,"batch":batch,"repeated":repeated})
		_dispose_departure(x)
	return rows

func _move_departure_input(x: Dictionary, id: String, cell: Array) -> void:
	x.world.facts.actors[id].location = {"kind":"floor","floor_id":1,"cell":cell.duplicate(),"height_m":0.0}
	x.actual.sync_actor(x.world,id)
	x.original.sync_actor(x.world,id)

func _notify_reservation(x: Dictionary, id: String) -> void:
	for geometry: HospitalSpace in [x.actual,x.original]:
		geometry.reservation_changed(x.world,id)
		geometry._navigation.invalidate(x.world,1)

func _dynamic_boundaries() -> Dictionary:
	var x: Dictionary = _departure_fixture()
	var rows: Array = []
	var repair: Array = x.actual.facility_layout(x.world,"west_chair").repair_cell
	_move_departure_input(x,x.obstacle.actor_id,repair)
	rows.append(_observe_departure(x,"unrelated_actual_body_still_blocks",true,false))
	_move_departure_input(x,x.obstacle.actor_id,[60,90])
	rows.append(_observe_departure(x,"unrelated_body_departure_recovers",true,true))
	# Only the selected facility's reservation is removed in the projection.
	# A neighboring real owner's overlapping work place retains its permissions.
	_facility(x,"departure_neighbor","FUR09",[35,67],"west")
	x.world.touch()
	x.actual.grant_facility_access(x.world,"west_chair",x.obstacle.actor_id)
	x.original._navigation.invalidate(x.world,1)
	var reserved: String = x.actual.reserve_facility(x.world,"departure_neighbor",x.obstacle.actor_id,x.obstacle.actor_id)
	_notify_reservation(x,"departure_neighbor")
	rows.append(_observe_departure(x,"unrelated_reservation_still_blocks",true,false))
	x.actual.grant_facility_access(x.world,"departure_neighbor",x.peer.actor_id)
	x.original._navigation.invalidate(x.world,1)
	rows.append(_observe_departure(x,"explicit_current_permission_allows",true,true))
	var access: Dictionary = x.world.facts.adaptations.get("departure_neighbor",{})
	if not access.is_empty(): access.staff_ids.erase(x.peer.actor_id)
	_notify_reservation(x,"departure_neighbor")
	rows.append(_observe_departure(x,"revoked_permission_blocks_again",true,false))
	x.actual.release_adaptations(x.world)
	_notify_reservation(x,"departure_neighbor")
	rows.append(_observe_departure(x,"real_reservation_release_recovers",true,true))
	var result: Dictionary = {"ok":x.held and x.validation.is_empty() and reserved.is_empty() and rows.all(func(row: Dictionary)->bool: return row.ok),"validation":x.validation,"neighbor_reservation":reserved,"boundaries":rows}
	_dispose_departure(x)
	return result

func _unannounced_and_commit() -> Dictionary:
	var x: Dictionary = _departure_fixture()
	var repair: Array = x.actual.facility_layout(x.world,"west_chair").repair_cell
	var prepared: Dictionary = _observe_departure(x,"initial_complete_quote",true,true)
	# An independent raw query may follow unannounced input edits at the same
	# revision. Its original source refresh must remain a real force operation.
	x.world.facts.actors[x.obstacle.actor_id].location.cell = repair.duplicate()
	var unannounced: Dictionary = _observe_departure(x,"raw_unannounced_body_change",false,false)
	_move_departure_input(x,x.obstacle.actor_id,[60,90])
	var before: Dictionary = x.world.freeze()
	var refusal: String = x.actual.reserve_facility(x.world,"west_chair",x.peer.actor_id,x.peer.actor_id)
	var no_premature_claim: bool = not refusal.is_empty() and before==x.world.freeze()
	var closed: bool = x.actual._route_queries.is_empty()
	# A real release invalidates live ownership. The following read is a new
	# independent batch, without retaining the preceding quote's scope or view.
	x.l._release_seat(x.world,x.holder.id)
	_move_departure_input(x,x.holder.actor_id,[40,74])
	x.actual.release_adaptations(x.world)
	_notify_reservation(x,"west_chair")
	x.actual.begin_dynamic_route_query(x.world)
	x.original.begin_dynamic_route_query(x.world)
	var current: Dictionary = x.actual_life._manual_seat_quote(x.world,x.peer,"west_chair")
	var original: Dictionary = x.original_life._manual_seat_quote(x.world,x.peer,"west_chair")
	x.actual.end_route_query()
	x.original.end_route_query()
	var result: Dictionary = {"ok":x.held and x.validation.is_empty() and prepared.ok and unannounced.ok and no_premature_claim and closed and current.get("ok",false) and var_to_bytes(current)==var_to_bytes(original) and x.actual._route_queries.is_empty(),"validation":x.validation,"prepared":prepared,"unannounced_body_change":unannounced,"occupied_facility_rejects_real_claim":no_premature_claim,"closed_before_real_commit":closed,"after_release_complete_quote_equal":var_to_bytes(current)==var_to_bytes(original),"new_quote":current}
	_dispose_departure(x)
	return result

func _historical_motion() -> Dictionary:
	var x: Dictionary = _departure_fixture()
	var repair: Array = x.actual.facility_layout(x.world,"west_chair").repair_cell
	x.actual.grant_facility_access(x.world,"west_chair",x.obstacle.actor_id)
	x.original._navigation.invalidate(x.world,1)
	_move_departure_input(x,x.obstacle.actor_id,[float(repair[0]),float(repair[1])+0.6])
	var request: String = x.actual.request_move(x.world,x.obstacle.actor_id,1,[repair[0],int(repair[1])+1])
	var initial: Array = x.world.facts.actors[x.obstacle.actor_id].location.cell.duplicate()
	var movement_service: HospitalMovement = x.actual.movement
	movement_service._sweep_index.begin_boundary(x.world.facts.actors)
	movement_service._accepted_sweeps.clear()
	movement_service._phase_owners.clear()
	x.actual._ensure_actor_index(x.world)
	movement_service._dispatch_routes(x.world,x.world.present_actor_count())
	var movement: Dictionary = x.world.facts.moves.get(x.obstacle.actor_id,{})
	var accepted: bool = false
	if not movement.is_empty() and not movement.get("route_pending",false) and not movement.path.is_empty():
		movement.cursor = movement_service._initial_route_cursor(x.world.facts.actors[x.obstacle.actor_id],movement.path)
		var motion: HospitalMovement.MotionResult = movement_service._move_step(x.world,x.world.facts.actors[x.obstacle.actor_id],movement,movement.path[int(movement.cursor)])
		accepted = not motion.blocked and motion.actual_motion.length()>0.0 and motion.actual_motion.length()<=0.2001
	# Both solvers observe the identical real accepted motion history. No body
	# or sweep is fabricated, and the production solver still owns the movement.
	x.original.movement._sweep_index = movement_service._sweep_index
	var region: Rect2 = Rect2(float(repair[0]),float(repair[1]),1.0,1.0)
	var clear_now: bool = not x.actual.body_rectangle(x.world.facts.actors[x.obstacle.actor_id]).intersects(region,false)
	var blocks: bool = movement_service._sweep_index.intersects(1,region,x.peer.actor_id,[x.peer.actor_id])
	var blocked: Dictionary = _observe_departure(x,"real_accepted_history_still_blocks",true,false)
	movement_service._accepted_sweeps.clear()
	movement_service._sweep_index.expire_boundary()
	var recovered: Dictionary = _observe_departure(x,"history_expires_at_boundary",true,true)
	var result: Dictionary = {"ok":x.held and x.validation.is_empty() and request.is_empty() and accepted and initial!=x.world.facts.actors[x.obstacle.actor_id].location.cell and clear_now and blocks and blocked.ok and recovered.ok,"validation":x.validation,"request":request,"real_substep_accepted":accepted,"current_body_clear":clear_now,"historical_sweep_intersects":blocks,"blocked":blocked,"recovered":recovered}
	_dispose_departure(x)
	return result

func run_case(suite: RefCounted) -> Dictionary:
	_content = suite.content
	var sources: Array = _source_cases()
	var dynamic: Dictionary = _dynamic_boundaries()
	var commit: Dictionary = _unannounced_and_commit()
	var history: Dictionary = _historical_motion()
	return {"ok":sources.all(func(row: Dictionary)->bool: return row.ok) and dynamic.ok and commit.ok and history.ok,"independent_complete_original_method":sources,"actual_dynamic_checks":dynamic,"raw_input_and_real_commit":commit,"actual_movement_history":history}
