extends SceneTree

const Fixture = preload("res://tools/performance/fixture.gd")
var _output: String
var _started: int
var _errors: Array = []
var _placements: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _place(world: WorldState, space: HospitalSpace, actor_id: String, floor_id: int, target: Array) -> bool:
	var actor: Dictionary = world.facts.actors[actor_id]
	var original: Dictionary = actor.location.duplicate(true)
	for offset: Array in [[0,0],[2,0],[-2,0],[0,2],[0,-2],[4,0],[-4,0],[0,4],[0,-4]]:
		var cell: Array = [float(target[0])+int(offset[0]),float(target[1])+int(offset[1])]
		actor.location = {"kind":"floor","floor_id":floor_id,"cell":cell,"height_m":0.0}
		var reason: String = space.static_reason(world,actor,floor_id,Vector2i(roundi(cell[0]),roundi(cell[1])))
		if reason.is_empty() and space._dynamic_clear(world,actor_id,floor_id,space.body_rectangle(actor)):
			space.sync_actor(world,actor_id)
			_placements[actor_id] = {"original_initial":original,"declared_initial":actor.location.duplicate(true),"preferred_service_cell":target.duplicate()}
			return true
	actor.location = original
	space.sync_actor(world,actor_id)
	_errors.append({"initial_placement_failed":actor_id,"target":target,"floor":floor_id})
	return false

