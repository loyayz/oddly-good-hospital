extends "res://tests/acceptance/staff_fixtures.gd"

func run_cases(database: HospitalContent, selected: Array = []) -> Dictionary:
	_content = database
	var runs: Dictionary = {"GUIDE-REAL-ARRIVAL":_single.bind(false),"GUIDE-JSON":_single.bind(true),"GUIDE-CROSS-FLOOR":_cross_floor,"GUIDE-SAME-FLOOR-NEW-STAGE":_same_floor_new_request,"GUIDE-NURSE-RECOVERY":_missing_nurse,"GUIDE-STAFFED-QUEUE-PAUSE-RECOVERY":_staffed_queue_pause,"GUIDE-EXIT-BYPASS":_departure,"GUIDE-ARRIVAL-ORDER":_simultaneous,"GUIDE-DESK-BUILD-RECOVERY":_missing_desk,"GUIDE-NURSE-SAFE-HANDOFF":_nurse_handoff,"GUIDE-LOCAL-SEATS":_local_seats,"GUIDE-DESK-REMOVAL":_desk_removal,"GUIDE-MOVE-OWNERSHIP":_move_ownership,"GUIDE-SAVE-GUARDS":_save_guards,"GUIDE-DYNAMIC-ADMISSION-RETRY":_dynamic_admission_retry}
	var cases: Array = []
	var passed: bool = true
	for id: String in (runs.keys() if selected.is_empty() else selected):
		if not runs.has(id): return {"ok":false,"error":"unknown selector "+id}
		var row: Dictionary = runs[id].call()
		cases.append(row)
		passed = passed and bool(row.ok)
	return {"ok":passed,"cases":cases}

func _guide_bind(world: WorldState) -> Dictionary:
	var x: Dictionary = _bind(world)
	x.g = HospitalFloorGuidance.new(_content,x.space)
	x.g.clinic = x.c; x.g.waiting = x.l
	x.c.floor_guidance = x.g; x.c.waiting_life = x.l; x.c.departments = x.p
	x.l.floor_guidance = x.g; x.p.clinic = x.c
	x.g.ensure(world)
	return x

func _base(doctor: bool = false, upper: bool = false) -> Dictionary:
	var old: Dictionary = _fixture({"guide_nurse":"nurse","upper_nurse":"nurse"} if upper else {"guide_nurse":"nurse"})
	var world: WorldState = old.world
	_dispose(old)
	var x: Dictionary = _guide_bind(world)
	HospitalFactory._add_room(world,{"id":"clinic","type":"gp","anchor":[34,66],"size":[10,12],"door":{"definition_id":"DR04","offset":3}},_content)
	_facility(x,"diagnosis","FUR02",[39,69],"clinic")
	_facility(x,"guide","SE01",[47,83])
	world.facts.departments.units.general.room_ids = ["clinic"]
	if doctor:
		HospitalFactory._add_staff(world,"doctor","医生","doctor",[43,87],_content)
		x.d.ensure(world);x.s.ensure(world);x.w.ensure(world);x.r.ensure(world);x.f.ensure(world)
		world.facts.staff.doctor.base_prepared = true
	if upper:
		var plots: Array = HospitalSpace.floor_plots(world,1).duplicate(true)
		world.facts.floors.completed_top_floor = {}
		for plot: Array in plots: world.facts.floors.completed_top_floor[HospitalSpace.plot_key(plot)] = 2
		world.facts.floors.height_intervals = [{"first":1,"last":2,"height_m":float(_content.balance.floors.clear_height_m)}]
		world.facts.floors.overrides["2"] = {"plots":plots,"blocked":world.facts.floors.overrides["1"].blocked.duplicate(true),"doors":world.facts.floors.overrides["1"].doors.duplicate(true),"paths":[]}
		world.facts.floors.overrides["1"].blocked = [];world.facts.floors.overrides["1"].doors = []
		world.facts.rooms.clinic.floor_id = 2
		world.facts.facilities.diagnosis.floor_id = 2
		_facility(x,"upper_guide","SE01",[47,83]);world.facts.facilities.upper_guide.floor_id = 2
		world.facts.actors.upper_nurse.location = {"kind":"floor","floor_id":2,"cell":[52,90],"height_m":0.0}
		world.facts.connectors["lift"] = {"id":"lift","definition_id":"VC02","stops":[1,2],"cell":[58,84],"footprint":[4,4],"rotation":0,"anchor":[59,88],"repair_cell":[57,85],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0,"ticket_next":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},"paid_cost":3200,"used":false}
		x.m.ensure(world)
	world.touch()
	return x

