extends "res://tests/acceptance/rooms_areas_guidance.gd"

# Independent coordinates for the built 2x1 desk at [47,83]. No production
# rotation or guidance helper is used to calculate these expected positions.
const BASE_POSTS: Array=[[47,82],[48,83],[48,84],[46,84]]
const LARGE_POSTS: Array=[[47,81],[48,83],[47,84],[45,83]]
const OUTER_CELLS: Array=[[48,81],[49,84],[47,85],[45,83]]

func run_case(database: HospitalContent) -> Dictionary:
	content=database
	var rows: Array=[]
	for turns: int in 4: rows.append(_geometry(turns))
	rows.append(_actual(false));rows.append(_actual(true))
	return {"ok":rows.all(func(row:Dictionary)->bool:return row.ok),"runs":rows}

func _restore_operator(x: Dictionary) -> Dictionary:
	var helper: RefCounted=load("res://tests/acceptance/guidance_nurse_local_release.gd").new()
	helper.content=content
	return helper._restore_release(x)

func _geometry_boundary(x: Dictionary, positions: Dictionary) -> bool:
	# Independent computational inputs only. Never replace a real tested trip,
	# attendance, work or exit; _actual owns all such process evidence.
	if int(x.steps)!=0: return false
	var facts: Dictionary=x.world.freeze()
	facts.moves={}
	for id: String in positions: facts.actors[id].location.cell=positions[id].duplicate()
	var world:=WorldState.new(facts)
	world.touch(false)
	if not world.validate(content).is_empty(): return false
	x.sim.dispose();x.world=world;x.sim=HospitalSimulation.new(world,content)
	return true

