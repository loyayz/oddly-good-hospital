extends "res://tests/acceptance/public_region_build.gd"

# Narrow calculation companion to STAFF-75. Fixtures are legal input states,
# never proof that movement, arrival, or use occurred. The existing real flows
# remain SPACE-49, STAFF-69, and furniture-free rest in STAFF-21.
const OriginalSelect = preload("public_select_original.gd")
const ACTOR: String = "patient_absent_select"
const MAX_TICKS: int = 9223372036854775807

class CountingSpace extends HospitalSpace:
	var dynamic_begins: int = 0
	var actor_index_calls: int = 0
	func begin_dynamic_route_query(world: WorldState, refresh_actors: bool = true) -> void:
		dynamic_begins += 1
		super.begin_dynamic_route_query(world,refresh_actors)
	func _ensure_actor_index(world: WorldState) -> void:
		actor_index_calls += 1
		super._ensure_actor_index(world)

class CountingAreas extends HospitalPublicAreas:
	var ensure_calls: int = 0
	func _ensure(world: WorldState, requested_floor: int = 0) -> void:
		ensure_calls += 1
		super._ensure(world,requested_floor)

func _probe() -> CountingAreas:
	var geometry: CountingSpace = CountingSpace.new(_content)
	var areas: CountingAreas = CountingAreas.new(geometry)
	# Keep the strong service owner outside its WeakRef back-reference.
	_owners.append(geometry)
	geometry.public_areas = areas
	return areas

var _owners: Array = []

func run_case(database: HospitalContent) -> Dictionary:
	_content = database
	var x: Dictionary = _areas()
	_visit(x,"absent_select",[38,74])
	x.world.touch()
	var original: Dictionary = x.world.freeze()
	var tick: int = x.world.sim_tick
	var checks: Dictionary = {"legal_original":x.world.validate(database).is_empty()}
	var rows: Array = []
	var actual: CountingAreas = _probe()

	# No requested furniture means no derived geometry, query, or index work,
	# both cold and after a successful query has retained real region views.
	rows.append(_observe("cold_absent_definition",x.world,actual,["FUR07"],[""],"toilet",true,true))
	rows.append(_observe("cold_empty_definitions",x.world,actual,[],[""],"seat",true,true))
	rows.append(_observe("warm_matching_definition",x.world,actual,["FUR09"],[""],"seat",false,false))
	rows.append(_observe("warm_absent_definition",x.world,actual,["FUR07"],[""],"toilet",true,true))
	rows.append(_observe("warm_empty_definitions",x.world,actual,[],[""],"recreation",true,true))
	actual.space.begin_dynamic_route_query(x.world)
	var outer: Dictionary = actual.space._route_queries.back()
	rows.append(_observe("absent_inside_caller_query",x.world,actual,["FUR07"],[""],"toilet",true,true))
	checks.caller_query_survives_empty_selection = actual.space._route_queries.size()==1 and is_same(outer,actual.space._route_queries.back())
	actual.space.end_route_query()
	checks.initial_queries_readonly = x.world.freeze()==original

	_live_edit_rows(original,tick,checks,rows)

	# Alternate same-revision independent worlds through one service. The
	# definition-presence decision must read this world, not the last owner or
	# an old result. A skipped query must not switch retained mutable views.
	var present: WorldState = WorldState.new(original.duplicate(true))
	var absent: WorldState = WorldState.new(original.duplicate(true))
	absent.facts.facilities.clear()
	var restored: WorldState = WorldState.new(present.freeze())
	var restored_absent: WorldState = WorldState.new(absent.freeze())
	checks.independent_worlds_share_revision_not_facilities = present.revision==absent.revision and present.geometry_revision==absent.geometry_revision and not is_same(present.facts.facilities,absent.facts.facilities)
	for pair: Array in [["independent_present",present,false],["independent_absent",absent,true],["restored_present",restored,false],["restored_absent",restored_absent,true],["return_original_present",present,false]]:
		rows.append(_observe(pair[0],pair[1],actual,["FUR09"],[""],"seat",pair[2],pair[2]))
	checks.source_world_never_changed = x.world.freeze()==original

	# Presence is deliberately a conservative definition-only test. Failed,
	# stored, or wrong-room matches must still reach the full original path.
	for variant: String in ["failed","stored","wrong_room"]:
		var world: WorldState = WorldState.new(original.duplicate(true))
		for facility: Dictionary in world.facts.facilities.values():
			if variant!="wrong_room": facility[variant] = true
		world.touch()
		rows.append(_observe("present_but_"+variant,world,_probe(),["FUR09"],["rest"] if variant=="wrong_room" else [""],"seat",true,false))
	var mixed: WorldState = WorldState.new(original.duplicate(true))
	rows.append(_observe("mixed_absent_matching_and_duplicate_definitions",mixed,_probe(),["FUR07","FUR09","FUR06","FUR09"],[""],"seat",false,false))

	# Existing real reservation API creates a busy legal calculation boundary.
	# The holder starts at the genuine facility patient cell; no move, arrival,
	# tick, seated phase, or completed-use fact is fabricated by this fixture.
	var busy: Dictionary = _areas()
	_visit(busy,"absent_select",[38,74])
	busy.world.facts.facilities.erase("east_chair")
	var holder_cell: Array = busy.space.facility_layout(busy.world,"west_chair").patient_cell
	var holder: Dictionary = _visit(busy,"occupied_input",holder_cell)
	busy.world.touch()
	var reserved: String = busy.space.reserve_facility(busy.world,"west_chair",holder.actor_id,holder.actor_id)
	checks.busy_input_has_real_exclusive_reservation = reserved.is_empty() and busy.world.facts.adaptations.has("west_chair") and not busy.space.facility_quote(busy.world,"west_chair",ACTOR).get("ok",true)
	rows.append(_observe("present_busy_region_still_selectable",busy.world,_probe(),["FUR09"],[""],"seat",false,false))

	# With no qualifying fixture there is no generated public region.
	# Safe ordinary standing on owned public floor remains independent from
	# finding an area or falsely promising an available seat.
	for purpose: String in ["rest","waiting"]:
		var world: WorldState = WorldState.new(original.duplicate(true))
		world.facts.facilities.clear()
		world.touch()
		for definitions: Array in [[],["FUR09"]]:
			var standing: CountingAreas = _probe()
			var row: Dictionary = _observe(purpose+"_without_furniture_"+str(definitions.size()),world,standing,definitions,["rest"] if purpose=="rest" else [""],purpose,true,false)
			var point: Dictionary = standing.floor_waiting_point(world,ACTOR)
			row.safe_standing = not point.is_empty() and standing.safe_wait(world,ACTOR,int(point.get("floor_id",0)),point.get("cell",[]))
			row.ok = row.ok and row.safe_standing and world.facts.facilities.is_empty()
			rows.append(row)

	checks.all_query_scopes_closed = _owners.all(func(owner: HospitalSpace)->bool:return owner._route_queries.is_empty())
	var result: Dictionary = {"ok":not checks.values().has(false) and rows.all(func(row: Dictionary)->bool:return row.ok),"checks":checks,"observations":rows,"scope":"Read-only region-selection calculations, original full select oracle, untouched empty-result output and runtime owners. No movement/arrival/use flow is claimed; existing STAFF-21, STAFF-69 and SPACE-49 own those handoffs."}
	_release(x)
	_release(busy)
	_owners.clear()
	return result