func _step(x: Dictionary, clinical_work: bool = false) -> void:
	x.g.dispatch(x.world)
	x.l.dispatch(x.world)
	x.c.dispatch(x.world)
	x.space.advance(x.world)
	if clinical_work: x.c.advance(x.world)
	x.g.advance(x.world)
	x.l.advance(x.world)
	x.world.facts.sim_tick += 1
	x.world.touch(false)

func _restore_json(x: Dictionary) -> Dictionary:
	var previous: Dictionary = x.world.freeze()
	var id: int = x.world.get_instance_id()
	var encoder: HospitalJsonStream = HospitalJsonStream.new()
	var path: String = "user://floor-guidance.json"
	if not encoder.encode(path,previous,func(_bytes:int)->bool:return true): return {"restore_error":"encode failed"}
	var decoded: Dictionary = HospitalJsonStream.new().decode(path,encoder.bytes,encoder.digest,func(_bytes:int)->bool:return true)
	if not decoded.get("ok",false): return {"restore_error":"decode failed: "+str(decoded)}
	var restored: Dictionary = _guide_bind(WorldState.new(decoded.value))
	restored.restore_ok = restored.world.get_instance_id()!=id and restored.world.freeze()==previous
	_dispose(x)
	return restored

func _single(json_restore: bool) -> Dictionary:
	var x: Dictionary = _base()
	var visit: Dictionary = _visit(x,"single",[40,88])
	var ticket: String = visit.ticket_id
	var no_clinical_hold: bool = true
	var work_ticks: int = 0
	var actual_work: bool = true
	var restored: bool = not json_restore
	var started: int = -1
	var previous_location: Dictionary = x.world.facts.actors[visit.actor_id].location.duplicate(true)
	var moved: bool = false
	for tick: int in 700:
		_step(x)
		var state: Dictionary = x.g.state(x.world,visit.id)
		moved = moved or previous_location!=x.world.facts.actors[visit.actor_id].location
		if state.get("phase","")=="working":
			work_ticks += 1
			var layout: Dictionary = x.space.facility_layout(x.world,"guide")
			actual_work = actual_work and x.space.at(x.world,visit.actor_id,1,layout.patient_cell) and x.space.at(x.world,"guide_nurse",1,layout.operator_cells[0])
			started = int(state.started_tick)
			if json_restore and not restored and int(state.remaining_ticks)<40:
				x = _restore_json(x)
				if x.has("restore_error"): return {"case":"GUIDE-JSON","ok":false,"error":x.restore_error}
				visit = x.world.facts.visits.single
				restored = bool(x.restore_ok)
		if state.get("phase","")!="ready":
			no_clinical_hold = no_clinical_hold and not x.world.facts.adaptations.has("diagnosis") and x.world.facts.sessions.is_empty() and int(state.get("arrived_seq",-1))<0
		else: break
	var state: Dictionary = x.g.state(x.world,visit.id)
	var complete: bool = state.get("phase","")=="ready" and state.receipts.size()==1 and int(state.receipts[0].completed_tick)-started+1==60
	var result: Dictionary = {"case":"GUIDE-JSON" if json_restore else "GUIDE-REAL-ARRIVAL","ok":complete and moved and actual_work and restored and no_clinical_hold and visit.ticket_id==ticket and x.world.validate(_content).is_empty(),"actual_guidance_complete":complete,"new_world_json_restored":restored,"patient_walked":moved,"real_patient_nurse_work":actual_work,"no_remote_destination_claim":no_clinical_hold,"state":state.duplicate(true),"validation":x.world.validate(_content)}
	_dispose(x);return result

