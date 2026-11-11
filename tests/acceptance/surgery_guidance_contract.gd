extends "res://tests/acceptance/clinical_fixtures.gd"

func run_case(database: HospitalContent) -> Dictionary:
	_content = database
	var started: int = Time.get_ticks_msec()
	var c: Dictionary = _hospital_input()
	var guidance: HospitalFloorGuidance = c.sim.services.floor_guidance
	var desks_ready: bool = false
	for index: int in 1600:
		_tick(c)
		if guidance._available_desks(c.world,1).size()==1 and guidance._available_desks(c.world,2).size()==1:
			desks_ready = true
			break
	var input_validation: String = c.world.validate(_content)
	var checks: Dictionary = {"legal_hospital":input_validation.is_empty(),"all_base_load_retained":c.original_load_retained,"both_nurses_really_posted":desks_ready,"original_nurse_preparation":c.nursing_handoff_ticks.get("starter_nurse",0)==60 and c.nursing_handoff_ticks.get("starter_guide_nurse",0)==60 and c.nursing_handoff_not_at_base.is_empty(),"world_valid":true,"real_bodies":true,"exact_original_candidate_list":false,"closed_and_unstaffed_still_candidates":false,"clinical_quote_rejects_unqualified":false,"initial_random_uses_original_list":false,"first_guidance_full_work":false,"second_guidance_full_work":false,"patient_really_crossed_floors":false,"original_or_preserved":true,"no_destination_desk_reroll":false,"arrival_order_only_on_actual_arrival":true,"arrival_registered_once":false,"real_or_waiting_point":false,"cold_restore":false,"no_clinical_commitment_or_extra_charge":false}
	if not desks_ready or not input_validation.is_empty(): return _finish_contract(c,checks,{"phase":"guide_prerequisite","validation":input_validation,"setup_ms":Time.get_ticks_msec()-started})
	# Declared legal boundary: the previous GP/consultation is input. Only the
	# new surgical referral's guidance, travel and actual arrival are exercised.
	if not _arrive(c,"B_S13_D09_M09","P_D09_SURGERY"): return _finish_contract(c,checks,{"phase":"declared_referral","fixture_errors":_fixture_failures})
	var visit: Dictionary = _visit(c)
	visit.evidence_by_source = {"gp":40.0}
	visit.doctor_fee_quote = 20
	visit.plan_decision = {"plan_id":"P_D09_SURGERY","source":"director","revision":1,"probability_bp":9600}
	HospitalLedger.post(c.world,LedgerEntry.new(visit.id,"consultation",20))
	HospitalLedger.post(c.world,LedgerEntry.new(visit.id,"gp",5))
	c.sim.clinic._queue(c.world,visit,"surgery")
	c.world.touch(false)
	var ticket: Dictionary = c.world.facts.tickets[visit.ticket_id]
	var ticket_id: String = str(ticket.id)
	var actor_id: String = str(visit.actor_id)
	var expected_ids: Array = c.world.facility_ids("EQ01")
	checks.exact_original_candidate_list = expected_ids==["a_table_upstairs","z_table_downstairs"] and guidance._target_ids(c.world,visit,"surgery")==expected_ids and guidance._target_ids(c.world,visit,"surgery","a_table_upstairs")==["a_table_upstairs"]
	c.world.facts.facilities.z_table_downstairs.open = false
	c.world.facts.facilities.z_table_downstairs.intake_open = false
	c.world.touch(false)
	var closed_quote: Dictionary = c.sim.clinic._surgery_quote(c.world,visit,[],{"facility_id":"z_table_downstairs"})
	checks.closed_and_unstaffed_still_candidates = guidance._target_ids(c.world,visit,"surgery")==expected_ids
	c.world.facts.facilities.z_table_downstairs.open = true
	c.world.facts.facilities.z_table_downstairs.intake_open = true
	c.world.touch(false)
	var unstaffed_quote: Dictionary = c.sim.clinic._surgery_quote(c.world,visit,[],{"facility_id":"a_table_upstairs"})
	checks.clinical_quote_rejects_unqualified = not closed_quote.get("ok",true) and not unstaffed_quote.get("ok",true) and c.world.facts.preparations.is_empty() and c.world.facts.attempts.is_empty()
	# Pick the initial input seed with the same native generator and bounds.
	# The first draw chooses the sole 1F desk, the next chooses an OR table.
	var initial_rng: Dictionary = _upstairs_seed(expected_ids)
	c.world.facts.rng.guidance = initial_rng.duplicate(true)
	var setup_ms: int = Time.get_ticks_msec()-started
	var input: Dictionary = {"kind":"diagnosed_confirmed_wait_surgery","tick":c.world.sim_tick,"validation":c.world.validate(_content),"patient_floor":1,"expected_or":"a_table_upstairs","candidate_ids":expected_ids,"staff":c.world.facts.staff.size(),"facilities":c.world.facts.facilities.size(),"base_staff":c.base_staff,"base_facilities":c.base_facilities,"initial_guidance_rng":initial_rng,"body_input_sha256":_facts_hash(c.world.freeze()),"prior_bill":_income(c),"prior_supply_units":_units_used(c)}
	var body_started: int = Time.get_ticks_msec()
	var observations: Dictionary = {"first_or":"","first_guidance_ticks":0,"second_guidance_ticks":0,"completion_rng_before":{},"completion_rng_after":{},"cross_floor_move":{},"restored":{},"arrival_seq":-1,"arrival_counter":-1,"arrival_tick":-1,"second_completion_tick":-1}
	var errors: Array = []
	var reached: bool = false
	for index: int in 2600:
		guidance = c.sim.services.floor_guidance
		var before: Dictionary = guidance.state(c.world,c.visit_id).duplicate(true)
		var before_rng: Dictionary = c.world.facts.rng.guidance.duplicate(true)
		var before_remaining: int = int(before.get("remaining_ticks",0))
		var second_last_tick: bool = before.get("phase","")=="working" and int(before.get("guide_floor",0))==2 and before_remaining==1
		if before.get("phase","")=="ready":
			reached = true
			break
		checks.arrival_order_only_on_actual_arrival = checks.arrival_order_only_on_actual_arrival and int(before.get("arrived_seq",-1))==-1
		_tick(c)
		guidance = c.sim.services.floor_guidance
		var current: Dictionary = guidance.state(c.world,c.visit_id)
		var phase: String = str(current.get("phase",""))
		var validation: String = c.world.validate(_content)
		var overlap: Array = _body_overlap(c)
		checks.world_valid = checks.world_valid and validation.is_empty()
		checks.real_bodies = checks.real_bodies and overlap.is_empty()
		if not validation.is_empty() or not overlap.is_empty(): errors.append({"tick":c.world.sim_tick,"validation":validation,"overlap":overlap}); break
		if before.get("phase","")=="working":
			var advanced: int = before_remaining-int(current.get("remaining_ticks",0))
			if phase!="working": advanced = before_remaining
			var field: String = "first_guidance_ticks" if int(before.guide_floor)==1 else "second_guidance_ticks"
			observations[field] += advanced
		elif phase=="working":
			var field: String = "first_guidance_ticks" if int(current.guide_floor)==1 else "second_guidance_ticks"
			observations[field] += 60-int(current.remaining_ticks)
		if observations.first_or=="" and str(current.get("target_id","")).is_empty()==false:
			observations.first_or = str(current.target_id)
			checks.initial_random_uses_original_list = observations.first_or=="a_table_upstairs"
		if observations.first_or!="": checks.original_or_preserved = checks.original_or_preserved and current.get("target_id","")==observations.first_or
		if second_last_tick:
			observations.completion_rng_before = before_rng
			observations.completion_rng_after = c.world.facts.rng.guidance.duplicate(true)
			observations.second_completion_tick = c.world.sim_tick
			checks.no_destination_desk_reroll = before_rng==c.world.facts.rng.guidance and current.get("target_id","")=="a_table_upstairs"
		var move: Dictionary = c.world.facts.moves.get(actor_id,{})
		if observations.restored.is_empty() and c.world.facts.actors[actor_id].location.kind=="transit" and move.get("floor_guidance_key","")==current.get("request_key",""):
			var facts: Dictionary = c.world.freeze()
			var original_target: String = str(current.target_id)
			var original_ticket: Dictionary = c.world.facts.tickets[ticket_id].duplicate(true)
			var original_move: Dictionary = move.duplicate(true)
			var original_rng: Dictionary = c.world.facts.rng.guidance.duplicate(true)
			observations.cross_floor_move = original_move
			observations.restored = _roundtrip(c)
			guidance = c.sim.services.floor_guidance
			checks.cold_restore = observations.restored.get("ok",false) and c.world.freeze()==facts and c.world.facts.tickets.get(ticket_id,{})==original_ticket and c.world.facts.moves.get(actor_id,{})==original_move and c.world.facts.rng.guidance==original_rng and guidance.target(c.world,c.visit_id)==original_target
			checks.patient_really_crossed_floors = checks.cold_restore
			if not checks.cold_restore: errors.append({"restore":observations.restored}); break
		if phase=="ready":
			observations.arrival_seq = int(current.arrived_seq)
			observations.arrival_counter = int(c.world.facts.floor_guidance.next_arrival)
			observations.arrival_tick = c.world.sim_tick
			checks.real_or_waiting_point = int(c.world.facts.actors[actor_id].location.floor_id)==2 and not c.world.facts.moves.has(actor_id) and c.sim.space.at(c.world,actor_id,2,current.destination_cell) and guidance.scope.allows(c.world,actor_id,"a_table_upstairs",2,current.destination_cell)
			reached = true
			break
		checks.arrival_order_only_on_actual_arrival = checks.arrival_order_only_on_actual_arrival and int(current.get("arrived_seq",-1))==-1
	checks.first_guidance_full_work = int(observations.first_guidance_ticks)==60
	checks.second_guidance_full_work = int(observations.second_guidance_ticks)==60
	if reached:
		var order: int = int(guidance.state(c.world,c.visit_id).arrived_seq)
		var counter: int = int(c.world.facts.floor_guidance.next_arrival)
		for index: int in 5: _tick(c)
		checks.arrival_registered_once = order>0 and guidance.state(c.world,c.visit_id).get("arrived_seq",-1)==order and int(c.world.facts.floor_guidance.next_arrival)==counter
	checks.no_clinical_commitment_or_extra_charge = c.world.facts.preparations.is_empty() and c.world.facts.sessions.is_empty() and c.world.facts.attempts.is_empty() and _income(c)==int(input.prior_bill) and _units_used(c)==int(input.prior_supply_units) and _visit(c).ticket_id==ticket_id
	return _finish_contract(c,checks,{"setup_ms":setup_ms,"body_ms":Time.get_ticks_msec()-body_started,"input":input,"observed":observations,"closed_quote":closed_quote,"unstaffed_quote":unstaffed_quote,"errors":errors,"guidance_receipts":guidance.state(c.world,c.visit_id).get("receipts",[]),"final_tick":c.world.sim_tick})

