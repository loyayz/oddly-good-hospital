extends SceneTree
func _initialize() -> void:call_deferred("_run")
func _save(path: String, value: Variant) -> void:
	var f:=FileAccess.open(path,FileAccess.WRITE);f.store_var(value,false);f.close()
func _run() -> void:
	var args:=OS.get_cmdline_user_args();var out: String=args[1]
	var f:=FileAccess.open(args[2],FileAccess.READ);var input: Dictionary=f.get_var(false);f.close()
	var content:=HospitalContent.new();var world:=WorldState.new(input);var sim:=HospitalSimulation.new(world,content)
	var waiter: Dictionary=world.facts.actors.maintenance_contractor_00000276
	var move: Dictionary=world.facts.moves.maintenance_contractor_00000276
	var retreat: Dictionary=world.facts.actors.maintenance_contractor_00000226
	var journey: Dictionary=world.facts.moves.maintenance_contractor_00000226
	var checks: Dictionary={};var before: Dictionary=world.freeze()
	# Real captured roles: unrelated staff has no matching exit-retreat ownership.
	var staff: Dictionary=world.facts.actors.bench_staff_0025
	checks.unrelated_retreat_rejected=not HospitalTransit.yield_to_retreat(sim.space,world,waiter,move,staff,world.facts.moves.get(staff.id,{}),Vector2.RIGHT) and world.freeze()==before
	checks.floor_owner_rejected=not HospitalTransit.yield_to_retreat(sim.space,world,retreat,journey,waiter,move,Vector2.LEFT) and world.freeze()==before
	var protected_id: String="bench_patient_0115"
	checks.real_transit_protected=not HospitalTransit.yield_to_retreat(sim.space,world,world.facts.actors[protected_id],world.facts.moves[protected_id],retreat,journey,Vector2.RIGHT) and world.freeze()==before
	# Only a real simulation step establishes the positive captured contact.
	var tick: TickResult=sim.step();var events: Array=[]
	for e: SimEvent in tick.facts:events.append(e.to_record())
	_save(out+"/pending.bin",world.freeze());_save(out+"/events.bin",events)
	checks.pending_created=move.get("route_waypoint",{}).has("prefix")
	before=world.freeze()
	checks.duplicate_rejected=not HospitalTransit.yield_to_retreat(sim.space,world,waiter,move,retreat,journey,Vector2.RIGHT) and world.freeze()==before
	checks.pending_validate=world.validate(content).is_empty()
	# Pure malformed-save validation negatives, not claimed legal flow fixtures.
	var malformed: Dictionary=before.duplicate(true)
	malformed.moves[waiter.id].route_waypoint.prefix=[]
	checks.empty_prefix_invalid=not WorldState.new(malformed).validate(content).is_empty()
	for variant: String in ["long","zero","collinear"]:
		var bad: Dictionary=before.duplicate(true)
		var wp: Dictionary=bad.moves[waiter.id].route_waypoint
		var origin: Vector2=ConvoyTrail.point(wp.binding.origin)
		var cells: Array=[[origin.x+4,origin.y]] if variant=="long" else [[origin.x,origin.y]] if variant=="zero" else [[origin.x+1,origin.y],[origin.x+2,origin.y]]
		wp.prefix=[]
		for cell: Array in cells:wp.prefix.append({"kind":"floor","floor_id":1,"cell":cell})
		wp.cell=cells[-1]
		checks[variant+"_prefix_invalid"]=not WorldState.new(bad).validate(content).is_empty()
	# Pure geometry boundary, not a fabricated clinical/transport flow.
	var sample: Dictionary={"id":"orientation_probe","species_id":"S27","posture":"standing","facing":0.0}
	var unchanged: Dictionary=sample.duplicate(true)
	var east: Rect2=HospitalTransit._release_stop_rect(sim.space,sample,Vector2(10,10),Vector2.RIGHT)
	var south: Rect2=HospitalTransit._release_stop_rect(sim.space,sample,Vector2(10,10),Vector2.DOWN)
	checks.non_square_final_orientation=is_equal_approx(east.size.x,0.4) and is_equal_approx(east.size.y,0.6) and is_equal_approx(south.size.x,0.6) and is_equal_approx(south.size.y,0.4) and sample==unchanged
	# Deferred-boundary unit test: stale persisted authority, not a fabricated trip.
	var stale: Dictionary=before.duplicate(true)
	stale.moves[waiter.id].route_waypoint.binding.trip_sequence+=1
	var stale_world:=WorldState.new(stale);var stale_sim:=HospitalSimulation.new(stale_world,content)
	var original_path: Array=stale_world.facts.moves[waiter.id].path.duplicate(true)
	var original_cursor: int=int(stale_world.facts.moves[waiter.id].cursor)
	var original_actor: Dictionary=stale_world.facts.actors[waiter.id].duplicate(true)
	var stale_binding: Dictionary=stale_world.facts.moves[waiter.id].route_waypoint.binding.duplicate(true)
	checks.stale_binding_shape_valid=stale_world.validate(content).is_empty()
	stale_sim.space.movement._dispatch_routes(stale_world,stale_world.present_actor_count())
	var after_stale: Dictionary=stale_world.facts.moves[waiter.id]
	checks.stale_trip_discarded=not after_stale.has("route_waypoint") and not after_stale.get("route_pending",false)
	checks.stale_kept_original=after_stale.path==original_path and int(after_stale.cursor)==original_cursor and stale_world.facts.actors[waiter.id]==original_actor and after_stale.request_sequence==move.request_sequence
	_save(out+"/stale-final.bin",stale_world.freeze())
	stale_sim.dispose()
	# Formal retarget must remove stale waypoint authority, even while pending.
	var request_before: int=int(move.request_sequence)
	var reason: String=sim.space.request_move(world,waiter.id,1,waiter.location.cell.duplicate())
	checks.formal_retarget_accepted=reason.is_empty()
	checks.retarget_cleared_prefix=not world.facts.moves[waiter.id].has("route_waypoint")
	checks.retarget_valid=world.validate(content).is_empty()
	_save(out+"/retarget-final.bin",world.freeze())
	var passed: bool=true
	for value: Variant in checks.values():passed=passed and bool(value)
	f=FileAccess.open(out+"/result.json",FileAccess.WRITE);f.store_string(JSON.stringify({"passed":passed,"checks":checks,"protected_actor":protected_id,"retarget_reason":reason,"original_request":request_before},"\t"));f.close()
	sim.dispose();quit(0 if passed else 1)
