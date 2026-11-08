extends "res://tests/acceptance/floor_guidance.gd"
func _overlap(x: Dictionary, actor_id: String) -> bool:
	var a: Dictionary=x.world.facts.actors[actor_id]
	if a.location.kind!="floor":return false
	var r: Rect2=x.space._actor_rect(a,Vector2(float(a.location.cell[0]),float(a.location.cell[1])))
	for id: String in x.world.facts.actors:
		if id==actor_id:continue
		var b: Dictionary=x.world.facts.actors[id]
		if b.location.kind!="floor" or b.location.floor_id!=a.location.floor_id:continue
		if r.intersects(x.space._actor_rect(b,Vector2(float(b.location.cell[0]),float(b.location.cell[1]))),false):return true
	return false
class RefuseCancel extends HospitalFloorGuidance:
	var refuse: bool=true
	func _cancel_own_move(world: WorldState, actor_id: String, current: Dictionary)->void:
		if refuse:return
		super._cancel_own_move(world,actor_id,current)
func run_prototype(content: HospitalContent) -> Dictionary:
	_content=content
	var cases: Array=[_crowded_approach(),_crowded_approach(true),_crowded_approach(false,true),_reflow_presence(),_failed_handoff(),_large_no_room_no_number(),_life_rejoin()]
	return {"passed":not cases.any(func(row: Dictionary)->bool:return not row.ok),"cases":cases}
func _crowded_approach(constrained: bool=false, large: bool=false) -> Dictionary:
	var x: Dictionary=_base();var visits: Array=[]
	var count: int=8 if constrained else 4
	if constrained:
		_facility(x,"guide","SE01",[47,70])
		HospitalFactory._add_room(x.world,{"id":"queue_wall","type":"gp","anchor":[46,78],"size":[10,12],"door":{"definition_id":"DR04","offset":3}},_content)
		x.world.touch()
	for i: int in count:visits.append(_visit(x,"crowd_"+str(i),[33+i*2,94]))
	if large:
		var big: Dictionary=visits[0]
		var actor: Dictionary=x.world.facts.actors[big.actor_id]
		actor.location.cell=[35,89]
		for i: int in range(1,visits.size()): x.world.facts.actors[visits[i].actor_id].location.cell=[40+i*2,94]
		for binding: Dictionary in _content.catalog.treatment_bindings:
			var probe: Dictionary=actor.duplicate(true)
			probe.species_id=binding.species_id;probe.body_binding_id=binding.id
			if x.space.clearance(probe)!=3 or float(x.space.body(probe).height_m)>6.5:continue
			actor.species_id=binding.species_id;actor.body_binding_id=binding.id
			big.binding_id=binding.id;big.disease_id=binding.disease_id;big.requested_plan_id="P_"+str(binding.disease_id)+"_COMMON"
			break
		x.world.touch()
	var admitted: Dictionary={};var completed: Dictionary={};var no_overlap: bool=true;var actual_queue: bool=true
	for tick: int in 1800:
		var before_cells: Dictionary={}
		for visit: Dictionary in visits:before_cells[visit.id]=x.world.facts.actors[visit.actor_id].location.cell.duplicate()
		_step(x)
		for visit: Dictionary in visits:
			var s: Dictionary=x.g.state(x.world,visit.id)
			no_overlap=no_overlap and not _overlap(x,visit.actor_id)
			if s.has("queue_seq") and not admitted.has(visit.id):
				admitted[visit.id]=int(s.queue_seq)
				actual_queue=actual_queue and Vector2(before_cells[visit.id][0],before_cells[visit.id][1]).distance_to(Vector2(s.queue_cell[0],s.queue_cell[1]))<0.001
			if not s.receipts.is_empty():completed[visit.id]=int(s.receipts[0].completed_tick)
		if completed.size()==count:break
	var fair: bool=admitted.size()==count and completed.size()==count
	for a: String in admitted:
		for b: String in admitted:
			if admitted[a]<admitted[b] and completed.has(a) and completed.has(b):fair=fair and completed[a]<completed[b]
	var result={"actors":x.world.facts.actors.duplicate(true),"moves":x.world.facts.moves.duplicate(true),"queue_states":x.world.facts.floor_guidance.visits.duplicate(true),"case":"mixed_body_arrivals" if large else "eight_full_queue_arrivals" if constrained else "four_real_arrivals","ok":fair and actual_queue and no_overlap and x.world.validate(_content).is_empty(),"admitted":admitted,"completed":completed,"arrival_order_preserved":fair,"actual_queue":actual_queue,"no_overlap":no_overlap,"validation":x.world.validate(_content)}
	_dispose(x);return result

