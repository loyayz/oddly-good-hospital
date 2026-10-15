class_name HospitalMaintenance
extends RefCounted

var content: HospitalContent
var space: HospitalSpace
var finance: RefCounted
var recruitment: RefCounted
var _worked: Dictionary = {}

func _init(database: HospitalContent, geometry: HospitalSpace) -> void:
	content = database
	space = geometry

func ensure(world: WorldState) -> void:
	if not world.facts.has("maintenance"):
		world.facts.maintenance = {"jobs":{},"upgrades":{},"receipts":{},"policy_id":content.balance.maintenance_dispatch.default_policy_id,
			"pinned_job_id":"","next_scan_tick":(world.sim_tick/(int(content.balance.equipment.scan_seconds)*10)+1)*int(content.balance.equipment.scan_seconds)*10}
	for item: Dictionary in _equipment(world).values():
		if not item.has("condition"):
			item.condition = float(content.balance.equipment.restored_condition)
		if not item.has("failed"):
			item.failed = false
		if not item.has("pending_failure"):
			item.pending_failure = false
		if not item.has("last_wear_day"):
			item.last_wear_day = world.sim_tick/WorldState.TICKS_PER_DAY
		if not item.has("repair_grace_until"):
			item.repair_grace_until = 0
		if not item.has("maintenance_order_id"):
			item.maintenance_order_id = ""

func worked_staff() -> Dictionary:
	return _worked.duplicate()

func _equipment(world: WorldState) -> Dictionary:
	var result: Dictionary = {}
	for collection: String in ["facilities","connectors"]:
		for id: String in world.ids(collection):
			var item: Dictionary = world.facts[collection][id]
			if item.definition_id in content.balance.equipment.maintained_definition_ids:
				result[id] = item
	for id: String in world.facts.inventory.get("build_items",{}):
		var item: Dictionary = world.facts.inventory.build_items[id]
		if item.definition_id in content.balance.equipment.maintained_definition_ids:
			result[id] = item
	return result

func _class(item: Dictionary) -> Dictionary:
	var definition: Dictionary = content.facility_definition(str(item.definition_id))
	if definition.is_empty():
		definition = content.definition("vertical_connectors",str(item.definition_id))
	for record: Dictionary in content.balance.equipment.classes:
		if record.id == definition.get("equipment_class",""):
			return record
	return {}

func boundaries(world: WorldState) -> void:
	ensure(world)
	var equipment: Dictionary = _equipment(world)
	var day: int = world.sim_tick/WorldState.TICKS_PER_DAY
	for id: String in equipment:
		var item: Dictionary = equipment[id]
		if _in_inventory(world,id):
			continue
		var category: Dictionary = _class(item)
		if category.is_empty():
			continue
		if day>int(item.last_wear_day):
			item.condition = maxf(0.0,float(item.condition)-float(category.wear_per_day)*(day-int(item.last_wear_day)))
			item.last_wear_day = day
		if world.facts.connectors.has(id):
			var phase: String = str(item.phase)
			if phase in ["riding","empty_riding"] and item.get("maintenance_last_phase","")!=phase:
				item.condition = maxf(0.0,float(item.condition)-float(category.wear_per_use))
			item.maintenance_last_phase = phase
		if item.pending_failure and _safe_free(world,id):
			item.failed = true
			item.pending_failure = false
	var state: Dictionary = world.facts.maintenance
	if world.sim_tick>=int(state.next_scan_tick):
		state.next_scan_tick = world.sim_tick+int(content.balance.equipment.scan_seconds)*10
		for id: String in equipment:
			var item: Dictionary = equipment[id]
			if item.failed or item.pending_failure or world.sim_tick<int(item.repair_grace_until) or _in_inventory(world,id):
				continue
			var category: Dictionary = _class(item)
			if category.is_empty():
				continue
			var multiplier: int = 1
			for index: int in content.balance.equipment.risk_condition_bounds.size():
				if float(item.condition)>=float(content.balance.equipment.risk_condition_bounds[index]):
					multiplier = int(content.balance.equipment.risk_multipliers[index])
					break
			item.last_fault_roll_tick = world.sim_tick
			if world.draw("equipment",10000)<int(category.base_failure_bp)*multiplier:
				item.pending_failure = true
				if _safe_free(world,id):
					item.failed = true
					item.pending_failure = false
	var threshold: float = float(content.balance.maintenance_dispatch.auto_thresholds[state.policy_id])
	for id: String in equipment:
		var item: Dictionary = equipment[id]
		if _in_inventory(world,id):
			continue
		if item.failed or item.pending_failure:
			var job: Dictionary = _ensure_job(world,item,"repair",true)
			if job.kind=="maintenance":
				_promote(world,job,item)
		elif float(item.condition)<=threshold:
			_ensure_job(world,item,"maintenance",true)
		elif not str(item.maintenance_order_id).is_empty() and state.jobs.has(item.maintenance_order_id):
			var job: Dictionary = state.jobs[item.maintenance_order_id]
			if job.kind=="maintenance" and not job.started and job.automatic:
				_release(world,job)
				job.phase = "cancelled"
				item.maintenance_order_id = ""
	for job: Dictionary in state.jobs.values():
		if not equipment.has(job.facility_id) and job.phase not in ["completed","cancelled"]:
			_release(world,job)
			job.phase = "cancelled"

