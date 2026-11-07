extends RefCounted

# No guidance policy is redefined here. These are the public route/dispatch
# handoffs used by lift-to-desk and same-floor desk/clinical journeys.
func fixture(suite: RefCounted) -> HospitalSimulation:
	var sim: HospitalSimulation = suite._transit_fixture()
	suite._command(sim,"connector_build",{"definition_id":"VC02","floor_id":1,"cell":[44,68]})
	var lift: String = sim.world.ids("connectors").back()
	suite._command(sim,"connector_extend",{"connection_id":lift,"floor_id":2})
	for floor_id: int in [1,2]:
		for index: int in 2:
			suite._command(sim,"build_facility",{"id":"guidance_%d_%d"%[floor_id,index],"definition_id":"SE01","floor_id":floor_id,"cell":[52,82+index*7]})
	suite._add_actor(sim,"guide_first","S49",[36,76],1)
	suite._add_actor(sim,"guide_second","S49",[40,80],1)
	suite._add_actor(sim,"guide_wide","S53",[43,84],1)
	return sim

func run_case(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = fixture(suite)
	var world: WorldState = sim.world
	var space: HospitalSpace = HospitalSpace.new(suite.content)
	var checks: Dictionary = {"legal_fixture":world.validate(suite.content).is_empty(),"no_eager_graphs_or_paths":space._navigation._entries.is_empty()}
	var results: Array = []
	var before: Dictionary = world.freeze()
	for floor_id: int in [1,2]:
		for actor_id: String in ["guide_first","guide_wide"]:
			var actor: Dictionary = world.facts.actors[actor_id]
			for lift: Dictionary in world.facts.connectors.values():
				for desk_index: int in 2:
					var target: Array = space.facility_layout(world,"guidance_%d_%d"%[floor_id,desk_index]).patient_cell
					for reverse: bool in [false,true]:
						var start: Vector2i = Vector2i(int(lift.anchor[0]),int(lift.anchor[1]))
						var goal: Vector2i = Vector2i(int(target[0]),int(target[1]))
						if reverse:
							var swap: Vector2i = start
							start = goal
							goal = swap
						var graph: FloorNavigation = space._navigation.graph(space,world,floor_id,actor,[],{})
						var cold: Dictionary = graph.find_path(start,goal,graph.geometry)
						var builds: int = int(space.query_counts.static_path_builds)
						var first: Dictionary = space.navigation._floor_route(world,actor,floor_id,start,goal,[],{},true,{},true)
						var retained: Dictionary = first.duplicate(true)
						if first.get("ok",false) and not first.path.is_empty(): first.path[0].cell[0] = -100
						var same_shape: Dictionary = world.facts.actors.guide_second if actor_id=="guide_first" else actor
						var hits: int = int(space.query_counts.static_path_hits)
						var second: Dictionary = space.navigation._floor_route(world,same_shape,floor_id,start,goal,[],{},true,{},true)
						var equal: bool = _same_floor_result(retained,cold) and retained==second
						var hit: bool = int(space.query_counts.static_path_hits)==hits+1 and int(space.query_counts.static_path_builds)==builds+1
						results.append({"floor":floor_id,"actor":actor_id,"start":[start.x,start.y],"goal":[goal.x,goal.y],"cold_equal_and_owned_result":equal,"repeat_hit":hit,"ok":equal and hit})
	checks.two_floors_lifts_desks_bodies_and_both_directions = results.size()==32
	for result: Dictionary in results: checks.two_floors_lifts_desks_bodies_and_both_directions = checks.two_floors_lifts_desks_bodies_and_both_directions and result.ok
	checks.route_queries_do_not_change_world = world.freeze()==before and space._route_queries.is_empty()
	var upgrade_actor: Dictionary = world.facts.actors.guide_first
	var upgrade_start: Vector2i = Vector2i(34,94)
	var upgrade_goal: Vector2i = Vector2i(60,94)
	var cost: Dictionary = space.navigation._floor_route(world,upgrade_actor,1,upgrade_start,upgrade_goal,[],{},true,{},true,true)
	var cost_builds: int = int(space.query_counts.static_path_builds)
	var full: Dictionary = space.navigation._floor_route(world,upgrade_actor,1,upgrade_start,upgrade_goal,[],{},true,{},true)
	var full_builds: int = int(space.query_counts.static_path_builds)
	var full_hits: int = int(space.query_counts.static_path_hits)
	var full_again: Dictionary = space.navigation._floor_route(world,world.facts.actors.guide_second,1,upgrade_start,upgrade_goal,[],{},true,{},true)
	checks.cost_only_record_upgrades_to_owned_full_path = cost.ok and full.ok and not cost.has("path") and full.walking_distance==cost.walking_distance and full_builds==cost_builds+1 and full_again==full and int(space.query_counts.static_path_hits)==full_hits+1
	var actor: Dictionary = world.facts.actors.guide_first
	var target: Array = space.facility_layout(world,"guidance_1_0").patient_cell
	var first: Dictionary = space.route(world,actor.id,1,target)
	var hits: int = int(space.query_counts.static_path_hits)
	var second: Dictionary = space.route(world,actor.id,1,target)
	checks.public_unscoped_route_reuses_same_result = first.ok and first==second and int(space.query_counts.static_path_hits)>hits
	world.facts.floors.overrides["1"].blocked.append(target.duplicate())
	world.touch()
	var blocked: Dictionary = space.route(world,actor.id,1,target)
	var cold_blocked: Dictionary = HospitalSpace.new(suite.content).route(world,actor.id,1,target)
	checks.real_floor_edit_does_not_reuse_reachable_path = not blocked.ok and blocked==cold_blocked
	var blocked_hits: int = int(space.query_counts.static_path_hits)
	var blocked_again: Dictionary = space.route(world,actor.id,1,target)
	checks.repeated_unreachable_result_is_cached = blocked_again==blocked and int(space.query_counts.static_path_hits)>blocked_hits
	world.facts.floors.overrides["1"].blocked.erase(target)
	world.touch()
	var restored: Dictionary = space.route(world,actor.id,1,target)
	checks.restore_does_not_reuse_disconnected_path = restored.ok and restored==HospitalSpace.new(suite.content).route(world,actor.id,1,target)
	space._navigation._trim(0,space.query_counts)
	checks.original_total_budget_evicts_all_paths = space._navigation._entries.is_empty() and space._navigation._charged==0 and space._navigation._query_charged==0
	checks.evicted_route_rebuilds = space.route(world,actor.id,1,target)==restored
	var saved: WorldState = WorldState.new(world.freeze())
	var saved_space: HospitalSpace = HospitalSpace.new(suite.content)
	checks.saved_world_owns_cold_runtime_cache = saved_space._navigation._entries.is_empty() and saved_space.route(saved,actor.id,1,target)==restored
	checks.valid_final_world = world.validate(suite.content).is_empty()
	var movement: Dictionary = _movement(suite)
	checks.actual_dispatch_collision_and_reservation_handoffs = movement.ok
	var clinical: Dictionary = _clinical_return(suite)
	checks.same_floor_clinical_desk_round_trips = clinical.ok
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"endpoint_cases":results,"movement":movement,"clinical_return":clinical,"counts":space.query_counts.duplicate(true)}
	sim.dispose()
	return result

