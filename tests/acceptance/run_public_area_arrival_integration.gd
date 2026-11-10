extends SceneTree
const Areas = preload("res://game/life/public_areas.gd")
class Life extends HospitalWaitingLife:
	var seat_move_requests: int = 0
	func _request_seat_move(world: WorldState, intent: Dictionary, actor_id: String, floor_id: int, cell: Array) -> String:
		seat_move_requests += 1
		return super._request_seat_move(world,intent,actor_id,floor_id,cell)
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var suite: RefCounted = load("res://tests/acceptance/public_area_use.gd").new()
	suite._content = content
	var rows: Array = []
	for variant: String in ["ordinary","blocked_entry","no_chairs","restored_trip"]:
		var blocked: bool = variant=="blocked_entry"
		var x: Dictionary = suite._areas()
		var visit: Dictionary = suite._visit(x,"arrival",[38,90])
		x.space.public_areas = Areas.new(x.space)
		var life: Life = Life.new(content,x.space)
		life.environment = x.e;life.visitors = x.c.visitors
		x.l = life;x.p.waiting_life = life
		x.space.public_areas.prepare_floor_arrivals(x.world,1)
		var area: Dictionary = x.space.public_areas.for_facility(x.world,"west_chair")
		var target: Dictionary = x.space.public_areas.arrival_point(x.world,visit.actor_id,area)
		var blocker: Dictionary = {}
		if blocked:
			var other: Dictionary = x.world.facts.actors[visit.actor_id].duplicate(true)
			other.id = "door_blocker";other.name = "door_blocker";other.location.cell = target.cell.duplicate()
			x.world.facts.actors[other.id] = other
			blocker = {"actor_id":other.id}
			x.space.sync_actor(x.world,blocker.actor_id);x.world.touch(false)
		var after: Dictionary = x.space.public_areas.arrival_point(x.world,visit.actor_id,area)
		var ticket: String = visit.ticket_id
		x.world.facts.sim_tick = 50
		x.l.dispatch(x.world)
		var intent: Dictionary = x.world.facts.waiting_life.seats.get(visit.id,{})
		var departure: bool = intent.get("phase","")=="area_travel" and intent.get("facility_id","")=="" and x.world.facts.adaptations.is_empty()
		if variant=="no_chairs":
			x.world.facts.facilities.west_chair.failed = true
			x.world.facts.facilities.east_chair.failed = true
			x.world.touch(false)
		var restored: bool = variant!="restored_trip"
		var release_requested: bool = false
		var early_seat: bool = false
		var actually_in_area: bool = false
		var first_safe_cell: Array = []
		var first_inside_tick: int = -1
		var first_safe_tick: int = -1
		for tick: int in 500:
			if tick==40 and variant=="restored_trip":
				var before: Dictionary = x.world.freeze()
				x.a.dispose()
				x = suite._restore(x)
				x.space.public_areas = Areas.new(x.space)
				var new_life: Life = Life.new(content,x.space)
				new_life.environment = x.e;new_life.visitors = x.c.visitors
				x.l = new_life;x.p.waiting_life = new_life
				x.space.public_areas.prepare_floor_arrivals(x.world,1)
				visit = x.world.facts.visits[visit.id]
				intent = x.world.facts.waiting_life.seats[visit.id]
				restored = before==x.world.freeze()
			if tick==120 and blocked:
				release_requested = x.space.request_move(x.world,blocker.actor_id,1,[41,72]).is_empty()
			suite._tick_waiting(x)
			var inside: bool = x.space.public_areas.contains(x.world,area,visit.actor_id)
			var safe: bool = x.space.public_areas.safe_wait(x.world,visit.actor_id,1,x.world.facts.actors[visit.actor_id].location.cell)
			if inside and first_inside_tick<0: first_inside_tick = x.world.sim_tick
			if inside and safe and first_safe_cell.is_empty():
				first_safe_cell = x.world.facts.actors[visit.actor_id].location.cell.duplicate()
				first_safe_tick = x.world.sim_tick
			if intent.get("phase","")=="seated":
				early_seat = not inside
				actually_in_area = inside
				break
		var seated: bool = intent.get("phase","")=="seated"
		var stood: bool = intent.get("phase","")=="local_wait" and not x.world.facts.moves.has(visit.actor_id) and x.space.public_areas.contains(x.world,area,visit.actor_id) and x.space.public_areas.safe_wait(x.world,visit.actor_id,1,x.world.facts.actors[visit.actor_id].location.cell)
		var result_ok: bool = stood if variant=="no_chairs" else seated and actually_in_area and not early_seat
		rows.append({"variant":variant,"blocked_entry":blocked,"passed":not target.is_empty() and target==after and departure and result_ok and restored and visit.ticket_id==ticket and int(x.space.query_counts.get("entry_order_builds",0))==0,"safe_local_standing":stood,"restored_without_fact_changes":restored,"target":target,"busy_entry_keeps_region":target==after,"no_remote_claim":departure,"seated_after_real_entry":seated and actually_in_area and not early_seat,"ticket_kept":visit.ticket_id==ticket,"final_intent":intent.duplicate(true),"final_actor":x.world.facts.actors[visit.actor_id].location.duplicate(true),"blocker_release_requested":release_requested,"first_safe_arrival_cell":first_safe_cell,"first_inside_tick":first_inside_tick,"first_safe_tick":first_safe_tick,"finished_tick":x.world.sim_tick,"seat_move_requests":x.l.seat_move_requests,"runtime":_counts(x.space),"preparation":{},"full_order_builds":x.space.query_counts.get("entry_order_builds",0)})
		x.a.dispose()
	rows.append(_deadline_boundary(content,suite))
	rows.append(_foreign_move(content,suite))
	var result: Dictionary = {"passed":rows.all(func(row: Dictionary)->bool:return row.passed),"cases":rows,"scope":"Production public-area arrival and patient movement integration. Six targeted cases only; not full acceptance or performance approval."}
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var file: FileAccess = FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("AREA_ARRIVAL_PROTOTYPE ",result.passed)
	quit(0 if result.passed else 1)

