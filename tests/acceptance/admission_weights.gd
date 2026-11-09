extends RefCounted

func _diseases(candidates: Array) -> Array:
	var ids: Array = []
	for candidate: Dictionary in candidates:
		if not candidate.disease_id in ids: ids.append(candidate.disease_id)
	ids.sort()
	return ids

func run(t, content: HospitalContent, ctx: Dictionary) -> void:
	var world: WorldState = ctx.world
	var arrivals: HospitalArrivalService = ctx.arrivals
	var commands_ok: bool = true
	for disease: Dictionary in content.catalog.diseases:
		commands_ok = arrivals.execute(world,"arrivals_weight",{"disease_id":disease.id,"weight":0}).accepted and commands_ok
	for setting: Array in [["D09",1],["D37",3],["D03",2]]:
		commands_ok = arrivals.execute(world,"arrivals_weight",{"disease_id":setting[0],"weight":setting[1]}).accepted and commands_ok
	var before: Dictionary = world.freeze()
	var weights: Dictionary = {}
	var candidates: Array = arrivals._admission_candidates(world,weights)
	var readonly: bool = before==world.freeze()
	var initial: bool = _diseases(candidates)==["D09","D37"]
	var unique: bool = true
	var pairs: Dictionary = {}
	for candidate: Dictionary in candidates:
		var key: Array = [candidate.disease_id,candidate.species_id]
		unique = unique and not pairs.has(key)
		pairs[key] = true
	# Legal query-boundary inputs: completed research is added/removed before
	# each selection. Research execution itself is covered by its own cases.
	world.facts.research.append("R01")
	var unlocked: bool = _diseases(arrivals._admission_candidates(world))==["D03","D09","D37"]
	world.facts.research.erase("R01")
	var relocked: bool = _diseases(arrivals._admission_candidates(world))==["D09","D37"]
	commands_ok = arrivals.execute(world,"arrivals_weight",{"disease_id":"D09","weight":0}).accepted and commands_ok
	var stopped: bool = _diseases(arrivals._admission_candidates(world))==["D37"]
	commands_ok = arrivals.execute(world,"arrivals_weight",{"disease_id":"D09","weight":1}).accepted and commands_ok
	var restarted: bool = _diseases(arrivals._admission_candidates(world))==["D09","D37"]
	# One actual binding per disease isolates the disease draw. Weights 1:3
	# partition four equally likely integer outcomes; one-species selection and
	# ordinary variants consume no further random word.
	var selected_candidates: Array = []
	for disease_id: String in ["D37","D09"]:
		for binding: Dictionary in content.catalog.treatment_bindings:
			if binding.disease_id==disease_id:
				selected_candidates.append({"binding_id":binding.id,"disease_id":binding.disease_id,"species_id":binding.species_id,"variants":[false]})
				break
	var draws_correct: bool = selected_candidates.size()==2
	var observed: Dictionary = {"D09":0,"D37":0}
	for seed: int in range(1,33):
		var generator: RandomNumberGenerator = RandomNumberGenerator.new()
		generator.seed = seed
		var input: Dictionary = world.freeze()
		input.rng.arrival.seed_decimal = str(seed)
		input.rng.arrival.state_decimal = str(generator.state)
		var roll: int = generator.randi()%4
		var expected: String = "D09" if roll<1 else "D37"
		for shared: bool in [false,true]:
			var sample: WorldState = WorldState.new(input.duplicate(true))
			var chosen: Dictionary = arrivals._choose_case(sample,selected_candidates,weights if shared else null)
			draws_correct = draws_correct and chosen.disease_id==expected and not chosen.complex and sample.facts.rng.arrival.state_decimal==str(generator.state)
			var expected_rng: Dictionary = input.rng.duplicate(true)
			expected_rng.arrival.state_decimal = str(generator.state)
			draws_correct = draws_correct and sample.facts.rng==expected_rng
		observed[expected] += 1
	var valid: String = world.validate(content)
	t.check("GROW-86",commands_ok and initial and unique and readonly and unlocked and relocked and stopped and restarted and draws_correct and int(observed.D09)>0 and int(observed.D37)>0 and valid.is_empty(),{"initial_pool":_diseases(candidates),"one_binding_per_species_disease":unique,"readonly":readonly,"unlocked":unlocked,"relocked":relocked,"zero_weight_stopped":stopped,"weight_restarted":restarted,"weighted_draws_and_rng":draws_correct,"expected_draw_counts":observed,"validation":valid})
