class_name HospitalFloorGuidance
extends RefCounted

const Scope = preload("res://game/operations/clinic_waiting_scope.gd")
var content: HospitalContent
var space: HospitalSpace
var clinic: HospitalClinic
var waiting: HospitalWaitingLife
var scope: RefCounted
var _worked: Dictionary = {}

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry
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
	var charge_before: int=cache._charged+cache._query_charged+cache._source_charged+cache._floor_charged
	var anchors: Array[Vector2i]=[]
	for id: String in world.ids("connectors"):
		var connection: Dictionary=world.facts.connectors[id]
		if content.definition("vertical_connectors",connection.definition_id).kind!="lift" or not HospitalTransit.has_stop(connection,floor_id): continue
		var anchor:=Vector2i(int(connection.anchor[0]),int(connection.anchor[1]))
		if not anchor in anchors: anchors.append(anchor)
	var desks: Array=[]
	for id: String in world.facility_ids("SE01"):
		if int(world.facts.facilities[id].floor_id)==floor_id: desks.append(id)
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
				var area: Dictionary=scope.area(world,actor_id,desk_id)
				for point: Vector2i in area.get("points",{}): goals[point]=true
				var cell: Array=space.facility_layout(world,desk_id).patient_cell
				goals[Vector2i(roundi(cell[0]),roundi(cell[1]))]=true
			for anchor: Vector2i in anchors:
				for goal: Vector2i in goals:
					var result: Dictionary=cache.cached_floor_path(space,world,floor_id,actor,graph,graph.geometry,anchor,goal)
					attempted+=1
					if result.get("ok",false): reachable+=1
	var charge_after: int=cache._charged+cache._query_charged+cache._source_charged+cache._floor_charged
	space.navigation._observed_floors=observed
	return {"elapsed_usec":Time.get_ticks_usec()-started,"body_envelopes":seen.size(),"lift_anchors":anchors.size(),"desks":desks.size(),"path_requests":attempted,"reachable":reachable,"path_builds":int(space.query_counts.static_path_builds)-builds_before,"path_hits":int(space.query_counts.static_path_hits)-hits_before,"cache_charge_before":charge_before,"cache_charge_after":charge_after,"cache_budget":int(content.balance.pathfinding.graph_cache_target_bytes)}

func ensure(world: WorldState) -> void:
	if not world.facts.has("floor_guidance"):
		world.facts.floor_guidance = {"visits":{},"desks":{},"releases":{},"next_arrival":0}
	if not world.facts.floor_guidance.has("releases"): world.facts.floor_guidance.releases = {}

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
	_release_nurses(world)
	_assign_desks(world)

func _desk_open(world: WorldState, id: String) -> bool:
	var f: Dictionary = world.facts.facilities.get(id,{})
	return f.get("definition_id","")=="SE01" and not f.get("failed",false) and f.get("open",true) and f.get("intake_open",true) and not HospitalRemodel.blocked(world,id)

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
		for state: Dictionary in world.facts.floor_guidance.visits.values():
			if state.get("desk_id","")==id and state.get("phase","")=="working": working = true
		if not working and (not _desk_open(world,id) or not _nurse_ready(world,nurse)):
			# A not-yet-started counter approach belongs to this desk, not to
			# the departing nurse. Keep its same-desk queue place for relief.
			for current: Dictionary in world.facts.floor_guidance.visits.values():
				if current.get("desk_id","")==id and current.get("phase","")=="to_counter":
					var visit: Dictionary = world.facts.visits[current.visit_id]
					_cancel_own_move(world,visit.actor_id,current)
					_release_counter(world,visit,current)
					current.phase = "desk_queue"
					current.erase("nurse_id")
			if world.facts.staff.has(nurse) and world.facts.staff[nurse].get("active_job_id","")=="floor_desk:"+id:
				world.facts.staff[nurse].active_job_id = "floor_desk_release:"+id
				world.facts.floor_guidance.releases[nurse] = {"desk_id":id,"floor_id":int(world.facts.actors[nurse].location.get("floor_id",world.facts.facilities.get(id,{}).get("floor_id",1))),"cell":world.facts.actors[nurse].location.get("cell",[0,0]).duplicate(),"clearance":space.clearance(world.facts.actors[nurse])}
			desk.nurse_id = ""
		if not world.facts.facilities.has(id): desks.erase(id)
	for id: String in world.facility_ids("SE01"):
		var desk: Dictionary = desks.get_or_add(id,{"id":id,"nurse_id":"","reason":""})
		if not _desk_open(world,id):
			desk.reason = "导诊台关闭、故障或正在改建"
			continue
		if str(desk.nurse_id).is_empty():
			for nurse: String in world.ids("staff"):
				if not _nurse_ready(world,nurse) or HospitalClinicalDevelopment.safe_busy(world,nurse) or _clinical_responsibility(world,nurse) or world.facts.moves.has(nurse): continue
				var staff: Dictionary = world.facts.staff[nurse]
				if not staff.get("base_task",{}).is_empty() or not staff.get("life_task",{}).get("phase","idle")=="idle": continue
				var layout: Dictionary = space.facility_layout(world,id)
				if not space.can_reach(world,nurse,int(layout.floor_id),space.guidance_operator_cell(world,id,nurse)): continue
				if HospitalStaffWellbeing.yield_for_work(world,content,space,[nurse]): continue
				desk.nurse_id = nurse
				staff.active_job_id = "floor_desk:"+id
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
	return str(ticket.id)+":"+str(ticket.kind)