func _same_floor_result(route: Dictionary, raw: Dictionary) -> bool:
	if route.ok!=raw.ok or route.status!=raw.status or route.reason!=raw.reason: return false
	if not route.ok: return true
	var cells: Array = []
	for segment: Dictionary in route.path: cells.append(segment.cell)
	return route.walking_distance==raw.walking_distance and cells==raw.cells

func _movement(suite: RefCounted) -> Dictionary:
	var observations: Array = []
	for mode: String in ["plain","body_blocker","reserved_goal"]:
		var sim: HospitalSimulation = suite._fixture()
		suite._command(sim,"build_facility",{"id":"real_guidance","definition_id":"M37" if mode=="reserved_goal" else "SE01","floor_id":1,"cell":[49,78] if mode=="reserved_goal" else [49,79]})
		suite._add_actor(sim,"guide_walker","S49",[35,80])
		var goal: Array = sim.space.facility_layout(sim.world,"real_guidance").patient_cell
		var prime: Dictionary = sim.space.route(sim.world,"guide_walker",1,goal)
		var initial_hits: int = int(sim.space.query_counts.static_path_hits)
		if mode=="body_blocker": suite._add_actor(sim,"guide_blocker","S49",[42,80])
		var reserved: String = ""
		if mode=="reserved_goal":
			suite._add_actor(sim,"guide_owner","S49",sim.space.facility_layout(sim.world,"real_guidance").repair_cell)
			reserved = sim.space.reserve_facility(sim.world,"real_guidance","guide_owner","guide_owner")
		var real_reservation: bool = mode!="reserved_goal" or sim.world.facts.adaptations.has("real_guidance") and not sim.space.at(sim.world,"guide_owner",1,goal)
		var requested: String = sim.space.request_move(sim.world,"guide_walker",1,goal)
		var physical: bool = true
		var detour: bool = false
		var unauthorized: bool = false
		var held_before_release: bool = false
		for tick: int in 260:
			if mode=="reserved_goal" and tick==100:
				held_before_release = not sim.space.at(sim.world,"guide_walker",1,goal) and sim.world.facts.moves.has("guide_walker")
				sim.world.facts.actors.guide_owner.location = {"kind":"outside"}
				sim.space.sync_actor(sim.world,"guide_owner")
				sim.world.touch()
			var from: Rect2 = sim.space.body_rectangle(sim.world.facts.actors.guide_walker)
			suite._movement_tick(sim)
			var to: Rect2 = sim.space.body_rectangle(sim.world.facts.actors.guide_walker)
			physical = physical and from.position.distance_to(to.position)<=float(suite.content.balance.movement_speeds["1"])*WorldState.TICK_SECONDS+0.0001
			if mode=="body_blocker":
				var blocker: Rect2 = sim.space.body_rectangle(sim.world.facts.actors.guide_blocker)
				physical = physical and not BodySweep.intersects(from,to,blocker,blocker) and not to.intersects(blocker,false)
				detour = detour or not is_equal_approx(float(sim.world.facts.actors.guide_walker.location.cell[1]),80.0)
			if mode=="reserved_goal" and tick<100: unauthorized = unauthorized or sim.space.at(sim.world,"guide_walker",1,goal)
		var arrived: bool = sim.space.at(sim.world,"guide_walker",1,goal) and not sim.world.facts.moves.has("guide_walker")
		var hit: bool = int(sim.space.query_counts.static_path_hits)>initial_hits
		var ok: bool = prime.ok and requested.is_empty() and reserved.is_empty() and real_reservation and physical and arrived and hit and (mode!="body_blocker" or detour) and (mode!="reserved_goal" or held_before_release and not unauthorized)
		observations.append({"mode":mode,"ok":ok,"arrived":arrived,"dispatch_cache_hit":hit,"physical_sweeps":physical,"body_detour":detour,"reserved_goal_waited":held_before_release,"reservation_exists_with_vacant_goal":real_reservation,"unauthorized_arrival":unauthorized,"final_location":sim.world.facts.actors.guide_walker.location.duplicate(true),"remaining_move":sim.world.facts.moves.get("guide_walker",{}).duplicate(true)})
		sim.dispose()
	var ok: bool = true
	for observation: Dictionary in observations: ok = ok and observation.ok
	return {"ok":ok,"observations":observations}

