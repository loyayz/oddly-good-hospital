extends RefCounted

const ACTOR: String = "source_tree_actor"
const OTHER: String = "source_tree_other"

# Frozen 3053938 complete point solver. It always invokes the original lazy
# goal search and never consumes a single-source tree.
class FrozenSolver extends HospitalNavigation:
	func _init(geometry: HospitalSpace) -> void:
		super(geometry)
	func _point_route(world: WorldState, actor: Dictionary, source_floor: int, start: Vector2i, target_floor: int, goal: Vector2i, members: Array, offsets: Dictionary, initial_ticks: int, distance_only: bool) -> Dictionary:
		var direct: Dictionary = {"ok":false,"status":"unreachable","reason":"没有合法通路"}
		if source_floor==target_floor:
			direct = _floor_route(world,actor,source_floor,start,goal,members,offsets,true,{},true,distance_only)
			# Current floor edges have unit cost. A sole connector returns to the
			# same anchor, so leaving and returning cannot improve this shortest walk.
			if direct.ok and (world.facts.connectors.size()<=1 or int(direct.walking_distance)==absi(goal.x-start.x)+absi(goal.y-start.y)):
				direct.travel_ticks = HospitalTransit._add(initial_ticks,HospitalTransit.walking_ticks(space,actor,members,float(direct.walking_distance)))
				if int(direct.travel_ticks)<0: return {"ok":false,"status":"time_overflow","reason":"基准通行时间超出整数范围"}
				# This new case previously returned the full solver's float distance.
				if world.facts.connectors.size()==1 and int(direct.walking_distance)!=absi(goal.x-start.x)+absi(goal.y-start.y): direct.walking_distance = float(direct.walking_distance)
				direct.quoted_tick = world.sim_tick
				if distance_only: direct.erase("path")
				return direct
		space.query_counts.transport_searches += 1
		var nodes: Dictionary = {"start":{"floor_id":source_floor,"cell":start},"goal":{"floor_id":target_floor,"cell":goal}}
		var topology: Dictionary = _topology(world)
		var node_ids: Array = topology.node_ids
		var extra_stops: Dictionary = {}
		for floor_id: int in {source_floor:true,target_floor:true}:
			if topology.candidates.has(floor_id): continue
			var extra: Dictionary = _topology_floor_nodes(world,topology,floor_id)
			if extra.ids.is_empty(): continue
			if is_same(node_ids,topology.node_ids): node_ids = node_ids.duplicate()
			node_ids.append_array(extra.ids)
			nodes.merge(extra.nodes)
			for id: String in extra.connectors:
				if not extra_stops.has(id): extra_stops[id] = []
				extra_stops[id].append(floor_id)
		# Native vertex declarations reuse the topology; floor A* still runs only
		# when Boost settles a node and requests its business-defined outgoing edges.
		# Compatibility is independent of the destination. The existing sealed
		# read-only scope owns reuse for this exact actor and ordered member list.
		var compatible: Dictionary = space.read_view(world,"point_connector_fits:"+JSON.stringify([actor.id,members]),func()->Dictionary:return {})
		var prepared: Dictionary = _connector_preparation(world,actor,members,offsets,distance_only,topology,extra_stops)
		var context: Dictionary = {"nodes":nodes,"stops":topology.stops,"extra_stops":extra_stops,"query_stops":{},"topology":topology,"connections":{},"compatible":compatible,"connector_prepared":prepared,"edges":{},"source_floor":source_floor,"target_floor":target_floor,"goal":goal,"members":members,"offsets":offsets,"distance_only":distance_only,"direct":direct}
		var solved: Dictionary = PlatformArrivalMath.route_search({"nodes":node_ids,"start":"start","goal":"goal","initial_ticks":initial_ticks,"expand":_point_edges.bind(world,actor,context)})
		if solved.has("error"):
			return {"ok":false,"status":"navigation_failed","reason":str(solved.get("bottleneck",solved.error))}
		if solved.get("ok",false):
			var chain: Array = solved.nodes
			var chunks: Array = []
			var distance: float = 0.0
			# Retain the original reverse accumulation order for floating distances.
			for index: int in range(chain.size()-1,0,-1):
				var edge: Dictionary = context.edges[chain[index-1]][chain[index]]
				distance += float(edge.walking_distance)
				if not distance_only: chunks.push_front(edge.path)
			var result: Dictionary = {"ok":true,"status":"complete","reason":"","walking_distance":distance,"travel_ticks":int(solved.travel_ticks),"quoted_tick":world.sim_tick}
			if not distance_only:
				var path: Array = []
				# Returned executable segments belong to this journey. Connector
				# preparation remains immutable when a caller edits its own path.
				for chunk: Array in chunks: path.append_array(chunk.duplicate(true))
				result.path = path
			return result
		if direct.ok: return {"ok":false,"status":"time_overflow","reason":"基准通行时间超出整数范围"}
		return direct if source_floor==target_floor else {"ok":false,"status":"unreachable","reason":"没有身体、停层和运行方向均合法的竖向通路"}

