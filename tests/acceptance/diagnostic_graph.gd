extends "res://tests/acceptance/growth_fixtures.gd"

func run_case(t, database: HospitalContent) -> void:
	_content = database
	var clinical: Dictionary = _clinical_paths()
	var mathematical: Dictionary = _exact_graph()
	for simulation: HospitalSimulation in _simulations: simulation.dispose()
	_simulations.clear()
	t.check("GROW-80",clinical.passed and mathematical.passed,{"clinical":clinical,"mathematical":mathematical})

func _clinical_paths() -> Dictionary:
	var builder = load("res://tests/acceptance/clinical_fixtures.gd").new()
	builder._content = _content
	var ctx: Dictionary = builder._context(false,true)
	_simulations.append(ctx.sim)
	_add_room(ctx.world,"graph_exam_room","gp",[42,65],[6,6])
	_add_facility(ctx.world,"graph_exam","FUR02","graph_exam_room",[44,67])
	ctx.world.facts.facilities.graph_exam.grade = 5
	builder._add_worker(ctx.world,"graph_exam_nurse","nurse",[48,75],"work",{"diagnosis":5,"treatment":0,"care":1,"surgery":0})
	var nominal: WorldState = ctx.sim.services.arrivals._capacity_reference_world(ctx.world)
	var frozen: Dictionary = ctx.world.freeze()
	var observed: Array = []
	var valid: bool = true
	for binding: String in ["B_S22_D14_M14","B_S49_D37_M37"]:
		for complex_case: bool in [false,true]:
			var candidate: Dictionary = ctx.sim.clinic._arrival_candidate(nominal,binding,complex_case)
			if not candidate.ok: return {"passed":false,"candidate":candidate}
			var query: Dictionary = {"candidates":{}}
			ctx.sim.space.begin_route_query(candidate.world,{"nominal":true})
			var gp_pairs: Array = ctx.sim.clinic._reference_candidates(candidate.world,candidate.visit,"gp",query)
			for gp: Dictionary in gp_pairs:
				var graph: Dictionary = ctx.sim.clinic._build_reference_diagnostic_stages(candidate.world,candidate.visit,gp,query)
				var expected: Array = _legal_sequences(ctx.sim.clinic,candidate.world,candidate.visit,gp)
				var actual: Array = []
				if graph.ok:
					var prefix: Array = _stage_identity(graph.gp_stages)
					if str(graph.next_group).is_empty(): actual.append(prefix)
					else:
						for tail: Array in _graph_sequences(graph.next_group,query.diagnostic_groups): actual.append(prefix+tail)
				var actual_keys: Array = _keys(actual)
				var expected_keys: Array = _keys(expected)
				valid = valid and actual_keys==expected_keys and bool(graph.ok)==not expected.is_empty()
				observed.append({"binding":binding,"complex":complex_case,"gp":gp,"branches":expected.size(),"equal":actual_keys==expected_keys,"step_groups":query.get("diagnostic_groups",{}).size()})
			ctx.sim.space.end_route_query()
	return {"passed":valid and ctx.world.freeze()==frozen and ctx.sim.space._route_queries.is_empty(),"observations":observed,"readonly":ctx.world.freeze()==frozen}

func _keys(values: Array) -> Array:
	var result: Array = []
	for value: Array in values: result.append(JSON.stringify(value))
	result.sort()
	return result

func _stage_identity(stages: Dictionary) -> Array:
	var result: Array = []
	for mode: String in ["gp","spectrum","resonance"]:
		if not stages.has(mode): continue
		var resources: Array = stages[mode].keys()
		resources.sort()
		result.append([mode,resources])
	return result

func _graph_sequences(group: String, groups: Dictionary) -> Array:
	var result: Array = []
	for part: Dictionary in groups[group]:
		var own: Array = _stage_identity(part.stage_resources)
		if not part.has("choices"): result.append(own)
		else:
			for tail: Array in _graph_sequences(part.choices[0],groups): result.append(own+tail)
	return result

func _evidence(world: WorldState, pair: Dictionary, mode: String) -> float:
	var level: int = int(world.facts.staff[pair.staff_id].abilities.diagnosis)
	var effective: float = float(world.facts.facilities[pair.facility_id].grade)*float(_content.balance.medical_equipment_effects.utilization_by_level[level])
	return 2.0*(level-1)+(2.0 if mode=="gp" else 3.0)*effective+(0.0 if mode=="gp" else float(_content.balance.tests[mode].confidence))

func _pair_identity(mode: String, pair: Dictionary) -> Array:
	var resources: Array = ["staff:"+str(pair.staff_id),"facility:"+str(pair.facility_id)]
	resources.sort()
	return [mode,resources]

func _legal_sequences(clinic: HospitalClinic, world: WorldState, visit: Dictionary, gp: Dictionary) -> Array:
	# The design adds evidence in the fixed GP/spectrum/resonance order and
	# stops as soon as it reaches the threshold. Enumerate this small legal
	# fixture independently, without the production graph or its memo identity.
	var threshold: float = float(_content.balance.diagnosis_threshold)
	var initial: float = float(clinic._profile(visit).gp_confidence)+_evidence(world,gp,"gp")
	var prefix: Array = [_pair_identity("gp",gp)]
	if initial>=threshold: return [prefix]
	var result: Array = []
	var query: Dictionary = {"candidates":{}}
	for spectrum: Dictionary in clinic._reference_candidates(world,visit,"spectrum",query):
		var after: float = initial+_evidence(world,spectrum,"spectrum")
		if after>=threshold: result.append(prefix+[_pair_identity("spectrum",spectrum)])
		else:
			for resonance: Dictionary in clinic._reference_candidates(world,visit,"resonance",query):
				if after+_evidence(world,resonance,"resonance")>=threshold: result.append(prefix+[_pair_identity("spectrum",spectrum),_pair_identity("resonance",resonance)])
	return result

