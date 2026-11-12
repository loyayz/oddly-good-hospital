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
var _facility_areas: HospitalFacilityAreaIndex = HospitalFacilityAreaIndex.new()
var _regions_by_definition: Dictionary = {}
var _by_facility: Dictionary = {}
var _derived_floors: Dictionary = {}
var _floor_regions: Dictionary = {}
var _wait_geometry: Dictionary = {}
var _geometry_fits: Dictionary = {}
var _entry_geometry: Dictionary = {}
var _decision_world: WeakRef
var _decision_tick: int = -1
var _decision_basis: Dictionary = {}
var _wait_results: Dictionary = {}
var _wait_dependencies: RefCounted = preload("res://game/life/waiting_dependencies.gd").new()
var _wait_observations: Array[WorldState] = []
var _decision_facts: Dictionary = {}
var _decision_generation: int = 0
var _wait_refreshed: int = -1
var _queue_fit_world: WeakRef
var _queue_fit_revision: int = -1
var _queue_fit_facilities: Dictionary = {}
var _queue_fit_facility_count: int = -1
var _queue_fits: Dictionary = {}

func _init(geometry: HospitalSpace) -> void:
	_space = weakref(geometry)

func invalidate() -> void:
	_revision = -1
	_decision_tick = -1
	_facility_areas.invalidate()

func changed(world: WorldState) -> void:
	if _decision_world!=null and _decision_world.get_ref()==world: _decision_tick = -1

func begin_wait_observation(world: WorldState) -> void:
	_wait_observations.append(world)
	changed(world)

func end_wait_observation() -> void:
	var world: WorldState = _wait_observations.pop_back()
	if _decision_world==null or _decision_world.get_ref()!=world or _wait_results.is_empty(): return
	var active: Dictionary = {}
	for intent: Dictionary in _intent_view(world).items: active[str(intent.id)] = true
	_prune_waiters(active)

func _prune_waiters(active: Dictionary) -> void:
	for id: String in _wait_results.keys():
		if active.has(id): continue
		_wait_results.erase(id)
		_wait_dependencies.remove(id)

func actor_changed(world: WorldState, id: String, old_floor: int, old_rect: Rect2, floor_id: int, rect: Rect2) -> void:
	if _decision_world==null or _decision_world.get_ref()!=world: return
	_wait_dependencies.mark("actor:"+id)
	_wait_dependencies.actor_changed(id,old_floor,old_rect,floor_id,rect)
	changed(world)

func reservation_changed(world: WorldState, id: String) -> void:
	if _decision_world==null or _decision_world.get_ref()!=world: return
	_wait_dependencies.reservation_changed(id,world.facts.adaptations.get(id,{}))
	changed(world)

func _wait_request(intent: Dictionary, definitions: Array, members: Array, extra: Dictionary) -> Array:
	return [intent.actor_id,intent.get("area",{}),intent.public_purpose,definitions,members,extra,intent.get("mode","auto"),intent.get("manual_facility_id",""),intent.get("arrived_tick",-1),intent.get("started_tick",-1),intent.has("ticket_id")]

func _observe_wait_dependencies(world: WorldState) -> Dictionary:
	var sealed: bool = not _wait_observations.is_empty() and _wait_observations.back()==world
	# Raw calculation callers may edit facts without an owner notification.
	# Their observations remain complete; production dispatch shares one view.
	if not sealed:
		changed(world)
		space._indexed_revision = -1
	var view: Dictionary = _decision_view(world)
	if _wait_refreshed==int(view.generation): return view
	if not _wait_dependencies.waiters.is_empty():
		space._ensure_actor_index(world)
		_wait_dependencies.observe_actors(space._actor_index)
		_wait_dependencies.observe_reservations(world.facts.adaptations)
	var changes: int = _wait_dependencies.refresh(_wait_dependency_value.bind(world,view))
	space.query_counts["public_wait_dependency_observations"] = int(space.query_counts.get("public_wait_dependency_observations",0))+1
	space.query_counts["public_wait_dependency_resources"] = int(space.query_counts.get("public_wait_dependency_resources",0))+_wait_dependencies.resources.size()
	space.query_counts["public_wait_dependency_changes"] = int(space.query_counts.get("public_wait_dependency_changes",0))+changes
	_wait_refreshed = int(view.generation)
	return view

func area_valid(world: WorldState, reference: Dictionary, room_kinds: Array) -> bool:
	if region(world,reference).is_empty(): return false
	var room: Dictionary = world.facts.rooms.get(reference.get("room_id",""),{})
	return "" in room_kinds if room.is_empty() else str(room.get("kind",room.get("type",""))) in room_kinds and not HospitalRemodel.blocked(world,str(room.id))

func should_recheck(world: WorldState, intent: Dictionary, definitions: Array, members: Array = [], extra: Dictionary = {}) -> bool:
	_observe_wait_dependencies(world)
	var saved: Dictionary = _wait_results.get(str(intent.id),{})
	if saved.is_empty():
		# A first attempt has no negative result to compare. Only a subsequent
		# failed selection records the complete current dependency signature.
		space.query_counts["public_wait_initial_rechecks"] = int(space.query_counts.get("public_wait_initial_rechecks",0))+1
		space.query_counts["public_wait_rechecks"] = int(space.query_counts.get("public_wait_rechecks",0))+1
		return true
	var dirty: bool = saved.request!=_wait_request(intent,definitions,members,extra) or _wait_dependencies.dirty(str(intent.id))
	if dirty: space.query_counts["public_wait_dirty_rechecks"] = int(space.query_counts.get("public_wait_dirty_rechecks",0))+1
	var repeat: bool = not dirty
	var counter: String = "public_wait_hits" if repeat else "public_wait_rechecks"
	space.query_counts[counter] = int(space.query_counts.get(counter,0))+1
	return not repeat

func remember_wait(world: WorldState, intent: Dictionary, definitions: Array, members: Array = [], extra: Dictionary = {}) -> void:
	_observe_wait_dependencies(world)
	var ids: Array = [str(intent.actor_id)] if members.is_empty() else members
	var floors: Array = space.navigation.observed_floors(world,ids)
	var local: int = int(intent.get("area",{}).get("floor_id",0))
	if local>0 and not local in floors:
		floors.append(local)
		floors.sort()
	# Keep one proof per shared resource. Individual unchanged waiters retain
	# only their request and reverse subscriptions, not another full signature.
	var observed: Dictionary = {"resources":{},"bounds":[]}
	_capture_wait_signature(world,intent,definitions,members,extra,floors,observed,false)
	space.query_counts["public_wait_dependency_captures"] = int(space.query_counts.get("public_wait_dependency_captures",0))+1
	if _wait_dependencies.waiters.is_empty():
		_wait_dependencies.observe_actors(space._actor_index)
		_wait_dependencies.observe_reservations(world.facts.adaptations)
	_wait_dependencies.remember(str(intent.id),observed.resources,int(intent.get("area",{}).get("floor_id",0)),observed.bounds)
	_wait_results[str(intent.id)] = {"request":_wait_request(intent,definitions,members,extra).duplicate(true)}

# One shared observation of actual ownership per changed dispatch boundary.
# Rows refer to original intents: phase changes are read from their sole owner.
func _decision_view(world: WorldState) -> Dictionary:
	if _decision_world==null or _decision_world.get_ref()!=world or not is_same(_decision_facts,world.facts):
		_decision_world = weakref(world)
		_decision_facts = world.facts
		_decision_tick = -1
		_decision_basis = {}
		_wait_results.clear()
		_wait_dependencies.clear()
		_wait_refreshed = -1
	var facility_environment: Dictionary = _facility_environment(world)
	if _decision_tick==world.sim_tick and _decision_basis.get("geometry_revision",-1)==world.geometry_revision and is_same(_decision_basis.get("facility_environment",{}),facility_environment): return _decision_basis
	_decision_tick = world.sim_tick
	var users: Dictionary = {}
	for actor: Dictionary in world.facts.actors.values():
		var id: String = str(actor.get("support_facility_id",""))
		if not id.is_empty(): users.get_or_add(id,[]).append(actor.id)
	var queues: Dictionary = {}
	var active: Dictionary = {}
	var intent_view: Dictionary = _intent_view(world)
	for intent: Dictionary in intent_view.items:
		active[str(intent.id)] = true
		var purpose: String = str(intent.get("public_purpose",""))
		var key: String = JSON.stringify([purpose,intent.get("area",{})],"",true,true)
		queues.get_or_add(key,[]).append(intent)
		if intent.get("phase","") in ["using","seated","returning"]:
			var id: String = str(intent.get("facility_id",""))
			if not id.is_empty(): users.get_or_add(id,[]).append(str(intent.get("actor_id","")))
	_prune_waiters(active)
	var environment: Dictionary = {}
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
	_decision_generation += 1
	_decision_basis = {"users":users,"queues":queues,"visitor_seats":intent_view.visitor_seats,"environment":environment,"environment_indices":{},"environment_matches":{},"facility_environment":facility_environment,"geometry_revision":world.geometry_revision,"generation":_decision_generation}
	return _decision_basis