func _hospital_input() -> Dictionary:
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"手术跨层导诊验收",true,_content)
	var original_facilities: Dictionary = world.facts.facilities.duplicate(true)
	var original_staff: Array = world.ids("staff")
	world.facts.floors.height_intervals = [{"first":1,"last":2,"height_m":float(_content.balance.floors.clear_height_m)}]
	world.facts.floors.completed_top_floor = {HospitalSpace.plot_key([1,2]):2}
	world.facts.floors.overrides["2"] = {"plots":[[1,2]],"blocked":[],"wall_edges":[],"doors":[],"paths":[]}
	_operating_room(world,"a_room_downstairs","z_table_downstairs",1)
	_operating_room(world,"z_room_upstairs","a_table_upstairs",2)
	world.facts.connectors["surgery_lift"] = {"id":"surgery_lift","definition_id":"VC02","first_floor":1,"last_floor":2,"cell":[57,66],"footprint":[4,4],"rotation":0,"anchor":[58,70],"repair_cell":[56,67],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0,"ticket_next":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},"paid_cost":3200,"used":false}
	var upstairs_desk: Dictionary = world.facts.facilities.floor_guidance_desk.duplicate(true)
	upstairs_desk.id = "upstairs_guidance_desk"
	upstairs_desk.floor_id = 2
	world.facts.facilities[upstairs_desk.id] = upstairs_desk
	for staff: Dictionary in world.facts.staff.values():
		if staff.role=="nurse": staff.schedule = _schedule("work")
	_initial_research(world,"R34")
	var retained: bool = world.ids("staff")==original_staff
	for id: String in original_facilities: retained = retained and world.facts.facilities[id]==original_facilities[id]
	var sim := HospitalSimulation.new(world,_content)
	_simulations.append(sim)
	var c: Dictionary = {"sim":sim,"world":world,"serial":0,"visit_id":"","doctors":[],"started":{},"group_seen":false,"beats":{},"errors":[],"fixture_ready":true,"capture_events":true,"event_log":[],"nursing_handoff_ticks":{},"nursing_handoff_not_at_base":[],"original_load_retained":retained,"base_staff":original_staff.size(),"base_facilities":original_facilities.size()}
	_command(c,"set_intake_open",{"open":false})
	_command(c,"tutorial_set_enabled",{"enabled":false})
	_command(c,"set_auto_restock",{"enabled":false})
	return c

