extends RefCounted

const CASES: Dictionary = {
	"PERF-01":"内容查询：规范与兼容身份、只读命中及独立缺失结果",
	"PERF-02":"医护默认字段：岗位差异、重复准备幂等及容器独立",
	"PERF-03":"活跃就诊：注册、离院结算、调用者隔离及恢复重建",
	"PERF-04":"门诊安排：同一步会话与释放、返原医生公平及精确超时后移",
	"PERF-05":"固定步补算：慢同步步保留完整欠账且逐帧有限发起",
	"PERF-06":"建造预览：分片只读、草案隔离、确认重检及一次收费",
	"PERF-07":"设备维护：空闲、逐日磨损、待生效故障及原随机抽取",
	"PERF-08":"导航缓存：冷热一致、假设来源隔离、真实失效及预算重建",
	"PERF-09":"墙边批量规划：完整障碍、精确首错、停靠层、预约、调用隔离及移除无额外扫描",
	"PERF-10":"完整几何：合法唯一后矩形证明、原坐标类型、边界96、无孔连通及开放分量全量排序"
}

class SlowSimulation extends HospitalSimulation:
	# A controller double supplies a predictably slow, completed fixed step.
	# Clinical work and movement remain covered by their real-flow cases.
	func step_nonblocking() -> TickResult:
		OS.delay_usec(GameSession.SYNCHRONOUS_BUDGET_USEC+1000)
		world.facts.sim_tick+=1
		world.touch(false)
		return TickResult.new(world.sim_tick,world.revision)

class MaintenanceProbe extends HospitalMaintenance:
	var class_queries: int = 0
	func _class(item: Dictionary) -> Dictionary:
		class_queries+=1
		return super._class(item)

func run(t) -> void:
	for id: String in CASES:
		if not t.wants(id): continue
		t.begin_case(id)
		var result: Dictionary=call("_case_"+id.right(2),HospitalContent.new())
		t.check(id,not result.checks.values().has(false),result)

func _world(content: HospitalContent, preset: bool = false) -> WorldState:
	return HospitalFactory.create(HospitalSnapshots.uuid(),"性能契约专项",preset,content)

func _case_09(content: HospitalContent) -> Dictionary:
	return preload("res://tests/acceptance/wall_batch_view.gd").new().run_case(content)

func _case_10(_content: HospitalContent) -> Dictionary:
	return preload("res://tests/acceptance/build_shape_contract.gd").new().run_case()

