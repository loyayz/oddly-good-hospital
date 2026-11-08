extends RefCounted

class ObservedMovement extends HospitalMovement:
	var observe: Callable
	func _init(geometry: HospitalSpace) -> void: super(geometry)
	func _move_step(world: WorldState, actor: Dictionary, movement: Dictionary, segment: Dictionary) -> MotionResult:
		var result: MotionResult = super._move_step(world,actor,movement,segment)
		if actor.id=="sweeper" and result.actual_motion!=Vector2.ZERO and observe.is_valid(): observe.call()
		return result

# Calculation boundaries from navigation selection section 7. Real movement
# is executed for sweep expiry; the other cases claim no journey or arrival.
func run(content: HospitalContent, selected: String = "") -> Dictionary:
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new()
	suite.content = content
	var names: Array = ["strict_floor_compound","permissions_and_owners","body_and_sweep"]
	if not selected.is_empty() and not selected in names: return {"ok":false,"error":"Unknown case: "+selected}
	var rows: Array = []
	var ok: bool = true
	for name: String in names:
		if not selected.is_empty() and name!=selected: continue
		var started: int = Time.get_ticks_usec()
		var row: Dictionary = call("_"+name,suite)
		row.elapsed_us = Time.get_ticks_usec()-started
		rows.append(row)
		ok = ok and row.ok
	return {"ok":ok,"rows":rows}

func _row(name: String, checks: Dictionary, details: Dictionary = {}) -> Dictionary:
	var ok: bool = true
	for value: bool in checks.values(): ok = ok and value
	return {"name":name,"ok":ok,"checks":checks,"details":details}

