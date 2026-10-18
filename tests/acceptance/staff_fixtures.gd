extends RefCounted

const CheckpointIdentity = preload("res://tests/acceptance/checkpoint_identity.gd")

var _cache: RefCounted
var _recorder: Object

# Fixed observations isolate the published seat-scoring example. Geometry,
# body fit, paths, reservations, personalities and selection remain production code.
class SeatObservations extends RefCounted:
	var cells: Dictionary = {}
	var fallback: Dictionary = {"value":50.0,"noise":0.0,"clean":true,"water":false}
	func begin_query(_world: WorldState) -> void:
		pass
	func end_query() -> void:
		pass
	func environment_at(_world: WorldState, _floor: int, cell: Array, _actor: String = "", _explain: bool = true) -> Dictionary:
		return cells.get("%d:%d" % [roundi(cell[0]),roundi(cell[1])],fallback).duplicate(true)

var _content: HospitalContent
var _next: int = 0

func _checkpoint_dependencies(key: String) -> Dictionary:
	if not key.begins_with("training_") or not key.trim_prefix("training_").is_valid_int(): return {"error":"Unknown training boundary: "+key}
	return CheckpointIdentity.describe("res://tests/acceptance/staff_fixtures.gd",{key:{"methods":["_training_checkpoint"],"ticks":int(key.trim_prefix("training_"))}},key)

func _fixture(roles: Dictionary = {}) -> Dictionary:
	_next += 1
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"员工专项%d" % _next,false,_content)
	var index: int = 0
	for id: String in roles:
		HospitalFactory._add_staff(world,id,id,str(roles[id]),[36+index*3,92],_content)
		index += 1
	return _bind(world)

func _bind(world: WorldState) -> Dictionary:
	var space: HospitalSpace = HospitalSpace.new(_content)
	var x: Dictionary = {"world":world,"space":space,
		"d":HospitalClinicalDevelopment.new(_content,space),"s":HospitalShiftScheduler.new(_content,space),
		"w":HospitalStaffWellbeing.new(_content,space),"l":HospitalWaitingLife.new(_content,space),
		"r":RecruitmentService.new(_content,space),"c":HospitalClinic.new(_content,space),
		"f":FinanceService.new(_content,space),"e":HospitalEnvironment.new(_content,space),
		"p":HospitalDepartments.new(_content,space),"m":HospitalMaintenance.new(_content,space),
		"a":HospitalArrivalService.new(_content,space)}
	for key: String in ["r","d","s","w","l","c","f","e","p","m","a"]:
		x[key].ensure(world)
	x.c.recruitment = x.r
	x.l.environment = x.e
	x.l.visitors = x.c.visitors
	x.p.environment = x.e
	x.p.waiting_life = x.l
	return x

func _restore(x: Dictionary) -> Dictionary:
	return _bind(WorldState.new(x.world.freeze()))

func _room(x: Dictionary, kind: String = "rest") -> String:
	var id: String = "support_room"
	HospitalFactory._add_room(x.world,{"id":id,"type":kind,"anchor":[34,66],"size":[26,24],
		"door":{"definition_id":"DR06","offset":12}},_content)
	return id

func _facility(x: Dictionary, id: String, definition_id: String, cell: Array, room_id: String = "") -> void:
	var definition: Dictionary = _content.facility_definition(definition_id)
	HospitalFactory._add_facility(x.world,{"id":id,"definition_id":definition_id,"anchor":cell,
		"size":definition.get("footprint",[1,1]),"room_id":room_id if not room_id.is_empty() else null},_content)

func _position(x: Dictionary, id: String, cell: Array) -> void:
	x.world.facts.actors[id].location = {"kind":"floor","floor_id":1,"cell":cell.duplicate(),"height_m":0.0}
	x.space.sync_actor(x.world,id)

func _cash(x: Dictionary, amount: int) -> void:
	x.world.facts.ledger.opening_balance += amount-HospitalLedger.balance(x.world)

func _near(a: float, b: float, epsilon: float = 0.00001) -> bool:
	return absf(a-b)<=epsilon

