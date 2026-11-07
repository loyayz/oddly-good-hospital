extends "res://tests/acceptance/public_area_use.gd"

const Dependencies = preload("res://game/life/waiting_dependencies.gd")
const WAITING_KINDS: Array = ["waiting","waiting_area","public","lobby","garden",""]

func run_adoptions(database: HospitalContent, selected: Array = []) -> Dictionary:
	_content = database
	var rows: Array = []
	if selected.is_empty() or "A22" in selected: rows.append(_shared_regions())
	if selected.is_empty() or "A30" in selected:
		for variant: String in ["occupied_old_seat","repurposed_room","blocked_return_point","json_return"]:
			rows.append(_need_return(variant))
		rows.append(_need_cross_floor())
	if selected.is_empty() or "A35" in selected:
		for mode: String in ["auto","manual","json"]: rows.append(_ready_call(mode))
		rows.append(_other_move())
		rows.append(_other_move(true))
		rows.append(_detour_call())
		rows.append(_convoy_call())
		rows.append(_clinical_call())
	if selected.is_empty() or "A37" in selected or "A35" in selected:
		rows.append(_standing_safety())
		rows.append(_floor_local())
		rows.append(_floor_local(true))
	return {"ok":not rows.is_empty() and rows.all(func(row: Dictionary)->bool:return row.ok),"cases":rows}

func _shared_regions() -> Dictionary:
	var d = Dependencies.new()
	var rect: Rect2 = Rect2(10,20,13,13)
	for n: int in 160:
		var id: String = str(n)
		d.remember(id,{"actor:"+id:{"kind":"actor","id":id,"value":[n]}},1,[rect,rect] as Array[Rect2])
	var shared: bool = d._regions._records.size()==1 and d.waiters.size()==160 and d.waiters["0"].regions.size()==1
	d.mark("actor:0")
	var personal: bool = _dirty_ids(d)==["0"]
	d.remove("0")
	var retained: bool = d._regions._records.size()==1 and d.waiters.size()==159
	d.remember("upper",{},65537,[rect] as Array[Rect2])
	d.remember("edge",{},1,[Rect2(23,20,1,1)] as Array[Rect2])
	d.actor_changed("body",0,Rect2(),1,Rect2(22,20,1,1))
	var exact: bool = _dirty_ids(d).size()==159 and not d.dirty("upper") and not d.dirty("edge")
	for id: String in d.waiters: d.waiters[id].dirty = false
	d.reservation_changed("claim",{"floor_id":65537,"kind":"facility","regions":[[10,20,1,1]]})
	var floor_exact: bool = _dirty_ids(d)==["upper"]
	d.remember("upper",{},2,[rect] as Array[Rect2])
	d.reservation_changed("claim",{})
	var rebind: bool = _dirty_ids(d).is_empty() and not d._region_tokens.has(65537)
	for id: String in d.waiters.keys(): d.remove(id)
	var removed: bool = d._regions._records.is_empty() and d._region_tokens.is_empty() and d._region_waiters.is_empty() and d.resources.is_empty()
	d.remember("again",{},1,[rect] as Array[Rect2]);d.clear()
	var cleared: bool = d.waiters.is_empty() and d._region_tokens.is_empty() and d._regions._records.is_empty() and d._actors.is_empty() and d._reservations.is_empty()
	return {"case":"A22_shared_exact_regions","ok":shared and personal and retained and exact and floor_exact and rebind and removed and cleared,"one_spatial_record_for_160_waiters":shared,"independent_actor_resources":personal,"remove_one_retains_159":retained,"strict_edge_and_floor":exact,"reservation_floor":floor_exact,"rebind":rebind,"last_remove":removed,"clear":cleared}

func _dirty_ids(d: RefCounted) -> Array:
	var ids: Array = []
	for id: String in d.waiters:
		if d.dirty(id): ids.append(id)
	ids.sort()
	return ids

