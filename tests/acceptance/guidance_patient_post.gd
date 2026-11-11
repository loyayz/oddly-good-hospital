extends "res://tests/acceptance/guidance_operator_wait.gd"

# Independent actor-cell coordinates for a 2x1 SE01 built at [47,83].
const PATIENT_ONE: Array=[[47.5,84.0],[46.0,83.5],[47.5,82.0],[48.0,83.5]]
const PATIENT_TWO: Array=[[47.0,84.0],[45.0,83.0],[47.0,81.0],[48.0,83.0]]
const PATIENT_FACING: Array=[PI,PI*0.5,0.0,-PI*0.5]

func run_case(database: HospitalContent) -> Dictionary:
	content=database
	var rows: Array=[]
	for turns: int in 4:
		for species: String in ["S13","S28"]: rows.append(_patient_geometry(turns,species))
	rows.append(_adjacent_and_restore())
	rows.append(_refusals())
	rows.append(_legacy_work())
	rows.append(_two_real_patients(false));rows.append(_two_real_patients(true))
	return {"ok":rows.all(func(row:Dictionary)->bool:return row.ok),"runs":rows}

func _species_binding(species: String) -> String:
	for binding: Dictionary in content.catalog.treatment_bindings:
		if binding.species_id==species: return str(binding.id)
	return ""

func _post_input(turns: int = 0, species: String = "S13") -> Dictionary:
	var x: Dictionary=_base()
	x.checks.desk=_command(x,"build_facility",{"id":"guide","definition_id":"SE01","cell":[47,83],"rotation":turns}).accepted
	_staff(x,"nurse","nurse",[55,90])
	x.world.facts.staff.nurse.base_prepared=true
	var binding: String=_species_binding(species)
	x.checks.actual_species_binding=not binding.is_empty()
	if binding.is_empty(): return x
	x.head=_patient(x,"head",[35,90],"gp",binding)
	x.world.facts.actors[x.head.actor_id].facing=PATIENT_FACING[turns]
	x.sim.services.maintenance.ensure(x.world)
	return x

func _patient_geometry(turns: int, species: String) -> Dictionary:
	var x: Dictionary=_post_input(turns,species)
	if not x.checks.values().all(func(v:Variant)->bool:return v==true): return _finish(x,{"turns":turns,"species":species})
	var k: int=1 if species=="S13" else 2
	var expected: Array=PATIENT_ONE[turns] if k==1 else PATIENT_TWO[turns]
	x.checks.initial_posts=_geometry_boundary(x,{x.head.actor_id:expected,"nurse":BASE_POSTS[turns]})
	var space: HospitalSpace=x.sim.space
	var actor: Dictionary=x.world.facts.actors[x.head.actor_id]
	var original: Dictionary=x.world.freeze()
	var post: Dictionary=space.guidance_patient_post(x.world,"guide",actor.id)
	var point: Dictionary=x.sim.services.floor_guidance._queue_point(x.world,actor.id,"guide")
	var quote: Dictionary=space.facility_geometry_quote(x.world,"guide",actor.id,["nurse"])
	var dimensions: Dictionary=content.actor_body(actor)
	var physical: Vector2=Vector2(float(dimensions.width_m),float(dimensions.depth_m))/1.5
	if turns%2==1: physical=Vector2(physical.y,physical.x)
	var expected_rect:=Rect2(Vector2(float(expected[0]),float(expected[1]))+(Vector2.ONE*k-physical)*0.5,physical)
	var actual: Rect2=space.body_rectangle(actor)
	var region: Array=quote.get("regions",[[],[]])[1]
	x.checks.actual_clearance=space.clearance(actor)==k
	x.checks.independent_center_and_negative_normal=post.cell==expected and point.cell==expected and quote.get("patient_cell",[])==expected
	x.checks.same_target_facing=is_zero_approx(angle_difference(float(post.facing),float(PATIENT_FACING[turns]))) and is_zero_approx(angle_difference(float(point.facing),float(PATIENT_FACING[turns])))
	x.checks.independent_full_rect=actual.position.is_equal_approx(expected_rect.position) and actual.size.is_equal_approx(expected_rect.size)
	x.checks.quote_contains_exact_engine_body=quote.get("ok",false) and var_to_bytes(region)==var_to_bytes([actual.position.x,actual.position.y,actual.size.x,actual.size.y]) and post.rect==actual
	x.checks.nurse_integer_post_unchanged=quote.get("operator_cells",[])==[BASE_POSTS[turns]] and quote.get("regions",[]).size()==4 and quote.regions[3]==[BASE_POSTS[turns][0],BASE_POSTS[turns][1],1,1]
	x.checks.facts_rng_and_raw_layout_unchanged=original==x.world.freeze()
	return _finish(x,{"kind":"geometry","turns":turns,"species":species,"expected_cell":expected,"quote":quote})