func _cross_floor() -> Dictionary:
	var x: Dictionary = _base(false,true)
	var visit: Dictionary = _visit(x,"upper",[40,88])
	var ride: bool = false
	var no_early: bool = true
	var restored: bool = false
	var prevalidation: String = x.world.validate(_content)
	for tick: int in 1400:
		_step(x)
		var actor: Dictionary = x.world.facts.actors[visit.actor_id]
		var state: Dictionary = x.g.state(x.world,visit.id)
		if actor.location.kind=="transit":
			ride = true
			no_early = no_early and state.receipts.size()==1 and int(state.arrived_seq)<0
			if not restored:
				x = _restore_json(x)
				if x.has("restore_error"): return {"case":"GUIDE-CROSS-FLOOR","ok":false,"error":x.restore_error}
				visit = x.world.facts.visits.upper
				restored = bool(x.restore_ok)
		if state.get("phase","")=="ready": break
	var state: Dictionary = x.g.state(x.world,visit.id)
	var floors: Array = []
	for receipt: Dictionary in state.receipts: floors.append(receipt.floor_id)
	var result: Dictionary = {"case":"GUIDE-CROSS-FLOOR","ok":ride and restored and no_early and floors==[1,2] and state.phase=="ready" and int(x.world.facts.actors[visit.actor_id].location.floor_id)==2 and prevalidation.is_empty() and x.world.validate(_content).is_empty(),"actual_ride":ride,"new_world_in_transit":restored,"no_landing_before_alight":no_early,"guidance_floors":floors,"state":state.duplicate(true),"prevalidation":prevalidation,"validation":x.world.validate(_content),"reason":visit.waiting_reason}
	_dispose(x);return result

func _same_floor_new_request() -> Dictionary:
	var x: Dictionary = _base(true)
	var visit: Dictionary = _visit(x,"stages",[40,88])
	var first_ticket: String = visit.ticket_id
	var clinical_ticks: int = 0
	var continuous: bool = true
	var completed: bool = false
	for tick: int in 1600:
		_step(x,true)
		var state: Dictionary = x.g.state(x.world,visit.id)
		if visit.phase=="gp":
			clinical_ticks += 1
			continuous = continuous and state.receipts.size()==1 and state.phase=="ready"
		if visit.evidence_by_source.has("gp"): completed = true
		if completed and state.receipts.size()>=2: break
	var state: Dictionary = x.g.state(x.world,visit.id)
	var different: bool = state.receipts.size()==2 and state.receipts[0].request_key!=state.receipts[1].request_key
	var result: Dictionary = {"case":"GUIDE-SAME-FLOOR-NEW-STAGE","ok":completed and clinical_ticks>0 and continuous and different and visit.ticket_id!=first_ticket and x.world.validate(_content).is_empty(),"actual_gp_work_ticks":clinical_ticks,"gp_completed":completed,"continuous_work_not_interrupted":continuous,"new_request_reguided":different,"state":state.duplicate(true),"phase":visit.phase,"reason":visit.waiting_reason,"validation":x.world.validate(_content)}
	_dispose(x);return result

