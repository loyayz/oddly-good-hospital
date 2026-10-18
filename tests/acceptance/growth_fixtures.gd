extends RefCounted

const CheckpointIdentity = preload("res://tests/acceptance/checkpoint_identity.gd")

var _cache: RefCounted

const F = preload("res://game/arrivals/exact_fraction.gd")
const DayPlan = preload("res://game/arrivals/day_plan.gd")

# This observer counts real production queries without substituting a result.
class AdmissionObserver extends HospitalClinic:
	var readiness_queries: int = 0
	func arrival_readiness(world: WorldState, binding_id: String, complex_case: bool = false, explain: bool = true) -> Dictionary:
		readiness_queries += 1
		return super.arrival_readiness(world,binding_id,complex_case,explain)

var _content: HospitalContent
var _simulations: Array[HospitalSimulation] = []
var _opened_snapshot: Dictionary = {}
var _fixture_errors: Array = []

func _checkpoint_dependencies(key: String) -> Dictionary:
	return CheckpointIdentity.describe("res://tests/acceptance/growth_fixtures.gd",{"research_opened":{"methods":["_prepare_opened_snapshot"]}},key)

func _context(preset: bool = true, opened: bool = false) -> Dictionary:
	if opened and _opened_snapshot.is_empty(): _prepare_opened_snapshot()
	var world: WorldState = WorldState.new(_opened_snapshot.duplicate(true)) if opened and not _opened_snapshot.is_empty() else HospitalFactory.create(HospitalSnapshots.uuid(),"来客与研究专项医院",preset,_content)
	var simulation: HospitalSimulation = HospitalSimulation.new(world,_content)
	_simulations.append(simulation)
	var arrivals: HospitalArrivalService = simulation.services.arrivals
	arrivals.execute(world,"tutorial_set_enabled",{"enabled":false})
	# Non-capacity cases start inside an already frozen day. Manual patients and
	# actual research/clinical work must not trigger an unrelated whole-case solver.
	world.facts.arrivals.plan = _plan(world,0,[0,0,0],[F.make(),F.make(),F.make()])
	arrivals.execute(world,"arrivals_intake",{"open":false})
	return {"world":world,"simulation":simulation,"space":simulation.space,"clinic":simulation.clinic,
		"arrivals":arrivals,"research":simulation.services.research,"development":simulation.services.development}

func _single_case(ctx: Dictionary, disease_id: String = "D09") -> void:
	for disease: Dictionary in _content.catalog.diseases:
		ctx.arrivals.execute(ctx.world,"arrivals_weight",{"disease_id":disease.id,"weight":1 if disease.id==disease_id else 0})
	ctx.arrivals.execute(ctx.world,"arrivals_intake",{"open":true})

func _plan(world: WorldState, count: int, counts: Array, capacities: Array = []) -> Dictionary:
	return {"day_index":world.sim_tick/18000+1,"preset":"normal","scale_numerator":3,
		"shift_capacities":capacities if not capacities.is_empty() else [F.make(1),F.make(),F.make()],
		"opportunity_count":count,"shift_opportunity_counts":counts.duplicate(),"schedule_seed":"321" if count>0 else null,
		"schedule_algorithm":"arrival-load-slot-v1","next_slot_index":0,"held_capacity_fraction":F.make(),"held_scale_numerator":0}

func _slot_ticks(plan: Dictionary) -> Array:
	var result: Array = []
	for index: int in int(plan.opportunity_count):
		result.append(DayPlan.slot_tick(plan,index))
	return result

func _add_room(world: WorldState, id: String, kind: String, origin: Array, size: Array) -> void:
	HospitalFactory._add_room(world,{"id":id,"type":kind,"anchor":origin,"size":size,"door":{"offset":1,"definition_id":"DR04"}},_content)
	world.touch()

func _add_facility(world: WorldState, id: String, definition_id: String, room_id: Variant, cell: Array) -> void:
	var definition: Dictionary = _content.facility_definition(definition_id)
	HospitalFactory._add_facility(world,{"id":id,"definition_id":definition_id,"room_id":room_id,"anchor":cell,"size":definition.footprint.duplicate()},_content)
	world.touch()

func _fresh_space(ctx: Dictionary) -> void:
	var geometry: HospitalSpace = HospitalSpace.new(_content)
	ctx.space = geometry
	ctx.clinic.space = geometry
	ctx.arrivals.space = geometry
	ctx.arrivals.clinic.space = geometry
	ctx.research.space = geometry
	ctx.development.space = geometry

func _observer(ctx: Dictionary) -> AdmissionObserver:
	var observer: AdmissionObserver = AdmissionObserver.new(_content,ctx.space)
	ctx.arrivals.clinic = observer
	return observer

func _sum(values: Array) -> Dictionary:
	var result: Dictionary = F.make()
	for value: Dictionary in values:
		result = F.add(result,value)
	return result

