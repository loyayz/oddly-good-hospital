extends SceneTree

# Preparation process only. Every changed business fact comes from an original
# command or complete 0.1-second production step; no construction is fast-forwarded.
const Fixture = preload("res://tools/performance/fixture.gd")
const Inputs = preload("res://tools/performance/acceptance/fixtures/prepare_inputs.gd")
const ROOM_ID: String = "formal_stability_room"
const DOOR_ID: String = "formal_stability_door"
var _started: int = 0
var _maximum_us: int = 3600000000
var _maximum_steps: int = 40000
var _steps: int = 0
var _published_steps: int = 0
var _command_scope: String = "published_input"
var _command_next: int = 0
var _failure: String = ""
var _receipts: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source: String = ""
	var output_dir: String = ""
	var mode: String = ""
	var id: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="): source = argument.trim_prefix("--input=")
		if argument.begins_with("--output-dir="): output_dir = argument.trim_prefix("--output-dir=")
		if argument.begins_with("--mode="): mode = argument.trim_prefix("--mode=")
		if argument.begins_with("--id="): id = argument.trim_prefix("--id=")
		if argument.begins_with("--maximum-real-seconds="): _maximum_us = argument.trim_prefix("--maximum-real-seconds=").to_int()*1000000
		if argument.begins_with("--maximum-steps="): _maximum_steps = argument.trim_prefix("--maximum-steps=").to_int()
	if not mode in ["stability","maximum_upper"] or source.is_empty() or output_dir.is_empty() or _maximum_us<=0 or _maximum_steps<=0:
		push_error("Expected --mode=stability|maximum_upper --input --output-dir, positive watchdogs and --id=stability_a|stability_b for stability.")
		quit(2)
		return
	if mode=="stability" and not id in ["stability_a","stability_b"]:
		push_error("Stability input identity must be stability_a or stability_b.")
		quit(2)
		return
	if mode=="maximum_upper": id = "maximum_upper"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))!=OK or not FileAccess.file_exists(source):
		push_error("Source input or output directory unavailable.")
		quit(2)
		return
	var output: String = output_dir.path_join(id+".input.bin")
	if FileAccess.file_exists(output) or FileAccess.file_exists(output_dir.path_join(id+".manifest.json")):
		push_error("Preserve existing inputs; choose a new output directory.")
		quit(2)
		return
	_started = Time.get_ticks_usec()
	var content: HospitalContent = HospitalContent.new()
	if not content.error.is_empty():
		push_error(content.error)
		quit(2)
		return
	var fixture: RefCounted = Fixture.new(content,320 if id=="stability_b" else 160,"four_floors",source)
	var validation: String = fixture.world.validate(content)
	var expected_count: int = 320 if id=="stability_b" else 160
	var initial_population: Dictionary = Inputs.population_of(fixture.world)
	var original_mix: bool = initial_population.present==expected_count and initial_population.staff==expected_count/5 \
		and initial_population.patients==expected_count*3/4 and initial_population.visitors==expected_count/20 and initial_population.unowned.is_empty()
	if not fixture.errors.is_empty() or not validation.is_empty() or fixture.floors!=[1,2,3,4] or fixture.world.facts.rooms.size()!=64 or not original_mix:
		push_error("Expected original valid four-floor base: "+validation+JSON.stringify(fixture.errors))
		quit(2)
		return
	var simulation: HospitalSimulation = HospitalSimulation.new(fixture.world,content)
	var source_facts: Dictionary = simulation.world.freeze()
	_progress("source_ready",simulation,{"source_sha256":FileAccess.get_sha256(source)})
	var details: Dictionary
	if mode=="stability": details = await _stability(simulation,source_facts)
	else: details = await _maximum_upper(simulation,source_facts)
	validation = simulation.world.validate(content)
	var ok: bool = _failure.is_empty() and bool(details.get("ok",false)) and validation.is_empty() and not simulation.step_in_progress()
	var manifest: Dictionary = {"schema_version":1,"ok":ok,"preparation_only":true,"id":id,"mode":mode,
		"source":source,"source_sha256":FileAccess.get_sha256(source),"input_file":id+".input.bin",
		"hospital_id":simulation.world.hospital_id,"layout":"four_floors","floors":fixture.floors,
		"population":Inputs.population_of(simulation.world),"source_population":Inputs.population_of(WorldState.new(source_facts)),
		"tick":simulation.world.sim_tick,"actual_steps":_published_steps,"preflight_actual_steps":_steps-_published_steps,"preparation_us":Time.get_ticks_usec()-_started,
		"engine":Engine.get_version_info().string,"content_fingerprint":content.content_fingerprint,
		"validation":validation,"reason":_failure,"details":details,"original_command_receipts":_receipts}
	if ok:
		fixture.store_input(output)
		manifest.input_sha256 = FileAccess.get_sha256(output)
		ok = not str(manifest.input_sha256).is_empty()
		manifest.ok = ok
	var report: FileAccess = FileAccess.open(output_dir.path_join(id+(".manifest.json" if ok else ".blocked.json")),FileAccess.WRITE)
	if report==null:
		simulation.dispose()
		push_error("Cannot write operation preparation evidence.")
		quit(2)
		return
	report.store_string(JSON.stringify(manifest,"\t"))
	report.close()
	print("ACCEPTANCE_OPERATION_INPUT="+JSON.stringify(manifest))
	simulation.dispose()
	quit(0 if ok else 1)

