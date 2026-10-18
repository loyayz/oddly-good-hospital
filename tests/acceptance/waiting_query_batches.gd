extends "res://tests/acceptance/staff_fixtures.gd"

# Independent pre-index candidate loop and neighborhood calculation are frozen
# from adcea18. They compare complete quotes, rather than feeding expected scores
# back through the optimized candidate lookup.
class CountedSpace extends HospitalSpace:
	var condition_scope: bool = false
	var condition_routes: int = 0
	var condition_route_us: int = 0
	var condition_trace: Array = []
	var route_calls: int = 0
	var route_us: int = 0
	func route(world: WorldState, actor_id: String, floor_id: int, target: Array, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false) -> Dictionary:
		route_calls += 1
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super.route(world,actor_id,floor_id,target,members,offsets,ignore_people)
		route_us += Time.get_ticks_usec()-started
		return result
	func _floor_route(world: WorldState, actor: Dictionary, floor_id: int, start: Vector2i, goal: Vector2i, members: Array = [], offsets: Dictionary = {}, ignore_people: bool = false, navigation: Dictionary = {}) -> Dictionary:
		var counted: bool = condition_scope
		if counted:
			condition_routes += 1
			condition_trace.append([floor_id,start.x,start.y,goal.x,goal.y])
		var started: int = Time.get_ticks_usec()
		var result: Dictionary = super._floor_route(world,actor,floor_id,start,goal,members,offsets,ignore_people,navigation)
		if counted: condition_route_us += Time.get_ticks_usec()-started
		return result

class CountedLife extends HospitalWaitingLife:
	var condition_calls: int = 0
	var actor_visits: int = 0
	var index_actor_visits: int = 0
	var quote_calls: int = 0
	var quoted: Array = []
	func _seat_quote(world: WorldState, visit: Dictionary, facility_id: String, actor_index: Variant = null) -> Dictionary:
		quote_calls += 1
		var result: Dictionary = super._seat_quote(world,visit,facility_id,actor_index)
		quoted.append(result.duplicate(true))
		return result
	func _condition_actor_index(world: WorldState) -> Dictionary:
		index_actor_visits += world.facts.actors.size()
		return super._condition_actor_index(world)
	func _condition_actors(world: WorldState, floor_id: int, cell: Array, actor_index: Variant) -> Array:
		var result: Array = super._condition_actors(world,floor_id,cell,actor_index)
		actor_visits += result.size()
		return result
	func _conditions(world: WorldState, visit: Dictionary, facility: Dictionary, cell: Array, observation: Dictionary, actor_index: Variant = null) -> Dictionary:
		condition_calls += 1
		(space as CountedSpace).condition_scope = true
		var result: Dictionary = super._conditions(world,visit,facility,cell,observation,actor_index)
		(space as CountedSpace).condition_scope = false
		return result

