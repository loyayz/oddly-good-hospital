extends "res://tests/acceptance/floor_guidance.gd"

# Focused ordering contract. Selector cases are legal input calculations, not
# claims of completed guidance. Ownership uses real guidance and GP arrival.
var _output_prefix: String = ""
var _inputs: Array = []

func run_order(database: HospitalContent, selected: Array, output_prefix: String) -> Dictionary:
	_content = database
	_output_prefix = output_prefix
	var methods: Dictionary = {"STATION-READY-ID":_ready_order,"STATION-FALLBACK":_fallback,"STATION-OWNERSHIP":_ownership,"STATION-MIXED-READY":_mixed_ready}
	var rows: Array = []
	for id: String in selected:
		if not methods.has(id): return {"ok":false,"error":"unknown selector "+id}
		rows.append(methods[id].call())
	return {"ok":not rows.is_empty() and not rows.any(func(row: Dictionary)->bool:return not row.get("ok",false)),"cases":rows,"inputs":_inputs,"scope":"selected ordering calculations and actual guidance/GP ownership only; no performance or full clinical chain"}

func _save_input(x: Dictionary, name: String) -> String:
	var validation: String = x.world.validate(_content)
	var path: String = _output_prefix+"-"+name+"-input.bin"
	var f: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	f.store_var(x.world.freeze(),true)
	f.close()
	_inputs.append({"name":name,"path":path,"validation":validation,"complete_facts_rng":true})
	return validation

func _add_alternate(x: Dictionary) -> bool:
	var build: BuildService = BuildService.new(_content,x.space)
	var room: CommandResult = build.execute(x.world,"build_room",{"id":"alternate_room","room_type_id":"gp","floor_id":1,"origin":[51,66],"size":[10,12],"door":{"definition_id":"DR04","edge":"south","offset":3}})
	var asset: CommandResult = build.execute(x.world,"build_facility",{"id":"alternate_diagnosis","definition_id":"FUR02","floor_id":1,"cell":[56,69],"room_id":"alternate_room"})
	x.world.facts.departments.units.general.room_ids.append("alternate_room")
	x.world.touch()
	return room.accepted and asset.accepted

func _pick(x: Dictionary, visit: Dictionary) -> String:
	return x.g._choose_target(x.world,visit,x.world.facts.tickets[visit.ticket_id])

func _ready_order() -> Dictionary:
	var x: Dictionary = _base(true)
	var visit: Dictionary = _visit(x,"ready",[40,88])
	var built: bool = _add_alternate(x)
	var validation: String = _save_input(x,"ready")
	var before: Dictionary = x.world.freeze()
	var pairs: Array = x.c.service_candidates(x.world,visit,"gp")
	var routes: Dictionary = {}
	for id: String in ["diagnosis","alternate_diagnosis"]:
		var layout: Dictionary = x.space.facility_layout(x.world,id)
		routes[id] = {"patient":x.space.route_cost(x.world,visit.actor_id,1,layout.patient_cell),"doctor":x.space.route_cost(x.world,"doctor",1,layout.operator_cells[0])}
	var selected: String = _pick(x,visit)
	var readonly: bool = before==x.world.freeze()
	var greater: bool = true
	for role: String in ["patient","doctor"]:
		greater = greater and routes.diagnosis[role].ok and routes.alternate_diagnosis[role].ok and int(routes.alternate_diagnosis[role].travel_ticks)>int(routes.diagnosis[role].travel_ticks)
	var copy: Dictionary = before.duplicate(true)
	var reversed: Dictionary = {}
	var ids: Array = copy.facilities.keys();ids.reverse()
	for id: String in ids: reversed[id] = copy.facilities[id]
	copy.facilities = reversed
	var restored: Dictionary = _guide_bind(WorldState.new(copy))
	var restore_validation: String = _save_input(restored,"ready-reversed-restored")
	var restored_pick: String = _pick(restored,restored.world.facts.visits.ready)
	_dispose(restored)
	# Legal mutable availability boundaries, no invented clinical completion.
	x.world.facts.facilities.alternate_diagnosis.intake_open = false;x.world.touch()
	var invalid_validation: String = _save_input(x,"first-closed")
	var closed_pick: String = _pick(x,visit)
	x.world.facts.facilities.alternate_diagnosis.intake_open = true
	x.world.facts.staff.doctor.on_shift = false;x.world.touch()
	var none_validation: String = _save_input(x,"no-ready")
	var no_ready: bool = x.c.service_candidates(x.world,visit,"gp").is_empty()
	var no_ready_pick: String = _pick(x,visit)
	x.world.facts.staff.doctor.on_shift = true;x.world.touch()
	var recovered: String = _pick(x,visit)
	HospitalFactory._add_staff(x.world,"aaa_doctor","另一医生","doctor",[60,90],_content)
	x.d.ensure(x.world);x.s.ensure(x.world);x.w.ensure(x.world);x.r.ensure(x.world);x.f.ensure(x.world)
	x.world.facts.staff.aaa_doctor.base_prepared = true;x.world.touch()
	var staff_validation: String = _save_input(x,"same-station-staff-id")
	var first_pair: Array = x.c.service_candidates(x.world,visit,"gp",false,false,{"first_only":true})
	var row: Dictionary = {"case":"STATION-READY-ID","ok":staff_validation.is_empty() and first_pair==[{"facility_id":"alternate_diagnosis","staff_id":"aaa_doctor"}] and built and validation.is_empty() and invalid_validation.is_empty() and none_validation.is_empty() and restore_validation.is_empty() and pairs==[{"facility_id":"alternate_diagnosis","staff_id":"doctor"},{"facility_id":"diagnosis","staff_id":"doctor"}] and greater and readonly and selected=="alternate_diagnosis" and restored_pick==selected and closed_pick=="diagnosis" and no_ready and no_ready_pick=="diagnosis" and recovered==selected,"staff_id_first_pair":first_pair,"both_full_ready_pairs":pairs,"routes":routes,"farther_id_first":selected,"read_only_full_facts_rng":readonly,"reverse_membership_restore":restored_pick,"first_closed":closed_pick,"doctor_off_shift_fallback":no_ready_pick,"recovered":recovered,"validation":validation}
	_dispose(x);return row

