extends "res://tests/acceptance/waiting_adoption.gd"

func run_followups(database: HospitalContent, selected: Array = []) -> Dictionary:
	_content = database
	var rows: Array = []
	if selected.is_empty() or "A13" in selected:
		for phase: String in ["seat_walk","seated","seek","using","returning","fallback","using_json","returning_json","abandon"]: rows.append(_departure(phase))
	if selected.is_empty() or "A23" in selected:
		for manual: bool in [false,true]: rows.append(_seat_race(manual))
	if selected.is_empty() or "A36" in selected:
		for data: Array in [["S07","light","FUR19"],["S02","moist","FUR17"],["S03","quiet",""]]:
			var row: Dictionary = _live_preference(data[0],data[1],data[2])
			row.ok = row.validation.is_empty() and row.preferred and row.actual_seated and row.after[data[1]]
			rows.append(row)
		var friend: Dictionary = _friend()
		friend.ok = friend.validation.is_empty() and friend.before.conditions.friendly_neighbor and not friend.during.conditions.friendly_neighbor and friend.friend_actually_arrived and friend.subject_actually_seated
		rows.append(friend)
		rows.append(_preference_boundaries())
		rows.append(_worker_preference_boundaries())
	if selected.is_empty() or "A38" in selected:
		var standing: Dictionary = _standing_target()
		standing.ok = standing.get("validation","invalid").is_empty() and standing.get("occupant_actually_arrived",false) and standing.get("alternate_goal_seen",false) and not standing.get("overlap",true)
		rows.append(standing)
		rows.append(_safety_target_race(false))
		rows.append(_safety_target_race(true))
		rows.append(_safety_same_goal_takeover())
	return {"ok":not rows.is_empty() and rows.all(func(row: Dictionary)->bool:return row.ok),"cases":rows}

func _departure(variant: String) -> Dictionary:
	var x: Dictionary = _areas()
	var phase: String = variant.trim_suffix("_json")
	if phase!="fallback": _facility(x,"toilet","FUR07",[39,68],"west")
	var v: Dictionary = _visit(x,"depart_subject",[38,73])
	x.world.touch()
	var valid: String = x.world.validate(_content)
	var reached: bool = false
	if phase in ["seat_walk","seated","abandon"]:
		x.world.facts.sim_tick = 650 if phase=="abandon" else 50
		x.l.dispatch(x.world)
		if phase=="seated": reached = _until_seated(x,v)
		else:
			_tick_waiting(x,5)
			reached = x.world.facts.moves.has(v.actor_id)
	else:
		x.world.facts.sim_tick = 1800
		x.l._begin_need(x.world,v)
		if phase=="seek": reached = x.world.facts.waiting_life.needs.has(v.id)
		else:
			for tick: int in 650:
				if x.world.facts.waiting_life.needs.get(v.id,{}).get("phase","")==phase: reached = true;break
				_tick_waiting(x)
	if variant.ends_with("_json"):
		x = _json_restore(x)
		v = x.world.facts.visits.depart_subject
	var ticket: String = v.ticket_id
	x.a.clinic = x.c
	x.a.advance_wait(x.world)
	var before: Dictionary = x.world.freeze()
	var result: CommandResult
	if phase=="abandon":
		v.anger = 100.0
		x.a.needs(x.world)
		result = CommandResult.new(v.final_result=="abandoned","test_observed","",[],x.world.revision)
	else: result = x.c.execute(x.world,"clinical_refer",{"visit_id":v.id})
	var protected: bool = phase in ["using","returning","fallback"]
	var atomic: bool = (not result.accepted and x.world.freeze()==before) if protected else (result.accepted and not x.world.facts.tickets.has(ticket) and not x.world.facts.waiting_life.seats.has(v.id) and not x.world.facts.waiting_life.needs.has(v.id))
	var departure: Dictionary = x.world.facts.wait_departures.get(v.actor_id,{}).duplicate(true)
	var record_ok: bool = departure.get("selected",false) if phase=="abandon" else not departure.is_empty() if protected else departure.is_empty()
	var same_step_valid: String = x.world.validate(_content)
	var returned: bool = not protected
	if protected:
		for tick: int in 650:
			_tick_waiting(x)
			if not x.world.facts.waiting_life.needs.has(v.id): returned = true;break
	var ticket_preserved: bool = not protected or x.world.facts.tickets.has(ticket) and v.ticket_id==ticket and not x.world.facts.tickets[ticket].pause_reasons.has("need_service")
	var retry: bool = not protected or returned and x.c.execute(x.world,"clinical_refer",{"visit_id":v.id}).accepted
	for tick: int in 800:
		x.l.dispatch(x.world);x.c.dispatch(x.world);x.space.advance(x.world);x.l.advance(x.world);x.c.advance(x.world)
		x.world.facts.sim_tick += 1;x.world.touch(false);x.space.finish_boundary(x.world)
		if v.phase=="departed": break
	var final_valid: String = x.world.validate(_content)
	return {"case":"A13_"+variant,"ok":valid.is_empty() and reached and atomic and record_ok and same_step_valid.is_empty() and returned and ticket_preserved and retry and v.phase=="departed" and final_valid.is_empty(),"input_validation":valid,"reached_real_phase":reached,"command":result.to_record(),"atomic_boundary":atomic,"departure_record":departure,"same_step_validation":same_step_valid,"completed_real_return":returned,"original_ticket_retained":ticket_preserved,"retry_accepted":retry,"final_phase":v.phase,"final_validation":final_valid}

