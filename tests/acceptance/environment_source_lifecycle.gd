extends "res://tests/acceptance/staff_fixtures.gd"

func _counts(x: Dictionary) -> Array:
	var counts: Dictionary = x.space.query_counts
	return [int(counts.get("environment_facility_source_builds",0)),int(counts.get("environment_dynamic_source_builds",0)),int(counts.get("environment_actor_source_builds",0))]

func _read(x: Dictionary, cell: Array, actor_id: String = "subject", nearby: bool = false) -> Dictionary:
	var result: Dictionary = x.e.environment_at(x.world,1,cell,actor_id) if nearby else x.e.sample_at(x.world,1,cell,actor_id)
	# Source record order is explanatory, as in OPS-11/18's original reference.
	result.sources.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return JSON.stringify(a)<JSON.stringify(b))
	return result

func _matches(x: Dictionary, cell: Array, actor_id: String = "subject", nearby: bool = false) -> Dictionary:
	var before: Dictionary = x.world.freeze()
	# The no-scope path enumerates original facts, independently of every new
	# source view, sample bucket and nearby-person bucket.
	var expected: Dictionary = _read(x,cell,actor_id,nearby)
	x.e.begin_query(x.world)
	var actual: Dictionary = _read(x,cell,actor_id,nearby)
	x.e.end_query()
	return {"ok":actual==expected and before==x.world.freeze(),"expected":expected,"actual":actual}

func run(database: HospitalContent) -> Dictionary:
	_content = database
	var x: Dictionary = _fixture({"subject":"doctor","neighbor":"nurse"})
	_facility(x,"plant","FUR25",[42,79])
	_facility(x,"light","FUR19",[42,82])
	_facility(x,"water","FUR17",[50,80])
	_facility(x,"screen","FUR23",[48,84])
	x.world.touch()
	_position(x,"subject",[44,80])
	_position(x,"neighbor",[45,80])
	x.e.waiting_life = x.l
	var service: HospitalEnvironment = x.e
	var checks: Dictionary = {}
	var frozen: Dictionary = x.world.freeze()
	for _scope: int in 20:
		service.begin_query(x.world)
		service.end_query()
	checks.empty_scopes_acquire_no_sources = _counts(x)==[0,0,0] and service.query_builds==20 and service._query.is_empty() and service._query_depth==0 and frozen==x.world.freeze()
	var expected: Dictionary = _read(x,[44,80])
	var before: Dictionary = x.world.freeze()
	service.begin_query(x.world)
	service.begin_query(x.world)
	var first: Dictionary = _read(x,[44,80])
	var second: Dictionary = _read(x,[44,80])
	service.end_query()
	checks.same_nested_scope_prepares_each_consumed_source_once = first==expected and second==expected and _counts(x)==[1,1,0] and service._query_depth==1 and service.query_builds==21
	service.end_query()
	checks.close_releases_dynamic_scope = service._query_depth==0 and service._query.is_empty() and before==x.world.freeze()
	var static_source: Dictionary = service._facility_sources
	var repeated: bool = true
	for _scope: int in 4:
		repeated = repeated and _matches(x,[44,80]).ok
	checks.new_consumers_reacquire_dynamic_and_reuse_static = repeated and _counts(x)==[1,5,0] and is_same(service._facility_sources,static_source)
	# These boundaries do not move any source: mutable facility fields must be
	# read from current facts rather than copies held by the position index.
	x.world.facts.facilities.light.failed = true
	var failed: Dictionary = _matches(x,[44,80])
	checks.same_tick_failure_is_live = failed.ok and int(failed.actual.value)<int(first.value) and is_same(service._facility_sources,static_source)
	var light: Dictionary = x.world.facts.facilities.light.duplicate(true)
	light.failed = false
	x.world.facts.facilities.light = light
	var replaced: Dictionary = _matches(x,[44,80])
	checks.same_identity_record_replacement_is_live = replaced.ok and replaced.actual==first and is_same(service._facility_sources,static_source)
	var available: Dictionary = _matches(x,[48,80])
	_position(x,"neighbor",x.space.facility_layout(x.world,"water").patient_cell)
	var occupied: Dictionary = _matches(x,[48,80])
	checks.water_permission_is_not_shared_across_commits = available.ok and occupied.ok and available.actual.water and not occupied.actual.water and is_same(service._facility_sources,static_source)
	_position(x,"neighbor",[45,80])
	var nearby: Dictionary = _matches(x,[44,80],"subject",true)
	_position(x,"neighbor",[60,80])
	var distant: Dictionary = _matches(x,[44,80],"subject",true)
	checks.nearby_people_are_lazy_and_current_each_scope = nearby.ok and distant.ok and nearby.actual.nearby_count==1 and distant.actual.nearby_count==0 and _counts(x)[2]==2
	var patch_id: String = service.spawn_dirt(x.world,"CL01","lifecycle_patch","lifecycle_patch:1",1,[44,82])
	var dirty: Dictionary = _matches(x,[44,82])
	if not patch_id.is_empty(): x.world.facts.environment.dirt.erase(patch_id)
	var cleaned: Dictionary = _matches(x,[44,82])
	checks.same_tick_dynamic_add_remove_is_current = not patch_id.is_empty() and dirty.ok and cleaned.ok and dirty.actual.dirt==1 and cleaned.actual.dirt==0
	static_source = service._facility_sources
	x.world.facts.facilities.light.cell = [62,82]
	x.world.touch()
	var moved: Dictionary = _matches(x,[44,80])
	checks.layout_owner_move_rebuilds_static_view = moved.ok and not is_same(service._facility_sources,static_source)
	static_source = service._facility_sources
	x.world.facts.facilities = x.world.facts.facilities.duplicate(true)
	var source_replaced: Dictionary = _matches(x,[44,80])
	checks.same_count_replaced_source_rebuilds = source_replaced.ok and not is_same(service._facility_sources,static_source)
	static_source = service._facility_sources
	var other: Dictionary = x.duplicate()
	other.world = WorldState.new(x.world.freeze())
	var changed_world: Dictionary = _matches(other,[44,80])
	checks.other_world_rebuilds_single_retained_view = changed_world.ok and not is_same(service._facility_sources,static_source) and service._facility_sources.world.get_ref()==other.world and is_same(service._facility_sources.records,other.world.facts.facilities)
	# Direct consumers must acquire their own prerequisites, without relying on
	# _observe_at having run first. They still avoid unrelated source families.
	var direct: Dictionary = _fixture()
	_facility(direct,"direct_light","FUR19",[42,80])
	direct.world.touch()
	direct.e.begin_query(direct.world)
	direct.e._coverage_edges(direct.world,1)
	checks.direct_edges_prepare_only_facilities = _counts(direct)==[1,0,0]
	direct.e._positive_facilities(direct.world,1,{"42:80":0})
	checks.direct_positive_reuses_facility_preparation = _counts(direct)==[1,0,0]
	direct.e._sample_records("dirt",1,{})
	direct.e._has_sample("machines",1,{})
	checks.direct_sample_consumers_prepare_dynamic_once = _counts(direct)==[1,1,0]
	direct.e._nearby_actors(direct.world,1,[44,80])
	direct.e._nearby_actors(direct.world,1,[44,80])
	checks.direct_nearby_consumers_prepare_people_once = _counts(direct)==[1,1,1]
	direct.e.end_query()
	return {"ok":not checks.values().has(false),"details":{"checks":checks,"final_source_counts":_counts(x),"water_available":available.actual.water,"water_occupied":occupied.actual.water}}
