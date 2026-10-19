class_name BuildPreview
extends RefCounted

# One window-owned preview. Neither requests nor results enter WorldState.
var service: BuildService
var generation: int = 0
var pending: Dictionary = {}
var current: Dictionary = {}
var result: Dictionary = {}
var job: BuildPreviewJob
var restarted_jobs: int = 0
var superseded_jobs: int = 0
var work_budget: ViewWorkBudget
var _completed_boundary: Array = []
var _safety_navigation: NavigationCache = NavigationCache.new()
var _previous_navigation: NavigationCache = NavigationCache.new()

func _init(building: BuildService) -> void:
	service = building

func request(draft: Dictionary, binding: Dictionary) -> int:
	var semantic: Dictionary = {"draft":draft.duplicate(true),"binding":_semantic_binding(binding)}
	var previous: Dictionary = pending if not pending.is_empty() else current
	if not previous.is_empty() and previous.semantic==semantic:
		previous.binding = binding.duplicate(true)
		if not result.is_empty():
			result.binding = binding.duplicate(true)
		return generation
	generation += 1
	if job!=null and not job.complete:
		superseded_jobs += 1
	job = null
	_completed_boundary = []
	pending = {"generation":generation,"semantic":semantic,"binding":binding.duplicate(true)}
	result = {"ok":false,"ready":false,"reason":"正在检查当前草案","generation":generation,"binding":binding.duplicate(true)}
	return generation

func update(world: WorldState, maximum_units: int = 0, completed_boundary: Array = []) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var budget_usec: int = maxi(1,int(float(service.content.balance.spatial_view.view_build_budget_ms_per_frame)*1000.0)) if work_budget==null else work_budget.remaining_usec()
	var value: Dictionary = _update(world,maximum_units,budget_usec,completed_boundary)
	if work_budget!=null: work_budget.spend(Time.get_ticks_usec()-started)
	return value

func _update(world: WorldState, maximum_units: int, budget_usec: int, completed_boundary: Array) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	if not pending.is_empty():
		current = pending
		pending = {}
		job = null
	if current.is_empty():
		return {"ok":false,"ready":false,"reason":"没有当前草案"}
	if str(current.binding.get("hospital_id",world.hospital_id))!=world.hospital_id:
		result = {"ok":false,"ready":false,"reason":"草案属于另一座医院","generation":generation}
		return result.duplicate(true)
	if job==null:
		job = BuildPreviewJob.new(service,world,current.semantic.draft,{},_safety_navigation,_previous_navigation)
	elif completed_boundary.is_empty() or _completed_boundary!=completed_boundary:
		# Only the window may identify an already completed, immutable-between-
		# ticks UI boundary. Public queries without that guarantee still compare
		# all actual facts, including reservations written without world.touch().
		var basis: Dictionary = job.dependency_basis(world)
		if job.dependencies(world,basis)!=job.dependency_key:
			restarted_jobs += 1
			var previous: BuildPreviewJob = job
			job = BuildPreviewJob.new(service,world,current.semantic.draft,basis,_safety_navigation,_previous_navigation)
			job.inherit_completed_shape(previous)
			result = {"ok":false,"ready":false,"reason":"相关占地或安全事实已变化，正在重新检查"}
	_completed_boundary = completed_boundary.duplicate()
	var remaining: int = budget_usec-(Time.get_ticks_usec()-started)
	if budget_usec>0 and remaining<0: job.atomic_overruns += 1
	if remaining>0: job.advance(world,remaining,maximum_units)
	elif budget_usec>0 and completed_boundary.is_empty():
		# A public query without a stable boundary must compare live facts on
		# every call. If that indivisible comparison consumes its budget, allow
		# one safe unit and report the overrun rather than starve indefinitely.
		job.advance(world,0,1)
	result = job.result.duplicate()
	result.generation = generation
	result.binding = current.binding.duplicate(true)
	result.atomic_overruns = job.atomic_overruns
	result.units_checked = job.units_checked
	if job.complete and result.ok:
		result.world_revision = world.revision
		result.balance_after = HospitalLedger.balance(world)-int(result.price)+int(result.refund)
	var target_floor: int = int(current.semantic.draft.get("floor_id",1))
	result.draw_on_current_floor = int(current.binding.get("view_floor_id",target_floor))==target_floor
	return result.duplicate(true)

func rebind(binding: Dictionary) -> void:
	if current.is_empty():
		return
	if _semantic_binding(binding)!=current.semantic.binding:
		request(current.semantic.draft,binding)
		return
	current.binding = binding.duplicate(true)
	result.binding = binding.duplicate(true)
	result.draw_on_current_floor = int(binding.get("view_floor_id",1))==int(current.semantic.draft.get("floor_id",1))

func cancel() -> void:
	generation += 1
	pending = {}
	current = {}
	result = {}
	job = null
	_completed_boundary = []
	_safety_navigation = NavigationCache.new()
	_previous_navigation = NavigationCache.new()

func _semantic_binding(binding: Dictionary) -> Dictionary:
	var result_binding: Dictionary = binding.duplicate(true)
	for field: String in ["view_id","view_generation","view_floor_id","pointer_pixels","world_revision"]:
		result_binding.erase(field)
	return result_binding
