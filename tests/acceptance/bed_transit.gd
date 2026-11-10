extends RefCounted
# Declared upper-floor ward and bedside patient input. The group actually
# assembles, boards, rides and alights before/after the new bed claim.
func run(content: HospitalContent) -> Dictionary:
	var h: RefCounted=load("res://tests/acceptance/space.gd").new();h.content=content
	var checks: Dictionary={};var observations: Dictionary={}
	for variant: String in ["safe_landing","terminal","short_tail","single_terminal"]:
		var terminal: bool=variant!="safe_landing"
		var single: bool=variant=="single_terminal"
		var sim: HospitalSimulation=h._transit_fixture();var w: WorldState=sim.world;var s: HospitalSpace=sim.space
		var id: String=h._connection(sim);var b: BuildService=BuildService.new(content,s);b._deferred_checks=true
		for r: Dictionary in content.catalog.research:
			if r.id not in w.facts.research:w.facts.research.append(r.id)
		HospitalSpace.materialize_layout(w,2)
		var origin: Array=[32,76] if single else ([34,76] if terminal else [34,78])
		var bed: Array=[34,77] if single else ([37,77] if terminal else [39,79])
		b._add_room(w,{"id":"ward","room_type_id":"ward","floor_id":2,"origin":origin,"size":[30 if single else 28,92-int(origin[1])],"doors":[{"definition_id":"DR06","edge":"north","offset":4 if single else 2},{"definition_id":"DR06","edge":"south","offset":14}]})
		b._add_facility(w,{"id":"bed","definition_id":"EQ05","floor_id":2,"cell":bed,"rotation":0,"room_id":"ward"})
		h._add_actor(sim,"p","S49",[int(bed[0]),int(bed[1])+3],2)
		h._add_actor(sim,"n","S49",[57,88],2);h._add_actor(sim,"d","S49",[59,88],2)
		h._add_actor(sim,"leader","S49",[44,80])
		if not single:h._add_actor(sim,"follower","S49",[42,80])
		var validation: String=w.validate(content)
		var goal: Array=[36,76] if single else ([35,78] if variant=="short_tail" else ([36,78] if terminal else [38,81]))
		var request: String=s.request_move(w,"leader",2,goal) if single else s.request_group_move(w,"leader",["leader","follower"],{},2,goal)
		var boarded: bool=h._wait(sim,func()->bool:return w.facts.connectors[id].phase=="riding",350,h._movement_tick.bind(sim))
		var reserved: String=s.reserve_facility(w,"bed","p","p",["n","d"])
		if reserved.is_empty():sim.clinic._support(w,{"actor_id":"p"},s.facility_layout(w,"bed"),"lying")
		var sequence: int=w.facts.moves.get("leader",{}).get("request_sequence",-1)
		var gate_seen: bool=false;var safe: bool=true;var errors: Array=[]
		for i: int in 400:
			h._movement_tick(sim)
			var e: String=w.validate(content)
			if not e.is_empty():errors.append(e);safe=false;break
			if not w.facts.moves.get("leader",{}).get("waiting_reason","").is_empty() and "护理床岗位" in str(w.facts.moves.leader.waiting_reason):gate_seen=true
			if gate_seen and (terminal or w.facts.connectors[id].phase=="idle"):break
		var c: Dictionary=w.facts.connectors[id];var m: Dictionary=w.facts.moves.get("leader",{})
		var prefix: String=variant
		checks[prefix+"_legal_input"]=validation.is_empty()
		checks[prefix+"_actual_boarding"]=request.is_empty() and boarded and reserved.is_empty()
		checks[prefix+"_held_without_reissue"]=gate_seen and int(m.get("request_sequence",-2))==sequence and ConvoyTrail.point(m.get("target_cell",[0,0]))==ConvoyTrail.point(goal)
		checks[prefix+"_safe_ownership"]=c.phase=="alighting" and w.facts.actors.leader.location.kind=="transit" if terminal else c.phase=="idle" and s.at(w,"leader",2,[36,78])
		observations[prefix]={"validation":validation,"request":request,"boarded":boarded,"reservation":reserved,"connection_phase":c.phase,"leader":w.facts.actors.leader.location.duplicate(true),"move":m.duplicate(true),"errors":errors}
		var release_request: String=s.request_move(w,"p",2,[52,88])
		var departed: bool=h._wait(sim,func()->bool:return not w.facts.adaptations.has("bed") and not w.facts.moves.has("p"),250,h._movement_tick.bind(sim))
		var arrived: bool=h._wait(sim,func()->bool:return not w.facts.moves.has("leader") and s.at(w,"leader",2,goal),400,h._movement_tick.bind(sim))
		checks[prefix+"_real_release_and_resume"]=release_request.is_empty() and departed and arrived
		checks[prefix+"_valid_movement"]=safe and w.validate(content).is_empty()
		sim.dispose()
	var failed: Array=[]
	for key: String in checks:
		if not checks[key]:failed.append(key)
	return {"ok":failed.is_empty(),"checks":checks,"failed":failed,"observations":observations}
