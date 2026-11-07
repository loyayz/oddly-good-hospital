extends "res://tests/acceptance/clinical_fixtures.gd"

# These checks deliberately begin before admission or before an actual
# consultation. They never seed completed diagnosis/treatment to prove either.
func run(t) -> void:
	_content = HospitalContent.new()
	await _natural_diagnosis(t)
	await _consultation_waits(t)
	await _no_doctor_wait(t)
	await _bed_shortage(t)
	_low_probability(t)
	_natural_opportunity(t)
	_complex_variants(t)
	_surgery_policy(t)
	await _mixed_treatment_pool(t)
	_dispose_simulations()

func _natural_diagnosis(t) -> void:
	var c: Dictionary = _context()
	c.sim.clinic.departments = c.sim.services.departments
	for id: String in c.world.facility_ids("M09"):
		c.world.facts.facilities[id].failed = true
	c.world.touch()
	var before: Dictionary = c.world.freeze()
	var ready: Dictionary = c.sim.clinic.arrival_readiness(c.world,"B_S13_D09_M09")
	var readonly: bool = before==c.world.freeze()
	var arrived: bool = _arrive(c)
	var diagnosed: bool = arrived and await _until(t,c,func()->bool: return _visit(c).get("evidence_by_source",{}).has("gp"),1800)
	var diagnosis: Dictionary = _visit(c).get("evidence_by_source",{}).duplicate()
	var ticket_id: String = str(_visit(c).get("ticket_id",""))
	await _steps(t,c,25)
	var waiting: bool = _visit(c).get("phase","")=="wait_consult" and _visit(c).get("ticket_id","")==ticket_id
	t.check("NAT-01",ready.ok and readonly and diagnosed and waiting and c.world.facts.attempts.is_empty() and int(c.started.get("gp",0))==1,{"ready":ready,"readonly":readonly,"diagnosis":diagnosis,"waiting":waiting,"state":_state(c)})
	# Repair is an actual state change; resumed care must not redo the GP.
	for id: String in c.world.facility_ids("M09"):
		c.world.facts.facilities[id].failed = false
	c.world.touch()
	_seed_stream(c.world,"treatment",true,true,9200,9800)
	var cured: bool = await _until(t,c,func()->bool: return _visit(c).get("phase","")=="departed",2200)
	t.check("NAT-02",cured and _visit(c).get("final_result","")=="cured" and int(c.started.get("gp",0))==1 and int(c.started.get("consult",0))==1 and _income(c,"consultation")==20 and _units_used(c)==1,{"started":c.started,"state":_state(c)})

func _clone(c: Dictionary) -> Dictionary:
	var copy: Dictionary = c.duplicate(true)
	copy.world = WorldState.new(c.world.freeze())
	copy.sim = HospitalSimulation.new(copy.world,_content)
	copy.sim.clinic.departments = copy.sim.services.departments
	_simulations.append(copy.sim)
	return copy

