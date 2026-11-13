class_name HospitalFloorGuidance
extends RefCounted

const QueueWait = preload("res://game/operations/guidance_queue_wait.gd")
const QueueLayout = preload("res://game/operations/guidance_queue_layout.gd")
var _queue_plans: Dictionary = {}
var _queue_contexts: Dictionary = {}
var _queue_valid: Dictionary = {}
var _queue_batches: Dictionary = {}
var _queue_plan_revision: int = -1
var _queue_plan_world: WeakRef

const Scope = preload("res://game/operations/clinic_waiting_scope.gd")
var content: HospitalContent
var space: HospitalSpace
var clinic: HospitalClinic
var waiting: HospitalWaitingLife
var scope: RefCounted
var _worked: Dictionary = {}
var _destination_basis: Array = []
var _destination_index: Dictionary = {}
var _destination_tick: int = -1
var _destination_revision: int = -1
var _destination_layout: Array = []
var _destination_facilities: Array = []
var _destination_views: Dictionary = {}
var _state_world: WeakRef
var _state_facts: Dictionary = {}

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry
	space.guidance_queue_provider=weakref(self)
	scope = Scope.new(geometry)

# Loading only: warm the same immutable endpoint cache actual floor legs use.
# Queue choice, reservations, lift availability and people remain live decisions.
func prepare_static_routes(world: WorldState, floor_id: int) -> Dictionary:
	var started: int=Time.get_ticks_usec()
	# Cache warming must not impersonate a live actor dependency observation.
	# This method is synchronous; restore the original container, including aliases.
	var observed: Dictionary=space.navigation._observed_floors
	space.navigation._observed_floors={}
	var cache: NavigationCache=space._navigation
	var charge_before: int=cache.total_charge()
	var anchors: Array[Vector2i]=[]
	for id: String in world.ids("connectors"):
		var connection: Dictionary=world.facts.connectors[id]
		if content.definition("vertical_connectors",connection.definition_id).kind!="lift" or not HospitalTransit.has_stop(connection,floor_id): continue
		var anchor:=Vector2i(int(connection.anchor[0]),int(connection.anchor[1]))
		if not anchor in anchors: anchors.append(anchor)
	var lift_anchor_count: int=anchors.size()
	var entry: Dictionary=world.facts.get("entry",{})
	var entry_anchor_count: int=0
	if int(entry.get("floor_id",1))==floor_id and entry.get("cell",[]).size()==2:
		var entry_anchor:=Vector2i(roundi(entry.cell[0]),roundi(entry.cell[1]))
		if not entry_anchor in anchors:anchors.append(entry_anchor)
		entry_anchor_count=1
	var desks: Array=[]
	for id: String in world.facility_ids("SE01"):
		if int(world.facts.facilities[id].floor_id)==floor_id: desks.append(id)
	for desk_id: String in desks:
		_queue_context(world,desk_id)
		_desk_queue(world,desk_id)
	var seen: Dictionary={}
	var attempted: int=0
	var reachable: int=0
	var builds_before: int=int(space.query_counts.static_path_builds)
	var hits_before: int=int(space.query_counts.static_path_hits)
	if not anchors.is_empty() and not desks.is_empty():
		for actor_id: String in world.ids("actors"):
			var actor: Dictionary=world.facts.actors[actor_id]
			if actor.has("_convoy_size") or actor.has("_convoy_body"): continue
			var key: String=cache._graph_key(space,world,floor_id,actor,[],{},cache.floor_source(space,world,floor_id))
			if seen.has(key): continue
			seen[key]=true
			var graph: FloorNavigation=cache.graph(space,world,floor_id,actor,[],{})
			var goals: Dictionary={}
			for desk_id: String in desks:
				# Warm the empty-queue arrival, using the same real-body snake
				# geometry as dispatch. Never inspect live membership or reserve a tail.
				var context: Dictionary=_queue_context(world,desk_id)
				var first: Dictionary=QueueLayout.snake_next(context.facility,[],_queue_body(world,actor,desk_id))
				if not first.is_empty():goals[Vector2i(roundi(first.cell[0]),roundi(first.cell[1]))]=true
				var cell: Array=space.facility_layout(world,desk_id).patient_cell
				goals[Vector2i(roundi(cell[0]),roundi(cell[1]))]=true
			for anchor: Vector2i in anchors:
				for goal: Vector2i in goals:
					var result: Dictionary=cache.cached_floor_path(space,world,floor_id,actor,graph,graph.geometry,anchor,goal)
					attempted+=1
					if result.get("ok",false): reachable+=1
	var charge_after: int=cache.total_charge()
	space.navigation._observed_floors=observed
	return {"elapsed_usec":Time.get_ticks_usec()-started,"body_envelopes":seen.size(),"lift_anchors":lift_anchor_count,"entry_anchors":entry_anchor_count,"desks":desks.size(),"path_requests":attempted,"reachable":reachable,"path_builds":int(space.query_counts.static_path_builds)-builds_before,"path_hits":int(space.query_counts.static_path_hits)-hits_before,"cache_charge_before":charge_before,"cache_charge_after":charge_after,"cache_budget":int(content.balance.pathfinding.graph_cache_target_bytes)}

func ensure(world: WorldState) -> void:
	if not world.facts.has("floor_guidance"):
		world.facts.floor_guidance = {"visits":{},"desks":{},"releases":{},"clinic_queues":{},"next_arrival":0}
	if not world.facts.floor_guidance.has("releases"): world.facts.floor_guidance.releases = {}
	if not world.facts.floor_guidance.has("clinic_queues"): world.facts.floor_guidance.clinic_queues = {}
	if _state_world==null or _state_world.get_ref()!=world or not is_same(_state_facts,world.facts):
		for row: Dictionary in world.facts.floor_guidance.visits.values():
			if not row.has("target_room_id"): row.target_room_id=str(world.facts.facilities.get(str(row.get("target_id","")),{}).get("room_id",""))
		_state_world=weakref(world); _state_facts=world.facts

