extends RefCounted

# Golden values in these cases come from clinical.md and the cited design/data.
# Production queries are the actual side of each assertion, never the oracle.
const CASES: Dictionary = {
	"CLIN-01":"docs/design/12-implementation-plan.md §10.1–10.2；真实接待6秒，Actor/Visit/原票只建一次",
	"CLIN-02":"docs/design/07-clinical-team.md §9、§14、§17；诊断池与治疗池由不同实际医生安全交接，D09首试成功实收235",
	"CLIN-03":"docs/design/01-simulation.md §4；C档证据42→77→102，检查各一次且不领包",
	"CLIN-04":"docs/design/07-clinical-team.md §14；诊断3/奇想台49.2→93，省略共振全部副作用",
	"CLIN-05":"docs/design/07-clinical-team.md §14；初诊按开工职称冻结，重复完成不重收25",
	"CLIN-06":"docs/design/01-simulation.md §4；临床§6、§16；报价只读，常规/舒缓从同一未取整工时分别最终ceil一次",
	"CLIN-07":"docs/design/07-clinical-team.md §5–6；C档能力/住院研究/覆盖不足不能开工",
	"CLIN-08":"docs/design/04-technical.md §6、§10；缺包不消费，补货按原票开工且不另扣采购现金",
	"CLIN-09":"docs/design/07-clinical-team.md §15；首败自动接第二次，重试+15个百分点夹98%，初诊不重收",
	"CLIN-10":"docs/design/07-clinical-team.md §14–15、§17；D09两次失败实收45、领2包、无第三次",
	"CLIN-11":"docs/design/07-clinical-team.md §6、§15；院长指定舒缓在短缺及首败后保留意图",
	"CLIN-12":"docs/design/01-simulation.md §1、§4；暂停与流式恢复保留Attempt、余量、随机流、费用和领包",
	"CLIN-13":"docs/design/07-clinical-team.md §14；D09舒缓治愈费220、D14手术1080，快照不随后改重算",
	"CLIN-14":"docs/design/07-clinical-team.md §5、§8；三位互异术组及另一位病区覆盖护士缺一不可",
	"CLIN-15":"docs/design/07-clinical-team.md §8；准备原子预留8包/床/团队，开术前不领包、不计尝试",
	"CLIN-16":"docs/design/07-clinical-team.md §8；取消/30秒到齐过期释放未承诺资源，保留原票",
	"CLIN-17":"docs/design/04-technical.md §10；两术室争一床，原票序只允许一个完整资源束",
	"CLIN-18":"docs/design/07-clinical-team.md §5、§8；开术冻结结果/120秒/180秒及四段15/45/25/15，恢复不重领",
	"CLIN-19":"docs/design/07-clinical-team.md §8、§14；术毕仍须15秒苏醒，完成才收60且不提前治愈",
	"CLIN-20":"docs/design/07-clinical-team.md §8；手术护士真实陪同转床，同Attempt交接床承诺",
	"CLIN-21":"docs/design/07-clinical-team.md §8；术中待故障安全完成，原结果/工时/领包不变",
	"CLIN-22":"docs/design/07-clinical-team.md §8.1；实际病房覆盖才推进，缺员/故障/暂停为0",
	"CLIN-23":"docs/design/07-clinical-team.md §8.1；同床双护士不加倍，每人不同时做两项主动护理",
	"CLIN-24":"docs/design/07-clinical-team.md §8.1、§14；8秒护理和10秒合格查房全部完成才收床费/治愈费",
	"CLIN-25":"docs/design/07-clinical-team.md §8.1、§10；安全换床保留标准余量/护理，回原床不重复磨损/收费",
	"CLIN-26":"docs/design/07-clinical-team.md §8；床故障无备用120秒安全转诊，只保留已完成术台60",
	"CLIN-27":"docs/design/07-clinical-team.md §8.1；缺员120秒提示/300秒转诊，改派走路不重置无进展",
	"CLIN-28":"docs/design/07-clinical-team.md §10、§14；住院各边界流式恢复保留护理/查房/最终唯一结算",
	"CLIN-29":"docs/design/07-clinical-team.md §5、§8、§14；C舒缓真实180秒恢复和查房后收60+660，领4包",
	"CLIN-30":"docs/design/07-clinical-team.md §8.2；无等候点仅有请求，条件齐备后独立亲友从入口真实到院",
	"CLIN-31":"docs/design/07-clinical-team.md §8.2；每窗口意向一次，换床/恢复不重抽，实际床边才起30秒",
	"CLIN-32":"docs/design/07-clinical-team.md §8.2；拒绝/医疗让位/出院安全退出，原停留不重启且空间不早释放"
}

const SELECTABLE_CASES: Array[String] = ["CLIN-13","CLIN-22","CLIN-24","CLIN-27","CLIN-29","CLIN-32"]

var _content: HospitalContent
var _simulations: Array[HospitalSimulation] = []
var _snapshots: Dictionary = {}
var _fixture_sequence: int = 0
var _fixture_failures: Array = []

func run(t) -> void:
	if not _initialize_content(t,CASES.keys()): return
	await _ordinary_chain(t)
	await _diagnosis_chain(t,false)
	await _diagnosis_chain(t,true)
	await _quotes_and_shortage(t)
	await _retry_and_restore(t)
	await _surgery_chain(t)
	await _surgical_boundaries(t)
	await _ward_boundaries(t)
	await _visitor_boundaries(t)
	_dispose_simulations()

func run_selected(t, ids: Array) -> void:
	var selected: Array[String] = []
	for requested: Variant in ids:
		var case_id: String = str(requested)
		if selected.has(case_id): continue
		selected.append(case_id)
	if not _initialize_content(t,selected): return
	if selected.has("CLIN-13"):
		await _ordinary_queue(t)
		await _fee_snapshots(t)
	if selected.has("CLIN-22") or selected.has("CLIN-24") or selected.has("CLIN-27") or selected.has("CLIN-32"):
		await _surgery_to_care(t,false)
		if selected.has("CLIN-22"): await _ward_coverage(t)
		if selected.has("CLIN-24"): await _ward_round(t)
		if selected.has("CLIN-27"): await _ward_shortage(t)
	if selected.has("CLIN-29"): await _gentle_ward(t)
	if selected.has("CLIN-32"):
		await _companion_entry(t)
		await _visitor_bedside(t)
		await _visitor_exit(t)
	for case_id: String in selected:
		if not case_id in SELECTABLE_CASES:
			t.check(case_id,false,{"unsupported_clinical_target":case_id,"supported":SELECTABLE_CASES})
	_dispose_simulations()

func _initialize_content(t, case_ids: Array) -> bool:
	_content = HospitalContent.new()
	if not _content.error.is_empty():
		for case_id: String in case_ids:
			t.check(case_id,false,{"content_error":_content.error})
		return false
	return true

func _dispose_simulations() -> void:
	for simulation: HospitalSimulation in _simulations:
		simulation.dispose()
	_simulations.clear()