class FrozenLife extends CountedLife:
	func _conditions(world: WorldState, visit: Dictionary, facility: Dictionary, cell: Array, observation: Dictionary, _actor_index: Variant = null) -> Dictionary:
		condition_calls += 1
		actor_visits += world.facts.actors.size()
		(space as CountedSpace).condition_scope = true
		var result: Dictionary = _original_conditions(world,visit,facility,cell,observation)
		(space as CountedSpace).condition_scope = false
		return result

	func seat_candidates(world: WorldState, visit_id: String) -> Array:
		var visit: Dictionary = world.facts.visits.get(visit_id,{})
		if visit.is_empty() or not _waiting(world,visit):
			return []
		var candidates: Array = []
		var facility_ids: Array = []
		for definition_id: String in PUBLIC_SEAT_DEFINITIONS:
			facility_ids.append_array(world.facility_ids(definition_id))
		facility_ids.sort()
		var maximum_travel_ticks: int = _ticks(content.balance.seat_choice.automatic_travel_seconds_max)
		space.begin_route_query(world,{},space.nominal_query(world))
		for facility_id: String in facility_ids:
			if space.facility_travel_lower_bound_ticks(world,facility_id,visit.actor_id)>maximum_travel_ticks: continue
			var quote: Dictionary = _seat_quote(world,visit,facility_id)
			if quote.ok and int(quote.travel_ticks)<=maximum_travel_ticks:
				candidates.append(quote)
		space.end_route_query()
		if candidates.is_empty():
			return []
		var closest: int = 2147483647
		for candidate: Dictionary in candidates:
			closest = mini(closest,int(candidate.travel_ticks))
		candidates = candidates.filter(func(item: Dictionary) -> bool: return int(item.travel_ticks)<=closest+_ticks(content.balance.seat_choice.nearby_detour_seconds))
		var preferred: Array = candidates.filter(func(item: Dictionary) -> bool: return item.preferred)
		if not preferred.is_empty():
			candidates = preferred
		var highest: float = 0.0
		for candidate: Dictionary in candidates:
			highest = maxf(highest,float(candidate.environment))
		candidates = candidates.filter(func(item: Dictionary) -> bool: return float(item.environment)>=highest-float(content.balance.seat_choice.environment_tolerance))
		candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
			if a.score!=b.score: return a.score>b.score
			if a.environment!=b.environment: return a.environment>b.environment
			if a.travel_ticks!=b.travel_ticks: return a.travel_ticks<b.travel_ticks
			return a.facility_id<b.facility_id)
		return candidates

	func _original_conditions(world: WorldState, visit: Dictionary, facility: Dictionary, cell: Array, observation: Dictionary) -> Dictionary:
		var nearby: int = 0
		var friendly: bool = false
		var radius: float = float(content.balance.patient_behavior.crowd_radius_cells)
		for actor: Dictionary in world.facts.actors.values():
			if actor.id==visit.actor_id or world.facts.staff.has(actor.id) or actor.location.kind!="floor" or int(actor.location.floor_id)!=int(facility.floor_id): continue
			if Vector2(float(actor.location.cell[0]),float(actor.location.cell[1])).distance_to(Vector2(float(cell[0]),float(cell[1])))>radius: continue
			var nearby_route: Dictionary = space._floor_route(world,world.facts.actors[visit.actor_id],int(facility.floor_id),Vector2i(int(cell[0]),int(cell[1])),Vector2i(roundi(actor.location.cell[0]),roundi(actor.location.cell[1])),[],{},true)
			if not nearby_route.ok or float(nearby_route.walking_distance)>radius: continue
			nearby += 1
			var pair: Array = [visit.actor_id,actor.id]
			pair.sort()
			var relationship: Variant = world.facts.get("relationships",{}).get(":".join(pair),{})
			if relationship is Dictionary and relationship.get("kind","")=="friend" and not world.facts.moves.has(actor.id): friendly = true
		return {"quiet":float(observation.noise)<=0,"less_crowded":nearby<int(content.balance.patient_behavior.crowded_neighbors_min),"friendly_neighbor":friendly,
			"calm_available":facility.definition_id=="FUR49" and float(visit.anger)>=float(content.balance.seat_choice.calm_minimum_anger) and not visit.get("chair_calm_claimed",false),
			"noise_reduction":facility.definition_id=="FUR50" and float(observation.noise)>0,"clean_ground":bool(observation.clean),
			"decor_nearby":observation.get("decor_nearby",false),"casual_scene_nearby":observation.get("casual_scene_nearby",false)}

func run(t, database: HospitalContent) -> void:
	var result: Dictionary = run_cases(database)
	t.check("STAFF-42",result.passed,result)