func run_live_edit_case(database: HospitalContent) -> Dictionary:
	_content = database
	var x: Dictionary = _areas()
	_visit(x,"absent_select",[38,74])
	x.world.touch()
	var original: Dictionary = x.world.freeze()
	var checks: Dictionary = {"legal_original":x.world.validate(database).is_empty()}
	var rows: Array = []
	_live_edit_rows(original,x.world.sim_tick,checks,rows)
	checks.source_world_never_changed = x.world.freeze()==original
	checks.all_query_scopes_closed = _owners.all(func(owner: HospitalSpace)->bool:return owner._route_queries.is_empty())
	var result: Dictionary = {"ok":not checks.values().has(false) and rows.all(func(row: Dictionary)->bool:return row.ok),"checks":checks,"observations":rows,"scope":"Affected same-tick add/remove/re-add calculation group only; unaffected candidate-01 groups are not repeated."}
	_release(x)
	_owners.clear()
	return result

func _live_edit_rows(original: Dictionary, tick: int, checks: Dictionary, rows: Array) -> void:
	# Geometry edits use the existing invalidation contract, but do not advance
	# simulation time. This guards against a cached negative result or a changed
	# retry schedule, without demanding unsupported raw-geometry invalidation.
	var edited: WorldState = WorldState.new(original.duplicate(true))
	var saved: Dictionary = edited.facts.facilities.duplicate(true)
	edited.facts.facilities.clear()
	edited.touch()
	var live: CountingAreas = _probe()
	rows.append(_observe("same_tick_before_add",edited,live,["FUR09"],[""],"seat",true,true))
	edited.facts.facilities["west_chair"] = saved.west_chair.duplicate(true)
	edited.touch()
	rows.append(_observe("same_tick_direct_add",edited,live,["FUR09"],[""],"seat",false,false))
	edited.facts.facilities.erase("west_chair")
	edited.touch()
	rows.append(_observe("same_tick_direct_remove",edited,live,["FUR09"],[""],"seat",true,true))
	edited.facts.facilities["west_chair"] = saved.west_chair.duplicate(true)
	edited.touch()
	rows.append(_observe("same_tick_direct_readd",edited,live,["FUR09"],[""],"seat",false,false))
	checks.all_live_edits_keep_original_tick = edited.sim_tick==tick


