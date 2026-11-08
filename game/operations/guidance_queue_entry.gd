extends RefCounted
const Layout=preload("res://game/operations/guidance_queue_layout.gd")

# Actual geometry/occupancy only. No admission token, queue number, reservation
# or world fact is created here. Runtime immutable-geometry caches may be read.
static func context(space: HospitalSpace, world: WorldState, desk_id: String) -> Dictionary:
	# Reuse the existing geometry-revision context, not a new occupancy cache.
	# Capacity below is always read afresh from actual bodies at this step.
	if space.guidance_queue_provider!=null:
		var provider: RefCounted=space.guidance_queue_provider.get_ref()
		if provider!=null:
			var geometry: Dictionary=provider._queue_context(world,desk_id)
			if not geometry.is_empty():
				if not geometry.has("entry_context"):geometry.entry_context=_build_context(space,world,desk_id)
				return geometry.entry_context
	return _build_context(space,world,desk_id)

static func _build_context(space: HospitalSpace, world: WorldState, desk_id: String) -> Dictionary:
	var desk: Dictionary=world.facts.facilities.get(desk_id,{})
	if desk.is_empty() or desk.get("definition_id","")!="SE01":return {}
	var room: Dictionary=world.facts.rooms.get(str(desk.get("room_id","")),{})
	if room.is_empty() or int(room.floor_id)!=int(desk.floor_id):return {}
	var floor_id: int=int(desk.floor_id)
	var bounds: Rect2=Rect2(float(room.origin[0]),float(room.origin[1]),float(room.size[0]),float(room.size[1]))
	if not bounds.has_area() or not bounds.encloses(Rect2(float(desk.cell[0]),float(desk.cell[1]),float(desk.footprint[0]),float(desk.footprint[1]))):return {}
	# Prototype supports a dedicated single-desk room (optionally its drinking
	# water fixture). Shared clinical/bed/other desk rooms need a different
	# capacity model: do not turn their legitimate occupants into a false full
	# guidance queue. This explicit fallback also covers open halls.
	for facility: Dictionary in world.facts.facilities.values():
		if facility.id==desk_id or int(facility.floor_id)!=floor_id:continue
		var footprint: Rect2=Rect2(float(facility.cell[0]),float(facility.cell[1]),float(facility.footprint[0]),float(facility.footprint[1]))
		if str(facility.get("room_id",""))!=str(room.id) and not footprint.intersects(bounds,false):continue
		if facility.get("definition_id","")!="FUR17":return {}
	var doors: Array[Rect2]=[]
	for door: Dictionary in world.facts.floors.overrides.get(str(floor_id),{}).get("doors",[]):
		if door.get("room_id","")!=room.id:continue
		if int(door.get("span",0))<1 or door.get("axis","") not in ["x","y"]:return {}
		var rect: Rect2=space._door_rect(door,int(door.span))
		# Accept only actual doors adjoining this room boundary, not an
		# arbitrary remote marker whose room_id happens to match.
		var adjacent: bool=false
		if door.axis=="x":
			adjacent=rect.position.x>=bounds.position.x and rect.end.x<=bounds.end.x and (is_equal_approx(rect.position.y,bounds.end.y) or is_equal_approx(rect.end.y,bounds.position.y))
		else:
			adjacent=rect.position.y>=bounds.position.y and rect.end.y<=bounds.end.y and (is_equal_approx(rect.position.x,bounds.end.x) or is_equal_approx(rect.end.x,bounds.position.x))
		if not adjacent:return {}
		doors.append(rect)
	if doors.is_empty():return {}
	return {"floor_id":floor_id,"room":room,"room_bounds":bounds,"door_bounds":doors,"desk_id":desk_id}

static func is_inside(ctx: Dictionary, space: HospitalSpace, actor: Dictionary, point: Vector2) -> bool:
	if ctx.is_empty() or actor.get("location",{}).get("kind","")!="floor" or int(actor.location.floor_id)!=int(ctx.floor_id):return false
	var body: Rect2=space._actor_rect(actor,point)
	if body.intersects(ctx.room_bounds,false):return true
	for door: Rect2 in ctx.door_bounds:
		if body.intersects(door,false):return true
	return false

# A read-only counterpart to queue membership. Do not call _queue_members or
# _queue_participating: those also observe departures and change live facts.
static func _held_member(space: HospitalSpace, world: WorldState, provider: RefCounted, row: Dictionary, visit: Dictionary, actor: Dictionary) -> bool:
	if not row.has("queue_seq") or row.get("phase","") not in ["desk_queue","to_counter","working"]:return false
	if actor.location.kind!="floor" or int(actor.location.floor_id)!=int(row.get("guide_floor",0)):return false
	var move: Dictionary=world.facts.moves.get(actor.id,{})
	var external: bool=not move.is_empty() and move.get("floor_guidance_key","")!=row.get("request_key","")
	var need: bool=world.facts.get("waiting_life",{}).get("needs",{}).has(visit.id)
	var at_slot: bool=row.has("queue_cell") and space.at(world,actor.id,int(row.guide_floor),row.queue_cell)
	if need or external:return at_slot
	if row.phase in ["to_counter","working"]:return true
	var bank: String=provider._queue_bank_key(world,str(row.desk_id))
	var participating: bool=row.get("queue_attending",false) and row.get("queue_bank_key","")==bank
	if not move.is_empty():participating=participating and move.get("floor_guidance_queue_advance","")==bank
	return participating or at_slot

