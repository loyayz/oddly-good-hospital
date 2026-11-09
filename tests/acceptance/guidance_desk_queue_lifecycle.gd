extends "res://tests/acceptance/guidance_fixed_queue.gd"

# The helper-level cases intentionally construct queue facts. Only the separate
# real-arrival case below proves movement, arrival admission and service order.
func run_desk_queue_checks(content: HospitalContent, real_arrivals: bool=true) -> Dictionary:
	_content=content
	var cases: Array=[_array_lifecycle(),_packing_lifecycle(),_service_body_change("to_counter"),_service_body_change("working")]
	if real_arrivals: cases.append(_real_array_arrivals())
	return {"ok":cases.all(func(row: Dictionary)->bool:return bool(row.ok)),"cases":cases}

func _row(x: Dictionary, id: String, desk_id: String="guide") -> Dictionary:
	var visit: Dictionary=_visit(x,id,[33+x.world.facts.visits.size()*2,94])
	var row: Dictionary={"visit_id":visit.id,"request_key":"desk_queue_test:"+id,"ticket_id":visit.ticket_id,"phase":"desk_queue","desk_id":desk_id,"guide_floor":1,"queue_attending":true,"queue_seq":x.world.facts.visits.size(),"queue_bank_key":x.g._queue_bank_key(x.world,desk_id)}
	x.world.facts.floor_guidance.visits[id]=row
	return row

func _array_lifecycle() -> Dictionary:
	var x: Dictionary=_base()
	_facility(x,"other_guide","SE01",[65,83])
	x.world.touch()
	var checks: Dictionary={}
	var rows: Array=[]
	for id: String in ["a","b","c","d"]:
		var row: Dictionary=_row(x,id)
		rows.append(row)
		x.g._queue_join(x.world,row)
	var other: Dictionary=_row(x,"other","other_guide")
	x.g._queue_join(x.world,other)
	checks.initial_order=x.g._desk_queue(x.world,"guide")==["a","b","c","d"]
	for row: Dictionary in rows: x.g._queue_join(x.world,row)
	checks.same_tick_join_idempotent=x.g._desk_queue(x.world,"guide")==["a","b","c","d"]
	x.g._queue_leave(x.world,rows[1])
	x.g._queue_leave(x.world,rows[1])
	checks.middle_remove_idempotent=x.g._desk_queue(x.world,"guide")==["a","c","d"]
	x.g._queue_leave(x.world,rows[0])
	checks.head_remove=x.g._desk_queue(x.world,"guide")==["c","d"]
	x.g._queue_leave(x.world,rows[3])
	checks.tail_remove=x.g._desk_queue(x.world,"guide")==["c"]
	x.g._queue_join(x.world,rows[1])
	checks.rejoin_at_tail=x.g._desk_queue(x.world,"guide")==["c","b"]
	x.g._change_desk(x.world,x.world.facts.visits.c,rows[2],"other_guide")
	checks.change_desk_removes_old_not_advance_add=x.g._desk_queue(x.world,"guide")==["b"] and x.g._desk_queue(x.world,"other_guide")==["other"]
	x.g._queue_join(x.world,rows[2])
	checks.new_desk_append=x.g._desk_queue(x.world,"other_guide")==["other","c"]
	x.g.release(x.world,"b")
	x.g.release(x.world,"b")
	checks.release_idempotent=x.g._desk_queue(x.world,"guide").is_empty() and not x.world.facts.floor_guidance.visits.has("b")
	checks.other_desk_unchanged=x.g._desk_queue(x.world,"other_guide")==["other","c"]
	var result: Dictionary={"case":"desk_array_helper_lifecycle","ok":checks.values().all(func(value: Variant)->bool:return value==true),"checks":checks,"scope":"helper-level synthetic queue facts, not real movement"}
	_dispose(x)
	return result

func _packing_lifecycle() -> Dictionary:
	var x: Dictionary=_base()
	var visit: Dictionary=_visit(x,"cache_probe",[33,94])
	var first: Dictionary=x.g._queue_point(x.world,visit.actor_id,"guide",visit.id)
	var checks: Dictionary={"initial_point":not first.is_empty(),"desk_cache_exists":x.g._queue_batches.has("guide")}
	var before: Dictionary=x.g._queue_batches.get("guide",{})
	var stable: bool=not before.is_empty()
	for tick: int in 5:
		x.world.facts.sim_tick+=1
		x.world.touch(false)
		x.g.dispatch(x.world)
		var point: Dictionary=x.g._queue_point(x.world,visit.actor_id,"guide",visit.id)
		stable=stable and point==first and is_same(before,x.g._queue_batches.get("guide",{}))
	checks.unrelated_ticks_reuse_same_packing=stable
	# Ceiling change is a real structural source change, not a world tick.
	x.world.facts.floors.height_intervals=[{"first":1,"last":1,"height_m":6.0}]
	x.world.touch()
	x.g._queue_point(x.world,visit.actor_id,"guide",visit.id)
	checks.geometry_replaces_packing=x.g._queue_batches.has("guide") and not is_same(before,x.g._queue_batches.guide)
	var result: Dictionary={"case":"desk_array_packing_lifecycle","ok":checks.values().all(func(value: Variant)->bool:return value==true),"checks":checks,"scope":"packing identity and structural invalidation; not movement proof"}
	_dispose(x)
	return result

