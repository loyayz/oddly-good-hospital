class_name HospitalStaffWellbeing
extends RefCounted

const Development = preload("res://game/staff/clinical_development.gd")
const REST_SEATS: Array[String] = ["FUR06","FUR09","FUR10","FUR11","FUR49","FUR50","FUR51","FUR52"]

var content: HospitalContent
var _facility_navigation: NavigationCache = NavigationCache.new()
var space: HospitalSpace
var _dispatch_view: Dictionary = {}
var personal_beds: HospitalPersonalBeds

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry
	personal_beds = HospitalPersonalBeds.new(self)

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
	personal_beds.sync(world)

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
	_dispatch_view = _staff_query(world)
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
		var safe: bool = not _busy(world,staff_id) and not _other_commitment(world,staff_id)
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
	_dispatch_view = {}

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
	var bed_error: String = HospitalPersonalBeds.validate(world)
	if not bed_error.is_empty(): return bed_error
	var owners: Dictionary = {}
	for facility_id: Variant in world.facts.staff_life.reservations:
		var reservation: Variant = world.facts.staff_life.reservations[facility_id]
		if not facility_id is String or not reservation is Dictionary or not world.facts.facilities.has(facility_id) or not world.facts.facilities[facility_id] is Dictionary or not reservation.get("staff_ids") is Array or reservation.staff_ids.is_empty() or not reservation.get("kind","") is String or not reservation.get("kind","") in ["rest","sleep","recreation"]:
			return "员工生活预约引用无效"
		for id: Variant in reservation.staff_ids:
			if not id is String or not world.facts.staff.has(id) or not world.facts.staff[id] is Dictionary or owners.has(id) or not world.facts.staff[id].get("life_task") is Dictionary or not facility_id in [world.facts.staff[id].life_task.get("facility_id",""),world.facts.staff[id].life_task.get("leaving_facility_id","")]:
				return "员工同时占用多个生活位置或预约身份失配"
			owners[id] = facility_id
			if reservation.kind=="sleep" and world.facts.staff_life.personal_beds.get(facility_id,{}).get("staff_id","")!=id: return "睡眠使用与个人床归属不一致"
	for staff_value: Variant in world.facts.staff.values():
		if not staff_value is Dictionary:
			return "员工生活记录无效"
		var staff: Dictionary = staff_value
		if not staff.get("awake_ticks") is int or int(staff.awake_ticks)<0 or not staff.get("sleep_remaining_ticks") is int or int(staff.sleep_remaining_ticks)<0 or int(staff.sleep_remaining_ticks)>_ticks(float(content.balance.staff_sleep.sleep_seconds)):
			return "清醒或睡眠余量无效"
		var task: Variant = staff.get("life_task")
		if not task is Dictionary or not task.get("phase","") is String or not task.get("phase","") in ["idle","wait_safe","travel","rest","sleep","wait_bed","exiting","offsite","returning","recreation","release","area_travel","local_wait","local_travel","manual_wait"]:
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
	_release_previous_seat(world,staff_id)
	if task.get("group_leader_id","")!="" and task.phase in ["area_travel","local_wait","local_travel","manual_wait"]:
		if task.group_leader_id==staff_id: _dispatch_public_recreation(world,staff_id)
		return
	if task.get("public_purpose","")=="rest" and task.phase in ["area_travel","local_wait","local_travel"]:
		_dispatch_public_rest(world,staff_id)
		return
	if task.phase=="wait_safe":
		if _busy(world,staff_id) or _other_commitment(world,staff_id) or world.facts.moves.has(staff_id):
			return
		staff.on_shift = false
		staff.base_prepared = false
		if task.kind=="leave":
			_go_outside(world,staff_id)
			return
		if task.kind=="rest":
			task.merge({"public_purpose":"rest","actor_id":staff_id,"mode":"auto","area":{},"arrived_tick":-1,"started_tick":world.sim_tick,"phase":"area_travel"},true)
			_dispatch_public_rest(world,staff_id)
			return
		var selection: Dictionary = task.selection
		var selection_query: Dictionary = {}
		if selection.is_empty():
			selection = _select_facility(world,staff_id,task.kind,selection_query)
		if not selection.is_empty() and _reserve(world,staff_id,task,selection):
			return
		if task.kind=="sleep":
			var tea: Dictionary = _tea_position(world,staff_id)
			if not tea.is_empty():
				task.phase = "wait_bed"
				task.floor_id = tea.floor_id
				task.cell = tea.cell
				staff.life_reason = ("未分配个人床" if personal_beds.bed_for(world,staff_id).is_empty() else "本人床暂不可用")+"，正在员工区候床"
				_move_target(world,staff_id,task)
			else:
				_go_outside(world,staff_id)
		else:
			var tea: Dictionary = selection_query.tea if selection_query.has("tea") else _tea_position(world,staff_id)
			if not tea.is_empty():
				task.phase = "travel"
				task.floor_id = tea.floor_id
				task.cell = tea.cell
				task.tea = true
				_move_target(world,staff_id,task)
			else:
				_go_outside(world,staff_id)
	elif task.phase=="wait_bed":
		var selection: Dictionary = {} if world.facts.moves.has(staff_id) else _select_facility(world,staff_id,"sleep")
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
	var reason: String = space.reserve_facility(world,facility_id,staff_id,staff_id)
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

