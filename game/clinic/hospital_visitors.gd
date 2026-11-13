class_name HospitalVisitors
extends RefCounted

const WAITING_SEAT_DEFINITIONS: Array[String] = ["FUR09","FUR10","FUR11","FUR12","FUR13","FUR14","FUR15","FUR16","FUR49","FUR50","FUR51","FUR52"]

var content: HospitalContent
var space: HospitalSpace
var waiting_scope: HospitalClinicWaitingScope
var waiting_life: WeakRef
var _present_world: WorldState
var _present_records: Dictionary = {}
var _present_count: int = -1
var _present_groups: Dictionary = {}
var _present_observer: String = "visitor_lookup_"+str(get_instance_id())

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry
	waiting_scope = HospitalClinicWaitingScope.new(geometry)

func ensure(world: WorldState) -> void:
	if not world.facts.has("visitors"):
		world.facts.visitors = {"requests":{},"stays":{},"next_scan_tick":0}

func admission(world: WorldState, visit: Dictionary, ward: Dictionary) -> void:
	ensure(world)
	if ward.get("companion_evaluated",false): return
	ward.companion_evaluated=true
	ward.companion_qualified=world.draw("arrival",10000)<roundi(float(content.balance.ward_care.companion_probability)*10000)
	ward.companion_actor_id=""
	ward.visitor_day=-1
	ward.visitor_intent=false
	ward.visitor_requested=false

func _daytime(world: WorldState) -> bool:
	return world.sim_tick%WorldState.TICKS_PER_DAY<_ticks(content.balance.schedule.shift_seconds)*2

func arrivals(world: WorldState) -> void:
	ensure(world)
	if world.sim_tick<int(world.facts.visitors.next_scan_tick): return
	world.facts.visitors.next_scan_tick=world.sim_tick+_ticks(content.balance.ward_care.visitor_request_scan_seconds)
	for visit_id: String in world.active_visit_ids():
		var visit: Dictionary=world.facts.visits[visit_id]
		var ward: Dictionary=_ward_stay(world,visit_id)
		if ward.is_empty() or not ward.has("admitted_tick") or visit.phase in ["leaving","departed","ward_referral"]: continue
		if not _daytime(world): continue
		var day: int=world.sim_tick/WorldState.TICKS_PER_DAY
		if int(ward.visitor_day)!=day:
			ward.visitor_day=day
			ward.visitor_intent=world.draw("arrival",10000)<roundi(float(content.balance.ward_care.ward_visit_probability)*10000)
			ward.visitor_requested=false
		if ward.companion_qualified and _role(world,visit_id,"companion").get("phase","outside")=="outside": _request(world,visit,"companion",str(day))
		if ward.visitor_intent and not ward.visitor_requested and bool(visit.get("visitor_consent",true)):
			if _role(world,visit_id,"ward_visit").is_empty():
				_request(world,visit,"ward_visit",str(day))
				ward.visitor_requested=true
	var ids: Array=world.facts.visitors.requests.keys()
	ids.sort()
	for id: String in ids:
		var request: Dictionary=world.facts.visitors.requests[id]
		var visit: Dictionary=world.facts.visits[request.visit_id]
		var ward: Dictionary=_ward_stay(world,visit.id)
		if ward.is_empty() or visit.phase in ["leaving","departed","ward_referral"] or not _daytime(world) or request.purpose=="ward_visit" and (not bool(visit.get("visitor_consent",true)) or request.window!=str(world.sim_tick/WorldState.TICKS_PER_DAY)):
			world.facts.visitors.requests.erase(id)
			continue
		if _admit(world,visit,request): world.facts.visitors.requests.erase(id)

func _request(world: WorldState, visit: Dictionary, purpose: String, window: String) -> void:
	var id: String=visit.id+":"+purpose
	var existing: Dictionary=world.facts.visitors.requests.get(id,{})
	if existing.is_empty() or existing.window!=window:
		world.facts.visitors.requests[id]={"id":id,"visit_id":visit.id,"purpose":purpose,"window":window,"request_tick":world.sim_tick}

func _role(world: WorldState, visit_id: String, purpose: String) -> Dictionary:
	for stay: Dictionary in world.facts.visitors.stays.values():
		if stay.visit_id==visit_id and stay.purpose==purpose: return stay
	return {}