func _facility_environment(world: WorldState) -> Dictionary:
	var records: Dictionary = world.facts.facilities
	var retained: Dictionary = _decision_basis.get("facility_environment",{})
	if not retained.is_empty() and int(retained.geometry_revision)==world.geometry_revision and is_same(retained.records,records) and int(retained.count)==records.size():
		space.query_counts["facility_environment_hits"] = int(space.query_counts.get("facility_environment_hits",0))+1
		return retained
	# Layout owners invalidate geometry when a facility moves. Only frozen
	# origins and identities persist; selected values are read from facts below.
	var rows: Dictionary = {}
	for facility: Dictionary in records.values():
		rows.get_or_add(int(facility.floor_id),[]).append([facility.cell.duplicate(),"facility",str(facility.id)])
	space.query_counts["facility_environment_builds"] = int(space.query_counts.get("facility_environment_builds",0))+1
	return {"records":records,"count":records.size(),"geometry_revision":world.geometry_revision,"rows":rows,"indices":{}}

func _decision_signature(world: WorldState, intent: Dictionary, definitions: Array, members: Array, extra: Dictionary, route_floors: Array = []) -> Array:
	return _capture_wait_signature(world,intent,definitions,members,extra,route_floors,{})

func _capture_wait_signature(world: WorldState, intent: Dictionary, definitions: Array, members: Array, extra: Dictionary, route_floors: Array, observed: Dictionary, collect_signature: bool = true) -> Array:
	# Dependency subscriptions do not consume the legacy diagnostic signature.
	# Keep its ordered output available without building a second set of body
	# and queue records during production negative-result capture.
	var view: Dictionary = _decision_view(world)
	var ids: Array = [str(intent.actor_id)] if members.is_empty() else members
	var bodies: Array = []
	for id: String in ids:
		var actor: Dictionary = world.facts.actors[id]
		if collect_signature: bodies.append([id,space.body(actor),actor.location,actor.get("posture","standing"),actor.get("facing",0.0)])
		_watch_wait(observed,"actor",id,_wait_actor_value(world,id))
	var reference: Dictionary = intent.get("area",{})
	var room: Dictionary = world.facts.rooms.get(reference.get("room_id",""),{})
	var records: Array = [reference,room.get("kind",room.get("type","")),room.get("origin",[]),room.get("size",[]),room.get("wall_edges",[]),definitions,bodies,extra,intent.get("mode","auto"),intent.get("manual_facility_id",""),intent.get("arrived_tick",-1),intent.get("started_tick",-1),intent.has("ticket_id"),"R15" in world.facts.research] if collect_signature else []
	if collect_signature: records.append(space.navigation.connection_basis(world))
	_watch_wait(observed,"control","",[space.navigation.connection_basis(world),"R15" in world.facts.research])
	var points: Array = []
	var observed_points: Dictionary = {}
	var other_ids: Dictionary = {}
	var reservations: Dictionary = {}
	space._ensure_actor_index(world)
	var area: Dictionary = region(world,reference)
	if collect_signature: records.append(area.get("geometry",""))
	_watch_wait(observed,"area",JSON.stringify(reference,"",true,true),_wait_area_value(world,reference),{"area":reference})
	var route_dependent: bool = intent.public_purpose=="rest" or definitions.is_empty()
	for number: int in _facility_members(area,definitions):
		var facility_id: String = str(area.facilities[number])
		var facility: Dictionary = world.facts.facilities[facility_id]
		var users: Array = view.users.get(facility_id,[])
		var reservation: Dictionary = world.facts.get("staff_life",{}).get("reservations",{}).get(facility_id,{})
		var adaptation: Dictionary = world.facts.adaptations.get(facility_id,{})
		var facility_basis: Array = _wait_facility_value(world,view,facility_id)
		if collect_signature: records.append(facility_basis)
		_watch_wait(observed,"facility",facility_id,facility_basis+[view.visitor_seats.has(facility_id)])
		var occupied: bool = false
		for owner: String in users:
			if not owner in ids: occupied = true
		# A patient can still ask a seated visitor to yield. Its vacancy preview
		# reads other real bodies and routes even while the seat remains occupied.
		var visitor_preview: bool = intent.public_purpose=="seat" and intent.has("ticket_id") and view.visitor_seats.has(facility_id) and (intent.get("mode","auto")!="manual" or intent.get("manual_facility_id","")==facility_id)
		if not visitor_preview and (occupied or not reservation.is_empty() or not adaptation.is_empty() and not str(adaptation.get("actor_id","")) in ids): continue
		route_dependent = true
		# Observe only the work places consumed here, with the same adaptation
		# overrides as facility_layout; the remaining facility state is above.
		var layout: Dictionary=space.facility_layout(world,facility_id)
		var patient_cell: Array = layout.patient_cell
		var operator_cells: Array = layout.get("operator_cells",[])
		var repair_cell: Array = layout.get("repair_cell",patient_cell)
		for point: Array in [patient_cell]+operator_cells+[repair_cell]:
			# This synchronous observation consumes a set union around identical
			# points. Patient/repair/operator aliases do not create new facts.
			if observed_points.has(point): continue
			observed_points[point] = true
			points.append(point)
	var reach: float = maxf(6.0,float(space.clearance(world.facts.actors[ids[0]]))+1.0)
	var bounds: Array[Rect2] = []
	for point: Array in points:
		bounds.append(Rect2(Vector2(float(point[0]),float(point[1])),Vector2.ONE).grow(reach))
	if (intent.public_purpose=="rest" or definitions.is_empty()) and not area.is_empty():
		# Tea is a real free standing place, including a region with no chairs.
		# Its availability can change when any body/reservation leaves that area.
		bounds.append(Rect2(area.bounds).grow(float(space.clearance(world.facts.actors[ids[0]]))+1.0))
	if not observed.is_empty(): observed.bounds = bounds
	if not bounds.is_empty(): _add_dynamic_dependencies(world,int(reference.floor_id),bounds,ids,other_ids,reservations)
	if route_dependent:
		# A failed route may recover through a remote floor. Retain the exact
		# static sources actually searched, plus newly declared routing stops.
		var versions: Array = []
		for floor_id: int in route_floors:
			var version: String = space._navigation.floor_static_version(space,world,floor_id)
			if collect_signature: versions.append([floor_id,version])
			_watch_wait(observed,"floor",str(floor_id),[version])
		if collect_signature: records.append([versions,space.navigation.routing_floor_basis(world)])
		_watch_wait(observed,"routing","",[space.navigation.routing_floor_basis(world)])
	# Queue eligibility cannot make an occupied seat available. Its owners,
	# reservations and adaptations are already observed above; their release
	# restores the complete queue dependencies on this same dispatch boundary.
	# A patient's visitor-yield preview sets route_dependent even while occupied.
	var queue: Array = []
	if route_dependent or intent.public_purpose!="seat":
		queue = view.queues.get(JSON.stringify([intent.public_purpose,reference],"",true,true),[])
		_watch_wait(observed,"queue",JSON.stringify([intent.public_purpose,reference],"",true,true),_wait_queue_value(world,queue),{"purpose":intent.public_purpose,"area":reference})
	if collect_signature:
		for other: Dictionary in queue:
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
		if collect_signature: records.append([id,other.location,space.body(other),other.get("posture","standing"),other.get("facing",0.0),world.facts.moves.has(id),world.facts.get("relationships",{}).get(":".join(pair),{})])
		_watch_wait(observed,"actor",id,_wait_actor_value(world,id))
		_watch_wait(observed,"relationship",":".join(pair),[world.facts.get("relationships",{}).get(":".join(pair),{})])
	var reservation_ids: Array = reservations.keys()
	reservation_ids.sort()
	for id: String in reservation_ids:
		if collect_signature: records.append(reservations[id])
		_watch_wait(observed,"reservation",id,reservations[id])
	var samples: Array = _environment_samples(view,int(reference.get("floor_id",-1)),points)
	if collect_signature: records.append_array(samples)
	_watch_wait(observed,"environment",JSON.stringify([reference.get("floor_id",-1),points]),samples,{"floor":int(reference.get("floor_id",-1)),"points":points})
	return records

func _watch_wait(observed: Dictionary, kind: String, id: String, value: Array, context: Dictionary = {}) -> void:
	if observed.is_empty(): return
	var source: Dictionary = context.duplicate()
	source.kind = kind
	source.id = id
	source.value = value
	observed.resources[kind+":"+id] = source

func _wait_actor_value(world: WorldState, id: String) -> Array:
	var actor: Dictionary = world.facts.actors.get(id,{})
	if actor.is_empty(): return []
	return [id,space.body(actor),actor.location,actor.get("posture","standing"),actor.get("facing",0.0),world.facts.moves.has(id)]

func _wait_area_value(world: WorldState, reference: Dictionary) -> Array:
	var room: Dictionary = world.facts.rooms.get(reference.get("room_id",""),{})
	var area: Dictionary = region(world,reference)
	return [room.get("kind",room.get("type","")),room.get("origin",[]),room.get("size",[]),room.get("wall_edges",[]),area.get("geometry",""),area.get("facilities",[])]

