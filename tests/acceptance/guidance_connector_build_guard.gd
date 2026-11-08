extends "res://tests/acceptance/guidance_fixed_queue.gd"
func run_connector_guard(content: HospitalContent)->Dictionary:
	_content=content
	var cases: Array=[_actual_connector("VC01"),_actual_connector("VC02")]
	return {"passed":not cases.any(func(r: Dictionary)->bool:return not r.ok),"cases":cases}
func _actual_connector(definition: String)->Dictionary:
	var x: Dictionary=_base(false,true)
	x.world.facts.connectors.clear()
	# Front cells 87..89 stay clear. The actual second queue body at y88
	# needs passage rows 89/90; the new shaft begins at y90, beyond the
	# initial three-cell desk-placement check.
	_facility(x,"guide","SE01",[55,86]);x.world.touch()
	var connector: HospitalConnectors=HospitalConnectors.new(_content,x.space)
	var draft: Dictionary={"definition_id":definition,"floor_id":1,"cell":[55,90],"rotation":2}
	var preflight: Dictionary=connector.preview(x.world,"connector_build",draft)
	var legal_without_queue: bool=preflight.get("ok",false)
	var gate: Dictionary=_visit(x,"gate",[56,88])
	for tick: int in 600:
		_step(x)
		if x.g.state(x.world,gate.id).get("phase","")=="working":break
	var leader_working: bool=x.g.state(x.world,gate.id).get("phase","")=="working"
	var v: Dictionary=_visit(x,"queued",[58,88])
	var initial: Dictionary=x.world.facts.actors[v.actor_id].location.duplicate(true)
	var actual: bool=false;var no_overlap: bool=true
	for tick: int in 60:
		_step(x)
		no_overlap=no_overlap and not _overlap(x,v.actor_id)
		var state: Dictionary=x.g.state(x.world,v.id)
		actual=state.get("phase","")=="desk_queue" and state.has("queue_seq") and state.get("queue_cell",[])==[56,88] and x.space.at(x.world,v.actor_id,1,state.queue_cell) and not x.world.facts.moves.has(v.actor_id) and state.receipts.is_empty() and initial!=x.world.facts.actors[v.actor_id].location
		if actual:break
	var state: Dictionary=x.g.state(x.world,v.id).duplicate(true)
	var before: Dictionary=x.world.freeze()
	var attempt: CommandResult=connector.execute(x.world,"connector_build",draft)
	var unchanged: bool=before==x.world.freeze()
	var row: Dictionary={"case":"actual_queue_blocks_later_shaft_"+definition,"ok":legal_without_queue and leader_working and actual and no_overlap and not attempt.accepted and attempt.reason.contains("两格静态通路") and unchanged,"legal_before_queue":legal_without_queue,"preflight_reason":preflight.get("reason",""),"leader_actually_working":leader_working,"patient_actually_walked_to_tail":actual,"initial_location":initial,"state_before_build":state,"shaft_draft":draft,"attempt":attempt.to_record(),"unchanged_on_rejection":unchanged,"no_overlap":no_overlap,"validation":x.world.validate(_content)}
	_dispose(x);return row