class SoleLiftProbe extends HospitalNavigation:
	var start_preparations: int = 0
	var source_preparations: Array = []
	var source_expansions: Array = []
	var source_nonempty_expansions: Array = []
	var source_floor_queries: Array = []
	var _source_expanding_id: String = ""
	func _init(geometry: HospitalSpace) -> void:
		super(geometry)
	func _connector_edges(world: WorldState, actor: Dictionary, context: Dictionary, node: Dictionary) -> Dictionary:
		if int(node.floor_id)==int(context.source_floor) and node.cell==context.nodes.start.cell: start_preparations += 1
		if context.get("single_source",false): source_preparations.append({"floor_id":int(node.floor_id),"cell":node.cell})
		return super._connector_edges(world,actor,context,node)
	func _point_edges(id: String, world: WorldState, actor: Dictionary, context: Dictionary) -> Array:
		var previous: String = _source_expanding_id
		if context.get("single_source",false):
			_source_expanding_id = id
			source_expansions.append(id)
		var result: Array = super._point_edges(id,world,actor,context)
		if context.get("single_source",false) and not result.is_empty(): source_nonempty_expansions.append(id)
		_source_expanding_id = previous
		return result
	func _floor_route(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2i, goal: Vector2i, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false, navigation: Dictionary = {}, structural_only: bool = false, cost_only: bool = false) -> Dictionary:
		if not _source_expanding_id.is_empty(): source_floor_queries.append({"node":_source_expanding_id,"floor_id":floor_id,"start":start,"goal":goal})
		return super._floor_route(world,actor,floor_id,start,goal,members,offsets,ignore_people,navigation,structural_only,cost_only)

func _counts(space: HospitalSpace) -> Array:
	return [int(space.query_counts.get("transport_searches",0)),int(space.query_counts.get("point_source_builds",0)),int(space.query_counts.get("point_source_hits",0))]

func _begin(space: HospitalSpace, reference: HospitalSpace, world: WorldState) -> void:
	space.begin_dynamic_route_query(world)
	reference.begin_dynamic_route_query(world)

func _end(space: HospitalSpace, reference: HospitalSpace) -> void:
	space.end_route_query()
	reference.end_route_query()

func _observe(space: HospitalSpace, reference: HospitalSpace, world: WorldState, floor_id: int, target: Array, cost_only: bool = true, members: Array = [], offsets: Dictionary = {}, initial: int = -1) -> Dictionary:
	var before: Dictionary = world.freeze()
	var actual: Dictionary
	var expected: Dictionary
	if initial>=0:
		var actor: Dictionary = world.facts.actors[ACTOR]
		var source_floor: int = int(actor.location.floor_id)
		var start: Vector2i = Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1]))
		var goal: Vector2i = Vector2i(int(target[0]),int(target[1]))
		actual = space.navigation._point_route(world,actor,source_floor,start,floor_id,goal,members,offsets,initial,cost_only)
		expected = reference.navigation._point_route(world,actor,source_floor,start,floor_id,goal,members,offsets,initial,cost_only)
	else:
		actual = space.route_cost(world,ACTOR,floor_id,target,members,offsets,true) if cost_only else space.route(world,ACTOR,floor_id,target,members,offsets,true)
		expected = reference.route_cost(world,ACTOR,floor_id,target,members,offsets,true) if cost_only else reference.route(world,ACTOR,floor_id,target,members,offsets,true)
	var equal: bool = var_to_bytes(actual)==var_to_bytes(expected)
	return {"ok":equal and before==world.freeze(),"floor_id":floor_id,"target":target,"cost_only":cost_only,"initial_ticks":initial,"full_result_including_types_and_reason_equal":equal,"world_and_rng_unchanged":before==world.freeze(),"actual":actual,"expected":expected if not equal else {}}