func _wait_facility_value(world: WorldState, view: Dictionary, id: String) -> Array:
	var facility: Dictionary = world.facts.facilities.get(id,{})
	if facility.is_empty(): return []
	var reservation: Dictionary = world.facts.get("staff_life",{}).get("reservations",{}).get(id,{})
	var adaptation: Dictionary = world.facts.adaptations.get(id,{})
	var layout: Dictionary=space.facility_layout(world,id)
	return [id,facility.definition_id,facility.cell,layout.footprint,facility.get("rotation",0),layout.get("patient_cell",[]),layout.get("operator_cells",[]),layout.get("repair_cell",[]),layout.get("operator_clearances",[]),facility.get("failed",false),HospitalRemodel.blocked(world,id),view.users.get(id,[]),reservation.get("id",""),reservation.get("staff_ids",[]),adaptation.get("actor_id",""),adaptation.get("staff_ids",[]),adaptation.get("regions",[])]

func _wait_queue_value(world: WorldState, queue: Array) -> Array:
	var result: Array = []
	for intent: Dictionary in queue:
		if int(intent.get("arrived_tick",-1))<0 or not intent.get("phase","") in ["local_wait","local_travel","manual_wait"]: continue
		var bodies: Array = []
		for id: String in intent.get("staff_ids",[str(intent.actor_id)]):
			if not world.facts.actors.has(id): continue
			var actor: Dictionary = world.facts.actors[id]
			bodies.append([id,space.body(actor),actor.get("posture","standing"),actor.get("facing",0.0)])
		result.append([intent.id,intent.arrived_tick,intent.phase,intent.get("facility_id",""),intent.get("mode","auto"),intent.get("manual_facility_id",""),bodies])
	return result

func _wait_dependency_value(source: Dictionary, world: WorldState, view: Dictionary) -> Array:
	match str(source.kind):
		"actor": return _wait_actor_value(world,str(source.id))
		"area": return _wait_area_value(world,source.area)
		"facility": return _wait_facility_value(world,view,str(source.id))+[view.visitor_seats.has(source.id)]
		"queue": return _wait_queue_value(world,view.queues.get(source.id,[]))
		"control": return [space.navigation.connection_basis(world),"R15" in world.facts.research]
		"routing": return [space.navigation.routing_floor_basis(world)]
		"floor": return [space._navigation.floor_static_version(space,world,int(source.id))]
		"relationship": return [world.facts.get("relationships",{}).get(source.id,{})]
		"environment": return _environment_samples(view,int(source.floor),source.points)
		"reservation":
			var reservation: Dictionary = world.facts.adaptations.get(source.id,{})
			return [] if reservation.is_empty() else [source.id,reservation.get("actor_id",""),reservation.get("staff_ids",[]),reservation.get("regions",[])]
	return []

func _environment_samples(view: Dictionary, floor_id: int, points: Array) -> Array:
	var result: Array = []
	var matched: Dictionary = _environment_matches(view,floor_id,points)
	var facilities: Dictionary = view.get("facility_environment",{})
	if not facilities.is_empty():
		var rows: Array = facilities.rows.get(floor_id,[])
		for number: int in matched.facilities:
			var row: Array = rows[number]
			var facility: Dictionary = facilities.records[row[2]]
			result.append([row[0],"facility",[facility.id,facility.definition_id,facility.get("level",1),facility.get("failed",false)]])
	var samples: Array = view.environment.get(floor_id,[])
	for number: int in matched.samples: result.append(samples[number])
	return result

func _environment_matches(view: Dictionary, floor_id: int, points: Array) -> Dictionary:
	if points.is_empty(): return {"facilities":[],"samples":[]}
	var matches: Dictionary = view.get_or_add("environment_matches",{})
	var recent: Array = matches.get_or_add(floor_id,[])
	for number: int in recent.size():
		var retained: Dictionary = recent[number]
		if retained.points!=points: continue
		recent.remove_at(number)
		recent.push_front(retained)
		space.query_counts["public_wait_environment_match_hits"] = int(space.query_counts.get("public_wait_environment_match_hits",0))+1
		return retained
	var facilities: Dictionary = view.get("facility_environment",{})
	var matched: Dictionary = {"points":points.duplicate(true),"facilities":[],"samples":[]}
	if not facilities.is_empty(): matched.facilities = _environment_sample_indices(facilities.rows.get(floor_id,[]),facilities.indices,floor_id,points)
	matched.samples = _environment_sample_indices(view.environment.get(floor_id,[]),view.environment_indices,floor_id,points)
	# Only recent full point sets in this closed observation share the ordered
	# index union. Current facility values and actor dependencies remain live.
	recent.push_front(matched)
	if recent.size()>2: recent.pop_back()
	space.query_counts["public_wait_environment_match_builds"] = int(space.query_counts.get("public_wait_environment_match_builds",0))+1
	return matched

func _environment_sample_indices(samples: Array, indices: Dictionary, floor_id: int, points: Array) -> Array:
	if points.is_empty() or samples.is_empty(): return []
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
	return ordered

func _add_dynamic_dependencies(world: WorldState, floor_id: int, bounds: Array[Rect2], members: Array, actors: Dictionary, reservations: Dictionary) -> void:
	if bounds.is_empty(): return
	for id: String in space._actor_index.candidates_in_regions(floor_id,bounds,members): actors[id] = true
	for region: Dictionary in space._reservation_regions_many(world,floor_id,bounds):
		if reservations.has(region.reservation_id): continue
		var reservation: Dictionary = region.reservation
		reservations[region.reservation_id] = [region.reservation_id,reservation.get("actor_id",""),reservation.get("staff_ids",[]),reservation.get("regions",[])]
	space.query_counts["public_wait_dependency_batches"] = int(space.query_counts.get("public_wait_dependency_batches",0))+1
	space.query_counts["public_wait_dependency_rectangles"] = int(space.query_counts.get("public_wait_dependency_rectangles",0))+bounds.size()

func facility_changed(before: Dictionary, after: Dictionary) -> void:
	var posts_changed: bool=before.get("operator_cells")!=after.get("operator_cells") or before.get("operator_clearances")!=after.get("operator_clearances")
	if before.get("footprint")!=after.get("footprint") or before.get("patient_cell")!=after.get("patient_cell") or posts_changed or before.get("repair_cell")!=after.get("repair_cell"):
		_geometry_fits.clear()
		_entry_geometry.clear()
	if posts_changed:
		_wait_results.clear()
		_wait_dependencies.clear()
		_decision_tick=-1
	if before.get("footprint")!=after.get("footprint") or before.get("patient_cell")!=after.get("patient_cell"):
		invalidate()
	if posts_changed or before.get("repair_cell")!=after.get("repair_cell"):
		_wait_geometry = {}

func for_facility(world: WorldState, facility_id: String) -> Dictionary:
	_ensure(world)
	return _by_facility[facility_id].ref.duplicate(true) if _by_facility.has(facility_id) else {}

func _ensure(world: WorldState, _requested_floor: int = 0) -> void:
	if not _facility_areas.refresh(world,space): return
	_world=weakref(world)
	_revision=world.geometry_revision
	_regions=_facility_areas.regions
	_by_facility=_facility_areas.by_facility
	_regions_by_definition.clear(); _derived_floors.clear(); _floor_regions.clear()
	for floor_id: int in _facility_areas.by_floor:
		_derived_floors[floor_id]=true
		_floor_regions[floor_id]={"by_cell":{}}
		for point: Vector2i in _facility_areas.by_floor[floor_id]:
			_floor_regions[floor_id].by_cell[point]=_facility_areas.by_floor[floor_id][point][0]
	for number: int in _regions.size():
		for definition: String in _regions[number].facility_definitions:
			_regions_by_definition.get_or_add(definition,[]).append(number)
	_wait_geometry.clear(); _geometry_fits.clear(); _entry_geometry.clear()

func public_point(world: WorldState, floor_id: int, point: Vector2i) -> bool:
	_ensure(world,floor_id)
	return _facility_areas.public_point(world,floor_id,point)

func floor_waiting_point(world: WorldState, actor_id: String) -> Dictionary:
	var actor: Dictionary=world.facts.actors[actor_id]
	if actor.location.kind!="floor": return {}
	var floor_id: int=int(actor.location.floor_id)
	var origin: Vector2=Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	# Complete owned public floor, nearest first. The original full body,
	# standing constraints and route proof apply to every candidate.
	var points: Array[Vector2i]=[]
	for plot: Array in HospitalSpace.floor_plots(world,floor_id):
		for y: int in range(int(plot[1])*32,(int(plot[1])+1)*32):
			for x: int in range(int(plot[0])*32,(int(plot[0])+1)*32):
				var point: Vector2i=Vector2i(x,y)
				if space.room_use.public_point(world,floor_id,point): points.append(point)
	_sort_floor_waiting_points(points,origin)
	for point: Vector2i in points:
		var cell: Array=[point.x,point.y]
		if safe_wait(world,actor_id,floor_id,cell) and space.can_reach(world,actor_id,floor_id,cell):
			return {"floor_id":floor_id,"cell":cell}
	return {}