func _admit(world: WorldState, visit: Dictionary, request: Dictionary, _lookup_unused: Dictionary = {}) -> bool:
	var ward: Dictionary=_ward_stay(world,visit.id)
	if ward.is_empty(): return false
	var existing: Dictionary=_role(world,visit.id,str(request.purpose))
	if not existing.is_empty() and existing.phase!="outside": return false
	var original: String=str(ward.companion_actor_id) if request.purpose=="companion" else ""
	var patient: Dictionary=world.facts.actors[visit.actor_id]
	var entry: Dictionary=world.facts.get("entry",{"floor_id":1,"cell":[47,93]})
	var actor: Dictionary=world.facts.actors[original].duplicate(true) if not original.is_empty() else {"id":"relative_probe","name":str(patient.name)+("的陪同家属" if request.purpose=="companion" else "的探视家属"),"species_id":patient.species_id,"relative_of":visit.actor_id,"facing":0.0,"posture":"standing"}
	actor.location={"kind":"floor","floor_id":int(entry.floor_id),"cell":entry.cell.duplicate(),"height_m":0.0}
	if not space.static_reason(world,actor,int(entry.floor_id),Vector2i(roundi(entry.cell[0]),roundi(entry.cell[1]))).is_empty() or not space._dynamic_clear(world,actor.id,int(entry.floor_id),space.body_rectangle(actor)): return false
	var facts: Dictionary=world.facts.duplicate()
	facts.actors=world.facts.actors.duplicate()
	facts.actors[actor.id]=actor
	var point: Dictionary=_waiting_point(WorldState.new(facts),actor.id)
	if point.is_empty(): return false
	var actor_id: String=original if not original.is_empty() else world.new_id("relative")
	actor.id=actor_id
	if not actor.has("personality_id"): actor.personality_id=content.catalog.patient_personalities[world.draw("personality",content.catalog.patient_personalities.size())].id
	world.facts.actors[actor_id]=actor
	if request.purpose=="companion": ward.companion_actor_id=actor_id
	var id: String=str(existing.id) if not existing.is_empty() else world.new_id("visitor")
	var stay: Dictionary={"id":id,"visit_id":visit.id,"actor_id":actor_id,"purpose":request.purpose,"phase":"waiting","remaining_ticks":_ticks(content.balance.hospital_situations.ward_visit_seconds) if request.purpose=="ward_visit" else 0,"waiting_floor":point.floor_id,"waiting_cell":point.cell,"next_need_tick":world.sim_tick+_ticks(content.balance.amenity_flow.first_need_seconds),"next_purpose":"toilet","life_task":{},"return_ward_first":false,"yielding":false,"public_use":{"id":id,"actor_id":actor_id,"public_purpose":"seat","mode":"auto","area":point.area,"facility_id":"","arrived_tick":-1,"phase":"area_travel","started_tick":world.sim_tick}}
	world.facts.visitors.stays[id]=stay
	world.fact_record_changed("visitor_stays",id)
	space.sync_actor(world,actor_id)
	space.public_areas.changed(world)
	return true

func dispatch(world: WorldState) -> void:
	ensure(world)
	for request_id: String in world.facts.visitors.requests.keys():
		var request: Dictionary=world.facts.visitors.requests[request_id]
		var owner: Dictionary=world.facts.visits.get(str(request.visit_id),{})
		if owner.is_empty() or _terminal(owner,_ward_stay(world,str(request.visit_id))):
			world.facts.visitors.requests.erase(request_id)
	for id: String in _stay_ids(world):
		var stay: Dictionary=world.facts.visitors.stays[id]
		var visit: Dictionary=world.facts.visits[stay.visit_id]
		var actor: Dictionary=world.facts.actors[stay.actor_id]
		if LiftController.pending_holds(world,str(stay.actor_id)): continue
		var ward: Dictionary=_ward_stay(world,visit.id)
		var terminal: bool=_terminal(visit,ward)
		if terminal:
			stay.remaining_ticks=0
			if stay.phase!="outside": stay.phase="leaving"
			stay.return_ward_first=false
		if stay.phase=="outside":
			if terminal: _retire(world,stay)
			continue
		if not stay.life_task.is_empty():
			_dispatch_life(world,stay,terminal)
			continue
		if stay.phase=="leaving":
			_depart(world,stay,terminal)
			continue
		if stay.purpose=="ward_visit" and not bool(visit.get("visitor_consent",true)):
			stay.phase="leaving"
			continue
		var away: bool=ward.phase in ["to_surgery","reserved","transfer","return_preop"]
		if stay.purpose=="companion" and not _daytime(world) and not away and _inside_ward(world,visit.actor_id,ward) and not stay.return_ward_first:
			stay.phase="leaving"
			continue
		if stay.purpose=="companion" and _join_patient_lift(world,stay,visit): continue
		var medical: bool=_medical_work(world,ward)
		if stay.yielding and not medical:
			var yielding_move: Dictionary=world.facts.moves.get(actor.id,{})
			if stay.get("destination",{}).get("kind","")=="ward_outside" and yielding_move.get("visitor_stay_id","")==stay.id and not _cancel_optional_ground(world,actor.id): continue
			stay.yielding=false
		if medical: stay.yielding=true
		if stay.purpose=="companion" and waiting_life!=null and waiting_life.get_ref()!=null and world.sim_tick>=int(stay.next_need_tick) and not stay.return_ward_first and not stay.yielding and not world.facts.moves.has(actor.id):
			_begin_life(world,stay)
			continue
		var target: Dictionary={}
		var target_kind: String="ward"
		var target_facility: String=str(ward.bed_id)
		if stay.yielding: target_kind="ward_outside"
		elif stay.return_ward_first: target_kind="ward_return"
		elif ward.phase in ["to_surgery","reserved"]:
			target_kind="surgery_outside"
			var preparation: Dictionary=world.facts.preparations.get(visit.id,{})
			var attempt: Dictionary=world.facts.attempts.get(str(ward.attempt_id),{})
			target_facility=str(preparation.get("facility_id",attempt.get("facility_id","")))
		var destination: Dictionary=stay.get("destination",{})
		if destination.get("kind","")==target_kind and destination.get("facility_id","")==target_facility and space.movement_failure(world,actor.id).is_empty():
			target=destination
		elif not target_facility.is_empty():
			target=_outside_point(world,stay,target_facility) if target_kind in ["ward_outside","surgery_outside"] else _bedside(world,actor.id,ward)
		if target.is_empty():
			stay.waiting_reason="等待合法家属站位及真实通路"
			var movement: Dictionary=world.facts.moves.get(actor.id,{})
			if movement.get("visitor_stay_id","")==stay.id and not _cancel_optional_ground(world,actor.id): continue
			stay.phase="waiting"
			_public_waiting(world,stay)
			continue
		_leave_public_seat(world,stay)
		if _travel(world,stay,target,target_kind,target_facility):
			stay.phase="visiting" if not away and not stay.yielding else "waiting"
			if stay.return_ward_first and not stay.yielding and _inside_ward(world,actor.id,ward):
				stay.return_ward_first=false
				stay.phase="waiting"
		else: stay.phase="walking"

func _terminal(visit: Dictionary, ward: Dictionary) -> bool:
	return ward.is_empty() or visit.get("phase","") in ["leaving","departed","ward_referral"]

