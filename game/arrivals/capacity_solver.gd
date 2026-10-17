class_name ArrivalCapacitySolver
extends RefCounted

# The native backend batches exact LP solving, all implicit-choice pricing and
# primal/dual checks. No hospital facts or random streams are modified here.
static func solve(cases: Array, budgets: Dictionary) -> Dictionary:
	return PlatformArrivalMath.solve(cases,budgets)