func _large_approach() -> Dictionary:
	var x: Dictionary=_base()
	var visit: Dictionary=_visit(x,"large",[35,89])
	var actor: Dictionary=x.world.facts.actors[visit.actor_id]
	var chosen: bool=false
	for binding: Dictionary in _content.catalog.treatment_bindings:
		var probe: Dictionary=actor.duplicate(true)
		probe.species_id=binding.species_id;probe.body_binding_id=binding.id
		if x.space.clearance(probe)!=3 or float(x.space.body(probe).height_m)>6.5:continue
		actor.species_id=binding.species_id;actor.body_binding_id=binding.id
		visit.binding_id=binding.id;visit.disease_id=binding.disease_id;visit.requested_plan_id="P_"+str(binding.disease_id)+"_COMMON"
		chosen=true;break
	x.world.touch()
	var input_error: String=x.world.validate(_content)
	var no_overlap: bool=true;var ready: bool=false
	for tick: int in 1600:
		_step(x)
		no_overlap=no_overlap and not _overlap(x,visit.actor_id)
		if x.g.state(x.world,visit.id).phase=="ready":ready=true;break
	var result: Dictionary={"case":"large_body_actual_service","ok":chosen and input_error.is_empty() and ready and no_overlap and x.world.validate(_content).is_empty(),"chosen":chosen,"input_validation":input_error,"no_overlap":no_overlap,"ready":ready,"actor":actor.duplicate(true),"state":x.g.state(x.world,visit.id).duplicate(true),"validation":x.world.validate(_content)}
	_dispose(x);return result

func _make_large(x: Dictionary, visit: Dictionary) -> bool:
	var actor: Dictionary=x.world.facts.actors[visit.actor_id]
	for binding: Dictionary in _content.catalog.treatment_bindings:
		var probe: Dictionary=actor.duplicate(true);probe.species_id=binding.species_id;probe.body_binding_id=binding.id
		if x.space.clearance(probe)!=3 or float(x.space.body(probe).height_m)>6.5:continue
		actor.species_id=binding.species_id;actor.body_binding_id=binding.id
		visit.binding_id=binding.id;visit.disease_id=binding.disease_id;visit.requested_plan_id="P_"+str(binding.disease_id)+"_COMMON"
		x.world.touch();return true
	return false

func _reflow_presence() -> Dictionary:
	var x: Dictionary=_base()
	var a: Dictionary=_visit(x,"early",[49,86]);var b: Dictionary=_visit(x,"middle",[50,87]);var c: Dictionary=_visit(x,"late",[51,88])
	var admission: Dictionary=_admit_then_pause(x,a,[b,c])
	var restaffed: bool=_restaff_only(x)
	var ordinary: Array=[a,b,c]
	var before: Dictionary={};var after: Dictionary={};var stable: bool=true;var participating: bool=true
	for visit: Dictionary in ordinary:
		var row: Dictionary=x.g.state(x.world,visit.id)
		before[visit.id]={"number":row.get("queue_seq",-1),"held_cell":row.get("queue_cell",[]).duplicate(),"position":x.world.facts.actors[visit.actor_id].location.cell.duplicate(),"planned":x.g._queue_point(x.world,visit.actor_id,"guide",visit.id)}
	var big: Dictionary=_visit(x,"incoming_large",[35,89])
	var chosen: bool=_make_large(x,big)
	x.g.prepare(x.world,big,x.world.facts.tickets[big.ticket_id])
	for visit: Dictionary in ordinary:
		var row: Dictionary=x.g.state(x.world,visit.id)
		after[visit.id]={"number":row.get("queue_seq",-1),"held_cell":row.get("queue_cell",[]).duplicate(),"position":x.world.facts.actors[visit.actor_id].location.cell.duplicate(),"planned":x.g._queue_point(x.world,visit.actor_id,"guide",visit.id)}
		stable=stable and before[visit.id]==after[visit.id] and int(row.get("queue_seq",-1))>=0
		participating=participating and x.g._queue_participating(x.world,row)
	var remote_no_number: bool=not x.g.state(x.world,big.id).has("queue_seq")
	var early: Dictionary=x.g.state(x.world,a.id)
	var number: int=int(early.get("queue_seq",-1))
	x.g.pause_for_need(x.world,a)
	var pending_kept: bool=not x.g._queue_participating(x.world,early) and int(early.get("queue_seq",-2))==number
	var pending_layout_unchanged: bool=true
	for visit: Dictionary in ordinary:
		pending_layout_unchanged=pending_layout_unchanged and x.g._queue_point(x.world,visit.actor_id,"guide",visit.id)==before[visit.id].planned
	var result: Dictionary={"case":"remote_large_seek_does_not_reflow_three_actual_members","ok":admission.ok and restaffed and chosen and stable and participating and remote_no_number and pending_kept and pending_layout_unchanged and x.world.validate(_content).is_empty(),"real_admission":admission,"before":before,"after":after,"ordinary_positions_and_numbers_unchanged":stable,"ordinary_still_participating":participating,"remote_large_has_no_number":remote_no_number,"pending_departure_before_movement_does_not_lose_number":pending_kept,"pending_departure_does_not_shift_layout":pending_layout_unchanged,"validation":x.world.validate(_content)}
	_dispose(x);return result

