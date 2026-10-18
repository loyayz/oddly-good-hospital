extends RefCounted

# Read only witnesses of an original complete snapshot boundary. The original
# loader verifies the entire canonical payload hash; this independently checks
# identity, RNG and a named clinical owner's commitments without copying history.
static func capture(world: WorldState, required: Dictionary = {}) -> Dictionary:
	var facts: Dictionary = world.facts
	var result: Dictionary = {"hospital_id":world.hospital_id,"sim_tick":world.sim_tick,"world_revision":world.revision,"rng":facts.rng.duplicate(true),"required_session":required.duplicate(true)}
	if required.is_empty(): return result
	var session: Dictionary = facts.sessions.get(str(required.get("id","")),{})
	var visit_id: String = str(session.get("visit_id",required.get("visit_id","")))
	var visit: Dictionary = facts.visits.get(visit_id,{})
	result.session = session.duplicate(true)
	result.visit = visit.duplicate(true)
	result.preparation = facts.preparations.get(visit_id,{}).duplicate(true)
	result.attempts = {}
	result.issues = {}
	result.ward_stays = {}
	result.tickets = {}
	result.actors = {}
	result.staff = {}
	result.facilities = {}
	result.adaptations = {}
	result.moves = {}
	var actors: Dictionary = {}
	var facilities: Dictionary = {}
	_actors(session,actors)
	_actors(result.preparation,actors)
	_facilities(session,facilities)
	_facilities(result.preparation,facilities)
	if not visit.is_empty(): actors[str(visit.actor_id)] = true
	for attempt_id: String in visit.get("attempt_ids",[]):
		var attempt: Dictionary = facts.attempts.get(attempt_id,{})
		var stay: Dictionary = facts.ward_stays.get(attempt_id,{})
		result.attempts[attempt_id] = attempt.duplicate(true)
		result.issues[attempt_id] = facts.inventory.issues.get(attempt_id,{}).duplicate(true)
		result.ward_stays[attempt_id] = stay.duplicate(true)
		_actors(attempt,actors)
		_actors(stay,actors)
		_facilities(attempt,facilities)
		_facilities(stay,facilities)
	for record: Dictionary in [session,visit,result.preparation]:
		var ticket_id: String = str(record.get("ticket_id",""))
		if not ticket_id.is_empty(): result.tickets[ticket_id] = facts.tickets.get(ticket_id,{}).duplicate(true)
	for id: String in actors:
		result.actors[id] = facts.actors.get(id,{}).duplicate(true)
		result.staff[id] = facts.staff.get(id,{}).duplicate(true)
		result.moves[id] = facts.moves.get(id,{}).duplicate(true)
	for id: String in facilities:
		result.facilities[id] = facts.facilities.get(id,{}).duplicate(true)
		result.adaptations[id] = facts.adaptations.get(id,{}).duplicate(true)
	return result

static func _actors(record: Dictionary, ids: Dictionary) -> void:
	for id: String in record.get("staff_ids",[]): ids[id] = true
	for key: String in ["nurse_id","round_doctor_id","escort_id","coverage_nurse_id"]:
		var id: String = str(record.get(key,""))
		if not id.is_empty(): ids[id] = true

static func _facilities(record: Dictionary, ids: Dictionary) -> void:
	for key: String in ["facility_id","bed_id","transfer_from_bed_id"]:
		var id: String = str(record.get(key,""))
		if not id.is_empty(): ids[id] = true
