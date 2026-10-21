extends RefCounted

# Observe real projection work. The comparison entry bypasses only the retained
# qualification; both sides execute the original production fit solver.
class QueueFitProbe extends HospitalPublicAreas:
	var projections: int = 0
	func _queue_fit_in_query(world: WorldState, facility_id: String, ids: Array) -> Dictionary:
		projections += 1
		return super._queue_fit_in_query(world,facility_id,ids)
	func uncached_fit(world: WorldState, facility_id: String, ids: Array) -> Dictionary:
		return super._queue_fit_in_query(world,facility_id,ids)

class ReservationProbe extends HospitalSpace:
	var complete_quotes: int = 0
	func facility_quote(world: WorldState, facility_id: String, actor_id: String, staff_ids: Array = []) -> Dictionary:
		complete_quotes += 1
		return super.facility_quote(world,facility_id,actor_id,staff_ids)

func run_case(suite: RefCounted) -> Dictionary:
	var batch: Dictionary = _observer_batch(suite)
	var boundaries: Dictionary = _dependency_boundaries(suite)
	return {"ok":batch.ok and boundaries.ok,"independent_observer_scopes":batch,"current_qualification_dependencies":boundaries,"scope":"Qualification calculations begin with legal arrived/occupied inputs. Only the explicitly recorded remote and sweep movement is executed; no arrival or use completion is inferred from prepared positions."}

func _fixture(suite: RefCounted, count: int) -> Dictionary:
	var x: Dictionary = suite._fixture()
	var room: String = suite._room(x,"waiting")
	x.chairs = []
	x.holders = []
	x.held = true
	for index: int in count:
		var id: String = "qualification_chair_%02d"%index
		suite._facility(x,id,"FUR09",[38+(index%4)*5,70+(index/4)*6],room)
		x.chairs.append(id)
	# Its patient place shares only the first chair's repair place, not either
	# built footprint. This permits an independent real reservation boundary.
	suite._facility(x,"qualification_neighbor","FUR09",[37,69],room)
	x.world.touch()
	for id: String in x.chairs:
		var holder: Dictionary = suite._visit(x,"holder_"+id,x.space.facility_layout(x.world,id).patient_cell)
		x.held = suite._seat_checkpoint(x,holder,id) and x.held
		x.holders.append(holder)
	x.earlier = suite._visit(x,"qualification_earlier",[46,84])
	x.peer = suite._visit(x,"qualification_peer",[53,84])
	x.obstacle = suite._visit(x,"qualification_obstacle",[58,86])
	x.world.facts.sim_tick = 100
	var geometry: ReservationProbe = ReservationProbe.new(suite._content)
	x.space = geometry
	x.probe = QueueFitProbe.new(geometry)
	geometry.public_areas = x.probe
	x.area = geometry.public_areas.for_facility(x.world,str(x.chairs[0]))
	_put_intent(x,x.earlier,1)
	x.validation = x.world.validate(suite._content)
	return x

func _put_intent(x: Dictionary, visit: Dictionary, arrived: int) -> Dictionary:
	var intent: Dictionary = {"id":"seat_"+str(visit.id),"actor_id":visit.actor_id,"ticket_id":visit.ticket_id,"facility_id":"","public_purpose":"seat","mode":"auto","area":x.area.duplicate(true),"phase":"local_wait","continuous_ticks":0,"arrived_tick":arrived,"started_tick":0,"area_travel_ticks":0}
	x.world.facts.waiting_life.seats[visit.id] = intent
	x.space.public_areas.changed(x.world)
	x.world.touch(false)
	return intent