func _stability(simulation: HospitalSimulation, source: Dictionary) -> Dictionary:
	var world: WorldState = simulation.world
	var expected: int = 160 if str(world.hospital_id).ends_with("000000000160") else 320 if str(world.hospital_id).ends_with("000000000320") else -1
	if expected<0 or world.present_actor_count()!=expected:
		_failure = "Stability source must retain the original 160/320 factory UUID and actual population."
		return {"ok":false}
	var draft: Dictionary = {"kind":"build_room","id":ROOM_ID,"room_type_id":"gp","floor_id":1,"origin":[15,81],"size":[8,8],
		"door":{"id":DOOR_ID,"definition_id":"DR04","edge":"south","offset":1}}
	if not _build(simulation,draft): return {"ok":false,"draft":draft}
	if not _original_entities_retained(source,world):
		_failure = "Original entities or source clinical/RNG facts changed during paused initial room construction."
		return {"ok":false}
	if world.facts.rooms.size()!=65 or int(HospitalLedger.balance(world))-int(HospitalLedger.balance(WorldState.new(source)))!=-2700:
		_failure = "Expected one actual 2700-coin room purchase and 65 rooms."
		return {"ok":false}
	# Preflight a separate clone. Published input stays before its first rotation.
	var probe: HospitalSimulation = HospitalSimulation.new(WorldState.new(world.freeze()),simulation.content)
	_command_scope = "rotation_preflight_clone"
	var observations: Array = []
	for index: int in 2:
		var rotation: Dictionary = await _rotate(probe,index)
		observations.append(rotation)
		if not bool(rotation.get("ok",false)):
			probe.dispose()
			return {"ok":false,"rotation_preflight":observations}
	probe.dispose()
	_command_scope = "published_input"
	return {"ok":true,"actual_rooms":65,"room_id":ROOM_ID,"door_id":DOOR_ID,"purchase_price":2700,
		"layout_a":{"origin":[15,81],"size":[8,8],"door_cell":[16,89]},
		"layout_b":{"origin":[15,81],"size":[8,8],"door_cell":[20,81]},"rotation_preflight":observations,
		"rotation_commands":[{"kind":"build_rotate","target_id":ROOM_ID,"turns":2}],
		"scope":"Original active hospital retained; genuine extra empty GP shell. Room/door rotations do not prove occupied clinical handoff."}