func _tick_need(x: Dictionary) -> void:
	x.world.facts.sim_tick += 1
	x.l.dispatch(x.world)
	x.space.advance(x.world)
	x.l.advance(x.world)
	x.world.touch(false)

func _json_restore(x: Dictionary) -> Dictionary:
	var encoder: HospitalJsonStream = HospitalJsonStream.new()
	var path: String = "user://waiting-current.json"
	if not encoder.encode(path,x.world.freeze(),func(_bytes:int)->bool:return true): return x
	var decoder: HospitalJsonStream = HospitalJsonStream.new()
	var decoded: Dictionary = decoder.decode(path,encoder.bytes,encoder.digest,func(_bytes:int)->bool:return true)
	return _bind(WorldState.new(decoded.value))

func _need_return(variant: String) -> Dictionary:
	var x: Dictionary = _areas()
	_facility(x,"toilet","FUR07",[39,68],"west")
	x.world.touch()
	var v: Dictionary = _visit(x,"return_subject",[38,73])
	var seated: bool = _seat_checkpoint(x,v,"west_chair")
	var old: Dictionary = x.world.facts.actors[v.actor_id].location.duplicate(true)
	var ticket: String = v.ticket_id
	var waited: int = x.world.facts.tickets[ticket].waited_ticks
	x.world.facts.sim_tick = 1800
	x.l._begin_need(x.world,v)
	var used: bool = false
	for tick: int in 250:
		if x.world.facts.waiting_life.needs.get(v.id,{}).get("phase","")=="using": used=true;break
		_tick_need(x)
	var other: Dictionary = {}
	if variant=="occupied_old_seat":
		other = _visit(x,"other_chair_user",[36,72])
		x.world.facts.waiting_life.clocks[other.id].next_need_tick = 1000000
		x.l.execute(x.world,"waiting_select_seat",{"visit_id":other.id,"facility_id":"west_chair"})
	elif variant=="repurposed_room":
		x.world.facts.rooms.west.kind = "treatment"
		x.world.facts.rooms.west.type = "treatment"
		x.world.touch()
	var returning: bool = false
	for tick: int in 110:
		if x.world.facts.waiting_life.needs.get(v.id,{}).get("phase","")=="returning": returning=true;break
		_tick_need(x)
	var chosen: Dictionary = x.world.facts.waiting_life.needs.get(v.id,{}).get("return_to",{}).duplicate(true)
	var retained_pause: bool = x.world.facts.tickets[ticket].pause_reasons.has("need_service")
	var saved: bool = true
	if variant=="json_return":
		var facts: Dictionary = x.world.freeze()
		x = _json_restore(x);v=x.world.facts.visits[v.id]
		saved = facts==x.world.freeze() and x.l.validate(x.world).is_empty()
	elif variant=="blocked_return_point" and not chosen.is_empty():
		# Explicit changed dynamic boundary: another body now occupies the chosen point.
		_visit(x,"new_return_blocker",chosen.cell)
		x.world.touch(false)
	var moved: bool = false
	var errors: Array = []
	for tick: int in 400:
		if not x.world.facts.waiting_life.needs.has(v.id): break
		var before: Vector2 = Vector2(x.world.facts.actors[v.actor_id].location.cell[0],x.world.facts.actors[v.actor_id].location.cell[1])
		_tick_need(x)
		var after: Vector2 = Vector2(x.world.facts.actors[v.actor_id].location.cell[0],x.world.facts.actors[v.actor_id].location.cell[1])
		moved = moved or before!=after
		if before.distance_to(after)>x.space.walking_speed(x.world.facts.actors[v.actor_id])*WorldState.TICK_SECONDS+0.0001: errors.append("nonphysical_step")
	var actor: Dictionary = x.world.facts.actors[v.actor_id]
	var area: Dictionary = x.space.public_areas.current_area(x.world,v.actor_id)
	var finished: bool = not x.world.facts.waiting_life.needs.has(v.id)
	var safe: bool = actor.location.kind=="floor" and x.space.public_areas.area_valid(x.world,area,WAITING_KINDS) and x.space.public_areas.safe_wait(x.world,v.actor_id,int(actor.location.floor_id),actor.location.cell)
	var same_ticket: bool = v.ticket_id==ticket and x.world.facts.tickets.has(ticket) and x.world.facts.tickets[ticket].waited_ticks==waited and not x.world.facts.tickets[ticket].pause_reasons.has("need_service")
	var not_old: bool = actor.location.cell!=old.cell
	var occupied: bool = variant!="occupied_old_seat" or x.world.facts.waiting_life.seats.get(other.id,{}).get("phase","")=="seated"
	return {"case":"A30_"+variant,"ok":seated and used and returning and retained_pause and saved and moved and finished and safe and same_ticket and not_old and occupied and errors.is_empty(),"used_actual_facility":used,"returning":returning,"pause_retained":retained_pause,"saved":saved,"real_return_moved":moved,"finished":finished,"legal_safe_region":safe,"same_ticket_and_wait":same_ticket,"old_seat_not_reclaimed":not_old and occupied,"old":old,"selected":chosen,"final":actor.location,"remaining":x.world.facts.waiting_life.needs.get(v.id,{}),"errors":errors}

