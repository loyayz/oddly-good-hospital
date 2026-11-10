extends "res://tests/acceptance/public_area_use.gd"

# Reusable, read-only production-code probe. Only isolated fixture worlds change.
# Every arrival below follows request_move and fixed 0.1-second movement steps.
# No actor position, facing, support exit, local_move, or arrival milestone is
# fabricated after the initial fixture declarations.
func run_entry_ownership_edges(database: HospitalContent) -> Dictionary:
	_content = database
	var rows: Array = [_single_port(false),_single_port(true),_support_departure(),_near_goal_detour()]
	for side: String in ["north","south","west","east"]: rows.append(_explicit_port(side))
	var ok: bool = true
	for row: Dictionary in rows: ok = ok and row.ok
	return {"ok":ok,"cases":rows,"scope":"Real movement and support transitions. The outside-approach case explicitly exercises a helper-produced alternate candidate, not the production selector's preferred choice."}

func _edge_actor(x: Dictionary, id: String, species_id: String, cell: Array) -> Dictionary:
	var actor: Dictionary = {"id":id,"name":id,"species_id":species_id,"facing":0.0,"posture":"standing","location":{"kind":"floor","floor_id":1,"cell":cell.duplicate(),"height_m":0.0}}
	for binding: Dictionary in _content.catalog.treatment_bindings:
		if binding.species_id==species_id:
			actor.body_binding_id = binding.id
			break
	x.world.facts.actors[id] = actor
	x.world.touch()
	return actor

func _edge_tick(x: Dictionary, ids: Array) -> String:
	var before: Dictionary = {}
	var rectangles: Dictionary = {}
	for id: String in ids:
		before[id] = ConvoyTrail.point(x.world.facts.actors[id].location.cell)
		rectangles[id] = x.space.body_rectangle(x.world.facts.actors[id])
	x.space.advance(x.world)
	x.world.facts.sim_tick += 1
	x.world.touch(false)
	for index: int in ids.size():
		var id: String = ids[index]
		var actor: Dictionary = x.world.facts.actors[id]
		var actual: Vector2 = ConvoyTrail.point(actor.location.cell)
		if actual.distance_to(before[id])>x.space.walking_speed(actor)*WorldState.TICK_SECONDS+0.0001: return "Movement budget exceeded: "+id
		var after: Rect2 = x.space.body_rectangle(actor)
		for other_index: int in range(index+1,ids.size()):
			var other: String = ids[other_index]
			var other_after: Rect2 = x.space.body_rectangle(x.world.facts.actors[other])
			if after.intersects(other_after,false) or BodySweep.intersects(rectangles[id],after,rectangles[other],other_after): return "Body/swept overlap: "+id+"/"+other
	return x.world.validate(_content)

func _edge_drive(x: Dictionary, actor_id: String, target: Array, area: Dictionary = {}, ids: Array = [], maximum: int = 150) -> Dictionary:
	if ids.is_empty(): ids = [actor_id]
	var request: String = x.space.request_move(x.world,actor_id,1,target)
	var errors: Array = []
	var steps: int = 0
	var first_contains: int = -1
	var local_seen: bool = false
	var support_seen: bool = false
	var lying_owned: bool = false
	var standing_tick: int = -1
	var trace: Array = []
	for tick: int in maximum:
		var movement: Dictionary = x.world.facts.moves.get(actor_id,{})
		if movement.is_empty(): break
		var actor: Dictionary = x.world.facts.actors[actor_id]
		local_seen = local_seen or movement.has("local_move")
		var cursor: int = int(movement.get("cursor",0))
		var path: Array = movement.get("path",[])
		if cursor>=0 and cursor<path.size() and path[cursor].kind=="support_exit": support_seen = true
		# actor_id is an existing movement identity; no ownership marker is injected.
		if actor.posture=="lying" and not area.is_empty(): lying_owned = lying_owned or x.space.public_areas.owns_arrival(x.world,actor_id,area,"actor_id",actor_id)
		var error: String = _edge_tick(x,ids)
		steps += 1
		var inside: bool = not area.is_empty() and x.space.public_areas.contains(x.world,area,actor_id)
		if inside and first_contains<0: first_contains = steps
		if actor.posture=="standing" and standing_tick<0: standing_tick = steps
		if tick<3 or inside and trace.size()<8 or not x.world.facts.moves.has(actor_id): trace.append({"tick":steps,"cell":actor.location.cell.duplicate(),"posture":actor.posture,"facing":actor.facing,"contains":inside})
		if not error.is_empty():
			errors.append(error)
			break
	var actor: Dictionary = x.world.facts.actors[actor_id]
	return {"request":request,"steps":steps,"errors":errors,"completed":not x.world.facts.moves.has(actor_id),"at_target":x.space.at(x.world,actor_id,1,target),"contains":not area.is_empty() and x.space.public_areas.contains(x.world,area,actor_id),"first_contains_tick":first_contains,"local_seen":local_seen,"support_seen":support_seen,"lying_owned":lying_owned,"standing_tick":standing_tick,"final_cell":actor.location.cell.duplicate(),"final_facing":actor.facing,"final_posture":actor.posture,"trace":trace}

