extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var suite=load("res://tests/acceptance/space.gd").new();suite.content=HospitalContent.new()
	var test=load("res://tests/acceptance/guidance_floor_move_cache.gd").new()
	var sim: HospitalSimulation=test.fixture(suite)
	var before: Dictionary=sim.world.freeze()
	sim.space.navigation._observe_floor(sim.world,"guide_first",2)
	var observations: Dictionary=sim.space.navigation._observed_floors
	var observation_values: Dictionary=observations.duplicate(true)
	var first: Dictionary=sim.prepare_floor_static(1)
	var second: Dictionary=sim.prepare_floor_static(1)
	var checks: Dictionary={"multiple_desks":first.guidance_routes.desks==2,"multiple_bodies":first.guidance_routes.body_envelopes>=2,"generated":first.guidance_routes.path_requests>0,"warm_no_builds":second.guidance_routes.path_builds==0,"facts_unchanged":before==sim.world.freeze(),"scope_closed":sim.space._route_queries.is_empty()}
	checks.observations_unchanged=is_same(observations,sim.space.navigation._observed_floors) and observations==observation_values
	var cached: int=int(sim.space.query_counts.static_path_hits)
	var actor: Dictionary=sim.world.facts.actors.guide_first
	var lift: Dictionary=sim.world.facts.connectors[sim.world.ids("connectors").back()]
	var goal: Array=sim.space.facility_layout(sim.world,"guidance_1_0").patient_cell
	var route: Dictionary=sim.space.navigation._floor_route(sim.world,actor,1,Vector2i(lift.anchor[0],lift.anchor[1]),Vector2i(goal[0],goal[1]),[],{},true,{},true)
	checks.actual_consumer_hits=int(sim.space.query_counts.static_path_hits)>cached and route.get("ok",false)
	actor.location={"kind":"floor","floor_id":1,"cell":lift.anchor.duplicate()}
	sim.space.sync_actor(sim.world,actor.id);sim.world.touch()
	var before_dispatch: int=int(sim.space.query_counts.static_path_hits)
	var request: String=sim.space.request_floor_move(sim.world,actor.id,1,goal)
	for tick: int in 260: suite._movement_tick(sim)
	checks.actual_movement_arrives=request.is_empty() and sim.space.at(sim.world,actor.id,1,goal) and not sim.world.facts.moves.has(actor.id)
	checks.actual_movement_cache_hit=int(sim.space.query_counts.static_path_hits)>before_dispatch
	sim.world.facts.floors.overrides["1"].blocked.append(goal.duplicate());sim.world.touch()
	var blocked: Dictionary=sim.space.navigation._floor_route(sim.world,actor,1,Vector2i(lift.anchor[0],lift.anchor[1]),Vector2i(goal[0],goal[1]),[],{},true,{},true)
	checks.preheated_path_invalidated=not blocked.get("ok",false)
	sim.world.facts.floors.overrides["1"].blocked.erase(goal);sim.world.touch()
	sim.space._navigation._trim(0,sim.space.query_counts)
	var rebuilt: Dictionary=sim.space.navigation._floor_route(sim.world,actor,1,Vector2i(lift.anchor[0],lift.anchor[1]),Vector2i(goal[0],goal[1]),[],{},true,{},true)
	checks.eviction_falls_back=rebuilt.get("ok",false)
	sim.dispose()
	var regression: Dictionary=test.run_case(suite)
	var passed: bool=checks.values().all(func(x: Variant)->bool:return bool(x)) and regression.get("ok",regression.get("passed",false))
	var f=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE);f.store_string(JSON.stringify({"passed":passed,"checks":checks,"first":first,"second":second,"regression":regression},"\t"));f.close();quit(0 if passed else 1)
