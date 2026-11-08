extends "res://tests/acceptance/floor_guidance.gd"
func run_same_room(content: HospitalContent)->Dictionary:
	_content=content
	var cases: Array=[]
	for mode: String in ["busy","doctor_unavailable","stable","release","other_room"]:cases.append(_actual_ready_case(mode))
	return {"passed":not cases.any(func(row: Dictionary)->bool:return not row.ok),"cases":cases}
func _guide_only_tick(x: Dictionary, visits: Array)->void:
	x.g.dispatch(x.world)
	for v: Dictionary in visits:x.g.prepare(x.world,v,x.world.facts.tickets[v.ticket_id])
	x.space.advance(x.world);x.g.advance(x.world)
	x.world.facts.sim_tick+=1;x.world.touch(false)
func _actual_ready_case(mode: String)->Dictionary:
	var x: Dictionary=_base(true)
	x.world.facts.staff.doctor.on_shift=false
	var a: Dictionary=_visit(x,"earlier",[49,86])
	var b: Dictionary=_visit(x,"later",[52,88])
	var visits: Array=[a,b]
	for tick: int in 1200:
		_guide_only_tick(x,visits)
		if x.g.state(x.world,a.id).get("phase","")=="ready" and x.g.state(x.world,b.id).get("phase","")=="ready":break
	var initial: Array=[x.g.state(x.world,a.id).duplicate(true),x.g.state(x.world,b.id).duplicate(true)]
	var real_ready: bool=initial[0].phase=="ready" and initial[1].phase=="ready" and initial[0].receipts.size()==1 and initial[1].receipts.size()==1 and initial[0].target_id=="diagnosis" and initial[1].target_id=="diagnosis"
	var room: String="clinic"
	if mode=="other_room":
		HospitalFactory._add_room(x.world,{"id":"other_clinic","type":"gp","anchor":[47,66],"size":[8,12],"door":{"definition_id":"DR04","offset":3}},_content)
		x.world.facts.departments.units.general.room_ids.append("other_clinic")
		room="other_clinic"
	_facility(x,"second_table","FUR02",[50,69] if mode=="other_room" else [40,74],room)
	x.world.facts.staff.doctor.on_shift=mode!="doctor_unavailable"
	x.world.touch()
	var held: bool=mode!="stable"
	var holder: Dictionary={};var hold_reason: String=""
	if held:
		var original: Dictionary=x.space.facility_layout(x.world,"diagnosis")
		holder=_visit(x,"physical_holder",original.patient_cell)
		hold_reason=x.space.reserve_facility(x.world,"diagnosis",holder.actor_id,holder.actor_id)
	var actual_hold: bool=not held or (hold_reason.is_empty() and x.world.facts.adaptations.get("diagnosis",{}).get("actor_id","")==holder.actor_id)
	var old_ready: String=x.g._ready_target(x.world,a,x.world.facts.tickets[a.ticket_id],"diagnosis")
	var new_ready: String=x.g._ready_target(x.world,a,x.world.facts.tickets[a.ticket_id],"second_table")
	var receipts_preserved: bool=true;var sequences_preserved: bool=true;var no_overlap: bool=true
	var saw_reset: bool=false;var switched: bool=false
	var trace: Array=[]
	for tick: int in 220:
		_guide_only_tick(x,visits)
		for i: int in visits.size():
			var v: Dictionary=visits[i];var row: Dictionary=x.g.state(x.world,v.id)
			receipts_preserved=receipts_preserved and row.receipts.size()==initial[i].receipts.size()
			sequences_preserved=sequences_preserved and row.arrived_seq==initial[i].arrived_seq
			no_overlap=no_overlap and not _overlap(x,v.actor_id)
		var current: Dictionary=x.g.state(x.world,a.id)
		if trace.is_empty() or trace.back().target!=current.target_id or trace.back().phase!=current.phase:trace.append({"tick":tick,"target":current.target_id,"phase":current.phase,"sequence":current.arrived_seq,"receipts":current.receipts.size()})
		if current.target_id=="second_table":
			switched=true;saw_reset=current.phase not in ["ready","destination"] or int(current.arrived_seq)<0
			if mode=="other_room":break
		if mode in ["busy","release"] and switched and current.phase=="ready":break
	var released: bool=true;var release_reason: String="";var release_recovered: bool=true
	if mode=="release":
		release_reason=x.space.request_move(x.world,holder.actor_id,1,[42,75])
		for tick: int in 200:
			x.space.advance(x.world);x.world.facts.sim_tick+=1;x.world.touch(false)
			x.space.release_adaptations(x.world)
			if not x.world.facts.moves.has(holder.actor_id) and not x.world.facts.adaptations.has("diagnosis"):break
		released=release_reason.is_empty() and x.space.at(x.world,holder.actor_id,1,[42,75]) and not x.world.facts.adaptations.has("diagnosis")
		release_recovered=x.g._ready_target(x.world,a,x.world.facts.tickets[a.ticket_id],"diagnosis")=="diagnosis"
		for tick: int in 160:_guide_only_tick(x,visits)
	var final: Array=[x.g.state(x.world,a.id).duplicate(true),x.g.state(x.world,b.id).duplicate(true)]
	var target_ok: bool=final[0].target_id==("diagnosis" if mode in ["stable","doctor_unavailable"] else "second_table")
	var opportunity: bool=(old_ready.is_empty() and new_ready=="second_table") if mode in ["busy","release","other_room"] else (old_ready=="diagnosis" if mode=="stable" else old_ready.is_empty() and new_ready.is_empty())
	var order_ok: bool=sequences_preserved and final[0].arrived_seq==initial[0].arrived_seq and final[1].arrived_seq==initial[1].arrived_seq
	var behavior: bool=(switched and saw_reset) if mode=="other_room" else (target_ok and receipts_preserved and order_ok and not saw_reset)
	var result: Dictionary={"case":"actual_ready_reselection_"+mode,"ok":real_ready and actual_hold and opportunity and behavior and no_overlap and released and release_recovered and x.world.validate(_content).is_empty(),"actual_ready_setup":real_ready,"initial":initial,"actual_reservation":actual_hold,"hold_reason":hold_reason,"old_table_ready":old_ready,"second_table_ready":new_ready,"switched":switched,"different_room_reset":saw_reset,"receipt_preserved":receipts_preserved,"arrival_sequences_preserved":order_ok,"release_actual":released,"release_reason":release_reason,"original_available_after_physical_release":release_recovered,"no_overlap":no_overlap,"trace":trace,"final":final,"validation":x.world.validate(_content)}
	_dispose(x);return result

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
