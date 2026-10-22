extends "res://tests/acceptance/staff_fixtures.gd"

# The design's bounded four-neighbour propagation is calculated independently
# from raw world facts. Neither the prepared masks nor the native graph decide
# the expected distances or the complete discovery order.
func _reference(x: Dictionary, floor_id: int, origin: Array, radius: int, noise: bool) -> Dictionary:
	var root: Array = [int(origin[0]),int(origin[1])]
	var found: Dictionary = {"%d:%d" % root:0}
	var pending: Array = [root]
	var cursor: int = 0
	while cursor<pending.size():
		var cell: Array = pending[cursor]
		cursor += 1
		var distance: int = found["%d:%d" % cell]
		if distance>=radius: continue
		for delta: Array in [[-1,0],[0,-1],[0,1],[1,0]]:
			var next: Array = [cell[0]+delta[0],cell[1]+delta[1]]
			var key: String = "%d:%d" % next
			if not found.has(key) and x.e._edge_open(x.world,floor_id,cell,next,noise):
				found[key] = distance+1
				pending.append(next)
	return found

func _count(x: Dictionary, name: String) -> int:
	return int(x.space.query_counts.get("environment_coverage_"+name,0))

func _compare(x: Dictionary, label: String, floor_id: int, origin: Array, radius: int, noise: bool, edges: Dictionary) -> Dictionary:
	var frozen: Dictionary = x.world.freeze()
	var expected: Dictionary = _reference(x,floor_id,origin,radius,noise)
	var native: int = _count(x,"native_calls")
	var fallback: int = _count(x,"fallbacks")
	var actual: Dictionary = x.e._coverage(x.world,floor_id,origin,radius,noise,edges)
	return {"ok":actual==expected and actual.keys()==expected.keys() and x.world.freeze()==frozen,"label":label,"origin":origin,"radius":radius,"noise":noise,"complete_distances_equal":actual==expected,"complete_discovery_order_equal":actual.keys()==expected.keys(),"cells":actual.size(),"native_calls":_count(x,"native_calls")-native,"fallback_calls":_count(x,"fallbacks")-fallback,"actual":actual}

func _dispose(x: Dictionary) -> void:
	x.a.dispose()
	x.p.waiting_life = null
	x.p.environment = null
	x.l.environment = null
	x.l.visitors = null
	x.c.recruitment = null
	x.clear()

