extends RefCounted

const ClinicalStep = preload("res://tests/acceptance/clinical_step.gd")

var _cache: RefCounted
var _content: HospitalContent
var _simulations: Array[HospitalSimulation] = []
var _snapshots: Dictionary = {}
var _fixture_sequence: int = 0
var _fixture_failures: Array = []
var _building_key: String = ""
var _building_context: Dictionary = {}

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
	var result: TickResult = ClinicalStep.step(c.sim) if c.get("clinical_scenario",false) else c.sim.step()
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
	var error: String = c.world.validate(_content)
	if not error.is_empty():
		_fixture_failures.append({"boundary":key,"validation":error})
		return
	var state: Dictionary = {"facts":c.world.freeze(),"visit_id":c.visit_id,"serial":int(c.serial),"doctors":c.doctors.duplicate(),"started":c.started.duplicate(),"group_seen":c.group_seen,"beats":c.beats.duplicate()}
	for field: String in ["queue_gp_session","queue_ready","ward_return","plan_selection","diagnosis_trace","boundary_input"]:
		if c.has(field): state[field] = c[field]
	_snapshots[key] = state.duplicate(true)
	_building_key = key
	_building_context = c
	if not _cache.publish(key,state): _fixture_failures.append({"boundary":key,"cache_write":false})

func _copy(key: String) -> Dictionary:
	if not _snapshots.has(key): return {}
	var source: Dictionary = _snapshots[key]
	var world: WorldState = WorldState.new(source.facts.duplicate(true))
	var simulation: HospitalSimulation = HospitalSimulation.new(world,_content)
	simulation.clinic.departments = null
	_simulations.append(simulation)
	var copy: Dictionary = source.duplicate(true)
	copy.erase("facts")
	copy.sim = simulation
	copy.world = world
	copy.errors = []
	return copy

func _ensure_boundary(t, key: String) -> bool:
	var cached: Dictionary = _cache.read(key)
	if not cached.is_empty():
		_snapshots[key] = cached
		return true
	var c: Dictionary = {}
	match key:
		"gp_started":
			c = _context()
			_seed_stream(c.world,"treatment",true,true,9200,9800)
			if _arrive(c) and await _until(t,c,func()->bool: return _visit(c).get("phase","")=="gp"):
				c.queue_gp_session = _session(c,"gp").duplicate(true)
				_remember(c,key)
		"c_diagnosed":
			c = await _diagnosis_state(t,false)
			if bool(c.diagnosis_trace.third): _remember(c,key)
		"surgery_queue", "c_surgery_queue":
			c = await _surgery_queue(t,key=="c_surgery_queue")
			if _visit(c).get("phase","")=="wait_surgery": _remember(c,key)
		"companion_entered":
			await _companion_entry(t)
		"visitor_visiting":
			if await _ensure_boundary(t,"ward_entered"): c = await _visitor_bedside(t)
		_:
			var stages: Dictionary = {
				"outpatient_queue":["gp_started",2200], "outpatient_started":["outpatient_queue",2200],
				"surgery_prepared":["surgery_queue",600], "surgery_started":["surgery_prepared",600],
				"surgery_wake":["surgery_started",1800], "surgery_transfer":["surgery_wake",200],
				"ward_entered":["surgery_transfer",900], "ward_care":["ward_entered",300],
				"ward_after_care":["ward_care",350], "ward_round_wait":["ward_after_care",2200],
				"ward_round":["ward_round_wait",500], "ward_settled":["ward_round",300]}
			if not stages.has(key):
				_fixture_failures.append({"unknown_boundary":key})
				return false
			if not await _ensure_boundary(t,stages[key][0]): return false
			# A newly generated prefix can continue in the same live simulation.
			# Frozen nodes stay independent. Restored inputs always rebuild services.
			c = _building_context if _building_key==stages[key][0] else _copy(stages[key][0])
			_building_key = ""
			_building_context = {}
			if not _boundary_input(c,key): return false
			if key=="ward_care":
				var escort: String = str(_stay(c).get("escort_id",""))
				await _until(t,c,func()->bool: return not c.sim.clinic.staff_busy(c.world,escort),180)
			if await _until(t,c,func()->bool: return _at_boundary(c,key),int(stages[key][1])):
				if key=="outpatient_queue": c.queue_ready = true
				_remember(c,key)
	if not _snapshots.has(key):
		_fixture_failures.append({"missing_boundary":key,"state":_state(c) if not c.is_empty() else {}})
	return _snapshots.has(key)