func _exact_graph() -> Dictionary:
	var cases: Array = [{"probability":F.make(1),"bundles":[{"resources":{"a":F.make(1)},"choices":["step"]}],"choice_groups":{
		"step":[{"resources":{"a":F.make(1)},"choices":["tail"]},{"resources":{"b":F.make(2)}}],
		"tail":[{"resources":{"b":F.make(1)}},{"resources":{"a":F.make(2)}}]}}]
	var backend = ClassDB.instantiate("PlatformArrivalCapacity")
	var first: Dictionary = backend.call("prepare",cases,{"a":F.make(8),"b":F.make(8)})
	var changed: Dictionary = backend.call("solve",{"a":F.make(4),"b":F.make(8)})
	var zero: Dictionary = backend.call("solve",{"a":F.make(),"b":F.make(8)})
	var restored: Dictionary = backend.call("solve",{"a":F.make(8),"b":F.make(8)})
	# a+b is three per optimal Visit, so total16 gives C<=16/3;
	# equal flows on (a2,b1) and (a1,b2) attain that exact bound.
	var c_valid: bool = first.get("capacity")==F.make(16,3) and changed.get("capacity")==F.make(4) and zero.get("capacity")==F.make() and restored.get("capacity")==F.make(16,3)
	var structure: Array = [{"bundles":[{"structural_resources":["staff:t0"],"structural_choices":["gp"]},{"structural_resources":["staff:t1"],"structural_choices":["gp"]}],"choice_groups":{
		"gp":[{"structural_resources":["staff:g0"],"structural_choices":["test"]},{"structural_resources":["staff:g1"]}],
		"test":[{"structural_resources":["staff:g0","facility:s"],"structural_choices":["tail"]}],
		"tail":[{"structural_resources":["staff:g0","facility:r"]}]},"reception_bundles":[{"resources":{"staff:r":F.make(1),"facility:d":F.make(1)}}]}]
	var reception: Dictionary = {"people":{"staff:r":true},"desks":{"facility:d":true},"ratio":3}
	var k: Dictionary = PlatformArrivalMath.structure(structure,{},reception,8)
	var blocked: Dictionary = PlatformArrivalMath.structure(structure,{"staff:g0":true},reception,8)
	var unavailable: Dictionary = PlatformArrivalMath.structure(structure,{"staff:g0":true,"staff:g1":true},reception,8)
	var invalid: Array = structure.duplicate(true)
	invalid[0].choice_groups.test[0].structural_choices = ["missing"]
	var rejected: Dictionary = PlatformArrivalMath.structure(invalid,{},reception,8)
	var retried: Dictionary = PlatformArrivalMath.structure(structure,{},reception,8)
	var k_valid: bool = k.get("pairs")==2 and blocked.get("pairs")==1 and unavailable.get("pairs")==0 and rejected.has("error") and retried.get("pairs")==2
	var expanded: Array = [{"bundles":[{"structural_resources":["staff:t0"],"structural_choices":["gp"]},{"structural_resources":["staff:t1"],"structural_choices":["gp"]}],"choice_groups":{"gp":[],"spectrum":[],"resonance":[]},"reception_bundles":structure[0].reception_bundles}]
	var unavailable_staff: Dictionary = {}
	for index: int in 17:
		expanded[0].choice_groups.gp.append({"structural_resources":["staff:g"+str(index),"facility:g"+str(index)],"structural_choices":["spectrum"]})
		expanded[0].choice_groups.spectrum.append({"structural_resources":["staff:b"+str(index),"facility:s"+str(index)],"structural_choices":["resonance"]})
		expanded[0].choice_groups.resonance.append({"structural_resources":["staff:b"+str(index),"facility:r"+str(index)]})
		if index>0: unavailable_staff["staff:b"+str(index)] = true
	# 17^3 different complete paths force implicit encoding. Two independent
	# terminal doctors bound K at2 and g0/b0, g1/b1 attain it. Restricting b to
	# b0 bounds K at1; using b0 twice within that path is a single resource.
	var implicit: Dictionary = PlatformArrivalMath.structure(expanded,{},reception,8)
	var implicit_blocked: Dictionary = PlatformArrivalMath.structure(expanded,unavailable_staff,reception,8)
	var implicit_valid: bool = implicit.get("pairs")==2 and implicit_blocked.get("pairs")==1 and implicit.get("structure_encoding")=="implicit" and implicit_blocked.get("structure_encoding")=="implicit" and int(implicit.get("structural_slots",0))==2
	return {"passed":c_valid and k_valid and implicit_valid,"exact_c":c_valid,"independent_k":k_valid,"capacity":first.get("capacity"),"pairs":[k.get("pairs"),blocked.get("pairs"),unavailable.get("pairs")],"failure_recovered":rejected.has("error") and retried.get("pairs")==2,"implicit_complete_paths":4913,"implicit":implicit,"implicit_blocked":implicit_blocked,"implicit_valid":implicit_valid}