func _select_facility(world: WorldState, staff_id: String, kind: String, query: Dictionary = {}) -> Dictionary:
	var best: Dictionary = {}
	var best_time: float = INF
	var staff: Dictionary = world.facts.staff[staff_id]
	var tea: Dictionary = _tea_position(world,staff_id) if kind=="rest" else {}
	if kind=="rest": query.tea = tea
	if not tea.is_empty():
		best_time = float(tea.travel_ticks)*WorldState.TICK_SECONDS+maxf(0,float(content.balance.schedule.compensatory_rest_target_energy)-float(staff.energy))/float(content.balance.wellbeing.energy_tea_per_second)
	# Each candidate has its own immutable adaptation projection. The space
	# caches compare world identity and captured geometry before sharing graphs.
	var candidate_space: HospitalSpace
	var occupied: Dictionary = {}
	var candidates: Array = []
	if kind=="sleep":
		var own_bed: String = personal_beds.bed_for(world,staff_id)
		if not own_bed.is_empty(): candidates = [own_bed]
	elif kind=="rest":
		var task: Dictionary = staff.life_task
		if task.get("public_purpose","")=="rest": candidates = space.public_areas.facilities(world,task.area,REST_SEATS)
		else:
			for definition_id: String in REST_SEATS: candidates.append_array(world.facility_ids(definition_id))
	else: candidates = world.ids("facilities")
	candidates.sort()
	for id: String in candidates:
		if not world.facts.facilities.has(id): continue
		var facility: Dictionary = world.facts.facilities[id]
		if kind=="sleep" and facility.definition_id!=str(content.balance.staff_sleep.bed_definition_id):
			continue
		if kind=="rest" and not _is_seat(facility.definition_id):
			continue
		if not _staff_area(world,facility) or HospitalRemodel.blocked(world,id) or facility.failed or world.facts.staff_life.reservations.has(id):
			continue
		if occupied.is_empty(): occupied = _patient_occupancy(world)
		if _patient_occupies(world,id,occupied): continue
		var fit: Dictionary = space.facility_quote(world,id,staff_id)
		if not fit.ok:
			continue
		var layout: Dictionary = space.facility_layout(world,id)
		var target: Array = fit.get("patient_cell",layout.patient_cell)
		var candidate: WorldState = _adapted_candidate(world,id,fit,staff_id)
		if candidate_space==null:
			candidate_space = HospitalSpace.new(content)
			# Retain only the existing bounded static graph cache. Actor indices,
			# scopes and route/exit witnesses belong to this fresh query space.
			candidate_space._navigation = _facility_navigation
		var route: Dictionary = candidate_space.route(candidate,staff_id,int(layout.floor_id),target)
		if not route.ok: continue
		var origin: Dictionary = world.facts.actors[staff_id].location
		candidate.facts.actors[staff_id].location = {"kind":"floor","floor_id":layout.floor_id,"cell":target.duplicate(),"height_m":0.0}
		candidate_space.sync_actor(candidate,staff_id)
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
	var task: Dictionary = world.facts.staff[staff_id].life_task
	var reference: Dictionary = task.get("area",{}) if task.get("public_purpose","")=="rest" else {}
	if reference.is_empty():
		var selected: Dictionary = space.public_areas.select(world,staff_id,REST_SEATS,["rest","staff_garden"],"rest")
		if selected.is_empty(): return {}
		reference = selected.area
		return {"floor_id":selected.floor_id,"cell":selected.cell,"travel_ticks":selected.travel_ticks}
	space.begin_dynamic_route_query(world)
	var point: Dictionary = space.public_areas.waiting_point(world,staff_id,reference)
	space.end_route_query()
	return point

