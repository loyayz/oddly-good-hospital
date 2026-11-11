extends "res://tests/acceptance/public_waiting_cost_field.gd"

# Exercise the production caller's rejection of a failed whole batch, including
# a malformed response which tries to attach complete-size poisoned payloads.
class FailedNativeCache extends NavigationCache:
	var include_partial: bool = false
	var attempts: int = 0
	var rejected: Dictionary = {}
	var input_count: int = 0
	var input_shapes: Array = []
	var input_unchanged: bool = false
	func _calculate_structural_fields(inputs: Array) -> Dictionary:
		attempts += 1
		input_count = inputs.size()
		input_shapes = []
		for item: Dictionary in inputs: input_shapes.append([item.enabled.size(),item.edges.size()])
		var before: PackedByteArray = var_to_bytes(inputs)
		var invalid: Array = inputs.duplicate(true)
		invalid[-1].enabled = PackedByteArray()
		rejected = PlatformArrivalMath.grid_structural_fields(invalid)
		var response: Dictionary = rejected.duplicate()
		if include_partial:
			var poison: PackedInt32Array = PackedInt32Array()
			poison.resize(96*96); poison.fill(-1)
			var fields: Array = []
			for _item: Dictionary in inputs: fields.append(poison)
			response.fields = fields
		input_unchanged = before==var_to_bytes(inputs)
		return response
	func installed_fields() -> int:
		var count: int = 0
		for entry: Dictionary in _entries.values():
			for field: Dictionary in entry.get("estimates",{}).values():
				if field.get("native_batch",false): count += 1
		return count

func run_case(suite: RefCounted) -> Dictionary:
	_content = suite.content
	var x: Dictionary = _field_fixture(false)
	var owner: HospitalSpace = x.actual
	var cache: NavigationCache = owner._navigation
	var world: WorldState = x.world
	var validation: String = _query_fixture_validation(x)
	var before: Dictionary = world.freeze()
	owner.begin_dynamic_route_query(world)
	cache.prepare_structural_fields(owner,world,[ACTOR,ACTOR])
	var field: Dictionary = cache.ready_structural_field(owner,world,1,world.facts.actors[ACTOR],Vector2i(38,90))
	var direct: Dictionary = owner.travel_quote(world,ACTOR,1,[39,90])
	var prepared: bool = field.get("ready",false) and int(field.distances[FloorNavigation._id(Vector2i(39,90))])==1 and direct.ok and int(direct.walking_distance)==1 and int(owner.query_counts.get("native_field_requests",0))==1
	owner.end_route_query()
	var actual: Dictionary = owner.public_areas.select(world,ACTOR,[],[""],"waiting",[],HospitalTransit.MAX_TICK,{},true)
	var expected: Dictionary = x.original.public_areas.select(world,ACTOR,[],[""],"waiting",[],HospitalTransit.MAX_TICK,{},true)
	var readonly: bool = before==world.freeze()
	world.facts.floors.overrides["1"].blocked.append([39,90]); world.touch()
	before = world.freeze()
	owner.begin_dynamic_route_query(world)
	var stale: Dictionary = cache.ready_structural_field(owner,world,1,world.facts.actors[ACTOR],Vector2i(38,90))
	cache.prepare_structural_fields(owner,world,[ACTOR])
	var blocked: Dictionary = owner.travel_quote(world,ACTOR,1,[39,90])
	owner.end_route_query()
	var invalidated: bool = stale.is_empty() and not blocked.ok and before==world.freeze()
	cache._trim(1)
	var evicted: bool = cache._entries.is_empty() and cache._query_charged==0 and cache._charged==0
	world.facts.floors.overrides["1"].blocked.erase([39,90]); world.touch()
	before = world.freeze()
	owner.begin_dynamic_route_query(world)
	cache.prepare_structural_fields(owner,world,[ACTOR])
	var restored: Dictionary = owner.travel_quote(world,ACTOR,1,[39,90])
	owner.end_route_query()
	var rebuilt: bool = restored.ok and int(restored.walking_distance)==1 and before==world.freeze()
	var details: Dictionary = {"input_validation":validation,"deduplicated_field_and_literal_unit_distance":prepared,"selection_equal":actual==expected,"selection":actual,"preparation_and_selection_readonly":readonly,"geometry_edit_invalidates_field":invalidated,"budget_evicts_all_query_payload":evicted,"rebuild_after_edit_and_eviction":rebuilt,"actual_native_field_hits":owner.query_counts.get("native_field_hits",0)}
	var ok: bool = validation.is_empty() and prepared and actual==expected and readonly and invalidated and evicted and rebuilt and int(details.actual_native_field_hits)>0
	_field_dispose(x)
	return {"ok":ok,"details":details}

# The original twelve request subjects and two other complete bodies remain.
# This is an explicit calculation boundary; no toilet dispatch, arrival, use or
# clock completion is asserted by preparing a structural matrix.
func _failure_fixture() -> Dictionary:
	var x: Dictionary = _fixture()
	HospitalFactory._add_room(x.world,{"id":"toilet_room","type":"toilet","anchor":[34,66],"size":[10,12],"door":{"definition_id":"DR04","offset":3}},_content)
	_facility(x,"toilet","FUR07",[39,68],"toilet_room")
	x.subjects = []
	for index: int in 12:
		var visit: Dictionary = _visit(x,"due_%02d" % index,[34+(index%4)*4,82+(index/4)*4])
		x.world.register_visit(str(visit.id))
		x.subjects.append(str(visit.actor_id))
	var later: Dictionary = _visit(x,"not_due",[50,92])
	later.arrival_tick = 1; later.arrived_tick = 1
	x.world.facts.waiting_life.clocks[later.id].next_need_tick = 1801
	var moving: Dictionary = _visit(x,"moving",[54,92])
	x.world.facts.sim_tick = 1800
	for visit: Dictionary in x.world.facts.visits.values(): x.world.facts.tickets[visit.ticket_id].waited_ticks = 1800-int(visit.arrival_tick)
	x.move_reason = x.space.request_move(x.world,moving.actor_id,1,[55,92])
	x.world.touch()
	return x

