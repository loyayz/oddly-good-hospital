class_name HospitalResearch
extends RefCounted

const JobIndex = preload("res://game/community/research_job_index.gd")
var _job_index: RefCounted = JobIndex.new()

var content: HospitalContent
var space: HospitalSpace
var recruitment: RefCounted
var scheduler: RefCounted
var clinic: HospitalClinic
var _diagnoses: Dictionary = {}
var _due_briefs: Dictionary = {}
var _opening_tick: int = -1
var _worked: Dictionary = {}
var _events: Array[SimEvent] = []

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry

func ensure(world: WorldState) -> void:
	if not world.facts.has("research_jobs"):
		world.facts.research_jobs = {}
	if not world.facts.has("research_progress"):
		world.facts.research_progress = {"opened_tick":-1,"materials":{},"mail":{},"todo":[]}
		# Existing completed diagnostic work is the migration evidence; no visit is
		# created to open the panel or to supply a research topic.
		for visit: Dictionary in world.facts.visits.values():
			if visit.evidence_by_source.has("gp"):
				var occurred: int = int(world.facts.ledger.entries.get(visit.id+":gp",{}).get("tick",world.sim_tick))
				var opened_tick: int = int(world.facts.research_progress.opened_tick)
				world.facts.research_progress.opened_tick = occurred if opened_tick<0 else mini(opened_tick,occurred)
			if _evidence(visit)>=float(content.balance.diagnosis_threshold):
				_collect_diagnosis(world,visit)
		for research_id: String in _diagnoses:
			world.facts.research_progress.materials[research_id] = _diagnoses[research_id]
		_diagnoses.clear()
	for definition: Dictionary in content.catalog.research:
		if definition.disease_ids.is_empty() and not world.facts.research_progress.materials.has(definition.id):
			world.facts.research_progress.materials[definition.id] = {"kind":"initial","tick":0}

func opened(world: WorldState) -> bool:
	return int(world.facts.get("research_progress",{}).get("opened_tick",-1))>=0

