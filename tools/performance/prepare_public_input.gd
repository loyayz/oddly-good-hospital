extends SceneTree

const Fixture = preload("res://tools/performance/fixture.gd")
const Operations = preload("res://tools/performance/representative_operations.gd")
var errors: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var options: Dictionary = {"source":"","output":"","contention":"false"}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument: options[argument.trim_prefix("--").get_slice("=",0)] = argument.substr(argument.find("=")+1)
	if not FileAccess.file_exists(options.source) or str(options.output).is_empty() or FileAccess.file_exists(options.output):
		push_error("Expected existing source and a new output path")
		quit(2)
		return
	var started: int = Time.get_ticks_usec()
	var content: HospitalContent = HospitalContent.new()
	var file: FileAccess = FileAccess.open(options.source,FileAccess.READ)
	var input: Dictionary = file.get_var()
	file.close()
	var fixture: RefCounted = Fixture.new(content,160,"four_floors",options.source)
	var world: WorldState = fixture.world
	var original: Dictionary = world.freeze()
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	var metadata: Dictionary = {"constructor":"new public intent and permanent bed facts at a declared initial boundary; no runtime save migration",
		"source":options.source,"source_sha256":FileAccess.get_sha256(options.source),"contention_scene":options.contention=="true",
		"visitor_intents":[],"need_inputs":[],"time_shift_ticks":0,"errors":errors}
	# These original companions stand at legal waiting points. Add only their
	# new intent; actual target selection, sitting and movement happen in steps.
	for stay: Dictionary in world.facts.visitors.stays.values():
		var actor: Dictionary = world.facts.actors[stay.actor_id]
		var closest: String = ""
		var distance: float = INF
		for id: String in world.ids("facilities"):
			var facility: Dictionary = world.facts.facilities[id]
			if not id.begins_with("acceptance_public_seat_") or int(facility.floor_id)!=int(actor.location.floor_id): continue
			var cell: Array = facility.patient_cell
			var value: float = absf(float(cell[0])-float(actor.location.cell[0]))+absf(float(cell[1])-float(actor.location.cell[1]))
			if value<distance: closest = id; distance = value
		var area: Dictionary = simulation.space.public_areas.for_facility(world,closest)
		if area.is_empty(): errors.append("No real public waiting region for companion "+stay.id)
		stay.public_use = {"id":stay.id,"actor_id":stay.actor_id,"public_purpose":"seat","mode":"auto","area":area,"arrived_tick":-1,"phase":"area_travel","facility_id":"","started_tick":world.sim_tick}
		metadata.visitor_intents.append({"stay_id":stay.id,"area":area,"actual_initial_location":actor.location.duplicate(true)})
	if options.contention=="true":
		# A named lawful critical input: preserve relative times of all existing
		# work, then declare selected idle visits at the first 180-second need.
		# No service, route, arrival, queue, work or completion is supplied.
		_shift_times(world.facts,1800)
		world.touch(false)
		metadata.time_shift_ticks = 1800
		metadata.absolute_time_rule = "tick and *_tick nonnegative integer-valued absolute timestamps +1800, except already-ready focus_ready_tick=0; durations and RNG unchanged"
		metadata.operations = Operations.new().apply(simulation,{"cleaning_mode":"local16","pending_renovation":true,"need_kinds":[]})
		errors.append_array(metadata.operations.errors)
		_seed_needs(simulation,metadata)
		_seed_manual(simulation,metadata)
	var original_world: WorldState = WorldState.new(original)
	metadata.capacity_basis_differences = []
	for shift: int in 3:
		var before: Dictionary = simulation.services.arrivals._reference_basis(original_world,shift)
		var after: Dictionary = simulation.services.arrivals._reference_basis(world,shift)
		for field: String in before:
			if before[field]!=after.get(field): metadata.capacity_basis_differences.append("shift_%d.%s"%[shift,field])
	if not metadata.capacity_basis_differences.is_empty(): errors.append("Original frozen day plan's reference basis changed")
	metadata.personal_beds = world.facts.staff_life.personal_beds.duplicate(true)
	metadata.positions_unchanged = original.actors==world.facts.actors
	metadata.rng_unchanged = original.rng==world.facts.rng
	metadata.population = world.present_actor_count()
	metadata.validation = world.validate(content)
	if metadata.population!=160 or (not metadata.positions_unchanged and options.contention!="true") or not metadata.rng_unchanged or not metadata.validation.is_empty(): errors.append("Initial facts failed preservation or validation")
	metadata.preparation_elapsed_us = Time.get_ticks_usec()-started
	if errors.is_empty():
		input.facts = world.freeze()
		if not input.has("representative_clinical"): input.representative_clinical = {}
		if not input.representative_clinical.has("metadata"): input.representative_clinical.metadata = {}
		if metadata.has("operations"): input.representative_clinical.metadata.operations = metadata.operations
		input.representative_clinical.metadata.public_input = metadata
		file = FileAccess.open(options.output,FileAccess.WRITE)
		file.store_var(input)
		file.close()
		metadata.output_sha256 = FileAccess.get_sha256(options.output)
	file = FileAccess.open(str(options.output)+".preparation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata,"\t"))
	file.close()
	print("PUBLIC_INPUT="+JSON.stringify(metadata))
	simulation.dispose()
	quit(0 if errors.is_empty() else 1)

func _shift_times(value: Variant, delta: int) -> void:
	if value is Dictionary:
		for key: Variant in value:
			var name: String = str(key)
			if name=="focus_ready_tick" and value[key]==0: continue
			if (name=="tick" or name.ends_with("_tick")) and (value[key] is int or value[key] is float) and int(value[key])>=0: value[key] += delta
			else: _shift_times(value[key],delta)
	elif value is Array:
		for entry: Variant in value: _shift_times(entry,delta)

func _idle_visit(world: WorldState, visit: Dictionary) -> bool:
	var actor: Dictionary = world.facts.actors[visit.actor_id]
	var ticket: Dictionary = world.facts.tickets.get(visit.ticket_id,{})
	if not str(visit.phase).begins_with("wait_") or actor.location.kind!="floor" or world.facts.moves.has(actor.id) or ticket.get("service_assigned",false) or not ticket.get("pause_reasons",{}).is_empty(): return false
	for stay: Dictionary in world.facts.visitors.stays.values():
		if stay.visit_id==visit.id: return false
	return not world.facts.waiting_life.needs.has(visit.id)

func _seed_needs(simulation: HospitalSimulation, metadata: Dictionary) -> void:
	var world: WorldState = simulation.world
	var areas: Array = []
	for floor_id: int in [1,2,3,4]:
		var choices: Array = []
		for visit_id: String in world.active_visit_ids():
			var visit: Dictionary = world.facts.visits[visit_id]
			if not _idle_visit(world,visit) or int(world.facts.actors[visit.actor_id].location.floor_id)!=floor_id: continue
			var best: Dictionary = {}
			for facility_id: String in world.facility_ids("FUR07"):
				if int(world.facts.facilities[facility_id].floor_id)!=floor_id: continue
				var quote: Dictionary = simulation.space.facility_quote(world,facility_id,visit.actor_id)
				quote.facility_id = facility_id
				quote.travel_ticks = simulation.space.facility_travel_lower_bound_ticks(world,facility_id,visit.actor_id)
				if quote.ok and (best.is_empty() or int(quote.travel_ticks)<int(best.travel_ticks)): best = quote
			if not best.is_empty(): choices.append({"visit_id":visit_id,"quote":best})
		choices.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a.quote.travel_ticks<b.quote.travel_ticks if a.quote.travel_ticks!=b.quote.travel_ticks else a.visit_id<b.visit_id)
		if choices.size()<4: errors.append("Fewer than four original idle visits with real reachable toilets on floor "+str(floor_id)); continue
		for index: int in 4:
			var choice: Dictionary = choices[index]
			var visit: Dictionary = world.facts.visits[choice.visit_id]
			var actor: Dictionary = world.facts.actors[visit.actor_id]
			var original_position: Dictionary = actor.location.duplicate(true)
			var placed: Dictionary = _place_approach(simulation,visit.actor_id,choice.quote.facility_id)
			if placed.is_empty(): errors.append("Cannot declare a legal unowned approach position for "+visit.id); continue
			var before: Dictionary = {"arrival_tick":visit.get("arrival_tick",visit.arrived_tick),"arrived_tick":visit.arrived_tick,"clock":world.facts.waiting_life.clocks[visit.id].duplicate(true)}
			visit.arrival_tick = world.sim_tick-1800
			visit.arrived_tick = world.sim_tick-1800
			world.facts.waiting_life.clocks[visit.id].next_need_tick = world.sim_tick
			world.facts.waiting_life.clocks[visit.id].next_purpose = "toilet"
			var area: Dictionary = simulation.space.public_areas.for_facility(world,choice.quote.facility_id)
			if not area in areas: areas.append(area)
			metadata.need_inputs.append({"visit_id":visit.id,"before":before,"arrival_tick":visit.arrival_tick,"arrived_tick":visit.arrived_tick,"clock":world.facts.waiting_life.clocks[visit.id].duplicate(true),"real_quote":placed,"area":area,"original_position":original_position,"declared_initial_position":actor.location.duplicate(true),"position_scope":"new critical input before the measured operation; idle actor with no movement or medical assignment; real approach, arrival, queue, use and exit must run"})
	metadata.need_areas = areas
	if areas.size()<2: errors.append("Contention input requires at least two distinct same-purpose regions")