func _geometry(turns: int) -> Dictionary:
	var x: Dictionary=_base()
	x.checks.desk=_command(x,"build_facility",{"id":"guide","definition_id":"SE01","cell":[47,83],"rotation":turns}).accepted
	if not x.checks.desk: return _finish(x,{"turns":turns,"reason":"Desk construction failed"})
	_staff(x,"a_large","nurse",[55,90]);_staff(x,"z_small","nurse",[59,90])
	x.world.facts.actors.a_large.species_id="S28"
	x.world.facts.staff.a_large.base_prepared=true;x.world.facts.staff.z_small.base_prepared=true
	x.world.touch(false);x.sim.space.sync_actor(x.world,"a_large")
	var visit: Dictionary=_patient(x,"probe",[35,90],"gp","B_S13_D09_M09")
	x.sim.services.maintenance.ensure(x.world)
	var raw: Dictionary=x.world.facts.facilities.guide.duplicate(true)
	var space: HospitalSpace=x.sim.space
	var areas: HospitalPublicAreas=space.public_areas
	var before: Dictionary=x.world.freeze()
	var base: Dictionary=space.facility_layout(x.world,"guide")
	x.checks.independent_base=base.operator_cells==[BASE_POSTS[turns]] and base.operator_clearances==[1]
	var base_quote: Dictionary=space.facility_geometry_quote(x.world,"guide",visit.actor_id)
	x.checks.no_nurse_quote_uses_same_base=base_quote.get("ok",false) and base_quote.get("operator_cells",[])==[BASE_POSTS[turns]]
	x.checks.base_post_not_waiting=not areas.safe_wait(x.world,visit.actor_id,1,BASE_POSTS[turns])
	x.checks.outer_initially_safe=areas.safe_wait(x.world,visit.actor_id,1,OUTER_CELLS[turns])
	x.checks.default_ground_post_excluded=not x.sim.services.environment._ground_spawn_legal(x.world,1,BASE_POSTS[turns]) and x.sim.services.environment._ground_spawn_legal(x.world,1,OUTER_CELLS[turns])
	x.checks.layout_and_wait_queries_readonly=before==x.world.freeze()
	x.sim.services.floor_guidance._assign_desks(x.world)
	var assigned: Dictionary=space.facility_layout(x.world,"guide")
	x.checks.real_large_body=space.clearance(x.world.facts.actors.a_large)==2
	x.checks.independent_actual_large=assigned.operator_cells==[LARGE_POSTS[turns]] and assigned.operator_clearances==[2] and x.world.facts.floor_guidance.desks.guide.nurse_id=="a_large"
	x.checks.warmed_outer_point_invalidated=not areas.safe_wait(x.world,visit.actor_id,1,OUTER_CELLS[turns])
	x.checks.actual_large_ground_post_excluded=not x.sim.services.environment._ground_spawn_legal(x.world,1,OUTER_CELLS[turns])
	var quote: Dictionary=space.facility_geometry_quote(x.world,"guide",visit.actor_id,["a_large"])
	x.checks.quote_uses_same_post=quote.get("ok",false) and quote.get("operator_cells",[])==[LARGE_POSTS[turns]]
	if not x.checks.quote_uses_same_post: return _finish(x,{"turns":turns,"quote":quote})
	var occupied: Dictionary={visit.actor_id:quote.patient_cell,"a_large":LARGE_POSTS[turns]}
	x.checks.occupied_initial_boundary=_geometry_boundary(x,occupied)
	space=x.sim.space;areas=space.public_areas
	x.checks.both_present_before_reservation=space.at(x.world,visit.actor_id,1,quote.patient_cell) and space.at(x.world,"a_large",1,LARGE_POSTS[turns]) and x.world.facts.moves.is_empty()
	if not x.checks.occupied_initial_boundary or not x.checks.both_present_before_reservation: return _finish(x,{"turns":turns,"reason":"Independent occupied boundary invalid"})
	var reserved: String=space.reserve_facility(x.world,"guide",visit.actor_id,visit.actor_id,["a_large"])
	x.checks.original_reservation=reserved.is_empty() and x.world.facts.adaptations.has("guide")
	if not x.checks.original_reservation: return _finish(x,{"turns":turns,"reservation_reason":reserved,"quote":quote})
	var held: Dictionary=x.world.facts.adaptations.guide.duplicate(true)
	x.checks.original_nurse_leaves=x.sim.services.wellbeing.begin_amenity(x.world,"a_large","water")
	x.sim.services.floor_guidance._assign_desks(x.world)
	var frozen: Dictionary=space.facility_layout(x.world,"guide")
	x.checks.frozen_quote_has_priority=frozen.operator_cells==held.operator_cells and frozen.operator_clearances==[2] and x.world.facts.adaptations.guide==held
	x.checks.frozen_full_post_not_waiting=not areas.safe_wait(x.world,visit.actor_id,1,OUTER_CELLS[turns])
	x.checks.frozen_ground_post_excluded=not x.sim.services.environment._ground_spawn_legal(x.world,1,OUTER_CELLS[turns])
	var frozen_restore: Dictionary=_restore_operator(x)
	x.checks.frozen_full_facts_cold_restore=frozen_restore.ok and x.sim.space.facility_layout(x.world,"guide").operator_cells==held.operator_cells and x.sim.space.facility_layout(x.world,"guide").operator_clearances==[2]
	space=x.sim.space;areas=space.public_areas
	space.release_adaptations(x.world)
	x.checks.occupied_frozen_quote_retained=x.world.facts.adaptations.has("guide")
	# A separate legal post-exit input checks release calculation. These declared
	# locations are not evidence of walking out; live/cold _actual proves movement.
	x.checks.exited_initial_boundary=_geometry_boundary(x,{visit.actor_id:[35,90],"a_large":[55,90]})
	space=x.sim.space;areas=space.public_areas
	x.checks.exited_frozen_post_warmed=not areas.safe_wait(x.world,visit.actor_id,1,OUTER_CELLS[turns])
	space.release_adaptations(x.world)
	x.checks.actual_reservation_released=not x.world.facts.adaptations.has("guide")
	x.sim.services.floor_guidance._assign_desks(x.world)
	var replacement: Dictionary=space.facility_layout(x.world,"guide")
	x.checks.actual_small_replacement=x.world.facts.floor_guidance.desks.guide.nurse_id=="z_small" and replacement.operator_clearances==[1] and replacement.operator_cells==[BASE_POSTS[turns]]
	x.checks.released_outer_point_available=areas.safe_wait(x.world,visit.actor_id,1,OUTER_CELLS[turns])
	x.checks.released_ground_post_available=x.sim.services.environment._ground_spawn_legal(x.world,1,OUTER_CELLS[turns])
	x.checks.small_nurse_leaves=x.sim.services.wellbeing.begin_amenity(x.world,"z_small","water")
	x.sim.services.floor_guidance._assign_desks(x.world)
	var empty: Dictionary=space.facility_layout(x.world,"guide")
	x.checks.unassigned_uses_base_only=x.world.facts.floor_guidance.desks.guide.nurse_id=="" and empty.operator_clearances==[1] and empty.operator_cells==[BASE_POSTS[turns]]
	var restored: Dictionary=_restore_operator(x)
	x.checks.full_facts_cold_restore=restored.ok
	x.checks.cold_post_is_still_protected=not x.sim.space.public_areas.safe_wait(x.world,visit.actor_id,1,BASE_POSTS[turns]) and x.sim.space.public_areas.safe_wait(x.world,visit.actor_id,1,OUTER_CELLS[turns])
	x.checks.legacy_layout_fact_unchanged=x.world.facts.facilities.guide==raw
	return _finish(x,{"turns":turns,"base_expected":BASE_POSTS[turns],"actual_expected":LARGE_POSTS[turns],"outer_probe":OUTER_CELLS[turns],"restore":restored,"frozen_restore":frozen_restore,"raw_operator_cells":raw.operator_cells,"scope":"Independent zero-step geometry inputs: participants already at their service posts before reserve; participants already outside before release calculation. Neither declared boundary proves travel or completed work."})

