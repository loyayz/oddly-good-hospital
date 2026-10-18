extends RefCounted

class UnreachableWorker extends HospitalSpace:
	var rejected_routes: int = 0
	func route(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false) -> Dictionary:
		if actor_id=="gather_worker":
			rejected_routes += 1
			return {"ok":false,"status":"no_route","reason":"controlled unreachable gathering operator"}
		return super.route(world,actor_id,floor_id,target,members,offsets,ignore_people)

func run_case(t, content: HospitalContent) -> void:
	var results: Array = []
	var passed: bool = true
	for kind: String in ["reception","gp"]:
		var result: Dictionary = _competition(content,kind)
		results.append(result)
		passed = passed and result.passed
	var permissions: Dictionary = _permissions(content)
	var failed_route: Dictionary = _failed_route(content)
	t.check("CLIN-33",passed and permissions.passed and failed_route.passed,{"competition":results,"permissions":permissions,"failed_route":failed_route})

func _context(content: HospitalContent, kind: String, geometry: HospitalSpace = null) -> Dictionary:
	var world: WorldState = HospitalFactory.create("00000000-0000-4000-8000-000000003300","服务到齐预约",false,content)
	var plots: Array = []
	for x: int in 3:
		for y: int in 3: plots.append([x,y])
	world.facts.floors.overrides["1"].plots = plots
	var definition_id: String = "FUR01" if kind=="reception" else "FUR02"
	var definition: Dictionary = content.facility_definition(definition_id)
	for index: int in 2:
		var room_id: String = "gather_room_"+str(index)
		var origin: Array = [8+index*18,8]
		HospitalFactory._add_room(world,{"id":room_id,"type":"gp","anchor":origin,"size":[8,8],"door":{"definition_id":"DR04","offset":3}},content)
		HospitalFactory._add_facility(world,{"id":"gather_facility_"+str(index),"definition_id":definition_id,"anchor":[int(origin[0])+1,int(origin[1])+2],"size":definition.footprint,"room_id":room_id},content)
	HospitalFactory._add_staff(world,"gather_worker","服务职员","receptionist" if kind=="reception" else "doctor",[20,20],content)
	var space: HospitalSpace = geometry if geometry!=null else HospitalSpace.new(content)
	var clinic: HospitalClinic = HospitalClinic.new(content,space)
	clinic.ensure(world)
	for index: int in 2:
		var actor_id: String = "gather_patient_"+str(index)
		var visit_id: String = "gather_visit_"+str(index)
		var binding: Dictionary = content.definition("treatment_bindings","B_S13_D09_M09")
		world.facts.actors[actor_id] = {"id":actor_id,"name":"候诊居民","species_id":binding.species_id,"body_binding_id":binding.id,"facing":0.0,"posture":"standing","location":{"kind":"floor","floor_id":1,"cell":[20+index*4,24],"height_m":0.0}}
		world.facts.visits[visit_id] = {"id":visit_id,"actor_id":actor_id,"disease_id":binding.disease_id,"binding_id":binding.id,"requested_plan_id":"P_D09_COMMON","expression":"clear","personality_id":"PP01","anger":15.0,"phase":"arrival","evidence_by_source":{},"attempt_ids":[],"plan_decision":{},"complex":false,"final_result":"","waiting_reason":"","ticket_id":"","doctor_fee_quote":-1,"arrived_tick":0,"arrival_key":visit_id,"last_progress_tick":0,"last_service_tick":0}
		world.facts.arrival_receipts[visit_id] = visit_id
		# Declared queue input: the measured operation is gathering and actual
		# arrival, not the prior reception or diagnostic service.
		clinic._queue(world,world.facts.visits[visit_id],kind)
	world.touch()
	return {"world":world,"space":space,"clinic":clinic,"validation":world.validate(content)}