func _ready_call(mode: String) -> Dictionary:
	var x: Dictionary = _areas()
	var v: Dictionary = _visit(x,"ready_subject",[38,90])
	x.world.facts.sim_tick = 50
	if mode=="auto": x.l.dispatch(x.world)
	else: x.l.execute(x.world,"waiting_select_seat",{"visit_id":v.id,"facility_id":"east_chair"})
	for tick: int in 5: _tick_need(x)
	var moving: bool = x.world.facts.moves.has(v.actor_id)
	var saved: bool = true
	if mode=="json":
		var facts: Dictionary = x.world.freeze()
		x = _json_restore(x);v=x.world.facts.visits[v.id]
		saved = facts==x.world.freeze()
	var location: Dictionary = x.world.facts.actors[v.actor_id].location.duplicate(true)
	var ticket: String = v.ticket_id
	var called: bool = x.l.call_patient(x.world,v.id)
	var stopped: bool = not x.world.facts.moves.has(v.actor_id) and not x.world.facts.waiting_life.seats.has(v.id) and location==x.world.facts.actors[v.actor_id].location
	var request: String = x.space.request_move(x.world,v.actor_id,1,[42,90])
	for tick: int in 300:
		x.world.facts.sim_tick += 1;x.space.advance(x.world);x.world.touch(false)
		if not x.world.facts.moves.has(v.actor_id): break
	var arrived: bool = x.space.at(x.world,v.actor_id,1,[42,90])
	return {"case":"A35_"+mode,"ok":moving and saved and called and stopped and request.is_empty() and arrived and v.ticket_id==ticket,"actual_optional_walk":moving,"json_equal":saved,"called":called,"only_owned_walk_cancelled_no_teleport":stopped,"new_real_destination_arrived":arrived}

func _other_move(same_destination: bool = false) -> Dictionary:
	var x: Dictionary = _areas()
	var v: Dictionary = _visit(x,"external_subject",[38,90])
	x.world.facts.sim_tick = 50;x.l.dispatch(x.world)
	var prior: Dictionary = x.world.facts.moves.get(v.actor_id,{}).duplicate(true)
	x.space.request_move(x.world,v.actor_id,int(prior.target_floor),prior.target_cell if same_destination else [42,90])
	var move: Dictionary = x.world.facts.moves.get(v.actor_id,{}).duplicate(true)
	var result: bool = x.l.call_patient(x.world,v.id)
	var kept: bool = not result and move==x.world.facts.moves.get(v.actor_id,{}) and not move.has("waiting_seat_id")
	return {"case":"A35_other_task_same_target" if same_destination else "A35_other_task_retarget","ok":prior.has("waiting_seat_id") and kept,"old_optional_identity":prior.get("waiting_seat_id",""),"new_task_not_cancelled":kept}

