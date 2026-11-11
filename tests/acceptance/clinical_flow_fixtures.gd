extends "res://tests/acceptance/clinical_fixtures.gd"

const Flow = preload("res://game/clinic/clinical_flow.gd")
const FlowIdentity = preload("res://tests/acceptance/checkpoint_identity.gd")
var _flow_cache: RefCounted
var _flow_draws: Dictionary = {}
var _flow_failed_nodes: Dictionary = {}

func flow_initialize(t, database: HospitalContent) -> void:
	_content=database
	_flow_cache=t.checkpoints(database,"res://tests/acceptance/clinical_flow_fixtures.gd",self)

func _checkpoint_dependencies(key: String) -> Dictionary:
	var source: String=FileAccess.get_file_as_string("res://tests/acceptance/clinical_fixtures.gd")+"\n"+FileAccess.get_file_as_string("res://tests/acceptance/clinical_flow_fixtures.gd")
	return FlowIdentity.describe("res://tests/acceptance/clinical_flow_fixtures.gd",flow_recipes(),key,source)

func flow_recipes() -> Dictionary:
	var recipes: Dictionary={
		"before_gp":{"generator":"flow_generate_before_gp","methods":["flow_context"]},
		"exam_wait":{"parent":"before_gp","generator":"flow_generate_gp_completion","arguments":[true],"methods":["flow_add_exam_room","flow_add_worker","flow_first_b_arrival"]},
		"diagnosed":{"parent":"before_gp","generator":"flow_generate_gp_completion","arguments":[false]},
		"exam_started":{"parent":"exam_wait","generator":"flow_generate_exam_start","methods":["flow_exam_session"]},
		"review_wait":{"parent":"exam_started","generator":"flow_generate_review_wait"},
		"continuation_outside":{"parent":"review_wait","generator":"flow_generate_continuation_outside","methods":["flow_schedule"]},
		"continuation_second_outside":{"parent":"continuation_outside","generator":"flow_generate_second_outside","methods":["flow_schedule","flow_outside_return_input"]},
		"outpatient_started":{"parent":"diagnosed","generator":"flow_generate_outpatient_start"},
		"inpatient_wait":{"generator":"flow_generate_inpatient","arguments":[1],"methods":["_surgery_queue"]},
		"cross_floor_inpatient":{"generator":"flow_generate_inpatient","arguments":[2],"methods":["_surgery_queue"]},
		"third_floor_inpatient":{"generator":"flow_generate_inpatient","arguments":[3],"methods":["_surgery_queue"]},
		"before_surgery":{"parent":"inpatient_wait","generator":"flow_generate_before_surgery"},
		"surgery_started":{"parent":"before_surgery","generator":"flow_generate_surgery_start"},
		"ward_recovery":{"parent":"surgery_started","generator":"flow_generate_recovery"}}
	var common: Array=["flow_build","flow_boundary","flow_exact_draw","flow_freeze","flow_restore","flow_until","flow_visit","flow_stay"]
	for recipe: Dictionary in recipes.values(): recipe.methods=common+recipe.get("methods",[])
	return recipes

func flow_context(surgical: bool = false, c_profile: bool = false, team_floor: int = 1, or_floor: int = 1) -> Dictionary:
	var c: Dictionary=_context(surgical,c_profile,true,[],true,team_floor,or_floor)
	c.clinical_scenario=true
	return c

func flow_exact_draw(world: WorldState, stream: String, value: int, modulus: int = 10000) -> bool:
	var key: String="%d:%d"%[modulus,value]
	if not _flow_draws.has(key):
		for seed_value: int in range(1,2000000):
			var generator:=RandomNumberGenerator.new()
			generator.seed=seed_value
			var initial: int=generator.state
			if generator.randi_range(0,modulus-1)==value:
				_flow_draws[key]={"algorithm":"godot-pcg32-4.7.2","seed_decimal":str(seed_value),"state_decimal":str(initial)}
				break
	if not _flow_draws.has(key): return false
	world.facts.rng[stream]=_flow_draws[key].duplicate(true)
	return true

func flow_uniform_arrival(world: WorldState, value: int) -> bool:
	# Arrival identity selection uses the exact-decimal bounded draw, whereas
	# clinical draws use randi_range. Supply an input to the actual algorithm.
	for seed_value: int in range(1,2000000):
		var generator:=RandomNumberGenerator.new()
		generator.seed=seed_value
		var initial: int=generator.state
		var word: int=generator.randi()
		if word<4294960000 and word%10000==value:
			world.facts.rng.arrival={"algorithm":"godot-pcg32-4.7.2","seed_decimal":str(seed_value),"state_decimal":str(initial)}
			return true
	return false

