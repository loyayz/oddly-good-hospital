extends "res://tests/acceptance/floor_guidance.gd"

func run_reselection(database: HospitalContent, selected: Array = []) -> Dictionary:
	_content = database
	var methods: Dictionary = {"GUIDE-TARGET-UNREACHABLE-ALTERNATIVE":_unreachable_alternative,"GUIDE-TARGET-UNREACHABLE-RECOVERY":_unreachable_recovery,"GUIDE-TARGET-CLOSED":_closed_or_removed.bind(false),"GUIDE-TARGET-REMOVED":_closed_or_removed.bind(true),"GUIDE-TARGET-TEMPORARY-BODY":_temporary_body,"GUIDE-TARGET-NONE-THEN-BUILD":_none_then_build,"GUIDE-TARGET-ACTIVE-MOVE-ALTERNATIVE":_unreachable_alternative.bind(true),"GUIDE-TARGET-ACTIVE-MOVE-RECOVERY":_unreachable_recovery.bind(true),"GUIDE-TARGET-ACTIVE-MOVE-BODY":_moving_temporary_body,"GUIDE-TARGET-UNSAFE-QUEUE-ALTERNATIVE":_unreachable_alternative.bind(true,true)}
	var rows: Array = []
	for id: String in (methods.keys() if selected.is_empty() else selected):
		if not methods.has(id): return {"ok":false,"error":"unknown selector "+id}
		rows.append(methods[id].call())
	return {"ok":not rows.any(func(row: Dictionary)->bool:return not row.get("ok",false)),"cases":rows}