func _ensure_job(world: WorldState, item: Dictionary, kind: String, automatic: bool) -> Dictionary:
	var jobs: Dictionary = world.facts.maintenance.jobs
	var original: Dictionary = jobs.get(str(item.get("maintenance_order_id","")),{})
	if not original.is_empty() and original.phase not in ["completed","cancelled"]:
		return original
	var category: Dictionary = _class(item)
	var seconds: int = int(category.repair_seconds if kind=="repair" else category.maintenance_seconds)
	var id: String = world.new_id("maintenance")
	var job: Dictionary = {"id":id,"facility_id":item.id,"kind":kind,"automatic":automatic,"created_tick":world.sim_tick,
		"phase":"queued","started":false,"paused":false,"total_milli":seconds*1000,"completed_milli":0,"remaining_milli":seconds*1000,
		"paid_parts":0,"worker_id":"","work_cell":[],"contributions":{},"reason":"","worker_rate":1.0,"frozen_class":{}}
	jobs[id] = job
	item.maintenance_order_id = id
	return job

func _promote(world: WorldState, job: Dictionary, item: Dictionary) -> void:
	var category: Dictionary = job.frozen_class if job.started else _class(item)
	job.kind = "repair"
	job.total_milli = int(category.repair_seconds)*1000
	job.remaining_milli = maxi(0,int(job.total_milli)-int(job.completed_milli))
	job.repair_difference_due = maxi(0,int(category.repair_parts)-int(job.paid_parts))
	job.phase = "queued"
	_release(world,job)

func upgrade_quote(world: WorldState, payload: Dictionary) -> Dictionary:
	var id: String = str(payload.get("facility_id",""))
	var item: Dictionary = world.facts.facilities.get(id,{})
	var reason: String = ""
	var stages: Array = []
	var total: int = 0
	if item.is_empty() or not _upgradable(item):
		reason = "该设施没有医疗主体升级"
	elif item.get("borrowed",false) or item.get("ownership","")=="borrowed":
		reason = "借用品不能升级"
	elif _active_upgrade(world,id)!="":
		reason = "设备已有未完成升级"
	elif item.get("remodel_id","")!="" or item.get("location","floor")=="inventory":
		reason = "设备须先完成改建并实际放置"
	else:
		var current: int = int(item.get("upgrade_level",item.get("grade",0)))
		var target: int = int(payload.get("target_level",current+1))
		if target<=current or target>2:
			reason = "升级必须包含下一未完成等级"
		for level: int in range(current+1,target+1):
			var tier: Dictionary = {}
			for candidate: Dictionary in content.catalog.upgrade_tiers:
				if int(candidate.level)==level:
					tier = candidate
			if tier.is_empty() or not tier.research_id in world.facts.research:
				reason = "缺少本等级升级研究"
				break
			var definition: Dictionary = content.facility_definition(item.definition_id)
			var price: int = ceili(float(definition.price)*float(tier.price_basis_points)/10000.0)
			stages.append({"level":level,"price":price,"total_milli":int(tier.work_seconds)*1000,"remaining_milli":int(tier.work_seconds)*1000,
				"completed_milli":0,"started":false,"completed":false,"cancelled":false,"contributions":{},"rule":tier.duplicate(true)})
			total += price
	if payload.has("cost") and int(payload.cost)!=total:
		reason = "升级材料报价已经改变"
	if reason.is_empty() and world.facts.mode!="creative" and HospitalLedger.balance(world)<total:
		reason = "升级材料资金不足"
	if reason.is_empty() and not _any_repair_position(world,item):
		reason = "缺少真实合法维修操作位"
	return {"ok":reason.is_empty(),"reason":reason,"facility_id":id,"stages":stages,"cost":total,
		"waiting_for_mechanic":not _has_mechanic(world),"safe_release_pending":not item.is_empty() and not _safe_free(world,id)}