func _edge_journey_ok(result: Dictionary) -> bool:
	return result.request.is_empty() and result.errors.is_empty() and result.completed and result.at_target

func _single_port(outside_alternative: bool) -> Dictionary:
	var x: Dictionary = _fixture()
	HospitalFactory._add_room(x.world,{"id":"west","type":"rest","anchor":[34,66],"size":[10,12],"door":{"definition_id":"DR03","offset":3}},_content)
	var actor: Dictionary = _edge_actor(x,"probe","S62",[37,81])
	var initial_validation: String = x.world.validate(_content)
	# Both trips finish normally. The second route's fractional departure stub
	# is its entire journey, leaving a real diagonal facing at integer [37,77].
	var predecessor: Dictionary = _edge_drive(x,actor.id,[37.4,76.91])
	var stub: Dictionary = _edge_drive(x,actor.id,[37,77])
	x.space.public_areas._ensure(x.world,1)
	var area: Dictionary = x.space.public_areas._cell_region(1,Vector2i(37,76)).ref
	var area_record: Dictionary = x.space.public_areas.region(x.world,area)
	var geometry: Dictionary = x.space.public_areas._entry_geometry_view(x.world,actor,area_record)
	var ports: Array = x.space.public_areas._arrival_points(x.world,actor,area_record,geometry)
	var targets: Array = x.space.public_areas._arrival_targets(x.world,actor,area_record,Vector2i(37,77),geometry.geometry)
	var before_contains: bool = x.space.public_areas.contains(x.world,area,actor.id)
	var before_rectangle: Rect2 = x.space.body_rectangle(actor)
	var budget4: Dictionary = x.space.public_areas.arrival_point(x.world,actor.id,area,4)
	var budget5: Dictionary = x.space.public_areas.arrival_point(x.world,actor.id,area,5)
	var target: Dictionary = x.space.public_areas.arrival_point(x.world,actor.id,area)
	var extra: Dictionary = {}
	var outside_ok: bool = true
	if outside_alternative:
		var outside: Dictionary = {}
		for candidate: Dictionary in targets:
			if int(candidate.remaining_ticks)>0:
				outside = candidate
				break
		if outside.is_empty():
			outside_ok = false
		else:
			# Branch coverage: physically execute this real helper-produced option.
			# It is not claimed to be the selector's preferred option in this world.
			var departure: Dictionary = _edge_drive(x,actor.id,outside.cell,area)
			outside_ok = _edge_journey_ok(departure) and not departure.contains and int(outside.remaining_ticks)==5
			target = x.space.public_areas.arrival_point(x.world,actor.id,area)
			extra = {"helper_alternate":outside,"departure":departure,"next_selected_entry":target}
	var arrival: Dictionary = {} if target.is_empty() else _edge_drive(x,actor.id,target.cell,area)
	var final_point: Dictionary = x.space.public_areas.arrival_point(x.world,actor.id,area)
	var checks: Dictionary = {"legal_input":initial_validation.is_empty(),"real_fractional_predecessor":_edge_journey_ok(predecessor),"real_diagonal_stub":_edge_journey_ok(stub) and not before_contains,"one_entry_origin":ports==[Vector2i(37,77)],"budget4_rejected":budget4.is_empty(),"budget5_retained":not budget5.is_empty() and int(budget5.travel_ticks)==5,"outside_alternative":outside_ok,"actual_arrival":not arrival.is_empty() and _edge_journey_ok(arrival) and arrival.contains,"no_zero_trip_loop":final_point.get("inside",false) and int(final_point.get("travel_ticks",-1))==0,"standing":actor.posture=="standing","final_validation":x.world.validate(_content).is_empty()}
	if outside_alternative and not arrival.is_empty(): checks.remaining_estimate_reaches_region = int(arrival.first_contains_tick)<=int(extra.helper_alternate.remaining_ticks)
	var ok: bool = true
	for value: bool in checks.values(): ok = ok and value
	var result: Dictionary = {"case":"single_port_outside_approach" if outside_alternative else "single_port_diagonal_stub_budget","ok":ok,"checks":checks,"input_validation":initial_validation,"predecessor":predecessor,"stub":stub,"prearrival_rectangle":str(before_rectangle),"entry_origins":str(ports),"targets":targets,"budget5":budget5,"arrival":arrival,"extra":extra}
	x.a.dispose()
	return result