func state(world: WorldState, visit_id: String) -> Dictionary:
	return world.facts.get("floor_guidance",{}).get("visits",{}).get(visit_id,{})

func waiting_allowed(world: WorldState, visit_id: String) -> bool:
	var current: Dictionary = state(world,visit_id)
	return current.is_empty() or current.get("phase","")=="ready"

func working(world: WorldState, visit_id: String) -> bool:
	return state(world,visit_id).get("phase","")=="working"

func target(world: WorldState, visit_id: String) -> String:
	return str(state(world,visit_id).get("target_id",""))

func prepare(world: WorldState, visit: Dictionary, ticket: Dictionary) -> bool:
	ensure(world)
	if ticket.has("resume_session_id"): return true
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
		previous = {"visit_id":visit.id,"request_key":_key(ticket),"ticket_id":ticket.id,"phase":"seek","target_id":"","desk_id":"","guide_floor":int(actor.location.get("floor_id",1)),"initial_done":initial_done,"receipts":receipts,"guided_target":"","arrived_seq":-1,"reason":"","next_recheck":0}
		world.facts.floor_guidance.visits[visit.id] = previous
	var current: Dictionary = previous
	if actor.location.kind!="floor":
		visit.waiting_reason = "正在真实前往本次就医楼层导诊"
		return false
	if not current.initial_done:
		current.guide_floor = int(current.guide_floor)
	elif not current.get("route_at_desk",false) and not _target_valid(world,visit,ticket,str(current.target_id)):
		_reset_destination(world,visit,current)
		current.target_id = _choose_target(world,visit,ticket)
		if str(current.target_id).is_empty():
			# A closed original department must not prevent the real desk visit
			# that can choose its replacement. Keep routing itself at the desk.
			if ticket.kind=="gp" and clinic.departments!=null and not clinic.departments.eligible_departments(world,visit.id,true).is_empty():
				current.route_at_desk = true
				current.guide_floor = int(actor.location.floor_id)
			else:
				visit.waiting_reason = "缺少适用于本次就医的开放目的地，保留待办"
				current.reason = visit.waiting_reason
				return false
		else: current.guide_floor = int(world.facts.facilities[current.target_id].floor_id)
	if current.phase=="ready":
		# Observe a genuine alternative service opportunity at the ordinary
		# behavior scan, not an every-tick all-hospital optimum search.
		if world.sim_tick>=int(current.next_recheck):
			current.next_recheck = world.sim_tick+maxi(1,int(float(content.balance.patient_behavior.scan_seconds)*10))
			if _reselect_unreachable_target(world,visit,current): return false
			var alternative: String = _ready_target(world,visit,ticket)
			if not alternative.is_empty() and alternative!=current.target_id and _ready_target(world,visit,ticket,str(current.target_id)).is_empty():
				_reset_destination(world,visit,current)
				current.target_id = alternative
				current.guide_floor = int(world.facts.facilities[current.target_id].floor_id)
		if current.phase=="ready": return true
	if current.phase=="destination": return _approach_destination(world,visit,ticket,current)
	if current.phase=="working":
		visit.waiting_reason = "护士正在导诊台安排本次目的地"
		return false
	return _approach_desk(world,visit,ticket,current)