func _adjacent_and_restore() -> Dictionary:
	var x: Dictionary=_post_input()
	x.peer=_patient(x,"peer",[55,90],"gp","B_S13_D09_M09")
	x.world.facts.actors[x.peer.actor_id].facing=-PI*0.5
	# A positive 0.0000167-cell gap avoids claiming that rounded engine values
	# form an exact mathematical zero-gap boundary. No body is compressed.
	x.checks.legal_initial_posts=_geometry_boundary(x,{x.head.actor_id:[47.5,84],x.peer.actor_id:[48.03335,84],"nurse":[47,82]})
	var space: HospitalSpace=x.sim.space
	var head: Rect2=space.body_rectangle(x.world.facts.actors[x.head.actor_id])
	var peer: Rect2=space.body_rectangle(x.world.facts.actors[x.peer.actor_id])
	x.checks.adjacent_actual_bodies_clear=not head.intersects(peer,false) and peer.position.x>=head.end.x
	x.checks.old_unit_box_would_block=Rect2(47.5,84,1,1).intersects(peer,false)
	var quote: Dictionary=space.facility_quote(x.world,"guide",x.head.actor_id,["nurse"])
	var result: String=space.reserve_facility(x.world,"guide",x.head.actor_id,x.head.actor_id,["nurse"])
	x.checks.neighbor_does_not_block_real_head=quote.get("ok",false) and result.is_empty()
	if not x.checks.neighbor_does_not_block_real_head: return _finish(x,{"kind":"adjacent_and_stream","quote":quote,"reserve_reason":result,"gap_cells":peer.position.x-head.end.x})
	x.checks.new_continuous_record_valid=x.world.validate(content).is_empty()
	var committed: Dictionary=x.world.facts.adaptations.get("guide",{}).duplicate(true)
	var restored: Dictionary=_restore_operator(x)
	x.checks.complete_fractional_cold_restore=restored.ok and committed==x.world.facts.adaptations.get("guide",{})
	var malformed: Array=[]
	for region: Array in [[NAN,84,0.5,0.5],[-0.1,84,0.5,0.5],[47.5,84,0.0,0.5],[47.5,84,0.5,-0.1],[47.5,84,INF,0.5]]:
		var facts: Dictionary=x.world.freeze();facts.adaptations.guide.regions[1]=region
		malformed.append(not WorldState.new(facts).validate(content).is_empty())
	var nurse_bad: Dictionary=x.world.freeze();nurse_bad.adaptations.guide.regions[3][2]=0.5
	var other_bad: Dictionary=x.world.freeze();other_bad.facilities.guide.definition_id="FUR09"
	var door_bad: Dictionary=x.world.freeze();door_bad.adaptations.guide.kind="door";door_bad.adaptations.guide.span=1;door_bad.adaptations.guide.clear_height_m=2.0;door_bad.adaptations.guide.clear_width_m=1.5;door_bad.adaptations.guide.regions=[[47.5,84,1,1]]
	x.checks.continuous_validation_is_narrow=malformed.all(func(v:bool)->bool:return v) and not WorldState.new(nurse_bad).validate(content).is_empty() and not WorldState.new(other_bad).validate(content).is_empty() and not WorldState.new(door_bad).validate(content).is_empty()
	return _finish(x,{"kind":"adjacent_and_stream","gap_cells":peer.position.x-head.end.x,"quote":quote,"reserve_reason":result,"restore":restored})