func execute(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	return CommandResult.new(false,"unknown_command","未知楼层导诊命令",[],world.revision)

func worked_staff() -> Dictionary:
	return _worked.duplicate()

func dispatch(world: WorldState) -> void:
	ensure(world)
	_worked.clear()
	for id: String in world.facts.floor_guidance.visits.keys():
		var visit: Dictionary = world.facts.visits.get(id,{})
		if visit.is_empty() or visit.get("phase","") in ["leaving","departed"]: release(world,id)
		else:
			var row: Dictionary=state(world,id)
			_observe_queue_departure(world,row)
	_release_nurses(world)
	_assign_desks(world)

func _desk_open(world: WorldState, id: String) -> bool:
	var f: Dictionary = world.facts.facilities.get(id,{})
	return f.get("definition_id","")=="SE01" and not f.get("failed",false) and f.get("open",true) and f.get("intake_open",true) and not HospitalRemodel.blocked(world,id)

func _desk_usable(world: WorldState, id: String) -> bool:
	if not _desk_open(world,id):return false
	var nurse: String=str(world.facts.floor_guidance.desks.get(id,{}).get("nurse_id",""))
	if not _nurse_ready(world,nurse) or world.facts.moves.has(nurse):return false
	return world.facts.staff[nurse].get("active_job_id","")=="floor_desk:"+id and space.at(world,nurse,int(world.facts.facilities[id].floor_id),space.guidance_operator_cell(world,id,nurse))

func _nurse_ready(world: WorldState, id: String) -> bool:
	var s: Dictionary = world.facts.staff.get(id,{})
	return s.get("role","")=="nurse" and bool(s.get("on_shift",false)) and not s.get("scheduled_kind","work") in ["rest","training"] and int(s.get("abilities",{}).get("care",0))>0 and HospitalStaffWellbeing.work_window(s) and not s.get("block_new_work",false) and float(s.get("energy",0))>15.0

func _clinical_responsibility(world: WorldState, nurse_id: String) -> bool:
	# Clinical gathering still owns its nurse in the gap after real arrival
	# and before session creation. Use the clinic's exact ticket/hold predicate.
	if clinic!=null and clinic.staff_busy(world,nurse_id): return true
	# A committed admission preparation reserves its future ward coverage
	# separately from the operating team, before a ward stay exists.
	for preparation: Dictionary in world.facts.preparations.values():
		if preparation.get("nurse_id","")==nurse_id: return true
	# Match staff wellbeing's live ward responsibility, not the permanent ward
	# assignment. Terminal stays no longer reserve nursing coverage, while
	# any separate physical clinical release remains protected above.
	for stay: Dictionary in world.facts.ward_stays.values():
		if stay.get("nurse_id","")==nurse_id and not stay.get("phase","") in ["release_wait","complete"]: return true
	return false

func _assign_desks(world: WorldState) -> void:
	var desks: Dictionary = world.facts.floor_guidance.desks
	for id: String in desks.keys():
		var desk: Dictionary = desks[id]
		var nurse: String = str(desk.get("nurse_id",""))
		var working: bool = false
		for state: Dictionary in _queue_members(world,id):
			if state.get("desk_id","")==id and state.get("phase","")=="working": working = true
		if not working and (not _desk_open(world,id) or not _nurse_ready(world,nurse)):
			# A not-yet-started counter approach belongs to this desk, not to
			# the departing nurse. Keep its same-desk queue place for relief.
			for current: Dictionary in _queue_members(world,id):
				if current.get("desk_id","")==id and current.get("phase","")=="to_counter":
					var visit: Dictionary = world.facts.visits[current.visit_id]
					_cancel_own_move(world,visit.actor_id,current)
					_release_counter(world,visit,current)
					current.phase = "desk_queue"
					current.erase("nurse_id")
			if world.facts.staff.has(nurse) and world.facts.staff[nurse].get("active_job_id","")=="floor_desk:"+id:
				world.facts.staff[nurse].active_job_id = "floor_desk_release:"+id
				_retain_departing_nurse_access(world,id,nurse)
				world.facts.floor_guidance.releases[nurse] = {"desk_id":id,"floor_id":int(world.facts.actors[nurse].location.get("floor_id",world.facts.facilities.get(id,{}).get("floor_id",1))),"cell":world.facts.actors[nurse].location.get("cell",[0,0]).duplicate(),"clearance":space.clearance(world.facts.actors[nurse])}
			var before: Dictionary=space.facility_layout(world,id) if world.facts.facilities.has(id) else {}
			desk.nurse_id = ""
			if not before.is_empty(): space.public_areas.facility_changed(before,space.facility_layout(world,id))
		if not world.facts.facilities.has(id): desks.erase(id)
	for id: String in world.facility_ids("SE01"):
		var desk: Dictionary = desks.get_or_add(id,{"id":id,"nurse_id":"","reason":""})
		if not desk.has("queue"):desk.queue=_desk_queue(world,id)
		if not _desk_open(world,id):
			desk.reason = "导诊台关闭、故障或正在改建"
			continue
		if str(desk.nurse_id).is_empty():
			for nurse: String in world.ids("staff"):
				if not _nurse_ready(world,nurse) or HospitalClinicalDevelopment.safe_busy(world,nurse) or _clinical_responsibility(world,nurse) or world.facts.moves.has(nurse): continue
				var staff: Dictionary = world.facts.staff[nurse]
				if clinic.scheduler!=null and not clinic.scheduler.assignment(world,nurse,clinic.scheduler.shift_index(world)).pools.is_empty(): continue
				if not staff.get("base_task",{}).is_empty() or not staff.get("life_task",{}).get("phase","idle")=="idle": continue
				var layout: Dictionary = space.facility_layout(world,id)
				if not space.can_reach(world,nurse,int(layout.floor_id),space.guidance_operator_cell(world,id,nurse)): continue
				if HospitalStaffWellbeing.yield_for_work(world,content,space,[nurse]): continue
				desk.nurse_id = nurse
				staff.active_job_id = "floor_desk:"+id
				space.public_areas.facility_changed(layout,space.facility_layout(world,id))
				break
		if str(desk.nurse_id).is_empty():
			desk.reason = "缺少可安全到岗的导诊护士"
			continue
		var layout: Dictionary = space.facility_layout(world,id)
		var nurse: String = str(desk.nurse_id)
		var operator: Array = space.guidance_operator_cell(world,id,nurse)
		if not space.at(world,nurse,int(layout.floor_id),operator):
			desk.reason = "导诊护士正在真实到岗"
			if not world.facts.moves.has(nurse):
				space.request_move(world,nurse,int(layout.floor_id),operator)
				if world.facts.moves.has(nurse): world.facts.moves[nurse].guidance_nurse_desk = id
		else: desk.reason = ""

func _key(ticket: Dictionary) -> String:
	return str(ticket.id)+":"+("examination" if ticket.kind in ["examination","spectrum","resonance"] else str(ticket.kind))

func state(world: WorldState, visit_id: String) -> Dictionary:
	return world.facts.get("floor_guidance",{}).get("visits",{}).get(visit_id,{})

func waiting_allowed(world: WorldState, visit_id: String) -> bool:
	var current: Dictionary = state(world,visit_id)
	return current.is_empty() or current.get("phase","")=="ready"

func working(world: WorldState, visit_id: String) -> bool:
	return state(world,visit_id).get("phase","")=="working"

func target(world: WorldState, visit_id: String) -> String:
	return str(state(world,visit_id).get("target_id",""))

func target_room(world: WorldState, visit_id: String) -> String:
	var current: Dictionary=state(world,visit_id)
	return str(current.get("target_room_id",world.facts.facilities.get(str(current.get("target_id","")),{}).get("room_id","")))

func prepare(world: WorldState, visit: Dictionary, ticket: Dictionary) -> bool:
	ensure(world)
	if ticket.has("resume_session_id"): return true
	var stay: Dictionary=HospitalClinic.Flow.ward_stay(world,visit.id)
	if ticket.kind=="surgery" and not stay.is_empty(): return true
	# A saved, already committed clinical journey completes its original safe
	# handoff. New requests never reserve clinical resources before this gate.
	if ticket.get("service_assigned",false) or world.facts.preparations.has(visit.id): return true
	if world.facts.get("waiting_life",{}).get("needs",{}).has(visit.id): return false
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	var previous: Dictionary = state(world,visit.id)
	if previous.get("request_key","")!=_key(ticket):
		var initial_done: bool = bool(previous.get("initial_done",false))
		var receipts: Array = previous.get("receipts",[]).duplicate(true)
		release(world,visit.id)
		previous = {"visit_id":visit.id,"request_key":_key(ticket),"ticket_id":ticket.id,"phase":"seek","target_id":"","target_room_id":"","desk_id":"","guide_floor":int(actor.location.get("floor_id",1)),"initial_done":initial_done,"receipts":receipts,"guided_target":"","arrived_seq":-1,"reason":"","next_recheck":0}
		world.facts.floor_guidance.visits[visit.id] = previous
	var current: Dictionary = previous
	if actor.location.kind!="floor":
		visit.waiting_reason = "正在真实前往本次就医楼层导诊"
		return false
	if current.has("floor_trip"):
		var trip: Dictionary=current.floor_trip
		if int(actor.location.floor_id)==int(trip.floor_id) and not _desk_usable(world,str(current.desk_id)):
			_cancel_own_move(world,visit.actor_id,current)
			if world.facts.moves.has(visit.actor_id): return false
			current.erase("floor_trip")
			current.phase="seek"
			var local: Array=_available_desks(world,int(trip.floor_id))
			if not local.is_empty(): _change_desk(world,visit,current,str(local[world.draw("registration",local.size())]))
			elif visit.get("continuation",{}).get("stage","")!="guidance": _select_floor(world,visit,current,true)
			return false
		if trip.cell.is_empty():
			var point: Dictionary=_queue_point(world,visit.actor_id,str(current.desk_id),visit.id)
			if point.is_empty():
				visit.waiting_reason="目标导诊层暂无合法队尾位置"
				return false
			trip.cell=point.cell.duplicate()
		if not space.at(world,visit.actor_id,int(trip.floor_id),trip.cell) or world.facts.moves.has(visit.actor_id):
			if not world.facts.moves.has(visit.actor_id): _move(world,visit,current,int(trip.floor_id),trip.cell)
			return false
		current.erase("floor_trip")
		current.phase="seek"
	var progress: Dictionary=visit.get("diagnosis",{})
	var continuation: Dictionary=visit.get("continuation",{})
	if ticket.kind=="outpatient" and current.phase=="seek":
		var gp: Dictionary=world.facts.facilities.get(str(progress.get("facility_id","")),{})
		if not gp.is_empty() and space.room_contains(world.facts.rooms[gp.room_id],space.body_rectangle(actor)):
			var binding: Dictionary=content.definition("treatment_bindings",visit.binding_id)
			var definition: String=str(content.definition("treatment_routines",binding.routine_id).equipment_id)
			for id: String in space.room_use.facilities(world,str(gp.room_id),[definition]):
				var doctor: Dictionary=world.facts.staff.get(str(progress.get("doctor_id","")),{})
				if doctor.is_empty() or not clinic._service_qualified(world,doctor,"outpatient") or not clinic._outpatient_quote(world,visit,doctor,world.facts.facilities[id],"",true,true).ok: continue
				current.target_id=id
				current.target_room_id=gp.room_id
				current.direct_doctor_id=doctor.id
				current.phase="ready"
				return true
	if ticket.kind in ["consult","plan"] and continuation.get("stage","")!="guidance":
		var original: String=str(progress.get("facility_id",""))
		if not world.facts.facilities.has(original):
			visit.waiting_reason="原门诊关闭或拆除，等待合法接续地点"
			return false
		if current.phase=="seek":
			current.target_id=original
			current.target_room_id=world.facts.facilities[original].room_id
			current.guide_floor=int(world.facts.facilities[original].floor_id)
			current.phase="destination"
			var queue: Dictionary=world.facts.floor_guidance.clinic_queues.get_or_add(current.target_room_id,{"visit_ids":[],"called_id":"","deadline_tick":-1})
			if not visit.id in queue.visit_ids: queue.visit_ids.append(visit.id)
		return _approach_destination(world,visit,ticket,current)
	if not current.get("floor_selected",false):
		if continuation.get("stage","")=="guidance":
			var original: Dictionary=world.facts.facilities.get(str(progress.get("facility_id","")),{})
			if original.is_empty(): return false
			current.guide_floor=int(original.floor_id)
			current.floor_selected=true
		elif not current.initial_done and not progress.get("gp_completed",false):
			if not _select_floor(world,visit,current,false): return false
			if current.has("floor_trip"): return false
		else:
			current.guide_floor=int(actor.location.floor_id)
			current.floor_selected=true
	if current.phase=="blocked_destination":
		if _target_ids(world,visit,str(ticket.kind)).is_empty():
			_depart_missing_destination(world,visit,current)
			return false
		current.phase="desk_queue"
		current.queue_attending=true
	# Removal can happen during transfer, queueing or counter service too.
	# Release only this request's movement/counter ownership and return to
	# the current floor's desk before considering any replacement.
	if ticket.kind!="surgery" and current.get("phase","")=="destination" and _destination_underway(world,visit,current): return false
	if current.phase in ["destination","ready"]: _refresh_target_anchor(world,visit,ticket,current)
	if _reselect_unreachable_target(world,visit,current): return false
	if current.phase in ["destination","ready"] and not _target_valid(world,visit,ticket,str(current.target_id)):
		_reset_destination(world,visit,current)
		current.target_id = ""
		current.guide_floor = int(actor.location.floor_id)
		return false
	if current.phase=="ready": return true
	if current.phase=="destination": return _approach_destination(world,visit,ticket,current)
	if current.phase=="working":
		visit.waiting_reason = "护士正在导诊台安排本次目的地"
		return false
	return _approach_desk(world,visit,ticket,current)

func _same_clinical_room(world: WorldState, first_id: String, second_id: String) -> bool:
	var first: Dictionary = world.facts.facilities.get(first_id,{})
	var second: Dictionary = world.facts.facilities.get(second_id,{})
	var room_id: String = str(first.get("room_id",""))
	return not room_id.is_empty() and world.facts.rooms.has(room_id) and room_id==str(second.get("room_id","")) and int(first.get("floor_id",-1))==int(second.get("floor_id",-2))

func _target_valid(world: WorldState, visit: Dictionary, ticket: Dictionary, id: String) -> bool:
	if id.is_empty(): return false
	return not _target_ids(world,visit,str(ticket.kind),id).is_empty()

func _target_ids(world: WorldState, visit: Dictionary, kind: String, only_id: String = "") -> Array:
	if kind in ["consult","plan"]:
		var id: String=str(visit.get("diagnosis",{}).get("facility_id",""))
		return [id] if world.facts.facilities.has(id) and clinic.service_room_reason(world,world.facts.facilities[id]).is_empty() else []
	if kind=="examination":
		var modes: Array=[str(visit.get("diagnosis",{}).get("exam_kind",""))] if not str(visit.get("diagnosis",{}).get("exam_kind","")).is_empty() else ["spectrum","resonance"]
		var ids: Array=[]
		for mode: String in modes:
			for id: String in _target_ids(world,visit,mode,only_id):
				if not id in ids: ids.append(id)
		return ids
	if kind=="surgery":
		var actor: Dictionary=world.facts.actors[visit.actor_id]
		var quote: Dictionary=clinic._compatible_bed(world,visit,int(actor.location.get("floor_id",1)),[],false,only_id)
		return [quote.bed_id] if quote.ok else []
	var definition: String = "FUR02"
	if kind=="outpatient": definition = str(content.definition("treatment_routines",content.definition("treatment_bindings",visit.binding_id).routine_id).equipment_id)
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	var floor_id: int = int(actor.location.get("floor_id",state(world,visit.id).get("guide_floor",1)))
	_refresh_destinations(world,floor_id)
	var ids: Array = []
	var selected_room: String=target_room(world,visit.id) if not only_id.is_empty() and only_id==target(world,visit.id) else str(world.facts.facilities.get(only_id,{}).get("room_id",""))
	for id: String in _destination_index.get(kind+":"+definition,[]):
		var facility: Dictionary = world.facts.facilities.get(id,{})
		var same_destination: bool=not selected_room.is_empty() and facility.get("room_id","")==selected_room
		if (only_id.is_empty() or same_destination) and int(facility.floor_id)==floor_id: ids.append(id)
	return ids

func _refresh_target_anchor(world: WorldState, visit: Dictionary, ticket: Dictionary, current: Dictionary) -> void:
	if ticket.kind=="surgery" or str(current.get("target_id","")).is_empty(): return
	var ids: Array=_target_ids(world,visit,str(ticket.kind),str(current.target_id))
	if not ids.is_empty() and not current.target_id in ids: current.target_id=ids[0]

func _refresh_destinations(world: WorldState, floor_id: int) -> void:
	var saved: Dictionary=_destination_views.get(floor_id,{})
	var first_b: int=int(world.facts.get("research_progress",{}).get("first_profile_b_tick",-1))
	if saved.get("world_id",-1)==world.get_instance_id() and saved.get("tick",-1)==world.sim_tick and saved.get("revision",-1)==world.revision and saved.get("first_b",-1)==first_b and saved.get("research",[])==world.facts.research:
		_destination_index=saved.index
		return
	var layout: Array=[world.get_instance_id(),world.geometry_revision,floor_id]
	if layout!=_destination_layout:
		_destination_layout=layout
		_destination_facilities.clear()
		var definitions: Array=["FUR02","EQ01"]
		for routine: Dictionary in content.catalog.treatment_routines:
			if not routine.equipment_id in definitions: definitions.append(routine.equipment_id)
		for definition: String in definitions:
			for id: String in world.facility_ids(definition):
				if int(world.facts.facilities[id].floor_id)==floor_id: _destination_facilities.append(id)
	var basis: Array = [layout,clinic.scheduler.shift_index(world) if clinic.scheduler!=null else -1,world.facts.research,first_b]
	for id: String in _destination_facilities:
		var facility: Dictionary=world.facts.facilities[id]
		basis.append([id,facility.get("failed",false),facility.get("open",true),facility.get("intake_open",true),HospitalRemodel.blocked(world,id)])
	for id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[id]
		basis.append([id,staff.role,staff.get("on_shift",false),staff.get("scheduled_kind","work"),staff.get("block_new_work",false),staff.get("life_task",{}).get("phase","idle"),float(staff.get("energy",0))>15.0,float(staff.get("fatigue",0))<float(content.balance.wellbeing.fatigue_stop_new_work),staff.abilities,staff.get("base_prepared",false),staff.get("schedule",[]),staff.get("schedule_overrides",{}),staff.get("departed",false)])
	_destination_tick=world.sim_tick
	_destination_revision=world.revision
	if saved.get("world_id",-1)==world.get_instance_id() and basis==saved.get("basis",[]):
		_destination_index=saved.index
		saved.tick=world.sim_tick
		saved.revision=world.revision
		return
	_destination_basis=basis.duplicate(true)
	_destination_index={}
	var definitions: Array = ["FUR02","EQ01"]
	for routine: Dictionary in content.catalog.treatment_routines:
		if not routine.equipment_id in definitions: definitions.append(routine.equipment_id)
	for definition: String in definitions:
		for id: String in world.facility_ids(definition):
			var facility: Dictionary=world.facts.facilities[id]
			if int(facility.floor_id)!=floor_id: continue
			if facility.get("failed",false) or not facility.get("open",true) or not facility.get("intake_open",true) or HospitalRemodel.blocked(world,id) or not clinic.service_room_reason(world,facility).is_empty(): continue
			var kinds: Array=["gp","spectrum","resonance","consult"] if definition=="FUR02" else ["surgery"] if definition=="EQ01" else ["outpatient"]
			for kind: String in kinds:
				if kind in ["gp","spectrum","resonance"] and not kind in content.facility_definition(definition).get("diagnostic_modes",["gp","spectrum","resonance"]): continue
				for staff_id: String in world.ids("staff"):
					var staff: Dictionary=world.facts.staff[staff_id]
					if not staff.get("on_shift",false) or not clinic._can_start(world,staff) or not clinic._schedule_allows(world,staff_id,kind,{},id): continue
					if kind!="surgery" and not clinic._service_qualified(world,staff,kind): continue
					_destination_index.get_or_add(kind+":"+definition,[]).append(id)
					break
	_destination_views[floor_id]={"world_id":world.get_instance_id(),"tick":world.sim_tick,"revision":world.revision,"first_b":first_b,"research":world.facts.research.duplicate(),"basis":basis.duplicate(true),"index":_destination_index}



func _choose_target(world: WorldState, visit: Dictionary, ticket: Dictionary) -> String:
	if ticket.get("kind","")=="examination":
		var progress: Dictionary=HospitalClinic.Flow.diagnosis(visit)
		if str(progress.exam_kind).is_empty():
			var modes: Array=[]
			for mode: String in ["spectrum","resonance"]:
				for id: String in _target_ids(world,visit,mode):
					var selection: Dictionary={"facility_id":id,"first_only":true,"eligible":_examination_pair_eligible.bind(world,visit,mode)}
					if not clinic.service_candidates(world,visit,mode,true,false,selection).is_empty():
						modes.append(mode)
						break
			if modes.is_empty(): return ""
			progress.exam_kind=str(modes[world.draw("treatment",modes.size())])
	var ids: Array = _target_ids(world,visit,str(ticket.get("kind","")))
	if ids.is_empty(): return ""
	if ticket.get("kind","")=="surgery": return str(ids[world.draw("registration",ids.size())])
	var rooms: Dictionary = {}
	for id: String in ids:
		rooms.get_or_add(str(world.facts.facilities[id].get("room_id","")),[]).append(id)
	var room_ids: Array = rooms.keys()
	room_ids.sort()
	return str(rooms[room_ids[world.draw("registration",room_ids.size())]][0])

func _examination_pair_eligible(pair: Dictionary, world: WorldState, visit: Dictionary, kind: String) -> bool:
	var staff: Dictionary=world.facts.staff[pair.staff_id]
	return staff.on_shift and clinic._can_start(world,staff) and clinic._schedule_allows(world,staff.id,kind,visit,str(pair.facility_id))

func _has_other_guidance_floor(world: WorldState, floor_id: int) -> bool:
	for id: String in world.facility_ids("SE01"):
		if int(world.facts.facilities[id].floor_id)!=floor_id and _desk_usable(world,id): return true
	return false

func _depart_missing_destination(_world: WorldState, visit: Dictionary, current: Dictionary) -> void:
	var world: WorldState=_world
	_release_counter(world,visit,current)
	if _select_floor(world,visit,current,true): return
	current.phase="blocked_destination"
	current.queue_attending=false
	current.reason="本层没有本次可用目的地，保留原序号等待条件变化"
	visit.waiting_reason=current.reason
	_wait_near_queue(world,visit,current)
	visit.waiting_reason=current.reason

func _select_floor(world: WorldState, visit: Dictionary, current: Dictionary, other_only: bool) -> bool:
	var floors: Dictionary={}
	var here: int=int(world.facts.actors[visit.actor_id].location.get("floor_id",current.guide_floor))
	for id: String in world.facility_ids("SE01"):
		if not _desk_usable(world,id): continue
		var floor_id: int=int(world.facts.facilities[id].floor_id)
		if other_only and floor_id==here: continue
		floors.get_or_add(floor_id,[]).append(id)
	if floors.is_empty():
		visit.waiting_reason="该楼层缺少可用导诊台" if not other_only else "没有其他可用导诊楼层，等待本层条件变化"
		if not other_only and waiting!=null and not world.facts.moves.has(visit.actor_id): waiting._wait_safely(world,visit,{"area":{}},space.public_areas.floor_waiting_point.bind(world,visit.actor_id))
		return false
	var ids: Array=floors.keys()
	ids.sort()
	var chosen: int=int(ids[world.draw("registration",ids.size())])
	var desks: Array=floors[chosen]
	desks.sort()
	var desk_id: String=str(desks[world.draw("registration",desks.size())])
	_change_desk(world,visit,current,desk_id)
	current.guide_floor=chosen
	current.floor_selected=true
	if chosen!=here:
		current.floor_trip={"floor_id":chosen,"cell":[]}
		var point: Dictionary=_queue_point(world,visit.actor_id,desk_id,visit.id)
		if point.is_empty():
			visit.waiting_reason="目标导诊层暂无合法队尾位置"
			return false
		current.floor_trip.cell=point.cell.duplicate()
		_move(world,visit,current,chosen,point.cell)
	return true

func _change_desk(world: WorldState, visit: Dictionary, current: Dictionary, desk_id: String) -> void:
	if str(current.get("desk_id",""))==desk_id: return
	_cancel_own_move(world,visit.actor_id,current)
	_release_counter(world,visit,current)
	# Arrival priority and unfinished counter work belong only to the old
	# desk. Preserve the clinical ticket and waiting history, never move the
	# old desk's queue place or service progress into another desk.
	_queue_leave(world,current)
	current.desk_id = desk_id
	current.phase = "seek"
	current.arrived_seq = -1
	for field: String in ["blocked_queue_revision","queue_trip","tail_seen","queue_seq","queue_cell","queue_bank_key","queue_attending","queue_arrived_tick","queue_desk_id","nurse_id","remaining_ticks","started_tick"]:
		current.erase(field)

func _reset_destination(world: WorldState, visit: Dictionary, current: Dictionary) -> void:
	for queue: Dictionary in world.facts.floor_guidance.clinic_queues.values():
		queue.visit_ids.erase(visit.id)
		if queue.called_id==visit.id: queue.called_id=""; queue.deadline_tick=-1
	_cancel_own_move(world,visit.actor_id,current)
	if waiting!=null: waiting._release_seat(world,visit.id)
	_change_desk(world,visit,current,"")
	current.phase = "seek"
	current.guided_target = ""
	current.target_room_id = ""
	current.arrived_seq = -1
	current.erase("queue_seq")
	current.erase("queue_cell")
	current.erase("destination_cell")
	current.erase("queue_trip")
	current.erase("tail_seen")

# Queue geometry is a floor-loading concern. Only membership/tail are live;
# pedestrians along the journey are left to the movement system.
# Adapted work posts/footprints can change without a building revision.
# The existing reservation owner publishes these rare geometry transitions.
func facility_layout_changed(world: WorldState, before: Dictionary, after: Dictionary) -> void:
	if _queue_plan_world==null or _queue_plan_world.get_ref()!=world:return
	for field: String in ["footprint","patient_cell","operator_cells","repair_cell"]:
		if before.get(field)!=after.get(field):
			# Facility geometry affects queue layouts on its old/new floors only.
			# Keep unrelated floors warm; no dynamic body result is cached here.
			if not before.has("floor_id") or not after.has("floor_id"):
				_queue_plans.clear();_queue_contexts.clear();_queue_valid.clear();_queue_batches.clear()
				return
			for desk_id: String in world.facility_ids("SE01"):
				if int(world.facts.facilities[desk_id].floor_id) not in [int(before.floor_id),int(after.floor_id)]:continue
				_queue_contexts.erase(desk_id);_queue_batches.erase(desk_id)
				for key: String in _queue_plans.keys():
					if key.begins_with(desk_id+":"):_queue_plans.erase(key)
				for key: String in _queue_valid.keys():
					if key.begins_with(desk_id+":"):_queue_valid.erase(key)
			return

func _queue_context(world: WorldState, desk_id: String) -> Dictionary:
	if _queue_plan_world==null or _queue_plan_world.get_ref()!=world or _queue_plan_revision!=world.geometry_revision:
		_queue_contexts.clear();_queue_batches.clear();_queue_valid.clear();_queue_plans.clear()
		_queue_plan_world=weakref(world);_queue_plan_revision=world.geometry_revision
	if _queue_contexts.has(desk_id):return _queue_contexts[desk_id]
	var facility: Dictionary=world.facts.facilities.get(desk_id,{})
	if facility.is_empty():return {}
	var base: Dictionary=facility.duplicate()
	var result: Dictionary={"facility":base}
	_queue_contexts[desk_id]=result
	return result

func _desk_queue(world: WorldState, desk_id: String) -> Array:
	var desk: Dictionary=world.facts.get("floor_guidance",{}).get("desks",{}).get(desk_id,{})
	if desk.has("queue"):return desk.queue
	# Read-only bootstrap for old test boundary inputs. Live creation stores
	# the array on the desk, never as a side effect of an entry query.
	var queue: Array=[]
	for row: Dictionary in world.facts.get("floor_guidance",{}).get("visits",{}).values():
		if row.get("desk_id","")==desk_id and row.has("queue_seq") and row.get("phase","") in ["desk_queue","to_counter","working","blocked_destination"]:queue.append(row.visit_id)
	queue.sort_custom(func(a: String,b: String)->bool:return int(state(world,a).queue_seq)<int(state(world,b).queue_seq))
	return queue

func _queue_join(world: WorldState, current: Dictionary) -> void:
	var desk_id: String=str(current.desk_id)
	var queue: Array=_desk_queue(world,desk_id)
	world.facts.floor_guidance.desks.get_or_add(desk_id,{"id":desk_id,"nurse_id":"","reason":""}).queue=queue
	if current.visit_id in queue:return
	queue.append(current.visit_id)
	var desk: Dictionary=world.facts.floor_guidance.desks[desk_id]
	desk.queue_revision=int(desk.get("queue_revision",0))+1
	_queue_batches.erase(desk_id)

func _queue_leave(world: WorldState, current: Dictionary) -> void:
	var desk_id: String=str(current.get("desk_id",""))
	if desk_id.is_empty():return
	var queue: Array=_desk_queue(world,desk_id)
	if world.facts.floor_guidance.desks.has(desk_id):world.facts.floor_guidance.desks[desk_id].queue=queue
	if current.get("visit_id","") in queue:
		queue.erase(current.visit_id)
		var desk: Dictionary=world.facts.floor_guidance.desks.get(desk_id,{})
		desk.queue_revision=int(desk.get("queue_revision",0))+1
		_queue_batches.erase(desk_id)

func _queue_members(world: WorldState, desk_id: String) -> Array:
	var result: Array=[]
	for id: String in _desk_queue(world,desk_id).duplicate():
		var row: Dictionary=state(world,id)
		if row.has("queue_seq"):result.append(row)
	return result

func _queue_position_allowed(world: WorldState, actor_id: String, desk_id: String, slot: Array, _span: int) -> bool:
	var actor: Dictionary=world.facts.actors[actor_id]
	var geometry: RouteClearance=space.navigation.structural_clearance(world,actor,int(world.facts.facilities[desk_id].floor_id))
	return geometry.position_reason(ConvoyTrail.point(slot)).is_empty()

func _queue_body(world: WorldState, actor: Dictionary, desk_id: String) -> Dictionary:
	return space.guidance_body(world,actor,desk_id)

func _queue_point(world: WorldState, actor_id: String, desk_id: String, _visit_id: String="") -> Dictionary:
	var context: Dictionary=_queue_context(world,desk_id)
	if context.is_empty():return {}
	if not _queue_batches.has(desk_id):
		var ids: Array=[]
		var bodies: Array=[]
		for row: Dictionary in _queue_members(world,desk_id):
			var id: String=str(world.facts.visits[row.visit_id].actor_id)
			ids.append(id);bodies.append(_queue_body(world,world.facts.actors[id],desk_id))
		var packing: Dictionary=QueueLayout.snake(context.facility,bodies)
		var positions: Dictionary={}
		for i: int in range(ids.size()):positions[ids[i]]=packing.placements[i]
		_queue_batches[desk_id]={"packing":packing,"positions":positions,"bodies":bodies}
	var bank: Dictionary=_queue_batches[desk_id]
	var point: Dictionary=bank.positions.get(actor_id,{})
	if point.is_empty():point=QueueLayout.snake_append(bank.packing,_queue_body(world,world.facts.actors[actor_id],desk_id))
	if point.is_empty():return {}
	var result: Dictionary=point.duplicate()
	result.floor_id=int(context.facility.floor_id)
	return result

func _queue_admission_clear(world: WorldState, actor_id: String, floor_id: int, cell: Array, facing: float=INF) -> bool:
	var actor: Dictionary=world.facts.actors[actor_id].duplicate()
	if facing!=INF:actor.facing=facing
	var point:=Vector2(float(cell[0]),float(cell[1]))
	# Arrival checks the actual oriented body. _dynamic_clear already checks
	# reservations, other bodies and accepted movement sweeps with this rectangle.
	return space._dynamic_clear(world,actor_id,floor_id,space._actor_rect(actor,point))

func _queue_bank_key(world: WorldState, desk_id: String) -> String:
	var desk: Dictionary=world.facts.facilities.get(desk_id,{})
	return JSON.stringify([desk_id,desk.get("floor_id",0),desk.get("cell",[]),desk.get("rotation",0)])

# A number belongs to continuous participation, not to the clinical ticket.
# A pending need or external trip can be cancelled before it actually moves;
# only real departure from the held queue point discards that number.
func _observe_queue_departure(world: WorldState, current: Dictionary) -> void:
	if not current.has("queue_seq") or current.get("phase","") not in ["desk_queue","to_counter"]:return
	var visit: Dictionary=world.facts.visits.get(str(current.get("visit_id","")),{})
	if visit.is_empty():return
	var actor: Dictionary=world.facts.actors[visit.actor_id]
	var move: Dictionary=world.facts.moves.get(visit.actor_id,{})
	var need: bool=world.facts.get("waiting_life",{}).get("needs",{}).has(visit.id)
	var external: bool=not move.is_empty() and move.get("floor_guidance_key","")!=current.get("request_key","")
	var other_floor: bool=actor.location.kind!="floor" or int(actor.location.floor_id)!=int(current.guide_floor)
	var disengaged: bool=not current.get("queue_attending",true) and (move.is_empty() or external)
	if not need and not external and not other_floor and not disengaged:return
	current.queue_attending=false
	if not other_floor and current.has("queue_cell") and space.at(world,visit.actor_id,int(current.guide_floor),current.queue_cell):return
	if current.phase=="to_counter":_release_counter(world,visit,current)
	_queue_leave(world,current)
	for field: String in ["queue_seq","queue_cell","queue_bank_key","queue_arrived_tick","queue_desk_id","nurse_id","remaining_ticks","started_tick"]:current.erase(field)
	current.phase="seek"

func _queue_participating(world: WorldState, current: Dictionary) -> bool:
	_observe_queue_departure(world,current)
	var visit: Dictionary=world.facts.visits.get(str(current.get("visit_id","")),{})
	if visit.is_empty() or world.facts.get("waiting_life",{}).get("needs",{}).has(visit.id):return false
	if current.get("phase","")!="desk_queue" or not current.get("queue_attending",false) or current.get("queue_bank_key","")!=_queue_bank_key(world,str(current.desk_id)):return false
	var move: Dictionary=world.facts.moves.get(visit.actor_id,{})
	if not move.is_empty():
		if move.get("floor_guidance_key","")!=current.request_key:current.queue_attending=false;return false
		return move.get("floor_guidance_queue_advance","")==current.queue_bank_key
	# Admission persists during a queue re-layout before this actor's next
	# callback. It is distinct from a patient returning from a life need.
	var actor: Dictionary=world.facts.actors[visit.actor_id]
	return actor.location.kind=="floor" and int(actor.location.floor_id)==int(current.guide_floor)

func _queue_present(world: WorldState, current: Dictionary) -> bool:
	# Staffing pauses preserve a present queue; a patient who actually leaves
	# must arrive at the then-current tail again before receiving a new number.
	# Read live facts here, not a phase another visit must update first.
	if current.get("phase","")!="desk_queue" or not current.has("queue_cell"): return false
	var visit: Dictionary = world.facts.visits.get(str(current.get("visit_id","")),{})
	if visit.is_empty() or world.facts.get("waiting_life",{}).get("needs",{}).has(visit.id): return false
	var actor_id: String = str(visit.actor_id)
	var floor_id: int = int(current.guide_floor)
	var point: Dictionary=_queue_point(world,actor_id,str(current.desk_id),visit.id)
	return not point.is_empty() and point.cell==current.queue_cell and not world.facts.moves.has(actor_id) and space.at(world,actor_id,floor_id,current.queue_cell)


func _available_desks(world: WorldState, floor_id: int, exclude: String="") -> Array:
	var options: Array=[]
	for id: String in world.facility_ids("SE01"):
		if id!=exclude and int(world.facts.facilities[id].floor_id)==floor_id and _desk_usable(world,id):options.append(id)
	return options

func _queue_blocked(world: WorldState, visit: Dictionary, current: Dictionary) -> void:
	if current.has("queue_seq"):
		visit.waiting_reason="等待前方患者前进"
		return
	var options: Array=_available_desks(world,int(current.guide_floor),str(current.desk_id))
	if not options.is_empty():
		_change_desk(world,visit,current,str(options[world.draw("registration",options.size())]))
		visit.waiting_reason="当前队尾无法加入，改去另一个随机导诊台"
	else:
		current.blocked_queue_revision=int(world.facts.floor_guidance.desks.get(current.desk_id,{}).get("queue_revision",0))
		visit.waiting_reason="只有一个可用导诊台，等待队伍前进"

func _approach_desk(world: WorldState, visit: Dictionary, ticket: Dictionary, current: Dictionary) -> bool:
	_observe_queue_departure(world,current)
	var floor_id: int = int(current.guide_floor)
	var selected: String=str(current.desk_id)
	if _desk_open(world,selected) and int(world.facts.facilities[selected].floor_id)==floor_id and not _desk_usable(world,selected) and current.has("queue_seq"):
		# Temporary staffing loss pauses this bank, not its actual queue order.
		visit.waiting_reason="本层导诊台尚未启用，等待护士实际到岗，保留原队序"
		return false
	if not _desk_usable(world,str(current.desk_id)) or int(world.facts.facilities.get(str(current.desk_id),{}).get("floor_id",0))!=floor_id:
		_change_desk(world,visit,current,"")
		var options: Array=_available_desks(world,floor_id)
		if options.is_empty():
			if visit.get("continuation",{}).get("stage","")!="guidance" and _select_floor(world,visit,current,true): return false
			visit.waiting_reason="本层暂无护士在岗的导诊台，在附近等待"
			if waiting!=null and not world.facts.moves.has(visit.actor_id) and not space.public_areas.safe_wait(world,visit.actor_id,floor_id,world.facts.actors[visit.actor_id].location.cell):
				waiting._wait_safely(world,visit,{"area":{}},space.public_areas.floor_waiting_point.bind(world,visit.actor_id))
			return false
		_change_desk(world,visit,current,str(options[world.draw("registration",options.size())]))
		if int(world.facts.actors[visit.actor_id].location.floor_id)!=floor_id:
			current.floor_trip={"floor_id":floor_id,"cell":[]}
			return false

	if current.phase=="to_counter": return _gather_counter(world,visit,current)
	var underway: Dictionary=world.facts.moves.get(visit.actor_id,{})
	if not underway.is_empty():
		# A fixed trip ends before another tail lookup. Movement may resolve
		# collisions, but guidance never retargets from a changing queue.
		if underway.get("floor_guidance_key","")==current.request_key:
			visit.waiting_reason="正在前往出发时记录的导诊队尾"
			if not space.movement_failure(world,visit.actor_id).is_empty():
				_cancel_own_move(world,visit.actor_id,current)
				current.erase("queue_trip")
				_queue_blocked(world,visit,current)
		return false
	if current.has("queue_trip") and not space.at(world,visit.actor_id,floor_id,current.queue_trip):
		_move(world,visit,current,floor_id,current.queue_trip)
		return false
	current.erase("queue_trip")
	if current.has("blocked_queue_revision"):
		if int(current.blocked_queue_revision)==int(world.facts.floor_guidance.desks.get(current.desk_id,{}).get("queue_revision",0)):return false
		current.erase("blocked_queue_revision")
	var point: Dictionary=_queue_point(world,visit.actor_id,str(current.desk_id),visit.id)
	if point.is_empty():return false
	if not space.at(world,visit.actor_id,floor_id,point.cell):
		# Only at the recorded destination is the new tail examined.
		if not current.has("queue_seq") and current.get("tail_seen",false) and not _queue_position_allowed(world,visit.actor_id,str(current.desk_id),point.cell,0):
			_queue_blocked(world,visit,current)
			return false
		current.tail_seen=true
		current.queue_trip=point.cell.duplicate()
		_move(world,visit,current,floor_id,point.cell)
		if current.has("queue_seq"):
			var accepted: Dictionary=world.facts.moves.get(visit.actor_id,{})
			if accepted.get("floor_guidance_key","")==current.request_key:accepted.floor_guidance_queue_advance=_queue_bank_key(world,str(current.desk_id))
		return false
	if not _queue_admission_clear(world,visit.actor_id,floor_id,point.cell,point.facing):
		# A body/reservation/sweep can clear without any queue membership change.
		# Retry actual admission next dispatch, not a queue-revision subscription.
		visit.waiting_reason="队尾暂时被占用，等待实际入队"
		return false
	var arriving: Dictionary=world.facts.actors[visit.actor_id]
	if float(arriving.facing)!=float(point.facing):
		arriving.facing=point.facing
		space.sync_actor(world,visit.actor_id)
	current.queue_cell=point.cell.duplicate()
	if not current.has("queue_seq"):
		world.facts.floor_guidance.next_arrival+=1
		current.queue_seq=world.facts.floor_guidance.next_arrival
		current.queue_desk_id=current.desk_id
		current.queue_arrived_tick=world.sim_tick
		_queue_join(world,current)
	current.phase = "desk_queue"
	current.queue_attending=true
	current.queue_bank_key=_queue_bank_key(world,str(current.desk_id))
	current.reason = ""
	for other: Dictionary in _queue_members(world,str(current.desk_id)):
		if other.visit_id==visit.id or other.get("desk_id","")!=current.desk_id or world.facts.get("waiting_life",{}).get("needs",{}).has(other.visit_id): continue
		if other.get("phase","") in ["to_counter","working"] or other.has("queue_seq") and int(other.queue_seq)<int(current.queue_seq) and _queue_participating(world,other):
			visit.waiting_reason = "本层导诊排队，尚未进入目的地队列"
			return false
	var desk: Dictionary = world.facts.floor_guidance.desks.get(current.desk_id,{})
	var nurse: String = str(desk.get("nurse_id",""))
	if nurse.is_empty() or not _nurse_ready(world,nurse):
		visit.waiting_reason = "本层导诊台缺少当班护士，保留排队顺序"
		return false
	if ticket.kind in ["consult","plan"] and visit.get("continuation",{}).get("stage","")=="guidance":
		if not HospitalClinic.Flow.continuation_ready(clinic,world,visit): return false
	if _target_ids(world,visit,str(ticket.kind)).is_empty() and not _has_other_guidance_floor(world,floor_id):
		_depart_missing_destination(world,visit,current)
		return false
	if current.get("arrangement_done",false):
		_finish_arrangement(world,visit,ticket,current)
		return false
	# The queue head may intend to walk into its post before the complete
	# operating area clears. Actual steps stay physical; no use is reserved yet.
	var quote: Dictionary = space.facility_geometry_quote(world,str(current.desk_id),visit.actor_id,[nurse])
	if not quote.get("ok",false) or quote.get("unchanged",false):
		visit.waiting_reason = quote.get("reason","导诊台缺少真实双人服务空间")
		return false
	var a: Dictionary = world.facts.actors[visit.actor_id]
	var n: Dictionary = world.facts.actors[nurse]
	if space._actor_rect(a,Vector2(quote.patient_cell[0],quote.patient_cell[1])).intersects(space._actor_rect(n,Vector2(quote.operator_cells[0][0],quote.operator_cells[0][1])),false):
		visit.waiting_reason = "导诊台患者位与护士位身体相交，需要调整布局"
		return false
	current.nurse_id = nurse
	current.phase = "to_counter"
	return _gather_counter(world,visit,current)

# Full-queue waiting uses only the desk layout and present physical geometry.
# No queue number, remote place reservation or additional waiting state exists.
func _wait_near_queue(world: WorldState, visit: Dictionary, current: Dictionary) -> bool:
	var context: Dictionary=QueueWait.context(space,world,self,str(current.desk_id))
	var actor: Dictionary=world.facts.actors[visit.actor_id]
	if context.is_empty() or actor.location.kind!="floor" or int(actor.location.floor_id)!=int(context.floor_id):return false
	var move: Dictionary=world.facts.moves.get(visit.actor_id,{})
	if not move.is_empty() and move.get("floor_guidance_key","")==current.request_key and int(move.target_floor)==int(context.floor_id) and QueueWait.allowed(space,world,visit.actor_id,context,move.target_cell):
		visit.waiting_reason="导诊队列已满，正在附近安全候位"
		return true
	var point: Dictionary=QueueWait.choose(space,world,visit.actor_id,context)
	if point.is_empty():
		# A full queue may withdraw its obsolete destination, but not stop
		# an already travelling body inside a real door. Recheck next tick;
		# once clear, cancellation prevents completing the old tail journey.
		if not move.is_empty() and move.get("floor_guidance_key","")==current.request_key:
			var body: Rect2=space._actor_rect(actor,ConvoyTrail.point(actor.location.cell))
			for door: Dictionary in space.movement_doors(world,actor,body,[]):
				if body.intersects(space._door_rect(door,space._door_span(actor,door)),false):
					visit.waiting_reason="导诊队列已满，先沿当前路线离开门口再候位"
					return true
		_cancel_own_move(world,visit.actor_id,current)
		visit.waiting_reason="导诊队列已满且附近暂无安全候位空间，保留待办"
		return true
	if space.at(world,visit.actor_id,int(point.floor_id),point.cell):_cancel_own_move(world,visit.actor_id,current)
	else:_move(world,visit,current,int(point.floor_id),point.cell)
	visit.waiting_reason="导诊队列已满，在附近安全候位"
	return true

func _gather_counter(world: WorldState, visit: Dictionary, current: Dictionary) -> bool:
	var nurse: String = str(current.nurse_id)
	if not _nurse_ready(world,nurse) or world.facts.floor_guidance.desks.get(current.desk_id,{}).get("nurse_id","")!=nurse:
		_release_counter(world,visit,current)
		current.phase = "desk_queue"
		return false
	var layout: Dictionary = space.facility_geometry_quote(world,str(current.desk_id),visit.actor_id,[nurse])
	if not layout.get("ok",false):
		visit.waiting_reason = layout.get("reason","导诊台没有合法的真实服务位")
		return false
	if not space.at(world,visit.actor_id,int(layout.floor_id),layout.patient_cell) or world.facts.moves.has(visit.actor_id):
		_move(world,visit,current,int(layout.floor_id),layout.patient_cell)
		visit.waiting_reason = "正在真实走到导诊台服务位"
		return false
	if not space.at(world,nurse,int(layout.floor_id),layout.operator_cells[0]) or world.facts.moves.has(nurse):
		if not world.facts.moves.has(nurse): space.request_move(world,nurse,int(layout.floor_id),layout.operator_cells[0])
		visit.waiting_reason = "等待导诊护士真实到台"
		return false
	var post: Dictionary=space.guidance_patient_post(world,str(current.desk_id),visit.actor_id)
	var patient: Dictionary=world.facts.actors[visit.actor_id]
	if float(patient.facing)!=float(post.facing):
		if not _queue_admission_clear(world,visit.actor_id,int(layout.floor_id),layout.patient_cell,float(post.facing)):
			visit.waiting_reason="等待真实患者身体可安全面向导诊台"
			return false
		patient.facing=float(post.facing)
		space.sync_actor(world,visit.actor_id)
	# Service begins only with both bodies really present and the original
	# full live preflight/reservation accepted in this dispatch boundary.
	var reason: String = space.reserve_facility(world,str(current.desk_id),visit.actor_id,"floor_guide:"+visit.id,[nurse])
	if not reason.is_empty():
		visit.waiting_reason = reason
		return false
	current.phase = "working"
	current.remaining_ticks = maxi(1,ceili(float(content.balance.guidance.nurse_seconds)*10.0/clinic._talent_rate(world,str(current.nurse_id),"guidance",visit)))
	current.started_tick = world.sim_tick
	return false

func _move(world: WorldState, visit: Dictionary, current: Dictionary, floor_id: int, cell: Array) -> void:
	var movement: Dictionary = world.facts.moves.get(visit.actor_id,{})
	if not movement.is_empty() and movement.get("floor_guidance_key","")==current.request_key and (int(movement.get("target_floor",floor_id))!=floor_id or movement.get("target_cell",[])!=cell):
		_cancel_own_move(world,visit.actor_id,current)
		movement=world.facts.moves.get(visit.actor_id,{})
	if not movement.is_empty():
		if movement.get("floor_guidance_key","")==current.request_key:
			# Movement owns safe retry/landing state. Only its current verified
			# route failure can replace an already-requested guidance journey.
			if not space.movement_failure(world,visit.actor_id).is_empty(): _reselect_unreachable_target(world,visit,current)
			return
		if waiting==null or not waiting.call_patient(world,visit.id): return
		world.facts.tickets[visit.ticket_id].called_tick = -1
	elif waiting!=null: waiting._release_seat(world,visit.id)
	var reason: String = space.request_floor_move(world,visit.actor_id,floor_id,cell) if int(world.facts.actors[visit.actor_id].location.get("floor_id",0))==floor_id else space.request_move(world,visit.actor_id,floor_id,cell)
	if reason.is_empty() and world.facts.moves.has(visit.actor_id):
		world.facts.moves[visit.actor_id].floor_guidance_key = current.request_key
		world.facts.moves[visit.actor_id].floor_guidance_visit_id = visit.id
	elif not reason.is_empty():
		if current.get("phase","")=="seek":
			current.erase("queue_trip")
			_queue_blocked(world,visit,current)
		elif not _reselect_unreachable_target(world,visit,current): visit.waiting_reason = reason

func _reselect_unreachable_target(world: WorldState, visit: Dictionary, current: Dictionary) -> bool:
	# Ordinary referrals re-evaluate only at an actual journey boundary.
	# Surgical referrals retain their original removal-only reset rule.
	var target_id: String = str(current.get("target_id",""))
	var surgical: bool=world.facts.tickets.get(str(current.get("ticket_id","")),{}).get("kind","")=="surgery"
	if target_id.is_empty() or (not surgical and _destination_underway(world,visit,current)): return false
	if world.facts.facilities.has(target_id) and (surgical or space.movement_failure(world,visit.actor_id).is_empty()): return false
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	if actor.location.kind!="floor": return false
	_reset_destination(world,visit,current)
	current.target_id = ""
	current.guide_floor = int(actor.location.floor_id)
	visit.waiting_reason = "原目的地已拆除或实际无法继续前往，回本层导诊台重新排队"
	return true

func _has_own_single_move(world: WorldState, actor_id: String, current: Dictionary) -> bool:
	var move: Dictionary=world.facts.moves.get(actor_id,{})
	return not move.is_empty() and move.get("floor_guidance_key","")==current.get("request_key","") and not move.has("convoy")

func _cancel_own_move(world: WorldState, actor_id: String, current: Dictionary) -> void:
	var move: Dictionary = world.facts.moves.get(actor_id,{})
	if move.get("floor_guidance_key","")!=current.get("request_key","") or move.has("convoy"): return
	if move.has("detour"):
		var actor: Dictionary=world.facts.actors[actor_id]
		if actor.location.kind!="floor" or not space.public_areas.safe_wait(world,actor_id,int(actor.location.floor_id),actor.location.cell): return
	# A single actor already standing on safe public ground can hand off its
	# old detour. Otherwise a newly occupied destination could keep an obsolete
	# move alive forever while the guidance owner repeatedly chooses a new one.
	space.cancel_ground_move(world,actor_id)

func _destination_underway(world: WorldState, visit: Dictionary, current: Dictionary) -> bool:
	var move: Dictionary=world.facts.moves.get(visit.actor_id,{})
	return move.get("floor_guidance_key","")==current.request_key and not move.is_empty() and space.movement_failure(world,visit.actor_id).is_empty()

func _approach_destination(world: WorldState, visit: Dictionary, ticket: Dictionary, current: Dictionary) -> bool:
	if ticket.kind!="surgery" and _destination_underway(world,visit,current): return false
	if not _target_valid(world,visit,ticket,str(current.target_id)):
		_reset_destination(world,visit,current)
		current.target_id = ""
		current.guide_floor = int(world.facts.actors[visit.actor_id].location.floor_id)
		return false
	var floor_id: int = int(world.facts.facilities[current.target_id].floor_id)
	if int(current.guide_floor)!=floor_id:
		current.guide_floor = floor_id
		_change_desk(world,visit,current,"")
		current.phase = "seek"
		return false
	if not current.has("destination_cell") or not scope.allows(world,visit.actor_id,str(current.target_id),floor_id,current.destination_cell) or not space.public_areas.safe_wait(world,visit.actor_id,floor_id,current.destination_cell):
		var point: Dictionary = scope.point(world,visit.actor_id,str(current.target_id))
		if point.is_empty():
			if _reselect_unreachable_target(world,visit,current): return false
			visit.waiting_reason = "目的地附近没有合法候诊位置，等待通路恢复"
			return false
		_cancel_own_move(world,visit.actor_id,current)
		current.destination_cell = point.cell
	if not space.at(world,visit.actor_id,floor_id,current.destination_cell) or world.facts.moves.has(visit.actor_id):
		_move(world,visit,current,floor_id,current.destination_cell)
		if current.phase=="seek": return false
		visit.waiting_reason = "正在前往护士指定目的地，尚未加入当地队列"
		return false
	if int(current.get("arrived_seq",-1))<0:
		if ticket.kind=="surgery":
			world.facts.floor_guidance.next_arrival+=1
			current.arrived_seq=world.facts.floor_guidance.next_arrival
		current.destination_arrived_tick = world.sim_tick
	current.phase = "ready"
	current.reason = ""
	visit.waiting_reason = "已到达指定目的地，等待叫号"
	return true

func advance(world: WorldState) -> void:
	for id: String in world.facts.get("floor_guidance",{}).get("visits",{}).keys():
		var current: Dictionary = state(world,id)
		if current.get("phase","")!="working": continue
		var visit: Dictionary = world.facts.visits[id]
		if _reselect_unreachable_target(world,visit,current): continue
		var layout: Dictionary = space.facility_layout(world,str(current.desk_id))
		if not space.at(world,visit.actor_id,int(layout.floor_id),layout.patient_cell) or not space.at(world,str(current.nurse_id),int(layout.floor_id),layout.operator_cells[0]) or world.facts.moves.has(visit.actor_id) or world.facts.moves.has(str(current.nurse_id)): continue
		_worked[current.nurse_id] = true
		current.remaining_ticks -= 1
		if int(current.remaining_ticks)>0: continue
		var ticket: Dictionary = world.facts.tickets.get(visit.get("ticket_id",""),{})
		if _target_ids(world,visit,str(ticket.get("kind",""))).is_empty():
			_release_counter(world,visit,current)
			current.phase="desk_queue"
			current.arrangement_done=true
			_depart_missing_destination(world,visit,current)
			continue
		_finish_arrangement(world,visit,ticket,current)

func _finish_arrangement(world: WorldState, visit: Dictionary, ticket: Dictionary, current: Dictionary) -> void:
	# The destination-floor desk continues the same surgical referral. A new
	# independent clinical request starts with an empty target in prepare().
	if ticket.get("kind","")!="surgery" or str(current.get("target_id","")).is_empty():
		current.target_id=_choose_target(world,visit,ticket)
	if str(current.target_id).is_empty():
		_release_counter(world,visit,current)
		current.arrangement_done=true
		_depart_missing_destination(world,visit,current)
		return
	current.target_room_id=str(world.facts.facilities[current.target_id].get("room_id",""))
	current.receipts.append({"request_key":current.request_key,"floor_id":current.guide_floor,"desk_id":current.desk_id,"nurse_id":current.get("nurse_id",""),"started_tick":current.get("started_tick",world.sim_tick),"completed_tick":world.sim_tick})
	if clinic.recruitment!=null: clinic.recruitment.service_mood(world,str(current.get("nurse_id","")),"guidance",visit.id,current.receipts[-1])
	current.initial_done=true
	current.erase("arrangement_done")
	_release_counter(world,visit,current)
	_queue_leave(world,current)
	current.erase("queue_seq")
	current.phase="destination"
	current.guided_target=current.target_id
	if ticket.kind!="surgery":
		world.facts.floor_guidance.next_arrival+=1
		current.arrived_seq=world.facts.floor_guidance.next_arrival
	if ticket.get("kind","") in ["gp","consult","plan"]:
		if visit.get("continuation",{}).get("stage","")=="guidance": visit.continuation.stage="continuing"
		var room_id: String=str(world.facts.facilities[current.target_id].get("room_id",""))
		var queue: Dictionary=world.facts.floor_guidance.clinic_queues.get_or_add(room_id,{"visit_ids":[],"called_id":"","deadline_tick":-1})
		if not visit.id in queue.visit_ids: queue.visit_ids.append(visit.id)

func _release_counter(world: WorldState, visit: Dictionary, current: Dictionary) -> void:
	var held: Dictionary = world.facts.adaptations.get(str(current.get("desk_id","")),{})
	if held.get("owner_id","")=="floor_guide:"+visit.id:
		held.owner_id = visit.actor_id
		# The dedicated nurse remains at this desk, but the completed patient
		# alone owns the short physical exit. Do not retain a previous patient
		# reservation forever merely because the next nurse is still at work.
		held.staff_ids = []
		space.reservation_changed(world,str(current.desk_id))
		space._navigation.invalidate(world,int(held.floor_id))
	space.release_adaptations(world)

func release(world: WorldState, visit_id: String) -> void:
	for queue: Dictionary in world.facts.get("floor_guidance",{}).get("clinic_queues",{}).values():
		queue.visit_ids.erase(visit_id)
		if queue.called_id==visit_id: queue.called_id=""; queue.deadline_tick=-1
	var current: Dictionary = state(world,visit_id)
	if current.is_empty(): return
	var visit: Dictionary = world.facts.visits.get(visit_id,{})
	if not visit.is_empty():
		_cancel_own_move(world,visit.actor_id,current)
		_release_counter(world,visit,current)
	_queue_leave(world,current)
	world.facts.floor_guidance.visits.erase(visit_id)

func _can_answer_call(world: WorldState, visit_id: String) -> bool:
	# Ready records a prior arrival, not availability while a life need owns
	# the patient's journey. Timeout rotation must not seize that movement.
	return state(world,visit_id).get("phase","")=="ready" and not world.facts.get("waiting_life",{}).get("needs",{}).has(visit_id)

func can_call(world: WorldState, visit: Dictionary, ticket: Dictionary) -> bool:
	if ticket.has("resume_session_id") or ticket.get("service_assigned",false): return true
	if ticket.kind in ["consult","plan"] and visit.get("continuation",{}).get("stage","")=="guidance": return true
	if not ticket.kind in ["gp","consult","plan"]: return true
	var current: Dictionary=state(world,visit.id)
	var room_id: String=target_room(world,visit.id)
	if room_id.is_empty(): return false
	var queue: Dictionary=world.facts.floor_guidance.clinic_queues.get(room_id,{})
	if queue.is_empty(): return false
	# Only the live head can be called. Departure owners remove their own
	# membership immediately; stale external rows are pruned as they reach it.
	while not queue.visit_ids.is_empty():
		var id: String=str(queue.visit_ids[0])
		if world.facts.visits.has(id) and not world.facts.visits[id].get("phase","") in ["leaving","departed"]: break
		queue.visit_ids.pop_front()
	if queue.visit_ids.is_empty(): return false
	var head: String=str(queue.visit_ids[0])
	var expired: bool=not _can_answer_call(world,head) and queue.visit_ids.size()>1 and world.sim_tick>=int(queue.deadline_tick)
	if visit.id!=head and queue.called_id==head and not expired: return false
	for session: Dictionary in world.facts.sessions.values():
		if world.facts.facilities[session.facility_id].get("room_id","")==room_id: return false
	if queue.called_id!=head:
		queue.called_id=head
		queue.deadline_tick=world.sim_tick+300
	if not _can_answer_call(world,head) and queue.visit_ids.size()>1 and world.sim_tick>=int(queue.deadline_tick):
		# A timeout counts three live waiting people, never abandoned tail rows.
		for index: int in range(queue.visit_ids.size()-1,0,-1):
			var id: String=str(queue.visit_ids[index])
			if not world.facts.visits.has(id) or world.facts.visits[id].get("phase","") in ["leaving","departed"]: queue.visit_ids.remove_at(index)
		if queue.visit_ids.size()==1: return visit.id==head
		queue.visit_ids.pop_front()
		queue.visit_ids.insert(mini(3,queue.visit_ids.size()),head)
		queue.called_id=""
		queue.deadline_tick=-1
		head=str(queue.visit_ids[0])
	return visit.id==head

func ordered_tickets(world: WorldState) -> Array:
	var ids: Array = world.ids("tickets")
	# One synchronous ordering reads each live key once. No queue or ordering
	# survives this call; the next dispatch observes every arrival/removal.
	var sequence: Dictionary={}
	for id: String in ids:
		var arrived: int=int(state(world,world.facts.tickets[id].visit_id).get("arrived_seq",-1))
		sequence[id]=9223372036854775807 if arrived<0 else arrived
	ids.sort_custom(func(a: String,b: String)->bool:
		var sa: int=sequence[a]
		var sb: int=sequence[b]
		if sa!=sb: return sa<sb
		return a<b)
	return ids

func validate(world: WorldState) -> String:
	var nurses: Dictionary = {}
	for desk: Dictionary in world.facts.get("floor_guidance",{}).get("desks",{}).values():
		var id: String = str(desk.get("nurse_id",""))
		if id.is_empty(): continue
		if nurses.has(id) or not world.facts.staff.has(id): return "楼层导诊护士重复指派或缺失"
		nurses[id] = true
		if world.facts.staff[id].get("active_job_id","")!="floor_desk:"+str(desk.id): return "楼层导诊护士岗位归属无效"
	return ""

static func owns_reservation(world: WorldState, reservation: Dictionary) -> bool:
	var owner: String = str(reservation.get("owner_id",""))
	if not owner.begins_with("floor_guide:"): return false
	var visit_id: String = owner.trim_prefix("floor_guide:")
	var current: Dictionary = world.facts.get("floor_guidance",{}).get("visits",{}).get(visit_id,{})
	if current.get("desk_id","")!=reservation.get("facility_id","") or not current.get("phase","") in ["to_counter","working"]: return false
	var visit: Dictionary = world.facts.visits.get(visit_id,{})
	var ticket: Dictionary = world.facts.tickets.get(str(current.get("ticket_id","")),{})
	var desk: Dictionary = world.facts.floor_guidance.desks.get(str(current.desk_id),{})
	var nurse: String = str(current.get("nurse_id",""))
	return not nurse.is_empty() and desk.get("nurse_id","")==nurse and world.facts.staff.get(nurse,{}).get("active_job_id","")=="floor_desk:"+str(current.desk_id) and visit.get("ticket_id","")==current.get("ticket_id","") and ticket.get("visit_id","")==visit_id and current.get("request_key","")==str(ticket.get("id",""))+":"+str(ticket.get("kind","")) and reservation.get("actor_id","")==visit.get("actor_id","") and reservation.get("staff_ids",[])==[nurse]

func pause_for_need(world: WorldState, visit: Dictionary) -> void:
	var current: Dictionary = state(world,visit.id)
	if not current.is_empty():current.queue_attending=false
	if current.get("phase","")=="to_counter":
		_release_counter(world,visit,current)
		current.phase = "desk_queue"

func _return_scope(world: WorldState, visit: Dictionary) -> String:
	var current: Dictionary = state(world,visit.id)
	if current.is_empty(): return ""
	if current.get("phase","") in ["ready","destination"]:
		var ticket: Dictionary = world.facts.tickets.get(visit.get("ticket_id",""),{})
		if not ticket.is_empty(): _refresh_target_anchor(world,visit,ticket,current)
		if not ticket.is_empty() and _target_valid(world,visit,ticket,str(current.get("target_id",""))): return str(current.target_id)
		# A clinic can legally disappear while the patient uses a life service.
		# End that safe service first, then return to guidance, not a dead anchor.
		_reset_destination(world,visit,current)
		current.target_id = ""
		current.guide_floor = int(world.facts.actors[visit.actor_id].location.get("floor_id",current.guide_floor))
	var id: String = str(current.get("desk_id",""))
	if _desk_open(world,id): return id
	for candidate: String in world.facility_ids("SE01"):
		if not _desk_open(world,candidate) or int(world.facts.facilities[candidate].floor_id)!=int(current.guide_floor): continue
		if scope.point(world,visit.actor_id,candidate).is_empty(): continue
		_change_desk(world,visit,current,candidate)
		return candidate
	_change_desk(world,visit,current,"")
	return ""

func return_point(world: WorldState, visit: Dictionary) -> Dictionary:
	var id: String = _return_scope(world,visit)
	if not id.is_empty(): return scope.point(world,visit.actor_id,id)
	var exit: Dictionary=space.public_areas.room_exit_point(world,visit.actor_id)
	if not exit.is_empty(): return exit
	# With no surviving desk, enter a legal waiting area before choosing a
	# safe local stop. Being inside a region is not proof of safe standing.
	# Neither step clears guidance or grants a destination queue place.
	var area: Dictionary = space.public_areas.current_area(world,visit.actor_id)
	var point: Dictionary = {}
	if space.public_areas.area_valid(world,area,HospitalWaitingLife.WAITING_ROOM_KINDS) and space.public_areas.contains(world,area,visit.actor_id):
		point = space.public_areas.waiting_point(world,visit.actor_id,area)
		if not point.is_empty(): point.area = area
	else:
		point=space.public_areas.select(world,visit.actor_id,[],HospitalWaitingLife.WAITING_ROOM_KINDS,"waiting",[],9223372036854775807,{},true)
	return space.public_areas.floor_waiting_point(world,visit.actor_id) if point.is_empty() else point

# A return journey can aim through a doorway that is not a safe stopping
# point. The original need owns that move; return_allows remains the separate
# proof required at the actual resting position after movement completes.
func return_target_valid(world: WorldState, visit: Dictionary, floor_id: int, cell: Array, area: Dictionary) -> bool:
	var id: String = _return_scope(world,visit)
	if not id.is_empty(): return scope.allows(world,visit.actor_id,id,floor_id,cell)
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	if actor.location.kind!="floor" or int(actor.location.floor_id)!=floor_id: return false
	var point:=Vector2i(floori(cell[0]),floori(cell[1]))
	if space.room_use.room_at(world,floor_id,point).is_empty() and space.room_use.public_point(world,floor_id,point): return true
	return int(area.get("floor_id",0))==floor_id and space.public_areas.area_valid(world,area,HospitalWaitingLife.WAITING_ROOM_KINDS)

func return_allows(world: WorldState, visit: Dictionary, floor_id: int, cell: Array) -> bool:
	var id: String = _return_scope(world,visit)
	if not id.is_empty(): return scope.allows(world,visit.actor_id,id,floor_id,cell)
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	return actor.location.kind=="floor" and int(actor.location.floor_id)==floor_id and space.public_areas.safe_wait(world,visit.actor_id,floor_id,cell)

func _ready_target(world: WorldState, visit: Dictionary, ticket: Dictionary, facility_id: String = "") -> String:
	if clinic==null: return ""
	if not facility_id.is_empty() and not _target_valid(world,visit,ticket,facility_id): return ""
	var selected: String = _ready_candidate(world,visit,ticket,facility_id)
	if not selected.is_empty() and _target_valid(world,visit,ticket,selected): return selected
	if not facility_id.is_empty(): return ""
	# A quote still has to belong to an available room on this floor.
	for id: String in _target_ids(world,visit,str(ticket.kind)):
		if id!=selected and _ready_candidate(world,visit,ticket,id)==id: return id
	return ""

func _ready_candidate(world: WorldState, visit: Dictionary, ticket: Dictionary, facility_id: String) -> String:
	if ticket.kind=="surgery":
		var quote: Dictionary = clinic._surgery_quote(world,visit,[],{} if facility_id.is_empty() else {"facility_id":facility_id})
		return str(quote.facility_id) if quote.get("ok",false) else ""
	if ticket.kind=="consult":
		var consultation: Dictionary = {}
		clinic._select_plan(world,visit,"",consultation,facility_id)
		return str(consultation.get("pair",{}).get("facility_id",""))
	var selection: Dictionary = {"first_only":true}
	clinic._destination_selection(world,selection,facility_id)
	if ticket.kind=="outpatient":
		var status: Dictionary = {"reason":"","policy_ok":false,"review_quote":{}}
		var plan_id: String = str(visit.plan_decision.get("plan_id",visit.requested_plan_id))
		selection.eligible = clinic._plan_candidate_eligible.bind(world,visit,plan_id,status)
		selection.accept = clinic._accept_outpatient_dispatch.bind(world,visit,status)
	var choices: Array = clinic.service_candidates(world,visit,str(ticket.kind),false,false,selection)
	return "" if choices.is_empty() else str(choices[0].facility_id)

func _retain_departing_nurse_access(world: WorldState, desk_id: String, nurse_id: String) -> void:
	# Keep the original participant able to leave its own still-held service
	# region. Membership ends with this reservation, not a separate movement rule.
	# Ordinary staffed completion does not take this departure branch.
	var held: Dictionary=world.facts.adaptations.get(desk_id,{})
	var actor: Dictionary=world.facts.actors.get(nurse_id,{})
	if held.get("kind","")!="facility" or actor.get("location",{}).get("kind","")!="floor":return
	if int(actor.location.floor_id)!=int(held.floor_id) or nurse_id in held.staff_ids:return
	var body: Rect2=space.body_rectangle(actor)
	for area: Array in held.regions:
		if body.intersects(Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3])),false):
			held.staff_ids.append(nurse_id)
			space.reservation_changed(world,desk_id)
			space._navigation.invalidate(world,int(held.floor_id))
			return