# Establish an occupied, genuinely staffed desk, admit the requested patient,
# then stop the nurse's shift. No queue number or completed journey is injected.
func _admit_then_pause(x: Dictionary, visit: Dictionary, additional: Array = []) -> Dictionary:
	# Input placement, before any journey: later patients start in the open
	# right-side aisle beside their expected successive slots, not in a slot.
	# They still walk to the actual current tail while the leader receives its
	# unchanged 60-tick service; no queue number or service progress is injected.
	var later: Array=[visit]
	later.append_array(additional)
	var initial_positions: Dictionary={}
	for index: int in later.size():
		var patient: Dictionary=later[index]
		var cell: Array=[50,85+index]
		_position(x,patient.actor_id,cell)
		initial_positions[patient.id]=cell.duplicate()
	var initial_nonoverlap: bool=true
	for i: int in later.size():
		for j: int in range(i+1,later.size()):
			initial_nonoverlap=initial_nonoverlap and not x.space.body_rectangle(x.world.facts.actors[later[i].actor_id]).intersects(x.space.body_rectangle(x.world.facts.actors[later[j].actor_id]),false)
	var first: Dictionary = _visit(x,"queue_gate",[48,85])
	var nurse_start: Dictionary = x.world.facts.actors.guide_nurse.location.duplicate(true)
	for tick: int in 600:
		x.g.dispatch(x.world)
		x.g.prepare(x.world,first,x.world.facts.tickets[first.ticket_id])
		x.space.advance(x.world)
		x.g.advance(x.world)
		x.world.facts.sim_tick += 1
		x.world.touch(false)
		if x.g.state(x.world,first.id).get("phase","")=="working": break
	var staffed: bool = x.g.state(x.world,first.id).get("phase","")=="working" and x.space.at(x.world,"guide_nurse",1,x.space.facility_layout(x.world,"guide").operator_cells[0])
	for tick: int in 500:
		_step(x)
		var row: Dictionary = x.g.state(x.world,visit.id)
		var all_queued: bool = _actual_queue_admission(x,visit,row)
		for extra: Dictionary in additional:
			var other: Dictionary = x.g.state(x.world,extra.id)
			all_queued = all_queued and _actual_queue_admission(x,extra,other)
		if all_queued: break
	var admitted: Dictionary = x.g.state(x.world,visit.id)
	var real_queue: bool = _actual_queue_admission(x,visit,admitted)
	var all_later_walked: bool=true
	for patient: Dictionary in later:
		all_later_walked=all_later_walked and not x.space.at(x.world,patient.actor_id,1,initial_positions[patient.id])
	var number: int = int(admitted.get("queue_seq",-1))
	x.world.facts.staff.guide_nurse.on_shift = false
	for tick: int in 500:
		_step(x)
		if not x.world.facts.adaptations.has("guide") and str(x.world.facts.staff.guide_nurse.get("active_job_id","")).is_empty() and not x.world.facts.moves.has("guide_nurse"): break
	return {"ok":staffed and real_queue and initial_nonoverlap and all_later_walked and int(x.g.state(x.world,visit.id).get("queue_seq",-2))==number and x.g.state(x.world,visit.id).receipts.is_empty() and not x.world.facts.adaptations.has("guide"),"nurse_actually_staffed":staffed,"nurse_walked":nurse_start!=x.world.facts.actors.guide_nurse.location,"patient_really_queued":real_queue,"initial_positions":initial_positions,"initial_later_nonoverlap":initial_nonoverlap,"all_later_really_walked":all_later_walked,"number":number,"state":x.g.state(x.world,visit.id).duplicate(true)}

# The arrival is real even when the head immediately starts its counter
# approach in the same dispatch. Observe the facts production wrote; never
# manufacture a queue number, arrival, location or service completion.
func _actual_queue_admission(x: Dictionary, visit: Dictionary, row: Dictionary) -> bool:
	if int(row.get("queue_seq",-1))<0 or int(row.get("queue_arrived_tick",-1))<0 or int(row.queue_arrived_tick)>int(x.world.sim_tick):return false
	if row.get("queue_cell",[]).size()!=2 or row.get("queue_desk_id","")!=row.get("desk_id",""):return false
	if row.get("phase","")=="to_counter":return true
	return row.get("phase","")=="desk_queue" and x.space.at(x.world,visit.actor_id,int(row.guide_floor),row.queue_cell) and not x.world.facts.moves.has(visit.actor_id)

func _restaff_only(x: Dictionary) -> bool:
	x.world.facts.staff.guide_nurse.on_shift = true
	for tick: int in 600:
		x.g.dispatch(x.world);x.space.advance(x.world);x.g.advance(x.world)
		x.world.facts.sim_tick += 1;x.world.touch(false)
		if x.g._desk_usable(x.world,"guide"):return true
	return false

func _staffed_queue_pause() -> Dictionary:
	var x: Dictionary = _base()
	var visit: Dictionary = _visit(x,"pause_queue",[49,86])
	var admission: Dictionary = _admit_then_pause(x,visit)
	var number: int = int(x.g.state(x.world,visit.id).get("queue_seq",-1))
	var retained: bool = admission.ok
	for tick: int in 50:
		_step(x)
		retained = retained and int(x.g.state(x.world,visit.id).get("queue_seq",-2))==number and x.g.state(x.world,visit.id).receipts.is_empty()
	x.world.facts.staff.guide_nurse.on_shift = true
	for tick: int in 800:
		_step(x)
		if x.g.state(x.world,visit.id).get("phase","")=="ready":break
	var row: Dictionary = {"case":"GUIDE-STAFFED-QUEUE-PAUSE-RECOVERY","ok":retained and x.g.state(x.world,visit.id).get("phase","")=="ready" and x.g.state(x.world,visit.id).receipts.size()==1 and x.world.validate(_content).is_empty(),"admission":admission,"number_preserved_during_absence":retained,"final":x.g.state(x.world,visit.id).duplicate(true),"validation":x.world.validate(_content)}
	_dispose(x);return row