func _observer_batch(suite: RefCounted) -> Dictionary:
	var x: Dictionary = _fixture(suite,8)
	if not x.held:
		var failed: Dictionary = {"ok":false,"holders_reserved":false,"validation":x.validation}
		_close_fixture(x)
		return failed
	var blocked: bool = true
	var readonly: bool = true
	var original_solver: bool = true
	var rows: Array = []
	for index: int in 17:
		# Each observer is really present in the same region. Creating its intent
		# happens outside both the preceding and following read-only scope.
		var later: Dictionary = suite._visit(x,"qualification_later_%02d"%index,[36+(index%8)*3,81+(index/8)*3])
		var intent: Dictionary = _put_intent(x,later,index+2)
		var before: Dictionary = x.world.freeze()
		var count_before: int = x.probe.projections
		x.space.begin_route_query(x.world,{},false)
		for id: String in x.chairs:
			blocked = not x.probe.turn(x.world,intent,id) and blocked
			var actual: Dictionary = x.probe._queue_fit(x.world,id,[x.earlier.actor_id])
			original_solver = actual==x.probe.uncached_fit(x.world,id,[x.earlier.actor_id]) and original_solver
		x.space.end_route_query()
		readonly = before==x.world.freeze() and readonly
		rows.append({"observer":later.actor_id,"new_projections":x.probe.projections-count_before})
	var only_eight: bool = x.probe.projections==8
	var batch_projections: int = x.probe.projections
	var additional: Dictionary = suite._visit(x,"qualification_additional",[58,87])
	_put_intent(x,additional,30)
	var additional_queue: Dictionary = _observe(x,"additional_queue",str(x.chairs[0]),[x.earlier.actor_id],0,true)
	var remote: Dictionary = suite._visit(x,"qualification_remote",[61,92])
	x.space.sync_actor(x.world,remote.actor_id)
	var request: String = x.space.request_move(x.world,remote.actor_id,1,[61,94])
	var origin: Array = x.world.facts.actors[remote.actor_id].location.cell.duplicate()
	for _tick: int in 30:
		if x.space.at(x.world,remote.actor_id,1,[61,94]): break
		x.world.facts.sim_tick += 1
		x.space.advance(x.world)
		x.world.touch(false)
	var moved: bool = x.world.facts.actors[remote.actor_id].location.cell!=origin and x.space.at(x.world,remote.actor_id,1,[61,94])
	var remote_motion: Dictionary = _observe(x,"remote_actual_motion",str(x.chairs[0]),[x.earlier.actor_id],0,true)
	var result: Dictionary = {"ok":x.validation.is_empty() and blocked and readonly and original_solver and only_eight and additional_queue.ok and request.is_empty() and moved and remote_motion.ok and x.space._route_queries.is_empty(),"validation":x.validation,"all_136_turns_preserve_earlier_waiter":blocked,"full_quotes_match_forced_original_solver":original_solver,"queries_leave_facts_and_rng_unchanged":readonly,"projections_for_eight_chairs_seventeen_observers":batch_projections,"observers":rows,"queue_addition":additional_queue,"remote_request":request,"remote_actually_arrived":moved,"remote_movement":remote_motion,"closed_scopes":x.space._route_queries.is_empty()}
	_close_fixture(x)
	return result

func _observe(x: Dictionary, label: String, facility_id: String, ids: Array, expected_builds: int = -1, expected_ok: Variant = null) -> Dictionary:
	var before: Dictionary = x.world.freeze()
	var count_before: int = x.probe.projections
	x.space.begin_route_query(x.world,{},false)
	var actual: Dictionary = x.probe._queue_fit(x.world,facility_id,ids)
	x.space.end_route_query()
	var builds: int = x.probe.projections-count_before
	x.space.begin_route_query(x.world,{},false)
	var expected: Dictionary = x.probe.uncached_fit(x.world,facility_id,ids)
	x.space.end_route_query()
	var readonly: bool = before==x.world.freeze()
	return {"ok":actual==expected and readonly and (expected_builds<0 or builds==expected_builds) and (expected_ok==null or bool(actual.ok)==bool(expected_ok)),"boundary":label,"new_projections":builds,"expected_projections":expected_builds,"available":actual.ok,"expected_available":expected_ok,"full_quote_matches_original_solver":actual==expected,"world_and_rng_unchanged":readonly,"quote":actual}