func _target_valid(world: WorldState, visit: Dictionary, ticket: Dictionary, id: String) -> bool:
	if id.is_empty(): return false
	return id in _target_ids(world,visit,str(ticket.kind),id)

func _target_ids(world: WorldState, visit: Dictionary, kind: String, only_id: String = "") -> Array:
	var definition: String = "EQ01" if kind=="surgery" else "FUR02"
	if kind=="outpatient": definition = str(content.definition("treatment_routines",content.definition("treatment_bindings",visit.binding_id).routine_id).equipment_id)
	var ids: Array = []
	var department: Dictionary = world.facts.get("departments",{}).get("units",{}).get(str(visit.get("department_id","general")),{})
	if not department.get("open",true): return ids
	for id: String in (world.facility_ids(definition) if only_id.is_empty() else [only_id]):
		var f: Dictionary = world.facts.facilities.get(id,{})
		if f.is_empty() or f.get("definition_id","")!=definition: continue
		if f.get("failed",false) or not f.get("open",true) or not f.get("intake_open",true) or HospitalRemodel.blocked(world,id): continue
		if not clinic.service_room_reason(world,f).is_empty(): continue
		if not department.is_empty() and clinic.departments!=null and not clinic.departments._belongs(department,f): continue
		if kind in ["gp","spectrum","resonance","consult"] and not kind in ["consult"] and not kind in content.facility_definition(definition).get("diagnostic_modes",["gp","spectrum","resonance"]): continue
		if not space.facility_geometry_quote(world,id,visit.actor_id).get("ok",false): continue
		ids.append(id)
	return ids

func _choose_target(world: WorldState, visit: Dictionary, ticket: Dictionary) -> String:
	var ready: String = _ready_target(world,visit,ticket)
	if not ready.is_empty(): return ready
	var ids: Array = _target_ids(world,visit,str(ticket.kind))
	var loads: Dictionary = {}
	for row: Dictionary in world.facts.floor_guidance.visits.values():
		if row.get("phase","") in ["destination","ready"]: loads[row.target_id] = int(loads.get(row.target_id,0))+1
	ids.sort_custom(func(a: String,b: String)->bool:
		var la: int = int(loads.get(a,0)); var lb: int = int(loads.get(b,0))
		if la!=lb: return la<lb
		var da: int = space.facility_travel_lower_bound_ticks(world,a,visit.actor_id)
		var db: int = space.facility_travel_lower_bound_ticks(world,b,visit.actor_id)
		return da<db if da!=db else a<b)
	for id: String in ids:
		var layout: Dictionary = space.facility_layout(world,id)
		if space.can_reach(world,visit.actor_id,int(layout.floor_id),layout.patient_cell): return id
	return ""

func _change_desk(world: WorldState, visit: Dictionary, current: Dictionary, desk_id: String) -> void:
	if str(current.get("desk_id",""))==desk_id: return
	_cancel_own_move(world,visit.actor_id,current)
	_release_counter(world,visit,current)
	# Arrival priority and unfinished counter work belong only to the old
	# desk. Preserve the clinical ticket and waiting history, never move the
	# old desk's queue place or service progress into another desk.
	current.desk_id = desk_id
	current.phase = "seek"
	current.arrived_seq = -1
	for field: String in ["queue_seq","queue_cell","queue_arrived_tick","queue_desk_id","nurse_id","remaining_ticks","started_tick"]:
		current.erase(field)

func _reset_destination(world: WorldState, visit: Dictionary, current: Dictionary) -> void:
	_cancel_own_move(world,visit.actor_id,current)
	if waiting!=null: waiting._release_seat(world,visit.id)
	_change_desk(world,visit,current,"")
	current.phase = "seek"
	current.guided_target = ""
	current.arrived_seq = -1
	current.erase("queue_seq")
	current.erase("queue_cell")
	current.erase("destination_cell")

