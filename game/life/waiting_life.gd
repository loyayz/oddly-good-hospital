class_name HospitalWaitingLife
extends RefCounted

const PUBLIC_SEAT_DEFINITIONS: Array[String] = ["FUR06","FUR09","FUR10","FUR11","FUR12","FUR13","FUR14","FUR15","FUR16","FUR49","FUR50","FUR51","FUR52","AE01"]

var content: HospitalContent
var space: HospitalSpace
var environment: RefCounted
var visitors: HospitalVisitors

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry

func ensure(world: WorldState) -> void:
	if not world.facts.has("waiting_life"):
		world.facts.waiting_life = {"seats":{},"needs":{},"clocks":{}}
	for visit_id: String in world.active_visit_ids():
		var visit: Dictionary = world.facts.visits[visit_id]
		if not world.facts.waiting_life.clocks.has(visit_id):
			world.facts.waiting_life.clocks[visit_id] = {"sequence":0,"next_purpose":"toilet",
				"next_need_tick":int(visit.get("arrival_tick",world.sim_tick))+_ticks(content.balance.amenity_flow.first_need_seconds)}

func dispatch(world: WorldState) -> void:
	ensure(world)
	for visit_id: String in world.active_visit_ids():
		var visit: Dictionary = world.facts.visits[visit_id]
		if world.facts.waiting_life.needs.has(visit_id):
			_dispatch_need(world,visit,world.facts.waiting_life.needs[visit_id])
			continue
		if not _waiting(world,visit):
			_release_seat(world,visit_id)
			continue
		var ticket: Dictionary = world.facts.tickets[visit.ticket_id]
		if ticket.get("service_assigned",false) and int(ticket.get("called_tick",-1))>=0:
			continue
		if world.sim_tick>=int(world.facts.waiting_life.clocks[visit_id].next_need_tick) and not world.facts.moves.has(visit.actor_id):
			_begin_need(world,visit)
			continue
		var seat: Dictionary = world.facts.waiting_life.seats.get(visit_id,{})
		if not seat.is_empty():
			_dispatch_public_seat(world,visit,seat)
			continue
		if world.sim_tick%_ticks(content.balance.patient_behavior.scan_seconds)==0 and not world.facts.moves.has(visit.actor_id):
			var area: Dictionary = space.public_areas.select(world,visit.actor_id,PUBLIC_SEAT_DEFINITIONS,["waiting","waiting_area","public","lobby","garden",""],"seat",[],_ticks(content.balance.seat_choice.automatic_travel_seconds_max))
			if not area.is_empty() and int(area.travel_ticks)<=_ticks(content.balance.seat_choice.automatic_travel_seconds_max):
				var intent: Dictionary = {"id":"seat_"+visit.id,"actor_id":visit.actor_id,"ticket_id":visit.ticket_id,"facility_id":"","public_purpose":"seat","mode":"auto","area":area.area,"phase":"area_travel","continuous_ticks":0,"arrived_tick":-1,"area_travel_ticks":int(area.travel_ticks),"started_tick":world.sim_tick,"floor_id":area.floor_id,"cell":area.cell}
				world.facts.waiting_life.seats[visit.id] = intent
				_dispatch_public_seat(world,visit,intent,area)

func advance(world: WorldState) -> void:
	for visit_id: String in world.facts.get("waiting_life",{}).get("seats",{}).keys():
		var seat: Dictionary = world.facts.waiting_life.seats[visit_id]
		var visit: Dictionary = world.facts.visits[visit_id]
		var actor: Dictionary = world.facts.actors[visit.actor_id]
		if seat.phase!="seated" or not _waiting(world,visit) or actor.get("posture","")!="seated" or actor.get("support_facility_id","")!=seat.facility_id or world.facts.moves.has(actor.id):
			seat.continuous_ticks = 0
			continue
		var variant: Dictionary = _chair(world.facts.facilities[seat.facility_id].definition_id)
		if variant.get("effect","")!="patient_calm_once" or visit.get("chair_calm_claimed",false):
			continue
		seat.continuous_ticks += 1
		if int(seat.continuous_ticks)>=_ticks(variant.parameters.continuous_seated_seconds):
			visit.chair_calm_claimed = true
			visit.anger = maxf(0.0,float(visit.anger)-float(variant.parameters.anger_reduction))
	for visit_id: String in world.facts.get("waiting_life",{}).get("needs",{}).keys():
		var need: Dictionary = world.facts.waiting_life.needs[visit_id]
		if need.phase in ["using","fallback"]:
			need.remaining_ticks -= 1
			if int(need.remaining_ticks)<=0:
				_complete_need(world,world.facts.visits[visit_id],need)

# Clinical dispatch calls this only after its resources become available. A life
# service owns its safe eight-second segment and return path; the original ticket
# remains in place throughout. A chair walk finishes before the service redirects it.
func call_patient(world: WorldState, visit_id: String) -> bool:
	ensure(world)
	if world.facts.waiting_life.needs.has(visit_id):
		return false
	var visit: Dictionary = world.facts.visits[visit_id]
	var ticket: Dictionary = world.facts.tickets.get(visit.get("ticket_id",""),{})
	if not ticket.get("pause_reasons",{}).is_empty(): return false
	if not ticket.is_empty():
		ticket.called_tick = world.sim_tick
	if world.facts.waiting_life.seats.get(visit_id,{}).get("phase","")!="seated": _release_seat(world,visit_id)
	if world.facts.moves.has(visit.actor_id):
		return false
	_release_seat(world,visit_id)
	return true