func _dependency_boundaries(suite: RefCounted) -> Dictionary:
	var x: Dictionary = _fixture(suite,1)
	if not x.held:
		var failed: Dictionary = {"ok":false,"holders_reserved":false,"validation":x.validation}
		_close_fixture(x)
		return failed
	var id: String = str(x.chairs[0])
	var ids: Array = [str(x.earlier.actor_id)]
	var rows: Array = []
	rows.append(_observe(x,"cold",id,ids,1,true))
	rows.append(_observe(x,"warm_independent_scope",id,ids,0,true))
	# Retention is one latest qualification per facility, not actor x facility
	# history. Identical bodies and reversed ordered participants stay distinct.
	rows.append(_observe(x,"same_body_different_identity",id,[x.peer.actor_id],1,true))
	rows.append(_observe(x,"previous_identity_evicted",id,ids,1,true))
	rows.append(_observe(x,"ordered_pair",id,[x.earlier.actor_id,x.peer.actor_id],1,true))
	rows.append(_observe(x,"reversed_pair",id,[x.peer.actor_id,x.earlier.actor_id],1,true))
	rows.append(_observe(x,"previous_pair_evicted",id,[x.earlier.actor_id,x.peer.actor_id],1,true))
	rows.append(_observe(x,"singleton_restored",id,ids,1,true))
	var repair: Array = x.space.facility_layout(x.world,id).repair_cell.duplicate()
	suite._position(x,x.obstacle.actor_id,repair)
	x.world.touch(false)
	rows.append(_observe(x,"actual_body_in_repair_place",id,ids,1,false))
	rows.append(_observe(x,"negative_body_result_not_retained",id,ids,1,false))
	suite._position(x,x.obstacle.actor_id,[58,86])
	x.world.touch(false)
	rows.append(_observe(x,"body_departure_recovers",id,ids,1,true))
	rows.append(_observe(x,"recovered_warm",id,ids,0,true))
	var body_before: Dictionary = x.world.facts.actors[x.earlier.actor_id].duplicate(true)
	var visit_before: Dictionary = x.world.facts.visits[x.earlier.id].duplicate(true)
	var changed_body: bool = _different_body(suite,x,x.earlier)
	rows.append(_observe(x,"incoming_body_changed",id,ids,1))
	x.world.facts.actors[x.earlier.actor_id] = body_before
	x.world.facts.visits[x.earlier.id] = visit_before
	x.space.sync_actor(x.world,x.earlier.actor_id)
	x.world.touch(false)
	rows.append(_observe(x,"incoming_body_restored",id,ids,1,true))
	var sweep: Dictionary = _historical_sweep(suite,x,id,ids,repair)
	var reservations: Dictionary = _reservation_permissions(suite,x,id,ids,repair)
	var current: Dictionary = x.world.facts.adaptations[id]
	var prior_holder: Dictionary = x.holders[0]
	x.world.facts.actors[prior_holder.actor_id].posture = "standing"
	x.world.facts.actors[prior_holder.actor_id].erase("support_facility_id")
	x.world.facts.waiting_life.seats.erase(prior_holder.id)
	suite._position(x,prior_holder.actor_id,[57,83])
	var replacement: Dictionary = suite._visit(x,"qualification_replacement",x.space.facility_layout(x.world,id).patient_cell)
	current.actor_id = replacement.actor_id
	current.owner_id = replacement.actor_id
	current.staff_ids = []
	x.space.reservation_changed(x.world,id)
	var replaced: bool = suite._seat_checkpoint(x,replacement,id)
	x.world.touch(false)
	rows.append(_observe(x,"current_departure_identity_changed",id,ids,1,true))
	x.world.facts.facilities[id].repair_cell = [int(repair[0]),int(repair[1])+1]
	x.world.touch()
	rows.append(_observe(x,"fixed_facility_layout_changed",id,ids,1,true))
	x.world.facts.facilities[id].repair_cell = repair.duplicate()
	x.world.touch()
	rows.append(_observe(x,"fixed_layout_restored",id,ids,1,true))
	x.world.facts.floors.overrides["1"].blocked.append(repair.duplicate())
	x.world.touch()
	rows.append(_observe(x,"static_region_now_blocked",id,ids,1,false))
	x.world.facts.floors.overrides["1"].blocked.erase(repair)
	x.world.touch()
	rows.append(_observe(x,"static_region_restored",id,ids,1,true))
	var actual_commit: Dictionary = _actual_commit(suite,x,id,ids,repair,replacement)
	# Independent raw-input callers preserve their original fresh path.
	var count_before: int = x.probe.projections
	x.probe._queue_fit(x.world,id,ids)
	x.probe._queue_fit(x.world,id,ids)
	var unscoped: bool = x.probe.projections-count_before==2
	var result: Dictionary = {"ok":x.validation.is_empty() and changed_body and replaced and sweep.ok and reservations.ok and actual_commit.ok and unscoped and rows.all(func(row: Dictionary)->bool: return row.ok) and x.space._route_queries.is_empty(),"validation":x.validation,"observations":rows,"incoming_body_really_different":changed_body,"departure_owner_replaced":replaced,"historical_sweep":sweep,"reservation_permissions":reservations,"actual_reservation_rechecks":actual_commit,"two_unscoped_calls_run_original_projection":unscoped,"closed_scopes":x.space._route_queries.is_empty()}
	_close_fixture(x)
	return result