func flow_freeze(c: Dictionary) -> Dictionary:
	var row: Dictionary={"facts":c.world.freeze(),"visit_id":str(c.get("visit_id",""))}
	for key: String in ["serial","doctors","started","group_seen","beats","event_log","before_admission","exam_input","first_b_input"]:
		if c.has(key): row[key]=c[key].duplicate(true) if c[key] is Dictionary or c[key] is Array else c[key]
	return row

func flow_restore(row: Dictionary) -> Dictionary:
	if row.is_empty() or not row.has("facts"): return {}
	var world:=WorldState.new(row.facts.duplicate(true))
	var simulation:=HospitalSimulation.new(world,_content)
	_simulations.append(simulation)
	var c: Dictionary=row.duplicate(true)
	c.erase("facts")
	c.world=world
	c.sim=simulation
	c.fixture_ready=true
	c.clinical_scenario=true
	c.capture_events=true
	c.errors=[]
	for key: String in ["started","beats","nursing_handoff_ticks"]:
		if not c.has(key): c[key]={}
	for key: String in ["event_log","nursing_handoff_not_at_base","doctors"]:
		if not c.has(key): c[key]=[]
	if not c.has("serial"):
		c.serial=0
		for id: String in world.facts.command_receipts:
			if id.begins_with("clinical_command_"): c.serial=maxi(int(c.serial),int(id.trim_prefix("clinical_command_")))
	if not c.has("group_seen"): c.group_seen=false
	return c

func flow_boundary(t, key: String, account_time: bool = true) -> Dictionary:
	var started: int=Time.get_ticks_msec()
	if _flow_failed_nodes.has(key):
		var previous: Dictionary=_flow_failed_nodes[key].duplicate(true)
		previous.reused_failure=true
		_fixture_failures.append(previous)
		if account_time: t.preparation_elapsed(started)
		return {}
	var row: Dictionary=_flow_cache.read(key)
	if row.is_empty():
		var c: Dictionary=await flow_build(t,key)
		if not c.is_empty() and c.get("flow_ready",false):
			row=flow_freeze(c)
			if not _flow_cache.publish(key,row): row={}
		elif not c.is_empty():
			var failure: Dictionary={"boundary":key,"state":flow_diagnostic(c)}
			_flow_failed_nodes[key]=failure.duplicate(true)
			_fixture_failures.append(failure)
			print("FLOW_FIXTURE_FAILURE "+JSON.stringify(failure))
	# Parent generation is inside this span; account it once per requested
	# boundary, while each checkpoint still reports its own source observation.
	if account_time: t.preparation_elapsed(started)
	return flow_restore(row)

func flow_build(t, key: String) -> Dictionary:
	var recipe: Dictionary=flow_recipes().get(key,{})
	if recipe.is_empty(): return {}
	var arguments: Array=[t]
	if recipe.has("parent"):
		var parent: Dictionary=await flow_boundary(t,str(recipe.parent),false)
		if parent.is_empty(): return {}
		arguments.append(parent)
	arguments.append_array(recipe.get("arguments",[]))
	return await callv(str(recipe.generator),arguments)

func flow_generate_before_gp(t) -> Dictionary:
	var c: Dictionary=flow_context()
	flow_exact_draw(c.world,"treatment",9999)
	if not _arrive(c): return {}
	for index: int in 2400:
		var before: Dictionary=flow_freeze(c)
		_tick(c)
		if not _session(c,"gp").is_empty():
			var result: Dictionary=flow_restore(before)
			result.flow_ready=true
			return result
		if index%100==99: await t.process_frame
	c.flow_ready=false
	return c

func flow_generate_gp_completion(t, c: Dictionary, insufficient: bool) -> Dictionary:
	if insufficient and not flow_add_exam_room(c):
		c.flow_ready=false
		return c
	flow_exact_draw(c.world,"treatment",0 if insufficient else 9999)
	if insufficient and not await flow_first_b_arrival(t,c):
		c.flow_ready=false
		return c
	c.flow_ready=await flow_until(t,c,func()->bool:return flow_visit(c).get("phase","")=="wait_examination" if insufficient else flow_visit(c).get("diagnosis",{}).get("state","")=="diagnosed",3000)
	return c

func flow_generate_exam_start(t, c: Dictionary) -> Dictionary:
	c.flow_ready=await flow_until(t,c,func()->bool:return not flow_exam_session(c).is_empty(),3000)
	return c

func flow_generate_review_wait(t, c: Dictionary) -> Dictionary:
	c.flow_ready=await flow_until(t,c,func()->bool:return flow_visit(c).get("diagnosis",{}).get("exam_completed",false) and _session(c,"consult").is_empty(),600)
	return c