func _operating_room(world: WorldState, room_id: String, table_id: String, floor_id: int) -> void:
	var layout: Dictionary = {}
	for row: Dictionary in _content.layouts.layouts:
		if row.id=="or_standard": layout = row
	var origin: Array = [33,65]
	HospitalFactory._add_room(world,{"id":room_id,"type":"operating_room","floor_id":floor_id,"anchor":origin,"size":layout.size,"door":{"definition_id":layout.door_id,"offset":layout.door_offset}},_content)
	var object: Dictionary = layout.objects[0]
	var definition: Dictionary = _content.facility_definition("EQ01")
	HospitalFactory._add_facility(world,{"id":table_id,"definition_id":"EQ01","anchor":[int(origin[0])+int(object.anchor[0]),int(origin[1])+int(object.anchor[1])],"size":definition.footprint,"room_id":room_id},_content)
	var facility: Dictionary = world.facts.facilities[table_id]
	facility.floor_id = floor_id
	facility.patient_cell = _layout_point(layout,"patient_staging",origin)
	facility.operator_cells = [_layout_point(layout,"surgeon",origin),_layout_point(layout,"anesthetist",origin),_layout_point(layout,"nurse",origin)]
	facility.repair_cell = [int(origin[0])+int(layout.repair_points[0][0]),int(origin[1])+int(layout.repair_points[0][1])]

