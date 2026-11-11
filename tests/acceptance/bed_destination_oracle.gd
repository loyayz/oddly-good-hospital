extends RefCounted

# Full facts, independent of reservation views, BodyIndex, summaries and the
# production permission helper. Stable first identity follows sorted region IDs.
static func blocker(world: WorldState, actor_id: String, floor_id: int, rect: Rect2, members: Array = []) -> String:
	var rows: Array=[]
	for id: String in world.facts.adaptations:
		var reservation: Dictionary=world.facts.adaptations[id]
		if reservation.get("kind","")!="facility" or int(reservation.floor_id)!=floor_id: continue
		if world.facts.facilities.get(reservation.get("facility_id",""),{}).get("definition_id","")!="EQ05": continue
		if actor_id==reservation.actor_id or actor_id in reservation.staff_ids or reservation.actor_id in members: continue
		for ordinal: int in range(1,reservation.regions.size()):
			var area: Array=reservation.regions[ordinal]
			var region:=Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3]))
			if rect.intersects(region,false): rows.append({"key":id+":"+str(ordinal),"id":id})
	rows.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return str(a.key)<str(b.key))
	return "" if rows.is_empty() else str(rows[0].id)