func flow_generate_continuation_outside(t, c: Dictionary) -> Dictionary:
	# Random input is supplied before the first real departure establishes its
	# plan. A saved plan is never redrawn or rewritten to match a shift.
	flow_exact_draw(c.world,"arrival",1500,WorldState.TICKS_PER_DAY)
	if not flow_schedule(c,str(flow_visit(c).diagnosis.doctor_id),"rest"):
		c.flow_ready=false
		return c
	c.flow_ready=await flow_until(t,c,func()->bool:return flow_visit(c).get("phase","")=="continuation_outside",2800)
	return c

func flow_generate_second_outside(t, source: Dictionary) -> Dictionary:
	var c: Dictionary=flow_outside_return_input(source,1)
	if c.is_empty(): return {}
	# This controls only the as-yet-unmade D+2 decision. D+1's established due
	# tick, actual service history, original ticket and complete world remain.
	flow_exact_draw(c.world,"arrival",1500,WorldState.TICKS_PER_DAY)
	c.flow_ready=await flow_until(t,c,func()->bool:return flow_visit(c).get("phase","")=="continuation_outside" and int(flow_visit(c).get("continuation",{}).get("return_day",-1))==2,3600)
	return c

func flow_generate_outpatient_start(t, c: Dictionary) -> Dictionary:
	flow_exact_draw(c.world,"treatment",0)
	c.flow_ready=await flow_until(t,c,func()->bool:return not _session(c,"outpatient").is_empty(),3000)
	return c

func flow_generate_inpatient(t, or_floor: int) -> Dictionary:
	var c: Dictionary=await _surgery_queue(t,false,false,or_floor)
	c.clinical_scenario=true
	c.capture_events=true
	c.flow_ready=not flow_stay(c).is_empty() and flow_stay(c).get("phase","")=="waiting_surgery" and flow_visit(c).attempt_ids.is_empty()
	return c

func flow_generate_before_surgery(t, c: Dictionary) -> Dictionary:
	flow_exact_draw(c.world,"treatment",0)
	for index: int in 3000:
		var before: Dictionary=flow_freeze(c)
		_tick(c)
		if not _session(c,"surgery").is_empty():
			var result: Dictionary=flow_restore(before)
			result.flow_ready=true
			return result
		if index%100==99: await t.process_frame
	c.flow_ready=false
	return c

func flow_generate_surgery_start(t, c: Dictionary) -> Dictionary:
	flow_exact_draw(c.world,"treatment",0)
	c.flow_ready=await flow_until(t,c,func()->bool:return not _session(c,"surgery").is_empty(),3000)
	return c

func flow_generate_recovery(t, c: Dictionary) -> Dictionary:
	c.flow_ready=await flow_until(t,c,func()->bool:return flow_stay(c).get("phase","")=="recovery",5000)
	return c

func flow_visit(c: Dictionary) -> Dictionary:
	return {} if c.is_empty() else c.world.facts.visits.get(str(c.get("visit_id","")),{})

func flow_stay(c: Dictionary) -> Dictionary:
	if c.is_empty(): return {}
	for stay: Dictionary in c.world.facts.ward_stays.values():
		if stay.get("visit_id","")==c.get("visit_id",""): return stay
	return {}

func flow_exam_session(c: Dictionary) -> Dictionary:
	for kind: String in ["spectrum","resonance"]:
		var found: Dictionary=_session(c,kind)
		if not found.is_empty(): return found
	return {}

func flow_until(t, c: Dictionary, condition: Callable, ticks: int = 2400) -> bool:
	return false if c.is_empty() else await _until(t,c,condition,ticks)

func flow_steps(t, c: Dictionary, ticks: int) -> void:
	if not c.is_empty(): await _steps(t,c,ticks)

func flow_schedule(c: Dictionary, staff_id: String, kind: String, room_id: String = "") -> bool:
	var rooms: Array=[] if room_id.is_empty() else [room_id]
	var change: Dictionary={"staff_id":staff_id,"schedule":_schedule(kind,rooms)}
	var result: CommandResult=c.sim.services.scheduler.execute(c.world,"apply_schedule",{"changes":[change]})
	return result.accepted

func flow_check(t, id: String, checks: Dictionary, c: Dictionary = {}, extra: Dictionary = {}) -> void:
	if not c.is_empty():
		var validation: String=c.world.validate(_content)
		checks.world_valid=validation.is_empty()
		extra.validation=validation
		extra.tick=c.world.sim_tick
		extra.visit=flow_visit(c).duplicate(true)
		extra.ward=flow_stay(c).duplicate(true)
		if c.has("clock_input"): extra.clock_input=c.clock_input.duplicate(true)
	extra.checks=checks
	if false in checks.values() and not _fixture_failures.is_empty(): extra.fixture_failures=_fixture_failures.duplicate(true)
	t.check(id,not checks.is_empty() and not false in checks.values(),extra)