func _close_fixture(x: Dictionary) -> void:
	x.a.dispose()
	x.p.waiting_life = null
	x.p.environment = null
	x.l.environment = null
	x.l.visitors = null
	x.c.recruitment = null
	x.clear()

func _different_body(suite: RefCounted, x: Dictionary, visit: Dictionary) -> bool:
	var actor: Dictionary = x.world.facts.actors[visit.actor_id]
	var before: Dictionary = x.space.body(actor)
	for binding: Dictionary in suite._content.catalog.treatment_bindings:
		if binding.species_id!="S53": continue
		actor.species_id = binding.species_id
		actor.body_binding_id = binding.id
		visit.binding_id = binding.id
		visit.disease_id = binding.disease_id
		visit.requested_plan_id = "P_"+str(binding.disease_id)+"_COMMON"
		x.space.sync_actor(x.world,visit.actor_id)
		x.world.touch(false)
		return before!=x.space.body(actor)
	return false

func _historical_sweep(suite: RefCounted, x: Dictionary, id: String, ids: Array, repair: Array) -> Dictionary:
	# Prepare a legal fractional movement input. The real movement system must
	# accept its 0.2-cell substep; the test never inserts a synthetic sweep.
	# Its real owner grants access before the walker enters that work place.
	# The incoming candidate receives no such access to the historical sweep.
	x.space.grant_facility_access(x.world,id,str(x.obstacle.actor_id))
	var access: Dictionary = _observe(x,"departure_access_changed",id,ids,1,true)
	suite._position(x,x.obstacle.actor_id,[float(repair[0]),float(repair[1])+0.6])
	x.world.touch(false)
	var request: String = x.space.request_move(x.world,x.obstacle.actor_id,1,[repair[0],int(repair[1])+1])
	var original: Array = x.world.facts.actors[x.obstacle.actor_id].location.cell.duplicate()
	x.world.facts.sim_tick += 1
	# Observe the real accepted substep before advance's ordinary end-of-phase
	# cleanup expires its history. No sweep or successful motion is fabricated.
	var movement_service: HospitalMovement = x.space.movement
	movement_service._sweep_index.begin_boundary(x.world.facts.actors)
	movement_service._accepted_sweeps.clear()
	movement_service._phase_owners.clear()
	x.space._ensure_actor_index(x.world)
	movement_service._dispatch_routes(x.world,x.world.present_actor_count())
	var movement: Dictionary = x.world.facts.moves.get(x.obstacle.actor_id,{})
	var accepted: bool = false
	if not movement.is_empty() and not movement.get("route_pending",false) and not movement.path.is_empty():
		movement.cursor = movement_service._initial_route_cursor(x.world.facts.actors[x.obstacle.actor_id],movement.path)
		var result: HospitalMovement.MotionResult = movement_service._move_step(x.world,x.world.facts.actors[x.obstacle.actor_id],movement,movement.path[int(movement.cursor)])
		accepted = not result.blocked and result.actual_motion.length()>0.0 and result.actual_motion.length()<=0.2001
	x.world.touch(false)
	var region: Rect2 = Rect2(float(repair[0]),float(repair[1]),1.0,1.0)
	var now_clear: bool = not x.space.body_rectangle(x.world.facts.actors[x.obstacle.actor_id]).intersects(region,false)
	var history_blocks: bool = x.space.movement._sweep_index.intersects(1,region,str(ids[0]),ids)
	var moved: bool = original!=x.world.facts.actors[x.obstacle.actor_id].location.cell
	var blocked: Dictionary = _observe(x,"accepted_historical_sweep_still_blocks",id,ids,1,false)
	movement_service._accepted_sweeps.clear()
	movement_service._sweep_index.expire_boundary()
	var recovered: Dictionary = _observe(x,"next_boundary_expires_history",id,ids,1,true)
	x.space.cancel_ground_move(x.world,x.obstacle.actor_id)
	suite._position(x,x.obstacle.actor_id,[58,86])
	x.world.touch(false)
	return {"ok":access.ok and request.is_empty() and accepted and moved and now_clear and history_blocks and blocked.ok and recovered.ok,"owner_granted_walk_access":access,"request":request,"real_substep_accepted":accepted,"actual_substep_moved":moved,"current_body_clear":now_clear,"accepted_sweep_intersects":history_blocks,"blocked":blocked,"recovered":recovered}

