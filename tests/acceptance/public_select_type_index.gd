extends "res://tests/acceptance/public_select_absent.gd"

# The existing world type index is shared by all services. Selection must
# consult its requested type buckets rather than enumerate facility records.
class CountingWorld extends WorldState:
	var definition_queries: Array = []
	var facility_enumerations: int = 0
	func facility_ids(definition_id: String) -> Array:
		definition_queries.append(definition_id)
		return super.facility_ids(definition_id)
	func ids(collection: String) -> Array:
		if collection=="facilities": facility_enumerations += 1
		return super.ids(collection)

func run_index_case(database: HospitalContent) -> Dictionary:
	_content = database
	var x: Dictionary = _areas()
	_visit(x,"absent_select",[38,74])
	x.world.touch()
	# Validate the identical source before construction so validation itself
	# cannot prewarm or increment the measured world's facility index.
	var checks: Dictionary = {"legal_input":x.world.validate(database).is_empty()}
	var world: CountingWorld = CountingWorld.new(x.world.freeze())
	var areas: CountingAreas = _probe()
	var rows: Array = []
	var original: Dictionary = world.freeze()
	var entries: Dictionary = {"keep":{"unchanged":true}}
	var result: Dictionary = areas.select(world,ACTOR,["FUR07"],["waiting"],"toilet",[],MAX_TICKS,entries)
	checks.cold_absent_uses_one_existing_index_build = result.is_empty() and world.definition_queries==["FUR07"] and world.facility_enumerations==1
	checks.absent_keeps_geometry_and_body_queries_cold = areas.ensure_calls==0 and areas.space.dynamic_begins==0 and areas.space.actor_index_calls==0
	checks.readonly_facts_and_output = world.freeze()==original and entries=={"keep":{"unchanged":true}}
	var buckets: Dictionary = world._facility_definitions
	var chairs: Array = world.facility_ids("FUR09")
	# Ordinary dispatch boundaries retain the same static membership. Both
	# unknown and duplicate definitions are valid conservative presence asks.
	for definitions: Array in [["FUR07"],["FUR07","unknown","FUR07"],[]]:
		world.facts.sim_tick += 1
		world.touch(false)
		world.definition_queries.clear()
		world.facility_enumerations = 0
		var before: Dictionary = world.freeze()
		result = areas.select(world,ACTOR,definitions,["waiting"],"seat",[],MAX_TICKS,entries)
		rows.append({"definitions":definitions,"ok":result.is_empty() and world.definition_queries==definitions and world.facility_enumerations==0 and areas.ensure_calls==0 and world.freeze()==before and is_same(buckets,world._facility_definitions) and is_same(chairs,world._facility_definitions.FUR09)})
	checks.warm_absent_only_reads_requested_buckets = rows.all(func(row: Dictionary)->bool:return row.ok)
	world.definition_queries.clear()
	result = areas.select(world,ACTOR,["FUR07","FUR09","unknown"],["waiting"],"seat")
	checks.match_stops_presence_lookup_and_keeps_real_selection = world.definition_queries==["FUR07","FUR09"] and result.get("area",{}).get("room_id","")=="west" and areas.space.dynamic_begins==1
	# Failure is a live filter, not cached definition absence. It must recover
	# on the next ordinary tick without rebuilding static membership.
	for failed: bool in [true,false]:
		for facility: Dictionary in world.facts.facilities.values(): facility.failed = failed
		world.touch(false)
		world.definition_queries.clear()
		result = areas.select(world,ACTOR,["FUR09"],["waiting"],"seat")
		checks["live_failure" if failed else "live_recovery"] = result.is_empty()==failed and world.definition_queries==["FUR09"] and is_same(chairs,world._facility_definitions.FUR09)
	checks.no_premature_ownership = world.facts.adaptations.is_empty() and world.facts.waiting_life.seats.is_empty()
	# Build commits replace facts on the same WorldState. Equal facility
	# counts must not retain old definition membership through that setter.
	x.world.facts.facilities.clear()
	_facility(x,"west_light","FUR19",[36,68],"west")
	_facility(x,"east_light","FUR19",[50,68],"east")
	x.world.touch()
	checks.equal_count_replacement_input_is_legal = x.world.validate(database).is_empty() and x.world.facts.facilities.size()==world.facts.facilities.size()
	world.facts = x.world.freeze()
	var previous_ensure: int = areas.ensure_calls
	result = areas.select(world,ACTOR,["FUR09"],["waiting"],"seat")
	checks.same_world_fact_replacement_discards_old_type = result.is_empty() and areas.ensure_calls==previous_ensure and world.facility_ids("FUR09").is_empty() and world.facility_ids("FUR19")==["east_light","west_light"]
	world.facts = original.duplicate(true)
	result = areas.select(world,ACTOR,["FUR09"],["waiting"],"seat")
	checks.same_world_fact_restore_recovers_type = result.get("area",{}).get("room_id","")=="west" and world.facility_ids("FUR19").is_empty() and world.facility_ids("FUR09")==["east_chair","west_chair"]
	checks.legal_final_and_closed_queries = world.validate(database).is_empty() and areas.space._route_queries.is_empty()
	_release(x)
	_owners.clear()
	return {"ok":not checks.values().has(false),"checks":checks,"observations":rows,"scope":"Static type lookup and real read-only region selection; actual arrival and occupancy are verified separately."}