func run_cases(database: HospitalContent) -> Dictionary:
	_content = database
	var valid: bool = true
	var rows: Array = []
	for kind: String in ["open_friend","wall","moving_friend","large_body","radius_boundary","bucket_float_boundary"]:
		var x: Dictionary = _input(kind)
		var before: Dictionary = x.world.freeze()
		var validation: String = x.world.validate(database)
		var compared: Dictionary = compare(x.world,"choice")
		var quotes: Array = compared.after_quotes
		var conditions: Dictionary = quotes[0].get("conditions",{}) if not quotes.is_empty() else {}
		var expected: bool = not quotes.is_empty() and quotes[0].get("ok",false)
		if kind in ["open_friend","bucket_float_boundary"]: expected = expected and conditions.get("friendly_neighbor",false)
		if kind in ["wall","moving_friend"]: expected = expected and not conditions.get("friendly_neighbor",true)
		if kind=="large_body": expected = expected and x.space.clearance(x.world.facts.actors[x.world.facts.visits.choice.actor_id])>1
		var readonly: bool = x.world.freeze()==before
		var ok: bool = validation.is_empty() and compared.equal and expected and readonly
		valid = valid and ok
		rows.append({"kind":kind,"passed":ok,"validation":validation,"complete_candidates_and_quotes_equal":compared.equal,"expected_conditions":expected,"facts_and_rng_readonly":readonly,"before":compared.before_metrics,"after":compared.after_metrics,"conditions":conditions})
	var reservation: Dictionary = _reservation_case()
	var empty: Dictionary = _empty_bound_case()
	valid = valid and reservation.passed and empty.passed
	return {"passed":valid,"neighborhoods":rows,"live_last_seat":reservation,"strict_rejected_bound":empty}

func _input(kind: String) -> Dictionary:
	var x: Dictionary = _fixture({"excluded_staff":"doctor"})
	_facility(x,"seat_A","FUR06",[42,75])
	_facility(x,"seat_B","FUR06",[48,75])
	x.world.facts.facilities.seat_A.patient_cell = [42,76]
	x.world.facts.facilities.seat_B.patient_cell = [48,76]
	var visit: Dictionary = _visit(x,"choice",[38,79],"PP04")
	if kind=="large_body":
		var binding: Dictionary = _content.definition("treatment_bindings","B_S08_D04_M04")
		var actor: Dictionary = x.world.facts.actors[visit.actor_id]
		actor.species_id = binding.species_id
		actor.body_binding_id = binding.id
		visit.binding_id = binding.id
		visit.disease_id = binding.disease_id
		visit.requested_plan_id = "P_"+str(binding.disease_id)+"_COMMON"
	else:
		# Deliberately reverse lexical IDs and cross bucket borders. Spatial
		# selection must retain the source dictionary's visitation order.
		for item: Array in [["z_neighbor",[44.0,76.0]],["a_neighbor",[41.5,78.0]],["m_neighbor",[40.0,77.0]]]:
			var id: String = item[0]
			x.world.facts.actors[id] = {"id":id,"name":id,"species_id":"S49","location":{"kind":"floor","floor_id":1,"cell":item[1].duplicate(),"height_m":0.0},"facing":0.0,"posture":"standing"}
		var pair: Array = [visit.actor_id,"z_neighbor"]
		pair.sort()
		if not x.world.facts.has("relationships"): x.world.facts.relationships = {}
		x.world.facts.relationships[":".join(pair)] = {"kind":"friend"}
		if kind=="wall":
			x.world.facts.actors.z_neighbor.location.cell = [45.0,76.0]
			x.world.facts.actors.a_neighbor.location.cell = [38.0,82.0]
			x.world.facts.actors.m_neighbor.location.cell = [38.0,84.0]
			for y: int in range(72,81): x.world.facts.floors.overrides["1"].blocked.append([44,y])
		if kind=="moving_friend":
			x.world.touch()
			var reason: String = x.space.request_move(x.world,"z_neighbor",1,[46,80])
			if not reason.is_empty(): push_error("Moving friend input: "+reason)
		if kind=="radius_boundary":
			# The bucket includes the legal resident exactly three cells away;
			# the ordinary inputs also contain fractional positions across bins.
			x.world.facts.actors.a_neighbor.location.cell = [39.0,76.0]
		if kind=="bucket_float_boundary":
			x.world.facts.facilities.seat_A.cell = [39,75]
			x.world.facts.facilities.seat_A.patient_cell = [39,76]
			x.world.facts.actors.z_neighbor.location.cell = [35.9999999,76.0]
			x.world.facts.actors.a_neighbor.location.cell = [38.0,82.0]
			x.world.facts.actors.m_neighbor.location.cell = [38.0,84.0]
	x.world.touch()
	return x