func _rotate(simulation: HospitalSimulation, index: int) -> Dictionary:
	var world: WorldState = simulation.world
	var before_cash: int = HospitalLedger.balance(world)
	var prepared: CommandResult = _command(simulation,"remodel_prepare",{"commands":[{"kind":"build_rotate","target_id":ROOM_ID,"turns":2}],"safe_transfer":false})
	if not prepared.accepted or prepared.changed_ids.is_empty(): return {"ok":false,"prepare":prepared.to_record()}
	var order_id: String = str(prepared.changed_ids[0])
	while not simulation.services.remodel._waiting(world,world.facts.remodels[order_id]).is_empty():
		if not await _advance(simulation,"rotation_real_evacuation"): return {"ok":false,"order_id":order_id}
	var plan: Dictionary = simulation.services.remodel.preview(world,order_id)
	if not plan.get("ok",false):
		_failure = "Original rotation preflight rejected: "+str(plan.get("reason",""))
		return {"ok":false,"order_id":order_id,"reason":_failure}
	var quote: Dictionary = {"price":plan.price,"refund":plan.refund,"layout":plan.layout}
	var applied: CommandResult = _command(simulation,"remodel_apply",{"order_id":order_id,"quote":quote})
	var door: Dictionary = _door(world,DOOR_ID)
	var entry: Dictionary = world.facts.ledger.entries.get(order_id+":remodel",{})
	var wanted: Array = [20,81] if index==0 else [16,89]
	var valid: bool = applied.accepted and door.get("cell",[])==wanted and world.facts.remodels[order_id].state=="applied" \
		and not entry.is_empty() and int(entry.amount)==0 and HospitalLedger.balance(world)==before_cash and world.validate(simulation.content).is_empty()
	if not valid: _failure = "Original rotation state, door, unique zero ledger or validation disagrees with the prequalified layout."
	_progress("rotation_preflight_complete",simulation,{"order_id":order_id,"door":door,"ok":valid})
	return {"ok":valid,"order_id":order_id,"quote":quote,"door":door,"ledger":entry,"apply":applied.to_record()}