func _dispatch_public_rest(world: WorldState, staff_id: String) -> void:
	var staff: Dictionary = world.facts.staff[staff_id]
	var task: Dictionary = staff.life_task
	if world.facts.actors[staff_id].location.kind!="floor" or world.facts.moves.has(staff_id): return
	var selected_point: Dictionary = {}
	if space.public_areas.region(world,task.area).is_empty():
		var selected: Dictionary = space.public_areas.select(world,staff_id,REST_SEATS,["rest","staff_garden"],"rest")
		if selected.is_empty():
			_go_outside(world,staff_id)
			return
		task.area = selected.area
		task.arrived_tick = -1
		task.floor_id = selected.floor_id
		task.cell = selected.cell
		selected_point = {"floor_id":selected.floor_id,"cell":selected.cell,"travel_ticks":selected.travel_ticks}
	if not space.public_areas.contains(world,task.area,staff_id):
		var point: Dictionary = selected_point if not selected_point.is_empty() else space.public_areas.waiting_point(world,staff_id,task.area)
		if not point.is_empty():
			task.floor_id = point.floor_id
			task.cell = point.cell
			_move_target(world,staff_id,task)
		staff.life_reason = "前往休息区"
		return
	if int(task.arrived_tick)<0: task.arrived_tick = world.sim_tick
	task.phase = "local_wait"
	var query: Dictionary = {}
	var choice: Dictionary = _select_facility(world,staff_id,"rest",query)
	if not choice.is_empty() and space.public_areas.turn(world,task,choice.facility_id):
		task.facility_id = choice.facility_id
		task.floor_id = choice.floor_id
		task.cell = choice.cell
		if not _at_target(world,staff_id,task):
			task.phase = "local_travel"
			_move_target(world,staff_id,task)
		elif _reserve(world,staff_id,task,choice): _dispatch_task(world,staff_id)
		return
	var tea: Dictionary = query.get("tea",{})
	if not tea.is_empty():
		task.facility_id = ""
		task.floor_id = tea.floor_id
		task.cell = tea.cell
		task.tea = true
		if _at_target(world,staff_id,task): task.phase = "rest"
		else:
			task.phase = "local_travel"
			_move_target(world,staff_id,task)
	staff.life_reason = "员工区清醒休息" if task.phase=="rest" else "本区等待休息位置"

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
	var arriving: Dictionary = actor.duplicate()
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
	if waiting_recreation(staff):
		var leader: Dictionary = world.facts.staff[task.group_leader_id].life_task
		for member: String in leader.staff_ids: _begin_return(world,member)
	elif task.kind=="recreation" and world.facts.staff_life.reservations.has(facility_id):
		var reservation: Dictionary = world.facts.staff_life.reservations[facility_id]
		reservation.state = "releasing"
		for participant_id: String in reservation.staff_ids:
			_begin_return(world,participant_id)
	else:
		_begin_return(world,staff_id)
	staff.life_reason = "安全离位，睡眠与补休余量保留"

static func waiting_recreation(staff: Dictionary) -> bool:
	var task: Dictionary = staff.get("life_task",{})
	return task.get("kind","")=="recreation" and task.get("group_leader_id","")!="" and task.get("phase","") in ["area_travel","local_wait","local_travel","manual_wait"]

static func work_window(staff: Dictionary) -> bool:
	return staff.get("life_task",{}).get("phase","idle")=="idle" or waiting_recreation(staff)

static func yield_for_work(world: WorldState, database: HospitalContent, geometry: HospitalSpace, staff_ids: Array) -> bool:
	var interrupted: bool = false
	var service: HospitalStaffWellbeing
	for staff_id: String in staff_ids:
		if not waiting_recreation(world.facts.staff[staff_id]): continue
		if service==null: service = HospitalStaffWellbeing.new(database,geometry)
		service._interrupt(world,staff_id)
		interrupted = true
	return interrupted

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
	if not staff.get("leave_plan",{}).is_empty() or _busy(world,staff_id) or _other_commitment(world,staff_id) or _ward_responsibility(world,staff_id) or staff.get("supply_strike",false):
		return false
	var allowed: Array = world.facts.staff_life.settings.roles
	if not allowed.is_empty() and not staff.role in allowed:
		return false
	if int(staff.recreation_count)>=int(content.balance.wellbeing.recreation_max_per_day) or world.sim_tick<int(staff.recreation_cooldown_tick):
		return false
	return _recreation_count(world)<int(world.facts.staff_life.settings.maximum_recreation)