func _reservation_permissions(suite: RefCounted, x: Dictionary, id: String, ids: Array, repair: Array) -> Dictionary:
	var neighbor: String = "qualification_neighbor"
	var owner: Dictionary = x.world.facts.actors[x.obstacle.actor_id]
	# Shared work places require explicit access before creating the neighbor's
	# actual reservation. The target's departure projection removes only its own
	# reservation, so the independently owned neighbor must remain effective.
	x.space.grant_facility_access(x.world,id,owner.id)
	var primed: Dictionary = _observe(x,"departure_access_still_current",id,ids,0,true)
	var reason: String = x.space.reserve_facility(x.world,neighbor,owner.id,owner.id)
	if not reason.is_empty(): return {"ok":false,"neighbor_reservation":reason,"primed":primed}
	var overlap: bool = false
	var target: Rect2 = Rect2(float(repair[0]),float(repair[1]),1.0,1.0)
	for area: Array in x.world.facts.adaptations.get(neighbor,{}).get("regions",[]):
		overlap = Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3])).intersects(target,false) or overlap
	var blocked: Dictionary = _observe(x,"another_real_reservation_blocks",id,ids,1,false)
	x.space.grant_facility_access(x.world,neighbor,str(ids[0]))
	var permitted: Dictionary = _observe(x,"current_reservation_access_allows",id,ids,1,true)
	var warm: Dictionary = _observe(x,"permitted_reservation_warm",id,ids,0,true)
	x.world.facts.adaptations[neighbor].staff_ids.erase(ids[0])
	x.space.reservation_changed(x.world,neighbor)
	x.space._navigation.invalidate(x.world,1)
	var revoked: Dictionary = _observe(x,"current_reservation_access_revoked",id,ids,1,false)
	x.space.release_adaptations(x.world)
	var released: bool = not x.world.facts.adaptations.has(neighbor)
	var recovered: Dictionary = _observe(x,"real_reservation_release_recovers",id,ids,1,true)
	return {"ok":primed.ok and reason.is_empty() and overlap and blocked.ok and permitted.ok and warm.ok and revoked.ok and released and recovered.ok,"neighbor_reservation":reason,"regions_really_overlap":overlap,"primed":primed,"blocked":blocked,"permitted":permitted,"warm":warm,"revoked":revoked,"released":released,"recovered":recovered}

func _actual_commit(suite: RefCounted, x: Dictionary, id: String, ids: Array, repair: Array, holder: Dictionary) -> Dictionary:
	var before: Dictionary = x.world.freeze()
	var occupied_reason: String = x.space.reserve_facility(x.world,id,str(ids[0]),str(ids[0]))
	var ownership: bool = not occupied_reason.is_empty() and before==x.world.freeze()
	# The following is a calculation boundary after the old owner has left.
	# No real arrival or exit is asserted by preparing these positions.
	x.world.facts.actors[holder.actor_id].posture = "standing"
	x.world.facts.actors[holder.actor_id].erase("support_facility_id")
	x.world.facts.waiting_life.seats.erase(holder.id)
	suite._position(x,holder.actor_id,[55,86])
	x.space.release_adaptations(x.world)
	suite._position(x,x.obstacle.actor_id,repair)
	x.world.touch(false)
	var count_before: int = x.space.complete_quotes
	before = x.world.freeze()
	var blocked_reason: String = x.space.reserve_facility(x.world,id,str(ids[0]),str(ids[0]))
	var rechecked: bool = x.space.complete_quotes==count_before+1 and not blocked_reason.is_empty() and before==x.world.freeze() and not x.world.facts.adaptations.has(id)
	return {"ok":ownership and rechecked,"old_qualification_grants_no_ownership":ownership,"occupied_reason":occupied_reason,"actual_reserve_executes_complete_quote":x.space.complete_quotes-count_before,"current_body_blocks_commit_atomically":rechecked,"current_reason":blocked_reason}