func _training_fixture() -> Dictionary:
	var x: Dictionary = _fixture({"doctor":"doctor","nurse":"nurse"})
	var room: String = _room(x,"research")
	_facility(x,"desk","FUR05",[43,74],room)
	x.world.facts.research = ["R11","R34"]
	for id: String in ["doctor","nurse"]:
		x.world.facts.staff[id].scheduled_kind = "training"
		x.world.facts.staff[id].on_shift = true
	_position(x,"doctor",x.space.facility_layout(x.world,"desk").operator_cells[0])
	_position(x,"nurse",[50,80])
	return x

func _enroll(x: Dictionary, id: String = "doctor", track: String = "treatment", mentor: String = "") -> Dictionary:
	var result: CommandResult = x.d.execute(x.world,"train_staff",{"staff_id":id,"track":track,"mentor_id":mentor,"desk_id":"desk"})
	if not result.accepted:
		return {}
	return x.world.facts.training_jobs[x.world.facts.staff[id].training_job_id]

func _training_checkpoint(ticks: int) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var key: String = "training_"+str(ticks)
	var state: Dictionary = _cache.read(key)
	if state.is_empty():
		var input: Dictionary = _training_fixture()
		_enroll(input)
		input.d.dispatch(input.world)
		_training_ticks(input,ticks)
		state = {"facts":input.world.freeze()}
		if not _cache.publish(key,state): push_error("Cannot publish legal training checkpoint: "+key)
	var copy: Dictionary = _bind(WorldState.new(state.facts.duplicate(true)))
	_recorder.preparation_elapsed(started)
	return copy

func _training_ticks(x: Dictionary, ticks: int) -> void:
	for _tick: int in ticks:
		x.world.facts.sim_tick += 1
		x.d.advance(x.world)
		x.d.settle(x.world)

func _life_ticks(x: Dictionary, ticks: int, move: bool = false) -> void:
	for _tick: int in ticks:
		x.world.facts.sim_tick += 1
		var previous: Dictionary = {}
		if move:
			for id: String in x.world.ids("staff"):
				previous[id] = x.world.facts.actors[id].location.duplicate(true)
			x.space.advance(x.world)
		x.w.advance(x.world,{},previous)

func _reach_life_phase(x: Dictionary, id: String, phase: String, maximum_ticks: int = 600) -> bool:
	for _tick: int in maximum_ticks:
		if x.world.facts.staff[id].life_task.phase==phase:
			return true
		x.w.dispatch(x.world)
		if x.world.facts.staff[id].life_task.phase==phase:
			return true
		_life_ticks(x,1,true)
	return x.world.facts.staff[id].life_task.phase==phase