func _context(surgical: bool = false, c_profile: bool = false, chairs: bool = true) -> Dictionary:
	_fixture_sequence += 1
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"临床验收%04d"%_fixture_sequence,true,_content)
	var doctors: Array = []
	for id: String in world.ids("staff"):
		var staff: Dictionary = world.facts.staff[id]
		if staff.role=="doctor": doctors.append(id)
		if staff.role in ["doctor","nurse"]:
			staff.base_prepared = true # Fixture starts in an already prepared work block.
			staff.personality_id = "DP05"
			staff.schedule = _schedule("outpatient" if staff.role=="doctor" else "work")
	for index: int in doctors.size():
		var doctor: Dictionary = world.facts.staff[doctors[index]]
		if index==0:
			doctor.schedule[0].pools = ["diagnosis"]
		elif index==1:
			doctor.schedule[0].pools = ["T01","T05"]
			doctor.abilities.treatment = 2 if c_profile or surgical else 1
		else:
			doctor.schedule = _schedule("rest")
	if c_profile or surgical:
		for definition: Dictionary in _content.catalog.research:
			world.facts.research.append(definition.id)
	if not chairs:
		for id: String in world.ids("facilities"):
			if world.facts.facilities[id].definition_id=="FUR09": world.facts.facilities.erase(id)
	if surgical:
		_add_layout(world,"or_standard","clin_or",[33,65])
		_add_layout(world,"ward_two_beds","clin_ward",[45,65])
		_add_worker(world,"clin_surgeon","doctor",[34,75],"surgery",{"diagnosis":1,"treatment":1,"care":0,"surgery":2},"DT02")
		_add_worker(world,"clin_anesthesia","doctor",[38,75],"surgery",{"diagnosis":1,"treatment":1,"care":0,"surgery":2},"DT02")
		_add_worker(world,"clin_or_nurse","nurse",[42,75],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":1})
		world.facts.staff.clin_or_nurse.certificates = ["q_or","q_ward"]
		_add_worker(world,"clin_cover","nurse",[46,72],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":0})
		world.facts.staff.clin_cover.ward_id = "clin_ward"
		_add_worker(world,"clin_round","doctor",[51,72],"round",{"diagnosis":2,"treatment":1,"care":0,"surgery":0})
	var simulation: HospitalSimulation = HospitalSimulation.new(world,_content)
	simulation.clinic.departments = null # Department routing is covered by OPS acceptance.
	_simulations.append(simulation)
	var c: Dictionary = {"sim":simulation,"world":world,"serial":0,"visit_id":"","doctors":doctors,"started":{},"group_seen":false,"beats":{},"errors":[],"fixture_ready":true}
	_command(c,"set_intake_open",{"open":false})
	_command(c,"tutorial_set_enabled",{"enabled":false})
	_command(c,"set_auto_restock",{"enabled":false})
	_fixture_arrival_plan(world)
	_fixture_preflight(c,c_profile,surgical)
	_tick(c)
	_seed_stream(world,"arrival",false,true,2500,5000)
	return c

func _fixture_preflight(c: Dictionary, c_profile: bool, surgical: bool) -> void:
	var binding_id: String = "B_S22_D14_M14" if c_profile else "B_S13_D09_M09"
	var disease_id: String = "D14" if c_profile else "D09"
	var binding: Dictionary = _content.definition("treatment_bindings",binding_id)
	var disease: Dictionary = _content.definition("diseases",disease_id)
	var routine: Dictionary = _content.definition("treatment_routines",str(binding.get("routine_id","")))
	var plan: Dictionary = _content.definition("treatment_plans","P_"+disease_id+"_COMMON")
	var missing: Array = []
	if binding.is_empty() or binding.get("disease_id","")!=disease_id or _content.definition("species",str(binding.get("species_id",""))).is_empty(): missing.append("病例、种族或疾病绑定不完整："+binding_id)
	if disease.is_empty() or routine.is_empty() or plan.get("disease_id","")!=disease_id or _content.definition("treatment_protocols",str(plan.get("protocol_id",""))).is_empty(): missing.append("疾病、治疗流程或常规协议定义不完整")
	if routine.get("equipment_id","")!="M09": missing.append("本病例的权威治疗主体不是预期M09")
	if not HospitalResearch.disease_unlocked(c.world,_content,disease_id): missing.append("本病例研究尚未完成："+disease_id)
	var required: Array = ["FUR01","FUR02","M09"]
	if surgical: required.append_array(["EQ01","EQ05","SE06"])
	for definition_id: String in required:
		var placed: bool = false
		for facility: Dictionary in c.world.facts.facilities.values():
			if facility.definition_id!=definition_id or int(facility.floor_id)!=1 or bool(facility.failed): continue
			var room_id: String = str(facility.get("room_id",""))
			if definition_id in ["FUR02","M09","EQ01","EQ05"] and not c.world.facts.rooms.has(room_id): continue
			placed = true
		if not placed: missing.append("缺少实际摆放且有合法房间的设施："+definition_id)
	var research_ids: Array = ["R11"] if c_profile else []
	if surgical: research_ids.append_array(["R33","R34"])
	for research_id: String in research_ids:
		if not research_id in c.world.facts.research: missing.append("缺少正式前置研究："+research_id)
	if surgical:
		var adapter_found: bool = false
		for adapter: Dictionary in _content.catalog.surgical_adapters:
			if adapter.binding_id==binding_id and adapter.plan_id=="P_"+disease_id+"_SURGERY": adapter_found = true
		if not adapter_found: missing.append("缺少本病例的正式手术适配")
	c.fixture_preflight = {"hospital_id":c.world.hospital_id,"binding_id":binding_id,"required_equipment":required,"missing":missing}
	if not missing.is_empty(): _fixture_failure(c,c.fixture_preflight)

func _fixture_failure(c: Dictionary, reason: Dictionary) -> void:
	c.fixture_ready = false
	c.errors.append({"fixture_prerequisite":reason.duplicate(true)})
	_fixture_failures.append(reason.duplicate(true))
	print("CLINICAL FIXTURE FAIL "+JSON.stringify(reason))

func _fixture_arrival_plan(world: WorldState) -> void:
	# Clinical fixtures own their explicit patients; daily capacity is covered by growth.
	var arrivals: Dictionary = world.facts.arrivals
	arrivals.intake_open = false
	var day: int = world.sim_tick/WorldState.TICKS_PER_DAY+1
	if int(arrivals.plan.get("day_index",-1))==day: return
	var zero: Dictionary = {"n":"0","d":"1"}
	arrivals.plan = {"day_index":day,"preset":"normal","scale_numerator":0,
		"shift_capacities":[zero.duplicate(),zero.duplicate(),zero.duplicate()],
		"opportunity_count":0,"shift_opportunity_counts":[0,0,0],"schedule_seed":null,
		"schedule_algorithm":str(_content.balance.arrivals.schedule.algorithm),"next_slot_index":0,
		"held_capacity_fraction":zero.duplicate(),"held_scale_numerator":0}

func _schedule(kind: String) -> Array:
	return [{"kind":kind,"pools":[],"locked":false},{"kind":kind,"pools":[],"locked":false},{"kind":"rest","pools":[],"locked":false}]

func _add_worker(world: WorldState, id: String, role: String, position: Array, duty: String, abilities: Dictionary, title: String = "DT01") -> void:
	HospitalFactory._add_staff(world,id,id,role,position,_content)
	var staff: Dictionary = world.facts.staff[id]
	staff.abilities = abilities.duplicate(true)
	staff.title_id = title if role=="doctor" else ""
	staff.base_prepared = true
	staff.personality_id = "DP05"
	staff.schedule = _schedule(duty)
	staff.on_shift = duty!="rest"

func _add_layout(world: WorldState, layout_id: String, room_id: String, origin: Array) -> void:
	var layout: Dictionary = {}
	for candidate: Dictionary in _content.layouts.layouts:
		if candidate.id==layout_id: layout = candidate
	if layout.is_empty(): return
	HospitalFactory._add_room(world,{"id":room_id,"type":layout.room_type_id,"anchor":origin,"size":layout.size,
		"door":{"definition_id":layout.door_id,"offset":layout.door_offset}},_content)
	var bed_index: int = 0
	for index: int in layout.objects.size():
		var item: Dictionary = layout.objects[index]
		var definition: Dictionary = _content.facility_definition(item.definition_id)
		var id: String = room_id+"_"+str(index)
		var cell: Array = [int(origin[0])+int(item.anchor[0]),int(origin[1])+int(item.anchor[1])]
		HospitalFactory._add_facility(world,{"id":id,"definition_id":item.definition_id,"anchor":cell,"size":definition.footprint,"room_id":room_id},_content)
		var facility: Dictionary = world.facts.facilities[id]
		if item.definition_id=="EQ01":
			facility.patient_cell = _layout_point(layout,"patient_staging",origin)
			facility.operator_cells = [_layout_point(layout,"surgeon",origin),_layout_point(layout,"anesthetist",origin),_layout_point(layout,"nurse",origin)]
			facility.repair_cell = [int(origin[0])+int(layout.repair_points[0][0]),int(origin[1])+int(layout.repair_points[0][1])]
		elif item.definition_id=="EQ05":
			bed_index += 1
			facility.patient_cell = _layout_point(layout,"patient_staging_"+str(bed_index),origin)
			var care: Array = _layout_point(layout,"care_"+str(bed_index),origin)
			# The second doctor's point remains in the one-cell aisle, inside this ward.
			facility.operator_cells = [care,[int(origin[0])+4,int(origin[1])+(1 if bed_index==1 else 3)]]
			facility.repair_cell = [int(origin[0])+int(layout.repair_points[bed_index-1][0]),int(origin[1])+int(layout.repair_points[bed_index-1][1])]
		elif item.definition_id=="SE06":
			facility.operator_cells = [_layout_point(layout,"nurse_base",origin)]

func _layout_point(layout: Dictionary, kind: String, origin: Array) -> Array:
	for point: Dictionary in layout.service_points:
		if point.kind==kind: return [int(origin[0])+int(point.anchor[0]),int(origin[1])+int(point.anchor[1])]
	return []

func _command(c: Dictionary, kind: String, payload: Dictionary) -> CommandResult:
	c.serial = int(c.serial)+1
	return c.sim.apply(GameCommand.new("clinical_command_"+str(c.serial),c.world.hospital_id,c.world.revision,kind,BusinessPayload.new(payload)))

func _arrive(c: Dictionary, binding: String = "B_S13_D09_M09", plan: String = "P_D09_COMMON", allow_visitors: bool = false) -> bool:
	if not bool(c.get("fixture_ready",true)): return false
	var result: CommandResult = _command(c,"clinical_arrive",{"arrival_key":"patient-"+str(c.serial),"binding_id":binding,"requested_plan_id":plan,"personality_id":"PP01","expression":"clear"})
	if not result.accepted:
		_fixture_failure(c,{"hospital_id":c.world.hospital_id,"binding_id":binding,"formal_arrival_readiness":result.to_record()})
		return false
	c.visit_id = str(result.changed_ids[0])
	if not allow_visitors: _command(c,"clinical_visit_consent",{"visit_id":c.visit_id,"allow":false})
	return true

func _tick(c: Dictionary) -> void:
	if not bool(c.get("fixture_ready",true)): return
	_fixture_arrival_plan(c.world)
	var result: TickResult = c.sim.step()
	for event: SimEvent in result.facts:
		if event.kind=="service_started":
			var kind: String = str(event.details.get("kind",""))
			c.started[kind] = int(c.started.get(kind,0))+1
	for movement: Dictionary in c.world.facts.moves.values():
		if movement.get("members",[]).size()>1: c.group_seen = true
	for session: Dictionary in c.world.facts.sessions.values():
		if session.kind=="surgery": c.beats[int(session.get("clinical_beat",0))] = true

func _until(t, c: Dictionary, condition: Callable, maximum_ticks: int = 2200) -> bool:
	if not bool(c.get("fixture_ready",true)): return false
	for index: int in maximum_ticks:
		if condition.call(): return true
		_tick(c)
		if index%100==99:
			print("CLINICAL_PROGRESS "+JSON.stringify(_state(c)))
			await t.process_frame
	return bool(condition.call())

func _steps(t, c: Dictionary, ticks: int) -> void:
	if not bool(c.get("fixture_ready",true)): return
	for index: int in ticks:
		_tick(c)
		if index%100==99: await t.process_frame

func _visit(c: Dictionary) -> Dictionary:
	return c.world.facts.visits.get(c.visit_id,{})

func _session(c: Dictionary, kind: String) -> Dictionary:
	for value: Dictionary in c.world.facts.sessions.values():
		if value.visit_id==c.visit_id and value.kind==kind: return value
	return {}

func _stay(c: Dictionary) -> Dictionary:
	for value: Dictionary in c.world.facts.ward_stays.values():
		if c.world.facts.attempts[value.attempt_id].visit_id==c.visit_id: return value
	return {}

func _income(c: Dictionary, component: String = "") -> int:
	var amount: int = 0
	for entry: Dictionary in c.world.facts.ledger.entries.values():
		if bool(entry.settled) and int(entry.amount)>0 and (component.is_empty() or entry.component==component): amount += int(entry.amount)
	return amount

func _units_used(c: Dictionary) -> int:
	var units: int = 0
	for issue: Dictionary in c.world.facts.inventory.issues.values(): units += int(issue.units)
	return units

func _remember(c: Dictionary, key: String) -> void:
	_snapshots[key] = {"facts":c.world.freeze(),"visit_id":c.visit_id,"serial":int(c.serial),"doctors":c.doctors.duplicate(),"started":c.started.duplicate(),"group_seen":c.group_seen,"beats":c.beats.duplicate()}

func _copy(key: String) -> Dictionary:
	if not _snapshots.has(key): return {}
	var source: Dictionary = _snapshots[key]
	var world: WorldState = WorldState.new(source.facts.duplicate(true))
	var simulation: HospitalSimulation = HospitalSimulation.new(world,_content)
	simulation.clinic.departments = null
	_simulations.append(simulation)
	return {"sim":simulation,"world":world,"serial":int(source.serial),"visit_id":source.visit_id,"doctors":source.doctors.duplicate(),"started":source.started.duplicate(),"group_seen":source.group_seen,"beats":source.beats.duplicate(),"errors":[]}

func _require(t, ids: Array, key: String) -> bool:
	if _snapshots.has(key): return true
	for id: String in ids: t.check(id,false,{"missing_real_business_boundary":key,"fixture_prerequisites":_fixture_failures})
	return false

func _state(c: Dictionary) -> Dictionary:
	var participants: Array = []
	for id: String in c.world.ids("actors"):
		var actor: Dictionary = c.world.facts.actors[id]
		var staff: Dictionary = c.world.facts.staff.get(id,{})
		var move: Dictionary = c.world.facts.moves.get(id,{})
		participants.append({"id":id,"location":actor.location.duplicate(true),"release":staff.get("clinical_release",{}).duplicate(true),"base":staff.get("base_task",{}).duplicate(true),"move":{"target":move.get("target_cell",[]),"cursor":move.get("cursor",-1),"blocked_since":move.get("blocked_since",-1),"yielding":move.get("yielding",false),"pending":move.get("route_pending",false),"next":move.get("path",[]).slice(int(move.get("cursor",0)),int(move.get("cursor",0))+3)}})
	return {"tick":c.world.sim_tick,"visit":_visit(c).duplicate(true),"sessions":c.world.facts.sessions.duplicate(true),"preparations":c.world.facts.preparations.duplicate(true),"stays":c.world.facts.ward_stays.duplicate(true),"participants":participants,"errors":c.errors}

func _seed_stream(world: WorldState, stream: String, first_success: bool, second_success: bool, first_limit: int, second_limit: int) -> bool:
	# Search input seeds, never modify or redraw an already committed Attempt.
	for seed_value: int in range(1,200000):
		var generator: RandomNumberGenerator = RandomNumberGenerator.new()
		generator.seed = seed_value
		var initial: int = generator.state
		var first: int = generator.randi_range(0,9999)
		var second: int = generator.randi_range(0,9999)
		if (first<first_limit)==first_success and (second<second_limit)==second_success:
			world.facts.rng[stream] = {"algorithm":"godot-pcg32-4.7.2","seed_decimal":str(seed_value),"state_decimal":str(initial)}
			return true
	return false

func _ordinary_queue(t, report_reception: bool = false) -> Dictionary:
	var c: Dictionary = _context()
	_seed_stream(c.world,"treatment",true,true,9200,9800)
	var arrived: bool = _arrive(c)
	var duplicate: CommandResult = CommandResult.new(false,"not_checked")
	if report_reception:
		var request: Dictionary = {"arrival_key":_visit(c).get("arrival_key",""),"binding_id":"B_S13_D09_M09","requested_plan_id":"P_D09_COMMON","personality_id":"PP01"}
		duplicate = _command(c,"clinical_arrive",request)
	var reception: bool = arrived and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="reception")
	var reception_session: Dictionary = _session(c,"reception").duplicate(true)
	if report_reception:
		t.check("CLIN-01",reception and duplicate.accepted and c.world.facts.visits.size()==1 and c.world.facts.arrival_receipts.size()==1 and c.world.facts.actors.size()==c.world.facts.staff.size()+1 and int(reception_session.get("total_ticks",-1))==60 and c.world.facts.attempts.is_empty() and _income(c)==0 and _units_used(c)==0,_state(c))
	var gp: bool = reception and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="gp")
	c.queue_gp_session = _session(c,"gp").duplicate(true)
	if gp: _remember(c,"gp_started")
	var waiting: bool = gp and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="wait_outpatient" and c.world.facts.preparations.has(c.visit_id) and _visit(c).attempt_ids.is_empty())
	if waiting: _remember(c,"outpatient_queue")
	c.queue_ready = waiting
	return c