func _queue_present(world: WorldState, current: Dictionary) -> bool:
	# The number survives a same-desk interruption, but it blocks others
	# only while its patient is really waiting at this desk's current point.
	# Read live facts here, not a phase another visit must update first.
	if current.get("phase","")!="desk_queue" or not current.has("queue_cell"): return false
	var visit: Dictionary = world.facts.visits.get(str(current.get("visit_id","")),{})
	if visit.is_empty() or world.facts.get("waiting_life",{}).get("needs",{}).has(visit.id): return false
	var actor_id: String = str(visit.actor_id)
	var floor_id: int = int(current.guide_floor)
	return not world.facts.moves.has(actor_id) and space.at(world,actor_id,floor_id,current.queue_cell) and scope.allows(world,actor_id,str(current.desk_id),floor_id,current.queue_cell)

func _approach_desk(world: WorldState, visit: Dictionary, ticket: Dictionary, current: Dictionary) -> bool:
	var floor_id: int = int(current.guide_floor)
	if not _desk_open(world,str(current.desk_id)) or int(world.facts.facilities.get(str(current.desk_id),{}).get("floor_id",0))!=floor_id:
		_change_desk(world,visit,current,"")
		var options: Array = []
		for id: String in world.facility_ids("SE01"):
			if not _desk_open(world,id) or int(world.facts.facilities[id].floor_id)!=floor_id: continue
			var point: Dictionary = scope.point(world,visit.actor_id,id)
			if point.is_empty(): continue
			var count: int = 0
			for row: Dictionary in world.facts.floor_guidance.visits.values():
				if row.get("desk_id","")==id and row.get("phase","") in ["desk_queue","to_counter","working"]: count += 1
			options.append({"id":id,"point":point,"count":count})
		options.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a.count<b.count if a.count!=b.count else a.id<b.id)
		if options.is_empty():
			if _reselect_unreachable_target(world,visit,current): return false
			visit.waiting_reason = "%d层缺少可达导诊台或安全排队位置"%floor_id
			current.reason = visit.waiting_reason
			return false
		_change_desk(world,visit,current,str(options[0].id))
		current.queue_cell = options[0].point.cell
	if current.phase=="to_counter": return _gather_counter(world,visit,current)
	if not current.has("queue_cell") or not scope.allows(world,visit.actor_id,str(current.desk_id),floor_id,current.queue_cell) or not space.public_areas.safe_wait(world,visit.actor_id,floor_id,current.queue_cell):
		var point: Dictionary = scope.point(world,visit.actor_id,str(current.desk_id))
		if point.is_empty():
			if _reselect_unreachable_target(world,visit,current): return false
			visit.waiting_reason = "本层导诊台前暂无安全排队位置"
			return false
		_cancel_own_move(world,visit.actor_id,current)
		current.queue_cell = point.cell
	if not space.at(world,visit.actor_id,floor_id,current.queue_cell) or world.facts.moves.has(visit.actor_id):
		visit.waiting_reason = "正在前往%d层导诊台，尚未入队"%floor_id
		_move(world,visit,current,floor_id,current.queue_cell)
		return false
	if not current.has("queue_seq"):
		world.facts.floor_guidance.next_arrival += 1
		current.queue_seq = world.facts.floor_guidance.next_arrival
		current.queue_desk_id = current.desk_id
		current.queue_arrived_tick = world.sim_tick
	current.phase = "desk_queue"
	current.reason = ""
	for other: Dictionary in world.facts.floor_guidance.visits.values():
		if other.visit_id==visit.id or other.get("desk_id","")!=current.desk_id or world.facts.get("waiting_life",{}).get("needs",{}).has(other.visit_id): continue
		if other.get("phase","") in ["to_counter","working"] or other.has("queue_seq") and int(other.queue_seq)<int(current.queue_seq) and _queue_present(world,other):
			visit.waiting_reason = "本层导诊排队，尚未进入目的地队列"
			return false
	var desk: Dictionary = world.facts.floor_guidance.desks.get(current.desk_id,{})
	var nurse: String = str(desk.get("nurse_id",""))
	if nurse.is_empty() or not _nurse_ready(world,nurse):
		visit.waiting_reason = "本层导诊台缺少当班护士，保留排队顺序"
		return false
	var quote: Dictionary = space.facility_quote(world,str(current.desk_id),visit.actor_id,[nurse])
	if not quote.get("ok",false) or quote.get("unchanged",false):
		visit.waiting_reason = quote.get("reason","导诊台缺少真实双人服务空间")
		return false
	var a: Dictionary = world.facts.actors[visit.actor_id]
	var n: Dictionary = world.facts.actors[nurse]
	if space._actor_rect(a,Vector2(quote.patient_cell[0],quote.patient_cell[1])).intersects(space._actor_rect(n,Vector2(quote.operator_cells[0][0],quote.operator_cells[0][1])),false):
		visit.waiting_reason = "导诊台患者位与护士位身体相交，需要调整布局"
		return false
	var reason: String = space.reserve_facility(world,str(current.desk_id),visit.actor_id,"floor_guide:"+visit.id,[nurse])
	if not reason.is_empty():
		visit.waiting_reason = reason
		return false
	current.nurse_id = nurse
	current.phase = "to_counter"
	return _gather_counter(world,visit,current)