func _missing_nurse() -> Dictionary:
	var x: Dictionary = _base()
	x.world.facts.staff.guide_nurse.on_shift = false
	var visit: Dictionary = _visit(x,"missing",[40,88])
	var ticket: String = visit.ticket_id
	var preserved: bool = true
	for tick: int in 150:
		_step(x)
		var pending: Dictionary = x.g.state(x.world,visit.id)
		preserved = preserved and pending.get("desk_id","").is_empty() and not pending.has("queue_seq") and pending.receipts.is_empty() and x.world.facts.tickets.has(ticket) and visit.ticket_id==ticket and not x.world.facts.moves.has(visit.actor_id)
	var blocked: bool = preserved and not x.world.facts.adaptations.has("diagnosis")
	x.world.facts.staff.guide_nurse.on_shift = true
	var observed_nurse_travel: bool = false
	var unstaffed_not_dispatched: bool = true
	var actual_staffed: bool = false
	for tick: int in 900:
		_step(x)
		var row: Dictionary = x.g.state(x.world,visit.id)
		if x.world.facts.moves.has("guide_nurse"):
			observed_nurse_travel = true
			unstaffed_not_dispatched = unstaffed_not_dispatched and row.get("desk_id","").is_empty() and not row.has("queue_seq") and not x.world.facts.moves.has(visit.actor_id)
		if x.g._desk_usable(x.world,"guide"):actual_staffed = true
		if row.get("phase","")=="ready":break
	var final: Dictionary = x.g.state(x.world,visit.id)
	var result: Dictionary = {"case":"GUIDE-NURSE-RECOVERY","ok":blocked and observed_nurse_travel and unstaffed_not_dispatched and actual_staffed and final.get("phase","")=="ready" and final.receipts.size()==1 and visit.ticket_id==ticket and x.world.validate(_content).is_empty(),"all_unstaffed_preserved_pending":blocked,"nurse_real_travel_observed":observed_nurse_travel,"no_patient_dispatch_while_nurse_travels":unstaffed_not_dispatched,"nurse_actually_arrived":actual_staffed,"state":final.duplicate(true),"reason":visit.waiting_reason,"validation":x.world.validate(_content)}
	_dispose(x);return result

func _departure() -> Dictionary:
	var x: Dictionary = _base()
	x.world.facts.staff.guide_nurse.on_shift = false
	var visit: Dictionary = _visit(x,"leaving",[40,88])
	for tick: int in 150: _step(x)
	var result: CommandResult = x.c.execute(x.world,"clinical_refer",{"visit_id":visit.id})
	for tick: int in 700:
		_step(x)
		if visit.phase=="departed": break
	var row: Dictionary = {"case":"GUIDE-EXIT-BYPASS","ok":result.accepted and visit.phase=="departed" and x.g.state(x.world,visit.id).is_empty() and x.world.validate(_content).is_empty(),"referred":result.accepted,"phase":visit.phase,"location":x.world.facts.actors[visit.actor_id].location.duplicate(true),"validation":x.world.validate(_content)}
	_dispose(x);return row

func _dispose(x: Dictionary) -> void:
	if x.has("g"): x.g.clinic = null; x.g.waiting = null
	if x.has("c"): x.c.floor_guidance = null; x.c.waiting_life = null; x.c.departments = null
	if x.has("l"): x.l.floor_guidance = null; x.l.visitors = null
	if x.has("p"): x.p.waiting_life = null; x.p.clinic = null