func execute(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	ensure(world)
	var visit_id: String = str(payload.get("visit_id",""))
	if not world.facts.visits.has(visit_id):
		return _result(world,false,"visit_missing","原就诊不存在")
	var visit: Dictionary = world.facts.visits[visit_id]
	if not _waiting(world,visit) or world.facts.waiting_life.needs.has(visit_id) or world.facts.tickets[visit.ticket_id].get("service_assigned",false) and int(world.facts.tickets[visit.ticket_id].get("called_tick",-1))>=0:
		return _result(world,false,"clinical_priority","当前临床或生活服务须先安全完成")
	if kind=="waiting_select_seat":
		var facility_id: String = str(payload.get("facility_id",""))
		if world.facts.moves.has(visit.actor_id):
			return _result(world,false,"movement_in_progress","先完成当前真实移动")
		var quote: Dictionary = _manual_seat_quote(world,visit,facility_id)
		if not quote.ok:
			return _result(world,false,"seat_unavailable",quote.reason)
		_release_seat(world,visit_id)
		var area: Dictionary = space.public_areas.for_facility(world,facility_id)
		if area.is_empty(): return _result(world,false,"seat_unavailable","指定设施没有合法公共使用区域")
		world.facts.waiting_life.seats[visit_id] = {"id":"seat_"+visit_id,"actor_id":visit.actor_id,"ticket_id":visit.ticket_id,"facility_id":"","manual_facility_id":facility_id,"public_purpose":"seat","mode":"manual","area":area,"phase":"area_travel","continuous_ticks":0,"arrived_tick":-1,"area_travel_ticks":0,"started_tick":world.sim_tick,"floor_id":quote.floor_id,"cell":quote.patient_cell}
		_dispatch_public_seat(world,visit,world.facts.waiting_life.seats[visit_id])
		return _result(world,true,"applied","",[visit_id,facility_id])
	if kind=="waiting_release_seat":
		_release_seat(world,visit_id)
		return _result(world,true,"applied","",[visit_id])
	return _result(world,false,"unknown_command","未知候诊生活操作")

func seat_candidates(world: WorldState, visit_id: String) -> Array:
	var visit: Dictionary = world.facts.visits.get(visit_id,{})
	if visit.is_empty() or not _waiting(world,visit):
		return []
	var candidates: Array = []
	var facility_ids: Array = []
	var intent: Dictionary = world.facts.get("waiting_life",{}).get("seats",{}).get(visit_id,{})
	if intent.has("public_purpose"):
		facility_ids = space.public_areas.facilities(world,intent.get("area",{}),PUBLIC_SEAT_DEFINITIONS)
	else:
		for definition_id: String in PUBLIC_SEAT_DEFINITIONS:
			facility_ids.append_array(world.facility_ids(definition_id))
	facility_ids.sort()
	var maximum_travel_ticks: int = _ticks(content.balance.seat_choice.automatic_travel_seconds_max)
	var remaining_travel_ticks: int = maximum_travel_ticks-int(intent.get("area_travel_ticks",0))
	var actor_index: Dictionary = {}
	space.begin_route_query(world,{},space.nominal_query(world))
	if environment!=null: environment.begin_query(world)
	for facility_id: String in facility_ids:
		if space.facility_travel_lower_bound_ticks(world,facility_id,visit.actor_id)>remaining_travel_ticks: continue
		var quote: Dictionary = _seat_quote(world,visit,facility_id,actor_index)
		if quote.ok and int(quote.travel_ticks)+int(intent.get("area_travel_ticks",0))<=maximum_travel_ticks:
			candidates.append(quote)
	if environment!=null: environment.end_query()
	space.end_route_query()
	if candidates.is_empty():
		return []
	var closest: int = 2147483647
	for candidate: Dictionary in candidates:
		closest = mini(closest,int(candidate.travel_ticks))
	candidates = candidates.filter(func(item: Dictionary) -> bool: return int(item.travel_ticks)<=closest+_ticks(content.balance.seat_choice.nearby_detour_seconds))
	var preferred: Array = candidates.filter(func(item: Dictionary) -> bool: return item.preferred)
	if not preferred.is_empty():
		candidates = preferred
	var highest: float = 0.0
	for candidate: Dictionary in candidates:
		highest = maxf(highest,float(candidate.environment))
	candidates = candidates.filter(func(item: Dictionary) -> bool: return float(item.environment)>=highest-float(content.balance.seat_choice.environment_tolerance))
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if a.score!=b.score: return a.score>b.score
		if a.environment!=b.environment: return a.environment>b.environment
		if a.travel_ticks!=b.travel_ticks: return a.travel_ticks<b.travel_ticks
		return a.facility_id<b.facility_id)
	return candidates

func _manual_seat_quote(world: WorldState, visit: Dictionary, facility_id: String) -> Dictionary:
	if not world.facts.facilities.has(facility_id) or not _public_seat(world,world.facts.facilities[facility_id]): return {"ok":false,"reason":"目标不是实际公共候诊座位"}
	if not _occupied(world,facility_id,visit.actor_id): return _seat_quote(world,visit,facility_id)
	# A manual target may be busy. Only its eventual former public user is
	# projected away to validate body fit; this grants no live use or reservation.
	var candidate: WorldState = WorldState.new(world.freeze())
	for actor: Dictionary in candidate.facts.actors.values():
		if actor.get("support_facility_id","")==facility_id:
			actor.location = {"kind":"outside"}
			actor.erase("support_facility_id")
	for seat: Dictionary in candidate.facts.waiting_life.seats.values():
		if seat.get("facility_id","")==facility_id:
			candidate.facts.actors[seat.actor_id].location = {"kind":"outside"}
			seat.facility_id = ""
	candidate.facts.staff_life.reservations.erase(facility_id)
	candidate.facts.adaptations.erase(facility_id)
	return _seat_quote(candidate,visit,facility_id)