func _ordinary_chain(t) -> void:
	var c: Dictionary = await _ordinary_queue(t,true)
	var waiting: bool = bool(c.queue_ready)
	var actual_gp: Dictionary = c.queue_gp_session
	var started: bool = waiting and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="outpatient")
	var actual_treatment: Dictionary = _session(c,"outpatient").duplicate(true)
	if started: _remember(c,"outpatient_started")
	var departed: bool = started and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="departed")
	var ids: Array = _visit(c).get("attempt_ids",[])
	var gp_id: String = str(actual_gp.get("staff_ids",[""])[0])
	var treatment_id: String = str(actual_treatment.get("staff_ids",[""])[0])
	var actual_handoff: bool = gp_id!=treatment_id and gp_id==str(c.doctors[0]) and treatment_id==str(c.doctors[1])
	if actual_handoff:
		actual_handoff = c.sim.clinic._schedule_allows(c.world,gp_id,"gp",_visit(c),str(actual_gp.facility_id)) and c.sim.clinic._schedule_allows(c.world,treatment_id,"outpatient",_visit(c),str(actual_treatment.facility_id)) and not c.sim.clinic._schedule_allows(c.world,gp_id,"outpatient",_visit(c),str(actual_treatment.facility_id))
	t.check("CLIN-02",departed and actual_handoff and _visit(c).get("final_result","")=="cured" and _income(c)==235 and _income(c,"consultation")==20 and _income(c,"gp")==5 and _income(c,"outpatient")==10 and _income(c,"cure")==200 and ids.size()==1 and _units_used(c)==1 and c.world.facts.sessions.is_empty() and c.world.facts.ward_stays.is_empty(),{"actual_gp_doctor":gp_id,"actual_treatment_doctor":treatment_id,"legal_separate_pool_handoff":actual_handoff,"state":_state(c)})
	if departed: _remember(c,"outpatient_departed")
	if not _require(t,["CLIN-05"],"gp_started"): return
	var frozen: Dictionary = _copy("gp_started")
	var original: Dictionary = _session(frozen,"gp").duplicate(true)
	var doctor_id: String = str(original.get("staff_ids",[""])[0])
	if frozen.world.facts.staff.has(doctor_id): frozen.world.facts.staff[doctor_id].title_id = "DT04"
	frozen.world.facts.facilities[original.facility_id].grade = 2
	var completed: bool = await _until(t,frozen,func()->bool: return _visit(frozen).get("evidence_by_source",{}).has("gp"))
	var paid: int = _income(frozen)
	# Late completion delivery goes through the existing Session identity guard.
	frozen.sim.clinic._complete_service(frozen.world,original)
	HospitalLedger.settle(frozen.world)
	t.check("CLIN-05",completed and int(original.get("doctor_fee",-1))==20 and paid==25 and _income(frozen)==25 and _visit(frozen).evidence_by_source.size()==1,{"quoted":original,"income":_income(frozen),"state":_state(frozen)})

func _diagnosis_chain(t, upgraded: bool) -> void:
	var id: String = "CLIN-04" if upgraded else "CLIN-03"
	var c: Dictionary = _context(false,true)
	for staff: Dictionary in c.world.facts.staff.values():
		if staff.role in ["doctor","nurse"]: staff.abilities.diagnosis = 3 if upgraded else 1
	if upgraded: c.world.facts.facilities.gp_station.grade = 2
	var arrived: bool = _arrive(c,"B_S22_D14_M14","P_D14_COMMON")
	var first: bool = arrived and await _until(t,c,func()->bool: return _visit(c).get("evidence_by_source",{}).has("gp"))
	var gp_evidence: float = float(_visit(c).get("evidence_by_source",{}).get("gp",-1))
	var second: bool = first and await _until(t,c,func()->bool: return _visit(c).get("evidence_by_source",{}).has("spectrum"))
	var after_spectrum: float = 0.0
	for amount: Variant in _visit(c).get("evidence_by_source",{}).values(): after_spectrum += float(amount)
	var third: bool = second
	if not upgraded: third = second and await _until(t,c,func()->bool: return _visit(c).get("evidence_by_source",{}).has("resonance"))
	var total: float = 0.0
	for amount: Variant in _visit(c).get("evidence_by_source",{}).values(): total += float(amount)
	if upgraded:
		t.check(id,third and is_equal_approx(gp_evidence,49.2) and is_equal_approx(after_spectrum,93.0) and not _visit(c).evidence_by_source.has("resonance") and int(c.started.get("resonance",0))==0 and _income(c,"resonance")==0 and _income(c)==40 and _units_used(c)==0 and _visit(c).phase=="wait_consult",{"gp":gp_evidence,"after_spectrum":after_spectrum,"income":_income(c),"state":_state(c)})
	else:
		t.check(id,third and is_equal_approx(gp_evidence,42.0) and is_equal_approx(after_spectrum,77.0) and is_equal_approx(total,102.0) and int(c.started.get("spectrum",0))==1 and int(c.started.get("resonance",0))==1 and _units_used(c)==0 and _income(c)==60 and _visit(c).phase=="wait_consult",{"gp":gp_evidence,"after_spectrum":after_spectrum,"total":total,"income":_income(c),"state":_state(c)})
		if third: _remember(c,"c_diagnosed")

func _quotes_and_shortage(t) -> void:
	if _require(t,["CLIN-06","CLIN-08"],"outpatient_queue"):
		var c: Dictionary = _copy("outpatient_queue")
		var before: Dictionary = c.world.freeze()
		var ordinary: Dictionary = c.sim.clinic.plan_quote(c.world,c.visit_id,"P_D09_COMMON")
		var gentle: Dictionary = c.sim.clinic.plan_quote(c.world,c.visit_id,"P_D09_GENTLE")
		var repeated: Dictionary = c.sim.clinic.plan_quote(c.world,c.visit_id,"P_D09_GENTLE")
		c.sim.clinic.compare_plans(c.world,c.visit_id)
		# Simulation §4: D09 uses 30 standard seconds, no communication or
		# department modifier in this fixture. Each plan rounds only its final ticks.
		var preparation: Dictionary = c.world.facts.preparations.get(c.visit_id,{})
		var operators: Array = preparation.get("staff_ids",[])
		var operator_id: String = str(operators[0]) if not operators.is_empty() else ""
		var operator: Dictionary = c.world.facts.staff.get(operator_id,{})
		var facility: Dictionary = c.world.facts.facilities.get(str(preparation.get("facility_id","")),{})
		var level: int = int(operator.get("abilities",{}).get("treatment",0))
		var grade: int = int(facility.get("grade",-1))
		var fatigue: float = float(operator.get("fatigue",0.0))
		var utilization: Dictionary = {1:0.60,2:0.70,3:0.80,4:0.90,5:1.00}
		var oracle_ready: bool = utilization.has(level) and grade>=0 and grade<=2 and facility.get("definition_id","")=="M09"
		var unrounded_seconds: float = 0.0
		var expected_common_ticks: int = -1
		var expected_gentle_ticks: int = -1
		if oracle_ready:
			var effective: float = float(grade)*float(utilization[level])
			unrounded_seconds = 30.0/(1.0+0.05*(level-1)+0.20*effective)*(1.0+0.003*fatigue)
			expected_common_ticks = ceili(unrounded_seconds*10.0)
			expected_gentle_ticks = ceili(unrounded_seconds*1.8*10.0)
		t.check("CLIN-06",oracle_ready and ordinary.get("ok",false) and gentle.get("ok",false) and int(ordinary.get("probability_bp",-1))==9200 and int(gentle.get("probability_bp",-1))==9700 and int(ordinary.get("supply_units",-1))==1 and int(gentle.get("supply_units",-1))==2 and int(ordinary.get("work_ticks",-1))==expected_common_ticks and int(gentle.get("work_ticks",-1))==expected_gentle_ticks and int(ordinary.get("facility_fee",-1))==10 and int(gentle.get("facility_fee",-1))==10 and int(ordinary.get("cure_fee",-1))==200 and int(gentle.get("cure_fee",-1))==220 and gentle==repeated and c.world.freeze()==before,{"ordinary":ordinary,"gentle":gentle,"oracle_inputs":{"operator_id":operator_id,"treatment_level":level,"equipment_grade":grade,"fatigue":fatigue},"unrounded_standard_seconds":unrounded_seconds,"expected_common_ticks":expected_common_ticks,"expected_gentle_ticks":expected_gentle_ticks,"world_changed":c.world.freeze()!=before})
		var short: Dictionary = _copy("outpatient_queue")
		# This shared boundary already owns a reservation. Release it through the
		# existing same-plan command before constructing an unreserved shortage.
		var released: CommandResult = _command(short,"clinical_select_plan",{"visit_id":short.visit_id,"plan_id":"P_D09_COMMON"})
		var unreserved: bool = released.accepted and short.world.facts.preparations.is_empty() and short.sim.services.supplies.reserved(short.world)==0
		if unreserved: short.world.facts.inventory.units = 0
		var original_ticket: String = str(_visit(short).ticket_id)
		var consults: int = int(short.started.get("consult",0))
		if unreserved: await _steps(t,short,50)
		var blocked: bool = unreserved and short.world.facts.attempts.is_empty() and _units_used(short)==0 and _income(short)==25 and str(_visit(short).ticket_id)==original_ticket
		var purchased: CommandResult = _command(short,"purchase_supplies",{"units":1,"unit_price":20,"order_id":"clinical_shortage_purchase"}) if blocked else CommandResult.new(false,"shortage_fixture_not_ready")
		var after_purchase: int = HospitalLedger.balance(short.world)
		var resumed: bool = purchased.accepted and await _until(t,short,func()->bool: return _visit(short).get("phase","")=="outpatient")
		var session: Dictionary = _session(short,"outpatient")
		t.check("CLIN-08",blocked and resumed and int(short.started.get("consult",0))==consults and str(session.get("original_ticket",{}).get("id",""))==original_ticket and _units_used(short)==1 and int(short.world.facts.inventory.units)==0 and HospitalLedger.balance(short.world)==after_purchase,{"released_unstarted_reservation":released.to_record(),"blocked_without_effects":blocked,"purchased":purchased.to_record(),"state":_state(short)})
	if _require(t,["CLIN-07"],"c_diagnosed"):
		var c: Dictionary = _copy("c_diagnosed")
		for staff: Dictionary in c.world.facts.staff.values():
			if staff.role=="doctor": staff.abilities.treatment = 1
		var too_low: Dictionary = c.sim.clinic.plan_quote(c.world,c.visit_id,"P_D14_COMMON")
		for staff: Dictionary in c.world.facts.staff.values():
			if staff.role=="doctor": staff.abilities.treatment = 3
		c.world.facts.research.erase("R33")
		var missing_research: Dictionary = c.sim.clinic.plan_quote(c.world,c.visit_id,"P_D14_GENTLE")
		c.world.facts.research.append("R33")
		var missing_bed: Dictionary = c.sim.clinic.plan_quote(c.world,c.visit_id,"P_D14_GENTLE")
		var rejected: CommandResult = _command(c,"clinical_select_plan",{"visit_id":c.visit_id,"plan_id":"P_D14_GENTLE"})
		t.check("CLIN-07",not too_low.get("ok",true) and not missing_research.get("ok",true) and not missing_bed.get("ok",true) and not rejected.accepted and c.world.facts.attempts.is_empty() and c.world.facts.preparations.is_empty() and _units_used(c)==0,{"ability":too_low,"research":missing_research,"bed":missing_bed,"command":rejected.to_record()})