func _upstairs_seed(ids: Array) -> Dictionary:
	for seed_value: int in 1000:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value+701
		var initial: Dictionary = {"algorithm":"godot-pcg32-4.7.2","seed_decimal":str(rng.seed),"state_decimal":str(rng.state)}
		rng.randi_range(0,0)
		if ids[rng.randi_range(0,ids.size()-1)]=="a_table_upstairs": return initial
	return {}

func _initial_research(world: WorldState, id: String) -> void:
	for prerequisite: String in _content.definition("research",id).get("requires",[]): _initial_research(world,prerequisite)
	if not id in world.facts.research: world.facts.research.append(id)

func _finish_contract(c: Dictionary, checks: Dictionary, details: Dictionary) -> Dictionary:
	details.checks = checks
	details.ok = checks.values().all(func(value: Variant)->bool:return value==true)
	if not details.ok: details.failure_world = _failure_world("GUIDE-09",c.world)
	_dispose_simulations()
	return details

func _facts_hash(facts: Dictionary) -> String:
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(var_to_bytes(facts))
	return hash_context.finish().hex_encode()

func _body_overlap(c: Dictionary) -> Array:
	var bodies: Array = []
	for actor: Dictionary in c.world.facts.actors.values():
		if actor.location.kind=="floor": bodies.append({"id":actor.id,"floor":actor.location.floor_id,"body":c.sim.space.body_rectangle(actor)})
	for index: int in bodies.size():
		for other: int in range(index+1,bodies.size()):
			if bodies[index].floor==bodies[other].floor and bodies[index].body.intersects(bodies[other].body,false): return [bodies[index].id,bodies[other].id]
	return []
