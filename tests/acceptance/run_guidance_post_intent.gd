extends SceneTree

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=1:push_error("Output JSON required");quit(2);return
	var suite: RefCounted=load("res://tests/acceptance/floor_guidance.gd").new();suite._content=HospitalContent.new()
	var started: int=Time.get_ticks_msec()
	var x: Dictionary=suite._base()
	# Reuse the real nurse arrival as preparation. The declared boundary then
	# contains a lawful arrived queue head, two fixed people and one passer.
	for tick: int in 200:
		suite._step(x)
		if x.g._desk_usable(x.world,"guide"):break
	var layout: Dictionary=x.space.facility_layout(x.world,"guide")
	var head: Dictionary=suite._visit(x,"head",layout.patient_cell)
	var point: Dictionary=x.g._queue_point(x.world,head.actor_id,"guide",head.id)
	x.world.facts.actors[head.actor_id].location.cell=point.cell.duplicate()
	for item: Array in [["passer",[float(point.cell[0])-0.6,point.cell[1]]],["lower_guard",[float(point.cell[0])-0.6,float(point.cell[1])+1.0]],["back_guard",[float(point.cell[0])-1.5,point.cell[1]]]]:
		var actor: Dictionary=x.world.facts.actors[head.actor_id].duplicate(true)
		actor.id=item[0];actor.name=item[0];actor.location.cell=item[1]
		x.world.facts.actors[str(item[0])]=actor
	x.world.touch()
	var goal: Array=[float(point.cell[0])+2.5,point.cell[1]]
	var request: String=x.space.request_move(x.world,"passer",1,goal)
	x.g.prepare(x.world,head,x.world.facts.tickets[head.ticket_id])
	var quote: Dictionary=x.space.facility_quote(x.world,"guide",head.actor_id,["guide_nurse"])
	var geometry: Dictionary=x.space.facility_geometry_quote(x.world,"guide",head.actor_id,["guide_nurse"])
	var input: Dictionary=x.world.freeze()
	var validation: String=x.world.validate(suite._content)
	var initial_ok: bool=request.is_empty() and validation.is_empty() and geometry.get("ok",false) and not quote.get("ok",false) and x.g.state(x.world,"head").get("queue_seq",0)>0
	var bad: Dictionary=input.duplicate(true)
	bad.floor_guidance.visits.head.phase="working"
	bad.floor_guidance.visits.head.remaining_ticks=60
	bad.floor_guidance.visits.head.started_tick=int(input.sim_tick)
	var working_guard: String=WorldState.new(bad).validate(suite._content)
	var cold_setup: Dictionary=_cold(suite,input)
	var prepared: int=Time.get_ticks_msec()
	var warm: Dictionary=_walk(suite,x,goal)
	suite._dispose(x)
	var cold: Dictionary={"ok":false,"error":cold_setup.get("error","")}
	if cold_setup.get("ok",false):
		cold=_walk(suite,cold_setup.x,goal)
		suite._dispose(cold_setup.x)
	var result: Dictionary={"case":"GUIDE-POST-INTENT","ok":initial_ok and warm.ok and cold.ok and cold_setup.get("exact",false) and not working_guard.is_empty(),"fixture_source":"floor_guidance._base real nurse arrival; lawful queue-head boundary before post movement; actual passer request","setup_ms":prepared-started,"initial_validation":validation,"working_without_reservation_rejected":working_guard,"initial_quote":quote,"geometry":geometry,"initial_intent":input.floor_guidance.visits.head,"warm":warm,"cold":cold,"json_exact":cold_setup.get("exact",false)}
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify({"ok":result.ok,"warm":warm.get("checks",{}),"cold":cold.get("checks",{})}))
	quit(0 if result.ok else 1)

