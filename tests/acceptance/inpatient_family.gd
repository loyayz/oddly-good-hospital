extends "res://tests/acceptance/clinical_fixtures.gd"

const CASES: Dictionary = {
	"FAMILY-01":"统一临床规格§2；普通门诊全程不产生家属或陪诊抽签",
	"FAMILY-02":"统一临床规格§4、8；首次实际住院80%精确边界与幂等",
	"FAMILY-03":"统一临床规格§5、8；每日30%精确边界，与陪同资格独立",
	"FAMILY-04":"统一临床规格§5、9；同日早中班、扫描与读档只评估一次",
	"FAMILY-05":"统一临床规格§4.2；夜间真实离开、次日同一演员真实返院",
	"FAMILY-06":"统一临床规格§5.2、6；两类不同家属合法共处，入房即计时",
	"FAMILY-07":"统一临床规格§4.3；真实手术随行、室外等待及原病房返回",
	"FAMILY-08":"统一临床规格§7.1；实际开工的日夜边界与已开术安全完成",
	"FAMILY-09":"统一临床规格§4.2；跨夜手术实际回房后陪同才离院",
	"FAMILY-10":"统一临床规格§5.3；术中来访跨夜等待后完成有效探视",
	"FAMILY-11":"统一临床规格§6；12秒后医疗打断，两类实际出房、暂停余量",
	"FAMILY-12":"统一临床规格§5.2；300有效步后实际离院，不转换角色或产生生活需求",
	"FAMILY-13":"统一临床规格§4.3；饮水和如厕不阻患者，完成后先真实返房",
	"FAMILY-14":"统一临床规格§4.3；生活返房时按患者现状继续，不追过期术台",
	"FAMILY-15":"统一临床规格§7.2；出院终止探视和请求，设施与运输安全退出",
	"FAMILY-16":"统一临床规格§9；换床、重试、夜间及暂停存档保留身份和进度",
	"FAMILY-17":"统一临床规格§6、8；真实身体与受阻入口合法等待，不缩身或夺医疗位置",
	"FAMILY-18":"统一临床规格§8；停止接诊不取消家属，同意探视仅约束探视者",
	"FAMILY-19":"统一临床规格§9；双角色、往返和终结不额外收费或无限累积身份"
}

var _admission_source: Dictionary = {}
var _source_attempted: bool = false
var _source_observation: Dictionary = {}
var _named_sources: Dictionary = {}
var _case_sources: Array = []
var _case_failures: Array = []
var _draw_inputs: Dictionary = {}

func run(t, content: HospitalContent = null, selected: Array = []) -> void:
	_content=content if content!=null else HospitalContent.new()
	for id: String in CASES:
		if not t.wants(id) or not selected.is_empty() and not id in selected: continue
		t.begin_case(id)
		_case_sources.clear()
		_case_failures.clear()
		if not _content.error.is_empty():
			t.check(id,false,{"content_error":_content.error})
			continue
		if id!="FAMILY-01" and _source_attempted and _admission_source.is_empty():
			_case_sources.append(_source_observation.duplicate(true))
			_report(t,id,{"required_admission_precondition":false},{"execution":"precondition_failed"})
			continue
		await call("_case_"+id.right(2),t)
	_dispose_simulations()

func _exact_input(world: WorldState, stream: String, value: int) -> void:
	if not _draw_inputs.has(value):
		for seed_value: int in range(1,2000000):
			var generator:=RandomNumberGenerator.new()
			generator.seed=seed_value
			var initial: int=generator.state
			if generator.randi_range(0,9999)==value:
				_draw_inputs[value]={"algorithm":"godot-pcg32-4.7.2","seed_decimal":str(seed_value),"state_decimal":str(initial)}
				break
	assert(_draw_inputs.has(value),"No exact probability input")
	world.facts.rng[stream]=_draw_inputs[value].duplicate(true)

func _copy_facts(facts: Dictionary, visit_id: String) -> Dictionary:
	var world:=WorldState.new(facts.duplicate(true))
	var simulation:=HospitalSimulation.new(world,_content)
	_simulations.append(simulation)
	var serial: int=0
	for command_id: String in world.facts.command_receipts:
		if not command_id.begins_with("clinical_command_"): continue
		var suffix: String=command_id.trim_prefix("clinical_command_")
		if suffix.is_valid_int(): serial=maxi(serial,int(suffix))
	return {"world":world,"sim":simulation,"visit_id":visit_id,"serial":serial,"started":{},"beats":{},"group_seen":false,"errors":[],"fixture_ready":true,"clinical_scenario":true,"capture_events":false}

func _source(t) -> Dictionary:
	if not _source_attempted:
		_source_attempted=true
		var started: int=Time.get_ticks_msec()
		var c: Dictionary=await _surgery_queue(t,false,true)
		if not c.get("before_admission",{}).is_empty(): _admission_source=c.before_admission.duplicate(true)
		_source_observation={"name":"before_admission","producer":"clinical_fixtures._surgery_queue","generation_ms":Time.get_ticks_msec()-started,"status":"ready" if not _admission_source.is_empty() else "failed"}
		if _admission_source.is_empty(): _source_observation.failure=_compact_failure(c,"before_admission","producer did not reach actual admission")
		t.preparation_elapsed(started)
	_case_sources.append(_source_observation.duplicate(true))
	return _admission_source

func _compact_failure(c: Dictionary, boundary: String, reason: String) -> Dictionary:
	var visit: Dictionary=_visit(c)
	var ward: Dictionary=_stay(c)
	var selected: Dictionary=c.get("plan_selection",{})
	var errors: Array=[]
	for row: Dictionary in c.get("errors",[]):
		if row.has("missing"): errors.append({"missing":row.missing})
		elif row.has("select_surgery"): errors.append({"code":row.select_surgery.get("code",""),"reason":row.select_surgery.get("reason","")})
		else: errors.append({"fields":row.keys()})
	var staff: Array=[]
	for id: String in ["clin_cover","clin_or_nurse","clin_surgeon","clin_anesthesia"]:
		var value: Dictionary=c.world.facts.staff.get(id,{})
		if not value.is_empty(): staff.append({"id":id,"on_shift":value.on_shift,"base_prepared":value.get("base_prepared",false),"ward_id":value.get("ward_id",""),"life_phase":value.get("life_task",{}).get("phase","idle"),"clinical_release":value.has("clinical_release")})
	var family: Array=[]
	for stay: Dictionary in c.world.facts.get("visitors",{}).get("stays",{}).values():
		if stay.visit_id==c.visit_id: family.append({"purpose":stay.purpose,"phase":stay.phase,"remaining_ticks":stay.remaining_ticks,"life_phase":stay.get("life_task",{}).get("phase",""),"location":c.world.facts.actors[stay.actor_id].location.duplicate(true)})
	return {"boundary":boundary,"reason":reason,"tick":c.world.sim_tick,"visit_phase":visit.get("phase",""),"waiting_reason":visit.get("waiting_reason",""),"diagnosis_state":visit.get("diagnosis",{}).get("state",""),"selection":{"accepted":selected.get("accepted",false),"code":selected.get("code",""),"reason":selected.get("reason","")},"ward":{"phase":ward.get("phase",""),"bed_id":ward.get("bed_id",""),"admitted_tick":ward.get("admitted_tick",-1)},"errors":errors,"staff":staff,"family":family,"request_count":c.world.facts.get("visitors",{}).get("requests",{}).size()}

func _failed_input(c: Dictionary, boundary: String, reason: String) -> Dictionary:
	_case_failures.append(_compact_failure(c,boundary,reason))
	return {}