func _floor_local(save_in_transit: bool = false) -> Dictionary:
	var x: Dictionary = _fixture()
	var plots: Array = HospitalSpace.floor_plots(x.world,1).duplicate(true)
	x.world.facts.floors.completed_top_floor = {}
	for plot: Array in plots: x.world.facts.floors.completed_top_floor[HospitalSpace.plot_key(plot)] = 2
	x.world.facts.floors.height_intervals = [{"first":1,"last":2,"height_m":float(_content.balance.floors.clear_height_m)}]
	x.world.facts.floors.overrides["2"] = {"plots":plots,"blocked":[],"doors":[],"paths":[]}
	x.world.facts.connectors["lift"] = {"id":"lift","definition_id":"VC02","stops":[1,2],"cell":[58,84],"footprint":[4,4],"rotation":0,"anchor":[59,88],"repair_cell":[57,85],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0,"ticket_next":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},"paid_cost":3200,"used":false}
	_facility(x,"upper_chair","FUR09",[40,80]);x.world.facts.facilities.upper_chair.floor_id=2
	_facility(x,"upper_competitor","FUR09",[52,80]);x.world.facts.facilities.upper_competitor.floor_id=2
	_facility(x,"upper_lamp","FUR19",[52,78]);x.world.facts.facilities.upper_lamp.floor_id=2
	x.m.ensure(x.world);x.world.touch()
	var v: Dictionary = _visit(x,"floor_local",[40,90])
	# The alternative is genuinely preferable for automatic choice: this real
	# species prefers the lamp beside it, while the explicitly chosen chair is dark.
	for binding: Dictionary in _content.catalog.treatment_bindings:
		if binding.species_id!="S07": continue
		x.world.facts.actors[v.actor_id].species_id = binding.species_id
		x.world.facts.actors[v.actor_id].body_binding_id = binding.id
		v.binding_id = binding.id;v.disease_id = binding.disease_id;v.requested_plan_id = "P_"+binding.disease_id+"_COMMON"
		x.space.sync_actor(x.world,v.actor_id)
		break
	x.world.facts.sim_tick = 50;x.l.dispatch(x.world)
	var no_auto: bool = not x.world.facts.moves.has(v.actor_id) and not x.world.facts.waiting_life.seats.has(v.id) and not x.l.patient_summary(x.world,v.id).reason.is_empty()
	var before: Dictionary = x.world.freeze()
	var request: CommandResult = x.l.execute(x.world,"waiting_select_seat",{"visit_id":v.id,"facility_id":"upper_chair"})
	var refused: bool = not request.accepted and x.world.freeze()==before
	# Latest rule removes the old manual cross-floor exception. A different
	# legitimate journey still uses the ordinary real transit implementation.
	var travel: String = x.space.request_move(x.world,v.actor_id,2,[52,88])
	var ride_seen: bool = false
	var protected: bool = false
	var restored: bool = not save_in_transit
	var valid: String = x.world.validate(_content)
	for tick: int in 650:
		_tick_need(x)
		var actor: Dictionary = x.world.facts.actors[v.actor_id]
		if actor.location.kind=="transit" and not ride_seen:
			ride_seen = true
			var move: Dictionary = x.world.facts.moves[v.actor_id].duplicate(true)
			protected = not x.l.call_patient(x.world,v.id) and x.world.facts.moves[v.actor_id]==move
			if save_in_transit:
				var old_id: int = x.world.get_instance_id()
				x = _json_restore(x)
				v = x.world.facts.visits.floor_local
				restored = x.world.get_instance_id()!=old_id and x.world.facts.moves.get(v.actor_id,{})==move
		if actor.location.kind=="floor" and int(actor.location.floor_id)==2 and not x.world.facts.moves.has(v.actor_id): break
	var arrived: bool = x.space.at(x.world,v.actor_id,2,[52,88]) and not x.world.facts.moves.has(v.actor_id)
	var local: CommandResult = x.l.execute(x.world,"waiting_select_seat",{"visit_id":v.id,"facility_id":"upper_chair"})
	for tick: int in 300:
		_tick_need(x)
		if x.world.facts.waiting_life.seats.get(v.id,{}).get("phase","")=="seated": break
	var seat: Dictionary = x.world.facts.waiting_life.seats.get(v.id,{})
	var seated: bool = seat.get("phase","")=="seated" and seat.get("mode","")=="manual" and seat.get("facility_id","")=="upper_chair" and int(x.world.facts.actors[v.actor_id].location.floor_id)==2
	return {"case":"A37_no_cross_floor_waiting_but_real_other_trip"+("_json" if save_in_transit else ""),"ok":valid.is_empty() and no_auto and refused and travel.is_empty() and ride_seen and protected and restored and arrived and local.accepted and seated and x.world.validate(_content).is_empty(),"input_validation":valid,"auto_stays_floor_one_without_chair":no_auto,"manual_upstairs_rejected_atomically":refused,"other_real_lift_ride":ride_seen,"ride_not_cancelled":protected,"json_restored":restored,"actual_other_trip_arrived":arrived,"manual_same_floor_seated":seated,"final_validation":x.world.validate(_content)}

