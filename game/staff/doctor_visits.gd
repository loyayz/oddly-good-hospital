extends RefCounted

var content: HospitalContent
var space: HospitalSpace
var _wellbeing: WeakRef

func _init(database: HospitalContent, geometry: HospitalSpace, owner: RefCounted) -> void:
	content=database
	space=geometry
	_wellbeing=weakref(owner)

# One saved daily decision, with clinical history as the relationship source.
# The social task never acquires a bed, nurse, clinical job or discharge gate.
func consider(world: WorldState, staff_id: String) -> void:
	if not _available(world,staff_id): return
	var staff: Dictionary=world.facts.staff[staff_id]
	var day: int=world.sim_tick/WorldState.TICKS_PER_DAY
	if int(staff.social_visit_day)==day or world.sim_tick%ceili(float(content.balance.doctor_visits.scan_seconds)/WorldState.TICK_SECONDS)!=0: return
	var candidates: Array=[]
	for stay_id: String in world.ids("ward_stays"):
		var stay: Dictionary=world.facts.ward_stays[stay_id]
		if stay.get("phase","")!="recovery": continue
		var visit_id: String=str(world.facts.attempts[stay.attempt_id].visit_id)
		var history: Dictionary=world.facts.get("patient_experience",{}).get("experience",{}).get(visit_id,{}).get("completed_services",{})
		for service: Dictionary in history.values():
			var staff_ids: Array=service.get("staff_ids",[])
			if service.get("kind","") in ["gp","surgery"] and not staff_ids.is_empty() and staff_ids[0]==staff_id:
				candidates.append({"stay_id":stay_id,"visit_id":visit_id})
				break
	if candidates.is_empty(): return
	staff.social_visit_day=day
	if world.draw("communication",10000)>=int(content.balance.doctor_visits.probability_bp): return
	var choice: Dictionary=candidates[world.draw("communication",candidates.size())]
	var point: Dictionary=_point(world,staff_id,world.facts.ward_stays[choice.stay_id])
	if point.is_empty(): return
	var owner: RefCounted=_wellbeing.get_ref()
	owner._begin(world,staff_id,"doctor_visit")
	staff.life_task.merge({"phase":"visit_travel","stay_id":choice.stay_id,"visit_id":choice.visit_id,"floor_id":point.floor_id,"cell":point.cell,"public_purpose":"doctor_visit","remaining_ticks":ceili(float(content.balance.doctor_visits.interaction_seconds)/WorldState.TICK_SECONDS)},true)
	staff.life_reason="空闲时前往探望原患者"
	dispatch(world,staff_id)

# False hands the existing safe return phase back to staff wellbeing.
func dispatch(world: WorldState, staff_id: String) -> bool:
	var staff: Dictionary=world.facts.staff[staff_id]
	var task: Dictionary=staff.life_task
	var stay: Dictionary=world.facts.ward_stays.get(str(task.get("stay_id","")),{})
	if not _available(world,staff_id) or (not task.get("interaction_completed",false) and stay.get("phase","")!="recovery"):
		_stop(world,staff_id)
		return true
	if task.phase in ["returning","release"]: return false
	var actor: Dictionary=world.facts.actors[staff_id]
	if actor.location.kind!="floor": return true
	var owner: RefCounted=_wellbeing.get_ref()
	if task.phase=="visit_travel":
		if world.facts.moves.has(staff_id):
			if not space.movement_failure(world,staff_id).is_empty(): _stop(world,staff_id)
			return true
		if not space.at(world,staff_id,int(task.floor_id),task.cell):
			if not owner._request_public_target(world,staff_id,task,int(task.floor_id),task.cell): _stop(world,staff_id)
			return true
		if not space.public_areas.safe_wait(world,staff_id,int(task.floor_id),task.cell):
			_stop(world,staff_id)
			return true
		task.phase="visiting"
		staff.life_reason="正在探望原患者，不推进护理或治疗"
	elif task.phase=="visiting" and not space.at(world,staff_id,int(task.floor_id),task.cell):
		_stop(world,staff_id)
	return true

func complete(world: WorldState, staff_id: String) -> void:
	var staff: Dictionary=world.facts.staff[staff_id]
	var task: Dictionary=staff.life_task
	task.interaction_completed=true
	staff.last_doctor_visit={"visit_id":task.visit_id,"completed_tick":world.sim_tick}
	_wellbeing.get_ref()._begin_return(world,staff_id)

func _available(world: WorldState, staff_id: String) -> bool:
	var staff: Dictionary=world.facts.staff[staff_id]
	var owner: RefCounted=_wellbeing.get_ref()
	if staff.role!="doctor" or not staff.get("on_shift",false) or staff.get("departed",false) or owner.scheduler==null: return false
	if staff.get("rest_obligation",false) or int(staff.get("rest_debt_ticks",0))>0 or int(staff.awake_ticks)>=ceili(float(content.balance.staff_sleep.awake_limit_seconds)/WorldState.TICK_SECONDS) or float(staff.energy)<=float(content.balance.wellbeing.recreation_max_energy_priority): return false
	var leave: Dictionary=staff.get("leave_plan",{})
	if not leave.is_empty() and world.sim_tick>=int(leave.requested_start_tick): return false
	if owner._busy(world,staff_id) or owner._other_commitment(world,staff_id): return false
	var assignment: Dictionary=owner.scheduler.assignment(world,staff_id,owner.scheduler.shift_index(world))
	return not assignment.kind in ["rest","training"] and assignment.get("pools",[]).is_empty()

func _point(world: WorldState, staff_id: String, stay: Dictionary) -> Dictionary:
	var bed: Dictionary=world.facts.facilities.get(str(stay.get("bed_id","")),{})
	if bed.is_empty(): return {}
	var room_id: String=str(bed.get("room_id",""))
	if not space.room_use.reason(world,room_id).is_empty(): return {}
	var origin:=Vector2(float(bed.patient_cell[0]),float(bed.patient_cell[1]))
	for cell: Array in space.room_use.standing_cells(world,room_id):
		if Vector2(float(cell[0]),float(cell[1])).distance_to(origin)>float(content.balance.doctor_visits.bedside_radius_cells): continue
		if not space.public_areas.safe_wait(world,staff_id,int(bed.floor_id),cell): continue
		if space.travel_quote(world,staff_id,int(bed.floor_id),cell).get("ok",false): return {"floor_id":int(bed.floor_id),"cell":cell.duplicate()}
	return {}

func _stop(world: WorldState, staff_id: String) -> void:
	var staff: Dictionary=world.facts.staff[staff_id]
	if world.facts.actors[staff_id].location.kind!="floor": return
	if not _wellbeing.get_ref()._cancel_life_move(world,staff_id,staff.life_task): return
	staff.life_task={"phase":"idle"}
	staff.block_new_work=bool(staff.rest_obligation) or int(staff.sleep_remaining_ticks)>0
	staff.life_reason="探望结束，继续按当前班表活动"
