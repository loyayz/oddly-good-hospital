extends SceneTree

const Fixture = preload("res://tools/performance/fixture.gd")
const CASES: Dictionary = {
	"160four":{"actors":160,"layout":"four_floors","floors":[1,2,3,4]},
	"320four":{"actors":320,"layout":"four_floors","floors":[1,2,3,4]},
	"640wide":{"actors":640,"layout":"wide","floors":[1]},
	"wide160":{"actors":160,"layout":"wide","floors":[1]},
	"tall640":{"actors":640,"layout":"tall","floors":[1,10,1000,10000]}
}
var _maximum_steps: int = 4000
var _maximum_us: int = 1800000000
var _started: int
var _steps: int = 0
var _source_input: String = ""
var _case_id: String = ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var selected: String = "all"
	var output_dir: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="): selected = argument.trim_prefix("--case=")
		if argument.begins_with("--output-dir="): output_dir = argument.trim_prefix("--output-dir=")
		if argument.begins_with("--source-input="): _source_input = argument.trim_prefix("--source-input=")
		if argument.begins_with("--maximum-steps="): _maximum_steps = argument.trim_prefix("--maximum-steps=").to_int()
		if argument.begins_with("--maximum-real-seconds="): _maximum_us = argument.trim_prefix("--maximum-real-seconds=").to_int()*1000000
	if output_dir.is_empty() or (selected!="all" and not CASES.has(selected)) or _maximum_steps<=0 or _maximum_us<=0:
		push_error("Expected --output-dir, --case=all|160four|320four|640wide|wide160|tall640 and positive watchdogs.")
		quit(2)
		return
	if not _source_input.is_empty() and selected=="all":
		push_error("--source-input requires one selected --case; never reuse one world's load as a different case.")
		quit(2)
		return
	if not _source_input.is_empty() and not FileAccess.file_exists(_source_input):
		push_error("Reusable source input does not exist: "+_source_input)
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))!=OK:
		quit(2)
		return
	var content: HospitalContent = HospitalContent.new()
	if not content.error.is_empty():
		push_error(content.error)
		quit(2)
		return
	var results: Array = []
	var ok: bool = true
	for id: String in CASES:
		if selected!="all" and selected!=id: continue
		var result: Dictionary = await _prepare(id,CASES[id],output_dir,content)
		results.append(result)
		ok = ok and result.ok
		print("ACCEPTANCE_INPUT="+JSON.stringify(result))
	var report: FileAccess = FileAccess.open(output_dir.path_join("base-preparation-%s.json"%selected),FileAccess.WRITE)
	if report==null:
		quit(2)
		return
	report.store_string(JSON.stringify({"schema_version":1,"preparation_only":true,"engine":Engine.get_version_info().string,
		"content_fingerprint":content.content_fingerprint,"ok":ok,"results":results},"\t"))
	report.close()
	quit(0 if ok else 1)