static func capacity_available(space: HospitalSpace, world: WorldState, provider: RefCounted, actor_id: String, desk_id: String) -> bool:
	var ctx: Dictionary=context(space,world,desk_id)
	# An open hall or unproved room boundary must not acquire a fake gate.
	if ctx.is_empty() or provider==null:return true
	var actor: Dictionary=world.facts.actors.get(actor_id,{})
	if actor.is_empty():return false
	var occupants: Array=[]
	var seen: Dictionary={}
	for row: Dictionary in world.facts.floor_guidance.visits.values():
		if row.get("desk_id","")!=desk_id:continue
		var visit: Dictionary=world.facts.visits.get(str(row.get("visit_id","")),{})
		if visit.is_empty() or visit.get("phase","") in ["leaving","departed"]:continue
		var id: String=str(visit.actor_id)
		if id==actor_id or seen.has(id):continue
		var other: Dictionary=world.facts.actors.get(id,{})
		if other.is_empty() or other.location.kind!="floor" or int(other.location.floor_id)!=int(ctx.floor_id):continue
		var held: bool=_held_member(space,world,provider,row,visit,other)
		var entering: bool=row.get("phase","")=="seek" and is_inside(ctx,space,other,Vector2(other.location.cell[0],other.location.cell[1]))
		if not held and not entering:continue
		seen[id]=true
		occupants.append({"id":id,"span":space.clearance(other),"held":held,"sequence":int(row.get("queue_seq",0))})
	# Physical departing patients still consume this bounded room's capacity,
	# even after their guidance row changed desk/floor or their number vanished.
	# Count all patient bodies here, not just current same-desk intentions.
	for visit: Dictionary in world.facts.visits.values():
		var id: String=str(visit.get("actor_id",""))
		if id==actor_id or seen.has(id):continue
		var other: Dictionary=world.facts.actors.get(id,{})
		if other.is_empty() or other.location.kind!="floor" or int(other.location.floor_id)!=int(ctx.floor_id):continue
		if not is_inside(ctx,space,other,Vector2(other.location.cell[0],other.location.cell[1])):continue
		seen[id]=true
		occupants.append({"id":id,"span":space.clearance(other),"held":false,"sequence":0})
	# Existing queue order stays unchanged. The ID tie-break only gives this
	# temporary geometric calculation a stable order, never a service number.
	occupants.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		if a.held!=b.held:return a.held
		if a.held and a.sequence!=b.sequence:return a.sequence<b.sequence
		return a.id<b.id)
	var spans: Array=[]
	for occupant: Dictionary in occupants:spans.append(occupant.span)
	var geometry: Dictionary=provider._queue_context(world,desk_id)
	if geometry.is_empty():return true
	var valid: Callable=func(index: int,cell: Array)->bool:return provider._queue_position_allowed(world,occupants[index].id,desk_id,cell,int(spans[index]))
	var packing: Dictionary=Layout.pack(geometry.facility,geometry.walls,geometry.bounds,spans,valid)
	if not packing.complete:return false
	var span: int=space.clearance(actor)
	var allowed: Callable=func(_index: int,cell: Array)->bool:return provider._queue_position_allowed(world,actor_id,desk_id,cell,span)
	return bool(Layout.probe(packing,span,allowed).get("ok",false))

static func block_entry(space: HospitalSpace, world: WorldState, provider: RefCounted, actor_id: String, movement: Dictionary, start: Vector2, next: Vector2) -> bool:
	if provider==null or movement.has("convoy") or movement.get("members",[actor_id]).size()!=1:return false
	var actor: Dictionary=world.facts.actors.get(actor_id,{})
	if actor.is_empty() or actor.location.kind!="floor":return false
	var key: String=str(movement.get("floor_guidance_key",""))
	if key.is_empty():return false
	for row: Dictionary in world.facts.floor_guidance.visits.values():
		if row.get("phase","")!="seek" or row.get("request_key","")!=key:continue
		var visit: Dictionary=world.facts.visits.get(str(row.get("visit_id","")),{})
		if visit.get("actor_id","")!=actor_id:continue
		var ctx: Dictionary=context(space,world,str(row.get("desk_id","")))
		if ctx.is_empty() or int(ctx.floor_id)!=int(actor.location.floor_id):return false
		# Actual presence is the only entry admission. Never stop a body
		# already crossing the door, and never block a departure from inside.
		if is_inside(ctx,space,actor,start) or not is_inside(ctx,space,actor,next):return false
		return not capacity_available(space,world,provider,actor_id,str(row.desk_id))
	return false
