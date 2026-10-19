class_name HospitalPublicAreas
extends RefCounted

# Geometry is derived, never saved. Intent and queue times belong to the
# original visit/staff/visitor task; this service owns no second queue.
var _space: WeakRef
var space: HospitalSpace:
	get: return _space.get_ref()
var _world: WeakRef
var _revision: int = -1
var _regions: Array = []
var _by_cell: Dictionary = {}
var _wait_geometry: Dictionary = {}
var _geometry_fits: Dictionary = {}

func _init(geometry: HospitalSpace) -> void:
	_space = weakref(geometry)

func invalidate() -> void:
	_revision = -1

func facility_changed(before: Dictionary, after: Dictionary) -> void:
	if before.get("footprint")!=after.get("footprint") or before.get("patient_cell")!=after.get("patient_cell") or before.get("operator_cells")!=after.get("operator_cells") or before.get("repair_cell")!=after.get("repair_cell"): _geometry_fits.clear()
	if before.get("footprint")!=after.get("footprint") or before.get("patient_cell")!=after.get("patient_cell"):
		invalidate()
	elif before.get("operator_cells")!=after.get("operator_cells") or before.get("repair_cell")!=after.get("repair_cell"):
		_wait_geometry = {}

func for_facility(world: WorldState, facility_id: String) -> Dictionary:
	_ensure(world)
	for area: Dictionary in _regions:
		if facility_id in area.facilities: return area.ref.duplicate(true)
	return {}

func _ensure(world: WorldState) -> void:
	if _world!=null and _world.get_ref()==world and _revision==world.geometry_revision: return
	_world = weakref(world)
	_revision = world.geometry_revision
	_regions.clear()
	_by_cell.clear()
	_wait_geometry = {}
	_geometry_fits.clear()
	var floors: Dictionary = {}
	for room: Dictionary in world.facts.rooms.values(): floors[int(room.floor_id)] = true
	for facility: Dictionary in world.facts.facilities.values(): floors[int(facility.floor_id)] = true
	for floor_id: int in floors:
		var zones: Dictionary = {}
		for plot: Array in HospitalSpace.floor_plots(world,floor_id):
			for y: int in range(int(plot[1])*32,(int(plot[1])+1)*32):
				for x: int in range(int(plot[0])*32,(int(plot[0])+1)*32): zones[Vector2i(x,y)] = ""
		for room_id: String in world.ids("rooms"):
			var room: Dictionary = world.facts.rooms[room_id]
			if int(room.floor_id)!=floor_id: continue
			for cell: Array in BuildGeometry.cells(room): zones[Vector2i(int(cell[0]),int(cell[1]))] = room_id
		var free: Dictionary = zones.duplicate()
		for cell: Array in HospitalSpace.floor_layout(world,floor_id).get("blocked",[]): free.erase(Vector2i(int(cell[0]),int(cell[1])))
		for collection: String in ["facilities","connectors"]:
			for record: Dictionary in world.facts[collection].values():
				if (int(record.floor_id)!=floor_id if collection=="facilities" else not HospitalTransit.has_stop(record,floor_id)) or record.get("stored",false): continue
				if collection=="facilities" and not space.content.facility_definition(record.definition_id).get("blocks_movement",true): continue
				var layout: Dictionary = space.facility_layout(world,record.id) if collection=="facilities" else record
				for y: int in range(int(layout.cell[1]),int(layout.cell[1])+int(layout.footprint[1])):
					for x: int in range(int(layout.cell[0]),int(layout.cell[0])+int(layout.footprint[0])): free.erase(Vector2i(x,y))
		var ordered: Array = free.keys()
		ordered.sort_custom(func(a: Vector2i,b: Vector2i)->bool: return a.y<b.y or a.y==b.y and a.x<b.x)
		var seen: Dictionary = {}
		for start: Vector2i in ordered:
			if seen.has(start): continue
			var cells: Dictionary = {start:true}
			var pending: Array[Vector2i] = [start]
			seen[start] = true
			var cursor: int = 0
			while cursor<pending.size():
				var point: Vector2i = pending[cursor]
				cursor += 1
				for direction: Vector2i in BuildGeometry.DIRECTIONS:
					var next: Vector2i = point+direction
					if seen.has(next) or not free.has(next) or zones[next]!=zones[start]: continue
					seen[next] = true
					cells[next] = true
					pending.append(next)
			var region: Dictionary = {"ref":{"floor_id":floor_id,"room_id":zones[start],"anchor":[start.x,start.y]},"cells":cells,"facilities":[]}
			_regions.append(region)
			for point: Vector2i in cells: _by_cell[_key(floor_id,point)] = region
		for id: String in world.ids("facilities"):
			var facility: Dictionary = world.facts.facilities[id]
			if int(facility.floor_id)!=floor_id or facility.get("stored",false): continue
			var layout: Dictionary = space.facility_layout(world,id)
			var point: Vector2i = Vector2i(int(layout.patient_cell[0]),int(layout.patient_cell[1]))
			var region: Dictionary = _by_cell.get(_key(floor_id,point),{})
			if not region.is_empty(): region.facilities.append(id)