func _prepare(id: String, definition: Dictionary, output_dir: String, content: HospitalContent) -> Dictionary:
	var output: String = output_dir.path_join(id+".input.bin")
	if FileAccess.file_exists(output): return {"ok":false,"id":id,"reason":"Input already exists; preserve it or choose a new output directory."}
	_started = Time.get_ticks_usec()
	_steps = 0
	_case_id = id
	_progress("fixture_load_start",{"source_input":_source_input})
	var fixture: RefCounted = Fixture.new(content,int(definition.actors),str(definition.layout),_source_input)
	if not fixture.errors.is_empty(): return {"ok":false,"id":id,"reason":"Original legal placement failed.","errors":fixture.errors}
	var world: WorldState = fixture.world
	if fixture.floors!=definition.floors or world.present_actor_count()!=int(definition.actors):
		return {"ok":false,"id":id,"reason":"Source floors/real population do not match this case."}
	var original_layout: Dictionary = _layout_counts(world)
	if original_layout.rooms!=64 or original_layout.props!=1200 or original_layout.service_objects!=128:
		return {"ok":false,"id":id,"reason":"Actual source layout is not the full original Fixture load.","actual_layout":original_layout}
	var original_room_ids: Array = world.facts.rooms.keys()
	var original_facility_definitions: Dictionary = {}
	for facility: Dictionary in world.facts.facilities.values(): original_facility_definitions[facility.id] = facility.definition_id
	_progress("fixture_load_ready",{"tick":world.sim_tick,"actual_layout":original_layout,"present":world.present_actor_count()})
	# Original Fixture visitors have no stay or owner. They are construction
	# placeholders, never part of a formal active sample. Original admission below
	# replaces them with the same number of real companions, retaining 75/20/5 mix.
	for actor_id: String in fixture.visitor_ids:
		if not _unowned_placeholder(world,actor_id): return {"ok":false,"id":id,"reason":"Source visitor is already owned; never delete an actual relative or moving actor.","actor_id":actor_id}
		world.facts.actors.erase(actor_id)
	fixture.visitor_ids.clear()
	_progress("simulation_create_start")
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	_progress("simulation_create_ready",{"tick":world.sim_tick})
	if not world.facts.visitors.stays.is_empty():
		simulation.dispose()
		return {"ok":false,"id":id,"reason":"Reusable base source already has actual visitors; never replace an admitted stay."}
	for visit: Dictionary in world.facts.visits.values():
		if not str(visit.get("relative_actor_id","")).is_empty():
			simulation.dispose()
			return {"ok":false,"id":id,"reason":"Reusable base source already owns a relative identity; preserve it in a separate named input.","visit_id":visit.id}
	if not _source_input.is_empty() and (world.facts.arrivals.plan.is_empty() or int(world.facts.arrivals.plan.day_index)!=world.sim_tick/WorldState.TICKS_PER_DAY+1):
		simulation.dispose()
		return {"ok":false,"id":id,"reason":"Requested reusable source has no genuine frozen plan for its current day; prepare one through the original boundary first."}
	_progress("source_plan_checked",{"day_index":world.facts.arrivals.plan.get("day_index",0),"opportunity_count":world.facts.arrivals.plan.get("opportunity_count",-1),"tick":world.sim_tick})
	var closed: CommandResult = _intake(simulation,false,"prepare-close-"+id)
	if not closed.accepted:
		simulation.dispose()
		return {"ok":false,"id":id,"reason":"Original intake-close command rejected.","command":closed.to_record()}
	_progress("intake_closed")
	var wanted_visitors: int = int(definition.actors)/20
	var chair_result: Dictionary = _add_public_seats(simulation,wanted_visitors)
	if not chair_result.ok:
		simulation.dispose()
		return chair_result.merged({"id":id})
	var visitors: HospitalVisitors = simulation.clinic.visitors
	# A fresh initial boundary can specify known intention facts before any real
	# scan. A reused real step retains every original intention, RNG and request;
	# only its existing requests may be consumed by actual admission.
	var intention_origin: String = "preserved_original_source_requests"
	if _source_input.is_empty():
		intention_origin = "known_intentions_before_first_original_step"
		var visit_ids: Array = world.active_visit_ids()
		for visit_id: String in visit_ids: world.facts.visits[visit_id].companion_intent = false
		for index: int in wanted_visitors:
			var visit: Dictionary = world.facts.visits[visit_ids[index]]
			visit.companion_intent = true
			visitors._request(world,visit,"companion","")
	var pending_before: int = world.facts.visitors.requests.size()
	var eligible: Array = _companion_request_ids(world)
	if eligible.size()<wanted_visitors:
		simulation.dispose()
		return {"ok":false,"id":id,"reason":"Actual source has too few existing legal companion requests; preserve it and prepare a fresh initial Fixture boundary without --source-input.","available":eligible.size(),"required":wanted_visitors,"pending_requests":pending_before}
	_progress("companion_requests_ready",{"origin":intention_origin,"eligible_requests":eligible.size(),"pending_requests":pending_before})
	while world.facts.visitors.stays.size()<wanted_visitors:
		eligible = _companion_request_ids(world)
		if eligible.is_empty():
			simulation.dispose()
			return {"ok":false,"id":id,"reason":"No original eligible companion request remains before the required actual admissions.","steps":_steps}
		var request_id: String = str(eligible[0])
		var request: Dictionary = world.facts.visitors.requests[request_id]
		var visit: Dictionary = world.facts.visits[request.visit_id]
		_progress("companion_admission_attempt",{"number":world.facts.visitors.stays.size()+1,"required":wanted_visitors,"visit_id":visit.id,"tick":world.sim_tick})
		# Same original owner and request order as HospitalVisitors.arrivals. It
		# checks the real entrance, one companion, public seat and full route.
		if visitors._admit(world,visit,request):
			world.facts.visitors.requests.erase(request_id)
			_progress("companion_admission_ready",{"number":world.facts.visitors.stays.size(),"actor_id":visit.relative_actor_id,"tick":world.sim_tick})
		else:
			var advanced: Dictionary = await _advance(simulation)
			if not advanced.ok:
				simulation.dispose()
				return advanced.merged({"id":id,"visit_id":visit.id,"seats":chair_result.seat_ids})
	for stay: Dictionary in world.facts.visitors.stays.values(): fixture.visitor_ids.append(str(stay.actor_id))
	var opened: CommandResult = _intake(simulation,true,"prepare-open-"+id)
	var validation: String = world.validate(content)
	var profiles_valid: bool = _companion_profiles_valid(world,fixture.visitor_ids)
	var population: Dictionary = population_of(world)
	var final_layout: Dictionary = _layout_counts(world)
	var layout_preserved: bool = final_layout.rooms==64 and final_layout.props==1200 and final_layout.service_objects==128+chair_result.seat_ids.size()
	for room_id: String in original_room_ids: layout_preserved = layout_preserved and world.facts.rooms.has(room_id)
	for facility_id: String in original_facility_definitions:
		layout_preserved = layout_preserved and world.facts.facilities.has(facility_id) and world.facts.facilities[facility_id].definition_id==original_facility_definitions[facility_id]
	var matches: bool = population.present==int(definition.actors) and population.staff==int(definition.actors)/5 \
		and population.patients==int(definition.actors)*3/4 and population.visitors==wanted_visitors and population.unowned.is_empty()
	if not opened.accepted or not validation.is_empty() or not matches or not profiles_valid or not layout_preserved:
		simulation.dispose()
		return {"ok":false,"id":id,"reason":"Exact legal workload failed; do not remove, replace or hold actors to make it pass.",
			"population":population,"validation":validation,"companion_profiles_valid":profiles_valid,"actual_layout":final_layout,"layout_preserved":layout_preserved,"command":opened.to_record(),"steps":_steps}
	_progress("write_input_start",{"tick":world.sim_tick,"population":population,"actual_layout":final_layout})
	fixture.store_input(output)
	var result: Dictionary = {"ok":true,"id":id,"input_file":id+".input.bin","hospital_id":world.hospital_id,
		"actors":int(definition.actors),"layout":definition.layout,"floors":fixture.floors,"population":population,
		"boundary":"original_companion_admissions_and_complete_steps","actual_steps":_steps,"source_tick":world.sim_tick,
		"added_public_seat_ids":chair_result.seat_ids,"original_prop_count":1200,"original_rooms":64,"original_service_objects":128,
		"actual_layout_before":original_layout,"actual_layout_after":final_layout,"original_object_ids_and_definitions_preserved":layout_preserved,
		"visitor_profile":"HospitalVisitors companion; original admission owner, actual entrance and public waiting route",
		"companion_intention_origin":intention_origin,"pending_visitor_requests_before":pending_before,"pending_visitor_requests_after":world.facts.visitors.requests.size(),
		"companion_profiles_valid":profiles_valid,"source_input":_source_input,"source_input_sha256":FileAccess.get_sha256(_source_input) if not _source_input.is_empty() else "",
		"validation":validation,"preparation_us":Time.get_ticks_usec()-_started,"input_sha256":FileAccess.get_sha256(output),
		"content_fingerprint":content.content_fingerprint,"engine":Engine.get_version_info().string}
	var metadata: FileAccess = FileAccess.open(output_dir.path_join(id+".manifest.json"),FileAccess.WRITE)
	if metadata==null:
		simulation.dispose()
		return {"ok":false,"id":id,"reason":"Input written but metadata cannot be created; preparation incomplete."}
	metadata.store_string(JSON.stringify(result,"\t"))
	metadata.close()
	simulation.dispose()
	return result

