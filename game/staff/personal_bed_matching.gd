class_name HospitalPersonalBedMatching
extends RefCounted

# The hospital supplies ordered compatible candidates. Boost.Graph owns maximum
# matching; the native adapter retains coverage priority and exact tie rules.
static func solve(staff_ids: Array, candidates: Dictionary) -> Dictionary:
	return compute(staff_ids,candidates).owners

static func compute(staff_ids: Array, candidates: Dictionary) -> Dictionary:
	var result: Dictionary = PlatformArrivalMath.personal_bed_matching(staff_ids,candidates)
	if not result.get("ok",false):
		return {"ok":false,"owners":{},"error":str(result.error)}
	return {"ok":true,"owners":result.owners}