static func _key(floor_id: int, point: Vector2i) -> String:
	return str(floor_id)+":"+str(point.x)+":"+str(point.y)

func region(world: WorldState, reference: Dictionary) -> Dictionary:
	_ensure(world)
	if reference.is_empty(): return {}
	if not str(reference.get("room_id","")).is_empty() and HospitalRemodel.blocked(world,reference.room_id): return {}
	var anchor: Array = reference.get("anchor",[])
	if anchor.size()!=2: return {}
	var result: Dictionary = _by_cell.get(_key(int(reference.floor_id),Vector2i(int(anchor[0]),int(anchor[1]))),{})
	return result if not result.is_empty() and result.ref==reference else {}

func contains(world: WorldState, reference: Dictionary, actor_id: String) -> bool:
	var area: Dictionary = region(world,reference)
	var actor: Dictionary = world.facts.actors[actor_id]
	if area.is_empty() or actor.location.kind!="floor" or int(actor.location.floor_id)!=int(reference.floor_id): return false
	var bounds: Rect2 = space.body_rectangle(actor)
	for y: int in range(floori(bounds.position.y),ceili(bounds.end.y)):
		for x: int in range(floori(bounds.position.x),ceili(bounds.end.x)):
			if not area.cells.has(Vector2i(x,y)): return false
	return true

func facilities(world: WorldState, reference: Dictionary, definitions: Array) -> Array:
	var result: Array = []
	for id: String in region(world,reference).get("facilities",[]):
		var facility: Dictionary = world.facts.facilities[id]
		if facility.definition_id in definitions and not facility.get("failed",false) and not HospitalRemodel.blocked(world,id): result.append(id)
	return result

func _fit_key(facility_id: String, world: WorldState, members: Array) -> String:
	var bodies: Array = []
	for id: String in members: bodies.append(space.body(world.facts.actors[id]))
	return JSON.stringify([facility_id,bodies])

func compatible_geometry(world: WorldState, reference: Dictionary, definitions: Array, members: Array) -> bool:
	for id: String in facilities(world,reference,definitions):
		var key: String = _fit_key(id,world,members)
		if not _geometry_fits.has(key): _geometry_fits[key] = space.facility_geometry_quote(world,id,members[0],members.slice(1)).ok
		if _geometry_fits[key]: return true
	return false