func _failure_case(source: Dictionary, partial: bool) -> Dictionary:
	var input: Dictionary = source.world.freeze()
	var failed: Dictionary = _bind(WorldState.new(input.duplicate(true)))
	var reference: Dictionary = _bind(WorldState.new(input.duplicate(true)))
	reference.space.navigation = OriginalTravel.FullSolver.new(reference.space)
	var cache: FailedNativeCache = FailedNativeCache.new()
	cache.include_partial = partial
	failed.space._navigation = cache
	var initial: String = failed.world.validate(_content)
	var unchanged_bind: bool = input==failed.world.freeze() and input==reference.world.freeze()
	failed.space.begin_dynamic_route_query(failed.world)
	cache.prepare_structural_fields(failed.space,failed.world,source.subjects)
	failed.space.end_route_query()
	var closed_after_prepare: bool = failed.space._route_queries.is_empty() and failed.space._indexed_actor_scope.is_empty()
	var installed_after_prepare: int = cache.installed_fields()
	var quotes: Array = []
	var complete: bool = true
	var before_routes: int = int(failed.space.query_counts.routes)
	var before_paths: int = int(failed.space.query_counts.static_path_builds)
	failed.space.begin_dynamic_route_query(failed.world)
	reference.space.begin_dynamic_route_query(reference.world)
	for id: String in source.subjects:
		# The real toilet-room wall requires an actual engine route through its
		# door. No field from a failed batch may turn this into a cached no-route.
		var actual: Dictionary = failed.space.route(failed.world,id,1,[35,70])
		var expected: Dictionary = reference.space.route(reference.world,id,1,[35,70])
		var same: bool = var_to_bytes(actual)==var_to_bytes(expected)
		complete = complete and actual.get("ok",false) and same and not actual.get("path",[]).is_empty()
		quotes.append({"actor_id":id,"ok":actual.get("ok",false),"complete_typed_result_equal":same,"path_cells":actual.get("path",[]).size(),"walking_distance":actual.get("walking_distance",-1),"reason":actual.get("reason","")})
	failed.space.end_route_query()
	reference.space.end_route_query()
	var counts: Dictionary = failed.space.query_counts.duplicate(true)
	var route_calls: int = int(counts.routes)-before_routes
	var path_builds: int = int(counts.static_path_builds)-before_paths
	var checks: Dictionary = {
		"legal_full_input":initial.is_empty() and source.move_reason.is_empty() and failed.world.facts.actors.size()==14 and failed.world.facts.visits.size()==14 and failed.world.facts.facilities.size()==1 and failed.world.facts.rooms.size()==1,
		"twelve_complete_native_requests":cache.input_count==12 and cache.input_shapes.size()==12 and cache.input_shapes.all(func(shape: Array)->bool:return shape==[9216,9216]),
		"native_rejects_last_request_atomically":cache.attempts==1 and not cache.rejected.get("ok",true) and not cache.rejected.has("fields") and not str(cache.rejected.get("error","")).is_empty() and cache.input_unchanged,
		"failed_response_installs_no_fields":installed_after_prepare==0 and cache.installed_fields()==0 and int(counts.get("native_field_batch_failures",0))==1 and int(counts.get("native_field_batches",0))==0 and int(counts.get("native_field_hits",0))==0,
		"complete_astar_fallback_for_all_subjects":complete and quotes.size()==12 and route_calls==12 and path_builds>0,
		"all_scopes_closed":closed_after_prepare and failed.space._route_queries.is_empty() and reference.space._route_queries.is_empty() and failed.space._indexed_actor_scope.is_empty(),
		"facts_rng_bodies_tickets_and_pending_move_unchanged":unchanged_bind and input==failed.world.freeze() and input==reference.world.freeze(),
		"valid_output":failed.world.validate(_content).is_empty() and reference.world.validate(_content).is_empty()}
	var result: Dictionary = {"ok":not checks.values().has(false),"partial_payload":partial,"checks":checks,"input_validation":initial,"request_count":cache.input_count,"request_shapes":cache.input_shapes,"installed_immediately_after_prepare":installed_after_prepare,"complete_route_calls":route_calls,"engine_path_builds":path_builds,"quotes":quotes,"native_rejection":cache.rejected,"query_counts":counts}
	for row: Dictionary in [failed,reference]: _field_dispose(row)
	return result

func run_failure_contract(database: HospitalContent) -> Dictionary:
	_content = database
	var source: Dictionary = _failure_fixture()
	var initial: String = source.world.validate(_content)
	var rows: Array = []
	for partial: bool in [false,true]: rows.append(_failure_case(source,partial))
	var result: Dictionary = {"ok":initial.is_empty() and rows.all(func(row: Dictionary)->bool:return row.ok),"input_validation":initial,"subjects":12,"complete_bodies":source.world.facts.actors.size(),"matrix_cells":9216,"cases":rows,"scope":"Explicit matrix preparation and failure fallback only; ordinary toilet dispatch is owned by the room queue and is not required to consume a waiting field."}
	_field_dispose(source)
	return result