func _companion_request_ids(world: WorldState) -> Array:
	var ids: Array = []
	for request: Dictionary in world.facts.visitors.requests.values():
		var visit: Dictionary = world.facts.visits[request.visit_id]
		if request.purpose=="companion" and bool(visit.get("companion_intent",false)) and not visit.phase in ["leaving","departed","ward_referral"] and str(visit.get("relative_actor_id","")).is_empty(): ids.append(request.id)
	ids.sort_custom(func(a: String,b: String) -> bool:
		var first: Dictionary = world.facts.visitors.requests[a]
		var second: Dictionary = world.facts.visitors.requests[b]
		return int(first.request_tick)<int(second.request_tick) if int(first.request_tick)!=int(second.request_tick) else a<b)
	return ids

func _unowned_placeholder(world: WorldState, actor_id: String) -> bool:
	if not actor_id.begins_with("bench_visitor_") or world.facts.staff.has(actor_id) or world.facts.moves.has(actor_id): return false
	for visit: Dictionary in world.facts.visits.values():
		if visit.actor_id==actor_id or visit.get("relative_actor_id","")==actor_id: return false
	for stay: Dictionary in world.facts.get("visitors",{}).get("stays",{}).values():
		if stay.actor_id==actor_id: return false
	return true

func _companion_profiles_valid(world: WorldState, visitor_ids: Array) -> bool:
	var seen: Dictionary = {}
	for stay: Dictionary in world.facts.visitors.stays.values():
		if not stay.actor_id in visitor_ids: continue
		var visit: Dictionary = world.facts.visits[stay.visit_id]
		var actor: Dictionary = world.facts.actors[stay.actor_id]
		if stay.purpose!="companion" or visit.get("relative_actor_id","")!=stay.actor_id or actor.get("relative_of","")!=visit.actor_id or seen.has(stay.visit_id): return false
		if actor.species_id!=world.facts.actors[visit.actor_id].species_id: return false
		seen[stay.visit_id] = true
	return seen.size()==visitor_ids.size()