func _gather_counter(world: WorldState, visit: Dictionary, current: Dictionary) -> bool:
	var layout: Dictionary = space.facility_layout(world,str(current.desk_id))
	var nurse: String = str(current.nurse_id)
	if not _nurse_ready(world,nurse) or world.facts.floor_guidance.desks.get(current.desk_id,{}).get("nurse_id","")!=nurse:
		_release_counter(world,visit,current)
		current.phase = "desk_queue"
		return false
	if not space.at(world,visit.actor_id,int(layout.floor_id),layout.patient_cell) or world.facts.moves.has(visit.actor_id):
		_move(world,visit,current,int(layout.floor_id),layout.patient_cell)
		visit.waiting_reason = "正在真实走到导诊台服务位"
		return false
	if not space.at(world,nurse,int(layout.floor_id),layout.operator_cells[0]) or world.facts.moves.has(nurse):
		if not world.facts.moves.has(nurse): space.request_move(world,nurse,int(layout.floor_id),layout.operator_cells[0])
		visit.waiting_reason = "等待导诊护士真实到台"
		return false
	current.phase = "working"
	current.remaining_ticks = maxi(1,ceili(float(content.balance.guidance.nurse_seconds)*10.0/clinic._talent_rate(world,str(current.nurse_id),"guidance",visit)))
	current.started_tick = world.sim_tick
	return false

func _move(world: WorldState, visit: Dictionary, current: Dictionary, floor_id: int, cell: Array) -> void:
	var movement: Dictionary = world.facts.moves.get(visit.actor_id,{})
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
	if reason.is_empty() and world.facts.moves.has(visit.actor_id): world.facts.moves[visit.actor_id].floor_guidance_key = current.request_key
	elif not reason.is_empty():
		if not _reselect_unreachable_target(world,visit,current): visit.waiting_reason = reason

func _reselect_unreachable_target(world: WorldState, visit: Dictionary, current: Dictionary) -> bool:
	var target_id: String = str(current.get("target_id",""))
	if target_id.is_empty() or not world.facts.facilities.has(target_id): return false
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	if actor.location.kind!="floor" or current.get("phase","")=="working": return false
	var layout: Dictionary = space.facility_layout(world,target_id)
	# A temporary crowd or occupied service is not a lost destination. Check
	# actual topology/connector availability only after a failed approach or
	# at the existing behavior scan, never expand every target every tick.
	if space.can_reach(world,visit.actor_id,int(layout.floor_id),layout.patient_cell,[],{},true): return false
	var ticket: Dictionary = world.facts.tickets.get(visit.get("ticket_id",""),{})
	if ticket.is_empty(): return false
	var alternative: String = _choose_target(world,visit,ticket)
	if alternative.is_empty() or alternative==target_id:
		# Keep the original pending journey if there is nowhere else to go.
		# Clearing it would make the department-routing fallback repeatedly
		# perform the same desk service while this lift remains unavailable.
		visit.waiting_reason = "原目的地已不可达，等待可用诊室或通路恢复"
	else:
		_reset_destination(world,visit,current)
		current.target_id = alternative
		current.guide_floor = int(world.facts.facilities[alternative].floor_id)
		visit.waiting_reason = "原目的地已不可达，重新前往本次就医楼层导诊"
	current.reason = visit.waiting_reason
	return true

func _cancel_own_move(world: WorldState, actor_id: String, current: Dictionary) -> void:
	var move: Dictionary = world.facts.moves.get(actor_id,{})
	if move.get("floor_guidance_key","")==current.get("request_key","") and not move.has("detour") and not move.has("convoy"): space.cancel_ground_move(world,actor_id)