func select(world: WorldState, actor_id: String, definitions: Array, room_kinds: Array, purpose: String, members: Array = [], maximum_travel_ticks: int = 9223372036854775807, selected_entries: Dictionary = {}) -> Dictionary:
	_ensure(world)
	var actor: Dictionary = world.facts.actors[actor_id]
	if actor.location.kind!="floor": return {}
	var best: Dictionary = {}
	var best_entries: Dictionary = {}
	var travellers: Array = [actor_id] if members.is_empty() else members
	space.begin_dynamic_route_query(world)
	for area: Dictionary in _regions:
		var room: Dictionary = world.facts.rooms.get(area.ref.room_id,{})
		if not room.is_empty() and (not str(room.get("kind",room.get("type",""))) in room_kinds or HospitalRemodel.blocked(world,area.ref.room_id)): continue
		if room.is_empty() and not "" in room_kinds: continue
		var local: Array = facilities(world,area.ref,definitions)
		local = local.filter(func(id: String)->bool:
			if _geometry_fits.get(_fit_key(id,world,travellers),true)==false: return false
			if maximum_travel_ticks<9223372036854775807 and space.facility_travel_lower_bound_ticks(world,id,actor_id)>maximum_travel_ticks: return false
			var definition: Dictionary = space.content.facility_definition(world.facts.facilities[id].definition_id)
			var capacity: Dictionary = definition.get("adapter_capacity",definition)
			for member: String in travellers:
				var body: Dictionary = world.facts.actors[member]
				if space.clearance(body)>int(capacity.get("max_clearance_cells",96)) or float(space.body(body).height_m)>float(capacity.get("max_height_m",INF)): return false
			return true)
		if local.is_empty() and purpose!="rest": continue
		var inside: bool = contains(world,area.ref,actor_id)
		var waiting: int = _wait_estimate(world,area.ref,local,purpose)
		var travel_limit: int = maximum_travel_ticks
		if not best.is_empty():
			if purpose in ["water","toilet"]:
				if waiting>int(best.start_ticks): continue
				travel_limit = mini(travel_limit,int(best.start_ticks)-waiting)
			else:
				if best.inside and not inside: continue
				if inside==bool(best.inside): travel_limit = mini(travel_limit,int(best.travel_ticks))
		# Equal bounds remain candidates: the original stable area tie-break
		# and the slowest member's actual journey still decide the winner.
		var point: Dictionary = waiting_point(world,actor_id,area.ref,travel_limit)
		if point.is_empty(): continue
		var entries: Dictionary = {actor_id:point.duplicate(true)}
		var all_reachable: bool = true
		for member: String in travellers:
			if member==actor_id: continue
			var entry: Dictionary = waiting_point(world,member,area.ref,travel_limit)
			if entry.is_empty(): all_reachable = false; break
			entries[member] = entry
			point.travel_ticks = maxi(int(point.travel_ticks),int(entry.travel_ticks))
		if not all_reachable: continue
		point.area = area.ref.duplicate(true)
		point.inside = inside
		point.start_ticks = int(point.travel_ticks)+waiting
		if best.is_empty() or _earlier(point,best,purpose):
			best = point
			best_entries = entries
	space.end_route_query()
	selected_entries.merge(best_entries,true)
	return best

static func _earlier(a: Dictionary,b: Dictionary,purpose: String) -> bool:
	if purpose in ["water","toilet"] and a.start_ticks!=b.start_ticks: return a.start_ticks<b.start_ticks
	if not purpose in ["water","toilet"] and a.inside!=b.inside: return a.inside
	if a.travel_ticks!=b.travel_ticks: return a.travel_ticks<b.travel_ticks
	return JSON.stringify(a.area)<JSON.stringify(b.area)

func waiting_point(world: WorldState, actor_id: String, reference: Dictionary, maximum_travel_ticks: int = 9223372036854775807) -> Dictionary:
	space.begin_route_query(world,{},false)
	var result: Dictionary = _waiting_point(world,actor_id,reference,maximum_travel_ticks)
	space.end_route_query()
	return result