func _consultation_waits(t) -> void:
	var base: Dictionary = _context()
	base.sim.clinic.departments = base.sim.services.departments
	var arrived: bool = _arrive(base)
	var started: bool = arrived and await _until(t,base,func()->bool: return _visit(base).get("phase","")=="consult",1800)
	if not started:
		t.check("NAT-03",false,{"consultation_missing":_state(base)})
		return
	var original: Dictionary = _session(base,"consult").duplicate(true)
	var recommended: Dictionary = original.get("selected_plan",{})
	var future_staff: Array = [str(base.doctors[1])] # The fixture assigns this separate doctor to the treatment pool.
	var consultant: String = str(original.staff_ids[0])
	var unreserved: bool = true
	for reservation: Dictionary in base.world.facts.preparations.values():
		if reservation.visit_id==base.visit_id:
			for id: String in reservation.staff_ids:
				if id!=consultant: unreserved = false
	t.check("NAT-03",not recommended.is_empty() and not future_staff.is_empty() and not consultant in future_staff and unreserved,{"consultant":consultant,"future_staff":future_staff,"selected_plan":recommended,"unreserved":unreserved})
	for shortage: String in ["supplies","staff","equipment","congestion"]:
		var c: Dictionary = _clone(base)
		var schedules: Dictionary = {}
		var units: int = int(c.world.facts.inventory.units)
		if shortage=="supplies": c.world.facts.inventory.units = 0
		if shortage=="staff":
			for id: String in future_staff:
				schedules[id] = c.world.facts.staff[id].schedule.duplicate(true)
				c.world.facts.staff[id].schedule = _schedule("rest")
		if shortage=="equipment": c.world.facts.facilities[recommended.facility_id].failed = true
		if shortage=="congestion":
			# A real, stationary body occupies the otherwise legal treatment slot.
			# We test waiting/recovery, not the bystander's earlier arrival.
			var blocker: Dictionary = c.world.facts.actors[_visit(c).actor_id].duplicate(true)
			blocker.id = "temporary_bystander"
			blocker.location.cell = c.world.facts.facilities[recommended.facility_id].patient_cell.duplicate()
			c.world.facts.actors[blocker.id] = blocker
			c.sim.space.sync_actor(c.world,blocker.id)
		c.world.touch()
		var completed: bool = await _until(t,c,func()->bool: return _visit(c).get("phase","")=="wait_outpatient",150)
		var decision: Dictionary = _visit(c).get("plan_decision",{}).duplicate(true)
		var ticket_id: String = str(_visit(c).get("ticket_id",""))
		await _steps(t,c,30)
		var remained: bool = _visit(c).get("phase","")=="wait_outpatient" and _visit(c).get("plan_decision",{})==decision and _visit(c).get("ticket_id","")==ticket_id and c.world.facts.attempts.is_empty()
		var valid: String = c.world.validate(_content)
		var resumed: Dictionary = _clone(c)
		# Current-version snapshot restore must retain completed consultation.
		var restored: bool = _visit(resumed).get("plan_decision",{})==decision and _visit(resumed).get("ticket_id","")==ticket_id
		if shortage=="supplies": resumed.world.facts.inventory.units = units
		if shortage=="staff":
			for id: String in schedules: resumed.world.facts.staff[id].schedule = schedules[id]
		if shortage=="equipment": resumed.world.facts.facilities[recommended.facility_id].failed = false
		if shortage=="congestion":
			resumed.world.facts.actors.temporary_bystander.location = {"kind":"outside"}
			resumed.sim.space.sync_actor(resumed.world,"temporary_bystander")
		resumed.world.touch()
		_seed_stream(resumed.world,"treatment",true,true,9200,9800)
		var cured: bool = await _until(t,resumed,func()->bool: return _visit(resumed).get("phase","")=="departed",2200)
		t.check("NAT-04-"+shortage,completed and remained and restored and valid.is_empty() and cured and _visit(resumed).get("final_result","")=="cured" and int(resumed.started.get("consult",0))==1 and _income(resumed,"consultation")==20 and _units_used(resumed)==1,{"completed":completed,"remained":remained,"restored":restored,"validation":valid,"started":resumed.started,"state":_state(resumed)})

func _no_doctor_wait(t) -> void:
	var c: Dictionary = _context()
	c.sim.clinic.departments = c.sim.services.departments
	for id: String in c.doctors: c.world.facts.staff[id].schedule = _schedule("rest")
	c.world.touch()
	var arrived: bool = _arrive(c)
	var waiting: bool = arrived and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="wait_gp",1000)
	await _steps(t,c,20)
	t.check("NAT-05",waiting and _visit(c).get("phase","")=="wait_gp" and int(c.started.get("gp",0))==0 and c.world.facts.attempts.is_empty(),_state(c))
	_seed_stream(c.world,"patience",true,true,1000,1000)
	var left: bool = await _until(t,c,func()->bool: return _visit(c).get("phase","")=="departed",1600)
	t.check("NAT-05-patience",left and _visit(c).get("final_result","")=="abandoned" and int(c.started.get("gp",0))==0 and c.world.facts.tickets.is_empty(),_state(c))

func _bed_shortage(t) -> void:
	var base: Dictionary = _context(true,true)
	base.sim.clinic.departments = base.sim.services.departments
	base.world.facts.staff[base.doctors[1]].abilities.treatment = 3
	var arrived: bool = _arrive(base,"B_S22_D14_M14","P_D14_COMMON")
	if arrived: _visit(base).complex = true
	base.world.touch()
	var consulted: bool = arrived and await _until(t,base,func()->bool: return _visit(base).get("phase","")=="consult",2200)
	var session: Dictionary = _session(base,"consult")
	var selected: Dictionary = session.get("selected_plan",{})
	if not consulted or selected.get("plan_id","")!="P_D14_GENTLE" or not selected.has("bed_id"):
		t.check("NAT-06",false,{"selected":selected,"state":_state(base)})
		return
	var c: Dictionary = _clone(base)
	var room_id: String = str(c.world.facts.facilities[selected.bed_id].room_id)
	c.world.facts.rooms[room_id].open = false
	c.world.touch()
	var completed: bool = await _until(t,c,func()->bool: return _visit(c).get("phase","")=="wait_outpatient",150)
	var ticket: String = str(_visit(c).get("ticket_id",""))
	var decision: Dictionary = _visit(c).get("plan_decision",{}).duplicate(true)
	await _steps(t,c,30)
	var waiting: bool = completed and _visit(c).get("phase","")=="wait_outpatient" and _visit(c).get("ticket_id","")==ticket and _visit(c).get("plan_decision",{})==decision and c.world.facts.attempts.is_empty()
	c.world.facts.rooms[room_id].open = true
	c.world.touch()
	var resumed: bool = await _until(t,c,func()->bool: return _visit(c).get("phase","")=="outpatient",1000)
	t.check("NAT-06",waiting and resumed and int(c.started.get("consult",0))==1 and not _stay(c).is_empty(),{"waited_for_bed":waiting,"resumed":resumed,"started":c.started,"state":_state(c)})
	# Removing the selected plan's research is different from resource scarcity.
	var invalid: Dictionary = _clone(base)
	for research_id: String in ["R33"]:
		while research_id in invalid.world.facts.research: invalid.world.facts.research.erase(research_id)
	invalid.world.touch()
	var reevaluate: bool = await _until(t,invalid,func()->bool: return _visit(invalid).get("phase","")=="wait_consult",150)
	t.check("NAT-07",reevaluate and _visit(invalid).get("plan_decision",{}).is_empty() and invalid.world.facts.attempts.is_empty(),_state(invalid))