func _approach_destination(world: WorldState, visit: Dictionary, ticket: Dictionary, current: Dictionary) -> bool:
	if not _target_valid(world,visit,ticket,str(current.target_id)):
		_reset_destination(world,visit,current)
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
	world.facts.floor_guidance.next_arrival += 1
	current.arrived_seq = world.facts.floor_guidance.next_arrival
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
		var layout: Dictionary = space.facility_layout(world,str(current.desk_id))
		if not space.at(world,visit.actor_id,int(layout.floor_id),layout.patient_cell) or not space.at(world,str(current.nurse_id),int(layout.floor_id),layout.operator_cells[0]) or world.facts.moves.has(visit.actor_id) or world.facts.moves.has(str(current.nurse_id)): continue
		_worked[current.nurse_id] = true
		current.remaining_ticks -= 1
		if int(current.remaining_ticks)>0: continue
		current.receipts.append({"request_key":current.request_key,"floor_id":current.guide_floor,"desk_id":current.desk_id,"nurse_id":current.nurse_id,"started_tick":current.started_tick,"completed_tick":world.sim_tick})
		if clinic.recruitment!=null:
			clinic.recruitment.service_mood(world,str(current.nurse_id),"guidance",visit.id,current.receipts[-1])
		current.initial_done = true
		current.erase("route_at_desk")
		_release_counter(world,visit,current)
		current.phase = "destination"
		current.erase("queue_seq")
		var ticket: Dictionary = world.facts.tickets.get(visit.get("ticket_id",""),{})
		if ticket.get("kind","")=="gp" and clinic.departments!=null:
			if not clinic.departments.route_patient(world,visit.id,true): current.target_id = ""
		if str(current.target_id).is_empty(): current.target_id = _choose_target(world,visit,ticket)
		current.guided_target = current.target_id

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
	var current: Dictionary = state(world,visit_id)
	if current.is_empty(): return
	var visit: Dictionary = world.facts.visits.get(visit_id,{})
	if not visit.is_empty():
		_cancel_own_move(world,visit.actor_id,current)
		_release_counter(world,visit,current)
	world.facts.floor_guidance.visits.erase(visit_id)