# Complete public candidates have exact integer coordinates in 0..95.
# Keep the original Vector2 distance precision and literal y/x tie order.
func _sort_floor_waiting_points(points: Array, origin: Vector2) -> void:
	var decorated: Array[Vector3]=[]
	for point: Vector2i in points:
		var distance: float=origin.distance_squared_to(Vector2(point))
		decorated.append(Vector3(distance,point.y,point.x))
	decorated.sort()
	for i: int in decorated.size():
		points[i]=Vector2i(int(decorated[i].z),int(decorated[i].y))
	# Release temporary ordering keys before live safety/reachability checks.
	decorated.clear()

func room_exit_point(world: WorldState, actor_id: String) -> Dictionary:
	var actor: Dictionary=world.facts.actors[actor_id]
	if actor.location.kind!="floor": return {}
	var floor_id: int=int(actor.location.floor_id)
	var origin:=Vector2i(floori(actor.location.cell[0]),floori(actor.location.cell[1]))
	var room_id: String=space.room_use.room_at(world,floor_id,origin)
	if room_id.is_empty():
		if safe_wait(world,actor_id,floor_id,actor.location.cell): return {"floor_id":floor_id,"cell":actor.location.cell.duplicate()}
		return {}
	# Door approaches already have a bounded layout index. A usable public
	# stop does not require another piece of furniture to generate an area.
	var points: Array=space.room_use.waiting_cells(world,room_id).duplicate()
	points.sort_custom(func(a:Vector2i,b:Vector2i)->bool:return origin.distance_squared_to(a)<origin.distance_squared_to(b) if origin.distance_squared_to(a)!=origin.distance_squared_to(b) else (a.y<b.y if a.y!=b.y else a.x<b.x))
	for point: Vector2i in points:
		if not space.room_use.room_at(world,floor_id,point).is_empty(): continue
		var cell: Array=[point.x,point.y]
		if not safe_wait(world,actor_id,floor_id,cell): continue
		if space.travel_quote(world,actor_id,floor_id,cell).get("ok",false): return {"floor_id":floor_id,"cell":cell}
	return {}









func _cell_region(floor_id: int, point: Vector2i) -> Dictionary:
	# The outer Dictionary keeps the complete 64-bit floor identity. Coordinates
	# already use Vector2i throughout region derivation, including its fallback.
	return _floor_regions.get(floor_id,{}).get("by_cell",{}).get(point,{})

func region(world: WorldState, reference: Dictionary) -> Dictionary:
	_ensure(world,int(reference.get("floor_id",0)))
	var area: Dictionary=_by_facility.get(str(reference.get("facility_id","")),{})
	return area if not area.is_empty() and area.ref==reference else {}

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
	return _cell_region(int(actor.location.floor_id),point).get("ref",{}).duplicate(true)

func facilities(world: WorldState, reference: Dictionary, definitions: Array) -> Array:
	var result: Array = []
	var area: Dictionary = region(world,reference)
	if area.is_empty(): return result
	var selected: PackedInt32Array = _facility_members(area,definitions)
	space.query_counts["public_facility_candidates"] = int(space.query_counts.get("public_facility_candidates",0))+selected.size()
	for number: int in selected:
		var id: String = str(area.facilities[number])
		var facility: Dictionary = world.facts.facilities[id]
		if not facility.get("failed",false) and not HospitalRemodel.blocked(world,id): result.append(id)
	return result

func _facility_members(area: Dictionary, definitions: Array) -> PackedInt32Array:
	# Membership is static; both availability and waiting dependencies consume
	# the complete original order. This view never filters failure/ownership.
	var selected: PackedInt32Array = PackedInt32Array()
	var seen: Dictionary = {}
	var definitions_index: Dictionary = area.get("facility_definitions",{})
	for definition: String in definitions:
		if seen.has(definition): continue
		seen[definition] = true
		selected.append_array(definitions_index.get(definition,PackedInt32Array()))
	selected.sort()
	return selected

func _candidate_regions(definitions: Array) -> Array:
	# The complete static membership only excludes regions with no requested
	# definition. Availability, room purpose and actual use remain live below.
	var selected: Dictionary = {}
	for definition: String in definitions:
		for number: int in _regions_by_definition.get(definition,[]): selected[number] = true
	var numbers: Array = selected.keys()
	numbers.sort()
	var result: Array = []
	for number: int in numbers: result.append(_regions[number])
	space.query_counts["public_region_definition_index_hits"] = int(space.query_counts.get("public_region_definition_index_hits",0))+1
	return result

func _body_key(world: WorldState, members: Array) -> String:
	var bodies: Array = []
	for id: String in members: bodies.append(space.body(world.facts.actors[id]))
	space.query_counts["public_fit_body_key_preparations"] = int(space.query_counts.get("public_fit_body_key_preparations",0))+1
	return JSON.stringify(bodies)

func compatible_geometry(world: WorldState, reference: Dictionary, definitions: Array, members: Array) -> bool:
	var local: Array = facilities(world,reference,definitions)
	if local.is_empty(): return false
	var key: String = _body_key(world,members)
	for id: String in local:
		var fits: Dictionary = _geometry_fits.get_or_add(id,{})
		if not fits.has(key): fits[key] = space.facility_geometry_quote(world,id,members[0],members.slice(1)).ok
		if fits[key]: return true
	return false

func select(world: WorldState, actor_id: String, definitions: Array, room_kinds: Array, purpose: String, members: Array = [], maximum_travel_ticks: int = 9223372036854775807, selected_entries: Dictionary = {}, current_floor_only: bool = false, excluded_rooms: Array = []) -> Dictionary:
	var actor: Dictionary = world.facts.actors[actor_id]
	# Support exit owns the real height, pose and origin until it finishes.
	# Public destinations are selected only after that ordinary handoff.
	if actor.location.kind!="floor" or actor.get("posture","standing")=="lying": return {}
	# Furniture-free standing areas remain valid for rest/return-to-waiting.
	# Other purposes cannot select a region without a requested definition.
	# Reuse the world's layout-owned type index instead of enumerating every
	# facility for each selection. Failure and occupancy remain live below.
	if not purpose in ["rest","waiting"]:
		var present: bool = false
		for definition: String in definitions:
			if not world.facility_ids(definition).is_empty(): present = true; break
		if not present: return {}
	_ensure(world)
	var best: Dictionary = {}
	var best_entries: Dictionary = {}
	var travellers: Array = [actor_id] if members.is_empty() else members
	var body_key: String = ""
	# Rest and return-to-waiting also permit a safe standing region without furniture.
	var candidates: Array = _regions if purpose in ["rest","waiting"] else _candidate_regions(definitions)
	if purpose=="toilet":
		var by_room: Dictionary={}
		for area: Dictionary in candidates: by_room.get_or_add(str(area.ref.room_id),[]).append(area)
		var random_rooms: Array=by_room.keys()
		candidates=[]
		while not random_rooms.is_empty():
			var index: int=world.draw("guidance",random_rooms.size())
			candidates.append_array(by_room[random_rooms.pop_at(index)])
	# Choose a strong bound cheaply before quoting other floors. This changes
	# evaluation order only; _earlier and equal-cost tie candidates stay intact.
	if not current_floor_only and purpose in ["water","toilet"]:
		var ordered_candidates: Array=[]
		for area: Dictionary in candidates:
			if int(area.ref.floor_id)==int(actor.location.floor_id): ordered_candidates.append(area)
		for area: Dictionary in candidates:
			if int(area.ref.floor_id)!=int(actor.location.floor_id): ordered_candidates.append(area)
		candidates=ordered_candidates
	space.query_counts["public_select_regions_total"] = int(space.query_counts.get("public_select_regions_total",0))+_regions.size()
	space.query_counts["public_select_regions_visited"] = int(space.query_counts.get("public_select_regions_visited",0))+candidates.size()
	# The caller may already own this unchanged, real-body enumeration. Its
	# actor index is reusable; this child still gets independent query views.
	space.begin_dynamic_route_query(world,not space.in_dynamic_route_query(world))
	for area: Dictionary in candidates:
		if current_floor_only and int(area.ref.floor_id)!=int(actor.location.floor_id): continue
		if str(area.ref.room_id) in excluded_rooms: continue
		var room: Dictionary = world.facts.rooms.get(area.ref.room_id,{})
		if not room.get("open_intent",true): continue
		if not room.is_empty() and (not str(room.get("kind",room.get("type",""))) in room_kinds or HospitalRemodel.blocked(world,area.ref.room_id)): continue
		if room.is_empty() and not "" in room_kinds: continue
		var local: Array = facilities(world,area.ref,definitions)
		if not local.is_empty() and body_key.is_empty(): body_key = _body_key(world,travellers)
		local = local.filter(func(id: String)->bool:
			if _geometry_fits.get(id,{}).get(body_key,true)==false: return false
			if maximum_travel_ticks<9223372036854775807 and space.facility_travel_lower_bound_ticks(world,id,actor_id)>maximum_travel_ticks: return false
			var definition: Dictionary = space.content.facility_definition(world.facts.facilities[id].definition_id)
			var capacity: Dictionary = definition.get("adapter_capacity",definition)
			for member: String in travellers:
				var body: Dictionary = world.facts.actors[member]
				if space.clearance(body)>int(capacity.get("max_clearance_cells",96)) or float(space.body(body).height_m)>float(capacity.get("max_height_m",INF)): return false
			return true)
		if local.is_empty() and not purpose in ["rest","waiting"]: continue
		var inside: bool = contains(world,area.ref,actor_id)
		var waiting: int = 0
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
		var point: Dictionary = arrival_point(world,actor_id,area.ref,travel_limit)
		if point.is_empty(): continue
		var entries: Dictionary = {actor_id:point.duplicate(true)}
		var all_reachable: bool = true
		for member: String in travellers:
			if member==actor_id: continue
			var entry: Dictionary = arrival_point(world,member,area.ref,travel_limit)
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
		if purpose=="toilet": break
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

