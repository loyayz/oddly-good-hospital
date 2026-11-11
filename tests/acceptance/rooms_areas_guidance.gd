extends RefCounted

const CASES: Dictionary = {
	"ROOM-05":"房间规格§3、§10.1；用途设施、单房排班、门诊一医与失败原子性",
	"ROOM-06":"房间规格§3.1；无桌工作、长期个人桌与实际办公室待岗",
	"ROOM-07":"房间规格§4.1；实际沙发睡眠、冷恢复与无位本次不睡",
	"ROOM-08":"房间规格§3；研究培训竞争同一真实桌位，多桌并行",
	"ROOM-09":"房间规格§3；诊疗整房多人，设备本人资格与真实独立并行",
	"ROOM-10":"房间规格§4.1；个人床损坏或真实不可达时换休息室，长期归属保留",
	"ROOM-11":"房间规格§4.2；无专用设施实际茶饮，门口无合法空位则结束本次尝试",
	"ROOM-12":"房间规格§9；连续转床尾迹插值舍入至端点时不产生零长段",
	"ROOM-13":"房间规格§3、§7.3；同一诊疗房两台同型设备真实并行，不改变原房间安排",
	"AREA-01":"房间规格§5；逐设施三格、重叠不合并、墙门边界及用途切换",
	"AREA-02":"房间规格§5.2；移动途中冻结原目标，自动重选与手动结束",
	"AREA-03":"房间规格§5.3；局部墙变更仅重建受影响设施投影，移动移除旧区域",
	"AREA-04":"房间规格§9；区域索引冷恢复所有权隔离，不复制运行时可变视图",
	"GUIDE-01":"房间规格§7.1～7.2；真实导诊护士、六秒工作、实体队列与实际到诊室",
	"GUIDE-02":"房间规格§7.3；缺本层目的地整台暂停，恢复后保持原待办",
	"GUIDE-03":"房间规格§7.4、§9；安排票序、精确三十秒后移三位与冷恢复",
	"GUIDE-04":"房间规格§7.3～7.4；同层随机房间、忙室仍可分配、六格共享椅",
	"GUIDE-05":"房间规格§7.2；实际体型蛇形坐标、左右朝向、单列与旋转边界计算",
	"GUIDE-06":"房间规格§7.4；实际长途到诊室期间医生等满三十秒后移三位",
	"GUIDE-07":"房间规格§7.3；如厕后实际返回原诊室，原室失效则恢复导诊待办且保留就诊票",
	"GUIDE-08":"房间规格§7.3、§9；代表设备移往别室或拆除后保留原房间，原行程与冷恢复不改派",
	"GUIDE-09":"房间规格§7.3、§9；手术原全院选择、患者真实跨层导诊、原目标与实际到场票序及冷恢复",
	"LIFE-01":"房间规格§8.1；门外唯一队伍、多洁具实际并行、不重置原期限",
	"LIFE-02":"房间规格§8.2；重叠饮水区域共享实际先后，远处不锁位",
	"LIFE-03":"房间规格§8；员工患者真实共用饮水/卫生间，按到场先后且完整使用后安全退出",
	"LIFE-04":"房间规格§3.1、§7.1、§8；真实护士准备与导诊/临床安全交接后生活服务，同工作段不重复准备",
	"LIFE-05":"房间规格§8；员工自动180秒需求、原集合及交接保护、实际80tick服务、冷却交替与失败原子性",
	"RESULT-01":"房间规格§2.3、§6、§9；房间失效后原安全服务完成一次，体验和小票保留",
	"RESULT-02":"房间规格§9；新医院身份重写保留房间班表、个人桌、两类队序和叫号期限",
	"RESULT-03":"房间规格§2.3、§3.2；恢复中病房结构失效后原护理、费用和安全退出承诺完整履行",
	"RESULT-04":"房间规格§3.2、§8；住院护士自动如厕等待原护理与覆盖安全结束，再真实使用设施",
	"RESULT-05":"房间规格§3.2；原医生随机探望实际到场六秒、每日幂等、临床优先和独立出院结算"
}
var content: HospitalContent
var _sequence: int=0

func run(t) -> void:
	content=HospitalContent.new()
	for id: String in CASES:
		if not t.wants(id): continue
		t.begin_case(id)
		var row: Dictionary=_case(id)
		t.check(id,row.ok,row)

func run_cases(database: HospitalContent, selected: Array = []) -> Dictionary:
	content=database
	var rows: Array=[]
	var ok: bool=true
	for id: String in (CASES.keys() if selected.is_empty() else selected):
		if not CASES.has(id): return {"ok":false,"error":"unknown selector "+id}
		var started: int=Time.get_ticks_usec()
		var row: Dictionary=_case(id)
		row.id=id; row.elapsed_ms=(Time.get_ticks_usec()-started)/1000.0
		rows.append(row); ok=ok and row.ok
	return {"ok":ok,"cases":rows}

func _case(id: String) -> Dictionary:
	match id:
		"ROOM-05": return _room_staff()
		"ROOM-06": return _offices()
		"ROOM-07": return _sleep()
		"ROOM-08": return _research_training()
		"ROOM-09": return _treatment_parallel()
		"ROOM-10": return _bed_fallback()
		"ROOM-11": return _tea()
		"ROOM-12": return _trail_boundary()
		"ROOM-13": return _same_equipment_parallel()
		"AREA-01": return _areas()
		"AREA-02": return _frozen_seat()
		"AREA-03": return load("res://tests/acceptance/public_region_lifecycle.gd").new().run_case(content)
		"AREA-04": return load("res://tests/acceptance/public_region_world_copy.gd").new().run_case(content)
		"GUIDE-01": return _guidance(false)
		"GUIDE-02": return _guidance(true)
		"GUIDE-03": return _clinic_order()
		"GUIDE-04": return _destinations()
		"GUIDE-05": return preload("res://tests/acceptance/guidance_snake_geometry.gd").new().run_checks()
		"GUIDE-06": return _actual_call_deadline()
		"GUIDE-07": return _need_return()
		"GUIDE-08": return _arranged_room_identity()
		"GUIDE-09": return load("res://tests/acceptance/surgery_guidance_contract.gd").new().run_case(content)
		"LIFE-01": return _toilets()
		"LIFE-02": return _water_order()
		"LIFE-03": return _shared_amenities()
		"LIFE-04": return _amenity_handoffs()
		"LIFE-05": return load("res://tests/acceptance/staff_room_life_contract.gd").new().run_case(content,"auto_need")
		"RESULT-01": return _safe_room_loss()
		"RESULT-02": return _import_identity()
		"RESULT-03": return load("res://tests/acceptance/ward_room_guidance_contract.gd").new().run_case(content,"room_loss")
		"RESULT-04": return load("res://tests/acceptance/ward_room_guidance_contract.gd").new().run_case(content,"nurse_need")
		"RESULT-05": return load("res://tests/acceptance/staff_room_life_contract.gd").new().run_case(content,"social_visit")
	return {"ok":false,"checks":{}}

func _base() -> Dictionary:
	var world: WorldState=HospitalFactory.create(HospitalSnapshots.uuid(),"房间区域导诊验收",false,content)
	# Legal built-hospital funding input; construction prices are asserted by
	# ROOM-BUILD rather than inferred from this prerequisite balance.
	world.facts.ledger.opening_balance=1000000
	var sim:=HospitalSimulation.new(world,content)
	sim.services.arrivals.execute(world,"arrivals_intake",{"open":false})
	return {"world":world,"sim":sim,"checks":{},"commands":[],"steps":0,"events":{},"service_starts":[],"service_completions":[]}

func _command(x: Dictionary, kind: String, payload: Dictionary) -> CommandResult:
	_sequence+=1
	var request: Dictionary=payload.duplicate(true)
	request.command_id="rooms_acceptance_%d"%_sequence
	var result: CommandResult=x.sim.services.building.execute(x.world,kind,request)
	x.commands.append({"kind":kind,"accepted":result.accepted,"reason":result.reason})
	return result

func _room(x: Dictionary, id: String, kind: String, cell: Array, size: Array = [10,10]) -> bool:
	return _command(x,"build_room",{"id":id,"room_type_id":kind,"origin":cell,"size":size,"door":{"definition_id":"DR04","edge":"south","offset":3}}).accepted

func _facility(x: Dictionary, id: String, definition: String, cell: Array, room_id: String = "") -> bool:
	return _command(x,"build_facility",{"id":id,"definition_id":definition,"cell":cell,"room_id":room_id}).accepted

func _staff(x: Dictionary, id: String, role: String, cell: Array, room_id: String = "") -> void:
	HospitalFactory._add_staff(x.world,id,id,role,cell,content)
	x.sim.services.development.ensure(x.world)
	x.sim.services.scheduler.ensure(x.world)
	x.sim.services.recruitment.ensure(x.world)
	x.sim.services.wellbeing.ensure(x.world)
	var staff: Dictionary=x.world.facts.staff[id]
	var duty: String="outpatient" if role=="doctor" else "work"
	staff.schedule=[{"kind":duty,"pools":[] if room_id.is_empty() else [room_id],"locked":false},{"kind":duty,"pools":[] if room_id.is_empty() else [room_id],"locked":false},{"kind":"rest","pools":[],"locked":false}]
	x.sim.space.sync_actor(x.world,id)
	x.world.touch(false)
	x.sim.services.finance.ensure(x.world)