func _outside_point(world: WorldState, stay: Dictionary, facility_id: String) -> Dictionary:
	var avoid: Rect2
	var floor_id: int=int(world.facts.facilities[facility_id].floor_id)
	for other: Dictionary in world.facts.visitors.stays.values():
		if other.id==stay.id or other.visit_id!=stay.visit_id: continue
		var destination: Dictionary=other.get("destination",{})
		if int(destination.get("floor_id",-1))!=floor_id or not destination.has("cell") or not other.life_task.is_empty(): continue
		avoid=space._actor_rect(world.facts.actors[other.actor_id],Vector2(float(destination.cell[0]),float(destination.cell[1])))
	return waiting_scope.point(world,stay.actor_id,facility_id,avoid)

# A companion finishes an active life/safe-release action before dispatch
# reaches this handoff. Both owners then walk their own real cross-floor route;
# the landing queue admits them together only after actual rendezvous.
func _join_patient_lift(world: WorldState, stay: Dictionary, visit: Dictionary) -> bool:
	var patient: Dictionary=world.facts.actors.get(visit.get("actor_id",""),{})
	if patient.get("location",{}).get("kind")!="floor": return false
	var journey: Dictionary=world.facts.moves.get(patient.get("id",""),{})
	if journey.is_empty():
		for m: Dictionary in world.facts.moves.values():
			if patient.get("id","") in m.get("members",[]): journey=m;break
	if journey.is_empty(): return false
	var trip: Dictionary=HospitalTransit.journey(journey)
	if trip.is_empty() or int(trip.from)!=int(patient.location.floor_id): return false
	var connection: Dictionary=world.facts.connectors.get(trip.connector_id,{})
	if connection.is_empty() or content.definition("vertical_connectors",connection.definition_id).kind!="lift": return false
	var companion_location: Dictionary=world.facts.actors[stay.actor_id].location
	if companion_location.kind=="floor" and int(companion_location.floor_id)!=int(trip.from):
		_travel(world,stay,{"floor_id":int(trip.from),"cell":connection.anchor.duplicate()},"companion_rendezvous")
		stay.waiting_reason="先实际到患者所在楼层会合"
		return true
	var own: Dictionary=world.facts.moves.get(stay.actor_id,{})
	var own_trip: Dictionary=HospitalTransit.journey(own)
	if own_trip==trip and own.get("visitor_stay_id","")==stay.id: return true
	var cell: Array=journey.target_cell if int(journey.target_floor)==int(trip.to) else connection.anchor
	_travel(world,stay,{"floor_id":int(trip.to),"cell":cell.duplicate()},"companion_transit")
	stay.waiting_reason="沿真实路线与患者会合候梯"
	return true

func _cancel_optional_ground(world: WorldState, actor_id: String) -> bool:
	var movement: Dictionary=world.facts.moves.get(actor_id,{})
	if movement.has("detour") or movement.has("local_move") or movement.has("convoy") or movement.get("members",[actor_id])!=[actor_id]: return false
	return space.cancel_ground_move(world,actor_id)

# A family journey owns only its own optional ground movement. Transit,
# convoys and local safety detours finish before a destination can change.
func _travel(world: WorldState, stay: Dictionary, target: Dictionary, kind: String, facility_id: String = "") -> bool:
	var actor_id: String=str(stay.actor_id)
	var movement: Dictionary=world.facts.moves.get(actor_id,{})
	if not movement.is_empty():
		if movement.get("visitor_stay_id","")!=stay.id and not _owns_public_move(world,stay): return false
		if int(movement.target_floor)==int(target.floor_id) and movement.target_cell==target.cell:
			stay.destination={"kind":kind,"facility_id":facility_id,"floor_id":int(target.floor_id),"cell":target.cell.duplicate()}
			return false
		if not _cancel_optional_ground(world,actor_id): return false
	stay.destination={"kind":kind,"facility_id":facility_id,"floor_id":int(target.floor_id),"cell":target.cell.duplicate()}
	if space.at(world,actor_id,int(target.floor_id),target.cell): return true
	stay.waiting_reason=space.request_move(world,actor_id,int(target.floor_id),target.cell)
	var accepted: Dictionary=world.facts.moves.get(actor_id,{})
	if stay.waiting_reason.is_empty() and not accepted.is_empty(): accepted.visitor_stay_id=stay.id
	return false

func advance(world: WorldState) -> void:
	for id: String in _stay_ids(world):
		var stay: Dictionary=world.facts.visitors.stays[id]
		if not stay.life_task.is_empty():
			if waiting_life!=null and waiting_life.get_ref()!=null and stay.life_task.phase in ["using","fallback"]:
				waiting_life.get_ref().advance_actor_need(world,stay.actor_id,stay.life_task)
			continue
		if stay.purpose!="ward_visit" or stay.phase in ["outside","leaving"] or stay.yielding: continue
		var ward: Dictionary=_ward_stay(world,stay.visit_id)
		var visit: Dictionary=world.facts.visits[stay.visit_id]
		if _terminal(visit,ward) or ward.phase in ["to_surgery","reserved","transfer","return_preop"] or _medical_work(world,ward) or not _inside_ward(world,visit.actor_id,ward) or not _inside_ward(world,stay.actor_id,ward): continue
		stay.remaining_ticks=maxi(0,int(stay.remaining_ticks)-1)
		if stay.remaining_ticks==0: stay.phase="leaving"