func _run() -> void:
	var source: String
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--source="): source = argument.trim_prefix("--source=")
		if argument.begins_with("--output-dir="): _output = argument.trim_prefix("--output-dir=")
	_started = Time.get_ticks_usec()
	if _output.is_empty() or not FileAccess.file_exists(source):
		push_error("Expected existing --source and --output-dir for a new representative160 input.")
		quit(2)
		return
	if FileAccess.file_exists(_output.path_join("clinical-fresh-initial.input.bin")) or FileAccess.file_exists(_output.path_join("clinical-fresh-preparation.json")):
		push_error("Representative preparation outputs already exist; choose a new output directory.")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))!=OK:
		quit(2)
		return
	var content: HospitalContent = HospitalContent.new()
	var source_fixture: RefCounted = Fixture.new(content,160,"four_floors",source)
	if not source_fixture.errors.is_empty() or source_fixture.world.facts.get("arrivals",{}).get("plan",{}).is_empty() or int(source_fixture.world.facts.arrivals.plan.get("day_index",-1))!=1:
		push_error("Source must contain the compatible original frozen day1 plan; no capacity recomputation is allowed here.")
		quit(2)
		return
	var fixture: RefCounted = Fixture.new(content,160,"four_floors")
	var world: WorldState = fixture.world
	# Only fresh unowned constructor placeholders are replaced, exactly as in
	# acceptance/fixtures/prepare_inputs.gd. No existing visit/relative is moved.
	for actor_id: String in fixture.visitor_ids:
		if not actor_id.begins_with("bench_visitor_") or world.facts.moves.has(actor_id): _errors.append("Unexpected owned initial visitor")
		world.facts.actors.erase(actor_id)
	fixture.visitor_ids.clear()
	var simulation: HospitalSimulation = HospitalSimulation.new(world,content)
	var space: HospitalSpace = simulation.space
	# The original day plan is a frozen business fact. Nominal capacity starts
	# reference staff at the entrance; initial real staff positions are excluded
	# from _reference_basis. Compare every original basis field before reuse.
	world.facts.arrivals.plan = source_fixture.world.facts.arrivals.plan.duplicate(true)
	for id: String in source_fixture.world.facts.facilities:
		if not id.begins_with("acceptance_public_seat_"): continue
		var original: Dictionary = source_fixture.world.facts.facilities[id]
		HospitalFactory._add_facility(world,{"id":id,"definition_id":original.definition_id,"anchor":original.cell.duplicate(),"size":original.footprint.duplicate(),"room_id":null},content)
		var positioned: Dictionary = simulation.services.building._facility_position(world,world.facts.facilities[id],[id])
		if not positioned.ok: _errors.append({"seat":id,"reason":positioned})
	var basis_difference: Array = []
	var basis_hashes: Array = []
	for shift: int in 3:
		var basis_before: Dictionary = simulation.services.arrivals._reference_basis(source_fixture.world,shift)
		var basis_after: Dictionary = simulation.services.arrivals._reference_basis(world,shift)
		for field: String in basis_before:
			if basis_before[field]!=basis_after.get(field): basis_difference.append("shift_%d.%s"%[shift,field])
		basis_before.erase("clinic")
		basis_hashes.append(JSON.stringify(basis_before).sha256_text())
	if not basis_difference.is_empty(): _errors.append({"capacity_basis_difference":basis_difference})
	for index: int in 32:
		var actor_id: String = "bench_staff_%04d"%index
		var floor_id: int = index%4+1
		var slot: int = index/4
		if slot==7: continue
		var facility_id: String
		var operator: int = 0
		if slot==0: facility_id = "bench_room_%d_00_0"%floor_id
		elif slot==1: facility_id = "bench_room_%d_01_0"%floor_id
		elif slot in [2,3,4]:
			facility_id = "bench_room_%d_02_0"%floor_id
			operator = slot-2
		elif slot==5: facility_id = "bench_room_%d_03_0"%floor_id
		else: facility_id = "bench_room_%d_14_reception"%floor_id
		var layout: Dictionary = space.facility_layout(world,facility_id)
		if layout.is_empty() or layout.operator_cells.size()<=operator:
			_errors.append({"initial_service_layout_missing":facility_id,"operator":operator})
			continue
		_place(world,space,actor_id,floor_id,layout.operator_cells[operator])
	var first_reception: Dictionary = space.facility_layout(world,"bench_room_1_14_reception")
	_place(world,space,"bench_patient_0000",1,first_reception.patient_cell)
	var construction_facts: Dictionary = {"sessions":world.facts.sessions.size(),"tickets":world.facts.tickets.size(),"preparations":world.facts.preparations.size(),"attempts":world.facts.attempts.size(),"moves":world.facts.moves.size(),"tick":world.sim_tick}
	if construction_facts!={"sessions":0,"tickets":0,"preparations":0,"attempts":0,"moves":0,"tick":0}: _errors.append({"not_fresh_initial_input":construction_facts})
	var visit_ids: Array = world.active_visit_ids()
	for visit_id: String in visit_ids: world.facts.visits[visit_id].companion_intent = false
	for index: int in 8:
		var visit: Dictionary = world.facts.visits[visit_ids[index]]
		visit.companion_intent = true
		simulation.clinic.visitors._request(world,visit,"companion","")
	world.touch()
	var command: GameCommand = GameCommand.from_record({"id":"fresh-initial-close","hospital_id":world.hospital_id,"kind":"arrivals_intake","typed_payload":{"open":false}})
	if not simulation.apply(command).accepted: _errors.append("Intake-close command rejected")
	var preparation_steps: int = 0
	while _errors.is_empty() and world.facts.visitors.stays.size()<8 and preparation_steps<80 and Time.get_ticks_usec()-_started<60000000:
		var ids: Array = world.facts.visitors.requests.keys()
		ids.sort()
		if not ids.is_empty():
			var request: Dictionary = world.facts.visitors.requests[ids[0]]
			if simulation.clinic.visitors._admit(world,world.facts.visits[request.visit_id],request): world.facts.visitors.requests.erase(ids[0])
		if world.facts.visitors.stays.size()==8: break
		var result: TickResult = simulation.step_nonblocking()
		while result==null and simulation.preparing_error().is_empty() and Time.get_ticks_usec()-_started<60000000:
			await process_frame
			result = simulation.step_nonblocking()
		if result==null: _errors.append("Fresh preparation step incomplete"); break
		preparation_steps += 1
	for stay: Dictionary in world.facts.visitors.stays.values(): fixture.visitor_ids.append(str(stay.actor_id))
	command = GameCommand.from_record({"id":"fresh-initial-open","hospital_id":world.hospital_id,"kind":"arrivals_intake","typed_payload":{"open":true}})
	if not simulation.apply(command).accepted: _errors.append("Intake-open command rejected")
	var validation: String = world.validate(content)
	if not validation.is_empty(): _errors.append(validation)
	if world.present_actor_count()!=160 or fixture.visitor_ids.size()!=8 or world.facts.staff.size()!=32 or world.active_visit_ids().size()!=120: _errors.append("Fresh original admissions did not produce the complete160 workload")
	var path: String = _output.path_join("clinical-fresh-initial.input.bin")
	if FileAccess.file_exists(path): _errors.append("Immutable fresh input already exists")
	if _errors.is_empty(): fixture.store_input(path)
	var report: Dictionary = {"ok":_errors.is_empty(),"errors":_errors,"source_plan_input":source,"source_plan_sha256":FileAccess.get_sha256(source),"engine":Engine.get_version_info().string,"content_fingerprint":content.content_fingerprint,"frozen_plan_sha256":JSON.stringify(world.facts.arrivals.plan).sha256_text(),"frozen_plan_basis_equal":basis_difference.is_empty(),"basis_shift_hashes":basis_hashes,"basis_difference":basis_difference,"initial_construction":construction_facts,"initial_placements":_placements,"preparation_steps":preparation_steps,"tick":world.sim_tick,"present":world.present_actor_count(),"rooms":world.facts.rooms.size(),"facilities":world.facts.facilities.size(),"visitors":fixture.visitor_ids.size(),"pending_requests":world.facts.visitors.requests.size(),"validation":validation,"elapsed_us":Time.get_ticks_usec()-_started,"input":path,"input_sha256":FileAccess.get_sha256(path) if _errors.is_empty() else ""}
	var sink: FileAccess = FileAccess.open(_output.path_join("clinical-fresh-preparation.json"),FileAccess.WRITE)
	sink.store_string(JSON.stringify(report,"\t"))
	sink.close()
	print("CLINICAL_FRESH="+JSON.stringify(report))
	simulation.dispose()
	quit(0 if _errors.is_empty() else 1)
