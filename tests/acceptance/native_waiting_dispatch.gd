extends "res://tests/acceptance/staff_fixtures.gd"

class SerialWaiting extends HospitalWaitingLife:
	func _prepare_need_costs(_world: WorldState) -> void: pass

class FailedNativeCache extends NavigationCache:
	var include_partial: bool = false
	var attempts: int = 0
	var rejected: Dictionary = {}
	func _calculate_structural_fields(inputs: Array) -> Dictionary:
		attempts += 1
		var invalid: Array = inputs.duplicate()
		invalid[-1] = inputs[-1].duplicate()
		# Reject the final request after the native parser has accepted the rest.
		invalid[-1].enabled = PackedByteArray()
		rejected = PlatformArrivalMath.grid_structural_fields(invalid)
		var response: Dictionary = rejected.duplicate()
		if include_partial:
			var poison: PackedInt32Array = PackedInt32Array()
			poison.resize(96*96); poison.fill(-1)
			var fields: Array = []
			for _input: Dictionary in inputs: fields.append(poison)
			response.fields = fields
		return response
	func installed_fields() -> int:
		var count: int = 0
		for entry: Dictionary in _entries.values():
			for field: Dictionary in entry.get("estimates",{}).values():
				if field.get("native_batch",false): count += 1
		return count

class CheckedWaiting extends HospitalWaitingLife:
	var prepared_closed: bool = false
	var partial_fields: int = -1
	func _prepare_need_costs(world: WorldState) -> void:
		super._prepare_need_costs(world)
		prepared_closed = space._route_queries.is_empty() and space._indexed_actor_scope.is_empty()
		partial_fields = space._navigation.installed_fields()

