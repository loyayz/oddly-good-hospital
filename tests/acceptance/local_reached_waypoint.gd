extends "res://tests/acceptance/transit_busy_recovery.gd"

# Completed local motion can physically reach the current original floor
# waypoint before a return intention has been installed. Actual arrival owns
# that handoff; neither passing the point nor intending it earns progress.
func _run() -> void:
	suite.content=HospitalContent.new()
	var rows: Array=[]
	for mode: String in ["terminal","connector","crossing"]:
		rows.append(_reached_current_point(mode))
	var ok: bool=rows.all(func(row: Dictionary)->bool:return row.ok)
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify({"ok":ok,"rows":rows},"\t"))
	print(JSON.stringify({"ok":ok,"rows":rows}))
	quit(0 if ok else 1)

func _reached_current_point(mode: String) -> Dictionary:
	var sim: HospitalSimulation=suite._transit_fixture() if mode=="connector" else suite._fixture()
	var world: WorldState=sim.world
	var point: Array=world.facts.connectors[suite._connection(sim)].anchor.duplicate() if mode=="connector" else [40,70]
	var start: Array=[float(point[0])+(0.4 if mode=="crossing" else 0.6),point[1]]
	var local_target: Array=[float(point[0])-0.6,point[1]] if mode=="crossing" else point.duplicate()
	var goal: Array=[44,82] if mode=="connector" else point.duplicate()
	var floor_id: int=2 if mode=="connector" else 1
	suite._add_actor(sim,"walker","S49",start)
	suite._add_actor(sim,"fixed","S49",[float(point[0])+2,point[1]])
	var path: Array=[{"kind":"floor","floor_id":1,"cell":point.duplicate()}]
	if mode=="connector": path.append_array([{"kind":"connector","connector_id":suite._connection(sim),"from":1,"to":2},{"kind":"floor","floor_id":2,"cell":[44,point[1]]},{"kind":"floor","floor_id":2,"cell":goal.duplicate()}])
	# Legal in-progress local-retreat boundary. No part of the tested retreat,
	# original-point arrival, portal ride or final approach is pre-completed.
	world.facts.move_request_next=1
	world.facts.moves["walker"]={"actor_id":"walker","path":path.duplicate(true),"cursor":0,"travelled":[{"kind":"floor","floor_id":1,"cell":start.duplicate()}],"blocked_since":-1,"target_floor":floor_id,"target_cell":goal.duplicate(),"request_sequence":1,"local_move":{"origin":start.duplicate(),"retreat":true,"target":{"kind":"floor","floor_id":1,"cell":local_target.duplicate()}}}
	world.touch()
	var initial_validation: String=world.validate(suite.content)
	var checks: Dictionary={"legal_input":initial_validation.is_empty()}
	var original_jobs: Dictionary=world.facts.maintenance.duplicate(true)
	var original_tickets: Dictionary=world.facts.tickets.duplicate(true)
	var fixed: Dictionary=world.facts.actors.fixed.duplicate(true)
	var cold: HospitalSimulation=null
	var equal: bool=true
	var safe: bool=true
	var request_kept: bool=true
	var unearned: bool=true
	var crossed: bool=false
	var endpoint_tick: int=-1
	var boarding_tick: int=-1
	var arrived: bool=false
	var trace: Array=[]
	for index: int in 200:
		var before: Dictionary=world.facts.actors.duplicate(true)
		suite._movement_tick(sim)
		if cold!=null:
			suite._movement_tick(cold)
			equal=equal and cold.world.freeze()==world.freeze()
		var actor: Dictionary=world.facts.actors.walker
		var m: Dictionary=world.facts.moves.get("walker",{})
		safe=safe and world.validate(suite.content).is_empty() and _floor_safety(sim,before) and world.facts.actors.fixed==fixed
		if before.walker.location.kind=="floor" and actor.location.kind=="floor" and before.walker.location.floor_id==actor.location.floor_id:
			safe=safe and ConvoyTrail.point(before.walker.location.cell).distance_to(ConvoyTrail.point(actor.location.cell))<=sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001
		if not m.is_empty(): request_kept=request_kept and m.path==path and m.request_sequence==1 and m.target_floor==floor_id and m.target_cell==goal and not m.get("route_pending",false)
		if actor.location.kind=="transit" and boarding_tick<0: boarding_tick=world.sim_tick
		if endpoint_tick<0:
			unearned=unearned and not m.is_empty() and int(m.cursor)==0 and m.has("local_move") and not m.has("transit_ticket") and actor.location.kind=="floor"
			if mode=="crossing" and actor.location.kind=="floor" and ConvoyTrail.point(actor.location.cell)==ConvoyTrail.point(point): crossed=true
			if actor.location.kind=="floor" and ConvoyTrail.point(actor.location.cell)==ConvoyTrail.point(local_target):
				endpoint_tick=world.sim_tick
				var decoded: Dictionary=bytes_to_var(var_to_bytes(world.freeze()))
				cold=HospitalSimulation.new(WorldState.new(decoded),suite.content)
				equal=equal and cold.world.freeze()==world.freeze() and cold.world.validate(suite.content).is_empty()
		if index<10: trace.append({"tick":world.sim_tick,"location":actor.location.duplicate(true),"cursor":m.get("cursor",-1),"local":m.get("local_move",{}).duplicate(true),"ticket":m.get("transit_ticket",{}).duplicate(true)})
		if m.is_empty():
			arrived=sim.space.at(world,"walker",floor_id,goal)
			break
		# Baseline stops at the demonstrated missed handoff, not a long wait.
		if mode!="crossing" and endpoint_tick>=0 and world.sim_tick>endpoint_tick and m.has("local_move") and int(m.cursor)==0: break
	checks.actual_retreat_endpoint=endpoint_tick>0
	checks.no_unearned_cursor_or_ticket=unearned
	checks.crossing_keeps_local_owner=mode!="crossing" or crossed
	checks.original_path_request_goal=request_kept
	checks.cold_continuation=equal and cold!=null
	checks.actual_final_arrival=arrived
	checks.portal_after_real_arrival=mode!="connector" or boarding_tick>endpoint_tick
	checks.real_body_sweep_speed_safety=safe
	checks.business_ownership=world.facts.maintenance==original_jobs and world.facts.tickets==original_tickets
	var result: Dictionary={"ok":_all(checks),"case":mode,"checks":checks,"initial_validation":initial_validation,"final_validation":world.validate(suite.content),"endpoint_tick":endpoint_tick,"boarding_tick":boarding_tick,"final_tick":world.sim_tick,"trace":trace,"remaining":_compact_move(world.facts.moves.get("walker",{}))}
	if cold!=null: cold.dispose()
	sim.dispose()
	return result