func _retry_and_restore(t) -> void:
	if _require(t,["CLIN-09","CLIN-10","CLIN-11"],"outpatient_queue"):
		var retry: Dictionary = _copy("outpatient_queue")
		_seed_stream(retry.world,"treatment",false,true,9200,9800)
		# Doctor ownership exercises automatic consultation after failure.
		_visit(retry).plan_decision.source = "doctor"
		var twice: bool = await _until(t,retry,func()->bool: return _visit(retry).attempt_ids.size()==2,2600)
		var ids: Array = _visit(retry).attempt_ids
		var first: Dictionary = retry.world.facts.attempts.get(ids[0],{}) if ids.size()>0 else {}
		var second: Dictionary = retry.world.facts.attempts.get(ids[1],{}) if ids.size()>1 else {}
		t.check("CLIN-09",twice and not first.get("result",true) and second.get("result",false) and int(second.get("probability_bp",-1))==9800 and _units_used(retry)==2 and _income(retry,"consultation")==20 and _income(retry,"gp")==5 and int(retry.started.get("consult",0))==2,{"first":first,"second":second,"state":_state(retry)})
		var failed: Dictionary = _copy("outpatient_queue")
		_seed_stream(failed.world,"treatment",false,false,9200,9800)
		var departed: bool = await _until(t,failed,func()->bool: return _visit(failed).get("phase","")=="departed",2600)
		var at_end: Dictionary = failed.world.facts.ledger.entries.duplicate(true)
		await _steps(t,failed,5)
		t.check("CLIN-10",departed and _visit(failed).attempt_ids.size()==2 and _visit(failed).get("final_result","")=="referred" and _income(failed)==45 and _income(failed,"cure")==0 and _units_used(failed)==2 and failed.world.facts.ledger.entries==at_end,{"income":_income(failed),"used":_units_used(failed),"state":_state(failed)})
		var manual: Dictionary = _copy("outpatient_queue")
		var selected: CommandResult = _command(manual,"clinical_select_plan",{"visit_id":manual.visit_id,"plan_id":"P_D09_GENTLE"})
		_seed_stream(manual.world,"treatment",false,true,9700,9800)
		manual.world.facts.inventory.units = 0
		var ticket: String = str(_visit(manual).ticket_id)
		var revision: int = int(_visit(manual).plan_decision.get("revision",-1))
		await _steps(t,manual,20)
		var preserved: bool = _visit(manual).plan_decision.get("plan_id","")=="P_D09_GENTLE" and _visit(manual).ticket_id==ticket and int(_visit(manual).plan_decision.get("revision",-2))==revision and manual.world.facts.preparations.is_empty()
		var purchase: CommandResult = _command(manual,"purchase_supplies",{"units":4,"order_id":"clinical_manual_supply"})
		var repeated: bool = purchase.accepted and await _until(t,manual,func()->bool: return _visit(manual).attempt_ids.size()==2,2800)
		var all_gentle: bool = true
		for attempt_id: String in _visit(manual).attempt_ids: all_gentle = all_gentle and manual.world.facts.attempts[attempt_id].plan_id=="P_D09_GENTLE"
		t.check("CLIN-11",selected.accepted and preserved and repeated and all_gentle and _visit(manual).plan_decision.get("source","")=="director" and int(manual.started.get("consult",0))==1 and _units_used(manual)==4,{"preserved_during_shortage":preserved,"state":_state(manual)})
	if _require(t,["CLIN-12"],"outpatient_started"):
		var c: Dictionary = _copy("outpatient_started")
		await _steps(t,c,17)
		var before: Dictionary = c.world.freeze()
		var session: GameSession = GameSession.new(c.sim,"clinical-pause")
		session.set_speed(1)
		session.pause("acceptance")
		for index: int in 4: session.advance(0.5)
		var paused: bool = c.world.freeze()==before
		var restored: Dictionary = _roundtrip(c)
		var resumed: bool = restored.ok and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="departed")
		t.check("CLIN-12",paused and resumed and _commitments(c.world.facts.attempts)==_commitments(before.attempts) and _income(c)==235 and _units_used(c)==1 and c.world.facts.inventory.issues==before.inventory.issues,{"paused_without_effects":paused,"restore":restored,"state":_state(c)})

func _commitments(attempts: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in attempts:
		var frozen: Dictionary = {}
		for key: String in ["id","visit_id","plan_id","protocol_id","result","probability_bp","start_tick","work_ticks","recovery_ticks","supply_units","cure_fee","facility_fee","ward_fee","ward_fee_quote","staff_ids","effective_level","beat_end_ticks"]:
			frozen[key] = attempts[id].get(key)
		result[id] = frozen
	return result

func _roundtrip(c: Dictionary) -> Dictionary:
	var chunks: Array = []
	var encoder: HospitalJsonStream = HospitalJsonStream.new()
	var encoded: bool = encoder.encode_to(c.world.freeze(),func(_bytes: int)->bool: return true,func(chunk: PackedByteArray)->Dictionary:
		chunks.append(chunk.duplicate())
		return {"ok":true})
	if not encoded: return {"ok":false,"error":encoder.error}
	var cursor: Dictionary = {"index":0}
	var decoder: HospitalJsonStream = HospitalJsonStream.new()
	var decoded: Dictionary = decoder.decode_from(encoder.bytes,encoder.digest,func(_bytes: int)->bool: return true,func()->Dictionary:
		if int(cursor.index)>=chunks.size(): return {"ok":true,"data":PackedByteArray()}
		var chunk: PackedByteArray = chunks[int(cursor.index)]
		cursor.index = int(cursor.index)+1
		return {"ok":true,"data":chunk})
	if not decoded.ok: return {"ok":false,"error":decoded.error}
	var world: WorldState = WorldState.new(decoded.value)
	var reason: String = world.validate(_content)
	if not reason.is_empty(): return {"ok":false,"error":reason}
	var original: Dictionary = c.world.freeze()
	if world.freeze()!=original: return {"ok":false,"error":"流式恢复后的世界与冻结边界不同"}
	var simulation: HospitalSimulation = HospitalSimulation.new(world,_content)
	simulation.clinic.departments = null
	_simulations.append(simulation)
	c.world = world
	c.sim = simulation
	return {"ok":true,"bytes":encoder.bytes,"sha256":encoder.digest}

func _surgery_queue(t, c_profile: bool = false) -> Dictionary:
	var c: Dictionary = _context(true,c_profile)
	c.ward_return = {"ok":not c_profile,"reason":"not_required" if not c_profile else "consult_missing"}
	c.plan_selection = CommandResult.new(false,"consult_missing").to_record()
	if c_profile:
		c.world.facts.staff.clin_surgeon.title_id = "DT03"
		c.world.facts.staff.clin_surgeon.abilities.surgery = 3
		c.world.facts.staff.clin_or_nurse.abilities.surgery = 2
	var binding: String = "B_S22_D14_M14" if c_profile else "B_S13_D09_M09"
	var plan: String = "P_D14_SURGERY" if c_profile else "P_D09_SURGERY"
	_seed_stream(c.world,"treatment",true,true,9600,9800)
	if not _arrive(c,binding,plan): return c
	var diagnostic: Dictionary = {"reported":false}
	var consulted: bool = await _until(t,c,func()->bool:
		var visit: Dictionary = _visit(c)
		if not diagnostic.reported and visit.get("phase","")=="wait_consult" and c.world.sim_tick-int(visit.get("last_progress_tick",c.world.sim_tick))>=150:
			diagnostic.reported = true
			_surgery_wait_diagnostic(c,plan)
		return visit.get("phase","") in ["wait_outpatient","wait_surgery"],3000)
	if consulted:
		if c_profile: c.ward_return = await _wait_ward_nurse_return(t,c)
		var selected: CommandResult = _command(c,"clinical_select_plan",{"visit_id":c.visit_id,"plan_id":plan}) if c.ward_return.ok else CommandResult.new(false,"ward_return_incomplete",str(c.ward_return.reason))
		c.plan_selection = selected.to_record()
		if not selected.accepted: c.errors.append({"select_surgery":selected.to_record()})
	else:
		c.errors.append({"missing":"completed_consultation"})
	return c

func _ward_nurse_return_state(c: Dictionary) -> Dictionary:
	var nurse: Dictionary = c.world.facts.staff.clin_cover
	var location: Dictionary = c.world.facts.actors.clin_cover.location
	var ward_id: String = str(nurse.get("ward_id",""))
	var ward: Dictionary = c.world.facts.rooms.get(ward_id,{})
	var inside: bool = not ward.is_empty() and location.kind=="floor" and int(location.floor_id)==int(ward.floor_id) and Rect2(float(ward.origin[0]),float(ward.origin[1]),float(ward.size[0]),float(ward.size[1])).has_point(Vector2(float(location.cell[0]),float(location.cell[1])))
	var ready: bool = ward_id=="clin_ward" and inside and nurse.on_shift and bool(nurse.get("base_prepared",false)) and "q_ward" in nurse.certificates and not bool(nurse.get("block_new_work",false)) and nurse.get("base_task",{}).is_empty() and str(nurse.get("life_task",{}).get("phase","idle")) in ["idle","wait_safe"] and not c.world.facts.moves.has("clin_cover") and not c.sim.clinic.staff_busy(c.world,"clin_cover")
	return {"ready":ready,"nurse_id":"clin_cover","ward_id":ward_id,"location":location.duplicate(true),"inside_assigned_ward":inside,"on_shift":nurse.on_shift,"base_prepared":nurse.get("base_prepared",false),"move":c.world.facts.moves.get("clin_cover",{}).duplicate(true),"clinical_release":nurse.get("clinical_release",{}).duplicate(true)}

func _wait_ward_nurse_return(t, c: Dictionary) -> Dictionary:
	var before: Dictionary = _ward_nurse_return_state(c)
	var started_tick: int = c.world.sim_tick
	await _until(t,c,func()->bool:
		if not c.world.facts.attempts.is_empty(): return true
		return bool(_ward_nurse_return_state(c).ready),240)
	var after: Dictionary = _ward_nurse_return_state(c)
	var unstarted: bool = c.world.facts.attempts.is_empty() and _visit(c).get("attempt_ids",[]).is_empty()
	var waiting: bool = _visit(c).get("phase","") in ["wait_outpatient","wait_surgery"]
	var reason: String = ""
	if not unstarted:
		reason = "等待回岗期间已经实际开工，保留原Attempt"
	elif not waiting:
		reason = "病例已离开候治疗边界"
	elif not bool(after.ready):
		reason = "覆盖护士未完成实际回岗"
	return {"ok":reason.is_empty(),"reason":reason,"started_tick":started_tick,"finished_tick":c.world.sim_tick,"no_attempt_started":unstarted,"phase":_visit(c).get("phase",""),"before":before,"after":after}

func _surgery_wait_diagnostic(c: Dictionary, surgery_plan: String) -> void:
	# A single read-only observation after a prolonged consultation wait.
	var visit: Dictionary = _visit(c)
	var quotes: Dictionary = {}
	var operators: Dictionary = {}
	for doctor_id: String in c.doctors.slice(0,2):
		var staff: Dictionary = c.world.facts.staff[doctor_id]
		operators[doctor_id] = {"location":c.world.facts.actors[doctor_id].location.duplicate(true),"abilities":staff.abilities.duplicate(),"on_shift":staff.on_shift,"base_prepared":staff.get("base_prepared",false),"block_new_work":staff.get("block_new_work",false),"schedule":staff.schedule.duplicate(true),"clinical_release":staff.get("clinical_release",{}).duplicate(true)}
		for suffix: String in ["COMMON","GENTLE"]:
			var plan_id: String = "P_"+str(visit.disease_id)+"_"+suffix
			quotes[doctor_id+":"+suffix] = c.sim.clinic.plan_quote(c.world,c.visit_id,plan_id,{"doctor_id":doctor_id})
	quotes.surgery = c.sim.clinic.plan_quote(c.world,c.visit_id,surgery_plan)
	print("CLINICAL SURGERY WAIT "+JSON.stringify({"tick":c.world.sim_tick,"visit_id":c.visit_id,"waiting_reason":visit.get("waiting_reason",""),"consult_candidates":c.sim.clinic.service_candidates(c.world,visit,"consult"),"doctor_quotes":quotes,"operators":operators}))

func _surgery_to_care(t, report_cases: bool = true) -> Dictionary:
	var c: Dictionary = await _surgery_queue(t)
	var queued: bool = _visit(c).get("phase","")=="wait_surgery"
	if queued: _remember(c,"surgery_queue")
	var prepared: bool = queued and await _until(t,c,func()->bool: return c.world.facts.preparations.has(c.visit_id),600)
	if prepared: _remember(c,"surgery_prepared")
	var preparation: Dictionary = c.world.facts.preparations.get(c.visit_id,{}).duplicate(true)
	if report_cases:
		t.check("CLIN-15",prepared and int(preparation.get("supply_units",-1))==8 and int(preparation.get("setup_remaining_ticks",-1))==80 and int(preparation.get("deadline_tick",-1))-c.world.sim_tick<=300 and preparation.get("staff_ids",[]).size()==3 and not str(preparation.get("bed_id","")).is_empty() and c.sim.services.supplies.reserved(c.world)==8 and c.world.facts.attempts.is_empty() and _units_used(c)==0 and int(c.world.facts.inventory.units)==60 and _income(c)==25 and int(c.world.facts.staff.clin_or_nurse.practice.surgery)==0,{"preparation":preparation,"state":_state(c)})
	var begun: bool = prepared and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="surgery",600)
	if begun: _remember(c,"surgery_started")
	var at_wake: bool = begun and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="wake",1800)
	if at_wake: _remember(c,"surgery_wake")
	var transferred: bool = at_wake and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="transfer",200)
	if transferred: _remember(c,"surgery_transfer")
	var in_bed: bool = transferred and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="recovery",900)
	if in_bed: _remember(c,"ward_entered")
	var stay: Dictionary = _stay(c)
	var attempt: Dictionary = c.world.facts.attempts.get(stay.get("attempt_id",""),{})
	var transferred_id: String = str(stay.get("attempt_id",""))
	var entered_units: int = _units_used(c)
	var escort: String = str(stay.get("escort_id",""))
	var released: bool = in_bed and await _until(t,c,func()->bool: return not c.sim.clinic.staff_busy(c.world,escort),180)
	if report_cases:
		t.check("CLIN-20",in_bed and released and bool(c.group_seen) and str(_stay(c).get("attempt_id",""))==transferred_id and not attempt.is_empty() and _visit(c).attempt_ids.size()==1 and c.world.facts.actors[_visit(c).actor_id].get("posture","")=="lying" and entered_units==8 and _units_used(c)==8 and _income(c,"surgery")==60 and _income(c,"ward")==0 and _income(c,"cure")==0,{"group_seen":c.group_seen,"escort_released":released,"state":_state(c)})
	var care_started: bool = in_bed and (not _session(c,"care").is_empty() or await _until(t,c,func()->bool: return not _session(c,"care").is_empty(),300))
	if care_started: _remember(c,"ward_care")
	var cared: bool = in_bed and await _until(t,c,func()->bool: return _stay(c).get("care_completed",false),350)
	if cared: _remember(c,"ward_after_care")
	c.care_ready = cared
	return c

