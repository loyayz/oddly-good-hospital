extends RefCounted

# Small, explicit answers from the personal-bed allocation contract. These
# cases deliberately include a lexicographic optimum with a worse total time;
# a second optimizer must not define the expected result.
func run() -> Dictionary:
	var valid: Array[Dictionary] = [
		{"name":"bed_identity_is_not_result_metadata","staff":["A"],"candidates":{"A":[{"bed_id":"error","travel_ticks":1}]},"expected":{"error":"A"}},
		{"name":"maximum_coverage_before_first_staff_cheapest","staff":["A","B"],"candidates":{
			"A":[{"bed_id":"shared","travel_ticks":1},{"bed_id":"spare","travel_ticks":99}],
			"B":[{"bed_id":"shared","travel_ticks":2}]},"expected":{"spare":"A","shared":"B"}},
		{"name":"scarce_bed_preserves_staff_priority","staff":["first","second","third"],"candidates":{
			"first":[{"bed_id":"bed","travel_ticks":100}],
			"second":[{"bed_id":"bed","travel_ticks":0}],
			"third":[{"bed_id":"bed","travel_ticks":1}]},"expected":{"bed":"first"}},
		{"name":"priority_set_with_independent_later_staff","staff":["A","B","C"],"candidates":{
			"A":[{"bed_id":"shared","travel_ticks":100}],
			"B":[{"bed_id":"shared","travel_ticks":0}],
			"C":[{"bed_id":"separate","travel_ticks":3}]},"expected":{"shared":"A","separate":"C"}},
		{"name":"per_staff_time_precedes_total_time","staff":["A","B"],"candidates":{
			"A":[{"bed_id":"bed_a","travel_ticks":1},{"bed_id":"bed_z","travel_ticks":2}],
			"B":[{"bed_id":"bed_a","travel_ticks":0},{"bed_id":"bed_z","travel_ticks":100}]},"expected":{"bed_a":"A","bed_z":"B"}},
		{"name":"time_precedes_bed_identity","staff":["A"],"candidates":{
			"A":[{"bed_id":"bed_a","travel_ticks":3},{"bed_id":"bed_z","travel_ticks":2}]},"expected":{"bed_z":"A"}},
		{"name":"bed_identity_breaks_equal_time","staff":["z_priority","a_second"],"candidates":{
			"z_priority":[{"bed_id":"bed_z","travel_ticks":1},{"bed_id":"bed_a","travel_ticks":1}],
			"a_second":[{"bed_id":"bed_z","travel_ticks":1},{"bed_id":"bed_a","travel_ticks":1}]},"expected":{"bed_a":"z_priority","bed_z":"a_second"}},
		{"name":"later_staff_tie_after_first_choice_fixed","staff":["A","B","C"],"candidates":{
			"A":[{"bed_id":"bed_a","travel_ticks":0}],
			"B":[{"bed_id":"bed_c","travel_ticks":7},{"bed_id":"bed_b","travel_ticks":7}],
			"C":[{"bed_id":"bed_c","travel_ticks":8},{"bed_id":"bed_b","travel_ticks":8}]},"expected":{"bed_a":"A","bed_b":"B","bed_c":"C"}},
		{"name":"duplicate_bed_keeps_shortest_last","staff":["A"],"candidates":{
			"A":[{"bed_id":"bed_a","travel_ticks":10},{"bed_id":"bed_b","travel_ticks":5},{"bed_id":"bed_a","travel_ticks":2}]},"expected":{"bed_a":"A"}},
		{"name":"duplicate_bed_keeps_shortest_first","staff":["A"],"candidates":{
			"A":[{"bed_id":"bed_a","travel_ticks":2},{"bed_id":"bed_b","travel_ticks":5},{"bed_id":"bed_a","travel_ticks":10}]},"expected":{"bed_a":"A"}},
		{"name":"empty_staff","staff":[],"candidates":{},"expected":{}},
		{"name":"missing_candidate_list","staff":["A"],"candidates":{},"expected":{}},
		{"name":"incompatible_staff","staff":["A","B"],"candidates":{"A":[],"B":[]},"expected":{}},
		{"name":"incompatible_first_does_not_block_later","staff":["A","B"],"candidates":{
			"A":[],"B":[{"bed_id":"bed_b","travel_ticks":0}]},"expected":{"bed_b":"B"}},
		{"name":"unrequested_staff_cannot_create_owner","staff":["A"],"candidates":{
			"A":[],"unrequested":[{"bed_id":"ghost","travel_ticks":0}]},"expected":{}},
		{"name":"integer_above_binary64_exact_range","staff":["A"],"candidates":{
			"A":[{"bed_id":"bed_a","travel_ticks":9007199254740993},{"bed_id":"bed_z","travel_ticks":9007199254740992}]},"expected":{"bed_z":"A"}},
		{"name":"maximum_int64_remains_legal","staff":["A","B"],"candidates":{
			"A":[{"bed_id":"bed_a","travel_ticks":9223372036854775807},{"bed_id":"bed_z","travel_ticks":9223372036854775806}],
			"B":[{"bed_id":"bed_a","travel_ticks":9223372036854775807}]},"expected":{"bed_z":"A","bed_a":"B"}},
		{"name":"maximum_int64_tie_without_sum_overflow","staff":["A","B"],"candidates":{
			"A":[{"bed_id":"bed_z","travel_ticks":9223372036854775807},{"bed_id":"bed_a","travel_ticks":9223372036854775807}],
			"B":[{"bed_id":"bed_z","travel_ticks":9223372036854775807},{"bed_id":"bed_a","travel_ticks":9223372036854775807}]},"expected":{"bed_a":"A","bed_z":"B"}}
	]
	var invalid: Array[Dictionary] = [
		{"name":"invalid_staff_type","staff":["A",1],"candidates":{"A":[{"bed_id":"real","travel_ticks":0}]}},
		{"name":"empty_staff_identity","staff":[""],"candidates":{"":[]}},
		{"name":"candidate_list_is_not_array","staff":["A","B"],"candidates":{"A":[{"bed_id":"real","travel_ticks":0}],"B":{}}},
		{"name":"candidate_is_not_dictionary","staff":["A"],"candidates":{"A":["bed"]}},
		{"name":"bed_identity_is_not_string","staff":["A"],"candidates":{"A":[{"bed_id":7,"travel_ticks":0}]}},
		{"name":"empty_bed_identity","staff":["A"],"candidates":{"A":[{"bed_id":"","travel_ticks":0}]}},
		{"name":"missing_bed_identity","staff":["A"],"candidates":{"A":[{"travel_ticks":0}]}},
		{"name":"missing_travel_ticks","staff":["A"],"candidates":{"A":[{"bed_id":"bed"}]}},
		{"name":"float_ticks_are_not_integer_ticks","staff":["A","B"],"candidates":{"A":[{"bed_id":"real","travel_ticks":0}],"B":[{"bed_id":"bad","travel_ticks":1.5}]}},
		{"name":"string_ticks_are_not_integer_ticks","staff":["A"],"candidates":{"A":[{"bed_id":"bed","travel_ticks":"1"}]}},
		{"name":"negative_travel_ticks","staff":["A","B"],"candidates":{"A":[{"bed_id":"real","travel_ticks":0}],"B":[{"bed_id":"bad","travel_ticks":-1}]}},
		{"name":"minimum_int64_is_not_legal_travel_time","staff":["A"],"candidates":{"A":[{"bed_id":"bed","travel_ticks":-9223372036854775807-1}]}}
	]
	var checks: Dictionary = {}
	var failures: Dictionary = {}
	var unchanged: bool = true
	for sample: Dictionary in valid:
		var before_staff: Array = sample.staff.duplicate(true)
		var before_candidates: Dictionary = sample.candidates.duplicate(true)
		var result: Dictionary = HospitalPersonalBedMatching.compute(sample.staff,sample.candidates)
		var passed: bool = result.get("ok",false) and result.get("owners",{})==sample.expected
		checks[sample.name] = passed
		unchanged = unchanged and sample.staff==before_staff and sample.candidates==before_candidates
		if not passed:
			failures[sample.name] = {"expected":sample.expected,"actual":result}
	for sample: Dictionary in invalid:
		var before_staff: Array = sample.staff.duplicate(true)
		var before_candidates: Dictionary = sample.candidates.duplicate(true)
		var result: Dictionary = HospitalPersonalBedMatching.compute(sample.staff,sample.candidates)
		var passed: bool = result.get("ok",true)==false and result.get("owners",null) is Dictionary and result.owners.is_empty() and not str(result.get("error","")).is_empty()
		checks[sample.name] = passed
		unchanged = unchanged and sample.staff==before_staff and sample.candidates==before_candidates
		if not passed:
			failures[sample.name] = {"expected":{"ok":false,"owners":{}},"actual":result}
	checks.input_unchanged = unchanged
	var ok: bool = true
	for name: String in checks:
		ok = ok and checks[name]
	return {"ok":ok,"checks":checks,"failures":failures,"legal_cases":valid.size(),"invalid_cases":invalid.size(),"literal_expectations":true}