func _recreation(world: WorldState, ids: Array, preferred: String) -> CommandResult:
	var previous: Dictionary = _dispatch_view
	if _dispatch_view.get("world_id",0)!=world.get_instance_id(): _dispatch_view = _staff_query(world)
	var result: CommandResult = _recreation_in_query(world,ids,preferred)
	_dispatch_view = previous
	return result

func _recreation_in_query(world: WorldState, ids: Array, preferred: String) -> CommandResult:
	if ids.is_empty():
		return _result(world,false,"staff_missing","请选择员工")
	var seen: Dictionary = {}
	for id: Variant in ids:
		if not id is String or seen.has(id) or not _can_recreate(world,id):
			return _result(world,false,"recreation_unavailable","员工当前有工作、睡眠、补休或冷却义务")
		seen[id] = true
	if _recreation_count(world)+ids.size()>int(world.facts.staff_life.settings.maximum_recreation):
		return _result(world,false,"recreation_limit","当前同时娱乐人数已满")
	return _begin_public_recreation(world,ids,preferred)

func _recreation_choice(world: WorldState, ids: Array, preferred: String, area: Dictionary) -> Dictionary:
	var candidate_space: HospitalSpace
	for facility_id: String in space.public_areas.region(world,area).get("facilities",[]):
		var facility: Dictionary = world.facts.facilities[facility_id]
		var definition: Dictionary = content.definition("staff_recreation_equipment",facility.definition_id)
		if not facility_id in space.public_areas.region(world,area).get("facilities",[]) or HospitalRemodel.blocked(world,facility_id) or (not preferred.is_empty() and facility_id!=preferred) or definition.is_empty() or facility.failed or not _staff_area(world,facility) or world.facts.staff_life.reservations.has(facility_id) or int(definition.capacity)<ids.size():
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
		if candidate_space==null:
			candidate_space = HospitalSpace.new(content)
			candidate_space._navigation = _facility_navigation
		for index: int in ids.size():
			if not candidate_space.route(candidate,ids[index],int(layout.floor_id),positions[index]).ok:
				all_reachable = false
				break
		if not all_reachable:
			continue
		return {"facility_id":facility_id,"floor_id":int(layout.floor_id),"positions":positions}
	return {}

func _begin_public_recreation(world: WorldState, ids: Array, preferred: String) -> CommandResult:
	var definitions: Array = []
	for definition: Dictionary in content.catalog.staff_recreation_equipment:
		if int(definition.capacity)>=ids.size(): definitions.append(str(definition.id))
	var area: Dictionary = {}
	var selected_entries: Dictionary = {}
	if not preferred.is_empty():
		var facility: Dictionary = world.facts.facilities.get(preferred,{})
		if facility.is_empty() or not facility.definition_id in definitions or facility.get("failed",false) or not _staff_area(world,facility) or HospitalRemodel.blocked(world,preferred): return _result(world,false,"no_recreation_slot","指定娱乐设施不可用或人数不兼容")
		area = space.public_areas.for_facility(world,preferred)
	else:
		var selected: Dictionary = space.public_areas.select(world,ids[0],definitions,["rest","staff_garden"],"recreation",ids,9223372036854775807,selected_entries)
		area = selected.get("area",{})
	if area.is_empty(): return _result(world,false,"no_recreation_slot","没有兼容且可达的员工娱乐区")
	if not preferred.is_empty() and _manual_recreation_quote(world,ids,preferred).is_empty(): return _result(world,false,"no_recreation_slot","指定娱乐设施不兼容或缺少合法真实路线")
	var entries: Dictionary = {}
	for id: String in ids:
		var actor: Dictionary = world.facts.actors[id]
		var point: Dictionary = {"floor_id":actor.location.floor_id,"cell":actor.location.cell.duplicate(),"travel_ticks":0} if space.public_areas.contains(world,area,id) else selected_entries[id] if selected_entries.has(id) else space.public_areas.waiting_point(world,id,area)
		if point.is_empty(): return _result(world,false,"no_recreation_slot","娱乐组成员无法真实进入指定区域")
		entries[id] = point
	var group_id: String = "recreation_"+str(world.sim_tick)+"_"+ids[0]
	for id: String in ids:
		var staff: Dictionary = world.facts.staff[id]
		var previous: Dictionary = staff.life_task
		var leaving: String = str(previous.get("facility_id",""))
		var actor: Dictionary = world.facts.actors[id]
		if actor.get("posture","")=="seated":
			actor.posture = "standing"
			actor.erase("support_facility_id")
			space.sync_actor(world,id)
		staff.life_task = {"id":group_id,"kind":"recreation","phase":"area_travel","facility_id":"","group_leader_id":ids[0],"leaving_facility_id":leaving,"floor_id":entries[id].floor_id,"cell":entries[id].cell,"return_location":previous.get("return_location",actor.location).duplicate(true),"resume_rest":previous.get("kind","")=="rest","offsite_ticks":0,"offsite_sleep_satisfied":false}
	var leader: Dictionary = world.facts.staff[ids[0]].life_task
	leader.merge({"staff_ids":ids.duplicate(),"actor_id":ids[0],"public_purpose":"recreation","mode":"manual" if not preferred.is_empty() else "auto","manual_facility_id":preferred,"area":area,"arrived_tick":-1,"started_tick":world.sim_tick})
	_dispatch_public_recreation(world,ids[0])
	return _result(world,true,"applied","",ids)

