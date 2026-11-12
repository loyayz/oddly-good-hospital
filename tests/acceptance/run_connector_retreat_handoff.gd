extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _save(path: String, value: Variant) -> void:
	var f:=FileAccess.open(path,FileAccess.WRITE);f.store_var(value,false);f.close()
func _run() -> void:
	var args:=OS.get_cmdline_user_args();var out: String=args[1]
	var f:=FileAccess.open(args[2],FileAccess.READ);var facts: Dictionary=f.get_var(false);f.close()
	var world:=WorldState.new(facts);var content:=HospitalContent.new();var sim:=HospitalSimulation.new(world,content)
	var exact: bool=world.freeze()==facts
	var original_position: Dictionary=world.facts.actors.maintenance_contractor_00000276.location.duplicate(true)
	var original: Dictionary=world.facts.moves.maintenance_contractor_00000276.duplicate(true)
	var before226: Dictionary=world.facts.moves.maintenance_contractor_00000226.duplicate(true)
	_save(out+"/preWorld.bin",facts)
	var rows: Array=[];var events: Array=[];var checks: Dictionary={"cold_input_exact":exact,"restore_equal":true,"owners_preserved":true,"step_budget":true}
	var restored: HospitalSimulation=null;var cold: WorldState=null
	for n: int in range(80):
		var positions: Dictionary={}
		for id: String in ["maintenance_contractor_00000226","maintenance_contractor_00000276"]:positions[id]=world.facts.actors[id].location.duplicate(true)
		var tick: TickResult=sim.step();var ordered: Array=[]
		for e: SimEvent in tick.facts:ordered.append(e.to_record())
		events.append(ordered)
		var move: Dictionary=world.facts.moves.get("maintenance_contractor_00000276",{})
		for key: String in ["request_sequence","owner_job_id","target_floor","target_cell"]:
			if move.get(key)!=original.get(key):checks.owners_preserved=false
		for id: String in positions:
			var now: Dictionary=world.facts.actors[id].location
			if now.kind=="floor" and positions[id].kind=="floor" and now.floor_id==positions[id].floor_id:
				if ConvoyTrail.point(now.cell).distance_to(ConvoyTrail.point(positions[id].cell))>0.2001:checks.step_budget=false
		rows.append({"tick":world.sim_tick,"actor226":world.facts.actors.maintenance_contractor_00000226.duplicate(true),"actor276":world.facts.actors.maintenance_contractor_00000276.duplicate(true),"move226":world.facts.moves.maintenance_contractor_00000226.duplicate(true),"move276":move.duplicate(true),"lift":world.facts.connectors.benchmark_lift.duplicate(true)})
		if n==0:
			var saved: Dictionary=world.freeze();_save(out+"/handoff.bin",saved)
			checks.waypoint_issued=move.has("route_waypoint") or move.get("route_pending",false)
			checks.original_continuation=move.get("route_waypoint",{}).get("continuation",[])==original.path.slice(int(original.cursor))
			checks.retreat_intent_preserved=world.facts.moves.maintenance_contractor_00000226.get("local_move",{})==before226.local_move
			cold=WorldState.new(saved);restored=HospitalSimulation.new(cold,content)
			checks.restore_equal=checks.restore_equal and cold.freeze()==saved
		else:
			var ct: TickResult=restored.step();var ce: Array=[]
			for e: SimEvent in ct.facts:ce.append(e.to_record())
			checks.restore_equal=checks.restore_equal and cold.freeze()==world.freeze() and ce==ordered
		if world.facts.connectors.benchmark_lift.get("trip_sequence",-1)!=65 and ConvoyTrail.point(world.facts.actors.maintenance_contractor_00000226.location.get("cell",[86.4,44])).distance_to(Vector2(86.3999938964844,44))>1.0:break
	checks.trip65_cleared=world.facts.connectors.benchmark_lift.get("trip_sequence",-1)!=65
	checks.worker276_moved=world.facts.actors.maintenance_contractor_00000276.location!=original_position
	_save(out+"/final.bin",world.freeze());_save(out+"/events.bin",events);_save(out+"/frames.bin",rows)
	var passed: bool=true
	for value: Variant in checks.values():passed=passed and bool(value)
	f=FileAccess.open(out+"/result.json",FileAccess.WRITE);f.store_string(JSON.stringify({"passed":passed,"checks":checks,"steps":rows.size(),"tick":world.sim_tick,"last":rows[-1]},"\t"));f.close()
	sim.dispose();if restored!=null:restored.dispose()
	quit(0 if passed else 1)
