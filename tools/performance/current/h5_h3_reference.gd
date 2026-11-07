extends HospitalMovement
func _detour_return_path(world: WorldState, actor: Dictionary, movement: Dictionary, origin: Vector2, prefix: Array = []) -> Dictionary:
	# Candidate links read one unchanged actor, geometry, reservations and
	# accepted sweeps. Exact single-body proofs live only in this synchronous
	# search; the next attempt rebuilds. Convoys retain their full trail proof.
	var proof: Dictionary = {"sweeps":{},"segments":{},"_capture_entry":true} if not movement.has("convoy") else {}
	var query: RouteClearance = null
	for index: int in movement.detour.original_path.size():
		var segment: Dictionary = movement.detour.original_path[index]
		if segment.kind!="floor" or int(segment.floor_id)!=int(actor.location.floor_id): break
		if query==null:
			var proxy: Dictionary = ConvoyTrail.proxy(world,movement) if movement.has("convoy") else actor
			query = space.navigation.structural_clearance(world,proxy,int(actor.location.floor_id))
		var target: Vector2 = ConvoyTrail.point(segment.cell)
		# Try the original blocked cell first, then its original successors.
		# Check fixed orthogonal local links, never a global route.
		var links: Array = [[Vector2(target.x,origin.y),target],[Vector2(origin.x,target.y),target]]
		# Four fixed outside links handle a nearby corner/passing pocket.
		# A queue's margin also clears its own tail before returning.
		var margin: float = float(movement.convoy.spacing) if movement.has("convoy") else float(space.clearance(actor))
		var outside_x: Array = [maxf(origin.x,target.x)+margin,minf(origin.x,target.x)-margin]
		var outside_y: Array = [maxf(origin.y,target.y)+margin,minf(origin.y,target.y)-margin]
		for x: float in outside_x: links.append([Vector2(x,origin.y),Vector2(x,target.y),target])
		for y: float in outside_y: links.append([Vector2(origin.x,y),Vector2(target.x,y),target])
		# A pocket beside furniture may need one outside bend on each axis
		# to reach the side of a doorway. Try these fixed links for this
		# original cell before considering a farther one; never redispatch.
		for x: float in outside_x:
			for y: float in outside_y:
				links.append([Vector2(x,origin.y),Vector2(x,y),Vector2(target.x,y),target])
				links.append([Vector2(origin.x,y),Vector2(x,y),Vector2(x,target.y),target])
		for link: Array in links:
			if _detour_first_segment_failed(world,actor,origin,prefix,link,segment,proof): continue
			var path: Array = prefix.duplicate(true)
			var previous: Vector2 = origin
			for point: Vector2 in link:
				if previous.distance_to(point)>0.001: path.append(_floor_point(actor,point))
				previous = point
			if path.is_empty(): path.append(segment.duplicate(true))
			if _detour_path_clear(world,actor,movement,path,query,proof): return {"path":path,"index":index}
	return {}

# Only the return-search owner can capture this exact entry state. A known
# first-segment failure can reject this candidate before building its path;
# unknown/positive/capped-out proofs still execute the complete predicate.
func _detour_first_segment_failed(world: WorldState, actor: Dictionary, link_origin: Vector2, prefix: Array, link: Array, fallback: Dictionary, proof: Dictionary) -> bool:
	if not proof.has("_entry"): return false
	var first: Vector2
	if not prefix.is_empty():
		first = ConvoyTrail.point(prefix[0].cell)
	else:
		var previous: Vector2 = link_origin
		var found: bool = false
		for point: Vector2 in link:
			if previous.distance_to(point)>0.001:
				first = point
				found = true
				break
			# The original builder advances even when this point is not appended.
			previous = point
		if not found: first = ConvoyTrail.point(fallback.cell)
	var entry: Dictionary = proof._entry
	var origin: Vector2 = entry.origin
	if absf(first.x-origin.x)>0.001 and absf(first.y-origin.y)>0.001: return false
	if origin.distance_to(first)<=0.001: return false
	var key: Array = [origin,first,entry.rect]
	if not proof.segments.has(key) or not proof.segments[key].is_empty(): return false
	# A first-segment negative memo returns before any trial-facing change.
	# Keep its original index/shape side effects, using the same actor fields
	# as the fresh sample. A surprising rectangle change takes full fallback.
	space._ensure_actor_index(world)
	return space._actor_rect(actor,origin)==entry.rect