func _surgery_chain(t) -> void:
	var c: Dictionary = await _surgery_to_care(t)
	var cared: bool = bool(c.care_ready)
	var round_wait: bool = cared and await _until(t,c,func()->bool: return _stay(c).get("phase","")=="round_wait",2200)
	if round_wait: _remember(c,"ward_round_wait")
	var round_started: bool = round_wait and await _until(t,c,func()->bool: return not _session(c,"round").is_empty(),500)
	if round_started: _remember(c,"ward_round")
	var ended: bool = round_started and await _until(t,c,func()->bool: return not _visit(c).get("final_result","").is_empty(),300)
	if ended: _remember(c,"ward_settled")
	if _require(t,["CLIN-18"],"surgery_started"):
		var frozen: Dictionary = _copy("surgery_started")
		var before: Dictionary = _commitments(frozen.world.facts.attempts)
		var original: Dictionary = frozen.world.facts.attempts.values()[0].duplicate(true)
		frozen.world.facts.staff[original.staff_ids[0]].abilities.surgery = 5
		frozen.world.facts.facilities[original.facility_id].grade = 2
		var restored: Dictionary = _roundtrip(frozen)
		await _steps(t,frozen,3)
		t.check("CLIN-18",restored.ok and int(original.get("probability_bp",-1))==9600 and int(original.get("work_ticks",-1))==1200 and int(original.get("recovery_ticks",-1))==1800 and int(original.get("ward_fee",original.get("ward_fee_quote",-1)))==60 and original.get("beat_end_ticks",[])==[180,720,1020,1200] and _commitments(frozen.world.facts.attempts)==before and c.beats.size()==4 and _units_used(frozen)==8 and frozen.world.facts.attempts.size()==1,{"attempt":original,"actual_beats":c.beats,"restore":restored,"state":_state(frozen)})
	if _require(t,["CLIN-19"],"surgery_wake"):
		var wake: Dictionary = _copy("surgery_wake")
		var wake_session: Dictionary = _session(wake,"wake").duplicate(true)
		var no_early_charge: bool = _income(wake,"surgery")==0 and _income(wake,"cure")==0 and int(wake_session.get("total_ticks",-1))==150
		var held: bool = true
		for staff_id: String in wake_session.get("staff_ids",[]): held = held and wake.sim.clinic.staff_busy(wake.world,staff_id)
		await _steps(t,wake,149)
		var before_end: bool = _visit(wake).phase=="wake" and _income(wake,"surgery")==0 and int(_session(wake,"wake").get("remaining_ticks",-1))==1
		await _steps(t,wake,1)
		t.check("CLIN-19",no_early_charge and held and before_end and _visit(wake).phase=="transfer" and _session(wake,"wake").is_empty() and _income(wake,"surgery")==60 and _income(wake,"ward")==0 and _income(wake,"cure")==0 and not _stay(wake).is_empty(),{"not_charged_before_wake":no_early_charge,"all_staff_held":held,"before_last_tick":before_end,"state":_state(wake)})