func execute(world: WorldState, kind: String, payload: Dictionary) -> CommandResult:
	var state: Dictionary = world.facts.maintenance
	match kind:
		"maintenance_policy":
			var policy: String = str(payload.get("policy_id",""))
			if not content.balance.maintenance_dispatch.auto_thresholds.has(policy):
				return _reject(world,"保养策略不存在")
			state.policy_id = policy
			world.touch()
			return CommandResult.new(true,"applied","",[],world.revision)
		"maintenance_order":
			var item: Dictionary = _equipment(world).get(str(payload.get("facility_id","")),{})
			if item.is_empty():
				return _reject(world,"该物件不属于维护集合")
			if not item.failed and not item.pending_failure and float(item.condition)>float(content.balance.maintenance_dispatch.manual_threshold):
				return _reject(world,"完好设备不能反复保养")
			var job: Dictionary = _ensure_job(world,item,"repair" if item.failed or item.pending_failure else "maintenance",false)
			world.touch()
			return CommandResult.new(true,"applied","",[job.id],world.revision)
		"maintenance_pin":
			var id: String = str(payload.get("job_id",""))
			if not id.is_empty() and not state.jobs.has(id):
				return _reject(world,"维护工单不存在")
			state.pinned_job_id = id
			world.touch()
			return CommandResult.new(true,"applied","",[id],world.revision)
		"maintenance_pause", "maintenance_resume", "maintenance_cancel":
			var id: String = str(payload.get("job_id",""))
			if not state.jobs.has(id):
				return _reject(world,"维护工单不存在")
			var job: Dictionary = state.jobs[id]
			if job.phase in ["completed","cancelled"]:
				return CommandResult.new(true,"duplicate","",[],world.revision)
			if kind=="maintenance_cancel":
				if job.started or job.kind=="repair":
					return _reject(world,"故障或已开工维护只能暂停与继续")
				_release(world,job)
				job.phase = "cancelled"
				var item: Dictionary = _equipment(world).get(job.facility_id,{})
				if not item.is_empty():
					item.maintenance_order_id = ""
			else:
				job.paused = kind=="maintenance_pause"
				if job.paused:
					_release(world,job)
			world.touch()
			return CommandResult.new(true,"applied","",[id],world.revision)
		"machine_upgrade", "upgrade_order":
			var quote: Dictionary = upgrade_quote(world,payload)
			if not quote.ok:
				return _reject(world,quote.reason)
			var id: String = "upgrade_%08d" % (int(world.facts.entity_next)+1)
			var hospital_paid: int = mini(HospitalLedger.balance(world),int(quote.cost)) if world.facts.mode=="creative" else int(quote.cost)
			var payment: CommandResult = HospitalLedger.post(world,LedgerEntry.new(id,"upgrade_material",-hospital_paid))
			if not payment.accepted:
				return payment
			world.new_id("upgrade")
			var remaining_paid: int = hospital_paid
			var total_work: int = 0
			for stage: Dictionary in quote.stages:
				stage.hospital_paid = mini(remaining_paid,int(stage.price))
				stage.direct_paid = int(stage.price)-int(stage.hospital_paid)
				remaining_paid -= int(stage.hospital_paid)
				total_work += int(stage.total_milli)
			state.upgrades[id] = {"id":id,"facility_id":quote.facility_id,"stages":quote.stages,"created_tick":world.sim_tick,
				"cost":quote.cost,"hospital_paid":hospital_paid,"direct_paid":int(quote.cost)-hospital_paid,"refunded":0,"phase":"queued","paused":false,
				"worker_id":"","work_cell":[],"reason":"已付材料，等待维修员" if quote.waiting_for_mechanic else "等待安全释放设备",
				"remaining_milli":total_work,"worker_rate":1.0,"contributions":{}}
			world.facts.facilities[quote.facility_id].upgrading_block = true
			world.touch()
			return CommandResult.new(true,"applied","",[id,quote.facility_id],world.revision)
		"upgrade_pause", "upgrade_resume", "upgrade_cancel", "upgrade_abandon":
			var id: String = str(payload.get("order_id",""))
			if not state.upgrades.has(id):
				return _reject(world,"升级工单不存在")
			var order: Dictionary = state.upgrades[id]
			if order.phase in ["completed","cancelled"]:
				return CommandResult.new(true,"duplicate","",[],world.revision)
			if kind in ["upgrade_cancel","upgrade_abandon"]:
				for stage: Dictionary in order.stages:
					if stage.started and not stage.completed and kind=="upgrade_cancel":
						return _reject(world,"本级已经施工，只能暂停或在出售时放弃")
				if kind=="upgrade_abandon" and not bool(payload.get("for_disposal",false)):
					return _reject(world,"放弃已开工升级仅限真实出售或拆除事务")
				var refund: int = 0
				for stage: Dictionary in order.stages:
					if not stage.started and not stage.cancelled:
						refund += int(stage.hospital_paid)
						stage.cancelled = true
				HospitalLedger.post(world,LedgerEntry.new(id,"upgrade_cancel_refund",refund))
				order.refunded += refund
				_release(world,order)
				order.phase = "cancelled"
				var item: Dictionary = _equipment(world).get(order.facility_id,{})
				if not item.is_empty():
					item.upgrading_block = false
			else:
				order.paused = kind=="upgrade_pause"
				if order.paused:
					_release(world,order)
			world.touch()
			return CommandResult.new(true,"applied","",[id],world.revision)
	return _reject(world,"未知设备维护操作")

