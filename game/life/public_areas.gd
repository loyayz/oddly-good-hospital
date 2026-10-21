class_name HospitalPublicAreas
extends RefCounted

const ENTRY_GRID_WIDTH: int = FloorNavigation.SIDE
const ENTRY_CELL_COUNT: int = ENTRY_GRID_WIDTH*ENTRY_GRID_WIDTH
const ENTRY_SORT_LIMIT: int = (HospitalTransit.MAX_TICK-(ENTRY_CELL_COUNT-1))/ENTRY_CELL_COUNT

# Geometry is derived, never saved. Intent and queue times belong to the
# original visit/staff/visitor task; this service owns no second queue.
var _space: WeakRef
var space: HospitalSpace:
	get: return _space.get_ref()
var _world: WeakRef
var _revision: int = -1
var _regions: Array = []
var _by_cell: Dictionary = {}
var _by_facility: Dictionary = {}
var _derived_floors: Dictionary = {}
var _wait_geometry: Dictionary = {}
var _geometry_fits: Dictionary = {}
var _entry_geometry: Dictionary = {}
var _decision_world: WeakRef
var _decision_tick: int = -1
var _decision_basis: Dictionary = {}
var _wait_results: Dictionary = {}

func _init(geometry: HospitalSpace) -> void:
	_space = weakref(geometry)

func invalidate() -> void:
	_revision = -1
	_decision_tick = -1

func changed(world: WorldState) -> void:
	if _decision_world!=null and _decision_world.get_ref()==world: _decision_tick = -1

func area_valid(world: WorldState, reference: Dictionary, room_kinds: Array) -> bool:
	if region(world,reference).is_empty(): return false
	var room: Dictionary = world.facts.rooms.get(reference.get("room_id",""),{})
	return "" in room_kinds if room.is_empty() else str(room.get("kind",room.get("type",""))) in room_kinds and not HospitalRemodel.blocked(world,str(room.id))

func should_recheck(world: WorldState, intent: Dictionary, definitions: Array, members: Array = [], extra: Dictionary = {}) -> bool:
	_decision_view(world)
	var saved: Dictionary = _wait_results.get(str(intent.id),{})
	var signature: Array = _decision_signature(world,intent,definitions,members,extra,saved.get("floors",[]))
	var repeat: bool = saved.get("signature",[])==signature
	var counter: String = "public_wait_hits" if repeat else "public_wait_rechecks"
	space.query_counts[counter] = int(space.query_counts.get(counter,0))+1
	return not repeat

func remember_wait(world: WorldState, intent: Dictionary, definitions: Array, members: Array = [], extra: Dictionary = {}) -> void:
	var ids: Array = [str(intent.actor_id)] if members.is_empty() else members
	var floors: Array = space.navigation.observed_floors(world,ids)
	var local: int = int(intent.get("area",{}).get("floor_id",0))
	if local>0 and not local in floors:
		floors.append(local)
		floors.sort()
	# Freeze nested facts once. Live observations can then use structural value
	# equality without serializing the whole dependency set on every wait step.
	var signature: Array = _decision_signature(world,intent,definitions,members,extra,floors)
	_wait_results[str(intent.id)] = {"signature":signature.duplicate(true),"floors":floors}