func execute(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	ensure(world)
	if not opened(world):
		return _result(world,false,"research_closed","完成第一次初诊后开放研究面板")
	var research_id: String = str(payload.get("research_id",""))
	if content.definition("research",research_id).is_empty():
		return _result(world,false,"research_missing","研究课题不存在")
	var progress: Dictionary = world.facts.research_progress
	match kind:
		"research_request_mail":
			if progress.materials.has(research_id) or progress.mail.has(research_id):
				return _result(world,true,"unchanged","资料已具备或简报已寄出",[research_id])
			progress.mail[research_id] = world.sim_tick+ceili(float(content.balance.research_mail_seconds)/WorldState.TICK_SECONDS)
			return _result(world,true,"applied","",[research_id])
		"research_todo_add":
			if research_id in world.facts.research:
				return _result(world,false,"research_completed","已完成课题不能再次加入待办")
			if not research_id in progress.todo:
				progress.todo.append(research_id)
			return _result(world,true,"applied","",[research_id])
		"research_todo_remove":
			progress.todo.erase(research_id)
			return _result(world,true,"applied","",[research_id])
		"research_todo_move":
			if not research_id in progress.todo:
				return _result(world,false,"todo_missing","课题尚未加入待办")
			var index: int = clampi(int(payload.get("index",0)),0,progress.todo.size()-1)
			progress.todo.erase(research_id)
			progress.todo.insert(index,research_id)
			return _result(world,true,"applied","",[research_id])
		"research_start":
			return _start(world,research_id,payload)
	var job: Dictionary = active_job(world,research_id)
	if job.is_empty():
		# The terminal task, rather than a new command ID, owns refund uniqueness.
		if kind=="research_cancel":
			return _result(world,true,"unchanged","课题当前没有有效任务",[research_id])
		return _result(world,false,"research_job_missing","课题当前没有有效研究任务")
	match kind:
		"research_pause":
			_release(world,job)
			job.paused = true
			job.state = "paused"
			job.reason = "主动暂停，实付款与研究余量保留"
		"research_resume":
			job.paused = false
			job.state = "waiting"
			job.reason = "等待重新检查研究员、排班、桌位和真实路线"
		"research_assign":
			var invalid: String = _selection_reason(world,payload)
			if not invalid.is_empty():
				return _result(world,false,"assignment_invalid",invalid)
			_release(world,job)
			job.preferred_desk_id = str(payload.get("desk_id",""))
			job.preferred_worker_id = str(payload.get("worker_id",""))
			job.state = "paused" if job.paused else "waiting"
			job.reason = "已更新选择，保留原研究进度"
		"research_cancel":
			_release(world,job)
			var numerator: int = maxi(0,int(job.cost)*int(job.remaining_work_milli)-ceili(float(job.cost)*float(job.get("work_fraction_milli",0.0))))
			var refund: int = numerator/int(job.total_work_milli)
			var payment: CommandResult = HospitalLedger.post(world,LedgerEntry.new(job.id,"research_refund",refund))
			if not payment.accepted:
				return payment
			job.refund = refund
			job.state = "cancelled"
			job.finished_tick = world.sim_tick
			job.reason = "已取消，按原实付款退还未完成比例"
		_:
			return _result(world,false,"unknown_command","未知研究操作")
	return _result(world,true,"applied","",[research_id,job.id])

func preview(world: WorldState, research_id: String, desk_id: String = "", community: bool = false, worker_id: String = "") -> Dictionary:
	var definition: Dictionary = content.definition("research",research_id)
	if definition.is_empty():
		return {"ok":false,"reason":"课题不存在"}
	var reasons: Array = []
	if not opened(world):
		reasons.append("完成第一次初诊后开放研究")
	if research_id in world.facts.research:
		reasons.append("课题已完成")
	if not active_job(world,research_id).is_empty():
		reasons.append("课题已有唯一有效任务")
	for required: String in definition.requires:
		if not required in world.facts.research:
			reasons.append("前置研究："+str(content.definition("research",required).name))
	if not world.facts.get("research_progress",{}).get("materials",{}).has(research_id):
		reasons.append("缺少病例资料，可免费请求120模拟秒后到达的简报")
	var creative: bool = world.facts.mode=="creative"
	var cash: int = HospitalLedger.balance(world)
	var community_available: bool = not creative and cash<int(definition.price)
	if community and not community_available:
		reasons.append("现金不足时才可选择社区课题")
	var cost: int = 0 if community or creative else int(definition.price)
	if cash<cost:
		reasons.append("现金不足，可选择零费用、双倍工作量的社区课题")
	var multiplier: int = int(content.balance.community_research_time_multiplier) if community else 1
	var total: int = ceili(float(definition.work_seconds)/WorldState.TICK_SECONDS)*1000*multiplier
	var basis: Dictionary = {"research_id":research_id,"mode":"community" if community else "cash","cost":cost,
		"total_work_milli":total,"rewards":_reward_snapshot(research_id),"content_fingerprint":content.content_fingerprint}
	var selection_reason: String = _selection_reason(world,{"desk_id":desk_id,"worker_id":worker_id})
	if not selection_reason.is_empty():
		reasons.append(selection_reason)
	var pair: Dictionary = _find_pair(world,desk_id,worker_id)
	return {"ok":reasons.is_empty(),"reason":"；".join(reasons),"resource_ready":not pair.is_empty(),
		"resource_reason":"" if not pair.is_empty() else _resource_reason(world,desk_id,worker_id),
		"community_available":community_available,"cost":cost,"total_work_milli":total,"basis":basis,"pair":pair}

func _start(world: WorldState, research_id: String, payload: Dictionary) -> CommandResult:
	var desk_id: String = str(payload.get("desk_id",""))
	var worker_id: String = str(payload.get("worker_id",""))
	var quote: Dictionary = preview(world,research_id,desk_id,bool(payload.get("community",false)),worker_id)
	if not quote.ok:
		return _result(world,false,"research_prerequisite",quote.reason)
	if payload.has("confirmed_quote") and payload.confirmed_quote!=quote.basis:
		return _result(world,false,"material_change","研究方式、费用、工作量或回报已变化，请刷新报价")
	if not quote.resource_ready and not bool(payload.get("allow_waiting",false)):
		return _result(world,false,"research_resources",quote.resource_reason+"；可明确保留已付待办")
	var id: String = "research_%08d" % (int(world.facts.entity_next)+1)
	var paid: CommandResult = HospitalLedger.post(world,LedgerEntry.new(id,"research",-int(quote.cost)))
	if not paid.accepted:
		return paid
	world.new_id("research")
	world.facts.research_jobs[id] = {"id":id,"research_id":research_id,"mode":quote.basis.mode,"cost":int(quote.cost),
		"total_work_milli":int(quote.total_work_milli),"remaining_work_milli":int(quote.total_work_milli),"work_fraction_milli":0.0,
		"rewards":quote.basis.rewards.duplicate(true),"content_fingerprint":quote.basis.content_fingerprint,
		"created_tick":world.sim_tick,"finished_tick":-1,"refund":0,"state":"waiting","paused":false,
		"desk_id":"","worker_id":"","preferred_desk_id":desk_id,"preferred_worker_id":worker_id,
		"reason":"等待共享研究桌队列调度"}
	world.fact_record_changed("research_jobs",id)
	return _result(world,true,"applied","",[research_id,id])

func record_diagnostic_work(world: WorldState, visit: Dictionary, kind: String) -> void:
	if kind=="gp" and not opened(world):
		_opening_tick = world.sim_tick
	if _evidence(visit)>=float(content.balance.diagnosis_threshold):
		_collect_diagnosis(world,visit)

func _collect_diagnosis(world: WorldState, visit: Dictionary) -> void:
	for definition: Dictionary in content.catalog.research:
		if visit.disease_id in definition.disease_ids and not world.facts.research_progress.materials.has(definition.id) and not _diagnoses.has(definition.id):
			_diagnoses[definition.id] = {"kind":"diagnosis","tick":world.sim_tick,"disease_id":visit.disease_id,
				"visit_id":visit.id,"case_name":str(world.facts.actors[visit.actor_id].name)}

func boundaries(world: WorldState) -> void:
	_worked.clear()
	_due_briefs.clear()
	for research_id: String in world.facts.research_progress.mail:
		if world.sim_tick>=int(world.facts.research_progress.mail[research_id]):
			_due_briefs[research_id] = {"kind":"mail","tick":world.sim_tick}
	# Research can stop at every fixed boundary, before the scheduler decides
	# whether a rest or leave must wait for an unsafe work commitment.
	for job_id: String in world.active_operation_ids("research_jobs","",["completed","cancelled"],false,"state"):
		var job: Dictionary = world.facts.research_jobs[job_id]
		if terminal(job) or str(job.worker_id).is_empty():
			continue
		if not _worker_ready(world,job.worker_id,job.id,true):
			_release(world,job)
			job.state = "waiting"
			job.reason = "研究员休息、换班或离职，原研究余量保留"

func dispatch_job(world: WorldState, job: Dictionary, desks: Dictionary = {}) -> void:
	if terminal(job) or job.paused:
		return
	if desks.is_empty(): desks = HospitalClinicalDevelopment.desk_view(world)
	if not desks.has("maintenance"): desks.maintenance = desk_maintenance_view(world)
	if not str(job.desk_id).is_empty() and (not desk_reason(world,job.desk_id,desks.maintenance).is_empty() or not _worker_ready(world,job.worker_id,job.id)):
		_release(world,job)
	if str(job.desk_id).is_empty():
		var pair: Dictionary = _find_pair(world,job.preferred_desk_id,job.preferred_worker_id,job.id,desks)
		if pair.is_empty():
			job.state = "waiting"
			job.reason = _resource_reason(world,job.preferred_desk_id,job.preferred_worker_id)
			return
		if HospitalStaffWellbeing.yield_for_work(world,content,space,[str(pair.worker_id)]):
			job.state = "waiting"
			job.reason = "等待公共娱乐候位者安全返回"
			return
		job.desk_id = pair.desk_id
		job.worker_id = pair.worker_id
		world.facts.staff[job.worker_id].active_job_id = job.id
	var layout: Dictionary = space.facility_layout(world,job.desk_id)
	var cell: Array = HospitalClinicalDevelopment._operator(layout)
	if not space.at(world,job.worker_id,int(layout.floor_id),cell):
		job.state = "travelling"
		job.reason = space.request_move(world,job.worker_id,int(layout.floor_id),cell)
		if world.facts.moves.has(job.worker_id):
			world.facts.moves[job.worker_id].owner_job_id = job.id
		if not job.reason.is_empty() and not world.facts.moves.has(job.worker_id):
			_release(world,job)
		return
	job.state = "working"
	job.reason = ""

func advance(world: WorldState) -> void:
	var maintenance: Dictionary = {}
	for id: String in world.active_operation_ids("research_jobs","",["completed","cancelled"],true,"state"):
		var job: Dictionary = world.facts.research_jobs[id]
		if job.state!="working" or job.paused:
			continue
		if maintenance.is_empty(): maintenance = desk_maintenance_view(world)
		if not desk_reason(world,job.desk_id,maintenance).is_empty() or not _worker_ready(world,job.worker_id,job.id):
			_release(world,job)
			job.state = "waiting"
			job.reason = "实际人员或桌位不可用，研究进度保留"
			continue
		var layout: Dictionary = space.facility_layout(world,job.desk_id)
		if not space.at(world,job.worker_id,int(layout.floor_id),HospitalClinicalDevelopment._operator(layout)):
			job.state = "travelling"
			continue
		var rate: float = 1.0+float(content.balance.staff_practice.speed_per_extra_level)*(int(world.facts.staff[job.worker_id].get("skill",1))-1)
		if recruitment!=null:
			rate = float(recruitment.call("work_rate",world,job.worker_id,"research"))
		var work: float = 1000.0*rate+float(job.get("work_fraction_milli",0.0))
		var amount: int = mini(int(job.remaining_work_milli),floori(work))
		job.work_fraction_milli = work-floorf(work) if amount<int(job.remaining_work_milli) else 0.0
		if amount<=0:
			continue
		job.remaining_work_milli -= amount
		_worked[job.worker_id] = true
		_use_desk(world,job)
		if recruitment!=null:
			var receipt: Dictionary = {"id":job.id+":"+str(world.sim_tick),"qualified_active_research":true}
			recruitment.call("research_work",world,job.worker_id,1,receipt)

func settle(world: WorldState) -> void:
	var progress: Dictionary = world.facts.research_progress
	if _opening_tick>=0 and int(progress.opened_tick)<0:
		progress.opened_tick = _opening_tick
		_events.append(SimEvent.new(world.sim_tick,"research_opened",[],{}))
	_opening_tick = -1
	for research_id: String in _diagnoses:
		if not progress.materials.has(research_id):
			progress.materials[research_id] = _diagnoses[research_id]
			_events.append(SimEvent.new(world.sim_tick,"research_material_acquired",[research_id],_diagnoses[research_id].duplicate(true)))
		progress.mail.erase(research_id)
	for research_id: String in _due_briefs:
		if not progress.materials.has(research_id):
			progress.materials[research_id] = _due_briefs[research_id]
			_events.append(SimEvent.new(world.sim_tick,"research_material_acquired",[research_id],_due_briefs[research_id].duplicate(true)))
		progress.mail.erase(research_id)
	_diagnoses.clear()
	_due_briefs.clear()
	for id: String in world.active_operation_ids("research_jobs","",["completed","cancelled"],true,"state"):
		var job: Dictionary = world.facts.research_jobs[id]
		if terminal(job) or int(job.remaining_work_milli)>0:
			continue
		_release(world,job)
		job.state = "completed"
		job.finished_tick = world.sim_tick
		job.reason = "研究完成，已开放原定义选项；接诊仍需实际人员与空间"
		if not job.research_id in world.facts.research:
			world.facts.research.append(job.research_id)
		progress.todo.erase(job.research_id)
		_events.append(SimEvent.new(world.sim_tick,"research_completed",[job.research_id,job.id],{"rewards":job.rewards.duplicate(true)}))

func suspend_facility(world: WorldState, facility_id: String, reason: String) -> void:
	for job_id: String in world.active_operation_ids("research_jobs","",["completed","cancelled"],false,"state"):
		var job: Dictionary = world.facts.research_jobs[job_id]
		if not terminal(job) and job.desk_id==facility_id:
			_release(world,job)
			job.state = "paused" if job.paused else "waiting"
			job.reason = reason

func active_job(world: WorldState, research_id: String) -> Dictionary:
	var index: Dictionary = _job_index.view(world)
	for id: String in index.groups.get(research_id,[]):
		var job: Dictionary = index.records[id]
		if job.research_id==research_id and not terminal(job):
			return job
	return {}

static func terminal(job: Dictionary) -> bool:
	return job.get("state","") in ["completed","cancelled"]

func worked_staff() -> Dictionary:
	return _worked.duplicate()

func take_events() -> Array[SimEvent]:
	var result: Array[SimEvent] = _events
	_events = []
	return result

func desk_maintenance_view(world: WorldState) -> Dictionary:
	var result: Dictionary = {"blocked":{}}
	for collection: String in ["jobs","upgrades"]:
		for id: String in world.active_operation_ids("maintenance",collection,["completed","cancelled"]):
			var job: Dictionary = world.facts.maintenance[collection][id]
			if not str(job.get("worker_id","")).is_empty() and not job.phase in ["completed","cancelled","inventory"]:
				result.blocked[str(job.get("facility_id",""))] = true
	return result

func desk_reason(world: WorldState, desk_id: String, maintenance: Dictionary = {}) -> String:
	var desk: Dictionary = world.facts.facilities.get(desk_id,{})
	if desk.is_empty() or desk.definition_id!="FUR05":
		return "研究桌尚未实际放置"
	if desk.get("failed",false) or desk.get("pending_failure",false) or desk.get("maintenance_block",false):
		return "研究桌故障或正在维护"
	if HospitalRemodel.blocked(world,desk_id):
		return "研究桌正在等待安全改建"
	if maintenance.is_empty(): maintenance = desk_maintenance_view(world)
	if maintenance.blocked.has(desk_id): return "研究桌已由实际维修工单预约"
	return ""

func _worker_ready(world: WorldState, worker_id: String, own_job: String = "", upcoming_schedule: bool = false) -> bool:
	var staff: Dictionary = world.facts.staff.get(worker_id,{})
	if staff.is_empty() or staff.role!="researcher" or staff.get("departed",false) or not world.facts.actors.has(worker_id):
		return false
	var kind: String = str(staff.get("scheduled_kind","work"))
	if upcoming_schedule and scheduler!=null:
		kind = str(scheduler.call("assignment",world,worker_id,int(scheduler.call("shift_index",world))).kind)
	if kind!="work" or (not upcoming_schedule and (not staff.get("on_shift",false) or staff.get("block_new_work",false))):
		return false
	var leave: Dictionary = staff.get("leave_plan",{})
	if not leave.is_empty() and world.sim_tick>=int(leave.get("requested_start_tick",0)):
		return false
	if staff.get("supply_strike",false) or staff.get("rest_obligation",false) or int(staff.get("sleep_remaining_ticks",0))>0 or int(staff.get("rest_debt_ticks",0))>0 or float(staff.get("energy",0))<=float(content.balance.wellbeing.recreation_max_energy_priority):
		return false
	if int(staff.get("awake_ticks",0))>=ceili(float(content.balance.staff_sleep.awake_limit_seconds)/WorldState.TICK_SECONDS):
		return false
	var location_kind: String = str(world.facts.actors[worker_id].location.kind)
	var travelling: bool = location_kind=="transit" and not own_job.is_empty() and world.facts.moves.get(worker_id,{}).get("owner_job_id","")==own_job
	return str(staff.get("active_job_id","")) in ["",own_job] and HospitalStaffWellbeing.work_window(staff) and (location_kind=="floor" or travelling)

func _find_pair(world: WorldState, preferred_desk: String = "", preferred_worker: String = "", own_job: String = "", desks: Dictionary = {}) -> Dictionary:
	if desks.is_empty(): desks = HospitalClinicalDevelopment.desk_view(world)
	var maintenance: Dictionary = desks.get("maintenance",{})
	if maintenance.is_empty(): maintenance = desk_maintenance_view(world)
	var desk_ids: Array = [preferred_desk] if not preferred_desk.is_empty() else world.facility_ids("FUR05")
	var worker_ids: Array = []
	var workers_ready: bool = false
	for desk_id: String in desk_ids:
		if not desk_reason(world,desk_id,maintenance).is_empty() or HospitalClinicalDevelopment.desk_taken(world,desk_id,own_job,desks):
			continue
		var layout: Dictionary = space.facility_layout(world,desk_id)
		if layout.get("operator_cells",[]).is_empty():
			continue
		if not workers_ready:
			var ids: Array = [preferred_worker] if not preferred_worker.is_empty() else world.ids("staff")
			for id: String in ids:
				if _worker_ready(world,id,own_job) and not world.facts.moves.has(id): worker_ids.append(id)
			workers_ready = true
		for worker_id: String in worker_ids:
			var region: Dictionary = world.facts.staff[worker_id].get("work_region",{})
			var cell: Array = HospitalClinicalDevelopment._operator(layout)
			if region.get("strict",false) and (int(region.get("floor_id",-1))!=int(layout.floor_id) or not _in_region(cell,region)):
				continue
			if space.route(world,worker_id,int(layout.floor_id),cell).ok:
				return {"desk_id":desk_id,"worker_id":worker_id}
	return {}

func _resource_reason(world: WorldState, preferred_desk: String, preferred_worker: String) -> String:
	if not preferred_desk.is_empty():
		var reason: String = desk_reason(world,preferred_desk)
		if not reason.is_empty(): return reason
	var researchers: bool = false
	var desks: bool = false
	for staff: Dictionary in world.facts.staff.values():
		researchers = researchers or (staff.role=="researcher" and not staff.get("departed",false))
	for facility: Dictionary in world.facts.facilities.values():
		desks = desks or facility.definition_id=="FUR05"
	if not researchers:
		return "缺少在职研究员，可前往招聘"
	if not desks:
		return "缺少实际研究桌，可前往建造研究室"
	if not preferred_worker.is_empty() and not _worker_ready(world,preferred_worker):
		return "指定研究员不在可工作班次或正在休息、工作"
	return "等待当班研究员、共享桌位和合法实际路线"

func _selection_reason(world: WorldState, payload: Dictionary) -> String:
	var desk_id: String = str(payload.get("desk_id",""))
	var worker_id: String = str(payload.get("worker_id",""))
	if not desk_id.is_empty() and world.facts.facilities.get(desk_id,world.facts.inventory.get("build_items",{}).get(desk_id,{})).get("definition_id","")!="FUR05":
		return "指定研究桌不存在"
	if not worker_id.is_empty() and (world.facts.staff.get(worker_id,{}).get("role","")!="researcher" or world.facts.staff[worker_id].get("departed",false)):
		return "指定研究员已不在职"
	return ""

func _release(world: WorldState, job: Dictionary) -> void:
	var worker_id: String = str(job.worker_id)
	if world.facts.staff.has(worker_id) and world.facts.staff[worker_id].get("active_job_id","")==job.id:
		world.facts.staff[worker_id].active_job_id = ""
	var movement: Dictionary = world.facts.moves.get(worker_id,{})
	var actor: Dictionary = world.facts.actors.get(worker_id,{})
	if movement.get("owner_job_id","")==job.id and actor.get("location",{}).get("kind","")=="floor" and movement.get("members",[]).is_empty():
		HospitalTransit.cancel_waiting(world,movement)
		world.facts.moves.erase(worker_id)
	job.worker_id = ""
	job.desk_id = ""

func _use_desk(world: WorldState, job: Dictionary) -> void:
	var desk: Dictionary = world.facts.facilities[job.desk_id]
	desk.used = true
	if world.facts.rooms.has(desk.get("room_id","")):
		world.facts.rooms[desk.room_id].used = true
	if not desk.use_receipts.has(job.id):
		desk.use_receipts[job.id] = world.sim_tick
		var definition: Dictionary = content.facility_definition(desk.definition_id)
		for category: Dictionary in content.balance.equipment.classes:
			if category.id==definition.get("equipment_class",""):
				desk.condition = maxf(0.0,float(desk.condition)-float(category.wear_per_use))

func _reward_snapshot(research_id: String) -> Dictionary:
	var result: Dictionary = {"disease_ids":content.definition("research",research_id).disease_ids.duplicate(),"definitions":[]}
	for collection: String in ContentRegistry.FACILITY_COLLECTIONS+["clinical_room_types","build_room_types","diagnostic_modes","treatment_plans"]:
		for definition: Dictionary in content.catalog.get(collection,[]):
			if research_id in definition.get("requires_research",[]):
				var id: String = str(definition.get("id",definition.get("definition_id","")))
				result.definitions.append({"collection":collection,"id":id,"name":str(definition.get("name",id))})
	return result

func trail_research(trail_id: String) -> Array:
	var result: Array = []
	for research_id: String in content.definition("research_trails",trail_id).get("research_ids",[]):
		_expand_dependencies(research_id,result)
	return result

func _expand_dependencies(research_id: String, result: Array) -> void:
	if research_id in result:
		return
	for required: String in content.definition("research",research_id).get("requires",[]):
		_expand_dependencies(required,result)
	result.append(research_id)

func reception_readiness(world: WorldState, research_id: String) -> Array:
	var result: Array = []
	if clinic==null:
		return result
	var unlocked: Dictionary = rewards(world,research_id)
	var disease_ids: Array = unlocked.get("disease_ids",[]).duplicate()
	for definition: Dictionary in unlocked.get("definitions",[]):
		if definition.collection=="treatment_plans":
			var disease_id: String = str(content.definition("treatment_plans",definition.id).get("disease_id",""))
			if not disease_id.is_empty() and not disease_id in disease_ids:
				disease_ids.append(disease_id)
	for disease_id: String in disease_ids:
		for binding: Dictionary in content.catalog.treatment_bindings:
			if binding.disease_id!=disease_id:
				continue
			var ready: Dictionary = clinic.arrival_readiness(world,binding.id)
			result.append({"binding_id":binding.id,"disease_id":disease_id,"species_id":binding.species_id,
				"ok":bool(ready.ok),"reason":str(ready.reason),"plans":ready.get("plans",[])})
	return result

func rewards(world: WorldState, research_id: String) -> Dictionary:
	var index: Dictionary = _job_index.view(world)
	for id: String in index.groups.get(research_id,[]):
		var job: Dictionary = index.records[id]
		if job.research_id==research_id and (job.state=="completed" or not terminal(job)):
			return job.rewards
	return _reward_snapshot(research_id)

static func disease_unlocked(world: WorldState, database: HospitalContent, disease_id: String, index: Dictionary = {}) -> bool:
	if disease_id in database.catalog.get("initial_disease_ids",[]):
		return true
	if index.is_empty(): index = JobIndex.build(world)
	for research_id: String in world.facts.research:
		var definition: Dictionary = database.definition("research",research_id)
		for id: String in index.groups.get(research_id,[]):
			var job: Dictionary = index.records[id]
			if job.research_id==research_id and job.state=="completed":
				definition = job.rewards
				break
		if disease_id in definition.get("disease_ids",[]):
			return true
	return false

static func _evidence(visit: Dictionary) -> float:
	var total: float = 0.0
	for value: Variant in visit.evidence_by_source.values():
		total += float(value)
	return total

static func _in_region(cell: Array, region: Dictionary) -> bool:
	var origin: Array = region.get("origin",[0,0])
	var size: Array = region.get("size",[0,0])
	return float(cell[0])>=float(origin[0]) and float(cell[1])>=float(origin[1]) and float(cell[0])<float(origin[0])+float(size[0]) and float(cell[1])<float(origin[1])+float(size[1])

func validate(world: WorldState) -> String:
	var progress: Variant = world.facts.get("research_progress")
	if not progress is Dictionary or not progress.get("materials") is Dictionary or not progress.get("mail") is Dictionary or not progress.get("todo") is Array or not world.facts.get("research_jobs") is Dictionary:
		return "研究资料、简报、待办或任务集合缺失"
	if not _saved_integer(progress.get("opened_tick"),-1,world.sim_tick):
		return "研究面板开放事实无效"
	for research_id: Variant in progress.materials:
		var source: Variant = progress.materials[research_id]
		if not research_id is String or content.definition("research",research_id).is_empty() or not source is Dictionary or not source.get("kind") in ["initial","diagnosis","mail"] or not _saved_integer(source.get("tick"),0,world.sim_tick):
			return "研究资料来源无效"
		if source.kind=="diagnosis" and (not source.get("visit_id") is String or not source.get("case_name") is String or not source.get("disease_id") in content.definition("research",research_id).disease_ids):
			return "研究确诊资料摘要无效"
	for research_id: Variant in progress.mail:
		if not research_id is String or content.definition("research",research_id).is_empty() or progress.materials.has(research_id) or not _saved_integer(progress.mail[research_id],0):
			return "研究简报请求或到期tick无效"
	var planned: Dictionary = {}
	for research_id: Variant in progress.todo:
		if not research_id is String or content.definition("research",research_id).is_empty() or planned.has(research_id) or research_id in world.facts.research:
			return "研究待办重复、已完成或引用无效"
		planned[research_id] = true
	var completed: Dictionary = {}
	for research_id: Variant in world.facts.research:
		if not research_id is String or content.definition("research",research_id).is_empty() or completed.has(research_id):
			return "研究完成集合重复或引用无效"
		completed[research_id] = true
	var active: Dictionary = {}
	var occupied: Dictionary = {}
	var workers: Dictionary = {}
	var desks: Dictionary = HospitalClinicalDevelopment.training_desk_view(world)
	for id: Variant in world.facts.research_jobs:
		var job: Variant = world.facts.research_jobs[id]
		if not id is String or not job is Dictionary or job.get("id")!=id or not job.get("research_id") is String or content.definition("research",job.research_id).is_empty():
			return "研究任务身份或课题引用无效"
		if not job.get("state") in ["waiting","travelling","working","paused","completed","cancelled"] or not job.get("mode") in ["cash","community"] or not job.get("paused") is bool:
			return "研究任务状态或冻结方式无效"
		if not _saved_integer(job.get("cost"),0) or not _saved_integer(job.get("refund"),0,int(job.get("cost",0))) or not _saved_integer(job.get("total_work_milli"),1) or not _saved_integer(job.get("remaining_work_milli"),0,int(job.get("total_work_milli",0))) or not _saved_integer(job.get("created_tick"),0,world.sim_tick) or not _saved_integer(job.get("finished_tick"),-1,world.sim_tick):
			return "研究任务费用、退款或工时无效"
		if job.has("work_fraction_milli") and (not (job.work_fraction_milli is int or job.work_fraction_milli is float) or not is_finite(float(job.work_fraction_milli)) or float(job.work_fraction_milli)<0.0 or float(job.work_fraction_milli)>=1.0):
			return "研究工作量小数余数无效"
		if job.mode=="community" and int(job.cost)!=0:
			return "社区研究不能持有实付款"
		if not job.get("content_fingerprint") is String or not job.get("rewards") is Dictionary or not job.rewards.get("disease_ids") is Array or not job.rewards.get("definitions") is Array:
			return "研究冻结回报或内容身份无效"
		for disease_id: Variant in job.rewards.disease_ids:
			if not disease_id is String or content.definition("diseases",disease_id).is_empty():
				return "研究冻结病症引用无效"
		for definition: Variant in job.rewards.definitions:
			if not definition is Dictionary or not definition.get("collection") is String or not definition.get("id") is String or not definition.get("name") is String:
				return "研究冻结定义回报无效"
		for field: String in ["worker_id","desk_id","preferred_worker_id","preferred_desk_id","reason"]:
			if not job.get(field) is String:
				return "研究人员或桌位字段无效"
		var payment: Dictionary = world.facts.ledger.entries.get(id+":research",{})
		if int(payment.get("amount",1))!=-int(job.cost) or not payment.get("settled",false):
			return "研究实付款凭据不匹配"
		if terminal(job):
			if not str(job.worker_id).is_empty() or not str(job.desk_id).is_empty() or int(job.finished_tick)<0:
				return "研究终态仍占用人员或桌位"
			if job.state=="completed" and (not completed.has(job.research_id) or int(job.remaining_work_milli)!=0 or world.facts.ledger.entries.has(id+":research_refund")):
				return "研究完成与退款终态互斥关系无效"
			if job.state=="cancelled" and int(world.facts.ledger.entries.get(id+":research_refund",{}).get("amount",-1))!=int(job.refund):
				return "研究取消退款凭据无效"
			continue
		if active.has(job.research_id) or completed.has(job.research_id) or int(job.finished_tick)!=-1 or world.facts.ledger.entries.has(id+":research_refund"):
			return "同一课题存在重复有效任务或冲突终态"
		active[job.research_id] = id
		if job.paused and (job.state!="paused" or not str(job.worker_id).is_empty() or not str(job.desk_id).is_empty()):
			return "主动暂停的研究仍占用工作资源"
		if str(job.worker_id).is_empty()!=str(job.desk_id).is_empty():
			return "研究人员与桌位必须成对预约"
		if not str(job.worker_id).is_empty():
			if workers.has(job.worker_id) or not world.facts.staff.has(job.worker_id) or world.facts.staff[job.worker_id].role!="researcher" or world.facts.staff[job.worker_id].get("active_job_id","")!=id:
				return "研究实际人员缺失或重复分派"
			if occupied.has(job.desk_id) or not world.facts.facilities.has(job.desk_id) or world.facts.facilities[job.desk_id].definition_id!="FUR05" or HospitalClinicalDevelopment.training_desk_taken(world,job.desk_id,"",desks):
				return "研究共享桌位不存在或重复占用"
			workers[job.worker_id] = id
			occupied[job.desk_id] = id
	return ""

static func _saved_integer(value: Variant, minimum: int = 0, maximum: int = 1000000000000) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value)) and float(value)>=minimum and float(value)<=maximum

func _result(world: WorldState, accepted: bool, code: String, reason: String, changed: Array = []) -> CommandResult:
	return CommandResult.new(accepted,code,reason,changed,world.revision)