func _clinical_call() -> Dictionary:
	var builder = preload("res://tests/acceptance/clinical_fixtures.gd").new()
	builder._content = _content
	var c: Dictionary = builder._context(false,false,true)
	var arrived: bool = builder._arrive(c)
	var v: Dictionary = c.world.facts.visits.get(c.visit_id,{})
	for tick: int in 900:
		if v.get("phase","")=="wait_gp": break
		builder._tick(c)
	var ready: bool = v.get("phase","")=="wait_gp"
	var x: Dictionary = {"world":c.world,"space":c.sim.space,"l":c.sim.services.waiting,"c":c.sim.clinic,"p":c.sim.services.departments}
	var request: bool = false
	var quote: Dictionary = {}
	for id: String in c.world.facility_ids("FUR09"):
		quote = x.l._seat_target_quote(c.world,v,id)
		if not quote.get("ok",false): continue
		request = x.l.execute(x.world,"waiting_select_seat",{"visit_id":v.id,"facility_id":id}).accepted
		if request: break
	var moving: bool = c.world.facts.moves.has(v.actor_id)
	var old_target: Array = c.world.facts.moves.get(v.actor_id,{}).get("target_cell",[]).duplicate()
	c.sim.clinic.dispatch(c.world)
	var new_move: Dictionary = c.world.facts.moves.get(v.actor_id,{})
	var redirected: bool = not new_move.is_empty() and not new_move.has("waiting_seat_id") and new_move.target_cell!=old_target and not c.world.facts.waiting_life.seats.has(v.id)
	var started: bool = false
	for tick: int in 700:
		builder._tick(c)
		if v.phase=="gp": started=true;break
	var result: Dictionary = {"case":"A35_ready_clinic_actual_handoff","ok":arrived and ready and request and moving and redirected and started,"naturally_arrived":arrived,"gp_queue":ready,"seat_request":request,"quote":quote,"optional_walk":moving,"ready_clinic_redirected":redirected,"actual_gp_started":started,"phase":v.phase,"reason":v.waiting_reason}
	builder._dispose_simulations()
	return result