func _failed_handoff() -> Dictionary:
	var x: Dictionary=_base()
	var a: Dictionary=_visit(x,"head",[49,86]);var middle: Dictionary=_visit(x,"middle",[50,87]);var b: Dictionary=_visit(x,"last",[51,88])
	var admission: Dictionary=_admit_then_pause(x,a,[middle,b])
	var restaffed: bool=_restaff_only(x)
	var initial: bool=admission.ok and restaffed and x.g.state(x.world,a.id).has("queue_seq") and x.g.state(x.world,middle.id).has("queue_seq") and x.g.state(x.world,b.id).has("queue_seq")
	# Two real departures, not a remote body's prospective size, change the
	# last patient's destination while its first queue-advance leg is underway.
	x.g.pause_for_need(x.world,a)
	var first_exit: String=x.space.request_move(x.world,a.actor_id,1,[44,85])
	for tick: int in 160:
		x.space.advance(x.world);x.world.facts.sim_tick+=1;x.world.touch(false)
		if not x.world.facts.moves.has(a.actor_id):break
	x.g._observe_queue_departure(x.world,x.g.state(x.world,a.id))
	x.g.prepare(x.world,middle,x.world.facts.tickets[middle.ticket_id])
	x.g.prepare(x.world,b,x.world.facts.tickets[b.ticket_id])
	x.space.advance(x.world);x.world.facts.sim_tick+=1;x.world.touch(false)
	var old_move: Dictionary=x.world.facts.moves.get(b.actor_id,{}).duplicate(true)
	var old_cell: Array=x.g.state(x.world,b.id).get("queue_cell",[]).duplicate()
	var original: HospitalFloorGuidance=x.g
	var replacement:=RefuseCancel.new(_content,x.space)
	replacement.clinic=x.c;replacement.waiting=x.l;x.g=replacement;x.c.floor_guidance=replacement;x.l.floor_guidance=replacement
	original.clinic=null;original.waiting=null
	x.g.pause_for_need(x.world,middle)
	var second_exit: String=x.space.request_move(x.world,middle.actor_id,1,[44,86])
	x.space.advance(x.world);x.world.facts.sim_tick+=1;x.world.touch(false)
	x.g._observe_queue_departure(x.world,x.g.state(x.world,middle.id))
	var new_point: Dictionary=x.g._queue_point(x.world,b.actor_id,"guide",b.id)
	var changed_by_actual_departure: bool=not x.g.state(x.world,middle.id).has("queue_seq") and not new_point.is_empty() and new_point.cell!=old_cell
	x.g.prepare(x.world,b,x.world.facts.tickets[b.ticket_id])
	var row: Dictionary=x.g.state(x.world,b.id)
	var preserved: bool=not old_move.is_empty() and row.queue_cell==old_cell and x.world.facts.moves.get(b.actor_id,{}).get("target_cell",[])==old_move.get("target_cell",[])
	for tick: int in 100:
		x.space.advance(x.world);x.world.facts.sim_tick+=1;x.world.touch(false)
		if not x.world.facts.moves.has(b.actor_id):break
	var participating: bool=x.g._queue_participating(x.world,row)
	replacement.refuse=false;x.g.prepare(x.world,b,x.world.facts.tickets[b.ticket_id])
	var retarget: Dictionary=x.world.facts.moves.get(b.actor_id,{})
	var accepted: bool=not retarget.is_empty() and retarget.target_cell==row.queue_cell and row.queue_cell!=old_cell
	var result: Dictionary={"case":"unsafe_retarget_refusal_keeps_actual_commitment","ok":initial and first_exit.is_empty() and second_exit.is_empty() and changed_by_actual_departure and preserved and participating and accepted and x.world.validate(_content).is_empty(),"real_initial_arrivals":initial,"two_real_departures_change_target":changed_by_actual_departure,"old_cell":old_cell,"new_point":new_point,"old_move_and_cell_preserved":preserved,"old_leg_completion_keeps_priority":participating,"later_safe_retarget_accepted":accepted,"validation":x.world.validate(_content)}
	_dispose(x);return result