func _all_ok(rows: Array) -> bool:
	for row: Dictionary in rows:
		if not row.ok: return false
	return true

func run_case(suite: RefCounted) -> Dictionary:
	var sole: Dictionary = _single_lift(suite)
	var sim: HospitalSimulation = suite._transit_fixture()
	suite._history_height(sim,5)
	for floor_id: int in [3,4,5]:
		var extended: CommandResult = suite._command(sim,"connector_extend",{"connection_id":suite._connection(sim),"floor_id":floor_id})
		if not extended.accepted:
			sim.dispose()
			return {"ok":false,"extension":extended.to_record()}
	var built: CommandResult = suite._command(sim,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[52,72]})
	if not built.accepted:
		sim.dispose()
		return {"ok":false,"second_connection":built.to_record()}
	var second: String = str(built.changed_ids[0])
	var extended_second: CommandResult = suite._command(sim,"connector_extend",{"connection_id":second,"floor_id":2})
	if not extended_second.accepted:
		sim.dispose()
		return {"ok":false,"second_extension":extended_second.to_record()}
	for floor_id: int in [2,3,4,5]: HospitalSpace.materialize_layout(sim.world,floor_id)
	suite._add_actor(sim,ACTOR,"S49",[44.25,80.25])
	suite._add_actor(sim,OTHER,"S49",[45.25,80.25])
	var reference: HospitalSpace = HospitalSpace.new(suite.content)
	reference.navigation = FrozenSolver.new(reference)
	var space: HospitalSpace = sim.space
	var world: WorldState = sim.world
	var checks: Dictionary = {"legal_input":world.validate(suite.content).is_empty(),"single_lift_arrivals_are_common_tree_leaves":sole.ok}
	var rows: Array = []
	var before: Array = _counts(space)
	var reference_before: int = int(reference.query_counts.transport_searches)
	_begin(space,reference,world)
	rows.append(_observe(space,reference,world,2,[46,82]))
	checks.one_target_keeps_lazy_search = _counts(space)[0]==before[0]+1 and _counts(space)[1]==before[1]
	for goal: Array in [[2,[47,82]],[2,[48,82]],[3,[46,82]],[5,[49,82]]]:
		rows.append(_observe(space,reference,world,int(goal[0]),goal[1]))
	var after: Array = _counts(space)
	checks.five_goals_use_one_lazy_and_one_source_search = after[0]-before[0]==2 and after[1]-before[1]==1 and after[2]-before[2]==3 and int(reference.query_counts.transport_searches)-reference_before==5
	checks.all_constructed_source_floors_are_observed = space.navigation.observed_floors(world,[ACTOR])==[1,2,3,4,5]
	# A result belongs to its caller, including the first tree-backed answer.
	rows[1].actual.walking_distance = -321.0
	rows[1].actual.reason = "caller-only mutation"
	var repeat_before: Array = _counts(space)
	var repeated: Dictionary = _observe(space,reference,world,2,[47,82])
	checks.caller_mutation_does_not_change_cached_answer = repeated.ok and _counts(space)==repeat_before
	rows.append(repeated)
	var full_before: Array = _counts(space)
	rows.append(_observe(space,reference,world,2,[46,83],false))
	rows.append(_observe(space,reference,world,2,[47,83],false))
	rows.append(_observe(space,reference,world,2,[46,84],true,[ACTOR,OTHER],{ACTOR:[0,0],OTHER:[1,0]}))
	rows.append(_observe(space,reference,world,2,[47,84],true,[ACTOR,OTHER],{ACTOR:[0,0],OTHER:[1,0]}))
	checks.executable_paths_and_groups_keep_lazy_solver = _counts(space)[0]-full_before[0]==4 and _counts(space)[1]==full_before[1] and _counts(space)[2]==full_before[2]
	var projected: WorldState = WorldState.new(world.freeze())
	var nested_before: Array = _counts(space)
	_begin(space,reference,projected)
	rows.append(_observe(space,reference,projected,2,[46,82]))
	rows.append(_observe(space,reference,projected,3,[47,82]))
	_end(space,reference)
	checks.other_world_builds_independently = _counts(space)[0]-nested_before[0]==2 and _counts(space)[1]-nested_before[1]==1
	var parent_before: Array = _counts(space)
	rows.append(_observe(space,reference,world,4,[48,82]))
	checks.parent_scope_restores_its_source_tree = _counts(space)[0]==parent_before[0] and _counts(space)[1]==parent_before[1] and _counts(space)[2]==parent_before[2]+1
	_end(space,reference)
	var fresh_before: Array = _counts(space)
	_begin(space,reference,world)
	rows.append(_observe(space,reference,world,2,[46,82]))
	checks.new_batch_starts_with_lazy_query = _counts(space)[0]==fresh_before[0]+1 and _counts(space)[1]==fresh_before[1]
	rows.append(_observe(space,reference,world,2,[48,82]))
	checks.new_batch_builds_fresh_tree = _counts(space)[1]==fresh_before[1]+1
	_end(space,reference)
	var unscoped_before: Array = _counts(space)
	rows.append(_observe(space,reference,world,2,[46,82]))
	rows.append(_observe(space,reference,world,2,[48,82]))
	checks.raw_calls_keep_independent_lazy_searches = _counts(space)[0]-unscoped_before[0]==2 and _counts(space)[1]==unscoped_before[1] and _counts(space)[2]==unscoped_before[2]
	var initial_before: Array = _counts(space)
	_begin(space,reference,world)
	rows.append(_observe(space,reference,world,2,[46,85],true,[],{},7))
	rows.append(_observe(space,reference,world,2,[47,85],true,[],{},8))
	checks.distinct_initial_ticks_have_independent_first_queries = _counts(space)[0]-initial_before[0]==2 and _counts(space)[1]==initial_before[1]
	rows.append(_observe(space,reference,world,2,[48,85],true,[],{},7))
	rows.append(_observe(space,reference,world,2,[49,85],true,[],{},8))
	checks.distinct_initial_ticks_build_two_trees = _counts(space)[0]-initial_before[0]==4 and _counts(space)[1]-initial_before[1]==2
	var maximum: Dictionary = _observe(space,reference,world,2,[46,86],true,[],{},HospitalTransit.MAX_TICK)
	var overflow: Dictionary = _observe(space,reference,world,2,[47,86],true,[],{},HospitalTransit.MAX_TICK)
	checks.maximum_initial_time_and_overflow_reason_match = maximum.ok and overflow.ok and not maximum.actual.ok and not overflow.actual.ok
	rows.append(maximum)
	rows.append(overflow)
	_end(space,reference)
	var sparse: Dictionary = _extra_stops(space,reference,world,suite.content)
	checks.extra_stop_variants = sparse.ok
	var bypass: Dictionary = _same_floor_bypass(space,reference,world,suite.content)
	checks.same_floor_two_connector_alternative = bypass.ok
	var changes: Dictionary = _changed_facts(space,reference,world,suite.content)
	checks.real_direction_geometry_and_origin_changes = changes.ok
	checks.all_complete_answers_match_frozen_solver = _all_ok(rows)
	checks.closed_scopes = space._route_queries.is_empty() and reference._route_queries.is_empty()
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"observations":rows,"single_lift":sole,"extra_stops":sparse,"same_floor_bypass":bypass,"changed_facts":changes,"source_counts":_counts(space),"scope":"Complete legal candidate quotes on the original fixed-time connector graph. No route, target, actor, stage or movement is removed."}
	sim.dispose()
	return result