func run(database: HospitalContent, include_failures: bool = false) -> Dictionary:
	_content = database
	var x: Dictionary = _fixture()
	HospitalFactory._add_room(x.world,{"id":"waiting","type":"waiting","anchor":[34,66],"size":[10,12],"door":{"definition_id":"DR04","offset":3}},_content)
	_facility(x,"toilet","FUR07",[39,68],"waiting")
	for index: int in 12:
		var visit: Dictionary = _visit(x,"due_%02d" % index,[34+(index%4)*4,82+(index/4)*4])
		x.world.register_visit(str(visit.id))
	var later: Dictionary = _visit(x,"not_due",[50,92])
	later.arrival_tick=1; later.arrived_tick=1
	x.world.facts.waiting_life.clocks[later.id].next_need_tick=1801
	var moving: Dictionary = _visit(x,"moving",[54,92])
	# Legal input boundary immediately before the first 180-second need.
	x.world.facts.sim_tick = 1800
	for visit: Dictionary in x.world.facts.visits.values(): x.world.facts.tickets[visit.ticket_id].waited_ticks=1800-int(visit.arrival_tick)
	var move_reason: String = x.space.request_move(x.world,moving.actor_id,1,[55,92])
	x.world.touch()
	var validation: String = x.world.validate(_content)
	var before: Dictionary = x.world.freeze()
	var original: Dictionary = _bind(WorldState.new(before.duplicate(true)))
	var serial: SerialWaiting = SerialWaiting.new(_content,original.space)
	serial.environment=original.e; serial.visitors=original.c.visitors
	original.l=serial; original.p.waiting_life=serial
	x.l.dispatch(x.world)
	serial.dispatch(original.world)
	var travelling: bool = x.world.facts.waiting_life.needs.size()==12 and x.world.facts.adaptations.is_empty()
	for visit: Dictionary in x.world.facts.visits.values():
		if not str(visit.id).begins_with("due_"): continue
		var need: Dictionary = x.world.facts.waiting_life.needs.get(visit.id,{})
		travelling = travelling and need.get("phase","")=="area_travel" and x.world.facts.moves.has(visit.actor_id) and x.world.facts.actors[visit.actor_id].location==before.actors[visit.actor_id].location and int(x.world.facts.tickets[visit.ticket_id].waited_ticks)==1800
	var same: bool = x.world.freeze()==original.world.freeze()
	var used: bool = int(x.space.query_counts.get("native_field_batches",0))==1 and int(x.space.query_counts.get("native_field_requests",0))==12 and int(x.space.query_counts.get("native_field_hits",0))>0
	var after_validation: String = x.world.validate(_content)
	var excluded: bool = move_reason.is_empty() and not x.world.facts.waiting_life.needs.has(later.id) and not x.world.facts.waiting_life.needs.has(moving.id)
	var details: Dictionary = {"input_validation":validation,"output_validation":after_validation,"due_visits":12,"one_real_batch_consumed":used,"travel_without_early_reservation_or_position_commit":travelling,"not_due_and_existing_move_excluded":excluded,"facts_rng_ids_tickets_equal_to_serial_preparation":same,"threads_used":x.space.query_counts.get("native_field_threads",0)}
	var failures: Array = []
	var failure_ok: bool = true
	for partial: bool in ([false,true] if include_failures else []):
		var failed: Dictionary = _bind(WorldState.new(before.duplicate(true)))
		var cache: FailedNativeCache = FailedNativeCache.new()
		cache.include_partial = partial
		failed.space._navigation = cache
		var waiting: CheckedWaiting = CheckedWaiting.new(_content,failed.space)
		waiting.environment=failed.e; waiting.visitors=failed.c.visitors
		failed.l=waiting; failed.p.waiting_life=waiting
		waiting.dispatch(failed.world)
		var counts: Dictionary = failed.space.query_counts
		var route_counts: Dictionary = counts.duplicate()
		var reference_counts: Dictionary = original.space.query_counts.duplicate()
		# Preparing a rejected batch may warm geometry and refresh the actor index.
		# All route, movement and reservation query counts still match no batching.
		for key: String in ["native_field_batch_failures","actor_index_builds","actor_index_actor_visits","door_candidates"]:
			route_counts.erase(key); reference_counts.erase(key)
		var queries_same: bool = route_counts==reference_counts
		var end_validation: String = failed.world.validate(_content)
		var passed: bool = cache.attempts==1 and not cache.rejected.get("ok",true) and not cache.rejected.has("fields") and not str(cache.rejected.get("error","")).is_empty()
		passed = passed and int(counts.get("native_field_batch_failures",0))==1 and int(counts.get("native_field_batches",0))==0 and int(counts.get("native_field_hits",0))==0
		passed = passed and waiting.prepared_closed and waiting.partial_fields==0 and cache.installed_fields()==0 and failed.space._route_queries.is_empty() and failed.space._indexed_actor_scope.is_empty()
		passed = passed and failed.world.freeze()==original.world.freeze() and end_validation.is_empty() and queries_same
		failures.append({"partial_payload":partial,"passed":passed,"native_response":cache.rejected,"attempts":cache.attempts,"prepared_scope_closed":waiting.prepared_closed,"partial_fields_after_prepare":waiting.partial_fields,"facts_equal_to_no_batch":failed.world.freeze()==original.world.freeze(),"route_movement_reservation_query_counts_equal":queries_same,"validation":end_validation,"query_counts":counts,"reference_counts":original.space.query_counts})
		failure_ok = failure_ok and passed
		failed.a.dispose(); failed.p.waiting_life=null; failed.p.environment=null; waiting.environment=null; waiting.visitors=null; failed.e.waiting_life=null; failed.c.recruitment=null
	details.failure_fallback = failures
	for row: Dictionary in [x,original]:
		row.a.dispose(); row.p.waiting_life=null; row.p.environment=null; row.l.environment=null; row.l.visitors=null; row.e.waiting_life=null; row.c.recruitment=null
	return {"ok":validation.is_empty() and after_validation.is_empty() and travelling and same and used and excluded and failure_ok,"details":details}
