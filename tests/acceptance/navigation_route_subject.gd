extends RefCounted

const ACTOR: String = "route_subject_primary"
const OTHER: String = "route_subject_other"

class SubjectProbe extends HospitalNavigation:
	var preparations: int = 0
	var source_proofs: int = 0
	var point_queries: int = 0
	func _init(geometry: HospitalSpace) -> void:
		super(geometry)
	func _prepare_route_subject(world: WorldState, actor: Dictionary, members: Array, offsets: Dictionary) -> Dictionary:
		preparations += 1
		return super._prepare_route_subject(world,actor,members,offsets)
	func structural_clearance(world: WorldState, actor: Dictionary, floor_id: int, members: Array = [], offsets: Dictionary = {}) -> RouteClearance:
		source_proofs += 1
		return super.structural_clearance(world,actor,floor_id,members,offsets)
	func _point_route(world: WorldState, actor: Dictionary, source_floor: int, start: Vector2i, target_floor: int, goal: Vector2i, members: Array, offsets: Dictionary, initial_ticks: int, distance_only: bool) -> Dictionary:
		point_queries += 1
		return super._point_route(world,actor,source_floor,start,target_floor,goal,members,offsets,initial_ticks,distance_only)

# Frozen 87af6a6 complete entry function. Source work remains per call and the
# original full key still owns its results; it never uses prepared subjects.
class OriginalNavigation extends SubjectProbe:
	func _route_result(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array, offsets: Dictionary, _ignore_people: bool, distance_only: bool) -> Dictionary:
		space.query_counts.routes += 1
		var actor: Dictionary = world.facts.actors[actor_id]
		if actor.location.kind!="floor": return {"ok":false,"status":"unavailable","reason":"角色正在竖向通行或院外"}
		_observe_floor(world,actor_id,int(actor.location.floor_id))
		var start: Vector2i = Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1]))
		var goal: Vector2i = Vector2i(int(target[0]),int(target[1]))
		var actual: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
		var stub: float = actual.distance_to(Vector2(start))
		if stub>0.0:
			var query: RouteClearance = structural_clearance(world,actor,int(actor.location.floor_id),members,offsets)
			var reason: String = query.sweep_reason(actual,Vector2(start))
			if not reason.is_empty(): return {"ok":false,"status":"unreachable","reason":reason}
		var journeys: Dictionary = space.read_view(world,"point_journeys",func()->Dictionary:return {})
		var key: String = JSON.stringify([actor.id,actor.location.floor_id,actor.location.cell,floor_id,target,_route_envelope(world,actor,members,offsets),distance_only],"",true,true)
		if journeys.has(key):
			space.query_counts.journey_hits += 1
			return journeys[key].duplicate(true)
		var result: Dictionary = _point_route(world,actor,int(actor.location.floor_id),start,floor_id,goal,members,offsets,HospitalTransit.walking_ticks(space,actor,members,stub),distance_only)
		if result.ok and stub>0.0:
			if not distance_only: result.path.push_front({"kind":"floor","floor_id":int(actor.location.floor_id),"cell":[start.x,start.y]})
			result.walking_distance += stub
		journeys[key] = result.duplicate(true)
		return result

func _pair(content: HospitalContent) -> Dictionary:
	var actual: HospitalSpace = HospitalSpace.new(content)
	var reference: HospitalSpace = HospitalSpace.new(content)
	actual.navigation = SubjectProbe.new(actual)
	reference.navigation = OriginalNavigation.new(reference)
	return {"actual":actual,"reference":reference}

func _begin(pair: Dictionary, world: WorldState) -> void:
	pair.actual.begin_dynamic_route_query(world)
	pair.reference.begin_dynamic_route_query(world)

func _end(pair: Dictionary) -> void:
	pair.actual.end_route_query()
	pair.reference.end_route_query()

func _observe(pair: Dictionary, world: WorldState, floor_id: int, target: Array, cost_only: bool, members: Array = [], offsets: Dictionary = {}) -> Dictionary:
	var before: Dictionary = world.freeze()
	var actual: Dictionary = pair.actual.route_cost(world,ACTOR,floor_id,target,members,offsets,true) if cost_only else pair.actual.route(world,ACTOR,floor_id,target,members,offsets,true)
	var expected: Dictionary = pair.reference.route_cost(world,ACTOR,floor_id,target,members,offsets,true) if cost_only else pair.reference.route(world,ACTOR,floor_id,target,members,offsets,true)
	return {"ok":var_to_bytes(actual)==var_to_bytes(expected) and before==world.freeze(),"floor":floor_id,"target":target,"cost_only":cost_only,"members":members,"actual":actual,"full_result_types_reason_cost_path_equal":var_to_bytes(actual)==var_to_bytes(expected),"world_and_rng_unchanged":before==world.freeze()}