func _simultaneous() -> Dictionary:
	var x: Dictionary = _base()
	var far: Dictionary = _visit(x,"far",[35,92])
	var near: Dictionary = _visit(x,"near",[46,86])
	for tick: int in 1000:
		_step(x)
		if x.g.state(x.world,far.id).get("phase","")=="ready" and x.g.state(x.world,near.id).get("phase","")=="ready": break
	var f: Dictionary = x.g.state(x.world,far.id)
	var n: Dictionary = x.g.state(x.world,near.id)
	var order: bool = f.get("phase","")=="ready" and n.get("phase","")=="ready" and int(n.receipts[0].completed_tick)<int(f.receipts[0].completed_tick) and int(n.arrived_seq)<int(f.arrived_seq)
	var row: Dictionary = {"case":"GUIDE-ARRIVAL-ORDER","ok":order and far.ticket_id<near.ticket_id and x.world.validate(_content).is_empty(),"old_ticket_far_first":far.ticket_id<near.ticket_id,"actual_near_first":order,"far":f.duplicate(true),"near":n.duplicate(true),"validation":x.world.validate(_content)}
	_dispose(x);return row

func _missing_desk() -> Dictionary:
	var x: Dictionary = _base()
	x.world.facts.facilities.erase("guide");x.world.touch()
	var visit: Dictionary = _visit(x,"desk_missing",[40,88])
	for tick: int in 80: _step(x)
	var blocked: bool = x.g.state(x.world,visit.id).receipts.is_empty() and visit.waiting_reason.contains("导诊台") and x.world.facts.preparations.is_empty()
	var build: BuildService = BuildService.new(_content,x.space)
	var command: CommandResult = build.execute(x.world,"build_facility",{"id":"guide","definition_id":"SE01","floor_id":1,"cell":[47,83]})
	visit = x.world.facts.visits.desk_missing
	for tick: int in 700:
		_step(x)
		if x.g.state(x.world,visit.id).phase=="ready": break
	var row: Dictionary = {"case":"GUIDE-DESK-BUILD-RECOVERY","ok":blocked and command.accepted and x.g.state(x.world,visit.id).phase=="ready" and x.world.validate(_content).is_empty(),"blocked_no_bypass":blocked,"actual_build":command.to_record(),"state":x.g.state(x.world,visit.id).duplicate(true),"validation":x.world.validate(_content)}
	_dispose(x);return row

func _nurse_handoff() -> Dictionary:
	var x: Dictionary = _base()
	HospitalFactory._add_staff(x.world,"replacement","接班护士","nurse",[53,90],_content)
	for key: String in ["d","s","w","r","f"]: x[key].ensure(x.world)
	var visit: Dictionary = _visit(x,"handoff_first",[40,88])
	var changed: bool = false
	var preserved: bool = true
	for tick: int in 800:
		_step(x)
		var row: Dictionary = x.g.state(x.world,visit.id)
		if row.phase=="working" and not changed and int(row.remaining_ticks)<40:
			x.world.facts.staff.guide_nurse.on_shift = false
			changed = true
		if changed and row.phase=="working": preserved = preserved and row.nurse_id=="guide_nurse"
		if row.phase=="ready" and x.world.facts.floor_guidance.releases.is_empty(): break
	var second: Dictionary = _visit(x,"handoff_second",[44,90])
	for tick: int in 900:
		_step(x)
		if x.g.state(x.world,second.id).phase=="ready": break
	var state: Dictionary = x.g.state(x.world,second.id)
	var second_nurse: String = "" if state.receipts.is_empty() else str(state.receipts[0].nurse_id)
	var old_clear: bool = x.world.facts.staff.guide_nurse.get("active_job_id","")=="" and x.world.facts.floor_guidance.releases.is_empty()
	var row: Dictionary = {"case":"GUIDE-NURSE-SAFE-HANDOFF","ok":changed and preserved and old_clear and second_nurse=="replacement" and state.phase=="ready" and x.world.validate(_content).is_empty(),"changed_during_real_work":changed,"original_work_finished":preserved,"old_nurse_really_clear":old_clear,"second_nurse":second_nurse,"state":state.duplicate(true),"old_location":x.world.facts.actors.guide_nurse.location.duplicate(true),"validation":x.world.validate(_content)}
	_dispose(x);return row

