extends RefCounted

const ROUNDING: float=2.0*96.0/8388608.0

func run(suite: RefCounted) -> Dictionary:
	var rows: Array=[]
	for kind: String in ["contractor","visitor"]:
		var prepared: Dictionary=_prepare(suite,kind)
		if not prepared.ok:
			rows.append(prepared)
			continue
		# The original precondition is never changed by either branch. The live
		# branch retains the producer's runtime; the second branch also restores
		# after its last leg has actually reached the exit, before owner dispatch.
		rows.append(_exercise(suite,prepared,prepared.sim,false))
		var restored: HospitalSimulation=HospitalSimulation.new(WorldState.new(prepared.input.duplicate(true)),suite.content)
		rows.append(_exercise(suite,prepared,restored,true))
	var ok: bool=rows.size()==4
	for row: Dictionary in rows: ok=ok and bool(row.ok)
	return {"ok":ok,"rows":rows,"scope":"Actual completed renovation and actual companion admission generate the owners. A declared legal partial local-return input precedes the final physical leg. Every final displacement and both owner departure handoffs execute production steps; no invalid outside/local state or completed movement is supplied."}

func _prepare(suite: RefCounted, kind: String) -> Dictionary:
	var sim: HospitalSimulation=suite._fixture()
	var metadata: Dictionary={"kind":kind,"setup_steps":0,"commands":[]}
	var actor_id: String=""
	var owner_id: String=""
	if kind=="contractor":
		var tool: CommandResult=suite._command(sim,"build_facility",{"id":"departure_tool","definition_id":"SE02","floor_id":1,"cell":[40,78]})
		var order: CommandResult=suite._command(sim,"renovation_order",{"material_id":"MAT01","floor_id":1,"units":[{"cell":[42,80]}]}) if tool.accepted else CommandResult.new(false,"tool_missing",tool.reason)
		metadata.commands=[tool.to_record(),order.to_record()]
		if not order.accepted: return _failed(sim,kind,"Actual renovation input rejected",metadata)
		owner_id=str(order.changed_ids[0])
		for step: int in 800:
			var actual: Dictionary=sim.world.facts.environment.orders[owner_id]
			if actual.phase=="completed": break
			if sim.step()==null: return _failed(sim,kind,"Incomplete setup step",metadata)
			metadata.setup_steps+=1
		var actual: Dictionary=sim.world.facts.environment.orders[owner_id]
		var unit: Dictionary=actual.units[0]
		var contributors: Array=unit.contributions.keys()
		var contributed: int=0
		for amount: int in unit.contributions.values(): contributed+=amount
		if actual.phase!="completed" or contributors.size()!=1 or contributed!=8000 or int(unit.remaining_milli)!=0:
			metadata.order=actual.duplicate(true)
			return _failed(sim,kind,"Actual eight-second renovation did not complete",metadata)
		actor_id=str(contributors[0])
		if sim.world.facts.maintenance.contractors.get(actor_id,{}).get("phase","")!="leaving": return _failed(sim,kind,"Completed construction did not release its real contractor",metadata)
		metadata.completed_renovation=actual.duplicate(true)
		metadata.construction_work_milli=contributed
		metadata.contractor=sim.world.facts.maintenance.contractors[actor_id].duplicate(true)
	else:
		var seat: CommandResult=suite._command(sim,"build_facility",{"id":"departure_public_seat","definition_id":"FUR09","floor_id":1,"cell":[40,84]})
		metadata.commands=[seat.to_record()]
		if not seat.accepted: return _failed(sim,kind,"Actual public seat rejected",metadata)
		# Legal waiting-patient input, before any clinical service. The family
		# itself is not supplied: its original request/admission checks the real
		# entrance, identity, body, public seat and complete route below.
		suite._add_actor(sim,"departure_patient","S49",[44,88])
		var patient: Dictionary=sim.world.facts.actors.departure_patient
		patient.body_binding_id="B_S49_D37_M37"
		var visit: Dictionary={"id":"departure_visit","actor_id":patient.id,"disease_id":"D37","binding_id":"B_S49_D37_M37","requested_plan_id":"P_D37_COMMON","expression":"clear","personality_id":"PP01","anger":15.0,"phase":"arrival","evidence_by_source":{},"attempt_ids":[],"plan_decision":{},"complex":false,"final_result":"","waiting_reason":"","ticket_id":"","doctor_fee_quote":-1,"arrived_tick":sim.world.sim_tick,"arrival_key":"departure_initial_patient","last_progress_tick":sim.world.sim_tick,"last_service_tick":sim.world.sim_tick,"companion_intent":true}
		sim.world.facts.visits[visit.id]=visit
		sim.world.facts.arrival_receipts[visit.arrival_key]=visit.id
		sim.world.register_visit(visit.id)
		sim.world.touch();sim.space.sync_actor(sim.world,patient.id)
		sim.clinic._queue(sim.world,visit,"gp")
		var visitors: HospitalVisitors=sim.clinic.visitors
		visitors._request(sim.world,visit,"companion","")
		var request_id: String=""
		for id: String in sim.world.facts.visitors.requests:
			if sim.world.facts.visitors.requests[id].visit_id==visit.id: request_id=id;break
		if request_id.is_empty() or not visitors._admit(sim.world,visit,sim.world.facts.visitors.requests[request_id]): return _failed(sim,kind,"Original companion admission rejected",metadata)
		sim.world.facts.visitors.requests.erase(request_id)
		actor_id=str(visit.relative_actor_id)
		for id: String in sim.world.facts.visitors.stays:
			if sim.world.facts.visitors.stays[id].actor_id==actor_id: owner_id=id;break
		if owner_id.is_empty(): return _failed(sim,kind,"Admitted family lacks its real stay",metadata)
		metadata.admitted_companion=sim.world.facts.actors[actor_id].duplicate(true)
		var entrance: Vector2=ConvoyTrail.point(sim.world.facts.entry.cell)
		var exit: Vector2=ConvoyTrail.point(sim.space.exit_cell(sim.world,sim.world.facts.actors[actor_id]))
		var cleared_entry: bool=false
		for step: int in 500:
			var actor: Dictionary=sim.world.facts.actors[actor_id]
			if actor.location.kind=="floor":
				var actual: Vector2=ConvoyTrail.point(actor.location.cell)
				if actual.distance_to(entrance)>=2.0 and actual.distance_to(exit)>=2.0: cleared_entry=true;break
			if sim.step()==null: return _failed(sim,kind,"Incomplete companion walking step",metadata)
			metadata.setup_steps+=1
		metadata.actual_companion_stay=sim.world.facts.visitors.stays.get(owner_id,{}).duplicate(true)
		metadata.actual_companion_pose=sim.world.facts.actors[actor_id].duplicate(true)
		metadata.original_public_route=sim.world.facts.moves.get(actor_id,{}).duplicate(true)
		metadata.cleared_entry_and_exit_by_two_cells=cleared_entry
		if not cleared_entry: return _failed(sim,kind,"Real companion did not walk clear of the entrance and exit",metadata)
		var referred: CommandResult=suite._command(sim,"clinical_refer",{"visit_id":visit.id})
		metadata.commands.append(referred.to_record())
		if not referred.accepted: return _failed(sim,kind,"Original patient referral rejected",metadata)
	# The task owns a genuine departure. Stop before a final, still uncompleted
	# route leg; do not relocate any actor or edit work/time/route checkpoints.
	var goal: Array=sim.space.exit_cell(sim.world,sim.world.facts.actors[actor_id])
	var declared: bool=false
	for step: int in 800:
		var actor: Dictionary=sim.world.facts.actors[actor_id]
		if actor.location.kind!="floor": return _failed(sim,kind,"Owner left before the selected input boundary",metadata)
		var move: Dictionary=sim.world.facts.moves.get(actor_id,{})
		var distance: float=ConvoyTrail.point(actor.location.cell).distance_to(ConvoyTrail.point(goal))
		if not move.is_empty() and not move.get("route_pending",false) and not move.has("convoy") and not move.has("members") and not move.has("detour") and not move.has("route_waypoint") and distance>=0.35 and distance<=1.0:
			var index: int=move.path.size()-1
			if index>=int(move.cursor) and move.path[index].kind=="floor" and int(move.path[index].floor_id)==1 and ConvoyTrail.point(move.path[index].cell)==ConvoyTrail.point(goal):
				move.local_move={"origin":actor.location.cell.duplicate(),"target":{"kind":"floor","floor_id":1,"cell":goal.duplicate()},"rejoin":{"index":index,"cell":goal.duplicate()}}
				declared=true;break
		if sim.step()==null: return _failed(sim,kind,"Incomplete real departure approach",metadata)
		metadata.setup_steps+=1
	if not declared: return _failed(sim,kind,"No lawful final local-leg input boundary",metadata)
	var validation: String=sim.world.validate(suite.content)
	metadata.input_validation=validation
	metadata.local_input="Declared legal partial return only; original path, cursor, request sequence, travelled checkpoints, actor pose and completed work retained."
	if not validation.is_empty(): return _failed(sim,kind,"Invalid partial local input",metadata)
	return {"ok":true,"sim":sim,"input":sim.world.freeze(),"kind":kind,"actor_id":actor_id,"owner_id":owner_id,"goal":goal,"metadata":metadata}