# Fixture setup uses production admission and queue creation. The chosen cell is
# the initial position of this focused saved-world input, not a movement result.
func _patient(ctx: Dictionary, cell: Array, binding: String = "B_S49_D37_M37", personality: String = "PP01", resident: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = {"arrival_key":ctx.world.new_id("acceptance_arrival"),"binding_id":binding,"personality_id":personality,"complex":false}
	if not resident.is_empty():
		payload.resident_id = resident.id
		payload.name = resident.name
		payload.personality_id = resident.personality_id
	var result: CommandResult = ctx.clinic.execute(ctx.world,"clinical_arrive",payload)
	ctx.last_admission = result.to_record()
	if not result.accepted:
		_fixture_errors.append({"code":result.code,"reason":result.reason,"binding":binding})
		return {}
	var visit: Dictionary = ctx.world.facts.visits[result.changed_ids[0]]
	ctx.world.facts.actors[visit.actor_id].location.cell = cell.duplicate()
	if not resident.is_empty():
		ctx.world.facts.actors[visit.actor_id].appearance = resident.appearance.duplicate(true)
		resident.current_actor_id = visit.actor_id
		ctx.world.facts.residents[resident.id] = resident
	ctx.world.touch()
	ctx.space.sync_actor(ctx.world,visit.actor_id)
	ctx.clinic._queue(ctx.world,visit,"reception")
	var ticket: Dictionary = ctx.world.facts.tickets[visit.ticket_id]
	ticket.waited_ticks = 0
	ticket.wait_accounted_tick = ctx.world.sim_tick
	return visit

func _wait_ctx(personality: String = "PP01") -> Dictionary:
	var ctx: Dictionary = _context()
	ctx.visit = _patient(ctx,[45,76],"B_S49_D37_M37",personality)
	ctx.ticket = ctx.world.facts.tickets.get(ctx.visit.get("ticket_id",""),{})
	_seed_survival(ctx.world)
	return ctx

func _seed_survival(world: WorldState) -> void:
	for seed: int in range(1,65):
		var generator: RandomNumberGenerator = RandomNumberGenerator.new()
		generator.seed = seed
		var initial: String = str(generator.state)
		if generator.randi_range(0,9999)>=3500 and generator.randi_range(0,9999)>=3500:
			world.facts.rng.patience.seed_decimal = str(seed)
			world.facts.rng.patience.state_decimal = initial
			return

func _patience_events(service: HospitalArrivalService) -> int:
	var count: int = 0
	for event: SimEvent in service.take_events():
		if event.kind=="patience_evaluated":
			count += 1
	return count

func _resident(ctx: Dictionary, cell: Array) -> Dictionary:
	var resident: Dictionary = ctx.arrivals._new_identity(ctx.world,"S49")
	resident.remembered = true
	var visit: Dictionary = _patient(ctx,cell,"B_S49_D37_M37","PP01",resident)
	return {"resident":resident,"visit":visit}

func _actual_departure(ctx: Dictionary, visit: Dictionary) -> bool:
	if not ctx.clinic.depart_visit(ctx.world,visit.id,"referred"):
		return false
	for index: int in 600:
		ctx.clinic.dispatch(ctx.world)
		ctx.space.advance(ctx.world)
		ctx.arrivals.settle(ctx.world)
		if visit.phase=="departed":
			return true
		ctx.world.facts.sim_tick += 1
		ctx.world.touch()
		ctx.space.finish_boundary(ctx.world)
	return false

func _return_hit(world: WorldState) -> void:
	for seed: int in range(1,65):
		var generator: RandomNumberGenerator = RandomNumberGenerator.new()
		generator.seed = seed
		var initial: String = str(generator.state)
		var value: int = generator.randi()
		if value<4294960000 and value%10000<2000:
			world.facts.rng.arrival.seed_decimal = str(seed)
			world.facts.rng.arrival.state_decimal = initial
			return

func mini_string(first: String, second: String) -> String:
	return first if first<second else second

func _prepare_opened_snapshot() -> void:
	if not _opened_snapshot.is_empty(): return
	var cached: Dictionary = _cache.read("research_opened")
	if not cached.is_empty():
		_opened_snapshot = cached.facts
		return
	var ctx: Dictionary = _context()
	# _context supplies the frozen current day; full steps here only need the
	# original manually admitted patient's real first GP, with no new arrivals.
	ctx.arrivals.execute(ctx.world,"arrivals_intake",{"open":false})
	var result: CommandResult = ctx.clinic.execute(ctx.world,"clinical_arrive",{"arrival_key":"research_opening_patient","binding_id":"B_S49_D37_M37","personality_id":"PP01"})
	if not result.accepted:
		_fixture_errors.append({"opening":result.reason})
		return
	for index: int in 1200:
		ctx.simulation.step()
		if index%100==99:
			print("GROWTH_OPENING_PROGRESS tick="+str(ctx.world.sim_tick)+" visits="+JSON.stringify(ctx.world.facts.visits))
		if ctx.research.opened(ctx.world):
			_opened_snapshot = ctx.world.freeze()
			if not _cache.publish("research_opened",{"facts":_opened_snapshot}):
				_fixture_errors.append({"checkpoint":"research_opened","reason":"Invalid generated state or cache write failed"})
			return
	_fixture_errors.append({"opening":"First actual GP did not finish within its necessary 120-second boundary"})

func _vector_plan(world: WorldState) -> Dictionary:
	return _plan(world,8,DayPlan.allocate_shifts(1,"321",8,[F.make(1),F.make(1),F.make(1)]),[F.make(3),F.make(3),F.make(3)])

func _research_context(desk: bool = true, worker: bool = true) -> Dictionary:
	var ctx: Dictionary = _context(true,true)
	if desk:
		_add_room(ctx.world,"research_room","research",[42,69],[6,6])
		_add_facility(ctx.world,"research_desk","FUR05","research_room",[43,70])
	if worker:
		HospitalFactory._add_staff(ctx.world,"research_worker","研究员","researcher",[45,70],_content)
		ctx.simulation.services.scheduler.ensure(ctx.world)
		ctx.simulation.services.recruitment.ensure(ctx.world)
	_fresh_space(ctx)
	return ctx

func _finish_opening_handoff(ctx: Dictionary) -> Dictionary:
	var opening: Dictionary = {}
	for visit: Dictionary in ctx.world.facts.visits.values():
		if visit.arrival_key=="research_opening_patient":
			opening = visit
			break
	if opening.is_empty():
		return {"cleared":false,"reason":"Actual first-GP visit is missing"}
	var referral: CommandResult = ctx.clinic.execute(ctx.world,"clinical_refer",{"visit_id":opening.id})
	var state: Dictionary = {"referral":referral.to_record(),"started_tick":ctx.world.sim_tick,"cleared":false}
	if referral.accepted:
		ctx.world.touch()
		# First GP opens research before its bodies and station have handed over.
		# Only the original patient's real exit and the GP's physical release are
		# needed before the next actual admission; no clinical facts are replaced.
		for index: int in 600:
			ctx.simulation.step()
			var gp_release: bool = false
			for staff: Dictionary in ctx.world.facts.staff.values():
				gp_release = gp_release or staff.get("clinical_release",{}).get("facility_id","")=="gp_station"
			if opening.phase=="departed" and ctx.world.facts.actors[opening.actor_id].location.kind=="outside" and not ctx.world.facts.adaptations.has("gp_station") and not gp_release:
				state.cleared = true
				break
	state.finished_tick = ctx.world.sim_tick
	state.visit_phase = opening.phase
	state.patient_location = ctx.world.facts.actors[opening.actor_id].location.duplicate(true)
	state.gp_adaptation = ctx.world.facts.adaptations.get("gp_station",{}).duplicate(true)
	state.gp_releases = {}
	for staff: Dictionary in ctx.world.facts.staff.values():
		if staff.get("clinical_release",{}).get("facility_id","")=="gp_station":
			state.gp_releases[staff.id] = {"release":staff.clinical_release.duplicate(true),"location":ctx.world.facts.actors[staff.id].location.duplicate(true),"move":ctx.world.facts.moves.get(staff.id,{}).duplicate(true)}
	return state

func _research_tick(ctx: Dictionary) -> void:
	ctx.research.boundaries(ctx.world)
	ctx.development.dispatch(ctx.world)
	ctx.space.advance(ctx.world)
	ctx.research.advance(ctx.world)
	ctx.research.settle(ctx.world)
	ctx.world.facts.sim_tick += 1
	ctx.world.touch()
	ctx.space.finish_boundary(ctx.world)

func _start(ctx: Dictionary, research_id: String = "R12", extra: Dictionary = {}) -> CommandResult:
	var payload: Dictionary = {"research_id":research_id}
	payload.merge(extra,true)
	return ctx.research.execute(ctx.world,"research_start",payload)

func _finish_research(ctx: Dictionary, research_id: String) -> bool:
	var job: Dictionary = ctx.research.active_job(ctx.world,research_id)
	if job.is_empty():
		return false
	# Only this original job's quoted work boundary is advanced.
	var limit: int = int(job.total_work_milli)/1000+300
	for index: int in limit:
		_research_tick(ctx)
		if HospitalResearch.terminal(job):
			return job.state=="completed"
	return false

func _material(ctx: Dictionary, research_id: String) -> void:
	ctx.research.execute(ctx.world,"research_request_mail",{"research_id":research_id})
	var due: int = int(ctx.world.facts.research_progress.mail.get(research_id,ctx.world.sim_tick))
	ctx.world.facts.sim_tick = due
	ctx.research.boundaries(ctx.world)
	ctx.research.settle(ctx.world)
