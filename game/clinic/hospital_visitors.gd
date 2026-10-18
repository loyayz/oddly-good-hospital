class_name HospitalVisitors
extends RefCounted

const WAITING_SEAT_DEFINITIONS: Array[String] = ["FUR09","FUR10","FUR11","FUR12","FUR13","FUR14","FUR15","FUR16","FUR49","FUR50","FUR51","FUR52"]

var content: HospitalContent
var space: HospitalSpace
var _present_world: WorldState
var _present_records: Dictionary = {}
var _present_count: int = -1
var _present_groups: Dictionary = {}
var _present_observer: String = "visitor_lookup_"+str(get_instance_id())

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry

func ensure(world: WorldState) -> void:
	if not world.facts.has("visitors"):
		world.facts.visitors = {"requests":{},"stays":{},"next_scan_tick":0}

func arrivals(world: WorldState) -> void:
	ensure(world)
	if world.sim_tick<int(world.facts.visitors.next_scan_tick):
		return
	world.facts.visitors.next_scan_tick = world.sim_tick+_ticks(content.balance.ward_care.visitor_request_scan_seconds)
	var lookup: Dictionary = _lookup(world)
	for visit_id: String in world.active_visit_ids():
		var visit: Dictionary = world.facts.visits[visit_id]
		if not visit.has("companion_intent"):
			visit.companion_intent = world.draw("arrival",10000)<roundi(float(content.balance.ward_care.companion_probability)*10000)
			if visit.companion_intent and not visit.phase in ["leaving","departed"]:
				_request(world,visit,"companion","")
		var stay: Dictionary = lookup.wards.get(visit_id,{})
		if stay.is_empty() or not stay.phase in ["recovery","round_wait"] or _window(world).ends_with(":2"):
			continue
		if not visit.has("visitor_windows"):
			visit.visitor_windows = {}
		var window: String = _window(world)
		if visit.visitor_windows.has(window):
			continue
		var present: Dictionary = lookup.present.get(visit_id,{})
		if not present.is_empty() and (present.phase in ["to_bed","visiting","yielding"] or not str(present.get("pending_window","")).is_empty()):
			continue
		var intent: bool = world.draw("arrival",10000)<roundi(float(content.balance.ward_care.ward_visit_probability)*10000)
		visit.visitor_windows[window] = {"intent":intent,"evaluated_tick":world.sim_tick,"started":false}
		if intent and bool(visit.get("visitor_consent",true)):
			if present.is_empty():
				_request(world,visit,"ward_visit",window)
			else:
				present.pending_window = window
	var ids: Array = world.facts.visitors.requests.keys()
	ids.sort_custom(func(a: String,b: String) -> bool:
		var first: Dictionary = world.facts.visitors.requests[a]
		var second: Dictionary = world.facts.visitors.requests[b]
		return int(first.request_tick)<int(second.request_tick) if int(first.request_tick)!=int(second.request_tick) else a<b)
	for id: String in ids:
		var request: Dictionary = world.facts.visitors.requests[id]
		var visit: Dictionary = world.facts.visits[request.visit_id]
		if visit.phase in ["leaving","departed","ward_referral"] or (request.purpose=="ward_visit" and (not bool(visit.get("visitor_consent",true)) or request.window!=_window(world))):
			world.facts.visitors.requests.erase(id)
			continue
		if _admit(world,visit,request,lookup):
			world.facts.visitors.requests.erase(id)
			break

func _request(world: WorldState, visit: Dictionary, purpose: String, window: String) -> void:
	var id: String = visit.id+":"+purpose+":"+window
	if not world.facts.visitors.requests.has(id):
		world.facts.visitors.requests[id] = {"id":id,"visit_id":visit.id,"purpose":purpose,"window":window,"request_tick":world.sim_tick}

