extends RefCounted

# Finite observation inputs at the real standing and seated boundaries of STAFF-69.
# These calculations do not replace travel, seat acquisition or elapsed work.
func run(world: WorldState, visit: Dictionary, departments: HospitalExperience, standing: bool) -> Dictionary:
	var before: Dictionary = world.freeze()
	var rows: Array = []
	var ok: bool = true
	var samples: Array = [
		{"observation":{"clean":true,"noise":0.0},"causes":[]},
		{"observation":{"clean":false,"noise":0.0},"causes":["dirty"]},
		{"observation":{"clean":true,"noise":1.0},"causes":["construction_noise"]},
		{"observation":{"clean":false,"noise":1.0},"causes":["dirty","construction_noise"]},
	]
	var histories: Array = [{},{"no_compatible_seat":17,"dirty":29,"construction_noise":43},{"legacy_cause":9},{"dirty":29,"legacy_cause":9}]
	for sample: Dictionary in samples:
		var causes: Array = sample.causes.duplicate()
		if standing: causes.push_front("no_compatible_seat")
		for history: Dictionary in histories:
			var expected: Dictionary = {}
			for cause: String in causes: expected[cause] = history.get(cause,world.sim_tick)
			var data: Dictionary = {"cause_clocks":history.duplicate(true)}
			departments._update_cause_clocks(world,visit,data,sample.observation)
			var first: bool = data.cause_clocks==expected
			departments._update_cause_clocks(world,visit,data,sample.observation)
			var repeated: bool = data.cause_clocks==expected
			ok = ok and first and repeated
			rows.append({"standing":standing,"observation":sample.observation,"history":history,"expected":expected,"actual":data.cause_clocks.duplicate(true),"first":first,"repeated":repeated})
	var readonly: bool = world.freeze()==before
	return {"ok":ok and readonly,"rows":rows,"world_readonly":readonly}