# Arrival is a structural journey into a region, not a claim on a free cell.
# A body already inside has arrived even if it still needs to leave a doorway.
func prepare_floor_arrivals(world: WorldState, floor_id: int) -> Dictionary:
	_ensure(world,floor_id)
	var before: int = int(space.query_counts.get("public_arrival_geometry_builds",0))
	for actor: Dictionary in world.facts.actors.values():
		if actor.get("posture","standing")=="lying": continue
		for area: Dictionary in _floor_regions.get(floor_id,{}).get("regions",[]):
			var geometry: Dictionary = _entry_geometry_view(world,actor,area)
			_arrival_points(world,actor,area,geometry)
	return {"complete":true,"built":int(space.query_counts.get("public_arrival_geometry_builds",0))-before}

func arrival_point(world: WorldState, actor_id: String, reference: Dictionary, maximum_travel_ticks: int = 9223372036854775807) -> Dictionary:
	var area: Dictionary = region(world,reference)
	if area.is_empty(): return {}
	var actor: Dictionary = world.facts.actors[actor_id]
	if actor.location.kind!="floor" or actor.get("posture","standing")=="lying": return {}
	if contains(world,reference,actor_id): return {"floor_id":int(reference.floor_id),"cell":actor.location.cell.duplicate(),"travel_ticks":0,"inside":true}
	space.begin_route_query(world,{},false)
	var geometry: Dictionary = _entry_geometry_view(world,actor,area)
	var best: Dictionary = {}
	for point: Vector2i in _arrival_points(world,actor,area,geometry):
		for target: Dictionary in _arrival_targets(world,actor,area,point,geometry.geometry):
			space.query_counts["public_arrival_quotes"] = int(space.query_counts.get("public_arrival_quotes",0))+1
			var route: Dictionary = space.travel_quote(world,actor_id,int(reference.floor_id),target.cell)
			if not route.ok or not route.has("travel_ticks"): continue
			var ticks: int = HospitalTransit._add(int(route.travel_ticks),int(target.remaining_ticks))
			if ticks<0 or ticks>maximum_travel_ticks: continue
			if best.is_empty() or ticks<int(best.travel_ticks):
				best = {"floor_id":int(reference.floor_id),"cell":target.cell,"travel_ticks":ticks,"inside":false}
				if int(target.remaining_ticks)>0: best.entry_cell = [point.x,point.y]
	space.end_route_query()
	return best

# An integer goal can itself be the fractional departure stub. If its actual
# final facing would still straddle the region, first walk to an adjacent
# structural approach. The original task then continues into the region;
# neither this waypoint nor its estimate is an arrival or a waiting claim.
func _arrival_targets(world: WorldState, actor: Dictionary, area: Dictionary, point: Vector2i, query: RouteClearance) -> Array:
	var direct: Array = [{"cell":[point.x,point.y],"remaining_ticks":0}]
	if int(actor.location.floor_id)!=int(area.ref.floor_id): return direct
	var origin: Vector2 = ConvoyTrail.point(actor.location.cell)
	if Vector2i(roundi(origin.x),roundi(origin.y))!=point: return direct
	var arrival: Dictionary = actor.duplicate()
	if origin!=Vector2(point): arrival.facing = atan2(float(point.x)-origin.x,float(point.y)-origin.y)
	if _contains_point(arrival,area,Vector2(point)): return direct
	var targets: Array = []
	for direction: Vector2i in BuildGeometry.DIRECTIONS:
		var approach: Vector2i = point+direction
		if not query.reason(approach).is_empty() or not query.edge_reason(approach,point).is_empty(): continue
		var remaining: int = 0 if _contains_arrival_envelope(area,approach,space.clearance(actor)) else HospitalTransit.walking_ticks(space,actor,[],1.0)
		targets.append({"cell":[approach.x,approach.y],"remaining_ticks":remaining})
	return targets

func _contains_point(actor: Dictionary, area: Dictionary, point: Vector2) -> bool:
	var rect: Rect2 = space._actor_rect(actor,point)
	for y: int in range(floori(rect.position.y),ceili(rect.end.y)):
		for x: int in range(floori(rect.position.x),ceili(rect.end.x)):
			if not area.cells.has(Vector2i(x,y)): return false
	return true

# The route's upright cardinal approach uses its checked square envelope,
# not the body's departure facing. Actual arrival still requires contains.
func _contains_arrival_envelope(area: Dictionary, point: Vector2i, size: int) -> bool:
	for y: int in range(point.y,point.y+size):
		for x: int in range(point.x,point.x+size):
			if not area.cells.has(Vector2i(x,y)): return false
	return true

# Each facility has a bounded three-cell region. Its geometric boundary is
# independent of floor entrances: a room door need not lie in this region.
# Prepare the complete boundary once for this region and body envelope.
func _arrival_points(world: WorldState, actor: Dictionary, area: Dictionary, geometry: Dictionary) -> Array:
	if geometry.has("arrival_points"): return geometry.arrival_points
	var size: int = space.clearance(actor)
	var points: Dictionary = {}
	var query: RouteClearance = geometry.geometry
	for point: Vector2i in area.cells:
		space.query_counts["public_arrival_local_geometry"] = int(space.query_counts.get("public_arrival_local_geometry",0))+1
		if not _contains_arrival_envelope(area,point,size) or not query.reason(point).is_empty(): continue
		for direction: Vector2i in BuildGeometry.DIRECTIONS:
			if not _contains_arrival_envelope(area,point+direction,size):
				points[point]=true
				break
	geometry.arrival_points = points.keys()
	space.query_counts["public_arrival_geometry_builds"] = int(space.query_counts.get("public_arrival_geometry_builds",0))+1
	return geometry.arrival_points

# Full safety selection is separate from entering a region. The existing
# complete order is prepared only when that safety query actually needs it;
# an entrance or current-position check must never enumerate the region.
func _prepare_order_geometry(geometry: Dictionary) -> void:
	if geometry.has("entry_cells"): return
	var area: Dictionary = geometry.area
	if not area.has("entry_order_cells"):
		var cells: Array = area.cells.keys()
		var entry_cells: PackedInt32Array = PackedInt32Array()
		entry_cells.resize(cells.size())
		var native_order: bool = true
		for index: int in cells.size():
			var point: Vector2i = cells[index]
			if point.x<0 or point.y<0 or point.x>=ENTRY_GRID_WIDTH or point.y>=ENTRY_GRID_WIDTH:
				native_order = false
				break
			entry_cells[index] = point.y*ENTRY_GRID_WIDTH+point.x
		area.entry_order_cells = {"cells":cells,"ids":entry_cells,"native_order":native_order}
	var prepared: Dictionary = area.entry_order_cells
	geometry.cells = prepared.cells
	geometry.entry_cells = prepared.ids
	geometry.native_order = prepared.native_order

