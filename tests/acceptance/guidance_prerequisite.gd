extends RefCounted

# A named boundary before allocation: keep the real stage driver, but dispatch
# only its production guidance gate until every selected patient has arrived.
# No world facts, receipts, actor positions, work counters or time steps are set.
static func reach(sim: HospitalSimulation, visit_ids: Array, tick: Callable, limit: int = 1800) -> Dictionary:
	var world: WorldState = sim.world
	var guide: HospitalFloorGuidance = sim.services.floor_guidance
	var rows: Dictionary = {}
	var selected_actors: Dictionary = {}
	var result: Dictionary = {"ok":false,"started_tick":world.sim_tick,"no_clinical_resources":true,"visits":rows}
	if not world.facts.preparations.is_empty() or not world.facts.sessions.is_empty() or not world.facts.attempts.is_empty():
		result.error = "导诊前提要求尚无临床准备、会话或Attempt"
		return result
	for id: String in visit_ids:
		var visit: Dictionary = world.facts.visits[id]
		selected_actors[visit.actor_id] = id
		var prior: Dictionary = guide.state(world,id)
		rows[id] = {"ticket_id":visit.ticket_id,"initial_location":world.facts.actors[visit.actor_id].location.duplicate(true),"initial_receipts":prior.get("receipts",[]).size(),"work_ticks":0,"real_work":true,"walked":false,"arrived":false,"transitions":[],"last_phase":"","before_work":{}}
	var dispatch_gate: Callable = func() -> void:
		for id: String in visit_ids:
			var visit: Dictionary = world.facts.visits[id]
			var row: Dictionary = rows[id]
			guide.prepare(world,visit,world.facts.tickets[visit.ticket_id])
			var state: Dictionary = guide.state(world,id)
			var phase: String = str(state.get("phase",""))
			if phase!=row.last_phase:
				row.transitions.append({"phase":phase,"tick":world.sim_tick,"location":world.facts.actors[visit.actor_id].location.duplicate(true),"arrived_seq":state.get("arrived_seq",-1)})
				row.last_phase = phase
			row.before_work = {}
			if phase=="working":
				var layout: Dictionary = sim.space.facility_layout(world,str(state.desk_id))
				var nurse: String = str(state.nurse_id)
				row.real_work = row.real_work and sim.space.at(world,visit.actor_id,int(layout.floor_id),layout.patient_cell) and sim.space.at(world,nurse,int(layout.floor_id),layout.operator_cells[0]) and not world.facts.moves.has(visit.actor_id) and not world.facts.moves.has(nurse)
				row.before_work = {"remaining":int(state.remaining_ticks),"receipts":state.receipts.size()}
			if phase=="ready" and not row.arrived:
				var floor_id: int = int(world.facts.facilities[state.target_id].floor_id)
				row.arrived = int(state.arrived_seq)>0 and sim.space.at(world,visit.actor_id,floor_id,state.destination_cell) and not world.facts.moves.has(visit.actor_id) and guide.scope.allows(world,visit.actor_id,str(state.target_id),floor_id,state.destination_cell)
				row.arrival = {"tick":world.sim_tick,"location":world.facts.actors[visit.actor_id].location.duplicate(true),"destination_cell":state.destination_cell.duplicate(),"target_id":state.target_id,"arrived_seq":state.arrived_seq}
	for _index: int in limit:
		tick.call(dispatch_gate)
		result.no_clinical_resources = result.no_clinical_resources and world.facts.preparations.is_empty() and world.facts.sessions.is_empty() and world.facts.attempts.is_empty() and sim.services.supplies.reserved(world)==0
		for id: String in world.facts.adaptations:
			var held: Dictionary = world.facts.adaptations[id]
			# A doorway used by actual movement is not a clinical resource.
			# Only the guidance counter may hold a facility adaptation here.
			if held.get("kind","")=="door":
				continue
			var facility: Dictionary = world.facts.facilities.get(str(held.get("facility_id","")),{})
			var actor_id: String = str(held.get("actor_id",""))
			var visit_id: String = str(selected_actors.get(actor_id,""))
			var waiting_seat: Dictionary = world.facts.waiting_life.seats.get(visit_id,{})
			# One patient may really take a public chair while others are
			# reaching the same clinic. A walking seat target, reservation
			# for another actor, or any clinical device cannot qualify.
			var public_wait: bool = held.get("kind","")=="facility" and not facility.is_empty() and sim.services.waiting._public_seat(world,facility) and held.get("owner_id","")==actor_id and held.get("staff_ids",[]).is_empty() and waiting_seat.get("facility_id","")==id and HospitalWaitingLife.is_seated(world,visit_id)
			if held.get("kind","")!="facility" or (facility.get("definition_id","")!="SE01" and not public_wait):
				result.no_clinical_resources = false
				if not result.has("unexpected_adaptation"):
					result.unexpected_adaptation = {"id":id,"tick":world.sim_tick,"held":held.duplicate(true)}
		var complete: bool = true
		for id: String in visit_ids:
			var visit: Dictionary = world.facts.visits[id]
			var row: Dictionary = rows[id]
			var state: Dictionary = guide.state(world,id)
			row.walked = row.walked or world.facts.actors[visit.actor_id].location!=row.initial_location
			if not row.before_work.is_empty():
				var after: int = int(state.get("remaining_ticks",0))
				if state.get("receipts",[]).size()>int(row.before_work.receipts): after = 0
				var worked: int = int(row.before_work.remaining)-after
				row.real_work = row.real_work and worked==1
				row.work_ticks += worked
			complete = complete and row.arrived
		if complete: break
	result.finished_tick = world.sim_tick
	result.validation = world.validate(sim.content)
	result.ok = result.no_clinical_resources and result.validation.is_empty()
	for id: String in visit_ids:
		var row: Dictionary = rows[id]
		row.state = guide.state(world,id).duplicate(true)
		row.erase("before_work")
		row.erase("last_phase")
		var expected_ticks: int = 60 # Design: six seconds at the unchanged 0.1-second step.
		result.ok = result.ok and row.arrived and row.walked and row.real_work and int(row.work_ticks)==expected_ticks and row.state.get("receipts",[]).size()==int(row.initial_receipts)+1 and world.facts.visits[id].ticket_id==row.ticket_id
	print("GUIDANCE_PREREQUISITE "+JSON.stringify(result))
	return result
