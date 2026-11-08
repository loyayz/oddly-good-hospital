extends RefCounted

class ObservedMovement extends HospitalMovement:
	var scopes: Array = []
	func _init(geometry: HospitalSpace) -> void: super(geometry)
	func _detour_path_clear(world: WorldState, actor: Dictionary, movement: Dictionary, path: Array, query: RouteClearance = null, proof: Dictionary = {}) -> bool:
		var clear: bool = super._detour_path_clear(world,actor,movement,path,query,proof)
		var scratch: HospitalMovement.ReturnContactScratch = proof.get("_return_contact_scratch")
		if scratch!=null and scratch.queries.has("regions"):
			var known: bool = false
			for scope: Dictionary in scopes: known = known or is_same(scope,scratch.queries)
			if not known: scopes.append(scratch.queries)
		return clear

func run(content: HospitalContent, selected: String = "") -> Dictionary:
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new()
	suite.content = content
	var names: Array = ["exact_candidates","permissions","owner_lifetime"]
	if not selected.is_empty() and not selected in names: return {"passed":false,"error":"Unknown case: "+selected}
	var rows: Array = []
	var passed: bool = true
	for name: String in names:
		if not selected.is_empty() and selected!=name: continue
		var started: int = Time.get_ticks_usec()
		var row: Dictionary = call("_"+name,suite)
		row.elapsed_us = Time.get_ticks_usec()-started
		rows.append(row)
		passed = passed and row.passed
	return {"passed":passed,"rows":rows,"scope":"Requirement-defined exact contact calculations and scope expiry after actual movement; no claimed journey from a hypothetical sweep."}

func _row(name: String, checks: Dictionary) -> Dictionary:
	var passed: bool = true
	for value: bool in checks.values(): passed = passed and value
	return {"name":name,"passed":passed,"checks":checks}

func _contact(sim: HospitalSimulation, id: String, from: Rect2, to: Rect2, queries: Dictionary, members: Array = []) -> Dictionary:
	var sweep: BodyIndex.Record = BodyIndex.Record.new()
	sweep.id = id
	sweep.sweep_from = from
	sweep.sweep_to = to
	var sweeps: Array[BodyIndex.Record] = [sweep]
	var result: HospitalMovement.MotionResult = HospitalMovement.MotionResult.new()
	sim.space.movement._movement_contacts(sim.world,id,1,from.merge(to),sweeps,members,result,queries)
	return {"actors":result.blocker_actor_ids.duplicate(),"reservations":result.reservation_ids.duplicate(),"blocked":result.blocked,"actual":result.actual_motion,"requested":result.requested_motion,"door":result.door_id}