func _failed_source(name: String, c: Dictionary, reason: String, started: int) -> Dictionary:
	var failure: Dictionary=_compact_failure(c,name,reason)
	_named_sources[name]={"failure":failure,"observation":{"name":name,"status":"failed","generation_ms":Time.get_ticks_msec()-started}}
	_case_failures.append(failure)
	return {}

func _remember_source(name: String, c: Dictionary, generation_ms: int, extras: Dictionary = {}) -> void:
	_named_sources[name]={"facts":c.world.freeze(),"visit_id":c.visit_id,"extras":extras.duplicate(true),"content_identity":_content.snapshot_identity().duplicate(true),"execution_identity":{"engine":Engine.get_version_info().get("string",""),"process_id":OS.get_process_id()},"observation":{"name":name,"producer":"production ClinicalStep","based_on":"before_admission","generation_ms":generation_ms,"source_tick":c.world.sim_tick,"status":"ready"}}

func _read_source(t, name: String) -> Dictionary:
	var started: int=Time.get_ticks_msec()
	var source: Dictionary=_named_sources[name]
	var observation: Dictionary=source.observation.duplicate(true)
	if source.has("failure"):
		_case_failures.append(source.failure.duplicate(true))
		_case_sources.append(observation)
		return {}
	var c: Dictionary=_copy_facts(source.facts,source.visit_id)
	var validation: String=c.world.validate(_content)
	if source.content_identity!=_content.snapshot_identity() or source.execution_identity.engine!=Engine.get_version_info().get("string","") or source.execution_identity.process_id!=OS.get_process_id(): validation="named source content or execution identity changed"
	c.merge(source.extras.duplicate(true))
	observation.read_ms=Time.get_ticks_msec()-started
	observation.validation=validation
	_case_sources.append(observation)
	t.preparation_elapsed(started)
	if not validation.is_empty(): return _failed_input(c,name,validation)
	return c

func _admitted(t, companion: bool = true, visitor: bool = true, hold_surgery: bool = true) -> Dictionary:
	var source: Dictionary=await _source(t)
	if source.is_empty(): return {}
	var c: Dictionary=_copy_facts(source.facts,source.visit_id)
	_exact_input(c.world,"arrival",7999 if companion else 8000)
	_tick(c)
	if not _stay(c).has("admitted_tick"): return _failed_input(c,"actual_admission","copied before_admission did not admit on the next production step")
	if hold_surgery:
		var closed: CommandResult=_command(c,"build_room_open",{"target_id":"clin_or","open_intent":false})
		if not closed.accepted: return _failed_input(c,"hold_surgery",closed.code+": "+closed.reason)
	_exact_input(c.world,"arrival",2999 if visitor else 3000)
	var evaluated: bool=await _until(t,c,func()->bool:return int(_stay(c).get("visitor_day",-1))==c.world.sim_tick/WorldState.TICKS_PER_DAY,60)
	return c if evaluated else _failed_input(c,"first_daily_intent","daily visit intent was not evaluated within the next scan")

func _with_family(t, companion: bool = true, visitor: bool = true) -> Dictionary:
	var name: String="family_in_ward:%s:%s"%[companion,visitor]
	if _named_sources.has(name): return _read_source(t,name)
	var started: int=Time.get_ticks_msec()
	var c: Dictionary=await _admitted(t,companion,visitor)
	if c.is_empty(): return {}
	var arrived: bool=await _until(t,c,func()->bool:
		return (not companion or not _role(c,"companion").is_empty() and _inside(c,_role(c,"companion").actor_id)) and (not visitor or not _role(c,"ward_visit").is_empty() and _inside(c,_role(c,"ward_visit").actor_id)),1200)
	if not arrived:
		var failure: Dictionary=_compact_failure(c,name,"required family bodies did not actually enter the ward")
		_named_sources[name]={"failure":failure,"observation":{"name":name,"status":"failed","generation_ms":Time.get_ticks_msec()-started}}
		_case_failures.append(failure)
		return {}
	_remember_source(name,c,Time.get_ticks_msec()-started)
	_case_sources.append(_named_sources[name].observation.duplicate(true))
	return c

func _role(c: Dictionary, purpose: String) -> Dictionary:
	return c.sim.clinic.visitors._role(c.world,c.visit_id,purpose)

func _inside(c: Dictionary, actor_id: String) -> bool:
	return c.sim.clinic.visitors._inside_ward(c.world,actor_id,_stay(c))

func _outside(c: Dictionary, actor_id: String) -> bool:
	return not c.sim.clinic.visitors._overlaps_ward(c.world,actor_id,_stay(c))

func _spatially_forgotten(c: Dictionary, actor_id: String) -> bool:
	var space: HospitalSpace=c.sim.space
	if space._actor_index._records.has(actor_id) or space._actor_shapes.has(actor_id): return false
	var areas: HospitalPublicAreas=space.public_areas
	return areas._decision_world==null or areas._decision_world.get_ref()!=c.world or not areas._wait_dependencies._actors.has(actor_id)

func _report(t, id: String, checks: Dictionary, details: Dictionary = {}) -> void:
	details.checks=checks
	if not _case_sources.is_empty(): details.preconditions=_case_sources.duplicate(true)
	if not _case_failures.is_empty(): details.precondition_failures=_case_failures.duplicate(true)
	t.check(id,not checks.is_empty() and not false in checks.values(),details)

# Named inputs at shift boundaries retain every body, route and work amount.
# Only absolute timestamps move together; the tested entry/exit still walks.
func _clock_boundary(c: Dictionary, tick: int, nurse_night: bool = false) -> Dictionary:
	var facts: Dictionary=c.world.freeze()
	_shift_ticks(facts,tick-int(facts.sim_tick))
	if nurse_night:
		facts.staff.clin_cover.schedule=[{"kind":"rest","pools":[],"locked":false},{"kind":"work","pools":["clin_ward"],"locked":false},{"kind":"work","pools":["clin_ward"],"locked":false}]
	var result: Dictionary=_copy_facts(facts,c.visit_id)
	print("CASE_INPUT "+JSON.stringify({"boundary":"family_shift_boundary","source_tick":c.world.sim_tick,"start_tick":tick,"nursing_night_coverage":nurse_night}))
	return result

func _shift_ticks(value: Variant, delta: int) -> void:
	if value is Dictionary:
		for key: Variant in value.keys():
			if (str(key)=="tick" or str(key).ends_with("_tick")) and (value[key] is int or value[key] is float) and int(value[key])>=0: value[key]=int(value[key])+delta
			else: _shift_ticks(value[key],delta)
	elif value is Array:
		for child: Variant in value: _shift_ticks(child,delta)

func _case_01(t) -> void:
	var c: Dictionary=_context()
	c.clinical_scenario=true
	_exact_input(c.world,"treatment",9999)
	var random_before: Dictionary=c.world.facts.rng.arrival.duplicate(true)
	var arrived: bool=_arrive(c)
	var done: bool=arrived and await _until(t,c,func()->bool:return _visit(c).phase=="departed",3000)
	var relatives: int=0
	for actor: Dictionary in c.world.facts.actors.values():
		if actor.has("relative_of"): relatives+=1
	_report(t,"FAMILY-01",{"departed":done,"no_requests":c.world.facts.visitors.requests.is_empty(),"no_relatives":c.world.facts.visitors.stays.is_empty() and relatives==0,"no_companion_draw":random_before==c.world.facts.rng.arrival})