func _step(x: Dictionary) -> bool:
	var result: TickResult=x.sim.step()
	x.steps+=1
	for event: SimEvent in result.facts:
		x.events[event.kind]=int(x.events.get(event.kind,0))+1
		if event.kind=="service_started": x.service_starts.append(event.to_record())
		if event.kind=="service_completed": x.service_completions.append(event.to_record())
	return result!=null

func _finish(x: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var validation: String=x.world.validate(content)
	x.checks.world_valid=validation.is_empty()
	var row: Dictionary={"ok":x.checks.values().all(func(v:Variant)->bool:return v==true),"checks":x.checks,"validation":validation,"commands":x.commands,"real_steps":x.steps,"business_events":x.events,"service_starts":x.service_starts,"service_completions":x.service_completions}
	if not row.ok: row.final_state={"tick":x.world.sim_tick,"staff":x.world.facts.staff.duplicate(true),"actors":x.world.facts.actors.duplicate(true),"moves":x.world.facts.moves.duplicate(true),"research_progress":x.world.facts.get("research_progress",{}).duplicate(true)}
	row.merge(extra)
	x.sim.dispose()
	return row

# A legal waiting input immediately before the operation being tested. The
# patient has a real body, ticket and RNG binding; subsequent travel and work
# always use the production simulator at its ordinary 0.1-second step.
func _patient(x: Dictionary, id: String, cell: Array, service: String = "gp", binding_id: String = "") -> Dictionary:
	var binding: Dictionary={}
	for row: Dictionary in content.catalog.treatment_bindings:
		if row.id==binding_id or binding_id.is_empty() and row.species_id=="S49": binding=row; break
	var actor_id: String="patient_"+id
	x.world.facts.actors[actor_id]={"id":actor_id,"name":id,"species_id":binding.species_id,"body_binding_id":binding.id,"location":{"kind":"floor","floor_id":1,"cell":cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
	var visit: Dictionary={"id":id,"actor_id":actor_id,"disease_id":binding.disease_id,"binding_id":binding.id,"requested_plan_id":"P_"+binding.disease_id+"_COMMON","expression":"clear","personality_id":"PP01","anger":0.0,"phase":"arrival","evidence_by_source":{},"attempt_ids":[],"plan_decision":{},"complex":false,"final_result":"","waiting_reason":"","ticket_id":"","doctor_fee_quote":-1,"arrival_tick":x.world.sim_tick,"arrived_tick":x.world.sim_tick,"last_progress_tick":x.world.sim_tick,"last_service_tick":x.world.sim_tick,"arrival_key":"acceptance_"+id}
	x.world.facts.visits[id]=visit
	x.world.register_visit(id)
	x.sim.clinic._queue(x.world,visit,service)
	x.sim.space.sync_actor(x.world,actor_id)
	x.world.touch(false)
	x.sim.services.waiting.ensure(x.world)
	x.sim.services.experience.ensure(x.world)
	return visit

func _arranged(x: Dictionary, visit: Dictionary, target: String, ready: bool = false) -> void:
	var ticket: Dictionary=x.world.facts.tickets[visit.ticket_id]
	var g: HospitalFloorGuidance=x.sim.services.floor_guidance
	x.world.facts.floor_guidance.next_arrival+=1
	x.world.facts.floor_guidance.visits[visit.id]={"visit_id":visit.id,"request_key":g._key(ticket),"ticket_id":ticket.id,"phase":"ready" if ready else "destination","target_id":target,"target_room_id":str(x.world.facts.facilities[target].get("room_id","")),"desk_id":"","guide_floor":1,"initial_done":true,"receipts":[],"guided_target":target,"arrived_seq":x.world.facts.floor_guidance.next_arrival,"reason":"","next_recheck":0}
	if ticket.kind=="gp":
		var room: String=str(x.world.facts.facilities[target].room_id)
		x.world.facts.floor_guidance.clinic_queues.get_or_add(room,{"visit_ids":[],"called_id":"","deadline_tick":-1}).visit_ids.append(visit.id)

func _room_staff() -> Dictionary:
	var x: Dictionary=_base()
	x.checks.rooms=_room(x,"gp","gp",[34,66]) and _room(x,"treatment","treatment",[46,66])
	x.checks.machine=_facility(x,"machine","M09",[48,69],"treatment")
	x.checks.missing_desk_blocks=not x.sim.space.room_use.reason(x.world,"gp").is_empty()
	x.checks.desk=_facility(x,"desk","FUR02",[37,69],"gp")
	x.checks.required_equipment_ready=x.sim.space.room_use.reason(x.world,"gp").is_empty() and x.sim.space.room_use.reason(x.world,"treatment").is_empty()
	_staff(x,"doctor","doctor",[56,90],"gp")
	_staff(x,"other","doctor",[59,90])
	_staff(x,"nurse","nurse",[56,93])
	var before: Dictionary=x.world.freeze()
	var proposed: Array=x.world.facts.staff.other.schedule.duplicate(true)
	proposed[0].pools=["gp"]
	var duplicate: CommandResult=x.sim.services.scheduler.execute(x.world,"apply_schedule",{"changes":[{"staff_id":"other","schedule":proposed}]})
	x.checks.one_gp_doctor=not duplicate.accepted and duplicate.code=="room_capacity" and before==x.world.freeze()
	proposed=x.world.facts.staff.nurse.schedule.duplicate(true); proposed[0].pools=["gp"]
	var wrong: CommandResult=x.sim.services.scheduler.execute(x.world,"apply_schedule",{"changes":[{"staff_id":"nurse","schedule":proposed}]})
	x.checks.no_nurse_gp=not wrong.accepted and before==x.world.freeze()
	x.checks.doctor_needs_no_preparation=not x.world.facts.staff.doctor.has("base_prepared") and not x.world.facts.staff.doctor.has("base_task") and x.sim.clinic._can_start(x.world,x.world.facts.staff.doctor)
	var original: Array=x.world.facts.facilities.machine.cell.duplicate()
	x.checks.change_use=_command(x,"build_room_use",{"target_id":"treatment","room_type_id":"research"}).accepted
	x.checks.unmatched_machine_stays=x.world.facts.facilities.machine.cell==original and not x.sim.space.room_use.facility_reason(x.world,x.world.facts.facilities.machine).is_empty()
	x.checks.close=_command(x,"build_room_open",{"target_id":"gp","open_intent":false}).accepted and not x.sim.space.room_use.reason(x.world,"gp").is_empty()
	var presets: bool=true
	for definition: Dictionary in content.catalog.blueprint_presets:
		var result: Dictionary=x.sim.services.blueprints.builtin(definition.id)
		presets=presets and result.ok and not result.get("blueprint",{}).get("rooms",[]).is_empty()
	x.checks.all_builtin_blueprints_have_real_room_sources=presets
	return _finish(x)

func _offices() -> Dictionary:
	var x: Dictionary=_base()
	x.checks.room=_room(x,"office","doctor_office",[34,66])
	_staff(x,"doctor","doctor",[55,90])
	x.checks.no_desk_still_employed=x.sim.clinic._can_start(x.world,x.world.facts.staff.doctor)
	x.checks.desk=_facility(x,"personal","SE05",[37,69],"office")
	var arrived: bool=false
	for index: int in 1000:
		if not _step(x): break
		var actor: Dictionary=x.world.facts.actors.doctor
		if actor.location.kind=="floor" and x.sim.space.room_contains(x.world.facts.rooms.office,x.sim.space.body_rectangle(actor)) and not x.world.facts.moves.has("doctor"):
			arrived=true; break
	x.checks.real_office_arrival=arrived
	x.checks.personal_desk=x.world.facts.doctor_desks.get("personal",{}).get("staff_id","")=="doctor"
	x.checks.move=_command(x,"build_move",{"target_id":"personal","floor_id":1,"cell":[38,69]}).accepted
	_step(x)
	x.checks.desk_owner_stable=x.world.facts.doctor_desks.get("personal",{}).get("staff_id","")=="doctor"
	_staff(x,"unassigned","doctor",[58,90])
	x.checks.no_second_desk_gate=x.sim.clinic._can_start(x.world,x.world.facts.staff.unassigned)
	return _finish(x)

func _sleep() -> Dictionary:
	var x: Dictionary=_base()
	x.checks.room=_room(x,"rest","rest",[34,66])
	x.checks.sofa=_facility(x,"sofa","FUR06",[37,69],"rest")
	_staff(x,"cleaner","cleaner",[55,90])
	x.world.facts.staff.cleaner.awake_ticks=ceili(float(content.balance.staff_sleep.awake_limit_seconds)/WorldState.TICK_SECONDS)
	x.world.facts.staff.cleaner.energy=40.0
	var projection: Dictionary={"area":x.sim.space.public_areas.for_facility(x.world,"sofa"),"fit":x.sim.space.facility_quote(x.world,"sofa","cleaner"),"route":x.sim.space.travel_quote(x.world,"cleaner",1,[36,73]),"sleep_fit":x.sim.services.wellbeing._sofa_sleep_fits(x.world,"cleaner","sofa")}
	projection.arrival=x.sim.space.public_areas.arrival_point(x.world,"cleaner",projection.area)
	var sleeping: bool=false
	var no_remote_use: bool=true
	for index: int in 1000:
		if not _step(x): break
		var staff: Dictionary=x.world.facts.staff.cleaner
		if staff.life_task.phase=="sleep": sleeping=true; break
		no_remote_use=no_remote_use and float(staff.energy)<=40.0
	x.checks.walking_has_no_sleep_recovery=no_remote_use
	x.checks.actual_sofa_sleep=sleeping and x.world.facts.actors.cleaner.get("support_facility_id","")=="sofa" and x.world.facts.actors.cleaner.posture=="lying"
	x.checks.no_invented_bed=x.world.facts.staff_life.personal_beds.is_empty()
	for index: int in 80: _step(x)
	var before: Dictionary=x.world.freeze()
	var restored:=WorldState.new(before)
	var restored_sim:=HospitalSimulation.new(restored,content)
	x.checks.cold_restore_preserves_progress=restored.freeze()==before and restored.validate(content).is_empty()
	var remaining: int=int(x.world.facts.staff.cleaner.sleep_remaining_ticks)
	_step(x)
	restored_sim.step()
	x.checks.cold_next_step_same=x.world.freeze()==restored.freeze() and int(x.world.facts.staff.cleaner.sleep_remaining_ticks)==remaining-1
	restored_sim.dispose()
	for index: int in 4700:
		_step(x)
		if x.world.facts.staff.cleaner.sleep_remaining_ticks==0 and x.world.facts.staff.cleaner.life_task.phase=="idle": break
	x.checks.full_sleep_and_actual_return=x.world.facts.staff.cleaner.sleep_remaining_ticks==0 and x.world.facts.staff.cleaner.life_task.phase=="idle" and x.world.facts.actors.cleaner.posture=="standing" and not x.world.facts.actors.cleaner.has("support_facility_id") and x.world.facts.staff_life.reservations.is_empty()
	var no_space: Dictionary=_base()
	_staff(no_space,"cleaner","cleaner",[55,90])
	no_space.world.facts.staff.cleaner.awake_ticks=ceili(float(content.balance.staff_sleep.awake_limit_seconds)/WorldState.TICK_SECONDS)
	var energy: float=float(no_space.world.facts.staff.cleaner.energy)
	for index: int in 4: _step(no_space)
	x.checks.no_space_no_offsite=no_space.world.facts.actors.cleaner.location.kind=="floor" and no_space.world.facts.staff.cleaner.life_task.phase=="idle" and int(no_space.world.facts.staff.cleaner.awake_ticks)>ceili(float(content.balance.staff_sleep.awake_limit_seconds)/WorldState.TICK_SECONDS) and float(no_space.world.facts.staff.cleaner.energy)<=energy
	var other: Dictionary=_finish(no_space)
	x.checks.no_space_world_valid=other.ok
	return _finish(x,{"no_space":other,"projection":projection})

func _areas() -> Dictionary:
	var x: Dictionary=_base()
	x.checks.facilities=_facility(x,"water_a","FUR17",[40,82]) and _facility(x,"water_b","FUR17",[44,82])
	var index: HospitalPublicAreas=x.sim.space.public_areas
	var first: Dictionary=index.for_facility(x.world,"water_a")
	var second: Dictionary=index.for_facility(x.world,"water_b")
	var a: Dictionary=index.region(x.world,first)
	var b: Dictionary=index.region(x.world,second)
	x.checks.independent=not a.is_empty() and not b.is_empty() and first!=second
	x.checks.overlap_without_merge=a.cells.has(Vector2i(42,82)) and b.cells.has(Vector2i(42,82))
	x.checks.three_grid_limit=a.cells.has(Vector2i(37,82)) and not a.cells.has(Vector2i(36,82)) and a.cells.size()<100
	x.checks.wall=_command(x,"build_wall",{"edges":[{"axis":"y","line":42,"low":78,"high":87}]}).accepted
	a=index.region(x.world,index.for_facility(x.world,"water_a"))
	x.checks.wall_boundary=not a.cells.has(Vector2i(42,82)) and a.cells.has(Vector2i(41,82))
	x.checks.door=_command(x,"build_door",{"id":"area_door","definition_id":"DR01","cell":[42,82],"edge":"west"}).accepted
	a=index.region(x.world,index.for_facility(x.world,"water_a"))
	x.checks.door_is_boundary=not a.cells.has(Vector2i(42,82))
	x.checks.public_room=_room(x,"rest","rest",[34,66]) and _facility(x,"inside","FUR17",[37,69],"rest")
	x.checks.public_room_area=not index.for_facility(x.world,"inside").is_empty()
	x.checks.private_change=_command(x,"build_room_use",{"target_id":"rest","room_type_id":"doctor_office"}).accepted and index.for_facility(x.world,"inside").is_empty()
	return _finish(x)

func _guidance(missing: bool) -> Dictionary:
	var x: Dictionary=_base()
	x.checks.desk=_facility(x,"guide","SE01",[47,83])
	_staff(x,"guide_nurse","nurse",[55,90])
	x.world.facts.staff.guide_nurse.base_prepared=true
	var visit: Dictionary=_patient(x,"first",[42,90])
	var ticket: String=visit.ticket_id
	if not missing:
		x.checks.clinic=_room(x,"gp","gp",[34,66]) and _facility(x,"diagnosis","FUR02",[38,69],"gp")
		_staff(x,"doctor","doctor",[57,90],"gp")
	var g: HospitalFloorGuidance=x.sim.services.floor_guidance
	var actual_work: bool=true
	var work: int=0
	var paused: bool=false
	var original_queue: Array=[]
	var second: Dictionary={}
	for index: int in 1600:
		_step(x)
		var state: Dictionary=g.state(x.world,visit.id)
		if state.get("phase","")=="working":
			work+=1
			var layout: Dictionary=x.sim.space.facility_layout(x.world,"guide")
			actual_work=actual_work and x.sim.space.at(x.world,visit.actor_id,1,layout.patient_cell) and x.sim.space.at(x.world,"guide_nurse",1,layout.operator_cells[0])
		if missing and second.is_empty() and state.has("queue_seq"):
			second=_patient(x,"second",[40,90])
		if missing and index==300:
			original_queue=g._desk_queue(x.world,"guide").duplicate()
			paused=state.get("phase","")=="desk_queue" and g.state(x.world,second.id).get("phase","")=="desk_queue" and work==0 and visit.ticket_id==ticket and not visit.phase in ["leaving","departed"]
			x.checks.recover=_room(x,"gp","gp",[34,66]) and _facility(x,"diagnosis","FUR02",[38,69],"gp")
			_staff(x,"doctor","doctor",[57,90],"gp")
		if not x.service_starts.is_empty(): break
	x.checks.real_six_second_guidance=actual_work and work==59 and not g.state(x.world,visit.id).get("receipts",[]).is_empty()
	x.checks.clinical_started_after_arrival=not x.service_starts.is_empty() and int(x.events.get("service_started",0))==1
	x.checks.fixed_nurse=x.world.facts.staff.guide_nurse.get("active_job_id","")=="floor_desk:guide"
	x.checks.no_preparation_gate=not x.world.facts.staff.doctor.has("base_prepared")
	if missing:
		x.checks.entire_desk_paused=paused and original_queue==[visit.id,second.id]
		x.checks.original_ticket=visit.ticket_id==ticket or not x.world.facts.tickets.has(ticket)
		x.checks.no_forced_referral=visit.final_result.is_empty()
	return _finish(x,{"observed_guidance_work_boundaries":work,"queue_before_recovery":original_queue})

func _clinic_order() -> Dictionary:
	var x: Dictionary=_base()
	x.checks.room=_room(x,"gp","gp",[34,66]) and _facility(x,"desk","FUR02",[38,69],"gp")
	var visits: Array=[]
	for number: int in 5:
		var visit: Dictionary=_patient(x,"order_"+str(number),[46+number*2,90])
		_arranged(x,visit,"desk",number>0)
		visits.append(visit)
	var g: HospitalFloorGuidance=x.sim.services.floor_guidance
	var queue: Dictionary=x.world.facts.floor_guidance.clinic_queues.gp
	var first: Dictionary=visits[0]
	x.checks.arrangement_before_arrival=g.can_call(x.world,first,x.world.facts.tickets[first.ticket_id]) and not g.can_call(x.world,visits[1],x.world.facts.tickets[visits[1].ticket_id]) and queue.deadline_tick==300
	# Named legal clock boundaries test the ordering calculation. Real waiting,
	# movement and six-second guidance are covered by GUIDE-01/02.
	x.world.facts.sim_tick=299
	g.can_call(x.world,first,x.world.facts.tickets[first.ticket_id])
	x.checks.before_deadline=queue.visit_ids[0]==first.id
	var frozen: Dictionary=x.world.freeze()
	var copy:=WorldState.new(frozen)
	var copy_sim:=HospitalSimulation.new(copy,content)
	x.checks.deadline_restored=copy.freeze()==frozen and copy.facts.floor_guidance.clinic_queues.gp.deadline_tick==300
	copy_sim.dispose()
	x.world.facts.sim_tick=300
	g.can_call(x.world,first,x.world.facts.tickets[first.ticket_id])
	x.checks.exact_deadline_back_three=queue.visit_ids==[visits[1].id,visits[2].id,visits[3].id,first.id,visits[4].id]
	g.can_call(x.world,visits[1],x.world.facts.tickets[visits[1].ticket_id])
	x.checks.next_call_new_deadline=queue.deadline_tick==600
	for visit: Dictionary in visits.slice(1): g.release(x.world,visit.id)
	queue.called_id="";queue.deadline_tick=-1
	g.can_call(x.world,first,x.world.facts.tickets[first.ticket_id])
	x.world.facts.sim_tick=1000
	g.can_call(x.world,first,x.world.facts.tickets[first.ticket_id])
	x.checks.single_never_reorders=queue.visit_ids==[first.id] and queue.called_id==first.id and queue.deadline_tick==600
	return _finish(x,{"calculation_boundaries":[299,300,1000]})

func _arranged_room_identity() -> Dictionary:
	var rows: Array=[]
	var ok: bool=true
	for remove_anchor: bool in [false,true]:
		var x: Dictionary=_base()
		x.checks.land=_command(x,"build_land",{"floor_id":1,"plot":[2,2]}).accepted
		# Complete the floor owner's ground-level defaults before the tested
		# journey. Restore must not be the first call that materializes them.
		x.sim.services.floors.ensure(x.world)
		x.checks.rooms=_room(x,"original","treatment",[34,66],[22,12]) and _room(x,"other","treatment",[60,66],[14,12])
		x.checks.equipment=_facility(x,"anchor","M09",[36,68],"original") and _facility(x,"remaining","M09",[48,68],"original")
		_staff(x,"original_doctor","doctor",[55,90],"original")
		_staff(x,"other_doctor","doctor",[70,90],"other")
		var visit: Dictionary=_patient(x,"room_identity",[58,90],"outpatient","B_S13_D09_M09")
		visit.evidence_by_source={"gp":100}
		x.checks.plan=x.sim.clinic.execute(x.world,"clinical_select_plan",{"visit_id":visit.id,"plan_id":visit.requested_plan_id}).accepted
		_arranged(x,visit,"anchor")
		for index: int in 20:
			_step(x)
			if x.world.facts.moves.has(visit.actor_id): break
		var goal: Dictionary=x.world.facts.moves.get(visit.actor_id,{}).duplicate(true)
		x.checks.real_original_trip=not goal.is_empty() and goal.get("floor_guidance_visit_id","")==visit.id
		if remove_anchor: x.checks.layout_change=_command(x,"build_demolish",{"target_id":"anchor"}).accepted
		else: x.checks.layout_change=_command(x,"build_move",{"target_id":"anchor","floor_id":1,"cell":[62,68]}).accepted and x.world.facts.facilities.anchor.room_id=="other"
		var frozen: bool=true
		var restored_equal: bool=true
		var cold_differences: Array=[]
		for index: int in 25:
			if index==10:
				var copy:=WorldState.new(x.world.freeze().duplicate(true))
				var copy_sim:=HospitalSimulation.new(copy,content)
				_step(x);copy_sim.step()
				restored_equal=x.world.freeze()==copy.freeze()
				if not restored_equal: _fact_differences(x.world.freeze(),copy.freeze(),"",cold_differences)
				copy_sim.dispose()
			else: _step(x)
			var move: Dictionary=x.world.facts.moves.get(visit.actor_id,{})
			frozen=frozen and not move.is_empty() and move.target_cell==goal.get("target_cell",[]) and move.target_floor==goal.get("target_floor",0) and x.sim.services.floor_guidance.target_room(x.world,visit.id)=="original"
		for index: int in 1200:
			_step(x)
			if not x.service_starts.is_empty(): break
		var sessions: Array=x.world.facts.sessions.values()
		x.checks.original_goal_not_followed_to_other_room=frozen
		x.checks.cold_keeps_original_room=restored_equal
		x.checks.real_service_in_original_room=sessions.size()==1 and sessions[0].facility_id=="remaining" and sessions[0].staff_ids==["original_doctor"] and x.sim.services.floor_guidance.target_room(x.world,visit.id)=="original"
		x.checks.no_new_guidance=x.sim.services.floor_guidance.state(x.world,visit.id).receipts.is_empty()
		var row: Dictionary=_finish(x,{"remove_anchor":remove_anchor,"original_goal":goal.get("target_cell",[]),"sessions":sessions.duplicate(true),"cold_differences":cold_differences})
		rows.append(row);ok=ok and row.ok
	return {"ok":ok,"runs":rows}

func _fact_differences(a: Variant, b: Variant, path: String, rows: Array) -> void:
	if rows.size()>=12 or a==b: return
	if a is Dictionary and b is Dictionary:
		var keys: Array=a.keys()
		for key: Variant in b:
			if not key in keys: keys.append(key)
		for key: Variant in keys: _fact_differences(a.get(key),b.get(key),path+"/"+str(key),rows)
	elif a is Array and b is Array:
		if a.size()!=b.size(): rows.append({"path":path+"/size","original":a.size(),"restored":b.size()})
		for index: int in mini(a.size(),b.size()): _fact_differences(a[index],b[index],path+"/"+str(index),rows)
	else: rows.append({"path":path,"original":a,"restored":b})

func _need_return() -> Dictionary:
	var rows: Array=[]
	var ok: bool=true
	for remove_room: bool in [false,true]:
		var x: Dictionary=_base()
		x.checks.rooms=_room(x,"gp","gp",[34,66]) and _room(x,"toilet","toilet",[46,66])
		x.checks.facilities=_facility(x,"desk","FUR02",[38,69],"gp") and _facility(x,"toilet_fixture","FUR07",[49,69],"toilet")
		_staff(x,"doctor","doctor",[59,90],"gp")
		var visit: Dictionary=_patient(x,"returning",[38,79])
		var ticket_id: String=visit.ticket_id
		_arranged(x,visit,"desk")
		x.sim.services.waiting._begin_need(x.world,visit)
		var removed: bool=false
		var saw_use: bool=false
		var finished: bool=false
		for index: int in 1100:
			_step(x)
			var need: Dictionary=x.world.facts.waiting_life.needs.get(visit.id,{})
			if need.get("phase","")=="using":
				saw_use=true
				if remove_room and not removed:
					removed=_command(x,"build_remove_wall",{"edges":[{"axis":"x","line":66,"low":34,"high":35}]}).accepted
			if saw_use and need.is_empty(): finished=true;break
		var state: Dictionary=x.sim.services.floor_guidance.state(x.world,visit.id)
		x.checks.real_toilet_and_return=saw_use and finished and not x.sim.space.overlaps_facility(x.world,visit.actor_id,"toilet_fixture")
		x.checks.original_ticket=x.world.facts.visits[visit.id].ticket_id==ticket_id and x.world.facts.tickets.has(ticket_id)
		x.checks.no_extra_guidance_receipt=state.get("receipts",[]).is_empty()
		if remove_room:
			x.checks.invalid_room_back_to_guidance=removed and state.get("target_id","").is_empty() and state.phase=="seek" and x.world.facts.sessions.is_empty()
		else:
			x.checks.original_room_and_order=state.target_id=="desk" and x.world.facts.floor_guidance.clinic_queues.gp.visit_ids==[visit.id]
			x.checks.actual_original_room_return=x.sim.services.floor_guidance.scope.allows(x.world,visit.actor_id,"desk",1,x.world.facts.actors[visit.actor_id].location.cell)
		var row: Dictionary=_finish(x,{"remove_room":remove_room,"guidance":state.duplicate(true)})
		rows.append(row);ok=ok and row.ok
	return {"ok":ok,"runs":rows}

func _actual_call_deadline() -> Dictionary:
	var x: Dictionary=_base()
	x.checks.room=_room(x,"gp","gp",[34,66]) and _facility(x,"desk","FUR02",[38,69],"gp")
	_staff(x,"doctor","doctor",[40,80],"gp")
	# Real legal long approach on the additional purchased plot; speed and
	# timestep remain unchanged, so the head cannot arrive before the deadline.
	x.checks.land=_command(x,"build_land",{"floor_id":1,"plot":[2,2]}).accepted
	var head: Dictionary=_patient(x,"head",[90,94])
	var next: Dictionary=_patient(x,"next",[38,80])
	_arranged(x,head,"desk")
	_arranged(x,next,"desk")
	var queue: Dictionary=x.world.facts.floor_guidance.clinic_queues.gp
	var before: bool=true
	var moved: bool=false
	var head_initial: Array=x.world.facts.actors[head.actor_id].location.cell.duplicate()
	for index: int in 500:
		_step(x)
		moved=moved or x.world.facts.actors[head.actor_id].location.cell!=head_initial
		if x.world.sim_tick<=300: before=before and queue.visit_ids[0]==head.id and x.service_starts.is_empty()
		if not x.service_starts.is_empty(): break
	x.checks.real_head_walk=moved
	x.checks.no_early_skip=before
	x.checks.next_called_after_full_deadline=not x.service_starts.is_empty() and next.id in x.service_starts[0].changed_ids and x.world.sim_tick>300
	x.checks.original_ticket_and_position=head.ticket_id!="" and queue.visit_ids==[next.id,head.id]
	return _finish(x,{"queue":queue.duplicate(true),"head_location":x.world.facts.actors[head.actor_id].location.duplicate(true)})

func _destinations() -> Dictionary:
	var x: Dictionary=_base()
	x.checks.rooms=_room(x,"gp_a","gp",[34,66]) and _room(x,"gp_b","gp",[46,66])
	x.checks.desks=_facility(x,"desk_a","FUR02",[38,69],"gp_a") and _facility(x,"desk_b","FUR02",[50,69],"gp_b")
	_staff(x,"doc_a","doctor",[55,90],"gp_a")
	_staff(x,"doc_b","doctor",[58,90],"gp_b")
	var visit: Dictionary=_patient(x,"random",[42,90])
	var g: HospitalFloorGuidance=x.sim.services.floor_guidance
	var ticket: Dictionary=x.world.facts.tickets[visit.ticket_id]
	var counts: Dictionary={}
	for attempt: int in 64:
		var chosen: String=g._choose_target(x.world,visit,ticket)
		counts[chosen]=int(counts.get(chosen,0))+1
	x.checks.random_uses_both_rooms=counts.has("desk_a") and counts.has("desk_b") and not counts.has("")
	x.world.facts.staff.doc_a.active_job_id="existing_actual_work"
	x.checks.busy_is_still_available="desk_a" in g._target_ids(x.world,visit,"gp")
	x.world.facts.staff.doc_a.active_job_id=""
	x.world.facts.facilities.desk_a.failed=true
	x.world.touch(false)
	x.checks.failure_rechecks=g._target_ids(x.world,visit,"gp")==["desk_b"]
	x.world.facts.facilities.desk_a.failed=false
	x.world.touch(false)
	x.checks.repair_rechecks=g._target_ids(x.world,visit,"gp").size()==2
	var actor: Dictionary=x.world.facts.actors[visit.actor_id]
	var prior: Dictionary=actor.location.duplicate(true)
	actor.location={"kind":"floor","floor_id":2,"cell":[42,90],"height_m":0.0}
	x.checks.no_cross_floor_ordinary=g._target_ids(x.world,visit,"gp").is_empty() and g._target_ids(x.world,visit,"spectrum").is_empty() and g._target_ids(x.world,visit,"outpatient").is_empty()
	actor.location=prior
	x.checks.chair=_facility(x,"shared","FUR09",[44,76])
	x.checks.six_grid_shared=g.scope.allows_seat(x.world,visit.actor_id,"desk_a","shared") and g.scope.allows_seat(x.world,visit.actor_id,"desk_b","shared")
	x.checks.distant_chair=_facility(x,"far","FUR09",[44,90]) and not g.scope.allows_seat(x.world,visit.actor_id,"desk_a","far")
	return _finish(x,{"random_room_counts":counts,"shared_chair":x.world.facts.facilities.shared.duplicate(true),"shared_scope_a":g.scope.area(x.world,visit.actor_id,"desk_a"),"shared_scope_b":g.scope.area(x.world,visit.actor_id,"desk_b")})

func _safe_room_loss() -> Dictionary:
	var x: Dictionary=_base()
	x.checks.room=_room(x,"gp","gp",[34,66]) and _facility(x,"desk","FUR02",[38,69],"gp")
	_staff(x,"doctor","doctor",[55,90],"gp")
	var visit: Dictionary=_patient(x,"safe",[40,80])
	_arranged(x,visit,"desk",true)
	for index: int in 600:
		_step(x)
		if not x.world.facts.sessions.is_empty(): break
	var session: Dictionary=x.world.facts.sessions.values()[0].duplicate(true) if not x.world.facts.sessions.is_empty() else {}
	x.checks.actual_service_started=not session.is_empty() and x.sim.space.at(x.world,visit.actor_id,1,x.sim.space.facility_layout(x.world,"desk").patient_cell)
	x.checks.remove_wall=_command(x,"build_remove_wall",{"edges":[{"axis":"x","line":66,"low":34,"high":35}]}).accepted
	x.checks.old_purpose_removed=x.world.facts.rooms.get("gp",{}).get("kind","")=="" and not x.world.facts.rooms.get("gp",{}).get("structure_valid",true)
	x.checks.commitment_retained=not session.is_empty() and x.world.facts.sessions.get(session.id,{})==session
	for index: int in 300:
		_step(x)
		if not x.world.facts.sessions.has(session.get("id","")): break
	var charges: Array=[]
	for entry: Dictionary in x.world.facts.ledger.entries.values():
		if entry.owner_id==visit.id: charges.append({"component":entry.component,"amount":entry.amount})
	x.checks.one_gp_charge=x.world.facts.ledger.entries.has(visit.id+":gp") and int(x.events.get("service_completed",0))==1 and not x.world.facts.sessions.has(session.get("id",""))
	x.checks.experience_preserved=x.world.facts.patient_experience.experience.has(visit.id) and x.world.facts.patient_experience.experience[visit.id].completed_services.size()==1
	x.checks.no_operational_departments=not x.world.facts.has("departments") and not x.world.facts.patient_experience.has("units") and not x.sim.services.has("departments")
	var receipt: Dictionary=x.sim.services.experience.receipt(x.world,visit.id)
	x.checks.receipt_preserved=not receipt.is_empty()
	return _finish(x,{"charges":charges,"receipt":receipt})

func _research_training() -> Dictionary:
	var x: Dictionary=_base()
	x.checks.room=_room(x,"research","research",[34,66]) and _facility(x,"desk_a","FUR05",[37,69],"research")
	_staff(x,"learner","doctor",[55,90])
	_staff(x,"researcher","researcher",[58,90],"research")
	x.world.facts.staff.learner.schedule[0]={"kind":"training","pools":[],"locked":false}
	x.world.facts.research_progress.opened_tick=0
	x.world.facts.research_progress.materials["R01"]={"kind":"mail","tick":0}
	var first: CommandResult=x.sim.services.research.execute(x.world,"research_start",{"research_id":"R01","worker_id":"researcher"})
	var second: CommandResult=x.sim.services.development.execute(x.world,"train_staff",{"staff_id":"learner","track":"surgery"})
	# Surgery has a research prerequisite; a level-one care/treatment course
	# without that prerequisite is independently selected from current rules.
	if not second.accepted:
		x.world.facts.staff.learner.abilities.treatment=0
		second=x.sim.services.development.execute(x.world,"train_staff",{"staff_id":"learner","track":"treatment"})
	x.checks.jobs_started=first.accepted and second.accepted
	var single: bool=false
	for index: int in 650:
		_step(x)
		var r: Array=x.world.facts.research_jobs.values()
		var t: Array=x.world.facts.training_jobs.values()
		if not r.is_empty() and not t.is_empty() and r[0].state=="working":
			single=t[0].desk_id.is_empty() and t[0].state=="waiting"
			break
	x.checks.one_desk_not_double_booked=single
	x.checks.second_desk=_facility(x,"desk_b","FUR05",[41,69],"research")
	var parallel: bool=false
	for index: int in 650:
		_step(x)
		var r: Array=x.world.facts.research_jobs.values()
		var t: Array=x.world.facts.training_jobs.values()
		if not r.is_empty() and not t.is_empty() and r[0].state=="working" and t[0].state=="working":
			parallel=r[0].desk_id!=t[0].desk_id and x.sim.space.at(x.world,"researcher",1,HospitalClinicalDevelopment._operator(x.sim.space.facility_layout(x.world,r[0].desk_id))) and x.sim.space.at(x.world,"learner",1,HospitalClinicalDevelopment._operator(x.sim.space.facility_layout(x.world,t[0].desk_id)))
			break
	x.checks.two_real_workers_parallel=parallel
	return _finish(x,{"research":x.world.facts.research_jobs.duplicate(true),"training":x.world.facts.training_jobs.duplicate(true)})

func _frozen_seat() -> Dictionary:
	var rows: Array=[]
	var result: bool=true
	for manual: bool in [false,true]:
		var x: Dictionary=_base()
		x.checks.room=_room(x,"rest","rest",[34,66],[20,12])
		x.checks.equipment=_facility(x,"game","RC01",[37,69],"rest")
		_staff(x,"worker","cleaner",[57,90])
		var staff: Dictionary=x.world.facts.staff.worker
		staff.schedule[0]={"kind":"rest","pools":[],"locked":false}
		staff.on_shift=false; staff.stress_milli=70000
		var accepted: CommandResult=x.sim.services.wellbeing.execute(x.world,"staff_recreation",{"staff_ids":["worker"],"facility_id":"game" if manual else ""})
		x.checks.accepted=accepted.accepted
		var old_goal: Dictionary=x.world.facts.moves.get("worker",{}).duplicate(true)
		x.checks.original_trip=not old_goal.is_empty()
		if manual: x.checks.remove=_command(x,"build_demolish",{"target_id":"game"}).accepted
		else: x.checks.move=_command(x,"build_move",{"target_id":"game","floor_id":1,"cell":[47,69]}).accepted
		staff=x.world.facts.staff.worker
		var frozen: bool=true
		for index: int in 25:
			_step(x)
			var move: Dictionary=x.world.facts.moves.get("worker",{})
			if move.is_empty(): break
			frozen=frozen and move.target_floor==old_goal.get("target_floor",0) and move.target_cell==old_goal.get("target_cell",[])
		x.checks.no_midway_chasing=frozen
		var ended: bool=false
		for index: int in 900:
			_step(x)
			if manual and staff.life_task.phase in ["returning","idle"]: ended=true;break
			if not manual and staff.life_task.phase=="recreation": ended=true;break
		x.checks.boundary_result=ended and (manual and staff.recreation_count==0 or not manual and x.world.facts.staff_life.reservations.has("game"))
		var row: Dictionary=_finish(x,{"manual":manual,"original_goal":old_goal.get("target_cell",[])})
		rows.append(row);result=result and row.ok
	return {"ok":result,"runs":rows}

func _toilets() -> Dictionary:
	var x: Dictionary=_base()
	x.checks.room=_room(x,"toilet","toilet",[34,66])
	x.checks.fixtures=_facility(x,"wc_a","FUR07",[37,69],"toilet") and _facility(x,"wc_b","FUR07",[41,69],"toilet")
	var visits: Array=[]
	for number: int in 3:
		var visit: Dictionary=_patient(x,"wc_"+str(number),[44+number*2,85+number])
		visits.append(visit)
		x.sim.services.waiting._begin_need(x.world,visit)
	x.checks.no_remote_reservation=x.world.facts.adaptations.is_empty()
	var parallel: bool=false
	var one_queue: bool=true
	var deadlines: bool=true
	var outside: bool=true
	var max_using: int=0
	for index: int in 900:
		_step(x)
		var using: int=0
		for need: Dictionary in x.world.facts.waiting_life.needs.values():
			deadlines=deadlines and int(need.started_tick)==0
			if need.phase=="using": using+=1
		max_using=maxi(max_using,using)
		for queue: Dictionary in x.world.facts.waiting_life.toilet_queues.values():
			one_queue=one_queue and queue.actor_ids.size()<=3
			for id: String in queue.actor_ids:
				var need: Dictionary=x.world.facts.waiting_life.needs[x.world.facts.visits.values().filter(func(v:Dictionary)->bool:return v.actor_id==id)[0].id]
				if need.phase!="local_wait": continue
				if x.world.facts.moves.has(id): continue
				outside=outside and not x.sim.space.room_contains(x.world.facts.rooms.toilet,x.sim.space.body_rectangle(x.world.facts.actors[id]))
		if using>=2: parallel=true;break
	x.checks.parallel_actual_use=parallel
	x.checks.one_room_queue=one_queue and x.world.facts.waiting_life.toilet_queues.keys()==["toilet"]
	x.checks.queue_outside=outside
	x.checks.original_deadline=deadlines
	return _finish(x,{"maximum_simultaneous_uses":max_using,"needs":x.world.facts.waiting_life.needs.duplicate(true),"queue":x.world.facts.waiting_life.toilet_queues.duplicate(true)})

func _water_order() -> Dictionary:
	var x: Dictionary=_base()
	x.checks.facilities=_facility(x,"water_a","FUR17",[40,82]) and _facility(x,"water_b","FUR17",[42,82])
	var first: Dictionary=_patient(x,"early",[40,80])
	var second: Dictionary=_patient(x,"late",[44,80])
	var life: HospitalWaitingLife=x.sim.services.waiting
	for visit: Dictionary in [first,second]:
		x.world.facts.waiting_life.clocks[visit.id].next_purpose="water"
		life._begin_need(x.world,visit)
	x.checks.no_remote_lock=x.world.facts.adaptations.is_empty()
	var simultaneous: bool=false
	for index: int in 200:
		_step(x)
		var active: Array=[]
		for need: Dictionary in x.world.facts.waiting_life.needs.values():
			if need.phase=="using": active.append(need.facility_id)
		if active.size()==2: simultaneous=active[0]!=active[1];break
	x.checks.free_facilities_parallel=simultaneous
	# Actual local queue inputs on overlapping regions have one global join
	# sequence. Neither the region identity nor actor type grants precedence.
	var a: Dictionary={"id":"earlier","actor_id":first.actor_id,"public_purpose":"water","area":x.sim.space.public_areas.for_facility(x.world,"water_a"),"phase":"local_wait","mode":"auto","arrived_tick":x.world.sim_tick,"facility_id":""}
	var b: Dictionary={"id":"later","actor_id":second.actor_id,"public_purpose":"water","area":x.sim.space.public_areas.for_facility(x.world,"water_b"),"phase":"local_wait","mode":"auto","arrived_tick":x.world.sim_tick,"facility_id":""}
	var probe: Dictionary=x.world.freeze()
	probe.waiting_life.needs={first.id:a,second.id:b}
	probe.adaptations={}
	var boundary:=WorldState.new(probe)
	probe.moves={}
	probe.actors[first.actor_id].location.cell=[41,80]
	probe.actors[second.actor_id].location.cell=[41,84]
	var boundary_space:=HospitalSpace.new(content)
	var area_owner:=HospitalPublicAreas.new(boundary_space)
	area_owner.join(boundary,a);area_owner.join(boundary,b)
	x.checks.shared_overlap_fifo=a.joined_seq<b.joined_seq and not area_owner.turn(boundary,b,"water_a") and not area_owner.turn(boundary,b,"water_b") and area_owner.turn(boundary,a,"water_a")
	return _finish(x,{"queue_join_sequence":[a.get("joined_seq",-1),b.get("joined_seq",-1)],"queue_probe":{"a_facilities":area_owner.facilities(boundary,a.area,["FUR17"]),"b_facilities":area_owner.facilities(boundary,b.area,["FUR17"]),"a_fit":area_owner._queue_fit(boundary,"water_a",[first.actor_id]),"a_queue":area_owner._facility_queue(boundary,"water","water_a"),"b_queue":area_owner._facility_queue(boundary,"water","water_b")}})

func _import_identity() -> Dictionary:
	var x: Dictionary=_base()
	var old: String=x.world.hospital_id
	var replacement: String=HospitalSnapshots.uuid()
	var gp: String=old+":gp"
	var office: String=old+":office"
	var personal: String=old+":personal"
	var doctor: String=old+":doctor"
	var desk: String=old+":diagnosis"
	var guide: String=old+":guide"
	x.checks.rooms=_room(x,gp,"gp",[34,66]) and _room(x,office,"doctor_office",[46,66])
	x.checks.desks=_facility(x,desk,"FUR02",[38,69],gp) and _facility(x,personal,"SE05",[50,69],office) and _facility(x,guide,"SE01",[47,83])
	_staff(x,doctor,"doctor",[55,90],gp)
	x.world.facts.doctor_desks[personal]={"staff_id":doctor}
	var visit: Dictionary=_patient(x,old+":arranged",[42,88])
	_arranged(x,visit,desk)
	var g: HospitalFloorGuidance=x.sim.services.floor_guidance
	g.can_call(x.world,visit,x.world.facts.tickets[visit.ticket_id])
	var waiting: Dictionary=_patient(x,old+":waiting",[40,88])
	var ticket: Dictionary=x.world.facts.tickets[waiting.ticket_id]
	x.world.facts.floor_guidance.next_arrival=2
	x.world.facts.floor_guidance.desks[guide]={"id":guide,"nurse_id":"","reason":"缺员","queue":[waiting.id]}
	x.world.facts.floor_guidance.visits[waiting.id]={"visit_id":waiting.id,"request_key":g._key(ticket),"ticket_id":ticket.id,"phase":"desk_queue","target_id":"","desk_id":guide,"guide_floor":1,"initial_done":false,"receipts":[],"guided_target":"","arrived_seq":-1,"reason":"","next_recheck":0,"queue_seq":2}
	var original: Dictionary=x.world.freeze()
	var rewritten: Dictionary=HospitalLibrary.new(content,null)._remap_hospital(original,old,replacement)
	var imported:=WorldState.new(rewritten)
	var imported_sim:=HospitalSimulation.new(imported,content)
	x.checks.original_read_only=x.world.freeze()==original
	x.checks.room_schedule=imported.facts.staff[replacement+":doctor"].schedule[0].pools==[replacement+":gp"]
	x.checks.personal_desk=imported.facts.doctor_desks[replacement+":personal"].staff_id==replacement+":doctor"
	x.checks.guidance_queue=imported.facts.floor_guidance.desks[replacement+":guide"].queue==[replacement+":waiting"]
	x.checks.clinical_queue=imported.facts.floor_guidance.clinic_queues[replacement+":gp"].visit_ids==[replacement+":arranged"] and imported.facts.floor_guidance.clinic_queues[replacement+":gp"].deadline_tick==300
	x.checks.original_room_identity=imported.facts.floor_guidance.visits[replacement+":arranged"].target_room_id==replacement+":gp"
	x.checks.imported_world_valid=imported.validate(content).is_empty()
	var import_error: String=imported.validate(content)
	imported_sim.dispose()
	return _finish(x,{"import_validation":import_error})

func _treatment_parallel() -> Dictionary:
	var x: Dictionary=_base()
	x.checks.room=_room(x,"treatment","treatment",[34,66],[22,12])
	x.checks.equipment=_facility(x,"machine_a","M09",[36,68],"treatment") and _facility(x,"machine_b","M37",[48,68],"treatment") and _facility(x,"diagnostic","FUR02",[42,68],"treatment")
	_staff(x,"doctor_a","doctor",[36,85],"treatment")
	_staff(x,"doctor_b","doctor",[39,85],"treatment")
	_staff(x,"nurse","nurse",[42,85],"treatment")
	x.world.facts.staff.nurse.base_prepared=true
	var a: Dictionary=_patient(x,"treatment_a",[45,85],"outpatient","B_S13_D09_M09")
	var b: Dictionary=_patient(x,"treatment_b",[48,85],"outpatient","B_S49_D37_M37")
	var exam: Dictionary=_patient(x,"examination",[51,85],"spectrum","B_S13_D09_M09")
	a.evidence_by_source={"gp":100};b.evidence_by_source={"gp":100};exam.evidence_by_source={"gp":42}
	var accepted: bool=true
	for visit: Dictionary in [a,b]:
		var result: CommandResult=x.sim.clinic.execute(x.world,"clinical_select_plan",{"visit_id":visit.id,"plan_id":visit.requested_plan_id})
		accepted=accepted and result.accepted
	_arranged(x,a,"machine_a",true);_arranged(x,b,"machine_b",true);_arranged(x,exam,"diagnostic",true)
	x.checks.legal_plan_quotes=accepted
	var parallel: bool=false
	var same_person: bool=false
	var maximum: int=0
	for index: int in 650:
		_step(x)
		maximum=maxi(maximum,x.world.facts.sessions.size())
		var busy: Dictionary={}
		for session: Dictionary in x.world.facts.sessions.values():
			for id: String in session.staff_ids:
				if busy.has(id): same_person=true
				busy[id]=session.facility_id
		if x.world.facts.sessions.size()==3:
			parallel=busy.size()==3 and busy.get("nurse","")=="diagnostic"
			break
	x.checks.three_devices_work_in_parallel=parallel
	x.checks.one_worker_one_device=not same_person
	x.checks.nurse_not_gp=not x.sim.clinic._service_qualified(x.world,x.world.facts.staff.nurse,"gp") and not x.sim.clinic._service_qualified(x.world,x.world.facts.staff.nurse,"outpatient")
	return _finish(x,{"maximum_simultaneous_sessions":maximum,"sessions":x.world.facts.sessions.duplicate(true)})

func _amenity_handoffs() -> Dictionary:
	var runs: Array=[_nurse_amenity_handoff(),_doctor_amenity_handoff()]
	return {"ok":runs.all(func(row:Dictionary)->bool:return row.ok),"runs":runs}

func _nurse_amenity_handoff() -> Dictionary:
	var x: Dictionary=_base()
	x.checks.room=_room(x,"gp","gp",[34,66]) and _facility(x,"diagnosis","FUR02",[38,69],"gp")
	x.checks.facilities=_facility(x,"guide","SE01",[47,83]) and _facility(x,"base","SE06",[55,80]) and _facility(x,"water","FUR17",[58,84])
	_staff(x,"nurse","nurse",[55,90])
	_staff(x,"doctor","doctor",[59,90],"gp")
	var visit: Dictionary=_patient(x,"handoff",[42,90])
	var prepare_ticks: int=0
	var prepare_at_base: bool=true
	var deferred: bool=false
	var requested: bool=false
	var safe_guidance: bool=true
	var prepared_kept: bool=true
	var used: bool=false
	var use_started: int=-1
	var use_ticks: int=-1
	var returned: bool=false
	var g: HospitalFloorGuidance=x.sim.services.floor_guidance
	for index: int in 1600:
		var before: Dictionary=x.world.facts.staff.nurse.get("base_task",{}).duplicate(true)
		if not deferred and before.get("phase","")=="working" and int(before.remaining_ticks)==40:
			var frozen: Dictionary=x.world.freeze()
			deferred=not x.sim.services.wellbeing.begin_amenity(x.world,"nurse","water") and frozen==x.world.freeze()
		var state_before: Dictionary=g.state(x.world,visit.id)
		if not requested and state_before.get("phase","")=="working" and int(state_before.remaining_ticks)==30:
			requested=x.sim.services.wellbeing.begin_amenity(x.world,"nurse","water")
			var frozen: Dictionary=x.world.freeze()
			x.checks.one_pending_need=not x.sim.services.wellbeing.begin_amenity(x.world,"nurse","toilet") and frozen==x.world.freeze()
		_step(x)
		var staff: Dictionary=x.world.facts.staff.nurse
		if before.has("remaining_ticks"):
			# Dispatch may begin work and consume its first tick in this same
			# step, while the pre-step task was still labelled travel.
			var remaining: int=int(staff.get("base_task",{}).get("remaining_ticks",0 if staff.get("base_prepared",false) else before.remaining_ticks))
			var worked: int=int(before.remaining_ticks)-remaining
			prepare_ticks+=worked
			if worked>0:
				var base: Dictionary=x.sim.space.facility_layout(x.world,"base")
				prepare_at_base=prepare_at_base and x.sim.space.at(x.world,"nurse",1,base.operator_cells[0]) and not x.world.facts.moves.has("nurse")
		var state: Dictionary=g.state(x.world,visit.id)
		if requested and state.get("phase","")=="working":
			var desk: Dictionary=x.sim.space.facility_layout(x.world,"guide")
			safe_guidance=safe_guidance and staff.life_task.phase=="wait_safe" and x.sim.space.at(x.world,"nurse",1,desk.operator_cells[0])
		if requested: prepared_kept=prepared_kept and staff.get("base_prepared",false)
		if staff.life_task.phase=="using":
			used=true;use_started=int(staff.life_task.use_started_tick)
		elif used and use_ticks<0: use_ticks=x.world.sim_tick-use_started
		if used and staff.life_task.phase=="idle": returned=true;break
	var reposted: bool=false
	for index: int in 500:
		_step(x)
		var staff: Dictionary=x.world.facts.staff.nurse
		prepared_kept=prepared_kept and staff.get("base_prepared",false)
		if staff.get("active_job_id","")=="floor_desk:guide" and not x.world.facts.moves.has("nurse") and x.sim.space.at(x.world,"nurse",1,x.sim.space.guidance_operator_cell(x.world,"guide","nurse")):
			reposted=true;break
	var receipts: Array=g.state(x.world,visit.id).get("receipts",[])
	x.checks.initial_prepare_protected=deferred
	x.checks.actual_original_prepare=prepare_at_base and prepare_ticks==60
	x.checks.original_guidance_completed=requested and safe_guidance and receipts.size()>=1 and int(receipts[0].completed_tick)-int(receipts[0].started_tick)+1==60
	x.checks.actual_amenity_and_return=used and use_ticks==80 and returned and reposted
	x.checks.same_work_segment=prepared_kept and x.world.facts.staff.nurse.base_task.is_empty() and x.world.facts.staff.nurse.last_rest_end_tick==0
	return _finish(x,{"role":"nurse","prepare_ticks":prepare_ticks,"use_ticks":use_ticks,"receipts":receipts.duplicate(true)})

func _doctor_amenity_handoff() -> Dictionary:
	var x: Dictionary=_base()
	x.checks.room=_room(x,"gp","gp",[34,66]) and _facility(x,"desk","FUR02",[38,69],"gp")
	x.checks.water=_facility(x,"water","FUR17",[50,84])
	_staff(x,"doctor","doctor",[55,90],"gp")
	var visit: Dictionary=_patient(x,"clinical_handoff",[38,79])
	_arranged(x,visit,"desk")
	for index: int in 700:
		_step(x)
		if not x.world.facts.sessions.is_empty(): break
	var sessions: Array=x.world.facts.sessions.values()
	var session: Dictionary=sessions[0].duplicate(true) if not sessions.is_empty() else {}
	var safe: bool=true
	x.checks.requested_after_actual_start=not session.is_empty() and x.sim.services.wellbeing.begin_amenity(x.world,"doctor","water")
	var used: bool=false
	var finished: bool=false
	for index: int in 1000:
		_step(x)
		var staff: Dictionary=x.world.facts.staff.doctor
		if x.world.facts.sessions.has(session.get("id","")):
			var table: Dictionary=x.sim.space.facility_layout(x.world,"desk")
			safe=safe and staff.life_task.phase=="wait_safe" and x.sim.space.at(x.world,"doctor",1,table.operator_cells[0])
		used=used or staff.life_task.phase=="using"
		if used and staff.life_task.phase=="idle": finished=true;break
	x.checks.safe_original_clinical_work=safe and not session.is_empty() and not x.world.facts.sessions.has(session.id) and int(x.events.get("service_completed",0))==1
	x.checks.one_original_charge=x.world.facts.ledger.entries.has(visit.id+":gp") and x.world.facts.ledger.entries.has(visit.id+":consultation") and x.sim.services.experience.receipt(x.world,visit.id).charges.size()==2
	x.checks.amenity_after_release=used and finished and x.world.facts.staff.doctor.last_rest_end_tick==0
	return _finish(x,{"role":"doctor","original_session":session})

func _shared_amenities() -> Dictionary:
	var rows: Array=[]
	var ok: bool=true
	for purpose: String in ["water","toilet"]:
		for employee_first: bool in [true,false]:
			var x: Dictionary=_base()
			if purpose=="toilet":
				x.checks.room=_room(x,"toilet","toilet",[34,66])
				x.checks.facility=_facility(x,"shared","FUR07",[37,69],"toilet")
			else: x.checks.facility=_facility(x,"shared","FUR17",[40,82])
			var near: Array=[40,85] if purpose=="water" else [39,79]
			var far: Array=[53,90]
			_staff(x,"employee","cleaner",near if employee_first else far)
			var patient: Dictionary=_patient(x,"shared_patient",far if employee_first else near)
			x.world.facts.waiting_life.clocks[patient.id].next_purpose=purpose
			x.sim.services.waiting._begin_need(x.world,patient)
			x.checks.employee_need_started=x.sim.services.wellbeing.begin_amenity(x.world,"employee",purpose)
			x.checks.no_remote_lock=x.world.facts.adaptations.is_empty()
			var employee_need: Dictionary=x.world.facts.staff.employee.life_task
			var patient_need: Dictionary=x.world.facts.waiting_life.needs[patient.id]
			var first: String=""
			var actual: bool=true
			var unique: bool=true
			var completed: Dictionary={}
			var seen: Dictionary={}
			var restored: bool=false
			var restored_equal: bool=true
			for index: int in 1000:
				if not restored and employee_need.phase=="using" and int(employee_need.remaining_ticks)==40:
					var copy:=WorldState.new(x.world.freeze().duplicate(true))
					var copy_sim:=HospitalSimulation.new(copy,content)
					_step(x);copy_sim.step()
					restored_equal=x.world.freeze()==copy.freeze()
					copy_sim.dispose();restored=true
				else: _step(x)
				var users: int=0
				for actor_id: String in ["employee",patient.actor_id]:
					var need: Dictionary=employee_need if actor_id=="employee" else patient_need
					if need.phase=="using":
						users+=1
						if first.is_empty(): first=actor_id
						seen[actor_id]=true
						var layout: Dictionary=x.sim.space.facility_layout(x.world,"shared")
						actual=actual and x.sim.space.at(x.world,actor_id,int(layout.floor_id),layout.patient_cell) and not x.world.facts.moves.has(actor_id)
					elif seen.has(actor_id) and not completed.has(actor_id): completed[actor_id]=x.world.sim_tick-int(need.use_started_tick)
				unique=unique and users<=1
				if completed.size()==2 and x.world.facts.staff.employee.life_task.phase=="idle" and not x.world.facts.waiting_life.needs.has(patient.id): break
			x.checks.real_shared_use=actual and completed.size()==2
			x.checks.actual_arrival_fifo=first==("employee" if employee_first else patient.actor_id)
			x.checks.no_double_use=unique
			x.checks.complete_eight_seconds=completed.size()==2 and completed.values().all(func(ticks:Variant)->bool:return int(ticks)==80)
			x.checks.real_safe_exit=x.world.facts.staff.employee.life_task.phase=="idle" and not x.world.facts.waiting_life.needs.has(patient.id) and not x.world.facts.adaptations.has("shared")
			x.checks.amenity_is_not_rest=x.world.facts.staff.employee.last_rest_end_tick==0 and x.world.facts.staff.employee.awake_ticks==x.steps
			x.checks.cold_use_preserved=restored and restored_equal
			var row: Dictionary=_finish(x,{"purpose":purpose,"employee_first":employee_first,"first_user":first,"completed_use_ticks":completed})
			rows.append(row);ok=ok and row.ok
	return {"ok":ok,"runs":rows,"trigger_scope":"legal need input; does not assert an employee automatic need clock"}

func _same_equipment_parallel() -> Dictionary:
	var x: Dictionary=_base()
	x.checks.room=_room(x,"treatment","treatment",[34,66],[22,12])
	x.checks.equipment=_facility(x,"machine_a","M09",[36,68],"treatment") and _facility(x,"machine_b","M09",[48,68],"treatment")
	_staff(x,"doctor_a","doctor",[36,85],"treatment")
	_staff(x,"doctor_b","doctor",[39,85],"treatment")
	var accepted: bool=true
	for row: Array in [["first",[45,85]],["second",[48,85]]]:
		var visit: Dictionary=_patient(x,row[0],row[1],"outpatient","B_S13_D09_M09")
		visit.evidence_by_source={"gp":100}
		accepted=accepted and x.sim.clinic.execute(x.world,"clinical_select_plan",{"visit_id":visit.id,"plan_id":visit.requested_plan_id}).accepted
		_arranged(x,visit,"machine_a")
	x.checks.legal_plan_quotes=accepted
	var parallel: bool=false
	var same_person: bool=false
	for index: int in 900:
		_step(x)
		var busy: Dictionary={}
		var devices: Dictionary={}
		for session: Dictionary in x.world.facts.sessions.values():
			devices[session.facility_id]=true
			for id: String in session.staff_ids:
				if busy.has(id): same_person=true
				busy[id]=true
		if devices.size()==2:
			parallel=devices.has("machine_a") and devices.has("machine_b") and busy.size()==2
			break
	x.checks.same_type_real_parallel=parallel
	x.checks.one_worker_one_device=not same_person
	x.checks.same_arranged_room=x.sim.services.floor_guidance.target(x.world,"first")=="machine_a" and x.sim.services.floor_guidance.target(x.world,"second")=="machine_a"
	return _finish(x,{"sessions":x.world.facts.sessions.duplicate(true)})

func _bed_fallback() -> Dictionary:
	var rows: Array=[]
	var ok: bool=true
	for blocked: bool in [false,true]:
		var x: Dictionary=_base()
		x.checks.rooms=_room(x,"dorm","dormitory",[34,66]) and _room(x,"rest_a","rest",[46,66]) and _room(x,"rest_b","rest",[34,78])
		x.checks.bed=_facility(x,"personal","SE04",[37,69],"dorm")
		x.checks.sofas=_facility(x,"sofa_a","FUR06",[49,69],"rest_a") and _facility(x,"sofa_b","FUR06",[37,81],"rest_b")
		_staff(x,"owner","cleaner",[55,90])
		x.sim.services.wellbeing.ensure(x.world)
		x.checks.personal_owner=x.world.facts.staff_life.personal_beds.get("personal",{}).get("staff_id","")=="owner"
		_staff(x,"resting","cleaner",[52,80])
		x.world.facts.staff.resting.energy=20.0
		var occupied: bool=false
		for index: int in 500:
			_step(x)
			if x.world.facts.staff.resting.life_task.phase=="rest":
				occupied=x.world.facts.staff.resting.life_task.facility_id=="sofa_a"; break
		x.checks.first_room_seat_really_occupied=occupied
		if blocked:
			x.checks.walls=_command(x,"build_wall",{"edges":[{"axis":"x","line":65,"low":33,"high":45},{"axis":"x","line":77,"low":33,"high":45},{"axis":"y","line":33,"low":65,"high":77},{"axis":"y","line":45,"low":65,"high":77}]}).accepted
			x.checks.bed_really_unreachable=not x.sim.space.travel_quote(x.world,"owner",1,x.sim.space.facility_layout(x.world,"personal").patient_cell).ok
		else:
			x.world.facts.facilities.personal.failed=true
			x.world.touch(false)
		var staff: Dictionary=x.world.facts.staff.owner
		staff.awake_ticks=ceili(float(content.balance.staff_sleep.awake_limit_seconds)/WorldState.TICK_SECONDS)
		var sleeping: bool=false
		for index: int in 1000:
			_step(x)
			if x.world.facts.staff.owner.life_task.phase=="sleep": sleeping=true;break
		x.checks.other_rest_room_used=sleeping and x.world.facts.staff.owner.life_task.facility_id=="sofa_b" and x.world.facts.actors.owner.support_facility_id=="sofa_b"
		x.checks.owner_never_changes=x.world.facts.staff_life.personal_beds.get("personal",{}).get("staff_id","")=="owner"
		var row: Dictionary=_finish(x,{"blocked_route":blocked})
		rows.append(row);ok=ok and row.ok
	return {"ok":ok,"runs":rows}

func _tea() -> Dictionary:
	var rows: Array=[]
	var ok: bool=true
	for tiny: bool in [false,true]:
		var x: Dictionary=_base()
		x.checks.room=_command(x,"build_room",{"id":"rest","room_type_id":"rest","origin":[34,66],"size":[1,1] if tiny else [10,10],"door":{"definition_id":"DR01","edge":"south","offset":0}}).accepted
		_staff(x,"worker","cleaner",[55,90])
		x.world.facts.staff.worker.energy=20.0
		var actual: bool=false
		var no_remote_recovery: bool=true
		for index: int in (4 if tiny else 600):
			_step(x)
			var staff: Dictionary=x.world.facts.staff.worker
			if staff.life_task.phase=="rest":
				var actor: Dictionary=x.world.facts.actors.worker
				actual=staff.life_task.get("tea",false) and x.sim.space.room_contains(x.world.facts.rooms.rest,x.sim.space.body_rectangle(actor)) and x.sim.space.public_areas.safe_wait(x.world,"worker",1,actor.location.cell)
				break
			no_remote_recovery=no_remote_recovery and float(staff.energy)<=20.0
		if tiny: x.checks.no_position_no_fake_rest=not actual and x.world.facts.staff.worker.life_task.phase=="idle" and x.world.facts.staff.worker.energy<=20.0
		else: x.checks.real_tea_without_equipment=actual and x.world.facts.facilities.is_empty()
		x.checks.no_remote_recovery=no_remote_recovery
		var row: Dictionary=_finish(x,{"tiny":tiny})
		rows.append(row);ok=ok and row.ok
	return {"ok":ok,"runs":rows}

func _trail_boundary() -> Dictionary:
	var source: Array=[[45.20000076293945,73.80000305175781],[45.20000076293945,74.0],[47.0,74.0]]
	var convoy: Dictionary={"version":1,"points":source.duplicate(true),"spacing":2.0,"size":1,"centers":{"leader":[0.0,0.0],"follower":[0.0,0.0]},"floor_id":1,"shift":0.0,"height":1.75}
	var end:=Vector2(47.0,73.80000305175781)
	var result: Dictionary=ConvoyTrail.propose(convoy,end)
	var valid: bool=result.ok
	for index: int in range(1,result.get("points",[]).size()):
		var delta: Vector2=ConvoyTrail.point(result.points[index])-ConvoyTrail.point(result.points[index-1])
		valid=valid and delta.length()>=0.000001 and (absf(delta.x)<=0.00001 or absf(delta.y)<=0.00001)
	var checks: Dictionary={"accepted_original_movement":result.ok,"nonzero_orthogonal_trail":valid,"keeps_corner_and_endpoint":result.get("points",[])==[[45.20000076293945,74.0],[47.0,74.0],[47.0,73.80000305175781]],"same_legal_length":absf(ConvoyTrail.length(result.get("points",[]))-2.0)<0.001,"input_read_only":convoy.points==source}
	return {"ok":checks.values().all(func(v:Variant)->bool:return v==true),"checks":checks,"proposal":result,"input_kind":"legal float32 boundary calculation; actual transfer and cold restore use full clinical chain"}