func _waiting_point(world: WorldState, actor_id: String, reference: Dictionary, maximum_travel_ticks: int) -> Dictionary:
	var actor: Dictionary = world.facts.actors[actor_id]
	if actor.location.kind!="floor" or actor.get("posture","standing")=="lying": return {}
	var area: Dictionary = region(world,reference)
	if area.is_empty(): return {}
	var floor_id: int = int(reference.floor_id)
	if contains(world,reference,actor_id) and safe_wait(world,actor_id,floor_id,actor.location.cell):
		return {"floor_id":floor_id,"cell":actor.location.cell.duplicate(),"travel_ticks":0}
	# Every candidate quote first proves this identical fractional departure.
	# Failure is target-independent: do not repeat it for every area cell.
	# This is one synchronous observation, never a retained negative result.
	if not str(space.navigation._prepare_route_subject(world,actor,[],{}).reason).is_empty():
		# Preserve the source-floor dependency normally recorded by each quote.
		space.navigation._observe_floor(world,actor_id,int(actor.location.floor_id))
		return {}
	var origin: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
	# Every cross-floor route must first reach a connector anchor on foot.
	# Include all anchors, even unavailable ones: that only weakens this bound.
	# Fractional stubs, waits and vertical travel add nonnegative time.
	if int(actor.location.floor_id)!=floor_id and _first_connector_lower_ticks(world,actor)>maximum_travel_ticks:
		space.query_counts["public_entry_departure_bound_prunes"]=int(space.query_counts.get("public_entry_departure_bound_prunes",0))+1
		return {}
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
	var compact: bool = ordered.compact
	var entry_count: int = packed.size() if compact else fallback.size()
	if entry_count==0: return {}
	var best: Dictionary = {}
	var field: Dictionary = {}
	var full_quotes: int = 0
	var next_field_check: int = 0
	var offset_ticks: int = int(ordered.get("offset_ticks",0))
	for index: int in entry_count:
		var lower: int
		var point: Vector2i
		if compact:
			var key: int = packed[index]
			var cell_id: int = key%ENTRY_CELL_COUNT
			lower = key/ENTRY_CELL_COUNT+offset_ticks
			point = Vector2i(cell_id%ENTRY_GRID_WIDTH,cell_id/ENTRY_GRID_WIDTH)
		else:
			lower = int(fallback[index].lower)
			point = fallback[index].cell
		if lower>maximum_travel_ticks: break
		if not best.is_empty() and lower>int(best.travel_ticks): break
		# A field already borrowed by this loop gives exact costs. Later cells
		# unable to beat the first winner need no dynamic waiting-place proof.
		# Unsupported fallback coordinates retain the original safety-first path.
		if not field.is_empty() and FloorNavigation._inside(point):
			var remaining_distance: int = field.distances[FloorNavigation._id(point)]
			if remaining_distance<0: continue
			var remaining_ticks: int = HospitalTransit._add(int(field.prefix_ticks),ceili(float(remaining_distance)/float(field.speed)/WorldState.TICK_SECONDS))
			if remaining_ticks<0 or remaining_ticks>maximum_travel_ticks or not best.is_empty() and remaining_ticks>=int(best.travel_ticks): continue
		if not _safe_wait_at(world,actor_id,floor_id,point,Vector2(point),actor,geometry): continue
		if field.is_empty() and full_quotes>=next_field_check:
			field = space.navigation.ready_waiting_cost_field(world,actor_id,floor_id,bounds)
			# Local-first selection may not yet have an actor quote context.
			# Recheck once after the first quote, then keep the cold-field cadence.
			next_field_check = 1 if full_quotes==0 else 12 if full_quotes<12 else full_quotes+12
		var travel_ticks: int = -1
		if not field.is_empty():
			# The complete resident field is borrowed only by this synchronous
			# loop. safe_wait does not acquire graphs or trim their cache; no
			# navigation query runs while this local array is being consumed.
			space.query_counts["public_entry_field_hits"] = int(space.query_counts.get("public_entry_field_hits",0))+1
			var distance: int = field.distances[FloorNavigation._id(point)]
			if distance<0: continue
			travel_ticks = HospitalTransit._add(int(field.prefix_ticks),ceili(float(distance)/float(field.speed)/WorldState.TICK_SECONDS))
		else:
			var leg: Dictionary = space.navigation.waiting_travel_ticks(world,actor_id,floor_id,point,bounds)
			full_quotes += 1
			if not leg.is_empty(): travel_ticks = int(leg.travel_ticks)
			else:
				var route: Dictionary = space.travel_quote(world,actor_id,floor_id,[point.x,point.y])
				if route.ok and route.has("travel_ticks"): travel_ticks = int(route.travel_ticks)
		if travel_ticks>=0 and travel_ticks<=maximum_travel_ticks and (best.is_empty() or travel_ticks<int(best.travel_ticks)): best = {"floor_id":floor_id,"cell":[point.x,point.y],"travel_ticks":travel_ticks}
	return best

func _entry_order(actor: Dictionary, origin: Vector2, bounds: Dictionary, geometry: Dictionary, maximum_travel_ticks: int) -> Dictionary:
	_prepare_order_geometry(geometry)
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
	var previous: Dictionary = geometry.get("previous_ordering",{})
	var ordered: Dictionary
	if retained.get("basis",[])==basis:
		space.query_counts["entry_order_hits"] = int(space.query_counts.get("entry_order_hits",0))+1
		ordered = retained.ordered
	elif previous.get("basis",[])==basis:
		space.query_counts["entry_order_hits"] = int(space.query_counts.get("entry_order_hits",0))+1
		ordered = previous.ordered
		geometry.previous_ordering = retained
		geometry.ordering = previous
	else:
		# Every candidate shares the fractional walking stub or minimum landing
		# arrival. Removing this additive prefix preserves lower/y/x ordering.
		# Keep the complete order: each caller applies its own travel budget.
		ordered = _ordered_entry_cells(actor,Vector2(start),normalized,geometry,HospitalTransit.MAX_TICK)
		space.query_counts["entry_order_builds"] = int(space.query_counts.get("entry_order_builds",0))+1
		if ordered.compact and geometry.has("ordering"):
			# Two recent bases preserve alternating observers without retaining an
			# origin history. Both complete orders belong to this static geometry.
			geometry.previous_ordering = retained
			geometry.ordering = {"basis":basis.duplicate(true),"ordered":ordered}
	var largest: int = int(ordered.packed[-1]/ENTRY_CELL_COUNT) if ordered.compact and not ordered.packed.is_empty() else 0
	if not ordered.compact or prefix<0 or prefix>ENTRY_SORT_LIMIT-largest:
		# Preserve the original exact int64 fallback, including mixed encodable
		# and very large values. No candidate or budget is approximated.
		space.query_counts["entry_order_fallbacks"] = int(space.query_counts.get("entry_order_fallbacks",0))+1
		return _ordered_entry_cells(actor,origin,bounds,geometry,maximum_travel_ticks)
	return {"packed":ordered.packed,"fallback":[],"compact":true,"offset_ticks":prefix}

func _ordered_entry_cells(actor: Dictionary, origin: Vector2, bounds: Dictionary, geometry: Dictionary, maximum_travel_ticks: int) -> Dictionary:
	_prepare_order_geometry(geometry)
	var start: Vector2i = Vector2i(roundi(origin.x),roundi(origin.y))
	var speed: float = float(space.content.balance.movement_speeds[str(space.clearance(actor))])
	var stub_ticks: int = ceili(origin.distance_to(Vector2(start))/speed/WorldState.TICK_SECONDS)
	var walking: PackedInt64Array = geometry.get("walking_ticks",PackedInt64Array())
	if walking.is_empty() or float(geometry.get("walking_speed",-1.0))!=speed:
		walking.resize((ENTRY_GRID_WIDTH-1)*2+1)
		for distance: int in walking.size():
			# Retain walking_ticks' division order and separate fractional-stub ceil.
			walking[distance] = ceili(float(distance)/speed/WorldState.TICK_SECONDS)
		if geometry.has("entry_cells"):
			geometry.walking_ticks = walking
			geometry.walking_speed = speed
			space.query_counts["entry_walking_table_builds"] = int(space.query_counts.get("entry_walking_table_builds",0))+1
	var landing_cells: Array[Vector2i] = []
	var landing_ticks: PackedInt64Array = PackedInt64Array()
	if not bounds.unknown:
		for landing: Dictionary in bounds.landings:
			landing_cells.append(Vector2i(int(landing.cell.x),int(landing.cell.y)))
			landing_ticks.append(int(landing.ticks))
	if geometry.get("native_order",false):
		var sources: PackedInt64Array = PackedInt64Array()
		for index: int in landing_cells.size():
			sources.append(landing_cells[index].x)
			sources.append(landing_cells[index].y)
			sources.append(landing_ticks[index])
		var excluded: PackedInt32Array = PackedInt32Array()
		for origin_key: Vector2 in geometry.points:
			if geometry.points[origin_key]!=false: continue
			var point: Vector2i = Vector2i(roundi(origin_key.x),roundi(origin_key.y))
			if Vector2(point)==origin_key and point.x>=0 and point.y>=0 and point.x<ENTRY_GRID_WIDTH and point.y<ENTRY_GRID_WIDTH:
				excluded.append(point.y*ENTRY_GRID_WIDTH+point.x)
		# Standard-library sort constructs all lower/y/x keys in one native call.
		# Noncompact/int64 cases retain the complete original calculation below.
		var native: Dictionary = PlatformArrivalMath.entry_order(geometry.entry_cells,{"start":[start.x,start.y],"walking":walking,"sources":sources,"stub_ticks":stub_ticks,"maximum_ticks":maximum_travel_ticks,"excluded":excluded})
		if native.get("ready",false):
			space.query_counts["entry_order_native_builds"] = int(space.query_counts.get("entry_order_native_builds",0))+1
			native.erase("ready")
			return native
		space.query_counts["entry_order_native_fallbacks"] = int(space.query_counts.get("entry_order_native_fallbacks",0))+1
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

func owns_arrival(world: WorldState, actor_id: String, area: Dictionary, owner_key: String, owner_id: String) -> bool:
	var movement: Dictionary = world.facts.moves.get(actor_id,{})
	if movement.is_empty() or movement.get(owner_key,"")!=owner_id or movement.has("detour") or movement.has("convoy") or movement.get("members",[actor_id])!=[actor_id]: return false
	var actor: Dictionary = world.facts.actors[actor_id]
	if actor.location.kind!="floor" or actor.get("posture","standing")=="lying" or not contains(world,area,actor_id): return false
	var cursor: int = int(movement.get("cursor",0))
	var path: Array = movement.get("path",[])
	return cursor<0 or cursor>=path.size() or path[cursor].kind=="floor"