# One shared observation of actual ownership per changed dispatch boundary.
# Rows refer to original intents: phase changes are read from their sole owner.
func _decision_view(world: WorldState) -> Dictionary:
	if _decision_world==null or _decision_world.get_ref()!=world:
		_decision_world = weakref(world)
		_decision_tick = -1
		_wait_results.clear()
	if _decision_tick==world.sim_tick and _decision_basis.get("geometry_revision",-1)==world.geometry_revision: return _decision_basis
	_decision_tick = world.sim_tick
	var users: Dictionary = {}
	for actor: Dictionary in world.facts.actors.values():
		var id: String = str(actor.get("support_facility_id",""))
		if not id.is_empty(): users.get_or_add(id,[]).append(actor.id)
	var queues: Dictionary = {}
	var active: Dictionary = {}
	for intent: Dictionary in _intent_view(world).items:
		active[str(intent.id)] = true
		var purpose: String = str(intent.get("public_purpose",""))
		var key: String = JSON.stringify([purpose,intent.get("area",{})],"",true,true)
		queues.get_or_add(key,[]).append(intent)
		if intent.get("phase","") in ["using","seated","returning"]:
			var id: String = str(intent.get("facility_id",""))
			if not id.is_empty(): users.get_or_add(id,[]).append(str(intent.get("actor_id","")))
	for id: String in _wait_results.keys():
		if not active.has(id): _wait_results.erase(id)
	var environment: Dictionary = {}
	for facility: Dictionary in world.facts.facilities.values():
		environment.get_or_add(int(facility.floor_id),[]).append([facility.cell,"facility",[facility.id,facility.definition_id,facility.get("level",1),facility.get("failed",false)]])
	for collection: String in ["surfaces","dirt"]:
		for record: Dictionary in world.facts.get("environment",{}).get(collection,{}).values():
			if collection=="dirt" and not str(record.get("bin_id","")).is_empty(): continue
			environment.get_or_add(int(record.floor_id),[]).append([record.cell,collection,record])
	for session: Dictionary in world.facts.sessions.values():
		var used: String = str(session.get("facility_id",""))
		if not used.is_empty(): users.get_or_add(used,[]).append("session:"+str(session.get("id","")))
		if not session.kind in ["outpatient","surgery","operate"]: continue
		var facility: Dictionary = world.facts.facilities.get(session.get("facility_id",""),{})
		if not facility.is_empty(): environment.get_or_add(int(facility.floor_id),[]).append([facility.cell,"machine",[facility.definition_id,facility.get("failed",false)]])
	for order: Dictionary in world.facts.get("environment",{}).get("orders",{}).values():
		if order.get("paused",false): continue
		for unit: Dictionary in order.get("units",[]):
			if unit.get("phase","")=="working" and not str(unit.get("worker_id","")).is_empty(): environment.get_or_add(int(order.floor_id),[]).append([unit.cell,"construction",unit.get("worker_id","")])
	for order: Dictionary in world.facts.get("maintenance",{}).get("upgrades",{}).values():
		if order.get("phase","")!="working": continue
		var facility: Dictionary = world.facts.facilities.get(order.get("facility_id",""),{})
		if not facility.is_empty(): environment.get_or_add(int(facility.floor_id),[]).append([facility.cell,"upgrade",facility.id])
	_decision_basis = {"users":users,"queues":queues,"environment":environment,"environment_indices":{},"geometry_revision":world.geometry_revision}
	return _decision_basis

