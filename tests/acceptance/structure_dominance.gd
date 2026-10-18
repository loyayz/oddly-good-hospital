extends RefCounted

const F = preload("res://game/arrivals/exact_fraction.gd")

func run_case(t, _database: HospitalContent) -> void:
	var reception: Dictionary = {"people":{"staff:r":true},"desks":{"facility:d":true},"ratio":3}
	var simple: Array = []
	for terminal: String in ["t0","t1"]:
		for complex_path: bool in [false,true]: simple.append(_case(terminal,[0,1],complex_path))
	var complete: Dictionary = _solve(simple,reception)
	var partial: Array = []
	for terminal: String in ["t0","t1"]:
		partial.append(_case(terminal,[0],false))
		partial.append(_case(terminal,[0,1],true))
	# GP g1 is absent from the cheaper case. Retaining the complex branch is
	# necessary for two disjoint groups; matching one OR branch is insufficient.
	var partial_result: Dictionary = _solve(partial,reception)
	var wards: Array = [_case("t0",[0],false,"n0","w0"),_case("t0",[0],true,"n0","w1"),_case("t1",[1],false,"n0","w1")]
	var ward_result: Dictionary = _solve(wards,reception)
	var nurses: Array = [_case("t0",[0],false,"n0","w0"),_case("t0",[0],true,"n1","w0"),_case("t1",[1],false)]
	nurses[2].bundles[0].structural_resources.append("staff:n0")
	var nurse_result: Dictionary = _solve(nurses,reception)
	# Equal languages with distinct wrappers must keep one representative.
	var equivalent: Array = [_case("t0",[0],false),_case("t0",[0],false)]
	equivalent[1].choice_groups.wrapper = [{"structural_resources":[],"structural_choices":["gp"]}]
	equivalent[1].bundles[0].structural_choices = ["wrapper"]
	var same: Dictionary = _solve(equivalent,reception)
	equivalent.reverse()
	var reversed: Dictionary = _solve(equivalent,reception)
	# K does not count an empty complete resource set. It cannot witness the
	# removal of the two nonempty GP alternatives of this empty terminal.
	var empty: Dictionary = _case("",[],false)
	empty.choice_groups.gp = [{"structural_resources":[]}]
	var nonempty: Dictionary = _solve([empty,_case("",[0,1],false)],reception)
	var invalid: Array = simple.duplicate(true)
	invalid[0].bundles[0].structural_choices = ["missing"]
	var rejected: Dictionary = _solve(invalid,reception)
	var recovered: Dictionary = _solve(simple,reception)
	var four: Array = []
	for index: int in 4: four.append(_case("a"+str(index),[index],false))
	var certificate: Dictionary = _solve(four,{"people":{"staff:r":true},"desks":{"facility:d":true},"ratio":6})
	# Greedy first chooses {a,b}, which blocks both members of the optimal
	# {a,c}+{b,d} packing. The bound stays two and the full MILP must recover it.
	var trap: Dictionary = _solve([_fixed(["staff:a","staff:b"]),_fixed(["staff:a","staff:c"]),_fixed(["staff:b","staff:d"])],reception)
	var repeated: Dictionary = _fixed(["staff:a"])
	repeated.bundles[0].structural_choices = ["same"]
	repeated.choice_groups = {"same":[{"structural_resources":["staff:a"]}]}
	var same_doctor: Dictionary = _solve([repeated],reception)
	# A conservative joint witness cannot reuse its clinical person as the
	# receptionist. Failure to certify retains the original separate-R API.
	var reception_overlap: Dictionary = _solve([_fixed(["staff:r"])],reception)
	var diluted: Array = []
	for index: int in 4:
		for extra: bool in [false,true]:
			var case: Dictionary = _fixed(["staff:d"+str(index)])
			case.bundles[0].structural_choices = ["gp"]
			case.choice_groups = {"gp":[]}
			for other: int in 4:
				if other==index: continue
				var option: Dictionary = {"structural_resources":["staff:d"+str(other)]}
				if extra: option.structural_choices = ["extra"]
				case.choice_groups.gp.append(option)
			if extra:
				case.choice_groups.extra = []
				for nurse: int in 4: case.choice_groups.extra.append({"structural_resources":["staff:n"+str(nurse)]})
			diluted.append(case)
	var subset_bound: Dictionary = _solve(diluted,reception)
	var valid: bool = complete.get("pairs")==2 and complete.get("structure_encoding")=="implicit" and int(complete.get("structural_dominated_alternatives",0))>=2 and int(complete.get("structural_nodes",0))<int(complete.get("structural_interned_nodes",0))
	valid = valid and partial_result.get("pairs")==2 and ward_result.get("pairs")==2 and nurse_result.get("pairs")==2
	valid = valid and same.get("pairs")==1 and reversed.get("pairs")==1 and int(same.get("structural_alternatives_after",0))>=1 and int(same.get("structural_dominated_alternatives",0))>=1
	valid = valid and nonempty.get("pairs")==2 and rejected.has("error") and recovered.get("pairs")==2
	valid = valid and certificate.get("pairs")==4 and certificate.get("structural_certificate_status")=="optimal" and certificate.get("structural_staff_minimum")==2 and certificate.get("structural_variables")==0 and int(certificate.get("structural_slots",0))<int(certificate.get("structural_original_slots",0))
	valid = valid and trap.get("pairs")==2 and trap.get("structural_certificate_status")=="fallback" and trap.get("structural_certificate_upper")==2 and trap.get("structural_slots")==2 and int(trap.get("structural_variables",0))>0
	valid = valid and same_doctor.get("pairs")==1 and same_doctor.get("structural_staff_minimum")==1 and reception_overlap.get("pairs")==1 and reception_overlap.get("structural_certificate_status")=="fallback" and reception_overlap.get("structural_certificate_lower")==0
	valid = valid and subset_bound.get("pairs")==2 and subset_bound.get("structural_certificate_status")=="optimal" and subset_bound.get("structural_staff_resources")==9 and subset_bound.get("structural_staff_minimum")==2 and subset_bound.get("structural_bound_resources")==4 and subset_bound.get("structural_bound_minimum")==2 and subset_bound.get("structural_bound_upper")==2
	t.check("GROW-82",valid,{"complete":complete,"partial_OR":partial_result,"wards":ward_result,"nurses":nurse_result,"equal_languages":same,"reversed":reversed,"nonempty":nonempty,"rejected":rejected,"recovered":recovered,"certificate":certificate,"greedy_trap":trap,"same_doctor":same_doctor,"reception_overlap":reception_overlap,"subset_bound":subset_bound})