func _seat_race(manual: bool) -> Dictionary:
	var x: Dictionary = _areas()
	var far: Dictionary = _visit(x,"earlier_far",[42,76])
	var near: Dictionary = _visit(x,"later_near",[37,71])
	var valid: String = x.world.validate(_content)
	if manual:
		x.l.execute(x.world,"waiting_select_seat",{"visit_id":far.id,"facility_id":"west_chair"})
		_tick_waiting(x)
		x.l.execute(x.world,"waiting_select_seat",{"visit_id":near.id,"facility_id":"west_chair"})
	else:
		x.world.facts.sim_tick = 50;x.l.dispatch(x.world)
	var no_preclaim: bool = x.world.facts.adaptations.is_empty()
	var winner: bool = false
	for tick: int in 300:
		_tick_waiting(x)
		if HospitalWaitingLife.is_seated(x.world,near.id): winner = true;break
		if HospitalWaitingLife.is_seated(x.world,far.id): break
	var old_move: Dictionary = x.world.facts.moves.get(far.actor_id,{}).duplicate(true)
	_tick_waiting(x)
	var new_move: Dictionary = x.world.facts.moves.get(far.actor_id,{}).duplicate(true)
	var released: bool = not old_move.is_empty() and new_move.is_empty() and x.world.facts.waiting_life.seats[far.id].facility_id.is_empty()
	var fixed: bool = not old_move.is_empty() and not new_move.is_empty() and new_move.target_cell==old_move.target_cell
	# Winner leaves through the ordinary referral/real movement path; loser can
	# later take the chair without inheriting an independent reservation queue.
	var referral: CommandResult = x.c.execute(x.world,"clinical_refer",{"visit_id":near.id})
	var seated: bool = false
	for tick: int in 800:
		x.c.dispatch(x.world);_tick_waiting(x);x.c.advance(x.world);x.space.finish_boundary(x.world)
		if HospitalWaitingLife.is_seated(x.world,far.id): seated = true;break
	return {"case":"A23_"+("manual" if manual else "automatic"),"ok":valid.is_empty() and no_preclaim and winner and (fixed if manual else released) and referral.accepted and seated and x.world.validate(_content).is_empty(),"input_validation":valid,"no_preclaim":no_preclaim,"near_really_won":winner,"automatic_released_next_boundary":released,"manual_target_preserved":fixed,"later_actually_seated":seated,"final_validation":x.world.validate(_content)}