func _fallback() -> Dictionary:
	var x: Dictionary = _base()
	var first: Dictionary = _visit(x,"load_owner",[40,88])
	var actual_arrival: bool = false
	for tick: int in 800:
		_step(x)
		if x.g.state(x.world,first.id).get("phase","")=="ready": actual_arrival = true;break
	var built: bool = _add_alternate(x)
	var other: Dictionary = _visit(x,"fallback",[42,88])
	var load_validation: String = _save_input(x,"fallback-real-load")
	var before: Dictionary = x.world.freeze()
	var no_ready: bool = x.c.service_candidates(x.world,other,"gp").is_empty()
	var bounds: Dictionary = {}
	for id: String in ["diagnosis","alternate_diagnosis"]: bounds[id] = x.space.facility_travel_lower_bound_ticks(x.world,id,other.actor_id)
	var load_pick: String = _pick(x,other)
	var readonly: bool = before==x.world.freeze()
	# A selector-only copy with no other pending visits is a separate legal
	# input, not a claim that an arrived patient vanished during a flow.
	var empty: Dictionary = _base()
	var empty_built: bool = _add_alternate(empty)
	var equal_visit: Dictionary = _visit(empty,"equal",[48,88])
	var equal_validation: String = _save_input(empty,"fallback-equal")
	var equal_bounds: Dictionary = {}
	for id: String in ["diagnosis","alternate_diagnosis"]: equal_bounds[id] = empty.space.facility_travel_lower_bound_ticks(empty.world,id,equal_visit.actor_id)
	var equal_pick: String = _pick(empty,equal_visit)
	var row: Dictionary = {"case":"STATION-FALLBACK","ok":actual_arrival and built and empty_built and load_validation.is_empty() and equal_validation.is_empty() and no_ready and bounds.diagnosis<bounds.alternate_diagnosis and load_pick=="alternate_diagnosis" and readonly and equal_bounds.diagnosis==equal_bounds.alternate_diagnosis and equal_pick=="alternate_diagnosis","actual_prior_guidance_and_arrival":actual_arrival,"prior_state":x.g.state(x.world,first.id).duplicate(true),"no_ready":no_ready,"load_over_distance":load_pick,"bounds":bounds,"read_only_full_facts_rng":readonly,"equal_bounds":equal_bounds,"equal_id_tie":equal_pick,"validation":load_validation,"equal_validation":equal_validation}
	_dispose(x);_dispose(empty);return row

