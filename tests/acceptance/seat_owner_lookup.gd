extends "res://tests/acceptance/public_area_use.gd"

# Observe lookup work without substituting occupancy, fit or movement results.
class WaitingProbe extends HospitalWaitingLife:
	var full_occupancy_views: int = 0
	func _occupancy_view(world: WorldState) -> Dictionary:
		full_occupancy_views += 1
		return super._occupancy_view(world)

func run_cases(database: HospitalContent, selected: Array) -> Dictionary:
	_content = database
	var rows: Array = []
	for id: String in selected:
		var row: Dictionary
		match id:
			"SEAT-OWNER-LIFECYCLE": row = _lifecycle()
			"SEAT-OWNER-PROJECTION": row = _projection()
			"SEAT-OWNER-DEFINITIONS": row = _definitions()
			_: return {"ok":false,"error":"Unknown case: "+id}
		row["case"] = id
		rows.append(row)
	return {"ok":not rows.is_empty() and rows.all(func(row: Dictionary)->bool:return row.ok),"cases":rows,"tick_seconds":WorldState.TICK_SECONDS}

func _observe(x: Dictionary) -> void:
	var probe: WaitingProbe = WaitingProbe.new(_content,x.space)
	probe.environment = x.e
	probe.visitors = x.c.visitors
	x.l = probe
	x.p.waiting_life = probe

func _dispose(x: Dictionary) -> void:
	x.a.dispose()
	x.p.waiting_life = null
	x.p.environment = null
	x.l.environment = null
	x.l.visitors = null
	x.c.recruitment = null

func _step_owner(x: Dictionary, visit: Dictionary, dispatch: bool) -> void:
	if dispatch:
		x.l._dispatch_public_seat(x.world,visit,x.world.facts.waiting_life.seats[visit.id])
	x.space.advance(x.world)
	x.l.advance(x.world)
	x.world.facts.sim_tick += 1
	x.world.touch(false)

func _lifecycle() -> Dictionary:
	var x: Dictionary = _areas()
	_observe(x)
	var holder: Dictionary = _visit(x,"holder",[38,74])
	var peer: Dictionary = _visit(x,"peer",[42,74])
	x.world.touch()
	var ticket: Dictionary = x.world.facts.tickets[holder.ticket_id].duplicate(true)
	var request: CommandResult = x.l.execute(x.world,"waiting_select_seat",{"visit_id":holder.id,"facility_id":"west_chair"})
	var checks: Dictionary = {"legal_input":request.accepted and x.world.validate(_content).is_empty(),"unreserved_approach":true,"valid_every_step":true,"actual_arrival":false,"retained_until_clear":true}
	var arrival_tick: int = -1
	for i: int in 200:
		if HospitalWaitingLife.is_seated(x.world,holder.id):
			arrival_tick = x.world.sim_tick
			checks.actual_arrival = x.space.at(x.world,holder.actor_id,1,x.space.facility_layout(x.world,"west_chair").patient_cell)
			break
		checks.unreserved_approach = checks.unreserved_approach and not x.world.facts.adaptations.has("west_chair") and not x.l._occupied(x.world,"west_chair",peer.actor_id)
		_step_owner(x,holder,true)
		checks.valid_every_step = checks.valid_every_step and x.world.validate(_content).is_empty()
	checks.live_owner = x.world.facts.adaptations.get("west_chair",{}).get("actor_id","")==holder.actor_id and x.l._occupied(x.world,"west_chair",peer.actor_id) and not x.l._occupied(x.world,"west_chair",holder.actor_id)
	x.space.begin_dynamic_route_query(x.world)
	checks.scoped_owner = x.l._occupied(x.world,"west_chair",peer.actor_id) and not x.l._occupied(x.world,"west_chair",holder.actor_id)
	x.space.end_route_query()
	checks.no_full_occupancy_view = x.l.full_occupancy_views==0
	var release: CommandResult = x.l.execute(x.world,"waiting_release_seat",{"visit_id":holder.id})
	checks.standing_still_owns = release.accepted and x.world.facts.actors[holder.actor_id].posture=="standing" and not x.world.facts.waiting_life.seats.has(holder.id) and x.l._occupied(x.world,"west_chair",peer.actor_id)
	var before: Dictionary = x.world.freeze()
	var preview: Dictionary = x.l._manual_seat_quote(x.world,peer,"west_chair")
	checks.standing_manual_preview = preview.get("ok",false) and before==x.world.freeze() and x.space._route_queries.is_empty()
	var restored: Dictionary = _restore(x)
	_observe(restored)
	checks.restore_exact = before==restored.world.freeze()
	checks.restore_owner_and_preview = restored.l._occupied(restored.world,"west_chair",peer.actor_id) and restored.l._manual_seat_quote(restored.world,restored.world.facts.visits[peer.id],"west_chair").get("ok",false)
	_dispose(x)
	x = restored
	holder = x.world.facts.visits[holder.id]
	var held_reservation: Dictionary = x.world.facts.adaptations.get("west_chair",{}).duplicate(true)
	var move: String = x.space.request_move(x.world,holder.actor_id,1,[40,74])
	var departed_tick: int = -1
	for i: int in 150:
		var physically_clear: bool = _reservation_clear(x,held_reservation)
		if not x.world.facts.adaptations.has("west_chair"):
			departed_tick = x.world.sim_tick
			checks.retained_until_clear = checks.retained_until_clear and physically_clear
			break
		checks.retained_until_clear = checks.retained_until_clear and x.l._occupied(x.world,"west_chair",peer.actor_id)
		_step_owner(x,holder,false)
		if not _reservation_clear(x,held_reservation):
			checks.retained_until_clear = checks.retained_until_clear and x.world.facts.adaptations.has("west_chair")
		checks.valid_every_step = checks.valid_every_step and x.world.validate(_content).is_empty()
	checks.actual_release = move.is_empty() and not held_reservation.is_empty() and departed_tick>arrival_tick and _reservation_clear(x,held_reservation) and not x.l._occupied(x.world,"west_chair",peer.actor_id)
	checks.ticket_unchanged = ticket==x.world.facts.tickets[holder.ticket_id]
	var result: Dictionary = {"ok":checks.values().all(func(value: Variant)->bool:return bool(value)),"checks":checks,"arrival_tick":arrival_tick,"departed_tick":departed_tick,"manual_preview":preview,"final_validation":x.world.validate(_content)}
	_dispose(x)
	return result