func dispatch(world: WorldState) -> void:
	_worked.clear()
	for staff: Dictionary in world.facts.staff.values():
		if staff.role=="mechanic":
			staff.dispatch_idle = false
			staff.dispatch_idle_tick = world.sim_tick
	var equipment: Dictionary = _equipment(world)
	var candidates: Array = []
	for job: Dictionary in world.facts.maintenance.jobs.values():
		if job.phase in ["completed","cancelled","inventory"] or job.paused or not equipment.has(job.facility_id) or world.sim_tick<int(job.get("resume_not_before_tick",0)):
			continue
		if not str(job.worker_id).is_empty():
			if not _worker_ready(world,str(job.worker_id),str(job.id)) or not _safe_free(world,str(job.facility_id)):
				_release(world,job)
			else:
				continue
		candidates.append({"job":job,"priority":_priority(world,job),"upgrade":false})
	for order: Dictionary in world.facts.maintenance.upgrades.values():
		if order.phase in ["completed","cancelled","inventory"] or order.paused or not equipment.has(order.facility_id) or world.sim_tick<int(order.get("resume_not_before_tick",0)):
			continue
		if not str(order.worker_id).is_empty():
			if not _worker_ready(world,str(order.worker_id),str(order.id)) or not _safe_free(world,str(order.facility_id)):
				_release(world,order)
			else:
				continue
		var item: Dictionary = equipment[order.facility_id]
		if item.failed or item.pending_failure or not str(item.maintenance_order_id).is_empty():
			order.reason = "先完成本设备原维修或保养"
			continue
		candidates.append({"job":order,"priority":4,"upgrade":true})
	for staff_id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[staff_id]
		if staff.role!="mechanic" or not _worker_ready(world,staff_id) or not _has_tools(world,staff_id):
			continue
		var legal: Array = []
		for candidate: Dictionary in candidates:
			var job: Dictionary = candidate.job
			if not str(job.worker_id).is_empty():
				continue
			var item: Dictionary = equipment[job.facility_id]
			if _in_inventory(world,str(item.id)) or not _safe_free(world,str(item.id)):
				job.reason = "等待现有安全服务或实际放置"
				continue
			var position: Dictionary = _position(world,item,staff_id)
			if position.is_empty() or not _region_allowed(staff,int(position.floor_id),position.cell):
				job.reason = "维修操作位不可达或超出员工严格区域"
				continue
			legal.append({"job":job,"priority":candidate.priority,"upgrade":candidate.upgrade,"position":position,
				"pinned":world.facts.maintenance.pinned_job_id==job.id,"preferred":_region_preferred(staff,int(position.floor_id),position.cell)})
		legal.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
			if a.priority!=b.priority: return a.priority<b.priority
			if a.pinned!=b.pinned: return a.pinned
			if a.preferred!=b.preferred: return a.preferred
			if a.job.created_tick!=b.job.created_tick: return a.job.created_tick<b.job.created_tick
			return a.job.id<b.job.id)
		if not legal.is_empty():
			var selected: Dictionary = legal[0]
			selected.job.worker_id = staff_id
			selected.job.work_cell = selected.position.cell
			selected.job.work_floor = selected.position.floor_id
			selected.job.phase = "travelling"
			selected.job.reason = ""
			staff.active_job_id = selected.job.id
	for staff_id: String in world.ids("staff"):
		if world.facts.staff[staff_id].role=="mechanic" and _worker_ready(world,staff_id):
			world.facts.staff[staff_id].dispatch_idle = true

