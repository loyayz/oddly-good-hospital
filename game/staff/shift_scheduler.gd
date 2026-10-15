class_name HospitalShiftScheduler
extends RefCounted

const Development = preload("res://game/staff/clinical_development.gd")

var content: HospitalContent
var space: HospitalSpace
var _worked: Dictionary = {}

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry

func ensure(world: WorldState) -> void:
	if not world.facts.has("staff_schedule"):
		world.facts.staff_schedule = {"day":world.sim_tick/WorldState.TICKS_PER_DAY,"handoffs":{},"applications":{}}
	for staff: Dictionary in world.facts.staff.values():
		if not staff.has("schedule"):
			if staff.get("shifts") is Array:
				var migrated: Array = []
				for source_value: Variant in staff.shifts:
					if not source_value is Dictionary:
						migrated.append(source_value)
						continue
					var source: Dictionary = source_value
					var pools: Variant = source.get("pools",source.get("pool",[]))
					if pools is Array:
						pools = pools.duplicate(true)
					migrated.append({"kind":source.get("kind",""),"pools":pools,"locked":false})
				staff.schedule = migrated
			else:
				var duty: String = "outpatient" if staff.role=="doctor" else "work"
				staff.schedule = [{"kind":duty,"pools":[],"locked":false},{"kind":duty,"pools":[],"locked":false},{"kind":"rest","pools":[],"locked":false}]
		var defaults: Dictionary = {"schedule_overrides":{},"schedule_day":world.sim_tick/WorldState.TICKS_PER_DAY,"scheduled_kind":"work","rest_debt_ticks":0,
			"leave_plan":{},"block_new_work":false,"schedule_reason":"","last_schedule_slot":-1,"overtime_ticks":0}
		for key: String in defaults:
			if not staff.has(key):
				staff[key] = defaults[key]

