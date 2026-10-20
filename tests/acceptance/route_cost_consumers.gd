extends RefCounted

class CountingSpace extends HospitalSpace:
	var synchronized_worlds: Dictionary = {}
	func _sync_actor(world: WorldState, id: String) -> void:
		var key: int = world.get_instance_id()
		synchronized_worlds[key] = int(synchronized_worlds.get(key,0))+1
		super._sync_actor(world,id)
	func projection_visits(owner: WorldState) -> int:
		var visits: int = 0
		for key: int in synchronized_worlds:
			if key!=owner.get_instance_id(): visits += int(synchronized_worlds[key])
		return visits

# The staff selector owns a private HospitalSpace. Observe its input world
# instead: a full actor-index rebuild must enumerate ids("actors").
class CountingWorld extends WorldState:
	var actor_enumerations: int = 0
	func ids(collection: String) -> Array:
		if collection=="actors": actor_enumerations += 1
		return super.ids(collection)

class CountingWellbeing extends HospitalStaffWellbeing:
	var projections: Array[CountingWorld] = []
	func _adapted_candidate(world: WorldState, facility_id: String, fit: Dictionary, actor_id: String) -> WorldState:
		var original: WorldState = super._adapted_candidate(world,facility_id,fit,actor_id)
		var observed: CountingWorld = CountingWorld.new(original.facts)
		projections.append(observed)
		return observed

func run(suite: RefCounted) -> Dictionary:
	var routes: Dictionary = _route_contract(suite)
	var groups: Dictionary = _group_contract(suite)
	var seat: Dictionary = _hot_seat_quote(suite)
	var staff: Dictionary = _staff_projection_index(suite)
	return {"ok":routes.ok and groups.ok and seat.ok and staff.ok,"route_fields":routes,"group_fields":groups,"hot_seat_quote":seat,"staff_projection_index":staff}

func _business_fields(result: Dictionary) -> Dictionary:
	var fields: Dictionary = result.duplicate(true)
	fields.erase("path")
	fields.erase("cells")
	return fields

func _compare(sim: HospitalSimulation, actor_id: String, floor_id: int, cell: Array, expected_ok: bool, expected_distance: int = -1, expected_ticks: int = -1, members: Array = [], offsets: Dictionary = {}) -> Dictionary:
	var before: Dictionary = sim.world.freeze()
	var count: int = int(sim.space.query_counts.materialized_floor_cells)
	var cost: Dictionary = sim.space.route_cost(sim.world,actor_id,floor_id,cell,members,offsets)
	var no_cells: bool = count==int(sim.space.query_counts.materialized_floor_cells) and not cost.has("path") and not cost.has("cells")
	var full: Dictionary = sim.space.route(sim.world,actor_id,floor_id,cell,members,offsets)
	var same: bool = _business_fields(cost)==_business_fields(full)
	var literal: bool = cost.get("ok",false)==expected_ok
	if expected_ok:
		literal = literal and float(cost.get("walking_distance",-1))==float(expected_distance) and int(cost.get("travel_ticks",-1))==expected_ticks
	else:
		literal = literal and not str(cost.get("reason","")).is_empty()
	var readonly: bool = before==sim.world.freeze()
	return {"ok":same and no_cells and literal and readonly,"business_fields_identical":same,"literal_expected_result":literal,"no_script_path_cells":no_cells,"facts_unchanged":readonly,"cost":cost,"complete_fields":_business_fields(full)}