func advance(world: WorldState) -> void:
	var equipment: Dictionary = _equipment(world)
	for id: String in _ordered(world.facts.maintenance.jobs):
		var job: Dictionary = world.facts.maintenance.jobs[id]
		if str(job.worker_id).is_empty() or job.paused or job.phase in ["completed","cancelled","inventory"] or not equipment.has(job.facility_id) or _in_inventory(world,str(job.facility_id)) or world.sim_tick<int(job.get("resume_not_before_tick",0)):
			continue
		var item: Dictionary = equipment[job.facility_id]
		if not _arrived(world,job,item):
			continue
		if job.kind=="maintenance" and (item.failed or item.pending_failure):
			_promote(world,job,item)
			continue
		if not job.started:
			job.frozen_class = _class(item).duplicate(true)
			var parts: int = int(job.frozen_class.repair_parts if job.kind=="repair" else job.frozen_class.maintenance_parts)
			var payment: CommandResult = _pay(world,str(job.id),"maintenance_parts",parts)
			if not payment.accepted:
				job.reason = payment.reason
				continue
			job.paid_parts = parts
			job.started = true
			item.maintenance_block = true
		if int(job.get("repair_difference_due",0))>0:
			var payment: CommandResult = _pay(world,str(job.id),"repair_difference",int(job.repair_difference_due))
			if not payment.accepted:
				job.reason = payment.reason
				continue
			job.paid_parts += int(job.repair_difference_due)
			job.repair_difference_due = 0
		job.phase = "working"
		job.worker_rate = _work_rate(world,str(job.worker_id),"maintenance")
		var amount: int = mini(roundi(100.0*float(job.worker_rate)),int(job.remaining_milli))
		job.completed_milli += amount
		job.remaining_milli -= amount
		_contribute(job,str(job.worker_id),amount)
		_worked[job.worker_id] = true
		if int(job.remaining_milli)==0:
			item.condition = float(content.balance.equipment.restored_condition)
			item.failed = false
			item.pending_failure = false
			item.maintenance_block = false
			item.repair_grace_until = world.sim_tick+int(content.balance.equipment.post_repair_grace_seconds)*10
			item.maintenance_order_id = ""
			_receipt(world,"repair_completed" if job.kind=="repair" else "maintenance_completed",str(job.id),job.contributions,int(job.total_milli),str(item.id))
			_release(world,job)
			job.phase = "completed"
	for id: String in _ordered(world.facts.maintenance.upgrades):
		var order: Dictionary = world.facts.maintenance.upgrades[id]
		if str(order.worker_id).is_empty() or order.paused or order.phase in ["completed","cancelled","inventory"] or not equipment.has(order.facility_id) or _in_inventory(world,str(order.facility_id)) or world.sim_tick<int(order.get("resume_not_before_tick",0)):
			continue
		var item: Dictionary = equipment[order.facility_id]
		if item.failed or item.pending_failure or not str(item.maintenance_order_id).is_empty():
			_release(world,order)
			order.reason = "故障先处理，原升级材料与工作保留"
			continue
		if not _arrived(world,order,item):
			continue
		var stage: Dictionary = _current_stage(order)
		if stage.is_empty():
			continue
		if not stage.started:
			stage.started = true
			stage.first_worker_rate = _work_rate(world,str(order.worker_id),"machine_upgrade")
		if order.phase!="working" or stage.get("rate_worker_id","")!=order.worker_id:
			order.worker_rate = _work_rate(world,str(order.worker_id),"machine_upgrade")
			stage.rate_worker_id = order.worker_id
		order.phase = "working"
		var amount: int = mini(roundi(100.0*float(order.worker_rate)),int(stage.remaining_milli))
		stage.remaining_milli -= amount
		stage.completed_milli += amount
		order.remaining_milli -= amount
		_contribute(stage,str(order.worker_id),amount)
		_worked[order.worker_id] = true
		if int(stage.remaining_milli)==0:
			stage.completed = true
			item.upgrade_level = int(stage.level)
			item.grade = int(stage.level)
			item.completed_upgrade_paid_cost = int(item.get("completed_upgrade_paid_cost",0))+int(stage.hospital_paid)
			_receipt(world,"upgrade_completed",str(order.id)+":"+str(stage.level),stage.contributions,int(stage.total_milli),str(item.id))
			if _current_stage(order).is_empty():
				_release(world,order)
				order.phase = "completed"
				item.upgrading_block = false

