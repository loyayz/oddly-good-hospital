extends RefCounted
const Fixture = preload("res://tests/acceptance/clinical_gathering.gd")
var content: HospitalContent
var results: Dictionary = {}
func _held(world: WorldState, visit_id: String, original_ticket: String) -> Array:
	var result: Array = []
	for id: String in world.ids("adaptations"):
		var r: Dictionary = world.facts.adaptations[id]
		if r.get("kind","")=="facility" and (r.get("actor_id","")==world.facts.visits[visit_id].actor_id or r.get("owner_id","")==original_ticket):
			result.append({"facility":id,"owner":r.get("owner_id",""),"actor":r.get("actor_id",""),"staff":r.get("staff_ids",[])})
	return result
func _snapshot(c: Dictionary, ticket_id: String) -> Dictionary:
	var w: WorldState = c.world
	var v: Dictionary = w.facts.visits.gather_visit_0
	return {"tick":w.sim_tick,"phase":v.phase,"ticket_id":v.ticket_id,"original_ticket_present":w.facts.tickets.has(ticket_id),"held":_held(w,v.id,ticket_id),"sessions":w.facts.sessions.duplicate(true),"move_ids":w.facts.moves.keys(),"patient":w.facts.actors[v.actor_id].location.duplicate(true),"worker":w.facts.actors.gather_worker.location.duplicate(true),"validation":w.validate(content)}
func _tick(c: Dictionary, visit: Dictionary, ticket_id: String) -> void:
	c.clinic._dispatch_clinical_releases(c.world)
	if c.world.facts.tickets.has(ticket_id): c.clinic._dispatch_service(c.world,visit,c.world.facts.tickets[ticket_id])
	c.space.advance(c.world)
	c.clinic.advance(c.world)
	c.world.facts.sim_tick += 1
	c.world.touch(false)
	c.space.finish_boundary(c.world)
func _case(mode: String, kind: String) -> Dictionary:
	var c: Dictionary = Fixture.new()._context(content,kind)
	var w: WorldState = c.world
	HospitalFactory._add_staff(w,"z_second_worker","备用职员","doctor",[25,20],content)
	w.facts.facilities.gather_facility_0.open = false
	w.touch()
	var v: Dictionary = w.facts.visits.gather_visit_0
	var tid: String = v.ticket_id
	var input_validation: String = w.validate(content)
	c.clinic._dispatch_service(w,v,w.facts.tickets[tid])
	var assigned: Dictionary = _snapshot(c,tid)
	var reached: bool = false
	var moved: bool = false
	var original_patient: Dictionary = w.facts.actors[v.actor_id].location.duplicate(true)
	if mode in ["normal_control","new_earlier_desk_at_arrival","held_desk_closed_at_arrival","held_worker_offshift_at_arrival"]:
		for n: int in 500:
			# Complete only actual movement/advance after dispatch. Inspect the
			# boundary before the next dispatch can choose/start a service.
			c.space.advance(w)
			c.clinic.advance(w)
			w.facts.sim_tick += 1;w.touch(false);c.space.finish_boundary(w)
			moved = moved or w.facts.actors[v.actor_id].location!=original_patient
			var layout: Dictionary = c.space.facility_layout(w,"gather_facility_1")
			reached = c.space.at(w,v.actor_id,1,layout.patient_cell) and c.space.at(w,"gather_worker",1,layout.operator_cells[0])
			if reached: break
			if w.facts.tickets.has(tid): c.clinic._dispatch_service(w,v,w.facts.tickets[tid])
	else:
		for n: int in 3: _tick(c,v,tid)
		moved = w.facts.actors[v.actor_id].location!=original_patient
	var before_change: Dictionary = _snapshot(c,tid)
	if mode!="normal_control": w.facts.facilities.gather_facility_0.open = true
	if mode in ["held_desk_closed_during_walk","held_desk_closed_at_arrival","held_desk_closed_then_reopened"]: w.facts.facilities.gather_facility_1.open = false
	if mode in ["held_worker_offshift_during_walk","held_worker_offshift_at_arrival"]: w.facts.staff.gather_worker.on_shift = false
	if mode=="held_desk_closed_then_reopened": w.facts.facilities.gather_facility_0.open = false
	w.touch()
	var changed_validation: String = w.validate(content)
	if w.facts.tickets.has(tid): c.clinic._dispatch_service(w,v,w.facts.tickets[tid])
	var after: Dictionary = _snapshot(c,tid)
	var recoverable_wait: bool = true
	if mode=="held_desk_closed_then_reopened":
		for n: int in 30: _tick(c,v,tid)
		recoverable_wait = _owned(w,tid).is_empty() and w.facts.sessions.is_empty() and v.ticket_id==tid and not w.facts.tickets[tid].service_assigned and w.validate(content).is_empty()
		w.facts.facilities.gather_facility_0.open = true
		w.touch()
	var max_held: int = _owned(w,tid).size()
	var completed_service: bool = false
	for n: int in 650:
		_tick(c,v,tid)
		max_held = maxi(max_held,_owned(w,tid).size())
		if v.phase!="wait_"+kind and v.phase!=kind: completed_service = true;break
	var final: Dictionary = _snapshot(c,tid)
	var selected: String = ""
	if not after.sessions.is_empty(): selected = str(after.sessions.values()[0].facility_id)
	else:
		# Use the captured re-dispatch boundary, not the fully completed live
		# world where the original ticket and its ownership are gone.
		for hold: Dictionary in after.held:
			if hold.owner==tid and hold.staff==["gather_worker"]:
				selected = str(hold.facility)
				break
	var retained: bool = mode!="new_earlier_desk_at_arrival" or selected=="gather_facility_1"
	for n: int in 160:
		c.clinic._dispatch_clinical_releases(w)
		c.space.advance(w)
		w.facts.sim_tick += 1;w.touch(false);c.space.finish_boundary(w)
	var stale_ticket: bool = false
	for reservation: Dictionary in w.facts.adaptations.values(): stale_ticket = stale_ticket or reservation.owner_id==tid
	var passed: bool = recoverable_wait and input_validation.is_empty() and changed_validation.is_empty() and moved and max_held<=1 and retained and completed_service and final.validation.is_empty() and not stale_ticket and w.validate(content).is_empty()
	return {"passed":passed,"retained_pair":retained,"recoverable_wait":recoverable_wait,"stale_ticket":stale_ticket,"cleanup_validation":w.validate(content),"input_validation":input_validation,"changed_validation":changed_validation,"first_assignment":assigned,"real_motion":moved,"reached_assigned_pair":reached,"before_change":before_change,"after_one_dispatch":after,"maximum_held_facilities":max_held,"completed_service":completed_service,"final":final}