func _dispatch_public_seat(world: WorldState, visit: Dictionary, intent: Dictionary, selected_entry: Dictionary = {}) -> void:
	if intent.phase=="seated":
		if not world.facts.facilities.has(intent.facility_id) or not _public_seat(world,world.facts.facilities[intent.facility_id]) or world.facts.facilities[intent.facility_id].get("failed",false) or HospitalRemodel.blocked(world,intent.facility_id): _release_seat(world,visit.id)
		return
	var actor_id: String = str(visit.actor_id)
	if world.facts.moves.has(actor_id) or world.facts.actors[actor_id].location.kind!="floor": return
	var area: Dictionary = space.public_areas.region(world,intent.area)
	if intent.mode=="manual" and (not world.facts.facilities.has(intent.manual_facility_id) or not _public_seat(world,world.facts.facilities[intent.manual_facility_id]) or world.facts.facilities[intent.manual_facility_id].get("failed",false) or HospitalRemodel.blocked(world,intent.manual_facility_id)):
		visit.waiting_reason = "指定设施已不可用"
		_release_seat(world,visit.id)
		return
	if area.is_empty() or space.public_areas.facilities(world,intent.area,PUBLIC_SEAT_DEFINITIONS).is_empty() or (space.public_areas.contains(world,intent.area,actor_id) and not space.public_areas.compatible_geometry(world,intent.area,PUBLIC_SEAT_DEFINITIONS,[actor_id])):
		if intent.mode=="manual":
			_release_seat(world,visit.id)
			return
		var selected: Dictionary = space.public_areas.select(world,actor_id,PUBLIC_SEAT_DEFINITIONS,["waiting","waiting_area","public","lobby","garden",""],"seat",[],maxi(0,_ticks(content.balance.seat_choice.automatic_travel_seconds_max)-int(intent.area_travel_ticks)))
		if selected.is_empty(): return
		intent.area = selected.area
		selected_entry = selected
		intent.arrived_tick = -1
		intent.area_travel_ticks += int(selected.travel_ticks)
		intent.facility_id = ""
	if not space.public_areas.contains(world,intent.area,actor_id):
		if intent.mode=="manual":
			var exact: Dictionary = _seat_quote(world,visit,intent.manual_facility_id)
			if exact.ok:
				space.request_move(world,actor_id,int(exact.floor_id),exact.patient_cell)
				return
		var point: Dictionary = selected_entry if not selected_entry.is_empty() else space.public_areas.waiting_point(world,actor_id,intent.area)
		if not point.is_empty(): space.request_move(world,actor_id,int(point.floor_id),point.cell)
		return
	if int(intent.arrived_tick)<0: intent.arrived_tick = world.sim_tick
	intent.phase = "manual_wait" if intent.mode=="manual" else "local_wait"
	var choices: Array = []
	if intent.mode=="manual":
		var quote: Dictionary = _seat_quote(world,visit,intent.manual_facility_id)
		if quote.ok:
			quote.facility_id = intent.manual_facility_id
			choices.append(quote)
	else: choices = seat_candidates(world,visit.id)
	for choice: Dictionary in choices:
		if not space.public_areas.turn(world,intent,choice.facility_id): continue
		intent.facility_id = choice.facility_id
		if not space.at(world,actor_id,int(choice.floor_id),choice.patient_cell):
			intent.phase = "local_travel"
			space.request_move(world,actor_id,int(choice.floor_id),choice.patient_cell)
			return
		if not space._dynamic_clear(world,actor_id,int(choice.floor_id),space.body_rectangle(world.facts.actors[actor_id])): continue
		var reason: String = space.reserve_facility(world,choice.facility_id,actor_id,actor_id)
		if not reason.is_empty(): continue
		intent.phase = "seated"
		var actor: Dictionary = world.facts.actors[actor_id]
		actor.posture = "seated"
		actor.support_facility_id = choice.facility_id
		space.sync_actor(world,actor_id)
		return
	intent.facility_id = ""
	visit.waiting_reason = "等待指定设施" if intent.mode=="manual" else "本区等待候诊位"
	if visitors!=null:
		var targets: Array = [intent.manual_facility_id] if intent.mode=="manual" else space.public_areas.facilities(world,intent.area,PUBLIC_SEAT_DEFINITIONS)
		for id: String in visitors.seated_facilities(world):
			if not id in targets: continue
			if not _manual_seat_quote(world,visit,id).get("ok",false): continue
			if visitors.yield_seat(world,id): break
	if not space.public_areas.safe_wait(world,actor_id,int(world.facts.actors[actor_id].location.floor_id),world.facts.actors[actor_id].location.cell):
		var point: Dictionary = space.public_areas.waiting_point(world,actor_id,intent.area)
		if not point.is_empty(): space.request_move(world,actor_id,int(point.floor_id),point.cell)

func patient_summary(world: WorldState, visit_id: String, low_motion: bool = false) -> Dictionary:
	var state: Dictionary = world.facts.get("waiting_life",{})
	var visit: Dictionary = world.facts.visits.get(visit_id,{})
	if visit.is_empty(): return {}
	var seat: Dictionary = state.get("seats",{}).get(visit_id,{})
	var need: Dictionary = state.get("needs",{}).get(visit_id,{})
	var summary: Dictionary = {"ticket_id":visit.get("ticket_id",""),"seat":seat.duplicate(true),"need":need.duplicate(true),"reasons":[]}
	if not need.is_empty():
		summary.reason = "正沿原路线返回候诊" if need.phase=="returning" else "正在生活服务，保留原票号" if need.phase in ["using","fallback"] else "本区等待生活设施" if int(need.get("arrived_tick",-1))>=0 else "前往生活区"
		var service: Dictionary = _amenity(need.purpose)
		if need.phase=="fallback":
			summary.scene = service.get("fallback_low_motion_scene" if low_motion else "fallback_scene","")
		else:
			var scene: Dictionary = content.definition("amenity_scenes",need.get("scene_id",""))
			summary.scene = scene.get("low_motion_scene" if low_motion else "scene","")
	elif not seat.is_empty() and seat.get("phase","")!="seated" and seat.has("public_purpose"):
		summary.reason = ("等待指定设施" if int(seat.arrived_tick)>=0 else "前往指定设施") if seat.mode=="manual" else ("本区等待候诊位" if int(seat.arrived_tick)>=0 else "前往候诊区")
	elif not seat.is_empty() and world.facts.facilities.has(seat.facility_id):
		var quote: Dictionary = _seat_quote(world,visit,seat.facility_id)
		summary.reasons = quote.get("reasons",[]).slice(0,2)
		var variant: Dictionary = _chair(world.facts.facilities[seat.facility_id].definition_id)
		var effect: bool = seat.phase=="seated" and (variant.get("effect","")=="patient_calm_once" and not visit.get("chair_calm_claimed",false) or variant.get("effect","")=="patient_noise_anger_multiplier" and _environment(world,visit.actor_id,int(world.facts.facilities[seat.facility_id].floor_id),world.facts.facilities[seat.facility_id].patient_cell).noise>0)
		summary.scene = variant.get("low_motion_scene" if low_motion else "effect_scene" if effect else "ordinary_scene","")
	else:
		summary.reason = "附近没有可用候诊位" if _waiting(world,visit) else ""
	return summary