func _surgical_boundaries(t) -> void:
	if _require(t,["CLIN-14","CLIN-16","CLIN-17","CLIN-21"],"surgery_queue"):
		var qualified: Dictionary = _copy("surgery_queue")
		var complete: Dictionary = qualified.sim.clinic.plan_quote(qualified.world,qualified.visit_id,"P_D09_SURGERY")
		var duplicate_team: Dictionary = qualified.sim.clinic._surgery_bundle_quote(qualified.world,_visit(qualified),["clin_surgeon","clin_surgeon","clin_or_nurse"],"clin_or_0",{})
		qualified.world.facts.staff.clin_anesthesia.abilities.surgery = 0
		var missing_doctor: Dictionary = qualified.sim.clinic.plan_quote(qualified.world,qualified.visit_id,"P_D09_SURGERY")
		qualified.world.facts.staff.clin_anesthesia.abilities.surgery = 2
		qualified.world.facts.staff.clin_cover.on_shift = false
		var missing_coverage: Dictionary = qualified.sim.clinic.plan_quote(qualified.world,qualified.visit_id,"P_D09_SURGERY")
		t.check("CLIN-14",complete.get("ok",false) and not duplicate_team.get("ok",true) and not missing_doctor.get("ok",true) and not missing_coverage.get("ok",true) and qualified.world.facts.preparations.is_empty() and qualified.world.facts.attempts.is_empty() and _units_used(qualified)==0,{"complete":complete,"duplicate_team":duplicate_team,"missing_doctor":missing_doctor,"missing_coverage":missing_coverage})
		var cancel: Dictionary = _copy("surgery_prepared") if _snapshots.has("surgery_prepared") else {}
		var cancelled: bool = false
		if not cancel.is_empty():
			var old_ticket: String = str(_visit(cancel).ticket_id)
			var result: CommandResult = _command(cancel,"clinical_auto_plan",{"visit_id":cancel.visit_id})
			cancelled = result.accepted and cancel.world.facts.preparations.is_empty() and cancel.sim.services.supplies.reserved(cancel.world)==0 and _units_used(cancel)==0 and cancel.world.facts.attempts.is_empty() and str(_visit(cancel).ticket_id)==old_ticket and _income(cancel)==25 and cancel.world.validate(_content).is_empty()
		var expiry: Dictionary = _copy("surgery_queue")
		# A legal, long walk plus the real 8-second setup cannot fit the 30-second window.
		expiry.world.facts.floors.overrides["1"].plots.append([0,2])
		expiry.world.facts.actors.clin_or_nurse.location.cell = [0,65]
		expiry.world.touch()
		var expiry_ticket: String = str(_visit(expiry).ticket_id)
		var reserved: bool = await _until(t,expiry,func()->bool: return expiry.world.facts.preparations.has(expiry.visit_id),100)
		var deadline: int = int(expiry.world.facts.preparations.get(expiry.visit_id,{}).get("deadline_tick",expiry.world.sim_tick))
		if reserved: await _steps(t,expiry,deadline-expiry.world.sim_tick+1)
		var expired: bool = reserved and expiry.world.facts.preparations.is_empty() and expiry.world.facts.attempts.is_empty() and _visit(expiry).ticket_id==expiry_ticket and _units_used(expiry)==0 and expiry.sim.services.supplies.reserved(expiry.world)==0
		t.check("CLIN-16",cancelled and expired,{"cancelled_without_effects":cancelled,"expired_without_effects":expired,"state":_state(expiry)})
		var race: Dictionary = _copy("surgery_queue")
		race.world.facts.facilities.erase("clin_ward_1")
		race.world.facts.floors.overrides["1"].plots.append([0,2])
		_add_layout(race.world,"or_standard","clin_second_or",[19,65])
		_add_worker(race.world,"second_surgeon","doctor",[20,75],"surgery",{"diagnosis":1,"treatment":1,"care":0,"surgery":2},"DT02")
		_add_worker(race.world,"second_anesthesia","doctor",[24,75],"surgery",{"diagnosis":1,"treatment":1,"care":0,"surgery":2},"DT02")
		_add_worker(race.world,"second_or_nurse","nurse",[28,75],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":1})
		race.world.facts.staff.second_or_nurse.certificates = ["q_or","q_ward"]
		var second_visit: String = _waiting_case(race,[49,94])
		race.world.touch()
		await _steps(t,race,1)
		var first_prepared: Dictionary = race.world.facts.preparations.get(race.visit_id,{})
		var later: Dictionary = race.world.facts.visits[second_visit]
		var later_quote: Dictionary = race.sim.clinic._surgery_quote(race.world,later,["second_surgeon","second_anesthesia","second_or_nurse"],{"facility_id":"clin_second_or_0"})
		t.check("CLIN-17",race.world.facts.preparations.size()==1 and not first_prepared.is_empty() and not race.world.facts.preparations.has(second_visit) and not later_quote.get("ok",true) and str(later_quote.get("reason","")).contains("床") and race.world.facts.attempts.is_empty() and _units_used(race)==0 and race.sim.services.supplies.reserved(race.world)==8,{"later_quote":later_quote,"state":_state(race)})
		if _snapshots.has("surgery_started"):
			var fault: Dictionary = _copy("surgery_started")
			var before: Dictionary = _commitments(fault.world.facts.attempts)
			fault.world.facts.facilities.clin_or_0.pending_failure = true
			var completed: bool = await _until(t,fault,func()->bool: return _visit(fault).get("phase","")=="transfer",1800)
			var table: Dictionary = fault.world.facts.facilities.clin_or_0
			t.check("CLIN-21",completed and _commitments(fault.world.facts.attempts)==before and fault.world.facts.attempts.size()==1 and _units_used(fault)==8 and _income(fault,"surgery")==60 and _income(fault,"cure")==0 and (table.pending_failure or table.failed or table.get("maintenance_block",false)),_state(fault))
		else: t.check("CLIN-21",false,{"missing_real_business_boundary":"surgery_started"})
	await _fee_snapshots(t)

func _fee_snapshots(t) -> void:
	if not _require(t,["CLIN-13"],"outpatient_queue"): return
	var basic: Dictionary = _copy("outpatient_queue")
	var gentle: Dictionary = basic.sim.clinic.plan_quote(basic.world,basic.visit_id,"P_D09_GENTLE")
	var surgical: Dictionary = await _surgery_queue(t,true)
	var surgery: Dictionary = surgical.sim.clinic.plan_quote(surgical.world,surgical.visit_id,"P_D14_SURGERY") if not surgical.visit_id.is_empty() else {}
	var selected: CommandResult = _command(basic,"clinical_select_plan",{"visit_id":basic.visit_id,"plan_id":"P_D09_GENTLE"})
	_seed_stream(basic.world,"treatment",true,true,9700,9800)
	var started: bool = selected.accepted and await _until(t,basic,func()->bool: return _visit(basic).get("phase","")=="outpatient")
	var frozen: int = int(basic.world.facts.attempts.values()[0].get("cure_fee",-1)) if started else -1
	if started: basic.world.facts.facilities.zombie_machine.grade = 2
	await _steps(t,basic,2)
	t.check("CLIN-13",gentle.get("ok",false) and surgery.get("ok",false) and surgical.get("ward_return",{}).get("ok",false) and surgical.get("plan_selection",{}).get("accepted",false) and int(gentle.get("cure_fee",-1))==220 and int(surgery.get("cure_fee",-1))==1080 and frozen==220 and int(basic.world.facts.attempts.values()[0].get("cure_fee",-1))==220 and _units_used(basic)==2 and _income(basic)==25,{"gentle":gentle,"surgery":surgery,"d09_selection":selected.to_record(),"c_ward_return":surgical.get("ward_return",{}),"c_selection":surgical.get("plan_selection",{}),"frozen_gentle_cure_fee":frozen,"state":_state(basic),"c_surgical_state":_state(surgical)})

func _waiting_case(c: Dictionary, position: Array) -> String:
	# A second already-diagnosed queue member is a boundary fixture, not a second flow implementation.
	var source: Dictionary = _visit(c)
	var actor_id: String = c.world.new_id("patient")
	var visit_id: String = c.world.new_id("visit")
	var ticket_id: String = c.world.new_id("ticket")
	var actor: Dictionary = c.world.facts.actors[source.actor_id].duplicate(true)
	actor.id = actor_id
	actor.location = {"kind":"floor","floor_id":1,"cell":position.duplicate(),"height_m":0.0}
	actor.posture = "standing"
	actor.erase("support_facility_id")
	var visit: Dictionary = source.duplicate(true)
	visit.id = visit_id
	visit.actor_id = actor_id
	visit.ticket_id = ticket_id
	visit.arrival_key = "second-prepared-patient"
	visit.phase = "wait_surgery"
	visit.companion_intent = false
	visit.attempt_ids = []
	visit.final_result = ""
	visit.erase("clinical_participants")
	visit.erase("registration_receipt")
	c.world.facts.actors[actor_id] = actor
	c.world.facts.visits[visit_id] = visit
	c.world.facts.tickets[ticket_id] = {"id":ticket_id,"visit_id":visit_id,"kind":"surgery","enqueued_tick":c.world.sim_tick}
	c.world.facts.arrival_receipts[visit.arrival_key] = visit_id
	HospitalLedger.post(c.world,LedgerEntry.new(visit_id,"consultation",20))
	HospitalLedger.post(c.world,LedgerEntry.new(visit_id,"gp",5))
	return visit_id

func _in_stay_ward(c: Dictionary, actor_id: String) -> bool:
	var bed: Dictionary = c.world.facts.facilities.get(str(_stay(c).get("bed_id","")),{})
	var ward: Dictionary = c.world.facts.rooms.get(str(bed.get("room_id","")),{})
	var actor: Dictionary = c.world.facts.actors.get(actor_id,{})
	if ward.is_empty() or actor.is_empty() or actor.location.kind!="floor" or int(actor.location.floor_id)!=int(ward.floor_id): return false
	return Rect2(float(ward.origin[0]),float(ward.origin[1]),float(ward.size[0]),float(ward.size[1])).has_point(Vector2(float(actor.location.cell[0]),float(actor.location.cell[1])))

func _ward_coverage(t) -> void:
	if not _require(t,["CLIN-22"],"ward_after_care"): return
	var coverage: Dictionary = _copy("ward_after_care")
	var nurse_id: String = str(_stay(coverage).nurse_id)
	var idle: bool = await _until(t,coverage,func()->bool: return not coverage.sim.clinic.staff_busy(coverage.world,nurse_id) and not coverage.world.facts.moves.has(nurse_id),180)
	var moving: String = coverage.sim.space.request_move(coverage.world,nurse_id,1,[44,75]) if idle else "覆盖护士尚未安全离位"
	var outside_seen: bool = false
	var uncovered_ticks: int = 0
	var uncovered_stops: bool = true
	var returned: bool = false
	if moving.is_empty():
		for index: int in 500:
			var before_inside: bool = _in_stay_ward(coverage,nurse_id)
			var before_remaining: int = int(_stay(coverage).get("remaining_ticks",-1))
			_tick(coverage)
			var after_inside: bool = _in_stay_ward(coverage,nurse_id)
			outside_seen = outside_seen or not after_inside
			if not before_inside and not after_inside:
				uncovered_ticks += 1
				uncovered_stops = uncovered_stops and int(_stay(coverage).get("remaining_ticks",-2))==before_remaining
			if outside_seen and after_inside and not coverage.world.facts.moves.has(nurse_id) and not coverage.sim.clinic.staff_busy(coverage.world,nurse_id):
				returned = true
				break
			if index%100==99: await t.process_frame
	var before_covered: int = int(_stay(coverage).get("remaining_ticks",-1))
	await _steps(t,coverage,3)
	var covered_progress: bool = returned and int(_stay(coverage).get("remaining_ticks",before_covered))==before_covered-3
	var frozen: Dictionary = coverage.world.freeze()
	var session: GameSession = GameSession.new(coverage.sim,"ward-paused")
	session.set_speed(0)
	for index: int in 3: session.advance(0.5)
	t.check("CLIN-22",idle and moving.is_empty() and outside_seen and uncovered_ticks>0 and uncovered_stops and returned and covered_progress and coverage.world.freeze()==frozen,{"outside_ticks_checked":uncovered_ticks,"uncovered_stops":uncovered_stops,"automatic_return_completed":returned,"covered_progress":covered_progress,"move_reason":moving,"state":_state(coverage)})

func _failure_world(case_id: String, world: WorldState) -> Dictionary:
	if world==null: return {"ok":false,"error":"缺少实际模拟世界"}
	var path: String = "res://"+case_id+"-failure-"+HospitalSnapshots.uuid()+".json"
	var encoder: HospitalJsonStream = HospitalJsonStream.new()
	var encoded: bool = encoder.encode(path,world.freeze(),func(_bytes: int)->bool: return true)
	return {"ok":encoded,"path":ProjectSettings.globalize_path(path),"bytes":encoder.bytes,"sha256":encoder.digest,"error":encoder.error,"tick":world.sim_tick}

func _ward_round(t) -> void:
	if not _snapshots.has("ward_after_care"):
		var partial: WorldState = _simulations.back().world if not _simulations.is_empty() else null
		t.check("CLIN-24",false,{"missing_real_business_boundary":"ward_after_care","fixture_prerequisites":_fixture_failures,"failure_world":_failure_world("CLIN-24",partial)})
		return
	var rounding: Dictionary = _copy("ward_after_care")
	_all_rest(rounding.world,"doctor",true)
	var ready: bool = await _until(t,rounding,func()->bool: return _stay(rounding).get("phase","")=="round_wait",2200)
	var held: bool = ready and int(_stay(rounding).get("remaining_ticks",-1))==0 and bool(_stay(rounding).get("care_completed",false)) and _income(rounding,"ward")==0 and _income(rounding,"cure")==0 and _visit(rounding).get("final_result","").is_empty()
	var care_ticks: int = -1
	for source: Dictionary in _snapshots.get("ward_care",{}).get("facts",{}).get("sessions",{}).values():
		if source.kind=="care": care_ticks = int(source.total_ticks)
	var round_input: Dictionary = {}
	var placement: Dictionary = {"qualification_blocked":false,"base_prepared":false,"bedside_reached":false}
	if ready:
		var candidate_doctor: Dictionary = rounding.world.facts.staff.clin_round
		var diagnosis_input: int = int(candidate_doctor.abilities.diagnosis)
		candidate_doctor.abilities.diagnosis = 1
		candidate_doctor.schedule = _schedule("round")
		placement.qualification_blocked = true
		for staff: Dictionary in rounding.world.facts.staff.values():
			if staff.role=="doctor" and staff.on_shift and int(staff.abilities.diagnosis)>=2 and int(staff.abilities.treatment)>=1:
				placement.qualification_blocked = false
		var bed: Dictionary = rounding.sim.space.facility_layout(rounding.world,str(_stay(rounding).bed_id))
		var nurse_id: String = str(_stay(rounding).nurse_id)
		placement.base_prepared = await _until(t,rounding,func()->bool:
			return candidate_doctor.on_shift and bool(candidate_doctor.get("base_prepared",false)) and candidate_doctor.get("base_task",{}).is_empty() and not bool(candidate_doctor.get("block_new_work",false)) and not rounding.world.facts.moves.has("clin_round") and not rounding.sim.clinic.staff_busy(rounding.world,"clin_round") and not rounding.world.facts.moves.has(nurse_id) and not rounding.sim.clinic.staff_busy(rounding.world,nurse_id) and not rounding.sim.space.at(rounding.world,nurse_id,int(bed.floor_id),bed.operator_cells[1]),600)
		placement.move_reason = rounding.sim.space.request_move(rounding.world,"clin_round",int(bed.floor_id),bed.operator_cells[1]) if placement.base_prepared else "医生基地整理或护士安全离位尚未完成"
		placement.bedside_reached = placement.qualification_blocked and placement.move_reason.is_empty() and await _until(t,rounding,func()->bool:
			return rounding.sim.space.at(rounding.world,"clin_round",int(bed.floor_id),bed.operator_cells[1]) and not rounding.world.facts.moves.has("clin_round"),400)
		placement.no_round_before_qualification = _session(rounding,"round").is_empty()
		if placement.bedside_reached and placement.no_round_before_qualification:
			# Qualification remains insufficient throughout the real preparation and walk.
			round_input = {"tick":rounding.world.sim_tick,"doctor_id":"clin_round","fatigue":float(candidate_doctor.fatigue),"treatment_level":int(candidate_doctor.abilities.treatment),"species_id":str(rounding.world.facts.actors.clin_round.species_id),"talent_rate":1.0,"diagnosis_before":int(candidate_doctor.abilities.diagnosis),"diagnosis_input":diagnosis_input}
			candidate_doctor.abilities.diagnosis = diagnosis_input
	var began_round: bool = not round_input.is_empty() and await _until(t,rounding,func()->bool: return not _session(rounding,"round").is_empty(),180)
	var expected_round_ticks: int = -1
	if not round_input.is_empty():
		# Clinical 10 standard seconds; S49 has a course talent, no ward_visit bonus.
		expected_round_ticks = ceili(10.0*10.0*(1.0+0.003*float(round_input.fatigue))/(1.0+0.05*(int(round_input.treatment_level)-1))/float(round_input.talent_rate))
	var round_session: Dictionary = _session(rounding,"round").duplicate(true)
	var doctor: Dictionary = rounding.world.facts.staff.get(str(round_session.get("staff_ids",[""])[0]),{})
	var before_charge: bool = _income(rounding,"ward")==0 and _income(rounding,"cure")==0
	var finished: bool = began_round and await _until(t,rounding,func()->bool: return _visit(rounding).get("final_result","")=="cured",180)
	var departed: bool = finished and await _until(t,rounding,func()->bool: return _visit(rounding).get("phase","")=="departed",900)
	var passed: bool = held and care_ticks==80 and began_round and placement.qualification_blocked and placement.base_prepared and placement.bedside_reached and placement.get("no_round_before_qualification",false) and round_input.get("species_id","")=="S49" and int(round_session.get("total_ticks",-1))==expected_round_ticks and int(doctor.get("abilities",{}).get("diagnosis",0))>=2 and int(doctor.get("abilities",{}).get("treatment",0))>=1 and before_charge and finished and departed and _income(rounding,"ward")==60 and _income(rounding,"cure")==360 and _income(rounding)==505
	var failure: Dictionary = _failure_world("CLIN-24",rounding.world) if not passed else {}
	t.check("CLIN-24",passed,{"waited_for_qualified_round":held,"care_ticks":care_ticks,"round_placement":placement,"round_start_input":round_input,"expected_round_ticks":expected_round_ticks,"round":round_session,"actual_departure":departed,"failure_world":failure,"state":_state(rounding)})

func _ward_shortage(t) -> void:
	if not _require(t,["CLIN-27"],"ward_after_care"): return
	var shortage: Dictionary = _copy("ward_after_care")
	var initial_progress: int = int(_stay(shortage).last_progress_tick)
	_all_rest(shortage.world,"nurse")
	_all_rest(shortage.world,"doctor",true)
	var nurse_id: String = str(_stay(shortage).nurse_id)
	var off_shift: bool = await _until(t,shortage,func()->bool:
		if _stay(shortage).is_empty(): return false
		var nurse: Dictionary = shortage.world.facts.staff[nurse_id]
		if nurse.on_shift or shortage.world.facts.moves.has(nurse_id) or shortage.sim.clinic.staff_busy(shortage.world,nurse_id): return false
		for doctor_id: String in shortage.world.ids("staff"):
			var doctor: Dictionary = shortage.world.facts.staff[doctor_id]
			if doctor.role!="doctor" or int(doctor.abilities.diagnosis)<2 or int(doctor.abilities.treatment)<1: continue
			if doctor.on_shift or shortage.world.facts.moves.has(doctor_id) or shortage.sim.clinic.staff_busy(shortage.world,doctor_id): return false
		return true,600)
	if not off_shift:
		t.check("CLIN-27",false,{"missing":"actual_off_shift_after_safe_work_and_movement","initial_progress_tick":initial_progress,"state":_state(shortage)})
		return
	var shortage_tick: int = shortage.world.sim_tick
	var no_progress: int = int(_stay(shortage).last_progress_tick)
	# This completed boundary has processed 119.9 seconds, before the 120-second dispatch.
	await _until(t,shortage,func()->bool: return shortage.world.sim_tick>=no_progress+1200,1300)
	var early_reason: String = str(_visit(shortage).get("waiting_reason",""))
	var no_early_prompt: bool = _visit(shortage).get("final_result","").is_empty() and not early_reason.contains("排班") and not early_reason.contains("招聘") and int(_stay(shortage).get("last_progress_tick",-1))==no_progress
	await _steps(t,shortage,1)
	var reason: String = str(_visit(shortage).get("waiting_reason",""))
	var prompt: bool = _visit(shortage).get("final_result","").is_empty() and reason.contains("排班") and reason.contains("招聘") and int(_stay(shortage).get("last_progress_tick",-1))==no_progress
	_command(shortage,"clinical_visit_consent",{"visit_id":shortage.visit_id,"allow":true})
	_command(shortage,"clinical_visit_consent",{"visit_id":shortage.visit_id,"allow":false})
	shortage.sim.clinic.compare_plans(shortage.world,shortage.visit_id)
	var did_not_reset: bool = int(_stay(shortage).get("last_progress_tick",-1))==no_progress
	await _until(t,shortage,func()->bool: return shortage.world.sim_tick>no_progress+3000,1900)
	var safe_referral: bool = await _until(t,shortage,func()->bool: return _visit(shortage).get("final_result","")=="referred",700)
	t.check("CLIN-27",no_early_prompt and prompt and did_not_reset and safe_referral and _units_used(shortage)==8 and _visit(shortage).attempt_ids.size()==1 and _income(shortage,"ward")==0 and _income(shortage,"cure")==0,{"initial_progress_tick":initial_progress,"actual_shortage_boundary_tick":shortage_tick,"last_actual_progress_tick":no_progress,"no_prompt_at_119_9_seconds":no_early_prompt,"reason_before_120_seconds":early_reason,"prompt_at_120_seconds":prompt,"prompt_reason":reason,"no_reset_by_controls_or_queries":did_not_reset,"state":_state(shortage)})

func _ward_boundaries(t) -> void:
	await _ward_coverage(t)
	await _ward_round(t)
	await _ward_shortage(t)
	if _require(t,["CLIN-23","CLIN-25","CLIN-26"],"ward_after_care"):
		var two: Dictionary = _copy("ward_after_care")
		_add_worker(two.world,"additional_ward_nurse","nurse",[52,72],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":0})
		two.world.facts.staff.additional_ward_nurse.ward_id = "clin_ward"
		two.world.touch()
		var assigned: String = str(_stay(two).nurse_id)
		var before_two: int = int(_stay(two).remaining_ticks)
		await _steps(t,two,1)
		var counts: Dictionary = {}
		for work: Dictionary in two.world.facts.sessions.values():
			for worker: String in work.staff_ids: counts[worker] = int(counts.get(worker,0))+1
		var unique: bool = true
		for count: int in counts.values(): unique = unique and count<=1
		t.check("CLIN-23",int(_stay(two).remaining_ticks)==before_two-1 and str(_stay(two).nurse_id)==assigned and unique and int(_content.balance.clinical.beds_per_nurse)==8,{"remaining_before":before_two,"remaining_after":_stay(two).remaining_ticks,"active_jobs_by_staff":counts,"assigned_nurse":_stay(two).nurse_id})
		var transfer: Dictionary = _copy("ward_after_care")
		await _until(t,transfer,func()->bool: return not transfer.sim.clinic.staff_busy(transfer.world,str(_stay(transfer).nurse_id)) and not transfer.world.facts.moves.has(str(_stay(transfer).nurse_id)),180)
		var original_attempt: String = str(_stay(transfer).attempt_id)
		var original_bed: String = str(_stay(transfer).bed_id)
		var old_condition: float = float(transfer.world.facts.facilities[original_bed].condition)
		var old_remaining: int = int(_stay(transfer).remaining_ticks)
		var old_progress: int = int(_stay(transfer).last_progress_tick)
		var switched: CommandResult = _command(transfer,"clinical_transfer_bed",{"visit_id":transfer.visit_id,"bed_id":"clin_ward_1"})
		var preserved_immediately: bool = switched.accepted and int(_stay(transfer).remaining_ticks)==old_remaining and int(_stay(transfer).last_progress_tick)==old_progress and bool(_stay(transfer).care_completed)
		var arrived: bool = switched.accepted and await _until(t,transfer,func()->bool: return _stay(transfer).get("phase","")=="recovery",800)
		var no_transfer_work: bool = arrived and int(_stay(transfer).remaining_ticks)>=old_remaining-1
		await _until(t,transfer,func()->bool: return not transfer.sim.clinic.staff_busy(transfer.world,str(_stay(transfer).nurse_id)),200)
		var return_remaining: int = int(_stay(transfer).get("remaining_ticks",-1))
		var returned: CommandResult = _command(transfer,"clinical_transfer_bed",{"visit_id":transfer.visit_id,"bed_id":original_bed})
		var back: bool = returned.accepted and await _until(t,transfer,func()->bool: return _stay(transfer).get("phase","")=="recovery",800)
		t.check("CLIN-25",preserved_immediately and no_transfer_work and back and str(_stay(transfer).attempt_id)==original_attempt and bool(_stay(transfer).care_completed) and int(_stay(transfer).remaining_ticks)>=return_remaining-1 and is_equal_approx(float(transfer.world.facts.facilities[original_bed].condition),old_condition) and transfer.world.facts.facilities[original_bed].use_receipts.size()==1 and _units_used(transfer)==8 and _income(transfer,"ward")==0 and _income(transfer,"cure")==0,{"immediate_preservation":preserved_immediately,"no_work_while_transferring":no_transfer_work,"outward":switched.to_record(),"return":returned.to_record(),"state":_state(transfer)})
		var fault: Dictionary = _copy("ward_after_care")
		fault.world.facts.facilities.erase("clin_ward_1")
		_all_rest(fault.world,"mechanic")
		var bed_id: String = str(_stay(fault).bed_id)
		fault.world.facts.facilities[bed_id].failed = true
		var remaining: int = int(_stay(fault).remaining_ticks)
		var fault_origin: int = int(_stay(fault).last_progress_tick)
		var before_deadline: bool = await _until(t,fault,func()->bool: return fault.world.sim_tick>=fault_origin+1200,1300)
		var retained: bool = before_deadline and not _stay(fault).is_empty() and int(_stay(fault).get("remaining_ticks",-1))==remaining and _visit(fault).get("final_result","").is_empty() and _income(fault,"ward")==0
		var referred: bool = await _until(t,fault,func()->bool: return _visit(fault).get("final_result","")=="referred",700)
		t.check("CLIN-26",retained and referred and _stay(fault).is_empty() and _income(fault)==85 and _income(fault,"surgery")==60 and _income(fault,"ward")==0 and _income(fault,"cure")==0 and _units_used(fault)==8 and _visit(fault).attempt_ids.size()==1,{"held_until_fault_deadline":retained,"state":_state(fault)})
	if _require(t,["CLIN-28"],"ward_round"):
		var boundaries: Array = ["ward_entered","ward_care","ward_round_wait","ward_round","ward_settled"]
		var restored_all: bool = true
		var observations: Dictionary = {}
		for boundary: String in boundaries:
			if not _snapshots.has(boundary):
				restored_all = false
				observations[boundary] = "实际链路未到达此边界"
				continue
			var copy: Dictionary = _copy(boundary)
			var before: Dictionary = copy.world.freeze()
			var roundtrip: Dictionary = _roundtrip(copy)
			restored_all = restored_all and roundtrip.ok and copy.world.freeze()==before
			observations[boundary] = roundtrip
		var round_copy: Dictionary = _copy("ward_round")
		var original_round: Dictionary = _session(round_copy,"round").duplicate(true)
		var completed: bool = await _until(t,round_copy,func()->bool: return _visit(round_copy).get("final_result","")=="cured",180)
		var previous: Dictionary = round_copy.world.facts.ledger.entries.duplicate(true)
		round_copy.sim.clinic._complete_service(round_copy.world,original_round)
		HospitalLedger.settle(round_copy.world)
		var restored_end: Dictionary = _roundtrip(round_copy)
		t.check("CLIN-28",restored_all and completed and restored_end.ok and round_copy.world.facts.ledger.entries==previous and _income(round_copy,"ward")==60 and _income(round_copy,"cure")==360 and _units_used(round_copy)==8,{"boundaries":observations,"final_restore":restored_end,"state":_state(round_copy)})
	await _gentle_ward(t)

func _all_rest(world: WorldState, role: String, only_round_qualified: bool = false) -> void:
	for staff: Dictionary in world.facts.staff.values():
		if staff.role!=role: continue
		if only_round_qualified and (int(staff.abilities.diagnosis)<2 or int(staff.abilities.treatment)<1): continue
		staff.schedule = _schedule("rest")

func _gentle_ward(t) -> void:
	var c: Dictionary = _context(true,true)
	c.world.facts.staff[c.doctors[1]].abilities.treatment = 3
	_seed_stream(c.world,"treatment",true,true,9700,9800)
	var arrived: bool = _arrive(c,"B_S22_D14_M14","P_D14_GENTLE")
	var consulted: bool = arrived and await _until(t,c,func()->bool: return _visit(c).get("phase","") in ["wait_outpatient","wait_surgery"],2800)
	var coverage_wait: Dictionary = {"ok":false,"reason":"consult_missing"}
	if consulted: coverage_wait = await _wait_ward_nurse_return(t,c)
	var coverage_at_selection: Dictionary = _ward_nurse_return_state(c)
	var selected: CommandResult = _command(c,"clinical_select_plan",{"visit_id":c.visit_id,"plan_id":"P_D14_GENTLE"}) if consulted and coverage_wait.ok else CommandResult.new(false,"ward_return_incomplete",str(coverage_wait.reason))
	var began: bool = selected.accepted and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="outpatient",800)
	var attempt: Dictionary = c.world.facts.attempts.values()[0].duplicate(true) if began else {}
	var operated: bool = began and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="transfer",1300)
	var unrevealed: bool = operated and _income(c,"ward")==0 and _income(c,"cure")==0 and _visit(c).get("final_result","").is_empty()
	var completed: bool = operated and await _until(t,c,func()->bool: return _visit(c).get("final_result","")=="cured",3000)
	t.check("CLIN-29",unrevealed and completed and int(attempt.get("recovery_ticks",-1))==1800 and int(attempt.get("supply_units",-1))==4 and int(attempt.get("cure_fee",-1))==660 and int(c.started.get("wake",0))==0 and _income(c,"outpatient")==10 and _income(c,"ward")==60 and _income(c,"cure")==660 and _income(c)==790 and _units_used(c)==4 and _visit(c).attempt_ids.size()==1,{"consulted":consulted,"selected":selected.to_record(),"coverage_wait":coverage_wait,"coverage_at_selection":coverage_at_selection,"result_hidden_after_operation":unrevealed,"attempt":attempt,"state":_state(c)})