func _visit(world: WorldState, id: String, cell: Array) -> Dictionary:
	# A legal pre-service input boundary. These cases test scheduling and index
	# calculations, not the journey that brought a resident to this position.
	world.facts.actors[id]={"id":id,"name":id,"species_id":"S13","body_binding_id":"B_S13_D09_M09",
		"location":{"kind":"floor","floor_id":1,"cell":cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
	var visit: Dictionary={"id":id,"actor_id":id,"disease_id":"D09","binding_id":"B_S13_D09_M09",
		"requested_plan_id":"P_D09_COMMON","expression":"clear","personality_id":"PP01","anger":0.0,
		"phase":"wait_gp","diagnosis":{},"attempt_ids":[],"plan_decision":{},"complex":false,"final_result":"",
		"waiting_reason":"","ticket_id":"ticket_"+id,"doctor_fee_quote":-1,"arrived_tick":world.sim_tick,
		"arrival_key":id,"last_progress_tick":world.sim_tick,"last_service_tick":world.sim_tick}
	world.facts.visits[id]=visit
	world.facts.tickets[visit.ticket_id]={"id":visit.ticket_id,"visit_id":id,"kind":"gp","created_tick":world.sim_tick,"sequence":world.facts.visits.size()}
	world.register_visit(id)
	return visit

func _case_01(content: HospitalContent) -> Dictionary:
	var checks: Dictionary={}
	var canonical: Dictionary=content.registry.definition("species","core:S13")
	checks.canonical_alias_same_definition=not canonical.is_empty() and is_same(canonical,content.registry.definition("species","S13")) and canonical.id=="core:S13"
	var legacy: Dictionary=content.definition("species","S13")
	checks.compatibility_alias=legacy.id=="S13" and is_same(legacy,content.definition("species","core:S13"))
	checks.immutable_hit=canonical.is_read_only() and legacy.is_read_only() and content.facility_definition("FUR02").is_read_only()
	var missing: Dictionary=content.registry.definition("species","missing")
	missing.caller=true
	var collection_missing: Dictionary=content.registry.definition("missing","S13")
	collection_missing.caller=true
	var legacy_missing: Dictionary=content.definition("species","missing")
	legacy_missing.caller=true
	var facility_missing: Dictionary=content.facility_definition("missing")
	facility_missing.caller=true
	checks.misses_are_independent=content.registry.definition("species","missing").is_empty() and content.registry.definition("missing","S13").is_empty() and content.definition("species","missing").is_empty() and content.facility_definition("missing").is_empty() and not canonical.has("caller")
	return {"checks":checks}

func _case_02(content: HospitalContent) -> Dictionary:
	var world: WorldState=_world(content,true)
	var development: HospitalClinicalDevelopment=HospitalClinicalDevelopment.new(content,HospitalSpace.new(content))
	var medical: Array=[]
	for staff: Dictionary in world.facts.staff.values():
		if staff.role not in ["doctor","nurse"]: continue
		medical.append(staff)
		for key: String in ["training_job_id","cured_cases","growth_direction","completed_courses","growth_history","growth_goal","title_rate_changed_tick","base_prepared","base_task"]: staff.erase(key)
	development.ensure(world)
	var roles: bool=true
	for staff: Dictionary in medical:
		roles=roles and staff.training_job_id=="" and staff.cured_cases==0 and staff.growth_direction==("treatment" if staff.role=="doctor" else "care")
		roles=roles and (staff.has("base_task")==bool(staff.role=="nurse")) and (staff.has("base_prepared")==bool(staff.role=="nurse"))
	var first: Dictionary=medical[0]
	first.completed_courses.historical_course={"track":"treatment","target_level":1,"tick":0}
	first.growth_history.append({"kind":"course","track":"treatment","target_level":1,"tick":0})
	first.growth_goal={"kind":"course","track":"treatment","target_level":2}
	first.cured_cases=7
	var isolated: bool=medical.size()>1
	for staff: Dictionary in medical.slice(1): isolated=isolated and staff.completed_courses.is_empty() and staff.growth_history.is_empty() and staff.growth_goal.is_empty()
	var before: Dictionary=world.freeze()
	for _repeat: int in 5: development.ensure(world)
	return {"checks":{"role_defaults":roles,"mutable_defaults_isolated":isolated,"warm_ensure_preserves_progress":world.freeze()==before},"medical_staff":medical.size()}

func _case_03(content: HospitalContent) -> Dictionary:
	var world: WorldState=_world(content)
	for sample: Array in [["visit_b",[40,86]],["visit_a",[43,86]],["visit_d",[46,86]]]: _visit(world,sample[0],sample[1])
	var before: Dictionary=world.freeze()
	var checks: Dictionary={"lexical_order":world.active_visit_ids()==["visit_a","visit_b","visit_d"]}
	var borrowed: Array=world.active_visit_ids()
	borrowed.reverse()
	borrowed.pop_back()
	checks.caller_does_not_edit_index=world.active_visit_ids()==["visit_a","visit_b","visit_d"] and world.freeze()==before
	_visit(world,"visit_c",[49,86])
	checks.same_step_registration=world.active_visit_ids()==["visit_a","visit_b","visit_c","visit_d"]
	world.facts.visits.visit_b.phase="departed"
	world.facts.actors.visit_b.location={"kind":"outside"}
	world.finish_visits()
	checks.departure_waits_for_settlement="visit_b" in world.active_visit_ids()
	world.facts.visits.visit_b.departure_recorded=true
	world.finish_visits()
	checks.recorded_departure_removed=world.active_visit_ids()==["visit_a","visit_c","visit_d"] and world.facts.visits.has("visit_b")
	var restored: WorldState=WorldState.new(world.freeze())
	checks.restore_rebuild=restored.active_visit_ids()==world.active_visit_ids()
	world.facts=restored.freeze()
	checks.replacement_rebuild=world.active_visit_ids()==["visit_a","visit_c","visit_d"]
	return {"checks":checks}

func _case_04(content: HospitalContent) -> Dictionary:
	var world: WorldState=_world(content)
	var building: BuildService=BuildService.new(content)
	var room: CommandResult=building.execute(world,"build_room",_room("queue_room"))
	var station: CommandResult=building.execute(world,"build_facility",{"id":"queue_station","definition_id":"FUR02","room_id":"queue_room","cell":[36,69],"floor_id":1})
	var guide: HospitalFloorGuidance=HospitalFloorGuidance.new(content,HospitalSpace.new(content))
	guide.ensure(world)
	var checks: Dictionary={"legal_room_setup":room.accepted and station.accepted}
	if not checks.legal_room_setup: return {"checks":checks,"room":room.to_record(),"station":station.to_record()}
	for index: int in 8:
		var id: String="queue_"+str(index)
		_visit(world,id,[36+index*3,86])
		world.facts.floor_guidance.visits[id]={"visit_id":id,"request_key":"ticket_"+id+":gp","ticket_id":"ticket_"+id,
			"target_id":"queue_station","target_room_id":"queue_room","desk_id":"","guided_target":"queue_station","reason":"",
			"phase":"ready","initial_done":true,"guide_floor":1,"arrived_seq":index,"next_recheck":0,"receipts":[]}
	world.facts.floor_guidance.next_arrival=8
	var queue: Dictionary={"visit_ids":["queue_0","queue_1","queue_2","queue_3","queue_4"],"called_id":"","deadline_tick":-1}
	world.facts.floor_guidance.clinic_queues.queue_room=queue
	checks.fifo_head_only=guide.can_call(world,world.facts.visits.queue_0,{"kind":"gp"}) and not guide.can_call(world,world.facts.visits.queue_1,{"kind":"gp"})
	# The scheduling calculation observes a newly owned Session immediately.
	world.facts.sessions.queue_service={"id":"queue_service","visit_id":"queue_0","kind":"gp","facility_id":"queue_station","staff_ids":[],"resources":[],"remaining_ticks":1,"total_ticks":1}
	checks.same_step_session_blocks=not guide.can_call(world,world.facts.visits.queue_0,{"kind":"gp"})
	world.facts.sessions.erase("queue_service")
	guide.release(world,"queue_0")
	checks.same_step_release_advances=guide.can_call(world,world.facts.visits.queue_1,{"kind":"gp"})
	checks.consult_and_plan_keep_tail=not guide.can_call(world,world.facts.visits.queue_3,{"kind":"consult"}) and not guide.can_call(world,world.facts.visits.queue_4,{"kind":"plan"}) and queue.visit_ids==["queue_1","queue_2","queue_3","queue_4"]
	# An owner-restoration boundary may contain an abandoned tail entry. It
	# never counts among the three live patients passed by a timed-out head.
	queue.visit_ids=["queue_1","queue_2","queue_5","queue_3","queue_6","queue_4","queue_7"]
	queue.called_id="queue_1"
	queue.deadline_tick=1300
	world.facts.visits.queue_5.phase="leaving"
	world.facts.visits.queue_6.phase="departed"
	world.facts.floor_guidance.visits.queue_1.phase="destination"
	world.facts.sim_tick=1299
	checks.before_exact_deadline=not guide.can_call(world,world.facts.visits.queue_2,{"kind":"gp"}) and queue.visit_ids[0]=="queue_1"
	world.facts.sim_tick=1300
	checks.exact_deadline_three_live=guide.can_call(world,world.facts.visits.queue_2,{"kind":"gp"}) and queue.visit_ids==["queue_2","queue_3","queue_4","queue_1","queue_7"]
	guide.release(world,"queue_2")
	checks.rotated_head_release_live=guide.can_call(world,world.facts.visits.queue_3,{"kind":"consult"})
	var newcomer: Dictionary=_visit(world,"queue_new",[60,86])
	world.facts.floor_guidance.visits.queue_new={"visit_id":"queue_new","request_key":"ticket_queue_new:plan","ticket_id":"ticket_queue_new","target_id":"queue_station","target_room_id":"queue_room","desk_id":"","guided_target":"queue_station","reason":"","phase":"ready","initial_done":true,"guide_floor":1,"arrived_seq":8,"next_recheck":0,"receipts":[]}
	queue.visit_ids.append("queue_new")
	checks.same_step_newcomer_joins_tail=not guide.can_call(world,newcomer,{"kind":"plan"}) and queue.visit_ids.back()=="queue_new"
	return {"checks":checks,"queue":queue.duplicate(true)}

func _case_05(content: HospitalContent) -> Dictionary:
	var sim: SlowSimulation=SlowSimulation.new(_world(content),content)
	var session: GameSession=GameSession.new(sim,"slow_budget")
	session.set_speed(1)
	var frames: Array=[]
	frames.append(session.advance(0.9).size())
	var owed: bool=session.running_slow
	for _frame: int in 12:
		if not session.running_slow: break
		frames.append(session.advance(0.0).size())
	var checks: Dictionary={"slow_step_defers_next":frames[0]==1 and owed,"each_frame_bounded":frames.all(func(count: int)->bool:return count==1),"all_nine_steps_retained":sim.world.sim_tick==9 and frames.reduce(func(total: int,count: int)->int:return total+count,0)==9 and not session.running_slow}
	sim.dispose()
	return {"checks":checks,"steps_per_frame":frames,"final_tick":sim.world.sim_tick,"frame_budget_usec":GameSession.SYNCHRONOUS_BUDGET_USEC}

func _room(id: String) -> Dictionary:
	return {"kind":"build_room","id":id,"room_type_id":"gp","floor_id":1,"origin":[35,68],"size":[4,4],"door":{"definition_id":"DR01","edge":"south","offset":1}}

func _case_06(content: HospitalContent) -> Dictionary:
	var world: WorldState=_world(content)
	var building: BuildService=BuildService.new(content)
	building.ensure(world)
	var draft: Dictionary=_room("preview_room")
	var before: Dictionary=world.freeze()
	var job: BuildPreviewJob=BuildPreviewJob.new(building,world,draft)
	for _unit: int in 4096:
		if job.complete: break
		job.advance(world,2000,1)
	var checks: Dictionary={"preview_complete_readonly":job.complete and job.result.get("ok",false) and before==world.freeze()}
	if not checks.preview_complete_readonly: return {"checks":checks,"preview":job.result}
	var direct: Dictionary=BuildService.new(content).preview(world,draft)
	checks.complete_plan_matches_blocking=direct.get("ok",false) and job.result.quote==direct.quote and job.result.changed_ids==direct.changed_ids
	var quoted: Dictionary=draft.duplicate(true)
	quoted.quote=job.result.quote.duplicate(true)
	quoted.record_key="preview_confirm"
	var changed: Dictionary=quoted.duplicate(true)
	changed.size=[5,4]
	var refused: CommandResult=building.execute(world,"build_room",changed)
	checks.confirm_replans_current_draft=not refused.accepted and refused.code=="material_change" and before==world.freeze()
	job.result.draft.origin[0]=41
	var cash: int=HospitalLedger.balance(world)
	var accepted: CommandResult=building.execute(world,"build_room",quoted)
	checks.original_draft_and_fee=accepted.accepted and world.facts.rooms.preview_room.origin==[35,68] and cash-HospitalLedger.balance(world)==int(job.result.price)
	var committed: Dictionary=world.freeze()
	var duplicate: CommandResult=building.execute(world,"build_room",quoted)
	checks.idempotent_no_second_charge=duplicate.accepted and duplicate.code=="duplicate" and world.freeze()==committed
	var other: WorldState=_world(content)
	var other_before: Dictionary=other.freeze()
	var other_quote: Dictionary=building.preview(other,draft)
	checks.geometry_reuse_has_no_world_or_draft_alias=other_quote.get("ok",false) and int(other_quote.price)==int(job.result.price) and other.freeze()==other_before and draft.origin==[35,68]
	var occupied: WorldState=_world(content)
	_visit(occupied,"preview_occupant",[36,70])
	var occupied_before: Dictionary=occupied.freeze()
	var occupied_job: BuildPreviewJob=BuildPreviewJob.new(building,occupied,draft)
	for _unit: int in 4096:
		if occupied_job.complete: break
		occupied_job.advance(occupied,2000,1)
	checks.cached_shape_keeps_occupancy_rejection=occupied_job.complete and not occupied_job.result.get("ok",true) and occupied.freeze()==occupied_before
	return {"checks":checks,"price":job.result.price,"units":job.units_checked,"maximum_unit_usec":job.maximum_unit_usec,"maximum_unit_phase":job.maximum_unit_phase,"atomic_overruns":job.atomic_overruns,"refused":refused.to_record()}

func _category(content: HospitalContent, item: Dictionary) -> Dictionary:
	var definition: Dictionary=content.facility_definition(item.definition_id)
	if definition.is_empty(): definition=content.definition("vertical_connectors",item.definition_id)
	for category: Dictionary in content.balance.equipment.classes:
		if category.id==definition.get("equipment_class",""): return category
	return {}

func _case_07(content: HospitalContent) -> Dictionary:
	var world: WorldState=_world(content,true)
	var maintenance: MaintenanceProbe=MaintenanceProbe.new(content,HospitalSpace.new(content))
	maintenance.ensure(world)
	var before: Dictionary=world.freeze()
	maintenance.boundaries(world)
	var checks: Dictionary={"idle_needs_no_class_query":maintenance.class_queries==0 and world.freeze()==before}
	var equipment: Dictionary=maintenance._equipment(world)
	var expected: Dictionary={}
	for id: String in equipment:
		if not world.facts.inventory.build_items.has(id): expected[id]=maxf(0.0,float(equipment[id].condition)-float(_category(content,equipment[id]).wear_per_day))
	checks.placed_equipment_present=not expected.is_empty()
	world.facts.sim_tick=WorldState.TICKS_PER_DAY
	world.facts.maintenance.next_scan_tick=world.sim_tick+int(content.balance.equipment.scan_seconds)*10
	var rng: Dictionary=world.facts.rng.duplicate(true)
	maintenance.boundaries(world)
	var daily: bool=not expected.is_empty()
	for id: String in expected: daily=daily and is_equal_approx(float(equipment[id].condition),float(expected[id])) and int(equipment[id].last_wear_day)==1
	checks.full_daily_wear_once=daily and world.facts.rng==rng
	maintenance.class_queries=0
	before=world.freeze()
	maintenance.boundaries(world)
	checks.same_day_idempotent=world.freeze()==before and maintenance.class_queries==0
	world.facts.maintenance.next_scan_tick=world.sim_tick
	var expected_rng: WorldState=WorldState.new(world.freeze())
	var faults: Array=[]
	var draws: int=0
	for id: String in equipment:
		var item: Dictionary=equipment[id]
		if item.failed or item.pending_failure or world.sim_tick<int(item.repair_grace_until) or world.facts.inventory.build_items.has(id): continue
		var multiplier: int=1
		for index: int in content.balance.equipment.risk_condition_bounds.size():
			if float(item.condition)>=float(content.balance.equipment.risk_condition_bounds[index]):
				multiplier=int(content.balance.equipment.risk_multipliers[index])
				break
		if expected_rng.draw("equipment",10000)<int(_category(content,item).base_failure_bp)*multiplier: faults.append(id)
		draws+=1
	maintenance.boundaries(world)
	var same_faults: bool=true
	for id: String in equipment:
		if not world.facts.inventory.build_items.has(id): same_faults=same_faults and (bool(equipment[id].failed) or bool(equipment[id].pending_failure))==(id in faults)
	checks.scheduled_scan_exact_draws_and_faults=draws==expected.size() and world.facts.rng==expected_rng.facts.rng and same_faults
	var pending: WorldState=_world(content,true)
	var pending_maintenance: MaintenanceProbe=MaintenanceProbe.new(content,HospitalSpace.new(content))
	pending_maintenance.ensure(pending)
	var pending_id: String=""
	for id: String in pending_maintenance._equipment(pending):
		if not pending.facts.inventory.build_items.has(id) and pending_maintenance._safe_free(pending,id): pending_id=id; break
	checks.safe_pending_fixture=not pending_id.is_empty()
	if not pending_id.is_empty():
		pending.facts.facilities[pending_id].pending_failure=true
		rng=pending.facts.rng.duplicate(true)
		pending_maintenance.boundaries(pending)
		var item: Dictionary=pending.facts.facilities[pending_id]
		checks.pending_fault_applies_without_scan=item.failed and not item.pending_failure and not item.maintenance_order_id.is_empty() and pending.facts.rng==rng
	return {"checks":checks,"placed_count":expected.size(),"scan_draws":draws,"faults":faults}

func _case_08(content: HospitalContent) -> Dictionary:
	var world: WorldState=_world(content)
	_visit(world,"navigation_visit",[44,80])
	var space: HospitalSpace=HospitalSpace.new(content)
	var before: Dictionary=world.freeze()
	var first: Dictionary=space.route(world,"navigation_visit",1,[48,84],[],{},true)
	var repeated: Dictionary=space.route(world,"navigation_visit",1,[48,84],[],{},true)
	var cold: Dictionary=HospitalSpace.new(content).route(world,"navigation_visit",1,[48,84],[],{},true)
	var checks: Dictionary={"warm_and_cold_exact_route":first.get("ok",false) and first==repeated and first==cold,"queries_readonly":world.freeze()==before}
	var cache: NavigationCache=space._navigation
	var actual: FloorStaticGeometry=cache.floor_geometry(space,world,1)
	var hypothetical: Dictionary=cache.floor_source(space,world,1).duplicate(true)
	hypothetical.layout.blocked.append([48,84])
	var alternative: FloorStaticGeometry=cache.floor_geometry(space,world,1,hypothetical)
	checks.hypothetical_source_isolation=alternative._blocked.has(Vector2i(48,84)) and not actual._blocked.has(Vector2i(48,84)) and world.freeze()==before
	world.facts.floors.overrides["1"].blocked.append([48,84])
	world.touch()
	var blocked: Dictionary=space.route(world,"navigation_visit",1,[48,84],[],{},true)
	checks.real_geometry_invalidates=not blocked.get("ok",true)
	world.facts.floors.overrides["1"].blocked.erase([48,84])
	world.touch()
	before=world.freeze()
	cache._trim(1)
	var rebuilt: Dictionary=space.route(world,"navigation_visit",1,[48,84],[],{},true)
	var rebuilt_cold: Dictionary=HospitalSpace.new(content).route(world,"navigation_visit",1,[48,84],[],{},true)
	checks.evicted_borrower_and_rebuild=not actual._blocked.has(Vector2i(48,84)) and rebuilt.get("ok",false) and rebuilt==rebuilt_cold and world.freeze()==before
	var charge: int=cache._charged+cache._query_charged+cache._source_charged+cache._floor_charged
	checks.original_cache_allowance=charge<=int(content.balance.pathfinding.graph_cache_target_bytes)
	return {"checks":checks,"route":rebuilt,"cache_charge":charge}