func noise_multiplier(world: WorldState, visit_id: String) -> float:
	var seat: Dictionary = world.facts.get("waiting_life",{}).get("seats",{}).get(visit_id,{})
	if seat.is_empty() or seat.phase!="seated": return 1.0
	var actor: Dictionary = world.facts.actors[world.facts.visits[visit_id].actor_id]
	if actor.get("posture","")!="seated" or actor.get("support_facility_id","")!=seat.facility_id or world.facts.moves.has(actor.id): return 1.0
	var variant: Dictionary = _chair(world.facts.facilities[seat.facility_id].definition_id)
	return float(variant.parameters.multiplier) if variant.get("effect","")=="patient_noise_anger_multiplier" else 1.0

# Environmental water coverage permits an ordinary short service to finish first.
# Its prospective fit releases only that user's eventual occupancy; all unrelated
# bodies, reservations, walls and the requesting body's return route stay intact.
func facility_availability(world: WorldState, actor_id: String, facility_id: String) -> Dictionary:
	if not world.facts.actors.has(actor_id) or not world.facts.facilities.has(facility_id): return {"ok":false,"reason":"人物或实际设施不存在"}
	# Seat scores ask about the same water source from the same real body.
	# This view ends before movement/reservation and never crosses worlds.
	return space.read_view(world,"waiting_availability:"+JSON.stringify([actor_id,facility_id]),_facility_availability.bind(world,actor_id,facility_id)).duplicate(true)

func _facility_availability(world: WorldState, actor_id: String, facility_id: String) -> Dictionary:
	var candidate: WorldState = world
	var using: Dictionary = space.read_view(world,"waiting_using_facilities",_using_facilities.bind(world))
	for need: Dictionary in using.get(facility_id,[]):
		if need.get("facility_id","")!=facility_id or need.phase!="using" or world.facts.visits[need.visit_id].actor_id==actor_id: continue
		var facts: Dictionary = world.facts.duplicate()
		var user_id: String = str(world.facts.visits[need.visit_id].actor_id)
		facts.actors = world.facts.actors.duplicate()
		facts.actors[user_id] = world.facts.actors[user_id].duplicate()
		facts.waiting_life = world.facts.waiting_life.duplicate()
		facts.waiting_life.needs = world.facts.waiting_life.needs.duplicate()
		facts.waiting_life.needs[need.visit_id] = need.duplicate()
		facts.adaptations = world.facts.adaptations.duplicate()
		candidate = WorldState.new(facts)
		candidate.facts.actors[user_id].location = {"kind":"outside"}
		candidate.facts.waiting_life.needs[need.visit_id].facility_id = ""
		candidate.facts.adaptations.erase(facility_id)
		break
	var quote: Dictionary = _facility_quote(candidate,{"actor_id":actor_id},facility_id)
	if quote.ok: quote.cell = quote.patient_cell.duplicate()
	return quote

func validate(world: WorldState) -> String:
	var state: Variant = world.facts.get("waiting_life")
	if not state is Dictionary or not world.facts.get("visits") is Dictionary or not world.facts.get("facilities") is Dictionary or not world.facts.get("tickets") is Dictionary: return "缺少候诊生活事实"
	for collection: String in ["seats","needs","clocks"]:
		if not state.get(collection) is Dictionary: return "候诊生活集合无效："+collection
	var occupied: Dictionary = {}
	for visit_id: Variant in state.seats:
		var seat: Variant = state.seats[visit_id]
		if not visit_id is String or not world.facts.visits.has(visit_id) or not world.facts.visits[visit_id] is Dictionary or not seat is Dictionary: return "候诊座位就诊引用无效"
		if seat.has("public_purpose"):
			if not seat.get("phase","") in ["area_travel","local_wait","local_travel","manual_wait","seated"] or not seat.get("area") is Dictionary or seat.actor_id!=world.facts.visits[visit_id].actor_id or seat.ticket_id!=world.facts.visits[visit_id].ticket_id or not seat.get("mode","") in ["auto","manual"] or not _natural(seat.get("continuous_ticks")): return "公共候诊意图无效"
			if seat.mode=="manual" and not seat.get("manual_facility_id") is String: return "指定候诊设施引用无效"
			if seat.phase!="seated": continue
		if not seat.get("facility_id") is String or not seat.get("actor_id") is String or not seat.get("ticket_id") is String or not seat.get("phase") is String or not world.facts.facilities.has(seat.get("facility_id","")) or not world.facts.facilities[seat.facility_id] is Dictionary or seat.actor_id!=world.facts.visits[visit_id].get("actor_id","") or seat.get("phase")!="seated" or not _natural(seat.get("continuous_ticks")): return "候诊座位占用无效"
		if not world.facts.tickets.has(seat.get("ticket_id","")) or not world.facts.tickets[seat.ticket_id] is Dictionary or occupied.has(seat.facility_id): return "候诊座位票号或互斥无效"
		occupied[seat.facility_id] = true
	for visit_id: Variant in state.needs:
		var need: Variant = state.needs[visit_id]
		if not visit_id is String or not world.facts.visits.has(visit_id) or not world.facts.visits[visit_id] is Dictionary or not need is Dictionary or state.seats.has(visit_id): return "生活需求就诊或座位互斥无效"
		if not need.get("id") is String or not need.get("phase") is String or not need.get("phase") in ["seek","walking","using","fallback","returning","area_travel","local_wait","local_travel"] or not need.get("purpose") is String or not need.get("purpose") in ["water","toilet"] or not need.get("ticket_id") is String or not need.get("facility_id","") is String or not _natural(need.get("started_tick")) or not _natural(need.get("remaining_ticks")) or not _natural(need.get("queued_ticks")): return "生活需求进度无效"
		if not need.get("return_to") is Dictionary or not need.return_to.get("cell") is Array or need.return_to.cell.size()!=2 or not need.return_to.get("floor_id") is int: return "生活需求返回位置无效"
		if not world.facts.tickets.has(need.get("ticket_id","")) or world.facts.visits[visit_id].get("ticket_id","")!=need.ticket_id: return "生活需求原票号无效"
		if not world.facts.tickets[need.ticket_id] is Dictionary or not world.facts.tickets[need.ticket_id].get("pause_reasons") is Dictionary or world.facts.tickets[need.ticket_id].pause_reasons.get("need_service","")!=need.id: return "生活需求暂离来源无效"
		if not str(need.get("facility_id","")).is_empty() and (need.phase in ["using","returning"]):
			if not world.facts.facilities.has(need.facility_id) or not world.facts.facilities[need.facility_id] is Dictionary or occupied.has(need.facility_id): return "生活设施引用或互斥无效"
			occupied[need.facility_id] = true
	for visit_id: Variant in state.clocks:
		var clock: Variant = state.clocks[visit_id]
		if not visit_id is String or not world.facts.visits.has(visit_id) or not clock is Dictionary or not _natural(clock.get("sequence")) or not _natural(clock.get("next_need_tick")) or not clock.get("next_purpose") is String or not clock.get("next_purpose") in ["toilet","water"]: return "生活需求时钟无效"
	return ""