func _public_recreation_eligible(world: WorldState, staff_id: String) -> bool:
	var staff: Dictionary = world.facts.staff[staff_id]
	if staff.get("departed",false) or float(staff.energy)<=float(content.balance.wellbeing.recreation_max_energy_priority) or int(staff.stress_milli)<roundi(float(content.balance.wellbeing.recreation_min_stress)*1000): return false
	if int(staff.get("rest_debt_ticks",0))>0 or int(staff.sleep_remaining_ticks)>0 or int(staff.awake_ticks)>=_ticks(float(content.balance.staff_sleep.awake_limit_seconds)): return false
	if not staff.get("leave_plan",{}).is_empty() or _busy(world,staff_id) or _other_commitment(world,staff_id) or _ward_responsibility(world,staff_id) or staff.get("supply_strike",false): return false
	if not world.facts.staff_life.settings.roles.is_empty() and not staff.role in world.facts.staff_life.settings.roles: return false
	if _recreation_count(world)>int(world.facts.staff_life.settings.maximum_recreation): return false
	return int(staff.recreation_count)<int(content.balance.wellbeing.recreation_max_per_day) and world.sim_tick>=int(staff.recreation_cooldown_tick)

func _manual_recreation_quote(world: WorldState, ids: Array, facility_id: String) -> Dictionary:
	var facts: Dictionary = world.facts.duplicate()
	facts.actors = world.facts.actors.duplicate()
	facts.adaptations = world.facts.adaptations.duplicate()
	facts.staff_life = world.facts.staff_life.duplicate()
	facts.staff_life.reservations = world.facts.staff_life.reservations.duplicate()
	var candidate: WorldState = WorldState.new(facts)
	var previous: Dictionary = candidate.facts.staff_life.reservations.get(facility_id,{})
	var displaced: Dictionary = {}
	for other: String in previous.get("staff_ids",[]):
		if not other in ids: displaced[other] = true
	for actor: Dictionary in candidate.facts.actors.values():
		if actor.get("support_facility_id","")==facility_id and not actor.id in ids:
			displaced[actor.id] = true
	for actor_id: String in displaced:
		var actor: Dictionary = world.facts.actors[actor_id].duplicate()
		actor.location = {"kind":"outside"}
		if actor.get("support_facility_id","")==facility_id: actor.erase("support_facility_id")
		candidate.facts.actors[actor_id] = actor
	candidate.facts.staff_life.reservations.erase(facility_id)
	candidate.facts.adaptations.erase(facility_id)
	var area: Dictionary = space.public_areas.for_facility(candidate,facility_id)
	return _recreation_choice(candidate,ids,facility_id,area)