func flow_in_room(c: Dictionary, actor_id: String, room_id: String) -> bool:
	var actor: Dictionary=c.world.facts.actors.get(actor_id,{})
	var room: Dictionary=c.world.facts.rooms.get(room_id,{})
	if actor.is_empty() or room.is_empty() or actor.location.kind!="floor" or int(actor.location.floor_id)!=int(room.floor_id): return false
	return Rect2(Vector2(float(room.origin[0]),float(room.origin[1])),Vector2(float(room.size[0]),float(room.size[1]))).has_point(Vector2(float(actor.location.cell[0]),float(actor.location.cell[1])))

func flow_guide(c: Dictionary) -> Dictionary:
	return c.sim.services.floor_guidance.state(c.world,str(c.visit_id))

func flow_finish_visit(t, c: Dictionary, maximum_ticks: int = 6000) -> bool:
	return await flow_until(t,c,func()->bool:return flow_visit(c).get("phase","")=="departed",maximum_ticks)

func flow_watch(t, c: Dictionary, condition: Callable, observer: Callable, maximum_ticks: int) -> bool:
	return await flow_until(t,c,func()->bool:
		observer.call()
		return condition.call(),maximum_ticks)

func flow_clock_boundary(c: Dictionary, tick: int) -> Dictionary:
	# This is a legal clock-boundary INPUT after the already-generated prefix,
	# never a replacement for any tested movement, work, wake or recovery.
	var row: Dictionary=flow_freeze(c)
	var source_tick: int=int(row.facts.sim_tick)
	flow_shift_absolute_ticks(row.facts,tick-source_tick)
	row.clock_input={"source_tick":source_tick,"start_tick":tick,"absolute_timestamps_shifted":true,"duration_ticks_unchanged":true}
	return flow_restore(row)

func flow_shift_absolute_ticks(value: Variant, delta: int) -> void:
	# Keep staff needs, reservations, travel and existing work on one clock;
	# plural *_ticks are durations and are deliberately not translated.
	if value is Dictionary:
		for key: Variant in value.keys():
			if (str(key)=="tick" or str(key).ends_with("_tick")) and (value[key] is int or value[key] is float) and int(value[key])>=0: value[key]=int(value[key])+delta
			else: flow_shift_absolute_ticks(value[key],delta)
	elif value is Array:
		for child: Variant in value: flow_shift_absolute_ticks(child,delta)

func flow_outside_return_input(c: Dictionary, return_day: int, first_day: int = 0) -> Dictionary:
	# Only the untested outside interval is prepared. Both source boundaries
	# were generated by actual entrance, counter work and safe exit; all saved
	# facts, clocks, identities, ticket, money, RNG and commitments are retained.
	var row: Dictionary=flow_freeze(c)
	var visit: Dictionary=row.facts.visits[row.visit_id]
	var plan: Dictionary=visit.get("continuation",{})
	if visit.phase!="continuation_outside" or plan.get("stage","")!="outside" or int(plan.get("return_day",-1))!=return_day or int(plan.get("first_day",-1))!=first_day or plan.get("outside_periods",[]).is_empty(): return {}
	row.facts.sim_tick=int(plan.due_tick)-1
	return flow_restore(row)

func flow_return_probe(c: Dictionary) -> Dictionary:
	var visit: Dictionary=flow_visit(c)
	var periods: Array=visit.continuation.outside_periods
	return {"service_tick":int(visit.last_service_tick),"progress_tick":int(visit.last_progress_tick),"ticket_id":str(visit.ticket_id),"waited_ticks":int(c.world.facts.tickets.get(visit.ticket_id,{}).get("waited_ticks",0)),"due_tick":int(visit.continuation.due_tick),"arrival_rng":c.world.facts.rng.arrival.duplicate(true),"inside_progress_age":flow_inside_segments(periods,int(visit.last_progress_tick)),"inside_service_age":flow_inside_segments(periods,int(visit.last_service_tick))}

func flow_inside_segments(periods: Array, since: int) -> int:
	# Sum the actual in-hospital gaps between the saved exit/entry events.
	var cursor: int=since
	var ticks: int=0
	for period: Dictionary in periods:
		if int(period.returned_tick)>=0 and int(period.returned_tick)<=cursor: continue
		if int(period.left_tick)>cursor: ticks+=int(period.left_tick)-cursor
		if int(period.returned_tick)<0: break
		cursor=maxi(cursor,int(period.returned_tick))
	return ticks