class CountedClinic extends HospitalClinic:
	var physical_pairs: int = 0
	var readiness_queries: int = 0
	func arrival_readiness(world: WorldState, binding_id: String, complex_case: bool = false, explain: bool = true) -> Dictionary:
		readiness_queries += 1
		return super.arrival_readiness(world,binding_id,complex_case,explain)
	func _service_pair_reachable(world: WorldState, visit: Dictionary, facility_id: String, staff_id: String, base_layout: Dictionary, physical: Dictionary = {}) -> bool:
		physical_pairs += 1
		return super._service_pair_reachable(world,visit,facility_id,staff_id,base_layout,physical)

func _low_probability(t) -> void:
	var c: Dictionary = _context(false,true)
	var arrived: bool = _arrive(c,"B_S22_D14_M14","P_D14_COMMON")
	if not arrived:
		t.check("NAT-08",false,_state(c))
		return
	_visit(c).complex = true
	var clinic: CountedClinic = CountedClinic.new(_content,c.sim.space)
	var before: Dictionary = c.world.freeze()
	var low: Dictionary = clinic.plan_quote(c.world,c.visit_id,"P_D14_COMMON",{"structural_only":true,"ignore_supplies":true})
	var readonly: bool = before==c.world.freeze()
	var below_floor: bool = clinic._outpatient_probability(c.world,_visit(c),c.world.facts.staff[c.doctors[1]],c.world.facts.facilities.zombie_machine,_content.definition("treatment_protocols","TP_COMMON"))<0.75
	var low_calls: int = clinic.physical_pairs
	c.world.facts.staff[c.doctors[1]].abilities.treatment = 5
	c.world.facts.facilities.zombie_machine.grade = 2
	_visit(c).complex = false
	c.world.touch()
	clinic.physical_pairs = 0
	var repaired: Dictionary = clinic.plan_quote(c.world,c.visit_id,"P_D14_COMMON",{"structural_only":true,"ignore_supplies":true})
	t.check("NAT-08",not low.ok and readonly and below_floor and low_calls==0 and repaired.ok and clinic.physical_pairs>0,{"low":low,"low_physical_pairs":low_calls,"repaired":repaired,"repaired_physical_pairs":clinic.physical_pairs,"initial_quote_readonly":readonly,"qualified_doctor_below_floor":below_floor})

func _natural_opportunity(t) -> void:
	var fixture: RefCounted = preload("res://tests/acceptance/growth_fixtures.gd").new()
	fixture._content = _content
	for tutorial: bool in [false,true]:
		var c: Dictionary = fixture._context()
		fixture._single_case(c)
		for id: String in c.world.ids("staff"):
			c.world.facts.staff.erase(id)
			c.world.facts.actors.erase(id)
		c.world.facts.facilities.zombie_machine.failed = true
		c.world.touch()
		if tutorial:
			c.arrivals.execute(c.world,"tutorial_set_enabled",{"enabled":true})
			var wanted: String = ""
			for step: Dictionary in _content.catalog.onboarding_steps:
				if step.get("patient_seed") is Dictionary and step.patient_seed.get("disease_id","")=="D09": wanted = step.id
			for id: String in c.world.facts.hospital_meta.tutorial_flags.requests:
				c.world.facts.hospital_meta.tutorial_flags.requests[id].state = "pending" if id==wanted else "skipped"
		var observer: CountedClinic = CountedClinic.new(_content,c.space)
		c.arrivals.clinic = observer
		var plan: Dictionary = fixture._plan(c.world,1,[1,0,0])
		c.world.facts.arrivals.plan = plan
		c.world.facts.sim_tick = preload("res://game/arrivals/day_plan.gd").slot_tick(plan,0)
		c.arrivals.arrivals(c.world)
		var stats: Dictionary = c.arrivals.daystats(c.world)
		var candidates: Array = c.arrivals._admission_candidates(c.world)
		t.check("NAT-09-"+("tutorial" if tutorial else "random"),c.world.facts.visits.size()==1 and observer.readiness_queries==1 and candidates.size()>=1 and c.world.facts.attempts.is_empty() and int(plan.next_slot_index)==1,{"stats":stats,"readiness_queries":observer.readiness_queries,"eligible_species":candidates.size(),"visits":c.world.facts.visits})
	for simulation: HospitalSimulation in fixture._simulations: simulation.dispose()