func _waiting(world: WorldState, visit: Dictionary) -> bool:
	return str(visit.get("phase","")).begins_with("wait_") and world.facts.tickets.has(visit.get("ticket_id","")) and world.facts.tickets[visit.ticket_id].get("pause_reasons",{}).is_empty() and world.facts.actors[visit.actor_id].location.kind=="floor"

func _seat_quote(world: WorldState, visit: Dictionary, facility_id: String, actor_index: Variant = null) -> Dictionary:
	space.begin_route_query(world,{},space.nominal_query(world))
	var result: Dictionary = _seat_quote_in_query(world,visit,facility_id,actor_index)
	space.end_route_query()
	return result

func _seat_quote_in_query(world: WorldState, visit: Dictionary, facility_id: String, actor_index: Variant = null) -> Dictionary:
	if not world.facts.facilities.has(facility_id) or not _public_seat(world,world.facts.facilities[facility_id]): return {"ok":false,"reason":"目标不是实际公共候诊座位"}
	var quote: Dictionary = _facility_quote(world,visit,facility_id)
	if not quote.ok: return quote
	var facility: Dictionary = world.facts.facilities[facility_id]
	var observation: Dictionary = _environment(world,visit.actor_id,int(facility.floor_id),quote.patient_cell)
	var conditions: Dictionary = _conditions(world,visit,facility,quote.patient_cell,observation,actor_index)
	var personality: Dictionary = content.definition("patient_personalities",visit.personality_id)
	var score: int = 0
	var reasons: Array = []
	var labels: Dictionary = {"quiet":"这里比较安静","less_crowded":"这里不拥挤","friendly_neighbor":"朋友正在旁边等候","calm_available":"安抚椅可让心情平静","noise_reduction":"椅罩减轻当前噪声","clean_ground":"脚下干净","decor_nearby":"附近有可看的装饰","casual_scene_nearby":"附近有人平静闲聊"}
	for criterion: String in personality.seating.weights:
		if conditions.get(criterion,false):
			score += int(personality.seating.weights[criterion])*int(content.balance.seat_choice.score_scale)
			if int(personality.seating.weights[criterion])>0: reasons.append(labels[criterion])
	score -= int(quote.travel_ticks)*int(personality.seating.travel_penalty_per_10_seconds)
	quote.merge({"facility_id":facility_id,"environment":float(observation.value),"score":score,"conditions":conditions,"reasons":reasons,"preferred":_preferred(world,visit,facility,observation)},true)
	return quote

func _facility_quote(world: WorldState, visit: Dictionary, facility_id: String) -> Dictionary:
	space.begin_route_query(world,{},space.nominal_query(world))
	var result: Dictionary = _facility_quote_in_query(world,visit,facility_id)
	space.end_route_query()
	return result

func _facility_quote_in_query(world: WorldState, visit: Dictionary, facility_id: String) -> Dictionary:
	if HospitalRemodel.blocked(world,facility_id): return {"ok":false,"reason":"设施正在准备安全改建"}
	if _occupied(world,facility_id,visit.actor_id): return {"ok":false,"reason":"已有实际使用者或预约"}
	var quote: Dictionary = space.facility_quote(world,facility_id,visit.actor_id)
	if not quote.ok: return quote
	var layout: Dictionary = space.facility_layout(world,facility_id)
	var candidate: WorldState = world
	if not quote.get("unchanged",false):
		candidate = _route_candidate(world,visit.actor_id)
		candidate.facts.adaptations[facility_id] = quote
		layout = space.facility_layout(candidate,facility_id)
		space.prepare_projection(world,candidate,[facility_id])
	# A changed fit and the reverse location are distinct actual worlds. They
	# must not inherit a parent's nominal routes or another world's views.
	if candidate!=world: space.begin_route_query(candidate,{},false)
	var route: Dictionary = space.route(candidate,visit.actor_id,int(layout.floor_id),layout.patient_cell)
	if candidate!=world: space.end_route_query()
	if not route.ok or not route.has("arrival_ticks"): return {"ok":false,"reason":route.get("reason","无法估计实际设施路程")}
	var reverse: WorldState = _route_candidate(candidate,visit.actor_id)
	var origin: Dictionary = world.facts.actors[visit.actor_id].location
	reverse.facts.actors[visit.actor_id].location = {"kind":"floor","floor_id":layout.floor_id,"cell":layout.patient_cell.duplicate(),"height_m":0.0}
	space.prepare_projection(candidate,reverse)
	space.begin_route_query(reverse,{},false)
	var back: Dictionary = space.route(reverse,visit.actor_id,int(origin.floor_id),origin.cell)
	space.end_route_query()
	if not back.ok: return {"ok":false,"reason":"设施没有合法返回路线："+str(back.get("reason",""))}
	return {"ok":true,"travel_ticks":int(route.arrival_ticks),"patient_cell":layout.patient_cell.duplicate(),"floor_id":int(layout.floor_id)}

