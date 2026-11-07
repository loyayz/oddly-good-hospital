extends "res://tests/acceptance/guidance_desk_ownership.gd"

func run_participation(database: HospitalContent, selected: Array = []) -> Dictionary:
	_content = database
	var runs: Dictionary = {"GUIDE-DESK-INVENTORY-MOVE":_participation.bind("inventory"),"GUIDE-DESK-DIRECT-MOVE":_participation.bind("move"),"GUIDE-DESK-INVENTORY-SAME-PLACE":_participation.bind("same"),"GUIDE-DESK-LIFE-LOCAL-PAUSE":_participation.bind("life"),"GUIDE-DESK-PRIORITY-LIVE-STATE":_participation.bind("first")}
	var rows: Array = []
	for id: String in (runs.keys() if selected.is_empty() else selected):
		if not runs.has(id): return {"ok":false,"error":"unknown case "+id}
		rows.append(runs[id].call())
	return {"ok":not rows.any(func(row: Dictionary)->bool:return not row.get("ok",false)),"cases":rows}

func _participation(mode: String) -> Dictionary:
	var x: Dictionary = _base()
	var moved: bool = mode in ["inventory","move","first"]
	var anchor: Array = [55,83] if moved else [47,83]
	# Legal input position before any measured movement. The off-duty nurse
	# is near the future location, but must still really walk onto its post.
	_position(x,"guide_nurse",[anchor[0],81])
	if mode=="life": _facility(x,"water","FUR17",[54,89])
	x.m.ensure(x.world)
	var rest: CommandResult = x.s.execute(x.world,"apply_schedule",{"changes":[{"staff_id":"guide_nurse","schedule":_desk_schedule(true)}]})
	var old: Dictionary = _visit(x,"old",[40,88])
	var old_ticket: String = old.ticket_id
	x.world.touch()
	var input_validation: String = x.world.validate(_content)
	for tick: int in 600:
		_scheduled_step(x)
		if x.g.state(x.world,old.id).get("phase","")=="desk_queue": break
	var old_waited: int = int(x.world.facts.tickets[old_ticket].waited_ticks)
	var old_state: Dictionary = x.g.state(x.world,old.id).duplicate(true)
	var old_location: Dictionary = x.world.facts.actors[old.actor_id].location.duplicate(true)
	var initial_queue: bool = old_state.get("phase","")=="desk_queue" and not x.world.facts.adaptations.has("guide") and not x.world.facts.moves.has(old.actor_id)
	var use_ticks: int = 0
	var actual_use: bool = mode!="life"
	if mode=="life":
		var clock: Dictionary = x.world.facts.waiting_life.clocks.old
		clock.next_purpose = "water";clock.next_need_tick = x.world.sim_tick
		for tick: int in 600:
			_scheduled_step(x)
			var need: Dictionary = x.world.facts.waiting_life.needs.get(old.id,{})
			if need.get("phase","")=="using":
				var layout: Dictionary = x.space.facility_layout(x.world,"water")
				actual_use = need.facility_id=="water" and x.space.at(x.world,old.actor_id,1,layout.patient_cell) and not x.world.facts.moves.has(old.actor_id)
				use_ticks += 1;break
	var commands: Array = []
	var paused_tick: int = x.world.sim_tick
	var no_dispatch_between_commands: bool = true
	if mode!="life":
		# This is the same normal command surface used by the paused UI.
		# Inventory placement supplies inventory_id, never a custom new id.
		var simulation: HospitalSimulation = HospitalSimulation.new(x.world,_content)
		if mode in ["inventory","same","first"]:
			var store: CommandResult = simulation.apply(GameCommand.new("participation_store",x.world.hospital_id,x.world.revision,"build_store",BusinessPayload.new({"target_id":"guide"})))
			commands.append(store.to_record())
			no_dispatch_between_commands = no_dispatch_between_commands and x.world.sim_tick==paused_tick and x.g.state(x.world,old.id)==old_state and x.world.facts.inventory.build_items.has("guide")
			var place: CommandResult = simulation.apply(GameCommand.new("participation_place",x.world.hospital_id,x.world.revision,"build_facility",BusinessPayload.new({"inventory_id":"guide","definition_id":"SE01","cell":anchor,"floor_id":1})))
			commands.append(place.to_record())
		else:
			var move: CommandResult = simulation.apply(GameCommand.new("participation_move",x.world.hospital_id,x.world.revision,"build_move",BusinessPayload.new({"target_id":"guide","cell":anchor,"floor_id":1})))
			commands.append(move.to_record())
		no_dispatch_between_commands = no_dispatch_between_commands and x.world.sim_tick==paused_tick and x.g.state(x.world,old.id)==old_state and x.world.facts.actors[old.actor_id].location==old_location
		simulation.dispose()
	var accepted: bool = not commands.any(func(row: Dictionary)->bool:return not row.accepted)
	var same_identity: bool = x.world.facts.facilities.has("guide") and not x.world.facts.inventory.build_items.has("guide") and x.world.facts.facilities.guide.cell==anchor
	var post_command_validation: String = x.world.validate(_content)
	var near: Dictionary = _visit(x,"near",[anchor[0]+(2 if mode=="first" else 3),85])
	var enabled: CommandResult = x.s.execute(x.world,"apply_schedule",{"changes":[{"staff_id":"guide_nurse","schedule":_desk_schedule(false)}]})
	var live_before_old_prepare: bool = mode!="first"
	var first_prepare: Dictionary = {}
	if mode=="first":
		# Separate callback-order boundary: this new patient is already at a
		# legal new-domain queue point in the input. The old patient's row and
		# old position have not had any prepare/dispatch turn since the move.
		x.s.boundaries(x.world);x.g.dispatch(x.world)
		var old_unchanged: bool = x.g.state(x.world,old.id)==old_state and x.world.facts.actors[old.actor_id].location==old_location and not x.world.facts.moves.has(old.actor_id)
		x.g.prepare(x.world,near,x.world.facts.tickets[near.ticket_id])
		var near_state: Dictionary = x.g.state(x.world,near.id)
		live_before_old_prepare = old_unchanged and near_state.get("phase","")=="to_counter"
		first_prepare = {"old_row_not_processed":old_unchanged,"old_location":old_location,"old_queue_cell":old_state.queue_cell,"new_patient_location":x.world.facts.actors[near.actor_id].location.duplicate(true),"new_state":near_state.duplicate(true)}
	var first_service: String = ""
	var first_service_snapshot: Dictionary = {}
	var near_claimed_while_old_away: bool = false
	var near_worked_while_old_away: bool = false
	var retained_number: bool = true
	var actual_work: bool = true
	var valid: bool = true
	var no_overlap: bool = true
	var first_old_return_tick: int = -1
	var trace: Array = []
	for tick: int in 1200:
		_scheduled_step(x)
		var a: Dictionary = x.g.state(x.world,old.id)
		var b: Dictionary = x.g.state(x.world,near.id)
		var actor: Dictionary = x.world.facts.actors[old.actor_id]
		var away: bool = not a.has("queue_cell") or not x.g.scope.allows(x.world,old.actor_id,"guide",1,actor.location.cell) or not x.space.at(x.world,old.actor_id,1,a.queue_cell) or x.world.facts.moves.has(old.actor_id) or x.world.facts.waiting_life.needs.has(old.id)
		if not away and first_old_return_tick<0: first_old_return_tick = x.world.sim_tick
		if a.has("queue_seq"): retained_number = retained_number and int(a.queue_seq)==int(old_state.queue_seq)
		if b.get("phase","") in ["to_counter","working"] and away and a.receipts.is_empty() and not a.get("phase","") in ["to_counter","working"]: near_claimed_while_old_away = true
		if b.get("phase","")=="working" and away and a.receipts.is_empty() and not a.get("phase","") in ["to_counter","working"]: near_worked_while_old_away = true
		if first_service.is_empty():
			for row: Dictionary in [a,b]:
				if row.get("phase","")=="working":
					first_service = str(row.visit_id)
					first_service_snapshot = {"tick":x.world.sim_tick,"old_location":actor.location.duplicate(true),"old":a.duplicate(true),"near":b.duplicate(true),"old_away":away}
		if x.g.worked_staff().has("guide_nurse"):
			var who: String = str(a.visit_id) if a.get("phase","")=="working" or not a.receipts.is_empty() and int(a.receipts.back().completed_tick)==x.world.sim_tick-1 else str(b.visit_id)
			var layout: Dictionary = x.space.facility_layout(x.world,"guide")
			actual_work = actual_work and x.space.at(x.world,"guide_nurse",1,layout.operator_cells[0]) and x.space.at(x.world,x.world.facts.visits[who].actor_id,1,layout.patient_cell)
		if mode=="life":
			var need: Dictionary = x.world.facts.waiting_life.needs.get(old.id,{})
			if need.get("phase","")=="using":
				use_ticks += 1
				actual_use = actual_use and need.facility_id=="water" and x.space.at(x.world,old.actor_id,1,x.space.facility_layout(x.world,"water").patient_cell) and not x.world.facts.moves.has(old.actor_id)
		valid = valid and x.world.validate(_content).is_empty()
		var ids: Array = [old.actor_id,near.actor_id,"guide_nurse"]
		for i: int in ids.size():
			for j: int in range(i+1,ids.size()): no_overlap = no_overlap and not x.space.body_rectangle(x.world.facts.actors[ids[i]]).intersects(x.space.body_rectangle(x.world.facts.actors[ids[j]]),false)
		if trace.is_empty() or trace.back().old_phase!=a.get("phase","") or trace.back().near_phase!=b.get("phase",""):
			trace.append({"tick":x.world.sim_tick,"old_phase":a.get("phase",""),"near_phase":b.get("phase",""),"old_away":away,"old_seq":a.get("queue_seq",-1),"near_seq":b.get("queue_seq",-1),"near_reason":near.waiting_reason})
		if a.get("phase","")=="ready" and b.get("phase","")=="ready": break
	var final_a: Dictionary = x.g.state(x.world,old.id)
	var final_b: Dictionary = x.g.state(x.world,near.id)
	var complete: bool = final_a.get("phase","")=="ready" and final_b.get("phase","")=="ready" and final_a.receipts.size()==1 and final_b.receipts.size()==1
	var same_ticket: bool = x.world.facts.visits[old.id].ticket_id==old_ticket and x.world.facts.tickets.has(old_ticket)
	var wait_kept: bool = same_ticket and int(x.world.facts.tickets[old_ticket].waited_ticks)>=old_waited
	var expected_order: bool = first_service==("old" if mode=="same" else "near")
	var local_priority: bool = not near_claimed_while_old_away if mode=="same" else near_claimed_while_old_away and near_worked_while_old_away
	var row: Dictionary = {"case":{"inventory":"GUIDE-DESK-INVENTORY-MOVE","move":"GUIDE-DESK-DIRECT-MOVE","same":"GUIDE-DESK-INVENTORY-SAME-PLACE","life":"GUIDE-DESK-LIFE-LOCAL-PAUSE","first":"GUIDE-DESK-PRIORITY-LIVE-STATE"}[mode],"ok":rest.accepted and initial_queue and input_validation.is_empty() and post_command_validation.is_empty() and accepted and no_dispatch_between_commands and same_identity and enabled.accepted and complete and expected_order and local_priority and live_before_old_prepare and retained_number and actual_work and actual_use and (mode!="life" or use_ticks>=79) and valid and no_overlap and same_ticket and wait_kept,"input_validation":input_validation,"post_command_validation":post_command_validation,"initial_real_queue":initial_queue,"commands":commands,"paused_tick_unchanged_no_dispatch":no_dispatch_between_commands,"same_physical_id":same_identity,"expected_first_service":expected_order,"first_service":first_service,"first_service_snapshot":first_service_snapshot,"near_claimed_while_old_away":near_claimed_while_old_away,"near_worked_while_old_away":near_worked_while_old_away,"same_desk_number_retained":retained_number,"eligibility_before_old_prepare":live_before_old_prepare,"first_prepare":first_prepare,"actual_staff_and_patient_work":actual_work,"actual_water_use":actual_use,"water_observed_ticks":use_ticks,"all_boundaries_valid":valid,"no_body_overlap":no_overlap,"same_clinical_ticket":same_ticket,"accumulated_wait_preserved":wait_kept,"waited_ticks_before":old_waited,"waited_ticks_after":x.world.facts.tickets.get(old_ticket,{}).get("waited_ticks",-1),"both_services_completed_once":complete,"old_receipts":final_a.receipts.duplicate(true),"near_receipts":final_b.receipts.duplicate(true),"first_old_local_return_tick":first_old_return_tick,"trace":trace}
	_dispose(x);return row