func _case_02(t) -> void:
	var source: Dictionary=await _source(t)
	var checks: Dictionary={"actual_admission_input":not source.is_empty()}
	var observations: Dictionary={}
	if not source.is_empty():
		for roll: int in [7999,8000]:
			var c: Dictionary=_copy_facts(source.facts,source.visit_id)
			_exact_input(c.world,"arrival",roll)
			_tick(c)
			var ward: Dictionary=_stay(c)
			var random_after: Dictionary=c.world.facts.rng.arrival.duplicate(true)
			var qualified_before: bool=bool(ward.companion_qualified)
			var visitor_day_before: int=int(ward.visitor_day)
			c.sim.clinic.visitors.admission(c.world,_visit(c),ward)
			checks["direct_repeat_%d"%roll]=random_after==c.world.facts.rng.arrival and bool(ward.companion_qualified)==qualified_before and ward.companion_evaluated
			var validation_before: String=c.world.validate(_content)
			var saved: Dictionary=_roundtrip(c)
			var random_restored: Dictionary=c.world.facts.rng.arrival.duplicate(true)
			if saved.get("ok",false): c.sim.clinic.visitors.admission(c.world,_visit(c),_stay(c))
			checks["roll_%d"%roll]=ward.has("admitted_tick") and ward.companion_evaluated and bool(ward.companion_qualified)==(roll==7999)
			var rng_same: bool=random_after==c.world.facts.rng.arrival
			var qualified_same: bool=bool(_stay(c).companion_qualified)==qualified_before
			checks["stable_%d"%roll]=saved.get("ok",false) and rng_same and qualified_same
			observations[str(roll)]={"world_validation_before":validation_before,"roundtrip_ok":saved.get("ok",false),"roundtrip_error":saved.get("error",""),"rng_same_after_restore":random_after==random_restored,"rng_same_after_repeat":rng_same,"qualification_same":qualified_same,"repeat_after_restore_called":saved.get("ok",false),"visitor_day_before":visitor_day_before,"visitor_day_after":_stay(c).visitor_day}
			var receipt_count: int=c.world.facts.command_receipts.size()
			var serial_before: int=int(c.serial)
			var consent: CommandResult=_command(c,"clinical_visit_consent",{"visit_id":c.visit_id,"allow":false})
			checks["fresh_command_identity_%d"%roll]=consent.accepted and not _visit(c).visitor_consent and int(c.serial)==serial_before+1 and c.world.facts.command_receipts.size()==receipt_count+1
			var input: Dictionary=c.world.freeze()
			input.waiting_life.clocks[c.visit_id].next_need_tick=int(input.sim_tick)
			var inpatient: Dictionary=_copy_facts(input,c.visit_id)
			var actor_before: Dictionary=inpatient.world.facts.actors[_visit(inpatient).actor_id].duplicate(true)
			var move_before: Dictionary=inpatient.world.facts.moves.get(_visit(inpatient).actor_id,{}).duplicate(true)
			inpatient.sim.services.waiting.dispatch(inpatient.world)
			checks["ward_owns_patient_%d"%roll]=not inpatient.sim.services.waiting._waiting_ticket(inpatient.world,_visit(inpatient)) and not inpatient.world.facts.waiting_life.needs.has(inpatient.visit_id) and not inpatient.world.facts.waiting_life.seats.has(inpatient.visit_id) and inpatient.world.facts.actors[_visit(inpatient).actor_id]==actor_before and inpatient.world.facts.moves.get(_visit(inpatient).actor_id,{})==move_before
			var called: bool=inpatient.sim.services.waiting.call_patient(inpatient.world,inpatient.visit_id)
			checks["ward_call_keeps_bed_support_%d"%roll]=called and actor_before.posture=="lying" and inpatient.world.facts.actors[_visit(inpatient).actor_id]==actor_before and not inpatient.world.facts.moves.has(_visit(inpatient).actor_id)
			var bed: Dictionary=inpatient.sim.space.facility_layout(inpatient.world,_stay(inpatient).bed_id)
			var moving: String=inpatient.sim.space.request_move(inpatient.world,_visit(inpatient).actor_id,int(bed.floor_id),bed.patient_cell)
			var support_move: Dictionary=inpatient.world.facts.moves.get(_visit(inpatient).actor_id,{})
			checks["clinical_move_owns_support_exit_%d"%roll]=moving.is_empty() and not support_move.get("path",[]).is_empty() and support_move.path[0].kind=="support_exit" and inpatient.world.facts.actors[_visit(inpatient).actor_id]==actor_before
	_report(t,"FAMILY-02",checks,{"roundtrips":observations})

func _case_03(t) -> void:
	var checks: Dictionary={}
	for companion: bool in [false,true]:
		for visitor: bool in [false,true]:
			var c: Dictionary=await _admitted(t,companion,visitor)
			checks["companion_%s_visitor_%s"%[companion,visitor]]=not c.is_empty() and bool(_stay(c).companion_qualified)==companion and bool(_stay(c).visitor_intent)==visitor
	_report(t,"FAMILY-03",checks)

func _case_04(t) -> void:
	var c: Dictionary=await _admitted(t,false,false)
	var checks: Dictionary={"daily_input":not c.is_empty()}
	if not c.is_empty():
		c=_clock_boundary(c,5998)
		var random_after: Dictionary=c.world.facts.rng.arrival.duplicate(true)
		var restored: Dictionary=_roundtrip(c)
		await _steps(t,c,105)
		checks.saved=restored.get("ok",false)
		checks.no_midday_redraw=_stay(c).visitor_day==0 and not _stay(c).visitor_intent and random_after==c.world.facts.rng.arrival
		checks.no_second_request=c.world.facts.visitors.requests.is_empty() and c.world.facts.visitors.stays.is_empty()
	_report(t,"FAMILY-04",checks)

func _case_05(t) -> void:
	var c: Dictionary=await _with_family(t,true,false)
	var checks: Dictionary={"actual_companion_input":not c.is_empty()}
	if not c.is_empty():
		var actor_id: String=str(_role(c,"companion").actor_id)
		c=_clock_boundary(c,11999,true)
		var exited: bool=await _until(t,c,func()->bool:return _role(c,"companion").get("phase","")=="outside",1100)
		checks.real_night_exit=exited and c.world.facts.actors[actor_id].location.kind=="outside" and not c.world.facts.moves.has(actor_id)
		if exited:
			c=_clock_boundary(c,17999)
			_exact_input(c.world,"arrival",3000)
			var entered: bool=await _until(t,c,func()->bool:return _role(c,"companion").get("actor_id","")==actor_id and _inside(c,actor_id),1100)
			checks.same_identity_returns=entered and _stay(c).companion_evaluated and _stay(c).companion_actor_id==actor_id
			checks.one_companion=c.world.facts.visitors.stays.size()==1
	_report(t,"FAMILY-05",checks)

func _case_06(t) -> void:
	var c: Dictionary=await _with_family(t,true,true)
	var checks: Dictionary={"two_actual_entries":not c.is_empty()}
	if not c.is_empty():
		var companion: Dictionary=_role(c,"companion")
		var visitor: Dictionary=_role(c,"ward_visit")
		var bed: Dictionary=c.sim.space.facility_layout(c.world,_stay(c).bed_id)
		checks.different_people=companion.actor_id!=visitor.actor_id
		checks.non_bed_positions=not c.sim.space.at(c.world,companion.actor_id,int(bed.floor_id),bed.patient_cell) and not c.sim.space.at(c.world,visitor.actor_id,int(bed.floor_id),bed.patient_cell)
		checks.counted_on_entry=int(visitor.remaining_ticks)<300
		checks.real_bodies_clear=not c.sim.space.body_rectangle(c.world.facts.actors[companion.actor_id]).intersects(c.sim.space.body_rectangle(c.world.facts.actors[visitor.actor_id]),false)
		checks.spatial_and_identity_valid=c.world.validate(_content).is_empty() and c.sim.clinic.validate(c.world).is_empty()
	_report(t,"FAMILY-06",checks)

func _open_surgery(c: Dictionary) -> bool:
	return _command(c,"build_room_open",{"target_id":"clin_or","open_intent":true}).accepted

