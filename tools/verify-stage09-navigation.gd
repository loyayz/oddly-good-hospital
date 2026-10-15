extends SceneTree

var _checks: Dictionary = {}
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	_body_cases(content)
	_room_edges(content)
	_life_facilities(content)
	_dynamic_and_restore(content)
	print(JSON.stringify({"ok":_failures.is_empty(),"checks":_checks,"failures":_failures,"performance":"skipped_by_request","existing_fifo_sweep_and_yield_regression":"tools/verify-stage03-kernel.gd -- --navigation-only"},"\t"))
	quit(0 if _failures.is_empty() else 1)

func _world(content: HospitalContent) -> WorldState:
	var world: WorldState = FeasibilityHospitals.create("stage09",false,content)
	for collection: String in ["actors","staff","visits","tickets","sessions","attempts","preparations","ward_stays","facilities","rooms","adaptations","connectors","moves"]:
		world.facts[collection] = {}
	world.facts.floors.overrides = {"1":{"plots":[[0,0]],"blocked":[],"doors":[]}}
	world.facts.entry = {"floor_id":1,"cell":[16,31],"exit_cell":[16,31]}
	return world

func _actor(id: String, species: String, cell: Array) -> Dictionary:
	return {"id":id,"name":id,"species_id":species,"location":{"kind":"floor","floor_id":1,"cell":cell.duplicate()},"facing":0.0,"posture":"standing"}

func _body_cases(content: HospitalContent) -> void:
	for pair: Array in [["ordinary","S49"],["micro","S21"],["giant","S59"],["tall","S55"],["symptom","S49"]]:
		var world: WorldState = _world(content)
		var actor: Dictionary = _actor("body",pair[1],[2,2])
		if pair[0]=="symptom":
			for binding: Dictionary in content.catalog.treatment_bindings:
				var species: Dictionary = content.definition("species",str(binding.get("species_id","")))
				if not species.is_empty() and binding.get("symptom_envelope",{}).get("width_m",0)>float(species.body.width_m):
					actor.species_id = binding.species_id
					actor.body_binding_id = binding.id
					break
			_check("symptom_case_has_actual_expanded_binding",actor.has("body_binding_id"))
		world.facts.actors.body = actor
		var space: HospitalSpace = HospitalSpace.new(content)
		var before: String = _canonical(world)
		var result: Dictionary = space.route(world,"body",1,[20,20])
		var cardinal: bool = true
		var previous: Array = [2,2]
		for segment: Dictionary in result.get("path",[]):
			cardinal = cardinal and absf(float(segment.cell[0])-float(previous[0]))+absf(float(segment.cell[1])-float(previous[1]))==1
			previous = segment.cell
		_check(str(pair[0])+"_uses_complete_four_neighbour_real_body",result.ok and cardinal and before==_canonical(world))
		var exit: Array = space.exit_cell(world,actor)
		_check(str(pair[0])+"_exit_contains_entire_body",space.static_reason(world,actor,1,Vector2i(int(exit[0]),int(exit[1]))).is_empty())
		if pair[0]=="tall":
			world.facts.floors.height_intervals[0].height_m = 2.2
			world.touch()
			_check("height_is_checked_even_without_doors",not space.route(world,"body",1,[20,20]).ok)

func _room_edges(content: HospitalContent) -> void:
	var world: WorldState = _world(content)
	world.facts.actors.body = _actor("body","S49",[14,10])
	var cells: Array = []
	for x: int in range(8,18):
		for y: int in range(8,18):
			if x<12 or y<12:
				cells.append([x,y])
	var edges: Array = [{"axis":"x","line":8,"low":8,"high":18},{"axis":"y","line":18,"low":8,"high":12},
		{"axis":"x","line":12,"low":12,"high":18},{"axis":"y","line":12,"low":12,"high":18},
		{"axis":"x","line":18,"low":8,"high":12},{"axis":"y","line":8,"low":8,"high":18}]
	world.facts.rooms.room = {"id":"room","kind":"diagnosis","floor_id":1,"origin":[8,8],"size":[10,10],"cells":cells,"wall_edges":edges}
	world.facts.floors.overrides["1"].doors = [{"id":"door","definition_id":"DR01","room_id":"room","axis":"x","cell":[10,8],"span":1}]
	var space: HospitalSpace = HospitalSpace.new(content)
	var query: RouteClearance = RouteClearance.new(space,world,world.facts.actors.body,1)
	_check("concave_room_wall_blocks_legal_grid_endpoints",not query.sweep_reason(Vector2(14,11),Vector2(14,12)).is_empty())
	_check("concave_room_contains_actual_inner_cells",space.room_contains(world.facts.rooms.room,Rect2(9,12,2,2)) and not space.room_contains(world.facts.rooms.room,Rect2(11,11,2,2)))
	_check("room_arms_connect_through_actual_interior",space.route(world,"body",1,[10,14]).ok)
	var base: Dictionary = space.route(world,"body",1,[14,14])
	_check("room_exit_uses_door_and_real_detour",base.ok and base.path.size()>4)
	world.facts.rooms.room.wall_edges = []
	world.touch()
	var warm: Dictionary = space.route(world,"body",1,[14,14])
	var cold: Dictionary = HospitalSpace.new(content).route(world,"body",1,[14,14])
	_check("dynamic_wall_edge_repair_matches_cold_graph",warm.ok and warm.path==cold.path and warm.path.size()<base.path.size())
	world.facts.rooms.room.wall_edges = edges
	world.facts.floors.overrides["1"].doors[0].cell = [11,12]
	world.touch()
	_check("door_cannot_expand_across_concave_corner",not space.door_quote(world,world.facts.actors.body,1,world.facts.floors.overrides["1"].doors[0]).ok)