func _boundary_input(c: Dictionary, key: String) -> bool:
	# These are declared input states for downstream cases. They do not prove
	# earlier travel or elapsed work. CLIN-18/19/20 exercise those actual segments.
	if key=="surgery_started":
		var preparation: Dictionary = c.world.facts.preparations[c.visit_id]
		var layout: Dictionary = c.sim.space.facility_layout(c.world,preparation.facility_id)
		var positions: Dictionary = {_visit(c).actor_id:layout.patient_cell}
		for index: int in preparation.staff_ids.size(): positions[preparation.staff_ids[index]] = layout.operator_cells[index]
		for id: String in positions:
			c.world.facts.moves.erase(id)
			c.world.facts.actors[id].location = {"kind":"floor","floor_id":int(layout.floor_id),"cell":positions[id].duplicate(),"height_m":0.0}
			c.world.facts.actors[id].posture = "standing"
			c.world.facts.actors[id].erase("support_facility_id")
		c.world.facts.sim_tick = maxi(c.world.sim_tick,int(preparation.deadline_tick)-2)
		preparation.setup_remaining_ticks = 1
		c.boundary_input = {"kind":"gathered_surgical_team","setup_remaining_ticks":1,"prior_travel_and_setup":"input"}
	elif key in ["surgery_wake","surgery_transfer","ward_after_care","ward_settled"]:
		var kinds: Dictionary = {"surgery_wake":"surgery","surgery_transfer":"wake","ward_after_care":"care","ward_settled":"round"}
		var session: Dictionary = _session(c,kinds[key])
		if session.is_empty(): return false
		var delta: int = maxi(0,int(session.remaining_ticks)-1)
		c.world.facts.sim_tick += delta
		session.remaining_ticks = 1
		if session.kind=="surgery": session.clinical_beat = 3
		if session.kind=="care": _stay(c).remaining_ticks = maxi(1,int(_stay(c).remaining_ticks)-delta)
		c.boundary_input = {"kind":"last_work_tick","service":session.kind,"remaining_ticks":1,"prior_work_ticks":"input"}
	elif key=="ward_round_wait":
		var stay: Dictionary = _stay(c)
		c.world.facts.sim_tick += maxi(0,int(stay.remaining_ticks)-1)
		stay.remaining_ticks = 1
		c.boundary_input = {"kind":"last_recovery_tick","prior_recovery_ticks":"input"}
	else:
		return true
	_visit(c).last_progress_tick = c.world.sim_tick
	_visit(c).last_service_tick = c.world.sim_tick
	if not _stay(c).is_empty():
		_stay(c).last_progress_tick = c.world.sim_tick
		if _stay(c).has("coverage_segment"): _stay(c).coverage_segment.start_tick = c.world.sim_tick
	c.world.touch()
	var validation: String = c.world.validate(_content)
	print("FIXTURE_INPUT "+JSON.stringify({"for_boundary":key,"input":c.boundary_input,"validation":validation}))
	if not validation.is_empty(): _fixture_failures.append({"boundary_input":key,"validation":validation})
	return validation.is_empty()