func _before_start(t, c: Dictionary) -> Dictionary:
	if not _open_surgery(c): return {}
	for index: int in 1600:
		var facts: Dictionary=c.world.freeze()
		_tick(c)
		if not _visit(c).attempt_ids.is_empty(): return {"facts":facts,"visit_id":c.visit_id}
		if index%100==99: await t.process_frame
	return {}

func _or_outside(c: Dictionary, actor_id: String) -> bool:
	if not c.world.facts.actors.has(actor_id): return false
	var actor: Dictionary=c.world.facts.actors[actor_id]
	var table_id: String=""
	for id: String in c.world.facility_ids("EQ01"): table_id=id; break
	if table_id.is_empty() or actor.location.kind!="floor": return false
	return c.sim.clinic.visitors.waiting_scope.allows(c.world,actor_id,table_id,int(actor.location.floor_id),actor.location.cell)

func _returned_from_surgery(t, c: Dictionary, purpose: String = "companion", visitor_clock: Dictionary = {}) -> Dictionary:
	var trace: Dictionary={"started":false,"actual_or_wait":false,"never_entered_or":true,"kept_original_bed":true,"did_not_leave_early":true,"returned":false,"wake_seen":false}
	var bed_id: String=str(_stay(c).bed_id)
	for index: int in 3400:
		var relative: Dictionary=_role(c,purpose)
		var ward: Dictionary=_stay(c)
		if ward.is_empty(): break
		trace.kept_original_bed=trace.kept_original_bed and str(ward.bed_id)==bed_id
		trace.started=trace.started or not _visit(c).attempt_ids.is_empty()
		trace.wake_seen=trace.wake_seen or not _session(c,"wake").is_empty()
		if not relative.is_empty():
			var actor: Dictionary=c.world.facts.actors[relative.actor_id]
			trace.actual_or_wait=trace.actual_or_wait or _or_outside(c,relative.actor_id)
			if actor.location.kind=="floor":
				var room: Dictionary=c.world.facts.rooms.clin_or
				if int(actor.location.floor_id)==int(room.floor_id) and c.sim.space.room_contains(room,c.sim.space.body_rectangle(actor)): trace.never_entered_or=false
			if purpose=="companion" and relative.phase in ["leaving","outside"] and not ward.phase in ["recovery","waiting_surgery"]: trace.did_not_leave_early=false
		if trace.started and ward.phase=="recovery" and _inside(c,_visit(c).actor_id):
			trace.returned=true
			break
		_tick(c)
		if not visitor_clock.is_empty(): _observe_visit_clock(c,visitor_clock)
		if index%100==99: await t.process_frame
	trace.bed_id=bed_id
	return trace

func _case_07(t) -> void:
	var c: Dictionary=await _with_family(t,true,false)
	var checks: Dictionary={"real_ward_companion":not c.is_empty()}
	if not c.is_empty():
		var actor_id: String=str(_role(c,"companion").actor_id)
		_exact_input(c.world,"treatment",0)
		checks.opened=_open_surgery(c)
		var trace: Dictionary=await _returned_from_surgery(t,c)
		checks.actual_tour=trace.started and trace.actual_or_wait and trace.returned and trace.wake_seen
		checks.medical_space=trace.never_entered_or and trace.kept_original_bed
		checks.same_person_back=await _until(t,c,func()->bool:return not _role(c,"companion").is_empty() and _role(c,"companion").actor_id==actor_id and _inside(c,actor_id),900)
	_report(t,"FAMILY-07",checks)

func _case_08(t) -> void:
	var c: Dictionary=await _with_family(t,true,false)
	var checks: Dictionary={"family_input":not c.is_empty()}
	if not c.is_empty():
		var boundary: Dictionary=await _before_start(t,c)
		checks.actual_ready_input=not boundary.is_empty()
		if not boundary.is_empty():
			for night: bool in [false,true]:
				var start: Dictionary=_copy_facts(boundary.facts,boundary.visit_id)
				start=_clock_boundary(start,12000 if night else 11999,true)
				for id: String in ["clin_surgeon","clin_anesthesia","clin_or_nurse"]:
					var staff: Dictionary=start.world.facts.staff[id]
					staff.schedule=[{"kind":"rest","pools":[],"locked":false},{"kind":"surgery" if staff.role=="doctor" else "work","pools":["clin_or"],"locked":false},{"kind":"surgery" if staff.role=="doctor" else "work","pools":["clin_or"],"locked":false}]
				_exact_input(start.world,"treatment",0)
				_tick(start)
				checks["night_refuses" if night else "last_day_tick_starts"]=_visit(start).attempt_ids.is_empty() if night else _visit(start).attempt_ids.size()==1
				if not night:
					var trace: Dictionary=await _returned_from_surgery(t,start)
					checks.started_finishes_safely=trace.returned and trace.wake_seen and trace.kept_original_bed
	_report(t,"FAMILY-08",checks)

func _case_09(t) -> void:
	var c: Dictionary=await _with_family(t,true,false)
	var checks: Dictionary={"real_companion_input":not c.is_empty()}
	if not c.is_empty():
		c=_clock_boundary(c,11300,true)
		var actor_id: String=str(_role(c,"companion").actor_id)
		_exact_input(c.world,"treatment",0)
		checks.opened=_open_surgery(c)
		var trace: Dictionary=await _returned_from_surgery(t,c)
		checks.crossed_night=trace.returned and c.world.sim_tick>=12000 and trace.actual_or_wait and trace.wake_seen
		checks.waited_for_actual_return=trace.did_not_leave_early and c.world.facts.actors[actor_id].location.kind!="outside"
		checks.departed_after_return=await _until(t,c,func()->bool:return _role(c,"companion").get("phase","")=="outside",1000)
	_report(t,"FAMILY-09",checks)

func _case_10(t) -> void:
	var c: Dictionary=await _admitted(t,false,true,false)
	var checks: Dictionary={"daily_visitor_input":not c.is_empty()}
	var observation: Dictionary={}
	if not c.is_empty():
		c=_clock_boundary(c,11400,true)
		_exact_input(c.world,"treatment",0)
		var clock: Dictionary={"initial_remaining":int(_role(c,"ward_visit").get("remaining_ticks",300)),"last_remaining":300,"eligible_ticks":0,"consumed_ticks":0,"no_outside_credit":true,"each_eligible_tick_counted":true,"first_credit":{},"first_mismatch":{}}
		var trace: Dictionary=await _returned_from_surgery(t,c,"ward_visit",clock)
		var visitor: Dictionary=_role(c,"ward_visit")
		checks.waited_outside=trace.actual_or_wait and trace.never_entered_or and trace.returned and not visitor.is_empty()
		observation.patient_return={"tick":c.world.sim_tick,"remaining_ticks":visitor.get("remaining_ticks",-1),"eligible_ticks":clock.eligible_ticks,"consumed_ticks":clock.consumed_ticks}
		var actor_id: String=str(visitor.get("actor_id",""))
		for index: int in 1600:
			if _role(c,"ward_visit").is_empty() and not c.world.facts.actors.has(actor_id): break
			_tick(c)
			_observe_visit_clock(c,clock)
			if index%100==99: await t.process_frame
		checks.no_travel_credit=clock.initial_remaining==300 and clock.no_outside_credit and clock.each_eligible_tick_counted and int(clock.eligible_ticks)==300 and int(clock.consumed_ticks)==300
		checks.visits_after_night=not clock.first_credit.is_empty() and int(clock.first_credit.tick)>=12000 and clock.first_credit.ward_phase=="recovery" and int(clock.first_credit.tick)<=int(observation.patient_return.tick)+600
		checks.real_exit=not clock.first_credit.is_empty() and _role(c,"ward_visit").is_empty() and not c.world.facts.actors.has(actor_id)
		observation.clock=clock
	_report(t,"FAMILY-10",checks,observation)