func flow_return_checks(c: Dictionary, before: Dictionary) -> Dictionary:
	var visit: Dictionary=flow_visit(c)
	var periods: Array=visit.continuation.outside_periods
	var returned: int=int(periods.back().returned_tick)
	var after_entry: int=c.world.sim_tick-returned
	return {"real_entry_closes_outside":c.world.facts.actors[visit.actor_id].location.kind=="floor" and returned==c.world.sim_tick-1,
		"actual_service_history_unchanged":int(visit.last_service_tick)==int(before.service_tick) and int(visit.last_progress_tick)==int(before.progress_tick),
		"clinical_ticket_and_wait_retained":visit.ticket_id==before.ticket_id and int(c.world.facts.tickets.get(visit.ticket_id,{}).get("waited_ticks",-1))>=int(before.waited_ticks),
		"return_due_and_rng_frozen":int(visit.continuation.due_tick)==int(before.due_tick) and c.world.facts.rng.arrival==before.arrival_rng,
		"prior_inside_no_progress_retained":c.sim.services.arrivals._inside_elapsed(c.world,visit,int(before.progress_tick))==int(before.inside_progress_age)+after_entry,
		"prior_inside_no_service_retained":c.sim.services.arrivals._inside_elapsed(c.world,visit,int(before.service_tick))==int(before.inside_service_age)+after_entry}

func flow_add_floor(c: Dictionary, last_floor: int = 2) -> void:
	c.world.facts.floors.height_intervals=[{"first":1,"last":last_floor,"height_m":float(_content.balance.floors.clear_height_m)}]
	c.world.facts.floors.completed_top_floor={HospitalSpace.plot_key([1,2]):last_floor}
	for floor_id: int in range(2,last_floor+1):
		c.world.facts.floors.overrides[str(floor_id)]={"plots":[[1,2]],"blocked":[],"wall_edges":[],"doors":[],"paths":[]}
	c.world.facts.connectors["flow_lift"]={"id":"flow_lift","definition_id":"VC02","first_floor":1,"last_floor":last_floor,"cell":[57,66],"footprint":[4,4],"rotation":0,"anchor":[58,70],"repair_cell":[56,67],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0,"ticket_next":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},"paid_cost":3200,"used":false}
	c.world.touch(true)

func flow_add_worker(c: Dictionary, id: String, role: String, floor_id: int, cell: Array, room_id: String = "") -> void:
	_add_worker(c.world,id,role,cell,"outpatient" if role=="doctor" else "work",{"diagnosis":2 if role=="doctor" else 1,"treatment":2 if role=="doctor" else 0,"care":1 if role=="nurse" else 0,"surgery":0},"DT02" if role=="doctor" else "DT01",room_id)
	# Initial spawn of a new worker, before any participation by that worker.
	c.world.facts.actors[id].location.floor_id=floor_id
	c.sim.services.development.ensure(c.world)
	c.sim.services.scheduler.ensure(c.world)
	c.sim.services.recruitment.ensure(c.world)
	c.sim.services.wellbeing.ensure(c.world)
	c.sim.services.finance.ensure(c.world)
	c.sim.space.sync_actor(c.world,id)
	c.world.touch(false)

func flow_two_floor_clinic() -> Dictionary:
	var c: Dictionary=flow_context(false,true)
	c.world.facts.ledger.opening_balance=1000000
	flow_add_floor(c)
	var room: CommandResult=_command(c,"build_room",{"id":"flow_gp_2","room_type_id":"gp","floor_id":2,"origin":[34,66],"size":[10,10],"door":{"definition_id":"DR04","edge":"south","offset":3}})
	var table: CommandResult=_command(c,"build_facility",{"id":"flow_exam_table","definition_id":"FUR02","floor_id":2,"cell":[38,69],"room_id":"flow_gp_2"})
	var desk: CommandResult=_command(c,"build_facility",{"id":"flow_guide_2","definition_id":"SE01","floor_id":2,"cell":[47,83]})
	flow_add_worker(c,"flow_exam_doctor","doctor",2,[54,89],"flow_gp_2")
	flow_add_worker(c,"flow_guide_nurse_2","nurse",2,[52,92])
	c.world.facts.staff[c.doctors[0]].abilities.diagnosis=1
	# The originating GP cannot perform either examination. Its ward nurse
	# rests; only the separate 2F GP has an examination-qualified assignment.
	c.world.facts.staff.starter_nurse.schedule=_schedule("rest")
	c.fixture_ready=room.accepted and table.accepted and desk.accepted
	c.input_commands={"room":room.to_record(),"table":table.to_record(),"desk":desk.to_record()}
	return c