func _fixed(resources: Array) -> Dictionary:
	return {"bundles":[{"structural_resources":resources}],"reception_bundles":[{"resources":{"staff:r":F.make(1),"facility:d":F.make(1)}}]}

func _case(terminal: String, gp: Array, complex_path: bool, nurse: String = "", ward: String = "") -> Dictionary:
	var root: Dictionary = {"structural_resources":["staff:"+terminal] if not terminal.is_empty() else [],"structural_choices":["gp"]}
	if not nurse.is_empty(): root.merge({"coverage_nurse_id":nurse,"ward_id":ward})
	var result: Dictionary = {"bundles":[root],"choice_groups":{"gp":[]},"reception_bundles":[{"resources":{"staff:r":F.make(1),"facility:d":F.make(1)}}]}
	for index: int in gp:
		var part: Dictionary = {"structural_resources":["staff:g"+str(index),"facility:g"+str(index)]}
		if complex_path: part.structural_choices = ["test"]
		result.choice_groups.gp.append(part)
	if complex_path: result.choice_groups.test = [{"structural_resources":["facility:s0"]},{"structural_resources":["facility:s1"]}]
	return result

func _solve(cases: Array, reception: Dictionary) -> Dictionary:
	# All 17^3 paths remain input. The unavailable root forces the implicit
	# encoding while contributing no group to the independently hand-counted K.
	var trigger: Dictionary = {"bundles":[{"structural_resources":["staff:disabled"],"structural_choices":["trigger0"]}],"choice_groups":{"trigger0":[],"trigger1":[],"trigger2":[]},"reception_bundles":[]}
	for stage: int in 3:
		for option: int in 17:
			var part: Dictionary = {"structural_resources":["facility:trigger%d_%d"%[stage,option]]}
			if stage<2: part.structural_choices = ["trigger"+str(stage+1)]
			trigger.choice_groups["trigger"+str(stage)].append(part)
	return PlatformArrivalMath.structure([trigger]+cases,{"staff:disabled":true},reception,8)