func _route_contract(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	suite._add_actor(sim,"cost_subject","S49",[40,84])
	# Four orthogonal cells at the specified 2 cells/s and 0.1 s per tick.
	var straight: Dictionary = _compare(sim,"cost_subject",1,[44,84],true,4,20)
	var stationary: Dictionary = _compare(sim,"cost_subject",1,[40,84],true,0,0)
	var before: Dictionary = sim.world.freeze()
	var count: int = int(sim.space.query_counts.materialized_floor_cells)
	var cost_floor: Dictionary = sim.space._floor_route(sim.world,sim.world.facts.actors.cost_subject,1,Vector2i(40,84),Vector2i(44,84),[],{},true,{},true)
	var floor_no_cells: bool = count==int(sim.space.query_counts.materialized_floor_cells) and not cost_floor.has("path") and not cost_floor.has("cells")
	var full_floor: Dictionary = sim.space._floor_route(sim.world,sim.world.facts.actors.cost_subject,1,Vector2i(40,84),Vector2i(44,84),[],{},true)
	var floor_equal: bool = _business_fields(cost_floor)==_business_fields(full_floor) and float(cost_floor.get("walking_distance",-1))==4.0
	var floor_readonly: bool = before==sim.world.freeze()
	# A blocked target is a legal failed route query, not a reduced load.
	sim.world.facts.floors.overrides["1"].blocked.append([44,84])
	sim.world.touch()
	var blocked: Dictionary = _compare(sim,"cost_subject",1,[44,84],false)
	sim.world.facts.actors.cost_subject.location = {"kind":"outside"}
	sim.world.touch()
	var outside: Dictionary = _compare(sim,"cost_subject",1,[40,84],false)
	sim.dispose()
	return {"ok":straight.ok and stationary.ok and floor_equal and floor_no_cells and floor_readonly and blocked.ok and outside.ok,"straight":straight,"stationary":stationary,"floor_fields_identical":floor_equal,"floor_no_script_path_cells":floor_no_cells,"floor_facts_unchanged":floor_readonly,"blocked_target":blocked,"outside_actor":outside}

func _group_contract(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._transit_fixture()
	suite._add_actor(sim,"cost_primary","S49",[44,84])
	suite._add_actor(sim,"cost_partner","S49",[45,84])
	suite._add_actor(sim,"cost_giant","S59",[49,84])
	# VC02's landing is [36,76]. Walking is 16 cells on each floor. At
	# 1.6 cells/s, the group walks 200 ticks plus 15+10+15 fixed lift ticks.
	var group: Dictionary = _compare(sim,"cost_primary",2,[44,84],true,32,240,["cost_primary","cost_partner"],{"cost_primary":[0,0],"cost_partner":[1,0]})
	var incompatible: Dictionary = _compare(sim,"cost_giant",2,[49,84],false)
	sim.dispose()
	return {"ok":group.ok and incompatible.ok,"complete_group":group,"incompatible_body":incompatible}

func _hot_seat_quote(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	var built: CommandResult = suite._command(sim,"build_facility",{"id":"cost_seat","definition_id":"FUR06","floor_id":1,"cell":[44,84]})
	if not built.accepted:
		sim.dispose()
		return {"ok":false,"build":built.to_record()}
	var visit: Dictionary = suite._waiting_visit(sim,"cost_seat_user",[44,88])
	var friend: Dictionary = suite._waiting_visit(sim,"cost_seat_friend",[46,85])
	var pair: Array = [visit.actor_id,friend.actor_id]
	pair.sort()
	if not sim.world.facts.has("relationships"): sim.world.facts.relationships = {}
	sim.world.facts.relationships[":".join(pair)] = {"kind":"friend"}
	sim.world.touch()
	sim.services.waiting.ensure(sim.world)
	var geometry: CountingSpace = CountingSpace.new(suite.content)
	var waiting: HospitalWaitingLife = HospitalWaitingLife.new(suite.content,geometry)
	waiting.environment = sim.services.environment
	var layout: Dictionary = geometry.facility_layout(sim.world,"cost_seat")
	var complete: Dictionary = geometry.route(sim.world,visit.actor_id,1,layout.patient_cell)
	var before: Dictionary = sim.world.freeze()
	var count: int = int(geometry.query_counts.materialized_floor_cells)
	var route_count: int = int(geometry.query_counts.routes)
	var quote: Dictionary = waiting._seat_quote(sim.world,visit,"cost_seat")
	var repeated: Dictionary = waiting._seat_quote(sim.world,visit,"cost_seat")
	var trip: Dictionary = geometry.facility_trip_quote(sim.world,"cost_seat",visit.actor_id)
	var no_cells: bool = count==int(geometry.query_counts.materialized_floor_cells)
	var queried: bool = int(geometry.query_counts.routes)>route_count
	var equal_time: bool = complete.get("ok",false) and quote.get("ok",false) and int(quote.get("travel_ticks",-1))==int(complete.get("travel_ticks",-2))
	var literal: bool = layout.patient_cell==[44,85] and float(complete.get("walking_distance",-1))==3.0 and int(quote.get("travel_ticks",-1))==15
	var trip_equal: bool = trip.get("ok",false) and int(trip.get("travel_ticks",-1))==15 and trip.get("cell",[])==layout.patient_cell
	var friendship: bool = quote.get("conditions",{}).get("friendly_neighbor",false)
	var no_projection_index: bool = geometry.projection_visits(sim.world)==0
	var index_builds: int = int(geometry.query_counts.actor_index_builds)
	var actor_visits: int = int(geometry.query_counts.actor_index_actor_visits)
	# Actual preflight still checks other bodies on the original world. These
	# private structural trips must not replace that index with a projected one.
	var source_preflight: bool = index_builds==1 and actor_visits==sim.world.facts.actors.size()
	var dynamic_blocked: bool = not geometry._dynamic_clear(sim.world,visit.actor_id,1,geometry.body_rectangle(sim.world.facts.actors[friend.actor_id]))
	var readonly: bool = before==sim.world.freeze()
	var repeatable: bool = repeated==quote
	var scopes_closed: bool = geometry._route_queries.is_empty()
	var cell_delta: int = int(geometry.query_counts.materialized_floor_cells)-count
	sim.dispose()
	return {"ok":equal_time and literal and trip_equal and friendship and no_cells and queried and no_projection_index and source_preflight and dynamic_blocked and readonly and repeatable and scopes_closed,"same_time_as_complete_route":equal_time,"literal_3_cells_15_ticks":literal,"facility_trip_same_literal_time":trip_equal,"friend_path_condition_evaluated":friendship,"no_script_path_cells":no_cells,"actual_cost_queries_executed":queried,"no_projection_actor_index":no_projection_index,"original_world_preflight_retained":source_preflight,"actual_dynamic_body_still_blocks":dynamic_blocked,"actor_index_builds":index_builds,"actor_index_actor_visits":actor_visits,"facts_unchanged":readonly,"repeatable":repeatable,"query_scopes_closed":scopes_closed,"quote":quote,"trip":trip,"materialized_cell_delta":cell_delta}

func _staff_projection_index(suite: RefCounted) -> Dictionary:
	var sim: HospitalSimulation = suite._fixture()
	HospitalFactory._add_room(sim.world,{"id":"cost_staff_room","type":"rest","anchor":[34,66],"size":[12,12],"door":{"definition_id":"DR01","offset":4}},suite.content)
	HospitalFactory._add_facility(sim.world,{"id":"cost_staff_bed","definition_id":"SE04","anchor":[39,69],"size":[1,2],"room_id":"cost_staff_room"},suite.content)
	suite._add_staff(sim,"cost_sleep_user","doctor",[44,82])
	var geometry: CountingSpace = CountingSpace.new(suite.content)
	var wellbeing: CountingWellbeing = CountingWellbeing.new(suite.content,geometry)
	wellbeing.ensure(sim.world)
	wellbeing.projections.clear()
	var before: Dictionary = sim.world.freeze()
	var selected: Dictionary = wellbeing._select_facility(sim.world,"cost_sleep_user","sleep")
	var no_projection_index: bool = not wellbeing.projections.is_empty()
	var enumerations: int = 0
	for projected: CountingWorld in wellbeing.projections: enumerations += projected.actor_enumerations
	no_projection_index = no_projection_index and enumerations==0 and geometry.projection_visits(sim.world)==0
	var readonly: bool = before==sim.world.freeze()
	var expected_bed: bool = selected.get("facility_id","")=="cost_staff_bed" and selected.get("cell",[])==[39,71]
	# An independent complete-route check still proves both journeys under the
	# same reservation geometry; the selector returns only the chosen target.
	var reference: WorldState = WorldState.new(before)
	var complete_space: HospitalSpace = HospitalSpace.new(suite.content)
	var complete_life: HospitalStaffWellbeing = HospitalStaffWellbeing.new(suite.content,complete_space)
	var fit: Dictionary = complete_space.facility_quote(reference,"cost_staff_bed","cost_sleep_user")
	var outward: Dictionary = {"ok":false}
	var back: Dictionary = {"ok":false}
	if fit.get("ok",false):
		var candidate: WorldState = complete_life._adapted_candidate(reference,"cost_staff_bed",fit,"cost_sleep_user")
		outward = complete_space.route(candidate,"cost_sleep_user",1,[39,71])
		candidate.facts.actors.cost_sleep_user.location = {"kind":"floor","floor_id":1,"cell":[39,71],"height_m":0.0}
		back = complete_space.route(candidate,"cost_sleep_user",1,[44,82])
	var round_trip: bool = outward.get("ok",false) and back.get("ok",false)
	var projections: int = wellbeing.projections.size()
	sim.dispose()
	return {"ok":no_projection_index and readonly and expected_bed and round_trip,"no_projection_actor_index":no_projection_index,"projection_actor_enumerations":enumerations,"candidate_count":projections,"facts_unchanged":readonly,"personal_bed_selected":expected_bed,"complete_round_trip_legal":round_trip,"selection":selected}