func _medical_work(world: WorldState, ward: Dictionary) -> bool:
	for session: Dictionary in world.facts.sessions.values():
		if session.visit_id==ward.visit_id and session.kind in ["care","outpatient"] and int(world.facts.facilities[session.facility_id].floor_id)==int(world.facts.facilities[ward.bed_id].floor_id) and world.facts.facilities[session.facility_id].get("room_id","")==world.facts.facilities[ward.bed_id].get("room_id",""): return true
	# Clinical dispatch follows family dispatch. A request from the previous
	# boundary is the live handoff until the caller renews it or starts work.
	# An unfinished future care task alone never excludes family from a room.
	for stay: Dictionary in world.facts.visitors.stays.values():
		if stay.visit_id==ward.visit_id and stay.get("yielding",false) and int(stay.get("yield_requested_tick",-2))>=world.sim_tick-1: return true
	return false

func _inside_ward(world: WorldState, actor_id: String, ward: Dictionary) -> bool:
	var bed: Dictionary=world.facts.facilities[ward.bed_id]
	var actor: Dictionary=world.facts.actors[actor_id]
	return actor.location.kind=="floor" and int(actor.location.floor_id)==int(bed.floor_id) and space.room_contains(world.facts.rooms[bed.room_id],space.body_rectangle(actor))

func _overlaps_ward(world: WorldState, actor_id: String, ward: Dictionary) -> bool:
	var bed: Dictionary=world.facts.facilities[ward.bed_id]
	var actor: Dictionary=world.facts.actors[actor_id]
	if actor.location.kind!="floor" or int(actor.location.floor_id)!=int(bed.floor_id): return false
	var room: Dictionary=world.facts.rooms[bed.room_id]
	var body: Rect2=space.body_rectangle(actor)
	if not room.has("cells"): return body.intersects(Rect2(float(room.origin[0]),float(room.origin[1]),float(room.size[0]),float(room.size[1])),false)
	for cell: Array in room.cells:
		if body.intersects(Rect2(float(cell[0]),float(cell[1]),1,1),false): return true
	return false

func yield_for_care(world: WorldState, visit_id: String) -> bool:
	var ward: Dictionary=_ward_stay(world,visit_id)
	if ward.is_empty(): return true
	var clear: bool=true
	for stay: Dictionary in world.facts.visitors.stays.values():
		if stay.visit_id!=visit_id or stay.phase=="outside": continue
		stay.yielding=true
		stay.yield_requested_tick=world.sim_tick
		if _overlaps_ward(world,stay.actor_id,ward): clear=false
		if not stay.life_task.is_empty(): continue
		# A body already outside may still own an inbound room journey. Change
		# that optional ground destination before medical work starts; transit
		# and safety segments remain with movement's existing owner.
		var point: Dictionary=_outside_point(world,stay,str(ward.bed_id))
		if not point.is_empty(): _travel(world,stay,point,"ward_outside",str(ward.bed_id))
	return clear

func _depart(world: WorldState, stay: Dictionary, terminal: bool) -> void:
	_leave_public_seat(world,stay)
	var actor: Dictionary=world.facts.actors[stay.actor_id]
	if actor.location.kind=="outside":
		if terminal or stay.purpose=="ward_visit": _retire(world,stay)
		else: stay.phase="outside"
		return
	var exit: Array=space.exit_cell(world,actor)
	if space.at(world,actor.id,1,exit):
		if not _cancel_optional_ground(world,actor.id): return
		actor.location={"kind":"outside"}
		space.sync_actor(world,actor.id)
		if terminal or stay.purpose=="ward_visit": _retire(world,stay)
		else: stay.phase="outside"
	else: _travel(world,stay,{"floor_id":1,"cell":exit},"exit")

func _retire(world: WorldState, stay: Dictionary) -> void:
	if not space.forget_actor(world,str(stay.actor_id)): return
	var ward: Dictionary=_ward_stay(world,stay.visit_id)
	if not ward.is_empty() and str(ward.get("companion_actor_id",""))==str(stay.actor_id): ward.companion_actor_id=""
	world.facts.visitors.stays.erase(stay.id)
	world.facts.actors.erase(stay.actor_id)
	world.fact_record_changed("visitor_stays",str(stay.id))
	space.public_areas.changed(world)

func _begin_life(world: WorldState, stay: Dictionary) -> void:
	_leave_public_seat(world,stay)
	stay.life_task={"id":stay.id+":life:"+str(world.sim_tick),"owner_kind":"visitor","actor_id":stay.actor_id,"purpose":stay.next_purpose,"public_purpose":stay.next_purpose,"phase":"seek","facility_id":"","area":{},"arrived_tick":-1,"remaining_ticks":0,"queued_ticks":0,"started_tick":world.sim_tick,"mode":"auto","return_to":{},"return_area":{},"scene_id":""}
	stay.return_ward_first=true
	stay.erase("destination")
	space.public_areas.changed(world)

func _dispatch_life(world: WorldState, stay: Dictionary, terminal: bool = false) -> void:
	if waiting_life==null or waiting_life.get_ref()==null: return
	var need: Dictionary=stay.life_task
	var cancelled_pending: bool=terminal and need.phase!="using" and not need.has("use_started_tick") and not need.has("completed_tick")
	if cancelled_pending:
		# A planned facility is not a held service. Finish real transit/safety
		# first, then hand this same body to departure without an extra stop.
		if not _cancel_optional_ground(world,stay.actor_id): return
		need.phase="returning"
	elif terminal and not need.phase in ["using","returning"]:
		if not _cancel_optional_ground(world,stay.actor_id): return
		need.phase="returning"
	if need.phase=="returning":
		if not cancelled_pending and not waiting_life.get_ref().finish_actor_need(world,stay.actor_id,need): return
		waiting_life.get_ref().toilets.leave(world,stay.actor_id)
		stay.life_task={}
		stay.next_need_tick=world.sim_tick+_ticks(content.balance.amenity_flow.cooldown_seconds)
		stay.next_purpose="water" if need.purpose=="toilet" else "toilet"
		space.public_areas.changed(world)
		return
	waiting_life.get_ref().dispatch_actor_need(world,stay.actor_id,need)