func _observe_visit_clock(c: Dictionary, clock: Dictionary) -> void:
	var visitor: Dictionary=_role(c,"ward_visit")
	if visitor.is_empty():
		if int(clock.last_remaining)<300 and int(clock.last_remaining)>0: clock.no_outside_credit=false
		return
	var remaining: int=int(visitor.remaining_ticks)
	var consumed: int=int(clock.last_remaining)-remaining
	var ward: Dictionary=_stay(c)
	if ward.is_empty():
		clock.no_outside_credit=false
		if clock.first_mismatch.is_empty(): clock.first_mismatch={"tick":c.world.sim_tick-1,"reason":"visitor outlived its inpatient stay","remaining_ticks":remaining}
		return
	var medical: bool=false
	for session: Dictionary in c.world.facts.sessions.values():
		if session.visit_id==c.visit_id and session.kind in ["care","outpatient"] and c.world.facts.facilities[session.facility_id].get("room_id","")==c.world.facts.facilities[ward.bed_id].room_id: medical=true
	var patient_inside: bool=_inside(c,_visit(c).actor_id)
	var visitor_inside: bool=_inside(c,visitor.actor_id)
	var active: bool=not visitor.phase in ["outside","leaving"] or consumed==1 and remaining==0 and visitor.phase=="leaving"
	var eligible: bool=active and visitor.life_task.is_empty() and not visitor.yielding and not medical and ward.phase in ["waiting_surgery","recovery"] and patient_inside and visitor_inside and not _visit(c).phase in ["leaving","departed","ward_referral"]
	var sample: Dictionary={"tick":c.world.sim_tick-1,"ward_phase":ward.phase,"visitor_phase":visitor.phase,"remaining_ticks":remaining,"consumed_ticks":consumed,"patient_inside":patient_inside,"visitor_inside":visitor_inside,"medical":medical,"yielding":visitor.yielding,"has_move":c.world.facts.moves.has(visitor.actor_id)}
	if consumed>0 and clock.first_credit.is_empty(): clock.first_credit=sample.duplicate(true)
	if not consumed in [0,1] or consumed==1 and not eligible or eligible and consumed!=1:
		if clock.first_mismatch.is_empty(): clock.first_mismatch=sample.duplicate(true)
	clock.no_outside_credit=clock.no_outside_credit and consumed in [0,1] and (consumed==0 or eligible)
	clock.each_eligible_tick_counted=clock.each_eligible_tick_counted and (not eligible or consumed==1)
	clock.eligible_ticks+=1 if eligible else 0
	clock.consumed_ticks+=consumed
	clock.last_remaining=remaining

func _interrupted_visit(t) -> Dictionary:
	var name: String="family_visit_paused_after_actual_care"
	if _named_sources.has(name): return _read_source(t,name)
	var started: int=Time.get_ticks_msec()
	var c: Dictionary=await _with_family(t,true,true)
	if c.is_empty(): return {}
	if not await _until(t,c,func()->bool:return int(_role(c,"ward_visit").get("remaining_ticks",0))==180,300): return _failed_source(name,c,"visitor did not reach 120 effective ticks",started)
	_exact_input(c.world,"treatment",0)
	if not _open_surgery(c): return _failed_source(name,c,"operating room could not reopen",started)
	var trace: Dictionary={"both_left":false,"no_outside_credit":true,"care_outside":false,"remaining":180,"at_least_twenty_seconds":false,"effective_return_ticks":0}
	var outside_ticks: int=0
	var previous_remaining: int=180
	for index: int in 3400:
		var visitor: Dictionary=_role(c,"ward_visit")
		var companion: Dictionary=_role(c,"companion")
		if visitor.is_empty() or companion.is_empty(): return _failed_source(name,c,"a family role disappeared before the medical interruption completed",started)
		var consumed: int=previous_remaining-int(visitor.remaining_ticks)
		if consumed>0:
			trace.no_outside_credit=trace.no_outside_credit and consumed==1 and _inside(c,visitor.actor_id) and _inside(c,_visit(c).actor_id) and _stay(c).phase=="recovery" and _session(c,"care").is_empty()
			trace.effective_return_ticks+=consumed
		previous_remaining=int(visitor.remaining_ticks)
		var both_outside: bool=_outside(c,visitor.actor_id) and _outside(c,companion.actor_id)
		if both_outside:
			trace.both_left=true
			outside_ticks+=1
			if not _session(c,"care").is_empty(): trace.care_outside=true
		if trace.care_outside and _stay(c).care_completed:
			trace.at_least_twenty_seconds=outside_ticks>=200
			trace.remaining=180-int(trace.effective_return_ticks)
			c.family_pause_trace=trace
			_remember_source(name,c,Time.get_ticks_msec()-started,{"family_pause_trace":trace})
			_case_sources.append(_named_sources[name].observation.duplicate(true))
			return c
		_tick(c)
		if index%100==99: await t.process_frame
	return _failed_source(name,c,"actual treatment, safe return and ward care did not reach the paused visit boundary",started)

func _case_11(t) -> void:
	var c: Dictionary=await _interrupted_visit(t)
	var checks: Dictionary={"actual_treatment_interruption":not c.is_empty()}
	if not c.is_empty():
		checks.both_actual_bodies_left=c.family_pause_trace.both_left and c.family_pause_trace.care_outside
		var remaining: int=int(c.family_pause_trace.remaining)
		checks.paused_exact_remaining=c.family_pause_trace.no_outside_credit and c.family_pause_trace.at_least_twenty_seconds and int(_role(c,"ward_visit").remaining_ticks)==remaining
		var resumed: bool=await _until(t,c,func()->bool:return int(_role(c,"ward_visit").get("remaining_ticks",remaining))<remaining,500)
		checks.return_resumes=resumed and int(_role(c,"ward_visit").remaining_ticks)==remaining-1
	var inbound: Dictionary=await _unstarted_care_visit(t)
	checks.unstarted_care_input=not inbound.is_empty()
	if not inbound.is_empty():
		var actor_id: String=str(_role(inbound,"ward_visit").actor_id)
		var original: Dictionary=inbound.world.freeze()
		var waiting: Dictionary=_copy_facts(original,inbound.visit_id)
		var initial: int=int(_role(waiting,"ward_visit").remaining_ticks)
		checks.unstarted_care_allows_entry=await _until(t,waiting,func()->bool:return _inside(waiting,actor_id) and int(_role(waiting,"ward_visit").remaining_ticks)<initial,900)
		checks.not_a_medical_session=_session(waiting,"care").is_empty() and not _stay(waiting).care_completed
		var requested: Dictionary=_copy_facts(original,inbound.visit_id)
		var before: Dictionary=requested.world.facts.moves[actor_id].duplicate(true)
		# This tests the existing clinical-to-family request interface. Its
		# caller owns care eligibility; this receiver never starts a Session.
		requested.sim.clinic.visitors.yield_for_care(requested.world,requested.visit_id)
		var redirected: Dictionary=requested.world.facts.moves.get(actor_id,{})
		checks.inbound_ground_retargeted=not redirected.is_empty() and (redirected.target_cell!=before.target_cell or redirected.target_floor!=before.target_floor) and _role(requested,"ward_visit").destination.kind=="ward_outside"
		var renewed: bool=true
		for index: int in 20:
			requested.sim.clinic.visitors.yield_for_care(requested.world,requested.visit_id)
			_tick(requested)
			renewed=renewed and _role(requested,"ward_visit").yielding and _role(requested,"ward_visit").get("destination",{}).get("kind","")=="ward_outside"
		checks.request_renews_until_caller_stops=renewed
		await _steps(t,requested,5)
		checks.expired_request_does_not_exclude_forever=not _role(requested,"ward_visit").yielding
	_report(t,"FAMILY-11",checks)