func _visitor(c: Dictionary) -> Dictionary:
	for stay: Dictionary in c.world.facts.visitors.stays.values():
		if stay.visit_id==c.visit_id: return stay
	return {}

func _remove_waiting_chairs(world: WorldState) -> void:
	for id: String in world.ids("facilities"):
		if world.facts.facilities[id].definition_id=="FUR09": world.facts.facilities.erase(id)
	world.touch()

func _companion_entry(t, report_case: bool = false) -> void:
	var companion: Dictionary = _context(false,false,false)
	_seed_stream(companion.world,"arrival",true,true,2500,5000)
	var admitted: bool = _arrive(companion,"B_S13_D09_M09","P_D09_COMMON",true)
	var requested: bool = admitted and await _until(t,companion,func()->bool: return not companion.world.facts.visitors.requests.is_empty(),180)
	var no_actor_before_space: bool = requested and companion.world.facts.visitors.requests.size()==1 and companion.world.facts.visitors.stays.is_empty() and not _visit(companion).has("relative_actor_id")
	var chair: Dictionary = _content.facility_definition("FUR09")
	HospitalFactory._add_facility(companion.world,{"id":"family_waiting_seat","definition_id":"FUR09","anchor":[34,92],"size":chair.footprint,"room_id":null},_content)
	companion.world.touch()
	var entered: bool = requested and await _until(t,companion,func()->bool: return not _visitor(companion).is_empty(),160)
	var relative: Dictionary = _visitor(companion)
	var actor: Dictionary = companion.world.facts.actors.get(relative.get("actor_id",""),{})
	var patient: Dictionary = companion.world.facts.actors.get(_visit(companion).get("actor_id",""),{})
	var from_entry: bool = false
	if not actor.is_empty() and actor.location.kind=="floor":
		var entry: Array = companion.world.facts.entry.cell
		from_entry = int(actor.location.floor_id)==1 and absf(float(actor.location.cell[0])-float(entry[0]))+absf(float(actor.location.cell[1])-float(entry[1]))<=1.0
	var no_family_income: bool = true
	for entry: Dictionary in companion.world.facts.ledger.entries.values():
		no_family_income = no_family_income and not str(entry.owner_id) in [str(relative.get("id","")),str(relative.get("actor_id",""))]
	if report_case:
		t.check("CLIN-30",no_actor_before_space and entered and from_entry and actor.get("id","")!=patient.get("id","") and actor.get("species_id","")==patient.get("species_id","") and actor.get("relative_of","")==patient.get("id","") and relative.get("visit_id","")==companion.visit_id and companion.world.facts.visitors.stays.size()==1 and no_family_income and not bool(companion.world.facts.arrivals.intake_open),{"no_actor_before_space":no_actor_before_space,"entered_from_real_entry":from_entry,"visitor":relative,"actor":actor,"state":_state(companion)})
	if entered: _remember(companion,"companion_entered")