func _dispatch_public_recreation(world: WorldState, leader_id: String) -> void:
	var leader: Dictionary = world.facts.staff[leader_id].life_task
	var ids: Array = leader.staff_ids
	for id: String in ids:
		_release_previous_seat(world,id)
		if not _public_recreation_eligible(world,id):
			for member: String in ids: _begin_return(world,member)
			return
	var definitions: Array = []
	for definition: Dictionary in content.catalog.staff_recreation_equipment:
		if int(definition.capacity)>=ids.size(): definitions.append(str(definition.id))
	if leader.mode=="manual" and (not world.facts.facilities.has(leader.manual_facility_id) or world.facts.facilities[leader.manual_facility_id].get("failed",false) or HospitalRemodel.blocked(world,leader.manual_facility_id)):
		for member: String in ids: _begin_return(world,member)
		return
	if space.public_areas.region(world,leader.area).is_empty() or space.public_areas.facilities(world,leader.area,definitions).is_empty() or (space.public_areas.contains(world,leader.area,leader_id) and not space.public_areas.compatible_geometry(world,leader.area,definitions,ids)):
		if leader.mode=="manual":
			for member: String in ids: _begin_return(world,member)
			return
		var selected: Dictionary = space.public_areas.select(world,leader_id,definitions,["rest","staff_garden"],"recreation",ids)
		if selected.is_empty():
			for member: String in ids: _begin_return(world,member)
			return
		leader.area = selected.area
		leader.arrived_tick = -1
	var all_inside: bool = true
	var direct: Dictionary = _recreation_choice(world,ids,str(leader.manual_facility_id),leader.area) if leader.mode=="manual" and space.public_areas.turn(world,leader,leader.manual_facility_id) else {}
	for id: String in ids:
		var task: Dictionary = world.facts.staff[id].life_task
		if world.facts.actors[id].location.kind!="floor" or world.facts.moves.has(id):
			all_inside = false
			continue
		if not space.public_areas.contains(world,leader.area,id):
			all_inside = false
			var entry: Dictionary = {"floor_id":direct.floor_id,"cell":direct.positions[ids.find(id)]} if not direct.is_empty() else space.public_areas.waiting_point(world,id,leader.area)
			if not entry.is_empty():
				task.floor_id = entry.floor_id
				task.cell = entry.cell
				_move_target(world,id,task)
		world.facts.staff[id].life_reason = "前往指定设施" if leader.mode=="manual" else "前往娱乐区"
	if not all_inside: return
	if int(leader.arrived_tick)<0: leader.arrived_tick = world.sim_tick
	leader.phase = "manual_wait" if leader.mode=="manual" else "local_wait"
	var choice: Dictionary = _recreation_choice(world,ids,str(leader.manual_facility_id),leader.area)
	if choice.is_empty() or not space.public_areas.turn(world,leader,str(choice.get("facility_id",""))):
		for id: String in ids: world.facts.staff[id].life_reason = "等待指定设施" if leader.mode=="manual" else "本区等待娱乐设施"
		return
	var all_present: bool = true
	for index: int in ids.size():
		var task: Dictionary = world.facts.staff[ids[index]].life_task
		task.facility_id = choice.facility_id
		task.floor_id = choice.floor_id
		task.cell = choice.positions[index]
		if not _at_target(world,ids[index],task):
			all_present = false
			task.phase = "local_travel"
			_move_target(world,ids[index],task)
	if not all_present: return
	var reason: String = space.reserve_facility(world,choice.facility_id,ids[0],ids[0],ids.slice(1))
	if not reason.is_empty(): return
	world.facts.staff_life.reservations[choice.facility_id] = {"id":leader.id,"kind":"recreation","staff_ids":ids.duplicate(),"state":"working","remaining_ticks":_ticks(float(content.balance.wellbeing.recreation_seconds)),"positions":choice.positions}
	for id: String in ids:
		var staff: Dictionary = world.facts.staff[id]
		staff.life_task.phase = "recreation"
		staff.block_new_work = true
		staff.recreation_count += 1
		staff.recreation_cooldown_tick = world.sim_tick+_ticks(float(content.balance.wellbeing.recreation_cooldown_seconds))
		staff.last_recreation_tick = world.sim_tick

func _release_previous_seat(world: WorldState, staff_id: String) -> void:
	var task: Dictionary = world.facts.staff[staff_id].life_task
	var id: String = str(task.get("leaving_facility_id",""))
	if id.is_empty() or world.facts.facilities.has(id) and space.overlaps_facility(world,staff_id,id): return
	if world.facts.staff_life.reservations.has(id):
		var reservation: Dictionary = world.facts.staff_life.reservations[id]
		reservation.staff_ids.erase(staff_id)
		if reservation.staff_ids.is_empty(): world.facts.staff_life.reservations.erase(id)
	task.erase("leaving_facility_id")

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
	if _dispatch_view.get("world_id",0)==world.get_instance_id(): return _dispatch_view.handoffs.has(staff_id)
	for handoff: Dictionary in world.facts.get("staff_schedule",{}).get("handoffs",{}).values():
		if handoff.get("new_id","")==staff_id:
			return true
	return false