func _at_boundary(c: Dictionary, key: String) -> bool:
	var phase: String = str(_visit(c).get("phase",""))
	match key:
		"outpatient_queue": return phase=="wait_outpatient" and c.world.facts.preparations.has(c.visit_id) and _visit(c).attempt_ids.is_empty()
		"outpatient_started": return phase=="outpatient"
		"surgery_prepared": return c.world.facts.preparations.has(c.visit_id)
		"surgery_started": return phase=="surgery"
		"surgery_wake": return phase=="wake"
		"surgery_transfer": return phase=="transfer"
		"ward_entered": return phase=="recovery"
		"ward_care": return not _session(c,"care").is_empty()
		"ward_after_care": return bool(_stay(c).get("care_completed",false))
		"ward_round_wait": return _stay(c).get("phase","")=="round_wait"
		"ward_round": return not _session(c,"round").is_empty()
		"ward_settled": return not _visit(c).get("final_result","").is_empty()
	return false

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
	if not c_profile:
		# The normal patient already completed real reception, GP and consultation.
		# Add the legal surgical resources to this input hospital instead of
		# admitting another patient and evaluating every alternative plan again.
		if not await _ensure_boundary(t,"outpatient_queue"): return _context(true)
		var queued: Dictionary = _copy("outpatient_queue")
		for definition: Dictionary in _content.catalog.research:
			if not definition.id in queued.world.facts.research: queued.world.facts.research.append(definition.id)
		queued.world.facts.staff[queued.doctors[1]].abilities.treatment = 2
		_add_layout(queued.world,"or_standard","clin_or",[33,65])
		_add_layout(queued.world,"ward_two_beds","clin_ward",[45,65])
		_add_worker(queued.world,"clin_surgeon","doctor",[34,75],"surgery",{"diagnosis":1,"treatment":1,"care":0,"surgery":2},"DT02")
		_add_worker(queued.world,"clin_anesthesia","doctor",[38,75],"surgery",{"diagnosis":1,"treatment":1,"care":0,"surgery":2},"DT02")
		_add_worker(queued.world,"clin_or_nurse","nurse",[42,75],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":1})
		queued.world.facts.staff.clin_or_nurse.certificates = ["q_or","q_ward"]
		_add_worker(queued.world,"clin_cover","nurse",[46,72],"work",{"diagnosis":1,"treatment":0,"care":1,"surgery":0})
		queued.world.facts.staff.clin_cover.ward_id = "clin_ward"
		_add_worker(queued.world,"clin_round","doctor",[51,72],"round",{"diagnosis":2,"treatment":1,"care":0,"surgery":0})
		queued.world.touch()
		queued.sim._ensure_services()
		var selected: CommandResult = _command(queued,"clinical_select_plan",{"visit_id":queued.visit_id,"plan_id":"P_D09_SURGERY"})
		queued.plan_selection = selected.to_record()
		queued.ward_return = {"ok":true,"reason":"normal_profile"}
		if not selected.accepted: queued.errors.append({"select_surgery":selected.to_record()})
		return queued
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

func _failure_world(case_id: String, world: WorldState) -> Dictionary:
	if world==null: return {"ok":false,"error":"缺少实际模拟世界"}
	var path: String = "res://"+case_id+"-failure-"+HospitalSnapshots.uuid()+".json"
	var encoder: HospitalJsonStream = HospitalJsonStream.new()
	var encoded: bool = encoder.encode(path,world.freeze(),func(_bytes: int)->bool: return true)
	return {"ok":encoded,"path":ProjectSettings.globalize_path(path),"bytes":encoder.bytes,"sha256":encoder.digest,"error":encoder.error,"tick":world.sim_tick}

func _all_rest(world: WorldState, role: String, only_round_qualified: bool = false) -> void:
	for staff: Dictionary in world.facts.staff.values():
		if staff.role!=role: continue
		if only_round_qualified and (int(staff.abilities.diagnosis)<2 or int(staff.abilities.treatment)<1): continue
		staff.schedule = _schedule("rest")

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
	var trace: Array = []
	var bedside: bool = await _until(t,visiting,func()->bool:
		var visitor: Dictionary = _visitor(visiting)
		var phase: String = str(visitor.get("phase","absent"))
		if trace.is_empty() or trace.back().phase!=phase:
			trace.append({"tick":visiting.world.sim_tick,"phase":phase,"visitor":visitor.duplicate(true),"care_completed":_stay(visiting).get("care_completed",false),"sessions":visiting.world.facts.sessions.duplicate(true)})
		return phase=="visiting",1000)
	if bedside: _remember(visiting,"visitor_visiting")
	visiting.bedside_ready = bedside
	visiting.visitor_trace = trace
	if not bedside: visiting.failure_world = _failure_world("visitor_bedside",visiting.world)
	return visiting

func _diagnosis_state(t, upgraded: bool) -> Dictionary:
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
	c.diagnosis_trace = {"third":third,"gp":gp_evidence,"after_spectrum":after_spectrum,"total":total}
	return c