func _local_seats() -> Dictionary:
	var x: Dictionary = _base()
	_facility(x,"near_chair","FUR09",[41,79])
	_facility(x,"far_chair","FUR09",[55,92])
	_facility(x,"up_chair","FUR09",[41,79]);x.world.facts.facilities.up_chair.floor_id = 2
	var plots: Array = HospitalSpace.floor_plots(x.world,1).duplicate(true)
	x.world.facts.floors.completed_top_floor = {}
	for plot: Array in plots: x.world.facts.floors.completed_top_floor[HospitalSpace.plot_key(plot)] = 2
	x.world.facts.floors.height_intervals = [{"first":1,"last":2,"height_m":float(_content.balance.floors.clear_height_m)}]
	x.world.facts.floors.overrides["2"] = {"plots":plots,"blocked":[],"doors":[],"paths":[]}
	x.world.touch()
	var visit: Dictionary = _visit(x,"seats",[40,88])
	for tick: int in 800:
		_step(x)
		if x.world.facts.actors[visit.actor_id].get("support_facility_id","")=="near_chair": break
	var seated: bool = x.world.facts.actors[visit.actor_id].get("support_facility_id","")=="near_chair"
	var before: Dictionary = x.world.freeze()
	var far: CommandResult = x.l.execute(x.world,"waiting_select_seat",{"visit_id":visit.id,"facility_id":"far_chair"})
	var up: CommandResult = x.l.execute(x.world,"waiting_select_seat",{"visit_id":visit.id,"facility_id":"up_chair"})
	var atomic: bool = before==x.world.freeze()
	var wall: bool = not x.g.scope.allows(x.world,visit.actor_id,"diagnosis",1,[35,69])
	var row: Dictionary = {"case":"GUIDE-LOCAL-SEATS","ok":seated and not far.accepted and not up.accepted and atomic and wall and x.world.validate(_content).is_empty(),"actual_near_chair":seated,"far_rejected":far.to_record(),"upper_rejected":up.to_record(),"rejections_unchanged":atomic,"inside_wall_not_waiting":wall,"validation":x.world.validate(_content),"reason":visit.waiting_reason}
	_dispose(x);return row

func _desk_removal() -> Dictionary:
	var x: Dictionary = _base()
	for tick: int in 500:
		_step(x)
		if x.space.at(x.world,"guide_nurse",1,x.space.guidance_operator_cell(x.world,"guide","guide_nurse")) and not x.world.facts.moves.has("guide_nurse"): break
	var arrived: bool = x.space.at(x.world,"guide_nurse",1,x.space.guidance_operator_cell(x.world,"guide","guide_nurse"))
	var before: Dictionary = x.world.facts.actors.guide_nurse.location.duplicate(true)
	var build: BuildService = BuildService.new(_content,x.space)
	var removed: CommandResult = build.execute(x.world,"build_demolish",{"target_id":"guide"})
	for tick: int in 3: _step(x)
	var released: bool = x.world.facts.staff.guide_nurse.get("active_job_id","")=="" and x.world.facts.floor_guidance.releases.is_empty()
	var same: bool = before==x.world.facts.actors.guide_nurse.location
	var row: Dictionary = {"case":"GUIDE-DESK-REMOVAL","ok":arrived and removed.accepted and released and same and x.world.validate(_content).is_empty(),"nurse_actually_arrived":arrived,"actual_demolition":removed.to_record(),"released_without_teleport":released and same,"validation":x.world.validate(_content)}
	_dispose(x);return row

func _move_ownership() -> Dictionary:
	var x: Dictionary = _base()
	x.g.dispatch(x.world)
	var move: Dictionary = x.world.facts.moves.get("guide_nurse",{})
	var tagged: bool = move.get("guidance_nurse_desk","")=="guide"
	var reason: String = "no approach movement"
	if not move.is_empty(): reason = x.space.request_move(x.world,"guide_nurse",int(move.target_floor),move.target_cell)
	var cleared: bool = not move.has("guidance_nurse_desk")
	x.world.facts.staff.guide_nurse.on_shift = false
	x.g.dispatch(x.world)
	x.g.dispatch(x.world)
	var protected: bool = x.world.facts.moves.has("guide_nurse") and x.world.facts.moves.guide_nurse==move
	var row: Dictionary = {"case":"GUIDE-MOVE-OWNERSHIP","ok":tagged and reason.is_empty() and cleared and protected and x.world.validate(_content).is_empty(),"own_approach_tag":tagged,"same_target_transfer_clears_tag":cleared,"release_does_not_cancel_external_trip":protected,"reason":reason,"validation":x.world.validate(_content)}
	_dispose(x);return row