func _maximum_upper(simulation: HospitalSimulation, source: Dictionary) -> Dictionary:
	var world: WorldState = simulation.world
	if world.facts.connectors.size()!=1 or not world.facts.connectors.has("benchmark_lift") or int(world.facts.connectors.benchmark_lift.last_floor)!=4:
		_failure = "Maximum-upper source must retain the original four-floor lift; no traffic is removed or extended into the target."
		return {"ok":false}
	for plot: Array in world.facts.floors.overrides["1"].plots:
		if int(world.facts.floors.completed_top_floor.get(HospitalSpace.plot_key(plot),0))!=4:
			_failure = "Every original source plot must be genuinely complete through 4F."
			return {"ok":false}
	if world.facts.floors.overrides["1"].plots.size()!=9:
		_failure = "Nine original purchased ground plots are required."
		return {"ok":false}
	var recruitment: RecruitmentService = simulation.services.recruitment
	var card: Dictionary = recruitment.standard_preview(world,{"role":"decorator"})
	if not card.get("ok",false):
		_failure = "Original standard decorator preview unavailable: "+str(card.get("reason",""))
		return {"ok":false}
	while not card.entry.get("ok",false):
		if not await _advance(simulation,"decorator_real_entry"): return {"ok":false}
		card = recruitment.standard_preview(world,{"role":"decorator"})
	var hired: CommandResult = _command(simulation,"recruitment_hire",{"filter":{"role":"decorator"},"standard_key":card.standard_key,"ordinal":card.ordinal,"quote_hash":card.quote_hash})
	if not hired.accepted: return {"ok":false,"hire":hired.to_record()}
	var worker_id: String = str(hired.changed_ids[0])
	if not _build(simulation,{"kind":"build_facility","id":"formal_upper_tool","definition_id":"SE02","floor_id":4,"cell":[15,81],"room_id":""}): return {"ok":false}
	# The first module uses the existing main lift's ground anchor plot. Further
	# modules use the actual completed same-floor module, all worked from 4F.
	var plots: Array = [[2,1],[0,0],[1,0],[2,0],[0,1],[1,1],[0,2],[1,2],[2,2]]
	var orders: Array = []
	for plot: Array in plots:
		var draft: Dictionary = {"floor_id":5,"plot":plot,"source":"lift" if orders.is_empty() else "same_floor","connection_id":"benchmark_lift"}
		var quote: Dictionary = simulation.services.floors.preview(world,draft)
		var previous_reason: String = ""
		while not quote.get("ok",false):
			if previous_reason!=str(quote.get("reason","")):
				previous_reason = str(quote.get("reason",""))
				_progress("floor_prerequisite_wait",simulation,{"plot":plot,"reason":previous_reason})
			if not await _advance(simulation,"floor_crew_ready"): return {"ok":false,"plot":plot,"reason":quote.get("reason","")}
			quote = simulation.services.floors.preview(world,draft)
		draft.quote = {"price":quote.price,"total_milli":quote.total_milli,"floor_id":quote.floor_id,"plot":quote.plot}
		var purchased: CommandResult = _command(simulation,"floor_purchase",draft)
		if not purchased.accepted or purchased.changed_ids.is_empty(): return {"ok":false,"purchase":purchased.to_record()}
		var order_id: String = str(purchased.changed_ids[0])
		orders.append(order_id)
		_progress("floor_original_order_created",simulation,{"plot":plot,"order_id":order_id,"quote":draft.quote})
		while world.facts.floors.orders[order_id].phase!="completed":
			if world.facts.floors.orders[order_id].phase=="cancelled":
				_failure = "Original floor order was cancelled."
				return {"ok":false,"order_id":order_id}
			if not await _advance(simulation,"floor_real_construction"): return {"ok":false,"order_id":order_id,"order":world.facts.floors.orders[order_id]}
		_progress("floor_original_order_completed",simulation,{"plot":plot,"order_id":order_id,"order":world.facts.floors.orders[order_id]})
	for connector: Dictionary in world.facts.connectors.values():
		if HospitalTransit.has_stop(connector,5):
			_failure = "Target 5F unexpectedly has a real connector; retain it and reject the maximum candidate."
			return {"ok":false}
	for room: Dictionary in world.facts.rooms.values():
		if int(room.floor_id)==5:
			_failure = "Target 5F must be genuinely empty before its measured room preview."
			return {"ok":false}
	for facility: Dictionary in world.facts.facilities.values():
		if int(facility.floor_id)==5:
			_failure = "Target 5F unexpectedly has an actual facility; preserve it and reject the maximum candidate."
			return {"ok":false}
	for actor: Dictionary in world.facts.actors.values():
		if actor.location.kind=="floor" and int(actor.location.floor_id)==5:
			_failure = "Target 5F unexpectedly contains an actual actor; do not relocate it to make the preview pass."
			return {"ok":false}
	var request: Dictionary = {"kind":"build_room","room_type_id":"gp","floor_id":5,"origin":[0,0],"size":[96,95],"door":{"definition_id":"DR01","edge":"south","offset":1}}
	var before_preview: Dictionary = world.freeze()
	var complete: Dictionary = simulation.services.building.preview(world,request)
	var completed_orders: Array = []
	var original_layout: bool = _original_layout_retained(source,world)
	for order_id: String in orders:
		var order: Dictionary = world.facts.floors.orders[order_id]
		var contributed: int = 0
		for amount: int in order.contributions.values(): contributed += amount
		original_layout = original_layout and order.phase=="completed" and int(order.remaining_milli)==0 and contributed==int(order.total_milli)
		completed_orders.append(order.duplicate(true))
	var valid: bool = complete.get("ok",false) and int(complete.get("price",-1))==364850 and before_preview==world.freeze() and original_layout
	if not valid: _failure = "Original maximum-upper complete preflight failed or mutated facts: "+str(complete.get("reason",""))
	return {"ok":valid,"target_floor":5,"target_size":[96,95],"target_cells":9120,"expected_price":364850,"construction_order_ids":orders,
		"hired_decorator_id":worker_id,"tool_id":"formal_upper_tool","maximum_preview":complete,"construction_orders":completed_orders,"original_load_and_traffic_retained":original_layout,
		"scope":"Nine modules built by original ordinary workers from 4F; original 1-4F lift retained. No 5F shaft, actor, room, completion rewrite or timestep change."}