func _waiting_point(world: WorldState, actor_id: String, reference: Dictionary, maximum_travel_ticks: int) -> Dictionary:
	var area: Dictionary = region(world,reference)
	if area.is_empty(): return {}
	var actor: Dictionary = world.facts.actors[actor_id]
	var floor_id: int = int(reference.floor_id)
	if contains(world,reference,actor_id) and safe_wait(world,actor_id,floor_id,actor.location.cell):
		return {"floor_id":floor_id,"cell":actor.location.cell.duplicate(),"travel_ticks":0}
	var origin: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	var bounds: Dictionary = space.read_view(world,"public_entry_landings:"+actor_id+":"+str(floor_id),_entry_landings.bind(world,actor_id,floor_id))
	# Every complete cross-floor estimate must first reach a connector anchor
	# on this floor. With no complete landing estimate, trying every area cell
	# cannot produce one either, even when the common prefix is unknown.
	# This rejects only this read-only query; a later exit change is rechecked.
	if int(actor.location.floor_id)!=floor_id and bounds.landings.is_empty(): return {}
	if not bounds.landings.is_empty() and not bounds.unknown:
		var earliest: int = 9223372036854775807
		for landing: Dictionary in bounds.landings: earliest = mini(earliest,int(landing.ticks))
		if earliest>maximum_travel_ticks: return {}
	var points: Array = []
	for point: Vector2i in area.cells:
		var lower: int = _entry_lower_bound(actor,origin,point,bounds)
		if lower<=maximum_travel_ticks: points.append({"cell":point,"lower":lower})
	points.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		if a.lower!=b.lower: return a.lower<b.lower
		return a.cell.y<b.cell.y or a.cell.y==b.cell.y and a.cell.x<b.cell.x)
	var best: Dictionary = {}
	for candidate: Dictionary in points:
		if int(candidate.lower)>maximum_travel_ticks: break
		if not best.is_empty() and int(candidate.lower)>int(best.travel_ticks): break
		var point: Vector2i = candidate.cell
		var cell: Array = [point.x,point.y]
		if not safe_wait(world,actor_id,floor_id,cell): continue
		var route: Dictionary = space.travel_quote(world,actor_id,floor_id,cell)
		if not route.ok or not route.has("travel_ticks"): continue
		if int(route.travel_ticks)<=maximum_travel_ticks and (best.is_empty() or int(route.travel_ticks)<int(best.travel_ticks)): best = {"floor_id":floor_id,"cell":cell,"travel_ticks":int(route.travel_ticks)}
	return best

func _entry_landings(world: WorldState, actor_id: String, floor_id: int) -> Dictionary:
	var result: Dictionary = {"landings":[],"unknown":false}
	if int(world.facts.actors[actor_id].location.floor_id)==floor_id: return result
	for id: String in world.ids("connectors"):
		var connection: Dictionary = world.facts.connectors[id]
		if not HospitalTransit.has_stop(connection,floor_id): continue
		var quote: Dictionary = space.travel_quote(world,actor_id,floor_id,connection.anchor)
		if quote.ok and quote.has("travel_ticks"): result.landings.append({"cell":Vector2(int(connection.anchor[0]),int(connection.anchor[1])),"ticks":int(quote.travel_ticks)})
		elif quote.get("status","")=="estimate_unknown": result.unknown = true
	return result

func _entry_lower_bound(actor: Dictionary, origin: Vector2, point: Vector2i, bounds: Dictionary) -> int:
	var start: Vector2i = Vector2i(roundi(origin.x),roundi(origin.y))
	var horizontal: int = HospitalTransit.walking_ticks(space,actor,[],origin.distance_to(Vector2(start)))+HospitalTransit.walking_ticks(space,actor,[],absi(start.x-point.x)+absi(start.y-point.y))
	if bounds.landings.is_empty() or bounds.unknown: return horizontal
	# Every cross-floor route last enters this floor at a real connector.
	# Earliest arrival there plus the remaining Manhattan walk is a lower bound
	# for every entry cell. Unknown estimates retain the weaker geometric bound.
	var earliest: int = 9223372036854775807
	for landing: Dictionary in bounds.landings:
		earliest = mini(earliest,int(landing.ticks)+HospitalTransit.walking_ticks(space,actor,[],absf(landing.cell.x-point.x)+absf(landing.cell.y-point.y)))
	return earliest

func safe_wait(world: WorldState, actor_id: String, floor_id: int, cell: Array) -> bool:
	_ensure(world)
	var actor: Dictionary = world.facts.actors[actor_id]
	var point: Vector2i = Vector2i(roundi(cell[0]),roundi(cell[1]))
	if not space.static_reason(world,actor,floor_id,point).is_empty(): return false
	var bounds: Rect2 = space._actor_rect(actor,Vector2(float(cell[0]),float(cell[1])))
	if not space._dynamic_clear(world,actor_id,floor_id,bounds): return false
	var constraints: Dictionary = _wait_constraints(world)
	for door: Dictionary in constraints.doors.get(floor_id,[]):
		var span: int = int(world.facts.adaptations.get(door.id,{}).get("span",door.span))
		if bounds.intersects(space._door_rect(door,span).grow(1.0),false): return false
	for x: int in range(floori(bounds.position.x/8.0),floori(bounds.end.x/8.0)+1):
		for y: int in range(floori(bounds.position.y/8.0),floori(bounds.end.y/8.0)+1):
			for work: Vector2 in constraints.points.get(floor_id,{}).get(Vector2i(x,y),[]):
				if bounds.intersects(Rect2(work,Vector2.ONE),false): return false
	# Targets belong to this sealed query, never to the built-geometry cache.
	# Include every actor so a second requester gets its own self exclusion.
	var targets: Dictionary = space.read_view(world,"public_wait_targets",_wait_targets.bind(world))
	return not (targets.index as BodyIndex).intersects(floor_id,bounds,actor_id)

