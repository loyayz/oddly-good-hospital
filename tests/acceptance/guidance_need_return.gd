extends "res://tests/acceptance/floor_guidance.gd"
func run_need_return(content: HospitalContent, selected: Array = [])->Dictionary:
	_content=content
	var runs: Dictionary={
		"unguided_need_returns_to_desk_scope":_before_guidance,
		"guided_destination_need_return_unchanged":_after_guidance.bind("destination"),
		"guided_ready_need_return_unchanged":_after_guidance.bind("ready"),
		"guided_destination_need_return_remove":_after_guidance.bind("destination","remove"),
		"guided_destination_need_return_move":_after_guidance.bind("destination","move"),
		"guided_need_return_without_desk_or_destination":_without_desk_or_destination,
	}
	var cases: Array=[]
	for id: String in (runs.keys() if selected.is_empty() else selected):
		if not runs.has(id):return {"passed":false,"error":"unknown selector "+id}
		cases.append(runs[id].call())
	return {"passed":not cases.any(func(r: Dictionary)->bool:return not r.ok),"cases":cases}
func _before_guidance()->Dictionary:
	var x: Dictionary=_base()
	var v: Dictionary=_visit(x,"before",[49,86])
	var real_unguided: bool=false
	for tick: int in 600:
		_step(x)
		var observed: Dictionary=x.g.state(x.world,v.id)
		var movement: Dictionary=x.world.facts.moves.get(v.actor_id,{})
		var own_journey: bool=not movement.is_empty() and movement.get("floor_guidance_key","")==observed.get("request_key","")
		var actual_queue: bool=observed.has("queue_cell") and x.space.at(x.world,v.actor_id,int(observed.get("guide_floor",0)),observed.queue_cell)
		real_unguided=observed.get("phase","") in ["seek","desk_queue","to_counter","working"] and observed.get("receipts",[]).is_empty() and observed.get("desk_id","")=="guide" and (own_journey or actual_queue)
		if real_unguided:break
	var state: Dictionary=x.g.state(x.world,v.id).duplicate(true)
	var id: String=x.g._return_scope(x.world,v)
	var point: Dictionary=x.g.return_point(x.world,v)
	var valid: bool=not point.is_empty() and x.g.scope.allows(x.world,v.actor_id,"guide",int(point.get("floor_id",0)),point.get("cell",[]))
	var row: Dictionary={"case":"unguided_need_returns_to_desk_scope","ok":real_unguided and state.receipts.is_empty() and id=="guide" and valid,"actual_unguided_journey_or_queue":real_unguided,"receipt_count":state.receipts.size(),"movement":x.world.facts.moves.get(v.actor_id,{}).duplicate(true),"state":state,"return_scope":id,"return_point":point}
	_dispose(x);return row