func _detour_call() -> Dictionary:
	var x: Dictionary = _areas()
	var v: Dictionary = _visit(x,"detour_subject",[38,90])
	var request: CommandResult = x.l.execute(x.world,"waiting_select_seat",{"visit_id":v.id,"facility_id":"east_chair"})
	_tick_need(x)
	var movement: Dictionary = x.world.facts.moves.get(v.actor_id,{})
	if movement.get("path",[]).size()<5: return {"case":"A35_real_detour","ok":false,"reason":"fixture path too short","movement":movement}
	var point: Array = movement.path[int(movement.cursor)+3].cell
	var blocker: Dictionary = _visit(x,"detour_blocker",point)
	x.world.facts.waiting_life.clocks[blocker.id].next_need_tick=1000000
	x.space.sync_actor(x.world,blocker.actor_id)
	var seen: bool = false
	var kept: bool = false
	for tick: int in 160:
		_tick_need(x)
		movement=x.world.facts.moves.get(v.actor_id,{})
		if movement.has("detour"):
			seen=true
			var before: Dictionary=movement.duplicate(true)
			kept=not x.l.call_patient(x.world,v.id) and before==x.world.facts.moves.get(v.actor_id,{})
			break
	var resumed: bool=false
	if seen:
		x.space.request_move(x.world,blocker.actor_id,1,[45,95])
		for tick: int in 400:
			_tick_need(x)
			if x.l.call_patient(x.world,v.id): resumed=true;break
	return {"case":"A35_real_detour","ok":request.accepted and seen and kept and resumed,"real_detour_seen":seen,"call_kept_safety_segment":kept,"call_resumed_after_detour":resumed,"remaining":x.world.facts.moves.get(v.actor_id,{})}

func _standing_safety() -> Dictionary:
	var x: Dictionary = _fixture()
	_facility(x,"water","FUR08",[40,80]);x.world.touch()
	var v: Dictionary = _visit(x,"standing_subject",x.space.facility_layout(x.world,"water").patient_cell)
	x.world.facts.sim_tick=50
	x.l.dispatch(x.world)
	var movement: Dictionary=x.world.facts.moves.get(v.actor_id,{}).duplicate(true)
	var needed: bool=not movement.is_empty() and not movement.has("waiting_seat_id")
	var kept: bool=not x.l.call_patient(x.world,v.id) and movement==x.world.facts.moves.get(v.actor_id,{})
	for tick: int in 100:
		_tick_need(x)
		if not x.world.facts.moves.has(v.actor_id): break
	var actor: Dictionary=x.world.facts.actors[v.actor_id]
	var safe: bool=x.space.public_areas.safe_wait(x.world,v.actor_id,1,actor.location.cell)
	var feedback: bool=not x.l.patient_summary(x.world,v.id).reason.is_empty()
	_facility(x,"new_local_chair","FUR09",[43,80]);x.world.touch()
	x.world.facts.tickets[v.ticket_id].called_tick=-1
	var seated: bool=_until_seated(x,v,300)
	return {"case":"A37_no_chair_safe_standing_and_new_local_chair","ok":needed and kept and safe and feedback and seated,"real_safety_departure":needed,"call_preserves_required_departure":kept,"safe_standing_arrived":safe,"no_seat_feedback":feedback,"new_local_chair_later_used":seated}