func try_finish_arrival(world: WorldState, actor_id: String, area: Dictionary, owner_key: String, owner_id: String) -> bool:
	if not owns_arrival(world,actor_id,area,owner_key,owner_id): return false
	var actor: Dictionary = world.facts.actors[actor_id]
	return safe_wait(world,actor_id,int(actor.location.floor_id),actor.location.cell) and space.cancel_ground_move(world,actor_id)

func _first_connector_lower_ticks(world: WorldState, actor: Dictionary) -> int:
	# Convoy portals can shift their boarding point away from the anchor.
	if actor.has("_convoy_size") or actor.has("_convoy_body"): return 0
	if world.facts.connectors.is_empty(): return 0
	var start: Vector2i=Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1]))
	var distance: int=HospitalTransit.MAX_TICK
	for connection: Dictionary in world.facts.connectors.values():
		var anchor: Vector2i=Vector2i(int(connection.anchor[0]),int(connection.anchor[1]))
		distance=mini(distance,absi(start.x-anchor.x)+absi(start.y-anchor.y))
	return HospitalTransit.walking_ticks(space,actor,[],float(distance))

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
		var area: Dictionary = _cell_region(floor_id,point)
		# Standing safety also serves offices, empty rest rooms and queue tails.
		# A facility region grants no additional physical standing permission.
		if area.is_empty(): area={"ref":{"floor_id":floor_id}}
		geometry = _entry_geometry_view(world,actor,area)
	if not geometry.points.has(origin): geometry.points[origin] = _safe_wait_geometry(world,actor,floor_id,origin,geometry.geometry,geometry.get("doors",{}))
	if not geometry.points[origin]: return false
	var current: Dictionary = space.read_view(world,"public_wait_clearance:"+actor_id+":"+str(floor_id),func()->Dictionary:
		return {"size":space.clearance(actor),"regions":RouteClearance.capture_reservation_regions(world,actor.id,floor_id)})
	if not RouteClearance.reservation_regions_reason(Vector2(point),int(current.size),current.regions).is_empty(): return false
	return space._dynamic_clear(world,actor_id,floor_id,space._actor_rect(actor,origin))

# Integer entry candidates only: region() already ensured this floor, and actor
# and geometry belong to the same synchronous read-only scan. Keep the public
# fractional-cell entry unchanged. The safety tail is intentionally identical;
# tests/native/entry_safety.py guards it against diverging permission checks.
func _safe_wait_at(world: WorldState, actor_id: String, floor_id: int, point: Vector2i, origin: Vector2, actor: Dictionary, geometry: Dictionary) -> bool:
	if not geometry.points.has(origin): geometry.points[origin] = _safe_wait_geometry(world,actor,floor_id,origin,geometry.geometry,geometry.get("doors",{}))
	if not geometry.points[origin]: return false
	var current: Dictionary = space.read_view(world,"public_wait_clearance:"+actor_id+":"+str(floor_id),func()->Dictionary:
		return {"size":space.clearance(actor),"regions":RouteClearance.capture_reservation_regions(world,actor.id,floor_id)})
	if not RouteClearance.reservation_regions_reason(Vector2(point),int(current.size),current.regions).is_empty(): return false
	return space._dynamic_clear(world,actor_id,floor_id,space._actor_rect(actor,origin))

func _safe_wait_geometry(world: WorldState, actor: Dictionary, floor_id: int, origin: Vector2, geometry: RouteClearance, doors: Dictionary = {}) -> bool:
	if not geometry.reason(Vector2i(roundi(origin.x),roundi(origin.y))).is_empty(): return false
	var bounds: Rect2 = space._actor_rect(actor,origin)
	var constraints: Dictionary = _wait_constraints(world)
	if doors.is_empty():
		for door: Dictionary in constraints.doors.get(floor_id,[]):
			space.query_counts["public_wait_door_checks"] = int(space.query_counts.get("public_wait_door_checks",0))+1
			var span: int = int(world.facts.adaptations.get(door.id,{}).get("span",door.span))
			if bounds.intersects(space._door_rect(door,span).grow(1.0),false): return false
	else:
		var numbers: PackedInt32Array = PackedInt32Array()
		for id: String in (doors.index as BodyIndex).candidates(floor_id,bounds): numbers.append(int(id))
		numbers.sort()
		for number: int in numbers:
			space.query_counts["public_wait_door_checks"] = int(space.query_counts.get("public_wait_door_checks",0))+1
			if bounds.intersects(doors.rectangles[number],false): return false
	for x: int in range(floori(bounds.position.x/8.0),floori(bounds.end.x/8.0)+1):
		for y: int in range(floori(bounds.position.y/8.0),floori(bounds.end.y/8.0)+1):
			for work: Vector2 in constraints.points.get(floor_id,{}).get(Vector2i(x,y),[]):
				if bounds.intersects(Rect2(work,Vector2.ONE),false): return false
			for post: Rect2 in constraints.get("posts",{}).get(floor_id,{}).get(Vector2i(x,y),[]):
				if bounds.intersects(post,false): return false
	return true

func _entry_geometry_view(world: WorldState, actor: Dictionary, area: Dictionary) -> Dictionary:
	var floor_id: int = int(area.ref.floor_id)
	var rectangle: Rect2 = space._actor_rect(actor,Vector2.ZERO)
	var spans: Array = []
	for door: Dictionary in _wait_constraints(world).doors.get(floor_id,[]): spans.append([door.id,world.facts.adaptations.get(door.id,{}).get("span",door.span)])
	var doors: Dictionary = _wait_door_view(world,floor_id,spans)
	# Serialize the unchanged floor door vector once per exact span view, not
	# once per patient. Preserve the original complete cache key byte for byte.
	var prefix: String = JSON.stringify([area.ref,space.body(actor),actor.get("posture","standing"),rectangle.position,rectangle.size],"",true,true)
	var key: String = prefix.substr(0,prefix.length()-1)+","+str(doors.span_key)+"]"
	var version: String = space._navigation.floor_static_version(space,world,floor_id)
	var saved: Dictionary = _entry_geometry.get(key,{})
	if saved.is_empty() or saved.version!=version:
		saved = {"version":version,"area":area,"points":{},"geometry":space.navigation.structural_clearance(world,actor,floor_id),"ordering":{},"previous_ordering":{}}
		_entry_geometry[key] = saved
	saved.doors = doors
	return saved

func _wait_door_view(world: WorldState, floor_id: int, spans: Array) -> Dictionary:
	var constraints: Dictionary = _wait_constraints(world)
	var views: Dictionary = constraints.get_or_add("door_views",{})
	var saved: Dictionary = views.get(floor_id,{})
	if not saved.is_empty() and saved.spans==spans: return saved
	# Every regional/body entry refers to this same current view. Rebuild its
	# index in place rather than retaining one native tree for each past span.
	var index: BodyIndex = BodyIndex.new() if saved.is_empty() else saved.index
	index.clear()
	var rectangles: Array[Rect2] = []
	var doors: Array = constraints.doors.get(floor_id,[])
	for number: int in doors.size():
		var rect: Rect2 = space._door_rect(doors[number],int(spans[number][1])).grow(1.0)
		rectangles.append(rect)
		index.update(str(number),floor_id,rect)
	if saved.is_empty(): saved = {"index":index}
	saved.spans = spans.duplicate(true)
	saved.span_key = JSON.stringify(spans,"",true,true)
	saved.rectangles = rectangles
	views[floor_id] = saved
	space.query_counts["public_wait_door_index_builds"] = int(space.query_counts.get("public_wait_door_index_builds",0))+1
	return saved