func _decision_signature(world: WorldState, intent: Dictionary, definitions: Array, members: Array, extra: Dictionary, route_floors: Array = []) -> Array:
	var view: Dictionary = _decision_view(world)
	var ids: Array = [str(intent.actor_id)] if members.is_empty() else members
	var bodies: Array = []
	for id: String in ids:
		var actor: Dictionary = world.facts.actors[id]
		bodies.append([id,space.body(actor),actor.location,actor.get("posture","standing"),actor.get("facing",0.0)])
	var reference: Dictionary = intent.get("area",{})
	var room: Dictionary = world.facts.rooms.get(reference.get("room_id",""),{})
	var records: Array = [reference,room.get("kind",room.get("type","")),room.get("origin",[]),room.get("size",[]),room.get("wall_edges",[]),definitions,bodies,extra,intent.get("mode","auto"),intent.get("manual_facility_id",""),intent.get("arrived_tick",-1),intent.get("started_tick",-1),intent.has("ticket_id"),"R15" in world.facts.research]
	records.append(space.navigation.connection_basis(world))
	var points: Array = []
	var other_ids: Dictionary = {}
	var reservations: Dictionary = {}
	space._ensure_actor_index(world)
	var area: Dictionary = region(world,reference)
	records.append(area.get("geometry",""))
	var route_dependent: bool = intent.public_purpose=="rest" or definitions.is_empty()
	for facility_id: String in area.get("facilities",[]):
		var facility: Dictionary = world.facts.facilities[facility_id]
		if not facility.definition_id in definitions: continue
		var users: Array = view.users.get(facility_id,[])
		var reservation: Dictionary = world.facts.get("staff_life",{}).get("reservations",{}).get(facility_id,{})
		var adaptation: Dictionary = world.facts.adaptations.get(facility_id,{})
		records.append([facility_id,facility.definition_id,facility.cell,facility.footprint,facility.get("rotation",0),facility.get("patient_cell",[]),facility.get("operator_cells",[]),facility.get("repair_cell",[]),facility.get("failed",false),HospitalRemodel.blocked(world,facility_id),users,reservation.get("id",""),reservation.get("staff_ids",[]),adaptation.get("actor_id",""),adaptation.get("staff_ids",[]),adaptation.get("regions",[])])
		var occupied: bool = false
		for owner: String in users:
			if not owner in ids: occupied = true
		if occupied or not reservation.is_empty() or not adaptation.is_empty() and not str(adaptation.get("actor_id","")) in ids: continue
		route_dependent = true
		var layout: Dictionary = space.facility_layout(world,facility_id)
		for point: Array in [layout.patient_cell]+layout.get("operator_cells",[])+[layout.get("repair_cell",layout.patient_cell)]:
			points.append(point)
			var reach: float = maxf(6.0,float(space.clearance(world.facts.actors[ids[0]]))+1.0)
			var bounds: Rect2 = Rect2(Vector2(float(point[0]),float(point[1])),Vector2.ONE).grow(reach)
			_add_dynamic_dependencies(world,int(reference.floor_id),bounds,ids,other_ids,reservations)
	if (intent.public_purpose=="rest" or definitions.is_empty()) and not area.is_empty():
		# Tea is a real free standing place, including a region with no chairs.
		# Its availability can change when any body/reservation leaves that area.
		var bounds: Rect2 = Rect2(area.bounds).grow(float(space.clearance(world.facts.actors[ids[0]]))+1.0)
		_add_dynamic_dependencies(world,int(reference.floor_id),bounds,ids,other_ids,reservations)
	if route_dependent:
		# A failed route may recover through a remote floor. Retain the exact
		# static sources actually searched, plus newly declared routing stops.
		var versions: Array = []
		for floor_id: int in route_floors: versions.append([floor_id,space._navigation.floor_static_version(space,world,floor_id)])
		records.append([versions,space.navigation.routing_floor_basis(world)])
	var queue_key: String = JSON.stringify([intent.public_purpose,reference],"",true,true)
	for other: Dictionary in view.queues.get(queue_key,[]):
		if str(other.get("id",""))==str(intent.id) or int(other.get("arrived_tick",-1))<0: continue
		if not other.get("phase","") in ["local_wait","local_travel","manual_wait"]: continue
		var queue_bodies: Array = []
		for id: String in other.get("staff_ids",[str(other.actor_id)]):
			if world.facts.actors.has(id):
				var actor: Dictionary = world.facts.actors[id]
				queue_bodies.append([id,space.body(actor),actor.get("posture","standing"),actor.get("facing",0.0)])
		records.append([other.id,other.arrived_tick,other.phase,other.get("facility_id",""),other.get("mode","auto"),other.get("manual_facility_id",""),queue_bodies])
	var sorted_ids: Array = other_ids.keys()
	sorted_ids.sort()
	for id: String in sorted_ids:
		var other: Dictionary = world.facts.actors[id]
		var pair: Array = [str(intent.actor_id),id]
		pair.sort()
		records.append([id,other.location,space.body(other),other.get("posture","standing"),other.get("facing",0.0),world.facts.moves.has(id),world.facts.get("relationships",{}).get(":".join(pair),{})])
	var reservation_ids: Array = reservations.keys()
	reservation_ids.sort()
	for id: String in reservation_ids: records.append(reservations[id])
	records.append_array(_environment_samples(view,int(reference.get("floor_id",-1)),points))
	return records

func _environment_samples(view: Dictionary, floor_id: int, points: Array) -> Array:
	var samples: Array = view.environment.get(floor_id,[])
	if points.is_empty() or samples.is_empty(): return []
	var indices: Dictionary = view.environment_indices
	if not indices.has(floor_id):
		var created: BodyIndex = BodyIndex.new()
		for number: int in samples.size():
			var cell: Array = samples[number][0]
			# Unit rectangles are broadphase proxies for sample origins only.
			# Exact original Manhattan distance below decides inclusion.
			created.update(str(number),floor_id,Rect2(Vector2(float(cell[0]),float(cell[1])),Vector2.ONE))
		indices[floor_id] = created
	var index: BodyIndex = indices[floor_id]
	var origins: Dictionary = {}
	for point: Array in points: origins[point] = true
	var matched: Dictionary = {}
	for point: Array in origins:
		# Padding keeps exact eight-cell boundaries inside the broadphase,
		# including fractional coordinates and float32 rectangle rounding.
		var bounds: Rect2 = Rect2(Vector2(float(point[0]),float(point[1])),Vector2.ONE).grow(9.0)
		for id: String in index.candidates(floor_id,bounds):
			var number: int = int(id)
			if matched.has(number): continue
			var cell: Array = samples[number][0]
			if absf(float(cell[0])-float(point[0]))+absf(float(cell[1])-float(point[1]))<=8.0: matched[number] = true
	var ordered: Array = matched.keys()
	ordered.sort()
	var result: Array = []
	for number: int in ordered: result.append(samples[number])
	return result