func _unreachable_alternative(after_move: bool = false, occupy_queue: bool = false) -> Dictionary:
	var x: Dictionary = _base(false,true)
	var visit: Dictionary = _visit(x,"reselect",[40,88])
	var reached_boundary: bool = false
	for tick: int in 800:
		_step(x)
		var state: Dictionary = x.g.state(x.world,visit.id)
		if state.get("target_id","")=="diagnosis" and state.get("phase","")=="destination" and int(x.world.facts.actors[visit.actor_id].location.get("floor_id",0))==1:
			reached_boundary = true;break
	if after_move: reached_boundary = reached_boundary and _pending_upper_move(x,visit)
	var before: Dictionary = x.g.state(x.world,visit.id).duplicate(true)
	var build: BuildService = BuildService.new(_content,x.space)
	var room: CommandResult = build.execute(x.world,"build_room",{"id":"lower","room_type_id":"gp","floor_id":1,"origin":[34,66],"size":[10,12],"door":{"definition_id":"DR04","edge":"south","offset":3}})
	var asset: CommandResult = build.execute(x.world,"build_facility",{"id":"lower_diagnosis","definition_id":"FUR02","floor_id":1,"cell":[39,69],"room_id":"lower"})
	# Legal failure boundary: elevator has not boarded this patient. No
	# body or job progress is changed; actual recovery movement is tested.
	if occupy_queue:
		x.world.facts.actors["queue_blocker"] = {"id":"queue_blocker","name":"临时楼上排队点占用者","species_id":"S49","location":{"kind":"floor","floor_id":2,"cell":before.queue_cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
	x.world.facts.connectors.lift.failed = true
	x.world.touch()
	var input_validation: String = x.world.validate(_content)
	var original: Dictionary = x.space.facility_layout(x.world,"diagnosis")
	var alternate: Dictionary = x.space.facility_layout(x.world,"lower_diagnosis")
	var old_unreachable: bool = not x.space.can_reach(x.world,visit.actor_id,2,original.patient_cell)
	var alternate_reachable: bool = x.space.can_reach(x.world,visit.actor_id,1,alternate.patient_cell)
	var unsafe_saved_queue: bool = not occupy_queue or not x.space.public_areas.safe_wait(x.world,visit.actor_id,2,before.queue_cell)
	var no_early_claim: bool = true
	for tick: int in 900:
		_step(x)
		no_early_claim = no_early_claim and x.world.facts.sessions.is_empty() and not x.world.facts.adaptations.has("lower_diagnosis")
		if x.g.state(x.world,visit.id).get("phase","")=="ready" and x.g.state(x.world,visit.id).get("target_id","")=="lower_diagnosis": break
	var after: Dictionary = x.g.state(x.world,visit.id).duplicate(true)
	var recovered: bool = after.get("phase","")=="ready" and after.get("target_id","")=="lower_diagnosis" and int(x.world.facts.actors[visit.actor_id].location.floor_id)==1
	var row: Dictionary = {"case":"GUIDE-TARGET-UNSAFE-QUEUE-ALTERNATIVE" if occupy_queue else "GUIDE-TARGET-ACTIVE-MOVE-ALTERNATIVE" if after_move else "GUIDE-TARGET-UNREACHABLE-ALTERNATIVE","ok":(not occupy_queue or x.space.at(x.world,"queue_blocker",2,before.queue_cell)) and unsafe_saved_queue and reached_boundary and room.accepted and asset.accepted and input_validation.is_empty() and old_unreachable and alternate_reachable and recovered and no_early_claim and x.world.validate(_content).is_empty(),"saved_queue_is_unsafe":unsafe_saved_queue,"upper_occupant_never_moved":not occupy_queue or x.space.at(x.world,"queue_blocker",2,before.queue_cell),"selected_original_before_edit":reached_boundary,"build_room":room.to_record(),"build_alternate":asset.to_record(),"input_validation":input_validation,"original_unreachable":old_unreachable,"alternate_reachable":alternate_reachable,"actual_reselection_and_arrival":recovered,"no_early_clinical_claim":no_early_claim,"before":before,"after":after,"reason":visit.waiting_reason,"location":x.world.facts.actors[visit.actor_id].location.duplicate(true),"validation":x.world.validate(_content)}
	_dispose(x);return row

func _first_destination(x: Dictionary, visit: Dictionary) -> bool:
	for tick: int in 800:
		_step(x)
		if x.g.state(x.world,visit.id).get("phase","")=="destination": return true
	return false

func _unreachable_recovery(after_move: bool = false) -> Dictionary:
	var x: Dictionary = _base(false,true)
	var visit: Dictionary = _visit(x,"recovery",[40,88])
	var ticket: String = visit.ticket_id
	var reached_boundary: bool = _first_destination(x,visit)
	if after_move: reached_boundary = reached_boundary and _pending_upper_move(x,visit)
	x.world.facts.connectors.lift.failed = true;x.world.touch()
	var input_validation: String = x.world.validate(_content)
	var stayed_safe: bool = true
	var sequence: int = int(x.world.facts.floor_guidance.next_arrival)
	for tick: int in 80:
		_step(x)
		var state: Dictionary = x.g.state(x.world,visit.id)
		stayed_safe = stayed_safe and state.get("phase","")!="ready" and state.receipts.size()==1 and state.arrived_seq==-1 and x.world.facts.sessions.is_empty() and x.world.facts.preparations.is_empty() and not x.world.facts.adaptations.has("diagnosis") and int(x.world.facts.actors[visit.actor_id].location.floor_id)==1
	var no_remote_sequence: bool = int(x.world.facts.floor_guidance.next_arrival)==sequence
	var waited: Dictionary = x.g.state(x.world,visit.id).duplicate(true)
	x = _restore_json(x)
	if x.has("restore_error"): return {"case":"GUIDE-TARGET-ACTIVE-MOVE-RECOVERY" if after_move else "GUIDE-TARGET-UNREACHABLE-RECOVERY","ok":false,"error":x.restore_error}
	visit = x.world.facts.visits.recovery
	var restored: bool = bool(x.restore_ok)
	x.world.facts.connectors.lift.failed = false;x.world.touch()
	var actual_ride: bool = false
	for tick: int in 1400:
		_step(x)
		actual_ride = actual_ride or x.world.facts.actors[visit.actor_id].location.kind=="transit"
		if x.g.state(x.world,visit.id).get("phase","")=="ready": break
	var after: Dictionary = x.g.state(x.world,visit.id).duplicate(true)
	var floors: Array = []
	for receipt: Dictionary in after.receipts: floors.append(receipt.floor_id)
	var row: Dictionary = {"case":"GUIDE-TARGET-ACTIVE-MOVE-RECOVERY" if after_move else "GUIDE-TARGET-UNREACHABLE-RECOVERY","ok":reached_boundary and input_validation.is_empty() and stayed_safe and no_remote_sequence and restored and actual_ride and after.phase=="ready" and after.target_id=="diagnosis" and floors==[1,2] and visit.ticket_id==ticket and x.world.validate(_content).is_empty(),"legal_failure_before_boarding":reached_boundary,"input_validation":input_validation,"no_alternative_safe_wait":stayed_safe,"no_remote_arrival_number":no_remote_sequence,"json_restore_while_waiting":restored,"wait_state":waited,"actual_lift_after_recovery":actual_ride,"guidance_floors":floors,"after":after,"validation":x.world.validate(_content)}
	_dispose(x);return row

func _closed_or_removed(remove: bool) -> Dictionary:
	var x: Dictionary = _base()
	var visit: Dictionary = _visit(x,"changed_target",[40,88])
	var ticket: String = visit.ticket_id
	var reached_boundary: bool = _first_destination(x,visit)
	var build: BuildService = BuildService.new(_content,x.space)
	var room: CommandResult = build.execute(x.world,"build_room",{"id":"alternate_room","room_type_id":"gp","floor_id":1,"origin":[51,66],"size":[10,12],"door":{"definition_id":"DR04","edge":"south","offset":3}})
	var asset: CommandResult = build.execute(x.world,"build_facility",{"id":"alternate_diagnosis","definition_id":"FUR02","floor_id":1,"cell":[56,69],"room_id":"alternate_room"})
	var changed: CommandResult
	if remove: changed = build.execute(x.world,"build_demolish",{"target_id":"diagnosis"})
	else:
		var remodel: HospitalRemodel = HospitalRemodel.new(_content,x.space)
		remodel.services = {"building":build}
		changed = remodel.execute(x.world,"remodel_prepare",{"commands":[{"kind":"build_move","target_id":"diagnosis","cell":[40,69],"floor_id":1}]})
	x.world.touch()
	var validation: String = x.world.validate(_content)
	var no_early_hold: bool = true
	for tick: int in 1000:
		_step(x)
		no_early_hold = no_early_hold and x.world.facts.sessions.is_empty() and not x.world.facts.adaptations.has("alternate_diagnosis")
		if x.g.state(x.world,visit.id).get("phase","")=="ready": break
	var after: Dictionary = x.g.state(x.world,visit.id).duplicate(true)
	var row: Dictionary = {"case":"GUIDE-TARGET-REMOVED" if remove else "GUIDE-TARGET-CLOSED","ok":reached_boundary and room.accepted and asset.accepted and changed.accepted and validation.is_empty() and no_early_hold and after.phase=="ready" and after.target_id=="alternate_diagnosis" and after.receipts.size()==2 and visit.ticket_id==ticket and x.world.validate(_content).is_empty(),"original_really_guided":reached_boundary,"normal_build_room":room.to_record(),"normal_build_alternate":asset.to_record(),"normal_close_or_demolish":changed.to_record(),"input_validation":validation,"no_early_clinical_hold":no_early_hold,"after":after,"validation":x.world.validate(_content)}
	_dispose(x);return row

func _temporary_body() -> Dictionary:
	var x: Dictionary = _base()
	var visit: Dictionary = _visit(x,"crowd",[40,88])
	var reached_boundary: bool = _first_destination(x,visit)
	var layout: Dictionary = x.space.facility_layout(x.world,"diagnosis")
	x.world.facts.actors["temporary_body"] = {"id":"temporary_body","name":"临时在场者","species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":layout.patient_cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
	x.world.touch()
	var input_validation: String = x.world.validate(_content)
	var before: Dictionary = x.world.freeze()
	var changed: bool = x.g._reselect_unreachable_target(x.world,visit,x.g.state(x.world,visit.id))
	var row: Dictionary = {"case":"GUIDE-TARGET-TEMPORARY-BODY","ok":reached_boundary and input_validation.is_empty() and not changed and before==x.world.freeze(),"input_validation":input_validation,"temporary_body_does_not_replace_target_or_mutate_world":not changed and before==x.world.freeze()}
	_dispose(x);return row

func _none_then_build() -> Dictionary:
	var x: Dictionary = _base()
	var visit: Dictionary = _visit(x,"no_target",[40,88])
	var ticket: String = visit.ticket_id
	var reached_boundary: bool = _first_destination(x,visit)
	var build: BuildService = BuildService.new(_content,x.space)
	var removed: CommandResult = build.execute(x.world,"build_demolish",{"target_id":"diagnosis"})
	var safe_wait: bool = true
	for tick: int in 150:
		_step(x)
		var state: Dictionary = x.g.state(x.world,visit.id)
		safe_wait = safe_wait and state.get("phase","")!="ready" and state.receipts.size()==1 and state.arrived_seq==-1 and x.world.facts.sessions.is_empty() and x.world.facts.preparations.is_empty()
	var wait_state: Dictionary = x.g.state(x.world,visit.id).duplicate(true)
	var created: CommandResult = build.execute(x.world,"build_facility",{"id":"rebuilt_diagnosis","definition_id":"FUR02","floor_id":1,"cell":[39,69],"room_id":"clinic"})
	for tick: int in 900:
		_step(x)
		if x.g.state(x.world,visit.id).get("phase","")=="ready": break
	var after: Dictionary = x.g.state(x.world,visit.id).duplicate(true)
	var row: Dictionary = {"case":"GUIDE-TARGET-NONE-THEN-BUILD","ok":reached_boundary and removed.accepted and safe_wait and created.accepted and after.phase=="ready" and after.target_id=="rebuilt_diagnosis" and after.receipts.size()==2 and visit.ticket_id==ticket and x.world.validate(_content).is_empty(),"actual_first_guidance":reached_boundary,"normal_demolition":removed.to_record(),"safe_wait_without_target_or_repeated_service":safe_wait,"wait_state":wait_state,"normal_new_facility_build":created.to_record(),"after":after,"validation":x.world.validate(_content)}
	_dispose(x);return row

func _pending_upper_move(x: Dictionary, visit: Dictionary) -> bool:
	for tick: int in 900:
		_step(x)
		var state: Dictionary = x.g.state(x.world,visit.id)
		var actor: Dictionary = x.world.facts.actors[visit.actor_id]
		var move: Dictionary = x.world.facts.moves.get(visit.actor_id,{})
		if state.get("guide_floor",0)==2 and move.get("floor_guidance_key","")==state.get("request_key","") and actor.location.kind=="floor" and actor.location.floor_id==1: return true
	return false

func _moving_temporary_body() -> Dictionary:
	var x: Dictionary = _base()
	var visit: Dictionary = _visit(x,"moving_crowd",[40,88])
	var boundary: bool = _first_destination(x,visit)
	var moving: bool = false
	for tick: int in 300:
		_step(x)
		var state: Dictionary = x.g.state(x.world,visit.id)
		if state.has("destination_cell") and x.world.facts.moves.has(visit.actor_id): moving = true;break
	var state: Dictionary = x.g.state(x.world,visit.id)
	if not moving: _dispose(x);return {"case":"GUIDE-TARGET-ACTIVE-MOVE-BODY","ok":false,"error":"actual move boundary missing"}
	x.world.facts.actors["moving_blocker"] = {"id":"moving_blocker","name":"临时等候者","species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":state.destination_cell.duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
	x.world.touch()
	var validation: String = x.world.validate(_content)
	var retained: bool = true
	for tick: int in 60:
		_step(x)
		state = x.g.state(x.world,visit.id)
		retained = retained and state.target_id=="diagnosis" and state.receipts.size()==1
	var release: String = x.space.request_move(x.world,"moving_blocker",1,[54,91])
	for tick: int in 900:
		_step(x)
		if x.g.state(x.world,visit.id).get("phase","")=="ready" and not x.world.facts.moves.has("moving_blocker"): break
	var after: Dictionary = x.g.state(x.world,visit.id).duplicate(true)
	var row: Dictionary = {"case":"GUIDE-TARGET-ACTIVE-MOVE-BODY","ok":boundary and moving and validation.is_empty() and retained and release.is_empty() and after.phase=="ready" and after.target_id=="diagnosis" and after.receipts.size()==1 and x.space.at(x.world,"moving_blocker",1,[54,91]) and x.world.validate(_content).is_empty(),"actual_patient_move_started":moving,"input_validation":validation,"temporary_body_kept_original_target":retained,"blocker_actual_move_request":release,"after":after,"validation":x.world.validate(_content)}
	_dispose(x);return row
