class_name HospitalPersonalBedMatching
extends RefCounted

# The caller supplies staff in mandatory-sleep, awake-time, energy and ID order.
# First maximize coverage and prefer the earliest staff when beds are scarce.
# Then minimize each covered staff member's (travel_ticks, bed_id), in that order.
# All working arrays and dictionaries are private; neither input is modified.
static func solve(staff_ids: Array, candidates: Dictionary) -> Dictionary:
	var ordered: Array[String] = []
	var edges: Dictionary = {}
	for staff_value: Variant in staff_ids:
		var staff_id: String = str(staff_value)
		if edges.has(staff_id):
			continue
		var travel_by_bed: Dictionary = {}
		for candidate: Dictionary in candidates.get(staff_id,[]):
			var bed_id: String = str(candidate.bed_id)
			var travel_ticks: int = int(candidate.travel_ticks)
			if not travel_by_bed.has(bed_id) or travel_ticks<int(travel_by_bed[bed_id]):
				travel_by_bed[bed_id] = travel_ticks
		var staff_edges: Array[Dictionary] = []
		for bed_id: String in travel_by_bed:
			staff_edges.append({"bed_id":bed_id,"travel_ticks":int(travel_by_bed[bed_id])})
		staff_edges.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
			if int(first.travel_ticks)!=int(second.travel_ticks):
				return int(first.travel_ticks)<int(second.travel_ticks)
			return str(first.bed_id)<str(second.bed_id))
		ordered.append(staff_id)
		edges[staff_id] = staff_edges

	var owners: Dictionary = {}
	var covered: Array[String] = []
	for staff_id: String in ordered:
		if _augment(staff_id,edges,owners,{}):
			covered.append(staff_id)
	# Matchable staff sets form a transversal matroid: accepting a staff member
	# whenever an augmenting path exists gives a maximum-size basis, preferring
	# every earlier staff member without displacing any already accepted one.
	var fixed_beds: Dictionary = {}
	for staff_id: String in covered:
		for candidate: Dictionary in edges[staff_id]:
			var bed_id: String = str(candidate.bed_id)
			if fixed_beds.has(bed_id):
				continue
			var trial: Dictionary = _try_fix(staff_id,bed_id,edges,owners,fixed_beds)
			if not trial.is_empty():
				owners = trial
				fixed_beds[bed_id] = true
				break
	return owners

# Force one edge while preserving earlier decisions. Removing this staff's old
# edge and taking the requested bed leaves at most one other staff unmatched.
# An augmenting path therefore decides whether a complete extension exists.
static func _try_fix(staff_id: String, bed_id: String, edges: Dictionary, owners: Dictionary, fixed_beds: Dictionary) -> Dictionary:
	var trial: Dictionary = owners.duplicate()
	for owned_bed: String in owners:
		if str(owners[owned_bed])==staff_id:
			trial.erase(owned_bed)
			break
	var occupied: bool = trial.has(bed_id)
	var displaced: String = str(trial.get(bed_id,""))
	trial[bed_id] = staff_id
	if not occupied:
		return trial
	var blocked: Dictionary = fixed_beds.duplicate()
	blocked[bed_id] = true
	if _augment(displaced,edges,trial,blocked):
		return trial
	return {}

# Iterative breadth-first augmentation avoids a recursion-depth limit. An
# unsuccessful search does not alter owners; a successful one changes only
# the discovered alternating path. Blocked beds encode fixed ownership edges.
# For S staff and E distinct compatibility edges, all coverage searches cost
# O(S*(E+1)); at most E constrained searches/copies cost O(E*(E+S+1)). Sorting costs
# O(E*log(E+1)); working memory is O(S+E). No staff/bed/edge count is truncated.
static func _augment(staff_id: String, edges: Dictionary, owners: Dictionary, blocked: Dictionary) -> bool:
	var queue: Array[String] = [staff_id]
	var seen_staff: Dictionary = {staff_id:true}
	var parent_staff: Dictionary = {}
	var incoming_bed: Dictionary = {}
	var head: int = 0
	var found: bool = false
	var free_bed: String = ""
	while head<queue.size() and not found:
		var current: String = queue[head]
		head += 1
		for candidate: Dictionary in edges[current]:
			var bed_id: String = str(candidate.bed_id)
			if blocked.has(bed_id) or parent_staff.has(bed_id):
				continue
			parent_staff[bed_id] = current
			if not owners.has(bed_id):
				free_bed = bed_id
				found = true
				break
			var occupant: String = str(owners[bed_id])
			if not seen_staff.has(occupant):
				seen_staff[occupant] = true
				incoming_bed[occupant] = bed_id
				queue.append(occupant)
	if not found:
		return false
	while true:
		var next_staff: String = str(parent_staff[free_bed])
		owners[free_bed] = next_staff
		if next_staff==staff_id:
			return true
		free_bed = str(incoming_bed[next_staff])
	return false