func _route_candidate(world: WorldState, actor_id: String) -> WorldState:
	# Only prospective adaptation and the returning actor may be written.
	# Every other fact is read synchronously through the original owners.
	var facts: Dictionary = world.facts.duplicate()
	facts.adaptations = world.facts.adaptations.duplicate()
	facts.actors = world.facts.actors.duplicate()
	facts.actors[actor_id] = world.facts.actors[actor_id].duplicate(true)
	return WorldState.new(facts)

func _using_facilities(world: WorldState) -> Dictionary:
	var result: Dictionary = {}
	for need: Dictionary in world.facts.get("waiting_life",{}).get("needs",{}).values():
		var id: String = str(need.get("facility_id",""))
		if id.is_empty() or need.phase!="using": continue
		if not result.has(id): result[id] = []
		result[id].append(need)
	return result

func _occupancy_view(world: WorldState) -> Dictionary:
	var result: Dictionary = {"owners":{},"blocked":{}}
	for actor: Dictionary in world.facts.actors.values():
		_occupancy_owner(result,str(actor.get("support_facility_id","")),str(actor.id))
	for seat: Dictionary in world.facts.get("waiting_life",{}).get("seats",{}).values():
		if seat.phase=="seated": _occupancy_owner(result,str(seat.facility_id),str(seat.actor_id))
	for need: Dictionary in world.facts.get("waiting_life",{}).get("needs",{}).values():
		if need.phase in ["using","returning"]: _occupancy_owner(result,str(need.get("facility_id","")),str(world.facts.visits[need.visit_id].actor_id))
	for session: Dictionary in world.facts.sessions.values():
		result.blocked[session.facility_id] = true
	for id: String in world.facts.get("staff_life",{}).get("reservations",{}): result.blocked[id] = true
	return result

func _occupancy_owner(view: Dictionary, facility_id: String, actor_id: String) -> void:
	if facility_id.is_empty(): return
	if not view.owners.has(facility_id): view.owners[facility_id] = {}
	view.owners[facility_id][actor_id] = true

func _occupied(world: WorldState, facility_id: String, actor_id: String) -> bool:
	var view: Dictionary = space.read_view(world,"waiting_occupancy",_occupancy_view.bind(world))
	var owners: Dictionary = view.owners.get(facility_id,{})
	return view.blocked.has(facility_id) or not owners.is_empty() and (owners.size()>1 or not owners.has(actor_id))

func _public_rooms(world: WorldState) -> Dictionary:
	var result: Dictionary = {"rooms":{},"seats":{}}
	for room: Dictionary in world.facts.rooms.values():
		var floor_id: int = int(room.floor_id)
		if not result.rooms.has(floor_id): result.rooms[floor_id] = []
		result.rooms[floor_id].append({"rect":Rect2(float(room.origin[0]),float(room.origin[1]),float(room.size[0]),float(room.size[1])),"public":str(room.get("kind",room.get("definition_id",""))) in ["waiting","waiting_area","public","lobby","garden"]})
	return result

func _public_seat(world: WorldState, facility: Dictionary) -> bool:
	if not facility.definition_id in PUBLIC_SEAT_DEFINITIONS: return false
	var view: Dictionary = space.read_view(world,"waiting_public_rooms",_public_rooms.bind(world))
	if view.seats.has(facility.id): return bool(view.seats[facility.id])
	for room: Dictionary in view.rooms.get(int(facility.floor_id),[]):
		if room.rect.has_point(Vector2(float(facility.cell[0]),float(facility.cell[1]))):
			view.seats[facility.id] = bool(room.public)
			return bool(room.public)
	var available: bool = space.owned(world,int(facility.floor_id),Vector2i(int(facility.cell[0]),int(facility.cell[1])))
	view.seats[facility.id] = available
	return available

func _release_seat(world: WorldState, visit_id: String) -> void:
	var seats: Dictionary = world.facts.get("waiting_life",{}).get("seats",{})
	if not seats.has(visit_id): return
	var actor: Dictionary = world.facts.actors[world.facts.visits[visit_id].actor_id]
	if actor.get("support_facility_id","")==seats[visit_id].facility_id:
		actor.posture = "standing"
		actor.erase("support_facility_id")
		space.sync_actor(world,actor.id)
	seats.erase(visit_id)

func _begin_need(world: WorldState, visit: Dictionary) -> void:
	var clock: Dictionary = world.facts.waiting_life.clocks[visit.id]
	clock.sequence += 1
	_release_seat(world,visit.id)
	var need: Dictionary = {"id":visit.id+":life:"+str(clock.sequence),"visit_id":visit.id,"ticket_id":visit.ticket_id,"purpose":clock.next_purpose,
		"started_tick":world.sim_tick,"queued_ticks":0,"phase":"seek","facility_id":"","remaining_ticks":0,
		"return_to":world.facts.actors[visit.actor_id].location.duplicate(true),"scene_id":"","public_purpose":clock.next_purpose,"actor_id":visit.actor_id,"mode":"auto","area":{},"arrived_tick":-1}
	var ticket: Dictionary = world.facts.tickets[visit.ticket_id]
	if not ticket.has("pause_reasons"): ticket.pause_reasons = {}
	ticket.pause_reasons.need_service = need.id
	world.facts.waiting_life.needs[visit.id] = need
	_dispatch_need(world,visit,need)