func _facility(definition: Dictionary, id: String) -> Dictionary:
	var size: Array = definition.footprint.duplicate()
	return {"id":id,"definition_id":str(definition.get("id",definition.get("definition_id",""))),"floor_id":1,"cell":[10,10],"footprint":size,"rotation":0,"patient_cell":[10,10+int(size[1])],"operator_cells":[[9,11]],"repair_cell":[9,10],"failed":false}

func _life_facilities(content: HospitalContent) -> void:
	var ids: Array[String] = []
	for collection: String in ["furniture_equipment","service_equipment","accessibility_equipment","staff_recreation_equipment"]:
		for definition: Dictionary in content.catalog.get(collection,[]):
			if definition.has("fit_profile_id"):
				ids.append(str(definition.get("id",definition.get("definition_id",""))))
	ids.sort()
	var checked: int = 0
	for id: String in ids:
		var definition: Dictionary = content.facility_definition(id)
		if definition.is_empty() or not definition.has("footprint"):
			_check("life_definition_registered_"+id,false)
			continue
		for species: String in ["S49","S21","S59","S55"]:
			var world: WorldState = _world(content)
			world.facts.actors.body = _actor("body",species,[2,2])
			world.facts.facilities.facility = _facility(definition,"facility")
			var space: HospitalSpace = HospitalSpace.new(content)
			var before: String = _canonical(world)
			var quote: Dictionary = space.facility_quote(world,"facility","body")
			_check(id+"_"+species+"_quote_is_readonly_and_complete",quote.ok and not quote.get("unchanged",false) and quote.has("patient_cell") and before==_canonical(world))
			if quote.ok and not quote.get("unchanged",false):
				space.reserve_facility(world,"facility","body","life-body")
				var layout: Dictionary = space.facility_layout(world,"facility")
				_check(id+"_"+species+"_station_is_reachable",space.route(world,"body",1,layout.patient_cell).ok)
			checked += 1
	_check("all_declared_life_fit_profiles_are_checked",checked>=40)
	var sleeping: WorldState = _world(content)
	sleeping.facts.actors.body = _actor("body","S55",[2,2])
	sleeping.facts.facilities.bed = _facility(content.facility_definition("SE04"),"bed")
	var space: HospitalSpace = HospitalSpace.new(content)
	var quote: Dictionary = space.facility_quote(sleeping,"bed","body")
	_check("staff_bed_uses_full_reclined_length",quote.ok and float(quote.footprint[1])*1.5>=float(space.body(sleeping.facts.actors.body).height_m))
	space.reserve_facility(sleeping,"bed","body","life-body")
	sleeping.facts.staff_life = {"reservations":{"bed":{"id":"life-body","staff_ids":["body"],"kind":"sleep"}}}
	space.release_adaptations(sleeping)
	_check("staff_reservation_retains_extension_before_arrival",sleeping.facts.adaptations.has("bed"))
	var anchor: Vector3 = space.support_anchor(sleeping,"bed")
	_check("unproduced_bed_has_real_geometry_support",anchor.is_finite() and anchor.y>0 and anchor.z>=float(sleeping.facts.adaptations.bed.footprint[1])*0.75)
	var station: Array = sleeping.facts.adaptations.bed.patient_cell.duplicate()
	sleeping.facts.actors.body.location.cell = station
	sleeping.facts.staff_life.reservations.clear()
	sleeping.touch()
	space.release_adaptations(sleeping)
	_check("finished_use_keeps_extension_until_body_exits",sleeping.facts.adaptations.has("bed"))
	sleeping.facts.actors.body.location.cell = [2,2]
	sleeping.touch()
	space.release_adaptations(sleeping)
	_check("real_departure_releases_staff_extension",not sleeping.facts.adaptations.has("bed"))

func _dynamic_and_restore(content: HospitalContent) -> void:
	var world: WorldState = _world(content)
	world.facts.actors.body = _actor("body","S49",[2,2])
	var space: HospitalSpace = HospitalSpace.new(content)
	space.request_move(world,"body",1,[20,20])
	_advance(space,world,7)
	_check("saving_includes_fractional_cell_progress",float(world.facts.actors.body.location.cell[0])!=roundf(float(world.facts.actors.body.location.cell[0])) or float(world.facts.actors.body.location.cell[1])!=roundf(float(world.facts.actors.body.location.cell[1])))
	var restored: WorldState = WorldState.new(world.freeze())
	var other: HospitalSpace = HospitalSpace.new(content)
	_advance(space,world,60)
	_advance(other,restored,60)
	_check("fractional_movement_resumes_exactly_after_restore",_canonical(world)==_canonical(restored))
	var movement: Dictionary = world.facts.moves.body
	var future: Array = movement.path[min(int(movement.cursor)+4,movement.path.size()-1)].cell.duplicate()
	world.facts.floors.overrides["1"].blocked.append(future)
	world.touch()
	restored = WorldState.new(world.freeze())
	other = HospitalSpace.new(content)
	_advance(space,world,1)
	_advance(other,restored,1)
	_check("construction_invalidates_remaining_route_without_teleport",world.facts.moves.body.route_pending and _canonical(world)==_canonical(restored))
	_advance(space,world,500)
	_check("dynamic_obstacle_replans_and_finishes",space.at(world,"body",1,[20,20]) and not world.facts.moves.has("body"))

func _advance(space: HospitalSpace, world: WorldState, ticks: int) -> void:
	for tick: int in ticks:
		world.facts.sim_tick += 1
		world.touch()
		space.advance(world)
		space.finish_boundary(world)

func _canonical(world: WorldState) -> String:
	return JSON.stringify(world.facts,"",true,true)

func _check(name: String, passed: bool) -> void:
	_checks[name] = passed
	if not passed:
		_failures.append(name)