func _exact_candidates(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._history_height(sim,2)
	suite._add_actor(sim,"walker","S03",[35.125,70.375])
	suite._add_actor(sim,"blocker","S49",[40,74])
	suite._add_actor(sim,"other_floor","S49",[38,72],2)
	var actor: Dictionary = sim.world.facts.actors.walker
	var scope: Dictionary = {"regions":{}}
	var before: Dictionary = sim.world.freeze()
	var checks: Dictionary = {"legal_world":sim.world.validate(suite.content).is_empty()}
	var blocker: Rect2 = sim.space.body_rectangle(sim.world.facts.actors.blocker)
	var shape: Rect2 = sim.space._actor_rect(actor,Vector2.ZERO)
	var touching: Rect2 = Rect2(Vector2(blocker.end.x,blocker.position.y),shape.size)
	var overlap: Rect2 = Rect2(touching.position-Vector2(0.0001,0),touching.size)
	var touch: Dictionary = _contact(sim,"walker",touching,touching,scope,["walker"])
	var first_size: int = scope.regions.size()
	var repeated: Dictionary = _contact(sim,"walker",touching,touching,scope,["walker"])
	checks.strict_touch_is_clear = not touch.blocked and touch==repeated
	checks.repeated_box_reuses_complete_candidates = first_size>0 and scope.regions.size()==first_size
	checks.small_overlap_retains_exact_identity = _contact(sim,"walker",overlap,overlap,scope,["walker"]).actors==["blocker"]
	var equal: bool = true
	for origin: Vector2 in [Vector2(35.125,70.375),Vector2(37.875,72.125),Vector2(39.9,73.8),Vector2(41.875,75.875)]:
		for direction: Vector2 in [Vector2.ZERO,Vector2(0.25,0),Vector2(0,0.25),Vector2(-0.25,0),Vector2(0,-0.25)]:
			var from: Rect2 = sim.space._actor_rect(actor,origin)
			var to: Rect2 = sim.space._actor_rect(actor,origin+direction)
			equal = equal and _contact(sim,"walker",from,to,scope,["walker"])==_contact(sim,"walker",from,to,{},["walker"])
	checks.fractional_large_body_cross_region_matches_full_query = equal
	var regions: Array[Rect2] = [Rect2(40,74,0.25,0.25),Rect2(42,74,0.25,0.25)]
	sim.space._actor_index.update_compound("blocker",1,regions)
	var compound: Dictionary = {"regions":{}}
	var gap: Rect2 = Rect2(41,74,0.25,0.25)
	checks.compound_gap_is_clear = not _contact(sim,"walker",gap,gap,compound,["walker"]).blocked
	checks.compound_regions_are_complete = _contact(sim,"walker",regions[0],regions[0],compound,["walker"]).actors==["blocker"] and _contact(sim,"walker",regions[1],regions[1],compound,["walker"]).actors==["blocker"]
	checks.world_facts_unchanged = sim.world.freeze()==before
	sim.dispose()
	# Dense complete-candidate calculation input; no arrival is inferred.
	var dense: HospitalSimulation = suite._fixture()
	suite._add_actor(dense,"walker","S49",[35,70])
	var expected: Array[String] = []
	for index: int in 30:
		var id: String = "body_%02d"%index
		suite._add_actor(dense,id,"S49",[36,70])
		expected.append(id)
	var target: Rect2 = dense.space._actor_rect(dense.world.facts.actors.walker,Vector2(36,70))
	checks.no_candidate_count_limit = _contact(dense,"walker",target,target,{"regions":{}},["walker"]).actors==expected
	dense.dispose()
	return _row("exact_candidates",checks)

func _permissions(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var placed: CommandResult = suite._command(sim,"build_facility",{"id":"reserved_machine","definition_id":"M37","floor_id":1,"cell":[42,76]})
	if not placed.accepted: return _row("permissions",{"fixture":false})
	suite._add_actor(sim,"walker","S49",[38,80])
	suite._add_actor(sim,"owner","S49",[34,80])
	suite._add_actor(sim,"peer","S49",[36,80])
	var reason: String = sim.space.reserve_facility(sim.world,"reserved_machine","owner","owner")
	var region: Array = sim.world.facts.adaptations.reserved_machine.regions[0]
	var rect: Rect2 = Rect2(float(region[0]),float(region[1]),float(region[2]),float(region[3]))
	var before: Dictionary = sim.world.freeze()
	var allowed: Array = ["walker","owner"]
	var denied: Array = ["walker","peer"]
	var a: Dictionary = _contact(sim,"walker",rect,rect,{"regions":{}},allowed)
	var b: Dictionary = _contact(sim,"walker",rect,rect,{"regions":{}},denied)
	var checks: Dictionary = {"legal_real_reservation":reason.is_empty() and sim.world.validate(suite.content).is_empty(),"allowed_member_is_clear":not a.blocked,"new_member_does_not_inherit_permission":b.reservations==["reserved_machine"],"both_match_full_predicate":a==_contact(sim,"walker",rect,rect,{},allowed) and b==_contact(sim,"walker",rect,rect,{},denied),"readonly":before==sim.world.freeze()}
	sim.dispose()
	return _row("permissions",checks)

func _owner_lifetime(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"walker","S49",[35,70])
	suite._add_actor(sim,"blocker","S49",[36,70])
	var service: ObservedMovement = ObservedMovement.new(sim.space)
	var movement: Dictionary = {"actor_id":"walker","detour":{"original_path":[{"kind":"floor","floor_id":1,"cell":[36,70]},{"kind":"floor","floor_id":1,"cell":[37,70]}]}}
	var before: Dictionary = sim.world.freeze()
	var first: Dictionary = service._detour_return_path(sim.world,sim.world.facts.actors.walker,movement,Vector2(35,70))
	var readonly: bool = before==sim.world.freeze()
	var requested: String = sim.space.request_move(sim.world,"blocker",1,[36,72])
	for index: int in 30:
		suite._movement_tick(sim)
		if sim.space.at(sim.world,"blocker",1,[36,72]): break
	var arrived: bool = sim.space.at(sim.world,"blocker",1,[36,72])
	before = sim.world.freeze()
	var second: Dictionary = service._detour_return_path(sim.world,sim.world.facts.actors.walker,movement,Vector2(35,70))
	var checks: Dictionary = {"blocked_nearest_target_uses_successor":first.get("index",-1)==1,"blocker_really_walked_away":requested.is_empty() and arrived,"next_owner_rechecks_released_target":second.get("index",-1)==0,"fresh_regions_for_each_owner":service.scopes.size()==2 and not is_same(service.scopes[0].regions,service.scopes[1].regions),"queries_readonly":readonly and before==sim.world.freeze()}
	sim.dispose()
	return _row("owner_lifetime",checks)
