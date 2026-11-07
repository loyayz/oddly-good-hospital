extends RefCounted

func _overlap(c: Dictionary) -> Array:
	var bodies: Array = []
	for id: String in c.world.facts.actors:
		var actor: Dictionary = c.world.facts.actors[id]
		if actor.location.kind=="floor": bodies.append({"id":id,"floor":actor.location.floor_id,"body":c.sim.space.body_rectangle(actor)})
	for i: int in bodies.size():
		for j: int in range(i+1,bodies.size()):
			if bodies[i].floor==bodies[j].floor and bodies[i].body.intersects(bodies[j].body,false): return [bodies[i].id,bodies[j].id]
	return []

func _clear_buffer(c: Dictionary, reservation: Dictionary) -> bool:
	var actor: Dictionary = c.world.facts.actors.clin_cover
	if actor.location.kind!="floor": return false
	for region: Array in reservation.regions:
		if c.sim.space.body_rectangle(actor).intersects(Rect2(region[0],region[1],region[2],region[3]).grow(1.0),false): return false
	return true

func _restore(c: Dictionary, content: HospitalContent) -> void:
	var facts: Dictionary = c.world.freeze()
	c.sim.dispose()
	c.world = WorldState.new(facts)
	c.sim = HospitalSimulation.new(c.world,content)
	c.sim.clinic.departments = null