func _clinical_return(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var desk: CommandResult = suite._command(sim,"build_facility",{"id":"return_guidance","definition_id":"SE01","floor_id":1,"cell":[49,79]})
	var medical: CommandResult = suite._command(sim,"build_facility",{"id":"return_medical","definition_id":"M37","floor_id":1,"cell":[36,87]})
	var desk_goal: Array = sim.space.facility_layout(sim.world,"return_guidance").patient_cell
	var clinical_goal: Array = sim.space.facility_layout(sim.world,"return_medical").patient_cell
	suite._add_actor(sim,"return_walker","S49",clinical_goal)
	var legs: Array = []
	var ok: bool = desk.accepted and medical.accepted and sim.world.validate(suite.content).is_empty()
	for index: int in 4:
		var goal: Array = desk_goal if index%2==0 else clinical_goal
		var hits: int = int(sim.space.query_counts.static_path_hits)
		var builds: int = int(sim.space.query_counts.static_path_builds)
		var requested: String = sim.space.request_move(sim.world,"return_walker",1,goal)
		var physical: bool = true
		var ticks: int = 0
		while ticks<250 and sim.world.facts.moves.has("return_walker"):
			var before: Vector2 = ConvoyTrail.point(sim.world.facts.actors.return_walker.location.cell)
			suite._movement_tick(sim)
			physical = physical and before.distance_to(ConvoyTrail.point(sim.world.facts.actors.return_walker.location.cell))<=float(suite.content.balance.movement_speeds["1"])*WorldState.TICK_SECONDS+0.0001
			ticks+=1
		var arrived: bool = sim.space.at(sim.world,"return_walker",1,goal) and not sim.world.facts.moves.has("return_walker")
		var cache: bool = int(sim.space.query_counts.static_path_builds)==builds+1 if index<2 else int(sim.space.query_counts.static_path_hits)==hits+1 and int(sim.space.query_counts.static_path_builds)==builds
		ok = ok and requested.is_empty() and arrived and physical and cache
		legs.append({"clinical_to_desk":index%2==0,"ticks":ticks,"arrived":arrived,"bounded_real_steps":physical,"expected_build_or_hit":cache})
	var result: Dictionary = {"ok":ok,"legs":legs,"desk_target":desk_goal,"clinical_target":clinical_goal}
	sim.dispose()
	return result