func _wait_targets(world: WorldState) -> Dictionary:
	var index: BodyIndex = BodyIndex.new()
	for movement: Dictionary in world.facts.moves.values():
		var target: Array = movement.target_cell
		index.update(movement.actor_id,int(movement.target_floor),space._actor_rect(world.facts.actors[movement.actor_id],Vector2(float(target[0]),float(target[1]))))
	return {"index":index}

func _wait_constraints(world: WorldState) -> Dictionary:
	if not _wait_geometry.is_empty(): return _wait_geometry
	var result: Dictionary = {"points":{},"doors":{}}
	for floor_key: String in world.facts.floors.overrides:
		var floor_id: int = int(floor_key)
		result.doors[floor_id] = []
		for door: Dictionary in world.facts.floors.overrides[floor_key].get("doors",[]): result.doors[floor_id].append(door)
	for facility: Dictionary in world.facts.facilities.values():
		var floor_id: int = int(facility.floor_id)
		if not result.points.has(floor_id): result.points[floor_id] = {}
		var layout: Dictionary = space.facility_layout(world,facility.id)
		for work: Array in [layout.get("patient_cell",[])]+layout.get("operator_cells",[])+[layout.get("repair_cell",[])]:
			if work.is_empty(): continue
			var point: Vector2 = Vector2(float(work[0]),float(work[1]))
			var bucket: Vector2i = Vector2i(floori(point.x/8.0),floori(point.y/8.0))
			if not result.points[floor_id].has(bucket): result.points[floor_id][bucket] = []
			result.points[floor_id][bucket].append(point)
	for connection: Dictionary in world.facts.connectors.values():
		for floor_id: int in HospitalTransit.routing_stops(connection,world,1,1):
			if not result.points.has(floor_id): result.points[floor_id] = {}
			var point: Vector2 = Vector2(float(connection.anchor[0]),float(connection.anchor[1]))
			var bucket: Vector2i = Vector2i(floori(point.x/8.0),floori(point.y/8.0))
			if not result.points[floor_id].has(bucket): result.points[floor_id][bucket] = []
			result.points[floor_id][bucket].append(point)
	_wait_geometry = result
	return result

func _wait_estimate(world: WorldState, reference: Dictionary, facility_ids: Array, purpose: String) -> int:
	if not purpose in ["water","toilet"]: return 0
	var view: Dictionary = space.read_view(world,"public_wait_estimate",_wait_estimate_view.bind(world))
	var earliest: int = 2147483647
	for id: String in facility_ids:
		earliest = mini(earliest,int(view.remaining.get(id,0)))
	if earliest==2147483647: return earliest
	var queued: int = int(view.queued.get(purpose,{}).get(JSON.stringify(reference,"",true,true),0))
	var service_ticks: int = 0
	for service: Dictionary in space.content.catalog.amenity_services:
		if service.purpose==purpose: service_ticks = ceili(float(service.ordinary_seconds)/WorldState.TICK_SECONDS)
	return earliest+ceili(float(queued)/maxi(1,facility_ids.size()))*service_ticks

func _wait_estimate_view(world: WorldState) -> Dictionary:
	var result: Dictionary = {"remaining":{},"queued":{}}
	for need: Dictionary in world.facts.get("waiting_life",{}).get("needs",{}).values():
		if need.phase in ["using","returning"]:
			var id: String = str(need.get("facility_id",""))
			result.remaining[id] = maxi(int(result.remaining.get(id,0)),int(need.remaining_ticks) if need.phase=="using" else 2147483647)
	for intent: Dictionary in intents(world):
		if int(intent.get("arrived_tick",-1))<0 or not intent.phase in ["local_wait","local_travel"]: continue
		var purpose: String = str(intent.get("public_purpose",""))
		var area: Dictionary = intent.get("area",{})
		# Region identity has no dictionary insertion-order semantics. A raw
		# Dictionary key has an order-sensitive hash even when equality is true.
		var key: String = JSON.stringify(area,"",true,true)
		if not result.queued.has(purpose): result.queued[purpose] = {}
		result.queued[purpose][key] = int(result.queued[purpose].get(key,0))+1
	return result