func run_case(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	suite._add_actor(sim,ACTOR,"S49",[44.25,80.25])
	suite._add_actor(sim,OTHER,"S49",[45.25,80.25])
	var world: WorldState = sim.world
	var pair: Dictionary = _pair(suite.content)
	var actual: SubjectProbe = pair.actual.navigation
	var reference: OriginalNavigation = pair.reference.navigation
	var checks: Dictionary = {"legal_input":world.validate(suite.content).is_empty()}
	var rows: Array = []
	_begin(pair,world)
	for query: Array in [[1,[46,82],false],[1,[47,82],false],[2,[46,82],false],[2,[47,82],true],[1,[46.0,82.0],false],[1,[46.25,82.5],true],[1,[-1,80],true]]:
		rows.append(_observe(pair,world,query[0],query[1],query[2]))
	checks.different_goals_modes_and_numeric_target_types_keep_full_results = rows.all(func(row: Dictionary)->bool:return row.ok)
	checks.one_source_preparation_and_real_proof_for_many_goals = actual.preparations==1 and actual.source_proofs==1 and reference.source_proofs==rows.size()
	checks.complete_point_queries_are_not_discarded = actual.point_queries==reference.point_queries and actual.point_queries>=5
	# Caller-owned executable cells must not mutate the subject's saved result.
	rows[0].actual.path[0].cell[0] = 94
	pair.actual.begin_route_query(world,{},false)
	pair.reference.begin_route_query(world,{},false)
	var repeated: Dictionary = _observe(pair,world,1,[46,82],false)
	pair.actual.end_route_query()
	pair.reference.end_route_query()
	checks.nested_scope_reuses_source_with_deep_owned_results = repeated.ok and actual.preparations==1 and actual.source_proofs==1
	var prior: int = actual.preparations
	var grouped: bool = true
	for target: Array in [[46,83],[47,83]]:
		grouped = grouped and _observe(pair,world,1,target,false,[ACTOR,OTHER],{ACTOR:[0,0],OTHER:[1,0]}).ok
	checks.group_keeps_original_source_chain_and_ordered_formation = grouped and actual.preparations-prior==2
	prior = actual.preparations
	var offset_only: Dictionary = _observe(pair,world,1,[46,84],true,[],{ACTOR:[0,0]})
	checks.nonempty_offsets_keep_original_chain = offset_only.ok and actual.preparations==prior+1
	var snapshot: WorldState = WorldState.new(world.freeze())
	snapshot.facts.actors[ACTOR].location.cell = [42.25,80.25]
	snapshot.facts.actors[ACTOR].facing = PI*0.5
	prior = actual.preparations
	_begin(pair,snapshot)
	var isolated: Dictionary = _observe(pair,snapshot,1,[46,82],false)
	_end(pair)
	var parent: Dictionary = _observe(pair,world,1,[46,82],false)
	checks.nested_other_world_has_its_own_source_and_parent_restores = isolated.ok and parent.ok and actual.preparations==prior+1
	_end(pair)
	var original_actor: Dictionary = world.facts.actors[ACTOR].duplicate(true)
	world.facts.actors[ACTOR].location.cell = [42.75,80.25]
	world.facts.actors[ACTOR].species_id = "S50"
	world.facts.actors[ACTOR].facing = PI*0.5
	prior = actual.preparations
	_begin(pair,world)
	var fresh: Dictionary = _observe(pair,world,1,[46,82],false)
	_end(pair)
	checks.new_batch_reads_current_origin_body_and_facing = fresh.ok and actual.preparations==prior+1
	prior = actual.preparations
	var unscoped: bool = true
	for _query: int in 3: unscoped = unscoped and _observe(pair,world,1,[46,82],false).ok
	checks.raw_queries_never_reuse_source_across_calls = unscoped and actual.preparations==prior+3
	world.facts.actors[ACTOR] = original_actor
	var failed: Dictionary = _stub_failure(suite.content,world.freeze())
	checks.original_stub_failure_and_recovery = failed.ok
	checks.closed_query_stacks = pair.actual._route_queries.is_empty() and pair.reference._route_queries.is_empty()
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"source_preparations":actual.preparations,"source_proofs":actual.source_proofs,"reference_source_proofs":reference.source_proofs,"complete_point_queries":actual.point_queries,"reference_complete_point_queries":reference.point_queries,"stub_failure":failed}
	sim.dispose()
	return result

func _stub_failure(content: HospitalContent, facts: Dictionary) -> Dictionary:
	var world: WorldState = WorldState.new(facts.duplicate(true))
	var actor: Dictionary = world.facts.actors[ACTOR]
	actor.location.cell = [44.75,80.0]
	world.facts.floors.overrides["1"].blocked.append([44,80])
	world.touch()
	var pair: Dictionary = _pair(content)
	var actual: SubjectProbe = pair.actual.navigation
	var reference: OriginalNavigation = pair.reference.navigation
	var physically_clear: bool = not pair.actual.body_rectangle(actor).intersects(Rect2(44,80,1,1),false)
	_begin(pair,world)
	var first: Dictionary = _observe(pair,world,1,[46,82],false)
	var second: Dictionary = _observe(pair,world,1,[47,82],true)
	_end(pair)
	var preserved: bool = first.ok and second.ok and first.actual==second.actual and not first.actual.ok and first.actual.status=="unreachable" and not str(first.actual.reason).is_empty() and actual.preparations==1 and actual.source_proofs==1 and reference.source_proofs==2 and actual.point_queries==0
	world.facts.floors.overrides["1"].blocked.erase([44,80])
	world.touch()
	_begin(pair,world)
	var restored: Dictionary = _observe(pair,world,1,[46,82],false)
	_end(pair)
	return {"ok":physically_clear and world.validate(content).is_empty() and preserved and restored.ok and restored.actual.ok and actual.preparations==2,"legal_actual_body_outside_block":physically_clear,"original_failure_preserved_once_per_scope":preserved,"failure_reason":first.actual.reason,"next_scope_after_real_recovery_accepts":restored.actual.ok}