func _add_dynamic_dependencies(world: WorldState, floor_id: int, bounds: Rect2, members: Array, actors: Dictionary, reservations: Dictionary) -> void:
	for id: String in space._actor_index.candidates(floor_id,bounds,members): actors[id] = true
	for region: Dictionary in space._reservation_regions(world,floor_id,bounds):
		var reservation: Dictionary = region.reservation
		reservations[region.reservation_id] = [region.reservation_id,reservation.get("actor_id",""),reservation.get("staff_ids",[]),reservation.get("regions",[])]

func facility_changed(before: Dictionary, after: Dictionary) -> void:
	if before.get("footprint")!=after.get("footprint") or before.get("patient_cell")!=after.get("patient_cell") or before.get("operator_cells")!=after.get("operator_cells") or before.get("repair_cell")!=after.get("repair_cell"):
		_geometry_fits.clear()
		_entry_geometry.clear()
	if before.get("footprint")!=after.get("footprint") or before.get("patient_cell")!=after.get("patient_cell"):
		invalidate()
	elif before.get("operator_cells")!=after.get("operator_cells") or before.get("repair_cell")!=after.get("repair_cell"):
		_wait_geometry = {}

func for_facility(world: WorldState, facility_id: String) -> Dictionary:
	_ensure(world)
	return _by_facility[facility_id].ref.duplicate(true) if _by_facility.has(facility_id) else {}