func _admit(world: WorldState, visit: Dictionary, request: Dictionary, lookup: Dictionary = {}) -> bool:
	if lookup.is_empty(): lookup = _lookup(world)
	if lookup.present.has(visit.id):
		return false
	var patient: Dictionary = world.facts.actors[visit.actor_id]
	var entry: Dictionary = world.facts.get("entry",{"floor_id":1,"cell":[47,93]})
	var original_id: String = str(visit.get("relative_actor_id",""))
	var actor: Dictionary = {"id":original_id if not original_id.is_empty() else "relative_probe","name":str(patient.name)+"的家属","species_id":patient.species_id,"relative_of":visit.actor_id,
		"location":{"kind":"floor","floor_id":int(entry.floor_id),"cell":entry.cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
	space.begin_route_query(world,{},space.nominal_query(world))
	var entry_clear: bool = space.static_reason(world,actor,int(entry.floor_id),Vector2i(int(entry.cell[0]),int(entry.cell[1]))).is_empty() and space._dynamic_clear(world,actor.id,int(entry.floor_id),space.body_rectangle(actor))
	space.end_route_query()
	if not entry_clear:
		return false
	var facility_ids: Array = _waiting_facility_ids(world)
	# Admission only adds its own probe; waiting and route queries read all
	# other facts synchronously without changing their owners.
	var facts: Dictionary = world.facts.duplicate()
	facts.actors = world.facts.actors.duplicate()
	var candidate: WorldState = WorldState.new(facts)
	candidate.facts.actors[actor.id] = actor
	var waiting: Dictionary = _waiting_point(candidate,actor.id,facility_ids,lookup.waiting)
	if waiting.is_empty():
		return false
	var actor_id: String = original_id if not original_id.is_empty() else world.new_id("relative")
	var stay_id: String = world.new_id("visitor")
	actor.id = actor_id
	actor.personality_id = world.facts.actors[original_id].personality_id if not original_id.is_empty() else content.catalog.patient_personalities[world.draw("personality",content.catalog.patient_personalities.size())].id
	visit.relative_actor_id = actor_id
	world.facts.actors[actor_id] = actor
	world.facts.visitors.stays[stay_id] = {"id":stay_id,"visit_id":visit.id,"actor_id":actor_id,"purpose":request.purpose,"phase":"to_waiting",
		"waiting_floor":waiting.floor_id,"waiting_cell":waiting.cell,"pending_window":request.window,"remaining_ticks":0,"started_window":""}
	world.fact_record_changed("visitor_stays",stay_id)
	space.sync_actor(world,actor_id)
	return true

func dispatch(world: WorldState) -> void:
	ensure(world)
	var wards: Dictionary = _lookup(world).wards
	for stay_id: String in _stay_ids(world):
		var stay: Dictionary = world.facts.visitors.stays[stay_id]
		var visit: Dictionary = world.facts.visits[stay.visit_id]
		var actor: Dictionary = world.facts.actors[stay.actor_id]
		if visit.phase in ["leaving","departed","ward_referral"]:
			stay.phase = "leaving"
			stay.pending_window = ""
		if not bool(visit.get("visitor_consent",true)) and stay.phase in ["to_bed","visiting"]:
			_end_visit(stay)
		if stay.phase=="leaving":
			var exit: Array = space.exit_cell(world,actor)
			if space.at(world,actor.id,1,exit):
				actor.location = {"kind":"outside"}
				space.sync_actor(world,actor.id)
				world.facts.visitors.stays.erase(stay_id)
			elif not world.facts.moves.has(actor.id):
				space.request_move(world,actor.id,1,exit)
			continue
		if stay.phase in ["to_waiting","yielding"]:
			if space.at(world,actor.id,int(stay.waiting_floor),stay.waiting_cell):
				if stay.phase=="yielding" and int(stay.remaining_ticks)==0:
					_end_visit(stay)
				else:
					stay.phase = "waiting"
			elif not world.facts.moves.has(actor.id):
				space.request_move(world,actor.id,int(stay.waiting_floor),stay.waiting_cell)
			continue
		if stay.phase=="waiting" and not str(stay.pending_window).is_empty():
			if stay.pending_window!=_window(world) or not bool(visit.get("visitor_consent",true)):
				stay.pending_window = ""
				if stay.purpose=="ward_visit": stay.phase = "leaving"
				continue
			var ward_stay: Dictionary = wards.get(visit.id,{})
			if ward_stay.is_empty() or not ward_stay.phase in ["recovery","round_wait"]:
				continue
			var position: Dictionary = _bedside(world,stay.actor_id,ward_stay)
			if position.is_empty():
				stay.waiting_reason = "床边暂时没有安全探视位置"
				continue
			stay.bed_id = ward_stay.bed_id
			stay.bedside_cell = position.cell
			stay.bedside_floor = position.floor_id
			stay.phase = "to_bed"
			space.request_move(world,actor.id,int(position.floor_id),position.cell)
		elif stay.phase=="to_bed":
			if stay.pending_window!=_window(world):
				_end_visit(stay)
			elif space.at(world,actor.id,int(stay.bedside_floor),stay.bedside_cell):
				stay.phase = "visiting"
				stay.started_window = stay.pending_window
				stay.pending_window = ""
				stay.remaining_ticks = _ticks(content.balance.hospital_situations.ward_visit_seconds)
				visit.visitor_windows[stay.started_window].started = true
				stay.scene_id = "WS04"
				stay.started_tick = world.sim_tick

func advance(world: WorldState) -> void:
	ensure(world)
	for stay: Dictionary in world.facts.visitors.stays.values():
		if stay.phase in ["visiting","yielding"] and int(stay.remaining_ticks)>0:
			stay.remaining_ticks = maxi(0,int(stay.remaining_ticks)-1)
			if int(stay.remaining_ticks)==0:
				_end_visit(stay)

func yield_for_care(world: WorldState, visit_id: String) -> bool:
	ensure(world)
	var visitor: Dictionary = _present(world,visit_id)
	if visitor.is_empty() or visitor.phase in ["waiting","to_waiting","leaving"]:
		return true
	if visitor.phase in ["visiting","to_bed"]:
		visitor.phase = "yielding"
		visitor.pending_window = ""
		visitor.yield_requested_tick = world.sim_tick
	var actor: Dictionary = world.facts.actors[visitor.actor_id]
	if visitor.phase=="yielding" and actor.location.kind=="floor":
		var movement: Dictionary = world.facts.moves.get(actor.id,{})
		if not movement.is_empty() and movement.get("members",[actor.id])==[actor.id] and (int(movement.target_floor)!=int(visitor.waiting_floor) or movement.target_cell!=visitor.waiting_cell):
			var target: Vector2i = Vector2i(int(visitor.waiting_cell[0]),int(visitor.waiting_cell[1]))
			if space.static_reason(world,actor,int(visitor.waiting_floor),target).is_empty():
				HospitalTransit.cancel_waiting(world,movement)
				world.facts.moves.erase(actor.id)
		if not world.facts.moves.has(actor.id):
			space.request_move(world,visitor.actor_id,int(visitor.waiting_floor),visitor.waiting_cell)
	var arrived: bool = space.at(world,visitor.actor_id,int(visitor.waiting_floor),visitor.waiting_cell)
	if arrived and int(visitor.remaining_ticks)==0:
		_end_visit(visitor)
	return arrived

func _end_visit(stay: Dictionary) -> void:
	stay.pending_window = ""
	stay.phase = "to_waiting" if stay.purpose=="companion" else "leaving"

func _waiting_point(world: WorldState, actor_id: String, facility_ids: Variant = null, waiting: Variant = null) -> Dictionary:
	space.begin_route_query(world,{},space.nominal_query(world))
	# A supplied empty list is complete, just like a nonempty source view.
	var candidates: Array = _waiting_facility_ids(world) if facility_ids==null else facility_ids
	var result: Dictionary = _waiting_point_in_query(world,actor_id,candidates,_lookup(world).waiting if waiting==null else waiting)
	space.end_route_query()
	return result

func _waiting_facility_ids(world: WorldState) -> Array:
	var facility_ids: Array = []
	for definition_id: String in WAITING_SEAT_DEFINITIONS:
		facility_ids.append_array(world.facility_ids(definition_id))
	facility_ids.sort()
	return facility_ids

func _waiting_point_in_query(world: WorldState, actor_id: String, facility_ids: Array, waiting: Variant = null) -> Dictionary:
	if waiting==null: waiting = _lookup(world).waiting
	for facility_id: String in facility_ids:
		var facility: Dictionary = world.facts.facilities[facility_id]
		if not facility.definition_id in WAITING_SEAT_DEFINITIONS:
			continue
		if not str(facility.get("room_id","")).is_empty() and not world.facts.rooms[facility.room_id].kind in ["waiting","public","lobby","garden"]:
			continue
		var layout: Dictionary = space.facility_layout(world,facility_id)
		if waiting.has(JSON.stringify([int(layout.floor_id),layout.patient_cell])):
			continue
		if _point_clear(world,actor_id,int(layout.floor_id),layout.patient_cell) and space.route(world,actor_id,int(layout.floor_id),layout.patient_cell,[],{},true).ok:
			return {"floor_id":int(layout.floor_id),"cell":layout.patient_cell.duplicate()}
	return {}

func _bedside(world: WorldState, actor_id: String, stay: Dictionary) -> Dictionary:
	space.begin_route_query(world,{},space.nominal_query(world))
	var result: Dictionary = _bedside_in_query(world,actor_id,stay)
	space.end_route_query()
	return result

func _bedside_in_query(world: WorldState, actor_id: String, stay: Dictionary) -> Dictionary:
	# Medical work takes priority; keep an unstarted visit in public waiting.
	if not bool(stay.care_completed):
		return {}
	for session: Dictionary in world.facts.sessions.values():
		if session.facility_id==stay.bed_id and session.kind in ["care","round"]:
			return {}
	var bed: Dictionary = space.facility_layout(world,stay.bed_id)
	var ward: Dictionary = world.facts.rooms[bed.room_id]
	var actor: Dictionary = world.facts.actors[actor_id]
	var k: int = space.clearance(actor)
	var room_rect: Rect2 = Rect2(float(ward.origin[0]),float(ward.origin[1]),float(ward.size[0]),float(ward.size[1]))
	var candidates: Array = [[int(bed.cell[0])+int(bed.footprint[0]),int(bed.cell[1])+1],[int(bed.cell[0])-k,int(bed.cell[1])+int(bed.footprint[1])-k]]
	for point: Array in candidates:
		var rectangle: Rect2 = space._actor_rect(actor,Vector2(float(point[0]),float(point[1])))
		if not room_rect.encloses(rectangle) or not _point_clear(world,actor_id,int(bed.floor_id),point):
			continue
		var compatible: bool = true
		for operator_cell: Array in bed.operator_cells:
			compatible = compatible and not rectangle.intersects(Rect2(float(operator_cell[0]),float(operator_cell[1]),1,1),false)
		if compatible and space.route(world,actor_id,int(bed.floor_id),point,[],{},true).ok:
			return {"floor_id":int(bed.floor_id),"cell":point}
	return {}

func _point_clear(world: WorldState, actor_id: String, floor_id: int, cell: Array) -> bool:
	var actor: Dictionary = world.facts.actors[actor_id]
	return space.static_reason(world,actor,floor_id,Vector2i(int(cell[0]),int(cell[1]))).is_empty() and space._dynamic_clear(world,actor_id,floor_id,space._actor_rect(actor,Vector2(float(cell[0]),float(cell[1]))))

func _lookup(world: WorldState) -> Dictionary:
	var result: Dictionary = {"wards":{},"present":{},"waiting":{}}
	for stay: Dictionary in world.facts.ward_stays.values():
		var id: String = str(world.facts.attempts[stay.attempt_id].visit_id)
		if not result.wards.has(id): result.wards[id] = stay
	for stay: Dictionary in world.facts.visitors.stays.values():
		if not result.present.has(stay.visit_id): result.present[stay.visit_id] = stay
		result.waiting[JSON.stringify([int(stay.waiting_floor),stay.waiting_cell])] = true
	return result

func _ward_stay(world: WorldState, visit_id: String) -> Dictionary:
	for stay: Dictionary in world.facts.ward_stays.values():
		if world.facts.attempts[stay.attempt_id].visit_id==visit_id:
			return stay
	return {}

func _present(world: WorldState, visit_id: String) -> Dictionary:
	var records: Dictionary = world.facts.visitors.stays
	var changed: Array = world.pending_fact_ids(_present_observer,"visitor_stays",records,self)
	if _present_world!=world or not is_same(_present_records,records) or _present_count!=records.size() or not changed.is_empty():
		_present_world = world
		_present_records = records
		_present_count = records.size()
		_present_groups.clear()
		for id: String in records:
			var owner: String = str(records[id].visit_id)
			if not _present_groups.has(owner): _present_groups[owner] = []
			_present_groups[owner].append(id)
	for id: String in _present_groups.get(visit_id,[]):
		if records.has(id) and records[id].visit_id==visit_id: return records[id]
	return {}

func _stay_ids(world: WorldState) -> Array:
	var ids: Array = world.facts.visitors.stays.keys()
	ids.sort()
	return ids

func _window(world: WorldState) -> String:
	return str(world.sim_tick/WorldState.TICKS_PER_DAY)+":"+str((world.sim_tick%WorldState.TICKS_PER_DAY)/_ticks(content.balance.schedule.shift_seconds))

func _ticks(seconds: Variant) -> int:
	return ceili(float(seconds)/WorldState.TICK_SECONDS)

func validate(world: WorldState) -> String:
	if not world.facts.has("visitors"):
		return ""
	var state: Variant = world.facts.visitors
	if not state is Dictionary or not state.get("requests") is Dictionary or not state.get("stays") is Dictionary or not WorldState._natural(state.get("next_scan_tick",-1)):
		return "家属请求与在院事实结构无效"
	var visits: Dictionary = {}
	for id: String in state.stays:
		var stay: Variant = state.stays[id]
		if not stay is Dictionary or stay.get("id")!=id or not world.facts.actors.has(stay.get("actor_id","")) or not world.facts.visits.has(stay.get("visit_id","")) or visits.has(stay.visit_id):
			return "同次就诊的家属身份或实际在院占用无效"
		if not stay.get("phase","") in ["to_waiting","waiting","to_bed","visiting","yielding","leaving"] or not WorldState._natural(stay.get("remaining_ticks",-1)):
			return "家属实际阶段或剩余探视时间无效"
		visits[stay.visit_id] = true
	for id: String in state.requests:
		var request: Variant = state.requests[id]
		if not request is Dictionary or request.get("id")!=id or not world.facts.visits.has(request.get("visit_id","")) or not request.get("purpose","") in ["companion","ward_visit"] or not WorldState._natural(request.get("request_tick",-1)):
			return "院外家属请求引用无效"
	return ""