func _after_guidance(wanted: String, edit: String="")->Dictionary:
	var x: Dictionary=_base()
	_facility(x,"water","FUR17",[54,89]);x.world.touch()
	var v: Dictionary=_visit(x,"after",[49,86])
	var reached: bool=false
	for tick: int in 1000:
		_step(x)
		if x.g.state(x.world,v.id).get("phase","")==wanted:reached=true;break
	var before: Dictionary=x.g.state(x.world,v.id).duplicate(true)
	var scope_before: String=x.g._return_scope(x.world,v)
	var clock: Dictionary=x.world.facts.waiting_life.clocks[v.id]
	clock.next_purpose="water";clock.next_need_tick=x.world.sim_tick
	x.world.touch(false)
	var actual_use: bool=false;var returned: bool=false;var no_overlap: bool=true
	var edited: bool=edit.is_empty();var edit_record: Dictionary={};var after_edit_scope: String=""
	var need_seen: bool=false;var return_point: Dictionary={};var final_scope: String=""
	for tick: int in 1000:
		_step(x)
		no_overlap=no_overlap and not _overlap(x,v.actor_id)
		var need: Dictionary=x.world.facts.waiting_life.needs.get(v.id,{})
		need_seen=need_seen or not need.is_empty()
		if need.get("phase","")=="using":
			var layout: Dictionary=x.space.facility_layout(x.world,str(need.facility_id))
			actual_use=actual_use or (x.space.at(x.world,v.actor_id,int(layout.floor_id),layout.patient_cell) and not x.world.facts.moves.has(v.actor_id))
			if not edited:
				var build: BuildService=BuildService.new(_content,x.space)
				var command: CommandResult
				if edit=="remove":command=build.execute(x.world,"build_demolish",{"target_id":"diagnosis"})
				else:command=build.execute(x.world,"build_move",{"target_id":"diagnosis","floor_id":1,"cell":[40,69],"room_id":"clinic"})
				edit_record=command.to_record();edited=command.accepted
				after_edit_scope=x.g._return_scope(x.world,v)
				if not edited:break
		if need.get("phase","")=="returning":
			return_point=x.g.return_point(x.world,v)
			final_scope=x.g._return_scope(x.world,v)
		if need_seen and actual_use and need.is_empty():
			final_scope=x.g._return_scope(x.world,v)
			var actor: Dictionary=x.world.facts.actors[v.actor_id]
			returned=x.g.return_allows(x.world,v,int(actor.location.floor_id),actor.location.cell)
			break
	var final: Dictionary=x.g.state(x.world,v.id).duplicate(true)
	var expected: String="guide" if edit=="remove" else "diagnosis"
	var no_extra_service: bool=final.receipts.size()==1
	var row: Dictionary={"case":"guided_"+wanted+"_need_return_"+("unchanged" if edit.is_empty() else edit),"ok":reached and before.receipts.size()==1 and scope_before=="diagnosis" and actual_use and edited and returned and final_scope==expected and no_overlap and no_extra_service and (edit.is_empty() or after_edit_scope==expected) and x.world.validate(_content).is_empty(),"reached_real_phase":reached,"before":before,"scope_before":scope_before,"actual_water_use":actual_use,"edit":edit_record,"scope_after_edit":after_edit_scope,"return_point":return_point,"actual_return_in_current_scope":returned,"final_scope":final_scope,"no_duplicate_guidance_service":no_extra_service,"no_overlap":no_overlap,"final":final,"validation":x.world.validate(_content)}
	_dispose(x);return row

