extends SceneTree

const Solver = preload("res://game/arrivals/capacity_solver.gd")
const F = preload("res://game/arrivals/exact_fraction.gd")

func _initialize() -> void:
	var vectors: Array = JSON.parse_string(FileAccess.get_file_as_string("res://solver-vectors.json"))
	var failures: Array = []
	var cpu_started: Dictionary = PlatformArrivalMath.thread_cpu()
	var roles: Array = JSON.parse_string(FileAccess.get_file_as_string("res://role-vectors.json"))
	for vector: Dictionary in roles:
		var backend: RefCounted = ClassDB.instantiate("PlatformArrivalCapacity")
		var result: Dictionary = backend.call("prepare",vector.cases,vector.budgets)
		if not _valid_solution(vector.cases,vector.budgets,vector.expected,result): failures.append({"role_index":vector.index,"phase":"prepare","expected":vector.expected,"actual":result})
		result = backend.call("solve",vector.changed_budgets)
		if not _valid_solution(vector.cases,vector.changed_budgets,vector.changed_expected,result): failures.append({"role_index":vector.index,"phase":"changed","expected":vector.changed_expected,"actual":result})
		result = backend.call("solve",vector.budgets)
		if not _valid_solution(vector.cases,vector.budgets,vector.expected,result): failures.append({"role_index":vector.index,"phase":"restored","expected":vector.expected,"actual":result})
		result = backend.call("solve",vector.redistributed_budgets)
		if not _valid_solution(vector.cases,vector.redistributed_budgets,vector.redistributed_expected,result): failures.append({"role_index":vector.index,"phase":"same_total","actual":result})
		result = backend.call("solve",vector.grown_budgets)
		var cold: RefCounted = ClassDB.instantiate("PlatformArrivalCapacity")
		var rebuilt: Dictionary = cold.call("prepare",vector.cases,vector.grown_budgets)
		if not _valid_solution(vector.cases,vector.grown_budgets,vector.grown_expected,result) or result.get("capacity")!=rebuilt.get("capacity"): failures.append({"role_index":vector.index,"phase":"growth","actual":result,"cold":rebuilt})
	var recovery: RefCounted = ClassDB.instantiate("PlatformArrivalCapacity")
	var prepared: Dictionary = recovery.call("prepare",roles[0].cases,roles[0].budgets)
	var invalid: Array = roles[0].cases.duplicate(true)
	invalid[0].bundles[0].choices = ["missing_group"]
	var rejected: Dictionary = recovery.call("prepare",invalid,roles[0].budgets)
	var unavailable: Dictionary = recovery.call("solve",roles[0].budgets)
	var retried: Dictionary = recovery.call("prepare",roles[0].cases,roles[0].budgets)
	if not _valid_solution(roles[0].cases,roles[0].budgets,roles[0].expected,prepared) or not rejected.has("error") or not unavailable.has("error") or not _valid_solution(roles[0].cases,roles[0].budgets,roles[0].expected,retried): failures.append({"model_recovery":retried,"prepared":prepared,"rejected":rejected,"unavailable":unavailable})
	var invalid_budgets: Dictionary = roles[0].budgets.duplicate(true)
	invalid_budgets[invalid_budgets.keys()[0]] = F.make(-1)
	var rejected_update: Dictionary = recovery.call("solve",invalid_budgets)
	var unavailable_update: Dictionary = recovery.call("solve",roles[0].budgets)
	var retried_update: Dictionary = recovery.call("prepare",roles[0].cases,roles[0].budgets)
	if not rejected_update.has("error") or not unavailable_update.has("error") or not _valid_solution(roles[0].cases,roles[0].budgets,roles[0].expected,retried_update): failures.append({"update_recovery":retried_update,"rejected":rejected_update,"unavailable":unavailable_update})
	var structure_vectors: Array = JSON.parse_string(FileAccess.get_file_as_string("res://structure-vectors.json"))
	for vector: Dictionary in structure_vectors:
		var actual: Dictionary = PlatformArrivalMath.structure(vector.cases,vector.blocked,vector.reception,int(vector.bed_limit))
		if actual.has("error") or int(actual.get("pairs",-1))!=int(vector.expected): failures.append({"structure_index":vector.index,"expected":vector.expected,"actual":actual})
	var integers: Array = JSON.parse_string(FileAccess.get_file_as_string("res://integer-vectors.json"))
	for vector: Dictionary in integers:
		var valid: bool = F.add_integer(vector.a,vector.b)==vector.sum and F.add_integer(vector.a,"-"+str(vector.b))==vector.difference and F.multiply_integer(vector.a,vector.b)==vector.product and F.divmod(vector.a,vector.b)==[vector.quotient,vector.remainder] and F.gcd(vector.a,vector.b)==vector.gcd
		if not valid: failures.append({"integer":vector})
	var arithmetic: Array = JSON.parse_string(FileAccess.get_file_as_string("res://fraction-vectors.json"))
	for vector: Dictionary in arithmetic:
		var valid: bool = F.make(vector.uncanonical.n,vector.uncanonical.d)==vector.a and F.add(vector.a,vector.b)==vector.add and F.sub(vector.a,vector.b)==vector.sub and F.mul(vector.a,vector.b)==vector.mul and F.div(vector.a,vector.b)==vector.div and F.compare(vector.a,vector.b)==int(vector.compare)
		var aggregated: Dictionary = PlatformArrivalMath.aggregate_stages({"first":{"a":vector.a,"b":vector.b},"second":{"a":vector.b}},vector.b)
		valid = valid and aggregated==vector.aggregate
		if not valid: failures.append({"arithmetic":vector})
	for vector: Dictionary in vectors:
		var result: Dictionary = Solver.solve(vector.cases,vector.budgets)
		if not _valid_solution(vector.cases,vector.budgets,vector.expected,result): failures.append({"index":vector.index,"phase":"cold","actual":result})
		var irrelevant: Dictionary = vector.budgets.duplicate(true)
		irrelevant["coverage:unused_nurse:unused_ward"] = F.make()
		var unchanged_model: RefCounted = ClassDB.instantiate("PlatformArrivalCapacity")
		var unchanged: Dictionary = unchanged_model.call("prepare",vector.cases,irrelevant)
		if not _valid_solution(vector.cases,irrelevant,vector.expected,unchanged) or unchanged.get("solver_kind","")!="lp" or unchanged.get("bottleneck","")=="coverage:unused_nurse:unused_ward": failures.append({"index":vector.index,"phase":"unused_coverage","actual":unchanged})
		irrelevant["coverage:unused_nurse:unused_ward"] = F.make(98765)
		var reused: Dictionary = unchanged_model.call("solve",irrelevant)
		if not _valid_solution(vector.cases,irrelevant,vector.expected,reused) or reused.get("resolution_count")!=unchanged.get("resolution_count"): failures.append({"index":vector.index,"phase":"unused_update","actual":reused})
		var backend: RefCounted = ClassDB.instantiate("PlatformArrivalCapacity")
		result = backend.call("prepare",vector.cases,vector.budgets)
		if not _valid_solution(vector.cases,vector.budgets,vector.expected,result): failures.append({"index":vector.index,"phase":"prepare","actual":result})
		result = backend.call("solve",vector.changed_budgets)
		if not _valid_solution(vector.cases,vector.changed_budgets,vector.changed_expected,result): failures.append({"index":vector.index,"phase":"changed","actual":result})
		result = backend.call("solve",vector.budgets)
		if not _valid_solution(vector.cases,vector.budgets,vector.expected,result): failures.append({"index":vector.index,"phase":"restored","actual":result})
	var cpu_finished: Dictionary = PlatformArrivalMath.thread_cpu()
	if not cpu_started.has("cpu_us") or not cpu_finished.has("cpu_us") or int(cpu_finished.cpu_us)<int(cpu_started.cpu_us): failures.append({"thread_cpu":"CPU 时间不可用或不单调"})
	var report: Dictionary = {"checks":vectors.size(),"warm_checks":vectors.size()*3,"arithmetic_checks":arithmetic.size(),"integer_checks":integers.size(),"structure_checks":structure_vectors.size(),"failures":failures,"solver_sha256":FileAccess.get_sha256("res://game/arrivals/capacity_solver.gd"),"fractions_sha256":FileAccess.get_sha256("res://game/arrivals/exact_fraction.gd"),"vectors_sha256":FileAccess.get_sha256("res://solver-vectors.json"),"native_sha256":FileAccess.get_sha256("res://game/platform/windows/bin/oddly_good_platform.windows.x86_64.dll"),"gmp_sha256":FileAccess.get_sha256("res://game/platform/windows/bin/libgmp-10.dll"),"mpfr_sha256":FileAccess.get_sha256("res://game/platform/windows/bin/libmpfr-6.dll")}
	report.role_checks = roles.size()*6
	report.recovery_checks = 7
	report.unused_resource_checks = vectors.size()*2
	report.aggregate_checks = arithmetic.size()
	var file: FileAccess = FileAccess.open("res://solver-check.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("EXACT_VERTEX_CHECK="+JSON.stringify({"checks":vectors.size(),"failed":failures.size()}))
	quit(0 if failures.is_empty() else 1)

func _valid_solution(cases: Array, budgets: Dictionary, expected: Dictionary, result: Dictionary) -> bool:
	if result.has("error") or result.get("capacity",{})!=expected: return false
	# Persistent models expose the capacity projection only. Their native
	# primal/dual checks still run after every actual budget change.
	if not result.has("assignments"): return true
	var amounts: Array = []
	var used: Dictionary = {}
	for case: Dictionary in cases: amounts.append(F.make())
	for assignment: Dictionary in result.assignments:
		if F.compare(assignment.amount,F.make())<0: return false
		amounts[assignment.case_index] = F.add(amounts[assignment.case_index],assignment.amount)
		for resource: String in assignment.resources:
			used[resource] = F.add(used.get(resource,F.make()),F.mul(assignment.amount,assignment.resources[resource]))
	for index: int in cases.size():
		if amounts[index]!=F.mul(result.capacity,cases[index].probability): return false
	for resource: String in budgets:
		if F.compare(used.get(resource,F.make()),budgets[resource])>0: return false
	return true