func _ensure(world: WorldState, requested_floor: int = 0) -> void:
	var current: bool = _world!=null and _world.get_ref()==world and _revision==world.geometry_revision
	if current and (requested_floor==0 or _derived_floors.has(requested_floor)): return
	var floors: Dictionary = {}
	if not current:
		_world = weakref(world)
		_revision = world.geometry_revision
		_regions.clear()
		_by_cell.clear()
		_by_facility.clear()
		_derived_floors.clear()
		_wait_geometry = {}
		_geometry_fits.clear()
		_entry_geometry.clear()
		# Empty purchased floor space is still a real place to stand. Completed
		# upper floors without overrides are materialized lazily on first use.
		for floor_key: String in world.facts.floors.overrides: floors[int(floor_key)] = true
		for room: Dictionary in world.facts.rooms.values(): floors[int(room.floor_id)] = true
		for facility: Dictionary in world.facts.facilities.values(): floors[int(facility.floor_id)] = true
	if requested_floor>0: floors[requested_floor] = true
	var layouts: Dictionary = {}
	for floor_id: int in floors:
		if _derived_floors.has(floor_id): continue
		var layout: Dictionary = HospitalSpace.floor_layout(world,floor_id)
		if not layout.plots.is_empty(): layouts[floor_id] = layout
	# The two consumers of a facility use the same current adaptation. These
	# views last only for this synchronous build, never across world changes.
	var rooms: Dictionary = {}
	for id: String in world.ids("rooms"):
		var room: Dictionary = world.facts.rooms[id]
		if layouts.has(int(room.floor_id)): rooms.get_or_add(int(room.floor_id),[]).append(room)
	var facilities: Dictionary = {}
	for id: String in world.ids("facilities"):
		var facility: Dictionary = world.facts.facilities[id]
		if not layouts.has(int(facility.floor_id)) or facility.get("stored",false): continue
		facilities.get_or_add(int(facility.floor_id),[]).append({"id":id,"layout":space.facility_layout(world,id),"blocks":space.content.facility_definition(facility.definition_id).get("blocks_movement",true)})
	for floor_id: int in floors:
		if not layouts.has(floor_id): continue
		_derived_floors[floor_id] = true
		_wait_geometry = {}
		var zones: Dictionary = {}
		for plot: Array in layouts[floor_id].plots:
			for y: int in range(int(plot[1])*32,(int(plot[1])+1)*32):
				for x: int in range(int(plot[0])*32,(int(plot[0])+1)*32): zones[Vector2i(x,y)] = ""
		for room: Dictionary in rooms.get(floor_id,[]):
			for cell: Array in BuildGeometry.cells(room): zones[Vector2i(int(cell[0]),int(cell[1]))] = str(room.id)
		var free: Dictionary = zones.duplicate()
		for cell: Array in layouts[floor_id].get("blocked",[]): free.erase(Vector2i(int(cell[0]),int(cell[1])))
		var blocking: Array = []
		for facility: Dictionary in facilities.get(floor_id,[]):
			if facility.blocks: blocking.append(facility.layout)
		for connector: Dictionary in world.facts.connectors.values():
			if HospitalTransit.has_stop(connector,floor_id) and not connector.get("stored",false): blocking.append(connector)
		for layout: Dictionary in blocking:
			for y: int in range(int(layout.cell[1]),int(layout.cell[1])+int(layout.footprint[1])):
				for x: int in range(int(layout.cell[0]),int(layout.cell[0])+int(layout.footprint[0])): free.erase(Vector2i(x,y))
		# Row-major IDs use the engine's integer sort while retaining the same
		# y/x anchors and the original per-component traversal order.
		var packed: PackedInt32Array = PackedInt32Array()
		packed.resize(free.size())
		var compact: bool = true
		var number: int = 0
		for point: Vector2i in free:
			if point.x<0 or point.y<0 or point.x>=ENTRY_GRID_WIDTH or point.y>=ENTRY_GRID_WIDTH:
				compact = false
				break
			packed[number] = point.y*ENTRY_GRID_WIDTH+point.x
			number += 1
		var ordered: Array = []
		if compact:
			packed.sort()
		else:
			# Keep the original ordering outside the bounded integer encoding.
			ordered = free.keys()
			ordered.sort_custom(func(a: Vector2i,b: Vector2i)->bool: return a.y<b.y or a.y==b.y and a.x<b.x)
		var seen: Dictionary = {}
		for index: int in free.size():
			var start: Vector2i = Vector2i(packed[index]%ENTRY_GRID_WIDTH,packed[index]/ENTRY_GRID_WIDTH) if compact else ordered[index]
			if seen.has(start): continue
			var cells: Dictionary = {start:true}
			var bounds: Rect2i = Rect2i(start,Vector2i.ONE)
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
					bounds = bounds.merge(Rect2i(next,Vector2i.ONE))
					pending.append(next)
			var geometry: String = JSON.stringify(pending,"",true,true).sha256_text()
			var region: Dictionary = {"ref":{"floor_id":floor_id,"room_id":zones[start],"anchor":[start.x,start.y]},"cells":cells,"facilities":[],"bounds":bounds,"geometry":geometry}
			_regions.append(region)
			for point: Vector2i in cells: _by_cell[_key(floor_id,point)] = region
		for facility: Dictionary in facilities.get(floor_id,[]):
			var layout: Dictionary = facility.layout
			var point: Vector2i = Vector2i(int(layout.patient_cell[0]),int(layout.patient_cell[1]))
			var region: Dictionary = _by_cell.get(_key(floor_id,point),{})
			if not region.is_empty():
				region.facilities.append(facility.id)
				_by_facility[facility.id] = region

static func _key(floor_id: int, point: Vector2i) -> String:
	return str(floor_id)+":"+str(point.x)+":"+str(point.y)

func region(world: WorldState, reference: Dictionary) -> Dictionary:
	_ensure(world,int(reference.get("floor_id",0)))
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

func current_area(world: WorldState, actor_id: String) -> Dictionary:
	var actor: Dictionary = world.facts.actors[actor_id]
	if actor.location.kind!="floor": return {}
	_ensure(world,int(actor.location.floor_id))
	var point: Vector2i = Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1]))
	return _by_cell.get(_key(int(actor.location.floor_id),point),{}).get("ref",{}).duplicate(true)

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
	# The caller may already own this unchanged, real-body enumeration. Its
	# actor index is reusable; this child still gets independent query views.
	space.begin_dynamic_route_query(world,not space.in_dynamic_route_query(world))
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
	var geometry: Dictionary = _entry_geometry_view(world,actor,area)
	var ordered: Dictionary = _entry_order(actor,origin,bounds,geometry,maximum_travel_ticks)
	var packed: PackedInt64Array = ordered.packed
	var fallback: Array = ordered.fallback
	var best: Dictionary = {}
	for index: int in (packed.size() if ordered.compact else fallback.size()):
		var lower: int
		var point: Vector2i
		if ordered.compact:
			var key: int = packed[index]
			var cell_id: int = key%ENTRY_CELL_COUNT
			lower = key/ENTRY_CELL_COUNT+int(ordered.get("offset_ticks",0))
			point = Vector2i(cell_id%ENTRY_GRID_WIDTH,cell_id/ENTRY_GRID_WIDTH)
		else:
			lower = int(fallback[index].lower)
			point = fallback[index].cell
		if lower>maximum_travel_ticks: break
		if not best.is_empty() and lower>int(best.travel_ticks): break
		var cell: Array = [point.x,point.y]
		if not safe_wait(world,actor_id,floor_id,cell,geometry): continue
		var route: Dictionary = space.travel_quote(world,actor_id,floor_id,cell)
		if not route.ok or not route.has("travel_ticks"): continue
		if int(route.travel_ticks)<=maximum_travel_ticks and (best.is_empty() or int(route.travel_ticks)<int(best.travel_ticks)): best = {"floor_id":floor_id,"cell":cell,"travel_ticks":int(route.travel_ticks)}
	return best