func _seed_manual(simulation: HospitalSimulation, metadata: Dictionary) -> void:
	var world: WorldState = simulation.world
	var needs: Array = metadata.need_inputs.map(func(row: Dictionary)->String: return row.visit_id)
	var best: Dictionary = {}
	for visit_id: String in world.active_visit_ids():
		var visit: Dictionary = world.facts.visits[visit_id]
		if visit_id in needs or not _idle_visit(world,visit): continue
		for facility_id: String in world.ids("facilities"):
			if not simulation.services.waiting._public_seat(world,world.facts.facilities[facility_id]): continue
			var facts: Dictionary = world.facts.duplicate()
			facts.actors = world.facts.actors.duplicate()
			var cell: Array = world.facts.facilities[facility_id].patient_cell
			# Select a future busy manual target: the original companion is
			# standing at this chair's point and may actually sit on step one.
			# This projection never writes that companion or starts a use.
			for stay: Dictionary in world.facts.visitors.stays.values():
				if not simulation.space.at(world,stay.actor_id,int(world.facts.facilities[facility_id].floor_id),cell): continue
				facts.actors[stay.actor_id] = world.facts.actors[stay.actor_id].duplicate()
				facts.actors[stay.actor_id].location = {"kind":"outside"}
			var quote: Dictionary = simulation.services.waiting._seat_quote(WorldState.new(facts),visit,facility_id)
			if quote.ok and (best.is_empty() or int(quote.travel_ticks)<int(best.travel_ticks)):
				best = quote
				best.visit_id = visit_id
				best.facility_id = facility_id
				break
		if not best.is_empty(): break
	if best.is_empty(): errors.append("No compatible actual manual chair target"); return
	metadata.manual_command = {"id":"public-contention-manual-seat","hospital_id":world.hospital_id,"kind":"waiting_select_seat","typed_payload":{"visit_id":best.visit_id,"facility_id":best.facility_id},"expected_revision":world.revision,"loading_session_id":"public-contention"}
	metadata.manual_quote = best
	metadata.manual_command_step = 1

