extends "res://tests/acceptance/public_waiting_cost_field.gd"

func run_case(suite: RefCounted) -> Dictionary:
	_content = suite.content
	var x: Dictionary = _field_fixture(false)
	var owner: HospitalSpace = x.actual
	var cache: NavigationCache = owner._navigation
	var world: WorldState = x.world
	var before: Dictionary = world.freeze()
	owner.begin_dynamic_route_query(world)
	cache.prepare_structural_fields(owner,world,[ACTOR,ACTOR])
	var field: Dictionary = cache.ready_structural_field(owner,world,1,world.facts.actors[ACTOR],Vector2i(38,90))
	var direct: Dictionary = owner.travel_quote(world,ACTOR,1,[39,90])
	var prepared: bool = field.get("ready",false) and int(field.distances[FloorNavigation._id(Vector2i(39,90))])==1 and direct.ok and int(direct.walking_distance)==1 and int(owner.query_counts.get("native_field_requests",0))==1
	owner.end_route_query()
	var actual: Dictionary = owner.public_areas.select(world,ACTOR,[],["waiting",""],"waiting",[],HospitalTransit.MAX_TICK,{},true)
	var expected: Dictionary = x.original.public_areas.select(world,ACTOR,[],["waiting",""],"waiting",[],HospitalTransit.MAX_TICK,{},true)
	var readonly: bool = before==world.freeze()
	world.facts.floors.overrides["1"].blocked.append([39,90]); world.touch()
	before = world.freeze()
	owner.begin_dynamic_route_query(world)
	var stale: Dictionary = cache.ready_structural_field(owner,world,1,world.facts.actors[ACTOR],Vector2i(38,90))
	cache.prepare_structural_fields(owner,world,[ACTOR])
	var blocked: Dictionary = owner.travel_quote(world,ACTOR,1,[39,90])
	owner.end_route_query()
	var invalidated: bool = stale.is_empty() and not blocked.ok and before==world.freeze()
	cache._trim(1)
	var evicted: bool = cache._entries.is_empty() and cache._query_charged==0 and cache._charged==0
	world.facts.floors.overrides["1"].blocked.erase([39,90]); world.touch()
	before = world.freeze()
	owner.begin_dynamic_route_query(world)
	cache.prepare_structural_fields(owner,world,[ACTOR])
	var restored: Dictionary = owner.travel_quote(world,ACTOR,1,[39,90])
	owner.end_route_query()
	var rebuilt: bool = restored.ok and int(restored.walking_distance)==1 and before==world.freeze()
	var details: Dictionary = {"deduplicated_field_and_literal_unit_distance":prepared,"selection_equal":actual==expected,"selection":actual,"preparation_and_selection_readonly":readonly,"geometry_edit_invalidates_field":invalidated,"budget_evicts_all_query_payload":evicted,"rebuild_after_edit_and_eviction":rebuilt,"actual_native_field_hits":owner.query_counts.get("native_field_hits",0)}
	var ok: bool = prepared and actual==expected and readonly and invalidated and evicted and rebuilt and int(details.actual_native_field_hits)>0
	_field_dispose(x)
	return {"ok":ok,"details":details}