func _release_nurses(world: WorldState) -> void:
	for id: String in world.facts.floor_guidance.releases.keys():
		var release: Dictionary = world.facts.floor_guidance.releases[id]
		if not world.facts.staff.has(id):
			world.facts.floor_guidance.releases.erase(id)
			continue
		var actor: Dictionary = world.facts.actors[id]
		if actor.location.kind!="floor": continue
		var move: Dictionary = world.facts.moves.get(id,{})
		if not move.is_empty():
			if move.get("guidance_nurse_desk","")==release.desk_id and not move.has("detour") and not move.has("convoy"):
				if not space.cancel_ground_move(world,id): continue
			else: continue
		var prior: Rect2 = Rect2(Vector2(float(release.cell[0]),float(release.cell[1])),Vector2.ONE*int(release.clearance))
		var floor_id: int=int(actor.location.floor_id)
		var desk: Dictionary=world.facts.facilities.get(str(release.desk_id),{})
		var desk_here: bool=not desk.is_empty() and int(desk.floor_id)==floor_id
		var prior_here: bool=int(release.floor_id)==floor_id
		if (not desk_here or not prior_here or not space.body_rectangle(actor).intersects(prior,false)) and space.public_areas.safe_wait(world,id,floor_id,actor.location.cell):
			var staff: Dictionary = world.facts.staff[id]
			if staff.get("active_job_id","")=="floor_desk_release:"+str(release.desk_id):
				staff.active_job_id = ""
				# Rest may have been requested while this safe desk handoff was
				# still running. Its former job position is no longer ours after
				# replacement; return only to the actual released public point.
				var life: Dictionary = staff.get("life_task",{})
				var back: Dictionary = life.get("return_location",{})
				if back.get("kind","")=="floor" and int(back.get("floor_id",0))==int(release.floor_id) and back.get("cell",[])==release.cell:
					life.return_location = actor.location.duplicate(true)
			world.facts.floor_guidance.releases.erase(id)
			continue
		var point: Dictionary
		if desk_here:
			point=scope.point(world,id,str(release.desk_id),prior if prior_here else Rect2())
		else:
			point=_nurse_local_release_point(world,id)
		if point.is_empty():
			world.facts.staff[id].life_reason = "等待导诊岗位的真实安全离位空间"
			continue
		var reason: String=space.request_floor_move(world,id,int(point.floor_id),point.cell)
		if not reason.is_empty(): world.facts.staff[id].life_reason=reason