func _build(simulation: HospitalSimulation, draft: Dictionary) -> bool:
	var quote: Dictionary = simulation.services.building.preview(simulation.world,draft)
	if not quote.get("ok",false):
		_failure = "Original build preview rejected: "+str(quote.get("reason",""))
		return false
	draft.quote = quote.quote
	var receipt: CommandResult = _command(simulation,str(draft.kind),draft)
	return receipt.accepted

func _command(simulation: HospitalSimulation, kind: String, payload: Dictionary) -> CommandResult:
	_command_next += 1
	var receipt: CommandResult = simulation.apply(GameCommand.from_record({"id":"formal-operation-preparation-%08d"%_command_next,
		"hospital_id":simulation.world.hospital_id,"expected_revision":simulation.world.revision,"kind":kind,"typed_payload":payload,"loading_session_id":"formal-operation-preparation"}))
	_receipts.append({"scope":_command_scope,"kind":kind,"tick":simulation.world.sim_tick,"result":receipt.to_record()})
	if not receipt.accepted: _failure = "Original command rejected: "+kind+" "+receipt.reason
	return receipt

func _advance(simulation: HospitalSimulation, stage: String) -> bool:
	if _steps>=_maximum_steps or Time.get_ticks_usec()-_started>=_maximum_us:
		_failure = "Actual preparation watchdog reached at "+stage+"; keep incomplete original work, never mark it finished."
		return false
	var result: TickResult = simulation.step_nonblocking()
	while result==null:
		if not simulation.preparing_error().is_empty() or Time.get_ticks_usec()-_started>=_maximum_us:
			_failure = "Original pending step incomplete: "+simulation.preparing_error()
			return false
		await process_frame
		result = simulation.step_nonblocking()
	_steps += 1
	if _command_scope=="published_input": _published_steps += 1
	if _steps%128==0: _progress(stage,simulation)
	await process_frame
	return true

func _original_entities_retained(source: Dictionary, world: WorldState) -> bool:
	for field: String in ["actors","staff","visits","tickets","sessions","attempts","preparations","ward_stays","moves","inventory","rng","connectors"]:
		if source[field]!=world.facts[field]: return false
	for field: String in ["rooms","facilities"]:
		for id: String in source[field]:
			if not world.facts[field].has(id) or source[field][id]!=world.facts[field][id]: return false
	return true

func _original_ids_present(source: Dictionary, world: WorldState) -> bool:
	for field: String in ["actors","staff","visits","rooms","facilities","connectors"]:
		for id: String in source[field]:
			if not world.facts[field].has(id): return false
	return true

func _original_layout_retained(source: Dictionary, world: WorldState) -> bool:
	if not _original_ids_present(source,world): return false
	for collection: String in ["rooms","facilities","connectors"]:
		for id: String in source[collection]:
			for field: String in ["definition_id","kind","floor_id","origin","size","cell","footprint","rotation","first_floor","last_floor"]:
				if source[collection][id].get(field)!=world.facts[collection][id].get(field): return false
	return true

func _door(world: WorldState, id: String) -> Dictionary:
	for layout: Dictionary in world.facts.floors.overrides.values():
		for door: Dictionary in layout.get("doors",[]):
			if door.id==id: return door.duplicate(true)
	return {}

func _progress(stage: String, simulation: HospitalSimulation, details: Dictionary = {}) -> void:
	print("ACCEPTANCE_OPERATION_PROGRESS="+JSON.stringify({"stage":stage,"elapsed_us":Time.get_ticks_usec()-_started,"actual_steps":_steps,"tick":simulation.world.sim_tick,"details":details}))