func _floor_point(actor: Dictionary, point: Vector2) -> Dictionary:
	return {"kind":"floor","floor_id":int(actor.location.floor_id),"cell":[point.x,point.y]}

# Read-only local proof. A convoy has one fixed leader proxy; its members only
# inherit the proven trail. No follower gets an independent passage query.
func _detour_path_clear(world: WorldState, actor: Dictionary, movement: Dictionary, path: Array, query: RouteClearance = null, proof: Dictionary = {}) -> bool:
	space._ensure_actor_index(world)
	var floor_id: int = int(actor.location.floor_id)
	var proxy: Dictionary = ConvoyTrail.proxy(world,movement) if movement.has("convoy") else actor
	if query==null: query = space.navigation.structural_clearance(world,proxy,floor_id)
	var trial: Dictionary = movement.convoy.duplicate(true) if movement.has("convoy") else {}
	var shift: Vector2 = Vector2.ONE*float(trial.shift) if not trial.is_empty() else Vector2.ZERO
	var origin: Vector2 = ConvoyTrail.point(actor.location.cell)
	var sample: Dictionary = actor.duplicate(true)
	var previous: Rect2 = space._actor_rect(sample,origin) if trial.is_empty() else Rect2(origin+shift,Vector2.ONE*int(trial.size))
	if proof.get("_capture_entry",false) and not proof.has("_entry"):
		proof._entry = {"origin":origin,"rect":previous}
	var members: Array = movement.get("members",[actor.id])
	for segment: Dictionary in path:
		var target: Vector2 = ConvoyTrail.point(segment.cell)
		if absf(target.x-origin.x)>0.001 and absf(target.y-origin.y)>0.001: return false
		var segment_key: Array = []
		var remember_segment: bool = false
		if proof.has("segments") and origin.distance_to(target)>0.001:
			segment_key = [origin,target,previous]
			if proof.segments.has(segment_key):
				var proven: Array = proof.segments[segment_key]
				if proven.is_empty(): return false
				# The quarter loop can stop within tolerance, short of target.
				origin = proven[0]
				previous = proven[1]
				continue
			# This map has the same single-call lifetime as the sweep proofs.
			# Its cap limits storage only; every uncached leg still runs below.
			remember_segment = proof.segments.size()<4096
			if remember_segment: proof.segments[segment_key] = []
		while origin.distance_to(target)>0.001:
			var next: Vector2 = origin.move_toward(target,0.25)
			var proof_key: Array = []
			var next_rect: Rect2
			var remember: bool = false
			if not proof.is_empty():
				sample.facing = atan2(target.x-origin.x,target.y-origin.y)
				next_rect = space._actor_rect(sample,next)
				# Keep exact points and both real rectangles: near-axis floats can
				# round to the same next point while retaining a different facing.
				proof_key = [origin,next,previous,next_rect]
				if proof.sweeps.has(proof_key):
					if not proof.sweeps[proof_key]: return false
					previous = next_rect
					origin = next
					continue
				# Bound scratch memory only; never limit candidates or sweep work.
				remember = proof.sweeps.size()<4096
				if remember: proof.sweeps[proof_key] = false
			if not query.sweep_reason(origin+shift,next+shift).is_empty(): return false
			var sweep: BodyIndex.Record = BodyIndex.Record.new()
			sweep.id = actor.id
			sweep.sweep_from = previous
			if not trial.is_empty():
				var proposal: Dictionary = ConvoyTrail.propose(trial,next)
				if not proposal.ok: return false
				trial.points = proposal.points
				sweep.sweep_to = Rect2(next+shift,Vector2.ONE*int(trial.size))
			else:
				if proof.is_empty():
					sample.facing = atan2(target.x-origin.x,target.y-origin.y)
					next_rect = space._actor_rect(sample,next)
				sweep.sweep_to = next_rect
			var contact: MotionResult = MotionResult.new()
			var sweeps: Array[BodyIndex.Record] = [sweep]
			_movement_contacts(world,actor.id,floor_id,sweep.sweep_from.merge(sweep.sweep_to),sweeps,members,contact)
			if contact.blocked: return false
			if remember: proof.sweeps[proof_key] = true
			previous = sweep.sweep_to
			origin = next
		if remember_segment: proof.segments[segment_key] = [origin,previous]
	return true