func _convoy_call() -> Dictionary:
	var x: Dictionary = _fixture()
	var leader: Dictionary = _visit(x,"group_leader",[44,88])
	var follower: Dictionary = _visit(x,"group_follower",[42,88])
	var members: Array = [leader.actor_id,follower.actor_id]
	var form: Dictionary = ConvoyTrail.formation(x.space,x.world,leader.actor_id,members)
	_position(x,follower.actor_id,form.targets[follower.actor_id])
	var reason: String = x.space.request_group_move(x.world,leader.actor_id,members,{},1,[54,88])
	var original: Dictionary = x.world.facts.moves.get(leader.actor_id,{}).duplicate(true)
	var kept_leader: bool = not x.l.call_patient(x.world,leader.id) and original==x.world.facts.moves.get(leader.actor_id,{})
	var kept_follower: bool = not x.l.call_patient(x.world,follower.id) and original==x.world.facts.moves.get(leader.actor_id,{})
	for tick: int in 300:
		x.world.facts.sim_tick+=1;x.space.advance(x.world);x.world.touch(false)
		if x.world.facts.moves.is_empty(): break
	var arrived: bool = x.space.at(x.world,leader.actor_id,1,[54,88]) and x.world.facts.moves.is_empty()
	var released: bool = x.l.call_patient(x.world,leader.id) and x.l.call_patient(x.world,follower.id)
	return {"case":"A35_real_convoy_and_follower","ok":reason.is_empty() and original.has("convoy") and kept_leader and kept_follower and arrived and released,"request":reason,"leader_kept":kept_leader,"follower_without_own_move_kept":kept_follower,"actual_convoy_arrived":arrived,"called_after_group_release":released}

func _need_cross_floor() -> Dictionary:
	var x: Dictionary = _fixture()
	HospitalFactory._add_room(x.world,{"id":"service_floor","type":"treatment","anchor":[33,65],"size":[30,30],"door":{"definition_id":"DR04","offset":3}},_content)
	var plots: Array = HospitalSpace.floor_plots(x.world,1).duplicate(true)
	x.world.facts.floors.completed_top_floor={}
	for plot: Array in plots: x.world.facts.floors.completed_top_floor[HospitalSpace.plot_key(plot)]=2
	x.world.facts.floors.height_intervals=[{"first":1,"last":2,"height_m":float(_content.balance.floors.clear_height_m)}]
	x.world.facts.floors.overrides["2"]={"plots":plots,"blocked":[],"doors":[],"paths":[]}
	x.world.facts.connectors["lift"]={"id":"lift","definition_id":"VC02","stops":[1,2],"cell":[58,84],"footprint":[4,4],"rotation":0,"anchor":[59,88],"repair_cell":[57,85],"floor_id":1,"phase":"idle","riders":[],"remaining_ticks":0,"ticket_next":0,"condition":100.0,"failed":false,"pending_failure":false,"use_receipts":{},"paid_cost":3200,"used":false}
	_facility(x,"toilet","FUR07",[39,68],"service_floor");x.m.ensure(x.world);x.world.touch()
	var v: Dictionary = _visit(x,"cross_floor_need",[38,73])
	var ticket: String = v.ticket_id
	var input_error: String=x.world.validate(_content)
	var local: Dictionary=x.space.public_areas.select(x.world,v.actor_id,[],WAITING_KINDS,"rest",[],9223372036854775807,{},true)
	x.world.facts.sim_tick=1800;x.l._begin_need(x.world,v)
	var used: bool=false;var ride: bool=false
	for tick: int in 1000:
		var need: Dictionary=x.world.facts.waiting_life.needs.get(v.id,{})
		used=used or need.get("phase","")=="using"
		ride=ride or x.world.facts.actors[v.actor_id].location.kind=="transit"
		if not x.world.facts.waiting_life.needs.has(v.id): break
		_tick_need(x)
	var actor: Dictionary=x.world.facts.actors[v.actor_id]
	var finished: bool=not x.world.facts.waiting_life.needs.has(v.id) and not x.world.facts.tickets[ticket].pause_reasons.has("need_service")
	var safe: bool=actor.location.kind=="floor" and int(actor.location.floor_id)==2 and x.space.public_areas.safe_wait(x.world,v.actor_id,2,actor.location.cell)
	return {"case":"A30_required_return_may_cross_floor","ok":input_error.is_empty() and local.is_empty() and used and ride and finished and safe and v.ticket_id==ticket,"input_validation":input_error,"no_legal_local_waiting_point":local.is_empty(),"real_use":used,"real_return_lift":ride,"finished":finished,"safe_upstairs":safe,"final":actor.location,"remaining":x.world.facts.waiting_life.needs.get(v.id,{})}