func _support_departure() -> Dictionary:
	var x: Dictionary = _fixture({"sleeper":"nurse"})
	var room: String = _room(x)
	_facility(x,"bed","SE04",[43,75],room)
	_position(x,"sleeper",[43,80])
	var actor: Dictionary = x.world.facts.actors.sleeper
	var staff: Dictionary = x.world.facts.staff.sleeper
	# Legal pre-dispatch need boundary, not fabricated sleeping/completion.
	staff.awake_ticks = 13500
	staff.energy = 50.0
	staff.stress_milli = 50000
	var initial_validation: String = x.world.validate(_content)
	var reached_sleep: bool = false
	var sleep_steps: int = 0
	var errors: Array = []
	for tick: int in 100:
		x.w.dispatch(x.world)
		var sleeping_now: bool = staff.life_task.phase=="sleep"
		var previous: Dictionary = {actor.id:actor.location.duplicate(true)}
		var error: String = _edge_tick(x,[actor.id])
		x.w.advance(x.world,{},previous)
		sleep_steps += 1
		if not error.is_empty(): errors.append(error); break
		# Includes the genuine movement-owner cleanup in this fixed step.
		if sleeping_now:
			reached_sleep = true
			break
	var sleeping: Dictionary = actor.duplicate(true)
	x.space.public_areas._ensure(x.world,1)
	var area: Dictionary = x.space.public_areas._cell_region(1,Vector2i(43,80)).ref
	var sleeping_facts: Dictionary = x.world.freeze()
	var waiting: Dictionary = x.space.public_areas.waiting_point(x.world,actor.id,area)
	var arrival: Dictionary = x.space.public_areas.arrival_point(x.world,actor.id,area)
	var selected: Dictionary = x.space.public_areas.select(x.world,actor.id,[],["","rest"],"waiting")
	var pending_exit: bool = waiting.is_empty() and arrival.is_empty() and selected.is_empty() and sleeping_facts==x.world.freeze()
	var interrupted: CommandResult = x.w.execute(x.world,"interrupt_staff_rest",{"staff_id":actor.id,"reason":"remodel"})
	# Repeating the unchanged real destination only preserves the existing move.
	var departure: Dictionary = _edge_drive(x,actor.id,[43,80],area)
	var checks: Dictionary = {"legal_input":initial_validation.is_empty(),"real_sleep_entry":reached_sleep and sleeping.posture=="lying" and sleeping.support_facility_id=="bed","fixed_sleep_steps_valid":errors.is_empty(),"interrupt_accepted":interrupted.accepted,"actual_support_exit":departure.support_seen,"lying_never_owned_arrival":not departure.lying_owned,"real_upright_return":_edge_journey_ok(departure) and departure.final_posture=="standing" and departure.contains,"support_cleared":not actor.has("support_facility_id") and float(actor.location.height_m)==0.0,"final_validation":x.world.validate(_content).is_empty()}
	checks.public_destinations_wait_for_real_support_exit = pending_exit
	var ok: bool = true
	for value: bool in checks.values(): ok = ok and value
	var result: Dictionary = {"case":"real_sleep_support_exit","ok":ok,"checks":checks,"input_validation":initial_validation,"sleep_steps":sleep_steps,"sleeping":sleeping,"errors":errors,"departure":departure}
	x.a.dispose()
	return result