func _wait_constraints(world: WorldState) -> Dictionary:
	if not _wait_geometry.is_empty(): return _wait_geometry
	var result: Dictionary = {"points":{},"doors":{},"posts":{}}
	var entry: Dictionary=world.facts.get("entry",{"floor_id":1,"cell":[47,93]})
	var entrance: Rect2=Rect2(float(entry.cell[0]),float(entry.cell[1]),1.0,1.0)
	var entry_posts: Dictionary=result.posts.get_or_add(int(entry.floor_id),{})
	for x: int in range(floori(entrance.position.x/8.0),floori(entrance.end.x/8.0)+1):
		for y: int in range(floori(entrance.position.y/8.0),floori(entrance.end.y/8.0)+1):
			entry_posts.get_or_add(Vector2i(x,y),[]).append(entrance)
	for floor_key: String in world.facts.floors.overrides:
		var floor_id: int = int(floor_key)
		result.doors[floor_id] = []
		for door: Dictionary in world.facts.floors.overrides[floor_key].get("doors",[]): result.doors[floor_id].append(door)
	for facility: Dictionary in world.facts.facilities.values():
		var definition: Dictionary = space.content.facility_definition(facility.definition_id)
		# Nonblocking noise screens have no use or maintenance workstation.
		# Their generic placement anchors do not reserve standing space.
		if definition.get("environment_function", "")=="noise_barrier" and not definition.get("blocks_movement",true): continue
		var floor_id: int = int(facility.floor_id)
		if not result.points.has(floor_id): result.points[floor_id] = {}
		var layout: Dictionary = space.facility_layout(world,facility.id)
		var operators: Array=layout.get("operator_cells",[])
		if facility.definition_id=="SE01":
			var buckets: Dictionary=result.posts.get_or_add(floor_id,{})
			for index: int in operators.size():
				var point: Array=operators[index]
				var post: Rect2=Rect2(float(point[0]),float(point[1]),int(layout.operator_clearances[index]),int(layout.operator_clearances[index]))
				for x: int in range(floori(post.position.x/8.0),floori(post.end.x/8.0)+1):
					for y: int in range(floori(post.position.y/8.0),floori(post.end.y/8.0)+1): buckets.get_or_add(Vector2i(x,y),[]).append(post)
			operators=[]
		for work: Array in [layout.get("patient_cell",[])]+operators+[layout.get("repair_cell",[])]:
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
	for intent: Dictionary in intents(world):
		if intent.phase in ["using","returning"]:
			var id: String=str(intent.get("facility_id",""))
			if not id.is_empty(): result.remaining[id]=maxi(int(result.remaining.get(id,0)),int(intent.remaining_ticks) if intent.phase=="using" else 2147483647)
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
	var visitor_seats: Dictionary = {}
	for collection: String in ["seats","needs"]:
		for intent: Dictionary in world.facts.get("waiting_life",{}).get(collection,{}).values():
			if intent.has("public_purpose"): result.append(intent)
	for staff: Dictionary in world.facts.staff.values():
		var task: Dictionary = staff.get("life_task",{})
		if task.has("public_purpose"): result.append(task)
	for stay: Dictionary in world.facts.get("visitors",{}).get("stays",{}).values():
		if not stay.get("life_task",{}).is_empty(): result.append(stay.life_task)
		if stay.has("public_use"):
			result.append(stay.public_use)
			if stay.public_use.get("phase","")=="seated": visitor_seats[str(stay.public_use.get("facility_id",""))] = true
	return {"items":result,"visitor_seats":visitor_seats}

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
			for id: String in area.facilities:
				result.targets.get_or_add(JSON.stringify([purpose,id]),[]).append(row)
	return result

func _facility_queue(world: WorldState, purpose: String, facility_id: String) -> Array:
	var view: Dictionary = space.read_view(world,"public_queue_members",_queue_members.bind(world))
	var key: String = JSON.stringify([purpose,facility_id])
	if not view.facilities.has(key):
		view.facilities[key] = view.targets.get(key,[])
	return view.facilities[key]

# Queue joining is an explicit task transition after actual regional arrival.
# The sequence is shared by patient and employee intents, including same-tick
# arrivals. Overlapping facility regions do not create separate queue priority.
func join(world: WorldState, intent: Dictionary) -> void:
	if intent.get("public_purpose","")!="water" or int(intent.get("arrived_tick",-1))<0 or intent.has("joined_seq"): return
	var state: Dictionary=world.facts.waiting_life
	state.next_queue_seq=int(state.get("next_queue_seq",0))+1
	intent.joined_seq=state.next_queue_seq
	changed(world)

func turn(world: WorldState, intent: Dictionary, facility_id: String) -> bool:
	# Waiting chairs have no arrival-ticket priority. Only actual occupancy
	# and the final fit check decide who can sit; service queues keep FIFO.
	if intent.public_purpose=="seat": return true
	for row: Dictionary in _facility_queue(world,str(intent.public_purpose),facility_id):
		var other: Dictionary = row.intent
		if is_same(other,intent): continue
		var before: bool = int(other.joined_seq)<int(intent.joined_seq) if other.has("joined_seq") and intent.has("joined_seq") else int(other.arrived_tick)<int(intent.arrived_tick) or int(other.arrived_tick)==int(intent.arrived_tick) and str(other.id)<str(intent.id)
		if int(intent.get("arrived_tick",-1))<0: before = true
		if not before: continue
		var ids: Array = other.get("staff_ids",[str(other.actor_id)])
		if ids.is_empty(): continue
		var fit: Dictionary = _queue_fit(world,facility_id,ids)
		if fit.ok: return false
	return true

func _queue_fit(world: WorldState, facility_id: String, ids: Array) -> Dictionary:
	var fits: Dictionary = space.read_view(world,"public_queue_fits",func()->Dictionary: return {})
	var key: String = JSON.stringify([facility_id,ids])
	if not fits.has(key): fits[key] = _queue_fit_current(world,facility_id,ids)
	return fits[key]

func _queue_fit_current(world: WorldState, facility_id: String, ids: Array) -> Dictionary:
	# Independent raw-input callers retain the original fresh projection path.
	# Cross-observer reuse requires an explicit current read-only boundary.
	if space._route_queries.is_empty() or space._route_queries.back().world!=world:
		space.query_counts["public_queue_fit_builds"] = int(space.query_counts.get("public_queue_fit_builds",0))+1
		return _queue_fit_in_query(world,facility_id,ids)
	# The qualification belongs to the earlier waiter, not each later observer.
	# Keep only this facility's latest successful fixed geometry. No queue,
	# negative result or permission to occupy survives the caller's scope.
	var facilities: Dictionary = world.facts.facilities
	if _queue_fit_world==null or _queue_fit_world.get_ref()!=world or _queue_fit_revision!=world.geometry_revision or not is_same(_queue_fit_facilities,facilities) or _queue_fit_facility_count!=facilities.size():
		_queue_fit_world = weakref(world)
		_queue_fit_revision = world.geometry_revision
		_queue_fit_facilities = facilities
		_queue_fit_facility_count = facilities.size()
		_queue_fits.clear()
	var basis: Array = _queue_fit_basis(world,facility_id,ids)
	var saved: Dictionary = _queue_fits.get(facility_id,{})
	if not basis.is_empty() and saved.get("basis",[])==basis and _queue_fit_clear(world,facility_id,ids,saved.quote):
		space.query_counts["public_queue_fit_hits"] = int(space.query_counts.get("public_queue_fit_hits",0))+1
		return saved.quote
	space.query_counts["public_queue_fit_builds"] = int(space.query_counts.get("public_queue_fit_builds",0))+1
	var result: Dictionary = _queue_fit_in_query(world,facility_id,ids)
	if not basis.is_empty() and result.ok and result.has("regions"):
		_queue_fits[facility_id] = {"basis":basis.duplicate(true),"quote":result.duplicate(true)}
	else:
		_queue_fits.erase(facility_id)
	return result

func _queue_fit_basis(world: WorldState, facility_id: String, ids: Array) -> Array:
	var current: Dictionary = world.facts.adaptations.get(facility_id,{})
	var facility: Dictionary = world.facts.facilities.get(facility_id,{})
	if facility.is_empty() or ids.is_empty() or space.nominal_query(world): return []
	var definition: Dictionary = space.content.facility_definition(facility.definition_id)
	var profile: Dictionary = space.content.definition("facility_fit_profiles",str(definition.get("fit_profile_id","")))
	# Beds can stretch and prove remote exits; a local region check cannot stand
	# in for that proof. Only fixed public fittings use this retained geometry.
	if profile.is_empty() or profile.get("kind","")=="bed": return []
	if current.is_empty() and (profile.get("kind","")!="amenity" or profile.get("extent_rule","")!="base_with_real_operator_areas" or not space._actor_exclusion_scope(world).is_empty()): return []
	var participants: Array = []
	for id: String in ids:
		if not world.facts.actors.has(id): return []
		participants.append([id,space.body(world.facts.actors[id])])
	return [space._navigation.floor_static_version(space,world,int(facility.floor_id)),facility,current,participants,world.facts.get("staff_life",{}).get("personal_beds",{}).get(facility_id,{}),space.content.content_fingerprint]

func _queue_fit_clear(world: WorldState, facility_id: String, ids: Array, quote: Dictionary) -> bool:
	var current: Dictionary = world.facts.adaptations.get(facility_id,{})
	var floor_id: int = int(quote.floor_id)
	if current.is_empty():
		# A vacant fitting has no departing owner or removed reservation. Keep
		# the original current body, reservation and accepted sweep checks.
		for area: Array in quote.regions:
			if not space._dynamic_clear(world,str(ids[0]),floor_id,Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3])),ids): return false
		return true
	space._ensure_actor_index(world)
	var ignored: Array = ids+[current.actor_id]+current.staff_ids
	for area: Array in quote.regions:
		var rect: Rect2 = Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3]))
		if space._actor_index.intersects(floor_id,rect,str(ids[0]),ignored): return false
		for region: Dictionary in space._reservation_regions(world,floor_id,rect):
			if region.reservation_id==facility_id: continue
			var reservation: Dictionary = region.reservation
			if reservation.actor_id in ids or ids[0] in reservation.get("staff_ids",[]): continue
			if rect.intersects(region.rect,false): return false
		# A departure projection excludes its current body, never its already
		# accepted historical sweep. This is the original actual-query contract.
		if space.movement._sweep_index.intersects(floor_id,rect,str(ids[0]),ids): return false
	return true

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