func _leave_public_seat(world: WorldState, stay: Dictionary) -> void:
	var actor: Dictionary = world.facts.actors[stay.actor_id]
	var changed: bool = actor.get("posture","")=="seated" or stay.public_use.phase!="away" or not str(stay.public_use.get("facility_id","")).is_empty()
	if actor.get("posture","")=="seated":
		actor.posture = "standing"
		actor.erase("support_facility_id")
		space.sync_actor(world,actor.id)
	stay.public_use.phase = "away"
	stay.public_use.facility_id = ""
	if changed: space.public_areas.changed(world)

func _public_waiting(world: WorldState, stay: Dictionary) -> bool:
	var actor: Dictionary = world.facts.actors[stay.actor_id]
	var intent: Dictionary = stay.public_use
	var waiting_for_area: bool = intent.phase=="local_wait" and intent.area.is_empty()
	if _yielded_seat(world,intent).is_empty(): intent.erase("yielded_seat")
	var failed: Dictionary = space.movement_failure(world,actor.id)
	var valid: bool = space.public_areas.area_valid(world,intent.area,["waiting","waiting_area","public","lobby","garden",""])
	if not failed.is_empty() or not valid:
		if world.facts.moves.has(actor.id) and not _cancel_public_move(world,stay): return false
		if intent.phase=="seated": _leave_public_seat(world,stay)
		if intent.phase=="area_travel" or not valid: intent.area = {}; intent.arrived_tick = -1
		intent.facility_id = ""
		intent.phase = "area_travel" if intent.area.is_empty() else "local_wait"
		space.public_areas.changed(world)
	_stop_lost_seat_trip(world,stay)
	if actor.location.kind!="floor": return false
	if intent.phase=="area_travel":
		space.public_areas.try_finish_arrival(world,actor.id,intent.area,"waiting_seat_id",str(intent.id))
	# A fully entered owner can replace its still-running entrance with a real
	# chair route. Unrelated moves, safety detours and local chair walks continue.
	if world.facts.moves.has(actor.id) and not _owns_public_arrival(world,stay): return false
	if intent.phase=="yielding":
		intent.phase = "local_wait"
		space.public_areas.changed(world)
		return _public_wait_position(world,stay)
	if intent.phase=="seated" and world.facts.facilities.has(intent.facility_id): return true
	# Optional chairs have no failed-choice dependencies. Settled waiting uses
	# the ordinary behavior scan; physical movement/safe stops are handled above.
	if (waiting_for_area or (intent.phase=="local_wait" and int(intent.arrived_tick)>=0)) and world.sim_tick%_ticks(content.balance.patient_behavior.scan_seconds)!=0:
		if waiting_for_area: intent.phase = "local_wait"
		return _public_wait_position(world,stay)
	var selected_entry: Dictionary = {}
	if not world.facts.moves.has(actor.id) and (space.public_areas.region(world,intent.area).is_empty() or space.public_areas.facilities(world,intent.area,WAITING_SEAT_DEFINITIONS).is_empty() or (space.public_areas.contains(world,intent.area,actor.id) and not space.public_areas.compatible_geometry(world,intent.area,WAITING_SEAT_DEFINITIONS,[actor.id]))):
		var selected: Dictionary = space.public_areas.select(world,actor.id,WAITING_SEAT_DEFINITIONS,["waiting","waiting_area","public","lobby","garden",""],"seat")
		# A missing optional chair is not a missing public waiting place.
		# Keep the admitted standing destination until actual arrival; otherwise
		# choose a permitted, reachable point using this visitor's own body.
		if selected.is_empty() and valid:
			selected = space.public_areas.arrival_point(world,actor.id,intent.area)
			if not selected.is_empty(): selected.area = intent.area
		if selected.is_empty(): selected = _standing_point(world,actor.id)
		if selected.is_empty():
			intent.area = {}
			intent.arrived_tick = -1
			intent.phase = "local_wait"
			return _public_wait_position(world,stay)
		if intent.area!=selected.area: intent.arrived_tick = -1
		intent.area = selected.area
		selected_entry = selected
		space.public_areas.changed(world)
	if not space.public_areas.contains(world,intent.area,actor.id):
		var entry: Dictionary = selected_entry
		if entry.is_empty(): entry = space.public_areas.arrival_point(world,actor.id,intent.area)
		if not entry.is_empty():
			stay.waiting_floor = entry.floor_id
			stay.waiting_cell = entry.cell
			_request_public_move(world,stay,int(entry.floor_id),entry.cell)
		return false
	if int(intent.arrived_tick)<0 and not world.facts.moves.has(actor.id) and space.public_areas.safe_wait(world,actor.id,int(actor.location.floor_id),actor.location.cell):
		intent.arrived_tick = world.sim_tick
		space.public_areas.changed(world)
	if intent.phase=="local_travel" and not str(intent.get("facility_id","")).is_empty():
		space.begin_dynamic_route_query(world)
		var current: String = str(intent.facility_id)
		var quote: Dictionary = _public_seat_quote(world,stay,current) if current in space.public_areas.facilities(world,intent.area,WAITING_SEAT_DEFINITIONS) else {}
		space.end_route_query()
		if not quote.is_empty():
			if _take_waiting_seat(world,stay,quote): return true
			if world.facts.moves.has(actor.id): return false
		intent.facility_id = ""
		space.public_areas.changed(world)
	if not world.facts.moves.has(actor.id): intent.phase = "local_wait"
	# Queue fits and exit witnesses belong to this visitor's read-only choice,
	# including nested trip quotes. End before any intent or resource commit.
	space.begin_dynamic_route_query(world)
	for id: String in space.public_areas.facilities(world,intent.area,WAITING_SEAT_DEFINITIONS):
		var quote: Dictionary = _public_seat_quote(world,stay,id)
		if quote.is_empty(): continue
		space.end_route_query()
		if _take_waiting_seat(world,stay,quote): return true
		if world.facts.moves.has(actor.id): return false
		# A failed commit continues in the original order, with fresh live views.
		space.begin_dynamic_route_query(world)
	space.end_route_query()
	intent.facility_id = ""
	if not world.facts.moves.has(actor.id): intent.phase = "local_wait"
	return _public_wait_position(world,stay)