func _near_goal_detour() -> Dictionary:
	var x: Dictionary = _fixture()
	HospitalFactory._add_room(x.world,{"id":"west","type":"rest","anchor":[34,66],"size":[10,12],"door":{"definition_id":"DR05","offset":3}},_content)
	var actor: Dictionary = _edge_actor(x,"probe","S02",[38,81])
	_edge_actor(x,"blocker","S49",[38,77.6])
	var initial_validation: String = x.world.validate(_content)
	x.space.public_areas._ensure(x.world,1)
	var area: Dictionary = x.space.public_areas._cell_region(1,Vector2i(38,76)).ref
	var entry: Dictionary = x.space.public_areas.arrival_point(x.world,actor.id,area)
	var trip: Dictionary = {} if entry.is_empty() else _edge_drive(x,actor.id,entry.cell,area,[actor.id,"blocker"],250)
	var checks: Dictionary = {"legal_input":initial_validation.is_empty(),"entry_exists":not entry.is_empty(),"real_local_detour":trip.get("local_seen",false),"actual_contained_arrival":not trip.is_empty() and _edge_journey_ok(trip) and trip.contains,"fixed_blocker_unchanged":x.space.at(x.world,"blocker",1,[38,77.6]) and not x.world.facts.moves.has("blocker"),"final_validation":x.world.validate(_content).is_empty()}
	var ok: bool = true
	for value: bool in checks.values(): ok = ok and value
	var result: Dictionary = {"case":"near_entry_real_local_detour","ok":ok,"checks":checks,"input_validation":initial_validation,"entry":entry,"trip":trip}
	x.a.dispose()
	return result

# BuildService creates the actual complete wall_edges and matching real door.
# All four orientations exercise arrival geometry independently of Factory's
# legacy rectangular blocked-cell room representation.
func _explicit_port(side: String) -> Dictionary:
	var x: Dictionary = _fixture()
	var builder: BuildService = BuildService.new(_content,x.space)
	var built: CommandResult = builder.execute(x.world,"build_room",{"id":"ports","room_type_id":"rest","floor_id":1,"origin":[40,70],"size":[8,8],"door":{"definition_id":"DR04","edge":side,"offset":3}})
	if not built.accepted:
		x.a.dispose()
		return {"case":"explicit_"+side,"ok":false,"build":built.to_record()}
	var starts: Dictionary = {"north":[43,67],"south":[43,81],"west":[37,73],"east":[51,73]}
	var actor: Dictionary = _edge_actor(x,"walker","S49",starts[side])
	actor.facing = PI/4.0
	x.space.sync_actor(x.world,actor.id)
	x.space.public_areas._ensure(x.world,1)
	var area: Dictionary = x.space.public_areas._cell_region(1,Vector2i(43,73)).ref
	var point: Dictionary = x.space.public_areas.arrival_point(x.world,actor.id,area)
	var journey: Dictionary = {} if point.is_empty() else _edge_drive(x,actor.id,point.cell,area)
	var validation: String = builder.validate(x.world)
	var full_order: int = int(x.space.query_counts.get("entry_order_builds",0))
	var ok: bool = not point.is_empty() and _edge_journey_ok(journey) and journey.contains and validation.is_empty() and full_order==0
	var result: Dictionary = {"case":"explicit_"+side,"ok":ok,"point":point,"real_move":journey,"build_validation":validation,"full_order":full_order}
	x.a.dispose()
	return result