func _large_no_room_no_number() -> Dictionary:
	var x: Dictionary=_base()
	# Fixture geometry exists before anyone joins: the floor boundary leaves
	# four ordinary slots plus two passage cells. No admitted person is moved,
	# no blocker is injected, and the actor count is unchanged.
	_facility(x,"guide","SE01",[47,89])
	x.world.touch()
	var a: Dictionary=_visit(x,"fit_a",[50,91]);var b: Dictionary=_visit(x,"fit_b",[50,92]);var c: Dictionary=_visit(x,"fit_c",[50,93])
	var followers: Array=[a,b,c]
	var starts: Dictionary={}
	for patient: Dictionary in followers: starts[patient.id]=x.world.facts.actors[patient.actor_id].location.duplicate(true)
	var gate: Dictionary=_visit(x,"fit_gate",[48,91])
	for tick: int in 600:
		x.g.dispatch(x.world);x.g.prepare(x.world,gate,x.world.facts.tickets[gate.ticket_id])
		x.space.advance(x.world);x.g.advance(x.world)
		x.world.facts.sim_tick+=1;x.world.touch(false)
		if x.g.state(x.world,gate.id).get("phase","")=="working":break
	var restaffed: bool=x.g._desk_usable(x.world,"guide")
	var all_queued: bool=false
	var overlap: bool=false
	var elapsed: int=0
	for tick: int in 60:
		_step(x);elapsed+=1;all_queued=true
		for patient: Dictionary in followers:
			var row: Dictionary=x.g.state(x.world,patient.id)
			all_queued=all_queued and row.has("queue_seq") and row.get("phase","")=="desk_queue" and x.space.at(x.world,patient.actor_id,1,row.get("queue_cell",[])) and not x.world.facts.moves.has(patient.actor_id) and row.receipts.is_empty() and starts[patient.id]!=x.world.facts.actors[patient.actor_id].location
			overlap=overlap or _overlap(x,patient.actor_id)
		if all_queued:break
	var states: Array=[]
	for patient: Dictionary in followers:states.append(x.g.state(x.world,patient.id).duplicate(true))
	var admission: Dictionary={"ok":all_queued and not overlap,"three_actually_queued":all_queued,"overlap":overlap,"elapsed":elapsed,"initial_locations":starts,"states":states,"gate":x.g.state(x.world,gate.id).duplicate(true)}
	var big: Dictionary=_visit(x,"too_large_now",[35,89]);var chosen: bool=_make_large(x,big)
	var point: Dictionary=x.g._queue_point(x.world,big.actor_id,"guide",big.id)
	x.g.prepare(x.world,big,x.world.facts.tickets[big.ticket_id])
	var state: Dictionary=x.g.state(x.world,big.id)
	var no_number: bool=point.is_empty() and not state.has("queue_seq") and state.receipts.is_empty()
	var result: Dictionary={"case":"mixed_tail_no_fit_grants_no_advance_number","ok":admission.ok and restaffed and chosen and no_number and x.world.validate(_content).is_empty(),"admission":admission,"tail_probe":point,"no_advance_number":no_number,"large_state":state.duplicate(true),"validation":x.world.validate(_content)}
	_dispose(x);return result

func _life_rejoin() -> Dictionary:
	# Reuse the real water-use event path, not a synthetic sequence edit.
	var suite: RefCounted=load("res://tests/acceptance/guidance_desk_participation.gd").new()
	var result: Dictionary=suite.run_participation(_content,["GUIDE-DESK-LIFE-LOCAL-PAUSE"])
	var row: Dictionary=result.cases[0]
	row.case="actual_need_departure_returns_to_new_tail_number"
	return row

func run_no_fit_only(content: HospitalContent) -> Dictionary:
	_content=content
	var row: Dictionary=_large_no_room_no_number()
	return {"passed":row.ok,"cases":[row]}