func _dispatch_need(world: WorldState, visit: Dictionary, need: Dictionary) -> void:
	if need.phase in ["using","fallback"]: return
	if need.phase!="returning":
		_dispatch_public_need(world,visit,need)
		return
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	if not str(need.facility_id).is_empty() and not space.overlaps_facility(world,actor.id,need.facility_id): need.facility_id = ""
	if actor.location.kind!="floor" or world.facts.moves.has(actor.id): return
	if not space.at(world,actor.id,int(need.return_to.floor_id),need.return_to.cell):
		visit.waiting_reason = space.request_move(world,actor.id,int(need.return_to.floor_id),need.return_to.cell)
		return
	world.facts.tickets[need.ticket_id].pause_reasons.erase("need_service")
	world.facts.waiting_life.needs.erase(visit.id)

func _dispatch_public_need(world: WorldState, visit: Dictionary, need: Dictionary) -> void:
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	if actor.location.kind!="floor" or world.facts.moves.has(actor.id):
		need.queued_ticks = 0
		return
	var deadline: int = int(need.started_tick)+_ticks(content.balance.amenity_flow.seek_seconds)
	if world.sim_tick>deadline:
		_start_fallback(world,visit,need)
		return
	var service: Dictionary = _amenity(need.purpose)
	var definitions: Array = [str(service.ordinary_facility_id),str(service.universal_facility_id)]
	var selected_entry: Dictionary = {}
	if space.public_areas.region(world,need.area).is_empty() or space.public_areas.facilities(world,need.area,definitions).is_empty() or (space.public_areas.contains(world,need.area,actor.id) and not space.public_areas.compatible_geometry(world,need.area,definitions,[actor.id])):
		var room_kinds: Array = [""]
		for room: Dictionary in world.facts.rooms.values():
			var kind: String = str(room.get("kind",room.get("type","")))
			if not kind in room_kinds: room_kinds.append(kind)
		var selected: Dictionary = space.public_areas.select(world,actor.id,definitions,room_kinds,need.purpose)
		if selected.is_empty() or int(selected.start_ticks)>deadline-world.sim_tick:
			_start_fallback(world,visit,need)
			return
		need.area = selected.area
		selected_entry = selected
		need.arrived_tick = -1
		need.phase = "area_travel"
	if not space.public_areas.contains(world,need.area,actor.id):
		need.queued_ticks = 0
		var point: Dictionary = selected_entry if not selected_entry.is_empty() else space.public_areas.waiting_point(world,actor.id,need.area)
		if not point.is_empty(): visit.waiting_reason = space.request_move(world,actor.id,int(point.floor_id),point.cell)
		elif world.sim_tick==deadline: _start_fallback(world,visit,need)
		return
	if int(need.arrived_tick)<0: need.arrived_tick = world.sim_tick
	need.phase = "local_wait"
	var choices: Array = []
	space.begin_dynamic_route_query(world)
	for id: String in space.public_areas.facilities(world,need.area,definitions):
		if not space.public_areas.turn(world,need,id): continue
		var quote: Dictionary = _facility_quote(world,visit,id)
		if quote.ok and world.sim_tick+int(quote.travel_ticks)<=deadline:
			quote.facility_id = id
			choices.append(quote)
	space.end_route_query()
	choices.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a.travel_ticks<b.travel_ticks if a.travel_ticks!=b.travel_ticks else a.facility_id<b.facility_id)
	for choice: Dictionary in choices:
		if not space.public_areas.turn(world,need,choice.facility_id): continue
		need.facility_id = choice.facility_id
		if not space.at(world,actor.id,int(choice.floor_id),choice.patient_cell):
			need.queued_ticks = 0
			need.phase = "local_travel"
			visit.waiting_reason = space.request_move(world,actor.id,int(choice.floor_id),choice.patient_cell)
			return
		if not space._dynamic_clear(world,actor.id,int(choice.floor_id),space.body_rectangle(actor)): continue
		var reason: String = space.reserve_facility(world,choice.facility_id,actor.id,actor.id)
		if not reason.is_empty(): continue
		need.phase = "using"
		need.queued_ticks = 0
		need.remaining_ticks = _ticks(service.ordinary_seconds)
		need.scene_id = _scene(need.purpose,visit.personality_id)
		return
	need.facility_id = ""
	if world.sim_tick==deadline:
		_start_fallback(world,visit,need)
		return
	need.queued_ticks += 1
	visit.waiting_reason = "本区等待生活设施"
	if not space.public_areas.safe_wait(world,actor.id,int(actor.location.floor_id),actor.location.cell):
		var point: Dictionary = space.public_areas.waiting_point(world,actor.id,need.area)
		if not point.is_empty(): space.request_move(world,actor.id,int(point.floor_id),point.cell)
		if world.facts.moves.has(actor.id): need.queued_ticks = 0

func _start_fallback(world: WorldState, visit: Dictionary, need: Dictionary) -> void:
	if world.facts.moves.has(visit.actor_id) or world.facts.actors[visit.actor_id].location.kind!="floor": return
	need.facility_id = ""
	need.phase = "fallback"
	need.queued_ticks = 0
	need.remaining_ticks = _ticks(content.balance.amenity_flow.fallback_seconds)
	visit.waiting_reason = "使用随身生活用品，保留原票号"

func _complete_need(world: WorldState, visit: Dictionary, need: Dictionary) -> void:
	if need.phase=="fallback":
		visit.anger = minf(100.0,float(visit.anger)+float(content.balance.amenity_flow.fallback_anger))
	elif environment!=null:
		environment.record_use(world,str(need.purpose)+"_completed",need.facility_id,need.id)
	var clock: Dictionary = world.facts.waiting_life.clocks[visit.id]
	clock.next_need_tick = world.sim_tick+_ticks(content.balance.amenity_flow.cooldown_seconds)
	clock.next_purpose = "water" if need.purpose=="toilet" else "toilet"
	need.phase = "returning"
	need.remaining_ticks = 0
	visit.waiting_reason = "生活服务结束，沿真实路线返回候诊"
	_dispatch_need(world,visit,need)