func ordered_tickets(world: WorldState) -> Array:
	var ids: Array = world.ids("tickets")
	ids.sort_custom(func(a: String,b: String)->bool:
		var sa: int = int(state(world,world.facts.tickets[a].visit_id).get("arrived_seq",-1))
		var sb: int = int(state(world,world.facts.tickets[b].visit_id).get("arrived_seq",-1))
		if sa<0: sa = 9223372036854775807
		if sb<0: sb = 9223372036854775807
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
	if current.get("phase","")=="to_counter":
		_release_counter(world,visit,current)
		current.phase = "desk_queue"

func _return_scope(world: WorldState, visit: Dictionary) -> String:
	var current: Dictionary = state(world,visit.id)
	if current.is_empty(): return ""
	if current.get("phase","")=="ready":
		var ticket: Dictionary = world.facts.tickets.get(visit.get("ticket_id",""),{})
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
	# With no surviving desk, finish the life return at a real safe local point.
	# This clears no guide requirement and grants no destination queue place.
	return space.public_areas.select(world,visit.actor_id,[],HospitalWaitingLife.WAITING_ROOM_KINDS,"waiting",[],9223372036854775807,{},true)

func return_allows(world: WorldState, visit: Dictionary, floor_id: int, cell: Array) -> bool:
	var id: String = _return_scope(world,visit)
	if not id.is_empty(): return scope.allows(world,visit.actor_id,id,floor_id,cell)
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	return actor.location.kind=="floor" and int(actor.location.floor_id)==floor_id and space.public_areas.safe_wait(world,visit.actor_id,floor_id,cell)

func _ready_target(world: WorldState, visit: Dictionary, ticket: Dictionary, facility_id: String = "") -> String:
	if clinic==null: return ""
	var department: Dictionary = world.facts.get("departments",{}).get("units",{}).get(str(visit.get("department_id","general")),{})
	if not department.get("open",true): return ""
	if not facility_id.is_empty() and not _target_valid(world,visit,ticket,facility_id): return ""
	var selected: String = _ready_candidate(world,visit,ticket,facility_id)
	if not selected.is_empty() and _target_valid(world,visit,ticket,selected): return selected
	if not facility_id.is_empty(): return ""
	# Legacy general-pool quotes can enumerate rooms owned by another unit.
	# Recheck actual department membership without weakening clinical policy.
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
	if not facility_id.is_empty(): selection.facility_id = facility_id
	if ticket.kind=="outpatient":
		var status: Dictionary = {"reason":"","policy_ok":false,"review_quote":{}}
		var plan_id: String = str(visit.plan_decision.get("plan_id",visit.requested_plan_id))
		selection.eligible = clinic._plan_candidate_eligible.bind(world,visit,plan_id,status)
		selection.accept = clinic._accept_outpatient_dispatch.bind(world,visit,status)
	var choices: Array = clinic.service_candidates(world,visit,str(ticket.kind),false,false,selection)
	return "" if choices.is_empty() else str(choices[0].facility_id)

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
		if (not world.facts.facilities.has(str(release.desk_id)) or not space.body_rectangle(actor).intersects(prior,false)) and space.public_areas.safe_wait(world,id,int(actor.location.floor_id),actor.location.cell):
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
		var point: Dictionary = scope.point(world,id,str(release.desk_id),prior)
		if point.is_empty():
			world.facts.staff[id].life_reason = "等待导诊岗位的真实安全离位空间"
			continue
		space.request_floor_move(world,id,int(point.floor_id),point.cell)

static func validate_state(world: WorldState) -> String:
	if not world.facts.has("floor_guidance"): return ""
	var data: Variant = world.facts.floor_guidance
	if not data is Dictionary or not data.get("visits") is Dictionary or not data.get("desks") is Dictionary or not data.get("releases",{}) is Dictionary or not WorldState._natural(data.get("next_arrival",-1)): return "楼层导诊状态结构无效"
	var nurses: Dictionary = {}
	var queues: Dictionary = {}
	var active_desks: Dictionary = {}
	for id: Variant in data.desks:
		var desk: Variant = data.desks[id]
		if not id is String or not desk is Dictionary or desk.get("id")!=id or not desk.get("nurse_id") is String or not desk.get("reason") is String: return "楼层导诊台岗位结构无效"
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
		if not row.get("phase","") in ["seek","desk_queue","to_counter","working","destination","ready"] or not row.get("initial_done") is bool or not WorldState._natural(row.get("guide_floor",-1)) or int(row.guide_floor)<1 or not row.get("arrived_seq") is int or int(row.arrived_seq)<-1 or not row.get("receipts") is Array: return "楼层导诊阶段或到达顺序无效"
		if not WorldState._natural(row.get("next_recheck",-1)) or row.has("route_at_desk") and not row.route_at_desk is bool: return "楼层导诊复查状态无效"
		if int(row.arrived_seq)>int(data.next_arrival): return "楼层导诊目的地顺序超出已发生到达"
		for field: String in ["queue_cell","destination_cell"]:
			if row.has(field) and not BuildGeometry.point(row[field]): return "楼层导诊移动位置无效"
		if row.has("queue_seq"):
			if not WorldState._natural(row.queue_seq) or int(row.queue_seq)>int(data.next_arrival) or queues.has(int(row.queue_seq)): return "楼层导诊排队顺序无效"
			queues[int(row.queue_seq)] = true
			if row.has("queue_desk_id") and row.queue_desk_id!=row.desk_id: return "楼层导诊排队资格不属于当前台"
		if row.phase in ["to_counter","working"] and (not world.facts.staff.has(row.get("nurse_id","")) or not world.facts.facilities.has(row.desk_id) or not world.facts.tickets.has(row.ticket_id)): return "楼层导诊正在服务的参与者缺失"
		if row.phase in ["to_counter","working"]:
			if active_desks.has(row.desk_id): return "同一导诊台不能同时服务两名患者"
			active_desks[row.desk_id] = id
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
		if row.get("phase","") in ["seek","desk_queue","to_counter","working"] and floors.has(int(row.guide_floor)): floors[int(row.guide_floor)].queue += 1
	var ids: Array = floors.keys(); ids.sort()
	var lines: Array[String] = []
	for id: int in ids:
		var count: Dictionary = floors[id]
		lines.append("%d层：导诊台%d · 到岗护士%d · 导诊等待%d%s"%[id,count.desks,count.nurses,count.queue,"；请补设导诊台" if int(count.desks)==0 else "；缺当班护士或通路" if int(count.nurses)<int(count.desks) else ""])
	return "\n".join(lines)