# The existing optional-trip marker is cleared by every movement retarget,
# even an identical destination. Never infer ownership from target equality.
func _owns_public_move(world: WorldState, stay: Dictionary) -> bool:
	var actor_id: String = str(stay.actor_id)
	var movement: Dictionary = world.facts.moves.get(actor_id,{})
	if movement.is_empty() or movement.get("waiting_seat_id","")!=stay.public_use.id: return false
	if movement.has("detour") or movement.has("local_move") or movement.has("convoy") or movement.get("members",[actor_id])!=[actor_id]: return false
	var actor: Dictionary = world.facts.actors[actor_id]
	if actor.location.kind!="floor" or actor.get("posture","")=="lying": return false
	var cursor: int = int(movement.cursor)
	return cursor<0 or cursor>=movement.path.size() or movement.path[cursor].kind=="floor"

func _owns_public_arrival(world: WorldState, stay: Dictionary) -> bool:
	return stay.public_use.phase=="area_travel" and _owns_public_move(world,stay) and space.public_areas.contains(world,stay.public_use.area,stay.actor_id)

func _cancel_public_move(world: WorldState, stay: Dictionary) -> bool:
	return _owns_public_move(world,stay) and space.cancel_ground_move(world,stay.actor_id)

func _request_public_move(world: WorldState, stay: Dictionary, floor_id: int, cell: Array) -> bool:
	if world.facts.moves.has(stay.actor_id) and not _owns_public_arrival(world,stay): return false
	var previous: Dictionary = world.facts.moves.get(stay.actor_id,{})
	if not previous.is_empty() and int(previous.target_floor)==floor_id and previous.target_cell==cell: return true
	var reason: String = space.request_move(world,stay.actor_id,floor_id,cell)
	var movement: Dictionary = world.facts.moves.get(stay.actor_id,{})
	if not reason.is_empty() or movement.is_empty() or int(movement.target_floor)!=floor_id or movement.target_cell!=cell: return false
	movement.waiting_seat_id = stay.public_use.id
	return true

# Only this optional trip may stop after someone else physically takes its chair.
# Retargeting, including an identical destination, clears waiting_seat_id in
# HospitalMovement. Safety maneuvers and real support/transit exits finish first.
func _stop_lost_seat_trip(world: WorldState, stay: Dictionary) -> void:
	var intent: Dictionary = stay.public_use
	if intent.phase!="local_travel": return
	var facility_id: String = str(intent.get("facility_id",""))
	if facility_id.is_empty() or not world.facts.facilities.has(facility_id): return
	var movement: Dictionary = world.facts.moves.get(stay.actor_id,{})
	if movement.is_empty() or movement.get("waiting_seat_id","")!=intent.id: return
	if movement.has("detour") or movement.has("convoy") or movement.get("members",[stay.actor_id])!=[stay.actor_id]: return
	var layout: Dictionary = space.facility_layout(world,facility_id)
	if int(movement.target_floor)!=int(layout.floor_id) or movement.target_cell!=layout.patient_cell: return
	var user_id: String = str(world.facts.adaptations.get(facility_id,{}).get("actor_id",""))
	var other: Dictionary = world.facts.actors.get(user_id,{})
	var occupied: bool = user_id!=stay.actor_id and other.get("posture","")=="seated" and other.get("support_facility_id","")==facility_id
	if not occupied or not space.cancel_ground_move(world,stay.actor_id): return
	intent.facility_id = ""
	intent.phase = "local_wait"
	space.public_areas.changed(world)

func _public_wait_position(world: WorldState, stay: Dictionary) -> bool:
	var actor: Dictionary = world.facts.actors[stay.actor_id]
	var intent: Dictionary = stay.public_use
	var current: Dictionary = space.public_areas.current_area(world,actor.id)
	var permitted: bool = space.public_areas.area_valid(world,current,["waiting","waiting_area","public","lobby","garden",""])
	if not permitted or not space.public_areas.safe_wait(world,actor.id,int(actor.location.floor_id),actor.location.cell):
		var point: Dictionary = {}
		if space.public_areas.area_valid(world,intent.area,["waiting","waiting_area","public","lobby","garden",""]):
			point = space.public_areas.waiting_point(world,actor.id,intent.area)
		if point.is_empty() and space.public_areas.contains(world,intent.area,actor.id): return false
		if point.is_empty():
			point = _standing_point(world,actor.id)
			if not point.is_empty():
				intent.area = point.area
				intent.arrived_tick = -1
				space.public_areas.changed(world)
		if point.is_empty(): return false
		if _request_public_move(world,stay,int(point.floor_id),point.cell):
			stay.waiting_floor = point.floor_id
			stay.waiting_cell = point.cell
		return false
	if world.facts.moves.has(actor.id): return false
	if int(intent.arrived_tick)<0 and space.public_areas.contains(world,intent.area,actor.id):
		intent.arrived_tick = world.sim_tick
		space.public_areas.changed(world)
	stay.waiting_floor = int(actor.location.floor_id)
	stay.waiting_cell = actor.location.cell.duplicate()
	return true