func _run(t, fixture, mode: String) -> Dictionary:
	var c: Dictionary = fixture._copy("ward_after_care")
	var content: HospitalContent = fixture._content
	var w: WorldState = c.world
	var bed_id: String = str(w.facts.ward_stays.values()[0].bed_id)
	var reservation: Dictionary = w.facts.adaptations[bed_id].duplicate(true)
	var original_other: Dictionary = w.facts.actors.clin_or_nurse.duplicate(true)
	var original_schedule: Array = w.facts.staff.clin_cover.schedule.duplicate(true)
	var before: Dictionary = w.facts.actors.clin_cover.location.duplicate(true)
	var r: Dictionary = {"mode":mode,"initial_tick":w.sim_tick,"initial_validation":w.validate(content),"errors":[],"moved":false,"restored":false,"held_when_blocked":true}
	var blockers: Array = []
	if mode in ["old_parking","restored_parking","leave_wait_safe","late_target","queued_training","interrupted_base","repeated_exit"]:
		# Legal owner input from the old release selector, not a fabricated
		# finished movement. The actor must actually walk and clear the bed.
		r.cancelled_ground = c.sim.space.cancel_ground_move(w,"clin_cover")
		w.facts.staff.clin_cover.clinical_release = {"facility_id":bed_id,"visit_id":c.visit_id,"phase":"walking","reason":"","target_floor":1,"target_cell":[45,72]}
		r.request_reason = c.sim.space.request_move(w,"clin_cover",1,[45,72])
	if mode=="late_target":
		r.assign = c.sim.apply(GameCommand.new("ward-release-assign",w.hospital_id,w.revision,"clinical_assign_ward",BusinessPayload.new({"staff_id":"clin_or_nurse","ward_id":"clin_ward"}))).to_record()
	if mode=="queued_training":
		r.training = c.sim.apply(GameCommand.new("ward-release-course",w.hospital_id,w.revision,"train_staff",BusinessPayload.new({"staff_id":"clin_cover","track":"care","queue_without_desk":true}))).to_record()
		r.training_job = w.facts.staff.clin_cover.training_job_id
		if not str(r.training_job).is_empty(): r.training_remaining=w.facts.training_jobs[r.training_job].remaining_work_milli
	if mode=="interrupted_base":
		# Legal critical boundary: urgent care retained this unfinished base
		# preparation. Its remainder is not an active competing movement.
		w.facts.staff.clin_cover.base_prepared=false
		w.facts.staff.clin_cover.base_task={"phase":"working","facility_id":"clin_ward_2","remaining_ticks":23,"queue_tick":w.sim_tick-60}
	if mode=="leave_wait_safe":
		r.leave = c.sim.apply(GameCommand.new("ward-release-leave",w.hospital_id,w.revision,"plan_leave",BusinessPayload.new({"staff_id":"clin_cover","days":1,"start":"now"}))).to_record()
	if mode=="no_safe_parking":
		r.cancelled_ground = c.sim.space.cancel_ground_move(w,"clin_cover")
		var ward: Dictionary = w.facts.rooms.clin_ward
		var actor: Dictionary = w.facts.actors.clin_cover
		for y: int in range(int(ward.origin[1]),int(ward.origin[1])+int(ward.size[1])):
			for x: int in range(int(ward.origin[0]),int(ward.origin[0])+int(ward.size[0])):
				var body: Rect2 = c.sim.space._actor_rect(actor,Vector2(x,y))
				var clear: bool = c.sim.space.static_reason(w,actor,1,Vector2i(x,y)).is_empty() and c.sim.space._dynamic_clear(w,"clin_cover",1,body)
				for region: Array in reservation.regions: clear=clear and not body.intersects(Rect2(region[0],region[1],region[2],region[3]).grow(1.0),false)
				if clear: blockers.append([x,y])
		w.facts.floors.overrides["1"].blocked.append_array(blockers)
		w.facts.staff.clin_cover.clinical_release = {"facility_id":bed_id,"visit_id":c.visit_id,"phase":"seek","reason":"","ward":true}
		w.touch(); c.sim.space.finish_boundary(w)
		r.blockers = blockers.size()
		r.blocked_validation = w.validate(content)
	if mode=="repeated_exit":
		var held: Dictionary = w.facts.staff.clin_cover.clinical_release.duplicate(true)
		var move: Dictionary = w.facts.moves.get("clin_cover",{}).duplicate(true)
		c.sim.clinic._release_ward_operator(w,w.facts.ward_stays.values()[0],"clin_cover")
		c.sim.clinic._release_ward_operator(w,w.facts.ward_stays.values()[0],"clin_cover")
		r.same_target = w.facts.staff.clin_cover.clinical_release.get("target_cell",[])==held.get("target_cell",[])
		r.same_move = w.facts.moves.get("clin_cover",{})==move
	var release_seen: bool = w.facts.staff.clin_cover.has("clinical_release")
	var changed_target: bool = false
	for i: int in 400:
		if mode=="no_safe_parking" and i==20:
			for cell: Array in blockers: w.facts.floors.overrides["1"].blocked.erase(cell)
			w.touch();c.sim.space.finish_boundary(w)
		c.sim.step()
		r.moved = r.moved or w.facts.actors.clin_cover.location!=before
		var overlap: Array = _overlap(c)
		if not overlap.is_empty(): r.errors.append({"overlap":overlap,"tick":w.sim_tick});break
		var invalid: String = w.validate(content)
		if not invalid.is_empty(): r.errors.append({"validation":invalid,"tick":w.sim_tick});break
		var release: Dictionary = w.facts.staff.clin_cover.get("clinical_release",{})
		changed_target = changed_target or not release.is_empty() and release.get("target_cell",[45,72])!=[45,72]
		if mode=="no_safe_parking" and i<20: r.held_when_blocked=r.held_when_blocked and not release.is_empty() and not _clear_buffer(c,reservation)
		if mode=="restored_parking" and not r.restored and i==8:
			_restore(c,content);w=c.world;r.restored=true
		if release_seen and release.is_empty() and (mode=="leave_wait_safe" or not w.facts.moves.has("clin_cover")):
			r.completed = true;r.final_tick=w.sim_tick;r.clear_buffer=_clear_buffer(c,reservation);break
		if i%100==99: await t.process_frame
	r.final_location = w.facts.actors.clin_cover.location.duplicate(true)
	r.other_unchanged = w.facts.actors.clin_or_nurse==original_other
	r.schedule_unchanged = w.facts.staff.clin_cover.schedule==original_schedule
	r.changed_target = changed_target
	r.final_validation = w.validate(content)
	r.passed = r.initial_validation.is_empty() and r.errors.is_empty() and r.moved and r.get("completed",false) and r.get("clear_buffer",false) and r.schedule_unchanged and r.held_when_blocked and r.final_validation.is_empty()
	if not mode in ["leave_wait_safe","late_target","interrupted_base"]: r.passed=r.passed and r.other_unchanged
	if mode=="repeated_exit": r.passed=r.passed and r.same_target and r.same_move
	if mode=="restored_parking": r.passed=r.passed and r.restored
	if mode=="leave_wait_safe": r.passed=r.passed and r.leave.accepted
	if mode=="late_target": r.passed=r.passed and r.assign.accepted and changed_target
	if mode=="queued_training":
		r.training_preserved = not str(r.training_job).is_empty() and w.facts.staff.clin_cover.training_job_id==r.training_job and w.facts.training_jobs[r.training_job].remaining_work_milli==r.training_remaining
		r.passed=r.passed and r.training.accepted and r.training_preserved
	if mode=="interrupted_base":
		r.base_preserved=int(w.facts.staff.clin_cover.get("base_task",{}).get("remaining_ticks",-1))==23
		r.passed=r.passed and r.base_preserved
	if mode=="no_safe_parking": r.passed=r.passed and r.blockers>0 and r.blocked_validation.is_empty()
	c.sim.dispose()
	return r

func run_case(t, fixture) -> void:
	var results: Dictionary = {}
	var passed: bool = true
	for mode: String in ["normal","old_parking","restored_parking","leave_wait_safe","no_safe_parking","late_target","queued_training","interrupted_base","repeated_exit"]:
		results[mode] = await _run(t,fixture,mode)
		passed = passed and results[mode].passed
	t.check("CLIN-37",passed,results)