func _preference_boundaries() -> Dictionary:
	var x: Dictionary = _areas()
	var v: Dictionary = _visit(x,"environment_subject",[40,74])
	_facility(x,"a_dry","FUR21",[38,68],"west")
	_facility(x,"b_moist","FUR20",[38,70],"west")
	_facility(x,"cool","FUR22",[39,70],"west")
	_facility(x,"lamp","FUR19",[39,69],"west")
	x.world.touch()
	var valid: String = x.world.validate(_content)
	var point: Array = x.space.facility_layout(x.world,"west_chair").patient_cell
	var tied: Dictionary = x.e.environment_at(x.world,1,point,v.actor_id)
	var near: Dictionary = x.e.environment_at(x.world,1,[38,71],v.actor_id)
	x.world.facts.facilities.a_dry.failed = true
	x.world.facts.facilities.lamp.failed = true
	x.world.touch(false)
	var failed: Dictionary = x.e.environment_at(x.world,1,point,v.actor_id)
	var remote: Dictionary = x.e.environment_at(x.world,1,[50,75],v.actor_id)
	var seats: Dictionary = {}
	var seat_checks: bool = true
	for record: Array in [["FUR12","shade","light"],["FUR13","moist","dry"],["FUR14","dry","moist"],["FUR15","cool",""]]:
		var y: Dictionary = _areas()
		var subject: Dictionary = _visit(y,"seat_subject",[40,74])
		var chair: Dictionary = y.world.facts.facilities.west_chair
		chair.definition_id = record[0]
		var values: Dictionary = {"light":true,"moist":true,"dry":true}
		var expected: Dictionary = {}
		for preference: String in [record[1],record[2]]:
			if preference.is_empty(): continue
			var chosen: String = ""
			for species: Dictionary in _content.catalog.species:
				if species.get("preferences",[])==[preference]: chosen = species.id;break
			_species(y,subject,chosen)
			expected[preference] = y.l._preferred(y.world,subject,chair,values)
		seat_checks = seat_checks and expected.get(record[1],false) and not expected.get(record[2],false)
		seats[record[0]] = expected
	return {"case":"A36_environment_boundaries","ok":valid.is_empty() and tied.dry and not tied.moist and tied.cool and tied.light and near.moist and not near.dry and failed.moist and not failed.dry and not failed.light and not remote.moist and not remote.dry and not remote.cool and not remote.light and seat_checks,"validation":valid,"equal_distance_id_tie":tied,"nearest_source":near,"failed_sources":failed,"outside_range_and_room":remote,"seat_local_overrides":seats}

func _species(x: Dictionary,v: Dictionary,species: String) -> void:
	for binding: Dictionary in _content.catalog.treatment_bindings:
		if binding.species_id!=species: continue
		var a: Dictionary=x.world.facts.actors[v.actor_id]
		a.species_id=species;a.body_binding_id=binding.id
		v.binding_id=binding.id;v.disease_id=binding.disease_id;v.requested_plan_id="P_"+binding.disease_id+"_COMMON"
		x.space.sync_actor(x.world,a.id)
		return

func _live_preference(species: String,preference: String,source: String) -> Dictionary:
	var x: Dictionary=_areas()
	var v: Dictionary=_visit(x,"subject",[40,74])
	_species(x,v,species)
	var chair: Dictionary=x.world.facts.facilities.west_chair
	var cell: Array=x.space.facility_layout(x.world,"west_chair").patient_cell
	var before: Dictionary=x.e.environment_at(x.world,1,cell,v.actor_id)
	if not source.is_empty(): _facility(x,"live_source",source,[38,68],"west");x.world.touch()
	var after: Dictionary=x.e.environment_at(x.world,1,cell,v.actor_id)
	var preferred: bool=x.l._preferred(x.world,v,chair,after)
	var quote: Dictionary=x.l._seat_quote(x.world,v,"west_chair")
	var validation: String=x.world.validate(_content)
	var request: CommandResult=x.l.execute(x.world,"waiting_select_seat",{"visit_id":v.id,"facility_id":"west_chair"})
	var seated: bool=_until_seated(x,v,500) if request.accepted else false
	return {"case":"A36_live_"+preference,"validation":validation,"source":source,"before":before,"after":after,"preferred":preferred,"quote":quote,"request":request.to_record(),"actual_seated":seated,"mapping_missing":not preferred and (float(after.value)>float(before.value) if not source.is_empty() else after.noise==0)}

func _friend() -> Dictionary:
	var x: Dictionary=_areas()
	var v: Dictionary=_visit(x,"social",[40,74])
	var friend: Dictionary=_visit(x,"friend",[38,70])
	var pair: Array=[v.actor_id,friend.actor_id];pair.sort()
	x.world.facts.get_or_add("relationships",{})[":".join(pair)]={"kind":"friend"}
	x.world.touch(false)
	var before: Dictionary=x.l._seat_quote(x.world,v,"west_chair")
	var reason: String=x.space.request_move(x.world,friend.actor_id,1,[41,75])
	var during: Dictionary=x.l._seat_quote(x.world,v,"west_chair")
	for tick: int in 200:
		x.world.facts.sim_tick+=1;x.space.advance(x.world);x.world.touch(false)
		if not x.world.facts.moves.has(friend.actor_id): break
	var friend_arrived: bool=x.space.at(x.world,friend.actor_id,1,[41,75])
	var after: Dictionary=x.l._seat_quote(x.world,v,"west_chair")
	var request: CommandResult=x.l.execute(x.world,"waiting_select_seat",{"visit_id":v.id,"facility_id":"west_chair"})
	var seated: bool=_until_seated(x,v,500) if request.accepted else false
	return {"case":"A36_live_friend","validation":x.world.validate(_content),"request_move":reason,"before":before,"during":during,"after":after,"friend_actually_arrived":friend_arrived,"subject_actually_seated":seated}