func _refusals() -> Dictionary:
	var rows: Array=[]
	for mode: String in ["body","blocked","wall","door","facility","reservation"]:
		var x: Dictionary=_post_input()
		x.peer=_patient(x,"peer",[55,90],"gp","B_S13_D09_M09")
		x.checks.head_not_already_at_rejected_post=_geometry_boundary(x,{x.head.actor_id:[35,90],x.peer.actor_id:[55,90],"nurse":[47,82]})
		if mode=="body":
			x.checks.body_boundary=_geometry_boundary(x,{x.peer.actor_id:[47.5,84]})
		elif mode=="blocked": x.world.facts.floors.overrides["1"].blocked.append([48,84]);x.world.touch()
		elif mode in ["wall","door"]:
			x.checks.wall=_command(x,"build_wall",{"edges":[{"axis":"y","line":48,"low":84,"high":86}]}).accepted
			if mode=="door": x.checks.door=_command(x,"build_door",{"id":"boundary_door","definition_id":"DR01","cell":[48,84],"edge":"east"}).accepted
		elif mode=="facility": x.checks.obstacle=_facility(x,"obstacle","FUR09",[48,84])
		else:
			# A neighboring real desk's integer nurse post is exclusive even when
			# this small nurse's physical body does not overlap the first patient.
			x.checks.neighbor=_facility(x,"neighbor","SE01",[48,85])
			_staff(x,"guard","nurse",[59,90]);x.world.facts.actors.guard.species_id="S34"
			x.world.facts.staff.guard.base_prepared=true
			x.checks.neighbor_posts=_geometry_boundary(x,{x.peer.actor_id:[48.5,86],"guard":[48,84]})
			x.checks.actual_bodies_do_not_explain_reservation=not x.sim.space._actor_rect(x.world.facts.actors[x.head.actor_id],Vector2(47.5,84)).intersects(x.sim.space.body_rectangle(x.world.facts.actors.guard),false)
			x.checks.neighbor_reserved=x.sim.space.reserve_facility(x.world,"neighbor",x.peer.actor_id,x.peer.actor_id,["guard"]).is_empty()
		var before: Dictionary=x.world.freeze()
		var quote: Dictionary=x.sim.space.facility_quote(x.world,"guide",x.head.actor_id,["nurse"])
		var reason: String=x.sim.space.reserve_facility(x.world,"guide",x.head.actor_id,"floor_guide:head",["nurse"])
		x.checks.refused_live_preflight=not quote.get("ok",false) and not reason.is_empty()
		x.checks.failure_atomic=before==x.world.freeze() and not x.world.facts.adaptations.has("guide")
		rows.append(_finish(x,{"kind":"refusal","mode":mode,"quote":quote,"reason":reason}))
	return {"ok":rows.all(func(row:Dictionary)->bool:return row.ok),"kind":"refusals","cases":rows}

