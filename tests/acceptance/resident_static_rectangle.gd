extends RefCounted

const CASES: Array[String] = ["MASK-NATIVE","MASK-LIFETIME","MASK-BOUNDARIES","MASK-FIRST-REASON"]

class Probe extends RouteClearance:
	var reason_calls: int = 0
	func reason(cell: Vector2i) -> String:
		reason_calls += 1
		return super.reason(cell)

class Complete extends Probe:
	func _resident_first_disabled(_low: Vector2i, _high: Vector2i) -> int: return -2

class RepairProbe extends FloorNavigation:
	var half_repair_rejected: bool = true
	func _repair(regions: Array[Rect2i]) -> void:
		half_repair_rejected = half_repair_rejected and resident_first_disabled(geometry.get_instance_id(),0,FloorNavigation.LIMIT-1)==-2
		super._repair(regions)

func run(content: HospitalContent, selected: Array) -> Dictionary:
	var rows: Array = []
	for id: String in selected:
		if id not in CASES: rows.append({"case":id,"ok":false,"error":"Unknown mask contract"});continue
		rows.append(_native() if id=="MASK-NATIVE" else _geometry(content,id))
	return {"complete":true,"ok":not rows.is_empty() and rows.all(func(row: Dictionary)->bool:return row.ok),"cases":rows}

func _call(mask: PackedByteArray, first: int, last: int) -> Dictionary:
	return ClassDB.class_call_static("PlatformArrivalMath","grid_first_disabled",mask,first,last)

func _rejected(result: Dictionary) -> bool:
	return not result.get("ok",false) and result.has("error") and not result.has("blocked_id")

func _native() -> Dictionary:
	if not ClassDB.class_has_method("PlatformArrivalMath","grid_first_disabled"): return {"case":"MASK-NATIVE","ok":false,"error":"Build the native query before running its contract"}
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(FloorNavigation.LIMIT)
	mask.fill(1)
	mask[2*96+90] = 0
	mask[3*96+1] = 0
	mask[FloorNavigation.LIMIT-1] = 0
	var before: PackedByteArray = mask.duplicate()
	var checks: Dictionary = {
		"row_before_column":_call(mask,0,FloorNavigation.LIMIT-1).get("blocked_id",-2)==2*96+90,
		"complete_last_column":_call(mask,95,FloorNavigation.LIMIT-1).get("blocked_id",-2)==FloorNavigation.LIMIT-1,
		"complete_last_row":_call(mask,95*96,FloorNavigation.LIMIT-1).get("blocked_id",-2)==FloorNavigation.LIMIT-1,
		"outside_rectangle_not_scanned":_call(mask,4*96,5*96+95).get("blocked_id",-2)==-1,
		"single_origin":_call(mask,2*96+90,2*96+90).get("blocked_id",-2)==2*96+90,
		"bad_length":_rejected(_call(PackedByteArray([1]),0,0)),
		"negative_boundary":_rejected(_call(mask,-1,0)),
		"past_96":_rejected(_call(mask,0,FloorNavigation.LIMIT)),
		"reversed_columns":_rejected(_call(mask,2,96+1)),
		"reversed_rows":_rejected(_call(mask,96,0))
	}
	var invalid: PackedByteArray = mask.duplicate()
	invalid[0] = 2
	checks.invalid_scanned_value=_rejected(_call(invalid,0,1))
	checks.input_unchanged=mask==before
	return {"case":"MASK-NATIVE","ok":checks.values().all(func(value: Variant)->bool:return value==true),"checks":checks}

func _pair(space: HospitalSpace, world: WorldState, actor: Dictionary, from: Vector2, to: Vector2) -> Dictionary:
	var source: Dictionary = space._navigation.floor_source(space,world,1)
	var geometry: RouteClearance = space._navigation.cached_static_geometry(space,world,1,actor)
	var actual: Probe = Probe.new(space,world,actor,1,[],{},false,source,geometry)
	var expected: Complete = Complete.new(space,world,actor,1,[],{},false,source,geometry)
	var before: PackedByteArray = var_to_bytes(world.facts)
	var position: String = actual.position_reason(to)
	var reference_position: String = expected.position_reason(to)
	var position_calls: Array = [actual.reason_calls,expected.reason_calls]
	actual.reason_calls = 0
	expected.reason_calls = 0
	var sweep: String = actual.sweep_reason(from,to)
	var reference_sweep: String = expected.sweep_reason(from,to)
	return {"ok":position==reference_position and sweep==reference_sweep and var_to_bytes(world.facts)==before,"from":[from.x,from.y],"to":[to.x,to.y],"position":position,"sweep":sweep,"position_reason_calls":position_calls,"sweep_reason_calls":[actual.reason_calls,expected.reason_calls],"resident":geometry!=null}