func _standing_target() -> Dictionary:
	var x: Dictionary=_areas()
	var v: Dictionary=_visit(x,"standing",[38,94])
	x.world.facts.sim_tick=50;x.l.dispatch(x.world)
	var initial: Dictionary=x.world.facts.moves.get(v.actor_id,{}).duplicate(true)
	if initial.is_empty(): return {"case":"A38_stolen_standing_goal","harness_error":"no automatic entry walk"}
	var goal: Array=initial.target_cell
	var occupant: Dictionary=_visit(x,"occupant",[float(goal[0])+2,float(goal[1])])
	x.world.touch(false);x.space.sync_actor(x.world,occupant.actor_id)
	var take: String=x.space.request_move(x.world,occupant.actor_id,1,goal)
	var arrived: bool=false
	var validation: String=x.world.validate(_content)
	for tick: int in 100:
		x.world.facts.sim_tick+=1;x.space.advance(x.world);x.world.touch(false)
		if x.space.at(x.world,occupant.actor_id,1,goal) and not x.world.facts.moves.has(occupant.actor_id): arrived=true;break
	var intent: Dictionary=x.world.facts.waiting_life.seats[v.id]
	var alternative_seen: bool=false
	var body_overlap: bool=false
	for tick: int in 250:
		x.world.facts.sim_tick+=1
		x.l._dispatch_public_seat(x.world,v,intent)
		x.space.advance(x.world);x.world.touch(false)
		var move: Dictionary=x.world.facts.moves.get(v.actor_id,{})
		if not move.is_empty() and move.target_cell!=goal: alternative_seen=true
		body_overlap=body_overlap or x.space.body_rectangle(x.world.facts.actors[v.actor_id]).intersects(x.space.body_rectangle(x.world.facts.actors[occupant.actor_id]),false)
	return {"case":"A38_stolen_standing_goal","validation":validation,"initial":initial,"occupant_request":take,"occupant_actually_arrived":arrived,"alternate_goal_seen":alternative_seen,"overlap":body_overlap,"final_intent":intent,"remaining_move":x.world.facts.moves.get(v.actor_id,{}),"actor":x.world.facts.actors[v.actor_id].location}


func _safety_target_race(restore: bool) -> Dictionary:
	var x: Dictionary=_areas()
	x.world.facts.facilities.erase("west_chair");x.world.facts.facilities.erase("east_chair")
	var v: Dictionary=_visit(x,"safety",[37,78])
	x.world.touch();x.world.facts.sim_tick=50
	x.l.dispatch(x.world)
	var initial: Dictionary=x.world.facts.moves[v.actor_id].duplicate(true)
	var goal: Array=initial.target_cell
	var occupant: Dictionary=_visit(x,"occupant",[float(goal[0])+1,float(goal[1])])
	x.world.touch(false);x.space.sync_actor(x.world,occupant.actor_id)
	var request: String=x.space.request_move(x.world,occupant.actor_id,1,goal)
	var call_kept: bool = not x.l.call_patient(x.world,v.id)
	if restore:
		x = _json_restore(x)
		v = x.world.facts.visits.safety
		occupant = x.world.facts.visits.occupant
	var validation: String=x.world.validate(_content)
	var arrived: bool=false
	var alternate: bool=false
	var overlap: bool=false
	var first_arrival_tick: int=-1
	var max_ticks: int=250
	for tick: int in max_ticks:
		x.world.facts.sim_tick+=1;x.l.dispatch(x.world);x.space.advance(x.world);x.world.touch(false)
		if x.space.at(x.world,occupant.actor_id,1,goal) and not x.world.facts.moves.has(occupant.actor_id):
			arrived=true
			if first_arrival_tick<0: first_arrival_tick=tick+1
		var move: Dictionary=x.world.facts.moves.get(v.actor_id,{})
		if not move.is_empty() and move.target_cell!=goal: alternate=true
		overlap=overlap or x.space.body_rectangle(x.world.facts.actors[v.actor_id]).intersects(x.space.body_rectangle(x.world.facts.actors[occupant.actor_id]),false)
	var safe: bool = x.space.public_areas.safe_wait(x.world,v.actor_id,1,x.world.facts.actors[v.actor_id].location.cell)
	return {"case":"A38_safety_target_"+("json" if restore else "live"),"ok":call_kept and validation.is_empty() and arrived and alternate and not overlap and safe and x.world.validate(_content).is_empty(),"call_kept":call_kept,"initial":initial,"occupant_request":request,"input_validation":validation,"occupant_arrived":arrived,"occupant_arrival_tick":first_arrival_tick,"alternate_goal":alternate,"overlap":overlap,"final_move":x.world.facts.moves.get(v.actor_id,{}),"final_position":x.world.facts.actors[v.actor_id].location,"final_safe":x.space.public_areas.safe_wait(x.world,v.actor_id,1,x.world.facts.actors[v.actor_id].location.cell),"final_validation":x.world.validate(_content),"intent":x.world.facts.waiting_life.seats.get(v.id,{})}