func _exercise(suite: RefCounted, prepared: Dictionary, sim: HospitalSimulation, restore_at_arrival: bool) -> Dictionary:
	var trace: Array=[]
	var errors: Array=[]
	var actor_id: String=prepared.actor_id
	var original_move: Dictionary=sim.world.facts.moves[actor_id].duplicate(true)
	var sequence: int=int(original_move.request_sequence)
	var ledger: Dictionary=sim.world.facts.ledger.duplicate(true)
	var orders: Dictionary=sim.world.facts.environment.orders.duplicate(true)
	var receipts: Dictionary=sim.world.facts.environment.receipts.duplicate(true)
	var inventory: Dictionary=sim.world.facts.inventory.duplicate(true)
	var arrival: bool=false
	var original: bool=true
	for step: int in 30:
		var actor: Dictionary=sim.world.facts.actors[actor_id]
		if actor.location.kind=="floor" and ConvoyTrail.point(actor.location.cell)==ConvoyTrail.point(prepared.goal): arrival=true;break
		_observe(suite,sim,actor_id,trace,errors)
		var move: Dictionary=sim.world.facts.moves.get(actor_id,{})
		original=original and not move.is_empty() and int(move.get("request_sequence",-1))==sequence and move.get("target_cell",[])==prepared.goal
		if not errors.is_empty(): break
	var arrived_move: Dictionary=sim.world.facts.moves.get(actor_id,{}).duplicate(true)
	var pending_local: bool=arrival and arrived_move.has("local_move") and arrived_move.local_move.has("rejoin") and int(arrived_move.cursor)<arrived_move.path.size() and sim.space.movement._target_checkpoint_reached(arrived_move)
	var arrival_validation: String=sim.world.validate(suite.content)
	var restored_equal: bool=true
	if pending_local and restore_at_arrival:
		var source: Dictionary=sim.world.freeze()
		var replacement: HospitalSimulation=HospitalSimulation.new(WorldState.new(source.duplicate(true)),suite.content)
		restored_equal=replacement.world.freeze()==source and replacement.world.validate(suite.content).is_empty()
		sim.dispose();sim=replacement
	var handed_off: bool=false
	var stable: bool=true
	if pending_local and arrival_validation.is_empty() and errors.is_empty():
		for step: int in 4:
			_observe(suite,sim,actor_id,trace,errors)
			var outside: bool=sim.world.facts.actors[actor_id].location.kind=="outside"
			var retired: bool=not sim.world.facts.moves.has(actor_id) and not sim.space.movement._pending_routes.has(actor_id) and not sim.space.movement._route_checks.has(actor_id) and not sim.space.movement._route_failures.has(actor_id)
			var owner_done: bool=sim.world.facts.maintenance.contractors.get(actor_id,{}).get("phase","")=="departed" if prepared.kind=="contractor" else not sim.world.facts.visitors.stays.has(prepared.owner_id)
			if step==0: handed_off=outside and retired and owner_done
			stable=stable and outside and retired and owner_done
	var accounts: bool=sim.world.facts.ledger==ledger and sim.world.facts.environment.orders==orders and sim.world.facts.environment.receipts==receipts and sim.world.facts.inventory==inventory
	var validation: String=sim.world.validate(suite.content)
	var checks: Dictionary={"real_final_leg":arrival and trace.size()>0,"original_goal_sequence":original,"pending_local_rejoin_at_real_exit":pending_local,"legal_arrival_boundary":arrival_validation.is_empty(),"cold_restore_exact":restored_equal,"owner_retires_move_before_outside":handed_off,"no_resurrection_over_four_steps":stable,"original_accounts_work_receipts_and_inventory":accounts,"bounded_actual_body_sweeps":errors.is_empty(),"final_validation":validation.is_empty()}
	var ok: bool=true
	for value: bool in checks.values(): ok=ok and value
	var row: Dictionary={"ok":ok,"kind":prepared.kind,"restore_at_real_arrival":restore_at_arrival,"checks":checks,"setup":prepared.metadata,"actor_id":actor_id,"owner_id":prepared.owner_id,"goal":prepared.goal,"initial_move":original_move,"arrived_move":arrived_move,"arrival_validation":arrival_validation,"errors":errors,"final_validation":validation,"final_actor":sim.world.facts.actors[actor_id].duplicate(true),"final_movement":sim.world.facts.moves.get(actor_id,{}).duplicate(true),"trace":trace}
	sim.dispose();return row