func _save_guards() -> Dictionary:
	var x: Dictionary = _base()
	var visit: Dictionary = _visit(x,"guards",[40,88])
	for tick: int in 700:
		_step(x)
		if x.g.state(x.world,visit.id).phase=="ready": break
	var checks: Dictionary = {"real_ready_input":x.g.state(x.world,visit.id).phase=="ready" and x.world.validate(_content).is_empty()}
	for field: String in ["next_recheck","route_at_desk","destination_cell"]:
		var candidate: WorldState = WorldState.new(x.world.freeze())
		candidate.facts.floor_guidance.visits.guards[field] = "invalid"
		var before: Dictionary = candidate.freeze()
		checks[field] = not candidate.validate(_content).is_empty() and candidate.freeze()==before
	x.world.facts.staff.guide_nurse.on_shift = false
	x.g.dispatch(x.world)
	checks.real_release_input = x.world.facts.floor_guidance.releases.has("guide_nurse") and x.world.validate(_content).is_empty()
	for field: String in ["cell","clearance"]:
		var candidate: WorldState = WorldState.new(x.world.freeze())
		candidate.facts.floor_guidance.releases.guide_nurse[field] = "invalid"
		var before: Dictionary = candidate.freeze()
		checks["release_"+field] = not candidate.validate(_content).is_empty() and candidate.freeze()==before
	var row: Dictionary = {"case":"GUIDE-SAVE-GUARDS","ok":not checks.values().has(false),"checks":checks}
	_dispose(x);return row

func _dynamic_admission_retry()->Dictionary:
	var x:Dictionary=_base()
	var v:Dictionary=_visit(x,"dynamic_retry",[35,94])
	var reached:bool=false
	for tick:int in 700:
		x.g.dispatch(x.world);x.c.dispatch(x.world);x.space.advance(x.world)
		var s:Dictionary=x.g.state(x.world,v.id)
		if not s.is_empty() and not s.has("queue_seq"):
			var p:Dictionary=x.g._queue_point(x.world,v.actor_id,"guide",v.id)
			if not p.is_empty() and x.space.at(x.world,v.actor_id,1,p.cell) and not x.world.facts.moves.has(v.actor_id):reached=true;break
		x.g.advance(x.world);x.world.facts.sim_tick+=1;x.world.touch(false)
	var s:Dictionary=x.g.state(x.world,v.id)
	var a:Dictionary=x.world.facts.actors[v.actor_id]
	var body:Rect2=x.space._actor_rect(a,ConvoyTrail.point(a.location.cell))
	# Controlled transient reservation at the real arrival boundary. No movement,
	# admission query or path result is replaced. This is not a reservation creator test.
	x.world.facts.adaptations.dynamic_retry={"kind":"facility","floor_id":1,"actor_id":"other","staff_ids":[],"facility_id":"probe","regions":[[body.position.x,body.position.y,body.size.x,body.size.y]]}
	x.space.reservation_changed(x.world,"dynamic_retry");x.world.touch(false)
	x.g.prepare(x.world,v,x.world.facts.tickets[v.ticket_id])
	var rejected:bool=not s.has("queue_seq")
	var revision:int=int(x.world.facts.floor_guidance.desks.guide.get("queue_revision",0))
	x.world.facts.adaptations.erase("dynamic_retry")
	x.space.reservation_changed(x.world,"dynamic_retry");x.world.touch(false)
	var released:bool=x.g._queue_admission_clear(x.world,v.actor_id,1,a.location.cell)
	var admitted:bool=false
	for tick:int in 20:
		x.g.prepare(x.world,v,x.world.facts.tickets[v.ticket_id])
		if s.has("queue_seq"):admitted=true;break
		x.world.facts.sim_tick+=1;x.world.touch(false)
	var result:Dictionary={"ok":reached and rejected and released and admitted,"reached_by_actual_movement":reached,"blocked_without_number":rejected,"released_body_check_clear":released,"admitted_without_other_queue_changes":admitted,"revision_before_release":revision,"state":s.duplicate(true)}
	_dispose(x);return result