func _relief_available(world: WorldState, staff_id: String) -> bool:
	var staff: Dictionary = world.facts.staff[staff_id]
	var query: Dictionary = _dispatch_view if _dispatch_view.get("world_id",0)==world.get_instance_id() else _staff_query(world)
	for other_id: String in query.roles.get(staff.role,[]):
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
	var query: Dictionary = _dispatch_view if _dispatch_view.get("world_id",0)==world.get_instance_id() else _staff_query(world)
	for id: String in query.roles.get(staff.role,[]):
		var other: Dictionary = world.facts.staff[id]
		if other.id!=staff_id and other.role==staff.role and other.get("life_task",{}).get("early",false) and other.life_task.phase!="idle":
			return true
	return false

func _ward_responsibility(world: WorldState, staff_id: String) -> bool:
	if _dispatch_view.get("world_id",0)==world.get_instance_id(): return _dispatch_view.ward.has(staff_id)
	for stay: Dictionary in world.facts.ward_stays.values():
		if stay.get("nurse_id","")==staff_id and not stay.get("phase","") in ["release_wait","complete"]:
			return true
	return false

func _patient_occupancy(world: WorldState) -> Dictionary:
	var result: Dictionary = {"blocked":{}}
	for actor: Dictionary in world.facts.actors.values():
		if not world.facts.staff.has(actor.id): result.blocked[str(actor.get("support_facility_id",""))] = true
	for seat: Dictionary in world.facts.get("waiting_life",{}).get("seats",{}).values():
		if not seat.has("public_purpose") or seat.phase=="seated": result.blocked[str(seat.get("facility_id",""))] = true
	for need: Dictionary in world.facts.get("waiting_life",{}).get("needs",{}).values():
		if not need.has("public_purpose") or need.phase in ["using","returning"]: result.blocked[str(need.get("facility_id",""))] = true
	return result

func _patient_occupies(world: WorldState, facility_id: String, view: Dictionary = {}) -> bool:
	if view.is_empty(): view = _patient_occupancy(world)
	return view.blocked.has(facility_id)

func _staff_query(world: WorldState) -> Dictionary:
	var result: Dictionary = {"world_id":world.get_instance_id(),"busy":Development.busy_view(world),"roles":{},"handoffs":{},"ward":{}}
	for id: String in world.ids("staff"):
		var role: String = str(world.facts.staff[id].role)
		if not result.roles.has(role): result.roles[role] = []
		result.roles[role].append(id)
	for handoff: Dictionary in world.facts.get("staff_schedule",{}).get("handoffs",{}).values(): result.handoffs[str(handoff.get("new_id",""))] = true
	for stay: Dictionary in world.facts.ward_stays.values():
		if not stay.get("phase","") in ["release_wait","complete"]: result.ward[str(stay.get("nurse_id",""))] = true
	return result

func _busy(world: WorldState, staff_id: String) -> bool:
	return Development.safe_busy(world,staff_id,_dispatch_view.get("busy",{}))

func _staff_area(world: WorldState, facility: Dictionary) -> bool:
	return _is_staff_room(world.facts.rooms.get(facility.get("room_id",""),{}))

static func _is_staff_room(room: Dictionary) -> bool:
	return str(room.get("kind",room.get("type",""))) in ["rest","staff_garden"]

static func _is_seat(definition_id: String) -> bool:
	return definition_id in REST_SEATS

func _recreation_count(world: WorldState) -> int:
	var participants: Dictionary = {}
	for reservation: Dictionary in world.facts.staff_life.reservations.values():
		if reservation.kind=="recreation":
			for id: String in reservation.staff_ids: participants[id] = true
	for staff: Dictionary in world.facts.staff.values():
		var task: Dictionary = staff.life_task
		if task.get("kind","")=="recreation" and task.phase in ["area_travel","local_wait","local_travel","manual_wait"]: participants[staff.id] = true
	return participants.size()

static func _route_ticks(route: Dictionary) -> float:
	return float(route.get("travel_ticks",route.get("estimated_ticks",route.get("path",[]).size())))

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