func _strict_floor_compound(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._history_height(sim,2)
	suite._add_actor(sim,"subject","S49",[38,80])
	suite._add_actor(sim,"blocker","S49",[40,80])
	suite._add_actor(sim,"other_floor","S49",[44,80],2)
	var before: Dictionary = sim.world.freeze()
	var prepared: Dictionary = sim.space._dynamic_route_query(sim.world,sim.world.facts.actors.subject,1,[],{})
	var rect: Rect2 = sim.space.body_rectangle(sim.world.facts.actors.blocker)
	var touching: Rect2 = Rect2(Vector2(rect.end.x,rect.position.y),Vector2(0.25,rect.size.y))
	var overlapping: Rect2 = Rect2(touching.position-Vector2(0.0001,0),touching.size)
	var other: Rect2 = sim.space.body_rectangle(sim.world.facts.actors.other_floor)
	var checks: Dictionary = {
		"legal_world":sim.world.validate(suite.content).is_empty(),
		"strict_edge_touch_is_clear":not prepared.index.intersects(1,touching,""),
		"positive_overlap_is_blocked":prepared.index.intersects(1,overlapping,""),
		"self_body_excluded":not prepared.index.intersects(1,sim.space.body_rectangle(sim.world.facts.actors.subject),""),
		"other_floor_is_not_imported":not prepared.index.intersects(1,other,""),
		"projection_has_only_requested_floor":not prepared.index.intersects(2,rect,"")
	}
	# Complete compound-record calculation input: its two real rectangles
	# leave a gap. The containing box cannot itself confer a blocked result.
	var regions: Array[Rect2] = [Rect2(40,80,0.25,0.25),Rect2(42,80,0.25,0.25)]
	sim.space._actor_index.update_compound("blocker",1,regions)
	var compound: Dictionary = sim.space._dynamic_route_query(sim.world,sim.world.facts.actors.subject,1,[],{})
	checks.compound_gap_remains_clear = not compound.index.intersects(1,Rect2(41,80,0.25,0.25),"")
	checks.both_compound_regions_preserved = compound.index.intersects(1,regions[0],"") and compound.index.intersects(1,regions[1],"")
	checks.world_facts_unchanged = before==sim.world.freeze()
	sim.dispose()
	return _row("strict_floor_compound",checks)

func _permissions_and_owners(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var placed: CommandResult = suite._command(sim,"build_facility",{"id":"reserved_machine","definition_id":"M37","floor_id":1,"cell":[42,76]})
	if not placed.accepted: return _row("permissions_and_owners",{"fixture":false},{"result":placed.to_record()})
	suite._add_actor(sim,"subject","S49",[38,80])
	suite._add_actor(sim,"patient","S49",[34,80])
	suite._add_actor(sim,"replacement","S49",[36,80])
	var reason: String = sim.space.reserve_facility(sim.world,"reserved_machine","patient","patient")
	var actor: Dictionary = sim.world.facts.actors.subject
	var allowed: Array = ["subject","patient"]
	var denied: Array = ["subject","replacement"]
	var original: Dictionary = sim.space._dynamic_route_query(sim.world,actor,1,allowed,{"patient":[1,0]})
	var replacement: Dictionary = sim.space._dynamic_route_query(sim.world,actor,1,denied,{"replacement":[1,0]})
	var area: Array = sim.world.facts.adaptations.reserved_machine.regions[0]
	var rectangle: Rect2 = Rect2(float(area[0]),float(area[1]),float(area[2]),float(area[3]))
	var checks: Dictionary = {
		"real_reservation_created":reason.is_empty(),
		"legal_world":sim.world.validate(suite.content).is_empty(),
		"member_permission_is_applied":not original.index.intersects(1,rectangle,""),
		"replacement_does_not_inherit_permission":replacement.index.intersects(1,rectangle,""),
		"permission_projections_are_distinct":original.index!=replacement.index
	}
	var projected: WorldState = WorldState.new(sim.world.freeze())
	projected.facts.actors = sim.world.facts.actors.duplicate()
	projected.facts.actors.replacement = sim.world.facts.actors.replacement.duplicate(true)
	projected.facts.actors.replacement.location.kind = "outside"
	sim.space.begin_actor_exclusion_query(sim.world,projected,["replacement"])
	var excluded: Dictionary = sim.space._dynamic_route_query(projected,projected.facts.actors.subject,1,[],{})
	var peer: Rect2 = sim.space.body_rectangle(sim.world.facts.actors.replacement)
	checks.projected_departure_excludes_only_that_body = not excluded.index.intersects(1,peer,"")
	sim.space.end_route_query()
	var restored: Dictionary = sim.space._dynamic_route_query(sim.world,actor,1,[],{})
	checks.source_owner_rebuild_restores_body = restored.index.intersects(1,peer,"")
	var same_revision: WorldState = WorldState.new(sim.world.freeze())
	same_revision.facts.actors.replacement.location.cell = [52,90]
	var rebound: Dictionary = sim.space._dynamic_route_query(same_revision,same_revision.facts.actors.subject,1,[],{})
	checks.equal_revision_other_facts_do_not_borrow_projection = not rebound.index.intersects(1,peer,"")
	sim.dispose()
	return _row("permissions_and_owners",checks)

func _body_and_sweep(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"subject","S03",[38.125,80.375])
	suite._add_actor(sim,"blocker","S49",[40,80])
	suite._add_actor(sim,"sweeper","S49",[46,80])
	var actor: Dictionary = sim.world.facts.actors.subject
	var checks: Dictionary = {"legal_world":sim.world.validate(suite.content).is_empty()}
	var comparisons: int = 0
	for posture: String in ["standing","lying"]:
		actor.posture = posture
		for facing: float in [0.0,0.125,PI*0.5]:
			actor.facing = facing
			sim.world.touch(false)
			var prepared: Dictionary = sim.space._dynamic_route_query(sim.world,actor,1,[],{})
			checks[posture+"_body_mode"] = prepared.has("shape") if posture=="standing" else not prepared.has("shape")
			var equal: bool = true
			for y: int in range(79,83):
				for x: int in range(37,43):
					for direction: Vector2i in [Vector2i.ZERO,Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN]:
						var from: Vector2i = Vector2i(x,y)
						var raw: bool = sim.space._unit_step_dynamic_clear(sim.world,actor,1,from,from+direction,[],{})
						var projected: bool = sim.space._unit_step_dynamic_clear(sim.world,actor,1,from,from+direction,[],{},prepared)
						equal = equal and raw==projected
						comparisons += 1
			checks[posture+"_"+str(facing)+"_exact_edge_results"] = equal
	actor.posture = "standing"
	actor.facing = 0.0
	sim.world.touch(false)
	var prior: Rect2 = sim.space.body_rectangle(sim.world.facts.actors.sweeper)
	var observation: Dictionary = {}
	var movement: ObservedMovement = ObservedMovement.new(sim.space)
	sim.space.movement = movement
	movement.observe = func() -> void:
		var current: Rect2 = sim.space.body_rectangle(sim.world.facts.actors.sweeper)
		var strip: Rect2 = Rect2(prior.position,Vector2(minf(0.05,current.position.x-prior.position.x),prior.size.y))
		var during: Dictionary = sim.space._dynamic_route_query(sim.world,actor,1,[],{})
		var expected_step: float = minf(1.0,float(suite.content.balance.movement_speeds[str(sim.space.clearance(sim.world.facts.actors.sweeper))])*WorldState.TICK_SECONDS)
		observation.merge({"strip":strip,"actual_step":absf(current.position.x-prior.position.x-expected_step)<0.00001,"left_strip":not current.intersects(strip,false),"sweep_retained":during.index.intersects(1,strip,"")})
		var projected_world: WorldState = WorldState.new(sim.world.freeze())
		projected_world.facts.actors = sim.world.facts.actors.duplicate()
		projected_world.facts.actors.sweeper = sim.world.facts.actors.sweeper.duplicate(true)
		projected_world.facts.actors.sweeper.location.kind = "outside"
		sim.space.begin_actor_exclusion_query(sim.world,projected_world,["sweeper"])
		var excluded: Dictionary = sim.space._dynamic_route_query(projected_world,projected_world.facts.actors.subject,1,[],{})
		observation.exclusion_keeps_sweep = excluded.index.intersects(1,strip,"")
		sim.space.end_route_query()
	sim.space.request_move(sim.world,"sweeper",1,[47,80])
	suite._movement_tick(sim)
	checks.observed_after_real_commit_before_phase_end = not observation.is_empty()
	checks.real_step_moved_without_teleport = observation.get("actual_step",false)
	checks.current_body_has_left_strip = observation.get("left_strip",false)
	checks.accepted_sweep_retains_strip = observation.get("sweep_retained",false)
	checks.projected_departure_keeps_accepted_sweep = observation.get("exclusion_keeps_sweep",false)
	var after: Dictionary = sim.space._dynamic_route_query(sim.world,actor,1,[],{})
	checks.phase_end_expires_prior_sweep = not observation.is_empty() and not after.index.intersects(1,observation.strip,"")
	movement.observe = Callable()
	sim.dispose()
	return _row("body_and_sweep",checks,{"edge_comparisons":comparisons})
