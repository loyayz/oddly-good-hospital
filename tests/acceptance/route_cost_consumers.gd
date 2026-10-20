extends RefCounted

func run(suite: RefCounted) -> Dictionary:
	var routes: Dictionary = _route_contract(suite)
	var groups: Dictionary = _group_contract(suite)
	var seat: Dictionary = _hot_seat_quote(suite)
	return {"ok":routes.ok and groups.ok and seat.ok,"route_fields":routes,"group_fields":groups,"hot_seat_quote":seat}

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
	var layout: Dictionary = sim.space.facility_layout(sim.world,"cost_seat")
	var complete: Dictionary = sim.space.route(sim.world,visit.actor_id,1,layout.patient_cell)
	var before: Dictionary = sim.world.freeze()
	var count: int = int(sim.space.query_counts.materialized_floor_cells)
	var route_count: int = int(sim.space.query_counts.routes)
	var quote: Dictionary = sim.services.waiting._seat_quote(sim.world,visit,"cost_seat")
	var repeated: Dictionary = sim.services.waiting._seat_quote(sim.world,visit,"cost_seat")
	var no_cells: bool = count==int(sim.space.query_counts.materialized_floor_cells)
	var queried: bool = int(sim.space.query_counts.routes)>route_count
	var equal_time: bool = complete.get("ok",false) and quote.get("ok",false) and int(quote.get("travel_ticks",-1))==int(complete.get("travel_ticks",-2))
	var literal: bool = layout.patient_cell==[44,85] and float(complete.get("walking_distance",-1))==3.0 and int(quote.get("travel_ticks",-1))==15
	var friendship: bool = quote.get("conditions",{}).get("friendly_neighbor",false)
	var readonly: bool = before==sim.world.freeze()
	var repeatable: bool = repeated==quote
	var scopes_closed: bool = sim.space._route_queries.is_empty()
	var cell_delta: int = int(sim.space.query_counts.materialized_floor_cells)-count
	sim.dispose()
	return {"ok":equal_time and literal and friendship and no_cells and queried and readonly and repeatable and scopes_closed,"same_time_as_complete_route":equal_time,"literal_3_cells_15_ticks":literal,"friend_path_condition_evaluated":friendship,"no_script_path_cells":no_cells,"actual_cost_queries_executed":queried,"facts_unchanged":readonly,"repeatable":repeatable,"query_scopes_closed":scopes_closed,"quote":quote,"materialized_cell_delta":cell_delta}