func _observe(label: String, world: WorldState, actual: CountingAreas, definitions: Array, room_kinds: Array, purpose: String, empty: bool, skipped: bool) -> Dictionary:
	var validation: String = world.validate(_content)
	var facts: Dictionary = world.freeze()
	var arguments: Array = [definitions.duplicate(true),room_kinds.duplicate(true)]
	var entries: Dictionary = {"keep":{"nested":["unchanged"]},ACTOR:{"prior":"unchanged_on_failure"}}
	var seed: Dictionary = entries.duplicate(true)
	var sentinel: Dictionary = entries.keep
	var runtime: Dictionary = _runtime(actual)
	var geometry: CountingSpace = actual.space
	var before_ensure: int = actual.ensure_calls
	var before_dynamic: int = geometry.dynamic_begins
	var before_actor: int = geometry.actor_index_calls
	var observed: Dictionary = actual.select(world,ACTOR,definitions,room_kinds,purpose,[],MAX_TICKS,entries)
	var ensure_delta: int = actual.ensure_calls-before_ensure
	var dynamic_delta: int = geometry.dynamic_begins-before_dynamic
	var actor_delta: int = geometry.actor_index_calls-before_actor
	var untouched: bool = _runtime(actual)==runtime
	var readonly: bool = world.freeze()==facts and definitions==arguments[0] and room_kinds==arguments[1]
	var reference_space: HospitalSpace = HospitalSpace.new(_content)
	var reference: HospitalPublicAreas = OriginalSelect.new(reference_space)
	reference_space.public_areas = reference
	var expected_entries: Dictionary = seed.duplicate(true)
	var expected: Dictionary = reference.select(world,ACTOR,definitions,room_kinds,purpose,[],MAX_TICKS,expected_entries)
	var equal: bool = observed==expected and entries==expected_entries
	var output: bool = entries==seed if empty else entries.has(ACTOR) and entries[ACTOR].has("travel_ticks")
	output = output and is_same(sentinel,entries.keep) and entries.keep==seed.keep
	var ownership: bool = not skipped or untouched
	var closed: bool = actual.space._route_queries.size()==runtime.query_depth and reference_space._route_queries.is_empty()
	return {"ok":validation.is_empty() and readonly and facts==world.freeze() and equal and observed.is_empty()==empty and output and ownership and closed,"boundary":label,"valid_input":validation,"result":observed,"same_complete_selection_and_entries":equal,"world_rng_and_arguments_unchanged":readonly and facts==world.freeze(),"output_preserved_or_correctly_merged":output,"expected_empty":empty,"skipped_materialization":skipped,"runtime_untouched":untouched,"ensure_calls":ensure_delta,"dynamic_query_begins":dynamic_delta,"actor_index_calls":actor_delta,"query_scope_preserved":closed}

func _runtime(areas: CountingAreas) -> Dictionary:
	var geometry: CountingSpace = areas.space
	var records: Array = []
	for id: String in geometry._actor_index._records:
		var record: BodyIndex.Record = geometry._actor_index._records[id]
		records.append([id,record,record.floor_id,record.rect,record.regions.duplicate(),record.boundary])
	return {"ensure_calls":areas.ensure_calls,"query_counts":geometry.query_counts.duplicate(true),"dynamic_begins":geometry.dynamic_begins,"actor_calls":geometry.actor_index_calls,"actor_index":geometry._actor_index,"actor_records":records,"indexed_world":geometry._indexed_world,"indexed_revision":geometry._indexed_revision,"actor_scope":geometry._indexed_actor_scope,"query_depth":geometry._route_queries.size(),"area_world":null if areas._world==null else areas._world.get_ref(),"area_revision":areas._revision,"regions":areas._regions.duplicate(true),"floor_ids":areas._floor_regions.keys(),"derived_floors":areas._derived_floors.duplicate(),"definitions":areas._regions_by_definition.duplicate(true)}

func _release(x: Dictionary) -> void:
	x.a.dispose()
	x.p.waiting_life = null
	x.p.environment = null
	x.e.waiting_life = null
	x.l.environment = null
	x.l.visitors = null
	x.c.recruitment = null
	x.clear()