func _place_approach(simulation: HospitalSimulation, actor_id: String, facility_id: String) -> Dictionary:
	var world: WorldState = simulation.world
	var space: HospitalSpace = simulation.space
	var actor: Dictionary = world.facts.actors[actor_id]
	var original: Dictionary = actor.location.duplicate(true)
	var area: Dictionary = space.public_areas.for_facility(world,facility_id)
	var layout: Dictionary = space.facility_layout(world,facility_id)
	var points: Array = []
	for plot: Array in HospitalSpace.floor_plots(world,int(layout.floor_id)):
		for y: int in range(int(plot[1])*32,(int(plot[1])+1)*32):
			for x: int in range(int(plot[0])*32,(int(plot[0])+1)*32):
				if space.public_areas.region(world,area).cells.has(Vector2i(x,y)): continue
				points.append(Vector2i(x,y))
	var target: Vector2i = Vector2i(int(layout.patient_cell[0]),int(layout.patient_cell[1]))
	points.sort_custom(func(a: Vector2i,b: Vector2i)->bool:
		var da: int = absi(a.x-target.x)+absi(a.y-target.y)
		var db: int = absi(b.x-target.x)+absi(b.y-target.y)
		return da<db if da!=db else a.y<b.y or a.y==b.y and a.x<b.x)
	for point: Vector2i in points:
		if not space.public_areas.safe_wait(world,actor_id,int(layout.floor_id),[point.x,point.y]): continue
		actor.location = {"kind":"floor","floor_id":int(layout.floor_id),"cell":[point.x,point.y],"height_m":0.0}
		space.sync_actor(world,actor_id)
		var quote: Dictionary = space.facility_trip_quote(world,facility_id,actor_id)
		if quote.ok and int(quote.travel_ticks)<=150: return quote
		actor.location = original
		space.sync_actor(world,actor_id)
	return {}
