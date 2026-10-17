extends "res://tests/acceptance/growth_fixtures.gd"

# Pause only after a real complete clinical quote has returned. Disposal opens
# the gate through its cancellation request; no clinical or native call is killed.
class ReleaseOnCancel extends ArrivalPreparation.Cancellation:
	var gate: Semaphore
	func _init(release_gate: Semaphore) -> void:
		gate = release_gate
	func request() -> void:
		super.request()
		gate.post()

class BoundaryArrival extends HospitalArrivalService:
	var entered: Semaphore = Semaphore.new()
	var gate: Semaphore = Semaphore.new()
	var cases: int = 0
	var pause_first: bool = true
	func _reference_variant(world: WorldState, binding: Dictionary, complex_case: bool, shift: int, quote: Dictionary, query: Dictionary) -> Dictionary:
		var result: Dictionary = super._reference_variant(world,binding,complex_case,shift,quote,query)
		cases += 1
		if pause_first:
			pause_first = false
			entered.post()
			gate.wait()
		return result

class ShiftArrival extends HospitalArrivalService:
	var cancellation: ArrivalPreparation.Cancellation
	var shifts: int = 0
	func _solve_roles(world: WorldState, classes: Array, budgets: Dictionary, shift: int, model_key: Variant = null, locked_roles: Dictionary = {}) -> Dictionary:
		var result: Dictionary = super._solve_roles(world,classes,budgets,shift,model_key,locked_roles)
		shifts += 1
		if shifts==1: cancellation.request()
		return result

func _configure(service: HospitalArrivalService) -> void:
	service.clinic.scheduler = HospitalShiftScheduler.new(_content,service.space)
	service.clinic.recruitment = RecruitmentService.new(_content,service.space)
	service.clinic.departments = HospitalDepartments.new(_content,service.space)
	service.departments = service.clinic.departments

func run_case(t, database: HospitalContent) -> void:
	_content = database
	var ctx: Dictionary = _context()
	_single_case(ctx)
	var before: Dictionary = ctx.world.freeze()
	var preparation: ArrivalPreparation = ArrivalPreparation.new(_content)
	var input: Dictionary = preparation._capture(ctx.world,false,-1)
	var worker: BoundaryArrival = BoundaryArrival.new(_content,HospitalSpace.new(_content))
	_configure(worker)
	var cancellation: ReleaseOnCancel = ReleaseOnCancel.new(worker.gate)
	preparation._worker = worker
	preparation._active = input
	preparation._active_id = 1
	preparation._active_cancellation = cancellation
	preparation._sequence = 1
	preparation._thread = Thread.new()
	var started: Error = preparation._thread.start(preparation._compute.bind(input,cancellation))
	var reached: bool = false
	if started==OK:
		while preparation._thread.is_alive():
			if worker.entered.try_wait():
				reached = true
				break
			await t.process_frame
	else:
		preparation._thread = null
	# Coalescing and releasing a sealed consumer do not cancel its active job.
	preparation._sealed = input
	preparation._sealed_id = 1
	var changed: Dictionary = input.duplicate(true)
	changed.facts.plan_strategy = "safety_first"
	changed.layers.reference.plan_strategy = "safety_first"
	preparation._select_request(changed)
	var sealed_preserved: bool = preparation._sealed_id==1 and not cancellation.requested()
	preparation.release_sealed()
	var release_preserved: bool = not cancellation.requested() and preparation._latest_id==2
	preparation.dispose()
	var stopped: bool = reached and cancellation.requested() and worker.cases==1 and preparation._thread==null and preparation._worker==null and preparation._completed.is_empty() and preparation._sealed_result.is_empty()
	var retained: Dictionary = worker._reference_cache.get(0,{})
	var complete_entries: bool = retained.get("cases",{}).size()==1 and not retained.has("outputs") and worker.space._route_queries.is_empty()
	var hits: int = int(worker.reference_counts.case_hits)
	worker.pause_first = false
	var resumed: Dictionary = worker.capacity(WorldState.new(input.facts),false)
	var fresh: HospitalArrivalService = HospitalArrivalService.new(_content,HospitalSpace.new(_content))
	_configure(fresh)
	var independent: Dictionary = fresh.capacity(WorldState.new(input.facts),false)
	var reusable: bool = resumed.get("complete",false) and resumed==independent and int(worker.reference_counts.case_hits)>hits and worker.space._route_queries.is_empty()
	var shift_worker: ShiftArrival = ShiftArrival.new(_content,HospitalSpace.new(_content))
	_configure(shift_worker)
	shift_worker.cancellation = ArrivalPreparation.Cancellation.new()
	var shift_cancelled: Dictionary = shift_worker.capacity(WorldState.new(input.facts),false,shift_worker.cancellation.requested)
	var shift_boundary: bool = shift_cancelled.get("cancelled",false) and not shift_cancelled.has("shift_capacities") and shift_worker.shifts==1 and shift_worker.space._route_queries.is_empty()
	var shift_resumed: Dictionary = shift_worker.capacity(WorldState.new(input.facts),false)
	shift_boundary = shift_boundary and shift_resumed==independent
	# A cancelled worker result is not a failure projection and cannot replace
	# an already completed or sealed result, even when collected through poll.
	var collected: ArrivalPreparation = ArrivalPreparation.new(_content)
	collected._completed = {"input":input,"projection":{"complete":true,"marker":"retained"}}
	collected._completed_id = 7
	collected._sealed = input
	collected._sealed_id = 7
	collected._sealed_result = collected._completed.projection
	collected._active = changed
	collected._active_id = 8
	collected._thread = Thread.new()
	var collecting: Error = collected._thread.start(func() -> Dictionary:
		return {"projection":{"complete":false,"cancelled":true},"elapsed_us":0})
	if collecting==OK:
		while collected._thread.is_alive(): await t.process_frame
		collected.poll(false)
	else:
		collected._thread = null
	var unpublished: bool = collecting==OK and collected._completed_id==7 and collected._completed.projection.get("marker")=="retained" and collected._sealed_result.get("marker")=="retained"
	collected.dispose()
	worker.dispose()
	fresh.dispose()
	shift_worker.dispose()
	for simulation: HospitalSimulation in _simulations: simulation.dispose()
	_simulations.clear()
	t.check("GROW-77",started==OK and stopped and sealed_preserved and release_preserved and complete_entries and reusable and shift_boundary and unpublished and ctx.world.freeze()==before,{"started":started,"reached_case_boundary":reached,"cases_before_stop":1 if stopped else worker.cases,"sealed_preserved":sealed_preserved,"release_preserved":release_preserved,"complete_cache_entries":complete_entries,"reuse_matches_cold":reusable,"native_shift_boundary":shift_boundary,"cancelled_result_unpublished":unpublished,"readonly":ctx.world.freeze()==before})