func _unstarted_care_visit(t) -> Dictionary:
	var name: String="visitor_inbound_before_unstarted_ward_care"
	if _named_sources.has(name): return _read_source(t,name)
	var started: int=Time.get_ticks_msec()
	var source: Dictionary=await _source(t)
	if source.is_empty(): return {}
	var c: Dictionary=_copy_facts(source.facts,source.visit_id)
	_exact_input(c.world,"arrival",8000)
	_tick(c)
	_command(c,"clinical_visit_consent",{"visit_id":c.visit_id,"allow":false})
	_exact_input(c.world,"arrival",2999)
	_exact_input(c.world,"treatment",0)
	var waking: bool=await _until(t,c,func()->bool:return not _session(c,"wake").is_empty() and int(_session(c,"wake").remaining_ticks)<=10,3000)
	if not waking: return _failed_source(name,c,"actual surgery did not reach the final wake boundary",started)
	# A lawful critical input interrupts the assigned nurse's ability to
	# start care. The committed operation, wake and actual return still run.
	var facts: Dictionary=c.world.freeze()
	facts.staff.clin_cover.energy=0.0
	c=_copy_facts(facts,c.visit_id)
	var returned: Dictionary=await _returned_from_surgery(t,c,"ward_visit")
	if not returned.returned or not _session(c,"care").is_empty(): return _failed_source(name,c,"patient did not return before the unstarted care boundary",started)
	_command(c,"clinical_visit_consent",{"visit_id":c.visit_id,"allow":true})
	var inbound: bool=await _until(t,c,func()->bool:
		var visitor: Dictionary=_role(c,"ward_visit")
		return not visitor.is_empty() and visitor.get("destination",{}).get("kind","")=="ward" and c.world.facts.moves.has(visitor.actor_id) and not _inside(c,visitor.actor_id),900)
	if not inbound: return _failed_source(name,c,"daily visitor did not begin an actual inbound ward journey",started)
	_remember_source(name,c,Time.get_ticks_msec()-started)
	_case_sources.append(_named_sources[name].observation.duplicate(true))
	return c

func _case_12(t) -> void:
	var c: Dictionary=await _with_family(t,false,true)
	var checks: Dictionary={"actual_visitor_input":not c.is_empty()}
	if not c.is_empty():
		var actor_id: String=str(_role(c,"ward_visit").actor_id)
		var actor_before: Dictionary=c.world.facts.actors[actor_id].duplicate(true)
		checks.in_hospital_cleanup_rejected=not c.sim.space.forget_actor(c.world,actor_id) and c.world.facts.actors[actor_id]==actor_before and c.sim.space._actor_index._records.has(actor_id)
		var previous: int=int(_role(c,"ward_visit").remaining_ticks)
		var effective_ticks: int=300-previous
		var exact_clock: bool=true
		var no_life: bool=true
		var reached_zero: bool=false
		for index: int in 1300:
			_tick(c)
			var visitor: Dictionary=_role(c,"ward_visit")
			if visitor.is_empty(): break
			var remaining: int=int(visitor.remaining_ticks)
			if remaining<previous:
				exact_clock=exact_clock and remaining==previous-1 and _inside(c,actor_id)
				effective_ticks+=previous-remaining
			previous=remaining
			reached_zero=reached_zero or remaining==0
			no_life=no_life and visitor.life_task.is_empty() and visitor.purpose=="ward_visit"
			if index%100==99: await t.process_frame
		checks.exact_300_ticks=exact_clock and reached_zero and effective_ticks==300
		checks.no_conversion_or_life=no_life and _role(c,"companion").is_empty()
		checks.actual_exit=_role(c,"ward_visit").is_empty() and not c.world.facts.actors.has(actor_id) and not c.world.facts.moves.has(actor_id)
		checks.spatial_identity_released=_spatially_forgotten(c,actor_id)
	_report(t,"FAMILY-12",checks)

func _life_due(c: Dictionary, purpose: String, upstairs_water: bool = false) -> Dictionary:
	var facts: Dictionary=c.world.freeze()
	var id: String=str(_role(c,"companion").id)
	facts.visitors.stays[id].next_need_tick=int(facts.sim_tick)
	facts.visitors.stays[id].next_purpose=purpose
	if upstairs_water: facts.facilities.water.floor_id=2
	return _copy_facts(facts,c.visit_id)

func _case_13(t) -> void:
	var checks: Dictionary={}
	for purpose: String in ["water","toilet"]:
		var c: Dictionary=await _with_family(t,true,false)
		if c.is_empty(): checks[purpose+"_input"]=false; continue
		c=_life_due(c,purpose)
		var using: bool=await _until(t,c,func()->bool:return _role(c,"companion").life_task.get("phase","")=="using",800)
		checks[purpose+"_actual_use"]=using
		if not using: continue
		var actor_id: String=str(_role(c,"companion").actor_id)
		_exact_input(c.world,"treatment",0)
		_open_surgery(c)
		var patient_moved_during_use: bool=false
		var completed: bool=false
		var visited_ward_first: bool=false
		var wrong_direct_or: bool=false
		var reached_or_after_ward: bool=false
		for index: int in 2500:
			var relative: Dictionary=_role(c,"companion")
			var task: Dictionary=relative.life_task
			if task.get("phase","")=="using" and _stay(c).phase=="to_surgery" and c.world.facts.moves.has(_visit(c).actor_id): patient_moved_during_use=true
			if task.has("completed_tick"): completed=true
			if completed and task.is_empty() and _inside(c,actor_id): visited_ward_first=true
			if completed and _or_outside(c,actor_id):
				if not visited_ward_first: wrong_direct_or=true
				else: reached_or_after_ward=true; break
			_tick(c)
			if index%100==99: await t.process_frame
		checks[purpose+"_patient_did_not_wait"]=patient_moved_during_use
		checks[purpose+"_ward_before_or"]=completed and visited_ward_first and reached_or_after_ward and not wrong_direct_or
	_report(t,"FAMILY-13",checks)

func _case_14(t) -> void:
	var c: Dictionary=await _with_family(t,true,false)
	var checks: Dictionary={"actual_companion_input":not c.is_empty()}
	if not c.is_empty():
		_exact_input(c.world,"treatment",0)
		_open_surgery(c)
		var wake_boundary: bool=await _until(t,c,func()->bool:return not _session(c,"wake").is_empty() and int(_session(c,"wake").remaining_ticks)<=10,2800)
		checks.actual_wake_boundary=wake_boundary
		if wake_boundary:
			c=_life_due(c,"water")
			var actor_id: String=str(_role(c,"companion").actor_id)
			var completed: bool=false
			var back_to_current_patient: bool=false
			for index: int in 1400:
				var task: Dictionary=_role(c,"companion").life_task
				completed=completed or task.has("completed_tick")
				if completed and task.is_empty() and _inside(c,actor_id) and _inside(c,_visit(c).actor_id): back_to_current_patient=true; break
				_tick(c)
				if index%100==99: await t.process_frame
			checks.returned_to_current_facts=back_to_current_patient
			if back_to_current_patient:
				await _steps(t,c,30)
				checks.no_expired_or_chase=_role(c,"companion").get("destination",{}).get("kind","")!="surgery_outside" and _inside(c,actor_id)
	_report(t,"FAMILY-14",checks)