func _visit(x: Dictionary, id: String = "visit", cell: Array = [38,76], personality: String = "PP01") -> Dictionary:
	var binding: Dictionary = {}
	for candidate: Dictionary in _content.catalog.treatment_bindings:
		if candidate.species_id=="S49":
			binding = candidate
			break
	var actor_id: String = "patient_"+id
	x.world.facts.actors[actor_id] = {"id":actor_id,"name":"候诊患者","species_id":binding.species_id,"body_binding_id":binding.id,
		"location":{"kind":"floor","floor_id":1,"cell":cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
	var visit: Dictionary = {"id":id,"actor_id":actor_id,"disease_id":binding.disease_id,"binding_id":binding.id,
		"requested_plan_id":"P_"+binding.disease_id+"_COMMON","expression":"clear","personality_id":personality,"anger":50.0,
		"phase":"arrival","evidence_by_source":{},"attempt_ids":[],"plan_decision":{},"complex":false,"final_result":"",
		"waiting_reason":"","ticket_id":"","doctor_fee_quote":-1,"arrival_tick":0,"arrived_tick":0,
		"last_progress_tick":0,"last_service_tick":0,"arrival_key":"arrival_"+id}
	x.world.facts.visits[id] = visit
	x.c._queue(x.world,visit,"gp")
	var ticket: Dictionary = x.world.facts.tickets[visit.ticket_id]
	ticket.waited_ticks = 900
	ticket.pause_reasons = {}
	ticket.service_assigned = false
	ticket.called_tick = -1
	x.l.ensure(x.world)
	x.p.ensure(x.world)
	return visit

func _seat_checkpoint(x: Dictionary, visit: Dictionary, facility_id: String) -> bool:
	var reason: String = x.space.reserve_facility(x.world,facility_id,visit.actor_id,visit.actor_id)
	if not reason.is_empty():
		return false
	var layout: Dictionary = x.space.facility_layout(x.world,facility_id)
	_position(x,visit.actor_id,layout.patient_cell)
	x.world.facts.actors[visit.actor_id].posture = "seated"
	x.world.facts.actors[visit.actor_id].support_facility_id = facility_id
	x.world.facts.waiting_life.seats[visit.id] = {"facility_id":facility_id,"actor_id":visit.actor_id,"ticket_id":visit.ticket_id,
		"phase":"seated","continuous_ticks":0,"id":"seat_"+visit.id,"public_purpose":"seat","mode":"manual","manual_facility_id":facility_id,"area":x.space.public_areas.for_facility(x.world,facility_id),"arrived_tick":x.world.sim_tick,"started_tick":x.world.sim_tick,"area_travel_ticks":0}
	x.space.sync_actor(x.world,visit.actor_id)
	return true

func _hire_payload(card: Dictionary, filter: Dictionary) -> Dictionary:
	return {"standard_key":card.standard_key,"ordinal":card.ordinal,"quote_hash":card.quote_hash,"filter":filter.duplicate(true)}

func _base_selection_examples() -> Dictionary:
	var reversed_ids: Array = []
	var nearest_ok: bool = true
	for reverse: bool in [false,true]:
		var x: Dictionary = _fixture({"nurse":"nurse"})
		var near_id: String = "a" if reverse else "b"
		var far_id: String = "b" if reverse else "a"
		_facility(x,near_id,"SE06",[42,80])
		_facility(x,far_id,"SE06",[52,80])
		_position(x,"nurse",[44,79])
		var near_route: Dictionary = x.space.route(x.world,"nurse",1,[44,80])
		var far_route: Dictionary = x.space.route(x.world,"nurse",1,[54,80])
		x.d.dispatch(x.world)
		var selected: String = str(x.world.facts.staff.nurse.base_task.get("facility_id",""))
		var before_save: Dictionary = x.world.freeze()
		x = _restore(x)
		var kept: bool = x.world.freeze()==before_save
		nearest_ok = nearest_ok and near_route.ok and far_route.ok and int(near_route.arrival_ticks)<int(far_route.arrival_ticks) and selected==near_id and kept
		reversed_ids.append({"near_id":near_id,"selected":selected,"near_ticks":near_route.get("arrival_ticks",-1),"far_ticks":far_route.get("arrival_ticks",-1),"saved":kept})
	var occupied: Dictionary = _fixture({"holder":"nurse"})
	_facility(occupied,"a_far","SE06",[60,90])
	_facility(occupied,"z_near","SE06",[42,80])
	_position(occupied,"holder",[44,80])
	occupied.d.dispatch(occupied.world)
	_training_ticks(occupied,55)
	occupied.world.facts.staff.holder.base_task.erase("queue_tick")
	var legacy_task: Dictionary = occupied.world.facts.staff.holder.base_task.duplicate(true)
	var legacy_valid: bool = occupied.d.validate(occupied.world).is_empty() and occupied.world.facts.staff.holder.base_task==legacy_task
	HospitalFactory._add_staff(occupied.world,"z_earlier","先到护士","nurse",[44,79],_content)
	occupied = _bind(occupied.world)
	occupied.d.dispatch(occupied.world)
	var first_queued: bool = occupied.world.facts.staff.z_earlier.base_task.get("facility_id","")=="z_near" and not occupied.world.facts.moves.has("z_earlier") and occupied.world.facts.staff.holder.base_task.get("remaining_ticks",-1)==5 and occupied.world.facts.staff.holder.base_task.get("queue_tick",-1)==occupied.world.sim_tick
	_training_ticks(occupied,1)
	HospitalFactory._add_staff(occupied.world,"a_later","后到护士","nurse",[46,79],_content)
	occupied = _bind(occupied.world)
	occupied.d.dispatch(occupied.world)
	var both_queued: bool = occupied.world.facts.staff.a_later.base_task.get("facility_id","")=="z_near" and not occupied.world.facts.moves.has("a_later") and int(occupied.world.facts.staff.z_earlier.base_task.get("queue_tick",-1))<int(occupied.world.facts.staff.a_later.base_task.get("queue_tick",-1))
	var queue_snapshot: Dictionary = occupied.world.freeze()
	occupied = _restore(occupied)
	var saved_queue: bool = occupied.world.freeze()==queue_snapshot
	_training_ticks(occupied,3)
	var last_occupied_tick: bool = not occupied.world.facts.staff.holder.base_prepared and occupied.world.facts.staff.holder.base_task.get("remaining_ticks",-1)==1 and occupied.world.facts.staff.z_earlier.base_task.get("remaining_ticks",-1)==60 and occupied.world.facts.staff.a_later.base_task.get("remaining_ticks",-1)==60
	_training_ticks(occupied,1)
	var earliest_arrived: bool = false
	var later_waits: bool = true
	for _tick: int in 60:
		occupied.d.dispatch(occupied.world)
		later_waits = later_waits and not occupied.world.facts.moves.has("a_later") and occupied.world.facts.staff.a_later.base_task.get("remaining_ticks",-1)==60
		if occupied.world.facts.staff.z_earlier.base_task.get("phase","")=="working":
			earliest_arrived = occupied.space.at(occupied.world,"z_earlier",1,[44,80])
			break
		occupied.world.facts.sim_tick += 1
		occupied.space.advance(occupied.world)
		occupied.d.advance(occupied.world)
		occupied.d.settle(occupied.world)
	_training_ticks(occupied,60)
	var earlier_complete: bool = occupied.world.facts.staff.holder.base_prepared and occupied.world.facts.staff.z_earlier.base_prepared and not occupied.world.facts.staff.a_later.base_prepared and occupied.world.facts.staff.a_later.base_task.get("remaining_ticks",-1)==60
	var short_occupation: bool = legacy_valid and first_queued and both_queued and saved_queue and last_occupied_tick and earliest_arrived and later_waits and earlier_complete
	return {"ok":nearest_ok and short_occupation,"reversed_ids":reversed_ids,"short_occupation":{"legacy_valid":legacy_valid,"first_queued":first_queued,"both_queued":both_queued,"saved":saved_queue,"last_occupied_tick":last_occupied_tick,"earliest_arrived":earliest_arrived,"later_waits":later_waits,"earlier_complete":earlier_complete}}

func _base_arrangement_command(sim: HospitalSimulation, kind: String, payload: Dictionary, id: String) -> CommandResult:
	return sim.apply(GameCommand.new("staff_base_"+id,sim.world.hospital_id,sim.world.revision,kind,BusinessPayload.new(payload)))

func _base_arrangement_ticks(sim: HospitalSimulation, ticks: int) -> void:
	for _tick: int in ticks:
		sim.world.facts.sim_tick += 1
		sim.services.remodel.dispatch(sim.world)
		sim.services.development.dispatch(sim.world)
		sim.space.advance(sim.world)
		sim.services.development.advance(sim.world)
		sim.services.development.settle(sim.world)
		sim.world.touch()
		sim.space.finish_boundary(sim.world)

func _base_arrangement_examples() -> Dictionary:
	var x: Dictionary = _fixture({"doctor":"doctor"})
	HospitalFactory._add_room(x.world,{"id":"base_office","type":"doctor_office","anchor":[36,79],"size":[4,4],"door":{"definition_id":"DR01","offset":1}},_content)
	_facility(x,"base","SE05",[36,80],"base_office")
	_position(x,"doctor",[38,80])
	var working: HospitalSimulation = HospitalSimulation.new(x.world,_content)
	working.services.development.dispatch(working.world)
	_base_arrangement_ticks(working,30)
	var cash: int = HospitalLedger.balance(working.world)
	var prepare_room: CommandResult = _base_arrangement_command(working,"remodel_prepare",{"commands":[{"kind":"build_move","target_id":"base_office","cell":[45,79],"floor_id":1}]},"prepare_working")
	var room_order: String = str(prepare_room.changed_ids[0]) if prepare_room.accepted else ""
	working.services.remodel.dispatch(working.world)
	working.services.development.dispatch(working.world)
	var work_held: bool = not working.world.facts.moves.has("doctor") and working.world.facts.staff.doctor.base_task.get("remaining_ticks",-1)==30
	_base_arrangement_ticks(working,29)
	work_held = work_held and not working.world.facts.moves.has("doctor") and not working.world.facts.staff.doctor.base_prepared and working.world.facts.staff.doctor.base_task.get("remaining_ticks",-1)==1
	_base_arrangement_ticks(working,1)
	var completed_safely: bool = working.world.facts.staff.doctor.base_prepared and working.world.facts.staff.doctor.base_task.is_empty() and not working.world.facts.moves.has("doctor") and HospitalLedger.balance(working.world)==cash
	working.services.remodel.dispatch(working.world)
	var evacuation: Dictionary = working.world.facts.moves.get("doctor",{}).duplicate(true)
	working.services.development.dispatch(working.world)
	var leaving_after_work: bool = not evacuation.is_empty() and working.world.facts.moves.get("doctor",{})==evacuation
	for _tick: int in 200:
		if not working.world.facts.moves.has("doctor"): break
		_base_arrangement_ticks(working,1)
	var vacated: bool = prepare_room.accepted and not working.world.facts.moves.has("doctor") and working.world.facts.actors.doctor.location.cell!=[38,80] and working.world.facts.staff.doctor.base_prepared and not working.services.remodel._in_affected_area(working.world,working.world.facts.remodels[room_order],working.world.facts.actors.doctor)
	var rest: CommandResult = _base_arrangement_command(working,"apply_schedule",{"changes":[{"staff_id":"doctor","schedule":_schedule(["rest","outpatient","outpatient"])}]},"new_rest_boundary")
	working.services.scheduler.boundaries(working.world)
	working.services.development.dispatch(working.world)
	var work: CommandResult = _base_arrangement_command(working,"apply_schedule",{"changes":[{"staff_id":"doctor","schedule":_schedule(["outpatient","rest","outpatient"])}]},"new_work_boundary")
	working.services.scheduler.boundaries(working.world)
	working.services.development.dispatch(working.world)
	var excludes_new: bool = rest.accepted and work.accepted and not working.world.facts.staff.doctor.base_prepared and working.world.facts.staff.doctor.base_task.is_empty() and not working.world.facts.moves.has("doctor")
	var cancelled_room: CommandResult = _base_arrangement_command(working,"remodel_cancel",{"order_id":room_order},"cancel_room")
	working.services.development.dispatch(working.world)
	var cancel_reopens: bool = cancelled_room.accepted and working.world.facts.staff.doctor.base_task.get("facility_id","")=="base" and working.world.facts.moves.has("doctor") and not working.world.facts.staff.doctor.base_prepared
	var working_ok: bool = prepare_room.accepted and work_held and completed_safely and leaving_after_work and vacated and excludes_new and cancel_reopens
	var working_details: Dictionary = {"prepare":prepare_room.code,"protected":work_held,"completed_safely":completed_safely,"leaving_after_work":leaving_after_work,"vacated":vacated,"excludes_new":excludes_new,"cancel_reopens":cancel_reopens}
	working.dispose()
	x = _fixture({"nurse":"nurse"})
	_facility(x,"base","SE06",[42,80])
	_position(x,"nurse",[44,79])
	var travelling: HospitalSimulation = HospitalSimulation.new(x.world,_content)
	travelling.services.development.dispatch(travelling.world)
	_base_arrangement_ticks(travelling,1)
	var original_task: Dictionary = travelling.world.facts.staff.nurse.base_task.duplicate(true)
	var first: CommandResult = _base_arrangement_command(travelling,"remodel_prepare",{"commands":[{"kind":"build_move","target_id":"base","cell":[44,79],"floor_id":1}]},"prepare_travel_cancel")
	var first_order: String = str(first.changed_ids[0]) if first.accepted else ""
	travelling.services.remodel.dispatch(travelling.world)
	travelling.services.development.dispatch(travelling.world)
	var paused: bool = not travelling.world.facts.moves.has("nurse") and travelling.world.facts.staff.nurse.base_task==original_task and not travelling.world.facts.staff.nurse.base_prepared
	var cancelled: CommandResult = _base_arrangement_command(travelling,"remodel_cancel",{"order_id":first_order},"cancel_travel")
	var before_resume: Dictionary = travelling.world.facts.actors.nurse.location.duplicate(true)
	travelling.services.development.dispatch(travelling.world)
	var cancel_resumes: bool = cancelled.accepted and travelling.world.facts.staff.nurse.base_task==original_task and travelling.world.facts.moves.has("nurse") and travelling.world.facts.actors.nurse.location==before_resume
	var second: CommandResult = _base_arrangement_command(travelling,"remodel_prepare",{"commands":[{"kind":"build_move","target_id":"base","cell":[44,79],"floor_id":1}]},"prepare_travel_apply")
	var second_order: String = str(second.changed_ids[0]) if second.accepted else ""
	travelling.services.remodel.dispatch(travelling.world)
	travelling.services.development.dispatch(travelling.world)
	travelling.services.remodel.dispatch(travelling.world)
	var vacating_move: Dictionary = travelling.world.facts.moves.get("nurse",{}).duplicate(true)
	travelling.services.development.dispatch(travelling.world)
	var preserves_evacuation: bool = not vacating_move.is_empty() and vacating_move.get("target_cell",[])!=[44,80] and travelling.world.facts.moves.get("nurse",{})==vacating_move
	var keeps_task: bool = true
	for _tick: int in 200:
		keeps_task = keeps_task and travelling.world.facts.staff.nurse.base_task==original_task
		if not travelling.world.facts.moves.has("nurse"): break
		_base_arrangement_ticks(travelling,1)
	var paused_snapshot: Dictionary = travelling.world.freeze()
	travelling.dispose()
	travelling = HospitalSimulation.new(WorldState.new(paused_snapshot),_content)
	var restored: bool = travelling.world.facts.staff.nurse.base_task==original_task and travelling.world.facts.remodels.get(second_order,{}).get("state","")=="preparing"
	var plan: Dictionary = travelling.services.remodel.preview(travelling.world,second_order)
	var applied: CommandResult = _base_arrangement_command(travelling,"remodel_apply",{"order_id":second_order,"quote":{"price":plan.get("price",-1),"refund":plan.get("refund",-1),"layout":plan.get("layout",[])}},"apply_travel_base")
	var applied_location: Dictionary = travelling.world.facts.actors.nurse.location.duplicate(true)
	travelling.services.development.dispatch(travelling.world)
	var moved_base: Dictionary = travelling.space.facility_layout(travelling.world,"base")
	var resumes_new_position: bool = applied.accepted and travelling.world.facts.facilities.base.cell==[44,79] and moved_base.operator_cells[0]!=[44,80] and travelling.world.facts.staff.nurse.base_task==original_task and travelling.world.facts.moves.get("nurse",{}).get("target_cell",[])==moved_base.operator_cells[0] and travelling.world.facts.actors.nurse.location==applied_location
	var arrived: bool = false
	for _tick: int in 200:
		travelling.services.development.dispatch(travelling.world)
		if travelling.world.facts.staff.nurse.base_task.get("phase","")=="working":
			arrived = travelling.space.at(travelling.world,"nurse",int(moved_base.floor_id),moved_base.operator_cells[0]) and travelling.world.facts.staff.nurse.base_task.get("remaining_ticks",-1)==60
			break
		_base_arrangement_ticks(travelling,1)
	_base_arrangement_ticks(travelling,60)
	var completed_original: bool = travelling.world.facts.staff.nurse.base_prepared and travelling.world.facts.staff.nurse.base_task.is_empty()
	var travel_ok: bool = first.accepted and paused and cancel_resumes and second.accepted and preserves_evacuation and keeps_task and restored and plan.get("ok",false) and resumes_new_position and arrived and completed_original
	var travel_details: Dictionary = {"first_prepare":first.code,"paused":paused,"cancel_resumes":cancel_resumes,"second_prepare":second.code,"preserves_evacuation":preserves_evacuation,"keeps_task":keeps_task,"restored":restored,"plan":plan.get("reason",""),"apply":applied.code,"resumes_new_position":resumes_new_position,"arrived":arrived,"completed_original":completed_original}
	travelling.dispose()
	return {"ok":working_ok and travel_ok,"working":working_details,"travelling":travel_details}

func _schedule(kinds: Array) -> Array:
	var result: Array = []
	for kind: String in kinds:
		result.append({"kind":kind,"pools":[],"locked":false})
	return result

func _sleep_fixture(role: String) -> Dictionary:
	var x: Dictionary = _fixture({"sleeper":role})
	var room: String = _room(x)
	_facility(x,"bed","SE04",[43,75],room)
	_position(x,"sleeper",x.space.facility_layout(x.world,"bed").patient_cell)
	var staff: Dictionary = x.world.facts.staff.sleeper
	staff.awake_ticks = 13500
	staff.energy = 50.0
	staff.stress_milli = 50000
	staff.fatigue = 10.0 if role=="doctor" else 0.0
	x.w.dispatch(x.world)
	x.w.dispatch(x.world)
	return x
