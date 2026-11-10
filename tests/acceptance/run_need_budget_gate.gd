extends SceneTree

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var suite: RefCounted = preload("res://tests/acceptance/public_area_use.gd").new()
	suite._content = content
	var rows: Array = []
	for delta: int in [-1,0,1]: rows.append(_boundary(content,suite,delta))
	var result: Dictionary = {"ok":rows.all(func(row: Dictionary)->bool:return row.ok),"cases":rows,"scope":"Declared remaining-budget boundaries around a real region-travel plus busy-service estimate. No fabricated elapsed seek history; accepted journeys must take a real bounded step without facility ownership."}
	FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("NEED_BUDGET_GATE ",result.ok)
	quit(0 if result.ok else 1)

func _boundary(content: HospitalContent, suite: RefCounted, delta: int) -> Dictionary:
	var x: Dictionary = suite._areas()
	suite._facility(x,"toilet","FUR07",[39,68],"west")
	x.world.touch()
	var holder: Dictionary = suite._visit(x,"holder",x.space.facility_layout(x.world,"toilet").patient_cell)
	var visit: Dictionary = suite._visit(x,"budget",[38,90])
	x.l._begin_need(x.world,holder)
	var busy: Dictionary = x.world.facts.waiting_life.needs[holder.id]
	var selected: Dictionary = x.space.public_areas.select(x.world,visit.actor_id,["FUR07","AE03"],["","waiting"],"toilet")
	var estimate: int = int(selected.start_ticks)
	var queue: int = int(busy.remaining_ticks)
	x.l._begin_need(x.world,visit)
	var need: Dictionary = x.world.facts.waiting_life.needs[visit.id]
	var cancelled: bool = x.space.cancel_ground_move(x.world,visit.actor_id)
	need.phase = "seek";need.area = {};need.facility_id = "";need.arrived_tick = -1
	var budget: int = ceili(float(content.balance.amenity_flow.seek_seconds)/WorldState.TICK_SECONDS)
	var remaining: int = estimate+delta
	x.world.facts.sim_tick = int(need.started_tick)+budget-remaining
	x.world.touch(false)
	var ticket: String = visit.ticket_id
	var input_validation: String = x.world.validate(content)
	var start: int = int(need.started_tick)
	var origin: Array = x.world.facts.actors[visit.actor_id].location.cell.duplicate()
	var readback: Dictionary = x.space.public_areas.select(x.world,visit.actor_id,["FUR07","AE03"],["","waiting"],"toilet")
	x.l._dispatch_need(x.world,visit,need)
	var accepted: bool = delta>=0
	var outcome: bool = need.phase=="area_travel" and x.world.facts.moves.has(visit.actor_id) if accepted else need.phase=="fallback" and need.remaining_ticks==80 and not x.world.facts.moves.has(visit.actor_id)
	var no_claim: bool = not x.world.facts.adaptations.has("toilet") or x.world.facts.adaptations.toilet.get("actor_id","")!=visit.actor_id
	var real_step: bool = true
	if accepted:
		x.space.advance(x.world)
		var after: Array = x.world.facts.actors[visit.actor_id].location.cell
		var distance: float = Vector2(float(after[0]),float(after[1])).distance_to(Vector2(float(origin[0]),float(origin[1])))
		real_step = distance>0.0 and distance<=x.space.walking_speed(x.world.facts.actors[visit.actor_id])*WorldState.TICK_SECONDS+0.001
	var stable: bool = int(need.started_tick)==start and visit.ticket_id==ticket and x.world.facts.tickets[ticket].pause_reasons.get("need_service","")==need.id
	var output_validation: String = x.world.validate(content)
	var row: Dictionary = {"case":"remaining_estimate_%+d"%delta,"ok":cancelled and busy.phase=="using" and queue==80 and estimate==int(selected.travel_ticks)+queue and int(readback.start_ticks)==estimate and remaining>0 and remaining<budget and outcome and no_claim and real_step and stable and input_validation.is_empty() and output_validation.is_empty(),"region_travel_ticks":selected.travel_ticks,"busy_service_ticks":queue,"start_estimate":estimate,"remaining_ticks":remaining,"expected_accept":accepted,"phase":need.phase,"actual_step_if_accepted":real_step,"no_remote_facility_claim":no_claim,"original_ticket_and_clock":stable,"input_validation":input_validation,"output_validation":output_validation}
	x.a.dispose()
	return row