func _ownership() -> Dictionary:
	var started_ms: int = Time.get_ticks_msec()
	var x: Dictionary = _base(true)
	var built: bool = _add_alternate(x)
	x.world.facts.facilities.diagnosis.intake_open = false;x.world.touch()
	var visit: Dictionary = _visit(x,"ownership",[40,88])
	var validation: String = _save_input(x,"ownership-start")
	var setup_ms: int = Time.get_ticks_msec()-started_ms
	var original_ticket: String = visit.ticket_id
	var guided: bool = false
	# Stop at the real completed desk work before destination travel.
	for tick: int in 800:
		_step(x)
		if x.g.state(x.world,visit.id).get("phase","")=="destination": guided = true;break
	var original: Dictionary = x.g.state(x.world,visit.id).duplicate(true)
	var build: BuildService = BuildService.new(_content,x.space)
	var removed: CommandResult = build.execute(x.world,"build_demolish",{"target_id":"diagnosis"})
	var added: CommandResult = build.execute(x.world,"build_facility",{"id":"aaa_near","definition_id":"FUR02","floor_id":1,"cell":[40,75],"room_id":"clinic"})
	x.world.touch()
	var challenger_validation: String = _save_input(x,"ownership-challenger")
	var challenger: String = _pick(x,visit)
	var challenger_routes: Dictionary = {}
	for id: String in ["aaa_near","alternate_diagnosis"]:
		var layout: Dictionary = x.space.facility_layout(x.world,id)
		challenger_routes[id] = x.space.route_cost(x.world,visit.actor_id,1,layout.patient_cell)
	var nearer: bool = challenger_routes.aaa_near.ok and challenger_routes.alternate_diagnosis.ok and int(challenger_routes.aaa_near.travel_ticks)<int(challenger_routes.alternate_diagnosis.travel_ticks)
	var kept: bool = true
	var assigned: bool = false
	for tick: int in 900:
		_step(x)
		kept = kept and x.g.target(x.world,visit.id)=="alternate_diagnosis"
		if not visit.ticket_id.is_empty() and x.world.facts.tickets[visit.ticket_id].get("service_assigned",false): assigned = true;break
	var target: Dictionary = x.g.state(x.world,visit.id).duplicate(true)
	var assigned_validation: String = _save_input(x,"ownership-assigned")
	var held: Dictionary = x.world.facts.adaptations.get("alternate_diagnosis",{}).duplicate(true)
	# Branch at a genuine assigned boundary: invalidating the held facility
	# must release its claim, not reserve another station in the same call.
	var invalid: Dictionary = _guide_bind(WorldState.new(x.world.freeze()))
	invalid.world.facts.facilities.alternate_diagnosis.intake_open = false;invalid.world.touch()
	var invalid_validation: String = _save_input(invalid,"ownership-invalidated")
	var invalid_visit: Dictionary = invalid.world.facts.visits.ownership
	var invalid_ticket: Dictionary = invalid.world.facts.tickets.get(invalid_visit.ticket_id,{})
	var invalid_pair: Dictionary = {}
	if assigned: invalid.c._gather_assigned(invalid.world,invalid_visit,invalid_ticket,invalid_pair)
	var released: bool = assigned and not invalid_ticket.get("service_assigned",false) and invalid_pair.is_empty() and not invalid.world.facts.adaptations.has("aaa_near") and invalid.world.facts.adaptations.get("alternate_diagnosis",{}).get("owner_id","")!=invalid_ticket.get("id","")
	_dispose(invalid)
	var begun: bool = false
	for tick: int in 1000:
		_step(x)
		kept = kept and x.g.target(x.world,visit.id)=="alternate_diagnosis"
		if visit.phase=="gp": begun = true;break
	var sessions: Array = x.world.facts.sessions.values()
	var correct_session: bool = begun and sessions.size()==1 and sessions[0].facility_id=="alternate_diagnosis" and sessions[0].staff_ids==["doctor"]
	var final_layout: Dictionary = x.space.facility_layout(x.world,"alternate_diagnosis")
	var at_service: bool = x.space.at(x.world,visit.actor_id,1,final_layout.patient_cell) and x.space.at(x.world,"doctor",1,final_layout.operator_cells[0])
	var same_ticket: bool = correct_session and sessions[0].get("original_ticket",{}).get("id","")==original_ticket and target.ticket_id==original_ticket and target.receipts[0].request_key==original_ticket+":gp"
	var row: Dictionary = {"case":"STATION-OWNERSHIP","ok":built and validation.is_empty() and guided and original.target_id=="alternate_diagnosis" and removed.accepted and added.accepted and challenger_validation.is_empty() and challenger=="aaa_near" and nearer and kept and assigned and assigned_validation.is_empty() and held.get("staff_ids",[])==["doctor"] and target.get("arrived_seq",-1)>=0 and target.receipts.size()==1 and invalid_validation.is_empty() and released and correct_session and at_service and same_ticket and x.world.validate(_content).is_empty(),"timing_ms":{"setup":setup_ms,"body":Time.get_ticks_msec()-started_ms-setup_ms},"real_patient_and_doctor_at_service_cells":at_service,"same_original_ticket_and_guidance_receipt":same_ticket,"final_session":sessions[0].duplicate(true) if correct_session else {},"real_guidance_completed":guided,"original":original,"challenger_routes":challenger_routes,"new_candidate_if_rechosen":challenger,"original_target_kept":kept,"actual_destination_arrival":target,"real_assigned_reservation":held,"invalid_assignment_released_without_second_claim":released,"actual_gp_start_same_pair":correct_session,"validation":validation,"final_validation":x.world.validate(_content)}
	_dispose(x);return row

