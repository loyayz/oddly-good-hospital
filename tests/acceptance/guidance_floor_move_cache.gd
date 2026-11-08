extends "res://tests/acceptance/guidance_route_cache.gd"

# The same physical/permission cases through guidance's actual floor-only dispatch.
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
		var requested: String = sim.space.request_floor_move(sim.world,"guide_walker",1,goal)
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