func _worker_preference_boundaries() -> Dictionary:
	var x: Dictionary = _areas()
	var v: Dictionary = _visit(x,"worker_subject",[38,73])
	_facility(x,"dry_source","FUR21",[36,73],"west")
	_facility(x,"water_source","FUR17",[39,71],"west")
	x.world.touch()
	var valid: String = x.world.validate(_content)
	var rows: Array = []
	var ok: bool = valid.is_empty()
	for failed: bool in [false,true]:
		x.world.facts.facilities.dry_source.failed = failed
		x.world.touch(false)
		var before: Dictionary = x.world.freeze()
		x.e.begin_query(x.world)
		var batch: RefCounted = preload("res://game/operations/environment_sample_batch.gd").new()
		var prepared: bool = batch.prepare(x.world,x.e,[v.id],4,true)
		var expected: Dictionary = x.e.sample_at(x.world,1,[38,73],v.actor_id)
		var actual: Dictionary = {}
		if prepared:
			batch.begin_apply()
			actual = batch.consume(x.world,x.e,v.id,v.actor_id)
			batch.end_apply(x.e)
		x.e.end_query()
		var equal: bool = actual==expected and actual.water and actual.moist==failed and actual.dry!=failed and before==x.world.freeze()
		ok = ok and prepared and equal
		rows.append({"dry_failed":failed,"prepared":prepared,"complete_observation_equal":equal,"actual":actual,"expected":expected})
	return {"case":"A36_worker_nearest_live_water","ok":ok,"input_validation":valid,"observations":rows}

func _safety_same_goal_takeover() -> Dictionary:
	var x: Dictionary = _areas()
	x.world.facts.facilities.erase("west_chair");x.world.facts.facilities.erase("east_chair")
	var v: Dictionary = _visit(x,"safety_takeover",[37,78])
	x.world.touch();x.world.facts.sim_tick = 50;x.l.dispatch(x.world)
	var movement: Dictionary = x.world.facts.moves.get(v.actor_id,{})
	var owned: bool = movement.get("waiting_safety_visit","")==v.id
	var goal: Array = movement.get("target_cell",[]).duplicate()
	var reason: String = x.space.request_move(x.world,v.actor_id,1,goal)
	var transferred: bool = not movement.has("waiting_safety_visit")
	var occupant: Dictionary = _visit(x,"takeover_occupant",[float(goal[0])+1,float(goal[1])])
	x.world.touch(false);x.space.sync_actor(x.world,occupant.actor_id)
	x.space.request_move(x.world,occupant.actor_id,1,goal)
	for tick: int in 100:
		x.world.facts.sim_tick+=1;x.space.advance(x.world);x.world.touch(false)
		if x.space.at(x.world,occupant.actor_id,1,goal) and not x.world.facts.moves.has(occupant.actor_id): break
	var original: Dictionary = x.world.facts.moves.get(v.actor_id,{}).duplicate(true)
	x.l.dispatch(x.world)
	var kept: bool = not original.is_empty() and original==x.world.facts.moves.get(v.actor_id,{})
	return {"case":"A38_safety_same_destination_takeover","ok":owned and reason.is_empty() and transferred and kept and x.world.validate(_content).is_empty(),"was_safety_owned":owned,"accepted_external_request":reason.is_empty(),"ownership_cleared":transferred,"other_task_preserved":kept,"validation":x.world.validate(_content)}