func _entry_order(actor: Dictionary, origin: Vector2, bounds: Dictionary, geometry: Dictionary, maximum_travel_ticks: int) -> Dictionary:
	var start: Vector2i = Vector2i(roundi(origin.x),roundi(origin.y))
	var speed: float = float(space.content.balance.movement_speeds[str(space.clearance(actor))])
	var prefix: int = ceili(origin.distance_to(Vector2(start))/speed/WorldState.TICK_SECONDS)
	var normalized: Dictionary = {"landings":[],"unknown":bool(bounds.unknown)}
	var basis: Array = ["walking",speed,start]
	if not bounds.unknown and not bounds.landings.is_empty():
		prefix = int(bounds.landings[0].ticks)
		for landing: Dictionary in bounds.landings: prefix = mini(prefix,int(landing.ticks))
		for landing: Dictionary in bounds.landings: normalized.landings.append({"cell":landing.cell,"ticks":int(landing.ticks)-prefix})
		basis = ["landings",speed,normalized.landings]
	var retained: Dictionary = geometry.get("ordering",{})
	var ordered: Dictionary
	if retained.get("basis",[])==basis:
		space.query_counts["entry_order_hits"] = int(space.query_counts.get("entry_order_hits",0))+1
		ordered = retained.ordered
	else:
		# Every candidate shares the fractional walking stub or minimum landing
		# arrival. Removing this additive prefix preserves lower/y/x ordering.
		# Keep the complete order: each caller applies its own travel budget.
		ordered = _ordered_entry_cells(actor,Vector2(start),normalized,geometry,HospitalTransit.MAX_TICK)
		space.query_counts["entry_order_builds"] = int(space.query_counts.get("entry_order_builds",0))+1
		if ordered.compact and geometry.has("ordering"):
			# One retained basis per static geometry; moving origins cannot grow
			# an unbounded cache. Geometry replacement discards its order too.
			geometry.ordering = {"basis":basis.duplicate(true),"ordered":ordered}
	var largest: int = int(ordered.packed[-1]/ENTRY_CELL_COUNT) if ordered.compact and not ordered.packed.is_empty() else 0
	if not ordered.compact or prefix<0 or prefix>ENTRY_SORT_LIMIT-largest:
		# Preserve the original exact int64 fallback, including mixed encodable
		# and very large values. No candidate or budget is approximated.
		space.query_counts["entry_order_fallbacks"] = int(space.query_counts.get("entry_order_fallbacks",0))+1
		return _ordered_entry_cells(actor,origin,bounds,geometry,maximum_travel_ticks)
	return {"packed":ordered.packed,"fallback":[],"compact":true,"offset_ticks":prefix}