func flow_add_exam_room(c: Dictionary) -> bool:
	if c.world.facts.facilities.has("flow_diagnostic_table"): return true
	c.world.facts.ledger.opening_balance=1000000
	var room: CommandResult=_command(c,"build_room",{"id":"flow_diagnostic_room","room_type_id":"treatment","floor_id":1,"origin":[33,65],"size":[10,8],"door":{"definition_id":"DR04","edge":"south","offset":3}})
	var table: CommandResult=_command(c,"build_facility",{"id":"flow_diagnostic_table","definition_id":"FUR02","floor_id":1,"cell":[37,68],"room_id":"flow_diagnostic_room"})
	# FUR02 alone does not activate the treatment-room purpose. The ordinary
	# treatment body is part of this lawful initial clinical installation.
	var machine: CommandResult=_command(c,"build_facility",{"id":"flow_diagnostic_room_machine","definition_id":"M37","floor_id":1,"cell":[40,66],"room_id":"flow_diagnostic_room"})
	# A room-bound nurse can operate the opened spectrum mode without R11;
	# the separate qualified doctor also supplies both modes when R11 opens.
	flow_add_worker(c,"flow_diagnostic_nurse","nurse",1,[61,79],"flow_diagnostic_room")
	flow_add_worker(c,"flow_diagnostic_doctor","doctor",1,[62,78],"flow_diagnostic_room")
	c.exam_input={"room":room.to_record(),"table":table.to_record(),"purpose_machine":machine.to_record()}
	return room.accepted and table.accepted and machine.accepted

func flow_first_b_arrival(t, c: Dictionary) -> bool:
	if int(c.world.facts.get("research_progress",{}).get("first_profile_b_tick",-1))>=0: return true
	# R19 is a declared completed-research input. R11 is deliberately absent:
	# only the following actual B admission opens spectrum for the test.
	if not "R19" in c.world.facts.research: c.world.facts.research.append("R19")
	c.world.touch(false)
	var prepared: bool=await flow_until(t,c,func()->bool:return c.world.facts.staff.flow_diagnostic_nurse.get("base_prepared",false) and c.world.facts.staff.flow_diagnostic_nurse.get("base_task",{}).is_empty(),900)
	if not prepared: return false
	var guidance: HospitalFloorGuidance=c.sim.services.floor_guidance
	# Warm the unavailable-mode projection with all physical prerequisites
	# ready, then change only the real B-admission fact, not geometry or staff.
	var before: Array=guidance._target_ids(c.world,flow_visit(c),"examination").duplicate()
	var entry_tick: int=c.world.sim_tick
	var arrival: CommandResult=_command(c,"clinical_arrive",{"arrival_key":"flow-first-b","binding_id":"B_S49_D38_M38","requested_plan_id":"P_D38_COMMON","personality_id":"PP01","expression":"clear"})
	c.first_b_input={"binding_id":"B_S49_D38_M38","research_prerequisite":"R19","arrival":arrival.to_record(),"entry_tick":entry_tick,"before_open_targets":before}
	if not arrival.accepted: return false
	var after: Array=guidance._target_ids(c.world,flow_visit(c),"examination").duplicate()
	c.first_b_input.after_open_targets=after
	var visit_id: String=str(arrival.changed_ids[0])
	c.first_b_input.visit_id=visit_id
	if not c.sim.clinic.depart_visit(c.world,visit_id,"abandoned"): return false
	var departed: bool=await flow_until(t,c,func()->bool:return c.world.facts.visits[visit_id].phase=="departed",900)
	if departed:
		c.first_b_input.departed_tick=c.world.facts.visits[visit_id].get("departed_tick",-1)
		c.sim.services.arrivals.settle(c.world)
	return departed and before.is_empty() and not after.is_empty() and int(c.world.facts.get("research_progress",{}).get("first_profile_b_tick",-1))==entry_tick

