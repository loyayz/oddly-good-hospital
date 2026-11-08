extends RefCounted

func run(content: HospitalContent) -> Dictionary:
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new()
	suite.content=content
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"self","S49",[35,70]); suite._add_actor(sim,"other","S49",[36,70])
	var life: HospitalWaitingLife = sim.services.waiting
	var w: WorldState = sim.world
	life.ensure(w)
	# Explicit ownership-predicate boundary inputs, not simulated seat arrivals.
	w.facts.actors.self.support_facility_id="own"
	w.facts.actors.other.support_facility_id="shared"
	w.facts.waiting_life.seats["own"]={"phase":"seated","facility_id":"own","actor_id":"self"}
	w.facts.waiting_life.seats["travel"]={"phase":"local_travel","facility_id":"travelling","actor_id":"other"}
	w.facts.visits["predicate_visit"]={"actor_id":"other"}
	w.facts.waiting_life.needs["n"]={"phase":"using","facility_id":"need","visit_id":"predicate_visit"}
	w.facts.sessions["predicate_session"]={"facility_id":"session"}
	if not w.facts.has("staff_life"): w.facts.staff_life={}
	w.facts.staff_life.reservations={"staff":{},"":{}}
	var before: Dictionary = w.freeze()
	var checks: Dictionary = {}
	for phase: String in ["using","returning","seek","fallback"]:
		w.facts.waiting_life.needs.n.phase=phase
		var view: Dictionary = life._occupancy_view(w)
		for target: String in ["own","shared","travelling","need","session","staff","missing",""]:
			for actor_id: String in ["self","other","nobody"]:
				var owners: Dictionary = view.owners.get(target,{})
				var expected: bool = view.blocked.has(target) or not owners.is_empty() and (owners.size()>1 or not owners.has(actor_id))
				checks[phase+":"+target+":"+actor_id]=life._occupied_now(w,target,actor_id)==expected and life._occupied(w,target,actor_id)==expected
	# Shared route-query callers retain their original full view.
	sim.space.begin_route_query(w)
	checks["scope_before"]=not life._occupied(w,"own","self")
	w.facts.actors.other.support_facility_id="own"
	checks["scope_preserved"]=not life._occupied(w,"own","self")
	sim.space.end_route_query()
	checks["live_after_scope"]=life._occupied(w,"own","self")
	w.facts.actors.other.support_facility_id="shared"
	w.facts.waiting_life.needs.n.phase="using"
	checks["facts_readonly"]=w.freeze()==before
	var ok: bool = true
	for v: bool in checks.values(): ok=ok and v
	sim.dispose()
	return {"passed":ok,"checks":checks}