func _ordered_entry_cells(actor: Dictionary, origin: Vector2, bounds: Dictionary, geometry: Dictionary, maximum_travel_ticks: int) -> Dictionary:
	var start: Vector2i = Vector2i(roundi(origin.x),roundi(origin.y))
	var speed: float = float(space.content.balance.movement_speeds[str(space.clearance(actor))])
	var stub_ticks: int = ceili(origin.distance_to(Vector2(start))/speed/WorldState.TICK_SECONDS)
	var walking: PackedInt64Array = PackedInt64Array()
	walking.resize((ENTRY_GRID_WIDTH-1)*2+1)
	for distance: int in walking.size():
		# Retain walking_ticks' division order and separate fractional-stub ceil.
		walking[distance] = ceili(float(distance)/speed/WorldState.TICK_SECONDS)
	var landing_cells: Array[Vector2i] = []
	var landing_ticks: PackedInt64Array = PackedInt64Array()
	if not bounds.unknown:
		for landing: Dictionary in bounds.landings:
			landing_cells.append(Vector2i(int(landing.cell.x),int(landing.cell.y)))
			landing_ticks.append(int(landing.ticks))
	var packed: PackedInt64Array = PackedInt64Array()
	packed.resize(geometry.cells.size())
	var count: int = 0
	var fallback: Array = []
	var compact: bool = true
	for point: Vector2i in geometry.cells:
		if geometry.points.get(Vector2(point),true)==false: continue
		var lower: int = HospitalTransit.MAX_TICK
		if landing_cells.is_empty():
			var distance: int = absi(start.x-point.x)+absi(start.y-point.y)
			lower = stub_ticks+(walking[distance] if distance<walking.size() else ceili(float(distance)/speed/WorldState.TICK_SECONDS))
		else:
			for index: int in landing_cells.size():
				var landing: Vector2i = landing_cells[index]
				var distance: int = absi(landing.x-point.x)+absi(landing.y-point.y)
				var travel: int = walking[distance] if distance<walking.size() else ceili(float(distance)/speed/WorldState.TICK_SECONDS)
				lower = mini(lower,landing_ticks[index]+travel)
		if lower>maximum_travel_ticks: continue
		if compact and lower>=0 and lower<=ENTRY_SORT_LIMIT and point.x>=0 and point.x<ENTRY_GRID_WIDTH and point.y>=0 and point.y<ENTRY_GRID_WIDTH:
			# The native numeric sort has the original lower/y/x total order.
			packed[count] = lower*ENTRY_CELL_COUNT+point.y*ENTRY_GRID_WIDTH+point.x
			count += 1
		else:
			if compact:
				# Very large legal times retain all candidates and the exact order.
				for index: int in count:
					var key: int = packed[index]
					var cell_id: int = key%ENTRY_CELL_COUNT
					fallback.append({"cell":Vector2i(cell_id%ENTRY_GRID_WIDTH,cell_id/ENTRY_GRID_WIDTH),"lower":key/ENTRY_CELL_COUNT})
				compact = false
			fallback.append({"cell":point,"lower":lower})
	if compact:
		packed.resize(count)
		packed.sort()
	else:
		packed.clear()
		fallback.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
			if a.lower!=b.lower: return a.lower<b.lower
			return a.cell.y<b.cell.y or a.cell.y==b.cell.y and a.cell.x<b.cell.x)
	return {"packed":packed,"fallback":fallback,"compact":compact}

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

func safe_wait(world: WorldState, actor_id: String, floor_id: int, cell: Array, geometry: Dictionary = {}) -> bool:
	_ensure(world,floor_id)
	var actor: Dictionary = world.facts.actors[actor_id]
	var point: Vector2i = Vector2i(roundi(cell[0]),roundi(cell[1]))
	var origin: Vector2 = Vector2(float(cell[0]),float(cell[1]))
	if geometry.is_empty():
		var area: Dictionary = _by_cell.get(_key(floor_id,point),{})
		if area.is_empty(): return false
		geometry = _entry_geometry_view(world,actor,area)
	if not geometry.points.has(origin): geometry.points[origin] = _safe_wait_geometry(world,actor,floor_id,origin,geometry.geometry)
	if not geometry.points[origin]: return false
	var current: Dictionary = space.read_view(world,"public_wait_clearance:"+actor_id+":"+str(floor_id),func()->Dictionary:
		return {"query":RouteClearance.new(space,world,actor,floor_id,[],{},true,space._navigation.floor_source(space,world,floor_id),geometry.geometry)})
	if not (current.query as RouteClearance).reservation_reason(point).is_empty(): return false
	return space._dynamic_clear(world,actor_id,floor_id,space._actor_rect(actor,origin))

