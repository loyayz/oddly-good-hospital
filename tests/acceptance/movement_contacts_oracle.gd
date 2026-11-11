extends RefCounted

# Enumerate complete facts and explicit accepted-sweep inputs. No spatial
# indexes, candidate limit, production contact function or old output is used.
# Body/convoy geometry and BodySweep remain the unchanged geometry interface.
static func capture(world: WorldState, space: HospitalSpace, accepted: Dictionary = {}) -> Dictionary:
	var current: Dictionary={}
	var grouped: Dictionary={}
	for movement: Dictionary in world.facts.moves.values():
		if not movement.has("convoy"): continue
		for id: String in movement.members: grouped[id]=true
		var actor: Dictionary=world.facts.actors[movement.actor_id]
		var regions: Array[Rect2]=ConvoyTrail.regions(movement.convoy)
		if actor.location.kind=="transit": regions=ConvoyPortal.ground_regions(movement.convoy,world.facts.connectors[actor.location.connector_id])
		if regions.is_empty(): continue
		var broad: Rect2=regions[0]
		for region: Rect2 in regions: broad=broad.merge(region)
		current[actor.id]={"floor_id":int(movement.convoy.floor_id),"rect":broad,"regions":regions.duplicate()}
	for id: String in world.facts.actors:
		var actor: Dictionary=world.facts.actors[id]
		if actor.location.kind=="floor" and not grouped.has(id): current[id]={"floor_id":int(actor.location.floor_id),"rect":space.body_rectangle(actor),"regions":[]}
	var sweeps: Dictionary={}
	for id: String in accepted:
		var sweep: BodyIndex.Record=accepted[id]
		sweeps[id]={"floor_id":sweep.floor_id,"from":sweep.sweep_from,"to":sweep.sweep_to,"rect":sweep.sweep_from.merge(sweep.sweep_to),"regions":sweep.regions.duplicate()}
	var reservations: Array=[]
	for id: String in world.facts.adaptations:
		var reservation: Dictionary=world.facts.adaptations[id]
		for ordinal: int in reservation.get("regions",[]).size():
			var raw: Array=reservation.regions[ordinal]
			var soft: bool=reservation.kind=="facility" and world.facts.facilities.get(reservation.get("facility_id",""),{}).get("definition_id","")=="EQ05"
			reservations.append({"key":id+":"+str(ordinal),"id":id,"reservation":reservation.duplicate(true),"rect":Rect2(float(raw[0]),float(raw[1]),float(raw[2]),float(raw[3])),"blocks":ordinal==0 or not soft})
	reservations.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return str(a.key)<str(b.key))
	return {"current":current,"accepted":sweeps,"reservations":reservations}

static func _overlap(record: Dictionary, broad: Rect2, compound: bool) -> bool:
	if compound and not record.regions.is_empty():
		for region: Rect2 in record.regions:
			if broad.intersects(region,false): return true
		return false
	return broad.intersects(record.rect,false)

static func candidates(snapshot: Dictionary, floor_id: int, broad: Rect2, members: Array) -> Dictionary:
	var current: Array[String]=[]
	var accepted: Array[String]=[]
	var union: Dictionary={}
	for id: String in snapshot.current:
		var record: Dictionary=snapshot.current[id]
		if int(record.floor_id)==floor_id and not id in members and _overlap(record,broad,true): current.append(id);union[id]=true
	for id: String in snapshot.accepted:
		var record: Dictionary=snapshot.accepted[id]
		if int(record.floor_id)==floor_id and not id in members and _overlap(record,broad,false): accepted.append(id);union[id]=true
	current.sort();accepted.sort()
	var all: Array[String]=[]
	for id: String in union: all.append(id)
	all.sort()
	return {"current":current,"accepted":accepted,"all":all}

static func _allows(reservation: Dictionary, actor_id: String, members: Array) -> bool:
	if reservation.kind=="door":
		if actor_id!=reservation.actor_id and not actor_id in reservation.staff_ids: return false
		for id: String in members:
			if id!=reservation.actor_id and not id in reservation.staff_ids: return false
		return true
	return actor_id==reservation.actor_id or actor_id in reservation.staff_ids or reservation.actor_id in members

static func query(snapshot: Dictionary, actor_id: String, floor_id: int, broad: Rect2, probes: Array[BodyIndex.Record], members: Array, first: bool = false) -> Dictionary:
	var actors: Array[String]=[]
	var held: Array[String]=[]
	var found: Dictionary=candidates(snapshot,floor_id,broad,members)
	for id: String in found.all:
		var current: Dictionary=snapshot.current.get(id,{})
		var accepted: Dictionary=snapshot.accepted.get(id,{})
		var from: Rect2=current.get("rect",Rect2()) if accepted.is_empty() else accepted.from
		var to: Rect2=from if accepted.is_empty() else accepted.to
		var regions: Array=accepted.regions if not accepted.get("regions",[]).is_empty() else current.get("regions",[])
		var hit: bool=false
		for probe: BodyIndex.Record in probes:
			if regions.is_empty(): hit=BodySweep.intersects(probe.sweep_from,probe.sweep_to,from,to)
			else:
				for region: Rect2 in regions:
					if BodySweep.intersects(probe.sweep_from,probe.sweep_to,region,region): hit=true;break
			if hit: break
		if hit:
			actors.append(id)
			if first: return _result(actors,held,found)
	for row: Dictionary in snapshot.reservations:
		var reservation: Dictionary=row.reservation
		if not row.blocks or int(reservation.floor_id)!=floor_id or not broad.intersects(row.rect,false) or _allows(reservation,actor_id,members) or str(row.id) in held: continue
		for probe: BodyIndex.Record in probes:
			if BodySweep.intersects(probe.sweep_from,probe.sweep_to,row.rect,row.rect):
				held.append(str(row.id))
				if first: return _result(actors,held,found)
				break
	held.sort()
	return _result(actors,held,found)

static func _result(actors: Array[String], held: Array[String], found: Dictionary) -> Dictionary:
	return {"actors":actors,"reservations":held,"candidate_ids":found.all,"current_candidates":found.current,"accepted_candidates":found.accepted,"blocked":not actors.is_empty() or not held.is_empty()}

static func typed(result: HospitalMovement.MotionResult) -> Dictionary:
	return {"actors":result.blocker_actor_ids.duplicate(),"reservations":result.reservation_ids.duplicate(),"blocked":result.blocked,"requested":result.requested_motion,"actual":result.actual_motion,"static_reason":result.static_reason,"door_id":result.door_id,"first_contact_only":result.first_contact_only}

static func expected_typed(result: Dictionary, first: bool) -> Dictionary:
	return {"actors":result.actors.duplicate(),"reservations":result.reservations.duplicate(),"blocked":result.blocked,"requested":Vector2.ZERO,"actual":Vector2.ZERO,"static_reason":"","door_id":"","first_contact_only":first}