# Regression: the water service cell is inside the public area but is not
# safe standing space. Losing both return scopes must still walk to safety.
func _without_desk_or_destination()->Dictionary:
	var x: Dictionary=_base()
	_facility(x,"water","FUR17",[54,89]);x.world.touch()
	var v: Dictionary=_visit(x,"without_return_scope",[49,86])
	var reached: bool=false
	for tick: int in 1000:
		_step(x)
		if x.g.state(x.world,v.id).get("phase","")=="destination":reached=true;break
	var before: Dictionary=x.g.state(x.world,v.id).duplicate(true)
	var ticket_before: Dictionary=x.world.facts.tickets[v.ticket_id].duplicate(true)
	var clock: Dictionary=x.world.facts.waiting_life.clocks[v.id]
	clock.next_purpose="water";clock.next_need_tick=x.world.sim_tick
	x.world.touch(false)
	var actual_use: bool=false;var returned: bool=false;var no_overlap: bool=true
	var pauses_preserved: bool=true;var ticket_preserved: bool=true
	var legal_steps: bool=true;var owned_return_move: bool=false;var moved_after_use: bool=false
	var edits: Array=[];var return_start: Dictionary={};var trace: Array=[]
	var previous: Array=x.world.facts.actors[v.actor_id].location.cell.duplicate()
	for tick: int in 1000:
		_step(x)
		var actor: Dictionary=x.world.facts.actors[v.actor_id]
		var cell: Array=actor.location.cell
		var distance: float=Vector2(cell[0],cell[1]).distance_to(Vector2(previous[0],previous[1]))
		# This human's ordinary movement is sub-cell per simulation tick.
		legal_steps=legal_steps and actor.location.kind=="floor" and int(actor.location.floor_id)==1 and distance<=1.0
		if not return_start.is_empty():moved_after_use=moved_after_use or distance>0.001
		previous=cell.duplicate()
		no_overlap=no_overlap and not _overlap(x,v.actor_id)
		var need: Dictionary=x.world.facts.waiting_life.needs.get(v.id,{})
		var ticket: Dictionary=x.world.facts.tickets[v.ticket_id]
		ticket_preserved=ticket_preserved and v.ticket_id==ticket_before.id and ticket.id==ticket_before.id and ticket.enqueued_tick==ticket_before.enqueued_tick and ticket.waited_ticks>=ticket_before.waited_ticks and not ticket.service_assigned
		if not need.is_empty():pauses_preserved=pauses_preserved and ticket.pause_reasons.get("need_service","")==need.id
		if need.get("phase","")=="using" and edits.is_empty():
			var layout: Dictionary=x.space.facility_layout(x.world,"water")
			actual_use=x.space.at(x.world,v.actor_id,int(layout.floor_id),layout.patient_cell) and not x.world.facts.moves.has(v.actor_id)
			var build: BuildService=BuildService.new(_content,x.space)
			for id: String in ["diagnosis","guide"]:
				edits.append(build.execute(x.world,"build_demolish",{"target_id":id}).to_record())
		if need.get("phase","")=="returning":
			var movement: Dictionary=x.world.facts.moves.get(v.actor_id,{})
			owned_return_move=owned_return_move or (not movement.is_empty() and movement.get("waiting_need_id","")==need.id)
			var safe: bool=x.space.public_areas.safe_wait(x.world,v.actor_id,1,cell)
			trace.append({"tick":x.world.sim_tick,"cell":cell.duplicate(),"safe":safe,"paused":ticket.pause_reasons.has("need_service"),"move":movement.duplicate(true)})
			if return_start.is_empty():
				return_start={"tick":x.world.sim_tick,"cell":cell.duplicate(),"safe":safe,"scope":x.g._return_scope(x.world,v),"point":x.g.return_point(x.world,v)}
		if actual_use and need.is_empty():
			returned=x.space.public_areas.safe_wait(x.world,v.actor_id,1,cell) and x.g.return_allows(x.world,v,1,cell) and not x.world.facts.moves.has(v.actor_id) and ticket.pause_reasons.is_empty()
			break
	var final: Dictionary=x.g.state(x.world,v.id).duplicate(true)
	var edits_applied: bool=edits.size()==2 and edits.all(func(r: Dictionary)->bool:return r.accepted) and not x.world.facts.facilities.has("guide") and not x.world.facts.facilities.has("diagnosis")
	var unsafe_start: bool=not return_start.is_empty() and not return_start.safe and return_start.scope.is_empty() and not return_start.point.is_empty()
	var no_false_guidance: bool=final.receipts==before.receipts and final.get("phase","")=="seek" and final.get("target_id","").is_empty() and int(final.get("arrived_seq",-1))<0
	var row: Dictionary={"case":"guided_need_return_without_desk_or_destination","ok":reached and before.receipts.size()==1 and actual_use and edits_applied and unsafe_start and owned_return_move and moved_after_use and legal_steps and no_overlap and pauses_preserved and ticket_preserved and returned and no_false_guidance and x.world.validate(_content).is_empty(),"reached_destination":reached,"actual_water_use":actual_use,"edits":edits,"unsafe_return_start":unsafe_start,"return_start":return_start,"owned_return_move":owned_return_move,"moved_after_use":moved_after_use,"legal_steps":legal_steps,"no_overlap":no_overlap,"pause_preserved_until_safe":pauses_preserved,"ticket_preserved":ticket_preserved,"safe_return_and_pause_released":returned,"no_false_guidance":no_false_guidance,"return_trace":trace,"final_tick":x.world.sim_tick,"final_location":x.world.facts.actors[v.actor_id].location.duplicate(true),"final_ticket":x.world.facts.tickets[v.ticket_id].duplicate(true),"final":final,"validation":x.world.validate(_content)}
	_dispose(x);return row

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
