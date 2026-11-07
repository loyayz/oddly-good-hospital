extends SceneTree
const Oracle = preload("res://tools/performance/current/independent_payload_oracle.gd")
var checks: Dictionary = {}
var rows: Array = []
var output: String
func _initialize() -> void:
	output = OS.get_cmdline_user_args()[0]
	call_deferred("_run")
func check(label: String, ok: bool) -> void:
	checks[label] = ok
	print("ORACLE ",label," ",ok)
func account(cache: NavigationCache, label: String) -> void:
	var row: Dictionary = Oracle.resident_accounting(cache)
	row.label = label
	rows.append(row)
	check(label+"_accounting",row.counter_exact and row.undercharged.is_empty())
func snapshot(world: WorldState, label: String) -> void:
	var file: FileAccess = FileAccess.open(output+"."+label+".bin",FileAccess.WRITE)
	file.store_buffer(var_to_bytes(world.freeze()))
	file.close()
func _run() -> void:
	var content: HospitalContent = HospitalContent.new()
	var world: WorldState = HospitalFactory.create(HospitalSnapshots.uuid(),"Independent payload ownership",false,content)
	HospitalFactory._add_facility(world,{"id":"oracle_facility","definition_id":"M37","anchor":[44,76],"size":content.facility_definition("M37").footprint.duplicate(),"room_id":null},content)
	var fixture: RefCounted = load("res://tests/acceptance/navigation_static_versions.gd").new()
	world.facts.actors["oracle_owner"] = fixture._actor("oracle_owner",[35,86])
	world.facts.actors["oracle_traveller"] = fixture._actor("oracle_traveller",[36,86])
	world.touch()
	check("legal_initial",world.validate(content).is_empty())
	snapshot(world,"initial")
	var space: HospitalSpace = HospitalSpace.new(content)
	var cache: NavigationCache = space._navigation
	var key: String = str(world.get_instance_id())+":1"
	var before: Dictionary = world.freeze()
	var source: Dictionary = cache.floor_source(space,world,1)
	var record: Dictionary = cache._sources[key]
	var old_copy: Dictionary = source.duplicate(true)
	var static_version: String = record.static_version
	check("payload_recursive_readonly",Oracle.readonly_tree(source) and Oracle.readonly_tree(record.static_source))
	check("world_recursive_writable",Oracle.writable_tree(world.facts))
	check("pure_read",world.freeze()==before)
	check("fresh_charge_direct",record.charge==Oracle.expected_charge(record))
	account(cache,"initial")
	check("reserve_success",space.reserve_facility(world,"oracle_facility","oracle_owner","oracle_owner").is_empty())
	space.grant_facility_access(world,"oracle_facility","oracle_traveller")
	snapshot(world,"permission")
	var current: Dictionary = cache.floor_source(space,world,1)
	record = cache._sources[key]
	check("permission_changes_full_not_static",current!=old_copy and record.static_version==static_version)
	check("old_borrower_stable",source==old_copy)
	check("new_source_matches_fresh_capture",current==RouteClearance.capture_source(space,world,1))
	check("permission_charge_direct",record.charge==Oracle.expected_charge(record))
	account(cache,"permission")
	var hypothetical: Dictionary = current.duplicate(true)
	check("deep_duplicate_writable",Oracle.writable_tree(hypothetical))
	hypothetical.facilities.erase("oracle_facility")
	var real_before: Dictionary = world.freeze()
	space._navigation.floor_geometry(space,world,1,hypothetical)
	check("external_hypothetical_not_frozen",Oracle.writable_tree(hypothetical))
	hypothetical.layout.blocked.append([45,85])
	check("hypothetical_edit_isolated",current.facilities.has("oracle_facility") and not current.layout.blocked.has([45,85]) and world.freeze()==real_before)
	var cow: Dictionary = current.duplicate()
	cow.facilities = cow.facilities.duplicate()
	cow.facilities.erase("oracle_facility")
	check("shallow_cow_edit_isolated",not cow.facilities.has("oracle_facility") and current.facilities.has("oracle_facility") and Oracle.readonly_tree(current))
	cache.graph(space,world,1,world.facts.actors.oracle_traveller,[],{})
	record = cache._sources[key]
	check("real_graph_proof_present",not record.graphs.is_empty())
	check("graph_proof_charge_direct",record.charge==Oracle.expected_charge(record))
	account(cache,"graph")
	cache._trim(4*int(record.charge))
	check("real_graph_eviction_proofs_removed",cache._entries.is_empty() and record.graphs.is_empty())
	account(cache,"after_graph_eviction")
	cache.floor_source(space,world,1)
	record = cache._sources[key]
	check("after_proof_removal_store_charge_direct",record.charge==Oracle.expected_charge(record))
	# A separate cache isolates source-only quarter arithmetic from graph/floor pressure.
	var isolated: NavigationCache = NavigationCache.new()
	isolated.floor_source(space,world,1)
	var borrowed: Dictionary = isolated._sources[key]
	var c: int = Oracle.expected_charge(borrowed)
	isolated._trim_source_payloads(4*c)
	check("exact_quarter_retained",isolated._sources.has(key) and isolated._source_charged==c)
	isolated._trim_source_payloads(4*c-1)
	check("one_below_quarter_evicted",isolated._sources.is_empty() and isolated._source_charged==0)
	isolated._store_source(key,borrowed)
	check("borrower_reinsert_no_double_charge",isolated._source_charged==c and borrowed.charge==Oracle.expected_charge(borrowed))
	isolated._trim_source_payloads(0)
	check("zero_target_releases",isolated._sources.is_empty() and isolated._source_charged==0 and borrowed.source==current)
	var reentered: Dictionary = isolated.floor_source(space,world,1)
	check("fresh_reentry_equal_readonly",reentered==current and Oracle.readonly_tree(reentered))
	account(isolated,"reentry")
	check("final_world_legal_writable",world.validate(content).is_empty() and Oracle.writable_tree(world.facts))
	check("query_operations_pure",world.freeze()==real_before)
	var passed: bool = not checks.values().has(false)
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"complete":true,"passed":passed,"checks":checks,"accounting":rows,"expected_isolated_charge":c},"\t"))
	file.close()
	quit(0 if passed else 1)