func _deadline_boundary(content: HospitalContent, suite: RefCounted) -> Dictionary:
	var x: Dictionary = suite._areas()
	suite._facility(x,"toilet","FUR07",[39,68],"west")
	x.world.touch()
	var visit: Dictionary = suite._visit(x,"deadline",[38,90])
	x.space.public_areas = Areas.new(x.space)
	var life: Life = Life.new(content,x.space)
	life.environment = x.e;life.visitors = x.c.visitors
	x.l = life;x.p.waiting_life = life
	x.space.public_areas.prepare_floor_arrivals(x.world,1)
	x.l._begin_need(x.world,visit)
	var need: Dictionary = x.world.facts.waiting_life.needs[visit.id]
	var start: int = int(need.started_tick)
	# Declared legal retry boundary. The prior 449 ticks are not claimed as
	# executed; this tests the retained remaining-budget gate and real fallback.
	x.space.cancel_ground_move(x.world,visit.actor_id)
	need.phase = "seek";need.area = {};need.facility_id = ""
	x.world.facts.sim_tick = start+449
	var origin: Array = x.world.facts.actors[visit.actor_id].location.cell.duplicate()
	x.l.dispatch(x.world)
	var rejected: bool = need.phase=="fallback" and need.remaining_ticks==80 and not x.world.facts.moves.has(visit.actor_id)
	var stayed: bool = x.world.facts.actors[visit.actor_id].location.cell==origin and x.space.public_areas.safe_wait(x.world,visit.actor_id,1,origin)
	var anger: float = visit.anger
	for tick: int in 79: suite._tick_waiting(x)
	var before_last: bool = need.phase=="fallback" and need.remaining_ticks==1 and visit.anger==anger
	suite._tick_waiting(x)
	var after: bool = need.phase=="returning" and visit.anger==anger+float(content.balance.amenity_flow.fallback_anger)
	var result: Dictionary = {"variant":"remaining_45_second_budget","passed":rejected and stayed and before_last and after and int(need.started_tick)==start,"late_retry_rejected_by_original_budget":rejected,"no_new_journey_or_unsafe_stop":stayed,"no_early_effect":before_last,"effect_after_real_80_ticks":after,"start_tick_preserved":int(need.started_tick)==start,"origin":origin,"runtime":_counts(x.space),"full_order_builds":x.space.query_counts.get("entry_order_builds",0),"precondition":"Declared retry at original started_tick+449. The regional estimate exceeds the one remaining tick. No prior 449-tick history is claimed; all 80 fallback work ticks execute."}
	x.a.dispose()
	return result

func _foreign_move(_content: HospitalContent, suite: RefCounted) -> Dictionary:
	var x: Dictionary = suite._areas()
	var visit: Dictionary = suite._visit(x,"foreign",[38,75])
	x.space.public_areas = Areas.new(x.space)
	x.space.public_areas.prepare_floor_arrivals(x.world,1)
	var area: Dictionary = x.space.public_areas.for_facility(x.world,"west_chair")
	var request: String = x.space.request_move(x.world,visit.actor_id,1,[41,75])
	var before: Dictionary = x.world.freeze()
	var stopped: bool = x.space.public_areas.try_finish_arrival(x.world,visit.actor_id,area,"waiting_seat_id","seat_foreign")
	var result: Dictionary = {"variant":"unrelated_move_owned_elsewhere","passed":request.is_empty() and not stopped and before==x.world.freeze(),"not_cancelled":not stopped,"all_facts_unchanged":before==x.world.freeze()}
	x.a.dispose()
	return result

func _counts(space: HospitalSpace) -> Dictionary:
	var result: Dictionary = {}
	for key: String in space.query_counts:
		if key.begins_with("public_arrival") or key=="public_wait_local_points": result[key] = space.query_counts[key]
	return result