func _geometry(content: HospitalContent, id: String) -> Dictionary:
	var suite: RefCounted = load("res://tests/acceptance/space.gd").new()
	suite.content = content
	var sim: HospitalSimulation = suite._fixture()
	var room: CommandResult = suite._command(sim,"build_room",suite._room("mask_room",[42,68],[14,10]))
	if not room.accepted: sim.dispose();return {"case":id,"ok":false,"prerequisite":room.to_record()}
	suite._add_actor(sim,"mask_actor","S49",[35.25,82.5])
	suite._add_actor(sim,"mask_peer","S49",[36.25,84.5])
	var actor: Dictionary = sim.world.facts.actors.mask_actor
	var space: HospitalSpace = HospitalSpace.new(content)
	var checks: Dictionary = {"legal_input":sim.world.validate(content).is_empty()}
	var rows: Array = []
	if id=="MASK-LIFETIME":
		var cold_entries: int = space._navigation._entries.size()
		rows.append(_pair(space,sim.world,actor,Vector2(35.25,82.5),Vector2(39.75,82.5)))
		checks.cold_no_new_graph=not rows[-1].resident and space._navigation._entries.size()==cold_entries
	var graph: FloorNavigation = space._navigation.graph(space,sim.world,1,actor,[],{})
	var geometry: RouteClearance = space._navigation.cached_static_geometry(space,sim.world,1,actor)
	checks.complete_matching_owner=geometry!=null and geometry._mask_geometry_id==geometry.get_instance_id() and graph._mask_ready
	if id=="MASK-LIFETIME":
		rows.append(_pair(space,sim.world,actor,Vector2(35.25,82.5),Vector2(39.75,82.5)))
		checks.clear_origins_skip_reason=rows[-1].sweep_reason_calls[0]==0 and int(rows[-1].sweep_reason_calls[1])>0
		checks.small_rectangle_complete_fallback=geometry._resident_first_disabled(Vector2i(35,82),Vector2i(36,82))==-2
		var current_source: Dictionary = space._navigation.floor_source(space,sim.world,1)
		var large_actor: Dictionary = actor.duplicate(true)
		large_actor.species_id="S59"
		var large_clone: RouteClearance = RouteClearance.new(space,sim.world,large_actor,1,[],{},false,current_source,geometry)
		checks.clone_size_gate=large_clone._mask_owner==null and not large_clone.position_reason(Vector2(62,82)).is_empty()
		var tall_actor: Dictionary = actor.duplicate(true)
		tall_actor._convoy_body=space.body(actor).duplicate(true)
		tall_actor._convoy_body.height_m=float(current_source.height)+1.0
		var tall_clone: RouteClearance = RouteClearance.new(space,sim.world,tall_actor,1,[],{},false,current_source,geometry)
		checks.clone_body_height_gate=tall_clone._mask_owner==null and tall_clone.position_reason(Vector2(35,82))=="真实身体超过本层实际净高"
		var low_source: Dictionary = current_source.duplicate(true)
		low_source.height=0.1
		var low_clone: RouteClearance = RouteClearance.new(space,sim.world,actor,1,[],{},false,low_source,geometry)
		checks.clone_ceiling_gate=low_clone._mask_owner==null and low_clone.position_reason(Vector2(35,82))=="真实身体超过本层实际净高"
		var original_species: String = actor.species_id
		actor.species_id = "S59"
		checks.body_change_cannot_borrow=space._navigation.cached_static_geometry(space,sim.world,1,actor)==null
		rows.append(_pair(space,sim.world,actor,Vector2(35.25,82.5),Vector2(39.75,82.5)))
		actor.species_id = original_species
		space._navigation._trim(0)
		checks.zero_budget_empty=space._navigation._entries.is_empty() and space._navigation._charged==0 and space._navigation._query_charged==0
		checks.existing_borrow_remains_usable=geometry._resident_first_disabled(Vector2i(35,82),Vector2i(39,83))==-1
		checks.new_acquisition_after_eviction_misses=space._navigation.cached_static_geometry(space,sim.world,1,actor)==null
		graph = null
		checks.weak_owner_does_not_pin=geometry._mask_owner.get_ref()==null and geometry._resident_first_disabled(Vector2i(35,82),Vector2i(39,83))==-2
		rows.append(_pair(space,sim.world,actor,Vector2(35.25,82.5),Vector2(39.75,82.5)))
		checks.evicted_lookup_no_build=space._navigation._entries.is_empty()
		graph = space._navigation.graph(space,sim.world,1,actor,[],{})
		geometry = graph.geometry
		sim.world.facts.floors.overrides["1"].blocked.append([38,82])
		sim.world.touch()
		checks.changed_source_cannot_borrow=space._navigation.cached_static_geometry(space,sim.world,1,actor)==null
		graph = space._navigation.graph(space,sim.world,1,actor,[],{})
		checks.old_geometry_rejected_after_refresh=geometry._resident_first_disabled(Vector2i(35,82),Vector2i(39,83))==-2
		rows.append(_pair(space,sim.world,actor,Vector2(35.25,82.5),Vector2(39.75,82.5)))
		var repair: RepairProbe = RepairProbe.new(graph.geometry)
		var replacement: RouteClearance = RouteClearance.new(space,sim.world,actor,1,[],{},false,space._navigation.floor_source(space,sim.world,1))
		repair.refresh(replacement)
		checks.half_repair_never_available=repair.half_repair_rejected and repair._mask_ready
	elif id=="MASK-BOUNDARIES":
		for species: String in ["S49","S59"]:
			actor.species_id = species
			space._navigation.graph(space,sim.world,1,actor,[],{})
			for endpoints: Array in [
				[Vector2(35.25,82.5),Vector2(39.75,82.5)],
				[Vector2(39.999996,78.00001),Vector2(40.000004,82.99999)],
				[Vector2(40,70),Vector2(45,70)],
				[Vector2(43.2,77.2),Vector2(44.2,78.2)],
				[Vector2(95,95),Vector2(95,95)],
				[Vector2(95.00001,95),Vector2(96,95)],
				[Vector2(-0.00001,82),Vector2(35,82)],
				[Vector2(32,64),Vector2(63,95)]]:
				rows.append(_pair(space,sim.world,actor,endpoints[0],endpoints[1]))
		actor.species_id = "S49"
		var source: Dictionary = RouteClearance.capture_source(space,sim.world,1)
		source.height = 0.1
		var low: RouteClearance = RouteClearance.new(space,sim.world,actor,1,[],{},false,source)
		var low_graph: FloorNavigation = FloorNavigation.new(low)
		checks.height_first=low_graph.geometry.sweep_reason(Vector2(35,82),Vector2(40,82))=="真实身体超过本层实际净高"
	elif id=="MASK-FIRST-REASON":
		var query: Probe = Probe.new(space,sim.world,actor,1,[],{},false,space._navigation.floor_source(space,sim.world,1),geometry)
		var full: Complete = Complete.new(space,sim.world,actor,1,[],{},false,space._navigation.floor_source(space,sim.world,1),geometry)
		query._reservations = [{"id":"earlier_reservation","regions":[Rect2(40,70,1,1)]}]
		full._reservations = query._reservations
		checks.reservation_gate=query._resident_first_disabled(Vector2i(40,70),Vector2i(46,70))==-2
		checks.reservation_first=query.sweep_reason(Vector2(40,70),Vector2(46,70))==full.sweep_reason(Vector2(40,70),Vector2(46,70)) and query.sweep_reason(Vector2(40,70),Vector2(46,70))=="真实展开与岗位预约阻挡：earlier_reservation"
		query._reservations = []
		full._reservations = []
		var member: RouteClearance = RouteClearance.new(space,sim.world,sim.world.facts.actors.mask_peer,1,[],{},false)
		member._blocked = member._blocked.duplicate()
		member._blocked[Vector2i(40,70)] = true
		query._members = [{"query":member,"offset":Vector2.ZERO}]
		full._members = query._members
		checks.member_gate=query._resident_first_disabled(Vector2i(40,70),Vector2i(46,70))==-2
		checks.member_first=query.sweep_reason(Vector2(40,70),Vector2(46,70))==full.sweep_reason(Vector2(40,70),Vector2(46,70)) and query.sweep_reason(Vector2(40,70),Vector2(46,70)).begins_with("通路不足")
		query._members = []
		checks.sweep_keeps_original_wall=query.sweep_reason(Vector2(41,70),Vector2(42,70))=="房间墙边阻挡真实身体"
	checks.all_complete_predicate_results=rows.all(func(row: Dictionary)->bool:return row.ok)
	checks.final_input_valid=sim.world.validate(content).is_empty()
	var ok: bool = checks.values().all(func(value: Variant)->bool:return value==true)
	sim.dispose()
	return {"case":id,"ok":ok,"checks":checks,"queries":rows}