func _arrived(world: WorldState, job: Dictionary, item: Dictionary) -> bool:
	if not _worker_ready(world,str(job.worker_id),str(job.id)) or not _safe_free(world,str(item.id)):
		_release(world,job)
		return false
	var id: String = str(job.worker_id)
	if space.at(world,id,int(job.work_floor),job.work_cell) and not world.facts.moves.has(id):
		return space.static_reason(world,world.facts.actors[id],int(job.work_floor),Vector2i(int(job.work_cell[0]),int(job.work_cell[1]))).is_empty()
	var route: Dictionary = space.route(world,id,int(job.work_floor),job.work_cell)
	if not route.ok:
		_release(world,job)
		job.reason = str(route.get("reason","维修路线被挡住"))
		return false
	space.request_move(world,id,int(job.work_floor),job.work_cell)
	var movement: Dictionary = world.facts.moves.get(id,{})
	if movement.get("target_floor",-1)==int(job.work_floor) and movement.get("target_cell",[])==job.work_cell and str(movement.get("owner_job_id",str(job.id)))==str(job.id):
		movement.owner_job_id = str(job.id)
	return false

func _safe_free(world: WorldState, id: String) -> bool:
	if _in_inventory(world,id):
		return false
	if world.facts.connectors.has(id):
		return world.facts.connectors[id].phase=="idle" and world.facts.connectors[id].riders.is_empty()
	for session: Dictionary in world.facts.sessions.values():
		if session.facility_id==id:
			return false
	for preparation: Dictionary in world.facts.preparations.values():
		if preparation.get("facility_id","")==id or preparation.get("bed_id","")==id:
			return false
	for stay: Dictionary in world.facts.ward_stays.values():
		if stay.bed_id==id:
			return false
	if world.facts.adaptations.has(id):
		return false
	for session: Dictionary in world.facts.get("waiting_life",{}).get("sessions",{}).values():
		if session.get("facility_id","")==id:
			return false
	return true

func _in_inventory(world: WorldState, id: String) -> bool:
	return world.facts.inventory.get("build_items",{}).has(id)

func _position(world: WorldState, item: Dictionary, staff_id: String) -> Dictionary:
	var floor_id: int = int(item.floor_id)
	var target: Array = []
	if world.facts.connectors.has(item.id):
		var definition: Dictionary = content.definition("vertical_connectors",item.definition_id)
		floor_id = int(item.stops.min())
		target = [int(item.cell[0])+int(definition.repair_anchor[0]),int(item.cell[1])+int(definition.repair_anchor[1])]
	else:
		target = space.facility_layout(world,str(item.id)).get("repair_cell",[])
	if target.is_empty():
		return {}
	var route: Dictionary = space.route(world,staff_id,floor_id,target)
	return {"floor_id":floor_id,"cell":target,"distance":route.walking_distance} if route.ok else {}