func flow_diagnostic(c: Dictionary) -> Dictionary:
	if c.is_empty(): return {"missing_input":true}
	var visit: Dictionary=flow_visit(c)
	var actor_id: String=str(visit.get("actor_id",""))
	var row: Dictionary={"tick":c.world.sim_tick,"visit":visit.duplicate(true),"guidance":flow_guide(c).duplicate(true),"ward":flow_stay(c).duplicate(true),"preparation":c.world.facts.preparations.get(c.get("visit_id",""),{}).duplicate(true),"ticket":c.world.facts.tickets.get(str(visit.get("ticket_id","")),{}).duplicate(true),"patient":c.world.facts.actors.get(actor_id,{}).duplicate(true),"errors":c.get("errors",[]).duplicate(true),"sessions":{},"staff":{},"diagnostic_facilities":[],"candidates":{},"research":c.world.facts.research.duplicate(),"first_profile_b_tick":int(c.world.facts.get("research_progress",{}).get("first_profile_b_tick",-1))}
	for session: Dictionary in c.world.facts.sessions.values():
		if session.visit_id==visit.get("id",""): row.sessions[session.id]=session.duplicate(true)
	for id: String in c.world.ids("staff"):
		var staff: Dictionary=c.world.facts.staff[id]
		if not staff.role in ["doctor","nurse"]: continue
		row.staff[id]={"role":staff.role,"abilities":staff.abilities.duplicate(),"on_shift":staff.get("on_shift",false),"pools":c.sim.services.scheduler.assignment(c.world,id,c.sim.services.scheduler.shift_index(c.world)).get("pools",[]),"base_prepared":staff.get("base_prepared",true),"job":staff.get("active_job_id",""),"release":staff.get("clinical_release",{}),"life":staff.get("life_task",{}).get("phase","idle"),"location":c.world.facts.actors[id].location.duplicate(true)}
	for id: String in c.world.facility_ids("FUR02"):
		var facility: Dictionary=c.world.facts.facilities[id]
		var eligibility: Array=[]
		for staff_id: String in c.world.ids("staff"):
			var staff: Dictionary=c.world.facts.staff[staff_id]
			if staff.role!="nurse": continue
			eligibility.append({"staff_id":staff_id,"can_start":c.sim.clinic._can_start(c.world,staff),"spectrum_qualified":c.sim.clinic._service_qualified(c.world,staff,"spectrum"),"spectrum_schedule":c.sim.clinic._schedule_allows(c.world,staff_id,"spectrum",visit,id)})
		row.diagnostic_facilities.append({"id":id,"room":facility.get("room_id",""),"floor":facility.floor_id,"open":facility.get("open",true),"failed":facility.failed,"room_reason":c.sim.clinic.service_room_reason(c.world,facility),"nurses":eligibility})
	for kind: String in ["spectrum","resonance"]:
		if not visit.is_empty() and row.patient.get("location",{}).get("kind","")=="floor": row.candidates[kind]=c.sim.clinic.service_candidates(c.world,visit,kind,false,false,{"first_only":true})
	if c.has("exam_input"): row.exam_input=c.exam_input
	if c.has("first_b_input"): row.first_b_input=c.first_b_input
	return row

func flow_guidance_handoff(c: Dictionary) -> Dictionary:
	var visit: Dictionary=flow_visit(c)
	var actor_id: String=str(visit.actor_id)
	var guidance: HospitalFloorGuidance=c.sim.services.floor_guidance
	var row: Dictionary={"tick":c.world.sim_tick,"visit":visit.duplicate(true),"guide":flow_guide(c).duplicate(true),"actor":c.world.facts.actors[actor_id].duplicate(true),"move":c.world.facts.moves.get(actor_id,{}).duplicate(true),"need":c.world.facts.waiting_life.needs.get(visit.id,{}).duplicate(true),"need_clock":c.world.facts.waiting_life.clocks.get(visit.id,{}).duplicate(true),"ticket":c.world.facts.tickets.get(str(visit.ticket_id),{}).duplicate(true),"desks":{},"nurses":{}}
	for id: String in c.world.facility_ids("SE01"):
		row.desks[id]={"state":c.world.facts.floor_guidance.desks.get(id,{}).duplicate(true),"usable":guidance._desk_usable(c.world,id),"open":guidance._desk_open(c.world,id)}
	for id: String in c.world.ids("staff"):
		var staff: Dictionary=c.world.facts.staff[id]
		if staff.role!="nurse": continue
		var operators: Dictionary={}
		for desk_id: String in c.world.facility_ids("SE01"): operators[desk_id]=c.sim.space.guidance_operator_cell(c.world,desk_id,id)
		row.nurses[id]={"ready":guidance._nurse_ready(c.world,id),"job":staff.get("active_job_id",""),"on_shift":staff.get("on_shift",false),"scheduled_kind":staff.get("scheduled_kind",""),"energy":staff.get("energy",0.0),"block_new_work":staff.get("block_new_work",false),"life":staff.get("life_task",{}).duplicate(true),"actor":c.world.facts.actors[id].duplicate(true),"move":c.world.facts.moves.get(id,{}).duplicate(true),"operators":operators}
	return row