func _mixed_ready() -> Dictionary:
	var started_ms: int = Time.get_ticks_msec()
	var x: Dictionary = _base(true)
	var built: bool = _add_alternate(x)
	var visit: Dictionary = _visit(x,"mixed",[40,88])
	x.c.scheduler = x.s
	var slot: int = x.s.shift_index(x.world)
	x.world.facts.staff.doctor.schedule[slot].pools = ["alternate_room"]
	x.world.touch()
	var validation: String = _save_input(x,"mixed-ready-far-room-duty")
	var setup_ms: int = Time.get_ticks_msec()-started_ms
	var before: Dictionary = x.world.freeze()
	var structural: Array = x.g._target_ids(x.world,visit,"gp")
	var reachable: bool = true
	var bounds: Dictionary = {}
	for id: String in ["diagnosis","alternate_diagnosis"]:
		var layout: Dictionary = x.space.facility_layout(x.world,id)
		reachable = reachable and x.space.can_reach(x.world,visit.actor_id,1,layout.patient_cell)
		bounds[id] = x.space.facility_travel_lower_bound_ticks(x.world,id,visit.actor_id)
	var ready_pairs: Array = x.c.service_candidates(x.world,visit,"gp")
	var selected: String = _pick(x,visit)
	var readonly: bool = before==x.world.freeze()
	x.world.facts.staff.doctor.on_shift = false;x.world.touch()
	var off_validation: String = _save_input(x,"mixed-none-ready")
	var none: Array = x.c.service_candidates(x.world,visit,"gp")
	var fallback: String = _pick(x,visit)
	x.world.facts.staff.doctor.on_shift = true;x.world.touch()
	var recovery_validation: String = _save_input(x,"mixed-far-ready-recovery")
	var recovered: String = _pick(x,visit)
	x.world.facts.staff.doctor.schedule[slot].pools = ["clinic"];x.world.touch()
	var changed_validation: String = _save_input(x,"mixed-near-room-duty")
	var near_pairs: Array = x.c.service_candidates(x.world,visit,"gp")
	var changed: String = _pick(x,visit)
	var row: Dictionary = {"case":"STATION-MIXED-READY","ok":built and validation.is_empty() and off_validation.is_empty() and recovery_validation.is_empty() and changed_validation.is_empty() and structural==["alternate_diagnosis","diagnosis"] and reachable and bounds.diagnosis<bounds.alternate_diagnosis and ready_pairs==[{"facility_id":"alternate_diagnosis","staff_id":"doctor"}] and selected=="alternate_diagnosis" and readonly and none.is_empty() and fallback=="diagnosis" and recovered=="alternate_diagnosis" and near_pairs==[{"facility_id":"diagnosis","staff_id":"doctor"}] and changed=="diagnosis","structural_open_candidates":structural,"both_reachable":reachable,"lower_bounds":bounds,"only_far_ready_pairs":ready_pairs,"ready_beats_nearer_fallback":selected,"read_only_full_facts_rng":readonly,"none_ready_fallback":fallback,"readiness_recovered":recovered,"changed_room_duty_ready_pairs":near_pairs,"changed_room_duty_selection":changed,"validation":validation,"timing_ms":{"setup":setup_ms,"body":Time.get_ticks_msec()-started_ms-setup_ms},"scope":"legal scheduler-assignment selector inputs; no physical guidance or schedule-edit workflow claimed"}
	x.c.scheduler = null
	_dispose(x);return row