func _public_seat_quote(world: WorldState, stay: Dictionary, facility_id: String) -> Dictionary:
	# This visitor voluntarily stepped aside for a real patient. Do not walk
	# straight back into that chair; it remains free for every other arrival.
	if _yielded_seat(world,stay.public_use)==facility_id: return {}
	if not space.public_areas.turn(world,stay.public_use,facility_id): return {}
	if not space.facility_reservation_reason(world,facility_id,str(stay.actor_id)).is_empty(): return {}
	var quote: Dictionary = space.facility_trip_quote(world,facility_id,str(stay.actor_id))
	return quote if quote.ok else {}

func _take_waiting_seat(world: WorldState, stay: Dictionary, quote: Dictionary) -> bool:
	var actor: Dictionary = world.facts.actors[stay.actor_id]
	var intent: Dictionary = stay.public_use
	if not space.at(world,actor.id,int(quote.floor_id),quote.cell) or world.facts.moves.has(actor.id):
		if _request_public_move(world,stay,int(quote.floor_id),quote.cell):
			intent.facility_id = quote.facility_id
			intent.phase = "local_travel"
			space.public_areas.changed(world)
		return false
	if not space._dynamic_clear(world,actor.id,int(quote.floor_id),space.body_rectangle(actor)): return false
	if not space.reserve_facility(world,quote.facility_id,actor.id,actor.id).is_empty(): return false
	actor.posture = "seated"
	actor.support_facility_id = quote.facility_id
	space.sync_actor(world,actor.id)
	intent.facility_id = quote.facility_id
	intent.phase = "seated"
	stay.waiting_floor = quote.floor_id
	stay.waiting_cell = quote.cell
	space.public_areas.changed(world)
	return true

func yield_seat(world: WorldState, facility_id: String, visit_id: String) -> bool:
	for stay: Dictionary in world.facts.visitors.stays.values():
		var intent: Dictionary = stay.public_use
		if intent.get("phase","")!="seated" or intent.get("facility_id","")!=facility_id or not stay.phase in ["waiting","to_waiting"]: continue
		var point: Dictionary = space.public_areas.waiting_point(world,stay.actor_id,intent.area)
		if point.is_empty(): return false
		_leave_public_seat(world,stay)
		intent.phase = "yielding"
		intent.yielded_seat = {"facility_id":facility_id,"visit_id":visit_id}
		stay.waiting_floor = point.floor_id
		stay.waiting_cell = point.cell
		space.request_move(world,stay.actor_id,int(point.floor_id),point.cell)
		return true
	return false

# A small courtesy owned by the yielding visitor, never a seat reservation or
# patient priority. It ends on use, cancellation, another target or departure.
func _yielded_seat(world: WorldState, intent: Dictionary) -> String:
	var offered: Dictionary = intent.get("yielded_seat",{})
	if offered.is_empty(): return ""
	var facility_id: String = str(offered.facility_id)
	if not world.facts.facilities.has(facility_id): return ""
	var patient: Dictionary = world.facts.visits.get(str(offered.visit_id),{})
	var ticket: Dictionary = world.facts.tickets.get(patient.get("ticket_id",""),{})
	if patient.is_empty() or not str(patient.get("phase","")).begins_with("wait_") or ticket.is_empty() or not ticket.get("pause_reasons",{}).is_empty() or int(ticket.get("called_tick",-1))>=0: return ""
	var target: Dictionary = world.facts.get("waiting_life",{}).get("seats",{}).get(str(offered.visit_id),{})
	if target.is_empty() or target.get("phase","")=="seated" or target.get("area",{})!=intent.get("area",{}): return ""
	# A shared public region does not authorize courtesy for a different clinic.
	# Reuse the same current guidance target and local-seat geometry as waiting.
	var guidance: Dictionary = world.facts.get("floor_guidance",{}).get("visits",{}).get(str(offered.visit_id),{})
	if not guidance.is_empty():
		if guidance.get("phase","")!="ready": return ""
		var clinic_id: String = str(guidance.get("target_id",""))
		if not clinic_id.is_empty() and not waiting_scope.allows_seat(world,str(patient.actor_id),clinic_id,facility_id): return ""
	if target.get("mode","")=="manual": return facility_id if str(target.get("manual_facility_id",""))==facility_id else ""
	return facility_id if str(target.get("facility_id","")) in ["",facility_id] else ""

func seated_facilities(world: WorldState) -> Array:
	var result: Array = []
	for stay: Dictionary in world.facts.visitors.stays.values():
		if stay.public_use.get("phase","")=="seated": result.append(str(stay.public_use.facility_id))
	return result

func _waiting_point(world: WorldState, actor_id: String) -> Dictionary:
	var point: Dictionary = space.public_areas.select(world,actor_id,WAITING_SEAT_DEFINITIONS,["waiting","waiting_area","public","lobby","garden",""],"seat")
	return point if not point.is_empty() else _standing_point(world,actor_id)

func _standing_point(world: WorldState, actor_id: String) -> Dictionary:
	return space.public_areas.select(world,actor_id,[],["waiting","waiting_area","public","lobby","garden",""],"waiting")

func _bedside(world: WorldState, actor_id: String, stay: Dictionary) -> Dictionary:
	space.begin_route_query(world,{},space.nominal_query(world))
	var result: Dictionary = _bedside_in_query(world,actor_id,stay)
	space.end_route_query()
	return result