func _legacy_work() -> Dictionary:
	var x: Dictionary=_post_input()
	x.checks.gp=_room(x,"gp","gp",[34,66]) and _facility(x,"diagnosis","FUR02",[38,69],"gp")
	_staff(x,"doctor","doctor",[59,90],"gp")
	x.checks.original_legacy_positions=_geometry_boundary(x,{x.head.actor_id:[47,84],"nurse":[47,82]})
	var quote: Dictionary=x.sim.space.facility_geometry_quote(x.world,"guide",x.head.actor_id,["nurse"])
	if not quote.get("ok",false): x.checks.initial_quote=false;return _finish(x,{"kind":"legacy","quote":quote})
	# Legal saved-service boundary from the original integer representation.
	# No work has been supplied: all 60 remaining ticks execute below.
	quote.erase("ok");quote.patient_cell=[47,84];quote.regions[1]=[47,84,1,1];quote.owner_id="floor_guide:head"
	x.world.facts.adaptations["guide"]=quote
	x.world.facts.staff.nurse.active_job_id="floor_desk:guide"
	x.world.facts.floor_guidance.desks["guide"]={"id":"guide","nurse_id":"nurse","reason":"","queue":["head"],"queue_revision":1}
	x.world.facts.floor_guidance.next_arrival=1
	var ticket: Dictionary=x.world.facts.tickets[x.head.ticket_id]
	x.world.facts.floor_guidance.visits["head"]={"visit_id":"head","request_key":x.sim.services.floor_guidance._key(ticket),"ticket_id":ticket.id,"phase":"working","target_id":"","target_room_id":"","desk_id":"guide","guide_floor":1,"initial_done":false,"receipts":[],"guided_target":"","arrived_seq":-1,"reason":"","next_recheck":0,"nurse_id":"nurse","queue_seq":1,"queue_desk_id":"guide","queue_cell":[47,84],"queue_attending":true,"queue_arrived_tick":0,"remaining_ticks":60,"started_tick":0}
	x.world.facts.floor_guidance.visits.head.queue_bank_key=x.sim.services.floor_guidance._queue_bank_key(x.world,"guide")
	x.world.touch();x.sim.services.maintenance.ensure(x.world)
	x.checks.legacy_input_valid=x.world.validate(content).is_empty() and x.sim.services.floor_guidance.validate(x.world).is_empty()
	if not x.checks.legacy_input_valid: return _finish(x,{"kind":"legacy","guidance_validation":x.sim.services.floor_guidance.validate(x.world)})
	var original: Dictionary=x.world.facts.adaptations.guide.duplicate(true)
	var restored: Dictionary=_restore_operator(x)
	x.checks.legacy_cold_restore=restored.ok and original==x.world.facts.adaptations.guide
	x.checks.original_frozen_point_and_regions=true
	var work: int=0
	for index: int in 70:
		var before: Dictionary=x.sim.services.floor_guidance.state(x.world,"head").duplicate(true)
		_step(x)
		var current: Dictionary=x.sim.services.floor_guidance.state(x.world,"head")
		if before.phase=="working": work+=int(before.remaining_ticks)-int(current.get("remaining_ticks",0)) if current.phase=="working" else int(before.remaining_ticks)
		if current.phase=="working": x.checks.original_frozen_point_and_regions=x.checks.original_frozen_point_and_regions and x.world.facts.adaptations.guide==original and x.sim.space.at(x.world,x.head.actor_id,1,[47,84])
		if not current.receipts.is_empty(): break
	var final: Dictionary=x.sim.services.floor_guidance.state(x.world,"head")
	x.checks.legacy_real_sixty_ticks=work==60 and int(x.steps)==60 and final.receipts.size()==1
	# Work runs at the current tick before the step publishes tick+1. The
	# sixty real work steps are therefore labelled 0 through 59 inclusive.
	x.checks.original_receipt_step_timestamps=final.receipts.size()==1 and int(final.receipts[0].started_tick)==0 and int(final.receipts[0].completed_tick)==59 and int(x.world.sim_tick)==60
	return _finish(x,{"kind":"legacy","work_ticks":work,"restore":restored,"guidance":final.duplicate(true)})