func _nurse_local_release_point(world: WorldState, id: String) -> Dictionary:
	# A cancelled cross-floor approach never owned a work slot on this floor.
	# Clear its actual landing/body safely instead of returning to the old desk.
	var floor_id: int=int(world.facts.actors[id].location.floor_id)
	var area: Dictionary=space.public_areas.current_area(world,id)
	var point: Dictionary=space.public_areas.waiting_point(world,id,area)
	if point.is_empty():
		var arrival: Dictionary=space.public_areas.select(world,id,[],HospitalWaitingLife.WAITING_ROOM_KINDS,"waiting",[],9223372036854775807,{},true)
		if not arrival.is_empty(): point=space.public_areas.waiting_point(world,id,arrival.area)
	return point if not point.is_empty() and int(point.floor_id)==floor_id else {}

static func validate_state(world: WorldState) -> String:
	if not world.facts.has("floor_guidance"): return ""
	var data: Variant = world.facts.floor_guidance
	if not data is Dictionary or not data.get("visits") is Dictionary or not data.get("desks") is Dictionary or not data.get("releases",{}) is Dictionary or not WorldState._natural(data.get("next_arrival",-1)): return "楼层导诊状态结构无效"
	var nurses: Dictionary = {}
	var queues: Dictionary = {}
	var active_desks: Dictionary = {}
	var queued_visits: Dictionary = {}
	var clinical_visits: Dictionary={}
	if not data.get("clinic_queues",{}) is Dictionary: return "门诊安排队列集合无效"
	for room_id: String in data.get("clinic_queues",{}):
		var queue: Variant=data.clinic_queues[room_id]
		if not queue is Dictionary or not queue.get("visit_ids") is Array or not queue.get("called_id") is String or not queue.get("deadline_tick") is int or int(queue.deadline_tick)<-1: return "门诊叫号状态无效"
		for visit_id: Variant in queue.visit_ids:
			if not visit_id is String or not world.facts.visits.has(visit_id) or clinical_visits.has(visit_id): return "门诊安排顺序重复或病例缺失"
			clinical_visits[visit_id]=true
		if not str(queue.called_id).is_empty() and (queue.visit_ids.is_empty() or queue.called_id!=queue.visit_ids[0]): return "门诊叫号与队首不一致"
	for id: Variant in data.desks:
		var desk: Variant = data.desks[id]
		if not id is String or not desk is Dictionary or desk.get("id")!=id or not desk.get("nurse_id") is String or not desk.get("reason") is String: return "楼层导诊台岗位结构无效"
		if desk.has("queue"):
			if not desk.queue is Array:return "导诊台队列数组无效"
			var prior: int=-1
			for visit_id: Variant in desk.queue:
				var row: Dictionary=data.visits.get(visit_id,{})
				# A missing destination keeps this desk's fair sequence while
				# releasing counter work; it is still a saved queue member.
				if not visit_id is String or queued_visits.has(visit_id) or row.get("desk_id","")!=id or not row.has("queue_seq") or row.get("phase","") not in ["desk_queue","to_counter","working","blocked_destination"]:return "导诊台队列成员归属无效"
				if int(row.queue_seq)<=prior:return "导诊台队列顺序无效"
				prior=int(row.queue_seq)
				queued_visits[visit_id]=id
		var nurse: String = str(desk.nurse_id)
		if nurse.is_empty(): continue
		if nurses.has(nurse) or not world.facts.staff.has(nurse) or world.facts.staff[nurse].role!="nurse" or world.facts.staff[nurse].get("active_job_id","")!="floor_desk:"+str(id): return "楼层导诊护士被重复指派或岗位归属无效"
		nurses[nurse] = true
	for id: Variant in data.releases:
		var release: Variant = data.releases[id]
		if not id is String or not release is Dictionary or not release.get("desk_id") is String or not WorldState._natural(release.get("floor_id",-1)) or not world.facts.staff.has(id) or nurses.has(id): return "楼层导诊护士离岗交接无效"
		if int(release.floor_id)<1 or not WorldState._point(release.get("cell")) or not WorldState._natural(release.get("clearance",-1)) or int(release.clearance)<1: return "楼层导诊离岗位置无效"
		if world.facts.staff[id].get("active_job_id","")!="floor_desk_release:"+str(release.desk_id): return "楼层导诊离岗责任丢失"
	for id: Variant in data.visits:
		var row: Variant = data.visits[id]
		if not id is String or not row is Dictionary or not world.facts.visits.has(id) or row.get("visit_id")!=id: return "楼层导诊病例引用无效"
		for field: String in ["request_key","ticket_id","target_id","desk_id","guided_target","reason"]:
			if not row.get(field) is String: return "楼层导诊目的地状态无效"
		if row.has("target_room_id") and not row.target_room_id is String: return "楼层导诊原房间身份无效"
		if not row.get("phase","") in ["seek","desk_queue","to_counter","working","destination","ready","blocked_destination"] or not row.get("initial_done") is bool or not WorldState._natural(row.get("guide_floor",-1)) or int(row.guide_floor)<1 or not row.get("arrived_seq") is int or int(row.arrived_seq)<-1 or not row.get("receipts") is Array: return "楼层导诊阶段或到达顺序无效"
		if row.has("floor_trip"):
			var trip: Variant=row.floor_trip
			if not trip is Dictionary or not WorldState._natural(trip.get("floor_id",-1)) or int(trip.floor_id)<1 or not trip.get("cell") is Array or not trip.cell.is_empty() and not WorldState._point(trip.cell): return "导诊目标层行程无效"
		if not WorldState._natural(row.get("next_recheck",-1)) or row.has("route_at_desk") and not row.route_at_desk is bool: return "楼层导诊复查状态无效"
		if int(row.arrived_seq)>int(data.next_arrival): return "楼层导诊目的地顺序超出已发生到达"
		for field: String in ["queue_cell","queue_trip","destination_cell"]:
			if row.has(field) and not WorldState._point(row[field]): return "楼层导诊移动位置无效"
		if row.has("queue_seq"):
			if data.desks.get(row.desk_id,{}).has("queue") and not queued_visits.has(id):return "导诊排队患者缺少台队列成员记录"
			if not WorldState._natural(row.queue_seq) or int(row.queue_seq)>int(data.next_arrival) or queues.has(int(row.queue_seq)): return "楼层导诊排队顺序无效"
			queues[int(row.queue_seq)] = true
			if row.has("queue_desk_id") and row.queue_desk_id!=row.desk_id: return "楼层导诊排队资格不属于当前台"
		if row.phase in ["to_counter","working"] and (not world.facts.staff.has(row.get("nurse_id","")) or not world.facts.facilities.has(row.desk_id) or not world.facts.tickets.has(row.ticket_id)): return "楼层导诊正在服务的参与者缺失"
		if row.phase in ["to_counter","working"]:
			if active_desks.has(row.desk_id): return "同一导诊台不能同时服务两名患者"
			active_desks[row.desk_id] = id
			# A movement intention may still be waiting on a previous physical
			# exit. Working alone requires this head's live use reservation.
			if row.phase=="working":
				var reservation: Dictionary = world.facts.adaptations.get(row.desk_id,{})
				if reservation.get("owner_id","")!="floor_guide:"+str(id) or not owns_reservation(world,reservation): return "楼层导诊台服务与病例、护士或预约不一致"
		if row.phase=="working" and (not WorldState._natural(row.get("remaining_ticks",-1)) or int(row.remaining_ticks)<1 or not WorldState._natural(row.get("started_tick",-1))): return "楼层导诊工作余量无效"
		for receipt: Variant in row.receipts:
			if not receipt is Dictionary or not receipt.get("request_key") is String or not receipt.get("desk_id") is String or not receipt.get("nurse_id") is String or not WorldState._natural(receipt.get("floor_id",-1)) or not WorldState._natural(receipt.get("started_tick",-1)) or not WorldState._natural(receipt.get("completed_tick",-1)) or int(receipt.completed_tick)<int(receipt.started_tick): return "楼层导诊完成凭据无效"
	return ""