func _single_lift(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	suite._history_height(sim,5)
	for floor_id: int in [3,4,5]:
		var extended: CommandResult = suite._command(sim,"connector_extend",{"connection_id":suite._connection(sim),"floor_id":floor_id})
		if not extended.accepted:
			sim.dispose()
			return {"ok":false,"extension":extended.to_record()}
	for floor_id: int in [2,3,4,5]: HospitalSpace.materialize_layout(sim.world,floor_id)
	suite._add_actor(sim,ACTOR,"S49",[44.25,80.25])
	var probe: SoleLiftProbe = SoleLiftProbe.new(sim.space)
	sim.space.navigation = probe
	var reference: HospitalSpace = HospitalSpace.new(suite.content)
	reference.navigation = FrozenSolver.new(reference)
	var checks: Dictionary = {"legal_single_lift_five_floor_input":sim.world.validate(suite.content).is_empty() and sim.world.facts.connectors.size()==1}
	var rows: Array = []
	var before: Array = _counts(sim.space)
	_begin(sim.space,reference,sim.world)
	for target: Array in [[2,[46,82]],[2,[47,82]],[3,[46,82]],[4,[47,82]],[5,[48,82]]]: rows.append(_observe(sim.space,reference,sim.world,int(target[0]),target[1]))
	_end(sim.space,reference)
	checks.five_targets_use_one_lazy_search_and_one_source_tree = _counts(sim.space)[0]-before[0]==2 and _counts(sim.space)[1]-before[1]==1 and _counts(sim.space)[2]-before[2]==3
	checks.original_start_edges_prepared_exactly_once = probe.start_preparations==1
	# The common start consumes the original lazy query's already prepared
	# edges. Every arrival is still settled, but no return ride is prepared.
	checks.common_tree_only_start_has_outgoing_edges = probe.source_expansions.size()==5 and probe.source_expansions[0]=="start" and probe.source_nonempty_expansions==["start"]
	checks.common_tree_reuses_start_without_repreparing_arrivals = probe.source_preparations.is_empty() and probe.source_floor_queries.is_empty()
	checks.every_full_quote_keeps_current_goal_checks = _all_ok(rows)
	for row: Dictionary in rows: checks.every_full_quote_keeps_current_goal_checks = checks.every_full_quote_keeps_current_goal_checks and row.actual.get("ok",false)
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"observations":rows,"start_preparations":probe.start_preparations,"source_expansions":probe.source_expansions,"source_nonempty_expansions":probe.source_nonempty_expansions,"source_connector_preparations":probe.source_preparations,"source_floor_queries":probe.source_floor_queries}
	sim.dispose()
	return result