func _add_public_seats(simulation: HospitalSimulation, wanted: int) -> Dictionary:
	var world: WorldState = simulation.world
	var builder: BuildService = simulation.services.building
	var seats: Array = []
	var waiting_cells: Array = []
	var definition: Dictionary = simulation.content.facility_definition("FUR09")
	if definition.is_empty() or definition.get("footprint",[])!=[1,1] or not definition.has("price"):
		return {"ok":false,"reason":"Original FUR09 public-seat definition is not the expected complete 1x1 definition."}
	for research_id: String in definition.get("requires_research",[]):
		if not research_id in world.facts.research: return {"ok":false,"reason":"Original public seat research is unavailable.","research_id":research_id}
	var checked: int = 0
	var rejected: Array = []
	_progress("public_seat_search_start",{"required":wanted})
	# This is an initial built-layout boundary, like original Fixture, not a
	# construction operation under measurement. Only the bottom public corridor
	# is considered: at most 39 candidates, with the real entry kept clear.
	for x: int in range(4,92,2):
		if seats.size()==wanted: return {"ok":true,"seat_ids":seats,"checked_candidates":checked}
		if x>=44 and x<=52: continue
		if Time.get_ticks_usec()-_started>=_maximum_us:
			return {"ok":false,"reason":"Public-seat preparation watchdog reached; retain full workload.","seat_ids":seats,"required":wanted,"checked_candidates":checked}
		checked += 1
		var seat_id: String = "acceptance_public_seat_%04d"%seats.size()
		if world.facts.facilities.has(seat_id): return {"ok":false,"reason":"Initial public-seat identity already exists.","seat_id":seat_id}
		var probe_facts: Dictionary = world.facts.duplicate()
		probe_facts.facilities = world.facts.facilities.duplicate()
		var probe: WorldState = WorldState.new(probe_facts)
		var item: Dictionary = {"id":seat_id,"definition_id":"FUR09","anchor":[x,90],"size":definition.footprint.duplicate(),"room_id":null}
		HospitalFactory._add_facility(probe,item,simulation.content)
		var facility: Dictionary = probe.facts.facilities[seat_id]
		# Original narrow placement authority checks owned ground, all actual
		# bodies, facilities, connectors, adaptation regions, dirt and doors.
		var positioned: Dictionary = builder._facility_position(probe,facility,[seat_id])
		var waiting: Array = facility.patient_cell
		if positioned.ok:
			positioned = BuildGeometry.occupied_error(probe,simulation.space,1,[Rect2(float(waiting[0]),float(waiting[1]),1,1)],[seat_id])
		if positioned.ok:
			for room: Dictionary in world.facts.rooms.values():
				if int(room.floor_id)==1 and BuildGeometry.contains(room,waiting): positioned = {"ok":false,"reason":"Initial public waiting point intrudes into a room."}
		if not positioned.ok or waiting in waiting_cells:
			rejected.append({"cell":[x,90],"reason":positioned.get("reason","Duplicate public waiting point.")})
			continue
		HospitalFactory._add_facility(world,item,simulation.content)
		world.touch()
		seats.append(seat_id)
		waiting_cells.append(waiting.duplicate())
		_progress("initial_public_seat_ready",{"seat_id":seat_id,"number":seats.size(),"cell":[x,90],"checked_candidates":checked})
	return {"ok":false,"reason":"Bounded original public corridor cannot supply enough lawful companion seats; no props/rooms were deleted.","available":seats.size(),"required":wanted,"seat_ids":seats,"checked_candidates":checked,"rejected":rejected}

