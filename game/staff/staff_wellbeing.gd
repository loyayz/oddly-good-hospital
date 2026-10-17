class_name HospitalStaffWellbeing
extends RefCounted

const Development = preload("res://game/staff/clinical_development.gd")

var content: HospitalContent
var space: HospitalSpace

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry

func ensure(world: WorldState) -> void:
	if not world.facts.has("staff_life"):
		world.facts.staff_life = {"reservations":{},"settings":{"maximum_recreation":int(content.balance.wellbeing.default_simultaneous_recreation),"roles":[]},"pressure_receipts":{}}
	for staff: Dictionary in world.facts.staff.values():
		var defaults: Dictionary = {"awake_ticks":0,"sleep_remaining_ticks":0,"life_task":{"phase":"idle"},"last_rest_end_tick":int(staff.get("hired_tick",0)),
			"recreation_day":world.sim_tick/WorldState.TICKS_PER_DAY,"recreation_count":0,"recreation_cooldown_tick":0,"last_recreation_tick":int(staff.get("hired_tick",0)),"life_reason":"",
			"stress_credit":0.0,"dispatch_idle":false,"rest_obligation":false}
		for key: String in defaults:
			if not staff.has(key):
				staff[key] = defaults[key]

func execute(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	ensure(world)
	if kind=="set_staff_recreation":
		var maximum: int = int(payload.get("maximum",content.balance.wellbeing.default_simultaneous_recreation))
		if maximum<0 or not payload.get("roles",[]) is Array:
			return _result(world,false,"invalid_recreation_settings","娱乐人数或岗位权限无效")
		world.facts.staff_life.settings = {"maximum_recreation":maximum,"roles":payload.get("roles",[]).duplicate()}
		return _result(world,true,"applied","")
	if kind=="staff_recreation":
		var ids: Array = payload.get("staff_ids",[str(payload.get("staff_id",""))])
		return _recreation(world,ids,str(payload.get("facility_id","")))
	var staff_id: String = str(payload.get("staff_id",""))
	if not world.facts.staff.has(staff_id):
		return _result(world,false,"staff_missing","员工不存在")
	var staff: Dictionary = world.facts.staff[staff_id]
	if kind=="interrupt_staff_rest":
		if not str(payload.get("reason","")) in ["safety","remodel"]:
			return _result(world,false,"sleep_protected","睡眠只因实际安全离位或改建中断")
		if staff.life_task.phase in ["rest","sleep","recreation","travel","wait_bed"]:
			_interrupt(world,staff_id)
		return _result(world,true,"applied","",[staff_id])
	if kind=="staff_pressure_event":
		var event_id: String = str(payload.get("event_id",""))
		var source: String = str(payload.get("source",""))
		if event_id.is_empty() or not source in ["conflict","frozen","gratitude"]:
			return _result(world,false,"pressure_source","情绪事件需要稳定完成凭据")
		var key: String = staff_id+":"+event_id
		if not world.facts.staff_life.pressure_receipts.has(key):
			var delta: float = float(content.balance.wellbeing.stress_frozen if source=="frozen" else content.balance.wellbeing.stress_conflict)
			if source=="gratitude":
				delta = -float(content.balance.wellbeing.gratitude_stress_relief)
			staff.stress_milli = clampi(int(staff.stress_milli)+roundi(delta*1000),0,100000)
			world.facts.staff_life.pressure_receipts[key] = {"staff_id":staff_id,"event_id":event_id,"source":source,"tick":world.sim_tick}
		return _result(world,true,"applied","",[staff_id])
	return _result(world,false,"unknown_command","未知员工生活命令")

func dispatch(world: WorldState) -> void:
	ensure(world)
	var day: int = world.sim_tick/WorldState.TICKS_PER_DAY
	var ordered: Array = world.ids("staff")
	ordered.sort_custom(func(a: String,b: String) -> bool:
		var first: Dictionary = world.facts.staff[a]
		var second: Dictionary = world.facts.staff[b]
		if int(first.awake_ticks)!=int(second.awake_ticks):
			return int(first.awake_ticks)>int(second.awake_ticks)
		if float(first.energy)!=float(second.energy):
			return float(first.energy)<float(second.energy)
		return a<b)
	for staff_id: String in ordered:
		var staff: Dictionary = world.facts.staff[staff_id]
		if staff.get("departed",false):
			continue
		if int(staff.recreation_day)!=day:
			staff.recreation_day = day
			staff.recreation_count = 0
		var task: Dictionary = staff.life_task
		if task.phase!="idle":
			_dispatch_task(world,staff_id)
			continue
		var leave: Dictionary = staff.get("leave_plan",{})
		if not leave.is_empty() and world.sim_tick>=int(leave.requested_start_tick):
			_begin(world,staff_id,"leave")
			continue
		var mandatory_sleep: bool = int(staff.awake_ticks)>=_ticks(float(content.balance.staff_sleep.awake_limit_seconds)) or int(staff.sleep_remaining_ticks)>0
		if mandatory_sleep:
			_begin(world,staff_id,"sleep")
			continue
		var safe: bool = not Development.safe_busy(world,staff_id) and not _other_commitment(world,staff_id)
		if int(staff.awake_ticks)>=_ticks(float(content.balance.staff_sleep.early_sleep_after_seconds)) and safe and (not staff.get("on_shift",true) or _relief_available(world,staff_id)):
			# Voluntary sleep does not create a bed queue or an offsite fallback.
			var bed: Dictionary = _select_facility(world,staff_id,"sleep")
			if not bed.is_empty():
				_begin(world,staff_id,"sleep",bed)
				continue
		var normal_rest: bool = float(staff.energy)<=float(content.balance.wellbeing.recreation_max_energy_priority) or int(staff.get("rest_debt_ticks",0))>0 or staff.rest_obligation
		var scheduled_rest: bool = not staff.get("on_shift",true) and float(staff.energy)<float(content.balance.schedule.compensatory_rest_target_energy)
		var early_rest: bool = not normal_rest and float(staff.energy)<=float(content.balance.staggered_rest.early_energy_ceiling) and safe and _relief_available(world,staff_id) and not _pool_resting(world,staff_id)
		if normal_rest or scheduled_rest or early_rest:
			_begin(world,staff_id,"rest",{},early_rest)
			continue
	# Recreation uses the original dispatcher's explicit idle result.
	ordered.sort_custom(func(a: String,b: String) -> bool:
		var first: Dictionary = world.facts.staff[a]
		var second: Dictionary = world.facts.staff[b]
		if int(first.stress_milli)!=int(second.stress_milli):
			return int(first.stress_milli)>int(second.stress_milli)
		if int(first.last_recreation_tick)!=int(second.last_recreation_tick):
			return int(first.last_recreation_tick)<int(second.last_recreation_tick)
		return a<b)
	for staff_id: String in ordered:
		if _can_recreate(world,staff_id):
			_recreation(world,[staff_id],"")
	_dispatch_recreation(world)

func boundaries(world: WorldState) -> void:
	ensure(world)
	for staff: Dictionary in world.facts.staff.values():
		if staff.get("departed",false):
			staff.on_shift = false
			staff.block_new_work = true
			continue
		var leave: Dictionary = staff.get("leave_plan",{})
		if int(staff.awake_ticks)>=_ticks(float(content.balance.staff_sleep.awake_limit_seconds)) or int(staff.sleep_remaining_ticks)>0 or float(staff.energy)<=float(content.balance.wellbeing.recreation_max_energy_priority) or staff.rest_obligation or (not leave.is_empty() and world.sim_tick>=int(leave.requested_start_tick)):
			staff.block_new_work = true

func advance(world: WorldState, worked: Dictionary = {}, before_movement: Dictionary = {}) -> void:
	var rates: Dictionary = content.balance.wellbeing
	for staff_id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[staff_id]
		if staff.get("departed",false):
			continue
		var task: Dictionary = staff.life_task
		var phase: String = str(task.phase)
		var actor: Dictionary = world.facts.actors[staff_id]
		var moved: bool = before_movement.has(staff_id) and before_movement[staff_id]!=actor.location
		if phase=="sleep":
			_recover(staff,float(content.balance.staff_sleep.energy_per_second),float(content.balance.staff_sleep.doctor_fatigue_per_second),float(content.balance.staff_sleep.stress_per_second))
			staff.sleep_remaining_ticks = maxi(0,int(staff.sleep_remaining_ticks)-1)
			if int(staff.sleep_remaining_ticks)==0:
				staff.awake_ticks = 0
				_begin_return(world,staff_id)
			continue
		if phase=="offsite":
			var leave: Dictionary = staff.get("leave_plan",{})
			_recover(staff,float(rates.energy_rest_per_second),float(rates.fatigue_leave_per_second),float(rates.stress_leave_per_second))
			task.offsite_ticks += 1
			if int(task.offsite_ticks)>=int(task.get("sleep_credit_ticks",_ticks(float(content.balance.staff_sleep.sleep_seconds)))):
				staff.sleep_remaining_ticks = 0
				staff.awake_ticks = 0
				task.offsite_sleep_satisfied = true
			elif not task.get("offsite_sleep_satisfied",false):
				staff.awake_ticks += 1
			if task.kind=="leave":
				var finished: bool = float(staff.fatigue)<=float(rates.long_rest_end_fatigue) if leave.get("kind","")=="automatic" else world.sim_tick>=int(leave.get("end_tick",world.sim_tick+1))
				if finished and int(staff.sleep_remaining_ticks)==0:
					_return_from_outside(world,staff_id)
			elif int(task.offsite_ticks)>=int(task.required_offsite_ticks) and int(staff.sleep_remaining_ticks)==0 and float(staff.energy)>=float(content.balance.schedule.compensatory_rest_target_energy) and int(staff.get("rest_debt_ticks",0))==0:
				_return_from_outside(world,staff_id)
			staff.rest_debt_ticks = maxi(0,int(staff.get("rest_debt_ticks",0))-1)
			continue
		staff.awake_ticks += 1
		if worked.has(staff_id):
			_integral(staff,-float(rates.energy_work_per_second),float(rates.fatigue_work_per_second) if staff.role=="doctor" else 0.0,float(rates.stress_work_per_second))
			if int(staff.get("overtime_ticks",0))>0 and not staff.get("on_shift",true):
				_integral(staff,0.0,0.0,float(rates.stress_overtime_per_second))
			staff.life_reason = "实际工作消耗"
		elif moved:
			_integral(staff,-float(rates.energy_walk_per_second),0.0,0.0)
			staff.life_reason = "实际移动消耗"
		elif phase=="rest":
			var energy_rate: float = _rest_energy_rate(world,task)
			var stress_rate: float = _rest_stress_rate(world,task)
			_recover(staff,energy_rate,float(rates.fatigue_rest_per_second),stress_rate)
			staff.rest_debt_ticks = maxi(0,int(staff.get("rest_debt_ticks",0))-1)
			staff.life_reason = "员工区清醒休息"
			if float(staff.energy)>=float(content.balance.schedule.compensatory_rest_target_energy) and int(staff.rest_debt_ticks)==0:
				_begin_return(world,staff_id)
		elif phase=="recreation":
			_recover(staff,float(rates.recreation_energy_per_second),float(rates.fatigue_recreation_per_second),float(rates.stress_recreation_per_second))
			staff.life_reason = "真实娱乐减压"
		elif phase=="wait_bed" and _at_target(world,staff_id,task):
			task.waited_ticks += 1
	for reservation: Dictionary in world.facts.staff_life.reservations.values():
		if reservation.kind=="recreation" and reservation.state=="working":
			reservation.remaining_ticks = maxi(0,int(reservation.remaining_ticks)-1)
			if int(reservation.remaining_ticks)==0:
				reservation.state = "releasing"
				for staff_id: String in reservation.staff_ids:
					_begin_return(world,staff_id)

func validate(world: WorldState) -> String:
	if not world.facts.get("staff_life") is Dictionary or not world.facts.staff_life.get("reservations") is Dictionary or not world.facts.staff_life.get("settings") is Dictionary or not world.facts.get("facilities") is Dictionary or not world.facts.get("staff") is Dictionary or not world.facts.get("actors") is Dictionary:
		return "员工生活状态缺失"
	var owners: Dictionary = {}
	for facility_id: Variant in world.facts.staff_life.reservations:
		var reservation: Variant = world.facts.staff_life.reservations[facility_id]
		if not facility_id is String or not reservation is Dictionary or not world.facts.facilities.has(facility_id) or not world.facts.facilities[facility_id] is Dictionary or not reservation.get("staff_ids") is Array or reservation.staff_ids.is_empty() or not reservation.get("kind","") is String or not reservation.get("kind","") in ["rest","sleep","recreation"]:
			return "员工生活预约引用无效"
		for id: Variant in reservation.staff_ids:
			if not id is String or not world.facts.staff.has(id) or not world.facts.staff[id] is Dictionary or owners.has(id) or not world.facts.staff[id].get("life_task") is Dictionary or world.facts.staff[id].life_task.get("facility_id","")!=facility_id:
				return "员工同时占用多个生活位置或预约身份失配"
			owners[id] = facility_id
	for staff_value: Variant in world.facts.staff.values():
		if not staff_value is Dictionary:
			return "员工生活记录无效"
		var staff: Dictionary = staff_value
		if not staff.get("awake_ticks") is int or int(staff.awake_ticks)<0 or not staff.get("sleep_remaining_ticks") is int or int(staff.sleep_remaining_ticks)<0 or int(staff.sleep_remaining_ticks)>_ticks(float(content.balance.staff_sleep.sleep_seconds)):
			return "清醒或睡眠余量无效"
		var task: Variant = staff.get("life_task")
		if not task is Dictionary or not task.get("phase","") is String or not task.get("phase","") in ["idle","wait_safe","travel","rest","sleep","wait_bed","exiting","offsite","returning","recreation","release"]:
			return "员工生活阶段无效"
		if task.phase!="idle" and (not task.get("kind","") is String or not task.get("kind","") in ["rest","sleep","leave","recreation"]):
			return "员工生活原义务缺失"
		if not staff.get("id") is String or not world.facts.actors.has(staff.id) or not world.facts.actors[staff.id] is Dictionary:
			return "员工实际身体引用无效"
		if task.phase=="offsite" and (not world.facts.actors[staff.id].get("location") is Dictionary or world.facts.actors[staff.id].location.get("kind","")!="outside"):
			return "院外休整与实际身体位置不一致"
		if task.phase=="sleep" and (not owners.has(staff.id) or world.facts.actors[staff.id].get("posture","")!="lying"):
			return "实际睡眠缺少专属床位或卧姿"
	return ""

func _begin(world: WorldState, staff_id: String, kind: String, selection: Dictionary = {}, early: bool = false) -> void:
	var staff: Dictionary = world.facts.staff[staff_id]
	var actor: Dictionary = world.facts.actors[staff_id]
	staff.life_task = {"id":"life_"+staff_id+"_"+str(world.sim_tick),"kind":kind,"phase":"wait_safe","facility_id":"","floor_id":0,"cell":[],"early":early,
		"return_location":actor.location.duplicate(true),"selection":selection,"waited_ticks":0,"offsite_ticks":0,"offsite_sleep_satisfied":false,"required_offsite_ticks":0}
	staff.block_new_work = true
	staff.life_reason = "等待当前安全任务结束"
	if kind=="rest":
		staff.rest_obligation = true
	if kind=="sleep" and int(staff.sleep_remaining_ticks)==0:
		staff.sleep_remaining_ticks = _ticks(float(content.balance.staff_sleep.sleep_seconds))
	_dispatch_task(world,staff_id)

func _dispatch_task(world: WorldState, staff_id: String) -> void:
	var staff: Dictionary = world.facts.staff[staff_id]
	var task: Dictionary = staff.life_task
	if task.phase=="wait_safe":
		if Development.safe_busy(world,staff_id) or _other_commitment(world,staff_id) or world.facts.moves.has(staff_id):
			return
		staff.on_shift = false
		staff.base_prepared = false
		if task.kind=="leave":
			_go_outside(world,staff_id)
			return
		var selection: Dictionary = task.selection
		if selection.is_empty():
			selection = _select_facility(world,staff_id,task.kind)
		if not selection.is_empty() and _reserve(world,staff_id,task,selection):
			return
		if task.kind=="sleep":
			var tea: Dictionary = _tea_position(world,staff_id)
			if not tea.is_empty():
				task.phase = "wait_bed"
				task.floor_id = tea.floor_id
				task.cell = tea.cell
				staff.life_reason = "缺兼容床位，正在员工区候床"
				_move_target(world,staff_id,task)
			else:
				_go_outside(world,staff_id)
		else:
			var tea: Dictionary = _tea_position(world,staff_id)
			if not tea.is_empty():
				task.phase = "travel"
				task.floor_id = tea.floor_id
				task.cell = tea.cell
				task.tea = true
				_move_target(world,staff_id,task)
			else:
				_go_outside(world,staff_id)
	elif task.phase=="wait_bed":
		var selection: Dictionary = _select_facility(world,staff_id,"sleep")
		if not selection.is_empty() and not world.facts.moves.has(staff_id) and _reserve(world,staff_id,task,selection):
			return
		if int(task.waited_ticks)>=_ticks(float(content.balance.staff_sleep.missing_bed_wait_seconds)):
			_go_outside(world,staff_id)
		elif not _at_target(world,staff_id,task):
			_move_target(world,staff_id,task)
	elif task.phase=="travel":
		var facility_id: String = str(task.facility_id)
		if not facility_id.is_empty() and (not world.facts.facilities.has(facility_id) or world.facts.facilities[facility_id].failed):
			_interrupt(world,staff_id)
			return
		if not _at_target(world,staff_id,task):
			if task.kind!="recreation" and not world.facts.moves.has(staff_id):
				var legal: Dictionary = space.route(world,staff_id,int(task.floor_id),task.cell,[],{},true)
				if not legal.ok and legal.get("status","")=="unreachable":
					_release_if_clear(world,staff_id)
					if str(task.facility_id).is_empty():
						task.selection = {}
						task.phase = "wait_safe"
						staff.life_reason = "原休息位置已不可达，重新选择合法位置"
						return
			_move_target(world,staff_id,task)
			return
		if task.kind=="sleep":
			task.phase = "sleep"
			_lie_down(world,staff_id,facility_id)
			staff.life_reason = "正在员工床实际睡眠"
		elif task.kind=="rest":
			task.phase = "rest"
			if not facility_id.is_empty():
				world.facts.actors[staff_id].posture = "seated"
				world.facts.actors[staff_id].support_facility_id = facility_id
				space.sync_actor(world,staff_id)
	elif task.phase in ["sleep","rest"]:
		if not str(task.facility_id).is_empty() and (not world.facts.facilities.has(task.facility_id) or world.facts.facilities[task.facility_id].failed):
			_interrupt(world,staff_id)
	elif task.phase=="exiting":
		if _at_target(world,staff_id,task):
			world.facts.actors[staff_id].location = {"kind":"outside"}
			space.sync_actor(world,staff_id)
			task.phase = "offsite"
			task.offsite_ticks = 0
			task.required_offsite_ticks = int(staff.sleep_remaining_ticks) if task.kind=="sleep" else 0
			task.sleep_credit_ticks = int(staff.sleep_remaining_ticks) if int(staff.sleep_remaining_ticks)>0 else _ticks(float(content.balance.staff_sleep.sleep_seconds))
			if task.kind=="leave":
				var leave: Dictionary = staff.leave_plan
				leave.state = "active"
				leave.actual_start_tick = world.sim_tick
				leave.end_tick = world.sim_tick+int(leave.days)*WorldState.TICKS_PER_DAY if leave.kind=="voluntary" else -1
			staff.life_reason = "院外带薪休整"
		else:
			_move_target(world,staff_id,task)
	elif task.phase in ["returning","release"]:
		_release_if_clear(world,staff_id)
		if _at_target(world,staff_id,task) and str(task.facility_id).is_empty():
			staff.life_task = {"phase":"idle"}
			staff.last_rest_end_tick = world.sim_tick
			staff.block_new_work = bool(staff.rest_obligation) or int(staff.sleep_remaining_ticks)>0
			if task.kind=="leave":
				staff.leave_plan = {}
			staff.life_reason = "休息结束，按当前班表返岗"
		else:
			_move_target(world,staff_id,task)

func _reserve(world: WorldState, staff_id: String, task: Dictionary, selection: Dictionary) -> bool:
	var facility_id: String = str(selection.facility_id)
	if world.facts.staff_life.reservations.has(facility_id) or _patient_occupies(world,facility_id):
		return false
	var reason: String = space.reserve_facility(world,facility_id,staff_id,task.id)
	if not reason.is_empty():
		world.facts.staff[staff_id].life_reason = reason
		return false
	var layout: Dictionary = space.facility_layout(world,facility_id)
	var target: Array = layout.patient_cell
	var route: Dictionary = space.route(world,staff_id,int(layout.floor_id),target)
	if not route.ok:
		world.facts.staff[staff_id].life_reason = route.get("reason","休息位置路线暂不可用")
		return false
	task.facility_id = facility_id
	task.floor_id = layout.floor_id
	task.cell = target.duplicate()
	task.phase = "travel"
	world.facts.staff_life.reservations[facility_id] = {"id":task.id,"kind":task.kind,"staff_ids":[staff_id],"state":"reserved","remaining_ticks":int(world.facts.staff[staff_id].sleep_remaining_ticks) if task.kind=="sleep" else 0}
	_move_target(world,staff_id,task)
	return true

func _select_facility(world: WorldState, staff_id: String, kind: String) -> Dictionary:
	var best: Dictionary = {}
	var best_time: float = INF
	var staff: Dictionary = world.facts.staff[staff_id]
	var tea: Dictionary = _tea_position(world,staff_id) if kind=="rest" else {}
	if not tea.is_empty():
		best_time = float(tea.travel_ticks)*WorldState.TICK_SECONDS+maxf(0,float(content.balance.schedule.compensatory_rest_target_energy)-float(staff.energy))/float(content.balance.wellbeing.energy_tea_per_second)
	for id: String in world.ids("facilities"):
		var facility: Dictionary = world.facts.facilities[id]
		if HospitalRemodel.blocked(world,id) or facility.failed or world.facts.staff_life.reservations.has(id) or _patient_occupies(world,id) or not _staff_area(world,facility):
			continue
		if kind=="sleep" and facility.definition_id!=str(content.balance.staff_sleep.bed_definition_id):
			continue
		if kind=="rest" and not _is_seat(facility.definition_id):
			continue
		var fit: Dictionary = space.facility_quote(world,id,staff_id)
		if not fit.ok:
			continue
		var layout: Dictionary = space.facility_layout(world,id)
		var target: Array = fit.get("patient_cell",layout.patient_cell)
		var candidate: WorldState = _adapted_candidate(world,id,fit,staff_id)
		var candidate_space: HospitalSpace = HospitalSpace.new(content)
		var route: Dictionary = candidate_space.route(candidate,staff_id,int(layout.floor_id),target)
		var origin: Dictionary = world.facts.actors[staff_id].location
		candidate.facts.actors[staff_id].location = {"kind":"floor","floor_id":layout.floor_id,"cell":target.duplicate(),"height_m":0.0}
		candidate_space = HospitalSpace.new(content)
		var back: Dictionary = candidate_space.route(candidate,staff_id,int(origin.get("floor_id",layout.floor_id)),origin.get("cell",target))
		if not route.ok or not back.ok:
			continue
		var travel: float = _route_ticks(route)
		var rate: float = float(content.balance.wellbeing.energy_rest_per_second)
		for variant: Dictionary in content.catalog.get("chair_variants",[]):
			if variant.definition_id==facility.definition_id and variant.effect=="staff_rest_energy_rate":
				rate = float(variant.parameters.per_second)
		var time: float = travel*WorldState.TICK_SECONDS
		if kind=="rest":
			time += maxf(0,float(content.balance.schedule.compensatory_rest_target_energy)-float(staff.energy)+travel*WorldState.TICK_SECONDS*float(content.balance.wellbeing.energy_walk_per_second))/rate
		if time<best_time:
			best_time = time
			best = {"facility_id":id,"floor_id":layout.floor_id,"cell":target}
	return best

func _tea_position(world: WorldState, staff_id: String) -> Dictionary:
	var best: Dictionary = {}
	var shortest: float = INF
	for room_id: String in world.ids("rooms"):
		var room: Dictionary = world.facts.rooms[room_id]
		if not _is_staff_room(room) or HospitalRemodel.blocked(world,room_id):
			continue
		for target: Array in BuildGeometry.cells(room):
			if not _tea_cell(world,staff_id,room,target):
				continue
			var route: Dictionary = space.route(world,staff_id,int(room.floor_id),target)
			if not route.ok:
				continue
			var cost: float = _route_ticks(route)
			if cost<shortest:
				shortest = cost
				best = {"floor_id":room.floor_id,"cell":target,"travel_ticks":cost}
	return best

func _go_outside(world: WorldState, staff_id: String) -> void:
	var task: Dictionary = world.facts.staff[staff_id].life_task
	var entry: Dictionary = _entry(world)
	task.phase = "exiting"
	task.floor_id = entry.floor_id
	task.cell = entry.cell.duplicate()
	world.facts.staff[staff_id].life_reason = "没有兼容休息位置，正在真实离院"
	_move_target(world,staff_id,task)

func _return_from_outside(world: WorldState, staff_id: String) -> void:
	var actor: Dictionary = world.facts.actors[staff_id]
	var entry: Dictionary = _entry(world)
	# Crossing the entrance is the sole re-entry point after actual offsite rest.
	if not space.static_reason(world,actor,int(entry.floor_id),Vector2i(entry.cell[0],entry.cell[1])).is_empty():
		world.facts.staff[staff_id].life_reason = "返院入口受阻，保留已完成的休整"
		return
	var arriving: Dictionary = actor.duplicate(true)
	arriving.location = {"kind":"floor","floor_id":entry.floor_id,"cell":entry.cell.duplicate(),"height_m":0.0}
	var bounds: Rect2 = space.body_rectangle(arriving)
	for other: Dictionary in world.facts.actors.values():
		if other.id!=staff_id and other.location.kind=="floor" and int(other.location.floor_id)==int(entry.floor_id) and bounds.intersects(space.body_rectangle(other),false):
			world.facts.staff[staff_id].life_reason = "返院入口正被使用，等待实际空位"
			return
	actor.location = {"kind":"floor","floor_id":entry.floor_id,"cell":entry.cell.duplicate(),"height_m":0.0}
	space.sync_actor(world,staff_id)
	_begin_return(world,staff_id)

func _begin_return(world: WorldState, staff_id: String) -> void:
	var staff: Dictionary = world.facts.staff[staff_id]
	var task: Dictionary = staff.life_task
	var actor: Dictionary = world.facts.actors[staff_id]
	if actor.get("posture","")=="seated":
		actor.posture = "standing"
		actor.erase("support_facility_id")
		space.sync_actor(world,staff_id)
	task.phase = "returning"
	if task.kind=="rest" and float(staff.energy)>=float(content.balance.schedule.compensatory_rest_target_energy) and int(staff.get("rest_debt_ticks",0))==0:
		staff.rest_obligation = false
	var return_location: Dictionary = task.return_location
	var entry: Dictionary = _entry(world)
	task.floor_id = return_location.get("floor_id",entry.floor_id)
	task.cell = return_location.get("cell",entry.cell).duplicate()
	_move_target(world,staff_id,task)

func _interrupt(world: WorldState, staff_id: String) -> void:
	var staff: Dictionary = world.facts.staff[staff_id]
	var task: Dictionary = staff.life_task
	var facility_id: String = str(task.get("facility_id",""))
	if task.kind=="recreation" and world.facts.staff_life.reservations.has(facility_id):
		var reservation: Dictionary = world.facts.staff_life.reservations[facility_id]
		reservation.state = "releasing"
		for participant_id: String in reservation.staff_ids:
			_begin_return(world,participant_id)
	else:
		_begin_return(world,staff_id)
	staff.life_reason = "安全离位，睡眠与补休余量保留"

func _release_if_clear(world: WorldState, staff_id: String) -> void:
	var task: Dictionary = world.facts.staff[staff_id].life_task
	var id: String = str(task.get("facility_id",""))
	if id.is_empty():
		return
	if world.facts.facilities.has(id) and space.overlaps_facility(world,staff_id,id):
		return
	task.facility_id = ""
	if not world.facts.staff_life.reservations.has(id):
		return
	var reservation: Dictionary = world.facts.staff_life.reservations[id]
	reservation.staff_ids.erase(staff_id)
	if reservation.staff_ids.is_empty():
		world.facts.staff_life.reservations.erase(id)

func _can_recreate(world: WorldState, staff_id: String) -> bool:
	if not world.facts.staff.has(staff_id):
		return false
	var staff: Dictionary = world.facts.staff[staff_id]
	var task: Dictionary = staff.life_task
	var rest_window: bool = task.phase=="rest" or not staff.get("on_shift",true)
	var idle_window: bool = staff.role!="doctor" and staff.get("dispatch_idle",false) and int(staff.get("dispatch_idle_tick",-1))==world.sim_tick
	if staff.get("departed",false) or not (rest_window or idle_window) or not task.phase in ["idle","rest"] or int(staff.stress_milli)<roundi(float(content.balance.wellbeing.recreation_min_stress)*1000):
		return false
	if float(staff.energy)<=float(content.balance.wellbeing.recreation_max_energy_priority) or int(staff.get("rest_debt_ticks",0))>0 or int(staff.sleep_remaining_ticks)>0 or int(staff.awake_ticks)>=_ticks(float(content.balance.staff_sleep.awake_limit_seconds)):
		return false
	if not staff.get("leave_plan",{}).is_empty() or Development.safe_busy(world,staff_id) or _other_commitment(world,staff_id) or _ward_responsibility(world,staff_id) or staff.get("supply_strike",false):
		return false
	var allowed: Array = world.facts.staff_life.settings.roles
	if not allowed.is_empty() and not staff.role in allowed:
		return false
	if int(staff.recreation_count)>=int(content.balance.wellbeing.recreation_max_per_day) or world.sim_tick<int(staff.recreation_cooldown_tick):
		return false
	return _recreation_count(world)<int(world.facts.staff_life.settings.maximum_recreation)

func _recreation(world: WorldState, ids: Array, preferred: String) -> CommandResult:
	if ids.is_empty():
		return _result(world,false,"staff_missing","请选择员工")
	var seen: Dictionary = {}
	for id: Variant in ids:
		if not id is String or seen.has(id) or not _can_recreate(world,id):
			return _result(world,false,"recreation_unavailable","员工当前有工作、睡眠、补休或冷却义务")
		seen[id] = true
	if _recreation_count(world)+ids.size()>int(world.facts.staff_life.settings.maximum_recreation):
		return _result(world,false,"recreation_limit","当前同时娱乐人数已满")
	for facility_id: String in world.ids("facilities"):
		var facility: Dictionary = world.facts.facilities[facility_id]
		var definition: Dictionary = content.definition("staff_recreation_equipment",facility.definition_id)
		if HospitalRemodel.blocked(world,facility_id) or (not preferred.is_empty() and facility_id!=preferred) or definition.is_empty() or facility.failed or not _staff_area(world,facility) or world.facts.staff_life.reservations.has(facility_id) or int(definition.capacity)<ids.size():
			continue
		var partners: Array = ids.slice(1)
		var fit: Dictionary = space.facility_quote(world,facility_id,ids[0],partners)
		if not fit.ok:
			continue
		var layout: Dictionary = space.facility_layout(world,facility_id)
		var positions: Array = [fit.get("patient_cell",layout.patient_cell)]
		var operators: Array = fit.get("operator_cells",layout.get("operator_cells",[]))
		for index: int in partners.size():
			if operators.size()<=index:
				positions.clear()
				break
			positions.append(operators[index])
		if positions.size()!=ids.size():
			continue
		var all_reachable: bool = true
		var candidate: WorldState = _adapted_candidate(world,facility_id,fit,ids[0])
		var candidate_space: HospitalSpace = HospitalSpace.new(content)
		for index: int in ids.size():
			if not candidate_space.route(candidate,ids[index],int(layout.floor_id),positions[index]).ok:
				all_reachable = false
		if not all_reachable:
			continue
		var reservation_id: String = "recreation_"+str(world.sim_tick)+"_"+ids[0]
		var reason: String = space.reserve_facility(world,facility_id,ids[0],reservation_id,partners)
		if not reason.is_empty():
			continue
		world.facts.staff_life.reservations[facility_id] = {"id":reservation_id,"kind":"recreation","staff_ids":ids.duplicate(),"state":"gathering","remaining_ticks":_ticks(float(content.balance.wellbeing.recreation_seconds)),"positions":positions}
		for index: int in ids.size():
			var staff: Dictionary = world.facts.staff[ids[index]]
			var previous: Dictionary = staff.life_task
			var return_location: Dictionary = previous.get("return_location",world.facts.actors[ids[index]].location).duplicate(true)
			var was_resting: bool = previous.get("kind","")=="rest"
			if not str(previous.get("facility_id","")).is_empty():
				# Restoring the original obligation does not retain two physical seats.
				_release_if_clear(world,ids[index])
				if not str(previous.get("facility_id","")).is_empty():
					world.facts.staff_life.reservations.erase(previous.facility_id)
			var actor: Dictionary = world.facts.actors[ids[index]]
			if actor.get("posture","")=="seated":
				actor.posture = "standing"
				actor.erase("support_facility_id")
				space.sync_actor(world,ids[index])
			staff.life_task = {"id":reservation_id,"kind":"recreation","phase":"travel","facility_id":facility_id,"floor_id":layout.floor_id,"cell":positions[index],
				"return_location":return_location,"resume_rest":was_resting,"offsite_ticks":0,"offsite_sleep_satisfied":false}
			staff.block_new_work = true
			_move_target(world,ids[index],staff.life_task)
		return _result(world,true,"applied","",ids)
	return _result(world,false,"no_recreation_slot","没有兼容、可达且空闲的员工娱乐设施")

func _dispatch_recreation(world: WorldState) -> void:
	for facility_id: String in world.facts.staff_life.reservations.keys():
		var reservation: Dictionary = world.facts.staff_life.reservations[facility_id]
		if reservation.kind!="recreation" or reservation.state!="gathering":
			continue
		var all_present: bool = true
		for staff_id: String in reservation.staff_ids:
			var task: Dictionary = world.facts.staff[staff_id].life_task
			if not _at_target(world,staff_id,task):
				all_present = false
		if not all_present:
			continue
		reservation.state = "working"
		for staff_id: String in reservation.staff_ids:
			var staff: Dictionary = world.facts.staff[staff_id]
			staff.life_task.phase = "recreation"
			staff.recreation_count += 1
			staff.recreation_cooldown_tick = world.sim_tick+_ticks(float(content.balance.wellbeing.recreation_cooldown_seconds))
			staff.last_recreation_tick = world.sim_tick

func _adapted_candidate(world: WorldState, facility_id: String, fit: Dictionary, actor_id: String) -> WorldState:
	var facts: Dictionary = world.facts.duplicate()
	facts.adaptations = world.facts.adaptations.duplicate()
	facts.actors = world.facts.actors.duplicate()
	facts.actors[actor_id] = world.facts.actors[actor_id].duplicate(true)
	var candidate: WorldState = WorldState.new(facts)
	if not fit.get("unchanged",false):
		var reservation: Dictionary = fit.duplicate(true)
		reservation.erase("ok")
		reservation.owner_id = "life_preview"
		candidate.facts.adaptations[facility_id] = reservation
	return candidate

func _tea_cell(world: WorldState, staff_id: String, room: Dictionary, cell: Array) -> bool:
	var actor: Dictionary = world.facts.actors[staff_id].duplicate(true)
	actor.location = {"kind":"floor","floor_id":room.floor_id,"cell":cell}
	actor.posture = "standing"
	var area: Rect2 = space.body_rectangle(actor)
	if not space.room_contains(room,area):
		return false
	for door: Dictionary in world.facts.floors.overrides[str(room.floor_id)].get("doors",[]):
		if area.grow(1.0).has_point(Vector2(float(door.cell[0]),float(door.cell[1]))):
			return false
	for facility: Dictionary in world.facts.facilities.values():
		if int(facility.floor_id)!=int(room.floor_id):
			continue
		for point: Array in [facility.get("patient_cell",[])]+facility.get("operator_cells",[]):
			if not point.is_empty() and area.has_point(Vector2(float(point[0]),float(point[1]))):
				return false
	for other: Dictionary in world.facts.staff.values():
		var task: Dictionary = other.get("life_task",{})
		if other.id!=staff_id and task.get("phase","idle")!="idle" and int(task.get("floor_id",-1))==int(room.floor_id) and task.get("cell",[])==cell:
			return false
	return true

func _lie_down(world: WorldState, staff_id: String, facility_id: String) -> void:
	var actor: Dictionary = world.facts.actors[staff_id]
	var facility: Dictionary = world.facts.facilities[facility_id]
	actor.posture = "lying"
	actor.support_facility_id = facility_id
	actor.facing = float(facility.get("rotation",0))*PI/2.0
	var anchor: Vector3 = space.support_anchor(world,facility_id)
	var layout: Dictionary = space.facility_layout(world,facility_id)
	var dimensions: Dictionary = content.actor_body(actor)
	var center: float = float(space.clearance(actor))*0.5
	var length: float = float(dimensions.height_m)/HospitalSpace.CELL_METERS
	actor.location.height_m = anchor.y+float(dimensions.depth_m)*0.5
	actor.location.cell = [float(layout.cell[0])+anchor.x/HospitalSpace.CELL_METERS+length*0.5*sin(float(actor.facing))-center,
		float(layout.cell[1])+anchor.z/HospitalSpace.CELL_METERS+length*0.5*cos(float(actor.facing))-center]
	space.sync_actor(world,staff_id)

func _integral(staff: Dictionary, energy_rate: float, fatigue_rate: float, stress_rate: float) -> void:
	staff.energy = clampf(float(staff.energy)+energy_rate*WorldState.TICK_SECONDS,0.0,100.0)
	if staff.role=="doctor":
		staff.fatigue = clampf(float(staff.fatigue)+fatigue_rate*WorldState.TICK_SECONDS,0.0,100.0)
	# Fractional milli-points survive ticks instead of rounding every sample up.
	var stress_delta: float = stress_rate*1000.0*WorldState.TICK_SECONDS+float(staff.stress_credit)
	var whole: int = int(stress_delta)
	staff.stress_credit = stress_delta-whole
	staff.stress_milli = clampi(int(staff.stress_milli)+whole,0,100000)
	if int(staff.stress_milli) in [0,100000]:
		staff.stress_credit = 0.0

func _recover(staff: Dictionary, energy_rate: float, fatigue_rate: float, stress_rate: float) -> void:
	_integral(staff,energy_rate,-fatigue_rate,-stress_rate)

func _rest_energy_rate(world: WorldState, task: Dictionary) -> float:
	if str(task.get("facility_id","")).is_empty():
		return float(content.balance.wellbeing.energy_tea_per_second)
	var definition_id: String = str(world.facts.facilities[task.facility_id].definition_id)
	for variant: Dictionary in content.catalog.get("chair_variants",[]):
		if variant.definition_id==definition_id and variant.effect=="staff_rest_energy_rate":
			return float(variant.parameters.per_second)
	return float(content.balance.wellbeing.energy_rest_per_second)

func _rest_stress_rate(world: WorldState, task: Dictionary) -> float:
	if not str(task.get("facility_id","")).is_empty():
		for variant: Dictionary in content.catalog.get("chair_variants",[]):
			if variant.definition_id==world.facts.facilities[task.facility_id].definition_id and variant.effect=="staff_rest_stress_rate":
				return float(variant.parameters.per_second)
	return float(content.balance.wellbeing.stress_rest_per_second)

func _other_commitment(world: WorldState, staff_id: String) -> bool:
	var staff: Dictionary = world.facts.staff[staff_id]
	if not staff.get("base_task",{}).is_empty():
		return true
	var training_id: String = str(staff.get("training_job_id",""))
	if not training_id.is_empty() and world.facts.get("training_jobs",{}).get(training_id,{}).get("state","")=="working":
		return true
	for handoff: Dictionary in world.facts.get("staff_schedule",{}).get("handoffs",{}).values():
		if handoff.get("new_id","")==staff_id:
			return true
	return false

func _relief_available(world: WorldState, staff_id: String) -> bool:
	var staff: Dictionary = world.facts.staff[staff_id]
	for other_id: String in world.ids("staff"):
		var other: Dictionary = world.facts.staff[other_id]
		if other_id==staff_id or other.role!=staff.role or not other.get("on_shift",false) or other.get("block_new_work",false) or other.life_task.phase!="idle" or world.facts.moves.has(other_id) or other.get("supply_strike",false) or not str(other.get("training_job_id","")).is_empty():
			continue
		if other.get("scheduled_kind","")!=staff.get("scheduled_kind","") or (staff.role in ["doctor","nurse"] and not other.get("base_prepared",false)):
			continue
		var qualified: bool = true
		if staff.role in ["doctor","nurse"]:
			for track: String in Development.tracks(staff):
				if int(other.abilities[track])<mini(1,int(staff.abilities[track])):
					qualified = false
		if qualified and world.facts.actors[other_id].location.kind=="floor":
			return true
	return false

func _pool_resting(world: WorldState, staff_id: String) -> bool:
	var staff: Dictionary = world.facts.staff[staff_id]
	for other: Dictionary in world.facts.staff.values():
		if other.id!=staff_id and other.role==staff.role and other.get("life_task",{}).get("early",false) and other.life_task.phase!="idle":
			return true
	return false

func _ward_responsibility(world: WorldState, staff_id: String) -> bool:
	for stay: Dictionary in world.facts.ward_stays.values():
		if stay.get("nurse_id","")==staff_id and not stay.get("phase","") in ["release_wait","complete"]:
			return true
	return false

func _patient_occupies(world: WorldState, facility_id: String) -> bool:
	for actor: Dictionary in world.facts.actors.values():
		if actor.get("support_facility_id","")==facility_id and not world.facts.staff.has(actor.id):
			return true
	for seat: Dictionary in world.facts.get("waiting_life",{}).get("seats",{}).values():
		if seat.get("facility_id","")==facility_id:
			return true
	for need: Dictionary in world.facts.get("waiting_life",{}).get("needs",{}).values():
		if need.get("facility_id","")==facility_id:
			return true
	return false

func _staff_area(world: WorldState, facility: Dictionary) -> bool:
	return _is_staff_room(world.facts.rooms.get(facility.get("room_id",""),{}))

static func _is_staff_room(room: Dictionary) -> bool:
	return str(room.get("kind",room.get("type",""))) in ["rest","staff_garden"]

static func _is_seat(definition_id: String) -> bool:
	return definition_id in ["FUR06","FUR09","FUR10","FUR11","FUR49","FUR50","FUR51","FUR52"]

func _recreation_count(world: WorldState) -> int:
	var count: int = 0
	for reservation: Dictionary in world.facts.staff_life.reservations.values():
		if reservation.kind=="recreation":
			count += reservation.staff_ids.size()
	return count

static func _route_ticks(route: Dictionary) -> float:
	return float(route.get("arrival_ticks",route.get("estimated_ticks",route.get("path",[]).size())))

static func _entry(world: WorldState) -> Dictionary:
	var entry: Dictionary = world.facts.get("entry",{})
	return {"floor_id":int(entry.get("floor_id",1)),"cell":entry.get("exit_cell",entry.get("cell",[48,95]))}

func _at_target(world: WorldState, staff_id: String, task: Dictionary) -> bool:
	return not task.get("cell",[]).is_empty() and space.at(world,staff_id,int(task.floor_id),task.cell)

func _move_target(world: WorldState, staff_id: String, task: Dictionary) -> void:
	if not _at_target(world,staff_id,task):
		var reason: String = space.request_move(world,staff_id,int(task.floor_id),task.cell)
		if not reason.is_empty():
			world.facts.staff[staff_id].life_reason = reason

static func _ticks(seconds: float) -> int:
	return ceili(seconds/WorldState.TICK_SECONDS)

func _result(world: WorldState, accepted: bool, code: String, reason: String, changed: Array = []) -> CommandResult:
	return CommandResult.new(accepted,code,reason,changed,world.revision)