func _actual(cold: bool) -> Dictionary:
	var x: Dictionary=_base()
	x.checks.desk=_facility(x,"guide","SE01",[47,83])
	x.checks.gp=_room(x,"gp","gp",[34,66]) and _facility(x,"diagnosis","FUR02",[38,69],"gp")
	if not x.checks.desk or not x.checks.gp: return _finish(x,{"cold":cold,"reason":"Initial construction failed"})
	_staff(x,"nurse","nurse",[55,90]);_staff(x,"doctor","doctor",[59,90],"gp")
	# Legal current-segment preparation boundary. No travel or guidance work
	# has occurred; the existing LIFE-04 measures real nurse preparation.
	x.world.facts.staff.nurse.base_prepared=true
	var visit: Dictionary=_patient(x,"blocked_post",[47,82],"gp","B_S13_D09_M09")
	x.sim.services.maintenance.ensure(x.world)
	var ticket: String=visit.ticket_id
	var original: Dictionary=x.world.facts.actors[visit.actor_id].location.duplicate(true)
	var raw: Dictionary=x.world.facts.facilities.guide.duplicate(true)
	var ledger: Dictionary=x.world.facts.ledger.entries.duplicate(true)
	var stock: int=int(x.world.facts.inventory.units)
	var initial_rng: Dictionary=x.world.facts.rng.guidance.duplicate(true)
	x.checks.legal_blocking_input=x.world.validate(content).is_empty() and not x.sim.space.public_areas.safe_wait(x.world,visit.actor_id,1,original.cell)
	x.checks.no_clinical_resources_before_guidance=true
	x.checks.same_original_ticket=true
	x.checks.safe_real_bodies=true
	x.checks.six_seconds_at_real_posts=true
	var observed: Dictionary={"cold":cold,"safety_walk_steps":0,"nurse_walk_steps":0,"work_ticks":0,"restore":{},"departure_rng":{},"posted_tick":-1,"completed_tick":-1,"errors":[]}
	var complete: bool=false
	for index: int in 1400:
		var guidance: HospitalFloorGuidance=x.sim.services.floor_guidance
		var before: Dictionary=guidance.state(x.world,visit.id).duplicate(true)
		var working_layout: Dictionary=x.sim.space.facility_layout(x.world,"guide")
		var previous: Dictionary=x.world.facts.actors[visit.actor_id].location.duplicate(true)
		var nurse_before: Dictionary=x.world.facts.actors.nurse.location.duplicate(true)
		var move: Dictionary=x.world.facts.moves.get(visit.actor_id,{})
		var safety_move: bool=move.get("waiting_safety_visit","")==visit.id
		_step(x)
		guidance=x.sim.services.floor_guidance
		var actor: Dictionary=x.world.facts.actors[visit.actor_id]
		var nurse: Dictionary=x.world.facts.actors.nurse
		var current: Dictionary=guidance.state(x.world,visit.id)
		var validation: String=x.world.validate(content)
		if not validation.is_empty(): observed.errors.append({"tick":x.world.sim_tick,"validation":validation});break
		x.checks.same_original_ticket=x.checks.same_original_ticket and visit.ticket_id==ticket and x.world.facts.tickets.has(ticket)
		x.checks.safe_real_bodies=x.checks.safe_real_bodies and not x.sim.space.body_rectangle(actor).intersects(x.sim.space.body_rectangle(nurse),false)
		if nurse.location!=nurse_before: observed.nurse_walk_steps+=1
		if safety_move and actor.location!=previous: observed.safety_walk_steps+=1
		var current_move: Dictionary=x.world.facts.moves.get(visit.actor_id,{})
		if observed.departure_rng.is_empty() and current_move.get("waiting_safety_visit","")==visit.id:
			observed.departure_rng=x.world.facts.rng.guidance.duplicate(true)
			x.checks.safety_did_not_draw_or_queue=observed.departure_rng==initial_rng and not current.has("queue_seq") and current.get("phase","")=="seek"
		if cold and observed.restore.is_empty() and int(observed.safety_walk_steps)>0 and current_move.get("waiting_safety_visit","")==visit.id:
			observed.restore=_restore_operator(x)
			x.checks.moving_departure_cold_restore=observed.restore.ok
			visit=x.world.facts.visits[visit.id]
			actor=x.world.facts.actors[visit.actor_id];nurse=x.world.facts.actors.nurse
		if int(observed.posted_tick)<0 and x.sim.space.at(x.world,"nurse",1,x.sim.space.guidance_operator_cell(x.world,"guide","nurse")) and not x.world.facts.moves.has("nurse"): observed.posted_tick=x.world.sim_tick
		var worked: int=0
		if before.get("phase","")=="working": worked=int(before.remaining_ticks)-int(current.get("remaining_ticks",0)) if current.get("phase","")=="working" else int(before.remaining_ticks)
		elif current.get("phase","")=="working":
			worked=60-int(current.remaining_ticks)
			working_layout=x.sim.space.facility_layout(x.world,"guide")
		if worked>0:
			observed.work_ticks+=worked
			x.checks.six_seconds_at_real_posts=x.checks.six_seconds_at_real_posts and worked==1 and x.sim.space.at(x.world,visit.actor_id,1,working_layout.patient_cell) and x.sim.space.at(x.world,"nurse",1,working_layout.operator_cells[0])
		x.checks.no_clinical_resources_before_guidance=x.checks.no_clinical_resources_before_guidance and x.world.facts.preparations.is_empty() and x.world.facts.sessions.is_empty() and x.world.facts.attempts.is_empty()
		if not current.get("receipts",[]).is_empty():
			observed.completed_tick=x.world.sim_tick;complete=true;break
	x.checks.real_evacuation_before_posting=int(observed.safety_walk_steps)>0 and int(observed.nurse_walk_steps)>0 and int(observed.posted_tick)>0 and x.world.facts.actors[visit.actor_id].location!=original
	x.checks.real_sixty_tick_guidance=complete and int(observed.work_ticks)==60
	x.checks.cold_branch_completed=not cold or observed.restore.get("ok",false)
	x.checks.no_fee_or_supply_use=x.world.facts.ledger.entries==ledger and int(x.world.facts.inventory.units)==stock
	x.checks.original_layout_fact_unchanged=true
	for field: String in ["cell","rotation","footprint","patient_cell","operator_cells","repair_cell"]:
		x.checks.original_layout_fact_unchanged=x.checks.original_layout_fact_unchanged and x.world.facts.facilities.guide.get(field)==raw.get(field)
	return _finish(x,{"observed":observed,"ticket_id":ticket,"guidance":x.sim.services.floor_guidance.state(x.world,visit.id).duplicate(true)})