# Each automatic selection is read-only until its eventual reservation. Keep this
# index local to that selection, so the next visitor sees current actors and seats.
func _condition_actor_index(world: WorldState) -> Dictionary:
	var size: float = maxf(1.0,float(content.balance.patient_behavior.crowd_radius_cells))
	var floors: Dictionary = {}
	var order: int = 0
	for actor: Dictionary in world.facts.actors.values():
		order += 1
		if world.facts.staff.has(actor.id) or actor.location.kind!="floor": continue
		var floor_id: int = int(actor.location.floor_id)
		if not floors.has(floor_id): floors[floor_id] = {}
		var point: Vector2 = Vector2(float(actor.location.cell[0]),float(actor.location.cell[1]))
		var bucket: Vector2i = Vector2i(floori(point.x/size),floori(point.y/size))
		if not floors[floor_id].has(bucket): floors[floor_id][bucket] = []
		floors[floor_id][bucket].append({"order":order,"actor":actor})
	return {"bucket_size":size,"floors":floors}

func _condition_actors(world: WorldState, floor_id: int, cell: Array, actor_index: Variant) -> Array:
	if actor_index==null: return world.facts.actors.values()
	if actor_index.is_empty(): actor_index.merge(_condition_actor_index(world))
	var buckets: Dictionary = actor_index.floors.get(floor_id,{})
	var radius: float = float(content.balance.patient_behavior.crowd_radius_cells)
	var size: float = float(actor_index.bucket_size)
	var center: Vector2 = Vector2(float(cell[0]),float(cell[1]))
	var rows: Array = []
	# Match the Vector2 precision used by the exact distance check. Raw doubles
	# just below a bucket edge may round onto its three-cell radius boundary.
	for y: int in range(floori((center.y-radius)/size),floori((center.y+radius)/size)+1):
		for x: int in range(floori((center.x-radius)/size),floori((center.x+radius)/size)+1):
			rows.append_array(buckets.get(Vector2i(x,y),[]))
	# Spatial bucket traversal must not change the original fact iteration order.
	rows.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.order)<int(b.order))
	var actors: Array = []
	for row: Dictionary in rows: actors.append(row.actor)
	return actors

func _conditions(world: WorldState, visit: Dictionary, facility: Dictionary, cell: Array, observation: Dictionary, actor_index: Variant = null) -> Dictionary:
	var nearby: int = 0
	var friendly: bool = false
	var radius: float = float(content.balance.patient_behavior.crowd_radius_cells)
	for actor: Dictionary in _condition_actors(world,int(facility.floor_id),cell,actor_index):
		if actor.id==visit.actor_id or world.facts.staff.has(actor.id) or actor.location.kind!="floor" or int(actor.location.floor_id)!=int(facility.floor_id): continue
		if Vector2(float(actor.location.cell[0]),float(actor.location.cell[1])).distance_to(Vector2(float(cell[0]),float(cell[1])))>radius: continue
		var nearby_route: Dictionary = space._floor_route(world,world.facts.actors[visit.actor_id],int(facility.floor_id),Vector2i(int(cell[0]),int(cell[1])),Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1])),[],{},true)
		if not nearby_route.ok or float(nearby_route.walking_distance)>radius: continue
		nearby += 1
		var pair: Array = [visit.actor_id,actor.id]
		pair.sort()
		var relationship: Variant = world.facts.get("relationships",{}).get(":".join(pair),{})
		if relationship is Dictionary and relationship.get("kind","")=="friend" and not world.facts.moves.has(actor.id): friendly = true
	return {"quiet":float(observation.noise)<=0,"less_crowded":nearby<int(content.balance.patient_behavior.crowded_neighbors_min),"friendly_neighbor":friendly,
		"calm_available":facility.definition_id=="FUR49" and float(visit.anger)>=float(content.balance.seat_choice.calm_minimum_anger) and not visit.get("chair_calm_claimed",false),
		"noise_reduction":facility.definition_id=="FUR50" and float(observation.noise)>0,"clean_ground":bool(observation.clean),
		"decor_nearby":observation.get("decor_nearby",false),"casual_scene_nearby":observation.get("casual_scene_nearby",false)}

func _preferred(_world: WorldState, visit: Dictionary, facility: Dictionary, observation: Dictionary) -> bool:
	var preferences: Array = content.definition("species",_world.facts.actors[visit.actor_id].species_id).get("preferences",[])
	if preferences.is_empty(): return true
	for preference: String in preferences:
		if preference in facility.get("preferences",[]) or observation.get(preference,false): return true
	return false

func _environment(world: WorldState, actor_id: String, floor_id: int, cell: Array) -> Dictionary:
	if environment!=null: return environment.environment_at(world,floor_id,cell,actor_id)
	return {"value":float(content.balance.environment.base)+float(content.balance.environment.clean_bonus),"noise":0.0,"dirt":false,"clean":true,"water":false}

func _chair(definition_id: String) -> Dictionary:
	for variant: Dictionary in content.catalog.get("chair_variants",[]):
		if variant.definition_id==definition_id: return variant
	return {}

func _amenity(purpose: String) -> Dictionary:
	for service: Dictionary in content.catalog.amenity_services:
		if service.purpose==purpose: return service
	return {}

func _scene(purpose: String, personality_id: String) -> String:
	var fallback: String = ""
	for scene: Dictionary in content.catalog.amenity_scenes:
		if scene.purpose!=purpose: continue
		if scene.get("personality_id")==personality_id: return scene.id
		if scene.get("personality_id")==null: fallback = scene.id
	return fallback

func _ticks(seconds: Variant) -> int:
	return ceili(float(seconds)/WorldState.TICK_SECONDS)

func _natural(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0 and float(value)<=1000000000000.0 and float(value)==floor(float(value))

func _result(world: WorldState, accepted: bool, code: String, reason: String, changed: Array = []) -> CommandResult:
	return CommandResult.new(accepted,code,reason,changed,world.revision)