func _case_15(t) -> void:
	var checks: Dictionary={}
	for in_use: bool in [false,true]:
		var c: Dictionary=await _with_family(t,true,true)
		if c.is_empty(): checks["input_%s"%in_use]=false; continue
		var companion_id: String=str(_role(c,"companion").actor_id)
		var visitor_id: String=str(_role(c,"ward_visit").actor_id)
		if in_use:
			c=_life_due(c,"water")
			if not await _until(t,c,func()->bool:return _role(c,"companion").life_task.get("phase","")=="using",800): checks.water_boundary=false; continue
		var required_ticks: int=int(_role(c,"companion").life_task.get("remaining_ticks",0))
		var referred: CommandResult=_command(c,"clinical_ward_refer",{"visit_id":c.visit_id})
		_tick(c)
		checks["terminal_immediate_%s"%in_use]=referred.accepted and _visit(c).phase in ["ward_referral","leaving","departed"] and c.world.facts.visitors.requests.is_empty()
		if in_use:
			checks.use_not_erased=c.world.facts.actors.has(companion_id) and not _role(c,"companion").life_task.is_empty() and int(_role(c,"companion").life_task.remaining_ticks)==maxi(0,required_ticks-1)
		var finished: bool=await _until(t,c,func()->bool:return _visit(c).phase=="departed" and c.world.facts.visitors.stays.is_empty(),1600)
		checks["real_safe_exits_%s"%in_use]=finished and not c.world.facts.actors.has(companion_id) and not c.world.facts.actors.has(visitor_id) and not c.world.facts.moves.has(companion_id) and not c.world.facts.moves.has(visitor_id)
		await _steps(t,c,55)
		checks["no_orphans_%s"%in_use]=c.world.facts.visitors.requests.is_empty() and c.world.facts.visitors.stays.is_empty()
	var pending_source: Dictionary=await _source(t)
	checks.pending_input=not pending_source.is_empty()
	if not pending_source.is_empty():
		var facts: Dictionary=pending_source.facts.duplicate(true)
		facts.actors.clin_round.location={"kind":"floor","floor_id":1,"cell":facts.entry.cell.duplicate(),"height_m":0.0}
		facts.moves.erase("clin_round")
		facts.staff.clin_round.erase("clinical_release")
		var pending: Dictionary=_copy_facts(facts,pending_source.visit_id)
		_exact_input(pending.world,"arrival",7999)
		_tick(pending)
		_command(pending,"build_room_open",{"target_id":"clin_or","open_intent":false})
		_exact_input(pending.world,"arrival",2999)
		pending.world.facts.visitors.next_scan_tick=pending.world.sim_tick
		_tick(pending)
		checks.only_light_requests=pending.world.facts.visitors.requests.size()==2 and pending.world.facts.visitors.stays.is_empty()
		var referred: CommandResult=_command(pending,"clinical_ward_refer",{"visit_id":pending.visit_id})
		_tick(pending)
		checks.pending_cancelled=referred.accepted and pending.world.facts.visitors.requests.is_empty() and pending.world.facts.visitors.stays.is_empty()
	# A separate initial hospital has a second-floor water facility. The
	# companion must really board its lift before the patient is discharged.
	var two_floor: Dictionary=await _surgery_queue(t,false,true,2)
	if two_floor.get("before_admission",{}).is_empty(): checks.lift_input=false
	else:
		var c: Dictionary=_copy_facts(two_floor.before_admission.facts,two_floor.visit_id)
		_exact_input(c.world,"arrival",7999)
		_tick(c)
		_command(c,"build_room_open",{"target_id":"clin_or","open_intent":false})
		_exact_input(c.world,"arrival",3000)
		var entered: bool=await _until(t,c,func()->bool:return not _role(c,"companion").is_empty() and _inside(c,_role(c,"companion").actor_id),1200)
		checks.lift_family_entry=entered
		if entered:
			c=_life_due(c,"water",true)
			var companion_id: String=str(_role(c,"companion").actor_id)
			var boarded: bool=await _until(t,c,func()->bool:return c.world.facts.actors[companion_id].location.kind=="transit" and c.world.facts.actors[companion_id].location.connector_id=="clin_lift",800)
			checks.actual_lift=boarded
			if boarded:
				var returning: Dictionary=_copy_facts(c.world.freeze(),c.visit_id)
				var journey: Dictionary=c.world.facts.moves[companion_id].duplicate(true)
				var transit: Dictionary=c.world.facts.actors[companion_id].location.duplicate(true)
				checks.transit_cleanup_rejected=not c.sim.space.forget_actor(c.world,companion_id) and c.world.facts.moves.get(companion_id,{})==journey and c.world.facts.actors[companion_id].location==transit
				c.sim.clinic.visitors.yield_for_care(c.world,c.visit_id)
				checks.medical_request_keeps_transit=c.world.facts.moves.get(companion_id,{})==journey and c.world.facts.actors[companion_id].location==transit
				var referred: CommandResult=_command(c,"clinical_ward_refer",{"visit_id":c.visit_id})
				_tick(c)
				checks.no_transit_disappearance=referred.accepted and c.world.facts.actors.has(companion_id)
				checks.lift_safe_exit=await _until(t,c,func()->bool:return _visit(c).phase=="departed" and not c.world.facts.actors.has(companion_id) and c.world.facts.visitors.stays.is_empty(),1800)
				checks.lift_departure_spatially_released=_spatially_forgotten(c,companion_id)
				var inbound_lift: bool=await _until(t,returning,func()->bool:
					var relative: Dictionary=_role(returning,"companion")
					return relative.life_task.is_empty() and relative.return_ward_first and returning.world.facts.actors[companion_id].location.kind=="transit" and returning.world.facts.moves.get(companion_id,{}).get("visitor_stay_id","")==relative.id,1500)
				checks.actual_inbound_family_lift=inbound_lift
				if inbound_lift:
					var incoming: Dictionary=returning.world.facts.moves[companion_id].duplicate(true)
					var cabin: Dictionary=returning.world.facts.actors[companion_id].location.duplicate(true)
					returning.sim.clinic.visitors.yield_for_care(returning.world,returning.visit_id)
					checks.inbound_lift_not_retargeted=returning.world.facts.moves.get(companion_id,{})==incoming and returning.world.facts.actors[companion_id].location==cabin
	_report(t,"FAMILY-15",checks)