func _complex_variants(t) -> void:
	var c: Dictionary = _context()
	var arrivals: HospitalArrivalService = c.sim.services.arrivals
	var before: Dictionary = c.world.freeze()
	var ordinary: Array = arrivals._arrival_variants(c.world,"D09")
	var readonly: bool = before==c.world.freeze()
	c.world.facts.research.append("R34")
	var expanded: Array = arrivals._arrival_variants(c.world,"D09")
	var non_surgical: String = ""
	for disease: Dictionary in _content.catalog.diseases:
		if _content.definition("treatment_plans","P_"+str(disease.id)+"_SURGERY").is_empty():
			non_surgical = disease.id
			break
	t.check("NAT-10",ordinary==[false] and readonly and expanded==[false,true] and not non_surgical.is_empty() and arrivals._arrival_variants(c.world,non_surgical)==[false],{"initial":ordinary,"unlocked":expanded,"non_surgical":non_surgical,"readonly":readonly})

func _surgery_policy(t) -> void:
	for source: String in ["doctor","director"]:
		var c: Dictionary = _context(true)
		var arrived: bool = _arrive(c)
		if not arrived:
			t.check("NAT-11-"+source,false,_state(c))
			continue
		# Legal boundary input: a surgery recommendation already exists, but no
		# preparation, resource promise or Attempt has begun. Only invalidation is tested.
		var visit: Dictionary = _visit(c)
		visit.evidence_by_source = {"gp":92.0}
		visit.plan_decision = {"plan_id":"P_D09_SURGERY","source":source,"doctor_id":c.doctors[0],"revision":1,"probability_bp":9600,"expected_team":["clin_surgeon","clin_anesthesia","clin_or_nurse"]}
		c.sim.clinic._queue(c.world,visit,"surgery")
		var ticket: Dictionary = c.world.facts.tickets[visit.ticket_id]
		var ticket_id: String = str(ticket.id)
		ticket.waited_ticks = 17
		while "R34" in c.world.facts.research: c.world.facts.research.erase("R34")
		c.world.touch()
		var units: int = int(c.world.facts.inventory.units)
		var before_validation: String = c.world.validate(_content)
		c.sim.clinic._prepare_surgery(c.world,visit,ticket)
		var after_validation: String = c.world.validate(_content)
		var reviewed: bool = visit.phase=="wait_consult" if source=="doctor" else visit.phase=="wait_surgery" and not str(visit.plan_decision.get("pending_reason","")).is_empty()
		t.check("NAT-11-"+source,before_validation.is_empty() and after_validation.is_empty() and reviewed and visit.ticket_id==ticket_id and int(ticket.waited_ticks)==17 and c.world.facts.attempts.is_empty() and c.world.facts.preparations.is_empty() and int(c.world.facts.inventory.units)==units,{"source":source,"reviewed":reviewed,"before_validation":before_validation,"after_validation":after_validation,"ticket":ticket,"decision":visit.plan_decision,"phase":visit.phase,"waiting_reason":visit.waiting_reason})

func _mixed_treatment_pool(t) -> void:
	var c: Dictionary = _context(false,true)
	c.sim.clinic.departments = c.sim.services.departments
	# First doctor can consult but cannot treat this C-profile plan. Both
	# clinicians are in the same actual treatment pool, so dispatch must skip
	# the unqualified first candidate rather than wait forever on that person.
	c.world.facts.staff[c.doctors[0]].schedule[0].pools = ["diagnosis","T01","T05"]
	c.world.touch()
	_seed_stream(c.world,"treatment",true,true,7400,9800)
	var arrived: bool = _arrive(c,"B_S22_D14_M14","P_D14_COMMON")
	var treatment: bool = arrived and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="outpatient",2200)
	var actual: Dictionary = _session(c,"outpatient").duplicate(true)
	var departed: bool = treatment and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="departed",1600)
	t.check("NAT-12",departed and _visit(c).get("final_result","")=="cured" and actual.get("staff_ids",[])==[c.doctors[1]] and _visit(c).plan_decision.doctor_id==c.doctors[0] and int(c.started.get("consult",0))==1 and _units_used(c)==3,{"consultant":_visit(c).get("plan_decision",{}).get("doctor_id",""),"actual_treatment_team":actual.get("staff_ids",[]),"started":c.started,"state":_state(c)})