func _competition(content: HospitalContent, kind: String) -> Dictionary:
	var c: Dictionary = _context(content,kind)
	var world: WorldState = c.world
	var clinic: HospitalClinic = c.clinic
	var first: Dictionary = world.facts.visits.gather_visit_0
	var second: Dictionary = world.facts.visits.gather_visit_1
	clinic._dispatch_service(world,first,world.facts.tickets[first.ticket_id])
	var first_assigned: bool = bool(world.facts.tickets[first.ticket_id].get("service_assigned",false)) and world.facts.sessions.is_empty()
	var scalar_busy: bool = clinic._staff_busy(world,"gather_worker") and not clinic._staff_busy(world,"gather_worker",first.id)
	var view: Dictionary = clinic._build_availability(world)
	var view_busy: bool = clinic._staff_busy(world,"gather_worker","",view) and not clinic._staff_busy(world,"gather_worker",first.id,view)
	var before: Dictionary = world.freeze()
	var structural: bool = not clinic.service_candidates(world,second,kind,true).is_empty() and world.freeze()==before
	clinic._dispatch_service(world,second,world.facts.tickets[second.ticket_id])
	var second_waits: bool = not bool(world.facts.tickets[second.ticket_id].get("service_assigned",false))
	var exclusive: bool = true
	var started: bool = false
	var steps: int = 0
	while first_assigned and second_waits and steps<500:
		clinic.dispatch(world)
		c.space.advance(world)
		clinic.advance(world)
		world.facts.sim_tick += 1
		world.touch(false)
		c.space.finish_boundary(world)
		steps += 1
		if world.facts.tickets.has(second.ticket_id) and bool(world.facts.tickets[second.ticket_id].get("service_assigned",false)): exclusive = false
		for session: Dictionary in world.facts.sessions.values():
			if session.visit_id==first.id and int(session.remaining_ticks)==int(session.total_ticks)-1: started = true
		if started: break
	return {"passed":c.validation.is_empty() and first_assigned and scalar_busy and view_busy and structural and second_waits and exclusive and started,"kind":kind,"input_validation":c.validation,"first_reservation_created":first_assigned,"scalar_busy_and_own_exemption":scalar_busy,"view_busy_and_own_exemption":view_busy,"structural_candidates_retained_readonly":structural,"second_keeps_ticket_unassigned":second_waits and exclusive,"original_service_started_after_real_walk":started,"actual_steps":steps}

func _permissions(content: HospitalContent) -> Dictionary:
	var c: Dictionary = _context(content,"gp")
	var world: WorldState = c.world
	var clinic: HospitalClinic = c.clinic
	var first: Dictionary = world.facts.visits.gather_visit_0
	clinic._dispatch_service(world,first,world.facts.tickets[first.ticket_id])
	var reservation: Dictionary = world.facts.adaptations.get("gather_facility_0",{})
	if reservation.is_empty(): return {"passed":false,"reason":"missing original gathering reservation"}
	reservation.owner_id = first.actor_id
	var released: bool = not clinic._staff_busy(world,"gather_worker") and not clinic._staff_busy(world,"gather_worker","",clinic._build_availability(world))
	reservation.owner_id = "missing_ticket"
	var orphan: bool = not clinic._staff_busy(world,"gather_worker") and not clinic._staff_busy(world,"gather_worker","",clinic._build_availability(world))
	reservation.owner_id = first.ticket_id
	world.facts.tickets[first.ticket_id].service_assigned = false
	var inactive: bool = not clinic._staff_busy(world,"gather_worker") and not clinic._staff_busy(world,"gather_worker","",clinic._build_availability(world))
	HospitalFactory._add_room(world,{"id":"gather_ward","type":"ward","anchor":[46,8],"size":[8,8],"door":{"definition_id":"DR04","offset":3}},content)
	HospitalFactory._add_facility(world,{"id":"gather_bed","definition_id":"EQ05","anchor":[47,9],"size":content.facility_definition("EQ05").footprint,"room_id":"gather_ward"},content)
	HospitalFactory._add_staff(world,"gather_nurse","病房护士","nurse",[44,20],content)
	world.touch()
	var bed_reason: String = c.space.reserve_facility(world,"gather_bed",world.facts.visits.gather_visit_1.actor_id,world.facts.visits.gather_visit_1.actor_id,["gather_nurse"])
	var before: Dictionary = world.freeze()
	var permission: bool = bed_reason.is_empty() and not clinic._staff_busy(world,"gather_nurse") and not clinic._staff_busy(world,"gather_nurse","",clinic._build_availability(world)) and world.freeze()==before
	return {"passed":released and orphan and inactive and permission,"released_permission_not_busy":released,"orphan_not_busy":orphan,"inactive_ticket_not_busy":inactive,"bed_passage_permission_not_active_work":permission,"bed_reason":bed_reason}

func _failed_route(content: HospitalContent) -> Dictionary:
	var geometry: UnreachableWorker = UnreachableWorker.new(content)
	var c: Dictionary = _context(content,"gp",geometry)
	var visit: Dictionary = c.world.facts.visits.gather_visit_0
	var before: Dictionary = c.world.freeze()
	c.clinic._dispatch_service(c.world,visit,c.world.facts.tickets[visit.ticket_id])
	var unchanged: bool = true
	for field: String in ["adaptations","moves","tickets","sessions","preparations","attempts","inventory","ledger","rng","entity_next"]:
		unchanged = unchanged and c.world.facts[field]==before[field]
	return {"passed":geometry.rejected_routes>0 and unchanged,"rejected_real_operator_route_checks":geometry.rejected_routes,"no_assignment_or_resource_effect":unchanged}