func _visitor_bedside(t) -> Dictionary:
	if not _snapshots.has("ward_entered"): return {}
	var visiting: Dictionary = _copy("ward_entered")
	_command(visiting,"clinical_visit_consent",{"visit_id":visiting.visit_id,"allow":true})
	_seed_stream(visiting.world,"arrival",true,false,5000,5000)
	var bedside: bool = await _until(t,visiting,func()->bool: return _visitor(visiting).get("phase","")=="visiting",1000)
	if bedside: _remember(visiting,"visitor_visiting")
	visiting.bedside_ready = bedside
	return visiting

func _visitor_boundaries(t) -> void:
	await _companion_entry(t,true)
	if _require(t,["CLIN-31"],"ward_entered"):
		var visiting: Dictionary = await _visitor_bedside(t)
		var bedside: bool = bool(visiting.bedside_ready)
		var original: Dictionary = _visitor(visiting).duplicate(true)
		var window: String = str(original.get("started_window",""))
		var windows: Dictionary = _visit(visiting).get("visitor_windows",{}).duplicate(true)
		var arrival_rng: Dictionary = visiting.world.facts.rng.arrival.duplicate(true)
		var legal_point: bool = bedside and visiting.sim.space.at(visiting.world,str(original.actor_id),int(original.bedside_floor),original.bedside_cell)
		var real_clock: bool = bedside and int(original.remaining_ticks)+(visiting.world.sim_tick-int(original.started_tick))==300
		var restored: Dictionary = _roundtrip(visiting)
		await _steps(t,visiting,50)
		var once: bool = visiting.world.facts.rng.arrival==arrival_rng and _visit(visiting).get("visitor_windows",{})==windows and visiting.world.facts.visitors.stays.size()==1
		# A clinical transfer must first make the same visitor physically yield.
		var transfer: CommandResult = _command(visiting,"clinical_transfer_bed",{"visit_id":visiting.visit_id,"bed_id":"clin_ward_1"})
		if not transfer.accepted:
			await _until(t,visiting,func()->bool: return _visitor(visiting).get("phase","") in ["waiting","to_waiting","leaving"],350)
			transfer = _command(visiting,"clinical_transfer_bed",{"visit_id":visiting.visit_id,"bed_id":"clin_ward_1"})
		var transferred: bool = transfer.accepted and await _until(t,visiting,func()->bool: return _stay(visiting).get("phase","")=="recovery",800)
		t.check("CLIN-31",bedside and legal_point and real_clock and restored.ok and once and windows.get(window,{}).get("intent",false) and windows.get(window,{}).get("started",false) and transferred and _visit(visiting).get("visitor_windows",{})==windows and visiting.world.facts.rng.arrival==arrival_rng and str(_visit(visiting).get("relative_actor_id",""))==str(original.get("actor_id","")) and _income(visiting,"ward")==0 and _income(visiting,"cure")==0,{"actual_bedside_before_timer":legal_point,"exact_30_second_timer":real_clock,"single_intent_after_restore":once,"transfer":transfer.to_record(),"restore":restored,"state":_state(visiting)})
	await _visitor_exit(t)

func _visitor_exit(t) -> void:
	var missing: Array = []
	for key: String in ["visitor_visiting","ward_entered","companion_entered"]:
		if not _snapshots.has(key): missing.append(key)
	if not missing.is_empty():
		t.check("CLIN-32",false,{"missing_real_business_boundaries":missing})
		return
	var yielding: Dictionary = _copy("visitor_visiting")
	var before_visitor: Dictionary = _visitor(yielding).duplicate(true)
	var cleared: bool = yielding.sim.clinic.visitors.yield_for_care(yielding.world,yielding.visit_id)
	var began_yielding: bool = not cleared and _visitor(yielding).get("phase","")=="yielding" and yielding.world.facts.moves.has(str(before_visitor.actor_id)) and int(_visitor(yielding).get("remaining_ticks",-1))==int(before_visitor.remaining_ticks)
	await _steps(t,yielding,1)
	var same_timer: bool = int(_visitor(yielding).get("remaining_ticks",-1))<=int(before_visitor.remaining_ticks) and _visitor(yielding).get("started_tick",-1)==before_visitor.started_tick
	var refusing: Dictionary = _copy("visitor_visiting")
	var before_anger: float = float(_visit(refusing).anger)
	var before_income: int = _income(refusing)
	var original_relative: String = str(_visitor(refusing).actor_id)
	var consent: CommandResult = _command(refusing,"clinical_visit_consent",{"visit_id":refusing.visit_id,"allow":false})
	refusing.sim.clinic.visitors.dispatch(refusing.world)
	var retained_until_exit: bool = consent.accepted and not _visitor(refusing).is_empty() and refusing.world.facts.actors[original_relative].location.kind=="floor" and _visitor(refusing).get("phase","")=="leaving" and is_equal_approx(float(_visit(refusing).anger),before_anger) and _income(refusing)==before_income
	var body_observation: Dictionary = {"retained":retained_until_exit,"floor_ticks":0,"body_blocks_space":true}
	var outside_after_walk: bool = await _until(t,refusing,func()->bool:
		var relative: Dictionary = refusing.world.facts.actors.get(original_relative,{})
		if relative.is_empty():
			body_observation.retained = false
			return false
		if relative.location.kind=="floor":
			body_observation.floor_ticks += 1
			body_observation.retained = body_observation.retained and not _visitor(refusing).is_empty()
			# Ignore every other actor to query this visitor's own real body/sweep.
			var ignored: Array = refusing.world.ids("actors")
			ignored.erase(original_relative)
			body_observation.body_blocks_space = body_observation.body_blocks_space and not refusing.sim.space._dynamic_clear(refusing.world,"clinical_visitor_exit_probe",int(relative.location.floor_id),refusing.sim.space.body_rectangle(relative),ignored)
		return relative.location.kind=="outside" and _visitor(refusing).is_empty(),900)
	var pending: Dictionary = _copy("ward_entered")
	_remove_waiting_chairs(pending.world)
	_command(pending,"clinical_visit_consent",{"visit_id":pending.visit_id,"allow":true})
	_seed_stream(pending.world,"arrival",true,false,5000,5000)
	var had_request: bool = await _until(t,pending,func()->bool: return not pending.world.facts.visitors.requests.is_empty(),100)
	_command(pending,"clinical_visit_consent",{"visit_id":pending.visit_id,"allow":false})
	await _steps(t,pending,50)
	var cancelled_request: bool = had_request and pending.world.facts.visitors.requests.is_empty() and pending.world.facts.visitors.stays.is_empty()
	var leaving: Dictionary = _copy("companion_entered")
	var relative_id: String = str(_visitor(leaving).actor_id)
	var safe_boundary: bool = await _until(t,leaving,func()->bool: return str(_visit(leaving).get("phase","")).begins_with("wait_") and leaving.world.facts.sessions.is_empty(),1000)
	var referred: CommandResult = _command(leaving,"clinical_refer",{"visit_id":leaving.visit_id}) if safe_boundary else CommandResult.new(false,"safe_boundary_missing")
	var family_departed: bool = referred.accepted and await _until(t,leaving,func()->bool: return leaving.world.facts.actors[relative_id].location.kind=="outside" and _visitor(leaving).is_empty(),900)
	t.check("CLIN-32",began_yielding and same_timer and retained_until_exit and body_observation.retained and int(body_observation.floor_ticks)>0 and body_observation.body_blocks_space and outside_after_walk and cancelled_request and family_departed,{"responded_to_clinical_yield":began_yielding,"original_timer_preserved":same_timer,"consent_command":consent.to_record(),"body_retained_until_exit":retained_until_exit and body_observation.retained,"exit_body_observation":body_observation,"outside_after_walk":outside_after_walk,"pending_request_cancelled":cancelled_request,"family_left_after_patient_referral":family_departed,"state":_state(yielding)})