func _reservation_clear(x: Dictionary, reservation: Dictionary) -> bool:
	if reservation.is_empty(): return false
	var participants: Array = [reservation.actor_id]+reservation.staff_ids
	for id: String in participants:
		var actor: Dictionary = x.world.facts.actors[id]
		if actor.location.kind!="floor" or int(actor.location.floor_id)!=int(reservation.floor_id): continue
		for area: Array in reservation.regions:
			if x.space.body_rectangle(actor).intersects(Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3])),false): return false
	return true

func _projection() -> Dictionary:
	var x: Dictionary = _areas()
	var holder: Dictionary = _visit(x,"holder",[36,70])
	var peer: Dictionary = _visit(x,"peer",[42,74])
	var held: bool = _seat_checkpoint(x,holder,"west_chair")
	var repair: Array = x.space.facility_layout(x.world,"west_chair").repair_cell
	var passer: Dictionary = _visit(x,"approaching",repair)
	# A valid before-query input: another body has passage permission and a
	# prospective seat target, neither of which makes it the chair's user.
	x.space.grant_facility_access(x.world,"west_chair",passer.actor_id)
	var intent: Dictionary = x.world.facts.waiting_life.seats[holder.id].duplicate(true)
	intent.id = "seat_"+passer.id
	intent.actor_id = passer.actor_id
	intent.ticket_id = passer.ticket_id
	intent.phase = "local_travel"
	intent.mode = "auto"
	intent.erase("manual_facility_id")
	x.world.facts.waiting_life.seats[passer.id] = intent
	x.world.touch()
	var validation: String = x.world.validate(_content)
	var before: Dictionary = x.world.freeze()
	var blocked: Dictionary = x.l._manual_seat_quote(x.world,peer,"west_chair")
	var checks: Dictionary = {"legal_query_boundary":held and validation.is_empty(),"passage_not_ownership":x.l._occupied(x.world,"west_chair",passer.actor_id),"other_target_body_not_projected_away":not blocked.get("ok",true) and str(blocked.get("reason","")).contains(passer.actor_id),"read_only":before==x.world.freeze(),"closed_scope":x.space._route_queries.is_empty()}
	# Test only the projection predicate above, not a fabricated journey. The
	# body below leaves its real position through the production mover.
	var move: String = x.space.request_move(x.world,passer.actor_id,1,[40,73])
	for i: int in 100:
		if not x.world.facts.moves.has(passer.actor_id): break
		_step_owner(x,holder,false)
	var after: Dictionary = x.l._manual_seat_quote(x.world,peer,"west_chair")
	checks.actual_body_departure_recovers = move.is_empty() and x.space.at(x.world,passer.actor_id,1,[40,73]) and after.get("ok",false)
	checks.target_never_claimed = intent.phase=="local_travel" and x.world.facts.adaptations.get("west_chair",{}).get("actor_id","")==holder.actor_id
	checks.final_valid = x.world.validate(_content).is_empty()
	var result: Dictionary = {"ok":checks.values().all(func(value: Variant)->bool:return bool(value)),"checks":checks,"input_validation":validation,"blocked_quote":blocked,"after_real_departure":after}
	_dispose(x)
	return result

func _definitions() -> Dictionary:
	var rows: Array = []
	for definition_id: String in HospitalWaitingLife.PUBLIC_SEAT_DEFINITIONS:
		var x: Dictionary = _fixture()
		_facility(x,"chair",definition_id,[42,74])
		var at: Array = x.space.facility_layout(x.world,"chair").patient_cell
		var visit: Dictionary = _visit(x,"arrived",at)
		x.world.touch()
		# A lawful input immediately before actual sitting. No remote reservation
		# or simulated approach is claimed by this per-definition contract check.
		var intent: Dictionary = {"id":"seat_"+visit.id,"actor_id":visit.actor_id,"ticket_id":visit.ticket_id,"facility_id":"chair","public_purpose":"seat","mode":"auto","area":x.space.public_areas.for_facility(x.world,"chair"),"phase":"local_travel","continuous_ticks":0,"arrived_tick":0,"started_tick":0,"area_travel_ticks":0}
		x.world.facts.waiting_life.seats[visit.id] = intent
		var input_validation: String = x.world.validate(_content)
		var claimed: bool = x.l._claim_seat(x.world,visit,intent,"chair")
		var reservation: Dictionary = x.world.facts.adaptations.get("chair",{})
		var valid: bool = input_validation.is_empty() and x.world.validate(_content).is_empty()
		rows.append({"definition":definition_id,"ok":valid and claimed and reservation.get("actor_id","")==visit.actor_id and reservation.get("kind","")=="facility" and HospitalWaitingLife.is_seated(x.world,visit.id),"input_validation":input_validation,"final_validation":x.world.validate(_content)})
		_dispose(x)
	return {"ok":rows.all(func(row: Dictionary)->bool:return row.ok),"definitions":rows}