func flow_trace_preparation(c: Dictionary, trace: Dictionary) -> void:
	if not trace.has("disappearances"):
		trace.merge({"disappearances":[],"transit":[],"_generation":0,"_seen":{}})
	var current: Dictionary=c.world.facts.preparations.get(c.visit_id,{})
	var previous: Dictionary=trace.get("_active",{})
	if current.is_empty():
		if not previous.is_empty():
			trace.disappearances.append({"tick":c.world.sim_tick,"previous_tick":previous.tick,"generation":trace._generation,"preparation":previous.preparation,"observed_waiting_reason":str(flow_visit(c).waiting_reason),"visit_phase":str(flow_visit(c).phase),"stay":flow_stay(c).duplicate(true),"surgery_session":_session(c,"surgery").duplicate(true),"bindings":flow_preparation_bindings(c,previous.preparation)})
		trace.erase("_active")
		return
	if previous.is_empty(): trace._generation+=1
	trace._active={"tick":c.world.sim_tick,"preparation":current.duplicate(true)}
	for id: String in [str(flow_visit(c).actor_id)]+current.get("staff_ids",[]):
		var actor: Dictionary=c.world.facts.actors.get(id,{})
		var key: String=str(trace._generation)+":"+id
		if actor.get("location",{}).get("kind","")!="transit" or trace._seen.has(key): continue
		trace._seen[key]=true
		trace.transit.append({"tick":c.world.sim_tick,"generation":trace._generation,"actor_id":id,"preparation":current.duplicate(true),"bindings":flow_preparation_bindings(c,current)})

func flow_preparation_bindings(c: Dictionary, preparation: Dictionary) -> Dictionary:
	var row: Dictionary={"actors":{},"adaptations":{},"ticket":c.world.facts.tickets.get(str(flow_visit(c).ticket_id),{}).duplicate(true)}
	for id: String in [str(flow_visit(c).actor_id)]+preparation.get("staff_ids",[]):
		row.actors[id]={"actor":c.world.facts.actors.get(id,{}).duplicate(true),"move":c.world.facts.moves.get(id,{}).duplicate(true),"clinical_release":c.world.facts.staff.get(id,{}).get("clinical_release",{}).duplicate(true)}
	for id: String in [str(preparation.get("facility_id","")),str(preparation.get("bed_id",""))]:
		if c.world.facts.adaptations.has(id): row.adaptations[id]=c.world.facts.adaptations[id].duplicate(true)
	return row

func flow_preparation_trace_result(trace: Dictionary) -> Dictionary:
	var result: Dictionary=trace.duplicate(true)
	result.erase("_active")
	result.erase("_seen")
	result.erase("_generation")
	return result

func flow_existing_gp_queue(c: Dictionary, target: String) -> Dictionary:
	# Declared existing queue input. Its own earlier guidance is not being
	# tested; the returning patient's real journey and FIFO insertion are.
	var actor_id: String=c.world.new_id("patient")
	var visit_id: String=c.world.new_id("visit")
	var actor: Dictionary={"id":actor_id,"name":"原门诊候诊者","species_id":"S49","body_binding_id":"B_S49_D37_M37","location":{"kind":"floor","floor_id":1,"cell":[40,90],"height_m":0.0},"facing":0.0,"posture":"standing"}
	var visit: Dictionary={"id":visit_id,"actor_id":actor_id,"disease_id":"D37","binding_id":"B_S49_D37_M37","requested_plan_id":"P_D37_COMMON","expression":"clear","personality_id":"PP01","anger":0.0,"phase":"arrival","diagnosis":{},"attempt_ids":[],"plan_decision":{},"complex":false,"final_result":"","waiting_reason":"","ticket_id":"","doctor_fee_quote":-1,"arrival_tick":c.world.sim_tick,"arrived_tick":c.world.sim_tick,"last_progress_tick":c.world.sim_tick,"last_service_tick":c.world.sim_tick,"arrival_key":"flow_fifo_"+visit_id}
	c.world.facts.actors[actor_id]=actor
	c.world.facts.visits[visit_id]=visit
	c.world.facts.arrival_receipts[visit.arrival_key]=visit_id
	c.world.register_visit(visit_id)
	c.sim.clinic._queue(c.world,visit,"gp")
	var guide: HospitalFloorGuidance=c.sim.services.floor_guidance
	var ticket: Dictionary=c.world.facts.tickets[visit.ticket_id]
	var room: String=str(c.world.facts.facilities[target].room_id)
	c.world.facts.floor_guidance.next_arrival+=1
	c.world.facts.floor_guidance.visits[visit_id]={"visit_id":visit_id,"request_key":guide._key(ticket),"ticket_id":ticket.id,"phase":"destination","target_id":target,"target_room_id":room,"desk_id":"","guide_floor":int(c.world.facts.facilities[target].floor_id),"floor_selected":true,"initial_done":true,"receipts":[],"guided_target":target,"arrived_seq":c.world.facts.floor_guidance.next_arrival,"reason":"","next_recheck":0}
	c.world.facts.floor_guidance.clinic_queues.get_or_add(room,{"visit_ids":[],"called_id":"","deadline_tick":-1}).visit_ids.append(visit_id)
	c.sim.space.sync_actor(c.world,actor_id)
	c.world.touch(false)
	return visit