func run_ranges(database: HospitalContent) -> Dictionary:
	_content = database
	var x: Dictionary = _fixture()
	x.world.facts.floors.overrides["1"].plots = []
	for y: int in 3:
		for column: int in 3: x.world.facts.floors.overrides["1"].plots.append([column,y])
	x.world.facts.floors.overrides["1"].blocked = [[32,32],[33,33]]
	x.world.touch()
	var edges: Dictionary = x.e._coverage_edges(x.world,1)
	var checks: Dictionary = {"legal_input":x.world.validate(database).is_empty(),"one_native_mask_for_source":_count(x,"mask_builds")==1 and edges.get("native_coverage",{}).get("ready",false)}
	var rows: Array = []
	var positive_fraction: Dictionary = {}
	var zero_fraction: Dictionary = {}
	for input: Array in [[[48,48],-3],[[48,48],0],[[48,48],1],[[48,48],4],[[48,48],5],[[0,0],4],[[95,95],4],[[32,32],1],[[44.25,80.99],4],[[44.99,80.01],4],[[45.01,80.99],4],[[-0.25,0.75],2],[[-0.99,-0.01],2],[[-1.01,0.75],2],[[95.99,95.99],4],[[96.01,95.99],2],[[44.25,-1.01],2],[[44.25,96.01],2],[[-1,0],2],[[96,95],2],[[48,48],9223372036854775807]]:
		var observed: Dictionary = _compare(x,"radius_and_origin",1,input[0],int(input[1]),false,edges)
		if input[0]==[48,48] and input[1]<=0: checks["radius_"+str(input[1])+"_only_root"] = observed.actual=={"48:48":0}
		if input[0]==[48,48] and input[1]==1: checks.authored_neighbour_order_preserved = observed.actual.keys()==["48:48","47:48","48:47","48:49","49:48"]
		if input[0]==[32,32]: checks.blocked_root_still_leaves_to_legal_next = observed.actual.get("32:32",-1)==0 and observed.actual.get("31:32",-1)==1
		var root: Array = [int(input[0][0]),int(input[0][1])]
		observed.normalized_origin = root
		if root[0]<0 or root[1]<0 or root[0]>=96 or root[1]>=96: observed.ok = observed.ok and observed.native_calls==0 and observed.fallback_calls==1
		else: observed.ok = observed.ok and observed.native_calls==1 and observed.fallback_calls==0
		if input[0]==[44.25,80.99]: positive_fraction = observed.actual
		if input[0]==[44.99,80.01]: checks.positive_fractions_in_same_cell_keep_full_coverage = observed.actual==positive_fraction and observed.actual.keys()==positive_fraction.keys()
		if input[0]==[45.01,80.99]: checks.positive_fraction_crossing_cell_changes_root = observed.actual.get("45:80",-1)==0 and positive_fraction.get("45:80",-1)==1
		if input[0]==[-0.25,0.75]: zero_fraction = observed.actual
		if input[0]==[-0.99,-0.01]: checks.negative_fraction_truncates_toward_zero = observed.actual==zero_fraction and observed.actual.keys()==zero_fraction.keys() and observed.actual.get("0:0",-1)==0
		if input[0]==[-1.01,0.75]: checks.negative_fraction_crossing_domain_keeps_outside_root = observed.actual.get("-1:0",-1)==0 and observed.actual.get("0:0",-1)==1
		observed.erase("actual")
		rows.append(observed)
	var compact: Dictionary = PlatformArrivalMath.environment_coverage(edges.native_coverage.ordinary,{"root":48*96+48,"radius":1})
	checks.native_returns_only_sparse_reachable_triples = compact.get("ready",false) and compact.cells.size()==15
	var outside: Dictionary = _fixture()
	var outside_edges: Dictionary = outside.e._coverage_edges(outside.world,1)
	var unowned: Dictionary = _compare(outside,"unowned_root_can_enter_owned_neighbour",1,[31,70],1,false,outside_edges)
	checks.unowned_root_can_leave = unowned.actual.get("31:70",-1)==0 and unowned.actual.get("32:70",-1)==1 and unowned.native_calls==1
	unowned.erase("actual")
	rows.append(unowned)
	# A special source stays on the complete script path; no domain is clipped.
	x.world.facts.floors.overrides["1"].plots.append([3,0])
	x.world.touch()
	var unsupported: Dictionary = x.e._coverage_edges(x.world,1)
	var special: Dictionary = _compare(x,"unsupported_source_full_fallback",1,[95,30],3,false,unsupported)
	checks.unsupported_source_has_no_native_hit = not unsupported.native_coverage.get("ready",false) and special.native_calls==0 and special.fallback_calls==1
	special.erase("actual")
	rows.append(special)
	var lifecycle: Dictionary = _cache_lifecycle()
	var permissions: Dictionary = preload("res://tests/acceptance/environment_source_lifecycle.gd").new().run(database)
	var result: Dictionary = {"ok":not checks.values().has(false) and rows.all(func(row: Dictionary)->bool:return row.ok) and lifecycle.ok and permissions.ok,"checks":checks,"complete_coverage":rows,"cache_lifecycle":lifecycle,"live_sources_and_permissions":permissions,"scope":"Coverage calculations and source/cache boundaries; actual environment scoring and R15 ranges remain the containing OPS-11 case."}
	_dispose(x)
	_dispose(outside)
	return result

func _cache_lifecycle() -> Dictionary:
	var x: Dictionary = _fixture()
	var checks: Dictionary = {}
	var service: HospitalEnvironment = x.e
	service.begin_query(x.world)
	var original: Dictionary = service._coverage_edges(x.world,1)
	var first: Dictionary = service._coverage(x.world,1,[44,80],4,false,original)
	var calls: int = _count(x,"native_calls")
	var repeated: Dictionary = service._coverage(x.world,1,[44,80],4,false,original)
	checks.same_scope_reuses_result = is_same(first,repeated) and _count(x,"native_calls")==calls
	service.end_query()
	service.begin_query(x.world)
	var retained: Dictionary = service._coverage_edges(x.world,1)
	var reused: Dictionary = service._coverage(x.world,1,[44,80],4,false,retained)
	checks.next_scope_reuses_static_mask_and_result = is_same(original,retained) and is_same(first,reused) and _count(x,"mask_builds")==1 and _count(x,"native_calls")==calls
	service.end_query()
	x.world.facts.floors.overrides["1"].blocked.append([45,80])
	x.world.touch()
	var changed: Dictionary = service._coverage_edges(x.world,1)
	var updated: Dictionary = _compare(x,"real_blocked_change",1,[44,80],4,false,changed)
	checks.changed_source_replaces_mask_and_old_negative_result = not is_same(changed,retained) and _count(x,"mask_builds")==2 and updated.ok and not updated.actual.has("45:80")
	# No scope may borrow a previous coverage result after a raw source edit.
	x.world.facts.floors.overrides["1"].blocked.clear()
	var direct: Dictionary = service._coverage_edges(x.world,1)
	var fresh: Dictionary = _compare(x,"direct_source_refresh_without_revision",1,[44,80],4,false,direct)
	checks.no_scope_rechecks_current_complete_source = fresh.ok and fresh.actual.has("45:80") and _count(x,"mask_builds")==3
	var previous_world: WorldState = x.world
	x.world = WorldState.new(previous_world.freeze())
	x.world.facts.floors.overrides["1"].blocked.append([44,79])
	var other: Dictionary = service._coverage_edges(x.world,1)
	var switched: Dictionary = _compare(x,"changed_world_geometry",1,[44,80],4,false,other)
	checks.other_world_does_not_borrow_different_geometry = switched.ok and not switched.actual.has("44:79") and previous_world.facts.floors.overrides["1"].blocked.is_empty()
	service.begin_query(x.world)
	var bounded: Dictionary = service._coverage_edges(x.world,1)
	for index: int in 140: service._coverage(x.world,1,[33+index%28,65+index/28],1,false,bounded)
	service.end_query()
	checks.original_128_result_limit_kept = service._coverage_cache[1].coverage.size()==128
	x.world.facts.floors.height_intervals[0].last = 10
	for floor_id: int in range(2,11): x.world.facts.floors.overrides[str(floor_id)] = {"plots":[[1,2]],"blocked":[],"doors":[],"paths":[]}
	x.world.touch()
	for floor_id: int in range(2,11): service._coverage_edges(x.world,floor_id)
	checks.original_eight_floor_limit_kept = service._coverage_cache.size()==8 and not service._coverage_cache.has(1)
	var builds: int = _count(x,"mask_builds")
	service._coverage_edges(x.world,1)
	checks.evicted_source_rebuilds_its_mask = _count(x,"mask_builds")==builds+1 and service._coverage_cache.size()==8
	var result: Dictionary = {"ok":not checks.values().has(false),"checks":checks,"mask_builds":_count(x,"mask_builds"),"native_misses":_count(x,"native_calls"),"fallback_misses":_count(x,"fallbacks")}
	_dispose(x)
	return result