func _case_16(t) -> void:
	var c: Dictionary=await _interrupted_visit(t)
	var checks: Dictionary={"actual_pause_input":not c.is_empty()}
	if not c.is_empty():
		var ward_id: String=str(_stay(c).id)
		var actor_id: String=str(_role(c,"companion").actor_id)
		var remaining: int=int(_role(c,"ward_visit").remaining_ticks)
		var random_after: Dictionary=c.world.facts.rng.arrival.duplicate(true)
		var saved: Dictionary=_roundtrip(c)
		checks.paused_roundtrip=saved.get("ok",false) and _role(c,"ward_visit").remaining_ticks==remaining and _role(c,"companion").actor_id==actor_id and c.world.facts.rng.arrival==random_after
		var invalid: Dictionary=c.world.freeze()
		invalid.visitors.stays[_role(c,"ward_visit").id].yield_requested_tick=int(invalid.sim_tick)+1
		checks.future_medical_request_rejected=not WorldState.new(invalid).validate(_content).is_empty()
		var other_bed: String=""
		for id: String in c.world.facility_ids("EQ05"):
			if id!=_stay(c).bed_id: other_bed=id; break
		var transferred: bool=false
		for index: int in 500:
			var result: CommandResult=_command(c,"clinical_transfer_bed",{"visit_id":c.visit_id,"bed_id":other_bed})
			if result.accepted: transferred=true; break
			_tick(c)
			if index%100==99: await t.process_frame
		checks.actual_transfer=transferred and await _until(t,c,func()->bool:return _stay(c).phase=="recovery" and _stay(c).bed_id==other_bed,1000)
		checks.same_stay_and_binding=_stay(c).id==ward_id and _stay(c).companion_actor_id==actor_id and c.world.facts.rng.arrival==random_after
		checks.transfer_roundtrip=_roundtrip(c).get("ok",false)
	# A failed first treatment returns and completes real recovery before a
	# second actual attempt. Neither the ward identity nor qualification rolls.
	var retry: Dictionary=await _with_family(t,true,false)
	checks.retry_input=not retry.is_empty()
	if not retry.is_empty():
		var original_stay: String=str(_stay(retry).id)
		var original_actor: String=str(_role(retry,"companion").actor_id)
		var random_after: Dictionary=retry.world.facts.rng.arrival.duplicate(true)
		_exact_input(retry.world,"treatment",9999)
		_open_surgery(retry)
		var first: bool=await _until(t,retry,func()->bool:return _visit(retry).attempt_ids.size()==1,1800)
		checks.first_failure_frozen=first and not retry.world.facts.attempts[_visit(retry).attempt_ids[0]].result
		if first:
			_exact_input(retry.world,"treatment",0)
			var second: bool=await _until(t,retry,func()->bool:return _visit(retry).attempt_ids.size()==2,6000)
			checks.retry_keeps_binding=second and _stay(retry).get("id","")==original_stay and _stay(retry).companion_actor_id==original_actor and retry.world.facts.rng.arrival==random_after
			checks.retry_roundtrip=_roundtrip(retry).get("ok",false)
	var night: Dictionary=await _with_family(t,true,false)
	checks.night_input=not night.is_empty()
	if not night.is_empty():
		night=_clock_boundary(night,11999,true)
		var actor_id: String=str(_role(night,"companion").actor_id)
		var outside: bool=await _until(t,night,func()->bool:return _role(night,"companion").get("phase","")=="outside",1000)
		var saved: Dictionary=_roundtrip(night)
		checks.overnight_binding_saved=outside and saved.get("ok",false) and _stay(night).companion_actor_id==actor_id and night.world.facts.actors[actor_id].location.kind=="outside"
	_report(t,"FAMILY-16",checks)

func _case_17(t) -> void:
	var source: Dictionary=await _source(t)
	var checks: Dictionary={"legal_admitted_input":not source.is_empty()}
	if not source.is_empty():
		# Entry is obstructed in the initial copied world, before any relative
		# participates. Its employee leaves only by the normal office journey.
		var facts: Dictionary=source.facts.duplicate(true)
		facts.actors.clin_round.location={"kind":"floor","floor_id":1,"cell":facts.entry.cell.duplicate(),"height_m":0.0}
		facts.moves.erase("clin_round")
		facts.staff.clin_round.erase("clinical_release")
		var c: Dictionary=_copy_facts(facts,source.visit_id)
		_exact_input(c.world,"arrival",7999)
		_tick(c)
		_command(c,"build_room_open",{"target_id":"clin_or","open_intent":false})
		_exact_input(c.world,"arrival",2999)
		c.world.facts.visitors.next_scan_tick=c.world.sim_tick
		_tick(c)
		checks.light_requests_no_fake_actors=c.world.facts.visitors.requests.size()==2 and c.world.facts.visitors.stays.is_empty()
		checks.patient_has_real_bed=_stay(c).has("admitted_tick") and _stay(c).phase=="waiting_surgery"
		_open_surgery(c)
		var progress: bool=await _until(t,c,func()->bool:return _stay(c).phase=="to_surgery" or not _visit(c).attempt_ids.is_empty(),300)
		checks.family_not_clinical_gate=progress
		var entered: bool=await _until(t,c,func()->bool:return not _role(c,"companion").is_empty(),800)
		checks.actual_entry_after_clearance=entered
		if entered:
			var actor: Dictionary=c.world.facts.actors[_role(c,"companion").actor_id]
			checks.original_real_body=actor.species_id==c.world.facts.actors[_visit(c).actor_id].species_id and c.sim.space.body(actor)==_content.definition("species",actor.species_id).body
	_report(t,"FAMILY-17",checks)

func _case_18(t) -> void:
	var c: Dictionary=await _with_family(t,true,true)
	var checks: Dictionary={"families_entered_with_intake_closed":not c.is_empty()}
	if not c.is_empty():
		var actor_id: String=str(_role(c,"companion").actor_id)
		var closed: CommandResult=_command(c,"set_intake_open",{"open":false})
		var anger: float=float(_visit(c).anger)
		var ledger: Dictionary=c.world.facts.ledger.duplicate(true)
		var refused: CommandResult=_command(c,"clinical_visit_consent",{"visit_id":c.visit_id,"allow":false})
		checks.no_consent_penalty=closed.accepted and refused.accepted and _visit(c).anger==anger and c.world.facts.ledger==ledger
		checks.visitor_leaves=await _until(t,c,func()->bool:return _role(c,"ward_visit").is_empty(),1000)
		checks.companion_unaffected=_role(c,"companion").get("actor_id","")==actor_id and _stay(c).companion_actor_id==actor_id and _stay(c).companion_qualified
		checks.no_extra_patient=c.world.facts.visits.size()==1
	_report(t,"FAMILY-18",checks)

func _case_19(t) -> void:
	var c: Dictionary=await _with_family(t,true,true)
	var checks: Dictionary={"two_role_input":not c.is_empty()}
	if not c.is_empty():
		var actor_id: String=str(_role(c,"companion").actor_id)
		var income: int=_income(c)
		var bounded: bool=true
		var same_identity: bool=true
		var spatially_released: bool=true
		for day: int in 3:
			if not _role(c,"ward_visit").is_empty():
				var departed_id: String=str(_role(c,"ward_visit").actor_id)
				bounded=bounded and await _until(t,c,func()->bool:return _role(c,"ward_visit").is_empty(),1100)
				spatially_released=spatially_released and not c.world.facts.actors.has(departed_id) and _spatially_forgotten(c,departed_id)
			c=_clock_boundary(c,day*WorldState.TICKS_PER_DAY+11999,true)
			var outside: bool=await _until(t,c,func()->bool:return _role(c,"companion").get("phase","")=="outside",1000)
			c=_clock_boundary(c,(day+1)*WorldState.TICKS_PER_DAY-1)
			_exact_input(c.world,"arrival",2999 if day%2==0 else 3000)
			var returned: bool=await _until(t,c,func()->bool:return _role(c,"companion").get("phase","")!="outside" and _inside(c,actor_id),1200)
			same_identity=same_identity and outside and returned and _stay(c).companion_actor_id==actor_id
			var relatives: int=0
			for actor: Dictionary in c.world.facts.actors.values():
				if actor.has("relative_of"): relatives+=1
			bounded=bounded and relatives<=2 and c.world.facts.visitors.stays.size()<=2 and c.world.facts.visitors.requests.size()<=2 and not _stay(c).has("visitor_windows")
		checks.same_fixed_companion=same_identity
		checks.bounded_daily_identities=bounded
		checks.no_retired_spatial_cache=spatially_released
		checks.no_fees_or_recovery_bonus=_income(c)==income and _income(c,"ward")==0 and _stay(c).remaining_ticks==0 and not _stay(c).care_completed and _visit(c).attempt_ids.is_empty()
		checks.no_new_patient_opportunities=c.world.facts.visits.size()==1
		var referred: CommandResult=_command(c,"clinical_ward_refer",{"visit_id":c.visit_id})
		checks.terminal_cleanup=referred.accepted and await _until(t,c,func()->bool:return _visit(c).phase=="departed" and c.world.facts.visitors.stays.is_empty() and c.world.facts.visitors.requests.is_empty(),1600)
		checks.fixed_companion_cache_released=_spatially_forgotten(c,actor_id)
	_report(t,"FAMILY-19",checks)