func _two_real_patients(cold: bool) -> Dictionary:
	var x: Dictionary=_base()
	x.checks.layout=_facility(x,"guide","SE01",[47,83]) and _room(x,"gp","gp",[34,66]) and _facility(x,"diagnosis","FUR02",[38,69],"gp")
	_staff(x,"nurse","nurse",[55,90]);_staff(x,"doctor","doctor",[59,90],"gp")
	x.world.facts.staff.nurse.base_prepared=true
	var first: Dictionary=_patient(x,"first",[47.5,87],"gp","B_S13_D09_M09")
	var second: Dictionary=_patient(x,"second",[52,90],"gp","B_S13_D09_M09")
	x.sim.services.maintenance.ensure(x.world)
	var ids: Array=[first.id,second.id]
	var tickets: Dictionary={first.id:first.ticket_id,second.id:second.ticket_id}
	var work: Dictionary={first.id:0,second.id:0}
	var joined: Dictionary={}
	var completed: Array=[]
	var observed: Dictionary={"cold":cold,"restore":{},"patient_walk_steps":0,"nurse_walk_steps":0,"errors":[]}
	x.checks.complete_real_posts=true;x.checks.no_early_clinical_resources=true;x.checks.original_tickets=true;x.checks.full_bodies_clear=true
	for index: int in 1600:
		var prior: Dictionary={};var locations: Dictionary={}
		var nurse_before: Dictionary=x.world.facts.actors.nurse.location.duplicate(true)
		var frozen: Dictionary=x.sim.space.facility_layout(x.world,"guide")
		for id: String in ids:
			prior[id]=x.sim.services.floor_guidance.state(x.world,id).duplicate(true)
			locations[id]=x.world.facts.actors[x.world.facts.visits[id].actor_id].location.duplicate(true)
		_step(x)
		if x.world.facts.actors.nurse.location!=nurse_before: observed.nurse_walk_steps+=1
		var validation: String=x.world.validate(content)
		if not validation.is_empty(): observed.errors.append({"tick":x.world.sim_tick,"reason":validation});break
		for id: String in ids:
			var visit: Dictionary=x.world.facts.visits[id]
			var actor: Dictionary=x.world.facts.actors[visit.actor_id]
			var current: Dictionary=x.sim.services.floor_guidance.state(x.world,id)
			if actor.location!=locations[id]: observed.patient_walk_steps+=1
			if current.has("queue_seq") and not joined.has(id): joined[id]=int(current.queue_seq)
			var credited: int=0
			if prior[id].get("phase","")=="working": credited=int(prior[id].remaining_ticks)-int(current.get("remaining_ticks",0)) if current.get("phase","")=="working" else int(prior[id].remaining_ticks)
			elif current.get("phase","")=="working": credited=60-int(current.remaining_ticks);frozen=x.sim.space.facility_layout(x.world,"guide")
			if credited>0:
				work[id]+=credited
				x.checks.complete_real_posts=x.checks.complete_real_posts and credited==1 and x.sim.space.at(x.world,visit.actor_id,1,frozen.patient_cell) and x.sim.space.at(x.world,"nurse",1,frozen.operator_cells[0])
			if current.get("receipts",[]).is_empty():
				x.checks.original_tickets=x.checks.original_tickets and visit.ticket_id==tickets[id]
				x.checks.no_early_clinical_resources=x.checks.no_early_clinical_resources and visit.attempt_ids.is_empty() and not x.world.facts.preparations.has(id) and not x.world.facts.sessions.values().any(func(row:Dictionary)->bool:return row.get("visit_id","")==id) and not x.world.facts.ledger.entries.values().any(func(row:Dictionary)->bool:return row.owner_id==id)
			elif not id in completed: completed.append(id)
		var a: Dictionary=x.world.facts.actors[first.actor_id];var b: Dictionary=x.world.facts.actors[second.actor_id]
		if a.location.kind=="floor" and b.location.kind=="floor" and a.location.floor_id==b.location.floor_id: x.checks.full_bodies_clear=x.checks.full_bodies_clear and not x.sim.space.body_rectangle(a).intersects(x.sim.space.body_rectangle(b),false)
		if cold and observed.restore.is_empty() and x.sim.services.floor_guidance.state(x.world,first.id).get("phase","")=="working": observed.restore=_restore_operator(x)
		if completed.size()==2: break
	x.checks.two_actual_sixty_tick_services=completed.size()==2 and work[first.id]==60 and work[second.id]==60
	x.checks.actual_fifo=completed.size()==2 and joined.size()==2 and int(joined[completed[0]])<int(joined[completed[1]])
	x.checks.real_travel_before_work=int(observed.patient_walk_steps)>0 and int(observed.nurse_walk_steps)>0
	x.checks.valid_cold_continuation=not cold or observed.restore.get("ok",false)
	return _finish(x,{"kind":"two_real_patients","observed":observed,"work_ticks":work,"arrival_sequences":joined,"completion_order":completed,"ledger":x.world.facts.ledger.entries.duplicate(true)})