func run_barriers(database: HospitalContent) -> Dictionary:
	_content = database
	var x: Dictionary = _fixture()
	HospitalFactory._add_room(x.world,{"id":"coverage_room","type":"waiting","anchor":[40,70],"size":[8,8],"door":{"definition_id":"DR04","offset":3}},database)
	_facility(x,"coverage_screen","FUR23",[45,75],"coverage_room")
	x.world.touch()
	var rows: Array = []
	var checks: Dictionary = {"legal_input":x.world.validate(database).is_empty()}
	var edges: Dictionary = x.e._coverage_edges(x.world,1)
	for query: Array in [[[45,76],1,false],[[45,76],1,true],[[45,76],3,true],[[43,77],3,false],[[40,70],4,false]]:
		var observed: Dictionary = _compare(x,"walls_door_and_screen",1,query[0],query[1],query[2],edges)
		if query[0]==[45,76] and query[1]==1: checks["screen_direct_"+str(query[2])] = observed.actual.has("45:75")!=bool(query[2])
		if query[0]==[45,76] and query[1]==3: checks.screen_can_be_bypassed_in_three_steps = observed.actual.get("45:75",-1)==3
		if query[0]==[43,77]: checks.real_door_opens_wall_edge = observed.actual.has("43:79")
		observed.erase("actual")
		rows.append(observed)
	var door: Dictionary = x.world.facts.floors.overrides["1"].doors.pop_back()
	x.world.touch()
	var closed: Dictionary = _compare(x,"door_removed",1,[43,77],3,false,x.e._coverage_edges(x.world,1))
	checks.closed_wall_stops_propagation = not closed.actual.has("43:79")
	closed.erase("actual")
	rows.append(closed)
	x.world.facts.floors.overrides["1"].doors.append(door)
	x.world.facts.facilities.coverage_screen.rotation = 1
	x.world.touch()
	var rotated: Dictionary = _compare(x,"screen_rotated",1,[45,76],1,true,x.e._coverage_edges(x.world,1))
	checks.rotation_changes_only_screened_edge = rotated.actual.has("45:75")
	rotated.erase("actual")
	rows.append(rotated)
	x.world.facts.facilities.coverage_screen.cell = [46,75]
	x.world.touch()
	var moved: Dictionary = _compare(x,"screen_moved",1,[46,75],1,true,x.e._coverage_edges(x.world,1))
	checks.move_replaces_screen_edge = not moved.actual.has("47:75")
	moved.erase("actual")
	rows.append(moved)
	var malformed: Dictionary = PlatformArrivalMath.environment_coverage(PackedByteArray(),{"root":0,"radius":4})
	var outside: Dictionary = PlatformArrivalMath.environment_coverage(edges.native_coverage.ordinary,{"root":-1,"radius":4})
	checks.special_native_input_declines_without_false_success = not malformed.get("ready",false) and not malformed.has("error") and not outside.get("ready",false) and not outside.has("error")
	var result: Dictionary = {"ok":not checks.values().has(false) and rows.all(func(row: Dictionary)->bool:return row.ok),"checks":checks,"complete_barrier_coverage":rows,"scope":"Bounded propagation only. The containing OPS-18 separately executes clinical/construction noise sources and actual screen commands."}
	_dispose(x)
	return result
