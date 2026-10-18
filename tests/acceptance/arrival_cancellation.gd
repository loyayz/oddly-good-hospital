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

class QueueClinic extends HospitalClinic:
	var cancellation: ArrivalPreparation.Cancellation
	var old_bindings: Dictionary = {}
	var old_quotes: int = 0
	var stop_after_reference: bool = true
	func reference_demand(world: WorldState, binding_id: String, complex_case: bool = false, shift: int = 0, query: Variant = null) -> Dictionary:
		var result: Dictionary = super.reference_demand(world,binding_id,complex_case,shift,query)
		if old_bindings.has(binding_id):
			old_quotes += 1
			if stop_after_reference: cancellation.request()
		return result

class QueueArrival extends HospitalArrivalService:
	var cancellation: ArrivalPreparation.Cancellation
	var stop_after_ticket: bool = false
	var tickets: int = 0
	var solves: int = 0
	func _remaining_bundle(world: WorldState, visit: Dictionary, source: Dictionary) -> Dictionary:
		var result: Dictionary = super._remaining_bundle(world,visit,source)
		tickets += 1
		if stop_after_ticket: cancellation.request()
		return result
	func _solve_roles(world: WorldState, classes: Array, budgets: Dictionary, shift: int, model_key: Variant = null, locked_roles: Dictionary = {}) -> Dictionary:
		solves += 1
		return super._solve_roles(world,classes,budgets,shift,model_key,locked_roles)

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
	var cancellation_metrics: Dictionary = preparation.metrics()
	var measured: bool = cancellation_metrics.jobs==1 and cancellation_metrics.get("cancelled_jobs",0)==1 and int(cancellation_metrics.get("cancel_response_us",0))>0 and int(cancellation_metrics.get("dispose_wait_us",0))>=int(cancellation_metrics.get("cancel_response_us",0)) and int(cancellation_metrics.worker_wall_us)>=int(cancellation_metrics.get("cancel_response_us",0))
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
	var old_queue: Dictionary = _old_queue_cancellation()
	for simulation: HospitalSimulation in _simulations: simulation.dispose()
	_simulations.clear()
	t.check("GROW-77",started==OK and stopped and measured and sealed_preserved and release_preserved and complete_entries and reusable and shift_boundary and unpublished and old_queue.passed and ctx.world.freeze()==before,{"started":started,"reached_case_boundary":reached,"cases_before_stop":1 if stopped else worker.cases,"cancellation_metrics":cancellation_metrics,"cancellation_measured":measured,"sealed_preserved":sealed_preserved,"release_preserved":release_preserved,"complete_cache_entries":complete_entries,"reuse_matches_cold":reusable,"native_shift_boundary":shift_boundary,"cancelled_result_unpublished":unpublished,"old_queue":old_queue,"readonly":ctx.world.freeze()==before})

func _old_queue_cancellation() -> Dictionary:
	var ctx: Dictionary = _context()
	_single_case(ctx)
	var first: Dictionary = _patient(ctx,[45,76],"B_S13_D09_M09")
	_single_case(ctx,"D37")
	var second: Dictionary = _patient(ctx,[47,76],"B_S49_D37_M37")
	# Both real reception tickets remain, but neither binding is in the new pool.
	_single_case(ctx,"D14")
	var validation: String = ctx.world.validate(_content)
	if first.is_empty() or second.is_empty() or not validation.is_empty():
		return {"passed":false,"validation":validation,"admission":ctx.get("last_admission",{}),"fixture_errors":_fixture_errors}
	var before: Dictionary = ctx.world.freeze()
	var worker: QueueArrival = QueueArrival.new(_content,HospitalSpace.new(_content))
	var observer: QueueClinic = QueueClinic.new(_content,worker.space)
	worker.clinic = observer
	_configure(worker)
	worker.cancellation = ArrivalPreparation.Cancellation.new()
	observer.cancellation = worker.cancellation
	observer.old_bindings = {first.binding_id:true,second.binding_id:true}
	var cancelled: Dictionary = worker.capacity(ctx.world,true,worker.cancellation.requested)
	var reference_boundary: bool = cancelled.get("cancelled",false) and not cancelled.has("capacity") and not cancelled.has("shift_capacities") and observer.old_quotes==1 and worker.tickets==0 and worker.solves==0 and worker.space._route_queries.is_empty()
	observer.stop_after_reference = false
	worker.cancellation = ArrivalPreparation.Cancellation.new()
	observer.cancellation = worker.cancellation
	worker.stop_after_ticket = true
	var query: Dictionary = {}
	var partial: Dictionary = worker._existing_workload(ctx.world,0,query,{},worker.cancellation.requested)
	var ticket_boundary: bool = query.get("cancelled",false) and partial.is_empty() and worker.tickets==1 and worker.solves==0 and worker.space._route_queries.is_empty()
	worker.stop_after_ticket = false
	var full_work: Dictionary = worker._existing_workload(ctx.world,0)
	var resumed: Dictionary = worker.capacity(ctx.world,true)
	var fresh: HospitalArrivalService = HospitalArrivalService.new(_content,HospitalSpace.new(_content))
	_configure(fresh)
	var cold_work: Dictionary = fresh._existing_workload(ctx.world,0)
	var independent: Dictionary = fresh.capacity(ctx.world,true)
	var reused: bool = not full_work.is_empty() and full_work==cold_work and resumed.get("complete",false) and resumed==independent and worker.space._route_queries.is_empty()
	worker.dispose()
	fresh.dispose()
	var readonly: bool = ctx.world.freeze()==before
	return {"passed":reference_boundary and ticket_boundary and reused and readonly,"reference_boundary":reference_boundary,"ticket_boundary":ticket_boundary,"resume_matches_cold":reused,"readonly":readonly,"validation":validation}