func _safe_wait_geometry(world: WorldState, actor: Dictionary, floor_id: int, origin: Vector2, geometry: RouteClearance) -> bool:
	if not geometry.reason(Vector2i(roundi(origin.x),roundi(origin.y))).is_empty(): return false
	var bounds: Rect2 = space._actor_rect(actor,origin)
	var constraints: Dictionary = _wait_constraints(world)
	for door: Dictionary in constraints.doors.get(floor_id,[]):
		var span: int = int(world.facts.adaptations.get(door.id,{}).get("span",door.span))
		if bounds.intersects(space._door_rect(door,span).grow(1.0),false): return false
	for x: int in range(floori(bounds.position.x/8.0),floori(bounds.end.x/8.0)+1):
		for y: int in range(floori(bounds.position.y/8.0),floori(bounds.end.y/8.0)+1):
			for work: Vector2 in constraints.points.get(floor_id,{}).get(Vector2i(x,y),[]):
				if bounds.intersects(Rect2(work,Vector2.ONE),false): return false
	return true

func _entry_geometry_view(world: WorldState, actor: Dictionary, area: Dictionary) -> Dictionary:
	var floor_id: int = int(area.ref.floor_id)
	var rectangle: Rect2 = space._actor_rect(actor,Vector2.ZERO)
	var spans: Array = []
	for door: Dictionary in _wait_constraints(world).doors.get(floor_id,[]): spans.append([door.id,world.facts.adaptations.get(door.id,{}).get("span",door.span)])
	var key: String = JSON.stringify([area.ref,space.body(actor),actor.get("posture","standing"),rectangle.position,rectangle.size,spans],"",true,true)
	var version: int = space._navigation.floor_static_version(space,world,floor_id)
	var saved: Dictionary = _entry_geometry.get(key,{})
	if saved.is_empty() or int(saved.version)!=version:
		saved = {"version":version,"cells":area.cells.keys(),"points":{},"geometry":space.navigation.structural_clearance(world,actor,floor_id),"ordering":{}}
		_entry_geometry[key] = saved
	return saved

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
		for floor_id: int in HospitalTransit.routing_stops(connection,world,1,1,_derived_floors.duplicate()):
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

func _queue_members(world: WorldState) -> Dictionary:
	var result: Dictionary = {"areas":{},"targets":{},"facilities":{}}
	var order: int = 0
	for other: Dictionary in intents(world):
		var row: Dictionary = {"intent":other,"order":order}
		order += 1
		if int(other.get("arrived_tick",-1))<0 or not other.get("phase","") in ["local_wait","local_travel","manual_wait"]: continue
		var purpose: String = str(other.get("public_purpose",""))
		var target: String = str(other.get("manual_facility_id","")) if other.get("mode","auto")=="manual" else str(other.get("facility_id","")) if other.phase=="local_travel" else ""
		if target.is_empty() and (other.get("mode","auto")=="manual" or other.phase=="local_travel"): continue
		if not target.is_empty():
			if other.get("mode","auto")!="manual" and not target in region(world,other.get("area",{})).get("facilities",[]): continue
			result.targets.get_or_add(JSON.stringify([purpose,target]),[]).append(row)
		else:
			var area: Dictionary = region(world,other.get("area",{}))
			if area.is_empty(): continue
			result.areas.get_or_add(JSON.stringify([purpose,area.ref],"",true,true),[]).append(row)
	return result

func _facility_queue(world: WorldState, purpose: String, facility_id: String) -> Array:
	var view: Dictionary = space.read_view(world,"public_queue_members",_queue_members.bind(world))
	var key: String = JSON.stringify([purpose,facility_id])
	if not view.facilities.has(key):
		var rows: Array = view.targets.get(key,[]).duplicate()
		var area: Dictionary = for_facility(world,facility_id)
		rows.append_array(view.areas.get(JSON.stringify([purpose,area],"",true,true),[]))
		rows.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return int(a.order)<int(b.order))
		view.facilities[key] = rows
	return view.facilities[key]

func turn(world: WorldState, intent: Dictionary, facility_id: String) -> bool:
	for row: Dictionary in _facility_queue(world,str(intent.public_purpose),facility_id):
		var other: Dictionary = row.intent
		if is_same(other,intent): continue
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
	var departing: Array = []
	for actor_id: String in [current.actor_id]+current.staff_ids:
		if actor_id in ids: continue
		departing.append(actor_id)
		facts.actors[actor_id] = world.facts.actors[actor_id].duplicate()
		facts.actors[actor_id].location = {"kind":"outside"}
	var candidate: WorldState = WorldState.new(facts)
	space.prepare_projection(world,candidate,[facility_id])
	space.begin_actor_exclusion_query(world,candidate,departing)
	var quote: Dictionary = space.facility_quote(candidate,facility_id,ids[0],ids.slice(1))
	space.end_route_query()
	return quote