func _bind_life(world: WorldState, original: bool) -> Dictionary:
	var geometry: CountedSpace = CountedSpace.new(_content)
	var life: CountedLife = FrozenLife.new(_content,geometry) if original else CountedLife.new(_content,geometry)
	var environment: HospitalEnvironment = HospitalEnvironment.new(_content,geometry)
	environment.waiting_life = life
	life.environment = environment
	return {"space":geometry,"life":life,"environment":environment}

func metrics(bound: Dictionary) -> Dictionary:
	return {"conditions":bound.life.condition_calls,"actor_records":bound.life.actor_visits,"index_build_actor_records":bound.life.index_actor_visits,"actor_records_total":bound.life.actor_visits+bound.life.index_actor_visits,"neighbor_routes":bound.space.condition_routes,"neighbor_route_us":bound.space.condition_route_us,"neighbor_route_trace":bound.space.condition_trace.duplicate(true),"facility_routes":bound.space.route_calls,"facility_route_us":bound.space.route_us,"full_quotes":bound.life.quote_calls}

func compare(world: WorldState, visit_id: String) -> Dictionary:
	var before: Dictionary = _bind_life(world,true)
	var after: Dictionary = _bind_life(world,false)
	before.environment.begin_query(world)
	var old: Array = before.life.seat_candidates(world,visit_id)
	before.environment.end_query()
	after.environment.begin_query(world)
	var actual: Array = after.life.seat_candidates(world,visit_id)
	after.environment.end_query()
	var result: Dictionary = {"equal":old==actual and before.life.quoted==after.life.quoted and before.space.condition_trace==after.space.condition_trace,"before_candidates":old,"after_candidates":actual,"before_quotes":before.life.quoted,"after_quotes":after.life.quoted,"before_metrics":metrics(before),"after_metrics":metrics(after)}
	_release_bound(before)
	_release_bound(after)
	return result

func _release_bound(bound: Dictionary) -> void:
	bound.life.environment = null
	bound.environment.waiting_life = null

func _reservation_case() -> Dictionary:
	var x: Dictionary = _fixture()
	_facility(x,"last_seat","FUR06",[42,75])
	_visit(x,"first",[38,79])
	_visit(x,"second",[46,79])
	x.world.touch()
	var compared: Dictionary = compare(x.world,"first")
	var service: HospitalWaitingLife = HospitalWaitingLife.new(_content,x.space)
	var first: CommandResult = service.execute(x.world,"waiting_select_seat",{"visit_id":"first","facility_id":"last_seat"})
	var second: CommandResult = service.execute(x.world,"waiting_select_seat",{"visit_id":"second","facility_id":"last_seat"})
	var no_remote: bool = x.world.facts.adaptations.is_empty()
	var seated: int = 0
	for tick: int in 300:
		x.world.facts.sim_tick += 1
		service.dispatch(x.world)
		x.space.advance(x.world)
		seated = 0
		for seat: Dictionary in x.world.facts.waiting_life.seats.values():
			if seat.phase=="seated": seated += 1
		if seated>0: break
	var occupied: Dictionary = compare(x.world,"second")
	return {"passed":compared.equal and first.accepted and second.accepted and no_remote and seated==1 and occupied.equal,"full_conditions_equal":compared.equal,"two_manual_requests":first.accepted and second.accepted,"no_remote_ownership":no_remote,"actual_seated":seated,"live_occupancy_conditions_equal":occupied.equal}

func _empty_bound_case() -> Dictionary:
	var x: Dictionary = _fixture()
	_facility(x,"far_seat","FUR06",[42,75])
	x.world.facts.floors.overrides["1"].plots.append([1,1])
	x.world.facts.floors.overrides["1"].plots.append([1,0])
	var visit: Dictionary = _visit(x,"far",[42,13])
	x.world.touch()
	var before: Dictionary = x.world.freeze()
	var compared: Dictionary = compare(x.world,visit.id)
	return {"passed":compared.equal and compared.after_candidates.is_empty() and compared.after_metrics.full_quotes==0 and compared.after_metrics.index_build_actor_records==0 and x.world.freeze()==before,"full_candidates_equal":compared.equal,"before":compared.before_metrics,"after":compared.after_metrics,"facts_and_rng_readonly":x.world.freeze()==before}