func _real_array_arrivals() -> Dictionary:
	var x: Dictionary=_base()
	var visits: Array=[]
	for i: int in 3: visits.append(_visit(x,"real_queue_"+str(i),[33+i*2,94]))
	var admitted: Dictionary={}
	var completed: Dictionary={}
	var actual: bool=true
	var arrays: bool=true
	var no_overlap: bool=true
	for tick: int in 1800:
		var before_cells: Dictionary={}
		for visit: Dictionary in visits: before_cells[visit.id]=x.world.facts.actors[visit.actor_id].location.cell.duplicate()
		_step(x)
		for visit: Dictionary in visits:
			var row: Dictionary=x.g.state(x.world,visit.id)
			no_overlap=no_overlap and not _overlap(x,visit.actor_id)
			if row.has("queue_seq") and not admitted.has(visit.id):
				admitted[visit.id]=int(row.queue_seq)
				actual=actual and Vector2(before_cells[visit.id][0],before_cells[visit.id][1]).distance_to(Vector2(row.queue_cell[0],row.queue_cell[1]))<0.001
				var queue: Array=x.g._desk_queue(x.world,"guide")
				arrays=arrays and queue.count(visit.id)==1
				var saved: Array=queue.duplicate()
				x.g._queue_join(x.world,row)
				arrays=arrays and x.g._desk_queue(x.world,"guide")==saved
			if not row.get("receipts",[]).is_empty(): completed[visit.id]=int(row.receipts[0].completed_tick)
		if completed.size()==visits.size(): break
	var fifo: bool=admitted.size()==visits.size() and completed.size()==visits.size()
	for a: String in admitted:
		for b: String in admitted:
			if admitted[a]<admitted[b] and completed.has(a) and completed.has(b): fifo=fifo and completed[a]<completed[b]
	var result: Dictionary={"case":"desk_array_real_arrival_fifo","ok":fifo and actual and arrays and no_overlap,"real_arrival":actual,"array_unique_and_join_idempotent":arrays,"no_overlap":no_overlap,"fifo":fifo,"admitted":admitted,"completed":completed,"remaining_queue":x.g._desk_queue(x.world,"guide").duplicate()}
	_dispose(x)
	return result

func _service_body_change(phase: String) -> Dictionary:
	var x: Dictionary=_base()
	var row: Dictionary=_row(x,"held")
	row.phase=phase
	x.g._queue_join(x.world,row)
	var incoming: Dictionary=_visit(x,"incoming",[40,94])
	x.g._queue_point(x.world,incoming.actor_id,"guide",incoming.id)
	var previous: Dictionary=x.g._queue_batches.guide
	var actor: Dictionary=x.world.facts.actors[x.world.facts.visits.held.actor_id]
	var old_span: int=x.space.clearance(actor)
	var changed: bool=false
	for binding: Dictionary in _content.catalog.treatment_bindings:
		var probe: Dictionary=actor.duplicate(true)
		probe.species_id=binding.species_id;probe.body_binding_id=binding.id
		if x.space.clearance(probe)!=3 or float(x.space.body(probe).height_m)>6.5:continue
		actor.species_id=binding.species_id;actor.body_binding_id=binding.id
		changed=true
		break
	# No callback/query of the changed member and no geometry revision bump.
	# Another patient's entry query must nevertheless reject the old packing.
	var actual: Dictionary=x.g._queue_point(x.world,incoming.actor_id,"guide")
	var rebuilt: Dictionary=x.g._queue_batches.guide
	var checks: Dictionary={"fixture_body_changed":changed and old_span!=x.space.clearance(actor),"changed_member_phase_unchanged":row.phase==phase,"other_patient_query_invalidates":not is_same(previous,rebuilt),"actual_new_span":rebuilt.packing.spans==[3],"queue_order_unchanged":x.g._desk_queue(x.world,"guide")==["held"]}
	x.g._queue_batches.clear()
	checks.matches_fresh_rebuild=actual==x.g._queue_point(x.world,incoming.actor_id,"guide")
	var result: Dictionary={"case":"desk_body_change_"+phase,"checks":checks,"ok":checks.values().all(func(value: Variant)->bool:return value==true),"scope":"shape invalidation boundary, not simulated service completion"}
	_dispose(x)
	return result
