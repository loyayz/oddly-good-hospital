class_name HospitalClinicalDevelopment
extends RefCounted

var content: HospitalContent
var space: HospitalSpace
var _worked: Dictionary = {}
var _mentor_blocks: Dictionary = {}

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry

func ensure(world: WorldState) -> void:
	if not world.facts.has("training_jobs"):
		world.facts.training_jobs = {}
	for staff: Dictionary in world.facts.staff.values():
		if not staff.role in ["doctor","nurse"]:
			continue
		var defaults: Dictionary = {"growth_direction":"treatment" if staff.role=="doctor" else "care", "training_job_id":"", "cured_cases":0,
			"completed_courses":{}, "growth_history":[], "growth_goal":{}, "base_prepared":false, "base_task":{}, "title_rate_changed_tick":int(staff.get("hired_tick",0))}
		for key: String in defaults:
			if not staff.has(key):
				staff[key] = defaults[key]

func execute(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	ensure(world)
	var staff_id: String = str(payload.get("staff_id",""))
	if not world.facts.staff.has(staff_id) or not world.facts.staff[staff_id].role in ["doctor","nurse"]:
		return _result(world,false,"staff_missing","请选择在职医护")
	var staff: Dictionary = world.facts.staff[staff_id]
	if kind=="set_growth_direction":
		var track: String = str(payload.get("track",""))
		if not track in tracks(staff):
			return _result(world,false,"invalid_track","只能选择本岗位适用能力")
		staff.growth_direction = track
		staff.growth_goal = {"kind":"course","track":track,"target_level":mini(int(content.balance.doctor_training.max_level),int(staff.abilities[track])+1)}
		return _result(world,true,"applied","",[staff_id])
	if kind=="cancel_training":
		var id: String = str(staff.training_job_id)
		if id.is_empty() or not world.facts.training_jobs.has(id):
			return _result(world,false,"training_missing","当前没有待取消的培养任务")
		_finish_cancel(world,world.facts.training_jobs[id],"cancelled")
		return _result(world,true,"applied","",[staff_id,id])
	if not kind in ["train_staff","promote_staff"]:
		return _result(world,false,"unknown_command","未知培养命令")
	if not str(staff.training_job_id).is_empty():
		return _result(world,false,"training_busy","每名医护同时只能有一项培养任务")
	var quote: Dictionary = preview(world,staff_id,str(payload.get("track",staff.growth_direction)),"promotion" if kind=="promote_staff" else "course")
	if not quote.ok:
		return _result(world,false,"prerequisite",quote.reason)
	if payload.has("confirmed_quote") and payload.confirmed_quote!=quote.basis:
		return _result(world,false,"material_change","能力、研究或费用已变化，请刷新培养预览")
	var desk_id: String = str(payload.get("desk_id",""))
	if not desk_id.is_empty() and (not world.facts.facilities.has(desk_id) or world.facts.facilities[desk_id].definition_id!="FUR05"):
		return _result(world,false,"desk_missing","指定研究桌已不存在")
	if desk_id.is_empty() and _desks(world).is_empty() and not bool(payload.get("queue_without_desk",false)):
		return _result(world,false,"desk_missing","没有研究桌，可明确保留已付培养待办")
	var mentor_id: String = str(payload.get("mentor_id",""))
	if not mentor_id.is_empty() and not _mentor_qualified(world,staff_id,mentor_id,str(quote.track)):
		return _result(world,false,"mentor_unqualified","导师岗位、职称或能力差距不满足条件")
	var job_id: String = "training_%08d" % (int(world.facts.entity_next)+1)
	var paid: CommandResult = HospitalLedger.post(world,LedgerEntry.new(job_id,"training",-int(quote.cost)))
	if not paid.accepted:
		return paid
	world.new_id("training")
	var total: int = int(quote.work_ticks)*1000
	world.facts.training_jobs[job_id] = {"id":job_id,"staff_id":staff_id,"kind":quote.kind,"track":quote.track,
		"target_level":quote.target_level,"target_title_id":quote.target_title_id,"cost":quote.cost,"total_work_milli":total,
		"remaining_work_milli":total,"state":"waiting","reason":"等待培训班、研究桌与安全交接","desk_id":"","preferred_desk_id":desk_id,
		"mentor_id":mentor_id,"created_tick":world.sim_tick,"finished_tick":-1,"refund":0,"basis":quote.basis}
	staff.training_job_id = job_id
	staff.growth_goal = {"kind":quote.kind,"track":quote.track,"target_level":quote.target_level,"target_title_id":quote.target_title_id}
	return _result(world,true,"applied","",[staff_id,job_id])

func preview(world: WorldState, staff_id: String, track: String = "", kind: String = "course") -> Dictionary:
	if not world.facts.staff.has(staff_id):
		return {"ok":false,"reason":"医护不存在"}
	var staff: Dictionary = world.facts.staff[staff_id]
	if not staff.role in ["doctor","nurse"] or (kind=="course" and not track in tracks(staff)):
		return {"ok":false,"reason":"本岗位不能学习该能力"}
	var target: int = int(staff.abilities.get(track,0))+1
	var cost: int = 0
	var seconds: float = 0.0
	var title_id: String = ""
	if kind=="promotion":
		if staff.role!="doctor":
			return {"ok":false,"reason":"护士没有医生职称评估"}
		var title: Dictionary = _next_title(staff)
		if title.is_empty():
			return {"ok":false,"reason":"已达到最高职称"}
		var rules: Dictionary = title.promotion
		for research_id: String in rules.requires_research:
			if not research_id in world.facts.research:
				return {"ok":false,"reason":"职称评估所需研究尚未完成"}
		var primary: String = str(staff.get("growth_direction","treatment"))
		var secondary: int = 0
		for other: String in tracks(staff):
			if other!=primary:
				secondary = maxi(secondary,int(staff.abilities[other]))
		if int(staff.get("cured_cases",0))<int(rules.cured_case_count) or int(staff.abilities[primary])<int(rules.primary_level) or int(staff.abilities.diagnosis)<int(rules.diagnosis_level) or secondary<int(rules.secondary_level):
			return {"ok":false,"reason":"治愈病例、主方向、诊断或第二方向尚未达标"}
		title_id = title.id
		track = primary
		for row: Dictionary in content.balance.doctor_pay:
			if row.title_id==title_id:
				cost = int(row.promotion_cost)
				seconds = float(row.promotion_seconds)
	else:
		if target>int(content.balance.doctor_training.max_level):
			return {"ok":false,"reason":"该能力已达到最高等级"}
		if target>=2 and not str(content.balance.doctor_training.advanced_research) in world.facts.research:
			return {"ok":false,"reason":"进阶能力需要完成医护培养研究"}
		if track=="surgery" and target==1 and not str(content.balance.doctor_training.surgical_research) in world.facts.research:
			return {"ok":false,"reason":"手术入门需要完成手术研究"}
		for row: Dictionary in content.balance.doctor_training.courses:
			if int(row.target_level)==target:
				if int(staff.practice.get(track,0))<int(row.practice_required):
					return {"ok":false,"reason":"该方向真实实践次数不足"}
				cost = int(row.cost)
				seconds = float(row.work_seconds)
		if staff.role=="nurse" and track=="surgery" and target==1:
			cost = int(content.balance.doctor_training.nurse_or_cost)
			seconds = float(content.balance.doctor_training.nurse_or_seconds)
		if str(content.balance.doctor_training.discount_research) in world.facts.research:
			cost = ceili(cost*float(content.balance.doctor_training.discount_multiplier))
			seconds = ceilf(seconds*float(content.balance.doctor_training.discount_multiplier))
		for talent: Dictionary in content.catalog.get("staff_talents",[]):
			if talent.species_id==world.facts.actors[staff_id].species_id and talent.handler_id=="training_work" and talent.action=="course":
				seconds = ceilf(seconds*float(talent.value))
	var basis: Dictionary = {"staff_id":staff_id,"kind":kind,"track":track,"abilities":staff.abilities.duplicate(true),"practice":staff.practice.duplicate(true),
		"title_id":staff.title_id,"cured_cases":int(staff.get("cured_cases",0)),"target_level":target,"target_title_id":title_id,"cost":cost,"work_ticks":ceili(seconds/WorldState.TICK_SECONDS)}
	return {"ok":true,"reason":"","kind":kind,"track":track,"target_level":target,"target_title_id":title_id,"cost":cost,"work_ticks":basis.work_ticks,"basis":basis}

func dispatch(world: WorldState) -> void:
	ensure(world)
	_worked.clear()
	_mentor_blocks.clear()
	for id: String in world.ids("training_jobs"):
		var job: Dictionary = world.facts.training_jobs[id]
		if terminal(job):
			continue
		var staff: Dictionary = world.facts.staff[job.staff_id]
		if not _training_window(world,staff) or safe_busy(world,job.staff_id) or staff.get("life_task",{}).get("phase","idle")!="idle" or not staff.get("base_task",{}).is_empty():
			_pause(world,job,"等待培训班或当前安全任务结束")
			continue
		staff.block_new_work = true
		if str(job.desk_id).is_empty():
			for desk_id: String in _desks(world):
				if not str(job.preferred_desk_id).is_empty() and desk_id!=str(job.preferred_desk_id):
					continue
				if _desk_taken(world,desk_id,job.id):
					continue
				var layout: Dictionary = space.facility_layout(world,desk_id)
				var route: Dictionary = space.route(world,job.staff_id,int(layout.floor_id),_operator(layout))
				if route.ok:
					job.desk_id = desk_id
					break
		if str(job.desk_id).is_empty():
			job.reason = "等待可达的空闲研究桌"
			continue
		if not world.facts.facilities.has(job.desk_id) or world.facts.facilities[job.desk_id].failed:
			_pause(world,job,"研究桌不可用，培养余量保留")
			continue
		var desk: Dictionary = space.facility_layout(world,job.desk_id)
		if not space.at(world,job.staff_id,int(desk.floor_id),_operator(desk)):
			job.erase("work_segment")
			job.state = "travelling"
			job.reason = space.request_move(world,job.staff_id,int(desk.floor_id),_operator(desk))
			continue
		job.state = "working"
		job.reason = ""
		if not str(job.mentor_id).is_empty() and _mentor_available(world,job):
			var adjacent: Array = [int(_operator(desk)[0])+space.clearance(world.facts.actors[job.staff_id]),int(_operator(desk)[1])]
			if not space.route(world,job.mentor_id,int(desk.floor_id),adjacent).ok:
				continue
			_mentor_blocks[job.mentor_id] = job.id
			world.facts.staff[job.mentor_id].block_new_work = true
			if not space.at(world,job.mentor_id,int(desk.floor_id),adjacent):
				space.request_move(world,job.mentor_id,int(desk.floor_id),adjacent)
	for staff_id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[staff_id]
		if not staff.role in ["doctor","nurse"] or _mentor_blocks.has(staff_id) or (not str(staff.get("training_job_id","")).is_empty() and _training_window(world,staff)):
			continue
		_prepare_base(world,staff_id,staff)

func advance(world: WorldState) -> void:
	for job: Dictionary in world.facts.get("training_jobs",{}).values():
		if job.state!="working" or not world.facts.facilities.has(job.desk_id) or world.facts.facilities[job.desk_id].failed:
			continue
		if not _training_window(world,world.facts.staff[job.staff_id]) or safe_busy(world,job.staff_id) or world.facts.staff[job.staff_id].get("life_task",{}).get("phase","idle")!="idle" or not world.facts.staff[job.staff_id].get("base_task",{}).is_empty():
			_pause(world,job,"等待培训班或当前安全任务结束")
			continue
		var mentor_present: bool = false
		var student_desk: Dictionary = space.facility_layout(world,job.desk_id)
		if not space.at(world,job.staff_id,int(student_desk.floor_id),_operator(student_desk)):
			_pause(world,job,"学员离开研究桌，培养余量保留")
			continue
		if _mentor_available(world,job):
			var desk: Dictionary = space.facility_layout(world,job.desk_id)
			var adjacent: Array = [int(_operator(desk)[0])+space.clearance(world.facts.actors[job.staff_id]),int(_operator(desk)[1])]
			if space.at(world,job.mentor_id,int(desk.floor_id),adjacent) and space.route(world,job.mentor_id,int(desk.floor_id),adjacent).ok:
				mentor_present = true
				_worked[job.mentor_id] = true
		var segment_mentor: String = str(job.mentor_id) if mentor_present else ""
		if not job.has("work_segment") or str(job.work_segment.mentor_id)!=segment_mentor:
			var solo: float = 1.0/_fatigue_multiplier(world.facts.staff[job.staff_id])
			var rate: float = solo
			if mentor_present:
				rate += 0.25*minf(solo,1.0/_fatigue_multiplier(world.facts.staff[job.mentor_id]))
			job.work_segment = {"mentor_id":segment_mentor,"rate_milli":1000.0*rate}
		var work: float = float(job.work_segment.rate_milli)+float(job.get("work_fraction_milli",0.0))
		var whole: int = floori(work)
		job.work_fraction_milli = work-float(whole)
		job.remaining_work_milli = maxi(0,int(job.remaining_work_milli)-whole)
		_worked[job.staff_id] = true
	for staff_id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[staff_id]
		var task: Dictionary = staff.get("base_task",{})
		if task.get("phase","")!="working":
			continue
		task.remaining_ticks = maxi(0,int(task.remaining_ticks)-1)
		_worked[staff_id] = true
		if int(task.remaining_ticks)==0:
			staff.base_prepared = true
			staff.base_task = {}
			staff.block_new_work = false

func settle(world: WorldState) -> void:
	ensure(world)
	# Courses that truly completed this tick precede practice-based growth.
	for job: Dictionary in world.facts.training_jobs.values():
		if terminal(job) or int(job.remaining_work_milli)>0:
			continue
		var staff: Dictionary = world.facts.staff[job.staff_id]
		if job.kind=="promotion":
			staff.title_id = job.target_title_id
			staff.title_rate_changed_tick = world.sim_tick
			staff.promoted_title = true
		else:
			staff.abilities[job.track] = maxi(int(staff.abilities[job.track]),int(job.target_level))
			staff.completed_courses[job.id] = {"track":job.track,"target_level":job.target_level,"tick":world.sim_tick}
		_finish(world,job,"completed")
		_history(staff,{"source":job.kind,"job_id":job.id,"track":job.track,"level":job.target_level,"title_id":job.target_title_id,"tick":world.sim_tick})
	for staff: Dictionary in world.facts.staff.values():
		if not staff.role in ["doctor","nurse"]:
			continue
		if str(content.balance.doctor_training.advanced_research) in world.facts.research:
			for track: String in tracks(staff):
				if int(staff.abilities[track])==0:
					continue
				var before: int = int(staff.abilities[track])
				for key: String in content.balance.clinical_ability_growth.auto_level_thresholds:
					if int(staff.practice.get(track,0))>=int(content.balance.clinical_ability_growth.auto_level_thresholds[key]):
						staff.abilities[track] = maxi(int(key),int(staff.abilities[track]))
				if before!=int(staff.abilities[track]):
					_history(staff,{"source":"practice","track":track,"level":int(staff.abilities[track]),"tick":world.sim_tick})
		var job_id: String = str(staff.training_job_id)
		if not job_id.is_empty():
			var job: Dictionary = world.facts.training_jobs[job_id]
			if job.kind=="course" and int(staff.abilities[job.track])>=int(job.target_level):
				_finish_cancel(world,job,"superseded")
	_settle_cases(world)

func worked_staff() -> Dictionary:
	return _worked.duplicate()

func validate(world: WorldState) -> String:
	if not world.facts.get("training_jobs") is Dictionary or not world.facts.get("staff") is Dictionary or not world.facts.get("facilities") is Dictionary:
		return "培养任务集合缺失"
	var active: Dictionary = {}
	var desks: Dictionary = {}
	for id: Variant in world.facts.training_jobs:
		var job: Variant = world.facts.training_jobs[id]
		if not job is Dictionary or not job.get("id") is String or job.get("id")!=id or not job.get("staff_id") is String or not world.facts.staff.has(job.staff_id):
			return "培养任务身份或学员无效"
		if not world.facts.staff[job.staff_id] is Dictionary or not job.get("desk_id") is String or not job.get("mentor_id","") is String:
			return "培养学员、导师或研究桌字段类型无效"
		if not job.get("remaining_work_milli") is int or not job.get("total_work_milli") is int or int(job.remaining_work_milli)<0 or int(job.remaining_work_milli)>int(job.total_work_milli) or int(job.total_work_milli)<=0:
			return "培养工时余量无效"
		if job.has("work_fraction_milli") and (not (job.work_fraction_milli is float or job.work_fraction_milli is int) or not is_finite(float(job.work_fraction_milli)) or float(job.work_fraction_milli)<0.0 or float(job.work_fraction_milli)>=1.0):
			return "培养工时小数无效"
		if job.has("work_segment"):
			var segment: Variant = job.work_segment
			if not segment is Dictionary or not segment.get("mentor_id") is String or not (segment.get("rate_milli") is float or segment.get("rate_milli") is int) or not is_finite(float(segment.rate_milli)) or float(segment.rate_milli)<=0.0 or float(segment.rate_milli)>1250.0:
				return "培养工作段无效"
			if not str(segment.mentor_id).is_empty() and (segment.mentor_id!=job.get("mentor_id","") or not world.facts.staff.has(segment.mentor_id)):
				return "培养工作段导师引用无效"
		if not job.get("state") in ["waiting","paused","travelling","working","completed","cancelled","superseded"] or not job.get("cost") is int or int(job.cost)<0:
			return "培养终态或费用无效"
		if not str(job.get("mentor_id","")).is_empty() and not world.facts.staff.has(job.mentor_id):
			return "培养导师引用缺失"
		if not terminal(job):
			if active.has(job.staff_id) or world.facts.staff[job.staff_id].get("training_job_id")!=id:
				return "同一学员存在重复活动课程"
			active[job.staff_id] = id
			if not str(job.desk_id).is_empty():
				if desks.has(job.desk_id) or not world.facts.facilities.has(job.desk_id) or not world.facts.facilities[job.desk_id] is Dictionary or world.facts.facilities[job.desk_id].get("definition_id","")!="FUR05":
					return "培养研究桌不存在或重复占用"
				desks[job.desk_id] = id
	for staff_value: Variant in world.facts.staff.values():
		if not staff_value is Dictionary:
			return "医护成长员工记录无效"
		var staff: Dictionary = staff_value
		if staff.role in ["doctor","nurse"]:
			if not staff.get("id") is String or not staff.get("growth_direction","") is String or not staff.get("growth_direction","") in tracks(staff) or not staff.get("completed_courses") is Dictionary or not staff.get("growth_history") is Array or not staff.get("cured_cases") is int or int(staff.cured_cases)<0 or not staff.get("training_job_id","") is String:
				return "医护成长事实无效"
			if not str(staff.get("training_job_id","")).is_empty() and not active.has(staff.id):
				return "学员活动培养引用无效"
	return ""

static func tracks(staff: Dictionary) -> Array:
	return ["diagnosis","treatment","surgery"] if staff.role=="doctor" else ["diagnosis","care","surgery"]

static func terminal(job: Dictionary) -> bool:
	return str(job.get("state","")) in ["completed","cancelled","superseded"]

static func safe_busy(world: WorldState, staff_id: String) -> bool:
	if world.facts.staff.get(staff_id,{}).has("clinical_release"):
		return true
	for session: Dictionary in world.facts.sessions.values():
		if staff_id in session.staff_ids:
			return true
	for preparation: Dictionary in world.facts.preparations.values():
		if staff_id in preparation.staff_ids:
			return true
	for stay: Dictionary in world.facts.ward_stays.values():
		if stay.get("phase","")=="transfer" and stay.get("escort_id","")==staff_id:
			return true
	for handoff: Dictionary in world.facts.get("staff_schedule",{}).get("handoffs",{}).values():
		if handoff.get("new_id","")==staff_id:
			return true
	return not str(world.facts.staff.get(staff_id,{}).get("active_job_id","")).is_empty()

func _prepare_base(world: WorldState, staff_id: String, staff: Dictionary) -> void:
	if not staff.get("on_shift",true) or staff.get("life_task",{}).get("phase","idle")!="idle":
		staff.base_prepared = false
		staff.base_task = {}
		return
	if staff.get("base_prepared",false) or safe_busy(world,staff_id) or world.facts.moves.has(staff_id):
		return
	var task: Dictionary = staff.base_task
	if task.is_empty():
		var wanted: String = str(content.balance.staff_work_bases.doctor_equipment_id if staff.role=="doctor" else content.balance.staff_work_bases.nurse_equipment_id)
		for id: String in world.ids("facilities"):
			var facility: Dictionary = world.facts.facilities[id]
			if facility.definition_id!=wanted or facility.failed or _base_taken(world,id,staff_id):
				continue
			var layout: Dictionary = space.facility_layout(world,id)
			if not space.route(world,staff_id,int(layout.floor_id),_operator(layout)).ok:
				continue
			task = {"phase":"travel","facility_id":id,"remaining_ticks":ceili(float(content.balance.staff_work_bases.preparation_seconds)/WorldState.TICK_SECONDS)}
			staff.base_task = task
			break
		if task.is_empty():
			staff.growth_reason = "缺少可达的医生办公桌或护士工作台"
			return
	staff.block_new_work = true
	if not world.facts.facilities.has(task.facility_id) or world.facts.facilities[task.facility_id].failed:
		staff.base_task = {}
		return
	var base: Dictionary = space.facility_layout(world,task.facility_id)
	if space.at(world,staff_id,int(base.floor_id),_operator(base)):
		task.phase = "working"
		staff.growth_reason = "正在整理本段工作记录"
	else:
		staff.growth_reason = space.request_move(world,staff_id,int(base.floor_id),_operator(base))

func _training_window(world: WorldState, staff: Dictionary) -> bool:
	var leave: Dictionary = staff.get("leave_plan",{})
	var leave_due: bool = not leave.is_empty() and world.sim_tick>=int(leave.get("requested_start_tick",0))
	return bool(staff.get("on_shift",false)) and staff.get("scheduled_kind","")=="training" and not staff.get("supply_strike",false) and float(staff.get("energy",0))>float(content.balance.wellbeing.recreation_max_energy_priority) and (staff.role!="doctor" or float(staff.get("fatigue",0))<float(content.balance.wellbeing.fatigue_stop_new_work)) and not staff.get("rest_obligation",false) and int(staff.get("sleep_remaining_ticks",0))==0 and int(staff.get("rest_debt_ticks",0))==0 and not leave_due

func _fatigue_multiplier(staff: Dictionary) -> float:
	return 1.0+float(content.balance.wellbeing.fatigue_work_multiplier_per_point)*float(staff.get("fatigue",0)) if staff.role=="doctor" else 1.0

func _desks(world: WorldState) -> Array:
	var result: Array = []
	for id: String in world.ids("facilities"):
		if world.facts.facilities[id].definition_id=="FUR05" and not world.facts.facilities[id].failed:
			result.append(id)
	return result

func _desk_taken(world: WorldState, desk_id: String, except_id: String) -> bool:
	for job: Dictionary in world.facts.training_jobs.values():
		if job.id!=except_id and not terminal(job) and job.desk_id==desk_id:
			return true
	for session: Dictionary in world.facts.sessions.values():
		if session.get("facility_id","")==desk_id:
			return true
	for job: Dictionary in world.facts.get("research_jobs",{}).values():
		if job.get("desk_id","")==desk_id and not str(job.get("state","")) in ["completed","cancelled","paused"]:
			return true
	return false

func _base_taken(world: WorldState, facility_id: String, except_id: String) -> bool:
	for staff: Dictionary in world.facts.staff.values():
		if staff.id!=except_id and staff.get("base_task",{}).get("facility_id","")==facility_id:
			return true
	return false

func _mentor_qualified(world: WorldState, student_id: String, mentor_id: String, track: String) -> bool:
	if mentor_id==student_id or not world.facts.staff.has(mentor_id):
		return false
	var student: Dictionary = world.facts.staff[student_id]
	var mentor: Dictionary = world.facts.staff[mentor_id]
	if mentor.role!=student.role or int(mentor.abilities.get(track,0))-int(student.abilities.get(track,0))<int(content.balance.doctor_training.mentor_level_gap):
		return false
	return mentor.role!="doctor" or int(content.definition("doctor_titles",mentor.title_id).get("rank",-1))>=int(content.definition("doctor_titles",str(content.balance.doctor_training.mentor_min_title_id)).rank)

func _mentor_available(world: WorldState, job: Dictionary) -> bool:
	if str(job.get("mentor_id","")).is_empty() or not _mentor_qualified(world,job.staff_id,job.mentor_id,job.track):
		return false
	var mentor: Dictionary = world.facts.staff[job.mentor_id]
	if mentor.get("block_new_work",false) and _mentor_blocks.get(job.mentor_id,"")!=job.id:
		return false
	if _mentor_blocks.has(job.mentor_id) and _mentor_blocks[job.mentor_id]!=job.id:
		return false
	return _training_window(world,mentor) and not safe_busy(world,job.mentor_id) and str(mentor.get("training_job_id","")).is_empty() and mentor.get("life_task",{}).get("phase","idle")=="idle" and mentor.get("base_task",{}).is_empty()

func _next_title(staff: Dictionary) -> Dictionary:
	for title: Dictionary in content.catalog.doctor_titles:
		if title.get("promotion",{}) is Dictionary and title.get("promotion",{}).get("prior_title_id","")==staff.title_id:
			return title
	return {}

func _pause(_world: WorldState, job: Dictionary, reason: String) -> void:
	job.state = "paused"
	job.reason = reason
	job.desk_id = ""
	job.erase("work_segment")

func _finish(world: WorldState, job: Dictionary, state: String) -> void:
	job.state = state
	job.finished_tick = world.sim_tick
	job.desk_id = ""
	var staff: Dictionary = world.facts.staff[job.staff_id]
	staff.training_job_id = ""
	staff.base_prepared = false
	staff.block_new_work = false
	job.reason = "实操已掌握，退还未完成课程" if state=="superseded" else ("已取消并退还剩余学费" if state=="cancelled" else "培养完成")

func _finish_cancel(world: WorldState, job: Dictionary, state: String) -> void:
	if terminal(job):
		return
	var numerator: int = maxi(0,int(job.cost)*int(job.remaining_work_milli)-ceili(float(job.cost)*float(job.get("work_fraction_milli",0.0))))
	var refund: int = numerator/int(job.total_work_milli)
	HospitalLedger.post(world,LedgerEntry.new(job.id,"training_refund",refund))
	job.refund = refund
	_finish(world,job,state)

func _history(staff: Dictionary, record: Dictionary) -> void:
	staff.growth_history.append(record)
	while staff.growth_history.size()>int(content.balance.ratings.staff_job_limit):
		staff.growth_history.pop_front()

func _settle_cases(world: WorldState) -> void:
	for visit: Dictionary in world.facts.visits.values():
		if visit.phase!="departed" or visit.get("final_result","")!="cured" or visit.get("development_case_settled",false):
			continue
		var participants: Dictionary = visit.get("clinical_participants",{}).duplicate()
		for attempt_id: String in visit.attempt_ids:
			for staff_id: String in world.facts.attempts[attempt_id].staff_ids:
				participants[staff_id] = true
		for staff_id: String in participants:
			if world.facts.staff.has(staff_id) and world.facts.staff[staff_id].role=="doctor":
				world.facts.staff[staff_id].cured_cases += 1
		visit.development_case_settled = true

static func _operator(layout: Dictionary) -> Array:
	return layout.operator_cells[0] if not layout.get("operator_cells",[]).is_empty() else layout.patient_cell

func _result(world: WorldState, accepted: bool, code: String, reason: String, changed: Array = []) -> CommandResult:
	return CommandResult.new(accepted,code,reason,changed,world.revision)