func intents(world: WorldState) -> Array:
	return space.read_view(world,"public_intents",_intent_view.bind(world)).items

func _intent_view(world: WorldState) -> Dictionary:
	var result: Array = []
	for collection: String in ["seats","needs"]:
		for intent: Dictionary in world.facts.get("waiting_life",{}).get(collection,{}).values():
			if intent.has("public_purpose"): result.append(intent)
	for staff: Dictionary in world.facts.staff.values():
		var task: Dictionary = staff.get("life_task",{})
		if task.has("public_purpose"): result.append(task)
	for stay: Dictionary in world.facts.get("visitors",{}).get("stays",{}).values():
		if stay.has("public_use"): result.append(stay.public_use)
	return {"items":result}

func turn(world: WorldState, intent: Dictionary, facility_id: String) -> bool:
	for other: Dictionary in intents(world):
		if is_same(other,intent) or int(other.get("arrived_tick",-1))<0 or not other.get("phase","") in ["local_wait","local_travel","manual_wait"] or other.get("public_purpose","")!=intent.public_purpose: continue
		# A local journey competes for its chosen target only. It cannot hold
		# every other free device in the area while that journey is in progress.
		if other.phase=="local_travel" and other.get("facility_id","")!=facility_id: continue
		if other.get("mode","auto")=="manual" and other.get("manual_facility_id","")!=facility_id: continue
		if other.get("mode","auto")!="manual" and not facility_id in region(world,other.get("area",{})).get("facilities",[]): continue
		var before: bool = int(other.arrived_tick)<int(intent.arrived_tick) or int(other.arrived_tick)==int(intent.arrived_tick) and str(other.id)<str(intent.id)
		if int(intent.get("arrived_tick",-1))<0: before = true
		if intent.public_purpose=="seat" and intent.has("ticket_id")!=other.has("ticket_id"): before = other.has("ticket_id")
		if not before: continue
		var ids: Array = other.get("staff_ids",[str(other.actor_id)])
		if ids.is_empty(): continue
		var fit: Dictionary = _queue_fit(world,facility_id,ids)
		if fit.ok: return false
	return true

func _queue_fit(world: WorldState, facility_id: String, ids: Array) -> Dictionary:
	var fits: Dictionary = space.read_view(world,"public_queue_fits",func()->Dictionary: return {})
	var key: String = JSON.stringify([facility_id,ids])
	if not fits.has(key): fits[key] = _queue_fit_in_query(world,facility_id,ids)
	return fits[key]

func _queue_fit_in_query(world: WorldState, facility_id: String, ids: Array) -> Dictionary:
	var current: Dictionary = world.facts.adaptations.get(facility_id,{})
	if current.is_empty(): return space.facility_quote(world,facility_id,ids[0],ids.slice(1))
	# Queue eligibility asks whether the next body fits after the current user
	# leaves. The departing user's still-unfolded adapter must not let that same
	# user repeatedly bypass an older eligible waiter and take the seat again.
	var facts: Dictionary = world.facts.duplicate()
	facts.adaptations = world.facts.adaptations.duplicate()
	facts.adaptations.erase(facility_id)
	facts.actors = world.facts.actors.duplicate()
	for actor_id: String in [current.actor_id]+current.staff_ids:
		if actor_id in ids: continue
		facts.actors[actor_id] = world.facts.actors[actor_id].duplicate()
		facts.actors[actor_id].location = {"kind":"outside"}
	var candidate: WorldState = WorldState.new(facts)
	space.prepare_projection(world,candidate,[facility_id])
	space.begin_route_query(candidate,{},false)
	var quote: Dictionary = space.facility_quote(candidate,facility_id,ids[0],ids.slice(1))
	space.end_route_query()
	return quote