func _any_repair_position(world: WorldState, item: Dictionary) -> bool:
	for id: String in world.ids("staff"):
		if world.facts.staff[id].role=="mechanic" and not _position(world,item,id).is_empty():
			return true
	# Missing mechanics can create a paid waiting order. The actual position must
	# still admit the standard recruit's full body; a preview never spawns a worker.
	var actor: Dictionary = {"id":"upgrade_preview","species_id":"S49","location":{"kind":"floor","floor_id":int(item.floor_id),"cell":item.cell},"facing":0.0}
	var target: Array = item.get("repair_cell",[])
	return not target.is_empty() and space.static_reason(world,actor,int(item.floor_id),Vector2i(int(target[0]),int(target[1]))).is_empty()

func _has_tools(world: WorldState, id: String) -> bool:
	var species: Dictionary = content.definition("species",world.facts.actors[id].species_id)
	for adapter: Dictionary in content.catalog.staff_rig_adapters:
		if adapter.rig==species.rig and "mechanic" in adapter.roles and "repair" in adapter.actions and "tool" in adapter.anchors:
			return true
	return false

func _worker_ready(world: WorldState, id: String, own_job: String = "") -> bool:
	if not world.facts.staff.has(id) or not world.facts.actors.has(id):
		return false
	var staff: Dictionary = world.facts.staff[id]
	return bool(staff.on_shift) and not staff.get("block_new_work",false) and str(staff.get("active_job_id","")) in ["",own_job] and str(staff.get("training_job_id","")).is_empty() and staff.get("life_task",{"phase":"idle"}).get("phase","idle")=="idle" and float(staff.get("energy",100))>15.0

func _release(world: WorldState, job: Dictionary) -> void:
	var id: String = str(job.get("worker_id",""))
	if world.facts.staff.has(id) and world.facts.staff[id].get("active_job_id","")==job.id:
		world.facts.staff[id].active_job_id = ""
	job.worker_id = ""
	if job.phase in ["working","travelling"]:
		job.phase = "queued"

func _work_rate(world: WorldState, id: String, action: String) -> float:
	if recruitment!=null and recruitment.has_method("work_rate"):
		return float(recruitment.call("work_rate",world,id,action))
	var skill: int = int(world.facts.staff[id].get("skill",world.facts.staff[id].get("level",1)))
	return 1.0+float(content.balance.staff_practice.speed_per_extra_level)*maxi(0,skill-1)

func _pay(world: WorldState, id: String, component: String, cost: int) -> CommandResult:
	if finance!=null and finance.has_method("pay_necessary"):
		return finance.call("pay_necessary",world,id,component,cost)
	var cash_paid: int = mini(HospitalLedger.balance(world),cost)
	var result: CommandResult = HospitalLedger.post(world,LedgerEntry.new(id,component,-cash_paid))
	if result.accepted:
		world.facts.maintenance.jobs[id][component+"_funding"] = {"cost":cost,"hospital_paid":cash_paid,"direct_paid":cost-cash_paid,"source":"creative_fund" if world.facts.mode=="creative" else "necessary_maintenance_aid"}
	return result

func _priority(world: WorldState, job: Dictionary) -> int:
	if job.kind=="maintenance":
		return 3
	for stay: Dictionary in world.facts.ward_stays.values():
		if stay.bed_id==job.facility_id:
			return 0
	for visit: Dictionary in world.facts.visits.values():
		if not str(visit.get("final_result","")).is_empty() or visit.phase in ["departed","leaving"]:
			continue
		var item: Dictionary = world.facts.facilities.get(job.facility_id,{})
		if not item.is_empty() and _upgradable(item):
			return 1
	return 2

func _upgradable(item: Dictionary) -> bool:
	for profile: Dictionary in content.catalog.medical_equipment_profiles:
		if profile.definition_id==item.definition_id:
			return true
	return false

func _active_upgrade(world: WorldState, facility_id: String) -> String:
	for order: Dictionary in world.facts.maintenance.upgrades.values():
		if order.facility_id==facility_id and order.phase not in ["completed","cancelled"]:
			return str(order.id)
	return ""

func _current_stage(order: Dictionary) -> Dictionary:
	for stage: Dictionary in order.stages:
		if not stage.completed and not stage.cancelled:
			return stage
	return {}