func summary(world: WorldState) -> String:
	var floors: Dictionary = {}
	for key: String in world.facts.floors.overrides:
		var id: int = int(key)
		if not HospitalSpace.floor_plots(world,id).is_empty(): floors[id] = {"desks":0,"nurses":0,"queue":0}
	for id: String in world.facility_ids("SE01"):
		var floor_id: int = int(world.facts.facilities[id].floor_id)
		var count: Dictionary = floors.get_or_add(floor_id,{"desks":0,"nurses":0,"queue":0})
		count.desks += 1
		var desk: Dictionary = world.facts.get("floor_guidance",{}).get("desks",{}).get(id,{})
		var nurse: String = str(desk.get("nurse_id",""))
		var layout: Dictionary = space.facility_layout(world,id)
		if _desk_open(world,id) and not nurse.is_empty() and world.facts.actors.has(nurse) and not world.facts.moves.has(nurse) and space.at(world,nurse,floor_id,space.guidance_operator_cell(world,id,nurse)): count.nurses += 1
	for row: Dictionary in world.facts.get("floor_guidance",{}).get("visits",{}).values():
		if row.get("phase","") in ["seek","desk_queue","to_counter","working","blocked_destination"] and floors.has(int(row.guide_floor)): floors[int(row.guide_floor)].queue += 1
	var ids: Array = floors.keys(); ids.sort()
	var lines: Array[String] = []
	for id: int in ids:
		var count: Dictionary = floors[id]
		lines.append("%d层：导诊台%d · 到岗护士%d · 导诊等待%d%s"%[id,count.desks,count.nurses,count.queue,"；请补设导诊台" if int(count.desks)==0 else "；缺当班护士或通路" if int(count.nurses)<int(count.desks) else ""])
	return "\n".join(lines)
