extends "res://tests/acceptance/floor_guidance.gd"

# Boundary checks exercise destination choice independently of queue geometry.
# These do not claim a completed natural walk or service session.
func run_rules(database: HospitalContent) -> Dictionary:
	_content=database
	var x: Dictionary=_base()
	var visit: Dictionary=_visit(x,"destination_rules",[40,88])
	var ticket: Dictionary=x.world.facts.tickets[visit.ticket_id]
	var checks: Dictionary={}
	x.world.facts.facilities.diagnosis.failed=true
	x.world.facts.facilities.diagnosis.open=false
	x.world.facts.facilities.diagnosis.intake_open=false
	x.world.facts.rooms.clinic.open=false
	checks.unavailable_still_exists=x.g._target_ids(x.world,visit,"gp")==["diagnosis"]
	checks.no_doctor_still_selected=x.g._choose_target(x.world,visit,ticket)=="diagnosis"
	_facility(x,"diagnosis_other","FUR02",[42,69],"clinic")
	var chosen: Dictionary={}
	for index: int in 32:chosen[x.g._choose_target(x.world,visit,ticket)]=true
	checks.random_multiple=chosen.has("diagnosis") and chosen.has("diagnosis_other")
	var current: Dictionary={"visit_id":visit.id,"request_key":x.g._key(ticket),"ticket_id":ticket.id,"phase":"destination","desk_id":"","target_id":"diagnosis","guide_floor":2,"initial_done":true,"receipts":[],"guided_target":"diagnosis","arrived_seq":-1}
	x.world.facts.floor_guidance.visits[visit.id]=current
	checks.unavailable_not_reassigned=not x.g._reselect_unreachable_target(x.world,visit,current) and current.target_id=="diagnosis"
	current.phase="ready"
	current.guide_floor=1
	current.arrived_seq=17
	x.world.facts.departments.units.general.open=false
	checks.closed_department_waits=not x.g.prepare(x.world,visit,ticket) and current.phase=="ready" and current.target_id=="diagnosis" and current.arrived_seq==17
	x.world.facts.departments.units.general.open=true
	checks.reopened_department_keeps_assignment=x.g.prepare(x.world,visit,ticket) and current.target_id=="diagnosis" and current.arrived_seq==17

	x.world.facts.facilities.erase("diagnosis")
	x.world.touch()
	checks.removal_returns_local=x.g._reselect_unreachable_target(x.world,visit,current) and current.phase=="seek" and current.guide_floor==1 and current.target_id==""
	x.world.facts.facilities.erase("diagnosis_other")
	x.world.touch()
	var reset_stages: Dictionary={}
	for stage: String in ["seek","desk_queue","to_counter","working","destination","ready"]:
		current.phase=stage
		current.target_id="removed_target"
		current.guide_floor=2
		current.queue_trip={"cell":[1,1]}
		current.tail_seen=[1,1]
		current.desk_id="guide"
		current.queue_seq=1
		x.g._desk_queue(x.world,"guide").assign([visit.id])
		var foreign_move: Dictionary={"floor_guidance_key":"another_request"}
		x.world.facts.moves[visit.actor_id]=foreign_move
		var prepared: bool=x.g.prepare(x.world,visit,ticket)
		reset_stages[stage]=not prepared and current.phase=="seek" and current.target_id=="" and current.guide_floor==1 and not current.has("queue_trip") and not current.has("tail_seen") and x.g._desk_queue(x.world,"guide").is_empty() and is_same(x.world.facts.moves.get(visit.actor_id),foreign_move)
		x.world.facts.moves.erase(visit.actor_id)
	checks.removal_all_stages=reset_stages.values().all(func(value:Variant)->bool:return value==true)
	current.phase="working"
	current.target_id="removed_between_dispatch_and_advance"
	current.guide_floor=2
	x.g.advance(x.world)
	checks.advance_removal_guard=current.phase=="seek" and current.target_id=="" and current.guide_floor==1
	checks.none_is_empty=x.g._choose_target(x.world,visit,ticket).is_empty()
	x.g._depart_missing_destination(x.world,visit,current)
	checks.missing_departs=visit.phase=="leaving" and not x.world.facts.tickets.has(ticket.id) and visit.get("guidance_departure_reason","")!=""
	var result: Dictionary={"ok":checks.values().all(func(value:Variant)->bool:return value==true),"checks":checks,"scope":"destination-boundary checks, not natural movement proof"}
	_dispose(x)
	return result