func _extra_stops(space: HospitalSpace, reference: HospitalSpace, original: WorldState, content: HospitalContent) -> Dictionary:
	var world: WorldState = WorldState.new(original.freeze())
	world.facts.floors.overrides.erase("3")
	world.facts.floors.overrides.erase("4")
	world.touch()
	var checks: Dictionary = {"legal_sparse_history":world.validate(content).is_empty()}
	var rows: Array = []
	var before: Array = _counts(space)
	_begin(space,reference,world)
	rows.append(_observe(space,reference,world,3,[46,82]))
	rows.append(_observe(space,reference,world,3,[47,82]))
	checks.first_extra_floor_has_its_own_tree = _counts(space)[0]-before[0]==2 and _counts(space)[1]-before[1]==1
	rows.append(_observe(space,reference,world,4,[46,82]))
	checks.other_extra_floor_starts_lazily = _counts(space)[0]-before[0]==3 and _counts(space)[1]-before[1]==1
	rows.append(_observe(space,reference,world,4,[47,82]))
	rows.append(_observe(space,reference,world,3,[48,82]))
	checks.complete_stop_declarations_keep_separate_labels = _counts(space)[0]-before[0]==4 and _counts(space)[1]-before[1]==2 and _counts(space)[2]-before[2]==1
	_end(space,reference)
	return {"ok":not checks.values().has(false) and _all_ok(rows),"checks":checks,"observations":rows}