func _observe(suite: RefCounted, sim: HospitalSimulation, actor_id: String, trace: Array, errors: Array) -> void:
	var before: Dictionary={}
	for id: String in sim.world.facts.actors:
		var actor: Dictionary=sim.world.facts.actors[id]
		if actor.location.kind=="floor": before[id]={"cell":actor.location.cell.duplicate(),"rect":sim.space.body_rectangle(actor)}
	var tick: int=sim.world.sim_tick
	if sim.step()==null: errors.append("Incomplete production step");return
	if sim.world.sim_tick!=tick+1: errors.append("Changed fixed tick")
	for id: String in before:
		var actor: Dictionary=sim.world.facts.actors[id]
		if actor.location.kind!="floor": continue
		var after: Rect2=sim.space.body_rectangle(actor)
		var distance: float=ConvoyTrail.point(before[id].cell).distance_to(ConvoyTrail.point(actor.location.cell))
		if distance>sim.space.walking_speed(actor)*WorldState.TICK_SECONDS+ROUNDING: errors.append("Walking budget exceeded: "+id)
		for other: String in before:
			if other==id or sim.world.facts.actors[other].location.kind!="floor": continue
			var end: Rect2=sim.space.body_rectangle(sim.world.facts.actors[other])
			if after.intersects(end,false) or BodySweep.intersects(before[id].rect,after,before[other].rect,end): errors.append("Actual body or sweep overlap: "+id+"/"+other)
	var validation: String=sim.world.validate(suite.content)
	if not validation.is_empty(): errors.append(validation)
	trace.append({"tick":sim.world.sim_tick,"actor_location":sim.world.facts.actors[actor_id].location.duplicate(true),"movement":sim.world.facts.moves.get(actor_id,{}).duplicate(true)})

func _failed(sim: HospitalSimulation, kind: String, reason: String, metadata: Dictionary) -> Dictionary:
	var result: Dictionary={"ok":false,"kind":kind,"reason":reason,"setup":metadata,"tick":sim.world.sim_tick,"validation":sim.world.validate(sim.content)}
	sim.dispose();return result