func execute(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	ensure(world)
	if kind=="apply_schedule":
		return _apply(world,payload)
	var staff_id: String = str(payload.get("staff_id",""))
	if not world.facts.staff.has(staff_id):
		return _result(world,false,"staff_missing","员工已不在职")
	var staff: Dictionary = world.facts.staff[staff_id]
	if kind=="set_schedule_lock":
		var slot: int = int(payload.get("shift",-1))
		if slot<0 or slot>=int(content.balance.schedule.shifts_per_day):
			return _result(world,false,"invalid_shift","班次无效")
		staff.schedule[slot].locked = bool(payload.get("locked",true))
		return _result(world,true,"applied","",[staff_id])
	if kind=="plan_leave":
		var days: int = int(payload.get("days",1))
		if not days in content.balance.wellbeing.leave_day_options or not staff.leave_plan.is_empty():
			return _result(world,false,"leave_conflict","假期天数无效或已有休假安排")
		var start: String = str(payload.get("start","now"))
		if not start in content.balance.wellbeing.leave_start_options:
			return _result(world,false,"leave_start","休假开始时间无效")
		var start_tick: int = world.sim_tick if start=="now" else (world.sim_tick/WorldState.TICKS_PER_DAY+1)*WorldState.TICKS_PER_DAY
		staff.leave_plan = {"kind":"voluntary","state":"planned","requested_start_tick":start_tick,"days":days,"actual_start_tick":-1,"end_tick":-1,"recalled":false}
		return _result(world,true,"applied","",[staff_id])
	if kind=="cancel_leave":
		if staff.leave_plan.is_empty():
			return _result(world,false,"leave_missing","当前没有假期")
		if staff.leave_plan.kind=="automatic" or (staff.role=="doctor" and float(staff.fatigue)>=float(content.balance.wellbeing.fatigue_stop_new_work)):
			return _result(world,false,"mandatory_rest","自动长休须恢复到安全终点")
		if staff.leave_plan.state=="planned":
			staff.leave_plan = {}
		else:
			staff.leave_plan.recalled = true
			staff.leave_plan.end_tick = world.sim_tick
		return _result(world,true,"applied","",[staff_id])
	return _result(world,false,"unknown_command","未知排班命令")

func boundaries(world: WorldState) -> void:
	ensure(world)
	_worked.clear()
	var day: int = world.sim_tick/WorldState.TICKS_PER_DAY
	var slot: int = shift_index(world)
	world.facts.staff_schedule.day = day
	for staff_id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[staff_id]
		if staff.get("departed",false):
			staff.on_shift = false
			staff.block_new_work = true
			continue
		if int(staff.schedule_day)!=day:
			staff.schedule_overrides.clear()
			staff.schedule_day = day
		var schedule: Dictionary = assignment(world,staff_id,slot,day)
		staff.scheduled_kind = schedule.kind
		var busy: bool = Development.safe_busy(world,staff_id)
		var life_phase: String = str(staff.get("life_task",{}).get("phase","idle"))
		if staff.role=="doctor" and float(staff.fatigue)>=float(content.balance.wellbeing.fatigue_stop_new_work) and staff.leave_plan.is_empty():
			staff.leave_plan = {"kind":"automatic","state":"planned","requested_start_tick":world.sim_tick,"days":0,"actual_start_tick":-1,"end_tick":-1,"recalled":false}
		var leave_due: bool = not staff.leave_plan.is_empty() and world.sim_tick>=int(staff.leave_plan.requested_start_tick)
		var needs_rest: bool = schedule.kind=="rest" or int(staff.rest_debt_ticks)>0 or leave_due
		if staff.role=="doctor" and float(staff.fatigue)>=float(content.balance.wellbeing.fatigue_stop_new_work):
			needs_rest = true
		if needs_rest and busy:
			staff.block_new_work = true
			staff.schedule_reason = "正在安全交接，完成当前服务后休息"
			if schedule.kind=="rest":
				staff.rest_debt_ticks += 1
				staff.overtime_ticks += 1
			continue
		staff.on_shift = not needs_rest
		staff.block_new_work = needs_rest or life_phase!="idle" or (schedule.kind=="training" and not str(staff.get("training_job_id","")).is_empty()) or not staff.get("base_task",{}).is_empty()
		staff.schedule_reason = "休假等待真实离院" if leave_due else ("补休中" if int(staff.rest_debt_ticks)>0 else ("休息班" if schedule.kind=="rest" else ""))
		if needs_rest and staff.has("base_prepared"):
			staff.base_prepared = false
		staff.last_schedule_slot = day*int(content.balance.schedule.shifts_per_day)+slot

func dispatch(world: WorldState) -> void:
	# Coverage transfers are real bedside work. Missing relief pauses recovery.
	for stay_id: String in world.ids("ward_stays"):
		var stay: Dictionary = world.facts.ward_stays[stay_id]
		if not stay.get("phase","") in ["recovery","round_wait"]:
			continue
		var old_id: String = str(stay.get("nurse_id",""))
		if old_id.is_empty() or not world.facts.staff.has(old_id):
			continue
		var old: Dictionary = world.facts.staff[old_id]
		if old.on_shift and not old.block_new_work:
			continue
		var bed: Dictionary = world.facts.facilities[stay.bed_id]
		var ward_id: String = str(bed.get("room_id",""))
		if world.facts.staff_schedule.handoffs.has(ward_id):
			continue
		for candidate_id: String in world.ids("staff"):
			var candidate: Dictionary = world.facts.staff[candidate_id]
			if candidate_id==old_id or candidate.role!="nurse" or not candidate.on_shift or candidate.block_new_work or Development.safe_busy(world,candidate_id) or int(candidate.abilities.get("care",0))<1:
				continue
			if not str(candidate.get("ward_id","")).is_empty() and candidate.ward_id!=ward_id:
				continue
			var layout: Dictionary = space.facility_layout(world,stay.bed_id)
			var position: Array = _bedside(layout)
			if not space.route(world,candidate_id,int(layout.floor_id),position).ok:
				continue
			var stay_ids: Array = []
			for related_id: String in world.ids("ward_stays"):
				var related: Dictionary = world.facts.ward_stays[related_id]
				if related.nurse_id==old_id and world.facts.facilities[related.bed_id].get("room_id","")==ward_id and stay_ids.size()<int(content.balance.clinical.beds_per_nurse):
					stay_ids.append(related_id)
			world.facts.staff_schedule.handoffs[ward_id] = {"id":"handoff_"+ward_id+"_"+str(world.sim_tick),"old_id":old_id,"new_id":candidate_id,"ward_id":ward_id,
				"stay_ids":stay_ids,"floor_id":layout.floor_id,"cell":position,"remaining_ticks":ceili(float(content.balance.hospital_situations.nursing_handoff_seconds)/WorldState.TICK_SECONDS),"phase":"travel"}
			candidate.block_new_work = true
			break
	for handoff: Dictionary in world.facts.staff_schedule.handoffs.values():
		world.facts.staff[handoff.new_id].block_new_work = true
		if not space.at(world,handoff.new_id,int(handoff.floor_id),handoff.cell):
			handoff.phase = "travel"
			space.request_move(world,handoff.new_id,int(handoff.floor_id),handoff.cell)
		else:
			handoff.phase = "working"

func advance(world: WorldState) -> void:
	for ward_id: String in world.facts.staff_schedule.handoffs.keys():
		var handoff: Dictionary = world.facts.staff_schedule.handoffs[ward_id]
		var nurse: Dictionary = world.facts.staff[handoff.new_id]
		if not nurse.on_shift or nurse.get("life_task",{}).get("phase","idle")!="idle":
			world.facts.staff_schedule.handoffs.erase(ward_id)
			continue
		if handoff.phase!="working":
			continue
		handoff.remaining_ticks = maxi(0,int(handoff.remaining_ticks)-1)
		_worked[handoff.new_id] = true
		if int(handoff.remaining_ticks)>0:
			continue
		for stay_id: String in handoff.stay_ids:
			if world.facts.ward_stays.has(stay_id) and world.facts.ward_stays[stay_id].nurse_id==handoff.old_id:
				world.facts.ward_stays[stay_id].nurse_id = handoff.new_id
		nurse.ward_id = ward_id
		nurse.block_new_work = false
		world.facts.staff_schedule.handoffs.erase(ward_id)

func suggestion(world: WorldState) -> Dictionary:
	var basis: Dictionary = _basis(world)
	var changes: Array = []
	var index: int = 0
	for id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[id]
		if staff.role!="doctor":
			continue
		var proposed: Array = staff.schedule.duplicate(true)
		var rest_slot: int = (index+1)%int(content.balance.schedule.shifts_per_day)
		index += 1
		for slot: int in int(content.balance.schedule.shifts_per_day):
			if not proposed[slot].locked:
				proposed[slot] = {"kind":"rest" if slot==rest_slot else "outpatient","pools":proposed[slot].pools.duplicate(),"locked":false}
		if _template_error(proposed).is_empty() and proposed!=staff.schedule:
			changes.append({"staff_id":id,"schedule":proposed})
	return {"id":str(hash(basis)),"basis":basis,"changes":changes,"coverage":coverage(world,changes)}

func coverage(world: WorldState, changes: Array = []) -> Array:
	var overrides: Dictionary = {}
	for change: Dictionary in changes:
		overrides[change.staff_id] = change.schedule
	var rows: Array = []
	for slot: int in int(content.balance.schedule.shifts_per_day):
		var row: Dictionary = {"shift":slot,"outpatient":0,"surgeon":0,"anesthesia":0,"ward":0,"nurse":0,"training":0,"gaps":[]}
		for id: String in world.ids("staff"):
			var staff: Dictionary = world.facts.staff[id]
			var entry: Dictionary = overrides.get(id,staff.get("schedule",[]))[slot]
			if entry.kind=="rest" or not staff.get("leave_plan",{}).is_empty():
				continue
			if entry.kind=="training":
				row.training += 1
			elif staff.role=="doctor":
				if entry.kind=="outpatient" and int(staff.abilities.get("diagnosis",0))>=1:
					row.outpatient += 1
				if entry.kind=="surgery" and int(staff.abilities.get("surgery",0))>=2 and int(content.definition("doctor_titles",staff.title_id).get("rank",0))>=1:
					row.surgeon += 1
					row.anesthesia += 1
				if entry.kind=="round" and int(staff.abilities.get("diagnosis",0))>=2 and int(staff.abilities.get("treatment",0))>=1:
					row.ward += 1
			elif staff.role=="nurse":
				row.nurse += 1
		if int(row.outpatient)==0:
			row.gaps.append("缺初诊/门诊医生")
		if _has_facility(world,"EQ01") and int(row.surgeon)<2:
			row.gaps.append("手术缺两名互异合资格医生")
		if _has_facility(world,"EQ05") and (int(row.ward)==0 or int(row.nurse)==0):
			row.gaps.append("病房缺护理或查房覆盖")
		var desks: int = 0
		for facility: Dictionary in world.facts.facilities.values():
			if facility.definition_id=="FUR05" and not facility.failed:
				desks += 1
		if int(row.training)>desks:
			row.gaps.append("培训研究桌不足")
		rows.append(row)
	return rows

func assignment(world: WorldState, staff_id: String, slot: int, day: int = -1) -> Dictionary:
	var staff: Dictionary = world.facts.staff[staff_id]
	if day<0:
		day = world.sim_tick/WorldState.TICKS_PER_DAY
	if int(staff.get("schedule_day",-1))==day and staff.get("schedule_overrides",{}).has(str(slot)):
		return staff.schedule_overrides[str(slot)]
	return staff.schedule[slot]

func available_ticks(world: WorldState, staff_id: String, slot: int, day: int = -1) -> int:
	if not world.facts.staff.has(staff_id) or slot<0 or slot>=int(content.balance.schedule.shifts_per_day):
		return 0
	if day<0:
		day = world.sim_tick/WorldState.TICKS_PER_DAY
	var staff: Dictionary = world.facts.staff[staff_id]
	var shift_ticks: int = ceili(float(content.balance.schedule.shift_seconds)/WorldState.TICK_SECONDS)
	var entry: Dictionary = assignment(world,staff_id,slot,day)
	if entry.kind in ["rest","training"]:
		return 0
	var start: int = day*WorldState.TICKS_PER_DAY+slot*shift_ticks
	var finish: int = start+shift_ticks
	var budget: int = finish-maxi(start,world.sim_tick)
	if budget<=0:
		return 0
	var leave: Dictionary = staff.get("leave_plan",{})
	if not leave.is_empty():
		var leave_start: int = int(leave.actual_start_tick) if int(leave.actual_start_tick)>=0 else int(leave.requested_start_tick)
		var leave_end: int = int(leave.end_tick) if int(leave.end_tick)>=0 else leave_start+int(leave.days)*WorldState.TICKS_PER_DAY
		if leave.kind=="automatic":
			leave_end = leave_start+ceili(maxf(0,float(staff.fatigue)-float(content.balance.wellbeing.long_rest_end_fatigue))/float(content.balance.wellbeing.fatigue_leave_per_second)/WorldState.TICK_SECONDS)
		budget -= maxi(0,mini(finish,leave_end)-maxi(maxi(start,world.sim_tick),leave_start))
	if start<=world.sim_tick and world.sim_tick<finish:
		var rest_ticks: int = int(staff.get("rest_debt_ticks",0))
		if staff.get("rest_obligation",false) or float(staff.get("energy",100))<=float(content.balance.wellbeing.recreation_max_energy_priority):
			var rest_rate: float = float(content.balance.wellbeing.energy_tea_per_second)
			var life: Dictionary = staff.get("life_task",{})
			if not str(life.get("facility_id","")).is_empty():
				rest_rate = float(content.balance.wellbeing.energy_rest_per_second)
			rest_ticks = maxi(rest_ticks,ceili(maxf(0,float(content.balance.schedule.compensatory_rest_target_energy)-float(staff.energy))/rest_rate/WorldState.TICK_SECONDS))
		budget -= maxi(rest_ticks,int(staff.get("sleep_remaining_ticks",0)))
		if not staff.get("life_task",{}).is_empty() and staff.life_task.get("kind","")=="recreation":
			budget -= int(staff.life_task.get("remaining_ticks",0))
	return maxi(0,budget)

func window_ticks(world: WorldState, staff_id: String, kind: String, pools: Array = []) -> int:
	var slot: int = shift_index(world)
	var ticks: int = ceili(float(content.balance.schedule.shift_seconds)/WorldState.TICK_SECONDS)
	var current: Dictionary = assignment(world,staff_id,slot)
	if current.kind!=kind or (not pools.is_empty() and current.pools!=pools):
		return 0
	var result: int = ticks-world.sim_tick%ticks
	var following: Dictionary = assignment(world,staff_id,(slot+1)%int(content.balance.schedule.shifts_per_day),world.sim_tick/WorldState.TICKS_PER_DAY+(1 if slot==int(content.balance.schedule.shifts_per_day)-1 else 0))
	if following.kind==kind and following.pools==current.pools:
		result += ticks
	return result

func shift_index(world: WorldState) -> int:
	return (world.sim_tick/ceili(float(content.balance.schedule.shift_seconds)/WorldState.TICK_SECONDS))%int(content.balance.schedule.shifts_per_day)

func worked_staff() -> Dictionary:
	return _worked.duplicate()

func validate(world: WorldState) -> String:
	if not world.facts.get("staff_schedule") is Dictionary or not world.facts.staff_schedule.get("handoffs") is Dictionary or not world.facts.get("staff") is Dictionary or not world.facts.get("ward_stays") is Dictionary:
		return "排班状态缺失"
	for staff_value: Variant in world.facts.staff.values():
		if not staff_value is Dictionary:
			return "员工排班记录无效"
		var staff: Dictionary = staff_value
		var error: String = _template_error(staff.get("schedule",[]))
		if not error.is_empty():
			return error
		if not staff.get("rest_debt_ticks") is int or int(staff.rest_debt_ticks)<0 or not staff.get("schedule_overrides") is Dictionary or not staff.get("leave_plan") is Dictionary:
			return "排班休息债或休假结构无效"
		var leave: Dictionary = staff.leave_plan
		if not leave.is_empty() and (not leave.get("kind","") in ["voluntary","automatic"] or not leave.get("state","") in ["planned","active","returning"] or not leave.get("requested_start_tick") is int or not leave.get("actual_start_tick") is int or not leave.get("end_tick") is int):
			return "休假计划无效"
	for handoff_value: Variant in world.facts.staff_schedule.handoffs.values():
		if not handoff_value is Dictionary:
			return "护理安全交接记录无效"
		var handoff: Dictionary = handoff_value
		if not handoff.get("old_id") is String or not handoff.get("new_id") is String or not handoff.get("stay_ids") is Array or not world.facts.staff.has(handoff.old_id) or not world.facts.staff.has(handoff.new_id) or handoff.old_id==handoff.new_id or not handoff.get("remaining_ticks") is int or int(handoff.remaining_ticks)<0:
			return "护理安全交接人员或余量无效"
		for stay_id: Variant in handoff.get("stay_ids",[]):
			if not stay_id is String or not world.facts.ward_stays.has(stay_id):
				return "护理安全交接床位责任缺失"
	return ""

func _apply(world: WorldState, payload: Dictionary) -> CommandResult:
	var expected: Dictionary = payload.get("basis",{})
	if not expected.is_empty() and expected!=_basis(world):
		return _result(world,false,"material_change","班表、资格或休假依据已经变化")
	var changes: Array = payload.get("changes",[])
	if changes.is_empty():
		return _result(world,true,"unchanged","")
	var seen: Dictionary = {}
	for change: Variant in changes:
		if not change is Dictionary or not world.facts.staff.has(change.get("staff_id","")) or seen.has(change.staff_id):
			return _result(world,false,"invalid_schedule","班表员工无效或重复")
		var staff: Dictionary = world.facts.staff[change.staff_id]
		var error: String = _template_error(change.get("schedule",[]))
		if not error.is_empty():
			return _result(world,false,"invalid_schedule",error)
		for slot: int in int(content.balance.schedule.shifts_per_day):
			if staff.schedule[slot].locked and staff.schedule[slot]!=change.schedule[slot]:
				return _result(world,false,"locked","手动锁定班次须先解锁")
		seen[change.staff_id] = true
	for change: Dictionary in changes:
		world.facts.staff[change.staff_id].schedule = change.schedule.duplicate(true)
	if not str(payload.get("id","")).is_empty():
		world.facts.staff_schedule.applications[str(payload.id)] = world.sim_tick
	return _result(world,true,"applied","",seen.keys())

func _basis(world: WorldState) -> Dictionary:
	var result: Dictionary = {}
	for id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[id]
		result[id] = {"role":staff.role,"schedule":staff.get("schedule",[]).duplicate(true),"abilities":staff.abilities.duplicate(true),"title_id":staff.title_id,"leave_plan":staff.get("leave_plan",{}).duplicate(true)}
	return result

func _template_error(schedule: Variant) -> String:
	var count: int = int(content.balance.schedule.shifts_per_day)
	if not schedule is Array or schedule.size()!=count:
		return "每天需要完整三班模板"
	var rests: int = 0
	for item: Variant in schedule:
		if not item is Dictionary or not item.get("kind","") in ["work","outpatient","surgery","round","training","rest"] or not item.get("pools") is Array or not item.get("locked") is bool:
			return "班次类型、工作池或锁定状态无效"
		if item.pools.size()>count:
			return "门诊每班最多关联三个服务池"
		for pool: Variant in item.pools:
			if not pool is String:
				return "工作池身份无效"
		if item.kind=="rest":
			rests += 1
	if rests<int(content.balance.schedule.minimum_rest_shifts):
		return "每天至少保留一个休息班"
	var consecutive: int = 0
	for slot: int in count*2:
		consecutive = 0 if schedule[slot%count].kind=="rest" else consecutive+1
		if consecutive>int(content.balance.schedule.max_consecutive_work_shifts):
			return "跨日连续工作不能超过两个班次"
	return ""

func _has_facility(world: WorldState, definition_id: String) -> bool:
	for facility: Dictionary in world.facts.facilities.values():
		if facility.definition_id==definition_id and not facility.failed:
			return true
	return false

static func _bedside(layout: Dictionary) -> Array:
	return layout.operator_cells[0] if not layout.get("operator_cells",[]).is_empty() else layout.patient_cell

func _result(world: WorldState, accepted: bool, code: String, reason: String, changed: Array = []) -> CommandResult:
	return CommandResult.new(accepted,code,reason,changed,world.revision)