func _has_mechanic(world: WorldState) -> bool:
	for staff: Dictionary in world.facts.staff.values():
		if staff.role=="mechanic":
			return true
	return false

func _region_preferred(staff: Dictionary, floor_id: int, cell: Array) -> bool:
	var zone: Dictionary = staff.get("work_region",{})
	return not zone.is_empty() and int(zone.get("floor_id",floor_id))==floor_id and Rect2(float(zone.origin[0]),float(zone.origin[1]),float(zone.size[0]),float(zone.size[1])).has_point(Vector2(float(cell[0]),float(cell[1])))

func _region_allowed(staff: Dictionary, floor_id: int, cell: Array) -> bool:
	return not staff.get("work_region",{}).get("strict",false) or _region_preferred(staff,floor_id,cell)

func _contribute(job: Dictionary, id: String, amount: int) -> void:
	job.contributions[id] = int(job.contributions.get(id,0))+amount

func _receipt(world: WorldState, kind: String, source_id: String, contributions: Dictionary, total: int, facility_id: String) -> void:
	var id: String = source_id+":"+kind
	if world.facts.maintenance.receipts.has(id):
		return
	var winner: String = ""
	var largest: int = -1
	for staff_id: String in _ordered(contributions):
		if int(contributions[staff_id])>largest:
			winner = staff_id
			largest = int(contributions[staff_id])
	if not world.facts.staff.has(winner):
		winner = ""
	world.facts.maintenance.receipts[id] = {"id":id,"kind":kind,"source_id":source_id,"facility_id":facility_id,"staff_id":winner,"tick":world.sim_tick,"standard_work_milli":total}
	world.touch()

func query(world: WorldState, facility_id: String = "") -> Dictionary:
	var result: Dictionary = {"policy_id":world.facts.maintenance.policy_id,"jobs":[],"upgrades":[]}
	for job: Dictionary in world.facts.maintenance.jobs.values():
		if facility_id.is_empty() or job.facility_id==facility_id:
			result.jobs.append(job.duplicate(true))
	for order: Dictionary in world.facts.maintenance.upgrades.values():
		if facility_id.is_empty() or order.facility_id==facility_id:
			result.upgrades.append(order.duplicate(true))
	return result

func pending_costs(world: WorldState) -> Array:
	var result: Array = []
	var equipment: Dictionary = _equipment(world)
	for job: Dictionary in world.facts.maintenance.jobs.values():
		if job.phase in ["completed","cancelled"] or not equipment.has(job.facility_id):
			continue
		var cost: int = int(job.get("repair_difference_due",0))
		if not job.started:
			var category: Dictionary = _class(equipment[job.facility_id])
			cost = int(category.repair_parts if job.kind=="repair" else category.maintenance_parts)
		if cost>0:
			result.append({"owner_id":job.id,"kind":job.kind,"cost":cost,"forecast":true})
	return result

func validate(world: WorldState) -> String:
	var equipment: Dictionary = _equipment(world)
	var active: Dictionary = {}
	for job: Dictionary in world.facts.maintenance.jobs.values():
		if int(job.remaining_milli)<0 or int(job.completed_milli)+int(job.remaining_milli)!=int(job.total_milli):
			return "维护工单标准工作量不守恒"
		if job.phase not in ["completed","cancelled"]:
			if not equipment.has(job.facility_id) or active.has(job.facility_id):
				return "维护对象缺失或同设备存在重复工单"
			active[job.facility_id] = true
	for order: Dictionary in world.facts.maintenance.upgrades.values():
		var work: int = 0
		var price: int = 0
		for stage: Dictionary in order.stages:
			if int(stage.remaining_milli)<0 or int(stage.remaining_milli)+int(stage.completed_milli)!=int(stage.total_milli):
				return "升级工单标准工作量不守恒"
			work += int(stage.remaining_milli)
			price += int(stage.price)
		if price!=int(order.cost) or work!=int(order.remaining_milli) or int(order.refunded)>int(order.hospital_paid):
			return "升级付款、退款或工作余量不守恒"
	return ""

func _ordered(collection: Dictionary) -> Array:
	var ids: Array = collection.keys()
	ids.sort()
	return ids

func _reject(world: WorldState, reason: String) -> CommandResult:
	return CommandResult.new(false,"maintenance_unavailable",reason,[],world.revision)