func _bedside_in_query(world: WorldState, actor_id: String, stay: Dictionary) -> Dictionary:
	var bed: Dictionary=space.facility_layout(world,stay.bed_id)
	var ward: Dictionary=world.facts.rooms[bed.room_id]
	var actor: Dictionary=world.facts.actors[actor_id]
	for y: int in range(int(ward.origin[1]),int(ward.origin[1])+int(ward.size[1])):
		for x: int in range(int(ward.origin[0]),int(ward.origin[0])+int(ward.size[0])):
			var point: Array=[x,y]
			var body: Rect2=space._actor_rect(actor,Vector2(x,y))
			if not space.room_contains(ward,body) or not _point_clear(world,actor_id,int(bed.floor_id),point): continue
			var blocked: bool=false
			for facility_id: String in space.room_use.facilities(world,ward.id,["EQ05"]):
				var layout: Dictionary=space.facility_layout(world,facility_id)
				for post: Array in layout.operator_cells+[layout.patient_cell]:
					if body.intersects(Rect2(float(post[0]),float(post[1]),1,1).grow(1.0),false): blocked=true
			for door: Dictionary in HospitalSpace.floor_layout(world,int(bed.floor_id)).doors:
				var span: int=int(world.facts.adaptations.get(str(door.id),{}).get("span",door.span))
				if door.get("room_id","")==ward.id and body.intersects(space._door_rect(door,span).grow(1.0),false): blocked=true
			# The other family's immutable live trip is a choice hint, not a
			# reservation. Avoid sending both bodies to one permanent stop.
			for other: Dictionary in world.facts.visitors.stays.values():
				if other.actor_id==actor_id or not other.life_task.is_empty(): continue
				var movement: Dictionary=world.facts.moves.get(str(other.actor_id),{})
				if movement.get("visitor_stay_id","")!=other.id or int(movement.get("target_floor",-1))!=int(bed.floor_id): continue
				var destination: Array=movement.target_cell
				if body.intersects(space._actor_rect(world.facts.actors[other.actor_id],Vector2(float(destination[0]),float(destination[1]))),false): blocked=true
			if not blocked and space.can_reach(world,actor_id,int(bed.floor_id),point): return {"floor_id":int(bed.floor_id),"cell":point}
	return {}

func _point_clear(world: WorldState, actor_id: String, floor_id: int, cell: Array) -> bool:
	var actor: Dictionary = world.facts.actors[actor_id]
	return space.static_reason(world,actor,floor_id,Vector2i(int(cell[0]),int(cell[1]))).is_empty() and space._dynamic_clear(world,actor_id,floor_id,space._actor_rect(actor,Vector2(float(cell[0]),float(cell[1]))))

func _lookup(world: WorldState, include_present: bool = true) -> Dictionary:
	var result: Dictionary = {"wards":{},"present":{}}
	for stay: Dictionary in world.facts.ward_stays.values():
		var id: String = str(stay.visit_id)
		if not result.wards.has(id): result.wards[id] = stay
	if not include_present: return result
	for stay: Dictionary in world.facts.visitors.stays.values():
		if not result.present.has(stay.visit_id): result.present[stay.visit_id] = stay
	return result

func _ward_stay(world: WorldState, visit_id: String) -> Dictionary:
	for stay: Dictionary in world.facts.ward_stays.values():
		if stay.visit_id==visit_id:
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
	var actors: Dictionary = {}
	for id: String in state.stays:
		var stay: Variant = state.stays[id]
		if not stay is Dictionary or stay.get("id")!=id or not world.facts.actors.has(stay.get("actor_id","")) or not world.facts.visits.has(stay.get("visit_id","")) or visits.has(str(stay.visit_id)+":"+str(stay.get("purpose",""))):
			return "同次就诊的家属身份或实际在院占用无效"
		if not stay.get("phase","") in ["to_waiting","waiting","walking","visiting","yielding","leaving","outside"] or not WorldState._natural(stay.get("remaining_ticks",-1)):
			return "家属实际阶段或剩余探视时间无效"
		if not stay.get("purpose","") in ["companion","ward_visit"] or actors.has(stay.actor_id) or world.facts.staff.has(stay.actor_id): return "家属角色或本人身份互斥无效"
		actors[stay.actor_id]=true
		if not stay.get("life_task") is Dictionary or not stay.get("return_ward_first") is bool or not stay.get("yielding") is bool: return "家属生活交接或医疗让位事实无效"
		if stay.has("yield_requested_tick") and (not WorldState._natural(stay.yield_requested_tick) or int(stay.yield_requested_tick)>world.sim_tick): return "家属医疗请求时刻无效"
		if stay.purpose=="ward_visit" and (not stay.life_task.is_empty() or int(stay.remaining_ticks)>_ticks(content.balance.hospital_situations.ward_visit_seconds)): return "探视家属不能产生生活需求或扩大有效时长"
		if not stay.life_task.is_empty():
			var task: Dictionary=stay.life_task
			if task.get("owner_kind","")!="visitor" or task.get("actor_id","")!=stay.actor_id or not task.get("purpose","") in ["water","toilet"] or not task.get("phase","") in ["seek","area_travel","local_wait","local_travel","using","returning"] or not WorldState._natural(task.get("remaining_ticks",-1)): return "陪同家属生活服务事实无效"
			if task.phase=="using" and not world.facts.facilities.has(task.get("facility_id","")): return "陪同家属正在使用的生活设施不存在"
		if not stay.get("destination",{}) is Dictionary: return "家属实际行程目标无效"
		if stay.get("public_use",{}).has("yielded_seat"):
			var offered: Variant = stay.public_use.yielded_seat
			if not offered is Dictionary or not offered.get("facility_id") is String or str(offered.facility_id).is_empty() or not offered.get("visit_id") is String or str(offered.visit_id).is_empty(): return "家属让座意图无效"
		visits[str(stay.visit_id)+":"+str(stay.purpose)] = true
	for id: String in state.requests:
		var request: Variant = state.requests[id]
		if not request is Dictionary or request.get("id")!=id or not world.facts.visits.has(request.get("visit_id","")) or not request.get("purpose","") in ["companion","ward_visit"] or not WorldState._natural(request.get("request_tick",-1)):
			return "院外家属请求引用无效"
	return ""