func _changed_facts(space: HospitalSpace, reference: HospitalSpace, original: WorldState, content: HospitalContent) -> Dictionary:
	var world: WorldState = WorldState.new(original.freeze())
	for connection: Dictionary in world.facts.connectors.values(): connection.failed = true
	world.touch(false)
	var rows: Array = []
	var checks: Dictionary = {"legal_failed_connections":world.validate(content).is_empty()}
	_begin(space,reference,world)
	rows.append(_observe(space,reference,world,3,[46,82]))
	rows.append(_observe(space,reference,world,4,[47,82]))
	checks.failed_ascent_retains_complete_unreachable_reason = not rows[0].actual.ok and not rows[1].actual.ok and rows[0].ok and rows[1].ok
	_end(space,reference)
	world.facts.actors[ACTOR].location.floor_id = 4
	world.touch(false)
	_begin(space,reference,world)
	rows.append(_observe(space,reference,world,2,[46,82]))
	rows.append(_observe(space,reference,world,1,[47,82]))
	checks.failed_connections_still_allow_safe_descent = rows[2].actual.ok and rows[3].actual.ok and rows[2].ok and rows[3].ok
	_end(space,reference)
	for connection: Dictionary in world.facts.connectors.values(): connection.failed = false
	world.facts.actors[ACTOR].location.floor_id = 1
	world.facts.floors.overrides["3"].blocked.append([46,82])
	world.touch()
	_begin(space,reference,world)
	rows.append(_observe(space,reference,world,3,[46,82]))
	rows.append(_observe(space,reference,world,3,[47,82]))
	checks.current_blocked_target_is_not_granted_by_source_tree = not rows[4].actual.ok and rows[5].actual.ok and rows[4].ok and rows[5].ok
	_end(space,reference)
	world.facts.floors.overrides["3"].blocked.erase([46,82])
	world.facts.actors[ACTOR].location.cell = [43.75,80.25]
	world.facts.actors[ACTOR].facing = PI*0.5
	world.touch()
	var before: Array = _counts(space)
	_begin(space,reference,world)
	rows.append(_observe(space,reference,world,3,[46,82]))
	checks.changed_origin_starts_with_current_lazy_source = _counts(space)[0]-before[0]==1 and _counts(space)[1]==before[1]
	rows.append(_observe(space,reference,world,3,[47,82]))
	checks.recovered_geometry_builds_new_tree = rows[6].actual.ok and rows[7].actual.ok and rows[6].ok and rows[7].ok and _counts(space)[1]-before[1]==1
	_end(space,reference)
	checks.final_input_valid = world.validate(content).is_empty()
	return {"ok":not checks.values().has(false) and _all_ok(rows),"checks":checks,"observations":rows}

func _same_floor_bypass(space: HospitalSpace, reference: HospitalSpace, original: WorldState, content: HospitalContent) -> Dictionary:
	var world: WorldState = WorldState.new(original.freeze())
	world.facts.actors[ACTOR].location.cell = [42,76]
	# The north-reaching wall forces a 42-cell floor walk. Two real lifts can
	# instead use 6 + 16 + 2 walking cells through the unobstructed upper floor.
	for y: int in range(64,93): world.facts.floors.overrides["1"].blocked.append([46,y])
	world.touch()
	var before: Array = _counts(space)
	var rows: Array = []
	_begin(space,reference,world)
	for cell: Array in [[50,76],[50,77],[50,78]]: rows.append(_observe(space,reference,world,1,cell))
	var direct: Dictionary = reference.navigation._floor_route(world,world.facts.actors[ACTOR],1,Vector2i(42,76),Vector2i(50,76),[],{},true,{},true,true)
	_end(space,reference)
	var checks: Dictionary = {"legal_world":world.validate(content).is_empty(),"literal_24_cell_lift_bypass_beats_42_cell_floor_walk":rows[0].actual.get("walking_distance",-1)==24.0 and direct.get("walking_distance",-1)==42,"three_same_floor_candidates_share_complete_alternatives":_counts(space)[0]-before[0]==2 and _counts(space)[1]-before[1]==1 and _counts(space)[2]-before[2]==1}
	return {"ok":not checks.values().has(false) and _all_ok(rows),"checks":checks,"observations":rows}