func _walk(suite: RefCounted, x: Dictionary, goal: Array) -> Dictionary:
	var started: int=Time.get_ticks_msec()
	var initial: Dictionary=x.world.freeze()
	var head_id: String=str(initial.visits.head.actor_id)
	var ids: Array=[head_id,"passer","guide_nurse","lower_guard","back_guard"]
	var ticket: String=str(initial.visits.head.ticket_id)
	var queue: int=int(initial.floor_guidance.visits.head.queue_seq)
	var sequence: int=int(initial.moves.passer.request_sequence)
	var errors: Array=[]
	var work: int=0
	var real_work: bool=true
	var original: bool=true
	var fixed: bool=true
	var trace: Array=[]
	var steps: int=0
	for tick: int in 300:
		var before: Dictionary={}
		for id: String in ids:before[id]=x.space.body_rectangle(x.world.facts.actors[id])
		var prior: Dictionary=x.g.state(x.world,"head").duplicate(true)
		suite._step(x);steps+=1
		var error: String=x.world.validate(suite._content)
		if not error.is_empty():errors.append(error);break
		for i: int in ids.size():
			var id: String=ids[i]
			var actor: Dictionary=x.world.facts.actors[id]
			var after: Rect2=x.space.body_rectangle(actor)
			if before[id].get_center().distance_to(after.get_center())>x.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001:errors.append("Walking budget: "+id)
			for j: int in range(i+1,ids.size()):
				var other: String=ids[j]
				var end: Rect2=x.space.body_rectangle(x.world.facts.actors[other])
				if after.intersects(end,false) or BodySweep.intersects(before[id],after,before[other],end):errors.append("Body/sweep: "+id+"/"+other)
		var state: Dictionary=x.g.state(x.world,"head")
		var move: Dictionary=x.world.facts.moves.get("passer",{})
		original=original and x.world.facts.visits.head.ticket_id==ticket and (move.is_empty() or move.target_cell==goal and int(move.request_sequence)==sequence)
		for id: String in ["lower_guard","back_guard"]:fixed=fixed and x.world.facts.actors[id]==initial.actors[id] and not x.world.facts.moves.has(id)
		var completed: bool=state.receipts.size()>0
		var remaining: int=int(state.get("remaining_ticks",0)) if not completed else 0
		var worked: int=int(prior.get("remaining_ticks",60))-remaining if prior.phase=="working" or state.phase=="working" or completed else 0
		if worked>0:
			work+=worked
			var layout: Dictionary=x.space.facility_layout(x.world,"guide")
			real_work=real_work and x.space.at(x.world,head_id,1,layout.patient_cell) and x.space.at(x.world,"guide_nurse",1,layout.operator_cells[0]) and not x.world.facts.moves.has(head_id)
			if not completed:real_work=real_work and x.world.facts.adaptations.get("guide",{}).get("owner_id","")=="floor_guide:head" and x.g.owns_reservation(x.world,x.world.facts.adaptations.guide)
		if not completed:original=original and int(state.get("queue_seq",-1))==queue
		if tick<12 or tick%20==0 or completed:trace.append({"tick":tick,"phase":state.phase,"head":x.world.facts.actors[head_id].location.cell.duplicate(),"passer":x.world.facts.actors.passer.location.cell.duplicate(),"remaining":remaining,"reason":x.world.facts.visits.head.waiting_reason})
		if not errors.is_empty() or completed:break
	var state: Dictionary=x.g.state(x.world,"head")
	var completed: bool=state.receipts.size()==1
	var span: int=int(state.receipts[0].completed_tick)-int(state.receipts[0].started_tick)+1 if completed else 0
	var checks: Dictionary={"actual_guidance_complete":completed,"full_six_second_work":work==60 and span==60 and real_work,"passer_actual_destination":x.space.at(x.world,"passer",1,goal) and not x.world.facts.moves.has("passer"),"body_sweep_budget_and_world_safe":errors.is_empty(),"ticket_queue_and_original_passer_request":original,"fixed_bodies_kept":fixed,"no_clinical_resource_held":x.world.facts.sessions.is_empty() and x.world.facts.attempts.is_empty() and not x.world.facts.adaptations.has("diagnosis")}
	return {"ok":checks.values().all(func(value: Variant)->bool:return value==true),"checks":checks,"steps":steps,"body_ms":Time.get_ticks_msec()-started,"work_ticks":work,"receipt_span_ticks":span,"receipts":state.receipts.duplicate(true),"errors":errors,"trace":trace}

func _cold(suite: RefCounted, facts: Dictionary) -> Dictionary:
	var encoder:=HospitalJsonStream.new();var path: String="user://guidance-post-intent.json"
	if not encoder.encode(path,facts,func(_bytes: int)->bool:return true):return {"ok":false,"error":encoder.error}
	var decoder:=HospitalJsonStream.new()
	var result: Dictionary=decoder.decode(path,encoder.bytes,encoder.digest,func(_bytes: int)->bool:return true)
	if not result.ok:return {"ok":false,"error":decoder.error}
	var world:=WorldState.new(result.value)
	var exact: bool=world.freeze()==facts and world.validate(suite._content).is_empty()
	return {"ok":exact,"exact":exact,"x":suite._guide_bind(world)}