func _advance(simulation: HospitalSimulation) -> Dictionary:
	if _steps>=_maximum_steps or Time.get_ticks_usec()-_started>=_maximum_us:
		return {"ok":false,"reason":"Preparation watchdog reached before actual entry/route became available.","steps":_steps,"population":population_of(simulation.world)}
	var result: TickResult = simulation.step_nonblocking()
	while result==null:
		if not simulation.preparing_error().is_empty(): return {"ok":false,"reason":simulation.preparing_error(),"steps":_steps}
		if Time.get_ticks_usec()-_started>=_maximum_us: return {"ok":false,"reason":"Preparation boundary/solver watchdog reached.","steps":_steps}
		await process_frame
		result = simulation.step_nonblocking()
	_steps += 1
	if _steps%32==0: _progress("actual_steps",{"tick":simulation.world.sim_tick})
	await process_frame
	return {"ok":true}

func _progress(stage: String, details: Dictionary = {}) -> void:
	print("ACCEPTANCE_PREPARATION_PROGRESS="+JSON.stringify({"id":_case_id,"stage":stage,"elapsed_us":Time.get_ticks_usec()-_started,"actual_steps":_steps,"details":details}))

static func _layout_counts(world: WorldState) -> Dictionary:
	var props: int = 0
	for facility: Dictionary in world.facts.facilities.values():
		if facility.definition_id=="FUR18": props += 1
	return {"rooms":world.facts.rooms.size(),"props":props,"service_objects":world.facts.facilities.size()-props,"facilities":world.facts.facilities.size()}

func _intake(simulation: HospitalSimulation, opened: bool, id: String) -> CommandResult:
	return simulation.apply(GameCommand.from_record({"id":id,"hospital_id":simulation.world.hospital_id,
		"expected_revision":simulation.world.revision,"kind":"arrivals_intake","typed_payload":{"open":opened},"loading_session_id":"acceptance-input-preparation"}))

static func population_of(world: WorldState) -> Dictionary:
	var result: Dictionary = {"present":world.present_actor_count(),"staff":0,"patients":0,"visitors":0,"unowned":[]}
	var owned: Dictionary = {}
	for id: String in world.facts.staff:
		if world.facts.actors[id].location.kind!="outside":
			result.staff += 1
			owned[id] = true
	for id: String in world.active_visit_ids():
		var actor_id: String = str(world.facts.visits[id].actor_id)
		if world.facts.actors[actor_id].location.kind!="outside":
			result.patients += 1
			owned[actor_id] = true
	for stay: Dictionary in world.facts.get("visitors",{}).get("stays",{}).values():
		if world.facts.actors[stay.actor_id].location.kind!="outside":
			result.visitors += 1
			owned[stay.actor_id] = true
	for id: String in world.facts.actors:
		if world.facts.actors[id].location.kind!="outside" and not owned.has(id): result.unowned.append(id)
	return result