func _owned(world: WorldState, ticket_id: String) -> Array:
	var ids: Array = []
	for id: String in world.ids("adaptations"):
		if world.facts.adaptations[id].get("kind","")=="facility" and world.facts.adaptations[id].owner_id==ticket_id: ids.append(id)
	return ids

func _departure(kind: String, stage: String) -> Dictionary:
	var c: Dictionary = Fixture.new()._context(content,kind)
	var w: WorldState = c.world
	var v: Dictionary = w.facts.visits.gather_visit_0
	var other: Dictionary = w.facts.visits.gather_visit_1
	w.facts.tickets.erase(other.ticket_id)
	w.facts.actors.erase(other.actor_id)
	w.facts.arrival_receipts.erase(other.arrival_key)
	w.facts.visits.erase(other.id)
	# Legal initial location only. All measured gathering and departure is real.
	w.facts.actors[v.actor_id].location.cell = [56,44]
	w.touch()
	var input_validation: String = w.validate(content)
	var ticket_id: String = v.ticket_id
	var origin: Dictionary = w.facts.actors.gather_worker.location.duplicate(true)
	var reached: bool = false
	var fid: String = ""
	for n: int in 700:
		c.clinic._dispatch_service(w,v,w.facts.tickets[ticket_id])
		c.space.advance(w)
		w.facts.sim_tick += 1;w.touch(false);c.space.finish_boundary(w)
		var held: Array = _owned(w,ticket_id)
		if held.is_empty(): break
		fid = held[0]
		var layout: Dictionary = c.space.facility_layout(w,fid)
		reached = c.space.at(w,"gather_worker",int(layout.floor_id),layout.operator_cells[0]) if stage=="arrived" else n==2
		if reached or not w.facts.sessions.is_empty(): break
	var at_cancel: Dictionary = w.facts.actors.gather_worker.location.duplicate(true)
	var before_validation: String = w.validate(content)
	var command: Dictionary = c.clinic.execute(w,"clinical_refer",{"visit_id":v.id}).to_record()
	var unchanged: bool = at_cancel==w.facts.actors.gather_worker.location
	var same_step: String = w.validate(content)
	var obsolete_approach: bool = stage=="walking" and w.facts.moves.has("gather_worker")
	# Continue through the full production simulator, including departure and
	# safe staff release. No movement erasure or post-command teleport.
	var simulation: HospitalSimulation = HospitalSimulation.new(w,content)
	for n: int in 600: simulation.step()
	var released: bool = not w.facts.adaptations.has(fid) and not w.facts.staff.gather_worker.has("clinical_release")
	var moved_after: bool = at_cancel!=w.facts.actors.gather_worker.location
	var final_validation: String = w.validate(content)
	var passed: bool = input_validation.is_empty() and before_validation.is_empty() and reached and origin!=at_cancel and command.accepted and unchanged and same_step.is_empty() and not obsolete_approach and released and v.phase=="departed" and final_validation.is_empty() and (stage!="arrived" or moved_after)
	var result: Dictionary = {"passed":passed,"input_validation":input_validation,"before_validation":before_validation,"reached":reached,"command":command,"same_step_no_teleport":unchanged,"same_step_validation":same_step,"obsolete_approach":obsolete_approach,"released":released,"moved_after":moved_after,"final_phase":v.phase,"final_validation":final_validation,"final_staff":w.facts.actors.gather_worker.location.duplicate(true)}
	simulation.dispose()
	return result

func run_case(t, source: HospitalContent) -> void:
	content = source
	var passed: bool = true
	for kind: String in ["gp"]:
		for mode: String in ["normal_control","new_earlier_desk_at_arrival","held_desk_closed_during_walk","held_worker_offshift_during_walk","held_desk_closed_at_arrival","held_worker_offshift_at_arrival","held_desk_closed_then_reopened"]:
			var result: Dictionary = _case(mode,kind)
			results[kind+"_"+mode] = result
			passed = passed and result.passed
		for stage: String in ["walking","arrived"]:
			var result: Dictionary = _departure(kind,stage)
			results[kind+"_referral_"+stage] = result
			passed = passed and result.passed
	t.check("CLIN-36",passed,results)
